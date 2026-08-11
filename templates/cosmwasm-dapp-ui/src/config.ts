export type CwNetwork = {
  id: string;
  label: string;
  rpcUrl: string;
  honesty: string;
};

export const NETWORKS: CwNetwork[] = [
  {
    id: "cosmwasm.local.mock",
    label: "Local cosmwasm-vm mock",
    rpcUrl: "mock://cosmwasm-vm",
    honesty: "Engineering mock via pf test -t cosmwasm — not wasmd chain RPC",
  },
  {
    id: "cosmwasm.testnet.catalog-only",
    label: "Cosmos testnet (catalog)",
    rpcUrl: "https://rpc.cosmos.directory/cosmoshub",
    honesty: "Catalog placeholder — pf deploy --broadcast refused in v0",
  },
];

export const DEFAULT_NETWORK = NETWORKS[0]!;
