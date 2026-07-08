import ProofForge.Backend.Solana.SbpfExec

/-!
Non-Counter reuse smoke for `SbpfExec`.

Models tiny scalar-read and conditional-jump paths, proving each by composing
generic `ReadyOpcodeAt` reductions and a `ReductionChainProvider`, mirroring
`EvmRefinement/PowdrExecSmoke.lean`.
-/

namespace ProofForge.Backend.Solana.SbpfExecSmoke

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Syscalls
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.SbpfExec

abbrev Program := SbpfProgram
abbrev State := SbpfState
abbrev StepReduction := ProofForge.Backend.Solana.SbpfExec.StepReduction
abbrev StepReductionChain := ProofForge.Backend.Solana.SbpfExec.StepReductionChain
abbrev ReadyOpcodeAt := ProofForge.Backend.Solana.SbpfExec.ReadyOpcodeAt
abbrev ExecutionSegment := ProofForge.Backend.Solana.SbpfExec.ExecutionSegment
abbrev ReductionChainProvider := ProofForge.Backend.Solana.SbpfExec.ReductionChainProvider

def slotPtr : Nat := 200
def slotValue : Nat := 42

def smokeProgram : Program := {
  instructions := #[
    inst .mov64 (some .r1) none none (some (.num slotPtr)),
    inst .ldxdw (some .r2) (some .r1) (some (.num 0)) none,
    inst .call none none none (some (.sym sol_set_return_data)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def smokeInitialState : State :=
  { regs := regSet (regSet emptyRegs .r10 stackBase) .r1 0
    memory := #[(slotPtr, slotValue)]
    pc := 0 }

def smokeState1 : State := execMov64 smokeInitialState .r1 slotPtr

def smokeState2 : State := execLoad smokeState1 .r2 slotPtr slotValue

def smokeState3 : State := execSetReturnData smokeState2 slotValue

def smokeFinalState : State := execExit smokeState3 0

theorem smoke_not_halted0 : ¬ smokeInitialState.halted := by
  intro h; cases h

theorem smoke_not_halted1 : ¬ smokeState1.halted := by
  intro h; cases h

theorem smoke_not_halted2 : ¬ smokeState2.halted := by
  intro h; cases h

theorem smoke_not_halted3 : ¬ smokeState3.halted := by
  intro h; cases h

theorem smokeFinal_halted : smokeFinalState.halted := rfl

def smokeAt0 : ReadyOpcodeAt smokeProgram 0
    (inst .mov64 (some .r1) none none (some (.num slotPtr)))
    smokeInitialState :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := smoke_not_halted0 }

def smokeAt1 : ReadyOpcodeAt smokeProgram 1
    (inst .ldxdw (some .r2) (some .r1) (some (.num 0)) none)
    smokeState1 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := smoke_not_halted1 }

def smokeAt2 : ReadyOpcodeAt smokeProgram 2
    (inst .call none none none (some (.sym sol_set_return_data)))
    smokeState2 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := smoke_not_halted2 }

def smokeAt3 : ReadyOpcodeAt smokeProgram 3
    (inst .exit none none none none)
    smokeState3 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := smoke_not_halted3 }

theorem smoke_r1_ptr1 : regGet smokeState1.regs .r1 = slotPtr := by
  unfold smokeState1 smokeInitialState execMov64 setReg nextPc regGet slotPtr
  rfl

theorem smoke_read_slot1 : smokeState1.memory.read slotPtr = slotValue := by
  unfold smokeState1 smokeInitialState execMov64 setReg nextPc slotPtr slotValue
  simp [Memory.read]

theorem smoke_addr_r1_1 : memoryAddress smokeState1 .r1 0 = slotPtr := by
  simp [memoryAddress, smoke_r1_ptr1]

theorem smoke_r1_ptr2 : regGet smokeState2.regs .r1 = slotPtr := by
  unfold smokeState2 smokeState1 smokeInitialState execLoad execMov64 setReg nextPc regGet slotPtr
  rfl

