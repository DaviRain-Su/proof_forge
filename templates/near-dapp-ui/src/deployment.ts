/** Optional public/deployment.json from `pf write-ui-json -t near`. */
export type NearUiDeployment = {
  schema?: string;
  target?: string;
  network?: string;
  rpcUrl?: string;
  program?: string;
  contractId?: string;
  wasmSha256?: string;
  notes?: string[];
};

export async function loadDeployment(): Promise<NearUiDeployment | null> {
  try {
    const r = await fetch("/deployment.json");
    if (!r.ok) return null;
    return (await r.json()) as NearUiDeployment;
  } catch {
    return null;
  }
}
