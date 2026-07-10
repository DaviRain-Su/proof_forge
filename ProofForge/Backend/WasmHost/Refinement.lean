import ProofForge.Backend.WasmHost.EmitWat
import ProofForge.Backend.WasmHost.Memory
import ProofForge.Backend.WasmHost.Types
import ProofForge.IR.Semantics
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.Compiler.Wasm.AST
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Contract.Examples.ValueVaultInvariant
import ProofForge.Backend.WasmHost.Refinement.Core
import ProofForge.Backend.WasmHost.WasmInterpreter
import ProofForge.IR.StepSemantics
import ProofForge.Target.Registry
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Target.Adapter

namespace ProofForge.Backend.WasmHost.Refinement

open ProofForge.IR
open ProofForge.Backend.Refinement
open ProofForge.Backend.WasmHost.WasmInterpreter

def counterTraceEntrypoints : Array Entrypoint := #[
  ProofForge.IR.Examples.Counter.initializeEntrypoint,
  ProofForge.IR.Examples.Counter.get,
  ProofForge.IR.Examples.Counter.increment,
  ProofForge.IR.Examples.Counter.get
]

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
  calls := traceCallsFromEntrypoints counterTraceEntrypoints
  expected := counterExpectedTrace
}

def valueVaultEntrypointD (entrypointName : String) : Entrypoint :=
  match ProofForge.Contract.Examples.ValueVault.module.entrypoints.find?
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
  module := ProofForge.Contract.Examples.ValueVault.module
  calls := valueVaultTraceCalls
  expected := valueVaultExpectedTrace
}

/-! ### Storage array and map probe obligations

These extend the in-Lean executable Wasm trace beyond scalar fields by running
the emitted fixed-array storage and u64 map helper paths against the shared IR
semantics. -/

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

def wasmExecutableTraceOk (obligation : TraceObligation) : Bool :=
  ProofForge.Backend.WasmHost.WasmInterpreter.executableTraceOk obligation

structure WasmHostMachineState where
  wasm : ProofForge.Compiler.Wasm.Module
  state : ProofForge.Backend.WasmHost.WasmInterpreter.WasmState

def WasmHostMachineState.traceStep (machine : WasmHostMachineState) (call : TraceCall) :
    Except String (WasmHostMachineState × ObservableStep) := do
  let state ←
    ProofForge.Backend.WasmHost.WasmInterpreter.runExport
      machine.wasm machine.state call
  let observable ←
    ProofForge.Backend.WasmHost.WasmInterpreter.observeEntrypoint
      call.entrypoint state
  .ok ({ machine with state }, {
    entrypointName := call.entrypoint.name
    returnValue := observable
  })

def wasmNearTargetSemantics : TargetSemantics := {
  id := "wasm-near"
  supportedFragments := #[.counter]
  fragmentAccepts := isCounterModuleForWasmBridge .near
  lowerableAccepts := isCounterShapeLowerableForWasmBridge .near
  MachineState := WasmHostMachineState
  Call := TraceCall
  Obs := ObservableStep
  traceStep := WasmHostMachineState.traceStep
  runTrace := fun calls state => ProofForge.IR.StepSemantics.runTraceListGen
    WasmHostMachineState.traceStep calls state
  runTrace_eq_traceStep := by
    intro calls state
    rfl
  executableTraceOk := wasmExecutableTraceOk
  initialRelHolds := by intros; trivial
}

def counterWasmSimulationRel
    (irState : ProofForge.IR.Semantics.State)
    (machine : WasmHostMachineState) : Bool :=
  ProofForge.Backend.WasmHost.WasmInterpreter.ROptional
    ProofForge.IR.Examples.Counter.module "count" irState machine.state

def counterWasmInitialTarget
    (wasm : ProofForge.Compiler.Wasm.Module) : WasmHostMachineState :=
  { wasm, state := ProofForge.Backend.WasmHost.WasmInterpreter.initialState wasm }

def counterWasmStateAfterPrefix
    (wasm : ProofForge.Compiler.Wasm.Module)
    (callPrefix : List TraceCall) :
    Except String (ProofForge.IR.Semantics.State × WasmHostMachineState) := do
  let (irState, _) ← ProofForge.IR.StepSemantics.runTraceListGen
    runEntrypointObservable callPrefix ProofForge.IR.Semantics.State.empty
  let (targetState, _) ← ProofForge.IR.StepSemantics.runTraceListGen
    WasmHostMachineState.traceStep callPrefix (counterWasmInitialTarget wasm)
  .ok (irState, targetState)

def counterWasmStepSimulationOkAfter
    (callPrefix : List TraceCall) (call : TraceCall) : Bool :=
  match ProofForge.Backend.WasmHost.EmitWat.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok wasm =>
      match counterWasmStateAfterPrefix wasm callPrefix with
      | .error _ => false
      | .ok (irState, targetState) =>
          executableStepSimulationOk
            runEntrypointObservable
            WasmHostMachineState.traceStep
            counterWasmSimulationRel
            call
            irState
            targetState

theorem counter_wasm_step_simulation_sound_after
    (callPrefix : List TraceCall) (call : TraceCall) :
    counterWasmStepSimulationOkAfter callPrefix call = true →
      match ProofForge.Backend.WasmHost.EmitWat.lowerModule
          ProofForge.IR.Examples.Counter.module with
      | .error _ => True
      | .ok wasm =>
          match counterWasmStateAfterPrefix wasm callPrefix with
          | .error _ => True
          | .ok (irState, targetState) =>
              ∃ nextIr nextTarget observable,
                runEntrypointObservable irState call =
                  .ok (nextIr, observable) ∧
                WasmHostMachineState.traceStep targetState call =
                  .ok (nextTarget, observable) ∧
                counterWasmSimulationRel nextIr nextTarget = true := by
  intro h
  unfold counterWasmStepSimulationOkAfter at h
  cases hmod : ProofForge.Backend.WasmHost.EmitWat.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | error _ =>
      trivial
  | ok wasm =>
      simp [hmod] at h
      cases hprefix : counterWasmStateAfterPrefix wasm callPrefix with
      | error _ =>
          simp [hprefix]
      | ok pair =>
          rcases pair with ⟨irState, targetState⟩
          simp [hprefix] at h
          simpa [hmod, hprefix] using executableStepSimulationOk_sound
            runEntrypointObservable
            WasmHostMachineState.traceStep
            counterWasmSimulationRel
            call
            irState
            targetState
            h

