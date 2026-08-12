import { useEffect, useMemo, useState } from "react";
import { DEFAULT_NETWORK, NETWORKS, type NearNetwork } from "./config";
import { loadDeployment, type NearUiDeployment } from "./deployment";

/**
 * Skeleton UI: paste contract account + optional view helper notes.
 * Does not ship a full wallet adaptor — use near-api-js / wallet-selector
 * from the ecosystem. PF MCP does not hold keys.
 */
export function App() {
  const [network, setNetwork] = useState<NearNetwork>(DEFAULT_NETWORK);
  const [accountId, setAccountId] = useState("test.near");
  const [method, setMethod] = useState("get");
  const [dep, setDep] = useState<NearUiDeployment | null>(null);
  useEffect(() => {
    void loadDeployment().then(setDep);
  }, []);
  const note = useMemo(
    () =>
      `Build: pf build -t near && pf deploy -t near (save-only package).\n` +
      `Local gate: pf test -t near (artifact fast-path).\n` +
      `One-shot: pf run -t near -- init 7 && pf run -t near -- get\n` +
      `RPC: ${network.rpcUrl} (${network.honesty})`,
    [network]
  );

  return (
    <main className="page">
      <h1>ProofForge · NEAR</h1>
      <p className="muted">
        Ecosystem frontend skeleton (near-api-js). Not shipped wallet code; not
        formal; public broadcast refused in pf v0.
      </p>

      <label>
        Network
        <select
          value={network.id}
          onChange={(e) => {
            const n = NETWORKS.find((x) => x.id === e.target.value);
            if (n) setNetwork(n);
          }}
        >
          {NETWORKS.map((n) => (
            <option key={n.id} value={n.id}>
              {n.label}
            </option>
          ))}
        </select>
      </label>

      <label>
        Contract account
        <input value={accountId} onChange={(e) => setAccountId(e.target.value)} />
      </label>

      <label>
        View method (docs only)
        <input value={method} onChange={(e) => setMethod(e.target.value)} />
      </label>

      {dep && (
        <pre className="note">
          loaded deployment.json{"\n"}
          program={dep.program ?? "?"} network={dep.network ?? "?"}{"\n"}
          contractId={dep.contractId ?? "(none)"}{"\n"}
          wasmSha256={dep.wasmSha256 ?? "?"}
        </pre>
      )}
      <pre className="note">{note}</pre>
      <p className="muted">
        Wire near-api-js <code>Contract</code> / wallet-selector yourself against{" "}
        <code>{accountId}.{method}</code>. See{" "}
        <code>docs/product/near-agent-cheatsheet.md</code>.
      </p>
    </main>
  );
}
