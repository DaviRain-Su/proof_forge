import ProofForge.Backend.Solana.SbpfExec
import ProofForge.IR.Examples.ValueVault

/-!
ValueVault reuse slice over generic `SbpfExec` step lemmas.

This is the SOL-4(a) genericity surface: unlike Counter, the deposit storage
core touches multiple scalar slots and combines stack locals, account data,
arithmetic, and stores. Keep this file as a short composition over `SbpfExec`;
new per-instruction facts belong in `SbpfExec.lean`.
-/

namespace ProofForge.Backend.Solana.ValueVaultSbpfExec

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.SbpfExec
open ProofForge.Backend.Solana.Syscalls

abbrev Program := SbpfProgram
abbrev State := SbpfState

def balanceOff : Nat := 96
def releasedOff : Nat := 104
def feesOff : Nat := 112
def lastValueOff : Nat := 120
def lastCheckpointOff : Nat := 128
def operationsOff : Nat := 136

def depositAmountScratch : Nat := stackBase - 8
def depositCurrentScratch : Nat := stackBase - 16
def depositNextScratch : Nat := stackBase - 24
def depositLhsScratch : Nat := stackBase - 32
def depositNextOpsScratch : Nat := stackBase - 40
def depositOpsScratch : Nat := stackBase - 48

def getNetBalanceScratch : Nat := stackBase - 8
def getNetFeesScratch : Nat := stackBase - 16
def getNetLhsScratch : Nat := stackBase - 24
def getNetReturnScratch : Nat := stackBase - 8

/-! ### deposit storage core

This models the storage-update tail after account validation and parameter
decoding:

`balance := balance + amount; last_value := amount; operations := operations + 1`.
-/

def depositStorageProgram : Program := {
  instructions := #[
    inst .ldxdw (some .r2) (some .r1) (some (.num balanceOff)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 16)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 16)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 32)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 8)) none,
    inst .ldxdw (some .r3) (some .r10) (some (.num 32)) none,
    inst .add64 (some .r2) (some .r3) none none,
    inst .stxdw (some .r10) (some .r2) (some (.num 24)) none,
    inst .ldxdw (some .r2) (some .r1) (some (.num operationsOff)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 32)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 32)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 48)) none,
    inst .mov64 (some .r2) none none (some (.num 1)),
    inst .ldxdw (some .r3) (some .r10) (some (.num 48)) none,
    inst .add64 (some .r2) (some .r3) none none,
    inst .stxdw (some .r10) (some .r2) (some (.num 40)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 24)) none,
    inst .stxdw (some .r1) (some .r2) (some (.num balanceOff)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 8)) none,
    inst .stxdw (some .r1) (some .r2) (some (.num lastValueOff)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 40)) none,
    inst .stxdw (some .r1) (some .r2) (some (.num operationsOff)) none,
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def depositStorageInitialState (balance amount operations : Nat) : State :=
  { regs := regSet (regSet emptyRegs .r1 inputBase) .r10 stackBase
    memory := #[
      (balanceOff, balance),
      (operationsOff, operations),
      (depositAmountScratch, amount)
    ]
    pc := 0 }

def depositState1 (balance amount operations : Nat) : State :=
  execLoad (depositStorageInitialState balance amount operations) .r2 balanceOff balance

def depositState2 (balance amount operations : Nat) : State :=
  execStore (depositState1 balance amount operations) depositCurrentScratch balance

def depositState3 (balance amount operations : Nat) : State :=
  execLoad (depositState2 balance amount operations) .r2 depositCurrentScratch balance

def depositState4 (balance amount operations : Nat) : State :=
  execStore (depositState3 balance amount operations) depositLhsScratch balance

def depositState5 (balance amount operations : Nat) : State :=
  execLoad (depositState4 balance amount operations) .r2 depositAmountScratch amount

def depositState6 (balance amount operations : Nat) : State :=
  execLoad (depositState5 balance amount operations) .r3 depositLhsScratch balance

def depositState7 (balance amount operations : Nat) : State :=
  nextPc (setReg (depositState6 balance amount operations) .r2 (amount + balance))

def depositState8 (balance amount operations : Nat) : State :=
  execStore (depositState7 balance amount operations) depositNextScratch (amount + balance)

def depositState9 (balance amount operations : Nat) : State :=
  execLoad (depositState8 balance amount operations) .r2 operationsOff operations

def depositState10 (balance amount operations : Nat) : State :=
  execStore (depositState9 balance amount operations) depositLhsScratch operations

def depositState11 (balance amount operations : Nat) : State :=
  execLoad (depositState10 balance amount operations) .r2 depositLhsScratch operations

def depositState12 (balance amount operations : Nat) : State :=
  execStore (depositState11 balance amount operations) depositOpsScratch operations

def depositState13 (balance amount operations : Nat) : State :=
  execMov64 (depositState12 balance amount operations) .r2 1

def depositState14 (balance amount operations : Nat) : State :=
  execLoad (depositState13 balance amount operations) .r3 depositOpsScratch operations

def depositState15 (balance amount operations : Nat) : State :=
  nextPc (setReg (depositState14 balance amount operations) .r2 (1 + operations))

def depositState16 (balance amount operations : Nat) : State :=
  execStore (depositState15 balance amount operations) depositNextOpsScratch (1 + operations)

def depositState17 (balance amount operations : Nat) : State :=
  execLoad (depositState16 balance amount operations) .r2 depositNextScratch (amount + balance)

def depositState18 (balance amount operations : Nat) : State :=
  execStore (depositState17 balance amount operations) balanceOff (amount + balance)

def depositState19 (balance amount operations : Nat) : State :=
  execLoad (depositState18 balance amount operations) .r2 depositAmountScratch amount

def depositState20 (balance amount operations : Nat) : State :=
  execStore (depositState19 balance amount operations) lastValueOff amount

def depositState21 (balance amount operations : Nat) : State :=
  execLoad (depositState20 balance amount operations) .r2 depositNextOpsScratch (1 + operations)

def depositState22 (balance amount operations : Nat) : State :=
  execStore (depositState21 balance amount operations) operationsOff (1 + operations)

def depositState23 (balance amount operations : Nat) : State :=
  execMov64 (depositState22 balance amount operations) .r0 0

def depositFinalState (balance amount operations : Nat) : State :=
  execExit (depositState23 balance amount operations) 0

theorem deposit_not_halted0 (b a o : Nat) :
    ¬ (depositStorageInitialState b a o).halted := by intro h; cases h
theorem deposit_not_halted1 (b a o : Nat) : ¬ (depositState1 b a o).halted := by intro h; cases h
theorem deposit_not_halted2 (b a o : Nat) : ¬ (depositState2 b a o).halted := by intro h; cases h
theorem deposit_not_halted3 (b a o : Nat) : ¬ (depositState3 b a o).halted := by intro h; cases h
theorem deposit_not_halted4 (b a o : Nat) : ¬ (depositState4 b a o).halted := by intro h; cases h
theorem deposit_not_halted5 (b a o : Nat) : ¬ (depositState5 b a o).halted := by intro h; cases h
theorem deposit_not_halted6 (b a o : Nat) : ¬ (depositState6 b a o).halted := by intro h; cases h
theorem deposit_not_halted7 (b a o : Nat) : ¬ (depositState7 b a o).halted := by intro h; cases h
theorem deposit_not_halted8 (b a o : Nat) : ¬ (depositState8 b a o).halted := by intro h; cases h
theorem deposit_not_halted9 (b a o : Nat) : ¬ (depositState9 b a o).halted := by intro h; cases h
theorem deposit_not_halted10 (b a o : Nat) : ¬ (depositState10 b a o).halted := by intro h; cases h
theorem deposit_not_halted11 (b a o : Nat) : ¬ (depositState11 b a o).halted := by intro h; cases h
theorem deposit_not_halted12 (b a o : Nat) : ¬ (depositState12 b a o).halted := by intro h; cases h
theorem deposit_not_halted13 (b a o : Nat) : ¬ (depositState13 b a o).halted := by intro h; cases h
theorem deposit_not_halted14 (b a o : Nat) : ¬ (depositState14 b a o).halted := by intro h; cases h
theorem deposit_not_halted15 (b a o : Nat) : ¬ (depositState15 b a o).halted := by intro h; cases h
theorem deposit_not_halted16 (b a o : Nat) : ¬ (depositState16 b a o).halted := by intro h; cases h
theorem deposit_not_halted17 (b a o : Nat) : ¬ (depositState17 b a o).halted := by intro h; cases h
theorem deposit_not_halted18 (b a o : Nat) : ¬ (depositState18 b a o).halted := by intro h; cases h
theorem deposit_not_halted19 (b a o : Nat) : ¬ (depositState19 b a o).halted := by intro h; cases h
theorem deposit_not_halted20 (b a o : Nat) : ¬ (depositState20 b a o).halted := by intro h; cases h
theorem deposit_not_halted21 (b a o : Nat) : ¬ (depositState21 b a o).halted := by intro h; cases h
theorem deposit_not_halted22 (b a o : Nat) : ¬ (depositState22 b a o).halted := by intro h; cases h
theorem deposit_not_halted23 (b a o : Nat) : ¬ (depositState23 b a o).halted := by intro h; cases h
theorem depositFinal_halted (b a o : Nat) : (depositFinalState b a o).halted := rfl

def depositReady0 (b a o : Nat) : StepReady depositStorageProgram (depositStorageInitialState b a o) :=
  ⟨deposit_not_halted0 b a o, ⟨depositStorageProgram.instructions[0], rfl⟩⟩
def depositReady1 (b a o : Nat) : StepReady depositStorageProgram (depositState1 b a o) :=
  ⟨deposit_not_halted1 b a o, ⟨depositStorageProgram.instructions[1], rfl⟩⟩
def depositReady2 (b a o : Nat) : StepReady depositStorageProgram (depositState2 b a o) :=
  ⟨deposit_not_halted2 b a o, ⟨depositStorageProgram.instructions[2], rfl⟩⟩
def depositReady3 (b a o : Nat) : StepReady depositStorageProgram (depositState3 b a o) :=
  ⟨deposit_not_halted3 b a o, ⟨depositStorageProgram.instructions[3], rfl⟩⟩
def depositReady4 (b a o : Nat) : StepReady depositStorageProgram (depositState4 b a o) :=
  ⟨deposit_not_halted4 b a o, ⟨depositStorageProgram.instructions[4], rfl⟩⟩
def depositReady5 (b a o : Nat) : StepReady depositStorageProgram (depositState5 b a o) :=
  ⟨deposit_not_halted5 b a o, ⟨depositStorageProgram.instructions[5], rfl⟩⟩
def depositReady6 (b a o : Nat) : StepReady depositStorageProgram (depositState6 b a o) :=
  ⟨deposit_not_halted6 b a o, ⟨depositStorageProgram.instructions[6], rfl⟩⟩
def depositReady7 (b a o : Nat) : StepReady depositStorageProgram (depositState7 b a o) :=
  ⟨deposit_not_halted7 b a o, ⟨depositStorageProgram.instructions[7], rfl⟩⟩
def depositReady8 (b a o : Nat) : StepReady depositStorageProgram (depositState8 b a o) :=
  ⟨deposit_not_halted8 b a o, ⟨depositStorageProgram.instructions[8], rfl⟩⟩
def depositReady9 (b a o : Nat) : StepReady depositStorageProgram (depositState9 b a o) :=
  ⟨deposit_not_halted9 b a o, ⟨depositStorageProgram.instructions[9], rfl⟩⟩
