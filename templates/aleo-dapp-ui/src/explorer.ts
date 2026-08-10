import { apiBase, networkPath } from "./config";

/** Read a public mapping value (e.g. pf_state_0 / 0u8). */
export async function readMapping(
  program: string,
  mapping: string,
  key: string,
): Promise<string> {
  const url = `${apiBase()}/${networkPath()}/program/${program}/mapping/${mapping}/${key}`;
  const res = await fetch(url);
  if (!res.ok) {
    const body = await res.text().catch(() => "");
    throw new Error(`mapping ${res.status}: ${url} ${body.slice(0, 200)}`);
  }
  const text = (await res.text()).trim();
  // API often returns JSON-encoded strings: "\"8u64\""
  try {
    const parsed = JSON.parse(text) as unknown;
    if (typeof parsed === "string") return parsed;
  } catch {
    /* plain */
  }
  return text.replace(/^"|"$/g, "");
}

export async function readStateCell(program: string): Promise<{
  count: string | null;
  initialized: string | null;
}> {
  const [count, initialized] = await Promise.all([
    readMapping(program, "pf_state_0", "0u8").catch(() => null),
    readMapping(program, "initialized", "0u8").catch(() => null),
  ]);
  return { count, initialized };
}
