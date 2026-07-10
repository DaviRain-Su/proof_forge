/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Assembly Backend Common Lowering State

Shared metadata, lowering context, account-input sizing, and scalar parameter
helpers for the Solana sBPF assembly backend.
-/

import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Diagnostic
import ProofForge.Backend.Solana.Asm
import ProofForge.Backend.Solana.Extension
import ProofForge.Backend.Solana.StateLayout
import ProofForge.Backend.Solana.Manifest
import ProofForge.Backend.Solana.Register
import ProofForge.Backend.Solana.Syscalls

namespace ProofForge.Backend.Solana.SbpfAsm

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Register
open ProofForge.Backend.Solana.Syscalls

-- ============================================================================
-- Metadata
-- ============================================================================

def targetId : String := "solana-sbpf-asm"
def artifactKind : String := "solana-elf"
def irVersion : String := "portable-ir-v0"

-- ============================================================================
-- Error type
-- ============================================================================

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String := err.message

instance : ProofForge.Backend.Diagnostic.LoweringError LowerError where
  toDiagnostic := fun e =>
    { message := e.message, backend? := some "solana-sbpf-asm" }

def diagnosticError (err : ProofForge.Target.Diagnostic) : LowerError := {
  message := err.render
}

/-- Reject IR modules whose portable capabilities are not in the
`solana-sbpf-asm` target profile (V-GATE-SOLANA-05). Portable
`crosscall.invoke` is accepted and materialized as CPI-shaped execution
(Phase B.3). Explicit Source.Solana CPI/PDA remain extension-only (D-027).
ZK capabilities stay unsupported. -/
def validateCapabilities (module : IR.Module) : Except LowerError Unit := do
  match ProofForge.Target.resolveModule ProofForge.Target.solanaSbpfAsm module with
  | .ok _ => .ok ()
  | .error err => .error (diagnosticError err)

-- ============================================================================
-- Lowering context
-- ============================================================================

structure LocalSlot where
  name : String
  offset : Nat
  byteSize : Nat := 8
  type? : Option ValueType := none
  deriving Inhabited

structure LowerCtx where
  stateFieldOffsets : Array (String × Nat)
  structs : Array StructDecl
  stateDecls : Array StateDecl
  locals : Array LocalSlot
  nextLocalOffset : Nat
  scratchOffset : Nat
  nextLabel : Nat
  allocator : Allocator
  /-- Instruction account count from the materialized Solana schema. Used by
  portable CPI to forward the full remaining-account vector (capped at
  `MAX_PORTABLE_CPI_ACCOUNTS`). -/
  txAccountCount : Nat := 0
  /-- Account layouts for packing portable CPI PDA signer seeds. -/
  accountBindings : Array ProofForge.Backend.Solana.Extension.CpiAccountBinding := #[]
  /-- State / entry-param bindings for bump and instruction-param seeds. -/
  valueBindings : Array ProofForge.Backend.Solana.Extension.CpiValueBinding := #[]
  /-- Raw seed descriptors (`literal:…`, `account:…`, `bump:…`) for portable
  `sol_invoke_signed_c` when the module declares a signer PDA. Empty ⇒ unsigned. -/
  portableSignerSeeds : Array String := #[]
  /-- Input-account indices for selective portable CPI packing (signer /
  writable / program-owned / executable). Empty ⇒ pack 0..txAccountCount-1. -/
  portableCpiAccountIndices : Array Nat := #[]
  deriving Inhabited

def LowerCtx.localOffset? (ctx : LowerCtx) (name : String) : Option Nat :=
  ctx.locals.find? (fun slot => slot.name == name) |>.map fun slot => slot.offset

def LowerCtx.localInfo? (ctx : LowerCtx) (name : String) : Option LocalSlot :=
  ctx.locals.find? (fun slot => slot.name == name)

/-- Byte size of a `ValueType` for stack-local allocation. Returns 0 for
    dynamic or unsupported types. -/
def valueTypeByteSize (ty : ValueType) : Nat :=
  match ty with
  | .unit => 0
  | .bool | .u8 => 1
  | .u32 => 4
  | .u64 => 8
  | .u128 => 16
  | .address => 20
  | .hash => 32
  | .fixedArray element length => valueTypeByteSize element * length
  | _ => 0

/-- Compute the byte offset of a struct field within its struct layout. -/
def structFieldOffset (structs : Array StructDecl) (typeName fieldName : String) : Option Nat :=
  match structs.find? (fun s => s.name == typeName) with
  | none => none
  | some struct => Id.run do
      let mut off := 0
      for field in struct.fields do
        if field.id == fieldName then
          return some off
        off := off + valueTypeByteSize field.type
      return none

