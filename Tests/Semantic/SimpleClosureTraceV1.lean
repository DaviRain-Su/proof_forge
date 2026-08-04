/-
  Tests.Semantic.SimpleClosureTraceV1 — foundation suite for the production
  name/module-parameterized simple-closure certificate AST.

  Covers:
    * materialize shape for arbitrary names (no Tests FQN hardcoding in
      production materialize)
    * extract ↔ materialize fixpoint on the elaborator Proofed carrier
    * elaborator-emitted Proof.simpleClosureParamsV1 / simpleClosureDataV1
    * parametric LiteralTrueInvariantWitness from materialize
    * wire-trace soundness composition under free encode/decode hyps
      (decode not forged)

  Does **not** claim product-positive raw-source certifier success.
  Exact blockers: B-SC-STRUCT / B-SC-ENC / B-SC-DEC / B-SC-ELAB-THM / B-SC-PRODUCT
  (see SimpleClosureTraceV1 module footer).

  No axiom / sorry / native_decide / ofReduceBool.
-/
import ProofForgeV2.Semantic.SimpleClosureTraceV1
import ProofForgeV2.Semantic.AuthorWireCertV1
import ProofForgeV2.Semantic.SimpleClosureCertV1
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI
import ProofForgeV2.Semantic.WireV1
import Tests.Language.InlineProofAuthoringV1
import Tests.Semantic.ProofedCertV1
import Tests.Semantic.ProofedEncodeCertV1

namespace Tests.Semantic.SimpleClosureTraceV1

open ProofForgeV2.Semantic.AuthorWireCertV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.SimpleClosureCertV1
open ProofForgeV2.Semantic.SimpleClosureTraceV1
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1
open Tests.Semantic.ProofedCertV1
open Tests.Semantic.ProofedEncodeCertV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-! ### Parametric materialize (no fixture FQN in production path) -/

/-- Arbitrary module path + names still materialize the family shape. -/
def demoParams : SimpleClosureParamsV1 :=
  {
    qnHead := "Demo"
    qnTail := #["Module", "Prog"]
    viewName := "alive"
    invName := "safe"
  }

theorem demo_qnSize : demoParams.qnSize = 3 := rfl

theorem demo_wellFormed : SimpleClosureParamsWellFormedV1 demoParams :=
  ⟨by decide, by decide, by decide, by decide⟩

theorem demo_materialize_types :
    (materializeSimpleClosureDataV1 demoParams).types =
      #[simpleClosureBoolTypeV1, simpleClosureUInt64TypeV1] :=
  rfl

theorem demo_materialize_callables_size :
    (materializeSimpleClosureDataV1 demoParams).callables.size = 2 :=
  rfl

theorem demo_materialize_invariants_size :
    (materializeSimpleClosureDataV1 demoParams).invariants.size = 1 :=
  rfl

theorem demo_literalTrueWitness :
    LiteralTrueInvariantWitnessV1 (materializeSimpleClosureDataV1 demoParams) 0
      (simpleClosureInvariantDeclV1 "safe")
      0 (some "safe") .public_ none :=
  literalTrueWitness_of_materialize demoParams

/-! ### Elaborator-emitted certificate constructors exist -/

#check Proofed.Proof.simpleClosureParamsV1
#check Proofed.Proof.simpleClosureDataV1

theorem emitted_params_view :
    Proofed.Proof.simpleClosureParamsV1.viewName = "alive" :=
  rfl

theorem emitted_params_inv :
    Proofed.Proof.simpleClosureParamsV1.invName = "safe" :=
  rfl

theorem emitted_params_qnHead :
    Proofed.Proof.simpleClosureParamsV1.qnHead = "Tests" :=
  rfl

theorem emitted_data_def :
    Proofed.Proof.simpleClosureDataV1 =
      materializeSimpleClosureDataV1 Proofed.Proof.simpleClosureParamsV1 :=
  rfl

