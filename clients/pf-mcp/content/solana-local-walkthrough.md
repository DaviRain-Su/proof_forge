---
id: DEMO-SOLANA-LOCAL-WALKTHROUGH
title: Demo — Solana with pf (build → Surfpool → UI)
status: draft
owner: product+engineering
updated: 2026-08-10
normative: false
---

# Demo: Solana with ProofForge `pf` + Surfpool

**Claims:** engineering only — not formal / hermetic / public broadcast

## MCP（只要 PF）

```bash
codex mcp add proof-forge-mcp --url https://proof-forge-mcp.davirain-yin.workers.dev/mcp
# tools: pf_solana_scaffold · pf_solana_ix_codec · pf_solana_artifacts
```

## Shot list（推荐一键）

### 0) Tooling

```bash
export PATH="$HOME/.local/bin:$HOME/.local/share/solana/install/active_release/bin:$HOME/.cargo/bin:$PATH"
export PROOF_FORGE_CLI=$PWD/.lake/build/bin/proof-forge-next
# surfpool 1.x preferred over cargo-installed 0.10.x
surfpool --version
solana --version
pf setup --target solana && pf doctor --target solana
```

Optional solders venv (for create-account + invoke helper):

```bash
python3 -m venv /tmp/pf-sol-venv
/tmp/pf-sol-venv/bin/pip install 'solders>=0.21'
```

### 1) One command: build → verify → Surfpool deploy → init

```bash
just pf-solana-local-demo
# or: bash scripts/pf_solana_local_demo.sh
```

Expected:

- offline `pf verify` ok  
- Surfpool RPC (e.g. `http://127.0.0.1:19422`)  
- program deploy + StateCell `init(7)` + `increment(5)` + `get`  
- account count **12** at offset 8  
- writes `templates/solana-dapp-ui/public/deployment.json`

Surfpool stays up by default (`PF_SOLANA_DEMO_KEEP=0` to tear down).

### 2) Frontend

```bash
cd templates/solana-dapp-ui && npm install && npm run dev
# wallet → custom RPC from deployment.json
# entry/view only (init already done by script; needs state signer)
```

### 3) Manual ladder (without one-shot)

```bash
pf build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/sc-sol
pf verify --target solana -o build/v2/sc-sol
just solana-surfpool-up
# pf deploy --network local --broadcast --endpoint <rpc> …
# python3 scripts/pf_solana_statecell_invoke.py --rpc … --idl … --init 7 --delta 5
```

### 4) Encoding reminder

Body-only (this demo):

```text
disc = sha256("proof-forge-solana-v1:initialize(u64)")[0:8]   # not handlerId
state = [marker u64 | count u64]   # count @ offset 8
```

### 5) Safety

- No public Solana RPC broadcast in pf v0  
- No keys in MCP/git  
- Success ≠ mainnet readiness  
- Tear down: `just solana-surfpool-down`

## Related

- `docs/product/09-solana-agent-playbook.md`  
- `docs/product/10-solana-dapp-frontend.md`  
- `templates/solana-dapp-ui/`  
- `scripts/pf_solana_local_demo.sh`  
