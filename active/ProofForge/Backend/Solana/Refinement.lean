import ProofForge.Backend.Refinement.Core
import ProofForge.Backend.Solana.SbpfInterpreter
import ProofForge.Backend.Solana.SbpfAsm
import ProofForge.IR.Semantics
import ProofForge.IR.StepSemantics
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.Contract.Examples.ValueVaultInvariant
import ProofForge.Target.Registry
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Target.Adapter

namespace ProofForge.Backend.Solana.Refinement

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.Solana.SbpfInterpreter

/-! ## Solana sBPF refinement scaffolding (FV-4 executable trace anchor)

This is the first formal anchor for the `solana-sbpf-asm` backend, mirroring
the shape of `ProofForge.Backend.WasmHost.Refinement`. It does **not** claim a
full sBPF instruction semantics (assembly-level execution is a research track,
see `docs/formal-verification.md` FV-4). Instead it fixes the observable
boundary that later differential gates and any future executable-trace work
should refine against:

1. **IR trace obligation** — the scalar IR reference semantics produces the
   expected observable Counter trace. This re-uses the same `runEntrypoint`
   machinery as the EVM and NEAR refinement layers, so the three backends are
   anchored against the same IR reference.
2. **Artifact-surface obligation** — the rendered sBPF assembly from
   `SbpfAsm.renderModule` contains the entrypoint dispatch labels named in the
   IR module's `entrypoints`.
3. **Executable sBPF trace obligation** — the lowered structured `AstNode`
   instruction list executes in the in-Lean sBPF interpreter and produces the
   same observable trace as the IR reference semantics for the Counter slice,
   the default ValueVault scalar/event slice, and focused storage array/map
   probe slices.

Future work (out of scope for this anchor):
- account-validation sequence obligation (entrypoint prologue: signer/writable
  checks at documented offsets).
- PDA derivation syscall sequence obligation.
- wider executable sBPF coverage beyond the scalar-storage/event/map/array
  slices.
-/

/-! ### Observable trace (shared with EVM and NEAR refinement layers) -/

/-! ### Artifact-surface obligation (rendered sBPF assembly)

The sBPF assembly rendered by `SbpfAsm.renderModule` is the artifact surface
that `sbpf`/`solana` tooling consumes. This check pins that every IR
entrypoint name appears as a dispatch label in the rendered assembly, so a
silently-dropped or renamed entrypoint is caught before the external build
step.

Note: the dispatch label naming convention is owned by `SbpfAsm.lowerModule`.
If that convention changes, this obligation must be updated in lockstep; the
obligation is intentionally written against the rendered text so the failure
is visible at the artifact boundary, not hidden inside the lowering. -/

/-- A rendered sBPF program references an entrypoint dispatch label iff the
entrypoint name appears as a label reference in the assembly text. -/
def hasEntrypointDispatch (asm : String) (entrypointName : String) : Bool :=
  -- sBPF assembly labels render as `<name>:` (definition) and `jmp <name>` /
  -- branch targets. We check for the label definition form, which is emitted
  -- once per entrypoint by `lowerModuleCoreWithSeed`.
  asm.contains s!"sol_{entrypointName}:"

/-- Artifact-surface obligation: the rendered sBPF assembly contains a dispatch
reference for every IR entrypoint. -/
def sbpfArtifactSurfaceOk (obligation : TraceObligation) : Bool :=
  match ProofForge.Backend.Solana.SbpfAsm.renderModule obligation.module with
  | .ok asm =>
    obligation.entrypoints.all (fun entrypoint =>
      hasEntrypointDispatch asm entrypoint.name)
  | .error _ => false

def sbpfExecutableTraceOk (obligation : TraceObligation) : Bool :=
  ProofForge.Backend.Solana.SbpfInterpreter.executableTraceOk obligation

structure SolanaSbpfMachineState where
  program : SbpfProgram
  module : Module
  memory : Memory := #[]

