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
    `byteWidth ∈ {1,2,4,8,32}` is the physical storage width (narrow values live
    in the low bytes of a 32-byte slot; Field uses the full 32-byte word).
    Default 8 keeps historical UInt64/Int64 Plan literals byte-identical. -/
structure StorageBinding where
  sourceId : Nat
  name : String
  slot : Nat
  /-- Physical width in bytes: UInt8→1, UInt16→2, UInt32→4, UInt64/Int64→8,
      Field(bn254)→32. -/
  byteWidth : Nat := 8
  deriving BEq, Inhabited, Repr

/-- Target-owned ABI word binding. `sourceId` is retained only for traceability;
all lowering after plan construction uses `wordIndex`. Each param still occupies
one 32-byte ABI word; narrow values sit in the low bytes; Field uses the full word. -/
structure Param where
  sourceId : Nat
  name : String
  wordIndex : Nat
  /-- True when the ABI word is signed Int (selector `int8`..`int64`); default
      false keeps historical UInt64 Plan literals byte-identical. -/
  isInt : Bool := false
  /-- Physical ABI value width in bytes: UInt/Int 8→1 … 64→8, Field→32.
      Field uses `byteWidth = 32` with `isInt = false` (ABI type `uint256`). -/
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
  /-- Full-word (or multi-limb) literal for UInt128/256 (T9b). Yul renders as
      decimal Nat; values may exceed UInt64. -/
  | bigLiteral (value : Nat)
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
  /-- Checked add at non-64 admitted width (T8b/T9b: `{8,16,32,128,256}`). -/
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
  /-- T9c: checked signed arithmetic on Int{8,16,32}; bitWidth selects signextend
  byte index and intMin/intMax range gate. Int64 keeps `signedChecked*`. -/
  | narrowSignedCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCompare (bitWidth : Nat) (op : ComparisonOp) (lhs rhs : Expr)
  | narrowCheckedNeg (bitWidth : Nat) (operand : Expr)
  /-- Arithmetic right shift of Int{8,16,32}; count is UInt32; reverts when
  `count ≥ bitWidth`. -/
  | narrowSar (bitWidth : Nat) (lhs rhs : Expr)
  /-- Storage load of a non-64 UInt/Int value; Yul masks after `sload`.
  UInt64/Int64 keep historical `storageLoad`. -/
  | narrowStorageLoad (bitWidth : Nat) (slot : Nat)
  /-- ABI param load of a non-64 UInt value; Yul masks after calldataload/mload.
  UInt64/Int64 keep historical `param`. -/
  | narrowParam (bitWidth : Nat) (wordIndex : Nat)
  /-- Exact mod-p Field arithmetic (bn254 Fr via ADDMOD/MULMOD). No overflow
  assert; div reverts on zero divisor (Fermat inv via `pow(b, p-2, p)`). -/
  | fieldAdd (lhs rhs : Expr)
  | fieldSub (lhs rhs : Expr)
  | fieldMul (lhs rhs : Expr)
  | fieldDiv (lhs rhs : Expr)
  /-- Field unary neg: `(p - a) mod p` via ADDMOD. -/
  | fieldNeg (operand : Expr)
  /-- Full 32-byte storage load for Field (no UInt64 range gate). -/
  | fieldStorageLoad (slot : Nat)
  /-- ArrayState: bounds-checked load from a contiguous storage slot range.
      Yul: `if iszero(lt(index, length)) { revert(0, 0) }` then
      `sload(add(baseSlot, index))` (narrow: mask after sload).
      `byteWidth ∈ {1,2,4,8}`. -/
  | indexedStorageLoad (baseSlot length : Nat) (index : Expr) (byteWidth : Nat := 8)
  /-- ArrayState: bounds-checked select among a fixed leaf vector (runtime index
      over non-contiguous or non-storage aggregate leaves). -/
  | arrayIndexGet (index : Expr) (leaves : Array Expr)
  /-- ArrayState: evaluate `index`, revert when `index ≥ length`, return index.
      Used so runtime IndexSet rebinds can share a single bounds gate. -/
  | boundsCheckedIndex (index : Expr) (length : Nat)
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
  /-- Sync external call (void). `callee` is the static QualifiedName component
      array (≥2); Yul derives a fixed 20-byte CALL address as the last 20 bytes
      of `keccak256(UTF-8 of target path)` and a 4-byte selector from the method
      name + `uint64` ABI. Not a dynamic address ValueId (B-3 Principal remains
      fail-closed). Failure reverts the caller. -/
  | externalCall (callee : Array String) (args : Array Expr)
  /-- Async fire-and-forget schedule (void). Same static-callee address/selector
      derivation as `externalCall`, but CALL success is ignored (no response
      channel — matches Reference schedule semantics). -/
  | schedule (callee : Array String) (args : Array Expr)
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

/-- Declared ABI result kind for an entry/view. Results admit
UInt8/16/32/64/128/256/Bool/Int8/16/32/64/Field (T9a/T9b/T9c). -/
inductive ResultKind where
  | uint64
  | bool
  | int64
  /-- bn254 Fr Field (ABI `uint256` full word). -/
  | field
  /-- T9a: narrow public UInt entry/view results (ABI `uint8`/`uint16`/`uint32`). -/
  | uint8
  | uint16
  | uint32
  /-- T9b: wide public UInt entry/view results (ABI `uint128`/`uint256`). -/
  | uint128
  | uint256
  /-- T9c: narrow public Int entry/view results (ABI `int8`/`int16`/`int32`). -/
  | int8
  | int16
  | int32
  deriving BEq, Inhabited, Repr

/-- Solidity ABI type string for a plan Param (selector + `.abi.json`). -/
def abiParamTypeString (p : Param) : String :=
  if p.isInt then
    match p.byteWidth with
    | 1 => "int8"
    | 2 => "int16"
    | 4 => "int32"
    | _ => "int64"
  else match p.byteWidth with
  | 1 => "uint8"
  | 2 => "uint16"
  | 4 => "uint32"
  | 16 => "uint128"
  | 32 => "uint256"
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
  /-- True when the pureFn result is Int8/16/32/64 (mutually exclusive with resultIsBool). -/
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
    Bool + UInt8/16/32 optional; Int64 optional; Field optional. Top-level
    scalar state/params admit UInt8/16/32/64/Int64/Field; named Struct/Enum
    state/params are flattened to UInt64/Int64 ABI/storage leaves (N3). -/
private abbrev EvmTypeClosureV1 := PilotTypeClosureV1

private def evmPlanErr (message : String) : CompileError :=
  .planInvariant .evm message

/-- EVM pilot admits anonymous UInt8/16/32/64 + Int64 + Unit + Bool + Field
    under `pilotUintWidthPolicyEvmBody` + `pilotIntWidthPolicyNarrow` +
    `pilotFieldPolicyBn254`, plus **named Struct/Enum**
    (`pilotNamedAggregateStatePolicyAdmit`, N3) and **anonymous fixed-length
    Array + Map + Bytes** (I1 MapState + EvmIndex + D4-E2). Body multi-width
    UInt and Int64 values are allowed; **top-level scalar state and ABI
    parameters admit UInt8/16/32/64/Int64/Field** via
    `requirePublicUintAbiOrInt64OrField*` (T8b + N2b-EVM), **named aggregates
    admit UInt64/Int64 leaves only** via
    `requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamed*` with
    `allowNonPublic := true` (N3), **Array state** flattens to contiguous
    scalar slots (element UInt8/16/32/64/128/256), and **Map UInt64 UInt64**
    flattens to a dense pilot table (16×(occ,key,val) UInt64 leaves; dynamic
    keys OK). non-64 Int fail closed.
    T9b admits UInt128/256 on scalar state/param/body/result. T10: Principal
    admitted as **storage identity only** (`pilotPrincipalPolicyAdmit`) —
    fixed leaf layout len+8×UInt64 (≤64B body, same pattern as N4 String);
    still not a fixed 20-byte EVM address (no truncate/pad/strip-prefix
    mapping; CALL target remains static QN). -/
