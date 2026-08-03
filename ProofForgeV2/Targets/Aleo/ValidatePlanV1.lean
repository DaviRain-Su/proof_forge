import ProofForgeV2.Targets.Aleo.LowerSemanticV1

/-!
# Aleo ValidatePlanV1 — plan canonicity

Validates the public `Aleo.Plan` value before any Leo source is produced.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

/-- Hard bounds (same order of magnitude as the sibling targets). -/
private def maxFunctions : Nat := 256
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
/-- Per-expression structural depth (nested constructor height). -/
private def maxExprDepth : Nat := 256
/-- Aggregate plan node budget (shared with the EVM profile; the dense Map
    upsert unrolls to thousands of pure-expr nodes). -/
private def maxPlanNodes : Nat := 100000

/-- Leo 4.0.2 reserved words / mapping method names that a DSL identifier must
    not collide with (conservative; `leo build` is the final authority).
    `rem`/`neg`/`gt`/`lt`/`add`/`sub`/`mul`/`div`/`mod`/`and`/`or`/`xor`/
    `not`/`shl`/`shr`/`pow`/`abs`/`sqrt`/`square`/`double`/`ternary`/`cast`
    are Leo reserved opcode names (spike-verified with leo 4.0.2: a function
    with any of these names fails to parse). -/
private def reservedLeoWords : Array String :=
  #[ "mapping", "transition", "finalize", "final", "function", "fn", "program",
     "constructor", "async", "record", "struct", "enum", "for", "if", "else",
     "return", "let", "assert", "true", "false", "public", "private",
     "self", "as", "cast", "i8", "i16", "i32", "i64", "i128", "u8", "u16",
     "u32", "u64", "u128", "field", "bool",
     "add", "sub", "mul", "div", "rem", "mod", "pow", "abs", "sqrt", "square",
     "neg", "and", "or", "xor", "not", "shl", "shr", "double", "ternary",
     "gt", "lt" ]

private def isReserved (name : String) : Bool :=
  reservedLeoWords.contains name


-- ---------------------------------------------------------------------------
-- Plan validation
-- ---------------------------------------------------------------------------

/-- Expression node count with a depth check. Returns `none` when the
    structural depth exceeds `maxExprDepth`. Node totals are compared against
    the aggregate `maxPlanNodes` budget by the caller. -/
