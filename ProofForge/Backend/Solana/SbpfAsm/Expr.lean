/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Expression Lowering

Lowering from portable IR expressions to Solana sBPF assembly AST nodes.
-/

import ProofForge.Backend.Solana.SbpfAsm.Common

namespace ProofForge.Backend.Solana.SbpfAsm

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
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
  | .effect (.contextRead .userId) =>
    .ok (#[
      .comment "solana.context.userId: read account[0] pubkey first 8 bytes as u64",
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r1, off := some (.num 16) }
    ], ctx)
  | .effect (.contextRead .origin) =>
    .ok (#[
      .comment "solana.context.origin: read account[0] pubkey first 8 bytes as u64",
      .instruction { opcode := .ldxdw, dst := some .r2, src := some .r1, off := some (.num 16) }
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

end ProofForge.Backend.Solana.SbpfAsm
