---
id: PRODUCT-COSMWASM-AGENT-CHEATSHEET
title: CosmWasm agent / external-author cheatsheet
status: draft
owner: product
updated: 2026-08-11
normative: false
---

# CosmWasm agent cheatsheet

One page for agents and external authors. **Do not** default to monorepo
`lake build` of the whole compiler tree as the product path.

Honesty: engineering Wasm + cosmwasm-vm mock (+ optional wasmd Docker rung).
Not formal, not mainnet, not hermetic Stage-0.

## Path

```bash
# 1) Tooling
pf setup --target cosmwasm --with-runtime -y   # when bootstrap path is available
# need: wat2wasm, cosmwasm-check; runtime corpus needs cargo + cosmwasm-vm

# 2) Build
proof-forge-next build Examples/StateCell.lean \
  --module Examples.StateCell --target cosmwasm -o build/v2/cw-state

# 3) Runtime gate (artifact fast-path when OutputSet has *.wasm)
pf test -t cosmwasm
# force full corpus rebuild:
#   PF_COSMWASM_TEST_MODE=corpus pf test -t cosmwasm
# product local:
#   proof-forge-next local --target cosmwasm --mode runtime
# monorepo full corpus:
#   scripts/cosmwasm_runtime_test.sh
# optional wasmd Docker rung:
#   scripts/cosmwasm_wasmd_test.sh

# 4) Deploy packaging (save-only; --broadcast refused)
pf deploy -t cosmwasm --network local
# → <artifact>/tx/<Program>.deployment.package.json
```

## Recommended Examples / fixtures

| Example | Why |
|---------|-----|
| `Examples/StateCell.lean` | minimal state machine |
| `Examples/ConstAnswer.lean` | scalar `const` / Op.Constant table |
| `Examples/BlockHeightCheck.lean` | `context.blockHeight` → Env.block.height |
| `Examples/TipJar.lean` | pf.assets native deposit + BankMsg::Send |
| `Examples/TokenJar.lean` | CW20 transfer SubMsg |
| `runtime-tests/cosmwasm/fixtures/BytesRet.lean` | Bytes 4 state + anonymous return |
| `runtime-tests/cosmwasm/fixtures/CallerGate.lean` | context.caller / MessageInfo.sender |
| `runtime-tests/cosmwasm/fixtures/ScheduleFlow.lean` | schedule → SubMsg reply_on=never |

## Sync vs async (CosmWasm)

| Kind | API | Notes |
|------|-----|-------|
| **Sync-ish same-tx** | `pf.assets.native.deposit` | exact `info.funds` stake denom |
| **Sync-ish same-tx** | `pf.assets.native.transfer` | BankMsg::Send SubMsg `reply_on=never` (**error-propagating**) |
| **Sync-ish same-tx** | `pf.assets.token.transfer` | CW20 Transfer SubMsg never |
| **Async-shaped schedule** | `schedule` | SubMsg never; whole-tx abort on sub fail; QN stub addr |
| **Permanent FC** | generic **sync `call`** | not catalog pf.assets |
| **Permanent FC** | `token.transferAsync` | not admitted on CW |
| **View FC** | `context.caller` on query | no MessageInfo.sender |

See also cross-chain table in `docs/product/near-sync-async-api.md`.

## Permanent fail-closed (do not file as bugs)

- Generic sync `call` (non-catalog)
- query/view `context.caller`
- Map return (named/Array/Option/**Bytes N** return open)
- nonempty source **invariants** (scalar constants open)
- public `pf deploy --broadcast`
- IBC / migrate / reply entry (not in MVP)

## Related

- Dossier: `docs/targets/04-cosmwasm.md`
- Install surface: `docs/product/01-toolchain-install-surface.md`
