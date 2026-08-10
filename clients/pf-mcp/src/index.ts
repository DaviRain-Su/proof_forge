/**
 * ProofForge remote MCP server (Cloudflare Workers).
 *
 * Streamable HTTP remote MCP for coding agents:
 *   - Transport at POST /mcp
 *   - Public, no API key (v0)
 *   - Docs / catalog / PF-target guidance (Solana = ProgramV1 + pf CLI, not Anchor MCP)
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
const SERVER_VERSION = "0.3.0";

/** In-product Solana knowledge for PF agents (not a pointer to external MCP). */
const SOLANA_PF = {
  contractPath: "ProofForge ProgramV1 + pf CLI (not Anchor/Rust scaffold)",
  frontendTemplate: "templates/solana-dapp-ui",
  docs: [
    "09-solana-agent-playbook.md",
    "10-solana-dapp-frontend.md",
    "solana-local-walkthrough.md",
  ],
  ixEncoding: {
    schema: "proof-forge.solana.ix-data.v1",
    layout: "handlerId_u64le + params_u64le_sequence",
    notAnchorSighash: true,
    detail:
      "Instruction data = u64 little-endian handlerId (from *.idl.json), then each non-Principal scalar param as u64 LE (narrow ints zero-extended). Do NOT use Anchor 8-byte sighash discriminators with PF ELF.",
  },
  artifacts: {
    forFrontend: ["*.idl.json", "deployment.json (after local deploy)"],
    forCliDeploy: ["*.so", "manifest.json", "evidence.json"],
    engineeringOnly: ["*.s", "*.cpi-*.json"],
  },
  safety: [
    "public Solana RPC broadcast refused in pf v0",
    "Principal wire identity ≠ Solana pubkey globally",
    "no private keys in MCP/chat/git",
    "engineering only — not formal/hermetic/mainnet",
  ],
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
          "pf_solana_ix_codec",
          "pf_solana_artifacts",
        ],
        liveDemo: LIVE,
        solana: SOLANA_PF,
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
                "# edit Lean ProgramV1 — not Anchor/Cargo",
                "pf build && pf verify && pf test",
                "pf deploy --network local",
                "cp build/**/**.idl.json templates/solana-dapp-ui/public/artifacts/",
                "cd templates/solana-dapp-ui && npm i && npm run dev",
                "# see pf_solana_scaffold / pf_solana_ix_codec",
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
- Use \`pf_solana_scaffold\`, \`pf_solana_ix_codec\`, \`pf_solana_artifacts\` for Solana (PF path).
- This remote server does **not** compile, does **not** hold keys, and does **not** broadcast.

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

## Solana notes (ProofForge-first)
- **Contracts are written in ProofForge ProgramV1**, compiled with \`pf build --target solana\`.
- Do **not** start an Anchor/Cargo program as the primary contract path.
- Ladder: \`pf setup -t solana\` → \`pf new … -t solana\` → edit Lean → \`pf build\` → \`pf verify\` → \`pf test\`.
- Deploy: \`pf deploy --network local\` (save-only). \`--broadcast\` only with loopback RPC.
- Frontend: \`templates/solana-dapp-ui\` consumes \`*.idl.json\` (ix-data = handlerId u64 LE + u64 params).
- Principal wire identity ≠ Solana pubkey globally.
- External Solana Rust/Anchor docs MCP is **out of the default agent path**; PF MCP already summarizes ix encoding + artifacts.

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
                "pf new hello --target solana && cd hello",
                "# edit ProgramV1 Lean source (not Anchor)",
                "pf build && pf verify --target solana",
                "pf test --target solana",
                "pf deploy --network local",
                "cp <out>/*.idl.json templates/solana-dapp-ui/public/artifacts/",
                "cd templates/solana-dapp-ui && npm i && npm run dev",
                "# docs: pf_get_doc id=09-solana-agent-playbook.md | 10-solana-dapp-frontend.md",
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
    "pf_solana_scaffold",
    {
      description:
        "Solana target scaffold using ProofForge only: write ProgramV1, pf setup/new/build/verify/test/deploy, then templates/solana-dapp-ui. Not an Anchor/Rust path.",
      inputSchema: z.object({
        includeFrontend: z
          .boolean()
          .optional()
          .describe("Include frontend template steps (default true)"),
      }),
    },
    async ({ includeFrontend }) => {
      const row = targetById("solana");
      const fe = includeFrontend !== false;
      return textResult({
        schema: "proof-forge.mcp.solana-scaffold.v1",
        target: "solana",
        contractPath: SOLANA_PF.contractPath,
        catalog: row,
        docs: SOLANA_PF.docs,
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
          "# edit Lean ProgramV1 sources — do not create Anchor/Cargo program",
          "pf build",
          "pf verify",
          "pf test",
          "pf deploy --network local",
        ],
        monorepoExample: [
          "pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol",
          "pf verify --target solana -o build/v2/sc-sol",
        ],
        frontend: fe
          ? {
              template: SOLANA_PF.frontendTemplate,
              steps: [
                "cp <out>/*.idl.json templates/solana-dapp-ui/public/artifacts/",
                "write public/deployment.json after local deploy (see deployment.example.json)",
                "cd templates/solana-dapp-ui && npm install && npm run dev",
              ],
              guide: "docs/product/10-solana-dapp-frontend.md",
            }
          : undefined,
        ixEncoding: SOLANA_PF.ixEncoding,
        safety: SOLANA_PF.safety,
        edgeNote:
          "Remote MCP is guidance-only. Compile/test/deploy with local pf + toolchains.",
      });
    },
  );

  server.registerTool(
    "pf_solana_ix_codec",
    {
      description:
        "Summarize ProofForge Solana instruction-data encoding for agents and frontends. PF uses handlerId u64 LE + u64 LE params — NOT Anchor sighash. Optional: encode a sample payload.",
      inputSchema: z.object({
        handlerId: z.number().int().min(0).optional(),
        params: z.array(z.string()).optional()
          .describe("Decimal u64 strings, e.g. [\"5\"] for increment delta"),
      }),
    },
    async ({ handlerId, params }) => {
      const enc = SOLANA_PF.ixEncoding;
      let sample: { hex: string; bytes: number[] } | undefined;
      if (handlerId !== undefined) {
        const ps = (params ?? []).map((s) => {
          const n = BigInt(s);
          if (n < 0n || n > 0xffff_ffff_ffff_ffffn) {
            throw new Error(`param out of u64 range: ${s}`);
          }
          return n;
        });
        const out = new Uint8Array(8 + ps.length * 8);
        const view = new DataView(out.buffer);
        view.setBigUint64(0, BigInt(handlerId), true);
        ps.forEach((p, i) => view.setBigUint64(8 + i * 8, p, true));
        const hex = Array.from(out)
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        sample = { hex, bytes: Array.from(out) };
      }
      return textResult({
        schema: "proof-forge.mcp.solana-ix-codec.v1",
        ...enc,
        example: {
          stateCell: {
            init: "handlerId=0 then u64 initial",
            increment: "handlerId=1 then u64 delta",
            get: "handlerId=2 (no params)",
          },
          note: "Exact handlerId values come from the program's *.idl.json after pf build.",
        },
        sample,
        frontendHelper: "templates/solana-dapp-ui/src/ix.ts → encodePfIxData",
        antiPatterns: [
          "Anchor sha256('global:name')[0..8] discriminators",
          "Borsh-only layouts without PF handlerId prefix",
          "Assuming Principal params are 32-byte pubkeys in ix data without PF wire rules",
        ],
      });
    },
  );

  server.registerTool(
    "pf_solana_artifacts",
    {
      description:
        "Explain pf build --target solana output files: which go to the frontend template vs CLI deploy/verify. PF-first; no external MCP.",
      inputSchema: z.object({
        programName: z
          .string()
          .optional()
          .describe("Artifact stem, default StateCell"),
      }),
    },
    async ({ programName }) => {
      const name = (programName ?? "StateCell").trim() || "StateCell";
      return textResult({
        schema: "proof-forge.mcp.solana-artifacts.v1",
        buildCommand: `pf build <Source.lean> --module <Module> --target solana -o <out>`,
        files: [
          {
            path: `${name}.idl.json`,
            role: "frontend + agents",
            requiredForUi: true,
            note: "handlerId, instruction names, account roles",
          },
          {
            path: `${name}.so`,
            role: "CLI deploy / Mollusk",
            requiredForUi: false,
          },
          {
            path: `${name}.s`,
            role: "debug asm",
            requiredForUi: false,
          },
          {
            path: "manifest.json",
            role: "OutputSet / pf verify",
            requiredForUi: false,
          },
          {
            path: "evidence.json",
            role: "engineering evidence note",
            requiredForUi: false,
          },
          {
            path: `${name}.cpi-*.json`,
            role: "engineering intermediate",
            requiredForUi: false,
          },
        ],
        uiCopy: [
          `cp <out>/${name}.idl.json templates/solana-dapp-ui/public/artifacts/`,
          "after deploy: write templates/solana-dapp-ui/public/deployment.json",
        ],
        verify: "pf verify --target solana -o <out>",
        deploy: "pf deploy --network local -o <out>",
        template: SOLANA_PF.frontendTemplate,
        docs: SOLANA_PF.docs,
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
    Streamable HTTP remote MCP for agents (docs · catalog · PF Solana/EVM/Aleo guidance).
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
    <tr><td><code>pf_solana_scaffold</code></td><td>Solana PF ladder + frontend template</td></tr>
    <tr><td><code>pf_solana_ix_codec</code></td><td>PF ix-data encoding (handlerId u64 LE)</td></tr>
    <tr><td><code>pf_solana_artifacts</code></td><td>build outputs → UI vs CLI</td></tr>
  </table>
  <h2>Solana (ProofForge path)</h2>
  <p>
    Contracts: <strong>ProgramV1 + <code>pf build --target solana</code></strong> (not Anchor).
    Frontend: <code>templates/solana-dapp-ui</code>. Tools: <code>pf_solana_scaffold</code>,
    <code>pf_solana_ix_codec</code>, <code>pf_solana_artifacts</code>.
  </p>
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
