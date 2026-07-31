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
/-- Policy program_error codes for the plan-only sBPF surface. Disjoint ranges:
    `0x1001` arithmetic overflow, `0x1002` bare assert failure, `0x1003` static
    loop-bound exceeded (reference `boundExceeded` at the latch back edge),
    and `declaredErrorBase + i` for declared program errors. -/
def arithmeticOverflowError : Nat := 0x1001
def assertionFailedError : Nat := 0x1002
/-- Static `for ... bounded N` exceeded: the (N+1)-th body has executed and the
    back edge is taken (reference `boundExceeded`). Distinct from arithmetic
    overflow and bare assert. -/
def loopBoundExceededError : Nat := 0x1003

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
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | bitNot (operand : Expr)
  | boolNot (operand : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | callFn (fnIndex : Nat) (args : Array Expr)
  /-- Plan-level loop induction temporary (bound by `Statement.forLoop`). -/
  | temp (id : Nat)
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
  /-- Bounded `for` recovered from a Normalize loop header/latch/exit CFG.
      `varTemp` is the induction temporary; `initial` seeds it; `cond` is the
      header predicate (references `.temp varTemp`); `update` is the latch
      expression (also may reference `.temp varTemp`); `maxIterations` is the
      static bound from `loopBounds` (reference enforces it at the back edge:
      the (N+1)-th body executes, then reverts); `body` is the then-arm region
      ending at the back edge. After the loop, control falls through. -/
  | forLoop (varTemp : Nat) (initial cond update : Expr) (maxIterations : Nat)
      (body : Array Statement)
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

/-- Pure local function binding (retained Semantic pureFn). Params reuse the
    handler Param layout; `resultIsBool` selects UInt64 vs Bool return. -/
structure FnBinding where
  name : String
  params : Array Param
  resultIsBool : Bool
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
  loopBoundExceededError : Nat
  programName : String
  stateAccount : StateAccount
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  fns : Array FnBinding
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
  /-- Structured bounded loop matching reference `noteBackEdge` semantics.
      `varTemp` is the IR induction temporary, seeded by `initial`.
      `counterTemp` is a completed-iteration counter seeded to 0 before the
      region (outer `const_u64 0`). Each iteration: evaluate `condOps`→`cond`;
      while true take `bodyOps`; then at the back edge run `boundOps` which
      assert `counter ≠ maxIterations` (else `loopBoundExceededError`) and
      rebind `counterTemp := counterNext` (`counter + 1`); then `updateOps`→
      `update` rebinds `varTemp`. Bodies 1..N pass the check; the (N+1)-th body
      runs and then errors; a return inside any body exits before the check.
      Latch `i + 1` cannot overflow under Normalize (`i < end ≤ UInt64.max`). -/
  | forRegion (varTemp initial counterTemp : Nat) (maxIterations : Nat)
      (condOps : Array Operation) (cond : Nat)
      (bodyOps : Array Operation)
      (boundOps : Array Operation) (counterNext : Nat)
      (updateOps : Array Operation) (update : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | checkedMul (destination lhs rhs errorCode : Nat)
  | checkedDiv (destination lhs rhs errorCode : Nat)
  | checkedMod (destination lhs rhs errorCode : Nat)
  | bitNot (destination source : Nat)
  | boolNot (destination source : Nat)
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

/-- Lowered pureFn body (plan-level temps; returns via setReturnData*/fn ret). -/
structure FnIR where
  name : String
  params : Array Param
  resultIsBool : Bool
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
  fns : Array FnIR
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

/-- Effect-boundary gate: values defined before `blockEntry` dominate this
    block (params, block-param slots, earlier pure SSA). Only in-block pure
    values between `blockEntry` and `segmentStart` are sealed by an effect. -/
private def currentValueV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= blockEntry && index < segmentStart then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Match-bind arm readability: the scrutinee of an enclosing switch may be
    referenced by its arm bodies across the (dominating) scrut-block boundary.
    Dominating pure SSA (`index < blockEntry`) is always readable so loop
    headers may consume pre-header values (e.g. the exclusive end bound). -/
private def currentValueWithArmsV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= blockEntry && index < segmentStart && !armReadables.contains id then
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

private def makeCheckedMulValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedMul lhsId rhsId lhs rhs false

private def makeCheckedDivValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedDiv lhsId rhsId lhs rhs false

private def makeCheckedModValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedMod lhsId rhsId lhs rhs false

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true

/-- Unary plan-value constructor (depth/node accounting for bitNot/boolNot). -/
private def makeUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  let depth := 1 + operand.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk operand.expr
    depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
    isBool
  }

private def makeBitNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 .bitNot operandId operand false

private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 .boolNot operandId operand true

/-- Pure local-call value: n-ary args, pure expression (not an effect boundary). -/
private def makeCallFnValueV1
    (fnIndex : Nat)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  let mut depth : Nat := 1
  let mut expandedNodes : Nat := 1
  for arg in args do
    depth := Nat.max depth (1 + arg.depth)
    if arg.expandedNodes > maxPlanNodes - expandedNodes then
      throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
    expandedNodes := expandedNodes + arg.expandedNodes
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  pure {
    expr := .callFn fnIndex (args.map (·.expr))
    depth
    expandedNodes
    dependencies := argIds
    isBool
  }

/-- Signature index for pureFn callables: CallableId → fnIndex, arity, result kind. -/
private structure PureFnTableV1 where
  byCallableId : Array (Option Nat)
  paramCounts : Array Nat
  resultIsBool : Array Bool

private def buildPureFnTableV1
    (types : SolanaTypeClosureV1)
    (callables : Array CallableV1) : CompileResult PureFnTableV1 := do
  let mut byCallableId : Array (Option Nat) := Array.mk (List.replicate callables.size none)
  let mut paramCounts : Array Nat := #[]
  let mut resultIsBool : Array Bool := #[]
  let mut i : Nat := 0
  for callable in callables do
    match callable.kind with
    | .pureFn =>
        if paramCounts.size >= maxEntries then
          throw <| .planInvariant .solana s!"pureFn count exceeds profile limit {maxEntries}"
        let name ← match callable.name with
          | some value => pure value
          | none => throw (.planInvariant .solana
              "unsupported Solana semantic shape: pureFn is missing its name")
        unless isIdentifier name do
          throw <| .planInvariant .solana s!"fn name '{name}' is not a safe identifier"
        unless callable.result.visibility == .public_ do
          throw <| .planInvariant .solana s!"fn '{name}' result is not public"
        let isBool := types.boolTypeId == some callable.result.typeId
        unless callable.result.typeId == types.uint64TypeId || isBool do
          throw <| .planInvariant .solana
            s!"fn '{name}' does not return public UInt64 or Bool"
        for param in callable.params do
          unless param.typeId == types.uint64TypeId && param.visibility == .public_ do
            throw <| .planInvariant .solana
              s!"fn '{name}' parameters must be public UInt64"
        byCallableId := byCallableId.set! i (some paramCounts.size)
        paramCounts := paramCounts.push callable.params.size
        resultIsBool := resultIsBool.push isBool
    | .invariant =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: invariants are outside the current UInt64 pilot"
    | .initializer | .entry | .view => pure ()
    i := i + 1
  pure { byCallableId, paramCounts, resultIsBool }

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  -- Only walk in-block segment values; dominating SSA is already closed.
  if root.toNat >= segmentStart then
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
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: dead or reordered value instructions"
  pure rootValue.expr

/-- Multi-root effect-boundary consumption (event/revert argument lists):
    every value produced in the current segment must be reachable from at
    least one sink root, mirroring the single-root discipline. -/
private def consumeSegmentRootsV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (roots : Array ValueIdV1) : CompileResult Unit := do
  for root in roots do
    let _ ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  for root in roots do
    if root.toNat >= segmentStart then
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
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: expression crosses an effect boundary"
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
    walker). Each block starts a fresh effect segment; dominating pure SSA
    (callable params, pre-allocated block-param slots, earlier blocks) remains
    readable. Block parameters are only legal on loop headers and are slotted
    before instruction lowering (see `allocateBlockParamSlotsV1`). -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (armReadables : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .solana
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let blockEntry := values0.size
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
        let lhs ← currentValueWithArmsV1 values blockEntry segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values blockEntry segmentStart armReadables rhsId
        unless !lhs.isBool && !rhs.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: binary operands must be UInt64"
        if op == .add then
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .sub then
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .mul then
          let value ← makeCheckedMulValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .div then
          let value ← makeCheckedDivValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .mod then
          let value ← makeCheckedModValueV1 lhsId rhsId lhs rhs
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
                "unsupported Solana semantic shape: only checked UInt64 add/sub/mul/div/mod and comparisons are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values blockEntry segmentStart armReadables operandId
        match op with
        | .bitNot =>
            unless !operand.isBool do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: bitNot operand must be UInt64"
            unless result.typeId == types.uint64TypeId do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: bitNot result must be UInt64"
            let value ← makeBitNotValueV1 operandId operand
            values := ← appendResultValueV1 types.uint64TypeId values result value
        | .not =>
            unless operand.isBool do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: boolNot operand must be Bool"
            let boolTypeId ← match types.boolTypeId with
              | some value => pure value
              | none => throw (.planInvariant .solana
                  "unsupported Solana semantic shape: Bool type is missing for boolNot")
            unless result.typeId == boolTypeId do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: boolNot result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTypeId values result value
        | .neg =>
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: unary neg is not admitted (checked negation desugars to 0 - x)"
    | .pureCall callableId argIds, some result =>
        -- Pure local call: value-producing, not an effect boundary (like checkedAdd).
        let fnIndex ← match pureFns.byCallableId[callableId.toNat]? with
          | some (some index) => pure index
          | _ =>
              throw <| .planInvariant .solana
                s!"unsupported Solana semantic shape: pureCall targets unknown pureFn {callableId.toNat}"
        unless argIds.size == pureFns.paramCounts[fnIndex]! do
          throw <| .planInvariant .solana
            s!"unsupported Solana semantic shape: pureCall arity mismatch for pureFn {fnIndex}"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !arg.isBool do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: pureCall arguments must be UInt64"
          argValues := argValues.push arg
        let resultIsBool := pureFns.resultIsBool[fnIndex]!
        let expectedTypeId ←
          if resultIsBool then
            match types.boolTypeId with
            | some value => pure value
            | none => throw (.planInvariant .solana
                "unsupported Solana semantic shape: Bool type is missing for pureCall result")
          else
            pure types.uint64TypeId
        unless result.typeId == expectedTypeId do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: pureCall result type does not match callee"
        let value ← makeCallFnValueV1 fnIndex argIds argValues resultIsBool
        values := ← appendResultValueV1 expectedTypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable writes state"
        let field ← findFieldV1 account stateId
        let stored ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        unless !stored.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: state store value must be UInt64"
        let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
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
        let cond ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
        unless cond.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert condition must be Bool"
        let value ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
        body := body.push (.assert value)
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable emits an event"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !root.isBool do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
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

/-- Region exit: forward join, path closed, or latch back-edge update. -/
private inductive RegionExitV1 where
  | join (blockId : Nat)
  | closed
  | latch (update : Expr)
  deriving Inhabited

private def findLoopBoundV1 (loopBounds : Array LoopBoundV1) (headerId : Nat) :
    Option LoopBoundV1 :=
  loopBounds.find? (fun lb => lb.header.toNat == headerId)

private def isLoopHeaderV1 (loopBounds : Array LoopBoundV1) (blockId : Nat) : Bool :=
  (findLoopBoundV1 loopBounds blockId).isSome

/-- Pre-allocate canonical block-parameter ValueId slots as plan `.temp`
    placeholders. Normalize places all block params (BlockId order) after
    callable params and before instruction results; only loop headers may
    carry the single UInt64 induction parameter. -/
private def allocateBlockParamSlotsV1
    (uint64TypeId : TypeIdV1)
    (loopBounds : Array LoopBoundV1)
    (blocks : Array BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  let mut values := values0
  for block in blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless isLoopHeaderV1 loopBounds block.id.toNat do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block parameters are only admitted on loop headers"
      unless block.params.size == 1 do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
      let some p := block.params[0]? |
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
      unless p.valueId.toNat == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block parameter ValueIds are not canonical"
      unless p.typeId == uint64TypeId do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop induction parameter must be UInt64"
      values := values.push {
        expr := .temp p.valueId.toNat
        depth := 1
        expandedNodes := 1
        dependencies := #[]
        isBool := false
      }
  pure values

/-- Read a jump-arg expression: args may be params, block-param temps, or
    dominating pure SSA (including the current block's open segment). When the
    arg is the sole sink of the current segment, consume that segment. -/
private def readJumpArgExprV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (argId : ValueIdV1) : CompileResult (Expr × Array LoweredValueV1 × Nat) := do
  let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
  unless !root.isBool do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: jump argument must be UInt64"
  if argId.toNat >= segmentStart then
    let expr ← consumeCurrentSegmentV1 values blockEntry segmentStart argId
    pure (expr, values, values.size)
  else if segmentStart == values.size then
    pure (root.expr, values, segmentStart)
  else
    -- Dominating arg with an open pure segment: leave the segment for a later
    -- consumer (e.g. pre-header limit used by the loop condition).
    pure (root.expr, values, segmentStart)

mutual
/-- Structured emission of multi-block CFGs: forward diamonds (branch/switch)
    and bounded for-loops recovered from `loopBounds` headers/latches.
    `enclosingHeaders` is the stack of active loop header ids (innermost last);
    a jump back to the innermost header ends the body with a latch update.
    Nested loop headers expand recursively. Returns (statements, values, exit).
    Mutually recursive with `lowerForLoopV1`. -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (enclosingHeaders : Array Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × RegionExitV1) := do
  if fuel == 0 then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: CFG region exceeds block bound"
  -- Starting directly on a loop header is only legal when the predecessor
  -- jump already expanded the loop; landing here otherwise is out of pilot.
  if isLoopHeaderV1 loopBounds start && !enclosingHeaders.contains start then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header must be entered via its pre-header jump"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: block ids are not dense"
  let lowered ← lowerBlockInstructionsV1
    owner mode types account pureFns armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  let blockEntry := values0.size
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .initialize =>
          throw <| .planInvariant .solana "initializer cannot return a value"
      | .mutate | .view =>
          let returned ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
          unless returned.isBool == expectsBoolReturn do
            throw <| .planInvariant .solana
              (if expectsBoolReturn then
                "unsupported Solana semantic shape: Bool entry/view must return a Bool value"
               else
                "unsupported Solana semantic shape: UInt64 entry/view must not return a Bool value")
          let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
          pure (instrs.push (.returnValue value), values, .closed)
  | .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, .closed)
  | .jump target =>
      let tid := target.blockId.toNat
      -- Latch back-edge: jump to the innermost enclosing loop header.
      if enclosingHeaders.back? == some tid then
        unless target.args.size == 1 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop latch must pass exactly one induction argument"
        let (update, values1, _) ←
          readJumpArgExprV1 values blockEntry segmentStart armReadables target.args[0]!
        pure (instrs, values1, .latch update)
      else if let some lb := findLoopBoundV1 loopBounds tid then
        -- Enter a (possibly nested) bounded for-loop at its pre-header jump.
        unless target.args.size == 1 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop entry must pass exactly one induction argument"
        let (initial, values1, _) ←
          readJumpArgExprV1 values blockEntry segmentStart armReadables target.args[0]!
        let (loopStmt, values2, exitId) ←
          lowerForLoopV1 owner mode expectsBoolReturn types account pureFns blocks
            loopBounds enclosingHeaders armReadables (fuel - 1) lb initial values1
        let (rest, values3, exit) ←
          emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
            loopBounds enclosingHeaders armReadables (fuel - 1) exitId values2
        pure (instrs ++ #[loopStmt] ++ rest, values3, exit)
      else
        -- Forward join: pure dominating values may remain for successors.
        pure (instrs, values, .join tid)
  | .branch condId thenT elseT =>
      let condVal ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
      unless condVal.isBool do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
      let (thenBody, values1, thenExit) ←
        emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
          loopBounds enclosingHeaders armReadables (fuel - 1) thenT.blockId.toNat values
      match thenExit with
      | .latch _ =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: branch then-arm cannot be a raw loop latch"
      | .closed =>
          let (elseBody, values2, elseExit) ←
            emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
              loopBounds enclosingHeaders armReadables (fuel - 1) elseT.blockId.toNat values1
          match elseExit with
          | .closed =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, .closed)
          | .join j =>
              let (rest, values3, exit) ←
                emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
                  loopBounds enclosingHeaders armReadables (fuel - 1) j values2
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, exit)
          | .latch _ =>
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: branch else-arm cannot be a raw loop latch"
      | .join j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, exit) ←
              emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
                loopBounds enclosingHeaders armReadables (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, exit)
          else
            let (elseBody, values2, elseExit) ←
              emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
                loopBounds enclosingHeaders armReadables (fuel - 1) elseT.blockId.toNat values1
            match elseExit with
            | .join j2 =>
                unless j == j2 do
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: branch arms converge on divergent joins"
                let (rest, values3, exit) ←
                  emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
                    loopBounds enclosingHeaders armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, exit)
            | .closed =>
                let (rest, values3, exit) ←
                  emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
                    loopBounds enclosingHeaders armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, exit)
            | .latch _ =>
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: branch else-arm cannot be a raw loop latch"
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values blockEntry segmentStart armReadables scrutId
      let scrut ← consumeCurrentSegmentV1 values blockEntry segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .solana
          "unsupported Solana semantic shape: switch must carry a default target")
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutVal.isBool switchCase.valueBytes
        let (body, values1, armExit) ←
          emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
            loopBounds enclosingHeaders (armReadables.push scrutId) (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        match armExit, joinAcc with
        | .closed, _ => pure ()
        | .join j, none => joinAcc := some j
        | .join j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: switch arms converge on divergent joins"
        | .latch _, _ =>
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: switch arm cannot be a loop latch"
      let (defaultBody, values2, defaultExit) ←
        emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
          loopBounds enclosingHeaders (armReadables.push scrutId) (fuel - 1)
          defaultT.blockId.toNat valuesA
      match defaultExit, joinAcc with
      | .closed, _ => pure ()
      | .join j, none => joinAcc := some j
      | .join j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: switch arms converge on divergent joins"
      | .latch _, _ =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: switch default cannot be a loop latch"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, .closed)
      | some j =>
          let (rest, values3, exit) ←
            emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
              loopBounds enclosingHeaders armReadables (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest, values3, exit)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
        unless !root.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, .closed)
  | .trap _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: trap terminators are outside the current pilot"

