import ProofForgeV2.Targets.Solana.SbpfStateCellProductionStructureV1

/-!
# Solana StateCell production encoding certificate
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


private theorem stateCellInstructionInversionsV1 :
    ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable0Instruction0V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction0V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction1V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction2V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable1Instruction3V1 3 ∧
      ExactMidOffsetInvertAtV1 encodeInstructionV1 decodeInstructionV1
        stateCellCallable2Instruction0V1 3 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨h00Result, h00Op, h10Result, h10Op, h11Result, h11Op,
      h12Result, h12Op, h13Result, h13Op, h20Result, h20Op⟩
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_⟩
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable0Instruction0V1 3
      (by decide)
    · rw [h00Result]
      exact exactAt_optionValueDefV1 none 4 (by decide)
    · rw [h00Op]
      exact exactAt_semanticOp_stateStoreV1 0 0 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction0V1 3
      (by decide)
    · rw [h10Result]
      exact exactAt_optionValueDefV1 (some { valueId := 1, typeId := 0 }) 4
        (by decide)
    · rw [h10Op]
      exact exactAt_semanticOp_stateLoadV1 0 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction1V1 3
      (by decide)
    · rw [h11Result]
      exact exactAt_optionValueDefV1 (some { valueId := 2, typeId := 0 }) 4
        (by decide)
    · rw [h11Op]
      exact exactAt_semanticOp_binaryAddV1 1 0 4 (by decide) (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction2V1 3
      (by decide)
    · rw [h12Result]
      exact exactAt_optionValueDefV1 none 4 (by decide)
    · rw [h12Op]
      exact exactAt_semanticOp_stateStoreV1 0 2 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable1Instruction3V1 3
      (by decide)
    · rw [h13Result]
      exact exactAt_optionValueDefV1 (some { valueId := 3, typeId := 0 }) 4
        (by decide)
    · rw [h13Op]
      exact exactAt_semanticOp_stateLoadV1 0 4 (by decide)
  · apply exactAt_instruction_of_fieldsV1 stateCellCallable2Instruction0V1 3
      (by decide)
    · rw [h20Result]
      exact exactAt_optionValueDefV1 (some { valueId := 0, typeId := 0 }) 4
        (by decide)
    · rw [h20Op]
      exact exactAt_semanticOp_stateLoadV1 0 4 (by decide)

private theorem stateCellBlockInversionsV1 :
    ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1
        stateCellCallable0BlockV1 2 ∧
      ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1
        stateCellCallable1BlockV1 2 ∧
      ExactMidOffsetInvertAtV1 encodeBlockV1 decodeBlockV1
        stateCellCallable2BlockV1 2 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_h0Id, h0Params, h0Terminator, _h1Id, h1Params, h1Terminator,
      _h2Id, h2Params, h2Terminator⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨h0Instructions, h1Instructions, h2Instructions⟩
  rcases stateCellInstructionInversionsV1 with
    ⟨h00, h10, h11, h12, h13, h20⟩
  refine ⟨?_, ?_, ?_⟩
  · apply exactAt_block_of_fieldsV1 stateCellCallable0BlockV1 2 (by decide)
    · rw [h0Params]
      exact exactAt_array_emptyV1 encodeBlockParameterV1
        decodeBlockParameterV1 maxArrayElements 3
    · rw [h0Instructions]
      exact exactAt_array_one_of_exactAtV1 encodeInstructionV1
        decodeInstructionV1 maxArrayElements (by decide)
        stateCellCallable0Instruction0V1 3 h00
    · rw [h0Terminator]
      exact exactAt_terminatorReturnV1 none 3 (by decide)
  · apply exactAt_block_of_fieldsV1 stateCellCallable1BlockV1 2 (by decide)
    · rw [h1Params]
      exact exactAt_array_emptyV1 encodeBlockParameterV1
        decodeBlockParameterV1 maxArrayElements 3
    · rw [h1Instructions]
      exact exactAt_array_four_of_exactAtV1 encodeInstructionV1
        decodeInstructionV1 maxArrayElements (by decide) (by decide)
        stateCellCallable1Instruction0V1 stateCellCallable1Instruction1V1
        stateCellCallable1Instruction2V1 stateCellCallable1Instruction3V1
        3 h10 h11 h12 h13
    · rw [h1Terminator]
      exact exactAt_terminatorReturnV1 (some 3) 3 (by decide)
  · apply exactAt_block_of_fieldsV1 stateCellCallable2BlockV1 2 (by decide)
    · rw [h2Params]
      exact exactAt_array_emptyV1 encodeBlockParameterV1
        decodeBlockParameterV1 maxArrayElements 3
    · rw [h2Instructions]
      exact exactAt_array_one_of_exactAtV1 encodeInstructionV1
        decodeInstructionV1 maxArrayElements (by decide)
        stateCellCallable2Instruction0V1 3 h20
    · rw [h2Terminator]
      exact exactAt_terminatorReturnV1 (some 0) 3 (by decide)

private theorem stateCellCallableInversionsV1 :
    ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        stateCellCallable0V1 1 ∧
      ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        stateCellCallable1V1 1 ∧
      ExactMidOffsetInvertAtV1 encodeCallableV1 decodeCallableV1
        stateCellCallable2V1 1 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_h0Id, h0Kind, h0Name, h0Params, h0Parameter, h0Result, _h0Entry,
      h0Loops, h0Steps, _h1Id, h1Kind, h1Name, h1Params, h1Parameter,
      h1Result, _h1Entry, h1Loops, h1Steps, _h2Id, h2Kind, h2Name,
      h2Params, h2Result, _h2Entry, h2Loops, h2Steps⟩
  rcases stateCellCallableBlockTablesV1 with ⟨h0Blocks, h1Blocks, h2Blocks⟩
  rcases stateCellBlockInversionsV1 with ⟨h0Block, h1Block, h2Block⟩
  refine ⟨?_, ?_, ?_⟩
  · apply exactAt_callable_of_fieldsV1 stateCellCallable0V1 1 (by decide)
    · rw [h0Kind]
      exact exactAt_callableKindV1 .initializer 2 (by decide)
    · rw [h0Name]
      exact exactAt_option_noneV1 encodeString decodeString 2
    · rw [h0Params]
      apply exactAt_array_one_of_exactAtV1 encodeParameterV1 decodeParameterV1
        maxArrayElements (by decide) stateCellCallable0Parameter0V1 2
      rw [h0Parameter]
      exact exactAt_parameter_publicV1 0 0 "initial" (by rfl) 2 (by decide)
    · rw [h0Result]
      exact exactAt_callableResultV1
        ({ typeId := 1, visibility := .public_ } : CallableResultV1) 2
        (by decide) (by decide)
    · rw [h0Blocks]
      exact exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1
        maxArrayElements (by decide) stateCellCallable0BlockV1 2 h0Block
    · rw [h0Loops]
      exact exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1
        maxArrayElements 2
    · rw [h0Steps]
      exact exactAt_option_noneV1
        (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2
  · apply exactAt_callable_of_fieldsV1 stateCellCallable1V1 1 (by decide)
    · rw [h1Kind]
      exact exactAt_callableKindV1 .entry 2 (by decide)
    · rw [h1Name]
      exact exactAt_optionString_some_identifierV1 "increment" (by rfl) 2
    · rw [h1Params]
      apply exactAt_array_one_of_exactAtV1 encodeParameterV1 decodeParameterV1
        maxArrayElements (by decide) stateCellCallable1Parameter0V1 2
      rw [h1Parameter]
      exact exactAt_parameter_publicV1 0 0 "delta" (by rfl) 2 (by decide)
    · rw [h1Result]
      exact exactAt_callableResultV1
        ({ typeId := 0, visibility := .public_ } : CallableResultV1) 2
        (by decide) (by decide)
    · rw [h1Blocks]
      exact exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1
        maxArrayElements (by decide) stateCellCallable1BlockV1 2 h1Block
    · rw [h1Loops]
      exact exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1
        maxArrayElements 2
    · rw [h1Steps]
      exact exactAt_option_noneV1
        (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2
  · apply exactAt_callable_of_fieldsV1 stateCellCallable2V1 1 (by decide)
    · rw [h2Kind]
      exact exactAt_callableKindV1 .view 2 (by decide)
    · rw [h2Name]
      exact exactAt_optionString_some_identifierV1 "get" (by rfl) 2
    · rw [h2Params]
      exact exactAt_array_emptyV1 encodeParameterV1 decodeParameterV1
        maxArrayElements 2
    · rw [h2Result]
      exact exactAt_callableResultV1
        ({ typeId := 0, visibility := .public_ } : CallableResultV1) 2
        (by decide) (by decide)
    · rw [h2Blocks]
      exact exactAt_array_one_of_exactAtV1 encodeBlockV1 decodeBlockV1
        maxArrayElements (by decide) stateCellCallable2BlockV1 2 h2Block
    · rw [h2Loops]
      exact exactAt_array_emptyV1 encodeLoopBoundV1 decodeLoopBoundV1
        maxArrayElements 2
    · rw [h2Steps]
      exact exactAt_option_noneV1
        (fun value : UInt64 => pure (encodeU64le value)) decodeU64le 2

/-- Source-derived qualified-name topology. The equation observes the output of
    the sole production identity lowerer; it is not a supplied Semantic AST. -/
private theorem stateCellQualifiedNameComponentsV1 :
    renderQualifiedNameComponents stateCellSemanticProgramDataV1.qualifiedName =
      .ok #["ProofForgeV2", "Examples", "StateCell", "ProofForgeV2",
        "Examples", "StateCell"] := by
  rfl

private theorem encodePublicVisibilityV1 :
    encodeVisibilityV1 (.public_ : VisibilityV1) =
      .ok (taggedBytesV1 "Visibility.Public" #[]) := by
  simp only [encodeVisibilityV1, encodeNullary]
  exact encodeTagged_eq_okV1 "Visibility.Public" #[]
    (by decide) (by decide) (by decide) (by decide) (by decide)

private theorem stateCellQualifiedNameEncodingV1 :
    ∃ bytes,
      encodeQualifiedName stateCellSemanticProgramDataV1.qualifiedName = .ok bytes ∧
        bytes.size ≤ 1024 := by
  let b0 := (encodeU32le (UInt32.ofNat "ProofForgeV2".toUTF8.size)).append
    "ProofForgeV2".toUTF8
  let b1 := (encodeU32le (UInt32.ofNat "Examples".toUTF8.size)).append
    "Examples".toUTF8
  let b2 := (encodeU32le (UInt32.ofNat "StateCell".toUTF8.size)).append
    "StateCell".toUTF8
  have h0 : encodeString "ProofForgeV2" = .ok b0 := by
    exact encodeString_eq_okV1 "ProofForgeV2"
      (requireNfc_eq_ok_of_isAscii "ProofForgeV2" (by decide)) (by decide)
  have h1 : encodeString "Examples" = .ok b1 := by
    exact encodeString_eq_okV1 "Examples"
      (requireNfc_eq_ok_of_isAscii "Examples" (by decide)) (by decide)
  have h2 : encodeString "StateCell" = .ok b2 := by
    exact encodeString_eq_okV1 "StateCell"
      (requireNfc_eq_ok_of_isAscii "StateCell" (by decide)) (by decide)
  let bytes := (encodeU32le 6).append
    (((((b0.append b1).append b2).append b0).append b1).append b2)
  have harray :
      encodeArray encodeString
          #["ProofForgeV2", "Examples", "StateCell", "ProofForgeV2",
            "Examples", "StateCell"] =
        .ok bytes := by
    simpa only [bytes] using
      encodeArray_sixV1 encodeString "ProofForgeV2" "Examples" "StateCell"
        "ProofForgeV2" "Examples" "StateCell" b0 b1 b2 b0 b1 b2
        h0 h1 h2 h0 h1 h2
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeQualifiedName, mapCommon,
      stateCellQualifiedNameComponentsV1, harray, Bind.bind, Except.bind]
  · decide

private theorem stateCellTypesEncodingV1 :
    ∃ bytes,
      encodeArray encodeTypeDeclV1 stateCellSemanticProgramDataV1.types = .ok bytes ∧
        bytes.size ≤ 512 := by
  rcases stateCellTypeValuesV1 with ⟨htype0, htype1⟩
  let uintShapeB := taggedBytesV1 "Type.UInt" #[encodeU16le 64]
  let unitShapeB := taggedBytesV1 "Type.Unit" #[]
  let type0B := taggedBytesV1 "TypeDecl"
    #[encodeU32le 0, encodeU8 0, uintShapeB]
  let type1B := taggedBytesV1 "TypeDecl"
    #[encodeU32le 1, encodeU8 0, unitShapeB]
  have huint : encodeTypeShapeV1 (.uint 64) = .ok uintShapeB := by
    simp only [encodeTypeShapeV1, uintShapeB]
    exact encodeTagged_eq_okV1 "Type.UInt" #[encodeU16le 64]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have hunit : encodeTypeShapeV1 .unit = .ok unitShapeB := by
    simp only [encodeTypeShapeV1, encodeNullary, unitShapeB]
    exact encodeTagged_eq_okV1 "Type.Unit" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have htype0 : encodeTypeDeclV1 stateCellType0V1 = .ok type0B := by
    rw [htype0]
    simp only [encodeTypeDeclV1, encodeOption, huint, type0B, Bind.bind,
      Except.bind]
    exact encodeTagged_eq_okV1 "TypeDecl"
      #[encodeU32le 0, encodeU8 0, uintShapeB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  have htype1 : encodeTypeDeclV1 stateCellType1V1 = .ok type1B := by
    rw [htype1]
    simp only [encodeTypeDeclV1, encodeOption, hunit, type1B, Bind.bind,
      Except.bind]
    exact encodeTagged_eq_okV1 "TypeDecl"
      #[encodeU32le 1, encodeU8 0, unitShapeB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  let bytes := (encodeU32le 2).append (type0B.append type1B)
  refine ⟨bytes, ?_, ?_⟩
  · rw [stateCellTypesV1]
    simpa only [bytes] using encodeArray_twoV1 encodeTypeDeclV1
      stateCellType0V1 stateCellType1V1 type0B type1B htype0 htype1
  · decide

private theorem stateCellLogicalStateEncodingV1 :
    ∃ bytes,
      encodeArray encodeStateDeclV1 stateCellSemanticProgramDataV1.logicalState =
          .ok bytes ∧
        bytes.size ≤ 512 := by
  let nameB := (encodeU32le (UInt32.ofNat "count".toUTF8.size)).append
    "count".toUTF8
  let visibilityB := taggedBytesV1 "Visibility.Public" #[]
  let stateB := taggedBytesV1 "StateDecl"
    #[encodeU32le 0, nameB, encodeU32le 0, visibilityB]
  have hname : encodeString "count" = .ok nameB := by
    exact encodeString_eq_okV1 "count"
      (requireNfc_eq_ok_of_isAscii "count" (by decide)) (by decide)
  have hstate : encodeStateDeclV1 stateCellState0V1 = .ok stateB := by
    rw [stateCellState0ValueV1]
    simp only [encodeStateDeclV1, hname, encodePublicVisibilityV1, stateB,
      visibilityB, Bind.bind, Except.bind]
    exact encodeTagged_eq_okV1 "StateDecl"
      #[encodeU32le 0, nameB, encodeU32le 0, visibilityB]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  let bytes := (encodeU32le 1).append stateB
  refine ⟨bytes, ?_, ?_⟩
  · rw [stateCellLogicalStateV1]
    simpa only [bytes] using encodeArray_oneV1 encodeStateDeclV1
      stateCellState0V1 stateB hstate
  · decide

private theorem stateCellEmptySemanticTableEncodingsV1 :
    encodeArray encodeConstantV1 stateCellSemanticProgramDataV1.constants =
        .ok (encodeU32le 0) ∧
      encodeArray encodeEventDeclV1 stateCellSemanticProgramDataV1.events =
        .ok (encodeU32le 0) ∧
      encodeArray encodeErrorDeclV1 stateCellSemanticProgramDataV1.errors =
        .ok (encodeU32le 0) ∧
      encodeArray encodeInvariantDeclV1 stateCellSemanticProgramDataV1.invariants =
        .ok (encodeU32le 0) := by
  rcases stateCellEmptySemanticTablesV1 with ⟨hconstants, hevents, herrors, hinvariants⟩
  rw [hconstants, hevents, herrors, hinvariants]
  exact ⟨encodeArray_zeroV1 encodeConstantV1,
    encodeArray_zeroV1 encodeEventDeclV1,
    encodeArray_zeroV1 encodeErrorDeclV1,
    encodeArray_zeroV1 encodeInvariantDeclV1⟩

private theorem encodeOptionalValueDefNoneV1 :
    encodeOption encodeValueDefV1 (none : Option ValueDefV1) = .ok (encodeU8 0) ∧
      (encodeU8 0).size ≤ 256 := by
  exact ⟨rfl, by rw [encodeU8_size]; decide⟩

private theorem encodeOptionalValueDefSomeV1 (value : ValueDefV1) :
    ∃ bytes,
      encodeOption encodeValueDefV1 (some value) = .ok bytes ∧ bytes.size ≤ 256 := by
  let valueB := taggedBytesV1 "ValueDef"
    #[encodeU32le value.valueId, encodeU32le value.typeId]
  have hvalue : encodeValueDefV1 value = .ok valueB := by
    simp only [encodeValueDefV1, valueB]
    exact encodeTagged_eq_okV1 "ValueDef"
      #[encodeU32le value.valueId, encodeU32le value.typeId]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  let bytes := (encodeU8 1).append valueB
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeOption, hvalue, bytes, Bind.bind, Pure.pure, Except.bind,
      Except.pure]
  · simp only [bytes]
    rw [ByteArray_size_append, encodeU8_size, taggedBytesV1_size,
      foldl_size_two, encodeU32le_size, encodeU32le_size]
    have ht : "ValueDef".toUTF8.size = 8 := by decide
    rw [ht]
    decide