/-- Total byte size of a struct type. -/
def structByteSize (structs : Array StructDecl) (typeName : String) : Nat :=
  match structs.find? (fun s => s.name == typeName) with
  | none => 0
  | some struct =>
      struct.fields.foldl (fun acc field => acc + valueTypeByteSize field.type) 0

/-- Whether a type is backed by owned heap memory (fixed array or struct). -/
def isOwnedHeapBacked (ty : ValueType) : Bool :=
  match ty with
  | .fixedArray _ _ | .structType _ | .array _ => true
  | _ => false

/-- Extract the declared capacity of a map state. -/
def mapStateCapacity? (stateDecls : Array StateDecl) (stateId : String) : Option Nat :=
  match stateDecls.find? (fun s => s.id == stateId) with
  | some { kind := .map _ capacity, .. } => some capacity
  | _ => none

/-- Extract the declared length of a fixed-size array state. -/
def arrayStateLength? (stateDecls : Array StateDecl) (stateId : String) : Option Nat :=
  match stateDecls.find? (fun s => s.id == stateId) with
  | some { kind := .array length, .. } => some length
  | some { type := .fixedArray _ length, .. } => some length
  | _ => none

/-- Extract the element type of a state declared as an array. -/
def arrayStateElementType? (stateDecls : Array StateDecl) (stateId : String) : Option ValueType :=
  match stateDecls.find? (fun s => s.id == stateId) with
  | none => none
  | some decl =>
      match decl.kind with
      | .array _ =>
          match decl.type with
          | .fixedArray element _ => some element
          | ty => some ty
      | _ =>
          match decl.type with
          | .fixedArray element _ => some element
          | .array element => some element
          | _ => none

/-- Compute the byte offset of a field inside an array-of-struct element. -/
def arrayStructFieldInfo? (ctx : LowerCtx) (stateId fieldName : String) : Option (Nat × Nat) :=
  match arrayStateElementType? ctx.stateDecls stateId with
  | none => none
  | some (.structType typeName) =>
      match structFieldOffset ctx.structs typeName fieldName with
      | none => none
      | some fieldOff => some (structByteSize ctx.structs typeName, fieldOff)
  | some element =>
      -- Treat a scalar array as a single-field struct for uniform lowering.
      some (valueTypeByteSize element, 0)

/-- Compute the byte offset of a field inside a scalar struct state. -/
def scalarStructFieldInfo? (ctx : LowerCtx) (stateId fieldName : String) : Option Nat :=
  match ctx.stateDecls.find? (fun s => s.id == stateId) with
  | none => none
  | some decl =>
      match decl.type with
      | .structType typeName => structFieldOffset ctx.structs typeName fieldName
      | _ => none

def LowerCtx.addLocal (ctx : LowerCtx) (name : String) (ty : ValueType) : LowerCtx :=
  let byteSize := valueTypeByteSize ty
  let alignedSize := max 8 (byteSize + alignTo8 byteSize)
  let offset := ctx.nextLocalOffset
  let scratchOffset :=
    if byteSize <= 8 then
      max ctx.scratchOffset (offset + 16)
    else
      max ctx.scratchOffset (offset + alignedSize + 16)
  { ctx with
    locals := ctx.locals.push { name, offset, byteSize, type? := some ty }
    nextLocalOffset := offset + alignedSize
    scratchOffset := scratchOffset }

/-- Reserve a stack word for a temporary value. The allocation is monotonic
within an entrypoint so nested expression lowering cannot overwrite an outer
temporary that is still live while lowering the RHS. -/
def LowerCtx.allocScratch (ctx : LowerCtx) : Nat × LowerCtx :=
  let offset := ctx.scratchOffset
  (offset, { ctx with scratchOffset := offset + 8 })

/-- Reserve a contiguous stack byte buffer and return the stack offset of the
first byte. Stack offsets render as `[r10-offset]`, so a buffer of `bytes`
starts at the lowest address in the reserved range. -/
def LowerCtx.allocScratchBytes (ctx : LowerCtx) (bytes : Nat) : Nat × LowerCtx :=
  let size := max 8 (bytes + alignTo8 bytes)
  let offset := ctx.scratchOffset + size - 8
  (offset, { ctx with scratchOffset := ctx.scratchOffset + size })

/-- Allocate a temporary location. Prefer a register, then fall back to a stack
slot assigned by `allocScratch` so spill slots stay disjoint from locals. -/
def LowerCtx.allocLoc (ctx : LowerCtx) : Loc × LowerCtx :=
  let (reg?, allocator) := ctx.allocator.allocReg?
  match reg? with
  | some r => (.reg r, { ctx with allocator })
  | none =>
      let ctx := { ctx with allocator }
      let (offset, ctx) := ctx.allocScratch
      (.spill offset, ctx)

