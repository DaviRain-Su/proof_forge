/**
 * Studio bridge client — talks to the LOCAL gate bridge
 * (proofship/rwa-share-v1/studio-bridge/server.mjs, default :5198).
 * The bridge runs the real proof-forge-next gate on this machine.
 * When the bridge is down (e.g. the static Pages deployment), the UI
 * degrades to showing the last real gate report — never a fabricated pass.
 */

export type GateRunResult = {
  ok: boolean;
  stage: "check" | "build" | "inspect" | "done";
  check?: string;
  build?: string;
  inspect?: string;
  error?: string;
};

const CANDIDATE_BASES = ["/api", "http://127.0.0.1:5198/api"];

let resolvedBase: string | null = null;
let cachedAgent: string | null = null;

async function probe(base: string): Promise<boolean> {
  try {
    const res = await fetch(`${base}/health`, { signal: AbortSignal.timeout(1500) });
    if (!res.ok) return false;
    const body = (await res.json()) as { ok?: boolean; agent?: string };
    cachedAgent = body.agent ?? null;
    return body.ok === true;
  } catch {
    return false;
  }
}

export function bridgeAgent(): string | null {
  return cachedAgent;
}

export async function bridgeBase(): Promise<string | null> {
  if (resolvedBase) return resolvedBase;
  for (const base of CANDIDATE_BASES) {
    if (await probe(base)) {
      resolvedBase = base;
      return base;
    }
  }
  return null;
}

export type AgentDraftResult =
  | { ok: true; lane: string; file: string; module: string; source: string; workdir: string }
  | { ok: false; lane?: string; error: string; stderrTail?: string; agentText?: string };

export type LaneInfo = { name: string; kind: "acp" | "exec"; cmd: string; available: boolean };

export async function listLanes(): Promise<{ default: string; lanes: LaneInfo[] } | null> {
  const base = await bridgeBase();
  if (!base) return null;
  try {
    const res = await fetch(`${base}/agent/lanes`, { signal: AbortSignal.timeout(5000) });
    const body = (await res.json()) as { default: string; lanes: LaneInfo[] };
    return body;
  } catch {
    return null;
  }
}

export async function runAgentDraft(nl: string, lane?: string): Promise<AgentDraftResult | null> {
  const base = await bridgeBase();
  if (!base) return null;
  try {
    const res = await fetch(`${base}/agent/draft`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ nl, lane }),
      signal: AbortSignal.timeout(480_000),
    });
    return (await res.json()) as AgentDraftResult;
  } catch {
    return null;
  }
}

export async function runGate(module: string, source: string): Promise<GateRunResult | null> {
  const base = await bridgeBase();
  if (!base) return null;
  try {
    const res = await fetch(`${base}/gate`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ module, source }),
      signal: AbortSignal.timeout(240_000),
    });
    return (await res.json()) as GateRunResult;
  } catch {
    return null;
  }
}
