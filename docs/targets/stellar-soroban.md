# Stellar Soroban Target

Status: **Counter MVP (refreshed 2026-07-15)** — registry id
`wasm-stellar-soroban` is live. Product Counter sources lower through
`EmitWat` + `HostBridge.soroban` (and, for Counter, a bridge-tagged
canonical `WasmHostModulePlan`), validate with `wat2wasm`, and execute the
Counter lifecycle on the **ProofForge offline host** (`just soroban-promotion`,
`just soroban-counter-offline`). This is **not** a Stellar-network deployable
backend yet.

**Scheduling (2026-07-15):** deep Soroban work is **queued after** the
primary-triad **direct authoring cutover** lands. That work is tracked in
[PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104)
(`DaviRain-Su/authoring-cutover-comparison`: Authored → Canonical Core →
target-owned plans + native differential evidence). Do not open large
HostABI / Env / CLI epics on a dual-authoring mainline. Allowed in parallel:
docs honesty, pure design notes, and CI-only maintenance. See
[Wasm-host analysis](../superpowers/specs/2026-07-12-wasm-host-target-analysis.md)
and decision **D-056**.

**SPIKE honesty (do not over-claim):**

| Claim | Reality |
|---|---|
| Runtime | offline-host Wasmtime implements a **custom** bridge ABI |
| Real Soroban Env | `tools/soroban-vm-runner` is a **placeholder** (not functional) |
| `require_auth_for_args` | always-authorised in Lean interpreter and offline host |
| `invoke_contract` | spike stub (records packed slices, returns handle `0`) |
| HostABI | hybrid: some Soroban names (`_get`/`_put`/`set_return_data`) plus retained NEAR-shaped helpers |
| Storage | flat host key-value map (not instance/persistent/temporary + TTL) |
| Token / NFT | no TokenSpec or NFT lane |
| Stellar CLI | not a promotion gate |
| Product triad | remains `evm` · `solana-sbpf-asm` · `wasm-near` only |

Portable crosscall maps to native form `soroban-invoke` (honest label) —
**not** NEAR `promise_create`. CosmWasm full crosscall remains deferred;
Move and Cloudflare backends were removed from `main` (D-055).

Target id: **`wasm-stellar-soroban`**

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
  -> (today) Lean portable IR → EmitWat + HostBridge.soroban → custom host ABI
  -> (goal) Wasm acceptable to real Soroban Env + Stellar CLI
  -> Stellar host environment (Env, Val/ScVal, auth, TTL storage)
  -> Stellar CLI validation, deploy (upload + instantiate), and invoke
