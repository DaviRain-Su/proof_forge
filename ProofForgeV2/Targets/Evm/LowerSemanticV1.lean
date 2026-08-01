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

/-- Target-owned binding from a semantic state identity to an EVM storage slot.
    `byteWidth ∈ {1,2,4,8}` is the physical storage width (narrow values live
    in the low bytes of a 32-byte slot). Default 8 keeps historical UInt64/Int64
    Plan literals byte-identical at the structure level. -/
structure StorageBinding where
  sourceId : Nat
  name : String
  slot : Nat
  /-- Physical width in bytes: UInt8→1, UInt16→2, UInt32→4, UInt64/Int64→8. -/
  byteWidth : Nat := 8
  deriving BEq, Inhabited, Repr

/-- Target-owned ABI word binding. `sourceId` is retained only for traceability;
all lowering after plan construction uses `wordIndex`. Each param still occupies
one 32-byte ABI word; narrow values sit in the low bytes. -/
structure Param where
  sourceId : Nat
  name : String
  wordIndex : Nat
  /-- True when the ABI word is Int64 (selector/`int64`); default false keeps
      historical UInt64 Plan literals byte-identical. -/
  isInt : Bool := false
  /-- Physical ABI value width in bytes: UInt8→1 … UInt64/Int64→8. `isInt`
      implies `byteWidth = 8`. -/
  byteWidth : Nat := 8
  deriving BEq, Inhabited, Repr

/-- Comparison ops over integer operands. Result is a Bool word (0/1) in Yul;
    signed vs unsigned is selected by the enclosing Expr constructor
    (`compare` vs `signedCompare`). -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

/-- EVM scalar expression for the Phase-1 UInt fragment. Storage slots and
ABI word positions have already been selected by the plan builder.

Historical constructors (`checkedAdd`, `bitNot`, `shl`, …) are **UInt64-width**
and keep hand-built Plan goldens byte-identical. Narrow body widths
(`bitWidth ∈ {8,16,32}`) use the parallel `narrow*` constructors so Yul can
emit width-correct overflow/shift/mask guards without rewriting UInt64 paths. -/
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
  /-- Bitwise not on a UInt64 operand (`Yul not` + 64-bit mask). -/
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
  /-- Checked add at `bitWidth ∈ {8,16,32}` (body multi-width). -/
  | narrowCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitAnd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitOr (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitXor (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitNot (bitWidth : Nat) (operand : Expr)
  /-- Left shift of a narrow UInt value; count is UInt32; reverts when
  `count ≥ bitWidth` or the shifted result exceeds the width mask. -/
  | narrowShl (bitWidth : Nat) (lhs rhs : Expr)
  | narrowShr (bitWidth : Nat) (lhs rhs : Expr)
  /-- Checked Int64 add (Yul sign-extend + range gate). -/
  | signedCheckedAdd (lhs rhs : Expr)
  | signedCheckedSub (lhs rhs : Expr)
  | signedCheckedMul (lhs rhs : Expr)
  /-- Checked Int64 div: reverts on zero divisor and intMin / -1. -/
  | signedCheckedDiv (lhs rhs : Expr)
  | signedCheckedMod (lhs rhs : Expr)
  /-- Signed Int64 comparison (`slt`/`sgt` family). -/
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  /-- Checked Int64 negation: reverts on intMin. -/
  | checkedNeg (operand : Expr)
  /-- Arithmetic right shift of Int64; count is UInt32; reverts on count ≥ 64. -/
  | sar (lhs rhs : Expr)
  /-- Storage load of a narrow UInt value (`bitWidth ∈ {8,16,32}`); Yul masks
  after `sload`. UInt64/Int64 keep historical `storageLoad`. -/
  | narrowStorageLoad (bitWidth : Nat) (slot : Nat)
  /-- ABI param load of a narrow UInt value (`bitWidth ∈ {8,16,32}`); Yul masks
  after `calldataload`/`mload`. UInt64/Int64 keep historical `param`. -/
  | narrowParam (bitWidth : Nat) (wordIndex : Nat)
  deriving BEq, Inhabited, Repr

structure Store where
  slot : Nat
  value : Expr
  /-- Physical width in bytes for the stored value (mask before `sstore`).
  Default 8 keeps historical UInt64/Int64 stores byte-identical at structure. -/
  byteWidth : Nat := 8
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

/-- Declared ABI result kind for an entry/view. Results stay UInt64/Bool/Int64
(result multi-width is out of scope); state/params admit UInt{8,16,32,64} or
Int64. -/
inductive ResultKind where
  | uint64
  | bool
  | int64
  deriving BEq, Inhabited, Repr

/-- Solidity ABI type string for a plan Param (selector + `.abi.json`). -/
def abiParamTypeString (p : Param) : String :=
  if p.isInt then "int64"
  else match p.byteWidth with
  | 1 => "uint8"
  | 2 => "uint16"
  | 4 => "uint32"
  | _ => "uint64"

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
  /-- True when the pureFn result is Int64 (mutually exclusive with resultIsBool). -/
  resultIsInt : Bool := false
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
    Bool + UInt8/16/32 optional; Int64 optional. Top-level scalar state/params
    admit UInt{8,16,32,64} or Int64 (T8b ABI multi-width); named Struct/Enum
    state/params are flattened to UInt64/Int64 ABI/storage leaves (N3). -/
private abbrev EvmTypeClosureV1 := PilotTypeClosureV1

private def evmPlanErr (message : String) : CompileError :=
  .planInvariant .evm message

/-- EVM pilot admits anonymous UInt{8,16,32,64} + Int64 + Unit + Bool under
    `pilotUintWidthPolicyEvmBody` + default `pilotIntWidthPolicyI64`, plus
    **named Struct/Enum** (`pilotNamedAggregateStatePolicyAdmit`, N3). Body
    multi-width UInt values and Int64 values are allowed; **top-level scalar
    state and ABI parameters admit UInt{8,16,32,64} or Int64** via
    `requirePublicUintAbiOrInt64*` (T8b), and **named aggregates admit
    UInt64/Int64 leaves only** via `requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamed*`
    with `allowNonPublic := true` (N3). UInt128/256 and non-64 Int fail closed.
    N2c: Principal remains fail-closed (wire identity is variable-length
    u32-prefixed; not a 20-byte EVM address). -/
private def validateEvmTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult EvmTypeClosureV1 :=
  validatePilotTypeClosure evmPlanErr evmTypeClosureWording types
    pilotUintWidthPolicyEvmBody
    (intPolicy := pilotIntWidthPolicyI64)
    (fieldPolicy := pilotFieldPolicyNone)
    (principalPolicy := pilotPrincipalPolicyNone)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)

/-- Lowering-time storage + type table. Plan.storageLayout is `bindings`
    (flattened leaf slots; sourceId == slot == declaration order of leaves).
    `stateLeaves[stateId]` is the ordered leaf slot list for that logical state. -/
private structure EvmLowerLayoutV1 where
  bindings : Array StorageBinding
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  deriving Inhabited

/-- Resolve admitted scalar state/param TypeId to physical byte width (1/2/4/8).
    Named aggregates must NOT be passed here (their leaves are 64-bit words). -/
private def abiByteWidthOfTypeV1
    (types : EvmTypeClosureV1) (typeId : TypeIdV1) : CompileResult Nat := do
  match types.uintWidthOf typeId with
  | some w =>
      unless isEvmAbiUintWidth w do
        throw <| .planInvariant .evm
          s!"unsupported EVM semantic shape: ABI UInt{w} is not admitted"
      pure (byteWidthOfBitWidth w)
  | none =>
      unless types.int64TypeId == some typeId do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: ABI type must be UInt{8,16,32,64} or Int64"
      pure 8

private structure LoweredValueV1 where
  expr : Expr
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  /-- Defensive kind bit: true for comparison/logical results and Bool
  literals only. State loads, params, UInt arithmetic/bitwise/shift are false. -/
  isBool : Bool
  /-- True for Int64-typed values (mutually exclusive with isBool). -/
  isInt : Bool := false
  /-- Bit width of non-Bool values: 8/16/32/64. Bool uses 1. -/
  bitWidth : Nat := 64
  /-- N3: named-aggregate leaf words (UInt64/Int64) in preorder flatten order.
      `none` = scalar. When `some`, `expr` mirrors `leaves[0]!` (or literal 0). -/
  aggregateLeaves : Option (Array Expr) := none
  /-- Parallel Int64 flag per aggregate leaf (same length as `aggregateLeaves`). -/
  aggregateLeafIsInt : Option (Array Bool) := none
  deriving Inhabited

private def LoweredValueV1.isAggregate (v : LoweredValueV1) : Bool :=
  v.aggregateLeaves.isSome

private def LoweredValueV1.leafExprs (v : LoweredValueV1) : Array Expr :=
  match v.aggregateLeaves with
  | some ls => ls
  | none => #[v.expr]

private def LoweredValueV1.leafIsInts (v : LoweredValueV1) : Array Bool :=
  match v.aggregateLeafIsInt with
  | some flags => flags
  | none => #[v.isInt]

private def mkScalarValueV1 (expr : Expr) (deps : Array ValueIdV1)
    (isBool isInt : Bool) (bitWidth depth expandedNodes : Nat) : LoweredValueV1 :=
  { expr, depth, expandedNodes, dependencies := deps, isBool, isInt, bitWidth }

private def mkAggregateValueV1 (leaves : Array Expr) (leafIsInt : Array Bool)
    (deps : Array ValueIdV1) (depth expandedNodes : Nat) : LoweredValueV1 :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head
    depth
    expandedNodes
    dependencies := deps
    isBool := false
    isInt := false
    bitWidth := 64
    aggregateLeaves := some leaves
    aggregateLeafIsInt := some leafIsInt }

