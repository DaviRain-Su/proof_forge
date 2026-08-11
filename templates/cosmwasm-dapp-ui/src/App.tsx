import { useMemo, useState } from "react";
import { DEFAULT_NETWORK, NETWORKS, type CwNetwork } from "./config";

export function App() {
  const [network, setNetwork] = useState<CwNetwork>(DEFAULT_NETWORK);
  const [contract, setContract] = useState("pf1…");
  const note = useMemo(
    () =>
      `Build: pf build -t cosmwasm\n` +
      `Local gate: pf test -t cosmwasm (artifact fast-path when *.wasm present)\n` +
      `Deploy package: pf deploy -t cosmwasm (save-only; no broadcast)\n` +
      `JSON ABI: flat instantiate + {"method":{params}} decimals\n` +
      `Network: ${network.id} — ${network.honesty}`,
    [network]
  );

  return (
    <main className="page">
      <h1>ProofForge · CosmWasm</h1>
      <p className="muted">
        Ecosystem frontend skeleton (cosmjs). Not formal; not wasmd mainnet;
        public broadcast refused in pf v0. Generic sync call FC.
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
        Contract address
        <input value={contract} onChange={(e) => setContract(e.target.value)} />
      </label>

      <pre className="note">{note}</pre>
      <p className="muted">
        Wire <code>@cosmjs/cosmwasm-stargate</code> query/execute against the
        product JSON subset. See{" "}
        <code>docs/product/cosmwasm-agent-cheatsheet.md</code>.
      </p>
    </main>
  );
}