def depositReady10 (b a o : Nat) : StepReady depositStorageProgram (depositState10 b a o) :=
  ⟨deposit_not_halted10 b a o, ⟨depositStorageProgram.instructions[10], rfl⟩⟩
def depositReady11 (b a o : Nat) : StepReady depositStorageProgram (depositState11 b a o) :=
  ⟨deposit_not_halted11 b a o, ⟨depositStorageProgram.instructions[11], rfl⟩⟩
def depositReady12 (b a o : Nat) : StepReady depositStorageProgram (depositState12 b a o) :=
  ⟨deposit_not_halted12 b a o, ⟨depositStorageProgram.instructions[12], rfl⟩⟩
def depositReady13 (b a o : Nat) : StepReady depositStorageProgram (depositState13 b a o) :=
  ⟨deposit_not_halted13 b a o, ⟨depositStorageProgram.instructions[13], rfl⟩⟩
def depositReady14 (b a o : Nat) : StepReady depositStorageProgram (depositState14 b a o) :=
  ⟨deposit_not_halted14 b a o, ⟨depositStorageProgram.instructions[14], rfl⟩⟩
def depositReady15 (b a o : Nat) : StepReady depositStorageProgram (depositState15 b a o) :=
  ⟨deposit_not_halted15 b a o, ⟨depositStorageProgram.instructions[15], rfl⟩⟩
def depositReady16 (b a o : Nat) : StepReady depositStorageProgram (depositState16 b a o) :=
  ⟨deposit_not_halted16 b a o, ⟨depositStorageProgram.instructions[16], rfl⟩⟩
def depositReady17 (b a o : Nat) : StepReady depositStorageProgram (depositState17 b a o) :=
  ⟨deposit_not_halted17 b a o, ⟨depositStorageProgram.instructions[17], rfl⟩⟩
def depositReady18 (b a o : Nat) : StepReady depositStorageProgram (depositState18 b a o) :=
  ⟨deposit_not_halted18 b a o, ⟨depositStorageProgram.instructions[18], rfl⟩⟩
def depositReady19 (b a o : Nat) : StepReady depositStorageProgram (depositState19 b a o) :=
  ⟨deposit_not_halted19 b a o, ⟨depositStorageProgram.instructions[19], rfl⟩⟩
def depositReady20 (b a o : Nat) : StepReady depositStorageProgram (depositState20 b a o) :=
  ⟨deposit_not_halted20 b a o, ⟨depositStorageProgram.instructions[20], rfl⟩⟩
def depositReady21 (b a o : Nat) : StepReady depositStorageProgram (depositState21 b a o) :=
  ⟨deposit_not_halted21 b a o, ⟨depositStorageProgram.instructions[21], rfl⟩⟩
def depositReady22 (b a o : Nat) : StepReady depositStorageProgram (depositState22 b a o) :=
  ⟨deposit_not_halted22 b a o, ⟨depositStorageProgram.instructions[22], rfl⟩⟩
def depositReady23 (b a o : Nat) : StepReady depositStorageProgram (depositState23 b a o) :=
  ⟨deposit_not_halted23 b a o, ⟨depositStorageProgram.instructions[23], rfl⟩⟩

theorem deposit_r1_base (s : State)
    (h : regGet s.regs .r1 = inputBase) :
    regGet (nextPc s).regs .r1 = inputBase := by
  simpa [nextPc] using h

theorem deposit_r10_stack (s : State)
    (h : regGet s.regs .r10 = stackBase) :
    regGet (nextPc s).regs .r10 = stackBase := by
  simpa [nextPc] using h

theorem deposit_initial_r1 (b a o : Nat) :
    regGet (depositStorageInitialState b a o).regs .r1 = inputBase := by
  unfold depositStorageInitialState regGet regSet emptyRegs inputBase registerCount
  rfl

theorem deposit_initial_r10 (b a o : Nat) :
    regGet (depositStorageInitialState b a o).regs .r10 = stackBase := by
  unfold depositStorageInitialState regGet regSet emptyRegs stackBase registerCount
  rfl

theorem deposit_initial_regs_size (b a o : Nat) :
    (depositStorageInitialState b a o).regs.size = registerCount := by
  unfold depositStorageInitialState emptyRegs registerCount
  simp [regSet_size]

theorem deposit_state1_regs_size (b a o : Nat) :
    (depositState1 b a o).regs.size = registerCount := by
  unfold depositState1
  rw [regs_size_execLoad]
  exact deposit_initial_regs_size b a o

theorem deposit_state2_regs_size (b a o : Nat) :
    (depositState2 b a o).regs.size = registerCount := by
  unfold depositState2
  rw [regs_size_execStore]
  exact deposit_state1_regs_size b a o

theorem deposit_state3_regs_size (b a o : Nat) :
    (depositState3 b a o).regs.size = registerCount := by
  unfold depositState3
  rw [regs_size_execLoad]
  exact deposit_state2_regs_size b a o

theorem deposit_state4_regs_size (b a o : Nat) :
    (depositState4 b a o).regs.size = registerCount := by
  unfold depositState4
  rw [regs_size_execStore]
  exact deposit_state3_regs_size b a o

theorem deposit_state5_regs_size (b a o : Nat) :
    (depositState5 b a o).regs.size = registerCount := by
  unfold depositState5
  rw [regs_size_execLoad]
  exact deposit_state4_regs_size b a o

theorem deposit_state6_regs_size (b a o : Nat) :
    (depositState6 b a o).regs.size = registerCount := by
  unfold depositState6
  rw [regs_size_execLoad]
  exact deposit_state5_regs_size b a o

theorem deposit_state7_regs_size (b a o : Nat) :
    (depositState7 b a o).regs.size = registerCount := by
  unfold depositState7
  simp [regs_size_nextPc, regs_size_setReg, deposit_state6_regs_size b a o]

theorem deposit_addr_r1_balance0 (b a o : Nat) :
    memoryAddress (depositStorageInitialState b a o) .r1 balanceOff = balanceOff := by
  simp [memoryAddress, deposit_initial_r1 b a o, balanceOff, inputBase]
  native_decide

theorem deposit_read_balance0 (b a o : Nat) :
    (depositStorageInitialState b a o).memory.read balanceOff = b := by
  unfold depositStorageInitialState balanceOff
  simp [Memory.read]

theorem deposit_step0 (b a o : Nat) :
    step depositStorageProgram (depositStorageInitialState b a o) =
      .ok (depositState1 b a o) :=
  step_ldxdw_ok (depositReady0 b a o) (by rfl)
    (deposit_addr_r1_balance0 b a o) (deposit_read_balance0 b a o)

theorem deposit_state1_r10 (b a o : Nat) :
    regGet (depositState1 b a o).regs .r10 = stackBase := by
  unfold depositState1 depositStorageInitialState execLoad setReg nextPc regGet regSet stackBase
  rfl

theorem deposit_state1_r2 (b a o : Nat) :
    regGet (depositState1 b a o).regs .r2 = b := by
  unfold depositState1 depositStorageInitialState execLoad setReg nextPc regGet regSet
  rfl

theorem deposit_state1_r1 (b a o : Nat) :
    regGet (depositState1 b a o).regs .r1 = inputBase := by
  unfold depositState1
  rw [regGet_execLoad_of_ne]
  exact deposit_initial_r1 b a o
  decide

theorem deposit_addr_r10_current1 (b a o : Nat) :
    memoryAddress (depositState1 b a o) .r10 16 = depositCurrentScratch := by
  simp [memoryAddress, deposit_state1_r10 b a o, depositCurrentScratch]
  native_decide

theorem deposit_step1 (b a o : Nat) :
    step depositStorageProgram (depositState1 b a o) =
      .ok (depositState2 b a o) :=
  step_stxdw_ok (depositReady1 b a o) (by rfl)
    (deposit_addr_r10_current1 b a o) (deposit_state1_r2 b a o)

theorem deposit_state2_r10 (b a o : Nat) :
    regGet (depositState2 b a o).regs .r10 = stackBase := by
  unfold depositState2 depositState1 depositStorageInitialState
    execStore execLoad setReg nextPc regGet regSet stackBase
  rfl

theorem deposit_state2_r1 (b a o : Nat) :
    regGet (depositState2 b a o).regs .r1 = inputBase := by
  unfold depositState2
  rw [regGet_execStore]
  exact deposit_state1_r1 b a o

theorem deposit_addr_r10_current2 (b a o : Nat) :
    memoryAddress (depositState2 b a o) .r10 16 = depositCurrentScratch := by
  simp [memoryAddress, deposit_state2_r10 b a o, depositCurrentScratch]
  native_decide

theorem deposit_read_current2 (b a o : Nat) :
    (depositState2 b a o).memory.read depositCurrentScratch = b := by
  unfold depositState2 execStore
  simp [nextPc, Memory.read_write]

theorem deposit_step2 (b a o : Nat) :
    step depositStorageProgram (depositState2 b a o) =
      .ok (depositState3 b a o) :=
  step_ldxdw_ok (depositReady2 b a o) (by rfl)
    (deposit_addr_r10_current2 b a o) (deposit_read_current2 b a o)

theorem deposit_state3_r10 (b a o : Nat) :
    regGet (depositState3 b a o).regs .r10 = stackBase := by
  unfold depositState3 depositState2 depositState1 depositStorageInitialState
    execLoad execStore setReg nextPc regGet regSet stackBase
  rfl

theorem deposit_state3_r2 (b a o : Nat) :
    regGet (depositState3 b a o).regs .r2 = b := by
  unfold depositState3 execLoad setReg nextPc regGet
  rfl

theorem deposit_state3_r1 (b a o : Nat) :
    regGet (depositState3 b a o).regs .r1 = inputBase := by
  unfold depositState3
  rw [regGet_execLoad_of_ne]
  exact deposit_state2_r1 b a o
  decide

theorem deposit_addr_r10_lhs3 (b a o : Nat) :
    memoryAddress (depositState3 b a o) .r10 32 = depositLhsScratch := by
  simp [memoryAddress, deposit_state3_r10 b a o, depositLhsScratch]
  native_decide

theorem deposit_step3 (b a o : Nat) :
    step depositStorageProgram (depositState3 b a o) =
      .ok (depositState4 b a o) :=
  step_stxdw_ok (depositReady3 b a o) (by rfl)
    (deposit_addr_r10_lhs3 b a o) (deposit_state3_r2 b a o)

theorem deposit_state4_r10 (b a o : Nat) :
    regGet (depositState4 b a o).regs .r10 = stackBase := by
  unfold depositState4 depositState3 depositState2 depositState1 depositStorageInitialState
    execStore execLoad setReg nextPc regGet regSet stackBase
  rfl

theorem deposit_state4_r1 (b a o : Nat) :
    regGet (depositState4 b a o).regs .r1 = inputBase := by
  unfold depositState4
  rw [regGet_execStore]
  exact deposit_state3_r1 b a o

theorem deposit_addr_r10_amount4 (b a o : Nat) :
    memoryAddress (depositState4 b a o) .r10 8 = depositAmountScratch := by
  simp [memoryAddress, deposit_state4_r10 b a o, depositAmountScratch]
  native_decide

theorem deposit_read_amount4 (b a o : Nat) :
    (depositState4 b a o).memory.read depositAmountScratch = a := by
  unfold depositState4 depositState3 depositState2 depositState1 depositStorageInitialState
    execStore execLoad setReg nextPc depositAmountScratch depositCurrentScratch depositLhsScratch
  simp [Memory.read, Memory.write, balanceOff, operationsOff, stackBase]

