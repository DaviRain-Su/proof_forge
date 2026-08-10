---
id: DEMO-SOLANA-LOCAL-WALKTHROUGH
title: Demo — Solana with pf (build → verify → optional UI)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Demo: Solana with ProofForge `pf`

**Claims:** engineering only — not formal / hermetic / public broadcast

## MCP（只要 PF）

```bash
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp
# tools: pf_solana_scaffold · pf_solana_ix_codec · pf_solana_artifacts
```

## Shot list

### 1) Tooling

```bash
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
pf setup --target solana && pf doctor --target solana
```

### 2) Write + build（PF 语言，不是 Anchor）

```bash
pf new sc-sol --target solana && cd sc-sol
# edit Lean ProgramV1
pf build
# or monorepo:
# pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol
```

### 3) Verify / test

```bash
pf verify --target solana
pf test --target solana   # when Mollusk harness available
```

### 4) Frontend template

```bash
cp <out>/StateCell.idl.json templates/solana-dapp-ui/public/artifacts/
cd templates/solana-dapp-ui && npm install && npm run dev
```

Fill `public/deployment.json` after local deploy (see `deployment.example.json`).

### 5) Safety

- No public Solana RPC broadcast in pf v0  
- No keys in MCP/git  
- Success ≠ mainnet readiness  

## Related

- `docs/product/09-solana-agent-playbook.md`  
- `docs/product/10-solana-dapp-frontend.md`  
- `templates/solana-dapp-ui/`  
