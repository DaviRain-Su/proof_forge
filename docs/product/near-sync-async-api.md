---
id: PRODUCT-NEAR-SYNC-ASYNC-API
title: NEAR sync vs async API matrix (compiler + product surface)
status: draft
owner: product+architecture
updated: 2026-08-11
normative: false
---

# NEAR sync vs async API matrix

NEAR receipts and cross-contract work use **Promise** (async). ProofForge does
**not** wrap async host APIs as synchronous expressions. This page is the
product-facing honesty table for agents, CLI, and the Host SDK.

Formal Reference↔Wasm is **out of scope** here.

## 1. Platform fact

| Mechanism | NEAR host | PF product stance |
|-----------|-----------|-------------------|
| Same-receipt state mutate + view | synchronous within one receipt | **Open** (StateCell, Pose, …) |
| `attached_deposit` exact check | sync host read in entry | **Open** (`pf.assets.native.deposit`) |
| `account_balance` (self) | sync host read | **Open** (`pf.assets.native.balanceOfSelf`, UInt64 range guard) |
| `predecessor_account_id` | sync host read; **view-forbidden** | **Open** init/entry only (`context.caller`) |
| `block_index` / `block_timestamp` | sync host read; view-safe | **Open** (`context.blockHeight` / `unixTimeSeconds`) |
| Native transfer to another account | Promise batch action | **Async only** → `transferAsync` |
| NEP-141 `ft_transfer` | Promise function_call | **Async only** → `token.transferAsync` |
| Generic cross-contract call | Promise (+ optional callback) | **Async only** → `schedule` / Promise path |
| Sync `call` / sync `transfer` | would lie about completion | **Permanent fail-closed** |
| NEP-141 `ft_balance_of` | async cross-contract view | **Permanent fail-closed** as env-read |

## 2. Compiler surface (already wired)

### Sync (admitted)

- Arithmetic / control / state Cell·Map·Bytes·Option·named aggregates (pilot)
- Scalar `const` / `Op.Constant` (UInt/Int/Bool)
- Aggregate returns: named Struct/Enum, Array UInt64 N, Option UInt64, **Bytes N (1..8)**
- Context: `unixTimeSeconds`, `blockHeight`, `caller` (init/entry)
- Assets sync half: `native.deposit`, `native.balanceOfSelf`

### Async (admitted as fire-and-forget)

- `pf.assets.native.transferAsync(dst, amount)` → promise transfer
- `pf.assets.token.transferAsync(mint, dst, amount)` → NEP-141 `ft_transfer` + 1 yocto
- `schedule` → promise function_call (pilot)

**Honesty:** async failure does **not** roll back the caller receipt; no response
cursor is exposed in the expression language.

### Permanent fail-closed (not debt)

- `pf.assets.native.transfer` (sync)
- `pf.assets.token.transfer` (sync)
- `pf.assets.token.balanceOfSelf`
- Generic sync `call` result-bearing
- view-path `context.caller`
- dense Map **return** (leaf explosion past B-RET cap of 8)

## 3. Other async-shaped targets (same discipline)

| Target | Sync assets / calls | Async encoding | Product note |
|--------|---------------------|----------------|--------------|
| **EVM** | native payable + CALL (sync) | `schedule` fire-and-forget same-tx | Anvil + `pf test -t evm` |
| **Solana** | System/Token CPI (sync in ix) | no Promise model | Mollusk + `pf test -t solana` |
| **CosmWasm** | Bank send as SubMsg (sync-ish same-tx) | `schedule` → SubMsg `reply_on:never` | `pf test -t cosmwasm`; sync call FC |
| **TON** | — | `createMessage` async subset | `pf test -t ton`; pf.assets frozen |
| **NEAR** | deposit / balanceOfSelf / context | Promise transfer / ft_transfer / schedule | this doc; `pf test -t near` |

Agents must not unify “transfer” across chains into one sync API.

## 4. Product CLI / SDK / MCP mapping

| Surface | NEAR command | Notes |
|---------|--------------|-------|
| Build | `pf build -t near` / `proof-forge-next build … --target near` | Wasm + near-abi + wat |
| Test | **`pf test -t near`** | `scripts/pf_near_test.sh`: **artifact fast-path** when `*.wasm` present (one suite, no full rebuild); `PF_NEAR_TEST_MODE=corpus` for all 15; skip-clean if tools missing |
| Local | **`proof-forge-next local --target near`** | same script path as product local JSON |
| Deploy | **`pf deploy -t near`** | save-only package; **`--broadcast` refused** (all nets) |
| Network catalog | `pf network list --family near` | `near.local.sandbox`, `near.testnet` (catalog only) |
| Host SDK | `ProofForgeClient.build/doctor/install` + `local(target="near"\|"cosmwasm")` | spawn CLI only; no second compiler |
| MCP | `pf_build`, `pf_local` (near/cosmwasm/ton runtime), `pf_chain_catalog` | no broadcast tools |

## 5. Agent rules (short)

1. Prefer **sync** APIs for business logic that must complete in one receipt.
2. Use **`*Async` / `schedule`** only when fire-and-forget is acceptable.
3. Never ask the compiler for sync transfer/call on NEAR — that is intentional FC.
4. Runtime evidence = near-sandbox scripts / `pf test -t near`, not testnet keys.
5. Do not claim formal refinement from sandbox PASS.

## 6. Related

- Dossier: `docs/targets/03-near.md`
- Cheatsheet: `docs/product/near-agent-cheatsheet.md`
- Roadmap: `docs/plan/near-parity-roadmap.md`
- ADR-0029 / ADR-0030 pf.assets; ADR-0031 context
