import ProofForgeV2.Core.Common
import ProofForgeV2.Core.RequirementIdsV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# XRPL LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Q0/Q1 XRPL Bedrock target (ADR-0049/0050): controlled Rust guest recipe
matching scaffold-xrp Counter shape (`xrpl_wasm_std`, `get_data`/`set_data`,
`#[unsafe(no_mangle)] pub extern "C"`). Public UInt64/Bool/Unit; T3 Bytes N
and Array UInt64 N flatten to N UInt64 low-8/`get_data` leaves (`name_0`…);
UInt64/Bool `Op.Constant` inline; T3–T9 language face (Bytes/Principal/named
flatten, view/entry leaf tuples, `emitRegion` if/`switchOn`/counted
`forLoop`); pureFn inline (depth ≤ 64); checked `+`/`-`/`*`/`/`/`%`;
bare assert; zero-payload declared revert. No Int64, Map/Option, Field,
events, call/schedule, ContextRead, Commit, invariants, Escrow/Vault,
Hooks, or EVM sidechain.

Failure codes (first failure wins at emission):
  overflow=1, underflow=2, divByZero=3, assertion=4,
  zero-payload declared-revert=256+canonical ErrorId
-/

namespace ProofForgeV2.Targets.Xrpl

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.RequirementIdsV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.EnvelopeV1

def codegenProfileString : String := "xrpl-bedrock-source-u64-v1"

def codegenProfile : CodegenProfileId := CodegenProfileId.xrplBedrockSourceU64V1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .xrpl message

private def xrplPlanErr (message : String) : CompileError :=
  .planInvariant .xrpl message

private def qnJoined (qn : ProofForgeV2.Core.Common.QualifiedName) : String :=
  String.intercalate "."
    (ProofForgeV2.Core.Common.NonEmptyArray.toArray qn.components).toList

private def isPfCryptoCalleeV1 (qn : String) : Bool :=
  qn.startsWith "pf.crypto."

private def isNamedUInt64ContextKey
    (key : ProofForgeV2.Core.Common.SchemaId) : Bool :=
  key == unixTimeSecondsContextKeyV1 ||
    key == blockHeightContextKeyV1 ||
    key == attachedValueContextKeyV1 ||
    key == chainIdContextKeyV1

-- ---------------------------------------------------------------------------
-- Target-owned Plan surface
-- ---------------------------------------------------------------------------

inductive ExprType where
  | uint64
  | bool
  | principal
  deriving BEq, Inhabited, Repr

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive ArithOp where
  | add | sub | mul | div | mod
  deriving BEq, Inhabited, Repr

inductive FailureKind where
  | overflow
  | underflow
  | divByZero
  | assertion
  | declaredRevert (errorIndex : Nat)
  | terminalRevert (errorIndex : Nat)
  deriving BEq, Inhabited, Repr

def FailureKind.code : FailureKind → Nat
  | .overflow => 1
  | .underflow => 2
  | .divByZero => 3
  | .assertion => 4
  | .declaredRevert errorIndex | .terminalRevert errorIndex => 256 + errorIndex

inductive Expr where
  | litU64 (value : UInt64)
  | litBool (value : Bool)
  | param (index : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- Bounded-for induction slot (T9c). -/
  | temp (index : Nat)
  | arith (op : ArithOp) (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | boolAnd (lhs rhs : Expr)
  | boolOr (lhs rhs : Expr)
  | boolNot (operand : Expr)
  deriving BEq, Inhabited, Repr

structure TypedExpr where
  ty : ExprType
  expr : Expr
  expandedNodes : Nat
  /-- Empty = scalar. Nonempty = Array/Bytes/Principal/named flatten leaves. -/
  leaves : Array Expr := #[]
  isNamed : Bool := false
  deriving BEq, Inhabited, Repr

structure Check where
  kind : FailureKind
  condition : Expr
  deriving BEq, Inhabited, Repr

/-- T9a CFG body. Straight-line entries keep `stores`+`result?` and leave
    `body` empty. Nonempty `body` is mutually exclusive with those fields. -/
inductive Statement where
  | store (fieldIndex : Nat) (value : Expr)
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  | forLoop (varTemp : Nat) (initial condition update : Expr)
      (maxIterations : Nat) (body : Array Statement)
  | returnValue (value : Expr)
  | returnNone
  | returnAggregate (leaves : Array Expr)
  deriving BEq, Inhabited, Repr

inductive ResultKind where
  | unit
  | uint64
  | bool
  /-- Flattened return (1..8 UInt64 leaves). T6 view / T7 entry. -/
  | aggregate (leafCount : Nat)
  deriving BEq, Inhabited, Repr

structure PlanState where
  name : String
  deriving BEq, Inhabited, Repr

structure PlanInit where
  name : String
  params : Array String
  stores : Array (Nat × Expr)
  deriving BEq, Inhabited, Repr

structure PlanEntry where
  actionIndex : Nat
  name : String
  params : Array String
  resultKind : ResultKind
  checks : Array Check
  stores : Array (Nat × Expr)
  result? : Option Expr
  /-- Aggregate leaves when `resultKind = .aggregate n`; empty for scalars. -/
  resultLeaves : Array Expr := #[]
  terminalRevert : Bool
  /-- Nonempty ⇒ `stores` and `result?` must be empty (T9a CFG). -/
  body : Array Statement := #[]
  deriving BEq, Inhabited, Repr

structure PlanView where
  name : String
  params : Array String
  resultKind : ResultKind
  value : Expr
  /-- Aggregate leaves when `resultKind = .aggregate n`; empty for scalars. -/
  leaves : Array Expr := #[]
  deriving BEq, Inhabited, Repr

structure Plan where
  programName : String
  sourceHash : String
  semanticHash : String
  states : Array PlanState
  initializer : Option PlanInit
  entries : Array PlanEntry
  views : Array PlanView
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Type closure (UInt64/Bool/Unit + UInt32 index + UInt8 Bytes element +
-- Array UInt64 N / Bytes N flatten; Map/Option/named/Principal stay FC)
-- ---------------------------------------------------------------------------

private def xrplTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "XRPL"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/UInt32/UInt8 widths are supported"
  unsupportedShapeDetail :=
    "only anonymous UInt64, UInt32 (index), UInt8 (Bytes element), Bool, Unit, Array UInt64 N, Bytes N (N UInt64 low-8 leaves, N in 1..8), Principal 9-leaf identity (len+w0..w7, not an XRPL AccountID), and named Struct/Enum UInt64 leaf flatten are supported (Int64/narrow Int/Field/Map/Option/String stay fail closed)"

private def pilotUintWidthPolicyU64U32U8 : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8]

private abbrev XrplTypeClosureV1 := PilotTypeClosureV1

private def validateXrplTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult XrplTypeClosureV1 :=
  validatePilotTypeClosure xrplPlanErr xrplTypeClosureWording types
    pilotUintWidthPolicyU64U32U8
    (intPolicy := pilotIntWidthPolicyNone)
    (fieldPolicy := pilotFieldPolicyNone)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayBytes)

private def maxIdentifierBytes : Nat := 200
private def maxPureInlineDepth : Nat := 64
private def maxStateFields : Nat := 64
private def maxParams : Nat := 64
private def maxBodyOps : Nat := 4096
private def maxBodyChecks : Nat := 128
private def maxExpandedExprNodes : Nat := 16384
private def maxU64Value : UInt64 := 18446744073709551615

private def checkedExprNodes (what : String) (nodes : Nat) : CompileResult Nat := do
  unless nodes ≤ maxExpandedExprNodes do
    planError s!"unsupported XRPL semantic shape: {what} expanded expression exceeds {maxExpandedExprNodes} nodes"
  pure nodes

private def binaryExprNodes (what : String) (lhs rhs : TypedExpr) : CompileResult Nat :=
  checkedExprNodes what (1 + lhs.expandedNodes + rhs.expandedNodes)

private def guardedDivModExprNodes
    (what : String) (lhs rhs : TypedExpr) : CompileResult Nat :=
  checkedExprNodes what (5 + lhs.expandedNodes + 2 * rhs.expandedNodes)

private def unaryExprNodes (what : String) (operand : TypedExpr) : CompileResult Nat :=
  checkedExprNodes what (1 + operand.expandedNodes)

private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

