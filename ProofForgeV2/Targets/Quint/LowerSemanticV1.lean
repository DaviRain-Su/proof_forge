import ProofForgeV2.Core.Common
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Quint LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Q0 source-only Quint target: public UInt64 **or** public Int64 state
(homogeneous numeric domain), public UInt64/Int64/Principal params
(Principal identity-only for pf.assets args; mixing UInt64 with Int64
fails closed), public Unit/UInt64/Int64/Bool results, single-block
callables, pureFn inline (depth ≤ 64), zero-param Bool invariants.
Anonymous `Array UInt64 N` (N=1..8) **state** flattens to N UInt64
Plan leaves `{name}_0`..`{name}_{N-1}` (no native Quint List).
Anonymous `Option UInt64` **state** flattens to two UInt64 leaves
`{name}_tag` + `{name}_p0` (tag 0=none / 1=some; none zeros payload).
Anonymous `Map UInt64 UInt64` **state** flattens to 24 UInt64 leaves
(cap-8 × occ/key/val interleaved; `Map.empty` + IndexSet upsert;
IndexGet → Option tag+payload). Array/Option/Map + signedNumeric,
Array/Option/Map param/return, N=0/N>8, non-UInt64 element/payload/key,
non-literal Array index, nested arrays/Option/Map, and Bytes fail closed.
Plan is target-owned and retains no Semantic carrier.

ADR-0029 Phase A5: void `Op.ExternalCall` whose callee is in the closed
`pf.assets` catalog is admitted only when the retained freeze carries exact
`extension.pf-assets`, and only for the Phase A vault subset:
  * `pf.assets.native.deposit(amount)` — nondet external outcome; success
    credits target-owned `vaultNative` (checked UInt64 add);
  * `pf.assets.native.transfer(dst, amount)` — nondet external outcome;
    success requires `vaultNative ≥ amount` then debits (Q0 explicit-failure
    discipline: insufficient vault is a first-failure outcome + stutter, not
    a blocked action).
Async (`*.transferAsync`) and token (`token.*`) QNs fail closed (no fake
native alias; token needs mint-keyed Map beyond Q0 Int vault). Non-catalog
QNs fail closed at Plan lowering (resolver may admit `effect.synchronous-call`
for them). `pf.crypto.*` is a dedicated honesty class: Quint has no
sha256/keccak256 host, so those QNs stay fail closed instead of the generic
pf.assets catch-all. Whole-entry atomic: any failure stutters business state
and vault.

Failure codes (evaluation order, first failure wins at emission):
  overflow=1, underflow=2, division-by-zero=3, assertion=4,
  externalCallFailed=5, vaultOverflow=6, vaultUnderflow=7,
  zero-payload declared-revert=256+canonical ErrorId
-/

namespace ProofForgeV2.Targets.Quint

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Engineering codegen profile spelling for the Quint UInt64 model slice. -/
def codegenProfileString : String := "quint-source-u64-model-v1"

/-- Well-known profile constant (wired by main-agent TargetIdentity cutover). -/
def codegenProfile : CodegenProfileId := CodegenProfileId.quintSourceU64ModelV1

/-- Emitted-syntax compatibility label only; not a Tool Lock identity. -/
def emitterSyntaxNote : String := "quint-0.32-compatible-source"

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .quint message

private def quintPlanErr (message : String) : CompileError :=
  .planInvariant .quint message

-- ---------------------------------------------------------------------------
-- Target-owned Plan surface
-- ---------------------------------------------------------------------------

inductive ExprType where
  | uint64
  | int64
  | bool
  /-- Opaque identity for pf.assets destination args; not arithmetic. -/
  | principal
  deriving BEq, Inhabited, Repr

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive ArithOp where
  | add | sub | mul | div | mod
  deriving BEq, Inhabited, Repr

/-- First-failure codes used by emission instrumentation. -/
inductive FailureKind where
  | overflow
  | underflow
  | divByZero
  | assertion
  /-- Nondet external callee outcome reverted (Reference responses cursor). -/
  | externalCallFailed
  /-- `pf.assets.native.deposit` would overflow UInt64 vault. -/
  | vaultOverflow
  /-- `pf.assets.native.transfer` amount exceeds current vault (explicit fail). -/
  | vaultUnderflow
  /-- Preserve canonical Semantic ErrorId identity for a revert propagated
      through a pureCall. -/
  | declaredRevert (errorIndex : Nat)
  /-- Root callable terminator marker; Plan validation binds this iff
      `PlanEntry.terminalRevert=true`. -/
  | terminalRevert (errorIndex : Nat)
  deriving BEq, Inhabited, Repr

def FailureKind.code : FailureKind → Nat
  | .overflow => 1
  | .underflow => 2
  | .divByZero => 3
  | .assertion => 4
  | .externalCallFailed => 5
  | .vaultOverflow => 6
  | .vaultUnderflow => 7
  | .declaredRevert errorIndex | .terminalRevert errorIndex => 256 + errorIndex

