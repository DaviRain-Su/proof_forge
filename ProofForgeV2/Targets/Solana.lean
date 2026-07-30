import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.solana

def discriminatorDomain : String := "proof-forge-solana-v1:"
def layoutDomain : String := "proof-forge-solana-layout-v1:"
def discriminatorBytes : Nat := 8
def stateHeaderBytes : Nat := 8
def arithmeticOverflowError : Nat := 0x1001
def assertionFailedError : Nat := 0x1002

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive OwnerPolicy where
  | currentProgram
  deriving BEq, Inhabited, Repr

inductive InitializationPolicy where
  | mustBeUninitialized
  | mustBeInitialized
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive HandlerMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

/-- Entry/view return ABI kind. Init handlers ignore this field (IDL `null`).
    Bool is a single-byte 0/1 return-data payload; UInt64 remains 8-byte LE. -/
inductive ResultKind where
  | u64
  | bool
  deriving BEq, Inhabited, Repr

structure StateField where
  sourceId : Nat
  name : String
  accountIndex : Nat
  byteOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

structure StateAccount where
  index : Nat
  name : String
  ownerPolicy : OwnerPolicy
  exactDataLen : Nat
  headerOffset : Nat
  headerWidth : Nat
  initializedMarker : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StateField
  deriving BEq, Inhabited, Repr