private def isUInt64Type (types : XrplTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  typeId == types.uint64TypeId

private def isUInt32Type (types : XrplTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 32 == some typeId

private def isUInt8Type (types : XrplTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 8 == some typeId

private def isBoolType (types : XrplTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.boolTypeId == some typeId

private def isUnitType (types : XrplTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.unitTypeId == some typeId

private def isPrincipalType (types : XrplTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.principalTypeId == some typeId

/-- T4: 9 UInt64 identity leaves (`len` + 8×UInt64 body). Not an AccountID. -/
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

private def decodePrincipalLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless bytes.size ≥ 4 do
    planError
      "unsupported XRPL semantic shape: Principal literal valueBytes too short"
  let len :=
    (bytes.get! 0).toNat + (bytes.get! 1).toNat * 256 +
      (bytes.get! 2).toNat * 65536 + (bytes.get! 3).toNat * 16777216
  unless bytes.size == 4 + len do
    planError
      "unsupported XRPL semantic shape: Principal literal valueBytes length framing mismatch"
  unless 1 ≤ len do
    planError
      "unsupported XRPL semantic shape: Principal body shorter than 1 byte"
  unless len ≤ principalMaxPayloadBytesV1 do
    planError
      s!"unsupported XRPL semantic shape: Principal longer than {principalMaxPayloadBytesV1} bytes (identity bound)"
  let payload := bytes.extract 4 bytes.size
  let mut leaves : Array Expr := #[.litU64 (UInt64.ofNat len)]
  for w in [0:principalDataWordCountV1] do
    let mut word : Nat := 0
    let mut place : Nat := 1
    for b in [0:8] do
      let idx := w * 8 + b
      let byte := if idx < payload.size then (payload.get! idx).toNat else 0
      word := word + byte * place
      place := place * 256
    leaves := leaves.push (.litU64 (UInt64.ofNat word))
  pure leaves

private def isArrayValue (v : TypedExpr) : Bool :=
  !v.leaves.isEmpty && v.ty != .principal && !v.isNamed

private def isPrincipalValue (v : TypedExpr) : Bool :=
  v.ty == .principal && v.leaves.size == principalLeafCountV1

private def isNamedValue (v : TypedExpr) : Bool :=
  v.isNamed && !v.leaves.isEmpty

private def mkArrayLeaves (leaves : Array Expr) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := leaves.size
    leaves }

private def mkPrincipalLeaves (leaves : Array Expr) : TypedExpr :=
  { ty := .principal
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := leaves.size
    leaves }

private def mkNamedLeaves (leaves : Array Expr) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := leaves.size
    leaves
    isNamed := true }

/-- Flatten named Struct/Enum into ordered leaf names. Leaves are UInt64 only. -/
private def flattenNamedLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : XrplTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) : CompileResult (Array String) := do
  if isUInt64Type types typeId then
    unless isIdentifier namePrefix do
      planError s!"state name '{namePrefix}' is not a safe identifier"
    return #[namePrefix]
  unless types.isNamedAggregate typeId do
    planError
      "unsupported XRPL semantic shape: named aggregate leaf must be UInt64 or named Struct/Enum"
  match typeDecls[typeId.toNat]? with
  | none =>
      planError
        s!"unsupported XRPL semantic shape: missing TypeDecl for aggregate {typeId}"
  | some decl =>
      match decl.shape with
      | .struct fields => do
          unless fields.size > 0 do
            planError
              "unsupported XRPL semantic shape: named Struct requires at least one field"
          let mut out : Array String := #[]
          for f in fields do
            unless isUInt64Type types f.typeId do
              planError
                "unsupported XRPL semantic shape: named Struct field must be UInt64 (nested named stay fail closed)"
            let subName :=
              if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
            unless isIdentifier subName do
              planError s!"state name '{subName}' is not a safe identifier"
            out := out.push subName
          pure out
      | .enum variants => do
          unless variants.size > 0 do
            planError
              "unsupported XRPL semantic shape: named Enum requires at least one variant"
          let tagName :=
            if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
          unless isIdentifier tagName do
            planError s!"state name '{tagName}' is not a safe identifier"
          let mut maxPay : Nat := 0
          for v in variants do
            unless v.payloadTypes.size ≤ 1 do
              planError
                "unsupported XRPL semantic shape: named Enum variant admits at most one UInt64 payload"
            for pt in v.payloadTypes do
              unless isUInt64Type types pt do
                planError
                  "unsupported XRPL semantic shape: named Enum payload must be UInt64 (nested named stay fail closed)"
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
            "unsupported XRPL semantic shape: named type must be Struct or Enum"

private def requireTy (v : TypedExpr) (expected : ExprType) (what : String) :
    CompileResult Expr := do
  unless v.leaves.isEmpty do
    planError
      s!"unsupported XRPL semantic shape: {what} cannot be an Array/Bytes/Principal aggregate"
  unless v.ty == expected do
    planError s!"unsupported XRPL semantic shape: {what} has the wrong type"
  pure v.expr

/-- CosmWasm/ICP-style Array UInt64 N / Bytes N flatten: `some n` for
    admitted 1..8; `none` for scalars. Nested/narrow/Map/N=0/N>8 fail closed. -/
private def arrayUInt64LenV1
    (typeDecls : Array TypeDeclV1) (types : XrplTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless isUInt64Type types elTid do
        planError
          "unsupported XRPL semantic shape: Array element must be UInt64 (nested/narrow arrays fail closed)"
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported XRPL semantic shape: Array UInt64 N state must be 1..8 (got {n}; cap 8 flatten)"
      pure (some n)
  | some { shape := .bytes len, .. } =>
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported XRPL semantic shape: Bytes N state must be 1..8 (got {n}; cap 8 flatten)"
      pure (some n)
  | _ =>
      planError
        "unsupported XRPL semantic shape: container TypeId is not Array UInt64 or Bytes N"

-- ---------------------------------------------------------------------------
-- State layout (public UInt64 + Array/Bytes flatten)
-- ---------------------------------------------------------------------------

private structure StateLayout where
  states : Array PlanState
  leavesOf : Array (Array Nat)
  deriving Inhabited

private def physicalLeaves
    (layout : StateLayout) (sid : StateIdV1) : CompileResult (Array Nat) := do
  match layout.leavesOf[sid.toNat]? with
  | some phys =>
      unless !phys.isEmpty do
        planError "unsupported XRPL semantic shape: state produced zero flatten leaves"
      pure phys
  | none =>
      planError "unsupported XRPL semantic shape: stateLoad/store references unknown state"

private def makeStateLayoutV1
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1) :
    CompileResult StateLayout := do
  unless data.logicalState.size ≤ maxStateFields do
    planError "unsupported XRPL semantic shape: state field count exceeds limit"
  let mut names : Array String := #[]
  let mut states : Array PlanState := #[]
  let mut leavesOf : Array (Array Nat) := #[]
  for st in data.logicalState do
    unless st.id.toNat == leavesOf.size do
      planError "unsupported XRPL semantic shape: state ids must match declaration order"
    unless isIdentifier st.name do
      planError s!"state '{st.name}' is not a safe identifier"
    if names.contains st.name then
      planError s!"state '{st.name}' is duplicated"
    names := names.push st.name
    if types.isNamedAggregate st.typeId then
      unless st.visibility == .public_ do
        planError s!"state '{st.name}' is not public UInt64"
      let leafSpecs ← flattenNamedLeafSpecsV1 data.types types st.typeId st.name
      if leafSpecs.isEmpty then
        planError s!"state '{st.name}' produced zero named-aggregate leaves"
      if states.size + leafSpecs.size > maxStateFields then
        planError "unsupported XRPL semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for leafName in leafSpecs do
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
    else if isPrincipalType types st.typeId then
      requirePublicUInt64OrInt64OrFieldOrPrincipalState xrplPlanErr types st
      if states.size + principalLeafCountV1 > maxStateFields then
        planError "unsupported XRPL semantic shape: state field count exceeds limit"
      let leafSpecs ← flattenPrincipalLeafNamesV1 st.name
      let mut leaves : Array Nat := #[]
      for leafName in leafSpecs do
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
    else
    match ← arrayUInt64LenV1 data.types types st.typeId with
    | some n =>
        if states.size + n > maxStateFields then
          planError "unsupported XRPL semantic shape: state field count exceeds limit"
        let mut leaves : Array Nat := #[]
        for i in [0:n] do
          let leafName := st.name ++ "_" ++ toString i
          unless isIdentifier leafName do
            planError s!"state name '{leafName}' is not a safe identifier"
          leaves := leaves.push states.size
          states := states.push { name := leafName }
        leavesOf := leavesOf.push leaves
    | none =>
        requirePublicUInt64State xrplPlanErr types.uint64TypeId st
        if states.size + 1 > maxStateFields then
          planError "unsupported XRPL semantic shape: state field count exceeds limit"
        let fi := states.size
        states := states.push { name := st.name }
        leavesOf := leavesOf.push #[fi]
  unless states.size ≤ maxStateFields do
    planError "unsupported XRPL semantic shape: state field count exceeds limit"
  pure { states, leavesOf }

-- ---------------------------------------------------------------------------
-- Env / overlay / body accum
-- ---------------------------------------------------------------------------

private structure ValueEnv where
  entries : Array (ValueIdV1 × TypedExpr)
  deriving Inhabited

private def envLookup (env : ValueEnv) (id : ValueIdV1) : Option TypedExpr :=
  env.entries.findSome? (fun (vid, v) => if vid == id then some v else none)

private def envInsert (env : ValueEnv) (id : ValueIdV1) (v : TypedExpr) : ValueEnv :=
  { env with entries := env.entries.push (id, v) }

private structure StateOverlay where
  entries : Array (StateIdV1 × TypedExpr)
  deriving Inhabited

private def overlayLookup (ov : StateOverlay) (sid : StateIdV1) : Option TypedExpr :=
  ov.entries.findSome? (fun (id, e) => if id == sid then some e else none)

private def overlayInsert
    (ov : StateOverlay) (sid : StateIdV1) (e : TypedExpr) : StateOverlay :=
  let withoutOld := ov.entries.filter (fun item => item.1 != sid)
  { ov with entries := withoutOld.push (sid, e) }

/-- Emit final stores in ascending **physical** field-index order. -/
private def overlayFinalStores
    (layout : StateLayout) (ov : StateOverlay) : Array (Nat × Expr) := Id.run do
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
  let mut out : Array (Nat × Expr) := #[]
  for i in [0:last.size] do
    match last[i]? with
    | some (some e) => out := out.push (i, e)
    | _ => pure ()
  pure out

/-- Map a return Expr that is exactly an overlay scalar or Array leaf back to
    `.stateLoad` of the physical field that now holds it (store-then-read). -/
private def rewriteReturnThroughOverlay
    (layout : StateLayout) (ov : StateOverlay) (e : Expr) : Expr :=
  Id.run do
    for (sid, v) in ov.entries do
      match layout.leavesOf[sid.toNat]? with
      | none => pure ()
      | some phys =>
          if !v.leaves.isEmpty then
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
  checks : Array Check
  opCount : Nat
  nextTemp : Nat := 0
  deriving Inhabited

private def emptyBodyAccum (env : ValueEnv) (overlay : StateOverlay) : BodyAccum :=
  { env, overlay, checks := #[], opCount := 0, nextTemp := 0 }

private def pushCheck (acc : BodyAccum) (ck : Check) : CompileResult BodyAccum := do
  if acc.checks.size + 1 > maxBodyChecks then
    planError s!"unsupported XRPL semantic shape: body check count exceeds {maxBodyChecks}"
  pure { acc with checks := acc.checks.push ck }

private def bumpOp (acc : BodyAccum) : CompileResult BodyAccum := do
  if acc.opCount + 1 > maxBodyOps then
    planError "unsupported XRPL semantic shape: body operation count exceeds limit"
  pure { acc with opCount := acc.opCount + 1 }

private structure CallableIndex where
  pureFns : Array (CallableIdV1 × CallableV1)

private def lookupPureFn (idx : CallableIndex) (id : CallableIdV1) : Option CallableV1 :=
  idx.pureFns.findSome? (fun (cid, c) => if cid == id then some c else none)

-- ---------------------------------------------------------------------------
-- Literal / binary / unary
-- ---------------------------------------------------------------------------

private def lowerLiteral
    (types : XrplTypeClosureV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult TypedExpr := do
  if isUInt64Type types typeId then
    let v ← decodeUInt64LiteralLe xrplPlanErr "XRPL" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt32Type types typeId then
    let v ← decodeUInt32LiteralLe xrplPlanErr "XRPL" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt8Type types typeId then
    let v ← decodeUInt8LiteralLe xrplPlanErr "XRPL" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isBoolType types typeId then
    let b ← decodeBoolLiteralBit xrplPlanErr "XRPL" valueBytes
    pure { ty := .bool, expr := .litBool b, expandedNodes := 1 }
  else if isPrincipalType types typeId then
    let leaves ← decodePrincipalLiteralLeavesV1 valueBytes
    pure (mkPrincipalLeaves leaves)
  else
    planError "unsupported XRPL semantic shape: literal type is outside UInt64/UInt32/UInt8/Bool/Principal"

private def literalIndexNatV1 (v : TypedExpr) : CompileResult Nat := do
  let e ← requireTy v .uint64 "Array/Bytes index"
  match e with
  | .litU64 n => pure n.toNat
  | _ =>
      planError
        "unsupported XRPL semantic shape: IndexGet/IndexSet requires a compile-time constant index"

private def lowerBinary
    (op : BinaryOpV1) (lhs rhs : TypedExpr) :
    CompileResult (TypedExpr × Array Check) := do
  match op with
  | .add => do
      let l ← requireTy lhs .uint64 "add lhs"
      let r ← requireTy rhs .uint64 "add rhs"
      let nodes ← binaryExprNodes "add" lhs rhs
      let e : Expr := .arith .add l r
      let _ ← checkedExprNodes "add overflow check" (nodes + 2)
      let cond : Expr := .compare .le e (.litU64 maxU64Value)
      pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
        #[{ kind := .overflow, condition := cond }])
  | .sub => do
      let l ← requireTy lhs .uint64 "sub lhs"
      let r ← requireTy rhs .uint64 "sub rhs"
      let nodes ← binaryExprNodes "sub" lhs rhs
      let e : Expr := .arith .sub l r
      let cond : Expr := .compare .ge l r
      pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
        #[{ kind := .underflow, condition := cond }])
  | .mul => do
      let l ← requireTy lhs .uint64 "mul lhs"
      let r ← requireTy rhs .uint64 "mul rhs"
      let nodes ← binaryExprNodes "mul" lhs rhs
      let e : Expr := .arith .mul l r
      let _ ← checkedExprNodes "mul overflow check" (nodes + 2)
      let cond : Expr := .compare .le e (.litU64 maxU64Value)
      pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
        #[{ kind := .overflow, condition := cond }])
  | .div => do
      let l ← requireTy lhs .uint64 "div lhs"
      let r ← requireTy rhs .uint64 "div rhs"
      let nodes ← guardedDivModExprNodes "div" lhs rhs
      let e : Expr := .arith .div l r
      let cond : Expr := .compare .ne r (.litU64 0)
      pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
        #[{ kind := .divByZero, condition := cond }])
  | .mod => do
      let l ← requireTy lhs .uint64 "mod lhs"
      let r ← requireTy rhs .uint64 "mod rhs"
      let nodes ← guardedDivModExprNodes "mod" lhs rhs
      let e : Expr := .arith .mod l r
      let cond : Expr := .compare .ne r (.litU64 0)
      pure ({ ty := .uint64, expr := e, expandedNodes := nodes },
        #[{ kind := .divByZero, condition := cond }])
  | .eq | .ne | .lt | .le | .gt | .ge => do
      if isPrincipalValue lhs && isPrincipalValue rhs then
        unless op == .eq || op == .ne do
          planError "unsupported XRPL semantic shape: Principal comparison only supports eq/ne"
        let mut acc : Expr :=
          .compare .eq lhs.leaves[0]! rhs.leaves[0]!
        for i in [1:principalLeafCountV1] do
          acc := .boolAnd acc (.compare .eq lhs.leaves[i]! rhs.leaves[i]!)
        if op == .ne then
          acc := .boolNot acc
        let nodes ← binaryExprNodes "principal comparison" lhs rhs
        return ({ ty := .bool, expr := acc, expandedNodes := nodes }, #[])
      unless lhs.ty == rhs.ty do
        planError "unsupported XRPL semantic shape: comparison operands must share a type"
      unless lhs.ty == .uint64 || lhs.ty == .bool do
        planError "unsupported XRPL semantic shape: comparison operands must be UInt64 or Bool"
      if lhs.ty == .bool && !(op == .eq || op == .ne) then
        planError "unsupported XRPL semantic shape: Bool comparison only supports eq/ne"
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
      planError "unsupported XRPL semantic shape: bitwise/shift ops are outside Q0"

private def lowerUnary (op : UnaryOpV1) (operand : TypedExpr) :
    CompileResult TypedExpr := do
  match op with
  | .not => do
      let o ← requireTy operand .bool "bool not"
      let nodes ← unaryExprNodes "bool not" operand
      pure { ty := .bool, expr := .boolNot o, expandedNodes := nodes }
  | .neg | .bitNot =>
      planError "unsupported XRPL semantic shape: unary neg/bitNot are outside Q0"

-- ---------------------------------------------------------------------------
-- Instruction walk
-- ---------------------------------------------------------------------------

mutual

private partial def lowerBlockInstructions
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1)
    (layout : StateLayout) (idx : CallableIndex) (callable : CallableV1)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (block : BlockV1) (acc0 : BodyAccum) :
    CompileResult BodyAccum := do
  let mut acc := acc0
  for instr in block.instructions do
    acc ← bumpOp acc
    match instr.op with
    | .literal typeId valueBytes => do
        let v ← lowerLiteral types typeId valueBytes
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: literal must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId v }
    | .constant constantId => do
        let some c := data.constants[constantId.toNat]? |
          planError "unsupported XRPL semantic shape: Constant references an unknown constant id"
        unless c.id == constantId do
          planError "unsupported XRPL semantic shape: Constant id does not match declaration order"
        let v ← lowerLiteral types c.typeId c.valueBytes
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: Constant must produce a value"
        | some vd =>
            unless vd.typeId == c.typeId do
              planError "unsupported XRPL semantic shape: Constant result typeId must match the declaration"
            acc := { acc with env := envInsert acc.env vd.valueId v }
    | .stateLoad stateId => do
        unless allowStateRead do
          planError "unsupported XRPL semantic shape: pureFn cannot read state"
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: stateLoad must produce a value"
        | some vd =>
            unless stateId.toNat < data.logicalState.size do
              planError "unsupported XRPL semantic shape: stateLoad references unknown state"
            let phys ← physicalLeaves layout stateId
            let value : TypedExpr :=
              match overlayLookup acc.overlay stateId with
              | some ov => ov
              | none =>
                  if phys.size == 1 then
                    { ty := .uint64
                      expr := .stateLoad phys[0]!
                      expandedNodes := 1 }
                  else if isPrincipalType types vd.typeId then
                    mkPrincipalLeaves (phys.map (fun fi => .stateLoad fi))
                  else if types.isNamedAggregate vd.typeId then
                    mkNamedLeaves (phys.map (fun fi => .stateLoad fi))
                  else
                    mkArrayLeaves (phys.map (fun fi => .stateLoad fi))
            acc := { acc with env := envInsert acc.env vd.valueId value }
    | .stateStore stateId value => do
        unless allowStateWrite do
          planError "unsupported XRPL semantic shape: StateStore is only legal in init/entry"
        let v ← match envLookup acc.env value with
          | some tv => pure tv
          | none => planError "unsupported XRPL semantic shape: stateStore value undefined"
        unless stateId.toNat < data.logicalState.size do
          planError "unsupported XRPL semantic shape: stateStore references unknown state"
        let phys ← physicalLeaves layout stateId
        if !v.leaves.isEmpty then
          unless v.leaves.size == phys.size do
            planError "unsupported XRPL semantic shape: stateStore leaf count mismatch"
        else
          unless phys.size == 1 do
            planError "unsupported XRPL semantic shape: stateStore scalar into Array/Bytes/Principal state"
          let _ ← requireTy v .uint64 "stateStore value"
        acc := { acc with overlay := overlayInsert acc.overlay stateId v }
    | .binary op lhs rhs => do
        let lv ← match envLookup acc.env lhs with
          | some v => pure v
          | none => planError "unsupported XRPL semantic shape: binary lhs undefined"
        let rv ← match envLookup acc.env rhs with
          | some v => pure v
          | none => planError "unsupported XRPL semantic shape: binary rhs undefined"
        let (tv, cks) ← lowerBinary op lv rv
        if forbidChecks && !cks.isEmpty then
          planError "unsupported XRPL semantic shape: initializer cannot contain fallible checks"
        for ck in cks do
          acc ← pushCheck acc ck
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: binary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .unary op operand => do
        let ov ← match envLookup acc.env operand with
          | some v => pure v
          | none => planError "unsupported XRPL semantic shape: unary operand undefined"
        let tv ← lowerUnary op ov
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: unary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .pureCall calleeId args => do
        if inlineDepth >= maxPureInlineDepth then
          planError "unsupported XRPL semantic shape: pureFn inline depth exceeds 64"
        let callee ← match lookupPureFn idx calleeId with
          | some c => pure c
          | none =>
              planError "unsupported XRPL semantic shape: pureCall callee is not a pureFn"
        unless callee.params.size == args.size do
          planError "unsupported XRPL semantic shape: pureCall arity mismatch"
        let mut cEnv : ValueEnv := { entries := #[] }
        for i in [0:args.size] do
          let some argId := args[i]? |
            planError "unsupported XRPL semantic shape: pureCall arg missing"
          let some p := callee.params[i]? |
            planError "unsupported XRPL semantic shape: pureCall param missing"
          let av ← match envLookup acc.env argId with
            | some v => pure v
            | none => planError "unsupported XRPL semantic shape: pureCall arg undefined"
          unless isUInt64Type types p.typeId && av.ty == .uint64 do
            planError "unsupported XRPL semantic shape: pureFn params must be public UInt64"
          cEnv := envInsert cEnv p.valueId av
        let cAcc0 : BodyAccum := emptyBodyAccum cEnv { entries := #[] }
        let (cAcc, ret?, _endedRevert) ←
          lowerInstructions data types layout idx callee
            (allowStateRead := false) (allowStateWrite := false)
            (forbidChecks := forbidChecks) (inlineDepth := inlineDepth + 1) cAcc0
        let expandedOpCount := acc.opCount + cAcc.opCount
        if expandedOpCount > maxBodyOps then
          planError "unsupported XRPL semantic shape: expanded pureFn operation count exceeds limit"
        acc := { acc with opCount := expandedOpCount }
        for ck in cAcc.checks do
          if forbidChecks then
            planError "unsupported XRPL semantic shape: initializer cannot contain fallible checks"
          let propagated :=
            match ck.kind with
            | .terminalRevert errorIndex =>
                { ck with kind := .declaredRevert errorIndex }
            | _ => ck
          acc ← pushCheck acc propagated
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: pureCall must produce a value"
        | some vd =>
            match ret? with
            | some tv => acc := { acc with env := envInsert acc.env vd.valueId tv }
            | none =>
                if isUnitType types vd.typeId then
                  pure ()
                else
                  planError "unsupported XRPL semantic shape: pureCall missing return value"
    | .assert_ condition errorId args => do
        unless errorId.isNone && args.isEmpty do
          planError "unsupported XRPL semantic shape: assert requires errorId=none and empty args"
        let c ← match envLookup acc.env condition with
          | some v => requireTy v .bool "assert condition"
          | none => planError "unsupported XRPL semantic shape: assert condition undefined"
        if forbidChecks then
          planError "unsupported XRPL semantic shape: initializer cannot contain fallible checks"
        acc ← pushCheck acc { kind := .assertion, condition := c }
    | .externalCall _effectId callee _args => do
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          planError
            s!"unsupported XRPL semantic shape: pf.crypto QN '{qn}' has no XRPL host binding (sha256/keccak256 and siblings stay fail closed)"
        planError "unsupported XRPL semantic shape: call/schedule are outside Q0"
    | .schedule _effectId callee _args => do
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          planError
            s!"unsupported XRPL semantic shape: pf.crypto QN '{qn}' has no XRPL host binding (sha256/keccak256 and siblings stay fail closed)"
        planError "unsupported XRPL semantic shape: op is outside Q0"
    | .envRead key _args =>
        if key == .nativeVaultBalance then
          planError
            s!"unsupported XRPL semantic shape: envRead nativeVaultBalance has no XRPL host binding (pf.assets.native.balanceOfSelf stays fail closed)"
        planError "unsupported XRPL semantic shape: envRead is outside Q0"
    | .contextRead key =>
        if isNamedUInt64ContextKey key then
          planError
            s!"unsupported XRPL semantic shape: ContextRead '{key.value}' has no XRPL host binding (unixTimeSeconds/blockHeight/attachedValue/chainId stay fail closed)"
        planError "unsupported XRPL semantic shape: op is outside Q0"
    | .indexGet base index => do
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: IndexGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: IndexGet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: IndexGet index undefined"
            unless isArrayValue bv do
              planError
                "unsupported XRPL semantic shape: IndexGet base must be an Array UInt64 or Bytes N aggregate"
            let i ← literalIndexNatV1 iv
            unless i < bv.leaves.size do
              planError "unsupported XRPL semantic shape: Array/Bytes IndexGet index out of range"
            let some leaf := bv.leaves[i]? |
              planError "unsupported XRPL semantic shape: Array/Bytes IndexGet leaf missing"
            acc := { acc with
              env := envInsert acc.env vd.valueId
                { ty := .uint64, expr := leaf, expandedNodes := 1 } }
    | .indexSet base index value => do
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: IndexSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: IndexSet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: IndexSet index undefined"
            let vv ← match envLookup acc.env value with
              | some v => requireTy v .uint64 "IndexSet value"
              | none => planError "unsupported XRPL semantic shape: IndexSet value undefined"
            unless isArrayValue bv do
              planError
                "unsupported XRPL semantic shape: IndexSet base must be an Array UInt64 or Bytes N aggregate"
            let i ← literalIndexNatV1 iv
            unless i < bv.leaves.size do
              planError "unsupported XRPL semantic shape: Array/Bytes IndexSet index out of range"
            let newLeaves := bv.leaves.set! i vv
            acc := { acc with
              env := envInsert acc.env vd.valueId (mkArrayLeaves newLeaves) }
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: construct must produce a value"
        | some vd =>
            if types.isNamedAggregate typeId then
              let some decl := data.types[typeId.toNat]? |
                planError "unsupported XRPL semantic shape: construct TypeDecl missing"
              match decl.shape with
              | .struct fields => do
                  unless ctorIdx.toNat == 0 do
                    planError
                      "unsupported XRPL semantic shape: struct construct ctorIdx must be 0"
                  unless argIds.size == fields.size do
                    planError
                      "unsupported XRPL semantic shape: struct construct arity mismatch"
                  let mut leafExprs : Array Expr := #[]
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "unsupported XRPL semantic shape: struct construct arg missing"
                    let some field := fields[i]? |
                      planError "unsupported XRPL semantic shape: struct construct field missing"
                    unless isUInt64Type types field.typeId do
                      planError
                        "unsupported XRPL semantic shape: named Struct field must be UInt64"
                    let av ← match envLookup acc.env argId with
                      | some v => requireTy v .uint64 "struct construct arg"
                      | none => planError "unsupported XRPL semantic shape: construct arg undefined"
                    leafExprs := leafExprs.push av
                  acc := { acc with
                    env := envInsert acc.env vd.valueId (mkNamedLeaves leafExprs) }
              | .enum variants => do
                  let vi := ctorIdx.toNat
                  let some variant := variants[vi]? |
                    planError
                      "unsupported XRPL semantic shape: enum construct variant out of range"
                  unless argIds.size == variant.payloadTypes.size do
                    planError
                      "unsupported XRPL semantic shape: enum construct arity mismatch"
                  let mut maxPay : Nat := 0
                  for v in variants do
                    if v.payloadTypes.size > maxPay then maxPay := v.payloadTypes.size
                  let mut leafExprs : Array Expr := #[.litU64 (UInt64.ofNat vi)]
                  for argId in argIds do
                    let av ← match envLookup acc.env argId with
                      | some v => requireTy v .uint64 "enum construct payload"
                      | none => planError "unsupported XRPL semantic shape: construct arg undefined"
                    leafExprs := leafExprs.push av
                  while leafExprs.size < 1 + maxPay do
                    leafExprs := leafExprs.push (.litU64 0)
                  acc := { acc with
                    env := envInsert acc.env vd.valueId (mkNamedLeaves leafExprs) }
              | _ =>
                  planError
                    "unsupported XRPL semantic shape: named construct requires Struct or Enum"
            else
              planError
                "unsupported XRPL semantic shape: construct admits only named Struct/Enum on XRPL"
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: fieldGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: fieldGet base undefined"
            unless isNamedValue bv do
              planError
                "unsupported XRPL semantic shape: fieldGet base must be a named Struct"
            let i := fieldIndex.toNat
            unless i < bv.leaves.size do
              planError "unsupported XRPL semantic shape: fieldGet leaf index out of range"
            let some leaf := bv.leaves[i]? |
              planError "unsupported XRPL semantic shape: fieldGet leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := .uint64
              expr := leaf
              expandedNodes := 1
            } }
    | .fieldSet baseId fieldIndex valueId => do
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: fieldSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: fieldSet base undefined"
            unless isNamedValue bv do
              planError
                "unsupported XRPL semantic shape: fieldSet base must be a named Struct"
            let vv ← match envLookup acc.env valueId with
              | some v => requireTy v .uint64 "fieldSet value"
              | none => planError "unsupported XRPL semantic shape: fieldSet value undefined"
            let i := fieldIndex.toNat
            unless i < bv.leaves.size do
              planError "unsupported XRPL semantic shape: fieldSet leaf index out of range"
            let newLeaves := bv.leaves.set! i vv
            acc := { acc with
              env := envInsert acc.env vd.valueId (mkNamedLeaves newLeaves) }
    | .variantTag baseId => do
        match instr.result with
        | none => planError "unsupported XRPL semantic shape: variantTag must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported XRPL semantic shape: variantTag base undefined"
            unless isNamedValue bv do
              planError
                "unsupported XRPL semantic shape: variantTag base must be a named Enum"
            let some tag := bv.leaves[0]? |
              planError "unsupported XRPL semantic shape: variantTag tag leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := .uint64
              expr := tag
              expandedNodes := 1
            } }
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none =>
            planError "unsupported XRPL semantic shape: variantPayload must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none =>
                  planError "unsupported XRPL semantic shape: variantPayload base undefined"
            unless isNamedValue bv do
              planError
                "unsupported XRPL semantic shape: variantPayload base must be a named Enum"
            if variantIndex.toNat == 0 && payloadIndex.toNat == 0 &&
                bv.leaves.size == 1 then
              planError
                "unsupported XRPL semantic shape: variantPayload of empty Enum variant is empty"
            let payloadIdx := 1 + payloadIndex.toNat
            let some payload := bv.leaves[payloadIdx]? |
              planError
                "unsupported XRPL semantic shape: variantPayload payload leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := .uint64
              expr := payload
              expandedNodes := 1
            } }
    | .checkedCast .. | .commit .. | .emit .. =>
        planError "unsupported XRPL semantic shape: op is outside Q0"
  pure acc

private partial def lowerInstructions
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1)
    (layout : StateLayout) (idx : CallableIndex) (callable : CallableV1)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (acc0 : BodyAccum) :
    CompileResult (BodyAccum × Option TypedExpr × Bool) := do
  unless callable.blocks.size == 1 do
    planError "unsupported XRPL semantic shape: each callable must have exactly one block"
  unless callable.loopBounds.isEmpty do
    planError "unsupported XRPL semantic shape: loopBounds are outside Q0"
  unless callable.entryBlock.toNat == 0 do
    planError "unsupported XRPL semantic shape: entryBlock must be 0"
  let some block := callable.blocks[0]? |
    planError "unsupported XRPL semantic shape: missing entry block"
  unless block.params.isEmpty do
    planError "unsupported XRPL semantic shape: block parameters are outside Q0"
  let mut acc ←
    lowerBlockInstructions data types layout idx callable
      allowStateRead allowStateWrite forbidChecks inlineDepth block acc0
  match block.terminator with
  | .return_ value => do
      match value with
      | none => pure (acc, none, false)
      | some vid =>
          match envLookup acc.env vid with
          | some tv =>
              let rewritten := rewriteReturnThroughOverlay layout acc.overlay tv.expr
              let rewrittenLeaves :=
                tv.leaves.map (rewriteReturnThroughOverlay layout acc.overlay)
              pure (acc, some { tv with expr := rewritten, leaves := rewrittenLeaves }, false)
          | none => planError "unsupported XRPL semantic shape: return value undefined"
  | .revert errorId args => do
      unless args.isEmpty do
        planError "unsupported XRPL semantic shape: revert requires zero-payload args"
      if forbidChecks then
        planError "unsupported XRPL semantic shape: initializer cannot contain fallible checks"
      acc ← pushCheck acc
        { kind := .terminalRevert errorId.toNat, condition := .litBool false }
      pure (acc, none, true)
  | .jump .. | .branch .. | .switch .. | .trap .. =>
      planError "unsupported XRPL semantic shape: multi-block/trap terminators are outside Q0"

