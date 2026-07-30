import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.near

def hostAbiVersion : String := "near-host-abi-v1"
def rawInputAbi : String := "packed-raw-little-endian-u64"
def stateLayoutDomain : String := "proof-forge-near-layout-v1:"
def layoutMarkerKey : String := "pf:v1:layout"

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive FailureAction where
  | trap
  | returnStatus
  deriving BEq, Inhabited, Repr

structure FailurePolicy where
  invalidInput : FailureAction
  uninitializedLayout : FailureAction
  corruptStorage : FailureAction
  arithmeticOverflow : FailureAction
  nonzeroDeposit : FailureAction
  deriving BEq, Inhabited, Repr

inductive ReceiptCommitPolicy where
  | rollbackOnTrap
  | retainWritesOnTrap
  deriving BEq, Inhabited, Repr

inductive MethodMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

inductive DepositPolicy where
  | requireZero
  | queryOnly
  deriving BEq, Inhabited, Repr

inductive HostImport where
  | input
  | registerLen
  | readRegister
  | storageRead
  | storageWrite
  | valueReturn
  | attachedDeposit
  deriving BEq, Inhabited, Repr

structure ResourceLimits where
  maxArtifactStemBytes : Nat
  maxStateFields : Nat
  maxEntries : Nat
  maxParams : Nat
  maxBodyStatements : Nat
  maxExprDepth : Nat
  maxPlanNodes : Nat
  maxRecipeNodes : Nat
  maxMethodLocals : Nat
  wasmMemoryPages : Nat
  deriving BEq, Inhabited, Repr

structure StorageField where
  sourceId : Nat
  name : String
  key : String
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

structure StorageLayout where
  markerKey : String
  markerValue : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StorageField
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

/-- Unsigned comparison operators for the public-UInt64 comparison envelope. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (inputOffset : Nat)
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

/-- Result kind of a NEAR method export. Init is always unit; entry/view may be
UInt64 or Bool. Wire encoding for both scalar returns is still 8-byte little-
endian i64 (Bool is 0/1); the ABI JSON result type distinguishes them. -/
inductive MethodResultKind where
  | unit
  | uint64
  | bool
  deriving BEq, Inhabited, Repr

structure Method where
  name : String
  params : Array Param
  exactInputLen : Nat
  mode : MethodMode
  depositPolicy : DepositPolicy
  resultKind : MethodResultKind
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- The NEAR-owned KV, raw ABI, method, and error policy for the supported
UInt64 (+ Bool result) fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  targetDescriptor : TargetDescriptor
  semanticSchemaVersion : Nat
  codegenProfile : String
  hostAbi : String
  inputAbi : String
  layoutDomain : String
  hostImports : Array HostImport
  failurePolicy : FailurePolicy
  commitPolicy : ReceiptCommitPolicy
  resourceLimits : ResourceLimits
  programName : String
  storage : StorageLayout
  initializer : Method
  entries : Array Method
  -- No Inhabited: Plan embeds TargetDescriptor (opaque TargetId/profile).
  deriving BEq, Repr

structure RegisterLayout where
  input : Nat
  storage : Nat
  evicted : Nat
  deriving BEq, Inhabited, Repr

structure KeyRegion where
  key : String
  offset : Nat
  length : Nat
  deriving BEq, Inhabited, Repr

structure MemoryLayout where
  minPages : Nat
  inputOffset : Nat
  inputCapacity : Nat
  depositOffset : Nat
  valueOffset : Nat
  deriving BEq, Inhabited, Repr

