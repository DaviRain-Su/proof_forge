import ProofForgeV2.Core.Common
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1

/-!
# Soroban LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

S0 source-only Soroban target: public homogeneous UInt64 or Int64
state/params, public Unit/UInt64/Int64/Bool results, single-block
callables, pureFn inline (depth ≤ 64). Anonymous `Array UInt64 N`
(N=1..8) **state** flattens to N UInt64 Plan leaves `{name}_0`..
`{name}_{N-1}` (instance `symbol_short!` keys; no Vec). Anonymous
`Option UInt64` **state** flattens to two instance `u64` keys
`{name}_tag` + `{name}_p0` (tag 0=none / 1=some; none zeros payload).
Anonymous `Map UInt64 UInt64` **state** flattens to 24 instance `u64`
keys (cap-8 × occ/key/val interleaved; `Map.empty` + IndexSet upsert;
IndexGet → Option tag+payload). Array/Option/Map + signedNumeric,
Array/Option/Map param/return, N=0/N>8, non-UInt64 element/payload/key,
non-literal Array/Bytes index, nested arrays/Option/Map, and leaf
names that exceed the `symbol_short!` 9-byte limit fail closed (never
truncated). Anonymous `Bytes N` (N=1..8) **state** flattens to N unsigned
UInt64 leaves storing the low 8 bits; IndexGet/Set reuse the Array
literal-index path. Plan is target-owned and retains no Semantic carrier.

Language subset (fail closed otherwise):
- anonymous UInt64/Int64/Bool/Unit; public homogeneous UInt64 or Int64
  state/params (mixing fail closed; unused interned UInt64 type-table
  row does not force mixed)
- Array UInt64 N state flatten (N=1..8); Option UInt64 2-leaf state
  (construct none/some); Map UInt64 UInt64 cap-8 flatten (`Map.empty`
  + IndexSet); UInt32 admitted only as the Normalize Array-index intern
  (not a state/param width); UInt256 admitted only as
  `pf.crypto.sha256` operand/result plumbing (4×u64 LE limbs)
- init/entry/view/pureFn; single-block only
- literal, state load/store, checked UInt64/Int64 arith (+-*/%), compare,
  bool and/or/not, ite mux, pureCall inline ≤ 64, bare assert,
  zero-payload revert
- REJECT: nonempty invariants, constants, events, call/schedule,
  residual ContextRead (`caller`/`self`/`attachedValue`/`chainId`),
  Commit, Int8/16/32 state/params, Bytes, nonempty Map construct,
  Array/Option/Map return/params, Field/Principal/String, emit,
  UInt256 state/param/result/arith, `pf.crypto.keccak256` and sibling QNs
  CAP-3 admits `context.unixTimeSeconds` / `context.blockHeight` as
  source-only `env.ledger()` reads on init/entry/view (every S0
  contract fn already receives `env: Env`; ledger is invocation-wide).
  CAP-4 admits exact `pf.crypto.sha256` on init/entry as
  `env.crypto().sha256` over Semantic UInt256 LE valueBytes.
  CAP-X-BYTES-SOR admits exact `pf.crypto.sha256Bytes` on init/entry
  as `env.crypto().sha256` over S0-flattened `Bytes N` (N=1..8
  UInt64 low-8 leaves → `Bytes::from_array`; independent Plan site).
-/

namespace ProofForgeV2.Targets.Soroban

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.EnvelopeV1

def codegenProfileString : String := "soroban-source-u64-v1"

def codegenProfile : CodegenProfileId := CodegenProfileId.sorobanSourceU64V1

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .soroban message

private def sorobanPlanErr (message : String) : CompileError :=
  .planInvariant .soroban message

private def qnJoined (qn : ProofForgeV2.Core.Common.QualifiedName) : String :=
  String.intercalate "."
    (ProofForgeV2.Core.Common.NonEmptyArray.toArray qn.components).toList

/-- CAP-4 / CAP-D-SOR-LEDGER: reserve the whole `pf.crypto.*` namespace.
    Only the exact sha256 leaf is admitted; keccak256 and siblings keep
    the named host-binding fail-closed diagnostic. -/
private def isPfCryptoCalleeV1 (qn : String) : Bool :=
  qn.startsWith "pf.crypto."

private def isPfCryptoSha256CalleeV1 (qn : String) : Bool :=
  qn == "pf.crypto.sha256"

private def isPfCryptoSha256BytesCalleeV1 (qn : String) : Bool :=
  qn == "pf.crypto.sha256Bytes"

/-- S0 Bytes flatten / `Bytes::from_array(&[u8; N])` honesty cap. -/
private def maxSha256BytesLenV1 : Nat := 8

private def uint256PlumbingFc (owner : String) : String :=
  s!"unsupported Soroban semantic shape: UInt256 is admitted only as pf.crypto.sha256 operand/result plumbing ({owner} stay fail closed)"

/-- ADR-0031 S4 residual after CAP-3 / CAP-D-SOR-LEDGER: attachedValue and
    chainId still have no Soroban host. `unixTimeSeconds` binds
    `env.ledger().timestamp()`; `blockHeight` binds `env.ledger().sequence()`
    (u32 widened to u64 in emitted Rust). `context.caller` / `context.self`
    are Principal; S0 rejects Principal at type closure, so those keys stay
    on the generic ContextRead envelope below. -/
private def isUnboundUInt64ContextKey
    (key : ProofForgeV2.Core.Common.SchemaId) : Bool :=
  key == attachedValueContextKeyV1 ||
    key == chainIdContextKeyV1

-- ---------------------------------------------------------------------------
-- Target-owned Plan surface
-- ---------------------------------------------------------------------------

