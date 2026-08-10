import type { FC } from "react";
import { DappPanel } from "./DappPanel";

export const App: FC = () => {
  return (
    <>
      <header>
        <div>
          <h1>ProofForge · EVM dApp UI</h1>
          <p>viem + browser wallet · StateCell-shaped contracts · local Anvil default</p>
        </div>
      </header>
      <p className="banner">
        Backend: <code>pf build -t evm</code> → <code>*.abi.json</code> + <code>*.bin</code>. Prefer{" "}
        <code>bash scripts/pf_evm_local_demo.sh</code> to start Anvil, deploy, and write{" "}
        <code>public/deployment.json</code>. Public-chain broadcast is out of scope for pf v0.
        Guide: <code>docs/product/08-evm-dapp-frontend.md</code>.
      </p>
      <DappPanel />
    </>
  );
};
