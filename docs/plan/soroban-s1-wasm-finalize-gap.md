---
id: PLAN-SOROBAN-S1-WASM-FINALIZE-GAP
title: Soroban S1 — locked Wasm Finalize + auth/TTL gap
status: draft
owner: engineering
updated: 2026-08-14
normative: false
---

# Soroban S1：locked Wasm / auth / TTL gap

> Engineering inventory only. Does **not** implement backlog **SOR-1**.
> Does **not** close formal TASK/TST, accepted PRD Phase 1, B-CALL-SEM, or
> hermetic/release. Does **not** invent a new `TASK-*`. S0 (ADR-0044) stays
> source-only.

Authority: [`0044-soroban-source-u64-target.md`](../adr/0044-soroban-source-u64-target.md) ·
[`05-soroban.md`](../targets/05-soroban.md) ·
[`engineering-backlog.md`](../engineering-backlog.md) `SOR-0` / `SOR-1` ·
OpenVM comparison [`0046-openvm-guest-elf-o1.md`](../adr/0046-openvm-guest-elf-o1.md) ·
CosmWasm comparison `ProofForgeV2/Targets/CosmWasm/FinalizeV1.lean`.

## 1. Why S0 must not claim Wasm / auth / TTL

| Claim S0 must not make | Why |
|---|---|
| Deployable Wasm | `FinalizeV1` is zero-tool: `deployable=false`, `extraFiles=#[]`, evidence note says no stellar-cli / Wasm toolchain. Encoding is `sorobanSource`, not `wasmText`. |
| `stellar contract build` / rustc / wasm32 | No Tool Lock row. Product finalization must not invoke those tools (ADR-0044 §决策.4). |
| Auth tree complete | Registry call axis is `synchronous-auth-tree`, but the S0 profile **does not advertise** `effect.synchronous-call`. Plan has no auth fields. `Address.require_auth` is not lowered. |
| TTL / durability complete | Registry state axis is `ttl-scoped-storage`, but S0 maps every slot to a single **instance** `env.storage().instance()` get/set. No persistent/temporary choice, no TTL numbers. |
| Contract spec / XDR | Emitter writes a `soroban-sdk` dialect `.rs` recipe. No spec JSON, no XDR, no ScVal ABI table. |
| Local invoke / host test | No stellar-cli, no local network, no SDK host test gate. |

The six-axis seed is platform truth. The **profile** is the honesty layer: S0
is `source-only` / 4-key / zero-tool. Treating axis labels as delivered
capability is the exact overclaim ADR-0044 forbids.

## 2. What S0 already emits

| Item | Code fact |
|---|---|
| Profile | Sole `soroban-source-u64-v1` (`CodegenProfileId.sorobanSourceU64V1`). Registry row has one profile; default = that id. |
| Encoding / maturity | `ArtifactEncoding.sorobanSource`; maturity `source-only`; `AcceptanceProfileRef` = `phase1.soroban-u64.v1`. |
| Capability | Resolver `sorobanRequests` = catalog minus event / sync-call / async. No `extension.pf-assets`. Exact 4-key: `failure.atomic-rollback`, `state.persistent`, `value.bool`, `value.checked-arithmetic`. |
| Plan | `programName`, `sourceHash`, `semanticHash`, `states` (name only), `initializer?`, `entries`, `views`. No auth, TTL, durability, Address, or XDR fields (`LowerSemanticV1.lean` `structure Plan`). |
| IR / file | Structured Rust AST → one `{programName}.rs`, `mediaType` `text/x-rust`. Header: `#![no_std]`, `use soroban_sdk::{contract, contractimpl, symbol_short, Env}`, `#[contract]` / `#[contractimpl]`, instance storage get/set, `checked_*` + `panic!` rollback. **No `Cargo.toml`, no `lib.rs` crate layout, no pinned `soroban-sdk` version.** |
| Finalize | `FinalizeV1.finalize` returns extras empty, `deployable=false`, note: no soroban-cli / stellar-cli / Wasm toolchain. |
| Fail-closed | nonempty invariants/constants/events, call/schedule, ContextRead/Commit (UInt64 keys named no-host), EnvRead, multi-width, aggregates, Field/Principal/String, emit. |
| Tests | `Tests/Materialization/SorobanPlanV1.lean` pins Plan/IR/source and named ContextRead/crypto/EnvRead FC. **No Finalize extraFiles / evidence-note pin today.** |

## 3. Remaining holes for SOR-1

Comparison, not a copy: OpenVM O1 adds an **opt-in second profile**
(`openvm-guest-elf-v1`) while O0 stays zero-tool. Finalize resolves
locked/ambient `cargo-openvm` 2.0.1 (`requiredByProfiles=["openvm-guest-elf-v1"]`)
and stages ELF/`.vmexe` extras; still `deployable=false`. That works because
O0 already emits a **compilable guest tree** (`guest/Cargo.toml`,
`guest/openvm.toml`). CosmWasm Finalize uses isolated
`LockedToolchainV1.resolve "wat2wasm"` on a single `.wat` and may set
`deployable=true` after an 8-byte Wasm header check — a one-binary, no-cargo
shape Soroban does not have.

### 3.1 Locked stellar-cli / rustc / wasm32 Finalize