inductive ExprType where
  | uint64
  | int64
  | bool
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
  /-- CAP-3: `env.ledger().timestamp()` — u64 Unix seconds. Admitted on
      init/entry/view (and inlined pureFn) because every S0 contract fn
      receives `env: Env` and ledger reads are invocation-wide. -/
  | unixTimeSeconds
  /-- CAP-3: `env.ledger().sequence()` — u32 ledger sequence, widened to
      u64 in emitted Rust (`u64::from`). Same invocation policy. -/
  | blockHeight
  /-- CAP-4: one LE u64 limb of a recorded `pf.crypto.sha256` site.
      `limbIndex` is 0=low .. 3=high, matching Semantic UInt256 valueBytes. -/
  | sha256Limb (siteIndex limbIndex : Nat)
  /-- Bounded-for induction slot (T9c). -/
  | temp (index : Nat)
  | arith (op : ArithOp) (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | boolAnd (lhs rhs : Expr)
  | boolOr (lhs rhs : Expr)
  | boolNot (operand : Expr)
  /-- Dense Map mux: `if cond then t else e`. Cond is Bool; t/e share a type. -/
  | ite (cond t e : Expr)
  /-- CAP-X-BYTES-SOR: one LE u64 limb of a recorded `pf.crypto.sha256Bytes`
      site. Appended so CAP-4 `sha256Limb` ctor index stays 6.
      `limbIndex` is 0=low .. 3=high, matching Semantic UInt256 LE image. -/
  | sha256BytesLimb (siteIndex limbIndex : Nat)
  deriving BEq, Inhabited, Repr

structure TypedExpr where
  ty : ExprType
  expr : Expr
  expandedNodes : Nat
  /-- Nonempty = flattened `Array UInt64 N` or `Option UInt64` leaves.
      Empty = scalar. -/
  leaves : Array Expr := #[]
  /-- True when `leaves` is Option tag+payload (`[tag, p0]`). -/
  isOption : Bool := false
  /-- True when `leaves` is dense Map UInt64 cap-8 (24 occ/key/val). -/
  isMap : Bool := false
  /-- True when `leaves` is Principal 9-leaf wire identity. -/
  isPrincipal : Bool := false
  /-- True when `leaves` is a named Struct/Enum flatten. -/
  isNamed : Bool := false
  /-- True when `leaves` is CAP-4 UInt256 sha256 plumbing (4 LE u64 limbs). -/
  isUInt256 : Bool := false
  /-- True when `leaves` is S0 `Bytes N` (N UInt64 low-8 leaves). -/
  isBytes : Bool := false
  deriving BEq, Inhabited, Repr

/-- CAP-4: one `pf.crypto.sha256` host site. Inputs are the four Semantic
    UInt256 little-endian u64 limbs (valueBytes[0..8) .. [24..32)). -/
structure Sha256Site where
  input0 : Expr
  input1 : Expr
  input2 : Expr
  input3 : Expr
  deriving BEq, Inhabited, Repr

/-- CAP-X-BYTES-SOR: one `pf.crypto.sha256Bytes` host site. Inputs are the
    N S0-flattened Bytes leaves (each a UInt64 holding the raw byte in
    the low 8 bits, Semantic valueBytes order). Independent of `Sha256Site`. -/
structure Sha256BytesSite where
  byteLen : Nat
  bytes : Array Expr
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
  | int64
  | bool
  /-- Flattened return (1..8 UInt64/Int64 leaves). View and entry admit;
      pureFn stays fail closed. -/
  | aggregate (leafCount : Nat)
  deriving BEq, Inhabited, Repr

structure PlanState where
  name : String
  deriving BEq, Inhabited, Repr

structure PlanInit where
  name : String
  params : Array String
  stores : Array (Nat × Expr)
  /-- CAP-4: sha256 sites emitted before init stores. -/
  sha256Sites : Array Sha256Site := #[]
  /-- CAP-X-BYTES-SOR: sha256Bytes sites emitted before init stores. -/
  sha256BytesSites : Array Sha256BytesSite := #[]
  deriving BEq, Inhabited, Repr

structure PlanEntry where
  name : String
  params : Array String
  resultKind : ResultKind
  checks : Array Check
  stores : Array (Nat × Expr)
  result? : Option Expr
  /-- Aggregate leaves when `resultKind = .aggregate n`; empty for scalars. -/
  leaves : Array Expr := #[]
  leafIsInt : Array Bool := #[]
  terminalRevert : Bool
  /-- CAP-4: sha256 sites emitted before checks/stores/result. -/
  sha256Sites : Array Sha256Site := #[]
  /-- CAP-X-BYTES-SOR: sha256Bytes sites emitted before checks/stores/result. -/
  sha256BytesSites : Array Sha256BytesSite := #[]
  /-- Nonempty ⇒ `stores` and `result?` must be empty (T9a CFG). -/
  body : Array Statement := #[]
  deriving BEq, Inhabited, Repr

structure PlanView where
  name : String
  params : Array String
  resultKind : ResultKind
  value : Expr
  leaves : Array Expr := #[]
  leafIsInt : Array Bool := #[]
  deriving BEq, Inhabited, Repr

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
  deriving BEq, Inhabited, Repr

-- ---------------------------------------------------------------------------
-- Type closure (anonymous unique UInt64 / Bool / Unit only)
-- ---------------------------------------------------------------------------

private def sorobanTypeClosureWording : PilotTypeClosureWording where
  targetLabel := "Soroban"
  uint32DuplicateDetail := "expected at most one anonymous UInt32 type"
  badIntegerWidthDetail :=
    "only anonymous UInt64/Int64 widths are supported (plus UInt256 sha256 plumbing)"
  unsupportedShapeDetail :=
    "only anonymous UInt64, Int64, UInt8 (Bytes element), Bool, Unit, named Struct/Enum UInt64/Int64 leaf flatten (return stays fail closed), Array UInt64 N state flatten, Option UInt64 2-leaf state, Map UInt64 UInt64 cap-8 flatten, Bytes N (N UInt64 low-8 leaves), Principal 9-leaf identity (owner_len+w0..w7, not address), and UInt256 sha256 plumbing are supported (narrow Int/Field/aggregates fail closed)"

/-- UInt32 is interned by Normalize for Array index literals only.
    State/params stay UInt64 or Int64 via the public-slot require helpers. -/
private def pilotUintWidthPolicyU64U32Index : PilotUintWidthPolicy where
  admittedWidths := #[64, 32, 8, 256]

private abbrev SorobanTypeClosureV1 := PilotTypeClosureV1

private def validateSorobanTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult SorobanTypeClosureV1 :=
  validatePilotTypeClosure sorobanPlanErr sorobanTypeClosureWording types
    pilotUintWidthPolicyU64U32Index
    (intPolicy := pilotIntWidthPolicyI64)
    (fieldPolicy := pilotFieldPolicyNone)
    (principalPolicy := pilotPrincipalPolicyAdmit)
    (stringPolicy := pilotStringPolicyAdmit)
    (namedAggregatePolicy := pilotNamedAggregateStatePolicyAdmit)
    (containerPolicy := pilotContainerStatePolicyArrayMapBytes)

private def maxIdentifierBytes : Nat := 200
private def maxPureInlineDepth : Nat := 64
private def maxStateFields : Nat := 64
private def maxParams : Nat := 64
private def maxBodyOps : Nat := 4096
private def maxBodyChecks : Nat := 128
private def maxExpandedExprNodes : Nat := 16384

private def checkedExprNodes (what : String) (nodes : Nat) : CompileResult Nat := do
  unless nodes ≤ maxExpandedExprNodes do
    planError s!"unsupported Soroban semantic shape: {what} expanded expression exceeds {maxExpandedExprNodes} nodes"
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

private def isUInt64Type (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.isUInt64 typeId

private def isInt64Type (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.int64TypeId == some typeId

/-- Program-wide numeric domain: signedNumeric ⇒ Int64, else UInt64. -/
private def matchesNumericDomain
    (types : SorobanTypeClosureV1) (signedNumeric : Bool) (typeId : TypeIdV1) : Bool :=
  if signedNumeric then isInt64Type types typeId else isUInt64Type types typeId

private def isBoolType (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.boolTypeId == some typeId

private def isUnitType (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.unitTypeId == some typeId

private def isUInt32Type (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 32 == some typeId

private def isUInt8Type (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 8 == some typeId

private def isPrincipalType (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.principalTypeId == some typeId

private def isStringType (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.stringTypeId == some typeId

private def isWireIdentityType (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.principalTypeId == some typeId || types.stringTypeId == some typeId

private def isUInt256Type (types : SorobanTypeClosureV1) (typeId : TypeIdV1) : Bool :=
  types.uintTypeIdAt 256 == some typeId

/-- Dense Map UInt64 UInt64 pilot: cap-8 × (occ, key, val) = 24 UInt64 leaves. -/
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

private def decodePrincipalLiteralLeavesV1 (bytes : ByteArray) :
    CompileResult (Array Expr) := do
  unless bytes.size ≥ 4 do
    planError
      "unsupported Soroban semantic shape: Principal literal valueBytes too short"
  let len :=
    (bytes.get! 0).toNat + (bytes.get! 1).toNat * 256 +
      (bytes.get! 2).toNat * 65536 + (bytes.get! 3).toNat * 16777216
  unless bytes.size == 4 + len do
    planError
      "unsupported Soroban semantic shape: Principal literal valueBytes length framing mismatch"
  unless 1 ≤ len do
    planError
      "unsupported Soroban semantic shape: Principal body shorter than 1 byte"
  unless len ≤ principalMaxPayloadBytesV1 do
    planError
      s!"unsupported Soroban semantic shape: Principal longer than {principalMaxPayloadBytesV1} bytes (identity bound)"
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

private def isAggregateValue (v : TypedExpr) : Bool :=
  !v.leaves.isEmpty

private def isPrincipalValue (v : TypedExpr) : Bool :=
  v.isPrincipal && v.leaves.size == principalLeafCountV1

private def isArrayValue (v : TypedExpr) : Bool :=
  isAggregateValue v && !v.isOption && !v.isMap && !v.isPrincipal &&
    !v.isNamed && !v.isUInt256 && !v.isBytes

private def isBytesValue (v : TypedExpr) : Bool :=
  v.isBytes && !v.leaves.isEmpty

private def isNamedValue (v : TypedExpr) : Bool :=
  v.isNamed && !v.leaves.isEmpty

private def mkUInt256Leaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := false
    isMap := false
    isPrincipal := false
    isNamed := false
    isUInt256 := true }

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

private def mkBytesLeaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := false
    isMap := false
    isBytes := true }

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

/-- T4: 9 unsigned UInt64 identity leaves. Not a Soroban Address. -/
private def mkPrincipalLeaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := false
    isMap := false
    isPrincipal := true
    isNamed := false }

private def mkNamedLeaves (leaves : Array Expr) (nodes : Nat) : TypedExpr :=
  { ty := .uint64
    expr := leaves[0]?.getD (.litU64 0)
    expandedNodes := nodes
    leaves
    isOption := false
    isMap := false
    isPrincipal := false
    isNamed := true }

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

private def isAnonymousBytesTypeIdV1
    (typeDecls : Array TypeDeclV1) (typeId : TypeIdV1) : Bool :=
  match typeDecls[typeId.toNat]? with
  | some { shape := .bytes _, name := none, .. } => true
  | _ => false

/-- Admit only anonymous `Map UInt64 UInt64` for the dense cap-8 pilot. -/
private def requireMapUInt64V1
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) : CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .map keyTid valTid, name := none, .. } =>
      unless matchesNumericDomain types signedNumeric keyTid &&
          matchesNumericDomain types signedNumeric valTid do
        planError
          "unsupported Soroban semantic shape: Map state admits only Map UInt64 UInt64"
  | _ =>
      planError
        "unsupported Soroban semantic shape: Map state admits only Map UInt64 UInt64"

/-- Dense Map IndexGet → Option UInt64 as `[tag, payload]`. -/
private def mapLookupOptionLeavesV1
    (mapLeaves : Array Expr) (key : Expr) : CompileResult (Array Expr) := do
  unless mapLeaves.size == mapPilotLeafCountV1 do
    planError
      "unsupported Soroban semantic shape: Map leaf count must match pilot capacity"
  let mut found : Expr := .litBool false
  let mut payload : Expr := .litU64 0
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Soroban semantic shape: Map lookup occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported Soroban semantic shape: Map lookup key leaf missing"
    let some v := mapLeaves[base + 2]? |
      planError "unsupported Soroban semantic shape: Map lookup val leaf missing"
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
      "unsupported Soroban semantic shape: Map leaf count must match pilot capacity"
  let mut anyMatch : Expr := .litBool false
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Soroban semantic shape: Map upsert occ leaf missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported Soroban semantic shape: Map upsert key leaf missing"
    let hit := .boolAnd (.compare .ne occ (.litU64 0)) (.compare .eq k key)
    anyMatch := .boolOr anyMatch hit
  let mut seenEmpty : Expr := .litBool false
  let mut isFirstEmpty : Array Expr := #[]
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Soroban semantic shape: Map upsert empty-scan occ missing"
    let empty := .compare .eq occ (.litU64 0)
    let first := .boolAnd empty (.boolNot seenEmpty)
    isFirstEmpty := isFirstEmpty.push first
    seenEmpty := .boolOr seenEmpty empty
  let okInsert := .boolOr anyMatch seenEmpty
  let mut out : Array Expr := #[]
  for e in [0:mapPilotCapacityV1] do
    let base := e * mapSlotsPerEntryV1
    let some occ := mapLeaves[base]? |
      planError "unsupported Soroban semantic shape: Map upsert rebuild occ missing"
    let some k := mapLeaves[base + 1]? |
      planError "unsupported Soroban semantic shape: Map upsert rebuild key missing"
    let some v := mapLeaves[base + 2]? |
      planError "unsupported Soroban semantic shape: Map upsert rebuild val missing"
    let matchHit :=
      .boolAnd (.compare .ne occ (.litU64 0)) (.compare .eq k key)
    let some firstE := isFirstEmpty[e]? |
      planError "unsupported Soroban semantic shape: Map upsert firstEmpty missing"
    let insertHere := .boolAnd firstE (.boolNot anyMatch)
    let write := .boolOr matchHit insertHere
    let occ' := .ite write (.litU64 1) occ
    let k' := .ite write key k
    let v' := .ite write value v
    out := out.push occ' |>.push k' |>.push v'
  pure (out, okInsert)

/-- S0: admit only anonymous `Option UInt64` for state (tag+payload).
    Non-UInt64 / nested / named Option stay fail closed. -/
private def requireOptionUInt64StateV1
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) (stateName : String) (signedNumeric : Bool) :
    CompileResult Unit := do
  match typeDecls[typeId.toNat]? with
  | some { shape := .option elTid, name := none, .. } =>
      unless matchesNumericDomain types signedNumeric elTid do
        planError
          s!"unsupported Soroban semantic shape: Option state '{stateName}' requires UInt64 payload"
  | _ =>
      planError
        s!"unsupported Soroban semantic shape: state '{stateName}' is not anonymous Option UInt64"

/-- CosmWasm/Quint-style Array UInt64 N flatten: `some n` for admitted 1..8;
    `none` for scalars or Option (Option is not a containerTypeId).
    Nested/narrow/Bytes/N=0/N>8 fail closed. Map is owned by
    `requireMapUInt64V1` / `makeStateLayoutV1`, not this length helper. -/
private def arrayUInt64LenV1
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless matchesNumericDomain types signedNumeric elTid do
        planError
          "unsupported Soroban semantic shape: Array element must be UInt64 (nested/narrow/Int arrays fail closed; no Vec)"
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported Soroban semantic shape: Array UInt64 N state must be 1..8 (got {n}; cap 8 flatten; no Vec)"
      pure (some n)
  | some { shape := .map _ _, .. } =>
      planError
        "unsupported Soroban semantic shape: Map UInt64 flatten is not an Array length"
  | some { shape := .bytes len, .. } =>
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported Soroban semantic shape: Bytes N state must be 1..8 (got {n}; cap 8 flatten)"
      pure (some n)
  | _ =>
      planError
        "unsupported Soroban semantic shape: container TypeId is not Array UInt64 or Bytes N"

/-- Flatten named Struct/Enum into ordered leaf names. UInt64/Int64 only. -/
private def flattenNamedLeafSpecsV1
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) (namePrefix : String) : CompileResult (Array String) := do
  if isUInt64Type types typeId || isInt64Type types typeId then
    unless isIdentifier namePrefix do
      planError s!"state name '{namePrefix}' is not a safe identifier"
    return #[namePrefix]
  unless types.isNamedAggregate typeId do
    planError
      "unsupported Soroban semantic shape: named aggregate leaf must be UInt64, Int64, or named Struct/Enum"
  match typeDecls[typeId.toNat]? with
  | none =>
      planError
        s!"unsupported Soroban semantic shape: missing TypeDecl for aggregate {typeId}"
  | some decl =>
      match decl.shape with
      | .struct fields => do
          unless fields.size > 0 do
            planError
              "unsupported Soroban semantic shape: named Struct requires at least one field"
          let mut out : Array String := #[]
          for f in fields do
            unless isUInt64Type types f.typeId || isInt64Type types f.typeId do
              planError
                "unsupported Soroban semantic shape: named Struct field must be UInt64 or Int64 (nested named stay fail closed)"
            let subName :=
              if namePrefix.isEmpty then f.name else namePrefix ++ "_" ++ f.name
            unless isIdentifier subName do
              planError s!"state name '{subName}' is not a safe identifier"
            out := out.push subName
          pure out
      | .enum variants => do
          unless variants.size > 0 do
            planError
              "unsupported Soroban semantic shape: named Enum requires at least one variant"
          let tagName :=
            if namePrefix.isEmpty then "tag" else namePrefix ++ "_tag"
          unless isIdentifier tagName do
            planError s!"state name '{tagName}' is not a safe identifier"
          let mut maxPay : Nat := 0
          for v in variants do
            unless v.payloadTypes.size ≤ 1 do
              planError
                "unsupported Soroban semantic shape: named Enum variant admits at most one UInt64/Int64 payload"
            for pt in v.payloadTypes do
              unless isUInt64Type types pt || isInt64Type types pt do
                planError
                  "unsupported Soroban semantic shape: named Enum payload must be UInt64 or Int64 (nested named stay fail closed)"
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
            "unsupported Soroban semantic shape: named type must be Struct or Enum"

/-- Parallel signedness marks for named Struct/Enum flatten (tag is unsigned). -/
private def flattenNamedLeafIsIntV1
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Array Bool) := do
  if isUInt64Type types typeId then
    return #[false]
  if isInt64Type types typeId then
    return #[true]
  unless types.isNamedAggregate typeId do
    planError
      "unsupported Soroban semantic shape: named aggregate leaf must be UInt64, Int64, or named Struct/Enum"
  match typeDecls[typeId.toNat]? with
  | none =>
      planError
        s!"unsupported Soroban semantic shape: missing TypeDecl for aggregate {typeId}"
  | some decl =>
      match decl.shape with
      | .struct fields => do
          unless fields.size > 0 do
            planError
              "unsupported Soroban semantic shape: named Struct requires at least one field"
          let mut out : Array Bool := #[]
          for f in fields do
            unless isUInt64Type types f.typeId || isInt64Type types f.typeId do
              planError
                "unsupported Soroban semantic shape: named Struct field must be UInt64 or Int64 (nested named stay fail closed)"
            out := out.push (isInt64Type types f.typeId)
          pure out
      | .enum variants => do
          unless variants.size > 0 do
            planError
              "unsupported Soroban semantic shape: named Enum requires at least one variant"
          let mut maxPay : Nat := 0
          for v in variants do
            unless v.payloadTypes.size ≤ 1 do
              planError
                "unsupported Soroban semantic shape: named Enum variant admits at most one UInt64/Int64 payload"
            for pt in v.payloadTypes do
              unless isUInt64Type types pt || isInt64Type types pt do
                planError
                  "unsupported Soroban semantic shape: named Enum payload must be UInt64 or Int64 (nested named stay fail closed)"
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
                          "unsupported Soroban semantic shape: named Enum payload slot mixes Int64 and UInt64"
            out := out.push (seen.getD false)
          pure out
      | _ =>
          planError
            "unsupported Soroban semantic shape: named type must be Struct or Enum"

/-- View-only aggregate return: Array UInt64 N / Option UInt64 / named
    Struct·Enum (UInt64/Int64 leaves). Map/Bytes stay fail closed. -/
private def viewAggregateLeafIsIntV1
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) (signedNumeric : Bool) :
    CompileResult (Option (Array Bool)) := do
  if isAnonymousOptionTypeIdV1 typeDecls typeId then
    requireOptionUInt64StateV1 typeDecls types typeId "view-return" signedNumeric
    return some #[false, signedNumeric]
  if isWireIdentityType types typeId then
    return some (Array.replicate principalLeafCountV1 false)
  if types.isNamedAggregate typeId then
    let marks ← flattenNamedLeafIsIntV1 typeDecls types typeId
    return some marks
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, name := none, .. } =>
      unless matchesNumericDomain types signedNumeric elTid do
        planError
          "unsupported Soroban semantic shape: Array view return element must be UInt64 (or Int64 when signedNumeric)"
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported Soroban semantic shape: Array UInt64 N view return must be 1..8 (got {n})"
      return some (Array.replicate n signedNumeric)
  | some { shape := .bytes len, name := none, .. } =>
      let n := len.toNat
      unless 1 ≤ n && n ≤ 8 do
        planError
          s!"unsupported Soroban semantic shape: Bytes N view return must be 1..8 (got {n})"
      return some (Array.replicate n false)
  | some { shape := .map .., name := none, .. } => do
      requireMapUInt64V1 typeDecls types typeId signedNumeric
      return some (Id.run do
        let mut marks : Array Bool := #[]
        for i in [0:mapPilotLeafCountV1] do
          marks := marks.push (signedNumeric && i % 3 == 2)
        pure marks)
  | _ =>
      return none

