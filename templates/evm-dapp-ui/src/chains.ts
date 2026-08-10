/**
 * EVM chain presets for the minimal dApp template.
 * Source of truth for public nets: docs/product/networks.v1.json
 * Default product demo path remains local Anvil.
 */

export type ChainPreset = {
  id: string;
  name: string;
  chainId: number;
  rpcUrls: readonly string[];
  nativeCurrency: { name: string; symbol: string; decimals: number };
  blockExplorers?: readonly { name: string; url: string }[];
  /** PF network-catalog policy (informational). */
  policy: "local-only" | "testnet-opt-in" | "mainnet-gated" | "metadata-only";
};

export const ANVIL_LOCAL: ChainPreset = {
  id: "evm.local.anvil",
  name: "Anvil (local)",
  chainId: 31337,
  rpcUrls: ["http://127.0.0.1:8545"],
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  policy: "local-only",
};

export const XLAYER_TESTNET: ChainPreset = {
  id: "evm.xlayer.testnet",
  name: "X Layer testnet",
  chainId: 1952,
  rpcUrls: [
    "https://testrpc.xlayer.tech/terigon",
    "https://xlayertestrpc.okx.com/terigon",
  ],
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  blockExplorers: [
    {
      name: "OKX Web3 Explorer",
      url: "https://www.okx.com/web3/explorer/xlayer-test",
    },
  ],
  policy: "testnet-opt-in",
};

export const XLAYER_MAINNET: ChainPreset = {
  id: "evm.xlayer.mainnet",
  name: "X Layer mainnet",
  chainId: 196,
  rpcUrls: ["https://rpc.xlayer.tech", "https://xlayerrpc.okx.com"],
  nativeCurrency: { name: "OKB", symbol: "OKB", decimals: 18 },
  blockExplorers: [
    {
      name: "OKX Web3 Explorer",
      url: "https://www.okx.com/web3/explorer/xlayer",
    },
  ],
  policy: "mainnet-gated",
};

export const CHAIN_PRESETS: readonly ChainPreset[] = [
  ANVIL_LOCAL,
  XLAYER_TESTNET,
  XLAYER_MAINNET,
] as const;

export function presetByChainId(chainId: number): ChainPreset | undefined {
  return CHAIN_PRESETS.find((c) => c.chainId === chainId);
}

export function presetById(id: string): ChainPreset | undefined {
  const needle = id.trim().toLowerCase();
  return CHAIN_PRESETS.find((c) => c.id.toLowerCase() === needle);
}

/** wallet_addEthereumChain params (MetaMask / OKX Wallet). */
export function walletAddEthereumChainParams(preset: ChainPreset) {
  return {
    chainId: `0x${preset.chainId.toString(16)}`,
    chainName: preset.name,
    nativeCurrency: preset.nativeCurrency,
    rpcUrls: [...preset.rpcUrls],
    blockExplorerUrls: preset.blockExplorers?.map((e) => e.url) ?? [],
  };
}
