/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Expression Lowering

Lowering from portable IR expressions to Solana sBPF assembly AST nodes.
-/

import ProofForge.Backend.Solana.SbpfAsm.Common
import ProofForge.Backend.Solana.PortableCrosscall

namespace ProofForge.Backend.Solana.SbpfAsm

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.PortableCrosscall
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Register
open ProofForge.Backend.Solana.Syscalls

-- ============================================================================
-- IR expression → AST nodes (result in r2, r3 as scratch)
-- ============================================================================

/-- Produce an `Inst` with dst = r2 and the given fields. -/
def res (opcode : Opcode) (src : Option Reg := none) (off : Option MemOff := none) (imm : Option Imm := none) : Inst :=
  { opcode, dst := some .r2, src, off, imm }

/-- Lower account[0] full 32-byte pubkey → `sol_sha256` → portable u64 handle
(digest LE word 0). Shared by `userId` / `origin`. Returns nodes + updated ctx. -/
def lowerAccount0PubkeyDigestU64 (ctx : LowerCtx) (label : String) :
    Array AstNode × LowerCtx :=
  let (inputPtrSave, ctx) := ctx.allocScratch
  let (inputBuf, ctx) := ctx.allocScratchBytes 32
  let (digestBuf, ctx) := ctx.allocScratchBytes 32
  let (sliceTable, ctx) := ctx.allocScratchBytes 16
  (#[
    .comment s!"solana.context.{label}: sha256(account[0] full 32-byte pubkey) → u64-le digest[0..8]",
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrSave), src := some .r1 },
    .instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
    .instruction { opcode := .sub64, dst := some .r3, imm := some (.num inputBuf) },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r1, off := some (.num 16) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r4 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r1, off := some (.num 24) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 8), src := some .r4 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r1, off := some (.num 32) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 16), src := some .r4 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r1, off := some (.num 40) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 24), src := some .r4 },
    .instruction { opcode := .mov64, dst := some .r5, src := some .r10 },
    .instruction { opcode := .sub64, dst := some .r5, imm := some (.num sliceTable) },
    .instruction { opcode := .stxdw, dst := some .r5, off := some (.num 0), src := some .r3 },
    .instruction { opcode := .mov64, dst := some .r6, imm := some (.num 32) },
    .instruction { opcode := .stxdw, dst := some .r5, off := some (.num 8), src := some .r6 },
    .instruction { opcode := .mov64, dst := some .r1, src := some .r5 },
    .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 1) },
    .instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
    .instruction { opcode := .sub64, dst := some .r3, imm := some (.num digestBuf) },
    .instruction { opcode := .call, imm := some (.sym sol_sha256) },
    .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_syscall") },
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num digestBuf) },
    .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrSave) }
  ], ctx)

