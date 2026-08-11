/**
 * ProofShip dApp chain presets.
 * Source of truth for public nets: docs/product/networks.v1.json
 * Default product network: X Layer testnet (1952); local loop: Anvil.
 */

export type ChainPreset = {
  id: string;
  name: string;
  chainId: number;
  rpcUrls: readonly string[];
  nativeCurrency: { name: string; symbol: string; decimals: number };
  blockExplorers?: readonly { name: string; url: string }[];
  policy: "local-only" | "testnet-opt-in" | "mainnet-gated" | "metadata-only";
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

export const ANVIL_LOCAL: ChainPreset = {
  id: "evm.local.anvil",
  name: "Anvil (local)",
  chainId: 31337,
  rpcUrls: ["http://127.0.0.1:8545"],
  nativeCurrency: { name: "Ether", symbol: "ETH", decimals: 18 },
  policy: "local-only",
};

export const CHAIN_PRESETS: readonly ChainPreset[] = [
  XLAYER_TESTNET,
  ANVIL_LOCAL,
] as const;

export function presetByChainId(chainId: number): ChainPreset | undefined {
  return CHAIN_PRESETS.find((c) => c.chainId === chainId);
}

export function presetById(id: string): ChainPreset | undefined {
  const needle = id.trim().toLowerCase();
  return CHAIN_PRESETS.find((c) => c.id.toLowerCase() === needle);
}

export function walletAddEthereumChainParams(preset: ChainPreset) {
  return {
    chainId: `0x${preset.chainId.toString(16)}`,
    chainName: preset.name,
    nativeCurrency: preset.nativeCurrency,
    rpcUrls: [...preset.rpcUrls],
    blockExplorerUrls: preset.blockExplorers?.map((e) => e.url) ?? [],
  };
}
