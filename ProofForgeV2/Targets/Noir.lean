import ProofForgeV2.Targets.Common

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2

def codegenProfile : String := "noir-source-u64-relations-v1"
def sourceDialect : String := "noir-native-u64-relations-v1"

def descriptor : TargetDescriptor := {
  targetId := .noir
  artifactEncoding := .noirSource
  executionHost := .circuit
  commitModel := .externalStateTransition
  stateBinding := .proofInputs
  callModel := .none
  proofModel := .circuitProof
  settlementModel := .externalVerifier
  codegenProfile
  supportedRequirements := #[
    .persistentState, .checkedArithmetic, .transactionalRollback, .privateWitness
  ]
}

inductive StateContinuity where
  | none
  | externalPublicPrePost
  deriving BEq, Inhabited, Repr

inductive ConstraintFailurePolicy where
  | unsatisfied
  deriving BEq, Inhabited, Repr

inductive ProofStatus where
  | notProduced
  deriving BEq, Inhabited, Repr

inductive RelationMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

inductive InputVisibility where
  | verifier
  | witness
  deriving BEq, Inhabited, Repr

inductive InputType where
  | u64
  | bool
  deriving BEq, Inhabited, Repr

inductive InputRole where
  | preInitialized
  | preState (sourceId : Nat)
  | parameter (sourceId : Nat)
  | postState (sourceId : Nat)
  | postInitialized
  | result
  deriving BEq, Inhabited, Repr

structure ResourceLimits where
  maxArtifactStemBytes : Nat
  maxStateFields : Nat
  maxRelations : Nat
  maxParams : Nat
  maxBodyStatements : Nat
  maxExprDepth : Nat
  maxPlanNodes : Nat
  maxIrOperations : Nat
  deriving BEq, Inhabited, Repr

structure StateField where
  sourceId : Nat
  name : String
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputIndex : Nat
  visibility : InputVisibility
  deriving BEq, Inhabited, Repr