/-- Untyped expression nodes; every Plan use-site carries an explicit `ExprType`. -/
inductive Expr where
  | litU64 (value : UInt64)
  | litBool (value : Bool)
  | param (index : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- Pre-action target-owned self-vault native balance (UInt64 domain). -/
  | vaultNative
  /-- Nondet external outcome for asset op `ordinal` (Bool; emission binds). -/
  | externalOk (ordinal : Nat)
  | arith (op : ArithOp) (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | boolAnd (lhs rhs : Expr)
  | boolOr (lhs rhs : Expr)
  | boolNot (operand : Expr)
  /-- Dense Map mux: `if cond then t else e`. Cond is Bool; t/e share a type. -/
  | ite (cond t e : Expr)
  deriving BEq, Inhabited, Repr

/-- Phase A Quint-admitted pf.assets vault op (sync native only). -/
inductive PfAssetsKind where
  | nativeDeposit
  | nativeTransfer
  deriving BEq, Inhabited, Repr

/-- One void pf.assets ExternalCall lowered into vault math + nondet outcome. -/
structure PfAssetsOp where
  kind : PfAssetsKind
  amount : Expr
  deriving BEq, Inhabited, Repr

structure TypedExpr where
  ty : ExprType
  expr : Expr
  /-- Fully expanded tree cost. This is tracked while substituting SSA values
      and pureFn arguments so a small CFG cannot manufacture exponentially
      large rendered Quint expressions. -/
  expandedNodes : Nat
  /-- Nonempty = flattened `Array UInt64 N` or `Option UInt64` leaves.
      Empty = scalar. -/
  leaves : Array Expr := #[]
  /-- True when `leaves` is Option tag+payload (`[tag, p0]`). -/
  isOption : Bool := false
  /-- True when `leaves` is dense Map UInt64 cap-8 (24 occ/key/val). -/
  isMap : Bool := false
  deriving BEq, Inhabited, Repr

/-- Success condition (Bool) that must hold; evaluated in array order. -/
structure Check where
  kind : FailureKind
  condition : Expr
  deriving BEq, Inhabited, Repr

inductive ResultKind where
  | unit
  | uint64
  | int64
  | bool
  deriving BEq, Inhabited, Repr

structure PlanState where
  name : String
  deriving BEq, Inhabited, Repr

/-- Initializer: no fallible checks allowed. -/
structure PlanInit where
  name : String
  params : Array String
  stores : Array (Nat × Expr)
  deriving BEq, Inhabited, Repr

structure PlanEntry where
  /-- 1-based action index for `pf_last_action` instrumentation. -/
  actionIndex : Nat
  name : String
  params : Array String
  /-- Parallel to `params`: true when the parameter is opaque Principal. -/
  paramIsPrincipal : Array Bool
  resultKind : ResultKind
  checks : Array Check
  stores : Array (Nat × Expr)
  /-- Source-order pf.assets vault ops (Phase A5). -/
  assetOps : Array PfAssetsOp
  result? : Option Expr
  /-- True only when the callable terminator is an unconditional zero-payload
      declared revert. This makes non-Unit/no-result Plan states canonical. -/
  terminalRevert : Bool
  deriving BEq, Inhabited, Repr

structure PlanView where
  name : String
  params : Array String
  resultKind : ResultKind
  value : Expr
  deriving BEq, Inhabited, Repr

structure PlanInvariant where
  name : String
  checks : Array Check
  value : Expr
  deriving BEq, Inhabited, Repr

/-- Target-owned Quint Plan. Digests + artifact name only; no Semantic carrier. -/
structure Plan where
  programName : String
  sourceHash : String
  semanticHash : String
  /-- True iff every integer state/param/result is Int64. False is the
      historical all-UInt64 domain. Mixing UInt64/Int64 fails closed. -/
  signedNumeric : Bool
  states : Array PlanState
  initializer : Option PlanInit
  entries : Array PlanEntry
  views : Array PlanView
  invariants : Array PlanInvariant
  /-- True when any entry carries pf.assets vault ops (emits `pf_vault_native`). -/
  usesVaultNative : Bool
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Type closure (anonymous unique UInt64 / Bool / Unit only)
-- ---------------------------------------------------------------------------

private def quintTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Quint"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/Int64 widths are supported"
  unsupportedShapeDetail :=
    "only anonymous UInt64, Int64, Bool, Unit, Principal (pf.assets identity args only), Array UInt64 N state flatten, Option UInt64 2-leaf flatten, and Map UInt64 UInt64 cap-8 flatten are supported (narrow Int/Field/aggregates/Bytes fail closed)"

private def pilotUintWidthPolicyU64U32Index : PilotUintWidthPolicy where
  admittedWidths := #[64, 32]

private abbrev QuintTypeClosureV1 := PilotTypeClosureV1

private def validateQuintTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult QuintTypeClosureV1 :=
  validatePilotTypeClosure quintPlanErr quintTypeClosureWording types
    pilotUintWidthPolicyU64U32Index
    (intPolicy := pilotIntWidthPolicyI64)
    (fieldPolicy := pilotFieldPolicyNone)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayMap)

private def maxIdentifierBytes : Nat := 200
private def maxPureInlineDepth : Nat := 64
private def maxStateFields : Nat := 64
private def maxParams : Nat := 64
private def maxBodyOps : Nat := 4096
private def maxBodyChecks : Nat := 128
/-- Maximum fully expanded nodes in any target Plan expression. This is
    intentionally separate from the linear Semantic instruction budget. -/
private def maxExpandedExprNodes : Nat := 16384

private def checkedExprNodes (what : String) (nodes : Nat) : CompileResult Nat := do
  unless nodes ≤ maxExpandedExprNodes do
    planError s!"unsupported Quint semantic shape: {what} expanded expression exceeds {maxExpandedExprNodes} nodes"
  pure nodes

private def binaryExprNodes (what : String) (lhs rhs : TypedExpr) : CompileResult Nat :=
  checkedExprNodes what (1 + lhs.expandedNodes + rhs.expandedNodes)

/-- Div/mod lower to `if rhs != 0 then lhs op rhs else 0`; account for
    both denominator occurrences plus the four additional QExpr nodes. -/
private def guardedDivModExprNodes
    (what : String) (lhs rhs : TypedExpr) : CompileResult Nat :=
  checkedExprNodes what (5 + lhs.expandedNodes + 2 * rhs.expandedNodes)

private def unaryExprNodes (what : String) (operand : TypedExpr) : CompileResult Nat :=
  checkedExprNodes what (1 + operand.expandedNodes)

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

private def isUInt64Type (types : QuintTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  typeId == types.uint64TypeId

private def isInt64Type (types : QuintTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.int64TypeId == some typeId

/-- Program-wide numeric domain: signedNumeric ⇒ Int64, else UInt64. -/
private def matchesNumericDomain
    (types : QuintTypeClosureV1) (signedNumeric : Bool) (typeId : TypeIdV1) : Bool :=
  if signedNumeric then isInt64Type types typeId else isUInt64Type types typeId

private def isBoolType (types : QuintTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.boolTypeId == some typeId

private def isUnitType (types : QuintTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.unitTypeId == some typeId

private def isPrincipalType (types : QuintTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.principalTypeId == some typeId

private def isUInt32Type (types : QuintTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 32 == some typeId

/-- Dense Map UInt64 UInt64 pilot: cap-8 × (occ, key, val) = 24 UInt64 leaves. -/
private def mapPilotCapacityV1 : Nat := 8
private def mapSlotsPerEntryV1 : Nat := 3
private def mapPilotLeafCountV1 : Nat :=
  mapPilotCapacityV1 * mapSlotsPerEntryV1

private def isAggregateValue (v : TypedExpr) : Bool :=
  !v.leaves.isEmpty

private def isArrayValue (v : TypedExpr) : Bool :=
  isAggregateValue v && !v.isOption && !v.isMap

private def isOptionValue (v : TypedExpr) : Bool :=
  v.isOption && v.leaves.size == 2

private def isMapValue (v : TypedExpr) : Bool :=
  v.isMap && v.leaves.size == mapPilotLeafCountV1

private def mkArrayLeaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := false
    isMap := false }

private def mkOptionLeaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := true
    isMap := false }

private def mkMapLeaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := false
    isMap := true }

/-- True when `typeId` is an anonymous Option TypeDecl. Option is never
    pushed to `containerTypeIds`; state planning owns the 2-leaf layout. -/
private def isAnonymousOptionTypeIdV1
    (typeDecls : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match typeDecls[typeId.toNat]? with
  | some { shape := .option _, name := none, .. } => true
  | _ => false

private def isAnonymousMapTypeIdV1
    (typeDecls : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match typeDecls[typeId.toNat]? with
  | some { shape := .map _ _, name := none, .. } => true
  | _ => false

/-- Admit only anonymous `Map UInt64 UInt64` for the dense cap-8 pilot. -/
private def requireMapUInt64V1
    (typeDecls : Array TypeDeclV1) (types : QuintTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) : CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .map keyTid valTid, name := none, .. } =>
      unless matchesNumericDomain types signedNumeric keyTid &&
          matchesNumericDomain types signedNumeric valTid do
        planError
          "unsupported Quint semantic shape: Map state admits only Map UInt64 UInt64"
  | _ =>
      planError
        "unsupported Quint semantic shape: Map state admits only Map UInt64 UInt64"

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]`. -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == mapPilotLeafCountV1 do
    planError
      "unsupported Quint semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .litBool false
  let mut payload : Expr := .litU64 0
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Quint semantic shape: Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported Quint semantic shape: Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      planError "unsupported Quint semantic shape: Map lookup val leaf missing"
    let hit := .boolAnd (.compare .ne occ (.litU64 0)) (.compare .eq k key)
    found := .boolOr found hit
    payload := .ite hit v payload
  let tag := .ite found (.litU64 1) (.litU64 0)
  pure #[tag, payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert). -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == mapPilotLeafCountV1 do
    planError
      "unsupported Quint semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .litBool false
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Quint semantic shape: Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported Quint semantic shape: Map upsert key leaf missing"
    let hit := .boolAnd (.compare .ne occ (.litU64 0)) (.compare .eq k key)
    anyMatch := .boolOr anyMatch hit
  let mut seenEmpty : Expr := .litBool false
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Quint semantic shape: Map upsert empty-scan occ missing"
    let empty := .compare .eq occ (.litU64 0)
    let first := .boolAnd empty (.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := .boolOr seenEmpty empty
  let okInsert := .boolOr anyMatch seenEmpty
  let mut out : Array Expr := #[]
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Quint semantic shape: Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported Quint semantic shape: Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      planError "unsupported Quint semantic shape: Map upsert rebuild val missing"
    let matchHit :=
      .boolAnd (.compare .ne occ (.litU64 0)) (.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      planError "unsupported Quint semantic shape: Map upsert firstEmpty missing"
    let insertHere := .boolAnd firstE (.boolNot anyMatch)
    let write := .boolOr matchHit insertHere
    let occ' := .ite write (.litU64 1) occ
    let k' := .ite write key k
    let v' := .ite write value v
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

/-- Admit only anonymous `Option UInt64` (tag+payload). Non-UInt64 /
    nested / named Option stay fail closed. -/
private def requireOptionUInt64V1
    (typeDecls : Array TypeDeclV1) (types : QuintTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) : CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .option elTid, name := none, .. } =>
      unless matchesNumericDomain types signedNumeric elTid do
        planError
          "unsupported Quint semantic shape: Option element must be UInt64"
  | _ =>
      planError
        "unsupported Quint semantic shape: Option element must be UInt64"

/-- CosmWasm-style Array UInt64 N flatten: `some n` for admitted 1..8;
    `none` for scalars or Option (Option is not a containerTypeId).
    Nested/narrow/Map/Bytes/N=0/N>8 fail closed. -/
private def arrayUInt64LenV1
    (typeDecls : Array TypeDeclV1) (types : QuintTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless matchesNumericDomain types signedNumeric elTid do
        planError
          "unsupported Quint semantic shape: Array element must be UInt64 (nested/narrow/Int arrays fail closed; no native Quint List)"
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported Quint semantic shape: Array UInt64 N state must be 1..8 (got {n}; cap 8 flatten; no native Quint List)"
      pure (some n)
  | some { shape := .map _ _, .. } =>
      -- Map is handled by `requireMapUInt64V1` / `makeStateLayoutV1`, not here.
      planError
        "unsupported Quint semantic shape: Map UInt64 flatten is not an Array length"
  | _ =>
      planError
        "unsupported Quint semantic shape: container TypeId is not Array UInt64 (Bytes stay fail closed)"

/-- Physical PlanState leaves after Array/Option flatten. `leavesOf[logicalId]`
    is the dense field-index list (`name`, `name_0`..`name_{N-1}`, or
    `name_tag`/`name_p0`). `isOptionOf` is parallel to `leavesOf`. -/
private structure StateLayout where
  states : Array PlanState
  leavesOf : Array (Array Nat)
  isOptionOf : Array Bool
  isMapOf : Array Bool
  deriving Inhabited

private def physicalLeaves
    (layout : StateLayout) (sid : StateIdV1) : CompileResult (Array Nat) := do
  match layout.leavesOf[sid.toNat]? with
  | some phys =>
      unless !phys.isEmpty do
        planError "unsupported Quint semantic shape: state produced zero flatten leaves"
      pure phys
  | none =>
      planError "unsupported Quint semantic shape: stateLoad/store references unknown state"

private def makeStateLayoutV1
    (data : SemanticProgramDataV1) (types : QuintTypeClosureV1)
    (signedNumeric : Bool) : CompileResult StateLayout := do
  let mut states : Array PlanState := #[]
  let mut leavesOf : Array (Array Nat) := #[]
  let mut isOptionOf : Array Bool := #[]
  let mut isMapOf : Array Bool := #[]
  for st in data.logicalState do
    unless st.id.toNat == leavesOf.size do
      planError "unsupported Quint semantic shape: state ids must match declaration order"
    unless isIdentifier st.name do
      planError s!"state name '{st.name}' is not a safe identifier"
    if isAnonymousOptionTypeIdV1 data.types st.typeId then
      requireOptionUInt64V1 data.types types st.typeId signedNumeric
      if states.size + 2 > maxStateFields then
        planError "unsupported Quint semantic shape: state field count exceeds limit"
      let tagName := st.name ++ "_tag"
      let pName := st.name ++ "_p0"
      unless isIdentifier tagName do
        planError s!"state name '{tagName}' is not a safe identifier"
      unless isIdentifier pName do
        planError s!"state name '{pName}' is not a safe identifier"
      let tagFi := states.size
      states := states.push { name := tagName }
      let pFi := states.size
      states := states.push { name := pName }
      leavesOf := leavesOf.push #[tagFi, pFi]
      isOptionOf := isOptionOf.push true
      isMapOf := isMapOf.push false
    else if isAnonymousMapTypeIdV1 data.types st.typeId then
      requireMapUInt64V1 data.types types st.typeId signedNumeric
      if states.size + mapPilotLeafCountV1 > maxStateFields then
        planError "unsupported Quint semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for i in [0:mapPilotLeafCountV1] do
        let leafName := st.name ++ "_" ++ toString i
        unless isIdentifier leafName do
          planError s!"state name '{leafName}' is not a safe identifier"
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isMapOf := isMapOf.push true
    else
      match ← arrayUInt64LenV1 data.types types st.typeId signedNumeric with
      | some n =>
          if states.size + n > maxStateFields then
            planError "unsupported Quint semantic shape: state field count exceeds limit"
          let mut leaves : Array Nat := #[]
          for i in [0:n] do
            let leafName := st.name ++ "_" ++ toString i
            unless isIdentifier leafName do
              planError s!"state name '{leafName}' is not a safe identifier"
            leaves := leaves.push states.size
            states := states.push { name := leafName }
          leavesOf := leavesOf.push leaves
          isOptionOf := isOptionOf.push false
          isMapOf := isMapOf.push false
      | none =>
          requirePublicUInt64OrInt64State quintPlanErr types st
          if states.size + 1 > maxStateFields then
            planError "unsupported Quint semantic shape: state field count exceeds limit"
          let fi := states.size
          states := states.push { name := st.name }
          leavesOf := leavesOf.push #[fi]
          isOptionOf := isOptionOf.push false
          isMapOf := isMapOf.push false
  unless states.size ≤ maxStateFields do
    planError "unsupported Quint semantic shape: state field count exceeds limit"
  pure { states, leavesOf, isOptionOf, isMapOf }

/-- First-seen integer domain. Mixed UInt64/Int64 user-facing slots fail closed. -/
private def noteIntegerDomain
    (types : QuintTypeClosureV1) (typeId : TypeIdV1) (signed? : Option Bool)
    (owner : String) : CompileResult (Option Bool) := do
  if isInt64Type types typeId then
    match signed? with
    | some false =>
        planError
          s!"unsupported Quint semantic shape: {owner} mixes Int64 with UInt64 (Q0 numeric domain is homogeneous)"
    | _ => pure (some true)
  else if isUInt64Type types typeId then
    match signed? with
    | some true =>
        planError
          s!"unsupported Quint semantic shape: {owner} mixes UInt64 with Int64 (Q0 numeric domain is homogeneous)"
    | _ => pure (some false)
  else
    pure signed?

private def numericTyOf (signed : Bool) : ExprType :=
  if signed then .int64 else .uint64

private def maxU64Value : UInt64 := UInt64.ofNat 18446744073709551615
private def minI64Bits : UInt64 := UInt64.ofNat 9223372036854775808
private def maxI64Bits : UInt64 := UInt64.ofNat 9223372036854775807
private def negOneBits : UInt64 := UInt64.ofNat 18446744073709551615

private def qnJoined (qn : ProofForgeV2.Core.Common.QualifiedName) : String :=
  String.intercalate "." (ProofForgeV2.Core.Common.NonEmptyArray.toArray qn.components).toList

private def hasPfAssetsExtensionRow (data : SemanticProgramDataV1) : Bool :=
  data.requirements.items.any (·.id == wireExtensionPfAssetsIdV1)

private def isPfAssetsCatalogQn (qn : String) : Bool :=
  pfAssetsCatalogQualifiedNamesV1.contains qn

/-- ADR-0031 S5: Quint has no sha256 or keccak256 host. Any `pf.crypto.*` QN stays
    fail closed instead of the generic pf.assets catch-all. -/
private def isPfCryptoCalleeV1 (qn : String) : Bool :=
  qn.startsWith "pf.crypto."

/-- ADR-0031 S4: Quint has no unixTime/blockHeight/attachedValue/chainId host.
    Named UInt64 catalog keys stay fail closed with a key-named diagnostic.
    `context.caller` / `context.self` are Principal; Q0 results are only
    Unit/UInt64/Bool, so a Principal-result entry is rejected at
    `resultKindOf` first. A Principal-typed ContextRead still hits the
    generic outside-Q0 envelope below — Q0 admits Principal only as
    pf.assets identity args, not as a caller/self host. -/
private def isNamedUInt64ContextKey
    (key : ProofForgeV2.Core.Common.SchemaId) : Bool :=
  key == unixTimeSecondsContextKeyV1 ||
    key == blockHeightContextKeyV1 ||
    key == attachedValueContextKeyV1 ||
    key == chainIdContextKeyV1

-- ---------------------------------------------------------------------------
-- Lowering helpers
-- ---------------------------------------------------------------------------

private structure ValueEnv where
  entries : Array (ValueIdV1 × TypedExpr)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option TypedExpr :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (v : TypedExpr) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

/-- Typed expression overlay for StateStore → subsequent StateLoad
    (single-block). Each state id occurs at most once, so lookup and final-store
    projection are both unambiguously last-write-wins. -/
private structure StateOverlay where
  entries : Array (StateIdV1 × TypedExpr)
  deriving Inhabited

private def overlayLookup (ov : StateOverlay) (sid : StateIdV1) : Option TypedExpr :=
  ov.entries.findSome? (fun (id, e) => if id == sid then some e else none)

private def overlayInsert
    (ov : StateOverlay) (sid : StateIdV1) (e : TypedExpr) : StateOverlay :=
  let withoutOld := ov.entries.filter (fun item => item.1 != sid)
  { ov with entries := withoutOld.push (sid, e) }

/-- Emit final stores in ascending **physical** field-index order. Array
    and Option overlays expand to N UInt64 leaves; scalars stay one field. -/
private def overlayFinalStores
    (ov : StateOverlay) (layout : StateLayout) : Array (Nat × Expr) := Id.run do
  let mut last : Array (Option Expr) := #[]
  for (sid, e) in ov.entries do
    match layout.leavesOf[sid.toNat]? with
    | none => pure ()
    | some phys =>
        if e.leaves.isEmpty then
          match phys[0]? with
          | none => pure ()
          | some fi =>
              while last.size ≤ fi do
                last := last.push none
              last := last.set! fi (some e.expr)
        else
          for i in [0:e.leaves.size] do
            match phys[i]?, e.leaves[i]? with
            | some fi, some leaf =>
                while last.size ≤ fi do
                  last := last.push none
                last := last.set! fi (some leaf)
            | _, _ => pure ()
  let mut out : Array (Nat × Expr) := #[]
  for i in [0:last.size] do
    match last[i]? with
    | some (some e) => out := out.push (i, e)
    | _ => pure ()
  pure out

private structure BodyAccum where
  env : ValueEnv
  overlay : StateOverlay
  checks : Array Check
  assetOps : Array PfAssetsOp
  /-- Success-path symbolic vault after processed asset ops (starts as vaultNative). -/
  vaultExpr : Expr
  vaultExpandedNodes : Nat
  opCount : Nat
  /-- ADR-0030 E2: body referenced vaultNative via env-read (or will via asset ops). -/
  usesVaultNative : Bool := false
  deriving Inhabited

private def emptyBodyAccum (env : ValueEnv) (overlay : StateOverlay) : BodyAccum :=
  { env
    overlay
    checks := #[]
    assetOps := #[]
    vaultExpr := .vaultNative
    vaultExpandedNodes := 1
    opCount := 0
    usesVaultNative := false }

private def pushCheck (acc : BodyAccum) (ck : Check) : CompileResult BodyAccum := do
  if acc.checks.size + 1 > maxBodyChecks then
    planError s!"unsupported Quint semantic shape: body check count exceeds {maxBodyChecks}"
  pure { acc with checks := acc.checks.push ck }

private def bumpOp (acc : BodyAccum) : CompileResult BodyAccum := do
  if acc.opCount + 1 > maxBodyOps then
    planError "unsupported Quint semantic shape: body operation count exceeds limit"
  pure { acc with opCount := acc.opCount + 1 }

private def requireTy (v : TypedExpr) (ty : ExprType) (what : String) :
    CompileResult Expr := do
  if isAggregateValue v then
    planError s!"unsupported Quint semantic shape: {what} cannot be an Array/Option aggregate"
  unless v.ty == ty do
    planError s!"unsupported Quint semantic shape: {what} type mismatch"
  pure v.expr

private def literalIndexNatV1 (v : TypedExpr) : CompileResult Nat := do
  unless !isAggregateValue v && v.ty == .uint64 do
    planError
      "unsupported Quint semantic shape: Array index must be a UInt32/UInt64 literal"
  match v.expr with
  | .litU64 n => pure n.toNat
  | _ =>
      planError
        "unsupported Quint semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

/-- Lower void pf.assets ExternalCall into vault math + nondet outcome checks. -/
private def lowerPfAssetsExternalCall
    (acc0 : BodyAccum) (qn : String) (argIds : Array ValueIdV1)
    (forbidChecks : Bool) : CompileResult BodyAccum := do
  if forbidChecks then
    planError "unsupported Quint semantic shape: initializer cannot contain external calls"
  let mut acc := acc0
  let ordinal := acc.assetOps.size
  if qn == "pf.assets.native.deposit" then
    unless argIds.size == 1 do
      planError "unsupported Quint semantic shape: pf.assets.native.deposit requires one UInt64 arg"
    let some amountId := argIds[0]? |
      planError "unsupported Quint semantic shape: pf.assets.native.deposit arg missing"
    let av ← match envLookup acc.env amountId with
      | some v => pure v
      | none => planError "unsupported Quint semantic shape: deposit amount undefined"
    let amount ← requireTy av .uint64 "pf.assets.native.deposit amount"
    acc ← pushCheck acc
      { kind := .externalCallFailed, condition := .externalOk ordinal }
    let nodes ← checkedExprNodes "vault deposit"
      (1 + acc.vaultExpandedNodes + av.expandedNodes)
    let sum : Expr := .arith .add acc.vaultExpr amount
    let _ ← checkedExprNodes "vault deposit overflow check" (nodes + 2)
    let ovf : Expr := .compare .le sum (.litU64 maxU64Value)
    acc ← pushCheck acc { kind := .vaultOverflow, condition := ovf }
    pure { acc with
      assetOps := acc.assetOps.push { kind := .nativeDeposit, amount }
      vaultExpr := sum
      vaultExpandedNodes := nodes }
  else if qn == "pf.assets.native.transfer" then
    unless argIds.size == 2 do
      planError
        "unsupported Quint semantic shape: pf.assets.native.transfer requires Principal + UInt64 args"
    let some dstId := argIds[0]? |
      planError "unsupported Quint semantic shape: transfer dst missing"
    let some amountId := argIds[1]? |
      planError "unsupported Quint semantic shape: transfer amount missing"
    let dv ← match envLookup acc.env dstId with
      | some v => pure v
      | none => planError "unsupported Quint semantic shape: transfer dst undefined"
    unless dv.ty == .principal do
      planError "unsupported Quint semantic shape: pf.assets.native.transfer dst must be Principal"
    let av ← match envLookup acc.env amountId with
      | some v => pure v
      | none => planError "unsupported Quint semantic shape: transfer amount undefined"
    let amount ← requireTy av .uint64 "pf.assets.native.transfer amount"
    acc ← pushCheck acc
      { kind := .externalCallFailed, condition := .externalOk ordinal }
    -- Q0: insufficient vault is an explicit failure outcome (stutter), not a
    -- blocked action. External nondet failure is ordered before this check.
    let bal : Expr := .compare .ge acc.vaultExpr amount
    acc ← pushCheck acc { kind := .vaultUnderflow, condition := bal }
    let nodes ← checkedExprNodes "vault transfer"
      (1 + acc.vaultExpandedNodes + av.expandedNodes)
    let diff : Expr := .arith .sub acc.vaultExpr amount
    pure { acc with
      assetOps := acc.assetOps.push { kind := .nativeTransfer, amount }
      vaultExpr := diff
      vaultExpandedNodes := nodes }
  else if isPfAssetsCatalogQn qn then
    planError
      s!"unsupported Quint semantic shape: pf.assets QN '{qn}' is outside Phase A Quint vault model (async/token fail closed)"
  else
    planError
      "unsupported Quint semantic shape: externalCall callee is not a Quint-admitted pf.assets QN"

private def lowerLiteral
    (types : QuintTypeClosureV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult TypedExpr := do
  if isInt64Type types typeId then
    let v ← decodeInt64LiteralLe quintPlanErr "Quint" valueBytes
    pure { ty := .int64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt64Type types typeId then
    let v ← decodeUInt64LiteralLe quintPlanErr "Quint" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt32Type types typeId then
    let v ← decodeUInt32LiteralLe quintPlanErr "Quint" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isBoolType types typeId then
    let b ← decodeBoolLiteralBit quintPlanErr "Quint" valueBytes
    pure { ty := .bool, expr := .litBool b, expandedNodes := 1 }
  else
    planError "unsupported Quint semantic shape: literal type is outside UInt64/Int64/UInt32/Bool"

private def signedRangeCond (e : Expr) : Expr :=
  .boolAnd
    (.compare .ge e (.litU64 minI64Bits))
    (.compare .le e (.litU64 maxI64Bits))

private def lowerBinary
    (op : BinaryOpV1) (lhs rhs : TypedExpr) :
    CompileResult (TypedExpr × Array Check) := do
  match op with
  | .add => do
      if lhs.ty == .int64 && rhs.ty == .int64 then
        let nodes ← binaryExprNodes "add" lhs rhs
        let e : Expr := .arith .add lhs.expr rhs.expr
        let _ ← checkedExprNodes "signed add overflow check" (nodes + 5)
        pure ({ ty := .int64, expr := e, expandedNodes := nodes },
          #[{ kind := .overflow, condition := signedRangeCond e }])
      else
        let l ← requireTy lhs .uint64 "add lhs"
        let r ← requireTy rhs .uint64 "add rhs"
        let nodes ← binaryExprNodes "add" lhs rhs
        let e : Expr := .arith .add l r
        -- success when lhs + rhs ≤ 2^64−1 (unbounded int at emission)
        let _ ← checkedExprNodes "add overflow check" (nodes + 2)
        let cond : Expr := .compare .le e (.litU64 maxU64Value)
        pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
          #[{ kind := .overflow, condition := cond }])
  | .sub => do
      if lhs.ty == .int64 && rhs.ty == .int64 then
        let nodes ← binaryExprNodes "sub" lhs rhs
        let e : Expr := .arith .sub lhs.expr rhs.expr
        let _ ← checkedExprNodes "signed sub overflow check" (nodes + 5)
        pure ({ ty := .int64, expr := e, expandedNodes := nodes },
          #[{ kind := .overflow, condition := signedRangeCond e }])
      else
        let l ← requireTy lhs .uint64 "sub lhs"
        let r ← requireTy rhs .uint64 "sub rhs"
        let nodes ← binaryExprNodes "sub" lhs rhs
        let e : Expr := .arith .sub l r
        let cond : Expr := .compare .ge l r
        pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
          #[{ kind := .underflow, condition := cond }])
  | .mul => do
      if lhs.ty == .int64 && rhs.ty == .int64 then
        let nodes ← binaryExprNodes "mul" lhs rhs
        let e : Expr := .arith .mul lhs.expr rhs.expr
        let _ ← checkedExprNodes "signed mul overflow check" (nodes + 5)
        pure ({ ty := .int64, expr := e, expandedNodes := nodes },
          #[{ kind := .overflow, condition := signedRangeCond e }])
      else
        let l ← requireTy lhs .uint64 "mul lhs"
        let r ← requireTy rhs .uint64 "mul rhs"
        let nodes ← binaryExprNodes "mul" lhs rhs
        let e : Expr := .arith .mul l r
        let _ ← checkedExprNodes "mul overflow check" (nodes + 2)
        let cond : Expr := .compare .le e (.litU64 maxU64Value)
        pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
          #[{ kind := .overflow, condition := cond }])
  | .div => do
      if lhs.ty == .int64 && rhs.ty == .int64 then
        let nodes ← guardedDivModExprNodes "div" lhs rhs
        let e : Expr := .arith .div lhs.expr rhs.expr
        let nz : Expr := .compare .ne rhs.expr (.litU64 0)
        let notMinDiv : Expr :=
          .boolOr
            (.compare .ne lhs.expr (.litU64 minI64Bits))
            (.compare .ne rhs.expr (.litU64 negOneBits))
        let cond : Expr := .boolAnd nz notMinDiv
        let _ ← checkedExprNodes "signed div check" (nodes + 8)
        pure ({ ty := .int64, expr := e, expandedNodes := nodes },
          #[{ kind := .divByZero, condition := cond }])
      else
        let l ← requireTy lhs .uint64 "div lhs"
        let r ← requireTy rhs .uint64 "div rhs"
        let nodes ← guardedDivModExprNodes "div" lhs rhs
        let _ ← checkedExprNodes "div zero check" (rhs.expandedNodes + 2)
        let e : Expr := .arith .div l r
        let cond : Expr := .compare .ne r (.litU64 0)
        pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
          #[{ kind := .divByZero, condition := cond }])
  | .mod => do
      if lhs.ty == .int64 && rhs.ty == .int64 then
        let nodes ← guardedDivModExprNodes "mod" lhs rhs
        let _ ← checkedExprNodes "signed mod zero check" (rhs.expandedNodes + 2)
        let e : Expr := .arith .mod lhs.expr rhs.expr
        let cond : Expr := .compare .ne rhs.expr (.litU64 0)
        pure ({ ty := .int64, expr := e, expandedNodes := nodes },
          #[{ kind := .divByZero, condition := cond }])
      else
        let l ← requireTy lhs .uint64 "mod lhs"
        let r ← requireTy rhs .uint64 "mod rhs"
        let nodes ← guardedDivModExprNodes "mod" lhs rhs
        let _ ← checkedExprNodes "mod zero check" (rhs.expandedNodes + 2)
        let e : Expr := .arith .mod l r
        let cond : Expr := .compare .ne r (.litU64 0)
        pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
          #[{ kind := .divByZero, condition := cond }])
  | .eq | .ne | .lt | .le | .gt | .ge => do
      unless lhs.ty == rhs.ty do
        planError "unsupported Quint semantic shape: comparison operands must share a type"
      unless lhs.ty == .uint64 || lhs.ty == .int64 || lhs.ty == .bool do
        planError "unsupported Quint semantic shape: comparison operands must be UInt64, Int64, or Bool"
      if lhs.ty == .bool && !(op == .eq || op == .ne) then
        planError "unsupported Quint semantic shape: Bool comparison only supports eq/ne"
      let cop : ComparisonOp :=
        match op with
        | .eq => .eq | .ne => .ne | .lt => .lt | .le => .le | .gt => .gt | .ge => .ge
        | _ => .eq
      let nodes ← binaryExprNodes "comparison" lhs rhs
      pure ({ ty := .bool, expr := .compare cop lhs.expr rhs.expr, expandedNodes := nodes }, #[])
  | .and => do
      let l ← requireTy lhs .bool "and lhs"
      let r ← requireTy rhs .bool "and rhs"
      let nodes ← binaryExprNodes "bool and" lhs rhs
      pure ({ ty := .bool, expr := .boolAnd l r, expandedNodes := nodes }, #[])
  | .or => do
      let l ← requireTy lhs .bool "or lhs"
      let r ← requireTy rhs .bool "or rhs"
      let nodes ← binaryExprNodes "bool or" lhs rhs
      pure ({ ty := .bool, expr := .boolOr l r, expandedNodes := nodes }, #[])
  | .bitAnd | .bitOr | .bitXor | .shl | .shr =>
      planError "unsupported Quint semantic shape: bitwise/shift ops are outside Q0"

private def lowerUnary (op : UnaryOpV1) (operand : TypedExpr) :
    CompileResult TypedExpr := do
  match op with
  | .not => do
      let o ← requireTy operand .bool "bool not"
      let nodes ← unaryExprNodes "bool not" operand
      pure { ty := .bool, expr := .boolNot o, expandedNodes := nodes }
  | .neg | .bitNot =>
      planError "unsupported Quint semantic shape: unary neg/bitNot are outside Q0"

private structure CallableIndex where
  pureFns : Array (CallableIdV1 × CallableV1)
  /-- Exact `extension.pf-assets` row present in retained requirements. -/
  pfAssetsDeclared : Bool
  deriving Inhabited

private def lookupPureFn (idx : CallableIndex) (id : CallableIdV1) :
    Option CallableV1 :=
  idx.pureFns.findSome? (fun (cid, c) => if cid == id then some c else none)

private def resultKindOf
    (typeDecls : Array TypeDeclV1) (types : QuintTypeClosureV1)
    (typeId : TypeIdV1) (owner : String) :
    CompileResult ResultKind := do
  if isUnitType types typeId then pure .unit
  else if isInt64Type types typeId then pure .int64
  else if isUInt64Type types typeId then pure .uint64
  else if isBoolType types typeId then pure .bool
  else if isAnonymousOptionTypeIdV1 typeDecls typeId then
    planError s!"{owner} Option return is outside Q0"
  else if types.isContainer typeId then
    planError
      s!"{owner} Array/Map return is outside Q0 (only Array/Map UInt64 state flattens; no native Quint List/Map)"
  else planError s!"{owner} result must be public Unit, UInt64, Int64, or Bool"

/-- Single-block instruction walk with optional pureFn inline. -/
private partial def lowerInstructions
    (data : SemanticProgramDataV1) (types : QuintTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1)
    (numericTy : ExprType) (layout : StateLayout)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (acc0 : BodyAccum) :
    CompileResult (BodyAccum × Option TypedExpr × Bool) := do
  -- Returns (acc, returnValue?, endedInRevert)
  unless callable.blocks.size == 1 do
    planError "unsupported Quint semantic shape: each callable must have exactly one block"
  unless callable.loopBounds.isEmpty do
    planError "unsupported Quint semantic shape: loopBounds are outside Q0"
  unless callable.entryBlock.toNat == 0 do
    planError "unsupported Quint semantic shape: entryBlock must be 0"
  let some block := callable.blocks[0]? |
    planError "unsupported Quint semantic shape: missing entry block"
  unless block.params.isEmpty do
    planError "unsupported Quint semantic shape: block parameters are outside Q0"
  let mut acc := acc0
  for instr in block.instructions do
    acc ← bumpOp acc
    match instr.op with
    | .literal typeId valueBytes => do
        let v ← lowerLiteral types typeId valueBytes
        match instr.result with
        | none => planError "unsupported Quint semantic shape: literal must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId v }
    | .stateLoad stateId => do
        unless allowStateRead do
          planError "unsupported Quint semantic shape: pureFn cannot read state"
        match instr.result with
        | none => planError "unsupported Quint semantic shape: stateLoad must produce a value"
        | some vd =>
            unless stateId.toNat < data.logicalState.size do
              planError "unsupported Quint semantic shape: stateLoad references unknown state"
            let phys ← physicalLeaves layout stateId
            let isOpt :=
              match layout.isOptionOf[stateId.toNat]? with
              | some b => b
              | none => false
            let isMp :=
              match layout.isMapOf[stateId.toNat]? with
              | some b => b
              | none => false
            let value : TypedExpr :=
              match overlayLookup acc.overlay stateId with
              | some ov => ov
              | none =>
                  if phys.size == 1 then
                    { ty := numericTy
                      expr := .stateLoad phys[0]!
                      expandedNodes := 1 }
                  else if isOpt then
                    mkOptionLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
                  else if isMp then
                    mkMapLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
                  else
                    mkArrayLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
            acc := { acc with env := envInsert acc.env vd.valueId value }
    | .stateStore stateId value => do
        unless allowStateWrite do
          planError "unsupported Quint semantic shape: StateStore is only legal in init/entry"
        let v ← match envLookup acc.env value with
          | some tv => pure tv
          | none => planError "unsupported Quint semantic shape: stateStore value undefined"
        unless stateId.toNat < data.logicalState.size do
          planError "unsupported Quint semantic shape: stateStore references unknown state"
        let phys ← physicalLeaves layout stateId
        if isAggregateValue v then
          unless v.leaves.size == phys.size do
            planError "unsupported Quint semantic shape: stateStore leaf count mismatch"
        else
          unless phys.size == 1 do
            planError "unsupported Quint semantic shape: stateStore scalar into Array/Option state"
          let _ ← requireTy v numericTy "stateStore value"
        acc := { acc with overlay := overlayInsert acc.overlay stateId v }
    | .binary op lhs rhs => do
        let lv ← match envLookup acc.env lhs with
          | some v => pure v
          | none => planError "unsupported Quint semantic shape: binary lhs undefined"
        let rv ← match envLookup acc.env rhs with
          | some v => pure v
          | none => planError "unsupported Quint semantic shape: binary rhs undefined"
        let (tv, cks) ← lowerBinary op lv rv
        if forbidChecks && !cks.isEmpty then
          planError "unsupported Quint semantic shape: initializer cannot contain fallible checks"
        for ck in cks do
          acc ← pushCheck acc ck
        match instr.result with
        | none => planError "unsupported Quint semantic shape: binary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .unary op operand => do
        let ov ← match envLookup acc.env operand with
          | some v => pure v
          | none => planError "unsupported Quint semantic shape: unary operand undefined"
        let tv ← lowerUnary op ov
        match instr.result with
        | none => planError "unsupported Quint semantic shape: unary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .pureCall calleeId args => do
        if inlineDepth >= maxPureInlineDepth then
          planError "unsupported Quint semantic shape: pureFn inline depth exceeds 64"
        let callee ← match lookupPureFn idx calleeId with
          | some c => pure c
          | none =>
              planError "unsupported Quint semantic shape: pureCall callee is not a pureFn"
        unless callee.params.size == args.size do
          planError "unsupported Quint semantic shape: pureCall arity mismatch"
        -- Build callee env from arg expressions (already lowered in caller).
        let mut cEnv : ValueEnv := { entries := #[] }
        for i in [0:args.size] do
          let some argId := args[i]? |
            planError "unsupported Quint semantic shape: pureCall arg missing"
          let some p := callee.params[i]? |
            planError "unsupported Quint semantic shape: pureCall param missing"
          let av ← match envLookup acc.env argId with
            | some v => pure v
            | none => planError "unsupported Quint semantic shape: pureCall arg undefined"
          unless (isUInt64Type types p.typeId && av.ty == .uint64) ||
              (isInt64Type types p.typeId && av.ty == .int64) do
            planError "unsupported Quint semantic shape: pureFn params must be public UInt64 or Int64"
          cEnv := envInsert cEnv p.valueId av
        let cAcc0 : BodyAccum := emptyBodyAccum cEnv { entries := #[] }
        let (cAcc, ret?, _endedRevert) ←
          lowerInstructions data types idx callee numericTy layout
            (allowStateRead := false) (allowStateWrite := false)
            (forbidChecks := forbidChecks) (inlineDepth := inlineDepth + 1) cAcc0
        -- Bound the fully expanded inline tree, not only each callable body.
        let expandedOpCount := acc.opCount + cAcc.opCount
        if expandedOpCount > maxBodyOps then
          planError "unsupported Quint semantic shape: expanded pureFn operation count exceeds limit"
        acc := { acc with opCount := expandedOpCount }
        -- `lowerInstructions` already records the callee's terminal revert in
        -- `cAcc.checks`; demote that root marker to a propagated call failure
        -- and do not duplicate it at the call site.
        for ck in cAcc.checks do
          if forbidChecks then
            planError "unsupported Quint semantic shape: initializer cannot contain fallible checks"
          let propagated :=
            match ck.kind with
            | .terminalRevert errorIndex =>
                { ck with kind := .declaredRevert errorIndex }
            | _ => ck
          acc ← pushCheck acc propagated
        match instr.result with
        | none => planError "unsupported Quint semantic shape: pureCall must produce a value"
        | some vd =>
            match ret? with
            | some tv => acc := { acc with env := envInsert acc.env vd.valueId tv }
            | none =>
                if isUnitType types vd.typeId then
                  -- Unit has no Quint expression representation in Q0. The SSA
                  -- result may be unused; any later value use fails closed via
                  -- the ordinary undefined-value lookup.
                  pure ()
                else
                  planError "unsupported Quint semantic shape: pureCall missing return value"
    | .assert_ condition errorId args => do
        unless errorId.isNone && args.isEmpty do
          planError "unsupported Quint semantic shape: assert requires errorId=none and empty args"
        let c ← match envLookup acc.env condition with
          | some v => requireTy v .bool "assert condition"
          | none => planError "unsupported Quint semantic shape: assert condition undefined"
        if forbidChecks then
          planError "unsupported Quint semantic shape: initializer cannot contain fallible checks"
        acc ← pushCheck acc { kind := .assertion, condition := c }
    | .externalCall _calleeId callee argIds => do
        -- Void-only; result-bearing externalCall stays fail closed.
        -- SYS-S5: pf.crypto.* is a dedicated honesty class even when the
        -- call is result-bearing (before the generic Q0 catch-all).
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          planError
            s!"unsupported Quint semantic shape: pf.crypto QN '{qn}' has no Quint host binding (sha256/keccak256 and siblings stay fail closed)"
        match instr.result with
        | some _ =>
            planError "unsupported Quint semantic shape: result-bearing externalCall is outside Q0"
        | none => pure ()
        unless allowStateWrite do
          planError
            "unsupported Quint semantic shape: externalCall is only legal in entry (not pureFn/view/invariant)"
        if isPfAssetsCatalogQn qn then
          unless idx.pfAssetsDeclared do
            planError
              "unsupported Quint semantic shape: pf.assets catalog call requires extension.pf-assets declaration"
          acc ← lowerPfAssetsExternalCall acc qn argIds forbidChecks
        else
          planError
            "unsupported Quint semantic shape: externalCall callee is not a Quint-admitted pf.assets QN"
    | .envRead key args => do
        -- ADR-0030 E2-Quint: read-only self-vault observation.
        -- Native → target-owned `vaultNative` (same Int model as deposit/transfer).
        -- Token → permanently fail closed: mint-keyed Map + Principal identity
        -- are outside Q0 Int vault (honesty boundary, not debt).
        let some result := instr.result |
          planError "unsupported Quint semantic shape: envRead must produce a value"
        unless idx.pfAssetsDeclared do
          planError
            "unsupported Quint semantic shape: pf.assets env-read requires extension.pf-assets declaration"
        unless allowStateRead do
          planError
            "unsupported Quint semantic shape: pureFn cannot use envRead (host/model vault read is not pure)"
        match key with
        | .nativeVaultBalanceU128 =>
            throw <| .planInvariant .quint
              "unsupported Quint semantic shape: nativeVaultBalanceU128 is not admitted"
        | .nativeVaultBalance =>
            unless isUInt64Type types result.typeId do
              planError "unsupported Quint semantic shape: envRead result must be UInt64"
            unless args.isEmpty do
              planError
                "unsupported Quint semantic shape: nativeVaultBalance takes no arguments"
            let tv : TypedExpr := {
              ty := .uint64
              expr := .vaultNative
              expandedNodes := 1
            }
            acc := { acc with
              env := envInsert acc.env result.valueId tv
              usesVaultNative := true
            }
        | .tokenVaultBalance =>
            planError
              "unsupported Quint semantic shape: pf.assets.token.balanceOfSelf permanently fail closed (mint-keyed token vault Map + Principal identity are outside Q0 Int vault model)"
    | .contextRead key =>
        if isNamedUInt64ContextKey key then
          planError
            s!"unsupported Quint semantic shape: ContextRead '{key.value}' has no Quint host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
        -- caller/self remain on this generic envelope (no caller/self host).
        planError "unsupported Quint semantic shape: op is outside Q0"
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported Quint semantic shape: construct must produce a value"
        | some vd =>
            if isAnonymousMapTypeIdV1 data.types typeId then
              requireMapUInt64V1 data.types types typeId (numericTy == .int64)
              unless ctorIdx == 0 do
                planError
                  "unsupported Quint semantic shape: Map construct ctorIdx must be 0"
              unless argIds.isEmpty do
                planError
                  "unsupported Quint semantic shape: nonempty Map construct is outside Q0 (build maps via IndexSet upsert)"
              let zeros := Array.replicate mapPilotLeafCountV1 (.litU64 0)
              acc := { acc with
                env := envInsert acc.env vd.valueId
                  (mkMapLeaves zeros mapPilotLeafCountV1) }
            else if isAnonymousOptionTypeIdV1 data.types typeId then
              requireOptionUInt64V1 data.types types typeId (numericTy == .int64)
              match ctorIdx.toNat with
              | 0 =>
                  unless argIds.isEmpty do
                    planError
                      "unsupported Quint semantic shape: Option.none construct takes no args"
                  acc := { acc with
                    env := envInsert acc.env vd.valueId
                      (mkOptionLeaves #[.litU64 0, .litU64 0] 2) }
              | 1 =>
                  unless argIds.size == 1 do
                    planError
                      "unsupported Quint semantic shape: Option.some construct takes one arg"
                  let some argId := argIds[0]? |
                    planError "unsupported Quint semantic shape: Option.some construct arg missing"
                  let av ← match envLookup acc.env argId with
                    | some v => pure v
                    | none => planError "unsupported Quint semantic shape: construct arg undefined"
                  unless !isAggregateValue av && av.ty == numericTy do
                    planError
                      "unsupported Quint semantic shape: Option.some arg must be scalar UInt64"
                  acc := { acc with
                    env := envInsert acc.env vd.valueId
                      (mkOptionLeaves #[.litU64 1, av.expr] (av.expandedNodes + 2)) }
              | _ =>
                  planError
                    "unsupported Quint semantic shape: Option construct ctorIdx must be 0 (none) or 1 (some)"
            else
              let n ← match ← arrayUInt64LenV1 data.types types typeId (numericTy == .int64) with
                | some n => pure n
                | none =>
                    planError
                      "unsupported Quint semantic shape: construct admits only Array UInt64 N, Option UInt64, or Map UInt64 UInt64 on Quint"
              unless ctorIdx == 0 do
                planError "unsupported Quint semantic shape: Array construct ctorIdx must be 0"
              unless argIds.size == n do
                planError "unsupported Quint semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              let mut nodes : Nat := 0
              for argId in argIds do
                let av ← match envLookup acc.env argId with
                  | some v => pure v
                  | none => planError "unsupported Quint semantic shape: construct arg undefined"
                unless !isAggregateValue av && av.ty == numericTy do
                  planError
                    "unsupported Quint semantic shape: Array construct args must be scalar UInt64"
                leafExprs := leafExprs.push av.expr
                nodes := nodes + av.expandedNodes
              acc := { acc with
                env := envInsert acc.env vd.valueId (mkArrayLeaves leafExprs (nodes + n)) }
    | .indexGet base index => do
        match instr.result with
        | none => planError "unsupported Quint semantic shape: IndexGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported Quint semantic shape: IndexGet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported Quint semantic shape: IndexGet index undefined"
            if isMapValue bv then
              unless !isAggregateValue iv && iv.ty == numericTy do
                planError
                  "unsupported Quint semantic shape: Map IndexGet key must be scalar UInt64"
              let optLeaves ← mapLookupOptionLeavesV1 bv.leaves iv.expr
              let ov := mkOptionLeaves optLeaves
                (bv.expandedNodes + iv.expandedNodes + 8)
              acc := { acc with env := envInsert acc.env vd.valueId ov }
            else do
              unless isArrayValue bv do
                planError
                  "unsupported Quint semantic shape: IndexGet base must be an Array UInt64 or Map UInt64 aggregate"
              let i ← literalIndexNatV1 iv
              unless i < bv.leaves.size do
                planError "unsupported Quint semantic shape: Array IndexGet index out of range"
              let some leaf := bv.leaves[i]? |
                planError "unsupported Quint semantic shape: Array IndexGet leaf missing"
              acc := { acc with env := envInsert acc.env vd.valueId {
                ty := numericTy
                expr := leaf
                expandedNodes := 1
              } }
    | .indexSet base index value => do
        match instr.result with
        | none => planError "unsupported Quint semantic shape: IndexSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported Quint semantic shape: IndexSet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported Quint semantic shape: IndexSet index undefined"
            let vv ← match envLookup acc.env value with
              | some v => pure v
              | none => planError "unsupported Quint semantic shape: IndexSet value undefined"
            if isMapValue bv then
              unless !isAggregateValue iv && iv.ty == numericTy do
                planError
                  "unsupported Quint semantic shape: Map IndexSet key must be scalar UInt64"
              unless !isAggregateValue vv && vv.ty == numericTy do
                planError
                  "unsupported Quint semantic shape: Map IndexSet value must be scalar UInt64"
              if forbidChecks then
                planError
                  "unsupported Quint semantic shape: initializer cannot contain fallible Map upsert"
              let (newLeaves, okInsert) ←
                mapUpsertLeavesV1 bv.leaves iv.expr vv.expr
              acc ← pushCheck acc { kind := .overflow, condition := okInsert }
              let tv := mkMapLeaves newLeaves
                (1 + bv.expandedNodes + iv.expandedNodes + vv.expandedNodes)
              acc := { acc with env := envInsert acc.env vd.valueId tv }
            else do
              unless isArrayValue bv do
                planError
                  "unsupported Quint semantic shape: IndexSet base must be an Array UInt64 or Map UInt64 aggregate"
              let i ← literalIndexNatV1 iv
              unless i < bv.leaves.size do
                planError "unsupported Quint semantic shape: Array IndexSet index out of range"
              unless !isAggregateValue vv && vv.ty == numericTy do
                planError
                  "unsupported Quint semantic shape: Array IndexSet value must be scalar UInt64"
              let newLeaves := bv.leaves.set! i vv.expr
              let tv := mkArrayLeaves newLeaves (1 + bv.expandedNodes + vv.expandedNodes)
              acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .variantTag baseId => do
        match instr.result with
        | none => planError "unsupported Quint semantic shape: variantTag must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported Quint semantic shape: variantTag base undefined"
            unless isOptionValue bv do
              planError
                "unsupported Quint semantic shape: variantTag base must be Option UInt64"
            let some tag := bv.leaves[0]? |
              planError "unsupported Quint semantic shape: variantTag Option tag leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := .uint64
              expr := tag
              expandedNodes := 1
            } }
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none =>
            planError "unsupported Quint semantic shape: variantPayload must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none =>
                  planError "unsupported Quint semantic shape: variantPayload base undefined"
            unless isOptionValue bv do
              planError
                "unsupported Quint semantic shape: variantPayload base must be Option UInt64"
            if variantIndex.toNat == 0 then
              planError
                "unsupported Quint semantic shape: variantPayload of Option.none is empty"
            unless variantIndex.toNat == 1 && payloadIndex.toNat == 0 do
              planError
                "unsupported Quint semantic shape: variantPayload Option some requires (variant 1, payload 0)"
            let some payload := bv.leaves[1]? |
              planError
                "unsupported Quint semantic shape: variantPayload Option payload leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := numericTy
              expr := payload
              expandedNodes := 1
            } }
    | .constant .. | .fieldGet .. | .fieldSet ..
    | .checkedCast .. | .commit ..
    | .emit .. | .schedule .. =>
        planError "unsupported Quint semantic shape: op is outside Q0"
  -- Terminator
  match block.terminator with
  | .return_ value => do
      match value with
      | none => pure (acc, none, false)
      | some vid =>
          match envLookup acc.env vid with
          | some tv => pure (acc, some tv, false)
          | none => planError "unsupported Quint semantic shape: return value undefined"
  | .revert errorId args => do
      unless args.isEmpty do
        planError "unsupported Quint semantic shape: revert requires zero-payload args"
      if forbidChecks then
        planError "unsupported Quint semantic shape: initializer cannot contain fallible checks"
      acc ← pushCheck acc
        { kind := .terminalRevert errorId.toNat, condition := .litBool false }
      pure (acc, none, true)
  | .jump .. | .branch .. | .switch .. | .trap .. =>
      planError "unsupported Quint semantic shape: multi-block/trap terminators are outside Q0"

private def seedParamEnv
    (typeDecls : Array TypeDeclV1) (types : QuintTypeClosureV1)
    (callable : CallableV1) (owner : String) :
    CompileResult (ValueEnv × Array String × Array Bool) := do
  let mut env : ValueEnv := { entries := #[] }
  let mut names : Array String := #[]
  let mut isPrincipal : Array Bool := #[]
  let mut i : Nat := 0
  for p in callable.params do
    unless p.visibility == .public_ do
      planError "unsupported Quint semantic shape: parameters must be public"
    unless isIdentifier p.name do
      planError s!"parameter '{p.name}' is not a safe identifier"
    if isAnonymousOptionTypeIdV1 typeDecls p.typeId then
      planError s!"{owner} Option params are outside Q0"
    if types.isContainer p.typeId then
      planError
        "unsupported Quint semantic shape: Array params are outside Q0 (only Array UInt64 N state flattens; no native Quint List)"
    if isInt64Type types p.typeId then
      env := envInsert env p.valueId {
        ty := .int64
        expr := .param i
        expandedNodes := 1
      }
      isPrincipal := isPrincipal.push false
    else if isUInt64Type types p.typeId then
      env := envInsert env p.valueId {
        ty := .uint64
        expr := .param i
        expandedNodes := 1
      }
      isPrincipal := isPrincipal.push false
    else if isPrincipalType types p.typeId then
      env := envInsert env p.valueId {
        ty := .principal
        expr := .param i
        expandedNodes := 1
      }
      isPrincipal := isPrincipal.push true
    else
      planError
        "unsupported Quint semantic shape: parameters must be public UInt64, Int64, or Principal"
    names := names.push p.name
    i := i + 1
  unless names.size ≤ maxParams do
    planError "unsupported Quint semantic shape: parameter count exceeds limit"
  pure (env, names, isPrincipal)

private def lowerCallableBody
    (data : SemanticProgramDataV1) (types : QuintTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1) (numericTy : ExprType)
    (layout : StateLayout)
    (allowStateRead allowStateWrite forbidChecks initialStateDefaults : Bool) :
    CompileResult
      (Array String × Array Bool × Array Check × Array (Nat × Expr) ×
        Array PfAssetsOp × Option TypedExpr × Bool × Bool) := do
  let owner :=
    match callable.kind, callable.name with
    | .entry, some n => s!"entry '{n}'"
    | .view, some n => s!"view '{n}'"
    | .pureFn, some n => s!"pureFn '{n}'"
    | .initializer, _ => "initializer"
    | .invariant, some n => s!"invariant '{n}'"
    | _, _ => "callable"
  let (env0, paramNames, paramIsPrincipal) ←
    seedParamEnv data.types types callable owner
  -- Reference initialization starts from canonical numeric zero. Seed the
  -- initializer overlay accordingly so an init StateLoad never refers to
  -- an unconstrained pre-state variable in the Quint initial action.
  let mut overlay0 : StateOverlay := { entries := #[] }
  if initialStateDefaults then
    for st in data.logicalState do
      let phys ← physicalLeaves layout st.id
      let isOpt :=
        match layout.isOptionOf[st.id.toNat]? with
        | some b => b
        | none => false
      let isMp :=
        match layout.isMapOf[st.id.toNat]? with
        | some b => b
        | none => false
      if phys.size == 1 then
        overlay0 := overlayInsert overlay0 st.id {
          ty := numericTy
          expr := .litU64 0
          expandedNodes := 1
        }
      else
        let zeros := phys.map (fun _ => Expr.litU64 0)
        if isOpt then
          overlay0 := overlayInsert overlay0 st.id (mkOptionLeaves zeros phys.size)
        else if isMp then
          overlay0 := overlayInsert overlay0 st.id (mkMapLeaves zeros phys.size)
        else
          overlay0 := overlayInsert overlay0 st.id (mkArrayLeaves zeros phys.size)
  let acc0 : BodyAccum := emptyBodyAccum env0 overlay0
  let (acc, ret?, endedRevert) ←
    lowerInstructions data types idx callable numericTy layout
      allowStateRead allowStateWrite forbidChecks 0 acc0
  let stores := overlayFinalStores acc.overlay layout
  -- Asset ops always touch the vault; env-read sets the flag explicitly.
  let usesVault := acc.usesVaultNative || !acc.assetOps.isEmpty
  pure (paramNames, paramIsPrincipal, acc.checks, stores, acc.assetOps, ret?,
    endedRevert, usesVault)

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  unless isIdentifier programName do
    planError s!"program name '{programName}' is not a safe identifier"
  unless data.constants.isEmpty do
    planError "unsupported Quint semantic shape: constants table must be empty"
  unless data.events.isEmpty do
    planError "unsupported Quint semantic shape: events table must be empty"
  for err in data.errors do
    unless err.fields.isEmpty do
      planError "unsupported Quint semantic shape: declared errors must have zero payload fields"
  let types ← validateQuintTypeClosureV1 data.types
  let mut signed? : Option Bool := none
  for st in data.logicalState do
    signed? ← noteIntegerDomain types st.typeId signed? s!"state '{st.name}'"
  for c in data.callables do
    signed? ←
      noteIntegerDomain types c.result.typeId signed? "callable result"
    for p in c.params do
      signed? ←
        noteIntegerDomain types p.typeId signed? s!"parameter '{p.name}'"
  let signedNumeric := signed? == some true
  let numericTy := numericTyOf signedNumeric
  -- States: public UInt64 or Int64, Array UInt64 N flattened to N leaves,
  -- Option UInt64 flattened to tag+payload, or Map UInt64 cap-8 (24 leaves).
  let layout ← makeStateLayoutV1 data types signedNumeric
  let states := layout.states
  -- PureFn index for inline + pf.assets declaration gate for catalog QNs.
  let mut pureFns : Array (CallableIdV1 × CallableV1) := #[]
  for c in data.callables do
    if c.kind == .pureFn then
      pureFns := pureFns.push (c.id, c)
  let idx : CallableIndex := {
    pureFns
    pfAssetsDeclared := hasPfAssetsExtensionRow data
  }
  let mut initializer : Option PlanInit := none
  let mut entries : Array PlanEntry := #[]
  let mut views : Array PlanView := #[]
  let mut invariants : Array PlanInvariant := #[]
  let mut entryActionIndex : Nat := 0
  let mut usesVaultNative := false
  for callable in data.callables do
    match callable.kind with
    | .pureFn => do
        -- Validate every pureFn, including unreachable declarations. Otherwise
        -- unsupported dead code could be silently erased from the target model.
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Quint semantic shape: pureFn requires a name"
        unless isIdentifier name do
          planError s!"pureFn '{name}' is not a safe identifier"
        let rk ← resultKindOf data.types types callable.result.typeId s!"pureFn '{name}'"
        unless callable.result.visibility == .public_ do
          planError s!"pureFn '{name}' result must be public"
        let (_params, paramIsPrincipal, _checks, stores, assetOps, ret?, endedRevert,
            bodyUsesVault) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := false) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false)
        unless stores.isEmpty do
          planError s!"pureFn '{name}' cannot write state"
        unless assetOps.isEmpty do
          planError s!"pureFn '{name}' cannot perform external calls"
        if bodyUsesVault then
          planError s!"pureFn '{name}' cannot use envRead (host/model vault read is not pure)"
        if paramIsPrincipal.any id then
          planError s!"pureFn '{name}' parameters must be public UInt64 (no Principal)"
        match rk, ret?, endedRevert with
        | .unit, none, _ => pure ()
        | .unit, some _, _ =>
            planError s!"pureFn '{name}' Unit result must not return a value"
        | .uint64, some tv, false =>
            let _ ← requireTy tv .uint64 s!"pureFn '{name}' result"
            pure ()
        | .int64, some tv, false =>
            let _ ← requireTy tv .int64 s!"pureFn '{name}' result"
            pure ()
        | .bool, some tv, false =>
            let _ ← requireTy tv .bool s!"pureFn '{name}' result"
            pure ()
        | .uint64, none, true | .int64, none, true | .bool, none, true =>
            planError s!"pureFn '{name}' non-Unit revert-only result is outside Q0"
        | .uint64, none, false | .int64, none, false | .bool, none, false =>
            planError s!"pureFn '{name}' non-Unit return is missing"
        | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
            planError s!"pureFn '{name}' revert path cannot carry a return value"
    | .initializer => do
        unless initializer.isNone do
          planError "unsupported Quint semantic shape: at most one initializer"
        let name := callable.name.getD "initialize"
        unless isIdentifier name do
          planError s!"initializer name '{name}' is not a safe identifier"
        unless isUnitType types callable.result.typeId do
          planError "unsupported Quint semantic shape: initializer result must be Unit"
        unless callable.result.visibility == .public_ do
          planError "unsupported Quint semantic shape: initializer result must be public"
        let (params, paramIsPrincipal, checks, stores, assetOps, ret?, endedRevert,
            bodyUsesVault) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := true) (forbidChecks := true)
            (initialStateDefaults := true)
        if endedRevert then
          planError "unsupported Quint semantic shape: initializer cannot revert"
        unless checks.isEmpty do
          planError "unsupported Quint semantic shape: initializer cannot contain fallible checks"
        unless assetOps.isEmpty do
          planError "unsupported Quint semantic shape: initializer cannot contain external calls"
        if bodyUsesVault then
          planError "unsupported Quint semantic shape: initializer cannot use envRead"
        if paramIsPrincipal.any id then
          planError "unsupported Quint semantic shape: initializer parameters must be public UInt64"
        unless ret?.isNone do
          planError "unsupported Quint semantic shape: initializer must return Unit"
        initializer := some { name, params, stores }
    | .entry => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Quint semantic shape: entry requires a name"
        unless isIdentifier name do
          planError s!"entry '{name}' is not a safe identifier"
        let rk ← resultKindOf data.types types callable.result.typeId s!"entry '{name}'"
        unless callable.result.visibility == .public_ do
          planError s!"entry '{name}' result must be public"
        let (params, paramIsPrincipal, checks, stores, assetOps, ret?, endedRevert,
            bodyUsesVault) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := true) (forbidChecks := false)
            (initialStateDefaults := false)
        let result? ← match rk, ret?, endedRevert with
          | .unit, none, _ => pure none
          | .unit, some _, _ =>
              planError s!"entry '{name}' Unit result must not return a value"
          | .uint64, some tv, false =>
              let e ← requireTy tv .uint64 s!"entry '{name}' result"
              pure (some e)
          | .int64, some tv, false =>
              let e ← requireTy tv .int64 s!"entry '{name}' result"
              pure (some e)
          | .bool, some tv, false =>
              let e ← requireTy tv .bool s!"entry '{name}' result"
              pure (some e)
          | .uint64, none, true | .int64, none, true | .bool, none, true =>
              -- Revert-only path: no result expression.
              pure none
          | .uint64, none, false | .int64, none, false | .bool, none, false =>
              planError s!"entry '{name}' non-Unit return is missing"
          | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
              planError s!"entry '{name}' revert path cannot carry a return value"
        if bodyUsesVault then
          usesVaultNative := true
        entryActionIndex := entryActionIndex + 1
        entries := entries.push {
          actionIndex := entryActionIndex
          name, params, paramIsPrincipal, resultKind := rk, checks, stores
          assetOps, result?
          terminalRevert := endedRevert
        }
    | .view => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Quint semantic shape: view requires a name"
        unless isIdentifier name do
          planError s!"view '{name}' is not a safe identifier"
        let rk ← resultKindOf data.types types callable.result.typeId s!"view '{name}'"
        unless rk != .unit do
          planError s!"view '{name}' result must be UInt64, Int64, or Bool"
        unless callable.result.visibility == .public_ do
          planError s!"view '{name}' result must be public"
        let (params, paramIsPrincipal, checks, stores, assetOps, ret?, endedRevert,
            bodyUsesVault) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false)
        if endedRevert then
          planError s!"view '{name}' cannot revert"
        unless stores.isEmpty do
          planError s!"view '{name}' cannot write state"
        unless assetOps.isEmpty do
          planError s!"view '{name}' cannot perform external calls"
        if paramIsPrincipal.any id then
          planError s!"view '{name}' parameters must be public UInt64 (no Principal)"
        -- Views may only use checks that are pure observations for invariants-style
        -- AND; for views we fold checks into the value only for invariants.
        -- Spec: views emit pure def of the value; fail closed if body has assert/revert.
        unless checks.isEmpty do
          planError s!"view '{name}' cannot contain assert/revert/fallible checks (pure def only)"
        let tv ← match ret? with
          | some v => pure v
          | none => planError s!"view '{name}' must return a value"
        let value ← match rk with
          | .uint64 => requireTy tv .uint64 s!"view '{name}' result"
          | .int64 => requireTy tv .int64 s!"view '{name}' result"
          | .bool => requireTy tv .bool s!"view '{name}' result"
          | .unit => planError s!"view '{name}' result must be UInt64, Int64, or Bool"
        if bodyUsesVault then
          usesVaultNative := true
        views := views.push { name, params, resultKind := rk, value }
    | .invariant => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Quint semantic shape: invariant requires a name"
        unless isIdentifier name do
          planError s!"invariant '{name}' is not a safe identifier"
        unless callable.params.isEmpty do
          planError s!"invariant '{name}' must be zero-parameter"
        unless isBoolType types callable.result.typeId do
          planError s!"invariant '{name}' must return public Bool"
        unless callable.result.visibility == .public_ do
          planError s!"invariant '{name}' result must be public"
        let (params, _paramIsPrincipal, checks, stores, assetOps, ret?, endedRevert,
            bodyUsesVault) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false)
        if endedRevert then
          planError s!"invariant '{name}' cannot revert"
        unless params.isEmpty do
          planError s!"invariant '{name}' must be zero-parameter"
        unless stores.isEmpty do
          planError s!"invariant '{name}' cannot write state"
        unless assetOps.isEmpty do
          planError s!"invariant '{name}' cannot perform external calls"
        if bodyUsesVault then
          planError s!"invariant '{name}' cannot use envRead (invariant closure forbids host/model vault reads)"
        let tv ← match ret? with
          | some v => pure v
          | none => planError s!"invariant '{name}' must return Bool"
        let value ← requireTy tv .bool s!"invariant '{name}' result"
        invariants := invariants.push { name, checks, value }
  unless entries.size > 0 do
    planError "unsupported Quint semantic shape: at least one entry is required"
  pure {
    programName
    sourceHash
    semanticHash
    signedNumeric
    states
    initializer
    entries
    views
    invariants
    usesVaultNative
  }

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "Quint received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

/-- Internal capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .quint do
    throw <| .planInvariant .quint "engineering capability kind is not Quint"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Quint source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Quint semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

/-- Unit-test Plan entry over retained SemanticProgramV1 (no registry required). -/
def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Quint source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Quint semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Quint
