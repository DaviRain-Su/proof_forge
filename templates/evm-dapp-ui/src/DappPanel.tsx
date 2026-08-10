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
import { anvil } from "viem/chains";
import {
  ANVIL_ACCOUNT0,
  envAddress,
  envChainId,
  envCtorInitial,
  envRpc,
  loadDefaultAbi,
  loadDeployment,
} from "./config";
import type { DeploymentFile } from "./types";

type LogLine = { at: string; text: string; kind?: "ok" | "bad" | "info" };

export const DappPanel: FC = () => {
  const [deployment, setDeployment] = useState<DeploymentFile | null>(null);
  const [abi, setAbi] = useState<Abi | null>(null);
  const [rpcUrl, setRpcUrl] = useState(envRpc());
  const [chainId, setChainId] = useState(envChainId());
  const [address, setAddress] = useState<Address | null>(envAddress());
  const [account, setAccount] = useState<Address | null>(null);
  const [count, setCount] = useState<string | null>(null);
  const [delta, setDelta] = useState("5");
  const [ctorInitial, setCtorInitial] = useState(String(envCtorInitial()));
  const [bytecodeHex, setBytecodeHex] = useState<Hex | null>(null);
  const [busy, setBusy] = useState(false);
  const [logs, setLogs] = useState<LogLine[]>([]);

  const pushLog = useCallback((text: string, kind: LogLine["kind"] = "info") => {
    const at = new Date().toISOString().slice(11, 19);
    setLogs((prev) => [{ at, text, kind }, ...prev].slice(0, 50));
  }, []);

  const publicClient: PublicClient = useMemo(
    () =>
      createPublicClient({
        chain: { ...anvil, id: chainId },
        transport: http(rpcUrl),
      }),
    [rpcUrl, chainId],
  );

  // Bootstrap: deployment.json wins, else default ABI + env.
  useEffect(() => {
    void (async () => {
      const dep = await loadDeployment();
      if (dep) {
        setDeployment(dep);
        setAbi(dep.abi);
        setRpcUrl(dep.rpcUrl);
        setChainId(dep.chainId);
        setAddress(dep.contractAddress);
        setCtorInitial(String(dep.constructorInitial));
        if (dep.bytecode) setBytecodeHex(dep.bytecode);
        pushLog(
          `loaded deployment.json program=${dep.program} addr=${dep.contractAddress}`,
          "ok",
        );
        return;
      }
      try {
        const a = await loadDefaultAbi();
        setAbi(a);
        pushLog("loaded default StateCell.abi.json (no deployment.json yet)", "info");
      } catch (e) {
        pushLog(`ABI load failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
      }
      // optional bytecode for in-UI deploy
      try {
        const res = await fetch("/artifacts/StateCell.bin", { cache: "no-store" });
        if (res.ok) {
          const text = (await res.text()).trim().replace(/\s+/g, "");
          const hex = (text.startsWith("0x") ? text : `0x${text}`) as Hex;
          setBytecodeHex(hex);
          pushLog("loaded /artifacts/StateCell.bin for in-UI deploy", "ok");
        }
      } catch {
        /* optional */
      }
    })();
  }, [pushLog]);

  const refreshCount = useCallback(async () => {
    if (!abi || !address) {
      setCount(null);
      return;
    }
    try {
      const data = encodeFunctionData({ abi, functionName: "get", args: [] });
      const raw = await publicClient.call({ to: address, data });
      if (!raw.data) throw new Error("empty eth_call");
      const value = decodeFunctionResult({
        abi,
        functionName: "get",
        data: raw.data,
      });
      setCount(String(value));
      pushLog(`get() = ${String(value)}`, "ok");
    } catch (e) {
      setCount(null);
      pushLog(`get() failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    }
  }, [abi, address, publicClient, pushLog]);

  useEffect(() => {
    void refreshCount();
  }, [refreshCount]);

  const getWalletClient = async (): Promise<{
    wallet: WalletClient;
    account: Address;
  }> => {
    if (!window.ethereum) {
      throw new Error("No window.ethereum — install MetaMask (or point at Anvil via demo script)");
    }
    const accounts = (await window.ethereum.request({
      method: "eth_requestAccounts",
    })) as string[];
    if (!accounts[0]) throw new Error("no account");
    const acc = accounts[0] as Address;
    setAccount(acc);

    // Best-effort switch to local chain
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
          params: [
            {
              chainId: hexId,
              chainName: `PF Local ${chainId}`,
              rpcUrls: [rpcUrl],
              nativeCurrency: { name: "ETH", symbol: "ETH", decimals: 18 },
            },
          ],
        });
      } catch {
        /* user rejected — continue; send may still work if already on chain */
      }
    }

    const wallet = createWalletClient({
      account: acc,
      chain: { ...anvil, id: chainId, rpcUrls: { default: { http: [rpcUrl] } } },
      transport: custom(window.ethereum),
    });
    return { wallet, account: acc };
  };

  const onConnect = async () => {
    setBusy(true);
    try {
      const { account: acc } = await getWalletClient();
      pushLog(`connected ${acc}`, "ok");
    } catch (e) {
      pushLog(`connect failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const onDeploy = async () => {
    if (!abi || !bytecodeHex) {
      pushLog("need ABI + bytecode (run demo script or copy *.bin)", "bad");
      return;
    }
    setBusy(true);
    try {
      const { wallet, account: acc } = await getWalletClient();
      const initial = BigInt(ctorInitial || "0");
      const data = encodeDeployData({
        abi,
        bytecode: bytecodeHex,
        args: [initial],
      });
      const hash = await wallet.sendTransaction({
        account: acc,
        chain: { ...anvil, id: chainId },
        data,
      });
      pushLog(`deploy tx ${hash}`, "info");
      const receipt = await publicClient.waitForTransactionReceipt({ hash });
      if (!receipt.contractAddress) throw new Error("no contractAddress");
      setAddress(receipt.contractAddress);
      pushLog(`deployed ${receipt.contractAddress}`, "ok");
      await refreshCount();
    } catch (e) {
      pushLog(`deploy failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const onIncrement = async () => {
    if (!abi || !address) {
      pushLog("no contract address", "bad");
      return;
    }
    setBusy(true);
    try {
      const { wallet, account: acc } = await getWalletClient();
      const d = BigInt(delta || "0");
      const data = encodeFunctionData({
        abi,
        functionName: "increment",
        args: [d],
      });
      const hash = await wallet.sendTransaction({
        account: acc,
        to: address,
        chain: { ...anvil, id: chainId },
        data,
      });
      pushLog(`increment tx ${hash}`, "info");
      await publicClient.waitForTransactionReceipt({ hash });
      pushLog("increment confirmed", "ok");
      await refreshCount();
    } catch (e) {
      pushLog(`increment failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <section className="panel">
        <h2>Network</h2>
        <div className="kv">
          <dt>RPC</dt>
          <dd className="mono">{rpcUrl}</dd>
          <dt>chainId</dt>
          <dd className="mono">{chainId}</dd>
          <dt>Wallet</dt>
          <dd className="mono">{account ?? "not connected"}</dd>
          <dt>Contract</dt>
          <dd className="mono">{address ?? "—"}</dd>
          <dt>count (get)</dt>
          <dd className="mono">{count ?? "—"}</dd>
        </div>
        {deployment && (
          <p className="muted">
            From deployment.json · program <code>{deployment.program}</code> · ctor initial{" "}
            {deployment.constructorInitial}
          </p>
        )}
        <div className="actions">
          <button type="button" disabled={busy} onClick={() => void onConnect()}>
            Connect wallet
          </button>
          <button type="button" className="ghost" disabled={busy} onClick={() => void refreshCount()}>
            Refresh get()
          </button>
        </div>
        <p className="muted" style={{ marginTop: "0.75rem" }}>
          Anvil default #0 (funding reference only): <span className="mono">{ANVIL_ACCOUNT0}</span>
        </p>
      </section>

      <section className="panel">
        <h2>Deploy (optional)</h2>
        <p className="muted">
          Needs <code>/artifacts/StateCell.bin</code> (or bytecode in deployment.json). Prefer the
          monorepo demo script so MetaMask only signs user txs.
        </p>
        <div className="row">
          <label htmlFor="ctor">constructor uint64</label>
          <input id="ctor" value={ctorInitial} onChange={(e) => setCtorInitial(e.target.value)} />
        </div>
        <div className="actions">
          <button type="button" disabled={busy || !bytecodeHex} onClick={() => void onDeploy()}>
            Deploy with wallet
          </button>
        </div>
      </section>

      <section className="panel">
        <h2>Call increment</h2>
        <div className="row">
          <label htmlFor="delta">delta</label>
          <input id="delta" value={delta} onChange={(e) => setDelta(e.target.value)} />
          <button type="button" disabled={busy || !address} onClick={() => void onIncrement()}>
            Send increment
          </button>
        </div>
        <div className="log mono" aria-live="polite">
          {logs.length === 0
            ? "logs…"
            : logs.map((l, i) => (
                <div
                  key={`${l.at}-${i}`}
                  className={l.kind === "ok" ? "ok" : l.kind === "bad" ? "bad" : ""}
                >
                  [{l.at}] {l.text}
                </div>
              ))}
        </div>
      </section>

      <section className="panel">
        <h2>Backend reminder</h2>
        <pre className="mono muted" style={{ margin: 0, whiteSpace: "pre-wrap" }}>{`# monorepo
bash scripts/pf_evm_local_demo.sh
# → starts Anvil, pf build StateCell, deploys, writes templates/evm-dapp-ui/public/deployment.json

cd templates/evm-dapp-ui && npm install && npm run dev
# MetaMask: add network chainId 31337 → http://127.0.0.1:<port>
# Import Anvil #0 if you want the funded deployer key (LOCAL ONLY)`}</pre>
      </section>
    </>
  );
};
