import ProofForgeV2.Targets.Solana.SbpfStateCellProductionV1

/-!
# StateCell Solana engineering-capability certificate

Fresh-process continuation of the source/compiler production certificate. It
composes the frozen Solana selection, generic requirement support, engineering
support claim, and sole engineering capability resolver without changing those
authorities or branching on the contract name.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Compiler
open ProofForgeV2.Examples
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.RequirementResolverV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellSolanaRequirementResolutionSuccessV1 :
    inspectResolveRequestsV1 initialSolanaSupportRowV1.supported
      stateCellSemanticProgramDataV1.requirements = .ok () := by
  rcases stateCellRequirementFieldValuesV1 with
    ⟨hid0, hversion0, hdigest0, hpredicates0, hid1, hversion1, hdigest1,
      hpredicates1, hid2, hversion2, hdigest2, hpredicates2⟩
  have hrequest0 : stateCellRequirement0V1 = initialS2RequestV1
      ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1
      ProofForgeV2.Semantic.RequirementsV1.s2FailureAtomicRollbackDigestBytesV1 := by
    cases hrequest : stateCellRequirement0V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid0 hversion0 hdigest0 hpredicates0
        simp only [initialS2RequestV1, hid0, hversion0, hdigest0,
          hpredicates0,
          ProofForgeV2.Core.RequirementIdsV1.s2FailureAtomicRollbackIdV1]
  have hrequest1 : stateCellRequirement1V1 = initialS2RequestV1
      ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1
      ProofForgeV2.Semantic.RequirementsV1.s2StatePersistentDigestBytesV1 := by
    cases hrequest : stateCellRequirement1V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid1 hversion1 hdigest1 hpredicates1
        simp only [initialS2RequestV1, hid1, hversion1, hdigest1,
          hpredicates1,
          ProofForgeV2.Core.RequirementIdsV1.s2StatePersistentIdV1]
  have hrequest2 : stateCellRequirement2V1 = initialS2RequestV1
      ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1
      ProofForgeV2.Semantic.RequirementsV1.s2ValueCheckedArithmeticDigestBytesV1 := by
    cases hrequest : stateCellRequirement2V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid2 hversion2 hdigest2 hpredicates2
        simp only [initialS2RequestV1, hid2, hversion2, hdigest2,
          hpredicates2,
          ProofForgeV2.Core.RequirementIdsV1.s2ValueCheckedArithmeticIdV1]
  apply inspectResolveRequestsV1_initial_solana_state_checked_eq_ok
  rw [stateCellRequirementItemsV1, hrequest0, hrequest1, hrequest2]

/-- StateCell crosses frozen Solana selection and the sole engineering
    capability resolver using its retained compiler requirements. The theorem
    composes generic registry/support/claim machinery; no resolver branch is
    keyed by the StateCell contract name. -/
theorem stateCellEngineeringCapabilityCertificateV1 :
    ∃ (binding : CanonicalSourceBindingV1
          StateCell.Source.subjectV1 StateCell.bytes)
      (selection : ResolvedBuildSelectionV1)
      (compiled : CompiledSemanticV1)
      (carrier : SemanticProgramV1)
      (capability : ResolvedEngineeringBuildV1),
      bindElaboratedSourceToCanonicalBytesV1
          StateCell.Source.subjectV1 StateCell.bytes = .ok binding ∧
        compileValidatedSourceV1 binding.validated = .ok compiled ∧
        validateSemanticProgramV1
            (CompiledSemanticV1.semanticV1Of compiled) =
          .ok stateCellSemanticProgramDataV1 ∧
        CompiledSemanticV1.semanticV1Of compiled = carrier ∧
        decodeSemanticProgramDataV1 carrier.canonicalBytes =
          .ok stateCellSemanticProgramDataV1 ∧
        resolveBuildSelectionV1 TargetId.solana
            (some CodegenProfileId.solanaSbpfCpiElfV1) = .ok selection ∧
        ResolvedBuildSelectionV1.targetIdOf selection = TargetId.solana ∧
        ResolvedBuildSelectionV1.codegenProfileOf selection =
          CodegenProfileId.solanaSbpfCpiElfV1 ∧
        ResolvedBuildSelectionV1.kindOf selection = .solana ∧
        resolveEngineeringRequirementsV1 selection compiled =
          .ok capability ∧
        ResolvedEngineeringBuildV1.selectionOf capability = selection ∧
        ResolvedEngineeringBuildV1.compiledOf capability = compiled := by
  rcases stateCellCompiledSemanticCertificateV1 with
    ⟨binding, carrier, compiled, hbinding, _hnormalize, hcompiled,
      hvalidate, hdecode, hcompiledCarrier, _hname, _hsourceDigest,
      _hsemanticDigest⟩
  have hcompiledValidation :
      validateSemanticProgramV1
          (CompiledSemanticV1.semanticV1Of compiled) =
        .ok stateCellSemanticProgramDataV1 := by
    simpa only [hcompiledCarrier] using hvalidate
  rcases resolveBuildSelectionV1_solana_sbpf_cpi_elf_exists with
    ⟨selection, hselection, htarget, hprofile, hkind⟩
  rcases resolveEngineeringRequirementsV1_solana_sbpf_cpi_elf_exists
      selection compiled stateCellSemanticProgramDataV1 htarget hprofile hkind
      hcompiledValidation stateCellSolanaRequirementResolutionSuccessV1 with
    ⟨capability, hcapability, hcapabilitySelection, hcapabilityCompiled⟩
  exact ⟨binding, selection, compiled, carrier, capability, hbinding, hcompiled,
    hcompiledValidation, hcompiledCarrier, hdecode, hselection, htarget,
    hprofile, hkind, hcapability, hcapabilitySelection, hcapabilityCompiled⟩

end ProofForgeV2.Targets.Solana
