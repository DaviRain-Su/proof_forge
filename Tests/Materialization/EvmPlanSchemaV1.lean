/-
  M4 engineering EVM Plan schema/digest + TargetIR structural validation suite.
  **Not** formal TASK-D4 / formal TargetIR / formal Anvil differential.
-/
import ProofForgeV2
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Evm
import ProofForgeV2.Targets.Evm.PlanSchemaV1
import ProofForgeV2.Targets.Evm.ValidateIRV1
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.EvmPlanSchemaV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Evm

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def liftExcept (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def digestWire (d : Digest) : IO String :=
  liftExcept "renderDigest" (renderDigest d)

private def expectDigestDiff (label : String) (base alt : Digest) : IO Unit :=
  expect (!(base.bytes == alt.bytes)) s!"{label}: digest must change"

private def minimalPlan : Plan := {
  objectName := "Mut"
  runtimeObjectName := "__proof_forge_runtime"
  storageLayout := #[{ sourceId := 0, name := "count", slot := 0 }]
  events := #[]
  errors := #[]
  constructor := some {
    params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
    stores := #[{ slot := 0, value := .param 0 }]
  }
  entries := #[{
    name := "get"
    selector := Targets.Evm.Keccak.selector "get" #[]
    params := #[]
    mutability := .view
    body := #[.returnValue (.storageLoad 0)]
  }]
  fns := #[]
}

private unsafe def compileCounter : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<evm-plan-schema-counter>"
    Examples.counterModuleNameV1 none)
  liftResult "compile Counter" (Compiler.compileValidatedSourceV1 source)

private unsafe def planCounter : IO Plan := do
  let compiled ← compileCounter
  let selection ← liftResult "select evm" (resolveBuildSelectionV1 TargetId.evm none)
  let capability ← liftResult "resolve"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  liftResult "plan" (planFromCapability capability)

private def testDomain : IO Unit := do
  expect (engineeringEvmPlanDomainV1 == "pf.evm-plan.engineering.v1") "domain"
  expect (engineeringEvmPlanDomainV1.endsWith ".engineering.v1") "suffix"
  match validateProfileIdValue engineeringEvmPlanDomainV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"domain grammar: {e}"

private def testMinimalPlanDeterminism : IO Unit := do
  match validatePlan minimalPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"minimal plan: {e.render}"
  let b1 ← liftExcept "e1" (encodeEngineeringEvmPlanBytesV1 minimalPlan)
  let b2 ← liftExcept "e2" (encodeEngineeringEvmPlanBytesV1 minimalPlan)
  expect (b1 == b2) "encode determinism"
  expect (b1.size > 0) "nonempty"
  let d1 ← liftExcept "d1" (engineeringEvmPlanDigestV1 minimalPlan)
  let d2 ← liftExcept "d2" (engineeringEvmPlanDigestV1 minimalPlan)
  expect (d1.algorithm == .sha256 && d1.bytes.size == 32) "sha256"
  expect (d1.bytes == d2.bytes) "digest determinism"
  let w ← digestWire d1
  expect (w.startsWith "sha256:") "wire prefix"

