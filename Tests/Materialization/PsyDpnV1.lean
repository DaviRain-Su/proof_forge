/-
  Tests.Materialization.PsyDpnV1 — PSY-DPN-1/2 schema + Counter golden + Plan lower.

  Pins:
    * OpType / DataType exact discriminants used by Counter
    * encodeIndexedId (dataType<<32)|index
    * golden parse → package structural equality with hand-built
    * encode round-trip
    * Examples/Counter product Plan → DPN package ≡ golden (DPN-2)
-/
import ProofForgeV2
import ProofForgeV2.Targets.Psy
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1
import ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1
import Tests.Language.ParserSession
import Tests.Compiler.ValidatedSourceV1Pipeline

namespace Tests.Materialization.PsyDpnV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets
open ProofForgeV2.Targets.Psy.Dpn.SchemaV1
open ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1
open ProofForgeV2.Targets.Psy.Dpn.LowerPlanV1

private def expect (cond : Bool) (message : String) : IO Unit :=
  unless cond do throw <| IO.userError message

private def liftResult {α : Type} : CompileResult α → IO α
  | .ok value => pure value
  | .error e => throw <| IO.userError e.render

def testOpTypeDiscriminants : IO Unit := do
  expect (OpTypeV1.inputTarget.toUInt16 == 0) "InputTarget=0"
  expect (OpTypeV1.constant.toUInt16 == 1) "Constant=1"
  expect (OpTypeV1.constantTrue.toUInt16 == 2) "ConstantTrue=2"
  expect (OpTypeV1.add.toUInt16 == 4) "Add=4"
  expect (OpTypeV1.gte.toUInt16 == 15) "Gte=15"
  expect (OpTypeV1.getStateCommandResultSingle.toUInt16 == 54)
    "GetStateCommandResultSingle=54"
  -- hole 39 must not map
  expect (OpTypeV1.ofUInt16? 39 |>.isNone) "op 39 is a hole"
  expect (OpTypeV1.ofUInt16? 54 == some .getStateCommandResultSingle)
    "ofUInt16 54"

def testEncodeIndexedId : IO Unit := do
  expect (encodeIndexedId .bool 0 == 4294967296) "bool#0"
  expect (encodeIndexedId .bool 1 == 4294967297) "bool#1"
  expect (encodeIndexedId .target 0 == 0) "target#0"
  match decodeIndexedId 4294967296 with
  | some (.bool, 0) => pure ()
  | other => throw <| IO.userError s!"decode bool#0 failed: {repr other}"

/-- Official dargo package JSON (field order may differ from Lean mkObj). -/
def testCounterGoldenDecode : IO Unit := do
  let goldenRaw ← IO.FS.readFile "testdata/golden/psy-dpn-v1/counter-package.v1.json"
  -- Golden is one JSON line; strip whitespace/newlines without Slice APIs.
  let golden := "".intercalate (goldenRaw.splitOn "\n")
  match parsePackage? golden with
  | none => throw <| IO.userError "failed to parse Counter DPN golden"
  | some pkg =>
      expect (pkg == counterPackageGoldenV1)
        "decoded dargo golden must equal hand-built counterPackageGoldenV1"
      expect (pkg.size == 3) "get + increment + initialize"
      expect (pkg[0]!.name == "get") "first method name-sorted"
      expect (pkg[1]!.name == "increment") "second method"
      expect (pkg[2]!.name == "initialize") "third method"
      expect (pkg[1]!.assertions.size == 1) "overflow assert present"
      expect (pkg[1]!.assertions[0]!.message == "u64 add overflow") "assert message"

/-- Encode → parse structural round-trip (ProofForge compact JSON key order). -/
def testCounterEncodeRoundTrip : IO Unit := do
  let encoded := encodePackageCompact counterPackageGoldenV1
  match parsePackage? encoded with
  | none => throw <| IO.userError s!"failed to parse our encode: {encoded}"
  | some pkg =>
      expect (pkg == counterPackageGoldenV1)
        "encodePackageCompact round-trip must preserve Counter package"

/-- PSY-DPN-2: product Plan for Examples/Counter lowers to golden package. -/
unsafe def testCounterPlanLowerEqualsGolden : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let src ← IO.FS.readFile "Examples/Counter.lean"
  let parsed ← liftResult (← session.selectProgramV1 src "<dpn-c>" "Examples.Counter" none)
  let compiled ← liftResult <| compileValidatedSourceV1 parsed
  let selection ← liftResult <| BuildSelectionV1.resolveBuildSelectionV1 TargetId.psy none
  let cap ← liftResult <| resolveEngineeringRequirementsV1 selection compiled
  let pkg ← liftResult <| packageFromCapabilityV1 cap
  expect (pkg == counterPackageGoldenV1)
    s!"Plan→DPN package must equal Counter golden (got {pkg.map (·.name)})"

unsafe def run : IO Unit := do
  testOpTypeDiscriminants
  testEncodeIndexedId
  testCounterGoldenDecode
  testCounterEncodeRoundTrip
  testCounterPlanLowerEqualsGolden
  IO.println "Tests.Materialization.PsyDpnV1: ok"

end Tests.Materialization.PsyDpnV1
