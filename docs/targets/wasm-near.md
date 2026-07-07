# Wasm-NEAR Target

**Target id:** `wasm-near`
**Family:** Wasm host

Two backends coexist:

- **Canonical (target state):** `EmitWat` — Portable IR → Wasm AST → WAT →
  `wat2wasm`, mirroring the in-repo portable-IR → Yul EVM backend. See
  [D-031](../decisions.md) and
  [Wasm family common shape](wasm-family.md).
- **Frozen v0 stopgap (in-repo, compiles):** Rust `near-sdk-rs` sourcegen —
  `Portable IR → near-sdk-rs package → cargo wasm32`. Validates NEAR semantics
  now; **not expanded**. Its details are documented below under
  [Frozen v0 reference](#frozen-v0-reference-rust-sourcegen).

## Canonical architecture (`EmitWat`)

```text
Portable IR (Module)
  -> EmitWat                       (portable IR -> Wasm AST; mirrors Backend/Evm/IR.lean)
  -> Wasm AST -> WAT text          (Compiler/Wasm/AST.lean + Printer.lean)
  -> wat2wasm                      (shared toolchain)
  -> NEAR-compatible Wasm          (imports env.* host functions)
```

`EmitWat` mirrors `ProofForge/Backend/Evm/IR.lean` (portable IR → Yul AST),
but targets WAT instead of Yul. Because the portable IR already abstracts over
Lean objects (only `u32`/`u64`/`bool`/`hash` scalars + storage effects), there
is **no Lean runtime to port and no object-model boxing/GC** — scalars map
directly to Wasm `i32`/`i64`, and storage/crypto/context effects lower to NEAR
host imports. The IR-lowering and validation logic is reusable from the frozen
Rust v0 (`Backend/WasmNear/IR.lean`) and from `Backend/Evm/IR.lean`; only the
emission target changes (Rust/Yul strings → Wasm AST → WAT).

Storage/crypto/context effects lower to these NEAR host imports:

| IR effect | NEAR host import |
|---|---|
| `storageScalarRead` / `storageMapGet` | `env.storage_read` |
| `storageScalarWrite` / `storageMapSet` | `env.storage_write` |
| `storageMapContains` | `env.storage_has_key` |
| `hash` / `hashTwoToOne` | `env.sha256` |
| `contextRead userId` | `env.predecessor_account_id` |
| `contextRead userIdHash` | `env.predecessor_account_id` + `env.sha256` |
| `contextRead contractId` | `env.current_account_id` |
| `contextRead checkpointId` | `env.block_index` |
| `contextRead timestamp` | `env.block_timestamp` |
| `contextRead epochHeight` | `env.epoch_height` |
| `contextRead randomSeed` | `env.random_seed` |
| `eventEmit` | `env.log` |

### NEAR Promise IR

Portable `crosscallInvoke` lowers to `promise_create` for remote calls. NEAR-specific
promise chaining and callback introspection use dedicated `Expr` forms tagged with
the `near.promise` capability on the canonical EmitWat path:

| IR expression | NEAR host import(s) | Role |
|---|---|---|
| `nearCrosscallInvokePool accountIndex methodId args deposit` | `promise_create` | Create a promise using runtime indices into `module.nearCrosscallStrings` for the account and method names. |
| `nearPromiseThen parent callbackMethod args deposit` | `promise_then`, `current_account_id` | Attach a callback method on the **current** contract to an existing promise id (`parent` is `U64`). Callback and remote method names index `module.nearCrosscallStrings` via `.literal (.address i)`. |
| `nearPromiseResultsCount` | `promise_results_count` | In callback entrypoints: how many completed promise results are visible. |
| `nearPromiseResultStatus index` | `promise_result` | Read result status at `index` (`1` = success, `2` = failed). |
| `nearPromiseResultU64 index` | `promise_result`, `read_register` | Borsh-decode the result payload at `index` as `U64` (returns `0` on failure). |

Typical shape:

```text
entry call_remote_with_callback:
  return nearPromiseThen(
    crosscallInvoke(...),
    callbackMethod = "handle_remote",
    args = [], deposit = 0)

entry handle_remote:
  return nearPromiseResultU64(0)
```

Fixture: `ProofForge/IR/Examples/NearCrosscallProbe.lean`.

### NEP-141 `ft_transfer_call` example

`Examples/WasmNear/FungibleToken.lean` reuses the
`ProofForge.Contract.Stdlib.NearFungibleToken` mixin. The generated contract
exports `ft_transfer_call(receiver_id, receiver_idx, amount)`, with Borsh input
layout `Hash || U32 || U64`:

- `receiver_id` is the portable `Hash` account key used for token balances.
- `receiver_idx` selects a registered NEAR account string from
  `module.nearCrosscallStrings`; the stdlib reserves `0 = "ft_on_transfer"`,
  `1 = "ft_resolve_transfer"`, and uses `2 + receiver_idx` for remote receiver
  account ids. In the checked example, `receiver_idx = 0` selects
  `demo.receiver.testnet`.
- `amount` is the transferred `U64`.

The promise chain emitted for that entrypoint is:

```text
ft_transfer_call
  -> promise_create(receiver account, "ft_on_transfer", [callerHash, amount])
  -> promise_then(current_account_id, "ft_resolve_transfer", [])
  -> promise_return(callback promise id)

ft_resolve_transfer
  -> nearPromiseResultU64(0) as unused
  -> refund unused balance from receiver back to sender
  -> return amount - unused
```

The static gate `just wasm-near-ft-transfer-call` verifies the Plan/EmitWat
shape, including the `nearCrosscallStrings` layout, hash JSON encoding for the
`ft_on_transfer` sender argument, and the absence of nested allowance
`mapKey+mapKey` paths. The behavior gate `just wasm-near-ft-transfer-call-e2e`
runs the generated WAT in `runtime/offline-host`, stubs the callback result as a
Borsh `U64`, and checks `promise_create` precedes `promise_then` and the refund
balances are correct.

### `caller` vs `callerHash`

`ProofForge.Contract.Surface.caller` remains the portable `userId` context
expression and lowers to a `U64` projection of `predecessor_account_id`. It is
useful for legacy U64-keyed examples, but it is not wide enough to key NEAR
account balances safely.

`ProofForge.Contract.Surface.callerHash` lowers `userIdHash` to the full
32-byte SHA-256 digest of `predecessor_account_id`. The NEP-141 stdlib uses
`callerHash` for account-keyed balances, allowance owner keys, and the
`ft_on_transfer` sender argument. `ProofForge.Contract.Surface.signer` is
separate: it reads `signer_account_id` and models the transaction signer, not
the immediate predecessor.

### Why not `EmitZig`

The earlier plan (`Lean → EmitZig → Zig → host bridge → Wasm`) is superseded
because it requires porting the full Lean runtime to Wasm (libuv / threads /
GC) — the documented blocker. `EmitWat` lowers the portable IR directly and
avoids that port entirely; it also avoids coupling to `near-sdk` macros (the
source of the E0119 / missing-`&self` bugs in the Rust v0).

### Spike gate (highest risk) — RESOLVED (EmitWat end-to-end)

NEAR passes entrypoint arguments as serialized Borsh and expects serialized
returns; contract methods export as `() -> ()` dispatchers that read args via
`env.input()`/`env.read_register` and return via `env.value_return` (not wasm
function returns).

The risk is fully de-risked, not just by the hand-written reference counter
(`examples/near/spike/handwritten-counter.wat`, ~40 lines) but by the complete
`EmitWat` backend lowering real IR modules end-to-end. The ABI is **symmetric
Borsh**: params decode from `env.input` (u32/u64/bool/hash, packed LE at
their cumulative Borsh offset) and returns encode via `value_return` of LE bytes
(u32/u64/bool) or the 32-byte hash directly — matching `near-sdk-rs`'s Borsh
convention, no JSON.

7 IR example probes deploy to `near-sandbox` and pass their scenarios via
`viewRaw` + Borsh decode (Counter / Features / Map / Hash / Context / Params /
Event), plus a `Map<Hash,Hash>` smoke (hash-keyed map) and a u32 arithmetic
smoke that exercises `.pow` (17^2=289 asserted). The four CLI emit modes
(`--emit-{counter,context,hash,map}-emitwat -o <dir>`) lower the built-in IR
examples and write `<name>.wat` + `<name>.wasm` (via `wat2wasm`) — a
deploy-ready package with no `cargo` step.

The foundational risk is resolved: the register-based host ABI and Borsh
(de)serialization are tractable at the WAT level for real IR, not just a
hand-written counter.

## Frozen v0 reference (Rust sourcegen)

The remainder of this document describes the frozen Rust `near-sdk-rs`
sourcegen backend (`ProofForge/Backend/WasmNear/IR.lean`). It is kept as a
working reference that validates NEAR semantics and capability coverage; it is
not the canonical path and is not being expanded.

**Backend pattern:** Portable IR → Rust `near-sdk-rs` package → `cargo build
--target wasm32-unknown-unknown` → NEAR-compatible Wasm.

### Capability Profile

Defined in `ProofForge/Target/Registry.lean` (`def wasmNear`):

| Capability | Supported | Notes |
|---|---|---|
| `storage.scalar` | Yes | u32, u64, bool, hash → Rust struct fields |
| `storage.map` | Yes | Map<U64, …> and Map<Hash, …> → raw `env::storage_read`/`env::storage_write` |
| `caller.sender` | Yes | EmitWat exposes `caller` as a U64 predecessor projection, `callerHash` as the full predecessor hash, and `signer` via `signer_account_id`; Rust sourcegen v0 keeps its existing account-id hash helper. |
| `value.native` | Partial | Rust sourcegen and EmitWat lower `nativeValue` to `env::attached_deposit()` / the `attached_deposit` host import as a U64 projection |
| `events.emit` | Yes | `near_sdk::log!` with deterministic JSON |
| `env.block` | Yes | `block_index`, `block_timestamp`, `epoch_height`, and `random_seed` host imports on EmitWat; `env::block_height()` in frozen Rust sourcegen |
| `crypto.hash` | Yes | `env::sha256`-based hash helpers |
| `assertions.check` | Yes | Lowered to Rust `assert!`/`assert_eq!` |
| `account.explicit` | Yes | `env::current_account_id()` |
| `crosscall.invoke` | Partial | EmitWat lowers untyped NEAR calls to Promise API; Rust sourcegen v0 rejects cross-contract calls. |
| `near.promise` | Partial | EmitWat lowers Promise chaining/result inspection/return; Rust sourcegen v0 does not. |
| `storage.array` | Partial | Target profile advertises the capability for the EmitWat path; Rust sourcegen v0 rejects array state |
| `control.conditional` | Partial | Target profile advertises the capability for EmitWat; Rust sourcegen v0 rejects `if/else` |
| `control.bounded_loop` | Partial | Target profile advertises the capability for EmitWat; Rust sourcegen v0 rejects bounded loops |
| `data.fixed_array` | Partial | Target profile advertises the capability for EmitWat; Rust sourcegen v0 rejects fixed-array ABI and expression lowering |
| `data.struct` | Partial | Target profile advertises the capability for EmitWat; Rust sourcegen v0 rejects struct ABI and expression lowering |

## Deviations from Original Plan

The implementation diverged from the original plan in several places, all
documented in [D-019](../decisions.md):

1. **Map keys widened to Hash.** The plan specified only `Map<U64, …>`, but
   `MapProbe` uses `Map<Hash, Hash, 128>`. The implementation supports both U64
   and Hash keys with separate `__pf_map_key_u64`/`__pf_map_key_hash` helpers.

2. **`.assertions` and `.accountExplicit` added.** The plan's capability list
   omitted these, but `MapProbe` uses `assertEq` and `ContextProbe` uses
   `contractId`. Both are now in the profile and lowered.

3. **`.crosscallInvoke` removed.** As planned, not supported in v0 sourcegen.

4. **`assert`/`assertEq` lowered.** Since `.assertions` is in the profile,
   these lower to Rust `assert!`/`assert_eq!` macros rather than being rejected.

5. **`ifElse`/`boundedFor` rejected.** Not in the capability profile.

6. **`nativeValue` expression rejected.** Despite `.valueNative` being in the
   profile (for the capability declaration), the expression for inspecting
   attached deposit is not supported in v0.

## Generated Package Structure

`renderPackage` produces a `NearPackage` with these files:

- `Cargo.toml` — package name sanitized from module name, dependencies on
  `near-sdk = "5"`, `borsh = "1"`, `serde = "1"`, `serde_json = "1"`
- `src/lib.rs` — `#[near(contract_state)]` struct, `Default` impl,
  `#[near] impl` block with entrypoints, and conditional helper functions

### Scalar State

Scalar state fields become Rust struct fields with `BorshDeserialize`/`BorshSerialize`:

| IR type | Rust type | Default |
|---|---|---|
| `u32` | `u32` | `0u32` |
| `u64` | `u64` | `0u64` |
| `bool` | `bool` | `false` |
| `hash` | `[u64; 4]` | `[0u64, 0u64, 0u64, 0u64]` |

### Map State

Map state uses raw NEAR KV storage through `env::storage_read`,
`env::storage_write`, and `env::storage_has_key`. Key helpers are emitted per
key type used:

- `__pf_map_key_u64(prefix, key)` — for `Map<U64, …>`
- `__pf_map_key_hash(prefix, key)` — for `Map<Hash, …>`

Codec helpers are emitted only for value types actually used by the module:
`__pf_encode_u64`/`__pf_decode_u64`, `__pf_encode_bool`/`__pf_decode_bool`,
`__pf_encode_hash`/`__pf_decode_hash`.

Map set helpers (`__pf_map_set_u64`, `__pf_map_set_bool`, `__pf_map_set_hash`)
return the previous value, matching existing Psy/EVM map semantics.

### Context Fields

| IR context field | Rust lowering |
|---|---|
| `userId` | `__pf_account_id_hash_u64(&env::predecessor_account_id())` |
| `contractId` | `__pf_account_id_hash_u64(&env::current_account_id())` |
| `checkpointId` | `env::block_height()` |

The `__pf_account_id_hash_u64` helper is emitted when either `.userId` or
`.contractId` is used.

### Hash Helpers

Emitted when `.cryptoHash` is used:

- `__pf_hash(value: [u64; 4]) -> [u64; 4]` — single-value SHA-256
- `__pf_hash_two_to_one(left: [u64; 4], right: [u64; 4]) -> [u64; 4]` — two-to-one SHA-256

### Events

`eventEmit` lowers to `near_sdk::log!` with deterministic JSON. v0 supports
`U32`, `U64`, `Bool`, and `Hash` event fields.

## CLI Modes

```
proof-forge emit --target wasm-near --fixture counter --format wat -o build/wasm-near/Counter
proof-forge emit --target wasm-near --fixture context --format wat -o build/wasm-near/ContextProbe
proof-forge emit --target wasm-near --fixture hash --format wat -o build/wasm-near/HashProbe
proof-forge emit --target wasm-near --fixture map --format wat -o build/wasm-near/MapProbe
```

`-o` is required for Wasm-NEAR target-first package emission and is interpreted
as a package output directory (not a single file). Legacy
`--emit-*-ir-wasm-near` aliases remain compatibility shims during the RFC 0009
transition.

## Implementation Files

**Canonical (EmitWat):**

| File | Purpose |
|---|---|
| `ProofForge/Backend/WasmNear/EmitWat.lean` | Core EmitWat lowering: IR → Wasm AST (scalars, maps incl. `Map<Hash,T>`, hash, context, events, params, returns, `.pow`) |
| `ProofForge/Backend/WasmNear/IR.lean` | Wasm AST → WAT text + printer wiring |
| `ProofForge/Compiler/Wasm/AST.lean` / `Printer.lean` | Wasm AST + WAT printer |
| `Tests/EmitWat{Smoke,Features,Map,Hash,Context,Params,Event,Hashmap,Arith}.lean` | Per-probe renderers |
| `scripts/near/emitwat-ci-smoke.sh` / `runtime/offline-host` | Rust offline-host execution and Borsh-decode regression gate |
| `ProofForge/Cli.lean` | `emit --target wasm-near --fixture ... --format wat` routing, `writeWatPackage`, `compileEmitWat` |

**Frozen v0 reference (Rust sourcegen):**

| File | Purpose |
|---|---|
| `ProofForge/Backend/WasmNear.lean` | Umbrella module |
| `ProofForge/Backend/WasmNear/IR.lean` | Core lowering: validation, type inference, Rust source generation (~57KB) |
| `ProofForge/Target/Registry.lean` | `wasmNear` profile with tools and capabilities |
| `ProofForge/Cli.lean` | `EmitMode` constructors, parse cases, `writeNearPackage`, compile functions |

## Required Tools

- `rustup` + `cargo` + `wasm32-unknown-unknown` target
- `near-cli` (for deployment validation; not required for source generation or cargo build)

## Verification

```sh
# Build the compiler
lake build

# Generate a Counter package
lake env proof-forge emit --target wasm-near --fixture counter --format wat -o build/wasm-near/Counter

# Build the Wasm artifact
cd build/wasm-near/Counter && cargo build --target wasm32-unknown-unknown --release

# Run diagnostics
lake env lean --run Tests/WasmNearDiagnostics.lean
```

## Open Questions

These concern the **frozen v0** (Rust sourcegen). The canonical-path open
questions live in [Wasm family common shape](wasm-family.md#open-questions).

- The v0 is frozen; capability coverage is **not** being expanded on the Rust
  route. New capabilities land on the canonical `EmitWat` path instead.
- Should `nativeValue` expression inspection (attached deposit) be added as a
  dedicated IR context field on the canonical path?
- Should map storage use `near_sdk::collections::LookupMap` in the v0 reference,
  or leave raw `env::storage_read`/`env::storage_write` as the documented
  semantics that `EmitWat` must reproduce?