theorem smoke_read_slot2 : smokeState2.memory.read slotPtr = slotValue := by
  unfold smokeState2 smokeState1 smokeInitialState execLoad execMov64 setReg nextPc slotPtr slotValue
  simp [Memory.read]

theorem smoke_r0_zero3 : regGet smokeState3.regs .r0 = 0 := by
  unfold smokeState3 smokeState2 smokeState1 smokeInitialState
    execSetReturnData execLoad execMov64 setReg nextPc regGet
  rfl

def smokeScalarReadPre (s : State) : Prop :=
  s = smokeInitialState

def smokeScalarReadPost (_s0 finalState : State) : Prop :=
  finalState = smokeFinalState

theorem smoke_scalar_read_reductionChain :
    StepReductionChain smokeProgram smokeInitialState 4 smokeFinalState := by
  have hmovReduction : StepReduction smokeProgram smokeInitialState smokeState1 :=
    reduction_mov64_imm_at_ok smokeAt0
  have hldxReduction : StepReduction smokeProgram smokeState1 smokeState2 :=
    reduction_ldxdw_at_ok smokeAt1 smoke_addr_r1_1 smoke_read_slot1
  have hsetReduction : StepReduction smokeProgram smokeState2 smokeState3 :=
    reduction_syscall_set_return_data_at_ok smokeAt2 smoke_r1_ptr2 smoke_read_slot2
  have hexitReduction : StepReduction smokeProgram smokeState3 smokeFinalState :=
    reduction_exit_at_ok smokeAt3 smoke_r0_zero3
  have chain01 := StepReductionChain.single hmovReduction
  have chain12 := StepReductionChain.single hldxReduction
  have chain23 := StepReductionChain.single hsetReduction
  have chain34 := StepReductionChain.single hexitReduction
  exact StepReductionChain.append (StepReductionChain.append chain01 chain12)
    (StepReductionChain.append chain23 chain34)

theorem smoke_scalar_read_executionSegment :
    ExecutionSegment smokeProgram 4 smokeScalarReadPost smokeInitialState smokeFinalState :=
  executionSegment_of_reductionChain smoke_scalar_read_reductionChain rfl

def smokeScalarReadReductionChainProvider :
    ReductionChainProvider smokeProgram smokeScalarReadPre 4 smokeScalarReadPost where
  chain := by
    intro state hpre
    subst hpre
    exact ⟨smokeFinalState, smoke_scalar_read_reductionChain, rfl⟩

theorem smoke_runSteps :
    runSteps smokeProgram 4 smokeInitialState = .ok smokeFinalState :=
  runSteps_of_executionSegment smoke_scalar_read_executionSegment smokeFinal_halted

theorem smokeScalarReadPost_halted {s f : State} (hpost : smokeScalarReadPost s f) : f.halted :=
  hpost ▸ smokeFinal_halted

theorem smoke_runSteps_via_provider :
    ∃ finalState,
      runSteps smokeProgram 4 smokeInitialState = .ok finalState ∧
      smokeScalarReadPost smokeInitialState finalState :=
  runSteps_post_of_reductionChainProvider
    smokeScalarReadReductionChainProvider rfl smokeScalarReadPost_halted

/-! ### Conditional-jump smoke (`jne` taken + `jeq` taken)

`jne` path: load a nonzero slot, branch over a marker `mov64`, then exit.
`jeq` path: compare an immediate against a loaded register and branch likewise.
-/

def jumpBranchPc : Nat := 4
def jumpMarkerValue : Nat := 99
def jeqMatchValue : Nat := 42

