/-
  Tests.Semantic.SimpleClosureEncodeV1 — B-SC-ENC focused suite.

  Covers:
    * sole body owner: encodeSimpleClosureDataFieldsV1 =
      encodeSemanticProgramDataBodyV1 (materialize p)
    * runtime equality: encode(materialize p) = ok (simpleClosureWireBytesV1 p)
      for Demo / alt-name / elaborator Proofed params
    * root encode == body (no second composition drift)
    * wire bytes match elaborator subjectBytesV1 (Proofed parity)
    * packaging under legal + body-ok; QN encode existence under legal

  Does **not** re-prove full Proofed structure/encode certificates.
  No axiom / sorry / native_decide / ofReduceBool.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.SimpleClosureEncodeFieldsV1
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1
import Tests.Language.InlineProofAuthoringV1

namespace Tests.Semantic.SimpleClosureEncodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureEncodeFieldsV1
open ProofForgeV2.Semantic.SimpleClosureEncodeV1
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Parametric demo params (no Tests FQN hardcoding in production path) -/

def demoParams : SimpleClosureParamsV1 :=
  {
    qnHead := "Demo"
    qnTail := #["Module", "Prog"]
    viewName := "alive"
    invName := "safe"
  }

theorem demo_wellFormed : SimpleClosureParamsWellFormedV1 demoParams :=
  ⟨by decide, by decide, by decide, by decide⟩

-- Concrete identifier lemmas (ASCII NFC free)
private theorem demo_ident_Demo :
    validateIdentifierComponent "Demo" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Demo" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_Module :
    validateIdentifierComponent "Module" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Module" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_Prog :
    validateIdentifierComponent "Prog" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Prog" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_alive :
    validateIdentifierComponent "alive" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem demo_ident_safe :
    validateIdentifierComponent "safe" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "safe" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

theorem demo_legal : SimpleClosureParamsLegalV1 demoParams := by
  refine {
    hqnSize := by decide
    hqnCap := by decide
    hdistinct := by decide
    hqnHead := demo_ident_Demo
    hqnTail := ?_
    hview := demo_ident_alive
    hinv := demo_ident_safe
  }
  intro i hi
  have hlt : i < 2 := by simpa [demoParams] using hi
  match i with
  | 0 => exact demo_ident_Module
  | 1 => exact demo_ident_Prog
  | n + 2 => omega

theorem demo_qn_encode_ok :
    ∃ b, encodeQualifiedName
        (materializeSimpleClosureDataV1 demoParams).qualifiedName = .ok b :=
  encodeQualifiedName_materialize_ok_of_legal demoParams demo_legal

theorem demo_qnShape :
    validateProgramQualifiedNameShapeV1
      (materializeSimpleClosureDataV1 demoParams).qualifiedName = .ok () :=
  validateProgramQualifiedNameShape_materialize_of_legal demoParams demo_legal

theorem demo_table_sizes_ok :
    checkTableSize (materializeSimpleClosureDataV1 demoParams).types.size = .ok () ∧
    checkTableSize (materializeSimpleClosureDataV1 demoParams).callables.size = .ok () ∧
    checkTableSize (materializeSimpleClosureDataV1 demoParams).invariants.size = .ok () :=
  ⟨checkTableSize_materialize_types demoParams,
    checkTableSize_materialize_callables demoParams,
    checkTableSize_materialize_invariants demoParams⟩

theorem demo_empty_tables :
    encodeArray encodeConstantV1 (materializeSimpleClosureDataV1 demoParams).constants =
      .ok simpleClosureEmptyTableBytesV1 :=
  encodeEmptyConstants_materialize demoParams

/-- Sole body path is the production body (no second composition). -/
theorem fields_eq_body (p : SimpleClosureParamsV1) :
    encodeSimpleClosureDataFieldsV1 p =
      encodeSemanticProgramDataBodyV1 (materializeSimpleClosureDataV1 p) :=
  rfl

