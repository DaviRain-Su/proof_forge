/-
  Tests.Semantic.SimpleClosureDecodeComposeV1 — B-SC-DEC final composition suite.

  Covers:
    * parameterized kernel: Legal alone ⇒ production encode + full transport
      decode recover materialize and close ordinal-0 InvariantTheoremV1
    * demo Legal kernel discharge + QN encode/parse
    * Unicode-runtime encode/decode parity
    * tagged body recovery at post-magic offset

  No Tests FQN in production theorems; no axiom / sorry / native_decide.
-/
import ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

namespace Tests.Semantic.SimpleClosureDecodeComposeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.SimpleClosureDecodeComposeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
-- DecodeV1 for DecodeSimpleClosureGoalV1 / qualifiedNamePayloadV1 only (avoid demoParams clash).
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
  (DecodeSimpleClosureGoalV1 qualifiedNamePayloadV1)

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Kernel: demo Legal + composition theorems -/

theorem demo_legal : SimpleClosureParamsLegalV1 demoParamsV1 :=
  demoParams_legal

theorem demo_qn_encode_payload :
    encodeQualifiedName (materializeSimpleClosureDataV1 demoParamsV1).qualifiedName =
      .ok (qualifiedNamePayloadV1 demoParamsV1) :=
  encodeQualifiedName_materialize_eq_payload_of_legal demoParamsV1 demoParams_legal