private theorem encodeStateLoadOpV1 (stateId : UInt32) :
    ∃ bytes,
      encodeSemanticOpV1 (.stateLoad stateId) = .ok bytes ∧ bytes.size ≤ 256 := by
  let bytes := taggedBytesV1 "Op.StateLoad" #[encodeU32le stateId]
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeSemanticOpV1, bytes]
    exact encodeTagged_eq_okV1 "Op.StateLoad" #[encodeU32le stateId]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_one, encodeU32le_size]
    have ht : "Op.StateLoad".toUTF8.size = 12 := by decide
    rw [ht]
    decide

private theorem encodeStateStoreOpV1 (stateId valueId : UInt32) :
    ∃ bytes,
      encodeSemanticOpV1 (.stateStore stateId valueId) = .ok bytes ∧
        bytes.size ≤ 256 := by
  let bytes := taggedBytesV1 "Op.StateStore"
    #[encodeU32le stateId, encodeU32le valueId]
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeSemanticOpV1, bytes]
    exact encodeTagged_eq_okV1 "Op.StateStore"
      #[encodeU32le stateId, encodeU32le valueId]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_two, encodeU32le_size,
      encodeU32le_size]
    have ht : "Op.StateStore".toUTF8.size = 13 := by decide
    rw [ht]
    decide