structure InputBinding where
  name : String
  sourceName : String
  type : InputType
  visibility : InputVisibility
  role : InputRole
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (inputIndex : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  deriving BEq, Inhabited, Repr

/-- One independently provable relation. Initializer, mutate, and view methods
are never folded into an inactive-selector circuit. -/
structure Relation where
  index : Nat
  name : String
  artifactStem : String
  mode : RelationMode
  params : Array Param
  inputs : Array InputBinding
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Target-owned source-relation plan. It deliberately retains no
SemanticProgram and records that proof production/settlement are external. -/
structure Plan where
  targetDescriptor : TargetDescriptor
  semanticSchemaVersion : Nat
  codegenProfile : String
  sourceDialect : String
  continuity : StateContinuity
  failurePolicy : ConstraintFailurePolicy
  proofStatus : ProofStatus
  resourceLimits : ResourceLimits
  programName : String
  sourceHash : String
  semanticHash : String
  /-- Deterministic digest of the complete canonical Plan. This detects
  unchecked in-process mutation; it is not an authenticity certificate for an
  untrusted serialized Plan. -/
  planHash : String
  states : Array StateField
  relations : Array Relation
  deriving BEq, Inhabited, Repr

inductive ValueRef where
  | input (index : Nat)
  | literal (value : UInt64)
  | temp (index : Nat)
  deriving BEq, Inhabited, Repr

inductive Operation where
  | checkedAdd (destination : Nat) (lhs rhs : ValueRef)
  | assertEqual (lhs rhs : ValueRef)
  | assertBool (inputIndex : Nat) (expected : Bool)
  deriving BEq, Inhabited, Repr

structure RelationIR where
  sourceRelation : Relation
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Exact typed circuit recipe. Rendering source is later than Plan-to-IR
validation so source strings cannot rediscover business semantics. -/
structure IR where
  sourcePlan : Plan
  name : String
  relations : Array RelationIR
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .noir message

private def maxIdentifierBytes : Nat := 120
private def maxArtifactStemBytes : Nat := 220
private def maxStateFields : Nat := 256
private def maxRelations : Nat := 256
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxPlanNodes : Nat := 100000
private def maxIrOperations : Nat := 110000

private def canonicalLimits : ResourceLimits := {
  maxArtifactStemBytes
  maxStateFields
  maxRelations
  maxParams
  maxBodyStatements
  maxExprDepth
  maxPlanNodes
  maxIrOperations
}

private def isIdentifier (value : String) : Bool :=
  value.toUTF8.size <= maxIdentifierBytes && match value.toList with
  | [] => false
  | first :: rest =>
      let isAsciiLetter (character : Char) : Bool :=
        let code := character.toNat
        (65 <= code && code <= 90) || (97 <= code && code <= 122)
      let isAsciiDigit (character : Char) : Bool :=
        let code := character.toNat
        48 <= code && code <= 57
      (isAsciiLetter first || first == '_') &&
        rest.all (fun character =>
          isAsciiLetter character || isAsciiDigit character || character == '_')

private def hasDuplicates [BEq α] (values : Array α) : Bool := Id.run do
  let mut seen : Array α := #[]
  for value in values do
    if seen.contains value then return true
    seen := seen.push value
  return false

private def validDigest (value : String) : Bool :=
  value.length == 64 && value.toList.all (fun character =>
    "0123456789abcdef".contains character)

private def canonicalPlanHash (plan : Plan) : String :=
  Crypto.sha256Hex <| ("pf.noir.plan.v1\u0000" ++
    reprStr plan.targetDescriptor ++ "\u0000" ++
    reprStr plan.semanticSchemaVersion ++ "\u0000" ++
    reprStr plan.codegenProfile ++ "\u0000" ++
    reprStr plan.sourceDialect ++ "\u0000" ++
    reprStr plan.continuity ++ "\u0000" ++
    reprStr plan.failurePolicy ++ "\u0000" ++
    reprStr plan.proofStatus ++ "\u0000" ++
    reprStr plan.resourceLimits ++ "\u0000" ++
    reprStr plan.programName ++ "\u0000" ++
    reprStr plan.sourceHash ++ "\u0000" ++
    reprStr plan.semanticHash ++ "\u0000" ++
    reprStr plan.states ++ "\u0000" ++
    reprStr plan.relations).toUTF8

private def artifactStem (index : Nat) (mode : RelationMode) (name : String) : String :=
  let suffix := if mode == .initialize then "init" else name
  s!"r{index}-{suffix}"

private def inputVisibility : Semantic.Visibility → CompileResult InputVisibility
  | .verifierVisible => .ok .verifier
  | .proverWitness => .ok .witness
  | .commitmentOnly => planError "commitment-only inputs need an explicit commitment extension"

private def makeStates (states : Array Semantic.StateDecl) : CompileResult (Array StateField) := do
  if states.size > maxStateFields then
    throw <| .planInvariant .noir s!"state count exceeds profile limit {maxStateFields}"
  let mut planned : Array StateField := #[]
  for state in states do
    unless state.type == .u64 do
      throw <| .planInvariant .noir s!"state '{state.name}' is not UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .noir s!"state name '{state.name}' is not a safe identifier"
    unless state.id.value == planned.size do
      throw <| .planInvariant .noir "semantic state ids must match declaration order"
    planned := planned.push { sourceId := state.id.value, name := state.name }
  if hasDuplicates (planned.map (·.name)) then
    throw <| .planInvariant .noir "state names must be unique"
  return planned

private def makeParams (owner : String) (inputOffset : Nat)
    (params : Array Semantic.Param) : CompileResult (Array Param) := do
  if params.size > maxParams then
    throw <| .planInvariant .noir s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  for param in params do
    unless param.type == .u64 do
      throw <| .planInvariant .noir s!"parameter '{param.name}' in {owner} is not UInt64"
    unless isIdentifier param.name do
      throw <| .planInvariant .noir
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    unless param.id.value == planned.size do
      throw <| .planInvariant .noir
        s!"semantic parameter ids in {owner} must match declaration order"
    planned := planned.push {
      sourceId := param.id.value
      name := param.name
      inputIndex := inputOffset + planned.size
      visibility := ← inputVisibility param.visibility
    }
  if hasDuplicates (planned.map (·.name)) then
    throw <| .planInvariant .noir s!"parameter names in {owner} must be unique"
  return planned

private def makeInputs (states : Array StateField) (mode : RelationMode)
    (params : Array Param) : Array InputBinding := Id.run do
  let mut inputs : Array InputBinding := #[]
  if !states.isEmpty then
    inputs := inputs.push {
      name := "pre_initialized"
      sourceName := "initialized"
      type := .bool
      visibility := .verifier
      role := .preInitialized
    }
  if mode != .initialize then
    for field in states do
      inputs := inputs.push {
        name := s!"pre_s{field.sourceId}"
        sourceName := field.name
        type := .u64
        visibility := .verifier
        role := .preState field.sourceId
      }
  for param in params do
    inputs := inputs.push {
      name := s!"arg_p{param.sourceId}"
      sourceName := param.name
      type := .u64
      visibility := param.visibility
      role := .parameter param.sourceId
    }
  for field in states do
    inputs := inputs.push {
      name := s!"post_s{field.sourceId}"
      sourceName := field.name
      type := .u64
      visibility := .verifier
      role := .postState field.sourceId
    }
  if !states.isEmpty then
    inputs := inputs.push {
      name := "post_initialized"
      sourceName := "initialized"
      type := .bool
      visibility := .verifier
      role := .postInitialized
    }
  if mode != .initialize then
    inputs := inputs.push {
      name := "result"
      sourceName := "result"
      type := .u64
      visibility := .verifier
      role := .result
    }
  return inputs

private def findState (states : Array StateField)
    (id : Semantic.StateId) : CompileResult StateField :=
  match states.find? (·.sourceId == id.value) with
  | some field => .ok field
  | none => planError s!"semantic expression references unknown state id {id.value}"

private def findParam (params : Array Param)
    (id : Semantic.ParamId) : CompileResult Param :=
  match params.find? (·.sourceId == id.value) with
  | some param => .ok param
  | none => planError s!"semantic expression references unknown parameter id {id.value}"

private partial def semanticExprNodes? (depthLeft nodeBudget : Nat)
    (expr : Semantic.Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. | .param .. | .state .. => some 1
    | .checkedAdd lhs rhs =>
        let available := nodeBudget - 1
        match semanticExprNodes? (depthLeft - 1) available lhs with
        | none => none
        | some lhsNodes =>
            match semanticExprNodes? (depthLeft - 1) (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addSemanticExprNodes (total : Nat)
    (expr : Semantic.Expr) : CompileResult Nat :=
  match semanticExprNodes? maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError
      s!"semantic expression exceeds depth {maxExprDepth} or aggregate node limit {maxPlanNodes}"

private def validateSemanticBudget (program : Semantic.Program) : CompileResult Unit := do
  if program.state.size > maxStateFields || program.entries.isEmpty ||
      program.entries.size + (if program.initializer.isSome then 1 else 0) > maxRelations then
    throw <| .planInvariant .noir "semantic relation/state count is outside profile limits"
  let initializerNodes := program.initializer.map (fun initializer =>
    1 + initializer.params.size + initializer.body.size) |>.getD 0
  let entryNodes := program.entries.foldl (fun total entry =>
    total + 1 + entry.params.size + entry.body.size) 0
  let mut total := program.state.size + initializerNodes + entryNodes
  if total > maxPlanNodes then
    throw <| .planInvariant .noir s!"semantic program exceeds aggregate node limit {maxPlanNodes}"
  if let some initializer := program.initializer then
    if initializer.params.size > maxParams || initializer.body.size > maxBodyStatements then
      throw <| .planInvariant .noir "initializer exceeds profile resource limits"
    for statement in initializer.body do
      match statement with
      | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
      | .synchronousCall .. => pure ()
  for entry in program.entries do
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .noir s!"entry '{entry.name}' exceeds profile resource limits"
    for statement in entry.body do
      match statement with
      | .store _ value | .returnValue value => total ← addSemanticExprNodes total value
      | .synchronousCall .. => pure ()

private partial def makeExprUnchecked (states : Array StateField) (params : Array Param) :
    Semantic.Expr → CompileResult Expr
  | .literal value => .ok <| .literal value
  | .param id => return .param (← findParam params id).inputIndex
  | .state id => return .stateLoad (← findState states id).sourceId
  | .checkedAdd lhs rhs => do
      let lhs ← makeExprUnchecked states params lhs
      let rhs ← makeExprUnchecked states params rhs
      return .checkedAdd lhs rhs

private def makeExpr (states : Array StateField) (params : Array Param)
    (expr : Semantic.Expr) : CompileResult Expr := do
  let _ ← addSemanticExprNodes 0 expr
  makeExprUnchecked states params expr

private def makeBody (states : Array StateField) (params : Array Param)
    (owner : String) (mode : RelationMode)
    (body : Array Semantic.Statement) : CompileResult (Array Statement) := do
  let mut planned : Array Statement := #[]
  for statement in body do
    match statement with
    | .store state value =>
        if mode == .view then
          throw <| .planInvariant .noir s!"view relation '{owner}' writes state"
        let field ← findState states state
        planned := planned.push <| .store {
          fieldIndex := field.sourceId
          value := ← makeExpr states params value
        }
    | .returnValue value =>
        if mode == .initialize then
          throw <| .planInvariant .noir "initializer relation cannot return a value"
        planned := planned.push <| .returnValue (← makeExpr states params value)
    | .synchronousCall callee =>
        throw <| .planInvariant .noir
          s!"call '{callee}' in {owner} cannot be represented by a circuit relation"
  return planned

private def makeRelation (index : Nat) (states : Array StateField)
    (name : String) (mode : RelationMode) (semanticParams : Array Semantic.Param)
    (semanticBody : Array Semantic.Statement) : CompileResult Relation := do
  unless isIdentifier name do
    throw <| .planInvariant .noir s!"relation name '{name}' is not a safe identifier"
  let inputOffset := if states.isEmpty then 0 else
    1 + (if mode == .initialize then 0 else states.size)
  let params ← makeParams s!"relation '{name}'" inputOffset semanticParams
  let relation : Relation := {
    index
    name
    artifactStem := artifactStem index mode name
    mode
    params
    inputs := makeInputs states mode params
    body := ← makeBody states params name mode semanticBody
  }
  return relation

private partial def planExprNodes? (states : Array StateField) (inputs : Array InputBinding)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param inputIndex =>
        match inputs[inputIndex]? with
        | some input => if let .parameter .. := input.role then some 1 else none
        | none => none
    | .stateLoad fieldIndex => if fieldIndex < states.size then some 1 else none
    | .checkedAdd lhs rhs =>
        let available := nodeBudget - 1
        match planExprNodes? states inputs (depthLeft - 1) available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? states inputs (depthLeft - 1) (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (plan : Plan) (relation : Relation)
    (total : Nat) (expr : Expr) : CompileResult Nat :=
  match planExprNodes? plan.states relation.inputs plan.resourceLimits.maxExprDepth
      (plan.resourceLimits.maxPlanNodes - total) expr with
  | some nodes => .ok (total + nodes)
  | none => planError "relation expression has a dangling reference or exceeds resource limits"

private def expectedParams (states : Array StateField)
    (relation : Relation) : Array Param :=
  let inputOffset := if states.isEmpty then 0 else
    1 + (if relation.mode == .initialize then 0 else states.size)
  relation.params.mapIdx fun index param => {
    param with sourceId := index, inputIndex := inputOffset + index
  }

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
    (if relation.mode == .initialize then 0 else 1)
  unless relation.inputs.size == expectedInputCount do
    throw <| .planInvariant .noir "relation input count is outside the canonical envelope"
  unless relation.index == expectedIndex && isIdentifier relation.name &&
      relation.artifactStem == artifactStem expectedIndex relation.mode relation.name do
    throw <| .planInvariant .noir "relation identity/artifact stem is not canonical"
  unless relation.params.all (fun param => isIdentifier param.name) &&
      !hasDuplicates (relation.params.map (·.name)) do
    throw <| .planInvariant .noir "relation parameter names are not canonical"
  unless relation.params == expectedParams plan.states relation &&
      relation.inputs == makeInputs plan.states relation.mode relation.params do
    throw <| .planInvariant .noir "relation parameters/input disclosure are not canonical"
  let mut total := baseNodes
  let mut returned := false
  for statement in relation.body do
    if returned then
      throw <| .planInvariant .noir s!"relation '{relation.name}' has a statement after return"
    match statement with
    | .store store =>
        if relation.mode == .view then
          throw <| .planInvariant .noir s!"view relation '{relation.name}' writes state"
        unless store.fieldIndex < plan.states.size do
          throw <| .planInvariant .noir s!"relation '{relation.name}' stores unknown state"
        total ← addPlanExprNodes plan relation total store.value
    | .returnValue value =>
        if relation.mode == .initialize then
          throw <| .planInvariant .noir "initializer relation cannot return a value"
        total ← addPlanExprNodes plan relation total value
        returned := true
  if relation.mode == .initialize then
    if returned then
      throw <| .planInvariant .noir "initializer relation cannot return a value"
  else unless returned do
    throw <| .planInvariant .noir s!"relation '{relation.name}' does not return UInt64"
  return total

/-- Validate the complete target-owned relation catalog before typed lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == Semantic.schemaVersion &&
      plan.codegenProfile == codegenProfile && plan.sourceDialect == sourceDialect &&
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

def makePlan (resolved : ResolvedProgram .noir) : CompileResult Plan := do
  unless resolved.descriptor == descriptor do
    throw <| .planInvariant .noir "resolved target descriptor does not match the Noir profile"
  let source := resolved.source
  unless source.schemaVersion == Semantic.schemaVersion do
    throw <| .planInvariant .noir
      s!"semantic schema version {source.schemaVersion} is not supported"
  unless source.requirements == Semantic.deriveRequirements source do
    throw <| .planInvariant .noir "semantic requirements are not canonical for the program body"
  validateSemanticBudget source
  let states ← makeStates source.state
  if states.isEmpty && source.initializer.isSome then
    throw <| .planInvariant .noir "stateless circuit programs cannot declare an initializer"
  if !states.isEmpty && source.initializer.isNone then
    throw <| .planInvariant .noir "stateful circuit programs require an initializer relation"
  let mut relations : Array Relation := #[]
  if let some initializer := source.initializer then
    relations := relations.push <| ← makeRelation 0 states "init" .initialize
      initializer.params initializer.body
  for entry in source.entries do
    unless entry.result == .u64 do
      throw <| .planInvariant .noir s!"entry '{entry.name}' does not return UInt64"
    let mode := match entry.mode with
      | .mutate => RelationMode.mutate
      | .view => RelationMode.view
    relations := relations.push <| ← makeRelation relations.size states entry.name mode
      entry.params entry.body
  let unsignedPlan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := Semantic.schemaVersion
    codegenProfile
    sourceDialect
    continuity := if states.isEmpty then .none else .externalPublicPrePost
    failurePolicy := .unsatisfied
    proofStatus := .notProduced
    resourceLimits := canonicalLimits
    programName := source.name
    sourceHash := source.sourceHash
    semanticHash := source.semanticHash
    planHash := String.ofList (List.replicate 64 '0')
    states
    relations
  }
  let plan := { unsignedPlan with planHash := canonicalPlanHash unsignedPlan }
  validatePlan plan
  return plan

private structure LoweredExpr where
  operations : Array Operation
  value : ValueRef
  next : Nat
  deriving Inhabited

private partial def lowerExpr (stateValues : Array ValueRef) (next : Nat) : Expr → LoweredExpr
  | .literal value => { operations := #[], value := .literal value, next }
  | .param inputIndex => { operations := #[], value := .input inputIndex, next }
  | .stateLoad fieldIndex => { operations := #[], value := stateValues[fieldIndex]!, next }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr stateValues next lhs
      let rhs := lowerExpr stateValues lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }

private def inputIndexFor (relation : Relation) (role : InputRole) : Nat := Id.run do
  for index in [0:relation.inputs.size] do
    if relation.inputs[index]!.role == role then return index
  return 0

private def lowerRelation (plan : Plan) (relation : Relation) : RelationIR := Id.run do
  let mut stateValues : Array ValueRef := #[]
  for field in plan.states do
    stateValues := stateValues.push <| if relation.mode == .initialize then
      .literal 0
    else
      .input (inputIndexFor relation (.preState field.sourceId))
  let mut operations : Array Operation := #[]
  if !plan.states.isEmpty then
    operations := operations.push <| .assertBool
      (inputIndexFor relation .preInitialized) (relation.mode != .initialize)
  let mut next := 0
  let mut returned : Option ValueRef := none
  for statement in relation.body do
    match statement with
    | .store store =>
        let value := lowerExpr stateValues next store.value
        operations := operations ++ value.operations
        stateValues := stateValues.set! store.fieldIndex value.value
        next := value.next
    | .returnValue value =>
        let value := lowerExpr stateValues next value
        operations := operations ++ value.operations
        returned := some value.value
        next := value.next
  for field in plan.states do
    operations := operations.push <| .assertEqual
      (.input (inputIndexFor relation (.postState field.sourceId)))
      stateValues[field.sourceId]!
  if !plan.states.isEmpty then
    operations := operations.push <| .assertBool
      (inputIndexFor relation .postInitialized) true
  if relation.mode != .initialize then
    operations := operations.push <| .assertEqual
      (.input (inputIndexFor relation .result)) returned.get!
  return { sourceRelation := relation, tempCount := next, operations }

private def expectedRelations (plan : Plan) : Array RelationIR :=
  plan.relations.map (lowerRelation plan)

private def addLiveTemp (live : Array Nat) : ValueRef → Array Nat
  | .temp index => if live.contains index then live else live.push index
  | .input .. | .literal .. => live

/-- Noir may eliminate an unused checked integer expression, including its
overflow failure. Until the source profile emits a dedicated non-elidable
overflow constraint, reject every checked addition that is not transitively
consumed by a final equality assertion. -/
private def validateCheckedAddLiveness (relation : RelationIR) : CompileResult Unit := do
  let mut live : Array Nat := #[]
  for offset in [0:relation.operations.size] do
    let operation := relation.operations[relation.operations.size - 1 - offset]!
    match operation with
    | .assertEqual lhs rhs =>
        live := addLiveTemp (addLiveTemp live lhs) rhs
    | .assertBool .. => pure ()
    | .checkedAdd destination lhs rhs =>
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relation.sourceRelation.name}' contains dead checked arithmetic whose overflow would not be constrained"
        live := addLiveTemp (addLiveTemp live lhs) rhs

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName &&
      ir.relations.size == ir.sourcePlan.relations.size do
    throw <| .planInvariant .noir "typed Noir IR identity/catalog is not bound to its Plan"
  let limit := ir.sourcePlan.resourceLimits.maxIrOperations
  let mut operationCount := 0
  for relation in ir.relations do
    if relation.tempCount > limit - operationCount then
      throw <| .planInvariant .noir "typed Noir IR exceeds operation limit"
    operationCount := operationCount + relation.tempCount
    if relation.operations.size > limit - operationCount then
      throw <| .planInvariant .noir "typed Noir IR exceeds operation limit"
    operationCount := operationCount + relation.operations.size
    validateCheckedAddLiveness relation
  unless ir.relations == expectedRelations ir.sourcePlan do
    throw <| .planInvariant .noir
      "typed Noir IR operations are not the exact lowering of their source Plan"

def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    relations := expectedRelations plan
  }
  validateIR ir
  return ir

private def renderValue (relation : Relation) : ValueRef → String
  | .input index => relation.inputs[index]!.name
  | .literal value => toString value.toNat
  | .temp index => s!"t{index}"

private def renderOperation (relation : Relation) : Operation → String
  | .checkedAdd destination lhs rhs =>
      s!"    let t{destination}: u64 = {renderValue relation lhs} + {renderValue relation rhs};\n"
  | .assertEqual lhs rhs =>
      s!"    assert({renderValue relation lhs} == {renderValue relation rhs});\n"
  | .assertBool inputIndex expected =>
      s!"    assert({relation.inputs[inputIndex]!.name} == {if expected then "true" else "false"});\n"

private def renderInput (input : InputBinding) : String :=
  let visibility := if input.visibility == .verifier then "pub " else ""
  let type := if input.type == .u64 then "u64" else "bool"
  s!"{input.name}: {visibility}{type}"

private def renderSource (relation : RelationIR) : String :=
  let signature := String.intercalate ", " <|
    relation.sourceRelation.inputs.toList.map renderInput
  let operations := String.intercalate "" <|
    relation.operations.toList.map (renderOperation relation.sourceRelation)
  s!"fn main({signature}) \{\n" ++ operations ++ "}\n"

private def renderPackage (relation : Relation) : String :=
  "[package]\n" ++
    s!"name = \"pf_relation_{relation.index}\"\n" ++
    "type = \"bin\"\n" ++
    "authors = [\"ProofForge V2\"]\n"

private def renderMode : RelationMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderVisibility : InputVisibility → String
  | .verifier => "public"
  | .witness => "private-witness"

private def renderInputJson (input : InputBinding) : String :=
  let (role, sourceId) := match input.role with
    | .preInitialized => ("pre-initialized", "null")
    | .preState id => ("pre-state", toString id)
    | .parameter id => ("parameter", toString id)
    | .postState id => ("post-state", toString id)
    | .postInitialized => ("post-initialized", "null")
    | .result => ("result", "null")
  let type := if input.type == .u64 then "u64" else "bool"
  "{" ++
    s!"\"name\":\"{Targets.escapeJson input.name}\"," ++
    s!"\"sourceName\":\"{Targets.escapeJson input.sourceName}\"," ++
    s!"\"sourceId\":{sourceId}," ++
    s!"\"role\":\"{role}\"," ++
    s!"\"visibility\":\"{renderVisibility input.visibility}\"," ++
    s!"\"type\":\"{type}\"}"

private def renderRelationJson (relation : RelationIR) : String :=
  let inputs := String.intercalate "," <|
    relation.sourceRelation.inputs.toList.map renderInputJson
  "{" ++
    s!"\"index\":{relation.sourceRelation.index}," ++
    s!"\"name\":\"{Targets.escapeJson relation.sourceRelation.name}\"," ++
    s!"\"mode\":\"{renderMode relation.sourceRelation.mode}\"," ++
    s!"\"package\":\"relations/{relation.sourceRelation.artifactStem}\"," ++
    s!"\"operationCount\":{relation.operations.size}," ++
    s!"\"inputs\":[{inputs}]}"

private def renderInterface (ir : IR) : String :=
  let relations := String.intercalate ",\n    " <|
    ir.relations.toList.map renderRelationJson
  let continuity := if ir.sourcePlan.continuity == .none then "none" else "external-public-pre-post"
  "{\n" ++
    "  \"schema\": \"proof-forge-noir-relations/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson ir.name}\",\n" ++
    s!"  \"codegenProfile\": \"{ir.sourcePlan.codegenProfile}\",\n" ++
    s!"  \"sourceDialect\": \"{ir.sourcePlan.sourceDialect}\",\n" ++
    s!"  \"sourceHash\": \"{ir.sourcePlan.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{ir.sourcePlan.semanticHash}\",\n" ++
    s!"  \"planHash\": \"{ir.sourcePlan.planHash}\",\n" ++
    "  \"artifactKind\": \"source-only\",\n" ++
    s!"  \"stateContinuity\": \"{continuity}\",\n" ++
    "  \"arithmetic\": \"native-checked-u64\",\n" ++
    "  \"proofStatus\": \"not-produced\",\n" ++
    "  \"relations\": [\n    " ++ relations ++ "\n  ]\n" ++
    "}\n"

def emit (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  let mut files : Array OutputFile := #[{
    path := s!"{ir.name}.noir-relations.json"
    mediaType := "application/json"
    contents := renderInterface ir
  }]
  for relation in ir.relations do
    let root := s!"relations/{relation.sourceRelation.artifactStem}"
    files := files.push {
      path := s!"{root}/src/main.nr"
      mediaType := "text/x-noir"
      contents := renderSource relation
    }
    files := files.push {
      path := s!"{root}/Nargo.toml"
      mediaType := "text/toml"
      contents := renderPackage relation.sourceRelation
    }
  return files

instance : Materializer .noir where
  Plan := Plan
  TargetIR := IR
  makePlan := makePlan
  lower := lower
  emit := emit

def materialize (program : SemanticProgram) : CompileResult OutputSet := do
  let resolved ← Targets.resolve descriptor program
  let plan ← makePlan resolved
  let ir ← lower plan
  let files ← emit ir
  return Targets.makeOutput descriptor program false files

end ProofForgeV2.Targets.Noir
