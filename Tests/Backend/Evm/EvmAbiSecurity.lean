/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
-/
import ProofForge.Backend.Evm.IR

namespace ProofForge.Tests.EvmAbiSecurity

open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def requireErrorContains {alpha : Type}
    (result : Except ProofForge.Backend.Evm.Validate.LowerError alpha)
    (expected label : String) : IO Unit :=
  match result with
  | .ok _ => throw <| IO.userError s!"{label}: expected failure containing `{expected}`"
  | .error err =>
      require (err.message.contains expected)
        s!"{label}: expected `{expected}`, got `{err.message}`"

def requireOk {alpha : Type}
    (result : Except ProofForge.Backend.Evm.Validate.LowerError alpha)
    (label : String) : IO Unit :=
  match result with
  | .ok _ => pure ()
  | .error err => throw <| IO.userError s!"{label}: {err.message}"

def requireOkValue {alpha : Type}
    (result : Except ProofForge.Backend.Evm.Validate.LowerError alpha)
    (label : String) : IO alpha :=
  match result with
  | .ok value => pure value
  | .error err => throw <| IO.userError s!"{label}: {err.message}"

def entrypointWithOverride
    (name : String) (type : ValueType) (override : String) : Entrypoint := {
  name
  selector? := some "00000000"
  params := #[("value", type)]
  paramAbiWords := #[some override]
  body := #[]
}

def moduleFor (entrypoint : Entrypoint) : Module := {
  name := "EvmAbiSecurityProbe"
  state := #[]
  entrypoints := #[entrypoint]
}

def planParams (entrypoint : Entrypoint) :=
  ProofForge.Backend.Evm.Lower.entrypointParamPlans (moduleFor entrypoint) entrypoint

def testValidScalarOverrideMatrix : IO Unit := do
  let valid : Array (ValueType × String) := #[
    (.u8, "uint8"),
    (.u32, "uint32"),
    (.u64, "uint64"),
    (.u128, "uint128"),
    (.bool, "bool"),
    (.hash, "uint256"),
    (.hash, "bytes32"),
    (.address, "address"),
    -- Source DSL compatibility carriers.
    (.u64, "address"),
    (.u64, "bytes4")
  ]
  for (type, override) in valid do
    requireOk (planParams (entrypointWithOverride "valid" type override))
      s!"valid `{type.name}` -> `{override}` override"

def testMismatchedAndDynamicOverridesFailClosed : IO Unit := do
  let invalid : Array (ValueType × String) := #[
    (.bytes, "address"),
    (.string, "bytes32"),
    (.fixedArray .u64 2, "address"),
    (.array .u64, "uint256"),
    (.u8, "uint32"),
    (.u32, "address"),
    (.u64, "uint256"),
    (.hash, "address"),
    (.bool, "uint8"),
    (.u64, "tuple")
  ]
  for (type, override) in invalid do
    requireErrorContains
      (planParams (entrypointWithOverride "invalid" type override))
      "incompatible EVM ABI override"
      s!"invalid `{type.name}` -> `{override}` override"

def testExtraAbiOverrideEntriesFailClosed : IO Unit := do
  let entrypoint : Entrypoint := {
    name := "extra_override"
    selector? := some "00000000"
    params := #[("value", .u64)]
    paramAbiWords := #[none, some "address"]
    body := #[]
  }
  requireErrorContains
    (planParams entrypoint)
    "has 2 ABI override entries for 1 parameter"
    "extra ABI override entry"

def testGeneratedPrefixIsReservedForParamsAndLocals : IO Unit := do
  let badParam : Entrypoint := {
    name := "bad_param"
    selector? := some "00000000"
    params := #[("__pf_receiver", .u64)]
    body := #[]
  }
  requireErrorContains
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan (moduleFor badParam))
    "starts with `__pf_`, which is reserved for generated EVM temporaries"
    "reserved parameter"

  let badLocal : Entrypoint := {
    name := "bad_local"
    selector? := some "00000000"
    body := #[.letBind "__pf_receiver" .u64 (.literal (.u64 1))]
  }
  requireErrorContains
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan (moduleFor badLocal))
    "starts with `__pf_`, which is reserved for generated EVM temporaries"
    "reserved local"

  let badLoop : Entrypoint := {
    name := "bad_loop"
    selector? := some "00000000"
    body := #[.boundedFor "__pf_i" 0 1 #[]]
  }
  requireErrorContains
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan (moduleFor badLoop))
    "starts with `__pf_`, which is reserved for generated EVM temporaries"
    "reserved loop index"

  let legacyGeneratedPrefix : Entrypoint := {
    name := "bad_legacy_generated_prefix"
    selector? := some "00000000"
    params := #[("__proof_forge_struct_value_field", .u64)]
    body := #[]
  }
  requireErrorContains
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan
      (moduleFor legacyGeneratedPrefix))
    "starts with `__proof_forge_`, which is reserved for generated EVM temporaries"
    "legacy generated parameter prefix"