theorem encodeString_alive :
    encodeString "alive" =
      .ok ((encodeU32le (UInt32.ofNat "alive".toUTF8.size)).append "alive".toUTF8) :=
  encodeString_eq_ok_of_ascii "alive" (by decide) (by decide)

theorem encodeString_safe :
    encodeString "safe" =
      .ok ((encodeU32le (UInt32.ofNat "safe".toUTF8.size)).append "safe".toUTF8) :=
  encodeString_eq_ok_of_ascii "safe" (by decide) (by decide)

theorem proofed_params_wellFormed :
    SimpleClosureParamsWellFormedV1 Proofed.Proof.simpleClosureParamsV1 :=
  ⟨by decide, by decide, by decide, by decide⟩

/-- Packaging under legal + body-ok (no free field-ok beyond body). -/
theorem encode_eq_wireBytes_of_legal_and_body
    (p : SimpleClosureParamsV1)
    (legal : SimpleClosureParamsLegalV1 p)
    (hbody : encodeSimpleClosureDataFieldsV1 p = .ok (simpleClosureWireBytesV1 p)) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) :=
  encodeSemanticProgramDataV1_materialize_eq_simpleClosureWireBytesV1_of_body_ok
    p (simpleClosureWireBytesV1 p) legal hbody

/-- Legal-only main theorem (no body-ok premise). -/
theorem encode_of_legal
    (p : SimpleClosureParamsV1) (legal : SimpleClosureParamsLegalV1 p) :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 p) =
      .ok (simpleClosureWireBytesV1 p) :=
  encodeSimpleClosure_of_legal p legal

theorem demo_encode_of_legal :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 demoParams) =
      .ok (simpleClosureWireBytesV1 demoParams) :=
  encodeSimpleClosure_of_legal demoParams demo_legal

theorem demoParamsV1_encode :
    encodeSemanticProgramDataV1 (materializeSimpleClosureDataV1 demoParamsV1) =
      .ok (simpleClosureWireBytesV1 demoParamsV1) :=
  encodeSimpleClosure_demo

/-! ### Proofed legal + encode kernel theorem (no extra premises) -/

private theorem proofed_ident_Tests :
    validateIdentifierComponent "Tests" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Tests" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem proofed_ident_Language :
    validateIdentifierComponent "Language" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Language" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem proofed_ident_InlineProofAuthoringV1 :
    validateIdentifierComponent "InlineProofAuthoringV1" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "InlineProofAuthoringV1" (by decide),
    Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem proofed_ident_Proofed :
    validateIdentifierComponent "Proofed" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Proofed" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem proofed_ident_alive :
    validateIdentifierComponent "alive" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "alive" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem proofed_ident_safe :
    validateIdentifierComponent "safe" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "safe" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

theorem proofed_legal :
    SimpleClosureParamsLegalV1 Proofed.Proof.simpleClosureParamsV1 := by
  have hparams :
      Proofed.Proof.simpleClosureParamsV1 =
        {
          qnHead := "Tests"
          qnTail := #["Language", "InlineProofAuthoringV1", "Proofed"]
          viewName := "alive"
          invName := "safe"
        } := by
    rfl
  refine {
    hqnSize := by simp only [hparams]; decide
    hqnCap := by simp only [hparams]; decide
    hdistinct := by simp only [hparams]; decide
    hqnHead := by simpa [hparams] using proofed_ident_Tests
    hqnTail := ?_
    hview := by simpa [hparams] using proofed_ident_alive
    hinv := by simpa [hparams] using proofed_ident_safe
  }
  intro i hi
  have hlt : i < 3 := by simpa [hparams] using hi
  match i with
  | 0 => simpa [hparams] using proofed_ident_Language
  | 1 => simpa [hparams] using proofed_ident_InlineProofAuthoringV1
  | 2 => simpa [hparams] using proofed_ident_Proofed
  | n + 3 => omega

