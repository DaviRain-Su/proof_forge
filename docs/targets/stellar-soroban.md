# Stellar Soroban Target

Status: **Counter MVP (PF-P3-02 six-gate, 2026-07-10)** — registry id
`wasm-stellar-soroban` is live; product Counter sources lower through
`EmitWat` + `HostBridge.soroban`, validate with `wat2wasm`, and execute the
Counter lifecycle on the offline host (`just soroban-promotion`).

**SPIKE honesty retained where incomplete:** in-Lean and offline-host
`require_auth_for_args` are always-authorised (not real Env auth);
`invoke_contract` is a spike stub (records slices, returns handle 0);
Stellar CLI / sandbox / TTL archival are **not** yet promotion gates.
Portable product triad remains EVM · Solana · NEAR.

**Product queue (2026-07 close-out):** EVM · Solana · NEAR portable crosscall
paths are the closed triad. **Soroban is the next Wasm-host spike** after that
triad; CosmWasm full crosscall and Cloudflare Workers product path are
**deferred**. Portable crosscall maps to native form `soroban-invoke` (honest)
— **not** NEAR `promise_create`.

**EmitWat honesty (landed):** `renderModule m .soroban` **rejects** modules
that use portable `crosscall.invoke` or NEAR Promise constructors with an
explicit diagnostic (`soroban-invoke` not lowered yet). Storage-only modules
(e.g. Counter) still lower. Host surface today is storage/auth
(`_put` / `_get` / `require_auth_for_args`); client-style cross-contract invoke
is the next engineering step.

Candidate target id: **`wasm-stellar-soroban`**

This note records the first ProofForge classification for Stellar smart
contracts, commonly associated with Soroban. It does not add a Lean target
profile yet.

Primary sources:

- [Stellar smart contracts overview](https://developers.stellar.org/docs/build/smart-contracts/overview)
- [Getting Started](https://developers.stellar.org/docs/build/smart-contracts/getting-started)
- [Setup](https://developers.stellar.org/docs/build/smart-contracts/getting-started/setup)
- [Hello World](https://developers.stellar.org/docs/build/smart-contracts/getting-started/hello-world)
- [Deploy to Testnet](https://developers.stellar.org/docs/build/smart-contracts/getting-started/deploy-to-testnet)
- [Storing Data](https://developers.stellar.org/docs/build/smart-contracts/getting-started/storing-data)
- [Contract Storage](https://developers.stellar.org/docs/build/guides/storage)
- [Contract Authorization](https://developers.stellar.org/docs/build/guides/auth/contract-authorization)

## Classification

Stellar/Soroban belongs in the Wasm-host family, but it must be a separate
target from NEAR and CosmWasm.

```text
Stellar smart contract target
  -> Rust/Soroban SDK authoring model today
  -> Wasm artifact compiled for wasm32v1-none
  -> Stellar host environment and Env API
  -> Stellar CLI validation, deploy, and invoke flow
```

This is not "generic Wasm." Wasm is the executable artifact format. The contract
ABI, host functions, storage model, authorization model, deployment lifecycle,
resource limits, and tooling are Stellar-specific.

## Why This Matters For ProofForge

The existing Wasm-family direction is correct: share only the common Wasm
runtime pieces, and keep chain adapters separate.

For Soroban, the target-specific concerns are:

- contracts are currently Rust/Soroban SDK programs compiled to Wasm;
- the setup path uses Rust `v1.84.0` or newer and the `wasm32v1-none` target;
- `stellar contract build` is the first native build command to mirror;
- deployment is a two-step model: upload/install Wasm bytes, then instantiate a
  contract ID that points at those bytes;
- storage has instance, persistent, and temporary forms, with TTL and archival
  semantics;
- authorization is explicit through address-based calls such as
  `require_auth()` and `require_auth_for_args()`;
- contract accounts can implement `__check_auth()` for custom authorization;
- cross-contract calls use generated client-style calls and host-managed
  authorization context;
- events, tokens, and Stellar Asset Contract integration are target-native
  surfaces, not generic Wasm features.

## Candidate Target Family

Candidate family:

```text
wasm-host
```

Candidate artifact shape:

```text
stellar-soroban-package
  - Wasm module
  - contract spec/interface metadata
  - deployment manifest for upload + instantiate
  - optional generated bindings
  - validation/test report from Stellar CLI or sandbox
```

The first ProofForge artifact should be reviewable and runnable through the
Stellar CLI or sandbox before claiming broader platform support.

## Candidate Capabilities

Most core capabilities overlap with existing Wasm-host targets:

| Existing capability | Soroban interpretation |
|---|---|
| `storage.scalar` | Instance/persistent/temporary contract storage entry. |
| `storage.map` | Typed key-value storage through Soroban storage maps. |
| `caller.sender` | Source account/invoker context where available. |
| `events.emit` | Contract event publishing. |
| `crosscall.invoke` | Cross-contract invocation through generated clients. |
| `env.block` | Ledger/network context reads. |
| `crypto.hash` | Host/Soroban SDK crypto helpers. |

Candidate capabilities that may need explicit ids later:

| Candidate capability | Meaning |
|---|---|
| `auth.require` | Address-level authorization through `require_auth` or equivalent payload binding. |
| `auth.account_contract` | Contract account authorization through `__check_auth`. |
| `storage.ttl` | Explicit TTL extension, archival, and restoration behavior. |
| `artifact.contract_spec` | Contract interface/spec metadata used by CLI and generated bindings. |
| `asset.stellar` | Stellar Asset Contract or token-interface integration. |

Do not add these ids to `ProofForge.Target.Capability` until a target profile
and lowering rules are reviewed.

## Implementation Road

### Road 1: Native Soroban Package Sourcegen

This is the most conservative first spike. Generate or wrap a Rust/Soroban SDK
package that can be built with the Stellar CLI.

First spike:

- choose a Counter-like storage example;
- generate a minimal Soroban package or manifest around hand-authored Rust;
- build with `stellar contract build`;
- validate tests with `cargo test` or Stellar's sandbox path;
- record the Wasm path, contract spec, and tool versions in artifact metadata.

This path validates target semantics before attempting a direct Lean runtime
bridge.

### Road 2: Wasm Host Bridge

This road mirrors NEAR/CosmWasm more directly: Lean lowers to a Wasm module and
a Stellar-specific host bridge.

First spike:

- define the minimal `Lean.Stellar` SDK surface;
- map storage, events, and authorization to Soroban host calls;
- emit a Wasm artifact acceptable to Stellar tooling;
- prove that the generic Wasm runtime does not force-link NEAR or CosmWasm
  bridge code.

This should wait until the Wasm runtime split is real enough to avoid another
one-off adapter.

## Non-Goals (still open after Counter MVP)

- Do not merge Soroban with `wasm-near` or `wasm-cosmwasm`.
- Do not treat Rust/Soroban SDK details as ProofForge's long-term IR.
- Do not ignore TTL/state archival when modeling storage beyond the
  shared host-key map used for Counter scalars.
- Do not model authorization as real Stellar `require_auth` until Env auth
  is wired (always-auth remains spike honesty).
- Do not claim Stellar CLI deploy/invoke until those tools are gated.

## PF-P3-02 six-gate evidence (Counter fragment)

| Gate | Evidence |
|---|---|
| 1 Input loaded | `proof-forge build --target wasm-stellar-soroban Examples/Product/Counter.lean` |
| 2 Fragment honesty | Artifact `hostBridge=soroban`; no NEAR wrapper swap; TokenSpec still unsupported |
| 3 Plan → AST → package | EmitWat + `HostBridge.soroban` (`_get`/`_put`, no `promise_create`) |
| 4 Toolchain | `wat2wasm` final stage (`validation.wat2wasm=passed`) |
| 5 Runtime | offline-host Counter `initialize/get/increment/get` → 0→1 |
| 6 Docs surface | registry + `--list-targets` + README + this note |

Command: `just soroban-promotion` / `scripts/cli/soroban-promotion-smoke.sh`.

## Research Exit Criteria

Soroban can leave Research only when we have:

- a reviewed target profile proposal;
- a decided first spike path: native Soroban package sourcegen or direct Wasm
  host bridge;
- a minimal Counter-like shared scenario;
- a documented toolchain requirement set, including Rust, `wasm32v1-none`, and
  Stellar CLI;
- at least one reproducible local validation command;
- artifact metadata for Wasm, contract spec, deployment manifest, and validation
  result.

## Phase 4 First Spike (2026-07-08) — WASM host-family adapter

The first Soroban spike took Road 2 (Wasm Host Bridge) and proved the WASM
host-family thesis: a new WASM chain is a thin `*Host.lean` on top of the
shared `WasmExec` core, not a forked EmitWat.

Landed:

- `ProofForge.Target.HostBridge.soroban` — third `HostBridge` variant (after
  `.near` / `.cosmWasm`) with `requiredExports`, `requiredImports`, and
  `hostFunctions` for storage/auth plus portable crosscall
  (`_put` / `_get` / `log_from_slice` / `require_auth_for_args` /
  `invoke_contract`).
- `ProofForge.Backend.WasmHost.WasmInterpreter.runSorobanHostCall` +
  `sorobanHostArity` + `runHostCall` dispatch arm. The storage model is the
  same byte-keyed `lookupStorage?` / `writeStorage` table NEAR and CosmWasm
  use, so contract-axis proofs reuse the same abstract scalar reasoning.
  `invoke_contract` is a spike stub (reads packed slices, returns handle `0`).
- EmitWat with `bridge = .soroban`: portable `crosscall.invoke` → host
  `invoke_contract` (shared string pool + JSON args); NEAR `promise_*` never
  imported; Promise host-extension constructors rejected. Scalar storage uses
  `_get`/`_put` (not NEAR `storage_*`). Entrypoints that read `caller` emit
  `require_auth_for_args` prologue. Logical peers rewrite via `PeerMap`.
- `ProofForge.Backend.WasmHost.SorobanHost.lean` — thin host-call lemmas
  (`_get` hit/miss, `_put`, `set_return_data`, `log`, `require_auth`,
  `invoke_contract`) + `soroban_host_smoke_ok`.
- `ProofForge.Backend.WasmHost.CounterSorobanRefinement.lean` — Counter
  universal C-proof reusing the SAME host-agnostic
  `counterWasmCoreTraceStep` core as NEAR/CosmWasm; only the host
  instantiation differs.
- `just wasm-soroban-host-smoke` (in `just check`) — machine-checked witness.
- `just crosscall-materialize` — asserts Soroban WAT contains `invoke_contract`
  and never `promise_create`.
- `ProofForge.Target.Registry.wasmStellarSoroban` — in `Registry.all` /
  `--list-targets` (`hostBridge? = .soroban`); materialize / preflight /
  `forProfile` → `soroban-invoke`. Stellar CLI + contract-spec still follow-on.
- `Target.Preflight.runPrimaryWithSoroban` — primary triad + Soroban form.

Not yet done (future Soroban spikes): real Soroban `Env` API (instance /
persistent / temporary storage with TTL, real `require_auth`, ledger reads,
`Address`/`Symbol`/`Vec<Val>` invoke), EmitWat storage name remap off NEAR
`storage_*`, `wasm32v1-none` artifact emit, Stellar CLI build/deploy/invoke
validation, promote profile into `Registry.all` / `--list-targets`.
