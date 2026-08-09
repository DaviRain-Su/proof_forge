import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Targets.Psy.PfAssetsDispositionV1

/-!
# Psy LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Psy-owned Plan surface and the retained-`SemanticProgramV1` Plan body
for the public UInt64 envelope (comparisons, bare assert, Bool results,
if/match, revert/emit, fn/localCall, let, bounded for, shift/bitwise/logical,
call/schedule). Plan canonicity lives in `ValidatePlanV1`; canonical DPN
package emission in `Dpn`; `FinalizeV1` remains a separate submodule.

**ADR-0029 Phase D**: every `pf.assets` catalog QN is **unbound** on Psy
(`PfAssetsDispositionV1`). Catalog calls fail closed at Plan with an explicit
unbound diagnostic. Non-catalog L0 sync calls lower to the target DPN
external-call instruction.

Psy maps UInt{8,16,32,64} → `Felt` (narrow widths are **Felt-carried**, not
native Psy U32 operations — their arithmetic/shift behavior is not faithful to
the Reference machine). Bool → `bool`. Checked u64 arithmetic uses the
Goldilocks field modulus.
**Narrow UInt{8,16,32}** body ops use the same Felt operators with
**explicit width guards** (`result < 2^w` after add/mul/shl; underflow/zero/
`count < w` otherwise). Reasoning: max product of two UInt32 values is
`(2^32−1)^2 = 2^64−2^33+1 < p = 2^64−2^32+1`, so narrow ops never wrap mod p
when operands are in-range — width bounds alone recover checked semantics.
Unary `~` on narrow widths is `x ^ (2^w−1)` as Felt (mask is a legal Felt
literal). **UInt64 bitNot** lowers to `checkedBitNot` (Felt representability
guard). Int64 bitNot and UInt128/256 / narrow Int stay fail-closed.

**Field is exact-spec gated.** Native Psy `Felt` is plonky2 Goldilocks
(`ORDER = 0xFFFFFFFF00000001`), so the target admits only catalog Goldilocks;
bn254 Fr and BLS12-377 Fr fail closed via `pilotFieldPolicyGoldilocks`.

## H3 PsyAleoAggregate (2026-08-02)

Named Struct/Enum and fixed-length `Array UInt64 N` are **LOWERED** by
flattening to consecutive Felt storage leaves (`name_field` / `name_i`).
Plan Expr remains scalar-only: construct/fieldGet/fieldSet/variantTag/
variantPayload/indexGet/indexSet operate in the lowering value env only.
PSY-SCALAR-ABI admits fixed Bytes 1..8 as N×UInt8 Felt leaves and
Principal/String wire identity as len+8×UInt32 (max 32B payload; returns FC
at 9 > B-RET cap 8). Array/Bytes IndexGet/IndexSet accept compile-time UInt literals or **runtime**
UInt indices with exact `indexOutOfBounds` assert (PSY-INDEX-CAST).
**PSY-CONTAINER-ABI** admits dense `Map UInt64 UInt64`
state (cap-8 × occ/key/val = 24 Felt leaves; empty + IndexGet→Option +
IndexSet upsert + atomic storeAggregate) and named Struct/Enum **params** as
preorder multi-leaf Felt formals. Nested Map, Map return, Map non-UInt64
K/V, and >8 aggregate return stay fail closed because no target-owned
resource proof permits raising the B-RET cap.

## B-RET-ABI named Struct/Enum entry/view returns (2026-08-03)

Named Struct/Enum **entry/view** results flatten to 1..8 preorder UInt64/Int64
leaves (`ResultKind.aggregate` + `Statement.returnAggregate`, appended at the
end of the Statement ctor space). DPN emission returns one honest aggregate
with 1..8 Felt leaves. PureFn aggregate returns and >8 leaves stay fail closed;
named aggregate **params** are open under PSY-CONTAINER-ABI (scalar leaf
fields only).

## N-ANON-RESULT anonymous Array/Option entry/view returns (BL-25)

Anonymous `Array UInt64 N` (1..8), `Option UInt64`, and fixed `Bytes N`
(1..8) entry/view results reuse the same preorder-leaf + `[Felt; N]` path:
Array → N Felt leaves; Option → `[Felt; 2]` tag+payload (`none=[0,0]`,
`some=[1,v]`); Bytes → N×UInt8 Felt leaves. Map return and nested/
non-UInt64-element anonymous returns stay fail closed. Option is admitted as
a body intermediate via container policy `ArrayMapBytes`. Map **state** is
the dense UInt64 pilot (PSY-CONTAINER-ABI), not a Map return.

## B-OPT-STATE Option UInt64 state (BL-36)

Anonymous `Option UInt64` **state** is admitted as Enum-shaped 2-leaf Felt
storage (`name_tag` + `name_p0`; `none=(0,0)`, `some=(1,v)`; none-assign
zeroes payload). Default zero-init matches none. Reads go through the existing
VariantTag/VariantPayload path (Option payload fallback when the base is not a
named Enum). Non-UInt64 payload, nested Option, and Option params stay fail
closed (mirrors Enum param policy).

## PSY-CONTEXT-COMMIT (evidence fail closed, 2026-08-08)

ContextRead (`unixTimeSeconds` / `caller` / `blockHeight` / unknown) and
Commit stay **fail closed** with key-specific diagnostics. Psy is circuit-
domain: the DPN contract has no bound public-input/witness source for
wall-clock, caller, or height. Unanchored injection is not chain reality.
Commit cannot open as Felt identity passthrough without a frozen
proof/public-input/commitment binding (B-COMMIT-ZK). EnvRead remains
ADR-0029 zero-binding FC.

## PSY-INVARIANT (evidence fail closed, 2026-08-08)

Nonempty Semantic `.invariant` callables / `InvariantDecl` rows stay **fail
closed**. The DPN schema has no predicate-closure carrier bound to the same
closure DAG and `invariantSteps` fuel as Semantic/Wire. Emitting unused
asserts would overclaim target refinement.
Inline product `check` certification (ADR-0027) is orthogonal and is **not**
target Plan lowering of invariants. Empty invariants remain admitted.

## PSY-TYPED-ERROR (2026-08-08)

Zero-payload declared errors are encoded as string-tagged DPN asserts:
`revert Name` → an always-failing assert tagged `revert:Name`; zero-arg
`assert c else Name` → an assert tagged `assert:Name`. Parameterized error
payloads stay fail closed because the DPN contract has no structured selector
or payload ABI. Bare assert and zero-arg paths remain stable.

## PSY-CALL-EVENT (2026-08-08, PARTIAL + evidence FC)

Void sync `call` → DPN `InvokeExternalContractFunctionSync` with static
qualified-name hashing and zero outputs. `emit` → DPN `events[]`. These remain
PARTIAL: no deployment-address binding, callee-failure refinement, ordered-log
runtime gate, or response ABI. Result-bearing call and `schedule` stay fail
closed. `pf.assets` catalog QNs remain unbound (ADR-0029).

## PSY-ASYNC-ASSETS (2026-08-08, evidence FC — no capability open)

`schedule` stays declined (resolver + Plan; no deferred form). Every
`pf.assets` catalog QN stays unbound (ADR-0029 Phase D zero-binding).
The DPN synchronous invoke operation must not be relabeled as async or as
native vault transfer; either admit requires a frozen native binding.

## PSY-LOOP (2026-08-08)

The DPN schema has no `for` operation. UInt64 bounded `for` lowers to a static
unroll of `maxIterations` (≤64) guarded steps after `boundExceeded`
(`end - start ≤ N`), preserving exact iteration semantics. Non-UInt64
(narrow UInt/Int) induction stays fail closed. Larger bounds fail closed at
the DPN unroll budget.
-/

namespace ProofForgeV2.Targets.Psy

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1
open ProofForgeV2.Targets.Psy.PfAssetsDispositionV1

/-- Sole Psy DPN profile. -/
def psyCodegenProfileIdString : String := "psy-dpn-v1"

private def validateCodegenProfileV1
    (profile : CodegenProfileId) : CompileResult Unit :=
  unless profile == CodegenProfileId.psyDpnV1 do
    .error <| .planInvariant .psy s!"unsupported Psy codegen profile '{profile}'"

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

/-- T14 catalog v2 (Goldilocks): native Felt field arithmetic operator.
    Felt is a field element, so each op is exact mod Goldilocks (no overflow). -/
inductive FieldArithOp where
  | add | sub | mul | div
  deriving BEq, Inhabited, Repr

/-- Which exact UInt128 div/mod result a target-owned restoring binding exposes. -/
inductive WideUInt128DivModResultV1 where
  | quotient
  | remainder
  deriving BEq, Inhabited, Repr

/-- Direction of an exact UInt128 shift binding (count is UInt32 Felt). -/
inductive WideUInt128ShiftKindV1 where
  | shl
  | shr
  deriving BEq, Inhabited, Repr

/-- Target-owned Psy Plan expression over the public UInt{8,16,32,64}/Bool
    envelope. Narrow widths are Felt-carried with explicit width guards at
    emission (not native Psy uN — VM uN ops are unfaithful to Reference). -/
inductive Expr where
  | literal (value : UInt64)
  | boolLiteral (value : Bool)
  | param (inputIndex : Nat)
  | loopVar (loopDepth : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  /-- Narrow UInt{8,16,32} checked arith as Felt + `result < 2^w` / underflow. -/
  | narrowCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | bitAnd (lhs rhs : Expr)
  | bitOr (lhs rhs : Expr)
  | bitXor (lhs rhs : Expr)
  /-- Narrow UInt{8,16,32} bitwise (Felt; result stays in-range if operands do). -/
  | narrowBitAnd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitOr (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitXor (bitWidth : Nat) (lhs rhs : Expr)
  | logicalAnd (lhs rhs : Expr)
  | logicalOr (lhs rhs : Expr)
  | shl (lhs rhs : Expr)
  | shr (lhs rhs : Expr)
  /-- Narrow UInt{8,16,32} shift: `count < bitWidth` + post-shl width guard. -/
  | narrowShl (bitWidth : Nat) (lhs rhs : Expr)
  | narrowShr (bitWidth : Nat) (lhs rhs : Expr)
  | boolNot (operand : Expr)
  /-- Historical u32-typed literal (loop counters only). Narrow program
      literals lower as Felt `.literal` with width tracking on LoweredVal. -/
  | u32Literal (value : UInt64)
  /-- T14 catalog v2 (Goldilocks): native Felt field literal. The value is the
      raw Goldilocks field element (`< p`); emitted as a Felt decimal literal
      reduced mod `0xFFFFFFFF00000001`. Carries no checked-arith guard. -/
  | fieldLiteral (value : UInt64)
  /-- T14 catalog v2 (Goldilocks): native Felt field arithmetic. Felt is a
      field element so the op is exact mod Goldilocks — no checked-overflow
      guard. `op` is one of add/sub/mul/div. -/
  | fieldBinary (op : FieldArithOp) (lhs rhs : Expr)
  /-- T14 catalog v2 (Goldilocks): native Felt field equality (eq/ne only;
      Felt has no ordering). Emitted as a Felt `==`/`!=` comparison. -/
  | fieldCompare (op : ComparisonOp) (lhs rhs : Expr)
  /-- T14 catalog v2 (Goldilocks): native Felt field negation `0 - x`
      (Goldilocks inverse; no intMin revert). -/
  | fieldNeg (operand : Expr)
  /-- Narrow UInt{8,16,32} bitwise-not: Felt `x ^ (2^w−1)` (mask literal).
      The target deliberately avoids a native-u32 lowering lane. -/
  | narrowBitNot (bitWidth : Nat) (operand : Expr)
  /-- Checked UInt64 bitwise-not. Exact `bitNot x = (2^64−1) − x` is a legal
      Felt iff `x ≥ 2^32−1` (result `< p = 2^64−2^32+1`). Emission asserts the
      threshold then does wrapping Felt sub `(2^32−2) − x`
      (`2^32−2 ≡ 2^64−1 (mod p)`); when the guard holds the field result equals
      the exact UInt64 bitNot. Boundary matrix: `x=0` / `x=2^32−2` trap;
      `x=2^32−1` → `p−1`; `x=UInt64.max` is not a Felt value (domain is
      `[0,p)`), so the runtime surface is the representable half only — never
      silent mod-p bitNot for the unrepresentable half. -/
  | checkedBitNot (operand : Expr)
  /-- Checked Int64 negation (intMin reverts at emission). -/
  | checkedNeg (operand : Expr)
  /-- Signed Int64 comparison (Felt signed interpretation at emission). -/
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  /-- T9c-style: Int{8,16,32} two's-complement bit-pattern ops on Felt.
      Values live in `0..2^w-1`; emission uses wrap + sign-bit overflow gates. -/
  | narrowSignedCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCompare (bitWidth : Nat) (op : ComparisonOp) (lhs rhs : Expr)
  | narrowCheckedNeg (bitWidth : Nat) (operand : Expr)
  | callFn (fnName : String) (args : Array Expr)
  /-- Target-internal exact limb arithmetic. Operands are range-bounded
      UInt32 Felt limbs/intermediates, so these raw Felt operations cannot wrap
      Goldilocks in the admitted UInt128 add/sub construction. -/
  | limbAdd (lhs rhs : Expr)
  | limbSub (lhs rhs : Expr)
  /-- Reference to one result limb produced by an earlier
      `Statement.bindWideUintMul` in the same lexical statement region.
      `operationId` is the Semantic ValueId ordinal of the multiplication;
      `limbIndex` is little-endian in `0..3`. -/
  | wideUintMulLimb (bitWidth operationId limbIndex : Nat)
  /-- Reference to one quotient/remainder limb produced by an earlier exact
      `Statement.bindWideUintDivMod` restoring-divider binding. -/
  | wideUintDivModLimb (resultKind : WideUInt128DivModResultV1)
      (bitWidth operationId limbIndex : Nat)
  /-- Reference to one result limb produced by an earlier exact
      `Statement.bindWideUintShift` (UInt32 count; fixed 128-step bit walk). -/
  | wideUintShiftLimb (kind : WideUInt128ShiftKindV1)
      (bitWidth operationId limbIndex : Nat)
  /-- Felt-valued conditional used to materialize carry/borrow without field
      division. `condition` is Bool; both branches are Felt expressions. -/
  | select (condition thenValue elseValue : Expr)
  deriving BEq, Inhabited, Repr

inductive Statement where
  | store (fieldIndex : Nat) (value : Expr)
  | assert (condition : Expr)
  | returnValue (value : Expr)
  | returnNone
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  | forLoop (start endExclusive : Expr) (maxIterations : Nat)
      (body : Array Statement)
  | emitEvent (eventIndex : Nat) (args : Array Expr)
  | revertError (errorIndex : Nat) (args : Array Expr)
  | bareRevert
  | externalCall (callee : Array String) (args : Array Expr)
  | schedule (callee : Array String) (args : Array Expr)
  /-- B-RET-ABI (appended; never renumber prior ctors): multi-leaf named
      Struct/Enum or admitted anonymous Array/Option return. `leaves` are
      preorder flatten expressions; `leafIsInt` is parallel (i64 vs u64 ABI).
      Emission packs as one Psy `[Felt; N]` return value (honest multi-leaf
      form on the Psy surface). -/
  | returnAggregate (leaves : Array Expr) (leafIsInt : Array Bool)
  /-- Target-internal checked-arithmetic guard with a stable runtime message.
      Appended so historical Plan constructor order remains unchanged. -/
  | assertWithMessage (condition : Expr) (message : String)
  /-- Atomic multi-leaf state update: the emitter snapshots every value into a
      local before writing any field, preventing store-then-read hazards. -/
  | storeAggregate (fieldIndices : Array Nat) (values : Array Expr)
  /-- Checked UInt128 multiplication binding for the direct DPN profile.
      The emitter freezes an exact 8×UInt16 schoolbook algorithm: every bit
      operation sees a value below 2^32, all Felt arithmetic intermediates stay
      below Goldilocks, and any nonzero high 128-bit digit traps before stores.
      Four little-endian result limbs become available through
      `Expr.wideUintMulLimb operationId 0..3`. -/
  | bindWideUintMul (bitWidth operationId : Nat) (lhs rhs : Array Expr)
  /-- Exact UInt128 unsigned division/remainder for the direct DPN profile.
      The emitter owns a fixed 129-bit restoring algorithm implemented as four
      constant 32-step loops over range-bounded Felt limbs; Psy field `/` and
      `%` are never used for the integer result. -/
  | bindWideUintDivMod (resultKind : WideUInt128DivModResultV1)
      (bitWidth operationId : Nat) (lhs rhs : Array Expr)
  /-- Exact UInt128 logical shift for the direct DPN profile. `value` is four
      little-endian UInt32 Felt limbs; `count` is a UInt32 Felt in `0..127`.
      The emitter owns a fixed 128-step bit walk (no Psy field `/` for whole/rem
      limb split); `shl` traps on any bit shifted past bit 127. -/
  | bindWideUintShift (kind : WideUInt128ShiftKindV1) (bitWidth operationId : Nat)
      (value : Array Expr) (count : Expr)
  deriving BEq, Inhabited, Repr

/-- ABI type of one aggregate return leaf. B-RET-ABI pilot: leaves are
UInt64/Int64 words (`isInt` selects i64 vs u64); `byteWidth` is 8. -/
structure LeafAbiType where
  isInt : Bool
  byteWidth : Nat
  deriving BEq, Inhabited, Repr

/-- Entry/view/pureFn result ABI kind. Scalar UInt{8,16,32,64}/Int64/Field all
    render as Felt (narrow = single Felt with documented `resultUintWidth`);
    B-RET-ABI `.aggregate` packs 1..8 UInt64/Int64 leaves as one Psy
    `[Felt; N]` return (named Struct/Enum + admitted anonymous Array UInt64 N /
    Option UInt64). Map/Bytes/nested stay FC. -/
inductive ResultKind where
  /-- Scalar Felt (UInt{8,16,32,64}/Int64/Goldilocks Field). -/
  | felt
  | bool
  | unit
  /-- B-RET-ABI: named Struct/Enum or admitted anonymous Array/Option
  aggregate return. `leaves` is preorder flatten order (1..8). -/
  | aggregate (leaves : Array LeafAbiType)
  deriving BEq, Inhabited, Repr

inductive FunctionKind where
  | initialize
  | mutate
  | pureHelper
  deriving BEq, Inhabited, Repr

structure PlanParam where
  sourceIndex : Nat
  name : String
  isBool : Bool
  /-- Unsigned width in bits: 0 or 64 → Felt UInt64; 8/16/32 → Felt-carried
      narrow (entry range-checked). Historical `isU32` is recovered as
      `uintWidth == 32`. -/
  uintWidth : Nat := 0
  /-- T14 catalog v2 (Goldilocks): native Felt field parameter. -/
  isField : Bool := false
  deriving BEq, Inhabited, Repr

/-- True when the param is a Felt-carried UInt32 (T8 multi-width). -/
def PlanParam.isU32 (p : PlanParam) : Bool := p.uintWidth == 32

structure PlanFunction where
  index : Nat
  name : String
  kind : FunctionKind
  params : Array PlanParam
  body : Array Statement
  resultIsBool : Bool
  resultIsUnit : Bool
  /-- Result unsigned width: 0/64 → UInt64 Felt; 8/16/32 → narrow Felt scalar.
      Emission always uses `-> Felt` for UInt results (BL-7 single-Felt model). -/
  resultUintWidth : Nat := 0
  /-- B-RET-ABI result kind. When `.aggregate`, scalar flags are false and body
      paths end in `returnAggregate`. Default `.felt` keeps historical scalar
      defaults for structure literals that omit the field. -/
  resultKind : ResultKind := .felt
  deriving BEq, Inhabited, Repr

/-- True when the function returns Felt-carried UInt32. -/
def PlanFunction.resultIsU32 (fn : PlanFunction) : Bool := fn.resultUintWidth == 32

structure PlanEvent where
  name : String
  fieldNames : Array String
  deriving BEq, Inhabited, Repr

structure PlanErrorDecl where
  name : String
  fieldNames : Array String
  deriving BEq, Inhabited, Repr

/-- Target-owned Psy Plan. Retains no SemanticProgram; carries digests and
    artifact program name. -/
structure Plan where
  programName : String
  /-- DPN is the sole product IR and therefore needs no target-language mode. -/
  stateFieldNames : Array String
  functions : Array PlanFunction
  events : Array PlanEvent
  errors : Array PlanErrorDecl
  sourceHash : String
  semanticHash : String
  deriving BEq, Inhabited, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .psy message

/-- Psy pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Field stays on `pilotFieldPolicyNone`: Felt is Goldilocks, not bn254 Fr. -/
private abbrev PsyTypeClosureV1 := PilotTypeClosureV1

private def psyPlanErr (message : String) : CompileError :=
  .planInvariant .psy message

/-- Psy DPN admits every implemented unsigned width, including its
    UInt128/256 little-endian UInt32-limb representation. -/
private def pilotUintWidthPolicyPsyBody : PilotUintWidthPolicy where
  admittedWidths := #[256, 128, 64, 32, 16, 8]

/-- True for Felt-carried narrow UInt widths admitted by the Psy T8 pilot. -/
def isNarrowUintWidth (bitWidth : Nat) : Bool :=
  bitWidth == 8 || bitWidth == 16 || bitWidth == 32

/-- Psy pilot accepts anonymous UInt{8,16,32,64}/Unit/Bool/Int64 under the T8
    multi-width + Int64 policies, plus **named Struct/Enum** and **Array**
    (H3 PsyAleoAggregate: flatten-to-Felt leaves). Field is Goldilocks only.
    Container policy is **ArrayMap** so anonymous `Option` may appear as a body
    intermediate for N-ANON-RESULT returns and (B-OPT-STATE) as `Option UInt64`
    storage (shared Envelope gate keys Option on `admitMap`; Option is never
    pushed to `containerTypeIds`). Map **state** still fail-closes at layout.
    Bytes 1..8 and Principal/String wire identity admitted (SCALAR-ABI).
    Narrow Int{8,16,32} admitted as two's-complement bit patterns in Felt
    (full range fits below Goldilocks p). -/
private def validatePsyTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult PsyTypeClosureV1 :=
  validatePilotTypeClosure psyPlanErr psyTypeClosureWording types
    pilotUintWidthPolicyPsyBody
    (intPolicy := pilotIntWidthPolicyNarrow)
    (fieldPolicy := pilotFieldPolicyGoldilocks)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (stringPolicy := pilotStringPolicyAdmit)
    -- ArrayMapBytes: Array + Option intermediates + fixed Bytes 1..8.
    -- Map state still fail-closes in flatten/makeStateLayout.
    (containerPolicy := pilotContainerStatePolicyArrayMapBytes)

-- ---------------------------------------------------------------------------
-- Wire semantic → target-owned Plan lowering
-- ---------------------------------------------------------------------------

private def maxIdentifierBytes : Nat := 240
private def maxStateLeafFields : Nat := 256
/-- PSY-SCALAR-ABI: Principal/String storage is full wire identity
    `u32le(len)||body` flattened to `len` + 8×UInt32 body limbs (max 32B
    payload). Not an address / Felt scalar. Returns stay FC (9 > B-RET cap 8). -/
private def psyWireIdentityBodyLimbCountV1 : Nat := 8
private def psyWireIdentityMaxPayloadBytesV1 : Nat := 32
private def psyBytesMaxLenV1 : Nat := 8
/-- PSY-CONTAINER-ABI dense Map UInt64 UInt64 pilot (NS-1 pattern): cap-8 ×
    (occ, key, val) = 24 Felt leaves. Matches EVM/Solana/NEAR/Noir capacity;
    not a native Psy `Map` type. -/
private def psyMapPilotCapacityV1 : Nat := 8
private def psyMapSlotsPerEntryV1 : Nat := 3
private def psyMapPilotLeafCountV1 : Nat :=
  psyMapPilotCapacityV1 * psyMapSlotsPerEntryV1

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

/-- Scalar + optional multi-leaf aggregate carrier (H3). SSA ValueIds are
    defined once; `leaves? = some` means fixed-width flattened Struct/Enum/Array.
    `uintWidth ∈ {8,16,32}` marks Felt-carried narrow UInt; 0/64 = UInt64 Felt. -/
private structure LoweredVal where
  expr : Expr
  leaves? : Option (Array Expr) := none
  /-- Scalar unsigned width: 0/64 = UInt64 Felt; 8/16/32 = Felt-carried narrow. -/
  uintWidth : Nat := 0
  /-- Scalar signed width: 0 = not Int; 8/16/32/64 = two's-complement Felt carrier. -/
  intWidth : Nat := 0
  /-- VM profile software-wide marker: 128 means four little-endian UInt32
      Felt limbs in `leaves?`; 0 means scalar or ordinary aggregate. -/
  wideUintWidth : Nat := 0
  /-- T14 catalog v2 (Goldilocks): scalar Felt field value. Selects native
      field arithmetic (no checked-overflow guard) and Felt-typed emission. -/
  isField : Bool := false
  /-- Dense Map UInt64 UInt64 pilot aggregate (24 occ/key/val leaves). -/
  isMapPilot : Bool := false
  deriving Inhabited

private def LoweredVal.isAggregate (v : LoweredVal) : Bool :=
  v.leaves?.isSome

private def LoweredVal.leafExprs (v : LoweredVal) : Array Expr :=
  match v.leaves? with
  | some ls => ls
  | none => #[v.expr]

/-- True when this scalar is Felt-carried UInt{8,16,32}. -/
private def LoweredVal.isNarrow (v : LoweredVal) : Bool :=
  isNarrowUintWidth v.uintWidth

/-- True when this scalar is Felt-carried Int{8,16,32}. -/
private def isNarrowIntWidth (bitWidth : Nat) : Bool :=
  bitWidth == 8 || bitWidth == 16 || bitWidth == 32

private def LoweredVal.isNarrowInt (v : LoweredVal) : Bool :=
  isNarrowIntWidth v.intWidth

private def LoweredVal.isInt (v : LoweredVal) : Bool :=
  v.intWidth == 8 || v.intWidth == 16 || v.intWidth == 32 || v.intWidth == 64

/-- Historical alias: UInt32 Felt-carried scalar. -/
private def LoweredVal.isU32 (v : LoweredVal) : Bool := v.uintWidth == 32

private def mkScalarVal (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, uintWidth := 0, intWidth := 0, isField := false }

private def mkNarrowVal (bitWidth : Nat) (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, uintWidth := bitWidth, intWidth := 0, isField := false }

private def mkNarrowIntVal (bitWidth : Nat) (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, uintWidth := 0, intWidth := bitWidth, isField := false }

private def mkInt64Val (e : Expr) : LoweredVal :=
  mkNarrowIntVal 64 e

private def mkU32Val (e : Expr) : LoweredVal :=
  mkNarrowVal 32 e

/-- T14 catalog v2 (Goldilocks): scalar Felt field value carrier. -/
private def mkFieldVal (e : Expr) : LoweredVal :=
  { expr := e, leaves? := none, uintWidth := 0, intWidth := 0, isField := true }

private def mkAggregateVal (leaves : Array Expr) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves, uintWidth := 0,
    wideUintWidth := 0, isField := false, isMapPilot := false }

private def mkMapPilotVal (leaves : Array Expr) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves, uintWidth := 0,
    wideUintWidth := 0, isField := false, isMapPilot := true }

