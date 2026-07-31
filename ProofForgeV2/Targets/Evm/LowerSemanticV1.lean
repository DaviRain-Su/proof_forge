import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Evm.Keccak

/-!
# Evm LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the EVM-owned Plan surface and the retained-`SemanticProgramV1` Plan body.
Plan canonicity lives in `ValidatePlanV1`; Yul/ABI emission in `EmitIRV1`.
-/

namespace ProofForgeV2.Targets.Evm

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

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
  /-- Named induction temporary for bounded `for` loops. Renders as `t{tempIndex}`
  and is mutated by the loop update step. -/
  | temp (tempIndex : Nat)
  | storageLoad (slot : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  /-- Checked UInt64 multiply: Yul `mul` with overflow guard. -/
  | checkedMul (lhs rhs : Expr)
  /-- Checked UInt64 divide: reverts on zero divisor. -/
  | checkedDiv (lhs rhs : Expr)
  /-- Checked UInt64 modulo: reverts on zero divisor. -/
  | checkedMod (lhs rhs : Expr)
  /-- Unchecked UInt64 add. Only admitted for the bounded-for induction step
  `i + 1`, which cannot overflow: the body runs only while `i < end ≤ UInt64.max`. -/
  | add (lhs rhs : Expr)
  /-- Bitwise not on a UInt64 operand (`Yul not`). -/
  | bitNot (operand : Expr)
  /-- Logical not on a Bool operand (`Yul iszero`). -/
  | boolNot (operand : Expr)
  /-- Bitwise and on UInt64 operands (`Yul and`); no failure mode. -/
  | bitAnd (lhs rhs : Expr)
  /-- Bitwise or on UInt64 operands (`Yul or`); no failure mode. -/
  | bitOr (lhs rhs : Expr)
  /-- Bitwise xor on UInt64 operands (`Yul xor`); no failure mode. -/
  | bitXor (lhs rhs : Expr)
  /-- Left shift: UInt64 value, UInt32 count. Yul reverts on count ≥ 64
  (`invalidShift`) or result ≥ 2^64 (`arithmeticOverflow`). -/
  | shl (lhs rhs : Expr)
  /-- Right shift: UInt64 value, UInt32 count. Yul reverts on count ≥ 64. -/
  | shr (lhs rhs : Expr)
  /-- Strict Bool and (both sides always evaluate; `Yul and` on 0/1 words). -/
  | logicalAnd (lhs rhs : Expr)
  /-- Strict Bool or (both sides always evaluate; `Yul or` on 0/1 words). -/
  | logicalOr (lhs rhs : Expr)
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
  /-- Bounded for recovered from a loopBounds header: induction temp, completed-
  iteration counter temp, static `maxIterations` (enforced at the back edge),
  init expression (incoming jump args), unsigned `i < end` condition, post-body
  update (always `i + 1` in the Normalize pilot), and body statements.
  Runtime: the (N+1)-th body executes then reverts at the post/back-edge check
  (`eq(counter, N) → revert`), matching ReferenceV1 boundExceeded. -/
  | forLoop (varTemp counterTemp : Nat) (maxIterations : UInt32)
      (initial : Expr) (cond : Expr) (update : Expr) (body : Array Statement)
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
private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .evm message

-- Profile-owned resource limits. They bound selector hashing and the current
-- array-based uniqueness checks before target lowering performs expensive work.
private def maxIdentifierBytes : Nat := 240
def maxArtifactStemBytes : Nat := 231
def maxStorageBindings : Nat := 1024
def maxEntries : Nat := 1024
def maxParams : Nat := 256
def maxBodyStatements : Nat := 4096
def maxExprDepth : Nat := 256
def maxPlanNodes : Nat := 100000

/-- Thin adapter: binds EVM's `maxIdentifierBytes` (240) to the shared grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

def validSelector (selector : String) : Bool :=
  selector.length == 8 && selector.toList.all (fun character =>
    "0123456789abcdef".contains character)

/-- EVM pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool/UInt32 optional; state/params remain UInt64-only. -/
private abbrev EvmTypeClosureV1 := PilotTypeClosureV1

private def evmPlanErr (message : String) : CompileError :=
  .planInvariant .evm message

/-- EVM pilot accepts the anonymous UInt64/Unit/Bool/UInt32 closure currently
    emitted by the NormalizeV1 public-UInt64 envelope. Valid but richer
    SemanticProgramV1 programs fail at the target Plan seam rather than being
    silently erased. Bool is optional (at most one): admitted as body intermediate
    values and as entry/view results. UInt32 is optional (at most one): admitted
    only as shift-count literals/intermediates. State/params remain UInt64-only. -/
private def validateEvmTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult EvmTypeClosureV1 :=
  validatePilotTypeClosure evmPlanErr evmTypeClosureWording types

private def makeStorageLayoutV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult (Array StorageBinding) := do
  if states.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
  let mut layout : Array StorageBinding := #[]
  for state in states do
    unless state.id.toNat == layout.size do
      throw <| .planInvariant .evm "semantic state ids must match declaration order"
    requirePublicUInt64State evmPlanErr uint64TypeId state
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
  /-- Defensive kind bit: true for comparison/logical results and Bool
  literals only. State loads, params, UInt32 shift counts, arithmetic,
  bitwise, and shifts are always false. -/
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
    requirePublicUInt64Param evmPlanErr uint64TypeId owner param
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

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt64LiteralLe evmPlanErr "EVM" bytes

/-- Shift-count literals are 4-byte LE UInt32 on the wire; widen to UInt64 for
    the Plan expression surface (values are always < 2^32). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt32LiteralLe evmPlanErr "EVM" bytes

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
    comparison results; arithmetic/bitwise are UInt64 or (shift-count only)
    UInt32; shifts are UInt64. Operands must be non-Bool. UInt32 arithmetic
    reuses the UInt64 Yul forms: a true u32 wrap (≥ 2^32) can only flow into a
    shift count in this envelope, where `lt(k, 64)` reverts as invalidShift
    (not arithmeticOverflow) — both paths fail closed. -/
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

/-- Strict Bool binary: both operands must already be Bool-tagged; result is
    Bool. Same expanded-tree cost accounting as UInt64 binaries. -/
private def makeLogicalTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.isBool && rhs.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: logical operands must be Bool"
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
    isBool := true
  }