private def validateEvmTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult EvmTypeClosureV1 :=
  validatePilotTypeClosure evmPlanErr evmTypeClosureWording types
    pilotUintWidthPolicyEvmBody
    (intPolicy := pilotIntWidthPolicyNarrow)
    (fieldPolicy := pilotFieldPolicyBn254)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (stringPolicy := pilotStringPolicyAdmit)
    -- I1 MapState + D4-E2: Array + Map + fixed Bytes.
    (containerPolicy := pilotContainerStatePolicyArrayMapBytes)

/-- Lowering-time storage + type table. Plan.storageLayout is `bindings`
    (flattened leaf slots; sourceId == slot == declaration order of leaves).
    `stateLeaves[stateId]` is the ordered leaf slot list for that logical state.
    `mapStaticKeys` is the program-wide sorted UInt64 key table for Map UInt64
    UInt64 (I1 MapState; empty when no Map index ops). -/
private structure EvmLowerLayoutV1 where
  bindings : Array StorageBinding
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  mapStaticKeys : Array UInt64 := #[]
  deriving Inhabited

/-- Resolve admitted scalar state/param TypeId to physical byte width
    (1/2/4/8/32). Named aggregates must NOT be passed here. -/
private def abiByteWidthOfTypeV1
    (types : EvmTypeClosureV1) (typeId : TypeIdV1) : CompileResult Nat := do
  if types.isField typeId then
    pure 32
  else
    match types.uintWidthOf typeId with
    | some w =>
        unless isEvmAbiUintWidth w do
          throw <| .planInvariant .evm
            s!"unsupported EVM semantic shape: ABI UInt{w} is not admitted"
        pure (byteWidthOfBitWidth w)
    | none =>
        match types.intWidthOf typeId with
        | some w =>
            unless isAbiIntWidth w do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: ABI Int{w} is not admitted"
            pure (byteWidthOfBitWidth w)
        | none =>
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: ABI type must be UInt8/16/32/64/128/256, Int8/16/32/64, or Field"

private structure LoweredValueV1 where
  expr : Expr
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  /-- Defensive kind bit: true for comparison/logical results and Bool
  literals only. State loads, params, UInt arithmetic/bitwise/shift are false. -/
  isBool : Bool
  /-- True for Int8/16/32/64-typed values (mutually exclusive with isBool/isField). -/
  isInt : Bool := false
  /-- True for bn254 Field-typed values (mutually exclusive with isBool/isInt). -/
  isField : Bool := false
  /-- Bit width of non-Bool values: 8/16/32/64 for UInt/Int; 256 for Field.
      Bool uses 1. -/
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

/-- EVM pilot String storage layout (N4, deterministic, fixed leaf count):
    * leaf 0: UTF-8 byte length (`UInt64`)
    * leaves 1..8: up to 64 payload bytes packed little-endian into 8×UInt64
      words (zero-padded)
    Strings longer than 64 UTF-8 bytes fail closed at plan lowering.
    Wire still admits up to `maxTypeLengthV1`; only the EVM pilot bound is 64. -/
private def evmStringMaxPayloadBytesV1 : Nat := 64
private def evmStringDataWordCountV1 : Nat := 8  -- 64 / 8

/-- EVM pilot Principal storage layout (T10, isomorphic to N4 String):
    * leaf 0: wire body length (`UInt64`; wire framing is still `u32le`)
    * leaves 1..8: up to 64 opaque body bytes packed little-endian into
      8×UInt64 words (zero-padded)
    Principal body longer than 64 bytes fails closed at plan lowering.
    Full wire admits 1..`maxTypeLengthV1`; EVM pilot bound is 64.
    **Not** a 20-byte EVM address — storage is raw wire identity only. -/
private def evmPrincipalMaxPayloadBytesV1 : Nat := 64
private def evmPrincipalDataWordCountV1 : Nat := 8  -- 64 / 8

/-- Shared len+payload leaf layout for N4 String and T10 Principal. -/
private def flattenWireBytesLeafSpecsV1 (namePrefix : String) (dataWordCount : Nat) :
    CompileResult (Array (String × Bool)) := do
  let lenName :=
    if namePrefix.isEmpty then "len" else namePrefix ++ "_len"
  unless isIdentifier lenName do
    throw <| .planInvariant .evm
      s!"storage name '{lenName}' is not an EVM ABI identifier"
  let mut out : Array (String × Bool) := #[(lenName, false)]
  for i in [0:dataWordCount] do
    let wName :=
      if namePrefix.isEmpty then s!"w{i}" else namePrefix ++ "_w" ++ toString i
    unless isIdentifier wName do
      throw <| .planInvariant .evm
        s!"storage name '{wName}' is not an EVM ABI identifier"
    out := out.push (wName, false)
  pure out

/-- Flatten a type into ordered leaf (name, isInt) pairs under EVM N3/N4/T10
    policy. Scalars: UInt64 / Int64 / String / Principal (length+8 data words).
    Named Struct: field preorder. Named Enum: tag (UInt64) + max-payload leaf
    slots across variants (`_tag`, `_p0`…). -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array (String × Bool)) := do
  if typeId == types.uint64TypeId then
    pure #[(namePrefix, false)]
  else if types.int64TypeId == some typeId then
    pure #[(namePrefix, true)]
  else if types.isString typeId then
    flattenWireBytesLeafSpecsV1 namePrefix evmStringDataWordCountV1
  else if types.isPrincipal typeId then
    flattenWireBytesLeafSpecsV1 namePrefix evmPrincipalDataWordCountV1
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
      "unsupported EVM semantic shape: storage/param leaf must be UInt64, Int64, String, Principal, or named Struct/Enum"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- Container positive layout: fixed-length `Array UInt8/16/32/64 N` or
    `Bytes N` (flattened as N×UInt8). Returns `(elementBitWidth, N)`.
    Map is handled separately via `mapUInt64LeafCountV1` (I1). Non-UInt Array
    elements fail closed. -/
private def arrayScalarLeafLayoutV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Nat × Nat)) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      let bitWidth ← match types.uintWidthOf elTid with
        | some w =>
            unless isEvmAbiUintWidth w do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: Array element UInt{w} is not admitted"
            pure w
        | none =>
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: Array state element must be UInt8/16/32/64"
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: Array state length must be ≥ 1"
      pure (some (bitWidth, n))
  | some { shape := .map .., .. } =>
      -- I1 MapState: leaf count depends on program-static keys; caller uses
      -- `mapUInt64LeafCountV1`. Signal "not Array/Bytes" with none only when
      -- the type is Map — callers must branch on shape.
      pure none
  | some { shape := .bytes len, .. } =>
      -- D4-E2: fixed-length Bytes N → N consecutive UInt8 storage leaves.
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: Bytes state length must be ≥ 1"
      pure (some (8, n))
  | _ =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: container TypeId is not Array/Map/Bytes"

/-- NS-1b / I1 Map pilot capacity: dense open table for dynamic UInt64 keys.
    Each entry: occupied (0/1), key, value → 3×UInt64 leaves. -/
private def evmMapPilotCapacityV1 : Nat := 16
private def evmMapSlotsPerEntryV1 : Nat := 3
private def evmMapPilotLeafCountV1 : Nat :=
  evmMapPilotCapacityV1 * evmMapSlotsPerEntryV1

/-- Map UInt64 UInt64 leaf count = fixed pilot capacity × 3 (occ/key/val).
    Dynamic keys are supported (Token mint/transfer). Returns `none` when not Map. -/