private def mkWideUInt128Val (leaves : Array Expr) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves, uintWidth := 0,
    wideUintWidth := 128, isField := false, isMapPilot := false }

private def mkWideUInt256Val (leaves : Array Expr) : LoweredVal :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head, leaves? := some leaves, uintWidth := 0,
    wideUintWidth := 256, isField := false, isMapPilot := false }

private def LoweredVal.isWideUInt128 (v : LoweredVal) : Bool :=
  v.wideUintWidth == 128 && v.leafExprs.size == 4

private def LoweredVal.isWideUInt256 (v : LoweredVal) : Bool :=
  v.wideUintWidth == 256 && v.leafExprs.size == 8

private def LoweredVal.isWideUint (v : LoweredVal) : Bool :=
  v.isWideUInt128 || v.isWideUInt256

private def wideLimbCountOf (bitWidth : Nat) : Nat := bitWidth / 32

private def mkWideUintVal (bitWidth : Nat) (leaves : Array Expr) : LoweredVal :=
  if bitWidth == 256 then mkWideUInt256Val leaves else mkWideUInt128Val leaves

private structure ValueEnv where
  entries : Array (ValueIdV1 × LoweredVal)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option LoweredVal :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envLookupExpr (env : ValueEnv) (id : ValueIdV1) : Option Expr :=
  (envLookup env id).map (·.expr)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  { env with entries := env.entries.push (id, mkScalarVal e) }

private def envInsertNarrow (env : ValueEnv) (id : ValueIdV1) (bitWidth : Nat) (e : Expr) :
    ValueEnv :=
  { env with entries := env.entries.push (id, mkNarrowVal bitWidth e) }

private def envInsertU32 (env : ValueEnv) (id : ValueIdV1) (e : Expr) : ValueEnv :=
  envInsertNarrow env id 32 e

private def envInsertVal (env : ValueEnv) (id : ValueIdV1) (v : LoweredVal) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

/-- Flattening layout: physical Felt leaf names + per-logical-state leaf ranges. -/
private structure PsyLowerLayoutV1 where
  fieldNames : Array String
  stateLeaves : Array (Array Nat)
  typeDecls : Array TypeDeclV1
  types : PsyTypeClosureV1

private def isUInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 64, .. } => true
  | _ => false

private def isInt64Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .int 64, .. } => true
  | _ => false

private def intWidthOfType
    (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Option Nat :=
  match data.types[typeId.toNat]? with
  | some { shape := .int w, .. } =>
      if w == 8 || w == 16 || w == 32 || w == 64 then some w.toNat else none
  | _ => none

private def isNarrowIntType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match intWidthOfType data typeId with
  | some w => isNarrowIntWidth w
  | none => false

private def isBoolType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .bool, .. } => true
  | _ => false

private def isUInt32Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 32, .. } => true
  | _ => false

private def isUInt16Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 16, .. } => true
  | _ => false

private def isUInt8Type (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint 8, .. } => true
  | _ => false

/-- Resolve anonymous UInt TypeId to a Psy-recognized bit width. UInt128/256
    are admitted only after the profile-bound type-closure gate and are
    represented as little-endian UInt32 Felt limbs (4 / 8). -/
private def uintWidthOfType
    (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Option Nat :=
  match data.types[typeId.toNat]? with
  | some { shape := .uint w, .. } =>
      if w == 8 || w == 16 || w == 32 || w == 64 || w == 128 || w == 256 then
        some w.toNat
      else none
  | _ => none

private def isUnitType (data : SemanticProgramDataV1) (typeId : TypeIdV1) : Bool :=
  match data.types[typeId.toNat]? with
  | some { shape := .unit, .. } => true
  | _ => false

/-- T14 catalog v2 (Goldilocks): is this the admitted Goldilocks Field type?
    `PilotTypeClosureV1.fieldTypeId` is `some` iff the exact Goldilocks
    FieldSpec passed the target type-closure. Any other catalog spec was
    rejected at closure, so a `some` here is exactly Goldilocks. -/
private def isGoldilocksFieldType
    (types : PsyTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.fieldTypeId == some typeId

/-- Named Struct/Enum flatten to UInt{8,16,32,64}/Int64 leaves (preorder).
    Array UInt64 N → N leaves; Map UInt64 UInt64 → dense cap-8 pilot;
    Bytes 1..8 → N UInt8 leaves. Nested Map stays fail closed. -/
private partial def flattenTypeLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) :
    CompileResult (Array String) := do
  if typeId == types.uint64TypeId then
    pure #[namePrefix]
  else if match types.uintWidthOf typeId with
      | some w => isNarrowUintWidth w
      | none => false then
    pure #[namePrefix]
  else if types.int64TypeId == some typeId then
    pure #[namePrefix]
  else if match types.intWidthOf typeId with
      | some w => isNarrowIntWidth w
      | none => false then
    pure #[namePrefix]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        planError s!"unsupported Psy semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              planError "unsupported Psy semantic shape: named Struct requires at least one field"
            let mut out : Array String := #[]
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
              planError "unsupported Psy semantic shape: named Enum requires at least one variant"
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
            let mut out : Array String := #[tagName]
            for i in [0:maxPay] do
              let pName :=
                if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
              unless isIdentifier pName do
                planError s!"state name '{pName}' is not a safe identifier"
              out := out.push pName
            pure out
        | _ =>
            planError "unsupported Psy semantic shape: named type must be Struct or Enum"
  else if types.isContainer typeId then
    match typeDecls[typeId.toNat]? with
    | some { shape := .array elTid len, .. } =>
        unless elTid == types.uint64TypeId do
          planError "unsupported Psy semantic shape: Array state element must be UInt64"
        let n := len.toNat
        unless n ≥ 1 do
          planError "unsupported Psy semantic shape: Array state length must be ≥ 1"
        let mut out : Array String := #[]
        for i in [0:n] do
          let leafName := namePrefix ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          out := out.push leafName
        pure out
    | some { shape := .map keyTid valTid, .. } =>
        unless keyTid == types.uint64TypeId && valTid == types.uint64TypeId do
          planError "unsupported Psy semantic shape: Map state pilot requires UInt64 keys and values"
        let mut out : Array String := #[]
        for e in [0:psyMapPilotCapacityV1] do
          for tag in #["occ", "key", "val"] do
            let leafName :=
              if namePrefix.isEmpty then tag ++ toString e
              else namePrefix ++ "_" ++ tag ++ toString e
            unless isIdentifier leafName do
              planError s!"state name '{leafName}' is not a safe identifier"
            out := out.push leafName
        pure out
    | some { shape := .bytes n, .. } =>
        let len := n.toNat
        unless len ≥ 1 && len ≤ psyBytesMaxLenV1 do
          planError s!"unsupported Psy semantic shape: Bytes state length must be in 1..{psyBytesMaxLenV1}"
        let mut out : Array String := #[]
        for i in [0:len] do
          let leafName := namePrefix ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          out := out.push leafName
        pure out
    | _ =>
        planError "unsupported Psy semantic shape: container TypeId is not Array/Map/Bytes"
  else if types.isPrincipal typeId || types.isString typeId then
    -- Full wire identity: len + 8×UInt32 body limbs (max 32B payload).
    let lenName := if namePrefix.isEmpty then "len" else namePrefix ++ "_len"
    unless isIdentifier lenName do
      planError s!"state name '{lenName}' is not a safe identifier"
    let mut out : Array String := #[lenName]
    for i in [0:psyWireIdentityBodyLimbCountV1] do
      let leafName :=
        if namePrefix.isEmpty then s!"b{i}" else namePrefix ++ "_b" ++ toString i
      unless isIdentifier leafName do
        planError s!"state name '{leafName}' is not a safe identifier"
      out := out.push leafName
    pure out
  else
    planError "unsupported Psy semantic shape: aggregate leaf must be UInt{8,16,32,64}, Int64, named Struct/Enum, Array UInt64, Map UInt64 UInt64, Bytes 1..8, Principal, or String"

private def leafCountOfTypeV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Nat := do
  let specs ← flattenTypeLeafSpecsV1 typeDecls types typeId "x"
  pure specs.size

/-- B-RET-ABI return flatten for named Struct/Enum leaves: only UInt64/Int64 +
    nested named Struct/Enum (preorder; Enum = tag + max-payload pad).
    Anonymous containers are handled separately by `anonymousReturnLeafAbiV1`. -/
private partial def flattenReturnLeafAbiV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Array LeafAbiType) := do
  if typeId == types.uint64TypeId then
    pure #[{ isInt := false, byteWidth := 8 }]
  else if types.int64TypeId == some typeId then
    pure #[{ isInt := true, byteWidth := 8 }]
  else if types.isNamedAggregate typeId then
    match typeDecls[typeId.toNat]? with
    | none =>
        planError s!"unsupported Psy semantic shape: missing TypeDecl for aggregate {typeId}"
    | some decl =>
        match decl.shape with
        | .struct fields => do
            unless fields.size > 0 do
              planError "unsupported Psy semantic shape: named Struct requires at least one field"
            let mut out : Array LeafAbiType := #[]
            for f in fields do
              let sub ← flattenReturnLeafAbiV1 typeDecls types f.typeId
              out := out ++ sub
            pure out
        | .enum variants => do
            unless variants.size > 0 do
              planError "unsupported Psy semantic shape: named Enum requires at least one variant"
            let mut maxPay : Nat := 0
            for v in variants do
              let mut n : Nat := 0
              for pt in v.payloadTypes do
                let sub ← flattenReturnLeafAbiV1 typeDecls types pt
                n := n + sub.size
              if n > maxPay then maxPay := n
            -- Tag is always unsigned UInt64; payload slots padded to max.
            let mut out : Array LeafAbiType := #[{ isInt := false, byteWidth := 8 }]
            for _ in [0:maxPay] do
              out := out.push { isInt := false, byteWidth := 8 }
            pure out
        | _ =>
            planError "unsupported Psy semantic shape: named type must be Struct or Enum"
  else
    planError "unsupported Psy semantic shape: aggregate return leaf must be UInt64, Int64, or named Struct/Enum"

