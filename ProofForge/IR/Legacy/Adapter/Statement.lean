import ProofForge.IR.Legacy.Adapter.Expr

namespace ProofForge.IR.Legacy.Adapter

open ProofForge.IR
open ProofForge.IR.Core

/- Partial block under construction. A block with a set terminator is finalized
and cannot accept further instructions. -/

structure PartialBlock where
  id : BlockId
  params : Array ValueDef := #[]
  instructions : Array Instruction := #[]
  terminator : Option Terminator := none
  deriving Repr

structure FunctionBuilder where
  blocks : Array Block
  current : PartialBlock
  deriving Repr

def FunctionBuilder.emitInstr (fb : FunctionBuilder) (instr : Instruction) : Except CanonicalizeError FunctionBuilder :=
  match fb.current.terminator with
  | some _ => .error (CanonicalizeError.terminatedBlock s!"cannot append instruction to terminated block {repr fb.current.id}")
  | none => .ok { fb with current := { fb.current with instructions := fb.current.instructions.push instr } }

def FunctionBuilder.setTerminator (fb : FunctionBuilder) (t : Terminator) : Except CanonicalizeError FunctionBuilder :=
  match fb.current.terminator with
  | some _ => .error (CanonicalizeError.terminatedBlock s!"block {repr fb.current.id} already has a terminator")
  | none => .ok { fb with current := { fb.current with terminator := some t } }

def FunctionBuilder.finishCurrent (fb : FunctionBuilder) : AdapterM FunctionBuilder :=
  match fb.current.terminator with
  | none => throw (CanonicalizeError.terminatedBlock s!"block {repr fb.current.id} has no terminator")
  | some t =>
      let block : Block := {
        id := fb.current.id,
        params := fb.current.params,
        instructions := fb.current.instructions,
        terminator := t
      }
      freshBlockId >>= fun nextId =>
        pure { blocks := fb.blocks.push block, current := { id := nextId } }

def FunctionBuilder.toBlocks (fb : FunctionBuilder) : Except CanonicalizeError (Array Block) :=
  match fb.current.terminator with
  | none => .error (CanonicalizeError.terminatedBlock s!"final block {repr fb.current.id} has no terminator")
  | some t =>
      let block : Block := {
        id := fb.current.id,
        params := fb.current.params,
        instructions := fb.current.instructions,
        terminator := t
      }
      .ok (fb.blocks.push block)

/- Default error reference for unconditional reverts. -/

def defaultRevertError : CoreErrorRef := { namespace_ := "legacy", code := 0 }

def errorRefOf (r : ErrorRef) : CoreErrorRef :=
  { namespace_ := "legacy", code := r.assertionId.toNat }

/- Normalize a legacy `Effect` into the function builder. -/

