import type { FC } from "react";
import { DappPanel } from "./DappPanel";

export const App: FC = () => {
  return (
    <>
      <header>
        <div>
          <h1>ProofForge · EVM dApp UI</h1>
          <p>
            viem + browser wallet · StateCell-shaped contracts · Anvil default · X Layer presets
          </p>
        </div>
      </header>
      <p className="banner">
        Backend: <code>pf build -t evm</code> → <code>*.abi.json</code> + <code>*.bin</code>. Prefer{" "}
        <code>bash scripts/pf_evm_local_demo.sh</code> for Anvil + <code>public/deployment.json</code>.
        X Layer: set <code>VITE_NETWORK_ID=evm.xlayer.testnet</code> (chain 1952, OKB) or mainnet 196 —
        catalog only; pf v0 does not default public broadcast. Guides:{" "}
        <code>docs/product/08-evm-dapp-frontend.md</code> ·{" "}
        <code>docs/product/13-xlayer-onchainos.md</code>.
      </p>
      <DappPanel />
    </>
  );
};