/-- Proofed kernel theorem: legal alone ⇒ encode = wireBytes; no body-ok. -/
theorem proofed_encode_of_legal :
    encodeSemanticProgramDataV1
        (materializeSimpleClosureDataV1 Proofed.Proof.simpleClosureParamsV1) =
      .ok (simpleClosureWireBytesV1 Proofed.Proof.simpleClosureParamsV1) :=
  encodeSimpleClosure_of_legal Proofed.Proof.simpleClosureParamsV1 proofed_legal

/-! ### Runtime checks (parametric + elaborator + Unicode names) -/

private def testEncodeEqualsWireBytes (p : SimpleClosureParamsV1) (label : String) :
    IO Unit := do
  let data := materializeSimpleClosureDataV1 p
  match encodeSemanticProgramDataV1 data with
  | .error e =>
      throw <| IO.userError s!"{label}: encode failed: {repr e}"
  | .ok bytes =>
      match encodeSimpleClosureDataFieldsV1 p with
      | .error e =>
          throw <| IO.userError s!"{label}: body path failed: {repr e}"
      | .ok bodyBytes =>
          expect (bytes == bodyBytes)
            s!"{label}: root encode == sole body"
          expect (bytes == simpleClosureWireBytesV1 p)
            s!"{label}: root encode == simpleClosureWireBytesV1"
          expect (simpleClosureWireBytesV1? p == some bytes)
            s!"{label}: wireBytes? == some root bytes"
          -- Body equals production body authority
          match encodeSemanticProgramDataBodyV1 data with
          | .error e =>
              throw <| IO.userError s!"{label}: encodeSemanticProgramDataBodyV1: {repr e}"
          | .ok b2 =>
              expect (bodyBytes == b2)
                s!"{label}: fields alias == body authority"

private def testDemoAndProofed : IO Unit := do
  testEncodeEqualsWireBytes demoParams "demo"
  let alt : SimpleClosureParamsV1 :=
    {
      qnHead := "Acme"
      qnTail := #["Ledger", "Safe"]
      viewName := "okView"
      invName := "okInv"
    }
  testEncodeEqualsWireBytes alt "alt-names"
  testEncodeEqualsWireBytes Proofed.Proof.simpleClosureParamsV1 "proofed"
  match encodeSemanticProgramDataV1
      (materializeSimpleClosureDataV1 Proofed.Proof.simpleClosureParamsV1) with
  | .error e => throw <| IO.userError s!"proofed encode: {repr e}"
  | .ok bytes =>
      expect (bytes == Proofed.Proof.subjectBytesV1)
        "proofed wire bytes == elaborator subjectBytesV1"
      expect (simpleClosureWireBytesV1 Proofed.Proof.simpleClosureParamsV1 ==
          Proofed.Proof.subjectBytesV1)
        "sole wireBytes owner == subjectBytesV1"
  match encodeSimpleClosureDataFieldsV1 Proofed.Proof.simpleClosureParamsV1 with
  | .error e => throw <| IO.userError s!"proofed body: {repr e}"
  | .ok b =>
      expect (simpleClosureWireBytesV1 Proofed.Proof.simpleClosureParamsV1 == b)
        "wireBytes == body ok payload"

/-- Runtime Unicode identifier encode (Greek α): legal path is not ASCII-only. -/
private def testUnicodeEncode : IO Unit := do
  match validateIdentifierComponent "α" with
  | .error e => throw <| IO.userError s!"unicode α ident: {e}"
  | .ok () => pure ()
  let p : SimpleClosureParamsV1 :=
    {
      qnHead := "α"
      qnTail := #["Module"]
      viewName := "alive"
      invName := "safe"
    }
  -- Distinctness: α ≠ Module ≠ alive ≠ safe
  testEncodeEqualsWireBytes p "unicode-alpha"

def run : IO Unit := do
  testDemoAndProofed
  testUnicodeEncode
  IO.println "Tests.Semantic.SimpleClosureEncodeV1: ok"

end Tests.Semantic.SimpleClosureEncodeV1