private def mapUInt64LeafCountV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (_mapStaticKeys : Array UInt64) (typeId : TypeIdV1) :
    CompileResult (Option Nat) := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .map keyTid valTid, .. } =>
      unless keyTid == types.uint64TypeId && valTid == types.uint64TypeId do
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: Map state admits only Map UInt64 UInt64"
      pure (some evmMapPilotLeafCountV1)
  | _ => pure none

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]` (unrolled). -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == evmMapPilotLeafCountV1 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .literal 0
  let mut payload : Expr := .literal 0
  for e in [0:evmMapPilotCapacityV1] do
    let base := e * evmMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .evm "Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .evm "Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      throw <| .planInvariant .evm "Map lookup val leaf missing"
    let hit := Expr.checkedMul occ (Expr.compare .eq k key)
    let miss := Expr.boolNot hit
    found := Expr.logicalOr found hit
    payload :=
      Expr.checkedAdd (Expr.checkedMul hit v) (Expr.checkedMul miss payload)
  pure #[found, payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert) where okInsert is
    0/1 — caller must `assert okInsert` (map full when key absent). -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == evmMapPilotLeafCountV1 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .literal 0
  for e in [0:evmMapPilotCapacityV1] do
    let base := e * evmMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .evm "Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .evm "Map upsert key leaf missing"
    let hit := Expr.checkedMul occ (Expr.compare .eq k key)
    anyMatch := Expr.logicalOr anyMatch hit
  let mut seenEmpty : Expr := .literal 0
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:evmMapPilotCapacityV1] do
    let base := e * evmMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .evm "Map upsert empty-scan occ missing"
    let empty := Expr.boolNot occ
    let first := Expr.checkedMul empty (Expr.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := Expr.logicalOr seenEmpty empty
  let okInsert := Expr.logicalOr anyMatch seenEmpty
  let mut out : Array Expr := #[]
  for e in [0:evmMapPilotCapacityV1] do
    let base := e * evmMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      throw <| .planInvariant .evm "Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      throw <| .planInvariant .evm "Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      throw <| .planInvariant .evm "Map upsert rebuild val missing"
    let matchHit := Expr.checkedMul occ (Expr.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      throw <| .planInvariant .evm "Map upsert firstEmpty missing"
    let insertHere := Expr.checkedMul firstE (Expr.boolNot anyMatch)
    let write := Expr.logicalOr matchHit insertHere
    let miss := Expr.boolNot write
    let occ' := Expr.logicalOr occ write
    let k' :=
      Expr.checkedAdd (Expr.checkedMul write key) (Expr.checkedMul miss k)
    let v' :=
      Expr.checkedAdd (Expr.checkedMul write value) (Expr.checkedMul miss v)
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

/-- Insert `k` into a sorted unique UInt64 array (stable for layout). -/
private def insertSortedUniqueU64V1 (keys : Array UInt64) (k : UInt64) :
    Array UInt64 := Id.run do
  let mut out : Array UInt64 := #[]
  let mut inserted := false
  for x in keys do
    if !inserted && k < x then
      out := out.push k
      inserted := true
    if x == k then
      inserted := true
      out := out.push x
    else
      out := out.push x
  if !inserted then
    out := out.push k
  pure out

private def ensureOptionArrV1 {α : Type} (arr : Array (Option α)) (i : Nat) :
    Array (Option α) := Id.run do
  let mut a := arr
  while a.size <= i do
    a := a.push none
  pure a

/-- Collect program-wide sorted unique UInt64 keys used as Map IndexGet/IndexSet
    indices. Dynamic (non-literal) Map keys fail closed. Map shapes other than
    UInt64→UInt64 fail closed when indexed. -/
private def collectMapUInt64StaticKeysV1
    (typeDecls : Array TypeDeclV1) (types : EvmTypeClosureV1)
    (callables : Array CallableV1) : CompileResult (Array UInt64) := do
  let mut keys : Array UInt64 := #[]
  for callable in callables do
    let mut typesByVid : Array (Option TypeIdV1) := #[]
    let mut litByVid : Array (Option UInt64) := #[]
    for p in callable.params do
      typesByVid := ensureOptionArrV1 typesByVid p.valueId.toNat
      typesByVid := typesByVid.set! p.valueId.toNat (some p.typeId)
    for block in callable.blocks do
      for bp in block.params do
        typesByVid := ensureOptionArrV1 typesByVid bp.valueId.toNat
        typesByVid := typesByVid.set! bp.valueId.toNat (some bp.typeId)
      for instr in block.instructions do
        match instr.result with
        | none => pure ()
        | some vd =>
            typesByVid := ensureOptionArrV1 typesByVid vd.valueId.toNat
            typesByVid := typesByVid.set! vd.valueId.toNat (some vd.typeId)
            match instr.op with
            | .literal typeId bytes =>
                if typeId == types.uint64TypeId then
                  let v ← decodeUInt64LiteralLe evmPlanErr "EVM" bytes
                  litByVid := ensureOptionArrV1 litByVid vd.valueId.toNat
                  litByVid := litByVid.set! vd.valueId.toNat (some v)
            | _ => pure ()
    for block in callable.blocks do
      for instr in block.instructions do
        let idxPair? : Option (ValueIdV1 × ValueIdV1) :=
          match instr.op with
          | .indexGet baseId idxId => some (baseId, idxId)
          | .indexSet baseId idxId _ => some (baseId, idxId)
          | _ => none
        match idxPair? with
        | none => pure ()
        | some (baseId, idxId) => do
            let baseTid? :=
              match typesByVid[baseId.toNat]? with
              | some (some t) => some t
              | _ => none
            match baseTid? with
            | none => pure ()
            | some baseTid =>
                match typeDecls[baseTid.toNat]? with
                | some { shape := .map keyTid valTid, .. } => do
                    unless keyTid == types.uint64TypeId &&
                        valTid == types.uint64TypeId do
                      throw <| .planInvariant .evm
                        "unsupported EVM semantic shape: Map index admits only Map UInt64 UInt64"
                    -- Dense pilot admits dynamic keys (Token params). Literals
                    -- are still collected for diagnostics/layout hints only.
                    match litByVid[idxId.toNat]? with
                    | some (some k) =>
                        keys := insertSortedUniqueU64V1 keys k
                    | _ => pure ()
                | _ => pure ()
  pure keys

/-- Index of `k` in sorted `keys`, if any. -/
private def findMapStaticKeyIndexV1 (keys : Array UInt64) (k : UInt64) :
    Option Nat := Id.run do
  for i in [0:keys.size] do
    match keys[i]? with
    | some x => if x == k then return some i
    | none => pure ()
  none

/-- Detect a contiguous storage-backed Array aggregate (all leaves are
    `storageLoad`/`narrowStorageLoad` of consecutive slots with a uniform
    physical width). Returns `(baseSlot, length, byteWidth)`. -/
private def contiguousStorageLeavesV1 (leaves : Array Expr) :
    Option (Nat × Nat × Nat) := Id.run do
  if leaves.isEmpty then return none
  let some head := leaves[0]? | return none
  match head with
  | .storageLoad s0 =>
      let mut ok := true
      for i in [1:leaves.size] do
        match leaves[i]? with
        | some (.storageLoad s) =>
            unless s == s0 + i do ok := false
        | _ => ok := false
      if ok then some (s0, leaves.size, 8) else none
  | .narrowStorageLoad w s0 =>
      let mut ok := true
      for i in [1:leaves.size] do
        match leaves[i]? with
        | some (.narrowStorageLoad w' s) =>
            unless w' == w && s == s0 + i do ok := false
        | _ => ok := false
      if ok then some (s0, leaves.size, byteWidthOfBitWidth w) else none
  | _ => none

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
    (states : Array StateDeclV1)
    (mapStaticKeys : Array UInt64) : CompileResult EvmLowerLayoutV1 := do
  if states.size > maxStorageBindings then
    throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
  let mut bindings : Array StorageBinding := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      throw <| .planInvariant .evm "semantic state ids must match declaration order"
    unless isIdentifier state.name do
      throw <| .planInvariant .evm s!"state name '{state.name}' is not an EVM ABI identifier"
    match ← mapUInt64LeafCountV1 typeDecls types mapStaticKeys state.typeId with
    | some n =>
        -- Dense Map pilot: fixed 3×capacity occ/key/val leaves named `{state}_{i}`.
        requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedOrContainerState
          evmPlanErr types state (allowNonPublic := true)
        if bindings.size + n > maxStorageBindings then
          throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
        let mut leaves : Array Nat := #[]
        for i in [0:n] do
          let leafName := state.name ++ "_" ++ toString i
          unless isIdentifier leafName do
            throw <| .planInvariant .evm
              s!"state name '{leafName}' is not an EVM ABI identifier"
          let slot := bindings.size
          bindings := bindings.push {
            sourceId := slot
            name := leafName
            slot
            byteWidth := 8
          }
          leaves := leaves.push slot
        stateLeaves := stateLeaves.push leaves
    | none =>
        match ← arrayScalarLeafLayoutV1 typeDecls types state.typeId with
        | some (bitWidth, n) =>
            -- Array/Bytes state: N consecutive slots named `{state}_{i}`.
            requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedOrContainerState
              evmPlanErr types state (allowNonPublic := true)
            if bindings.size + n > maxStorageBindings then
              throw <| .planInvariant .evm s!"state count exceeds profile limit {maxStorageBindings}"
            let byteWidth := byteWidthOfBitWidth bitWidth
            let mut leaves : Array Nat := #[]
            for i in [0:n] do
              let leafName := state.name ++ "_" ++ toString i
              unless isIdentifier leafName do
                throw <| .planInvariant .evm
                  s!"state name '{leafName}' is not an EVM ABI identifier"
              let slot := bindings.size
              bindings := bindings.push {
                sourceId := slot
                name := leafName
                slot
                byteWidth
              }
              leaves := leaves.push slot
            stateLeaves := stateLeaves.push leaves
        | none =>
            if types.isNamedAggregate state.typeId || types.isString state.typeId ||
                types.isPrincipal state.typeId then
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
                  byteWidth := 8
                }
                leaves := leaves.push slot
              stateLeaves := stateLeaves.push leaves
            else
              requirePublicEvmUintAbiOrInt64OrFieldState evmPlanErr types state
                (allowNonPublic := true)
              let byteWidth ← abiByteWidthOfTypeV1 types state.typeId
              let slot := bindings.size
              bindings := bindings.push {
                sourceId := slot
                name := state.name
                slot
                byteWidth
              }
              stateLeaves := stateLeaves.push #[slot]
  pure { bindings, stateLeaves, typeDecls, mapStaticKeys }

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
    if types.isNamedAggregate param.typeId || types.isString param.typeId ||
        types.isPrincipal param.typeId then
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
      requirePublicEvmUintAbiOrInt64OrFieldParam
        evmPlanErr types owner param (allowNonPublic := true)
      let isInt := (types.intWidthOf param.typeId).isSome
      let isField := types.isField param.typeId
      let byteWidth ← abiByteWidthOfTypeV1 types param.typeId
      let bitWidth := if isField then 256 else bitWidthOfByteWidth byteWidth
      let binding : Param := {
        sourceId := nextWord
        name := param.name
        wordIndex := nextWord
        isInt
        byteWidth
      }
      planned := planned.push binding
      values := values.push {
        -- Field and UInt64/Int64 share `.param` (full ABI word); narrow UInt
        -- uses `narrowParam`. Field load range is full 256-bit (no UInt64 gate).
        expr := if isField then .param binding.wordIndex
          else mkParamExpr bitWidth binding.wordIndex
        depth := 1
        expandedNodes := 1
        dependencies := #[]
        isBool := false
        isInt
        isField
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

/-- Pack wire `u32le len || body` valueBytes into EVM pilot leaves: length word
    + `dataWordCount`×UInt64 data words (zero-padded). Shared by N4 String and
    T10 Principal (opaque body; String UTF-8 is already validated on wire). -/
private def decodeWireBytesLiteralLeavesV1
    (label : String) (maxPayload : Nat) (dataWordCount : Nat)
    (bytes : ByteArray) (minLen : Nat) : CompileResult (Array Expr) := do
  unless bytes.size ≥ 4 do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: {label} literal valueBytes too short"
  let len :=
    (bytes.get! 0).toNat + (bytes.get! 1).toNat * 256 +
      (bytes.get! 2).toNat * 65536 + (bytes.get! 3).toNat * 16777216
  unless bytes.size == 4 + len do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: {label} literal valueBytes length framing mismatch"
  unless minLen ≤ len do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: {label} body shorter than {minLen} bytes"
  unless len ≤ maxPayload do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: {label} longer than {maxPayload} bytes (EVM pilot bound)"
  let payload := bytes.extract 4 bytes.size
  let mut leaves : Array Expr := #[.literal (UInt64.ofNat len)]
  for w in [0:dataWordCount] do
    let mut word : Nat := 0
    let mut place : Nat := 1
    for b in [0:8] do
      let idx := w * 8 + b
      let byte := if idx < payload.size then (payload.get! idx).toNat else 0
      word := word + byte * place
      place := place * 256
    leaves := leaves.push (.literal (UInt64.ofNat word))
  pure leaves

/-- Pack wire String valueBytes (`u32le len || UTF-8`) into EVM pilot leaves:
    length word + 8×UInt64 data words (max 64 payload bytes; empty allowed). -/
private def decodeStringLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) :=
  decodeWireBytesLiteralLeavesV1 "String" evmStringMaxPayloadBytesV1
    evmStringDataWordCountV1 bytes 0

/-- Pack wire Principal valueBytes (`u32le len || body`, `1 ≤ len ≤ 4096` on
    wire) into EVM pilot leaves. Body longer than 64 fails closed. No source
    Principal literal — used if Semantic carries Op.Literal Principal. -/
private def decodePrincipalLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) :=
  decodeWireBytesLiteralLeavesV1 "Principal" evmPrincipalMaxPayloadBytesV1
    evmPrincipalDataWordCountV1 bytes 1

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
  unless isBool || resultIsInt || isEvmBodyUintWidth resultBitWidth do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: width {resultBitWidth} is not an admitted body width"
  -- Int admits Int8/16/32/64 (T9c); Int128/256 fail closed.
  unless isBool || !resultIsInt || isAbiIntWidth resultBitWidth do
    throw <| .planInvariant .evm
      s!"unsupported EVM semantic shape: Int{resultBitWidth} is not an admitted body Int width"
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

/-- Admit Int8/16/32/64 result TypeId and return `(typeId, bitWidth)`. -/
private def admitIntWidthResultTypeV1
    (types : EvmTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × Nat) := do
  match types.intWidthOf resultTypeId with
  | some w =>
      unless isPilotBodyIntWidth w do
        throw <| .planInvariant .evm
          s!"unsupported EVM semantic shape: signed arithmetic result Int{w} is not admitted"
      pure (resultTypeId, w)
  | none =>
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: signed arithmetic result must be admitted Int width"

/-- Backward-compatible Int64-only admit (pureFn historical paths). -/
private def admitInt64ResultTypeV1
    (types : EvmTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult TypeIdV1 := do
  let (tid, w) ← admitIntWidthResultTypeV1 types resultTypeId
  unless w == 64 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: signed arithmetic result must be Int64"
  pure tid

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

/-- Width-dispatch signed arithmetic: Int64 keeps historical constructors; narrow
    Int{8,16,32} use `narrowSigned*` so Plan digests for Int64 stay byte-identical. -/
private def mkSignedCheckedAdd (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedAdd l r else .narrowSignedCheckedAdd w l r
private def mkSignedCheckedSub (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedSub l r else .narrowSignedCheckedSub w l r
private def mkSignedCheckedMul (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedMul l r else .narrowSignedCheckedMul w l r
private def mkSignedCheckedDiv (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedDiv l r else .narrowSignedCheckedDiv w l r
private def mkSignedCheckedMod (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .signedCheckedMod l r else .narrowSignedCheckedMod w l r
private def mkSignedCompare (w : Nat) (op : ComparisonOp) (l r : Expr) : Expr :=
  if w == 64 then .signedCompare op l r else .narrowSignedCompare w op l r
private def mkCheckedNeg (w : Nat) (o : Expr) : Expr :=
  if w == 64 then .checkedNeg o else .narrowCheckedNeg w o
private def mkSar (w : Nat) (l r : Expr) : Expr :=
  if w == 64 then .sar l r else .narrowSar w l r

/-- Field binary tree cost (bn254 Fr). Operands must both be Field. -/
private def makeFieldBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.isField && rhs.isField && !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Field arithmetic operands must be Field"
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
    isInt := false
    isField := true
    bitWidth := 256
  }

private def makeFieldUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless operand.isField && !operand.isBool do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Field unary operand must be Field"
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
    isBool := false
    isInt := false
    isField := true
    bitWidth := 256
  }

private def makeCheckedAddValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isField || rhs.isField then
    makeFieldBinaryTreeValueV1 .fieldAdd lhsId rhsId lhs rhs
  else if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedAdd bitWidth) lhsId rhsId lhs rhs false bitWidth
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedAdd bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedSubValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isField || rhs.isField then
    makeFieldBinaryTreeValueV1 .fieldSub lhsId rhsId lhs rhs
  else if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedSub bitWidth) lhsId rhsId lhs rhs false bitWidth
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedSub bitWidth) lhsId rhsId lhs rhs false bitWidth

/-- Leaf-wise unsigned equality chain: `(((l0==r0) && (l1==r1)) && ...)`.
    Shared by aggregate `==`/`!=` and N-A1 String match-switch desugar. -/
private def makeLeafWiseEqExprV1 (lhs rhs : Array Expr) : CompileResult Expr := do
  unless lhs.size == rhs.size && lhs.size > 0 do
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: aggregate comparison leaf count mismatch"
  let mut acc : Expr := .compare .eq lhs[0]! rhs[0]!
  for i in [1:lhs.size] do
    acc := .logicalAnd acc (.compare .eq lhs[i]! rhs[i]!)
  pure acc

/-- Comparison: same-width UInt or Int64 operands → Bool; Field admits only
    `eq`/`ne`. N4: aggregate (String / named) operands only support `eq`/`ne`
    via leaf-wise unsigned equality AND/OR chain. -/
private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.isAggregate || rhs.isAggregate then
    unless lhs.isAggregate && rhs.isAggregate do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: aggregate comparison requires both operands aggregate"
    unless op == .eq || op == .ne do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: aggregate comparison only supports == / !="
    let le := lhs.leafExprs
    let re := rhs.leafExprs
    let acc ← makeLeafWiseEqExprV1 le re
    let expr := if op == .ne then .boolNot acc else acc
    pure {
      expr
      depth := max lhs.depth rhs.depth + le.size + 1
      expandedNodes := lhs.expandedNodes + rhs.expandedNodes + le.size + 1
      dependencies := (lhs.dependencies ++ rhs.dependencies).push lhsId |>.push rhsId
      isBool := true
      isInt := false
      isField := false
      bitWidth := 1
    }
  else if lhs.isField || rhs.isField then
    unless lhs.isField && rhs.isField do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: Field comparison requires both operands Field"
    unless op == .eq || op == .ne do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: Field admits only == / != (ordering fail closed)"
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
      isBool := true
      isInt := false
      isField := false
      bitWidth := 1
    }
  else do
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
      unless isPilotBodyIntWidth lhs.bitWidth do
        throw <| .planInvariant .evm
          s!"unsupported EVM semantic shape: Int{lhs.bitWidth} comparison is not admitted"
      makeBinaryTreeValueV1 (mkSignedCompare lhs.bitWidth op) lhsId rhsId lhs rhs true 1
    else
      makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true 1

private def makeCheckedMulValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isField || rhs.isField then
    makeFieldBinaryTreeValueV1 .fieldMul lhsId rhsId lhs rhs
  else if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedMul bitWidth) lhsId rhsId lhs rhs false bitWidth
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedMul bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedDivValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isField || rhs.isField then
    makeFieldBinaryTreeValueV1 .fieldDiv lhsId rhsId lhs rhs
  else if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedDiv bitWidth) lhsId rhsId lhs rhs false bitWidth
      (resultIsInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedDiv bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedModValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.isField || rhs.isField then
    throw <| .planInvariant .evm
      "unsupported EVM semantic shape: Field does not support mod (remainder)"
  else if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedMod bitWidth) lhsId rhsId lhs rhs false bitWidth
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
    -- Arithmetic right shift for Int8/16/32/64; count ≥ bitWidth → invalidShift.
    unless isPilotBodyIntWidth bitWidth do
      throw <| .planInvariant .evm
        s!"unsupported EVM semantic shape: Int{bitWidth} arithmetic shift is not admitted"
    let v ← makeShiftTreeValueV1 (mkSar bitWidth) bitWidth lhsId rhsId lhs rhs
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
  if operand.isField then
    makeFieldUnaryTreeValueV1 .fieldNeg operandId operand
  else do
    unless operand.isInt && !operand.isBool && isPilotBodyIntWidth operand.bitWidth do
      throw <| .planInvariant .evm
        "unsupported EVM semantic shape: checkedNeg requires admitted Int width or Field operand"
    makeUnaryTreeValueV1 (mkCheckedNeg operand.bitWidth) operandId operand false false operand.bitWidth

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
            unless isEvmBodyUintWidth bitWidth do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: UInt{bitWidth} literal is not admitted"
            let n ← decodeUIntWideLiteralLe evmPlanErr "EVM" bitWidth bytes
            let expr : Expr :=
              if bitWidth ≤ 64 then .literal (UInt64.ofNat n) else .bigLiteral n
            values := ← appendResultValueV1 typeId values result {
              expr
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isInt := false
              bitWidth
            }
        | none =>
            match types.intWidthOf typeId with
            | some bitWidth => do
                unless isPilotBodyIntWidth bitWidth do
                  throw <| .planInvariant .evm
                    s!"unsupported EVM semantic shape: Int{bitWidth} literal is not admitted"
                let value ← decodeIntWidthLiteralLe evmPlanErr "EVM" bitWidth bytes
                values := ← appendResultValueV1 typeId values result {
                  expr := .literal value
                  depth := 1
                  expandedNodes := 1
                  dependencies := #[]
                  isBool := false
                  isInt := true
                  bitWidth
                }
            | none => do
                let boolTid ← match types.boolTypeId with
                  | some tid => pure tid
                  | none => throw (.planInvariant .evm
                      "unsupported EVM semantic shape: Bool literal requires anonymous Bool type")
                if types.isString typeId then
                  let leafExprs ← decodeStringLiteralLeavesV1 bytes
                  let leafIsInt := leafExprs.map (fun _ => false)
                  let value := mkAggregateValueV1 leafExprs leafIsInt #[] 1 leafExprs.size
                  values := ← appendResultValueV1 typeId values result value
                else if types.isPrincipal typeId then
                  let leafExprs ← decodePrincipalLiteralLeavesV1 bytes
                  let leafIsInt := leafExprs.map (fun _ => false)
                  let value := mkAggregateValueV1 leafExprs leafIsInt #[] 1 leafExprs.size
                  values := ← appendResultValueV1 typeId values result value
                else do
                  unless typeId == boolTid do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: literal is not admitted UInt/Int64/Bool/String/Principal"
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
        if types.isContainer result.typeId then
          -- Array/Bytes multi-leaf load OR I1 Map present+value leaves.
          let bitWidth ← match ← mapUInt64LeafCountV1 layout.typeDecls types
              layout.mapStaticKeys result.typeId with
            | some n =>
                unless leaves.size == n do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: Map state load leaf count mismatch"
                pure 64
            | none =>
                let layoutInfo ← arrayScalarLeafLayoutV1 layout.typeDecls types result.typeId
                match layoutInfo with
                | some (bw, n) =>
                    unless leaves.size == n do
                      throw <| .planInvariant .evm
                        "unsupported EVM semantic shape: Array state load leaf count mismatch"
                    pure bw
                | none =>
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: container state load is not Array/Map/Bytes"
          let mut leafExprs : Array Expr := #[]
          let mut leafIsInt : Array Bool := #[]
          for i in [0:leaves.size] do
            let some slot := leaves[i]? |
              throw <| .planInvariant .evm "container state load slot missing"
            leafExprs := leafExprs.push (mkStorageLoadExpr bitWidth slot)
            leafIsInt := leafIsInt.push false
          let value := mkAggregateValueV1 leafExprs leafIsInt #[] 1 leaves.size
          values := ← appendResultValueV1 result.typeId values result value
        else if types.isNamedAggregate result.typeId || types.isString result.typeId ||
            types.isPrincipal result.typeId then
          -- N3/N4/T10 aggregate load; per-leaf isInt restored from the flatten
          -- specs (base N3 lowering marked every leaf UInt64, losing Int64 flags).
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
          let intW := types.intWidthOf result.typeId
          let isInt := intW.isSome
          let isField := types.isField result.typeId
          if isField then
            unless binding.byteWidth == 32 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Field state load requires 32-byte slot"
            values := ← appendResultValueV1 result.typeId values result {
              expr := .fieldStorageLoad binding.slot
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isInt := false
              isField := true
              bitWidth := 256
            }
          else if let some bitWidth := intW then
            unless binding.byteWidth == byteWidthOfBitWidth bitWidth do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: Int{bitWidth} state load requires {byteWidthOfBitWidth bitWidth}-byte slot"
            values := ← appendResultValueV1 result.typeId values result {
              expr := mkStorageLoadExpr bitWidth binding.slot
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isInt := true
              bitWidth
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
                  "unsupported EVM semantic shape: state load result must be UInt8/16/32/64, Int64, or Field"
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values paramCount segmentStart armReadables rhsId
        if op == .add then
          if types.isField result.typeId then
            let value ← makeCheckedAddValueV1 256 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 result.typeId values result value
          else if let some bitWidth := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedAddValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedAddValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .sub then
          if types.isField result.typeId then
            let value ← makeCheckedSubValueV1 256 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 result.typeId values result value
          else if let some bitWidth := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedSubValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedSubValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .mul then
          if types.isField result.typeId then
            let value ← makeCheckedMulValueV1 256 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 result.typeId values result value
          else if let some bitWidth := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedMulValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedMulValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .div then
          if types.isField result.typeId then
            let value ← makeCheckedDivValueV1 256 lhsId rhsId lhs rhs
            values := ← appendResultValueV1 result.typeId values result value
          else if let some bitWidth := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedDivValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedDivValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .mod then
          if types.isField result.typeId || lhs.isField || rhs.isField then
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: Field does not support mod (remainder)"
          else if let some bitWidth := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedModValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeCheckedModValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .bitAnd then
          -- Bitwise is bit-pattern identical for Int64 two's complement.
          if let some _ := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeBitAndValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitAndValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .bitOr then
          if let some _ := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeBitOrValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitOrValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .bitXor then
          if let some _ := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeBitXorValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeBitXorValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .shl then
          if let some _ := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeShlValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 tid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            let value ← makeShlValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else if op == .shr then
          if let some _ := types.intWidthOf result.typeId then
            let (tid, w) ← admitIntWidthResultTypeV1 types result.typeId
            let value ← makeShrValueV1 w lhsId rhsId lhs rhs
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
            -- Int64: Op.Unary.neg (intMin reverts). Field: fieldNeg (p - a).
            -- UInt still arrives as 0-x.
            if types.isField result.typeId then
              unless types.fieldTypeId == some result.typeId do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: fieldNeg result must be Field"
              let value ← makeCheckedNegValueV1 operandId operand
              values := ← appendResultValueV1 result.typeId values result value
            else
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
            -- N3 named leaves are 64-bit; ArrayState leaves use layout byteWidth.
            let byteWidth :=
              match layout.bindings[slot]? with
              | some b => b.byteWidth
              | none => 8
            body := body.push (.store { slot, value := expr, byteWidth })
        else
          unless leaves.size == 1 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: scalar store targets multi-leaf state"
          let binding ← findStorageV1 layout stateId
          if stored.isField then
            unless binding.byteWidth == 32 && stored.bitWidth == 256 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Field state store requires 32-byte slot"
            unless !stored.isBool && !stored.isInt do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Field state store kind conflict"
          else
            let expectedBitWidth := bitWidthOfByteWidth binding.byteWidth
            unless !stored.isBool && stored.bitWidth == expectedBitWidth do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: state store value width {stored.bitWidth} must match storage bitWidth {expectedBitWidth}"
            unless stored.isInt || isEvmAbiUintWidth stored.bitWidth do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: state store value must be admitted UInt/Int width or Field"
            unless !stored.isInt || isAbiIntWidth stored.bitWidth do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Int state store requires admitted Int8/16/32/64 width"
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
    -- AddressBearing: static QualifiedName callees (wire Op.ExternalCall/
    -- Schedule take QN, not a ValueId address). T10 admits Principal storage
    -- only — CALL target is never a Principal ValueId (wire ≠ 20-byte address).
    -- View/pureFn banned.
    | .externalCall _effectId callee argIds, none =>
        if mode == .view then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: view callable makes an external call"
        if mode == .pureFn then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: pureFn cannot make external calls"
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: external call callee must have at least two components"
        for c in components do
          unless isIdentifier c do
            throw <| .planInvariant .evm
              s!"unsupported EVM semantic shape: external call callee component '{c}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless !root.isBool && root.bitWidth == 64 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: external call arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart argIds
        body := body.push (.externalCall components argExprs)
        hasAssert := true
        segmentStart := values.size
    | .schedule _effectId callee argIds, none =>
        if mode == .view then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: view callable schedules a workflow"
        if mode == .pureFn then
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: pureFn cannot schedule workflows"
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: schedule callee must have at least two components"
        for c in components do
          unless isIdentifier c do
            throw <| .planInvariant .evm
              s!"unsupported EVM semantic shape: schedule callee component '{c}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
          unless !root.isBool && root.bitWidth == 64 do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: schedule arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values paramCount segmentStart argIds
        body := body.push (.schedule components argExprs)
        hasAssert := true
        segmentStart := values.size
    | .construct typeId ctorIdx argIds, some result => do
        unless result.typeId == typeId do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: construct result typeId must match op typeId"
        if types.isContainer typeId then
          match ← mapUInt64LeafCountV1 layout.typeDecls types layout.mapStaticKeys typeId with
          | some n =>
              -- I1: Map.empty only (ctor 0, no args) → 2N zero present+value leaves.
              unless ctorIdx == 0 do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: Map construct ctorIdx must be 0 (Map.empty)"
              unless argIds.isEmpty do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: Map construct admits only empty Map.empty"
              let mut leafExprs : Array Expr := #[]
              let mut leafIsInt : Array Bool := #[]
              for _ in [0:n] do
                leafExprs := leafExprs.push (.literal 0)
                leafIsInt := leafIsInt.push false
              let value := mkAggregateValueV1 leafExprs leafIsInt #[] 1 (n + 1)
              values := ← appendResultValueV1 typeId values result value
          | none =>
              -- ArrayState: construct fixed Array UInt{w} N from N scalar args.
              let (elBitWidth, n) ← match ← arrayScalarLeafLayoutV1 layout.typeDecls types typeId with
                | some p => pure p
                | none =>
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: construct admits only fixed Array/Map on EVM"
              unless ctorIdx == 0 do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: Array construct ctorIdx must be 0"
              unless argIds.size == n do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              let mut leafIsInt : Array Bool := #[]
              let mut deps : Array ValueIdV1 := #[]
              let mut depth : Nat := 1
              let mut nodes : Nat := 0
              for argId in argIds do
                let arg ← currentValueWithArmsV1 values paramCount segmentStart armReadables argId
                unless !arg.isBool && !arg.isInt && !arg.isField && !arg.isAggregate &&
                    arg.bitWidth == elBitWidth do
                  throw <| .planInvariant .evm
                    s!"unsupported EVM semantic shape: Array construct args must be scalar UInt{elBitWidth}"
                leafExprs := leafExprs.push arg.expr
                leafIsInt := leafIsInt.push false
                deps := deps.push argId
                depth := Nat.max depth (arg.depth + 1)
                nodes := nodes + arg.expandedNodes
              let value := mkAggregateValueV1 leafExprs leafIsInt deps depth (nodes + n)
              values := ← appendResultValueV1 typeId values result value
        else
          unless types.isNamedAggregate typeId do
            throw <| .planInvariant .evm
              "unsupported EVM semantic shape: construct requires named Struct/Enum or Array"
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
            "unsupported EVM semantic shape: variantTag base must be an aggregate (Enum or Option)"
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
              -- I1: Option intermediate from Map IndexGet is a 2-leaf aggregate
              -- (tag=present, payload=value). Option.some = variantIndex 1.
              if variantIndex.toNat == 1 && payloadIndex.toNat == 0 &&
                  base.leafExprs.size >= 2 then
                pure (1, 1)
              else if variantIndex.toNat == 0 then
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: variantPayload of Option.none is empty"
              else
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
    | .indexGet baseId idxId, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: IndexGet base must be an Array/Map aggregate"
        let idx ← currentValueWithArmsV1 values paramCount segmentStart armReadables idxId
        unless !idx.isBool && !idx.isInt && !idx.isField && !idx.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: IndexGet index must be unsigned integer"
        -- I1 Map IndexGet: result is Option V (not scalar UInt) → 2-leaf aggregate.
        -- Array/Bytes IndexGet: result is scalar UInt element.
        match types.uintWidthOf result.typeId with
        | none =>
            -- Map → Option path (dense pilot table; dynamic keys OK).
            unless base.leafExprs.size == evmMapPilotLeafCountV1 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Map IndexGet base leaf count mismatch"
            let optLeaves ← mapLookupOptionLeavesV1 base.leafExprs idx.expr
            let value := mkAggregateValueV1
              optLeaves #[false, false] #[baseId, idxId]
              (Nat.max base.depth idx.depth + 1)
              (base.expandedNodes + idx.expandedNodes + 1)
            values := ← appendResultValueV1 result.typeId values result value
        | some elBitWidth =>
            unless isEvmAbiUintWidth elBitWidth do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: Array IndexGet result UInt{elBitWidth} is not admitted"
            let leaves := base.leafExprs
            let valueExpr ← match idx.expr with
              | .literal n =>
                  let i := n.toNat
                  unless i < leaves.size do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: Array IndexGet index out of range"
                  match leaves[i]? with
                  | some leaf => pure leaf
                  | none =>
                      throw <| .planInvariant .evm "Array IndexGet leaf missing"
              | _ =>
                  match contiguousStorageLeavesV1 leaves with
                  | some (baseSlot, length, byteWidth) =>
                      pure (.indexedStorageLoad baseSlot length idx.expr byteWidth)
                  | none =>
                      pure (.arrayIndexGet idx.expr leaves)
            values := ← appendResultValueV1 result.typeId values result {
              expr := valueExpr
              depth := Nat.max base.depth idx.depth + 1
              expandedNodes := base.expandedNodes + idx.expandedNodes + 1
              dependencies := #[baseId, idxId]
              isBool := false
              isInt := false
              isField := false
              bitWidth := elBitWidth
            }
    | .indexSet baseId idxId valueId, some result => do
        let base ← currentValueWithArmsV1 values paramCount segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: IndexSet base must be an Array/Map aggregate"
        unless types.isContainer result.typeId do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: IndexSet result must be Array/Map container"
        let idx ← currentValueWithArmsV1 values paramCount segmentStart armReadables idxId
        unless !idx.isBool && !idx.isInt && !idx.isField && !idx.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: IndexSet index must be unsigned integer"
        let val ← currentValueWithArmsV1 values paramCount segmentStart armReadables valueId
        unless !val.isBool && !val.isInt && !val.isField && !val.isAggregate do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: IndexSet value must be scalar UInt"
        match ← mapUInt64LeafCountV1 layout.typeDecls types layout.mapStaticKeys result.typeId with
        | some n =>
            -- Dense Map IndexSet: dynamic key upsert; assert not full.
            unless base.leafExprs.size == n do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Map IndexSet base leaf count mismatch"
            unless val.bitWidth == 64 do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Map IndexSet value must be UInt64"
            let (outLeaves0, okInsert) ←
              mapUpsertLeavesV1 base.leafExprs idx.expr val.expr
            -- Fail closed when map is full: `1 / okInsert` reverts on 0 without
            -- introducing an effect-boundary assert mid-value segment.
            let gate := Expr.checkedDiv (.literal 1) okInsert
            let mut outLeaves : Array Expr := #[]
            let mut outIsInt : Array Bool := #[]
            for i in [0:outLeaves0.size] do
              let some e := outLeaves0[i]? |
                throw <| .planInvariant .evm "Map IndexSet leaf missing after upsert"
              -- Touch every leaf with gate so the div0 is reachable.
              outLeaves := outLeaves.push
                (Expr.checkedAdd e (Expr.checkedMul gate (.literal 0)))
              outIsInt := outIsInt.push false
            let value := mkAggregateValueV1 outLeaves outIsInt
              #[baseId, idxId, valueId]
              (Nat.max (Nat.max base.depth idx.depth) val.depth + 1)
              (base.expandedNodes + idx.expandedNodes + val.expandedNodes + 1)
            values := ← appendResultValueV1 result.typeId values result value
        | none => do
            let layoutInfo ← arrayScalarLeafLayoutV1 layout.typeDecls types result.typeId
            let (elBitWidth, n) ← match layoutInfo with
              | some p => pure p
              | none =>
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: IndexSet result is not Array UInt"
            unless base.leafExprs.size == n do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: Array IndexSet base leaf count mismatch"
            unless val.bitWidth == elBitWidth do
              throw <| .planInvariant .evm
                s!"unsupported EVM semantic shape: Array IndexSet value width {val.bitWidth} must match element UInt{elBitWidth}"
            let leaves := base.leafExprs
            let mut outLeaves : Array Expr := #[]
            let mut outIsInt : Array Bool := #[]
            match idx.expr with
            | .literal lit =>
                let i := lit.toNat
                unless i < leaves.size do
                  throw <| .planInvariant .evm
                    "unsupported EVM semantic shape: Array IndexSet index out of range"
                for j in [0:leaves.size] do
                  if j == i then
                    outLeaves := outLeaves.push val.expr
                  else
                    let some e := leaves[j]? |
                      throw <| .planInvariant .evm "Array IndexSet leaf missing"
                    outLeaves := outLeaves.push e
                  outIsInt := outIsInt.push false
            | _ =>
                -- Runtime index: bounds-check once, then rebind every leaf via
                -- arithmetic select `eq(idx,j) ? value : base[j]`.
                let guarded := Expr.boundsCheckedIndex idx.expr leaves.size
                for j in [0:leaves.size] do
                  let some baseLeaf := leaves[j]? |
                    throw <| .planInvariant .evm "Array IndexSet leaf missing"
                  let jLit := Expr.literal (UInt64.ofNat j)
                  let isHit := Expr.compare .eq guarded jLit
                  let isMiss := Expr.boolNot isHit
                  let chosen :=
                    Expr.checkedAdd
                      (Expr.checkedMul isHit val.expr)
                      (Expr.checkedMul isMiss baseLeaf)
                  outLeaves := outLeaves.push chosen
                  outIsInt := outIsInt.push false
            let value := mkAggregateValueV1 outLeaves outIsInt #[baseId, idxId, valueId]
              (Nat.max (Nat.max base.depth idx.depth) val.depth + 1)
              (base.expandedNodes + idx.expandedNodes + val.expandedNodes + 1)
            values := ← appendResultValueV1 result.typeId values result value
    -- N5: Op.Commit is label-only identity — reuse the operand's Plan value
    -- (no new Expr tag; PlanSchema/ValidatePlan stay frozen). Cryptographic
    -- commitment realization is a later capability.
    | .commit valueId, some result => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          throw <| .planInvariant .evm
            "unsupported EVM semantic shape: Commit is not admitted by pilot context policy"
        let operand ← findValueV1 values valueId
        -- Wire gate already enforces result.typeId == type(operand); bind the
        -- same Plan surface under the result ValueId (identity passthrough).
        values := ← appendResultValueV1 result.typeId values result {
          expr := operand.expr
          depth := operand.depth + 1
          expandedNodes := operand.expandedNodes + 1
          dependencies := operand.dependencies.push valueId
          isBool := operand.isBool
          isInt := operand.isInt
          bitWidth := operand.bitWidth
          aggregateLeaves := operand.aggregateLeaves
          aggregateLeafIsInt := operand.aggregateLeafIsInt
        }
    | .contextRead key, some _ =>
        -- N5: sole wire key would map to Yul `timestamp()`, but PlanSchema/
        -- ValidatePlan are frozen against new Expr tags in this slice.
        unless key == unixTimeSecondsContextKeyV1 do
          throw <| .planInvariant .evm
            s!"unsupported EVM semantic shape: unknown ContextRead key '{key.value}'"
        throw <| .planInvariant .evm
          "unsupported EVM semantic shape: ContextRead (unix-time-seconds) is not admitted by pilot context policy (PlanSchema frozen; Yul timestamp deferred)"
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
                  unless !returned.isBool && !returned.isInt && !returned.isField &&
                      returned.bitWidth == 64 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt64"
              | .uint32 =>
                  unless !returned.isBool && !returned.isInt && !returned.isField &&
                      returned.bitWidth == 32 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt32"
              | .uint16 =>
                  unless !returned.isBool && !returned.isInt && !returned.isField &&
                      returned.bitWidth == 16 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt16"
              | .uint8 =>
                  unless !returned.isBool && !returned.isInt && !returned.isField &&
                      returned.bitWidth == 8 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt8"
              | .uint128 =>
                  unless !returned.isBool && !returned.isInt && !returned.isField &&
                      returned.bitWidth == 128 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt128"
              | .uint256 =>
                  unless !returned.isBool && !returned.isInt && !returned.isField &&
                      returned.bitWidth == 256 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be UInt256"
              | .int64 =>
                  unless !returned.isBool && returned.isInt && !returned.isField &&
                      returned.bitWidth == 64 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Int64"
              | .int32 =>
                  unless !returned.isBool && returned.isInt && !returned.isField &&
                      returned.bitWidth == 32 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Int32"
              | .int16 =>
                  unless !returned.isBool && returned.isInt && !returned.isField &&
                      returned.bitWidth == 16 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Int16"
              | .int8 =>
                  unless !returned.isBool && returned.isInt && !returned.isField &&
                      returned.bitWidth == 8 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Int8"
              | .bool =>
                  unless returned.isBool do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Bool"
              | .field =>
                  unless !returned.isBool && !returned.isInt && returned.isField &&
                      returned.bitWidth == 256 do
                    throw <| .planInvariant .evm
                      "unsupported EVM semantic shape: return value must be Field"
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
          let some defaultT := defaultTarget |
            throw (.planInvariant .evm
              "unsupported EVM semantic shape: switch must carry a default target")
          if scrutVal.isAggregate then
            -- N-A1: String match-switch desugars to leaf-wise eq + nested if chains
            -- (Plan `switchOn` is UInt64-case only). Named/non-String aggregates
            -- fail closed: only the EVM pilot String leaf layout is admitted.
            let expectedStringLeaves := 1 + evmStringDataWordCountV1
            let scrutLeaves := scrutVal.leafExprs
            unless scrutLeaves.size == expectedStringLeaves do
              throw <| .planInvariant .evm
                "unsupported EVM semantic shape: switch on non-String aggregate is outside the EVM pilot"
            let _ ← consumeCurrentSegmentWithArmsV1
              values paramCount segmentStart armReadables scrutId
            let mut caseArms : Array (Expr × Array Statement) := #[]
            let mut joinAcc : Option Nat := none
            let mut valuesA := values
            let mut hAAcc := hA
            for switchCase in cases do
              let caseLeaves ← decodeStringLiteralLeavesV1 switchCase.valueBytes
              unless caseLeaves.size == scrutLeaves.size do
                throw <| .planInvariant .evm
                  "unsupported EVM semantic shape: String match case leaf count mismatch"
              let cond ← makeLeafWiseEqExprV1 scrutLeaves caseLeaves
              let (body, values1, armCont, hA1, _) ←
                emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                  paramCount expectedResultKind (fuel - 1)
                  (.region (armReadables.push scrutId) activeLoopHeader
                    switchCase.target.blockId.toNat valuesA)
              caseArms := caseArms.push (cond, body)
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
            -- First-match nesting: if c0 then body0 else (if c1 then body1 else default)
            let mut nested : Array Statement := defaultBody
            let mut i := caseArms.size
            while i > 0 do
              i := i - 1
              let (cond, body) := caseArms[i]!
              nested := #[.ifThenElse cond body nested]
            match joinAcc with
            | none =>
                pure (instrs ++ nested, values2, .done, hAAcc, true)
            | some j =>
                let (rest, values3, next, hA3, _) ←
                  emitJobV1 owner mode types layout fnIndexByCallableId fns blocks loopBounds
                    paramCount expectedResultKind (fuel - 1)
                    (.region armReadables activeLoopHeader j values2)
                pure (instrs ++ nested ++ rest, values3, next, hAAcc || hA3, true)
          else
            let scrut ← consumeCurrentSegmentWithArmsV1
              values paramCount segmentStart armReadables scrutId
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
  -- Semantic ValueId boundary for params (NOT ABI word count). N4 String / T10
  -- Principal expand one Semantic param into many ABI words (`params.size`),
  -- but `values` still holds one LoweredValueV1 per Semantic ValueId. Using
  -- `params.size` here mis-classifies stateLoad/compare results as "free params"
  -- and trips dead/reordered segment consumption on `state == param` paths.
  let paramCount := initialValues.size
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
      s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int8/16/32/64, Bool, or Field"
  let resultKind : ResultKind ←
    match types.uintWidthOf callable.result.typeId with
    | some 8 => pure .uint8
    | some 16 => pure .uint16
    | some 32 => pure .uint32
    | some 64 => pure .uint64
    | some 128 => pure .uint128
    | some 256 => pure .uint256
    | some _ =>
        throw <| .planInvariant .evm
          s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int8/16/32/64, Bool, or Field"
    | none =>
        match types.intWidthOf callable.result.typeId with
        | some 8 => pure .int8
        | some 16 => pure .int16
        | some 32 => pure .int32
        | some 64 => pure .int64
        | some w =>
            throw <| .planInvariant .evm
              s!"entry '{name}' does not return public Int{w} (only Int8/16/32/64)"
        | none =>
          if types.boolTypeId == some callable.result.typeId then
            pure .bool
          else if types.isField callable.result.typeId then
            pure .field
          else
            throw <| .planInvariant .evm
              s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int8/16/32/64, Bool, or Field"
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
    else
      match types.intWidthOf callable.result.typeId with
      | some 8 => pure (false, true, .int8)
      | some 16 => pure (false, true, .int16)
      | some 32 => pure (false, true, .int32)
      | some 64 => pure (false, true, .int64)
      | some _ =>
          throw <| .planInvariant .evm
            s!"fn '{name}' does not return public UInt64, Int8/16/32/64, or Bool"
      | none =>
        if types.boolTypeId == some callable.result.typeId then
          pure (true, false, .bool)
        else
          throw <| .planInvariant .evm
            s!"fn '{name}' does not return public UInt64, Int8/16/32/64, or Bool"
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
  let mapStaticKeys ←
    collectMapUInt64StaticKeysV1 source.types types source.callables
  let storageLayout ←
    makeStorageLayoutV1 types source.types source.logicalState mapStaticKeys
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
            s!"fn '{name}' does not return public UInt64, Int8/16/32/64, or Bool"
        let (resultIsBool, resultIsInt) : Bool × Bool ←
          if callable.result.typeId == types.uint64TypeId then
            pure (false, false)
          else if (types.intWidthOf callable.result.typeId).isSome then
            pure (false, true)
          else if types.boolTypeId == some callable.result.typeId then
            pure (true, false)
          else
            throw <| .planInvariant .evm
              s!"fn '{name}' does not return public UInt64, Int8/16/32/64, or Bool"
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