/-- Admit a wire result TypeId for UInt-width arithmetic/bitwise: anonymous
    UInt64 (ordinary path) or the optional anonymous UInt32 (shift-count
    intermediates only). Returns the TypeId for `appendResultValueV1`. -/
private def admitUIntWidthResultTypeV1
    (types : EvmTypeClosureV1) (resultTypeId : TypeIdV1) : CompileResult TypeIdV1 := do
  if resultTypeId == types.uint64TypeId then
    pure resultTypeId
  else if types.uint32TypeId == some resultTypeId then
    pure resultTypeId
  else
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: arithmetic/bitwise result must be UInt64 or UInt32"

/-- Compute expanded tree cost before constructing an EVM Expr node. A shared
    SSA operand counts once per use, so `add(v,v)` doubles the expanded cost.
    Also admits UInt32-typed shift-count arithmetic (same Plan/Yul forms). -/
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

/-- Multiply has the same bounded SSA-tree cost as addition. -/
private def makeCheckedMulValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedMul lhsId rhsId lhs rhs false

/-- Division has the same bounded SSA-tree cost as addition. -/
private def makeCheckedDivValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedDiv lhsId rhsId lhs rhs false

/-- Modulo has the same bounded SSA-tree cost as addition. -/
private def makeCheckedModValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .checkedMod lhsId rhsId lhs rhs false

/-- Bitwise and: UInt64/UInt32 operands → same-width result; no failure mode. -/
private def makeBitAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .bitAnd lhsId rhsId lhs rhs false