/-- Lower current program id (32-byte pubkey after instruction_data) →
`sol_sha256` → portable u64 limb0. Matches OwnableHash / userIdHash product
convention so `contextRead.contractId` is a HostEnv selfAddress path. -/
def lowerProgramIdDigestU64 (ctx : LowerCtx) (label : String) :
    Array AstNode × LowerCtx :=
  let (inputPtrSave, ctx) := ctx.allocScratch
  let (inputBuf, ctx) := ctx.allocScratchBytes 32
  let (digestBuf, ctx) := ctx.allocScratchBytes 32
  let (sliceTable, ctx) := ctx.allocScratchBytes 16
  (#[
    .comment s!"solana.context.{label}: sha256(program_id full 32-byte pubkey) → u64-le digest[0..8]",
    .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrSave), src := some .r1 }
  ] ++ loadCurrentProgramIdPtr .r7 .r3 ++ #[
    .instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
    .instruction { opcode := .sub64, dst := some .r3, imm := some (.num inputBuf) },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r7, off := some (.num 0) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 0), src := some .r4 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r7, off := some (.num 8) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 8), src := some .r4 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r7, off := some (.num 16) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 16), src := some .r4 },
    .instruction { opcode := .ldxdw, dst := some .r4, src := some .r7, off := some (.num 24) },
    .instruction { opcode := .stxdw, dst := some .r3, off := some (.num 24), src := some .r4 },
    .instruction { opcode := .mov64, dst := some .r5, src := some .r10 },
    .instruction { opcode := .sub64, dst := some .r5, imm := some (.num sliceTable) },
    .instruction { opcode := .stxdw, dst := some .r5, off := some (.num 0), src := some .r3 },
    .instruction { opcode := .mov64, dst := some .r6, imm := some (.num 32) },
    .instruction { opcode := .stxdw, dst := some .r5, off := some (.num 8), src := some .r6 },
    .instruction { opcode := .mov64, dst := some .r1, src := some .r5 },
    .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 1) },
    .instruction { opcode := .mov64, dst := some .r3, src := some .r10 },
    .instruction { opcode := .sub64, dst := some .r3, imm := some (.num digestBuf) },
    .instruction { opcode := .call, imm := some (.sym sol_sha256) },
    .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_syscall") },
    .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num digestBuf) },
    .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrSave) }
  ], ctx)

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
  -- Portable identity/account handles (NEAR string-pool indices, Solana account
  -- indices, EVM address words) lower as u64 immediates on Solana.
  | .literal (.address n) =>
    .ok (#[
      .comment s!"portable address handle → u64 account index {n}",
      .instruction (res .mov64 (imm := some (.num n)))
    ], ctx)
  -- Hash literal: Phase-1 product path uses limb0 (word `a`) as the portable
  -- Hash handle, matching userIdHash / storageScalarRead limb0 convention.
  -- Full four-limb stack buffer materialization is deferred; zero-hash
  -- (`hash4 0 0 0 0`) for OwnableHash renounce/init is the primary consumer.
  | .literal (.hash4 a _b _c _d) =>
    .ok (#[
      .comment s!"hash4 literal → limb0 handle {a} (Phase-1 Hash as u64-le word0)",
      .instruction (res .mov64 (imm := some (.num a)))
    ], ctx)
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
  | .add lhs rhs _ => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerBinaryCombine ln rn .add64 scratch, ctx)
  | .sub lhs rhs _ => do
    let (ln, ctx) ← lowerExpr ctx lhs
    let (scratch, ctx) := ctx.allocScratch
    let (rn, ctx) ← lowerExpr ctx rhs
    .ok (lowerOrderedBinaryCombine ln rn .sub64 scratch, ctx)
  | .mul lhs rhs _ => do
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
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown map state: {stateId}" }
    | some mapBase =>
      let maxEntries ←
        match mapStateCapacity? ctx.stateDecls stateId with
        | some capacity => .ok capacity
        | none => .error { message := s!"state `{stateId}` is not a map state" }
      let (kn, ctx') ← lowerExpr ctx key
      let (keyScratch, ctx') := ctx'.allocScratch
      let (resultScratch, ctx') := ctx'.allocScratch
      let (loopLabel, ctx') := ctx'.freshLabel
      let (continueLabel, ctx') := ctx'.freshLabel
      let (missLabel, ctx') := ctx'.freshLabel
      let (endLabel, ctx') := ctx'.freshLabel
      let entrySize := 16
      .ok (kn ++ #[
        .comment s!"solana.storage.map_get {stateId}: linear search {maxEntries} entries at base={mapBase}",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num keyScratch), src := some .r2 },
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num 0) },
        .label loopLabel,
        .instruction { opcode := .mov64, dst := some .r4, imm := some (.num maxEntries) },
        .instruction { opcode := .jge, dst := some .r3, src := some .r4, off := some (.sym missLabel) },
        .instruction { opcode := .mov64, dst := some .r5, imm := some (.num entrySize) },
        .instruction { opcode := .mul64, dst := some .r5, src := some .r3 },
        .instruction { opcode := .add64, dst := some .r5, imm := some (.num mapBase) },
        .instruction { opcode := .add64, dst := some .r5, src := some .r1 },
        .instruction { opcode := .ldxdw, dst := some .r6, src := some .r5, off := some (.num 0) },
        .instruction { opcode := .ldxdw, dst := some .r7, src := some .r10, off := some (.num keyScratch) },
        .instruction { opcode := .jne, dst := some .r6, src := some .r7, off := some (.sym continueLabel) },
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r5, off := some (.num 8) },
        .instruction { opcode := .ja, off := some (.sym endLabel) },
        .label continueLabel,
        .instruction { opcode := .add64, dst := some .r3, imm := some (.num 1) },
        .instruction { opcode := .ja, off := some (.sym loopLabel) },
        .label missLabel,
        .instruction { opcode := .mov64, dst := some .r2, imm := some (.num 0) },
        .label endLabel,
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num resultScratch), src := some .r2 },
        .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num resultScratch) }
      ], ctx')
  | .effect (.storageArrayRead stateId index) => do
    match ctx.stateAbsOff? stateId with
    | none => .error { message := s!"unknown array state: {stateId}" }
    | some base =>
      let length ←
        match arrayStateLength? ctx.stateDecls stateId with
        | some length => .ok length
        | none => .error { message := s!"state `{stateId}` is not a fixed array state" }
      let elementSize ←
        match arrayStateElementType? ctx.stateDecls stateId with
        | some ty => .ok (valueTypeByteSize ty)
        | none => .error { message := s!"cannot resolve element type for array state `{stateId}`" }
      let (idxNodes, ctx') ← lowerExpr ctx index
      .ok (idxNodes ++ #[
        .comment s!"solana.storage.array_read {stateId}",
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num length) },
        .instruction { opcode := .jge, dst := some .r2, src := some .r3, off := some (.sym "error_array_bounds") },
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
      let length ←
        match arrayStateLength? ctx.stateDecls stateId with
        | some length => .ok length
        | none => .error { message := s!"state `{stateId}` is not a fixed array state" }
      match arrayStructFieldInfo? ctx stateId fieldName with
      | none => .error { message := s!"cannot resolve field `{fieldName}` for array state `{stateId}`" }
      | some (elementSize, fieldOff) =>
        let (idxNodes, ctx') ← lowerExpr ctx index
        .ok (idxNodes ++ #[
          .comment s!"solana.storage.array_struct_field_read {stateId}.{fieldName}",
          .instruction { opcode := .mov64, dst := some .r3, imm := some (.num length) },
          .instruction { opcode := .jge, dst := some .r2, src := some .r3, off := some (.sym "error_array_bounds") },
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
  | .effect (.contextRead .timestamp) =>
    -- Same Clock sysvar fill as checkpointId; load unix_timestamp (i64@+32) as u64.
    let (inputPtrScratch, ctx) := ctx.allocScratch
    let (clockBuffer, ctx) := ctx.allocScratchBytes CLOCK_SYSVAR_SIZE
    let tsOff := clockBuffer - CLOCK_UNIX_TIMESTAMP_OFF
    .ok (#[
      .comment "solana.sysvar.clock: sol_get_clock_sysvar -> Clock.unix_timestamp",
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrScratch), src := some .r1 },
      .instruction { opcode := .mov64, dst := some .r1, src := some .r10 },
      .instruction { opcode := .sub64, dst := some .r1, imm := some (.num clockBuffer) },
      .instruction { opcode := .call, imm := some (.sym sol_get_clock_sysvar) },
      .instruction { opcode := .jne, dst := some .r0, imm := some (.num 0), off := some (.sym "error_syscall") },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r10, off := some (.num tsOff) },
      .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrScratch) }
    ], ctx)
  | .effect (.contextRead .userId) =>
      let (nodes, ctx) := lowerAccount0PubkeyDigestU64 ctx "userId"
      .ok (nodes, ctx)
  | .effect (.contextRead .origin) =>
      let (nodes, ctx) := lowerAccount0PubkeyDigestU64 ctx "origin"
      .ok (nodes, ctx)
  | .effect (.contextRead .userIdHash) =>
      -- Full 32-byte identity digest left at digest buffer; r2 holds limb0 and
      -- subsequent limbs are reloaded by hash-typed consumers from the buffer
      -- when they treat the result as a stack-backed hash (same limb0 convention
      -- as other Solana hash lowers). Product: full-pubkey identity for hash owner.
      let (nodes, ctx) := lowerAccount0PubkeyDigestU64 ctx "userIdHash"
      .ok (nodes ++ #[
        .comment "solana.context.userIdHash: same full-pubkey sha256; portable Hash limb0 in r2"
      ], ctx)
  | .effect (.contextRead .contractId) =>
      let (nodes, ctx) := lowerProgramIdDigestU64 ctx "contractId"
      .ok (nodes ++ #[
        .comment "solana.context.contractId: program_id sha256 limb0 (HostEnv.selfAddress)"
      ], ctx)
  | .effect (.contextRead .gasLeft) =>
    -- HostEnv.gasOrComputeBudgetLeft: remaining CU as portable u64.
    -- Uses sol_remaining_compute_units (same syscall as extension compute_units path).
    let (inputPtrSave, ctx) := ctx.allocScratch
    .ok (#[
      .comment "solana.context.gasLeft: sol_remaining_compute_units → HostEnv.gasOrComputeBudgetLeft",
      .instruction { opcode := .stxdw, dst := some .r10, off := some (.num inputPtrSave), src := some .r1 },
      .instruction { opcode := .call, imm := some (.sym sol_remaining_compute_units) },
      .instruction { opcode := .mov64, dst := some .r2, src := some .r0 },
      .instruction { opcode := .ldxdw, dst := some .r1, src := some .r10, off := some (.num inputPtrSave) }
    ], ctx)
  | .effect (.contextRead field) =>
    .error { message := s!"Solana context read `{field.name}` is not supported; userId/origin/userIdHash are sha256(account[0] pubkey), contractId is sha256(program_id), checkpointId maps to Clock.slot, timestamp maps to Clock.unix_timestamp, gasLeft maps to sol_remaining_compute_units" }
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
  | .ecrecover _ _ _ _ | .eip712PermitDigest _ _ _ _ _ _ =>
    .error { message := "Solana: ecrecover / EIP-712 permit require crypto.ecrecover (EVM-only)" }
  | .crosscallAbiPacked _ _ _ _ _ _ _ _ _ =>
    .error { message := "Solana: crosscallAbiPacked (compile-time ABI Call[]) is EVM-only" }
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
      .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num arrScratch) },
      .instruction { opcode := .mov64, dst := some .r4, src := some .r3 },
      .instruction { opcode := .sub64, dst := some .r4, imm := some (.num 8) },
      .instruction { opcode := .ldxdw, dst := some .r4, src := some .r4, off := some (.num 0) },
      .instruction { opcode := .jge, dst := some .r2, src := some .r4, off := some (.sym "error_array_bounds") },
      .instruction { opcode := .mov64, dst := some .r4, imm := some (.num elementSize) },
      .instruction { opcode := .mul64, dst := some .r2, src := some .r4 },
      .instruction { opcode := .add64, dst := some .r3, src := some .r2 },
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r3, off := some (.num 0) }
    ], ctx)
  -- Phase B.3: portable crosscall.invoke → Solana CPI-shaped materialization
  -- (method+args as ix data; callee_program account by index; result 0 / return data).
  | .crosscallInvoke target method args =>
      lowerPortableCrosscallInvoke ctx target method args
  | .crosscallInvokeTyped target method args _returnType =>
      lowerPortableCrosscallInvoke ctx target method args
  | .crosscallInvokeValueTyped target method _callValue args _returnType =>
      lowerPortableCrosscallInvoke ctx target method args
  | .crosscallInvokeStaticTyped _ _ _ _ =>
      .error { message := "STATICCALL is EVM-only; Solana materializes portable crosscall.invoke as CPI" }
  | .crosscallInvokeDelegateTyped _ _ _ _ =>
      .error { message := "DELEGATECALL is EVM-only; Solana materializes portable crosscall.invoke as CPI" }
  | .crosscallCreate _ _ | .crosscallCreate2 _ _ _ =>
      .error { message := "create/create2 are EVM-only; not materializable as Solana CPI" }
  | .nearCrosscallInvokePool .. | .nearPromiseThen .. | .nearPromiseResultsCount
  | .nearPromiseResultStatus _ | .nearPromiseResultU64 _ =>
      .error { message := "NEAR Promise expressions are not materializable on solana-sbpf-asm" }
  | _ => .error { message := "unsupported expression in Phase 1" }
