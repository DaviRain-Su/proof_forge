import ProofForgeV2.Targets.Solana.SbpfStateCellPlanV1

/-!
# StateCell Solana callable and Plan certificate

Kernel replay of the sole production callable/CFG lowerer, Handler builders,
source-order Plan accumulator, Plan finisher, and retained certificate
constructor. `StateCell` is only a minimal regression witness; no production
stage below dispatches on its contract or callable names.
-/

namespace ProofForgeV2.Targets.Solana
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1

namespace StateCellPlanCertificateV1

def expectedStateAccount : StateAccount := {
  index := 0
  name := "state"
  ownerPolicy := .currentProgram
  exactDataLen := 16
  headerOffset := 0
  headerWidth := 8
  initializedMarker := 0x0bbe897f0336e6fc
  payloadInitialization := .zeroAllFields
  fields := #[stateCellPlanStateFieldV1]
  stateLeaves := #[#[0]]
}

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateAccountValue :
    stateCellPlanStateAccountV1 = expectedStateAccount := by
  have hexact : makeStateAccountV1 stateCellPlanTypesV1
      stateCellSemanticProgramDataV1.types
      stateCellSemanticProgramDataV1.logicalState =
        .ok expectedStateAccount := by
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
        endianness := Endianness.little
      }] = 0x0bbe897f0336e6fc := by
      simpa only [stateCellPlanStateFieldV1] using stateCellPlanLayoutMarkerV1
    simp [hname, Pure.pure, Except.pure, Bind.bind, Except.bind,
      hmarker, stateCellPlanStateFieldV1, expectedStateAccount]
  rw [stateCellPlanStateAccountSuccessV1] at hexact
  exact Except.ok.inj hexact

def expectedTargetAccount : StateAccount := {
  expectedStateAccount with
    admitCallerRole := false
    admitProductExternalCall := true
}

def expectedContext : PlanLoweringContextV1 := {
  types := stateCellPlanTypesV1
  typeDecls := stateCellSemanticProgramDataV1.types
  stateAccount := expectedTargetAccount
  constants := stateCellSemanticProgramDataV1.constants
  events := #[]
  errors := #[]
  pureFns := {
    byCallableId := #[none, none, none]
    paramCounts := #[]
    resultIsBool := #[]
    resultIsInt := #[]
  }
  programName := "StateCell"
  admitCallerRole := false
}

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem contextValue : stateCellPlanContextV1 = expectedContext := by
  have h := stateCellPlanContextSuccessV1
  rcases stateCellEmptySemanticTablesV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  have hcallableSize : stateCellSemanticProgramDataV1.callables.size = 3 := by
    simp [stateCellCallablesV1]
  have hrequirementSize :
      stateCellSemanticProgramDataV1.requirements.items.size = 3 := by
    simp [stateCellRequirementItemsV1]
  unfold preparePlanLoweringContextV1 at h
  simp only [hinvariants, Array.isEmpty_empty, Bool.not_true,
    Bool.false_eq_true, ↓reduceIte, hcallableSize, maxEntries,
    hrequirementSize, ProofForgeV2.Targets.maxRequirementKinds] at h
  rw [stateCellPlanTypesSuccessV1] at h
  dsimp only [Bind.bind, Except.bind] at h
  rw [stateCellPlanConstantsSuccessV1] at h
  dsimp only [Bind.bind, Except.bind] at h
  rw [stateCellPlanStateAccountSuccessV1] at h
  rw [stateAccountValue] at h
  dsimp only [Bind.bind, Except.bind] at h
  rw [hevents, herrors] at h
  simp only [Array.mapM_empty, Pure.pure, Except.pure] at h
  rw [stateCellPlanPureFnsSuccessV1, stateCellPlanProgramNameV1] at h
  exact Except.ok.inj h.symm

def expectedParam : Param := {
  sourceId := 0
  name := "initial"
  dataOffset := 8
  byteWidth := 8
  endianness := .little
}

def expectedValue : LoweredValueV1 := {
  expr := .param 8
  depth := 1
  expandedNodes := 1
  dependencies := #[]
  isBool := false
}

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem probe :
    makeParamsV1 "initializer" stateCellPlanContextV1.types
      stateCellPlanContextV1.typeDecls stateCellCallable0V1.params =
        .ok (#[expectedParam], #[expectedValue]) := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _⟩
  rw [hparams0, _hparam0]
  unfold makeParamsV1
  rw [contextValue]
  unfold expectedContext
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isPrincipal,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isString,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isContainer,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isNamedAggregate,
    isAnonymousOptionTypeIdV1,
    ProofForgeV2.Targets.EnvelopeV1.requirePublicSolanaUintAbiOrInt64Param,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isSolanaUintAbiOrInt64,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.intWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.isSolanaAbiUintWidth,
    abiByteWidthOfTypeV1, ProofForgeV2.Targets.EnvelopeV1.byteWidthOfBitWidth,
    isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    expectedParam, expectedValue, maxParams, discriminatorBytes,
    slotPitchOfByteWidth, ProofForgeV2.Targets.EnvelopeV1.bitWidthOfByteWidth]
  rfl


