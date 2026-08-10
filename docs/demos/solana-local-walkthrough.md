---
id: DEMO-SOLANA-LOCAL-WALKTHROUGH
title: Demo — Solana with pf (build → verify → optional Mollusk)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Demo: Solana with `pf`

**Audience:** hackathon / agent onboarding  
**Time:** ~10 minutes  
**Claims:** engineering only — **not** formal / hermetic / public-network broadcast

## Dual MCP (agents)

```bash
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp
codex mcp add solana-mcp --url https://mcp.solana.com/mcp
```

- ProofForge MCP: `pf_solana_scaffold`, `pf_target_info`, catalog  
- Solana MCP: docs search + `program_autofixer` for ecosystem Rust  

## Shot list

### 1) Tooling

```bash
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
export PATH="$HOME/.cargo/bin:$PATH"
pf setup --target solana
pf doctor --target solana
# expect: proof-forge-next + proof-forge-solana-client present (or install hints)
```

### 2) Scaffold + build

```bash
pf new sc-sol --target solana && cd sc-sol
cat ProofForge.toml
pf build
ls build/
```

Or monorepo example:

```bash
pf build Examples/StateCell.lean --module Examples.StateCell -t solana -o build/v2/sc-sol
ls build/v2/sc-sol/
```

### 3) Offline verify

```bash
pf verify -t solana -o build/v2/sc-sol
# uses proof-forge-solana-client verify-artifacts
```

### 4) Test (when harness available)

```bash
pf test -t solana
# or monorepo host-heavy:
# just solana-runtime
```

### 5) Deploy package (save-only)

```bash
pf deploy --network local -o build/v2/sc-sol
# tx/ package only — no public RPC
# optional local validator broadcast (loopback only):
# pf deploy --network local --broadcast --endpoint http://127.0.0.1:8899
```

### 6) Safety on camera

- Public Solana RPC broadcast is **refused** in `pf` v0  
- No keys in MCP / git / chat  
- Success ≠ mainnet readiness  

## Related

- `docs/product/09-solana-agent-playbook.md`  
- `docs/targets/02-solana.md`  
- Official Solana MCP: https://mcp.solana.com/
