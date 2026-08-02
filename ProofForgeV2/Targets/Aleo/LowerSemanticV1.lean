import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Aleo LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Aleo-owned Plan surface and the retained-`SemanticProgramV1` Plan body.
Plan canonicity lives in `ValidatePlanV1`; Leo emission in `EmitIRV1`.
`FinalizeV1` remains a separate submodule.

## Coverage boundary (AleoCoverage + H3 PsyAleoAggregate + NS-1 Map pilot + Bytes N)

LOWERED (product path): scalar stateLoad/stateStore (UInt64, Int64),
checked arithmetic/compare/bitwise/shift/logical (signed for Int64),
unary not/bitNot/neg (Int64), pureCall, bare assert, bare revert
(`assert(false)`), if/switch/for, Commit identity passthrough (label-only;
no crypto commitment realization), **named Struct/Enum and fixed Array
UInt64 N** via flatten-to-mapping leaves (`name_field` / `name_i` →
consecutive `pf_state_*` mappings), **dense Map UInt64 UInt64**
(NS-1 occ/key/val pilot, **capacity 2** — see `aleoMapPilotCapacityV1`:
Leo 4.0.2 caps a final block at 32 mapping sets statically across all
arms, ECMP0376015, so the shipped Token mint/transfer fits only at
capacity 2; `ValidatePlanV1` enforces the set budget fail-closed), and
**fixed Bytes N** (N×`u8 => u8` mappings; u8 params/results; checked u8
arithmetic = widen → u64 op → checked `as u8` narrow, spike-verified
255-ok/256-revert boundary).

FAIL-CLOSED (explicit pins, not catch-all GAP):
  * **Field (bn254 Fr)** — research pin: Aleo native `field` is the BLS12-377
    scalar field (Edwards BLS Fr = BLS12-377 Fr), **not** catalog bn254 Fr.
    Mapping would be a silent wrong modulus. Keep `pilotFieldPolicyNone`.
  * **Option-state/String/Principal state** — outside the Array/Map/Bytes
    container pilot; UInt8 scalar state/params (outside the Bytes element
    lane) and UInt16/128/256 stay fail-closed.
  * **Computed state-reading views** — only bare public-state reads map to
    the off-chain `leo query` model; `balanceOf`-style match-on-state views
    fail closed.
  * **Map shapes other than Map UInt64 UInt64** — declined at type closure.
  * **ContextRead** — no host clock ABI in Leo 4.0.2 Final model for this pilot.
  * **emit / externalCall / schedule / revert-with-args** — no Leo analogue
    (resolver also declines event/sync/async requirement keys).
  * Array IndexGet/IndexSet require compile-time UInt literal index.
  * Int64 for-loop endpoints (shared Normalize retains them; this Aleo profile
    has no signed range surface) / Int64 match scrutinees.
  * Leo final-block mapping-set budget > 32 (ECMP0376015) — plan-time
    fail-closed, including the dense-Map upsert expansion.
-/

namespace ProofForgeV2.Targets.Aleo

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Engineering codegen profile for the Leo 4.0.2 source slice. Any change to
    the supported surface or the Leo toolchain requires a new profile. -/
def codegenProfile : CodegenProfileId := CodegenProfileId.aleoLeoU64V1

/-- Locked Leo toolchain version string (source-only; no approved digest-pinned
    `leo` binary is configured, mirroring the Noir zero-tool finalization). -/
def leoToolchain : String := "4.0.2"

/-- Engineering descriptor (shared DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.aleo

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

/-- T14 catalog v2 (BLS12-377): native Leo `field` arithmetic operator.
    Leo `field` is a field element, so each op is exact mod BLS12-377 Fr. -/
inductive FieldArithOp where
  | add | sub | mul | div
  deriving BEq, Inhabited, Repr

/-- Target-owned Aleo Plan expression over the shipped public
    UInt64/Int64/Bool semantic envelope. UInt32 shift counts are promoted to
    UInt64 values with an explicit `count < 64` guard at emission. Int64 uses
    dedicated signed constructors; Leo's native `i64` type is type-directed so
    the emitter renders `i64` bindings/literals for them. -/
inductive Expr where
  | literal (value : UInt64)
  /-- Raw Int64 bit pattern (two's complement); Leo `i64` literal. -/
  | i64Literal (value : UInt64)
  /-- UInt8 literal (0..255); Leo `u8` literal (Bytes element lane). -/
  | u8Literal (value : UInt64)
  | boolLiteral (value : Bool)
  | param (inputIndex : Nat)
  /-- The induction value of the enclosing bounded `for` at loop stack depth
      `loopDepth` (0 = outermost). -/
  | loopVar (loopDepth : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- UInt8 → u64 widening (`as u64`; always in range). -/
  | u8To64 (operand : Expr)
  /-- Range-guarded UInt8 result: assert(value ≤ 255) then `as u8`
      (Bytes element lane; wire UInt8 arithmetic is checked). -/
  | narrow8 (value : Expr)
  /-- UInt8 << / >> with an explicit `count < 8` guard at emission
      (wire invalidShift at count ≥ 8) plus the ≤ 255 overflow guard. -/
  | u8Shl (lhs rhs : Expr)
  | u8Shr (lhs rhs : Expr)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | signedCheckedAdd (lhs rhs : Expr)
  | signedCheckedSub (lhs rhs : Expr)
  | signedCheckedMul (lhs rhs : Expr)
  | signedCheckedDiv (lhs rhs : Expr)
  | signedCheckedMod (lhs rhs : Expr)
  /-- Signed Int64 comparison (Leo `i64` native signed comparison). -/
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  | bitAnd (lhs rhs : Expr)
  | bitOr (lhs rhs : Expr)
  | bitXor (lhs rhs : Expr)
  /-- Int64 bitwise ops (same Leo operators; bindings render as `i64`). -/
  | signedBitAnd (lhs rhs : Expr)
  | signedBitOr (lhs rhs : Expr)
  | signedBitXor (lhs rhs : Expr)
  /-- Strict Bool and/or: both sides are evaluated (no short circuit). -/
  | logicalAnd (lhs rhs : Expr)
  | logicalOr (lhs rhs : Expr)
  /-- UInt64 << / >> with an explicit count < 64 guard at emission. -/
  | shl (lhs rhs : Expr)
  | shr (lhs rhs : Expr)
  /-- Int64 << / >> with an explicit count < 64 guard at emission. -/
  | signedShl (lhs rhs : Expr)
  | signedShr (lhs rhs : Expr)
  | bitNot (operand : Expr)
  /-- Int64 bitwise not (Leo `!` on i64; binding renders as `i64`). -/
  | signedBitNot (operand : Expr)
  /-- UInt8 bitwise not (Bytes element lane; binding renders as `u8`). -/
  | u8BitNot (operand : Expr)
  | boolNot (operand : Expr)
  /-- Checked Int64 negation (intMin reverts at emission). -/
  | checkedNeg (operand : Expr)
  /-- Type-directed selection `cond ? thenV : elseV` (Map pilot selectors;
      Leo ternary requires same-typed arms and a Bool condition). -/
  | ternary (condition thenValue elseValue : Expr)
  /-- T14 catalog v2 (BLS12-377): native Leo `field` literal. The value is the
      raw BLS12-377 Fr element (`< r`); emitted as a Leo `field` literal. -/
  | fieldLiteral (value : UInt64)
  /-- T14 catalog v2 (BLS12-377): native Leo `field` arithmetic. Leo `field` is
      a field element so the op is exact mod BLS12-377 Fr — no checked-overflow
      guard. -/
  | fieldBinary (op : FieldArithOp) (lhs rhs : Expr)
  /-- T14 catalog v2 (BLS12-377): native Leo `field` equality (eq/ne only;
      Leo `field` has no ordering). -/
  | fieldCompare (op : ComparisonOp) (lhs rhs : Expr)
  /-- T14 catalog v2 (BLS12-377): native Leo `field` negation `0 - x`
      (BLS12-377 Fr inverse; no intMin revert). -/
  | fieldNeg (operand : Expr)
  | callFn (fnName : String) (args : Array Expr)
  deriving BEq, Inhabited, Repr

/-- One leaf write: `fieldIndex` into `stateFieldNames` + value Expr. -/
structure Store where
  fieldIndex : Nat
  value : Expr
  deriving BEq, Inhabited, Repr

inductive Statement where
  /-- Scalar StateStore (single mapping leaf). -/
  | store (fieldIndex : Nat) (value : Expr)
  /-- Atomic multi-leaf StateStore (Map / Array / Struct / Bytes flatten).
      EmitIR two-phase: every leaf Expr lowers against the same pre-store
      mapping snapshot (all `get_or_use`), then all `set`s apply. Sequential
      per-leaf `.store` would interleave live `set` with later leaf
      `get_or_use` (Map empty-slot upsert hazard). Distinct storeAggregate
      statements stay ordered — the next StateStore sees prior writes.
      Scalar stores remain `.store`; never batch consecutive stores by guess. -/
  | storeAggregate (leaves : Array Store)
  | assert (condition : Expr)
  | returnValue (value : Expr)
  | returnNone
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  /-- Bounded for (see module doc for the exact Leo encoding). -/
  | forLoop (start endExclusive : Expr) (maxIterations : Nat)
      (body : Array Statement)
  | emitEvent (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  deriving BEq, Inhabited, Repr

inductive FunctionKind where
  | initialize
  | mutate
  deriving BEq, Inhabited, Repr

structure PlanParam where
  sourceIndex : Nat
  name : String
  isBool : Bool
  /-- Int64 parameter (Leo `i64`); overrides the `isBool`-driven u64 default. -/
  isInt : Bool := false
  /-- UInt8 parameter (Bytes element lane; Leo `u8`). -/
  isU8 : Bool := false
  /-- T14 catalog v2 (BLS12-377): native Leo `field` parameter. -/
  isField : Bool := false
  deriving BEq, Inhabited, Repr

/-- One callable artifact. `resultDropped` records that a non-Unit result
    cannot be returned by Leo's `Final` model (see module doc): the value is
    observable post-transaction via `leo query`, and each return expression
    is still evaluated in the final block for failure semantics.
    `isPureHelper` is true for Semantic `pureFn` callables: Leo 4.0.2 requires
    helper `fn`s outside the `program` block (no input modes) so entry points
    can call them. -/
structure PlanFunction where
  index : Nat
  name : String
  kind : FunctionKind
  params : Array PlanParam
  body : Array Statement
  /-- True when the body reads or writes mappings (Final function). -/
  touchesState : Bool
  resultIsBool : Bool
  /-- Int64 result (Leo `i64`); overrides the `isBool`-driven u64 default. -/
  resultIsInt : Bool := false
  /-- UInt8 result (Bytes element lane; Leo `u8`). -/
  resultIsU8 : Bool := false
  /-- T14 catalog v2 (BLS12-377): native Leo `field` result. -/
  resultIsField : Bool := false
  resultDropped : Bool
  /-- True when source kind was `pureFn` (Leo helper outside program). -/
  isPureHelper : Bool := false
  deriving BEq, Inhabited, Repr

/-- Bare public-state read view: materializes as an off-chain mapping query
    (the EVM `eth_call` analogue), never as an on-chain artifact. -/
structure PlanView where
  name : String
  stateFieldIndex : Nat
  deriving BEq, Inhabited, Repr

/-- Target-owned Aleo Plan. Retains no SemanticProgram; carries the canonical
    source/semantic digests and the artifact program name. -/
structure Plan where
  programName : String
  stateFieldNames : Array String
  /-- Int64 flag per state field (index-aligned with `stateFieldNames`); used
      to render `i64` mappings and default values. -/
  stateFieldIsInt : Array Bool
  /-- UInt8 flag per state field (Bytes element lane; `u8` mappings). -/
  stateFieldIsU8 : Array Bool
  /-- T14 catalog v2 (BLS12-377): Leo `field` flag per state field. -/
  stateFieldIsField : Array Bool
  functions : Array PlanFunction
  views : Array PlanView
  sourceHash : String
  semanticHash : String
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .aleo message

private def aleoPlanErr (message : String) : CompileError :=
  .planInvariant .aleo message

/-- Aleo type-closure wording. Field pin cites BLS12-377 Fr ≠ bn254 Fr. -/
private def aleoTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Aleo"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/UInt32/UInt8/Int64 widths are supported"
  unsupportedShapeDetail :=
    "only UInt64, UInt32, UInt8, Int64, Unit, Bool, Field(bls12-377-fr), named Struct/Enum, Array UInt64, Map UInt64 UInt64, and Bytes N are supported (Aleo native field is BLS12-377 Fr / Edwards BLS scalar, exact modulus match; bn254 Fr and Goldilocks fail closed as wrong modulus; Option-state/Principal/String stay fail-closed)"

/-- Aleo pilot width policy: UInt64 + UInt32 (shift counts) + **UInt8**
    (Bytes N element lane). UInt16/128/256 stay fail-closed. -/
private def pilotUintWidthPolicyU64U32U8 : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8]

/-- Aleo pilot type-closure: UInt64 + UInt32 + UInt8 (Bytes elements) +
    Int64 + Unit/Bool + named Struct/Enum + Array UInt64 + dense **Map
    UInt64 UInt64** (capacity-2 occ/key/val leaves, NS-1 pattern) + fixed
    **Bytes N** (N UInt8 leaves) + Option body intermediate (Map IndexGet
    result). Field stays `pilotFieldPolicyNone` (BLS12-377 ≠ bn254).
    Bytes-state/Principal/String stay fail-closed; UInt8 state/params stay
    fail-closed (only the Bytes element lane is open). -/
private def validateAleoTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult PilotTypeClosureV1 :=
  validatePilotTypeClosure aleoPlanErr aleoTypeClosureWording types
    pilotUintWidthPolicyU64U32U8
    (intPolicy := pilotIntWidthPolicyI64)
    (fieldPolicy := pilotFieldPolicyBls12377)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayMapBytes)

-- ---------------------------------------------------------------------------
-- Wire semantic → target-owned Plan lowering
-- ---------------------------------------------------------------------------

private def maxIdentifierBytes : Nat := 240
private def maxStateLeafFields : Nat := 256

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

private abbrev AleoTypeClosureV1 := PilotTypeClosureV1

private structure LoweredVal where
  expr : Expr
  leaves? : Option (Array Expr) := none
  /-- Int64 signedness for scalar values and per-leaf (index-aligned with
      `leaves?` when set). Used by binary/unary lowering to select signed ops
      and by emission to render `i64`. -/
  leafIsInt? : Option (Array Bool) := none
  /-- UInt8 (Bytes element) flag, per-leaf like `leafIsInt?`. -/
  leafIsU8? : Option (Array Bool) := none
  /-- T14 catalog v2 (BLS12-377): scalar Leo `field` value. Selects native
      field arithmetic (no checked-overflow guard) and `field` emission. -/
  isField : Bool := false
  deriving Inhabited

private def LoweredVal.isAggregate (v : LoweredVal) : Bool :=
  v.leaves?.isSome

private def LoweredVal.leafExprs (v : LoweredVal) : Array Expr :=
  match v.leaves? with
  | some ls => ls
  | none => #[v.expr]

/-- Scalar signedness: for a scalar `LoweredVal`, the single leaf's Int64 flag. -/
private def LoweredVal.isIntScalar (v : LoweredVal) : Bool :=
  match v.leafIsInt? with
  | some flags => flags.getD 0 false
  | none => false

/-- Scalar UInt8 flag (Bytes element lane). -/
private def LoweredVal.isU8Scalar (v : LoweredVal) : Bool :=
  match v.leafIsU8? with
  | some flags => flags.getD 0 false
  | none => false

private def mkScalarVal (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, leafIsInt? := none, leafIsU8? := none, isField := false }

/-- Scalar Int64 carrier (single i64 leaf). -/
private def mkScalarIntVal (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, leafIsInt? := some #[true], leafIsU8? := none, isField := false }

/-- Scalar UInt8 carrier (Bytes element lane). -/
private def mkScalarU8Val (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, leafIsInt? := none, leafIsU8? := some #[true], isField := false }

/-- T14 catalog v2 (BLS12-377): scalar Leo `field` carrier. -/
private def mkScalarFieldVal (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, leafIsInt? := none, leafIsU8? := none, isField := true }

private def mkAggregateVal (leaves : Array Expr) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves,
    leafIsInt? := some (leaves.map (fun _ => false)),
    leafIsU8? := some (leaves.map (fun _ => false)), isField := false }

/-- Aggregate carrier with explicit per-leaf signedness. -/
private def mkAggregateValInt (leaves : Array Expr) (flags : Array Bool) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves, leafIsInt? := some flags,
    leafIsU8? := some (leaves.map (fun _ => false)), isField := false }

/-- Aggregate carrier with explicit per-leaf Int64 and UInt8 flags. -/
private def mkAggregateValFlags (leaves : Array Expr)
    (intFlags u8Flags : Array Bool) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves, leafIsInt? := some intFlags,
    leafIsU8? := some u8Flags, isField := false }

private structure ValueEnv where
  entries : Array (ValueIdV1 × LoweredVal)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option LoweredVal :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envLookupExpr (env : ValueEnv) (id : ValueIdV1) : Option Expr :=
  (envLookup env id).map (·.expr)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, mkScalarVal e) }

