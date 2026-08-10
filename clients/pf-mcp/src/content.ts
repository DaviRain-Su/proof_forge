import {
  CATALOG_JSON,
  DOCS_INDEX_JSON,
  MARKDOWN,
  NETWORKS_JSON,
} from "./bundled";

export type DocEntry = {
  id: string;
  title: string;
  kind: "markdown" | "catalog";
  text: string;
};

export const CATALOG = CATALOG_JSON as unknown as {
  schema: string;
  version?: string;
  updated?: string;
  notes?: string[];
  targets: Array<Record<string, unknown>>;
  networksRef?: Record<string, unknown>;
};

export const NETWORKS = NETWORKS_JSON as unknown as {
  schema: string;
  version?: string;
  updated?: string;
  notes?: string[];
  policyEnum?: string[];
  networks: Array<Record<string, unknown>>;
  ecosystems?: Record<string, unknown>;
};

export const DOCS_INDEX = DOCS_INDEX_JSON as unknown as {
  schema: string;
  docs: Array<{ id: string; title: string; bytes: number; kind: string }>;
};

export function listDocs() {
  return DOCS_INDEX.docs;
}

export function getDoc(id: string): DocEntry | null {
  const clean = id.trim().replace(/^docs\//, "").replace(/^product\//, "");
  if (clean === "chain-client-catalog.v1.json" || clean === "catalog") {
    return {
      id: "chain-client-catalog.v1.json",
      title: "Chain client catalog",
      kind: "catalog",
      text: JSON.stringify(CATALOG, null, 2),
    };
  }
  if (
    clean === "networks.v1.json" ||
    clean === "networks" ||
    clean === "network-catalog"
  ) {
    return {
      id: "networks.v1.json",
      title: "Network catalog (X Layer / Anvil)",
      kind: "catalog",
      text: JSON.stringify(NETWORKS, null, 2),
    };
  }
  const text = MARKDOWN[clean];
  if (!text) return null;
  const meta = DOCS_INDEX.docs.find((d) => d.id === clean);
  return {
    id: clean,
    title: meta?.title ?? clean,
    kind: "markdown",
    text,
  };
}

export function filterNetworks(opts: {
  id?: string;
  targetFamily?: string;
  env?: string;
  chainId?: number;
}): {
  schema: string;
  version?: string;
  updated?: string;
  notes?: string[];
  ecosystems?: Record<string, unknown>;
  networks: Array<Record<string, unknown>>;
  filter: Record<string, unknown>;
  found: boolean;
} {
  const id = opts.id?.trim();
  const family = opts.targetFamily?.trim();
  const env = opts.env?.trim();
  const chainId = opts.chainId;
  let rows = NETWORKS.networks.slice();
  if (id) {
    rows = rows.filter(
      (n) => String(n.id ?? "").toLowerCase() === id.toLowerCase(),
    );
  }
  if (family) {
    rows = rows.filter(
      (n) =>
        String(n.targetFamily ?? "").toLowerCase() === family.toLowerCase(),
    );
  }
  if (env) {
    rows = rows.filter(
      (n) => String(n.env ?? "").toLowerCase() === env.toLowerCase(),
    );
  }
  if (typeof chainId === "number" && Number.isFinite(chainId)) {
    rows = rows.filter((n) => Number(n.chainId) === chainId);
  }
  return {
    schema: NETWORKS.schema,
    version: NETWORKS.version,
    updated: NETWORKS.updated,
    notes: NETWORKS.notes,
    ecosystems: NETWORKS.ecosystems,
    networks: rows,
    filter: {
      id: id || null,
      targetFamily: family || null,
      env: env || null,
      chainId: typeof chainId === "number" ? chainId : null,
    },
    found: rows.length > 0,
  };
}

export function searchDocs(
  query: string,
  limit = 8,
): Array<{ id: string; title: string; score: number; snippet: string }> {
  const q = query.trim().toLowerCase();
  if (!q) return [];
  const terms = q.split(/\s+/).filter(Boolean);
  const hits: Array<{
    id: string;
    title: string;
    score: number;
    snippet: string;
  }> = [];

  const corpus: Array<{ id: string; title: string; text: string }> = [
    {
      id: "chain-client-catalog.v1.json",
      title: "Chain client catalog",
      text: JSON.stringify(CATALOG),
    },
    {
      id: "networks.v1.json",
      title: "Network catalog (X Layer / Anvil)",
      text: JSON.stringify(NETWORKS),
    },
    ...Object.entries(MARKDOWN).map(([id, text]) => ({
      id,
      title: DOCS_INDEX.docs.find((d) => d.id === id)?.title ?? id,
      text,
    })),
  ];

  for (const doc of corpus) {
    const lower = doc.text.toLowerCase();
    let score = 0;
    for (const t of terms) {
      if (doc.id.toLowerCase().includes(t)) score += 5;
      if (doc.title.toLowerCase().includes(t)) score += 4;
      let idx = 0;
      let n = 0;
      while ((idx = lower.indexOf(t, idx)) !== -1 && n < 20) {
        n += 1;
        idx += t.length;
      }
      score += n;
    }
    if (score <= 0) continue;
    const first = terms.find((t) => lower.includes(t));
    let snippet = doc.text.slice(0, 240).replace(/\s+/g, " ").trim();
    if (first) {
      const at = lower.indexOf(first);
      const start = Math.max(0, at - 80);
      const end = Math.min(doc.text.length, at + 160);
      snippet = doc.text.slice(start, end).replace(/\s+/g, " ").trim();
      if (start > 0) snippet = "…" + snippet;
      if (end < doc.text.length) snippet = snippet + "…";
    }
    hits.push({ id: doc.id, title: doc.title, score, snippet });
  }

  hits.sort((a, b) => b.score - a.score || a.id.localeCompare(b.id));
  return hits.slice(0, Math.max(1, Math.min(limit, 20)));
}

export function targetById(id: string) {
  const needle = id.trim().toLowerCase();
  return (
    CATALOG.targets.find(
      (t) => String(t.id ?? "").toLowerCase() === needle,
    ) ?? null
  );
}

export function networkById(id: string) {
  const needle = id.trim().toLowerCase();
  return (
    NETWORKS.networks.find(
      (n) => String(n.id ?? "").toLowerCase() === needle,
    ) ?? null
  );
}