/-- Bitwise or: UInt64/UInt32 operands → same-width result; no failure mode. -/
private def makeBitOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .bitOr lhsId rhsId lhs rhs false

/-- Bitwise xor: UInt64/UInt32 operands → same-width result; no failure mode. -/
private def makeBitXorValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .bitXor lhsId rhsId lhs rhs false

/-- Left shift: UInt64 value + UInt32 count → UInt64 (guards in Yul). -/
private def makeShlValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .shl lhsId rhsId lhs rhs false

/-- Right shift: UInt64 value + UInt32 count → UInt64 (count guard in Yul). -/
private def makeShrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .shr lhsId rhsId lhs rhs false

/-- Strict Bool and: Bool operands → Bool result. -/
private def makeLogicalAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeLogicalTreeValueV1 .logicalAnd lhsId rhsId lhs rhs

/-- Strict Bool or: Bool operands → Bool result. -/
private def makeLogicalOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeLogicalTreeValueV1 .logicalOr lhsId rhsId lhs rhs

/-- Shared bounded SSA-tree cost for unary Expr constructors. -/
private def makeUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1)
    (expectBoolOperand isBoolResult : Bool) : CompileResult LoweredValueV1 := do
  unless operand.isBool == expectBoolOperand do
    throw <| .planInvariant .evm
      (if expectBoolOperand then
        "unsupported EVM semantic shape: unary not operand must be Bool"
       else
        "unsupported EVM semantic shape: unary bitNot operand must be UInt64")
  let depth := 1 + operand.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .evm s!"EVM plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk operand.expr
    depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
    isBool := isBoolResult
  }

/-- Bitwise not: UInt64 operand → UInt64 result. -/
private def makeBitNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 .bitNot operandId operand false false

/-- Logical not: Bool operand → Bool result. -/
private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 .boolNot operandId operand true true

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

/-- EVM Plan surface stores Bool as UInt64 0/1 words. -/
private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  let bit ← decodeBoolLiteralBit evmPlanErr "EVM" bytes
  pure (if bit then 1 else 0)

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

/-- Like `consumeCurrentSegmentV1`, but dependencies listed in `armReadables`
    (induction temps, dominating pure values, match scrutinees) are free and
    need not live in the current segment. Used for loop-header conditions and
    loop-body sinks that close over the induction variable. -/