/-- Insert a scalar Int64 value (carries signedness for later op selection). -/
private def envInsertInt (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, mkScalarIntVal e) }

/-- Insert a scalar UInt8 value (Bytes element lane). -/
private def envInsertU8 (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, mkScalarU8Val e) }

private def envInsertVal (env : ValueEnv) (id : ValueIdV1) (v : LoweredVal) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

private structure AleoLowerLayoutV1 where
  fieldNames : Array String
  /-- Int64 flag per state leaf (index-aligned with `fieldNames`). -/
  fieldIsInt : Array Bool
  /-- UInt8 flag per state leaf (Bytes element lane; u8 mappings). -/
  fieldIsU8 : Array Bool
  /-- T14 catalog v2 (BLS12-377): Leo `field` flag per state leaf. -/
  fieldIsField : Array Bool
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  types : AleoTypeClosureV1

private def isUInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 64, .. } => true
  | _ => false

private def isUInt8Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 8, .. } => true
  | _ => false

private def isInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .int 64, .. } => true
  | _ => false

private def isBoolType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .bool, .. } => true
  | _ => false

private def isUInt32Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 32, .. } => true
  | _ => false

private def isUnitType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .unit, .. } => true
  | _ => false

/-- T14 catalog v2 (BLS12-377): is this the admitted BLS12-377 Field type?
    `PilotTypeClosureV1.fieldTypeId` is `some` iff the exact BLS12-377
    FieldSpec passed the target type-closure. Any other catalog spec was
    rejected at closure, so a `some` here is exactly BLS12-377 Fr. -/
private def isBls12377FieldType
    (types : AleoTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.fieldTypeId == some typeId

/-- Dense Map pilot capacity (NS-1 occ/key/val pattern shared with
    EVM/Solana/NEAR/Noir), **reduced to 2 for Leo 4.0.2**: Leo limits a
    `final` block to 32 mapping `set`/`remove` commands **statically across
    every control-flow arm** (spike-verified ECMP0376015: transfer's two
    inner upserts count 2×cap×3 even though only one path executes). Every
    upsert emits capacity×3 sets, so capacity 2 → 6 leaves keeps the full
    shipped Token (mint 2×(6+1)=14, transfer 2×(6+6)=24) under the budget.
    `ValidatePlanV1` enforces the sum-over-arms budget so larger programs
    fail closed instead of emitting invalid Leo. -/
private def aleoMapPilotCapacityV1 : Nat := 2
private def aleoMapSlotsPerEntryV1 : Nat := 3
private def aleoMapPilotLeafCountV1 : Nat :=
  aleoMapPilotCapacityV1 * aleoMapSlotsPerEntryV1

/-- Flatten a state type to (leaf name, isInt64, isUInt8) triples (preorder).
    UInt64 → u64 leaf; Int64 → i64 leaf; named Struct/Enum and Array UInt64
    recurse as before; Map UInt64 UInt64 → capacity-2 × occ/key/val leaves;
    **Bytes N → N UInt8 leaves** (`<name>_<i>`, u8 mapping values).
    Nested containers fail closed. -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array (String × Bool × Bool)) := do
  if typeId == types.uint64TypeId then
    pure #[(namePrefix, false, false)]
  else if types.int64TypeId == some typeId then
    pure #[(namePrefix, true, false)]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        planError s!"unsupported Aleo semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              planError "unsupported Aleo semantic shape: named Struct requires at least one field"
            let mut out : Array (String × Bool × Bool) := #[]
            for f in fields do
              let subName :=
                if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
              unless isIdentifier subName do
                planError s!"state name '{subName}' is not a safe identifier"
              let sub ← flattenTypeLeafSpecsV1 typeDecls types f.typeId subName
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              planError "unsupported Aleo semantic shape: named Enum requires at least one variant"
            let tagName :=
              if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
            unless isIdentifier tagName do
              planError s!"state name '{tagName}' is not a safe identifier"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenTypeLeafSpecsV1 typeDecls types pt "tmp"
                n := n + sub.size
              if n > maxPay then maxPay := n
            let mut out : Array (String × Bool × Bool) := #[(tagName, false, false)]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                planError s!"state name '{pName}' is not a safe identifier"
              out := out.push (pName, false, false)
            pure out
        | _ =>
            planError "unsupported Aleo semantic shape: named type must be Struct or Enum"
  else if types.isContainer typeId then
    match typeDecls[typeId.toNat]? with
    | some { shape := .array elTid len, .. } =>
        unless elTid == types.uint64TypeId do
          planError "unsupported Aleo semantic shape: Array state element must be UInt64"
        let n := len.toNat
        unless n ≥ 1 do
          planError "unsupported Aleo semantic shape: Array state length must be ≥ 1"
        let mut out : Array (String × Bool × Bool) := #[]
        for i in [0:n] do
          let leafName := namePrefix ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          out := out.push (leafName, false, false)
        pure out
    | some { shape := .map keyTid valTid, .. } =>
        unless keyTid == types.uint64TypeId && valTid == types.uint64TypeId do
          planError "unsupported Aleo semantic shape: Map state admits only Map UInt64 UInt64"
        let mut out : Array (String × Bool × Bool) := #[]
        for e in [0:aleoMapPilotCapacityV1] do
          for (_, tag) in #[(0, "occ"), (1, "key"), (2, "val")] do
            let leafName := namePrefix ++ "_" ++ toString e ++ "_" ++ tag
            unless isIdentifier leafName do
              planError s!"state name '{leafName}' is not a safe identifier"
            out := out.push (leafName, false, false)
        pure out
    | some { shape := .bytes len, .. } =>
        -- D4-E2 pattern: fixed Bytes N → N consecutive UInt8 leaves.
        let n := len.toNat
        unless n ≥ 1 do
          planError "unsupported Aleo semantic shape: Bytes state length must be ≥ 1"
        let mut out : Array (String × Bool × Bool) := #[]
        for i in [0:n] do
          let leafName := namePrefix ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          out := out.push (leafName, false, true)
        pure out
    | _ =>
        planError "unsupported Aleo semantic shape: container TypeId is not Array/Map/Bytes"
  else
    planError "unsupported Aleo semantic shape: aggregate leaf must be UInt64, Int64, named Struct/Enum, Array UInt64, Map UInt64 UInt64, or Bytes N"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- Per-leaf Int64 flags of a state type (preorder flatten). -/
