import { useCallback, useEffect, useState, type FC } from "react";
import { useWallet } from "@provablehq/aleo-wallet-adaptor-react";
import { useWalletModal } from "@provablehq/aleo-wallet-adaptor-react-ui";
import {
  explorerProgramUrl,
  explorerTxUrl,
  feeMicrocredits,
  networkPath,
  programId as defaultProgramId,
} from "./config";
import { readStateCell } from "./explorer";

type LogLine = { at: string; text: string; kind?: "ok" | "bad" | "info" };

export const DappPanel: FC = () => {
  const {
    connected,
    address,
    network,
    executeTransaction,
    transactionStatus: getTransactionStatus,
  } = useWallet();
  const { setVisible: openWalletModal } = useWalletModal();

  const [program, setProgram] = useState(defaultProgramId());
  const [delta, setDelta] = useState("3");
  const [initial, setInitial] = useState("5");
  const [busy, setBusy] = useState(false);
  const [count, setCount] = useState<string | null>(null);
  const [initialized, setInitialized] = useState<string | null>(null);
  const [lastTx, setLastTx] = useState<string | null>(null);
  const [logs, setLogs] = useState<LogLine[]>([]);

  const pushLog = useCallback((text: string, kind: LogLine["kind"] = "info") => {
    const at = new Date().toISOString().slice(11, 19);
    setLogs((prev) => [{ at, text, kind }, ...prev].slice(0, 40));
  }, []);

  const refreshState = useCallback(async () => {
    try {
      const s = await readStateCell(program.trim());
      setCount(s.count);
      setInitialized(s.initialized);
      pushLog(`state count=${s.count ?? "—"} initialized=${s.initialized ?? "—"}`, "ok");
    } catch (e) {
      const msg = e instanceof Error ? e.message : String(e);
      pushLog(`state read failed: ${msg}`, "bad");
    }
  }, [program, pushLog]);

  useEffect(() => {
    void refreshState();
  }, [refreshState]);

  const ensureConnected = () => {
    if (!connected) {
      openWalletModal(true);
      return false;
    }
    return true;
  };

  const runFn = async (functionName: string, inputs: string[]) => {
    if (!ensureConnected()) return;
    setBusy(true);
    setLastTx(null);
    try {
      pushLog(`execute ${program}::${functionName}(${inputs.join(", ")})…`);
      const tx = await executeTransaction({
        program: program.trim(),
        function: functionName,
        inputs,
        fee: feeMicrocredits(),
        privateFee: false,
      });
      const tempId = tx?.transactionId as string | undefined;
      if (!tempId) {
        pushLog("no transactionId returned", "bad");
        return;
      }
      pushLog(`submitted id=${tempId}`, "ok");
      setLastTx(tempId);

      // Poll a few times for finalization (wallet-dependent).
      for (let i = 0; i < 30; i++) {
        await new Promise((r) => setTimeout(r, 1500));
        try {
          const st = await getTransactionStatus(tempId);
          const status = String(st?.status ?? "");
          const onchain = (st?.transactionId as string | undefined) || tempId;
          pushLog(`status=${status || "?"} tx=${onchain}`);
          if (st?.transactionId) setLastTx(String(st.transactionId));
          const low = status.toLowerCase();
          if (low.includes("accept") || low === "finalized" || low === "confirmed") {
            pushLog("accepted — refreshing public mappings", "ok");
            break;
          }
          if (low.includes("fail") || low.includes("reject")) {
            pushLog(`failed: ${st?.error ?? status}`, "bad");
            break;
          }
        } catch (err) {
          pushLog(`poll error: ${err instanceof Error ? err.message : String(err)}`, "bad");
        }
      }
      await refreshState();
    } catch (e) {
      console.error(e);
      pushLog(`execute error: ${e instanceof Error ? e.message : String(e)}`, "bad");
    } finally {
      setBusy(false);
    }
  };

  return (
    <>
      <section className="panel">
        <h2>Connection</h2>
        <div className="kv">
          <dt>Network</dt>
          <dd className="mono">
            {String(network ?? networkPath())} · path <code>{networkPath()}</code>
          </dd>
          <dt>Address</dt>
          <dd className="mono">{connected ? address ?? "—" : "not connected"}</dd>
        </div>
      </section>

      <section className="panel">
        <h2>Program</h2>
        <div className="row">
          <label htmlFor="program">Program ID</label>
          <input
            id="program"
            className="mono"
            value={program}
            onChange={(e) => setProgram(e.target.value)}
            spellCheck={false}
          />
        </div>
        <p className="muted">
          Explorer:{" "}
          <a href={explorerProgramUrl(program.trim())} target="_blank" rel="noreferrer">
            {program.trim()}
          </a>
        </p>
        <div className="kv" style={{ marginTop: "0.75rem" }}>
          <dt>count</dt>
          <dd className="mono">{count ?? "—"}</dd>
          <dt>initialized</dt>
          <dd className="mono">{initialized ?? "—"}</dd>
        </div>
        <div className="actions">
          <button type="button" className="action ghost" disabled={busy} onClick={() => void refreshState()}>
            Refresh state
          </button>
        </div>
      </section>

      <section className="panel">
        <h2>Actions (StateCell-shaped)</h2>
        <p className="muted">
          Matches ProofForge Hello / StateCell twin: <code>initialize(u64)</code>,{" "}
          <code>increment(u64)</code>. Fee default {feeMicrocredits()} microcredits (public).
        </p>

        <div className="row">
          <label htmlFor="initial">initialize</label>
          <input
            id="initial"
            value={initial}
            onChange={(e) => setInitial(e.target.value)}
            inputMode="numeric"
          />
          <button
            type="button"
            className="action"
            disabled={busy}
            onClick={() => void runFn("initialize", [`${initial.trim()}u64`])}
          >
            Call initialize
          </button>
        </div>

        <div className="row">
          <label htmlFor="delta">increment</label>
          <input
            id="delta"
            value={delta}
            onChange={(e) => setDelta(e.target.value)}
            inputMode="numeric"
          />
          <button
            type="button"
            className="action"
            disabled={busy}
            onClick={() => void runFn("increment", [`${delta.trim()}u64`])}
          >
            Call increment
          </button>
        </div>

        {lastTx && (
          <p className="muted">
            Last tx:{" "}
            <a className="mono" href={explorerTxUrl(lastTx)} target="_blank" rel="noreferrer">
              {lastTx}
            </a>
          </p>
        )}

        <div className="log mono" aria-live="polite">
          {logs.length === 0
            ? "logs appear here…"
            : logs.map((l, i) => (
                <div key={`${l.at}-${i}`} className={l.kind === "ok" ? "status-ok" : l.kind === "bad" ? "status-bad" : ""}>
                  [{l.at}] {l.text}
                </div>
              ))}
        </div>
      </section>

      <section className="panel">
        <h2>Backend reminder</h2>
        <pre className="mono muted" style={{ margin: 0, whiteSpace: "pre-wrap" }}>{`# from monorepo / pf project
pf build
pf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id <stem>
# then set VITE_ALEO_PROGRAM_ID=<stem>.aleo`}</pre>
      </section>
    </>
  );
};