def LowerCtx.freeLoc (ctx : LowerCtx) (loc : Loc) : LowerCtx :=
  { ctx with allocator := ctx.allocator.free loc }

def LowerCtx.stateAbsOff? (ctx : LowerCtx) (id : String) : Option Nat :=
  ctx.stateFieldOffsets.find? (fun p => p.fst == id) |>.map fun p => p.snd

/-- Mint a fresh local label name and a context with the label counter bumped.
Used by nested control flow and boolean expressions so labels stay unique
across an entire module lowering. -/
def LowerCtx.freshLabel (ctx : LowerCtx) : String × LowerCtx :=
  (s!"sol_lbl_{ctx.nextLabel}", { ctx with nextLabel := ctx.nextLabel + 1 })

/-- Reset local allocation state so each entrypoint gets its own scratch/local
frame. The label counter and state-field offsets are preserved by the caller. -/
def LowerCtx.resetLocals (ctx : LowerCtx) : LowerCtx :=
  { ctx with locals := #[], nextLocalOffset := 8, scratchOffset := 8, allocator := Allocator.new }

/-- Reconstruct a `LowerCtx` from a plan seed plus the lowering-local mutable
fields reset to their entry defaults. This is the plan-driven context builder
shared by `Solana.Plan.LowerCtx.fromSeed` and the direct assembly lowering
entry. -/
def LowerCtx.fromPlanSeed
    (stateFieldOffsets : Array (String × Nat))
    (structs : Array StructDecl)
    (stateDecls : Array StateDecl)
    (txAccountCount : Nat := 0)
    (accountBindings : Array ProofForge.Backend.Solana.Extension.CpiAccountBinding := #[])
    (valueBindings : Array ProofForge.Backend.Solana.Extension.CpiValueBinding := #[])
    (portableSignerSeeds : Array String := #[])
    (portableCpiAccountIndices : Array Nat := #[]) : LowerCtx :=
  { stateFieldOffsets
    structs
    stateDecls
    locals := #[]
    nextLocalOffset := 8
    scratchOffset := 8
    nextLabel := 0
    allocator := Allocator.new
    txAccountCount
    accountBindings
    valueBindings
    portableSignerSeeds
    portableCpiAccountIndices }

/-- Raw seed descriptors for portable signed CPI: first **signer** PDA's
effective seeds (literals / account pubkeys / bump). General peer remote can
then call as a PDA authority without Source.Solana protocol CPI. -/
def portableSignerSeedsFromExtensions
    (extensions : ProofForge.Backend.Solana.Extension.ProgramExtensions)
    (entrypoint : String) : Array String :=
  let matching :=
    extensions.pdas.filter fun pda =>
      pda.signer &&
        (pda.entrypoint?.isNone || pda.entrypoint? == some entrypoint)
  match matching[0]? with
  | none => #[]
  | some pda =>
      (ProofForge.Backend.Solana.Extension.PdaDerive.effectiveSeeds pda).map
        (fun s => s.raw)

/-- Build the lowering context through the same seed shape recorded in
`SolanaModulePlan`, so the direct and plan-driven lowering paths cannot drift. -/
def buildLowerCtx (module : IR.Module) (stateDataOff : Nat) (txAccountCount : Nat := 0)
    (accountBindings : Array ProofForge.Backend.Solana.Extension.CpiAccountBinding := #[])
    (valueBindings : Array ProofForge.Backend.Solana.Extension.CpiValueBinding := #[])
    (portableCpiAccountIndices : Array Nat := #[]) :
    LowerCtx :=
  let offsets := buildStateOffsetsAtBase module stateDataOff
  LowerCtx.fromPlanSeed
    (offsets.map (fun f => (f.id, f.absOff)))
    module.structs
    module.state
    txAccountCount
    accountBindings
    valueBindings
    #[]
    portableCpiAccountIndices

def buildCtx (module : Module) (stateDataOff : Nat) (txAccountCount : Nat := 0) :
    Except LowerError LowerCtx := do
  .ok (buildLowerCtx module stateDataOff txAccountCount)

def SPL_TOKEN_ACCOUNT_DATA_SIZE : Nat := 165
def SPL_TOKEN_MINT_DATA_SIZE : Nat := 82
def CLOCK_SYSVAR_SIZE : Nat := 40
/-- Byte offset of `Clock.unix_timestamp` (i64) within the 40-byte sysvar buffer.
Layout: slot@0, epoch_start_timestamp@8, epoch@16, leader_schedule_epoch@24,
unix_timestamp@32. -/
def CLOCK_UNIX_TIMESTAMP_OFF : Nat := 32

def LOG_EVENT_TAG_MODULUS : Nat := 4294967296

def stableEventTag (name : String) : Nat :=
  (stringBytes name).foldl
    (fun acc byte => (acc * 33 + byte) % LOG_EVENT_TAG_MODULUS)
    5381

def cpiAccountName? (cpi : CpiInvoke) (idx : Nat) : Option String :=
  cpi.accounts[idx]? |>.map fun account => account.name

def cpiAccountIs? (cpi : CpiInvoke) (idx : Nat) (name : String) : Bool :=
  cpiAccountName? cpi idx == some name

def tokenCpiAccountDataSize? (cpi : CpiInvoke) (account : AccountEntry) : Option Nat :=
  match cpi.dataLayout? with
  | some "spl-token.transfer_checked" =>
      if cpiAccountIs? cpi 0 account.name || cpiAccountIs? cpi 2 account.name then
        some SPL_TOKEN_ACCOUNT_DATA_SIZE
      else if cpiAccountIs? cpi 1 account.name then
        some SPL_TOKEN_MINT_DATA_SIZE
      else
        none
  | some "spl-token.mint_to" =>
      if cpiAccountIs? cpi 0 account.name then
        some SPL_TOKEN_MINT_DATA_SIZE
      else if cpiAccountIs? cpi 1 account.name then
        some SPL_TOKEN_ACCOUNT_DATA_SIZE
      else
        none
  | some "spl-token.burn" =>
      if cpiAccountIs? cpi 0 account.name then
        some SPL_TOKEN_ACCOUNT_DATA_SIZE
      else if cpiAccountIs? cpi 1 account.name then
        some SPL_TOKEN_MINT_DATA_SIZE
      else
        none
  | some "spl-token.approve" =>
      if cpiAccountIs? cpi 0 account.name then
        some SPL_TOKEN_ACCOUNT_DATA_SIZE
      else
        none
  | some "spl-token.revoke" =>
      if cpiAccountIs? cpi 0 account.name then
        some SPL_TOKEN_ACCOUNT_DATA_SIZE
      else
        none
  | some "spl-token.close_account" =>
      if cpiAccountIs? cpi 0 account.name then
        some SPL_TOKEN_ACCOUNT_DATA_SIZE
      else
        none
  | some "spl-token.set_authority" =>
      match ProofForge.Backend.Solana.Extension.metadataValue? cpi.metadata "solana.cpi.authority_type" with
      | some "account_owner"
      | some "close_account" =>
          if cpiAccountIs? cpi 0 account.name then
            some SPL_TOKEN_ACCOUNT_DATA_SIZE
          else
            none
      | _ =>
          if cpiAccountIs? cpi 0 account.name then
            some SPL_TOKEN_MINT_DATA_SIZE
          else
            none
  | _ => none

def extensionAccountDataSize (extensions : ProgramExtensions) (account : AccountEntry) : Nat :=
  extensions.cpis.foldl
    (fun acc cpi =>
      match tokenCpiAccountDataSize? cpi account with
      | some size => max acc size
      | none => acc)
    0

def accountDataSize (module : Module) (extensions : ProgramExtensions) (account : AccountEntry) : Nat :=
  -- State is identified by IR state-id name (may not be index 0 when portable
  -- auth places `authority` first for caller/userId).
  if !module.state.isEmpty && account.name == defaultStateAccountName module then
    moduleDataSize module
  else
    extensionAccountDataSize extensions account

/-- Whether the serialized Solana input reserves `MAX_PERMITTED_DATA_INCREASE`
after this account's data.

Must stay `true` for every account: `lowerAccountScanStep` always advances by
that padding (matching the BPF loader input format). Skipping realloc for
read-only accounts desyncs `OWNER_DATA` / state offsets from the runtime scan
and drops portable auth writes into non-persisted padding (PF-P2-01 Ownable). -/
def accountReserveRealloc (_idx _accountCount : Nat) (_account : AccountEntry) : Bool :=
  true

def accountDataSizes (module : Module) (extensions : ProgramExtensions)
    (accounts : Array AccountEntry) : Array Nat :=
  accounts.map (accountDataSize module extensions)

def accountInputSpecs (module : Module) (extensions : ProgramExtensions)
    (accounts : Array AccountEntry) : Array (Nat × Bool) :=
  accounts.mapIdx fun idx account =>
    (accountDataSize module extensions account, accountReserveRealloc idx accounts.size account)

def scalarParamSize? : ValueType → Option Nat :=
  instructionParamByteSize?

def scalarParamLoadOpcode? : ValueType → Option Opcode
  | .u64 => some .ldxdw
  | .u32 => some .ldxw
  | .bool => some .ldxb
  | _ => none

end ProofForge.Backend.Solana.SbpfAsm
