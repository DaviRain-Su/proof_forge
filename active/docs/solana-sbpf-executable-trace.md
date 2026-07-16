# Solana sBPF Executable Trace — Design Note (FV-4)

Status: **Counter + ValueVault scalar/event + fixed-array/u64-map storage subset implemented** (2026-07).
Tracks the in-Lean Solana refinement step after the artifact-surface anchor
landed in #77 / #78.

## Where we are today

`ProofForge/Backend/Solana/Refinement.lean` pins three Solana FV-4 anchors:

1. **IR observable trace** (`counter_ir_observable_trace_ok`,
   `value_vault_ir_observable_trace_ok`,
   `array_storage_ir_observable_trace_ok`,
   `map_storage_ir_observable_trace_ok`, `revert_rollback_ir_trace_ok`) — the
   Counter scenario, default ValueVault scenario, focused storage array/map
   probe scenarios, and revert-rollback invariant are checked against the
   shared `IR.Semantics`.
2. **sBPF artifact-surface** (`counter_sbpf_artifact_surface_ok`) — the rendered
   sBPF assembly *contains* a dispatch label for every IR entrypoint name.
3. **sBPF executable trace** (`counter_sbpf_executable_trace_ok`,
   `value_vault_sbpf_executable_trace_ok`,
   `array_storage_sbpf_executable_trace_ok`,
   `map_storage_sbpf_executable_trace_ok`) — the lowered structured `AstNode`
   program runs in the in-Lean interpreter and produces the same observable
   returns as the IR reference trace for the implemented scalar/event and
   fixed-array/u64-map storage slices.

The artifact-surface check is a text-containment test against
`SbpfAsm.renderModule`. It catches dropped/renamed entrypoints but proves
nothing about what the assembly *does*. This note scopes the lift to an
**executable sBPF trace**: a small Lean interpreter over a subset of the sBPF
instruction set, and a differential gate that checks the interpreter's
observable output against the IR reference trace.

## Goal (non-goal)

**Goal:** for the Counter scenario, the default ValueVault scenario, the
`ArrayProbe.storage_lifecycle` fixed-array scenario, and the focused
`EvmMapProbe.set_balance → read_balance` u64-map scenario, the sBPF
interpreter and the IR reference semantics produce the same observable return
words, checked by `native_decide` theorems. This moves the scalar/event and
focused storage-probe slices from "artifact-surface only" to Tier C-diff (see
[formal-verification.md](formal-verification.md)).

**Non-goal:** a complete sBPF model. We cover the instruction and syscall
subset emitted for Counter scalar storage, ValueVault's scalar storage,
instruction-data arguments, `Clock.slot`, `sol_log_64_` event path, fixed
u64 storage arrays, and a linear-scan u64 map slab. Full sBPF semantics
(CPI, PDA derivation, broad syscalls, hash maps, nested paths, dynamic arrays,
and a complete account model) stays in the external differential-testing trust
boundary (Mollusk / Surfpool), out of scope for the Lean proof.

## Existing structured representation (already in the repo)

The interpreter targets the structured AST that already exists; no new IR:

- `ProofForge/Backend/Solana/Asm.lean`:
  - `Reg` (`r0`..`r10`, with `r10` = frame pointer / stack)
  - `Imm` (`num` / `sym`), `MemOff`
  - `Opcode` (64/32-bit ALU, loads, stores, endian, control flow, `call`,
    `exit`) — see `Opcode.isRegOp` / `isLoad` / `isStore` / `isStoreReg` /
    `isCondJump` / `isEndian` helpers.
  - `Inst` (`opcode`, `dst`, `src`, `off`, `imm`)
  - `AstNode` (`sectionDecl` / `globalDecl` / `equDecl` / `label` /
    `instruction` / `data` / `comment` / `blankLine`)
- `ProofForge/Backend/Solana/SbpfAsm.lean`:
  - `lowerModule : IR.Module → Except LowerError (Array AstNode)` (the lowering
    whose output we interpret).
  - `renderModule : IR.Module → Except LowerError String` (current
    artifact-surface input).

So the executable-trace work consumes `lowerModule`'s `Array AstNode` directly
instead of its rendered text.

## Interpreter design

### Machine state

```lean
structure SbpfState where
  regs    : Array Nat       -- index 0..10 (r10 is the stack frame pointer)
  stack   : Array Nat       -- scratch / local slots, addressed via r10 + off
  entryR0 : Nat             -- observable return word (r0 at `exit`)
  pc      : Nat             -- program counter into the flattened instruction list
```

A label table maps `entry_<name>` labels to instruction indices, built by a
pre-pass over the `AstNode` array. `equDecl`s resolve symbol immediates
(`Imm.sym`) to `Nat`.

### Instruction subset (implemented coverage)

The current covered lowering (`SbpfAsm.Stmt` + `SbpfAsm.Expr`) emits, for the
Counter, ValueVault, fixed-array, and u64-map probe entrypoints:

| Opcode class | Subset to model | Why |
|---|---|---|
| ALU 64-bit | `mov64`, `add64`, `sub64`, `mul64`, `div64`, `mod64`, bitwise ops, shifts | scalar arithmetic, address computation |
| Load immediate | `lddw` (split into two pseudo-insns) | loading constants |
| Load register-relative | `ldxdw` (`ldxw` if 32-bit) | reading scratch slots |
| Store register-relative | `stxdw` (`stxw`) | writing scratch slots (the counter slot) |
| Control flow | `ja`, `jeq`, `jne`, `jge`, `jlt`, `exit` | entrypoint dispatch, bounds checks, map scan loops, return |
| Syscall stub | `call` (`sol_set_return_data`, `sol_get_clock_sysvar`, `sol_log_64_`) | return words, `Clock.slot`, scalar event logging |

Storage model: scalar fields, fixed u64 arrays, and u64 map entries use the
same account-data offsets computed by `StateLayout.lean` and emitted as
`.equ` constants by `SbpfAsm.lowerModule`. Unsupported syscall indices remain
interpreter errors (out of the covered subset).

### Entrypoint dispatch

The Solana lowering emits a dispatch prologue that compares an account-input
discriminator and jumps to `entry_<name>`. The interpreter:

1. Sets `r1` to the discriminator bytes for the entrypoint under test.
2. Runs from the program start until the dispatch `jeq` fires and transfers to
   `entry_<name>`.
3. Runs the entrypoint body until `exit`.
4. Records `r0` at `exit` as the observable return.

### Observable projection

```lean
def SbpfState.observableReturn (entrypoint : IR.Entrypoint) (st : SbpfState) :
    ObservableReturn :=
  match entrypoint.returns with
  | .u64 => .u64 st.entryR0
  | .unit => .none
  | _ => .error "sBPF interpreter subset only models U64/Unit returns"
```

This reuses the existing `ObservableReturn` from `Solana/Refinement.lean`
(now including `.reverted` from #78).

## Differential gate

```lean
def TraceObligation.sbpfExecutableTraceOk (obligation : TraceObligation) : Bool :=
  match lowerModule obligation.module with
  | .error _ => false
  | .ok nodes =>
    match SbpfInterpreter.runTrace nodes obligation.entrypoints with
    | .error _ => false
    | .ok actual => actual == obligation.expected

theorem counter_sbpf_executable_trace_ok :
    counterTraceObligation.sbpfExecutableTraceOk = true := by
  native_decide
```

`SbpfInterpreter.runTrace` threads `SbpfState` across entrypoints so the
counter persists across `initialize → get → increment → get`, mirroring the IR
trace layer.

## Risks / unknowns

- **Dispatch prologue shape.** The dispatch label naming is owned by
  `SbpfAsm.lowerModuleCoreWithSeed`; if it changes, the interpreter's label
  lookup must track it (same lockstep risk as the current
  `hasEntrypointDispatch`). Mitigation: the interpreter reads labels from the
  lowered `AstNode` array, not a hard-coded string.
- **`call` syscall coverage.** The implemented slice models
  `sol_set_return_data`, `sol_get_clock_sysvar`, and `sol_log_64_`.
  CPI/PDA/hash/memory syscalls stay out of scope.
- **Termination.** The interpreter must terminate on the Counter instruction
  subset. `boundedFor` lowers to a fixed-trip loop, so a step budget
  (configurable, default a few thousand) makes the interpreter total; exceeding
  the budget is an interpreter error, not a hang.

## Phasing

1. **Slice A (implemented):** Counter-only, scalar storage, U64/Unit
   returns, ALU/load/store/jump/exit subset. One `native_decide` theorem.
2. **Slice B (implemented):** ValueVault scalar fields, instruction-data u64
   params, `Clock.slot` reads, and `sol_log_64_` event calls.
3. **Slice C (implemented, focused):** fixed u64 storage arrays and a u64
   map set/read probe, backed by the same account-data offset model as the
   lowered sBPF artifact. Broader hash maps, nested paths, dynamic arrays, and
   aggregate array elements remain later slices.
4. **Slice D (research):** account-validation prologue obligation, PDA
   derivation syscall sequence obligation — these stay differential gates
   against Mollusk/Surfpool unless a fuller sBPF model lands.

## Acceptance

- `Solana/Refinement.lean` gains `sbpfExecutableTraceOk` and
  `counter_sbpf_executable_trace_ok` /
  `value_vault_sbpf_executable_trace_ok` /
  `array_storage_sbpf_executable_trace_ok` /
  `map_storage_sbpf_executable_trace_ok` (native_decide).
- The interpreter lives in `ProofForge/Backend/Solana/SbpfInterpreter.lean`
  (pure Lean, total via step budget, no external tools).
- `solana-refinement-smoke` is extended to `#check` the executable-trace
  theorem; `just solana-light` runs it locally without `sbpf`/`surfpool`.
- `docs/formal-verification.md` Tier C-diff row for `solana-sbpf-asm` is
  updated from "artifact-surface only" to "executable-trace (Counter +
  ValueVault scalar/event + fixed-array/u64-map storage subset)".