private theorem encodeBinaryAddOpV1 (lhs rhs : UInt32) :
    ∃ bytes,
      encodeSemanticOpV1 (.binary .add lhs rhs) = .ok bytes ∧ bytes.size ≤ 256 := by
  let operatorB := taggedBytesV1 "Binary.Add" #[]
  have hoperator : encodeBinaryOpV1 .add = .ok operatorB := by
    simp only [encodeBinaryOpV1, encodeNullary, operatorB]
    exact encodeTagged_eq_okV1 "Binary.Add" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  let bytes := taggedBytesV1 "Op.Binary"
    #[operatorB, encodeU32le lhs, encodeU32le rhs]
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeSemanticOpV1, hoperator, bytes, Bind.bind, Except.bind]
    exact encodeTagged_eq_okV1 "Op.Binary"
      #[operatorB, encodeU32le lhs, encodeU32le rhs]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_three, encodeU32le_size,
      encodeU32le_size]
    have houter : "Op.Binary".toUTF8.size = 9 := by decide
    have hoperatorSize : operatorB.size = 16 := by
      simp only [operatorB]
      rw [taggedBytesV1_size]
      decide
    rw [houter, hoperatorSize]
    decide

private theorem encodeInstructionV1_ok_size_of_fields
    (instruction : InstructionV1) (resultB opB : ByteArray)
    (hresult : encodeOption encodeValueDefV1 instruction.result = .ok resultB)
    (hop : encodeSemanticOpV1 instruction.op = .ok opB)
    (hresultSize : resultB.size ≤ 256) (hopSize : opB.size ≤ 256) :
    ∃ bytes, encodeInstructionV1 instruction = .ok bytes ∧ bytes.size ≤ 1024 := by
  let bytes := taggedBytesV1 "Instruction" #[resultB, opB]
  have htag : encodeTagged "Instruction" #[resultB, opB] = .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Instruction" #[resultB, opB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes,
    encodeInstructionV1_eq_of_fields instruction resultB opB bytes hresult hop htag, ?_⟩
  simp only [bytes]
  rw [taggedBytesV1_size, foldl_size_two]
  have ht : "Instruction".toUTF8.size = 11 := by decide
  rw [ht]
  omega