end

private def seedParamEnv
    (types : XrplTypeClosureV1) (callable : CallableV1) (owner : String) :
    CompileResult (ValueEnv × Array String) := do
  let mut env : ValueEnv := { entries := #[] }
  let mut names : Array String := #[]
  let mut i : Nat := 0
  for p in callable.params do
    unless p.visibility == .public_ do
      planError s!"parameter '{p.name}' in {owner} is not public UInt64"
    unless isIdentifier p.name do
      planError s!"parameter '{p.name}' is not a safe identifier"
    if isUInt64Type types p.typeId then
      unless names.size < maxParams do
        planError "unsupported XRPL semantic shape: parameter count exceeds limit"
      env := envInsert env p.valueId {
        ty := .uint64
        expr := .param i
        expandedNodes := 1
      }
      names := names.push p.name
      i := i + 1
    else if isPrincipalType types p.typeId then
      let leafSpecs ← flattenPrincipalLeafNamesV1 p.name
      unless names.size + leafSpecs.size ≤ maxParams do
        planError "unsupported XRPL semantic shape: parameter count exceeds limit"
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        names := names.push leafName
        leafExprs := leafExprs.push (.param i)
        i := i + 1
      env := envInsert env p.valueId (mkPrincipalLeaves leafExprs)
    else
      planError s!"parameter '{p.name}' in {owner} is not public UInt64"
  pure (env, names)

private def resultKindNamedOrFc
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1)
    (typeId : TypeIdV1) (owner : String) (allowNamed : Bool) :
    CompileResult ResultKind := do
  if types.isNamedAggregate typeId then
    if allowNamed then
      let specs ← flattenNamedLeafSpecsV1 data.types types typeId ""
      let n := specs.size
      unless 1 ≤ n && n ≤ 8 do
        planError s!"{owner} aggregate return must have 1..8 leaves (got {n})"
      pure (.aggregate n)
    else
      planError s!"{owner} named Struct/Enum return is outside this XRPL slice"
  else planError s!"{owner} result must be public Unit, UInt64, or Bool"