def jumpSmokeProgram : Program := {
  instructions := #[
    inst .mov64 (some .r1) none none (some (.num slotPtr)),
    inst .ldxdw (some .r2) (some .r1) (some (.num 0)) none,
    inst .jne (some .r2) none (some (.num jumpBranchPc)) (some (.num 0)),
    inst .mov64 (some .r0) none none (some (.num jumpMarkerValue)),
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def jeqSmokeProgram : Program := {
  instructions := #[
    inst .mov64 (some .r1) none none (some (.num jeqMatchValue)),
    inst .jeq (some .r1) none (some (.num 3)) (some (.num jeqMatchValue)),
    inst .mov64 (some .r0) none none (some (.num jumpMarkerValue)),
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def jumpSmokeInitialState : State :=
  { regs := regSet (regSet emptyRegs .r10 stackBase) .r1 0
    memory := #[(slotPtr, slotValue)]
    pc := 0 }

def jumpSmokeState1 : State := execMov64 jumpSmokeInitialState .r1 slotPtr

def jumpSmokeState2 : State := execLoad jumpSmokeState1 .r2 slotPtr slotValue

def jumpSmokeState3 : State := execJump jumpSmokeState2 jumpBranchPc

def jumpSmokeState4 : State := execMov64 jumpSmokeState3 .r0 0

def jumpSmokeFinalState : State := execExit jumpSmokeState4 0

def jeqSmokeInitialState : State :=
  { regs := regSet emptyRegs .r10 stackBase, pc := 0 }

def jeqSmokeState1 : State := execMov64 jeqSmokeInitialState .r1 jeqMatchValue

def jeqSmokeState2 : State := execJump jeqSmokeState1 3

def jeqSmokeState3 : State := execMov64 jeqSmokeState2 .r0 0

def jeqSmokeFinalState : State := execExit jeqSmokeState3 0

theorem jump_not_halted0 : ¬ jumpSmokeInitialState.halted := by intro h; cases h
theorem jump_not_halted1 : ¬ jumpSmokeState1.halted := by intro h; cases h
theorem jump_not_halted2 : ¬ jumpSmokeState2.halted := by intro h; cases h
theorem jump_not_halted3 : ¬ jumpSmokeState3.halted := by intro h; cases h
theorem jump_not_halted4 : ¬ jumpSmokeState4.halted := by intro h; cases h
theorem jumpFinal_halted : jumpSmokeFinalState.halted := rfl

theorem jeq_not_halted0 : ¬ jeqSmokeInitialState.halted := by intro h; cases h
theorem jeq_not_halted1 : ¬ jeqSmokeState1.halted := by intro h; cases h
theorem jeq_not_halted2 : ¬ jeqSmokeState2.halted := by intro h; cases h
theorem jeq_not_halted3 : ¬ jeqSmokeState3.halted := by intro h; cases h
theorem jeqFinal_halted : jeqSmokeFinalState.halted := rfl

def jumpAt0 : ReadyOpcodeAt jumpSmokeProgram 0
    (inst .mov64 (some .r1) none none (some (.num slotPtr)))
    jumpSmokeInitialState :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jump_not_halted0 }

def jumpAt1 : ReadyOpcodeAt jumpSmokeProgram 1
    (inst .ldxdw (some .r2) (some .r1) (some (.num 0)) none)
    jumpSmokeState1 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jump_not_halted1 }

def jumpAt2 : ReadyOpcodeAt jumpSmokeProgram 2
    (inst .jne (some .r2) none (some (.num jumpBranchPc)) (some (.num 0)))
    jumpSmokeState2 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jump_not_halted2 }

def jumpAt4 : ReadyOpcodeAt jumpSmokeProgram 4
    (inst .mov64 (some .r0) none none (some (.num 0)))
    jumpSmokeState3 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jump_not_halted3 }

def jumpAt5 : ReadyOpcodeAt jumpSmokeProgram 5
    (inst .exit none none none none)
    jumpSmokeState4 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jump_not_halted4 }

def jeqAt0 : ReadyOpcodeAt jeqSmokeProgram 0
    (inst .mov64 (some .r1) none none (some (.num jeqMatchValue)))
    jeqSmokeInitialState :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jeq_not_halted0 }

