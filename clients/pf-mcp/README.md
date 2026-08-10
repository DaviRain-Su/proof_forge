# ProofForge remote MCP (Cloudflare Workers)

Public **Streamable HTTP** MCP server for coding agents — Streamable HTTP remote MCP for coding agents.

| | |
|---|---|
| Transport | Streamable HTTP |
| Path | `/mcp` |
| Auth | none (v0 public) |
| Role | docs · catalog · agent guidance · live demo links |
| Not included | Lean compile, key custody, network broadcast |

Local compile/deploy remains:

- Developer CLI: `pf` / `proof-forge-next`
- Stdio MCP: `tools/mcp/proof_forge_mcp_server.py`

## Develop

```bash
cd clients/pf-mcp
npm install
npm run dev
# MCP: http://127.0.0.1:8787/mcp
# UI:  http://127.0.0.1:8787/
```

## Deploy

```bash
cd clients/pf-mcp
npm install
npx wrangler deploy
```

After deploy, connect:

```bash
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.<account>.workers.dev/mcp
# or
claude mcp add --transport http proof-forge-mcp https://proof-forge-mcp.<account>.workers.dev/mcp
```

## Tools

- `pf_health`
- `pf_list_docs` / `pf_get_doc` / `pf_search_docs`
- `pf_chain_catalog` / `pf_target_info`
- `pf_agent_instructions`
- `pf_cli_cheatsheet`
- `pf_aleo_live_demo`
- `pf_solana_scaffold` — PF Solana ladder + `templates/solana-dapp-ui`
- `pf_solana_ix_codec` — PF ix-data encoding summary (handlerId u64 LE)
- `pf_solana_artifacts` — build outputs → UI vs CLI

## Solana (in this MCP)

Contracts are **ProofForge ProgramV1 + `pf`**, not Anchor. This server **summarizes**
ix encoding and artifact layout for agents; it does not recommend an external
Solana Rust MCP as the default path. See `docs/product/09-solana-agent-playbook.md`
and `docs/product/10-solana-dapp-frontend.md`.


## Content refresh

Bundled snapshots live under `content/`. After editing monorepo docs:

```bash
cp docs/product/chain-client-catalog.v1.json clients/pf-mcp/content/
cp docs/product/0*.md clients/pf-mcp/content/
cp docs/demos/*.md clients/pf-mcp/content/
# regenerate docs-index.json + src/bundled.ts:
python3 -I scripts/pf_mcp_bundle_content.py   # or the inline regen used in deploy notes
```

## Safety

- No private keys in Worker env for v0.
- No mainnet / broadcast tools on the remote surface.
- Engineering guidance only — not formal/hermetic evidence.
