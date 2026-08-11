import type { ShareFields } from "./template";
import type { GateRunResult } from "./bridge";

export type ChatMsg =
  | { role: "user"; text: string; at: string }
  | {
      role: "agent";
      kind: "draft";
      fields: ShareFields;
      program: string;
      source: string;
      note?: string | null;
      at: string;
    }
  | {
      role: "agent";
      kind: "gate";
      state: "running" | "pass" | "fail" | "offline";
      result?: GateRunResult;
      at: string;
    }
  | { role: "agent"; kind: "note"; text: string; at: string };

export type Launch = {
  id: string;
  title: string;
  createdAt: string;
  msgs: ChatMsg[];
  fields?: ShareFields;
  program?: string;
  source?: string;
};

const KEY = "proofship.launches.v1";

export function loadLaunches(): Launch[] {
  try {
    const raw = localStorage.getItem(KEY);
    if (!raw) return [];
    const parsed = JSON.parse(raw) as Launch[];
    return Array.isArray(parsed) ? parsed : [];
  } catch {
    return [];
  }
}

export function saveLaunches(launches: Launch[]): void {
  try {
    localStorage.setItem(KEY, JSON.stringify(launches.slice(0, 20)));
  } catch {
    /* storage full or blocked — non-fatal */
  }
}

export function newLaunch(): Launch {
  const id = `${Date.now().toString(36)}-${Math.random().toString(36).slice(2, 7)}`;
  return { id, title: "New launch", createdAt: new Date().toISOString(), msgs: [] };
}