```

Wasm is only the executable envelope. ABI, host functions, storage model,
authorization, deployment lifecycle, resource limits, and tooling are
Stellar-specific. Sharing EmitWat with NEAR does **not** share semantics.

## Why This Matters For ProofForge

The Wasm-family direction stays: share only the common Wasm runtime pieces,
and keep chain adapters separate (D-028 / D-054).

For Soroban, the target-specific concerns are:

- production contracts today are Rust/Soroban SDK programs for `wasm32v1-none`;
- `stellar contract build` is the first native toolchain mirror for a real Env path;
- deployment is upload/install Wasm, then instantiate a contract id;
- storage has instance, persistent, and temporary forms, with TTL and archival;
- authorization is explicit (`require_auth` / `require_auth_for_args` / `__check_auth`);
- cross-contract calls use host-managed auth context and typed values, not NEAR promises;
- events, tokens, and Stellar Asset Contract integration are target-native.

## Candidate Capabilities

Most core capabilities *name* the same as other Wasm hosts; **registration
must not exceed what the bridge implements**.

| Capability | Counter MVP (today) | Production goal |
|---|---|---|
| `storage.scalar` | flat offline KV via `_get`/`_put` | instance/persistent/temporary + TTL |
| `storage.map` | advertised; limited product evidence | typed maps / object keys |
| `caller.sender` | auth prologue always-auth stub | real invoker / `require_auth` |
| `events.emit` | log host surface | contract events |
| `crosscall.invoke` | emit path → stub `invoke_contract` | real Env invoke + returns |
| `env.block` | **registry advertises; ValueVault fail-closed** | ledger sequence/timestamp |
| `crypto.hash` | hybrid/TODO vs HostABI | Env crypto helpers |

Candidate ids (do not add until a reviewed plan owns them):

| Candidate | Meaning |
|---|---|
| `auth.require` | Address-level authorization |
| `auth.account_contract` | `__check_auth` contract accounts |
| `storage.ttl` | TTL extension, archival, restoration |
| `artifact.contract_spec` | CLI/bindings interface metadata |
| `asset.stellar` | Stellar Asset Contract / token interface |

## Implementation Roads

### Road 1: Native Soroban Package Sourcegen (not chosen for first spike)

Generate or wrap a Rust/Soroban SDK package built with Stellar CLI. Deferred;
Road 2 landed first.

### Road 2: Wasm Host Bridge (current path)

Lean lowers to Wasm with a Stellar-specific host bridge. First spike proved
the family thesis: thin `*Host.lean` on shared `WasmExec`, not a forked EmitWat.

### Road 3 (next after cutover): Honesty → native HostABI → real Env

Ordered slices (do not start deep code until D-056 / PR #104 baseline lands):

| Slice | Goal | Exit evidence |
|---|---|---|
| **S0** | Honest capability/registry/docs vs implemented fragment | ValueVault and over-wide caps fail closed with stable diagnostics; README/target note agree |
| **S1** | De-NEAR HostABI | WAT imports match Soroban HostABI only; no silent NEAR `storage_*` / hybrid context leftovers for supported paths |
| **S2** | Single canonical path | Authored → `buildFromCore` → `lowerFromPlan` is the product route for Counter; EmitWat is oracle/compat only |
| **S3** | Crosscall simulation depth | `invoke_contract` returns useful offline results; RemoteCall differential |
| **S4** | Real Soroban Env | Val/ScVal boundary design; `soroban-vm-runner` runs Counter; then Stellar CLI deploy gate |
| **S5** | Product depth | ValueVault, Token/NFT intent only via IntentMaterializer after Env truth |

## Non-Goals (still open after Counter MVP)

- Do not merge Soroban with `wasm-near` or `wasm-cosmwasm`.
- Do not treat Rust/Soroban SDK details as ProofForge's long-term IR.
- Do not ignore TTL/state archival when modeling storage beyond Counter KV.
- Do not model authorization as real Stellar `require_auth` until Env auth is wired.
- Do not claim Stellar CLI deploy/invoke until those tools are gated.
- Do not expand TokenSpec/NFT onto Soroban while the primary triad cutover is open.

## PF-P3-02 six-gate evidence (Counter fragment)

| Gate | Evidence |
|---|---|
| 1 Input loaded | `proof-forge build --target wasm-stellar-soroban Examples/Product/Counter.lean` |
| 2 Fragment honesty | Artifact `hostBridge=soroban`; no NEAR wrapper swap; TokenSpec unsupported |
| 3 Plan → AST → package | EmitWat + `HostBridge.soroban` (`_get`/`_put`, no `promise_create`) |
| 4 Toolchain | `wat2wasm` final stage |
| 5 Runtime | offline-host Counter `initialize/get/increment/get` → 0→1 |
| 6 Docs surface | registry + `--list-targets` + README + this note |

Commands: `just soroban-promotion`, `just soroban-public-route`,
`just soroban-counter-offline`, `just wasm-soroban-host-smoke`.

## Landed (Phase 4 + B3, through 2026-07-15)

- `HostBridge.soroban` with host function table for storage/auth/crosscall stubs.
- `WasmInterpreter` / `SorobanHost.lean` lemmas; `CounterSorobanRefinement`.
- EmitWat `bridge = .soroban`: scalar `_get`/`_put`, `set_return_data`,
  portable `crosscall.invoke` → stub `invoke_contract`; NEAR promise constructors
  rejected; caller entrypoints may emit always-auth prologue.
- Canonical: `ModulePlan.Core.buildFromCore` accepts `.soroban` (reuses NEAR
  layout builder + bridge tag); `lowerFromPlan` emits Soroban imports for
  Counter (see `Tests/Canonical/SorobanPublicRoute.lean`).
- Registry profile in `knownIds`; CLI `build`/`check` for `contract_source`;
  `emit` fixture path intentionally unmapped.
- Offline-host implements the **custom** bridge; not the real Env.

## Open gap inventory (engineering truth)

### P0 — honesty / fail-closed

- Registry capability set is wider than proven product evidence (`env.block`,
  maps, crypto, crosscall depth).
- Auth always-auth; invoke stub; must stay documented until Env work.
- Fixture `emit --target wasm-stellar-soroban` is not supported (by design today).

### P1 — architecture (post–authoring cutover)

- `buildFromCore` still rewrites planning through a NEAR-shaped layout path.
- HostABI retains NEAR helper names/TODOs (`input`, account ids, ledger fields).
- Dual lowering (EmitWat vs canonical plan) should converge on one product path.
- No Soroban-native parameter/result ABI plan (XDR / contract-spec / ScVal).

### P2 — real Stellar runtime

- Real Env import set (Val objects / handles) ≠ ptr/len custom ABI.
- `tools/soroban-vm-runner` not functional until Env migration.
- Storage TTL / archival; real `require_auth`; ledger context.
- Deploy lifecycle metadata (upload + instantiate); Stellar CLI gates.

### P3 — product depth

- ValueVault, RemoteCall e2e, Token/NFT, rich SDK schema, resource budgets, FV beyond Counter.

## Research / maturity exit (toward Experimental)

Soroban may leave **Counter MVP** only when:

1. Authoring cutover baseline is on `main` (D-056).
2. S0 honesty is closed (caps match evidence).
3. S1 HostABI is non-hybrid for the supported fragment.
4. Counter runs on **real** Soroban Env (or an equivalent Env-faithful harness), not only offline-host.
5. Artifact metadata records Wasm, contract-spec (or explicit gap), deploy shape, and validation.
6. Unsupported product shapes (TokenSpec, ValueVault until ready) fail closed with stable diagnostics.

Stellar CLI deploy/invoke may trail Env execution but must not be claimed early.
