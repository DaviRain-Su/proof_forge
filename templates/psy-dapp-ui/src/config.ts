import type { PsyAbi, PsyDeployment } from "./types";

export async function loadDeployment(): Promise<PsyDeployment | null> {
  try {
    const r = await fetch("/deployment.json", { cache: "no-store" });
    if (!r.ok) return null;
    return (await r.json()) as PsyDeployment;
  } catch {
    return null;
  }
}

export async function loadAbi(): Promise<PsyAbi | null> {
  // Prefer deployment-adjacent name, then default StateCell
  for (const path of [
    "/artifacts/StateCell.abi.json",
    "/artifacts/program.abi.json",
  ]) {
    try {
      const r = await fetch(path, { cache: "no-store" });
      if (r.ok) return (await r.json()) as PsyAbi;
    } catch {
      /* try next */
    }
  }
  return null;
}