/-- Flatten a type into ordered leaf (name, isInt) pairs under EVM N3 policy.
    Scalars: UInt64 / Int64 only. Named Struct: field preorder. Named Enum:
    tag (UInt64) + max-payload leaf slots across variants (`_tag`, `_p0`…). -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array (String × Bool)) := do
  if typeId == types.uint64TypeId then
    pure #[(namePrefix, false)]
  else if types.int64TypeId == some typeId then
    pure #[(namePrefix, true)]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        throw <| .planInvariant .evm
          s!"unsupported EVM semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: named Struct requires at least one field"
            let mut out : Array (String × Bool) := #[]
            for f in fields do
              let subName :=
                if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
              unless isIdentifier subName do
                throw <| .planInvariant .evm
                  s!"storage name '{subName}' is not an EVM ABI identifier"
              let sub ← flattenTypeLeafSpecsV1 typeDecls types f.typeId subName
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: named Enum requires at least one variant"
            let tagName :=
              if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
            unless isIdentifier tagName do
              throw <| .planInvariant .evm
                s!"storage name '{tagName}' is not an EVM ABI identifier"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafSpecsV1 typeDecls types pt "tmp"
                n := n + sub.size
              if n > maxPay then maxPay := n
            let mut out : Array (String × Bool) := #[(tagName, false)]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                throw <| .planInvariant .evm
                  s!"storage name '{pName}' is not an EVM ABI identifier"
              out := out.push (pName, false)
            pure out
        | _ =>
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: named type must be Struct or Enum"
  else
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: storage/param leaf must be UInt64, Int64, or named Struct/Enum"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- Struct field leaf range (start, length) within the flattened leaf vector. -/
private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (fields : Array StructFieldV1) (fieldIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let mut start : Nat := 0
  for i in [0:fields.size] do
    let some f := fields[i]? |
      throw <| .planInvariant .evm "struct field index out of range"
    let n ← leafCountOfTypeV1 typeDecls types f.typeId
    if i == fieldIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .evm "struct field index out of range"

/-- Enum max payload leaf count (excluding tag). -/
private def enumMaxPayloadLeavesV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (variants : Array EnumVariantV1) : CompileResult Nat := do
  let mut maxPay : Nat := 0
  for v in variants do
    let mut n : Nat := 0
    for pt in v.payloadTypes do
      let c ← leafCountOfTypeV1 typeDecls types pt
      n := n + c
    if n > maxPay then maxPay := n
  pure maxPay

/-- Payload leaf offset of `payloadIndex` within variant `variantIndex`
    (0-based within the payload region after the tag). -/
private def enumPayloadLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (variants : Array EnumVariantV1) (variantIndex payloadIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let some v := variants[variantIndex]? |
    throw <| .planInvariant .evm "enum variant index out of range"
  let mut start : Nat := 0
  for i in [0:v.payloadTypes.size] do
    let some pt := v.payloadTypes[i]? |
      throw <| .planInvariant .evm "enum payload index out of range"
    let n ← leafCountOfTypeV1 typeDecls types pt
    if i == payloadIndex then return (start, n)
    start := start + n
  throw <| .planInvariant .evm "enum payload index out of range"

private def makeStorageLayoutV1
    (types : EvmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult EvmLowerLayoutV1 := do
  if states.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
  let mut bindings : Array StorageBinding := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      throw <| .planInvariant .evm "semantic state ids must match declaration order"
    unless isIdentifier state.name do
      throw <| .planInvariant .evm s!"state name '{state.name}' is not an EVM ABI identifier"
    if types.isNamedAggregate state.typeId then
      -- N3: flatten named Struct/Enum state to 64-bit leaf slots.
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState evmPlanErr types state
        (allowNonPublic := true)
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
      if leafSpecs.isEmpty then
        throw <| .planInvariant .evm s!"state '{state.name}' produced zero storage leaves"
      if bindings.size + leafSpecs.size > maxStorageBindings then
        throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
      let mut leaves : Array Nat := #[]
      for (leafName, _) in leafSpecs do
        let slot := bindings.size
        bindings := bindings.push {
          sourceId := slot
          name := leafName
          slot
          -- N3 aggregate leaves stay 64-bit words.
          byteWidth := 8
        }
        leaves := leaves.push slot
      stateLeaves := stateLeaves.push leaves
    else
      -- T8b: scalar state admits UInt{8,16,32,64} / Int64 with byteWidth 1/2/4/8.
      requirePublicUintAbiOrInt64State evmPlanErr types state (allowNonPublic := true)
      let byteWidth ← abiByteWidthOfTypeV1 types state.typeId
      let slot := bindings.size
      bindings := bindings.push {
        sourceId := slot
        name := state.name
        slot
        byteWidth
      }
      stateLeaves := stateLeaves.push #[slot]
  pure { bindings, stateLeaves, typeDecls }

/-- Width-dispatch for ABI param loads: UInt64/Int64 keep historical `param`. -/
private def mkParamExpr (bitWidth : Nat) (wordIndex : Nat) : Expr :=
  if bitWidth == 64 then .param wordIndex else .narrowParam bitWidth wordIndex

/-- Width-dispatch for storage loads: UInt64/Int64 keep historical `storageLoad`. -/
private def mkStorageLoadExpr (bitWidth : Nat) (slot : Nat) : Expr :=
  if bitWidth == 64 then .storageLoad slot else .narrowStorageLoad bitWidth slot

private def makeParamsV1 (owner : String) (types : EvmTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .evm s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  let mut nextWord : Nat := 0
  for param in params do
    unless param.valueId.toNat == values.size do
      throw <| .planInvariant .evm
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    unless isIdentifier param.name do
      throw <| .planInvariant .evm
        s!"parameter name '{param.name}' in {owner} is not an EVM ABI identifier"
    if types.isNamedAggregate param.typeId then
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedParam
        evmPlanErr types owner param (allowNonPublic := true)
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types param.typeId param.name
      if nextWord + leafSpecs.size > maxParams then
        throw <| .planInvariant .evm
          s!"parameter count in {owner} exceeds profile limit {maxParams}"
      let mut leafExprs : Array Expr := #[]
      let mut leafIsInt : Array Bool := #[]
      for (leafName, isInt) in leafSpecs do
        unless isIdentifier leafName do
          throw <| .planInvariant .evm
            s!"parameter name '{leafName}' in {owner} is not an EVM ABI identifier"
        -- ValidatePlan requires unique dense sourceId == wordIndex per ABI word.
        planned := planned.push {
          sourceId := nextWord
          name := leafName
          wordIndex := nextWord
          isInt
          -- N3 aggregate leaves stay 64-bit ABI words.
          byteWidth := 8
        }
        leafExprs := leafExprs.push (.param nextWord)
        leafIsInt := leafIsInt.push isInt
        nextWord := nextWord + 1
      values := values.push (mkAggregateValueV1 leafExprs leafIsInt #[] 1 leafExprs.size)
    else
      requirePublicUintAbiOrInt64Param
        evmPlanErr types owner param (allowNonPublic := true)
      let isInt := types.int64TypeId == some param.typeId
      let byteWidth ← abiByteWidthOfTypeV1 types param.typeId
      let bitWidth := bitWidthOfByteWidth byteWidth
      let binding : Param := {
        sourceId := nextWord
        name := param.name
        wordIndex := nextWord
        isInt
        byteWidth
      }
      planned := planned.push binding
      values := values.push {
        expr := mkParamExpr bitWidth binding.wordIndex
        depth := 1
        expandedNodes := 1
        dependencies := #[]
        isBool := false
        isInt
        bitWidth
      }
      nextWord := nextWord + 1
  return (planned, values)

private def findStateLeavesV1 (layout : EvmLowerLayoutV1)
    (id : StateIdV1) : CompileResult (Array Nat) :=
  match layout.stateLeaves[id.toNat]? with
  | some leaves =>
      if leaves.isEmpty then
        planError s!"semantic expression references empty leaf set for state id {id.toNat}"
      else .ok leaves
  | none => planError s!"semantic expression references unknown state id {id.toNat}"

private def findStorageV1 (layout : EvmLowerLayoutV1)
    (id : StateIdV1) : CompileResult StorageBinding := do
  let leaves ← findStateLeavesV1 layout id
  match leaves with
  | #[slot] =>
      match layout.bindings[slot]? with
      | some binding =>
          if binding.slot == slot then .ok binding
          else planError s!"semantic expression references noncanonical state id {id.toNat}"
      | none => planError s!"semantic expression references unknown state id {id.toNat}"
  | _ =>
      planError
        s!"semantic expression expects scalar state id {id.toNat}, got aggregate leaves"

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

/-- Admitted body UInt widths for EVM Yul (same set as ABI after T8b). -/
private def isEvmBodyUintWidth (w : Nat) : Bool :=
  isEvmAbiUintWidth w

/-- Shared bounded SSA-tree cost for binary Expr constructors. Operands must
    be non-Bool and share `bitWidth` (+ signedness for non-Bool results).
    Comparison results are Bool (`bitWidth=1`). -/
private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1)
    (isBool : Bool)
    (resultBitWidth : Nat)
    (resultIsInt : Bool := false) : CompileResult LoweredValueV1 := do
  unless !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: binary operands must be integer"
  unless isBool || (lhs.bitWidth == rhs.bitWidth && lhs.bitWidth == resultBitWidth) do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: binary operands must share integer width"
  unless isBool || lhs.isInt == rhs.isInt do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: binary operands must share signedness"
  unless isBool || (resultIsInt == lhs.isInt) do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: binary result signedness mismatch"
  unless isBool || isEvmBodyUintWidth resultBitWidth do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: width {resultBitWidth} is not an admitted body width"
  -- Int is Int64-only in the EVM pilot.
  unless isBool || !resultIsInt || resultBitWidth == 64 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: only Int64 is admitted (not narrower/wider Int)"
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
    isInt := resultIsInt
    bitWidth := resultBitWidth
  }

/-- Strict Bool binary: both operands must already be Bool-tagged; result is
    Bool. Same expanded-tree cost accounting as UInt binaries. -/
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
    bitWidth := 1
  }

/-- Admit a wire result TypeId for UInt-width arithmetic/bitwise and return
    `(typeId, bitWidth)`. UInt8/16/32/64 only; UInt128/256 fail closed. -/
private def admitUIntWidthResultTypeV1
    (types : EvmTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × Nat) := do
  match types.uintWidthOf resultTypeId with
  | some w =>
      unless isEvmBodyUintWidth w do
        throw <| .planInvariant .evm
          s!"unsupported EVM semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
      pure (resultTypeId, w)
  | none =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: arithmetic/bitwise result must be admitted UInt width"

/-- Admit Int64 result TypeId (sole signed width on EVM). -/
private def admitInt64ResultTypeV1
    (types : EvmTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult TypeIdV1 := do
  match types.int64TypeId with
  | some tid =>
      unless resultTypeId == tid do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: signed arithmetic result must be Int64"
      pure tid
  | none =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: Int64 type is not interned"

/-- Width-dispatch: UInt64 keeps historical constructors; narrow widths use
    `narrow*` so Emit can attach mask/overflow guards without touching goldens. -/
private def mkCheckedAdd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedAdd l r else .narrowCheckedAdd w l r
private def mkCheckedSub (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedSub l r else .narrowCheckedSub w l r
private def mkCheckedMul (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedMul l r else .narrowCheckedMul w l r
private def mkCheckedDiv (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedDiv l r else .narrowCheckedDiv w l r
private def mkCheckedMod (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .checkedMod l r else .narrowCheckedMod w l r
private def mkBitAnd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitAnd l r else .narrowBitAnd w l r
private def mkBitOr (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitOr l r else .narrowBitOr w l r
private def mkBitXor (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .bitXor l r else .narrowBitXor w l r
private def mkBitNot (w : Nat) (o : Expr) : Expr :=
  if w == 64 then .bitNot o else .narrowBitNot w o
private def mkShl (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .shl l r else .narrowShl w l r
private def mkShr (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .shr l r else .narrowShr w l r

private def makeCheckedAddValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 .signedCheckedAdd lhsId rhsId lhs rhs false 64
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedAdd bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedSubValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 .signedCheckedSub lhsId rhsId lhs rhs false 64
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedSub bitWidth) lhsId rhsId lhs rhs false bitWidth

/-- Comparison: same-width UInt or Int64 operands → Bool. -/
private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: comparison operands must be integer"
  unless lhs.bitWidth == rhs.bitWidth && isEvmBodyUintWidth lhs.bitWidth do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: comparison operands must share admitted width"
  unless lhs.isInt == rhs.isInt do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: comparison operands must share signedness"
  if lhs.isInt then
    unless lhs.bitWidth == 64 do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: only Int64 comparisons are admitted"
    makeBinaryTreeValueV1 (.signedCompare op) lhsId rhsId lhs rhs true 1
  else
    makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true 1

private def makeCheckedMulValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 .signedCheckedMul lhsId rhsId lhs rhs false 64
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedMul bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedDivValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 .signedCheckedDiv lhsId rhsId lhs rhs false 64
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedDiv bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedModValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 .signedCheckedMod lhsId rhsId lhs rhs false 64
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedMod bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeBitAndValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (mkBitAnd bitWidth) lhsId rhsId lhs rhs false bitWidth
    (resultIsInt := lhs.isInt)

private def makeBitOrValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (mkBitOr bitWidth) lhsId rhsId lhs rhs false bitWidth
    (resultIsInt := lhs.isInt)

private def makeBitXorValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (mkBitXor bitWidth) lhsId rhsId lhs rhs false bitWidth
    (resultIsInt := lhs.isInt)

/-- Shift tree cost: lhs carries `bitWidth`, count is UInt32 (distinct width). -/
private def makeShiftTreeValueV1
    (mk : Expr → Expr → Expr)
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: shift operands must be integer"
  unless !rhs.isInt do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: shift count must be UInt32"
  unless lhs.bitWidth == bitWidth && isEvmBodyUintWidth bitWidth do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: shift lhs width mismatch"
  unless rhs.bitWidth == 32 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: shift count must be UInt32"
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
    isBool := false
    isInt := lhs.isInt
    bitWidth
  }

private def makeShlValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  -- Int64 shl reuses unsigned shift with overflow gate (same bit semantics).
  let v ← makeShiftTreeValueV1 (mkShl bitWidth) bitWidth lhsId rhsId lhs rhs
  pure { v with isInt := lhs.isInt }

private def makeShrValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.isInt then
    -- Arithmetic right shift for Int64.
    unless bitWidth == 64 do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: only Int64 arithmetic shift is admitted"
    let v ← makeShiftTreeValueV1 .sar bitWidth lhsId rhsId lhs rhs
    pure { v with isInt := true }
  else
    makeShiftTreeValueV1 (mkShr bitWidth) bitWidth lhsId rhsId lhs rhs

private def makeLogicalAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeLogicalTreeValueV1 .logicalAnd lhsId rhsId lhs rhs

private def makeLogicalOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeLogicalTreeValueV1 .logicalOr lhsId rhsId lhs rhs

/-- Shared bounded SSA-tree cost for unary Expr constructors. -/
private def makeUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1)
    (expectBoolOperand isBoolResult : Bool)
    (resultBitWidth : Nat) : CompileResult LoweredValueV1 := do
  unless operand.isBool == expectBoolOperand do
    throw <| .planInvariant .evm
      (if expectBoolOperand then
        "unsupported EVM semantic shape: unary not operand must be Bool"
       else
        "unsupported EVM semantic shape: unary bitNot operand must be UInt")
  unless isBoolResult || operand.bitWidth == resultBitWidth do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: unary bitNot width mismatch"
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
    isInt := !isBoolResult && operand.isInt
    bitWidth := resultBitWidth
  }

private def makeBitNotValueV1
    (bitWidth : Nat)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (mkBitNot bitWidth) operandId operand false false bitWidth

private def makeCheckedNegValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless operand.isInt && !operand.isBool && operand.bitWidth == 64 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: checkedNeg requires Int64 operand"
  makeUnaryTreeValueV1 .checkedNeg operandId operand false false 64

private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 .boolNot operandId operand true true 1

/-- PureCall tree cost: one node plus each argument tree (SSA args counted per
    use). Args are UInt64 or Int64 words; result kind is the callee's. -/
private def makeCallFnValueV1
    (fnIndex : Nat)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1)
    (isBool : Bool)
    (isInt : Bool := false) : CompileResult LoweredValueV1 := do
  for arg in args do
    unless !arg.isBool && arg.bitWidth == 64 do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: pureCall arguments must be UInt64 or Int64"
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
    isInt := !isBool && isInt
    bitWidth := if isBool then 1 else 64
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
    (layout : EvmLowerLayoutV1)
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
        match types.uintWidthOf typeId with
        | some bitWidth => do
            let value ← decodeUIntWidthLiteralLe evmPlanErr "EVM" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .literal value
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isInt := false
              bitWidth
            }
        | none =>
            match types.intWidthOf typeId with
            | some 64 => do
                let value ← decodeInt64LiteralLe evmPlanErr "EVM" bytes
                values := ← appendResultValueV1 typeId values result {
                  expr := .literal value
                  depth := 1
                  expandedNodes := 1
                  dependencies := #[]
                  isBool := false
                  isInt := true
                  bitWidth := 64
                }
            | some w =>
                throw <| .planInvariant .evm
                  s!"unsupported EVM semantic shape: only Int64 is admitted, got Int{w}"
            | none => do
                let boolTid ← match types.boolTypeId with
                  | some tid => pure tid
                  | none => throw (.planInvariant .evm
                      "unsupported EVM semantic shape: Bool literal requires anonymous Bool type")
                unless typeId == boolTid do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: literal is not admitted UInt/Int64/Bool"
                let value ← decodeBoolLiteralV1 bytes
                -- Bool words are 0/1 UInt64 literals in the Plan expression surface,
                -- tagged isBool so return/assert/store kind gates remain defensive.
                values := ← appendResultValueV1 boolTid values result {
                  expr := .literal value
                  depth := 1
                  expandedNodes := 1
                  dependencies := #[]
                  isBool := true
                  isInt := false
                  bitWidth := 1
                }
    | .stateLoad stateId, some result =>
        if mode == .pureFn then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: pureFn body loads storage"
        let leaves ← findStateLeavesV1 layout stateId
        if types.isNamedAggregate result.typeId then
          -- N3 aggregate load; per-leaf isInt restored from the flatten specs
          -- (the base N3 lowering marked every leaf UInt64, losing Int64 flags).
          let specs ← flattenTypeLeafSpecsV1 layout.typeDecls types result.typeId "state"
          unless specs.size == leaves.size do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: aggregate state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          let mut leafIsInt : Array Bool := #[]
          for i in [0:leaves.size] do
            let some slot := leaves[i]? |
              throw <| .planInvariant .evm "aggregate state load slot missing"
            let some (_, isInt) := specs[i]? |
              throw <| .planInvariant .evm "aggregate state load spec missing"
            leafExprs := leafExprs.push (.storageLoad slot)
            leafIsInt := leafIsInt.push isInt
          let value := mkAggregateValueV1 leafExprs leafIsInt #[] 1 leaves.size
          values := ← appendResultValueV1 result.typeId values result value
        else
          let binding ← findStorageV1 layout stateId
          let expectedBitWidth := bitWidthOfByteWidth binding.byteWidth
          let isInt := types.int64TypeId == some result.typeId
          if isInt then
            unless binding.byteWidth == 8 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Int64 state load requires 8-byte slot"
            values := ← appendResultValueV1 result.typeId values result {
              expr := .storageLoad binding.slot
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isInt := true
              bitWidth := 64
            }
          else
            match types.uintWidthOf result.typeId with
            | some bitWidth =>
                unless bitWidth == expectedBitWidth do
                  throw <| .planInvariant .evm
                    s!"unsupported EVM semantic shape: state load result UInt{bitWidth} does not match storage byteWidth {binding.byteWidth}"
                unless isEvmAbiUintWidth bitWidth do
                  throw <| .planInvariant .evm
                    s!"unsupported EVM semantic shape: state load result UInt{bitWidth} is not admitted"
                values := ← appendResultValueV1 result.typeId values result {
                  expr := mkStorageLoadExpr bitWidth binding.slot
                  depth := 1
                  expandedNodes := 1
                  dependencies := #[]
                  isBool := false
                  isInt := false
                  bitWidth
                }
            | none =>
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: state load result must be UInt{8,16,32,64} or Int64"
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables rhsId
        if op == .add then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeCheckedAddValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedAddValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .sub then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeCheckedSubValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedSubValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .mul then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeCheckedMulValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedMulValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .div then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeCheckedDivValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedDivValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .mod then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeCheckedModValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedModValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .bitAnd then
          -- Bitwise is bit-pattern identical for Int64 two's complement.
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeBitAndValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitAndValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .bitOr then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeBitOrValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitOrValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .bitXor then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeBitXorValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitXorValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .shl then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeShlValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeShlValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .shr then
          if types.intWidthOf result.typeId == some 64 then
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeShrValueV1 64 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeShrValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
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
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitNotValueV1 bitWidth operandId operand
            values := ← appendResultValueV1 widthTid values result value
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
            -- Int64: Op.Unary.neg (intMin reverts). UInt still arrives as 0-x.
            let tid ← admitInt64ResultTypeV1 types result.typeId
            let value ← makeCheckedNegValueV1 operandId operand
            values := ← appendResultValueV1 tid values result value
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
          unless !arg.isBool && arg.bitWidth == 64 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: pureCall arguments must be UInt64 or Int64"
          argValues := argValues.push arg
        let value ← makeCallFnValueV1 fnIndex argIds argValues fnBinding.resultIsBool
          fnBinding.resultIsInt
        if fnBinding.resultIsBool then
          let boolTid ← match types.boolTypeId with
            | some tid => pure tid
            | none => throw (.planInvariant .evm
                "unsupported EVM semantic shape: Bool pureCall requires anonymous Bool type")
          unless result.typeId == boolTid do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: pureCall result type must match callee Bool"
          values := ← appendResultValueV1 boolTid values result value
        else if fnBinding.resultIsInt then
          let tid ← admitInt64ResultTypeV1 types result.typeId
          values := ← appendResultValueV1 tid values result value
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
        let leaves ← findStateLeavesV1 layout stateId
        -- Consume the whole segment via the stored value's dependency closure
        -- (works for both scalar and aggregate roots).
        let _ ← consumeCurrentSegmentWithArmsV1
          values paramCount segmentStart armReadables valueId
        if stored.isAggregate then
          let leafExprs := stored.leafExprs
          unless leafExprs.size == leaves.size do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: aggregate state store leaf count mismatch"
          for i in [0:leaves.size] do
            let some slot := leaves[i]? |
              throw <| .planInvariant .evm "aggregate store leaf slot missing"
            let some expr := leafExprs[i]? |
              throw <| .planInvariant .evm "aggregate store leaf expr missing"
            -- N3 aggregate leaves stay 64-bit storage words.
            body := body.push (.store { slot, value := expr, byteWidth := 8 })
        else
          unless leaves.size == 1 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: scalar store targets multi-leaf state"
          let binding ← findStorageV1 layout stateId
          let expectedBitWidth := bitWidthOfByteWidth binding.byteWidth
          unless !stored.isBool && stored.bitWidth == expectedBitWidth do
            throw <| .planInvariant .evm
              s!"unsupported EVM semantic shape: state store value width {stored.bitWidth} must match storage bitWidth {expectedBitWidth}"
          unless !stored.isInt || expectedBitWidth == 64 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: Int state store requires 8-byte slot"
          unless stored.isInt || isEvmAbiUintWidth stored.bitWidth do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: state store value must be admitted UInt width or Int64"
          body := body.push (.store {
            slot := binding.slot
            value := stored.expr
            byteWidth := binding.byteWidth
          })
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
          unless !root.isBool && root.bitWidth == 64 do
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
    | .construct typeId ctorIdx argIds, some result => do
        unless result.typeId == typeId do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: construct result typeId must match op typeId"
        unless types.isNamedAggregate typeId do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: construct requires named Struct/Enum"
        let some decl := layout.typeDecls[typeId.toNat]? |
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: construct TypeDecl missing"
        match decl.shape with
        | .struct fields => do
            unless ctorIdx.toNat == 0 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: struct construct ctorIdx must be 0"
            unless argIds.size == fields.size do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: struct construct arity mismatch"
            let mut leaves : Array Expr := #[]
            let mut leafIsInt : Array Bool := #[]
            let mut deps : Array ValueIdV1 := #[]
            let mut depth : Nat := 1
            let mut nodes : Nat := 1
            for i in [0:argIds.size] do
              let some argId := argIds[i]? |
                throw <| .planInvariant .evm "struct construct arg missing"
              let some field := fields[i]? |
                throw <| .planInvariant .evm "struct construct field missing"
              let arg ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
              let expectedLeaves ← leafCountOfTypeV1 layout.typeDecls types field.typeId
              let argLeaves := arg.leafExprs
              let argIsInt := arg.leafIsInts
              unless argLeaves.size == expectedLeaves do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: struct construct field leaf count mismatch"
              leaves := leaves ++ argLeaves
              leafIsInt := leafIsInt ++ argIsInt
              deps := deps.push argId
              depth := Nat.max depth (arg.depth + 1)
              nodes := nodes + arg.expandedNodes
            let value := mkAggregateValueV1 leaves leafIsInt deps depth nodes
            values := ← appendResultValueV1 typeId values result value
        | .enum variants => do
            let vi := ctorIdx.toNat
            let some variant := variants[vi]? |
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: enum construct variant out of range"
            unless argIds.size == variant.payloadTypes.size do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: enum construct arity mismatch"
            let maxPay ← enumMaxPayloadLeavesV1 layout.typeDecls types variants
            let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
            let mut leafIsInt : Array Bool := #[false]
            let mut deps : Array ValueIdV1 := #[]
            let mut depth : Nat := 1
            let mut nodes : Nat := 1
            for i in [0:argIds.size] do
              let some argId := argIds[i]? |
                throw <| .planInvariant .evm "enum construct arg missing"
              let some pt := variant.payloadTypes[i]? |
                throw <| .planInvariant .evm "enum construct payload type missing"
              let arg ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
              let expectedLeaves ← leafCountOfTypeV1 layout.typeDecls types pt
              let argLeaves := arg.leafExprs
              let argIsInt := arg.leafIsInts
              unless argLeaves.size == expectedLeaves do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: enum construct payload leaf count mismatch"
              leaves := leaves ++ argLeaves
              leafIsInt := leafIsInt ++ argIsInt
              deps := deps.push argId
              depth := Nat.max depth (arg.depth + 1)
              nodes := nodes + arg.expandedNodes
            -- Pad payload region to maxPay so enum storage layout is fixed-width.
            while leaves.size < 1 + maxPay do
              leaves := leaves.push (.literal 0)
              leafIsInt := leafIsInt.push false
            let value := mkAggregateValueV1 leaves leafIsInt deps depth nodes
            values := ← appendResultValueV1 typeId values result value
        | _ =>
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: construct requires Struct or Enum shape"
    | .fieldGet baseId fieldIndex, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: fieldGet base must be a named aggregate"
        let baseLeaves := base.leafExprs
        let baseIsInt := base.leafIsInts
        -- Locate unique named struct whose total leaf count == baseLeaves.size
        -- and fieldIndex is in range with matching result type.
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          match layout.typeDecls[tid.toNat]? with
          | some { shape := .struct fields, .. } => do
              let total ← leafCountOfTypeV1 layout.typeDecls types tid
              if total == baseLeaves.size && fieldIndex.toNat < fields.size then
                match fields[fieldIndex.toNat]? with
                | some f =>
                    if f.typeId == result.typeId then
                      let (s, l) ←
                        structFieldLeafRangeV1 layout.typeDecls types fields
                          fieldIndex.toNat
                      hit := some (s, l)
                | none => pure ()
          | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: fieldGet could not resolve struct field range"
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: fieldGet leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        let mut outIsInt : Array Bool := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .evm "fieldGet leaf missing"
          let some b := baseIsInt[i]? |
            throw <| .planInvariant .evm "fieldGet leaf isInt missing"
          outLeaves := outLeaves.push e
          outIsInt := outIsInt.push b
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves outIsInt #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .evm "fieldGet scalar leaf missing"
            let isInt := match outIsInt[0]? with | some b => b | none => false
            pure {
              expr := e0
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
              isBool := false
              isInt
              bitWidth := 64
            }
        values := ← appendResultValueV1 result.typeId values result value
    | .fieldSet baseId fieldIndex valueId, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        let val ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
        unless base.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: fieldSet base must be a named aggregate"
        unless types.isNamedAggregate result.typeId do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: fieldSet result must be named aggregate"
        let baseLeaves := base.leafExprs
        let baseIsInt := base.leafIsInts
        let valLeaves := val.leafExprs
        let valIsInt := val.leafIsInts
        -- Resolve field range via unique named struct matching base leaf count + result type.
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          if tid == result.typeId then
            match layout.typeDecls[tid.toNat]? with
            | some { shape := .struct fields, .. } => do
                if fieldIndex.toNat < fields.size then
                  let (s, l) ←
                    structFieldLeafRangeV1 layout.typeDecls types fields fieldIndex.toNat
                  hit := some (s, l)
            | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: fieldSet could not resolve struct field range"
        unless start + len <= baseLeaves.size && valLeaves.size == len do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: fieldSet leaf range/value size mismatch"
        let mut outLeaves : Array Expr := #[]
        let mut outIsInt : Array Bool := #[]
        for i in [0:baseLeaves.size] do
          if i >= start && i < start + len then
            let j := i - start
            let some e := valLeaves[j]? |
              throw <| .planInvariant .evm "fieldSet value leaf missing"
            let some b := valIsInt[j]? |
              throw <| .planInvariant .evm "fieldSet value isInt missing"
            outLeaves := outLeaves.push e
            outIsInt := outIsInt.push b
          else
            let some e := baseLeaves[i]? |
              throw <| .planInvariant .evm "fieldSet base leaf missing"
            let some b := baseIsInt[i]? |
              throw <| .planInvariant .evm "fieldSet base isInt missing"
            outLeaves := outLeaves.push e
            outIsInt := outIsInt.push b
        let value := mkAggregateValueV1 outLeaves outIsInt #[baseId, valueId]
          (Nat.max base.depth val.depth + 1)
          (base.expandedNodes + val.expandedNodes + 1)
        values := ← appendResultValueV1 result.typeId values result value
    | .variantTag baseId, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: variantTag base must be a named Enum aggregate"
        -- Tag is leaf 0; result must be unique UInt32 in the pilot (Normalize emits UInt32).
        let u32Tid ← match types.uintWidthOf result.typeId with
          | some 32 => pure result.typeId
          | _ =>
              -- Also accept UInt64 if the type closure lacks a distinct UInt32
              -- (should not happen after Normalize).
              if result.typeId == uint64TypeId then pure result.typeId
              else
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: variantTag result must be UInt32"
        let some tagExpr := base.leafExprs[0]? |
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: variantTag enum has no tag leaf"
        values := ← appendResultValueV1 result.typeId values result {
          expr := tagExpr
          depth := base.depth + 1
          expandedNodes := base.expandedNodes + 1
          dependencies := #[baseId]
          isBool := false
          isInt := false
          bitWidth :=
            match types.uintWidthOf result.typeId with
            | some w => w
            | none => 64
        }
        let _ := u32Tid
    | .variantPayload baseId variantIndex payloadIndex, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: variantPayload base must be a named Enum"
        let mut hit : Option (Nat × Nat) := none
        for tid in types.namedTypeIds do
          match layout.typeDecls[tid.toNat]? with
          | some { shape := .enum variants, .. } => do
              let total ← leafCountOfTypeV1 layout.typeDecls types tid
              if total == base.leafExprs.size then
                let (s, l) ← enumPayloadLeafRangeV1 layout.typeDecls types variants
                  variantIndex.toNat payloadIndex.toNat
                -- payload region starts after tag (offset +1)
                hit := some (s + 1, l)
          | _ => pure ()
        let (start, len) ← match hit with
          | some r => pure r
          | none =>
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: variantPayload could not resolve range"
        let baseLeaves := base.leafExprs
        let baseIsInt := base.leafIsInts
        unless start + len <= baseLeaves.size do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: variantPayload leaf range out of bounds"
        let mut outLeaves : Array Expr := #[]
        let mut outIsInt : Array Bool := #[]
        for i in [start:start+len] do
          let some e := baseLeaves[i]? |
            throw <| .planInvariant .evm "variantPayload leaf missing"
          let some b := baseIsInt[i]? |
            throw <| .planInvariant .evm "variantPayload isInt missing"
          outLeaves := outLeaves.push e
          outIsInt := outIsInt.push b
        let value ←
          if types.isNamedAggregate result.typeId then
            pure (mkAggregateValueV1 outLeaves outIsInt #[baseId]
              (base.depth + 1) (base.expandedNodes + 1))
          else
            let some e0 := outLeaves[0]? |
              throw <| .planInvariant .evm "variantPayload scalar missing"
            let isInt := match outIsInt[0]? with | some b => b | none => false
            pure {
              expr := e0
              depth := base.depth + 1
              expandedNodes := base.expandedNodes + 1
              dependencies := #[baseId]
              isBool := false
              isInt
              bitWidth := 64
            }
        values := ← appendResultValueV1 result.typeId values result value
    | .indexGet .., some _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: IndexGet is outside the EVM named-aggregate pilot (no Array/Map/Bytes state)"
    | .indexSet .., some _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: IndexSet is outside the EVM named-aggregate pilot (no Array/Map/Bytes state)"
    | _, _ =>
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart, hasAssert }

/-- Decode a switch case constant against the scrutinee kind/width. -/
private def decodeSwitchCaseValueV1
    (scrutIsBool : Bool) (scrutBitWidth : Nat) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if scrutIsBool then
    decodeBoolLiteralV1 bytes
  else
    decodeUIntWidthLiteralLe evmPlanErr "EVM" scrutBitWidth bytes

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
    (layout : EvmLowerLayoutV1)
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
                  unless !returned.isBool && !returned.isInt && returned.bitWidth == 64 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt64"
              | .int64 =>
                  unless !returned.isBool && returned.isInt && returned.bitWidth == 64 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Int64"
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
            let caseValue ←
              decodeSwitchCaseValueV1 scrutVal.isBool scrutVal.bitWidth switchCase.valueBytes
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
    (layout : EvmLowerLayoutV1)
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
    (layout : EvmLowerLayoutV1)
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
  let (params, initialValues) ← makeParamsV1 owner types layout.typeDecls callable.params
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
    (layout : EvmLowerLayoutV1)
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
    (layout : EvmLowerLayoutV1)
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
    throw <| .planInvariant .evm
      s!"entry '{name}' does not return public UInt64, Int64, or Bool"
  let resultKind : ResultKind ←
    if callable.result.typeId == types.uint64TypeId then
      pure .uint64
    else if types.int64TypeId == some callable.result.typeId then
      pure .int64
    else if types.boolTypeId == some callable.result.typeId then
      pure .bool
    else
      throw <| .planInvariant .evm
        s!"entry '{name}' does not return public UInt64, Int64, or Bool"
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
    selector := Keccak.selector name
      (lowered.params.map abiParamTypeString)
    params := lowered.params
    mutability
    body := lowered.body
    resultKind
  }

/-- Lower one pureFn callable into a dense Plan fn binding. Signatures in
    `fns` must already be populated so nested pureCall can resolve arity/kind. -/
private def makeFnV1
    (types : EvmTypeClosureV1)
    (layout : EvmLowerLayoutV1)
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
    throw <| .planInvariant .evm
      s!"fn '{name}' does not return public UInt64, Int64, or Bool"
  let (resultIsBool, resultIsInt, resultKind) : Bool × Bool × ResultKind ←
    if callable.result.typeId == types.uint64TypeId then
      pure (false, false, .uint64)
    else if types.int64TypeId == some callable.result.typeId then
      pure (false, true, .int64)
    else if types.boolTypeId == some callable.result.typeId then
      pure (true, false, .bool)
    else
      throw <| .planInvariant .evm
        s!"fn '{name}' does not return public UInt64, Int64, or Bool"
  let lowered ← lowerCallableV1 s!"fn '{name}'" .pureFn types layout
    fnIndexByCallableId fns callable (some resultKind)
  pure {
    name
    params := lowered.params
    body := lowered.body
    resultIsBool
    resultIsInt
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

/-- EVM-private public-UInt64/Int64 SemanticProgramV1 data → target-owned Plan.
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
  let storageLayout ← makeStorageLayoutV1 types source.types source.logicalState
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
            s!"fn '{name}' does not return public UInt64, Int64, or Bool"
        let (resultIsBool, resultIsInt) : Bool × Bool ←
          if callable.result.typeId == types.uint64TypeId then
            pure (false, false)
          else if types.int64TypeId == some callable.result.typeId then
            pure (false, true)
          else if types.boolTypeId == some callable.result.typeId then
            pure (true, false)
          else
            throw <| .planInvariant .evm
              s!"fn '{name}' does not return public UInt64, Int64, or Bool"
        let (params, _) ←
          makeParamsV1 s!"fn '{name}'" types storageLayout.typeDecls callable.params
        let fnIndex := fns.size
        fnIndexByCallableId := fnIndexByCallableId.set! callable.id.toNat (some fnIndex)
        fns := fns.push { name, params, body := #[], resultIsBool, resultIsInt }
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
  if !storageLayout.bindings.isEmpty && constructor.isNone then
    throw <| .planInvariant .evm "stateful programs require an explicit initializer"
  let runtimeObjectName :=
    if objectName == "__proof_forge_runtime" then
      "__proof_forge_runtime_1"
    else
      "__proof_forge_runtime"
  let plan : Plan := {
    objectName
    runtimeObjectName
    storageLayout := storageLayout.bindings
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