private def leafFlagsOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Array Bool) := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure (specs.map (·.2.1))

/-- Per-leaf UInt8 flags of a state type (Bytes element lane). -/
private def leafU8FlagsOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Array Bool) := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure (specs.map (·.2.2))

private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (fields : Array StructFieldV1) (fieldIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let mut start : Nat := 0
  for i in [0:fields.size] do
    let some f := fields[i]? |
      planError "struct field index out of range"
    let n ← leafCountOfTypeV1 typeDecls types f.typeId
    if i == fieldIndex then return (start, n)
    start := start + n
  planError "struct field index out of range"

private def enumMaxPayloadLeavesV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (variants : Array EnumVariantV1) : CompileResult Nat := do
  let mut maxPay : Nat := 0
  for v in variants do
    let mut n : Nat := 0
    for pt in v.payloadTypes do
      let c ← leafCountOfTypeV1 typeDecls types pt
      n := n + c
    if n > maxPay then maxPay := n
  pure maxPay

private def enumPayloadLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (variants : Array EnumVariantV1) (variantIndex payloadIndex : Nat) :
    CompileResult (Nat × Nat) := do
  let some v := variants[variantIndex]? |
    planError "enum variant index out of range"
  let mut start : Nat := 0
  for i in [0:v.payloadTypes.size] do
    let some pt := v.payloadTypes[i]? |
      planError "enum payload index out of range"
    let n ← leafCountOfTypeV1 typeDecls types pt
    if i == payloadIndex then return (start, n)
    start := start + n
  planError "enum payload index out of range"

private def arrayUInt64LeafCountV1
    (typeDecls : Array TypeDeclV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless elTid == types.uint64TypeId do
        planError "unsupported Aleo semantic shape: Array state element must be UInt64"
      let n := len.toNat
      unless n ≥ 1 do
        planError "unsupported Aleo semantic shape: Array state length must be ≥ 1"
      pure (some n)
  | some { shape := .map keyTid valTid, .. } =>
      unless keyTid == types.uint64TypeId && valTid == types.uint64TypeId do
        planError "unsupported Aleo semantic shape: Map state admits only Map UInt64 UInt64"
      pure (some aleoMapPilotLeafCountV1)
  | some { shape := .bytes len, .. } =>
      -- Bytes N → N UInt8 leaves.
      let n := len.toNat
      unless n ≥ 1 do
        planError "unsupported Aleo semantic shape: Bytes state length must be ≥ 1"
      pure (some n)
  | _ =>
      planError "unsupported Aleo semantic shape: container TypeId is not Array/Map/Bytes"

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]` (unrolled; the
    EVM/NEAR pattern). Leo is type-strict, so every selector is a typed
    ternary (`cond ? thenV : elseV` with Bool condition and same-typed u64
    arms); the tag leaf is a u64 0/1. -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == aleoMapPilotLeafCountV1 do
    planError "unsupported Aleo semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .boolLiteral false
  let mut payload : Expr := .literal 0
  for e in [0:aleoMapPilotCapacityV1] do
    let base := e * aleoMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      planError "Map lookup val leaf missing"
    let hit :=
      Expr.logicalAnd (Expr.compare .ne occ (.literal 0)) (Expr.compare .eq k key)
    found := Expr.logicalOr found hit
    payload := Expr.ternary hit v payload
  -- Tag leaf is a u64 0/1 (UInt-compatible for the Option aggregate).
  pure #[Expr.ternary found (.literal 1) (.literal 0), payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert) where okInsert is
    a u64 0/1 — caller must assert (divide-by) it (map full when key absent).
    All selectors are typed Leo ternaries. -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == aleoMapPilotLeafCountV1 do
    planError "unsupported Aleo semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .boolLiteral false
  for e in [0:aleoMapPilotCapacityV1] do
    let base := e * aleoMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "Map upsert key leaf missing"
    let hit :=
      Expr.logicalAnd (Expr.compare .ne occ (.literal 0)) (Expr.compare .eq k key)
    anyMatch := Expr.logicalOr anyMatch hit
  let mut seenEmpty : Expr := .boolLiteral false
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:aleoMapPilotCapacityV1] do
    let base := e * aleoMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map upsert empty-scan occ missing"
    let empty := Expr.compare .eq occ (.literal 0)
    let first := Expr.logicalAnd empty (Expr.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := Expr.logicalOr seenEmpty empty
  let okInsert := Expr.ternary (Expr.logicalOr anyMatch seenEmpty) (.literal 1) (.literal 0)
  let mut out : Array Expr := #[]
  for e in [0:aleoMapPilotCapacityV1] do
    let base := e * aleoMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      planError "Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      planError "Map upsert rebuild val missing"
    let matchHit :=
      Expr.logicalAnd (Expr.compare .ne occ (.literal 0)) (Expr.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      planError "Map upsert firstEmpty missing"
    let insertHere := Expr.logicalAnd firstE (Expr.boolNot anyMatch)
    let write := Expr.logicalOr matchHit insertHere
    let occ' := Expr.ternary (Expr.logicalOr (Expr.compare .ne occ (.literal 0)) write)
      (.literal 1) (.literal 0)
    let k' := Expr.ternary write key k
    let v' := Expr.ternary write value v
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

private def makeStateLayoutV1
    (types : AleoTypeClosureV1) (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult AleoLowerLayoutV1 := do
  let mut fieldNames : Array String := #[]
  let mut fieldIsInt : Array Bool := #[]
  let mut fieldIsU8 : Array Bool := #[]
  let mut fieldIsField : Array Bool := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      planError "unsupported Aleo semantic shape: semantic state ids must match declaration order"
    unless isIdentifier state.name do
      planError s!"state name '{state.name}' is not a safe identifier"
    if types.isNamedAggregate state.typeId || types.isContainer state.typeId then
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
      if fieldNames.size + leafSpecs.size > maxStateLeafFields then
        planError "unsupported Aleo semantic shape: state leaf count exceeds Aleo profile limit"
      let mut leaves : Array Nat := #[]
      for (name, isInt, isU8) in leafSpecs do
        leaves := leaves.push fieldNames.size
        fieldNames := fieldNames.push name
        fieldIsInt := fieldIsInt.push isInt
        fieldIsU8 := fieldIsU8.push isU8
        fieldIsField := fieldIsField.push false
      stateLeaves := stateLeaves.push leaves
    else if state.typeId == types.uint64TypeId then
      let leafIdx := fieldNames.size
      fieldNames := fieldNames.push state.name
      fieldIsInt := fieldIsInt.push false
      fieldIsU8 := fieldIsU8.push false
      fieldIsField := fieldIsField.push false
      stateLeaves := stateLeaves.push #[leafIdx]
    else if types.int64TypeId == some state.typeId then
      let leafIdx := fieldNames.size
      fieldNames := fieldNames.push state.name
      fieldIsInt := fieldIsInt.push true
      fieldIsU8 := fieldIsU8.push false
      fieldIsField := fieldIsField.push false
      stateLeaves := stateLeaves.push #[leafIdx]
    else if isBls12377FieldType types state.typeId then
      -- T14 catalog v2 (BLS12-377): Field state is one native Leo `field` leaf.
      let leafIdx := fieldNames.size
      fieldNames := fieldNames.push state.name
      fieldIsInt := fieldIsInt.push false
      fieldIsU8 := fieldIsU8.push false
      fieldIsField := fieldIsField.push true
      stateLeaves := stateLeaves.push #[leafIdx]
    else
      planError "Aleo state must be UInt64, Int64, BLS12-377 Field, named Struct/Enum, Array UInt64, Map UInt64 UInt64, or Bytes N (Option/bn254-fr/Goldilocks declined)"
  pure { fieldNames, fieldIsInt, fieldIsU8, fieldIsField, stateLeaves, typeDecls, types }

private def literalIndexNatV1 (v : LoweredVal) : CompileResult Nat := do
  unless !v.isAggregate do
    planError "unsupported Aleo semantic shape: Array index must be a scalar UInt literal"
  match v.expr with
  | .literal n => pure n.toNat
  | _ =>
      planError "unsupported Aleo semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    planError "Aleo UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ => planError "Aleo UInt64 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ => planError "Aleo UInt64 literal carries trailing bytes"

/-- Canonical 1-byte Bool literal decode (0x00/0x01 only). -/
private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    planError "Aleo Bool literal must contain exactly 1 byte"
  let b := bytes.get! 0
  if b == 0 then pure false
  else if b == 1 then pure true
  else planError "Aleo Bool literal must be 0x00 or 0x01"

/-- Shift-count literals are 4-byte LE UInt32 on the wire; widen to UInt64 for
    the Plan expression surface (values are always < 2^32). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    planError "Aleo UInt32 literal must contain exactly 4 bytes"
  match decodeU32le (start bytes) with
  | .error _ => planError "Aleo UInt32 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure (UInt64.ofNat value.toNat)
      | .error _ => planError "Aleo UInt32 literal carries trailing bytes"

/-- UInt8 literals are 1-byte LE values (Bytes element lane). -/
private def decodeUInt8LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 1 do
    planError "Aleo UInt8 literal must contain exactly 1 byte"
  pure (UInt64.ofNat (bytes.get! 0).toNat)

private def lowerLiteral
    (data : SemanticProgramDataV1) (types : AleoTypeClosureV1)
    (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult Expr := do
  if isUInt64Type data typeId then
    match decodeUInt64LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error _ => planError "Aleo UInt64 literal is not canonical"
  else if isInt64Type data typeId then
    -- Int64 literals are canonical 8-byte LE two's complement bit patterns;
    -- the raw bits carry through to the Leo `i64` literal rendering.
    match decodeUInt64LiteralV1 valueBytes with
    | .ok value => pure (.i64Literal value)
    | .error _ => planError "Aleo Int64 literal is not canonical"
  else if isBoolType data typeId then
    match decodeBoolLiteralV1 valueBytes with
    | .ok flag => pure (.boolLiteral flag)
    | .error _ => planError "Aleo Bool literal is not canonical"
  else if isUInt32Type data typeId then
    match decodeUInt32LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error _ => planError "Aleo UInt32 literal is not canonical"
  else if isUInt8Type data typeId then
    -- UInt8 literals are canonical 1-byte LE values (Bytes element lane).
    match decodeUInt8LiteralV1 valueBytes with
    | .ok value => pure (.u8Literal value)
    | .error _ => planError "Aleo UInt8 literal is not canonical"
  else if isBls12377FieldType types typeId then
    -- T14 catalog v2 (BLS12-377): Field literal. The wire valueBytes are 32
    -- LE bytes (`< r`). The Plan Expr surface carries a UInt64 leaf; the only
    -- Field literal that can reach here is the init default `0` (Normalize has
    -- no Field source literal), so decoding the low 8 LE bytes is exact for
    -- the admitted slice. A non-zero high-byte Field literal fails closed to
    -- avoid silently truncating a 253-bit element into a UInt64 leaf.
    unless valueBytes.size == 32 do
      planError "Aleo BLS12-377 Field literal must contain exactly 32 bytes"
    let highClear := Id.run do
      let mut ok := true
      for i in [8:32] do
        if (valueBytes.get! i).toNat != 0 then ok := false
      pure ok
    unless highClear do
      planError "Aleo BLS12-377 Field literal exceeds the UInt64 leaf envelope (only the init default 0 is admitted)"
    match decodeU64le (start valueBytes) with
    | .error _ => planError "Aleo BLS12-377 Field literal is not canonical"
    | .ok (value, _cursor) => pure (.fieldLiteral value)
  else
    planError "Aleo literal type is outside the public UInt64/Int64/Bool/UInt32/UInt8/BLS12-377-Field envelope"

private def lowerBinary
    (op : BinaryOpV1) (lhs rhs : Expr) (signed : Bool) : CompileResult Expr :=
  match op with
  | .add => pure (if signed then .signedCheckedAdd lhs rhs else .checkedAdd lhs rhs)
  | .sub => pure (if signed then .signedCheckedSub lhs rhs else .checkedSub lhs rhs)
  | .mul => pure (if signed then .signedCheckedMul lhs rhs else .checkedMul lhs rhs)
  | .div => pure (if signed then .signedCheckedDiv lhs rhs else .checkedDiv lhs rhs)
  | .mod => pure (if signed then .signedCheckedMod lhs rhs else .checkedMod lhs rhs)
  | .eq => pure (if signed then .signedCompare .eq lhs rhs else .compare .eq lhs rhs)
  | .ne => pure (if signed then .signedCompare .ne lhs rhs else .compare .ne lhs rhs)
  | .lt => pure (if signed then .signedCompare .lt lhs rhs else .compare .lt lhs rhs)
  | .le => pure (if signed then .signedCompare .le lhs rhs else .compare .le lhs rhs)
  | .gt => pure (if signed then .signedCompare .gt lhs rhs else .compare .gt lhs rhs)
  | .ge => pure (if signed then .signedCompare .ge lhs rhs else .compare .ge lhs rhs)
  | .and => pure (.logicalAnd lhs rhs)
  | .or => pure (.logicalOr lhs rhs)
  | .bitAnd => pure (if signed then .signedBitAnd lhs rhs else .bitAnd lhs rhs)
  | .bitOr => pure (if signed then .signedBitOr lhs rhs else .bitOr lhs rhs)
  | .bitXor => pure (if signed then .signedBitXor lhs rhs else .bitXor lhs rhs)
  | .shl => pure (if signed then .signedShl lhs rhs else .shl lhs rhs)
  | .shr => pure (if signed then .signedShr lhs rhs else .shr lhs rhs)

private def lowerUnary
    (op : UnaryOpV1) (operand : Expr) (signed : Bool) : CompileResult Expr :=
  match op with
  | .not => pure (.boolNot operand)
  | .bitNot => pure (if signed then .signedBitNot operand else .bitNot operand)
  | .neg =>
      if signed then pure (.checkedNeg operand)
      else planError "Aleo does not support unary neg on unsigned values"

/-- UInt8-lane binary (Bytes elements).

    * shifts → `u8Shl`/`u8Shr` (count < 8 guard + Leo's native checked u8
      shift: overflow and invalidShift both revert, spike-verified).
    * comparisons → widen both operands to u64 (`as u64` is lossless) and
      compare there; the result is Bool.
    * arithmetic/bitwise → widen both operands to u64, run the checked u64
      op (u64 add/sub of two widened u8 values can only overflow/underflow
      exactly when the wire u8 op would, since u8 wraps at 256), then
      `narrow8` — Leo's `as u8` cast reverts out-of-range values
      (spike-verified), which is exactly the wire's checked-UInt8 boundary.
      Bitwise and/or/xor of u8 values is always ≤ 255 so the narrow cast is
      vacuous there. -/
private def lowerU8Binary
    (op : BinaryOpV1) (lhs rhs : Expr) : CompileResult Expr :=
  match op with
  | .shl => pure (.u8Shl lhs rhs)
  | .shr => pure (.u8Shr lhs rhs)
  | .eq => pure (.compare .eq (.u8To64 lhs) (.u8To64 rhs))
  | .ne => pure (.compare .ne (.u8To64 lhs) (.u8To64 rhs))
  | .lt => pure (.compare .lt (.u8To64 lhs) (.u8To64 rhs))
  | .le => pure (.compare .le (.u8To64 lhs) (.u8To64 rhs))
  | .gt => pure (.compare .gt (.u8To64 lhs) (.u8To64 rhs))
  | .ge => pure (.compare .ge (.u8To64 lhs) (.u8To64 rhs))
  | .and | .or =>
      planError "Aleo UInt8 lane does not admit logical and/or"
  | other =>
      let l' := .u8To64 lhs
      let r' := .u8To64 rhs
      match lowerBinary other l' r' false with
      | .ok e => pure (.narrow8 e)
      | .error err => .error err

private structure LoopCtxV1 where
  header : BlockIdV1
  deriving Inhabited

private structure LowerStateV1 where
  stmts : Array Statement
  deriving Inhabited

/-- Whether a block id is a loop header of this callable (any bound). -/
private def isLoopHeaderV1 (callable : CallableV1) (blockId : BlockIdV1) : Bool :=
  callable.loopBounds.any (fun lb => lb.header == blockId)

/-- Whether a block id is a loop header currently on the loop stack. -/
private def isActiveHeader (loops : Array LoopCtxV1) (blockId : BlockIdV1) : Bool :=
  loops.any (fun ctx => ctx.header == blockId)

private structure RegionResult where
  stmts : Array Statement
  join? : Option Nat
  deriving Inhabited

private def regionClosed : CompileResult RegionResult :=
  pure { stmts := #[], join? := none }

mutual

/-- Lower one callable body starting at `entry` (a non-loop block; loop
    headers are entered through `lowerLoop`). Blocks are forward-only except
    the loop back edges; joins are blocks reached by jumps from multiple open
    arms and are walked exactly once by the caller. -/
private partial def lowerRegion
    (data : SemanticProgramDataV1) (layout : AleoLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (entry : Nat) (loops : Array LoopCtxV1) (env : ValueEnv)
    (ls : LowerStateV1) : CompileResult RegionResult := do
  if entry >= callable.blocks.size then
    planError "Aleo lowering references a missing block"
  let block ← match callable.blocks[entry]? with
    | some b => pure b
    | none => planError "Aleo lowering references a missing block"
  unless block.params.isEmpty do
    planError "Aleo lowering: block parameters only appear on loop headers"
  let mut env := env
  let mut ls := ls
  for instr in block.instructions do
    match instr.op with
    | .literal typeId valueBytes => do
        let e ← lowerLiteral data layout.types typeId valueBytes
        match instr.result with
        | none => planError "Aleo literal instruction must produce a value"
        | some valueDef =>
            if isInt64Type data typeId then
              env := envInsertInt env valueDef.valueId e
            else if isUInt8Type data typeId then
              env := envInsertU8 env valueDef.valueId e
            else if isBls12377FieldType layout.types typeId then
              env := envInsertVal env valueDef.valueId (mkScalarFieldVal e)
            else
              env := envInsert env valueDef.valueId e
    | .stateLoad stateId => do
        match instr.result with
        | none => planError "Aleo stateLoad instruction must produce a value"
        | some valueDef =>
            let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
              | some idxs => pure idxs
              | none => planError "Aleo stateLoad references unknown state id"
            if leafIdxs.size == 1 then
              let some fi := leafIdxs[0]? |
                planError "Aleo stateLoad leaf index missing"
              if layout.fieldIsInt.getD fi false then
                env := envInsertInt env valueDef.valueId (.stateLoad fi)
              else if layout.fieldIsU8.getD fi false then
                env := envInsertU8 env valueDef.valueId (.stateLoad fi)
              else if layout.fieldIsField.getD fi false then
                env := envInsertVal env valueDef.valueId (mkScalarFieldVal (.stateLoad fi))
              else
                env := envInsert env valueDef.valueId (.stateLoad fi)
            else
              let mut leaves : Array Expr := #[]
              let mut intFlags : Array Bool := #[]
              let mut u8Flags : Array Bool := #[]
              for fi in leafIdxs do
                leaves := leaves.push (.stateLoad fi)
                intFlags := intFlags.push (layout.fieldIsInt.getD fi false)
                u8Flags := u8Flags.push (layout.fieldIsU8.getD fi false)
              env := envInsertVal env valueDef.valueId
                (mkAggregateValFlags leaves intFlags u8Flags)
    | .binary op lhs rhs => do
        let l ← match envLookup env lhs with
          | some v => pure v
          | none => planError "Aleo binary references an undefined operand"
        let r ← match envLookup env rhs with
          | some v => pure v
          | none => planError "Aleo binary references an undefined operand"
        unless !l.isAggregate && !r.isAggregate do
          planError "Aleo binary operands must be scalar"
        -- T14 catalog v2 (BLS12-377): native Leo `field` arithmetic. Both
        -- operands must be scalar Field values; the op is exact mod BLS12-377
        -- Fr so no checked-overflow guard. Field admits add/sub/mul/div and
        -- eq/ne (ordering is rejected at Normalize); bitwise/shift fail closed.
        if l.isField && r.isField then
          let e ←
            match op with
            | .add => pure (.fieldBinary .add l.expr r.expr)
            | .sub => pure (.fieldBinary .sub l.expr r.expr)
            | .mul => pure (.fieldBinary .mul l.expr r.expr)
            | .div => pure (.fieldBinary .div l.expr r.expr)
            | .eq => pure (.fieldCompare .eq l.expr r.expr)
            | .ne => pure (.fieldCompare .ne l.expr r.expr)
            | _ => planError "Aleo Field admits only add/sub/mul/div/eq/ne"
          match instr.result with
          | none => planError "Aleo binary instruction must produce a value"
          | some valueDef =>
              if op == .eq || op == .ne then
                env := envInsert env valueDef.valueId e
              else
                env := envInsertVal env valueDef.valueId (mkScalarFieldVal e)
          pure ()
        -- Signedness: both operands must agree, except shifts whose count is
        -- always the UInt32 lane (unsigned). Bool/aggregate operands fail.
        let isShift := op == .shl || op == .shr
        let signed := l.isIntScalar
        if isShift then
          unless !r.isIntScalar do
            planError "Aleo shift count must be unsigned UInt32"
        else
          unless l.isIntScalar == r.isIntScalar do
            planError "Aleo binary operands must share signedness"
        -- UInt8 lane (Bytes elements): arithmetic/comparison operands must
        -- both be u8; shifts widen the lhs to u64 and use the u8 shift ops.
        let u8Lane := l.isU8Scalar || r.isU8Scalar
        if u8Lane then
          unless !signed do
            planError "Aleo UInt8 lane cannot mix with Int64"
        if u8Lane && !isShift then
          unless l.isU8Scalar && r.isU8Scalar do
            planError "Aleo UInt8 binary operands must share the u8 lane"
        let e ←
          if u8Lane && isShift then
            let widened := match instr.result with
              | some vd => isUInt8Type data vd.typeId
              | none => false
            if widened then
              pure (Expr.u8Shl l.expr r.expr)
            else
              planError "Aleo UInt8 shift result must be UInt8"
          else if u8Lane then
            -- Arithmetic/comparison in the u8 lane: Leo's native u8 ops are
            -- checked (add/mul overflow, div/mod zero, invalidShift); the
            -- wire's checked arithmetic maps directly.
            lowerU8Binary op l.expr r.expr
          else
            lowerBinary op l.expr r.expr signed
        match instr.result with
        | none => planError "Aleo binary instruction must produce a value"
        | some valueDef =>
            if signed && !(op == .eq || op == .ne || op == .lt || op == .le ||
                op == .gt || op == .ge) then
              env := envInsertInt env valueDef.valueId e
            else if u8Lane && !(op == .eq || op == .ne || op == .lt || op == .le ||
                op == .gt || op == .ge) then
              env := envInsertU8 env valueDef.valueId e
            else
              env := envInsert env valueDef.valueId e
    | .unary op operand => do
        let o ← match envLookup env operand with
          | some v => pure v
          | none => planError "Aleo unary references an undefined operand"
        unless !o.isAggregate do
          planError "Aleo unary operand must be scalar"
        -- T14 catalog v2 (BLS12-377): native Leo `field` negation.
        let e ← if o.isField then
            match op with
            | .neg => pure (.fieldNeg o.expr)
            | _ => planError "Aleo Field unary admits only neg"
          else if o.isU8Scalar then
            match op with
            | .bitNot => pure (.u8BitNot o.expr)
            | _ => planError "Aleo UInt8 unary admits only bitwise not"
          else
            lowerUnary op o.expr o.isIntScalar
        match instr.result with
        | none => planError "Aleo unary instruction must produce a value"
        | some valueDef =>
            if o.isField && op == .neg then
              env := envInsertVal env valueDef.valueId (mkScalarFieldVal e)
            else if o.isIntScalar && op != .not then
              env := envInsertInt env valueDef.valueId e
            else if o.isU8Scalar && op == .bitNot then
              env := envInsertU8 env valueDef.valueId e
            else
              env := envInsert env valueDef.valueId e
    | .pureCall callableId args => do
        let fnName ← match fnNames.findSome? (fun (cid, n) =>
            if cid == callableId then some n else none) with
          | some n => pure n
          | none => planError "Aleo pureCall references an unknown callee"
        let mut argExprs : Array Expr := #[]
        for arg in args do
          match envLookup env arg with
          | some v =>
              if v.isAggregate then
                planError "Aleo pureCall does not accept aggregate arguments"
              argExprs := argExprs.push v.expr
          | none => planError "Aleo pureCall references an undefined argument"
        let e : Expr := .callFn fnName argExprs
        match instr.result with
        | none => planError "Aleo pureCall instruction must produce a value"
        | some valueDef =>
            -- Callee result signedness: an Int64-returning pureFn call's
            -- result stays on the i64 lane.
            let calleeInt ← match data.callables.findSome? (fun c =>
                if c.id == callableId then some (isInt64Type data c.result.typeId) else none) with
              | some b => pure b
              | none => planError "Aleo pureCall references an unknown callee"
            if calleeInt then
              env := envInsertInt env valueDef.valueId e
            else
              env := envInsert env valueDef.valueId e
    | .stateStore stateId value => do
        let v ← match envLookup env value with
          | some lv => pure lv
          | none => planError "Aleo stateStore references an undefined value"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some idxs => pure idxs
          | none => planError "Aleo stateStore references unknown state id"
        let leaves := v.leafExprs
        unless leaves.size == leafIdxs.size do
          planError "Aleo stateStore leaf count mismatch"
        -- Per-leaf width check: the stored value's leaf lane must match the
        -- target leaf (u8 for Bytes elements, otherwise the u64 lane).
        let vFlags := match v.leafIsU8? with
          | some f => f
          | none => leaves.map (fun _ => false)
        let mut leafStores : Array Store := #[]
        for i in [0:leafIdxs.size] do
          let some fi := leafIdxs[i]? |
            planError "Aleo stateStore leaf index missing"
          let some e := leaves[i]? |
            planError "Aleo stateStore leaf value missing"
          let targetU8 := layout.fieldIsU8.getD fi false
          let valU8 := vFlags.getD i false
          unless targetU8 == valU8 do
            planError "Aleo stateStore leaf width mismatch (Bytes u8 lane vs scalar lane)"
          leafStores := leafStores.push { fieldIndex := fi, value := e }
        -- Multi-leaf aggregate: one storeAggregate so EmitIR two-phase
        -- evaluates every leaf Expr against the pre-store mapping snapshot
        -- (Map upsert cross-reads sibling leaves via stateLoad). Scalar
        -- stays `.store`. Do not merge across distinct StateStores.
        if leafStores.size == 1 then
          let some s := leafStores[0]? |
            planError "Aleo stateStore scalar leaf missing"
          ls := { ls with stmts := ls.stmts.push (.store s.fieldIndex s.value) }
        else if leafStores.size > 1 then
          ls := { ls with stmts := ls.stmts.push (.storeAggregate leafStores) }
        else
          planError "Aleo stateStore has zero leaves"
    | .assert_ condition _ args => do
        unless args.isEmpty do
          planError "Aleo assert-else is outside the envelope"
        let c ← match envLookupExpr env condition with
          | some e => pure e
          | none => planError "Aleo assert references an undefined condition"
        ls := { ls with stmts := ls.stmts.push (.assert c) }
    | .emit .. =>
        planError "Aleo does not support emit: Leo 4.0.2 has no on-chain event log"
    | .externalCall .. =>
        planError "Aleo does not support external calls"
    | .schedule .. =>
        planError "Aleo does not support scheduled workflows"
    -- N5: Op.Commit is label-only identity — reuse the operand's Plan value
    -- (no new Expr tag). Cryptographic commitment realization is deferred.
    | .commit valueId => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          planError "unsupported Aleo semantic shape: Commit is not admitted by pilot context policy"
        let operand ← match envLookup env valueId with
          | some v => pure v
          | none => planError "Aleo commit references an undefined operand"
        match instr.result with
        | none => planError "Aleo commit instruction must produce a value"
        | some valueDef =>
            env := envInsertVal env valueDef.valueId operand
    | .contextRead key => do
        unless key == unixTimeSecondsContextKeyV1 do
          planError s!"unsupported Aleo semantic shape: unknown ContextRead key '{key.value}'"
        planError
          "unsupported Aleo semantic shape: ContextRead is not admitted by pilot context policy"
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported Aleo semantic shape: construct instruction must produce a value"
        | some valueDef =>
            unless valueDef.typeId == typeId do
              planError "unsupported Aleo semantic shape: construct result typeId must match op typeId"
            if layout.types.isContainer typeId then
              let n ← match ← arrayUInt64LeafCountV1 layout.typeDecls layout.types typeId with
                | some n => pure n
                | none => planError "unsupported Aleo semantic shape: construct admits only Array UInt64 / Map UInt64 UInt64 on Aleo"
              unless ctorIdx == 0 do
                planError "unsupported Aleo semantic shape: Array/Map construct ctorIdx must be 0"
              -- Map.empty (ctor 0, 0 args) → dense zero leaves; Array
              -- construct takes exactly N scalar args.
              if n == aleoMapPilotLeafCountV1 && argIds.isEmpty then
                let mut zeros : Array Expr := #[]
                for _ in [0:n] do
                  zeros := zeros.push (.literal 0)
                env := envInsertVal env valueDef.valueId (mkAggregateVal zeros)
              else do
                unless argIds.size == n do
                  planError "unsupported Aleo semantic shape: Array construct arity mismatch"
                let mut leafExprs : Array Expr := #[]
                for argId in argIds do
                  let arg ← match envLookup env argId with
                    | some v => pure v
                    | none => planError "unsupported Aleo semantic shape: construct references undefined arg"
                  unless !arg.isAggregate do
                    planError "unsupported Aleo semantic shape: Array construct args must be scalar UInt64"
                  unless !arg.isIntScalar do
                    planError "unsupported Aleo semantic shape: Array UInt64 construct args must be unsigned"
                  leafExprs := leafExprs.push arg.expr
                env := envInsertVal env valueDef.valueId (mkAggregateVal leafExprs)
            else
              unless layout.types.isNamedAggregate typeId do
                planError "unsupported Aleo semantic shape: construct requires named Struct/Enum or Array"
              let some decl := layout.typeDecls[typeId.toNat]? |
                planError "unsupported Aleo semantic shape: construct TypeDecl missing"
              match decl.shape with
              | .struct fields => do
                  unless ctorIdx.toNat == 0 do
                    planError "unsupported Aleo semantic shape: struct construct ctorIdx must be 0"
                  unless argIds.size == fields.size do
                    planError "unsupported Aleo semantic shape: struct construct arity mismatch"
                  let mut leaves : Array Expr := #[]
                  let mut flags : Array Bool := #[]
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "struct construct arg missing"
                    let some field := fields[i]? |
                      planError "struct construct field missing"
                    let arg ← match envLookup env argId with
                      | some v => pure v
                      | none => planError "struct construct undefined arg"
                    let expected ← leafCountOfTypeV1 layout.typeDecls layout.types field.typeId
                    let argLeaves := arg.leafExprs
                    unless argLeaves.size == expected do
                      planError "unsupported Aleo semantic shape: struct construct field leaf count mismatch"
                    leaves := leaves ++ argLeaves
                    let fieldFlags ← leafFlagsOfTypeV1 layout.typeDecls layout.types field.typeId
                    flags := flags ++ fieldFlags
                  env := envInsertVal env valueDef.valueId (mkAggregateValInt leaves flags)
              | .enum variants => do
                  let vi := ctorIdx.toNat
                  let some variant := variants[vi]? |
                    planError "unsupported Aleo semantic shape: enum construct variant out of range"
                  unless argIds.size == variant.payloadTypes.size do
                    planError "unsupported Aleo semantic shape: enum construct arity mismatch"
                  let maxPay ← enumMaxPayloadLeavesV1 layout.typeDecls layout.types variants
                  let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
                  let mut flags : Array Bool := #[false]
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "enum construct arg missing"
                    let some pt := variant.payloadTypes[i]? |
                      planError "enum construct payload type missing"
                    let arg ← match envLookup env argId with
                      | some v => pure v
                      | none => planError "enum construct undefined arg"
                    let expected ← leafCountOfTypeV1 layout.typeDecls layout.types pt
                    let argLeaves := arg.leafExprs
                    unless argLeaves.size == expected do
                      planError "unsupported Aleo semantic shape: enum construct payload leaf count mismatch"
                    leaves := leaves ++ argLeaves
                    let ptFlags ← leafFlagsOfTypeV1 layout.typeDecls layout.types pt
                    flags := flags ++ ptFlags
                  while leaves.size < 1 + maxPay do
                    leaves := leaves.push (.literal 0)
                    flags := flags.push false
                  env := envInsertVal env valueDef.valueId (mkAggregateValInt leaves flags)
              | _ =>
                  planError "unsupported Aleo semantic shape: construct requires Struct or Enum shape"
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported Aleo semantic shape: fieldGet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "unsupported Aleo semantic shape: fieldGet base undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: fieldGet base must be a named aggregate"
            let baseLeaves := base.leafExprs
            let baseFlags := match base.leafIsInt? with
              | some f => f
              | none => baseLeaves.map (fun _ => false)
            let mut hit : Option (Nat × Nat) := none
            for tid in layout.types.namedTypeIds do
              match layout.typeDecls[tid.toNat]? with
              | some { shape := .struct fields, .. } => do
                  let total ← leafCountOfTypeV1 layout.typeDecls layout.types tid
                  if total == baseLeaves.size && fieldIndex.toNat < fields.size then
                    match fields[fieldIndex.toNat]? with
                    | some f =>
                        if f.typeId == valueDef.typeId then
                          let (s, l) ←
                            structFieldLeafRangeV1 layout.typeDecls layout.types fields
                              fieldIndex.toNat
                          hit := some (s, l)
                    | none => pure ()
              | _ => pure ()
            let (start, len) ← match hit with
              | some r => pure r
              | none =>
                  planError "unsupported Aleo semantic shape: fieldGet could not resolve struct field range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Aleo semantic shape: fieldGet leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            let mut outFlags : Array Bool := #[]
            for i in [start:start+len] do
              let some e := baseLeaves[i]? |
                planError "fieldGet leaf missing"
              outLeaves := outLeaves.push e
              outFlags := outFlags.push (baseFlags.getD i false)
            if layout.types.isNamedAggregate valueDef.typeId then
              env := envInsertVal env valueDef.valueId (mkAggregateValInt outLeaves outFlags)
            else
              let some e0 := outLeaves[0]? |
                planError "fieldGet scalar leaf missing"
              let isInt := outFlags.getD 0 false
              if isInt then
                env := envInsertInt env valueDef.valueId e0
              else
                env := envInsert env valueDef.valueId e0
    | .fieldSet baseId fieldIndex valueId => do
        match instr.result with
        | none => planError "unsupported Aleo semantic shape: fieldSet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "fieldSet base undefined"
            let val ← match envLookup env valueId with
              | some v => pure v
              | none => planError "fieldSet value undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: fieldSet base must be a named aggregate"
            unless layout.types.isNamedAggregate valueDef.typeId do
              planError "unsupported Aleo semantic shape: fieldSet result must be named aggregate"
            let baseLeaves := base.leafExprs
            let valLeaves := val.leafExprs
            let mut hit : Option (Nat × Nat) := none
            for tid in layout.types.namedTypeIds do
              if tid == valueDef.typeId then
                match layout.typeDecls[tid.toNat]? with
                | some { shape := .struct fields, .. } => do
                    if fieldIndex.toNat < fields.size then
                      let (s, l) ←
                        structFieldLeafRangeV1 layout.typeDecls layout.types fields
                          fieldIndex.toNat
                      hit := some (s, l)
                | _ => pure ()
            let (start, len) ← match hit with
              | some r => pure r
              | none => planError "unsupported Aleo semantic shape: fieldSet could not resolve field range"
            unless valLeaves.size == len do
              planError "unsupported Aleo semantic shape: fieldSet value leaf count mismatch"
            unless start + len <= baseLeaves.size do
              planError "unsupported Aleo semantic shape: fieldSet leaf range out of bounds"
            let baseFlags := match base.leafIsInt? with
              | some f => f
              | none => baseLeaves.map (fun _ => false)
            let valFlags := match val.leafIsInt? with
              | some f => f
              | none => valLeaves.map (fun _ => false)
            unless valFlags.size == len do
              planError "unsupported Aleo semantic shape: fieldSet value flag count mismatch"
            -- The field's stored signedness comes from the value being stored;
            -- the surrounding leaves keep their own flags.
            let mut outLeaves : Array Expr := #[]
            let mut outFlags : Array Bool := #[]
            for i in [0:baseLeaves.size] do
              if i >= start && i < start + len then
                let some e := valLeaves[i - start]? |
                  planError "fieldSet value leaf missing"
                outLeaves := outLeaves.push e
                outFlags := outFlags.push (valFlags.getD (i - start) false)
              else
                let some e := baseLeaves[i]? |
                  planError "fieldSet base leaf missing"
                outLeaves := outLeaves.push e
                outFlags := outFlags.push (baseFlags.getD i false)
            env := envInsertVal env valueDef.valueId (mkAggregateValInt outLeaves outFlags)
    | .variantTag baseId => do
        match instr.result with
        | none => planError "variantTag must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "variantTag base undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: variantTag base must be a named Enum aggregate"
            let some tag := base.leafExprs[0]? |
              planError "variantTag missing tag leaf"
            -- Option intermediate (2 leaves from Map IndexGet): the tag is
            -- 0/1; Normalize switches on a UInt32 tag so the 0/1 value is
            -- already UInt-compatible (Leo u64 arithmetic).
            env := envInsert env valueDef.valueId tag
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none => planError "variantPayload must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "variantPayload base undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: variantPayload base must be a named Enum aggregate"
            let baseLeaves := base.leafExprs
            let mut hit : Option (Nat × Nat × Bool) := none
            for tid in layout.types.namedTypeIds do
              match layout.typeDecls[tid.toNat]? with
              | some { shape := .enum variants, .. } => do
                  let total ← leafCountOfTypeV1 layout.typeDecls layout.types tid
                  if total == baseLeaves.size && variantIndex.toNat < variants.size then
                    let (s, l) ←
                      enumPayloadLeafRangeV1 layout.typeDecls layout.types variants
                        variantIndex.toNat payloadIndex.toNat
                    -- payload region starts after tag (leaf 0)
                    hit := some (1 + s, l, layout.types.isNamedAggregate valueDef.typeId)
              | _ => pure ()
            let (start, len, asAgg) ← match hit with
              | some r => pure r
              | none =>
                  -- I1: Option intermediate from Map IndexGet is a 2-leaf
                  -- aggregate `[tag, payload]`; Option.some = variant 1.
                  if variantIndex.toNat == 1 && payloadIndex.toNat == 0 &&
                      baseLeaves.size == 2 then
                    pure (1, 1, false)
                  else if variantIndex.toNat == 0 && baseLeaves.size == 2 then
                    planError "unsupported Aleo semantic shape: variantPayload of Option.none is empty"
                  else
                    planError "unsupported Aleo semantic shape: variantPayload could not resolve range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Aleo semantic shape: variantPayload leaf range out of bounds"
            let baseFlags := match base.leafIsInt? with
              | some f => f
              | none => baseLeaves.map (fun _ => false)
            let mut outLeaves : Array Expr := #[]
            let mut outFlags : Array Bool := #[]
            for i in [start:start+len] do
              let some e := baseLeaves[i]? |
                planError "variantPayload leaf missing"
              outLeaves := outLeaves.push e
              outFlags := outFlags.push (baseFlags.getD i false)
            if asAgg then
              env := envInsertVal env valueDef.valueId (mkAggregateValInt outLeaves outFlags)
            else
              let some e0 := outLeaves[0]? |
                planError "variantPayload scalar leaf missing"
              let isInt := outFlags.getD 0 false
              if isInt then
                env := envInsertInt env valueDef.valueId e0
              else
                env := envInsert env valueDef.valueId e0
    | .indexGet baseId idxId => do
        match instr.result with
        | none => planError "indexGet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "indexGet base undefined"
            let idx ← match envLookup env idxId with
              | some v => pure v
              | none => planError "indexGet index undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: IndexGet base must be an Array/Map aggregate"
            unless !idx.isAggregate && !idx.isIntScalar do
              planError "unsupported Aleo semantic shape: IndexGet index must be scalar unsigned"
            if base.leafExprs.size == aleoMapPilotLeafCountV1 then
              -- Dense Map IndexGet → Option UInt64 as `[tag, payload]`.
              let optLeaves ← mapLookupOptionLeavesV1 base.leafExprs idx.expr
              env := envInsertVal env valueDef.valueId (mkAggregateVal optLeaves)
            else do
              let i ← literalIndexNatV1 idx
              let leaves := base.leafExprs
              unless i < leaves.size do
                planError "unsupported Aleo semantic shape: Array/Bytes IndexGet index out of range"
              let some leaf := leaves[i]? |
                planError "Array/Bytes IndexGet leaf missing"
              let intFlags := match base.leafIsInt? with
                | some f => f
                | none => leaves.map (fun _ => false)
              let u8Flags := match base.leafIsU8? with
                | some f => f
                | none => leaves.map (fun _ => false)
              if intFlags.getD i false then
                env := envInsertInt env valueDef.valueId leaf
              else if u8Flags.getD i false then
                env := envInsertU8 env valueDef.valueId leaf
              else
                env := envInsert env valueDef.valueId leaf
    | .indexSet baseId idxId valueId => do
        match instr.result with
        | none => planError "indexSet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "indexSet base undefined"
            let idx ← match envLookup env idxId with
              | some v => pure v
              | none => planError "indexSet index undefined"
            let val ← match envLookup env valueId with
              | some v => pure v
              | none => planError "indexSet value undefined"
            unless base.isAggregate do
              planError "unsupported Aleo semantic shape: IndexSet base must be an Array/Map aggregate"
            unless !val.isAggregate do
              planError "unsupported Aleo semantic shape: IndexSet value must be scalar"
            unless !val.isIntScalar do
              planError "unsupported Aleo semantic shape: IndexSet value must be unsigned"
            if base.leafExprs.size == aleoMapPilotLeafCountV1 then
              -- Dense Map upsert; revert when the map is full.
              unless !val.isU8Scalar do
                planError "unsupported Aleo semantic shape: Map value must be UInt64 (not Bytes u8)"
              let (outLeaves0, okInsert) ←
                mapUpsertLeavesV1 base.leafExprs idx.expr val.expr
              let gate := Expr.checkedDiv (.literal 1) okInsert
              let mut outLeaves : Array Expr := #[]
              for i in [0:outLeaves0.size] do
                let some e := outLeaves0[i]? |
                  planError "Map IndexSet leaf missing after upsert"
                let e' :=
                  if i == 0 then
                    Expr.checkedAdd e (Expr.checkedMul gate (.literal 0))
                  else e
                outLeaves := outLeaves.push e'
              env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
            else do
              let i ← literalIndexNatV1 idx
              let leaves := base.leafExprs
              unless i < leaves.size do
                planError "unsupported Aleo semantic shape: Array/Bytes IndexSet index out of range"
              let u8Flags := match base.leafIsU8? with
                | some f => f
                | none => leaves.map (fun _ => false)
              -- Bytes element stores need the u8 lane; Array UInt64 stays u64.
              if u8Flags.getD i false then
                unless val.isU8Scalar do
                  planError "unsupported Aleo semantic shape: Bytes IndexSet value must be UInt8"
              else
                unless !val.isU8Scalar do
                  planError "unsupported Aleo semantic shape: Array UInt64 IndexSet value must be unsigned UInt64"
              let mut outLeaves : Array Expr := #[]
              for j in [0:leaves.size] do
                if j == i then
                  outLeaves := outLeaves.push val.expr
                else
                  let some e := leaves[j]? |
                    planError "Array/Bytes IndexSet leaf missing"
                  outLeaves := outLeaves.push e
              -- The rebuilt aggregate keeps the base's per-leaf lanes; the
              -- stored element's lane was checked against slot i above.
              let intFlags := match base.leafIsInt? with
                | some f => f
                | none => leaves.map (fun _ => false)
              env := envInsertVal env valueDef.valueId
                (mkAggregateValFlags outLeaves intFlags u8Flags)
    | .constant .. =>
        planError "unsupported Aleo semantic shape: Constant load is outside the public UInt64 envelope"
    | .checkedCast .. =>
        planError "unsupported Aleo semantic shape: CheckedCast is outside the public UInt64 envelope"
  -- Terminator
  match block.terminator with
  | .jump target =>
      if isActiveHeader loops target.blockId then
        -- Back edge: the enclosing loop's latch. The latch's own statements
        -- are the induction increment, re-derived by the loop encoding.
        pure { stmts := ls.stmts, join? := none }
      else if isLoopHeaderV1 callable target.blockId then
        lowerLoop data layout callable fnNames target ls env loops
      else
        lowerRegion data layout callable fnNames target.blockId.toNat loops env ls
  | .branch condition thenTarget elseTarget => do
      let c ← match envLookupExpr env condition with
        | some e => pure e
        | none => planError "Aleo branch references an undefined condition"
      let thenRes ← lowerRegion data layout callable fnNames thenTarget.blockId.toNat loops env ls
      let elseRes ← lowerRegion data layout callable fnNames elseTarget.blockId.toNat loops env ls
      let join? ← match thenRes.join?, elseRes.join? with
        | none, none => pure none
        | some j, none => pure (some j)
        | none, some j => pure (some j)
        | some j1, some j2 =>
            if j1 == j2 then pure (some j1)
            else planError "Aleo lowering: branch arms join at different blocks"
      let stmts := ls.stmts.push (.ifThenElse c thenRes.stmts elseRes.stmts)
      pure { stmts, join? }
  | .switch scrutinee cases defaultTarget => do
      let s ← match envLookup env scrutinee with
        | some v => pure v
        | none => planError "Aleo switch references an undefined scrutinee"
      -- Normalize admits only UInt/Bool match scrutinees; an Int64 scrutinee
      -- would render as an i64/unsigned-literal comparison — fail closed.
      unless !s.isIntScalar do
        planError "Aleo does not support Int64 match scrutinees (Normalize admits only UInt/Bool)"
      let sExpr := s.expr
      let mut caseStmts : Array (UInt64 × Array Statement) := #[]
      let mut joins : Array Nat := #[]
      for case in cases do
        -- Case constants carry their wire TypeId: UInt32 covers the Option
        -- variantTag (Map IndexGet tag switch); UInt64/Bool cover literals.
        let value ← if case.typeId.toNat < data.types.size &&
            (match data.types[case.typeId.toNat]? with
              | some { shape := .uint 32, .. } => true | _ => false) then
            match decodeUInt32LiteralV1 case.valueBytes with
              | .ok v => pure v
              | .error _ => planError "Aleo switch case value is not a canonical UInt32 tag"
          else
            match decodeUInt64LiteralV1 case.valueBytes with
              | .ok v => pure v
              | .error _ => planError "Aleo switch case value is not a canonical UInt64"
        let targetRes ← lowerRegion data layout callable fnNames case.target.blockId.toNat loops env ls
        caseStmts := caseStmts.push (value, targetRes.stmts)
        match targetRes.join? with
        | some j => joins := joins.push j
        | none => pure ()
      let defaultRes ← match defaultTarget with
        | none => regionClosed
        | some t => lowerRegion data layout callable fnNames t.blockId.toNat loops env ls
      match defaultRes.join? with
      | some j => joins := joins.push j
      | none => pure ()
      let join? ← match joins.toList with
        | [] => pure none
        | j :: rest =>
            if rest.all (· == j) then pure (some j)
            else planError "Aleo lowering: switch arms join at different blocks"
      let stmts := ls.stmts.push (.switchOn sExpr caseStmts defaultRes.stmts)
      pure { stmts, join? }
  | .return_ value => do
      let stmts ← match value with
        | none => pure (ls.stmts.push .returnNone)
        | some vid =>
            match envLookup env vid with
            | some v =>
                if v.isAggregate then
                  planError "Aleo return of aggregate is outside the scalar result envelope (B-RET-ABI: Aleo does not support named-aggregate return)"
                pure (ls.stmts.push (.returnValue v.expr))
            | none => planError "Aleo return references an undefined value"
      pure { stmts, join? := none }
  | .revert errorId args => do
      unless args.isEmpty do
        planError "Aleo does not support revert payloads: Leo 4.0.2 cannot represent error arguments"
      let stmts := ls.stmts.push (.revertError errorId.toNat #[])
      pure { stmts, join? := none }
  | .trap _ => do
      let stmts := ls.stmts.push (.assert (.boolLiteral false))
      pure { stmts, join? := none }

/-- Lower a bounded loop entered by `target` (a loop header): construct the
    `forLoop` statement from the header's `i < end` condition, the body region
    (terminated by the latch back edge), and the exit continuation. -/
private partial def lowerLoop
    (data : SemanticProgramDataV1) (layout : AleoLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (target : JumpTargetV1) (ls : LowerStateV1) (env : ValueEnv)
    (loops : Array LoopCtxV1) : CompileResult RegionResult := do
  let headerIdx := target.blockId.toNat
  let lb ← match callable.loopBounds.findSome? (fun lb =>
      if lb.header == target.blockId then some lb else none) with
    | some lb => pure lb
    | none => planError "Aleo lowering: loop bound missing for header"
  if loops.any (fun ctx => ctx.header == target.blockId) then
    planError "Aleo lowering: re-entered an active loop header"
  let header ← match callable.blocks[headerIdx]? with
    | some b => pure b
    | none => planError "Aleo lowering: loop header block is missing"
  unless header.params.size == 1 do
    planError "Aleo lowering: loop header must carry exactly one block parameter"
  let some paramDef := header.params[0]? |
    planError "Aleo lowering: loop header parameter is missing"
  unless target.args.size == 1 do
    planError "Aleo lowering: loop entry must carry exactly one argument"
  let startVid ← match target.args[0]? with
    | some v => pure v
    | none => planError "Aleo lowering: loop start value is missing"
  let startVal ← match envLookup env startVid with
    | some v => pure v
    | none => planError "Aleo lowering: loop start value is not defined"
  -- Bounded-for induction stays on the UInt64 lane. Shared Normalize retains
  -- Int endpoints, but a signed start would render an i64/u64 range mix here.
  unless !startVal.isIntScalar do
    planError "Aleo does not support Int64 for-loop endpoints in this profile"
  let startExpr := startVal.expr
  -- The header must be exactly `cond := i < end` + branch; the end value is
  -- loop-invariant (already in env). The branch condition must be the cond
  -- instruction's result.
  let mut condVid? : Option ValueIdV1 := none
  let mut endExpr? : Option Expr := none
  for instr in header.instructions do
    match instr.op with
    | .binary .lt lhs rhs => do
        unless lhs == paramDef.valueId do
          planError "Aleo lowering: loop condition lhs must be the induction parameter"
        let r ← match envLookup env rhs with
          | some v => pure v
          | none => planError "Aleo lowering: loop end value is not defined"
        unless !r.isIntScalar do
          planError "Aleo does not support Int64 for-loop endpoints in this profile"
        match instr.result with
        | some valueDef => condVid? := some valueDef.valueId
        | none => planError "Aleo lowering: loop condition must produce a value"
        endExpr? := some r.expr
    | _ =>
        planError "Aleo lowering: loop header carries an unexpected instruction"
  let endExpr ← match endExpr? with
    | some e => pure e
    | none => planError "Aleo lowering: loop header must compute `i < end`"
  let depth := loops.size
  let envLoop := envInsert env paramDef.valueId (.loopVar depth)
  let loops' := loops.push { header := target.blockId }
  match header.terminator with
  | .branch condVid thenTarget _ => do
      match condVid? with
      | some expected =>
          unless condVid == expected do
            planError "Aleo lowering: loop branch condition does not match the header computation"
      | none => planError "Aleo lowering: loop header branch condition is missing"
      let thenRes ← lowerRegion data layout callable fnNames thenTarget.blockId.toNat loops' envLoop ls
      unless thenRes.join?.isNone do
        planError "Aleo lowering: loop body must end at the latch back edge"
      let body := thenRes.stmts
      let maxIter := lb.maxIterations.toNat
      unless maxIter ≤ 4096 do
        planError "Aleo lowering: loop bound exceeds the wire maximum"
      let forStmt := .forLoop startExpr endExpr maxIter body
      match header.terminator with
      | .branch _ _ elseTarget =>
          lowerRegion data layout callable fnNames elseTarget.blockId.toNat loops env
            { ls with stmts := ls.stmts.push forStmt }
      | _ => planError "Aleo lowering: loop header must end in a branch"
  | _ => planError "Aleo lowering: loop header must end in a branch"

end
/-- Resolve a callable result to (isBool, isUnit, isInt64, isUInt8). -/
private def resultShape (data : SemanticProgramDataV1) (types : AleoTypeClosureV1)
    (callable : CallableV1) :
    CompileResult (Bool × Bool × Bool × Bool × Bool) := do
  if isBoolType data callable.result.typeId then pure (true, false, false, false, false)
  else if isUInt64Type data callable.result.typeId then pure (false, false, false, false, false)
  else if isInt64Type data callable.result.typeId then pure (false, false, true, false, false)
  else if isUInt8Type data callable.result.typeId then pure (false, false, false, true, false)
  else if isBls12377FieldType types callable.result.typeId then pure (false, false, false, false, true)
  else if (match data.types[callable.result.typeId.toNat]? with
      | some { shape := .unit, .. } => true | _ => false) then pure (false, true, false, false, false)
  else planError "Aleo callable result is outside the public UInt64/Int64/UInt8/Bool/BLS12-377-Field/Unit envelope"

private partial def touchesStateExpr : Expr → Bool
  | .stateLoad _ => true
  | .checkedAdd l r | .checkedSub l r | .checkedMul l r | .checkedDiv l r
  | .checkedMod l r | .bitAnd l r | .bitOr l r | .bitXor l r
  | .logicalAnd l r | .logicalOr l r | .shl l r | .shr l r
  | .signedCheckedAdd l r | .signedCheckedSub l r | .signedCheckedMul l r
  | .signedCheckedDiv l r | .signedCheckedMod l r | .signedShl l r | .signedShr l r
  | .signedBitAnd l r | .signedBitOr l r | .signedBitXor l r =>
      touchesStateExpr l || touchesStateExpr r
  | .compare _ l r | .signedCompare _ l r => touchesStateExpr l || touchesStateExpr r
  | .bitNot o | .boolNot o | .checkedNeg o | .signedBitNot o | .u8BitNot o => touchesStateExpr o
  | .u8To64 o | .narrow8 o => touchesStateExpr o
  | .u8Shl l r | .u8Shr l r => touchesStateExpr l || touchesStateExpr r
  | .ternary c t e => touchesStateExpr c || touchesStateExpr t || touchesStateExpr e
  | .callFn _ args => args.any touchesStateExpr
  | _ => false

/-- Does a statement list read or write mappings? -/
private partial def touchesStateStmts (stmts : Array Statement) : Bool :=
  stmts.any fun stmt =>
    match stmt with
    | .store _ _ | .storeAggregate _ => true
    | .returnValue e => touchesStateExpr e
    | .ifThenElse _ t e => touchesStateStmts t || touchesStateStmts e
    | .switchOn _ cases d => cases.any (fun (_, b) => touchesStateStmts b) || touchesStateStmts d
    | .forLoop _ _ _ b => touchesStateStmts b
    | _ => false

inductive CallableLowering where
  | asFunction (fn : PlanFunction)
  | asView (view : PlanView)
  deriving Inhabited

/-- Lower one callable into a plan function or a bare view descriptor. -/
private partial def lowerCallable
    (data : SemanticProgramDataV1) (layout : AleoLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String)) :
    CompileResult CallableLowering := do

  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty do
    planError "Aleo lowering: callable must have entry block 0"
  -- Pre-validate the loop pattern (single-param headers, branch + latch).
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      planError "Aleo lowering: loop header block is missing"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      planError "Aleo lowering: loop latch block is missing"
    unless header.params.size == 1 do
      planError "Aleo lowering: loop header must carry one UInt64 parameter"
    match header.terminator with
    | .branch .. => pure ()
    | _ => planError "Aleo lowering: loop header must end in a branch"

    match latch.terminator with
    | .jump t =>
        unless t.blockId == lb.header && t.args.size == 1 do
          planError "Aleo lowering: loop latch must jump back with one argument"
    | _ => planError "Aleo lowering: loop latch must jump back to the header"
  for blk in callable.blocks do
    unless blk.params.isEmpty ||
        callable.loopBounds.any (fun lb => lb.header == blk.id) do
      planError "Aleo lowering: block parameters are only supported on loop headers"
  -- Params.
  let mut params : Array PlanParam := #[]
  let mut paramIndex : Nat := 0
  for p in callable.params do
    let isBool ← if isBoolType data p.typeId then pure true
      else if isUInt64Type data p.typeId then pure false
      else if isInt64Type data p.typeId then pure false
      else if isUInt8Type data p.typeId then pure false
      else if isBls12377FieldType layout.types p.typeId then pure false
      else planError "Aleo callable parameter is outside the UInt64/Int64/UInt8/Bool/BLS12-377-Field envelope"
    params := params.push {
      sourceIndex := paramIndex, name := p.name, isBool
      isInt := isInt64Type data p.typeId
      isU8 := isUInt8Type data p.typeId
      isField := isBls12377FieldType layout.types p.typeId }
    paramIndex := paramIndex + 1
  -- Seed the value env with callable params (source-indexed), then walk the
  -- body from the entry block.
  let mut env0 : ValueEnv := default
  let mut paramOrdinal : Nat := 0
  for p in callable.params do
    if isInt64Type data p.typeId then
      env0 := envInsertInt env0 p.valueId (.param paramOrdinal)
    else if isUInt8Type data p.typeId then
      env0 := envInsertU8 env0 p.valueId (.param paramOrdinal)
    else if isBls12377FieldType layout.types p.typeId then
      env0 := envInsertVal env0 p.valueId (mkScalarFieldVal (.param paramOrdinal))
    else
      env0 := envInsert env0 p.valueId (.param paramOrdinal)
    paramOrdinal := paramOrdinal + 1
  let res ← lowerRegion data layout callable fnNames 0 #[] env0 { stmts := #[] }
  unless res.join?.isNone do
    planError "Aleo lowering: callable does not end in return on all paths"
  let body := res.stmts
  let (resultIsBool, resultIsUnit, resultIsInt, resultIsU8, resultIsField) ←
    resultShape data layout.types callable
  -- Bare view: body is exactly `return <stateLoad f>`.
  let bareView? : Option PlanView :=
    match callable.kind, body.toList with
    | .view, [.returnValue (.stateLoad f)] =>
        match callable.name with
        | some n => some { name := n, stateFieldIndex := f }
        | none => none
    | _, _ => none
  match bareView? with
  | some view => return (.asView view)
  | none => pure ()
  -- Ordinary function.
  let kind := match callable.kind with
    | .initializer => FunctionKind.initialize
    | _ => FunctionKind.mutate
  let touchesState := touchesStateStmts body
  -- Computed state-reading views fail closed (only bare reads map to the
  -- off-chain query model).
  if callable.kind == .view && touchesState then
    planError "Aleo computed views that read state fail closed: only bare public-state reads map to leo query"
  let resultDropped := !resultIsUnit && touchesState
  let isPureHelper := callable.kind == .pureFn
  let name ← match callable.name with
    | some n => pure n
    | none => pure "initialize"
  pure (.asFunction {
    index := 0
    name
    kind
    params
    body
    touchesState
    resultIsBool
    resultIsInt
    resultIsU8
    resultIsField
    resultDropped
    isPureHelper
  })

/-- Assembly entry: wire semantic data → target-owned Plan. -/
private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  -- Type-closure: Field fail closed; named + Array admitted (H3).
  let types ← validateAleoTypeClosureV1 data.types
  let layout ← makeStateLayoutV1 types data.types data.logicalState
  let fnNames := data.callables.filterMap fun c =>
    match c.kind with
    | .pureFn => some (c.id, c.name.getD "fn")
    | _ => none
  let mut functions : Array PlanFunction := #[]
  let mut views : Array PlanView := #[]
  for callable in data.callables do
    match callable.kind with
    | .invariant =>
        planError "Aleo does not support invariants in this slice"
    | .initializer | .entry | .view | .pureFn =>
        match ← lowerCallable data layout callable fnNames with
        | .asFunction fn =>
            functions := functions.push { fn with index := functions.size }
        | .asView view =>
            views := views.push view
  let plan := {
    programName
    stateFieldNames := layout.fieldNames
    stateFieldIsInt := layout.fieldIsInt
    stateFieldIsU8 := layout.fieldIsU8
    stateFieldIsField := layout.fieldIsField
    functions
    views
    sourceHash
    semanticHash
  }
  pure plan

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Aleo received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash


private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"


/-- Internal Aleo family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .aleo do
    throw <| .planInvariant .aleo "engineering capability kind is not Aleo"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Aleo source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Aleo semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Aleo