private def resultKindOf
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1)
    (typeId : TypeIdV1) (owner : String)
    (allowNamed : Bool) (allowBytes : Bool) :
    CompileResult ResultKind := do
  if isUnitType types typeId then pure .unit
  else if isUInt64Type types typeId then pure .uint64
  else if isBoolType types typeId then pure .bool
  else if allowBytes then
    match data.types[typeId.toNat]? with
    | some { shape := .bytes len, name := none, .. } => do
        unless owner.startsWith "view " do
          planError
            s!"{owner} Bytes return is outside this XRPL slice (only Bytes N view flattens; entry stays fail closed)"
        let n := len.toNat
        unless 1 ≤ n && n ≤ 8 do
          planError s!"{owner} Bytes N return must be 1..8 (got {n})"
        pure (.aggregate n)
    | _ =>
        resultKindNamedOrFc data types typeId owner allowNamed
  else
    resultKindNamedOrFc data types typeId owner allowNamed

private def decodeSwitchCaseValue
    (types : XrplTypeClosureV1) (typeId : TypeIdV1) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if isBoolType types typeId then
    let b ← decodeBoolLiteralBit xrplPlanErr "XRPL" bytes
    pure (if b then 1 else 0)
  else if isUInt32Type types typeId then
    decodeUInt32LiteralLe xrplPlanErr "XRPL" bytes
  else if isUInt64Type types typeId then
    decodeUInt64LiteralLe xrplPlanErr "XRPL" bytes
  else
    planError
      "unsupported XRPL semantic shape: switch case type is outside UInt64/UInt32/Bool"

