# Tier C-proof Feasibility — Machine-checked Refinement vs `powdr-labs/evm-semantics`

Status: research + design assessment (RFC 0014 Phase 5 / Tier C-proof).
Date: 2026-07-07.

## 1. Current state of ProofForge's formal assets

### 1.1 `ProofForge/Backend/Evm/Refinement.lean`

This is **not** a machine-checked refinement proof. It is an *executable trace-equivalence
check* discharged by `native_decide`:

- `TraceObligation` bundles an IR `Module`, a sequence of `TraceCall`s, and an
  `expected : Array ObservableStep`.
- `irTraceOk` runs the IR semantics (`ProofForge.IR.Semantics.runEntrypointWithArgs`)
  over the call list and compares the produced `ObservableStep` array to `expected`.
- `evmYulSurfaceOk` lowers the module with `Evm.IR.lowerModule` and checks that the
  generated Yul object exposes every entrypoint needed by the trace (top-level function
  + dispatch switch case).
- `evmYulTraceOk` runs the *in-tree pseudo-Yul semantics*
  (`ProofForge.Backend.Evm.YulSemantics.runSelectorWithArgsWithLogs`) over the lowered
  Yul object and compares observable returns/logs to `expected`.

The theorems (`counter_evm_yul_executable_trace_ok`, `value_vault_...`, etc.) are all
discharged by `native_decide`, i.e. they compile the definitions to native code and run
them. This is a *bounded* check for fixed scenarios, not a universally quantified proof.

**Strengths:** it ties the IR semantics, the Yul surface, and the in-tree Yul executor
together for a battery of representative scenarios (Counter, ValueVault, Expression,
Conditional, Loop, Event, EvmMap, TypedStorage, StorageStruct, AbiAggregate, Context).
It is the strongest executable differential check short of running real `forge` tests.

**Gap to Tier C-proof:** there is no simulation relation, no induction, no universally
quantified statement. Every theorem is `... = true` decided by evaluation. A true
Tier C-proof would state: "for *all* IR states `s` and *all* well-typed call sequences,
the observable behavior of `runEntrypointWithArgs s ep args` is matched by the behavior
of the EVM bytecode semantics on the compiled artifact." That is absent.

### 1.2 `ProofForge/Contract/Examples/ValueVaultInvariant.lean`

Also `native_decide`-discharged executable checks, not universally quantified proofs:

- `value_vault_default_trace_ok` checks the observed returns for the *default* scenario
  inputs (`initial=100, deposit=25, ...`) against a precomputed expected array.
- `value_vault_accounting_invariant_trace_ok` checks the accounting invariant
  (`balance + released + fees == supplied`) for the *default* inputs only.
- `value_vault_net_value_invariant_trace_ok` checks `net_value == balance - fees` for
  the *default* inputs only.

A real invariant theorem would be: "for *all* `inputs : ScenarioInputs` satisfying
preconditions, `accountingInvariantHolds inputs result.state`." That is not present.

### 1.3 IR operational semantics (`ProofForge/IR/Semantics.lean`)

A small executable semantics for the scalar IR subset: `Value`, `State`
(name→value bindings + logs), `runEntrypointWithArgs`. It is the formal anchor that
`Refinement.lean` and `ValueVaultInvariant.lean` both build on. It is an
*interpreter*, not a small-step relation — there is no explicit `step : State → State`
transition relation that a simulation proof would need.

## 2. Lean 4 EVM semantics options: `powdr-labs/evm-semantics` vs `EVMYulLean`