theorem counter_wasm_initialize_step_simulation_ok :
    counterWasmStepSimulationOkAfter [] counterInitializeCall = true := by
  native_decide

theorem counter_wasm_get_after_initialize_step_simulation_ok :
    counterWasmStepSimulationOkAfter [counterInitializeCall] counterGetCall = true := by
  native_decide

theorem counter_wasm_increment_after_initialize_step_simulation_ok :
    counterWasmStepSimulationOkAfter [counterInitializeCall] counterIncrementCall = true := by
  native_decide

theorem counter_wasm_get_after_increment_step_simulation_ok :
    counterWasmStepSimulationOkAfter
      [counterInitializeCall, counterIncrementCall] counterGetCall = true := by
  native_decide

theorem counter_wasm_initialize_step_simulation_sound_checked :
    match ProofForge.Backend.WasmHost.EmitWat.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok wasm =>
        match counterWasmStateAfterPrefix wasm [] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterInitializeCall =
                .ok (nextIr, observable) ∧
              WasmHostMachineState.traceStep targetState counterInitializeCall =
                .ok (nextTarget, observable) ∧
              counterWasmSimulationRel nextIr nextTarget = true :=
  counter_wasm_step_simulation_sound_after
    [] counterInitializeCall counter_wasm_initialize_step_simulation_ok

theorem counter_wasm_get_after_initialize_step_simulation_sound_checked :
    match ProofForge.Backend.WasmHost.EmitWat.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok wasm =>
        match counterWasmStateAfterPrefix wasm [counterInitializeCall] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterGetCall =
                .ok (nextIr, observable) ∧
              WasmHostMachineState.traceStep targetState counterGetCall =
                .ok (nextTarget, observable) ∧
              counterWasmSimulationRel nextIr nextTarget = true :=
  counter_wasm_step_simulation_sound_after
    [counterInitializeCall] counterGetCall
    counter_wasm_get_after_initialize_step_simulation_ok

theorem counter_wasm_increment_after_initialize_step_simulation_sound_checked :
    match ProofForge.Backend.WasmHost.EmitWat.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok wasm =>
        match counterWasmStateAfterPrefix wasm [counterInitializeCall] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterIncrementCall =
                .ok (nextIr, observable) ∧
              WasmHostMachineState.traceStep targetState counterIncrementCall =
                .ok (nextTarget, observable) ∧
              counterWasmSimulationRel nextIr nextTarget = true :=
  counter_wasm_step_simulation_sound_after
    [counterInitializeCall] counterIncrementCall
    counter_wasm_increment_after_initialize_step_simulation_ok

theorem counter_wasm_get_after_increment_step_simulation_sound_checked :
    match ProofForge.Backend.WasmHost.EmitWat.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok wasm =>
        match counterWasmStateAfterPrefix wasm
            [counterInitializeCall, counterIncrementCall] with
        | .error _ => True
        | .ok (irState, targetState) =>
            ∃ nextIr nextTarget observable,
              runEntrypointObservable irState counterGetCall =
                .ok (nextIr, observable) ∧
              WasmHostMachineState.traceStep targetState counterGetCall =
                .ok (nextTarget, observable) ∧
              counterWasmSimulationRel nextIr nextTarget = true :=
  counter_wasm_step_simulation_sound_after
    [counterInitializeCall, counterIncrementCall] counterGetCall
    counter_wasm_get_after_increment_step_simulation_ok

def counterWasmTraceSimulationOk : Bool :=
  match ProofForge.Backend.WasmHost.EmitWat.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | .error _ => false
  | .ok wasm =>
      executableSimulationTraceOk
        runEntrypointObservable
        WasmHostMachineState.traceStep
        counterWasmSimulationRel
        counterTraceObligation.calls.toList
        ProofForge.IR.Semantics.State.empty
        (counterWasmInitialTarget wasm)

theorem counter_wasm_trace_simulation_ok :
    counterWasmTraceSimulationOk = true := by
  native_decide

theorem counter_wasm_trace_simulation_sound :
    counterWasmTraceSimulationOk = true →
      match ProofForge.Backend.WasmHost.EmitWat.lowerModule
          ProofForge.IR.Examples.Counter.module with
      | .error _ => True
      | .ok wasm =>
          ∃ finalIr finalTarget observables,
            ProofForge.IR.StepSemantics.runTraceListGen
              runEntrypointObservable
              counterTraceObligation.calls.toList
              ProofForge.IR.Semantics.State.empty =
                .ok (finalIr, observables) ∧
            ProofForge.IR.StepSemantics.runTraceListGen
              WasmHostMachineState.traceStep
              counterTraceObligation.calls.toList
              { wasm,
                state := ProofForge.Backend.WasmHost.WasmInterpreter.initialState wasm } =
                .ok (finalTarget, observables) ∧
            counterWasmSimulationRel finalIr finalTarget = true := by
  intro h
  unfold counterWasmTraceSimulationOk at h
  cases hmod : ProofForge.Backend.WasmHost.EmitWat.lowerModule
      ProofForge.IR.Examples.Counter.module with
  | error _ =>
      trivial
  | ok wasm =>
      simp [hmod] at h
      exact executableSimulationTraceOk_sound
        runEntrypointObservable
        WasmHostMachineState.traceStep
        counterWasmSimulationRel
        counterTraceObligation.calls.toList
        ProofForge.IR.Semantics.State.empty
        { wasm, state := ProofForge.Backend.WasmHost.WasmInterpreter.initialState wasm }
        h

theorem counter_wasm_trace_simulation_sound_checked :
    match ProofForge.Backend.WasmHost.EmitWat.lowerModule
        ProofForge.IR.Examples.Counter.module with
    | .error _ => True
    | .ok wasm =>
        ∃ finalIr finalTarget observables,
          ProofForge.IR.StepSemantics.runTraceListGen
            runEntrypointObservable
            counterTraceObligation.calls.toList
            ProofForge.IR.Semantics.State.empty =
              .ok (finalIr, observables) ∧
          ProofForge.IR.StepSemantics.runTraceListGen
            WasmHostMachineState.traceStep
            counterTraceObligation.calls.toList
            { wasm,
              state := ProofForge.Backend.WasmHost.WasmInterpreter.initialState wasm } =
              .ok (finalTarget, observables) ∧
          counterWasmSimulationRel finalIr finalTarget = true :=
  counter_wasm_trace_simulation_sound counter_wasm_trace_simulation_ok

