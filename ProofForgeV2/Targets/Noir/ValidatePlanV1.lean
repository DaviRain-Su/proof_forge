import ProofForgeV2.Targets.Noir.LowerSemanticV1

/-!
# Noir ValidatePlanV1 — plan canonicity

Validates the complete target-owned relation catalog before typed lowering.
-/

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

mutual

private partial def planExprNodes? (states : Array StateField) (inputs : Array InputBinding)
    (fnCount : Nat) (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .loopParam _ => some 1
    | .param inputIndex =>
        match inputs[inputIndex]? with
        | some input => if let .parameter .. := input.role then some 1 else none
        | none => none
    | .stateLoad fieldIndex => if fieldIndex < states.size then some 1 else none
    | .checkedAdd lhs rhs | .checkedSub lhs rhs | .checkedMul lhs rhs |
        .checkedDiv lhs rhs | .checkedMod lhs rhs |
        .narrowCheckedAdd _ lhs rhs | .narrowCheckedSub _ lhs rhs |
        .narrowCheckedMul _ lhs rhs | .narrowCheckedDiv _ lhs rhs |
        .narrowCheckedMod _ lhs rhs |
        .narrowBitAnd _ lhs rhs | .narrowBitOr _ lhs rhs | .narrowBitXor _ lhs rhs |
        .narrowShl _ lhs rhs | .narrowShr _ lhs rhs |
        .fieldAdd lhs rhs | .fieldSub lhs rhs | .fieldMul lhs rhs | .fieldDiv lhs rhs |
        .bitAnd lhs rhs | .bitOr lhs rhs | .bitXor lhs rhs |
        .shl lhs rhs | .shr lhs rhs | .boolAnd lhs rhs | .boolOr lhs rhs =>
        let available := nodeBudget - 1
        match planExprNodes? states inputs fnCount (depthLeft - 1) available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? states inputs fnCount (depthLeft - 1) (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .bitNot operand | .narrowBitNot _ operand | .boolNot operand |
        .checkedNeg operand | .fieldNeg operand =>
        match planExprNodes? states inputs fnCount (depthLeft - 1) (nodeBudget - 1) operand with
        | none => none
        | some operandNodes => some (1 + operandNodes)
    | .compare _ lhs rhs | .signedCompare _ lhs rhs =>
        let available := nodeBudget - 1
        match planExprNodes? states inputs fnCount (depthLeft - 1) available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? states inputs fnCount (depthLeft - 1) (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .callFn fnIndex args =>
        if fnIndex >= fnCount then none
        else
          match planCallArgNodes? states inputs fnCount (depthLeft - 1) (nodeBudget - 1) args.toList with
          | none => none
          | some argNodes => some (1 + argNodes)

/-- Sum node counts of pure-call arguments in source order under the
    remaining budget (helper for the non-do expression walker). -/
private partial def planCallArgNodes? (states : Array StateField) (inputs : Array InputBinding)
    (fnCount depthLeft remaining : Nat) (args : List Expr) : Option Nat :=
  match args with
  | [] => some 0
  | arg :: rest =>
      match planExprNodes? states inputs fnCount (depthLeft - 1) remaining arg with
      | none => none
      | some argNodes =>
          match planCallArgNodes? states inputs fnCount (depthLeft - 1)
              (remaining - argNodes) rest with
          | none => none
          | some restNodes => some (argNodes + restNodes)

end

private def addPlanExprNodes (plan : Plan) (relation : Relation)
    (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .noir "Noir Plan exceeds aggregate node limit"
  match planExprNodes? plan.states relation.inputs plan.fns.size
      plan.resourceLimits.maxExprDepth (plan.resourceLimits.maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .noir
        "relation expression has a dangling reference or exceeds resource limits"

private def expectedParams (states : Array StateField)
    (relation : Relation) : Array Param :=
  let inputOffset := if states.isEmpty then 0 else
    1 + (if relation.mode == .initialize then 0 else states.size)
  relation.params.mapIdx fun index param => {
    param with sourceId := index, inputIndex := inputOffset + index
  }

/-- Recursive statement-tree validator for one relation: view-write ban
    (including inside branches), node accounting, and per-level return
    ordering. Returns (total, closed). -/
private partial def checkRelationStatementsV1
    (plan : Plan) (relation : Relation) (isView : Bool)
    (statements : Array Statement) (total : Nat) :
    CompileResult (Nat × Bool) := do
  let mut total := total
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .noir s!"relation '{relation.name}' has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .noir s!"view relation '{relation.name}' writes state"
        unless store.fieldIndex < plan.states.size do
          throw <| .planInvariant .noir s!"relation '{relation.name}' stores unknown state"
        total ← addPlanExprNodes plan relation total store.value
    | .returnValue value =>
        if relation.mode == .initialize then
          throw <| .planInvariant .noir "initializer relation cannot return a value"
        total ← addPlanExprNodes plan relation total value
        closed := true
    | .returnNone =>
        -- Bare return exists only for the initializer's Unit result; a marker
        -- in an entry/view relation would have no result value to bind.
        if relation.mode != .initialize then
          throw <| .planInvariant .noir
            s!"relation '{relation.name}' uses bare return outside the initializer"
        total := total + 1
        closed := true
    | .emitEvent _ eventIndex args =>
        if relation.mode == .view then
          throw <| .planInvariant .noir s!"view relation '{relation.name}' emits an event"
        unless eventIndex < plan.events.size do
          throw <| .planInvariant .noir s!"relation '{relation.name}' emits an unknown event"
        unless args.size == plan.events[eventIndex]!.fieldCount do
          throw <| .planInvariant .noir s!"relation '{relation.name}' event argument count mismatch"
        for arg in args do
          total ← addPlanExprNodes plan relation total arg
        total := total + 1
    | .externalCall _ callee args =>
        if relation.mode == .view then
          throw <| .planInvariant .noir s!"view relation '{relation.name}' makes an external call"
        unless callee.size ≥ 2 do
          throw <| .planInvariant .noir
            s!"relation '{relation.name}' external call callee must have at least two components"
        for arg in args do
          total ← addPlanExprNodes plan relation total arg
        total := total + 1
    | .schedule _ callee args =>
        if relation.mode == .view then
          throw <| .planInvariant .noir s!"view relation '{relation.name}' schedules a workflow"
        unless callee.size ≥ 2 do
          throw <| .planInvariant .noir
            s!"relation '{relation.name}' schedule callee must have at least two components"
        for arg in args do
          total ← addPlanExprNodes plan relation total arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < plan.errors.size do
          throw <| .planInvariant .noir s!"relation '{relation.name}' reverts with an unknown error"
        unless args.size == plan.errors[errorIndex]!.fieldCount do
          throw <| .planInvariant .noir s!"relation '{relation.name}' error argument count mismatch"
        for arg in args do
          total ← addPlanExprNodes plan relation total arg
        total := total + 1
        closed := true
    | .assert condition =>
        total ← addPlanExprNodes plan relation total condition
    | .forLoop _ _ initial cond update body =>
        total ← addPlanExprNodes plan relation total initial
        total ← addPlanExprNodes plan relation total cond
        total ← addPlanExprNodes plan relation total update
        -- One static event slot cannot bind multiple dynamic occurrences.
        unless (collectEmitSlots body).isEmpty do
          throw <| .planInvariant .noir
            s!"relation '{relation.name}' emits an event inside a loop"
        total := total + 1
        let (t, _) ← checkRelationStatementsV1 plan relation isView body total
        total := t
        closed := false
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes plan relation total condition
        total := total + 1
        let (t1, c1) ← checkRelationStatementsV1 plan relation isView thenBody total
        let (t2, c2) ← checkRelationStatementsV1 plan relation isView elseBody t1
        total := t2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes plan relation total scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, c) ← checkRelationStatementsV1 plan relation isView caseBody total
          total := t
          allClosed := allClosed && c
        let (td, cd) ← checkRelationStatementsV1 plan relation isView defaultBody total
        total := td
        closed := allClosed && cd
  pure (total, closed)

private def validateRelation (plan : Plan) (expectedIndex baseNodes : Nat)
    (relation : Relation) : CompileResult Nat := do
  if relation.params.size > plan.resourceLimits.maxParams then
    throw <| .planInvariant .noir s!"relation '{relation.name}' exceeds parameter limit"
  if relation.body.size > plan.resourceLimits.maxBodyStatements then
    throw <| .planInvariant .noir s!"relation '{relation.name}' exceeds body limit"
  let expectedInputCount :=
    (if plan.states.isEmpty then 0 else 2) +
    (if relation.mode == .initialize then 0 else plan.states.size) +
    relation.params.size + plan.states.size +
    (if relation.mode == .initialize then 0 else 1) +
    (collectEmitSlots relation.body).foldl (fun acc (_, _, argCount) => acc + argCount) 0 +
    (collectCallSlots relation.body).foldl (fun acc (_, argCount) => acc + 1 + argCount) 0 +
    (collectScheduleSlots relation.body).foldl (fun acc (_, argCount) => acc + argCount) 0
  unless relation.inputs.size == expectedInputCount do
    throw <| .planInvariant .noir "relation input count is outside the canonical envelope"
  unless relation.index == expectedIndex && isIdentifier relation.name &&
      relation.artifactStem == artifactStem expectedIndex relation.mode relation.name do
    throw <| .planInvariant .noir "relation identity/artifact stem is not canonical"
  unless relation.params.all (fun param => isIdentifier param.name) &&
      !hasDuplicates (relation.params.map (·.name)) do
    throw <| .planInvariant .noir "relation parameter names are not canonical"
  let expectedResultType := resultInputTypeOf relation
  unless relation.params == expectedParams plan.states relation &&
      relation.inputs == makeInputsV1 plan.states relation.mode relation.params
        expectedResultType (collectEmitSlots relation.body)
        (collectCallSlots relation.body) (collectScheduleSlots relation.body) do
    throw <| .planInvariant .noir "relation parameters/input disclosure are not canonical"
  if relation.mode != .initialize then
    unless expectedResultType == .u64 || expectedResultType == .bool ||
        expectedResultType == .field do
      throw <| .planInvariant .noir
        s!"relation '{relation.name}' result type is outside the UInt64/Bool/Field pilot"
  let (total, closed) ← checkRelationStatementsV1
    plan relation (relation.mode == .view) relation.body baseNodes
  unless closed do
    throw <| .planInvariant .noir
      s!"relation '{relation.name}' does not terminate on all paths"
  return total

/-- Validate the complete target-owned relation catalog before typed lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == semanticProgramSchemaVersionV1 &&
      plan.codegenProfile == codegenProfileString && plan.sourceDialect == sourceDialect &&
      plan.failurePolicy == .unsatisfied && plan.proofStatus == .notProduced &&
      plan.resourceLimits == canonicalLimits do
    throw <| .planInvariant .noir "Noir Plan descriptor/schema/profile policy is not canonical"
  unless isIdentifier plan.programName &&
      plan.programName.toUTF8.size <= plan.resourceLimits.maxArtifactStemBytes do
    throw <| .planInvariant .noir "program name is not a safe artifact stem"
  unless validDigest plan.sourceHash && validDigest plan.semanticHash &&
      validDigest plan.planHash do
    throw <| .planInvariant .noir "source/semantic/plan digest shape is not canonical"
  if plan.states.size > plan.resourceLimits.maxStateFields || plan.relations.isEmpty ||
      plan.relations.size > plan.resourceLimits.maxRelations then
    throw <| .planInvariant .noir "state/relation count is outside profile limits"
  for index in [0:plan.states.size] do
    let field := plan.states[index]!
    unless field.sourceId == index && isIdentifier field.name do
      throw <| .planInvariant .noir "state binding is not canonical"
  if hasDuplicates (plan.states.map (·.name)) ||
      hasDuplicates (plan.relations.map (·.name)) ||
      hasDuplicates (plan.relations.map (·.artifactStem)) then
    throw <| .planInvariant .noir "state/relation identities must be unique"
  let expectedContinuity := if plan.states.isEmpty then .none else .externalPublicPrePost
  unless plan.continuity == expectedContinuity do
    throw <| .planInvariant .noir "state continuity policy does not match the Plan state surface"
  if plan.states.isEmpty then
    if plan.relations.any (·.mode == .initialize) then
      throw <| .planInvariant .noir "stateless circuit catalog cannot contain an initializer"
  else
    unless plan.relations[0]!.mode == .initialize &&
        (plan.relations.toList.drop 1).all (·.mode != .initialize) do
      throw <| .planInvariant .noir
        "stateful circuit catalog requires exactly one leading initializer relation"
  let base := plan.states.size + plan.relations.size +
    plan.relations.foldl (fun total relation =>
      total + relation.params.size + relation.inputs.size + relation.body.size) 0
  if base > plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .noir "Noir Plan exceeds aggregate node limit"
  let mut total := base
  for index in [0:plan.relations.size] do
    total ← validateRelation plan index total plan.relations[index]!
  unless plan.planHash == canonicalPlanHash plan do
    throw <| .planInvariant .noir "complete Plan hash is not canonical"




end ProofForgeV2.Targets.Noir
