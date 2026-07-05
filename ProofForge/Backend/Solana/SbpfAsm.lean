/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Assembly Backend

Architecture: IR.Module → `Array AstNode` → sBPF assembly text (`.s`)

The AST/printer lives in `ProofForge.Backend.Solana.Asm`, account layout in
`StateLayout`, manifest generation in `Manifest`, syscalls in `Syscalls`, and
register bookkeeping in `Register`. This file owns the IR → AST lowering.

See `docs/targets/solana-sbpf-asm.md` (D-026).
-/

import ProofForge.IR.Contract
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
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

def diagnosticError (err : ProofForge.Target.Diagnostic) : LowerError := {
  message := err.render
}

/-- Reject IR modules whose portable capabilities are not in the
`solana-sbpf-asm` target profile (V-GATE-SOLANA-05). For Solana this mainly
rules out the generic `.crosscallInvoke` (Solana uses `.crosscallCpi`,
D-027) and the ZK capabilities. -/
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

/-- Extract the element type of a state declared as an array. -/
def arrayStateElementType? (stateDecls : Array StateDecl) (stateId : String) : Option ValueType :=
  match stateDecls.find? (fun s => s.id == stateId) with
  | none => none
  | some decl =>
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

def buildCtx (module : Module) (stateDataOff : Nat) : Except LowerError LowerCtx := do
  let offsets := buildStateOffsetsAtBase module stateDataOff
  return { stateFieldOffsets := offsets.map (fun f => (f.id, f.absOff)), structs := module.structs, stateDecls := module.state, locals := #[], nextLocalOffset := 8, scratchOffset := 8, nextLabel := 0, allocator := Allocator.new }

def SPL_TOKEN_ACCOUNT_DATA_SIZE : Nat := 165
def SPL_TOKEN_MINT_DATA_SIZE : Nat := 82
def CLOCK_SYSVAR_SIZE : Nat := 40

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
  if account.index == 0 then
    moduleDataSize module
  else
    extensionAccountDataSize extensions account

def accountReserveRealloc (idx accountCount : Nat) (account : AccountEntry) : Bool :=
  account.writable || idx + 1 == accountCount

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

-- ============================================================================
-- IR expression → AST nodes (result in r2, r3 as scratch)
-- ============================================================================

/-- Produce an `Inst` with dst = r2 and the given fields. -/
def res (opcode : Opcode) (src : Option Reg := none) (off : Option MemOff := none) (imm : Option Imm := none) : Inst :=
  { opcode, dst := some .r2, src, off, imm }

/-- Combine already-lowered LHS/RHS nodes for a commutative binary ALU op.
The result lands in r2. LHS is stashed to the scratch slot, RHS is evaluated
into r2, then LHS is reloaded into r3 and `op r2, r3` is applied. Order does
not matter for commutative ops. -/
def lowerBinaryCombine (lhsNodes rhsNodes : Array AstNode) (op : Opcode) (scratchOffset : Nat) : Array AstNode :=
  lhsNodes ++ #[
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchOffset), src := some .r2 }
  ] ++ rhsNodes ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num scratchOffset) },
    .instruction { opcode := op, dst := some .r2, src := some .r3 }
  ]

/-- Combine already-lowered LHS/RHS nodes for a non-commutative binary ALU op.
The result lands in r2 in `lhs op rhs` order. LHS is stashed, RHS is evaluated,
then RHS is moved to r3, LHS is reloaded into r2, and `op r2, r3` is applied. -/
def lowerOrderedBinaryCombine (lhsNodes rhsNodes : Array AstNode) (op : Opcode) (scratchOffset : Nat) : Array AstNode :=
  lhsNodes ++ #[
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchOffset), src := some .r2 }
  ] ++ rhsNodes ++ #[
    .instruction { opcode := .mov64, dst := some .r3, src := some .r2 },
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratchOffset) },
    .instruction { opcode := op, dst := some .r2, src := some .r3 }
  ]

/-- Combine already-lowered LHS/RHS nodes for an unsigned comparison that
returns a boolean 0/1 in r2. `condJmp` is `jeq/jne/jlt/jle/jgt/jge`; it jumps
to `trueLabel` when the comparison holds. The boolean temp is allocated from
the register pool (or spilled to the stack); the LHS is stashed at the caller's
scratch offset. -/
def lowerCmpCombine (lhsNodes rhsNodes : Array AstNode) (condJmp : Opcode) (trueLabel endLabel : String) (scratchOffset : Nat) (boolLoc : Loc) : Array AstNode :=
  let boolSet (v : Nat) : Array AstNode := match boolLoc with
    | .reg r => #[ .instruction { opcode := .mov64, dst := some r, imm := some (.num v) } ]
    | .spill off => #[ .instruction { opcode := .stdw, dst := some .r10, off := some (.num off), imm := some (.num v) } ]
  let boolMovToR2 : Array AstNode := match boolLoc with
    | .reg r =>
        if r == .r2 then #[]
        else #[ .instruction { opcode := .mov64, dst := some .r2, src := some r } ]
    | .spill off => #[ .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num off) } ]
  lhsNodes ++ #[
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchOffset), src := some .r2 }
  ] ++ rhsNodes ++ #[
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num scratchOffset) }
  ] ++ boolSet 0 ++ #[
    .instruction { opcode := condJmp, dst := some .r3, src := some .r2, off := some (.sym trueLabel) },
    .instruction { opcode := .ja, off := some (.sym endLabel) },
    .label trueLabel
  ] ++ boolSet 1 ++ #[
    .label endLabel
  ] ++ boolMovToR2

def assignOpcode : AssignOp → Opcode
  | .add => .add64
  | .sub => .sub64
  | .mul => .mul64
  | .div => .div64
  | .mod => .mod64
  | .bitAnd => .and64
  | .bitOr => .or64
  | .bitXor => .xor64
  | .shiftLeft => .lsh64
  | .shiftRight => .rsh64

