import ProofForge.Backend.Solana.SbpfExec

/-!
Counter core-tail compositions over generic `SbpfExec` step lemmas.

These model the semantic tails of `sol_initialize`, `sol_increment`, and `sol_get`
from `Examples/Solana/Counter.golden.s` (account-validation prologue omitted).
-/

namespace ProofForge.Backend.Solana.CounterSbpfExec

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Syscalls
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.SbpfExec

abbrev Program := SbpfProgram
abbrev State := SbpfState

/-- Account-data offset for the Counter `count` scalar (`COUNT_DATA` in golden asm). -/
def countOff : Nat := 96

/-! ### initialize core: `mov64 r2,0; stxdw [r1+96],r2; mov64 r0,0; exit` -/

def initializeProgram : Program := {
  instructions := #[
    inst .mov64 (some .r2) none none (some (.num 0)),
    inst .stxdw (some .r1) (some .r2) (some (.num countOff)) none,
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def initializeInitialState : State :=
  { regs := regSet emptyRegs .r1 inputBase
    pc := 0 }

def initializeState1 : State := execMov64 initializeInitialState .r2 0

def initializeState2 : State := execStore initializeState1 countOff 0

def initializeState3 : State := execMov64 initializeState2 .r0 0

def initializeFinalState : State := execExit initializeState3 0

theorem initialize_not_halted0 : ¬ initializeInitialState.halted := by intro h; cases h
theorem initialize_not_halted1 : ¬ initializeState1.halted := by intro h; cases h
theorem initialize_not_halted2 : ¬ initializeState2.halted := by intro h; cases h
theorem initialize_not_halted3 : ¬ initializeState3.halted := by intro h; cases h
theorem initializeFinal_halted : initializeFinalState.halted := rfl

def initializeReady0 : StepReady initializeProgram initializeInitialState :=
  ⟨initialize_not_halted0, ⟨initializeProgram.instructions[0], rfl⟩⟩
def initializeReady1 : StepReady initializeProgram initializeState1 :=
  ⟨initialize_not_halted1, ⟨initializeProgram.instructions[1], rfl⟩⟩
def initializeReady2 : StepReady initializeProgram initializeState2 :=
  ⟨initialize_not_halted2, ⟨initializeProgram.instructions[2], rfl⟩⟩
def initializeReady3 : StepReady initializeProgram initializeState3 :=
  ⟨initialize_not_halted3, ⟨initializeProgram.instructions[3], rfl⟩⟩

theorem initialize_r1_base1 : regGet initializeState1.regs .r1 = inputBase := by
  unfold initializeState1 initializeInitialState execMov64 setReg nextPc regGet inputBase
  rfl

theorem initialize_r2_zero1 : regGet initializeState1.regs .r2 = 0 := by
  unfold initializeState1 initializeInitialState execMov64 setReg nextPc regGet
  rfl

theorem initialize_addr_count1 : memoryAddress initializeState1 .r1 countOff = countOff := by
  simp [memoryAddress, initialize_r1_base1, countOff, inputBase]
  decide

theorem initialize_step_mov_zero :
    step initializeProgram initializeInitialState = .ok initializeState1 :=
  step_mov64_imm_ok initializeReady0 (by rfl)

theorem initialize_step_store_zero :
    step initializeProgram initializeState1 = .ok initializeState2 :=
  step_stxdw_ok initializeReady1 (by rfl) initialize_addr_count1 initialize_r2_zero1

theorem initialize_r0_zero3 : regGet initializeState3.regs .r0 = 0 := by
  unfold initializeState3 initializeState2 initializeState1 initializeInitialState
    execMov64 execStore setReg nextPc regGet
  rfl

theorem initialize_step_mov_r0 :
    step initializeProgram initializeState2 = .ok initializeState3 :=
  step_mov64_imm_ok initializeReady2 (by rfl)

theorem initialize_step_exit :
    step initializeProgram initializeState3 = .ok initializeFinalState :=
  step_exit_ok initializeReady3 (by rfl) initialize_r0_zero3

theorem initialize_runSteps :
    runSteps initializeProgram 4 initializeInitialState = .ok initializeFinalState := by
  apply runSteps_of_stepPath_done
  exact StepPath.cons initializeReady0 initialize_step_mov_zero
    (StepPath.cons initializeReady1 initialize_step_store_zero
      (StepPath.cons initializeReady2 initialize_step_mov_r0
        (StepPath.cons initializeReady3 initialize_step_exit
          (StepPath.nil initializeFinalState initializeFinal_halted))))

theorem initialize_state2_count_zero :
    initializeState2.memory.read countOff = 0 := by
  unfold initializeState2 initializeState1 initializeInitialState execStore execMov64 setReg nextPc
    countOff inputBase
  unfold Memory.read Memory.write
  simp

theorem initialize_count_zero :
    initializeFinalState.memory.read countOff = 0 := by
  unfold initializeFinalState initializeState3 initializeState2 execExit execMov64
  exact initialize_state2_count_zero

/-! ### increment core: `ldxdw; mov64 1; add64; stxdw; mov64 r0,0; exit` -/

def incrementProgram : Program := {
  instructions := #[
    inst .ldxdw (some .r2) (some .r1) (some (.num countOff)) none,
    inst .mov64 (some .r3) none none (some (.num 1)),
    inst .add64 (some .r2) (some .r3) none none,
    inst .stxdw (some .r1) (some .r2) (some (.num countOff)) none,
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def incrementInitialState (n : Nat) : State :=
  { regs := regSet emptyRegs .r1 inputBase
    memory := #[(countOff, n)]
    pc := 0 }

def incrementState1 (n : Nat) : State :=
  execLoad (incrementInitialState n) .r2 countOff n

def incrementState2 (n : Nat) : State :=
  execMov64 (incrementState1 n) .r3 1

def incrementState3 (n : Nat) : State :=
  nextPc (setReg (incrementState2 n) .r2 (n + 1))

def incrementState4 (n : Nat) : State :=
  execStore (incrementState3 n) countOff (n + 1)

def incrementState5 (n : Nat) : State :=
  execMov64 (incrementState4 n) .r0 0

def incrementFinalState (n : Nat) : State :=
  execExit (incrementState5 n) 0

theorem increment_not_halted0 (n : Nat) : ¬ (incrementInitialState n).halted := by
  intro h; cases h
theorem increment_not_halted1 (n : Nat) : ¬ (incrementState1 n).halted := by
  intro h; cases h
theorem increment_not_halted2 (n : Nat) : ¬ (incrementState2 n).halted := by
  intro h; cases h
theorem increment_not_halted3 (n : Nat) : ¬ (incrementState3 n).halted := by
  intro h; cases h
theorem increment_not_halted4 (n : Nat) : ¬ (incrementState4 n).halted := by
  intro h; cases h
theorem increment_not_halted5 (n : Nat) : ¬ (incrementState5 n).halted := by
  intro h; cases h
theorem incrementFinal_halted (n : Nat) : (incrementFinalState n).halted := rfl

def incrementReady0 (n : Nat) : StepReady incrementProgram (incrementInitialState n) :=
  ⟨increment_not_halted0 n, ⟨incrementProgram.instructions[0], rfl⟩⟩
def incrementReady1 (n : Nat) : StepReady incrementProgram (incrementState1 n) :=
  ⟨increment_not_halted1 n, ⟨incrementProgram.instructions[1], rfl⟩⟩
def incrementReady2 (n : Nat) : StepReady incrementProgram (incrementState2 n) :=
  ⟨increment_not_halted2 n, ⟨incrementProgram.instructions[2], rfl⟩⟩
def incrementReady3 (n : Nat) : StepReady incrementProgram (incrementState3 n) :=
  ⟨increment_not_halted3 n, ⟨incrementProgram.instructions[3], rfl⟩⟩
def incrementReady4 (n : Nat) : StepReady incrementProgram (incrementState4 n) :=
  ⟨increment_not_halted4 n, ⟨incrementProgram.instructions[4], rfl⟩⟩
def incrementReady5 (n : Nat) : StepReady incrementProgram (incrementState5 n) :=
  ⟨increment_not_halted5 n, ⟨incrementProgram.instructions[5], rfl⟩⟩

theorem increment_r1_base1 (n : Nat) : regGet (incrementState1 n).regs .r1 = inputBase := by
  unfold incrementState1 incrementInitialState execLoad setReg nextPc regGet inputBase
  rfl

theorem increment_read_count0 (n : Nat) :
    (incrementInitialState n).memory.read countOff = n := by
  unfold incrementInitialState countOff
  simp [Memory.read]

theorem increment_addr_count1 (n : Nat) :
    memoryAddress (incrementState1 n) .r1 countOff = countOff := by
  simp [memoryAddress, increment_r1_base1, countOff, inputBase]
  decide

theorem increment_step_ldx (n : Nat) :
    step incrementProgram (incrementInitialState n) = .ok (incrementState1 n) :=
  step_ldxdw_ok (incrementReady0 n) (by rfl) (increment_addr_count1 n) (increment_read_count0 n)

theorem increment_r2_count2 (n : Nat) : regGet (incrementState2 n).regs .r2 = n := by
  unfold incrementState2 incrementState1 incrementInitialState execMov64 execLoad setReg nextPc regGet
  rfl

theorem increment_r3_one2 (n : Nat) : regGet (incrementState2 n).regs .r3 = 1 := by
  unfold incrementState2 incrementState1 incrementInitialState execMov64 execLoad setReg nextPc regGet
  rfl

theorem increment_step_mov_one (n : Nat) :
    step incrementProgram (incrementState1 n) = .ok (incrementState2 n) :=
  step_mov64_imm_ok (incrementReady1 n) (by rfl)

theorem increment_step_add (n : Nat) :
    step incrementProgram (incrementState2 n) = .ok (incrementState3 n) :=
  step_add64_reg_ok (incrementReady2 n) (by rfl) (increment_r2_count2 n) (increment_r3_one2 n)

theorem increment_r1_base3 (n : Nat) : regGet (incrementState3 n).regs .r1 = inputBase := by
  unfold incrementState3 incrementState2 incrementState1 incrementInitialState
    execMov64 execLoad setReg nextPc regGet inputBase
  rfl

theorem increment_r2_succ3 (n : Nat) : regGet (incrementState3 n).regs .r2 = n + 1 := by
  unfold incrementState3 incrementState2 incrementState1 incrementInitialState
    execMov64 execLoad setReg nextPc regGet
  rfl

theorem increment_addr_count3 (n : Nat) :
    memoryAddress (incrementState3 n) .r1 countOff = countOff := by
  simp [memoryAddress, increment_r1_base3 n, countOff, inputBase]
  decide

theorem increment_step_store (n : Nat) :
    step incrementProgram (incrementState3 n) = .ok (incrementState4 n) :=
  step_stxdw_ok (incrementReady3 n) (by rfl) (increment_addr_count3 n) (increment_r2_succ3 n)

theorem increment_r0_zero5 (n : Nat) : regGet (incrementState5 n).regs .r0 = 0 := by
  unfold incrementState5 incrementState4 incrementState3 incrementState2 incrementState1
    incrementInitialState execMov64 execStore setReg nextPc regGet
  rfl

theorem increment_step_mov_r0 (n : Nat) :
    step incrementProgram (incrementState4 n) = .ok (incrementState5 n) :=
  step_mov64_imm_ok (incrementReady4 n) (by rfl)

theorem increment_step_exit (n : Nat) :
    step incrementProgram (incrementState5 n) = .ok (incrementFinalState n) :=
  step_exit_ok (incrementReady5 n) (by rfl) (increment_r0_zero5 n)

theorem increment_runSteps (n : Nat) :
    runSteps incrementProgram 6 (incrementInitialState n) = .ok (incrementFinalState n) := by
  apply runSteps_of_stepPath_done
  exact StepPath.cons (incrementReady0 n) (increment_step_ldx n)
    (StepPath.cons (incrementReady1 n) (increment_step_mov_one n)
      (StepPath.cons (incrementReady2 n) (increment_step_add n)
        (StepPath.cons (incrementReady3 n) (increment_step_store n)
          (StepPath.cons (incrementReady4 n) (increment_step_mov_r0 n)
            (StepPath.cons (incrementReady5 n) (increment_step_exit n)
              (StepPath.nil _ (incrementFinal_halted n)))))))

theorem increment_state4_count_succ (n : Nat) :
    (incrementState4 n).memory.read countOff = n + 1 := by
  unfold incrementState4 incrementState3 incrementState2 incrementState1 incrementInitialState
    execStore execMov64 execLoad setReg nextPc countOff inputBase
  unfold Memory.read Memory.write
  simp

theorem increment_count_succ (n : Nat) :
    (incrementFinalState n).memory.read countOff = n + 1 := by
  unfold incrementFinalState incrementState5 incrementState4 execExit execMov64
  exact increment_state4_count_succ n

/-! ### get core: `ldxdw; mov64 r1,countOff; set_return_data; mov64 r0,0; exit` -/

def getProgram : Program := {
  instructions := #[
    inst .ldxdw (some .r2) (some .r1) (some (.num countOff)) none,
    inst .mov64 (some .r1) none none (some (.num countOff)),
    inst .call none none none (some (.sym sol_set_return_data)),
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def getInitialState (n : Nat) : State :=
  { regs := regSet emptyRegs .r1 inputBase
    memory := #[(countOff, n)]
    pc := 0 }

def getState1 (n : Nat) : State :=
  execLoad (getInitialState n) .r2 countOff n

def getState2 (n : Nat) : State :=
  execMov64 (getState1 n) .r1 countOff

def getState3 (n : Nat) : State :=
  execSetReturnData (getState2 n) n

def getState4 (n : Nat) : State :=
  execMov64 (getState3 n) .r0 0

def getFinalState (n : Nat) : State :=
  execExit (getState4 n) 0

theorem get_not_halted0 (n : Nat) : ¬ (getInitialState n).halted := by intro h; cases h
theorem get_not_halted1 (n : Nat) : ¬ (getState1 n).halted := by intro h; cases h
theorem get_not_halted2 (n : Nat) : ¬ (getState2 n).halted := by intro h; cases h
theorem get_not_halted3 (n : Nat) : ¬ (getState3 n).halted := by intro h; cases h
theorem get_not_halted4 (n : Nat) : ¬ (getState4 n).halted := by intro h; cases h
theorem getFinal_halted (n : Nat) : (getFinalState n).halted := rfl

def getReady0 (n : Nat) : StepReady getProgram (getInitialState n) :=
  ⟨get_not_halted0 n, ⟨getProgram.instructions[0], rfl⟩⟩
def getReady1 (n : Nat) : StepReady getProgram (getState1 n) :=
  ⟨get_not_halted1 n, ⟨getProgram.instructions[1], rfl⟩⟩
def getReady2 (n : Nat) : StepReady getProgram (getState2 n) :=
  ⟨get_not_halted2 n, ⟨getProgram.instructions[2], rfl⟩⟩
def getReady3 (n : Nat) : StepReady getProgram (getState3 n) :=
  ⟨get_not_halted3 n, ⟨getProgram.instructions[3], rfl⟩⟩
def getReady4 (n : Nat) : StepReady getProgram (getState4 n) :=
  ⟨get_not_halted4 n, ⟨getProgram.instructions[4], rfl⟩⟩

theorem get_r1_base1 (n : Nat) : regGet (getState1 n).regs .r1 = inputBase := by
  unfold getState1 getInitialState execLoad setReg nextPc regGet inputBase
  rfl

theorem get_read_count0 (n : Nat) : (getInitialState n).memory.read countOff = n := by
  unfold getInitialState countOff
  simp [Memory.read]

theorem get_addr_count1 (n : Nat) : memoryAddress (getState1 n) .r1 countOff = countOff := by
  simp [memoryAddress, get_r1_base1 n, countOff, inputBase]
  decide

theorem get_step_ldx (n : Nat) :
    step getProgram (getInitialState n) = .ok (getState1 n) :=
  step_ldxdw_ok (getReady0 n) (by rfl) (get_addr_count1 n) (get_read_count0 n)

theorem get_r1_count2 (n : Nat) : regGet (getState2 n).regs .r1 = countOff := by
  unfold getState2 getState1 getInitialState execMov64 execLoad setReg nextPc regGet countOff
  rfl

theorem get_read_count2 (n : Nat) : (getState2 n).memory.read countOff = n := by
  unfold getState2 getState1 getInitialState execMov64 execLoad setReg nextPc countOff
  simp [Memory.read]

theorem get_step_mov_ptr (n : Nat) :
    step getProgram (getState1 n) = .ok (getState2 n) :=
  step_mov64_imm_ok (getReady1 n) (by rfl)

theorem get_step_set_return_data (n : Nat) :
    step getProgram (getState2 n) = .ok (getState3 n) :=
  step_syscall_set_return_data_ok (getReady2 n) (by rfl) (get_r1_count2 n) (get_read_count2 n)

theorem get_r0_zero4 (n : Nat) : regGet (getState4 n).regs .r0 = 0 := by
  unfold getState4 getState3 getState2 getState1 getInitialState
    execMov64 execSetReturnData setReg nextPc regGet
  rfl

theorem get_step_mov_r0 (n : Nat) :
    step getProgram (getState3 n) = .ok (getState4 n) :=
  step_mov64_imm_ok (getReady3 n) (by rfl)

theorem get_step_exit (n : Nat) :
    step getProgram (getState4 n) = .ok (getFinalState n) :=
  step_exit_ok (getReady4 n) (by rfl) (get_r0_zero4 n)

theorem get_runSteps (n : Nat) :
    runSteps getProgram 5 (getInitialState n) = .ok (getFinalState n) := by
  apply runSteps_of_stepPath_done
  exact StepPath.cons (getReady0 n) (get_step_ldx n)
    (StepPath.cons (getReady1 n) (get_step_mov_ptr n)
      (StepPath.cons (getReady2 n) (get_step_set_return_data n)
        (StepPath.cons (getReady3 n) (get_step_mov_r0 n)
          (StepPath.cons (getReady4 n) (get_step_exit n)
            (StepPath.nil _ (getFinal_halted n))))))

theorem get_return_data (n : Nat) : (getFinalState n).returnData = some n := by
  unfold getFinalState getState4 getState3 getState2 getState1 getInitialState
    execExit execMov64 execSetReturnData setReg nextPc
  rfl

/-! ### Layout anchor: `countOff` matches emitted Counter state layout -/

theorem countOff_matches_layout :
    stateFieldOffset? ProofForge.IR.Examples.Counter.module "count" = some countOff := by
  native_decide

end ProofForge.Backend.Solana.CounterSbpfExec