theorem emitted_literalTrueWitness :
    LiteralTrueInvariantWitnessV1 Proofed.Proof.simpleClosureDataV1 0
      (simpleClosureInvariantDeclV1
        Proofed.Proof.simpleClosureParamsV1.invName)
      0 (some Proofed.Proof.simpleClosureParamsV1.invName) .public_ none := by
  simpa [emitted_data_def] using
    literalTrueWitness_of_materialize Proofed.Proof.simpleClosureParamsV1

theorem emitted_wellFormed :
    SimpleClosureParamsWellFormedV1 Proofed.Proof.simpleClosureParamsV1 :=
  ⟨by decide, by decide, by decide, by decide⟩

/-! ### Wire-trace soundness under free decode (encode closed for Proofed) -/

/-- Encode of emitted materialize equals elaborator subject when data matches
    the fixture encode certificate. Free hyp: materialize equals proofedData
    (established at runtime / sibling decode lane). -/
theorem proofed_wireTrace_of_materialize_eq_proofedData
    (hdata :
      materializeSimpleClosureDataV1 Proofed.Proof.simpleClosureParamsV1 =
        proofedData)
    (hdecode :
      decodeSemanticProgramDataV1 Proofed.Proof.subjectBytesV1 =
        .ok proofedData) :
    SimpleClosureWireTraceV1
      Proofed.Proof.simpleClosureParamsV1
      Proofed.Proof.subjectBytesV1 := by
  refine SimpleClosureWireTraceV1.ofParts
    Proofed.Proof.simpleClosureParamsV1
    Proofed.Proof.subjectBytesV1
    emitted_wellFormed
    ?hencode
    ?hdecode
  · -- encode path: rewrite to proofedData then use closed encode certificate.
    have hencode := encodeData_proofed
    simpa [hdata, proofedBytes] using hencode
  · simpa [hdata] using hdecode

theorem proofed_invariant_of_materialize_eq_proofedData
    (hdata :
      materializeSimpleClosureDataV1 Proofed.Proof.simpleClosureParamsV1 =
        proofedData)
    (hdecode :
      decodeSemanticProgramDataV1 Proofed.Proof.subjectBytesV1 =
        .ok proofedData) :
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0 := by
  have t := proofed_wireTrace_of_materialize_eq_proofedData hdata hdecode
  have hclosed :=
    invariantTheoremV1_of_simpleClosureWireTrace
      Proofed.Proof.simpleClosureParamsV1
      Proofed.Proof.subjectBytesV1 t
  -- subjectProgramV1 := ⟨subjectBytesV1⟩
  simpa [subjectProgram_def, proofedBytes] using hclosed

/-! ### Runtime extract / elaborator emission checks -/

private def testExtractAndEmit : IO Unit := do
  match decodeSemanticProgramDataV1 Proofed.Proof.subjectBytesV1 with
  | .error e =>
      throw <| IO.userError s!"decode subjectBytesV1: {repr e}"
  | .ok data =>
      expect (isSimpleClosureFamilyDataV1 data)
        "Proofed subject is simple-closure family"
      match extractSimpleClosureParamsV1 data with
      | none => throw <| IO.userError "extract Proofed params failed"
      | some p =>
          expect (p.viewName == "alive") "view name alive"
          expect (p.invName == "safe") "inv name safe"
          expect (p.qnHead == "Tests") "qn head Tests"
          expect (p.qnTail == #["Language", "InlineProofAuthoringV1", "Proofed"])
            "qn tail module path"
          expect (materializeSimpleClosureDataV1 p == data)
            "materialize fixpoint on Proofed data"
          expect (Proofed.Proof.simpleClosureParamsV1 == p)
            "elaborator params == extract params"
          expect (Proofed.Proof.simpleClosureDataV1 == data)
            "elaborator data == decoded subject"
  -- Parametric demo does not hardcode Tests FQN.
  expect (demoParams.qnHead == "Demo") "demo head"
  match (materializeSimpleClosureDataV1 demoParams).invariants[0]? with
  | some inv => expect (inv.name == "safe") "demo inv name"
  | none => throw <| IO.userError "demo invariants empty"

def run : IO Unit := do
  testExtractAndEmit
  IO.println "Tests.Semantic.SimpleClosureTraceV1: ok"

end Tests.Semantic.SimpleClosureTraceV1
