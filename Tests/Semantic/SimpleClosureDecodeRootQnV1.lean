/-
  Tests.Semantic.SimpleClosureDecodeRootQnV1 — B-SC-DEC root tag + QN leaf.

  Kernel: expectTag from FieldsOk / encodeTagged nine-field body.
  Runtime: demo + unicode field-path → expectTag after magic + decodeQualifiedName.

  No axiom / sorry / native_decide.
-/
import ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common

namespace Tests.Semantic.SimpleClosureDecodeRootQnV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.SimpleClosureDecodeRootQnV1
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Kernel: tag constants + expectTag mid-offset -/

theorem tag_size_kernel : semanticProgramDataTagV1.toUTF8.size = 20 :=
  tag_utf8_size

theorem header_size_kernel :
    (taggedHeaderBytesV1 semanticProgramDataTagV1 9).size =
      semanticProgramDataHeaderSizeV1 :=
  header_size

theorem expectTag_empty_mid :
    expectTag "SemanticProgram.Data" 9
        ⟨taggedHeaderBytesV1 semanticProgramDataTagV1 9, 0, 1⟩ =
      .ok ((),
        ⟨taggedHeaderBytesV1 semanticProgramDataTagV1 9,
          semanticProgramDataHeaderSizeV1, 1⟩) := by
  have h := expectTag_data_midV1 ByteArray.empty ByteArray.empty 1
  simpa [ByteArray.append_empty] using h

theorem expectTag_demo_fields_ok
    (b : ByteArray)
    (hfields : encodeSimpleClosureDataFieldsV1 demoParamsV1 = .ok b) :
    expectTag "SemanticProgram.Data" 9
        ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, 1⟩ =
      .ok ((),
        ⟨b,
          (encodeMagicPrefix semanticProgramMagicV1).size +
            semanticProgramDataHeaderSizeV1, 1⟩) :=
  expectTag_of_simpleClosure_fields_ok demoParamsV1 b hfields 1

theorem demo_tail_size : demoParamsV1.qnTail.size = 1 := by decide

/-! ### Runtime: demo + unicode -/

private def checkExpectTagQn (p : SimpleClosureParamsV1) (label : String) : IO Unit := do
  match encodeSimpleClosureDataFieldsV1 p with
  | .error e => throw <| IO.userError s!"{label}: fields encode failed: {repr e}"
  | .ok b =>
      let magicSz := (encodeMagicPrefix semanticProgramMagicV1).size
      -- expectTag after magic
      match expectTag "SemanticProgram.Data" 9 ⟨b, magicSz, 1⟩ with
      | .error e => throw <| IO.userError s!"{label}: expectTag failed: {repr e}"
      | .ok ((), c) =>
          expect (c.offset == magicSz + semanticProgramDataHeaderSizeV1)
            s!"{label}: after-header offset"
          expect (c.nesting == 1) s!"{label}: nesting"
          -- decodeQualifiedName at after-header
          match decodeQualifiedName c with
          | .error e =>
              throw <| IO.userError s!"{label}: decodeQualifiedName failed: {repr e}"
          | .ok (qn, c') =>
              let want := (materializeSimpleClosureDataV1 p).qualifiedName
              expect (qn == want) s!"{label}: QN == materialize"
              expect (c'.offset > c.offset) s!"{label}: QN advanced cursor"
              -- types field should start next
              expect (c'.input == b) s!"{label}: same input"

def run : IO Unit := do
  -- Kernel surface: empty mid expectTag
  match expectTag "SemanticProgram.Data" 9
      ⟨taggedHeaderBytesV1 semanticProgramDataTagV1 9, 0, 1⟩ with
  | .error e => throw <| IO.userError s!"kernel expectTag empty: {repr e}"
  | .ok ((), c) =>
      expect (c.offset == 26) "kernel after-header = 26"
  checkExpectTagQn demoParamsV1 "demo"
  checkExpectTagQn unicodeLegalParamsV1 "unicode"
  -- Demo QN components
  let left := ByteArray.empty
  let right := ByteArray.empty
  match decodeArray 256 decodeString
      ⟨left ++ qualifiedNamePayloadV1 demoParamsV1 ++ right, 0, 1⟩ with
  | .error e => throw <| IO.userError s!"demo QN array: {repr e}"
  | .ok (comps, _) =>
      expect (comps == #["Module", "Prog"]) "demo QN comps"
  IO.println "Tests.Semantic.SimpleClosureDecodeRootQnV1: ok"
  IO.println "  expectTag SemanticProgram.Data/9 from FieldsOk closed"
  IO.println "  runtime demo+unicode: expectTag + decodeQualifiedName after magic"
  IO.println "  kernel QN decode under Legal: residual parse/encodeArray (see module)"

end Tests.Semantic.SimpleClosureDecodeRootQnV1

def main : IO UInt32 := do
  Tests.Semantic.SimpleClosureDecodeRootQnV1.run
  pure 0
