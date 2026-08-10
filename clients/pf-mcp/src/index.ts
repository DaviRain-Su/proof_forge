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
  filterNetworks,
  getDoc,
  listDocs,
  NETWORKS,
  searchDocs,
  targetById,
} from "./content";

const SERVER_NAME = "proof-forge-mcp";
const SERVER_VERSION = "0.3.6";

/** Psy: PF emits DPN only; deploy/wallet/SDK are official ecosystem. */
const PSY_PF = {
  contractPath: "ProofForge ProgramV1 + pf CLI → canonical *.dpn.json (not Dargo/.psy source)",
  profile: "psy-dpn-v1",
  deployable: false,
  zeroTool: true,
  docs: [
    "11-psy-agent-playbook.md",
    "12-psy-dapp-frontend.md",
    "psy-dpn-walkthrough.md",
    "10-psy.md",
  ],
  artifact: {
    schema: "proof-forge.psy.dpn-package.v1",
    file: "{programName}.dpn.json",
    mime: "application/json",
    encoding: "psyDpn",
    note: "Array of DPNFunctionCircuitDefinition (name, method_id, definitions, state_commands, …). Authority pin: PsyProtocol/psy-node DPN schema — not a Tool Lock binary.",
  },
  official: {
    docs: ["https://docs.psy-protocol.xyz", "https://psy.xyz/docs"],
    app: "https://app.psy-protocol.xyz",
    wallet: "https://app.psy-protocol.xyz/#/wallet",
    explorer: "https://explorer.psy-protocol.xyz",
    ide: "https://ide.psy-protocol.xyz",
    config: "https://config.psy-protocol.xyz/config.json",
    toolchainInstaller: "https://github.com/QEDProtocol/psyup",
    template: "https://github.com/PsyProtocol/psy-template",
    sdk: "https://github.com/PsyProtocol/psy-sdk",
    node: "https://github.com/PsyProtocol/psy-node",
    packages: [
      "@psy-protocol/psy-sdk",
      "@psy-protocol/contract-sdk",
      "@psy-protocol/utils",
    ],
    cli: ["psyup", "dargo", "psy_user_cli"],
  },
  handOff: [
    "pf build --target psy → *.dpn.json",
    "pf test -t psy (multi-step session 7+5=12)",
    "pf run -t psy -- <method> (wraps psy_user_cli simulate)",
    "pf deploy -t psy (wraps deploy-contract; receipt has contractUuid/contractId)",
    "pf execute -t psy --broadcast (wraps psy_user_cli call)",
    "ABI: scripts/psy_dpn_to_abi.py / pf deploy·test emit *.abi.json",
    "diff: just psy-dpn-diff · UI: templates/psy-dapp-ui",
    "just psy-dpn-local-smoke / psy-example-matrix / psy_local_chain_status",
    "frontend: @psy-protocol/* + psy-wallet window.psy",
  ],
  safety: [
    "PF has no Psy network broadcast product command",
    "no private keys in MCP/chat/git",
    "config endpoints drift — refresh config.psy-protocol.xyz",
    "engineering DPN emission ≠ UPS/proof/mainnet evidence",
  ],
};

