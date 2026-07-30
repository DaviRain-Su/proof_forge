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
  deriving BEq, Inhabited, Repr

structure Store where
  slot : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (operation : Store)
  | returnValue (value : Expr)
  | assert (condition : Expr)
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

structure Entry where
  name : String
  selector : String
  params : Array Param
  mutability : Mutability
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Complete EVM decisions for the currently supported portable fragment.
The renderer consumes this value without consulting `SemanticProgram`. -/
structure Plan where
  objectName : String
  runtimeObjectName : String
  storageLayout : Array StorageBinding
  constructor : Option Constructor
  entries : Array Entry
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
    silently erased. Bool is optional (at most one) and never appears in
    state/param/result positions. -/
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

/-- Compute expanded tree cost before constructing an EVM Expr node. A shared
    SSA operand counts once per use, so `add(v,v)` doubles the expanded cost. -/
private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .checkedAdd lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

/-- Subtraction has the same bounded SSA-tree cost as addition; its distinct
    constructor preserves the source operator through Plan validation/Yul. -/
private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .checkedSub lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

/-- Comparison has the same bounded SSA-tree cost as checked arithmetic. -/
private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := .compare op lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

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
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  stores : Array Store
  body : Array Statement

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  let uint64TypeId := types.uint64TypeId
  unless callable.entryBlock.toNat == 0 && callable.blocks.size == 1 &&
      callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: callable must be one acyclic entry block"
  let block ← match callable.blocks[0]? with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: callable entry block is missing")
  unless block.id.toNat == 0 && block.params.isEmpty do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: block parameters are not supported"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .evm
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let (params, initialValues) ← makeParamsV1 owner uint64TypeId callable.params
  let paramCount := params.size
  let mut values := initialValues
  let mut segmentStart := values.size
  let mut stores : Array Store := #[]
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
          -- Bool words are 0/1 UInt64 literals in the Plan expression surface.
          values := ← appendResultValueV1 boolTid values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
    | .stateLoad stateId, some result =>
        let binding ← findStorageV1 layout stateId
        values := ← appendResultValueV1 uint64TypeId values result {
          expr := .storageLoad binding.slot
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
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: view callable writes storage"
        let binding ← findStorageV1 layout stateId
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
        let store : Store := { slot := binding.slot, value }
        stores := stores.push store
        body := body.push (.store store)
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: assert must have errorId=none and empty args"
        let cond ← consumeCurrentSegmentV1 values paramCount segmentStart condId
        body := body.push (.assert cond)
        hasAssert := true
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: instruction op/result is outside the current UInt64 pilot"
  match mode, block.terminator with
  | .constructor, .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: constructor has unconsumed values"
  | .entry, .return_ (some valueId)
  | .view, .return_ (some valueId) =>
      let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
      body := body.push (.returnValue value)
      segmentStart := values.size
  | .constructor, .return_ (some _) =>
      throw <| .planInvariant .evm "constructor cannot return a value"
  | _, _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: callable terminator is outside the current UInt64 pilot"
  unless segmentStart == values.size do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: callable has unconsumed values"
  if stores.size > maxBodyStatements || body.size > maxBodyStatements then
    throw <| .planInvariant .evm s!"{owner} body exceeds profile limit {maxBodyStatements}"
  -- Constructor store-only path keeps body empty so aggregate tests that mutate
  -- `stores` remain authoritative; interleaved assert requires ordered body.
  let constructorBody :=
    if mode == .constructor && !hasAssert then #[] else body
  let constructorStores :=
    if mode == .constructor && hasAssert then #[] else stores
  let entryBody := if mode == .constructor then constructorBody else body
  let entryStores := if mode == .constructor then constructorStores else #[]
  pure { params, stores := entryStores, body := entryBody }

private def makeConstructorV1
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
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
  let lowered ← lowerCallableV1 "constructor" .constructor types layout callable
  pure {
    params := lowered.params
    stores := lowered.stores
    body := lowered.body
  }

private def makeEntryV1
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (callable : CallableV1) : CompileResult Entry := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .evm
        "unsupported EVM semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .evm s!"entry name '{name}' is not an EVM ABI identifier"
  unless callable.result.typeId == types.uint64TypeId &&
      callable.result.visibility == .public_ do
    throw <| .planInvariant .evm s!"entry '{name}' does not return public UInt64"
  let mode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .entry
    | .view => pure .view
    | _ => throw (.planInvariant .evm
        "unsupported EVM semantic shape: callable is not an entry or view")
  let mutability : Mutability := match mode with
    | .entry => .nonpayable
    | .view => .view
    | .constructor => .nonpayable
  let lowered ← lowerCallableV1 s!"entry '{name}'" mode types layout callable
  pure {
    name
    selector := Keccak.selector name (lowered.params.map fun _ => "uint64")
    params := lowered.params
    mutability
    body := lowered.body
  }

private partial def planExprNodes? (slots : Array Nat) (paramCount depthLeft nodeBudget : Nat)
    (expr : Expr) : Option Nat :=
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
        match planExprNodes? slots paramCount childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .checkedSub lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? slots paramCount childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? slots paramCount childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (slots : Array Nat) (paramCount total : Nat)
    (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? slots paramCount maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .evm
        s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private def addPlanStoreNodes (slots : Array Nat) (paramCount total : Nat)
    (store : Store) : CompileResult Nat := do
  unless slots.contains store.slot do
    throw <| .planInvariant .evm "plan store references an unknown storage slot"
  addPlanExprNodes slots paramCount total store.value

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
  let mut totalPlanNodes := plan.storageLayout.size + plan.entries.size + constructorNodes + entryNodes
  if totalPlanNodes > maxPlanNodes then
    throw <| .planInvariant .evm s!"plan exceeds aggregate node limit {maxPlanNodes}"
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
        totalPlanNodes ← addPlanStoreNodes slots constructor.params.size totalPlanNodes store
    else
      for statement in constructor.body do
        match statement with
        | .store store =>
            totalPlanNodes ← addPlanStoreNodes slots constructor.params.size totalPlanNodes store
        | .assert condition =>
            totalPlanNodes ← addPlanExprNodes slots constructor.params.size totalPlanNodes condition
        | .returnValue _ =>
            throw <| .planInvariant .evm "constructor cannot return a value"
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
    let mut returned := false
    for statement in entry.body do
      if returned then
        throw <| .planInvariant .evm s!"entry '{entry.name}' has a statement after return"
      match statement with
      | .store store =>
          if entry.mutability == .view then
            throw <| .planInvariant .evm s!"view entry '{entry.name}' writes storage"
          totalPlanNodes ← addPlanStoreNodes slots entry.params.size totalPlanNodes store
      | .assert condition =>
          totalPlanNodes ← addPlanExprNodes slots entry.params.size totalPlanNodes condition
      | .returnValue value =>
          totalPlanNodes ← addPlanExprNodes slots entry.params.size totalPlanNodes value
          returned := true
    unless returned do
      throw <| .planInvariant .evm s!"entry '{entry.name}' does not return"

/-- EVM-private public-UInt64 SemanticProgramV1 data → target-owned Plan pilot.
    This is intentionally not shared with other targets: storage/ABI/layout and
    SSA-tree policy remain EVM-owned until another native consumer proves a
    genuinely common bounded utility. -/
private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.events.isEmpty || !source.errors.isEmpty ||
      !source.invariants.isEmpty then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: constants/events/errors/invariants are outside the current UInt64 pilot"
  if source.callables.size > maxEntries + 1 then
    throw <| .planInvariant .evm s!"callable count exceeds EVM profile limit {maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .evm
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateEvmTypeClosureV1 source.types
  let storageLayout ← makeStorageLayoutV1 types.uint64TypeId source.logicalState
  let components := source.qualifiedName.components.toArray
  let objectName := components.back!
  let mut constructor : Option Constructor := none
  let mut entries : Array Entry := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if constructor.isSome then
          throw <| .planInvariant .evm "semantic program has multiple initializers"
        constructor := some (← makeConstructorV1 types storageLayout callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .evm s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types storageLayout callable)
    | .pureFn | .invariant =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: pure functions/invariants are outside the current UInt64 pilot"
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
    constructor
    entries
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

private def renderStores (indent paramPrefix : String) (stores : Array Store) : String := Id.run do
  let mut output := ""
  let mut next := 0
  for store in stores do
    let rendered := renderExpr indent paramPrefix next store.value
    output := output ++ rendered.code ++ s!"{indent}sstore({store.slot}, {rendered.value})\n"
    next := rendered.next
  return output

private def renderBody (indent paramPrefix : String) (body : Array Statement) : String := Id.run do
  let mut output := ""
  let mut next := 0
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
        output := output ++ rendered.code ++
          s!"{indent}mstore(0, {rendered.value})\n{indent}return(0, 32)\n"
        next := rendered.next
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
      renderBody "    " "ctor_arg" constructor.body)
  return output ++
    s!"    datacopy(0, dataoffset(\"{plan.runtimeObjectName}\"), datasize(\"{plan.runtimeObjectName}\"))\n" ++
    s!"    return(0, datasize(\"{plan.runtimeObjectName}\"))\n"

private def renderEntry (entry : Entry) : String := Id.run do
  let calldataBytes := 4 + entry.params.size * 32
  let mut output :=
    s!"      case 0x{entry.selector} \{\n" ++
    s!"        if iszero(eq(calldatasize(), {calldataBytes})) \{ revert(0, 0) }\n"
  for param in entry.params do
    let offset := 4 + param.wordIndex * 32
    output := output ++
      s!"        let arg{param.wordIndex} := calldataload({offset})\n" ++
      s!"        if gt(arg{param.wordIndex}, 0xffffffffffffffff) \{ revert(0, 0) }\n"
  output := output ++ renderBody "        " "arg" entry.body
  return output ++ "      }\n"

private def renderYul (plan : Plan) : String :=
  let entries := plan.entries.foldl (fun output entry => output ++ renderEntry entry) ""
  s!"object \"{plan.objectName}\" \{\n  code \{\n" ++
    renderConstructor plan ++
    s!"  }\n  object \"{plan.runtimeObjectName}\" \{\n    code \{\n" ++
    "      if callvalue() { revert(0, 0) }\n" ++
    "      if lt(calldatasize(), 4) { revert(0, 0) }\n" ++
    "      switch shr(224, calldataload(0))\n" ++
    entries ++
    "      default { revert(0, 0) }\n" ++
    "    }\n  }\n}\n"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"uint64\"}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderConstructorAbi (constructor : Constructor) : String :=
  "{\"type\":\"constructor\",\"stateMutability\":\"nonpayable\",\"inputs\":[" ++
    renderParamsJson constructor.params ++ "]}"

private def renderEntryAbi (entry : Entry) : String :=
  let mutability := match entry.mutability with
    | .nonpayable => "nonpayable"
    | .view => "view"
  "{\"type\":\"function\",\"name\":\"" ++ Targets.escapeJson entry.name ++
    "\",\"stateMutability\":\"" ++ mutability ++ "\",\"inputs\":[" ++
    renderParamsJson entry.params ++
    "],\"outputs\":[{\"name\":\"\",\"type\":\"uint64\"}]}"

private def renderAbi (plan : Plan) : String :=
  let constructor := plan.constructor.map (fun value => #[renderConstructorAbi value]) |>.getD #[]
  let entries := plan.entries.map renderEntryAbi
  let items := constructor ++ entries
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
