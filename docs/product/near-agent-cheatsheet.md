---
id: PRODUCT-NEAR-AGENT-CHEATSHEET
title: NEAR agent / external-author cheatsheet
status: draft
owner: product
updated: 2026-08-11
normative: false
---

# NEAR agent cheatsheet

One page for agents and external authors. **Do not** default to monorepo
`lake build` of the whole compiler tree.

Honesty: engineering Wasm + locked `near-sandbox` only. Not formal, not
testnet/mainnet, not sync-call.

## Path

```bash
# 1) Tooling (product install surface — see 01-toolchain-install-surface.md)
#    need: proof-forge-next (or monorepo CLI), wat2wasm, optional near-sandbox
pf setup --target near --with-runtime -y   # when bootstrap path is available
# contributor fallback: PROOF_FORGE_TOOL_ROOT with locked wat2wasm + near-sandbox

# 2) Build a program
proof-forge-next build Examples/PoseTransform.lean \
  --module Examples.PoseTransform --target near -o build/v2/near-pose

# 3) Runtime gate (all twelve engineering suites, skip-clean if tools missing)
scripts/near_runtime_test.sh

# Single-suite debug (after a full script build left wasm under build/v2/near-runtime):
#   PF_NEAR_SUITE=posetransform PF_NEAR_WASM=... python3 runtime-tests/near/run_tests.py
```

## Recommended low-integration Examples

| Example | Why |
|---------|-----|
| `Examples/PoseTransform.lean` | translate / rotate90 / scale; Int64 pose; overflow hold |
| `Examples/BlockHeightCheck.lean` | `context.blockHeight` → `block_index` |
| `Examples/StateCell.lean` | minimal state machine |
| `Examples/VerifiedVaultPF.lean` | proof-bearing invariant-root erasure (ADR-0042); **not formal** |

## Permanent fail-closed (do not file as bugs)

- Sync `call` / sync native or token `transfer`
- `pf.assets.token` balance-of (async view call)
- view-path `context.caller`
- nonempty source `constants` table on NEAR materialize
- Map / Bytes / nested aggregate **returns**

## Roadmap

`docs/plan/near-parity-roadmap.md` — phases 0–4 vs EVM/Solana engineering surface.