/-- Physical PlanState leaves after Array/Option/Map/named flatten. -/
private structure StateLayout where
  states : Array PlanState
  leavesOf : Array (Array Nat)
  isOptionOf : Array Bool
  isMapOf : Array Bool
  isNamedOf : Array Bool
  deriving Inhabited

private def physicalLeaves
    (layout : StateLayout) (sid : StateIdV1) : CompileResult (Array Nat) := do
  match layout.leavesOf[sid.toNat]? with
  | some phys =>
      unless !phys.isEmpty do
        planError "unsupported Soroban semantic shape: state produced zero flatten leaves"
      pure phys
  | none =>
      planError "unsupported Soroban semantic shape: stateLoad/store references unknown state"

/-- Soroban instance keys go through `symbol_short!` (≤ 9 UTF-8 bytes).
    Flattened leaves must fit; never truncate. -/
private def maxSymbolShortBytes : Nat := 9

private def requireSymbolShortName (name : String) (what : String) : CompileResult Unit := do
  unless name.toUTF8.size ≤ maxSymbolShortBytes do
    planError
      s!"unsupported Soroban semantic shape: {what} '{name}' exceeds symbol_short! 9-byte limit"

private def makeStateLayoutV1
    (data : SemanticProgramDataV1) (types : SorobanTypeClosureV1)
    (signedNumeric : Bool) : CompileResult StateLayout := do
  let mut states : Array PlanState := #[]
  let mut leavesOf : Array (Array Nat) := #[]
  let mut isOptionOf : Array Bool := #[]
  let mut isMapOf : Array Bool := #[]
  let mut isNamedOf : Array Bool := #[]
  for st in data.logicalState do
    unless st.id.toNat == leavesOf.size do
      planError "unsupported Soroban semantic shape: state ids must match declaration order"
    unless isIdentifier st.name do
      planError s!"state name '{st.name}' is not a safe identifier"
    if types.isNamedAggregate st.typeId then
      requirePublicUInt64OrInt64OrFieldOrPrincipalOrNamedState sorobanPlanErr types st
      let leafSpecs ← flattenNamedLeafSpecsV1 data.types types st.typeId st.name
      if leafSpecs.isEmpty then
        planError s!"state '{st.name}' produced zero named-aggregate leaves"
      if states.size + leafSpecs.size > maxStateFields then
        planError "unsupported Soroban semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for leafName in leafSpecs do
        requireSymbolShortName leafName "flattened leaf"
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isMapOf := isMapOf.push false
      isNamedOf := isNamedOf.push true
    else if isAnonymousOptionTypeIdV1 data.types st.typeId then
      -- Option UInt64 → tag + payload (2 instance u64 keys). Names
      -- follow CosmWasm Enum convention (`name_tag` / `name_p0`).
      -- Default zeros = none; construct none also zeros payload.
      requireOptionUInt64StateV1 data.types types st.typeId st.name signedNumeric
      if states.size + 2 > maxStateFields then
        planError "unsupported Soroban semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for leafName in #[st.name ++ "_tag", st.name ++ "_p0"] do
        unless isIdentifier leafName do
          planError s!"state name '{leafName}' is not a safe identifier"
        requireSymbolShortName leafName "flattened leaf"
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push true
      isMapOf := isMapOf.push false
      isNamedOf := isNamedOf.push false
    else if isAnonymousMapTypeIdV1 data.types st.typeId then
      requireMapUInt64V1 data.types types st.typeId signedNumeric
      if states.size + mapPilotLeafCountV1 > maxStateFields then
        planError "unsupported Soroban semantic shape: state field count exceeds limit"
      let mut leaves : Array Nat := #[]
      for i in [0:mapPilotLeafCountV1] do
        let leafName := st.name ++ "_" ++ toString i
        unless isIdentifier leafName do
          planError s!"state name '{leafName}' is not a safe identifier"
        requireSymbolShortName leafName "flattened leaf"
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isMapOf := isMapOf.push true
      isNamedOf := isNamedOf.push false
    else if isWireIdentityType types st.typeId then
      if states.size + principalLeafCountV1 > maxStateFields then
        planError "unsupported Soroban semantic shape: state field count exceeds limit"
      let leafSpecs ← flattenPrincipalLeafNamesV1 st.name
      let mut leaves : Array Nat := #[]
      for leafName in leafSpecs do
        requireSymbolShortName leafName "flattened leaf"
        leaves := leaves.push states.size
        states := states.push { name := leafName }
      leavesOf := leavesOf.push leaves
      isOptionOf := isOptionOf.push false
      isMapOf := isMapOf.push false
      isNamedOf := isNamedOf.push false
    else
      match ← arrayUInt64LenV1 data.types types st.typeId signedNumeric with
      | some n =>
          if states.size + n > maxStateFields then
            planError "unsupported Soroban semantic shape: state field count exceeds limit"
          let mut leaves : Array Nat := #[]
          for i in [0:n] do
            let leafName := st.name ++ "_" ++ toString i
            unless isIdentifier leafName do
              planError s!"state name '{leafName}' is not a safe identifier"
            requireSymbolShortName leafName "flattened leaf"
            leaves := leaves.push states.size
            states := states.push { name := leafName }
          leavesOf := leavesOf.push leaves
          isOptionOf := isOptionOf.push false
          isMapOf := isMapOf.push false
          isNamedOf := isNamedOf.push false
      | none =>
          if isUInt256Type types st.typeId then
            planError (uint256PlumbingFc "state")
          requirePublicUInt64OrInt64State sorobanPlanErr types st
          if states.size + 1 > maxStateFields then
            planError "unsupported Soroban semantic shape: state field count exceeds limit"
          requireSymbolShortName st.name "state name"
          let fi := states.size
          states := states.push { name := st.name }
          leavesOf := leavesOf.push #[fi]
          isOptionOf := isOptionOf.push false
          isMapOf := isMapOf.push false
          isNamedOf := isNamedOf.push false
  unless states.size ≤ maxStateFields do
    planError "unsupported Soroban semantic shape: state field count exceeds limit"
  pure { states, leavesOf, isOptionOf, isMapOf, isNamedOf }

/-- First-seen integer domain. Mixed UInt64/Int64 user-facing slots fail closed. -/
private def noteIntegerDomain
    (types : SorobanTypeClosureV1) (typeId : TypeIdV1) (signed? : Option Bool)
    (owner : String) : CompileResult (Option Bool) := do
  if isInt64Type types typeId then
    match signed? with
    | some false =>
        planError
          s!"unsupported Soroban semantic shape: {owner} mixes Int64 with UInt64 (S0 numeric domain is homogeneous)"
    | _ => pure (some true)
  else if isUInt64Type types typeId then
    match signed? with
    | some true =>
        planError
          s!"unsupported Soroban semantic shape: {owner} mixes UInt64 with Int64 (S0 numeric domain is homogeneous)"
    | _ => pure (some false)
  else
    pure signed?

private def numericTyOf (signed : Bool) : ExprType :=
  if signed then .int64 else .uint64

private def maxU64Value : UInt64 := UInt64.ofNat 18446744073709551615
private def minI64Bits : UInt64 := UInt64.ofNat 9223372036854775808
private def maxI64Bits : UInt64 := UInt64.ofNat 9223372036854775807
private def negOneBits : UInt64 := UInt64.ofNat 18446744073709551615

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
    / Option / Map overlays expand to their flatten leaves; scalars stay
    one field. -/
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
  opCount : Nat
  sha256Sites : Array Sha256Site := #[]
  sha256BytesSites : Array Sha256BytesSite := #[]
  nextTemp : Nat := 0
  deriving Inhabited