theorem deposit_step4 (b a o : Nat) :
    step depositStorageProgram (depositState4 b a o) =
      .ok (depositState5 b a o) :=
  step_ldxdw_ok (depositReady4 b a o) (by rfl)
    (deposit_addr_r10_amount4 b a o) (deposit_read_amount4 b a o)

theorem deposit_read_lhs4 (b a o : Nat) :
    (depositState4 b a o).memory.read depositLhsScratch = b := by
  unfold depositState4 execStore
  simp [nextPc, Memory.read_write]

theorem deposit_state5_r10 (b a o : Nat) :
    regGet (depositState5 b a o).regs .r10 = stackBase := by
  unfold depositState5 depositState4 depositState3 depositState2 depositState1
    depositStorageInitialState execLoad execStore setReg nextPc regGet regSet stackBase
  rfl

theorem deposit_state5_r1 (b a o : Nat) :
    regGet (depositState5 b a o).regs .r1 = inputBase := by
  unfold depositState5
  rw [regGet_execLoad_of_ne]
  exact deposit_state4_r1 b a o
  decide

theorem deposit_addr_r10_lhs5 (b a o : Nat) :
    memoryAddress (depositState5 b a o) .r10 32 = depositLhsScratch := by
  simp [memoryAddress, deposit_state5_r10 b a o, depositLhsScratch]
  native_decide

theorem deposit_read_lhs5 (b a o : Nat) :
    (depositState5 b a o).memory.read depositLhsScratch = b := by
  unfold depositState5 execLoad setReg nextPc
  simpa using deposit_read_lhs4 b a o

theorem deposit_step5 (b a o : Nat) :
    step depositStorageProgram (depositState5 b a o) =
      .ok (depositState6 b a o) :=
  step_ldxdw_ok (depositReady5 b a o) (by rfl)
    (deposit_addr_r10_lhs5 b a o) (deposit_read_lhs5 b a o)

theorem deposit_state6_r2 (b a o : Nat) :
    regGet (depositState6 b a o).regs .r2 = a := by
  unfold depositState6 depositState5 execLoad setReg nextPc regGet
  rfl

theorem deposit_state6_r3 (b a o : Nat) :
    regGet (depositState6 b a o).regs .r3 = b := by
  unfold depositState6 execLoad setReg nextPc regGet
  rfl

theorem deposit_state6_r1 (b a o : Nat) :
    regGet (depositState6 b a o).regs .r1 = inputBase := by
  unfold depositState6
  rw [regGet_execLoad_of_ne]
  exact deposit_state5_r1 b a o
  decide

theorem deposit_step6 (b a o : Nat) :
    step depositStorageProgram (depositState6 b a o) =
      .ok (depositState7 b a o) :=
  step_add64_reg_ok (depositReady6 b a o) (by rfl)
    (deposit_state6_r2 b a o) (deposit_state6_r3 b a o)

theorem deposit_state7_r10 (b a o : Nat) :
    regGet (depositState7 b a o).regs .r10 = stackBase := by
  unfold depositState7 depositState6 depositState5 depositState4 depositState3
    depositState2 depositState1 depositStorageInitialState execLoad execStore setReg
    nextPc regGet regSet stackBase
  rfl

theorem deposit_state7_r2 (b a o : Nat) :
    regGet (depositState7 b a o).regs .r2 = a + b := by
  unfold depositState7 setReg nextPc regGet
  rfl

theorem deposit_addr_r10_next7 (b a o : Nat) :
    memoryAddress (depositState7 b a o) .r10 24 = depositNextScratch := by
  simp [memoryAddress, deposit_state7_r10 b a o, depositNextScratch]
  native_decide

theorem deposit_step7 (b a o : Nat) :
    step depositStorageProgram (depositState7 b a o) =
      .ok (depositState8 b a o) :=
  step_stxdw_ok (depositReady7 b a o) (by rfl)
    (deposit_addr_r10_next7 b a o) (deposit_state7_r2 b a o)

