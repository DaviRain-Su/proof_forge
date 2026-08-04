/-
  Tests.Semantic.SimpleClosureDecodeFixedFieldsV1 — focused suite for the
  B-SC-DEC fixed-fields leaf.

  Covers kernel mid-offset decode of:
    * Bool + UInt64 TypeDecl and two-element types array
    * four empty tables
    * InvariantDecl + singleton array under demo Legal
    * sole value.bool ProgramRequirements
  plus runtime Unicode invName encode/decode and materialize encode identity.

  Registered in ProofForgeV2Tests roots + Typed shard (`def run`).
  No axiom / sorry / native_decide / ofReduceBool.
-/
import ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.Wire.CodecRoundtripV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

namespace Tests.Semantic.SimpleClosureDecodeFixedFieldsV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureDecodeFixedFieldsV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Kernel: types / empty / inv / requirements mid-offset -/

theorem kernel_encode_types :
    encodeArray encodeTypeDeclV1
        #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1] =
      .ok typesArrayBytesV1 :=
  encodeTypes_simpleClosure_eq_ok

theorem kernel_decode_types (left right : ByteArray) :
    decodeArray maxTableElements decodeTypeDeclV1
        ⟨left ++ typesArrayBytesV1 ++ right, left.size, 1⟩ =
      .ok (#[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1],
        ⟨left ++ typesArrayBytesV1 ++ right,
          left.size + typesArrayBytesV1.size, 1⟩) :=
  demo_decodeTypes_mid left right