private def consumeCurrentSegmentWithArmsV1
    (values : Array LoweredValueV1)
    (paramCount segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueWithArmsV1 values paramCount segmentStart armReadables root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  if root.toNat >= paramCount && !armReadables.contains root then
    stack := stack.push root.toNat
  else if root.toNat >= segmentStart then
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
        if dependencyIndex >= paramCount && !armReadables.contains dependency then
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
    blocks stay referenceable only via params, match-arm scrutinees, or
    loop-dominating pure values (armReadables). Loop-header block params are
    pre-allocated in the value table and already bound to induction temps. -/
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
  unless block.id.toNat < 1000000 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: block id is out of range"
  -- Block params are admitted only when already materialised in values0
  -- (loop-header induction temps pre-allocated by lowerCallableV1).
  for p in block.params do
    unless p.valueId.toNat < values0.size do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: block parameter ValueId is not pre-allocated"
    unless p.typeId == uint64TypeId do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: block parameter must be anonymous UInt64"
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
        else if types.uint32TypeId == some typeId then
          -- Shift-count intermediates only; stored as non-Bool UInt64 words.
          let value ← decodeUInt32LiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
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
              "unsupported EVM semantic shape: literal is not UInt64, UInt32, or Bool"
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
          -- UInt64 ordinary path, or UInt32 shift-count arithmetic (e.g. 32+32).
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeCheckedAddValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .sub then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeCheckedSubValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .mul then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeCheckedMulValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .div then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeCheckedDivValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .mod then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeCheckedModValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .bitAnd then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeBitAndValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .bitOr then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeBitOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .bitXor then
          let widthTid ← admitUIntWidthResultTypeV1 types result.typeId
          let value ← makeBitXorValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 widthTid values result value
        else if op == .shl then
          -- Shift result is always UInt64 (value width); count may be UInt32.
          let value ← makeShlValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 uint64TypeId values result value
        else if op == .shr then
          let value ← makeShrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 uint64TypeId values result value
        else if op == .and then
          let boolTid ← match types.boolTypeId with
            | some tid => pure tid
            | none => throw (.planInvariant .evm
                "unsupported EVM semantic shape: logical and requires anonymous Bool type")
          unless result.typeId == boolTid do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: logical and result must be Bool"
          let value ← makeLogicalAndValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTid values result value
        else if op == .or then
          let boolTid ← match types.boolTypeId with
            | some tid => pure tid
            | none => throw (.planInvariant .evm
                "unsupported EVM semantic shape: logical or requires anonymous Bool type")
          unless result.typeId == boolTid do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: logical or result must be Bool"
          let value ← makeLogicalOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTid values result value
        else
          match comparisonOpOfBinaryV1 op with
          | none =>
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: only checked UInt64 arith/bitwise/shift, Bool logical, and comparisons are supported"
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
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values paramCount segmentStart armReadables operandId
        match op with
        | .bitNot =>
            let value ← makeBitNotValueV1 operandId operand
            values := ← appendResultValueV1 uint64TypeId values result value
        | .not =>
            let boolTid ← match types.boolTypeId with
              | some tid => pure tid
              | none => throw (.planInvariant .evm
                  "unsupported EVM semantic shape: unary not requires anonymous Bool type")
            unless result.typeId == boolTid do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: unary not result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTid values result value
        | .neg =>
            -- Checked negation is desugared to `0 - x` by Normalize; direct
            -- Op.Unary.neg is outside the EVM pilot envelope.
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: unary neg is not admitted (Normalize desugars to sub)"
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
        let value ← consumeCurrentSegmentWithArmsV1
          values paramCount segmentStart armReadables valueId
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
        let cond ← consumeCurrentSegmentWithArmsV1
          values paramCount segmentStart armReadables condId
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
    -- Wave I: EVM declines external calls / workflow schedules. Product
    -- capability resolution rejects `effect.synchronous-call` and
    -- `effect.asynchronous-workflow` with PF-REQ-UNSUPPORTED before this
    -- lowerer runs; the arms below are defensive for hand-built / inspection
    -- SemanticProgramV1 carriers. No placeholder CALL/CREATE Yul: EVM
    -- external calls require an address-bearing type that does not exist in
    -- the current public-UInt64 envelope.
    | .externalCall _effectId _callee _args, none =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: external calls are outside the EVM pilot envelope (no address-bearing type)"
    | .schedule _effectId _callee _args, none =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: workflow schedules are outside the EVM pilot envelope (no address-bearing type)"
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

private def findLoopBoundV1 (loopBounds : Array LoopBoundV1) (headerId : Nat) :
    Option LoopBoundV1 :=
  loopBounds.find? (fun lb => lb.header.toNat == headerId)

/-- Method-scoped counter temp for a loopBounds header: one unique Nat per
    loop, allocated after every induction (block-param) ValueId so Yul names
    `t{counterTemp}` never collide with induction temps. -/
private def loopCounterTempV1 (blocks : Array BlockV1) (loopBounds : Array LoopBoundV1)
    (headerId : Nat) : CompileResult Nat := do
  let mut maxBp : Nat := 0
  for b in blocks do
    for p in b.params do
      if p.valueId.toNat > maxBp then
        maxBp := p.valueId.toNat
  let mut idx : Nat := 0
  let mut found : Option Nat := none
  for lb in loopBounds do
    if lb.header.toNat == headerId then
      found := some idx
    idx := idx + 1
  match found with
  | some i => pure (maxBp + 1 + i)
  | none =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: loop counter temp missing loopBounds entry"

/-- Collect pure ValueIds in `[paramCount, values.size)` so loop-header and
    body blocks may read dominating pure arithmetic (e.g. `limit := n + 4`). -/
private def dominatingPureReadablesV1
    (paramCount : Nat) (values : Array LoweredValueV1)
    (base : Array ValueIdV1) : Array ValueIdV1 := Id.run do
  let mut out := base
  for i in [paramCount:values.size] do
    let id : ValueIdV1 := UInt32.ofNat i
    unless out.contains id do
      out := out.push id
  pure out

/-- Strip the checked-add overflow guard from a latch update. Normalize always
    emits `i + 1` after a body that only ran while `i < end ≤ UInt64.max`, so
    the induction step cannot overflow. -/
private def inductionUpdateExprV1 (expr : Expr) : Expr :=
  match expr with
  | .checkedAdd lhs rhs => .add lhs rhs
  | other => other


/-- Continuation of a region walk: terminal, forward join, or loop latch. -/
private inductive RegionContV1 where
  | done
  | join (blockId : Nat)
  | latch (update : Expr)
  deriving Inhabited

/-- Single recursive entry for region and for-loop materialisation (avoids a
    mutual block). -/
private inductive EmitJobV1 where
  | region
      (armReadables : Array ValueIdV1)
      (activeLoopHeader : Option Nat)
      (start : Nat)
      (values : Array LoweredValueV1)
  | forFromJump
      (armReadables : Array ValueIdV1)
      (enclosingLoopHeader : Option Nat)
      (lb : LoopBoundV1)
      (initArgs : Array ValueIdV1)
      (values : Array LoweredValueV1)
      (segmentStart : Nat)

/-- Structured emission of multi-block CFGs including forward diamonds
    (branch/switch) and bounded for-loops recovered from `loopBounds`. Diamonds
    follow each arm to its exit jump or return; convergent joins continue the
    region. A jump into a loopBounds header materialises a `forLoop` statement
    (nested headers recurse). The fuel bounds recursion to the block count.
    Returns (statements, values, cont, hasAssert, hasControlRegion).
    `activeLoopHeader = some h` means a jump back to `h` is this loop's latch. -/
private partial def emitJobV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (paramCount : Nat)
    (expectedResultKind : Option ResultKind)
    (fuel : Nat)
    (job : EmitJobV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × RegionContV1 × Bool × Bool) := do
  if fuel == 0 then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: CFG region exceeds block bound"
  match job with
  | .forFromJump armReadables enclosingLoopHeader lb initArgs values0 segmentStart0 => do
      let headerId := lb.header.toNat
      let header ← match blocks[headerId]? with
        | some b => pure b
        | none => throw (.planInvariant .evm
            "unsupported EVM semantic shape: loopBounds header is missing")
      unless header.id.toNat == headerId do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop header block id is not dense"
      let headerParam ← match header.params[0]? with
        | some p => pure p
        | none => throw (.planInvariant .evm
            "unsupported EVM semantic shape: loop header must carry exactly one block param")
      unless header.params.size == 1 do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop header must carry exactly one block param"
      let initArg ← match initArgs[0]? with
        | some a => pure a
        | none => throw (.planInvariant .evm
            "unsupported EVM semantic shape: loop entry must pass exactly one induction arg")
      unless initArgs.size == 1 do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop entry must pass exactly one induction arg"
      let initRoot ← currentValueWithArmsV1
        values0 paramCount segmentStart0 armReadables initArg
      unless !initRoot.isBool do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop induction init must be UInt64"
      let initial := initRoot.expr
      let varTemp := headerParam.valueId.toNat
      unless varTemp < values0.size do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: induction ValueId is not pre-allocated"
      let mut values := values0.set! varTemp {
        expr := .temp varTemp
        depth := 1
        expandedNodes := 1
        dependencies := #[]
        isBool := false
      }
      let mut loopReadables :=
        dominatingPureReadablesV1 paramCount values armReadables
      let indId : ValueIdV1 := UInt32.ofNat varTemp
      unless loopReadables.contains indId do
        loopReadables := loopReadables.push indId
      let headerLowered ← lowerBlockInstructionsV1
        owner mode types layout fnIndexByCallableId fns paramCount loopReadables header values
      values := headerLowered.values
      let headerSeg := headerLowered.segmentStart
      unless headerLowered.statements.isEmpty do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop header must not emit side-effect statements"
      match header.terminator with
      | .branch condId thenT elseT =>
          let condVal ← currentValueWithArmsV1
            values paramCount headerSeg loopReadables condId
          unless condVal.isBool do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: loop condition must be Bool"
          let cond ← consumeCurrentSegmentWithArmsV1
            values paramCount headerSeg loopReadables condId
          let (bodyStmts, values1, bodyCont, hA1, _) ←
            emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
              paramCount expectedResultKind (fuel - 1)
              (.region loopReadables (some headerId) thenT.blockId.toNat values)
          let update ← match bodyCont with
            | .latch u => pure u
            | _ =>
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: loop body must latch back to its header"
          values := values1
          let exitId := elseT.blockId.toNat
          let counterTemp ← loopCounterTempV1 blocks loopBounds headerId
          unless counterTemp != varTemp do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: loop counter temp collides with induction temp"
          let forStmt : Statement :=
            .forLoop varTemp counterTemp lb.maxIterations initial cond update bodyStmts
          let (exitStmts, values2, exitCont, hA2, _) ←
            emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
              paramCount expectedResultKind (fuel - 1)
              (.region loopReadables enclosingLoopHeader exitId values)
          pure (#[forStmt] ++ exitStmts, values2, exitCont, hA1 || hA2, true)
      | _ =>
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: loop header terminator must be a branch"
  | .region armReadables activeLoopHeader start values0 => do
      if activeLoopHeader != some start then
        if (findLoopBoundV1 loopBounds start).isSome then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: loop header must be entered via jump"
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
              let value ← consumeCurrentSegmentWithArmsV1
                values paramCount segmentStart armReadables valueId
              pure (instrs.push (.returnValue value), values, .done, hA, false)
      | .return_ none =>
          unless segmentStart == values.size do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: block has unconsumed values"
          pure (instrs.push .returnNone, values, .done, hA, false)
      | .jump target =>
          let targetId := target.blockId.toNat
          if activeLoopHeader == some targetId then
            unless target.args.size == 1 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: loop latch must pass exactly one induction arg"
            let updateArg ← match target.args[0]? with
              | some a => pure a
              | none => throw (.planInvariant .evm
                  "unsupported EVM semantic shape: loop latch must pass exactly one induction arg")
            let updateRoot ← currentValueWithArmsV1
              values paramCount segmentStart armReadables updateArg
            unless !updateRoot.isBool do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: loop induction update must be UInt64"
            let update ← consumeCurrentSegmentWithArmsV1
              values paramCount segmentStart armReadables updateArg
            pure (instrs, values, .latch (inductionUpdateExprV1 update), hA, false)
          else
            match findLoopBoundV1 loopBounds targetId with
            | some lb =>
                let (loopStmts, values1, exitCont, hA1, _) ←
                  emitJobV1 owner mode types layout fnIndexByCallableId fns
                    blocks loopBounds paramCount expectedResultKind (fuel - 1)
                    (.forFromJump armReadables activeLoopHeader lb target.args values segmentStart)
                pure (instrs ++ loopStmts, values1, exitCont, hA || hA1, true)
            | none =>
                unless target.args.isEmpty do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: non-header jump must carry empty args"
                unless segmentStart == values.size do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: block has unconsumed values"
                pure (instrs, values, .join targetId, hA, false)
      | .branch condId thenT elseT =>
          let condVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables condId
          unless condVal.isBool do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: branch condition must be Bool"
          let cond ← consumeCurrentSegmentWithArmsV1
            values paramCount segmentStart armReadables condId
          let (thenBody, values1, thenCont, hA1, _) ←
            emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
              paramCount expectedResultKind (fuel - 1)
              (.region armReadables activeLoopHeader thenT.blockId.toNat values)
          match thenCont with
          | .latch update =>
              pure (instrs ++ #[.ifThenElse cond thenBody #[]], values1,
                .latch update, hA || hA1, true)
          | .join j =>
              if elseT.blockId.toNat == j then
                let (rest, values2, next, hA2, _) ←
                  emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                    paramCount expectedResultKind (fuel - 1)
                    (.region armReadables activeLoopHeader j values1)
                pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest,
                  values2, next, hA || hA1 || hA2, true)
              else
                let (elseBody, values2, elseCont, hA2, _) ←
                  emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                    paramCount expectedResultKind (fuel - 1)
                    (.region armReadables activeLoopHeader elseT.blockId.toNat values1)
                match elseCont with
                | .join j2 =>
                    unless j == j2 do
                      throw <| .planInvariant .evm
                        "unsupported EVM semantic shape: branch arms converge on divergent joins"
                    let (rest, values3, next, hA3, _) ←
                      emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                        paramCount expectedResultKind (fuel - 1)
                        (.region armReadables activeLoopHeader j values2)
                    pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                      values3, next, hA || hA1 || hA2 || hA3, true)
                | .done =>
                    let (rest, values3, next, hA3, _) ←
                      emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                        paramCount expectedResultKind (fuel - 1)
                        (.region armReadables activeLoopHeader j values2)
                    pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                      values3, next, hA || hA1 || hA2 || hA3, true)
                | .latch _ =>
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: branch arms mix latch and join exits"
          | .done =>
              let (elseBody, values2, elseCont, hA2, _) ←
                emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                  paramCount expectedResultKind (fuel - 1)
                  (.region armReadables activeLoopHeader elseT.blockId.toNat values1)
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody],
                values2, elseCont, hA || hA1 || hA2, true)
      | .switch scrutId cases defaultTarget =>
          let scrutVal ← currentValueWithArmsV1 values paramCount segmentStart armReadables scrutId
          let scrut ← consumeCurrentSegmentWithArmsV1
            values paramCount segmentStart armReadables scrutId
          let some defaultT := defaultTarget |
            throw (.planInvariant .evm
              "unsupported EVM semantic shape: switch must carry a default target")
          let mut caseBodies : Array (UInt64 × Array Statement) := #[]
          let mut joinAcc : Option Nat := none
          let mut valuesA := values
          let mut hAAcc := hA
          for switchCase in cases do
            let caseValue ← decodeSwitchCaseValueV1 scrutVal.isBool switchCase.valueBytes
            let (body, values1, armCont, hA1, _) ←
              emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                paramCount expectedResultKind (fuel - 1)
                (.region (armReadables.push scrutId) activeLoopHeader
                  switchCase.target.blockId.toNat valuesA)
            caseBodies := caseBodies.push (caseValue, body)
            valuesA := values1
            hAAcc := hAAcc || hA1
            match armCont, joinAcc with
            | .done, _ => pure ()
            | .latch _, _ =>
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: switch arm cannot be a loop latch"
            | .join j, none => joinAcc := some j
            | .join j, some j0 =>
                unless j == j0 do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: switch arms converge on divergent joins"
          let (defaultBody, values2, defaultCont, hA2, _) ←
            emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
              paramCount expectedResultKind (fuel - 1)
              (.region (armReadables.push scrutId) activeLoopHeader
                defaultT.blockId.toNat valuesA)
          hAAcc := hAAcc || hA2
          match defaultCont, joinAcc with
          | .done, _ => pure ()
          | .latch _, _ =>
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: switch default cannot be a loop latch"
          | .join j, none => joinAcc := some j
          | .join j, some j0 =>
              unless j == j0 do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: switch arms converge on divergent joins"
          match joinAcc with
          | none =>
              pure (instrs ++ #[.switchOn scrut caseBodies defaultBody],
                values2, .done, hAAcc, true)
          | some j =>
              let (rest, values3, next, hA3, _) ←
                emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                  paramCount expectedResultKind (fuel - 1)
                  (.region armReadables activeLoopHeader j values2)
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
          pure (instrs.push (.revertError errorId.toNat argExprs), values, .done, hA, false)
      | .trap _ =>
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: trap terminators are outside the current pilot"

