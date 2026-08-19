import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Semantic.Wire.CodecInvertCallableV1
import ProofForgeV2.Semantic.Wire.CodecInvertRootV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Solana.EmitIRV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1
import ProofForgeV2.Targets.Solana.ProductionCompositionV1
import ProofForgeV2.Targets.Solana.ProductionMethodV1
import ProofForgeV2.Targets.Solana.SbpfHandlerJoinV1
import ProofForgeV2.Targets.Solana.SbpfStateCellProductionStructureDataV1
import ProofForgeV2.Targets.Solana.SbpfStateCellTypedV1

-- The independent structural certificates below each retain large normalized
-- terms. Lean 4.31 command-line elaboration otherwise checks several of them
-- concurrently and multiplies peak memory without reducing proof work.
set_option Elab.async false

/-!
# Solana StateCell production subject

Continuation of `SbpfStateCellProductionDataV1`: CFG block projections,
codec inversions, and certified joins. Block getElem is isolated here so
the kernel heap from the data-stage projections is not retained.
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


set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable0BlockV1 : BlockV1 :=
  stateCellCallable0V1.blocks[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1BlockV1 : BlockV1 :=
  stateCellCallable1V1.blocks[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable2BlockV1 : BlockV1 :=
  stateCellCallable2V1.blocks[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable0Parameter0V1 : ParameterV1 :=
  stateCellCallable0V1.params[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1Parameter0V1 : ParameterV1 :=
  stateCellCallable1V1.params[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable0Instruction0V1 : InstructionV1 :=
  stateCellCallable0BlockV1.instructions[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1Instruction0V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[0]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1Instruction1V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[1]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1Instruction2V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[2]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable1Instruction3V1 : InstructionV1 :=
  stateCellCallable1BlockV1.instructions[3]'(by decide)

set_option maxHeartbeats 400000 in
set_option maxRecDepth 100000 in
def stateCellCallable2Instruction0V1 : InstructionV1 :=
  stateCellCallable2BlockV1.instructions[0]'(by decide)

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallableBlockTablesV1 :
    stateCellCallable0V1.blocks = #[stateCellCallable0BlockV1] ∧
      stateCellCallable1V1.blocks = #[stateCellCallable1BlockV1] ∧
      stateCellCallable2V1.blocks = #[stateCellCallable2BlockV1] := by
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable0V1.blocks.size = 1 := by decide
          rw [hsize] at hleft
          omega
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable1V1.blocks.size = 1 := by decide
          rw [hsize] at hleft
          omega
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable2V1.blocks.size = 1 := by decide
          rw [hsize] at hleft
          omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallableInstructionTablesV1 :
    stateCellCallable0BlockV1.instructions =
        #[stateCellCallable0Instruction0V1] ∧
      stateCellCallable1BlockV1.instructions =
        #[stateCellCallable1Instruction0V1, stateCellCallable1Instruction1V1,
          stateCellCallable1Instruction2V1, stateCellCallable1Instruction3V1] ∧
      stateCellCallable2BlockV1.instructions =
        #[stateCellCallable2Instruction0V1] := by
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable0BlockV1.instructions.size = 1 := by decide
          rw [hsize] at hleft
          omega
  constructor
  · apply Array.ext
    · decide
    · intro index hleft _hright
      have hsize : stateCellCallable1BlockV1.instructions.size = 4 := by decide
      rw [hsize] at hleft
      match index with
      | 0 => rfl
      | 1 => rfl
      | 2 => rfl
      | 3 => rfl
      | n + 4 => omega
  · apply Array.ext
    · decide
    · intro index hleft _hright
      match index with
      | 0 => rfl
      | n + 1 =>
          have hsize : stateCellCallable2BlockV1.instructions.size = 1 := by decide
          rw [hsize] at hleft
          omega

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellCallableFieldValuesV1 :
    stateCellCallable0V1.id = 0 ∧
      stateCellCallable0V1.kind = .initializer ∧
      stateCellCallable0V1.name = none ∧
      stateCellCallable0V1.params = #[stateCellCallable0Parameter0V1] ∧
      stateCellCallable0Parameter0V1 = {
        valueId := 0, name := "initial", typeId := 0, visibility := .public_
      } ∧
      stateCellCallable0V1.result = { typeId := 1, visibility := .public_ } ∧
      stateCellCallable0V1.entryBlock = 0 ∧
      stateCellCallable0V1.loopBounds = #[] ∧
      stateCellCallable0V1.invariantSteps = none ∧
    stateCellCallable1V1.id = 1 ∧
      stateCellCallable1V1.kind = .entry ∧
      stateCellCallable1V1.name = some "increment" ∧
      stateCellCallable1V1.params = #[stateCellCallable1Parameter0V1] ∧
      stateCellCallable1Parameter0V1 = {
        valueId := 0, name := "delta", typeId := 0, visibility := .public_
      } ∧
      stateCellCallable1V1.result = { typeId := 0, visibility := .public_ } ∧
      stateCellCallable1V1.entryBlock = 0 ∧
      stateCellCallable1V1.loopBounds = #[] ∧
      stateCellCallable1V1.invariantSteps = none ∧
    stateCellCallable2V1.id = 2 ∧
      stateCellCallable2V1.kind = .view ∧
      stateCellCallable2V1.name = some "get" ∧
      stateCellCallable2V1.params = #[] ∧
      stateCellCallable2V1.result = { typeId := 0, visibility := .public_ } ∧
      stateCellCallable2V1.entryBlock = 0 ∧
      stateCellCallable2V1.loopBounds = #[] ∧
      stateCellCallable2V1.invariantSteps = none := by
  repeat' apply And.intro
  all_goals rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellBlockFieldValuesV1 :
    stateCellCallable0BlockV1.id = 0 ∧
      stateCellCallable0BlockV1.params = #[] ∧
      stateCellCallable0BlockV1.terminator = .return_ none ∧
    stateCellCallable1BlockV1.id = 0 ∧
      stateCellCallable1BlockV1.params = #[] ∧
      stateCellCallable1BlockV1.terminator = .return_ (some 3) ∧
    stateCellCallable2BlockV1.id = 0 ∧
      stateCellCallable2BlockV1.params = #[] ∧
      stateCellCallable2BlockV1.terminator = .return_ (some 0) := by
  repeat' apply And.intro
  all_goals rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellInstructionFieldValuesV1 :
    stateCellCallable0Instruction0V1.result = none ∧
      stateCellCallable0Instruction0V1.op = .stateStore 0 0 ∧
    stateCellCallable1Instruction0V1.result = some { valueId := 1, typeId := 0 } ∧
      stateCellCallable1Instruction0V1.op = .stateLoad 0 ∧
    stateCellCallable1Instruction1V1.result = some { valueId := 2, typeId := 0 } ∧
      stateCellCallable1Instruction1V1.op = .binary .add 1 0 ∧
    stateCellCallable1Instruction2V1.result = none ∧
      stateCellCallable1Instruction2V1.op = .stateStore 0 2 ∧
    stateCellCallable1Instruction3V1.result = some { valueId := 3, typeId := 0 } ∧
      stateCellCallable1Instruction3V1.op = .stateLoad 0 ∧
    stateCellCallable2Instruction0V1.result = some { valueId := 0, typeId := 0 } ∧
      stateCellCallable2Instruction0V1.op = .stateLoad 0 := by
  repeat' apply And.intro
  all_goals rfl

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableUsesV1 :
    opValueUses stateCellCallable0Instruction0V1.op = #[0] ∧
      terminatorValueUses stateCellCallable0BlockV1.terminator = #[] ∧
      opValueUses stateCellCallable1Instruction0V1.op = #[] ∧
      opValueUses stateCellCallable1Instruction1V1.op = #[1, 0] ∧
      opValueUses stateCellCallable1Instruction2V1.op = #[2] ∧
      opValueUses stateCellCallable1Instruction3V1.op = #[] ∧
      terminatorValueUses stateCellCallable1BlockV1.terminator = #[3] ∧
      opValueUses stateCellCallable2Instruction0V1.op = #[] ∧
      terminatorValueUses stateCellCallable2BlockV1.terminator = #[0] := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallableDefSitesValuesV1 :
    stateCellCallable0DefSitesV1 = #[(0, 0)] ∧
      stateCellCallable1DefSitesV1 = #[(0, 0), (1, 0), (2, 0), (3, 0)] ∧
      stateCellCallable2DefSitesV1 = #[(0, 0)] := by
  decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0ValueFlowSuccessV1 :
    validateCallableCfgValueFlow stateCellCallable0V1
      stateCellCallable0ReachabilityV1 = .ok () := by
  rw [stateCellCallableReachabilityValuesV1.1]
  apply validateCallableCfgValueFlow_eq_ok_of_phases stateCellCallable0V1
      #[true] stateCellCallable0DefSitesV1
  · rfl
  · rw [stateCellCallableDefSitesValuesV1.1]
    apply exceptUnitSuccessV1
    decide
  · rw [stateCellCallableDefSitesValuesV1.1]
    unfold checkValueIdUsesExist
    rw [stateCellCallableBlockTablesV1.1]
    rcases stateCellCallableUsesV1 with
      ⟨hop, hterm, _hop10, _hop11, _hop12, _hop13, _hterm1, _hop2, _hterm2⟩
    simp [stateCellCallableInstructionTablesV1.1, hop, hterm,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · rw [stateCellCallableDefSitesValuesV1.1]
    unfold validateCallableDominanceOfUse
    rw [stateCellCallableBlockTablesV1.1]
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1ValueFlowSuccessV1 :
    validateCallableCfgValueFlow stateCellCallable1V1
      stateCellCallable1ReachabilityV1 = .ok () := by
  rw [stateCellCallableReachabilityValuesV1.2.1]
  apply validateCallableCfgValueFlow_eq_ok_of_phases stateCellCallable1V1
      #[true] stateCellCallable1DefSitesV1
  · rfl
  · rw [stateCellCallableDefSitesValuesV1.2.1]
    apply exceptUnitSuccessV1
    decide
  · rw [stateCellCallableDefSitesValuesV1.2.1]
    unfold checkValueIdUsesExist
    rw [stateCellCallableBlockTablesV1.2.1]
    rcases stateCellCallableUsesV1 with
      ⟨_hop0, _hterm0, hop10, hop11, hop12, hop13, hterm, _hop2, _hterm2⟩
    simp [stateCellCallableInstructionTablesV1.2.1, hop10, hop11, hop12,
      hop13, hterm, Pure.pure, Except.pure, Bind.bind, Except.bind]
  · rw [stateCellCallableDefSitesValuesV1.2.1]
    unfold validateCallableDominanceOfUse
    rw [stateCellCallableBlockTablesV1.2.1]
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2ValueFlowSuccessV1 :
    validateCallableCfgValueFlow stateCellCallable2V1
      stateCellCallable2ReachabilityV1 = .ok () := by
  rw [stateCellCallableReachabilityValuesV1.2.2]
  apply validateCallableCfgValueFlow_eq_ok_of_phases stateCellCallable2V1
      #[true] stateCellCallable2DefSitesV1
  · rfl
  · rw [stateCellCallableDefSitesValuesV1.2.2]
    apply exceptUnitSuccessV1
    decide
  · rw [stateCellCallableDefSitesValuesV1.2.2]
    unfold checkValueIdUsesExist
    rw [stateCellCallableBlockTablesV1.2.2]
    rcases stateCellCallableUsesV1 with
      ⟨_hop0, _hterm0, _hop10, _hop11, _hop12, _hop13, _hterm1, hop, hterm⟩
    simp [stateCellCallableInstructionTablesV1.2.2, hop, hterm,
      Pure.pure, Except.pure, Bind.bind, Except.bind]
  · rw [stateCellCallableDefSitesValuesV1.2.2]
    unfold validateCallableDominanceOfUse
    rw [stateCellCallableBlockTablesV1.2.2]
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable0CfgSuccessV1 :
    validateCallableCfgShape stateCellCallable0V1
      stateCellSemanticProgramDataV1.types.size
      stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1 =
        .ok () := by
  apply validateCallableCfgShape_eq_ok_of_phases
      stateCellCallable0V1 stateCellSemanticProgramDataV1.types.size
        stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1
          stateCellCallable0ReachabilityV1
  · exact exceptToOptionGetSuccessV1 _ stateCellCallable0ReachabilitySomeV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallable0ValueFlowSuccessV1
  ·
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable1CfgSuccessV1 :
    validateCallableCfgShape stateCellCallable1V1
      stateCellSemanticProgramDataV1.types.size
      stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1 =
        .ok () := by
  apply validateCallableCfgShape_eq_ok_of_phases
      stateCellCallable1V1 stateCellSemanticProgramDataV1.types.size
        stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1
          stateCellCallable1ReachabilityV1
  · exact exceptToOptionGetSuccessV1 _ stateCellCallable1ReachabilitySomeV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallable1ValueFlowSuccessV1
  ·
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCallable2CfgSuccessV1 :
    validateCallableCfgShape stateCellCallable2V1
      stateCellSemanticProgramDataV1.types.size
      stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1 =
        .ok () := by
  apply validateCallableCfgShape_eq_ok_of_phases
      stateCellCallable2V1 stateCellSemanticProgramDataV1.types.size
        stateCellSemanticProgramDataV1.types stateCellSemanticProgramDataV1
          stateCellCallable2ReachabilityV1
  · exact exceptToOptionGetSuccessV1 _ stateCellCallable2ReachabilitySomeV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallable2ValueFlowSuccessV1
  ·
    apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellGenericCfgSuccessV1 :
    validateGenericCfgPhasesV1 stateCellSemanticProgramDataV1 = .ok () := by
  apply validateGenericCfgPhasesV1_three_eq_ok stateCellSemanticProgramDataV1
      stateCellCallable0V1 stateCellCallable1V1 stateCellCallable2V1
  · exact stateCellCallablesV1
  · exact stateCellCallable0CfgSuccessV1
  · exact stateCellCallable1CfgSuccessV1
  · exact stateCellCallable2CfgSuccessV1
  · apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellInvariantClosureSomeV1 :
    (validateInvariantClosurePhasesV1
      stateCellSemanticProgramDataV1.callables).toOption.isSome = true := by
  decide

private def stateCellInvariantClosureMembersV1 : Array Bool :=
  (validateInvariantClosurePhasesV1
    stateCellSemanticProgramDataV1.callables).toOption.get
      stateCellInvariantClosureSomeV1

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
private theorem stateCellCfgInvariantPhasesSuccessV1 :
    validateCfgInvariantPhasesV1 stateCellSemanticProgramDataV1 = .ok () := by
  apply validateCfgInvariantPhasesV1_eq_ok stateCellSemanticProgramDataV1
      stateCellInvariantClosureMembersV1
  · exact stateCellGenericCfgSuccessV1
  · exact exceptToOptionGetSuccessV1 _ stateCellInvariantClosureSomeV1
  · apply exceptUnitSuccessV1
    decide

set_option maxHeartbeats 10000000 in
set_option maxRecDepth 100000 in
theorem stateCellSemanticStructureSuccessV1 :
    validateSemanticProgramStructureV1 stateCellSemanticProgramDataV1 =
      .ok () := by
  apply validateSemanticProgramStructureV1_eq_ok_of_phases
      stateCellSemanticProgramDataV1 maxCanonicalProgramBytes
        maxCanonicalProgramBytes
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellTypeKeyPhasesSuccessV1
  · exact stateCellUsageClosureSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptToOptionGetSuccessV1
    decide
  · apply exceptToOptionGetSuccessV1
    decide
  · exact stateCellConstantNamesSuccessV1
  · exact stateCellStateNamesSuccessV1
  · exact stateCellEventNamesSuccessV1
  · exact stateCellErrorNamesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCallableSignaturePhasesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · exact stateCellCfgInvariantPhasesSuccessV1
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide
  · apply exceptUnitSuccessV1
    decide

end ProofForgeV2.Targets.Solana
