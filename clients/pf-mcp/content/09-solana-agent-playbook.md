---
id: PRODUCT-SOLANA-AGENT-PLAYBOOK
title: Solana agent playbook — pf target + official Solana MCP
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Solana agent playbook

**Audience:** coding agents + developers building with ProofForge **`--target solana`**.  
**Claims:** engineering guidance only — **not** formal / hermetic / mainnet evidence.

## Two MCP servers (use both)

| Server | Endpoint | Role |
|---|---|---|
| **ProofForge remote MCP** | `https://proof-forge-mcp.davirain-yin.workers.dev/mcp` | PF catalog, `pf` CLI guidance, Solana target honesty, build/test/verify ladder |
| **Solana Developer MCP** (official) | `https://mcp.solana.com/mcp` | Live Solana docs, semantic search, Anchor/Pinocchio `program_autofixer` |

Connect both:

```bash
# ProofForge (docs/catalog/guidance — no compile on edge)
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp

# Official Solana (docs + program_autofixer)
codex mcp add solana-mcp --url https://mcp.solana.com/mcp
```

Claude Code:

```bash
claude mcp add --transport http proof-forge-mcp https://proof-forge-mcp.davirain-yin.workers.dev/mcp
claude mcp add --transport http solana-mcp https://mcp.solana.com/mcp
```

### When to call which

1. **Choosing PF surface / maturity / commands** → ProofForge tools  
   (`pf_chain_catalog`, `pf_target_info`, `pf_solana_scaffold`, `pf_cli_cheatsheet`)
2. **Solana ecosystem how-to, Anchor/Pinocchio Rust review** → official Solana tools  
   (`Solana_Documentation_Search`, `Solana_Expert__Ask_For_Help`, `program_autofixer`)
3. **Compile / test / deploy** → local `pf` + toolchains (edge MCP never spawns Lean/CLI)

## Local `pf` ladder (Solana target)

```bash
export PROOF_FORGE_CLI=/path/to/proof-forge-next   # monorepo: .lake/build/bin/proof-forge-next
export PATH="$HOME/.cargo/bin:$PATH"

pf setup --target solana
pf doctor --target solana

# Project mode
pf new hello --target solana && cd hello
pf build                         # default target from ProofForge.toml
pf test                          # Mollusk / StateCell-shaped when available
pf verify                        # offline OutputSet via proof-forge-solana-client
pf deploy --network local        # save-only package under tx/ by default
# Broadcast only on loopback local validator (public RPC refused in pf v0):
# pf deploy --network local --broadcast --endpoint http://127.0.0.1:8899
```

One-shot from monorepo examples:

```bash
pf build Examples/StateCell.lean --module Examples.StateCell -t solana -o build/v2/sc-sol
pf verify -t solana -o build/v2/sc-sol
# host-heavy runtime (optional):
# just solana-runtime
# or: pf test -t solana   (when harness resolves)
```

## Install companions

| Binary | Purpose |
|---|---|
| `pf` (`proof-forge-pf`) | Developer CLI |
| `proof-forge-next` | Compiler |
| `proof-forge-solana-client` | Offline `pf verify -t solana` |

```bash
cargo install proof-forge-pf --locked
cargo install proof-forge-solana-client --locked
# monorepo compiler:
lake build proof_forge_next
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
export PROOF_FORGE_SOLANA_CLIENT="$(command -v proof-forge-solana-client)"
```

## Honesty / safety

- Product default Solana rail is CPI/ELF engineering (`solana-sbpf-cpi-elf-v1`); maturity is **not** “mainnet ready”.
- **Principal ≠ Solana pubkey** globally (wire identity; no silent truncate/pad).
- `pf` v0 **refuses public Solana broadcast** (devnet/testnet/mainnet endpoints). Local loopback only when `--broadcast`.
- Never paste private keys into chat, git, or remote MCP tool arguments.
- Official Solana `program_autofixer` reviews **Rust** Anchor/Pinocchio — PF emits sBPF from Lean ProgramV1; use autofixer on any hand-written Rust adapters, not as a substitute for PF Plan validation.

## Agent checklist

1. `pf_target_info` / `pf_solana_scaffold` (ProofForge MCP) — confirm commands + boundaries.  
2. If writing/reviewing ecosystem Rust (Anchor/Pinocchio) → `program_autofixer` loop on Solana MCP.  
3. Run `pf build -t solana` locally; then `pf verify` / `pf test` as available.  
4. Do not claim formal/hermetic/mainnet success from engineering smokes.

## Related

- `docs/targets/02-solana.md` — target dossier  
- `docs/demos/solana-local-walkthrough.md` — short demo shot list  
- Official: https://mcp.solana.com/ · endpoint `https://mcp.solana.com/mcp`