def jeqAt1 : ReadyOpcodeAt jeqSmokeProgram 1
    (inst .jeq (some .r1) none (some (.num 3)) (some (.num jeqMatchValue)))
    jeqSmokeState1 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jeq_not_halted1 }

def jeqAt3 : ReadyOpcodeAt jeqSmokeProgram 3
    (inst .mov64 (some .r0) none none (some (.num 0)))
    jeqSmokeState2 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jeq_not_halted2 }

def jeqAt4 : ReadyOpcodeAt jeqSmokeProgram 4
    (inst .exit none none none none)
    jeqSmokeState3 :=
  { decoded := { pcAt := rfl, decodedAt := rfl }
    running := jeq_not_halted3 }

theorem jump_r1_ptr1 : regGet jumpSmokeState1.regs .r1 = slotPtr := by
  unfold jumpSmokeState1 jumpSmokeInitialState execMov64 setReg nextPc regGet slotPtr
  rfl

theorem jump_read_slot1 : jumpSmokeState1.memory.read slotPtr = slotValue := by
  unfold jumpSmokeState1 jumpSmokeInitialState execMov64 setReg nextPc slotPtr slotValue
  simp [Memory.read]

theorem jump_addr_r1_1 : memoryAddress jumpSmokeState1 .r1 0 = slotPtr := by
  simp [memoryAddress, jump_r1_ptr1]

theorem jump_r2_slot2 : regGet jumpSmokeState2.regs .r2 = slotValue := by
  unfold jumpSmokeState2 jumpSmokeState1 jumpSmokeInitialState execLoad execMov64 setReg nextPc
    regGet slotPtr slotValue
  rfl

theorem jump_r2_ne_zero : slotValue ≠ 0 := by decide

theorem jump_r0_zero4 : regGet jumpSmokeState4.regs .r0 = 0 := by
  unfold jumpSmokeState4 jumpSmokeState3 jumpSmokeState2 jumpSmokeState1 jumpSmokeInitialState
    execMov64 execJump execLoad setReg nextPc regGet
  rfl

theorem jeq_r1_match1 : regGet jeqSmokeState1.regs .r1 = jeqMatchValue := by
  unfold jeqSmokeState1 jeqSmokeInitialState execMov64 setReg nextPc regGet jeqMatchValue
  rfl

theorem jeq_r0_zero3 : regGet jeqSmokeState3.regs .r0 = 0 := by
  unfold jeqSmokeState3 jeqSmokeState2 jeqSmokeState1 jeqSmokeInitialState
    execMov64 execJump setReg nextPc regGet
  rfl

def jumpSmokeTakenPre (s : State) : Prop :=
  s = jumpSmokeInitialState

def jumpSmokeTakenPost (_s0 finalState : State) : Prop :=
  finalState = jumpSmokeFinalState

def jeqSmokeTakenPre (s : State) : Prop :=
  s = jeqSmokeInitialState

def jeqSmokeTakenPost (_s0 finalState : State) : Prop :=
  finalState = jeqSmokeFinalState

theorem jump_taken_reductionChain :
    StepReductionChain jumpSmokeProgram jumpSmokeInitialState 5 jumpSmokeFinalState := by
  have hmov := reduction_mov64_imm_at_ok jumpAt0
  have hldx := reduction_ldxdw_at_ok jumpAt1 jump_addr_r1_1 jump_read_slot1
  have hjne := reduction_jne_imm_taken_at_ok jumpAt2 jump_r2_slot2 jump_r2_ne_zero
  have hmov0 := reduction_mov64_imm_at_ok jumpAt4
  have hexit := reduction_exit_at_ok jumpAt5 jump_r0_zero4
  exact StepReductionChain.append
    (StepReductionChain.append (StepReductionChain.append
      (StepReductionChain.append (StepReductionChain.single hmov)
        (StepReductionChain.single hldx))
      (StepReductionChain.single hjne))
      (StepReductionChain.single hmov0))
    (StepReductionChain.single hexit)