/-- `lowerExpr` lowers an IR expr into AST nodes that compute the value in r2
and thread the lowering context so nested comparisons can mint fresh labels. -/
partial def lowerExpr (ctx : LowerCtx) (expr : IR.Expr) : Except LowerError (Array AstNode × LowerCtx) :=
  match expr with
  | .literal (.u64 n) =>
    .ok (#[ .instruction (res .mov64 (imm := some (.num n))) ], ctx)
  | .literal (.u32 n) =>
    .ok (#[ .instruction (res .mov32 (imm := some (.num n))) ], ctx)
  | .literal (.bool true) =>
    .ok (#[ .instruction (res .mov64 (imm := some (.num 1))) ], ctx)
  | .literal (.bool false) =>
    .ok (#[ .instruction (res .mov64 (imm := some (.num 0))) ], ctx)
  | .literal _ => .error { message := "unsupported literal type in Phase 1" }
  | .local name =>
    match ctx.localInfo? name with
    | some slot =>
      if slot.byteSize <= 8 then
        .ok (#[ .instruction (res .ldxdw (src := some .r10) (off := some (.num slot.offset))) ], ctx)
      else
        -- Composite local (fixed array / struct): return its stack address.
        .ok (#[
          .comment s!"local address {name}: composite {slot.byteSize} bytes",
          .instruction { opcode := .mov64, dst := some .r2, src := some .r10 },
          .instruction { opcode := .sub64, dst := some .r2, imm := some (.num slot.offset) }
        ], ctx)
    | none => .error { message := s!"unknown local: {name}" }
  | .arrayLit _ _ =>
    .error { message := "array literal must be bound directly to a local (Phase 2)" }
  | .structLit _ _ =>
    .error { message := "struct literal must be bound directly to a local (Phase 2)" }
  | .arrayGet array index => do
    let arrayName := match array with | .local name => name | _ => ""
    let elementType? := match ctx.localInfo? arrayName with
      | some { type? := some (.fixedArray element _), .. } => some element
      | _ => none
    match elementType? with
    | none => .error { message := s!"array index requires a fixed-array local; got `{arrayName}`" }
    | some elementType => do
      let elementSize := valueTypeByteSize elementType
      let (baseNodes, ctx') ← lowerExpr ctx array
      let (baseScratch, ctx') := ctx'.allocScratch
      let (idxNodes, ctx') ← lowerExpr ctx' index
      .ok (baseNodes ++ #[
        AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num baseScratch), src := some .r2 }
      ] ++ idxNodes ++ #[
        AstNode.comment "array.get: compute element address",
        AstNode.instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
        AstNode.instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
        AstNode.instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num baseScratch) },
        AstNode.instruction { opcode := .sub64, dst := some .r3, src := some .r2 },
        AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) }
      ], ctx')
  | .field base fieldName => do
    let baseName := match base with | .local name => name | _ => ""
    let typeName? := match ctx.localInfo? baseName with
      | some { type? := some (.structType name), .. } => some name
      | _ => none
    match typeName? with
    | none => .error { message := s!"field access requires a struct local; got `{baseName}`" }
    | some typeName => do
      match structFieldOffset ctx.structs typeName fieldName with
      | none => .error { message := s!"field `{fieldName}` not found in struct `{typeName}`" }
      | some fieldOff => do
        let (baseNodes, ctx') ← lowerExpr ctx base
        .ok (baseNodes ++ #[
          AstNode.comment s!"struct.field {typeName}.{fieldName}",
          AstNode.instruction { opcode := .sub64, dst := some .r2, imm := some (.num fieldOff) },
          AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r2, off := some (.num 0) }
        ], ctx')
  | .add lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerBinaryCombine ln rn .add64 scratch, ctx)
  | .sub lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerOrderedBinaryCombine ln rn .sub64 scratch, ctx)
  | .mul lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerBinaryCombine ln rn .mul64 scratch, ctx)
  | .div lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerOrderedBinaryCombine ln rn .div64 scratch, ctx)
  | .mod lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerOrderedBinaryCombine ln rn .mod64 scratch, ctx)
  | .boolAnd lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerBinaryCombine ln rn .and64 scratch, ctx)
  | .boolOr lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerBinaryCombine ln rn .or64 scratch, ctx)
  | .boolNot value => do
    -- value is a strict 0/1 boolean: bitwise NOT via xor with 1.
    let (vn, ctx) ← lowerExpr ctx value
    .ok (vn ++ #[ .instruction { opcode := .xor64, dst := some .r2, imm := some (.num 1) } ], ctx)
  | .eq lhs rhs => lowerCmp ctx lhs rhs .jeq
  | .ne lhs rhs => lowerCmp ctx lhs rhs .jne
  | .lt lhs rhs => lowerCmp ctx lhs rhs .jlt
  | .le lhs rhs => lowerCmp ctx lhs rhs .jle
  | .gt lhs rhs => lowerCmp ctx lhs rhs .jgt
  | .ge lhs rhs => lowerCmp ctx lhs rhs .jge
  | .effect (.storageScalarRead stateId) =>
    match ctx.stateAbsOff? stateId with
    | some absOff => .ok (#[ .instruction (res .ldxdw (src := some .r1) (off := some (.num absOff))) ], ctx)
    | none => .error { message := s!"unknown state: {stateId}" }
  | .effect (.storageMapGet stateId key) => do
    -- Linear search the map region: entries of (key:u64, value:u64) = 16 bytes each.
    -- key is lowered into r2; we search mapBase[i].key == r2.
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown map state: {stateId}" }
    | some mapBase =>
      let (kn, ctx') ← lowerExpr ctx key
      let (keyScratch, ctx') := ctx'.allocScratch
      let (idxScratch, ctx') := ctx'.allocScratch
      let (foundLabel, ctx') := ctx'.freshLabel
      let (notFoundLabel, ctx') := ctx'.freshLabel
      let (endLabel, ctx') := ctx'.freshLabel
      let entrySize := 16  -- key(8) + value(8)
      let maxEntries := 256  -- default capacity
      .ok (kn ++ #[
        .comment s!"solana.storage.map_get {stateId}: linear search {maxEntries} entries at base={mapBase}",
        -- Save key to scratch
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num keyScratch), src := some .r2 },
        -- r3 = index counter = 0
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num 0) },
        .label foundLabel,
        -- Check if we've exhausted the map
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num maxEntries) },
        .instruction { opcode := .jge, dst := some .r3, src := some .r4, off := some (.sym notFoundLabel) },
        -- Compute entry address: r5 = r1 + mapBase + r3 * entrySize
        .instruction { opcode := .mov64, dst := some .r5, imm := some (.num entrySize) },
        .instruction { opcode := .mul64, dst := some .r5, src := some .r3 },
        .instruction { opcode := .add64, dst := some .r5, imm := some (.num mapBase) },
        .instruction { opcode := .add64, dst := some .r5, src := some .r1 },
        -- Load entry key: r6 = *(u64*)(r5 + 0)
        .instruction { opcode := .ldxdw, dst := some .r6, src := some .r5, off := some (.num 0) },
        -- Load saved key: r7 = scratch
        .instruction { opcode := .ldxdw, dst := some .r7, src := some .r10, off := some (.num keyScratch) },
        -- Compare: if key matches, load value
        .instruction { opcode := .jne, dst := some .r6, src := some .r7, off := some (.sym notFoundLabel) },
        -- Found! Load value: r1 = *(u64*)(r5 + 8)
        .instruction { opcode := .ldxdw, dst := some .r1, src := some .r5, off := some (.num 8) },
        .instruction { opcode := .ja, off := some (.sym endLabel) },
        .label notFoundLabel,
        -- Not found (or continue): increment index, loop
        .instruction { opcode := .add64, dst := some .r3, imm := some (.num 1) },
        .instruction { opcode := .ja, off := some (.sym foundLabel) },
        .label endLabel,
        -- Result in r1; save and reload to preserve caller r1
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num idxScratch), src := some .r1 },
        .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num idxScratch) }
      ], ctx')
  | .effect (.storageArrayRead stateId index) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown array state: {stateId}" }
    | some base =>
      let elementSize :=
        match arrayStateElementType? ctx.stateDecls stateId with
        | some ty => valueTypeByteSize ty
        | none => 8
      let (idxNodes, ctx') ← lowerExpr ctx index
      .ok (idxNodes ++ #[
        .comment s!"solana.storage.array_read {stateId}",
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
        .instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
        .instruction { opcode := .add64, dst := some .r2, imm := some (.num base) },
        .instruction { opcode := .add64, dst := some .r2, src := some .r1 },
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r2, off := some (.num 0) }
      ], ctx')
  | .effect (.storageArrayStructFieldRead stateId index fieldName) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown array state: {stateId}" }
    | some base =>
      match arrayStructFieldInfo? ctx stateId fieldName with
      | none => .error { message := s!"cannot resolve field `{fieldName}` for array state `{stateId}`" }
      | some (elementSize, fieldOff) =>
        let (idxNodes, ctx') ← lowerExpr ctx index
        .ok (idxNodes ++ #[
          .comment s!"solana.storage.array_struct_field_read {stateId}.{fieldName}",
          .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
          .instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
          .instruction { opcode := .add64, dst := some .r2, imm := some (.num base) },
          .instruction { opcode := .add64, dst := some .r2, src := some .r1 },
          .instruction { opcode := .add64, dst := some .r2, imm := some (.num fieldOff) },
          .instruction { opcode := .ldxdw, dst := some .r2, src := some .r2, off := some (.num 0) }
        ], ctx')
  | .effect (.storageStructFieldRead stateId fieldName) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown struct state: {stateId}" }
    | some base =>
      match scalarStructFieldInfo? ctx stateId fieldName with
      | none => .error { message := s!"cannot resolve field `{fieldName}` for struct state `{stateId}`" }
      | some fieldOff =>
        .ok (#[
          .comment s!"solana.storage.struct_field_read {stateId}.{fieldName}",
          .instruction { opcode := .mov64, dst := some .r2, src := some .r1 },
          .instruction { opcode := .add64, dst := some .r2, imm := some (.num (base + fieldOff)) },
          .instruction { opcode := .ldxdw, dst := some .r2, src := some .r2, off := some (.num 0) }
        ], ctx)
  | .effect (.storagePathRead stateId path) =>
    if path.isEmpty then
      match ctx.stateAbsOff? stateId with
      | some absOff => .ok (#[ .instruction (res .ldxdw (src := some .r1) (off := some (.num absOff))) ], ctx)
      | none => .error { message := s!"unknown state: {stateId}" }
    else
      -- Single mapKey path: treat as storageMapGet
      match path[0]? with
      | some (ProofForge.IR.StoragePathSegment.mapKey key) => lowerExpr ctx (.effect (.storageMapGet stateId key))
      | _ => .error { message := "storage path read with non-mapKey segments not supported" }
  | .effect (.contextRead .checkpointId) =>
    let (inputPtrScratch, ctx) := ctx.allocScratch
    let (clockBuffer, ctx) := ctx.allocScratchBytes CLOCK_SYSVAR_SIZE
    .ok (#[
      .comment "solana.sysvar.clock: sol_get_clock_sysvar -> Clock.slot",
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrScratch), src := some .r1 },
      .instruction { opcode := .mov64, dst := some .r1, src := some .r10 },
      .instruction { opcode := .sub64, dst := some .r1, imm := some (.num clockBuffer) },
      .instruction { opcode := .call, imm := some (.sym sol_get_clock_sysvar) },
      .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_syscall") },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num clockBuffer) },
      .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrScratch) }
    ], ctx)
  | .effect (.contextRead .userId) =>
    -- On Solana, the "caller" maps to account[0] (the fee payer / first signer).
    -- Return the first 8 bytes of the pubkey as a u64 identifier.
    let (inputPtrScratch, ctx) := ctx.allocScratch
    .ok (#[
      .comment "solana.context.userId: read account[0] pubkey first 8 bytes as u64",
      .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrScratch) }
    ], ctx)
  | .effect (.contextRead .origin) =>
    -- tx.origin maps to account[0] on Solana (same as userId)
    let (inputPtrScratch, ctx) := ctx.allocScratch
    .ok (#[
      .comment "solana.context.origin: read account[0] pubkey first 8 bytes as u64",
      .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrScratch) }
    ], ctx)
  | .effect (.contextRead field) =>
    .error { message := s!"Solana context read `{field.name}` is not supported; userId/origin map to account[0], checkpointId maps to Clock.slot" }
  | .hashValue a b c d => do
    let (an, ctx) ← lowerExpr ctx a
    let (scratchA, ctx) := ctx.allocScratch
    let (bn, ctx) ← lowerExpr ctx b
    let (scratchB, ctx) := ctx.allocScratch
    let (cn, ctx) ← lowerExpr ctx c
    let (scratchC, ctx) := ctx.allocScratch
    let (dn, ctx) ← lowerExpr ctx d
    let (digestBuf, ctx) := ctx.allocScratchBytes 32
    let (sliceTable, ctx) := ctx.allocScratchBytes 16
    let (inputBuf, ctx) := ctx.allocScratchBytes 32
    .ok (an ++ #[
      AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchA), src := some .r2 }
    ] ++ bn ++ #[
      AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchB), src := some .r2 }
    ] ++ cn ++ #[
      AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchC), src := some .r2 }
    ] ++ dn ++ #[
      AstNode.comment "hashValue: pack four u64 words into input buffer",
      AstNode.instruction { opcode := .mov64, dst := some .r4, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r4, imm := some (.num inputBuf) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 0), src := some .r2 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratchC) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 8), src := some .r2 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratchB) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 16), src := some .r2 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratchA) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 24), src := some .r2 },
      AstNode.comment "hashValue: build SolSlice table",
      AstNode.instruction { opcode := .mov64, dst := some .r5, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r5, imm := some (.num sliceTable) },
      AstNode.instruction { opcode := .stxdw, dst := some .r5, off := some (.num 0), src := some .r4 },
      AstNode.instruction { opcode := .mov64, dst := some .r6, imm := some (.num 32) },
      AstNode.instruction { opcode := .stxdw, dst := some .r5, off := some (.num 8), src := some .r6 },
      AstNode.comment "hashValue: call sol_sha256",
      AstNode.instruction { opcode := .mov64, dst := some .r1, src := some .r5 },
      AstNode.instruction { opcode := .mov64, dst := some .r2, imm := some (.num 1) },
      AstNode.instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r3, imm := some (.num digestBuf) },
      AstNode.instruction { opcode := .call, imm := some (.sym sol_sha256) },
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num digestBuf) }
    ], ctx)
  | .hash preimage => do
    let (preNodes, ctx) ← lowerExpr ctx preimage
    let (inputBuf, ctx) := ctx.allocScratchBytes 32
    let (digestBuf, ctx) := ctx.allocScratchBytes 32
    let (sliceTable, ctx) := ctx.allocScratchBytes 16
    .ok (preNodes ++ #[
      AstNode.comment "hash: copy 32-byte preimage into input buffer",
      AstNode.instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r3, imm := some (.num inputBuf) },
      AstNode.instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r4, src := some .r10, off := some (.num (inputBuf - 8)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r3, off := some (.num 8), src := some .r4 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r4, src := some .r10, off := some (.num (inputBuf - 16)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r3, off := some (.num 16), src := some .r4 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r4, src := some .r10, off := some (.num (inputBuf - 24)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r3, off := some (.num 24), src := some .r4 },
      AstNode.comment "hash: build SolSlice table",
      AstNode.instruction { opcode := .mov64, dst := some .r5, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r5, imm := some (.num sliceTable) },
      AstNode.instruction { opcode := .stxdw, dst := some .r5, off := some (.num 0), src := some .r3 },
      AstNode.instruction { opcode := .mov64, dst := some .r6, imm := some (.num 32) },
      AstNode.instruction { opcode := .stxdw, dst := some .r5, off := some (.num 8), src := some .r6 },
      AstNode.comment "hash: call sol_sha256",
      AstNode.instruction { opcode := .mov64, dst := some .r1, src := some .r5 },
      AstNode.instruction { opcode := .mov64, dst := some .r2, imm := some (.num 1) },
      AstNode.instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r3, imm := some (.num digestBuf) },
      AstNode.instruction { opcode := .call, imm := some (.sym sol_sha256) },
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num digestBuf) }
    ], ctx)
  | .hashTwoToOne lhs rhs => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratchL, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    let (inputBuf, ctx) := ctx.allocScratchBytes 64
    let (digestBuf, ctx) := ctx.allocScratchBytes 32
    let (sliceTable, ctx) := ctx.allocScratchBytes 16
    .ok (ln ++ #[
      AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratchL), src := some .r2 }
    ] ++ rn ++ #[
      AstNode.comment "hashTwoToOne: pack right hash into input buffer+32",
      AstNode.instruction { opcode := .mov64, dst := some .r4, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r4, imm := some (.num (inputBuf - 32)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 0), src := some .r2 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num (inputBuf - 40)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 8), src := some .r5 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num (inputBuf - 48)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 16), src := some .r5 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num (inputBuf - 56)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 24), src := some .r5 },
      AstNode.comment "hashTwoToOne: pack left hash into input buffer",
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratchL) },
      AstNode.instruction { opcode := .mov64, dst := some .r4, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r4, imm := some (.num inputBuf) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 0), src := some .r2 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num (inputBuf - 8)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 8), src := some .r5 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num (inputBuf - 16)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 16), src := some .r5 },
      AstNode.instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num (inputBuf - 24)) },
      AstNode.instruction { opcode := .stxdw, dst := some .r4, off := some (.num 24), src := some .r5 },
      AstNode.comment "hashTwoToOne: build SolSlice table",
      AstNode.instruction { opcode := .mov64, dst := some .r5, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r5, imm := some (.num sliceTable) },
      AstNode.instruction { opcode := .stxdw, dst := some .r5, off := some (.num 0), src := some .r4 },
      AstNode.instruction { opcode := .mov64, dst := some .r6, imm := some (.num 64) },
      AstNode.instruction { opcode := .stxdw, dst := some .r5, off := some (.num 8), src := some .r6 },
      AstNode.comment "hashTwoToOne: call sol_sha256",
      AstNode.instruction { opcode := .mov64, dst := some .r1, src := some .r5 },
      AstNode.instruction { opcode := .mov64, dst := some .r2, imm := some (.num 1) },
      AstNode.instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r3, imm := some (.num digestBuf) },
      AstNode.instruction { opcode := .call, imm := some (.sym sol_sha256) },
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num digestBuf) }
    ], ctx)
  | .nativeValue =>
    -- On Solana, native value = lamports of account[0] (the fee payer).
    -- Account info layout: accountStart(8) + header(8) + pubkey(32) + owner_pubkey(32) + lamports(8)
    -- lamports offset for account[0] = 8 + 8 + 32 + 32 = 80
    .ok (#[
      .comment "solana.nativeValue: read account[0] lamports",
      .instruction { opcode := .ldxdw, dst := some .r1, src := some .r1, off := some (.num 80) }
    ], ctx)
  | .memoryArrayNew elementType length => do
    let elementSize := valueTypeByteSize elementType
    if elementSize == 0 then
      .error { message := s!"memoryArrayNew element type `{elementType.name}` has zero byte size" }
    let (lenNodes, ctx) ← lowerExpr ctx length
    let (lenScratch, ctx) := ctx.allocScratch
    .ok (lenNodes ++ #[
      .comment s!"memory.array.new: allocate heap array of {elementSize}-byte elements",
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num lenScratch), src := some .r2 },
      .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
      .instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
      .instruction { opcode := .add64, dst := some .r2, imm := some (.num 8) },
      .instruction { opcode := .mov64, dst := some .r1, src := some .r2 },
      .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 0) },
      .instruction { opcode := .call, imm := some (.sym sol_alloc_free_) },
      .instruction { opcode := .mov64, dst := some .r3, src := some .r0 },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num lenScratch) },
      .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 },
      .instruction { opcode := .mov64, dst := some .r2, src := some .r3 },
      .instruction { opcode := .add64, dst := some .r2, imm := some (.num 8) }
    ], ctx)
  | .memoryArrayLength array => do
    let (arrNodes, ctx) ← lowerExpr ctx array
    .ok (arrNodes ++ #[
      .comment "memory.array.length: load length from header",
      .instruction { opcode := .sub64, dst := some .r2, imm := some (.num 8) },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r2, off := some (.num 0) }
    ], ctx)
  | .memoryArrayGet array index => do
    let elementSize :=
      match array with
      | .local name =>
        match ctx.localInfo? name with
        | some { type? := some (.array element), .. } => valueTypeByteSize element
        | _ => 8
      | _ => 8
    let (arrNodes, ctx) ← lowerExpr ctx array
    let (arrScratch, ctx) := ctx.allocScratch
    let (idxNodes, ctx) ← lowerExpr ctx index
    .ok (arrNodes ++ #[
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num arrScratch), src := some .r2 }
    ] ++ idxNodes ++ #[
      .comment "memory.array.get",
      .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
      .instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
      .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num arrScratch) },
      .instruction { opcode := .add64, dst := some .r3, src := some .r2 },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) }
    ], ctx)
  | _ => .error { message := "unsupported expression in Phase 1" }
