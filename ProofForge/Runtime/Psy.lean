/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Lean Psy/DPN SDK

This module is the first SDK surface for the `psy-dpn` ZK circuit target. The
extern functions are target intrinsics for future Psy source generation; they do
not have a native C/Zig runtime implementation.
-/
module

prelude
public import Init
public import Init.Prelude
public import Init.Data.Bool
public import Init.Data.Nat
public import Init.Data.UInt
public import Init.System.IO

public section

namespace Lean.Psy

/-! ## Primitive types -/

/-- Psy field element. The first SDK model keeps this as `Nat`; the Psy backend
will validate target-specific field bounds before source generation. -/
abbrev Felt := Nat

/-- Psy `u32` value. -/
abbrev U32 := UInt32

/-- Psy hash value, matching the common `[Felt; 4]` shape in `.psy` examples. -/
structure Hash where
  f0 : Felt
  f1 : Felt
  f2 : Felt
  f3 : Felt
  deriving BEq, Inhabited, Repr

namespace Hash

def zero : Hash := { f0 := 0, f1 := 0, f2 := 0, f3 := 0 }

def scalar (value : Felt) : Hash := { zero with f0 := value }

def get (hash : Hash) (index : Nat) : Felt :=
  match index with
  | 0 => hash.f0
  | 1 => hash.f1
  | 2 => hash.f2
  | 3 => hash.f3
  | _ => 0

def set (hash : Hash) (index : Nat) (value : Felt) : Hash :=
  match index with
  | 0 => { hash with f0 := value }
  | 1 => { hash with f1 := value }
  | 2 => { hash with f2 := value }
  | 3 => { hash with f3 := value }
  | _ => hash

end Hash

/-! ## Context intrinsics -/

@[extern "lean_psy_get_user_id"] opaque getUserId : IO Felt
@[extern "lean_psy_get_contract_id"] opaque getContractId : IO Felt
@[extern "lean_psy_get_caller_contract_id"] opaque getCallerContractId : IO Felt
@[extern "lean_psy_get_checkpoint_id"] opaque getCheckpointId : IO Felt
@[extern "lean_psy_get_last_nonce"] opaque getLastNonce : IO Felt
@[extern "lean_psy_get_user_public_key_hash"] opaque getUserPublicKeyHash : IO Hash
@[extern "lean_psy_get_session_proof_tree_root"] opaque getSessionProofTreeRoot : IO Hash

@[extern "lean_psy_get_checkpoint_user_tree_root"] opaque getCheckpointUserTreeRoot (checkpointId : Felt) : IO Hash
@[extern "lean_psy_get_checkpoint_contract_tree_root"] opaque getCheckpointContractTreeRoot (checkpointId : Felt) : IO Hash
@[extern "lean_psy_get_checkpoint_deposit_tree_root"] opaque getCheckpointDepositTreeRoot (checkpointId : Felt) : IO Hash
@[extern "lean_psy_get_checkpoint_withdrawal_tree_root"] opaque getCheckpointWithdrawalTreeRoot (checkpointId : Felt) : IO Hash

namespace Context

@[inline] def userId : IO Felt := getUserId
@[inline] def contractId : IO Felt := getContractId
@[inline] def callerContractId : IO Felt := getCallerContractId
@[inline] def checkpointId : IO Felt := getCheckpointId
@[inline] def lastNonce : IO Felt := getLastNonce
@[inline] def userPublicKeyHash : IO Hash := getUserPublicKeyHash
@[inline] def sessionProofTreeRoot : IO Hash := getSessionProofTreeRoot

end Context

/-! ## Contract metadata -/

structure ContractMetadata where
  contractId : Felt
  userId : Felt
  deriving BEq, Inhabited, Repr

namespace ContractMetadata

def current : IO ContractMetadata := do
  pure {
    contractId := (← getContractId)
    userId := (← getUserId)
  }

def forUser (userId : Felt) : IO ContractMetadata := do
  pure {
    contractId := (← getContractId)
    userId := userId
  }

def forContractUser (contractId userId : Felt) : ContractMetadata := {
  contractId := contractId
  userId := userId
}

end ContractMetadata

/-! ## State and storage intrinsics -/

@[extern "lean_psy_get_state_hash_at"] opaque getStateHashAt (slotIndex : Felt) : IO Hash
@[extern "lean_psy_set_state_hash_at"] opaque setStateHashAt (slotIndex : Felt) (newValue : Hash) : IO Hash
@[extern "lean_psy_get_other_contract_state_hash_at"] opaque getOtherContractStateHashAt
  (contractStateTreeHeight contractId slotIndex : Felt) : IO Hash