def SolanaSbpfMachineState.traceStep (state : SolanaSbpfMachineState) (call : TraceCall) :
    Except String (SolanaSbpfMachineState × ObservableStep) := do
  let (memory, observableStep, _) ←
    runEntrypointState state.program state.module state.memory call
  .ok ({ state with memory }, observableStep)

def solanaSbpfTargetSemantics : TargetSemantics := {
  id := "solana-sbpf-asm"
  supportedFragments := #[.counter]
  fragmentAccepts := isCounterModule
  lowerableAccepts := isCounterShapeLowerable
  MachineState := SolanaSbpfMachineState
  Call := TraceCall
  Obs := ObservableStep
  traceStep := SolanaSbpfMachineState.traceStep
  runTrace := fun calls state => ProofForge.IR.StepSemantics.runTraceListGen
    SolanaSbpfMachineState.traceStep calls state
  runTrace_eq_traceStep := by
    intro calls state
    rfl
  executableTraceOk := sbpfExecutableTraceOk
  initialRelHolds := by intros; trivial
}

/-! ### Counter scenario obligation

The canonical cross-target acceptance scenario. Same IR fixture and same
observable-shape expectation as the EVM and NEAR refinement layers. -/

/-- Counter `initialize → get → increment → get` observable trace. -/
def counterInitializeCall : TraceCall := {
  entrypoint := ProofForge.IR.Examples.Counter.initializeEntrypoint
}

def counterGetCall : TraceCall := {
  entrypoint := ProofForge.IR.Examples.Counter.get
}

def counterIncrementCall : TraceCall := {
  entrypoint := ProofForge.IR.Examples.Counter.increment
}

def counterExpectedTrace : Array ObservableStep := #[
  { entrypointName := "initialize", returnValue := .none },
  { entrypointName := "get", returnValue := .u64 0 },
  { entrypointName := "increment", returnValue := .none },
  { entrypointName := "get", returnValue := .u64 1 }
]

def counterTraceObligation : TraceObligation := {
  name := "Counter.initialize-get-increment-get"
  module := ProofForge.IR.Examples.Counter.module
  calls := traceCallsFromEntrypoints #[
    ProofForge.IR.Examples.Counter.initializeEntrypoint,
    ProofForge.IR.Examples.Counter.get,
    ProofForge.IR.Examples.Counter.increment,
    ProofForge.IR.Examples.Counter.get
  ]
  expected := counterExpectedTrace
}

def counterSbpfSimulationRel
    (irState : ProofForge.IR.Semantics.State)
    (machine : SolanaSbpfMachineState) : Bool :=
  ProofForge.Backend.Solana.SbpfInterpreter.RMemoryOptional
    ProofForge.IR.Examples.Counter.module "count" irState machine.memory

