import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# ICP LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Narrow ICP-2 Counter/StateCell target leaf (ADR-0047). Envelope:

* public UInt64 **or** public Int64 state (homogeneous numeric domain: a
  program is entirely UInt64 or entirely Int64 on every integer
  state/param/result; mixing is fail closed). Array UInt64 N∈1..8 state
  flattens to N mutable i64 Wasm globals (no Candid `vec`). `Bytes N`
  (N=1..8) state flattens to N extra i64 globals storing low-8 bits
  (no Candid `vec nat8`). Anonymous `Option UInt64` state flattens to
  two extra i64 globals `{name}_tag`/`{name}_p0` (tag 0=none / 1=some;
  no Candid `opt`). Named Struct/Enum flatten to extra i64 globals
  (no Candid `record`/`variant`). Anonymous `Map UInt64 UInt64` state
  flattens to 24 extra i64 globals (cap-8 × occ/key/val; no Candid
  `vec`/`record`). Bool results are admitted. No Field; Map return,
  Option-of-*, Option params stay fail closed
* `init` (initializer), `entry` (canister_update), `view` (canister_query)
* single-block callable bodies; checked `+`/`-`/`*`/`/`/`%` and
  comparisons (no bitwise); literal, param, stateLoad, stateStore, return,
  Array IndexGet/Set/construct with a compile-time index
* zero pureFn, zero invariants, zero constants/events/errors
* zero `emit` / `call` (`Op.ExternalCall`) / `schedule` / `Op.Commit`;
  `Op.ContextRead` admits only `context.unixTimeSeconds` (`ic0.time` ns÷10⁹);
  other keys stay named fail-closed. The ICP-1 async advertise
  (`effect.asynchronous-workflow`) stays a resolver-level advertisement
  only — no ICP-2 Plan shape realizes it

Anything outside this envelope fails closed here (target-owned Plan; retains
no Semantic carrier). Not NEAR/CosmWasm Plan reuse (ADR-0007); not
sync-call/event/async materialization.
-/

namespace ProofForgeV2.Targets.Icp

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Engineering codegen profile spelling for the sole ICP-2 leaf. -/
def codegenProfileString : String := "icp-wasm-candid-u64-v1"

def codegenProfile : CodegenProfileId := CodegenProfileId.icpWasmCandidU64V1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .icp message

private def icpPlanErr (message : String) : CompileError :=
  .planInvariant .icp message

private def qnJoined (qn : ProofForgeV2.Core.Common.QualifiedName) : String :=
  String.intercalate "."
    (ProofForgeV2.Core.Common.NonEmptyArray.toArray qn.components).toList

/-- ADR-0031 S5: ICP has no sha256 or keccak256 host. Any `pf.crypto.*` QN
    stays fail closed instead of the generic ICP-2 call/schedule envelope. -/
private def isPfCryptoCalleeV1 (qn : String) : Bool :=
  qn.startsWith "pf.crypto."

/-- ADR-0031 S4 residual after CAP-1a: these UInt64 catalog keys still have
    no ICP host. `unixTimeSeconds` is bound separately to `ic0.time`.
    `context.caller` / `context.self` are Principal; ICP-2 rejects Principal
    params/results at type closure, so those keys stay on the generic
    ContextRead envelope below. -/
private def isUnboundUInt64ContextKey
    (key : ProofForgeV2.Core.Common.SchemaId) : Bool :=
  key == blockHeightContextKeyV1 ||
    key == attachedValueContextKeyV1 ||
    key == chainIdContextKeyV1

-- ---------------------------------------------------------------------------
-- Target-owned Plan surface
-- ---------------------------------------------------------------------------

/-- Numeric and Bool expression nodes. Comparisons produce a 0/1 Bool; there
    is still no control-flow `if` (single-block Counter/StateCell envelope). -/
inductive CompareOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (index : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- CAP-1a: `ic0.time` nanoseconds, truncated to whole Unix seconds. -/
  | unixTimeSeconds
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | compare (op : CompareOp) (lhs rhs : Expr)
  /-- Dense Map mux (0/1 Bool cond). Not a control-flow `if`. -/
  | ite (cond t e : Expr)
  | boolAnd (lhs rhs : Expr)
  | boolOr (lhs rhs : Expr)
  | boolNot (operand : Expr)
  deriving BEq, Inhabited, Repr

/-- Method body statement. `returnNone` is the explicit Unit terminator
    marker (initializer and Unit-result entries). -/
inductive Statement where
  | store (fieldIndex : Nat) (value : Expr)
  /-- Trap when the condition is 0. Used for Map cap-8 upsert overflow. -/
  | assert (condition : Expr)
  | returnValue (value : Expr)
  | returnNone
  /-- Flattened return (Candid positional tuple of i64 leaves). -/
  | returnAggregate (leaves : Array Expr)
  deriving BEq, Inhabited, Repr

/-- IC method dispatch mode: initializer runs once at canister install;
    mutate is a `canister_update`; query is a `canister_query`. -/
inductive MethodMode where
  | initialize
  | mutate
  | query
  deriving BEq, Inhabited, Repr

inductive ResultKind where
  | unit
  | uint64
  | int64
  | bool
  /-- Flattened return (1..8 UInt64/Int64 leaves). View and entry admit;
      Candid positional tuple, not record/opt/vec. -/
  | aggregate (leafCount : Nat)
  deriving BEq, Inhabited, Repr

structure StateField where
  name : String
  deriving BEq, Inhabited, Repr

structure Method where
  name : String
  params : Array String
  mode : MethodMode
  resultKind : ResultKind
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Target-owned ICP Plan. Digests + artifact name only; no Semantic carrier.
    `signedNumeric` is true iff every integer state/param/result is Int64
    (Candid `int64` + signed overflow). False is the historical all-`nat64`
    domain. Mixed UInt64/Int64 programs fail closed at lowering. -/
structure Plan where
  programName : String
  sourceHash : String
  semanticHash : String
  signedNumeric : Bool
  states : Array StateField
  initializer : Method
  entries : Array Method
  views : Array Method
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Type closure (anonymous unique UInt64 required; Int64 optional; Unit for init)
-- ---------------------------------------------------------------------------

private def icpTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "ICP"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/Int64 widths are supported"
  unsupportedShapeDetail :=
    "only anonymous UInt64, Int64, UInt8 (Bytes element), Bool, Unit, named Struct/Enum UInt64/Int64 leaf flatten (extra i64 globals; no Candid record/variant), Array UInt64 N state flatten, Bytes N (N i64 globals, low-8, no Candid vec nat8), Option UInt64 2-leaf identity (o_tag/o_p0, no Candid opt), Map UInt64 UInt64 cap-8 flatten (24 i64 globals, no Candid map/vec), and Principal 9-leaf identity (9 i64 globals, not Candid principal) are supported (narrow Int/Field/aggregates/String fail closed on the ICP-2 Counter/StateCell envelope)"

private def pilotUintWidthPolicyU64U32Index : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8]

private abbrev IcpTypeClosureV1 := PilotTypeClosureV1

private def validateIcpTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult IcpTypeClosureV1 :=
  validatePilotTypeClosure icpPlanErr icpTypeClosureWording types
    pilotUintWidthPolicyU64U32Index
    (intPolicy := pilotIntWidthPolicyI64)
    (fieldPolicy := pilotFieldPolicyNone)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayMapBytes)

private def maxIdentifierBytes : Nat := 200
private def maxStateFields : Nat := 64
private def maxParams : Nat := 32
private def maxBodyStatements : Nat := 256
/-- Maximum fully expanded nodes in any target Plan expression. -/
private def maxExpandedExprNodes : Nat := 4096

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

