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
  active : Bool := true
  deriving Repr

def FunctionBuilder.emitInstr (fb : FunctionBuilder) (instr : Instruction) : Except CanonicalizeError FunctionBuilder :=
  if !fb.active then
    .error (CanonicalizeError.terminatedBlock "cannot append instruction after all control-flow paths terminated")
  else
    match fb.current.terminator with
    | some _ => .error (CanonicalizeError.terminatedBlock s!"cannot append instruction to terminated block {repr fb.current.id}")
    | none => .ok { fb with current := { fb.current with instructions := fb.current.instructions.push instr } }

def FunctionBuilder.setTerminator (fb : FunctionBuilder) (t : Terminator) : Except CanonicalizeError FunctionBuilder :=
  if !fb.active then
    .error (CanonicalizeError.terminatedBlock "cannot terminate an unreachable continuation")
  else
    match fb.current.terminator with
    | some _ => .error (CanonicalizeError.terminatedBlock s!"block {repr fb.current.id} already has a terminator")
    | none => .ok { fb with current := { fb.current with terminator := some t } }

def FunctionBuilder.sealedBlocks (fb : FunctionBuilder) : Except CanonicalizeError (Array Block) :=
  if !fb.active then
    .ok fb.blocks
  else
    match fb.current.terminator with
    | none => .error (CanonicalizeError.terminatedBlock s!"block {repr fb.current.id} has no terminator")
    | some terminator => .ok (fb.blocks.push {
        id := fb.current.id
        params := fb.current.params
        instructions := fb.current.instructions
        terminator := terminator
      })

def FunctionBuilder.finishCurrent (fb : FunctionBuilder) : AdapterM FunctionBuilder := do
  let blocks ← liftExcept fb.sealedBlocks
  let nextId ← freshBlockId
  return { blocks := blocks, current := { id := nextId } }