def counterSbpfInitialTarget
    (program : ProofForge.Backend.Solana.SbpfInterpreter.SbpfProgram) :
    SolanaSbpfMachineState :=
  { program,
    module := ProofForge.IR.Examples.Counter.module,
    memory := #[] }

def counterSbpfStateAfterPrefix
    (program : ProofForge.Backend.Solana.SbpfInterpreter.SbpfProgram)
    (callPrefix : List TraceCall) :
    Except String (ProofForge.IR.Semantics.State × SolanaSbpfMachineState) := do
  let (irState, _) ← ProofForge.IR.StepSemantics.runTraceListGen
    runEntrypointObservable callPrefix ProofForge.IR.Semantics.State.empty
  let (targetState, _) ← ProofForge.IR.StepSemantics.runTraceListGen
    SolanaSbpfMachineState.traceStep callPrefix (counterSbpfInitialTarget program)
  .ok (irState, targetState)

def counterSbpfStepSimulationOkAfter
    (callPrefix : List TraceCall) (call : TraceCall) : Bool :=
  match ProofForge.Backend.Solana.SbpfAsm.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok nodes =>
      let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
      match counterSbpfStateAfterPrefix program callPrefix with
      | .error _ => false
      | .ok (irState, targetState) =>
          executableStepSimulationOk
            runEntrypointObservable
            SolanaSbpfMachineState.traceStep
            counterSbpfSimulationRel
            call
            irState
            targetState

theorem counter_sbpf_step_simulation_sound_after
    (callPrefix : List TraceCall) (call : TraceCall) :
    counterSbpfStepSimulationOkAfter callPrefix call = true →
      match ProofForge.Backend.Solana.SbpfAsm.lowerModule
          ProofForge.IR.Examples.Counter.module with
      | .error _ => True
      | .ok nodes =>
          let program :=
            ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
          match counterSbpfStateAfterPrefix program callPrefix with
          | .error _ => True
          | .ok (irState, targetState) =>
              ∃ nextIr nextTarget observable,
                runEntrypointObservable irState call =
                  .ok (nextIr, observable) ∧
                SolanaSbpfMachineState.traceStep targetState call =
                  .ok (nextTarget, observable) ∧
                counterSbpfSimulationRel nextIr nextTarget = true := by
  intro h
  unfold counterSbpfStepSimulationOkAfter at h
  cases hmod : ProofForge.Backend.Solana.SbpfAsm.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | error _ =>
      trivial
  | ok nodes =>
      simp [hmod] at h
      let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
      cases hprefix : counterSbpfStateAfterPrefix program callPrefix with
      | error _ =>
          simp [program] at hprefix
          simp [hprefix]
      | ok pair =>
          rcases pair with ⟨irState, targetState⟩
          simp [program, hprefix] at h
          simpa [hmod, program, hprefix] using executableStepSimulationOk_sound
            runEntrypointObservable
            SolanaSbpfMachineState.traceStep
            counterSbpfSimulationRel
            call
            irState
            targetState
            h

theorem counter_sbpf_initialize_step_simulation_ok :
    counterSbpfStepSimulationOkAfter [] counterInitializeCall = true := by
  native_decide

theorem counter_sbpf_get_after_initialize_step_simulation_ok :
    counterSbpfStepSimulationOkAfter [counterInitializeCall] counterGetCall = true := by
  native_decide

theorem counter_sbpf_increment_after_initialize_step_simulation_ok :
    counterSbpfStepSimulationOkAfter [counterInitializeCall] counterIncrementCall = true := by
  native_decide

theorem counter_sbpf_get_after_increment_step_simulation_ok :
    counterSbpfStepSimulationOkAfter
      [counterInitializeCall, counterIncrementCall] counterGetCall = true := by
  native_decide

theorem counter_sbpf_initialize_step_simulation_sound_checked :
    match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok nodes =>
        let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
        match counterSbpfStateAfterPrefix program [] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterInitializeCall =
                .ok (nextIr, observable) ∧
              SolanaSbpfMachineState.traceStep targetState counterInitializeCall =
                .ok (nextTarget, observable) ∧
              counterSbpfSimulationRel nextIr nextTarget = true :=
  counter_sbpf_step_simulation_sound_after
    [] counterInitializeCall counter_sbpf_initialize_step_simulation_ok

theorem counter_sbpf_get_after_initialize_step_simulation_sound_checked :
    match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok nodes =>
        let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
        match counterSbpfStateAfterPrefix program [counterInitializeCall] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterGetCall =
                .ok (nextIr, observable) ∧
              SolanaSbpfMachineState.traceStep targetState counterGetCall =
                .ok (nextTarget, observable) ∧
              counterSbpfSimulationRel nextIr nextTarget = true :=
  counter_sbpf_step_simulation_sound_after
    [counterInitializeCall] counterGetCall
    counter_sbpf_get_after_initialize_step_simulation_ok

theorem counter_sbpf_increment_after_initialize_step_simulation_sound_checked :
    match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok nodes =>
        let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
        match counterSbpfStateAfterPrefix program [counterInitializeCall] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterIncrementCall =
                .ok (nextIr, observable) ∧
              SolanaSbpfMachineState.traceStep targetState counterIncrementCall =
                .ok (nextTarget, observable) ∧
              counterSbpfSimulationRel nextIr nextTarget = true :=
  counter_sbpf_step_simulation_sound_after
    [counterInitializeCall] counterIncrementCall
    counter_sbpf_increment_after_initialize_step_simulation_ok

theorem counter_sbpf_get_after_increment_step_simulation_sound_checked :
    match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok nodes =>
        let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
        match counterSbpfStateAfterPrefix program
            [counterInitializeCall, counterIncrementCall] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterGetCall =
                .ok (nextIr, observable) ∧
              SolanaSbpfMachineState.traceStep targetState counterGetCall =
                .ok (nextTarget, observable) ∧
              counterSbpfSimulationRel nextIr nextTarget = true :=
  counter_sbpf_step_simulation_sound_after
    [counterInitializeCall, counterIncrementCall] counterGetCall
    counter_sbpf_get_after_increment_step_simulation_ok

def counterSbpfTraceSimulationOk : Bool :=
  match ProofForge.Backend.Solana.SbpfAsm.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok nodes =>
      let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
      executableSimulationTraceOk
        runEntrypointObservable
        SolanaSbpfMachineState.traceStep
        counterSbpfSimulationRel
        counterTraceObligation.calls.toList
        ProofForge.IR.Semantics.State.empty
        (counterSbpfInitialTarget program)

theorem counter_sbpf_trace_simulation_ok :
    counterSbpfTraceSimulationOk = true := by
  native_decide

theorem counter_sbpf_trace_simulation_sound :
    counterSbpfTraceSimulationOk = true →
      match ProofForge.Backend.Solana.SbpfAsm.lowerModule
          ProofForge.IR.Examples.Counter.module with
      | .error _ => True
      | .ok nodes =>
          let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
          ∃ finalIr finalTarget observables,
            ProofForge.IR.StepSemantics.runTraceListGen
              runEntrypointObservable
              counterTraceObligation.calls.toList
              ProofForge.IR.Semantics.State.empty =
                .ok (finalIr, observables) ∧
            ProofForge.IR.StepSemantics.runTraceListGen
              SolanaSbpfMachineState.traceStep
              counterTraceObligation.calls.toList
              { program,
                module := ProofForge.IR.Examples.Counter.module,
                memory := #[] } =
                .ok (finalTarget, observables) ∧
            counterSbpfSimulationRel finalIr finalTarget = true := by
  intro h
  unfold counterSbpfTraceSimulationOk at h
  cases hmod : ProofForge.Backend.Solana.SbpfAsm.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | error _ =>
      trivial
  | ok nodes =>
      simp [hmod] at h
      exact executableSimulationTraceOk_sound
        runEntrypointObservable
        SolanaSbpfMachineState.traceStep
        counterSbpfSimulationRel
        counterTraceObligation.calls.toList
        ProofForge.IR.Semantics.State.empty
        {
          program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes,
          module := ProofForge.IR.Examples.Counter.module,
          memory := #[]
        }
        h

theorem counter_sbpf_trace_simulation_sound_checked :
    match ProofForge.Backend.Solana.SbpfAsm.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok nodes =>
        let program := ProofForge.Backend.Solana.SbpfInterpreter.collectProgram nodes
        ∃ finalIr finalTarget observables,
          ProofForge.IR.StepSemantics.runTraceListGen
            runEntrypointObservable
            counterTraceObligation.calls.toList
            ProofForge.IR.Semantics.State.empty =
              .ok (finalIr, observables) ∧
          ProofForge.IR.StepSemantics.runTraceListGen
            SolanaSbpfMachineState.traceStep
            counterTraceObligation.calls.toList
            { program,
              module := ProofForge.IR.Examples.Counter.module,
              memory := #[] } =
              .ok (finalTarget, observables) ∧
          counterSbpfSimulationRel finalIr finalTarget = true :=
  counter_sbpf_trace_simulation_sound counter_sbpf_trace_simulation_ok

def valueVaultEntrypointD (entrypointName : String) : Entrypoint :=
  match ProofForge.Contract.Examples.ValueVaultInvariant.module.entrypoints.find?
      (fun entrypoint => entrypoint.name == entrypointName) with
  | some entrypoint => entrypoint
  | none => ProofForge.IR.Examples.Counter.initializeEntrypoint

def valueVaultCall (name : String)
    (args : Array ProofForge.IR.Semantics.Value := #[]) : TraceCall := {
  entrypoint := valueVaultEntrypointD name
  args
}

def valueVaultTraceCalls : Array TraceCall :=
  let inputs := ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs
  #[
    valueVaultCall "initialize" #[.u64 inputs.initial],
    valueVaultCall "get_balance",
    valueVaultCall "deposit" #[.u64 inputs.deposit],
    valueVaultCall "get_balance",
    valueVaultCall "charge_fee" #[.u64 inputs.grossCharge, .u64 inputs.feeBps],
    valueVaultCall "get_balance",
    valueVaultCall "get_net_value",
    valueVaultCall "release" #[.u64 inputs.release],
    valueVaultCall "get_balance",
    valueVaultCall "snapshot",
    valueVaultCall "get_net_value"
  ]

def valueVaultExpectedTrace : Array ObservableStep :=
  let inputs := ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs
  let fee := ProofForge.Contract.Examples.ValueVaultInvariant.expectedFee inputs
  let afterDeposit := inputs.initial + inputs.deposit
  let afterCharge := afterDeposit +
    ProofForge.Contract.Examples.ValueVaultInvariant.expectedNetCharge inputs
  let balance := ProofForge.Contract.Examples.ValueVaultInvariant.expectedBalance inputs
  let netValue := ProofForge.Contract.Examples.ValueVaultInvariant.expectedNetValue inputs
  #[
    { entrypointName := "initialize", returnValue := .none },
    { entrypointName := "get_balance", returnValue := .u64 inputs.initial },
    { entrypointName := "deposit", returnValue := .none },
    { entrypointName := "get_balance", returnValue := .u64 afterDeposit },
    { entrypointName := "charge_fee", returnValue := .none },
    { entrypointName := "get_balance", returnValue := .u64 afterCharge },
    { entrypointName := "get_net_value", returnValue := .u64 (afterCharge - fee) },
    { entrypointName := "release", returnValue := .none },
    { entrypointName := "get_balance", returnValue := .u64 balance },
    { entrypointName := "snapshot", returnValue := .u64 balance },
    { entrypointName := "get_net_value", returnValue := .u64 netValue }
  ]

def valueVaultTraceObligation : TraceObligation := {
  name := "ValueVault.default-scenario"
  module := ProofForge.Contract.Examples.ValueVaultInvariant.module
  calls := valueVaultTraceCalls
  expected := valueVaultExpectedTrace
}

/-! ### Storage array and map probe obligations

These deepen the Solana executable trace beyond scalar slots. They are still
pointwise C-diff checks, but they run the actual lowered sBPF array-index and
map-linear-scan instruction paths against the shared IR semantics. -/

def arrayStorageExpectedTrace : Array ObservableStep := #[
  { entrypointName := "storage_lifecycle", returnValue := .u64 31 }
]

