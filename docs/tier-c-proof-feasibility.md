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

## 2. `powdr-labs/evm-semantics` overview

The GitHub org `powdr-labs` has a repository literally named `evm-semantics`, but the
substantive Lean 4 EVM+Yul formal model lives in the Nethermind-maintained
[`leonardoalt/EVMYulLean`](https://github.com/leonardoalt/EVMYulLean) (referenced by
the powdr ecosystem and the Nethermind blog post "A Trustworthy Formal Model of EVM
and Yul in Lean for Cancun"):

- **Language:** Lean 4.
- **Granularity:** EVM bytecode opcode-level (`EVM.State`, `step`) **and** Yul-level
  (`Yul` semantics reusing underlying EVM primops where applicable).
- **Conformance:** tested against the official `ethereum/tests` Cancun suite; passes
  22,330 / 22,332 (99.99%) execution tests. The two failures have unclear/non-deterministic
  expected behavior.
- **Relational story:** the model is a *standalone* semantics of EVM/Yul, not a
  refinement framework. It defines `EVM.State` and a `step` function; relating an
  arbitrary source semantics to it is the user's proof obligation.
- **Integration shape:** a Lean 4 `lake` dependency. It would be added as a
  `require` entry in `lakefile.lean` (or a transitive `lake-manifest.json` entry),
  with its `EthereumTests` submodule pulled for conformance checks. It is *not*
  vendored in ProofForge today.

This is the right artifact for Tier C-proof on the EVM path: it gives a trustworthy,
conformance-tested EVM+Yul semantics to relate against.

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
   by `Refinement.lean`) or the external `EVMYulLean` EVM bytecode semantics. The
   latter is strictly stronger (bytecode, not Yul) but requires the lake dependency.

## 4. Gap analysis: current → full Tier C-proof

| Piece | Current state | Needed for Tier C-proof |
|---|---|---|
| IR operational semantics | Interpreter (`runEntrypointWithArgs`) | Explicit small-step `step` relation + induction principle |
| EVM target semantics | In-tree pseudo-Yul (`Evm.YulSemantics`) | External `EVMYulLean` EVM bytecode `step` (lake dep) |
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
   wants `EVMYulLean`'s bytecode semantics, which means adding a lake dependency.
3. Storage layout bridging: IR flat `State` vs EVM 256-bit storage slots is non-trivial
   and is currently only encoded implicitly in the lowering. The `Evm.Plan.ModulePlan`
   storage plan is the right place to make it explicit (a side-benefit of the Tier B work).

## 5. Phased roadmap

### Phase 6a — Tighten `Evm.Refinement` toward a real simulation (internal, no new dep)

**Status:** Landed (2026-07-07).

**What was delivered:**

- `ProofForge/IR/StepSemantics.lean` (new) defines a generic inductive
  `IRTraceMatches step : State → List Call → Array Obs → Prop` predicate,
  structurally recursive over the call list (two constructors: `nil` for
  the empty trace, `cons` for one atomic `step` call followed by the rest).
  It is parameterized by an atomic per-call step function
  `step : State → Call → Except String (State × Obs)` so it stays
  EVM-agnostic; `Evm.Refinement.lean` instantiates it with the existing
  `runEntrypointObservable` to recover the IR trace semantics.
- A generic executable runner `runTraceListGen step` mirrors
  `Evm.Refinement.runTraceList` and is proven *sound* against
  `IRTraceMatches` by `theorem runTraceListGen_sound` discharged with
  `induction calls generalizing s` — NOT `native_decide`. This is the first
  universally-quantified IR-side trace lemma in the Tier C-proof chain:
  for ALL states `s` and ALL call lists, the executable runner agrees with
  the inductive predicate (on `.ok`; `.error` is `True`). A completeness
  lemma and an `iff` bridge are also provided.
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
- Deliverable: first universally-quantified IR-side trace lemmas.

### Phase 6b — Integrate `EVMYulLean` EVM bytecode semantics as a lake dependency

**Status: blocked — seam only (2026-07-07).** The integration was
investigated and found blocked by a Lean toolchain + mathlib version
mismatch; the `require` entry was NOT added to `lakefile.lean` (so `lake
build` stays green), and a stub adapter was left as the seam. The full
blocker record, the exact `require` syntax that would be used, and the
resolution path are in [`docs/phase-6b-integration-blockers.md`](phase-6b-integration-blockers.md).

- **Toolchain mismatch (the blocker).** `EVMYulLean` pins
  `leanprover/lean4:v4.22.0` in its `lean-toolchain` and
  `require mathlib from git "https://github.com/leanprover-community/mathlib4.git"@"v4.22.0"`
  in its `lakefile.lean`. ProofForge pins `leanprover/lean4:v4.31.0` and has
  no mathlib dependency. A single lake workspace uses one toolchain;
  mathlib v4.22.0 will not compile under lean v4.31.0. Per the Phase 6b
  constraint, ProofForge is NOT downgraded to v4.22.0 — that would break
  the existing 378-job build.
