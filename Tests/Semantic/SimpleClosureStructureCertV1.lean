/-
  Tests.Semantic.SimpleClosureStructureCertV1 — B-SC-STRUCT suite.

  Covers:
    * parametric structure certificate under SimpleClosureParamsLegalV1
      (no Tests FQN hardcoding in production theorems)
    * shared identifier/NFC premises for QN head/tail + view/inv names
    * names distinct
    * runtime validateSemanticProgramStructureV1 on materialize(p) = ok
    * equal view/inv names fail structure (uniqueness)

  Does not claim encode/decode/product-positive (B-SC-ENC / B-SC-DEC).
  No axiom / sorry / native_decide / ofReduceBool.
-/
import ProofForgeV2.Semantic.SimpleClosureStructureCertV1
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

namespace Tests.Semantic.SimpleClosureStructureCertV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Semantic.SimpleClosureStructureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Parametric demo names (not Tests FQN) -/

def demoParams : SimpleClosureParamsV1 :=
  {
    qnHead := "Demo"
    qnTail := #["Module", "Prog"]
    viewName := "alive"
    invName := "safe"
  }

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

/-- B-SC-STRUCT for the parametric demo (no Tests FQN). -/
theorem demo_structure :
    validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 demoParams) =
      .ok () :=
  structure_of_legal demoParams demo_legal

theorem demo_structure_alias :
    validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 demoParams) =
      .ok () :=
  validateSemanticProgramStructureV1_materialize_eq_ok_of_legal demoParams demo_legal

theorem demo_qn_identifiers :
    validateIdentifierComponent demoParams.qnHead = .ok () ∧
      (∀ (i : Nat) (hi : i < demoParams.qnTail.size),
        validateIdentifierComponent demoParams.qnTail[i] = .ok ()) :=
  qnComponents_identifierOk_of_legal demoParams demo_legal

theorem demo_view_inv_identifiers :
    validateIdentifierComponent demoParams.viewName = .ok () ∧
      validateIdentifierComponent demoParams.invName = .ok () :=
  viewInv_identifierOk_of_legal demoParams demo_legal

/-! ### Alternate module path (still no Tests FQN) -/

def altParams : SimpleClosureParamsV1 :=
  {
    qnHead := "Acme"
    qnTail := #["Ledger"]
    viewName := "ok"
    invName := "holds"
  }

private theorem alt_ident_Acme :
    validateIdentifierComponent "Acme" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Acme" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem alt_ident_Ledger :
    validateIdentifierComponent "Ledger" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "Ledger" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem alt_ident_ok :
    validateIdentifierComponent "ok" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "ok" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

private theorem alt_ident_holds :
    validateIdentifierComponent "holds" = .ok () := by
  unfold validateIdentifierComponent
  rw [if_pos (by decide)]
  simp only [requireNfc_eq_ok_of_isAscii "holds" (by decide), Bind.bind, Except.bind]
  rw [if_neg (by decide)]
  simp only [Pure.pure, Except.pure]
  rfl

theorem alt_legal : SimpleClosureParamsLegalV1 altParams := by
  refine {
    hqnSize := by decide
    hdistinct := by decide
    hqnHead := alt_ident_Acme
    hqnTail := ?_
    hview := alt_ident_ok
    hinv := alt_ident_holds
  }
  intro i hi
  have : i = 0 := by
    have : i < 1 := by simpa [altParams] using hi
    omega
  subst this
  exact alt_ident_Ledger

theorem alt_structure :
    validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 altParams) =
      .ok () :=
  structure_of_legal altParams alt_legal

/-! ### Runtime structure gate -/

private def testRuntimeStructure : IO Unit := do
  match validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 demoParams) with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"demo structure: expected ok, got {repr e}"
  match validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 altParams) with
  | .ok () => pure ()
  | .error e =>
      throw <| IO.userError s!"alt structure: expected ok, got {repr e}"
  expect (demoParams.qnHead == "Demo") "demo head"
  expect (demoParams.viewName != demoParams.invName) "demo distinct"
  expect (altParams.qnHead == "Acme") "alt head"
  -- Negative: equal view/inv names fail callable uniqueness at structure.
  let bad : SimpleClosureParamsV1 :=
    { qnHead := "X", qnTail := #["Y"], viewName := "same", invName := "same" }
  match validateSemanticProgramStructureV1 (materializeSimpleClosureDataV1 bad) with
  | .ok () =>
      throw <| IO.userError "duplicate view/inv should fail structure"
  | .error _ => pure ()

def run : IO Unit := do
  testRuntimeStructure
  IO.println "Tests.Semantic.SimpleClosureStructureCertV1: ok"

end Tests.Semantic.SimpleClosureStructureCertV1
