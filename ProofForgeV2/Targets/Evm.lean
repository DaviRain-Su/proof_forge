import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Evm.Keccak

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.evm

/-- Target-owned binding from a semantic state identity to an EVM storage slot. -/
structure StorageBinding where
  sourceId : Nat
  name : String
  slot : Nat
  deriving BEq, Inhabited, Repr

/-- Target-owned ABI word binding. `sourceId` is retained only for traceability;
all lowering after plan construction uses `wordIndex`. -/
structure Param where
  sourceId : Nat
  name : String
  wordIndex : Nat
  deriving BEq, Inhabited, Repr

/-- Unsigned comparison ops over UInt64 operands. Result is a Bool word (0/1)
in Yul; operator identity is preserved through Plan validation. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

/-- EVM scalar expression for the Phase-1 UInt64 fragment. Storage slots and
ABI word positions have already been selected by the plan builder. -/
inductive Expr where
  | literal (value : UInt64)
  | param (wordIndex : Nat)
  | storageLoad (slot : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  /-- Pure local call: `fnIndex` indexes `Plan.fns`; args are UInt64 expressions.
  Result kind is the callee's declared result (UInt64 or Bool). Not an effect
  boundary — stays inside a value segment like checkedAdd. -/
  | callFn (fnIndex : Nat) (args : Array Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  slot : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  | returnNone
  | assert (condition : Expr)
  | emitEvent (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  deriving BEq, Inhabited, Repr

/-- Constructor carries store-only `stores` for the historical store-only path
(byte-identical Yul) and an ordered `body` when asserts interleave with stores.
When `body` is non-empty it is the sole validation/render authority; when empty,
`stores` is used (aggregate Plan-mutation tests still target `stores`). -/
structure Constructor where
  params : Array Param
  stores : Array Store
  body : Array Statement := #[]
  deriving BEq, Inhabited, Repr

inductive Mutability where
  | nonpayable
  | view
  deriving BEq, Inhabited, Repr

/-- Declared ABI result kind for an entry/view. Params and state remain UInt64-only;
Bool is admitted only as the callable result (and as body intermediate values). -/
inductive ResultKind where
  | uint64
  | bool
  deriving BEq, Inhabited, Repr

structure Entry where
  name : String
  selector : String
  params : Array Param
  mutability : Mutability
  body : Array Statement
  /-- ABI/result kind. Default `.uint64` keeps historical Plan constructors and
  non-Bool goldens byte-identical. -/
  resultKind : ResultKind := .uint64
  deriving BEq, Inhabited, Repr

/-- One declared event/error binding: its name and UInt64 argument count,
    from which the canonical ABI signature and Keccak topic/selector derive. -/
structure InterfaceBinding where
  name : String
  fieldCount : Nat
  deriving BEq, Inhabited, Repr

/-- Target-owned pure function binding. Bodies are lowered from pureFn callables
    (no store/emit); params mirror ABI-word Param layout for rendering only. -/
structure FnBinding where
  name : String
  params : Array Param
  body : Array Statement
  resultIsBool : Bool
  deriving BEq, Inhabited, Repr

/-- Complete EVM decisions for the currently supported portable fragment.
The renderer consumes this value without consulting `SemanticProgram`. -/
structure Plan where
  objectName : String
  runtimeObjectName : String
  storageLayout : Array StorageBinding
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  constructor : Option Constructor
  entries : Array Entry
  /-- Dense pureFn table in source-order of pureFn callables. Default empty
  keeps historical Plan literals byte-identical. -/
  fns : Array FnBinding := #[]
  deriving BEq, Inhabited, Repr

structure IR where
  objectName : String
  yul : String
  abi : String
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .evm message

-- Profile-owned resource limits. They bound selector hashing and the current
-- array-based uniqueness checks before target lowering performs expensive work.
private def maxIdentifierBytes : Nat := 240
private def maxArtifactStemBytes : Nat := 231
private def maxStorageBindings : Nat := 1024
private def maxEntries : Nat := 1024
private def maxParams : Nat := 256
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxPlanNodes : Nat := 100000

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
        rest.all (fun character => isAsciiLetter character || isAsciiDigit character || character == '_')

private def hasDuplicates [BEq α] (values : Array α) : Bool := Id.run do
  let mut seen : Array α := #[]
  for value in values do
    if seen.contains value then return true
    seen := seen.push value
  return false

private def validSelector (selector : String) : Bool :=
  selector.length == 8 && selector.toList.all (fun character =>
    "0123456789abcdef".contains character)

private structure EvmTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1

/-- EVM pilot accepts the anonymous UInt64/Unit/Bool closure currently emitted
    by the NormalizeV1 public-UInt64 comparison+assert envelope. Valid but richer
    SemanticProgramV1 programs fail at the target Plan seam rather than being
    silently erased. Bool is optional (at most one): admitted as body intermediate
    values and as entry/view results; state/params remain UInt64-only. -/
private def validateEvmTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult EvmTypeClosureV1 := do
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  for decl in types do
    unless decl.name.isNone do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: named types are outside the current UInt64 pilot"
    match decl.shape with
    | .uint width =>
        unless width.toNat == 64 && uint64TypeId.isNone do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: expected one anonymous UInt64 type"
        uint64TypeId := some decl.id
    | .unit =>
        unless unitTypeId.isNone do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: duplicate Unit type"
        unitTypeId := some decl.id
    | .bool =>
        unless boolTypeId.isNone do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: duplicate Bool type"
        boolTypeId := some decl.id
    | _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: only UInt64, Unit, and Bool are supported"
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: UInt64 type is missing")
  pure { uint64TypeId := resolvedUInt64TypeId, unitTypeId, boolTypeId }

private def makeStorageLayoutV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult (Array StorageBinding) := do
  if states.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
  let mut layout : Array StorageBinding := #[]
  for state in states do
    unless state.id.toNat == layout.size do
      throw <| .planInvariant .evm "semantic state ids must match declaration order"
    unless state.typeId == uint64TypeId && state.visibility == .public_ do
      throw <| .planInvariant .evm s!"state '{state.name}' is not public UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .evm s!"state name '{state.name}' is not an EVM ABI identifier"
    layout := layout.push {
      sourceId := state.id.toNat
      name := state.name
      slot := layout.size
    }
  return layout

private structure LoweredValueV1 where
  expr : Expr
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  /-- Defensive kind bit: true for comparison results and Bool literals only.
  State loads, params, and checked arithmetic are always false. -/
  isBool : Bool
  deriving Inhabited

private def makeParamsV1 (owner : String) (uint64TypeId : TypeIdV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .evm s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .evm
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless param.typeId == uint64TypeId && param.visibility == .public_ do
      throw <| .planInvariant .evm
        s!"parameter '{param.name}' in {owner} is not public UInt64"
    unless isIdentifier param.name do
      throw <| .planInvariant .evm
        s!"parameter name '{param.name}' in {owner} is not an EVM ABI identifier"
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      wordIndex := planned.size
    }
    planned := planned.push binding
    values := values.push {
      expr := .param binding.wordIndex
      depth := 1
      expandedNodes := 1
      dependencies := #[]
      isBool := false
    }
  return (planned, values)

private def findStorageV1 (layout : Array StorageBinding)
    (id : StateIdV1) : CompileResult StorageBinding :=
  match layout[id.toNat]? with
  | some binding =>
      if binding.sourceId == id.toNat then .ok binding
      else planError s!"semantic expression references noncanonical state id {id.toNat}"
  | none => planError s!"semantic expression references unknown state id {id.toNat}"

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: invalid UInt64 literal"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: trailing UInt64 literal bytes"

private def currentValueV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Match-bind arm readability: the scrutinee of an enclosing switch may be
    referenced by its arm bodies across the (dominating) scrut-block boundary.
    All other cross-block reads still fail at the effect boundary. -/
private def currentValueWithArmsV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart && !armReadables.contains id then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Shared bounded SSA-tree cost for binary Expr constructors. `isBool` tags
    comparison results; arithmetic is always UInt64. -/
private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  unless !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: binary operands must be UInt64"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
    isBool
  }

/-- Compute expanded tree cost before constructing an EVM Expr node. A shared
    SSA operand counts once per use, so `add(v,v)` doubles the expanded cost. -/
private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedAdd lhsId rhsId lhs rhs false

/-- Subtraction has the same bounded SSA-tree cost as addition; its distinct
    constructor preserves the source operator through Plan validation/Yul. -/
private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedSub lhsId rhsId lhs rhs false

/-- Comparison has the same bounded SSA-tree cost as checked arithmetic. -/
private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true

/-- PureCall tree cost: one node plus each argument tree (SSA args counted per
    use). Result kind is the callee's declared result. -/
private def makeCallFnValueV1
    (fnIndex : Nat)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  for arg in args do
    unless !arg.isBool do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: pureCall arguments must be UInt64"
  let mut depth : Nat := 0
  let mut expandedNodes : Nat := 0
  for arg in args do
    depth := max depth arg.depth
    if expandedNodes > maxPlanNodes - arg.expandedNodes then
      throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
    expandedNodes := expandedNodes + arg.expandedNodes
  depth := 1 + depth
  if expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  if depth > maxExprDepth then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds depth {maxExprDepth}"
  pure {
    expr := .callFn fnIndex (args.map (·.expr))
    depth
    expandedNodes := 1 + expandedNodes
    dependencies := argIds
    isBool
  }

private def resolveFnIndexV1
    (fnIndexByCallableId : Array (Option Nat))
    (callableId : CallableIdV1) : CompileResult Nat :=
  match fnIndexByCallableId[callableId.toNat]? with
  | some (some fnIndex) => pure fnIndex
  | _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: pureCall targets a non-pureFn callable"

private def comparisonOpOfBinaryV1 (op : BinaryOpV1) : Option ComparisonOp :=
  match op with
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 1 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Bool literal must contain exactly 1 byte"
  let b := bytes.get! 0
  unless b == 0 || b == 1 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Bool literal must be 0x00 or 0x01"
  pure (UInt64.ofNat b.toNat)

/-- Every instruction result emitted since the prior stateStore must be in the
    current sink's dependency closure. This preserves the current NormalizeV1
    evaluation regions instead of deferring stale state loads or checked failures across a
    storage effect. -/
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
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: dead or reordered value instructions"
  pure rootValue.expr

/-- Multi-root effect-boundary consumption (event/revert argument lists):
    every value produced in the current segment must be reachable from at
    least one sink root, mirroring the single-root discipline. -/
private def consumeSegmentRootsV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (roots : Array ValueIdV1) : CompileResult Unit := do
  for root in roots do
    let _ ← currentValueV1 values paramCount segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  for root in roots do
    if root.toNat >= paramCount then
      stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: result ValueId/type is not canonical for the expected type"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .evm s!"EVM value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private inductive SemanticCallableModeV1 where
  | constructor
  | entry
  | view
  /-- pureFn body: same return/value rules as entry, but storage/effects banned. -/
  | pureFn
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  stores : Array Store
  body : Array Statement

private structure LoweredBlockV1 where
  statements : Array Statement
  values : Array LoweredValueV1
  segmentStart : Nat
  hasAssert : Bool

/-- Lower one block's instruction sequence (terminator handled by the region
    walker). Each block starts a fresh effect segment; values from dominating
    blocks stay referenceable only via params or match-arm scrutinees. -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  let uint64TypeId := types.uint64TypeId
  unless block.id.toNat < 1000000 && block.params.isEmpty do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: block parameters are not supported"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .evm
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let mut segmentStart := values0.size
  let mut body : Array Statement := #[]
  let mut hasAssert := false
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 uint64TypeId values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := false
          }
        else
          let boolTid ← match types.boolTypeId with
            | some tid => pure tid
            | none => throw (.planInvariant .evm
                "unsupported EVM semantic shape: Bool literal requires anonymous Bool type")
          unless typeId == boolTid do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: literal is not UInt64 or Bool"
          let value ← decodeBoolLiteralV1 bytes
          -- Bool words are 0/1 UInt64 literals in the Plan expression surface,
          -- tagged isBool so return/assert/store kind gates remain defensive.
          values := ← appendResultValueV1 boolTid values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := true
          }
    | .stateLoad stateId, some result =>
        if mode == .pureFn then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: pureFn body loads storage"
        let binding ← findStorageV1 layout stateId
        values := ← appendResultValueV1 uint64TypeId values result {
          expr := .storageLoad binding.slot
          depth := 1
          expandedNodes := 1
          dependencies := #[]
          isBool := false
        }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables rhsId
        if op == .add then
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 uint64TypeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 uint64TypeId values result value
        else
          match comparisonOpOfBinaryV1 op with
          | none =>
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: only checked UInt64 add/sub and comparisons are supported"
          | some cmpOp =>
              let boolTid ← match types.boolTypeId with
                | some tid => pure tid
                | none => throw (.planInvariant .evm
                    "unsupported EVM semantic shape: comparison requires anonymous Bool type")
              unless result.typeId == boolTid do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTid values result value
    | .pureCall callableId argIds, some result =>
        -- Not an effect boundary: callFn is a value expression inside the segment.
        let fnIndex ← resolveFnIndexV1 fnIndexByCallableId callableId
        let fnBinding ← match fns[fnIndex]? with
          | some binding => pure binding
          | none => throw (.planInvariant .evm
              "unsupported EVM semantic shape: pureCall fnIndex is out of range")
        unless argIds.size == fnBinding.params.size do
          throw <| .planInvariant .evm
            s!"unsupported EVM semantic shape: pureCall arity mismatch for '{fnBinding.name}'"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let arg ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless !arg.isBool do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: pureCall arguments must be UInt64"
          argValues := argValues.push arg
        let value ← makeCallFnValueV1 fnIndex argIds argValues fnBinding.resultIsBool
        if fnBinding.resultIsBool then
          let boolTid ← match types.boolTypeId with
            | some tid => pure tid
            | none => throw (.planInvariant .evm
                "unsupported EVM semantic shape: Bool pureCall requires anonymous Bool type")
          unless result.typeId == boolTid do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: pureCall result type must match callee Bool"
          values := ← appendResultValueV1 boolTid values result value
        else
          unless result.typeId == uint64TypeId do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: pureCall result type must match callee UInt64"
          values := ← appendResultValueV1 uint64TypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view || mode == .pureFn then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: view/pureFn callable writes storage"
        let stored ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
        unless !stored.isBool do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: state store value must be UInt64"
        let binding ← findStorageV1 layout stateId
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
        let store : Store := { slot := binding.slot, value }
        body := body.push (.store store)
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: assert must have errorId=none and empty args"
        let condVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
        unless condVal.isBool do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: assert condition must be Bool"
        let cond ← consumeCurrentSegmentV1 values paramCount segmentStart condId
        body := body.push (.assert cond)
        hasAssert := true
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view || mode == .pureFn then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: view/pureFn callable emits an event"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless !root.isBool do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        hasAssert := true
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart, hasAssert }