def emitWatKeyBuf : Nat := ProofForge.Backend.WasmHost.Memory.KEY_BUF
def emitWatRetBuf : Nat := ProofForge.Backend.WasmHost.Memory.RET_BUF
def emitWatEventBuf : Nat := ProofForge.Backend.WasmHost.Memory.EVENT_BUF
def emitWatEvtKeyPtr : Nat := ProofForge.Backend.WasmHost.Memory.EVT_KEY_PTR
def emitWatInputBuf : Nat := ProofForge.Backend.WasmHost.Memory.INPUT_BUF
def emitWatEvtPtrGlobal : String := ProofForge.Backend.WasmHost.EmitWat.evtPtrGlobal

def nearHostBufferMemoryRegions : Array WasmMemoryRegionExpectation := #[
  { name := "KEY_BUF", offset := emitWatKeyBuf, byteLength := 32 },
  { name := "RET_BUF", offset := emitWatRetBuf, byteLength := 32 },
  { name := "EVENT_BUF", offset := emitWatEventBuf, byteLength := 256 },
  { name := "EVT_PUNCT", offset := emitWatEvtKeyPtr, byteLength := 16 },
  { name := "INPUT_BUF", offset := emitWatInputBuf, byteLength := 1024 }
]

def nearHostBufferMemoryLayoutOk : Bool :=
  wasmMemoryLayoutOk nearHostBufferMemoryRegions

def nearU64StorageReadFrame : Array WasmTraceOp := #[
  .localGet "kl",
  .plain "i64.extend_i32_u",
  .localGet "kp",
  .plain "i64.extend_i32_u",
  .i64Const 0,
  .call "storage_read",
  .localSet "found",
  .localGet "found",
  .i64Const 0,
  .plain "i64.ne",
  .i64Const 0,
  .i64Const emitWatKeyBuf,
  .call "read_register",
  .i32Const emitWatKeyBuf,
  .load "i64.load" 0,
  .localSet "r"
]

def nearU64StorageWriteFrame : Array WasmTraceOp := #[
  .i32Const emitWatKeyBuf,
  .localGet "v",
  .store "i64.store" 0,
  .localGet "kl",
  .plain "i64.extend_i32_u",
  .localGet "kp",
  .plain "i64.extend_i32_u",
  .i64Const 8,
  .i64Const emitWatKeyBuf,
  .i64Const 0,
  .call "storage_write",
  .drop
]

def nearU64ValueReturnFrame : Array WasmTraceOp := #[
  .i32Const emitWatRetBuf,
  .localGet "v",
  .store "i64.store" 0,
  .i64Const 8,
  .i64Const emitWatRetBuf,
  .call "value_return"
]

def nearEventLogUtf8Frame : Array WasmTraceOp := #[
  .globalGet emitWatEvtPtrGlobal,
  .i32Const emitWatEventBuf,
  .plain "i32.sub",
  .plain "i64.extend_i32_u",
  .i64Const emitWatEventBuf,
  .call "log_utf8"
]

def nearInputRegisterFrame : Array WasmTraceOp := #[
  .i64Const 0,
  .call "input",
  .i64Const 0,
  .i64Const emitWatInputBuf,
  .call "read_register"
]

def nearU64InputParamFrame (name : String) (offset : Nat) : Array WasmTraceOp :=
  nearInputRegisterFrame ++ #[
    .i32Const (emitWatInputBuf + offset),
    .load "i64.load" 0,
    .localSet name
  ]

def nearU64ParamLoadFrame (name : String) (offset : Nat) : Array WasmTraceOp := #[
  .i32Const (emitWatInputBuf + offset),
  .load "i64.load" 0,
  .localSet name
]

def nearU64StorageReadKeyFrame (keyPtr keyLen : Nat) : Array WasmTraceOp := #[
  .i32Const keyPtr,
  .i32Const keyLen,
  .call (ProofForge.Backend.WasmHost.Types.readName .u64)
]

def nearU64StorageWriteExprFrame
    (keyPtr keyLen : Nat)
    (valueOps : Array WasmTraceOp) : Array WasmTraceOp :=
  #[.i32Const keyPtr, .i32Const keyLen] ++
    valueOps ++
    #[.call (ProofForge.Backend.WasmHost.Types.writeName .u64)]

def nearU64StorageWriteLiteralFrame (keyPtr keyLen value : Nat) : Array WasmTraceOp :=
  nearU64StorageWriteExprFrame keyPtr keyLen #[.i64Const value]

def nearU64StorageWriteLocalFrame (keyPtr keyLen : Nat) (localName : String) :
    Array WasmTraceOp :=
  nearU64StorageWriteExprFrame keyPtr keyLen #[.localGet localName]

def nearU64StorageWriteLocalAddLiteralFrame
    (keyPtr keyLen : Nat)
    (localName : String)
    (value : Nat) : Array WasmTraceOp :=
  nearU64StorageWriteExprFrame keyPtr keyLen #[
    .localGet localName,
    .i64Const value,
    .plain "i64.add"
  ]

def nearCheckpointBlockIndexFrame (localName : String) : Array WasmTraceOp := #[
  .call "block_index",
  .localSet localName
]

def nearU64HostFrameExpectations : Array WasmHostFrameExpectation := #[
  {
    functionName := ProofForge.Backend.WasmHost.Types.readName .u64
    expectedOps := nearU64StorageReadFrame
  },
  {
    functionName := ProofForge.Backend.WasmHost.Types.writeName .u64
    expectedOps := nearU64StorageWriteFrame
  },
  {
    functionName := ProofForge.Backend.WasmHost.Types.returnU64Name
    expectedOps := nearU64ValueReturnFrame
  }
]

/-- Counter entrypoints are zero-arg: no `input` / `read_register` prologue. -/
def nearInputHostFrameExpectations : Array WasmHostFrameExpectation := #[]

/-- Only entrypoints with Borsh params keep the input prologue. -/
def nearValueVaultInputHostFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearU64InputParamFrame "initial" 0 },
  { functionName := "deposit", expectedOps := nearU64InputParamFrame "amount" 0 },
  { functionName := "charge_fee", expectedOps := nearU64InputParamFrame "gross" 0 },
  {
    functionName := "charge_fee"
    expectedOps := nearU64ParamLoadFrame "fee_bps" 8
  },
  { functionName := "release", expectedOps := nearU64InputParamFrame "amount" 0 }
]

def nearValueVaultContextHostFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearCheckpointBlockIndexFrame "checkpoint" },
  { functionName := "snapshot", expectedOps := nearCheckpointBlockIndexFrame "checkpoint" }
]

def counterStorageReadKeyFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "increment", expectedOps := nearU64StorageReadKeyFrame 0 5 },
  { functionName := "get", expectedOps := nearU64StorageReadKeyFrame 0 5 }
]

def counterStorageWriteKeyValueFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 0 5 0 },
  {
    functionName := "increment"
    expectedOps := nearU64StorageWriteLocalAddLiteralFrame 0 5 "n" 1
  }
]

/-- Unversioned NEAR modules retain the stable per-field key layout. -/
def valueVaultStorageReadKeyFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "deposit", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "deposit", expectedOps := nearU64StorageReadKeyFrame 49 10 },
  { functionName := "charge_fee", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "charge_fee", expectedOps := nearU64StorageReadKeyFrame 17 4 },
  { functionName := "charge_fee", expectedOps := nearU64StorageReadKeyFrame 49 10 },
  { functionName := "release", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "release", expectedOps := nearU64StorageReadKeyFrame 8 8 },
  { functionName := "release", expectedOps := nearU64StorageReadKeyFrame 49 10 },
  { functionName := "snapshot", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "snapshot", expectedOps := nearU64StorageReadKeyFrame 8 8 },
  { functionName := "snapshot", expectedOps := nearU64StorageReadKeyFrame 17 4 },
  { functionName := "get_balance", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "get_net_value", expectedOps := nearU64StorageReadKeyFrame 0 7 },
  { functionName := "get_net_value", expectedOps := nearU64StorageReadKeyFrame 17 4 }
]

def valueVaultStorageWriteKeyValueFrameExpectations : Array WasmHostFrameExpectation := #[
  { functionName := "initialize", expectedOps := nearU64StorageWriteLocalFrame 0 7 "initial" },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 8 8 0 },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 17 4 0 },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLocalFrame 22 10 "initial" },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLocalFrame 33 15 "checkpoint" },
  { functionName := "initialize", expectedOps := nearU64StorageWriteLiteralFrame 49 10 1 },
  { functionName := "deposit", expectedOps := nearU64StorageWriteLocalFrame 0 7 "next" },
  { functionName := "deposit", expectedOps := nearU64StorageWriteLocalFrame 22 10 "amount" },
  { functionName := "deposit", expectedOps := nearU64StorageWriteLocalFrame 49 10 "next_ops" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 0 7 "next" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 17 4 "next_fees" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 22 10 "net" },
  { functionName := "charge_fee", expectedOps := nearU64StorageWriteLocalFrame 49 10 "next_ops" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 0 7 "next" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 8 8 "released_next" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 22 10 "amount" },
  { functionName := "release", expectedOps := nearU64StorageWriteLocalFrame 49 10 "next_ops" },
  { functionName := "snapshot", expectedOps := nearU64StorageWriteLocalFrame 33 15 "checkpoint" }
]

def wasmHostFramesOk
    (module : Module)
    (frames : Array WasmHostFrameExpectation) : Bool :=
  match ProofForge.Backend.WasmHost.EmitWat.lowerModule module with
  | .ok wasm => frames.all (fun expectation => expectation.ok wasm)
  | .error _ => false

def wasmHostFrameExpectationEq
    (lhs rhs : WasmHostFrameExpectation) : Bool :=
  lhs.functionName == rhs.functionName && lhs.expectedOps == rhs.expectedOps

def wasmHostFramesPairwiseUniqueList : List WasmHostFrameExpectation → Bool
  | [] => true
  | frame :: rest =>
      !rest.any (wasmHostFrameExpectationEq frame) &&
        wasmHostFramesPairwiseUniqueList rest

def wasmHostFramesPairwiseUnique
    (frames : Array WasmHostFrameExpectation) : Bool :=
  wasmHostFramesPairwiseUniqueList frames.toList

def wasmTraceCallCount (ops : Array WasmTraceOp) (callee : String) : Nat :=
  ops.foldl (fun count op =>
    match op with
    | .call name => if name == callee then count + 1 else count
    | _ => count) 0

def expectedHostFrameCount
    (frames : Array WasmHostFrameExpectation)
    (functionName : String) : Nat :=
  frames.foldl (fun count frame =>
    if frame.functionName == functionName then count + 1 else count) 0

/-- Exact entrypoint host-frame coverage: every listed frame must exist, frames
are unique, and their per-entrypoint count must equal the generated call count.
This turns omission from a vacuous pass into a failing obligation. -/
def wasmEntrypointHostFramesComplete
    (module : Module)
    (frames : Array WasmHostFrameExpectation)
    (callee : String) : Bool :=
  match ProofForge.Backend.WasmHost.EmitWat.lowerModule module with
  | .error _ => false
  | .ok wasm =>
      wasmHostFramesPairwiseUnique frames &&
        frames.all (fun expectation => expectation.ok wasm) &&
        module.entrypoints.all (fun entrypoint =>
          match findFunc? wasm entrypoint.name with
          | none => false
          | some func =>
              wasmTraceCallCount func.traceOps callee ==
                expectedHostFrameCount frames entrypoint.name)

def counterInputHostFramesOk : Bool :=
  wasmHostFramesOk ProofForge.IR.Examples.Counter.module nearInputHostFrameExpectations

def counterStorageReadKeyFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.IR.Examples.Counter.module
    counterStorageReadKeyFrameExpectations

def counterStorageWriteKeyValueFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.IR.Examples.Counter.module
    counterStorageWriteKeyValueFrameExpectations

def valueVaultInputHostFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.Contract.Examples.ValueVault.module
    nearValueVaultInputHostFrameExpectations

def valueVaultContextHostFramesOk : Bool :=
  wasmHostFramesOk
    ProofForge.Contract.Examples.ValueVault.module
    nearValueVaultContextHostFrameExpectations

def valueVaultStorageReadKeyFramesOk : Bool :=
  wasmEntrypointHostFramesComplete
    ProofForge.Contract.Examples.ValueVault.module
    valueVaultStorageReadKeyFrameExpectations
    (ProofForge.Backend.WasmHost.Types.readName .u64)

def valueVaultStorageWriteKeyValueFramesOk : Bool :=
  wasmEntrypointHostFramesComplete
    ProofForge.Contract.Examples.ValueVault.module
    valueVaultStorageWriteKeyValueFrameExpectations
    (ProofForge.Backend.WasmHost.Types.writeName .u64)

