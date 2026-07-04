/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana Account State Layout

Compute serialized account data offsets from the instruction manifest and IR
state declarations. The layout is deterministic so codegen can emit `.equ`
constants for every field.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

import ProofForge.IR.Contract

namespace ProofForge.Backend.Solana.StateLayout

open ProofForge.IR

-- ============================================================================
-- Solana serialized input constants
-- ============================================================================

def ACCOUNT_HEADER_SIZE : Nat := 8   -- is_signer + is_writable + is_executable + padding
def PUBKEY_SIZE : Nat := 32
def U64_SIZE : Nat := 8
def MAX_PERMITTED_DATA_INCREASE : Nat := 10240

def alignTo8 (n : Nat) : Nat :=
  let r := n % 8
  if r == 0 then 0 else 8 - r

structure AccountInputLayout where
  index : Nat
  accountStart : Nat
  signerOff : Nat
  writableOff : Nat
  executableOff : Nat
  keyOff : Nat
  ownerOff : Nat
  lamportsOff : Nat
  dataLenOff : Nat
  dataStart : Nat
  rentEpochOff : Nat
  nextAccountStart : Nat
  deriving Repr, Inhabited

structure InputLayout where
  accounts : Array AccountInputLayout
  instructionDataLenOff : Nat
  instructionDataOff : Nat
  deriving Repr, Inhabited

def computeAccountLayoutAt (index accountStart dataSize : Nat) (reserveRealloc : Bool := true) :
    AccountInputLayout :=
  let signerOff := accountStart + 1
  let writableOff := accountStart + 2
  let executableOff := accountStart + 3
  let keyOff := accountStart + ACCOUNT_HEADER_SIZE
  let ownerOff := keyOff + PUBKEY_SIZE
  let lamportsOff := ownerOff + PUBKEY_SIZE
  let dataLenOff := lamportsOff + U64_SIZE
  let dataStart := dataLenOff + U64_SIZE
  let reallocPadding := if reserveRealloc then MAX_PERMITTED_DATA_INCREASE else 0
  let afterPadding := dataStart + dataSize + reallocPadding
  let rentEpochOff := afterPadding
  let nextAccountStart := rentEpochOff + U64_SIZE
  {
    index
    accountStart
    signerOff
    writableOff
    executableOff
    keyOff
    ownerOff
    lamportsOff
    dataLenOff
    dataStart
    rentEpochOff
    nextAccountStart := nextAccountStart + alignTo8 nextAccountStart
  }

def computeInputLayout (accountDataSizes : Array Nat) : InputLayout := Id.run do
  let mut accounts := #[]
  let mut accountStart := U64_SIZE
  let mut idx := 0
  for dataSize in accountDataSizes do
    let layout := computeAccountLayoutAt idx accountStart dataSize
    accounts := accounts.push layout
    accountStart := layout.nextAccountStart
    idx := idx + 1
  return {
    accounts
    instructionDataLenOff := accountStart
    instructionDataOff := accountStart + U64_SIZE
  }

def computeInputLayoutWithReallocFlags (accountSpecs : Array (Nat × Bool)) : InputLayout := Id.run do
  let mut accounts := #[]
  let mut accountStart := U64_SIZE
  let mut idx := 0
  for (dataSize, reserveRealloc) in accountSpecs do
    let layout := computeAccountLayoutAt idx accountStart dataSize reserveRealloc
    accounts := accounts.push layout
    accountStart := layout.nextAccountStart
    idx := idx + 1
  return {
    accounts
    instructionDataLenOff := accountStart
    instructionDataOff := accountStart + U64_SIZE
  }

/-- Layout for a single account with `dataSize` bytes of account data.
Returns `(dataStartOffset, instructionDataStartOffset)` relative to the
beginning of the Solana input buffer. -/
def computeSingleAccountLayout (dataSize : Nat) : Nat × Nat :=
  let numAccounts := U64_SIZE
  let dataStart := numAccounts + ACCOUNT_HEADER_SIZE + PUBKEY_SIZE + PUBKEY_SIZE + U64_SIZE + U64_SIZE
  let afterPadding := dataStart + dataSize + MAX_PERMITTED_DATA_INCREASE
  let rentEpochEnd := afterPadding + U64_SIZE
  let instrDataLenOff := rentEpochEnd + alignTo8 rentEpochEnd
  let instrDataStart := instrDataLenOff + U64_SIZE
  (dataStart, instrDataStart)

/-- Compute the total account data size needed for all IR state variables.
    Scalar state occupies 8 bytes. Map state occupies `capacity × 16` bytes
    (8-byte key + 8-byte value per entry). Array state occupies `length × 8`. -/
def moduleDataSize (module : Module) : Nat :=
  module.state.foldl (fun acc state =>
    match state.kind with
    | .scalar => acc + 8
    | .map _ capacity => acc + capacity * 16
    | .array length => acc + length * 8
  ) 0

/-- Map entry layout: key (8 bytes) + value (8 bytes) = 16 bytes per entry. -/
def MAP_ENTRY_SIZE : Nat := 16
def MAP_KEY_OFFSET : Nat := 0
def MAP_VALUE_OFFSET : Nat := 8

/-- Compute the byte size of a single state declaration in account data. -/
def stateDeclSize (state : StateDecl) : Nat :=
  match state.kind with
  | .scalar => 8
  | .map _ capacity => capacity * MAP_ENTRY_SIZE
  | .array length => length * 8

-- ============================================================================
-- Per-module field offsets
-- ============================================================================

structure StateField where
  id : String
  absOff : Nat
  deriving Repr, Inhabited

/-- Build a flat list of absolute account-data offsets for every state field.
    Scalar state: 8 bytes. Map/array state: variable size (see stateDeclSize). -/
def buildStateOffsetsAtBase (module : Module) (acctDataOff : Nat) : Array StateField := Id.run do
  let mut offsets := #[]
  let mut fieldOff := 0
  for state in module.state do
    offsets := offsets.push { id := state.id, absOff := acctDataOff + fieldOff }
    fieldOff := fieldOff + stateDeclSize state
  return offsets

/-- Build a flat list of absolute account-data offsets for every state field
in the module. Phase 1 assumes all state lives in account 0. -/
def buildStateOffsets (module : Module) : Array StateField := Id.run do
  let dataSize := moduleDataSize module
  let (acctDataOff, _) := computeSingleAccountLayout dataSize
  return buildStateOffsetsAtBase module acctDataOff

end ProofForge.Backend.Solana.StateLayout