/-- Decode a switch case constant against the scrutinee kind. -/
private def decodeSwitchCaseValueV1 (scrutIsBool : Bool) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if scrutIsBool then
    decodeBoolLiteralV1 bytes
  else
    decodeUInt64LiteralV1 bytes

/-- Structured emission of the forward-only multi-block CFG. Diamonds
    (branch/switch) are recovered by following each arm to its exit jump or
    return; convergent joins continue the region. The fuel bounds recursion
    to the block count. Returns (statements, values, nextJoin, hasAssert,
    hasControlRegion). -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (blocks : Array BlockV1)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (expectedResultKind : Option ResultKind)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × Option Nat × Bool × Bool) := do
  if fuel == 0 then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: CFG region exceeds block bound"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: block ids are not dense"
  let lowered ← lowerBlockInstructionsV1
    owner mode types layout fnIndexByCallableId fns paramCount armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  let hA := lowered.hasAssert
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .constructor =>
          throw <| .planInvariant .evm "constructor cannot return a value"
      | .entry | .view | .pureFn =>
          let expected ← match expectedResultKind with
            | some kind => pure kind
            | none => throw (.planInvariant .evm
                "unsupported EVM semantic shape: entry/view/pureFn return missing expected result kind")
          let returned ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
          match expected with
          | .uint64 =>
              unless !returned.isBool do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: return value must be UInt64"
          | .bool =>
              unless returned.isBool do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: return value must be Bool"
          let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
          pure (instrs.push (.returnValue value), values, none, hA, false)
  | .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, none, hA, false)
  | .jump target =>
      unless segmentStart == values.size do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: block has unconsumed values"
      pure (instrs, values, some target.blockId.toNat, hA, false)
  | .branch condId thenT elseT =>
      let condVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
      unless condVal.isBool do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values paramCount segmentStart condId
      let (thenBody, values1, thenNext, hA1, _) ←
        emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
          armReadables expectedResultKind (fuel - 1) thenT.blockId.toNat values
      match thenNext with
      | some j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, next, hA2, _) ←
              emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
                armReadables expectedResultKind (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest,
              values2, next, hA || hA1 || hA2, true)
          else
            let (elseBody, values2, elseNext, hA2, _) ←
              emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
                armReadables expectedResultKind (fuel - 1) elseT.blockId.toNat values1
            match elseNext with
            | some j2 =>
                unless j == j2 do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: branch arms converge on divergent joins"
                let (rest, values3, next, hA3, _) ←
                  emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
                    armReadables expectedResultKind (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, next, hA || hA1 || hA2 || hA3, true)
            | none =>
                let (rest, values3, next, hA3, _) ←
                  emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
                    armReadables expectedResultKind (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, next, hA || hA1 || hA2 || hA3, true)
      | none =>
          let (elseBody, values2, elseNext, hA2, _) ←
            emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
              armReadables expectedResultKind (fuel - 1) elseT.blockId.toNat values1
          pure (instrs ++ #[.ifThenElse cond thenBody elseBody],
            values2, elseNext, hA || hA1 || hA2, true)
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables scrutId
      let scrut ← consumeCurrentSegmentV1 values paramCount segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .evm
          "unsupported EVM semantic shape: switch must carry a default target")
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      let mut hAAcc := hA
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutVal.isBool switchCase.valueBytes
        let (body, values1, armNext, hA1, _) ←
          emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
            (armReadables.push scrutId) expectedResultKind (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        hAAcc := hAAcc || hA1
        match armNext, joinAcc with
        | none, _ => pure ()
        | some j, none => joinAcc := some j
        | some j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: switch arms converge on divergent joins"
      let (defaultBody, values2, defaultNext, hA2, _) ←
        emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
          (armReadables.push scrutId) expectedResultKind (fuel - 1)
          defaultT.blockId.toNat valuesA
      hAAcc := hAAcc || hA2
      match defaultNext, joinAcc with
      | none, _ => pure ()
      | some j, none => joinAcc := some j
      | some j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: switch arms converge on divergent joins"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody],
            values2, none, hAAcc, true)
      | some j =>
          let (rest, values3, next, hA3, _) ←
            emitRegionV1 owner mode types layout fnIndexByCallableId fns blocks paramCount
              armReadables expectedResultKind (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest,
            values3, next, hAAcc || hA3, true)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
        unless !root.isBool do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values paramCount segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, none, hA, false)
  | .trap _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: trap terminators are outside the current pilot"

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (callable : CallableV1)
    (expectedResultKind : Option ResultKind) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: callable must have an acyclic entry block"
  unless callable.blocks.all (fun b => b.params.isEmpty) do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: block parameters are not supported"
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  let paramCount := params.size
  let (body0, values0, nextJoin0, hA0, hasRegion0) ←
    emitRegionV1 owner mode types layout fnIndexByCallableId fns callable.blocks paramCount #[]
      expectedResultKind callable.blocks.size 0 initialValues
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG, so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextJoin := nextJoin0
  let mut hasAssert := hA0
  let mut hasRegion := hasRegion0
  for _ in [0:callable.blocks.size] do
    match nextJoin with
    | none => break
    | some j =>
        let (rest, values1, next1, hA1, hasRegion1) ←
          emitRegionV1 owner mode types layout fnIndexByCallableId fns callable.blocks paramCount #[]
            expectedResultKind callable.blocks.size j values
        body := body ++ rest
        values := values1
        nextJoin := next1
        hasAssert := hasAssert || hA1
        hasRegion := hasRegion || hasRegion1
  match nextJoin with
  | some _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: callable does not end in return on all paths"
  | none => pure ()
  if body.size > maxBodyStatements then
    throw <| .planInvariant .evm s!"{owner} body exceeds profile limit {maxBodyStatements}"
  -- Constructor store-only path keeps `stores` authoritative (aggregate
  -- mutation tests target it); asserts/control regions require ordered body.
  let mut stores : Array Store := #[]
  if mode == .constructor && !hasAssert && !hasRegion then
    for statement in body do
      match statement with
      | .store store => stores := stores.push store
      | _ => pure ()
  let constructorBody :=
    if mode == .constructor && !hasAssert && !hasRegion then #[] else body
  let constructorStores :=
    if mode == .constructor && !hasAssert && !hasRegion then stores else #[]
  let entryBody := if mode == .constructor then constructorBody else body
  let entryStores := if mode == .constructor then constructorStores else #[]
  pure { params, stores := entryStores, body := entryBody }