private def emptyBodyAccum (env : ValueEnv) (overlay : StateOverlay) : BodyAccum :=
  { env, overlay, checks := #[], opCount := 0, sha256Sites := #[],
    sha256BytesSites := #[], nextTemp := 0 }

private def pushCheck (acc : BodyAccum) (ck : Check) : CompileResult BodyAccum := do
  if acc.checks.size + 1 > maxBodyChecks then
    planError s!"unsupported Soroban semantic shape: body check count exceeds {maxBodyChecks}"
  pure { acc with checks := acc.checks.push ck }

private def bumpOp (acc : BodyAccum) : CompileResult BodyAccum := do
  if acc.opCount + 1 > maxBodyOps then
    planError "unsupported Soroban semantic shape: body operation count exceeds limit"
  pure { acc with opCount := acc.opCount + 1 }

private def requireTy (v : TypedExpr) (ty : ExprType) (what : String) :
    CompileResult Expr := do
  if v.isUInt256 then
    planError
      s!"unsupported Soroban semantic shape: {what} cannot be a UInt256 (UInt256 is sha256 plumbing only)"
  if isAggregateValue v then
    planError s!"unsupported Soroban semantic shape: {what} cannot be an Array/Option/Map aggregate"
  unless v.ty == ty do
    planError s!"unsupported Soroban semantic shape: {what} type mismatch"
  pure v.expr

private def literalIndexNatV1 (v : TypedExpr) : CompileResult Nat := do
  unless !isAggregateValue v && v.ty == .uint64 do
    planError
      "unsupported Soroban semantic shape: Array index must be a UInt32/UInt64 literal"
  match v.expr with
  | .litU64 n => pure n.toNat
  | _ =>
      planError
        "unsupported Soroban semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def lowerLiteral
    (types : SorobanTypeClosureV1) (typeId : TypeIdV1) (valueBytes : ByteArray) :
    CompileResult TypedExpr := do
  if isInt64Type types typeId then
    let v ← decodeInt64LiteralLe sorobanPlanErr "Soroban" valueBytes
    pure { ty := .int64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt64Type types typeId then
    let v ← decodeUInt64LiteralLe sorobanPlanErr "Soroban" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt32Type types typeId then
    let v ← decodeUInt32LiteralLe sorobanPlanErr "Soroban" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isUInt8Type types typeId then
    let v ← decodeUInt8LiteralLe sorobanPlanErr "Soroban" valueBytes
    pure { ty := .uint64, expr := .litU64 v, expandedNodes := 1 }
  else if isBoolType types typeId then
    let b ← decodeBoolLiteralBit sorobanPlanErr "Soroban" valueBytes
    pure { ty := .bool, expr := .litBool b, expandedNodes := 1 }
  else if isWireIdentityType types typeId then
    let leaves ← decodePrincipalLiteralLeavesV1 valueBytes
    pure (mkPrincipalLeaves leaves leaves.size)
  else if isUInt256Type types typeId then
    let n ← decodeUIntWideLiteralLe sorobanPlanErr "Soroban" 256 valueBytes
    let b : Nat := 18446744073709551616
    let leaves : Array Expr :=
      #[.litU64 (UInt64.ofNat (n % b)),
        .litU64 (UInt64.ofNat ((n / b) % b)),
        .litU64 (UInt64.ofNat ((n / (b * b)) % b)),
        .litU64 (UInt64.ofNat ((n / (b * b * b)) % b))]
    pure (mkUInt256Leaves leaves 4)
  else
    planError "unsupported Soroban semantic shape: literal type is outside UInt64/Int64/UInt32/UInt8/Bool/Principal/UInt256"

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
      if isPrincipalValue lhs && isPrincipalValue rhs then
        unless op == .eq || op == .ne do
          planError "unsupported Soroban semantic shape: Principal comparison only supports eq/ne"
        let mut acc : Expr :=
          .compare .eq lhs.leaves[0]! rhs.leaves[0]!
        for i in [1:principalLeafCountV1] do
          acc := .boolAnd acc (.compare .eq lhs.leaves[i]! rhs.leaves[i]!)
        if op == .ne then
          acc := .boolNot acc
        let nodes ← binaryExprNodes "principal comparison" lhs rhs
        return ({ ty := .bool, expr := acc, expandedNodes := nodes }, #[])
      unless lhs.ty == rhs.ty do
        planError "unsupported Soroban semantic shape: comparison operands must share a type"
      unless lhs.ty == .uint64 || lhs.ty == .int64 || lhs.ty == .bool do
        planError "unsupported Soroban semantic shape: comparison operands must be UInt64, Int64, or Bool"
      if lhs.ty == .bool && !(op == .eq || op == .ne) then
        planError "unsupported Soroban semantic shape: Bool comparison only supports eq/ne"
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
      planError "unsupported Soroban semantic shape: bitwise/shift ops are outside S0"

private def lowerUnary (op : UnaryOpV1) (operand : TypedExpr) :
    CompileResult TypedExpr := do
  match op with
  | .not => do
      let o ← requireTy operand .bool "bool not"
      let nodes ← unaryExprNodes "bool not" operand
      pure { ty := .bool, expr := .boolNot o, expandedNodes := nodes }
  | .neg | .bitNot =>
      planError "unsupported Soroban semantic shape: unary neg/bitNot are outside S0"

private structure CallableIndex where
  pureFns : Array (CallableIdV1 × CallableV1)
  deriving Inhabited

private def lookupPureFn (idx : CallableIndex) (id : CallableIdV1) :
    Option CallableV1 :=
  idx.pureFns.findSome? (fun (cid, c) => if cid == id then some c else none)

private def resultKindOf
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (typeId : TypeIdV1) (owner : String)
    (signedNumeric : Bool) (allowViewAggregate : Bool) :
    CompileResult ResultKind := do
  if isUnitType types typeId then pure .unit
  else if isInt64Type types typeId then pure .int64
  else if isUInt64Type types typeId then pure .uint64
  else if isBoolType types typeId then pure .bool
  else if isWireIdentityType types typeId then
    pure (.aggregate principalLeafCountV1)
  else if allowViewAggregate then
    match typeDecls[typeId.toNat]? with
    | some { shape := .bytes len, name := none, .. } => do
        let n := len.toNat
        unless 1 ≤ n && n ≤ 8 do
          planError s!"{owner} Bytes N return must be 1..8 (got {n})"
        pure (.aggregate n)
    | some { shape := .map .., name := none, .. } => do
        requireMapUInt64V1 typeDecls types typeId signedNumeric
        pure (.aggregate mapPilotLeafCountV1)
    | _ =>
    match ← viewAggregateLeafIsIntV1 typeDecls types typeId signedNumeric with
    | some marks => do
        let n := marks.size
        unless 1 ≤ n && n ≤ 8 do
          planError
            s!"{owner} aggregate return must have 1..8 leaves (got {n})"
        pure (.aggregate n)
    | none =>
        if isAnonymousOptionTypeIdV1 typeDecls typeId then
          planError s!"{owner} Option return is outside S0"
        else if types.isNamedAggregate typeId then
          planError s!"{owner} named Struct/Enum return is outside S0"
        else if types.isContainer typeId then
          planError
            s!"{owner} Array/Map return is outside S0 (only Array/Map UInt64 state flattens; no Vec/HashMap)"
        else planError s!"{owner} result must be public Unit, UInt64, Int64, or Bool"
  else if isAnonymousOptionTypeIdV1 typeDecls typeId then
    planError s!"{owner} Option return is outside S0"
  else if types.isNamedAggregate typeId then
    planError s!"{owner} named Struct/Enum return is outside S0"
  else if isUInt256Type types typeId then
    planError (uint256PlumbingFc "result")
  else if types.isContainer typeId then
    planError
      s!"{owner} Array/Map return is outside S0 (only Array/Map UInt64 state flattens; no Vec/HashMap)"
  else planError s!"{owner} result must be public Unit, UInt64, Int64, or Bool"

private partial def lowerBlockInstructions
    (data : SemanticProgramDataV1) (types : SorobanTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1)
    (numericTy : ExprType) (layout : StateLayout)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (block : BlockV1)
    (acc0 : BodyAccum) :
    CompileResult BodyAccum := do
  unless block.params.isEmpty || block.params.size == 1 do
    planError "unsupported Soroban semantic shape: block parameters are outside S0"
  let mut acc := acc0
  for instr in block.instructions do
    acc ← bumpOp acc
    match instr.op with
    | .literal typeId valueBytes => do
        let v ← lowerLiteral types typeId valueBytes
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: literal must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId v }
    | .constant constantId => do
        let some c := data.constants[constantId.toNat]? |
          planError "unsupported Soroban semantic shape: Constant references an unknown constant id"
        unless c.id == constantId do
          planError "unsupported Soroban semantic shape: Constant id does not match declaration order"
        let v ← lowerLiteral types c.typeId c.valueBytes
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: Constant must produce a value"
        | some vd =>
            unless vd.typeId == c.typeId do
              planError "unsupported Soroban semantic shape: Constant result typeId must match the declaration"
            acc := { acc with env := envInsert acc.env vd.valueId v }
    | .stateLoad stateId => do
        unless allowStateRead do
          planError "unsupported Soroban semantic shape: pureFn cannot read state"
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: stateLoad must produce a value"
        | some vd =>
            unless stateId.toNat < data.logicalState.size do
              planError "unsupported Soroban semantic shape: stateLoad references unknown state"
            let phys ← physicalLeaves layout stateId
            let isOpt :=
              match layout.isOptionOf[stateId.toNat]? with
              | some b => b
              | none => false
            let isMp :=
              match layout.isMapOf[stateId.toNat]? with
              | some b => b
              | none => false
            let isNm :=
              match layout.isNamedOf[stateId.toNat]? with
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
                  else if isNm then
                    mkNamedLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
                  else if isWireIdentityType types vd.typeId then
                    mkPrincipalLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
                  else if isAnonymousBytesTypeIdV1 data.types vd.typeId then
                    mkBytesLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
                  else
                    mkArrayLeaves (phys.map (fun fi => .stateLoad fi)) phys.size
            acc := { acc with env := envInsert acc.env vd.valueId value }
    | .stateStore stateId value => do
        unless allowStateWrite do
          planError "unsupported Soroban semantic shape: StateStore is only legal in init/entry"
        let v ← match envLookup acc.env value with
          | some tv => pure tv
          | none => planError "unsupported Soroban semantic shape: stateStore value undefined"
        unless stateId.toNat < data.logicalState.size do
          planError "unsupported Soroban semantic shape: stateStore references unknown state"
        let phys ← physicalLeaves layout stateId
        if isAggregateValue v then
          unless v.leaves.size == phys.size do
            planError "unsupported Soroban semantic shape: stateStore leaf count mismatch"
        else
          unless phys.size == 1 do
            planError "unsupported Soroban semantic shape: stateStore scalar into Array/Option/Map state"
          let _ ← requireTy v numericTy "stateStore value"
        acc := { acc with overlay := overlayInsert acc.overlay stateId v }
    | .binary op lhs rhs => do
        let lv ← match envLookup acc.env lhs with
          | some v => pure v
          | none => planError "unsupported Soroban semantic shape: binary lhs undefined"
        let rv ← match envLookup acc.env rhs with
          | some v => pure v
          | none => planError "unsupported Soroban semantic shape: binary rhs undefined"
        let (tv, cks) ← lowerBinary op lv rv
        if forbidChecks && !cks.isEmpty then
          planError "unsupported Soroban semantic shape: initializer cannot contain fallible checks"
        for ck in cks do
          acc ← pushCheck acc ck
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: binary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .unary op operand => do
        let ov ← match envLookup acc.env operand with
          | some v => pure v
          | none => planError "unsupported Soroban semantic shape: unary operand undefined"
        let tv ← lowerUnary op ov
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: unary must produce a value"
        | some vd => acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .pureCall calleeId args => do
        if inlineDepth >= maxPureInlineDepth then
          planError "unsupported Soroban semantic shape: pureFn inline depth exceeds 64"
        let callee ← match lookupPureFn idx calleeId with
          | some c => pure c
          | none =>
              planError "unsupported Soroban semantic shape: pureCall callee is not a pureFn"
        unless callee.params.size == args.size do
          planError "unsupported Soroban semantic shape: pureCall arity mismatch"
        let mut cEnv : ValueEnv := { entries := #[] }
        for i in [0:args.size] do
          let some argId := args[i]? |
            planError "unsupported Soroban semantic shape: pureCall arg missing"
          let some p := callee.params[i]? |
            planError "unsupported Soroban semantic shape: pureCall param missing"
          let av ← match envLookup acc.env argId with
            | some v => pure v
            | none => planError "unsupported Soroban semantic shape: pureCall arg undefined"
          unless (isUInt64Type types p.typeId && av.ty == .uint64) ||
              (isInt64Type types p.typeId && av.ty == .int64) do
            planError "unsupported Soroban semantic shape: pureFn params must be public UInt64 or Int64"
          cEnv := envInsert cEnv p.valueId av
        let cAcc0 : BodyAccum := emptyBodyAccum cEnv { entries := #[] }
        unless callee.blocks.size == 1 do
          planError "unsupported Soroban semantic shape: each callable must have exactly one block"
        unless callee.loopBounds.isEmpty do
          planError "unsupported Soroban semantic shape: loopBounds are outside S0"
        let some cBlock := callee.blocks[0]? |
          planError "unsupported Soroban semantic shape: missing entry block"
        let cAcc ←
          lowerBlockInstructions data types idx callee numericTy layout
            (allowStateRead := false) (allowStateWrite := false)
            (forbidChecks := forbidChecks) (inlineDepth := inlineDepth + 1)
            cBlock cAcc0
        let ret? ← match cBlock.terminator with
          | .return_ value =>
              match value with
              | none => pure (none : Option TypedExpr)
              | some vid =>
                  match envLookup cAcc.env vid with
                  | some tv => pure (some tv)
                  | none =>
                      planError "unsupported Soroban semantic shape: return value undefined"
          | .revert .. =>
              planError
                "unsupported Soroban semantic shape: pureFn revert during inline is outside S0"
          | .jump .. | .branch .. | .switch .. | .trap .. =>
              planError "unsupported Soroban semantic shape: multi-block/trap terminators are outside S0"
        let expandedOpCount := acc.opCount + cAcc.opCount
        if expandedOpCount > maxBodyOps then
          planError "unsupported Soroban semantic shape: expanded pureFn operation count exceeds limit"
        acc := { acc with opCount := expandedOpCount }
        for ck in cAcc.checks do
          if forbidChecks then
            planError "unsupported Soroban semantic shape: initializer cannot contain fallible checks"
          let propagated :=
            match ck.kind with
            | .terminalRevert errorIndex =>
                { ck with kind := .declaredRevert errorIndex }
            | _ => ck
          acc ← pushCheck acc propagated
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: pureCall must produce a value"
        | some vd =>
            match ret? with
            | some tv => acc := { acc with env := envInsert acc.env vd.valueId tv }
            | none =>
                if isUnitType types vd.typeId then
                  pure ()
                else
                  planError "unsupported Soroban semantic shape: pureCall missing return value"
    | .assert_ condition errorId args => do
        unless errorId.isNone && args.isEmpty do
          planError "unsupported Soroban semantic shape: assert requires errorId=none and empty args"
        let c ← match envLookup acc.env condition with
          | some v => requireTy v .bool "assert condition"
          | none => planError "unsupported Soroban semantic shape: assert condition undefined"
        if forbidChecks then
          planError "unsupported Soroban semantic shape: initializer cannot contain fallible checks"
        acc ← pushCheck acc { kind := .assertion, condition := c }
    | .externalCall _effectId callee argIds => do
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          if isPfCryptoSha256BytesCalleeV1 qn then
            if callable.kind == .view || callable.kind == .pureFn then
              planError
                "unsupported Soroban semantic shape: view/pureFn must not call pf.crypto.sha256Bytes"
            if numericTy == .int64 then
              planError
                "unsupported Soroban semantic shape: signedNumeric Int64 programs cannot carry pf.crypto.sha256Bytes (UInt256 plumbing is unsigned)"
            match instr.result with
            | none =>
                planError
                  "unsupported Soroban semantic shape: pf.crypto.sha256Bytes requires exactly one Bytes N argument and UInt256 result"
            | some vd =>
                unless argIds.size == 1 && isUInt256Type types vd.typeId do
                  planError
                    "unsupported Soroban semantic shape: pf.crypto.sha256Bytes requires exactly one Bytes N argument and UInt256 result"
                let some argId := argIds[0]? |
                  planError
                    "unsupported Soroban semantic shape: pf.crypto.sha256Bytes Bytes argument is missing"
                let root ← match envLookup acc.env argId with
                  | some v => pure v
                  | none =>
                      planError
                        "unsupported Soroban semantic shape: pf.crypto.sha256Bytes argument is undefined"
                unless isBytesValue root do
                  planError
                    "unsupported Soroban semantic shape: pf.crypto.sha256Bytes requires exactly one Bytes N argument and UInt256 result"
                let n := root.leaves.size
                unless 1 ≤ n && n ≤ maxSha256BytesLenV1 && n == root.leaves.size do
                  planError
                    s!"unsupported Soroban semantic shape: pf.crypto.sha256Bytes Bytes N must be 1..8 (got {n}; S0 flatten / Bytes::from_array honesty cap)"
                let siteIdx := acc.sha256BytesSites.size
                acc := { acc with
                  sha256BytesSites := acc.sha256BytesSites.push {
                    byteLen := n
                    bytes := root.leaves
                  } }
                let leaves : Array Expr :=
                  #[.sha256BytesLimb siteIdx 0, .sha256BytesLimb siteIdx 1,
                    .sha256BytesLimb siteIdx 2, .sha256BytesLimb siteIdx 3]
                acc := { acc with
                  env := envInsert acc.env vd.valueId (mkUInt256Leaves leaves 4) }
          else do
            unless isPfCryptoSha256CalleeV1 qn do
              planError
                s!"unsupported Soroban semantic shape: pf.crypto QN '{qn}' has no Soroban host binding (sha256/keccak256 and siblings stay fail closed)"
            if callable.kind == .view || callable.kind == .pureFn then
              planError
                "unsupported Soroban semantic shape: view/pureFn must not call pf.crypto.sha256"
            if numericTy == .int64 then
              planError
                "unsupported Soroban semantic shape: signedNumeric Int64 programs cannot carry pf.crypto.sha256 (UInt256 plumbing is unsigned)"
            match instr.result with
            | none =>
                planError
                  "unsupported Soroban semantic shape: pf.crypto.sha256 requires exactly one UInt256 argument and UInt256 result"
            | some vd =>
                unless argIds.size == 1 && isUInt256Type types vd.typeId do
                  planError
                    "unsupported Soroban semantic shape: pf.crypto.sha256 requires exactly one UInt256 argument and UInt256 result"
                let some argId := argIds[0]? |
                  planError
                    "unsupported Soroban semantic shape: pf.crypto.sha256 UInt256 argument is missing"
                let root ← match envLookup acc.env argId with
                  | some v => pure v
                  | none =>
                      planError
                        "unsupported Soroban semantic shape: pf.crypto.sha256 argument is undefined"
                unless root.isUInt256 && root.leaves.size == 4 do
                  planError
                    "unsupported Soroban semantic shape: pf.crypto.sha256 requires exactly one UInt256 argument and UInt256 result"
                let some in0 := root.leaves[0]? |
                  planError "unsupported Soroban semantic shape: pf.crypto.sha256 limb 0 missing"
                let some in1 := root.leaves[1]? |
                  planError "unsupported Soroban semantic shape: pf.crypto.sha256 limb 1 missing"
                let some in2 := root.leaves[2]? |
                  planError "unsupported Soroban semantic shape: pf.crypto.sha256 limb 2 missing"
                let some in3 := root.leaves[3]? |
                  planError "unsupported Soroban semantic shape: pf.crypto.sha256 limb 3 missing"
                let siteIdx := acc.sha256Sites.size
                acc := { acc with
                  sha256Sites := acc.sha256Sites.push {
                    input0 := in0, input1 := in1, input2 := in2, input3 := in3
                  } }
                let leaves : Array Expr :=
                  #[.sha256Limb siteIdx 0, .sha256Limb siteIdx 1,
                    .sha256Limb siteIdx 2, .sha256Limb siteIdx 3]
                acc := { acc with
                  env := envInsert acc.env vd.valueId (mkUInt256Leaves leaves 4) }
        else
          planError "unsupported Soroban semantic shape: op is outside S0"
    | .schedule _effectId callee _args => do
        let qn := qnJoined callee
        if isPfCryptoCalleeV1 qn then
          planError
            s!"unsupported Soroban semantic shape: pf.crypto QN '{qn}' has no Soroban host binding (sha256/keccak256 and siblings stay fail closed)"
        planError "unsupported Soroban semantic shape: op is outside S0"
    | .contextRead key => do
        match instr.result with
        | none =>
            planError "unsupported Soroban semantic shape: ContextRead must produce a value"
        | some vd =>
            if key == unixTimeSecondsContextKeyV1 then
              unless isUInt64Type types vd.typeId do
                planError
                  "unsupported Soroban semantic shape: ContextRead unix-time-seconds result must be UInt64"
              let v : TypedExpr :=
                { ty := .uint64, expr := .unixTimeSeconds, expandedNodes := 1 }
              acc := { acc with env := envInsert acc.env vd.valueId v }
            else if key == blockHeightContextKeyV1 then
              unless isUInt64Type types vd.typeId do
                planError
                  "unsupported Soroban semantic shape: ContextRead block-height result must be UInt64"
              let v : TypedExpr :=
                { ty := .uint64, expr := .blockHeight, expandedNodes := 1 }
              acc := { acc with env := envInsert acc.env vd.valueId v }
            else if isUnboundUInt64ContextKey key then
              planError
                s!"unsupported Soroban semantic shape: ContextRead '{key.value}' has no Soroban host binding (attachedValue/chainId stay fail closed)"
            else
              -- caller/self remain on this generic envelope (Principal rejected first).
              planError "unsupported Soroban semantic shape: op is outside S0"
    | .envRead key _args =>
        if key == .nativeVaultBalance then
          planError
            s!"unsupported Soroban semantic shape: envRead nativeVaultBalance has no Soroban host binding (pf.assets.native.balanceOfSelf stays fail closed)"
        -- tokenVaultBalance needs a Principal mint; nativeVaultBalanceU128 is
        -- outside S0 UInt64. Both stay on the generic envRead envelope.
        planError "unsupported Soroban semantic shape: op is outside S0"
    | .construct typeId ctorIdx argIds => do
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: construct must produce a value"
        | some vd =>
            if isAnonymousMapTypeIdV1 data.types typeId then
              requireMapUInt64V1 data.types types typeId (numericTy == .int64)
              unless ctorIdx == 0 do
                planError
                  "unsupported Soroban semantic shape: Map construct ctorIdx must be 0"
              unless argIds.isEmpty do
                planError
                  "unsupported Soroban semantic shape: nonempty Map construct is outside S0 (build maps via IndexSet upsert)"
              let zeros := Array.replicate mapPilotLeafCountV1 (.litU64 0)
              acc := { acc with
                env := envInsert acc.env vd.valueId
                  (mkMapLeaves zeros mapPilotLeafCountV1) }
            else if isAnonymousOptionTypeIdV1 data.types typeId then
              -- CosmWasm-shaped Option UInt64 construct: ctor 0 none
              -- arity 0 → #[0,0]; ctor 1 some arity 1 → #[1,v].
              match data.types[typeId.toNat]? with
              | some { shape := .option elTid, name := none, .. } => do
                  unless matchesNumericDomain types (numericTy == .int64) elTid do
                    planError
                      "unsupported Soroban semantic shape: Option construct requires UInt64 payload"
                  unless ctorIdx.toNat == 0 || ctorIdx.toNat == 1 do
                    planError
                      "unsupported Soroban semantic shape: Option construct ctorIdx must be 0 (none) or 1 (some)"
                  if ctorIdx.toNat == 0 then
                    unless argIds.isEmpty do
                      planError
                        "unsupported Soroban semantic shape: Option.none construct takes no args"
                    acc := { acc with
                      env := envInsert acc.env vd.valueId
                        (mkOptionLeaves #[.litU64 0, .litU64 0] 2) }
                  else do
                    unless argIds.size == 1 do
                      planError
                        "unsupported Soroban semantic shape: Option.some construct takes one arg"
                    let some argId := argIds[0]? |
                      planError "unsupported Soroban semantic shape: Option.some construct arg missing"
                    let av ← match envLookup acc.env argId with
                      | some v => pure v
                      | none =>
                          planError
                            "unsupported Soroban semantic shape: construct arg undefined"
                    unless !isAggregateValue av && av.ty == numericTy do
                      planError
                        "unsupported Soroban semantic shape: Option.some arg must be scalar UInt64"
                    acc := { acc with
                      env := envInsert acc.env vd.valueId
                        (mkOptionLeaves #[.litU64 1, av.expr] (av.expandedNodes + 2)) }
              | _ =>
                  planError
                    "unsupported Soroban semantic shape: Option construct requires anonymous Option"
            else if types.isNamedAggregate typeId then
              let some decl := data.types[typeId.toNat]? |
                planError "unsupported Soroban semantic shape: construct TypeDecl missing"
              match decl.shape with
              | .struct fields => do
                  unless ctorIdx.toNat == 0 do
                    planError
                      "unsupported Soroban semantic shape: struct construct ctorIdx must be 0"
                  unless argIds.size == fields.size do
                    planError
                      "unsupported Soroban semantic shape: struct construct arity mismatch"
                  let mut leafExprs : Array Expr := #[]
                  let mut nodes : Nat := 0
                  for i in [0:argIds.size] do
                    let some argId := argIds[i]? |
                      planError "unsupported Soroban semantic shape: struct construct arg missing"
                    let av ← match envLookup acc.env argId with
                      | some v => pure v
                      | none => planError "unsupported Soroban semantic shape: construct arg undefined"
                    unless !isAggregateValue av &&
                        (av.ty == .uint64 || av.ty == .int64) do
                      planError
                        "unsupported Soroban semantic shape: struct construct args must be scalar UInt64/Int64"
                    leafExprs := leafExprs.push av.expr
                    nodes := nodes + av.expandedNodes
                  acc := { acc with
                    env := envInsert acc.env vd.valueId
                      (mkNamedLeaves leafExprs (nodes + leafExprs.size)) }
              | .enum variants => do
                  let vi := ctorIdx.toNat
                  let some variant := variants[vi]? |
                    planError
                      "unsupported Soroban semantic shape: enum construct variant out of range"
                  unless argIds.size == variant.payloadTypes.size do
                    planError
                      "unsupported Soroban semantic shape: enum construct arity mismatch"
                  let mut maxPay : Nat := 0
                  for v in variants do
                    if v.payloadTypes.size > maxPay then maxPay := v.payloadTypes.size
                  let mut leafExprs : Array Expr := #[.litU64 (UInt64.ofNat vi)]
                  let mut nodes : Nat := 1
                  for argId in argIds do
                    let av ← match envLookup acc.env argId with
                      | some v => pure v
                      | none => planError "unsupported Soroban semantic shape: construct arg undefined"
                    unless !isAggregateValue av &&
                        (av.ty == .uint64 || av.ty == .int64) do
                      planError
                        "unsupported Soroban semantic shape: enum construct payload must be scalar UInt64/Int64"
                    leafExprs := leafExprs.push av.expr
                    nodes := nodes + av.expandedNodes
                  while leafExprs.size < 1 + maxPay do
                    leafExprs := leafExprs.push (.litU64 0)
                    nodes := nodes + 1
                  acc := { acc with
                    env := envInsert acc.env vd.valueId
                      (mkNamedLeaves leafExprs nodes) }
              | _ =>
                  planError
                    "unsupported Soroban semantic shape: named construct requires Struct or Enum"
            else
              let n ← match ← arrayUInt64LenV1 data.types types typeId (numericTy == .int64) with
                | some n => pure n
                | none =>
                    planError
                      "unsupported Soroban semantic shape: construct admits only Array UInt64 N, Option UInt64, Map UInt64 UInt64, or named Struct/Enum on Soroban"
              unless ctorIdx == 0 do
                planError "unsupported Soroban semantic shape: Array construct ctorIdx must be 0"
              unless argIds.size == n do
                planError "unsupported Soroban semantic shape: Array construct arity mismatch"
              let mut leafExprs : Array Expr := #[]
              let mut nodes : Nat := 0
              for argId in argIds do
                let av ← match envLookup acc.env argId with
                  | some v => pure v
                  | none => planError "unsupported Soroban semantic shape: construct arg undefined"
                unless !isAggregateValue av && av.ty == numericTy do
                  planError
                    "unsupported Soroban semantic shape: Array construct args must be scalar UInt64"
                leafExprs := leafExprs.push av.expr
                nodes := nodes + av.expandedNodes
              let tv :=
                if isAnonymousBytesTypeIdV1 data.types typeId then
                  mkBytesLeaves leafExprs (nodes + n)
                else
                  mkArrayLeaves leafExprs (nodes + n)
              acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .indexGet base index => do
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: IndexGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: IndexGet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: IndexGet index undefined"
            if isMapValue bv then
              unless !isAggregateValue iv && iv.ty == numericTy do
                planError
                  "unsupported Soroban semantic shape: Map IndexGet key must be scalar UInt64"
              let optLeaves ← mapLookupOptionLeavesV1 bv.leaves iv.expr
              let ov := mkOptionLeaves optLeaves
                (bv.expandedNodes + iv.expandedNodes + 8)
              acc := { acc with env := envInsert acc.env vd.valueId ov }
            else do
              unless isArrayValue bv || isBytesValue bv do
                planError
                  "unsupported Soroban semantic shape: IndexGet base must be an Array UInt64 or Map UInt64 aggregate"
              let i ← literalIndexNatV1 iv
              unless i < bv.leaves.size do
                planError "unsupported Soroban semantic shape: Array IndexGet index out of range"
              let some leaf := bv.leaves[i]? |
                planError "unsupported Soroban semantic shape: Array IndexGet leaf missing"
              acc := { acc with env := envInsert acc.env vd.valueId {
                ty := numericTy
                expr := leaf
                expandedNodes := 1
              } }
    | .indexSet base index value => do
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: IndexSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env base with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: IndexSet base undefined"
            let iv ← match envLookup acc.env index with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: IndexSet index undefined"
            let vv ← match envLookup acc.env value with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: IndexSet value undefined"
            if isMapValue bv then
              unless !isAggregateValue iv && iv.ty == numericTy do
                planError
                  "unsupported Soroban semantic shape: Map IndexSet key must be scalar UInt64"
              unless !isAggregateValue vv && vv.ty == numericTy do
                planError
                  "unsupported Soroban semantic shape: Map IndexSet value must be scalar UInt64"
              if forbidChecks then
                planError
                  "unsupported Soroban semantic shape: initializer cannot contain fallible Map upsert"
              let (newLeaves, okInsert) ←
                mapUpsertLeavesV1 bv.leaves iv.expr vv.expr
              acc ← pushCheck acc { kind := .overflow, condition := okInsert }
              let tv := mkMapLeaves newLeaves
                (1 + bv.expandedNodes + iv.expandedNodes + vv.expandedNodes)
              acc := { acc with env := envInsert acc.env vd.valueId tv }
            else do
              unless isArrayValue bv || isBytesValue bv do
                planError
                  "unsupported Soroban semantic shape: IndexSet base must be an Array UInt64 or Map UInt64 aggregate"
              let i ← literalIndexNatV1 iv
              unless i < bv.leaves.size do
                planError "unsupported Soroban semantic shape: Array IndexSet index out of range"
              unless !isAggregateValue vv && vv.ty == numericTy do
                planError
                  "unsupported Soroban semantic shape: Array IndexSet value must be scalar UInt64"
              let newLeaves := bv.leaves.set! i vv.expr
              let tv :=
                if isBytesValue bv then
                  mkBytesLeaves newLeaves (1 + bv.expandedNodes + vv.expandedNodes)
                else
                  mkArrayLeaves newLeaves (1 + bv.expandedNodes + vv.expandedNodes)
              acc := { acc with env := envInsert acc.env vd.valueId tv }
    | .fieldGet baseId fieldIndex => do
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: fieldGet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: fieldGet base undefined"
            unless isNamedValue bv do
              planError
                "unsupported Soroban semantic shape: fieldGet base must be a named Struct"
            let i := fieldIndex.toNat
            unless i < bv.leaves.size do
              planError "unsupported Soroban semantic shape: fieldGet leaf index out of range"
            let some leaf := bv.leaves[i]? |
              planError "unsupported Soroban semantic shape: fieldGet leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := numericTy
              expr := leaf
              expandedNodes := 1
            } }
    | .fieldSet baseId fieldIndex valueId => do
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: fieldSet must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: fieldSet base undefined"
            unless isNamedValue bv do
              planError
                "unsupported Soroban semantic shape: fieldSet base must be a named Struct"
            let vv ← match envLookup acc.env valueId with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: fieldSet value undefined"
            unless !isAggregateValue vv && (vv.ty == .uint64 || vv.ty == .int64) do
              planError
                "unsupported Soroban semantic shape: fieldSet value must be scalar UInt64/Int64"
            let i := fieldIndex.toNat
            unless i < bv.leaves.size do
              planError "unsupported Soroban semantic shape: fieldSet leaf index out of range"
            let newLeaves := bv.leaves.set! i vv.expr
            acc := { acc with
              env := envInsert acc.env vd.valueId
                (mkNamedLeaves newLeaves (bv.expandedNodes + vv.expandedNodes + 1)) }
    | .variantTag baseId => do
        match instr.result with
        | none => planError "unsupported Soroban semantic shape: variantTag must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none => planError "unsupported Soroban semantic shape: variantTag base undefined"
            unless isOptionValue bv || isNamedValue bv do
              planError
                "unsupported Soroban semantic shape: variantTag base must be Option UInt64 or named Enum"
            let some tag := bv.leaves[0]? |
              planError "unsupported Soroban semantic shape: variantTag Option tag leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := .uint64
              expr := tag
              expandedNodes := 1
            } }
    | .variantPayload baseId variantIndex payloadIndex => do
        match instr.result with
        | none =>
            planError "unsupported Soroban semantic shape: variantPayload must produce a value"
        | some vd =>
            let bv ← match envLookup acc.env baseId with
              | some v => pure v
              | none =>
                  planError "unsupported Soroban semantic shape: variantPayload base undefined"
            unless isOptionValue bv || isNamedValue bv do
              planError
                "unsupported Soroban semantic shape: variantPayload base must be Option UInt64 or named Enum"
            if isOptionValue bv then
              if variantIndex.toNat == 0 then
                planError
                  "unsupported Soroban semantic shape: variantPayload of Option.none is empty"
              unless variantIndex.toNat == 1 && payloadIndex.toNat == 0 do
                planError
                  "unsupported Soroban semantic shape: variantPayload Option some requires (variant 1, payload 0)"
            let payloadIdx :=
              if isOptionValue bv then 1 else 1 + payloadIndex.toNat
            let some payload := bv.leaves[payloadIdx]? |
              planError
                "unsupported Soroban semantic shape: variantPayload payload leaf missing"
            acc := { acc with env := envInsert acc.env vd.valueId {
              ty := numericTy
              expr := payload
              expandedNodes := 1
            } }
    | .checkedCast .. =>
        planError "unsupported Soroban semantic shape: checkedCast is outside S0"
    | .commit .. | .emit .. =>
        planError "unsupported Soroban semantic shape: commit/emit is outside S0"
  pure acc

private def decodeSwitchCaseValue
    (types : SorobanTypeClosureV1) (typeId : TypeIdV1) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if isBoolType types typeId then
    let b ← decodeBoolLiteralBit sorobanPlanErr "Soroban" bytes
    pure (if b then 1 else 0)
  else if isUInt32Type types typeId then
    decodeUInt32LiteralLe sorobanPlanErr "Soroban" bytes
  else if isUInt64Type types typeId || isInt64Type types typeId then
    decodeUInt64LiteralLe sorobanPlanErr "Soroban" bytes
  else
    planError
      "unsupported Soroban semantic shape: switch case type is outside UInt64/Int64/UInt32/Bool"

private partial def regionHasReturn (body : Array Statement) : Bool :=
  body.any fun s =>
    match s with
    | .returnValue _ | .returnAggregate _ | .returnNone => true
    | .ifThenElse _ t e => regionHasReturn t || regionHasReturn e
    | .switchOn _ cases d =>
        cases.any (fun (_, b) => regionHasReturn b) || regionHasReturn d
    | .forLoop _ _ _ _ _ body => regionHasReturn body
    | _ => false

private def returnStmts (ret? : Option TypedExpr) : Array Statement :=
  match ret? with
  | none => #[.returnNone]
  | some tv =>
      if !tv.leaves.isEmpty then #[.returnAggregate tv.leaves]
      else #[.returnValue tv.expr]

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
    (types : SorobanTypeClosureV1) (callable : CallableV1) : CompileResult Unit := do
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless block.params.size == 1 do
        planError
          "unsupported Soroban semantic shape: loop header must carry exactly one block param"
      let some p := block.params[0]? |
        planError
          "unsupported Soroban semantic shape: loop header must carry exactly one block param"
      unless isUInt64Type types p.typeId || isInt64Type types p.typeId do
        planError
          "unsupported Soroban semantic shape: loop induction must be public UInt64/Int64"
      unless isLoopHeaderV1 callable.loopBounds block.id.toNat do
        planError
          "unsupported Soroban semantic shape: block parameters require a loopBounds header entry"
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      planError "unsupported Soroban semantic shape: loopBounds header is out of range"
    unless header.params.size == 1 do
      planError
        "unsupported Soroban semantic shape: loopBounds header must have one block param"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      planError
        "unsupported Soroban semantic shape: loopBounds backEdgeFrom is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          planError
            "unsupported Soroban semantic shape: loop latch must jump to its header with one arg"
    | _ =>
        planError
          "unsupported Soroban semantic shape: loop latch terminator must be a jump"
    unless lb.maxIterations.toNat ≤ 4096 do
      planError
        "unsupported Soroban semantic shape: loop maxIterations exceeds the wire ceiling"

private def flushRegion
    (layout : StateLayout) (acc : BodyAccum) : Array Statement × BodyAccum :=
  let stores := overlayFinalStores acc.overlay layout
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
      | none => planError "unsupported Soroban semantic shape: return value undefined"

private partial def emitRegion
    (data : SemanticProgramDataV1) (types : SorobanTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1)
    (numericTy : ExprType) (layout : StateLayout)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (enclosingHeader : Option Nat)
    (fuel : Nat) (blockId : Nat) (acc0 : BodyAccum) :
    CompileResult (Array Statement × BodyAccum × Option TypedExpr × RegionCont) := do
  match fuel with
  | 0 =>
      planError "unsupported Soroban semantic shape: CFG walk fuel exhausted"
  | fuel' + 1 => do
      let some block := callable.blocks[blockId]? |
        planError "unsupported Soroban semantic shape: missing CFG block"
      unless block.id.toNat == blockId do
        planError "unsupported Soroban semantic shape: block id must match index"
      let acc ←
        lowerBlockInstructions data types idx callable numericTy layout
          allowStateRead allowStateWrite forbidChecks inlineDepth block acc0
      match block.terminator with
      | .return_ value => do
          let (stmts, acc) := flushRegion layout acc
          let ret? ← lookupReturn acc value
          pure (stmts ++ returnStmts ret?, acc, ret?, .closed)
      | .jump target => do
          let targetId := target.blockId.toNat
          if enclosingHeader == some targetId then
            unless target.args.size == 1 do
              planError
                "unsupported Soroban semantic shape: loop latch must carry exactly one induction arg"
            let (stmts, acc) := flushRegion layout acc
            let some updateVid := target.args[0]? |
              planError
                "unsupported Soroban semantic shape: loop latch must carry exactly one induction arg"
            let update ← match envLookup acc.env updateVid with
              | some v => requireTy v numericTy "loop update"
              | none =>
                  planError "unsupported Soroban semantic shape: loop update undefined"
            pure (stmts, acc, none, .latch update)
          else if isLoopHeaderV1 callable.loopBounds targetId then
            let some lb := findLoopBoundV1 callable.loopBounds targetId |
              planError "unsupported Soroban semantic shape: missing loopBounds for loop header"
            unless target.args.size == 1 do
              planError
                "unsupported Soroban semantic shape: loop pre-header must jump with one start arg"
            let (preStmts, acc) := flushRegion layout acc
            let some startVid := target.args[0]? |
              planError
                "unsupported Soroban semantic shape: loop pre-header must jump with one start arg"
            let initial ← match envLookup acc.env startVid with
              | some v => requireTy v numericTy "loop start"
              | none =>
                  planError "unsupported Soroban semantic shape: loop start value undefined"
            let some header := callable.blocks[targetId]? |
              planError "unsupported Soroban semantic shape: loop header block is missing"
            unless header.params.size == 1 do
              planError
                "unsupported Soroban semantic shape: loop header must carry exactly one block param"
            let some inductionParam := header.params[0]? |
              planError
                "unsupported Soroban semantic shape: loop header must carry exactly one block param"
            let varTemp := acc.nextTemp
            let acc :=
              { acc with
                nextTemp := acc.nextTemp + 1
                env := envInsert acc.env inductionParam.valueId {
                  ty := numericTy
                  expr := .temp varTemp
                  expandedNodes := 1
                } }
            let acc ←
              lowerBlockInstructions data types idx callable numericTy layout
                allowStateRead allowStateWrite forbidChecks inlineDepth header acc
            unless acc.overlay.entries.isEmpty do
              planError
                "unsupported Soroban semantic shape: loop header may not contain effect instructions"
            match header.terminator with
            | .branch condId thenT elseT => do
                unless thenT.args.isEmpty && elseT.args.isEmpty do
                  planError
                    "unsupported Soroban semantic shape: loop branch targets must carry empty args"
                let cond ← match envLookup acc.env condId with
                  | some v => requireTy v .bool "loop condition"
                  | none =>
                      planError
                        "unsupported Soroban semantic shape: loop condition undefined"
                let (bodyStmts, acc1, _bodyRet, bodyCont) ←
                  emitRegion data types idx callable numericTy layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    (some targetId) fuel' thenT.blockId.toNat acc
                let update ← match bodyCont with
                  | .latch e => pure e
                  | .closed =>
                      planError
                        "unsupported Soroban semantic shape: loop body closed without a latch"
                  | .join _ =>
                      planError
                        "unsupported Soroban semantic shape: loop body must end at its latch jump"
                let forStmt :=
                  Statement.forLoop varTemp initial cond update
                    lb.maxIterations.toNat bodyStmts
                let (rest, acc2, restRet, restCont) ←
                  emitRegion data types idx callable numericTy layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' elseT.blockId.toNat acc1
                pure (preStmts ++ #[forStmt] ++ rest, acc2, restRet, restCont)
            | _ =>
                planError
                  "unsupported Soroban semantic shape: loop header terminator must be a branch"
          else
            unless target.args.isEmpty do
              planError
                "unsupported Soroban semantic shape: jump args / block-param phi are outside S0"
            let (stmts, acc) := flushRegion layout acc
            pure (stmts, acc, none, .join targetId)
      | .branch condId thenT elseT => do
          unless thenT.args.isEmpty && elseT.args.isEmpty do
            planError
              "unsupported Soroban semantic shape: branch targets must carry empty args"
          let cond ← match envLookup acc.env condId with
            | some v => requireTy v .bool "branch condition"
            | none =>
                planError "unsupported Soroban semantic shape: branch condition undefined"
          let (preStmts, acc) := flushRegion layout acc
          let (thenStmts, acc1, thenRet, thenCont) ←
            emitRegion data types idx callable numericTy layout
              allowStateRead allowStateWrite forbidChecks inlineDepth
              enclosingHeader fuel' thenT.blockId.toNat acc
          match thenCont with
          | .latch _ =>
              planError
                "unsupported Soroban semantic shape: latch jump is only valid as a loop body end"
          | .closed | .join _ => pure ()
          let thenJoin := joinOf thenCont
          if thenJoin == some elseT.blockId.toNat then
            let (rest, acc2, restRet, restCont) ←
              emitRegion data types idx callable numericTy layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' elseT.blockId.toNat acc1
            pure
              (preStmts ++ #[.ifThenElse cond thenStmts #[]] ++ rest,
                acc2, thenRet <|> restRet, restCont)
          else
            let (elseStmts, acc2, elseRet, elseCont) ←
              emitRegion data types idx callable numericTy layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' elseT.blockId.toNat acc1
            match elseCont with
            | .latch _ =>
                planError
                  "unsupported Soroban semantic shape: latch jump is only valid as a loop body end"
            | .closed | .join _ => pure ()
            let elseJoin := joinOf elseCont
            match thenJoin, elseJoin with
            | some j1, some j2 => do
                unless j1 == j2 do
                  planError
                    "unsupported Soroban semantic shape: branch arms converge on divergent joins"
                let (rest, acc3, restRet, restCont) ←
                  emitRegion data types idx callable numericTy layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' j1 acc2
                pure
                  (preStmts ++ #[.ifThenElse cond thenStmts elseStmts] ++ rest,
                    acc3, thenRet <|> elseRet <|> restRet, restCont)
            | none, none =>
                pure
                  (preStmts ++ #[.ifThenElse cond thenStmts elseStmts],
                    acc2, thenRet <|> elseRet, .closed)
            | some j, none | none, some j => do
                let (rest, acc3, restRet, restCont) ←
                  emitRegion data types idx callable numericTy layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' j acc2
                pure
                  (preStmts ++ #[.ifThenElse cond thenStmts elseStmts] ++ rest,
                    acc3, thenRet <|> elseRet <|> restRet, restCont)
      | .switch scrutId cases defaultTarget => do
          let some defaultT := defaultTarget |
            planError
              "unsupported Soroban semantic shape: switch must carry a default target"
          unless !cases.isEmpty do
            planError "unsupported Soroban semantic shape: switch cases must be nonempty"
          let scrutVal ← match envLookup acc.env scrutId with
            | some v => pure v
            | none =>
                planError "unsupported Soroban semantic shape: switch scrutinee undefined"
          unless defaultT.args.isEmpty do
            planError
              "unsupported Soroban semantic shape: switch default args / block-param phi are outside S0"
          if isPrincipalValue scrutVal then
            -- N-A1: String 9-leaf identity match desugars to leaf-wise eq +
            -- nested if (Plan `switchOn` stays UInt64-case only).
            let (preStmts, acc) := flushRegion layout acc
            let mut caseArms : Array (Expr × Array Statement) := #[]
            let mut accA := acc
            let mut joinAcc : Option Nat := none
            let mut retAcc : Option TypedExpr := none
            for switchCase in cases do
              unless switchCase.target.args.isEmpty do
                planError
                  "unsupported Soroban semantic shape: switch case args / block-param phi are outside S0"
              let caseLeaves ← decodePrincipalLiteralLeavesV1 switchCase.valueBytes
              unless caseLeaves.size == scrutVal.leaves.size do
                planError
                  "unsupported Soroban semantic shape: String match case leaf count mismatch"
              let mut cond : Expr :=
                .compare .eq scrutVal.leaves[0]! caseLeaves[0]!
              for i in [1:principalLeafCountV1] do
                cond := .boolAnd cond
                  (.compare .eq scrutVal.leaves[i]! caseLeaves[i]!)
              let (body, acc1, armRet, armCont) ←
                emitRegion data types idx callable numericTy layout
                  allowStateRead allowStateWrite forbidChecks inlineDepth
                  enclosingHeader fuel' switchCase.target.blockId.toNat accA
              caseArms := caseArms.push (cond, body)
              accA := acc1
              retAcc := retAcc <|> armRet
              match armCont, joinAcc with
              | .closed, _ => pure ()
              | .latch _, _ =>
                  planError
                    "unsupported Soroban semantic shape: latch jump is only valid as a loop body end"
              | .join j, none => joinAcc := some j
              | .join j, some j0 =>
                  unless j == j0 do
                    planError
                      "unsupported Soroban semantic shape: switch arms converge on divergent joins"
            let (defaultBody, acc2, defaultRet, defaultCont) ←
              emitRegion data types idx callable numericTy layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' defaultT.blockId.toNat accA
            retAcc := retAcc <|> defaultRet
            match defaultCont, joinAcc with
            | .closed, _ => pure ()
            | .latch _, _ =>
                planError
                  "unsupported Soroban semantic shape: latch jump is only valid as a loop body end"
            | .join j, none => joinAcc := some j
            | .join j, some j0 =>
                unless j == j0 do
                  planError
                    "unsupported Soroban semantic shape: switch arms converge on divergent joins"
            let mut nested : Array Statement := defaultBody
            let mut i := caseArms.size
            while i > 0 do
              i := i - 1
              let (cond, body) := caseArms[i]!
              nested := #[.ifThenElse cond body nested]
            match joinAcc with
            | none =>
                pure (preStmts ++ nested, acc2, retAcc, .closed)
            | some j => do
                let (rest, acc3, restRet, restCont) ←
                  emitRegion data types idx callable numericTy layout
                    allowStateRead allowStateWrite forbidChecks inlineDepth
                    enclosingHeader fuel' j acc2
                pure
                  (preStmts ++ nested ++ rest, acc3,
                    retAcc <|> restRet, restCont)
          else if !scrutVal.leaves.isEmpty then
            planError "unsupported Soroban semantic shape: switch scrutinee must be scalar"
          else
          let scrut := scrutVal.expr
          let (preStmts, acc) := flushRegion layout acc
          let mut caseBodies : Array (UInt64 × Array Statement) := #[]
          let mut accA := acc
          let mut joinAcc : Option Nat := none
          let mut retAcc : Option TypedExpr := none
          for switchCase in cases do
            unless switchCase.target.args.isEmpty do
              planError
                "unsupported Soroban semantic shape: switch case args / block-param phi are outside S0"
            let caseValue ←
              decodeSwitchCaseValue types switchCase.typeId switchCase.valueBytes
            let (body, acc1, armRet, armCont) ←
              emitRegion data types idx callable numericTy layout
                allowStateRead allowStateWrite forbidChecks inlineDepth
                enclosingHeader fuel' switchCase.target.blockId.toNat accA
            caseBodies := caseBodies.push (caseValue, body)
            accA := acc1
            retAcc := retAcc <|> armRet
            match armCont, joinAcc with
            | .closed, _ => pure ()
            | .latch _, _ =>
                planError
                  "unsupported Soroban semantic shape: latch jump is only valid as a loop body end"
            | .join j, none => joinAcc := some j
            | .join j, some j0 =>
                unless j == j0 do
                  planError
                    "unsupported Soroban semantic shape: switch arms converge on divergent joins"
          let (defaultBody, acc2, defaultRet, defaultCont) ←
            emitRegion data types idx callable numericTy layout
              allowStateRead allowStateWrite forbidChecks inlineDepth
              enclosingHeader fuel' defaultT.blockId.toNat accA
          retAcc := retAcc <|> defaultRet
          match defaultCont, joinAcc with
          | .closed, _ => pure ()
          | .latch _, _ =>
              planError
                "unsupported Soroban semantic shape: latch jump is only valid as a loop body end"
          | .join j, none => joinAcc := some j
          | .join j, some j0 =>
              unless j == j0 do
                planError
                  "unsupported Soroban semantic shape: switch arms converge on divergent joins"
          let switchStmt := Statement.switchOn scrut caseBodies defaultBody
          match joinAcc with
          | none =>
              pure (preStmts.push switchStmt, acc2, retAcc, .closed)
          | some j => do
              let (rest, acc3, restRet, restCont) ←
                emitRegion data types idx callable numericTy layout
                  allowStateRead allowStateWrite forbidChecks inlineDepth
                  enclosingHeader fuel' j acc2
              pure
                (preStmts.push switchStmt ++ rest, acc3,
                  retAcc <|> restRet, restCont)
      | .trap .. =>
          planError "unsupported Soroban semantic shape: trap terminators are outside S0"
      | .revert .. =>
          planError
            "unsupported Soroban semantic shape: revert in CFG arms is outside S0"

private def lowerInstructions
    (data : SemanticProgramDataV1) (types : SorobanTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1)
    (numericTy : ExprType) (layout : StateLayout)
    (allowStateRead allowStateWrite : Bool)
    (forbidChecks : Bool) (inlineDepth : Nat)
    (acc0 : BodyAccum) :
    CompileResult (BodyAccum × Option TypedExpr × Bool) := do
  unless callable.blocks.size == 1 do
    planError "unsupported Soroban semantic shape: each callable must have exactly one block"
  unless callable.loopBounds.isEmpty do
    planError "unsupported Soroban semantic shape: loopBounds are outside S0"
  unless callable.entryBlock.toNat == 0 do
    planError "unsupported Soroban semantic shape: entryBlock must be 0"
  let some block := callable.blocks[0]? |
    planError "unsupported Soroban semantic shape: missing entry block"
  let acc ←
    lowerBlockInstructions data types idx callable numericTy layout
      allowStateRead allowStateWrite forbidChecks inlineDepth block acc0
  match block.terminator with
  | .return_ value => do
      let ret? ← lookupReturn acc value
      pure (acc, ret?, false)
  | .revert errorId args => do
      unless args.isEmpty do
        planError "unsupported Soroban semantic shape: revert requires zero-payload args"
      if forbidChecks then
        planError "unsupported Soroban semantic shape: initializer cannot contain fallible checks"
      let acc ← pushCheck acc
        { kind := .terminalRevert errorId.toNat, condition := .litBool false }
      pure (acc, none, true)
  | .jump .. | .branch .. | .switch .. | .trap .. =>
      planError "unsupported Soroban semantic shape: multi-block/trap terminators are outside S0"

private def seedParamEnv
    (typeDecls : Array TypeDeclV1) (types : SorobanTypeClosureV1)
    (callable : CallableV1) :
    CompileResult (ValueEnv × Array String) := do
  let mut env : ValueEnv := { entries := #[] }
  let mut names : Array String := #[]
  let mut i : Nat := 0
  for p in callable.params do
    unless p.visibility == .public_ do
      planError "unsupported Soroban semantic shape: parameters must be public"
    unless isIdentifier p.name do
      planError s!"parameter '{p.name}' is not a safe identifier"
    if isAnonymousOptionTypeIdV1 typeDecls p.typeId then
      match typeDecls[p.typeId.toNat]? with
      | some { shape := .option elTid, name := none, .. } =>
          unless isUInt64Type types elTid || isInt64Type types elTid do
            planError
              "unsupported Soroban semantic shape: Option param payload must be UInt64 or Int64"
          let tagName := p.name ++ "_tag"
          let pName := p.name ++ "_p0"
          unless isIdentifier tagName do
            planError s!"parameter '{tagName}' is not a safe identifier"
          unless isIdentifier pName do
            planError s!"parameter '{pName}' is not a safe identifier"
          names := names.push tagName |>.push pName
          env := envInsert env p.valueId
            (mkOptionLeaves #[.param i, .param (i + 1)] 2)
          i := i + 2
      | _ =>
          planError
            "unsupported Soroban semantic shape: Option params require anonymous Option UInt64/Int64"
    else if isUInt256Type types p.typeId then
      planError (uint256PlumbingFc "param")
    else if types.isNamedAggregate p.typeId then
      let leafSpecs ← flattenNamedLeafSpecsV1 typeDecls types p.typeId p.name
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        names := names.push leafName
        leafExprs := leafExprs.push (.param i)
        i := i + 1
      env := envInsert env p.valueId (mkNamedLeaves leafExprs leafExprs.size)
    else if types.isContainer p.typeId then
      match typeDecls[p.typeId.toNat]? with
      | some { shape := .bytes len, .. } =>
          let n := len.toNat
          unless 1 ≤ n && n ≤ 8 do
            planError
              s!"parameter '{p.name}' Bytes N must flatten to 1..8 leaves (got {n})"
          let mut leafExprs : Array Expr := #[]
          for j in [0:n] do
            let leafName := p.name ++ "_" ++ toString j
            unless isIdentifier leafName do
              planError s!"parameter '{leafName}' is not a safe identifier"
            names := names.push leafName
            leafExprs := leafExprs.push (.param i)
            i := i + 1
          env := envInsert env p.valueId (mkBytesLeaves leafExprs leafExprs.size)
      | some { shape := .array elTid len, .. } =>
          unless isUInt64Type types elTid || isInt64Type types elTid do
            planError
              "unsupported Soroban semantic shape: Array param element must be UInt64 or Int64"
          let n := len.toNat
          unless 1 ≤ n && n ≤ 8 do
            planError
              s!"parameter '{p.name}' Array N must flatten to 1..8 leaves (got {n})"
          let mut leafExprs : Array Expr := #[]
          for j in [0:n] do
            let leafName := p.name ++ "_" ++ toString j
            unless isIdentifier leafName do
              planError s!"parameter '{leafName}' is not a safe identifier"
            names := names.push leafName
            leafExprs := leafExprs.push (.param i)
            i := i + 1
          env := envInsert env p.valueId (mkArrayLeaves leafExprs leafExprs.size)
      | some { shape := .map keyTid valTid, name := none, .. } =>
          unless (isUInt64Type types keyTid && isUInt64Type types valTid) ||
              (isInt64Type types keyTid && isInt64Type types valTid) do
            planError
              "unsupported Soroban semantic shape: Map param must be Map UInt64 UInt64 or Map Int64 Int64"
          let n := mapPilotLeafCountV1
          let mut leafExprs : Array Expr := #[]
          for j in [0:n] do
            let leafName := p.name ++ "_" ++ toString j
            unless isIdentifier leafName do
              planError s!"parameter '{leafName}' is not a safe identifier"
            names := names.push leafName
            leafExprs := leafExprs.push (.param i)
            i := i + 1
          env := envInsert env p.valueId (mkMapLeaves leafExprs leafExprs.size)
      | _ =>
          planError
            "unsupported Soroban semantic shape: nested/unknown container params stay fail closed"
    else if isWireIdentityType types p.typeId then
      let leafSpecs ← flattenPrincipalLeafNamesV1 p.name
      let mut leafExprs : Array Expr := #[]
      for leafName in leafSpecs do
        names := names.push leafName
        leafExprs := leafExprs.push (.param i)
        i := i + 1
      env := envInsert env p.valueId (mkPrincipalLeaves leafExprs leafExprs.size)
    else
      requirePublicUInt64OrInt64Param sorobanPlanErr types "callable" p
      let ty := if isInt64Type types p.typeId then ExprType.int64 else .uint64
      env := envInsert env p.valueId {
        ty
        expr := .param i
        expandedNodes := 1
      }
      names := names.push p.name
      i := i + 1
  unless names.size ≤ maxParams do
    planError "unsupported Soroban semantic shape: parameter count exceeds limit"
  pure (env, names)

private def lowerCallableBody
    (data : SemanticProgramDataV1) (types : SorobanTypeClosureV1)
    (idx : CallableIndex) (callable : CallableV1) (numericTy : ExprType)
    (layout : StateLayout)
    (allowStateRead allowStateWrite forbidChecks initialStateDefaults : Bool) :
    CompileResult
      (Array String × Array Check × Array (Nat × Expr) ×
        Option TypedExpr × Bool × Array Sha256Site × Array Sha256BytesSite ×
        Array Statement) := do
  let (env0, paramNames) ← seedParamEnv data.types types callable
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
      let isNm :=
        match layout.isNamedOf[st.id.toNat]? with
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
        else if isNm then
          overlay0 := overlayInsert overlay0 st.id (mkNamedLeaves zeros phys.size)
        else if isWireIdentityType types st.typeId then
          overlay0 := overlayInsert overlay0 st.id (mkPrincipalLeaves zeros phys.size)
        else if isAnonymousBytesTypeIdV1 data.types st.typeId then
          overlay0 := overlayInsert overlay0 st.id (mkBytesLeaves zeros phys.size)
        else
          overlay0 := overlayInsert overlay0 st.id (mkArrayLeaves zeros phys.size)
  let acc0 : BodyAccum := emptyBodyAccum env0 overlay0
  if callable.blocks.size == 1 then
    let (acc, ret?, endedRevert) ←
      lowerInstructions data types idx callable numericTy layout
        allowStateRead allowStateWrite forbidChecks 0 acc0
    let stores := overlayFinalStores acc.overlay layout
    pure (paramNames, acc.checks, stores, ret?, endedRevert, acc.sha256Sites,
      acc.sha256BytesSites, #[])
  else
    unless callable.entryBlock.toNat == 0 do
      planError "unsupported Soroban semantic shape: entryBlock must be 0"
    unless callable.loopBounds.isEmpty do
      validateCallableLoopsV1 types callable
    let (stmts, acc, ret?, cont) ←
      emitRegion data types idx callable numericTy layout
        allowStateRead allowStateWrite forbidChecks 0 none
        callable.blocks.size callable.entryBlock.toNat acc0
    unless cont == .closed do
      planError "unsupported Soroban semantic shape: CFG walk ended without a return"
    let stmts :=
      if regionHasReturn stmts then
        stmts
      else
        match ret? with
        | none => stmts
        | some tv =>
            if !tv.leaves.isEmpty then
              stmts.push (.returnAggregate tv.leaves)
            else
              stmts.push (.returnValue tv.expr)
    pure (paramNames, acc.checks, #[], none, false, acc.sha256Sites,
      acc.sha256BytesSites, stmts)

private def makePlanFromSemanticDataV1
    (data : SemanticProgramDataV1) (programName : String)
    (sourceHash semanticHash : String) : CompileResult Plan := do
  unless isIdentifier programName do
    planError s!"program name '{programName}' is not a safe identifier"
  unless data.events.isEmpty do
    planError "unsupported Soroban semantic shape: events table must be empty"
  for err in data.errors do
    unless err.fields.isEmpty do
      planError "unsupported Soroban semantic shape: declared errors must have zero payload fields"
  unless data.invariants.isEmpty do
    planError "unsupported Soroban semantic shape: invariants are outside S0"
  let types ← validateSorobanTypeClosureV1 data.types
  for c in data.constants do
    unless isInt64Type types c.typeId || isUInt64Type types c.typeId ||
        isUInt32Type types c.typeId || isBoolType types c.typeId ||
        isStringType types c.typeId do
      planError
        "unsupported Soroban semantic shape: constant is not admitted UInt64/Int64/UInt32/Bool/String"
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
  let numericTy := numericTyOf signedNumeric
  -- States: public UInt64 or Int64, Array UInt64 N flattened to N leaves,
  -- Option UInt64 flattened to tag+payload, or Map UInt64 UInt64
  -- flattened to 24 occ/key/val leaves.
  let layout ← makeStateLayoutV1 data types signedNumeric
  let states := layout.states
  let mut pureFns : Array (CallableIdV1 × CallableV1) := #[]
  for c in data.callables do
    if c.kind == .pureFn then
      pureFns := pureFns.push (c.id, c)
  let idx : CallableIndex := { pureFns }
  let mut initializer : Option PlanInit := none
  let mut entries : Array PlanEntry := #[]
  let mut views : Array PlanView := #[]
  for callable in data.callables do
    match callable.kind with
    | .pureFn => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Soroban semantic shape: pureFn requires a name"
        unless isIdentifier name do
          planError s!"pureFn '{name}' is not a safe identifier"
        let rk ← resultKindOf data.types types callable.result.typeId s!"pureFn '{name}'"
          signedNumeric false
        unless callable.result.visibility == .public_ do
          planError s!"pureFn '{name}' result must be public"
        let (_params, _checks, stores, ret?, endedRevert, sha256Sites, sha256BytesSites, body) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := false) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false)
        unless sha256Sites.isEmpty do
          planError s!"pureFn '{name}' must not call pf.crypto.sha256"
        unless sha256BytesSites.isEmpty do
          planError s!"pureFn '{name}' must not call pf.crypto.sha256Bytes"
        unless body.isEmpty do
          planError s!"pureFn '{name}' control flow is outside S0"
        unless stores.isEmpty do
          planError s!"pureFn '{name}' cannot write state"
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
            planError s!"pureFn '{name}' non-Unit revert-only result is outside S0"
        | .uint64, none, false | .int64, none, false | .bool, none, false =>
            planError s!"pureFn '{name}' non-Unit return is missing"
        | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
            planError s!"pureFn '{name}' revert path cannot carry a return value"
        | .aggregate _, _, _ =>
            planError s!"pureFn '{name}' aggregate return is outside S0"
    | .initializer => do
        unless initializer.isNone do
          planError "unsupported Soroban semantic shape: at most one initializer"
        let name := callable.name.getD "initialize"
        unless isIdentifier name do
          planError s!"initializer name '{name}' is not a safe identifier"
        unless isUnitType types callable.result.typeId do
          planError "unsupported Soroban semantic shape: initializer result must be Unit"
        unless callable.result.visibility == .public_ do
          planError "unsupported Soroban semantic shape: initializer result must be public"
        let (params, checks, stores, ret?, endedRevert, sha256Sites, sha256BytesSites, body) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := true) (forbidChecks := true)
            (initialStateDefaults := true)
        unless body.isEmpty do
          planError "unsupported Soroban semantic shape: initializer control flow is outside S0"
        if endedRevert then
          planError "unsupported Soroban semantic shape: initializer cannot revert"
        unless checks.isEmpty do
          planError "unsupported Soroban semantic shape: initializer cannot contain fallible checks"
        unless ret?.isNone do
          planError "unsupported Soroban semantic shape: initializer must return Unit"
        initializer := some { name, params, stores, sha256Sites, sha256BytesSites }
    | .entry => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Soroban semantic shape: entry requires a name"
        unless isIdentifier name do
          planError s!"entry '{name}' is not a safe identifier"
        let rk ← resultKindOf data.types types callable.result.typeId s!"entry '{name}'"
          signedNumeric true
        unless callable.result.visibility == .public_ do
          planError s!"entry '{name}' result must be public"
        let (params, checks, stores, ret?, endedRevert, sha256Sites, sha256BytesSites, body) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := true) (forbidChecks := false)
            (initialStateDefaults := false)
        if !body.isEmpty then
          entries := entries.push {
            name, params, resultKind := rk, checks, stores := #[]
            result? := none, leaves := #[], leafIsInt := #[], terminalRevert := endedRevert
            sha256Sites, sha256BytesSites, body
          }
        else do
        let (result?, leaves, leafIsInt) ← match rk, ret?, endedRevert with
          | .unit, none, _ => pure (none, #[], #[])
          | .unit, some _, _ =>
              planError s!"entry '{name}' Unit result must not return a value"
          | .uint64, some tv, false =>
              let e ← requireTy tv .uint64 s!"entry '{name}' result"
              pure (some e, #[], #[])
          | .int64, some tv, false =>
              let e ← requireTy tv .int64 s!"entry '{name}' result"
              pure (some e, #[], #[])
          | .bool, some tv, false =>
              let e ← requireTy tv .bool s!"entry '{name}' result"
              pure (some e, #[], #[])
          | .uint64, none, true | .int64, none, true | .bool, none, true =>
              pure (none, #[], #[])
          | .uint64, none, false | .int64, none, false | .bool, none, false =>
              planError s!"entry '{name}' non-Unit return is missing"
          | .uint64, some _, true | .int64, some _, true | .bool, some _, true =>
              planError s!"entry '{name}' revert path cannot carry a return value"
          | .aggregate n, some tv, false => do
              unless isAggregateValue tv && tv.leaves.size == n do
                planError
                  s!"entry '{name}' aggregate return must flatten to exactly {n} leaves"
              let some head := tv.leaves[0]? |
                planError s!"entry '{name}' aggregate return is empty"
              let marks ←
                match ← viewAggregateLeafIsIntV1 data.types types
                    callable.result.typeId signedNumeric with
                | some m =>
                    unless m.size == n do
                      planError
                        s!"entry '{name}' aggregate signedness length must match leaf count"
                    pure m
                | none =>
                    planError s!"entry '{name}' aggregate return type is not admitted"
              pure (some head, tv.leaves, marks)
          | .aggregate _, none, true =>
              planError s!"entry '{name}' revert path cannot carry an aggregate return"
          | .aggregate _, some _, true =>
              planError s!"entry '{name}' revert path cannot carry a return value"
          | .aggregate _, none, false =>
              planError s!"entry '{name}' aggregate return is missing"
        entries := entries.push {
          name, params, resultKind := rk, checks, stores
          result?, leaves, leafIsInt, terminalRevert := endedRevert, sha256Sites,
          sha256BytesSites
        }
    | .view => do
        let name ← match callable.name with
          | some n => pure n
          | none => planError "unsupported Soroban semantic shape: view requires a name"
        unless isIdentifier name do
          planError s!"view '{name}' is not a safe identifier"
        let rk ← resultKindOf data.types types callable.result.typeId s!"view '{name}'"
          signedNumeric true
        unless rk != .unit do
          planError s!"view '{name}' result must be UInt64, Int64, Bool, or a view-only aggregate"
        unless callable.result.visibility == .public_ do
          planError s!"view '{name}' result must be public"
        let (params, checks, stores, ret?, endedRevert, sha256Sites, sha256BytesSites, body) ←
          lowerCallableBody data types idx callable numericTy layout
            (allowStateRead := true) (allowStateWrite := false) (forbidChecks := false)
            (initialStateDefaults := false)
        unless body.isEmpty do
          planError s!"view '{name}' control flow is outside S0"
        if endedRevert then
          planError s!"view '{name}' cannot revert"
        unless stores.isEmpty do
          planError s!"view '{name}' cannot write state"
        unless sha256Sites.isEmpty do
          planError s!"view '{name}' must not call pf.crypto.sha256"
        unless sha256BytesSites.isEmpty do
          planError s!"view '{name}' must not call pf.crypto.sha256Bytes"
        unless checks.isEmpty do
          planError s!"view '{name}' cannot contain assert/revert/fallible checks (pure def only)"
        let tv ← match ret? with
          | some v => pure v
          | none => planError s!"view '{name}' must return a value"
        let (value, leaves, leafIsInt) ← match rk with
          | .uint64 => do
              let e ← requireTy tv .uint64 s!"view '{name}' result"
              pure (e, #[], #[])
          | .int64 => do
              let e ← requireTy tv .int64 s!"view '{name}' result"
              pure (e, #[], #[])
          | .bool => do
              let e ← requireTy tv .bool s!"view '{name}' result"
              pure (e, #[], #[])
          | .unit =>
              planError s!"view '{name}' result must be UInt64, Int64, Bool, or a view-only aggregate"
          | .aggregate n => do
              unless isAggregateValue tv && tv.leaves.size == n do
                planError
                  s!"view '{name}' aggregate return must flatten to exactly {n} leaves"
              let some head := tv.leaves[0]? |
                planError s!"view '{name}' aggregate return is empty"
              let marks ←
                match ← viewAggregateLeafIsIntV1 data.types types
                    callable.result.typeId signedNumeric with
                | some m =>
                    unless m.size == n do
                      planError
                        s!"view '{name}' aggregate signedness length must match leaf count"
                    pure m
                | none =>
                    planError s!"view '{name}' aggregate return type is not admitted"
              pure (head, tv.leaves, marks)
        views := views.push { name, params, resultKind := rk, value, leaves, leafIsInt }
    | .invariant =>
        planError "unsupported Soroban semantic shape: invariants are outside S0"
  unless entries.size > 0 || views.size > 0 do
    planError "unsupported Soroban semantic shape: at least one entry or view is required"
  pure {
    programName
    sourceHash
    semanticHash
    signedNumeric
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
        throw <| .invalidProgram "Soroban received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data artifactProgramName sourceHash semanticHash

private def digestHex (label : String)
    (digest : ProofForgeV2.Core.Common.Digest) : CompileResult String := do
  match ProofForgeV2.Core.Common.renderDigest digest with
  | .ok rendered => pure rendered
  | .error error => planError s!"{label} digest render failed: {error}"

def materializePlanFromCapabilityV1
    (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .soroban do
    throw <| .planInvariant .soroban "engineering capability kind is not Soroban"
  let compiled := ResolvedEngineeringBuildV1.compiledOf capability
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Soroban source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Soroban semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

def planFromCompiledSemanticV1 (compiled : CompiledSemanticV1) : CompileResult Plan := do
  let source := CompiledSemanticV1.semanticV1Of compiled
  let name := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceHash ← digestHex "Soroban source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHex "Soroban semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  makePlanFromSemanticV1 source name sourceHash semanticHash

end ProofForgeV2.Targets.Soroban