theorem kernel_decode_empty_constants (left right : ByteArray) :
    decodeArray maxTableElements decodeConstantV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, 1⟩ =
      .ok (#[], ⟨left ++ emptyTableBytesV1 ++ right, left.size + 4, 1⟩) :=
  decodeEmptyConstants_materialize_midV1 left right 1

theorem kernel_decode_invariants (left right : ByteArray) :
    decodeArray maxTableElements decodeInvariantDeclV1
        ⟨left ++ invariantsArrayBytesV1 demoParamsV1.invName ++ right,
          left.size, 1⟩ =
      .ok (#[simpleClosureInvariantDeclV1 demoParamsV1.invName],
        ⟨left ++ invariantsArrayBytesV1 demoParamsV1.invName ++ right,
          left.size + (invariantsArrayBytesV1 demoParamsV1.invName).size, 1⟩) :=
  demo_decodeInvariants_mid left right

theorem kernel_decode_requirements (left right : ByteArray) :
    decodeProgramRequirementsV1
        ⟨left ++ programRequirementsValueBoolBytesV1 ++ right, left.size, 1⟩ =
      .ok ({ items := #[simpleClosureBoolRequirementV1] },
        ⟨left ++ programRequirementsValueBoolBytesV1 ++ right,
          left.size + programRequirementsValueBoolBytesV1.size, 1⟩) :=
  demo_decodeRequirements_mid left right

theorem kernel_encode_requirements_materialize (p : SimpleClosureParamsV1) :
    encodeProgramRequirementsV1 (materializeSimpleClosureDataV1 p).requirements =
      .ok programRequirementsValueBoolBytesV1 :=
  encodeRequirements_materialize_eq_ok p

theorem kernel_demo_legal : SimpleClosureParamsLegalV1 demoParamsV1 :=
  demoParams_legal

/-! ### Runtime: mid-offset surfaces + Unicode invName -/

private def testTypesMidOffset : IO Unit := do
  let left := ByteArray.mk #[1, 2, 3]
  let right := ByteArray.mk #[9, 8]
  match decodeArray maxTableElements decodeTypeDeclV1
      ⟨left ++ typesArrayBytesV1 ++ right, left.size, 1⟩ with
  | .error e => throw <| IO.userError s!"types mid decode failed: {repr e}"
  | .ok (types, c) =>
      expect (types == #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1])
        "types value"
      expect (c.offset == left.size + typesArrayBytesV1.size) "types cursor"

private def testEmptyTablesMidOffset : IO Unit := do
  let left := ByteArray.mk #[7]
  let right := ByteArray.mk #[0]
  let checkConstants : IO Unit := do
    match decodeArray maxTableElements decodeConstantV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, 2⟩ with
    | .error e => throw <| IO.userError s!"constants empty decode failed: {repr e}"
    | .ok (arr, c) =>
        expect (arr.size == 0) "constants empty"
        expect (c.offset == left.size + 4) "constants cursor"
  let checkState : IO Unit := do
    match decodeArray maxTableElements decodeStateDeclV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, 2⟩ with
    | .error e => throw <| IO.userError s!"state empty decode failed: {repr e}"
    | .ok (arr, c) =>
        expect (arr.size == 0) "state empty"
        expect (c.offset == left.size + 4) "state cursor"
  let checkEvents : IO Unit := do
    match decodeArray maxTableElements decodeEventDeclV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, 2⟩ with
    | .error e => throw <| IO.userError s!"events empty decode failed: {repr e}"
    | .ok (arr, c) =>
        expect (arr.size == 0) "events empty"
        expect (c.offset == left.size + 4) "events cursor"
  let checkErrors : IO Unit := do
    match decodeArray maxTableElements decodeErrorDeclV1
        ⟨left ++ emptyTableBytesV1 ++ right, left.size, 2⟩ with
    | .error e => throw <| IO.userError s!"errors empty decode failed: {repr e}"
    | .ok (arr, c) =>
        expect (arr.size == 0) "errors empty"
        expect (c.offset == left.size + 4) "errors cursor"
  checkConstants
  checkState
  checkEvents
  checkErrors

private def testInvariantsDemoMidOffset : IO Unit := do
  let left := ByteArray.empty
  let right := ByteArray.mk #[42]
  match decodeArray maxTableElements decodeInvariantDeclV1
      ⟨left ++ invariantsArrayBytesV1 demoParamsV1.invName ++ right, 0, 1⟩ with
  | .error e => throw <| IO.userError s!"inv array decode failed: {repr e}"
  | .ok (arr, c) =>
      expect (arr == #[simpleClosureInvariantDeclV1 "safe"]) "inv value"
      expect (c.offset == (invariantsArrayBytesV1 "safe").size) "inv cursor"

private def testRequirementsMidOffset : IO Unit := do
  let left := ByteArray.mk #[0, 1]
  let right := ByteArray.empty
  match decodeProgramRequirementsV1
      ⟨left ++ programRequirementsValueBoolBytesV1 ++ right, left.size, 1⟩ with
  | .error e => throw <| IO.userError s!"requirements decode failed: {repr e}"
  | .ok (req, c) =>
      expect (req.items == #[simpleClosureBoolRequirementV1]) "req value"
      expect (c.offset == left.size + programRequirementsValueBoolBytesV1.size)
        "req cursor"

private def testUnicodeInvName : IO Unit := do
  let invName := unicodeLegalParamsV1.invName
  -- Identifier authority must accept the Unicode-bearing invName.
  match validateIdentifierComponent invName with
  | .error e => throw <| IO.userError s!"unicode inv identifier failed: {e}"
  | .ok () => pure ()
  -- Encode must succeed and match the fixed-fields builder.
  match encodeInvariantDeclV1 (simpleClosureInvariantDeclV1 invName) with
  | .error e => throw <| IO.userError s!"unicode inv encode failed: {repr e}"
  | .ok bytes =>
      expect (bytes == invariantDeclBytesV1 invName) "unicode inv bytes"
      let left := ByteArray.mk #[3, 1]
      let right := ByteArray.mk #[2]
      match decodeInvariantDeclV1
          ⟨left ++ bytes ++ right, left.size, 1⟩ with
      | .error e =>
          throw <| IO.userError s!"unicode inv decode failed: {repr e}"
      | .ok (decl, c) =>
          expect (decl == simpleClosureInvariantDeclV1 invName) "unicode inv value"
          expect (c.offset == left.size + bytes.size) "unicode inv cursor"
  -- Singleton array path
  match encodeArray encodeInvariantDeclV1 #[simpleClosureInvariantDeclV1 invName] with
  | .error e => throw <| IO.userError s!"unicode inv array encode failed: {repr e}"
  | .ok arrB =>
      expect (arrB == invariantsArrayBytesV1 invName) "unicode inv array bytes"
      match decodeArray maxTableElements decodeInvariantDeclV1
          ⟨arrB, 0, 1⟩ with
      | .error e =>
          throw <| IO.userError s!"unicode inv array decode failed: {repr e}"
      | .ok (arr, _) =>
          expect (arr == #[simpleClosureInvariantDeclV1 invName])
            "unicode inv array value"

private def testMaterializeEncodeIdentity : IO Unit := do
  let p := demoParamsV1
  match encodeArray encodeTypeDeclV1 (materializeSimpleClosureDataV1 p).types with
  | .error e => throw <| IO.userError s!"materialize types encode: {repr e}"
  | .ok b => expect (b == typesArrayBytesV1) "materialize types bytes"
  match encodeProgramRequirementsV1
      (materializeSimpleClosureDataV1 p).requirements with
  | .error e => throw <| IO.userError s!"materialize req encode: {repr e}"
  | .ok b =>
      expect (b == programRequirementsValueBoolBytesV1) "materialize req bytes"
  let isOkEmpty (r : Except SemanticWireErrorV1 ByteArray) : Bool :=
    match r with
    | .ok b => b == emptyTableBytesV1
    | .error _ => false
  expect (isOkEmpty
    (encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 p).constants))
    "empty constants"
  expect (isOkEmpty
    (encodeArray encodeStateDeclV1 (materializeSimpleClosureDataV1 p).logicalState))
    "empty state"
  expect (isOkEmpty
    (encodeArray encodeEventDeclV1 (materializeSimpleClosureDataV1 p).events))
    "empty events"
  expect (isOkEmpty
    (encodeArray encodeErrorDeclV1 (materializeSimpleClosureDataV1 p).errors))
    "empty errors"
  -- Kernel package is inhabited (proved).
  let _ := encodeEmptyTables_materialize p
  pure ()

def run : IO Unit := do
  testTypesMidOffset
  testEmptyTablesMidOffset
  testInvariantsDemoMidOffset
  testRequirementsMidOffset
  testUnicodeInvName
  testMaterializeEncodeIdentity
  IO.println "Tests.Semantic.SimpleClosureDecodeFixedFieldsV1: ok"
  IO.println "  types/empty/inv/requirements mid-offset kernel + Unicode inv closed"

end Tests.Semantic.SimpleClosureDecodeFixedFieldsV1