private def makeConstructorV1
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (callable : CallableV1) : CompileResult Constructor := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: initializer result is not Unit"
  let lowered ← lowerCallableV1 "constructor" .constructor types layout
    fnIndexByCallableId fns callable none
  pure {
    params := lowered.params
    stores := lowered.stores
    body := lowered.body
  }

private def makeEntryV1
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (callable : CallableV1) : CompileResult Entry := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .evm s!"entry name '{name}' is not an EVM ABI identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .evm s!"entry '{name}' does not return public UInt64 or Bool"
  let resultKind : ResultKind ←
    if callable.result.typeId == types.uint64TypeId then
      pure .uint64
    else if types.boolTypeId == some callable.result.typeId then
      pure .bool
    else
      throw <| .planInvariant .evm s!"entry '{name}' does not return public UInt64 or Bool"
  let mode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .entry
    | .view => pure .view
    | _ => throw (.planInvariant .evm
        "unsupported EVM semantic shape: callable is not an entry or view")
  let mutability : Mutability := match mode with
    | .entry => .nonpayable
    | .view => .view
    | .constructor | .pureFn => .nonpayable
  let lowered ← lowerCallableV1 s!"entry '{name}'" mode types layout
    fnIndexByCallableId fns callable (some resultKind)
  pure {
    name
    selector := Keccak.selector name (lowered.params.map fun _ => "uint64")
    params := lowered.params
    mutability
    body := lowered.body
    resultKind
  }