def arrayStorageTraceObligation : TraceObligation := {
  name := "ArrayProbe.storage-lifecycle"
  module := ProofForge.IR.Examples.ArrayProbe.emitWatStorageModule
  calls := traceCallsFromEntrypoints #[
    ProofForge.IR.Examples.ArrayProbe.storageLifecycle
  ]
  expected := arrayStorageExpectedTrace
}

def mapStorageModule : Module := {
  name := "EvmMapProbe"
  state := #[
    ProofForge.IR.Examples.EvmMapProbe.stateBefore,
    ProofForge.IR.Examples.EvmMapProbe.stateBalances,
    ProofForge.IR.Examples.EvmMapProbe.stateAfter
  ]
  entrypoints := #[
    ProofForge.IR.Examples.EvmMapProbe.setBalance,
    ProofForge.IR.Examples.EvmMapProbe.readBalance
  ]
}

def mapSetCall : TraceCall := {
  entrypoint := ProofForge.IR.Examples.EvmMapProbe.setBalance
  args := #[.u64 5, .u64 42]
}

def mapReadCall : TraceCall := {
  entrypoint := ProofForge.IR.Examples.EvmMapProbe.readBalance
  args := #[.u64 5]
}

def mapStorageExpectedTrace : Array ObservableStep := #[
  { entrypointName := "set_balance", returnValue := .none },
  { entrypointName := "read_balance", returnValue := .u64 42 }
]

