import type { Abi } from "viem";
import {
  ANVIL_LOCAL,
  presetByChainId,
  presetById,
  type ChainPreset,
} from "./chains";
import type { DeploymentFile } from "./types";

export const DEFAULT_RPC = ANVIL_LOCAL.rpcUrls[0];
export const DEFAULT_CHAIN_ID = ANVIL_LOCAL.chainId;
/** Anvil account #0 — local demo only. Never use on public nets. */
export const ANVIL_ACCOUNT0 =
  "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const;

export {
  ANVIL_LOCAL,
  XLAYER_TESTNET,
  XLAYER_MAINNET,
  CHAIN_PRESETS,
  presetByChainId,
  presetById,
  walletAddEthereumChainParams,
} from "./chains";
export type { ChainPreset } from "./chains";

export async function loadDeployment(): Promise<DeploymentFile | null> {
  try {
    const res = await fetch("/deployment.json", { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as DeploymentFile;
  } catch {
    return null;
  }
}

export async function loadDefaultAbi(): Promise<Abi> {
  const res = await fetch("/artifacts/StateCell.abi.json");
  if (!res.ok) throw new Error("missing /artifacts/StateCell.abi.json");
  return (await res.json()) as Abi;
}

/**
 * Optional `VITE_NETWORK_ID` = networks.v1.json id (e.g. evm.xlayer.testnet).
 * Overrides default chain when VITE_CHAIN_ID / VITE_RPC_URL are unset.
 */
export function envNetworkPreset(): ChainPreset | null {
  const id = (import.meta.env.VITE_NETWORK_ID ?? "").trim();
  if (!id) return null;
  return presetById(id) ?? null;
}

export function envChainId(): number {
  const fromEnv = Number(import.meta.env.VITE_CHAIN_ID ?? "");
  if (Number.isFinite(fromEnv) && fromEnv > 0) return fromEnv;
  const preset = envNetworkPreset();
  if (preset) return preset.chainId;
  return DEFAULT_CHAIN_ID;
}

export function envRpc(): string {
  const explicit = (import.meta.env.VITE_RPC_URL ?? "").trim();
  if (explicit) return explicit.replace(/\/$/, "");
  const preset =
    envNetworkPreset() ?? presetByChainId(envChainId()) ?? ANVIL_LOCAL;
  return preset.rpcUrls[0].replace(/\/$/, "");
}

export function envChainPreset(): ChainPreset {
  return (
    envNetworkPreset() ??
    presetByChainId(envChainId()) ??
    ANVIL_LOCAL
  );
}

export function envAddress(): `0x${string}` | null {
  const a = (import.meta.env.VITE_CONTRACT_ADDRESS ?? "").trim();
  if (!a) return null;
  return (a.startsWith("0x") ? a : `0x${a}`) as `0x${string}`;
}

export function envCtorInitial(): number {
  const n = Number(import.meta.env.VITE_CONSTRUCTOR_INITIAL ?? "7");
  return Number.isFinite(n) ? n : 7;
}
