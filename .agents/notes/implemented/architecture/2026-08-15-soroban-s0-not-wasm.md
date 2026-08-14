# Agent Note: Soroban S0 stays source-only

Status: implemented

## Problem

Registry axes for Soroban say `synchronous-auth-tree` and
`ttl-scoped-storage`. S0 already emits a `soroban-sdk` dialect `.rs` file.
The tempting read is that Finalize can grow locked Wasm, auth, and TTL
the same way CosmWasm grew `wat2wasm`.

ADR-0044 forbids that claim on `soroban-source-u64-v1`. Axis labels are
platform truth; the profile is the honesty layer.

## Decision

S0 Finalize is zero-tool: `extraFiles` empty, `deployable=false`, evidence
names stellar-cli / Wasm toolchain as absent. Unknown profiles fail
`PF-PROFILE-UNKNOWN`. Plan has no auth, TTL, durability, Address, or XDR
fields. Storage is instance get/set only.

[`docs/plan/soroban-s1-wasm-finalize-gap.md`](../../../../docs/plan/soroban-s1-wasm-finalize-gap.md)
inventories what SOR-1 would need. It does not implement SOR-1.
`SOR-1A` only pinned the honesty already required by ADR-0044.

Opening locked Wasm needs a product decision on all four: new opt-in
profile vs mutating S0; Tool Lock (stellar-cli, rustc, wasm32,
`soroban-sdk`); ambient cargo vs isolated `LockedToolchainV1`; host test
lane. Do not invent a temp `Cargo.toml` at Finalize.

## Alternatives considered

- **Mutate S0 Finalize to call `stellar` on PATH** — rejected: unlocked
  host, same class of silent toolchain ADR-0044 forbids.
- **Treat CosmWasm `wat2wasm` as the template** — rejected: CosmWasm
  Finalize is one isolated binary plus an 8-byte Wasm header check. Soroban
  Wasm is cargo / rustc / wasm32 / sdk, closer to OpenVM O1 than to
  CosmWasm.
- **Read registry axes as delivered capability** — rejected: that is the
  overclaim ADR-0044 exists to stop. Sync-call is not advertised; Principal
  / Address fail S0 type closure.
- **Hand-written spec JSON / golden Wasm without a lock** — rejected: spec
  that does not match `.rs` / Wasm is test theater; Wasm bytes drift with
  rustc/sdk.

## Consequences

Backlog `SOR-1` stays open. Goal drain must not grow S0 into Wasm, auth, or
TTL. A later opt-in profile can exist only after the four product answers
above. This note does not close formal, accepted Phase 1, or `B-CALL-SEM`.