/** In-product Solana knowledge for PF agents (not a pointer to external MCP). */
const SOLANA_PF = {
  contractPath: "ProofForge ProgramV1 + pf CLI (not Anchor/Rust scaffold)",
  frontendTemplate: "templates/solana-dapp-ui",
  localDemo: "scripts/pf_solana_local_demo.sh (Surfpool)",
  docs: [
    "09-solana-agent-playbook.md",
    "10-solana-dapp-frontend.md",
    "solana-local-walkthrough.md",
  ],
  /** Default demo path = body-only S1b (StateCell / pf new). */
  ixEncoding: {
    schema: "proof-forge.solana.ix-data.body-only.v1",
    profile: "body-only-S1b",
    layout:
      "sha256('proof-forge-solana-v1:' + name + '(' + types + ')')[0:8] + params_u64le",
    notAnchorSighash: true,
    notHandlerId: true,
    detail:
      "Body-only (StateCell, pf new HelloSol): first 8 bytes = SHA256('proof-forge-solana-v1:' + discName + '(' + 'u64'*n joined by ',' + ')')[0:8], then each non-Principal scalar as u64 LE. Initializer disc name is 'initialize' (IDL name may be 'init'). Do NOT use Anchor sighash and do NOT use handlerId for body-only ELF.",
    cpiProductBranch: {
      schema: "proof-forge.solana.ix-data.cpi-product.v1",
      profile: "cpi-product",
      layout: "handlerId_u64le + params_u64le_sequence",
      detail:
        "CPI-product programs (e.g. TransferSol) use u64 LE handlerId from *.idl.json then u64 LE params. Branch on build profile / manifest — never assume one layout for all PF Solana ELFs.",
    },
    stateCellLayout: {
      schema: "proof-forge.solana.state-layout.ordinary.v1",
      bytes: 16,
      fields: [
        { name: "layoutMarker", offset: 0, width: 8 },
        { name: "count", offset: 8, width: 8 },
      ],
      note: "init requires state account is_signer + is_writable; entry needs writable; view is read-only.",
    },
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
    "Surfpool/local validator only for dApp demo",
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
          "pf_network_info",
          "pf_onchainos_guide",
          "pf_target_info",
          "pf_agent_instructions",
          "pf_aleo_live_demo",
          "pf_cli_cheatsheet",
          "pf_solana_scaffold",
          "pf_solana_ix_codec",
          "pf_solana_artifacts",
          "pf_psy_scaffold",
          "pf_psy_artifacts",
          "pf_psy_ecosystem",
        ],
        liveDemo: LIVE,
        solana: SOLANA_PF,
        psy: PSY_PF,
        xlayer: {
          networksCatalog: "networks.v1.json",
          guide: "13-xlayer-onchainos.md",
          testnetChainId: 1952,
          mainnetChainId: 196,
          gas: "OKB",
          onchainosMcp: "https://web3.okx.com/api/v1/onchainos-mcp",
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
          networksRef: CATALOG.networksRef,
        });
      }
      return textResult({
        schema: CATALOG.schema,
        version: CATALOG.version,
        updated: CATALOG.updated,
        notes: CATALOG.notes,
        networksRef: CATALOG.networksRef,
        targets,
      });
    },
  );

  server.registerTool(
    "pf_network_info",
    {
      description:
        "Return the ProofForge network catalog (Anvil, X Layer testnet/mainnet, placeholders). Metadata + policy only — no broadcast.",
      inputSchema: z.object({
        id: z
          .string()
          .optional()
          .describe("Network id, e.g. evm.xlayer.testnet"),
        targetFamily: z
          .string()
          .optional()
          .describe("Filter by target family, e.g. evm"),
        env: z
          .string()
          .optional()
          .describe("Filter: local | testnet | mainnet"),
        chainId: z
          .number()
          .int()
          .optional()
          .describe("EVM chain id filter (1952, 196, 31337, …)"),
      }),
    },
    async ({ id, targetFamily, env, chainId }) => {
      const result = filterNetworks({ id, targetFamily, env, chainId });
      if (id && id.trim() && !result.found) {
        return textResult({
          ok: false,
          error: `unknown network id '${id}'`,
          known: NETWORKS.networks.map((n) => n.id),
        });
      }
      return textResult({
        ok: true,
        ...result,
        note: "Catalog presence ≠ product public broadcast. See 13-xlayer-onchainos.md.",
      });
    },
  );

  server.registerTool(
    "pf_onchainos_guide",
    {
      description:
        "OKX OnchainOS dual-MCP guide: official DEX MCP, wallet/trade/market/payments map, P0–P2 roadmap. Prefer official onchainos-mcp for swaps.",
      inputSchema: z.object({}),
    },
    async () =>
      textResult({
        schema: "proof-forge.mcp.onchainos-guide.v1",
        guide: "13-xlayer-onchainos.md",
        networksCatalog: "networks.v1.json",
        okxOnchainOs: NETWORKS.ecosystems?.["okx-onchainos"] ?? null,
        agentWiring: {
          proofForgeRemoteMcp:
            "https://proof-forge-mcp.davirain-yin.workers.dev/mcp",
          onchainosOfficialMcp: "https://web3.okx.com/api/v1/onchainos-mcp",
          onchainosAuthHeader: "OK-ACCESS-KEY",
          devPortal:
            "https://web3.okx.com/zh-hans/onchainos/dev-portal/project",
          never: [
            "put OK-ACCESS-KEY in git or PF remote Worker env",
            "pass private keys to MCP tools",
            "treat catalog presence as product public broadcast",
          ],
        },
        priority: {
          P0: "networks catalog + dual MCP docs + X Layer UI presets + official DEX MCP",
          P1: "market API probe / optional read-only proxy; Agentic Wallet notes; testnet deploy engineering",
          P2: "payments; more EVM rows; Lean NetworkRegistry product cutover",
        },
      }),
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
                  "pf_network_info id=evm.xlayer.testnet  # catalog metadata",
                  "templates/evm-dapp-ui: VITE_NETWORK_ID=evm.xlayer.testnet",
                  "DEX: official onchainos-mcp (not PF) — see pf_onchainos_guide",
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
- Use \`pf_network_info\` for Anvil / X Layer chain ids + RPC (metadata only).
- Use \`pf_onchainos_guide\` for OKX OnchainOS dual-MCP wiring (DEX = official onchainos-mcp).
- Use \`pf_cli_cheatsheet\` for command sequences.
- Use \`pf_aleo_live_demo\` for the published Aleo Testnet evidence links.
- Use \`pf_solana_scaffold\`, \`pf_solana_ix_codec\`, \`pf_solana_artifacts\` for Solana (PF path).
- Use \`pf_psy_scaffold\`, \`pf_psy_artifacts\`, \`pf_psy_ecosystem\` for Psy (DPN only + official hand-off).
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
- Frontend: \`templates/solana-dapp-ui\` consumes \`*.idl.json\`. Body-only ix-data = PF name discriminator (sha256 domain) + u64 params — **not** handlerId, **not** Anchor sighash. CPI-product uses handlerId (see \`pf_solana_ix_codec\`).
- StateCell account: 16 bytes = layout marker @0 + count @8. Local demo: \`scripts/pf_solana_local_demo.sh\` (Surfpool).
- Principal wire identity ≠ Solana pubkey globally.
- External Solana Rust/Anchor docs MCP is **out of the default agent path**; PF MCP already summarizes ix encoding + artifacts.

## Psy notes (DPN hand-off)
- **PF sole path:** \`pf build --target psy\` → \`{name}.dpn.json\` (profile \`psy-dpn-v1\`, \`deployable=false\`, zero-tool).
- Do **not** treat Dargo/\`.psy\` as the PF source of truth; do **not** expect \`pf deploy\` for Psy.
- Official deploy/prove/wallet: \`psyup\` / \`dargo\` / \`psy_user_cli\` / WebIDE / \`@psy-protocol/psy-sdk\` / psy-wallet.
- Surfaces: app · wallet · explorer · IDE · config.psy-protocol.xyz (see \`pf_psy_ecosystem\`).
- DPN schema authority pin is psy-node revision annotation — not an installable Tool Lock binary.

## X Layer / OnchainOS
- Networks: \`pf_network_info\` / doc \`13-xlayer-onchainos.md\` / \`networks.v1.json\`.
- Testnet chainId **1952**, mainnet **196**, gas **OKB** (not ETH).
- PF \`--target evm\` artifacts apply (full EVM equivalence).
- DEX quote/swap: hang **official** \`https://web3.okx.com/api/v1/onchainos-mcp\` with app-local \`OK-ACCESS-KEY\`.
- Do **not** put OKX keys on this public PF edge Worker.

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
              : t === "psy"
                ? [
                    "pf setup --target psy && pf doctor --target psy",
                    "pf new hello --target psy && cd hello",
                    "# edit ProgramV1 Lean (not Dargo.toml / .psy as PF source)",
                    "pf build   # → *.dpn.json  deployable=false",
                    "pf inspect --output-dir .",
                    "# hand-off: official psyup/dargo/WebIDE/wallet — NOT pf deploy",
                    "# docs: pf_get_doc id=11-psy-agent-playbook.md | 12-psy-dapp-frontend.md | psy-dpn-walkthrough.md",
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
    "pf_psy_scaffold",
    {
      description:
        "Psy target scaffold: ProofForge emits canonical DPN only; then hand off to official psyup/dargo/SDK/wallet. No PF network broadcast.",
      inputSchema: z.object({
        includeEcosystem: z
          .boolean()
          .optional()
          .describe("Include official Psy URLs and toolchain notes (default true)"),
      }),
    },
    async ({ includeEcosystem }) => {
      const row = targetById("psy");
      const eco = includeEcosystem !== false;
      return textResult({
        schema: "proof-forge.mcp.psy-scaffold.v1",
        target: "psy",
        contractPath: PSY_PF.contractPath,
        profile: PSY_PF.profile,
        deployable: PSY_PF.deployable,
        catalog: row,
        docs: PSY_PF.docs,
        pfLadder: [
          "export PROOF_FORGE_CLI=/path/to/proof-forge-next",
          "pf setup --target psy",
          "pf doctor --target psy   # zero-tool ok",
          "pf new hello --target psy && cd hello",
          "# edit Lean ProgramV1",
          "pf build",
          "ls *.dpn.json manifest.json",
          "pf inspect --output-dir .",
          "pf test -t psy          # multi-step session",
          "pf run -t psy -- initialize 7",
          "pf deploy -t psy        # wraps deploy-contract save-only",
        ],
        monorepoExample: [
          "pf build Examples/StateCell.lean --module Examples.StateCell --target psy -o build/v2/sc-psy",
          "jq '.[].name, .[].method_id' build/v2/sc-psy/StateCell.dpn.json",
        ],
        officialHandOff: eco ? PSY_PF.handOff : undefined,
        official: eco ? PSY_PF.official : undefined,
        safety: PSY_PF.safety,
        edgeNote:
          "Remote MCP is guidance-only. DPN compile is local pf; deploy/prove stay on official Psy tools.",
      });
    },
  );

  server.registerTool(
    "pf_psy_artifacts",
    {
      description:
        "Explain pf build --target psy outputs: sole *.dpn.json package, manifest deployable=false, no PF deploy artifact.",
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
        schema: "proof-forge.mcp.psy-artifacts.v1",
        buildCommand: `pf build <Source.lean> --module <Module> --target psy -o <out>`,
        profile: PSY_PF.profile,
        deployable: false,
        files: [
          {
            path: `${name}.dpn.json`,
            role: "materialized-base",
            note: PSY_PF.artifact.note,
          },
          {
            path: "manifest.json",
            role: "inventory",
            note: "proof-forge.output.v1; deployable=false",
          },
          {
            path: "evidence.json",
            role: "evidence",
            note: "content-bound engineering evidence",
          },
        ],
        notEmitted: [
          ".psy source",
          "Dargo.toml project",
          "UPS proofs",
          "network deployment receipt from pf",
        ],
        nextSteps: PSY_PF.handOff,
        docs: PSY_PF.docs,
      });
    },
  );

  server.registerTool(
    "pf_psy_ecosystem",
    {
      description:
        "Official Psy Protocol surfaces (app, wallet, explorer, IDE, config, SDK, psyup) for agents. Not installed by ProofForge.",
      inputSchema: z.object({}),
    },
    async () =>
      textResult({
        schema: "proof-forge.mcp.psy-ecosystem.v1",
        ...PSY_PF.official,
        samplePublicConfig: {
          source: "https://config.psy-protocol.xyz/config.json",
          note: "Live JSON drifts; always refetch. Snapshot fields observed 2026-07-20 release config.",
          l1: "Ethereum Sepolia chain_id=11155111",
          services: {
            coordinator_rpc: "https://coordinator.psy-protocol.xyz",
            realm_rpcs: [
              "https://realm0.psy-protocol.xyz",
              "https://realm1.psy-protocol.xyz",
            ],
            prove_proxy: "https://prove.psy-protocol.xyz",
            indexer_graphql: "https://indexer.psy-protocol.xyz/v1/graphql",
          },
        },
        pfBoundary: PSY_PF.contractPath,
        safety: PSY_PF.safety,
        docs: PSY_PF.docs,
      }),
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
          "# end-to-end Surfpool + UI: just pf-solana-local-demo",
        ],
        monorepoExample: [
          "pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol",
          "pf verify --target solana -o build/v2/sc-sol",
          "just pf-solana-local-demo  # Surfpool deploy + init + deployment.json",
        ],
        frontend: fe
          ? {
              template: SOLANA_PF.frontendTemplate,
              localDemo: SOLANA_PF.localDemo,
              steps: [
                "just pf-solana-local-demo   # preferred: Surfpool + init + deployment.json",
                "# or manual: cp <out>/*.idl.json templates/solana-dapp-ui/public/artifacts/",
                "cd templates/solana-dapp-ui && npm install && npm run dev",
                "# wallet connects to Surfpool RPC from deployment.json (entry/view; init via script)",
              ],
              guide: "docs/product/10-solana-dapp-frontend.md",
              walkthrough: "docs/demos/solana-local-walkthrough.md",
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
        "Summarize ProofForge Solana instruction-data encoding. Default body-only S1b uses sha256('proof-forge-solana-v1:name(types)')[0:8] + u64 params (StateCell). CPI-product uses handlerId u64 LE. NOT Anchor sighash. Optional: encode a body-only sample.",
      inputSchema: z.object({
        name: z
          .string()
          .optional()
          .describe(
            "Body-only disc name, e.g. initialize | increment | get (init → initialize)",
          ),
        params: z
          .array(z.string())
          .optional()
          .describe('Decimal u64 strings, e.g. ["5"] for increment delta'),
        profile: z
          .enum(["body-only", "cpi-product"])
          .optional()
          .describe("Encoding branch; default body-only"),
        handlerId: z
          .number()
          .int()
          .min(0)
          .optional()
          .describe("Only for profile=cpi-product sample encode"),
      }),
    },
    async ({ name, params, profile, handlerId }) => {
      const enc = SOLANA_PF.ixEncoding;
      const branch = profile === "cpi-product" ? "cpi-product" : "body-only";
      let sample:
        | { profile: string; hex: string; bytes: number[]; preimage?: string }
        | undefined;

      const ps = (params ?? []).map((s) => {
        const n = BigInt(s);
        if (n < 0n || n > 0xffff_ffff_ffff_ffffn) {
          throw new Error(`param out of u64 range: ${s}`);
        }
        return n;
      });

      if (branch === "cpi-product" && handlerId !== undefined) {
        const out = new Uint8Array(8 + ps.length * 8);
        const view = new DataView(out.buffer);
        view.setBigUint64(0, BigInt(handlerId), true);
        ps.forEach((p, i) => view.setBigUint64(8 + i * 8, p, true));
        const hex = Array.from(out)
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        sample = { profile: "cpi-product", hex, bytes: Array.from(out) };
      } else if (branch === "body-only" && name) {
        const discName =
          name === "init" || name === "initializer" ? "initialize" : name;
        const types = Array.from({ length: ps.length }, () => "u64").join(",");
        const preimage = `proof-forge-solana-v1:${discName}(${types})`;
        const digest = new Uint8Array(
          await crypto.subtle.digest(
            "SHA-256",
            new TextEncoder().encode(preimage),
          ),
        );
        const out = new Uint8Array(8 + ps.length * 8);
        out.set(digest.slice(0, 8), 0);
        const view = new DataView(out.buffer);
        ps.forEach((p, i) => view.setBigUint64(8 + i * 8, p, true));
        const hex = Array.from(out)
          .map((b) => b.toString(16).padStart(2, "0"))
          .join("");
        sample = {
          profile: "body-only-S1b",
          hex,
          bytes: Array.from(out),
          preimage,
        };
      }

      return textResult({
        ...enc,
        schema: "proof-forge.mcp.solana-ix-codec.v2",
        defaultProfile: "body-only-S1b",
        example: {
          stateCellBodyOnly: {
            init: "disc=sha256('proof-forge-solana-v1:initialize(u64)')[0:8] || u64le(initial); state is_signer+writable",
            increment:
              "disc=sha256('proof-forge-solana-v1:increment(u64)')[0:8] || u64le(delta); state writable",
            get: "disc=sha256('proof-forge-solana-v1:get()')[0:8]; state readonly",
            knownDiscs: {
              initialize_u64: "5e494767a7582864",
              increment_u64: "9dc79703d1db3e22",
              get: "a4a276b0d690dd37",
            },
          },
          cpiProduct: {
            note: "TransferSol-class: handlerId u64 LE from IDL + u64 params",
          },
        },
        sample,
        frontendHelper: "templates/solana-dapp-ui/src/ix.ts → encodePfIxData",
        localDemo: SOLANA_PF.localDemo,
        antiPatterns: [
          "Anchor sha256('global:name')[0..8] discriminators on PF ELF",
          "Using handlerId for StateCell / body-only S1b programs",
          "Using body-only name disc for CPI-product TransferSol without checking profile",
          "Assuming Principal params are 32-byte pubkeys in ix data without PF wire rules",
          "Reading StateCell count at offset 0 (count is at offset 8 after layout marker)",
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
            note: "instruction names, modes, accounts; handlerId only for CPI-product branch",
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
    <tr><td><code>pf_solana_ix_codec</code></td><td>PF ix-data (body-only disc / CPI handlerId)</td></tr>
    <tr><td><code>pf_solana_artifacts</code></td><td>build outputs → UI vs CLI</td></tr>
    <tr><td><code>pf_psy_scaffold</code></td><td>Psy DPN ladder + official hand-off</td></tr>
    <tr><td><code>pf_psy_artifacts</code></td><td><code>*.dpn.json</code> package shape</td></tr>
    <tr><td><code>pf_psy_ecosystem</code></td><td>app / wallet / explorer / IDE / SDK</td></tr>
  </table>
  <h2>Solana (ProofForge path)</h2>
  <p>
    Contracts: <strong>ProgramV1 + <code>pf build --target solana</code></strong> (not Anchor).
    Frontend: <code>templates/solana-dapp-ui</code>. Tools: <code>pf_solana_scaffold</code>,
    <code>pf_solana_ix_codec</code>, <code>pf_solana_artifacts</code>.
  </p>
  <h2>Psy (DPN hand-off)</h2>
  <p>
    Contracts: <strong>ProgramV1 + <code>pf build --target psy</code> → <code>*.dpn.json</code></strong>
    (<code>deployable=false</code>). Deploy/wallet/SDK: official
    <a href="https://app.psy-protocol.xyz">app</a> ·
    <a href="https://app.psy-protocol.xyz/#/wallet">wallet</a> ·
    <a href="https://ide.psy-protocol.xyz">WebIDE</a> ·
    <a href="https://explorer.psy-protocol.xyz">explorer</a> ·
    <code>psyup</code>/<code>dargo</code>. Tools: <code>pf_psy_scaffold</code>,
    <code>pf_psy_artifacts</code>, <code>pf_psy_ecosystem</code>.
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
