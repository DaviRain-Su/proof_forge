import type { FC } from "react";
import { useMemo } from "react";
import {
  ConnectionProvider as ConnectionProviderImpl,
  WalletProvider as WalletProviderImpl,
} from "@solana/wallet-adapter-react";
import {
  WalletModalProvider as WalletModalProviderImpl,
  WalletMultiButton as WalletMultiButtonImpl,
} from "@solana/wallet-adapter-react-ui";
import { PhantomWalletAdapter, SolflareWalletAdapter } from "@solana/wallet-adapter-wallets";
import { DappPanel } from "./DappPanel";
import { envRpc } from "./config";

// wallet-adapter FC types can disagree with @types/react minor lines; cast for JSX.
const ConnectionProvider = ConnectionProviderImpl as FC<any>;
const WalletProvider = WalletProviderImpl as FC<any>;
const WalletModalProvider = WalletModalProviderImpl as FC<any>;
const WalletMultiButton = WalletMultiButtonImpl as FC<any>;

export const App: FC = () => {
  const endpoint = envRpc();
  const wallets = useMemo(
    () => [new PhantomWalletAdapter(), new SolflareWalletAdapter()],
    [],
  );

  return (
    <ConnectionProvider endpoint={endpoint}>
      <WalletProvider wallets={wallets} autoConnect={false}>
        <WalletModalProvider>
          <header>
            <div>
              <h1>ProofForge · Solana dApp UI</h1>
              <p>
                wallet-adapter + web3.js · StateCell-shaped PF IDL · local validator default
              </p>
            </div>
            <WalletMultiButton />
          </header>
          <p className="banner">
            Backend is <strong>ProofForge</strong>: write ProgramV1, then{" "}
            <code>pf build --target solana</code> → <code>*.idl.json</code> + <code>*.so</code>.
            Deploy with <code>pf deploy --network local</code> (public RPC broadcast refused in pf
            v0). This UI only talks to a local validator + wallet — it is not an Anchor/Rust
            scaffold. Guide: <code>docs/product/09-solana-agent-playbook.md</code> ·{" "}
            <code>docs/product/10-solana-dapp-frontend.md</code>.
          </p>
          <DappPanel />
        </WalletModalProvider>
      </WalletProvider>
    </ConnectionProvider>
  );
};
