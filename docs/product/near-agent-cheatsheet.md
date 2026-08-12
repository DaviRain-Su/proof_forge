---
id: PRODUCT-NEAR-AGENT-CHEATSHEET
title: NEAR agent / external-author cheatsheet
status: draft
owner: product
updated: 2026-08-12
normative: false
---

# NEAR agent cheatsheet

One page for agents and external authors. **Do not** default to monorepo
`lake build` of the whole compiler tree.

Honesty: engineering Wasm + locked `near-sandbox` only. Not formal, not
testnet/mainnet, not sync-call.

**Unified path:** [16-external-author-cheatsheet.md](16-external-author-cheatsheet.md)

## Path

```bash
# 0) Doctor / setup
pf setup --target near --with-runtime -y
# NEED: near-sandbox + wat2wasm under PROOF_FORGE_TOOL_ROOT; scripts/pf_near_*.sh

# 1–2) Project + build (external author: pf new; monorepo: proof-forge-next build Examples/…)
pf new cell --target near && cd cell
pf build
# monorepo fixture example:
# proof-forge-next build Examples/PoseTransform.lean \
#   --module Examples.PoseTransform --target near -o build/v2/near-pose

# 3) Runtime gate
pf test -t near
# auto: if out/ has *.wasm → ONE suite (fast; no lake rebuild)
# full corpus: PF_NEAR_TEST_MODE=corpus pf test -t near | just near-runtime
# corpus includes StateCell negative_corpus (unknown method / bad arg lens + state-hold)

# 4) One-shot sandbox call/view (engineering; not testnet)
pf run -t near -- init 7
pf run -t near -- increment 5
pf run -t near -- get
# ABI mode prefers *.near-abi.json (e.g. nativeBalanceU128 is a view)

# 5) Deploy packaging (save-only; --broadcast refused)
pf deploy -t near --network local

# 6) Frontend skeleton (ecosystem near-api-js; no wallet keys in PF)
pf write-ui-json -t near --address <id>
pf scaffold-ui --template near-dapp
# detail: docs/product/18-near-dapp-frontend.md
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
| `Examples/EnvReadBalanceU128.lean` | `pf.assets@1.2.0` full-width u128 balance (no hi64 trap) |
| `Examples/WideShiftProbe.lean` | body-only UInt128 multiword `<<` / `>>` |
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
- UInt64 `balanceOfSelf` on ordinary funded accounts (hi64 trap; use `balanceOfSelfU128`)
- UInt128/256 / aggregate / Principal **const** rows (scalar UInt/Int/Bool ok)
- nested aggregate returns beyond admitted Map/Bytes surface
- Public testnet/mainnet `pf deploy --broadcast` (NEAR broadcast refused even for local)
- Old Linux GLIBC vs locked near-sandbox: on linux-x86_64 run
  `scripts/near_sandbox_glibc_materialize.sh` (writes Tool Root
  `near-sandbox-glibc/`; auto-used by pf test/run). Engineering only — not
  hermetic Tool Lock pin until digests admitted (see
  `supply-chain/near-sandbox-glibc-linux-x86_64.v1.json`). Env override:
  `PF_NEAR_SANDBOX_LOADER` + `PF_NEAR_SANDBOX_LIBRARY_PATH`.

## Sync vs async (read this before calling)

`docs/product/near-sync-async-api.md` — NEAR Promise is async; sync transfer/call
are permanent fail-closed. Use `*Async` / `schedule` for fire-and-forget only.

## Roadmap

`docs/plan/near-parity-roadmap.md` — phases 0–4 vs EVM/Solana engineering surface.
