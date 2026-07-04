import ProofForge.Backend.Evm.Plan
import ProofForge.Backend.Evm.ToYul
import ProofForge.Compiler.Yul.Printer
import ProofForge.IR.Examples.EvmContextProbe
import ProofForge.IR.Examples.EvmMapProbe
import ProofForge.IR.Examples.EvmTypedMapProbe
import ProofForge.Target.Capability

namespace ProofForge.Tests.EvmPlan

open ProofForge.IR
open ProofForge.Backend.Evm.Plan
open ProofForge.Target

def mapProbeModule : Module :=
  ProofForge.IR.Examples.EvmMapProbe.module

def typedMapProbeModule : Module :=
  ProofForge.IR.Examples.EvmTypedMapProbe.module

def mapProbePathKey : Expr :=
  ProofForge.IR.Examples.EvmMapProbe.pathKey

def mapProbeSeedKey : Expr :=
  ProofForge.IR.Examples.EvmMapProbe.seedKey

def mapProbeNestedOuterKey : Expr :=
  ProofForge.IR.Examples.EvmMapProbe.nestedOuterKey

def mapProbeNestedInnerKey : Expr :=
  ProofForge.IR.Examples.EvmMapProbe.nestedInnerKey

def typedMapProbeU32 (value : Nat) : Expr :=
  ProofForge.IR.Examples.EvmTypedMapProbe.u32 value

def typedMapProbeNestedMapPath (outer inner : Expr) : Array StoragePathSegment :=
  ProofForge.IR.Examples.EvmTypedMapProbe.nestedMapPath outer inner

def storagePairStruct : StructDecl := {
  name := "Pair"
  fields := #[
    { id := "x", type := .u64 },
    { id := "y", type := .u64 }
  ]
}

def storageSlotProbeModule : Module := {
  name := "StorageSlotProbe"
  structs := #[storagePairStruct]
  state := #[
    { id := "count", kind := .scalar, type := .u64 },
    { id := "values", kind := .array 3, type := .u64 },
    { id := "pairs", kind := .array 2, type := .structType "Pair" },
    { id := "after", kind := .scalar, type := .u64 }
  ]
  entrypoints := #[]
}

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireEqNat (actual expected : Nat) (message : String) : IO Unit :=
  require (actual == expected) s!"{message}: expected {expected}, got {actual}"

def requireSome {α : Type} (value : Option α) (message : String) : IO α :=
  match value with
  | some x => pure x
  | none => throw <| IO.userError message

def requireOk {α : Type} (value : Except PlanError α) (message : String) : IO α :=
  match value with
  | .ok x => pure x
  | .error err => throw <| IO.userError s!"{message}: {err.render}"

def requireOkString {α : Type} (value : Except String α) (message : String) : IO α :=
  match value with
  | .ok x => pure x
  | .error err => throw <| IO.userError s!"{message}: {err}"

def requireScalarSlot (plan : StorageSlotPlan) (expectedSlot : Nat) (message : String) : IO Unit := do
  match plan with
  | .scalarSlot slot => requireEqNat slot expectedSlot message
  | _ => throw <| IO.userError s!"{message}: expected scalar slot plan"

def requireMapValueSlot
    (plan : StorageSlotPlan)
    (expectedRootSlot expectedKeys : Nat)
    (message : String) : IO Unit := do
  match plan with
  | .mapValueSlot rootSlot keys => do
      requireEqNat rootSlot expectedRootSlot s!"{message}: root slot"
      requireEqNat keys.size expectedKeys s!"{message}: key count"
  | _ => throw <| IO.userError s!"{message}: expected map value slot plan"

def requireMapPresenceSlot
    (plan : StorageSlotPlan)
    (expectedRootSlot expectedKeys : Nat)
    (message : String) : IO Unit := do
  match plan with
  | .mapPresenceSlot rootSlot keys => do
      requireEqNat rootSlot expectedRootSlot s!"{message}: root slot"
      requireEqNat keys.size expectedKeys s!"{message}: key count"
  | _ => throw <| IO.userError s!"{message}: expected map presence slot plan"