set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem allocateProbe :
    allocateBlockParamSlotsV1 stateCellPlanContextV1.types
      stateCellCallable0V1.loopBounds stateCellCallable0V1.blocks
      #[expectedValue] = .ok #[expectedValue] := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, hloops0, _hsteps0, _⟩
  rw [hloops0, stateCellCallableBlockTablesV1.1]
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, hblockParams0, _hterm0, _⟩
  unfold allocateBlockParamSlotsV1
  simp [hblockParams0, Pure.pure, Except.pure, Bind.bind, Except.bind]

def expectedStore : Store := {
  accountIndex := 0
  byteOffset := 8
  value := .param 8
  byteWidth := 8
}

def expectedBlock : LoweredBlockV1 := {
  statements := #[.store expectedStore]
  values := #[expectedValue]
  segmentStart := 1
  armReadables := #[]
}

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem lowerBlockProbe :
    lowerBlockInstructionsV1 "initializer" .initialize
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns #[] stateCellCallable0BlockV1
      #[expectedValue] = .ok expectedBlock := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  unfold lowerBlockInstructionsV1
  rcases stateCellCallableInstructionTablesV1 with
    ⟨hinstructions0, _hinstructions1, _hinstructions2⟩
  rw [hinstructions0]
  rcases stateCellInstructionFieldValuesV1 with
    ⟨hresult0, hop0, _⟩
  have hleaf := findStateLeafFieldsV1_singleton_eq expectedTargetAccount 0 0
    stateCellPlanStateFieldV1 (by rfl) (by rfl) (by rfl)
  have hcurrent := currentValueWithArmsV1_eq_of_lt #[expectedValue] 1 1
    #[] 0 expectedValue (by decide) (by rfl)
  have hconsume := consumeCurrentSegmentV1_eq_of_dominating_leaf
    #[expectedValue] 1 1 0 expectedValue (by decide) (by rfl) (by rfl)
      (by rfl)
  have hpromote := promoteDominatingPureV1_eq_of_size_le 1
    #[expectedValue] #[] (by decide)
  simp only [expectedTargetAccount, expectedStateAccount,
    stateCellPlanStateFieldV1] at hleaf
  simp only [expectedValue] at hcurrent hconsume hpromote
  simp [hresult0, hop0, hleaf, hcurrent, hconsume, hpromote,
    LoweredValueV1.isAggregate_eq_isSome, Pure.pure, Except.pure, Bind.bind, Except.bind,
    expectedValue, expectedBlock, expectedStore, expectedTargetAccount, expectedStateAccount,
    stateCellPlanStateFieldV1,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isContainer,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isPrincipal,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isString,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isNamedAggregate,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isUInt64,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.intWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.isSolanaAbiUintWidth,
    ProofForgeV2.Targets.EnvelopeV1.isAbiIntWidth,
    ProofForgeV2.Targets.EnvelopeV1.bitWidthOfByteWidth,
    maxBodyStatements]
  rfl