private def isUInt64Type (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  typeId == types.uint64TypeId

private def isInt64Type (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.int64TypeId == some typeId

/-- Program-wide numeric domain: signedNumeric ⇒ Int64, else UInt64. -/
private def matchesNumericDomain
    (types : IcpTypeClosureV1) (signedNumeric : Bool) (typeId : TypeIdV1) : Bool :=
  if signedNumeric then isInt64Type types typeId else isUInt64Type types typeId

private def isUnitType (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.unitTypeId == some typeId

private def isBoolType (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.boolTypeId == some typeId

private def isUInt32Type (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 32 == some typeId

private def isUInt8Type (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 8 == some typeId

private def isPrincipalType (types : IcpTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.principalTypeId == some typeId

/-- Dense Map UInt64 UInt64 pilot: cap-8 × (occ, key, val) = 24 i64 globals. -/
private def mapPilotCapacityV1 : Nat := 8
private def mapSlotsPerEntryV1 : Nat := 3
private def mapPilotLeafCountV1 : Nat :=
  mapPilotCapacityV1 * mapSlotsPerEntryV1

private def principalDataWordCountV1 : Nat := 8
private def principalMaxPayloadBytesV1 : Nat := 64
private def principalLeafCountV1 : Nat := 1 + principalDataWordCountV1

private def flattenPrincipalLeafNamesV1 (namePrefix : String) :
    CompileResult (Array String) := do
  let lenName :=
    if namePrefix.isEmpty then "len" else namePrefix ++ "_len"
  unless isIdentifier lenName do
    planError s!"state name '{lenName}' is not a safe identifier"
  let mut out : Array String := #[lenName]
  for i in [0:principalDataWordCountV1] do
    let wName :=
      if namePrefix.isEmpty then s!"w{i}" else namePrefix ++ "_w" ++ toString i
    unless isIdentifier wName do
      planError s!"state name '{wName}' is not a safe identifier"
    out := out.push wName
  pure out

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

/-- Admit only anonymous `Map UInt64 UInt64` for the dense cap-8 pilot.
    Int64-key/value Maps stay fail closed (no Candid map). -/
private def requireMapUInt64V1
    (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .map keyTid valTid, name := none, .. } =>
      unless isUInt64Type types keyTid && isUInt64Type types valTid do
        planError
          "unsupported ICP semantic shape: Map state admits only Map UInt64 UInt64"
  | _ =>
      planError
        "unsupported ICP semantic shape: Map state admits only Map UInt64 UInt64"

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]`. -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == mapPilotLeafCountV1 do
    planError
      "unsupported ICP semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .literal 0
  let mut payload : Expr := .literal 0
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported ICP semantic shape: Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported ICP semantic shape: Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      planError "unsupported ICP semantic shape: Map lookup val leaf missing"
    let hit := .boolAnd (.compare .ne occ (.literal 0)) (.compare .eq k key)
    found := .boolOr found hit
    payload := .ite hit v payload
  let tag := .ite found (.literal 1) (.literal 0)
  pure #[tag, payload]

/-- Dense Map IndexSet upsert. Returns (newLeaves, okInsert). -/
private def mapUpsertLeavesV1
    (mapLeaves : Array Expr) (key value : Expr) :
    CompileResult (Array Expr × Expr) := do
  unless mapLeaves.size == mapPilotLeafCountV1 do
    planError
      "unsupported ICP semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .literal 0
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported ICP semantic shape: Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported ICP semantic shape: Map upsert key leaf missing"
    let hit := .boolAnd (.compare .ne occ (.literal 0)) (.compare .eq k key)
    anyMatch := .boolOr anyMatch hit
  let mut seenEmpty : Expr := .literal 0
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported ICP semantic shape: Map upsert empty-scan occ missing"
    let empty := .compare .eq occ (.literal 0)
    let first := .boolAnd empty (.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := .boolOr seenEmpty empty
  let okInsert := .boolOr anyMatch seenEmpty
  let mut out : Array Expr := #[]
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported ICP semantic shape: Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported ICP semantic shape: Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      planError "unsupported ICP semantic shape: Map upsert rebuild val missing"
    let matchHit :=
      .boolAnd (.compare .ne occ (.literal 0)) (.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      planError "unsupported ICP semantic shape: Map upsert firstEmpty missing"
    let insertHere := .boolAnd firstE (.boolNot anyMatch)
    let write := .boolOr matchHit insertHere
    let occ' := .ite write (.literal 1) occ
    let k' := .ite write key k
    let v' := .ite write value v
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

/-- Admit only anonymous `Option UInt64` (tag+payload). Non-UInt64 /
    nested / named Option stay fail closed. Int64 payload stays FC
    (T5 gold is Option UInt64; mixed OptInt needles keep a payload cite). -/
private def requireOptionUInt64V1
    (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) (stateName : String) : CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .option elTid, name := none, .. } =>
      unless isUInt64Type types elTid do
        planError
          s!"unsupported ICP semantic shape: Option state '{stateName}' requires UInt64 payload"
  | _ =>
      planError
        s!"unsupported ICP semantic shape: Option state '{stateName}' requires UInt64 payload"

/-- CosmWasm/Quint-style Array UInt64 N flatten: `some n` for admitted 1..8;
    `none` for scalars or Option (Option is not a containerTypeId).
    Nested/narrow/Map/N=0/N>8 fail closed. -/
private def arrayUInt64LenV1
    (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless matchesNumericDomain types signedNumeric elTid do
        planError
          "unsupported ICP semantic shape: Array element must be UInt64 (nested/narrow/Int arrays fail closed; no Candid vec)"
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported ICP semantic shape: Array UInt64 N state must be 1..8 (got {n}; cap 8 flatten; no Candid vec)"
      pure (some n)
  | some { shape := .bytes len, .. } =>
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported ICP semantic shape: Bytes N state must be 1..8 (got {n}; cap 8 flatten; no Candid vec nat8)"
      pure (some n)
  | _ =>
      planError
        "unsupported ICP semantic shape: container TypeId is not Array UInt64 or Bytes N (Map stays fail closed)"

private def flattenNamedLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) : CompileResult (Array String) := do
  if isUInt64Type types typeId || isInt64Type types typeId then
    unless isIdentifier namePrefix do
      planError s!"state name '{namePrefix}' is not a safe identifier"
    return #[namePrefix]
  unless types.isNamedAggregate typeId do
    planError
      "unsupported ICP semantic shape: named aggregate leaf must be UInt64, Int64, or named Struct/Enum"
  match typeDecls[typeId.toNat]? with
  | none =>
      planError
        s!"unsupported ICP semantic shape: missing TypeDecl for aggregate {typeId}"
  | some decl =>
      match decl.shape with
      | .struct fields => do
          unless fields.size > 0 do
            planError
              "unsupported ICP semantic shape: named Struct requires at least one field"
          let mut out : Array String := #[]
          for f in fields do
            unless isUInt64Type types f.typeId || isInt64Type types f.typeId do
              planError
                "unsupported ICP semantic shape: named Struct field must be UInt64 or Int64 (nested named stay fail closed)"
            let subName :=
              if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
            unless isIdentifier subName do
              planError s!"state name '{subName}' is not a safe identifier"
            out := out.push subName
          pure out
      | .enum variants => do
          unless variants.size > 0 do
            planError
              "unsupported ICP semantic shape: named Enum requires at least one variant"
          let tagName :=
            if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
          unless isIdentifier tagName do
            planError s!"state name '{tagName}' is not a safe identifier"
          let mut maxPay : Nat := 0
          for v in variants do
            unless v.payloadTypes.size ≤ 1 do
              planError
                "unsupported ICP semantic shape: named Enum variant admits at most one UInt64/Int64 payload"
            for pt in v.payloadTypes do
              unless isUInt64Type types pt || isInt64Type types pt do
                planError
                  "unsupported ICP semantic shape: named Enum payload must be UInt64 or Int64 (nested named stay fail closed)"
            if v.payloadTypes.size > maxPay then maxPay := v.payloadTypes.size
          let mut out : Array String := #[tagName]
          for i in [0:maxPay] do
            let pName :=
              if namePrefix.isEmpty then s!"p{i}" else namePrefix ++ "_p" ++ toString i
            unless isIdentifier pName do
              planError s!"state name '{pName}' is not a safe identifier"
            out := out.push pName
          pure out
      | _ =>
          planError
            "unsupported ICP semantic shape: named type must be Struct or Enum"

private def flattenNamedLeafIsIntV1
    (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Array Bool) := do
  if isUInt64Type types typeId then
    return #[false]
  if isInt64Type types typeId then
    return #[true]
  unless types.isNamedAggregate typeId do
    planError
      "unsupported ICP semantic shape: named aggregate leaf must be UInt64, Int64, or named Struct/Enum"
  match typeDecls[typeId.toNat]? with
  | none =>
      planError
        s!"unsupported ICP semantic shape: missing TypeDecl for aggregate {typeId}"
  | some decl =>
      match decl.shape with
      | .struct fields => do
          unless fields.size > 0 do
            planError
              "unsupported ICP semantic shape: named Struct requires at least one field"
          let mut out : Array Bool := #[]
          for f in fields do
            unless isUInt64Type types f.typeId || isInt64Type types f.typeId do
              planError
                "unsupported ICP semantic shape: named Struct field must be UInt64 or Int64 (nested named stay fail closed)"
            out := out.push (isInt64Type types f.typeId)
          pure out
      | .enum variants => do
          unless variants.size > 0 do
            planError
              "unsupported ICP semantic shape: named Enum requires at least one variant"
          let mut maxPay : Nat := 0
          for v in variants do
            unless v.payloadTypes.size ≤ 1 do
              planError
                "unsupported ICP semantic shape: named Enum variant admits at most one UInt64/Int64 payload"
            for pt in v.payloadTypes do
              unless isUInt64Type types pt || isInt64Type types pt do
                planError
                  "unsupported ICP semantic shape: named Enum payload must be UInt64 or Int64 (nested named stay fail closed)"
            if v.payloadTypes.size > maxPay then maxPay := v.payloadTypes.size
          let mut out : Array Bool := #[false]
          for i in [0:maxPay] do
            let mut seen : Option Bool := none
            for v in variants do
              match v.payloadTypes[i]? with
              | none => pure ()
              | some pt =>
                  let isInt := isInt64Type types pt
                  match seen with
                  | none => seen := some isInt
                  | some prev =>
                      unless prev == isInt do
                        planError
                          "unsupported ICP semantic shape: named Enum payload slot mixes Int64 and UInt64"
            out := out.push (seen.getD false)
          pure out
      | _ =>
          planError
            "unsupported ICP semantic shape: named type must be Struct or Enum"

private def viewAggregateLeafIsIntV1
    (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option (Array Bool)) := do
  if isAnonymousOptionTypeIdV1 typeDecls typeId then
    requireOptionUInt64V1 typeDecls types typeId "view-return"
    return some #[false, false]
  if types.isNamedAggregate typeId then
    let marks ← flattenNamedLeafIsIntV1 typeDecls types typeId
    return some marks
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, name := none, .. } =>
      unless isUInt64Type types elTid do
        planError
          "unsupported ICP semantic shape: Array view return element must be UInt64"
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported ICP semantic shape: Array UInt64 N view return must be 1..8 (got {n})"
      return some (Array.replicate n false)
  | some { shape := .bytes len, name := none, .. } =>
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported ICP semantic shape: Bytes N view return must be 1..8 (got {n})"
      return some (Array.replicate n false)
  | _ =>
      return none

/-- Physical PlanState leaves after Array/Option/named flatten. `leavesOf[logicalId]`
    is the dense field-index list (`name`, `name_0`..`name_{N-1}`,
    `name_tag`/`name_p0`, or `{state}_{field}`). Extra i64 globals; no Candid
    record/variant. `isOptionOf` / `isNamedOf` are parallel to `leavesOf`. -/
private structure StateLayout where
  states : Array StateField
  leavesOf : Array (Array Nat)
  isOptionOf : Array Bool
  isNamedOf : Array Bool
  isMapOf : Array Bool
  deriving Inhabited

private def physicalLeaves
    (layout : StateLayout) (sid : StateIdV1) : CompileResult (Array Nat) := do
  match layout.leavesOf[sid.toNat]? with
  | some phys =>
      unless !phys.isEmpty do
        planError "unsupported ICP semantic shape: state produced zero flatten leaves"
      pure phys
  | none =>
      planError "unsupported ICP semantic shape: stateLoad/store references unknown state"

private def makeStateLayoutV1
    (data : SemanticProgramDataV1) (types : IcpTypeClosureV1)
    (signedNumeric : Bool) : CompileResult StateLayout := do
  let mut states : Array StateField := #[]
  let mut leavesOf : Array (Array Nat) := #[]
  let mut isOptionOf : Array Bool := #[]
  let mut isNamedOf : Array Bool := #[]
  let mut isMapOf : Array Bool := #[]
  for st in data.logicalState do
    unless st.id.toNat == leavesOf.size do
      planError "unsupported ICP semantic shape: state ids must match declaration order"
    unless isIdentifier st.name do
      planError s!"state name '{st.name}' is not a safe identifier"
    if types.isNamedAggregate st.typeId then
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState icpPlanErr types st
      let leafSpecs ← flattenNamedLeafSpecsV1 data.types types st.typeId st.name
      if leafSpecs.isEmpty then
        planError s!"state '{st.name}' produced zero named-aggregate leaves"
      if states.size + leafSpecs.size > maxStateFields then
        planError "unsupported ICP semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for leafName in leafSpecs do
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isNamedOf := isNamedOf.push true
      isMapOf := isMapOf.push false
    else if isAnonymousMapTypeIdV1 data.types st.typeId then
      requireMapUInt64V1 data.types types st.typeId
      if states.size + mapPilotLeafCountV1 > maxStateFields then
        planError "unsupported ICP semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for i in [0:mapPilotLeafCountV1] do
        let leafName := st.name ++ "_" ++ toString i
        unless isIdentifier leafName do
          planError s!"state name '{leafName}' is not a safe identifier"
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isNamedOf := isNamedOf.push false
      isMapOf := isMapOf.push true
    else if isAnonymousOptionTypeIdV1 data.types st.typeId then
      requireOptionUInt64V1 data.types types st.typeId st.name
      if states.size + 2 > maxStateFields then
        planError "unsupported ICP semantic shape: state field count exceeds limit"
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
      isNamedOf := isNamedOf.push false
      isMapOf := isMapOf.push false
    else if isPrincipalType types st.typeId then
      if states.size + principalLeafCountV1 > maxStateFields then
        planError "unsupported ICP semantic shape: state field count exceeds limit"
      let leafSpecs ← flattenPrincipalLeafNamesV1 st.name
      let mut leaves : Array Nat := #[]
      for leafName in leafSpecs do
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isNamedOf := isNamedOf.push false
      isMapOf := isMapOf.push false
    else
      match ← arrayUInt64LenV1 data.types types st.typeId signedNumeric with
      | some n =>
          if states.size + n > maxStateFields then
            planError "unsupported ICP semantic shape: state field count exceeds limit"
          let mut leaves : Array Nat := #[]
          for i in [0:n] do
            let leafName := st.name ++ "_" ++ toString i
            unless isIdentifier leafName do
              planError s!"state name '{leafName}' is not a safe identifier"
            leaves := leaves.push states.size
            states := states.push { name := leafName }
          leavesOf := leavesOf.push leaves
          isOptionOf := isOptionOf.push false
          isNamedOf := isNamedOf.push false
          isMapOf := isMapOf.push false
      | none =>
          requirePublicUInt64OrInt64State icpPlanErr types st
          if states.size + 1 > maxStateFields then
            planError "unsupported ICP semantic shape: state field count exceeds limit"
          let fi := states.size
          states := states.push { name := st.name }
          leavesOf := leavesOf.push #[fi]
          isOptionOf := isOptionOf.push false
          isNamedOf := isNamedOf.push false
          isMapOf := isMapOf.push false
  unless states.size ≤ maxStateFields do
    planError "unsupported ICP semantic shape: state field count exceeds limit"
  pure { states, leavesOf, isOptionOf, isNamedOf, isMapOf }

/-- First-seen integer domain. Mixed UInt64/Int64 user-facing slots fail closed. -/
private def noteIntegerDomain
    (types : IcpTypeClosureV1) (typeId : TypeIdV1) (signed? : Option Bool)
    (owner : String) : CompileResult (Option Bool) := do
  if isInt64Type types typeId then
    match signed? with
    | some false =>
        planError
          s!"unsupported ICP semantic shape: {owner} mixes Int64 with UInt64 (ICP-2 numeric domain is homogeneous)"
    | _ => pure (some true)
  else if isUInt64Type types typeId then
    match signed? with
    | some true =>
        planError
          s!"unsupported ICP semantic shape: {owner} mixes UInt64 with Int64 (ICP-2 numeric domain is homogeneous)"
    | _ => pure (some false)
  else
    pure signed?

-- ---------------------------------------------------------------------------
-- Lowering helpers
-- ---------------------------------------------------------------------------

/-- Scalar Plan Expr plus optional flatten leaves. Empty `leaves` is a
    scalar; nonempty is an Array UInt64 N aggregate (not a Candid vec),
    Option UInt64 2-leaf (not a Candid `opt`), or Principal 9-leaf
    identity (not a Candid principal). -/
private structure LoweredValue where
  expr : Expr
  leaves : Array Expr
  isPrincipal : Bool := false
  isOption : Bool := false
  isNamed : Bool := false
  isMap : Bool := false
  deriving BEq, Inhabited

private def isArrayValue (v : LoweredValue) : Bool :=
  !v.leaves.isEmpty && !v.isPrincipal && !v.isOption && !v.isNamed && !v.isMap

private def isPrincipalValue (v : LoweredValue) : Bool :=
  v.isPrincipal && v.leaves.size == principalLeafCountV1

private def isOptionValue (v : LoweredValue) : Bool :=
  v.isOption && v.leaves.size == 2

private def isNamedValue (v : LoweredValue) : Bool :=
  v.isNamed && !v.leaves.isEmpty

private def isMapValue (v : LoweredValue) : Bool :=
  v.isMap && v.leaves.size == mapPilotLeafCountV1

private def mkScalar (e : Expr) : LoweredValue :=
  { expr := e, leaves := #[] }

private def mkArrayLeaves (leaves : Array Expr) : LoweredValue :=
  { expr := leaves[0]?.getD (.literal 0), leaves }

private def mkPrincipalLeaves (leaves : Array Expr) : LoweredValue :=
  { expr := leaves[0]?.getD (.literal 0), leaves, isPrincipal := true }

private def mkOptionLeaves (leaves : Array Expr) : LoweredValue :=
  { expr := leaves[0]?.getD (.literal 0), leaves, isOption := true }

private def mkNamedLeaves (leaves : Array Expr) : LoweredValue :=
  { expr := leaves[0]?.getD (.literal 0), leaves, isNamed := true }

private def mkMapLeaves (leaves : Array Expr) : LoweredValue :=
  { expr := leaves[0]?.getD (.literal 0), leaves, isMap := true }

private def decodePrincipalLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless bytes.size ≥ 4 do
    planError
      "unsupported ICP semantic shape: Principal literal valueBytes too short"
  let len :=
    (bytes.get! 0).toNat + (bytes.get! 1).toNat * 256 +
      (bytes.get! 2).toNat * 65536 + (bytes.get! 3).toNat * 16777216
  unless bytes.size == 4 + len do
    planError
      "unsupported ICP semantic shape: Principal literal valueBytes length framing mismatch"
  unless 1 ≤ len do
    planError
      "unsupported ICP semantic shape: Principal body shorter than 1 byte"
  unless len ≤ principalMaxPayloadBytesV1 do
    planError
      s!"unsupported ICP semantic shape: Principal longer than {principalMaxPayloadBytesV1} bytes (identity bound)"
  let payload := bytes.extract 4 bytes.size
  let mut leaves : Array Expr := #[.literal (UInt64.ofNat len)]
  for w in [0:principalDataWordCountV1] do
    let mut word : Nat := 0
    let mut place : Nat := 1
    for b in [0:8] do
      let idx := w * 8 + b
      let byte := if idx < payload.size then (payload.get! idx).toNat else 0
      word := word + byte * place
      place := place * 256
    leaves := leaves.push (.literal (UInt64.ofNat word))
  pure leaves

private def requireScalar (v : LoweredValue) (what : String) : CompileResult Expr := do
  if isArrayValue v || isPrincipalValue v || isOptionValue v || isNamedValue v ||
      isMapValue v then
    planError s!"unsupported ICP semantic shape: {what} cannot be an Array/Principal/Option/named/Map aggregate"
  pure v.expr

private structure ValueEnv where
  entries : Array (ValueIdV1 × LoweredValue)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option LoweredValue :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (v : LoweredValue) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

/-- Overlay for StateStore → subsequent StateLoad within the single block.
    Last write wins on `overlayFinalStores` projection. Values are logical
    (Array aggregates stay one overlay slot and expand to physical leaves). -/
private structure StateOverlay where
  entries : Array (StateIdV1 × LoweredValue)
  deriving Inhabited

private def overlayLookup (ov : StateOverlay) (sid : StateIdV1) : Option LoweredValue :=
  ov.entries.findSome? (fun (id, e) => if id == sid then some e else none)

private def overlayInsert
    (ov : StateOverlay) (sid : StateIdV1) (e : LoweredValue) : StateOverlay :=
  let withoutOld := ov.entries.filter (fun item => item.1 != sid)
  { ov with entries := withoutOld.push (sid, e) }

/-- Emit final stores in ascending **physical** field-index order. -/
private def overlayFinalStores
    (layout : StateLayout) (ov : StateOverlay) : Array Statement := Id.run do
  let mut last : Array (Option Expr) := #[]
  for (sid, v) in ov.entries do
    match layout.leavesOf[sid.toNat]? with
    | none => pure ()
    | some phys =>
        if !v.leaves.isEmpty then
          for i in [0:phys.size] do
            match phys[i]?, v.leaves[i]? with
            | some fi, some e =>
                while last.size ≤ fi do
                  last := last.push none
                last := last.set! fi (some e)
            | _, _ => pure ()
        else
          match phys[0]? with
          | none => pure ()
          | some fi =>
              while last.size ≤ fi do
                last := last.push none
              last := last.set! fi (some v.expr)
  let mut out : Array Statement := #[]
  for i in [0:last.size] do
    match last[i]? with
    | some (some e) => out := out.push (.store i e)
    | _ => pure ()
  pure out

/-- After overlay stores are projected, a return that still names the pre-store
    Expr tree would re-evaluate that tree in Emit (classic store-then-read
    hazard: `count := count + delta; return count` became add-twice). Map any
    return Expr that is exactly an overlay scalar or Array leaf back to
    `.stateLoad` of the physical field that now holds it. -/
private def rewriteReturnThroughOverlay
    (layout : StateLayout) (ov : StateOverlay) (e : Expr) : Expr :=
  Id.run do
    for (sid, v) in ov.entries do
      match layout.leavesOf[sid.toNat]? with
      | none => pure ()
      | some phys =>
          if isArrayValue v || isMapValue v then
            for i in [0:phys.size] do
              match phys[i]?, v.leaves[i]? with
              | some fi, some leaf =>
                  if leaf == e then return .stateLoad fi
              | _, _ => pure ()
          else if v.expr == e then
            match phys[0]? with
            | some fi => return .stateLoad fi
            | none => pure ()
    return e

private structure BodyAccum where
  env : ValueEnv
  overlay : StateOverlay
  opCount : Nat
  asserts : Array Expr := #[]
  deriving Inhabited

private def emptyBodyAccum (env : ValueEnv) (overlay : StateOverlay) : BodyAccum :=
  { env, overlay, opCount := 0, asserts := #[] }

private def bumpOp (acc : BodyAccum) : CompileResult BodyAccum := do
  if acc.opCount + 1 > maxBodyStatements then
    planError "unsupported ICP semantic shape: body operation count exceeds limit"
  pure { acc with opCount := acc.opCount + 1 }

private partial def exprNodes : Expr → Nat
  | .literal _ | .param _ | .stateLoad _ | .unixTimeSeconds => 1
  | .checkedAdd lhs rhs | .checkedSub lhs rhs
  | .checkedMul lhs rhs | .checkedDiv lhs rhs | .checkedMod lhs rhs
  | .compare _ lhs rhs | .boolAnd lhs rhs | .boolOr lhs rhs =>
      1 + exprNodes lhs + exprNodes rhs
  | .boolNot operand => 1 + exprNodes operand
  | .ite cond t e => 1 + exprNodes cond + exprNodes t + exprNodes e

private def checkedExprNodes (what : String) (e : Expr) : CompileResult Expr := do
  unless exprNodes e ≤ maxExpandedExprNodes do
    planError
      s!"unsupported ICP semantic shape: {what} expanded expression exceeds {maxExpandedExprNodes} nodes"
  pure e

private def lowerLiteral
    (types : IcpTypeClosureV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult LoweredValue := do
  if isInt64Type types typeId then
    let v ← decodeInt64LiteralLe icpPlanErr "ICP" valueBytes
    pure (mkScalar (.literal v))
  else if isUInt64Type types typeId then
    let v ← decodeUInt64LiteralLe icpPlanErr "ICP" valueBytes
    pure (mkScalar (.literal v))
  else if isUInt32Type types typeId then
    let v ← decodeUInt32LiteralLe icpPlanErr "ICP" valueBytes
    pure (mkScalar (.literal v))
  else if isUInt8Type types typeId then
    let v ← decodeUInt8LiteralLe icpPlanErr "ICP" valueBytes
    pure (mkScalar (.literal v))
  else if isBoolType types typeId then
    let b ← decodeBoolLiteralBit icpPlanErr "ICP" valueBytes
    pure (mkScalar (.literal (if b then 1 else 0)))
  else if isPrincipalType types typeId then
    let leaves ← decodePrincipalLiteralLeavesV1 valueBytes
    pure (mkPrincipalLeaves leaves)
  else
    planError "unsupported ICP semantic shape: literal type is outside UInt64/Int64/UInt32/UInt8/Bool/Principal"

private def literalIndexNatV1 (v : LoweredValue) : CompileResult Nat := do
  let e ← requireScalar v "Array index"
  match e with
  | .literal n => pure n.toNat
  | _ =>
      planError
        "unsupported ICP semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def lowerBinary (op : BinaryOpV1) (lhs rhs : Expr) : CompileResult Expr := do
  match op with
  | .add => checkedExprNodes "add" (.checkedAdd lhs rhs)
  | .sub => checkedExprNodes "sub" (.checkedSub lhs rhs)
  | .mul => checkedExprNodes "mul" (.checkedMul lhs rhs)
  | .div => checkedExprNodes "div" (.checkedDiv lhs rhs)
  | .mod => checkedExprNodes "mod" (.checkedMod lhs rhs)
  | .eq => checkedExprNodes "eq" (.compare .eq lhs rhs)
  | .ne => checkedExprNodes "ne" (.compare .ne lhs rhs)
  | .lt => checkedExprNodes "lt" (.compare .lt lhs rhs)
  | .le => checkedExprNodes "le" (.compare .le lhs rhs)
  | .gt => checkedExprNodes "gt" (.compare .gt lhs rhs)
  | .ge => checkedExprNodes "ge" (.compare .ge lhs rhs)
  | .and | .or
  | .bitAnd | .bitOr | .bitXor | .shl | .shr =>
      planError
        "unsupported ICP semantic shape: only checked add/sub/mul/div/mod and comparisons are admitted on the ICP-2 Counter/StateCell envelope"

/-- Single-block instruction walk (ICP-2 has no pureFn/invariant closures, no
    branching, no async continuations — StateCell shape only). -/
private partial def lowerInstructions
    (data : SemanticProgramDataV1) (types : IcpTypeClosureV1)
    (layout : StateLayout) (allowStateWrite : Bool) (signedNumeric : Bool)
    (callable : CallableV1)
    (acc0 : BodyAccum) :
    CompileResult (BodyAccum × Option LoweredValue) := do
  unless callable.blocks.size == 1 do
    planError
      "unsupported ICP semantic shape: each callable must have exactly one block (Counter/StateCell envelope has no control flow)"
  unless callable.loopBounds.isEmpty do
    planError "unsupported ICP semantic shape: loopBounds are outside ICP-2"
  unless callable.entryBlock.toNat == 0 do
    planError "unsupported ICP semantic shape: entryBlock must be 0"
  let some block := callable.blocks[0]? |
    planError "unsupported ICP semantic shape: missing entry block"
  unless block.params.isEmpty do
    planError "unsupported ICP semantic shape: block parameters are outside ICP-2"
  let mut acc := acc0
  for instr in block.instructions do
    acc ← bumpOp acc
    match instr.op with
    | .literal typeId valueBytes => do
        let v ← lowerLiteral types typeId valueBytes
        match instr.result with
        | none => planError "unsupported ICP semantic shape: literal must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId v }
    | .constant constantId => do
        let some c := data.constants[constantId.toNat]? |
          planError "unsupported ICP semantic shape: Constant references an unknown constant id"
        unless c.id == constantId do
          planError "unsupported ICP semantic shape: Constant id does not match declaration order"
        let v ← lowerLiteral types c.typeId c.valueBytes
        match instr.result with
        | none => planError "unsupported ICP semantic shape: Constant must produce a value"
        | some vd =>
            unless vd.typeId == c.typeId do
              planError "unsupported ICP semantic shape: Constant result typeId must match the declaration"
            acc := { acc with env := envInsert acc.env vd.valueId v }
    | .stateLoad stateId => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: stateLoad must produce a value"
        | some vd =>
            unless stateId.toNat < data.logicalState.size do
              planError "unsupported ICP semantic shape: stateLoad references unknown state"
            let phys ← physicalLeaves layout stateId
            let isOpt :=
              match layout.isOptionOf[stateId.toNat]? with
              | some b => b
              | none => false
            let isNm :=
              match layout.isNamedOf[stateId.toNat]? with
              | some b => b
              | none => false
            let isMp :=
              match layout.isMapOf[stateId.toNat]? with
              | some b => b
              | none => false
            let value : LoweredValue :=
              match overlayLookup acc.overlay stateId with
              | some ov => ov
              | none =>
                  if phys.size == 1 then
                    mkScalar (.stateLoad phys[0]!)
                  else if isOpt then
                    mkOptionLeaves (phys.map (fun fi => .stateLoad fi))
                  else if isNm then
                    mkNamedLeaves (phys.map (fun fi => .stateLoad fi))
                  else if isMp then
                    mkMapLeaves (phys.map (fun fi => .stateLoad fi))
                  else if isPrincipalType types vd.typeId then
                    mkPrincipalLeaves (phys.map (fun fi => .stateLoad fi))
                  else
                    mkArrayLeaves (phys.map (fun fi => .stateLoad fi))
            acc := { acc with env := envInsert acc.env vd.valueId value }
    | .stateStore stateId value => do
        unless allowStateWrite do
          planError "unsupported ICP semantic shape: view methods cannot write state"
        let v ← match envLookup acc.env value with
          | some tv => pure tv
          | none => planError "unsupported ICP semantic shape: stateStore value undefined"
        unless stateId.toNat < data.logicalState.size do
          planError "unsupported ICP semantic shape: stateStore references unknown state"
        let phys ← physicalLeaves layout stateId
        if !v.leaves.isEmpty then
          unless v.leaves.size == phys.size do
            planError "unsupported ICP semantic shape: stateStore leaf count mismatch"
        else
          unless phys.size == 1 do
            planError "unsupported ICP semantic shape: stateStore scalar into Array/Principal state"
        acc := { acc with overlay := overlayInsert acc.overlay stateId v }
    | .binary op lhs rhs => do
        let lv ← match envLookup acc.env lhs with
          | some v => pure v
          | none => planError "unsupported ICP semantic shape: binary lhs undefined"
        let rv ← match envLookup acc.env rhs with
          | some v => pure v
          | none => planError "unsupported ICP semantic shape: binary rhs undefined"
        if isPrincipalValue lv && isPrincipalValue rv then
          unless op == .eq || op == .ne do
            planError "unsupported ICP semantic shape: Principal comparison only supports eq/ne"
          let mut accEq : Expr :=
            .compare .eq lv.leaves[0]! rv.leaves[0]!
          for i in [1:principalLeafCountV1] do
            accEq := .checkedMul accEq (.compare .eq lv.leaves[i]! rv.leaves[i]!)
          let e :=
            if op == .ne then .compare .eq accEq (.literal 0) else accEq
          let e ← checkedExprNodes "principal comparison" e
          match instr.result with
          | none => planError "unsupported ICP semantic shape: binary must produce a value"
          | some vd => acc := { acc with env := envInsert acc.env vd.valueId (mkScalar e) }
        else
          let le ← requireScalar lv "binary lhs"
          let re ← requireScalar rv "binary rhs"
          let e ← lowerBinary op le re
          match instr.result with
          | none => planError "unsupported ICP semantic shape: binary must produce a value"
          | some vd => acc := { acc with env := envInsert acc.env vd.valueId (mkScalar e) }
    | .contextRead key => do
        match instr.result with
        | none =>
            planError "unsupported ICP semantic shape: ContextRead must produce a value"
        | some vd =>
            if key == unixTimeSecondsContextKeyV1 then
              unless isUInt64Type types vd.typeId do
                planError
                  "unsupported ICP semantic shape: ContextRead unix-time-seconds result must be UInt64"
              acc := { acc with env := envInsert acc.env vd.valueId (mkScalar .unixTimeSeconds) }
            else if isUnboundUInt64ContextKey key then
              planError
                s!"unsupported ICP semantic shape: ContextRead '{key.value}' has no Icp host binding (blockHeight/attachedValue/chainId stay fail closed)"
            else
              -- caller/self remain on this generic envelope (Principal first).
              planError
                "unsupported ICP semantic shape: Op.ContextRead is outside the ICP-2 envelope"
    | .commit .. =>
        planError "unsupported ICP semantic shape: Op.Commit is outside the ICP-2 envelope"
    | .emit .. =>
        planError "unsupported ICP semantic shape: emit is outside the ICP-2 envelope (no portable event bus)"
    | .externalCall _effectId callee _args => do
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          planError
            s!"unsupported ICP semantic shape: pf.crypto QN '{qn}' has no Icp host binding (sha256/keccak256 and siblings stay fail closed)"
        planError "unsupported ICP semantic shape: call is outside the ICP-2 envelope (ICP has no sync inter-canister call)"
    | .schedule _effectId callee _args => do
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          planError
            s!"unsupported ICP semantic shape: pf.crypto QN '{qn}' has no Icp host binding (sha256/keccak256 and siblings stay fail closed)"
        planError "unsupported ICP semantic shape: schedule (async workflow) is advertised at the resolver only — ICP-2 Plan has no realized async shape"
    | .envRead key _args =>
        if key == .nativeVaultBalance then
          planError
            s!"unsupported ICP semantic shape: envRead nativeVaultBalance has no Icp host binding (pf.assets.native.balanceOfSelf stays fail closed)"
        -- tokenVaultBalance needs a Principal mint; nativeVaultBalanceU128 is
        -- outside ICP-2 UInt64. Both stay on the generic envRead envelope.
        planError "unsupported ICP semantic shape: op is outside the ICP-2 Counter/StateCell envelope"
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: construct must produce a value"
        | some vd =>
            if isAnonymousMapTypeIdV1 data.types typeId then
              requireMapUInt64V1 data.types types typeId
              unless ctorIdx == 0 do
                planError
                  "unsupported ICP semantic shape: Map construct ctorIdx must be 0"
              unless argIds.isEmpty do
                planError
                  "unsupported ICP semantic shape: nonempty Map construct is outside ICP-2 (build maps via IndexSet upsert)"
              let zeros := Array.replicate mapPilotLeafCountV1 (.literal 0)
              acc := { acc with
                env := envInsert acc.env vd.valueId (mkMapLeaves zeros) }
            else if isAnonymousOptionTypeIdV1 data.types typeId then
              requireOptionUInt64V1 data.types types typeId "construct"
              match ctorIdx.toNat with
              | 0 =>
                  unless argIds.isEmpty do
                    planError
                      "unsupported ICP semantic shape: Option.none construct takes no args"
                  acc := { acc with
                    env := envInsert acc.env vd.valueId
                      (mkOptionLeaves #[.literal 0, .literal 0]) }
              | 1 =>
                  unless argIds.size == 1 do
                    planError
                      "unsupported ICP semantic shape: Option.some construct takes one arg"
                  let some argId := argIds[0]? |
                    planError "unsupported ICP semantic shape: Option.some construct arg missing"
                  let av ← match envLookup acc.env argId with
                    | some v => requireScalar v "Option.some arg"
                    | none => planError "unsupported ICP semantic shape: construct arg undefined"
                  acc := { acc with
                    env := envInsert acc.env vd.valueId
                      (mkOptionLeaves #[.literal 1, av]) }
              | _ =>
                  planError
                    "unsupported ICP semantic shape: Option construct ctorIdx must be 0 (none) or 1 (some)"
            else if types.isNamedAggregate typeId then
              let some decl := data.types[typeId.toNat]? |
                planError "unsupported ICP semantic shape: construct TypeDecl missing"
              match decl.shape with
              | .struct fields => do
                  unless ctorIdx.toNat == 0 do
                    planError
                      "unsupported ICP semantic shape: struct construct ctorIdx must be 0"
                  unless argIds.size == fields.size do
                    planError
                      "unsupported ICP semantic shape: struct construct arity mismatch"
                  let mut leafExprs : Array Expr := #[]
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "unsupported ICP semantic shape: struct construct arg missing"
                    let some field := fields[i]? |
                      planError "unsupported ICP semantic shape: struct construct field missing"
                    unless isUInt64Type types field.typeId || isInt64Type types field.typeId do
                      planError
                        "unsupported ICP semantic shape: named Struct field must be UInt64 or Int64"
                    let av ← match envLookup acc.env argId with
                      | some v => requireScalar v "struct construct arg"
                      | none => planError "unsupported ICP semantic shape: construct arg undefined"
                    leafExprs := leafExprs.push av
                  acc := { acc with
                    env := envInsert acc.env vd.valueId (mkNamedLeaves leafExprs) }
              | .enum variants => do
                  let vi := ctorIdx.toNat
                  let some variant := variants[vi]? |
                    planError
                      "unsupported ICP semantic shape: enum construct variant out of range"
                  unless argIds.size == variant.payloadTypes.size do
                    planError
                      "unsupported ICP semantic shape: enum construct arity mismatch"
                  let mut maxPay : Nat := 0
                  for v in variants do
                    if v.payloadTypes.size > maxPay then maxPay := v.payloadTypes.size
                  let mut leafExprs : Array Expr := #[.literal (UInt64.ofNat vi)]
                  for argId in argIds do
                    let av ← match envLookup acc.env argId with
                      | some v => requireScalar v "enum construct payload"
                      | none => planError "unsupported ICP semantic shape: construct arg undefined"
                    leafExprs := leafExprs.push av
                  while leafExprs.size < 1 + maxPay do
                    leafExprs := leafExprs.push (.literal 0)
                  acc := { acc with
                    env := envInsert acc.env vd.valueId (mkNamedLeaves leafExprs) }
              | _ =>
                  planError
                    "unsupported ICP semantic shape: named construct requires Struct or Enum"
            else
              let n ← match ← arrayUInt64LenV1 data.types types typeId signedNumeric with
                | some n => pure n
                | none =>
                    planError
                      "unsupported ICP semantic shape: construct admits only Array UInt64 N, Option UInt64, Map UInt64 UInt64, or named Struct/Enum on ICP-2"
              unless ctorIdx == 0 do
                planError "unsupported ICP semantic shape: Array construct ctorIdx must be 0"
              unless argIds.size == n do
                planError "unsupported ICP semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              for argId in argIds do
                let av ← match envLookup acc.env argId with
                  | some v => requireScalar v "Array construct arg"
                  | none => planError "unsupported ICP semantic shape: construct arg undefined"
                leafExprs := leafExprs.push av
              acc := { acc with
                env := envInsert acc.env vd.valueId (mkArrayLeaves leafExprs) }
    | .indexGet base index => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: IndexGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: IndexGet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: IndexGet index undefined"
            if isMapValue bv then
              let key ← requireScalar iv "Map IndexGet key"
              let optLeaves ← mapLookupOptionLeavesV1 bv.leaves key
              acc := { acc with
                env := envInsert acc.env vd.valueId (mkOptionLeaves optLeaves) }
            else do
              unless isArrayValue bv do
                planError
                  "unsupported ICP semantic shape: IndexGet base must be an Array UInt64 or Map UInt64 aggregate"
              let i ← literalIndexNatV1 iv
              unless i < bv.leaves.size do
                planError "unsupported ICP semantic shape: Array IndexGet index out of range"
              let some leaf := bv.leaves[i]? |
                planError "unsupported ICP semantic shape: Array IndexGet leaf missing"
              acc := { acc with env := envInsert acc.env vd.valueId (mkScalar leaf) }
    | .indexSet base index value => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: IndexSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: IndexSet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: IndexSet index undefined"
            let vv ← match envLookup acc.env value with
              | some v => requireScalar v "IndexSet value"
              | none => planError "unsupported ICP semantic shape: IndexSet value undefined"
            if isMapValue bv then
              let key ← requireScalar iv "Map IndexSet key"
              let (newLeaves, okInsert) ← mapUpsertLeavesV1 bv.leaves key vv
              acc := { acc with
                asserts := acc.asserts.push okInsert
                env := envInsert acc.env vd.valueId (mkMapLeaves newLeaves) }
            else do
              unless isArrayValue bv do
                planError
                  "unsupported ICP semantic shape: IndexSet base must be an Array UInt64 or Map UInt64 aggregate"
              let i ← literalIndexNatV1 iv
              unless i < bv.leaves.size do
                planError "unsupported ICP semantic shape: Array IndexSet index out of range"
              let newLeaves := bv.leaves.set! i vv
              acc := { acc with
                env := envInsert acc.env vd.valueId (mkArrayLeaves newLeaves) }
    | .variantTag baseId => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: variantTag must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: variantTag base undefined"
            unless isOptionValue bv || isNamedValue bv do
              planError
                "unsupported ICP semantic shape: variantTag base must be Option UInt64 or named Enum"
            let some tag := bv.leaves[0]? |
              planError "unsupported ICP semantic shape: variantTag Option tag leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId (mkScalar tag) }
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none =>
            planError "unsupported ICP semantic shape: variantPayload must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none =>
                  planError "unsupported ICP semantic shape: variantPayload base undefined"
            unless isOptionValue bv || isNamedValue bv do
              planError
                "unsupported ICP semantic shape: variantPayload base must be Option UInt64 or named Enum"
            if variantIndex.toNat == 0 then
              planError
                "unsupported ICP semantic shape: variantPayload of Option.none is empty"
            unless variantIndex.toNat == 1 && payloadIndex.toNat == 0 do
              planError
                "unsupported ICP semantic shape: variantPayload Option some requires (variant 1, payload 0)"
            let some payload := bv.leaves[1]? |
              planError
                "unsupported ICP semantic shape: variantPayload Option payload leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId (mkScalar payload) }
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: fieldGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: fieldGet base undefined"
            unless isNamedValue bv do
              planError
                "unsupported ICP semantic shape: fieldGet base must be a named Struct"
            let i := fieldIndex.toNat
            unless i < bv.leaves.size do
              planError "unsupported ICP semantic shape: fieldGet leaf index out of range"
            let some leaf := bv.leaves[i]? |
              planError "unsupported ICP semantic shape: fieldGet leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId (mkScalar leaf) }
    | .fieldSet baseId fieldIndex valueId => do
        match instr.result with
        | none => planError "unsupported ICP semantic shape: fieldSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported ICP semantic shape: fieldSet base undefined"
            unless isNamedValue bv do
              planError
                "unsupported ICP semantic shape: fieldSet base must be a named Struct"
            let vv ← match envLookup acc.env valueId with
              | some v => requireScalar v "fieldSet value"
              | none => planError "unsupported ICP semantic shape: fieldSet value undefined"
            let i := fieldIndex.toNat
            unless i < bv.leaves.size do
              planError "unsupported ICP semantic shape: fieldSet leaf index out of range"
            let newLeaves := bv.leaves.set! i vv
            acc := { acc with
              env := envInsert acc.env vd.valueId (mkNamedLeaves newLeaves) }
    | .checkedCast .. | .unary .. | .pureCall .. | .assert_ .. =>
        planError "unsupported ICP semantic shape: op is outside the ICP-2 Counter/StateCell envelope"
  match block.terminator with
  | .return_ value => do
      match value with
      | none => pure (acc, none)
      | some vid =>
          match envLookup acc.env vid with
          | some v =>
              pure (acc, some v)
          | none => planError "unsupported ICP semantic shape: return value undefined"
  | .revert .. =>
      planError "unsupported ICP semantic shape: revert is outside the ICP-2 envelope (errors table must be empty)"
  | .jump .. | .branch .. | .switch .. | .trap .. =>
      planError "unsupported ICP semantic shape: multi-block/branch/switch/trap terminators are outside ICP-2 (no control flow)"

private def seedParamEnv (typeDecls : Array TypeDeclV1) (types : IcpTypeClosureV1)
    (owner : String) (callable : CallableV1) :
    CompileResult (ValueEnv × Array String) := do
  let mut env : ValueEnv := { entries := #[] }
  let mut names : Array String := #[]
  let mut i : Nat := 0
  for p in callable.params do
    unless isIdentifier p.name do
      planError s!"parameter '{p.name}' in {owner} is not a safe identifier"
    if isAnonymousOptionTypeIdV1 typeDecls p.typeId then
      planError s!"{owner} Option params are outside ICP-2"
    if types.isNamedAggregate p.typeId then
      unless p.visibility == .public_ do
        planError s!"parameter '{p.name}' in {owner} is not public"
      let leafSpecs ← flattenNamedLeafSpecsV1 typeDecls types p.typeId p.name
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        names := names.push leafName
        leafExprs := leafExprs.push (.param i)
        i := i + 1
      env := envInsert env p.valueId (mkNamedLeaves leafExprs)
    else if isPrincipalType types p.typeId then
      unless p.visibility == .public_ do
        planError s!"parameter '{p.name}' in {owner} is not public"
      let leafSpecs ← flattenPrincipalLeafNamesV1 p.name
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        names := names.push leafName
        leafExprs := leafExprs.push (.param i)
        i := i + 1
      env := envInsert env p.valueId (mkPrincipalLeaves leafExprs)
    else
      requirePublicUInt64OrInt64Param icpPlanErr types owner p
      env := envInsert env p.valueId (mkScalar (.param i))
      names := names.push p.name
      i := i + 1
  unless names.size ≤ maxParams do
    planError s!"{owner} parameter count exceeds limit"
  if hasDuplicates names then
    planError s!"{owner} parameter names must be unique"
  pure (env, names)

private def lowerCallableBody
    (data : SemanticProgramDataV1) (types : IcpTypeClosureV1)
    (layout : StateLayout) (allowStateWrite seedZeroState : Bool)
    (signedNumeric : Bool)
    (owner : String) (callable : CallableV1) :
    CompileResult (Array String × Array Statement × Option LoweredValue) := do
  let (env0, paramNames) ← seedParamEnv data.types types owner callable
  let mut overlay0 : StateOverlay := { entries := #[] }
  if seedZeroState then
    for st in data.logicalState do
      let phys ← physicalLeaves layout st.id
      let isOpt :=
        match layout.isOptionOf[st.id.toNat]? with
        | some b => b
        | none => false
      let isNm :=
        match layout.isNamedOf[st.id.toNat]? with
        | some b => b
        | none => false
      let isMp :=
        match layout.isMapOf[st.id.toNat]? with
        | some b => b
        | none => false
      if phys.size == 1 then
        overlay0 := overlayInsert overlay0 st.id (mkScalar (.literal 0))
      else if isOpt then
        overlay0 := overlayInsert overlay0 st.id
          (mkOptionLeaves (phys.map (fun _ => .literal 0)))
      else if isNm then
        overlay0 := overlayInsert overlay0 st.id
          (mkNamedLeaves (phys.map (fun _ => .literal 0)))
      else if isMp then
        overlay0 := overlayInsert overlay0 st.id
          (mkMapLeaves (phys.map (fun _ => .literal 0)))
      else if isPrincipalType types st.typeId then
        overlay0 := overlayInsert overlay0 st.id
          (mkPrincipalLeaves (phys.map (fun _ => .literal 0)))
      else
        overlay0 := overlayInsert overlay0 st.id
          (mkArrayLeaves (phys.map (fun _ => .literal 0)))
  let acc0 := emptyBodyAccum env0 overlay0
  let (acc, ret?) ←
    lowerInstructions data types layout allowStateWrite signedNumeric callable acc0
  let mut stores := acc.asserts.map (fun c => Statement.assert c)
  stores := stores ++ overlayFinalStores layout acc.overlay
  let ret? := ret?.map (fun v =>
    { v with
      expr := rewriteReturnThroughOverlay layout acc.overlay v.expr
      leaves := v.leaves.map (rewriteReturnThroughOverlay layout acc.overlay) })
  pure (paramNames, stores, ret?)

private def resultKindOf
    (data : SemanticProgramDataV1) (types : IcpTypeClosureV1)
    (typeId : TypeIdV1) (owner : String) (allowViewAggregate : Bool) :
    CompileResult ResultKind := do
  if isUnitType types typeId then pure .unit
  else if isBoolType types typeId then pure .bool
  else if isInt64Type types typeId then pure .int64
  else if isUInt64Type types typeId then pure .uint64
  else if isPrincipalType types typeId then
    planError s!"{owner} Principal return is outside ICP-2"
  else if allowViewAggregate then
    match data.types[typeId.toNat]? with
    | some { shape := .bytes len, name := none, .. } => do
        unless owner.startsWith "view " do
          planError
            s!"{owner} Bytes return is outside ICP-2 (only Bytes N view flattens; no Candid vec nat8; entry stays fail closed)"
        let n := len.toNat
        unless 1 ≤ n && n ≤ 8 do
          planError s!"{owner} Bytes N return must be 1..8 (got {n})"
        pure (.aggregate n)
    | _ =>
    match ← viewAggregateLeafIsIntV1 data.types types typeId with
    | some marks => do
        let n := marks.size
        unless 1 ≤ n && n ≤ 8 do
          planError
            s!"{owner} aggregate return must have 1..8 leaves (got {n})"
        pure (.aggregate n)
    | none =>
        if isAnonymousOptionTypeIdV1 data.types typeId then
          planError s!"{owner} Option return is outside ICP-2"
        else if types.isNamedAggregate typeId then
          planError s!"{owner} named Struct/Enum return is outside ICP-2"
        else if types.isContainer typeId then
          planError
            s!"{owner} Array/Map return is outside ICP-2 (only Array UInt64 N / Map UInt64 UInt64 state flattens; no Candid vec/map)"
        else planError s!"{owner} result must be public Unit, UInt64, Int64, or Bool"
  else if isAnonymousOptionTypeIdV1 data.types typeId then
    planError s!"{owner} Option return is outside ICP-2"
  else if types.isNamedAggregate typeId then
    planError s!"{owner} named Struct/Enum return is outside ICP-2"
  else if types.isContainer typeId then
    planError
      s!"{owner} Array/Map return is outside ICP-2 (only Array UInt64 N / Map UInt64 UInt64 state flattens; no Candid vec/map)"
  else planError s!"{owner} result must be public Unit, UInt64, Int64, or Bool"

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  unless isIdentifier programName do
    planError s!"program name '{programName}' is not a safe identifier"
  unless data.events.isEmpty do
    planError "unsupported ICP semantic shape: events table must be empty (emit is outside ICP-2)"
  unless data.errors.isEmpty do
    planError "unsupported ICP semantic shape: errors table must be empty (revert is outside ICP-2)"
  unless data.invariants.isEmpty do
    planError "unsupported ICP semantic shape: invariants must be empty (nonempty invariants fail closed on ICP-2)"
  let types ← validateIcpTypeClosureV1 data.types
  for c in data.constants do
    unless isInt64Type types c.typeId || isUInt64Type types c.typeId ||
        isUInt32Type types c.typeId do
      planError
        "unsupported ICP semantic shape: constant is not admitted UInt64/Int64/UInt32"
    let _ ← lowerLiteral types c.typeId c.valueBytes
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
  let layout ← makeStateLayoutV1 data types signedNumeric
  let states := layout.states
  let mut initializer? : Option Method := none
  let mut entries : Array Method := #[]
  let mut views : Array Method := #[]
  for callable in data.callables do
    match callable.kind with
    | .pureFn =>
        planError "unsupported ICP semantic shape: pureFn is outside the ICP-2 Counter/StateCell envelope"
    | .invariant =>
        planError "unsupported ICP semantic shape: invariant callables are outside the ICP-2 envelope"
    | .initializer => do
        unless initializer?.isNone do
          planError "unsupported ICP semantic shape: at most one initializer"
        unless isUnitType types callable.result.typeId do
          planError "unsupported ICP semantic shape: initializer result must be Unit"
        unless callable.result.visibility == .public_ do
          planError "unsupported ICP semantic shape: initializer result must be public"
        for p in callable.params do
          signed? ← noteIntegerDomain types p.typeId signed? s!"initializer parameter '{p.name}'"
        let (params, stores, ret?) ←
          lowerCallableBody data types layout (allowStateWrite := true)
            (seedZeroState := true) signedNumeric "initializer" callable
        unless ret?.isNone do
          planError "unsupported ICP semantic shape: initializer must return Unit"
        initializer? := some {
          name := "init", params, mode := .initialize, resultKind := .unit
          body := stores
        }
    | .entry => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported ICP semantic shape: entry requires a name"
        unless isIdentifier name do
          planError s!"entry '{name}' is not a safe identifier"
        let rk ← resultKindOf data types callable.result.typeId s!"entry '{name}'" true
        unless rk == .unit || rk == .bool ||
            (match rk with | .aggregate _ => true | _ => false) do
          signed? ←
            noteIntegerDomain types callable.result.typeId signed? s!"entry '{name}' result"
        unless callable.result.visibility == .public_ do
          planError s!"entry '{name}' result must be public"
        for p in callable.params do
          signed? ←
            noteIntegerDomain types p.typeId signed? s!"entry '{name}' parameter '{p.name}'"
        let (params, stores, ret?) ←
          lowerCallableBody data types layout (allowStateWrite := true)
            (seedZeroState := false) signedNumeric s!"entry '{name}'" callable
        let body ← match rk, ret? with
          | .unit, none => pure stores
          | .unit, some _ =>
              planError s!"entry '{name}' Unit result must not return a value"
          | .uint64, some v | .int64, some v | .bool, some v => do
              let e ← requireScalar v s!"entry '{name}' result"
              pure (stores.push (.returnValue e))
          | .uint64, none | .int64, none | .bool, none =>
              planError s!"entry '{name}' non-Unit result is missing"
          | .aggregate n, some tv => do
              unless (isArrayValue tv || isOptionValue tv || isNamedValue tv) &&
                  tv.leaves.size == n do
                planError
                  s!"entry '{name}' aggregate return must flatten to exactly {n} leaves"
              pure (stores.push (.returnAggregate tv.leaves))
          | .aggregate _, none =>
              planError s!"entry '{name}' aggregate return is missing"
        entries := entries.push {
          name, params, mode := .mutate, resultKind := rk, body
        }
    | .view => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported ICP semantic shape: view requires a name"
        unless isIdentifier name do
          planError s!"view '{name}' is not a safe identifier"
        let rk ← resultKindOf data types callable.result.typeId s!"view '{name}'" true
        unless rk == .uint64 || rk == .int64 || rk == .bool ||
            (match rk with | .aggregate _ => true | _ => false) do
          planError s!"view '{name}' result must be UInt64, Int64, Bool, or a view-only aggregate"
        unless rk == .bool do
          signed? ←
            noteIntegerDomain types callable.result.typeId signed? s!"view '{name}' result"
        unless callable.result.visibility == .public_ do
          planError s!"view '{name}' result must be public"
        for p in callable.params do
          signed? ←
            noteIntegerDomain types p.typeId signed? s!"view '{name}' parameter '{p.name}'"
        let (params, stores, ret?) ←
          lowerCallableBody data types layout (allowStateWrite := false)
            (seedZeroState := false) signedNumeric s!"view '{name}'" callable
        unless stores.isEmpty do
          planError s!"view '{name}' cannot write state"
        let tv ← match ret? with
          | some v => pure v
          | none => planError s!"view '{name}' must return a value"
        let body ← match rk with
          | .uint64 | .int64 | .bool => do
              let e ← requireScalar tv s!"view '{name}' result"
              pure #[.returnValue e]
          | .aggregate n => do
              unless (isArrayValue tv || isOptionValue tv || isNamedValue tv) &&
                  tv.leaves.size == n do
                planError
                  s!"view '{name}' aggregate return must flatten to exactly {n} leaves"
              pure #[.returnAggregate tv.leaves]
          | .unit =>
              planError s!"view '{name}' result must be UInt64, Int64, Bool, or a view-only aggregate"
        views := views.push {
          name, params, mode := .query, resultKind := rk, body
        }
  let initializer ← match initializer? with
    | some m => pure m
    | none => planError "unsupported ICP semantic shape: ICP-2 requires exactly one initializer"
  unless entries.size > 0 || views.size > 0 do
    planError "unsupported ICP semantic shape: at least one entry or view is required"
  pure {
    programName
    sourceHash
    semanticHash
    signedNumeric := signed? == some true
    states
    initializer
    entries
    views
  }

private def makePlanFromSemanticV1
    (source : SemanticProgramV1) (artifactProgramName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  let data ← match validateSemanticProgramV1 source with
    | .ok value => pure value
    | .error _ =>
        throw <| .invalidProgram "ICP received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

/-- Internal capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .icp do
    throw <| .planInvariant .icp "engineering capability kind is not ICP"
  let selection := ResolvedEngineeringBuildV1.selectionOf capability
  unless selection.codegenProfile == codegenProfile do
    planError s!"unsupported ICP codegen profile (expected {codegenProfileString})"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "ICP source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "ICP semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

/-- Unit-test Plan entry over retained SemanticProgramV1 (no registry required). -/
def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "ICP source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "ICP semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Icp