private theorem stateCellCallable0Instruction0EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable0Instruction0V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨hresult, hop, _hresult10, _hop10, _hresult11, _hop11, _hresult12,
      _hop12, _hresult13, _hop13, _hresult20, _hop20⟩
  rcases encodeOptionalValueDefNoneV1 with ⟨hresultB, hresultSize⟩
  rcases encodeStateStoreOpV1 0 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable0Instruction0V1
    (encodeU8 0) opB
  · simpa only [hresult] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction0EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction0V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, hresult, hop, _hresult11, _hop11, _hresult12,
      _hop12, _hresult13, _hop13, _hresult20, _hop20⟩
  let value : ValueDefV1 := { valueId := 1, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeStateLoadOpV1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction0V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction1EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction1V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, hresult, hop, _hresult12,
      _hop12, _hresult13, _hop13, _hresult20, _hop20⟩
  let value : ValueDefV1 := { valueId := 2, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeBinaryAddOpV1 1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction1V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction2EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction2V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, _hresult11, _hop11, hresult,
      hop, _hresult13, _hop13, _hresult20, _hop20⟩
  rcases encodeOptionalValueDefNoneV1 with ⟨hresultB, hresultSize⟩
  rcases encodeStateStoreOpV1 0 2 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction2V1
    (encodeU8 0) opB
  · simpa only [hresult] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable1Instruction3EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable1Instruction3V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, _hresult11, _hop11, _hresult12,
      _hop12, hresult, hop, _hresult20, _hop20⟩
  let value : ValueDefV1 := { valueId := 3, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeStateLoadOpV1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable1Instruction3V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem stateCellCallable2Instruction0EncodingV1 :
    ∃ bytes,
      encodeInstructionV1 stateCellCallable2Instruction0V1 = .ok bytes ∧
        bytes.size ≤ 1024 := by
  rcases stateCellInstructionFieldValuesV1 with
    ⟨_hresult00, _hop00, _hresult10, _hop10, _hresult11, _hop11, _hresult12,
      _hop12, _hresult13, _hop13, hresult, hop⟩
  let value : ValueDefV1 := { valueId := 0, typeId := 0 }
  rcases encodeOptionalValueDefSomeV1 value with ⟨resultB, hresultB, hresultSize⟩
  rcases encodeStateLoadOpV1 0 with ⟨opB, hopB, hopSize⟩
  apply encodeInstructionV1_ok_size_of_fields stateCellCallable2Instruction0V1
    resultB opB
  · simpa only [hresult, value] using hresultB
  · simpa only [hop] using hopB
  · exact hresultSize
  · exact hopSize

private theorem encodeReturnTerminatorV1 (value : Option UInt32) :
    ∃ bytes,
      encodeTerminatorV1 (.return_ value) = .ok bytes ∧ bytes.size ≤ 256 := by
  let valueB := match value with
    | none => encodeU8 0
    | some id => (encodeU8 1).append (encodeU32le id)
  have hvalue :
      encodeOption (fun id => pure (encodeU32le id)) value = .ok valueB := by
    cases value <;> rfl
  let bytes := taggedBytesV1 "Term.Return" #[valueB]
  have htag : encodeTagged "Term.Return" #[valueB] = .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Term.Return" #[valueB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeTerminatorV1, hvalue, htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_one]
    have htagSize : "Term.Return".toUTF8.size = 11 := by decide
    have hvalueSize : valueB.size ≤ 5 := by
      cases value with
      | none =>
          simp only [valueB, encodeU8_size]
          decide
      | some id =>
          simp only [valueB, ByteArray_size_append, encodeU8_size,
            encodeU32le_size]
          decide
    rw [htagSize]
    omega

private theorem encodeBlockV1_ok_size_of_fields
    (block : BlockV1) (paramsB instructionsB terminatorB : ByteArray)
    (hparams : encodeArray encodeBlockParameterV1 block.params = .ok paramsB)
    (hinstructions : encodeArray encodeInstructionV1 block.instructions =
      .ok instructionsB)
    (hterminator : encodeTerminatorV1 block.terminator = .ok terminatorB)
    (hparamsSize : paramsB.size ≤ 256)
    (hinstructionsSize : instructionsB.size ≤ 8192)
    (hterminatorSize : terminatorB.size ≤ 256) :
    ∃ bytes, encodeBlockV1 block = .ok bytes ∧ bytes.size ≤ 65536 := by
  let bytes := taggedBytesV1 "Block"
    #[encodeU32le block.id, paramsB, instructionsB, terminatorB]
  have htag :
      encodeTagged "Block"
          #[encodeU32le block.id, paramsB, instructionsB, terminatorB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Block"
      #[encodeU32le block.id, paramsB, instructionsB, terminatorB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, encodeBlockV1_eq_of_fields block paramsB instructionsB
    terminatorB bytes hparams hinstructions hterminator htag, ?_⟩
  simp only [bytes]
  rw [taggedBytesV1_size, foldl_size_four, encodeU32le_size]
  have htagSize : "Block".toUTF8.size = 5 := by decide
  rw [htagSize]
  omega

private theorem stateCellCallable0BlockEncodingV1 :
    ∃ bytes, encodeBlockV1 stateCellCallable0BlockV1 = .ok bytes ∧
      bytes.size ≤ 65536 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hid, hparams, hterminator, _hid1, _hparams1, _hterminator1,
      _hid2, _hparams2, _hterminator2⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨hinstructions, _hinstructions1, _hinstructions2⟩
  rcases stateCellCallable0Instruction0EncodingV1 with
    ⟨instructionB, hinstruction, hinstructionSize⟩
  let instructionsB := (encodeU32le 1).append instructionB
  have hinstructionsB :
      encodeArray encodeInstructionV1 stateCellCallable0BlockV1.instructions =
        .ok instructionsB := by
    rw [hinstructions]
    simpa only [instructionsB] using encodeArray_oneV1 encodeInstructionV1
      stateCellCallable0Instruction0V1 instructionB hinstruction
  have hinstructionsSize : instructionsB.size ≤ 8192 := by
    simp only [instructionsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodeReturnTerminatorV1 none with
    ⟨terminatorB, hterminatorB, hterminatorSize⟩
  apply encodeBlockV1_ok_size_of_fields stateCellCallable0BlockV1
    (encodeU32le 0) instructionsB terminatorB
  · simpa only [hparams] using encodeArray_zeroV1 encodeBlockParameterV1
  · exact hinstructionsB
  · simpa only [hterminator] using hterminatorB
  · rw [encodeU32le_size]
    decide
  · exact hinstructionsSize
  · exact hterminatorSize

private theorem stateCellCallable1BlockEncodingV1 :
    ∃ bytes, encodeBlockV1 stateCellCallable1BlockV1 = .ok bytes ∧
      bytes.size ≤ 65536 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hid0, _hparams0, _hterminator0, _hid, hparams, hterminator,
      _hid2, _hparams2, _hterminator2⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨_hinstructions0, hinstructions, _hinstructions2⟩
  rcases stateCellCallable1Instruction0EncodingV1 with
    ⟨instruction0B, hinstruction0, hinstruction0Size⟩
  rcases stateCellCallable1Instruction1EncodingV1 with
    ⟨instruction1B, hinstruction1, hinstruction1Size⟩
  rcases stateCellCallable1Instruction2EncodingV1 with
    ⟨instruction2B, hinstruction2, hinstruction2Size⟩
  rcases stateCellCallable1Instruction3EncodingV1 with
    ⟨instruction3B, hinstruction3, hinstruction3Size⟩
  let instructionsB := (encodeU32le 4).append
    (((instruction0B.append instruction1B).append instruction2B).append
      instruction3B)
  have hinstructionsB :
      encodeArray encodeInstructionV1 stateCellCallable1BlockV1.instructions =
        .ok instructionsB := by
    rw [hinstructions]
    simpa only [instructionsB] using encodeArray_fourV1 encodeInstructionV1
      stateCellCallable1Instruction0V1 stateCellCallable1Instruction1V1
      stateCellCallable1Instruction2V1 stateCellCallable1Instruction3V1
      instruction0B instruction1B instruction2B instruction3B hinstruction0
      hinstruction1 hinstruction2 hinstruction3
  have hinstructionsSize : instructionsB.size ≤ 8192 := by
    simp only [instructionsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodeReturnTerminatorV1 (some 3) with
    ⟨terminatorB, hterminatorB, hterminatorSize⟩
  apply encodeBlockV1_ok_size_of_fields stateCellCallable1BlockV1
    (encodeU32le 0) instructionsB terminatorB
  · simpa only [hparams] using encodeArray_zeroV1 encodeBlockParameterV1
  · exact hinstructionsB
  · simpa only [hterminator] using hterminatorB
  · rw [encodeU32le_size]
    decide
  · exact hinstructionsSize
  · exact hterminatorSize

private theorem stateCellCallable2BlockEncodingV1 :
    ∃ bytes, encodeBlockV1 stateCellCallable2BlockV1 = .ok bytes ∧
      bytes.size ≤ 65536 := by
  rcases stateCellBlockFieldValuesV1 with
    ⟨_hid0, _hparams0, _hterminator0, _hid1, _hparams1, _hterminator1,
      _hid, hparams, hterminator⟩
  rcases stateCellCallableInstructionTablesV1 with
    ⟨_hinstructions0, _hinstructions1, hinstructions⟩
  rcases stateCellCallable2Instruction0EncodingV1 with
    ⟨instructionB, hinstruction, hinstructionSize⟩
  let instructionsB := (encodeU32le 1).append instructionB
  have hinstructionsB :
      encodeArray encodeInstructionV1 stateCellCallable2BlockV1.instructions =
        .ok instructionsB := by
    rw [hinstructions]
    simpa only [instructionsB] using encodeArray_oneV1 encodeInstructionV1
      stateCellCallable2Instruction0V1 instructionB hinstruction
  have hinstructionsSize : instructionsB.size ≤ 8192 := by
    simp only [instructionsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodeReturnTerminatorV1 (some 0) with
    ⟨terminatorB, hterminatorB, hterminatorSize⟩
  apply encodeBlockV1_ok_size_of_fields stateCellCallable2BlockV1
    (encodeU32le 0) instructionsB terminatorB
  · simpa only [hparams] using encodeArray_zeroV1 encodeBlockParameterV1
  · exact hinstructionsB
  · simpa only [hterminator] using hterminatorB
  · rw [encodeU32le_size]
    decide
  · exact hinstructionsSize
  · exact hterminatorSize

private theorem encodeInitializerCallableKindV1 :
    encodeCallableKindV1 .initializer =
        .ok (taggedBytesV1 "Callable.Initializer" #[]) ∧
      (taggedBytesV1 "Callable.Initializer" #[]).size ≤ 64 := by
  constructor
  · simp only [encodeCallableKindV1, encodeNullary]
    exact encodeTagged_eq_okV1 "Callable.Initializer" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  · rw [taggedBytesV1_size]
    decide

private theorem encodeEntryCallableKindV1 :
    encodeCallableKindV1 .entry =
        .ok (taggedBytesV1 "Callable.Entry" #[]) ∧
      (taggedBytesV1 "Callable.Entry" #[]).size ≤ 64 := by
  constructor
  · simp only [encodeCallableKindV1, encodeNullary]
    exact encodeTagged_eq_okV1 "Callable.Entry" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  · rw [taggedBytesV1_size]
    decide

private theorem encodeViewCallableKindV1 :
    encodeCallableKindV1 .view =
        .ok (taggedBytesV1 "Callable.View" #[]) ∧
      (taggedBytesV1 "Callable.View" #[]).size ≤ 64 := by
  constructor
  · simp only [encodeCallableKindV1, encodeNullary]
    exact encodeTagged_eq_okV1 "Callable.View" #[]
      (by decide) (by decide) (by decide) (by decide) (by decide)
  · rw [taggedBytesV1_size]
    decide

private theorem encodeOptionalAsciiStringSomeV1 (value : String)
    (hascii : isAscii value = true) (hsize : value.toUTF8.size ≤ 240) :
    ∃ bytes,
      encodeOption encodeString (some value) = .ok bytes ∧ bytes.size ≤ 512 := by
  let stringB := (encodeU32le (UInt32.ofNat value.toUTF8.size)).append value.toUTF8
  have hstring : encodeString value = .ok stringB := by
    exact encodeString_eq_okV1 value (requireNfc_eq_ok_of_isAscii value hascii)
      (Nat.le_trans hsize (by decide))
  let bytes := (encodeU8 1).append stringB
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeOption, hstring, bytes, Bind.bind, Pure.pure, Except.bind,
      Except.pure]
  · simp only [bytes, stringB, ByteArray_size_append, encodeU8_size,
      encodeU32le_size]
    omega

private theorem encodePublicParameterV1 (valueId typeId : UInt32) (name : String)
    (hascii : isAscii name = true) (hsize : name.toUTF8.size ≤ 240) :
    ∃ bytes,
      encodeParameterV1 {
        valueId, name, typeId, visibility := .public_
      } = .ok bytes ∧ bytes.size ≤ 512 := by
  let nameB := (encodeU32le (UInt32.ofNat name.toUTF8.size)).append name.toUTF8
  have hname : encodeString name = .ok nameB := by
    exact encodeString_eq_okV1 name (requireNfc_eq_ok_of_isAscii name hascii)
      (Nat.le_trans hsize (by decide))
  let visibilityB := taggedBytesV1 "Visibility.Public" #[]
  let bytes := taggedBytesV1 "Parameter"
    #[encodeU32le valueId, nameB, encodeU32le typeId, visibilityB]
  have htag :
      encodeTagged "Parameter"
          #[encodeU32le valueId, nameB, encodeU32le typeId, visibilityB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Parameter"
      #[encodeU32le valueId, nameB, encodeU32le typeId, visibilityB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeParameterV1, hname, encodePublicVisibilityV1, visibilityB,
      htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_four, encodeU32le_size,
      encodeU32le_size]
    have htagSize : "Parameter".toUTF8.size = 9 := by decide
    have hnameSize : nameB.size = 4 + name.toUTF8.size := by
      simp only [nameB, ByteArray_size_append, encodeU32le_size]
    have hvisibilitySize : visibilityB.size = 23 := by
      simp only [visibilityB]
      rw [taggedBytesV1_size]
      decide
    rw [htagSize, hnameSize, hvisibilitySize]
    omega

private theorem encodePublicCallableResultV1 (typeId : UInt32) :
    ∃ bytes,
      encodeCallableResultV1 { typeId, visibility := .public_ } = .ok bytes ∧
        bytes.size ≤ 256 := by
  let visibilityB := taggedBytesV1 "Visibility.Public" #[]
  let bytes := taggedBytesV1 "CallableResult" #[encodeU32le typeId, visibilityB]
  have htag :
      encodeTagged "CallableResult" #[encodeU32le typeId, visibilityB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "CallableResult"
      #[encodeU32le typeId, visibilityB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeCallableResultV1, encodePublicVisibilityV1, visibilityB,
      htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_two, encodeU32le_size]
    have htagSize : "CallableResult".toUTF8.size = 14 := by decide
    have hvisibilitySize : visibilityB.size = 23 := by
      simp only [visibilityB]
      rw [taggedBytesV1_size]
      decide
    rw [htagSize, hvisibilitySize]
    decide

private theorem encodeCallableV1_ok_size_of_fields
    (callable : CallableV1)
    (kindB nameB paramsB resultB blocksB loopB stepsB : ByteArray)
    (hkind : encodeCallableKindV1 callable.kind = .ok kindB)
    (hname : encodeOption encodeString callable.name = .ok nameB)
    (hparams : encodeArray encodeParameterV1 callable.params = .ok paramsB)
    (hresult : encodeCallableResultV1 callable.result = .ok resultB)
    (hblocks : encodeArray encodeBlockV1 callable.blocks = .ok blocksB)
    (hloop : encodeArray encodeLoopBoundV1 callable.loopBounds = .ok loopB)
    (hsteps : encodeOption (fun v => pure (encodeU64le v))
      callable.invariantSteps = .ok stepsB)
    (hkindSize : kindB.size ≤ 64) (hnameSize : nameB.size ≤ 512)
    (hparamsSize : paramsB.size ≤ 1024) (hresultSize : resultB.size ≤ 256)
    (hblocksSize : blocksB.size ≤ 131072) (hloopSize : loopB.size ≤ 256)
    (hstepsSize : stepsB.size ≤ 16) :
    ∃ bytes, encodeCallableV1 callable = .ok bytes ∧ bytes.size ≤ 262144 := by
  let bytes := taggedBytesV1 "Callable" #[encodeU32le callable.id, kindB,
    nameB, paramsB, resultB, encodeU32le callable.entryBlock, blocksB, loopB,
    stepsB]
  have htag :
      encodeTagged "Callable" #[encodeU32le callable.id, kindB, nameB, paramsB,
          resultB, encodeU32le callable.entryBlock, blocksB, loopB, stepsB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "Callable"
      #[encodeU32le callable.id, kindB, nameB, paramsB, resultB,
        encodeU32le callable.entryBlock, blocksB, loopB, stepsB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, encodeCallableV1_eq_of_fields callable kindB nameB paramsB
    resultB blocksB loopB stepsB bytes hkind hname hparams hresult hblocks hloop
    hsteps htag, ?_⟩
  simp only [bytes]
  rw [taggedBytesV1_size, foldl_size_nine, encodeU32le_size,
    encodeU32le_size]
  have htagSize : "Callable".toUTF8.size = 8 := by decide
  rw [htagSize]
  omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0EncodingV1 :
    ∃ bytes, encodeCallableV1 stateCellCallable0V1 = .ok bytes ∧
      bytes.size ≤ 262144 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid, hkind, hname, hparams, hparameter, hresult, _hentry, hloop, hsteps,
      _hid1, _hkind1, _hname1, _hparams1, _hparameter1, _hresult1, _hentry1,
      _hloop1, _hsteps1, _hid2, _hkind2, _hname2, _hparams2, _hresult2,
      _hentry2, _hloop2, _hsteps2⟩
  rcases stateCellCallableBlockTablesV1 with ⟨hblocks, _hblocks1, _hblocks2⟩
  rcases encodeInitializerCallableKindV1 with ⟨hkindB, hkindSize⟩
  rcases encodePublicParameterV1 0 0 "initial" (by decide) (by decide) with
    ⟨parameterB, hparameterB, hparameterSize⟩
  have hparameterB' :
      encodeParameterV1 stateCellCallable0Parameter0V1 = .ok parameterB := by
    simpa only [hparameter] using hparameterB
  let paramsB := (encodeU32le 1).append parameterB
  have hparamsB : encodeArray encodeParameterV1 stateCellCallable0V1.params =
      .ok paramsB := by
    rw [hparams]
    simpa only [paramsB] using encodeArray_oneV1 encodeParameterV1
      stateCellCallable0Parameter0V1 parameterB hparameterB'
  have hparamsSize : paramsB.size ≤ 1024 := by
    simp only [paramsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodePublicCallableResultV1 1 with ⟨resultB, hresultB, hresultSize⟩
  rcases stateCellCallable0BlockEncodingV1 with ⟨blockB, hblockB, hblockSize⟩
  let blocksB := (encodeU32le 1).append blockB
  have hblocksB : encodeArray encodeBlockV1 stateCellCallable0V1.blocks =
      .ok blocksB := by
    rw [hblocks]
    simpa only [blocksB] using encodeArray_oneV1 encodeBlockV1
      stateCellCallable0BlockV1 blockB hblockB
  have hblocksSize : blocksB.size ≤ 131072 := by
    simp only [blocksB, ByteArray_size_append, encodeU32le_size]
    omega
  apply encodeCallableV1_ok_size_of_fields stateCellCallable0V1
    (taggedBytesV1 "Callable.Initializer" #[]) (encodeU8 0) paramsB resultB
    blocksB (encodeU32le 0) (encodeU8 0)
  · simpa only [hkind] using hkindB
  · rw [hname]
    rfl
  · exact hparamsB
  · simpa only [hresult] using hresultB
  · exact hblocksB
  · simpa only [hloop] using encodeArray_zeroV1 encodeLoopBoundV1
  · rw [hsteps]
    rfl
  · exact hkindSize
  · rw [encodeU8_size]
    decide
  · exact hparamsSize
  · exact hresultSize
  · exact hblocksSize
  · rw [encodeU32le_size]
    decide
  · rw [encodeU8_size]
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1EncodingV1 :
    ∃ bytes, encodeCallableV1 stateCellCallable1V1 = .ok bytes ∧
      bytes.size ≤ 262144 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparameter0, _hresult0, _hentry0,
      _hloop0, _hsteps0, _hid, hkind, hname, hparams, hparameter, hresult,
      _hentry, hloop, hsteps, _hid2, _hkind2, _hname2, _hparams2, _hresult2,
      _hentry2, _hloop2, _hsteps2⟩
  rcases stateCellCallableBlockTablesV1 with ⟨_hblocks0, hblocks, _hblocks2⟩
  rcases encodeEntryCallableKindV1 with ⟨hkindB, hkindSize⟩
  rcases encodeOptionalAsciiStringSomeV1 "increment" (by decide) (by decide) with
    ⟨nameB, hnameB, hnameSize⟩
  rcases encodePublicParameterV1 0 0 "delta" (by decide) (by decide) with
    ⟨parameterB, hparameterB, hparameterSize⟩
  have hparameterB' :
      encodeParameterV1 stateCellCallable1Parameter0V1 = .ok parameterB := by
    simpa only [hparameter] using hparameterB
  let paramsB := (encodeU32le 1).append parameterB
  have hparamsB : encodeArray encodeParameterV1 stateCellCallable1V1.params =
      .ok paramsB := by
    rw [hparams]
    simpa only [paramsB] using encodeArray_oneV1 encodeParameterV1
      stateCellCallable1Parameter0V1 parameterB hparameterB'
  have hparamsSize : paramsB.size ≤ 1024 := by
    simp only [paramsB, ByteArray_size_append, encodeU32le_size]
    omega
  rcases encodePublicCallableResultV1 0 with ⟨resultB, hresultB, hresultSize⟩
  rcases stateCellCallable1BlockEncodingV1 with ⟨blockB, hblockB, hblockSize⟩
  let blocksB := (encodeU32le 1).append blockB
  have hblocksB : encodeArray encodeBlockV1 stateCellCallable1V1.blocks =
      .ok blocksB := by
    rw [hblocks]
    simpa only [blocksB] using encodeArray_oneV1 encodeBlockV1
      stateCellCallable1BlockV1 blockB hblockB
  have hblocksSize : blocksB.size ≤ 131072 := by
    simp only [blocksB, ByteArray_size_append, encodeU32le_size]
    omega
  apply encodeCallableV1_ok_size_of_fields stateCellCallable1V1
    (taggedBytesV1 "Callable.Entry" #[]) nameB paramsB resultB blocksB
    (encodeU32le 0) (encodeU8 0)
  · simpa only [hkind] using hkindB
  · simpa only [hname] using hnameB
  · exact hparamsB
  · simpa only [hresult] using hresultB
  · exact hblocksB
  · simpa only [hloop] using encodeArray_zeroV1 encodeLoopBoundV1
  · rw [hsteps]
    rfl
  · exact hkindSize
  · exact hnameSize
  · exact hparamsSize
  · exact hresultSize
  · exact hblocksSize
  · rw [encodeU32le_size]
    decide
  · rw [encodeU8_size]
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2EncodingV1 :
    ∃ bytes, encodeCallableV1 stateCellCallable2V1 = .ok bytes ∧
      bytes.size ≤ 262144 := by
  rcases stateCellCallableFieldValuesV1 with
    ⟨_hid0, _hkind0, _hname0, _hparams0, _hparameter0, _hresult0, _hentry0,
      _hloop0, _hsteps0, _hid1, _hkind1, _hname1, _hparams1, _hparameter1,
      _hresult1, _hentry1, _hloop1, _hsteps1, _hid, hkind, hname, hparams,
      hresult, _hentry, hloop, hsteps⟩
  rcases stateCellCallableBlockTablesV1 with ⟨_hblocks0, _hblocks1, hblocks⟩
  rcases encodeViewCallableKindV1 with ⟨hkindB, hkindSize⟩
  rcases encodeOptionalAsciiStringSomeV1 "get" (by decide) (by decide) with
    ⟨nameB, hnameB, hnameSize⟩
  rcases encodePublicCallableResultV1 0 with ⟨resultB, hresultB, hresultSize⟩
  rcases stateCellCallable2BlockEncodingV1 with ⟨blockB, hblockB, hblockSize⟩
  let blocksB := (encodeU32le 1).append blockB
  have hblocksB : encodeArray encodeBlockV1 stateCellCallable2V1.blocks =
      .ok blocksB := by
    rw [hblocks]
    simpa only [blocksB] using encodeArray_oneV1 encodeBlockV1
      stateCellCallable2BlockV1 blockB hblockB
  have hblocksSize : blocksB.size ≤ 131072 := by
    simp only [blocksB, ByteArray_size_append, encodeU32le_size]
    omega
  apply encodeCallableV1_ok_size_of_fields stateCellCallable2V1
    (taggedBytesV1 "Callable.View" #[]) nameB (encodeU32le 0) resultB blocksB
    (encodeU32le 0) (encodeU8 0)
  · simpa only [hkind] using hkindB
  · simpa only [hname] using hnameB
  · simpa only [hparams] using encodeArray_zeroV1 encodeParameterV1
  · simpa only [hresult] using hresultB
  · exact hblocksB
  · simpa only [hloop] using encodeArray_zeroV1 encodeLoopBoundV1
  · rw [hsteps]
    rfl
  · exact hkindSize
  · exact hnameSize
  · rw [encodeU32le_size]
    decide
  · exact hresultSize
  · exact hblocksSize
  · rw [encodeU32le_size]
    decide
  · rw [encodeU8_size]
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallablesEncodingV1 :
    ∃ bytes,
      encodeArray encodeCallableV1 stateCellSemanticProgramDataV1.callables =
          .ok bytes ∧
        bytes.size ≤ 1048576 := by
  rcases stateCellCallable0EncodingV1 with ⟨callable0B, hcallable0, hsize0⟩
  rcases stateCellCallable1EncodingV1 with ⟨callable1B, hcallable1, hsize1⟩
  rcases stateCellCallable2EncodingV1 with ⟨callable2B, hcallable2, hsize2⟩
  let bytes := (encodeU32le 3).append
    ((callable0B.append callable1B).append callable2B)
  refine ⟨bytes, ?_, ?_⟩
  · rw [stateCellCallablesV1]
    simpa only [bytes] using encodeArray_threeV1 encodeCallableV1
      stateCellCallable0V1 stateCellCallable1V1 stateCellCallable2V1
      callable0B callable1B callable2B hcallable0 hcallable1 hcallable2
  · simp only [bytes, ByteArray_size_append, encodeU32le_size]
    omega

private theorem encodeRequirementRequestV1_ok_size_of_fields
    (request : RequirementRequestV1)
    (idB versionB digestB predicatesB : ByteArray)
    (hid : encodeString request.id = .ok idB)
    (hversion : encodeSemVer request.version = .ok versionB)
    (hdigest : encodeDigest request.digest = .ok digestB)
    (hpredicates : encodeArray encodeRequirementPredicateV1 request.predicates =
      .ok predicatesB)
    (hidSize : idB.size ≤ 512) (hversionSize : versionB.size ≤ 512)
    (hdigestSize : digestB.size ≤ 64) (hpredicatesSize : predicatesB.size ≤ 256) :
    ∃ bytes,
      encodeRequirementRequestV1 request = .ok bytes ∧ bytes.size ≤ 2048 := by
  let bytes := taggedBytesV1 "RequirementRequest"
    #[idB, versionB, digestB, predicatesB]
  have htag :
      encodeTagged "RequirementRequest" #[idB, versionB, digestB, predicatesB] =
        .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "RequirementRequest"
      #[idB, versionB, digestB, predicatesB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeRequirementRequestV1, hid, hversion, hdigest, hpredicates,
      htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_four]
    have htagSize : "RequirementRequest".toUTF8.size = 18 := by decide
    rw [htagSize]
    omega

private theorem encodeClosedS2RequirementV1
    (request : RequirementRequestV1) (id : String) (digestBytes : ByteArray)
    (hid : request.id = id)
    (hversion : request.version = s2RequirementVersionV1)
    (hdigest : request.digest = { algorithm := .sha256, bytes := digestBytes })
    (hpredicates : request.predicates = #[])
    (hascii : isAscii id = true) (hidSize : id.toUTF8.size ≤ 240)
    (hdigestSize : digestBytes.size = 32) :
    ∃ bytes,
      encodeRequirementRequestV1 request = .ok bytes ∧ bytes.size ≤ 2048 := by
  let idB := (encodeU32le (UInt32.ofNat id.toUTF8.size)).append id.toUTF8
  have hidB : encodeString request.id = .ok idB := by
    rw [hid]
    exact encodeString_eq_okV1 id (requireNfc_eq_ok_of_isAscii id hascii)
      (Nat.le_trans hidSize (by decide))
  let versionB := (encodeU32le 5).append "1.0.0".toUTF8
  have hversionB : encodeSemVer request.version = .ok versionB := by
    rw [hversion]
    have hstring :
        encodeString "1.0.0" = .ok versionB := by
      exact encodeString_eq_okV1 "1.0.0"
        (requireNfc_eq_ok_of_isAscii "1.0.0" (by decide)) (by decide)
    simp only [encodeSemVer, mapCommon,
      show renderSemVer s2RequirementVersionV1 = .ok "1.0.0" by rfl,
      hstring, Bind.bind, Except.bind]
  have hdigestB : encodeDigest request.digest = .ok digestBytes := by
    rw [hdigest]
    have hdigestValid :
        validateDigest ({ algorithm := .sha256, bytes := digestBytes } : Digest) =
          .ok () := by
      simp [validateDigest, hdigestSize]
      rfl
    simp only [encodeDigest, mapCommon, hdigestValid, Bind.bind, Pure.pure,
      Except.bind, Except.pure]
  have hpredicatesB :
      encodeArray encodeRequirementPredicateV1 request.predicates =
        .ok (encodeU32le 0) := by
    rw [hpredicates]
    exact encodeArray_zeroV1 encodeRequirementPredicateV1
  apply encodeRequirementRequestV1_ok_size_of_fields request idB versionB
    digestBytes (encodeU32le 0) hidB hversionB hdigestB hpredicatesB
  · simp only [idB, ByteArray_size_append, encodeU32le_size]
    omega
  · simp only [versionB, ByteArray_size_append, encodeU32le_size]
    decide
  · omega
  · rw [encodeU32le_size]
    decide

private theorem stateCellRequirementsEncodingV1 :
    ∃ bytes,
      encodeProgramRequirementsV1 stateCellSemanticProgramDataV1.requirements =
          .ok bytes ∧
        bytes.size ≤ 8192 := by
  rcases stateCellRequirementFieldValuesV1 with
    ⟨hid0, hversion0, hdigest0, hpredicates0, hid1, hversion1, hdigest1,
      hpredicates1, hid2, hversion2, hdigest2, hpredicates2⟩
  rcases encodeClosedS2RequirementV1 stateCellRequirement0V1
      "failure.atomic-rollback" s2FailureAtomicRollbackDigestBytesV1 hid0
      hversion0 hdigest0 hpredicates0 (by decide) (by decide) (by rfl) with
    ⟨request0B, hrequest0, hrequest0Size⟩
  rcases encodeClosedS2RequirementV1 stateCellRequirement1V1
      "state.persistent" s2StatePersistentDigestBytesV1 hid1 hversion1 hdigest1
      hpredicates1 (by decide) (by decide) (by rfl) with
    ⟨request1B, hrequest1, hrequest1Size⟩
  rcases encodeClosedS2RequirementV1 stateCellRequirement2V1
      "value.checked-arithmetic" s2ValueCheckedArithmeticDigestBytesV1 hid2
      hversion2 hdigest2 hpredicates2 (by decide) (by decide) (by rfl) with
    ⟨request2B, hrequest2, hrequest2Size⟩
  let itemsB := (encodeU32le 3).append
    ((request0B.append request1B).append request2B)
  have hitems :
      encodeArray encodeRequirementRequestV1
          stateCellSemanticProgramDataV1.requirements.items = .ok itemsB := by
    rw [stateCellRequirementItemsV1]
    simpa only [itemsB] using encodeArray_threeV1 encodeRequirementRequestV1
      stateCellRequirement0V1 stateCellRequirement1V1 stateCellRequirement2V1
      request0B request1B request2B hrequest0 hrequest1 hrequest2
  have hitemsSize : itemsB.size ≤ 7168 := by
    simp only [itemsB, ByteArray_size_append, encodeU32le_size]
    omega
  let bytes := taggedBytesV1 "ProgramRequirements" #[itemsB]
  have htag : encodeTagged "ProgramRequirements" #[itemsB] = .ok bytes := by
    simpa only [bytes] using encodeTagged_eq_okV1 "ProgramRequirements" #[itemsB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  refine ⟨bytes, ?_, ?_⟩
  · simp only [encodeProgramRequirementsV1, hitems, htag, Bind.bind, Except.bind]
  · simp only [bytes]
    rw [taggedBytesV1_size, foldl_size_one]
    have htagSize : "ProgramRequirements".toUTF8.size = 19 := by decide
    rw [htagSize]
    omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellRootFieldInvertV1 :
    RootFieldInvertV1 stateCellSemanticProgramDataV1 := by
  rcases stateCellTypeValuesV1 with ⟨htype0, htype1⟩
  rcases stateCellEmptySemanticTablesV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  rcases stateCellCallableInversionsV1 with
    ⟨hcallable0, hcallable1, hcallable2⟩
  rcases stateCellRequirementFieldValuesV1 with
    ⟨hid0, hversion0, hdigest0, hpredicates0, hid1, hversion1, hdigest1,
      hpredicates1, hid2, hversion2, hdigest2, hpredicates2⟩
  have hrequest0 : stateCellRequirement0V1 = {
      id := "failure.atomic-rollback"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2FailureAtomicRollbackDigestBytesV1
      }
      predicates := #[]
    } := by
    cases hrequest : stateCellRequirement0V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid0 hversion0 hdigest0 hpredicates0
        simp only [hid0, hversion0, hdigest0, hpredicates0]
  have hrequest1 : stateCellRequirement1V1 = {
      id := "state.persistent"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2StatePersistentDigestBytesV1
      }
      predicates := #[]
    } := by
    cases hrequest : stateCellRequirement1V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid1 hversion1 hdigest1 hpredicates1
        simp only [hid1, hversion1, hdigest1, hpredicates1]
  have hrequest2 : stateCellRequirement2V1 = {
      id := "value.checked-arithmetic"
      version := s2RequirementVersionV1
      digest := {
        algorithm := .sha256
        bytes := s2ValueCheckedArithmeticDigestBytesV1
      }
      predicates := #[]
    } := by
    cases hrequest : stateCellRequirement2V1 with
    | mk id version digest predicates =>
        simp only [hrequest] at hid2 hversion2 hdigest2 hpredicates2
        simp only [hid2, hversion2, hdigest2, hpredicates2]
  constructor
  · exact ExactMidOffsetInvertAtV1.ofExact
      (exactMidOffsetInvert_qualifiedName
        stateCellSemanticProgramDataV1.qualifiedName) (by decide)
  · rw [stateCellTypesV1, htype0, htype1]
    exact exactAt_array_two_of_exactAtV1 encodeTypeDeclV1 decodeTypeDeclV1
      maxTableElements (by decide) (by decide)
      ({ id := 0, name := none, shape := .uint 64 } : TypeDeclV1)
      ({ id := 1, name := none, shape := .unit } : TypeDeclV1) 1
      (exactAt_typeDecl_uint_noneV1 0 64 1 (by decide))
      (exactAt_typeDecl_unit_noneV1 1 1 (by decide))
  · rw [hconstants]
    exact exactAt_array_emptyV1 encodeConstantV1 decodeConstantV1
      maxTableElements 1
  · rw [stateCellLogicalStateV1]
    apply exactAt_array_one_of_exactAtV1 encodeStateDeclV1 decodeStateDeclV1
      maxTableElements (by decide) stateCellState0V1 1
    rw [stateCellState0ValueV1]
    exact exactAt_stateDecl_publicV1 0 0 "count" (by rfl) 1 (by decide)
  · rw [hevents]
    exact exactAt_array_emptyV1 encodeEventDeclV1 decodeEventDeclV1
      maxTableElements 1
  · rw [herrors]
    exact exactAt_array_emptyV1 encodeErrorDeclV1 decodeErrorDeclV1
      maxTableElements 1
  · rw [stateCellCallablesV1]
    exact exactAt_array_three_of_exactAtV1 encodeCallableV1 decodeCallableV1
      maxTableElements (by decide) stateCellCallable0V1 stateCellCallable1V1
      stateCellCallable2V1 1 hcallable0 hcallable1 hcallable2
  · rw [hinvariants]
    exact exactAt_array_emptyV1 encodeInvariantDeclV1 decodeInvariantDeclV1
      maxTableElements 1
  · apply exactAt_programRequirements_of_itemsV1
      stateCellSemanticProgramDataV1.requirements 1 (by decide)
    rw [stateCellRequirementItemsV1, hrequest0, hrequest1, hrequest2]
    exact exactAt_array_three_of_exactAtV1 encodeRequirementRequestV1
      decodeRequirementRequestV1 maxArrayElements (by decide)
      ({
        id := "failure.atomic-rollback"
        version := s2RequirementVersionV1
        digest := {
          algorithm := .sha256
          bytes := s2FailureAtomicRollbackDigestBytesV1
        }
        predicates := #[]
      } : RequirementRequestV1)
      ({
        id := "state.persistent"
        version := s2RequirementVersionV1
        digest := {
          algorithm := .sha256
          bytes := s2StatePersistentDigestBytesV1
        }
        predicates := #[]
      } : RequirementRequestV1)
      ({
        id := "value.checked-arithmetic"
        version := s2RequirementVersionV1
        digest := {
          algorithm := .sha256
          bytes := s2ValueCheckedArithmeticDigestBytesV1
        }
        predicates := #[]
      } : RequirementRequestV1)
      2
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          "failure.atomic-rollback" s2RequirementVersionV1
          { algorithm := .sha256,
            bytes := s2FailureAtomicRollbackDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion) (by decide))
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          "state.persistent" s2RequirementVersionV1
          { algorithm := .sha256, bytes := s2StatePersistentDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion) (by decide))
      (ExactMidOffsetInvertAtV1.ofExact
        (exactMidOffsetInvert_requirementRequest_emptyPredicates
          "value.checked-arithmetic" s2RequirementVersionV1
          { algorithm := .sha256,
            bytes := s2ValueCheckedArithmeticDigestBytesV1 }
          scalarMidOffsetInvert_semVer_s2RequirementVersion) (by decide))

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellRootEncodingGatesV1 :
    validateProgramQualifiedNameShapeV1
        stateCellSemanticProgramDataV1.qualifiedName = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.types.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.constants.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.logicalState.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.events.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.errors.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.callables.size = .ok () ∧
      checkTableSize stateCellSemanticProgramDataV1.invariants.size = .ok () := by
  rcases stateCellEmptySemanticTablesV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  refine ⟨?_, ?_, ?_, ?_, ?_, ?_, ?_, ?_⟩
  · rfl
  · rw [stateCellTypesV1]
    rfl
  · rw [hconstants]
    rfl
  · rw [stateCellLogicalStateV1]
    rfl
  · rw [hevents]
    rfl
  · rw [herrors]
    rfl
  · rw [stateCellCallablesV1]
    rfl
  · rw [hinvariants]
    rfl

/- Exact canonical wire certificate for the data produced by the sole
    StateCell source normalizer. Every witness is composed from production
    field encoders; no materialized root bytes or alternate encoder is used. -/
set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellSemanticEncodingSuccessV1 :
    ∃ bytes,
      encodeSemanticProgramDataV1 stateCellSemanticProgramDataV1 = .ok bytes ∧
        bytes.size ≤ maxCanonicalProgramBytes := by
  rcases stateCellRootEncodingGatesV1 with
    ⟨hnameShape, htypesSize, hconstantsSize, hstateSize, heventsSize,
      herrorsSize, hcallablesSize, hinvariantsSize⟩
  rcases stateCellQualifiedNameEncodingV1 with
    ⟨qualifiedNameB, hqualifiedName, hqualifiedNameSize⟩
  rcases stateCellTypesEncodingV1 with ⟨typesB, htypes, htypesBSize⟩
  rcases stateCellLogicalStateEncodingV1 with ⟨stateB, hstate, hstateBSize⟩
  rcases stateCellEmptySemanticTableEncodingsV1 with
    ⟨hconstants, hevents, herrors, hinvariants⟩
  rcases stateCellCallablesEncodingV1 with
    ⟨callablesB, hcallables, hcallablesBSize⟩
  rcases stateCellRequirementsEncodingV1 with
    ⟨requirementsB, hrequirements, hrequirementsBSize⟩
  let emptyB := encodeU32le 0
  let body := taggedBytesV1 "SemanticProgram.Data"
    #[qualifiedNameB, typesB, emptyB, stateB, emptyB, emptyB, callablesB,
      emptyB, requirementsB]
  have hbody :
      encodeTagged "SemanticProgram.Data"
          #[qualifiedNameB, typesB, emptyB, stateB, emptyB, emptyB, callablesB,
            emptyB, requirementsB] = .ok body := by
    simpa only [body] using encodeTagged_eq_okV1 "SemanticProgram.Data"
      #[qualifiedNameB, typesB, emptyB, stateB, emptyB, emptyB, callablesB,
        emptyB, requirementsB]
      (by decide) (by decide) (by decide) (by decide) (by simp)
  have hemptySize : emptyB.size = 4 := by
    simp only [emptyB, encodeU32le_size]
  have hbodySize : body.size ≤ 2097152 := by
    simp only [body]
    rw [taggedBytesV1_size, foldl_size_nine]
    have htagSize : "SemanticProgram.Data".toUTF8.size = 20 := by decide
    rw [htagSize, hemptySize]
    omega
  have houtSize :
      ((encodeMagicPrefix semanticProgramMagicV1).append body).size ≤
        maxCanonicalProgramBytes := by
    rw [ByteArray_size_append, encodeMagicPrefix_size]
    have hmagicSize : semanticProgramMagicV1.toUTF8.size + 1 ≤ 64 := by decide
    have hcap : 64 + 2097152 ≤ maxCanonicalProgramBytes := by decide
    omega
  let bytes := (encodeMagicPrefix semanticProgramMagicV1).append body
  refine ⟨bytes, ?_, ?_⟩
  · apply encodeSemanticProgramDataV1_eq_of_fields stateCellSemanticProgramDataV1
      qualifiedNameB typesB emptyB stateB emptyB emptyB callablesB emptyB
      requirementsB body hnameShape htypesSize hconstantsSize hstateSize
      heventsSize herrorsSize hcallablesSize hinvariantsSize
      stateCellSemanticStructureSuccessV1 hqualifiedName htypes hconstants hstate
      hevents herrors hcallables hinvariants hrequirements hbody houtSize
  · simpa only [bytes] using houtSize

end ProofForgeV2.Targets.Solana