where
  lowerCmp (ctx : LowerCtx) (lhs rhs : IR.Expr) (condJmp : Opcode) : Except LowerError (Array AstNode × LowerCtx) := do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    let (trueLabel, ctx) := ctx.freshLabel
    let (endLabel, ctx) := ctx.freshLabel
    let (boolLoc, ctx) := ctx.allocLoc
    let nodes := lowerCmpCombine ln rn condJmp trueLabel endLabel scratch boolLoc
    let ctx := ctx.freeLoc boolLoc
    .ok (nodes, ctx)

/-- Emit nodes that store an array literal into a stack buffer starting at
`baseOff` (rendered as `[r10 - baseOff]`). Each element is evaluated and stored
at its fixed offset. Returns the updated context. -/
partial def lowerArrayLiteral (ctx : LowerCtx) (elementType : ValueType) (values : Array Expr) (baseOff : Nat) :
    Except LowerError (Array AstNode × LowerCtx) := do
  let elementSize := valueTypeByteSize elementType
  if elementSize == 0 then
    .error { message := s!"array literal element type `{elementType.name}` has zero byte size" }
  let mut nodes := #[AstNode.comment s!"array literal: {values.size} x {elementType.name} ({elementSize} bytes each)"]
  let mut ctx := ctx
  for value in values, i in [0:values.size] do
    let (vn, ctx') ← lowerExpr ctx value
    let elemOff := baseOff + i * elementSize
    nodes := nodes ++ vn ++ #[
      AstNode.instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
      AstNode.instruction { opcode := .sub64, dst := some .r3, imm := some (.num elemOff) },
      AstNode.instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 }
    ]
    ctx := ctx'
  .ok (nodes, ctx)

