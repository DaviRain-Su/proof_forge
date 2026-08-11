import { useCallback, useEffect, useMemo, useState, type FC } from "react";
import {
  createPublicClient,
  createWalletClient,
  custom,
  decodeFunctionResult,
  encodeDeployData,
  encodeFunctionData,
  http,
  type Abi,
  type Address,
  type Hex,
  type PublicClient,
  type WalletClient,
} from "viem";
import {
  CHAIN_PRESETS,
  envAddress,
  envChainId,
  envChainPreset,
  envRpc,
  loadDefaultAbi,
  loadBytecode,
  loadDeployment,
  walletAddEthereumChainParams,
  type ChainPreset,
} from "./config";
import { parseAmount, principalWords } from "./principal";
import type { DeploymentFile } from "./types";

type LogLine = { at: string; text: string; kind?: "ok" | "bad" | "info" };

export const RegistryPanel: FC = () => {
  const [deployment, setDeployment] = useState<DeploymentFile | null>(null);
  const [abi, setAbi] = useState<Abi | null>(null);
  const [preset, setPreset] = useState<ChainPreset>(envChainPreset());
  const [rpcUrl, setRpcUrl] = useState(envRpc());
  const [chainId, setChainId] = useState(envChainId());
  const [address, setAddress] = useState<Address | null>(envAddress());
  const [addressInput, setAddressInput] = useState(envAddress() ?? "");
  const [account, setAccount] = useState<Address | null>(null);
  const [bytecodeHex, setBytecodeHex] = useState<Hex | null>(null);
  const [issued, setIssued] = useState<string | null>(null);
  const [policy, setPolicy] = useState<string | null>(null);
  const [queryAddr, setQueryAddr] = useState("");
  const [queryResult, setQueryResult] = useState<string | null>(null);
  const [issueTo, setIssueTo] = useState("");
  const [issueAmount, setIssueAmount] = useState("100000");
  const [allowAddr, setAllowAddr] = useState("");
  const [allowFlag, setAllowFlag] = useState("1");
  const [transferTo, setTransferTo] = useState("");
  const [transferAmount, setTransferAmount] = useState("40000");
  const [ctorSupply, setCtorSupply] = useState("1000000");
  const [ctorPerTx, setCtorPerTx] = useState("50000");
  const [ctorWindow, setCtorWindow] = useState("100000");
  const [busy, setBusy] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);

  const pushLog = useCallback((text: string, kind: LogLine["kind"] = "info") => {
    const at = new Date().toISOString().slice(11, 19);
    setLogs((prev) => [{ at, text, kind }, ...prev].slice(0, 60));
  }, []);

  const publicClient: PublicClient = useMemo(
    () =>
      createPublicClient({
        chain: { id: chainId, name: preset.name, nativeCurrency: preset.nativeCurrency, rpcUrls: { default: { http: [rpcUrl] } } },
        transport: http(rpcUrl),
      }),
    [rpcUrl, chainId, preset],
  );

  useEffect(() => {
    void (async () => {
      const dep = await loadDeployment();
      if (dep) {
        setDeployment(dep);
        setAbi(dep.abi);
        setRpcUrl(dep.rpcUrl);
        setChainId(dep.chainId);
        setAddress(dep.contractAddress);
        setAddressInput(dep.contractAddress);
        setCtorSupply(dep.ctor.supply);
        setCtorPerTx(dep.ctor.perTx);
        setCtorWindow(dep.ctor.windowCap);
        if (dep.bytecode) setBytecodeHex(dep.bytecode);
        pushLog(`deployment.json: ${dep.program} @ ${dep.contractAddress}`, "ok");
        return;
      }
      try {
        setAbi(await loadDefaultAbi());
      } catch (e) {
        pushLog(`ABI load failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
      }
      const bin = await loadBytecode();
      if (bin) setBytecodeHex(bin);
    })();
  }, [pushLog]);

  const readView = useCallback(
    async (fn: "issuedTotal" | "policy" | "balanceOf" | "isAllowed", args: bigint[] = []) => {
      if (!abi || !address) throw new Error("no ABI / contract address");
      const data = encodeFunctionData({ abi, functionName: fn, args });
      const raw = await publicClient.call({ to: address, data });
      if (!raw.data) throw new Error("empty eth_call");
      return decodeFunctionResult({ abi, functionName: fn, data: raw.data });
    },
    [abi, address, publicClient],
  );

  const refreshViews = useCallback(async () => {
    if (!abi || !address) {
      setIssued(null);
      setPolicy(null);
      return;
    }
    try {
      const [i, p] = await Promise.all([readView("issuedTotal"), readView("policy")]);
      setIssued(String(i));
      setPolicy(String(p));
      pushLog(`issuedTotal=${String(i)} maxPerTx=${String(p)}`, "ok");
    } catch (e) {
      setIssued(null);
      setPolicy(null);
      pushLog(`views failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    }
  }, [abi, address, readView, pushLog]);

  useEffect(() => {
    void refreshViews();
  }, [refreshViews]);

  const getWalletClient = async (): Promise<{ wallet: WalletClient; account: Address }> => {
    if (!window.ethereum) throw new Error("No wallet — install OKX Wallet / MetaMask");
    const accounts = (await window.ethereum.request({ method: "eth_requestAccounts" })) as string[];
    if (!accounts[0]) throw new Error("no account");
    const acc = accounts[0] as Address;
    setAccount(acc);
    const hexId = `0x${chainId.toString(16)}`;
    try {
      await window.ethereum.request({
        method: "wallet_switchEthereumChain",
        params: [{ chainId: hexId }],
      });
    } catch {
      try {
        await window.ethereum.request({
          method: "wallet_addEthereumChain",
          params: [walletAddEthereumChainParams(preset)],
        });
      } catch {
        /* user rejected */
      }
    }
    const wallet = createWalletClient({
      account: acc,
      chain: { id: chainId, name: preset.name, nativeCurrency: preset.nativeCurrency, rpcUrls: { default: { http: [rpcUrl] } } },
      transport: custom(window.ethereum),
    });
    return { wallet, account: acc };
  };

  const runTx = async (label: string, fn: "issue" | "setAllow" | "transfer", args: bigint[]) => {
    if (!abi || !address) {
      pushLog("no contract address", "bad");
      return;
    }
    setBusy(true);
    try {
      const { wallet, account: acc } = await getWalletClient();
      const data = encodeFunctionData({ abi, functionName: fn, args });
      const hash = await wallet.sendTransaction({ account: acc, to: address, chain: wallet.chain, data });
      pushLog(`${label} tx ${hash}`, "info");
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (receipt.status === "success") {
        pushLog(`${label} confirmed`, "ok");
      } else {
        pushLog(`${label} reverted on-chain (status=reverted)`, "bad");
      }
      await refreshViews();
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      const short = msg.length > 220 ? `${msg.slice(0, 220)}…` : msg;
      pushLog(`${label} rejected: ${short}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const onQuery = async () => {
    setBusy(true);
    try {
      const words = principalWords(queryAddr);
      const [bal, allowed] = await Promise.all([
        readView("balanceOf", words),
        readView("isAllowed", words),
      ]);
      setQueryResult(`balanceOf=${String(bal)} · isAllowed=${String(allowed)}`);
      pushLog(`query ${queryAddr}: balance=${String(bal)} allowed=${String(allowed)}`, "ok");
    } catch (e) {
      setQueryResult(null);
      pushLog(`query failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const onDeploy = async () => {
    if (!abi || !bytecodeHex) {
      pushLog("need ABI + bytecode artifacts (run scripts/build-dapp-artifacts.sh)", "bad");
      return;
    }
    setBusy(true);
    try {
      const { wallet, account: acc } = await getWalletClient();
      const data = encodeDeployData({
        abi,
        bytecode: bytecodeHex,
        args: [
          parseAmount(ctorSupply, "supply"),
          parseAmount(ctorPerTx, "perTx"),
          parseAmount(ctorWindow, "windowCap"),
        ],
      });
      const hash = await wallet.sendTransaction({ account: acc, chain: wallet.chain, data });
      pushLog(`deploy tx ${hash}`, "info");
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (!receipt.contractAddress) throw new Error("no contractAddress");
      setAddress(receipt.contractAddress);
      setAddressInput(receipt.contractAddress);
      pushLog(`deployed ${receipt.contractAddress}`, "ok");
      await refreshViews();
    } catch (e) {
      pushLog(`deploy failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const applyPreset = (id: string) => {
    const p = CHAIN_PRESETS.find((c) => c.id === id);
    if (!p) return;
    setPreset(p);
    setChainId(p.chainId);
    setRpcUrl(p.rpcUrls[0]);
  };

  const guardTx = (fn: "issue" | "setAllow" | "transfer", who: string, amount: string) =>
    void runTx(fn, fn, [...principalWords(who), parseAmount(amount, "amount")]);

  const stampClass = (kind: LogLine["kind"]) =>
    kind === "ok" ? "stamp-ok" : kind === "bad" ? "stamp-bad" : "stamp-info";

  return (
    <>
      <section className="panel">
        <h2>
          Network & contract
          <span className="h2-note">{preset.name}</span>
        </h2>
        <div className="row">
          <label htmlFor="preset">network</label>
          <select id="preset" value={preset.id} onChange={(e) => applyPreset(e.target.value)}>
            {CHAIN_PRESETS.map((c) => (
              <option key={c.id} value={c.id}>
                {c.name} ({c.chainId})
              </option>
            ))}
          </select>
        </div>
        <div className="row">
          <label htmlFor="addr">contract</label>
          <input
            id="addr"
            value={addressInput}
            onChange={(e) => setAddressInput(e.target.value)}
            placeholder="0x… — deploy below or paste an address"
          />
          <button
            type="button"
            className="ghost"
            disabled={busy}
            onClick={() => {
              setAddress(addressInput.trim() as Address);
              pushLog(`attached ${addressInput.trim()}`, "info");
            }}
          >
            Attach
          </button>
        </div>
        <div className="kv">
          <dt>rpc</dt>
          <dd>{rpcUrl}</dd>
          <dt>wallet</dt>
          <dd>{account ?? "not connected"}</dd>
          <dt>issuedTotal</dt>
          <dd>{issued ?? "—"}</dd>
          <dt>maxPerTx</dt>
          <dd>{policy ?? "—"}</dd>
        </div>
        <div className="actions">
          <button
            type="button"
            disabled={busy}
            onClick={() =>
              void (async () => {
                setBusy(true);
                try {
                  const { account: acc } = await getWalletClient();
                  pushLog(`connected ${acc}`, "ok");
                } catch (e) {
                  pushLog(`connect failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
                } finally {
                  setBusy(false);
                }
              })()
            }
          >
            Connect wallet
          </button>
          <button type="button" className="ghost" disabled={busy || !address} onClick={() => void refreshViews()}>
            Refresh views
          </button>
        </div>
      </section>

      <section className="panel">
        <h2>
          Transfer shares
          <span className="h2-note">holder</span>
        </h2>
        <div className="row">
          <label htmlFor="tto">recipient</label>
          <input id="tto" value={transferTo} onChange={(e) => setTransferTo(e.target.value)} placeholder="0x… must be allowlisted" />
          <input
            id="tamt"
            value={transferAmount}
            onChange={(e) => setTransferAmount(e.target.value)}
            style={{ maxWidth: "9rem" }}
            aria-label="transfer amount"
          />
          <button type="button" disabled={busy || !address} onClick={() => guardTx("transfer", transferTo, transferAmount)}>
            Transfer
          </button>
        </div>
        <div className="row">
          <label htmlFor="q">query</label>
          <input id="q" value={queryAddr} onChange={(e) => setQueryAddr(e.target.value)} placeholder="0x… any address" />
          <button type="button" className="ghost" disabled={busy || !address} onClick={() => void onQuery()}>
            balanceOf / isAllowed
          </button>
        </div>
        {queryResult && <p className="mono ok">{queryResult}</p>}
        <p className="muted">
          Try the negative paths: exceed maxPerTx, exceed the window cap, or send to a
          non-allowlisted address — the contract reverts and the log shows the verdict.
        </p>
      </section>

      <section className="panel">
        <h2>
          Issue & allowlist
          <span className="h2-note">issuer only</span>
        </h2>
        <div className="row">
          <label htmlFor="ito">issue to</label>
          <input id="ito" value={issueTo} onChange={(e) => setIssueTo(e.target.value)} placeholder="0x… holder" />
          <input
            id="iamt"
            value={issueAmount}
            onChange={(e) => setIssueAmount(e.target.value)}
            style={{ maxWidth: "9rem" }}
            aria-label="issue amount"
          />
          <button type="button" disabled={busy || !address} onClick={() => guardTx("issue", issueTo, issueAmount)}>
            Issue shares
          </button>
        </div>
        <div className="row">
          <label htmlFor="aa">allowlist</label>
          <input id="aa" value={allowAddr} onChange={(e) => setAllowAddr(e.target.value)} placeholder="0x… address" />
          <select id="af" value={allowFlag} onChange={(e) => setAllowFlag(e.target.value)}>
            <option value="1">allow (1)</option>
            <option value="0">block (0)</option>
          </select>
          <button type="button" disabled={busy || !address} onClick={() => guardTx("setAllow", allowAddr, allowFlag)}>
            Set allowlist
          </button>
        </div>
      </section>

      <section className="panel">
        <h2>
          Deploy
          <span className="h2-note">wallet signs · OKB gas</span>
        </h2>
        <div className="row">
          <label htmlFor="cs">supply</label>
          <input id="cs" value={ctorSupply} onChange={(e) => setCtorSupply(e.target.value)} />
        </div>
        <div className="row">
          <label htmlFor="cp">maxPerTx</label>
          <input id="cp" value={ctorPerTx} onChange={(e) => setCtorPerTx(e.target.value)} />
        </div>
        <div className="row">
          <label htmlFor="cw">windowCap</label>
          <input id="cw" value={ctorWindow} onChange={(e) => setCtorWindow(e.target.value)} />
        </div>
        <div className="actions">
          <button type="button" disabled={busy || !bytecodeHex} onClick={() => void onDeploy()}>
            Deploy to {preset.name}
          </button>
        </div>
        <p className="muted">
          The artifact already passed the machine gate; nothing deploys if it fails. CLI
          alternative: <code>scripts/deploy-testnet.sh</code>.
        </p>
      </section>

      <section className="panel">
        <h2>
          Log
          <span className="h2-note">verdicts included</span>
        </h2>
        <div className="log" aria-live="polite">
          {logs.length === 0
            ? "logs…"
            : logs.map((l, i) => (
                <div key={`${l.at}-${i}`} className={stampClass(l.kind)}>
                  [{l.at}] {l.text}
                </div>
              ))}
        </div>
        {deployment?.notes && (
          <p className="muted" style={{ marginTop: "0.5rem" }}>
            {deployment.notes.join(" · ")}
          </p>
        )}
      </section>
    </>
  );
};
