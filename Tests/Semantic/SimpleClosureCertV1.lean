/-
  Tests.Semantic.SimpleClosureCertV1 — show the production simple-closure
  author bridge substitutes for the Proofed-specific conditional proof.

  Wire validation / encode-decode of the Proofed carrier remain hypotheses
  (closed positive decode lane is separate). This module only checks that the
  generic `LiteralTrueInvariantWitnessV1` + production theorems close
  `InvariantTheoremV1` for the known Proofed table shape without replaying
  the hand-rolled evaluator composition.
-/
import ProofForgeV2.Semantic.SimpleClosureCertV1
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI
import Tests.Semantic.ProofedCertV1

namespace Tests.Semantic.SimpleClosureCertV1

open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.SimpleClosureCertV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.ProofedCertV1

/-- Proofed table shape is exactly the production literal-true witness when
    the carrier data is `proofedData`. -/
theorem literalTrueWitness_of_proofedData
    (data : SemanticProgramDataV1)
    (hdata : data = proofedData) :
    LiteralTrueInvariantWitnessV1 data 0
      { id := 0, name := "safe", callableId := 1 }
      0 (some "safe") .public_ none := by
  refine {
    hselection := ?_
    htype := ?_
    hroot := ?_
    hcanonical := ?_
  }
  · simp [hdata, proofedData]
  · simp [hdata, proofedData, boolT]
  · simp [hdata, proofedData, invC, singleBlock, litTrue]
  · simp [hdata]
    exact boolLiteralTrue_canonical

/-- Generic evaluator theorem substitutes for `eval_safe_of_validate` once a
    validated carrier is available with `proofedData`. -/
theorem eval_safe_of_validated_carrier
    (carrier : ValidatedSemanticProgramV1)
    (hdata : carrier.data = proofedData)
    (st : LogicalStateV1)
    (hconforms : StateConformsV1 carrier.program st) :
    evalInvariantV1 carrier.program 0 st = .returnedTrue := by
  have w := literalTrueWitness_of_proofedData carrier.data hdata
  exact evalInvariantV1_eq_returnedTrue_of_literalTrueWitness
    carrier 0 { id := 0, name := "safe", callableId := 1 }
    0 (some "safe") .public_ none w st hconforms

/-- Generic theorem bridge substitutes for
    `invariantTheorem_proofed_of_validate` under a validated carrier. -/
theorem invariantTheorem_proofed_of_validated_carrier
    (carrier : ValidatedSemanticProgramV1)
    (hdata : carrier.data = proofedData) :
    InvariantTheoremV1 carrier.program 0 := by
  have w := literalTrueWitness_of_proofedData carrier.data hdata
  exact invariantTheoremV1_of_literalTrueWitness
    carrier 0 { id := 0, name := "safe", callableId := 1 }
    0 (some "safe") .public_ none w

/-- Same conclusion as the historical conditional Proofed theorem, but via
    the production bridge (carrier packages `hvalidate`). -/
theorem invariantTheorem_proofed_via_simple_closure
    (carrier : ValidatedSemanticProgramV1)
    (hdata : carrier.data = proofedData)
    (hprogram : carrier.program = { canonicalBytes := proofedBytes }) :
    InvariantTheoremV1 { canonicalBytes := proofedBytes } 0 := by
  have hclosed := invariantTheorem_proofed_of_validated_carrier carrier hdata
  simpa [hprogram] using hclosed

end Tests.Semantic.SimpleClosureCertV1
