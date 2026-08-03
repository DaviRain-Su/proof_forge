/-
  Tests.Semantic.AuthorWireCertV1 — raw same-file author theorem bridge for the
  elaborator Proofed carrier via production AuthorWireCertV1.

  Closed without free hyp:
    * structure_proofed
    * encodeData_proofed (= elaborator subjectBytesV1)
    * LiteralTrueInvariantWitnessV1 for proofedData ordinal 0

  Sole free hyp (decode blocker; do not forge):
    decodeSemanticProgramDataV1 proofedBytes = .ok proofedData
  Parallel lane `lane/inline-proof-decode` owns ProofedDecodeCertV1; this suite
  keeps hdecode as an explicit premise and proves that discharging it closes
  `Proofed.Proof.safe` / `InvariantTheoremV1` kernel-checked.

  No axiom / sorry / native_decide / ofReduceBool. Theorem bodies do not enter
  ProgramV1 / sourceHash / semanticHash.
-/
import ProofForgeV2.Semantic.AuthorWireCertV1
import ProofForgeV2.Semantic.SimpleClosureCertV1
import ProofForgeV2.Semantic.ProofBridgeV1
import ProofForgeV2.Semantic.InvariantABI
import Tests.Semantic.ProofedCertV1
import Tests.Semantic.ProofedEncodeCertV1
import Tests.Semantic.SimpleClosureCertV1

namespace Tests.Semantic.AuthorWireCertV1

open ProofForgeV2.Semantic.AuthorWireCertV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.ProofBridgeV1
open ProofForgeV2.Semantic.SimpleClosureCertV1
open ProofForgeV2.Semantic.WireV1
open Tests.Semantic.ProofedCertV1
open Tests.Semantic.ProofedEncodeCertV1
open Tests.Semantic.SimpleClosureCertV1
open Tests.Language.InlineProofAuthoringV1

/-- Proofed literal-true shape is available on exact `proofedData`. -/
theorem proofedLiteralTrueWitness :
    LiteralTrueInvariantWitnessV1 proofedData 0
      { id := 0, name := "safe", callableId := 1 }
      0 (some "safe") .public_ none :=
  literalTrueWitness_of_proofedData proofedData rfl

/-- Wire certificate once transport decode is supplied (not forged here). -/
theorem proofedAuthorWireCert_of_decode
    (hdecode : decodeSemanticProgramDataV1 proofedBytes = .ok proofedData) :
    LiteralTrueAuthorWireCertV1 proofedData proofedBytes 0
      { id := 0, name := "safe", callableId := 1 }
      0 (some "safe") .public_ none :=
  LiteralTrueAuthorWireCertV1.ofParts proofedData proofedBytes 0
    { id := 0, name := "safe", callableId := 1 }
    0 (some "safe") .public_ none
    encodeData_proofed hdecode proofedLiteralTrueWitness

/-- Kernel-checked author bridge: decode hyp ⇒ product-byte InvariantTheorem. -/
theorem invariantTheorem_proofed_of_authorWire
    (hdecode : decodeSemanticProgramDataV1 proofedBytes = .ok proofedData) :
    InvariantTheoremV1 { canonicalBytes := proofedBytes } 0 := by
  have c := proofedAuthorWireCert_of_decode hdecode
  exact invariantTheoremV1_of_literalTrueAuthorWireCert proofedData proofedBytes 0
    { id := 0, name := "safe", callableId := 1 }
    0 (some "safe") .public_ none c

/-- Same conclusion on elaborator subjectProgramV1 (definitional bytes). -/
theorem invariantTheorem_subjectProgramV1_of_authorWire
    (hdecode :
      decodeSemanticProgramDataV1 Proofed.Proof.subjectBytesV1 = .ok proofedData) :
    InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0 := by
  have hdecode' : decodeSemanticProgramDataV1 proofedBytes = .ok proofedData := by
    -- proofedBytes := Proofed.Proof.subjectBytesV1 (definitional).
    simpa [proofedBytes] using hdecode
  have hclosed := invariantTheorem_proofed_of_authorWire hdecode'
  -- subjectProgramV1 := ⟨subjectBytesV1⟩ and proofedBytes := subjectBytesV1.
  simpa [subjectProgram_def, proofedBytes] using hclosed

/-- Normalize encode witness packaging matches closed encode. -/
theorem proofedNormalizeEncodeWitness :
    encodeSemanticProgramDataV1 proofedData = .ok proofedBytes :=
  encodeData_proofed

theorem invariantTheorem_via_normalizeEncode_of_decode
    (hdecode : decodeSemanticProgramDataV1 proofedBytes = .ok proofedData) :
    InvariantTheoremV1 { canonicalBytes := proofedBytes } 0 := by
  let w : NormalizeEncodeWitnessV1 :=
    NormalizeEncodeWitnessV1.ofEncode proofedData proofedBytes encodeData_proofed
  exact invariantTheoremV1_of_normalizeEncode_literalTrue w 0
    { id := 0, name := "safe", callableId := 1 }
    0 (some "safe") .public_ none hdecode proofedLiteralTrueWitness

end Tests.Semantic.AuthorWireCertV1

/-! ### Same-file author name expected by `proof safe using ProofedProof.safe` -/

namespace ProofedProof

open Tests.Semantic.AuthorWireCertV1
open Tests.Semantic.ProofedCertV1
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.WireV1
open Tests.Language.InlineProofAuthoringV1

/-- Production author-wire path: only transport decode remains free.
    Structure + encode + simple-closure witness are closed on this carrier.
    When the sibling decode lane supplies `decodeData_proofed`, this becomes
    an unconditional `Proofed.Proof.safe` without replaying evaluator phases. -/
theorem safe_of_authorWire
    (hdecode :
      decodeSemanticProgramDataV1 Proofed.Proof.subjectBytesV1 = .ok proofedData) :
    Proofed.Proof.safe := by
  change InvariantTheoremV1 Proofed.Proof.subjectProgramV1 0
  exact invariantTheorem_subjectProgramV1_of_authorWire hdecode

end ProofedProof