def requireArraySlot
    (plan : StorageSlotPlan)
    (expectedRootSlot expectedLength : Nat)
    (message : String) : IO Unit := do
  match plan with
  | .arraySlot rootSlot length _ => do
      requireEqNat rootSlot expectedRootSlot s!"{message}: root slot"
      requireEqNat length expectedLength s!"{message}: length"
  | _ => throw <| IO.userError s!"{message}: expected array slot plan"

def requireStructArrayFieldSlot
    (plan : StorageSlotPlan)
    (expectedRootSlot expectedLength expectedFieldCount expectedFieldOffset : Nat)
    (message : String) : IO Unit := do
  match plan with
  | .structArrayFieldSlot rootSlot length fieldCount fieldOffset _ => do
      requireEqNat rootSlot expectedRootSlot s!"{message}: root slot"
      requireEqNat length expectedLength s!"{message}: length"
      requireEqNat fieldCount expectedFieldCount s!"{message}: field count"
      requireEqNat fieldOffset expectedFieldOffset s!"{message}: field offset"
  | _ => throw <| IO.userError s!"{message}: expected struct-array field slot plan"

def requireHelper (helpers : HelperSet) (helper : Helper) (message : String) : IO Unit :=
  require (HelperSet.contains helpers helper) message

def requireMissingHelper (helpers : HelperSet) (helper : Helper) (message : String) : IO Unit :=
  require (!HelperSet.contains helpers helper) message

def requireCapability (plan : ModulePlan) (capability : Capability) (message : String) : IO Unit :=
  require (plan.capabilities.any (fun existing => existing == capability)) message

def requireNoCapability (plan : ModulePlan) (capability : Capability) (message : String) : IO Unit :=
  require (!plan.capabilities.any (fun existing => existing == capability)) message

def testMapProbeLayout : IO Unit := do
  requireEqNat (← requireSome (stateSlot? mapProbeModule "before") "missing before slot") 0
    "EvmMapProbe.before slot"
  requireEqNat (← requireSome (stateSlot? mapProbeModule "balances") "missing balances slot") 1
    "EvmMapProbe.balances slot"
  requireEqNat (← requireSome (stateSlot? mapProbeModule "after") "missing after slot") 2
    "EvmMapProbe.after slot"
  let layout := storageLayout mapProbeModule
  let balances ← requireSome (layout.find? "balances") "missing balances layout plan"
  requireEqNat balances.slot 1 "EvmMapProbe.balances layout slot"
  requireEqNat balances.span 1 "EvmMapProbe.balances layout span"

def testScalarSlotPlan : IO Unit := do
  let before ← requireOk (scalarSlotPlan mapProbeModule "before") "scalar plan failed"
  requireScalarSlot before 0 "EvmMapProbe.before scalar slot"
  match scalarSlotPlan mapProbeModule "balances" with
  | .ok _ => throw <| IO.userError "map state must not produce a scalar slot plan"
  | .error err =>
      require (err.render == "EVM storage state 'balances' is not a scalar slot")
        "map-as-scalar diagnostic mismatch"

