import { useCallback, useEffect, useMemo, useState, type FC } from "react";
import { loadAbi, loadDeployment } from "./config";
import type { PsyAbi, PsyDeployment } from "./types";

type Log = { at: string; text: string; kind?: "ok" | "bad" | "info" };

export const App: FC = () => {
  const [dep, setDep] = useState<PsyDeployment | null>(null);
  const [abi, setAbi] = useState<PsyAbi | null>(null);
  const [account, setAccount] = useState<string | null>(null);
  const [method, setMethod] = useState("increment");
  const [arg0, setArg0] = useState("5");
  const [contractId, setContractId] = useState("");
  const [busy, setBusy] = useState(false);
  const [logs, setLogs] = useState<Log[]>([]);

  const push = useCallback((text: string, kind: Log["kind"] = "info") => {
    const at = new Date().toISOString().slice(11, 19);
    setLogs((prev) => [{ at, text, kind }, ...prev].slice(0, 40));
  }, []);

  useEffect(() => {
    void (async () => {
      const d = await loadDeployment();
      const a = await loadAbi();
      if (d) {
        setDep(d);
        if (d.contractId != null) setContractId(String(d.contractId));
        push(
          `loaded deployment.json network=${d.network ?? "?"} id=${d.contractId ?? "—"}`,
          "ok",
        );
      } else {
        push("no /deployment.json — copy from pf deploy tx/deployment.json", "info");
      }
      if (a) {
        setAbi(a);
        if (a.methods[0]) setMethod(a.methods[0].name);
        push(`loaded ABI methods=${a.methods.map((m) => m.name).join(",")}`, "ok");
      } else {
        push("no ABI — run scripts/psy_dpn_to_abi.py after pf build -t psy", "info");
      }
    })();
  }, [push]);

  const hasWallet = typeof window !== "undefined" && Boolean(window.psy);
  const methods = useMemo(() => abi?.methods ?? [], [abi]);
  const selected = methods.find((m) => m.name === method);

  const connect = async () => {
    if (!window.psy) {
      push("window.psy missing — install Psy wallet extension", "bad");
      return;
    }
    setBusy(true);
    try {
      const accs = await window.psy.requestAccounts();
      setAccount(accs[0] ?? null);
      push(`connected ${accs[0] ?? "(none)"}`, "ok");
    } catch (e) {
      push(`connect failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  const send = async () => {
    if (!window.psy || !account) {
      push("connect wallet first", "bad");
      return;
    }
    const cid = Number(contractId);
    if (!Number.isFinite(cid) || cid <= 0) {
      push("set a valid contractId (from pf deploy receipt)", "bad");
      return;
    }
    const nIn = selected?.arity?.inputs ?? selected?.params?.length ?? 0;
    const inputs: bigint[] = [];
    if (nIn >= 1) {
      try {
        inputs.push(BigInt(arg0 || "0"));
      } catch {
        push("arg0 must be integer", "bad");
        return;
      }
    }
    setBusy(true);
    try {
      const tx = await window.psy.sendTransaction(account, {
        contract_id: cid,
        method_name: method,
        inputs,
      });
      push(`sendTransaction ok tx=${tx}`, "ok");
    } catch (e) {
      push(`tx failed: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  return (
    <div>
      <p className="pill">ProofForge · Psy · engineering demo</p>
      <h1>Psy dApp UI (PF ABI + official wallet)</h1>
      <p className="muted">
        Contracts: <code>pf build -t psy</code> → DPN + derived ABI. Wallet/calls: official{" "}
        <code>window.psy</code>. Install wallet from{" "}
        <a href="https://app.psy-protocol.xyz/#/wallet" target="_blank" rel="noreferrer">
          app.psy-protocol.xyz
        </a>
        . Fund L2 balance before calls (GUTA/DA fees).
      </p>

      <div className="card">
        <div>
          wallet:{" "}
          <strong className={hasWallet ? "ok" : "bad"}>
            {hasWallet ? "window.psy present" : "not detected"}
          </strong>
        </div>
        <div>account: <strong>{account ?? "—"}</strong></div>
        <div>
          network: <strong>{dep?.network ?? "—"}</strong> · contractId:{" "}
          <strong>{contractId || "—"}</strong>
        </div>
        {dep?.contractUuid && (
          <div className="muted">uuid: {dep.contractUuid.slice(0, 18)}…</div>
        )}
        {dep?.explorer && (
          <div>
            <a href={dep.explorer} target="_blank" rel="noreferrer">
              explorer
            </a>
          </div>
        )}
        <button type="button" disabled={busy || !hasWallet} onClick={() => void connect()}>
          Connect Psy wallet
        </button>
      </div>

      <div className="card">
        <label>contract id</label>
        <input value={contractId} onChange={(e) => setContractId(e.target.value)} />
        <label>method</label>
        <select value={method} onChange={(e) => setMethod(e.target.value)}>
          {(methods.length ? methods : [{ name: "initialize" }, { name: "increment" }, { name: "get" }]).map(
            (m) => (
              <option key={m.name} value={m.name}>
                {m.name}
                {"methodId" in m && m.methodId != null ? ` (${m.methodId})` : ""}
              </option>
            ),
          )}
        </select>
        {(selected?.arity?.inputs ?? 1) > 0 && (
          <>
            <label>arg0 (u64)</label>
            <input value={arg0} onChange={(e) => setArg0(e.target.value)} />
          </>
        )}
        <div>
          <button type="button" disabled={busy || !account} onClick={() => void send()}>
            Send via wallet
          </button>
        </div>
        <p className="muted">
          CLI equivalent:{" "}
          <code>
            pf execute -t psy --network testnet --broadcast --private-key-env PF_PSY_KEY -- {method}{" "}
            {arg0}
          </code>
        </p>
      </div>

      <div className="card">
        <strong>log</strong>
        <div className="log">
          {logs.map((l, i) => (
            <div key={`${l.at}-${i}`} className={l.kind}>
              [{l.at}] {l.text}
            </div>
          ))}
        </div>
      </div>
    </div>
  );
};
