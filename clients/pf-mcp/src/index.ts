/**
 * ProofForge remote MCP server (Cloudflare Workers).
 *
 * Shape mirrors Solana Developer MCP (https://mcp.solana.com/mcp):
 *   - Streamable HTTP transport at POST /mcp
 *   - Public, no API key (v0)
 *   - Docs / catalog / agent-guidance tools for coding agents
 *
 * This edge surface does NOT spawn Lean/CLI binaries (Workers cannot).
 * Local compile/deploy stays on:
 *   - stdio MCP: tools/mcp/proof_forge_mcp_server.py
 *   - developer CLI: pf / proof-forge-next
 */
import { McpServer } from "@modelcontextprotocol/server";
import { createMcpHandler } from "agents/mcp/server";
import { z } from "zod";
import {
  CATALOG,
  getDoc,
  listDocs,
  searchDocs,
  targetById,
} from "./content";

const SERVER_NAME = "proof-forge-mcp";
const SERVER_VERSION = "0.2.0";

const SOLANA_OFFICIAL = {
  name: "Solana Developer MCP",
  landing: "https://mcp.solana.com/",
  endpoint: "https://mcp.solana.com/mcp",
  transport: "streamable-http",
  auth: "none",
  tools: [
    "list_sections",
    "get_documentation",
    "Solana_Documentation_Search",
    "Solana_Expert__Ask_For_Help",
    "program_autofixer",
  ],
  connect: {
    codex: "codex mcp add solana-mcp --url https://mcp.solana.com/mcp",
    claude:
      "claude mcp add --transport http solana-mcp https://mcp.solana.com/mcp",
    cursor: "npx -y mcp-remote https://mcp.solana.com/mcp",
  },
  note:
    "Official Solana docs + Anchor/Pinocchio program_autofixer. Connect alongside ProofForge MCP; this Worker does not proxy Solana tools.",
};

const LIVE = {
  program: "pfdemo336641.aleo",
  deployTx: "at147hjftmt294hrdgy7hfkjzn69ryxj3j2ank4jxl4u9qn8vl6nvqs73a5mt",
  executeTx: "at1j4g47meu322csew7vdlwx5x3hrpfaq0fftmet3zphdyzvxfanczsns58fd",
  state: "pf_state_0[0]=8u64, initialized[0]=true",
  asciinema: "https://asciinema.org/a/1262697",
  explorerProgram: "https://testnet.explorer.provable.com/program/pfdemo336641.aleo",
  explorerDeploy:
    "https://testnet.explorer.provable.com/transaction/at147hjftmt294hrdgy7hfkjzn69ryxj3j2ank4jxl4u9qn8vl6nvqs73a5mt",
  explorerExecute:
    "https://testnet.explorer.provable.com/transaction/at1j4g47meu322csew7vdlwx5x3hrpfaq0fftmet3zphdyzvxfanczsns58fd",
  leoMin: "4.4.1",
};

function textResult(payload: unknown) {
  const text =
    typeof payload === "string" ? payload : JSON.stringify(payload, null, 2);
  return {
    content: [{ type: "text" as const, text }],
  };
}