theorem jeq_taken_reductionChain :
    StepReductionChain jeqSmokeProgram jeqSmokeInitialState 4 jeqSmokeFinalState := by
  have hmov := reduction_mov64_imm_at_ok jeqAt0
  have hjeq := reduction_jeq_imm_taken_at_ok jeqAt1 jeq_r1_match1 rfl
  have hmov0 := reduction_mov64_imm_at_ok jeqAt3
  have hexit := reduction_exit_at_ok jeqAt4 jeq_r0_zero3
  exact StepReductionChain.append
    (StepReductionChain.append (StepReductionChain.append
      (StepReductionChain.single hmov)
      (StepReductionChain.single hjeq))
      (StepReductionChain.single hmov0))
    (StepReductionChain.single hexit)

theorem jump_taken_executionSegment :
    ExecutionSegment jumpSmokeProgram 5 jumpSmokeTakenPost jumpSmokeInitialState jumpSmokeFinalState :=
  executionSegment_of_reductionChain jump_taken_reductionChain rfl

theorem jeq_taken_executionSegment :
    ExecutionSegment jeqSmokeProgram 4 jeqSmokeTakenPost jeqSmokeInitialState jeqSmokeFinalState :=
  executionSegment_of_reductionChain jeq_taken_reductionChain rfl

def jumpSmokeTakenReductionChainProvider :
    ReductionChainProvider jumpSmokeProgram jumpSmokeTakenPre 5 jumpSmokeTakenPost where
  chain := by
    intro state hpre
    subst hpre
    exact ⟨jumpSmokeFinalState, jump_taken_reductionChain, rfl⟩

def jeqSmokeTakenReductionChainProvider :
    ReductionChainProvider jeqSmokeProgram jeqSmokeTakenPre 4 jeqSmokeTakenPost where
  chain := by
    intro state hpre
    subst hpre
    exact ⟨jeqSmokeFinalState, jeq_taken_reductionChain, rfl⟩

theorem jumpSmokeTakenPost_halted {s f : State} (hpost : jumpSmokeTakenPost s f) : f.halted :=
  hpost ▸ jumpFinal_halted

theorem jeqSmokeTakenPost_halted {s f : State} (hpost : jeqSmokeTakenPost s f) : f.halted :=
  hpost ▸ jeqFinal_halted

theorem smoke_jump_jne_taken_runSteps :
    runSteps jumpSmokeProgram 5 jumpSmokeInitialState = .ok jumpSmokeFinalState :=
  runSteps_of_executionSegment jump_taken_executionSegment jumpFinal_halted

theorem smoke_jump_jeq_taken_runSteps :
    runSteps jeqSmokeProgram 4 jeqSmokeInitialState = .ok jeqSmokeFinalState :=
  runSteps_of_executionSegment jeq_taken_executionSegment jeqFinal_halted

theorem smoke_jump_jne_taken_runSteps_via_provider :
    ∃ finalState,
      runSteps jumpSmokeProgram 5 jumpSmokeInitialState = .ok finalState ∧
      jumpSmokeTakenPost jumpSmokeInitialState finalState :=
  runSteps_post_of_reductionChainProvider
    jumpSmokeTakenReductionChainProvider rfl jumpSmokeTakenPost_halted

theorem smoke_jump_jeq_taken_runSteps_via_provider :
    ∃ finalState,
      runSteps jeqSmokeProgram 4 jeqSmokeInitialState = .ok finalState ∧
      jeqSmokeTakenPost jeqSmokeInitialState finalState :=
  runSteps_post_of_reductionChainProvider
    jeqSmokeTakenReductionChainProvider rfl jeqSmokeTakenPost_halted

end ProofForge.Backend.Solana.SbpfExecSmoke