where
  lowerPortableCrosscallInvoke (ctx0 : LowerCtx) (target method : IR.Expr) (args : Array IR.Expr) :
      Except LowerError (Array AstNode × LowerCtx) := do
    -- Evaluate operands into r2, then write into the fixed CPI frame so stack
    -- locals never collide with cpiInstructionOffset…cpiProgramIdOffset.
    -- PF-P2-03: portable peer handles (`.literal (.address _)` from declareRemote)
    -- are string-pool indices, not Solana input account indices. Map them to
    -- the inferred peer_program / callee_program account so CPI program_id is
    -- the real peer ELF, not the marker data account at index 0.
    let peerAccountIdx? : Option Nat :=
      match ctx0.accountBindings.find? (fun b => b.name == "peer_program") with
      | some b => some b.layout.index
      | none =>
          match ctx0.accountBindings.find? (fun b => b.name == "callee_program") with
          | some b => some b.layout.index
          | none => none
    let (tNodes, ctx1) ←
      match target, peerAccountIdx? with
      | .literal (.address _), some peerIdx =>
          .ok (#[
            .comment s!"portable peer handle → peer/callee account index {peerIdx} (PF-P2-03)",
            .instruction {
              opcode := .mov64
              dst := some .r2
              imm := some (.num peerIdx)
            }
          ], ctx0)
      | _, _ => lowerExpr ctx0 target
    let saveTarget : Array AstNode := tNodes ++ #[
      .instruction {
        opcode := .stxdw
        dst := some .r10
        off := some (.num portableTargetIndexSaveOffset)
        src := some .r2
      }
    ]
    let (mNodes, ctx2) ← lowerExpr ctx1 method
    let mut nodes : Array AstNode :=
      saveTarget ++ mNodes ++
        #[.comment "portable crosscall → Solana CPI (method + args as ix data)"] ++
        storeIxDataWord 0
    let mut workCtx := ctx2
    let mut argIdx : Nat := 0
    for arg in args do
      let (n, c) ← lowerExpr workCtx arg
      nodes := nodes ++ n ++ storeIxDataWord (argIdx + 1)
      workCtx := c
      argIdx := argIdx + 1
    let dataBytes := (1 + args.size) * 8
    let (retNoneLabel, ctxAfterArgs) := workCtx.freshLabel
    let (retEndLabel, ctxFinal) := ctxAfterArgs.freshLabel
    -- Selective accounts: signer|writable|program|executable; else full range.
    let accountIndices :=
      if !workCtx.portableCpiAccountIndices.isEmpty then
        workCtx.portableCpiAccountIndices
      else if workCtx.txAccountCount == 0 then
        #[0]
      else
        (List.range workCtx.txAccountCount).toArray
    -- PDA-authority signing for general peer CPI (not protocol/token-only).
    let signerSeeds := workCtx.portableSignerSeeds
    let (signerNodes, numSigners) :=
      if signerSeeds.isEmpty then
        (#[], 0)
      else
        let stub : ProofForge.Backend.Solana.Extension.CpiInvoke := {
          name := "portable_crosscall"
          program := ""
          instruction := ""
          signerSeeds := signerSeeds
          signed := true
        }
        (ProofForge.Backend.Solana.Extension.lowerCpiSignerSeeds
          workCtx.accountBindings workCtx.valueBindings #[] stub, 1)
    nodes := nodes ++
      invokeSignedC dataBytes accountIndices numSigners signerNodes retNoneLabel retEndLabel
    .ok (nodes, ctxFinal)

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

end ProofForge.Backend.Solana.SbpfAsm