/-- Emit nodes that store a struct literal into a stack buffer starting at
`baseOff`. Field order and size come from `ctx.structs`. -/
partial def lowerStructLiteral (ctx : LowerCtx) (typeName : String) (fields : Array (String × Expr)) (baseOff : Nat) :
    Except LowerError (Array AstNode × LowerCtx) := do
  match ctx.structs.find? (fun s => s.name == typeName) with
  | none => .error { message := s!"unknown struct type: {typeName}" }
  | some _ => do
    let mut nodes := #[AstNode.comment s!"struct literal: {typeName}"]
    let mut ctx := ctx
    for (fieldName, value) in fields do
      match structFieldOffset ctx.structs typeName fieldName with
      | none => .error { message := s!"field `{fieldName}` not found in struct `{typeName}`" }
      | some fieldOff => do
        let (vn, ctx') ← lowerExpr ctx value
        let elemOff := baseOff + fieldOff
        nodes := nodes ++ vn ++ #[
          AstNode.instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
          AstNode.instruction { opcode := .sub64, dst := some .r3, imm := some (.num elemOff) },
          AstNode.instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 }
        ]
        ctx := ctx'
    .ok (nodes, ctx)

-- ============================================================================
-- IR statement → AST nodes
-- ============================================================================

partial def lowerStmt (ctx : LowerCtx) (stmt : IR.Statement) : Except LowerError (Array AstNode × LowerCtx) :=
  match stmt with
  | .letBind name ty value => do
    match value with
    | .arrayLit elementType values => do
      let off := ctx.nextLocalOffset
      let ctx' := ctx.addLocal name ty
      let (nodes, ctx'') ← lowerArrayLiteral ctx' elementType values off
      .ok (nodes, ctx'')
    | .structLit typeName fields => do
      let off := ctx.nextLocalOffset
      let ctx' := ctx.addLocal name ty
      let (nodes, ctx'') ← lowerStructLiteral ctx' typeName fields off
      .ok (nodes, ctx'')
    | _ => do
      let (vn, ctxAfterValue) ← lowerExpr ctx value
      let off := ctxAfterValue.nextLocalOffset
      let ctx' := ctxAfterValue.addLocal name ty
      .ok (vn ++ #[ .instruction { opcode := .stxdw, dst := some .r10, off := some (.num off), src := some .r2 } ], ctx')
  | .letMutBind name ty value => do
    match value with
    | .arrayLit elementType values => do
      let off := ctx.nextLocalOffset
      let ctx' := ctx.addLocal name ty
      let (nodes, ctx'') ← lowerArrayLiteral ctx' elementType values off
      .ok (nodes, ctx'')
    | .structLit typeName fields => do
      let off := ctx.nextLocalOffset
      let ctx' := ctx.addLocal name ty
      let (nodes, ctx'') ← lowerStructLiteral ctx' typeName fields off
      .ok (nodes, ctx'')
    | _ => do
      let (vn, ctxAfterValue) ← lowerExpr ctx value
      let off := ctxAfterValue.nextLocalOffset
      let ctx' := ctxAfterValue.addLocal name ty
      .ok (vn ++ #[ .instruction { opcode := .stxdw, dst := some .r10, off := some (.num off), src := some .r2 } ], ctx')
  | .assign target value =>
    match target with
    | .local name =>
      match ctx.localOffset? name with
      | some off => do
        let (vn, ctx') ← lowerExpr ctx value
        .ok (vn ++ #[ .instruction { opcode := .stxdw, dst := some .r10, off := some (.num off), src := some .r2 } ], ctx')
      | none => .error { message := s!"assign to unknown local: {name}" }
    | _ => .error { message := "assign to non-local not supported in Phase 1" }
  | .assignOp target opA value =>
    match target with
    | .local name =>
      match ctx.localOffset? name with
      | some localOff => do
        let (scratch, ctx) := ctx.allocScratch
        let (vn, ctx') ← lowerExpr ctx value
        .ok (#[
          .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num localOff) },
          .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratch), src := some .r3 }
        ] ++ vn ++ #[
          .instruction { opcode := .mov64, dst := some .r3, src := some .r2 },
          .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratch) },
          .instruction { opcode := assignOpcode opA, dst := some .r2, src := some .r3 },
          .instruction { opcode := .stxdw, dst := some .r10, off := some (.num localOff), src := some .r2 }
        ], ctx')
      | none => .error { message := s!"assignOp to unknown local: {name}" }
    | _ => .error { message := "assignOp to non-local not supported in Phase 1" }
  | .effect (.storageArrayWrite stateId index value) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown array state: {stateId}" }
    | some base => do
      let elementSize :=
        match arrayStateElementType? ctx.stateDecls stateId with
        | some ty => valueTypeByteSize ty
        | none => 8
      let (valNodes, ctx') ← lowerExpr ctx value
      let (valScratch, ctx') := ctx'.allocScratch
      let (idxNodes, ctx') ← lowerExpr ctx' index
      .ok (valNodes ++ #[
        .comment s!"solana.storage.array_write {stateId}: save value",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num valScratch), src := some .r2 }
      ] ++ idxNodes ++ #[
        .comment s!"solana.storage.array_write {stateId}: compute address and store",
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
        .instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
        .instruction { opcode := .add64, dst := some .r2, imm := some (.num base) },
        .instruction { opcode := .add64, dst := some .r2, src := some .r1 },
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num valScratch) },
        .instruction { opcode := .stxdw, dst := some .r2, off := some (.num 0), src := some .r3 }
      ], ctx')
  | .effect (.storageArrayStructFieldWrite stateId index fieldName value) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown array state: {stateId}" }
    | some base => do
      match arrayStructFieldInfo? ctx stateId fieldName with
      | none => .error { message := s!"cannot resolve field `{fieldName}` for array state `{stateId}`" }
      | some (elementSize, fieldOff) =>
        let (valNodes, ctx') ← lowerExpr ctx value
        let (valScratch, ctx') := ctx'.allocScratch
        let (idxNodes, ctx') ← lowerExpr ctx' index
        .ok (valNodes ++ #[
          .comment s!"solana.storage.array_struct_field_write {stateId}.{fieldName}: save value",
          .instruction { opcode := .stxdw, dst := some .r10, off := some (.num valScratch), src := some .r2 }
        ] ++ idxNodes ++ #[
          .comment s!"solana.storage.array_struct_field_write {stateId}.{fieldName}: compute address and store",
          .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
          .instruction { opcode := .mul64, dst := some .r2, src := some .r3 },
          .instruction { opcode := .add64, dst := some .r2, imm := some (.num base) },
          .instruction { opcode := .add64, dst := some .r2, src := some .r1 },
          .instruction { opcode := .add64, dst := some .r2, imm := some (.num fieldOff) },
          .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num valScratch) },
          .instruction { opcode := .stxdw, dst := some .r2, off := some (.num 0), src := some .r3 }
        ], ctx')
  | .effect (.storageStructFieldWrite stateId fieldName value) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown struct state: {stateId}" }
    | some base => do
      match scalarStructFieldInfo? ctx stateId fieldName with
      | none => .error { message := s!"cannot resolve field `{fieldName}` for struct state `{stateId}`" }
      | some fieldOff => do
        let (vn, ctx') ← lowerExpr ctx value
        .ok (vn ++ #[
          .comment s!"solana.storage.struct_field_write {stateId}.{fieldName}",
          .instruction { opcode := .mov64, dst := some .r3, src := some .r1 },
          .instruction { opcode := .add64, dst := some .r3, imm := some (.num (base + fieldOff)) },
          .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 }
        ], ctx')
  | .effect (.storageScalarWrite stateId value) => do
    match ctx.stateAbsOff? stateId with
    | some absOff => do
      let (vn, ctx') ← lowerExpr ctx value
      .ok (vn ++ #[ .instruction { opcode := .stxdw, dst := some .r1, off := some (.num absOff), src := some .r2 } ], ctx')
    | none => .error { message := s!"unknown state: {stateId}" }
  | .effect (.storageMapSet stateId key value) | .effect (.storageMapInsert stateId key value) => do
    -- Find matching key or empty slot, write (key, value)
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown map state: {stateId}" }
    | some mapBase => do
      let (kn, ctx') ← lowerExpr ctx key
      let (keyScratch, ctx') := ctx'.allocScratch
      let (loopLabel, ctx') := ctx'.freshLabel
      let (writeLabel, ctx') := ctx'.freshLabel
      let (endLabel, ctx') := ctx'.freshLabel
      let entrySize := 16
      let maxEntries := 256
      -- Lower value after key
      let (vn2, ctx') ← lowerExpr ctx' value
      .ok (kn ++ #[
        .comment s!"solana.storage.map_set {stateId}: find slot and write",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num keyScratch), src := some .r2 },
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num 0) },
        .label loopLabel,
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num maxEntries) },
        .instruction { opcode := .jge, dst := some .r3, src := some .r4, off := some (.sym endLabel) },
        -- Compute entry address
        .instruction { opcode := .mov64, dst := some .r5, imm := some (.num entrySize) },
        .instruction { opcode := .mul64, dst := some .r5, src := some .r3 },
        .instruction { opcode := .add64, dst := some .r5, imm := some (.num mapBase) },
        .instruction { opcode := .add64, dst := some .r5, src := some .r1 },
        -- Load entry key
        .instruction { opcode := .ldxdw, dst := some .r6, src := some .r5, off := some (.num 0) },
        .instruction { opcode := .ldxdw, dst := some .r7, src := some .r10, off := some (.num keyScratch) },
        -- If key matches or slot empty (key==0), write here
        .instruction { opcode := .jeq, dst := some .r6, src := some .r7, off := some (.sym writeLabel) },
        .instruction { opcode := .jeq, dst := some .r6, imm := some (.num 0), off := some (.sym writeLabel) },
        -- Continue searching
        .instruction { opcode := .add64, dst := some .r3, imm := some (.num 1) },
        .instruction { opcode := .ja, off := some (.sym loopLabel) },
        .label writeLabel
      ] ++ vn2 ++ #[ -- value now in r2
        -- Write key + value
        .instruction { opcode := .ldxdw, dst := some .r7, src := some .r10, off := some (.num keyScratch) },
        .instruction { opcode := .stxdw, dst := some .r5, off := some (.num 0), src := some .r7 },
        .instruction { opcode := .stxdw, dst := some .r5, off := some (.num 8), src := some .r2 },
        .label endLabel,
        .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num keyScratch) }
      ], ctx')
  | .effect (.storagePathWrite stateId path value) =>
    if path.isEmpty then
      match ctx.stateAbsOff? stateId with
      | some absOff => do
        let (vn, ctx') ← lowerExpr ctx value
        .ok (vn ++ #[ .instruction { opcode := .stxdw, dst := some .r1, off := some (.num absOff), src := some .r2 } ], ctx')
      | none => .error { message := s!"unknown state: {stateId}" }
    else
      match path[0]? with
      | some (ProofForge.IR.StoragePathSegment.mapKey key) => lowerStmt ctx (.effect (.storageMapSet stateId key value))
      | _ => .error { message := "storage path write with non-mapKey segments not supported" }
  | .effect (.storageScalarAssignOp stateId opA value) => do
    match ctx.stateAbsOff? stateId with
    | some absOff => do
      let (scratch, ctx) := ctx.allocScratch
      let (vn, ctx') ← lowerExpr ctx value
      .ok (#[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r1, off := some (.num absOff) },
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratch), src := some .r3 }
      ] ++ vn ++ #[
        .instruction { opcode := .mov64, dst := some .r3, src := some .r2 },
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num scratch) },
        .instruction { opcode := assignOpcode opA, dst := some .r2, src := some .r3 },
        .instruction { opcode := .stxdw, dst := some .r1, off := some (.num absOff), src := some .r2 }
      ], ctx')
    | none => .error { message := s!"unknown state: {stateId}" }
  | .effect (.eventEmit name fields) => do
    let mut nodes := #[.comment s!"solana.event.emit {name}: sol_log_64_ scalar fields"]
    let mut ctx := ctx
    let tag := stableEventTag name
    for field in fields, idx in [0:fields.size] do
      let (fieldName, value) := field
      let (vn, ctx') ← lowerExpr ctx value
      let (inputPtrScratch, ctx') := ctx'.allocScratch
      nodes := nodes ++ vn ++ #[
        .comment s!"solana.event.field {name}.{fieldName}: tag={tag} index={idx}",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrScratch), src := some .r1 },
        .instruction { opcode := .mov64, dst := some .r3, src := some .r2 },
        .instruction { opcode := .mov64, dst := some .r1, imm := some (.num tag) },
        .instruction { opcode := .mov64, dst := some .r2, imm := some (.num idx) },
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num 0) },
        .instruction { opcode := .mov64, dst := some .r5, imm := some (.num 0) },
        .instruction { opcode := .call, imm := some (.sym sol_log_64_) },
        .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrScratch) }
      ]
      ctx := ctx'
    .ok (nodes, ctx)
  | .effect (.eventEmitIndexed name indexedFields dataFields) => do
    -- On Solana, the indexed/data distinction is EVM-specific and has no
    -- runtime equivalent (sol_log_64_ just logs raw values). Flatten both
    -- indexed and data fields into a single ordered field list, same as
    -- non-indexed eventEmit. Indexed fields come first.
    let allFields := indexedFields ++ dataFields
    let mut nodes := #[.comment s!"solana.event.emit_indexed {name}: sol_log_64_ ({indexedFields.size} indexed + {dataFields.size} data fields flattened)"]
    let mut ctx := ctx
    let tag := stableEventTag name
    for field in allFields, idx in [0:allFields.size] do
      let (fieldName, value) := field
      let (vn, ctx') ← lowerExpr ctx value
      let (inputPtrScratch, ctx') := ctx'.allocScratch
      nodes := nodes ++ vn ++ #[
        .comment s!"solana.event.field {name}.{fieldName}: tag={tag} index={idx}",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrScratch), src := some .r1 },
        .instruction { opcode := .mov64, dst := some .r3, src := some .r2 },
        .instruction { opcode := .mov64, dst := some .r1, imm := some (.num tag) },
        .instruction { opcode := .mov64, dst := some .r2, imm := some (.num idx) },
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num 0) },
        .instruction { opcode := .mov64, dst := some .r5, imm := some (.num 0) },
        .instruction { opcode := .call, imm := some (.sym sol_log_64_) },
        .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrScratch) }
      ]
      ctx := ctx'
    .ok (nodes, ctx)
  | .assert cond _ errorRef? => do
    let (cn, ctx') ← lowerExpr ctx cond
    match errorRef? with
    | none =>
      .ok (cn ++ #[
        .comment "control.assert",
        .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "assert_fail") }
      ], ctx')
    | some ref =>
      let customError := 4294967296 + ref.assertionId.toNat
      .ok (cn ++ #[
        .comment s!"control.assert error={ref.assertionId}",
        .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 1), off := some (.sym s!"assert_ok_{ref.assertionId}") },
        .instruction { opcode := .mov64, dst := some .r0, imm := some (.num customError) },
        .instruction { opcode := .exit },
        .label s!"assert_ok_{ref.assertionId}"
      ], ctx')
  | .assertEq lhs rhs _ errorRef? => do
    let (ln, ctx') ← lowerExpr ctx lhs
    let (scratch, ctx') := ctx'.allocScratch
    let (rn, ctx') ← lowerExpr ctx' rhs
    match errorRef? with
    | none =>
      .ok (ln ++ #[
        .comment "control.assert_eq",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratch), src := some .r2 }
      ] ++ rn ++ #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num scratch) },
        .instruction { opcode := .jne, dst := some .r3, src := some .r2, off := some (.sym "assert_eq_fail") }
      ], ctx')
    | some ref =>
      let customError := 4294967296 + ref.assertionId.toNat
      .ok (ln ++ #[
        .comment s!"control.assert_eq error={ref.assertionId}",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num scratch), src := some .r2 }
      ] ++ rn ++ #[
        .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num scratch) },
        .instruction { opcode := .jeq, dst := some .r3, src := some .r2, off := some (.sym s!"assert_eq_ok_{ref.assertionId}") },
        .instruction { opcode := .mov64, dst := some .r0, imm := some (.num customError) },
        .instruction { opcode := .exit },
        .label s!"assert_eq_ok_{ref.assertionId}"
      ], ctx')
  | .ifElse cond thenBody elseBody => do
    let (cn, ctx) ← lowerExpr ctx cond
    let (elseLabel, ctx) := ctx.freshLabel
    let (endLabel, ctx) := ctx.freshLabel
    let mut nodes : Array AstNode := cn ++ #[
      .comment "control.conditional",
      .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym elseLabel) }
    ]
    let mut ctx := ctx
    for stmt in thenBody do
      let (sn, ctx') ← lowerStmt ctx stmt
      nodes := nodes.append sn
      ctx := ctx'
    nodes := nodes.push (.instruction { opcode := .ja, off := some (.sym endLabel) })
    nodes := nodes.push (.label elseLabel)
    for stmt in elseBody do
      let (sn, ctx') ← lowerStmt ctx stmt
      nodes := nodes.append sn
      ctx := ctx'
    nodes := nodes.push (.label endLabel)
    .ok (nodes, ctx)
  | .boundedFor indexName start stopExclusive body => do
    let indexOff := ctx.nextLocalOffset
    let ctx := ctx.addLocal indexName .u64
    let (loopStart, ctx) := ctx.freshLabel
    let (loopEnd, ctx) := ctx.freshLabel
    let mut nodes : Array AstNode := #[
      AstNode.comment s!"control.boundedFor {indexName} {start}..{stopExclusive}",
      AstNode.instruction { opcode := .mov64, dst := some .r2, imm := some (.num start) },
      AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num indexOff), src := some .r2 },
      AstNode.label loopStart,
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num indexOff) },
      AstNode.instruction { opcode := .mov64, dst := some .r3, imm := some (.num stopExclusive) },
      AstNode.instruction { opcode := .jge, dst := some .r2, src := some .r3, off := some (.sym loopEnd) }
    ]
    let mut ctx := ctx
    for stmt in body do
      let (sn, ctx') ← lowerStmt ctx stmt
      nodes := nodes.append sn
      ctx := ctx'
    nodes := nodes ++ #[
      AstNode.instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num indexOff) },
      AstNode.instruction { opcode := .add64, dst := some .r2, imm := some (.num 1) },
      AstNode.instruction { opcode := .stxdw, dst := some .r10, off := some (.num indexOff), src := some .r2 },
      AstNode.instruction { opcode := .ja, off := some (.sym loopStart) },
      AstNode.label loopEnd
    ]
    .ok (nodes, ctx)
  | .effect (.memoryArraySet array index value) => do
    let elementSize :=
      match array with
      | .local name =>
        match ctx.localInfo? name with
        | some { type? := some (.array element), .. } => valueTypeByteSize element
        | _ => 8
      | _ => 8
    let (arrNodes, ctx) ← lowerExpr ctx array
    let (arrScratch, ctx) := ctx.allocScratch
    let (idxNodes, ctx) ← lowerExpr ctx index
    let (idxScratch, ctx) := ctx.allocScratch
    let (valNodes, ctx) ← lowerExpr ctx value
    .ok (arrNodes ++ #[
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num arrScratch), src := some .r2 }
    ] ++ idxNodes ++ #[
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num idxScratch), src := some .r2 }
    ] ++ valNodes ++ #[
      .comment "memory.array.set",
      .instruction { opcode := .ldxdw, dst := some .r4, src := some .r10, off := some (.num idxScratch) },
      .instruction { opcode := .mov64, dst := some .r3, imm := some (.num elementSize) },
      .instruction { opcode := .mul64, dst := some .r4, src := some .r3 },
      .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num arrScratch) },
      .instruction { opcode := .add64, dst := some .r3, src := some .r4 },
      .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 }
    ], ctx)
  | .release name =>
    match ctx.localInfo? name with
    | none => .error { message := s!"release of unknown local: {name}" }
    | some slot =>
      match slot.type? with
      | some ty =>
        if isOwnedHeapBacked ty then
          .ok (#[
            .comment s!"memory.release {name}: free heap array",
            .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num slot.offset) },
            .instruction { opcode := .sub64, dst := some .r2, imm := some (.num 8) },
            .instruction { opcode := .mov64, dst := some .r1, imm := some (.num 0) },
            .instruction { opcode := .call, imm := some (.sym sol_alloc_free_) }
          ], ctx)
        else
          .error { message := s!"release expects an owned heap-backed local, got `{name}: {ty.name}`" }
      | none => .error { message := s!"release of local `{name}` with unknown type" }
  | .return value => do
    let (vn, ctx') ← lowerExpr ctx value
    .ok (vn ++ #[
      .instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
      .instruction { opcode := .sub64, dst := some .r3, imm := some (.num 8) },
      .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r2 },
      .instruction { opcode := .mov64, dst := some .r1, src := some .r3 },
      .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 8) },
      .instruction { opcode := .call, imm := some (.sym "sol_set_return_data") },
      .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
      .instruction { opcode := .exit }
    ], ctx')
  | _ => .error { message := "unsupported statement in Phase 1" }