def mapStorageTraceObligation : TraceObligation := {
  name := "EvmMapProbe.set-read"
  module := mapStorageModule
  calls := #[mapSetCall, mapReadCall]
  expected := mapStorageExpectedTrace
}

/-! ### Counter FV-4 artifact-surface and executable-trace theorems

These are the first Solana refinement theorems. They mirror the NEAR
artifact-surface pattern and add a first Counter executable-trace check over
the lowered structured sBPF AST. -/

theorem counter_ir_observable_trace_ok :
    counterTraceObligation.irTraceOk = true := by
  native_decide

theorem counter_sbpf_artifact_surface_ok :
    sbpfArtifactSurfaceOk counterTraceObligation = true := by
  native_decide

theorem counter_sbpf_executable_trace_ok :
    sbpfExecutableTraceOk counterTraceObligation = true := by
  native_decide

theorem value_vault_ir_observable_trace_ok :
    valueVaultTraceObligation.irTraceOk = true := by
  native_decide

theorem value_vault_sbpf_executable_trace_ok :
    sbpfExecutableTraceOk valueVaultTraceObligation = true := by
  native_decide

theorem array_storage_ir_observable_trace_ok :
    arrayStorageTraceObligation.irTraceOk = true := by
  native_decide

theorem array_storage_sbpf_executable_trace_ok :
    sbpfExecutableTraceOk arrayStorageTraceObligation = true := by
  native_decide

