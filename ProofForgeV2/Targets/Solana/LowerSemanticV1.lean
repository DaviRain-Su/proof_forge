import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline

/-!
# Solana LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Solana-owned Plan surface and Semantic→Plan body.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.solana

def discriminatorDomain : String := "proof-forge-solana-v1:"
def layoutDomain : String := "proof-forge-solana-layout-v1:"
def discriminatorBytes : Nat := 8
def stateHeaderBytes : Nat := 8
/-- Policy program_error codes for the plan-only sBPF surface. Disjoint ranges:
    `0x1001` arithmetic overflow (checked add/sub/mul/div/mod and `shl` result
    ≥ 2^64), `0x1002` bare assert failure, `0x1003` static loop-bound exceeded
    (reference `boundExceeded` at the latch back edge), `0x1004` invalid shift
    count (reference `invalidShift` when the UInt32 count is ≥ 64 for `shl`/
    `shr`), and `declaredErrorBase + i` for declared program errors. -/
def arithmeticOverflowError : Nat := 0x1001
def assertionFailedError : Nat := 0x1002
/-- Static `for ... bounded N` exceeded: the (N+1)-th body has executed and the
    back edge is taken (reference `boundExceeded`). Distinct from arithmetic
    overflow and bare assert. -/
def loopBoundExceededError : Nat := 0x1003
/-- Shift count ≥ 64 (reference `invalidShift`). Distinct from arithmetic
    overflow; `shl` may still raise `arithmeticOverflowError` when the shifted
    result does not fit in UInt64. -/
def invalidShiftError : Nat := 0x1004

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
  /-- Plain UInt64 bitwise AND (no failure mode). -/
  | bitAnd (lhs rhs : Expr)
  /-- Plain UInt64 bitwise OR (no failure mode). -/
  | bitOr (lhs rhs : Expr)
  /-- Plain UInt64 bitwise XOR (no failure mode). -/
  | bitXor (lhs rhs : Expr)
  /-- UInt64 `<<` with UInt32 count: count ≥ 64 → invalidShift; result ≥ 2^64
      → arithmeticOverflow. -/
  | shl (lhs rhs : Expr)
  /-- UInt64 `>>` with UInt32 count: count ≥ 64 → invalidShift. -/
  | shr (lhs rhs : Expr)
  | bitNot (operand : Expr)
  | boolNot (operand : Expr)
  /-- Strict Bool `&&` (both operands always evaluated; no failure mode). -/
  | boolAnd (lhs rhs : Expr)
  /-- Strict Bool `||` (both operands always evaluated; no failure mode). -/
  | boolOr (lhs rhs : Expr)
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
  invalidShiftError : Nat
  programName : String
  stateAccount : StateAccount
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  fns : Array FnBinding
  initializer : Handler
  entries : Array Handler
  deriving BEq, Inhabited, Repr
private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .solana message

private def maxIdentifierBytes : Nat := 240
-- `.sbpf-plan` is the longest emitted suffix (10 bytes) under the CLI's
-- 240-byte relative-path ceiling.
def maxArtifactStemBytes : Nat := 230
def maxStateFields : Nat := 1024
def maxEntries : Nat := 255
def maxParams : Nat := 64
def maxBodyStatements : Nat := 4096
def maxExprDepth : Nat := 256
def maxPlanNodes : Nat := 100000

/-- Thin adapter: binds Solana's `maxIdentifierBytes` (240) to the shared grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

def validDiscriminator (value : String) : Bool :=
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

def signature (name : String) (params : Array Param) : String :=
  s!"{name}({String.intercalate "," (params.toList.map fun _ => "u64")})"

def instructionDiscriminator (name : String) (params : Array Param) : String :=
  ((Crypto.sha256Hex (discriminatorDomain ++ signature name params).toUTF8).take
    (2 * discriminatorBytes)).copy

