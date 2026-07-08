import ProofForge.Backend.Solana.SbpfExec

/-!
Non-Counter reuse smoke for `SbpfExec`.

Models a tiny scalar read path (`mov64 ptr; ldxdw; call sol_set_return_data; exit`)
and proves it by composing generic `ReadyOpcodeAt` reductions and a
`ReductionChainProvider`, mirroring `EvmRefinement/PowdrExecSmoke.lean`.
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

end ProofForge.Backend.Solana.SbpfExecSmoke