/-- Lower one pureFn callable into a dense Plan fn binding. Signatures in
    `fns` must already be populated so nested pureCall can resolve arity/kind. -/
private def makeFnV1
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (callable : CallableV1) : CompileResult FnBinding := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: pureFn is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .evm s!"fn name '{name}' is not an EVM ABI identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .evm s!"fn '{name}' does not return public UInt64 or Bool"
  let resultIsBool : Bool ←
    if callable.result.typeId == types.uint64TypeId then
      pure false
    else if types.boolTypeId == some callable.result.typeId then
      pure true
    else
      throw <| .planInvariant .evm s!"fn '{name}' does not return public UInt64 or Bool"
  let resultKind : ResultKind := if resultIsBool then .bool else .uint64
  let lowered ← lowerCallableV1 s!"fn '{name}'" .pureFn types layout
    fnIndexByCallableId fns callable (some resultKind)
  pure {
    name
    params := lowered.params
    body := lowered.body
    resultIsBool
  }

private partial def planExprNodes? (slots : Array Nat) (paramCount depthLeft nodeBudget : Nat)
    (fns : Array FnBinding) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param wordIndex => if wordIndex < paramCount then some 1 else none
    | .storageLoad slot => if slots.contains slot then some 1 else none
    | .checkedAdd lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available fns lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) fns rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .checkedSub lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available fns lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) fns rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available fns lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) fns rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .callFn fnIndex args =>
        match fns[fnIndex]? with
        | none => none
        | some binding =>
            if args.size != binding.params.size then
              none
            else
              -- Args must be UInt64-compatible (no compare / Bool-returning callFn).
              let argsOk := args.all fun arg =>
                match arg with
                | .compare .. => false
                | .callFn nestedIdx _ =>
                    match fns[nestedIdx]? with
                    | some nested => !nested.resultIsBool
                    | none => false
                | _ => true
              if !argsOk then
                none
              else
                let childDepth := depthLeft - 1
                Id.run do
                  let mut available := nodeBudget - 1
                  let mut total : Nat := 1
                  let mut ok := true
                  for arg in args do
                    match planExprNodes? slots paramCount childDepth available fns arg with
                    | none => ok := false
                    | some nodes =>
                        total := total + nodes
                        available := available - nodes
                  if ok then some total else none

private def addPlanExprNodes (slots : Array Nat) (paramCount total : Nat)
    (fns : Array FnBinding) (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? slots paramCount maxExprDepth (maxPlanNodes - total) fns expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .evm
        s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private def addPlanStoreNodes (slots : Array Nat) (paramCount total : Nat)
    (fns : Array FnBinding) (store : Store) : CompileResult Nat := do
  unless slots.contains store.slot do
    throw <| .planInvariant .evm "plan store references an unknown storage slot"
  addPlanExprNodes slots paramCount total fns store.value

/-- Structural Bool-producer: comparison is always Bool. Bool literals are
    surface-encoded as `.literal 0`/`.literal 1` and are accepted only where a
    Bool kind is required (return/assert). callFn uses the callee result flag. -/
private def exprIsCompareV1 : Expr → Bool
  | .compare .. => true
  | _ => false

private def exprIsBoolLiteralV1 : Expr → Bool
  | .literal value => value == 0 || value == 1
  | _ => false

private def exprIsBoolCompatibleV1 (fns : Array FnBinding) (expr : Expr) : Bool :=
  match expr with
  | .compare .. => true
  | .literal value => value == 0 || value == 1
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some binding => binding.resultIsBool
      | none => false
  | _ => false

/-- UInt64-compatible: everything except comparison and Bool-returning callFn.
    Literals/params/loads/arithmetic remain UInt64, including 0/1 which also
    double as Bool words when resultKind demands it. -/
private def exprIsUInt64CompatibleV1 (fns : Array FnBinding) (expr : Expr) : Bool :=
  match expr with
  | .compare .. => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some binding => !binding.resultIsBool
      | none => false
  | _ => true

/-- Recursive statement-tree validator: kind gates, view-write ban (including
    inside branches), node accounting, and per-level return ordering. Returns
    the updated node total and whether execution of this statement list always
    ends in a return on every path. A bare-return marker is accepted only at
    the top level of a constructor body (`allowReturnNone`); early bare returns
    inside branch arms fail closed (the constructor deployment epilogue must
    run on every path, which a mid-arm halt would skip). -/
private partial def checkPlanStatementsV1
    (owner : String) (isConstructor : Bool) (isView : Bool)
    (resultKind : ResultKind) (slots : Array Nat) (paramCount : Nat)
    (allowReturnNone : Bool)
    (eventCount : Nat) (eventFieldCounts : Array Nat)
    (errorCount : Nat) (errorFieldCounts : Array Nat)
    (fns : Array FnBinding)
    (statements : Array Statement) (total : Nat) :
    CompileResult (Nat × Bool) := do
  let mut total := total
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .evm s!"{owner} has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} writes storage in a view context"
        unless exprIsUInt64CompatibleV1 fns store.value do
          throw <| .planInvariant .evm
            s!"{owner} cannot store a Bool-typed expression into a UInt64 slot"
        total ← addPlanStoreNodes slots paramCount total fns store
    | .assert condition =>
        unless exprIsBoolCompatibleV1 fns condition do
          throw <| .planInvariant .evm
            s!"{owner} assert condition must be a Bool-typed expression"
        total ← addPlanExprNodes slots paramCount total fns condition
    | .returnValue value =>
        if isConstructor then
          throw <| .planInvariant .evm "constructor cannot return a value"
        match resultKind with
        | .uint64 =>
            unless exprIsUInt64CompatibleV1 fns value do
              throw <| .planInvariant .evm
                s!"{owner} resultKind uint64 is inconsistent with Bool return expression"
        | .bool =>
            unless exprIsBoolCompatibleV1 fns value do
              throw <| .planInvariant .evm
                s!"{owner} resultKind bool is inconsistent with UInt64 return expression"
        total ← addPlanExprNodes slots paramCount total fns value
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .evm
            s!"{owner} has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .evm s!"{owner} emits an event in a view context"
        unless eventIndex < eventCount do
          throw <| .planInvariant .evm s!"{owner} emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .evm s!"{owner} event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .evm
              s!"{owner} event arguments must be UInt64 expressions"
          total ← addPlanExprNodes slots paramCount total fns arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .evm s!"{owner} reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .evm s!"{owner} error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .evm
              s!"{owner} error arguments must be UInt64 expressions"
          total ← addPlanExprNodes slots paramCount total fns arg
        total := total + 1
        closed := true
    | .ifThenElse condition thenBody elseBody =>
        unless exprIsBoolCompatibleV1 fns condition do
          throw <| .planInvariant .evm
            s!"{owner} if condition must be a Bool-typed expression"
        total ← addPlanExprNodes slots paramCount total fns condition
        total := total + 1
        let (t1, c1) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns thenBody total
        let (t2, c2) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns elseBody t1
        total := t2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes slots paramCount total fns scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, c) ← checkPlanStatementsV1
            owner isConstructor isView resultKind slots paramCount false
            eventCount eventFieldCounts errorCount errorFieldCounts fns caseBody total
          total := t
          allClosed := allClosed && c
        let (td, cd) ← checkPlanStatementsV1
          owner isConstructor isView resultKind slots paramCount false
          eventCount eventFieldCounts errorCount errorFieldCounts fns defaultBody total
        total := td
        closed := allClosed && cd
  pure (total, closed)

