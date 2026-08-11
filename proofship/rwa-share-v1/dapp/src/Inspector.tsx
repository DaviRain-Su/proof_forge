import { useEffect, useState, type FC } from "react";
import { loadGateReport } from "./config";
import type { Launch } from "./studio/store";
import type { GateReport } from "./types";

type Tab = "fields" | "program" | "gate" | "ship";

export const Inspector: FC<{ launch: Launch | null; onOpenRegistry: () => void }> = ({
  launch,
  onOpenRegistry,
}) => {
  const [tab, setTab] = useState<Tab>("fields");
  const [report, setReport] = useState<GateReport | null>(null);

  useEffect(() => {
    void (async () => setReport(await loadGateReport()))();
  }, []);

  useEffect(() => {
    if (launch?.fields) setTab("fields");
  }, [launch?.id, launch?.fields]);

  return (
    <aside className="inspector">
      <nav className="insp-tabs" aria-label="inspector">
        {(["fields", "program", "gate", "ship"] as const).map((t) => (
          <button
            key={t}
            type="button"
            className={tab === t ? "insp-tab active" : "insp-tab"}
            onClick={() => setTab(t)}
          >
            {t}
          </button>
        ))}
      </nav>

      <div className="insp-body">
        {tab === "fields" &&
          (launch?.fields ? (
            <div className="kv">
              <dt>program</dt>
              <dd>{launch.program}</dd>
              <dt>totalSupply</dt>
              <dd>{launch.fields.totalSupply}</dd>
              <dt>maxPerTx</dt>
              <dd>{launch.fields.maxPerTx}</dd>
              <dt>window</dt>
              <dd>
                {launch.fields.windowCap} / {launch.fields.windowBlocks} blocks
              </dd>
              <dt>rule</dt>
              <dd>allowlist only</dd>
            </div>
          ) : (
            <p className="muted">Send rules in the chat — the draft fields land here.</p>
          ))}

        {tab === "program" &&
          (launch?.source ? (
            <pre className="src insp-src">{launch.source}</pre>
          ) : (
            <p className="muted">No program yet. The drafted ProgramV1 source appears here.</p>
          ))}

        {tab === "gate" &&
          (report ? (
            <>
              <div className="seal-row" style={{ marginTop: 0 }}>
                {report.proofs.map((p) => (
                  <div key={p.program} className="seal small" role="img" aria-label={`certified ${p.program}`}>
                    <span className="seal-glyph">⊢</span>
                    <span className="seal-word">certified</span>
                    <span className="seal-sub">{p.program}</span>
                  </div>
                ))}
                <div className="seal small rejected" role="img" aria-label="rejected EvenStepBad">
                  <span className="seal-glyph">✗</span>
                  <span className="seal-word">rejected</span>
                  <span className="seal-sub">EvenStepBad</span>
                </div>
              </div>
              <div className="kv" style={{ marginTop: "1rem" }}>
                <dt>program</dt>
                <dd>{report.program}</dd>
                <dt>source</dt>
                <dd>{report.sourceDigest}</dd>
                <dt>output set</dt>
                <dd>{report.build.outputSetDigest}</dd>
                <dt>negative</dt>
                <dd className="bad">
                  {report.negative.file} · exit {report.negative.exitCode} · {report.negative.artifacts}
                </dd>
                <dt>anvil</dt>
                <dd>
                  {report.anvil.scenarios} scenarios · {report.anvil.result}
                </dd>
                <dt>sealed at</dt>
                <dd>{report.generatedAt}</dd>
              </div>
            </>
          ) : (
            <p className="muted">
              No sealed report — run <code>scripts/build-dapp-artifacts.sh</code>.
            </p>
          ))}

        {tab === "ship" && (
          <>
            <div className="kv">
              <dt>cli</dt>
              <dd>
                scripts/deploy-testnet.sh {launch?.fields?.totalSupply ?? "<supply>"}{" "}
                {launch?.fields?.maxPerTx ?? "<perTx>"} {launch?.fields?.windowCap ?? "<windowCap>"}
              </dd>
              <dt>network</dt>
              <dd>X Layer testnet · 1952 · OKB</dd>
              <dt>keys</dt>
              <dd>env or wallet — never a server</dd>
            </div>
            <div className="actions">
              <button type="button" onClick={onOpenRegistry}>
                Open the registry
              </button>
            </div>
            <p className="muted">
              The Registry tab deploys with your wallet signature, or attaches an already-deployed
              address.
            </p>
          </>
        )}
      </div>
    </aside>
  );
};
