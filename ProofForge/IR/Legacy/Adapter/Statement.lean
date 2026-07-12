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

private def projectOuterLocals (outer candidate : Std.HashMap String ValueRef) :
    Std.HashMap String ValueRef :=
  outer.toList.foldl (fun projected entry =>
    let (name, before) := entry
    projected.insert name ((Std.HashMap.get? candidate name).getD before)) {}

private def mergeBranchLocals (outer trueLocals falseLocals : Std.HashMap String ValueRef)
    (trueFallsThrough falseFallsThrough : Bool) :
    Except CanonicalizeError (Std.HashMap String ValueRef) := do
  if trueFallsThrough && falseFallsThrough then
    let mut merged : Std.HashMap String ValueRef := {}
    for (name, before) in outer.toList do
      let trueValue := (Std.HashMap.get? trueLocals name).getD before
      let falseValue := (Std.HashMap.get? falseLocals name).getD before
      unless trueValue == falseValue do
        throw (CanonicalizeError.unsupportedConstructor "Statement.ifElse"
          s!"outer local `{name}` requires a continuation phi parameter")
      merged := merged.insert name trueValue
    return merged
  else if trueFallsThrough then
    return projectOuterLocals outer trueLocals
  else if falseFallsThrough then
    return projectOuterLocals outer falseLocals
  else
    return outer

private def changedOuterLocal? (outer candidate : Std.HashMap String ValueRef) : Option String :=
  outer.toList.findSome? (fun entry =>
    let (name, before) := entry
    match Std.HashMap.get? candidate name with
    | some after => if after == before then none else some name
    | none => some name)

/- Default error reference for unconditional reverts. -/