-- ============================================================================
-- Entrypoint lowering
-- ============================================================================

def entrypointHasReturn (ep : IR.Entrypoint) : Bool :=
  ep.body.any fun stmt => match stmt with | .return _ => true | _ => false

def moduleNeedsSyscallError (module : IR.Module) : Bool :=
  module.capabilities.any (fun capability => capability == .envBlock)

def lowerProgramOwnerValidation (layout : AccountInputLayout) : Array AstNode :=
  loadCurrentProgramIdPtr .r4 .r2 ++ #[
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num 3600), src := some .r4 }
  ] ++
  inputAccountFieldPtr .r7 layout layout.ownerOff ++
  #[
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r10, off := some (.num 3600) },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 0) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 0) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 8) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 8) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 16) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 16) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
    .instruction { opcode := .ldxdw, dst := some .r5, src := some .r7, off := some (.num 24) },
    .instruction { opcode := .ldxdw, dst := some .r6, src := some .r4, off := some (.num 24) },
    .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") }
  ]

def lowerPubkeyPtrEqualityCheck (actual expected : Reg) : Array AstNode := #[
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 0) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 0) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 8) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 8) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 16) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 16) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") },
  .instruction { opcode := .ldxdw, dst := some .r5, src := some actual, off := some (.num 24) },
  .instruction { opcode := .ldxdw, dst := some .r6, src := some expected, off := some (.num 24) },
  .instruction { opcode := .jne, dst := some .r5, src := some .r6, off := some (.sym "error_owner") }
]

