# WASM Executable Trace - Design Note (FV-4)

Status: **Counter + ValueVault scalar/event + fixed-array/u64-map storage subset implemented** (2026-07).
Tracks the in-Lean executable trace for `wasm-near` after the export,
artifact-surface, and offline-host execution-surface anchors.

## Where we are today

`ProofForge/Backend/WasmHost/Refinement.lean` pins three NEAR/Wasm anchors:

1. **IR observable trace** - the Counter, ValueVault, fixed-array storage, and
   u64-map storage scenarios are checked against the shared `IR.Semantics`.
2. **EmitWat artifact surface** - the emitted Wasm AST contains the expected
   imports, exports, helper calls, memory export, storage-key data segments,
   and host-boundary frames.
3. **Offline-host execution surface** - deterministic Borsh input bytes,
   storage snapshots, return payloads, and log payloads are derived from the
   same IR trace that the Rust offline host executes.

The offline host is still an external differential-testing boundary. The
in-Lean executable trace closes the Counter slice, the default ValueVault
scalar/event slice, and focused fixed-array/u64-map storage slices by
interpreting `EmitWat.lowerModule`'s structured `Wasm.Module` directly and
comparing its observable output to the IR reference trace.

## Goal (non-goal)

**Goal:** for the Counter scenario, the default ValueVault scenario, the
`ArrayProbe.storage_lifecycle` fixed-array scenario, and the focused
`EvmMapProbe.set_balance → read_balance` u64-map scenario, the Wasm
interpreter and the IR reference semantics produce the same observable trace,
checked by `native_decide` theorems. This moves the scalar-storage, event-log,
and focused storage-probe slices from offline-host-only differential coverage
to Tier C-diff with an in-Lean target interpreter.

**Non-goal:** a complete Wasm or NEAR VM model. The implemented slice covers
the instruction and host-call subset emitted for Counter scalar storage,
ValueVault's scalar storage, `block_index`, `log_utf8` event path, fixed u64
storage arrays, and a u64 map set/read probe. NEAR Promise, async
cross-contract behavior, gas metering, allocator reuse, hash maps, nested
paths, dynamic arrays, aggregate array elements, and chain runtime details stay
in the external offline-host/wasmtime boundary.

## Existing structured representation (already in the repo)

The interpreter targets the structured Wasm AST that already exists; no new
text parser is introduced:

- `ProofForge/Compiler/Wasm/AST.lean`:
  - `ValType`, `Import`, `Memory`, `DataSegment`, `Func`, `Block`, and `Insn`.
  - `Insn` covers stack values, locals, loads/stores, calls, structured
    `block`/`loop`/`if`, branches, and returns.
- `ProofForge/Backend/WasmHost/EmitWat.lean`:
  - `lowerModule : IR.Module -> Except _ Wasm.Module`.
  - `renderModule : IR.Module -> Except _ String`.
- `ProofForge/Backend/WasmHost/Layout.lean`:
  - scalar storage key layout for state fields.
- `ProofForge/Target/HostBridge.lean`:
  - host import metadata for NEAR and future Wasm-family reuse.

The executable-trace work consumes `EmitWat.lowerModule`'s `Wasm.Module`
directly, before WAT printing.

## Interpreter design

### Machine state

```lean
structure HostState where
  bridge : HostBridge
  input : Array Nat
  registers : Array (Nat x Array Nat)
  storage : Array (Array Nat x Array Nat)
  returnValue : Array Nat
  signerAccountId : Array Nat
  attachedDeposit : Nat

structure WasmState where
  valueStack : Array Nat
  locals : Array (String x Nat)
  memory : Array (Nat x Nat)
  host : HostState
```

Linear memory is byte-addressed and sparse. Data segments initialize storage
keys such as `"count"`. Numeric loads/stores use little-endian byte encoding,
matching the Rust offline host's `read_memory` and `write_memory` boundary.

### Instruction subset (implemented coverage)

The covered Counter, ValueVault, array, and map probe lowerings emit this
subset:

| Opcode class | Subset to model | Why |
|---|---|---|
| Stack values | `i32.const`, `i64.const`, `drop` | helper arguments/results |
| Locals | `local.get`, `local.set`, `local.tee` | `increment` local and helper params |
| Numeric ops | `i64.add/sub/mul/div/rem`, comparisons, bitwise ops, shifts, integer casts | scalar arithmetic, array/key address helpers, and helper conditionals |
| Memory | `i64.load/store`, `i32.load/store`, `i32.load8_u/store8` | Borsh and host-register buffers |
| Control flow | `if`, `block`, `loop`, `br`, `br_if`, `return` | helper branches and future bounded loops |
| Calls | internal helper calls plus host calls | `__pf_read_u64`, `__pf_write_u64`, `__pf_return_u64` |

Uncovered opcodes and host functions are interpreter errors. Fuel exhaustion
is also an interpreter error, never a hang.

### Host model

The host layer is parameterized by `HostBridge`, with the first implementation
for `.near`. The modeled NEAR functions are:

- `input` and `read_register` for the register ABI.
- `storage_read` and `storage_write` over pure host storage.
- `value_return` over linear-memory bytes.
- `signer_account_id` and `attached_deposit` for the first context/value hooks.

The same shape can be reused by CosmWasm/Soroban-style hosts once their
EmitWat path uses `HostBridge` imports.

### Entrypoint dispatch

Each exported entrypoint is found by `exportName`. A call begins by clearing
host registers and return bytes, then setting host input to the Borsh-encoded
trace arguments. The interpreter executes the exported function, recursively
calling helper functions and host imports.

### Observable projection

```lean
def observeEntrypoint (entrypoint : IR.Entrypoint) (state : WasmState) :
    Except String ObservableReturn :=
  match entrypoint.returns with
  | .unit => .ok .none
  | .u64 => .ok (.u64 (littleEndian state.host.returnValue))
  | .u32 => .ok (.u32 (littleEndian state.host.returnValue))
  | .bool => .ok (.bool (littleEndian state.host.returnValue != 0))
  | _ => .error "unsupported return type"
```

## Differential gate

```lean
def wasmExecutableTraceOk (obligation : TraceObligation) : Bool :=
  match EmitWat.lowerModule obligation.module with
  | .error _ => false
  | .ok wasm =>
      match WasmInterpreter.runTrace wasm obligation with
      | .error _ => false
      | .ok actual => actual == obligation.expected

theorem counter_wasm_executable_trace_ok :
    wasmExecutableTraceOk counterTraceObligation = true := by
  native_decide
```

The trace threads host storage across entrypoints, mirroring the IR trace
state and the Rust offline host.

## Risks / unknowns

- **Helper-function drift.** The interpreter executes the structured helper
  functions emitted by `EmitWat`, so it tracks helper changes automatically.
  New opcodes introduced by helper expansion must be added deliberately.
- **HostBridge breadth.** Only the NEAR Counter host subset is modeled now.
  Promise and async host calls remain external until a richer host semantics
  exists.
- **Memory exactness.** The interpreter models little-endian byte memory for
  values and keys, but it does not model Wasm traps, alignment costs, or gas.
- **Termination.** Fuel bounds make execution total. Any loop that exceeds the
  budget fails the check instead of hanging CI.

## Phasing

1. **Slice A (implemented):** Counter-only, scalar storage, Unit/U64 returns,
   helper calls, register ABI, storage read/write, and `value_return`.
2. **Slice B (implemented):** ValueVault scalar fields, Borsh u64 input args,
   `block_index`, mutable event-buffer globals, and event-log host calls.
3. **Slice C (implemented, focused):** fixed u64 storage arrays and a u64 map
   set/read probe, using the existing storage-key and Borsh layout helpers.
   Broader hash maps, nested paths, dynamic arrays, and aggregate array
   elements remain later slices.
4. **Slice D:** broader HostBridge reuse for non-NEAR Wasm-family targets.

## Acceptance

- `ProofForge/Backend/WasmHost/WasmInterpreter.lean` contains the in-Lean
  interpreter and host model.
- `ProofForge/Backend/WasmHost/Refinement.lean` gains
  `wasmExecutableTraceOk`, `counter_wasm_executable_trace_ok`, and
  `value_vault_wasm_executable_trace_ok`,
  `array_storage_wasm_executable_trace_ok`, and
  `map_storage_wasm_executable_trace_ok`.
- `Tests/NearWasmFormal.lean` `#check`s the executable trace and scalar
  relation theorems.
- `docs/formal-verification.md` describes the `wasm-near` Tier C-diff row as
  executable-trace coverage for the Counter + ValueVault scalar/event plus
  fixed-array/u64-map storage subset.