def fallbackError (message : String) (form : RegisteredErrorForm) : AdapterM CoreErrorRef := do
  let id ← registerError "legacy" "Revert" none 0 message form
  return { id := id, args := #[] }

def errorRefOf (message : String) (r : ErrorRef) : AdapterM CoreErrorRef := do
  let name := r.userCode?.getD s!"Error{r.assertionId}"
  let form := if r.soliditySelector?.isSome then
      RegisteredErrorForm.solidityCustom
    else
      RegisteredErrorForm.proofForgeEnvelope
  let id ← registerError "legacy" name r.userCode? r.assertionId.toNat message
    form (r.soliditySelector?.map String.toLower) r.solidityArgWords r.solidityArgTypes
  return { id := id, args := #[] }

private def normalizeStatementStoragePath (name : String) (path : Array StoragePathSegment) :
    AdapterM (Array Instruction × Array Core.StorageSegment × CoreType) := do
  let shape ← lookupStateShape name
  match shape, path with
  | .map .u64 value _, #[.mapKey outer, .mapKey inner] =>
      let nouter ← coerceLegacyAddressHandle (← normalizeExpr outer) .u64
      let ninner ← coerceLegacyAddressHandle (← normalizeExpr inner) .u64
      let salt ← emitValueInstruction (.pure (.literal (.u64Lit 0x9e3779b185ebca87))) .u64
      let mixed ← arithmeticValue .wrapping .mul nouter.value salt.value .u64
      let key ← arithmeticValue .wrapping .xor mixed.value ninner.value .u64
      return (nouter.instructions ++ ninner.instructions ++ salt.instructions ++
        mixed.instructions ++ key.instructions, #[.mapKey key.value], value)
  | _, _ =>
      let mut instructions := #[]
      let mut segments := #[]
      let mut current := shape
      for segment in path do
        match segment, current with
        | .mapKey key, .map expectedKey value _ =>
            let normalized ← coerceLegacyAddressHandle (← normalizeExpr key) expectedKey
            instructions := instructions ++ normalized.instructions
            segments := segments.push (.mapKey normalized.value)
            current := .scalar value
        | .index index, .fixedArray element _ =>
            let normalized ← normalizeExpr index
            unless normalized.value.type == .u64 do
              throw (CanonicalizeError.typeMismatch (reprStr CoreType.u64) (reprStr normalized.value.type))
            instructions := instructions ++ normalized.instructions
            segments := segments.push (.index normalized.value)
            current := .scalar element
        | .field _, _ =>
            throw (CanonicalizeError.unsupportedConstructor "StoragePathSegment.field"
              "record field IDs are not available in the initial adapter environment")
        | _, _ => throw (CanonicalizeError.typeMismatch "compatible storage path" (reprStr current))
      let resultType ← match current with
        | .scalar type => pure type
        | _ => throw (CanonicalizeError.typeMismatch "scalar storage leaf" (reprStr current))
      return (instructions, segments, resultType)

/- Normalize a legacy `Effect` into the function builder. -/

def normalizeEffect (fb : FunctionBuilder) (eff : Effect) : AdapterM FunctionBuilder :=
  match eff with
  | .storageScalarWrite stateName value => do
      let stateId ← lookupState stateName
      let resultType ← stateScalarType stateName
      let nv ← coerceLegacyAddressHandle (← normalizeExpr value) resultType
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let instr := { results := #[], op := .storageStore { root := stateId, resultType := resultType } nv.value }
      liftExcept (fb.emitInstr instr)
  | .storageScalarAssignOp stateName op value => do
      if stateName == "$eip1967.implementation" then
        throw (CanonicalizeError.unsupportedConstructor "Effect.storageScalarAssignOp"
          "compound assignment is not allowed for the EIP-1967 implementation state")
      let stateId ← lookupState stateName
      let resultType ← stateScalarType stateName
      let path := { root := stateId, resultType := resultType }
      let loadRef ← emitValueInstruction (.storageLoad path) resultType
      let nv ← normalizeExpr value
      let arithOp ← liftExcept (adaptAssignOp op)
      let mode := (← get).env.overflowMode
      let arithRef ← emitValueInstruction (.pure (.arithmetic arithOp mode loadRef.value nv.value)) resultType
      let storeInstr := { results := #[], op := .storageStore path arithRef.value }
      let fb ← liftExcept (loadRef.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (arithRef.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.emitInstr storeInstr)
  | .storageMapSet stateName key value => do
      let stateId ← lookupState stateName
      let (keyType, valueType) ← stateMapTypes stateName
      let normalizedKey ← normalizeExpr key
      let normalizedValue ← normalizeExpr value
      unless normalizedKey.value.type == keyType do
        throw (CanonicalizeError.typeMismatch (reprStr keyType) (reprStr normalizedKey.value.type))
      unless normalizedValue.value.type == valueType do
        throw (CanonicalizeError.typeMismatch (reprStr valueType) (reprStr normalizedValue.value.type))
      let fb ← liftExcept (normalizedKey.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (normalizedValue.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.emitInstr { results := #[], op := .storageStore {
        root := stateId
        path := #[.mapKey normalizedKey.value]
        resultType := valueType } normalizedValue.value })
  | .storagePathWrite stateName path value => do
      let stateId ← lookupState stateName
      let (pathInstructions, segments, resultType) ← normalizeStatementStoragePath stateName path
      let normalizedValue ← coerceLegacyAddressHandle (← normalizeExpr value) resultType
      let fb ← liftExcept (pathInstructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (normalizedValue.instructions.foldlM FunctionBuilder.emitInstr fb)
      liftExcept (fb.emitInstr { results := #[], op := .storageStore {
        root := stateId, path := segments, resultType } normalizedValue.value })
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
  | .eventEmitIndexed name indexedFields dataFields => do
      let eventId ← lookupEvent name
      let mut args : Array ValueRef := #[]
      let mut instrs : Array Instruction := #[]
      for (_, e) in indexedFields ++ dataFields do
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
  | .letBind name ty (.arrayLit elementType values) => do
      let coreTy ← liftExcept (adaptType (← get).env.typeIds ty)
      let coreElementType ← liftExcept (adaptType (← get).env.typeIds elementType)
      unless coreTy == CoreType.fixedArray coreElementType values.size do
        throw (CanonicalizeError.typeMismatch
          (reprStr (CoreType.fixedArray coreElementType values.size)) (reprStr coreTy))
      let mut fb := fb
      let mut normalizedValues := #[]
      for value in values do
        let normalized ← normalizeExpr value
        unless normalized.value.type == coreElementType do
          throw (CanonicalizeError.typeMismatch (reprStr coreElementType) (reprStr normalized.value.type))
        fb ← liftExcept (normalized.instructions.foldlM FunctionBuilder.emitInstr fb)
        normalizedValues := normalizedValues.push normalized.value
      bindLocalArray name normalizedValues
      return fb
  | .letBind name ty value => do
      let coreTy ← liftExcept (adaptType (← get).env.typeIds ty)
      let nv ← coerceLegacyAddressHandle (← normalizeExpr value) coreTy
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      bindLocal name { id := nv.value.id, type := coreTy }
      return fb
  | .letMutBind name ty value => do
      let coreTy ← liftExcept (adaptType (← get).env.typeIds ty)
      let nv ← coerceLegacyAddressHandle (← normalizeExpr value) coreTy
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
            throw (CanonicalizeError.typeMismatch (reprStr current.type) (reprStr nv.value.type))
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
          let mode := (← get).env.overflowMode
          let arithRef ← emitValueInstruction (.pure (.arithmetic arithOp mode loadRef.value nv.value)) resultType
          let storeInstr := { results := #[], op := .storageStore path arithRef.value }
          let fb ← liftExcept (loadRef.instructions.foldlM FunctionBuilder.emitInstr fb)
          let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
          let fb ← liftExcept (arithRef.instructions.foldlM FunctionBuilder.emitInstr fb)
          liftExcept (fb.emitInstr storeInstr)
      | .local name => do
          let current ← lookupLocal name
          let nv ← normalizeExpr value
          let arithOp ← liftExcept (adaptAssignOp op)
          let mode := (← get).env.overflowMode
          let arithRef ← emitValueInstruction (.pure (.arithmetic arithOp mode current nv.value)) current.type
          let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
          let fb ← liftExcept (arithRef.instructions.foldlM FunctionBuilder.emitInstr fb)
          bindLocal name arithRef.value
          return fb
      | other => throw (CanonicalizeError.invalidLValue s!"assign-op target {repr other}")
  | .effect eff => normalizeEffect fb eff
  | .assert cond message errorRef? => do
      let nv ← normalizeExpr cond
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let error ← match errorRef? with
        | some r => errorRefOf message r
        | none => fallbackError message .assertFallback
      let instr := { results := #[], op := .assert nv.value error }
      liftExcept (fb.emitInstr instr)
  | .assertEq lhs rhs message errorRef? => do
      let nl ← normalizeExpr lhs
      let nr ← coerceLegacyAddressHandle (← normalizeExpr rhs) nl.value.type
      let nc ← emitValueInstruction (.pure (.compare .eq nl.value nr.value)) .bool
      let fb ← liftExcept (nl.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nr.instructions.foldlM FunctionBuilder.emitInstr fb)
      let fb ← liftExcept (nc.instructions.foldlM FunctionBuilder.emitInstr fb)
      let error ← match errorRef? with
        | some r => errorRefOf message r
        | none => fallbackError message .assertFallback
      let instr := { results := #[], op := .assert nc.value error }
      liftExcept (fb.emitInstr instr)
  | .revert message => do
      let error ← fallbackError message .revertMessage
      liftExcept (fb.setTerminator (.revert error))
  | .revertWithError ref => do
      let error ← errorRefOf (ref.userCode?.getD "revertWithError") ref
      liftExcept (fb.setTerminator (.revert error))
  | .release _ =>
      throw (CanonicalizeError.unsupportedConstructor "Statement.release"
        "ownership-aware memory release is not implemented in canonical normalization")
  | .ifElse cond thenBody elseBody => do
      let nv ← normalizeExpr cond
      unless nv.value.type == .bool do
        throw (CanonicalizeError.typeMismatch (reprStr CoreType.bool) (reprStr nv.value.type))
      let fb ← liftExcept (nv.instructions.foldlM FunctionBuilder.emitInstr fb)
      let trueId ← freshBlockId
      let falseId ← freshBlockId
      let contId ← freshBlockId
      let fb ← liftExcept (fb.setTerminator (.branch nv.value trueId falseId))
      let entryBlocks ← liftExcept fb.sealedBlocks
      let localsBefore := (← get).env.localValues
      let arraysBefore := (← get).env.localArrays

      let trueBuilder : FunctionBuilder := { blocks := entryBlocks, current := { id := trueId } }
      let trueBuilder ← thenBody.foldlM (fun b stmt => normalizeStatement b stmt retType) trueBuilder
      let trueFallsThrough := trueBuilder.active && trueBuilder.current.terminator.isNone
      let trueBuilder ← if trueFallsThrough then
          liftExcept (trueBuilder.setTerminator (.jump contId #[]))
        else
          pure trueBuilder
      let trueBlocks ← liftExcept trueBuilder.sealedBlocks
      let trueLocals := (← get).env.localValues

      modify (fun s => { s with env := {
        s.env with localValues := localsBefore, localArrays := arraysBefore } })
      let falseBuilder : FunctionBuilder := { blocks := trueBlocks, current := { id := falseId } }
      let falseBuilder ← elseBody.foldlM (fun b stmt => normalizeStatement b stmt retType) falseBuilder
      let falseFallsThrough := falseBuilder.active && falseBuilder.current.terminator.isNone
      let falseBuilder ← if falseFallsThrough then
          liftExcept (falseBuilder.setTerminator (.jump contId #[]))
        else
          pure falseBuilder
      let branchBlocks ← liftExcept falseBuilder.sealedBlocks
      let falseLocals := (← get).env.localValues

      let mergedLocals ← liftExcept <|
        mergeBranchLocals localsBefore trueLocals falseLocals trueFallsThrough falseFallsThrough
      modify (fun s => { s with env := {
        s.env with localValues := mergedLocals, localArrays := arraysBefore } })
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
      let arraysBefore := (← get).env.localArrays
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
      let bodyFallsThrough := bodyBuilder.active && bodyBuilder.current.terminator.isNone
      if bodyFallsThrough then
        let oneLit ← liftExcept (adaptLiteral (.u64 1))
        let oneRef ← emitValueInstruction (.pure (.literal oneLit)) .u64
        let nextRef ← emitValueInstruction
          (.pure (.arithmetic .add .wrapping boundRef oneRef.value)) .u64
        bodyBuilder ← liftExcept (oneRef.instructions.foldlM FunctionBuilder.emitInstr bodyBuilder)
        bodyBuilder ← liftExcept (nextRef.instructions.foldlM FunctionBuilder.emitInstr bodyBuilder)
        bodyBuilder ← liftExcept (bodyBuilder.setTerminator
          (.jump headerId #[nextRef.value] (some (.atMost (stopExclusive - start)))))
      if bodyFallsThrough then
        match changedOuterLocal? localsBefore (← get).env.localValues with
        | some name =>
            throw (CanonicalizeError.unsupportedConstructor "Statement.boundedFor"
              s!"outer local `{name}` requires a loop-carried block parameter")
        | none => pure ()
      let loopBlocks ← liftExcept bodyBuilder.sealedBlocks
      modify (fun s => { s with env := {
        s.env with localValues := localsBefore, localArrays := arraysBefore } })
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