def lowerExecutableOwnerValidation (layout : AccountInputLayout) : Array AstNode :=
  inputAccountFieldPtr .r7 layout layout.executableOff ++ #[
    .instruction { opcode := .ldxb, dst := some .r2, src := some .r7, off := some (.num 0) },
    .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "error_owner") }
  ]

def lowerNamedOwnerValidation (layout ownerLayout : AccountInputLayout) : Array AstNode :=
  inputAccountFieldPtr .r7 layout layout.ownerOff ++
  inputAccountFieldPtr .r4 ownerLayout ownerLayout.keyOff ++
  lowerPubkeyPtrEqualityCheck .r7 .r4

def accountLayoutByName? : List AccountEntry -> List AccountInputLayout -> String ->
    Option AccountInputLayout
  | [], _, _ => none
  | _, [], _ => none
  | account :: accounts, layout :: layouts, name =>
      if account.name == name then
        some layout
      else
        accountLayoutByName? accounts layouts name

def lowerOwnerValidationFor (allAccounts : Array AccountEntry)
    (allLayouts : Array AccountInputLayout) (account : AccountEntry)
    (layout : AccountInputLayout) : Except LowerError (Array AstNode) := do
  if account.owner == "any" || account.owner.isEmpty then
    .ok #[]
  else if account.owner == "program" then
    .ok <| #[.comment s!"account.validation[{account.index}:{account.name}]: owner=program"] ++
      lowerProgramOwnerValidation layout
  else if account.owner == "executable" then
    .ok <| #[.comment s!"account.validation[{account.index}:{account.name}]: owner=executable"] ++
      lowerExecutableOwnerValidation layout
  else
    match accountLayoutByName? allAccounts.toList allLayouts.toList account.owner with
    | some ownerLayout =>
        .ok <| #[.comment s!"account.validation[{account.index}:{account.name}]: owner={account.owner}"] ++
          lowerNamedOwnerValidation layout ownerLayout
    | none =>
        .error {
          message := s!"unknown Solana owner account `{account.owner}` for account `{account.name}`"
        }

