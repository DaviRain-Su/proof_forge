---
id: PRODUCT-COSMWASM-AGENT-CHEATSHEET
title: CosmWasm agent / external-author cheatsheet
status: draft
owner: product
updated: 2026-08-12
normative: false
---

# CosmWasm agent cheatsheet

One page for agents and external authors. **Do not** default to monorepo
`lake build` of the whole compiler tree as the product path.

Honesty: engineering Wasm + cosmwasm-vm mock (+ optional wasmd Docker rung).
Not formal, not mainnet, not hermetic Stage-0.

**Unified path:** [16-external-author-cheatsheet.md](16-external-author-cheatsheet.md)

## Path

```bash
# 0) Doctor / setup
pf setup --target cosmwasm --with-runtime -y
# NEED: wat2wasm (+ optional cosmwasm-check); cargo for cosmwasm-vm / pf run

# 1–2) Project + build
pf new cell --target cosmwasm && cd cell
pf build
# monorepo fixture:
# proof-forge-next build Examples/StateCell.lean \
#   --module Examples.StateCell --target cosmwasm -o build/v2/cw-state

# 3) Runtime gate (artifact fast-path when OutputSet has *.wasm)
pf test -t cosmwasm
# corpus: PF_COSMWASM_TEST_MODE=corpus pf test -t cosmwasm | just cosmwasm-runtime
# optional wasmd Docker: scripts/cosmwasm_wasmd_test.sh

# 4) One-shot cosmwasm-vm mock (auto-instantiate; not wasmd)
pf run -t cosmwasm -- get
pf run -t cosmwasm -- increment 5
# mode from *.cosmwasm-abi.json when present

# 5) Deploy packaging (save-only; --broadcast refused)
pf deploy -t cosmwasm --network local

# 6) Frontend skeleton (ecosystem cosmjs; no keys in PF)
pf write-ui-json -t cosmwasm --address <id>
pf scaffold-ui --template cosmwasm-dapp
# detail: docs/product/17-cosmwasm-dapp-frontend.md
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
| `Examples/UnixTimeCheck.lean` | `context.unixTimeSeconds` → Env.block.time |
| `Examples/PoseTransform.lean` | named Struct Int64 pose ops |
| `Examples/MapMini.lean` | dense Map UInt64 **cap-4 state** (MAX_LOCALS) |
| `Examples/Token.lean` | Map balances + supply (mint/transfer under MAX_LOCALS) |
| `Examples/MapDump.lean` | Map **return** as 24×u64 JSON decimals (occ/key/val, cap-8) |
| `Examples/WideShiftProbe.lean` | body-only UInt128 multiword `<<` / `>>` |
| `runtime-tests/cosmwasm/fixtures/CallerGate.lean` | context.caller / MessageInfo.sender |
| `runtime-tests/cosmwasm/fixtures/ScheduleFlow.lean` | schedule → SubMsg reply_on=never |
| `runtime-tests/cosmwasm/tests/negative_corpus.rs` | bad JSON / corrupt storage / gas pins |

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
- nested / narrow-element anonymous containers beyond admitted B-RET surface
- nonempty source **invariants** (scalar constants open)
- public `pf deploy --broadcast`
- IBC / migrate / reply entry (not in MVP)
- JSON trailing-garbage after decimal currently **accepted** (honesty pin in negative_corpus)

## Open / known product tension

- `context.chainId` fail-closed (Env.block.chain_id is String; no frozen UInt64 schema)
- `context.contractId` (self) open on CW; see dossier
- UInt128/256 are **body-only** on CosmWasm (no ABI state/param/result)
- NEAR ordinary balances: prefer `balanceOfSelfU128` (`pf.assets@1.2.0`)

## Related

- Dossier: `docs/targets/04-cosmwasm.md`
- Install surface: `docs/product/01-toolchain-install-surface.md`
