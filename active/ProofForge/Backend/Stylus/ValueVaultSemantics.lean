import ProofForge.Backend.Stylus.Semantics

namespace ProofForge.Backend.Stylus.ValueVaultSemantics

open ProofForge.Backend.Stylus.Semantics

structure VaultState where
  owner : Word
  balance : Nat
  lastBlock : Nat
  deriving Repr, BEq

inductive VaultCall where
  | deposit (maxValue : Nat)
  | withdraw (amount : Nat)
  deriving Repr, BEq

inductive VaultStatus where
  | success
  | reverted (bytes : Word)
  deriving Repr, BEq

structure VaultExecution where
  state : VaultState
  status : VaultStatus
  pendingWrites : Nat := 0
  flushes : Nat := 0
  deriving Repr, BEq

def unauthorizedBytes : Word := "stylus: unauthorized".toUTF8.data
def zeroValueBytes : Word := "stylus: zero value".toUTF8.data
def excessValueBytes : Word := "stylus: value exceeds limit".toUTF8.data
def nonPayableBytes : Word := "stylus: nonpayable".toUTF8.data
def insufficientBalanceBytes : Word := "stylus: insufficient balance".toUTF8.data

private def reject (state : VaultState) (bytes : Word) : VaultExecution := {
  state
  status := .reverted bytes
  pendingWrites := 0
  flushes := 0
}

private def accept (state : VaultState) : VaultExecution := {
  state
  status := .success
  pendingWrites := 0
  flushes := 1
}

def execute (state : VaultState) (context : Context) : VaultCall -> VaultExecution
  | .deposit maxValue =>
      let value := decodeU64 context.value
      if context.sender != state.owner then reject state unauthorizedBytes
      else if value == 0 then reject state zeroValueBytes
      else if value > maxValue then reject state excessValueBytes
      else accept { state with balance := state.balance + value, lastBlock := context.blockNumber }
  | .withdraw amount =>
      let value := decodeU64 context.value
      if value != 0 then reject state nonPayableBytes
      else if context.sender != state.owner then reject state unauthorizedBytes
      else if amount > state.balance then reject state insufficientBalanceBytes
      else accept { state with balance := state.balance - amount, lastBlock := context.blockNumber }

end ProofForge.Backend.Stylus.ValueVaultSemantics