function createServer() {
  const server = new McpServer({
    name: SERVER_NAME,
    version: SERVER_VERSION,
  });

  server.registerTool(
    "pf_health",
    {
      description:
        "Health / capability probe for the ProofForge remote MCP. Reports transport, boundaries, and live demo links.",
      inputSchema: z.object({}),
    },
    async () =>
      textResult({
        ok: true,
        server: SERVER_NAME,
        version: SERVER_VERSION,
        transport: "streamable-http",
        endpointPath: "/mcp",
        boundaries: {
          edge: "docs + catalog + agent guidance only",
          noNetworkBroadcast: true,
          noPrivateKeys: true,
          noMainnet: true,
          compileDeploy:
            "use local pf / proof-forge-next or stdio MCP (tools/mcp)",
        },
        tools: [
          "pf_health",
          "pf_list_docs",
          "pf_get_doc",
          "pf_search_docs",
          "pf_chain_catalog",
          "pf_target_info",
          "pf_agent_instructions",
          "pf_aleo_live_demo",
          "pf_cli_cheatsheet",
          "pf_solana_scaffold",
          "pf_solana_official_mcp",
        ],
        liveDemo: LIVE,
        companionMcps: {
          solanaOfficial: SOLANA_OFFICIAL,
        },
      }),
  );

  server.registerTool(
    "pf_list_docs",
    {
      description:
        "List bundled ProofForge product docs available on this remote MCP (ids for pf_get_doc).",
      inputSchema: z.object({}),
    },
    async () =>
      textResult({
        schema: "proof-forge.mcp.docs-index.v1",
        docs: listDocs(),
        note: "Snapshot bundled at deploy time; monorepo docs/ is source of truth.",
      }),
  );

  server.registerTool(
    "pf_get_doc",
    {
      description:
        "Fetch a bundled ProofForge doc by id (from pf_list_docs), e.g. '01-toolchain-install-surface.md' or 'chain-client-catalog.v1.json'.",
      inputSchema: z.object({
        id: z
          .string()
          .describe("Document id from pf_list_docs, or 'catalog'"),
      }),
    },
    async ({ id }) => {
      const doc = getDoc(id);
      if (!doc) {
        return textResult({
          ok: false,
          error: `unknown doc id '${id}'`,
          available: listDocs().map((d) => d.id),
        });
      }
      return textResult({
        ok: true,
        id: doc.id,
        title: doc.title,
        kind: doc.kind,
        content: doc.text,
      });
    },
  );

  server.registerTool(
    "pf_search_docs",
    {
      description:
        "Keyword search over bundled ProofForge product docs (Aleo, pf CLI, install, MCP, targets).",
      inputSchema: z.object({
        query: z.string().describe("Search query, e.g. 'aleo deploy broadcast'"),
        limit: z.number().int().min(1).max(20).optional(),
      }),
    },
    async ({ query, limit }) =>
      textResult({
        schema: "proof-forge.mcp.search.v1",
        query,
        hits: searchDocs(query, limit ?? 8),
      }),
  );

  server.registerTool(
    "pf_chain_catalog",
    {
      description:
        "Return the ProofForge chain-client catalog (targets, maturity, pfSurface mcpTools). Optional filter by target id.",
      inputSchema: z.object({
        target: z
          .string()
          .optional()
          .describe("Optional target id filter, e.g. aleo | solana | evm"),
        includeDesignOnly: z
          .boolean()
          .optional()
          .describe("Include design-only targets (default true on edge)"),
      }),
    },
    async ({ target, includeDesignOnly }) => {
      let targets = CATALOG.targets.slice();
      if (includeDesignOnly === false) {
        targets = targets.filter((t) => {
          const m = String(
            (t as { maturity?: string }).maturity ??
              (t as { status?: string }).status ??
              "",
          ).toLowerCase();
          return !m.includes("design");
        });
      }
      if (target && target.trim()) {
        const one = targetById(target);
        return textResult({
          schema: CATALOG.schema,
          filter: target,
          target: one,
          found: Boolean(one),
        });
      }
      return textResult({
        schema: CATALOG.schema,
        version: CATALOG.version,
        updated: CATALOG.updated,
        notes: CATALOG.notes,
        targets,
      });
    },
  );

  server.registerTool(
    "pf_target_info",
    {
      description:
        "Explain one ProofForge target for agents: catalog row + recommended local pf commands. Edge cannot compile.",
      inputSchema: z.object({
        target: z.string().describe("Target id, e.g. aleo"),
      }),
    },
    async ({ target }) => {
      const row = targetById(target);
      if (!row) {
        return textResult({
          ok: false,
          error: `unknown target '${target}'`,
          known: CATALOG.targets.map((t) => t.id),
        });
      }
      const id = String(row.id);
      const cheats =
        id === "aleo"
          ? [
              "pf setup --target aleo",
              "pf new hello --target aleo && cd hello",
              "pf build && pf run -- initialize 5u64",
              "pf deploy --network testnet",
              "pf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id <stem>",
              "Requires Leo 4.4.1+ for live Testnet base fees",
            ]
          : id === "solana"
            ? [
                "pf setup --target solana && pf doctor --target solana",
                "pf new hello --target solana && cd hello",
                "pf build && pf verify && pf test",
                "pf deploy --network local  # save-only; public RPC broadcast refused",
                "# companion: codex mcp add solana-mcp --url https://mcp.solana.com/mcp",
                "# see pf_solana_scaffold + 09-solana-agent-playbook.md",
              ]
            : id === "evm"
              ? [
                  "pf setup --target evm",
                  "pf new hello --target evm && cd hello",
                  "pf build && pf test",
                  "pf deploy --network local --broadcast  # Anvil/local only",
                ]
              : [
                  `pf setup --target ${id}`,
                  `pf new hello --target ${id}`,
                  "pf build",
                  "See catalog pfSurface for mcpTools / local modes",
                ];
      return textResult({
        ok: true,
        target: row,
        localCommands: cheats,
        edgeNote:
          "Remote MCP is guidance-only. Run compile/test/deploy on a machine with pf + toolchains.",
      });
    },
  );

  server.registerTool(
    "pf_agent_instructions",
    {
      description:
        "Canonical instructions for coding agents using ProofForge (remote MCP + local pf). Prefer these over model memory.",
      inputSchema: z.object({}),
    },
    async () =>
      textResult(`# ProofForge agent instructions

For ProofForge / multi-chain ProgramV1 work, prefer these MCP tools and the local \`pf\` CLI over model memory.

## Remote MCP (this server)
- Use \`pf_list_docs\` then \`pf_get_doc\` / \`pf_search_docs\` for product contracts.
- Use \`pf_chain_catalog\` / \`pf_target_info\` before choosing a chain.
- Use \`pf_cli_cheatsheet\` for command sequences.
- Use \`pf_aleo_live_demo\` for the published Aleo Testnet evidence links.
- Use \`pf_solana_scaffold\` + \`pf_solana_official_mcp\` for Solana target ladder and dual-MCP wiring.
- This remote server does **not** compile, does **not** hold keys, and does **not** broadcast.

## Official Solana Developer MCP (companion — not proxied here)
- Endpoint: \`https://mcp.solana.com/mcp\` (Streamable HTTP, no API key).
- Connect: \`codex mcp add solana-mcp --url https://mcp.solana.com/mcp\`.
- Tools: docs list/get/search, expert help, \`program_autofixer\` (Anchor + Pinocchio Rust).
- When reviewing hand-written Solana Rust, run \`program_autofixer\`, apply fixes, re-run until clean.
- PF Lean→sBPF path is separate: do not treat autofixer as a substitute for \`pf build/verify\`.

## Local execution (developer machine)
- Install/use \`pf\` (\`proof-forge-pf\` on crates.io) + \`proof-forge-next\` compiler.
- Solana offline verify: \`proof-forge-solana-client\` (\`pf verify -t solana\`).
- Stdio MCP (full CLI tools): monorepo \`tools/mcp/proof_forge_mcp_server.py\`.
- Never paste private keys into chat, git, or remote MCP tool args.
- Mainnet / public Solana RPC broadcast is refused by \`pf\` v0. Default deploy is save-only.
- Success is **not** formal / hermetic / mainnet evidence.

## Aleo notes
- Live Testnet needs Leo **4.4.1+** (4.0.2 under-estimates base fee).
- Broadcast: \`--broadcast --private-key-env NAME --program-id <stem>\`.
- Keep the same \`--program-id\` for deploy and execute.

## Solana notes
- Ladder: \`pf setup -t solana\` → \`pf new … -t solana\` → \`pf build\` → \`pf verify\` → \`pf test\`.
- Deploy: \`pf deploy --network local\` (package only). \`--broadcast\` only with loopback RPC.
- Principal wire identity ≠ Solana pubkey globally.
- Dual MCP: ProofForge for PF surface; Solana MCP for ecosystem docs/Rust review.

## Safety
- No default network broadcast on MCP.
- No well-known Leo dev key on broadcast.
- Prefer testnet/devnet/local only.
`),
  );

  server.registerTool(
    "pf_aleo_live_demo",
    {
      description:
        "Return the published Aleo Testnet live demo evidence (program, txs, explorer, public asciinema).",
      inputSchema: z.object({}),
    },
    async () =>
      textResult({
        schema: "proof-forge.mcp.aleo-live-demo.v1",
        network: "testnet",
        ...LIVE,
        claims:
          "engineering demo only — not formal/hermetic/mainnet; private keys never embedded",
      }),
  );

  server.registerTool(
    "pf_cli_cheatsheet",
    {
      description:
        "Short pf / proof-forge-next command cheatsheet for agents (setup, new, build, test, deploy).",
      inputSchema: z.object({
        target: z
          .string()
          .optional()
          .describe("Optional focus target: aleo | solana | evm | ..."),
      }),
    },
    async ({ target }) => {
      const t = (target ?? "aleo").toLowerCase();
      const common = [
        "export PROOF_FORGE_CLI=/path/to/proof-forge-next",
        "export PATH=\"$HOME/.cargo/bin:$PATH\"  # pf, leo, ...",
        "pf setup --target <target>",
        "pf doctor --target <target>",
        "pf new hello --target <target> && cd hello",
        "pf build",
        "pf test   # when target supports it",
      ];
      const focused =
        t === "aleo"
          ? [
              "pf run -- initialize 5u64",
              "pf run -- increment 3u64",
              "pf deploy --network testnet                 # save-only",
              "pf execute --network testnet -- initialize 5u64",
              "pf deploy --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id myprog01",
              "pf execute --network testnet --broadcast --private-key-env PF_ALEO_TESTNET_KEY --program-id myprog01 -- initialize 5u64",
              "# Leo >= 4.4.1 required for current testnet fees",
            ]
          : t === "solana"
            ? [
                "pf setup --target solana && pf doctor --target solana",
                "pf new hello --target solana && cd hello && pf build",
                "pf verify --target solana",
                "pf test --target solana",
                "pf deploy --network local",
                "# pf deploy --network local --broadcast --endpoint http://127.0.0.1:8899",
                "# companion: codex mcp add solana-mcp --url https://mcp.solana.com/mcp",
                "# docs: pf_get_doc id=09-solana-agent-playbook.md",
              ]
            : t === "evm"
              ? [
                  "pf test --target evm",
                  "pf deploy --network local --broadcast",
                ]
              : [`# see pf_target_info for ${t}`];
      return textResult({
        target: t,
        common,
        focused,
        remoteMcp:
          "guidance only — run these commands on a host with toolchains installed",
      });
    },
  );


  server.registerTool(
    "pf_solana_official_mcp",
    {
      description:
        "How to connect the official Solana Developer MCP (https://mcp.solana.com/mcp) alongside ProofForge. Lists official tools (docs + program_autofixer). This Worker does not proxy Solana tools — agents must add the second MCP server.",
      inputSchema: z.object({}),
    },
    async () =>
      textResult({
        schema: "proof-forge.mcp.solana-official.v1",
        proofForgeMcp: {
          role: "PF catalog, pf CLI ladder, Solana target honesty",
          endpointPath: "/mcp",
        },
        solanaOfficial: SOLANA_OFFICIAL,
        dualMcpRecommended: true,
        routing: [
          "PF surface / maturity / pf commands → ProofForge tools (pf_solana_scaffold, pf_target_info)",
          "Solana ecosystem docs / Anchor-Pinocchio Rust review → official Solana tools",
          "Compile/test/deploy → local pf + toolchains (never edge MCP)",
        ],
        agentLoop:
          "For hand-written Anchor/Pinocchio Rust: call program_autofixer, apply fixes, re-run until clean. For PF ProgramV1→sBPF: use pf build/verify locally.",
      }),
  );

  server.registerTool(
    "pf_solana_scaffold",
    {
      description:
        "Solana target scaffold for agents: dual-MCP wiring, pf setup/new/build/verify/test/deploy ladder, install companions, and honesty boundaries. Prefer this before writing Solana-targeted PF projects.",
      inputSchema: z.object({
        includeOfficialMcp: z
          .boolean()
          .optional()
          .describe("Include official Solana MCP connect block (default true)"),
      }),
    },
    async ({ includeOfficialMcp }) => {
      const row = targetById("solana");
      const includeOfficial = includeOfficialMcp !== false;
      return textResult({
        schema: "proof-forge.mcp.solana-scaffold.v1",
        target: "solana",
        catalog: row,
        docs: [
          "09-solana-agent-playbook.md",
          "solana-local-walkthrough.md",
          "chain-client-catalog.v1.json",
        ],
        dualMcp: includeOfficial
          ? {
              proofForge: "this server (/mcp)",
              solanaOfficial: SOLANA_OFFICIAL,
            }
          : { proofForge: "this server (/mcp)" },
        install: [
          "cargo install proof-forge-pf --locked",
          "cargo install proof-forge-solana-client --locked",
          "export PROOF_FORGE_CLI=/path/to/proof-forge-next",
          'export PROOF_FORGE_SOLANA_CLIENT="$(command -v proof-forge-solana-client)"',
          "pf setup --target solana",
          "pf doctor --target solana",
        ],
        projectLadder: [
          "pf new hello --target solana && cd hello",
          "pf build",
          "pf verify",
          "pf test",
          "pf deploy --network local",
        ],
        monorepoExample: [
          "pf build Examples/StateCell.lean --module Examples.StateCell -t solana -o build/v2/sc-sol",
          "pf verify -t solana -o build/v2/sc-sol",
          "# optional host-heavy: just solana-runtime",
        ],
        safety: [
          "public Solana RPC broadcast refused in pf v0",
          "no private keys in MCP/chat/git",
          "Principal ≠ Solana pubkey globally",
          "engineering only — not formal/hermetic/mainnet",
        ],
        edgeNote:
          "Remote MCP is guidance-only. Run compile/test/deploy on a machine with pf + toolchains.",
      });
    },
  );

  return server;
}