private def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : EvmTypeClosureV1)
    (layout : Array StorageBinding)
    (fnIndexByCallableId : Array (Option Nat))
    (fns : Array FnBinding)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (paramCount : Nat)
    (armReadables : Array ValueIdV1)
    (activeLoopHeader : Option Nat)
    (expectedResultKind : Option ResultKind)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × RegionContV1 × Bool × Bool) :=
  emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
    paramCount expectedResultKind fuel
    (.region armReadables activeLoopHeader start values0)

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
      callable.invariantSteps.isNone do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: callable entry/invariant shape is invalid"
  -- Block params are admitted only on loopBounds headers (exactly one UInt64
  -- induction param). Degenerate param'd blocks without a loopBounds entry
  -- stay fail-closed (out of pilot).
  for b in callable.blocks do
    if !b.params.isEmpty then
      unless b.params.size == 1 do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop header must have exactly one block param"
      unless (findLoopBoundV1 callable.loopBounds b.id.toNat).isSome do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: block parameters require a loopBounds header"
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: loopBounds header is out of range"
    unless header.params.size == 1 do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: loopBounds header must carry one block param"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: loopBounds backEdgeFrom is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: loop latch must jump to its header with one arg"
    | _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: loop back edge must be a jump"
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  let paramCount := params.size
  -- Pre-allocate block-param ValueIds so instruction results stay dense
  -- (callable params < all block params < instruction results).
  let mut values := initialValues
  for b in callable.blocks do
    for p in b.params do
      unless p.valueId.toNat == values.size do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: block parameter ValueIds are not canonical"
      unless p.typeId == types.uint64TypeId do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: block parameter must be anonymous UInt64"
      -- Placeholder; overwrite with `.temp` when the loop is materialised.
      values := values.push {
        expr := .literal 0
        depth := 1
        expandedNodes := 1
        dependencies := #[]
        isBool := false
      }
  let (body0, valuesAfter, cont0, hA0, hasRegion0) ←
    emitRegionV1 owner mode types layout fnIndexByCallableId fns callable.blocks
      callable.loopBounds paramCount #[] none expectedResultKind callable.blocks.size 0 values
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG, so this terminates within blocks.size folds.
  let mut body := body0
  let mut liveValues := valuesAfter
  let mut cont := cont0
  let mut hasAssert := hA0
  let mut hasRegion := hasRegion0
  for _ in [0:callable.blocks.size] do
    match cont with
    | .done => break
    | .latch _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: dangling loop latch outside a for body"
    | .join j =>
        let (rest, values1, cont1, hA1, hasRegion1) ←
          emitRegionV1 owner mode types layout fnIndexByCallableId fns callable.blocks
            callable.loopBounds paramCount #[] none expectedResultKind
            callable.blocks.size j liveValues
        body := body ++ rest
        liveValues := values1
        cont := cont1
        hasAssert := hasAssert || hA1
        hasRegion := hasRegion || hasRegion1
  match cont with
  | .done => pure ()
  | .join _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: callable does not end in return on all paths"
  | .latch _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: dangling loop latch outside a for body"
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
  return plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) : CompileResult Plan := do
  -- Semantic structure was validated once at the capability mint
  -- (resolveEngineeringRequirementsV1 → validateSemanticProgramV1); the
  -- carrier is private-ctor so re-validation here is redundant. Transport
  -- decode still yields SemanticProgramDataV1 for the Plan body.
  let data ← match decodeSemanticProgramDataV1 source.canonicalBytes with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "EVM received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Internal Evm family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .evm do
    throw <| .planInvariant .evm "engineering capability kind is not EVM"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

end ProofForgeV2.Targets.Evm