def FunctionBuilder.toBlocks (fb : FunctionBuilder) : Except CanonicalizeError (Array Block) :=
  fb.sealedBlocks

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
      unless nv.value.type == coreTy do
        throw (CanonicalizeError.typeMismatch (reprStr coreTy) (reprStr nv.value.type))
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      bindLocal name { id := nv.value.id, type := coreTy }
      return fb
  | .letMutBind name ty value => do
      let coreTy ← liftExcept (adaptType ty)
      let nv ← normalizeExpr value
      unless nv.value.type == coreTy do
        throw (CanonicalizeError.typeMismatch (reprStr coreTy) (reprStr nv.value.type))
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
  | .assert cond _msg errorRef? => do
      let nv ← normalizeExpr cond
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let error := errorRef?.map errorRefOf |>.getD defaultRevertError
      let instr := { results := #[], op := .assert nv.value error }
      liftExcept (fb.emitInstr instr)
  | .assertEq lhs rhs _msg errorRef? => do
      let nl ← normalizeExpr lhs
      let nr ← normalizeExpr rhs
      let nc ← emitValueInstruction (.pure (.compare .eq nl.value nr.value)) .bool
      let fb ← liftExcept (nl.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nr.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nc.instructions.foldlM FunctionBuilder.emitInstr fb)
      let error := errorRef?.map errorRefOf |>.getD defaultRevertError
      let instr := { results := #[], op := .assert nc.value error }
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
      let entryBlocks ← liftExcept fb.sealedBlocks
      let localsBefore := (← get).env.localValues

      let trueBuilder : FunctionBuilder := { blocks := entryBlocks, current := { id := trueId } }
      let trueBuilder ← thenBody.foldlM (fun b stmt => normalizeStatement b stmt retType) trueBuilder
      let trueFallsThrough := trueBuilder.current.terminator.isNone
      let trueBuilder ← if trueFallsThrough then
          liftExcept (trueBuilder.setTerminator (.jump contId #[]))
        else
          pure trueBuilder
      let trueBlocks ← liftExcept trueBuilder.sealedBlocks

      modify (fun s => { s with env := { s.env with localValues := localsBefore } })
      let falseBuilder : FunctionBuilder := { blocks := trueBlocks, current := { id := falseId } }
      let falseBuilder ← elseBody.foldlM (fun b stmt => normalizeStatement b stmt retType) falseBuilder
      let falseFallsThrough := falseBuilder.current.terminator.isNone
      let falseBuilder ← if falseFallsThrough then
          liftExcept (falseBuilder.setTerminator (.jump contId #[]))
        else
          pure falseBuilder
      let branchBlocks ← liftExcept falseBuilder.sealedBlocks

      modify (fun s => { s with env := { s.env with localValues := localsBefore } })
      return {
        blocks := branchBlocks
        current := { id := contId }
        active := trueFallsThrough || falseFallsThrough
      }
  | .boundedFor indexName start stopExclusive body => do
      if stopExclusive < start then
        throw (CanonicalizeError.other s!"boundedFor: stopExclusive {stopExclusive} < start {start}")
      let headerId ← freshBlockId
      let bodyId ← freshBlockId
      let contId ← freshBlockId
      let localsBefore := (← get).env.localValues
      let headerParamId ← freshValueId
      let indexParam : ValueDef := { id := headerParamId, type := .u64 }
      let boundRef : ValueRef := { id := headerParamId, type := .u64 }
      let startRefId ← freshValueId
      let startLit ← liftExcept (adaptLiteral (.u64 start))
      let startInstr := { results := #[{ id := startRefId, type := .u64 }], op := .pure (.literal startLit) }
      let fb ← liftExcept (fb.emitInstr startInstr)
      let fb ← liftExcept (fb.setTerminator (.jump headerId #[{ id := startRefId, type := .u64 }]))
      let entryBlocks ← liftExcept fb.sealedBlocks

      let headerBlock : PartialBlock := { id := headerId, params := #[indexParam] }
      let stopLit ← liftExcept (adaptLiteral (.u64 stopExclusive))
      let stopRef ← emitValueInstruction (.pure (.literal stopLit)) .u64
      let condRef ← emitValueInstruction (.pure (.compare .lt boundRef stopRef.value)) .bool
      let mut headerBuilder : FunctionBuilder := { blocks := entryBlocks, current := headerBlock }
      headerBuilder ← liftExcept (stopRef.instructions.foldlM FunctionBuilder.emitInstr headerBuilder)
      headerBuilder ← liftExcept (condRef.instructions.foldlM FunctionBuilder.emitInstr headerBuilder)
      headerBuilder ← liftExcept (headerBuilder.setTerminator (.branch condRef.value bodyId contId))
      let headerBlocks ← liftExcept headerBuilder.sealedBlocks

      let mut bodyBuilder : FunctionBuilder := { blocks := headerBlocks, current := { id := bodyId } }
      bindLocal indexName boundRef
      bodyBuilder ← body.foldlM (fun b stmt => normalizeStatement b stmt retType) bodyBuilder
      if bodyBuilder.current.terminator.isNone then
        let oneLit ← liftExcept (adaptLiteral (.u64 1))
        let oneRef ← emitValueInstruction (.pure (.literal oneLit)) .u64
        let nextRef ← emitValueInstruction
          (.pure (.arithmetic .add .wrapping boundRef oneRef.value)) .u64
        bodyBuilder ← liftExcept (oneRef.instructions.foldlM FunctionBuilder.emitInstr bodyBuilder)
        bodyBuilder ← liftExcept (nextRef.instructions.foldlM FunctionBuilder.emitInstr bodyBuilder)
        bodyBuilder ← liftExcept (bodyBuilder.setTerminator
          (.jump headerId #[nextRef.value] (some (.atMost (stopExclusive - start)))))
      let loopBlocks ← liftExcept bodyBuilder.sealedBlocks
      modify (fun s => { s with env := { s.env with localValues := localsBefore } })
      return { blocks := loopBlocks, current := { id := contId } }
  | .whileLoop _ _ =>
      throw (CanonicalizeError.unboundedLoop "whileLoop requires requiresUnbounded capability resolution")
  | .return value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.setTerminator (.return #[nv.value]))

/- Ensure the final block has a return terminator. Unit functions return no
values; non-unit functions must have an explicit source return. -/

def ensureTerminator (fb : FunctionBuilder) (retType : CoreType) : AdapterM FunctionBuilder :=
  if !fb.active then
    return fb
  else
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