theorem deposit_state8_next_balance_scratch (b a o : Nat) :
    (depositState8 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState8 execStore
  simp [nextPc, Memory.read_write]

theorem deposit_state7_r1 (b a o : Nat) :
    regGet (depositState7 b a o).regs .r1 = inputBase := by
  unfold depositState7
  rw [regGet_nextPc, regGet_setReg_of_ne]
  exact deposit_state6_r1 b a o
  decide

theorem deposit_state8_r1 (b a o : Nat) :
    regGet (depositState8 b a o).regs .r1 = inputBase := by
  unfold depositState8
  rw [regGet_execStore]
  exact deposit_state7_r1 b a o

theorem deposit_state8_r10 (b a o : Nat) :
    regGet (depositState8 b a o).regs .r10 = stackBase := by
  unfold depositState8
  rw [regGet_execStore]
  exact deposit_state7_r10 b a o

theorem deposit_state8_regs_size (b a o : Nat) :
    (depositState8 b a o).regs.size = registerCount := by
  unfold depositState8
  rw [regs_size_execStore]
  exact deposit_state7_regs_size b a o

theorem deposit_addr_r1_operations8 (b a o : Nat) :
    memoryAddress (depositState8 b a o) .r1 operationsOff = operationsOff := by
  simp [memoryAddress, deposit_state8_r1 b a o, operationsOff, inputBase]
  native_decide

theorem deposit_read_operations8 (b a o : Nat) :
    (depositState8 b a o).memory.read operationsOff = o := by
  unfold depositState8 depositState7 depositState6 depositState5 depositState4
    depositState3 depositState2 depositState1 depositStorageInitialState
    execStore execLoad setReg nextPc depositNextScratch depositAmountScratch
    depositCurrentScratch depositLhsScratch
  simp [Memory.read, Memory.write, balanceOff, operationsOff, stackBase]

theorem deposit_step8 (b a o : Nat) :
    step depositStorageProgram (depositState8 b a o) =
      .ok (depositState9 b a o) :=
  step_ldxdw_ok (depositReady8 b a o) (by rfl)
    (deposit_addr_r1_operations8 b a o) (deposit_read_operations8 b a o)

theorem deposit_state9_r10 (b a o : Nat) :
    regGet (depositState9 b a o).regs .r10 = stackBase := by
  unfold depositState9
  rw [regGet_execLoad_of_ne]
  exact deposit_state8_r10 b a o
  decide

theorem deposit_state9_r1 (b a o : Nat) :
    regGet (depositState9 b a o).regs .r1 = inputBase := by
  unfold depositState9
  rw [regGet_execLoad_of_ne]
  exact deposit_state8_r1 b a o
  decide

theorem deposit_state9_r2 (b a o : Nat) :
    regGet (depositState9 b a o).regs .r2 = o := by
  unfold depositState9
  apply regGet_execLoad_same_of_lt
  simp [Reg.idx, registerCount, deposit_state8_regs_size b a o]

theorem deposit_addr_r10_lhs9 (b a o : Nat) :
    memoryAddress (depositState9 b a o) .r10 32 = depositLhsScratch := by
  simp [memoryAddress, deposit_state9_r10 b a o, depositLhsScratch]
  native_decide

theorem deposit_step9 (b a o : Nat) :
    step depositStorageProgram (depositState9 b a o) =
      .ok (depositState10 b a o) :=
  step_stxdw_ok (depositReady9 b a o) (by rfl)
    (deposit_addr_r10_lhs9 b a o) (deposit_state9_r2 b a o)

theorem deposit_state10_r10 (b a o : Nat) :
    regGet (depositState10 b a o).regs .r10 = stackBase := by
  unfold depositState10
  rw [regGet_execStore]
  exact deposit_state9_r10 b a o

theorem deposit_state10_r1 (b a o : Nat) :
    regGet (depositState10 b a o).regs .r1 = inputBase := by
  unfold depositState10
  rw [regGet_execStore]
  exact deposit_state9_r1 b a o

theorem deposit_state9_regs_size (b a o : Nat) :
    (depositState9 b a o).regs.size = registerCount := by
  unfold depositState9
  rw [regs_size_execLoad]
  exact deposit_state8_regs_size b a o

theorem deposit_state10_regs_size (b a o : Nat) :
    (depositState10 b a o).regs.size = registerCount := by
  unfold depositState10
  rw [regs_size_execStore]
  exact deposit_state9_regs_size b a o

theorem deposit_addr_r10_lhs10 (b a o : Nat) :
    memoryAddress (depositState10 b a o) .r10 32 = depositLhsScratch := by
  simp [memoryAddress, deposit_state10_r10 b a o, depositLhsScratch]
  native_decide

theorem deposit_read_lhs10 (b a o : Nat) :
    (depositState10 b a o).memory.read depositLhsScratch = o := by
  unfold depositState10 execStore
  simp [nextPc, Memory.read_write]

theorem deposit_step10 (b a o : Nat) :
    step depositStorageProgram (depositState10 b a o) =
      .ok (depositState11 b a o) :=
  step_ldxdw_ok (depositReady10 b a o) (by rfl)
    (deposit_addr_r10_lhs10 b a o) (deposit_read_lhs10 b a o)

theorem deposit_state11_r10 (b a o : Nat) :
    regGet (depositState11 b a o).regs .r10 = stackBase := by
  unfold depositState11
  rw [regGet_execLoad_of_ne]
  exact deposit_state10_r10 b a o
  decide

theorem deposit_state11_r1 (b a o : Nat) :
    regGet (depositState11 b a o).regs .r1 = inputBase := by
  unfold depositState11
  rw [regGet_execLoad_of_ne]
  exact deposit_state10_r1 b a o
  decide

theorem deposit_state11_r2 (b a o : Nat) :
    regGet (depositState11 b a o).regs .r2 = o := by
  unfold depositState11
  apply regGet_execLoad_same_of_lt
  simp [Reg.idx, registerCount, deposit_state10_regs_size b a o]

theorem deposit_addr_r10_ops11 (b a o : Nat) :
    memoryAddress (depositState11 b a o) .r10 48 = depositOpsScratch := by
  simp [memoryAddress, deposit_state11_r10 b a o, depositOpsScratch]
  native_decide

theorem deposit_step11 (b a o : Nat) :
    step depositStorageProgram (depositState11 b a o) =
      .ok (depositState12 b a o) :=
  step_stxdw_ok (depositReady11 b a o) (by rfl)
    (deposit_addr_r10_ops11 b a o) (deposit_state11_r2 b a o)

theorem deposit_state12_r10 (b a o : Nat) :
    regGet (depositState12 b a o).regs .r10 = stackBase := by
  unfold depositState12
  rw [regGet_execStore]
  exact deposit_state11_r10 b a o

theorem deposit_state12_r1 (b a o : Nat) :
    regGet (depositState12 b a o).regs .r1 = inputBase := by
  unfold depositState12
  rw [regGet_execStore]
  exact deposit_state11_r1 b a o

theorem deposit_state11_regs_size (b a o : Nat) :
    (depositState11 b a o).regs.size = registerCount := by
  unfold depositState11
  rw [regs_size_execLoad]
  exact deposit_state10_regs_size b a o

theorem deposit_state12_regs_size (b a o : Nat) :
    (depositState12 b a o).regs.size = registerCount := by
  unfold depositState12
  rw [regs_size_execStore]
  exact deposit_state11_regs_size b a o

theorem deposit_step12 (b a o : Nat) :
    step depositStorageProgram (depositState12 b a o) =
      .ok (depositState13 b a o) :=
  step_mov64_imm_ok (depositReady12 b a o) (by rfl)

theorem deposit_state13_r2 (b a o : Nat) :
    regGet (depositState13 b a o).regs .r2 = 1 := by
  unfold depositState13
  apply regGet_execMov64_same_of_lt
  simp [Reg.idx, registerCount, deposit_state12_regs_size b a o]

theorem deposit_state13_r10 (b a o : Nat) :
    regGet (depositState13 b a o).regs .r10 = stackBase := by
  unfold depositState13
  rw [regGet_execMov64_of_ne]
  exact deposit_state12_r10 b a o
  decide

theorem deposit_state13_r1 (b a o : Nat) :
    regGet (depositState13 b a o).regs .r1 = inputBase := by
  unfold depositState13
  rw [regGet_execMov64_of_ne]
  exact deposit_state12_r1 b a o
  decide

theorem deposit_addr_r10_ops13 (b a o : Nat) :
    memoryAddress (depositState13 b a o) .r10 48 = depositOpsScratch := by
  simp [memoryAddress, deposit_state13_r10 b a o, depositOpsScratch]
  native_decide

theorem deposit_read_ops13 (b a o : Nat) :
    (depositState13 b a o).memory.read depositOpsScratch = o := by
  unfold depositState13 depositState12 execMov64 execStore setReg nextPc
  simp [Memory.read_write]

theorem deposit_step13 (b a o : Nat) :
    step depositStorageProgram (depositState13 b a o) =
      .ok (depositState14 b a o) :=
  step_ldxdw_ok (depositReady13 b a o) (by rfl)
    (deposit_addr_r10_ops13 b a o) (deposit_read_ops13 b a o)

theorem deposit_state14_r2 (b a o : Nat) :
    regGet (depositState14 b a o).regs .r2 = 1 := by
  unfold depositState14
  rw [regGet_execLoad_of_ne]
  exact deposit_state13_r2 b a o
  decide

theorem deposit_state13_regs_size (b a o : Nat) :
    (depositState13 b a o).regs.size = registerCount := by
  unfold depositState13
  rw [regs_size_execMov64]
  exact deposit_state12_regs_size b a o

theorem deposit_state14_r3 (b a o : Nat) :
    regGet (depositState14 b a o).regs .r3 = o := by
  unfold depositState14
  apply regGet_execLoad_same_of_lt
  simp [Reg.idx, registerCount, deposit_state13_regs_size b a o]

theorem deposit_state14_regs_size (b a o : Nat) :
    (depositState14 b a o).regs.size = registerCount := by
  unfold depositState14
  rw [regs_size_execLoad]
  exact deposit_state13_regs_size b a o

theorem deposit_state14_r10 (b a o : Nat) :
    regGet (depositState14 b a o).regs .r10 = stackBase := by
  unfold depositState14
  rw [regGet_execLoad_of_ne]
  exact deposit_state13_r10 b a o
  decide

theorem deposit_state14_r1 (b a o : Nat) :
    regGet (depositState14 b a o).regs .r1 = inputBase := by
  unfold depositState14
  rw [regGet_execLoad_of_ne]
  exact deposit_state13_r1 b a o
  decide

theorem deposit_step14 (b a o : Nat) :
    step depositStorageProgram (depositState14 b a o) =
      .ok (depositState15 b a o) :=
  step_add64_reg_ok (depositReady14 b a o) (by rfl)
    (deposit_state14_r2 b a o) (deposit_state14_r3 b a o)

theorem deposit_state15_r10 (b a o : Nat) :
    regGet (depositState15 b a o).regs .r10 = stackBase := by
  unfold depositState15
  rw [regGet_nextPc_setReg_of_ne]
  exact deposit_state14_r10 b a o
  decide

theorem deposit_state15_r2 (b a o : Nat) :
    regGet (depositState15 b a o).regs .r2 = 1 + o := by
  unfold depositState15
  exact regGet_nextPc_setReg_same_of_lt (depositState14 b a o) .r2 (1 + o)
    (by simp [Reg.idx, registerCount, deposit_state14_regs_size b a o])

theorem deposit_addr_r10_next_ops15 (b a o : Nat) :
    memoryAddress (depositState15 b a o) .r10 40 = depositNextOpsScratch := by
  simp [memoryAddress, deposit_state15_r10 b a o, depositNextOpsScratch]
  native_decide

theorem deposit_step15 (b a o : Nat) :
    step depositStorageProgram (depositState15 b a o) =
      .ok (depositState16 b a o) :=
  step_stxdw_ok (depositReady15 b a o) (by rfl)
    (deposit_addr_r10_next_ops15 b a o) (deposit_state15_r2 b a o)

theorem deposit_state15_r1 (b a o : Nat) :
    regGet (depositState15 b a o).regs .r1 = inputBase := by
  unfold depositState15
  rw [regGet_nextPc_setReg_of_ne]
  exact deposit_state14_r1 b a o
  decide

theorem deposit_state15_regs_size (b a o : Nat) :
    (depositState15 b a o).regs.size = registerCount := by
  unfold depositState15
  rw [regs_size_nextPc_setReg]
  exact deposit_state14_regs_size b a o

theorem deposit_state16_r10 (b a o : Nat) :
    regGet (depositState16 b a o).regs .r10 = stackBase := by
  unfold depositState16
  rw [regGet_execStore]
  exact deposit_state15_r10 b a o

theorem deposit_state16_r1 (b a o : Nat) :
    regGet (depositState16 b a o).regs .r1 = inputBase := by
  unfold depositState16
  rw [regGet_execStore]
  exact deposit_state15_r1 b a o

theorem deposit_state16_regs_size (b a o : Nat) :
    (depositState16 b a o).regs.size = registerCount := by
  unfold depositState16
  rw [regs_size_execStore]
  exact deposit_state15_regs_size b a o

theorem deposit_state9_next_balance_scratch (b a o : Nat) :
    (depositState9 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState9
  rw [memory_read_execLoad]
  exact deposit_state8_next_balance_scratch b a o

theorem deposit_state10_next_balance_scratch (b a o : Nat) :
    (depositState10 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState10
  rw [memory_read_execStore_of_ne]
  · exact deposit_state9_next_balance_scratch b a o
  · native_decide

theorem deposit_state11_next_balance_scratch (b a o : Nat) :
    (depositState11 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState11
  rw [memory_read_execLoad]
  exact deposit_state10_next_balance_scratch b a o

theorem deposit_state12_next_balance_scratch (b a o : Nat) :
    (depositState12 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState12
  rw [memory_read_execStore_of_ne]
  · exact deposit_state11_next_balance_scratch b a o
  · native_decide

theorem deposit_state13_next_balance_scratch (b a o : Nat) :
    (depositState13 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState13
  rw [memory_read_execMov64]
  exact deposit_state12_next_balance_scratch b a o

theorem deposit_state14_next_balance_scratch (b a o : Nat) :
    (depositState14 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState14
  rw [memory_read_execLoad]
  exact deposit_state13_next_balance_scratch b a o

theorem deposit_state15_next_balance_scratch (b a o : Nat) :
    (depositState15 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState15
  rw [memory_read_nextPc_setReg]
  exact deposit_state14_next_balance_scratch b a o

theorem deposit_state16_next_balance_scratch (b a o : Nat) :
    (depositState16 b a o).memory.read depositNextScratch = a + b := by
  unfold depositState16
  rw [memory_read_execStore_of_ne]
  · exact deposit_state15_next_balance_scratch b a o
  · native_decide

theorem deposit_state16_next_ops_scratch (b a o : Nat) :
    (depositState16 b a o).memory.read depositNextOpsScratch = 1 + o := by
  unfold depositState16
  exact memory_read_execStore (depositState15 b a o) depositNextOpsScratch (1 + o)

theorem deposit_state5_amount_scratch (b a o : Nat) :
    (depositState5 b a o).memory.read depositAmountScratch = a := by
  unfold depositState5
  rw [memory_read_execLoad]
  exact deposit_read_amount4 b a o

theorem deposit_state6_amount_scratch (b a o : Nat) :
    (depositState6 b a o).memory.read depositAmountScratch = a := by
  unfold depositState6
  rw [memory_read_execLoad]
  exact deposit_state5_amount_scratch b a o

theorem deposit_state7_amount_scratch (b a o : Nat) :
    (depositState7 b a o).memory.read depositAmountScratch = a := by
  unfold depositState7
  rw [memory_read_nextPc_setReg]
  exact deposit_state6_amount_scratch b a o

theorem deposit_state8_amount_scratch (b a o : Nat) :
    (depositState8 b a o).memory.read depositAmountScratch = a := by
  unfold depositState8
  exact (memory_read_execStore_of_ne (depositState7 b a o)
    (readAddr := depositAmountScratch) (writeAddr := depositNextScratch)
    (value := a + b) (by native_decide)).trans
      (deposit_state7_amount_scratch b a o)

theorem deposit_state9_amount_scratch (b a o : Nat) :
    (depositState9 b a o).memory.read depositAmountScratch = a := by
  unfold depositState9
  simpa [memory_execLoad] using deposit_state8_amount_scratch b a o

theorem deposit_state10_amount_scratch (b a o : Nat) :
    (depositState10 b a o).memory.read depositAmountScratch = a := by
  unfold depositState10
  exact (memory_read_execStore_of_ne (depositState9 b a o)
    (readAddr := depositAmountScratch) (writeAddr := depositLhsScratch)
    (value := o) (by native_decide)).trans
      (deposit_state9_amount_scratch b a o)

theorem deposit_state11_amount_scratch (b a o : Nat) :
    (depositState11 b a o).memory.read depositAmountScratch = a := by
  unfold depositState11
  simpa [memory_execLoad] using deposit_state10_amount_scratch b a o

theorem deposit_state12_amount_scratch (b a o : Nat) :
    (depositState12 b a o).memory.read depositAmountScratch = a := by
  unfold depositState12
  exact (memory_read_execStore_of_ne (depositState11 b a o)
    (readAddr := depositAmountScratch) (writeAddr := depositOpsScratch)
    (value := o) (by native_decide)).trans
      (deposit_state11_amount_scratch b a o)

theorem deposit_state13_amount_scratch (b a o : Nat) :
    (depositState13 b a o).memory.read depositAmountScratch = a := by
  unfold depositState13
  simpa [memory_execMov64] using deposit_state12_amount_scratch b a o

theorem deposit_state14_amount_scratch (b a o : Nat) :
    (depositState14 b a o).memory.read depositAmountScratch = a := by
  unfold depositState14
  simpa [memory_execLoad] using deposit_state13_amount_scratch b a o

theorem deposit_state15_amount_scratch (b a o : Nat) :
    (depositState15 b a o).memory.read depositAmountScratch = a := by
  unfold depositState15
  simpa [nextPc, setReg] using deposit_state14_amount_scratch b a o

theorem deposit_state16_amount_scratch (b a o : Nat) :
    (depositState16 b a o).memory.read depositAmountScratch = a := by
  unfold depositState16
  exact (memory_read_execStore_of_ne (depositState15 b a o)
    (readAddr := depositAmountScratch) (writeAddr := depositNextOpsScratch)
    (value := 1 + o) (by native_decide)).trans
      (deposit_state15_amount_scratch b a o)

theorem deposit_addr_r10_next16 (b a o : Nat) :
    memoryAddress (depositState16 b a o) .r10 24 = depositNextScratch := by
  simp [memoryAddress, deposit_state16_r10 b a o, depositNextScratch]
  native_decide

theorem deposit_step16 (b a o : Nat) :
    step depositStorageProgram (depositState16 b a o) =
      .ok (depositState17 b a o) :=
  step_ldxdw_ok (depositReady16 b a o) (by rfl)
    (deposit_addr_r10_next16 b a o) (deposit_state16_next_balance_scratch b a o)

theorem deposit_state17_r1 (b a o : Nat) :
    regGet (depositState17 b a o).regs .r1 = inputBase := by
  unfold depositState17
  rw [regGet_execLoad_of_ne]
  exact deposit_state16_r1 b a o
  decide

theorem deposit_state17_r10 (b a o : Nat) :
    regGet (depositState17 b a o).regs .r10 = stackBase := by
  unfold depositState17
  rw [regGet_execLoad_of_ne]
  exact deposit_state16_r10 b a o
  decide

theorem deposit_state17_regs_size (b a o : Nat) :
    (depositState17 b a o).regs.size = registerCount := by
  unfold depositState17
  rw [regs_size_execLoad]
  exact deposit_state16_regs_size b a o

theorem deposit_state17_r2 (b a o : Nat) :
    regGet (depositState17 b a o).regs .r2 = a + b := by
  unfold depositState17
  apply regGet_execLoad_same_of_lt
  simp [Reg.idx, registerCount, deposit_state16_regs_size b a o]

theorem deposit_state17_amount_scratch (b a o : Nat) :
    (depositState17 b a o).memory.read depositAmountScratch = a := by
  unfold depositState17
  simpa [memory_execLoad] using deposit_state16_amount_scratch b a o

theorem deposit_addr_r1_balance17 (b a o : Nat) :
    memoryAddress (depositState17 b a o) .r1 balanceOff = balanceOff := by
  simp [memoryAddress, deposit_state17_r1 b a o, balanceOff, inputBase]
  native_decide

theorem deposit_step17 (b a o : Nat) :
    step depositStorageProgram (depositState17 b a o) =
      .ok (depositState18 b a o) :=
  step_stxdw_ok (depositReady17 b a o) (by rfl)
    (deposit_addr_r1_balance17 b a o) (deposit_state17_r2 b a o)

theorem deposit_state18_balance (b a o : Nat) :
    (depositState18 b a o).memory.read balanceOff = a + b := by
  unfold depositState18 execStore
  simp [nextPc, Memory.read_write]

theorem deposit_state18_r10 (b a o : Nat) :
    regGet (depositState18 b a o).regs .r10 = stackBase := by
  unfold depositState18
  rw [regGet_execStore]
  exact deposit_state17_r10 b a o

theorem deposit_state18_r1 (b a o : Nat) :
    regGet (depositState18 b a o).regs .r1 = inputBase := by
  unfold depositState18
  rw [regGet_execStore]
  exact deposit_state17_r1 b a o

theorem deposit_state18_regs_size (b a o : Nat) :
    (depositState18 b a o).regs.size = registerCount := by
  unfold depositState18
  rw [regs_size_execStore]
  exact deposit_state17_regs_size b a o

theorem deposit_state18_amount_scratch (b a o : Nat) :
    (depositState18 b a o).memory.read depositAmountScratch = a := by
  unfold depositState18
  rw [memory_read_execStore_of_ne]
  · exact deposit_state17_amount_scratch b a o
  · native_decide

theorem deposit_state17_next_ops_scratch (b a o : Nat) :
    (depositState17 b a o).memory.read depositNextOpsScratch = 1 + o := by
  unfold depositState17
  simpa [memory_execLoad] using deposit_state16_next_ops_scratch b a o

theorem deposit_state18_next_ops_scratch (b a o : Nat) :
    (depositState18 b a o).memory.read depositNextOpsScratch = 1 + o := by
  unfold depositState18
  exact (memory_read_execStore_of_ne (depositState17 b a o)
    (readAddr := depositNextOpsScratch) (writeAddr := balanceOff)
    (value := a + b) (by native_decide)).trans
      (deposit_state17_next_ops_scratch b a o)

theorem deposit_addr_r10_amount18 (b a o : Nat) :
    memoryAddress (depositState18 b a o) .r10 8 = depositAmountScratch := by
  simp [memoryAddress, deposit_state18_r10 b a o, depositAmountScratch]
  native_decide

theorem deposit_step18 (b a o : Nat) :
    step depositStorageProgram (depositState18 b a o) =
      .ok (depositState19 b a o) :=
  step_ldxdw_ok (depositReady18 b a o) (by rfl)
    (deposit_addr_r10_amount18 b a o) (deposit_state18_amount_scratch b a o)

theorem deposit_state19_r1 (b a o : Nat) :
    regGet (depositState19 b a o).regs .r1 = inputBase := by
  unfold depositState19
  rw [regGet_execLoad_of_ne]
  exact deposit_state18_r1 b a o
  decide

theorem deposit_state19_r10 (b a o : Nat) :
    regGet (depositState19 b a o).regs .r10 = stackBase := by
  unfold depositState19
  rw [regGet_execLoad_of_ne]
  exact deposit_state18_r10 b a o
  decide

theorem deposit_state19_r2 (b a o : Nat) :
    regGet (depositState19 b a o).regs .r2 = a := by
  unfold depositState19
  apply regGet_execLoad_same_of_lt
  simp [Reg.idx, registerCount, deposit_state18_regs_size b a o]

theorem deposit_state19_regs_size (b a o : Nat) :
    (depositState19 b a o).regs.size = registerCount := by
  unfold depositState19
  rw [regs_size_execLoad]
  exact deposit_state18_regs_size b a o

theorem deposit_state19_balance (b a o : Nat) :
    (depositState19 b a o).memory.read balanceOff = a + b := by
  unfold depositState19
  simpa [memory_execLoad] using deposit_state18_balance b a o

theorem deposit_state19_next_ops_scratch (b a o : Nat) :
    (depositState19 b a o).memory.read depositNextOpsScratch = 1 + o := by
  unfold depositState19
  simpa [memory_execLoad] using deposit_state18_next_ops_scratch b a o

theorem deposit_addr_r1_last_value19 (b a o : Nat) :
    memoryAddress (depositState19 b a o) .r1 lastValueOff = lastValueOff := by
  simp [memoryAddress, deposit_state19_r1 b a o, lastValueOff, inputBase]
  native_decide

theorem deposit_step19 (b a o : Nat) :
    step depositStorageProgram (depositState19 b a o) =
      .ok (depositState20 b a o) :=
  step_stxdw_ok (depositReady19 b a o) (by rfl)
    (deposit_addr_r1_last_value19 b a o) (deposit_state19_r2 b a o)

theorem deposit_state20_last_value (b a o : Nat) :
    (depositState20 b a o).memory.read lastValueOff = a := by
  unfold depositState20
  exact memory_read_execStore (depositState19 b a o) lastValueOff a

theorem deposit_state20_balance (b a o : Nat) :
    (depositState20 b a o).memory.read balanceOff = a + b := by
  unfold depositState20
  exact (memory_read_execStore_of_ne (depositState19 b a o)
    (readAddr := balanceOff) (writeAddr := lastValueOff)
    (value := a) (by native_decide)).trans (deposit_state19_balance b a o)

theorem deposit_state20_r10 (b a o : Nat) :
    regGet (depositState20 b a o).regs .r10 = stackBase := by
  unfold depositState20
  rw [regGet_execStore]
  exact deposit_state19_r10 b a o

theorem deposit_state20_r1 (b a o : Nat) :
    regGet (depositState20 b a o).regs .r1 = inputBase := by
  unfold depositState20
  rw [regGet_execStore]
  exact deposit_state19_r1 b a o

theorem deposit_state20_regs_size (b a o : Nat) :
    (depositState20 b a o).regs.size = registerCount := by
  unfold depositState20
  rw [regs_size_execStore]
  exact deposit_state19_regs_size b a o

theorem deposit_state20_next_ops_scratch (b a o : Nat) :
    (depositState20 b a o).memory.read depositNextOpsScratch = 1 + o := by
  unfold depositState20
  exact (memory_read_execStore_of_ne (depositState19 b a o)
    (readAddr := depositNextOpsScratch) (writeAddr := lastValueOff)
    (value := a) (by native_decide)).trans
      (deposit_state19_next_ops_scratch b a o)

theorem deposit_addr_r10_next_ops20 (b a o : Nat) :
    memoryAddress (depositState20 b a o) .r10 40 = depositNextOpsScratch := by
  simp [memoryAddress, deposit_state20_r10 b a o, depositNextOpsScratch]
  native_decide

theorem deposit_step20 (b a o : Nat) :
    step depositStorageProgram (depositState20 b a o) =
      .ok (depositState21 b a o) :=
  step_ldxdw_ok (depositReady20 b a o) (by rfl)
    (deposit_addr_r10_next_ops20 b a o) (deposit_state20_next_ops_scratch b a o)

theorem deposit_state21_r1 (b a o : Nat) :
    regGet (depositState21 b a o).regs .r1 = inputBase := by
  unfold depositState21
  rw [regGet_execLoad_of_ne]
  exact deposit_state20_r1 b a o
  decide

theorem deposit_state21_r2 (b a o : Nat) :
    regGet (depositState21 b a o).regs .r2 = 1 + o := by
  unfold depositState21
  apply regGet_execLoad_same_of_lt
  simp [Reg.idx, registerCount, deposit_state20_regs_size b a o]

theorem deposit_state21_regs_size (b a o : Nat) :
    (depositState21 b a o).regs.size = registerCount := by
  unfold depositState21
  rw [regs_size_execLoad]
  exact deposit_state20_regs_size b a o

theorem deposit_state21_balance (b a o : Nat) :
    (depositState21 b a o).memory.read balanceOff = a + b := by
  unfold depositState21
  simpa [memory_execLoad] using deposit_state20_balance b a o

theorem deposit_state21_last_value (b a o : Nat) :
    (depositState21 b a o).memory.read lastValueOff = a := by
  unfold depositState21
  simpa [memory_execLoad] using deposit_state20_last_value b a o

theorem deposit_addr_r1_operations21 (b a o : Nat) :
    memoryAddress (depositState21 b a o) .r1 operationsOff = operationsOff := by
  simp [memoryAddress, deposit_state21_r1 b a o, operationsOff, inputBase]
  native_decide

theorem deposit_step21 (b a o : Nat) :
    step depositStorageProgram (depositState21 b a o) =
      .ok (depositState22 b a o) :=
  step_stxdw_ok (depositReady21 b a o) (by rfl)
    (deposit_addr_r1_operations21 b a o) (deposit_state21_r2 b a o)

theorem deposit_state22_operations (b a o : Nat) :
    (depositState22 b a o).memory.read operationsOff = 1 + o := by
  unfold depositState22
  exact memory_read_execStore (depositState21 b a o) operationsOff (1 + o)

theorem deposit_state22_balance (b a o : Nat) :
    (depositState22 b a o).memory.read balanceOff = a + b := by
  unfold depositState22
  exact (memory_read_execStore_of_ne (depositState21 b a o)
    (readAddr := balanceOff) (writeAddr := operationsOff)
    (value := 1 + o) (by native_decide)).trans
      (deposit_state21_balance b a o)

theorem deposit_state22_last_value (b a o : Nat) :
    (depositState22 b a o).memory.read lastValueOff = a := by
  unfold depositState22
  exact (memory_read_execStore_of_ne (depositState21 b a o)
    (readAddr := lastValueOff) (writeAddr := operationsOff)
    (value := 1 + o) (by native_decide)).trans
      (deposit_state21_last_value b a o)

theorem deposit_state22_regs_size (b a o : Nat) :
    (depositState22 b a o).regs.size = registerCount := by
  unfold depositState22
  rw [regs_size_execStore]
  exact deposit_state21_regs_size b a o

theorem deposit_step22 (b a o : Nat) :
    step depositStorageProgram (depositState22 b a o) =
      .ok (depositState23 b a o) :=
  step_mov64_imm_ok (depositReady22 b a o) (by rfl)

theorem deposit_state23_r0 (b a o : Nat) :
    regGet (depositState23 b a o).regs .r0 = 0 := by
  unfold depositState23
  apply regGet_execMov64_same_of_lt
  simp [Reg.idx, registerCount, deposit_state22_regs_size b a o]

theorem deposit_state23_balance (b a o : Nat) :
    (depositState23 b a o).memory.read balanceOff = a + b := by
  unfold depositState23
  simpa [memory_execMov64] using deposit_state22_balance b a o

theorem deposit_state23_last_value (b a o : Nat) :
    (depositState23 b a o).memory.read lastValueOff = a := by
  unfold depositState23
  simpa [memory_execMov64] using deposit_state22_last_value b a o

theorem deposit_state23_operations (b a o : Nat) :
    (depositState23 b a o).memory.read operationsOff = 1 + o := by
  unfold depositState23
  simpa [memory_execMov64] using deposit_state22_operations b a o

theorem deposit_step23 (b a o : Nat) :
    step depositStorageProgram (depositState23 b a o) =
      .ok (depositFinalState b a o) :=
  step_exit_ok (depositReady23 b a o) (by rfl) (deposit_state23_r0 b a o)

theorem deposit_runSteps (b a o : Nat) :
    runSteps depositStorageProgram 24 (depositStorageInitialState b a o) =
      .ok (depositFinalState b a o) := by
  apply runSteps_of_stepPath_done
  exact StepPath.cons (depositReady0 b a o) (deposit_step0 b a o)
    (StepPath.cons (depositReady1 b a o) (deposit_step1 b a o)
      (StepPath.cons (depositReady2 b a o) (deposit_step2 b a o)
        (StepPath.cons (depositReady3 b a o) (deposit_step3 b a o)
          (StepPath.cons (depositReady4 b a o) (deposit_step4 b a o)
            (StepPath.cons (depositReady5 b a o) (deposit_step5 b a o)
              (StepPath.cons (depositReady6 b a o) (deposit_step6 b a o)
                (StepPath.cons (depositReady7 b a o) (deposit_step7 b a o)
                  (StepPath.cons (depositReady8 b a o) (deposit_step8 b a o)
                    (StepPath.cons (depositReady9 b a o) (deposit_step9 b a o)
                      (StepPath.cons (depositReady10 b a o) (deposit_step10 b a o)
                        (StepPath.cons (depositReady11 b a o) (deposit_step11 b a o)
                          (StepPath.cons (depositReady12 b a o) (deposit_step12 b a o)
                            (StepPath.cons (depositReady13 b a o) (deposit_step13 b a o)
                              (StepPath.cons (depositReady14 b a o) (deposit_step14 b a o)
                                (StepPath.cons (depositReady15 b a o) (deposit_step15 b a o)
                                  (StepPath.cons (depositReady16 b a o) (deposit_step16 b a o)
                                    (StepPath.cons (depositReady17 b a o) (deposit_step17 b a o)
                                      (StepPath.cons (depositReady18 b a o) (deposit_step18 b a o)
                                        (StepPath.cons (depositReady19 b a o) (deposit_step19 b a o)
                                          (StepPath.cons (depositReady20 b a o) (deposit_step20 b a o)
                                            (StepPath.cons (depositReady21 b a o)
                                              (deposit_step21 b a o)
                                              (StepPath.cons (depositReady22 b a o)
                                                (deposit_step22 b a o)
                                                (StepPath.cons (depositReady23 b a o)
                                                  (deposit_step23 b a o)
                                                  (StepPath.nil _
                                                    (depositFinal_halted b a o)))))))))))))))))))))))))

theorem depositFinal_balance (b a o : Nat) :
    (depositFinalState b a o).memory.read balanceOff = a + b := by
  unfold depositFinalState
  simpa [memory_execExit] using deposit_state23_balance b a o

theorem depositFinal_last_value (b a o : Nat) :
    (depositFinalState b a o).memory.read lastValueOff = a := by
  unfold depositFinalState
  simpa [memory_execExit] using deposit_state23_last_value b a o

theorem depositFinal_operations (b a o : Nat) :
    (depositFinalState b a o).memory.read operationsOff = 1 + o := by
  unfold depositFinalState
  simpa [memory_execExit] using deposit_state23_operations b a o

/-! ### get_net_value storage core

This models the return path after account validation:

`return balance - fees`.
-/

def getNetValueStorageProgram : Program := {
  instructions := #[
    inst .ldxdw (some .r2) (some .r1) (some (.num balanceOff)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 8)) none,
    inst .ldxdw (some .r2) (some .r1) (some (.num feesOff)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 16)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 8)) none,
    inst .stxdw (some .r10) (some .r2) (some (.num 24)) none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 16)) none,
    inst .mov64 (some .r3) (some .r2) none none,
    inst .ldxdw (some .r2) (some .r10) (some (.num 24)) none,
    inst .sub64 (some .r2) (some .r3) none none,
    inst .mov64 (some .r3) (some .r10) none none,
    inst .sub64 (some .r3) none none (some (.num 8)),
    inst .stxdw (some .r3) (some .r2) (some (.num 0)) none,
    inst .mov64 (some .r1) (some .r3) none none,
    inst .mov64 (some .r2) none none (some (.num 8)),
    inst .call none none none (some (.sym sol_set_return_data)),
    inst .mov64 (some .r0) none none (some (.num 0)),
    inst .exit
  ]
  labels := #[]
  symbols := #[]
}

def getNetValueInitialState (balance fees : Nat) : State :=
  { regs := regSet (regSet emptyRegs .r1 inputBase) .r10 stackBase
    memory := #[
      (balanceOff, balance),
      (feesOff, fees)
    ]
    pc := 0 }

def getNetState1 (balance fees : Nat) : State :=
  execLoad (getNetValueInitialState balance fees) .r2 balanceOff balance

def getNetState2 (balance fees : Nat) : State :=
  execStore (getNetState1 balance fees) getNetBalanceScratch balance

def getNetState3 (balance fees : Nat) : State :=
  execLoad (getNetState2 balance fees) .r2 feesOff fees

def getNetState4 (balance fees : Nat) : State :=
  execStore (getNetState3 balance fees) getNetFeesScratch fees

def getNetState5 (balance fees : Nat) : State :=
  execLoad (getNetState4 balance fees) .r2 getNetBalanceScratch balance

def getNetState6 (balance fees : Nat) : State :=
  execStore (getNetState5 balance fees) getNetLhsScratch balance

def getNetState7 (balance fees : Nat) : State :=
  execLoad (getNetState6 balance fees) .r2 getNetFeesScratch fees

def getNetState8 (balance fees : Nat) : State :=
  execMov64 (getNetState7 balance fees) .r3 fees

def getNetState9 (balance fees : Nat) : State :=
  execLoad (getNetState8 balance fees) .r2 getNetLhsScratch balance

def getNetState10 (balance fees : Nat) : State :=
  nextPc (setReg (getNetState9 balance fees) .r2 (balance - fees))

def getNetState11 (balance fees : Nat) : State :=
  execMov64 (getNetState10 balance fees) .r3 stackBase

def getNetState12 (balance fees : Nat) : State :=
  nextPc (setReg (getNetState11 balance fees) .r3 getNetReturnScratch)

def getNetState13 (balance fees : Nat) : State :=
  execStore (getNetState12 balance fees) getNetReturnScratch (balance - fees)

def getNetState14 (balance fees : Nat) : State :=
  execMov64 (getNetState13 balance fees) .r1 getNetReturnScratch

def getNetState15 (balance fees : Nat) : State :=
  execMov64 (getNetState14 balance fees) .r2 8

def getNetState16 (balance fees : Nat) : State :=
  execSetReturnData (getNetState15 balance fees) (balance - fees)

def getNetState17 (balance fees : Nat) : State :=
  execMov64 (getNetState16 balance fees) .r0 0

def getNetFinalState (balance fees : Nat) : State :=
  execExit (getNetState17 balance fees) 0

theorem getNet_not_halted0 (b f : Nat) :
    ¬ (getNetValueInitialState b f).halted := by intro h; cases h
theorem getNet_not_halted1 (b f : Nat) : ¬ (getNetState1 b f).halted := by intro h; cases h
theorem getNet_not_halted2 (b f : Nat) : ¬ (getNetState2 b f).halted := by intro h; cases h
theorem getNet_not_halted3 (b f : Nat) : ¬ (getNetState3 b f).halted := by intro h; cases h
theorem getNet_not_halted4 (b f : Nat) : ¬ (getNetState4 b f).halted := by intro h; cases h
theorem getNet_not_halted5 (b f : Nat) : ¬ (getNetState5 b f).halted := by intro h; cases h
theorem getNet_not_halted6 (b f : Nat) : ¬ (getNetState6 b f).halted := by intro h; cases h
theorem getNet_not_halted7 (b f : Nat) : ¬ (getNetState7 b f).halted := by intro h; cases h
theorem getNet_not_halted8 (b f : Nat) : ¬ (getNetState8 b f).halted := by intro h; cases h
theorem getNet_not_halted9 (b f : Nat) : ¬ (getNetState9 b f).halted := by intro h; cases h
theorem getNet_not_halted10 (b f : Nat) : ¬ (getNetState10 b f).halted := by intro h; cases h
theorem getNet_not_halted11 (b f : Nat) : ¬ (getNetState11 b f).halted := by intro h; cases h
theorem getNet_not_halted12 (b f : Nat) : ¬ (getNetState12 b f).halted := by intro h; cases h
theorem getNet_not_halted13 (b f : Nat) : ¬ (getNetState13 b f).halted := by intro h; cases h
theorem getNet_not_halted14 (b f : Nat) : ¬ (getNetState14 b f).halted := by intro h; cases h
theorem getNet_not_halted15 (b f : Nat) : ¬ (getNetState15 b f).halted := by intro h; cases h
theorem getNet_not_halted16 (b f : Nat) : ¬ (getNetState16 b f).halted := by intro h; cases h
theorem getNet_not_halted17 (b f : Nat) : ¬ (getNetState17 b f).halted := by intro h; cases h
theorem getNetFinal_halted (b f : Nat) : (getNetFinalState b f).halted := rfl

def getNetReady0 (b f : Nat) : StepReady getNetValueStorageProgram (getNetValueInitialState b f) :=
  ⟨getNet_not_halted0 b f, ⟨getNetValueStorageProgram.instructions[0], rfl⟩⟩
def getNetReady1 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState1 b f) :=
  ⟨getNet_not_halted1 b f, ⟨getNetValueStorageProgram.instructions[1], rfl⟩⟩
