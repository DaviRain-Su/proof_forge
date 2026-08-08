/-
  ALEO-IR-1: Aleo Instructions SchemaV1 + TextCodecV1 + Counter golden.

  Covers:
  * schema id / Leo golden version pins
  * hand-built `counterProgramV1` encode ≡ locked-leo golden file bytes
  * golden decode ≡ hand-built structure
  * encode → decode structural round-trip
  * decode fail-closed on truncated / unknown opcode

  **Not** Plan→Instructions lower (ALEO-IR-2), snarkVM execute, prove/deploy.
-/
import ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
import ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1

namespace Tests.Materialization.AleoInstructionsV1

open ProofForgeV2.Targets.Aleo.Instructions.SchemaV1
open ProofForgeV2.Targets.Aleo.Instructions.TextCodecV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def goldenPath : System.FilePath :=
  "testdata/golden/aleo-instructions-v1/counter.compiled.aleo"

private def testPins : IO Unit := do
  expect (schemaIdV1 == "proof-forge.aleo-instructions.v1") "schema id"
  expect (goldenLeoVersionV1 == "4.0.2") "Leo golden version pin"
  expect (counterProgramV1.name == "counter.aleo") "counter program name"
  expect (counterProgramV1.items.size == 7)
    "2 mappings + initialize fn/final + increment fn/final + constructor"

private def testEncodeEqualsGolden : IO Unit := do
  expect (← goldenPath.pathExists) "Counter compiled.aleo golden must exist"
  let golden ← IO.FS.readFile goldenPath
  let encoded := encodeProgram counterProgramV1
  expect (encoded == golden)
    s!"hand-built encode must equal golden bytes\n--- encoded ---\n{encoded}\n--- golden ---\n{golden}"
  expect (encoded.length == 870) "golden size pin (Leo 4.0.2 product Counter)"

private def testGoldenDecodeEqualsHandBuilt : IO Unit := do
  let golden ← IO.FS.readFile goldenPath
  match decodeProgram? golden with
  | none => throw <| IO.userError "failed to decode Counter golden"
  | some prog =>
      expect (prog == counterProgramV1)
        "decoded golden must equal hand-built counterProgramV1"
      expect (prog.name == "counter.aleo") "program name"
      -- Spot-check structure: first mapping + constructor last.
      match prog.items[0]!, prog.items[6]! with
      | .mapping m, .constructor c =>
          expect (m.name == "pf_state_0") "first mapping"
          expect (c.body.size == 1) "constructor single assert"
      | _, _ => throw <| IO.userError "unexpected item kinds at ends"

private def testEncodeDecodeRoundTrip : IO Unit := do
  let encoded := encodeProgram counterProgramV1
  match decodeProgram? encoded with
  | none => throw <| IO.userError "encode→decode failed"
  | some prog =>
      expect (prog == counterProgramV1) "structural round-trip"
      expect (encodeProgram prog == encoded) "re-encode byte identity"

private def testDecodeFailClosed : IO Unit := do
  expect ((decodeProgram? "").isNone) "empty"
  expect ((decodeProgram? "program counter.aleo;\n\nmapping x:\n").isNone)
    "truncated mapping"
  -- Opcode without `into` / assert shape → fail closed
  expect ((decodeProgram?
      "program counter.aleo;\n\nfunction f:\n    mystery r0 r1;\n").isNone)
    "opcode without into / unknown shape"
  -- Missing semicolon on instruction
  expect ((decodeProgram?
      "program counter.aleo;\n\nfunction f:\n    input r0 as u64.public\n").isNone)
    "missing semicolon"
  -- Missing program header semicolon
  expect ((decodeProgram? "program counter.aleo\n").isNone)
    "header without semicolon"

/-- Structural counts for Counter (documentation pin for IR-2). -/
private def testCounterShape : IO Unit := do
  let p := counterProgramV1
  let mut mappings := 0
  let mut functions := 0
  let mut finals := 0
  let mut constructors := 0
  for item in p.items do
    match item with
    | .mapping _ => mappings := mappings + 1
    | .function _ => functions := functions + 1
    | .finalize _ => finals := finals + 1
    | .constructor _ => constructors := constructors + 1
  expect (mappings == 2) "mappings"
  expect (functions == 2) "functions"
  expect (finals == 2) "finalize blocks"
  expect (constructors == 1) "constructor"
  -- initialize finalize uses get.or_use + not + assert.eq + set×2
  match p.items[3]! with
  | .finalize f =>
      expect (f.name == "initialize") "finalize initialize"
      expect (f.body.size == 6) "initialize finalize body size"
  | _ => throw <| IO.userError "items[3] must be finalize initialize"

def run : IO Unit := do
  testPins
  testEncodeEqualsGolden
  testGoldenDecodeEqualsHandBuilt
  testEncodeDecodeRoundTrip
  testDecodeFailClosed
  testCounterShape
  IO.println "Tests.Materialization.AleoInstructionsV1: ok"

end Tests.Materialization.AleoInstructionsV1

/-- Allow `lake env lean --run Tests/Materialization/AleoInstructionsV1.lean`. -/
def main : IO Unit :=
  Tests.Materialization.AleoInstructionsV1.run
