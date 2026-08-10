import type { DeploymentFile, PfIdl } from "./types";

export const DEFAULT_RPC = "http://127.0.0.1:8899";

export async function loadDeployment(): Promise<DeploymentFile | null> {
  try {
    const res = await fetch("/deployment.json", { cache: "no-store" });
    if (!res.ok) return null;
    return (await res.json()) as DeploymentFile;
  } catch {
    return null;
  }
}

export async function loadDefaultIdl(): Promise<PfIdl> {
  const res = await fetch("/artifacts/StateCell.idl.json");
  if (!res.ok) throw new Error("missing /artifacts/StateCell.idl.json — run pf build -t solana");
  return (await res.json()) as PfIdl;
}

export function envRpc(): string {
  return (import.meta.env.VITE_RPC_URL ?? DEFAULT_RPC).replace(/\/$/, "");
}

export function envProgramId(): string {
  return (import.meta.env.VITE_PROGRAM_ID ?? "").trim();
}

export function envStateAccount(): string {
  return (import.meta.env.VITE_STATE_ACCOUNT ?? "").trim();
}