inductive Operation where
  | checkInputLen (bytes : Nat)
  | requireZeroAttachedDeposit
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | storeState (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  | setReturnData (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed NEAR host-call/Wasm recipe. Rendering WAT is deliberately later than
the exact Plan-to-recipe binding check.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`); the private packaging ctor is not a product emission API. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  registers : RegisterLayout
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .near message

private def maxIdentifierBytes : Nat := 240
-- `.near-abi.json` is the longest emitted suffix (14 bytes) under the CLI's
-- 240-byte relative-path ceiling.
private def maxArtifactStemBytes : Nat := 226
private def maxStateFields : Nat := 1024
private def maxEntries : Nat := 255
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxPlanNodes : Nat := 100000
private def maxRecipeNodes : Nat := 110000
private def maxMethodLocals : Nat := 50000
private def wasmPageBytes : Nat := 65536

private def canonicalFailurePolicy : FailurePolicy := {
  invalidInput := .trap
  uninitializedLayout := .trap
  corruptStorage := .trap
  arithmeticOverflow := .trap
  nonzeroDeposit := .trap
}

private def canonicalResourceLimits : ResourceLimits := {
  maxArtifactStemBytes
  maxStateFields
  maxEntries
  maxParams
  maxBodyStatements
  maxExprDepth
  maxPlanNodes
  maxRecipeNodes
  maxMethodLocals
  wasmMemoryPages := 1
}

private def canonicalImports : Array HostImport := #[
  .input, .registerLen, .readRegister, .storageRead, .storageWrite, .valueReturn,
  .attachedDeposit
]

private def canonicalRegisters : RegisterLayout := {
  input := 0
  storage := 1
  evicted := 2
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

private def stateKey (sourceId : Nat) : String :=
  s!"pf:v1:state:{sourceId}"

private def layoutFieldSignature (field : StorageField) : String :=
  s!"{field.sourceId}:{field.name}:{field.key}:{field.byteWidth}:u64-le"

private def layoutSignature (fields : Array StorageField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StorageField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (stateLayoutDomain ++ layoutSignature fields).toUTF8

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

/-- Value kinds admitted in the NEAR pilot value table. Bool is admitted for
comparison/literal temps, assert conditions, and entry/view return values.
State/params remain UInt64-only; initializer result stays Unit. -/
private inductive NearValueKindV1 where
  | uint64
  | bool
  deriving BEq, Inhabited, Repr

private structure NearTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1

private def validateNearTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult NearTypeClosureV1 := do
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  for decl in types do
    unless decl.name.isNone do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: named types are outside the current UInt64 pilot"
    match decl.shape with
    | .uint width =>
        unless width.toNat == 64 && uint64TypeId.isNone do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: expected one anonymous UInt64 type"
        uint64TypeId := some decl.id
    | .unit =>
        unless unitTypeId.isNone do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: duplicate Unit type"
        unitTypeId := some decl.id
    | .bool =>
        unless boolTypeId.isNone do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: duplicate Bool type"
        boolTypeId := some decl.id
    | _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: only UInt64, Unit, and Bool are supported"
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: UInt64 type is missing")
  pure { uint64TypeId := resolvedUInt64TypeId, unitTypeId, boolTypeId }

private def makeStorageLayoutV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult StorageLayout := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .near "state count is outside the profile limits"
  let mut fields : Array StorageField := #[]
  for state in states do
    unless state.id.toNat == fields.size do
      throw <| .planInvariant .near "semantic state ids must match declaration order"
    unless state.typeId == uint64TypeId && state.visibility == .public_ do
      throw <| .planInvariant .near s!"state '{state.name}' is not public UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .near s!"state name '{state.name}' is not a safe identifier"
    fields := fields.push {
      sourceId := state.id.toNat
      name := state.name
      key := stateKey state.id.toNat
      byteWidth := 8
      endianness := .little
    }
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .near
      "state layout marker collides with the reserved uninitialized value"
  pure {
    markerKey := layoutMarkerKey
    markerValue := marker
    payloadInitialization := .zeroAllFields
    fields
  }

private structure LoweredValueV1 where
  expr : Expr
  kind : NearValueKindV1
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  deriving Inhabited

private def makeParamsV1 (owner : String) (uint64TypeId : TypeIdV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .near s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .near
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless param.typeId == uint64TypeId && param.visibility == .public_ do
      throw <| .planInvariant .near
        s!"parameter '{param.name}' in {owner} is not public UInt64"
    unless isIdentifier param.name do
      throw <| .planInvariant .near
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      inputOffset := planned.size * 8
      byteWidth := 8
      endianness := .little
    }
    planned := planned.push binding
    values := values.push {
      expr := .param binding.inputOffset
      kind := .uint64
      depth := 1
      expandedNodes := 1
      dependencies := #[]
    }
  pure (planned, values)

private def findFieldV1 (layout : StorageLayout)
    (id : StateIdV1) : CompileResult StorageField :=
  match layout.fields[id.toNat]? with
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
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| .planInvariant .near "unsupported NEAR semantic shape: invalid UInt64 literal"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: trailing UInt64 literal bytes"

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: Bool literal must contain exactly 1 byte"
  match bytes[0]! with
  | 0 => pure false
  | 1 => pure true
  | _ =>
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: Bool literal must be 0x00 or 0x01"

private def comparisonOpOfBinaryV1 (op : BinaryOpV1) : Option ComparisonOp :=
  match op with
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

private def currentValueV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart then
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (kind : NearValueKindV1)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == .uint64 && rhs.kind == .uint64 do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: binary operands must be UInt64"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    kind
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedAdd l r) .uint64 lhsId rhsId lhs rhs

private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedSub l r) .uint64 lhsId rhsId lhs rhs

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .compare op l r) .bool lhsId rhsId lhs rhs

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
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: dead or reordered value instructions"
  pure rootValue.expr

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: result ValueId/type is not canonical for its kind"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .near s!"NEAR value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : Option NearValueKindV1)
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && callable.blocks.size == 1 &&
      callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: callable must be one acyclic entry block"
  let block ← match callable.blocks[0]? with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: callable entry block is missing")
  unless block.id.toNat == 0 && block.params.isEmpty do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: block parameters are not supported"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .near
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  let paramCount := params.size
  let mut values := initialValues
  let mut segmentStart := values.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == types.uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 types.uint64TypeId values result {
            expr := .literal value
            kind := .uint64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else
          let boolTypeId ← match types.boolTypeId with
            | some tid =>
                unless typeId == tid do
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: literal is not UInt64 or Bool"
                pure tid
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: Bool type is missing for Bool literal"
          let flag ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 boolTypeId values result {
            expr := .literal (if flag then 1 else 0)
            kind := .bool
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
    | .stateLoad stateId, some result =>
        let field ← findFieldV1 layout stateId
        values := ← appendResultValueV1 types.uint64TypeId values result {
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
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else
          match comparisonOpOfBinaryV1 op with
          | some cmpOp =>
              let boolTypeId ← match types.boolTypeId with
                | some tid => pure tid
                | none =>
                    throw <| .planInvariant .near
                      "unsupported NEAR semantic shape: Bool type is missing for comparison"
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTypeId values result value
          | none =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: only checked UInt64 add/sub and comparisons are supported"
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: view callable writes state"
        let field ← findFieldV1 layout stateId
        let root ← currentValueV1 values paramCount segmentStart valueId
        unless root.kind == .uint64 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: state store value must be UInt64"
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
        body := body.push (.store { fieldIndex := field.sourceId, value })
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: assert must use errorId=none and empty args"
        let root ← currentValueV1 values paramCount segmentStart condId
        unless root.kind == .bool do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: assert condition must be Bool"
        let condition ← consumeCurrentSegmentV1 values paramCount segmentStart condId
        body := body.push (.assert condition)
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: instruction op/result is outside the current UInt64 pilot"
  match mode, block.terminator with
  | .initialize, .return_ none =>
      unless expectedReturn.isNone do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: initializer expected-return kind is non-empty"
      unless segmentStart == values.size do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: initializer has unconsumed values"
  | .mutate, .return_ (some valueId)
  | .view, .return_ (some valueId) =>
      let expectedKind ← match expectedReturn with
        | some kind => pure kind
        | none =>
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: entry/view is missing expected return kind"
      let root ← currentValueV1 values paramCount segmentStart valueId
      unless root.kind == expectedKind do
        let expectedLabel :=
          match expectedKind with
          | .uint64 => "UInt64"
          | .bool => "Bool"
        throw <| .planInvariant .near
          s!"unsupported NEAR semantic shape: return value must be {expectedLabel}"
      let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
      body := body.push (.returnValue value)
      segmentStart := values.size
  | .initialize, .return_ (some _) =>
      throw <| .planInvariant .near "initializer cannot return a value"
  | _, _ =>
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: callable terminator is outside the current UInt64 pilot"
  unless segmentStart == values.size do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: callable has unconsumed values"
  if body.size > maxBodyStatements then
    throw <| .planInvariant .near s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (callable : CallableV1) : CompileResult Method := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: initializer result is not Unit"
  let lowered ← lowerCallableV1 "initializer" .initialize none types layout callable
  pure {
    name := "init"
    params := lowered.params
    exactInputLen := lowered.params.size * 8
    mode := .initialize
    depositPolicy := .requireZero
    resultKind := .unit
    body := lowered.body
  }

private def makeEntryV1
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (callable : CallableV1) : CompileResult Method := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .near s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .near s!"entry '{name}' does not return a public result"
  let (resultKind, expectedReturn) ←
    if callable.result.typeId == types.uint64TypeId then
      pure (MethodResultKind.uint64, some NearValueKindV1.uint64)
    else if types.boolTypeId == some callable.result.typeId then
      pure (MethodResultKind.bool, some NearValueKindV1.bool)
    else
      throw <| .planInvariant .near
        s!"entry '{name}' does not return public UInt64 or Bool"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .near
        "unsupported NEAR semantic shape: callable is not an entry or view")
  let mode : MethodMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
  let lowered ←
    lowerCallableV1 s!"entry '{name}'" semanticMode expectedReturn types layout callable
  pure {
    name
    params := lowered.params
    exactInputLen := lowered.params.size * 8
    mode
    depositPolicy := if mode == .view then .queryOnly else .requireZero
    resultKind
    body := lowered.body
  }

private partial def planExprNodes? (layout : StorageLayout) (params : Array Param)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param inputOffset => if params.any (·.inputOffset == inputOffset) then some 1 else none
    | .stateLoad fieldIndex => if fieldIndex < layout.fields.size then some 1 else none
    | .checkedAdd lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? layout params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? layout params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .checkedSub lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? layout params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? layout params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? layout params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? layout params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

private def addPlanExprNodes (limits : ResourceLimits) (layout : StorageLayout)

    (params : Array Param) (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= limits.maxPlanNodes then
    throw <| .planInvariant .near
      s!"plan exceeds aggregate node limit {limits.maxPlanNodes}"
  match planExprNodes? layout params limits.maxExprDepth (limits.maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .near
        s!"plan expression has a dangling reference or exceeds depth {limits.maxExprDepth}/node limit {limits.maxPlanNodes}"

private def addMethodExprTemps (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= limits.maxMethodLocals then
    throw <| .planInvariant .near
      s!"method expression exceeds local limit {limits.maxMethodLocals}"
  match planExprNodes? layout params limits.maxExprDepth (limits.maxMethodLocals - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .near
        s!"method expression has a dangling reference or exceeds depth {limits.maxExprDepth}/local limit {limits.maxMethodLocals}"

private def validateStorageLayout (limits : ResourceLimits)
    (layout : StorageLayout) : CompileResult Unit := do
  unless layout.markerKey == layoutMarkerKey && layout.markerValue != 0 &&
      layout.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .near "NEAR storage initialization/layout policy is not canonical"
  if layout.fields.isEmpty || layout.fields.size > limits.maxStateFields then
    throw <| .planInvariant .near "state field count is outside the profile limits"
  for index in [0:layout.fields.size] do
    let field := layout.fields[index]!
    unless field.sourceId == index && isIdentifier field.name &&
        field.key == stateKey index && field.byteWidth == 8 &&
        field.endianness == .little do
      throw <| .planInvariant .near "state field KV layout is not canonical UInt64 little-endian"
  if hasDuplicates (layout.fields.map (·.name)) ||
      hasDuplicates (layout.fields.map (·.key)) ||
      layout.fields.any (·.key == layout.markerKey) then
    throw <| .planInvariant .near "state field names/keys must be unique and distinct from the marker"
  unless layout.markerValue == layoutMarker layout.fields do
    throw <| .planInvariant .near "state layout marker is not bound to the canonical KV schema"

private def validateParams (limits : ResourceLimits) (owner : String)
    (params : Array Param) : CompileResult Unit := do
  if params.size > limits.maxParams then
    throw <| .planInvariant .near
      s!"parameter count in {owner} exceeds profile limit {limits.maxParams}"
  for index in [0:params.size] do
    let param := params[index]!
    unless param.sourceId == index && isIdentifier param.name &&
        param.inputOffset == index * 8 && param.byteWidth == 8 &&
        param.endianness == .little do
      throw <| .planInvariant .near
        s!"parameter binding in {owner} is not canonical UInt64 little-endian"
  if hasDuplicates (params.map (·.name)) then
    throw <| .planInvariant .near s!"parameter names in {owner} must be unique"

private def validateMethod (limits : ResourceLimits) (layout : StorageLayout)
    (isInitializer : Bool) (baseNodes : Nat) (method : Method) : CompileResult Nat := do
  unless isIdentifier method.name && method.name != "memory" do
    throw <| .planInvariant .near s!"method '{method.name}' is not a safe export name"
  if isInitializer then
    unless method.name == "init" && method.mode == .initialize &&
        method.depositPolicy == .requireZero && method.resultKind == .unit do
      throw <| .planInvariant .near "initializer export identity is not canonical"
  else if method.mode == .initialize then
    throw <| .planInvariant .near "entry method cannot use initialize mode"
  else unless method.resultKind == .uint64 || method.resultKind == .bool do
    throw <| .planInvariant .near
      s!"method '{method.name}' result kind must be UInt64 or Bool"
  unless method.depositPolicy ==
      (if method.mode == .view then .queryOnly else .requireZero) do
    throw <| .planInvariant .near s!"method '{method.name}' deposit policy is not canonical"
  validateParams limits s!"method '{method.name}'" method.params
  unless method.exactInputLen == method.params.size * 8 do
    throw <| .planInvariant .near s!"method '{method.name}' raw input length is not canonical"
  if method.body.size > limits.maxBodyStatements || (!isInitializer && method.body.isEmpty) then
    throw <| .planInvariant .near s!"method '{method.name}' has an invalid body size"
  let mut total := baseNodes
  let mut methodTemps := 0
  let mut returned := false
  for statement in method.body do
    if returned then
      throw <| .planInvariant .near s!"method '{method.name}' has a statement after return"
    match statement with
    | .store store =>
        if method.mode == .view then
          throw <| .planInvariant .near s!"view method '{method.name}' writes state"
        unless store.fieldIndex < layout.fields.size do
          throw <| .planInvariant .near s!"method '{method.name}' stores to an unknown KV field"
        total ← addPlanExprNodes limits layout method.params total store.value
        methodTemps ← addMethodExprTemps limits layout method.params methodTemps store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .near "initializer cannot return a value"
        total ← addPlanExprNodes limits layout method.params total value
        methodTemps ← addMethodExprTemps limits layout method.params methodTemps value
        returned := true
    | .assert condition =>
        total ← addPlanExprNodes limits layout method.params total condition
        methodTemps ← addMethodExprTemps limits layout method.params methodTemps condition
  if isInitializer then
    if returned then
      throw <| .planInvariant .near "initializer cannot return a value"
  else unless returned do
    throw <| .planInvariant .near s!"method '{method.name}' does not return a scalar value"
  return total

/-- Validate the public target-owned NEAR Plan before recipe lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == semanticProgramSchemaVersionV1 &&
      plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.hostAbi == hostAbiVersion && plan.inputAbi == rawInputAbi &&
      plan.layoutDomain == stateLayoutDomain &&
      plan.hostImports == canonicalImports &&
      plan.failurePolicy == canonicalFailurePolicy &&
      plan.commitPolicy == .rollbackOnTrap &&
      plan.resourceLimits == canonicalResourceLimits do
    throw <| .planInvariant .near "NEAR Plan descriptor/schema/profile policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .near s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > plan.resourceLimits.maxArtifactStemBytes then
    throw <| .planInvariant .near
      s!"program name exceeds artifact-stem limit {plan.resourceLimits.maxArtifactStemBytes} bytes"
  validateStorageLayout plan.resourceLimits plan.storage
  if plan.entries.isEmpty || plan.entries.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .near "entry count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total method => total + method.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total method => total + method.body.size) 0
  let mut total := plan.storage.fields.size + handlerCount + paramCount + statementCount
  if total > plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .near
      s!"plan exceeds aggregate node limit {plan.resourceLimits.maxPlanNodes}"
  total ← validateMethod plan.resourceLimits plan.storage true total plan.initializer
  for method in plan.entries do
    total ← validateMethod plan.resourceLimits plan.storage false total method
  let methods := #[plan.initializer] ++ plan.entries
  if hasDuplicates (methods.map (·.name)) then
    throw <| .planInvariant .near "NEAR export names must be unique"

/-- NEAR-private retained SemanticProgramV1 data → target-owned Plan pilot. -/
private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.events.isEmpty || !source.errors.isEmpty ||
      !source.invariants.isEmpty then
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: constants/events/errors/invariants are outside the current UInt64 pilot"
  if source.callables.size > maxEntries + 1 then
    throw <| .planInvariant .near s!"callable count exceeds NEAR profile limit {maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .near
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateNearTypeClosureV1 source.types
  let storage ← makeStorageLayoutV1 types.uint64TypeId source.logicalState
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let mut initializer : Option Method := none
  let mut entries : Array Method := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .near "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types storage callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .near s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types storage callable)
    | .pureFn | .invariant =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: pure functions/invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .near "KV-state programs require an initializer"
  let plan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := semanticProgramSchemaVersionV1
    codegenProfile := descriptor.codegenProfile.toString
    hostAbi := hostAbiVersion
    inputAbi := rawInputAbi
    layoutDomain := stateLayoutDomain
    hostImports := canonicalImports
    failurePolicy := canonicalFailurePolicy
    commitPolicy := .rollbackOnTrap
    resourceLimits := canonicalResourceLimits
    programName
    storage
    initializer := resolvedInitializer
    entries
  }
  validatePlan plan
  pure plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "NEAR received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Capability-gated public plan entry. Plan semantics consume retained V1 only. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .near do
    throw <| .planInvariant .near "engineering capability kind is not NEAR"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 0
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

private def maxInputLen (plan : Plan) : Nat :=
  plan.entries.foldl (fun current method => max current method.exactInputLen)
    plan.initializer.exactInputLen

private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 0
  let inputOffset := align8 keysEnd
  let inputCapacity := maxInputLen plan
  let depositOffset := align8 (inputOffset + inputCapacity)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset
    inputCapacity
    depositOffset
    valueOffset := depositOffset + 16
  }

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

private partial def lowerExpr (keys : Array KeyRegion) (next : Nat) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param inputOffset =>
      { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .stateLoad fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next lhs
      let rhs := lowerExpr keys lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr keys next lhs
      let rhs := lowerExpr keys lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr keys next lhs
      let rhs := lowerExpr keys lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[.checkInputLen method.exactInputLen]
  if method.depositPolicy == .requireZero then
    operations := operations.push .requireZeroAttachedDeposit
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      operations := operations.push (.zeroState (fieldRegion keys index))
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  let mut next := 0
  for statement in method.body do
    match statement with
    | .store store =>
        let value := lowerExpr keys next store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState (fieldRegion keys store.fieldIndex) value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr keys next value
        operations := operations ++ value.operations
        operations := operations.push (.setReturnData value.value)
        next := value.next
    | .assert condition =>
        let value := lowerExpr keys next condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value)
        next := value.next
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    tempCount := next
    operations
  }

private def expectedMethods (plan : Plan) (keys : Array KeyRegion) : Array MethodIR :=
  #[lowerMethod plan keys plan.initializer] ++ plan.entries.map (lowerMethod plan keys)

/-- Validate the typed host-call recipe and bind it exactly to its source Plan. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .near "typed NEAR IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports && ir.registers == canonicalRegisters do
    throw <| .planInvariant .near "typed NEAR IR host imports/registers are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .near "typed NEAR IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages &&
      ir.memory.valueOffset + 8 <= ir.memory.minPages * wasmPageBytes do
    throw <| .planInvariant .near "typed NEAR IR memory layout is not canonical or exceeds one page"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .near "typed NEAR IR export count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
  let operationCount := ir.methods.foldl (fun total method =>
    total + method.params.size + method.operations.size) 0
  if operationCount > ir.sourcePlan.resourceLimits.maxRecipeNodes then
    throw <| .planInvariant .near
      s!"typed NEAR IR exceeds recipe node limit {ir.sourcePlan.resourceLimits.maxRecipeNodes}"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .near
      "typed NEAR IR methods/operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    registers := canonicalRegisters
    keys
    memory
    methods := expectedMethods plan keys
  }
  validateIR ir
  return ir

private def uint64Hex (value : UInt64) : String :=
  let raw := String.ofList (Nat.toDigits 16 value.toNat)
  let raw := if raw.isEmpty then "0" else raw
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderImport : HostImport → String
  | .input => "  (import \"env\" \"input\" (func $pf_input (param i64)))\n"
  | .registerLen =>
      "  (import \"env\" \"register_len\" (func $pf_register_len (param i64) (result i64)))\n"
  | .readRegister =>
      "  (import \"env\" \"read_register\" (func $pf_read_register (param i64 i64)))\n"
  | .storageRead =>
      "  (import \"env\" \"storage_read\" (func $pf_storage_read (param i64 i64 i64) (result i64)))\n"
  | .storageWrite =>
      "  (import \"env\" \"storage_write\" (func $pf_storage_write (param i64 i64 i64 i64 i64) (result i64)))\n"
  | .valueReturn =>
      "  (import \"env\" \"value_return\" (func $pf_value_return (param i64 i64)))\n"
  | .attachedDeposit =>
      "  (import \"env\" \"attached_deposit\" (func $pf_attached_deposit (param i64)))\n"

private def renderReadKey (registers : RegisterLayout) (memory : MemoryLayout)
    (destination : Nat) (field : KeyRegion) : String :=
  s!"    (if (i64.ne (call $pf_storage_read (i64.const {field.length}) (i64.const {field.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
    s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
    s!"    (call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
    s!"    (local.set $t{destination} (i64.load (i32.const {memory.valueOffset})))\n"

private def renderOperation (registers : RegisterLayout) (memory : MemoryLayout) :
    Operation → String
  | .checkInputLen bytes =>
      s!"    (call $pf_input (i64.const {registers.input}))\n" ++
        s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.input})) (i64.const {bytes})) (then unreachable))\n" ++
        (if bytes == 0 then "" else
          s!"    (call $pf_read_register (i64.const {registers.input}) (i64.const {memory.inputOffset}))\n")
  | .requireZeroAttachedDeposit =>
      s!"    (call $pf_attached_deposit (i64.const {memory.depositOffset}))\n" ++
        s!"    (if (i64.ne (i64.load (i32.const {memory.depositOffset})) (i64.const 0)) (then unreachable))\n" ++
        s!"    (if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n"
  | .requireLayoutAbsent marker =>
      s!"    (if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 0)) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"    (if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
        s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
        s!"    (call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
        s!"    (if (i64.ne (i64.load (i32.const {memory.valueOffset})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (i64.const 0))\n" ++
        s!"    (if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .literal destination value =>
      s!"    (local.set $t{destination} (i64.const {value.toNat}))\n"
  | .loadParam destination inputOffset =>
      s!"    (local.set $t{destination} (i64.load (i32.const {memory.inputOffset + inputOffset})))\n"
  | .loadState destination field =>
      renderReadKey registers memory destination field
  | .checkedAdd destination lhs rhs =>
      s!"    (local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"    (if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .checkedSub destination lhs rhs =>
      s!"    (if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"    (local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .compare destination lhs rhs op =>
      let insn :=
        match op with
        | .eq => "i64.eq"
        | .ne => "i64.ne"
        | .lt => "i64.lt_u"
        | .le => "i64.le_u"
        | .gt => "i64.gt_u"
        | .ge => "i64.ge_u"
      s!"    (local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .assert condition =>
      s!"    (if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .storeState field value =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"    (if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))\n" ++
        s!"    (if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const 8)) (then unreachable))\n"
  | .setLayout marker value =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (i64.const {value.toNat}))\n" ++
        s!"    (if (i64.ne (call $pf_storage_write (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .setReturnData value =>
      s!"    (i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"    (call $pf_value_return (i64.const 8) (i64.const {memory.valueOffset}))\n"

private def renderMethod (ir : IR) (method : MethodIR) : String :=
  let locals := String.intercalate "" <| (Array.range method.tempCount).toList.map fun index =>
    s!" (local $t{index} i64)"
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.registers ir.memory)
  s!"  (func (export \"{method.name}\"){locals}\n" ++ operations ++ "  )\n"

private def renderWat (ir : IR) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let data := String.intercalate "" <| ir.keys.toList.map fun key =>
    s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  let methods := String.intercalate "" <| ir.methods.toList.map (renderMethod ir)
  "(module\n" ++ imports ++
    s!"  (memory (export \"memory\") {ir.memory.minPages})\n" ++ data ++ methods ++ ")\n"

private def renderMode : MethodMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderDepositPolicy : DepositPolicy → String
  | .requireZero => "zero-required"
  | .queryOnly => "query-only"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"u64-le\",\"inputOffset\":{param.inputOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StorageField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"key\":\"{Targets.escapeJson field.key}\",\"type\":\"u64-le\"}"

private def renderResultKindJson : MethodResultKind → String
  | .unit => "null"
  | .uint64 => "\"u64-le\""
  | .bool => "\"bool\""

private def renderMethodJson (method : Method) : String :=
  let returns := renderResultKindJson method.resultKind
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"depositPolicy\":\"{renderDepositPolicy method.depositPolicy}\"," ++
    s!"\"exactInputLen\":{method.exactInputLen}," ++
    s!"\"args\":[{renderParamsJson method.params}],\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map renderFieldJson)
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-near-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"layoutMarker\":\"0x{uint64Hex plan.storage.markerValue}\"," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"exports\": [\n    " ++ exports ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := renderWat ir
    },
    {
      path := s!"{ir.name}.near-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    }
  ]

/-- Replace methods on an existing IR (private `mk`; for validateIR characterization). -/
def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

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

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Near