private inductive RegionCont where
  | join (blockId : Nat)
  | closed
  | latch (update : Expr)
  deriving BEq, Inhabited

private def findLoopBoundV1 (loopBounds : Array LoopBoundV1) (headerId : Nat) :
    Option LoopBoundV1 :=
  loopBounds.find? (fun lb => lb.header.toNat == headerId)

private def isLoopHeaderV1 (loopBounds : Array LoopBoundV1) (blockId : Nat) : Bool :=
  (findLoopBoundV1 loopBounds blockId).isSome

private def joinOf : RegionCont → Option Nat
  | .join j => some j
  | .closed | .latch _ => none

private def validateCallableLoopsV1
    (types : XrplTypeClosureV1) (callable : CallableV1) : CompileResult Unit := do
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless block.params.size == 1 do
        planError
          "unsupported XRPL semantic shape: loop header must carry exactly one block param"
      let some p := block.params[0]? |
        planError
          "unsupported XRPL semantic shape: loop header must carry exactly one block param"
      unless isUInt64Type types p.typeId do
        planError
          "unsupported XRPL semantic shape: loop induction must be public UInt64"
      unless isLoopHeaderV1 callable.loopBounds block.id.toNat do
        planError
          "unsupported XRPL semantic shape: block parameters require a loopBounds header entry"
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      planError "unsupported XRPL semantic shape: loopBounds header is out of range"
    unless header.params.size == 1 do
      planError
        "unsupported XRPL semantic shape: loopBounds header must have one block param"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      planError
        "unsupported XRPL semantic shape: loopBounds backEdgeFrom is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          planError
            "unsupported XRPL semantic shape: loop latch must jump to its header with one arg"
    | _ =>
        planError
          "unsupported XRPL semantic shape: loop latch terminator must be a jump"
    unless lb.maxIterations.toNat ≤ 4096 do
      planError
        "unsupported XRPL semantic shape: loop maxIterations exceeds the wire ceiling"