structure AccountAccess where
  accountIndex : Nat
  ownerPolicy : OwnerPolicy
  exactDataLen : Nat
  signerRequired : Bool
  writableRequired : Bool
  initialization : InitializationPolicy
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  dataOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (dataOffset : Nat)
  | stateLoad (accountIndex byteOffset : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  accountIndex : Nat
  byteOffset : Nat
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

structure Handler where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  resultKind : ResultKind
  accountAccess : AccountAccess
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- One declared event/error binding: its name and UInt64 argument count. -/
structure InterfaceBinding where
  name : String
  fieldCount : Nat
  deriving BEq, Inhabited, Repr

/-- Every Solana-specific ABI, account, layout, and dispatch decision for the
current UInt64 planning fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  codegenProfile : String
  instructionDiscriminatorDomain : String
  instructionDiscriminatorBytes : Nat
  stateLayoutDomain : String
  arithmeticOverflowError : Nat
  assertionFailedError : Nat
  programName : String
  stateAccount : StateAccount
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  initializer : Handler
  entries : Array Handler
  deriving BEq, Inhabited, Repr

inductive Check where
  | instructionDataLen (bytes : Nat)
  | ownerCurrentProgram (accountIndex : Nat)
  | accountDataLen (accountIndex bytes : Nat)
  | signer (accountIndex : Nat)
  | writable (accountIndex : Nat)
  | headerEquals (accountIndex byteOffset : Nat) (value : UInt64)
  deriving BEq, Inhabited, Repr

inductive Operation where
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination dataOffset : Nat)
  | loadState (destination accountIndex byteOffset : Nat)
  | checkedAdd (destination lhs rhs errorCode : Nat)
  | checkedSub (destination lhs rhs errorCode : Nat)
  | zeroState (accountIndex byteOffset : Nat)
  | storeState (accountIndex byteOffset value : Nat)
  | setHeader (accountIndex byteOffset : Nat) (value : UInt64)
  | setReturnData (value : Nat)
  | setReturnDataBool (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat) (errorCode : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  deriving BEq, Inhabited, Repr

structure HandlerIR where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  resultKind : ResultKind
  accountAccess : AccountAccess
  checks : Array Check
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed, plan-level sBPF audit IR. It is intentionally not an ELF or an
assembler input until the pinned sBPF toolchain/backend exists.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`). -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  stateAccount : StateAccount
  handlers : Array HandlerIR
  deriving BEq, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .solana message

private def maxIdentifierBytes : Nat := 240
-- `.sbpf-plan` is the longest emitted suffix (10 bytes) under the CLI's
-- 240-byte relative-path ceiling.
private def maxArtifactStemBytes : Nat := 230
private def maxStateFields : Nat := 1024
private def maxEntries : Nat := 255
private def maxParams : Nat := 64
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
        rest.all (fun character =>
          isAsciiLetter character || isAsciiDigit character || character == '_')

private def hasDuplicates [BEq α] (values : Array α) : Bool := Id.run do
  let mut seen : Array α := #[]
  for value in values do
    if seen.contains value then return true
    seen := seen.push value
  return false

private def validDiscriminator (value : String) : Bool :=
  value.length == 2 * discriminatorBytes && value.toList.all (fun character =>
    "0123456789abcdef".contains character)

private def layoutFieldSignature (field : StateField) : String :=
  s!"{field.sourceId}:{field.name}:{field.accountIndex}:{field.byteOffset}:{field.byteWidth}:u64-le"

private def layoutSignature (fields : Array StateField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StateField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (layoutDomain ++ layoutSignature fields).toUTF8

private def signature (name : String) (params : Array Param) : String :=
  s!"{name}({String.intercalate "," (params.toList.map fun _ => "u64")})"

def instructionDiscriminator (name : String) (params : Array Param) : String :=
  ((Crypto.sha256Hex (discriminatorDomain ++ signature name params).toUTF8).take
    (2 * discriminatorBytes)).copy

private def accessFor (account : StateAccount) (mode : HandlerMode) : AccountAccess := {
  accountIndex := account.index
  ownerPolicy := account.ownerPolicy
  exactDataLen := account.exactDataLen
  signerRequired := mode == .initialize
  writableRequired := mode != .view
  initialization := if mode == .initialize then
    .mustBeUninitialized
  else
    .mustBeInitialized
}

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

private structure SolanaTypeClosureV1 where
  uint64TypeId : TypeIdV1
  unitTypeId : Option TypeIdV1
  boolTypeId : Option TypeIdV1

private def validateSolanaTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult SolanaTypeClosureV1 := do
  let mut uint64TypeId : Option TypeIdV1 := none
  let mut unitTypeId : Option TypeIdV1 := none
  let mut boolTypeId : Option TypeIdV1 := none
  for decl in types do
    unless decl.name.isNone do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: named types are outside the current UInt64 pilot"
    match decl.shape with
    | .uint width =>
        unless width.toNat == 64 && uint64TypeId.isNone do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: expected one anonymous UInt64 type"
        uint64TypeId := some decl.id
    | .unit =>
        unless unitTypeId.isNone do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: duplicate Unit type"
        unitTypeId := some decl.id
    | .bool =>
        unless boolTypeId.isNone do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: duplicate Bool type"
        boolTypeId := some decl.id
    | _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: only UInt64, Unit, and Bool are supported"
  let resolvedUInt64TypeId ← match uint64TypeId with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: UInt64 type is missing")
  pure { uint64TypeId := resolvedUInt64TypeId, unitTypeId, boolTypeId }

private def makeStateAccountV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult StateAccount := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .solana "state count is outside the profile limits"
  let mut fields : Array StateField := #[]
  for state in states do
    unless state.id.toNat == fields.size do
      throw <| .planInvariant .solana "semantic state ids must match declaration order"
    unless state.typeId == uint64TypeId && state.visibility == .public_ do
      throw <| .planInvariant .solana s!"state '{state.name}' is not public UInt64"
    unless isIdentifier state.name do
      throw <| .planInvariant .solana s!"state name '{state.name}' is not a safe identifier"
    fields := fields.push {
      sourceId := state.id.toNat
      name := state.name
      accountIndex := 0
      byteOffset := stateHeaderBytes + fields.size * 8
      byteWidth := 8
      endianness := .little
    }
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .solana
      "state layout marker collides with the reserved uninitialized zero value"
  pure {
    index := 0
    name := "state"
    ownerPolicy := .currentProgram
    exactDataLen := stateHeaderBytes + fields.size * 8
    headerOffset := 0
    headerWidth := stateHeaderBytes
    initializedMarker := marker
    payloadInitialization := .zeroAllFields
    fields
  }

private structure LoweredValueV1 where
  expr : Expr
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  isBool : Bool
  deriving Inhabited

private def makeParamsV1 (owner : String) (uint64TypeId : TypeIdV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .solana
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless param.typeId == uint64TypeId && param.visibility == .public_ do
      throw <| .planInvariant .solana
        s!"parameter '{param.name}' in {owner} is not public UInt64"
    unless isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      dataOffset := discriminatorBytes + planned.size * 8
      byteWidth := 8
      endianness := .little
    }
    planned := planned.push binding
    values := values.push {
      expr := .param binding.dataOffset
      depth := 1
      expandedNodes := 1
      dependencies := #[]
      isBool := false
    }
  pure (planned, values)

private def findFieldV1 (account : StateAccount)
    (id : StateIdV1) : CompileResult StateField :=
  match account.fields[id.toNat]? with
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
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: invalid UInt64 literal"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: trailing UInt64 literal bytes"

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: Bool literal must contain exactly 1 byte"
  match bytes[0]!.toNat with
  | 0 => pure false
  | 1 => pure true
  | _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: Bool literal must be 0x00 or 0x01"

private def currentValueV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= paramCount && index < segmentStart then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: computed ValueId crosses an effect boundary"
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
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
    isBool
  }

private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedAdd lhsId rhsId lhs rhs false

private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedSub lhsId rhsId lhs rhs false

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true

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
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: dead or reordered value instructions"
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
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= paramCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: result ValueId/type is not canonical"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .solana s!"Solana value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private def comparisonOpOfV1 : BinaryOpV1 → Option ComparisonOp
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

private structure LoweredBlockV1 where
  statements : Array Statement
  values : Array LoweredValueV1
  segmentStart : Nat

/-- Lower one block's instruction sequence (terminator handled by the region
    walker). Each block starts a fresh effect segment; values from dominating
    blocks stay referenceable only via params or match-arm scrutinees. -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  unless block.params.isEmpty do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: block parameters are not supported"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .solana
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let mut segmentStart := values0.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == types.uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 types.uint64TypeId values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := false
          }
        else if types.boolTypeId == some typeId then
          let bit ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal (if bit then 1 else 0)
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := true
          }
        else
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: literal is not UInt64 or Bool"
    | .stateLoad stateId, some result =>
        let field ← findFieldV1 account stateId
        values := ← appendResultValueV1 types.uint64TypeId values result {
          expr := .stateLoad field.accountIndex field.byteOffset
          depth := 1
          expandedNodes := 1
          dependencies := #[]
          isBool := false
        }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables rhsId
        unless !lhs.isBool && !rhs.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: binary operands must be UInt64"
        if op == .add then
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else
          match comparisonOpOfV1 op with
          | some cmpOp =>
              let boolTypeId ← match types.boolTypeId with
                | some value => pure value
                | none => throw (.planInvariant .solana
                    "unsupported Solana semantic shape: Bool type is missing for comparison")
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTypeId values result value
          | none =>
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: only checked UInt64 add/sub and comparisons are supported"
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable writes state"
        let field ← findFieldV1 account stateId
        let stored ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
        unless !stored.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: state store value must be UInt64"
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
        body := body.push (.store {
          accountIndex := field.accountIndex
          byteOffset := field.byteOffset
          value
        })
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert requires errorId=none and empty args"
        let cond ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
        unless cond.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert condition must be Bool"
        let value ← consumeCurrentSegmentV1 values paramCount segmentStart condId
        body := body.push (.assert value)
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable emits an event"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless !root.isBool do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart }

/-- Decode a switch case constant against the scrutinee kind. -/
private def decodeSwitchCaseValueV1 (scrutIsBool : Bool) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if scrutIsBool then
    let bit ← decodeBoolLiteralV1 bytes
    pure (if bit then 1 else 0)
  else
    decodeUInt64LiteralV1 bytes

/-- Structured emission of the forward-only multi-block CFG. Diamonds
    (branch/switch) are recovered by following each arm to its exit jump or
    return; convergent joins continue the region. The fuel bounds recursion
    to the block count. Returns (statements, values, nextJoin). -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (blocks : Array BlockV1)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × Option Nat) := do
  if fuel == 0 then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: CFG region exceeds block bound"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: block ids are not dense"
  let lowered ← lowerBlockInstructionsV1
    owner mode types account paramCount armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .initialize =>
          throw <| .planInvariant .solana "initializer cannot return a value"
      | .mutate | .view =>
          let returned ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
          unless returned.isBool == expectsBoolReturn do
            throw <| .planInvariant .solana
              (if expectsBoolReturn then
                "unsupported Solana semantic shape: Bool entry/view must return a Bool value"
               else
                "unsupported Solana semantic shape: UInt64 entry/view must not return a Bool value")
          let value ← consumeCurrentSegmentV1 values paramCount segmentStart valueId
          pure (instrs.push (.returnValue value), values, none)
  | .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, none)
  | .jump target =>
      unless segmentStart == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block has unconsumed values"
      pure (instrs, values, some target.blockId.toNat)
  | .branch condId thenT elseT =>
      let condVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
      unless condVal.isBool do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values paramCount segmentStart condId
      let (thenBody, values1, thenNext) ←
        emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
          armReadables (fuel - 1) thenT.blockId.toNat values
      match thenNext with
      | some j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, next) ←
              emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
                armReadables (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, next)
          else
            let (elseBody, values2, elseNext) ←
              emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
                armReadables (fuel - 1) elseT.blockId.toNat values1
            match elseNext with
            | some j2 =>
                unless j == j2 do
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: branch arms converge on divergent joins"
                let (rest, values3, next) ←
                  emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
                    armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, next)
            | none =>
                let (rest, values3, next) ←
                  emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
                    armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, next)
      | none =>
          let (elseBody, values2, elseNext) ←
            emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
              armReadables (fuel - 1) elseT.blockId.toNat values1
          pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, elseNext)
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables scrutId
      let scrut ← consumeCurrentSegmentV1 values paramCount segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .solana
          "unsupported Solana semantic shape: switch must carry a default target")
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutVal.isBool switchCase.valueBytes
        let (body, values1, armNext) ←
          emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
            (armReadables.push scrutId) (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        match armNext, joinAcc with
        | none, _ => pure ()
        | some j, none => joinAcc := some j
        | some j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: switch arms converge on divergent joins"
      let (defaultBody, values2, defaultNext) ←
        emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
          (armReadables.push scrutId) (fuel - 1)
          defaultT.blockId.toNat valuesA
      match defaultNext, joinAcc with
      | none, _ => pure ()
      | some j, none => joinAcc := some j
      | some j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: switch arms converge on divergent joins"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, none)
      | some j =>
          let (rest, values3, next) ←
            emitRegionV1 owner mode expectsBoolReturn types account blocks paramCount
              armReadables (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest, values3, next)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
        unless !root.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values paramCount segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, none)
  | .trap _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: trap terminators are outside the current pilot"

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.loopBounds.isEmpty && callable.invariantSteps.isNone do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: callable must have an acyclic entry block"
  unless callable.blocks.all (fun b => b.params.isEmpty) do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: block parameters are not supported"
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  let paramCount := params.size
  let (body0, values0, nextJoin0) ←
    emitRegionV1 owner mode expectsBoolReturn types account callable.blocks paramCount #[]
      callable.blocks.size 0 initialValues
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG, so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextJoin := nextJoin0
  for _ in [0:callable.blocks.size] do
    match nextJoin with
    | none => break
    | some j =>
        let (rest, values1, next1) ←
          emitRegionV1 owner mode expectsBoolReturn types account callable.blocks
            paramCount #[] callable.blocks.size j values
        body := body ++ rest
        values := values1
        nextJoin := next1
  match nextJoin with
  | some _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: callable does not end in return on all paths"
  | none => pure ()
  if body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (callable : CallableV1) : CompileResult Handler := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: initializer result is not Unit"
  let lowered ← lowerCallableV1 "initializer" .initialize false types account callable
  let handler : Handler := {
    name := "initialize"
    discriminator := ""
    params := lowered.params
    mode := .initialize
    resultKind := .u64
    accountAccess := accessFor account .initialize
    body := lowered.body
  }
  pure { handler with discriminator := instructionDiscriminator handler.name handler.params }

private def makeEntryV1
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (callable : CallableV1) : CompileResult Handler := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .solana s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .solana s!"entry '{name}' result is not public"
  let resultKind : ResultKind ←
    if callable.result.typeId == types.uint64TypeId then
      pure .u64
    else if types.boolTypeId == some callable.result.typeId then
      pure .bool
    else
      throw <| .planInvariant .solana
        s!"entry '{name}' does not return public UInt64 or Bool"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .solana
        "unsupported Solana semantic shape: callable is not an entry or view")
  let mode : HandlerMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
  let expectsBoolReturn := resultKind == .bool
  let lowered ← lowerCallableV1 s!"entry '{name}'" semanticMode expectsBoolReturn
    types account callable
  let handler : Handler := {
    name
    discriminator := ""
    params := lowered.params
    mode
    resultKind
    accountAccess := accessFor account mode
    body := lowered.body
  }
  pure { handler with discriminator := instructionDiscriminator handler.name handler.params }

private partial def planExprNodes? (account : StateAccount) (params : Array Param)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .param dataOffset => if params.any (·.dataOffset == dataOffset) then some 1 else none
    | .stateLoad accountIndex byteOffset =>
        if account.fields.any (fun field =>
            field.accountIndex == accountIndex && field.byteOffset == byteOffset) then
          some 1
        else
          none
    | .checkedAdd lhs rhs | .checkedSub lhs rhs | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? account params childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)

/-- UInt64-compatible plan expression (comparison results are Bool). -/
private def exprIsUInt64CompatibleV1 : Expr → Bool
  | .compare .. => false
  | _ => true

private def addPlanExprNodes (account : StateAccount) (params : Array Param)
    (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? account params maxExprDepth (maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .solana
        s!"plan expression has a dangling reference or exceeds depth {maxExprDepth}/node limit {maxPlanNodes}"

private def validateStateAccount (account : StateAccount) : CompileResult Unit := do
  unless account.index == 0 && account.name == "state" &&
      account.ownerPolicy == .currentProgram do
    throw <| .planInvariant .solana "state account identity/owner policy is not canonical"
  unless account.headerOffset == 0 && account.headerWidth == stateHeaderBytes &&
      account.initializedMarker != 0 &&
      account.initializedMarker == layoutMarker account.fields &&
      account.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .solana "state account header is not canonical"
  if account.fields.isEmpty || account.fields.size > maxStateFields then
    throw <| .planInvariant .solana "state account field count is outside the profile limits"
  unless account.exactDataLen == stateHeaderBytes + account.fields.size * 8 do
    throw <| .planInvariant .solana "state account exact data length does not match its fields"
  let sourceIds := account.fields.map (·.sourceId)
  let names := account.fields.map (·.name)
  let offsets := account.fields.map (·.byteOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana "state field origins, names, and offsets must be unique"
  for index in [0:account.fields.size] do
    let field := account.fields[index]!
    unless field.sourceId == index && field.accountIndex == account.index &&
        field.byteOffset == stateHeaderBytes + index * 8 && field.byteWidth == 8 &&
        field.endianness == .little && isIdentifier field.name do
      throw <| .planInvariant .solana "state field layout is not canonical UInt64 little-endian"

private def validateParams (owner : String) (params : Array Param) : CompileResult Unit := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let sourceIds := params.map (·.sourceId)
  let names := params.map (·.name)
  let offsets := params.map (·.dataOffset)
  if hasDuplicates sourceIds || hasDuplicates names || hasDuplicates offsets then
    throw <| .planInvariant .solana s!"parameter bindings in {owner} must be unique"
  for index in [0:params.size] do
    let param := params[index]!
    unless param.sourceId == index && param.dataOffset == discriminatorBytes + index * 8 &&
        param.byteWidth == 8 && param.endianness == .little && isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter binding in {owner} is not canonical UInt64 little-endian"

/-- Recursive statement-tree validator for one handler: view-write ban
    (including inside branches), node accounting, and per-level return
    ordering. Returns the updated node total and whether this level closes in
    return or revert on every path. A bare-return marker is accepted only at
    the top level of the initializer body (`allowReturnNone`); early bare
    returns inside branch arms fail closed (the initializer's header-marking
    epilogue must run on every path). -/
private partial def checkHandlerStatementsV1
    (account : StateAccount) (isInitializer : Bool) (isView : Bool)
    (allowReturnNone : Bool)
    (eventCount : Nat) (eventFieldCounts : Array Nat)
    (errorCount : Nat) (errorFieldCounts : Array Nat)
    (params : Array Param) (statements : Array Statement) (total : Nat) :
    CompileResult (Nat × Bool) := do
  let mut total := total
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .solana "handler has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .solana "view handler writes state"
        unless account.fields.any (fun field =>
            field.accountIndex == store.accountIndex && field.byteOffset == store.byteOffset) do
          throw <| .planInvariant .solana "handler stores to an unknown field"
        total ← addPlanExprNodes account params total store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .solana "initializer cannot return a value"
        total ← addPlanExprNodes account params total value
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .solana "handler has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .solana "view handler emits an event"
        unless eventIndex < eventCount do
          throw <| .planInvariant .solana "handler emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .solana "handler event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 arg do
            throw <| .planInvariant .solana "handler event arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params total arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .solana "handler reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .solana "handler error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 arg do
            throw <| .planInvariant .solana "handler error arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params total arg
        total := total + 1
        closed := true
    | .assert condition =>
        total ← addPlanExprNodes account params total condition
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes account params total condition
        total := total + 1
        let (t1, c1) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts params thenBody total
        let (t2, c2) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts params elseBody t1
        total := t2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes account params total scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, c) ← checkHandlerStatementsV1
            account isInitializer isView false
            eventCount eventFieldCounts errorCount errorFieldCounts params caseBody total
          total := t
          allClosed := allClosed && c
        let (td, cd) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts params defaultBody total
        total := td
        closed := allClosed && cd
  pure (total, closed)

private def expectedAccess (account : StateAccount) (mode : HandlerMode) : AccountAccess :=
  accessFor account mode

private def validateHandler (account : StateAccount) (isInitializer : Bool)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (baseNodes : Nat) (handler : Handler) : CompileResult Nat := do
  unless isIdentifier handler.name && validDiscriminator handler.discriminator do
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid ABI identity"
  if isInitializer then
    unless handler.name == "initialize" && handler.mode == .initialize do
      throw <| .planInvariant .solana "initializer handler identity is not canonical"
  else
    if handler.mode == .initialize then
      throw <| .planInvariant .solana "entry handler cannot use initialize mode"
  validateParams s!"handler '{handler.name}'" handler.params
  unless handler.discriminator == instructionDiscriminator handler.name handler.params do
    throw <| .planInvariant .solana
      s!"handler '{handler.name}' discriminator is not bound to its canonical signature"
  unless handler.accountAccess == expectedAccess account handler.mode do
    throw <| .planInvariant .solana s!"handler '{handler.name}' account access is not canonical"
  if handler.body.isEmpty || handler.body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"handler '{handler.name}' has an invalid body size"
  let (total, closed) ← checkHandlerStatementsV1
    account isInitializer (handler.mode == .view) isInitializer
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    handler.params handler.body baseNodes
  unless closed do
    throw <| .planInvariant .solana
      s!"handler '{handler.name}' does not terminate on all paths"
  return total

/-- Validate the public target-owned Plan before typed IR lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.instructionDiscriminatorDomain == discriminatorDomain &&
      plan.instructionDiscriminatorBytes == discriminatorBytes &&
      plan.stateLayoutDomain == layoutDomain &&
      plan.arithmeticOverflowError == arithmeticOverflowError &&
      plan.assertionFailedError == assertionFailedError do
    throw <| .planInvariant .solana "Solana Plan profile/error policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .solana s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .solana
      s!"program name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  validateStateAccount plan.stateAccount
  if plan.entries.isEmpty || plan.entries.size > maxEntries then
    throw <| .planInvariant .solana "entry count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total handler => total + handler.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total handler => total + handler.body.size) 0
  let mut total := plan.stateAccount.fields.size + handlerCount + paramCount + statementCount
  if total > maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  total ← validateHandler plan.stateAccount true plan.events plan.errors total plan.initializer
  for handler in plan.entries do
    total ← validateHandler plan.stateAccount false plan.events plan.errors total handler
  let handlers := #[plan.initializer] ++ plan.entries
  if hasDuplicates (handlers.map (·.name)) then
    throw <| .planInvariant .solana "handler names must be unique"
  if hasDuplicates (handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "handler discriminators collide"

/-- Validate one declared event/error binding: safe name and public UInt64
    fields (the Solana pilot plan records UInt64 args only). -/
private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .solana
      s!"unsupported Solana semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .solana
        s!"unsupported Solana semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- Solana-private retained SemanticProgramV1 data → target-owned Plan pilot. -/

private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.invariants.isEmpty then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: constants/invariants are outside the current UInt64 pilot"
  if source.callables.size > maxEntries + 1 then
    throw <| .planInvariant .solana s!"callable count exceeds Solana profile limit {maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .solana
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateSolanaTypeClosureV1 source.types
  let stateAccount ← makeStateAccountV1 types.uint64TypeId source.logicalState
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let mut initializer : Option Handler := none
  let mut entries : Array Handler := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .solana "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types stateAccount callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .solana s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types stateAccount callable)
    | .pureFn | .invariant =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: pure functions/invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .solana "state-account programs require an initializer"
  let plan : Plan := {
    codegenProfile := descriptor.codegenProfile.toString
    instructionDiscriminatorDomain := discriminatorDomain
    instructionDiscriminatorBytes := discriminatorBytes
    stateLayoutDomain := layoutDomain
    arithmeticOverflowError
    assertionFailedError
    programName
    stateAccount
    events
    errors
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
        throw <| .invalidProgram "Solana received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Capability-gated public plan entry. Plan semantics consume retained V1 only. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private partial def lowerExpr (overflowError next : Nat) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param dataOffset =>
      { operations := #[.loadParam next dataOffset], value := next, next := next + 1 }
  | .stateLoad accountIndex byteOffset =>
      { operations := #[.loadState next accountIndex byteOffset], value := next, next := next + 1 }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr overflowError next lhs
      let rhs := lowerExpr overflowError lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr overflowError next lhs
      let rhs := lowerExpr overflowError lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr overflowError next lhs
      let rhs := lowerExpr overflowError lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }

private def checksFor (discriminatorWidth : Nat) (account : StateAccount)
    (handler : Handler) : Array Check := Id.run do
  let access := handler.accountAccess
  let headerValue := match access.initialization with
    | .mustBeUninitialized => 0
    | .mustBeInitialized => account.initializedMarker
  let mut checks := #[
    .instructionDataLen (discriminatorWidth + handler.params.size * 8),
    .ownerCurrentProgram access.accountIndex,
    .accountDataLen access.accountIndex access.exactDataLen
  ]
  if access.signerRequired then checks := checks.push (.signer access.accountIndex)
  if access.writableRequired then checks := checks.push (.writable access.accountIndex)
  return checks.push (.headerEquals access.accountIndex account.headerOffset headerValue)

/-- Whether every path through a statement list ends in a return (valued or
    bare marker), matching the region emitter's closedness: a list closes iff
    its last statement is a return or a region whose arms all close. An empty
    else/default arm is a fallthrough (open). Used to append a hard `exit`
    after arms whose set_return_data would otherwise fall through into the
    region's continuation (the syscall does not halt execution). -/
private partial def statementListClosesV1 : List Statement → Bool
  | [] => false
  | [statement] =>
      match statement with
      | .returnValue _ | .returnNone | .revertError .. => true
      | .ifThenElse _ thenBody elseBody =>
          !elseBody.isEmpty && statementListClosesV1 thenBody.toList &&
            statementListClosesV1 elseBody.toList
      | .switchOn _ cases defaultBody =>
          !defaultBody.isEmpty && statementListClosesV1 defaultBody.toList &&
            cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList
      | .store _ | .assert _ | .emitEvent .. => false
  | _ :: _ :: rest => statementListClosesV1 rest

/-- Append the hard exit after a closed region arm, unless the arm already
    ends in a halting statement (the initializer's bare-return marker, or a
    declared revert, which traps by itself). -/
private def armOpsWithHardExit (arm : Array Statement)
    (operations : Array Operation) : Array Operation :=
  let alreadyHalts := match arm.back? with
    | some .returnNone | some (.revertError ..) => true
    | _ => false
  if statementListClosesV1 arm.toList && !alreadyHalts then
    operations.push .returnNone
  else
    operations

private partial def lowerBodyOps
    (overflowError : Nat) (resultKind : ResultKind) (assertErr : Nat)
    (next : Nat) (statements : Array Statement) : Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr overflowError next store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState store.accountIndex store.byteOffset value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr overflowError next value
        operations := operations ++ value.operations
        let returnOp : Operation := match resultKind with
          | .u64 => .setReturnData value.value
          | .bool => .setReturnDataBool value.value
        operations := operations.push returnOp
        next := value.next
    | .returnNone =>
        -- Valid only inside region arms (validated); the initializer's own
        -- final marker is stripped by lowerHandler before lowering.
        operations := operations.push .returnNone
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr overflowError next arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr overflowError next arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .assert condition =>
        let value := lowerExpr overflowError next condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value assertErr)
        next := value.next
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr overflowError next condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps overflowError resultKind assertErr value.next thenBody
        let (elseOps, next2) := lowerBodyOps overflowError resultKind assertErr next1 elseBody
        operations := operations.push (.ifRegion value.value
          (armOpsWithHardExit thenBody thenOps) (armOpsWithHardExit elseBody elseOps))
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr overflowError next scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps overflowError resultKind assertErr nextC caseBody
          caseOps := caseOps.push (caseValue, armOpsWithHardExit caseBody ops)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps overflowError resultKind assertErr nextC defaultBody
        operations := operations.push (.switchRegion value.value caseOps
          (armOpsWithHardExit defaultBody defaultOps))
        next := nextD
  pure (operations, next)

private def lowerHandler (plan : Plan) (handler : Handler) : HandlerIR := Id.run do
  let account := plan.stateAccount
  let operations0 : Array Operation :=
    if handler.mode == .initialize then
      account.fields.map fun field => .zeroState field.accountIndex field.byteOffset
    else
      #[]
  -- The initializer's final bare-return marker is the natural fall-through;
  -- in-arm markers are rejected by validatePlan and never reach this point.
  let body := if handler.body.back? == some .returnNone then
    handler.body.pop
  else
    handler.body
  let (bodyOps, _) := lowerBodyOps
    plan.arithmeticOverflowError handler.resultKind plan.assertionFailedError 0 body
  let mut operations := operations0 ++ bodyOps
  if handler.mode == .initialize then
    operations := operations.push <|
      .setHeader account.index account.headerOffset account.initializedMarker
  return {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    resultKind := handler.resultKind
    accountAccess := handler.accountAccess
    checks := checksFor plan.instructionDiscriminatorBytes account handler
    operations
  }

private def tempDestination? : Operation → Option Nat
  | .literal destination .. | .loadParam destination .. |
      .loadState destination .. | .checkedAdd destination .. |
      .checkedSub destination .. | .compare destination .. => some destination
  | _ => none

/-- Recursive operation-sequence validator: canonical temp numbering across
    nested regions, operand range checks, and per-level terminator ordering.
    Returns (next, returnedOnThisLevel, initializedOnThisLevel). -/
private partial def validateOperationSequence
    (plan : Plan) (handler : HandlerIR)
    (fieldOffsets paramOffsets : Array Nat)
    (operations : Array Operation) (next : Nat) :
    CompileResult (Nat × Bool × Bool) := do
  let account := plan.stateAccount
  let mut next := next
  let mut returned := false
  let mut initialized := false
  let mut halted := false
  for operation in operations do
    if halted then
      throw <| .planInvariant .solana "typed Solana IR has an operation after its hard exit"
    if let some destination := tempDestination? operation then
      unless destination == next do
        throw <| .planInvariant .solana "typed Solana IR temporary numbering is not canonical"
      next := next + 1
    match operation with
    | .returnNone =>
        -- The hard exit terminates an arm after set_return_data (or the
        -- initializer's bare return); it neither sets nor requires flags.
        halted := true
    | .literal ..
    | .loadParam .. | .loadState .. | .checkedAdd .. | .checkedSub ..
    | .compare .. | .assert .. | .zeroState .. | .storeState ..
    | .setHeader .. | .setReturnData .. | .setReturnDataBool ..
    | .emitEvent .. | .revertError ..
    | .ifRegion .. | .switchRegion .. =>
        if returned || initialized then
          throw <| .planInvariant .solana "typed Solana IR has an operation after its terminator"
    match operation with
    | .returnNone => pure ()
    | .literal .. => pure ()
    | .loadParam _ dataOffset =>
        unless paramOffsets.contains dataOffset do
          throw <| .planInvariant .solana "typed Solana IR loads an unknown parameter offset"
    | .loadState _ accountIndex byteOffset =>
        unless accountIndex == account.index && fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana "typed Solana IR loads an unknown state field"
    | .checkedAdd _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-add operands/error are invalid"
    | .checkedSub _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-sub operands/error are invalid"
    | .compare _ lhs rhs _op =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR compare operands are invalid"
    | .assert condition errorCode =>
        unless condition < next && errorCode == plan.assertionFailedError do
          throw <| .planInvariant .solana "typed Solana IR assert condition/error is invalid"
    | .zeroState accountIndex byteOffset =>
        unless handler.mode == .initialize && accountIndex == account.index &&
            fieldOffsets.contains byteOffset do
          throw <| .planInvariant .solana "typed Solana IR zeroes an unknown state field"
    | .storeState accountIndex byteOffset value =>
        unless handler.mode != .view && accountIndex == account.index &&
            fieldOffsets.contains byteOffset && value < next do
          throw <| .planInvariant .solana "typed Solana IR store is invalid"
    | .setHeader accountIndex byteOffset value =>
        unless handler.mode == .initialize && accountIndex == account.index &&
            byteOffset == account.headerOffset && value == account.initializedMarker do
          throw <| .planInvariant .solana "typed Solana IR header write is invalid"
        initialized := true
    | .setReturnData value =>
        unless handler.mode != .initialize && handler.resultKind == .u64 && value < next do
          throw <| .planInvariant .solana "typed Solana IR UInt64 return value is invalid"
        returned := true
    | .setReturnDataBool value =>
        unless handler.mode != .initialize && handler.resultKind == .bool && value < next do
          throw <| .planInvariant .solana "typed Solana IR Bool return value is invalid"
        returned := true
    | .emitEvent eventIndex args =>
        unless handler.mode != .view && eventIndex < plan.events.size &&
            args.size == plan.events[eventIndex]!.fieldCount &&
            args.all (· < next) do
          throw <| .planInvariant .solana "typed Solana IR event emission is invalid"
    | .revertError errorIndex args =>
        unless errorIndex < plan.errors.size &&
            args.size == plan.errors[errorIndex]!.fieldCount &&
            args.all (· < next) do
          throw <| .planInvariant .solana "typed Solana IR declared revert is invalid"
        -- A declared revert closes this path (return or revert on all paths).
        returned := true
    | .ifRegion condition thenOps elseOps =>
        unless condition < next do
          throw <| .planInvariant .solana "typed Solana IR if-region condition is invalid"
        let (n1, r1, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets thenOps next
        let (n2, r2, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets elseOps n1
        next := n2
        returned := (r1 && r2 && !elseOps.isEmpty) || returned
    | .switchRegion scrutinee cases defaultOps =>
        unless scrutinee < next do
          throw <| .planInvariant .solana "typed Solana IR switch-region scrutinee is invalid"
        let mut nextC := next
        let mut allClosed := !defaultOps.isEmpty
        for (_, ops) in cases do
          let (n, r, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets ops nextC
          nextC := n
          allClosed := allClosed && r
        let (nd, rd, _) ← validateOperationSequence plan handler fieldOffsets paramOffsets defaultOps nextC
        next := nd
        returned := (allClosed && rd) || returned
  pure (next, returned, initialized)

private def validateHandlerIR (plan : Plan) (handler : HandlerIR) : CompileResult Unit := do
  let account := plan.stateAccount
  unless isIdentifier handler.name && validDiscriminator handler.discriminator do
    throw <| .planInvariant .solana "typed Solana IR has an invalid handler identity"
  validateParams s!"IR handler '{handler.name}'" handler.params
  unless handler.discriminator == instructionDiscriminator handler.name handler.params do
    throw <| .planInvariant .solana "typed Solana IR discriminator does not match its ABI signature"
  unless handler.accountAccess == expectedAccess account handler.mode do
    throw <| .planInvariant .solana "typed Solana IR account access is not canonical"
  let planHandler : Handler := {
    name := handler.name
    discriminator := handler.discriminator
    params := handler.params
    mode := handler.mode
    resultKind := handler.resultKind
    accountAccess := handler.accountAccess
    body := #[.returnValue (.literal 0)]
  }
  unless handler.checks == checksFor plan.instructionDiscriminatorBytes account planHandler do
    throw <| .planInvariant .solana "typed Solana IR checks are incomplete or out of order"
  let fieldOffsets := account.fields.map (·.byteOffset)
  let paramOffsets := handler.params.map (·.dataOffset)
  let (_, returned, initialized) ← validateOperationSequence
    plan handler fieldOffsets paramOffsets handler.operations 0
  if handler.mode == .initialize then
    unless initialized do
      throw <| .planInvariant .solana "initializer IR does not set the initialized marker"
  else unless returned do
    throw <| .planInvariant .solana "entry IR does not set return data"

def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName &&
      ir.stateAccount == ir.sourcePlan.stateAccount do
    throw <| .planInvariant .solana "typed Solana IR identity/layout is not bound to its source Plan"
  unless isIdentifier ir.name && ir.name.toUTF8.size <= maxArtifactStemBytes do
    throw <| .planInvariant .solana "typed Solana IR has an unsafe artifact name"
  validateStateAccount ir.stateAccount
  if ir.handlers.size < 2 || ir.handlers.size > maxEntries + 1 then
    throw <| .planInvariant .solana "typed Solana IR handler count is outside the profile limits"
  unless ir.handlers[0]!.mode == .initialize && ir.handlers[0]!.name == "initialize" do
    throw <| .planInvariant .solana "typed Solana IR must begin with the canonical initializer"
  for index in [1:ir.handlers.size] do
    if ir.handlers[index]!.mode == .initialize then
      throw <| .planInvariant .solana "typed Solana IR may contain only one initializer"
  if hasDuplicates (ir.handlers.map (·.name)) ||
      hasDuplicates (ir.handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "typed Solana IR handler identities must be unique"
  let operationCount := ir.handlers.foldl (fun total handler =>
    total + handler.checks.size + handler.operations.size + handler.params.size) 0
  if operationCount > maxPlanNodes then
    throw <| .planInvariant .solana "typed Solana IR exceeds the aggregate node limit"
  for handler in ir.handlers do
    validateHandlerIR ir.sourcePlan handler
  let expectedHandlers := #[lowerHandler ir.sourcePlan ir.sourcePlan.initializer] ++
    ir.sourcePlan.entries.map (lowerHandler ir.sourcePlan)
  unless ir.handlers == expectedHandlers do
    throw <| .planInvariant .solana "typed Solana IR operations are not the exact lowering of its source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let handlers := #[lowerHandler plan plan.initializer] ++
    plan.entries.map (lowerHandler plan)
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    stateAccount := plan.stateAccount
    handlers
  }
  validateIR ir
  return ir

private def renderMode : HandlerMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderInitialization : InitializationPolicy → String
  | .mustBeUninitialized => "uninitialized"
  | .mustBeInitialized => "initialized"

private def natHex (value : Nat) : String :=
  if value == 0 then "0" else String.ofList (Nat.toDigits 16 value)

private def uint64Hex (value : UInt64) : String :=
  let raw := natHex value.toNat
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderCheck : Check → String
  | .instructionDataLen bytes => s!"  check instruction_data_len == {bytes}\n"
  | .ownerCurrentProgram accountIndex =>
      s!"  check account[{accountIndex}].owner == current_program\n"
  | .accountDataLen accountIndex bytes =>
      s!"  check account[{accountIndex}].data_len == {bytes}\n"
  | .signer accountIndex => s!"  check account[{accountIndex}].is_signer\n"
  | .writable accountIndex => s!"  check account[{accountIndex}].is_writable\n"
  | .headerEquals accountIndex byteOffset value =>
      s!"  check load_u64_le(account[{accountIndex}].data + {byteOffset}) == 0x{uint64Hex value}\n"

private def renderComparisonOp : ComparisonOp → String
  | .eq => "eq"
  | .ne => "ne"
  | .lt => "lt"
  | .le => "le"
  | .gt => "gt"
  | .ge => "ge"

/-- Plan-level declared-error program_error code base: declared error `i`
    traps with `0x{declaredErrorBase:x} + i`, disjoint from the arithmetic and
    assertion-failure policy codes. -/
def declaredErrorBase : Nat := 8192

private partial def renderOperation (indent : String)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding) :
    Operation → String
  | .literal destination value => s!"{indent}%{destination} = const_u64 {value}\n"
  | .loadParam destination dataOffset =>
      s!"{indent}%{destination} = load_u64_le(instruction_data + {dataOffset})\n"
  | .loadState destination accountIndex byteOffset =>
      s!"{indent}%{destination} = load_u64_le(account[{accountIndex}].data + {byteOffset})\n"
  | .checkedAdd destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_add_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedSub destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_sub_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .zeroState accountIndex byteOffset =>
      s!"{indent}zero_u64_le account[{accountIndex}].data + {byteOffset}\n"
  | .storeState accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, %{value}\n"
  | .setHeader accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, 0x{uint64Hex value}\n"
  | .setReturnData value => s!"{indent}set_return_data_u64_le %{value}\n"
  | .setReturnDataBool value => s!"{indent}set_return_data_bool %{value}\n"
  | .compare destination lhs rhs op =>
      s!"{indent}%{destination} = cmp_{renderComparisonOp op}_u64 %{lhs}, %{rhs}\n"
  | .assert condition errorCode =>
      s!"{indent}assert %{condition} else program_error 0x{natHex errorCode}\n"
  | .returnNone =>
      s!"{indent}exit\n"
  | .emitEvent eventIndex args =>
      let argText := String.intercalate ", " (args.toList.map (fun a => s!"%{a}"))
      s!"{indent}emit_event {events[eventIndex]!.name} {argText}\n"
  | .revertError errorIndex args =>
      let argText := String.intercalate ", " (args.toList.map (fun a => s!"%{a}"))
      s!"{indent}program_error 0x{natHex (declaredErrorBase + errorIndex)} ; {errors[errorIndex]!.name}({argText})\n"
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") events errors operation) ""
      let elseText := elseOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") events errors operation) ""
      s!"{indent}if %{condition} \{\n" ++ thenText ++
        s!"{indent}} else \{\n" ++ elseText ++ s!"{indent}}\n"
  | .switchRegion scrutinee cases defaultOps =>
      let caseText := cases.foldl (fun output (caseValue, ops) =>
        let body := ops.foldl (fun inner operation =>
          inner ++ renderOperation (indent ++ "  ") events errors operation) ""
        output ++ s!"{indent}case {caseValue} \{\n" ++ body ++ s!"{indent}}\n") ""
      let defaultText := defaultOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") events errors operation) ""
      s!"{indent}switch %{scrutinee} \{\n" ++ caseText ++
        s!"{indent}default \{\n" ++ defaultText ++ s!"{indent}}\n"

private def renderHandlerPlan (ir : IR) (handler : HandlerIR) : String :=
  let checks := handler.checks.foldl (fun output check => output ++ renderCheck check) ""
  let operations := handler.operations.foldl (fun output operation =>
    output ++ renderOperation "  " ir.sourcePlan.events ir.sourcePlan.errors operation) ""
  s!".handler {handler.discriminator} {handler.name} mode={renderMode handler.mode}\n" ++
    checks ++ operations ++ ".end-handler\n"

private def renderPlanText (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := account.fields.foldl (fun output field => output ++
    s!"; field source_id={field.sourceId} name={field.name} account={field.accountIndex} offset={field.byteOffset} type=u64-le\n") ""
  let handlers := ir.handlers.foldl (fun output handler =>
    output ++ renderHandlerPlan ir handler) ""
  "; PROOF-FORGE-SBPF-PLAN v1\n" ++
    "; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present\n" ++
    s!"; codegen-profile: {ir.sourcePlan.codegenProfile}\n" ++
    s!"; program: {ir.name}\n" ++
    s!"; state-account index={account.index} owner=current-program exact-data-len={account.exactDataLen}\n" ++
    s!"; header offset={account.headerOffset} type=u64-le initialized-marker=0x{uint64Hex account.initializedMarker} layout-domain={ir.sourcePlan.stateLayoutDomain}\n" ++
    "; initializer-payload-policy: zero-all-fields\n" ++
    fields ++ handlers

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"u64\",\"dataOffset\":{param.dataOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StateField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"offset\":{field.byteOffset},\"type\":\"u64-le\"}"

private def renderHandlerJson (handler : HandlerIR) : String :=
  let access := handler.accountAccess
  let signer := if access.signerRequired then "true" else "false"
  let writable := if access.writableRequired then "true" else "false"
  let returns :=
    if handler.mode == .initialize then "null"
    else match handler.resultKind with
      | .u64 => "\"u64-le\""
      | .bool => "\"bool\""
  "{" ++
    s!"\"name\":\"{Targets.escapeJson handler.name}\"," ++
    s!"\"discriminator\":\"{handler.discriminator}\"," ++
    s!"\"mode\":\"{renderMode handler.mode}\"," ++
    "\"accounts\":[{" ++
    s!"\"name\":\"state\",\"index\":{access.accountIndex}," ++
    "\"owner\":\"current-program\"," ++
    s!"\"isSigner\":{signer},\"isWritable\":{writable}," ++
    s!"\"initialization\":\"{renderInitialization access.initialization}\"" ++
    "}]," ++
    s!"\"args\":[{renderParamsJson handler.params}],\"returns\":{returns}" ++
    "}"

private def renderInterfaceBindingJson (binding : InterfaceBinding) : String :=
  "{\"name\":\"" ++ Targets.escapeJson binding.name ++
    "\",\"args\":[" ++
    String.intercalate "," ((List.range binding.fieldCount).map fun _ => "\"u64-le\"") ++
    "]}"

private def renderIdl (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := String.intercalate "," (account.fields.toList.map renderFieldJson)
  let handlers := String.intercalate ",\n    " (ir.handlers.toList.map renderHandlerJson)
  let events := String.intercalate "," (ir.sourcePlan.events.toList.map renderInterfaceBindingJson)
  let errors := String.intercalate "," (ir.sourcePlan.errors.toList.map renderInterfaceBindingJson)
  "{\n" ++
    "  \"version\": \"proof-forge-solana-idl/v1\",\n" ++
    s!"  \"name\": \"{Targets.escapeJson ir.name}\",\n" ++
    s!"  \"codegenProfile\": \"{ir.sourcePlan.codegenProfile}\",\n" ++
    "  \"deployable\": false,\n" ++
    "  \"instructionEncoding\": {" ++
    s!"\"discriminator\":\"sha256-prefix-{ir.sourcePlan.instructionDiscriminatorBytes}\"," ++
    s!"\"domain\":\"{ir.sourcePlan.instructionDiscriminatorDomain}\"," ++
    "\"arguments\":\"packed-u64-le\",\"trailingBytes\":\"reject\"},\n" ++
    "  \"accounts\": [{" ++
    s!"\"name\":\"state\",\"index\":{account.index}," ++
    "\"owner\":\"current-program\"," ++
    s!"\"exactDataLen\":{account.exactDataLen}," ++
    s!"\"header\":\{\"offset\":{account.headerOffset},\"type\":\"u64-le\",\"initializedMarker\":\"0x{uint64Hex account.initializedMarker}\",\"layoutDomain\":\"{ir.sourcePlan.stateLayoutDomain}\"}," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "}],\n" ++
    "  \"instructions\": [\n    " ++ handlers ++ "\n  ],\n" ++
    s!"  \"events\": [{events}],\n" ++
    s!"  \"errors\": [{errors}]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.sbpf-plan"
      mediaType := "application/vnd.proof-forge.sbpf-plan"
      contents := renderPlanText ir
    },
    {
      path := s!"{ir.name}.idl.json"
      mediaType := "application/json"
      contents := renderIdl ir
    }
  ]

/-- Replace handlers on an existing IR (private `mk`; for validateIR characterization). -/
def withHandlers (ir : IR) (handlers : Array HandlerIR) : IR :=
  { ir with handlers }

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

instance : Materializer .solana where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Solana