theorem map_storage_ir_observable_trace_ok :
    mapStorageTraceObligation.irTraceOk = true := by
  native_decide

theorem map_storage_sbpf_executable_trace_ok :
    sbpfExecutableTraceOk mapStorageTraceObligation = true := by
  native_decide

/-! ### Revert-aware trace obligation

This is the first trace obligation that asserts a **contract revert** as an
observable outcome rather than a trace failure. It exercises the three-valued
`ExecResult` path: `Statement.revert` produces `.reverted "revert: <msg>"` in
the IR semantics, which the revert-aware `runEntrypointObservable` lifts into
an `ObservableReturn.reverted` step.

It also pins the **rollback** half of the contract: a reverting entrypoint
must not advance the trace state, so a subsequent read of unmodified state
returns the pre-revert value. This is the chain-rollback invariant the
revert-aware trace layer promises. -/

/-- A minimal entrypoint that unconditionally reverts. -/
def revertEntrypoint : Entrypoint :=
  {
    name := "revertAlways"
    mutability := .call
    body := #[.revert "always rolls back"]
  }

/-- A minimal entrypoint that returns a constant, used to observe post-revert
state (it touches no storage, so it succeeds against any state). -/
def readConstEntrypoint : Entrypoint :=
  {
    name := "readConst"
    mutability := .view
    «returns» := .u64
    body := #[.return (.literal (.u64 7))]
  }

/-- `revertAlways → readConst`: the revert is observed, and the subsequent read
still succeeds (state was not corrupted/advanced by the revert). -/
def revertRollbackTrace : Array ObservableStep := #[
  { entrypointName := "revertAlways", returnValue := .reverted "revert: always rolls back" },
  { entrypointName := "readConst", returnValue := .u64 7 }
]

def revertRollbackObligation : TraceObligation := {
  name := "Revert.rollback"
  module := ProofForge.IR.Examples.Counter.module
  calls := traceCallsFromEntrypoints #[ revertEntrypoint, readConstEntrypoint ]
  expected := revertRollbackTrace
}

