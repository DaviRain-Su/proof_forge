/-
  Tests.Semantic.SimpleClosureDecodeV1 — focused suite for B-SC-DEC.

  Covers:
    * CodecRoundtrip production mid-offset NFC string / u32 / option / empty array
    * sole Encode builder alias `canonicalWireBytesV1`
    * QN component-list induction + array decode under Legal
    * demo legal + view/inv string encode/decode under Legal
    * Unicode-shaped params materialize (runtime identifier)
    * Proofed params parity: materialize shape + builder == subjectBytes (runtime)
    * framing package typechecks without free intermediate decode premises

  Does not claim unconditional DecodeSimpleClosureGoalV1 for all Legal p
  (nested fixed-shape field composition residual).
  No axiom / sorry / native_decide / ofReduceBool.
-/
import ProofForgeV2.Semantic.SimpleClosureDecodeV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import Tests.Language.InlineProofAuthoringV1

namespace Tests.Semantic.SimpleClosureDecodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureDecodeV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Kernel: production mid-offset primitives -/

theorem u32_encode_mid (left right : ByteArray) (v : UInt32) :
    readU32leAtV1 (left ++ encodeU32le v ++ right) left.size =
      .ok (v, left.size + 4) :=
  readU32le_encode_midV1 left right v

theorem empty_array_encode_zero (left right : ByteArray) :
    decodeArray maxTableElements decodeConstantV1
        ⟨left ++ encodeU32le 0 ++ right, left.size, 1⟩ =
      .ok (#[], ⟨left ++ encodeU32le 0 ++ right, left.size + 4, 1⟩) :=
  decodeArray_encode_zero_midV1 maxTableElements decodeConstantV1 left right 1

theorem string_nfc_ascii_mid (left right : ByteArray) :
    decodeString
        ⟨left ++ stringPayloadBytesV1 "alive" ++ right, left.size, 1⟩ =
      .ok ("alive",
        ⟨left ++ stringPayloadBytesV1 "alive" ++ right,
          left.size + 4 + "alive".toUTF8.size, 1⟩) :=
  decodeString_of_identifier_midV1 left right "alive" 1 (by
    unfold validateIdentifierComponent
    rw [if_pos (by decide)]
    simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
    rw [if_neg (by decide)]
    simp only [Pure.pure, Except.pure]
    rfl)

/-! ### Kernel: demo legal + name-hole encode/decode -/

theorem demo_legal : SimpleClosureParamsLegalV1 demoParamsV1 :=
  demoParams_legal

theorem demo_encode_view :
    encodeString demoParamsV1.viewName =
      .ok (stringPayloadBytesV1 demoParamsV1.viewName) :=
  encodeString_view_of_legal demoParamsV1 demoParams_legal

theorem demo_decode_view (left right : ByteArray) :
    decodeString
        ⟨left ++ stringPayloadBytesV1 demoParamsV1.viewName ++ right,
          left.size, 1⟩ =
      .ok (demoParamsV1.viewName,
        ⟨left ++ stringPayloadBytesV1 demoParamsV1.viewName ++ right,
          left.size + 4 + demoParamsV1.viewName.toUTF8.size, 1⟩) :=
  decodeString_view_of_legal left right demoParamsV1 demoParams_legal 1

theorem demo_option_view (left right : ByteArray) :
    decodeOption decodeString
        ⟨left ++ someStringPayloadBytesV1 demoParamsV1.viewName ++ right,
          left.size, 1⟩ =
      .ok (some demoParamsV1.viewName,
        ⟨left ++ someStringPayloadBytesV1 demoParamsV1.viewName ++ right,
          left.size + 1 + 4 + demoParamsV1.viewName.toUTF8.size, 1⟩) :=
  decodeOptionString_view_of_legal left right demoParamsV1 demoParams_legal 1

theorem demo_qn_components_decode (left right : ByteArray) :
    decodeArray 256 decodeString
        ⟨left ++ qualifiedNamePayloadV1 demoParamsV1 ++ right, left.size, 1⟩ =
      .ok ((demoParamsV1.qnHead :: demoParamsV1.qnTail.toList).toArray,
        ⟨left ++ qualifiedNamePayloadV1 demoParamsV1 ++ right,
          left.size + (qualifiedNamePayloadV1 demoParamsV1).size, 1⟩) :=
  decodeArray_qnComponents_of_legal left right demoParamsV1 demoParams_legal 1
    (by decide) (by decide)

theorem demo_materialize_shape :
    (materializeSimpleClosureDataV1 demoParamsV1).types.size = 2 ∧
    (materializeSimpleClosureDataV1 demoParamsV1).callables.size = 2 ∧
    (materializeSimpleClosureDataV1 demoParamsV1).invariants.size = 1 := by
  refine ⟨?_, ?_, ?_⟩ <;> rfl

/-- Framing packager: DecodeSimpleClosureGoalV1 has no free intermediate decode
    premises in its statement (only framing successes). -/
theorem framing_interface_type
    (p : SimpleClosureParamsV1)
    (afterMagic afterData : Cursor)
    (hsize : (canonicalWireBytesV1 p).size ≤ maxCanonicalProgramBytes)
    (hmagic :
      consumeMagic semanticProgramMagicV1 (start (canonicalWireBytesV1 p)) =
        .ok ((), afterMagic))
    (hdata :
      decodeSemanticProgramDataTaggedV1 afterMagic =
        .ok (materializeSimpleClosureDataV1 p, afterData))
    (hfinish : finish afterData = .ok ()) :
    DecodeSimpleClosureGoalV1 p :=
  decodeSimpleClosure_of_framing p afterMagic afterData hsize hmagic hdata hfinish

/-- Builder ownership: canonical alias is Encode wire bytes. -/
theorem canonical_eq_encode_builder (p : SimpleClosureParamsV1) :
    canonicalWireBytesV1 p = simpleClosureWireBytesV1 p :=
  rfl

/-! ### Runtime: demo / unicode / Proofed parity -/

private def testDemoDecodeSurface : IO Unit := do
  -- QN components array recovers head+tail under Legal.
  let left := ByteArray.empty
  let right := ByteArray.empty
  match decodeArray 256 decodeString
      ⟨left ++ qualifiedNamePayloadV1 demoParamsV1 ++ right, 0, 1⟩ with
  | .error e => throw <| IO.userError s!"demo QN decode failed: {repr e}"
  | .ok (comps, _) =>
      expect (comps == #["Module", "Prog"]) "demo QN components"
  -- view option string
  match decodeOption decodeString
      ⟨left ++ someStringPayloadBytesV1 demoParamsV1.viewName ++ right, 0, 1⟩ with
  | .error e => throw <| IO.userError s!"demo view option failed: {repr e}"
  | .ok (name?, _) =>
      expect (name? == some "alive") "demo view name"

private def testUnicodeLegalRuntime : IO Unit := do
  let p := unicodeLegalParamsV1
  -- Identifier authority must accept the Unicode-bearing names.
  expect (validateIdentifierComponent p.qnHead matches .ok _)
    "unicode qnHead identifier"
  expect (validateIdentifierComponent p.viewName matches .ok _)
    "unicode viewName identifier"
  expect (validateIdentifierComponent p.invName matches .ok _)
    "unicode invName identifier"
  -- Materialize shape is parametric (2 types / 2 callables / 1 inv).
  let data := materializeSimpleClosureDataV1 p
  expect (data.types.size == 2) "unicode types size"
  expect (data.callables.size == 2) "unicode callables size"
  expect (data.invariants.size == 1) "unicode invariants size"
  -- Field-path encode must succeed for legal Unicode names (NFC + size).
  match encodeSimpleClosureDataFieldsV1 p with
  | .error e => throw <| IO.userError s!"unicode field encode failed: {repr e}"
  | .ok bytes =>
      expect (bytes.size > 0) "unicode wire nonempty"
      expect (simpleClosureWireBytesV1 p == bytes) "unicode wireBytes == fields"
      -- Transport decode of production bytes must recover materialize data.
      match decodeSemanticProgramDataV1 bytes with
      | .error e =>
          throw <| IO.userError s!"unicode transport decode failed: {repr e}"
      | .ok data' =>
          expect (data' == data) "unicode decode == materialize"

private def testProofedParity : IO Unit := do
  let p := Proofed.Proof.simpleClosureParamsV1
  let data := materializeSimpleClosureDataV1 p
  expect (data.types.size == 2) "proofed types"
  expect (data.callables.size == 2) "proofed callables"
  expect (data.invariants.size == 1) "proofed invariants"
  match encodeSemanticProgramDataV1 data with
  | .error e => throw <| IO.userError s!"proofed encode failed: {repr e}"
  | .ok bytes =>
      expect (bytes == Proofed.Proof.subjectBytesV1)
        "proofed encode == subjectBytesV1"
      expect (simpleClosureWireBytesV1 p == Proofed.Proof.subjectBytesV1)
        "builder == subjectBytesV1"
      match decodeSemanticProgramDataV1 bytes with
      | .error e =>
          throw <| IO.userError s!"proofed decode failed: {repr e}"
      | .ok data' =>
          expect (data' == data) "proofed decode == materialize"
          expect (data' == materializeSimpleClosureDataV1 p)
            "proofed decode == materialize(p)"

def run : IO Unit := do
  testDemoDecodeSurface
  testUnicodeLegalRuntime
  testProofedParity
  IO.println "Tests.Semantic.SimpleClosureDecodeV1: ok"
  IO.println "  CodecRoundtrip production mid-offset NFC/u32/option/empty closed"
  IO.println "  QN array induction under Legal + demo/unicode/Proofed parity"
  IO.println "  DecodeSimpleClosureGoalV1 residual: nested fixed-shape field composition"

end Tests.Semantic.SimpleClosureDecodeV1