@[extern "lean_psy_get_other_user_contract_state_hash_at"] opaque getOtherUserContractStateHashAt
  (contractStateTreeHeight userId contractId slotIndex : Felt) : IO Hash

@[extern "lean_psy_imt_get"] opaque imtGet (key : Hash) (baseOffset capacity : Felt) : IO Hash
@[extern "lean_psy_imt_set"] opaque imtSet (key newValue : Hash) (baseOffset capacity : Felt) : IO Hash
@[extern "lean_psy_imt_contains"] opaque imtContains (key : Hash) (baseOffset capacity : Felt) : IO Bool
@[extern "lean_psy_imt_get_other_user"] opaque imtGetOtherUser
  (contractStateTreeHeight userId contractId : Felt) (key : Hash) (baseOffset capacity : Felt) : IO Hash
@[extern "lean_psy_imt_contains_other_user"] opaque imtContainsOtherUser
  (contractStateTreeHeight userId contractId : Felt) (key : Hash) (baseOffset capacity : Felt) : IO Bool

namespace Storage

/-- A scalar field backed by a Psy state slot. -/
structure Var (α : Type) where
  slot : Felt
  deriving Repr

namespace Var

@[inline] def ofSlot (slot : Felt) : Var α := { slot := slot }

@[inline] def readHash (var : Var Hash) : IO Hash :=
  getStateHashAt var.slot

@[inline] def writeHash (var : Var Hash) (value : Hash) : IO Unit := do
  let _ ← setStateHashAt var.slot value
  pure ()

@[inline] def readFelt (var : Var Felt) : IO Felt := do
  pure (Hash.get (← getStateHashAt var.slot) 0)

@[inline] def writeFelt (var : Var Felt) (value : Felt) : IO Unit := do
  let _ ← setStateHashAt var.slot (Hash.scalar value)
  pure ()

end Var

/-- Fixed-capacity map backed by Psy IMT-style storage. -/
structure Map (κ : Type) (α : Type) where
  baseOffset : Felt
  capacity : Felt
  deriving Repr

namespace Map

@[inline] def ofOffset (baseOffset capacity : Felt) : Map κ α := {
  baseOffset := baseOffset
  capacity := capacity
}

@[inline] def getHash (map : Map Hash Hash) (key : Hash) : IO Hash :=
  imtGet key map.baseOffset map.capacity

@[inline] def setHash (map : Map Hash Hash) (key value : Hash) : IO Unit := do
  let _ ← imtSet key value map.baseOffset map.capacity
  pure ()

@[inline] def containsHash (map : Map Hash Hash) (key : Hash) : IO Bool :=
  imtContains key map.baseOffset map.capacity

end Map

end Storage

/-! ## Hash and crypto intrinsics -/

@[extern "lean_psy_hash"] opaque hash (value : Hash) : IO Hash
@[extern "lean_psy_hash_two_to_one"] opaque hashTwoToOne (lhs rhs : Hash) : IO Hash
@[extern "lean_psy_keccak256_hash"] opaque keccak256Hash (value : Hash) : IO Hash

/-! ## Cross-contract invocation intrinsics -/

@[extern "lean_psy_invoke_deferred0"] opaque invokeDeferred0 (contractId methodId : Felt) : IO Unit
@[extern "lean_psy_invoke_deferred1"] opaque invokeDeferred1 (contractId methodId arg0 : Felt) : IO Unit
@[extern "lean_psy_invoke_deferred2"] opaque invokeDeferred2 (contractId methodId arg0 arg1 : Felt) : IO Unit
@[extern "lean_psy_invoke_deferred3"] opaque invokeDeferred3 (contractId methodId arg0 arg1 arg2 : Felt) : IO Unit
@[extern "lean_psy_invoke_deferred4"] opaque invokeDeferred4 (contractId methodId arg0 arg1 arg2 arg3 : Felt) : IO Unit

namespace Invoke

@[inline] def deferred0 := invokeDeferred0
@[inline] def deferred1 := invokeDeferred1
@[inline] def deferred2 := invokeDeferred2
@[inline] def deferred3 := invokeDeferred3
@[inline] def deferred4 := invokeDeferred4

end Invoke

/-! ## Test-only state helper -/

@[extern "lean_psy_clear_entire_tree"] opaque clearEntireTree : IO Unit

end Lean.Psy