def normalizeEffect (fb : FunctionBuilder) (eff : Effect) : AdapterM FunctionBuilder :=
  match eff with
  | .storageScalarWrite stateName value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let stateId ← lookupState stateName
      let resultType ← stateScalarType stateName
      let instr := { results := #[], op := .storageStore { root := stateId, resultType := resultType } nv.value }
      liftExcept (fb.emitInstr instr)
  | .storageScalarAssignOp stateName op value => do
      let stateId ← lookupState stateName
      let resultType ← stateScalarType stateName
      let path := { root := stateId, resultType := resultType }
      let loadRef ← emitValueInstruction (.storageLoad path) resultType
      let nv ← normalizeExpr value
      let arithOp ← liftExcept (adaptAssignOp op)
      let arithRef ← emitValueInstruction (.pure (.arithmetic arithOp .wrapping loadRef.value nv.value)) resultType
      let storeInstr := { results := #[], op := .storageStore path arithRef.value }
      let fb ← liftExcept (loadRef.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (arithRef.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.emitInstr storeInstr)
  | .eventEmit name fields => do
      let eventId ← lookupEvent name
      let mut args : Array ValueRef := #[]
      let mut instrs : Array Instruction := #[]
      for (_, e) in fields do
        let nv ← normalizeExpr e
        instrs := instrs ++ nv.instructions
        args := args.push nv.value
      let fb ← liftExcept (instrs.foldlM FunctionBuilder.emitInstr fb)
      let instr := { results := #[], op := .emit eventId args }
      liftExcept (fb.emitInstr instr)
  | .contextRead field => do
      let coreField ← liftExcept (adaptContextField field)
      let resultType := contextFieldType coreField
      let ctxRef ← emitValueInstruction (.contextRead coreField) resultType
      let fb ← liftExcept (ctxRef.instructions.foldlM FunctionBuilder.emitInstr fb)
      return fb
  | other =>
      throw (CanonicalizeError.unsupportedConstructor (effectTag other) "effect not in initial fragment")

/- Normalize a legacy `Statement` into the function builder. -/

def normalizeStatement (fb : FunctionBuilder) (stmt : Statement) (retType : CoreType) : AdapterM FunctionBuilder :=
  match stmt with
  | .letBind name ty value => do
      let coreTy ← liftExcept (adaptType ty)
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      bindLocal name { id := nv.value.id, type := coreTy }
      return fb
  | .letMutBind name ty value => do
      let coreTy ← liftExcept (adaptType ty)
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      bindLocal name { id := nv.value.id, type := coreTy }
      return fb
  | .assign target value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      match target with
      | .local name => do
          bindLocal name nv.value
          return fb
      | .effect (.storageScalarRead stateName) => do
          let stateId ← lookupState stateName
          let resultType ← stateScalarType stateName
          let instr := { results := #[], op := .storageStore { root := stateId, resultType := resultType } nv.value }
          liftExcept (fb.emitInstr instr)
      | other => throw (CanonicalizeError.invalidLValue s!"assignment target {repr other}")
  | .assignOp target op value => do
      match target with
      | .effect (.storageScalarRead stateName) => do
          let stateId ← lookupState stateName
          let resultType ← stateScalarType stateName
          let path := { root := stateId, resultType := resultType }
          let loadRef ← emitValueInstruction (.storageLoad path) resultType
          let nv ← normalizeExpr value
          let arithOp ← liftExcept (adaptAssignOp op)
          let arithRef ← emitValueInstruction (.pure (.arithmetic arithOp .wrapping loadRef.value nv.value)) resultType
          let storeInstr := { results := #[], op := .storageStore path arithRef.value }
          let fb ← liftExcept (loadRef.instructions.foldlM FunctionBuilder.emitInstr fb)
          let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
          let fb ← liftExcept (arithRef.instructions.foldlM FunctionBuilder.emitInstr fb)
          liftExcept (fb.emitInstr storeInstr)
      | .local name => do
          let current ← lookupLocal name
          let nv ← normalizeExpr value
          let arithOp ← liftExcept (adaptAssignOp op)
          let arithRef ← emitValueInstruction (.pure (.arithmetic arithOp .wrapping current nv.value)) current.type
          let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
          let fb ← liftExcept (arithRef.instructions.foldlM FunctionBuilder.emitInstr fb)
          bindLocal name arithRef.value
          return fb
      | other => throw (CanonicalizeError.invalidLValue s!"assign-op target {repr other}")
  | .effect eff => normalizeEffect fb eff
  | .assert cond _msg _ => do
      let nv ← normalizeExpr cond
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let instr := { results := #[], op := .assert nv.value { namespace_ := "legacy", code := 0 } }
      liftExcept (fb.emitInstr instr)
  | .assertEq lhs rhs _msg _ => do
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nc ← emitValueInstruction (.pure (.compare .eq nl.value nr.value)) .bool
      let fb ← liftExcept (nl.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nr.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nc.instructions.foldlM FunctionBuilder.emitInstr fb)
      let instr := { results := #[], op := .assert nc.value { namespace_ := "legacy", code := 0 } }
      liftExcept (fb.emitInstr instr)
  | .revert _msg =>
      liftExcept (fb.setTerminator (.revert defaultRevertError))
  | .revertWithError ref =>
      liftExcept (fb.setTerminator (.revert (errorRefOf ref)))
  | .release _ =>
      -- Release is a no-op at the Core level; ownership is checked structurally.
      return fb
  | .ifElse cond thenBody elseBody => do
      let nv ← normalizeExpr cond
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let trueId ← freshBlockId
      let falseId ← freshBlockId
      let contId ← freshBlockId
      let fb ← liftExcept (fb.setTerminator (.branch nv.value trueId falseId))
      -- true branch
      let trueBuilder : FunctionBuilder := { blocks := fb.blocks, current := { id := trueId } }
      let trueBuilder ← thenBody.foldlM (fun b stmt => normalizeStatement b stmt retType) trueBuilder
      let trueBuilder ← liftExcept (trueBuilder.setTerminator (.jump contId #[]))
      -- false branch
      let falseBuilder : FunctionBuilder := { blocks := trueBuilder.blocks, current := { id := falseId } }
      let falseBuilder ← elseBody.foldlM (fun b stmt => normalizeStatement b stmt retType) falseBuilder
      let falseBuilder ← liftExcept (falseBuilder.setTerminator (.jump contId #[]))
      -- continuation
      return { blocks := falseBuilder.blocks, current := { id := contId } }
  | .boundedFor indexName start stopExclusive body => do
      if stopExclusive < start then
        throw (CanonicalizeError.other s!"boundedFor: stopExclusive {stopExclusive} < start {start}")
      let headerId ← freshBlockId
      let bodyId ← freshBlockId
      let contId ← freshBlockId
      -- Fresh value identities for the loop-index block parameters.
      let headerParamId ← freshValueId
      let bodyParamId ← freshValueId
      let indexParam : ValueDef := { id := headerParamId, type := .u64 }
      let bodyParam : ValueDef := { id := bodyParamId, type := .u64 }
      let boundRef : ValueRef := { id := headerParamId, type := .u64 }
      let bodyRef : ValueRef := { id := bodyParamId, type := .u64 }
      -- Enter loop: jump to header with initial index value.
      let startRefId ← freshValueId
      let startLit ← liftExcept (adaptLiteral (.u64 start))
      let startInstr := { results := #[{ id := startRefId, type := .u64 }], op := .pure (.literal startLit) }
      let fb ← liftExcept (fb.emitInstr startInstr)
      let fb ← liftExcept (fb.setTerminator (.jump headerId #[{ id := startRefId, type := .u64 }]))
      -- Header block: branch on index < stopExclusive.
      let headerBlock : PartialBlock := { id := headerId, params := #[indexParam] }
      let stopLit ← liftExcept (adaptLiteral (.u64 stopExclusive))
      let stopRef ← emitValueInstruction (.pure (.literal stopLit)) .u64
      let condRef ← emitValueInstruction (.pure (.compare .lt boundRef stopRef.value)) .bool
      let mut headerBuilder : FunctionBuilder := { blocks := fb.blocks, current := headerBlock }
      headerBuilder ← liftExcept (stopRef.instructions.foldlM FunctionBuilder.emitInstr headerBuilder)
      headerBuilder ← liftExcept (condRef.instructions.foldlM FunctionBuilder.emitInstr headerBuilder)
      headerBuilder ← liftExcept (headerBuilder.setTerminator (.branch condRef.value bodyId contId))
      -- Body block: bind index, emit body, increment, jump back to header.
      let mut bodyBuilder : FunctionBuilder := { blocks := headerBuilder.blocks, current := { id := bodyId, params := #[bodyParam] } }
      bindLocal indexName bodyRef
      bodyBuilder ← body.foldlM (fun b stmt => normalizeStatement b stmt retType) bodyBuilder
      let oneLit ← liftExcept (adaptLiteral (.u64 1))
      let oneRef ← emitValueInstruction (.pure (.literal oneLit)) .u64
      let nextRef ← emitValueInstruction (.pure (.arithmetic .add .wrapping bodyRef oneRef.value)) .u64
      bodyBuilder ← liftExcept (oneRef.instructions.foldlM FunctionBuilder.emitInstr bodyBuilder)
      bodyBuilder ← liftExcept (nextRef.instructions.foldlM FunctionBuilder.emitInstr bodyBuilder)
      bodyBuilder ← liftExcept (bodyBuilder.setTerminator (.jump headerId #[nextRef.value] (some (.atMost (stopExclusive - start)))))
      -- Continuation block becomes current.
      return { blocks := bodyBuilder.blocks, current := { id := contId } }
  | .whileLoop _ _ =>
      throw (CanonicalizeError.unboundedLoop "whileLoop requires requiresUnbounded capability resolution")
  | .return value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.setTerminator (.return #[nv.value]))

/- Ensure the final block has a return terminator. Unit functions return no
values; non-unit functions must have an explicit source return. -/

def ensureTerminator (fb : FunctionBuilder) (retType : CoreType) : AdapterM FunctionBuilder :=
  match fb.current.terminator with
  | some _ => return fb
  | none =>
      if retType == .unit then
        liftExcept (fb.setTerminator (.return #[]))
      else
        throw (CanonicalizeError.terminatedBlock s!"function returning {repr retType} missing return")

/- Normalize a statement body and return the completed blocks plus the entry
block identifier. -/

def normalizeBody (stmts : Array Statement) (retType : CoreType) : AdapterM (Array Block × BlockId) := do
  let entryId ← freshBlockId
  let builder : FunctionBuilder := { blocks := #[], current := { id := entryId } }
  let builder ← stmts.foldlM (fun b stmt => normalizeStatement b stmt retType) builder
  let builder ← ensureTerminator builder retType
  let blocks ← liftExcept builder.toBlocks
  return (blocks, entryId)

end ProofForge.IR.Legacy.Adapter
