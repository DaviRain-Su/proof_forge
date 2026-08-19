import ProofForgeV2.Targets.Solana.SbpfStateCellProductionEncodingV1

/-!
# Solana StateCell final production certificates
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode
open ProofForgeV2.Examples
open ProofForgeV2.Semantic.InvariantABI
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ReferenceV1
open ProofForgeV2.Semantic.RequirementsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1


/-- Unconditional source-to-carrier certificate for the real exported StateCell
    declaration. It composes the already certified Typed and lowering stages
    with the production wire theorem above. -/
theorem stateCellCanonicalCarrierCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (carrier : SemanticProgramV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        normalizeProgramV1 binding.validated = .ok carrier := by
  rcases stateCellCanonicalSourceBindingV1 with ⟨binding, hbinding⟩
  rcases stateCellSemanticEncodingSuccessV1 with ⟨bytes, hencode, _hsize⟩
  let carrier : SemanticProgramV1 := ⟨bytes⟩
  have hcarrier : encodeCarrierV1 stateCellSemanticProgramDataV1 = .ok carrier := by
    simpa only [carrier] using encodeCarrierV1_eq_ok_of_encode
      stateCellSemanticProgramDataV1 bytes hencode
  refine ⟨binding, carrier, hbinding, ?_⟩
  exact normalizeProgramV1_eq_ok_of_stages binding.validated
    stateCellSemanticProgramDataV1 carrier
    (stateCellTypedCheckSuccessV1 binding)
    (stateCellProgramLoweringSuccessV1 binding) hcarrier

/-- The exact StateCell carrier round-trips through the sole production decoder
    and explicit structure gate. The inverse is assembled from reusable field
    codec certificates rather than evaluating or copying the root bytes. -/
theorem stateCellSemanticValidationSuccessV1 :
    ∃ bytes,
      encodeSemanticProgramDataV1 stateCellSemanticProgramDataV1 = .ok bytes ∧
        validateSemanticProgramV1 ⟨bytes⟩ =
          .ok stateCellSemanticProgramDataV1 := by
  rcases stateCellSemanticEncodingSuccessV1 with ⟨bytes, hencode, _hsize⟩
  have hdecode :
      decodeSemanticProgramDataV1 bytes = .ok stateCellSemanticProgramDataV1 :=
    decodeSemanticProgramDataV1_of_encode_ok_of_rootFieldInvert
      stateCellSemanticProgramDataV1 bytes hencode stateCellRootFieldInvertV1
  exact ⟨bytes, hencode,
    validateSemanticProgramV1_eq_ok_of_encode_decode
      stateCellSemanticProgramDataV1 bytes hencode hdecode⟩

/- Unconditional source-to-`CompiledSemanticV1` identity certificate for the
    real exported StateCell declaration. Source and semantic digests remain
    exact symbolic results of the sole production SHA-256 implementation; no
    concrete digest or alternate compiler is supplied. -/
set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCompiledSemanticCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (carrier : SemanticProgramV1)
      (compiled : CompiledSemanticV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        normalizeProgramV1 binding.validated = .ok carrier ∧
        compileValidatedSourceV1 binding.validated = .ok compiled ∧
        validateSemanticProgramV1 carrier =
          .ok stateCellSemanticProgramDataV1 ∧
        CompiledSemanticV1.semanticV1Of compiled = carrier ∧
        CompiledSemanticV1.artifactProgramNameOf compiled = "StateCell" ∧
        CompiledSemanticV1.sourceDigestOf compiled = sha256Bytes
          (("pf.source.v1".toUTF8.push 0).append StateCell.bytes) ∧
        CompiledSemanticV1.semanticDigestOf compiled =
          sha256Bytes carrier.canonicalBytes := by
  rcases stateCellCanonicalSourceBindingV1 with ⟨binding, hbinding⟩
  rcases stateCellSemanticValidationSuccessV1 with
    ⟨bytes, hencode, hvalidate⟩
  let carrier : SemanticProgramV1 := ⟨bytes⟩
  have hcarrier : encodeCarrierV1 stateCellSemanticProgramDataV1 = .ok carrier := by
    simpa only [carrier] using encodeCarrierV1_eq_ok_of_encode
      stateCellSemanticProgramDataV1 bytes hencode
  have hnormalize : normalizeProgramV1 binding.validated = .ok carrier :=
    normalizeProgramV1_eq_ok_of_stages binding.validated
      stateCellSemanticProgramDataV1 carrier
      (stateCellTypedCheckSuccessV1 binding)
      (stateCellProgramLoweringSuccessV1 binding) hcarrier
  have hvalidateCarrier :
      validateSemanticProgramV1 carrier = .ok stateCellSemanticProgramDataV1 := by
    simpa only [carrier] using hvalidate
  have hname :
      (stateCellSemanticProgramDataV1.qualifiedName.components.toArray.back! ==
        ProofForgeV2.Source.NameComponentV1.SourceNameComponentV1.raw
          binding.validated.program.name) = true := by
    rw [binding.program_eq]
    rfl
  let sourceDigest := sha256Bytes
    (("pf.source.v1".toUTF8.push 0).append StateCell.bytes)
  have hsourceHash : sourceHashV1 binding.validated = .ok sourceDigest := by
    simp only [sourceHashV1, binding.canonicalBytes_eq, domainSeparatedSha256,
      show validateProfileIdValue "pf.source.v1" = .ok () by rfl,
      Bind.bind, Pure.pure, Except.bind, Except.pure, sourceDigest]
  let semanticDigest := sha256Bytes bytes
  have hsemanticHash : semanticHashV1 carrier = .ok semanticDigest := by
    simp only [semanticHashV1, hvalidateCarrier, Bind.bind, Pure.pure,
      Except.bind, Except.pure, semanticDigest, carrier]
  rcases compileValidatedSourceV1_eq_ok_of_stages binding.validated carrier
      stateCellSemanticProgramDataV1 sourceDigest semanticDigest hnormalize
      hvalidateCarrier hname hsourceHash hsemanticHash
      (validateDigest_sha256Bytes
        (("pf.source.v1".toUTF8.push 0).append StateCell.bytes))
      (validateDigest_sha256Bytes bytes) with
    ⟨compiled, hcompile, hcompiledCarrier, hcompiledName,
      hcompiledSource, hcompiledSemantic⟩
  refine ⟨binding, carrier, compiled, hbinding, hnormalize, hcompile,
    hvalidateCarrier, hcompiledCarrier, ?_, ?_, ?_⟩
  · exact hcompiledName.trans (by rfl)
  · simpa only [sourceDigest] using hcompiledSource
  · simpa only [semanticDigest, carrier] using hcompiledSemantic

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellReferenceAdmissionOkV1 :
    referenceProgramDataAdmissionOkV1 stateCellSemanticProgramDataV1 = true := by
  decide

/-- StateCell has crossed the source-dependent ingress of production
    preparation. The witnesses come from the same canonical source and sole
    compiler certificate, while Reference admission reuses the production
    data-only check. No partial preparation value or alternate resolver is
    minted here; static selection remains the next exact stage. -/
theorem stateCellProductionPreparationIngressCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (compiled : CompiledSemanticV1)
      (admitted : AdmittedReferenceSliceV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        compileValidatedSourceV1 binding.validated = .ok compiled ∧
        validateSemanticProgramV1
            (CompiledSemanticV1.semanticV1Of compiled) =
          .ok stateCellSemanticProgramDataV1 ∧
        admitReferenceProgramSliceV1
            (CompiledSemanticV1.semanticV1Of compiled) = .ok admitted := by
  rcases stateCellCompiledSemanticCertificateV1 with
    ⟨binding, carrier, compiled, hbinding, _hnormalize, hcompiled,
      hvalidate, hcompiledCarrier, _hname, _hsourceDigest,
      _hsemanticDigest⟩
  have hcompiledValidation :
      validateSemanticProgramV1
          (CompiledSemanticV1.semanticV1Of compiled) =
        .ok stateCellSemanticProgramDataV1 := by
    simpa only [hcompiledCarrier] using hvalidate
  have hadmissionCheck :
      validateReferenceProgramDataAdmissionV1
        stateCellSemanticProgramDataV1 = .ok () :=
    validateReferenceProgramDataAdmissionV1_eq_ok_of_bool
      stateCellSemanticProgramDataV1 stateCellReferenceAdmissionOkV1
  rcases admitReferenceProgramSliceV1_exists_of_checks
      (CompiledSemanticV1.semanticV1Of compiled)
      stateCellSemanticProgramDataV1 hcompiledValidation hadmissionCheck with
    ⟨admitted, hadmitted⟩
  exact ⟨binding, compiled, admitted, hbinding, hcompiled,
    hcompiledValidation, hadmitted⟩

end ProofForgeV2.Targets.Solana
