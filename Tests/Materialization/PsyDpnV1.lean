/-
  Tests.Materialization.PsyDpnV1 — PSY-DPN-1 schema + Counter golden.

  Pins:
    * OpType / DataType exact discriminants used by Counter
    * encodeIndexedId (dataType<<32)|index
    * hand-built Counter package compact JSON equals committed golden
    * golden parse → package structural equality with hand-built
-/
import ProofForgeV2.Targets.Psy.Dpn.SchemaV1
import ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

namespace Tests.Materialization.PsyDpnV1

open ProofForgeV2.Targets.Psy.Dpn.SchemaV1
open ProofForgeV2.Targets.Psy.Dpn.JsonCodecV1

private def expect (cond : Bool) (message : String) : IO Unit :=
  unless cond do throw <| IO.userError message

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
      expect (pkg.size == 2) "initialize + increment"
      expect (pkg[0]!.name == "initialize") "first method"
      expect (pkg[1]!.name == "increment") "second method"
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

def run : IO Unit := do
  testOpTypeDiscriminants
  testEncodeIndexedId
  testCounterGoldenDecode
  testCounterEncodeRoundTrip
  IO.println "Tests.Materialization.PsyDpnV1: ok"

end Tests.Materialization.PsyDpnV1
