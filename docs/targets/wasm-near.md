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
| `contextRead contractId` | `env.current_account_id` |
| `contextRead checkpointId` | `env.block_height` |
| `eventEmit` | `env.log` |

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
| `caller.sender` | Yes | `env::predecessor_account_id()` |
| `value.native` | Partial | Rust sourcegen and EmitWat lower `nativeValue` to `env::attached_deposit()` / the `attached_deposit` host import as a U64 projection |
| `events.emit` | Yes | `near_sdk::log!` with deterministic JSON |
| `env.block` | Yes | `env::block_height()` |
| `crypto.hash` | Yes | `env::sha256`-based hash helpers |
| `assertions.check` | Yes | Lowered to Rust `assert!`/`assert_eq!` |
| `account.explicit` | Yes | `env::current_account_id()` |
| `crosscall.invoke` | No | Not supported in sourcegen v0 |
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
| `Examples/near/spike/emitwat-{regression,hashmap-smoke,arith-smoke}.cjs` | Deploy + Borsh-decode smoke tests |
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
