import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Noir

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

def codegenProfileString : String := "noir-source-u64-relations-v1"
def codegenProfile : CodegenProfileId := CodegenProfileId.noirSourceU64RelationsV1
def sourceDialect : String := "noir-native-u64-relations-v1"

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.noir

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

/-- Native UInt64 comparison operators for Noir relation expressions. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (inputIndex : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  | assert (condition : Expr)
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
  -- No Inhabited: Plan embeds TargetDescriptor (opaque TargetId/profile).
  deriving BEq, Repr

inductive ValueRef where
  | input (index : Nat)
  | literal (value : UInt64)
  | temp (index : Nat)
  deriving BEq, Inhabited, Repr

inductive Operation where
  | checkedAdd (destination : Nat) (lhs rhs : ValueRef)
  | checkedSub (destination : Nat) (lhs rhs : ValueRef)
  | assertEqual (lhs rhs : ValueRef)
  | assertBool (inputIndex : Nat) (expected : Bool)
  | compare (op : ComparisonOp) (destination : Nat) (lhs rhs : ValueRef)
  | assertConstraint (condition : ValueRef)
  deriving BEq, Inhabited, Repr

structure RelationIR where
  sourceRelation : Relation
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Exact typed circuit recipe. Rendering source is later than Plan-to-IR
validation so source strings cannot rediscover business semantics.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`). -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  relations : Array RelationIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

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

/-- Transitional deterministic descriptor preimage for the engineering Noir
plan hash. It serializes only target/profile/axis identity and deliberately
excludes requirement support; the exact resolver index is the sole current
support authority. This is not the formal D3 TargetSemantics/Profile digest. -/
def targetDescriptorEngineeringReprV1 (d : TargetDescriptor) : String :=
  let targetIdWire (id : TargetId) : String :=
    s!"ProofForgeV2.TargetId.{id.toString}"
  let codegenProfileWire (profile : CodegenProfileId) : String :=
    -- Profile grammar forbids escapes, so quoted UTF-8 is unambiguous here.
    s!"\"{profile.toString}\""
  "{ targetId := " ++ targetIdWire d.targetId ++ ",\n" ++
  "  artifactEncoding := " ++ reprStr d.artifactEncoding ++ ",\n" ++
  "  executionHost := " ++ reprStr d.executionHost ++ ",\n" ++
  "  commitModel := " ++ reprStr d.commitModel ++ ",\n" ++
  "  stateBinding := " ++ reprStr d.stateBinding ++ ",\n" ++
  "  callModel := " ++ reprStr d.callModel ++ ",\n" ++
  "  proofModel := " ++ reprStr d.proofModel ++ ",\n" ++
  "  settlementModel := " ++ reprStr d.settlementModel ++ ",\n" ++
  "  codegenProfile := " ++ codegenProfileWire d.codegenProfile ++ " }"

private def canonicalPlanHash (plan : Plan) : String :=
  Crypto.sha256Hex <| ("pf.noir.plan.v1\u0000" ++
    targetDescriptorEngineeringReprV1 plan.targetDescriptor ++ "\u0000" ++
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

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

/-- Value kinds admitted in the Noir pilot value table. Bool may be intermediate
(comparison/literal results feeding assert) or an entry/view result binding;
state and params stay UInt64-only. -/
private inductive NoirValueKindV1 where
  | uint64
  | bool
  deriving BEq, Inhabited, Repr

private structure NoirTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1

private def validateNoirTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult NoirTypeClosureV1 := do
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  for decl in types do
    unless decl.name.isNone do
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: named types are outside the current UInt64 pilot"
    match decl.shape with
    | .uint width =>
        unless width.toNat == 64 && uint64TypeId.isNone do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: expected one anonymous UInt64 type"
        uint64TypeId := some decl.id
    | .unit =>
        unless unitTypeId.isNone do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: duplicate Unit type"
        unitTypeId := some decl.id
    | .bool =>
        unless boolTypeId.isNone do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: duplicate Bool type"
        boolTypeId := some decl.id
    | _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: only UInt64, Unit, and Bool are supported"
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (.planInvariant .noir
        "unsupported Noir semantic shape: UInt64 type is missing")
  pure { uint64TypeId := resolvedUInt64TypeId, unitTypeId, boolTypeId }

private def makeStatesV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult (Array StateField) := do
  if states.size > maxStateFields then
    throw <| .planInvariant .noir s!"state count exceeds profile limit {maxStateFields}"
  let mut planned : Array StateField := #[]
  for state in states do
    unless state.id.toNat == planned.size do
      throw <| .planInvariant .noir "semantic state ids must match declaration order"
    unless state.typeId == uint64TypeId && state.visibility == .public_ do
      throw <| .planInvariant .noir s!"state '{state.name}' is not public UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .noir s!"state name '{state.name}' is not a safe identifier"
    planned := planned.push { sourceId := state.id.toNat, name := state.name }
  if hasDuplicates (planned.map (·.name)) then
    throw <| .planInvariant .noir "state names must be unique"
  pure planned

private structure LoweredValueV1 where
  expr : Expr
  kind : NoirValueKindV1
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  deriving Inhabited

private def makeParamsV1 (owner : String) (inputOffset : Nat)
    (uint64TypeId : TypeIdV1) (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .noir s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .noir
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless param.typeId == uint64TypeId && param.visibility == .public_ do
      throw <| .planInvariant .noir
        s!"parameter '{param.name}' in {owner} is not public UInt64"
    unless isIdentifier param.name do
      throw <| .planInvariant .noir
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      inputIndex := inputOffset + planned.size
      visibility := .verifier
    }
    planned := planned.push binding
    values := values.push {
      expr := .param binding.inputIndex
      kind := .uint64
      depth := 1
      expandedNodes := 1
      dependencies := #[]
    }
  if hasDuplicates (planned.map (·.name)) then
    throw <| .planInvariant .noir s!"parameter names in {owner} must be unique"
  pure (planned, values)

/-- Build the canonical public-input envelope. `resultType` is used only for
    non-initializer relations (entry/view) and is ignored for `.initialize`. -/
private def makeInputsV1 (states : Array StateField) (mode : RelationMode)
    (params : Array Param) (resultType : InputType) : Array InputBinding := Id.run do
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
      type := resultType
      visibility := .verifier
      role := .result
    }
  pure inputs

private def resultInputTypeOf (relation : Relation) : InputType :=
  match relation.inputs.find? (fun binding => binding.role == .result) with
  | some binding => binding.type
  | none => .u64

private def findStateV1 (states : Array StateField)
    (id : StateIdV1) : CompileResult StateField :=
  match states[id.toNat]? with
  | some field =>
      if field.sourceId == id.toNat then .ok field
      else planError s!"semantic expression references noncanonical state id {id.toNat}"
  | none => planError s!"semantic expression references unknown state id {id.toNat}"

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| .planInvariant .noir "unsupported Noir semantic shape: invalid UInt64 literal"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: trailing UInt64 literal bytes"

/-- Decode a SemanticProgramV1 Bool literal (exactly one byte `0x00`/`0x01`).
    Represented as UInt64 0/1 inside the plan Expr surface. -/
private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 1 do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: Bool literal must contain exactly 1 byte"
  match bytes.get! 0 with
  | 0 => pure 0
  | 1 => pure 1
  | _ =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: Bool literal byte must be 0x00 or 0x01"

private def currentValueV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart then
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == .uint64 && rhs.kind == .uint64 do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: checked add operands must be UInt64"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .checkedAdd lhs.expr rhs.expr
    kind := .uint64
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == .uint64 && rhs.kind == .uint64 do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: checked sub operands must be UInt64"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .checkedSub lhs.expr rhs.expr
    kind := .uint64
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def binaryOpToComparisonV1 : BinaryOpV1 → Option ComparisonOp
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == .uint64 && rhs.kind == .uint64 do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: comparison operands must be UInt64"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .noir s!"Noir plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .compare op lhs.expr rhs.expr
    kind := .bool
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueV1 values paramCount segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  if root.toNat >= paramCount then
    stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: dead or reordered value instructions"
  pure rootValue.expr

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: result ValueId/type is not canonical for the instruction"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .noir s!"Noir value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

/-- `returnKind = none` for initializer (no return value). For entry/view it is
    the admitted result kind (UInt64 or Bool) and must match the returned value. -/
private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (inputOffset : Nat)
    (types : NoirTypeClosureV1)
    (states : Array StateField)
    (returnKind : Option NoirValueKindV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && callable.blocks.size == 1 &&
      callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: callable must be one acyclic entry block"
  let block ← match callable.blocks[0]? with
    | some value => pure value
    | none => throw (.planInvariant .noir
        "unsupported Noir semantic shape: callable entry block is missing")
  unless block.id.toNat == 0 && block.params.isEmpty do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: block parameters are not supported"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .noir
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let uint64TypeId := types.uint64TypeId
  let (params, initialValues) ← makeParamsV1 owner inputOffset uint64TypeId callable.params
  let paramCount := params.size
  let mut values := initialValues
  let mut segmentStart := values.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 uint64TypeId values result {
            expr := .literal value
            kind := .uint64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if types.boolTypeId == some typeId then
          let value ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind := .bool
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: literal is not UInt64 or Bool"
    | .stateLoad stateId, some result =>
        let field ← findStateV1 states stateId
        values := ← appendResultValueV1 uint64TypeId values result {
          expr := .stateLoad field.sourceId
          kind := .uint64
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueV1 values paramCount segmentStart lhsId
        let rhs ← currentValueV1 values paramCount segmentStart rhsId
        if op == .add then
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 uint64TypeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 uint64TypeId values result value
        else
          match binaryOpToComparisonV1 op with
          | some comparison =>
              let boolTypeId ← match types.boolTypeId with
                | some value => pure value
                | none => throw (.planInvariant .noir
                    "unsupported Noir semantic shape: comparison requires interned Bool type")
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .noir
                  "unsupported Noir semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 comparison lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTypeId values result value
          | none =>
              throw <| .planInvariant .noir
                "unsupported Noir semantic shape: only checked UInt64 add/sub and comparisons are supported"
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: view callable writes state"
        let field ← findStateV1 states stateId
        let root ← currentValueV1 values paramCount segmentStart valueId
        unless root.kind == .uint64 do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: state store value must be UInt64"
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
        body := body.push (.store { fieldIndex := field.sourceId, value })
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: assert must use errorId=none and empty args"
        let root ← currentValueV1 values paramCount segmentStart condId
        unless root.kind == .bool do
          throw <| .planInvariant .noir
            "unsupported Noir semantic shape: assert condition must be Bool"
        let condition ← consumeCurrentSegmentV1 values paramCount segmentStart condId
        body := body.push (.assert condition)
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: instruction op/result is outside the current UInt64 pilot"
  match mode, block.terminator with
  | .initialize, .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: initializer has unconsumed values"
  | .mutate, .return_ (some valueId)
  | .view, .return_ (some valueId) =>
      let expectedKind ← match returnKind with
        | some kind => pure kind
        | none =>
            throw <| .planInvariant .noir
              "unsupported Noir semantic shape: entry/view return kind is missing"
      let root ← currentValueV1 values paramCount segmentStart valueId
      unless root.kind == expectedKind do
        throw <| .planInvariant .noir
          s!"unsupported Noir semantic shape: return value kind is not consistent with the {owner} result type"
      let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
      body := body.push (.returnValue value)
      segmentStart := values.size
  | .initialize, .return_ (some _) =>
      throw <| .planInvariant .noir "initializer relation cannot return a value"
  | _, _ =>
      throw <| .planInvariant .noir
        "unsupported Noir semantic shape: callable terminator is outside the current UInt64 pilot"
  unless segmentStart == values.size do
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: callable has unconsumed values"
  if body.size > maxBodyStatements then
    throw <| .planInvariant .noir s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def resolveEntryViewResultV1
    (types : NoirTypeClosureV1)
    (name : String)
    (callable : CallableV1) : CompileResult (NoirValueKindV1 × InputType) := do
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .noir s!"entry '{name}' does not return a public UInt64 or Bool"
  if callable.result.typeId == types.uint64TypeId then
    pure (.uint64, .u64)
  else if types.boolTypeId == some callable.result.typeId then
    pure (.bool, .bool)
  else
    throw <| .planInvariant .noir s!"entry '{name}' does not return public UInt64 or Bool"

private def makeRelationV1
    (index : Nat)
    (types : NoirTypeClosureV1)
    (states : Array StateField)
    (name : String)
    (mode : RelationMode)
    (callable : CallableV1) : CompileResult Relation := do
  unless isIdentifier name do
    throw <| .planInvariant .noir s!"relation name '{name}' is not a safe identifier"
  let returnKind : Option NoirValueKindV1 ←
    if mode == .initialize then
      unless callable.name.isNone && callable.result.visibility == .public_ do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: initializer signature is invalid"
      let unitTypeId ← match types.unitTypeId with
        | some value => pure value
        | none => throw (.planInvariant .noir
            "unsupported Noir semantic shape: initializer Unit type is missing")
      unless callable.result.typeId == unitTypeId do
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: initializer result is not Unit"
      pure none
    else
      let (kind, _) ← resolveEntryViewResultV1 types name callable
      pure (some kind)
  let resultType : InputType := match returnKind with
    | some .bool => .bool
    | some .uint64 | none => .u64
  let inputOffset := if states.isEmpty then 0 else
    1 + (if mode == .initialize then 0 else states.size)
  let semanticMode : SemanticCallableModeV1 := match mode with
    | .initialize => .initialize
    | .mutate => .mutate
    | .view => .view
  let lowered ← lowerCallableV1 s!"relation '{name}'" semanticMode inputOffset
    types states returnKind callable
  pure {
    index
    name
    artifactStem := artifactStem index mode name
    mode
    params := lowered.params
    inputs := makeInputsV1 states mode lowered.params resultType
    body := lowered.body
  }

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
    | .checkedSub lhs rhs =>
        let available := nodeBudget - 1
        match planExprNodes? states inputs (depthLeft - 1) available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? states inputs (depthLeft - 1) (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .compare _ lhs rhs =>
        let available := nodeBudget - 1
        match planExprNodes? states inputs (depthLeft - 1) available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? states inputs (depthLeft - 1) (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (plan : Plan) (relation : Relation)
    (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .noir "Noir Plan exceeds aggregate node limit"
  match planExprNodes? plan.states relation.inputs plan.resourceLimits.maxExprDepth
      (plan.resourceLimits.maxPlanNodes - total) expr with
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
  let expectedResultType := resultInputTypeOf relation
  unless relation.params == expectedParams plan.states relation &&
      relation.inputs == makeInputsV1 plan.states relation.mode relation.params
        expectedResultType do
    throw <| .planInvariant .noir "relation parameters/input disclosure are not canonical"
  if relation.mode != .initialize then
    unless expectedResultType == .u64 || expectedResultType == .bool do
      throw <| .planInvariant .noir
        s!"relation '{relation.name}' result type is outside the UInt64/Bool pilot"
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
    | .assert condition =>
        total ← addPlanExprNodes plan relation total condition
  if relation.mode == .initialize then
    if returned then
      throw <| .planInvariant .noir "initializer relation cannot return a value"
  else unless returned do
    throw <| .planInvariant .noir s!"relation '{relation.name}' does not return a value"
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

/-- Noir-private retained SemanticProgramV1 data → target-owned Plan pilot.
    Name/source/semantic identity comes from the same non-alpha compiled carrier;
    hash strings are derived from sourceHashV1/semanticHashV1 digests. -/
private def makePlanFromSemanticDataV1
    (artifactProgramName sourceHash semanticHash : String)
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.events.isEmpty || !source.errors.isEmpty ||
      !source.invariants.isEmpty then
    throw <| .planInvariant .noir
      "unsupported Noir semantic shape: constants/events/errors/invariants are outside the current UInt64 pilot"
  if source.callables.size > maxRelations then
    throw <| .planInvariant .noir s!"callable count exceeds Noir profile limit {maxRelations}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .noir
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateNoirTypeClosureV1 source.types
  let states ← makeStatesV1 types.uint64TypeId source.logicalState
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  unless programName == artifactProgramName do
    throw <| .planInvariant .noir
      "retained SemanticProgramV1 name diverges from compiled artifact identity"
  let mut initializer : Option CallableV1 := none
  let mut entries : Array CallableV1 := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .noir "semantic program has multiple initializers"
        initializer := some callable
    | .entry | .view => entries := entries.push callable
    | .pureFn | .invariant =>
        throw <| .planInvariant .noir
          "unsupported Noir semantic shape: pure functions/invariants are outside the current UInt64 pilot"
  if states.isEmpty && initializer.isSome then
    throw <| .planInvariant .noir "stateless circuit programs cannot declare an initializer"
  if !states.isEmpty && initializer.isNone then
    throw <| .planInvariant .noir "stateful circuit programs require an initializer relation"
  let mut relations : Array Relation := #[]
  if let some initCallable := initializer then
    relations := relations.push (← makeRelationV1 0 types states "init" .initialize initCallable)
  for callable in entries do
    let name ← match callable.name with
      | some value => pure value
      | none => throw (.planInvariant .noir
          "unsupported Noir semantic shape: named entry is missing its name")
    let mode : RelationMode := match callable.kind with
      | .entry => .mutate
      | .view => .view
      | _ => .mutate
    relations := relations.push (← makeRelationV1 relations.size types states name mode callable)
  let unsignedPlan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := semanticProgramSchemaVersionV1
    codegenProfile := codegenProfileString
    sourceDialect
    continuity := if states.isEmpty then .none else .externalPublicPrePost
    failurePolicy := .unsatisfied
    proofStatus := .notProduced
    resourceLimits := canonicalLimits
    programName
    sourceHash
    semanticHash
    planHash := String.ofList (List.replicate 64 '0')
    states
    relations
  }
  let plan := { unsignedPlan with planHash := canonicalPlanHash unsignedPlan }
  validatePlan plan
  pure plan

private def makePlanFromSemanticV1
    (artifactProgramName sourceHash semanticHash : String)
    (source : SemanticProgramV1) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Noir received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 artifactProgramName sourceHash semanticHash data

/-- Capability-gated public plan entry. Plan semantics and identity are both
    derived from the single retained-semantic compiled carrier. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .noir do
    throw <| .planInvariant .noir "engineering capability kind is not Noir"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let sourceHash ← CompiledSemanticV1.artifactSourceHashHexOf compiled
  let semanticHash ← CompiledSemanticV1.artifactSemanticHashHexOf compiled
  makePlanFromSemanticV1
    (CompiledSemanticV1.artifactProgramNameOf compiled)
    sourceHash
    semanticHash
    source

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
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr stateValues next lhs
      let rhs := lowerExpr stateValues lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := .temp rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr stateValues next lhs
      let rhs := lowerExpr stateValues lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare op rhs.next lhs.value rhs.value]
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
    | .assert condition =>
        let value := lowerExpr stateValues next condition
        operations := operations ++ value.operations ++
          #[.assertConstraint value.value]
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
failure constraint. Reject every checked add/sub/compare result that is not
transitively consumed by a final equality or assert constraint. -/
private def validateCheckedArithmeticLiveness
    (relation : RelationIR) : CompileResult Unit := do
  let mut live : Array Nat := #[]
  for offset in [0:relation.operations.size] do
    let operation := relation.operations[relation.operations.size - 1 - offset]!
    match operation with
    | .assertEqual lhs rhs =>
        live := addLiveTemp (addLiveTemp live lhs) rhs
    | .assertConstraint condition =>
        live := addLiveTemp live condition
    | .assertBool .. => pure ()
    | .checkedAdd destination lhs rhs
    | .checkedSub destination lhs rhs
    | .compare _ destination lhs rhs =>
        unless live.contains destination do
          throw <| .planInvariant .noir
            s!"relation '{relation.sourceRelation.name}' contains dead checked arithmetic whose failure would not be constrained"
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
    validateCheckedArithmeticLiveness relation
  unless ir.relations == expectedRelations ir.sourcePlan do
    throw <| .planInvariant .noir
      "typed Noir IR operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
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

private def renderComparisonOp : ComparisonOp → String
  | .eq => "=="
  | .ne => "!="
  | .lt => "<"
  | .le => "<="
  | .gt => ">"
  | .ge => ">="

/-- Render a condition ValueRef for `assert(...)`. Bool plan literals are
encoded as UInt64 0/1 and surface as native Noir `true`/`false`. -/
private def renderAssertCondition (relation : Relation) : ValueRef → String
  | .literal 0 => "false"
  | .literal 1 => "true"
  | value => renderValue relation value

/-- True when an assertEqual involves a Bool-typed public input (result or
    lifecycle flag). Bool plan literals are UInt64 0/1 and must surface as
    native Noir `true`/`false` on the equality. -/
private def assertEqualUsesBool (relation : Relation) (lhs rhs : ValueRef) : Bool :=
  let isBoolInput : ValueRef → Bool
    | .input index =>
        match relation.inputs[index]? with
        | some input => input.type == .bool
        | none => false
    | _ => false
  isBoolInput lhs || isBoolInput rhs

private def renderEqualOperand (relation : Relation) (asBool : Bool) :
    ValueRef → String
  | .literal value =>
      if asBool then
        if value == 0 then "false" else "true"
      else
        toString value.toNat
  | value => renderValue relation value

private def renderOperation (relation : Relation) : Operation → String
  | .checkedAdd destination lhs rhs =>
      s!"    let t{destination}: u64 = {renderValue relation lhs} + {renderValue relation rhs};\n"
  | .checkedSub destination lhs rhs =>
      s!"    assert({renderValue relation lhs} >= {renderValue relation rhs});\n" ++
        s!"    let t{destination}: u64 = {renderValue relation lhs} - {renderValue relation rhs};\n"
  | .assertEqual lhs rhs =>
      let asBool := assertEqualUsesBool relation lhs rhs
      s!"    assert({renderEqualOperand relation asBool lhs} == {renderEqualOperand relation asBool rhs});\n"
  | .assertBool inputIndex expected =>
      s!"    assert({relation.inputs[inputIndex]!.name} == {if expected then "true" else "false"});\n"
  | .compare op destination lhs rhs =>
      s!"    let t{destination}: bool = {renderValue relation lhs} {renderComparisonOp op} {renderValue relation rhs};\n"
  | .assertConstraint condition =>
      s!"    assert({renderAssertCondition relation condition});\n"

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

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
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

/-- Replace relations on an existing IR (private `mk`; for validateIR characterization). -/
def withRelations (ir : IR) (relations : Array RelationIR) : IR :=
  { ir with relations }

/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← planFromCapability capability
  lower plan

/-- Capability-gated public materialize entry (S6). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

instance : Materializer .noir where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Noir
