/**
 * Network presets — catalog-only for product v0.
 * Public broadcast stays refused in `pf deploy -t near`.
 * Default: local near-sandbox style RPC (engineering).
 */
export type NearNetwork = {
  id: string;
  label: string;
  rpcUrl: string;
  networkId: string;
  walletUrl?: string;
  explorerUrl?: string;
  honesty: string;
};

export const NETWORKS: NearNetwork[] = [
  {
    id: "near.local.sandbox",
    label: "Local near-sandbox",
    rpcUrl: "http://127.0.0.1:3030",
    networkId: "sandbox",
    honesty: "Engineering only — start via pf test -t near / near-sandbox",
  },
  {
    id: "near.testnet.catalog-only",
    label: "NEAR testnet (catalog)",
    rpcUrl: "https://rpc.testnet.near.org",
    networkId: "testnet",
    walletUrl: "https://testnet.mynearwallet.com",
    explorerUrl: "https://testnet.nearblocks.io",
    honesty: "Catalog RPC only — pf deploy --broadcast refused in v0",
  },
];

export const DEFAULT_NETWORK = NETWORKS[0]!;