def getNetReady2 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState2 b f) :=
  ⟨getNet_not_halted2 b f, ⟨getNetValueStorageProgram.instructions[2], rfl⟩⟩
def getNetReady3 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState3 b f) :=
  ⟨getNet_not_halted3 b f, ⟨getNetValueStorageProgram.instructions[3], rfl⟩⟩
def getNetReady4 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState4 b f) :=
  ⟨getNet_not_halted4 b f, ⟨getNetValueStorageProgram.instructions[4], rfl⟩⟩
def getNetReady5 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState5 b f) :=
  ⟨getNet_not_halted5 b f, ⟨getNetValueStorageProgram.instructions[5], rfl⟩⟩
def getNetReady6 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState6 b f) :=
  ⟨getNet_not_halted6 b f, ⟨getNetValueStorageProgram.instructions[6], rfl⟩⟩
def getNetReady7 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState7 b f) :=
  ⟨getNet_not_halted7 b f, ⟨getNetValueStorageProgram.instructions[7], rfl⟩⟩
def getNetReady8 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState8 b f) :=
  ⟨getNet_not_halted8 b f, ⟨getNetValueStorageProgram.instructions[8], rfl⟩⟩
def getNetReady9 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState9 b f) :=
  ⟨getNet_not_halted9 b f, ⟨getNetValueStorageProgram.instructions[9], rfl⟩⟩
