import { useMemo, type FC } from "react";
import { AleoWalletProvider } from "@provablehq/aleo-wallet-adaptor-react";
import {
  WalletModalProvider,
  WalletMultiButton,
} from "@provablehq/aleo-wallet-adaptor-react-ui";
import { LeoWalletAdapter } from "@provablehq/aleo-wallet-adaptor-leo";
import { PuzzleWalletAdapter } from "@provablehq/aleo-wallet-adaptor-puzzle";
import { ShieldWalletAdapter } from "@provablehq/aleo-wallet-adaptor-shield";
import { DecryptPermission } from "@provablehq/aleo-wallet-adaptor-core";
import "@provablehq/aleo-wallet-adaptor-react-ui/dist/styles.css";

import { networkFromEnv, programId } from "./config";
import { DappPanel } from "./DappPanel";

export const App: FC = () => {
  const wallets = useMemo(
    () => [
      new LeoWalletAdapter(),
      new PuzzleWalletAdapter(),
      new ShieldWalletAdapter(),
    ],
    [],
  );

  const programs = useMemo(() => {
    const id = programId();
    // credits always useful for fee/records; pin app program too
    return Array.from(new Set(["credits.aleo", id]));
  }, []);

  return (
    <AleoWalletProvider
      wallets={wallets}
      network={networkFromEnv()}
      decryptPermission={DecryptPermission.UponRequest}
      autoConnect={false}
      programs={programs}
      onError={(e) => console.error("[aleo-wallet]", e)}
    >
      <WalletModalProvider>
        <header className="app-header">
          <div>
            <h1>ProofForge · Aleo dApp UI</h1>
            <p>Wallet connect + execute StateCell-shaped programs (testnet default)</p>
          </div>
          <WalletMultiButton />
        </header>

        <p className="banner">
          Backend contracts come from <code>pf build / pf deploy</code>. This UI never embeds
          private keys — signing stays in the wallet extension. See{" "}
          <code>docs/product/07-aleo-dapp-frontend-wallet.md</code>.
        </p>

        <DappPanel />
      </WalletModalProvider>
    </AleoWalletProvider>
  );
};