const mcpFetch = createMcpHandler(createServer);

const LANDING = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>ProofForge Developer MCP</title>
  <style>
    :root { color-scheme: light dark; font-family: ui-sans-serif, system-ui, sans-serif; }
    body { max-width: 52rem; margin: 2rem auto; padding: 0 1.25rem; line-height: 1.5; }
    code, pre { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 0.92em; }
    pre { background: #1113; padding: 1rem; overflow: auto; border-radius: 8px; }
    a { color: inherit; }
    .pill { display:inline-block; padding: .15rem .55rem; border-radius: 999px; border: 1px solid #8884; font-size: .85rem; }
    table { border-collapse: collapse; width: 100%; }
    td, th { border-bottom: 1px solid #8883; text-align: left; padding: .4rem .3rem; vertical-align: top; }
  </style>
</head>
<body>
  <p class="pill">Remote MCP · Streamable HTTP · no API key (v0)</p>
  <h1>ProofForge Developer MCP</h1>
  <p>
    Coding-agent surface for ProofForge product docs, chain catalog, and CLI guidance —
    similar in shape to <a href="https://mcp.solana.com/">Solana Developer MCP</a>.
  </p>
  <h2>Live endpoint</h2>
  <pre>POST https://&lt;this-host&gt;/mcp
Transport: Streamable HTTP</pre>
  <h2>Connect</h2>
  <pre># Codex
codex mcp add proof-forge-mcp --url https://&lt;this-host&gt;/mcp

# Claude Code
claude mcp add --transport http proof-forge-mcp https://&lt;this-host&gt;/mcp

# Cursor / generic (mcp-remote proxy)
npx -y mcp-remote https://&lt;this-host&gt;/mcp</pre>
  <h2>Tools</h2>
  <table>
    <tr><th>Tool</th><th>Purpose</th></tr>
    <tr><td><code>pf_health</code></td><td>Capability probe + live demo links</td></tr>
    <tr><td><code>pf_list_docs</code> / <code>pf_get_doc</code> / <code>pf_search_docs</code></td><td>Product docs</td></tr>
    <tr><td><code>pf_chain_catalog</code> / <code>pf_target_info</code></td><td>Target metadata</td></tr>
    <tr><td><code>pf_agent_instructions</code></td><td>How agents should use PF</td></tr>
    <tr><td><code>pf_cli_cheatsheet</code></td><td>Local <code>pf</code> commands</td></tr>
    <tr><td><code>pf_aleo_live_demo</code></td><td>Published Aleo Testnet evidence</td></tr>
    <tr><td><code>pf_solana_scaffold</code></td><td>Solana <code>pf</code> ladder + dual-MCP wiring</td></tr>
    <tr><td><code>pf_solana_official_mcp</code></td><td>Official Solana MCP connect (docs + autofixer)</td></tr>
  </table>
  <h2>Companion: official Solana MCP</h2>
  <p>
    For Solana ecosystem docs and Anchor/Pinocchio <code>program_autofixer</code>, also connect
    <a href="https://mcp.solana.com/">Solana Developer MCP</a>:
  </p>
  <pre>codex mcp add solana-mcp --url https://mcp.solana.com/mcp
claude mcp add --transport http solana-mcp https://mcp.solana.com/mcp</pre>
  <p>ProofForge MCP does <strong>not</strong> proxy those tools — add both servers. See <code>pf_solana_scaffold</code>.</p>
  <h2>Boundaries</h2>
  <ul>
    <li>Edge MCP is <strong>guidance-only</strong> (no Lean/CLI spawn, no keys, no broadcast).</li>
    <li>Compile / deploy: local <code>pf</code> or monorepo stdio MCP <code>tools/mcp</code>.</li>
    <li>Not formal / hermetic / mainnet.</li>
  </ul>
  <h2>Live Aleo demo</h2>
  <ul>
    <li>Recording: <a href="https://asciinema.org/a/1262697">asciinema.org/a/1262697</a></li>
    <li>Program: <a href="https://testnet.explorer.provable.com/program/pfdemo336641.aleo">pfdemo336641.aleo</a></li>
  </ul>
  <p><a href="/health">/health</a> · <a href="/mcp">/mcp</a></p>
</body>
</html>`;

export default {
  async fetch(request: Request, env: unknown, ctx: ExecutionContext) {
    const url = new URL(request.url);

    if (url.pathname === "/" || url.pathname === "/index.html") {
      return new Response(LANDING, {
        headers: {
          "content-type": "text/html; charset=utf-8",
          "cache-control": "public, max-age=60",
        },
      });
    }

    if (
      url.pathname === "/health" ||
      url.pathname === "/health/" ||
      url.pathname === "/ready" ||
      url.pathname === "/ready/"
    ) {
      return Response.json(
        {
          ok: true,
          server: SERVER_NAME,
          version: SERVER_VERSION,
          mcp: "/mcp",
        },
        {
          headers: {
            "cache-control": "no-store",
            "access-control-allow-origin": "*",
          },
        },
      );
    }

    // MCP Streamable HTTP (and legacy lane) — typically /mcp
    if (url.pathname === "/mcp" || url.pathname.startsWith("/mcp/")) {
      return mcpFetch(request, env, ctx);
    }

    return new Response("Not found. Try / or /mcp\n", { status: 404 });
  },
} satisfies ExportedHandler;
