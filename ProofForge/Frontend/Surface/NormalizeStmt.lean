import ProofForge.Frontend.Surface.NormalizeExpr

/-! # Surface AST — Statement and Function Normalization

Normalize Surface statements into Core CFG blocks using a FunctionBuilder.
Mirrors the Legacy adapter's block/branch/loop construction with
Surface-owned types. Fail-closed: no wildcard fallback.
-/

namespace ProofForge.Frontend.Surface

open ProofForge.IR.Core

/-- Partial block under construction. A block with a set terminator is finalized
and cannot accept further instructions. -/
structure PartialBlock where
  id : BlockId
  params : Array ValueDef := #[]
  instructions : Array Instruction := #[]
  terminator : Option Terminator := none
  deriving Repr

/-- Function builder accumulates completed blocks and tracks the current
partial block. -/
structure FunctionBuilder where
  blocks : Array Block
  current : PartialBlock
  active : Bool := true
  deriving Repr

def FunctionBuilder.emitInstr (fb : FunctionBuilder) (instr : Instruction) :
    Except SurfaceNormalizeError FunctionBuilder :=
  if !fb.active then
    .error (SurfaceNormalizeError.terminatedBlock "cannot append instruction after all control-flow paths terminated")
  else
    match fb.current.terminator with
    | some _ => .error (SurfaceNormalizeError.terminatedBlock s!"cannot append instruction to terminated block {repr fb.current.id}")
    | none => .ok { fb with current := { fb.current with instructions := fb.current.instructions.push instr } }

def FunctionBuilder.setTerminator (fb : FunctionBuilder) (t : Terminator) :
    Except SurfaceNormalizeError FunctionBuilder :=
  if !fb.active then
    .error (SurfaceNormalizeError.terminatedBlock "cannot terminate an unreachable continuation")
  else
    match fb.current.terminator with
    | some _ => .error (SurfaceNormalizeError.terminatedBlock s!"block {repr fb.current.id} already has a terminator")
    | none => .ok { fb with current := { fb.current with terminator := some t } }

def FunctionBuilder.sealedBlocks (fb : FunctionBuilder) :
    Except SurfaceNormalizeError (Array Block) :=
  if !fb.active then
    .ok fb.blocks
  else
    match fb.current.terminator with
    | none => .error (SurfaceNormalizeError.terminatedBlock s!"block {repr fb.current.id} has no terminator")
    | some terminator => .ok (fb.blocks.push {
        id := fb.current.id,
        params := fb.current.params,
        instructions := fb.current.instructions,
        terminator := terminator })