/-- Validate the public `Evm.Plan` value before any Yul is produced. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless isIdentifier plan.objectName do
    throw <| .planInvariant .evm s!"object name '{plan.objectName}' is not a safe EVM identifier"
  if plan.objectName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .evm
      s!"object name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  unless isIdentifier plan.runtimeObjectName && plan.runtimeObjectName != plan.objectName do
    throw <| .planInvariant .evm "runtime object name must be safe and distinct from the containing object"
  if plan.entries.isEmpty then
    throw <| .planInvariant .evm "plan has no entries"
  if plan.storageLayout.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"storage layout exceeds profile limit {maxStorageBindings}"
  if plan.entries.size > maxEntries then
    throw <| .planInvariant .evm s!"entry count exceeds profile limit {maxEntries}"
  for binding in plan.storageLayout do
    unless isIdentifier binding.name do
      throw <| .planInvariant .evm s!"storage name '{binding.name}' is not a safe identifier"
  let stateIds := plan.storageLayout.map (·.sourceId)
  let stateNames := plan.storageLayout.map (·.name)
  let slots := plan.storageLayout.map (·.slot)
  if hasDuplicates stateIds || hasDuplicates stateNames || hasDuplicates slots then
    throw <| .planInvariant .evm "storage ids, names, and slots must each be unique"
  for binding in plan.events do
    unless isIdentifier binding.name && binding.fieldCount <= maxParams do
      throw <| .planInvariant .evm s!"event '{binding.name}' is not a canonical binding"
  if hasDuplicates (plan.events.map (·.name)) then
    throw <| .planInvariant .evm "event names must be unique"
  for binding in plan.errors do
    unless isIdentifier binding.name && binding.fieldCount <= maxParams do
      throw <| .planInvariant .evm s!"error '{binding.name}' is not a canonical binding"
  if hasDuplicates (plan.errors.map (·.name)) then
    throw <| .planInvariant .evm "error names must be unique"
  let eventFieldCounts := plan.events.map (·.fieldCount)
  let errorFieldCounts := plan.errors.map (·.fieldCount)
  for index in [0:plan.storageLayout.size] do
    unless plan.storageLayout[index]!.slot == index &&
        plan.storageLayout[index]!.sourceId == index do
      throw <| .planInvariant .evm "storage slots and semantic origins must match declaration order"
  let constructorNodes := plan.constructor.map (fun constructor =>
    let stmtCount :=
      if constructor.body.isEmpty then constructor.stores.size else constructor.body.size
    1 + constructor.params.size + stmtCount) |>.getD 0
  let entryNodes := plan.entries.foldl (fun total entry =>
    total + entry.params.size + entry.body.size) 0
  let fnNodes := plan.fns.foldl (fun total fn =>
    total + fn.params.size + fn.body.size) 0
  let mut totalPlanNodes :=
    plan.storageLayout.size + plan.entries.size + plan.fns.size +
      constructorNodes + entryNodes + fnNodes
  if totalPlanNodes > maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
  if plan.fns.size > maxEntries then
    throw <| .planInvariant .evm s!"fn count exceeds profile limit {maxEntries}"
  for fn in plan.fns do
    unless isIdentifier fn.name do
      throw <| .planInvariant .evm s!"fn name '{fn.name}' is not a safe identifier"
    if fn.params.size > maxParams || fn.body.size > maxBodyStatements then
      throw <| .planInvariant .evm s!"fn '{fn.name}' exceeds the profile resource limits"
    for index in [0:fn.params.size] do
      unless fn.params[index]!.wordIndex == index &&
          fn.params[index]!.sourceId == index do
        throw <| .planInvariant .evm
          s!"fn '{fn.name}' ABI words and semantic origins must be canonical"
      unless isIdentifier fn.params[index]!.name do
        throw <| .planInvariant .evm s!"fn '{fn.name}' parameter name is not a safe ABI identifier"
    let sourceIds := fn.params.map (·.sourceId)
    let names := fn.params.map (·.name)
    let words := fn.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm s!"fn '{fn.name}' parameter bindings must be unique"
  let fnNames := plan.fns.map (·.name)
  if hasDuplicates fnNames then
    throw <| .planInvariant .evm "fn names must be unique"
  if let some constructor := plan.constructor then
    let ctorBodySize :=
      if constructor.body.isEmpty then constructor.stores.size else constructor.body.size
    if constructor.params.size > maxParams || ctorBodySize > maxBodyStatements then
      throw <| .planInvariant .evm "constructor exceeds the profile resource limits"
    for index in [0:constructor.params.size] do
      unless constructor.params[index]!.wordIndex == index &&
          constructor.params[index]!.sourceId == index do
        throw <| .planInvariant .evm "constructor ABI words and semantic origins must be canonical"
      unless isIdentifier constructor.params[index]!.name do
        throw <| .planInvariant .evm "constructor parameter name is not a safe ABI identifier"
    let sourceIds := constructor.params.map (·.sourceId)
    let names := constructor.params.map (·.name)
    let words := constructor.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm "constructor parameter bindings must be unique"
    if constructor.body.isEmpty then
      for store in constructor.stores do
        unless exprIsUInt64CompatibleV1 plan.fns store.value do
          throw <| .planInvariant .evm
            "constructor cannot store a Bool-typed expression into a UInt64 slot"
        totalPlanNodes ← addPlanStoreNodes slots constructor.params.size totalPlanNodes
          plan.fns store
    else
      let (t, _) ← checkPlanStatementsV1 "constructor" true false .uint64
        slots constructor.params.size true
        plan.events.size eventFieldCounts plan.errors.size errorFieldCounts
        plan.fns constructor.body totalPlanNodes
      totalPlanNodes := t
  for entry in plan.entries do
    unless isIdentifier entry.name && validSelector entry.selector do
      throw <| .planInvariant .evm s!"entry '{entry.name}' has an invalid ABI identity"
    if entry.params.size > maxParams || entry.body.size > maxBodyStatements then
      throw <| .planInvariant .evm s!"entry '{entry.name}' exceeds the profile resource limits"
    for index in [0:entry.params.size] do
      unless entry.params[index]!.wordIndex == index &&
          entry.params[index]!.sourceId == index do
        throw <| .planInvariant .evm
          s!"entry '{entry.name}' ABI words and semantic origins must be canonical"
      unless isIdentifier entry.params[index]!.name do
        throw <| .planInvariant .evm s!"entry '{entry.name}' parameter name is not a safe ABI identifier"
  let entryNames := plan.entries.map (·.name)
  let selectors := plan.entries.map (·.selector)
  if hasDuplicates entryNames then
    throw <| .planInvariant .evm "entry names must be unique"
  if hasDuplicates selectors then
    throw <| .planInvariant .evm "entry selectors collide"
  for entry in plan.entries do
    let expectedSelector := Keccak.selector entry.name (entry.params.map fun _ => "uint64")
    unless entry.selector == expectedSelector do
      throw <| .planInvariant .evm
        s!"entry '{entry.name}' selector is not bound to its canonical ABI signature"
    let sourceIds := entry.params.map (·.sourceId)
    let names := entry.params.map (·.name)
    let words := entry.params.map (·.wordIndex)
    if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates words then
      throw <| .planInvariant .evm s!"entry '{entry.name}' parameter bindings must be unique"
    if entry.body.isEmpty then
      throw <| .planInvariant .evm s!"entry '{entry.name}' has no body"
    let (t, returned) ← checkPlanStatementsV1 s!"entry '{entry.name}'" false
      (entry.mutability == .view) entry.resultKind slots entry.params.size
      false plan.events.size eventFieldCounts plan.errors.size errorFieldCounts
      plan.fns entry.body totalPlanNodes
    totalPlanNodes := t
    unless returned do
      throw <| .planInvariant .evm s!"entry '{entry.name}' does not return"
  -- pureFn bodies: no store/emit (isView=true), must return, result kind from flag.
  for fn in plan.fns do
    if fn.body.isEmpty then
      throw <| .planInvariant .evm s!"fn '{fn.name}' has no body"
    let resultKind : ResultKind := if fn.resultIsBool then .bool else .uint64
    let (t, returned) ← checkPlanStatementsV1 s!"fn '{fn.name}'" false
      true resultKind slots fn.params.size
      false plan.events.size eventFieldCounts plan.errors.size errorFieldCounts
      plan.fns fn.body totalPlanNodes
    totalPlanNodes := t
    unless returned do
      throw <| .planInvariant .evm s!"fn '{fn.name}' does not return"