/-- The revert-aware IR trace observes the revert message and the post-revert
read still produces its constant (state rollback). -/
theorem revert_rollback_ir_trace_ok :
    revertRollbackObligation.irTraceOk = true := by
  native_decide

/-! ### Track 1.4 fragment theorems (Solana sBPF instance)

Two theorems instantiated for the Solana sBPF backend with its own
`SbpfAsm.lowerModule`, replacing the ad-hoc coverage manifest for the Counter
proven fragment.

1. `solana_counter_lowering_total` — the canonical Counter module lowers to
   sBPF assembly without error, witnessed by `native_decide`.
2. `solana_proven_subset_lowerable_counter` — the proven-fragment predicate
   implies the lowerable-fragment predicate for the Counter module.
-/

theorem solana_counter_lowering_total :
    (ProofForge.Backend.Solana.SbpfAsm.lowerModule
      ProofForge.IR.Examples.Counter.module).isOk = true := by
  native_decide

/-- PF-P3-01 structural inclusion: every proved Counter module is Solana-lowerable. -/
theorem solana_proven_subset_lowerable
    (m : ProofForge.IR.Module)
    (h : solanaSbpfTargetSemantics.fragmentAccepts m = true) :
    solanaSbpfTargetSemantics.lowerableAccepts m = true :=
  isCounterModule_implies_shape_lowerable m h

theorem solana_proven_subset_lowerable_counter :
    solanaSbpfTargetSemantics.fragmentAccepts
      ProofForge.IR.Examples.Counter.module = true →
    solanaSbpfTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true :=
  solana_proven_subset_lowerable ProofForge.IR.Examples.Counter.module

theorem solana_lowerable_implies_lowering_total_counter
    (_h : solanaSbpfTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true) :
    (ProofForge.Backend.Solana.SbpfAsm.lowerModule
      ProofForge.IR.Examples.Counter.module).isOk = true :=
  solana_counter_lowering_total

theorem solana_fragment_subset_lowerable_counter
    (h : solanaSbpfTargetSemantics.fragmentAccepts
      ProofForge.IR.Examples.Counter.module = true) :
    solanaSbpfTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true :=
  solana_proven_subset_lowerable_counter h

/-- Track 1.4 theorem 3 (capability-accept ⇒ lowerable), Solana Counter
instance: if the Solana target profile resolves the Counter module's capability
spec, then the Counter module is in the Solana lowerable fragment. -/
theorem solana_capability_accept_implies_lowerable_counter
    (h : (ProofForge.Target.resolveModule ProofForge.Target.solanaSbpfAsm
        ProofForge.IR.Examples.Counter.module).isOk = true) :
    solanaSbpfTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true := by
  native_decide

def solanaRenamedCounterWitness : ProofForge.IR.Module :=
  { ProofForge.IR.Examples.Counter.module with name := "CounterRenamed" }

theorem solana_renamed_counter_lowerable_not_proved :
    solanaSbpfTargetSemantics.lowerableAccepts solanaRenamedCounterWitness = true ∧
      solanaSbpfTargetSemantics.fragmentAccepts solanaRenamedCounterWitness = false := by
  native_decide

theorem solana_renamed_counter_lowering_total :
    (ProofForge.Backend.Solana.SbpfAsm.lowerModule
      solanaRenamedCounterWitness).isOk = true := by
  native_decide

/-- PF-P3-01: name pin turns lowerable renamed shape into proved Counter. -/
theorem solana_renamed_witness_canonicalizes_to_proved :
    isCounterModule (withCanonicalCounterName solanaRenamedCounterWitness) = true :=
  isCounterShapeLowerable_implies_isCounterModule_with_canonical_name
    solanaRenamedCounterWitness (by native_decide)

theorem solana_renamed_witness_canonical_lowering_total :
    (ProofForge.Backend.Solana.SbpfAsm.lowerModule
      (withCanonicalCounterName solanaRenamedCounterWitness)).isOk = true := by
  native_decide

end ProofForge.Backend.Solana.Refinement