/-- Recover one bounded for-loop from its `loopBounds` entry: bind the header
    induction temp from `initial`, lower the header condition, walk the body
    until the latch back-edge, and return the exit block id (branch else). -/
private partial def lowerForLoopV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (enclosingHeaders : Array Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (lb : LoopBoundV1)
    (initial : Expr)
    (values0 : Array LoweredValueV1) :
    CompileResult (Statement × Array LoweredValueV1 × Nat) := do
  if fuel == 0 then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: CFG region exceeds block bound"
  let headerId := lb.header.toNat
  let header ← match blocks[headerId]? with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: loop header block is missing")
  unless header.id.toNat == headerId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header block id is not dense"
  unless header.params.size == 1 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
  let some induction := header.params[0]? |
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
  let varTemp := induction.valueId.toNat
  unless induction.typeId == types.uint64TypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop induction parameter must be UInt64"
  unless varTemp < values0.size do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop induction temp is not pre-allocated"
  -- Re-bind the induction slot to the plan temp (identity already `.temp`).
  let valuesBound := values0.set! varTemp {
    expr := .temp varTemp
    depth := 1
    expandedNodes := 1
    dependencies := #[]
    isBool := false
  }
  let lowered ← lowerBlockInstructionsV1
    owner mode types account pureFns armReadables header valuesBound
  unless lowered.statements.isEmpty do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header may not contain effectful statements"
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  let blockEntry := valuesBound.size
  match header.terminator with
  | .branch condId thenT elseT =>
      let condVal ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
      unless condVal.isBool do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
      let bodyId := thenT.blockId.toNat
      let exitId := elseT.blockId.toNat
      let headers' := enclosingHeaders.push headerId
      let (bodyStmts, values1, bodyExit) ←
        emitRegionV1 owner mode expectsBoolReturn types account pureFns blocks
          loopBounds headers' armReadables (fuel - 1) bodyId values
      match bodyExit with
      | .latch update =>
          pure (.forLoop varTemp initial cond update lb.maxIterations.toNat bodyStmts,
            values1, exitId)
      | .join _ | .closed =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop body must end at its latch back-edge"
  | _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loop header must terminate in a branch"
end

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.invariantSteps.isNone do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: callable must enter at block 0 without invariant fuel"
  -- Loop headers: exactly one UInt64 param and a matching loopBounds row.
  -- Non-header blocks must remain param-free. Degenerate param'd blocks
  -- without loopBounds stay fail-closed.
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else if isLoopHeaderV1 callable.loopBounds block.id.toNat then
      unless block.params.size == 1 do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
    else
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: block parameters are only admitted on loop headers"
  for lb in callable.loopBounds do
    let headerId := lb.header.toNat
    let latchId := lb.backEdgeFrom.toNat
    let some header := callable.blocks[headerId]? |
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loopBounds header is out of range"
    unless header.id.toNat == headerId && header.params.size == 1 do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loopBounds header is not a single-param loop header"
    let some latch := callable.blocks[latchId]? |
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loopBounds latch is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId.toNat == headerId && target.args.size == 1 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop latch must jump back with one induction arg"
    | _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop latch must be a jump back to its header"
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  let valuesPadded ← allocateBlockParamSlotsV1 types.uint64TypeId callable.loopBounds
    callable.blocks initialValues
  let (body0, values0, exit0) ←
    emitRegionV1 owner mode expectsBoolReturn types account pureFns callable.blocks
      callable.loopBounds #[] #[] callable.blocks.size 0 valuesPadded
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG (loop headers are expanded at their entry jump),
  -- so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextJoin : Option Nat :=
    match exit0 with
    | .join j => some j
    | .closed => none
    | .latch _ => none
  match exit0 with
  | .latch _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: top-level region cannot end in a loop latch"
  | _ => pure ()
  for _ in [0:callable.blocks.size] do
    match nextJoin with
    | none => break
    | some j =>
        let (rest, values1, exit1) ←
          emitRegionV1 owner mode expectsBoolReturn types account pureFns callable.blocks
            callable.loopBounds #[] #[] callable.blocks.size j values
        body := body ++ rest
        values := values1
        match exit1 with
        | .join j2 => nextJoin := some j2
        | .closed => nextJoin := none
        | .latch _ =>
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: top-level region cannot end in a loop latch"
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
    (pureFns : PureFnTableV1)
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
  let lowered ← lowerCallableV1 "initializer" .initialize false types account pureFns callable
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
    (pureFns : PureFnTableV1)
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
    types account pureFns callable
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

private def makePureFnV1
    (types : SolanaTypeClosureV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (callable : CallableV1) : CompileResult FnBinding := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: pureFn is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .solana s!"fn name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .solana s!"fn '{name}' result is not public"
  let resultIsBool := types.boolTypeId == some callable.result.typeId
  unless callable.result.typeId == types.uint64TypeId || resultIsBool do
    throw <| .planInvariant .solana
      s!"fn '{name}' does not return public UInt64 or Bool"
  -- pureFn bodies use view mode so store/emit fail closed at the lowerer.
  let lowered ← lowerCallableV1 s!"fn '{name}'" .view resultIsBool
    types account pureFns callable
  pure {
    name
    params := lowered.params
    resultIsBool
    body := lowered.body
  }

private partial def planExprNodes? (account : StateAccount) (params : Array Param)
    (fns : Array FnBinding)
    (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    match expr with
    | .literal .. => some 1
    | .temp _ => some 1
    | .param dataOffset => if params.any (·.dataOffset == dataOffset) then some 1 else none
    | .stateLoad accountIndex byteOffset =>
        if account.fields.any (fun field =>
            field.accountIndex == accountIndex && field.byteOffset == byteOffset) then
          some 1
        else
          none
    | .checkedAdd lhs rhs | .checkedSub lhs rhs
    | .checkedMul lhs rhs | .checkedDiv lhs rhs | .checkedMod lhs rhs
    | .compare _ lhs rhs =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params fns childDepth available lhs with
        | none => none
        | some lhsNodes =>
            match planExprNodes? account params fns childDepth (available - lhsNodes) rhs with
            | none => none
            | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    | .bitNot operand | .boolNot operand =>
        let childDepth := depthLeft - 1
        let available := nodeBudget - 1
        match planExprNodes? account params fns childDepth available operand with
        | none => none
        | some n => some (1 + n)
    | .callFn fnIndex args =>
        match fns[fnIndex]? with
        | none => none
        | some fn =>
            if args.size != fn.params.size then
              none
            else
              let childDepth := depthLeft - 1
              let rec walk (remaining : List Expr) (available totalNodes : Nat) : Option Nat :=
                match remaining with
                | [] => some totalNodes
                | arg :: rest =>
                    match planExprNodes? account params fns childDepth available arg with
                    | none => none
                    | some n => walk rest (available - n) (totalNodes + n)
              walk args.toList (nodeBudget - 1) 1

/-- UInt64-compatible plan expression (comparison/boolNot results and
    Bool-returning callFn results are not UInt64). -/
private def exprIsUInt64CompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. | .boolNot _ => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => !fn.resultIsBool
      | none => false
  | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .bitNot _
  | .checkedAdd .. | .checkedSub .. | .literal _ | .param _ | .stateLoad ..
  | .temp _ => true

/-- Bool-compatible plan expression (compare/boolNot and Bool-returning callFn). -/
private def exprIsBoolCompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. | .boolNot _ => true
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => fn.resultIsBool
      | none => false
  | .literal _ => true
  | .checkedMul .. | .checkedDiv .. | .checkedMod .. | .bitNot _
  | .checkedAdd .. | .checkedSub .. | .param _ | .stateLoad .. | .temp _ => false

private def addPlanExprNodes (account : StateAccount) (params : Array Param)
    (fns : Array FnBinding) (total : Nat) (expr : Expr) : CompileResult Nat := do
  if total >= maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  match planExprNodes? account params fns maxExprDepth (maxPlanNodes - total) expr with
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
    (fns : Array FnBinding)
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
        total ← addPlanExprNodes account params fns total store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .solana "initializer cannot return a value"
        total ← addPlanExprNodes account params fns total value
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
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .solana "handler event arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params fns total arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .solana "handler reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .solana "handler error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .solana "handler error arguments must be UInt64 expressions"
          total ← addPlanExprNodes account params fns total arg
        total := total + 1
        closed := true
    | .assert condition =>
        unless exprIsBoolCompatibleV1 fns condition do
          throw <| .planInvariant .solana "handler assert condition must be a Bool expression"
        total ← addPlanExprNodes account params fns total condition
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes account params fns total condition
        total := total + 1
        let (t1, c1) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params thenBody total
        let (t2, c2) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params elseBody t1
        total := t2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes account params fns total scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, c) ← checkHandlerStatementsV1
            account isInitializer isView false
            eventCount eventFieldCounts errorCount errorFieldCounts fns params caseBody total
          total := t
          allClosed := allClosed && c
        let (td, cd) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params defaultBody total
        total := td
        closed := allClosed && cd
    | .forLoop _varTemp initial cond update maxIterations body =>
        total ← addPlanExprNodes account params fns total initial
        total ← addPlanExprNodes account params fns total cond
        total ← addPlanExprNodes account params fns total update
        total := total + 1
        -- maxIterations is wire-capped at 4096 by Normalize/structure gates.
        unless maxIterations <= 4096 do
          throw <| .planInvariant .solana
            "handler forLoop maxIterations exceeds the wire ceiling 4096"
        let (tBody, cBody) ← checkHandlerStatementsV1
          account isInitializer isView false
          eventCount eventFieldCounts errorCount errorFieldCounts fns params body total
        total := tBody
        -- A loop body that returns/reverts on every path still leaves the
        -- post-loop fallthrough reachable only when the body is open; the
        -- loop statement itself never closes the enclosing region.
        closed := false
        let _ := cBody
  pure (total, closed)

private def expectedAccess (account : StateAccount) (mode : HandlerMode) : AccountAccess :=
  accessFor account mode

private def validateHandler (account : StateAccount) (isInitializer : Bool)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
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
    fns handler.params handler.body baseNodes
  unless closed do
    throw <| .planInvariant .solana
      s!"handler '{handler.name}' does not terminate on all paths"
  return total

private def validateFnBinding (account : StateAccount)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
    (baseNodes : Nat) (fn : FnBinding) : CompileResult Nat := do
  unless isIdentifier fn.name do
    throw <| .planInvariant .solana s!"fn '{fn.name}' has an invalid name"
  validateParams s!"fn '{fn.name}'" fn.params
  if fn.body.isEmpty || fn.body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"fn '{fn.name}' has an invalid body size"
  -- pureFn bodies: isView=true bans store/emit; no bare returnNone.
  let (total, closed) ← checkHandlerStatementsV1
    account false true false
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    fns fn.params fn.body baseNodes
  unless closed do
    throw <| .planInvariant .solana
      s!"fn '{fn.name}' does not terminate on all paths"
  return total

/-- Validate the public target-owned Plan before typed IR lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  unless plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.instructionDiscriminatorDomain == discriminatorDomain &&
      plan.instructionDiscriminatorBytes == discriminatorBytes &&
      plan.stateLayoutDomain == layoutDomain &&
      plan.arithmeticOverflowError == arithmeticOverflowError &&
      plan.assertionFailedError == assertionFailedError &&
      plan.loopBoundExceededError == loopBoundExceededError do
    throw <| .planInvariant .solana "Solana Plan profile/error policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .solana s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > maxArtifactStemBytes then
    throw <| .planInvariant .solana
      s!"program name exceeds artifact-stem limit {maxArtifactStemBytes} bytes"
  validateStateAccount plan.stateAccount
  if plan.entries.isEmpty || plan.entries.size > maxEntries then
    throw <| .planInvariant .solana "entry count is outside the profile limits"
  if plan.fns.size > maxEntries then
    throw <| .planInvariant .solana s!"pureFn count exceeds profile limit {maxEntries}"
  let handlerCount := 1 + plan.entries.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total handler => total + handler.params.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total handler => total + handler.body.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.body.size) 0
  let mut total := plan.stateAccount.fields.size + handlerCount + plan.fns.size +
    paramCount + statementCount
  if total > maxPlanNodes then
    throw <| .planInvariant .solana s!"plan exceeds aggregate node limit {maxPlanNodes}"
  for fn in plan.fns do
    total ← validateFnBinding plan.stateAccount plan.events plan.errors plan.fns total fn
  if hasDuplicates (plan.fns.map (·.name)) then
    throw <| .planInvariant .solana "fn names must be unique"
  total ← validateHandler plan.stateAccount true plan.events plan.errors plan.fns
    total plan.initializer
  for handler in plan.entries do
    total ← validateHandler plan.stateAccount false plan.events plan.errors plan.fns
      total handler
  let handlers := #[plan.initializer] ++ plan.entries
  if hasDuplicates (handlers.map (·.name)) then
    throw <| .planInvariant .solana "handler names must be unique"
  if hasDuplicates (handlers.map (·.discriminator)) then
    throw <| .planInvariant .solana "handler discriminators collide"
  -- pureFn names must not collide with handler names either.
  if hasDuplicates (handlers.map (·.name) ++ plan.fns.map (·.name)) then
    throw <| .planInvariant .solana "handler and fn names must be unique together"

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
  -- init+entries ≤ maxEntries+1; pureFns ≤ maxEntries (checked in buildPureFnTableV1).
  if source.callables.size > maxEntries + 1 + maxEntries then
    throw <| .planInvariant .solana
      s!"callable count exceeds Solana profile limit {maxEntries + 1 + maxEntries}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .solana
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateSolanaTypeClosureV1 source.types
  let stateAccount ← makeStateAccountV1 types.uint64TypeId source.logicalState
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let pureFnTable ← buildPureFnTableV1 types source.callables
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let mut initializer : Option Handler := none
  let mut entries : Array Handler := #[]
  let mut fns : Array FnBinding := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .solana "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types stateAccount pureFnTable callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .solana s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types stateAccount pureFnTable callable)
    | .pureFn =>
        fns := fns.push (← makePureFnV1 types stateAccount pureFnTable callable)
    | .invariant =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: invariants are outside the current UInt64 pilot"
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
    loopBoundExceededError
    programName
    stateAccount
    events
    errors
    fns
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

/-- Lookup plan-level loop induction temp → IR temp. Missing binding is a
    plan/IR construction bug (validatePlan admits `.temp` only under forLoop). -/
private def resolveTempV1 (tempMap : List (Nat × Nat)) (id : Nat) : Nat :=
  match tempMap.find? (fun p => p.1 == id) with
  | some (_, irTemp) => irTemp
  | none => id

private partial def lowerExpr (overflowError : Nat) (tempMap : List (Nat × Nat))
    (next : Nat) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param dataOffset =>
      { operations := #[.loadParam next dataOffset], value := next, next := next + 1 }
  | .stateLoad accountIndex byteOffset =>
      { operations := #[.loadState next accountIndex byteOffset], value := next, next := next + 1 }
  | .temp id =>
      let irTemp := resolveTempV1 tempMap id
      { operations := #[], value := irTemp, next }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value overflowError]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand =>
      let operand := lowerExpr overflowError tempMap next operand
      {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .boolNot operand =>
      let operand := lowerExpr overflowError tempMap next operand
      {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr overflowError tempMap next lhs
      let rhs := lowerExpr overflowError tempMap lhs.next rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .callFn fnIndex args =>
      Id.run do
        let mut operations : Array Operation := #[]
        let mut next := next
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let lowered := lowerExpr overflowError tempMap next arg
          operations := operations ++ lowered.operations
          argTemps := argTemps.push lowered.value
          next := lowered.next
        {
          operations := operations ++ #[.callFn fnIndex next argTemps]
          value := next
          next := next + 1
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
      | .store _ | .assert _ | .emitEvent .. | .forLoop .. => false
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
    (overflowError : Nat) (resultKind : ResultKind) (assertErr boundErr : Nat)
    (tempMap : List (Nat × Nat))
    (next : Nat) (statements : Array Statement) : Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr overflowError tempMap next store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState store.accountIndex store.byteOffset value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr overflowError tempMap next value
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
          let value := lowerExpr overflowError tempMap next arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr overflowError tempMap next arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .assert condition =>
        let value := lowerExpr overflowError tempMap next condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value assertErr)
        next := value.next
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr overflowError tempMap next condition
        operations := operations ++ value.operations
        let (thenOps, next1) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap value.next thenBody
        let (elseOps, next2) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap next1 elseBody
        operations := operations.push (.ifRegion value.value
          (armOpsWithHardExit thenBody thenOps) (armOpsWithHardExit elseBody elseOps))
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr overflowError tempMap next scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) :=
            lowerBodyOps overflowError resultKind assertErr boundErr tempMap nextC caseBody
          caseOps := caseOps.push (caseValue, armOpsWithHardExit caseBody ops)
          nextC := next1
        let (defaultOps, nextD) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap nextC defaultBody
        operations := operations.push (.switchRegion value.value caseOps
          (armOpsWithHardExit defaultBody defaultOps))
        next := nextD
    | .forLoop varTemp initial cond update maxIterations body =>
        -- Seed induction from `initial`, allocate completed-iteration counter
        -- at 0, then bind plan varTemp → induction IR temp.
        let initL := lowerExpr overflowError tempMap next initial
        operations := operations ++ initL.operations
        let irVar := initL.value
        let counterTemp := initL.next
        operations := operations.push (.literal counterTemp 0)
        let tempMap' := (varTemp, irVar) :: tempMap
        let afterSeed := counterTemp + 1
        let condL := lowerExpr overflowError tempMap' afterSeed cond
        let (bodyOps, nextBody) :=
          lowerBodyOps overflowError resultKind assertErr boundErr tempMap' condL.next body
        -- Back-edge bound check (reference noteBackEdge): after the body, if
        -- completed iterations already equal N, revert boundExceeded; else
        -- increment the counter. Counter ≤ N ≤ 4096 so +1 cannot overflow;
        -- still use checked_add to stay within the existing opcode set.
        let litN := nextBody
        let eqT := nextBody + 1
        let okT := nextBody + 2
        let lit1 := nextBody + 3
        let counterNext := nextBody + 4
        let boundOps : Array Operation := #[
          .literal litN (UInt64.ofNat maxIterations),
          .compare eqT counterTemp litN .eq,
          .boolNot okT eqT,
          .assert okT boundErr,
          .literal lit1 1,
          .checkedAdd counterNext counterTemp lit1 overflowError
        ]
        let updateL := lowerExpr overflowError tempMap' (counterNext + 1) update
        operations := operations.push (.forRegion irVar irVar counterTemp maxIterations
          condL.operations condL.value bodyOps boundOps counterNext
          updateL.operations updateL.value)
        next := updateL.next
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
    plan.arithmeticOverflowError handler.resultKind
    plan.assertionFailedError plan.loopBoundExceededError [] 0 body
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
      .checkedSub destination .. | .checkedMul destination .. |
      .checkedDiv destination .. | .checkedMod destination .. |
      .bitNot destination _ | .boolNot destination _ |
      .compare destination .. | .callFn _ destination _ => some destination
  | _ => none

private def lowerFn (plan : Plan) (fn : FnBinding) : FnIR := Id.run do
  let resultKind : ResultKind := if fn.resultIsBool then .bool else .u64
  let (bodyOps, _) := lowerBodyOps
    plan.arithmeticOverflowError resultKind
    plan.assertionFailedError plan.loopBoundExceededError [] 0 fn.body
  {
    name := fn.name
    params := fn.params
    resultIsBool := fn.resultIsBool
    operations := bodyOps
  }
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
    | .checkedMul .. | .checkedDiv .. | .checkedMod ..
    | .bitNot .. | .boolNot ..
    | .compare .. | .assert .. | .zeroState .. | .storeState ..
    | .setHeader .. | .setReturnData .. | .setReturnDataBool ..
    | .emitEvent .. | .revertError ..
    | .ifRegion .. | .switchRegion .. | .forRegion .. | .callFn .. =>
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
    | .checkedMul _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-mul operands/error are invalid"
    | .checkedDiv _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-div operands/error are invalid"
    | .checkedMod _ lhs rhs errorCode =>
        unless lhs < next - 1 && rhs < next - 1 &&
            errorCode == plan.arithmeticOverflowError do
          throw <| .planInvariant .solana "typed Solana IR checked-mod operands/error are invalid"
    | .bitNot _ source =>
        unless source < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR bitNot operand is invalid"
    | .boolNot _ source =>
        unless source < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR boolNot operand is invalid"
    | .compare _ lhs rhs _op =>
        unless lhs < next - 1 && rhs < next - 1 do
          throw <| .planInvariant .solana "typed Solana IR compare operands are invalid"
    | .callFn fnIndex _destination args =>
        unless fnIndex < plan.fns.size do
          throw <| .planInvariant .solana "typed Solana IR callFn index is out of range"
        unless args.size == plan.fns[fnIndex]!.params.size do
          throw <| .planInvariant .solana "typed Solana IR callFn arity is invalid"
        unless args.all (· < next - 1) do
          throw <| .planInvariant .solana "typed Solana IR callFn arguments are invalid"
    | .assert condition errorCode =>
        -- Bare assert uses assertionFailedError; for-loop back-edge bound
        -- checks use loopBoundExceededError (validated further in forRegion).
        unless condition < next &&
            (errorCode == plan.assertionFailedError ||
              errorCode == plan.loopBoundExceededError) do
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
    | .forRegion varTemp initial counterTemp maxIterations condOps cond bodyOps
          boundOps counterNext updateOps update =>
        unless varTemp == initial && initial < next && counterTemp < next &&
            counterTemp != varTemp do
          throw <| .planInvariant .solana "typed Solana IR for-region induction/counter binding is invalid"
        unless maxIterations <= 4096 do
          throw <| .planInvariant .solana "typed Solana IR for-region maxIterations exceeds 4096"
        let (nCond, rCond, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets condOps next
        unless !rCond && cond < nCond do
          throw <| .planInvariant .solana "typed Solana IR for-region condition is invalid"
        let (nBody, rBody, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets bodyOps nCond
        unless !rBody do
          throw <| .planInvariant .solana
            "typed Solana IR for-region body must not close every path (post-loop fallthrough)"
        -- Bound-check sequence is fixed: lit N, cmp_eq counter, bool_not, assert
        -- with loopBoundExceededError, lit 1, checked_add → counterNext.
        unless boundOps.size == 6 do
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check shape is invalid"
        let (nBound, rBound, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets boundOps nBody
        unless !rBound && counterNext < nBound && counterNext + 1 == nBound do
          throw <| .planInvariant .solana "typed Solana IR for-region counter rebind is invalid"
        let some op0 := boundOps[0]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op0"
        let some op1 := boundOps[1]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op1"
        let some op2 := boundOps[2]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op2"
        let some op3 := boundOps[3]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op3"
        let some op4 := boundOps[4]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op4"
        let some op5 := boundOps[5]? |
          throw <| .planInvariant .solana "typed Solana IR for-region bound-check missing op5"
        match op0, op1, op2, op3, op4, op5 with
        | Operation.literal nLit nVal,
          Operation.compare eqT cT nT ComparisonOp.eq,
          Operation.boolNot okT eqSrc,
          Operation.assert okSrc errCode,
          Operation.literal oneLit oneVal,
          Operation.checkedAdd dest lhs rhs errAdd =>
            unless nLit + 1 == eqT && eqT + 1 == okT && okT + 1 == oneLit &&
                oneLit + 1 == dest && dest == counterNext do
              throw <| .planInvariant .solana
                "typed Solana IR for-region bound-check temps are not dense"
            unless nVal.toNat == maxIterations && nT == nLit && cT == counterTemp do
              throw <| .planInvariant .solana
                "typed Solana IR for-region bound compare is not counter == maxIterations"
            unless eqSrc == eqT && okSrc == okT &&
                errCode == plan.loopBoundExceededError do
              throw <| .planInvariant .solana
                "typed Solana IR for-region bound assert/error is invalid"
            unless oneVal == 1 && lhs == counterTemp && rhs == oneLit && dest == counterNext &&
                errAdd == plan.arithmeticOverflowError do
              throw <| .planInvariant .solana
                "typed Solana IR for-region counter increment is invalid"
        | _, _, _, _, _, _ =>
            throw <| .planInvariant .solana
              "typed Solana IR for-region bound-check opcodes are invalid"
        let (nUpd, rUpd, _) ←
          validateOperationSequence plan handler fieldOffsets paramOffsets updateOps nBound
        unless !rUpd && update < nUpd do
          throw <| .planInvariant .solana "typed Solana IR for-region update is invalid"
        next := nUpd
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

private def validateFnIR (plan : Plan) (fn : FnIR) : CompileResult Unit := do
  unless isIdentifier fn.name do
    throw <| .planInvariant .solana "typed Solana IR has an invalid fn name"
  validateParams s!"IR fn '{fn.name}'" fn.params
  -- Synthetic view-mode handler so store/emit fail and setReturnData* is accepted.
  let resultKind : ResultKind := if fn.resultIsBool then .bool else .u64
  let synthetic : HandlerIR := {
    name := fn.name
    discriminator := instructionDiscriminator fn.name fn.params
    params := fn.params
    mode := .view
    resultKind
    accountAccess := accessFor plan.stateAccount .view
    checks := #[]
    operations := fn.operations
  }
  let fieldOffsets := plan.stateAccount.fields.map (·.byteOffset)
  let paramOffsets := fn.params.map (·.dataOffset)
  let (_, returned, _) ← validateOperationSequence
    plan synthetic fieldOffsets paramOffsets fn.operations 0
  unless returned do
    throw <| .planInvariant .solana s!"fn IR '{fn.name}' does not set return data"
  -- pureFn bodies must not load state (purity defense beyond view-mode write ban).
  for op in fn.operations do
    match op with
    | .loadState .. | .storeState .. | .zeroState .. | .setHeader ..
    | .emitEvent .. =>
        throw <| .planInvariant .solana
          s!"fn IR '{fn.name}' contains a non-pure operation"
    | .ifRegion _ thenOps elseOps =>
        for nested in thenOps ++ elseOps do
          match nested with
          | .loadState .. | .storeState .. | .emitEvent .. =>
              throw <| .planInvariant .solana
                s!"fn IR '{fn.name}' contains a non-pure nested operation"
          | _ => pure ()
    | .switchRegion _ cases defaultOps =>
        let nestedOps := cases.foldl (fun acc (_, ops) => acc ++ ops) defaultOps
        for nested in nestedOps do
          match nested with
          | .loadState .. | .storeState .. | .emitEvent .. =>
              throw <| .planInvariant .solana
                s!"fn IR '{fn.name}' contains a non-pure nested operation"
          | _ => pure ()
    | .forRegion _ _ _ _ condOps _ bodyOps boundOps _ updateOps _ =>
        for nested in condOps ++ bodyOps ++ boundOps ++ updateOps do
          match nested with
          | .loadState .. | .storeState .. | .emitEvent .. =>
              throw <| .planInvariant .solana
                s!"fn IR '{fn.name}' contains a non-pure nested operation"
          | _ => pure ()
    | _ => pure ()

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
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .solana "typed Solana IR fn count does not match its source Plan"
  if hasDuplicates (ir.fns.map (·.name)) then
    throw <| .planInvariant .solana "typed Solana IR fn names must be unique"
  let operationCount := ir.handlers.foldl (fun total handler =>
    total + handler.checks.size + handler.operations.size + handler.params.size) 0 +
    ir.fns.foldl (fun total fn => total + fn.operations.size + fn.params.size) 0
  if operationCount > maxPlanNodes then
    throw <| .planInvariant .solana "typed Solana IR exceeds the aggregate node limit"
  for fn in ir.fns do
    validateFnIR ir.sourcePlan fn
  for handler in ir.handlers do
    validateHandlerIR ir.sourcePlan handler
  let expectedFns := ir.sourcePlan.fns.map (lowerFn ir.sourcePlan)
  unless ir.fns == expectedFns do
    throw <| .planInvariant .solana "typed Solana IR fns are not the exact lowering of its source Plan"
  let expectedHandlers := #[lowerHandler ir.sourcePlan ir.sourcePlan.initializer] ++
    ir.sourcePlan.entries.map (lowerHandler ir.sourcePlan)
  unless ir.handlers == expectedHandlers do
    throw <| .planInvariant .solana "typed Solana IR operations are not the exact lowering of its source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let fns := plan.fns.map (lowerFn plan)
  let handlers := #[lowerHandler plan plan.initializer] ++
    plan.entries.map (lowerHandler plan)
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    stateAccount := plan.stateAccount
    fns
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
    (fns : Array FnBinding) (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnReturnStyle : Bool) :
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
  | .checkedMul destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_mul_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedDiv destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_div_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .checkedMod destination lhs rhs errorCode =>
      s!"{indent}%{destination} = checked_rem_u64 %{lhs}, %{rhs} else program_error 0x{natHex errorCode}\n"
  | .bitNot destination source =>
      s!"{indent}%{destination} = bitnot_u64 %{source}\n"
  | .boolNot destination source =>
      s!"{indent}%{destination} = bool_not %{source}\n"
  | .zeroState accountIndex byteOffset =>
      s!"{indent}zero_u64_le account[{accountIndex}].data + {byteOffset}\n"
  | .storeState accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, %{value}\n"
  | .setHeader accountIndex byteOffset value =>
      s!"{indent}store_u64_le account[{accountIndex}].data + {byteOffset}, 0x{uint64Hex value}\n"
  | .setReturnData value =>
      if fnReturnStyle then s!"{indent}ret %{value}\n"
      else s!"{indent}set_return_data_u64_le %{value}\n"
  | .setReturnDataBool value =>
      if fnReturnStyle then s!"{indent}ret %{value}\n"
      else s!"{indent}set_return_data_bool %{value}\n"
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
  | .callFn fnIndex destination args =>
      let name := fns[fnIndex]!.name
      let argText := String.intercalate ", " (args.toList.map (fun a => s!"%{a}"))
      if args.isEmpty then
        s!"{indent}%{destination} = call {name}\n"
      else
        s!"{indent}%{destination} = call {name} {argText}\n"
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
      let elseText := elseOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
      s!"{indent}if %{condition} \{\n" ++ thenText ++
        s!"{indent}} else \{\n" ++ elseText ++ s!"{indent}}\n"
  | .switchRegion scrutinee cases defaultOps =>
      let caseText := cases.foldl (fun output (caseValue, ops) =>
        let body := ops.foldl (fun inner operation =>
          inner ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
        output ++ s!"{indent}case {caseValue} \{\n" ++ body ++ s!"{indent}}\n") ""
      let defaultText := defaultOps.foldl (fun output operation =>
        output ++ renderOperation (indent ++ "  ") fns events errors fnReturnStyle operation) ""
      s!"{indent}switch %{scrutinee} \{\n" ++ caseText ++
        s!"{indent}default \{\n" ++ defaultText ++ s!"{indent}}\n"
  | .forRegion varTemp initial counterTemp maxIterations condOps cond bodyOps
        boundOps counterNext updateOps update =>
      -- Structured loop_u64 form: induction + completed-iteration counter,
      -- then cond / body / bound (back-edge check) / update sections.
      -- Bound check matches reference noteBackEdge: after body N+1,
      -- counter == N ⇒ program_error 0x1003 (loopBoundExceededError); else
      -- counter := counter + 1. Latch i+1 overflow is unreachable under
      -- Normalize (i < end ≤ UInt64.max). Counter +1 is also safe (≤4096).
      let nested := indent ++ "  "
      let condText := condOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      let bodyText := bodyOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      let boundText := boundOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      let updateText := updateOps.foldl (fun output operation =>
        output ++ renderOperation nested fns events errors fnReturnStyle operation) ""
      s!"{indent}loop_u64 %{varTemp} = %{initial} counter=%{counterTemp} max={maxIterations}\n" ++
        s!"{indent}cond \{\n" ++ condText ++
          s!"{nested}; cond_temp %{cond}\n" ++ s!"{indent}}\n" ++
        s!"{indent}body \{\n" ++ bodyText ++ s!"{indent}}\n" ++
        s!"{indent}bound \{\n" ++ boundText ++
          s!"{nested}; counter_next %{counterNext}\n" ++ s!"{indent}}\n" ++
        s!"{indent}update \{\n" ++ updateText ++
          s!"{nested}; update_temp %{update}\n" ++ s!"{indent}}\n"

private def renderFnPlan (ir : IR) (index : Nat) (fn : FnIR) : String :=
  let result := if fn.resultIsBool then "bool" else "u64"
  let operations := fn.operations.foldl (fun output operation =>
    output ++ renderOperation "  " ir.sourcePlan.fns ir.sourcePlan.events
      ir.sourcePlan.errors true operation) ""
  s!".fn {index} {fn.name} (-> {result})\n" ++ operations ++ ".end-fn\n"

private def renderHandlerPlan (ir : IR) (handler : HandlerIR) : String :=
  let checks := handler.checks.foldl (fun output check => output ++ renderCheck check) ""
  let operations := handler.operations.foldl (fun output operation =>
    output ++ renderOperation "  " ir.sourcePlan.fns ir.sourcePlan.events
      ir.sourcePlan.errors false operation) ""
  s!".handler {handler.discriminator} {handler.name} mode={renderMode handler.mode}\n" ++
    checks ++ operations ++ ".end-handler\n"

private def renderPlanText (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := account.fields.foldl (fun output field => output ++
    s!"; field source_id={field.sourceId} name={field.name} account={field.accountIndex} offset={field.byteOffset} type=u64-le\n") ""
  let fnsText := Id.run do
    let mut text := ""
    for index in [0:ir.fns.size] do
      text := text ++ renderFnPlan ir index ir.fns[index]!
    pure text
  let handlers := ir.handlers.foldl (fun output handler =>
    output ++ renderHandlerPlan ir handler) ""
  "; PROOF-FORGE-SBPF-PLAN v1\n" ++
    "; PLAN-ONLY NON-EXECUTABLE: no sBPF instructions, object, or ELF are present\n" ++
    s!"; codegen-profile: {ir.sourcePlan.codegenProfile}\n" ++
    s!"; program: {ir.name}\n" ++
    s!"; state-account index={account.index} owner=current-program exact-data-len={account.exactDataLen}\n" ++
    s!"; header offset={account.headerOffset} type=u64-le initialized-marker=0x{uint64Hex account.initializedMarker} layout-domain={ir.sourcePlan.stateLayoutDomain}\n" ++
    "; initializer-payload-policy: zero-all-fields\n" ++
    fields ++ fnsText ++ handlers

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

private def renderFnJson (fn : FnIR) : String :=
  let result := if fn.resultIsBool then "bool" else "u64"
  "{" ++
    s!"\"name\":\"{Targets.escapeJson fn.name}\"," ++
    s!"\"argCount\":{fn.params.size}," ++
    s!"\"result\":\"{result}\"" ++
    "}"

private def renderIdl (ir : IR) : String :=
  let account := ir.stateAccount
  let fields := String.intercalate "," (account.fields.toList.map renderFieldJson)
  let handlers := String.intercalate ",\n    " (ir.handlers.toList.map renderHandlerJson)
  let events := String.intercalate "," (ir.sourcePlan.events.toList.map renderInterfaceBindingJson)
  let errors := String.intercalate "," (ir.sourcePlan.errors.toList.map renderInterfaceBindingJson)
  let fns := String.intercalate "," (ir.fns.toList.map renderFnJson)
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
    s!"  \"fns\": [{fns}],\n" ++
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

/-- Replace pureFn IR table (private `mk`; for validateIR characterization). -/
def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }

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