def expectedBody : Array Statement :=
  #[.store expectedStore, .returnNone]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem regionProbe :
    emitRegionV1 "initializer" .initialize false 64 none
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns #[stateCellCallable0BlockV1] #[] #[] #[]
      1 0 #[expectedValue] =
        .ok (expectedBody, #[expectedValue], .closed) := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  have hblock := lowerBlockProbe
  rw [contextValue] at hblock
  simp only [expectedContext] at hblock
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hblock
  unfold emitRegionV1
  rcases stateCellBlockFieldValuesV1 with
    ⟨hblockId0, _hblockParams0, hterm0, _⟩
  simp [hblock, hblockId0, hterm0, expectedBlock, expectedBody,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem callableProbe :
    lowerCallableV1 "initializer" .initialize false 64 none
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns stateCellCallable0V1 =
        .ok { params := #[expectedParam], body := expectedBody } := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, hparams0, hparam0, _hresult0,
      hentry0, hloops0, hsteps0, _⟩
  rcases stateCellCallableBlockTablesV1 with
    ⟨hblocks0, _hblocks1, _hblocks2⟩
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, hblockParams0, _hterm0, _⟩
  unfold lowerCallableV1
  rw [hentry0, hsteps0, hblocks0, hloops0, hparams0, hparam0]
  have hparamsStage := probe
  rw [contextValue] at hparamsStage
  simp only [expectedContext] at hparamsStage
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hparamsStage
  rw [hparams0, hparam0] at hparamsStage
  simp only [expectedParam, expectedValue] at hparamsStage
  have hallocateStage := allocateProbe
  rw [contextValue] at hallocateStage
  simp only [expectedContext] at hallocateStage
  rw [stateCellPlanTypesValueV1] at hallocateStage
  rw [hloops0, hblocks0] at hallocateStage
  simp only [expectedValue] at hallocateStage
  have hregionStage := regionProbe
  rw [contextValue] at hregionStage
  simp only [expectedContext] at hregionStage
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hregionStage
  simp only [expectedValue] at hregionStage
  simp [hblockParams0, hparamsStage, hallocateStage, hregionStage, expectedParam, expectedBody,
    Pure.pure, Except.pure, Bind.bind, Except.bind,
    maxBodyStatements]


def incrementParam : Param := {
  sourceId := 0
  name := "delta"
  dataOffset := 8
  byteWidth := 8
  endianness := .little
}

def incrementValue0 : LoweredValueV1 := {
  expr := .param 8
  depth := 1
  expandedNodes := 1
  dependencies := #[]
  isBool := false
}

def incrementValue1 : LoweredValueV1 := {
  expr := .stateLoad 0 8
  depth := 1
  expandedNodes := 1
  dependencies := #[]
  isBool := false
}

def incrementValue2 : LoweredValueV1 := {
  expr := .checkedAdd (.stateLoad 0 8) (.param 8)
  depth := 2
  expandedNodes := 3
  dependencies := #[1, 0]
  isBool := false
}

def incrementValue3 : LoweredValueV1 := {
  expr := .stateLoad 0 8
  depth := 1
  expandedNodes := 1
  dependencies := #[]
  isBool := false
}

def incrementValues : Array LoweredValueV1 :=
  #[incrementValue0, incrementValue1, incrementValue2, incrementValue3]

def incrementStore : Store := {
  accountIndex := 0
  byteOffset := 8
  value := incrementValue2.expr
  byteWidth := 8
}

def incrementBlock : LoweredBlockV1 := {
  statements := #[.store incrementStore]
  values := incrementValues
  segmentStart := 3
  armReadables := #[1, 2]
}

def incrementBody : Array Statement :=
  #[.store incrementStore, .returnValue incrementValue3.expr]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementParamsProbe :
    makeParamsV1 "entry 'increment'" stateCellPlanContextV1.types
      stateCellPlanContextV1.typeDecls stateCellCallable1V1.params =
        .ok (#[incrementParam], #[incrementValue0]) := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      hparams1, hparam1, _⟩
  rw [hparams1, hparam1]
  unfold makeParamsV1
  rw [contextValue]
  unfold expectedContext
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isPrincipal,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isString,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isContainer,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isNamedAggregate,
    isAnonymousOptionTypeIdV1,
    ProofForgeV2.Targets.EnvelopeV1.requirePublicSolanaUintAbiOrInt64Param,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isSolanaUintAbiOrInt64,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.intWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.isSolanaAbiUintWidth,
    abiByteWidthOfTypeV1, ProofForgeV2.Targets.EnvelopeV1.byteWidthOfBitWidth,
    isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    incrementParam, incrementValue0, maxParams, discriminatorBytes,
    slotPitchOfByteWidth, ProofForgeV2.Targets.EnvelopeV1.bitWidthOfByteWidth]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementAllocateProbe :
    allocateBlockParamSlotsV1 stateCellPlanContextV1.types
      stateCellCallable1V1.loopBounds stateCellCallable1V1.blocks
      #[incrementValue0] = .ok #[incrementValue0] := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, hloops1, _⟩
  rw [hloops1, stateCellCallableBlockTablesV1.2.1]
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, _hblockParams0, _hterm0, _hblockId1, hblockParams1, _⟩
  unfold allocateBlockParamSlotsV1
  simp [hblockParams1, Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementBlockProbe :
    lowerBlockInstructionsV1 "entry 'increment'" .mutate
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns #[] stateCellCallable1BlockV1
      #[incrementValue0] = .ok incrementBlock := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableInstructionTablesV1 with
    ⟨_hinstructions0, hinstructions1, _hinstructions2⟩
  unfold lowerBlockInstructionsV1
  rw [hinstructions1]
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult0, _hop0, hresult10, hop10, hresult11, hop11,
      hresult12, hop12, hresult13, hop13, _⟩
  have hleaf := findStateLeafFieldsV1_singleton_eq expectedTargetAccount 0 0
    stateCellPlanStateFieldV1 (by rfl) (by rfl) (by rfl)
  simp only [expectedTargetAccount, expectedStateAccount,
    stateCellPlanStateFieldV1] at hleaf
  have happend1 := appendResultValueV1_eq_ok 0 #[incrementValue0]
    ({ valueId := 1, typeId := 0 } : ValueDefV1) incrementValue1
    (by decide) (by rfl) (by decide)
  have hcurrent1 := currentValueWithArmsV1_eq_of_segment_le
    #[incrementValue0, incrementValue1] 1 1 #[] 1 incrementValue1
    (by decide) (by rfl)
  have hcurrent0 := currentValueWithArmsV1_eq_of_lt
    #[incrementValue0, incrementValue1] 1 1 #[] 0 incrementValue0
    (by decide) (by rfl)
  have hadd := makeCheckedAddValueV1_uint64_eq 1 0 incrementValue1
    incrementValue0 (by rfl) (by rfl) (by rfl) (by rfl)
      (by decide) (by decide) (by decide)
  have happend2 := appendResultValueV1_eq_ok 0
    #[incrementValue0, incrementValue1]
    ({ valueId := 2, typeId := 0 } : ValueDefV1) incrementValue2
    (by decide) (by rfl) (by decide)
  have hcurrent2 := currentValueWithArmsV1_eq_of_segment_le
    #[incrementValue0, incrementValue1, incrementValue2] 1 1 #[] 2
      incrementValue2 (by decide) (by rfl)
  have hconsume2 := consumeCurrentSegmentV1_eq_of_complete_walk
    #[incrementValue0, incrementValue1, incrementValue2] 1 1 2
      incrementValue2 (by decide) (by rfl) (by rfl)
  have hpromote := promoteDominatingPureV1_two_after_block_entry 1
    #[incrementValue0, incrementValue1, incrementValue2] (by decide)
  have hadmit := admitUIntWidthResultTypeV1_eq_ok stateCellPlanTypesV1 0 64
    (by rw [stateCellPlanTypesValueV1]; rfl) (by rfl)
  simp only [stateCellPlanTypesValueV1] at hadmit
  obtain ⟨haddAnd, haddOr, haddShl, haddShr, haddAdd, haddSub, haddMul,
      haddDiv, haddMod, haddBitAnd, haddBitOr, haddBitXor⟩ :=
    binaryOpAddClassificationsV1
  simp only [incrementValue0, incrementValue1, incrementValue2] at happend1 hcurrent1 hcurrent0 hadd happend2 hcurrent2 hconsume2 hpromote
  simp [hresult10, hop10, hresult11, hop11, hresult12, hop12,
    hresult13, hop13, hleaf, happend1, hcurrent1, hcurrent0, haddAnd,
    haddOr, haddShl, haddShr, haddAdd, haddSub, haddMul, haddDiv, haddMod,
    haddBitAnd, haddBitOr, haddBitXor, hadd, hadmit,
    happend2, hcurrent2, hconsume2, hpromote,
    LoweredValueV1.isAggregate_eq_isSome, mkStateLoadExpr_uint64,
    isSolanaBodyUintWidth_uint64V1,
    semanticCallableModeMutate_ne_viewV1,
    isAnonymousOptionTypeIdV1, Pure.pure, Except.pure, Bind.bind, Except.bind,
    incrementValue0, incrementValue1, incrementValue2,
    incrementValue3, incrementValues, incrementBlock, incrementStore,
    expectedTargetAccount, expectedStateAccount, stateCellPlanStateFieldV1,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isContainer,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isPrincipal,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isString,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isNamedAggregate,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isUInt64,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.intWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.isSolanaAbiUintWidth,
    ProofForgeV2.Targets.EnvelopeV1.isAbiIntWidth,
    ProofForgeV2.Targets.EnvelopeV1.bitWidthOfByteWidth,
    maxBodyStatements]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementRegionProbe :
    emitRegionV1 "entry 'increment'" .mutate false 64 none
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns #[stateCellCallable1BlockV1] #[] #[] #[]
      1 0 #[incrementValue0] =
        .ok (incrementBody, incrementValues, .closed) := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  have hblock := incrementBlockProbe
  rw [contextValue] at hblock
  simp only [expectedContext] at hblock
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hblock
  simp only [incrementValue0, incrementBlock, incrementValues,
    incrementValue1, incrementValue2, incrementValue3, incrementStore] at hblock
  have hcurrent := currentValueWithArmsV1_eq_of_segment_le
    incrementValues 1 3 #[1, 2] 3 incrementValue3 (by decide) (by rfl)
  have hconsume := consumeCurrentSegmentV1_eq_of_complete_walk
    incrementValues 1 3 3 incrementValue3 (by decide) (by rfl) (by rfl)
  simp only [incrementValues, incrementValue0, incrementValue1,
    incrementValue2, incrementValue3] at hcurrent hconsume
  unfold emitRegionV1
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, _hblockParams0, _hterm0, hblockId1, _hblockParams1,
      hterm1, _⟩
  simp [hblock, hblockId1, hterm1, hcurrent, hconsume,
    incrementBody, incrementValues, incrementValue0, incrementValue1,
    incrementValue2, incrementValue3, incrementStore,
    Pure.pure, Except.pure, Bind.bind, Except.bind]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementCallableProbe :
    lowerCallableV1 "entry 'increment'" .mutate false 64 none
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns stateCellCallable1V1 =
        .ok { params := #[incrementParam], body := incrementBody } := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      hparams1, hparam1, _hresult1, hentry1, hloops1, hsteps1, _⟩
  rcases stateCellCallableBlockTablesV1 with
    ⟨_hblocks0, hblocks1, _hblocks2⟩
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, _hblockParams0, _hterm0, _hblockId1, hblockParams1, _⟩
  unfold lowerCallableV1
  rw [hentry1, hsteps1, hblocks1, hloops1, hparams1, hparam1]
  have hparamsStage := incrementParamsProbe
  rw [contextValue] at hparamsStage
  simp only [expectedContext] at hparamsStage
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hparamsStage
  rw [hparams1, hparam1] at hparamsStage
  simp only [incrementParam, incrementValue0] at hparamsStage
  have hallocateStage := incrementAllocateProbe
  rw [contextValue] at hallocateStage
  simp only [expectedContext] at hallocateStage
  rw [stateCellPlanTypesValueV1] at hallocateStage
  rw [hloops1, hblocks1] at hallocateStage
  simp only [incrementValue0] at hallocateStage
  have hregionStage := incrementRegionProbe
  rw [contextValue] at hregionStage
  simp only [expectedContext] at hregionStage
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hregionStage
  simp only [incrementValue0, incrementBody, incrementValues,
    incrementValue1, incrementValue2, incrementValue3, incrementStore] at hregionStage
  simp [hblockParams1, hparamsStage, hallocateStage, hregionStage,
    incrementParam, incrementBody, incrementStore, incrementValue2,
    incrementValue3,
    Pure.pure, Except.pure, Bind.bind, Except.bind, maxBodyStatements]

def getValue : LoweredValueV1 := {
  expr := .stateLoad 0 8
  depth := 1
  expandedNodes := 1
  dependencies := #[]
  isBool := false
}

def getValues : Array LoweredValueV1 := #[getValue]

def getBlock : LoweredBlockV1 := {
  statements := #[]
  values := getValues
  segmentStart := 0
  armReadables := #[]
}

def getBody : Array Statement := #[.returnValue getValue.expr]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getParamsProbe :
    makeParamsV1 "entry 'get'" stateCellPlanContextV1.types
      stateCellPlanContextV1.typeDecls stateCellCallable2V1.params =
        .ok (#[], #[]) := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, _hloops1, _hsteps1,
      _hid2, _hkind2, _hname2, hparams2, _⟩
  rw [hparams2]
  unfold makeParamsV1
  simp [Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getAllocateProbe :
    allocateBlockParamSlotsV1 stateCellPlanContextV1.types
      stateCellCallable2V1.loopBounds stateCellCallable2V1.blocks #[] =
        .ok #[] := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, _hloops1, _hsteps1,
      _hid2, _hkind2, _hname2, _hparams2, _hresult2, _hentry2,
      hloops2, _⟩
  rcases stateCellCallableBlockTablesV1 with
    ⟨_hblocks0, _hblocks1, hblocks2⟩
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, _hblockParams0, _hterm0, _hblockId1, _hblockParams1,
      _hterm1, _hblockId2, hblockParams2, _⟩
  rw [hloops2, hblocks2]
  unfold allocateBlockParamSlotsV1
  simp [hblockParams2, Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getBlockProbe :
    lowerBlockInstructionsV1 "entry 'get'" .view
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns #[] stateCellCallable2BlockV1 #[] =
        .ok getBlock := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableInstructionTablesV1 with
    ⟨_hinstructions0, _hinstructions1, hinstructions2⟩
  unfold lowerBlockInstructionsV1
  rw [hinstructions2]
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult0, _hop0, _hresult10, _hop10, _hresult11, _hop11,
      _hresult12, _hop12, _hresult13, _hop13, hresult20, hop20⟩
  have hleaf := findStateLeafFieldsV1_singleton_eq expectedTargetAccount 0 0
    stateCellPlanStateFieldV1 (by rfl) (by rfl) (by rfl)
  simp only [expectedTargetAccount, expectedStateAccount,
    stateCellPlanStateFieldV1] at hleaf
  have happend := appendResultValueV1_eq_ok 0 #[]
    ({ valueId := 0, typeId := 0 } : ValueDefV1) getValue
    (by decide) (by rfl) (by decide)
  simp only [getValue] at happend
  simp [hresult20, hop20, hleaf, happend, mkStateLoadExpr_uint64,
    isAnonymousOptionTypeIdV1, Pure.pure, Except.pure, Bind.bind, Except.bind,
    getValue, getValues, getBlock, expectedTargetAccount, expectedStateAccount,
    stateCellPlanStateFieldV1,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isContainer,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isPrincipal,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isString,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isNamedAggregate,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.isUInt64,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.intWidthOf,
    ProofForgeV2.Targets.EnvelopeV1.isSolanaAbiUintWidth,
    ProofForgeV2.Targets.EnvelopeV1.isAbiIntWidth,
    ProofForgeV2.Targets.EnvelopeV1.bitWidthOfByteWidth,
    maxBodyStatements]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getRegionProbe :
    emitRegionV1 "entry 'get'" .view false 64 none
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns #[stateCellCallable2BlockV1] #[] #[] #[]
      1 0 #[] = .ok (getBody, getValues, .closed) := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  have hblock := getBlockProbe
  rw [contextValue] at hblock
  simp only [expectedContext] at hblock
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hblock
  simp only [getBlock, getValues, getValue] at hblock
  have hcurrent := currentValueWithArmsV1_eq_of_segment_le
    getValues 0 0 #[] 0 getValue (by decide) (by rfl)
  have hconsume := consumeCurrentSegmentV1_eq_of_complete_walk
    getValues 0 0 0 getValue (by decide) (by rfl) (by rfl)
  simp only [getValues, getValue] at hcurrent hconsume
  unfold emitRegionV1
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, _hblockParams0, _hterm0, _hblockId1, _hblockParams1,
      _hterm1, hblockId2, _hblockParams2, hterm2⟩
  simp [hblock, hblockId2, hterm2, hcurrent, hconsume,
    getBody, getValues, getValue, Pure.pure, Except.pure, Bind.bind,
    Except.bind]
  rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getCallableProbe :
    lowerCallableV1 "entry 'get'" .view false 64 none
      stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns stateCellCallable2V1 =
        .ok { params := #[], body := getBody } := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, _hloops1, _hsteps1,
      _hid2, _hkind2, _hname2, hparams2, _hresult2, hentry2,
      hloops2, hsteps2⟩
  rcases stateCellCallableBlockTablesV1 with
    ⟨_hblocks0, _hblocks1, hblocks2⟩
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hblockId0, _hblockParams0, _hterm0, _hblockId1, _hblockParams1,
      _hterm1, _hblockId2, hblockParams2, _⟩
  unfold lowerCallableV1
  rw [hentry2, hsteps2, hblocks2, hloops2, hparams2]
  have hparamsStage := getParamsProbe
  rw [contextValue] at hparamsStage
  simp only [expectedContext] at hparamsStage
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hparamsStage
  rw [hparams2] at hparamsStage
  have hallocateStage := getAllocateProbe
  rw [contextValue] at hallocateStage
  simp only [expectedContext] at hallocateStage
  rw [stateCellPlanTypesValueV1] at hallocateStage
  rw [hloops2, hblocks2] at hallocateStage
  have hregionStage := getRegionProbe
  rw [contextValue] at hregionStage
  simp only [expectedContext] at hregionStage
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hregionStage
  simp only [getBody, getValues, getValue] at hregionStage
  simp [hblockParams2, hparamsStage, hallocateStage, hregionStage,
    getBody, getValue, Pure.pure, Except.pure, Bind.bind, Except.bind,
    maxBodyStatements]

def expectedInitializerHandler : Handler := {
  name := "initialize"
  discriminator := instructionDiscriminator "initialize" #[expectedParam]
  params := #[expectedParam]
  mode := .initialize
  resultKind := .u64
  accountAccess := accessFor expectedTargetAccount .initialize
  body := expectedBody
}

def expectedIncrementHandler : Handler := {
  name := "increment"
  discriminator := instructionDiscriminator "increment" #[incrementParam]
  params := #[incrementParam]
  mode := .mutate
  resultKind := .u64
  accountAccess := accessFor expectedTargetAccount .mutate
  body := incrementBody
}

def expectedGetHandler : Handler := {
  name := "get"
  discriminator := instructionDiscriminator "get" #[]
  params := #[]
  mode := .view
  resultKind := .u64
  accountAccess := accessFor expectedTargetAccount .view
  body := getBody
}

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem initializerHandlerProbe :
    makeInitializerV1 stateCellPlanContextV1.types
      stateCellPlanContextV1.typeDecls stateCellPlanContextV1.stateAccount
      stateCellPlanContextV1.constants stateCellPlanContextV1.pureFns
      stateCellCallable0V1 = .ok expectedInitializerHandler := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, hname0, _hparams0, _hparam0, hresult0, _⟩
  unfold makeInitializerV1
  rw [hname0, hresult0]
  have hcallable := callableProbe
  rw [contextValue] at hcallable
  simp only [expectedContext] at hcallable
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hcallable
  simp only [expectedParam, expectedBody, expectedStore] at hcallable
  obtain ⟨hpublic, _hu64Bool⟩ := publicUInt64HandlerClassificationsV1
  simp [hcallable, expectedInitializerHandler, expectedParam, expectedBody,
    expectedStore, hpublic,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementHandlerProbe :
    makeEntryV1 stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns stateCellCallable1V1 =
        .ok expectedIncrementHandler := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, hkind1, hname1,
      _hparams1, _hparam1, hresult1, _⟩
  unfold makeEntryV1
  rw [hname1, hresult1, hkind1]
  have hcallable := incrementCallableProbe
  rw [contextValue] at hcallable
  simp only [expectedContext] at hcallable
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hcallable
  simp only [incrementParam, incrementBody, incrementStore, incrementValue2,
    incrementValue3] at hcallable
  obtain ⟨hpublic, hu64Bool⟩ := publicUInt64HandlerClassificationsV1
  have hsafeName : "increment".utf8ByteSize ≤ 240 := by decide
  have howner :
      (toString "entry '" ++ toString "increment" ++ toString "'") =
        "entry 'increment'" := by rfl
  simp [hcallable, expectedIncrementHandler, incrementParam, incrementBody,
    incrementStore, incrementValue2, incrementValue3, hpublic, hu64Bool,
    hsafeName, howner, isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getHandlerProbe :
    makeEntryV1 stateCellPlanContextV1.types stateCellPlanContextV1.typeDecls
      stateCellPlanContextV1.stateAccount stateCellPlanContextV1.constants
      stateCellPlanContextV1.pureFns stateCellCallable2V1 =
        .ok expectedGetHandler := by
  rw [contextValue]
  simp only [expectedContext]
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1]
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, _hloops1, _hsteps1,
      _hid2, hkind2, hname2, _hparams2, hresult2, _⟩
  unfold makeEntryV1
  rw [hname2, hresult2, hkind2]
  have hcallable := getCallableProbe
  rw [contextValue] at hcallable
  simp only [expectedContext] at hcallable
  rw [stateCellPlanTypesValueV1, stateCellTypesExactV1] at hcallable
  simp only [getBody, getValue] at hcallable
  obtain ⟨hpublic, hu64Bool⟩ := publicUInt64HandlerClassificationsV1
  have hsafeName : "get".utf8ByteSize ≤ 240 := by decide
  have howner :
      (toString "entry '" ++ toString "get" ++ toString "'") =
        "entry 'get'" := by rfl
  simp [hcallable, expectedGetHandler, getBody, getValue,
    hpublic, hu64Bool, hsafeName, howner, isIdentifier, maxIdentifierBytes,
    ProofForgeV2.Targets.EnvelopeV1.isAsciiIdentifier,
    ProofForgeV2.Targets.EnvelopeV1.PilotTypeClosureV1.uintWidthOf,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

def callableStateAfterInitializer : PlanCallableLoweringStateV1 := {
  initializer := some expectedInitializerHandler
  entries := #[]
  fns := #[]
}

def callableStateAfterIncrement : PlanCallableLoweringStateV1 := {
  initializer := some expectedInitializerHandler
  entries := #[expectedIncrementHandler]
  fns := #[]
}

def expectedCallableState : PlanCallableLoweringStateV1 := {
  initializer := some expectedInitializerHandler
  entries := #[expectedIncrementHandler, expectedGetHandler]
  fns := #[]
}

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem initializerItemProbe :
    lowerPlanCallableItemV1 stateCellPlanContextV1
      initialPlanCallableLoweringStateV1 stateCellCallable0V1 =
        .ok callableStateAfterInitializer := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, hkind0, _⟩
  unfold lowerPlanCallableItemV1
  rw [hkind0, initializerHandlerProbe]
  simp [initialPlanCallableLoweringStateV1, callableStateAfterInitializer,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem incrementItemProbe :
    lowerPlanCallableItemV1 stateCellPlanContextV1
      callableStateAfterInitializer stateCellCallable1V1 =
        .ok callableStateAfterIncrement := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, hkind1, _⟩
  unfold lowerPlanCallableItemV1
  rw [hkind1, incrementHandlerProbe]
  simp [callableStateAfterInitializer, callableStateAfterIncrement,
    maxEntries, Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem getItemProbe :
    lowerPlanCallableItemV1 stateCellPlanContextV1
      callableStateAfterIncrement stateCellCallable2V1 =
        .ok expectedCallableState := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparam0, _hresult0,
      _hentry0, _hloops0, _hsteps0, _hid1, _hkind1, _hname1,
      _hparams1, _hparam1, _hresult1, _hentry1, _hloops1, _hsteps1,
      _hid2, hkind2, _⟩
  unfold lowerPlanCallableItemV1
  rw [hkind2, getHandlerProbe]
  simp [callableStateAfterIncrement, expectedCallableState, maxEntries,
    Pure.pure, Except.pure, Bind.bind, Except.bind]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem callableBodiesProbe :
    lowerPlanCallableBodiesV1 stateCellPlanContextV1
      stateCellSemanticProgramDataV1.callables = .ok expectedCallableState := by
  rw [stateCellCallablesV1]
  unfold lowerPlanCallableBodiesV1 lowerPlanCallableItemsV1
  rw [initializerItemProbe]
  dsimp only [Bind.bind, Except.bind]
  rw [lowerPlanCallableItemsV1]
  rw [incrementItemProbe]
  dsimp only [Bind.bind, Except.bind]
  rw [lowerPlanCallableItemsV1]
  rw [getItemProbe]
  dsimp only [Bind.bind, Except.bind]
  rw [lowerPlanCallableItemsV1]

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem finishPlanSomeProbe :
    (finishPlanLoweringV1 stateCellPlanContextV1
      expectedCallableState).toOption.isSome = true := by
  unfold finishPlanLoweringV1
  simp [expectedCallableState, Pure.pure, Except.pure, Bind.bind, Except.bind,
    Except.toOption]

def projectedPlan :=
  (finishPlanLoweringV1 stateCellPlanContextV1
    expectedCallableState).toOption.get finishPlanSomeProbe

theorem finishPlanProbe :
    finishPlanLoweringV1 stateCellPlanContextV1 expectedCallableState =
      .ok projectedPlan := by
  apply exceptToOptionGetSuccessV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem certifiedPlanSomeProbe :
    (certifyPlanLoweringV1 stateCellSemanticProgramDataV1 false true).toOption.isSome =
      true := by
  exact certifyPlanLoweringV1_toOption_isSome_of_stages
    stateCellSemanticProgramDataV1 false true stateCellPlanContextV1
    expectedCallableState projectedPlan stateCellPlanContextSuccessV1
    callableBodiesProbe finishPlanProbe

def projectedCertifiedPlan :=
  (certifyPlanLoweringV1 stateCellSemanticProgramDataV1 false true).toOption.get
    certifiedPlanSomeProbe

theorem certifiedPlanProbe :
    certifyPlanLoweringV1 stateCellSemanticProgramDataV1 false true =
      .ok projectedCertifiedPlan := by
  apply exceptToOptionGetSuccessV1

end StateCellPlanCertificateV1

/-- Plan projected only after the exact production context, callable, and
    finishing stages succeed. -/
abbrev stateCellLoweredPlanV1 :=
  StateCellPlanCertificateV1.projectedPlan

/-- Retained certificate projected only after `certifyPlanLoweringV1`
    succeeds on the real StateCell Semantic carrier. -/
abbrev stateCellCertifiedPlanV1 :=
  StateCellPlanCertificateV1.projectedCertifiedPlan

theorem stateCellCertifiedPlanSuccessV1 :
    certifyPlanLoweringV1 stateCellSemanticProgramDataV1 false true =
      .ok stateCellCertifiedPlanV1 := by
  exact StateCellPlanCertificateV1.certifiedPlanProbe

/-- The retained certificate contains the same Plan produced by the exact
    finishing-stage equation above. -/
theorem stateCellCertifiedPlanValueV1 :
    stateCellCertifiedPlanV1.plan = stateCellLoweredPlanV1 := by
  have hcontext : stateCellCertifiedPlanV1.context = stateCellPlanContextV1 := by
    exact Except.ok.inj
      (stateCellCertifiedPlanV1.contextSuccess.symm.trans
        stateCellPlanContextSuccessV1)
  have hcallables : stateCellCertifiedPlanV1.callables =
      StateCellPlanCertificateV1.expectedCallableState := by
    have hsuccess := stateCellCertifiedPlanV1.callablesSuccess
    rw [hcontext] at hsuccess
    exact Except.ok.inj
      (hsuccess.symm.trans
        StateCellPlanCertificateV1.callableBodiesProbe)
  have hfinish := stateCellCertifiedPlanV1.finishSuccess
  rw [hcontext, hcallables] at hfinish
  exact Except.ok.inj
    (hfinish.symm.trans StateCellPlanCertificateV1.finishPlanProbe)

end ProofForgeV2.Targets.Solana