/-- Register a revert error and return its CoreErrorRef. -/
def revertErrorRef (message : String) : SurfaceM CoreErrorRef := do
  let s ← get
  let id := ⟨s.env.nextErrorId⟩
  modify (fun st => { st with env := { st.env with
    errorDecls := st.env.errorDecls.push {
      id := id, namespace_ := "$surface", name := s!"Revert#{id.value}", code := id.value }
    nextErrorId := st.env.nextErrorId + 1 } })
  return { id := id, args := #[] }

/-- Register an assert error and return its CoreErrorRef. -/
def assertErrorRef (message : String) : SurfaceM CoreErrorRef := do
  let s ← get
  let id := ⟨s.env.nextErrorId⟩
  modify (fun st => { st with env := { st.env with
    errorDecls := st.env.errorDecls.push {
      id := id, namespace_ := "$surface", name := s!"Assert#{id.value}", code := id.value }
    nextErrorId := st.env.nextErrorId + 1 } })
  return { id := id, args := #[] }

/-- Normalize a Surface statement into the function builder. -/
partial def normalizeStatement (fb : FunctionBuilder) (stmt : SurfaceStmt)
    (retType : CoreType) : SurfaceM FunctionBuilder :=
  match stmt with
  | .bind name ty value => do
      let coreTy ← liftExcept (resolveSurfaceType (← get).env.typeIds ty)
      let nv ← normalizeExpr value
      unless nv.value.type == coreTy do
        throw (SurfaceNormalizeError.typeMismatch (reprStr coreTy) (reprStr nv.value.type))
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      bindLocal name { id := nv.value.id, type := coreTy }
      return fb
  | .mutBind name ty value => do
      let coreTy ← liftExcept (resolveSurfaceType (← get).env.typeIds ty)
      let nv ← normalizeExpr value
      unless nv.value.type == coreTy do
        throw (SurfaceNormalizeError.typeMismatch (reprStr coreTy) (reprStr nv.value.type))
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      bindLocal name { id := nv.value.id, type := coreTy }
      return fb
  | .assign target value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      match target with
      | .local name => do
          let current ← lookupLocal name
          unless current.type == nv.value.type do
            throw (SurfaceNormalizeError.typeMismatch (reprStr current.type) (reprStr nv.value.type))
          bindLocal name nv.value
          return fb
      | .stateField name => do
          let stateId ← lookupState name
          let resultType ← stateScalarType name
          let instr := { results := #[], op := .storageStore { root := stateId, resultType := resultType } nv.value }
          liftExcept (fb.emitInstr instr)
  | .stateWrite name value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let stateId ← lookupState name
      let resultType ← stateScalarType name
      let instr := { results := #[], op := .storageStore { root := stateId, resultType := resultType } nv.value }
      liftExcept (fb.emitInstr instr)
  | .emit eventName args => do
      let eventId ← lookupEvent eventName
      let mut argRefs : Array ValueRef := #[]
      let mut allInstrs : Array Instruction := #[]
      for arg in args do
        let nv ← normalizeExpr arg
        allInstrs := allInstrs ++ nv.instructions
        argRefs := argRefs.push nv.value
      let fb ← liftExcept (allInstrs.foldlM FunctionBuilder.emitInstr fb)
      let instr := { results := #[], op := .emit eventId argRefs }
      liftExcept (fb.emitInstr instr)
  | .assert cond message => do
      let nv ← normalizeExpr cond
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let error ← assertErrorRef message
      let instr := { results := #[], op := .assert nv.value error }
      liftExcept (fb.emitInstr instr)
  | .revert message => do
      let error ← revertErrorRef message
      liftExcept (fb.setTerminator (.revert error))
  | .branch cond thenBody elseBody => do
      let nv ← normalizeExpr cond
      unless nv.value.type == .bool do
        throw (SurfaceNormalizeError.typeMismatch (reprStr CoreType.bool) (reprStr nv.value.type))
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let trueId ← freshBlockId
      let falseId ← freshBlockId
      let contId ← freshBlockId
      let fb ← liftExcept (fb.setTerminator (.branch nv.value trueId falseId))
      let entryBlocks ← liftExcept fb.sealedBlocks
      let localsBefore := (← get).env.localValues
      /- True branch. -/
      let trueBuilder : FunctionBuilder := { blocks := entryBlocks, current := { id := trueId } }
      let trueBuilder ← thenBody.foldlM (fun b s => normalizeStatement b s retType) trueBuilder
      let trueFallsThrough := trueBuilder.active && trueBuilder.current.terminator.isNone
      let trueBuilder ← if trueFallsThrough then
          liftExcept (trueBuilder.setTerminator (.jump contId #[]))
        else pure trueBuilder
      let trueBlocks ← liftExcept trueBuilder.sealedBlocks
      /- False branch. -/
      modify (fun s => { s with env := { s.env with localValues := localsBefore } })
      let falseBuilder : FunctionBuilder := { blocks := trueBlocks, current := { id := falseId } }
      let falseBuilder ← elseBody.foldlM (fun b s => normalizeStatement b s retType) falseBuilder
      let falseFallsThrough := falseBuilder.active && falseBuilder.current.terminator.isNone
      let falseBuilder ← if falseFallsThrough then
          liftExcept (falseBuilder.setTerminator (.jump contId #[]))
        else pure falseBuilder
      let branchBlocks ← liftExcept falseBuilder.sealedBlocks
      modify (fun s => { s with env := { s.env with localValues := localsBefore } })
      return { blocks := branchBlocks, current := { id := contId }, active := trueFallsThrough || falseFallsThrough }
  | .boundedLoop indexName start stopExclusive body => do
      if stopExclusive < start then
        throw (SurfaceNormalizeError.terminatedBlock
          s!"boundedLoop: stopExclusive {stopExclusive} < start {start}")
      let headerId ← freshBlockId
      let bodyId ← freshBlockId
      let contId ← freshBlockId
      let localsBefore := (← get).env.localValues
      let headerParamId ← freshValueId
      let indexParam : ValueDef := { id := headerParamId, type := .u64 }
      let boundRef : ValueRef := { id := headerParamId, type := .u64 }
      let startRefId ← freshValueId
      let startLit ← liftExcept (adaptLiteral (.u64Lit start))
      let startInstr := { results := #[{ id := startRefId, type := .u64 }], op := .pure (.literal startLit) }
      let fb ← liftExcept (fb.emitInstr startInstr)
      let fb ← liftExcept (fb.setTerminator
        (.jump headerId #[{ id := startRefId, type := .u64 }]))
      let entryBlocks ← liftExcept fb.sealedBlocks
      /- Header block: compare index < stopExclusive. -/
      let headerBlock : PartialBlock := { id := headerId, params := #[indexParam] }
      let stopLit ← liftExcept (adaptLiteral (.u64Lit stopExclusive))
      let stopRef ← emitValueInstruction (.pure (.literal stopLit)) .u64
      let condRef ← emitValueInstruction (.pure (.compare .lt boundRef stopRef.value)) .bool
      let mut headerBuilder : FunctionBuilder := { blocks := entryBlocks, current := headerBlock }
      headerBuilder ← liftExcept (stopRef.instructions.foldlM FunctionBuilder.emitInstr headerBuilder)
      headerBuilder ← liftExcept (condRef.instructions.foldlM FunctionBuilder.emitInstr headerBuilder)
      headerBuilder ← liftExcept (headerBuilder.setTerminator
        (.branch condRef.value bodyId contId))
      let headerBlocks ← liftExcept headerBuilder.sealedBlocks
      /- Body block. -/
      let mut bodyBuilder : FunctionBuilder := { blocks := headerBlocks, current := { id := bodyId } }
      bindLocal indexName boundRef
      bodyBuilder ← body.foldlM (fun b s => normalizeStatement b s retType) bodyBuilder
      let bodyFallsThrough := bodyBuilder.active && bodyBuilder.current.terminator.isNone
      if bodyFallsThrough then
        let oneLit ← liftExcept (adaptLiteral (.u64Lit 1))
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
  | .hostCallBind name ty id args => do
      let coreTy ← liftExcept (resolveSurfaceType (← get).env.typeIds ty)
      let mut allInstrs : Array Instruction := #[]
      let mut argRefs : Array ValueRef := #[]
      for arg in args do
        let nv ← normalizeExpr arg
        allInstrs := allInstrs ++ nv.instructions
        argRefs := argRefs.push nv.value
      let fb ← liftExcept (allInstrs.foldlM FunctionBuilder.emitInstr fb)
      let vid ← freshValueId
      let vdef := { id := vid, type := coreTy }
      let instr := { results := #[vdef], op := .hostCall { id := id, args := argRefs } }
      let fb ← liftExcept (fb.emitInstr instr)
      bindLocal name { id := vid, type := coreTy }
      return fb
   | .returnExpr value => do
      let nv ← normalizeExpr value
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.setTerminator (.return #[nv.value]))
  | .returnUnit =>
      liftExcept (fb.setTerminator (.return #[]))

/-- Ensure the final block has a return terminator. -/
def ensureTerminator (fb : FunctionBuilder) (retType : CoreType) :
    SurfaceM FunctionBuilder :=
  if !fb.active then return fb
  else match fb.current.terminator with
    | some _ => return fb
    | none =>
        if retType == .unit then
          liftExcept (fb.setTerminator (.return #[]))
        else
          throw (SurfaceNormalizeError.terminatedBlock
            s!"function returning {repr retType} missing return")

/-- Normalize a statement body and return the completed blocks plus the entry
block identifier. -/
def normalizeBody (stmts : Array SurfaceStmt) (retType : CoreType) :
    SurfaceM (Array Block × BlockId) := do
  let entryId ← freshBlockId
  let builder : FunctionBuilder := { blocks := #[], current := { id := entryId } }
  let builder ← stmts.foldlM (fun b s => normalizeStatement b s retType) builder
  let builder ← ensureTerminator builder retType
  let blocks ← liftExcept builder.sealedBlocks
  return (blocks, entryId)

/-- Normalize one Surface entrypoint to a Core Function. -/
def adaptFunction (ep : SurfaceEntrypoint) : SurfaceM Function := do
  resetLocals
  let fid ← lookupFunction ep.name
  let params ← ep.params.mapM fun p => do
    let coreTy ← liftExcept (resolveSurfaceType (← get).env.typeIds p.type)
    let vid ← freshValueId
    let vdef := { id := vid, type := coreTy }
    bindLocal p.name { id := vid, type := coreTy }
    return vdef
  let retType ← liftExcept (resolveSurfaceType (← get).env.typeIds ep.retType)
  let (blocks, entryId) ← normalizeBody ep.body retType
  return { id := fid, params := params, retType := retType, blocks := blocks, entry := entryId }

/-- Adapt a Surface struct declaration to canonical form. -/
def adaptStruct (decl : SurfaceStructDecl) : SurfaceM Struct := do
  let id ← lookupType decl.name
  let fields ← decl.fields.mapIdxM fun idx f => do
    let ty ← liftExcept (resolveSurfaceType (← get).env.typeIds f.type)
    return { id := ⟨idx⟩, type := ty : FieldDecl }
  return { id := id, fields := fields, semantics := .value }

/-- Adapt Surface events to Core events. -/
def adaptEvents (contract : SurfaceContract) : SurfaceM (Array Event) := do
  contract.events.mapIdxM fun idx ev => do
    let eventId ← lookupEvent ev.name
    let fields ← ev.fields.mapIdxM fun fidx f => do
      let ty ← liftExcept (resolveSurfaceType (← get).env.typeIds f.type)
      return { id := ⟨fidx⟩, type := ty : EventFieldDecl }
    return { id := eventId, fields := fields }

/-- Adapt the runtime portion of a Surface contract to canonical Core. -/
def adaptModule (contract : SurfaceContract) : SurfaceM Module := do
  let structs ← contract.structs.mapM adaptStruct
  let state ← contract.state.mapM fun s => do
    let id ← lookupState s.name
    let shape ← lookupStateShape s.name
    return { id := id, shape := shape : StateDecl }
  let functions ← contract.entrypoints.mapM adaptFunction
  let events ← adaptEvents contract
  let env := (← get).env
  return {
    name := contract.name,
    structs := structs,
    state := state,
    functions := functions,
    events := events,
    errors := env.errorDecls
  }

end ProofForge.Frontend.Surface