theorem demo_parse_qn :
    parseQualifiedName (#[demoParamsV1.qnHead] ++ demoParamsV1.qnTail) =
      .ok demoParamsV1.toQualifiedName :=
  parseQualifiedName_qnComponents_of_legal demoParamsV1 demoParams_legal

/-- Parameterized kernel packaging: sole Legal + hfields ⇒ full decode. -/
theorem kernel_decode_of_fields_ok
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    decodeSemanticProgramDataV1 b = .ok (materializeSimpleClosureDataV1 p) :=
  decodeSimpleClosure_of_fields_ok_legal p b legal hfields

/-- Strong goal form under Legal + body encode success. -/
theorem kernel_decode_goal
    (p : SimpleClosureParamsV1) (b : ByteArray)
    (legal : SimpleClosureParamsLegalV1 p)
    (hfields : encodeSimpleClosureDataFieldsV1 p = .ok b) :
    DecodeSimpleClosureGoalV1 p :=
  decodeSimpleClosureGoal_of_fields_ok_legal p b legal hfields

/-- Legal alone closes production transport decode; no encode premise remains. -/
theorem kernel_decode_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    decodeSemanticProgramDataV1 (simpleClosureWireBytesV1 p) =
      .ok (materializeSimpleClosureDataV1 p) :=
  decodeSimpleClosure_of_legal p legal

/-- Legal alone closes the exact ordinal-0 invariant theorem. -/
theorem kernel_invariant_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    InvariantTheoremV1 { canonicalBytes := simpleClosureWireBytesV1 p } 0 :=
  invariantTheoremV1_of_simpleClosure_legal p legal

theorem demo_tagged_body
    (b : ByteArray)
    (hfields : encodeSimpleClosureDataFieldsV1 demoParamsV1 = .ok b) :
    decodeSemanticProgramDataTaggedV1
        ⟨b, (encodeMagicPrefix semanticProgramMagicV1).size, 0⟩ =
      .ok (materializeSimpleClosureDataV1 demoParamsV1, ⟨b, b.size, 0⟩) := by
  have fok := encodeSimpleClosureFields_ok_inv demoParamsV1 b hfields
  have h :=
    decodeSemanticProgramDataTagged_of_simpleClosure_field_bytes
      demoParamsV1 b demoParams_legal fok
  simpa using h

theorem demo_full_decode
    (b : ByteArray)
    (hfields : encodeSimpleClosureDataFieldsV1 demoParamsV1 = .ok b) :
    decodeSemanticProgramDataV1 b =
      .ok (materializeSimpleClosureDataV1 demoParamsV1) :=
  decodeSimpleClosure_of_fields_ok_legal demoParamsV1 b demoParams_legal hfields

theorem demo_full_decode_legal_only :
    decodeSemanticProgramDataV1 (simpleClosureWireBytesV1 demoParamsV1) =
      .ok (materializeSimpleClosureDataV1 demoParamsV1) :=
  decodeSimpleClosure_of_legal demoParamsV1 demoParams_legal

theorem demo_invariant_legal_only :
    InvariantTheoremV1 { canonicalBytes := simpleClosureWireBytesV1 demoParamsV1 } 0 :=
  invariantTheoremV1_of_simpleClosure_legal demoParamsV1 demoParams_legal

/-! ### Runtime: demo + unicode parity -/

private def testDemoKernelCompose : IO Unit := do
  match encodeSimpleClosureDataFieldsV1 demoParamsV1 with
  | .error e => throw <| IO.userError s!"demo encode: {repr e}"
  | .ok b =>
      match decodeSemanticProgramDataV1 b with
      | .error e => throw <| IO.userError s!"demo decode: {repr e}"
      | .ok data =>
          expect (data == materializeSimpleClosureDataV1 demoParamsV1)
            "demo decode == materialize"
          expect (data.qualifiedName.components.head == "Module")
            "demo QN head"
          expect (data.callables.size == 2) "demo callables"
          expect (data.invariants.size == 1) "demo invariants"
      let magicSz := (encodeMagicPrefix semanticProgramMagicV1).size
      match decodeSemanticProgramDataTaggedV1 ⟨b, magicSz, 0⟩ with
      | .error e => throw <| IO.userError s!"demo tagged: {repr e}"
      | .ok (dataT, c) =>
          expect (dataT == materializeSimpleClosureDataV1 demoParamsV1)
            "demo tagged == materialize"
          expect (c.offset == b.size) "demo tagged EOF"
      match encodeQualifiedName
          (materializeSimpleClosureDataV1 demoParamsV1).qualifiedName with
      | .error e => throw <| IO.userError s!"demo QN encode: {repr e}"
      | .ok qnB =>
          expect (qnB == qualifiedNamePayloadV1 demoParamsV1)
            "demo QN bytes == payload"

private def testUnicodeCompose : IO Unit := do
  let p := unicodeLegalParamsV1
  expect (validateIdentifierComponent p.qnHead matches .ok _)
    "unicode qnHead"
  expect (validateIdentifierComponent p.viewName matches .ok _)
    "unicode view"
  expect (validateIdentifierComponent p.invName matches .ok _)
    "unicode inv"
  match encodeSimpleClosureDataFieldsV1 p with
  | .error e => throw <| IO.userError s!"unicode encode: {repr e}"
  | .ok b =>
      match decodeSemanticProgramDataV1 b with
      | .error e => throw <| IO.userError s!"unicode decode: {repr e}"
      | .ok data =>
          expect (data == materializeSimpleClosureDataV1 p)
            "unicode decode == materialize"
          expect (data.qualifiedName.components.head == p.qnHead)
            "unicode QN head preserved"
          match data.callables[0]?, data.callables[1]?, data.invariants[0]? with
          | some c0, some c1, some inv =>
              expect (c0.name == some p.viewName) "unicode view name preserved"
              expect (c1.name == some p.invName) "unicode inv name preserved"
              expect (inv.name == p.invName) "unicode inv decl name preserved"
          | _, _, _ =>
              throw <| IO.userError "unicode: missing callables/invariants"

def run : IO Unit := do
  testDemoKernelCompose
  testUnicodeCompose
  IO.println "Tests.Semantic.SimpleClosureDecodeComposeV1: ok"
  IO.println "  kernel: Legal alone ⇒ encode/decode + ordinal-0 invariant theorem"
  IO.println "  demo + unicode runtime transport decode parity closed"
  IO.println "  QN encode payload + parse under Legal closed (no free hparse)"

end Tests.Semantic.SimpleClosureDecodeComposeV1