def counterArtifactSurfaceObligation : ArtifactSurfaceObligation := {
  name := "Counter.EmitWat.artifact-surface"
  module := ProofForge.IR.Examples.Counter.module
  requiredImports := #[
    "read_register",
    "storage_read",
    "storage_write",
    "value_return"
  ]
  requiredImportSignatures := #[
    { functionName := "read_register", params := #[.i64, .i64] },
    { functionName := "storage_read", params := #[.i64, .i64, .i64], results := #[.i64] },
    {
      functionName := "storage_write"
      params := #[.i64, .i64, .i64, .i64, .i64]
      results := #[.i64]
    },
    { functionName := "value_return", params := #[.i64, .i64] }
  ]
  requiredExports := #[
    { exportName := "initialize", expectedCalls := #["__pf_write_u64"] },
    { exportName := "increment", expectedCalls := #["__pf_read_u64", "__pf_write_u64"] },
    { exportName := "get", expectedCalls := #["__pf_read_u64", "__pf_return_u64"] }
  ]
  requiredFunctions := #[
    { functionName := "__pf_read_u64", expectedCalls := #["storage_read", "read_register"] },
    { functionName := "__pf_write_u64", expectedCalls := #["storage_write"] },
    { functionName := "__pf_return_u64", expectedCalls := #["value_return"] }
  ]
  requiredHostFrames :=
    nearU64HostFrameExpectations ++
      nearInputHostFrameExpectations ++
      counterStorageReadKeyFrameExpectations ++
      counterStorageWriteKeyValueFrameExpectations
  requiredDataSegments := #[(0, "count")]
  requiredMemoryRegions := nearHostBufferMemoryRegions
}

def counterStorageSnapshot (count : Nat) :
    Array (String × ProofForge.IR.Semantics.Value) :=
  #[("count", .u64 count)]

def counterStorageHexSnapshot (count : Nat) : Array (String × String) :=
  #[("count", littleEndianHex 8 count)]

def counterOfflineHostExecutionObligation : OfflineHostExecutionObligation := {
  name := "Counter.EmitWat.offline-host-execution-surface"
  artifactSurface := counterArtifactSurfaceObligation
  steps := #[
    { exportName := "initialize" },
    { exportName := "get" },
    { exportName := "increment" },
    { exportName := "get" }
  ]
  expectedIO := #[
    {
      exportName := "initialize"
      inputHex := ""
      returnLineFragment := "call 1:initialize: return=<none>"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 0
      storageHexSnapshot := counterStorageHexSnapshot 0
      logCount := 0
    },
    {
      exportName := "get"
      inputHex := ""
      returnLineFragment := "call 1:get: return_hex=0000000000000000 return_u64=0"
      returnPayloadHex := "0000000000000000"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 0
      storageHexSnapshot := counterStorageHexSnapshot 0
      logCount := 0
    },
    {
      exportName := "increment"
      inputHex := ""
      returnLineFragment := "call 1:increment: return=<none>"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 1
      storageHexSnapshot := counterStorageHexSnapshot 1
      logCount := 0
    },
    {
      exportName := "get"
      inputHex := ""
      returnLineFragment := "call 1:get: return_hex=0100000000000000 return_u64=1"
      returnPayloadHex := "0100000000000000"
      storageKeys := 1
      storageSnapshot := counterStorageSnapshot 1
      storageHexSnapshot := counterStorageHexSnapshot 1
      logCount := 0
    }
  ]
}

def valueVaultArtifactSurfaceObligation : ArtifactSurfaceObligation := {
  name := "ValueVault.EmitWat.artifact-surface"
  module := ProofForge.Contract.Examples.ValueVault.module
  requiredImports := #[
    "input",
    "read_register",
    "storage_read",
    "storage_write",
    "value_return",
    "log_utf8",
    "block_index"
  ]
  requiredImportSignatures := #[
    { functionName := "input", params := #[.i64] },
    { functionName := "read_register", params := #[.i64, .i64] },
    { functionName := "storage_read", params := #[.i64, .i64, .i64], results := #[.i64] },
    {
      functionName := "storage_write"
      params := #[.i64, .i64, .i64, .i64, .i64]
      results := #[.i64]
    },
    { functionName := "value_return", params := #[.i64, .i64] },
    { functionName := "log_utf8", params := #[.i64, .i64] },
    { functionName := "block_index", results := #[.i64] }
  ]
  requiredExports := #[
    {
      exportName := "initialize"
      expectedCalls := #[
        "input", "read_register", "block_index", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "deposit"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "charge_fee"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "release"
      expectedCalls := #[
        "input", "read_register", "__pf_read_u64", "__pf_write_u64", "__pf_evt_log"
      ]
    },
    {
      exportName := "snapshot"
      -- Zero-arg stateful entrypoint: no input prologue.
      expectedCalls := #[
        "block_index", "__pf_read_u64", "__pf_write_u64",
        "__pf_evt_log", "__pf_return_u64"
      ]
    },
    {
      exportName := "get_balance"
      expectedCalls := #["__pf_read_u64", "__pf_return_u64"]
    },
    {
      exportName := "get_net_value"
      expectedCalls := #["__pf_read_u64", "__pf_return_u64"]
    }
  ]
  requiredFunctions := #[
    { functionName := "__pf_read_u64", expectedCalls := #["storage_read", "read_register"] },
    { functionName := "__pf_write_u64", expectedCalls := #["storage_write"] },
    { functionName := "__pf_return_u64", expectedCalls := #["value_return"] },
    { functionName := "__pf_evt_log", expectedCalls := #["log_utf8"] }
  ]
  requiredHostFrames :=
    nearU64HostFrameExpectations ++
      nearValueVaultInputHostFrameExpectations ++
      nearValueVaultContextHostFrameExpectations ++
      valueVaultStorageReadKeyFrameExpectations ++
      valueVaultStorageWriteKeyValueFrameExpectations ++
      #[{
          functionName := ProofForge.Backend.WasmHost.Types.returnU64Name
          expectedOps := nearU64ValueReturnFrame
        },
        {
          functionName := ProofForge.Backend.WasmHost.EmitWat.evtLogName
          expectedOps := nearEventLogUtf8Frame
        }]
  requiredDataSegments := #[
    (0, "balance"),
    (8, "released"),
    (17, "fees"),
    (22, "last_value"),
    (33, "last_checkpoint"),
    (49, "operations"),
    -- Composite JSON event headers (one putstr per event; see Layout.eventHeaderPoolString)
    (43000, "{\"event\":\"VaultInitialized\""),
    (43055, "{\"event\":\"ValueDeposited\""),
    (43119, "{\"event\":\"ValueCharged\""),
    (43169, "{\"event\":\"ValueReleased\""),
    (43207, "{\"event\":\"ValueSnapshot\"")
  ]
  requiredMemoryRegions := nearHostBufferMemoryRegions
}

def valueVaultStorageSnapshot
    (balance released fees lastValue lastCheckpoint operations : Nat) :
    Array (String × ProofForge.IR.Semantics.Value) := #[
  ("balance", .u64 balance),
  ("released", .u64 released),
  ("fees", .u64 fees),
  ("last_value", .u64 lastValue),
  ("last_checkpoint", .u64 lastCheckpoint),
  ("operations", .u64 operations)
]

def valueVaultStorageHexSnapshot
    (balance released fees lastValue lastCheckpoint operations : Nat) :
    Array (String × String) := #[
  ("balance", littleEndianHex 8 balance),
  ("released", littleEndianHex 8 released),
  ("fees", littleEndianHex 8 fees),
  ("last_value", littleEndianHex 8 lastValue),
  ("last_checkpoint", littleEndianHex 8 lastCheckpoint),
  ("operations", littleEndianHex 8 operations)
]

def valueVaultOfflineHostExecutionObligation : OfflineHostExecutionObligation := {
  name := "ValueVault.EmitWat.offline-host-execution-surface"
  artifactSurface := valueVaultArtifactSurfaceObligation
  steps := #[
    { exportName := "initialize", args := #[.u64 100] },
    { exportName := "get_balance" },
    { exportName := "deposit", args := #[.u64 25] },
    { exportName := "get_balance" },
    { exportName := "charge_fee", args := #[.u64 100, .u64 250] },
    { exportName := "get_balance" },
    { exportName := "get_net_value" },
    { exportName := "release", args := #[.u64 23] },
    { exportName := "get_balance" },
    { exportName := "snapshot" },
    { exportName := "get_net_value" }
  ]
  expectedIO := #[
    {
      exportName := "initialize"
      inputHex := "6400000000000000"
      returnLineFragment := "call 1:initialize: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 100 0 0 100 0 1
      storageHexSnapshot := valueVaultStorageHexSnapshot 100 0 0 100 0 1
      logCount := 1
      logLineFragments := #[
        "log: {\"event\":\"VaultInitialized\",\"initial\":100,\"checkpoint\":0}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"VaultInitialized\",\"initial\":100,\"checkpoint\":0}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=6400000000000000 return_u64=100"
      returnPayloadHex := "6400000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 100 0 0 100 0 1
      storageHexSnapshot := valueVaultStorageHexSnapshot 100 0 0 100 0 1
      logCount := 1
    },
    {
      exportName := "deposit"
      inputHex := "1900000000000000"
      returnLineFragment := "call 1:deposit: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 125 0 0 25 0 2
      storageHexSnapshot := valueVaultStorageHexSnapshot 125 0 0 25 0 2
      logCount := 2
      logLineFragments := #[
        "log: {\"event\":\"ValueDeposited\",\"amount\":25,\"balance\":125,\"operations\":2}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueDeposited\",\"amount\":25,\"balance\":125,\"operations\":2}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=7d00000000000000 return_u64=125"
      returnPayloadHex := "7d00000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 125 0 0 25 0 2
      storageHexSnapshot := valueVaultStorageHexSnapshot 125 0 0 25 0 2
      logCount := 2
    },
    {
      exportName := "charge_fee"
      inputHex := "6400000000000000fa00000000000000"
      returnLineFragment := "call 1:charge_fee: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 223 0 2 98 0 3
      storageHexSnapshot := valueVaultStorageHexSnapshot 223 0 2 98 0 3
      logCount := 3
      logLineFragments := #[
        "log: {\"event\":\"ValueCharged\",\"gross\":100,\"fee\":2,\"net\":98,\"balance\":223}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueCharged\",\"gross\":100,\"fee\":2,\"net\":98,\"balance\":223}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=df00000000000000 return_u64=223"
      returnPayloadHex := "df00000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 223 0 2 98 0 3
      storageHexSnapshot := valueVaultStorageHexSnapshot 223 0 2 98 0 3
      logCount := 3
    },
    {
      exportName := "get_net_value"
      inputHex := ""
      returnLineFragment := "call 1:get_net_value: return_hex=dd00000000000000 return_u64=221"
      returnPayloadHex := "dd00000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 223 0 2 98 0 3
      storageHexSnapshot := valueVaultStorageHexSnapshot 223 0 2 98 0 3
      logCount := 3
    },
    {
      exportName := "release"
      inputHex := "1700000000000000"
      returnLineFragment := "call 1:release: return=<none>"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 4
      logLineFragments := #[
        "log: {\"event\":\"ValueReleased\",\"amount\":23,\"balance\":200,\"released\":23}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueReleased\",\"amount\":23,\"balance\":200,\"released\":23}"
      ]
    },
    {
      exportName := "get_balance"
      inputHex := ""
      returnLineFragment := "call 1:get_balance: return_hex=c800000000000000 return_u64=200"
      returnPayloadHex := "c800000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 4
    },
    {
      exportName := "snapshot"
      inputHex := ""
      returnLineFragment := "call 1:snapshot: return_hex=c800000000000000 return_u64=200"
      returnPayloadHex := "c800000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 5
      logLineFragments := #[
        "log: {\"event\":\"ValueSnapshot\",\"balance\":200,\"released\":23,\"fees\":2,\"checkpoint\":0}"
      ]
      logPayloadHexFragments := #[
        stringHex "{\"event\":\"ValueSnapshot\",\"balance\":200,\"released\":23,\"fees\":2,\"checkpoint\":0}"
      ]
    },
    {
      exportName := "get_net_value"
      inputHex := ""
      returnLineFragment := "call 1:get_net_value: return_hex=c600000000000000 return_u64=198"
      returnPayloadHex := "c600000000000000"
      storageKeys := 6
      storageSnapshot := valueVaultStorageSnapshot 200 23 2 23 0 4
      storageHexSnapshot := valueVaultStorageHexSnapshot 200 23 2 23 0 4
      logCount := 5
    }
  ]
}

def valueVaultOfflineHostStepsDeriveFromInvariantInputs : Bool :=
  valueVaultOfflineHostExecutionObligation.steps ==
    valueVaultOfflineHostSteps ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs

def valueVaultOfflineHostExpectedIODerivesFromInvariantReturns : Bool :=
  match valueVaultOfflineHostExpectedIO? ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs with
  | .ok expected =>
      offlineHostReturnSurfaceMatches expected valueVaultOfflineHostExecutionObligation.expectedIO
  | .error _ => false

def valueVaultOfflineHostReturnPayloadHexDerivesFromInvariantReturns : Bool :=
  match valueVaultOfflineHostExpectedIO? ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs with
  | .ok expected =>
      offlineHostReturnPayloadHexMatches expected valueVaultOfflineHostExecutionObligation.expectedIO
  | .error _ => false

def valueVaultEmitWatBackendInvariantBridgeOk : Bool :=
  ProofForge.Contract.Examples.ValueVaultInvariant.defaultScenarioTraceOk &&
    ProofForge.Contract.Examples.ValueVaultInvariant.defaultScenarioAccountingOk &&
    ProofForge.Contract.Examples.ValueVaultInvariant.defaultScenarioNetValueOk &&
    valueVaultOfflineHostStepsDeriveFromInvariantInputs &&
    valueVaultOfflineHostExpectedIODerivesFromInvariantReturns &&
    valueVaultOfflineHostReturnPayloadHexDerivesFromInvariantReturns &&
    valueVaultOfflineHostFinalStateDerivesFromInvariant
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs &&
    valueVaultArtifactSurfaceObligation.memorySurfaceOk &&
    valueVaultInputHostFramesOk &&
    valueVaultContextHostFramesOk &&
    valueVaultStorageReadKeyFramesOk &&
    valueVaultStorageWriteKeyValueFramesOk &&
    valueVaultOfflineHostExecutionObligation.returnPayloadHexOk &&
    valueVaultOfflineHostExecutionObligation.storageSnapshotsOk &&
    valueVaultOfflineHostExecutionObligation.storageHexSnapshotsOk &&
    valueVaultOfflineHostLogFragmentsDeriveFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs &&
    valueVaultOfflineHostExecutionObligation.logPayloadHexOk &&
    valueVaultOfflineHostLogPayloadHexDerivesFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs &&
    valueVaultOfflineHostExecutionObligation.ok

theorem value_vault_offline_host_final_state_derives_from_invariant :
    valueVaultOfflineHostFinalStateDerivesFromInvariant
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs = true := by
  native_decide

theorem value_vault_offline_host_logs_derive_from_invariant_state :
    valueVaultOfflineHostLogFragmentsDeriveFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs = true := by
  native_decide

theorem value_vault_offline_host_log_payload_hex_derives_from_invariant_state :
    valueVaultOfflineHostLogPayloadHexDerivesFromInvariantState
      ProofForge.Contract.Examples.ValueVaultInvariant.defaultInputs = true := by
  native_decide

theorem value_vault_offline_host_return_payload_hex_derives_from_invariant_returns :
    valueVaultOfflineHostReturnPayloadHexDerivesFromInvariantReturns = true := by
  native_decide

theorem near_emitwat_host_buffer_memory_layout_ok :
    nearHostBufferMemoryLayoutOk = true := by
  native_decide

theorem counter_ir_observable_trace_ok :
    counterTraceObligation.irTraceOk = true := by
  native_decide

theorem value_vault_ir_observable_trace_ok :
    valueVaultTraceObligation.irTraceOk = true := by
  native_decide

theorem array_storage_ir_observable_trace_ok :
    arrayStorageTraceObligation.irTraceOk = true := by
  native_decide

theorem map_storage_ir_observable_trace_ok :
    mapStorageTraceObligation.irTraceOk = true := by
  native_decide

theorem counter_emitwat_exports_trace_entrypoints :
    emitWatExportsOk counterTraceObligation = true := by
  native_decide

theorem counter_emitwat_artifact_surface_ok :
    counterArtifactSurfaceObligation.ok = true := by
  native_decide

theorem counter_emitwat_host_import_signatures_ok :
    counterArtifactSurfaceObligation.hostImportSignaturesOk = true := by
  native_decide

theorem counter_emitwat_host_frames_ok :
    counterArtifactSurfaceObligation.hostFramesOk = true := by
  native_decide

theorem counter_emitwat_input_host_frames_ok :
    counterInputHostFramesOk = true := by
  native_decide

theorem counter_emitwat_storage_read_key_frames_ok :
    counterStorageReadKeyFramesOk = true := by
  native_decide

theorem counter_emitwat_storage_write_key_value_frames_ok :
    counterStorageWriteKeyValueFramesOk = true := by
  native_decide

theorem counter_emitwat_memory_surface_ok :
    counterArtifactSurfaceObligation.memorySurfaceOk = true := by
  native_decide

theorem counter_emitwat_offline_host_execution_surface_ok :
    counterOfflineHostExecutionObligation.ok = true := by
  native_decide

theorem counter_wasm_executable_trace_ok :
    wasmExecutableTraceOk counterTraceObligation = true := by
  native_decide

theorem value_vault_wasm_executable_trace_ok :
    wasmExecutableTraceOk valueVaultTraceObligation = true := by
  native_decide

theorem array_storage_wasm_executable_trace_ok :
    wasmExecutableTraceOk arrayStorageTraceObligation = true := by
  native_decide

theorem map_storage_wasm_executable_trace_ok :
    wasmExecutableTraceOk mapStorageTraceObligation = true := by
  native_decide

theorem counter_emitwat_offline_host_return_payload_hex_ok :
    counterOfflineHostExecutionObligation.returnPayloadHexOk = true := by
  native_decide

theorem counter_emitwat_offline_host_storage_snapshots_ok :
    counterOfflineHostExecutionObligation.storageSnapshotsOk = true := by
  native_decide

theorem counter_emitwat_offline_host_storage_hex_snapshots_ok :
    counterOfflineHostExecutionObligation.storageHexSnapshotsOk = true := by
  native_decide

theorem value_vault_emitwat_artifact_surface_ok :
    valueVaultArtifactSurfaceObligation.ok = true := by
  native_decide

theorem value_vault_emitwat_host_import_signatures_ok :
    valueVaultArtifactSurfaceObligation.hostImportSignaturesOk = true := by
  native_decide

theorem value_vault_emitwat_host_frames_ok :
    valueVaultArtifactSurfaceObligation.hostFramesOk = true := by
  native_decide

theorem value_vault_emitwat_input_host_frames_ok :
    valueVaultInputHostFramesOk = true := by
  native_decide

theorem value_vault_emitwat_context_host_frames_ok :
    valueVaultContextHostFramesOk = true := by
  native_decide

theorem value_vault_emitwat_storage_read_key_frames_ok :
    valueVaultStorageReadKeyFramesOk = true := by
  native_decide

theorem value_vault_emitwat_storage_write_key_value_frames_ok :
    valueVaultStorageWriteKeyValueFramesOk = true := by
  native_decide

theorem value_vault_emitwat_storage_read_key_frame_omission_rejected :
    wasmEntrypointHostFramesComplete
        ProofForge.Contract.Examples.ValueVault.module
        valueVaultStorageReadKeyFrameExpectations.pop
        (ProofForge.Backend.WasmHost.Types.readName .u64) = false := by
  native_decide

theorem value_vault_emitwat_storage_write_key_value_frame_omission_rejected :
    wasmEntrypointHostFramesComplete
        ProofForge.Contract.Examples.ValueVault.module
        valueVaultStorageWriteKeyValueFrameExpectations.pop
        (ProofForge.Backend.WasmHost.Types.writeName .u64) = false := by
  native_decide

theorem value_vault_emitwat_memory_surface_ok :
    valueVaultArtifactSurfaceObligation.memorySurfaceOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_execution_surface_ok :
    valueVaultOfflineHostExecutionObligation.ok = true := by
  native_decide

theorem value_vault_emitwat_offline_host_return_payload_hex_ok :
    valueVaultOfflineHostExecutionObligation.returnPayloadHexOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_storage_snapshots_ok :
    valueVaultOfflineHostExecutionObligation.storageSnapshotsOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_storage_hex_snapshots_ok :
    valueVaultOfflineHostExecutionObligation.storageHexSnapshotsOk = true := by
  native_decide

theorem value_vault_emitwat_offline_host_log_payload_hex_ok :
    valueVaultOfflineHostExecutionObligation.logPayloadHexOk = true := by
  native_decide

theorem value_vault_emitwat_backend_invariant_bridge_ok :
    valueVaultEmitWatBackendInvariantBridgeOk = true := by
  native_decide

/-! ### Track 1.4 fragment theorems (Wasm/NEAR instance)

Two theorems instantiated for the Wasm/NEAR backend with its own
`EmitWat.lowerModule`, replacing the ad-hoc coverage manifest for the Counter
proven fragment.

1. `wasm_near_counter_lowering_total` — the canonical Counter module lowers to
   a Wasm module without error, witnessed by `native_decide`.
2. `wasm_near_proven_subset_lowerable_counter` — the proven-fragment predicate
   implies the lowerable-fragment predicate for the Counter module.
-/

theorem wasm_near_counter_lowering_total :
    (ProofForge.Backend.WasmHost.EmitWat.lowerModule
      ProofForge.IR.Examples.Counter.module).isOk = true := by
  native_decide

/-- PF-P3-01 structural inclusion: every proved Counter module is NEAR-lowerable. -/
theorem wasm_near_proven_subset_lowerable
    (m : ProofForge.IR.Module)
    (h : wasmNearTargetSemantics.fragmentAccepts m = true) :
    wasmNearTargetSemantics.lowerableAccepts m = true :=
  isCounterModuleForWasmBridge_implies_shape_lowerable .near m h

theorem wasm_near_proven_subset_lowerable_counter :
    wasmNearTargetSemantics.fragmentAccepts
      ProofForge.IR.Examples.Counter.module = true →
    wasmNearTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true :=
  wasm_near_proven_subset_lowerable ProofForge.IR.Examples.Counter.module

theorem wasm_near_lowerable_implies_lowering_total_counter
    (_h : wasmNearTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true) :
    (ProofForge.Backend.WasmHost.EmitWat.lowerModule
      ProofForge.IR.Examples.Counter.module).isOk = true :=
  wasm_near_counter_lowering_total

theorem wasm_near_fragment_subset_lowerable_counter
    (h : wasmNearTargetSemantics.fragmentAccepts
      ProofForge.IR.Examples.Counter.module = true) :
    wasmNearTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true :=
  wasm_near_proven_subset_lowerable_counter h

/-- Track 1.4 theorem 3 (capability-accept ⇒ lowerable), Wasm/NEAR Counter
instance: if the NEAR target profile resolves the Counter module's capability
spec, then the Counter module is in the Wasm/NEAR lowerable fragment. -/
theorem wasm_near_capability_accept_implies_lowerable_counter
    (_h : (ProofForge.Target.resolveModule ProofForge.Target.wasmNear
        ProofForge.IR.Examples.Counter.module).isOk = true) :
    wasmNearTargetSemantics.lowerableAccepts
      ProofForge.IR.Examples.Counter.module = true := by
  native_decide

def wasmNearRenamedCounterWitness : ProofForge.IR.Module :=
  { ProofForge.IR.Examples.Counter.module with name := "CounterRenamed" }

theorem wasm_near_renamed_counter_lowerable_not_proved :
    wasmNearTargetSemantics.lowerableAccepts wasmNearRenamedCounterWitness = true ∧
      wasmNearTargetSemantics.fragmentAccepts wasmNearRenamedCounterWitness = false := by
  native_decide

theorem wasm_near_renamed_counter_lowering_total :
    (ProofForge.Backend.WasmHost.EmitWat.lowerModule
      wasmNearRenamedCounterWitness).isOk = true := by
  native_decide

/-- PF-P3-01: name pin turns lowerable renamed shape into proved Counter. -/
theorem wasm_near_renamed_witness_canonicalizes_to_proved :
    isCounterModule (withCanonicalCounterName wasmNearRenamedCounterWitness) = true :=
  isCounterShapeLowerable_implies_isCounterModule_with_canonical_name
    wasmNearRenamedCounterWitness (by native_decide)

theorem wasm_near_renamed_witness_canonical_lowering_total :
    (ProofForge.Backend.WasmHost.EmitWat.lowerModule
      (withCanonicalCounterName wasmNearRenamedCounterWitness)).isOk = true := by
  native_decide

end ProofForge.Backend.WasmHost.Refinement
