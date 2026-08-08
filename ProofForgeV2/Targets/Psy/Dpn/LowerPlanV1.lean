/-
  PSY-DPN-2: PsyPlan → DPN package (restricted UInt64 Counter-shaped slice).

  Goal (product): eventually encode **all ProgramV1 constructs admitted on Psy**
  into DPN (see `docs/targets/10-psy-dpn-lowering.md` §3). This module is the
  first vertical cut: single-field UInt64 state + initialize store(param) +
  mutate store(checkedAdd(load,param))+return load + view return load.

  Method ids are pinned to locked-dargo Counter package values until the
  official `gen_dapen_contract_function_method_id` hash is reimplemented.
  Slot layout matches observed dargo output (initialize/increment use
  sub_slot 1; view get uses sub_slot 0 — exact dargo quirk, not invented).
-/
import ProofForgeV2.Targets.Psy.LowerSemanticV1
import ProofForgeV2.Targets.Psy.ValidatePlanV1
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1

open ProofForgeV2
open ProofForgeV2.Targets.Psy
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

/-- Pinned method ids from locked-dargo Counter package (psy-node-aligned). -/
def pinnedMethodIdV1 (name : String) : Option UInt32 :=
  match name with
  | "initialize" => some 202172507
  | "increment" => some 1990357658
  | "get" => some 1459926901
  | "add" => none  -- Accumulator: fill when golden captured
  | "current" => none
  | _ => none

/-- Require pinned id for DPN-2; unknown names fail closed (extend pin table). -/
def requireMethodIdV1 (name : String) : CompileResult UInt32 :=
  match pinnedMethodIdV1 name with
  | some id => pure id
  | none =>
      planError s!"PSY-DPN-2: method_id not pinned for '{name}' \
(extend pinnedMethodIdV1 after dargo golden capture)"

private def bTrue : UInt64 := encodeIndexedId .bool 0

/-- View get: Constant + GetState(sub_slot 0) → output target 1. -/
def lowerViewLoadReturnV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN-2: only state field 0 supported in this slice"
  let methodId ← requireMethodIdV1 name
  -- dargo view path uses sub_slot_index 0 for Counter.count
  pure {
    name, methodId
    circuitInputs := #[]
    circuitOutputs := #[1]
    stateCommands := #[.getSelfUserCurrentContractStateSlotSingle 0]
    stateCommandResolutionIndices := #[1]
    assertions := #[]
    definitions := #[
      { dataType := .target, index := 0, opType := .constant, inputs := #[0] },
      { dataType := .target, index := 1, opType := .getStateCommandResultSingle, inputs := #[0] }
    ]
    events := #[]
  }

/-- initialize: store param 0 into field 0 (dargo sub_slot 1). -/
def lowerInitializeStoreParamV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN-2: only state field 0 supported in this slice"
  let methodId ← requireMethodIdV1 name
  pure {
    name, methodId
    circuitInputs := #[0]
    circuitOutputs := #[]
    stateCommands := #[
      .getSelfUserCurrentContractStateSlotSingle 1,
      .setContractStateSlotSingle bTrue 1 0
    ]
    stateCommandResolutionIndices := #[2, 3]
    assertions := #[]
    definitions := #[
      { dataType := .target, index := 0, opType := .inputTarget, inputs := #[0] },
      { dataType := .target, index := 1, opType := .constant, inputs := #[0] },
      { dataType := .bool, index := 0, opType := .constantTrue, inputs := #[1] }
    ]
    events := #[]
  }

/-- increment-shaped: store(checkedAdd(load,param)); return load. -/
def lowerCheckedAddStoreReturnV1 (name : String) (fieldIndex : Nat) :
    CompileResult FunctionCircuitDefV1 := do
  unless fieldIndex == 0 do
    planError "PSY-DPN-2: only state field 0 supported in this slice"
  let methodId ← requireMethodIdV1 name
  pure {
    name, methodId
    circuitInputs := #[0]
    circuitOutputs := #[4]
    stateCommands := #[
      .getSelfUserCurrentContractStateSlotSingle 1,
      .setContractStateSlotSingle bTrue 1 3,
      .getSelfUserCurrentContractStateSlotSingle 1
    ]
    stateCommandResolutionIndices := #[2, 5, 5]
    assertions := #[{
      left := encodeIndexedId .bool 1
      right := encodeIndexedId .bool 0
      message := "u64 add overflow"
    }]
    definitions := #[
      { dataType := .target, index := 0, opType := .inputTarget, inputs := #[0] },
      { dataType := .target, index := 1, opType := .constant, inputs := #[0] },
      { dataType := .bool, index := 0, opType := .constantTrue, inputs := #[1] },
      { dataType := .target, index := 2, opType := .getStateCommandResultSingle, inputs := #[0] },
      { dataType := .target, index := 3, opType := .add, inputs := #[2, 0] },
      { dataType := .bool, index := 1, opType := .gte, inputs := #[3, 2] },
      { dataType := .target, index := 4, opType := .getStateCommandResultSingle, inputs := #[2] }
    ]
    events := #[]
  }

/-- Classify a single PlanFunction into a DPN-2 template. -/
def lowerFunctionV1 (fn : PlanFunction) : CompileResult FunctionCircuitDefV1 := do
  match fn.body.toList with
  | [.returnValue (.stateLoad f)] =>
      lowerViewLoadReturnV1 fn.name f
  | [.store f (.param 0), .returnNone] =>
      lowerInitializeStoreParamV1 fn.name f
  | [.store f (.checkedAdd (.stateLoad f2) (.param 0)),
      .returnValue (.stateLoad f3)] => do
      unless f == f2 && f == f3 do
        planError "PSY-DPN-2: checkedAdd store/return field mismatch"
      lowerCheckedAddStoreReturnV1 fn.name f
  | _ =>
      planError s!"PSY-DPN-2: unsupported PlanFunction shape name='{fn.name}' \
body={fn.body.size} kind={repr fn.kind} (expand LowerPlanV1 for more ProgramV1 → DPN coverage)"

/-- Lower an entire Plan to a DPN package. Functions sorted by name (dargo order). -/
def lowerPlanToPackageV1 (plan : Plan) : CompileResult PackageV1 := do
  unless plan.stateFieldNames.size == 1 do
    planError s!"PSY-DPN-2: expected exactly one state field, got {plan.stateFieldNames.size}"
  let mut out : Array FunctionCircuitDefV1 := #[]
  for fn in plan.functions do
    let d ← lowerFunctionV1 fn
    out := out.push d
  -- Stable order by name (matches dargo package ordering for Counter).
  let sorted := out.qsort (fun a b => a.name < b.name)
  pure sorted

/-- Capability path: materialize Plan then DPN lower (avoids importing Psy façade). -/
def packageFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) :
    CompileResult PackageV1 := do
  let plan ← materializePlanFromCapabilityV1 capability
  validatePlan plan
  lowerPlanToPackageV1 plan

end ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
