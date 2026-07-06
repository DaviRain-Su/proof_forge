/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# Solana sBPF Statement Lowering

Lowering from portable IR statements to Solana sBPF assembly AST nodes.
-/

import ProofForge.Backend.Solana.SbpfAsm.Expr

namespace ProofForge.Backend.Solana.SbpfAsm

open ProofForge.IR
open ProofForge.Backend.Solana.Asm
open ProofForge.Backend.Solana.Extension
open ProofForge.Backend.Solana.StateLayout
open ProofForge.Backend.Solana.Manifest
open ProofForge.Backend.Solana.Register
open ProofForge.Backend.Solana.Syscalls

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
      let length ←
        match arrayStateLength? ctx.stateDecls stateId with
        | some length => .ok length
        | none => .error { message := s!"state `{stateId}` is not a fixed array state" }
      let elementSize ←
        match arrayStateElementType? ctx.stateDecls stateId with
        | some ty => .ok (valueTypeByteSize ty)
        | none => .error { message := s!"cannot resolve element type for array state `{stateId}`" }
      let (valNodes, ctx') ← lowerExpr ctx value
      let (valScratch, ctx') := ctx'.allocScratch
      let (idxNodes, ctx') ← lowerExpr ctx' index
      .ok (valNodes ++ #[
        .comment s!"solana.storage.array_write {stateId}: save value",
        .instruction { opcode := .stxdw, dst := some .r10, off := some (.num valScratch), src := some .r2 }
      ] ++ idxNodes ++ #[
        .comment s!"solana.storage.array_write {stateId}: compute address and store",
        .instruction { opcode := .mov64, dst := some .r3, imm := some (.num length) },
        .instruction { opcode := .jge, dst := some .r2, src := some .r3, off := some (.sym "error_array_bounds") },
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
      let length ←
        match arrayStateLength? ctx.stateDecls stateId with
        | some length => .ok length
        | none => .error { message := s!"state `{stateId}` is not a fixed array state" }
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
          .instruction { opcode := .mov64, dst := some .r3, imm := some (.num length) },
          .instruction { opcode := .jge, dst := some .r2, src := some .r3, off := some (.sym "error_array_bounds") },
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
      .instruction { opcode := .ldxdw, dst := some .r3, src := some .r10, off := some (.num arrScratch) },
      .instruction { opcode := .mov64, dst := some .r4, src := some .r3 },
      .instruction { opcode := .sub64, dst := some .r4, imm := some (.num 8) },
      .instruction { opcode := .ldxdw, dst := some .r4, src := some .r4, off := some (.num 0) },
      .instruction { opcode := .ldxdw, dst := some .r5, src := some .r10, off := some (.num idxScratch) },
      .instruction { opcode := .jge, dst := some .r5, src := some .r4, off := some (.sym "error_array_bounds") },
      .instruction { opcode := .mov64, dst := some .r4, imm := some (.num elementSize) },
      .instruction { opcode := .mul64, dst := some .r5, src := some .r4 },
      .instruction { opcode := .add64, dst := some .r3, src := some .r5 },
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

end ProofForge.Backend.Solana.SbpfAsm
