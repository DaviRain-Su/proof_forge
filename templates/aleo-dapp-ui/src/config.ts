import { Network } from "@provablehq/aleo-types";

/** Default matches the live ProofForge Testnet demo program. */
export const DEFAULT_PROGRAM_ID = "pfdemo336641.aleo";

export function programId(): string {
  return (import.meta.env.VITE_ALEO_PROGRAM_ID ?? DEFAULT_PROGRAM_ID).trim();
}

export function networkFromEnv(): Network {
  const raw = (import.meta.env.VITE_ALEO_NETWORK ?? "testnet").trim().toLowerCase();
  if (raw === "mainnet") return Network.MAINNET;
  if (raw === "canary") return Network.CANARY;
  return Network.TESTNET;
}

export function networkPath(): string {
  const n = networkFromEnv();
  if (n === Network.MAINNET) return "mainnet";
  if (n === Network.CANARY) return "canary";
  return "testnet";
}

export function apiBase(): string {
  return (import.meta.env.VITE_ALEO_API ?? "https://api.explorer.provable.com/v1").replace(
    /\/$/,
    "",
  );
}

export function feeMicrocredits(): number {
  const n = Number(import.meta.env.VITE_ALEO_FEE_MICROCREDITS ?? "100000");
  return Number.isFinite(n) && n >= 0 ? n : 100000;
}

export function explorerProgramUrl(id: string): string {
  const net = networkPath();
  if (net === "mainnet") {
    return `https://explorer.provable.com/program/${id}`;
  }
  return `https://testnet.explorer.provable.com/program/${id}`;
}

export function explorerTxUrl(txId: string): string {
  const net = networkPath();
  if (net === "mainnet") {
    return `https://explorer.provable.com/transaction/${txId}`;
  }
  return `https://testnet.explorer.provable.com/transaction/${txId}`;
}