private def flushRegion
    (layout : StateLayout) (acc : BodyAccum) : Array Statement × BodyAccum :=
  let stores := overlayFinalStores layout acc.overlay
  let stmts := stores.map (fun (i, e) => Statement.store i e)
  (stmts, { acc with overlay := { entries := #[] } })

private def lookupReturn
    (acc : BodyAccum) (value : Option ValueIdV1) :
    CompileResult (Option TypedExpr) := do
  match value with
  | none => pure none
  | some vid =>
      match envLookup acc.env vid with
      | some tv => pure (some tv)
      | none => planError "unsupported XRPL semantic shape: return value undefined"

private def returnStmts (ret? : Option TypedExpr) : Array Statement :=
  match ret? with
  | none => #[.returnNone]
  | some tv =>
      if !tv.leaves.isEmpty then #[.returnAggregate tv.leaves]
      else #[.returnValue tv.expr]

private partial def emitRegion
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1)
    (layout : StateLayout)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (enclosingHeader : Option Nat)
    (fuel : Nat) (blockId : Nat) (acc0 : BodyAccum) :
    CompileResult (Array Statement × BodyAccum × RegionCont) := do
  match fuel with
  | 0 =>
      planError "unsupported XRPL semantic shape: CFG walk fuel exhausted"
  | fuel' + 1 => do
      let some block := callable.blocks[blockId]? |
        planError "unsupported XRPL semantic shape: missing CFG block"
      unless block.id.toNat == blockId do
        planError "unsupported XRPL semantic shape: block id must match index"
      let acc ←
        lowerBlockInstructions data types layout idx callable
          allowStateRead allowStateWrite forbidChecks inlineDepth block acc0
      match block.terminator with
      | .return_ value => do
          let (stmts, acc) := flushRegion layout acc
          let ret? ← lookupReturn acc value
          pure (stmts ++ returnStmts ret?, acc, .closed)
      | .revert .. =>
          planError
            "unsupported XRPL semantic shape: revert in CFG arms is outside this slice"
      | .trap .. =>
          planError "unsupported XRPL semantic shape: trap terminators are outside Q0"
      | .jump target => do
          let targetId := target.blockId.toNat
          if enclosingHeader == some targetId then
            unless target.args.size == 1 do
              planError
                "unsupported XRPL semantic shape: loop latch must carry exactly one induction arg"
            let (stmts, acc) := flushRegion layout acc
            let some updateVid := target.args[0]? |
              planError
                "unsupported XRPL semantic shape: loop latch must carry exactly one induction arg"
            let update ← match envLookup acc.env updateVid with
              | some v => requireTy v .uint64 "loop update"
              | none =>
                  planError "unsupported XRPL semantic shape: loop update undefined"
            pure (stmts, acc, .latch update)
          else if isLoopHeaderV1 callable.loopBounds targetId then
            let some lb := findLoopBoundV1 callable.loopBounds targetId |
              planError "unsupported XRPL semantic shape: missing loopBounds for loop header"
            unless target.args.size == 1 do
              planError
                "unsupported XRPL semantic shape: loop pre-header must jump with one start arg"
            let (preStmts, acc) := flushRegion layout acc
            let some startVid := target.args[0]? |
              planError
                "unsupported XRPL semantic shape: loop pre-header must jump with one start arg"
            let initial ← match envLookup acc.env startVid with
              | some v => requireTy v .uint64 "loop start"
              | none =>
                  planError "unsupported XRPL semantic shape: loop start value undefined"
            let some header := callable.blocks[targetId]? |
              planError "unsupported XRPL semantic shape: loop header block is missing"
            unless header.params.size == 1 do
              planError
                "unsupported XRPL semantic shape: loop header must carry exactly one block param"
            let some inductionParam := header.params[0]? |
              planError
                "unsupported XRPL semantic shape: loop header must carry exactly one block param"
            let varTemp := acc.nextTemp
            let acc :=
              { acc with
                nextTemp := acc.nextTemp + 1
                env := envInsert acc.env inductionParam.valueId {
                  ty := .uint64
                  expr := .temp varTemp
                  expandedNodes := 1
                } }
            let acc ←
              lowerBlockInstructions data types layout idx callable
                allowStateRead allowStateWrite forbidChecks inlineDepth header acc
            unless acc.overlay.entries.isEmpty do
              planError
                "unsupported XRPL semantic shape: loop header may not contain effect instructions"
            match header.terminator with
            | .branch condId thenT elseT => do
                unless thenT.args.isEmpty && elseT.args.isEmpty do
                  planError
                    "unsupported XRPL semantic shape: loop branch targets must carry empty args"
                let cond ← match envLookup acc.env condId with
                  | some v => requireTy v .bool "loop condition"
                  | none =>
                      planError
                        "unsupported XRPL semantic shape: loop condition undefined"
                let (bodyStmts, acc1, bodyCont) ←
                  emitRegion data types idx callable layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    (some targetId) fuel' thenT.blockId.toNat acc
                let update ← match bodyCont with
                  | .latch e => pure e
                  | .closed =>
                      planError
                        "unsupported XRPL semantic shape: loop body closed without a latch"
                  | .join _ =>
                      planError
                        "unsupported XRPL semantic shape: loop body must end at its latch jump"
                let forStmt :=
                  Statement.forLoop varTemp initial cond update
                    lb.maxIterations.toNat bodyStmts
                let (rest, acc2, restCont) ←
                  emitRegion data types idx callable layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' elseT.blockId.toNat acc1
                pure (preStmts ++ #[forStmt] ++ rest, acc2, restCont)
            | _ =>
                planError
                  "unsupported XRPL semantic shape: loop header terminator must be a branch"
          else
            unless target.args.isEmpty do
              planError
                "unsupported XRPL semantic shape: jump args / block-param phi are outside Q0"
            let (stmts, acc) := flushRegion layout acc
            pure (stmts, acc, .join targetId)
      | .branch condId thenT elseT => do
          unless thenT.args.isEmpty && elseT.args.isEmpty do
            planError
              "unsupported XRPL semantic shape: branch targets must carry empty args"
          let cond ← match envLookup acc.env condId with
            | some v => requireTy v .bool "branch condition"
            | none =>
                planError "unsupported XRPL semantic shape: branch condition undefined"
          let (preStmts, acc) := flushRegion layout acc
          let (thenStmts, acc1, thenCont) ←
            emitRegion data types idx callable layout
              allowStateRead allowStateWrite forbidChecks inlineDepth
              enclosingHeader fuel' thenT.blockId.toNat acc
          match thenCont with
          | .latch _ =>
              planError
                "unsupported XRPL semantic shape: latch jump is only valid as a loop body end"
          | .closed | .join _ => pure ()
          let thenJoin := joinOf thenCont
          if thenJoin == some elseT.blockId.toNat then
            let (rest, acc2, restCont) ←
              emitRegion data types idx callable layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' elseT.blockId.toNat acc1
            pure
              (preStmts ++ #[.ifThenElse cond thenStmts #[]] ++ rest,
                acc2, restCont)
          else
            let (elseStmts, acc2, elseCont) ←
              emitRegion data types idx callable layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' elseT.blockId.toNat acc1
            match elseCont with
            | .latch _ =>
                planError
                  "unsupported XRPL semantic shape: latch jump is only valid as a loop body end"
            | .closed | .join _ => pure ()
            let elseJoin := joinOf elseCont
            match thenJoin, elseJoin with
            | some j1, some j2 => do
                unless j1 == j2 do
                  planError
                    "unsupported XRPL semantic shape: branch arms converge on divergent joins"
                let (rest, acc3, restCont) ←
                  emitRegion data types idx callable layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' j1 acc2
                pure
                  (preStmts ++ #[.ifThenElse cond thenStmts elseStmts] ++ rest,
                    acc3, restCont)
            | none, none =>
                pure
                  (preStmts ++ #[.ifThenElse cond thenStmts elseStmts],
                    acc2, .closed)
            | some j, none | none, some j => do
                let (rest, acc3, restCont) ←
                  emitRegion data types idx callable layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' j acc2
                pure
                  (preStmts ++ #[.ifThenElse cond thenStmts elseStmts] ++ rest,
                    acc3, restCont)
      | .switch scrutId cases defaultTarget => do
          let some defaultT := defaultTarget |
            planError
              "unsupported XRPL semantic shape: switch must carry a default target"
          unless !cases.isEmpty do
            planError "unsupported XRPL semantic shape: switch cases must be nonempty"
          let scrut ← match envLookup acc.env scrutId with
            | some v =>
                if !v.leaves.isEmpty then
                  planError "unsupported XRPL semantic shape: switch scrutinee must be scalar"
                else
                  pure v.expr
            | none =>
                planError "unsupported XRPL semantic shape: switch scrutinee undefined"
          unless defaultT.args.isEmpty do
            planError
              "unsupported XRPL semantic shape: switch default args / block-param phi are outside Q0"
          let (preStmts, acc) := flushRegion layout acc
          let mut caseBodies : Array (UInt64 × Array Statement) := #[]
          let mut accA := acc
          let mut joinAcc : Option Nat := none
          for switchCase in cases do
            unless switchCase.target.args.isEmpty do
              planError
                "unsupported XRPL semantic shape: switch case args / block-param phi are outside Q0"
            let caseValue ←
              decodeSwitchCaseValue types switchCase.typeId switchCase.valueBytes
            let (body, acc1, armCont) ←
              emitRegion data types idx callable layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' switchCase.target.blockId.toNat accA
            caseBodies := caseBodies.push (caseValue, body)
            accA := acc1
            match armCont, joinAcc with
            | .closed, _ => pure ()
            | .latch _, _ =>
                planError
                  "unsupported XRPL semantic shape: latch jump is only valid as a loop body end"
            | .join j, none => joinAcc := some j
            | .join j, some j0 =>
                unless j == j0 do
                  planError
                    "unsupported XRPL semantic shape: switch arms converge on divergent joins"
          let (defaultBody, acc2, defaultCont) ←
            emitRegion data types idx callable layout
              allowStateRead allowStateWrite forbidChecks inlineDepth
              enclosingHeader fuel' defaultT.blockId.toNat accA
          match defaultCont, joinAcc with
          | .closed, _ => pure ()
          | .latch _, _ =>
              planError
                "unsupported XRPL semantic shape: latch jump is only valid as a loop body end"
          | .join j, none => joinAcc := some j
          | .join j, some j0 =>
              unless j == j0 do
                planError
                  "unsupported XRPL semantic shape: switch arms converge on divergent joins"
          let switchStmt := Statement.switchOn scrut caseBodies defaultBody
          match joinAcc with
          | none =>
              pure (preStmts.push switchStmt, acc2, .closed)
          | some j => do
              let (rest, acc3, restCont) ←
                emitRegion data types idx callable layout
                  allowStateRead allowStateWrite forbidChecks inlineDepth
                  enclosingHeader fuel' j acc2
              pure (preStmts.push switchStmt ++ rest, acc3, restCont)

private def lowerCallableBody
    (data : SemanticProgramDataV1) (types : XrplTypeClosureV1)
    (layout : StateLayout) (idx : CallableIndex) (callable : CallableV1)
    (allowStateRead allowStateWrite forbidChecks initialStateDefaults : Bool)
    (owner : String) :
    CompileResult
      (Array String × Array Check × Array (Nat × Expr) ×
        Option TypedExpr × Bool × Array Statement) := do
  let (env0, paramNames) ← seedParamEnv types callable owner
  let mut overlay0 : StateOverlay := { entries := #[] }
  if initialStateDefaults then
    for st in data.logicalState do
      let phys ← physicalLeaves layout st.id
      if phys.size == 1 then
        overlay0 := overlayInsert overlay0 st.id {
          ty := .uint64
          expr := .litU64 0
          expandedNodes := 1
        }
      else if isPrincipalType types st.typeId then
        overlay0 := overlayInsert overlay0 st.id
          (mkPrincipalLeaves (phys.map (fun _ => .litU64 0)))
      else if types.isNamedAggregate st.typeId then
        overlay0 := overlayInsert overlay0 st.id
          (mkNamedLeaves (phys.map (fun _ => .litU64 0)))
      else
        overlay0 := overlayInsert overlay0 st.id
          (mkArrayLeaves (phys.map (fun _ => .litU64 0)))
  let acc0 : BodyAccum := emptyBodyAccum env0 overlay0
  if callable.blocks.size == 1 then
    let (acc, ret?, endedRevert) ←
      lowerInstructions data types layout idx callable
        allowStateRead allowStateWrite forbidChecks 0 acc0
    let stores := overlayFinalStores layout acc.overlay
    pure (paramNames, acc.checks, stores, ret?, endedRevert, #[])
  else
    unless callable.entryBlock.toNat == 0 do
      planError "unsupported XRPL semantic shape: entryBlock must be 0"
    unless callable.loopBounds.isEmpty do
      validateCallableLoopsV1 types callable
    let (stmts, acc, cont) ←
      emitRegion data types idx callable layout
        allowStateRead allowStateWrite forbidChecks 0 none
        callable.blocks.size callable.entryBlock.toNat acc0
    unless cont == .closed do
      planError "unsupported XRPL semantic shape: CFG walk ended without a return"
    pure (paramNames, acc.checks, #[], none, false, stmts)

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  unless isIdentifier programName do
    planError s!"program name '{programName}' is not a safe identifier"
  unless data.events.isEmpty do
    planError "unsupported XRPL semantic shape: events table must be empty"
  unless data.invariants.isEmpty do
    planError "unsupported XRPL semantic shape: invariants are outside Q0"
  for err in data.errors do
    unless err.fields.isEmpty do
      planError "unsupported XRPL semantic shape: declared errors must have zero payload fields"
  let types ← validateXrplTypeClosureV1 data.types
  for c in data.constants do
    unless isUInt64Type types c.typeId || isBoolType types c.typeId do
      planError
        "unsupported XRPL semantic shape: constant is not admitted UInt64/Bool"
    let _ ← lowerLiteral types c.typeId c.valueBytes
  let layout ← makeStateLayoutV1 data types
  let states := layout.states
  let mut pureFns : Array (CallableIdV1 × CallableV1) := #[]
  for c in data.callables do
    if c.kind == .pureFn then
      pureFns := pureFns.push (c.id, c)
  let idx : CallableIndex := { pureFns }
  let mut initializer : Option PlanInit := none
  let mut entries : Array PlanEntry := #[]
  let mut views : Array PlanView := #[]
  let mut entryActionIndex : Nat := 0
  for callable in data.callables do
    match callable.kind with
    | .pureFn => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported XRPL semantic shape: pureFn requires a name"
        unless isIdentifier name do
          planError s!"pureFn '{name}' is not a safe identifier"
        let rk ← resultKindOf data types callable.result.typeId s!"pureFn '{name}'"
          (allowNamed := false) (allowBytes := false)
        unless callable.result.visibility == .public_ do
          planError s!"pureFn '{name}' result must be public"
        let (_params, _checks, stores, ret?, endedRevert, body) ←
          lowerCallableBody data types layout idx callable
            (allowStateRead := false) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false) s!"pureFn '{name}'"
        unless stores.isEmpty do
          planError s!"pureFn '{name}' cannot write state"
        unless body.isEmpty do
          planError s!"pureFn '{name}' CFG body is outside this XRPL slice"
        match rk, ret?, endedRevert with
        | .unit, none, _ => pure ()
        | .unit, some _, _ =>
            planError s!"pureFn '{name}' Unit result must not return a value"
        | .uint64, some tv, false =>
            let _ ← requireTy tv .uint64 s!"pureFn '{name}' result"
            pure ()
        | .bool, some tv, false =>
            let _ ← requireTy tv .bool s!"pureFn '{name}' result"
            pure ()
        | .uint64, none, true | .bool, none, true =>
            planError s!"pureFn '{name}' non-Unit revert-only result is outside Q0"
        | .uint64, none, false | .bool, none, false =>
            planError s!"pureFn '{name}' non-Unit return is missing"
        | .uint64, some _, true | .bool, some _, true =>
            planError s!"pureFn '{name}' revert path cannot carry a return value"
        | .aggregate _, _, _ =>
            planError s!"pureFn '{name}' aggregate return is outside this XRPL slice"
    | .initializer => do
        unless initializer.isNone do
          planError "unsupported XRPL semantic shape: at most one initializer"
        let name := callable.name.getD "initialize"
        unless isIdentifier name do
          planError s!"initializer name '{name}' is not a safe identifier"
        unless isUnitType types callable.result.typeId do
          planError "unsupported XRPL semantic shape: initializer result must be Unit"
        unless callable.result.visibility == .public_ do
          planError "unsupported XRPL semantic shape: initializer result must be public"
        let (params, checks, stores, ret?, endedRevert, body) ←
          lowerCallableBody data types layout idx callable
            (allowStateRead := true) (allowStateWrite := true) (forbidChecks := true)
            (initialStateDefaults := true) "initializer"
        if endedRevert then
          planError "unsupported XRPL semantic shape: initializer cannot revert"
        unless checks.isEmpty do
          planError "unsupported XRPL semantic shape: initializer cannot contain fallible checks"
        unless ret?.isNone do
          planError "unsupported XRPL semantic shape: initializer must return Unit"
        unless body.isEmpty do
          planError "unsupported XRPL semantic shape: initializer CFG body is outside this slice"
        initializer := some { name, params, stores }
    | .entry => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported XRPL semantic shape: entry requires a name"
        unless isIdentifier name do
          planError s!"entry '{name}' is not a safe identifier"
        let rk ← resultKindOf data types callable.result.typeId s!"entry '{name}'"
          (allowNamed := true) (allowBytes := false)
        unless callable.result.visibility == .public_ do
          planError s!"entry '{name}' result must be public"
        let (params, checks, stores, ret?, endedRevert, body) ←
          lowerCallableBody data types layout idx callable
            (allowStateRead := true) (allowStateWrite := true) (forbidChecks := false)
            (initialStateDefaults := false) s!"entry '{name}'"
        if !body.isEmpty then
          entryActionIndex := entryActionIndex + 1
          entries := entries.push {
            actionIndex := entryActionIndex
            name, params, resultKind := rk, checks, stores := #[]
            result? := none, resultLeaves := #[], terminalRevert := endedRevert
            body
          }
        else do
        let (result?, resultLeaves) ← match rk, ret?, endedRevert with
          | .unit, none, _ => pure (none, #[])
          | .unit, some _, _ =>
              planError s!"entry '{name}' Unit result must not return a value"
          | .uint64, some tv, false =>
              let e ← requireTy tv .uint64 s!"entry '{name}' result"
              pure (some e, #[])
          | .bool, some tv, false =>
              let e ← requireTy tv .bool s!"entry '{name}' result"
              pure (some e, #[])
          | .uint64, none, true | .bool, none, true =>
              pure (none, #[])
          | .uint64, none, false | .bool, none, false =>
              planError s!"entry '{name}' non-Unit return is missing"
          | .uint64, some _, true | .bool, some _, true =>
              planError s!"entry '{name}' revert path cannot carry a return value"
          | .aggregate n, some tv, false => do
              unless tv.leaves.size == n do
                planError
                  s!"entry '{name}' aggregate return must flatten to exactly {n} leaves"
              unless checks.isEmpty do
                planError
                  s!"entry '{name}' aggregate return cannot contain fallible checks"
              unless !tv.leaves.isEmpty do
                planError s!"entry '{name}' aggregate return is empty"
              pure (tv.leaves[0]?, tv.leaves)
          | .aggregate _, none, true =>
              planError s!"entry '{name}' revert path cannot carry an aggregate return"
          | .aggregate _, some _, true =>
              planError s!"entry '{name}' revert path cannot carry an aggregate return"
          | .aggregate _, none, false =>
              planError s!"entry '{name}' aggregate return is missing"
        entryActionIndex := entryActionIndex + 1
        entries := entries.push {
          actionIndex := entryActionIndex
          name, params, resultKind := rk, checks, stores, result?
          resultLeaves
          terminalRevert := endedRevert
        }
    | .view => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported XRPL semantic shape: view requires a name"
        unless isIdentifier name do
          planError s!"view '{name}' is not a safe identifier"
        let rk ← resultKindOf data types callable.result.typeId s!"view '{name}'"
          (allowNamed := true) (allowBytes := true)
        unless rk != .unit do
          planError s!"view '{name}' result must be UInt64, Bool, or a view-only aggregate"
        unless callable.result.visibility == .public_ do
          planError s!"view '{name}' result must be public"
        let (params, checks, stores, ret?, endedRevert, body) ←
          lowerCallableBody data types layout idx callable
            (allowStateRead := true) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false) s!"view '{name}'"
        if endedRevert then
          planError s!"view '{name}' cannot revert"
        unless stores.isEmpty do
          planError s!"view '{name}' cannot write state"
        unless body.isEmpty do
          planError s!"view '{name}' CFG body is outside this XRPL slice"
        unless checks.isEmpty do
          planError s!"view '{name}' cannot contain assert/revert/fallible checks (pure def only)"
        let tv ← match ret? with
          | some v => pure v
          | none => planError s!"view '{name}' must return a value"
        let (value, leaves) ← match rk with
          | .uint64 => do
              let e ← requireTy tv .uint64 s!"view '{name}' result"
              pure (e, #[])
          | .bool => do
              let e ← requireTy tv .bool s!"view '{name}' result"
              pure (e, #[])
          | .aggregate n => do
              unless tv.leaves.size == n do
                planError
                  s!"view '{name}' aggregate return must flatten to exactly {n} leaves"
              unless !tv.leaves.isEmpty do
                planError s!"view '{name}' aggregate return is empty"
              pure (tv.leaves[0]!, tv.leaves)
          | .unit => planError s!"view '{name}' result must be UInt64, Bool, or a view-only aggregate"
        views := views.push { name, params, resultKind := rk, value, leaves }
    | .invariant =>
        planError "unsupported XRPL semantic shape: invariants are outside Q0"
  unless entries.size > 0 do
    planError "unsupported XRPL semantic shape: at least one entry is required"
  pure {
    programName
    sourceHash
    semanticHash
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
        throw <| .invalidProgram "XRPL received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

def materializePlanFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .xrpl do
    throw <| .planInvariant .xrpl "engineering capability kind is not XRPL"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "XRPL source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "XRPL semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "XRPL source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "XRPL semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Xrpl