/-- N-ANON-RESULT (Psy ABI): anonymous result leaf layout for admitted
container returns. `Array UInt64 N` → N×Felt leaves; `Option UInt64` →
tag+payload (`none=[0,0]`, `some=[1,v]`); `Bytes N` (1..8) → N×UInt8 leaves.
Map throws for precise FC. -/
private def anonymousReturnLeafAbiV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Array LeafAbiType)) := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, name := none, .. } =>
      unless elTid == types.uint64TypeId do
        planError
          "unsupported Psy semantic shape: anonymous Array return requires UInt64 elements"
      let n := len.toNat
      unless n ≥ 1 do
        planError
          "unsupported Psy semantic shape: anonymous Array return length must be ≥ 1"
      pure (some (Array.replicate n { isInt := false, byteWidth := 8 }))
  | some { shape := .option elTid, name := none, .. } =>
      unless elTid == types.uint64TypeId do
        planError
          "unsupported Psy semantic shape: anonymous Option return requires UInt64 payload"
      pure (some #[{ isInt := false, byteWidth := 8 }, { isInt := false, byteWidth := 8 }])
  | some { shape := .bytes n, name := none, .. } =>
      let len := n.toNat
      unless len ≥ 1 && len ≤ psyBytesMaxLenV1 do
        planError s!"unsupported Psy semantic shape: Bytes return length must be in 1..{psyBytesMaxLenV1}"
      pure (some (Array.replicate len { isInt := false, byteWidth := 1 }))
  | some { shape := .map .., name := none, .. } =>
      planError
        "unsupported Psy semantic shape: anonymous Map return is outside the Psy B-RET ABI"
  | some { shape := .array .., .. } | some { shape := .option .., .. } =>
      pure none
  | _ => pure none

/-- True when `typeId` should be resolved through the aggregate result path
(named Struct/Enum or anonymous Array/Map/Bytes/Option, so Map/Bytes get
precise fail-closed diagnostics instead of a scalar fallthrough). -/
private def isAggregateResultCandidateV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : Bool :=
  if types.isNamedAggregate typeId then true
  else
    match typeDecls[typeId.toNat]? with
    | some { shape := .array .., name := none, .. }
    | some { shape := .option .., name := none, .. }
    | some { shape := .map .., name := none, .. }
    | some { shape := .bytes .., name := none, .. } => true
    | _ => false

/-- B-RET-ABI: resolve a named Struct/Enum or admitted anonymous Array/Option/Bytes
result TypeId into an aggregate `ResultKind`. Enforces 1..8 leaves.
Map/nested/narrow-element anonymous containers fail closed. -/
private def aggregateResultKindOfV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (owner : String) (typeId : TypeIdV1) : CompileResult ResultKind := do
  let leaves ←
    if types.isNamedAggregate typeId then
      flattenReturnLeafAbiV1 typeDecls types typeId
    else
      match ← anonymousReturnLeafAbiV1 typeDecls types typeId with
      | some ls => pure ls
      | none =>
          planError
            s!"{owner} does not return a named Struct/Enum or admitted anonymous Array/Option aggregate"
  let n := leaves.size
  unless n > 0 do
    planError s!"{owner} aggregate return must have at least one leaf"
  unless n ≤ 8 do
    planError s!"{owner} aggregate return has {n} leaves, exceeding the B-RET-ABI cap of 8"
  pure (.aggregate leaves)

private def structFieldLeafRangeV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
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
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless elTid == types.uint64TypeId do
        planError "unsupported Psy semantic shape: Array state element must be UInt64"
      let n := len.toNat
      unless n ≥ 1 do
        planError "unsupported Psy semantic shape: Array state length must be ≥ 1"
      pure (some n)
  | some { shape := .map .., .. } =>
      -- Map is handled by `mapUInt64LeafCountV1` (dense pilot), not Array layout.
      pure none
  | some { shape := .bytes n, .. } =>
      let len := n.toNat
      unless len ≥ 1 && len ≤ psyBytesMaxLenV1 do
        planError s!"unsupported Psy semantic shape: Bytes length must be in 1..{psyBytesMaxLenV1}"
      pure (some len)
  | _ =>
      planError "unsupported Psy semantic shape: container TypeId is not Array/Map/Bytes"

/-- Dense Map UInt64 UInt64 pilot leaf count when `typeId` is that shape. -/
private def mapUInt64LeafCountV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .map keyTid valTid, .. } =>
      unless keyTid == types.uint64TypeId && valTid == types.uint64TypeId do
        planError "unsupported Psy semantic shape: Map pilot requires UInt64 keys and values"
      pure (some psyMapPilotLeafCountV1)
  | _ => pure none