def testMapSlotPlans : IO Unit := do
  let singleValue ← requireOk
    (storagePathMapValueSlotPlan mapProbeModule "balances" #[.mapKey mapProbePathKey])
    "single map value plan failed"
  requireMapValueSlot singleValue 1 1 "single map value plan"
  requireHelper singleValue.requiredHelpers Helper.mapSlot "single map value plan must require map slot helper"
  requireMissingHelper singleValue.requiredHelpers Helper.mapPresenceSlot
    "single map value plan must not require presence helper"

  let nestedPath := #[.mapKey mapProbeNestedOuterKey, .mapKey mapProbeNestedInnerKey]
  let nestedValue ← requireOk
    (storagePathMapValueSlotPlan mapProbeModule "balances" nestedPath)
    "nested map value plan failed"
  requireMapValueSlot nestedValue 1 2 "nested map value plan"
  requireHelper nestedValue.requiredHelpers Helper.mapSlot "nested map value plan must require map slot helper"

  let nestedPresence ← requireOk
    (storagePathMapPresenceSlotPlan mapProbeModule "balances" nestedPath)
    "nested map presence plan failed"
  requireMapPresenceSlot nestedPresence 1 2 "nested map presence plan"
  requireHelper nestedPresence.requiredHelpers Helper.mapPresenceSlot
    "nested map presence plan must require presence helper"
  requireHelper nestedPresence.requiredHelpers Helper.mapSlot
    "nested map presence plan must require parent map slot helper"

  match storagePathMapValueSlotPlan mapProbeModule "balances" #[.mapKey mapProbeSeedKey, .field "amount"] with
  | .ok _ => throw <| IO.userError "mixed map/aggregate path must not produce a map slot plan"
  | .error err =>
      require
        (err.render == "EVM plan supports map storage paths only as one or more mapKey segments")
        "mixed map/aggregate path diagnostic mismatch"

def testTypedMapProbeLayout : IO Unit := do
  requireEqNat (← requireSome (stateSlot? typedMapProbeModule "scores") "missing scores slot") 0
    "EvmTypedMapProbe.scores slot"
  requireEqNat (← requireSome (stateSlot? typedMapProbeModule "flags") "missing flags slot") 1
    "EvmTypedMapProbe.flags slot"
  requireEqNat (← requireSome (stateSlot? typedMapProbeModule "roots") "missing roots slot") 2
    "EvmTypedMapProbe.roots slot"
  requireEqNat (← requireSome (stateSlot? typedMapProbeModule "after") "missing after slot") 3
    "EvmTypedMapProbe.after slot"

  let typedNested ← requireOk
    (storagePathMapValueSlotPlan
      typedMapProbeModule
      "scores"
      (typedMapProbeNestedMapPath (typedMapProbeU32 9) (typedMapProbeU32 10)))
    "typed nested map value plan failed"
  requireMapValueSlot typedNested 0 2 "typed nested map value plan"

def lowerSlotTestExpr : Expr → Except String Lean.Compiler.Yul.Expr
  | .literal (.u64 value) => .ok (Lean.Compiler.Yul.Expr.num value)
  | .local name => .ok (Lean.Compiler.Yul.Expr.id name)
  | _ => .error "unsupported slot test expression"

def renderSlotPlan (plan : StorageSlotPlan) : Except String String := do
  let expr ← ProofForge.Backend.Evm.ToYul.storageSlotExpr id lowerSlotTestExpr plan
  .ok (Lean.Compiler.Yul.Printer.printExpr expr)

def testArraySlotPlans : IO Unit := do
  requireEqNat (← requireSome (stateSlot? storageSlotProbeModule "count") "missing count slot") 0
    "StorageSlotProbe.count slot"
  requireEqNat (← requireSome (stateSlot? storageSlotProbeModule "values") "missing values slot") 1
    "StorageSlotProbe.values slot"
  requireEqNat (← requireSome (stateSlot? storageSlotProbeModule "pairs") "missing pairs slot") 4
    "StorageSlotProbe.pairs slot"
  requireEqNat (← requireSome (stateSlot? storageSlotProbeModule "after") "missing after slot") 8
    "StorageSlotProbe.after slot"

  let arrayPlan ← requireOk
    (arraySlotPlan storageSlotProbeModule "values" (.local "idx"))
    "array slot plan failed"
  requireArraySlot arrayPlan 1 3 "values array slot plan"
  requireHelper arrayPlan.requiredHelpers Helper.arraySlot
    "array slot plan must require array slot helper"
  let arrayExpr ← requireOkString (renderSlotPlan arrayPlan) "array slot ToYul lowering failed"
  require (arrayExpr == "__proof_forge_array_slot(1, 3, idx)")
    s!"array slot ToYul expression mismatch: {arrayExpr}"

  let structArrayPlan ← requireOk
    (structArrayFieldSlotPlan storageSlotProbeModule "pairs" (.local "idx") "y")
    "struct-array slot plan failed"
  requireStructArrayFieldSlot structArrayPlan 4 2 2 1 "pairs.y struct-array slot plan"
  requireHelper structArrayPlan.requiredHelpers Helper.structArraySlot
    "struct-array field slot plan must require struct-array slot helper"
  let structArrayExpr ← requireOkString (renderSlotPlan structArrayPlan) "struct-array slot ToYul lowering failed"
  require (structArrayExpr == "__proof_forge_struct_array_slot(4, 2, 2, 1, idx)")
    s!"struct-array slot ToYul expression mismatch: {structArrayExpr}"

def testModulePlanCapabilities : IO Unit := do
  let plan ← requireOk (buildModulePlan mapProbeModule) "EVM module plan failed"
  require (plan.name == mapProbeModule.name) "module plan name mismatch"
  require (plan.targetPlan.targetId == "evm") "module plan target must be evm"
  requireCapability plan .storageScalar "EVM module plan missing storage.scalar"
  requireCapability plan .storageMap "EVM module plan missing storage.map"
  requireCapability plan .assertions "EVM module plan missing assertions.check"
  requireNoCapability plan .storagePda "EVM module plan must not claim storage.pda"
  requireNoCapability plan .crosscallCpi "EVM module plan must not claim crosscall.cpi"
  requireHelper plan.helpers Helper.mapSlot "EVM module plan missing map slot helper"
  requireHelper plan.helpers Helper.mapPresenceSlot "EVM module plan missing map presence helper"
  requireHelper plan.helpers Helper.mapWrite "EVM module plan missing map write helper"
  requireHelper plan.helpers Helper.mapSetReturn "EVM module plan missing map set-return helper"
  require (plan.mapAssignOps.any (fun op => op == .add))
    "EVM module plan missing map assign-op helper requirement"
  let balances ← requireSome (plan.storage.find? "balances") "module plan missing balances storage"
  requireEqNat balances.slot 1 "module plan balances slot"

def testWrongTargetPlanRejected : IO Unit := do
  let wrongTargetPlan : CapabilityPlan := {
    targetId := "solana-sbpf-asm"
    calls := #[CapabilityCall.fromCapability .storageScalar]
  }
  match buildModulePlanWithTargetPlan mapProbeModule wrongTargetPlan with
  | .ok _ => throw <| IO.userError "EVM module plan must reject a non-EVM target plan"
  | .error err =>
      require
        (err.render == "EVM module plan requires target `evm`, got `solana-sbpf-asm`")
        "wrong-target diagnostic mismatch"

def testContextOpsPlan : IO Unit := do
  let plan ← requireOk (buildModulePlan ProofForge.IR.Examples.EvmContextProbe.module) "EVM context module plan failed"
  let fieldNames := plan.contextOps.map (fun op => op.field.name)
  require (fieldNames.contains "userId") "contextOps must include userId"
  require (fieldNames.contains "timestamp") "contextOps must include timestamp"
  require (fieldNames.contains "origin") "contextOps must include origin"
  require (fieldNames.contains "blockHash") "contextOps must include blockHash"
  require (fieldNames.contains "coinbase") "contextOps must include coinbase"
  requireEqNat plan.contextOps.size 12 "EvmContextProbe contextOps count"

def main : IO UInt32 := do
  testMapProbeLayout
  testScalarSlotPlan
  testMapSlotPlans
  testTypedMapProbeLayout
  testArraySlotPlans
  testModulePlanCapabilities
  testWrongTargetPlanRejected
  testContextOpsPlan
  IO.println "evm-plan: ok"
  return 0

end ProofForge.Tests.EvmPlan

def main : IO UInt32 :=
  ProofForge.Tests.EvmPlan.main