def getNetReady10 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState10 b f) :=
  ⟨getNet_not_halted10 b f, ⟨getNetValueStorageProgram.instructions[10], rfl⟩⟩
def getNetReady11 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState11 b f) :=
  ⟨getNet_not_halted11 b f, ⟨getNetValueStorageProgram.instructions[11], rfl⟩⟩
def getNetReady12 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState12 b f) :=
  ⟨getNet_not_halted12 b f, ⟨getNetValueStorageProgram.instructions[12], rfl⟩⟩
def getNetReady13 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState13 b f) :=
  ⟨getNet_not_halted13 b f, ⟨getNetValueStorageProgram.instructions[13], rfl⟩⟩
def getNetReady14 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState14 b f) :=
  ⟨getNet_not_halted14 b f, ⟨getNetValueStorageProgram.instructions[14], rfl⟩⟩
def getNetReady15 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState15 b f) :=
  ⟨getNet_not_halted15 b f, ⟨getNetValueStorageProgram.instructions[15], rfl⟩⟩
def getNetReady16 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState16 b f) :=
  ⟨getNet_not_halted16 b f, ⟨getNetValueStorageProgram.instructions[16], rfl⟩⟩
def getNetReady17 (b f : Nat) : StepReady getNetValueStorageProgram (getNetState17 b f) :=
  ⟨getNet_not_halted17 b f, ⟨getNetValueStorageProgram.instructions[17], rfl⟩⟩

