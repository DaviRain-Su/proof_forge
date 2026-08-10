import type { Abi } from "viem";
import type { DeploymentFile } from "./types";

export const DEFAULT_RPC = "http://127.0.0.1:8545";
export const DEFAULT_CHAIN_ID = 31337;
/** Anvil account #0 — local demo only. Never use on public nets. */
export const ANVIL_ACCOUNT0 =
  "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266" as const;

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

export function envRpc(): string {
  return (import.meta.env.VITE_RPC_URL ?? DEFAULT_RPC).replace(/\/$/, "");
}

export function envChainId(): number {
  const n = Number(import.meta.env.VITE_CHAIN_ID ?? DEFAULT_CHAIN_ID);
  return Number.isFinite(n) ? n : DEFAULT_CHAIN_ID;
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