/-- Validate one declared event/error binding: safe name and public UInt64
    fields (the EVM pilot ABI encodes UInt64 words only). -/
private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .evm
        s!"unsupported EVM semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- EVM-private public-UInt64 SemanticProgramV1 data → target-owned Plan pilot.
    This is intentionally not shared with other targets: storage/ABI/layout and
    SSA-tree policy remain EVM-owned until another native consumer proves a
    genuinely common bounded utility. -/
private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.invariants.isEmpty then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: constants/invariants are outside the current UInt64 pilot"
  -- init (0..1) + entries + pureFns; each class is capped at maxEntries.
  if source.callables.size > 2 * maxEntries + 1 then
    throw <| .planInvariant .evm
      s!"callable count exceeds EVM profile limit {2 * maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .evm
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateEvmTypeClosureV1 source.types
  let storageLayout ← makeStorageLayoutV1 types.uint64TypeId source.logicalState
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let components := source.qualifiedName.components.toArray
  let objectName := components.back!
  -- Phase 1: dense pureFn signature table + CallableId → fnIndex map so nested
  -- PureCall can resolve arity/result kind before any body is lowered.
  let mut fnIndexByCallableId : Array (Option Nat) :=
    Array.mk (List.replicate source.callables.size none)
  let mut fns : Array FnBinding := #[]
  let mut pureFnCallables : Array CallableV1 := #[]
  for callable in source.callables do
    match callable.kind with
    | .pureFn =>
        if fns.size >= maxEntries then
          throw <| .planInvariant .evm s!"fn count exceeds profile limit {maxEntries}"
        unless callable.id.toNat < source.callables.size do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: pureFn CallableId out of range"
        let name ← match callable.name with
          | some value => pure value
          | none => throw (.planInvariant .evm
              "unsupported EVM semantic shape: pureFn is missing its name")
        unless isIdentifier name do
          throw <| .planInvariant .evm s!"fn name '{name}' is not an EVM ABI identifier"
        unless callable.result.visibility == .public_ do
          throw <| .planInvariant .evm
            s!"fn '{name}' does not return public UInt64 or Bool"
        let resultIsBool : Bool ←
          if callable.result.typeId == types.uint64TypeId then
            pure false
          else if types.boolTypeId == some callable.result.typeId then
            pure true
          else
            throw <| .planInvariant .evm
              s!"fn '{name}' does not return public UInt64 or Bool"
        let (params, _) ← makeParamsV1 s!"fn '{name}'" types.uint64TypeId callable.params
        let fnIndex := fns.size
        fnIndexByCallableId := fnIndexByCallableId.set! callable.id.toNat (some fnIndex)
        fns := fns.push { name, params, body := #[], resultIsBool }
        pureFnCallables := pureFnCallables.push callable
    | .invariant =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: invariants are outside the current UInt64 pilot"
    | _ => pure ()
  -- Phase 2: lower pureFn bodies (signatures already resolve nested pureCall).
  for i in [0:pureFnCallables.size] do
    let callable ← match pureFnCallables[i]? with
      | some value => pure value
      | none => throw (.planInvariant .evm
          "unsupported EVM semantic shape: pureFn table is incomplete")
    let binding ← makeFnV1 types storageLayout fnIndexByCallableId fns callable
    fns := fns.set! i binding
  -- Phase 3: constructor + entries with the complete fn table.
  let mut constructor : Option Constructor := none
  let mut entries : Array Entry := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if constructor.isSome then
          throw <| .planInvariant .evm "semantic program has multiple initializers"
        constructor := some (← makeConstructorV1 types storageLayout
          fnIndexByCallableId fns callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .evm s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types storageLayout
          fnIndexByCallableId fns callable)
    | .pureFn | .invariant => pure ()
  if !storageLayout.isEmpty && constructor.isNone then
    throw <| .planInvariant .evm "stateful programs require an explicit initializer"
  let runtimeObjectName :=
    if objectName == "__proof_forge_runtime" then
      "__proof_forge_runtime_1"
    else
      "__proof_forge_runtime"
  let plan : Plan := {
    objectName
    runtimeObjectName
    storageLayout
    events
    errors
    constructor
    entries
    fns
  }
  validatePlan plan
  return plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "EVM received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Capability-gated public Plan entry (Wave 2 EVM pilot). Support is already
    decided by the capability; the Plan body consumes only retained
    SemanticProgramV1, never residual alpha. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .evm do
    throw <| .planInvariant .evm "engineering capability kind is not EVM"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

private structure RenderedExpr where
  code : String
  value : String
  next : Nat
  deriving Inhabited

private partial def renderExpr (indent paramPrefix : String) (next : Nat) : Expr → RenderedExpr
  | .literal value =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {value}\n", value := name, next := next + 1 }
  | .param wordIndex =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := {paramPrefix}{wordIndex}\n", value := name, next := next + 1 }
  | .storageLoad slot =>
      let name := s!"expr{next}"
      { code := s!"{indent}let {name} := sload({slot})\n" ++
          s!"{indent}if gt({name}, 0xffffffffffffffff) \{ revert(0, 0) }\n",
        value := name, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if gt({lhs.value}, sub(0xffffffffffffffff, {rhs.value})) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := add({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .checkedSub lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      { code := lhs.code ++ rhs.code ++
          s!"{indent}if lt({lhs.value}, {rhs.value}) \{ revert(0, 0) }\n" ++
          s!"{indent}let {name} := sub({lhs.value}, {rhs.value})\n",
        value := name, next := rhs.next + 1 }
  | .compare op lhs rhs =>
      let lhs := renderExpr indent paramPrefix next lhs
      let rhs := renderExpr indent paramPrefix lhs.next rhs
      let name := s!"expr{rhs.next}"
      let yul := match op with
        | .eq => s!"eq({lhs.value}, {rhs.value})"
        | .ne => s!"iszero(eq({lhs.value}, {rhs.value}))"
        | .lt => s!"lt({lhs.value}, {rhs.value})"
        | .le => s!"iszero(gt({lhs.value}, {rhs.value}))"
        | .gt => s!"gt({lhs.value}, {rhs.value})"
        | .ge => s!"iszero(lt({lhs.value}, {rhs.value}))"
      { code := lhs.code ++ rhs.code ++ s!"{indent}let {name} := {yul}\n",
        value := name, next := rhs.next + 1 }
  | .callFn fnIndex args => Id.run do
      let mut code := ""
      let mut next := next
      let mut argValues : Array String := #[]
      for arg in args do
        let rendered := renderExpr indent paramPrefix next arg
        code := code ++ rendered.code
        next := rendered.next
        argValues := argValues.push rendered.value
      let name := s!"expr{next}"
      let argsJoined := String.intercalate ", " argValues.toList
      { code := code ++ s!"{indent}let {name} := pf_fn{fnIndex}({argsJoined})\n",
        value := name, next := next + 1 }

private def renderStores (indent paramPrefix : String) (stores : Array Store) : String := Id.run do
  let mut output := ""
  let mut next := 0
  for store in stores do
    let rendered := renderExpr indent paramPrefix next store.value
    output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
    next := rendered.next
  return output

private structure RenderedBody where
  code : String
  next : Nat
  deriving Inhabited

/-- Render a statement list. `returnVar = none` is the contract path
    (`mstore` + `return`); `some r` is a Yul function path that assigns `r`. -/
private partial def renderBody (indent paramPrefix : String) (next : Nat)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (returnVar : Option String)
    (body : Array Statement) : RenderedBody := Id.run do
  let mut output := ""
  let mut next := next
  for statement in body do
    match statement with
    | .store store =>
        let rendered := renderExpr indent paramPrefix next store.value
        output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
        next := rendered.next
    | .assert condition =>
        let rendered := renderExpr indent paramPrefix next condition
        output := output ++ rendered.code ++
          s!"{indent}if iszero({rendered.value}) \{ revert(0, 0) }\n"
        next := rendered.next
    | .returnValue value =>
        let rendered := renderExpr indent paramPrefix next value
        match returnVar with
        | none =>
            output := output ++ rendered.code ++
              s!"{indent}mstore(0, {rendered.value})\n{indent}return(0, 32)\n"
        | some r =>
            output := output ++ rendered.code ++
              s!"{indent}{r} := {rendered.value}\n"
        next := rendered.next
    | .returnNone =>
        -- Valid only as the constructor body's final statement (validated);
        -- falling off the body reaches the deployment epilogue on this path.
        pure ()
    | .emitEvent eventIndex args =>
        let binding := events[eventIndex]!
        let signature := Keccak.signature binding.name
          (Array.replicate binding.fieldCount "uint64")
        let topic0 := Keccak.keccak256Hex signature.toUTF8
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}log1(0, {32 * args.size}, 0x{topic0})\n"
    | .revertError errorIndex args =>
        let binding := errors[errorIndex]!
        let selector := Keccak.selector binding.name
          (Array.replicate binding.fieldCount "uint64")
        let padded := selector ++ String.ofList (List.replicate 56 '0')
        for index in [0:args.size] do
          let rendered := renderExpr indent paramPrefix next args[index]!
          output := output ++ rendered.code
          next := rendered.next
          output := output ++ s!"{indent}mstore({4 + 32 * index}, {rendered.value})\n"
        output := output ++ s!"{indent}mstore(0, 0x{padded})\n"
        output := output ++ s!"{indent}revert(0, {4 + 32 * args.size})\n"
    | .ifThenElse condition thenBody elseBody =>
        let rendered := renderExpr indent paramPrefix next condition
        output := output ++ rendered.code
        let thenRendered := renderBody (indent ++ "  ") paramPrefix rendered.next
          events errors returnVar thenBody
        output := output ++ s!"{indent}if {rendered.value} \{\n" ++
          thenRendered.code ++ s!"{indent}}\n"
        next := thenRendered.next
        if !elseBody.isEmpty then
          let elseRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar elseBody
          output := output ++ s!"{indent}if iszero({rendered.value}) \{\n" ++
            elseRendered.code ++ s!"{indent}}\n"
          next := elseRendered.next
    | .switchOn scrutinee cases defaultBody =>
        let rendered := renderExpr indent paramPrefix next scrutinee
        let scrutName := s!"expr{rendered.next}"
        output := output ++ rendered.code ++
          s!"{indent}let {scrutName} := {rendered.value}\n"
        next := rendered.next + 1
        let mut guard : String := ""
        for (caseValue, caseBody) in cases do
          let caseRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar caseBody
          output := output ++
            s!"{indent}if eq({scrutName}, {caseValue}) \{\n" ++
            caseRendered.code ++ s!"{indent}}\n"
          next := caseRendered.next
          let eqExpr := s!"eq({scrutName}, {caseValue})"
          guard := if guard.isEmpty then eqExpr else s!"or({guard}, {eqExpr})"
        if !defaultBody.isEmpty then
          let defaultRendered := renderBody (indent ++ "  ") paramPrefix next
            events errors returnVar defaultBody
          output := output ++ s!"{indent}if iszero({guard}) \{\n" ++
            defaultRendered.code ++ s!"{indent}}\n"
          next := defaultRendered.next
  return { code := output, next }

/-- Emit `function pf_fn{i}(...) -> r { ... }` definitions. Duplicated into both
    Yul objects because each object is self-contained. -/
private def renderFnDefs (indent : String) (plan : Plan) : String := Id.run do
  if plan.fns.isEmpty then
    return ""
  let mut output := ""
  for index in [0:plan.fns.size] do
    let fn := plan.fns[index]!
    let mut paramList := ""
    for i in [0:fn.params.size] do
      if i > 0 then paramList := paramList ++ ", "
      paramList := paramList ++ s!"arg{i}"
    let body := renderBody (indent ++ "  ") "arg" 0 plan.events plan.errors (some "r") fn.body
    output := output ++
      s!"{indent}function pf_fn{index}({paramList}) -> r \{\n" ++
      body.code ++
      s!"{indent}}\n"
  return output

private def renderConstructor (plan : Plan) : String := Id.run do
  let constructor := plan.constructor.getD { params := #[], stores := #[] }
  let argumentBytes := constructor.params.size * 32
  let mut output :=
    s!"    if callvalue() \{ revert(0, 0) }\n" ++
    s!"    let programSize := datasize(\"{plan.objectName}\")\n" ++
    s!"    if iszero(eq(codesize(), add(programSize, {argumentBytes}))) \{ revert(0, 0) }\n"
  if argumentBytes > 0 then
    output := output ++ s!"    codecopy(0, programSize, {argumentBytes})\n"
  for param in constructor.params do
    output := output ++
      s!"    let ctor_arg{param.wordIndex} := mload({param.wordIndex * 32})\n" ++
      s!"    if gt(ctor_arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  -- Store-only constructors keep body empty for byte-identical Yul via stores.
  output := output ++
    (if constructor.body.isEmpty then
      renderStores "    " "ctor_arg" constructor.stores
    else
      (renderBody "    " "ctor_arg" 0 plan.events plan.errors none constructor.body).code)
  return output ++
    s!"    datacopy(0, dataoffset(\"{plan.runtimeObjectName}\"), datasize(\"{plan.runtimeObjectName}\"))\n" ++
    s!"    return(0, datasize(\"{plan.runtimeObjectName}\"))\n"

private def renderEntry (plan : Plan) (entry : Entry) : String := Id.run do
  let calldataBytes := 4 + entry.params.size * 32
  let mut output :=
    s!"      case 0x{entry.selector} \{\n" ++
    s!"        if iszero(eq(calldatasize(), {calldataBytes})) \{ revert(0, 0) }\n"
  for param in entry.params do
    let offset := 4 + param.wordIndex * 32
    output := output ++
      s!"        let arg{param.wordIndex} := calldataload({offset})\n" ++
      s!"        if gt(arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  output := output ++
    (renderBody "        " "arg" 0 plan.events plan.errors none entry.body).code
  return output ++ "      }\n"

private def renderYul (plan : Plan) : String :=
  let entries := plan.entries.foldl (fun output entry => output ++ renderEntry plan entry) ""
  let ctorFns := renderFnDefs "    " plan
  let runtimeFns := renderFnDefs "      " plan
  s!"object \"{plan.objectName}\" \{\n  code \{\n" ++
    renderConstructor plan ++
    ctorFns ++
    s!"  }\n  object \"{plan.runtimeObjectName}\" \{\n    code \{\n" ++
    "      if callvalue() { revert(0, 0) }\n" ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    entries ++
    "      default { revert(0, 0) }\n" ++
    runtimeFns ++
    "    }\n  }\n}\n"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"uint64\"}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderConstructorAbi (constructor : Constructor) : String :=
  "{\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[" ++
    renderParamsJson constructor.params ++ "]}"

private def resultKindAbiType (kind : ResultKind) : String :=
  match kind with
  | .uint64 => "uint64"
  | .bool => "bool"

private def renderEntryAbi (entry : Entry) : String :=
  let mutability := match entry.mutability with
    | .nonpayable => "nonpayable"
    | .view => "view"
  let resultType := resultKindAbiType entry.resultKind
  "{\"type\":\"function\",\"name\":\"" ++ Targets.escapeJson entry.name ++
    "\",\"stateMutability\":\"" ++ mutability ++ "\",\"inputs\":[" ++
    renderParamsJson entry.params ++
    "],\"outputs\":[{\"name\":\"\",\"type\":\"" ++ resultType ++ "\"}]}"

private def renderInterfaceBindingAbi (kind : String) (binding : InterfaceBinding) : String :=
  let inputs := (List.range binding.fieldCount).map fun index =>
    "{\"name\":\"arg" ++ toString index ++ "\",\"type\":\"uint64\"}"
  "{\"type\":\"" ++ kind ++ "\",\"name\":\"" ++ Targets.escapeJson binding.name ++
    "\",\"inputs\":[" ++ String.intercalate "," inputs ++ "]}"

private def renderAbi (plan : Plan) : String :=
  let constructor := plan.constructor.map (fun value => #[renderConstructorAbi value]) |>.getD #[]
  let entries := plan.entries.map renderEntryAbi
  let events := plan.events.map (renderInterfaceBindingAbi "event")
  let errors := plan.errors.map (renderInterfaceBindingAbi "error")
  let items := constructor ++ entries ++ events ++ errors
  "[\n  " ++ String.intercalate ",\n  " items.toList ++ "\n]\n"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  return { objectName := plan.objectName, yul := renderYul plan, abi := renderAbi plan }

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) :=
  .ok #[
    { path := s!"{ir.objectName}.yul", mediaType := "text/yul", contents := ir.yul },
    { path := s!"{ir.objectName}.abi.json", mediaType := "application/json", contents := ir.abi }
  ]

/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files.
    Not a residual Plan→IR bypass. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← planFromCapability capability
  lower plan

/-- Capability-gated public materialize entry. Sole path from the retained
    SemanticProgramV1-native EVM Plan body to emitted files for this target. -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

instance : Materializer .evm where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Evm