private def testTamperMatrix : IO Unit := do
  let base ← liftExcept "base" (engineeringEvmPlanDigestV1 minimalPlan)
  expectDigestDiff "objectName" base
    (← liftExcept "n" (engineeringEvmPlanDigestV1 { minimalPlan with objectName := "MutX" }))
  expectDigestDiff "runtime" base
    (← liftExcept "r" (engineeringEvmPlanDigestV1 { minimalPlan with runtimeObjectName := "__rt_x" }))
  expectDigestDiff "storage" base
    (← liftExcept "s" (engineeringEvmPlanDigestV1 {
      minimalPlan with storageLayout := #[{ sourceId := 0, name := "total", slot := 0 }] }))
  expectDigestDiff "entry" base
    (← liftExcept "e" (engineeringEvmPlanDigestV1 {
      minimalPlan with entries := #[{
        minimalPlan.entries[0]! with body := #[.returnValue (.literal 0)] }] }))
  expectDigestDiff "ctor" base
    (← liftExcept "c" (engineeringEvmPlanDigestV1 {
      minimalPlan with constructor := some {
        params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
        stores := #[{ slot := 0, value := .literal 7 }] } }))
  expectDigestDiff "mut" base
    (← liftExcept "m" (engineeringEvmPlanDigestV1 {
      minimalPlan with entries := #[{
        minimalPlan.entries[0]! with mutability := .nonpayable }] }))
  expectDigestDiff "no ctor" base
    (← liftExcept "nc" (engineeringEvmPlanDigestV1 { minimalPlan with constructor := none }))
  expectDigestDiff "event" base
    (← liftExcept "ev" (engineeringEvmPlanDigestV1 {
      minimalPlan with events := #[{ name := "Moved", fieldCount := 1 }] }))

private unsafe def testProductPathRecompute : IO Unit := do
  let plan ← planCounter
  expect (plan.objectName == "Counter") "Counter name"
  let d1 ← liftExcept "d1" (engineeringEvmPlanDigestV1 plan)
  let bytes ← liftExcept "enc" (encodeEngineeringEvmPlanBytesV1 plan)
  let recomputed ← liftExcept "dom"
    (domainSeparatedSha256 engineeringEvmPlanDomainV1 bytes)
  expect (d1.bytes == recomputed.bytes) "recompute"
  let plan2 ← planCounter
  let d2 ← liftExcept "d2" (engineeringEvmPlanDigestV1 plan2)
  expect (d1.bytes == d2.bytes) "two mints"
  let b1 ← liftExcept "b1" (encodeEngineeringEvmPlanBytesV1 plan)
  let b2 ← liftExcept "b2" (encodeEngineeringEvmPlanBytesV1 plan2)
  expect (b1 == b2) "bytes equal"

private unsafe def testIrValidationPositive : IO Unit := do
  let compiled ← compileCounter
  let selection ← liftResult "sel" (resolveBuildSelectionV1 TargetId.evm none)
  let capability ← liftResult "cap"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let ir ← liftResult "ir" (irFromCapability capability)
  match validateIR ir with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"product IR: {e.render}"
  match validateEvmTargetIRV1 ir.objectName ir.yul ir.abi with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"parts: {e.render}"
  expect (ir.objectName == "Counter") "name"
  let files ← liftResult "build" (buildFromCapability capability)
  expect (files.size == 2) "two files"
  expect (files.any (·.path.endsWith ".yul")) "yul"
  expect (files.any (·.path.endsWith ".abi.json")) "abi"

private def testIrValidationNegatives : IO Unit := do
  let goodName := "Mut"
  let goodYul :=
    "object \"Mut\" {\n  code {\n  }\n  object \"__proof_forge_runtime\" {\n    code {\n" ++
    "      if callvalue() { revert(0, 0) }\n" ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    "      default { revert(0, 0) }\n    }\n  }\n}\n"
  let goodAbi := "[]\n"
  match validateEvmTargetIRV1 goodName goodYul goodAbi with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"scaffold: {e.render}"
  match validateEvmTargetIRV1 "" goodYul goodAbi with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "empty name"
  match validateEvmTargetIRV1 goodName "" goodAbi with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "empty yul"
  match validateEvmTargetIRV1 goodName goodYul "" with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "empty abi"
  -- Nested-slot .fieldDiv marker must be rejected at IR validation
  -- (fail closed instead of silently emitting a multiply).
  let markerYul := goodYul ++ "      let x := pf_unsupported_nested_field_div()\n"
  match validateEvmTargetIRV1 goodName markerYul goodAbi with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "nested fieldDiv marker accepted"
  match validateEvmTargetIRV1 "Other" goodYul goodAbi with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "name mismatch"
  let noSwitch := goodYul.replace "switch shr(224, calldataload(0))\n" ""
  match validateEvmTargetIRV1 goodName noSwitch goodAbi with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "missing switch"
  match validateEvmTargetIRV1 goodName (goodYul ++ "{\n") goodAbi with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "unbalanced"
  match validateEvmTargetIRV1 goodName goodYul "{\"type\":\"function\"}" with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "non-array abi"
  match validateEvmTargetIRV1 goodName goodYul "[{}" with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "abi brackets"
  let badIr : IR := { objectName := goodName, yul := noSwitch, abi := goodAbi }
  match validateIR badIr with
  | .error (.planInvariant .evm _) => pure ()
  | _ => throw <| IO.userError "validateIR reject"

private def testWirePresence : IO Unit := do
  let hits ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "validateIR|validateEvmTargetIRV1",
      "ProofForgeV2/Targets/Evm/EmitIRV1.lean"]
  }
  expect (hits.exitCode == 0 && hits.stdout.contains "validateIR")
    s!"wire: {hits.stdout}"
  let schema ← IO.Process.output {
    cmd := "rg"
    args := #["-n",
      "^def encodeEngineeringEvmPlanBytesV1\\b|^def engineeringEvmPlanDigestV1\\b|^def engineeringEvmPlanDomainV1\\b",
      "ProofForgeV2/Targets/Evm/PlanSchemaV1.lean"]
  }
  expect (schema.exitCode == 0 &&
      schema.stdout.contains "encodeEngineeringEvmPlanBytesV1" &&
      schema.stdout.contains "engineeringEvmPlanDigestV1")
    s!"schema surface: {schema.stdout}"

/-- N2b-EVM: Field Expr tags are additive; Field plan digest is deterministic
    and distinct from a UInt64-only plan with the same names. -/
private unsafe def testFieldPlanDigestDeterminism : IO Unit := do
  let fieldPlan : Plan := {
    objectName := "F"
    runtimeObjectName := "__proof_forge_runtime"
    storageLayout := #[{ sourceId := 0, name := "acc", slot := 0, byteWidth := 32 }]
    events := #[]
    errors := #[]
    constructor := some {
      params := #[{ sourceId := 0, name := "i", wordIndex := 0, byteWidth := 32 }]
      stores := #[{ slot := 0, value := .param 0, byteWidth := 32 }]
    }
    entries := #[{
      name := "add"
      selector := Targets.Evm.Keccak.selector "add" #["uint256"]
      params := #[{ sourceId := 0, name := "d", wordIndex := 0, byteWidth := 32 }]
      mutability := .nonpayable
      body := #[
        .store {
          slot := 0
          value := .fieldAdd (.fieldStorageLoad 0) (.param 0)
          byteWidth := 32
        },
        .returnValue (.fieldStorageLoad 0)
      ]
      resultKind := .field
    }, {
      name := "div"
      selector := Targets.Evm.Keccak.selector "div" #["uint256"]
      params := #[{ sourceId := 0, name := "d", wordIndex := 0, byteWidth := 32 }]
      mutability := .nonpayable
      body := #[
        .returnValue (.fieldDiv (.fieldStorageLoad 0) (.param 0))
      ]
      resultKind := .field
    }, {
      name := "neg"
      selector := Targets.Evm.Keccak.selector "neg" #["uint256"]
      params := #[{ sourceId := 0, name := "x", wordIndex := 0, byteWidth := 32 }]
      mutability := .nonpayable
      body := #[.returnValue (.fieldNeg (.param 0))]
      resultKind := .field
    }]
    fns := #[]
  }
  match validatePlan fieldPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"field plan: {e.render}"
  let b1 ← liftExcept "e1" (encodeEngineeringEvmPlanBytesV1 fieldPlan)
  let b2 ← liftExcept "e2" (encodeEngineeringEvmPlanBytesV1 fieldPlan)
  expect (b1 == b2) "Field plan encode determinism"
  let d1 ← liftExcept "d1" (engineeringEvmPlanDigestV1 fieldPlan)
  let d2 ← liftExcept "d2" (engineeringEvmPlanDigestV1 fieldPlan)
  expect (d1.bytes == d2.bytes) "Field plan digest determinism"
  -- Historical UInt64-only minimal plan encoding must remain unchanged shape
  -- (Field uses new Expr tags 42..47; Counter product digest still recomputes).
  let uintPlan := minimalPlan
  let ub ← liftExcept "u" (encodeEngineeringEvmPlanBytesV1 uintPlan)
  expect (!(ub == b1)) "Field plan bytes must differ from UInt64 minimal plan"
  -- Counter product path still digests deterministically after Field tags.
  let counter ← planCounter
  let cd1 ← liftExcept "cd1" (engineeringEvmPlanDigestV1 counter)
  let cd2 ← liftExcept "cd2" (engineeringEvmPlanDigestV1 counter)
  expect (cd1.bytes == cd2.bytes) "Counter digest still deterministic with Field tags present"


/-- EvmIndex: new Expr tags 48..50 must digest deterministically and leave
    historical Field/UInt64 encodings distinct when absent. -/
private unsafe def testArrayIndexPlanDigestDeterminism : IO Unit := do
  let arrayPlan : Plan := {
    objectName := "A"
    runtimeObjectName := "__proof_forge_runtime"
    storageLayout := #[
      { sourceId := 0, name := "s0", slot := 0 },
      { sourceId := 1, name := "s1", slot := 1 },
      { sourceId := 2, name := "s2", slot := 2 }
    ]
    events := #[]
    errors := #[]
    constructor := some {
      params := #[]
      stores := #[
        { slot := 0, value := .literal 0 },
        { slot := 1, value := .literal 0 },
        { slot := 2, value := .literal 0 }
      ]
    }
    entries := #[{
      name := "getAt"
      selector := Targets.Evm.Keccak.selector "getAt" #["uint64"]
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      mutability := .view
      body := #[.returnValue
        (.indexedStorageLoad 0 3 (.param 0) 8)]
      resultKind := .uint64
    }, {
      name := "pick"
      selector := Targets.Evm.Keccak.selector "pick" #["uint64"]
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      mutability := .view
      body := #[.returnValue
        (.arrayIndexGet (.param 0)
          #[.storageLoad 0, .storageLoad 1, .storageLoad 2])]
      resultKind := .uint64
    }, {
      name := "guarded"
      selector := Targets.Evm.Keccak.selector "guarded" #["uint64"]
      params := #[{ sourceId := 0, name := "i", wordIndex := 0 }]
      mutability := .view
      body := #[.returnValue
        (.boundsCheckedIndex (.param 0) 3)]
      resultKind := .uint64
    }]
    fns := #[]
  }
  match validatePlan arrayPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"array plan: {e.render}"
  let b1 ← liftExcept "e1" (encodeEngineeringEvmPlanBytesV1 arrayPlan)
  let b2 ← liftExcept "e2" (encodeEngineeringEvmPlanBytesV1 arrayPlan)
  expect (b1 == b2) "Array-index plan encode determinism"
  let d1 ← liftExcept "d1" (engineeringEvmPlanDigestV1 arrayPlan)
  let d2 ← liftExcept "d2" (engineeringEvmPlanDigestV1 arrayPlan)
  expect (d1.bytes == d2.bytes) "Array-index plan digest determinism"
  let fieldOnly : Plan := {
    objectName := "F"
    runtimeObjectName := "__proof_forge_runtime"
    storageLayout := #[{ sourceId := 0, name := "acc", slot := 0, byteWidth := 32 }]
    events := #[]
    errors := #[]
    constructor := none
    entries := #[{
      name := "g"
      selector := Targets.Evm.Keccak.selector "g" #[]
      params := #[]
      mutability := .view
      body := #[.returnValue (.fieldStorageLoad 0)]
      resultKind := .field
    }]
    fns := #[]
  }
  let fb ← liftExcept "f" (encodeEngineeringEvmPlanBytesV1 fieldOnly)
  expect (!(fb == b1)) "Array-index plan bytes must differ from Field plan"
  let counter ← planCounter
  let cd1 ← liftExcept "cd1" (engineeringEvmPlanDigestV1 counter)
  let cd2 ← liftExcept "cd2" (engineeringEvmPlanDigestV1 counter)
  expect (cd1.bytes == cd2.bytes) "Counter digest still deterministic with Array tags present"