def lowerAccountValidationFor (account : AccountEntry)
    (layout : AccountInputLayout) (allAccounts : Array AccountEntry)
    (allLayouts : Array AccountInputLayout) : Except LowerError (Array AstNode) := do
  let signerCheck :=
    if account.signer then
      #[
        .comment s!"account.validation[{account.index}:{account.name}]: signer=true"
      ] ++ inputAccountFieldPtr .r7 layout layout.signerOff ++ #[
        .instruction { opcode := .ldxb, dst := some .r2, src := some .r7, off := some (.num 0) },
        .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "error_signer") }
      ]
    else
      #[]
  let writableCheck :=
    if account.writable then
      #[
        .comment s!"account.validation[{account.index}:{account.name}]: writable=true"
      ] ++ inputAccountFieldPtr .r7 layout layout.writableOff ++ #[
        .instruction { opcode := .ldxb, dst := some .r2, src := some .r7, off := some (.num 0) },
        .instruction { opcode := .jeq, dst := some .r2, imm := some (.num 0), off := some (.sym "error_not_writable") }
      ]
    else
      #[]
  let ownerCheck ← lowerOwnerValidationFor allAccounts allLayouts account layout
  .ok <| signerCheck ++ writableCheck ++ ownerCheck

/-- Account-validation prologue for the generated fixed account schema. The
owner check uses the runtime instruction-data pointer saved from entrypoint
register `r9`, so it stays correct under account-data direct mapping. -/
def lowerAccountValidation (allAccounts : Array AccountEntry)
    (allLayouts : Array AccountInputLayout) :
    List AccountEntry -> List AccountInputLayout -> Except LowerError (Array AstNode)
  | [], _ => .ok #[]
  | _, [] => .ok #[]
  | account :: accounts, layout :: layouts => do
      let head ← lowerAccountValidationFor account layout allAccounts allLayouts
      let tail ← lowerAccountValidation allAccounts allLayouts accounts layouts
      .ok <| head ++ tail

def lowerAccountValidations (accounts : Array AccountEntry)
    (layouts : Array AccountInputLayout) : Except LowerError (Array AstNode) := do
  let validation ← lowerAccountValidation accounts layouts accounts.toList layouts.toList
  .ok <| #[
    .comment "account.validation: generated account schema"
  ] ++ validation

def lowerInstructionDataLengthCheck (requiredLen : Nat) : Array AstNode :=
  if requiredLen <= 1 then
    #[]
  else
    #[
      .comment s!"instruction_data.length >= {requiredLen}"
    ] ++ loadSavedInstructionDataPtr .r3 ++ #[
      .instruction { opcode := .mov64, dst := some .r4, src := some .r3 },
      .instruction { opcode := .sub64, dst := some .r4, imm := some (.num 8) },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r4, off := some (.num 0) },
      .instruction { opcode := .jlt, dst := some .r2, imm := some (.num requiredLen), off := some (.sym "error_instruction_data") }
    ]

def lowerEntrypointParamDecoding (ctx : LowerCtx) (ep : IR.Entrypoint) :
    Except LowerError (LowerCtx × Array AstNode) := do
  let mut ctx := ctx
  let mut nodes := #[]
  let mut payloadOff := 1
  for param in ep.params do
    let (name, ty) := param
    let some byteSize := scalarParamSize? ty
      | .error { message := s!"unsupported Solana entrypoint parameter type for `{name}`: {ty.name}" }
    let some opcode := scalarParamLoadOpcode? ty
      | .error { message := s!"unsupported Solana entrypoint parameter load for `{name}`: {ty.name}" }
    let localOff := ctx.nextLocalOffset
    ctx := ctx.addLocal name ty
    nodes := nodes ++ #[
      .comment s!"entrypoint.param[{ep.name}.{name}]: {ty.name} @ instruction_data+{payloadOff}"
    ] ++ loadSavedInstructionDataPtr .r3 ++ #[
      .instruction { opcode := opcode, dst := some .r2, src := some .r3, off := some (.num payloadOff) },
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num localOff), src := some .r2 }
    ]
    payloadOff := payloadOff + byteSize
  .ok (ctx, nodes)

partial def lowerEntrypoint (ctx : LowerCtx)
    (accounts : Array AccountEntry) (accountLayouts : Array AccountInputLayout)
    (extensions : ProgramExtensions) (ep : IR.Entrypoint) :
    Except LowerError (LowerCtx × Array AstNode) := do
  let mut nodes := #[
    .label s!"sol_{ep.name}",
    .blankLine
  ]
  let accountValidationNodes ← lowerAccountValidations accounts accountLayouts
  nodes := nodes ++ accountValidationNodes
  nodes := nodes ++ lowerInstructionDataLengthCheck (instructionDataMinLen ep)
  let (ctx, paramNodes) ← lowerEntrypointParamDecoding ctx ep
  nodes := nodes ++ paramNodes
  nodes := nodes ++ lowerEntrypointActions extensions ep.name
  let mut ctx := ctx
  for stmt in ep.body do
    let (sn, ctx') ← lowerStmt ctx stmt
    nodes := nodes ++ sn
    ctx := ctx'
  if !entrypointHasReturn ep then
    nodes := nodes ++ #[
      .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 0) },
      .instruction { opcode := .exit }
    ]
  .ok (ctx, nodes)