/-- Return leaf count for fixed Bytes N (UInt8 elements) when admitted. -/
private def bytesLeafCountV1
    (typeDecls : Array TypeDeclV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .bytes n, .. } =>
      let len := n.toNat
      unless len ≥ 1 && len ≤ psyBytesMaxLenV1 do
        planError s!"unsupported Psy semantic shape: Bytes length must be in 1..{psyBytesMaxLenV1}"
      pure (some len)
  | _ => pure none

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]` (unrolled select). -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == psyMapPilotLeafCountV1 do
    planError "unsupported Psy semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .boolLiteral false
  let mut payload : Expr := .literal 0
  for e in [0:psyMapPilotCapacityV1] do
    let base := e * psyMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      planError "Map lookup val leaf missing"
    let hit :=
      .logicalAnd (.compare .ne occ (.literal 0)) (.compare .eq k key)
    found := .logicalOr found hit
    payload := .select hit v payload
  pure #[.select found (.literal 1) (.literal 0), payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert) where okInsert is
    Felt 0/1 — caller asserts it (map full when key absent). -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == psyMapPilotLeafCountV1 do
    planError "unsupported Psy semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .boolLiteral false
  for e in [0:psyMapPilotCapacityV1] do
    let base := e * psyMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "Map upsert key leaf missing"
    let hit :=
      .logicalAnd (.compare .ne occ (.literal 0)) (.compare .eq k key)
    anyMatch := .logicalOr anyMatch hit
  let mut seenEmpty : Expr := .boolLiteral false
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:psyMapPilotCapacityV1] do
    let base := e * psyMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map upsert empty-scan occ missing"
    let empty := .compare .eq occ (.literal 0)
    let first := .logicalAnd empty (.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := .logicalOr seenEmpty empty
  let okInsert := .select (.logicalOr anyMatch seenEmpty) (.literal 1) (.literal 0)
  let mut out : Array Expr := #[]
  for e in [0:psyMapPilotCapacityV1] do
    let base := e * psyMapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      planError "Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      planError "Map upsert rebuild val missing"
    let matchHit :=
      .logicalAnd (.compare .ne occ (.literal 0)) (.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      planError "Map upsert firstEmpty missing"
    let insertHere := .logicalAnd firstE (.boolNot anyMatch)
    let write := .logicalOr matchHit insertHere
    let occ' := .select (.logicalOr (.compare .ne occ (.literal 0)) write)
      (.literal 1) (.literal 0)
    let k' := .select write key k
    let v' := .select write value v
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

/-- True when `typeId` is an anonymous Option TypeDecl (not named; not in
    `containerTypeIds`). Admitted surfaces: N-ANON-RESULT / B-RET-ABI return
    intermediates and B-OPT-STATE `Option UInt64` storage (2-leaf Enum-shaped
    layout). Element-type gates remain at each use site. -/
private def isAnonymousOptionTypeIdV1
    (typeDecls : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match typeDecls[typeId.toNat]? with
  | some { shape := .option _, name := none, .. } => true
  | _ => false

/-- B-OPT-STATE: `Option UInt64` storage leaves mirror named 2-variant Enum —
    `{prefix}_tag` + `{prefix}_p0` (tag 0=none / 1=some; payload zeroed on none). -/
private def flattenOptionUInt64LeafSpecsV1 (namePrefix : String) :
    CompileResult (Array String) := do
  let tagName :=
    if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
  let pName :=
    if namePrefix.isEmpty then "p0" else namePrefix ++ "_p0"
  unless isIdentifier tagName do
    planError s!"state name '{tagName}' is not a safe identifier"
  unless isIdentifier pName do
    planError s!"state name '{pName}' is not a safe identifier"
  pure #[tagName, pName]

private def makeStateLayoutV1
    (types : PsyTypeClosureV1) (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult PsyLowerLayoutV1 := do
  let mut fieldNames : Array String := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      planError "unsupported Psy semantic shape: semantic state ids must match declaration order"
    unless isIdentifier state.name do
      planError s!"state name '{state.name}' is not a safe identifier"
    if types.isNamedAggregate state.typeId || types.isContainer state.typeId
        || types.isPrincipal state.typeId || types.isString state.typeId then
      let leafSpecs ← flattenTypeLeafSpecsV1 typeDecls types state.typeId state.name
      if fieldNames.size + leafSpecs.size > maxStateLeafFields then
        planError "unsupported Psy semantic shape: state leaf count exceeds Psy profile limit"
      let mut leaves : Array Nat := #[]
      for name in leafSpecs do
        leaves := leaves.push fieldNames.size
        fieldNames := fieldNames.push name
      stateLeaves := stateLeaves.push leaves
    else if isAnonymousOptionTypeIdV1 typeDecls state.typeId then
      -- B-OPT-STATE / BL-36: Option UInt64 → tag + payload (2 Felt leaves),
      -- same physical shape as a 1-payload Enum. Names follow Enum convention
      -- (`name_tag` / `name_p0`). Default zero fields = Option.none; multi-leaf
      -- store writes both leaves; none construct zeroes payload (pin).
      match typeDecls[state.typeId.toNat]? with
      | some { shape := .option elTid, name := none, .. } =>
          unless elTid == types.uint64TypeId do
            planError
              s!"unsupported Psy semantic shape: Option state '{state.name}' requires UInt64 payload"
      | _ =>
          planError
            s!"unsupported Psy semantic shape: state '{state.name}' is not anonymous Option UInt64"
      let leafSpecs ← flattenOptionUInt64LeafSpecsV1 state.name
      if fieldNames.size + leafSpecs.size > maxStateLeafFields then
        planError "unsupported Psy semantic shape: state leaf count exceeds Psy profile limit"
      let mut leaves : Array Nat := #[]
      for name in leafSpecs do
        leaves := leaves.push fieldNames.size
        fieldNames := fieldNames.push name
      stateLeaves := stateLeaves.push leaves
    else if types.uintWidthOf state.typeId == some 128 ||
        types.uintWidthOf state.typeId == some 256 then
      -- UInt128/256 use 4/8 little-endian UInt32 Felt limbs in DPN.
      let limbCount :=
        if types.uintWidthOf state.typeId == some 256 then 8 else 4
      let mut leafNames : Array String := #[]
      for i in [0:limbCount] do
        leafNames := leafNames.push s!"{state.name}_{i}"
      if fieldNames.size + leafNames.size > maxStateLeafFields then
        planError "unsupported Psy semantic shape: state leaf count exceeds Psy profile limit"
      let mut leaves : Array Nat := #[]
      for name in leafNames do
        unless isIdentifier name do
          planError s!"state leaf name '{name}' is not a safe identifier"
        leaves := leaves.push fieldNames.size
        fieldNames := fieldNames.push name
      stateLeaves := stateLeaves.push leaves
    else if state.typeId == types.uint64TypeId
        || (match types.uintWidthOf state.typeId with
            | some w => isNarrowUintWidth w
            | none => false)
        || types.int64TypeId == some state.typeId
        || (match types.intWidthOf state.typeId with
            | some w => isNarrowIntWidth w
            | none => false)
        || isGoldilocksFieldType types state.typeId then
      let leafIdx := fieldNames.size
      fieldNames := fieldNames.push state.name
      stateLeaves := stateLeaves.push #[leafIdx]
    else
      planError "unsupported Psy semantic shape: state must be UInt{8,16,32,64,128,256}, Int{8,16,32,64}, Goldilocks Field, named Struct/Enum, Array UInt64, Map UInt64 UInt64, Bytes 1..8, Principal, String, or Option UInt64"
  pure { fieldNames, stateLeaves, typeDecls, types }

private def literalIndexNatV1 (v : LoweredVal) : CompileResult Nat := do
  unless !v.isAggregate do
    planError "unsupported Psy semantic shape: Array index must be a scalar UInt literal"
  match v.expr with
  | .literal n => pure n.toNat
  | .u32Literal n => pure n.toNat
  | _ =>
      planError "unsupported Psy semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

/-- Optional compile-time Nat when `v` is a UInt literal index; `none` → runtime. -/
private def literalIndexNat? (v : LoweredVal) : Option Nat :=
  if v.isAggregate then none
  else
    match v.expr with
    | .literal n => some n.toNat
    | .u32Literal n => some n.toNat
    | _ => none

/-- PSY-INDEX-CAST: bounds assert for dynamic Array/Bytes index. -/
private def indexOutOfBoundsGuardV1 (index : Expr) (length : Nat) : Statement :=
  .assertWithMessage
    (.compare .lt index (.literal (UInt64.ofNat length)))
    "indexOutOfBounds"

/-- Dynamic IndexGet: left-fold select `eq(idx,i) ? leaf_i : acc` after bounds. -/
private def dynamicIndexGetExprV1
    (index : Expr) (leaves : Array Expr) : CompileResult Expr := do
  unless leaves.size > 0 do
    planError "unsupported Psy semantic shape: dynamic IndexGet requires a non-empty aggregate"
  let mut acc : Expr := .literal 0
  for i in [0:leaves.size] do
    let some leaf := leaves[i]? |
      planError "dynamic IndexGet leaf missing"
    let hit := .compare .eq index (.literal (UInt64.ofNat i))
    acc := .select hit leaf acc
  pure acc

/-- Dynamic IndexSet: rebind every leaf via `eq(idx,j) ? value : base[j]`. -/
private def dynamicIndexSetLeavesV1
    (index value : Expr) (leaves : Array Expr) : CompileResult (Array Expr) := do
  unless leaves.size > 0 do
    planError "unsupported Psy semantic shape: dynamic IndexSet requires a non-empty aggregate"
  let mut out : Array Expr := #[]
  for j in [0:leaves.size] do
    let some baseLeaf := leaves[j]? |
      planError "dynamic IndexSet leaf missing"
    let hit := .compare .eq index (.literal (UInt64.ofNat j))
    out := out.push (.select hit value baseLeaf)
  pure out

/-- Max exclusive upper bound for unsigned width `w` as Felt-legal Nat.
    UInt64 is not admitted for CheckedCast on Psy (full 2^64 ⊄ Goldilocks). -/
private def uintExclusiveBoundNatV1 (bitWidth : Nat) : CompileResult Nat := do
  match bitWidth with
  | 8 => pure 256
  | 16 => pure 65536
  | 32 => pure 4294967296
  | _ =>
      planError s!"unsupported Psy semantic shape: CheckedCast UInt{bitWidth} is outside Psy narrow widths"

/-- Signed two's-complement max (2^{w-1}-1) as Nat. Int64 FC for CheckedCast. -/
private def intSignedMaxNatV1 (bitWidth : Nat) : CompileResult Nat := do
  match bitWidth with
  | 8 => pure 127
  | 16 => pure 32767
  | 32 => pure 2147483647
  | _ =>
      planError s!"unsupported Psy semantic shape: CheckedCast Int{bitWidth} is outside Psy narrow widths"

private def intTwoComplementMaskNatV1 (bitWidth : Nat) : CompileResult Nat := do
  match bitWidth with
  | 8 => pure 255
  | 16 => pure 65535
  | 32 => pure 4294967295
  | _ =>
      planError s!"unsupported Psy semantic shape: CheckedCast Int{bitWidth} mask outside Psy narrow widths"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 8 do
    planError "unsupported Psy semantic shape: UInt64 literal must contain exactly 8 bytes"
  match decodeU64le (start bytes) with
  | .error _ => planError "unsupported Psy semantic shape: UInt64 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure value
      | .error _ => planError "unsupported Psy semantic shape: UInt64 literal carries trailing bytes"

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool := do
  unless bytes.size == 1 do
    planError "unsupported Psy semantic shape: Bool literal must contain exactly 1 byte"
  let b := bytes.get! 0
  if b == 0 then pure false
  else if b == 1 then pure true
  else planError "unsupported Psy semantic shape: Bool literal must be 0x00 or 0x01"

private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    planError "unsupported Psy semantic shape: UInt32 literal must contain exactly 4 bytes"
  match decodeU32le (start bytes) with
  | .error _ => planError "unsupported Psy semantic shape: UInt32 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure (UInt64.ofNat value.toNat)
      | .error _ => planError "unsupported Psy semantic shape: UInt32 literal carries trailing bytes"

private def decodeUInt16LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 2 do
    planError "unsupported Psy semantic shape: UInt16 literal must contain exactly 2 bytes"
  match decodeU16le (start bytes) with
  | .error _ => planError "unsupported Psy semantic shape: UInt16 literal is not canonical"
  | .ok (value, cursor) =>
      match finish cursor with
      | .ok () => pure (UInt64.ofNat value.toNat)
      | .error _ => planError "unsupported Psy semantic shape: UInt16 literal carries trailing bytes"

private def decodeUInt8LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 1 do
    planError "unsupported Psy semantic shape: UInt8 literal must contain exactly 1 byte"
  pure (UInt64.ofNat (bytes.get! 0).toNat)

/-- Psy Felt modulus and Int64 sign bit, used to keep Constant lowering exact.
    Ordinary literal emission has historical modulo-p caveats; opening
    `Op.Constant` must not introduce a new silent value change. -/
private def goldilocksPrimeU64V1 : UInt64 := 0xFFFFFFFF00000001
private def int64SignBitU64V1 : UInt64 := 0x8000000000000000

private def lowerLiteral
    (data : SemanticProgramDataV1) (types : PsyTypeClosureV1)
    (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult Expr := do
  if isUInt64Type data typeId then
    match decodeUInt64LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else if isInt64Type data typeId then
    unless valueBytes.size == 8 do
      planError "unsupported Psy semantic shape: Int64 literal must contain exactly 8 bytes"
    match decodeU64le (start valueBytes) with
    | .error _ => planError "unsupported Psy semantic shape: Int64 literal is not canonical"
    | .ok (value, cursor) =>
        match finish cursor with
        | .ok () => pure (.literal value)
        | .error _ =>
            planError "unsupported Psy semantic shape: Int64 literal carries trailing bytes"
  else if match intWidthOfType data typeId with
      | some w => isNarrowIntWidth w
      | none => false then
    let w := (intWidthOfType data typeId).getD 8
    let need := w / 8
    unless valueBytes.size == need do
      planError s!"unsupported Psy semantic shape: Int{w} literal must contain exactly {need} bytes"
    let mut value : Nat := 0
    for i in [0:need] do
      value := value + ((valueBytes.get! i).toNat <<< (8 * i))
    pure (.literal (UInt64.ofNat value))
  else if isBoolType data typeId then
    match decodeBoolLiteralV1 valueBytes with
    | .ok flag => pure (.boolLiteral flag)
    | .error e => .error e
  else if isUInt32Type data typeId then
    -- Felt-carried narrow literal (not native u32 suffix).
    match decodeUInt32LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else if isUInt16Type data typeId then
    match decodeUInt16LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else if isUInt8Type data typeId then
    match decodeUInt8LiteralV1 valueBytes with
    | .ok value => pure (.literal value)
    | .error e => .error e
  else if isGoldilocksFieldType types typeId then
    -- T14 catalog v2 (Goldilocks): Field literal is an 8-byte LE value `< p`.
    -- The wire canonical valueBytes already enforces `< modulus` (Wire
    -- ValueBytesV1), so the decoded UInt64 is a legal Goldilocks element.
    unless valueBytes.size == 8 do
      planError "unsupported Psy semantic shape: Goldilocks Field literal must contain exactly 8 bytes"
    match decodeU64le (start valueBytes) with
    | .error _ => planError "unsupported Psy semantic shape: Goldilocks Field literal is not canonical"
    | .ok (value, cursor) =>
        match finish cursor with
        | .ok () => pure (.fieldLiteral value)
        | .error _ =>
            planError "unsupported Psy semantic shape: Goldilocks Field literal carries trailing bytes"
  else
    planError "unsupported Psy semantic shape: literal type is outside the public UInt{8,16,32,64}/Int64/Bool/Goldilocks-Field envelope"

private def decodeWideUintLimbsV1
    (bitWidth : Nat) (bytes : ByteArray) : CompileResult (Array Expr) := do
  let limbCount := wideLimbCountOf bitWidth
  let need := limbCount * 4
  unless bytes.size == need do
    planError s!"unsupported Psy semantic shape: UInt{bitWidth} literal must contain exactly {need} bytes"
  let mut limbs : Array Expr := #[]
  for limbIndex in [0:limbCount] do
    let base := limbIndex * 4
    let value :=
      (bytes.get! base).toNat +
      ((bytes.get! (base + 1)).toNat <<< 8) +
      ((bytes.get! (base + 2)).toNat <<< 16) +
      ((bytes.get! (base + 3)).toNat <<< 24)
    limbs := limbs.push (.literal (UInt64.ofNat value))
  pure limbs

private def decodeUInt128LimbsV1 (bytes : ByteArray) : CompileResult (Array Expr) :=
  decodeWideUintLimbsV1 128 bytes

private def decodeUInt256LimbsV1 (bytes : ByteArray) : CompileResult (Array Expr) :=
  decodeWideUintLimbsV1 256 bytes

/-- Decode wire Principal/String `u32le(len)||body` into len + 8×UInt32 body limbs.
    Body longer than 32 bytes fails closed (honest fixed layout). -/
private def decodeWireIdentityLimbsV1 (valueBytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless valueBytes.size ≥ 4 do
    planError "unsupported Psy semantic shape: Principal/String wire identity needs a length header"
  let len :=
    (valueBytes.get! 0).toNat +
    ((valueBytes.get! 1).toNat <<< 8) +
    ((valueBytes.get! 2).toNat <<< 16) +
    ((valueBytes.get! 3).toNat <<< 24)
  unless len ≥ 1 do
    planError "unsupported Psy semantic shape: Principal/String length must be ≥ 1"
  unless len ≤ psyWireIdentityMaxPayloadBytesV1 do
    planError s!"unsupported Psy semantic shape: Principal/String payload exceeds {psyWireIdentityMaxPayloadBytesV1} bytes on Psy"
  unless valueBytes.size == 4 + len do
    planError "unsupported Psy semantic shape: Principal/String wire length does not match payload"
  let mut limbs : Array Expr := #[.literal (UInt64.ofNat len)]
  for i in [0:psyWireIdentityBodyLimbCountV1] do
    let base := 4 + i * 4
    let mut word : Nat := 0
    for b in [0:4] do
      let off := base + b
      if off < valueBytes.size then
        word := word + ((valueBytes.get! off).toNat <<< (8 * b))
    limbs := limbs.push (.literal (UInt64.ofNat word))
  pure limbs

/-- Decode fixed Bytes N as N UInt8 Felt leaves. -/
private def decodeBytesLimbsV1 (n : Nat) (valueBytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless valueBytes.size == n do
    planError s!"unsupported Psy semantic shape: Bytes {n} literal must contain exactly {n} bytes"
  let mut limbs : Array Expr := #[]
  for i in [0:n] do
    limbs := limbs.push (.literal (UInt64.ofNat (valueBytes.get! i).toNat))
  pure limbs

private def lowerLiteralValue
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1)
    (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult LoweredVal := do
  match uintWidthOfType data typeId with
  | some 128 =>
      pure (mkWideUInt128Val (← decodeUInt128LimbsV1 valueBytes))
  | some 256 =>
      pure (mkWideUInt256Val (← decodeUInt256LimbsV1 valueBytes))
  | some w =>
      let e ← lowerLiteral data layout.types typeId valueBytes
      if isNarrowUintWidth w then pure (mkNarrowVal w e)
      else pure (mkScalarVal e)
  | none =>
      match intWidthOfType data typeId with
      | some w =>
          let e ← lowerLiteral data layout.types typeId valueBytes
          if isNarrowIntWidth w then pure (mkNarrowIntVal w e)
          else if w == 64 then pure (mkInt64Val e)
          else pure (mkScalarVal e)
      | none =>
          if layout.types.isPrincipal typeId || layout.types.isString typeId then
            pure (mkAggregateVal (← decodeWireIdentityLimbsV1 valueBytes))
          else
            match ← bytesLeafCountV1 layout.typeDecls layout.types typeId with
            | some n =>
                pure (mkAggregateVal (← decodeBytesLimbsV1 n valueBytes))
            | none =>
                let e ← lowerLiteral data layout.types typeId valueBytes
                if isGoldilocksFieldType layout.types typeId then pure (mkFieldVal e)
                else if isInt64Type data typeId then pure (mkInt64Val e)
                else pure (mkScalarVal e)

/-- Constant rows carry canonical valueBytes rather than source expression
    structure. Guard the two scalar cases whose raw wire integer cannot always
    be passed directly to a Goldilocks Felt without changing the value:
    UInt64 must be `< p`; Int64 must have a clear sign bit (nonnegative).
    Full negative Int64 support requires an explicit two's-complement→Psy
    signed-representation contract and remains fail closed. -/
private def validateConstantRepresentabilityV1
    (data : SemanticProgramDataV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult Unit := do
  if isUInt64Type data typeId then
    let raw ← decodeUInt64LiteralV1 valueBytes
    unless raw < goldilocksPrimeU64V1 do
      planError
        "unsupported Psy semantic shape: UInt64 constant must be below the Goldilocks modulus"
  else if isInt64Type data typeId then
    let raw ← decodeUInt64LiteralV1 valueBytes
    unless raw < int64SignBitU64V1 do
      planError
        "unsupported Psy semantic shape: negative Int64 constants require two's-complement-to-Goldilocks conversion and remain fail closed"

private def lowerBinary
    (op : BinaryOpV1) (lhs rhs : Expr) (signed : Bool) : CompileResult Expr :=
  match op with
  | .add => pure (.checkedAdd lhs rhs)
  | .sub => pure (.checkedSub lhs rhs)
  | .mul => pure (.checkedMul lhs rhs)
  | .div => pure (.checkedDiv lhs rhs)
  | .mod => pure (.checkedMod lhs rhs)
  | .eq => pure (if signed then .signedCompare .eq lhs rhs else .compare .eq lhs rhs)
  | .ne => pure (if signed then .signedCompare .ne lhs rhs else .compare .ne lhs rhs)
  | .lt => pure (if signed then .signedCompare .lt lhs rhs else .compare .lt lhs rhs)
  | .le => pure (if signed then .signedCompare .le lhs rhs else .compare .le lhs rhs)
  | .gt => pure (if signed then .signedCompare .gt lhs rhs else .compare .gt lhs rhs)
  | .ge => pure (if signed then .signedCompare .ge lhs rhs else .compare .ge lhs rhs)
  | .and => pure (.logicalAnd lhs rhs)
  | .or => pure (.logicalOr lhs rhs)
  | .bitAnd => pure (.bitAnd lhs rhs)
  | .bitOr => pure (.bitOr lhs rhs)
  | .bitXor => pure (.bitXor lhs rhs)
  | .shl => pure (.shl lhs rhs)
  | .shr => pure (.shr lhs rhs)

/-- Narrow UInt{8,16,32} binary as Felt-carried ops with width-guard emission.
    Compares stay unsigned (Felt order matches unsigned for values < 2^32 < p). -/
private def lowerNarrowBinary
    (bitWidth : Nat) (op : BinaryOpV1) (lhs rhs : Expr) : CompileResult Expr :=
  match op with
  | .add => pure (.narrowCheckedAdd bitWidth lhs rhs)
  | .sub => pure (.narrowCheckedSub bitWidth lhs rhs)
  | .mul => pure (.narrowCheckedMul bitWidth lhs rhs)
  | .div => pure (.narrowCheckedDiv bitWidth lhs rhs)
  | .mod => pure (.narrowCheckedMod bitWidth lhs rhs)
  | .bitAnd => pure (.narrowBitAnd bitWidth lhs rhs)
  | .bitOr => pure (.narrowBitOr bitWidth lhs rhs)
  | .bitXor => pure (.narrowBitXor bitWidth lhs rhs)
  | .shl => pure (.narrowShl bitWidth lhs rhs)
  | .shr => pure (.narrowShr bitWidth lhs rhs)
  | .eq => pure (.compare .eq lhs rhs)
  | .ne => pure (.compare .ne lhs rhs)
  | .lt => pure (.compare .lt lhs rhs)
  | .le => pure (.compare .le lhs rhs)
  | .gt => pure (.compare .gt lhs rhs)
  | .ge => pure (.compare .ge lhs rhs)
  | .and | .or =>
      planError s!"unsupported Psy semantic shape: UInt{bitWidth} does not admit logical and/or"

/-- Narrow Int{8,16,32}: two's-complement bit patterns in Felt (`0..2^w-1`).
    Modular wrap matches wire two's-complement; overflow uses sign-bit rules.
    Bitwise/shift treat the carrier as unsigned width-w bits (same as UInt). -/
private def lowerNarrowSignedBinary
    (bitWidth : Nat) (op : BinaryOpV1) (lhs rhs : Expr) : CompileResult Expr :=
  match op with
  | .add => pure (.narrowSignedCheckedAdd bitWidth lhs rhs)
  | .sub => pure (.narrowSignedCheckedSub bitWidth lhs rhs)
  | .mul => pure (.narrowSignedCheckedMul bitWidth lhs rhs)
  | .div => pure (.narrowSignedCheckedDiv bitWidth lhs rhs)
  | .mod => pure (.narrowSignedCheckedMod bitWidth lhs rhs)
  | .bitAnd => pure (.narrowBitAnd bitWidth lhs rhs)
  | .bitOr => pure (.narrowBitOr bitWidth lhs rhs)
  | .bitXor => pure (.narrowBitXor bitWidth lhs rhs)
  | .shl => pure (.narrowShl bitWidth lhs rhs)
  | .shr => pure (.narrowShr bitWidth lhs rhs)  -- logical; arithmetic shr deferred
  | .eq => pure (.narrowSignedCompare bitWidth .eq lhs rhs)
  | .ne => pure (.narrowSignedCompare bitWidth .ne lhs rhs)
  | .lt => pure (.narrowSignedCompare bitWidth .lt lhs rhs)
  | .le => pure (.narrowSignedCompare bitWidth .le lhs rhs)
  | .gt => pure (.narrowSignedCompare bitWidth .gt lhs rhs)
  | .ge => pure (.narrowSignedCompare bitWidth .ge lhs rhs)
  | .and | .or =>
      planError s!"unsupported Psy semantic shape: Int{bitWidth} does not admit logical and/or"

private structure WideUintBinaryV1 where
  /-- Statements that must execute before any result-limb expression is used. -/
  prelude : Array Statement := #[]
  value : LoweredVal
  assertion? : Option (Expr × String) := none

private abbrev WideUInt128BinaryV1 := WideUintBinaryV1

private def requireWideUintLeaves
    (bitWidth : Nat) (label : String) (value : LoweredVal) :
    CompileResult (Array Expr) := do
  let need := wideLimbCountOf bitWidth
  let ok :=
    (bitWidth == 128 && value.isWideUInt128) ||
      (bitWidth == 256 && value.isWideUInt256)
  unless ok do
    planError s!"unsupported Psy semantic shape: {label} must be UInt{bitWidth} ({need}×UInt32 Felt limbs)"
  pure value.leafExprs

private def requireWideUInt128Leaves
    (label : String) (value : LoweredVal) : CompileResult (Array Expr) :=
  requireWideUintLeaves 128 label value

private def lowerWideUintAdd
    (bitWidth : Nat) (lhs rhs : LoweredVal) : CompileResult WideUintBinaryV1 := do
  let left ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} add lhs" lhs
  let right ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} add rhs" rhs
  let limbs := wideLimbCountOf bitWidth
  let base : Expr := .literal 4294967296
  let zero : Expr := .literal 0
  let one : Expr := .literal 1
  let mut carry := zero
  let mut out : Array Expr := #[]
  for i in [0:limbs] do
    let sum := .limbAdd (.limbAdd left[i]! right[i]!) carry
    let hasCarry := .compare .ge sum base
    let limb := .select hasCarry (.limbSub sum base) sum
    out := out.push limb
    carry := .select hasCarry one zero
  let tag := if bitWidth == 256 then "u256" else "u128"
  pure {
    value := mkWideUintVal bitWidth out
    assertion? := some (.compare .eq carry zero, s!"{tag} add overflow")
  }

private def lowerWideUintSub
    (bitWidth : Nat) (lhs rhs : LoweredVal) : CompileResult WideUintBinaryV1 := do
  let left ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} sub lhs" lhs
  let right ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} sub rhs" rhs
  let limbs := wideLimbCountOf bitWidth
  let base : Expr := .literal 4294967296
  let zero : Expr := .literal 0
  let one : Expr := .literal 1
  let mut borrow := zero
  let mut out : Array Expr := #[]
  for i in [0:limbs] do
    let rhsWithBorrow := .limbAdd right[i]! borrow
    let underflow := .compare .lt left[i]! rhsWithBorrow
    let wrapped := .limbSub (.limbAdd left[i]! base) rhsWithBorrow
    let direct := .limbSub left[i]! rhsWithBorrow
    out := out.push (.select underflow wrapped direct)
    borrow := .select underflow one zero
  let tag := if bitWidth == 256 then "u256" else "u128"
  pure {
    value := mkWideUintVal bitWidth out
    assertion? := some (.compare .eq borrow zero, s!"{tag} sub underflow")
  }

private def lowerWideUintMul
    (bitWidth operationId : Nat) (lhs rhs : LoweredVal) :
    CompileResult WideUintBinaryV1 := do
  let left ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} mul lhs" lhs
  let right ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} mul rhs" rhs
  let limbs := wideLimbCountOf bitWidth
  let mut out : Array Expr := #[]
  for limbIndex in [0:limbs] do
    out := out.push (.wideUintMulLimb bitWidth operationId limbIndex)
  pure {
    prelude := #[.bindWideUintMul bitWidth operationId left right]
    value := mkWideUintVal bitWidth out
  }

private def lowerWideUintDivMod
    (bitWidth operationId : Nat) (resultKind : WideUInt128DivModResultV1)
    (lhs rhs : LoweredVal) : CompileResult WideUintBinaryV1 := do
  let label := match resultKind with
    | .quotient => s!"UInt{bitWidth} div"
    | .remainder => s!"UInt{bitWidth} mod"
  let left ← requireWideUintLeaves bitWidth (label ++ " lhs") lhs
  let right ← requireWideUintLeaves bitWidth (label ++ " rhs") rhs
  let limbs := wideLimbCountOf bitWidth
  let mut out : Array Expr := #[]
  for limbIndex in [0:limbs] do
    out := out.push (.wideUintDivModLimb resultKind bitWidth operationId limbIndex)
  pure {
    prelude := #[.bindWideUintDivMod resultKind bitWidth operationId left right]
    value := mkWideUintVal bitWidth out
  }

/-- Per-limb bitwise: each UInt32 Felt limb is operated independently. -/
private def lowerWideUintBitwise
    (bitWidth : Nat) (op : BinaryOpV1) (lhs rhs : LoweredVal) :
    CompileResult WideUintBinaryV1 := do
  let left ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} bitwise lhs" lhs
  let right ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} bitwise rhs" rhs
  let limbs := wideLimbCountOf bitWidth
  let mut out : Array Expr := #[]
  for i in [0:limbs] do
    let limb ← match op with
      | .bitAnd => pure (Expr.bitAnd left[i]! right[i]!)
      | .bitOr => pure (Expr.bitOr left[i]! right[i]!)
      | .bitXor => pure (Expr.bitXor left[i]! right[i]!)
      | _ => planError s!"unsupported Psy semantic shape: UInt{bitWidth} bitwise op mismatch"
    out := out.push limb
  pure { value := mkWideUintVal bitWidth out }

/-- Exact wide logical shift: UInt32 count; binding emission owns the bit walk. -/
private def lowerWideUintShift
    (bitWidth operationId : Nat) (kind : WideUInt128ShiftKindV1)
    (lhs rhs : LoweredVal) : CompileResult WideUintBinaryV1 := do
  let left ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} shift value" lhs
  unless rhs.isU32 do
    planError s!"unsupported Psy semantic shape: UInt{bitWidth} shift count must be UInt32"
  let limbs := wideLimbCountOf bitWidth
  let mut out : Array Expr := #[]
  for limbIndex in [0:limbs] do
    out := out.push (.wideUintShiftLimb kind bitWidth operationId limbIndex)
  pure {
    prelude := #[.bindWideUintShift kind bitWidth operationId left rhs.expr]
    value := mkWideUintVal bitWidth out
  }

private def lowerWideUintCompare
    (bitWidth : Nat) (op : BinaryOpV1) (lhs rhs : LoweredVal) :
    CompileResult WideUintBinaryV1 := do
  let left ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} compare lhs" lhs
  let right ← requireWideUintLeaves bitWidth s!"UInt{bitWidth} compare rhs" rhs
  let limbs := wideLimbCountOf bitWidth
  let mut eqExpr : Expr := .compare .eq left[0]! right[0]!
  let mut ltExpr : Expr := .compare .lt left[0]! right[0]!
  for i in [1:limbs] do
    let limbEq : Expr := .compare .eq left[i]! right[i]!
    let limbLt : Expr := .compare .lt left[i]! right[i]!
    ltExpr := .logicalOr limbLt (.logicalAnd limbEq ltExpr)
    eqExpr := .logicalAnd limbEq eqExpr
  let result ← match op with
    | .eq => pure eqExpr
    | .ne => pure (.boolNot eqExpr)
    | .lt => pure ltExpr
    | .le => pure (.logicalOr ltExpr eqExpr)
    | .gt => pure (.boolNot (.logicalOr ltExpr eqExpr))
    | .ge => pure (.boolNot ltExpr)
    | _ =>
        planError s!"unsupported Psy semantic shape: UInt{bitWidth} admits add/sub and six comparisons only"
  pure { value := mkScalarVal result }

private def lowerWideUintBinary
    (bitWidth operationId : Nat) (op : BinaryOpV1) (lhs rhs : LoweredVal) :
    CompileResult WideUintBinaryV1 :=
  match op with
  | .add => lowerWideUintAdd bitWidth lhs rhs
  | .sub => lowerWideUintSub bitWidth lhs rhs
  | .mul => lowerWideUintMul bitWidth operationId lhs rhs
  | .div => lowerWideUintDivMod bitWidth operationId .quotient lhs rhs
  | .mod => lowerWideUintDivMod bitWidth operationId .remainder lhs rhs
  | .bitAnd | .bitOr | .bitXor => lowerWideUintBitwise bitWidth op lhs rhs
  | .shl => lowerWideUintShift bitWidth operationId .shl lhs rhs
  | .shr => lowerWideUintShift bitWidth operationId .shr lhs rhs
  | .eq | .ne | .lt | .le | .gt | .ge => lowerWideUintCompare bitWidth op lhs rhs
  | _ =>
      planError s!"unsupported Psy semantic shape: UInt{bitWidth} admits add/sub/mul/div/mod/bitwise/shift and six comparisons only"

private def lowerWideUInt128Binary
    (operationId : Nat) (op : BinaryOpV1) (lhs rhs : LoweredVal) :
    CompileResult WideUintBinaryV1 :=
  lowerWideUintBinary 128 operationId op lhs rhs

private def lowerUnary
    (op : UnaryOpV1) (operand : Expr) (_resultTypeId : TypeIdV1) : CompileResult Expr :=
  match op with
  | .not => pure (.boolNot operand)
  | .bitNot =>
      -- UInt{8,16,32,64} bitNot are handled in the unary instruction arm before
      -- this helper; residual callers (Int64 / wrong width) stay fail-closed.
      planError "unsupported Psy semantic shape: unary bitNot (~) on Int64 has no Psy surface form (checkedBitNot is UInt64-only; Int two's-complement flip is not admitted on Felt)"
  | .neg => pure (.checkedNeg operand)

private structure LoopCtxV1 where
  header : BlockIdV1
  deriving Inhabited

private structure LowerStateV1 where
  stmts : Array Statement
  deriving Inhabited

private def isLoopHeaderV1 (callable : CallableV1) (blockId : BlockIdV1) : Bool :=
  callable.loopBounds.any (fun lb => lb.header == blockId)

private def isActiveHeader (loops : Array LoopCtxV1) (blockId : BlockIdV1) : Bool :=
  loops.any (fun ctx => ctx.header == blockId)

private structure RegionResult where
  stmts : Array Statement
  join? : Option Nat
  deriving Inhabited

private def regionClosed : CompileResult RegionResult :=
  pure { stmts := #[], join? := none }

private def lookupArgs
    (env : ValueEnv) (args : Array ValueIdV1) (what : String)
    (allowWideUInt128 : Bool := false) : CompileResult (Array Expr) := do
  let mut out : Array Expr := #[]
  for arg in args do
    match envLookup env arg with
    | some v =>
        if v.isWideUint && allowWideUInt128 then
          out := out ++ v.leafExprs
        else if v.isAggregate then
          planError s!"unsupported Psy semantic shape: {what} does not accept aggregate arguments"
        else
          -- Narrow UInt{8,16,32} are Felt-carried and legal on the call surface.
          out := out.push v.expr
    | none => planError s!"unsupported Psy semantic shape: {what} references an undefined argument"
  pure out

mutual

private partial def lowerRegion
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (expectedAggregateLeaves : Option (Array LeafAbiType))
    (entry : Nat) (loops : Array LoopCtxV1) (env : ValueEnv)
    (ls : LowerStateV1) : CompileResult RegionResult := do
  if entry >= callable.blocks.size then
    planError "unsupported Psy semantic shape: lowering references a missing block"
  let block ← match callable.blocks[entry]? with
    | some b => pure b
    | none => planError "unsupported Psy semantic shape: lowering references a missing block"
  unless block.params.isEmpty do
    planError "unsupported Psy semantic shape: block parameters only appear on loop headers"
  let mut env := env
  let mut ls := ls
  for instr in block.instructions do
    match instr.op with
    | .literal typeId valueBytes => do
        let value ← lowerLiteralValue data layout typeId valueBytes
        match instr.result with
        | none => planError "unsupported Psy semantic shape: literal instruction must produce a value"
        | some valueDef =>
            env := envInsertVal env valueDef.valueId value
    | .stateLoad stateId => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: stateLoad instruction must produce a value"
        | some valueDef =>
            let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
              | some idxs => pure idxs
              | none => planError "unsupported Psy semantic shape: stateLoad references unknown state id"
            let stateTypeId ← match data.logicalState[stateId.toNat]? with
              | some st => pure st.typeId
              | none => planError "unsupported Psy semantic shape: stateLoad declaration is missing"
            let wideStateW? :=
              match uintWidthOfType data stateTypeId with
              | some 128 => some 128
              | some 256 => some 256
              | _ => none
            if let some bitWidth := wideStateW? then
              let need := wideLimbCountOf bitWidth
              unless leafIdxs.size == need do
                planError s!"unsupported Psy semantic shape: UInt{bitWidth} stateLoad must carry {need} UInt32 limbs"
              let mut leaves : Array Expr := #[]
              for fi in leafIdxs do
                leaves := leaves.push (.stateLoad fi)
              env := envInsertVal env valueDef.valueId (mkWideUintVal bitWidth leaves)
            else if leafIdxs.size == 1 then
              let some fi := leafIdxs[0]? |
                planError "unsupported Psy semantic shape: stateLoad leaf index missing"
              let isFieldState := isGoldilocksFieldType layout.types stateTypeId
              let narrowW? :=
                match uintWidthOfType data stateTypeId with
                | some w => if isNarrowUintWidth w then some w else none
                | none => none
              let narrowIntW? :=
                match intWidthOfType data stateTypeId with
                | some w => if isNarrowIntWidth w then some w else none
                | none => none
              if isFieldState then
                env := envInsertVal env valueDef.valueId (mkFieldVal (.stateLoad fi))
              else if let some w := narrowW? then
                env := envInsertNarrow env valueDef.valueId w (.stateLoad fi)
              else if let some w := narrowIntW? then
                env := envInsertVal env valueDef.valueId (mkNarrowIntVal w (.stateLoad fi))
              else if isInt64Type data stateTypeId then
                env := envInsertVal env valueDef.valueId (mkInt64Val (.stateLoad fi))
              else
                env := envInsert env valueDef.valueId (.stateLoad fi)
            else
              let mut leaves : Array Expr := #[]
              for fi in leafIdxs do
                leaves := leaves.push (.stateLoad fi)
              let mapN? ← mapUInt64LeafCountV1 layout.typeDecls layout.types stateTypeId
              if mapN?.isSome then
                env := envInsertVal env valueDef.valueId (mkMapPilotVal leaves)
              else
                env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
    | .binary op lhs rhs => do
        let lv ← match envLookup env lhs with
          | some v => pure v
          | none => planError "unsupported Psy semantic shape: binary references an undefined operand"
        let rv ← match envLookup env rhs with
          | some v => pure v
          | none => planError "unsupported Psy semantic shape: binary references an undefined operand"
        let valueDef ← match instr.result with
          | some vd => pure vd
          | none => planError "unsupported Psy semantic shape: binary instruction must produce a value"
        -- PSY-SCALAR-ABI: Principal/String/Bytes/named multi-leaf eq/ne is
        -- leaf-wise Felt equality (not address/pubkey). Ordering stays FC.
        if (lv.isAggregate || rv.isAggregate) && !lv.isWideUint && !rv.isWideUint then
          unless lv.isAggregate && rv.isAggregate do
            planError "unsupported Psy semantic shape: aggregate comparison requires both operands aggregate"
          unless op == .eq || op == .ne do
            planError "unsupported Psy semantic shape: aggregate comparison only supports == / !="
          let le := lv.leafExprs
          let re := rv.leafExprs
          unless le.size == re.size && le.size > 0 do
            planError "unsupported Psy semantic shape: aggregate comparison leaf count mismatch"
          let mut acc : Expr := .compare .eq le[0]! re[0]!
          for i in [1:le.size] do
            acc := .logicalAnd acc (.compare .eq le[i]! re[i]!)
          let e := if op == .ne then .boolNot acc else acc
          env := envInsert env valueDef.valueId e
        else
        let resultWideW? :=
          match uintWidthOfType data valueDef.typeId with
          | some 128 => some 128
          | some 256 => some 256
          | _ => none
        let operandWideW? :=
          if lv.isWideUInt256 || rv.isWideUInt256 then some 256
          else if lv.isWideUInt128 || rv.isWideUInt128 then some 128
          else none
        let usesWideUint :=
          resultWideW?.isSome || operandWideW?.isSome
        if usesWideUint then
          let bitWidth ← match resultWideW?, operandWideW? with
            | some w, _ => pure w
            | none, some w => pure w
            | none, none =>
                planError "unsupported Psy semantic shape: wide binary width unresolved"
          let lowered ← lowerWideUintBinary bitWidth valueDef.valueId.toNat op lv rv
          if !lowered.prelude.isEmpty then
            ls := { ls with stmts := ls.stmts ++ lowered.prelude }
          match lowered.assertion? with
          | some (condition, message) =>
              ls := { ls with stmts := ls.stmts.push (.assertWithMessage condition message) }
          | none => pure ()
          if resultWideW?.isSome then
            unless lowered.value.wideUintWidth == bitWidth do
              planError s!"unsupported Psy semantic shape: UInt{bitWidth} arithmetic must produce {wideLimbCountOf bitWidth} UInt32 limbs"
          else
            unless !lowered.value.isAggregate do
              planError s!"unsupported Psy semantic shape: UInt{bitWidth} comparison must produce a scalar Bool"
          env := envInsertVal env valueDef.valueId lowered.value
        else if lv.isField && rv.isField then
          -- T14 catalog v2 (Goldilocks): native Felt field arithmetic. Both
          -- operands must be scalar Field values; the op is exact mod Goldilocks
          -- so no checked-overflow guard is emitted. Field supports add/sub/mul/
          -- div and eq/ne (ordering is rejected at Normalize). Bitwise/shift on
          -- Field fail closed (Field has no bitwise ops).
          unless !lv.isAggregate && !rv.isAggregate do
            planError "unsupported Psy semantic shape: Field binary operands must be scalar"
          let e ←
            match op with
            | .add => pure (.fieldBinary .add lv.expr rv.expr)
            | .sub => pure (.fieldBinary .sub lv.expr rv.expr)
            | .mul => pure (.fieldBinary .mul lv.expr rv.expr)
            | .div => pure (.fieldBinary .div lv.expr rv.expr)
            | .eq => pure (.fieldCompare .eq lv.expr rv.expr)
            | .ne => pure (.fieldCompare .ne lv.expr rv.expr)
            | _ =>
                planError "unsupported Psy semantic shape: Field admits only add/sub/mul/div/eq/ne"
          match instr.result with
          | none => planError "unsupported Psy semantic shape: binary instruction must produce a value"
          | some valueDef =>
              if op == .eq || op == .ne then
                env := envInsert env valueDef.valueId e
              else
                env := envInsertVal env valueDef.valueId (mkFieldVal e)
          pure ()
        else
        -- T8 multi-width: Felt-carried UInt{8,16,32} with explicit width guards
        -- at emission. Prefer result TypeId width; fall back to lhs narrow tag
        -- (comparisons yield Bool so width comes from the operand lane).
        let narrowW? : Option Nat :=
          match instr.result with
          | some vd =>
              match uintWidthOfType data vd.typeId with
              | some w => if isNarrowUintWidth w then some w else none
              | none =>
                  -- Comparison / logical result is Bool — use lhs narrow width.
                  if lv.isNarrow then some lv.uintWidth else none
          | none => if lv.isNarrow then some lv.uintWidth else none
        let narrowIntW? : Option Nat :=
          match instr.result with
          | some vd =>
              match intWidthOfType data vd.typeId with
              | some w => if isNarrowIntWidth w then some w else none
              | none =>
                  if lv.isNarrowInt then some lv.intWidth else none
          | none => if lv.isNarrowInt then some lv.intWidth else none
        -- Shift count may be UInt32 while lhs is UInt64 — keep UInt64 path with
        -- count folded as Felt (count still needs count < 64 guard).
        let e ← match narrowW?, narrowIntW? with
          | some w, _ =>
              unless !lv.isNarrow || lv.uintWidth == w || op == .shl || op == .shr do
                planError s!"unsupported Psy semantic shape: UInt{w} binary lhs width mismatch"
              unless !rv.isNarrow || rv.uintWidth == w || op == .shl || op == .shr do
                planError s!"unsupported Psy semantic shape: UInt{w} binary rhs width mismatch"
              lowerNarrowBinary w op lv.expr rv.expr
          | none, some w =>
              unless !lv.isNarrowInt || lv.intWidth == w || op == .shl || op == .shr do
                planError s!"unsupported Psy semantic shape: Int{w} binary lhs width mismatch"
              unless !rv.isNarrowInt || rv.intWidth == w || op == .shl || op == .shr do
                planError s!"unsupported Psy semantic shape: Int{w} binary rhs width mismatch"
              -- Shift count may be UInt32 while value is Int.
              unless !rv.isNarrow || op == .shl || op == .shr do
                planError s!"unsupported Psy semantic shape: Int{w} binary rhs must be Int{w}"
              lowerNarrowSignedBinary w op lv.expr rv.expr
          | none, none =>
              let l := lv.expr
              let r := rv.expr
              let signed :=
                if lv.isNarrow || rv.isNarrow || lv.isNarrowInt || rv.isNarrowInt then false
                else
                  lv.intWidth == 64 || rv.intWidth == 64 ||
                    match instr.result with
                    | some _ =>
                        match l with
                        | .stateLoad idx =>
                            match data.logicalState[idx]? with
                            | some st => isInt64Type data st.typeId
                            | none => false
                        | .param pidx =>
                            match callable.params[pidx]? with
                            | some p => isInt64Type data p.typeId
                            | none => false
                        | _ =>
                            data.logicalState.any (fun st => isInt64Type data st.typeId) ||
                              callable.params.any (fun p => isInt64Type data p.typeId)
                    | none => false
              lowerBinary op l r signed
        match instr.result with
        | none => planError "unsupported Psy semantic shape: binary instruction must produce a value"
        | some valueDef =>
            match uintWidthOfType data valueDef.typeId with
            | some w =>
                if isNarrowUintWidth w then
                  env := envInsertNarrow env valueDef.valueId w e
                else
                  env := envInsert env valueDef.valueId e
            | none =>
                match intWidthOfType data valueDef.typeId with
                | some w =>
                    if isNarrowIntWidth w then
                      env := envInsertVal env valueDef.valueId (mkNarrowIntVal w e)
                    else if w == 64 then
                      env := envInsertVal env valueDef.valueId (mkInt64Val e)
                    else
                      env := envInsert env valueDef.valueId e
                | none =>
                    env := envInsert env valueDef.valueId e
    | .unary op operand => do
        let o ← match envLookup env operand with
          | some v => pure v
          | none => planError "unsupported Psy semantic shape: unary references an undefined operand"
        match instr.result with
        | none => planError "unsupported Psy semantic shape: unary instruction must produce a value"
        | some valueDef =>
            match op, uintWidthOfType data valueDef.typeId with
            | .bitNot, some w =>
                if isNarrowUintWidth w then
                  unless !o.isAggregate && (o.isNarrow || o.uintWidth == 0) do
                    planError s!"unsupported Psy semantic shape: UInt{w} bitNot operand must be a scalar"
                  env := envInsertNarrow env valueDef.valueId w (.narrowBitNot w o.expr)
                else if w == 64 then
                  unless !o.isAggregate && !o.isNarrow && !o.isField do
                    planError "unsupported Psy semantic shape: UInt64 bitNot operand must be a scalar Felt UInt64"
                  env := envInsert env valueDef.valueId (.checkedBitNot o.expr)
                else if w == 128 || w == 256 then
                  let ok :=
                    (w == 128 && o.isWideUInt128) || (w == 256 && o.isWideUInt256)
                  unless ok do
                    planError s!"unsupported Psy semantic shape: UInt{w} bitNot operand must be {wideLimbCountOf w} UInt32 limbs"
                  let mask : Expr := .literal 4294967295
                  let mut out : Array Expr := #[]
                  for limb in o.leafExprs do
                    out := out.push (.bitXor limb mask)
                  env := envInsertVal env valueDef.valueId (mkWideUintVal w out)
                else
                  planError s!"unsupported Psy semantic shape: bitNot on UInt{w} is outside the Psy envelope"
            | .neg, _ =>
                if o.isField then
                  unless !o.isAggregate do
                    planError "unsupported Psy semantic shape: Field neg operand must be scalar"
                  env := envInsertVal env valueDef.valueId (mkFieldVal (.fieldNeg o.expr))
                else if o.isNarrowInt then
                  env := envInsertVal env valueDef.valueId
                    (mkNarrowIntVal o.intWidth (.narrowCheckedNeg o.intWidth o.expr))
                else if o.intWidth == 64 ||
                    (match intWidthOfType data valueDef.typeId with
                     | some 64 => true | _ => false) then
                  let e ← lowerUnary op o.expr valueDef.typeId
                  env := envInsertVal env valueDef.valueId (mkInt64Val e)
                else
                  unless !o.isNarrow do
                    planError "unsupported Psy semantic shape: unary neg on narrow UInt is not admitted"
                  unless !o.isField do
                    planError "unsupported Psy semantic shape: Field admits only unary neg"
                  let e ← lowerUnary op o.expr valueDef.typeId
                  env := envInsert env valueDef.valueId e
            | .not, _ =>
                unless !o.isNarrow do
                  planError "unsupported Psy semantic shape: logical not on narrow UInt is not admitted"
                unless !o.isField do
                  planError "unsupported Psy semantic shape: Field admits only unary neg"
                let e ← lowerUnary op o.expr valueDef.typeId
                env := envInsert env valueDef.valueId e
            | .bitNot, none =>
                planError "unsupported Psy semantic shape: unary bitNot (~) on Int64 has no Psy surface form (checkedBitNot is UInt64-only; Int two's-complement flip is not admitted on Felt)"
    | .pureCall callableId args => do
        let fnName ← match fnNames.findSome? (fun (cid, n) =>
            if cid == callableId then some n else none) with
          | some n => pure n
          | none => planError "unsupported Psy semantic shape: pureCall references an unknown callee"
        let argExprs ← lookupArgs env args "pureCall" true
        let e : Expr := .callFn fnName argExprs
        match instr.result with
        | none => planError "unsupported Psy semantic shape: pureCall instruction must produce a value"
        | some valueDef =>
            match uintWidthOfType data valueDef.typeId with
            | some 128 | some 256 =>
                planError "unsupported Psy semantic shape: pureFn UInt128/256 returns require multi-result call binding and remain fail closed"
            | some w =>
                if isNarrowUintWidth w then
                  env := envInsertNarrow env valueDef.valueId w e
                else
                  env := envInsert env valueDef.valueId e
            | none =>
                env := envInsert env valueDef.valueId e
    | .stateStore stateId value => do
        let v ← match envLookup env value with
          | some lv => pure lv
          | none => planError "unsupported Psy semantic shape: stateStore references an undefined value"
        let leafIdxs ← match layout.stateLeaves[stateId.toNat]? with
          | some idxs => pure idxs
          | none => planError "unsupported Psy semantic shape: stateStore references unknown state id"
        let stateTypeId ← match data.logicalState[stateId.toNat]? with
          | some st => pure st.typeId
          | none => planError "unsupported Psy semantic shape: stateStore declaration is missing"
        let stateWideW? :=
          match uintWidthOfType data stateTypeId with
          | some 128 => some 128
          | some 256 => some 256
          | _ => none
        if let some bitWidth := stateWideW? then
          let ok :=
            (bitWidth == 128 && v.isWideUInt128) ||
              (bitWidth == 256 && v.isWideUInt256)
          unless ok do
            planError s!"unsupported Psy semantic shape: UInt{bitWidth} stateStore requires {wideLimbCountOf bitWidth} UInt32 limbs"
        else if v.isWideUint then
          planError "unsupported Psy semantic shape: wide UInt value cannot be stored into a non-matching state"
        let leaves := v.leafExprs
        unless leaves.size == leafIdxs.size do
          planError "unsupported Psy semantic shape: stateStore leaf count mismatch"
        if leafIdxs.size == 1 then
          let some fi := leafIdxs[0]? |
            planError "unsupported Psy semantic shape: stateStore leaf index missing"
          let some e := leaves[0]? |
            planError "unsupported Psy semantic shape: stateStore leaf value missing"
          ls := { ls with stmts := ls.stmts.push (.store fi e) }
        else
          ls := { ls with stmts := ls.stmts.push (.storeAggregate leafIdxs leaves) }
    | .assert_ condition errorId args => do
        -- PSY-TYPED-ERROR: zero-payload assert-else tags the declared error
        -- name in the DPN assert record. Structured payloads fail closed.
        unless args.isEmpty do
          planError
            "unsupported Psy semantic shape: assert-else error payload arguments require a structured DPN error ABI (PSY-TYPED-ERROR FC)"
        let c ← match envLookupExpr env condition with
          | some e => pure e
          | none => planError "unsupported Psy semantic shape: assert references an undefined condition"
        match errorId with
        | none =>
            ls := { ls with stmts := ls.stmts.push (.assert c) }
        | some eid =>
            let errDecl ← match data.errors[eid.toNat]? with
              | some e => pure e
              | none =>
                  planError "unsupported Psy semantic shape: assert-else references an unknown error id"
            unless errDecl.fields.isEmpty do
              planError
                s!"unsupported Psy semantic shape: assert-else error '{errDecl.name}' has fields but no payload args (parameterized error ABI not admitted on Psy; PSY-TYPED-ERROR FC)"
            let guard : Statement :=
              .assertWithMessage c s!"assert:{errDecl.name}"
            ls := { ls with stmts := ls.stmts.push guard }
    | .emit _effectId eventId args => do
        -- PSY-CALL-EVENT PARTIAL: direct DPN event record, but Finalize has no
        -- ordered-event runtime observable / log gate.
        let argExprs ← lookupArgs env args "emit"
        ls := { ls with stmts := ls.stmts.push (.emitEvent eventId.toNat argExprs) }
    | .externalCall _effectId callee args => do
        -- PSY-CALL-EVENT: void sync call → direct DPN
        -- InvokeExternalContractFunctionSync (hashed static QN; no deployment
        -- binding, callee-failure refinement, or product runtime gate).
        -- Result-bearing calls have no response-binding ABI and fail closed.
        match instr.result with
        | some _ =>
            planError
              "unsupported Psy semantic shape: result-bearing external call is not admitted (no DPN response-binding / return-value ABI; PSY-CALL-EVENT FC)"
        | none => pure ()
        let comps := callee.components.toArray
        unless comps.size ≥ 2 do
          planError "unsupported Psy semantic shape: external callee must have at least two components"
        -- ADR-0029 Phase D: catalog QNs are unbound. Hashing them into a DPN
        -- sync invoke would falsely imply native value movement.
        let qn := String.intercalate "." comps.toList
        if isPfAssetsCatalogQnV1 qn then
          planError s!"unsupported Psy semantic shape: {unboundCatalogDiagV1 qn}"
        let argExprs ← lookupArgs env args "externalCall"
        ls := { ls with stmts := ls.stmts.push (.externalCall comps argExprs) }
    | .schedule _effectId callee args => do
        -- PSY-CALL-EVENT / async: DPN has no admitted deferred crosscall op;
        -- never alias the synchronous invoke operation.
        let _ := callee
        let _ := args
        planError
          "unsupported Psy semantic shape: schedule is not admitted on Psy (no deferred crosscall form; effect.asynchronous-workflow declined; PSY-CALL-EVENT FC)"
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: construct instruction must produce a value"
        | some valueDef =>
            unless valueDef.typeId == typeId do
              planError "unsupported Psy semantic shape: construct result typeId must match op typeId"
            if layout.types.isContainer typeId then
              let mapN? ← mapUInt64LeafCountV1 layout.typeDecls layout.types typeId
              if let some n := mapN? then
                -- Map.empty() → all-zero dense pilot leaves (NS-1).
                unless ctorIdx == 0 do
                  planError "unsupported Psy semantic shape: Map construct ctorIdx must be 0 (Map.empty)"
                unless argIds.isEmpty do
                  planError "unsupported Psy semantic shape: Map.empty construct takes no args (nonempty Map construct stays fail closed)"
                let mut leafExprs : Array Expr := #[]
                for _ in [0:n] do
                  leafExprs := leafExprs.push (.literal 0)
                env := envInsertVal env valueDef.valueId (mkMapPilotVal leafExprs)
              else
                let bytesN? ← bytesLeafCountV1 layout.typeDecls layout.types typeId
                let arrayN? ← arrayUInt64LeafCountV1 layout.typeDecls layout.types typeId
                let (n, isBytes) ← match bytesN?, arrayN? with
                  | some n, _ => pure (n, true)
                  | none, some n => pure (n, false)
                  | none, none =>
                      planError "unsupported Psy semantic shape: construct admits only Map.empty, fixed Array UInt64, or Bytes 1..8 on Psy"
                unless ctorIdx == 0 do
                  planError "unsupported Psy semantic shape: Array/Bytes construct ctorIdx must be 0"
                unless argIds.size == n do
                  planError "unsupported Psy semantic shape: Array/Bytes construct arity mismatch"
                let mut leafExprs : Array Expr := #[]
                for argId in argIds do
                  let arg ← match envLookup env argId with
                    | some v => pure v
                    | none => planError "unsupported Psy semantic shape: construct references undefined arg"
                  unless !arg.isAggregate do
                    planError "unsupported Psy semantic shape: Array/Bytes construct args must be scalar"
                  if isBytes then
                    unless arg.isNarrow && arg.uintWidth == 8 do
                      planError "unsupported Psy semantic shape: Bytes construct args must be UInt8"
                  else
                    unless !arg.isNarrow || arg.uintWidth == 0 || arg.uintWidth == 64 do
                      planError "unsupported Psy semantic shape: Array construct args must be scalar UInt64"
                  leafExprs := leafExprs.push arg.expr
                env := envInsertVal env valueDef.valueId (mkAggregateVal leafExprs)
            else if layout.types.isPrincipal typeId || layout.types.isString typeId then
              -- Wire identity construct: single Bytes-like payload not used;
              -- callers materialize via constant/literal path or leaf store.
              planError "unsupported Psy semantic shape: Principal/String construct must use constant/literal materialization (no runtime ctor)"
            else
              -- Option UInt64 construct (none/some) for N-ANON-RESULT returns
              -- and B-OPT-STATE store RHS; named Struct/Enum remains the other
              -- non-container path. none zeroes payload (stale-payload pin).
              match layout.typeDecls[typeId.toNat]? with
              | some { shape := .option elTid, name := none, .. } => do
                  unless elTid == layout.types.uint64TypeId do
                    planError
                      "unsupported Psy semantic shape: Option construct requires UInt64 payload"
                  match ctorIdx.toNat with
                  | 0 =>
                      -- Option.none → (tag=0, payload=0)
                      unless argIds.isEmpty do
                        planError
                          "unsupported Psy semantic shape: Option.none construct takes no args"
                      env := envInsertVal env valueDef.valueId
                        (mkAggregateVal #[.literal 0, .literal 0])
                  | 1 =>
                      -- Option.some(v) → (tag=1, payload=v)
                      unless argIds.size == 1 do
                        planError
                          "unsupported Psy semantic shape: Option.some construct takes one arg"
                      let some argId := argIds[0]? |
                        planError "Option.some construct arg missing"
                      let arg ← match envLookup env argId with
                        | some v => pure v
                        | none => planError "unsupported Psy semantic shape: Option.some undefined arg"
                      unless !arg.isAggregate do
                        planError
                          "unsupported Psy semantic shape: Option.some arg must be scalar UInt64"
                      env := envInsertVal env valueDef.valueId
                        (mkAggregateVal #[.literal 1, arg.expr])
                  | _ =>
                      planError
                        "unsupported Psy semantic shape: Option construct ctorIdx must be 0 (none) or 1 (some)"
              | _ => do
                  unless layout.types.isNamedAggregate typeId do
                    planError "unsupported Psy semantic shape: construct admits only Array UInt64, Option UInt64, or named Struct/Enum on Psy"
                  let some decl := layout.typeDecls[typeId.toNat]? |
                    planError "unsupported Psy semantic shape: construct TypeDecl missing"
                  match decl.shape with
                  | .struct fields => do
                      unless ctorIdx.toNat == 0 do
                        planError "unsupported Psy semantic shape: struct construct ctorIdx must be 0"
                      unless argIds.size == fields.size do
                        planError "unsupported Psy semantic shape: struct construct arity mismatch"
                      let mut leaves : Array Expr := #[]
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
                          planError "unsupported Psy semantic shape: struct construct field leaf count mismatch"
                        leaves := leaves ++ argLeaves
                      env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
                  | .enum variants => do
                      let vi := ctorIdx.toNat
                      let some variant := variants[vi]? |
                        planError "unsupported Psy semantic shape: enum construct variant out of range"
                      unless argIds.size == variant.payloadTypes.size do
                        planError "unsupported Psy semantic shape: enum construct arity mismatch"
                      let maxPay ← enumMaxPayloadLeavesV1 layout.typeDecls layout.types variants
                      let mut leaves : Array Expr := #[.literal (UInt64.ofNat vi)]
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
                          planError "unsupported Psy semantic shape: enum construct payload leaf count mismatch"
                        leaves := leaves ++ argLeaves
                      while leaves.size < 1 + maxPay do
                        leaves := leaves.push (.literal 0)
                      env := envInsertVal env valueDef.valueId (mkAggregateVal leaves)
                  | _ =>
                      planError "unsupported Psy semantic shape: construct requires Struct or Enum shape"
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: fieldGet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "unsupported Psy semantic shape: fieldGet base undefined"
            unless base.isAggregate do
              planError "unsupported Psy semantic shape: fieldGet base must be a named aggregate"
            let baseLeaves := base.leafExprs
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
                  planError "unsupported Psy semantic shape: fieldGet could not resolve struct field range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Psy semantic shape: fieldGet leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            for i in [start:start+len] do
              let some e := baseLeaves[i]? |
                planError "fieldGet leaf missing"
              outLeaves := outLeaves.push e
            if layout.types.isNamedAggregate valueDef.typeId then
              env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
            else
              let some e0 := outLeaves[0]? |
                planError "fieldGet scalar leaf missing"
              env := envInsert env valueDef.valueId e0
    | .fieldSet baseId fieldIndex valueId => do
        match instr.result with
        | none => planError "unsupported Psy semantic shape: fieldSet must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "fieldSet base undefined"
            let val ← match envLookup env valueId with
              | some v => pure v
              | none => planError "fieldSet value undefined"
            unless base.isAggregate do
              planError "unsupported Psy semantic shape: fieldSet base must be a named aggregate"
            unless layout.types.isNamedAggregate valueDef.typeId do
              planError "unsupported Psy semantic shape: fieldSet result must be named aggregate"
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
              | none => planError "unsupported Psy semantic shape: fieldSet could not resolve field range"
            unless valLeaves.size == len do
              planError "unsupported Psy semantic shape: fieldSet value leaf count mismatch"
            unless start + len <= baseLeaves.size do
              planError "unsupported Psy semantic shape: fieldSet leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            for i in [0:baseLeaves.size] do
              if i >= start && i < start + len then
                let some e := valLeaves[i - start]? |
                  planError "fieldSet value leaf missing"
                outLeaves := outLeaves.push e
              else
                let some e := baseLeaves[i]? |
                  planError "fieldSet base leaf missing"
                outLeaves := outLeaves.push e
            env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
    | .variantTag baseId => do
        match instr.result with
        | none => planError "variantTag must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "variantTag base undefined"
            unless base.isAggregate do
              planError "unsupported Psy semantic shape: variantTag base must be an Enum or Option aggregate"
            let some tag := base.leafExprs[0]? |
              planError "variantTag missing tag leaf"
            -- Semantic VariantTag is UInt32 (Normalize match switch cases are
            -- 4-byte LE). Carry as Felt-narrow so switch case decoding uses
            -- decodeUInt32LiteralV1 rather than requiring 8-byte UInt64.
            env := envInsertNarrow env valueDef.valueId 32 tag
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none => planError "variantPayload must produce a value"
        | some valueDef =>
            let base ← match envLookup env baseId with
              | some v => pure v
              | none => planError "variantPayload base undefined"
            unless base.isAggregate do
              planError "unsupported Psy semantic shape: variantPayload base must be an aggregate (Enum or Option)"
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
                  -- B-OPT-STATE / N-ANON-RESULT: Option is 2-leaf [tag, payload].
                  -- some (variant 1) payload 0 is leaf 1; none has empty payload.
                  if variantIndex.toNat == 1 && payloadIndex.toNat == 0 &&
                      baseLeaves.size == 2 then
                    pure (1, 1, layout.types.isNamedAggregate valueDef.typeId)
                  else if variantIndex.toNat == 0 then
                    planError
                      "unsupported Psy semantic shape: variantPayload of Option.none is empty"
                  else
                    planError
                      "unsupported Psy semantic shape: variantPayload could not resolve range"
            unless start + len <= baseLeaves.size do
              planError "unsupported Psy semantic shape: variantPayload leaf range out of bounds"
            let mut outLeaves : Array Expr := #[]
            for i in [start:start+len] do
              let some e := baseLeaves[i]? |
                planError "variantPayload leaf missing"
              outLeaves := outLeaves.push e
            if asAgg then
              env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
            else
              let some e0 := outLeaves[0]? |
                planError "variantPayload scalar leaf missing"
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
              planError "unsupported Psy semantic shape: IndexGet base must be an Array UInt64, Bytes, or dense Map aggregate"
            if base.isMapPilot then
              -- Dense Map IndexGet → Option UInt64 (dynamic UInt64 key).
              unless !idx.isAggregate do
                planError "unsupported Psy semantic shape: Map IndexGet key must be scalar UInt64"
              let optLeaves ← mapLookupOptionLeavesV1 base.leafExprs idx.expr
              env := envInsertVal env valueDef.valueId (mkAggregateVal optLeaves)
            else
              unless !idx.isAggregate do
                planError "unsupported Psy semantic shape: Array/Bytes IndexGet index must be scalar UInt"
              let leaves := base.leafExprs
              let leaf ← match literalIndexNat? idx with
                | some i => do
                    unless i < leaves.size do
                      planError "unsupported Psy semantic shape: IndexGet index out of range"
                    let some e := leaves[i]? |
                      planError "IndexGet leaf missing"
                    pure e
                | none => do
                    -- PSY-INDEX-CAST: runtime index with exact indexOutOfBounds.
                    let g := indexOutOfBoundsGuardV1 idx.expr leaves.size
                    ls := { ls with stmts := ls.stmts.push g }
                    dynamicIndexGetExprV1 idx.expr leaves
              -- Bytes elements are UInt8; Array UInt64 elements stay scalar Felt.
              match uintWidthOfType data valueDef.typeId with
              | some 8 =>
                  env := envInsertNarrow env valueDef.valueId 8 leaf
              | _ =>
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
              planError "unsupported Psy semantic shape: IndexSet base must be an Array UInt64, Bytes, or dense Map aggregate"
            unless !val.isAggregate do
              planError "unsupported Psy semantic shape: IndexSet value must be scalar"
            if base.isMapPilot then
              unless !idx.isAggregate do
                planError "unsupported Psy semantic shape: Map IndexSet key must be scalar UInt64"
              let (outLeaves, okInsert) ←
                mapUpsertLeavesV1 base.leafExprs idx.expr val.expr
              -- Map full (key absent and no empty slot) → assert fail.
              let fullGuard : Statement :=
                .assertWithMessage
                  (.compare .eq okInsert (.literal 1))
                  "map full: no empty slot for new key"
              ls := { ls with stmts := ls.stmts.push fullGuard }
              env := envInsertVal env valueDef.valueId (mkMapPilotVal outLeaves)
            else
              unless !idx.isAggregate do
                planError "unsupported Psy semantic shape: Array/Bytes IndexSet index must be scalar UInt"
              let leaves := base.leafExprs
              let outLeaves ← match literalIndexNat? idx with
                | some i => do
                    unless i < leaves.size do
                      planError "unsupported Psy semantic shape: IndexSet index out of range"
                    let mut out : Array Expr := #[]
                    for j in [0:leaves.size] do
                      if j == i then
                        out := out.push val.expr
                      else
                        let some e := leaves[j]? |
                          planError "IndexSet leaf missing"
                        out := out.push e
                    pure out
                | none => do
                    let g := indexOutOfBoundsGuardV1 idx.expr leaves.size
                    ls := { ls with stmts := ls.stmts.push g }
                    dynamicIndexSetLeavesV1 idx.expr val.expr leaves
              env := envInsertVal env valueDef.valueId (mkAggregateVal outLeaves)
    | .constant constantId => do
        let constant ← match data.constants[constantId.toNat]? with
          | some c => pure c
          | none =>
              planError "unsupported Psy semantic shape: Constant references an unknown constant id"
        unless constant.id == constantId do
          planError "unsupported Psy semantic shape: Constant id does not match declaration order"
        let valueDef ← match instr.result with
          | some vd => pure vd
          | none =>
              planError "unsupported Psy semantic shape: Constant instruction must produce a value"
        unless valueDef.typeId == constant.typeId do
          planError "unsupported Psy semantic shape: Constant result typeId must match the declaration"
        validateConstantRepresentabilityV1 data constant.typeId constant.valueBytes
        let value ← lowerLiteralValue data layout constant.typeId constant.valueBytes
        env := envInsertVal env valueDef.valueId value
    | .checkedCast valueId toType => do
        -- PSY-INDEX-CAST: UInt/Int width casts with exact castOutOfRange assert.
        -- Felt-carried bit patterns; no silent truncate. Int64 mixed casts FC.
        match instr.result with
        | none => planError "unsupported Psy semantic shape: CheckedCast must produce a value"
        | some valueDef =>
            unless valueDef.typeId == toType do
              planError "unsupported Psy semantic shape: CheckedCast result typeId must equal toType"
            let src ← match envLookup env valueId with
              | some v => pure v
              | none => planError "unsupported Psy semantic shape: CheckedCast references undefined value"
            unless !src.isAggregate && !src.isWideUint do
              planError "unsupported Psy semantic shape: CheckedCast operand must be a scalar UInt/Int"
            let srcSigned? : Option Bool :=
              if src.isNarrow then some false
              else if src.isNarrowInt then some true
              else if src.intWidth == 64 then some true
              else if src.uintWidth == 0 || src.uintWidth == 64 then some false
              else none
            let srcW? : Option Nat :=
              if src.isNarrow then some src.uintWidth
              else if src.isNarrowInt then some src.intWidth
              else if src.intWidth == 64 then some 64
              else if src.uintWidth == 0 || src.uintWidth == 64 then some 64
              else none
            let srcSigned ← match srcSigned? with
              | some b => pure b
              | none => planError "unsupported Psy semantic shape: CheckedCast source width unresolved"
            let srcW ← match srcW? with
              | some w => pure w
              | none => planError "unsupported Psy semantic shape: CheckedCast source width unresolved"
            let dstUW? := uintWidthOfType data toType
            let dstIW? := intWidthOfType data toType
            let (dstSigned, dstW) ← match dstUW?, dstIW? with
              | some w, _ =>
                  unless isNarrowUintWidth w || w == 64 do
                    planError s!"unsupported Psy semantic shape: CheckedCast to UInt{w} is outside Psy"
                  pure (false, w)
              | none, some w =>
                  unless isNarrowIntWidth w || w == 64 do
                    planError s!"unsupported Psy semantic shape: CheckedCast to Int{w} is outside Psy"
                  pure (true, w)
              | none, none =>
                  planError "unsupported Psy semantic shape: CheckedCast destination must be UInt/Int"
            unless srcW != 64 && dstW != 64 do
              planError "unsupported Psy semantic shape: CheckedCast involving UInt64/Int64 remains fail closed on Psy Felt (no full 2^64 domain)"
            let srcE := src.expr
            if !srcSigned && !dstSigned then
              let bound ← uintExclusiveBoundNatV1 dstW
              let guard : Statement :=
                .assertWithMessage
                  (.compare .lt srcE (.literal (UInt64.ofNat bound)))
                  "castOutOfRange"
              ls := { ls with stmts := ls.stmts.push guard }
              env := envInsertNarrow env valueDef.valueId dstW srcE
            else if srcSigned && dstSigned then
              if srcW == dstW || srcW < dstW then
                env := envInsertVal env valueDef.valueId (mkNarrowIntVal dstW srcE)
              else
                let maxD ← intSignedMaxNatV1 dstW
                let maskD ← intTwoComplementMaskNatV1 dstW
                let negStart : Nat :=
                  match srcW, dstW with
                  | 16, 8 => 65408
                  | 32, 8 => 4294967168
                  | 32, 16 => 4294934528
                  | _, _ =>
                      (Nat.pow 2 srcW) - (Nat.pow 2 (dstW - 1))
                let inRange :=
                  .logicalOr
                    (.compare .le srcE (.literal (UInt64.ofNat maxD)))
                    (.compare .ge srcE (.literal (UInt64.ofNat negStart)))
                let guard : Statement := .assertWithMessage inRange "castOutOfRange"
                ls := { ls with stmts := ls.stmts.push guard }
                let truncated := .bitAnd srcE (.literal (UInt64.ofNat maskD))
                env := envInsertVal env valueDef.valueId (mkNarrowIntVal dstW truncated)
            else if !srcSigned && dstSigned then
              let maxD ← intSignedMaxNatV1 dstW
              let guard : Statement :=
                .assertWithMessage
                  (.compare .le srcE (.literal (UInt64.ofNat maxD)))
                  "castOutOfRange"
              ls := { ls with stmts := ls.stmts.push guard }
              env := envInsertVal env valueDef.valueId (mkNarrowIntVal dstW srcE)
            else
              let maxS ← intSignedMaxNatV1 srcW
              let boundD ← uintExclusiveBoundNatV1 dstW
              let inRange :=
                .logicalAnd
                  (.compare .le srcE (.literal (UInt64.ofNat maxS)))
                  (.compare .lt srcE (.literal (UInt64.ofNat boundD)))
              let guard : Statement := .assertWithMessage inRange "castOutOfRange"
              ls := { ls with stmts := ls.stmts.push guard }
              env := envInsertNarrow env valueDef.valueId dstW srcE
    -- PSY-CONTEXT-COMMIT (evidence FC): the direct DPN contract has no bound
    -- public-input/witness source for wall-clock, caller, or height. Unanchored
    -- injection proves only that the program used T, not that T is chain
    -- reality. Commit also needs a frozen proof/public-input/commitment binding.
    | .contextRead key =>
        if key == unixTimeSecondsContextKeyV1 then
          planError
            "unsupported Psy semantic shape: ContextRead context.unixTimeSeconds has no bound DPN wall-clock input (circuit-domain FC)"
        else if key == callerContextKeyV1 then
          planError
            "unsupported Psy semantic shape: ContextRead context.caller has no bound DPN caller input; Principal is not a Psy address (circuit-domain FC)"
        else if key == blockHeightContextKeyV1 then
          planError
            "unsupported Psy semantic shape: ContextRead context.blockHeight has no bound DPN height input (circuit-domain FC)"
        else
          planError
            s!"unsupported Psy semantic shape: unknown ContextRead key '{key.value}' is not admitted by pilot context policy"
    | .commit .. =>
        planError
          "unsupported Psy semantic shape: Commit is not admitted (proof/public-input/commitment binding not frozen on Psy; Felt identity passthrough would overclaim cryptographic commitment; B-COMMIT-ZK FC)"
    -- ADR-0030 E2: env-read (pf.assets balanceOfSelf) is fail closed on Psy
    -- (Psy/Aleo zero-binding disposition).
    | .envRead .. =>
        planError
          "unsupported Psy semantic shape: EnvRead is not admitted (no native Psy balance/vault host read; ADR-0029 zero-binding FC)"
  match block.terminator with
  | .jump target =>
      if isActiveHeader loops target.blockId then
        pure { stmts := ls.stmts, join? := none }
      else if isLoopHeaderV1 callable target.blockId then
        lowerLoop data layout callable fnNames expectedAggregateLeaves target ls env loops
      else
        lowerRegion data layout callable fnNames expectedAggregateLeaves target.blockId.toNat loops env ls
  | .branch condition thenTarget elseTarget => do
      let c ← match envLookupExpr env condition with
        | some e => pure e
        | none => planError "unsupported Psy semantic shape: branch references an undefined condition"
      let emptyLs : LowerStateV1 := { stmts := #[] }
      let thenRes ← lowerRegion data layout callable fnNames expectedAggregateLeaves thenTarget.blockId.toNat loops env emptyLs
      let elseRes ← lowerRegion data layout callable fnNames expectedAggregateLeaves elseTarget.blockId.toNat loops env emptyLs
      let join? ← match thenRes.join?, elseRes.join? with
        | none, none => pure none
        | some j, none => pure (some j)
        | none, some j => pure (some j)
        | some j1, some j2 =>
            if j1 == j2 then pure (some j1)
            else planError "unsupported Psy semantic shape: branch arms join at different blocks"
      let stmts := ls.stmts.push (.ifThenElse c thenRes.stmts elseRes.stmts)
      pure { stmts, join? }
  | .switch scrutinee cases defaultTarget => do
      let sVal ← match envLookup env scrutinee with
        | some v => pure v
        | none => planError "unsupported Psy semantic shape: switch references an undefined scrutinee"
      if sVal.isWideUint then
        planError "unsupported Psy semantic shape: Switch on UInt128/256 is outside the Psy VM profile"
      let s := sVal.expr
      -- Case values: UInt64 wire decoding for 8-byte; narrow switch cases use
      -- the same LE decode path sized to the scrutinee width.
      let mut caseStmts : Array (UInt64 × Array Statement) := #[]
      let mut joins : Array Nat := #[]
      for case in cases do
        let value ←
          if sVal.isNarrow then
            match sVal.uintWidth with
            | 8 => decodeUInt8LiteralV1 case.valueBytes
            | 16 => decodeUInt16LiteralV1 case.valueBytes
            | 32 => decodeUInt32LiteralV1 case.valueBytes
            | _ => decodeUInt64LiteralV1 case.valueBytes
          else
            match decodeUInt64LiteralV1 case.valueBytes with
            | .ok v => pure v
            | .error e => .error e
        let emptyLs : LowerStateV1 := { stmts := #[] }
        let targetRes ← lowerRegion data layout callable fnNames expectedAggregateLeaves case.target.blockId.toNat loops env emptyLs
        caseStmts := caseStmts.push (value, targetRes.stmts)
        match targetRes.join? with
        | some j => joins := joins.push j
        | none => pure ()
      let emptyLs : LowerStateV1 := { stmts := #[] }
      let defaultRes ← match defaultTarget with
        | none => regionClosed
        | some t => lowerRegion data layout callable fnNames expectedAggregateLeaves t.blockId.toNat loops env emptyLs
      match defaultRes.join? with
      | some j => joins := joins.push j
      | none => pure ()
      let join? ← match joins.toList with
        | [] => pure none
        | j :: rest =>
            if rest.all (· == j) then pure (some j)
            else planError "unsupported Psy semantic shape: switch arms join at different blocks"
      let stmts := ls.stmts.push (.switchOn s caseStmts defaultRes.stmts)
      pure { stmts, join? }
  | .return_ value => do
      let stmts ← match value with
        | none => pure (ls.stmts.push .returnNone)
        | some vid =>
            match envLookup env vid with
            | some v =>
                match expectedAggregateLeaves with
                | some expectedLeaves =>
                    -- B-RET-ABI plus the VM-profile UInt128/256 ABI. Wide values
                    -- are 4/8 unsigned 4-byte limbs; other aggregates remain
                    -- 1..8 UInt64/Int64 words.
                    unless v.isAggregate do
                      planError "unsupported Psy semantic shape: aggregate return value must be a multi-leaf aggregate"
                    let expectsWideUint :=
                      (expectedLeaves.size == 4 || expectedLeaves.size == 8) &&
                        expectedLeaves.all (fun leaf => !leaf.isInt && leaf.byteWidth == 4)
                    if expectsWideUint then
                      let ok :=
                        (expectedLeaves.size == 4 && v.isWideUInt128) ||
                          (expectedLeaves.size == 8 && v.isWideUInt256)
                      unless ok do
                        planError s!"unsupported Psy semantic shape: UInt{expectedLeaves.size * 32} return requires {expectedLeaves.size} UInt32 limbs"
                    else if v.isWideUint then
                      planError "unsupported Psy semantic shape: wide UInt value cannot satisfy a non-wide aggregate return"
                    let gotLeaves := v.leafExprs
                    unless gotLeaves.size == expectedLeaves.size do
                      planError s!"unsupported Psy semantic shape: aggregate return leaf count mismatch (expected {expectedLeaves.size}, got {gotLeaves.size})"
                    let mut leafIsInt : Array Bool := #[]
                    for leaf in expectedLeaves do
                      unless leaf.byteWidth == 1 || leaf.byteWidth == 4 || leaf.byteWidth == 8 do
                        planError "unsupported Psy semantic shape: aggregate return leaves must be Bytes UInt8, UInt32 limbs, or UInt64/Int64 words"
                      if leaf.byteWidth == 4 && leaf.isInt then
                        planError "unsupported Psy semantic shape: wide UInt ABI limbs must be unsigned UInt32"
                      leafIsInt := leafIsInt.push leaf.isInt
                    pure (ls.stmts.push (.returnAggregate gotLeaves leafIsInt))
                | none =>
                    if v.isAggregate then
                      planError "unsupported Psy semantic shape: return of aggregate is outside the Psy scalar result envelope (B-RET-ABI: named Struct/Enum and admitted anonymous Array/Option entry/view returns only; Map/Bytes and pureFn aggregates stay fail-closed)"
                    pure (ls.stmts.push (.returnValue v.expr))
            | none => planError "unsupported Psy semantic shape: return references an undefined value"
      pure { stmts, join? := none }
  | .revert errorId args => do
      -- PSY-TYPED-ERROR: zero-payload named revert becomes a tagged failing
      -- DPN assert. Nonempty payloads have no structured DPN ABI.
      unless args.isEmpty do
        let errName :=
          match data.errors[errorId.toNat]? with
          | some e => e.name
          | none => "error"
        planError
          s!"unsupported Psy semantic shape: revert '{errName}' payload requires a structured DPN error ABI (zero-payload named revert remains open; PSY-TYPED-ERROR FC)"
      let stmts := ls.stmts.push (.revertError errorId.toNat #[])
      pure { stmts, join? := none }
  | .trap _ => do
      let stmts := ls.stmts.push .bareRevert
      pure { stmts, join? := none }

private partial def lowerLoop
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String))
    (expectedAggregateLeaves : Option (Array LeafAbiType))
    (target : JumpTargetV1) (ls : LowerStateV1) (env : ValueEnv)
    (loops : Array LoopCtxV1) : CompileResult RegionResult := do
  let headerIdx := target.blockId.toNat
  let lb ← match callable.loopBounds.findSome? (fun lb =>
      if lb.header == target.blockId then some lb else none) with
    | some lb => pure lb
    | none => planError "unsupported Psy semantic shape: loop bound missing for header"
  if loops.any (fun ctx => ctx.header == target.blockId) then
    planError "unsupported Psy semantic shape: re-entered an active loop header"
  let header ← match callable.blocks[headerIdx]? with
    | some b => pure b
    | none => planError "unsupported Psy semantic shape: loop header block is missing"
  unless header.params.size == 1 do
    planError "unsupported Psy semantic shape: loop header must carry exactly one block parameter"
  let some paramDef := header.params[0]? |
    planError "unsupported Psy semantic shape: loop header parameter is missing"
  unless paramDef.typeId == layout.types.uint64TypeId do
    planError "unsupported Psy semantic shape: loop header must carry one UInt64 parameter"
  unless target.args.size == 1 do
    planError "unsupported Psy semantic shape: loop entry must carry exactly one argument"
  let startVid ← match target.args[0]? with
    | some v => pure v
    | none => planError "unsupported Psy semantic shape: loop start value is missing"
  let startVal ← match envLookup env startVid with
    | some v => pure v
    | none => planError "unsupported Psy semantic shape: loop start value is not defined"
  -- PSY-LOOP: only public UInt64 induction is admitted through a guarded
  -- static DPN unroll. Narrow UInt and Int endpoints stay fail closed.
  if startVal.isNarrow || startVal.isNarrowInt || startVal.intWidth == 64 then
    planError
      "unsupported Psy semantic shape: non-UInt64 loop endpoints are not admitted (PSY-LOOP supports UInt64 through guarded DPN static unroll only)"
  let startExpr := startVal.expr
  let mut condVid? : Option ValueIdV1 := none
  let mut endExpr? : Option Expr := none
  for instr in header.instructions do
    match instr.op with
    | .binary .lt lhs rhs => do
        unless lhs == paramDef.valueId do
          planError "unsupported Psy semantic shape: loop condition lhs must be the induction parameter"
        let rVal ← match envLookup env rhs with
          | some v => pure v
          | none => planError "unsupported Psy semantic shape: loop end value is not defined"
        if rVal.isNarrow || rVal.isNarrowInt || rVal.intWidth == 64 then
          planError
            "unsupported Psy semantic shape: non-UInt64 loop endpoints are not admitted (PSY-LOOP supports UInt64 through guarded DPN static unroll only)"
        match instr.result with
        | some valueDef => condVid? := some valueDef.valueId
        | none => planError "unsupported Psy semantic shape: loop condition must produce a value"
        endExpr? := some rVal.expr
    | _ =>
        planError "unsupported Psy semantic shape: loop header carries an unexpected instruction"
  let endExpr ← match endExpr? with
    | some e => pure e
    | none => planError "unsupported Psy semantic shape: loop header must compute `i < end`"
  let depth := loops.size
  let envLoop := envInsert env paramDef.valueId (.loopVar depth)
  let loops' := loops.push { header := target.blockId }
  match header.terminator with
  | .branch condVid thenTarget _ => do
      match condVid? with
      | some expected =>
          unless condVid == expected do
            planError "unsupported Psy semantic shape: loop branch condition does not match the header computation"
      | none => planError "unsupported Psy semantic shape: loop header branch condition is missing"
      let emptyBody : LowerStateV1 := { stmts := #[] }
      let thenRes ← lowerRegion data layout callable fnNames expectedAggregateLeaves thenTarget.blockId.toNat loops' envLoop emptyBody
      unless thenRes.join?.isNone do
        planError "unsupported Psy semantic shape: loop body must end at the latch back edge"
      let body := thenRes.stmts
      let maxIter := lb.maxIterations.toNat
      unless maxIter ≤ 4096 do
        planError "unsupported Psy semantic shape: loop bound exceeds the wire maximum"
      let forStmt := .forLoop startExpr endExpr maxIter body
      match header.terminator with
      | .branch _ _ elseTarget =>
          let ls' : LowerStateV1 := { ls with stmts := ls.stmts.push forStmt }
          lowerRegion data layout callable fnNames expectedAggregateLeaves elseTarget.blockId.toNat loops env ls'
      | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"
  | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"

end

/-- Resolve callable result to Plan scalar flags + resultUintWidth + ResultKind.
    UInt{8,16,32,64} all emit as Felt (narrow width documented on PlanFunction).
    Named Struct/Enum and admitted anonymous Array UInt64 N / Option UInt64 /
    Bytes N (1..8) entry/view results become `.aggregate` (cap-8). pureFn
    aggregate is rejected by the pureFn gate below; Map/nested stay FC.
    Principal/String results FC (9 leaves > cap 8). -/
private def resultShape (data : SemanticProgramDataV1)
    (types : PsyTypeClosureV1)
    (typeDecls : Array TypeDeclV1) (callable : CallableV1) (owner : String) :
    CompileResult (Bool × Bool × Nat × ResultKind) := do
  if isBoolType data callable.result.typeId then pure (true, false, 0, .bool)
  else if isUInt64Type data callable.result.typeId then pure (false, false, 64, .felt)
  else if uintWidthOfType data callable.result.typeId == some 128 then
    pure (false, false, 128,
      .aggregate (Array.replicate 4 { isInt := false, byteWidth := 4 }))
  else if uintWidthOfType data callable.result.typeId == some 256 then
    pure (false, false, 256,
      .aggregate (Array.replicate 8 { isInt := false, byteWidth := 4 }))
  else if isInt64Type data callable.result.typeId then pure (false, false, 0, .felt)
  else if let some w := intWidthOfType data callable.result.typeId then
    if isNarrowIntWidth w then pure (false, false, w, .felt)
    else pure (false, false, 0, .felt)
  else if let some w := uintWidthOfType data callable.result.typeId then
    if isNarrowUintWidth w then pure (false, false, w, .felt)
    else pure (false, false, 64, .felt)
  else if isGoldilocksFieldType types callable.result.typeId then pure (false, false, 0, .felt)
  else if isUnitType data callable.result.typeId then pure (false, true, 0, .unit)
  else if types.isPrincipal callable.result.typeId || types.isString callable.result.typeId then
    planError s!"{owner} Principal/String result is outside Psy B-RET-ABI (wire identity is 9 leaves > cap 8; state/param only)"
  else if isAggregateResultCandidateV1 typeDecls types callable.result.typeId then
    let kind ← aggregateResultKindOfV1 typeDecls types owner callable.result.typeId
    pure (false, false, 0, kind)
  else
    planError s!"{owner} result is outside the public UInt8/16/32/64/Int/Bool/Goldilocks-Field/Unit/named/Array/Option/Bytes envelope"

private def lowerCallable
    (data : SemanticProgramDataV1) (layout : PsyLowerLayoutV1) (callable : CallableV1)
    (fnNames : Array (CallableIdV1 × String)) :
    CompileResult PlanFunction := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty do
    planError "unsupported Psy semantic shape: callable must have entry block 0"
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      planError "unsupported Psy semantic shape: loop header block is missing"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      planError "unsupported Psy semantic shape: loop latch block is missing"
    unless header.params.size == 1 do
      planError "unsupported Psy semantic shape: loop header must carry one UInt64 parameter"
    match header.terminator with
    | .branch .. => pure ()
    | _ => planError "unsupported Psy semantic shape: loop header must end in a branch"
    match latch.terminator with
    | .jump t =>
        unless t.blockId == lb.header && t.args.size == 1 do
          planError "unsupported Psy semantic shape: loop latch must jump back with one argument"
    | _ => planError "unsupported Psy semantic shape: loop latch must jump back to the header"
  for blk in callable.blocks do
    unless blk.params.isEmpty ||
        callable.loopBounds.any (fun lb => lb.header == blk.id) do
      planError "unsupported Psy semantic shape: block parameters are only supported on loop headers"
  let name ← match callable.name with
    | some n => pure n
    | none => pure "initialize"
  let owner :=
    match callable.kind with
    | .initializer => "initializer"
    | .pureFn => s!"pureFn '{name}'"
    | .entry => s!"entry '{name}'"
    | .view => s!"view '{name}'"
    | .invariant => s!"invariant '{name}'"
  let mut params : Array PlanParam := #[]
  let mut physicalParamIndex : Nat := 0
  let types := layout.types
  for p in callable.params do
    if types.isPrincipal p.typeId || types.isString p.typeId then
      for limbIndex in [0:1 + psyWireIdentityBodyLimbCountV1] do
        let leafName :=
          if limbIndex == 0 then s!"{p.name}_len" else s!"{p.name}_b{limbIndex - 1}"
        params := params.push
          { sourceIndex := physicalParamIndex,
            name := leafName, isBool := false,
            uintWidth := 32, isField := false }
        physicalParamIndex := physicalParamIndex + 1
    else
      match ← bytesLeafCountV1 layout.typeDecls types p.typeId with
      | some n =>
          for limbIndex in [0:n] do
            params := params.push
              { sourceIndex := physicalParamIndex,
                name := s!"{p.name}_{limbIndex}", isBool := false,
                uintWidth := 8, isField := false }
            physicalParamIndex := physicalParamIndex + 1
      | none =>
          match uintWidthOfType data p.typeId with
          | some 128 | some 256 =>
              let bitWidth := (uintWidthOfType data p.typeId).getD 128
              for limbIndex in [0:wideLimbCountOf bitWidth] do
                params := params.push
                  { sourceIndex := physicalParamIndex,
                    name := s!"{p.name}_limb{limbIndex}", isBool := false,
                    uintWidth := 32, isField := false }
                physicalParamIndex := physicalParamIndex + 1
          | width? =>
              let intW? := intWidthOfType data p.typeId
              let isBool ← if isBoolType data p.typeId then pure true
                else if isUInt64Type data p.typeId || isInt64Type data p.typeId then pure false
                else if match width? with
                    | some w => isNarrowUintWidth w || w == 64
                    | none => false then pure false
                else if match intW? with
                    | some w => isNarrowIntWidth w
                    | none => false then pure false
                else if isGoldilocksFieldType types p.typeId then pure false
                else if types.isNamedAggregate p.typeId then
                  -- PSY-CONTAINER-ABI: expand named Struct/Enum params to
                  -- preorder scalar Felt leaves (same flatten as state).
                  let leafSpecs ←
                    flattenTypeLeafSpecsV1 layout.typeDecls types p.typeId p.name
                  unless leafSpecs.size ≥ 1 do
                    planError s!"unsupported Psy semantic shape: named aggregate parameter '{p.name}' flattened to zero leaves"
                  unless leafSpecs.size ≤ 8 do
                    planError s!"unsupported Psy semantic shape: named aggregate parameter '{p.name}' has {leafSpecs.size} leaves, exceeding the B-RET-ABI cap of 8"
                  for leafName in leafSpecs do
                    params := params.push
                      { sourceIndex := physicalParamIndex,
                        name := leafName, isBool := false,
                        uintWidth := 0, isField := false }
                    physicalParamIndex := physicalParamIndex + 1
                  pure false  -- unused; we already pushed leaves
                else if isAnonymousOptionTypeIdV1 layout.typeDecls p.typeId then
                  planError s!"unsupported Psy semantic shape: Option parameter '{p.name}' in {owner} is outside the Psy pilot (Option is state-only; B-RET-ABI scalar)"
                else planError "unsupported Psy semantic shape: callable parameter is outside the UInt/Int/Bool/Field/Bytes/Principal/String/named-aggregate envelope"
              -- Named-aggregate branch already pushed leaves and set isBool false
              -- via a dummy path; only push a scalar param for non-aggregate.
              if types.isNamedAggregate p.typeId then
                pure ()
              else
                let uintWidth :=
                  match width? with
                  | some w => w
                  | none =>
                      match intW? with
                      | some w => if isNarrowIntWidth w then w else 0
                      | none => 0
                params := params.push
                  { sourceIndex := physicalParamIndex, name := p.name, isBool,
                    uintWidth,
                    isField := isGoldilocksFieldType types p.typeId }
                physicalParamIndex := physicalParamIndex + 1
  let mut env0 : ValueEnv := default
  let mut physicalParamOrdinal : Nat := 0
  for p in callable.params do
    if types.isPrincipal p.typeId || types.isString p.typeId then
      let mut limbs : Array Expr := #[]
      for _ in [0:1 + psyWireIdentityBodyLimbCountV1] do
        limbs := limbs.push (.param physicalParamOrdinal)
        physicalParamOrdinal := physicalParamOrdinal + 1
      env0 := envInsertVal env0 p.valueId (mkAggregateVal limbs)
    else if types.isNamedAggregate p.typeId then
      let leafSpecs ← flattenTypeLeafSpecsV1 layout.typeDecls types p.typeId p.name
      let mut limbs : Array Expr := #[]
      for _ in leafSpecs do
        limbs := limbs.push (.param physicalParamOrdinal)
        physicalParamOrdinal := physicalParamOrdinal + 1
      env0 := envInsertVal env0 p.valueId (mkAggregateVal limbs)
    else
      match ← bytesLeafCountV1 layout.typeDecls types p.typeId with
      | some n =>
          let mut limbs : Array Expr := #[]
          for _ in [0:n] do
            limbs := limbs.push (.param physicalParamOrdinal)
            physicalParamOrdinal := physicalParamOrdinal + 1
          env0 := envInsertVal env0 p.valueId (mkAggregateVal limbs)
      | none =>
          match uintWidthOfType data p.typeId with
          | some 128 | some 256 =>
              let bitWidth := (uintWidthOfType data p.typeId).getD 128
              let mut limbs : Array Expr := #[]
              for _ in [0:wideLimbCountOf bitWidth] do
                limbs := limbs.push (.param physicalParamOrdinal)
                physicalParamOrdinal := physicalParamOrdinal + 1
              env0 := envInsertVal env0 p.valueId (mkWideUintVal bitWidth limbs)
          | some w =>
              if isNarrowUintWidth w then
                env0 := envInsertNarrow env0 p.valueId w (.param physicalParamOrdinal)
              else
                env0 := envInsert env0 p.valueId (.param physicalParamOrdinal)
              physicalParamOrdinal := physicalParamOrdinal + 1
          | none =>
              match intWidthOfType data p.typeId with
              | some w =>
                  if isNarrowIntWidth w then
                    env0 := envInsertVal env0 p.valueId
                      (mkNarrowIntVal w (.param physicalParamOrdinal))
                  else
                    env0 := envInsertVal env0 p.valueId (mkInt64Val (.param physicalParamOrdinal))
                  physicalParamOrdinal := physicalParamOrdinal + 1
              | none =>
                  if isGoldilocksFieldType types p.typeId then
                    env0 := envInsertVal env0 p.valueId (mkFieldVal (.param physicalParamOrdinal))
                  else if isInt64Type data p.typeId then
                    env0 := envInsertVal env0 p.valueId (mkInt64Val (.param physicalParamOrdinal))
                  else
                    env0 := envInsert env0 p.valueId (.param physicalParamOrdinal)
                  physicalParamOrdinal := physicalParamOrdinal + 1
  let (resultIsBool, resultIsUnit, resultUintWidth, resultKind) ←
    resultShape data layout.types layout.typeDecls callable owner
  -- pureFn aggregate returns stay fail closed (B-RET-ABI entry/view only).
  match resultKind with
  | .aggregate _ =>
      match callable.kind with
      | .pureFn =>
          planError s!"pureFn '{name}' cannot return an aggregate (B-RET-ABI: pureFn aggregate returns stay fail-closed; named Struct/Enum and anonymous Array/Option returns are entry/view only)"
      | .initializer =>
          planError "initializer cannot return an aggregate"
      | _ => pure ()
  | _ => pure ()
  let expectedAggregateLeaves : Option (Array LeafAbiType) :=
    match resultKind with
    | .aggregate leaves => some leaves
    | _ => none
  let empty0 : LowerStateV1 := { stmts := #[] }
  let res ← lowerRegion data layout callable fnNames expectedAggregateLeaves 0 #[] env0 empty0
  unless res.join?.isNone do
    planError "unsupported Psy semantic shape: callable does not end in return on all paths"
  let body := res.stmts
  let kind := match callable.kind with
    | .initializer => FunctionKind.initialize
    | .pureFn => FunctionKind.pureHelper
    | _ => FunctionKind.mutate
  pure {
    index := 0
    name
    kind
    params
    body
    resultIsBool
    resultIsUnit
    resultUintWidth
    resultKind
  }

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let types ← validatePsyTypeClosureV1 data.types
  let layout ← makeStateLayoutV1 types data.types data.logicalState
  let mut events : Array PlanEvent := #[]
  for ev in data.events do
    let fieldNames := ev.fields.map (·.name)
    events := events.push { name := ev.name, fieldNames }
  let mut errors : Array PlanErrorDecl := #[]
  for err in data.errors do
    let fieldNames := err.fields.map (·.name)
    errors := errors.push { name := err.name, fieldNames }
  let fnNames := data.callables.filterMap fun c =>
    match c.kind with
    | .pureFn => some (c.id, c.name.getD "fn")
    | _ => none
  -- DPN has no target predicate/fuel contract for Semantic invariants.
  if !data.invariants.isEmpty then
    let names := data.invariants.map (·.name)
    let listed := String.intercalate ", " names.toList
    planError
      s!"unsupported Psy DPN semantic shape: nonempty invariants [{listed}] have no predicate-closure and invariantSteps binding"
  let mut functions : Array PlanFunction := #[]
  for callable in data.callables do
    match callable.kind with
    | .invariant =>
        let invName := callable.name.getD "<unnamed>"
        planError
          s!"unsupported Psy DPN semantic shape: invariant '{invName}' has no predicate-closure and invariantSteps binding"
    | .initializer | .entry | .view | .pureFn =>
        let fn ← lowerCallable data layout callable fnNames
        functions := functions.push { fn with index := functions.size }
  pure {
    programName
    stateFieldNames := layout.fieldNames
    functions
    events
    errors
    sourceHash
    semanticHash
  }

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Psy received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

/-- Internal Psy family phase entry: capability → Plan (pre-canonicity).
    Kind must be `.psy` (TargetKind already includes psy; P-B flips registry
    membership/default profile so product selection can mint a capability). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .psy do
    throw <| .planInvariant .psy "engineering capability kind is not Psy"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  validateCodegenProfileV1 (ResolvedEngineeringBuildV1.codegenProfileOf capability)
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Psy source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Psy semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

/-- Pre-P-B / unit-test Plan entry: retained SemanticProgramV1 only. Same body
    as the capability path after the kind check. Product materialize remains
    capability-only once P-B wires registry/descriptor/support. -/
def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Psy source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Psy semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Psy