/-- Tag-11 storeAtomic is in the engineering plan wire; distinct from two sequential stores. -/
private unsafe def testStoreAtomicPlanDigest : IO Unit := do
  let atomicPlan : Plan := {
    objectName := "At"
    runtimeObjectName := "__proof_forge_runtime"
    storageLayout := #[
      { sourceId := 0, name := "a0", slot := 0 },
      { sourceId := 1, name := "a1", slot := 1 }
    ]
    events := #[]
    errors := #[]
    constructor := none
    entries := #[{
      name := "set"
      selector := Targets.Evm.Keccak.selector "set" #["uint64"]
      params := #[{ sourceId := 0, name := "v", wordIndex := 0 }]
      mutability := .nonpayable
      body := #[
        .storeAtomic #[
          { slot := 0, value := .param 0 },
          { slot := 1, value := .storageLoad 1 }
        ],
        .returnValue (.storageLoad 0)
      ]
      resultKind := .uint64
    }]
    fns := #[]
  }
  match validatePlan atomicPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"storeAtomic plan must validate: {e.render}"
  let d1 ← liftExcept "a1" (engineeringEvmPlanDigestV1 atomicPlan)
  let d2 ← liftExcept "a2" (engineeringEvmPlanDigestV1 atomicPlan)
  expect (d1.bytes == d2.bytes) "storeAtomic plan digest determinism"
  let sequentialPlan : Plan := {
    atomicPlan with
    entries := #[{
      atomicPlan.entries[0]! with body := #[
        .store { slot := 0, value := .param 0 },
        .store { slot := 1, value := .storageLoad 1 },
        .returnValue (.storageLoad 0)
      ]
    }]
  }
  match validatePlan sequentialPlan with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"sequential plan: {e.render}"
  let ds ← liftExcept "seq" (engineeringEvmPlanDigestV1 sequentialPlan)
  expect (!(d1.bytes == ds.bytes))
    "storeAtomic plan digest must differ from sequential scalar stores"
  -- Counter product path still digests without storeAtomic tag pollution.
  let counter ← planCounter
  let cd ← liftExcept "cd" (engineeringEvmPlanDigestV1 counter)
  expect (cd.bytes.size == 32) "Counter digest remains 32-byte sha256"

unsafe def run : IO Unit := do
  testDomain
  testMinimalPlanDeterminism
  testTamperMatrix
  testProductPathRecompute
  testIrValidationPositive
  testIrValidationNegatives
  testWirePresence
  testFieldPlanDigestDeterminism
  testArrayIndexPlanDigestDeterminism
  testStoreAtomicPlanDigest
  IO.println "Tests.Materialization.EvmPlanSchemaV1: ok"

end Tests.Materialization.EvmPlanSchemaV1