private def validateExprNodes (expr : Expr) (depth : Nat) : Option Nat :=
  if depth > maxExprDepth then none
  else
  match expr with
  | .literal _ | .i64Literal _ | .uintLiteral _ _ | .boolLiteral _ | .fieldLiteral _
  | .param _ | .loopVar _ | .stateLoad _ =>
      some 1
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r
  | .signedCheckedAdd l r | .signedCheckedSub l r | .signedCheckedMul l r
  | .signedCheckedDiv l r | .signedCheckedMod l r
  | .signedShl l r | .signedShr l r
  | .signedBitAnd l r | .signedBitOr l r | .signedBitXor l r
  | .narrowCheckedAdd _ l r | .narrowCheckedSub _ l r | .narrowCheckedMul _ l r
  | .narrowCheckedDiv _ l r | .narrowCheckedMod _ l r
  | .narrowBitAnd _ l r | .narrowBitOr _ l r | .narrowBitXor _ l r
  | .narrowShl _ l r | .narrowShr _ l r
  | .fieldBinary _ l r | .fieldCompare _ l r => do
      let dl ← validateExprNodes l (depth + 1)
      let dr ← validateExprNodes r (depth + 1)
      some (dl + dr + 1)
  | .compare _ l r | .signedCompare _ l r => do
      let dl ← validateExprNodes l (depth + 1)
      let dr ← validateExprNodes r (depth + 1)
      some (dl + dr + 1)
  | .bitNot o | .boolNot o | .checkedNeg o | .signedBitNot o | .narrowBitNot _ o
  | .fieldNeg o => do
      let do' ← validateExprNodes o (depth + 1)
      some (do' + 1)
  | .ternary c t e => do
      let dc ← validateExprNodes c (depth + 1)
      let dt ← validateExprNodes t (depth + 1)
      let de ← validateExprNodes e (depth + 1)
      some (dc + dt + de + 1)
  | .callFn _ args => do
      let mut total : Nat := 1
      for arg in args do
        let da ← validateExprNodes arg (depth + 1)
        total := total + da
      some total

/-- Charge expression-node budget for one Expr; fail closed on depth/budget. -/
private def chargeExpr (budget : Nat) (value : Expr) : CompileResult Nat := do
  match validateExprNodes value 0 with
  | some nodes =>
      unless nodes ≤ budget do
        planError "Aleo plan expression exceeds the aggregate node limit"
      pure (budget - nodes)
  | none => planError "Aleo plan expression exceeds the depth limit"

/-- Aggregate node accounting across a statement list (bounded by
    `maxPlanNodes`). Depth violations surface as planInvariant directly. -/
private partial def validateStatements
    (stmts : Array Statement) (stateFieldCount : Nat) : CompileResult Unit := do
  if stmts.size > maxBodyStatements then
    planError "Aleo function body exceeds the statement limit"
  let mut budget : Nat := maxPlanNodes
  for stmt in stmts do
    match stmt with
    | .store fieldIndex value => do
        unless fieldIndex < stateFieldCount do
          planError "Aleo store targets an unknown state field"
        budget ← chargeExpr budget value
    | .storeAggregate leaves => do
        unless leaves.size > 0 do
          planError "Aleo storeAggregate has no leaves"
        let mut seen : Array Nat := #[]
        for store in leaves do
          unless store.fieldIndex < stateFieldCount do
            planError "Aleo storeAggregate targets an unknown state field"
          if seen.contains store.fieldIndex then
            planError "Aleo storeAggregate writes the same state field more than once"
          seen := seen.push store.fieldIndex
          budget ← chargeExpr budget store.value
    | .returnValue value => do
        budget ← chargeExpr budget value
    | .returnAggregate leaves leafIsInt => do
        unless leaves.size > 0 && leaves.size ≤ 8 do
          planError "Aleo returnAggregate leaf count must be in 1..8 (B-RET-ABI)"
        unless leafIsInt.size == leaves.size do
          planError "Aleo returnAggregate leafIsInt length must match leaves"
        for leaf in leaves do
          budget ← chargeExpr budget leaf
    | .returnNone => pure ()
    | .assert condition => do
        budget ← chargeExpr budget condition
    | .ifThenElse condition thenBody elseBody => do
        budget ← chargeExpr budget condition
        validateStatements thenBody stateFieldCount
        validateStatements elseBody stateFieldCount
    | .switchOn condition cases defaultBody => do
        budget ← chargeExpr budget condition
        for (_, caseBody) in cases do
          validateStatements caseBody stateFieldCount
        validateStatements defaultBody stateFieldCount
    | .forLoop start endExclusive _ body => do
        match validateExprNodes start 0, validateExprNodes endExclusive 0 with
        | some ns, some ne =>
            unless ns + ne ≤ budget do
              planError "Aleo plan expression exceeds the aggregate node limit"
            budget := budget - (ns + ne)
        | _, _ => planError "Aleo plan expression exceeds the depth limit"
        validateStatements body stateFieldCount
    | .emitEvent .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .revertError _ args =>
        unless args.isEmpty do
          planError "Aleo does not support revert payloads: Leo 4.0.2 cannot represent error arguments"

/-- B-RET-ABI depth defense: return form must match resultAggregateLeaves. -/
private partial def checkReturnFormsV1
    (fnName : String) (aggregateLeaves : Option (Array LeafAbiType))
    (stmts : Array Statement) : CompileResult Unit := do
  for s in stmts do
    match s with
    | .returnValue _ =>
        match aggregateLeaves with
        | some _ =>
            planError
              s!"function '{fnName}' aggregate result must use returnAggregate, not returnValue"
        | none => pure ()
    | .returnAggregate leaves leafIsInt =>
        match aggregateLeaves with
        | some expected =>
            unless leaves.size == expected.size && leafIsInt.size == expected.size do
              planError
                s!"function '{fnName}' returnAggregate leaf count mismatch"
            for i in [0:expected.size] do
              let some exp := expected[i]? |
                planError "returnAggregate expected leaf missing"
              let some gotInt := leafIsInt[i]? |
                planError "returnAggregate leafIsInt missing"
              unless gotInt == exp.isInt && exp.byteWidth == 8 do
                planError
                  s!"function '{fnName}' returnAggregate leaf {i} ABI mismatch"
        | none =>
            planError
              s!"function '{fnName}' returnAggregate requires an aggregate result kind"
    | .ifThenElse _ t e =>
        checkReturnFormsV1 fnName aggregateLeaves t
        checkReturnFormsV1 fnName aggregateLeaves e
    | .switchOn _ cases defaultBody =>
        for (_, body) in cases do
          checkReturnFormsV1 fnName aggregateLeaves body
        checkReturnFormsV1 fnName aggregateLeaves defaultBody
    | .forLoop _ _ _ body =>
        checkReturnFormsV1 fnName aggregateLeaves body
    | _ => pure ()

/-- Leo 4.0.2 hard limit: a `final` block allows at most 32 mapping
    `set`/`remove` commands (spike-verified ECMP0376015). Leo counts the
    emitted commands **statically across every control-flow arm** (transfer's
    two inner upserts both count), so this is a sum over arms, not a max.
    `for` bodies are guarded by `ValidatePlanV1`'s bounded-iteration model:
    the emitted body contains its sets once (the `for` is a single region),
    so the body's set count counts once. Multi-leaf `storeAggregate` counts
    one set per leaf (same as sequential emission). -/
private partial def setCountPerFinalBlock (stmts : Array Statement) : Nat :=
  stmts.foldl (fun acc stmt =>
    match stmt with
    | .store _ _ => acc + 1
    | .storeAggregate leaves => acc + leaves.size
    | .ifThenElse _ t e => acc + setCountPerFinalBlock t + setCountPerFinalBlock e
    | .switchOn _ cases d =>
        acc + cases.foldl (fun a (_, b) => a + setCountPerFinalBlock b)
          (setCountPerFinalBlock d)
    | .forLoop _ _ _ b => acc + setCountPerFinalBlock b
    | _ => acc) 0

/-- Leo final-block mapping command budget (ECMP0376015). -/
private def maxLeoMappingSets : Nat := 32

def validatePlan (plan : Plan) : CompileResult Unit := do
  if plan.functions.size > maxFunctions then
    planError "Aleo plan exceeds the function limit"
  if plan.stateFieldNames.size > maxParams then
    planError "Aleo plan exceeds the state mapping limit"
  unless plan.stateFieldIsInt.size == plan.stateFieldNames.size do
    planError "Aleo plan state signedness table must match the state field count"
  unless plan.stateFieldUintWidth.size == plan.stateFieldNames.size do
    planError "Aleo plan state uint-width table must match the state field count"
  -- A leaf cannot be both Int64 and a narrow/unsigned width, or Field+narrow.
  for i in [0:plan.stateFieldNames.size] do
    let w : Nat := plan.stateFieldUintWidth.getD i 0
    if w != 0 && w != 8 && w != 16 && w != 32 && w != 64 then
      planError s!"Aleo state leaf uint width {w} is outside 0/8/16/32/64"
    if plan.stateFieldIsInt.getD i false && isNarrowUintWidth w then
      planError "Aleo state leaf cannot be both Int64 and narrow UInt"
    if plan.stateFieldIsField.getD i false && isNarrowUintWidth w then
      planError "Aleo state leaf cannot be both Field and narrow UInt"
  let names := plan.functions.map (·.name) ++ plan.views.map (·.name)
  for name in names do
    if isReserved name then
      planError s!"Aleo identifier '{name}' collides with a reserved Leo word"
  for fn in plan.functions do
    if fn.params.size > maxParams then
      planError "Aleo plan function exceeds the parameter limit"
    for param in fn.params do
      if isReserved param.name then
        planError s!"Aleo parameter '{param.name}' collides with a reserved Leo word"
      if param.isInt && param.isBool then
        planError "Aleo parameter cannot be both Bool and Int64"
      if param.isInt && isNarrowUintWidth param.uintWidth then
        planError "Aleo parameter cannot be both Int64 and narrow UInt"
      if param.isField && isNarrowUintWidth param.uintWidth then
        planError "Aleo parameter cannot be both Field and narrow UInt"
    validateStatements fn.body plan.stateFieldNames.size
    -- Leo ECMP0376015: >32 mapping sets in one final block is invalid Leo.
    -- Fail closed at plan time (the dense Map upsert emits 3×capacity sets
    -- per arm; multi-arm matches sum statically).
    if fn.touchesState && setCountPerFinalBlock fn.body > maxLeoMappingSets then
      planError "Aleo final function exceeds the Leo mapping-set budget (32 per final block)"
    if fn.resultIsInt && fn.resultIsBool then
      planError "Aleo function result cannot be both Bool and Int64"
    -- B-RET-ABI: aggregate result is mutually exclusive with scalar flags.
    match fn.resultAggregateLeaves with
    | some leaves =>
        unless leaves.size > 0 && leaves.size ≤ 8 do
          planError
            s!"function '{fn.name}' aggregate result leaf count must be in 1..8"
        unless leaves.all (fun l => l.byteWidth == 8) do
          planError
            s!"function '{fn.name}' aggregate result leaves must be 8-byte UInt64/Int64"
        if fn.resultIsBool || fn.resultIsInt || fn.resultIsField ||
            isNarrowUintWidth fn.resultUintWidth then
          planError
            s!"function '{fn.name}' aggregate result cannot also set scalar result flags"
        if fn.isPureHelper then
          planError
            s!"function '{fn.name}' pure helper cannot return an aggregate (B-RET-ABI)"
    | none => pure ()
    checkReturnFormsV1 fn.name fn.resultAggregateLeaves fn.body
    if fn.resultDropped && fn.kind != .mutate then
      planError "resultDropped is only valid on state-touching entries"
    if fn.resultDropped && !fn.touchesState then
      planError "resultDropped requires a state-touching body"
  for view in plan.views do
    if view.stateFieldIndex >= plan.stateFieldNames.size then
      planError "Aleo view references a missing state field"
  pure ()


end ProofForgeV2.Targets.Aleo
