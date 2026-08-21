import ProofForgeV2.Targets.Solana.SbpfStateCellProductionStructureV1

/-!
# StateCell Solana production Plan stages

Concrete kernel facts for the context-preparation stage of the sole
`SemanticProgramDataV1 → Plan` lowerer. StateCell is only a regression witness:
all functions replayed below are target-generic production stages, and no
resolver or lowerer branches on the contract name.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellPlanTypesExactSuccessV1 :
    validateSolanaTypeClosureV1 stateCellSemanticProgramDataV1.types = .ok {
      uint64TypeId := some 0
      unitTypeId := some 1
      boolTypeId := none
      uint32TypeId := none
    } := by
  unfold validateSolanaTypeClosureV1
  rw [stateCellTypesExactV1]
  unfold ProofForgeV2.Targets.EnvelopeV1.validatePilotTypeClosure
    ProofForgeV2.Targets.EnvelopeV1.widthAdmitted
    ProofForgeV2.Targets.EnvelopeV1.intWidthAdmitted
    ProofForgeV2.Targets.EnvelopeV1.pilotUintWidthPolicySolanaBody
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind]

theorem stateCellPlanTypesSomeV1 :
    (validateSolanaTypeClosureV1
      stateCellSemanticProgramDataV1.types).toOption.isSome = true := by
  rw [stateCellPlanTypesExactSuccessV1]
  rfl

def stateCellPlanTypesV1 :=
  (validateSolanaTypeClosureV1
    stateCellSemanticProgramDataV1.types).toOption.get
      stateCellPlanTypesSomeV1

theorem stateCellPlanTypesSuccessV1 :
    validateSolanaTypeClosureV1 stateCellSemanticProgramDataV1.types =
      .ok stateCellPlanTypesV1 := by
  apply exceptToOptionGetSuccessV1

theorem stateCellPlanTypesValueV1 :
    stateCellPlanTypesV1 = {
      uint64TypeId := some 0
      unitTypeId := some 1
      boolTypeId := none
      uint32TypeId := none
    } := by
  have h := stateCellPlanTypesSuccessV1
  rw [stateCellPlanTypesExactSuccessV1] at h
  exact Except.ok.inj h.symm

/-- Exact field emitted by the generic state-account stage for the sole
    StateCell UInt64 declaration. It is not an independently supplied Plan. -/
def stateCellPlanStateFieldV1 : StateField := {
  sourceId := 0
  name := "count"
  accountIndex := 0
  byteOffset := 8
  byteWidth := 8
  endianness := .little
}

/-- The real production layout renderer yields the bytes certified below. -/
theorem stateCellPlanLayoutHashInputV1 :
    (layoutDomain ++ layoutSignature #[stateCellPlanStateFieldV1]).toUTF8 =
      "proof-forge-solana-layout-v1:1|0:count:0:8:8:u64-le".toUTF8 := by
  unfold layoutDomain layoutSignature layoutFieldSignature
    layoutFieldTypeSuffix stateCellPlanStateFieldV1
  decide

private abbrev stateCellPlanLayoutShaFinalStateV1 :
    ProofForgeV2.Crypto.Sha256State := #[
  0x0bbe897f, 0x0336e6fc, 0xe5387766, 0xb6e29ee6,
  0x1a492191, 0x5d0e84f5, 0x92317f12, 0xe93051a6]

set_option maxRecDepth 100000 in
set_option maxHeartbeats 5000000 in
/-- One-block kernel certificate over the sole production layout preimage.
    This replays `Crypto.sha256`; it is not a second hash implementation. -/
def stateCellPlanLayoutShaCertificateV1 :
    ProofForgeV2.Crypto.Sha256BlockCertificate
      "proof-forge-solana-layout-v1:1|0:count:0:8:8:u64-le".toUTF8
      "0bbe897f0336e6fce5387766b6e29ee61a4921915d0e84f592317f12e93051a6" := {
  finalState := stateCellPlanLayoutShaFinalStateV1
  trace := .step 0 0 ProofForgeV2.Crypto.sha256InitialState
    stateCellPlanLayoutShaFinalStateV1 stateCellPlanLayoutShaFinalStateV1
    (by decide) (.done 64 stateCellPlanLayoutShaFinalStateV1)
  hex_eq := by decide
}