def testGeneratedInlineNamesCannotCollideWithUserNames : IO Unit := do
  let scalarReturn : Entrypoint := {
    name := "scalar_return"
    selector? := some "00000001"
    params := #[("result", .u64)]
    returns := .u64
    body := #[.return (.local "result")]
  }
  let scalarPlan ← requireOkValue
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan (moduleFor scalarReturn))
    "scalar return generated-name plan"
  let scalarEntrypoint := scalarPlan.entrypoints[0]!
  require (scalarEntrypoint.params[0]!.localNames == #["result"])
    "source scalar parameter must retain its user-visible name"
  require (scalarEntrypoint.returns.localNames == #["__pf_result"])
    "scalar return local must use the reserved generated namespace"

  let dynamicCollision : Entrypoint := {
    name := "dynamic_collision"
    selector? := some "00000002"
    params := #[("payload", .bytes), ("payload__length", .u64)]
    body := #[]
  }
  let dynamicPlan ← requireOkValue
    (ProofForge.Backend.Evm.Lower.buildFullModulePlan (moduleFor dynamicCollision))
    "dynamic parameter generated-name plan"
  let dynamicEntrypoint := dynamicPlan.entrypoints[0]!
  require
    (dynamicEntrypoint.params[0]!.localNames ==
      #["__pf_param_payload_length", "__pf_param_payload_data_ptr"])
    "dynamic ABI expansion locals must use the reserved generated namespace"
  require
    (!dynamicEntrypoint.params[0]!.localNames.contains
      dynamicEntrypoint.params[1]!.localNames[0]!)
    "dynamic ABI expansion must not collide with another source parameter"

  let event := ProofForge.Backend.Evm.Plan.EventPlan.mk
    "CollisionEvent" "CollisionEvent(uint64)"
    #[ProofForge.Backend.Evm.Plan.EventFieldPlan.mk "value" .u64 false]
  let topicStatements :=
    ProofForge.Backend.Evm.ToYul.eventSignatureTopicStatements event
  let topicYul := topicStatements.foldl
    (fun acc stmt => acc ++ Lean.Compiler.Yul.Printer.printStatement 0 stmt)
    ""
  require (topicYul.contains "let __pf_event_topic0")
    "event topic temporary must use the reserved generated namespace"
  let indexedStatements ← requireOkValue
    (ProofForge.Backend.Evm.ToYul.eventIndexedTopicStatements
      (fun message => ({ message } : ProofForge.Backend.Evm.Validate.LowerError))
      (ProofForge.Backend.Evm.Plan.EventFieldPlan.mk "owner" .address true)
      0
      #[Lean.Compiler.Yul.Expr.num 7])
    "indexed event generated-name plan"
  let indexedYul := indexedStatements.foldl
    (fun acc stmt => acc ++ Lean.Compiler.Yul.Printer.printStatement 0 stmt)
    ""
  require (indexedYul.contains "let __pf_event_indexed_topic0")
    "indexed event temporary must use the reserved generated namespace"

  let storageStatements :=
    ProofForge.Backend.Evm.ToYul.storagePathWriteTargetStatements
      (Lean.Compiler.Yul.Expr.num 1)
      (.mapValuePresence (Lean.Compiler.Yul.Expr.num 2) (Lean.Compiler.Yul.Expr.num 3))
  let storageYul := storageStatements.foldl
    (fun acc stmt => acc ++ Lean.Compiler.Yul.Printer.printStatement 0 stmt)
    ""
  require (storageYul.contains "let __pf_storage_slot")
    "storage value temporary must use the reserved generated namespace"
  require (storageYul.contains "let __pf_storage_presence_slot")
    "storage presence temporary must use the reserved generated namespace"

def main : IO UInt32 := do
  testExtraAbiOverrideEntriesFailClosed
  testGeneratedPrefixIsReservedForParamsAndLocals
  testGeneratedInlineNamesCannotCollideWithUserNames
  testValidScalarOverrideMatrix
  testMismatchedAndDynamicOverridesFailClosed
  IO.println "evm-abi-security: ok"
  return 0

end ProofForge.Tests.EvmAbiSecurity

def main : IO UInt32 :=
  ProofForge.Tests.EvmAbiSecurity.main
