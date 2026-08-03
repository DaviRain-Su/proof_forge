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
import ProofForgeV2.Semantic.SimpleClosureEncodeV1
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1
import Tests.Language.InlineProofAuthoringV1

namespace Tests.Semantic.SimpleClosureEncodeV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
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

/-! ### Runtime checks (parametric + elaborator) -/

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

def run : IO Unit := do
  testDemoAndProofed
  IO.println "Tests.Semantic.SimpleClosureEncodeV1: ok"

end Tests.Semantic.SimpleClosureEncodeV1