theorem stateCellPlanLayoutMarkerV1 :
    layoutMarker #[stateCellPlanStateFieldV1] = 0x0bbe897f0336e6fc := by
  unfold layoutMarker layoutHashBytesV1
  rw [stateCellPlanLayoutHashInputV1]
  have hdigest := stateCellPlanLayoutShaCertificateV1.toHexCertificate.digest_eq
  change ProofForgeV2.Crypto.sha256
      "proof-forge-solana-layout-v1:1|0:count:0:8:8:u64-le".toUTF8 =
        ProofForgeV2.Crypto.sha256StateDigest
          stateCellPlanLayoutShaFinalStateV1 at hdigest
  rw [hdigest]
  unfold firstWordBE ProofForgeV2.Crypto.sha256StateDigest
    ProofForgeV2.Crypto.appendUInt32BE stateCellPlanLayoutShaFinalStateV1
  simp [Pure.pure, Bind.bind]
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellPlanStateAccountSomeV1 :
    (makeStateAccountV1 stateCellPlanTypesV1
      stateCellSemanticProgramDataV1.types
      stateCellSemanticProgramDataV1.logicalState).toOption.isSome = true := by
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1,
    stateCellLogicalStateV1, stateCellState0ValueV1]
  unfold makeStateAccountV1 containerLeafLayoutV1
    isAnonymousOptionTypeIdV1 abiByteWidthOfTypeV1
    maxStateFields stateHeaderBytes slotPitchOfByteWidth isIdentifier
    maxIdentifierBytes
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier
    ProofForgeV2.Targets.EnvelopeV1.requirePublicSolanaUintAbiOrInt64State
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isContainer
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isPrincipal
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isString
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isNamedAggregate
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isUInt64
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isSolanaUintAbiOrInt64
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.intWidthOf
    ProofForgeV2.Targets.EnvelopeV1.isSolanaAbiUintWidth
    ProofForgeV2.Targets.EnvelopeV1.byteWidthOfBitWidth
  have hname : "count".utf8ByteSize ≤ 240 := by decide
  have hmarker : layoutMarker #[{
      sourceId := 0
      name := "count"
      accountIndex := 0
      byteOffset := 8
      byteWidth := 8
      endianness := .little
    }] = 0x0bbe897f0336e6fc := by
    simpa only [stateCellPlanStateFieldV1] using stateCellPlanLayoutMarkerV1
  simp [hname, Pure.pure, Except.pure, Bind.bind, Except.bind,
    Except.toOption, hmarker]

def stateCellPlanStateAccountV1 :=
  (makeStateAccountV1 stateCellPlanTypesV1
    stateCellSemanticProgramDataV1.types
    stateCellSemanticProgramDataV1.logicalState).toOption.get
      stateCellPlanStateAccountSomeV1

theorem stateCellPlanStateAccountSuccessV1 :
    makeStateAccountV1 stateCellPlanTypesV1
      stateCellSemanticProgramDataV1.types
      stateCellSemanticProgramDataV1.logicalState =
        .ok stateCellPlanStateAccountV1 := by
  apply exceptToOptionGetSuccessV1

theorem stateCellPlanConstantsSuccessV1 :
    validateSolanaConstantTableV1 stateCellPlanTypesV1
      stateCellSemanticProgramDataV1.constants = .ok () := by
  rcases stateCellEmptySemanticTablesV1 with ⟨hconstants, _⟩
  unfold validateSolanaConstantTableV1
  rw [hconstants]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellPlanPureFnsSuccessV1 :
    buildPureFnTableV1 stateCellPlanTypesV1
      stateCellSemanticProgramDataV1.callables = .ok {
        byCallableId := #[none, none, none]
        paramCounts := #[]
        resultIsBool := #[]
        resultIsInt := #[]
      } := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, _hloops1, _hsteps1,
      _hid2, hkind2, _hname2, _hparams2, _hresult2, _hentry2,
      _hloops2, _hsteps2⟩
  unfold buildPureFnTableV1
  rw [stateCellPlanTypesValueV1, stateCellCallablesV1]
  simp [hkind0, hkind1, hkind2, Pure.pure, Except.pure, Bind.bind,
    Except.bind]

theorem stateCellPlanProgramNameV1 :
    stateCellSemanticProgramDataV1.qualifiedName.components.toArray.back! =
      "StateCell" := by
  unfold stateCellSemanticProgramDataV1 assembleProgramLoweringDataV1
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellPlanContextSomeV1 :
    (preparePlanLoweringContextV1 stateCellSemanticProgramDataV1 false
      true).toOption.isSome = true := by
  rcases stateCellEmptySemanticTablesV1 with
    ⟨_hconstants, hevents, herrors, hinvariants⟩
  have hcallableSize : stateCellSemanticProgramDataV1.callables.size = 3 := by
    simp [stateCellCallablesV1]
  have hrequirementSize :
      stateCellSemanticProgramDataV1.requirements.items.size = 3 := by
    simp [stateCellRequirementItemsV1]
  unfold preparePlanLoweringContextV1
  simp only [hinvariants, Array.isEmpty_empty, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, hcallableSize, maxEntries,
    hrequirementSize, ProofForgeV2.Targets.maxRequirementKinds]
  rw [stateCellPlanTypesSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [stateCellPlanConstantsSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [stateCellPlanStateAccountSuccessV1]
  dsimp only [Bind.bind, Except.bind]
  rw [hevents, herrors]
  simp only [Array.mapM_empty, Pure.pure, Except.pure]
  rw [stateCellPlanPureFnsSuccessV1, stateCellPlanProgramNameV1]
  rfl

/-- Context witness projected only after the exact production stage succeeds. -/
def stateCellPlanContextV1 :=
  (preparePlanLoweringContextV1 stateCellSemanticProgramDataV1 false
    true).toOption.get stateCellPlanContextSomeV1

theorem stateCellPlanContextSuccessV1 :
    preparePlanLoweringContextV1 stateCellSemanticProgramDataV1 false true =
      .ok stateCellPlanContextV1 := by
  apply exceptToOptionGetSuccessV1

end ProofForgeV2.Targets.Solana
