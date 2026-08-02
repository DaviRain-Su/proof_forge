import ProofForgeV2.Semantic.NormalizeV1

/-
  ProofForgeV2.Semantic.ProofSubjectV1 — source-bound proof-subject authority.

  This engineering boundary validates the complete immutable proof subject
  before any `.olean` declaration loader is allowed to consume it:
    * strict canonical `.pfsem` and `.pfprov` decode
    * sourceHash / semanticHash recomputation
    * source + path + spans authoritative provenance rebuild and digest
    * deterministic closed Lean source embedding every semantic byte

  It deliberately does not read files, trust manifest digest claims, load Lean
  declarations, or claim formal TST-PROOF-001 completion.
-/

namespace ProofForgeV2.Semantic.ProofSubjectV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

/-- Phase-preserving proof-subject validation failures. -/
inductive ProofSubjectErrorV1 where
  | semanticProgramWire (error : SemanticWireErrorV1)
  | semanticProvenanceWire (error : SemanticWireErrorV1)
  | sourceHash (detail : String)
  | authority (error : NormalizeErrorV1)
  deriving Repr

/-- A sealed capability minted only after the complete source-bound join. -/
structure ProofSubjectV1 where
  private mk ::
  program : SemanticProgramV1
  provenance : SemanticProvenanceV1
  sourceHash : Digest
  semanticHash : Digest
  semanticProvenanceDigest : Digest
  closedLeanSource : String

private def renderDecimalBytesV1 (bytes : ByteArray) : String :=
  String.intercalate ", " <| bytes.data.toList.map fun byte => toString byte.toNat

/-- Freeze a complete, reducible proof-subject module. Names and imports are
    fixed: no untrusted manifest or source string can inject Lean syntax. -/
private def renderClosedLeanSourceV1 (bytes : ByteArray) : String :=
  "import ProofForgeV2.Semantic.WireV1\n\n" ++
  "namespace ProofForgeV2.Generated.ProofSubjectV1\n\n" ++
  "abbrev subjectBytes : ByteArray :=\n" ++
  "  ByteArray.mk #[" ++ renderDecimalBytesV1 bytes ++ "]\n\n" ++
  "abbrev subjectProgram :\n" ++
  "    ProofForgeV2.Semantic.WireV1.SemanticProgramV1 :=\n" ++
  "  ⟨subjectBytes⟩\n\n" ++
  "end ProofForgeV2.Generated.ProofSubjectV1\n"

/-- Validate and mint the unique source-bound proof subject.

    Error priority is transport first (`.pfsem`, then `.pfprov`), followed by
    source hashing, semantic hashing, and finally the full provenance authority.
    Caller-supplied inventories and digest claims are intentionally absent. -/
def buildProofSubjectV1
    (source : ValidatedSourceV1)
    (sourcePath : ProjectRelativePath)
    (trustedSpans :
      Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))
    (pfsemBytes pfprovBytes : ByteArray) :
    Except ProofSubjectErrorV1 ProofSubjectV1 := do
  let program ← match decodeSemanticProgramV1 pfsemBytes with
    | .ok value => pure value
    | .error error => return ← .error (.semanticProgramWire error)
  let provenance ← match decodeSemanticProvenanceV1 pfprovBytes with
    | .ok value => pure value
    | .error error => return ← .error (.semanticProvenanceWire error)
  let sourceHash ← match sourceHashV1 source with
    | .ok value => pure value
    | .error detail => return ← .error (.sourceHash detail)
  let semanticHash ← match semanticHashV1 program with
    | .ok value => pure value
    | .error error => return ← .error (.semanticProgramWire error)
  let semanticProvenanceDigest ← match semanticProvenanceDigestV1
      source sourcePath trustedSpans program provenance with
    | .ok value => pure value
    | .error error => return ← .error (.authority error)
  pure ⟨program, provenance, sourceHash, semanticHash,
    semanticProvenanceDigest, renderClosedLeanSourceV1 program.canonicalBytes⟩

end ProofForgeV2.Semantic.ProofSubjectV1
