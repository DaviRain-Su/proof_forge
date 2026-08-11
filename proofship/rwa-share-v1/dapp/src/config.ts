import type { Abi } from "viem";
import {
  ANVIL_LOCAL,
  XLAYER_TESTNET,
  presetByChainId,
  presetById,
  type ChainPreset,
} from "./chains";
import type { DeploymentFile, GateReport } from "./types";

export { CHAIN_PRESETS, walletAddEthereumChainParams } from "./chains";
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
  const res = await fetch("/artifacts/RwaShareRegistry.abi.json");
  if (!res.ok) throw new Error("missing /artifacts/RwaShareRegistry.abi.json");
  return (await res.json()) as Abi;
}

export async function loadBytecode(): Promise<`0x${string}` | null> {
  try {
    const res = await fetch("/artifacts/RwaShareRegistry.bin", { cache: "no-store" });
    if (!res.ok) return null;
    const text = (await res.text()).trim().replace(/\s+/g, "");
    return (text.startsWith("0x") ? text : `0x${text}`) as `0x${string}`;
  } catch {
    return null;
  }
}

export async function loadGateReport(): Promise<GateReport | null> {
  try {
    const res = await fetch("/gate-report.json", { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as GateReport;
  } catch {
    return null;
  }
}

/** VITE_NETWORK_ID selects a networks.v1.json preset; default = X Layer testnet. */
export function envNetworkPreset(): ChainPreset | null {
  const id = (import.meta.env.VITE_NETWORK_ID ?? "").trim();
  if (!id) return null;
  return presetById(id) ?? null;
}

export function envChainId(): number {
  const fromEnv = Number(import.meta.env.VITE_CHAIN_ID ?? "");
  if (Number.isFinite(fromEnv) && fromEnv > 0) return fromEnv;
  return (envNetworkPreset() ?? XLAYER_TESTNET).chainId;
}

export function envRpc(): string {
  const explicit = (import.meta.env.VITE_RPC_URL ?? "").trim();
  if (explicit) return explicit.replace(/\/$/, "");
  const preset =
    envNetworkPreset() ?? presetByChainId(envChainId()) ?? XLAYER_TESTNET;
  return preset.rpcUrls[0].replace(/\/$/, "");
}

export function envChainPreset(): ChainPreset {
  return (
    envNetworkPreset() ??
    presetByChainId(envChainId()) ??
    (envChainId() === ANVIL_LOCAL.chainId ? ANVIL_LOCAL : XLAYER_TESTNET)
  );
}

export function envAddress(): `0x${string}` | null {
  const a = (import.meta.env.VITE_CONTRACT_ADDRESS ?? "").trim();
  if (!a) return null;
  return (a.startsWith("0x") ? a : `0x${a}`) as `0x${string}`;
}
