import ProofForge.Backend.Solana.Extension.Common
import ProofForge.Backend.Solana.SbpfInterpreter

/-! Runtime regression for Solana's duplicate-account input encoding.

The loader serializes a repeated account as an eight-byte duplicate record, not
as another full account. The generated account-pointer scan must resolve that
record through an earlier logical account while keeping the serialized cursor
aligned for later unique accounts and instruction data.
-/

namespace ProofForge.Tests.SolanaDuplicateAccounts

open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.SbpfInterpreter
open ProofForge.Backend.Solana.StateLayout

def firstAccount : AccountInputLayout :=
  computeAccountLayoutAt 0 U64_SIZE 0

def duplicateStart : Nat := firstAccount.nextAccountStart
def thirdAccountStart : Nat := duplicateStart + U64_SIZE

def thirdAccount : AccountInputLayout :=
  computeAccountLayoutAt 2 thirdAccountStart 0

def instructionDataLenStart : Nat := thirdAccount.nextAccountStart

def secondUniqueAccount : AccountInputLayout :=
  computeAccountLayoutAt 1 duplicateStart 0

def twoAccountInstructionDataLenStart : Nat :=
  secondUniqueAccount.nextAccountStart

def duplicateInputMemory : Memory :=
  Memory.write
    (Memory.write
      (Memory.write
        (Memory.write
          (Memory.write
            (Memory.write #[] 0 3)
            U64_SIZE 0xff)
          firstAccount.dataLenOff 0)
        duplicateStart 0)
      thirdAccountStart 0xff)
    thirdAccount.dataLenOff 0

def scanNodes : Array AstNode :=
  lowerAccountPtrTableSetup "duplicate_test" 3 ++ #[
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
    .instruction { opcode := .exit },
    .label "error_duplicate_account",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 13) },
    .instruction { opcode := .exit },
    .label "error_account_count",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 14) },
    .instruction { opcode := .exit }
  ]

def twoUniqueInputMemory : Memory :=
  Memory.write
    (Memory.write
      (Memory.write
        (Memory.write
          (Memory.write #[] 0 2)
          U64_SIZE 0xff)
        firstAccount.dataLenOff 0)
      duplicateStart 0xff)
    secondUniqueAccount.dataLenOff 0

def runScanWith (memory : Memory) : Except String SbpfState :=
  run (collectProgram scanNodes) defaultFuel {
    regs := regSet (regSet emptyRegs .r1 inputBase) .r10 stackBase
    memory
  }

def runScan : Except String SbpfState :=
  runScanWith duplicateInputMemory

def pointerSlot (index : Nat) : Nat :=
  stackBase - accountPtrTableOffset + index * U64_SIZE

def checkDuplicateScan : IO Bool := do
  match runScan with
  | .error err =>
      IO.eprintln s!"solana-duplicate-accounts: interpreter failed: {err}"
      return false
  | .ok state =>
      let firstPtr := state.memory.read (pointerSlot 0)
      let duplicatePtr := state.memory.read (pointerSlot 1)
      let thirdPtr := state.memory.read (pointerSlot 2)
      let cursor := regGet state.regs .r3
      if firstPtr != U64_SIZE then
        IO.eprintln s!"solana-duplicate-accounts: account 0 pointer {firstPtr}, expected {U64_SIZE}"
        return false
      if duplicatePtr != U64_SIZE then
        IO.eprintln s!"solana-duplicate-accounts: duplicate pointer {duplicatePtr}, expected {U64_SIZE}"
        return false
      if thirdPtr != thirdAccountStart then
        IO.eprintln s!"solana-duplicate-accounts: account 2 pointer {thirdPtr}, expected {thirdAccountStart}"
        return false
      if cursor != instructionDataLenStart then
        IO.eprintln s!"solana-duplicate-accounts: instruction-data cursor {cursor}, expected {instructionDataLenStart}"
        return false
      return true

def checkInvalidDuplicateRejected : IO Bool := do
  let invalidMemory := Memory.write duplicateInputMemory duplicateStart 1
  match runScanWith invalidMemory with
  | .error err =>
      IO.eprintln s!"solana-duplicate-accounts: invalid-index interpreter failed: {err}"
      return false
  | .ok state =>
      if state.entryR0 != 13 then
        IO.eprintln s!"solana-duplicate-accounts: invalid duplicate exited with {state.entryR0}, expected 13"
        return false
      return true

def checkRuntimeAccountCount : IO Bool := do
  match runScanWith twoUniqueInputMemory with
  | .error err =>
      IO.eprintln s!"solana-duplicate-accounts: runtime-count interpreter failed: {err}"
      return false
  | .ok state =>
      let cursor := regGet state.regs .r3
      if cursor != twoAccountInstructionDataLenStart then
        IO.eprintln s!"solana-duplicate-accounts: two-account cursor {cursor}, expected {twoAccountInstructionDataLenStart}"
        return false
      return true

end ProofForge.Tests.SolanaDuplicateAccounts

def main : IO UInt32 := do
  let decoded ← ProofForge.Tests.SolanaDuplicateAccounts.checkDuplicateScan
  let rejected ← ProofForge.Tests.SolanaDuplicateAccounts.checkInvalidDuplicateRejected
  let runtimeCount ← ProofForge.Tests.SolanaDuplicateAccounts.checkRuntimeAccountCount
  if decoded && rejected && runtimeCount then
    IO.println "solana-duplicate-accounts: alias decoded, invalid index rejected, runtime count honored"
    return 0
  else
    return 1