theorem getNet_r1_base (b f : Nat) :
    regGet (getNetValueInitialState b f).regs .r1 = inputBase := by
  unfold getNetValueInitialState regGet regSet emptyRegs inputBase registerCount
  rfl

theorem getNet_r10_stack (b f : Nat) :
    regGet (getNetValueInitialState b f).regs .r10 = stackBase := by
  unfold getNetValueInitialState regGet regSet emptyRegs stackBase registerCount
  rfl

theorem getNet_read_balance0 (b f : Nat) :
    (getNetValueInitialState b f).memory.read balanceOff = b := by
  unfold getNetValueInitialState balanceOff feesOff
  simp [Memory.read]

theorem getNet_addr_r1_balance0 (b f : Nat) :
    memoryAddress (getNetValueInitialState b f) .r1 balanceOff = balanceOff := by
  simp [memoryAddress, getNet_r1_base b f, inputBase, balanceOff]
  native_decide

theorem getNet_step0 (b f : Nat) :
    step getNetValueStorageProgram (getNetValueInitialState b f) =
      .ok (getNetState1 b f) :=
  step_ldxdw_ok (getNetReady0 b f) (by rfl)
    (getNet_addr_r1_balance0 b f) (getNet_read_balance0 b f)

theorem getNet_state1_r10 (b f : Nat) :
    regGet (getNetState1 b f).regs .r10 = stackBase := by
  unfold getNetState1 getNetValueInitialState execLoad setReg nextPc regGet regSet stackBase
  rfl

theorem getNet_state1_r2 (b f : Nat) :
    regGet (getNetState1 b f).regs .r2 = b := by
  unfold getNetState1 getNetValueInitialState execLoad setReg nextPc regGet regSet
  rfl

theorem getNet_addr_r10_balance1 (b f : Nat) :
    memoryAddress (getNetState1 b f) .r10 8 = getNetBalanceScratch := by
  simp [memoryAddress, getNet_state1_r10 b f, getNetBalanceScratch]
  native_decide

theorem getNet_step1 (b f : Nat) :
    step getNetValueStorageProgram (getNetState1 b f) =
      .ok (getNetState2 b f) :=
  step_stxdw_ok (getNetReady1 b f) (by rfl)
    (getNet_addr_r10_balance1 b f) (getNet_state1_r2 b f)

theorem getNet_state2_r1 (b f : Nat) :
    regGet (getNetState2 b f).regs .r1 = inputBase := by
  unfold getNetState2
  rw [regGet_execStore]
  unfold getNetState1
  rw [regGet_execLoad_of_ne]
  exact getNet_r1_base b f
  decide

theorem getNet_read_fees2 (b f : Nat) :
    (getNetState2 b f).memory.read feesOff = f := by
  unfold getNetState2 getNetState1 getNetValueInitialState execStore execLoad
    setReg nextPc getNetBalanceScratch balanceOff feesOff
  simp [Memory.read, Memory.write, stackBase]

theorem getNet_addr_r1_fees2 (b f : Nat) :
    memoryAddress (getNetState2 b f) .r1 feesOff = feesOff := by
  simp [memoryAddress, getNet_state2_r1 b f, inputBase, feesOff]
  native_decide

theorem getNet_step2 (b f : Nat) :
    step getNetValueStorageProgram (getNetState2 b f) =
      .ok (getNetState3 b f) :=
  step_ldxdw_ok (getNetReady2 b f) (by rfl)
    (getNet_addr_r1_fees2 b f) (getNet_read_fees2 b f)

theorem getNet_state3_r10 (b f : Nat) :
    regGet (getNetState3 b f).regs .r10 = stackBase := by
  unfold getNetState3
  rw [regGet_execLoad_of_ne]
  unfold getNetState2
  rw [regGet_execStore]
  exact getNet_state1_r10 b f
  decide

theorem getNet_state3_r2 (b f : Nat) :
    regGet (getNetState3 b f).regs .r2 = f := by
  unfold getNetState3 getNetState2 getNetState1 getNetValueInitialState
    execLoad execStore setReg nextPc regGet regSet
  rfl

theorem getNet_addr_r10_fees3 (b f : Nat) :
    memoryAddress (getNetState3 b f) .r10 16 = getNetFeesScratch := by
  simp [memoryAddress, getNet_state3_r10 b f, getNetFeesScratch]
  native_decide

theorem getNet_step3 (b f : Nat) :
    step getNetValueStorageProgram (getNetState3 b f) =
      .ok (getNetState4 b f) :=
  step_stxdw_ok (getNetReady3 b f) (by rfl)
    (getNet_addr_r10_fees3 b f) (getNet_state3_r2 b f)

theorem getNet_state4_r10 (b f : Nat) :
    regGet (getNetState4 b f).regs .r10 = stackBase := by
  unfold getNetState4
  rw [regGet_execStore]
  exact getNet_state3_r10 b f

theorem getNet_read_balance_scratch4 (b f : Nat) :
    (getNetState4 b f).memory.read getNetBalanceScratch = b := by
  unfold getNetState4
  exact (memory_read_execStore_of_ne (getNetState3 b f)
    (readAddr := getNetBalanceScratch) (writeAddr := getNetFeesScratch)
    (value := f) (by native_decide)).trans (by
      unfold getNetState3 getNetState2
      simpa [memory_execLoad] using
        (memory_read_execStore (getNetState1 b f) getNetBalanceScratch b))

theorem getNet_addr_r10_balance4 (b f : Nat) :
    memoryAddress (getNetState4 b f) .r10 8 = getNetBalanceScratch := by
  simp [memoryAddress, getNet_state4_r10 b f, getNetBalanceScratch]
  native_decide

theorem getNet_step4 (b f : Nat) :
    step getNetValueStorageProgram (getNetState4 b f) =
      .ok (getNetState5 b f) :=
  step_ldxdw_ok (getNetReady4 b f) (by rfl)
    (getNet_addr_r10_balance4 b f) (getNet_read_balance_scratch4 b f)

theorem getNet_state5_r10 (b f : Nat) :
    regGet (getNetState5 b f).regs .r10 = stackBase := by
  unfold getNetState5
  rw [regGet_execLoad_of_ne]
  exact getNet_state4_r10 b f
  decide

theorem getNet_state5_r2 (b f : Nat) :
    regGet (getNetState5 b f).regs .r2 = b := by
  unfold getNetState5 getNetState4 getNetState3 getNetState2 getNetState1
    getNetValueInitialState execLoad execStore setReg nextPc regGet regSet
  rfl

theorem getNet_addr_r10_lhs5 (b f : Nat) :
    memoryAddress (getNetState5 b f) .r10 24 = getNetLhsScratch := by
  simp [memoryAddress, getNet_state5_r10 b f, getNetLhsScratch]
  native_decide

theorem getNet_step5 (b f : Nat) :
    step getNetValueStorageProgram (getNetState5 b f) =
      .ok (getNetState6 b f) :=
  step_stxdw_ok (getNetReady5 b f) (by rfl)
    (getNet_addr_r10_lhs5 b f) (getNet_state5_r2 b f)

theorem getNet_state6_r10 (b f : Nat) :
    regGet (getNetState6 b f).regs .r10 = stackBase := by
  unfold getNetState6
  rw [regGet_execStore]
  exact getNet_state5_r10 b f

theorem getNet_read_fees_scratch6 (b f : Nat) :
    (getNetState6 b f).memory.read getNetFeesScratch = f := by
  unfold getNetState6
  exact (memory_read_execStore_of_ne (getNetState5 b f)
    (readAddr := getNetFeesScratch) (writeAddr := getNetLhsScratch)
    (value := b) (by native_decide)).trans (by
      unfold getNetState5 getNetState4
      simpa [memory_execLoad] using
        (memory_read_execStore (getNetState3 b f) getNetFeesScratch f))

theorem getNet_addr_r10_fees6 (b f : Nat) :
    memoryAddress (getNetState6 b f) .r10 16 = getNetFeesScratch := by
  simp [memoryAddress, getNet_state6_r10 b f, getNetFeesScratch]
  native_decide

theorem getNet_step6 (b f : Nat) :
    step getNetValueStorageProgram (getNetState6 b f) =
      .ok (getNetState7 b f) :=
  step_ldxdw_ok (getNetReady6 b f) (by rfl)
    (getNet_addr_r10_fees6 b f) (getNet_read_fees_scratch6 b f)

theorem getNet_state7_r2 (b f : Nat) :
    regGet (getNetState7 b f).regs .r2 = f := by
  unfold getNetState7
  apply regGet_execLoad_same_of_lt
  unfold getNetState6 getNetState5 getNetState4 getNetState3 getNetState2
    getNetState1 getNetValueInitialState execStore execLoad setReg nextPc
    emptyRegs registerCount regSet
  simp [Reg.idx]

theorem getNet_step7 (b f : Nat) :
    step getNetValueStorageProgram (getNetState7 b f) =
      .ok (getNetState8 b f) :=
  step_mov64_reg_ok (getNetReady7 b f) (by rfl) (getNet_state7_r2 b f)