def accessFor (account : StateAccount) (mode : HandlerMode) : AccountAccess := {
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

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering

The Solana pilot lowers public-UInt64 state, checked arith/bitwise/shift,
Bool compare/logical, bare assert, emit/revert, pureFn localCall, if/match
regions, and bounded for. External calls (`Op.ExternalCall`) and workflow
schedules (`Op.Schedule`) are declined this wave: CPI needs a 32-byte
program id, which the current UInt64 envelope cannot express. The product
path rejects those S2 requirements at `resolveEngineeringRequirementsV1`
before any Solana lowering; hand-built/inspection Semantic programs that
still carry the ops fail closed here with an explicit planInvariant. -/

/-- Solana pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool/UInt32 optional; state/params remain UInt64-only. -/
private abbrev SolanaTypeClosureV1 := PilotTypeClosureV1

private def solanaPlanErr (message : String) : CompileError :=
  .planInvariant .solana message

/-- Solana pilot accepts the anonymous UInt64/Unit/Bool/UInt32 closure currently
    emitted by the NormalizeV1 public-UInt64 envelope. Valid but richer
    SemanticProgramV1 programs fail at the target Plan seam rather than being
    silently erased. -/
private def validateSolanaTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult SolanaTypeClosureV1 :=
  validatePilotTypeClosure solanaPlanErr solanaTypeClosureWording types

private def makeStateAccountV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult StateAccount := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .solana "state count is outside the profile limits"
  let mut fields : Array StateField := #[]
  for state in states do
    unless state.id.toNat == fields.size do
      throw <| .planInvariant .solana "semantic state ids must match declaration order"
    requirePublicUInt64State solanaPlanErr uint64TypeId state (allowNonPublic := true)
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
  /-- True for anonymous UInt32 shift-count values (never simultaneously Bool). -/
  isUInt32 : Bool := false
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
    requirePublicUInt64Param solanaPlanErr uint64TypeId owner param
      (allowNonPublic := true)
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

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt64LiteralLe solanaPlanErr "Solana" bytes

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool :=
  decodeBoolLiteralBit solanaPlanErr "Solana" bytes

/-- Decode a 4-byte little-endian UInt32 shift-count literal into a UInt64
    carrier (plan temps remain 64-bit words; the type flag carries the width).
    Hand-rolled LE without trailing-byte finish check — intentionally not the
    shared `decodeUInt32LiteralLe` (EVM/NEAR path). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: UInt32 literal must contain exactly 4 bytes"
  let b0 := bytes[0]!.toNat
  let b1 := bytes[1]!.toNat
  let b2 := bytes[2]!.toNat
  let b3 := bytes[3]!.toNat
  pure (UInt64.ofNat (b0 + b1 * 256 + b2 * 65536 + b3 * 16777216))

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

private def makeBitAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .bitAnd lhsId rhsId lhs rhs false

private def makeBitOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .bitOr lhsId rhsId lhs rhs false

private def makeBitXorValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .bitXor lhsId rhsId lhs rhs false

private def makeShlValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .shl lhsId rhsId lhs rhs false

private def makeShrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .shr lhsId rhsId lhs rhs false

private def makeBoolAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .boolAnd lhsId rhsId lhs rhs true

private def makeBoolOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .boolOr lhsId rhsId lhs rhs true

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
          -- N1: pureFn params may be private/commitment; type stays UInt64.
          unless param.typeId == types.uint64TypeId do
            throw <| .planInvariant .solana
              s!"fn '{name}' parameters must be UInt64"
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
            isUInt32 := false
          }
        else if types.boolTypeId == some typeId then
          let bit ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal (if bit then 1 else 0)
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := true
            isUInt32 := false
          }
        else if types.uint32TypeId == some typeId then
          let value ← decodeUInt32LiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := false
            isUInt32 := true
          }
        else
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: literal is not UInt64, UInt32, or Bool"
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
        -- Strict Bool logical ops: both operands Bool, result Bool.
        if op == .and || op == .or then
          unless lhs.isBool && rhs.isBool do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: logical operands must be Bool"
          let boolTypeId ← match types.boolTypeId with
            | some value => pure value
            | none => throw (.planInvariant .solana
                "unsupported Solana semantic shape: Bool type is missing for logical op")
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: logical result must be Bool"
          let value ←
            if op == .and then makeBoolAndValueV1 lhsId rhsId lhs rhs
            else makeBoolOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        -- Shifts: UInt64 operand, UInt32 count (literal or computed), UInt64 result.
        else if op == .shl || op == .shr then
          unless !lhs.isBool && !lhs.isUInt32 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: shift operand must be UInt64"
          unless rhs.isUInt32 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: shift count must be UInt32"
          unless result.typeId == types.uint64TypeId do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: shift result must be UInt64"
          let value ←
            if op == .shl then makeShlValueV1 lhsId rhsId lhs rhs
            else makeShrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        -- UInt32 arithmetic/bitwise: admitted only as shift-count composition
        -- (e.g. `x >> (32 + 32)`). Same plan/IR opcodes as UInt64; checked-op
        -- overflow guards are UInt64-wide (a conservative superset for the small
        -- counts Normalize produces). A u32 arithmetic overflow yields a value
        -- ≥ 2^32 which, in this envelope, can only flow into a shift count,
        -- where the shift's own invalidShift (0x1004) check errors it — both
        -- paths revert; u32 values never escape the count position.
        else if (op == .add || op == .sub || op == .mul || op == .div ||
            op == .mod || op == .bitAnd || op == .bitOr || op == .bitXor) &&
            lhs.isUInt32 && rhs.isUInt32 then
          let u32TypeId ← match types.uint32TypeId with
            | some tid => pure tid
            | none => throw (.planInvariant .solana
                "unsupported Solana semantic shape: UInt32 type is missing for shift-count arithmetic")
          unless result.typeId == u32TypeId do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: UInt32 binary result type mismatch"
          let raw ←
            if op == .add then makeCheckedAddValueV1 lhsId rhsId lhs rhs
            else if op == .sub then makeCheckedSubValueV1 lhsId rhsId lhs rhs
            else if op == .mul then makeCheckedMulValueV1 lhsId rhsId lhs rhs
            else if op == .div then makeCheckedDivValueV1 lhsId rhsId lhs rhs
            else if op == .mod then makeCheckedModValueV1 lhsId rhsId lhs rhs
            else if op == .bitAnd then makeBitAndValueV1 lhsId rhsId lhs rhs
            else if op == .bitOr then makeBitOrValueV1 lhsId rhsId lhs rhs
            else makeBitXorValueV1 lhsId rhsId lhs rhs
          let value := { raw with isBool := false, isUInt32 := true }
          values := ← appendResultValueV1 u32TypeId values result value
        -- UInt64 arithmetic / bitwise / comparison operands.
        else
          unless !lhs.isBool && !rhs.isBool && !lhs.isUInt32 && !rhs.isUInt32 do
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
          else if op == .bitAnd then
            let value ← makeBitAndValueV1 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 types.uint64TypeId values result value
          else if op == .bitOr then
            let value ← makeBitOrValueV1 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 types.uint64TypeId values result value
          else if op == .bitXor then
            let value ← makeBitXorValueV1 lhsId rhsId lhs rhs
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
                  "unsupported Solana semantic shape: only checked UInt64/UInt32 arith/bitwise, UInt64 shift, Bool logical, and comparisons are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values blockEntry segmentStart armReadables operandId
        match op with
        | .bitNot =>
            unless !operand.isBool && !operand.isUInt32 do
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
          unless !arg.isBool && !arg.isUInt32 do
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
        unless !stored.isBool && !stored.isUInt32 do
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
          unless !root.isBool && !root.isUInt32 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        segmentStart := values.size
    -- External call / workflow schedule: Solana declines both this wave.
    -- CPI needs a 32-byte program id; the UInt64 pilot envelope has no
    -- address-bearing type, so there is no placeholder, adapter, or
    -- fabricated program id — fail closed with an explicit planInvariant.
    | .externalCall _ _ _, _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: external calls are outside the Solana pilot envelope (CPI requires a 32-byte program id the current UInt64 envelope cannot express)"
    | .schedule _ _ _, _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: workflow schedules are outside the Solana pilot envelope (CPI requires a 32-byte program id the current UInt64 envelope cannot express)"
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
  unless !root.isBool && !root.isUInt32 do
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
    invalidShiftError
    programName
    stateAccount
    events
    errors
    fns
    initializer := resolvedInitializer
    entries
  }
  pure plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) : CompileResult Plan := do
  -- Semantic structure was validated once at the capability mint
  -- (resolveEngineeringRequirementsV1 → validateSemanticProgramV1); the
  -- carrier is private-ctor so re-validation here is redundant. Transport
  -- decode still yields SemanticProgramDataV1 for the Plan body.
  let data ← match decodeSemanticProgramDataV1 source.canonicalBytes with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Solana received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Internal Solana family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

end ProofForgeV2.Targets.Solana