Two Lean 4 formal EVM semantics can serve as the Tier C-proof refinement target.
**Update (2026-07): [`powdr-labs/evm-semantics`](https://github.com/powdr-labs/evm-semantics)
is now the preferred one** — it is toolchain-compatible with ProofForge and relationally
structured, which resolves the Phase 6b blocker that stopped the `EVMYulLean` route.
(This supersedes the earlier note that treated `powdr-labs/evm-semantics` as
unusable for ProofForge's Lean proof lane.)

### `powdr-labs/evm-semantics` (preferred)

- **Language / toolchain:** Lean 4, pinned to **`leanprover/lean4:v4.31.0` — identical to
  ProofForge's pin** (verified against its `lean-toolchain`). This is the decisive fact:
  it removes the Phase 6b toolchain mismatch entirely.
- **Dependency:** requires `mathlib @ v4.31.0` (its `lakefile.toml`). ProofForge has no
  mathlib today, so this is the one real cost — see the isolation note below.
- **Shape:** a relational small-step / big-step semantics — Prop-valued inductive
  relations `Step` / `Eval` — **plus** an executable shadow `stepF`. It "mirrors the
  structure of `NethermindEth/EVMYulLean` but expressed as Prop-valued inductive
  relations rather than executable functions"; portions are ported from EVMYulLean.
- **Why relational fits us:** ProofForge's refinement is an induction over a simulation
  relation (see `ProofForge/Backend/Refinement/CounterUniversal.lean`). A Prop-valued
  `Step` is the natural object to build the relation `R` against and to `induction` over;
  the executable `stepF` covers the Tier C-diff (`native_decide`) side. One dependency
  serves both tiers.
- **Maturity:** ~355 commits, 11 CI conformance suites passing, Apache-2.0, but
  self-described as a **draft, "not for production"**. Pin a specific commit; its `Step`
  relation joins ProofForge's trusted computing base (trust rests on its own conformance
  testing, not the Lean kernel alone).

### `EVMYulLean` (the executable-function sibling, toolchain-blocked)

- [`leonardoalt/EVMYulLean`](https://github.com/leonardoalt/EVMYulLean): a Lean 4 EVM+Yul
  model, conformance-tested against `ethereum/tests` Cancun (22,330 / 22,332).
  Executable-function-first (`EVM.State`, `step`).
- **Blocked for us:** pins `leanprover/lean4:v4.22.0` + `mathlib @ v4.22.0`, incompatible
  with ProofForge's v4.31.0 (the Phase 6b blocker; see
  [phase-6b-integration-blockers.md](phase-6b-integration-blockers.md)). Usable only if it
  later moves to a ≥ v4.31 toolchain.

### Practical notes for either

- **Isolate the mathlib cost:** add `powdr-labs/evm-semantics` (+ mathlib) only to an
  **opt-in lake target** for the EVM-refinement modules, so the core ProofForge build
  stays mathlib-free and fast (same spirit as keeping `EthereumTests` CI-only).
- **Granularity:** these model EVM **bytecode**; ProofForge emits **Yul** (then `solc` →
  bytecode). Confirm whether `powdr-labs/evm-semantics` also exposes a Yul-level relation;
  otherwise either the Yul→bytecode step (`solc`) stays in the trusted boundary, or the
  in-tree `Evm.YulSemantics` covers the Yul level while powdr covers bytecode.

Either way, a conformance-tested Lean 4 EVM semantics is the right artifact for Tier
C-proof on the EVM path; **`powdr-labs/evm-semantics` is the one to adopt, because its
toolchain matches ProofForge's and its relational shape fits the refinement proofs.**

## 3. Proposed Tier C-proof obligation for EVM

The goal is a machine-checked theorem of the shape:

```
theorem ir_refines_evm_bytecode (m : Module) (wellTyped : ...) :
    ∀ (s : IR.Semantics.State) (calls : List TraceCall),
      matchesSpec m calls wellTyped →
        let (s', obsIR) := runTraceIR m s calls
        let (s'', obsEVM) := runTraceEVMBytecode (compile m) (encodeState s) (encodeCalls calls)
        observableEquiv obsIR obsEVM ∧ decodeState s'' ≈ s'
```

Concretely, the pieces are:

1. **IR small-step relation.** Today `IR.Semantics` is an interpreter. A simulation
   proof needs a small-step `step : State → Option State` (or a big-step
   `run : State → Stmt → State`) relation so that each IR step can be matched to one or
   more EVM steps. This is the biggest missing piece on the IR side.

2. **Simulation relation `R : IR.State ↔ EVM.State`** mapping IR name→value bindings
   to EVM storage slots (per `Evm.Plan.ModulePlan` storage layout), IR logs to EVM
   logs, and IR entrypoint calls to EVM call frames.

3. **Per-entrypoint simulation lemma.** For each entrypoint, a proof that one IR step
   is simulated by zero-or-more EVM `step`s, preserving `R` and observable outputs.

4. **Observable equivalence.** `observableEquiv` lifts the per-step simulation to
   whole-trace equality of `ObservableStep`s (the type already defined in
   `Refinement.lean`).

5. **Target semantics.** Either the in-tree `Evm.YulSemantics` (pseudo-Yul, already used
   by `Refinement.lean`) or the external `powdr-labs/evm-semantics` EVM bytecode
   semantics. The latter is strictly stronger (bytecode, not Yul), matches ProofForge's
   Lean toolchain, and should be wired through an opt-in mathlib target.

## 4. Gap analysis: current → full Tier C-proof

| Piece | Current state | Needed for Tier C-proof |
|---|---|---|
| IR operational semantics | Interpreter (`runEntrypointWithArgs`) | Explicit small-step `step` relation + induction principle |
| EVM target semantics | In-tree pseudo-Yul (`Evm.YulSemantics`) | External `powdr-labs/evm-semantics` EVM bytecode `Step` / `Eval` plus executable `stepF` (opt-in lake target with mathlib) |
| Simulation relation `R` | Absent | Define `R : IR.State ↔ EVM.State` over storage layout |
| Per-entrypoint sim lemma | Absent | Prove `R s s' → R (stepIR s ep) (stepEVM* s' (compile ep))` |
| Observable equivalence | `ObservableStep` type exists, equality via `evmCompatible` | Lift per-step sim to whole-trace equality by induction |
| Theorem discharge | `native_decide` on fixed scenarios | `by induction ...` universally quantified |
| Scenario invariants | `ValueVaultInvariant` default-inputs only | Universally quantified over `ScenarioInputs` + preconditions |

**Biggest blockers:**
1. IR semantics has no small-step relation — it's an interpreter. Extracting/reframing
   it as a `step` relation is a prerequisite for any simulation proof.
2. The in-tree `Evm.YulSemantics` is a *pseudo*-Yul semantics (pseudo-keccak, simplified
   memory/storage). It is not conformance-tested against real EVM. A real Tier C-proof
   wants `powdr-labs/evm-semantics`' bytecode `Step` relation and executable `stepF`,
   which means adding an opt-in lake dependency that pulls mathlib.
3. Storage layout bridging: IR flat `State` vs EVM 256-bit storage slots is non-trivial
   and is currently only encoded implicitly in the lowering. The `Evm.Plan.ModulePlan`
   storage plan is the right place to make it explicit (a side-benefit of the Tier B work).

## 5. Phased roadmap

### Phase 6a — Tighten `Evm.Refinement` toward a real simulation (internal, no new dep)

**Status:** Landed (2026-07-07).

**What was delivered:**

- `ProofForge/IR/StepSemantics.lean` (new) defines a generic inductive
  `IRTraceMatches step : MachineState → List Call → Array Obs → Prop` predicate,
  structurally recursive over the call list (two constructors: `nil` for
  the empty trace, `cons` for one atomic `step` call followed by the rest).
  It is parameterized by an atomic per-call step function
  `step : MachineState → Call → Except String (MachineState × Obs)` so it
  stays target-agnostic; `Evm.Refinement.lean` instantiates it with the
  existing IR `runEntrypointObservable`, and
  `Tests/TargetSemanticsInstances.lean` instantiates the same induction
  theorem over the EVM/Yul, Solana sBPF, and Wasm/NEAR target runner states.
- A generic executable runner `runTraceListGen step` mirrors
  `Evm.Refinement.runTraceList` and is proven *sound* against
  `IRTraceMatches` by `theorem runTraceListGen_sound` discharged with
  `induction calls generalizing s` — NOT `native_decide`. This is the first
  universally-quantified trace-runner lemma in the Tier C-proof chain:
  for ALL machine states `s` and ALL call lists, the executable runner
  agrees with the inductive predicate (on `.ok`; `.error` is `True`). A
  completeness lemma and an `iff` bridge are also provided.
- A `Decidable` instance on `IRTraceMatches` computes `runTraceListGen`
  and compares the observable array, letting `native_decide` re-prove the
  fixed-scenario theorems as `IRTraceMatches` instances without changing
  their truth values.
- `Evm.Refinement.lean` adds `counter_ir_trace_matches_inductive` and
  `value_vault_ir_trace_matches_inductive` — the Counter and ValueVault
  observable traces restated as inductive `IRTraceMatches` propositions,
  discharged via the `Decidable` bridge + `native_decide` on the fixed
  scenarios. The existing `counter_ir_observable_trace_ok` and
  `value_vault_ir_observable_trace_ok` `native_decide` theorems are
  preserved as regression smoke.
- `Tests/IRStepSemantics.lean` (new) `#check`s the soundness theorem,
  the inductive bridge theorems, and the preserved `native_decide`
  theorems, plus two sanity-check theorems that the generic runner and the
  inductive predicate agree with the existing `runTrace` on the Counter
  scenario. `just ir-step-semantics-smoke` runs it and is wired into
  `just check` (Lean-only, ~2.5s).
- Track 1.1 now has a total Counter IR fragment in
  `ProofForge/IR/CounterSemantics.lean`: fuel-indexed total `def`s for the
  Counter subset plus per-entrypoint all-state lemmas for `initialize`, `get`,
  and `increment`. `just ir-counter-semantics-smoke` pins the surface.
- `ProofForge/Backend/Refinement/CounterUniversal.lean` adds the first
  Counter C-proof-shaped simulation layer: per-entrypoint simulation lemmas,
  an induction theorem over every Counter call list from related states, and
  an init-prefixed theorem from arbitrary IR states. The target is a deliberately
  tiny `counter-model`, not EVM/Yul bytecode or another chain VM.
- `ProofForge/Backend/Refinement/Core.lean` now gives `TargetSemantics` a
  `supportedFragments` boundary plus `supportedFragment` /
  `requireSupportedFragment`. `Tests/SupportedFragment.lean` pins that the
  `counter-model` accepts canonical Counter and rejects checked/renamed Counter
  modules outside the proved fragment.
- The existing executable EVM/Yul, Solana sBPF, and Wasm/NEAR runners are now
  wired through the shared `TargetSemantics` interface. `just
  target-semantics-instances-smoke` checks those instances and confirms that
  `runTraceListGen_sound` can be specialized to each target machine state.

**Design choice (b) — big-step induction over the call list.** We keep the
existing big-step interpreter `IR.Semantics.runEntrypointWithArgs` as the
atomic step and layer the inductive predicate on top, rather than
reframing the IR semantics as a small-step `step : State → Option State`
relation. This is the minimal change that enables induction over the trace
without refactoring the whole IR interpreter. A small-step relation (the
Phase 6c simulation-prerequisite) is left to Phase 6b+.

- Introduce a small-step `step : IR.Semantics.State → Option IR.Semantics.State`
  relation (or a big-step `evalStmt : State → Stmt → State`) in a new
  `ProofForge/IR/StepSemantics.lean`.
- Reformulate `Refinement.lean`'s `irTraceOk` as an inductive predicate
  `IRTraceMatches : State → List TraceCall → Array ObservableStep → Prop` and prove
  `runTrace` sound against it by induction (not `native_decide`).
- Keep the existing `native_decide` theorems as a regression smoke; layer the inductive
  ones on top.
- Deliverable: first universally-quantified trace-runner lemmas over arbitrary
  machine states, with IR and target-runner instantiations.

### Phase 6b — Integrate `powdr-labs/evm-semantics` as the EVM bytecode semantics

**Status: preferred target selected; opt-in powdr target, wrapper, Counter storage relation,
and native executable Counter refinement lane landed; default build still mathlib-free
(updated 2026-07-08).**
The original `EVMYulLean` route was blocked by a Lean toolchain + mathlib
version mismatch. That blocker is avoided by switching the refinement target to
`powdr-labs/evm-semantics`, which pins Lean `v4.31.0` and mathlib `v4.31.0`.
The seam at `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` now mirrors
powdr's relational `Step`/`Eval` plus executable `stepF` shape. The external
dependency is now pinned behind the opt-in `EvmRefinement` lake target, so
ProofForge's default build still avoids powdr/mathlib imports.

- **Toolchain mismatch (the blocker).** `EVMYulLean` pins
  `leanprover/lean4:v4.22.0` in its `lean-toolchain` and
  `require mathlib from git "https://github.com/leanprover-community/mathlib4.git"@"v4.22.0"`
  in its `lakefile.lean`. ProofForge pins `leanprover/lean4:v4.31.0` and has
  no mathlib dependency. A single lake workspace uses one toolchain;
  mathlib v4.22.0 will not compile under lean v4.31.0. Per the Phase 6b
  constraint, ProofForge is NOT downgraded to v4.22.0 — that would break
  the existing 378-job build.
- **Resolution path.** `powdr-labs/evm-semantics` is now pinned behind the
  opt-in `EvmRefinement` lake target at commit
  `ae13dbc506158f9d0c7e05634636b17e2bccf850`, with mathlib pinned transitively
  at `fabf563a7c95a166b8d7b6efca11c8b4dc9d911f`. The opt-in adapter now exposes
  real powdr-backed `State`, `Step`, `stepF`, and `runBytecode` wrappers. The
  Counter storage relation now maps the IR `count` binding to the low 64 bits
  of the powdr account storage word at ProofForge's EVM layout slot 0, allowing
  high 192-bit padding, and successful
  `runBytecode` executions now lift to powdr's relational `Steps` closure.
  The pinned powdr tree exposes bytecode semantics, not a Yul-level relation,
  so the Yul→bytecode `solc` step remains an explicit trust boundary. The
  selected EVM delivery boundary is now the `native_decide` discharge over
  powdr's conformance-tested executable `stepF`, lifted through the shared trace
  machinery; hand-deriving the concrete bytecode path against powdr `Step` is
  deferred unless a contract-agnostic automation layer exists first.
- **What was landed:**
  - `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` (new) — stub
    adapter with the public surface aligned to `Refinement.ObservableStep`,
    `sorry`-free stub theorems (`step_noop`, `runBytecode_empty`), and a
    module docstring recording the blocker. Compiles with NO external
    dependency (imports only `ProofForge.Backend.Evm.Refinement`).
  - `EvmRefinement/PowdrAdapter.lean` + `lakefile.lean` + `lake-manifest.json`
    — opt-in powdr/mathlib target that imports powdr's `State`, `Step`,
    `StepF`, `BigStep`, and `Equiv` modules, exposes a seam-compatible
    `stepF : State → Except String State` wrapper, and checks the real
    `EvmSemantics.EVM.stepF_sound` surface. It also proves successful
    `runBytecode` executions imply powdr `Steps`.
  - `EvmRefinement/CounterRefinement.lean` — opt-in Counter relation layer that
    proves `count` is EVM scalar slot 0 and relates IR `count` to powdr
    `AccountMap`/`Storage` over the generated EVM packed U64 slot shape:
    `count` occupies the low 64 bits, the high 192 bits are padding/other-packed
    field space, and `count < 2^64`. This corrects both the earlier
    raw-`UInt256.ofNat count` relation and the too-strong canonical whole-word
    equality relation, neither of which matches the compiled runtime's `get` and
    write behavior. **Legacy storage-layout checkpoint:** the prepared-frame,
    safe-trace, and hand-expanded opcode names in the historical detail below live
    under `ProofForge.Backend.Evm.CounterRefinement.LegacyHighPacked`. They target
    the pre-migration high-64-bit layout and do not establish refinement for the
    current low-order runtime. It also prepares runtime-code parameterized Counter call
    frames and proves that preparation preserves the
    storage relation. It now embeds the current CLI-generated Counter runtime
    bytecode witness, proves its size and selector offsets, exposes
    `counterCompiledPowdrConfig`, and adds the opt-in
    `just evm-powdr-counter-runtime` drift gate. The compiled-runtime path also
    exposes `counterCompiledPowdrTargetSemantics` and
    `counterCompiledPowdr_trace_simulates_after_initialize_from_obligations`,
    which specialized the obligation surface to the real Counter runtime
    witness. It also defines `counterBaseEvmState` and native executable smokes
    for `initialize`, `get`, and `initialize; increment; get`; together with the
    explicit TCB statement, those are the selected executable witness boundary
    over powdr's driver. The concrete compiled target's
    `executableTraceOk` now consumes Counter `TraceObligation`s through the
    compiled runtime and proves the initialize-get-increment-get trace with
    `counterCompiledPowdr_executable_trace_ok`. Prepared calls now normalize a
    fresh top-level EVM frame while preserving storage, so stale halted frames or
    zero-gas defaults are not accidental counterexamples. Packed-storage smokes
    use low-bit count `7` with nonzero high padding; `initialize; get` returns
    `0` from that padded slot, and
    `increment; get` reaches `8`. The
    module now exposes a
    powdr-backed Counter trace-step surface and proves successful trace steps
    are backed by powdr `Steps` plus the stated observable projection; the
    compiled-runtime C-diff is green. The relational per-entrypoint obligation
    surface is retained as the theorem-machine shape, but no longer drives
    manual bytecode reduction. It
    also exposes the three per-entrypoint powdr obligations and proves that, if
    they hold, the shared trace induction yields universal Counter trace
    simulation. `initialize` is now the relation-establishing entrypoint:
    `counterPowdr_trace_simulates_after_initialize_from_obligations` proves
    universal `initialize :: calls` traces from arbitrary IR/EVM starting states
    under the same obligations.
    The explicit `count < 2^64` side condition is now the next proof boundary:
    an unbounded IR `u64` Nat increment at `2^64 - 1` will not match the compiled
    EVM runtime unless the supported fragment/input predicate excludes overflow
    or the IR Counter semantics is changed to the same checked/wrapping behavior.
    That boundary is now represented in Lean by `counterTraceSafeFromCount` /
    `counterTraceSafeAfterInitialize`, with native checks for the normal
    initialize-get-increment-get trace and for the unsafe max-u64 increment case.
    The obligation surface now also has a safe variant:
    `LegacyHighPacked.CounterStepSafe`,
    `LegacyHighPacked.CounterPowdrSafeEntrypointObligations`, and
    `counterPowdr_safe_step_simulates_from_obligations` make the bounded
    `increment` precondition explicit at the per-entrypoint EVM proof boundary.
    `counterPowdr_safe_trace_simulates_from_obligations` and
    `LegacyHighPacked.counterPowdr_safe_trace_simulates_after_initialize_from_obligations` lift
    that predicate through the universal trace induction, with a compiled-runtime
    specialization exposed for `counterCompiledPowdrConfig`.
    `LegacyHighPacked.CounterTraceSafeAtState` and
    `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_from_state_safe_obligations`
    expose the boundary as a state/input predicate for the later supported-fragment
    gate. `LegacyHighPacked.CounterPowdrEvmPostconditions` plus
    `LegacyHighPacked.counterPowdrSafeEntrypointObligationsOfPostconditions` historically reduced a
    deeper powdr route to EVM-only storage postconditions for the compiled runtime;
    that route is deferred until generic automation exists.
    `LegacyHighPacked.CounterPowdrPreparedEvmPostconditions` and
    `LegacyHighPacked.counterPowdrEvmPostconditionsOfPrepared` split those postconditions into
    prepared-frame bytecode facts plus the `prepareCounterCall` bridge.
    `LegacyHighPacked.counterInitializeStorageWord` models the historical initialize body as
    high-64-bit count clear plus low-192-bit padding preservation, and
    `LegacyHighPacked.counterPreparedInitializePostconditionOfStorageModel` turns that model into
    the prepared-frame initialize postcondition. `LegacyHighPacked.CounterPowdrPreparedStorageModels`
    now names the remaining prepared-frame storage-model obligations, and the
    compiled `LegacyHighPacked.counterCompiledPowdr_safe_trace_simulates_*_prepared_storage_models`
    theorems connect those obligations directly to the safe universal trace
    theorems. `LegacyHighPacked.counterInitializeStorageValue_of_sstore_stackMemFlow_ok` proves
    the final powdr `SSTORE` helper step writes the initialize model value into
    Counter slot 0 once the dispatcher/body proof establishes the required stack
    shape. `LegacyHighPacked.counterStack_of_initialize_sload_and_or_ok` composes the preceding
    powdr `SLOAD`, `AND`, and `OR` helper steps into the value shape consumed by
    that SSTORE proof. `LegacyHighPacked.counterInitializeBodyWriteWord_eq_storageWord` and
    `LegacyHighPacked.counterInitializeBodyWriteWord_rel_zero` prove the historical initialize
    mask/set-value expression equals the storage model; the specialized
    `counterStack_of_initialize_sload_and_or_storageWord_ok` helper now returns
    that model value after the SLOAD/AND/OR sequence.
    `counterStack_of_initialize_prefix_to_sload_ok` proves the initialize-body
    prefix constructs the exact stack consumed by the SLOAD helper.
    `counterStorageValue_of_initialize_sload_and_or_push_sstore_ok` stitches the
    SLOAD/AND/OR result through the final `PUSH0; SSTORE` and proves the
    resulting state writes the initialize storage model into Counter slot 0.
    `counterStorageValue_of_initialize_body_helpers_ok` composes the complete
    initialize-body helper sequence from the prefix through SSTORE.
    `counterCompiledRuntimeCode_decodes_initialize_first_push0`,
    `counterPreparedInitializeFirstPush0_decoded`, and
    `counterStack_of_stepFE_push0_ok` start the concrete opcode bridge from
    compiled bytecode decode through top-level `stepFE` to the helper stack
    effect. The bridge now also has `stepFE` stack-effect lemmas for `PUSH1`,
    `DUP1`, `SHL`, `SUB`, and `NOT`, plus compiled-runtime decode facts for the
    initialize prefix through the final slot `PUSH0` before `SLOAD`.
    `counterCompiledStateAt`, `counterPreparedInitialize*_decoded`, and
    `counterStack_of_initialize_prefix_stepFE_to_sload_ok` then compose those
    decode and `stepFE` facts into the concrete prefix path consumed by `SLOAD`.
    `counterStack_of_stepFE_stackMemFlow_sload_ok`,
    `counterStack_of_stepFE_compBit_and_ok`,
    `counterStack_of_stepFE_compBit_or_ok`,
    `counterStorageValue_of_stepFE_stackMemFlow_sstore_ok`,
    `counterStack_of_stepFE_stackMemFlow_sstore_ok`, and
    `counterStorageValue_of_initialize_tail_stepFE_ok` extend the same
    top-level bridge through SLOAD/AND/OR/PUSH0/SSTORE and prove the tail writes
    the initialize storage model value. `counterStack_of_initialize_tail_stepFE_ok`
    also fixes the stack tail after SSTORE, preserving the return address and
    selector needed by the final return segment. The trampoline bridge now has
    concrete decode facts plus `counterState_of_initialize_trampoline_stepFE_to_body_ok`
    and `counterState_of_initialize_body_jumpdest_stepFE_to_first_opcode_ok`,
    proving the top-level `stepFE` trampoline lands at the initialize body and
    advances to the first body opcode. The initialize selector dispatcher is now
    pinned through `JUMPI` by `counterCompiledRuntimeCode_decodes_dispatcher_*`
    plus `counterPreparedDispatcher*_decoded`, and
    `counterState_of_dispatcher_first_push0_stepFE_to_calldataload_ok` proves
    the first dispatcher `stepFE` reaches `CALLDATALOAD` with selector offset 0
    on the stack. The bridge now also has generic state lemmas for
    `CALLDATALOAD`, `SHR`, `EQ`, and taken `JUMPI`, concrete initialize
    selector facts, and path theorems through
    `counterState_of_dispatcher_selector_shr_stepFE_to_dup_ok`, proving the
    concrete dispatcher reaches PC 5 (`DUP1`) with the extracted selector on the
    stack. The tail path now reaches the initialize trampoline `JUMPDEST` via
    `counterState_of_dispatcher_initialize_jumpi_stepFE_to_trampoline_ok`, and
    `counterState_of_dispatcher_trampoline_stepFE_to_initialize_first_opcode_ok`
    composes through the trampoline and body `JUMPDEST` to the first initialize
    body opcode. `counterStorageValue_of_initialize_body_stepFE_from_first_opcode_ok`
    then composes that first opcode through SSTORE and proves the body writes
    `counterInitializeStorageWord` relative to the SLOAD-state storage word;
    `counterStack_of_initialize_body_stepFE_from_first_opcode_ok` proves the
    same body path preserves the return-address/selector stack tail.
    `counterCompiledPreparedInitialize_entry_facts` records the prepared
    initialize frame facts needed to instantiate the composed path from a real
    `CounterPreparedCall`. The body final `JUMP` plus
    `JUMPDEST; PUSH0; DUP1; RETURN` segment is now bridged by
    `counterCompiledRuntimeCode_decodes_initialize_body_return_jump`,
    `counterCompiledRuntimeCode_decodes_initialize_return*`, and
    `counterPreparedInitializeReturn*_decoded`, plus
    `counterState_of_stepFE_system_return_empty_ok` and
    `counterState_of_initialize_return_stepFE_to_returned_empty_ok`, proving the
    frame halts with `Returned ByteArray.empty` while preserving Counter
    storage. `counterInitializeObservable_of_returned_empty` maps that result to
    the Counter `initialize` observable `.none`.
    `counterInitializeReturn_preserves_storage_model_stepFE_ok` packages the
    return-path bridge from an already-established initialize storage model to
    the final halted frame plus `.none` observable. `runBytecode_halted_succ`,
    `runBytecode_step_succ`, `runBytecode_stepFE_succ`, `StepFEPath`, and
    `stepFEPath_append`, `runBytecode_of_stepFEPath`, and
    `runBytecode_of_stepFEPath_done` now expose the fuel-driver bridge needed to
    feed either one successful `stepFE` opcode or a reusable composed `stepFE`
    path segment into `counterPowdrPreparedTraceStep`.
    `counterStepFEPath_initialize_return_segment_ok`,
    `counterStepFEPath_initialize_body_and_return_ok`, and
    `counterStepFEPath_initialize_dispatcher_body_and_return_ok` split the
    initialize deep path into named segment facts before converting it to
    `runBytecode`.
    `counterRunBytecode_initialize_return_segment_ok` applies that bridge to
    the final return segment with 5 fuel steps.
    `counterRunBytecode_initialize_body_and_return_ok` composes the body and
    return paths into a 22-fuel bridge from the first body opcode to the halted
    `.none` result, with storage model preservation and the final
    `halt = .Returned` fact carried out of the return segment.
    `counterStack_of_initialize_tail_stepFE_to_sstore_ok` and
    `counterStack_of_initialize_body_stepFE_to_sstore_ok` expose the pre-SSTORE
    stack fact from the composed tail/body path, and
    `counterCompiledStateAt_of_initialize_sstore_stepFE_ok` feeds that fact
    back into the 22-fuel bridge. The body-return-jump `counterCompiledStateAt`
    fact is now derived internally rather than passed as an explicit premise;
    the body opcode families also now have reusable call-stack preservation
    lemmas for `SHL`, `NOT`, `SUB`, `SLOAD`, `AND`, `OR`, and `SSTORE`, so the
    remaining prefix proof can compose those local facts instead of rebuilding
    each opcode branch inside the entrypoint theorem.
    `counterCallStack_of_initialize_tail_stepFE_ok` already composes the
    `SLOAD; AND; OR; PUSH0; SSTORE` tail into a reusable call-stack segment, so
    the remaining body proof only has to connect the first body opcode to the
    SLOAD state and append that tail segment.
    `counterCallStack_of_initialize_prefix_stepFE_to_sload_ok` now supplies
    that first-body-opcode-to-SLOAD call-stack segment, leaving the body
    call-stack proof as a prefix-plus-tail composition.
    `counterRunBytecode_initialize_dispatcher_body_and_return_ok` now prepends
    the initialize selector dispatcher and trampoline through `StepFEPath`,
    yielding a 36-fuel `runBytecode` bridge from PC0 to the halted `.none`
    result. The return-path bridge now carries returned halt and call-stack
    preservation through the 36-step theorem, proving the final frame's
    `callStack` equals the body-return-jump frame's `callStack`.
    `runBytecode_halted`, `runBytecode_extend_halted`,
    `runBytecode_extend_to_fuel`,
    `runBytecode_extend_to_fuel_of_returned_top_level`, and
    `runBytecode_extend_of_stepFEPath_returned_top_level` lift any short fuel
    run, or any packaged `StepFEPath`, to a larger target fuel once the final
    frame is known to be halted. The Counter-specific compiled-fuel bridge is
    now only a wrapper around that adapter-level interface.
    `isHalted_of_returned_top_level` and
    `counterPowdrPreparedTraceStep_initialize_of_run36_returned_top_level_ok`
    reduce the remaining side condition to returned halt plus an empty
    top-level `callStack`; `counterCompiledPreparedInitialize_entry_facts`
    exposes the prepared frame's initial empty `callStack`. The returned-halt
    half is already available from the 36-step bridge, so the remaining prefix
    proof only has to carry the prepared empty `callStack` to the
    body-return-jump frame.
    The safe universal trace layer is green once
    `LegacyHighPacked.CounterCompiledPowdrPreparedStorageModels` is supplied; the scaling
    boundary is now the target-specific discharge of those prepared storage
    models, not the shared trace induction.
  - `docs/phase-6b-integration-blockers.md` (new) — full blocker record.
- **Implementation guardrail (updated 2026-07-08):** stop copying the initialize
  dispatcher/body/return proof shape into `increment`, `get`, or another
  contract. The file-size and proof-shape trend shows this is not converging
  into a thin reusable proof. `PowdrExec` may continue only as a genuinely
  contract-agnostic automation substrate; a patch that adds more
  Counter-specific selector/body/return facts is out of scope for this track.
- **Deliverable (corrected 2026-07-10):** the EVM lane delivers a clean powdr-target
  seam, an opt-in dependency path and wrapper, a canonical low-order Counter storage
  relation, and a fixed Counter IR/bytecode trace backed by `native_decide` over powdr
  `stepF`. `evmCompiledPowdr_fragment_refines_all` remains conditional on
  `CounterCompiledPowdrEntrypointObligations`. The explicit TCB boundary is powdr's executable
  semantics plus Lean's native evaluator, with ProofForge's Yul→bytecode `solc`
  hop also called out. Active proof effort should move to the shared
  theorem-machine shape (`TargetSemantics`, `SupportedFragment`, relation `R`,
  per-entrypoint obligations, `traceSimulation_lift`) for Solana/WASM, or to a
  future generic EVM symbolic-execution tactic before revisiting deep bytecode
  reduction.

### Phase 6c — Bank EVM Counter and stop deep bytecode hand-derivation

- Preserve the Counter relation, prepared-call boundary, safe-input predicate,
  and universal trace-lift theorem route already in `EvmRefinement`.
- Treat the fixed powdr `stepF` trace discharged by `native_decide` as the EVM
  delivery boundary for this milestone. This is machine-checked, but it is not a
  closed universal theorem; its TCB is
  explicit: powdr's conformance-tested executable semantics, Lean's native
  evaluator, and ProofForge's Yul→bytecode `solc` hop.
- Do not extend `CounterRefinement.lean` with new hand-written selector/body/
  return segment proofs. Revisit deep bytecode reduction only after a generic
  symbolic-execution tactic or lemma library can discharge a second contract
  without bespoke per-segment facts.
- Deliverable: a documented, green EVM reference lane plus the reusable theorem
  skeleton that Solana/WASM can copy without inheriting the EVM bytecode proof
  rabbit hole.

### Phase 6d — Future EVM broadening only after generic automation

- ValueVault or a two-slot Counter can serve as a genericity smoke only if it
  reuses the same `TargetSemantics` / obligation / `native_decide` machinery
  with short proofs.
- Extending `R` to storage maps and events remains desirable, but it is not a
  reason to hand-derive ValueVault bytecode paths. If the proof needs fresh
  selector/body/return segment derivation, stop and move the effort back to
  automation or to the self-owned Solana/WASM interpreters.

### Phase 6e — Generalize the simulation framework

- Extract a reusable `SimulationFramework` (parametric in the target semantics) so that
  the same pattern can in principle target Solana (Mollusk/Pinocchio), NEAR (offline-host
  wasm), etc.
- Note: Tier C-proof for non-EVM chains requires a formal target semantics for each,
  which is itself a research project (no `powdr-labs/evm-semantics`-equivalent exists
  for Solana sBPF or NEAR wasm today). This phase is exploratory.

## 6. Non-goals (out of scope for Tier C-proof)

- Full EVM conformance-suite coverage — conformance belongs to the external EVM
  semantics package and its CI baselines, not ProofForge's default build. ProofForge
  only needs the adapter and simulation proofs to be correct.
- All EVM opcodes — only the subset ProofForge's lowering emits.
- All backends at once — EVM is the imported-semantics reference lane, while
  Solana/WASM need self-owned target semantics before full-fragment C-proof can
  land. Their existing executable traces remain Tier C-diff until those
  interpreters and supported-fragment predicates are broadened.
- ZK proving / powdr the zkVM toolkit — `powdr-labs/powdr` (the zkVM accelerator) is a
  separate Rust project and is *not* the EVM semantics dependency. The Lean 4 EVM
  semantics options are `powdr-labs/evm-semantics` (preferred — toolchain-compatible) and
  `leonardoalt/EVMYulLean` (toolchain-blocked); see §2.
- Removing `native_decide` from the imported EVM lane by hand — the selected EVM
  boundary trusts powdr `stepF` through Lean's native evaluator. A future
  contract-agnostic symbolic-execution tactic may reduce that TCB, but
  per-contract opcode derivations are out of scope.

## 7. Recommendation

Tier C-proof is feasible, but the EVM experience sets a sharper boundary:
importing a full external VM semantics is enough to establish a reference lane,
but hand-removing the executable `native_decide` discharge from real EVM
bytecode does not scale without automation. The practical next deliverable is
the reusable theorem machine: `SupportedFragment`, `TargetSemantics`, relation
`R`, per-entrypoint obligations, and `traceSimulation_lift`, applied to
self-owned Solana/WASM interpreters that are designed to reduce cleanly.

For EVM, bank the green powdr `stepF`/`native_decide` lane with an explicit TCB
statement. Future EVM deep bytecode reduction should start with a generic
symbolic-execution tactic or a second-contract genericity proof; it should not
resume as more Counter-specific segment facts.
