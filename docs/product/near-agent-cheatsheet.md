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

# 3) Runtime gate — product CLI (preferred)
pf test -t near
# auto: if out/ has *.wasm → ONE suite against that wasm (fast; no lake rebuild)
# full corpus / monorepo:
#   PF_NEAR_TEST_MODE=corpus pf test -t near
#   just near-runtime          # ordinary CI job near-runtime (path-filtered)
# product local (same script):
#   proof-forge-next local --target near --mode runtime

# 3b) One-shot sandbox call/view (engineering; not testnet)
pf run -t near -- init 7
pf run -t near -- increment 5
pf run -t near -- get

# 4) Deploy packaging (save-only; --broadcast refused)
pf deploy -t near --network local
# → <artifact>/tx/<Program>.deployment.package.json

# 5) Frontend skeleton (ecosystem near-api-js; no wallet keys in PF)
pf scaffold-ui --template near-dapp

# Single-suite debug (after a full script build left wasm under build/v2/near-runtime):
#   PF_NEAR_SUITE=posetransform PF_NEAR_WASM=... python3 runtime-tests/near/run_tests.py
```

## Recommended low-integration Examples

| Example | Why |
|---------|-----|
| `Examples/PoseTransform.lean` | translate / rotate90 / scale; Int64 pose; overflow hold |
| `Examples/BlockHeightCheck.lean` | `context.blockHeight` → `block_index` |
| `Examples/UnixTimeCheck.lean` | `context.unixTimeSeconds` → `block_timestamp` ns÷10^9 |
| `Examples/ConstAnswer.lean` | scalar `const` table (`Op.Constant`) |
| `runtime-tests/near/fixtures/BytesRet.lean` | anonymous `Bytes 4` return (4×u8 tight) |
| `Examples/StateCell.lean` | minimal state machine |
| `Examples/VerifiedVaultPF.lean` | proof-bearing invariant-root erasure (ADR-0042); **not formal** |

## Networks (catalog only)

```bash
pf network list --family near
# near.local.sandbox  — engineering sandbox narrative (ephemeral port in scripts)
# near.testnet        — RPC discovery only; pf deploy --broadcast refused
```

## Permanent fail-closed (do not file as bugs)

- Sync `call` / sync native or token `transfer`
- `pf.assets.token` balance-of (async view call)
- view-path `context.caller` (NEAR host forbids predecessor in view)
- UInt128/256 / aggregate / Principal **const** rows (scalar UInt/Int/Bool ok)
- Map / nested aggregate **returns** (Bytes N 1..8 return admitted)
- Public testnet/mainnet `pf deploy --broadcast` (NEAR broadcast refused even for local)

## Sync vs async (read this before calling)

`docs/product/near-sync-async-api.md` — NEAR Promise is async; sync transfer/call
are permanent fail-closed. Use `*Async` / `schedule` for fire-and-forget only.

## Roadmap

`docs/plan/near-parity-roadmap.md` — phases 0–4 vs EVM/Solana engineering surface.