theorem getNet_state8_r10 (b f : Nat) :
    regGet (getNetState8 b f).regs .r10 = stackBase := by
  unfold getNetState8
  rw [regGet_execMov64_of_ne]
  unfold getNetState7
  rw [regGet_execLoad_of_ne]
  exact getNet_state6_r10 b f
  decide
  decide

theorem getNet_read_lhs8 (b f : Nat) :
    (getNetState8 b f).memory.read getNetLhsScratch = b := by
  unfold getNetState8
  simpa [memory_execMov64] using
    (by
      unfold getNetState7 getNetState6
      simpa [memory_execLoad] using
        (memory_read_execStore (getNetState5 b f) getNetLhsScratch b))

theorem getNet_addr_r10_lhs8 (b f : Nat) :
    memoryAddress (getNetState8 b f) .r10 24 = getNetLhsScratch := by
  simp [memoryAddress, getNet_state8_r10 b f, getNetLhsScratch]
  native_decide

theorem getNet_step8 (b f : Nat) :
    step getNetValueStorageProgram (getNetState8 b f) =
      .ok (getNetState9 b f) :=
  step_ldxdw_ok (getNetReady8 b f) (by rfl)
    (getNet_addr_r10_lhs8 b f) (getNet_read_lhs8 b f)

theorem getNet_state9_r2 (b f : Nat) :
    regGet (getNetState9 b f).regs .r2 = b := by
  unfold getNetState9
  apply regGet_execLoad_same_of_lt
  unfold getNetState8 getNetState7 getNetState6 getNetState5 getNetState4
    getNetState3 getNetState2 getNetState1 getNetValueInitialState execMov64
    execLoad execStore setReg nextPc emptyRegs registerCount regSet
  simp [Reg.idx]

theorem getNet_state9_r3 (b f : Nat) :
    regGet (getNetState9 b f).regs .r3 = f := by
  unfold getNetState9
  rw [regGet_execLoad_of_ne]
  unfold getNetState8
  apply regGet_execMov64_same_of_lt
  unfold getNetState7 getNetState6 getNetState5 getNetState4 getNetState3
    getNetState2 getNetState1 getNetValueInitialState execLoad execStore
    setReg nextPc emptyRegs registerCount regSet
  simp [Reg.idx]
  decide

theorem getNet_state9_r10 (b f : Nat) :
    regGet (getNetState9 b f).regs .r10 = stackBase := by
  unfold getNetState9
  rw [regGet_execLoad_of_ne]
  exact getNet_state8_r10 b f
  decide

theorem getNet_step9 (b f : Nat) :
    step getNetValueStorageProgram (getNetState9 b f) =
      .ok (getNetState10 b f) :=
  step_sub64_reg_ok (getNetReady9 b f) (by rfl)
    (getNet_state9_r2 b f) (getNet_state9_r3 b f)

theorem getNet_state10_r10 (b f : Nat) :
    regGet (getNetState10 b f).regs .r10 = stackBase := by
  unfold getNetState10
  rw [regGet_nextPc, regGet_setReg_of_ne]
  exact getNet_state9_r10 b f
  decide

theorem getNet_step10 (b f : Nat) :
    step getNetValueStorageProgram (getNetState10 b f) =
      .ok (getNetState11 b f) :=
  step_mov64_reg_ok (getNetReady10 b f) (by rfl) (getNet_state10_r10 b f)

theorem getNet_state11_r3 (b f : Nat) :
    regGet (getNetState11 b f).regs .r3 = stackBase := by
  unfold getNetState11
  apply regGet_execMov64_same_of_lt
  unfold getNetState10 getNetState9 getNetState8 getNetState7 getNetState6
    getNetState5 getNetState4 getNetState3 getNetState2 getNetState1
    getNetValueInitialState execMov64 execLoad execStore setReg nextPc
    emptyRegs registerCount regSet
  simp [Reg.idx]

theorem getNet_step11 (b f : Nat) :
    step getNetValueStorageProgram (getNetState11 b f) =
      .ok (getNetState12 b f) :=
  step_sub64_imm_ok (getNetReady11 b f) (by rfl) (getNet_state11_r3 b f)

theorem getNet_state12_r2 (b f : Nat) :
    regGet (getNetState12 b f).regs .r2 = b - f := by
  unfold getNetState12
  rw [regGet_nextPc, regGet_setReg_of_ne]
  unfold getNetState11
  rw [regGet_execMov64_of_ne]
  unfold getNetState10
  rw [regGet_nextPc]
  apply regGet_setReg_same_of_lt
  unfold getNetState9 getNetState8 getNetState7 getNetState6 getNetState5
    getNetState4 getNetState3 getNetState2 getNetState1 getNetValueInitialState
    execMov64 execLoad execStore setReg nextPc emptyRegs registerCount regSet
  simp [Reg.idx]
  decide
  decide

theorem getNet_state12_r3 (b f : Nat) :
    regGet (getNetState12 b f).regs .r3 = getNetReturnScratch := by
  unfold getNetState12
  rw [regGet_nextPc]
  apply regGet_setReg_same_of_lt
  unfold getNetState11 getNetState10 getNetState9 getNetState8 getNetState7
    getNetState6 getNetState5 getNetState4 getNetState3 getNetState2
    getNetState1 getNetValueInitialState execMov64 execLoad execStore setReg
    nextPc emptyRegs registerCount regSet
  simp [Reg.idx]

theorem getNet_addr_r3_return12 (b f : Nat) :
    memoryAddress (getNetState12 b f) .r3 0 = getNetReturnScratch := by
  simp [memoryAddress, getNet_state12_r3 b f, getNetReturnScratch]

theorem getNet_step12 (b f : Nat) :
    step getNetValueStorageProgram (getNetState12 b f) =
      .ok (getNetState13 b f) :=
  step_stxdw_ok (getNetReady12 b f) (by rfl)
    (getNet_addr_r3_return12 b f) (getNet_state12_r2 b f)

theorem getNet_state13_r3 (b f : Nat) :
    regGet (getNetState13 b f).regs .r3 = getNetReturnScratch := by
  unfold getNetState13
  rw [regGet_execStore]
  exact getNet_state12_r3 b f

theorem getNet_step13 (b f : Nat) :
    step getNetValueStorageProgram (getNetState13 b f) =
      .ok (getNetState14 b f) :=
  step_mov64_reg_ok (getNetReady13 b f) (by rfl) (getNet_state13_r3 b f)

theorem getNet_step14 (b f : Nat) :
    step getNetValueStorageProgram (getNetState14 b f) =
      .ok (getNetState15 b f) :=
  step_mov64_imm_ok (getNetReady14 b f) (by rfl)

theorem getNet_state15_r1 (b f : Nat) :
    regGet (getNetState15 b f).regs .r1 = getNetReturnScratch := by
  unfold getNetState15
  rw [regGet_execMov64_of_ne]
  unfold getNetState14
  apply regGet_execMov64_same_of_lt
  unfold getNetState13 getNetState12 getNetState11 getNetState10 getNetState9
    getNetState8 getNetState7 getNetState6 getNetState5 getNetState4
    getNetState3 getNetState2 getNetState1 getNetValueInitialState execStore
    execMov64 execLoad setReg nextPc emptyRegs registerCount regSet
  simp [Reg.idx]
  decide

theorem getNet_state15_return_scratch (b f : Nat) :
    (getNetState15 b f).memory.read getNetReturnScratch = b - f := by
  unfold getNetState15 getNetState14
  simpa [getNetState13, memory_execMov64] using
    (memory_read_execStore (getNetState12 b f) getNetReturnScratch (b - f))

theorem getNet_step15 (b f : Nat) :
    step getNetValueStorageProgram (getNetState15 b f) =
      .ok (getNetState16 b f) :=
  step_syscall_set_return_data_ok (getNetReady15 b f) (by rfl)
    (getNet_state15_r1 b f) (getNet_state15_return_scratch b f)

theorem getNet_step16 (b f : Nat) :
    step getNetValueStorageProgram (getNetState16 b f) =
      .ok (getNetState17 b f) :=
  step_mov64_imm_ok (getNetReady16 b f) (by rfl)

theorem getNet_state17_r0 (b f : Nat) :
    regGet (getNetState17 b f).regs .r0 = 0 := by
  unfold getNetState17
  apply regGet_execMov64_same_of_lt
  unfold getNetState16 getNetState15 getNetState14 getNetState13 getNetState12
    getNetState11 getNetState10 getNetState9 getNetState8 getNetState7
    getNetState6 getNetState5 getNetState4 getNetState3 getNetState2
    getNetState1 getNetValueInitialState execSetReturnData execStore execMov64
    execLoad setReg nextPc emptyRegs registerCount regSet
  simp [Reg.idx]

theorem getNet_step17 (b f : Nat) :
    step getNetValueStorageProgram (getNetState17 b f) =
      .ok (getNetFinalState b f) :=
  step_exit_ok (getNetReady17 b f) (by rfl) (getNet_state17_r0 b f)

theorem getNetValue_runSteps (b f : Nat) :
    runSteps getNetValueStorageProgram 18 (getNetValueInitialState b f) =
      .ok (getNetFinalState b f) := by
  apply runSteps_of_stepPath_done
  exact StepPath.cons (getNetReady0 b f) (getNet_step0 b f)
    (StepPath.cons (getNetReady1 b f) (getNet_step1 b f)
      (StepPath.cons (getNetReady2 b f) (getNet_step2 b f)
        (StepPath.cons (getNetReady3 b f) (getNet_step3 b f)
          (StepPath.cons (getNetReady4 b f) (getNet_step4 b f)
            (StepPath.cons (getNetReady5 b f) (getNet_step5 b f)
              (StepPath.cons (getNetReady6 b f) (getNet_step6 b f)
                (StepPath.cons (getNetReady7 b f) (getNet_step7 b f)
                  (StepPath.cons (getNetReady8 b f) (getNet_step8 b f)
                    (StepPath.cons (getNetReady9 b f) (getNet_step9 b f)
                      (StepPath.cons (getNetReady10 b f) (getNet_step10 b f)
                        (StepPath.cons (getNetReady11 b f) (getNet_step11 b f)
                          (StepPath.cons (getNetReady12 b f) (getNet_step12 b f)
                            (StepPath.cons (getNetReady13 b f) (getNet_step13 b f)
                              (StepPath.cons (getNetReady14 b f) (getNet_step14 b f)
                                (StepPath.cons (getNetReady15 b f) (getNet_step15 b f)
                                  (StepPath.cons (getNetReady16 b f) (getNet_step16 b f)
                                    (StepPath.cons (getNetReady17 b f)
                                      (getNet_step17 b f)
                                      (StepPath.nil _
                                        (getNetFinal_halted b f)))))))))))))))))))

theorem getNetValue_return_data (b f : Nat) :
    (getNetFinalState b f).returnData = some (b - f) := by
  unfold getNetFinalState getNetState17
  rw [returnData_execExit, returnData_execMov64]
  unfold getNetState16
  exact returnData_execSetReturnData (getNetState15 b f) (b - f)

theorem balanceOff_matches_layout :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "balance" = some balanceOff := by
  native_decide

theorem feesOff_matches_layout :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "fees" = some feesOff := by
  native_decide

theorem operationsOff_matches_layout :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "operations" = some operationsOff := by
  native_decide

theorem lastValueOff_matches_layout :
    stateFieldOffset? ProofForge.IR.Examples.ValueVault.module "last_value" = some lastValueOff := by
  native_decide

end ProofForge.Backend.Solana.ValueVaultSbpfExec