-- ============================================================================
-- Module → AST nodes
-- ============================================================================

structure ModuleInputSchema where
  accounts : Array AccountEntry
  inputLayout : InputLayout
  deriving Inhabited

def buildModuleInputSchema (module : IR.Module) (extensions : ProgramExtensions) :
    ModuleInputSchema :=
  let instructions := buildInstructionsWithExtensions module extensions
  let accounts :=
    match instructions[0]? with
    | some instruction => instruction.accounts
    | none => buildDefaultAccounts module
  let inputLayout := computeInputLayoutWithReallocFlags (accountInputSpecs module extensions accounts)
  { accounts, inputLayout }

def buildCpiAccountBindings (accounts : Array AccountEntry)
    (layouts : Array AccountInputLayout) : Array CpiAccountBinding := Id.run do
  let mut bindings := #[]
  let mut idx := 0
  for account in accounts do
    match layouts[idx]? with
    | some layout =>
        bindings := bindings.push { name := account.name, layout }
    | none =>
        pure ()
    idx := idx + 1
  return bindings

def buildStateCpiValueBindings (module : IR.Module) (stateDataOff : Nat) : Array CpiValueBinding :=
  buildStateOffsetsAtBase module stateDataOff |>.map fun field => {
    name := field.id
    absOff := field.absOff
    byteSize := 8
    sourceKind := "state"
  }

def buildEntrypointParamCpiValueBindings (module : IR.Module) :
    Array CpiValueBinding := Id.run do
  let mut bindings := #[]
  let mut ambiguous : Array String := #[]
  for ep in module.entrypoints do
    let mut payloadOff := 1
    for param in ep.params do
      let (name, ty) := param
      match scalarParamSize? ty with
      | some byteSize =>
          let binding := {
            name := name
            absOff := payloadOff
            byteSize := byteSize
            sourceKind := "instruction param"
            relativeToInstructionData := true
          }
          if ambiguous.any (fun existing => existing == name) then
            pure ()
          else
            match bindings.find? (fun existing => existing.name == name) with
            | none => bindings := bindings.push binding
            | some existing =>
                if existing.absOff == binding.absOff then
                  pure ()
                else
                  bindings := bindings.filter (fun item => item.name != name)
                  ambiguous := ambiguous.push name
          payloadOff := payloadOff + byteSize
      | none =>
          pure ()
  return bindings

def buildCpiValueBindings (module : IR.Module) (stateDataOff : Nat) :
    Array CpiValueBinding :=
  buildStateCpiValueBindings module stateDataOff ++
  buildEntrypointParamCpiValueBindings module

def lastAccountLayout? (layouts : Array AccountInputLayout) : Option AccountInputLayout :=
  layouts[layouts.size - 1]?

def lowerInstructionDataPointerSetup (accountCount : Nat) : Array AstNode :=
  #[
    .comment "save instruction_data pointer from generated Solana input layout"
  ] ++ lowerAccountPtrTableSetup "entrypoint" accountCount ++ #[
    .instruction { opcode := .mov64, dst := some entryInstructionDataReg, src := some .r3 },
    .instruction { opcode := .add64, dst := some entryInstructionDataReg, imm := some (.num U64_SIZE) },
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num entryInstructionDataSaveOffset), src := some entryInstructionDataReg }
  ]

partial def lowerModuleCore (module : IR.Module) (extensions : ProgramExtensions) :
    Except LowerError (Array AstNode) := do
  validateCapabilities module
  let schema := buildModuleInputSchema module extensions
  let accounts := schema.accounts
  let inputLayout := schema.inputLayout
  let stateDataOff ←
    match inputLayout.accounts[0]? with
    | some accountLayout => .ok accountLayout.dataStart
    | none => .error { message := "Solana account schema must contain at least one state account" }
  let ctx ← buildCtx module stateDataOff

  let mut nodes := #[
    .comment s!"ProofForge generated sBPF — {module.name} (Phase 1)",
    .comment "Target: solana-sbpf-asm (D-026)",
    .blankLine,
    .equDecl "INSTRUCTION_DATA_LEN" inputLayout.instructionDataLenOff,
    .equDecl "INSTRUCTION_DATA" inputLayout.instructionDataOff
  ]
  for (stateId, absOff) in ctx.stateFieldOffsets do
    nodes := nodes.push (.equDecl (stateId.toUpper ++ "_DATA") absOff)

  nodes := nodes ++ #[
    .blankLine,
    .globalDecl "entrypoint",
    .blankLine,
    .label "entrypoint"
  ] ++ lowerInstructionDataPointerSetup accounts.size ++ #[
    .comment "instruction_data.length >= 1",
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num entryInstructionDataSaveOffset) },
    .instruction { opcode := .sub64, dst := some .r3, imm := some (.num 8) },
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) },
    .instruction { opcode := .jlt, dst := some .r2, imm := some (.num 1), off := some (.sym "error_instruction_data") },
    .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num entryInstructionDataSaveOffset) },
    .instruction { opcode := .ldxb, dst := some .r2, src := some .r3, off := some (.num 0) }
  ]
  let mut idx := 0
  for ep in module.entrypoints do
    nodes := nodes.push (.instruction {
      opcode := .jeq, dst := some .r2, imm := some (.num idx), off := some (.sym s!"sol_{ep.name}")
    })
    idx := idx + 1
  nodes := nodes ++ #[
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 1) },
    .instruction { opcode := .exit }
  ]

  let mut ctx := ctx
  for ep in module.entrypoints do
    nodes := nodes.push .blankLine
    let epCtx := ctx.resetLocals
    let (ctx', block) ←
      lowerEntrypoint epCtx accounts inputLayout.accounts extensions ep
    ctx := { ctx with nextLabel := ctx'.nextLabel }
    nodes := nodes ++ block

  nodes := nodes ++ #[
    .blankLine,
    .label "assert_fail",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 2) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "assert_eq_fail",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 3) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_not_writable",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 4) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_signer",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 5) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_owner",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 6) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_instruction_data",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 9) },
    .instruction { opcode := .exit },
    .blankLine,
    .label "error_pda_bump",
    .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 11) },
    .instruction { opcode := .exit }
  ]
  if moduleNeedsSyscallError module then
    nodes := nodes ++ #[
      .blankLine,
      .label "error_syscall",
      .instruction { opcode := .mov64, dst := some .r0, imm := some (.num 10) },
      .instruction { opcode := .exit }
    ]
  .ok nodes

partial def lowerModule (module : IR.Module) : Except LowerError (Array AstNode) :=
  lowerModuleCore module {}

-- ============================================================================
-- Module rendering (IR → AST → text pipeline)
-- ============================================================================

def renderModule (module : IR.Module) : Except LowerError String := do
  let nodes ← lowerModule module
  .ok (Asm.renderNodes nodes)

def lowerModuleWithPlan (module : IR.Module) (plan : ProofForge.Target.CapabilityPlan) :
    Except LowerError (Array AstNode) := do
  let extensions := ProgramExtensions.fromPlan plan
  let schema := buildModuleInputSchema module extensions
  let accountBindings := buildCpiAccountBindings schema.accounts schema.inputLayout.accounts
  let valueBindings :=
    match schema.inputLayout.accounts[0]? with
    | some accountLayout =>
        buildCpiValueBindings module accountLayout.dataStart
    | none => #[]
  let nodes ← lowerModuleCore module extensions
  .ok (nodes ++
    ProofForge.Backend.Solana.Extension.lowerProgramExtensionsWithBindings
      accountBindings valueBindings extensions)

def renderModuleWithPlan (module : IR.Module) (plan : ProofForge.Target.CapabilityPlan) :
    Except LowerError String := do
  let nodes ← lowerModuleWithPlan module plan
  .ok (Asm.renderNodes nodes)

-- ============================================================================
-- Phase 0: canned entrypoint
-- ============================================================================

def renderCannedEntrypoint : Except LowerError String :=
  .ok (String.intercalate "\n" #[
    "; ProofForge generated sBPF entrypoint (Phase 0 spike)",
    "; Target: solana-sbpf-asm (D-026)",
    "; This canned entrypoint returns success (r0 = 0) without parsing accounts.",
    "",
    ".globl entrypoint",
    "",
    "entrypoint:",
    "  mov64 r0, 0",
    "  exit",
    ""
  ].toList)

end ProofForge.Backend.Solana.SbpfAsm