| | |
|---|---|
| Code fact | S0 Finalize never resolves a tool. `toolchains.lock.json` has no stellar-cli / rustc / wasm32 / soroban-sdk row. Emitter output is one `.rs` file, not a cargo package. |
| Tool/lock implication | `stellar contract build` shells out to cargo / rustc / `wasm32-unknown-unknown` (ambient `PATH`/`HOME`/`CARGO_HOME`, same class as OpenVM `cargo-openvm`, **not** CosmWasm `env -i` wat2wasm). A lock must name: stellar-cli (or cargo-stellar) version, rustc channel, wasm32 target, `soroban-sdk` crate pin, and whether isolation is ambient-only. Mutating S0 Finalize to call an unlocked `stellar` on PATH would be a silent host. |
| Fixture risk | Feeding `{name}.rs` to stellar-cli without a synthesized crate will fail or pick ambient sdk. A temp `Cargo.toml` invented at Finalize is a second emitter. Golden Wasm bytes will drift with rustc/sdk unless both are pinned. |

### 3.2 Contract spec / XDR

| | |
|---|---|
| Code fact | No spec/XDR types on Plan or IR. Function names and `u64`/`bool`/`()` are Rust surface only. |
| Tool/lock implication | Spec usually comes from the compiled Wasm custom section / stellar-cli inspect, or from a second frozen encoder. Either path needs a locked build **or** a product-owned XDR writer. |
| Fixture risk | Hand-written spec JSON that does not match the `.rs` / Wasm is test theater. ScVal encoding mistakes look green until invoke. |

### 3.3 Auth tree Plan fields

| | |
|---|---|
| Code fact | Call axis `synchronous-auth-tree` is registry semantics, not a Plan field. Sync-call requirement is declined. Principal / Address fail at S0 type closure. No `require_auth` IR node. |
| Tool/lock implication | Opening auth without Address + invocation-tree fields would be always-pass (ADR-0044 explicit reject). B-CALL-SEM stays open until a versioned requirement and target-owned auth IR exist. |
| Fixture risk | A Counter that “builds” without `require_auth` can be invoked by anyone on a real host. Do not add a bool `auth=true` default. |

### 3.4 TTL / durability Plan fields

| | |
|---|---|
| Code fact | State axis `ttl-scoped-storage` is registry semantics. `PlanState` is `{ name }`. Emitter hard-codes `env.storage().instance()`. |
| Tool/lock implication | Persistent vs temporary vs instance is host lifetime, not a comment. TTL extend/expire needs numbers and a bump policy. Silent “instance = persistent” is a lie. |
| Fixture risk | Tests that only read instance storage will not catch archival / bump bugs. Do not invent TTL literals in S0. |

### 3.5 Local invoke / runtime gate

| | |
|---|---|
| Code fact | No sandbox/host test lane (unlike CosmWasm mock / TON sandbox / OpenVM elf extras). Dossier §10 lists SDK host → local network invoke as SOR-1+. |
| Tool/lock implication | Needs locked stellar-cli **and** a local network / RPC pin, plus Wasm that actually loaded. Host-optional (like ICP PocketIC) is a second product decision. |
| Fixture risk | `stellar contract invoke` against unpinned local net is non-repeatable. Do not fold this into ordinary `just ci`. |

## 4. Recommended next implementable engineering slice

**SOR-1a — S0 Finalize honesty + unknown Wasm-profile fail-closed pins.**

Do **not** open stellar-cli, rustc, Wasm extras, auth, or TTL.

Opening locked Wasm Finalize is **not safe** without a product decision on
all four of: (1) new opt-in profile vs mutating S0 (ADR-0044 already says
later independent profile — do not overwrite `soroban-source-u64-v1`);
(2) emit a real cargo guest tree vs keep a single `.rs` recipe;
(3) ambient cargo (OpenVM O1) vs isolated `LockedToolchainV1` (CosmWasm
wat2wasm — **not** a fit for stellar-cli);
(4) `soroban-sdk` / stellar-cli / rustc versions. Until those are decided,
a Tool Lock mutation or Finalize host call would either fail closed on a
non-crate `.rs` or invent a crate behind the profile.

Allowlist (one slice):

- `Tests/Materialization/SorobanPlanV1.lean` only (Fast / shard registration
  if that suite is not already on the ordinary target shard).
- Pin product Finalize: `extraFiles` empty, `deployable=false`, evidence note
  contains `stellar-cli` or `Wasm toolchain` (the live S0 string).
- Pin `--profile` other than `soroban-source-u64-v1` is **unknown** (no
  reserved wasm profile id in `TargetIdentityV1`).
- Optional comment in the suite that S0 `.rs` is not a cargo package.

**Out of allowlist:** `toolchains.lock.json`, new `CodegenProfileId`,
`FinalizeV1` behavior change, Plan schema fields, `Cargo.toml` emission,
auth/TTL, local invoke, formal TASK/TST.

This slice is safe without a product decision. It makes the S0 non-claim
mechanically testable (today there is no Finalize pin) and blocks a silent
S0→Wasm cutover.

**Pinned 2026-08-14** in `Tests/Materialization/SorobanPlanV1.lean`
(`testCapabilityProductPath` / `testUnknownProfileFailClosed`).

## 5. Non-claims

- Not accepted PRD Phase 1 (still EVM/Solana/NEAR/Noir; ADR-0036).
- Not formal D3/D4, SupportClaim, OutputSetV1, ToolchainIdentity, or
  Reference↔Soroban differential.
- Not B-CALL-SEM done. Registry `synchronous-auth-tree` ≠ advertised sync
  call ≠ `require_auth` lowering.
- Not hermetic / Stage-0 / testnet / deployable.
- This inventory does not implement SOR-1 and does not flip `SOR-1` to done.