- **Resolution path.** Wait for `EVMYulLean` to update its toolchain pin to
  a Lean version compatible with ProofForge's (≥ v4.31.0) and cut a
  matching mathlib tag; then add the pinned `require` entry and run
  `lake update` in an environment with network access. The seam at
  `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` is ready to absorb
  the real `EvmYul.EVM.State` / `EVM.Semantics.step` the moment the
  toolchains align — its public surface (`State`, `step`, `runBytecode`,
  alignment with `Refinement.ObservableStep`) is fixed by the stub, and
  no `Refinement.lean` theorem depends on the stub body.
- **What was landed (the seam):**
  - `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` (new) — stub
    adapter with the public surface aligned to `Refinement.ObservableStep`,
    `sorry`-free stub theorems (`step_noop`, `runBytecode_empty`), and a
    module docstring recording the blocker. Compiles with NO external
    dependency (imports only `ProofForge.Backend.Evm.Refinement`).
  - `docs/phase-6b-integration-blockers.md` (new) — full blocker record.
- **What was NOT done (deferred to when the blocker clears):**
  - Add `leonardoalt/EVMYulLean` as a `require` in `lakefile.lean`.
  - Pull its `EthereumTests` submodule for conformance (CI-only; not in
    the default build).
  - Provide the real `EVM.State` / `step` / `runBytecode` driver (the stub
    is in place; only the bodies need replacing).
  - Wire the adapter into `Refinement.lean`'s theorems (that is Phase 6c).
  - Add a `Tests/EvmBytecodeSemantics.lean` smoke + `just
    evm-bytecode-semantics-smoke` recipe (per the task, the smoke is
    added only if integration succeeded).
- **Deliverable (revised):** a clean seam + documented blocker (not a
  conformance-tested EVM bytecode semantics callable from Lean proofs
  yet — that remains the goal once the toolchains align).

### Phase 6c — Prove IR → bytecode refinement for Counter

- Define the simulation relation `R : IR.State ↔ EVM.State` for the Counter module
  (single U64 scalar → one storage slot).
- Prove `R`-simulation for `initialize`, `increment`, `get` individually.
- Lift to the trace theorem `counter_ir_refines_evm_bytecode` by induction over the
  call list, reusing `ObservableStep.evmCompatible`.
- Deliverable: first end-to-end machine-checked refinement for a real example.

### Phase 6d — Extend to ValueVault (storage map + events)

- Extend `R` to map IR map state to EVM storage slot prefixes (using
  `Evm.Plan.ModulePlan` storage layout).
- Prove refinement for all seven ValueVault entrypoints, including event emission
  (`ObservableEventLog` equivalence).
- Prove `value_vault_accounting_invariant` universally quantified over
  `ScenarioInputs` (the real invariant theorem that the current
  `ValueVaultInvariant.lean` only checks for default inputs).
- Deliverable: a universally-quantified contract invariant carried from IR to bytecode.

### Phase 6e — Generalize the simulation framework

- Extract a reusable `SimulationFramework` (parametric in the target semantics) so that
  the same pattern can in principle target Solana (Mollusk/Pinocchio), NEAR (offline-host
  wasm), etc.
- Note: Tier C-proof for non-EVM chains requires a formal target semantics for each,
  which is itself a research project (no `EVMYulLean`-equivalent exists for Solana sBPF
  or NEAR wasm today). This phase is exploratory.

## 6. Non-goals (out of scope for Tier C-proof)

- Full `ethereum/tests` coverage (22k+ tests) — conformance is `EVMYulLean`'s job, not
  ProofForge's. ProofForge only needs the adapter to be correct.
- All EVM opcodes — only the subset ProofForge's lowering emits.
- All backends — Tier C-proof starts with EVM. Solana/NEAR/Psy lack a formal target
  semantics; they remain in Tier C-diff (Quint MBT) until such semantics exist.
- ZK proving / powdr the zkVM toolkit — `powdr-labs/powdr` is a separate Rust project
  about zkVM acceleration; it is *not* the EVM semantics dependency. The Lean 4 model
  is `leonardoalt/EVMYulLean`.
- Replacing the existing `native_decide` smoke — it stays as a fast regression gate;
  the inductive proofs layer on top.

## 7. Recommendation

Tier C-proof is feasible but is a multi-phase research effort, not a single sprint.
The realistic first deliverable is **Phase 6a** (tighten `Evm.Refinement` to an
inductive, universally-quantified IR-side trace lemma), because it needs no new
dependency and directly strengthens what already exists. **Phase 6b** (the `EVMYulLean`
dependency) is the inflection point: it converts the target side from a pseudo-Yul
mock into a conformance-tested EVM bytecode semantics, after which **6c/6d** become
tractable simulation proofs.

Until 6a-6b land, Tier C-proof remains aspirational and the operative verification tier
is **Tier C-diff** (Quint MBT differential replay), which is already being extended to
NEAR and is the pragmatic verification frontier.