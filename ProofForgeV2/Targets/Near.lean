import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.Targets.Near

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.near

def hostAbiVersion : String := "near-host-abi-v1"
def rawInputAbi : String := "packed-raw-little-endian-u64"
def stateLayoutDomain : String := "proof-forge-near-layout-v1:"
def layoutMarkerKey : String := "pf:v1:layout"

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive FailureAction where
  | trap
  | returnStatus
  deriving BEq, Inhabited, Repr

structure FailurePolicy where
  invalidInput : FailureAction
  uninitializedLayout : FailureAction
  corruptStorage : FailureAction
  arithmeticOverflow : FailureAction
  nonzeroDeposit : FailureAction
  deriving BEq, Inhabited, Repr

inductive ReceiptCommitPolicy where
  | rollbackOnTrap
  | retainWritesOnTrap
  deriving BEq, Inhabited, Repr

inductive MethodMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

inductive DepositPolicy where
  | requireZero
  | queryOnly
  deriving BEq, Inhabited, Repr

inductive HostImport where
  | input
  | registerLen
  | readRegister
  | storageRead
  | storageWrite
  | valueReturn
  | attachedDeposit
  | logUtf8
  | panicUtf8
  /-- NEAR async promise batch create (account_id_len, account_id_ptr → promise_idx).
      Only present on Plans that lower at least one schedule. -/
  | promiseBatchCreate
  /-- NEAR async function-call action on a promise batch. Deposit (u128) and gas
      are explicit zero placeholders in the emitted WAT — not economics. Only
      present on Plans that lower at least one schedule. -/
  | promiseBatchActionFunctionCall
  deriving BEq, Inhabited, Repr

structure ResourceLimits where
  maxArtifactStemBytes : Nat
  maxStateFields : Nat
  maxEntries : Nat
  maxParams : Nat
  maxBodyStatements : Nat
  maxExprDepth : Nat
  maxPlanNodes : Nat
  maxRecipeNodes : Nat
  maxMethodLocals : Nat
  wasmMemoryPages : Nat
  deriving BEq, Inhabited, Repr

structure StorageField where
  sourceId : Nat
  name : String
  key : String
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

structure StorageLayout where
  markerKey : String
  markerValue : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StorageField
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  inputOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  deriving BEq, Inhabited, Repr

/-- Unsigned comparison operators for the public-UInt64 comparison envelope. -/
inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  | param (inputOffset : Nat)
  | stateLoad (fieldIndex : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  | bitAnd (lhs rhs : Expr)
  | bitOr (lhs rhs : Expr)
  | bitXor (lhs rhs : Expr)
  /-- UInt64 left shift by a UInt32 count (zero-extended into the plan literal /
      temp surface). Count ≥ 64 and result overflow trap. -/
  | shl (lhs rhs : Expr)
  /-- UInt64 logical right shift by a UInt32 count. Count ≥ 64 traps. -/
  | shr (lhs rhs : Expr)
  | bitNot (operand : Expr)
  | boolNot (operand : Expr)
  /-- Strict Bool AND on 0/1 words (both sides always evaluate). -/
  | boolAnd (lhs rhs : Expr)
  /-- Strict Bool OR on 0/1 words (both sides always evaluate). -/
  | boolOr (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  | callFn (fnIndex : Nat) (args : Array Expr)
  /-- Mutable plan-local (loop induction). Index is method-local and unique per
      forLoop; IR lowering maps it to a stable Wasm temp rewritten each latch. -/
  | localTemp (index : Nat)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
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
  /-- Bounded for-loop recovered from a Semantic header/latch CFG. `varTemp` is
      the induction local; `condition`/`update`/`body` may mention `.localTemp
      varTemp`. `maxIterations` is the static Normalize bound enforced at the
      back edge after each completed body (bodies 1..N pass; the (N+1)-th body
      runs then traps; a `return` inside any body exits before the check). The
      latch update is unchecked `i+1` at WAT level because the body only runs
      while `i < end ≤ UInt64.max`. -/
  | forLoop (varTemp : Nat) (initial : Expr) (condition : Expr) (update : Expr)
      (maxIterations : Nat) (body : Array Statement)
  /-- Async fire-and-forget cross-contract schedule lowered to a NEAR promise.
      `receiver` is the callee QualifiedName components joined by `.` (verbatim;
      must pass the NEAR account-id grammar — no silent case fold). `method` is
      the last component. `args` are public UInt64 values serialized in the WAT
      as a deterministic little-endian payload (each arg 8-byte LE, in source
      order). Failure never propagates to the caller (matches schedule's
      no-response channel and NEAR promise semantics). Deposit/gas are not
      carried on the Plan; the WAT emits explicit zero placeholders. -/
  | promiseAccount (receiver : String) (method : String) (args : Array Expr)
  deriving BEq, Inhabited, Repr

/-- Result kind of a NEAR method export. Init is always unit; entry/view may be
UInt64 or Bool. Wire encoding for both scalar returns is still 8-byte little-
endian i64 (Bool is 0/1); the ABI JSON result type distinguishes them. -/
inductive MethodResultKind where
  | unit
  | uint64
  | bool
  deriving BEq, Inhabited, Repr

structure Method where
  name : String
  params : Array Param
  exactInputLen : Nat
  mode : MethodMode
  depositPolicy : DepositPolicy
  resultKind : MethodResultKind
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Pure function binding: public UInt64 params, UInt64-or-Bool result, and a
    pure statement body (no state/event effects). Indexed by Plan.fns. -/
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

/-- The NEAR-owned KV, raw ABI, method, and error policy for the supported
UInt64 (+ Bool result) fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  targetDescriptor : TargetDescriptor
  semanticSchemaVersion : Nat
  codegenProfile : String
  hostAbi : String
  inputAbi : String
  layoutDomain : String
  hostImports : Array HostImport
  failurePolicy : FailurePolicy
  commitPolicy : ReceiptCommitPolicy
  resourceLimits : ResourceLimits
  programName : String
  storage : StorageLayout
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  fns : Array FnBinding
  initializer : Method
  entries : Array Method
  -- No Inhabited: Plan embeds TargetDescriptor (opaque TargetId/profile).
  deriving BEq, Repr

structure RegisterLayout where
  input : Nat
  storage : Nat
  evicted : Nat
  deriving BEq, Inhabited, Repr

structure KeyRegion where
  key : String
  offset : Nat
  length : Nat
  deriving BEq, Inhabited, Repr

structure MemoryLayout where
  minPages : Nat
  inputOffset : Nat
  inputCapacity : Nat
  depositOffset : Nat
  valueOffset : Nat
  deriving BEq, Inhabited, Repr

inductive Operation where
  | checkInputLen (bytes : Nat)
  | requireZeroAttachedDeposit
  | requireLayoutAbsent (marker : KeyRegion)
  | requireLayout (marker : KeyRegion) (value : UInt64)
  | zeroState (field : KeyRegion)
  | literal (destination : Nat) (value : UInt64)
  | loadParam (destination inputOffset : Nat)
  | loadState (destination : Nat) (field : KeyRegion)
  | checkedAdd (destination lhs rhs : Nat)
  | checkedSub (destination lhs rhs : Nat)
  | storeState (field : KeyRegion) (value : Nat)
  | setLayout (marker : KeyRegion) (value : UInt64)
  | setReturnData (value : Nat)
  | compare (destination lhs rhs : Nat) (op : ComparisonOp)
  | assert (condition : Nat)
  | emitEvent (eventIndex : Nat) (args : Array Nat)
  | revertError (errorIndex : Nat) (args : Array Nat)
  | returnNone
  | ifRegion (condition : Nat) (thenOps elseOps : Array Operation)
  | switchRegion (scrutinee : Nat) (cases : Array (UInt64 × Array Operation))
      (defaultOps : Array Operation)
  /-- Structured bounded loop. Host/WAT re-run `condOps` each iteration;
      `varTemp` is seeded from `initial` then rewritten from `updateValue`
      after each body. `counterTemp` counts completed bodies; the static bound
      is checked at the back edge after the body (reference `noteBackEdge`
      placement): body runs first, then trap if `counterTemp ≥ maxIterations`,
      then increment + update. A body `return`/`revert` exits before the check. -/
  | forRegion (varTemp : Nat) (initial : Nat) (counterTemp : Nat)
      (maxIterations : Nat)
      (condOps : Array Operation) (condition : Nat)
      (bodyOps : Array Operation)
      (updateOps : Array Operation) (updateValue : Nat)
  | callFn (fnIndex : Nat) (destination : Nat) (args : Array Nat)
  | returnValue (value : Nat)
  | checkedMul (destination lhs rhs : Nat)
  | checkedDiv (destination lhs rhs : Nat)
  | checkedMod (destination lhs rhs : Nat)
  | bitAnd (destination lhs rhs : Nat)
  | bitOr (destination lhs rhs : Nat)
  | bitXor (destination lhs rhs : Nat)
  /-- Count guard (≥ 64 → trap) then i64.shl then overflow round-trip guard. -/
  | shl (destination lhs rhs : Nat)
  /-- Count guard (≥ 64 → trap) then i64.shr_u. -/
  | shr (destination lhs rhs : Nat)
  | bitNot (destination source : Nat)
  | boolNot (destination source : Nat)
  /-- Strict Bool AND: i64.and on 0/1 words. -/
  | boolAnd (destination lhs rhs : Nat)
  /-- Strict Bool OR: i64.or on 0/1 words. -/
  | boolOr (destination lhs rhs : Nat)
  /-- Async schedule → `promise_batch_create` + `promise_batch_action_function_call`.
      Args are temp indices whose i64 values are stored LE into the scratch
      payload. Deposit (u128 = 0,0) and gas (0) are explicit artifact
      placeholders, not economics. Fire-and-forget: no response, no revert
      propagation. -/
  | promiseAccount (receiver : String) (method : String) (args : Array Nat)
  deriving BEq, Inhabited, Repr

structure MethodIR where
  name : String
  params : Array Param
  mode : MethodMode
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Pure-function recipe: params occupy temps `0..paramCount-1`; body ops use
    `returnValue` (Wasm `return`) rather than host `value_return`. -/
structure FnIR where
  name : String
  paramCount : Nat
  resultIsBool : Bool
  tempCount : Nat
  operations : Array Operation
  deriving BEq, Inhabited, Repr

/-- Typed NEAR host-call/Wasm recipe. Rendering WAT is deliberately later than
the exact Plan-to-recipe binding check.
    Private `mk`: public Plan→IR construction is capability-gated only
    (`irFromCapability`); the private packaging ctor is not a product emission API. -/
structure IR where
  private mk ::
  sourcePlan : Plan
  name : String
  imports : Array HostImport
  registers : RegisterLayout
  keys : Array KeyRegion
  memory : MemoryLayout
  methods : Array MethodIR
  fns : Array FnIR
  -- No Inhabited: IR embeds Plan → TargetDescriptor identities.
  deriving BEq, Repr

private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .near message

private def maxIdentifierBytes : Nat := 240
-- `.near-abi.json` is the longest emitted suffix (14 bytes) under the CLI's
-- 240-byte relative-path ceiling.
private def maxArtifactStemBytes : Nat := 226
private def maxStateFields : Nat := 1024
private def maxEntries : Nat := 255
private def maxParams : Nat := 64
private def maxBodyStatements : Nat := 4096
private def maxExprDepth : Nat := 256
private def maxPlanNodes : Nat := 100000
private def maxRecipeNodes : Nat := 110000
private def maxMethodLocals : Nat := 50000
private def wasmPageBytes : Nat := 65536

private def canonicalFailurePolicy : FailurePolicy := {
  invalidInput := .trap
  uninitializedLayout := .trap
  corruptStorage := .trap
  arithmeticOverflow := .trap
  nonzeroDeposit := .trap
}

private def canonicalResourceLimits : ResourceLimits := {
  maxArtifactStemBytes
  maxStateFields
  maxEntries
  maxParams
  maxBodyStatements
  maxExprDepth
  maxPlanNodes
  maxRecipeNodes
  maxMethodLocals
  wasmMemoryPages := 1
}

/-- Base host allowlist for programs without schedules. Kept separate so
    no-schedule Plans (and their WAT bytes) stay identical when promise hosts
    are introduced for schedule-bearing programs only. -/
private def canonicalImports : Array HostImport := #[
  .input, .registerLen, .readRegister, .storageRead, .storageWrite, .valueReturn,
  .attachedDeposit, .logUtf8, .panicUtf8
]

/-- Extra hosts required only when the Plan lowers at least one schedule. -/
private def promiseHostImports : Array HostImport := #[
  .promiseBatchCreate, .promiseBatchActionFunctionCall
]

private def hostImportsFor (usesPromise : Bool) : Array HostImport :=
  if usesPromise then canonicalImports ++ promiseHostImports else canonicalImports

private def canonicalRegisters : RegisterLayout := {
  input := 0
  storage := 1
  evicted := 2
}

/-- Thin adapter: binds NEAR's `maxIdentifierBytes` (240) to the shared grammar. -/
private def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

/-- NEAR account-id grammar for schedule receivers (pilot): lowercase ASCII
    letters, digits, `_`, `-`, `.`; UTF-8 length 2..64; no leading or trailing
    `.`. Uppercase is rejected (never case-normalized). This is intentionally
    stricter than DSL identifier components and matches the NEAR account-id
    character set for this envelope. -/
private def isNearAccountId (value : String) : Bool :=
  let n := value.toUTF8.size
  let chars := value.toList.toArray
  (2 ≤ n && n ≤ 64) && !chars.isEmpty &&
    chars[0]! != '.' && chars[chars.size - 1]! != '.' &&
      chars.all fun character =>
        let code := character.toNat
        (97 ≤ code && code ≤ 122) ||
          (48 ≤ code && code ≤ 57) ||
          character == '_' || character == '-' || character == '.'

/-- Sole schedule-receiver account-id error text (lowering + validatePlan). -/
private def nearAccountIdError (receiver : String) : String :=
  s!"schedule receiver '{receiver}' is not a valid NEAR account id (lowercase letters, digits, underscore, hyphen or dot, length 2..64, no leading/trailing dot)"

/-- Sole view/pureFn schedule-disallow error text (lowering + validatePlan).
    `kind` is the richer lowering form, e.g. `"view callable schedules a workflow"`
    or `"pureFn cannot schedule workflows"`. -/
private def nearScheduleDisallowedError (kind : String) : String :=
  s!"unsupported NEAR semantic shape: {kind}"

private def stateKey (sourceId : Nat) : String :=
  s!"pf:v1:state:{sourceId}"

private def layoutFieldSignature (field : StorageField) : String :=
  s!"{field.sourceId}:{field.name}:{field.key}:{field.byteWidth}:u64-le"

private def layoutSignature (fields : Array StorageField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StorageField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (stateLayoutDomain ++ layoutSignature fields).toUTF8

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering -/

/-- Value kinds admitted in the NEAR pilot value table. Bool is admitted for
comparison/logical/literal temps, assert conditions, and entry/view return
values. UInt32 is admitted only as a shift-count temp (zero-extended into the
i64 plan surface). State/params remain UInt64-only; initializer result stays
Unit. -/
private inductive NearValueKindV1 where
  | uint64
  | uint32
  | bool
  deriving BEq, Inhabited, Repr

/-- NEAR pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool/UInt32 optional; state/params remain UInt64-only. -/
private abbrev NearTypeClosureV1 := PilotTypeClosureV1

private def nearPlanErr (message : String) : CompileError :=
  .planInvariant .near message

/-- NEAR pilot accepts the anonymous UInt64/Unit/Bool/UInt32 closure currently
    emitted by the NormalizeV1 public-UInt64 envelope. Valid but richer
    SemanticProgramV1 programs fail at the target Plan seam rather than being
    silently erased. -/
private def validateNearTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult NearTypeClosureV1 :=
  validatePilotTypeClosure nearPlanErr nearTypeClosureWording types

private def makeStorageLayoutV1
    (uint64TypeId : TypeIdV1)
    (states : Array StateDeclV1) : CompileResult StorageLayout := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .near "state count is outside the profile limits"
  let mut fields : Array StorageField := #[]
  for state in states do
    unless state.id.toNat == fields.size do
      throw <| .planInvariant .near "semantic state ids must match declaration order"
    requirePublicUInt64State nearPlanErr uint64TypeId state
    unless isIdentifier state.name do
      throw <| .planInvariant .near s!"state name '{state.name}' is not a safe identifier"
    fields := fields.push {
      sourceId := state.id.toNat
      name := state.name
      key := stateKey state.id.toNat
      byteWidth := 8
      endianness := .little
    }
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .near
      "state layout marker collides with the reserved uninitialized value"
  pure {
    markerKey := layoutMarkerKey
    markerValue := marker
    payloadInitialization := .zeroAllFields
    fields
  }

private structure LoweredValueV1 where
  expr : Expr
  kind : NearValueKindV1
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  deriving Inhabited

private def makeParamsV1 (owner : String) (uint64TypeId : TypeIdV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .near s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .near
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    requirePublicUInt64Param nearPlanErr uint64TypeId owner param
    unless isIdentifier param.name do
      throw <| .planInvariant .near
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      inputOffset := planned.size * 8
      byteWidth := 8
      endianness := .little
    }
    planned := planned.push binding
    values := values.push {
      expr := .param binding.inputOffset
      kind := .uint64
      depth := 1
      expandedNodes := 1
      dependencies := #[]
    }
  pure (planned, values)

private def findFieldV1 (layout : StorageLayout)
    (id : StateIdV1) : CompileResult StorageField :=
  match layout.fields[id.toNat]? with
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
  decodeUInt64LiteralLe nearPlanErr "NEAR" bytes

/-- Decode a 4-byte little-endian UInt32 literal into a zero-extended UInt64
    plan value (shift counts only). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt32LiteralLe nearPlanErr "NEAR" bytes

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool :=
  decodeBoolLiteralBit nearPlanErr "NEAR" bytes

private def comparisonOpOfBinaryV1 (op : BinaryOpV1) : Option ComparisonOp :=
  match op with
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

/-- `stableCount` is the prefix of the value table that remains readable across
    effect segments: callable params, all loop-header block params, and any
    pre-header values frozen when a loop is entered. -/
private def currentValueV1
    (values : Array LoweredValueV1)
    (stableCount segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= stableCount && index < segmentStart then
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Match-bind arm readability: the scrutinee of an enclosing switch may be
    referenced by its arm bodies across the (dominating) scrut-block boundary.
    Loop-stable values (`index < stableCount`) and arm readables are free;
    all other cross-segment reads still fail at the effect boundary. -/
private def currentValueWithArmsV1
    (values : Array LoweredValueV1)
    (stableCount segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= stableCount && index < segmentStart && !armReadables.contains id then
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

private def makeBinaryTreeValueKindsV1
    (mk : Expr → Expr → Expr)
    (lhsKind rhsKind resultKind : NearValueKindV1)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == lhsKind && rhs.kind == rhsKind do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: binary operand kinds do not match the operator"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    kind := resultKind
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
  }

private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (kind : NearValueKindV1)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 mk .uint64 .uint64 kind lhsId rhsId lhs rhs

private def makeCheckedAddValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedAdd l r) .uint64 lhsId rhsId lhs rhs

private def makeCheckedSubValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedSub l r) .uint64 lhsId rhsId lhs rhs

private def makeCheckedMulValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedMul l r) .uint64 lhsId rhsId lhs rhs

private def makeCheckedDivValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedDiv l r) .uint64 lhsId rhsId lhs rhs

private def makeCheckedModValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .checkedMod l r) .uint64 lhsId rhsId lhs rhs

private def makeBitAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .bitAnd l r) .uint64 lhsId rhsId lhs rhs

private def makeBitOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .bitOr l r) .uint64 lhsId rhsId lhs rhs

private def makeBitXorValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .bitXor l r) .uint64 lhsId rhsId lhs rhs

private def makeShlValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (fun l r => .shl l r) .uint64 .uint32 .uint64
    lhsId rhsId lhs rhs

private def makeShrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (fun l r => .shr l r) .uint64 .uint32 .uint64
    lhsId rhsId lhs rhs

private def makeBoolAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (fun l r => .boolAnd l r) .bool .bool .bool
    lhsId rhsId lhs rhs

private def makeBoolOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (fun l r => .boolOr l r) .bool .bool .bool
    lhsId rhsId lhs rhs

private def makeUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandKind resultKind : NearValueKindV1)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless operand.kind == operandKind do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: unary operand kind mismatch"
  let depth := 1 + operand.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk operand.expr
    kind := resultKind
    depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
  }

private def makeBitNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (fun o => .bitNot o) .uint64 .uint64 operandId operand

private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (fun o => .boolNot o) .bool .bool operandId operand

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (fun l r => .compare op l r) .bool lhsId rhsId lhs rhs

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (stableCount segmentStart : Nat)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueV1 values stableCount segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  if root.toNat >= stableCount then
    stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= stableCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: dead or reordered value instructions"
  pure rootValue.expr

/-- Multi-root effect-boundary consumption (event/revert argument lists):
    every value produced in the current segment must be reachable from at
    least one sink root, mirroring the single-root discipline. -/
private def consumeSegmentRootsV1
    (values : Array LoweredValueV1)
    (stableCount segmentStart : Nat)
    (roots : Array ValueIdV1) : CompileResult Unit := do
  for root in roots do
    let _ ← currentValueV1 values stableCount segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  for root in roots do
    if root.toNat >= stableCount then
      stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= stableCount then
          unless segmentStart <= dependencyIndex && dependencyIndex < values.size do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
  unless visitedCount == segmentCount do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: result ValueId/type is not canonical for its kind"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .near s!"NEAR value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  | pureFn
  deriving BEq

/-- PureFn signature environment used while lowering: `byCallable[callableId]`
    is `some fnIndex` for pureFn callables; `sigs` is indexed by fnIndex. -/
private structure NearFnSigV1 where
  paramCount : Nat
  resultKind : NearValueKindV1
  deriving BEq, Inhabited

private structure NearFnEnvV1 where
  byCallable : Array (Option Nat)
  sigs : Array NearFnSigV1
  deriving Inhabited

private def emptyNearFnEnvV1 : NearFnEnvV1 := { byCallable := #[], sigs := #[] }

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

private structure LoweredBlockV1 where
  statements : Array Statement
  values : Array LoweredValueV1
  segmentStart : Nat

private def makeCallFnValueV1
    (fnIndex : Nat)
    (resultKind : NearValueKindV1)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1) : CompileResult LoweredValueV1 := do
  let mut depth : Nat := 1
  let mut expanded : Nat := 1
  for arg in args do
    unless arg.kind == .uint64 do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: pureCall arguments must be UInt64"
    depth := max depth (1 + arg.depth)
    if expanded > maxPlanNodes - arg.expandedNodes then
      throw <| .planInvariant .near s!"NEAR plan expression exceeds node limit {maxPlanNodes}"
    expanded := expanded + arg.expandedNodes
  if depth > maxExprDepth then
    throw <| .planInvariant .near s!"NEAR plan expression exceeds depth {maxExprDepth}"
  pure {
    expr := .callFn fnIndex (args.map (·.expr))
    kind := resultKind
    depth
    expandedNodes := expanded
    dependencies := argIds
  }

/-- Lower one block's instruction sequence (terminator handled by the region
    walker). Each block starts a fresh effect segment; values from dominating
    blocks stay referenceable via the stable prefix, match-arm scrutinees, or
    pre-materialized loop-header block params. -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (fnEnv : NearFnEnvV1)
    (stableCount : Nat)
    (armReadables : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  -- Block params are admitted only as pre-materialized loop induction slots
  -- (filled by the region walker before entering a header). Empty is the
  -- non-loop case; non-empty without a prior materialization fails closed.
  for p in block.params do
    let some slot := values0[p.valueId.toNat]? |
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: block parameter ValueId is out of range"
    match slot.expr with
    | .localTemp _ =>
        unless slot.kind == .uint64 && p.typeId == types.uint64TypeId do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop induction must be public UInt64"
    | _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: block parameters are not supported outside loop headers"
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .near
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let mut segmentStart := values0.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == types.uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 types.uint64TypeId values result {
            expr := .literal value
            kind := .uint64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if types.uint32TypeId == some typeId then
          -- Shift-count surface: 4-byte LE UInt32, zero-extended into the
          -- plan literal / i64 temp word.
          let value ← decodeUInt32LiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind := .uint32
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else
          let boolTypeId ← match types.boolTypeId with
            | some tid =>
                unless typeId == tid do
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: literal is not UInt64, UInt32, or Bool"
                pure tid
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: Bool type is missing for Bool literal"
          let flag ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 boolTypeId values result {
            expr := .literal (if flag then 1 else 0)
            kind := .bool
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
    | .stateLoad stateId, some result =>
        if mode == .pureFn then
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureFn cannot load state"
        let field ← findFieldV1 layout stateId
        values := ← appendResultValueV1 types.uint64TypeId values result {
          expr := .stateLoad field.sourceId
          kind := .uint64
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values stableCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values stableCount segmentStart armReadables rhsId
        -- UInt32 arithmetic is admitted only as shift-count composition
        -- (e.g. `x >> (32 + 32)`). Same plan/IR opcodes as UInt64; the
        -- host/WAT overflow guards are UInt64-wide, which is a conservative
        -- superset for the small counts Normalize produces in this envelope.
        if (op == .add || op == .sub || op == .mul || op == .div || op == .mod ||
            op == .bitAnd || op == .bitOr || op == .bitXor) &&
            lhs.kind == .uint32 && rhs.kind == .uint32 then
          let u32TypeId ← match types.uint32TypeId with
            | some tid => pure tid
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: UInt32 type is missing for shift-count arithmetic"
          unless result.typeId == u32TypeId do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: UInt32 binary result type mismatch"
          let value ← match op with
            | .add =>
                makeBinaryTreeValueKindsV1 (fun l r => .checkedAdd l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .sub =>
                makeBinaryTreeValueKindsV1 (fun l r => .checkedSub l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .mul =>
                makeBinaryTreeValueKindsV1 (fun l r => .checkedMul l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .div =>
                makeBinaryTreeValueKindsV1 (fun l r => .checkedDiv l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .mod =>
                makeBinaryTreeValueKindsV1 (fun l r => .checkedMod l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .bitAnd =>
                makeBinaryTreeValueKindsV1 (fun l r => .bitAnd l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .bitOr =>
                makeBinaryTreeValueKindsV1 (fun l r => .bitOr l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | .bitXor =>
                makeBinaryTreeValueKindsV1 (fun l r => .bitXor l r)
                  .uint32 .uint32 .uint32 lhsId rhsId lhs rhs
            | _ =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: unexpected UInt32 binary op"
          values := ← appendResultValueV1 u32TypeId values result value
        else if op == .add then
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
        else if op == .shl then
          let value ← makeShlValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .shr then
          let value ← makeShrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 types.uint64TypeId values result value
        else if op == .and then
          let boolTypeId ← match types.boolTypeId with
            | some tid => pure tid
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: Bool type is missing for logical and"
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: logical and result must be Bool"
          let value ← makeBoolAndValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        else if op == .or then
          let boolTypeId ← match types.boolTypeId with
            | some tid => pure tid
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: Bool type is missing for logical or"
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: logical or result must be Bool"
          let value ← makeBoolOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        else
          match comparisonOpOfBinaryV1 op with
          | some cmpOp =>
              let boolTypeId ← match types.boolTypeId with
                | some tid => pure tid
                | none =>
                    throw <| .planInvariant .near
                      "unsupported NEAR semantic shape: Bool type is missing for comparison"
              unless result.typeId == boolTypeId do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: comparison result must be Bool"
              let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
              values := ← appendResultValueV1 boolTypeId values result value
          | none =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: only checked UInt64 arithmetic, bitwise, shift, comparison, and strict logical ops are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values stableCount segmentStart armReadables operandId
        match op with
        | .bitNot =>
            let value ← makeBitNotValueV1 operandId operand
            values := ← appendResultValueV1 types.uint64TypeId values result value
        | .not =>
            let boolTypeId ← match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: Bool type is missing for bool not"
            unless result.typeId == boolTypeId do
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: bool not result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTypeId values result value
        | .neg =>
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: Op.Unary.neg is not supported (checked negation desugars to 0 - x)"
    | .pureCall callableId argIds, some result =>
        let fnIndex ← match fnEnv.byCallable[callableId.toNat]? with
          | some (some idx) => pure idx
          | _ =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: pureCall target is not a declared pureFn"
        let sig ← match fnEnv.sigs[fnIndex]? with
          | some s => pure s
          | none =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: pureCall fnIndex is out of range"
        unless argIds.size == sig.paramCount do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureCall arity does not match the callee"
        let expectedTypeId ← match sig.resultKind with
          | .uint64 => pure types.uint64TypeId
          | .bool =>
              match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: Bool type is missing for pureCall result"
          | .uint32 =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: pureCall result cannot be UInt32"
        unless result.typeId == expectedTypeId do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureCall result type does not match the callee"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: pureCall arguments must be UInt64"
          argValues := argValues.push root
        -- Pure expression (not an effect boundary): stay inside the segment;
        -- dependencies on the arg roots let later sinks consume the tree.
        let value ← makeCallFnValueV1 fnIndex sig.resultKind argIds argValues
        values := ← appendResultValueV1 expectedTypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: view callable writes state"
        if mode == .pureFn then
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureFn cannot store state"
        let field ← findFieldV1 layout stateId
        let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables valueId
        unless root.kind == .uint64 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: state store value must be UInt64"
        let value ← consumeCurrentSegmentV1 values stableCount segmentStart valueId
        body := body.push (.store { fieldIndex := field.sourceId, value })
        segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: assert must use errorId=none and empty args"
        let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables condId
        unless root.kind == .bool do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: assert condition must be Bool"
        let condition ← consumeCurrentSegmentV1 values stableCount segmentStart condId
        body := body.push (.assert condition)
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: view callable emits an event"
        if mode == .pureFn then
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureFn cannot emit events"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values stableCount segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        segmentStart := values.size
    | .externalCall _effectId _callee _argIds, none =>
        -- NEAR has no synchronous cross-contract calls. The S2 resolver already
        -- declines effect.synchronous-call; this is the defensive plan gate.
        throw <| .planInvariant .near
          "synchronous external calls are outside the NEAR envelope (NEAR has no synchronous cross-contract calls)"
    | .schedule _effectId callee argIds, none =>
        if mode == .view then
          throw <| .planInvariant .near
            (nearScheduleDisallowedError "view callable schedules a workflow")
        if mode == .pureFn then
          throw <| .planInvariant .near
            (nearScheduleDisallowedError "pureFn cannot schedule workflows")
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: schedule callee must have at least two components"
        let receiver := String.intercalate "." components.toList
        unless isNearAccountId receiver do
          throw <| .planInvariant .near (nearAccountIdError receiver)
        let method := components[components.size - 1]!
        unless isIdentifier method do
          throw <| .planInvariant .near
            s!"schedule method '{method}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables argId
          unless root.kind == .uint64 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: schedule arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values stableCount segmentStart argIds
        body := body.push (.promiseAccount receiver method argExprs)
        segmentStart := values.size
    | _, _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart }

/-- Decode a switch case constant against the scrutinee kind. -/
private def decodeSwitchCaseValueV1 (scrutIsBool : Bool) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if scrutIsBool then
    let bit ← decodeBoolLiteralV1 bytes
    pure (if bit then 1 else 0)
  else
    decodeUInt64LiteralV1 bytes

/-- Region continuation after emitting a block sequence. -/
private inductive RegionContV1 where
  | closed
  | join (blockId : Nat)
  | latch (args : Array ValueIdV1)
  deriving Inhabited

private def findLoopBoundV1 (loopBounds : Array LoopBoundV1) (headerId : Nat) :
    Option LoopBoundV1 :=
  loopBounds.find? (fun lb => lb.header.toNat == headerId)

private def isLoopHeaderV1 (loopBounds : Array LoopBoundV1) (blockId : Nat) : Bool :=
  (findLoopBoundV1 loopBounds blockId).isSome

/-- Validate the Normalize loop envelope: each loopBounds header carries
    exactly one UInt64 block param; every param'd block is a recorded header;
    each latch is a jump back to its header with one arg; degenerate param'd
    blocks without a loopBounds row fail closed. -/
private def validateCallableLoopsV1
    (types : NearTypeClosureV1) (callable : CallableV1) : CompileResult Nat := do
  let mut blockParamCount : Nat := 0
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless block.params.size == 1 do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: loop header must carry exactly one block param"
      let some p := block.params[0]? |
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: loop header must carry exactly one block param"
      unless p.typeId == types.uint64TypeId do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: loop induction must be public UInt64"
      unless p.valueId.toNat == callable.params.size + blockParamCount do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: block parameter ValueIds are not canonical"
      unless isLoopHeaderV1 callable.loopBounds block.id.toNat do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: block parameters require a loopBounds header entry"
      blockParamCount := blockParamCount + 1
  for lb in callable.loopBounds do
    let some header := callable.blocks[lb.header.toNat]? |
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: loopBounds header is out of range"
    unless header.params.size == 1 do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: loopBounds header must have one block param"
    let some latch := callable.blocks[lb.backEdgeFrom.toNat]? |
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: loopBounds backEdgeFrom is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId == lb.header && target.args.size == 1 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop latch must jump to its header with one arg"
    | _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: loop latch terminator must be a jump"
    unless lb.maxIterations.toNat ≤ 4096 do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: loop maxIterations exceeds the wire ceiling"
  pure blockParamCount

/-- Structured emission of multi-block CFGs: forward diamonds (branch/switch)
    and Normalize loop headers (loopBounds + single induction param). Fuel
    bounds recursion to the block count. `enclosingHeader` is set while walking
    a loop body so a jump back to that header ends the body as a latch.
    Returns (statements, values, nextLocal, continuation). -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : Option NearValueKindV1)
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (fnEnv : NearFnEnvV1)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (stableCount : Nat)
    (nextLocal0 : Nat)
    (enclosingHeader : Option Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × Nat × RegionContV1) := do
  if fuel == 0 then
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: CFG region exceeds block bound"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: block ids are not dense"
  -- Starting emission at a loop header is only valid when the induction slot
  -- was already materialised (nested entry is via the jump-to-header path).
  if isLoopHeaderV1 loopBounds start then
    let some p := block.params[0]? |
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: loop header missing induction param"
    let some slot := values0[p.valueId.toNat]? |
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: loop header must be entered via its pre-header jump"
    match slot.expr with
    | .localTemp _ => pure ()
    | _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: loop header must be entered via its pre-header jump"
  let lowered ← lowerBlockInstructionsV1
    owner mode types layout fnEnv stableCount armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .initialize =>
          throw <| .planInvariant .near "initializer cannot return a value"
      | .mutate | .view | .pureFn =>
          let expectedKind ← match expectedReturn with
            | some kind => pure kind
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: entry/view/pureFn is missing expected return kind"
          let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables valueId
          unless root.kind == expectedKind do
            let expectedLabel :=
              match expectedKind with
              | .uint64 => "UInt64"
              | .uint32 => "UInt32"
              | .bool => "Bool"
            throw <| .planInvariant .near
              s!"unsupported NEAR semantic shape: return value must be {expectedLabel}"
          let value ← consumeCurrentSegmentV1 values stableCount segmentStart valueId
          pure (instrs.push (.returnValue value), values, nextLocal0, .closed)
  | .return_ none =>
      unless expectedReturn.isNone do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: initializer expected-return kind is non-empty"
      unless segmentStart == values.size do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, nextLocal0, .closed)
  | .jump target =>
      let targetId := target.blockId.toNat
      -- Latch: jump back to the loop currently being lowered as a body.
      if enclosingHeader == some targetId then
        unless target.args.size == 1 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop latch must carry exactly one induction arg"
        -- Latch args may reference the just-produced increment; do not require
        -- the segment to be empty — the update expr is recovered from args.
        let _ ← currentValueWithArmsV1 values stableCount segmentStart armReadables target.args[0]!
        pure (instrs, values, nextLocal0, .latch target.args)
      else if isLoopHeaderV1 loopBounds targetId then
        -- Enter a (possibly nested) bounded for-loop.
        let some lb := findLoopBoundV1 loopBounds targetId |
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: missing loopBounds for loop header"
        unless target.args.size == 1 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop pre-header must jump with one start arg"
        let initRoot ←
          currentValueWithArmsV1 values stableCount segmentStart armReadables target.args[0]!
        unless initRoot.kind == .uint64 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop start value must be UInt64"
        let initial := initRoot.expr
        -- Freeze every value produced so far (params, block-param slots,
        -- pre-header lets/arithmetic) as loop-stable for the header/body.
        let loopStable := values.size
        let some header := blocks[targetId]? |
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop header block is missing"
        unless header.params.size == 1 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop header must carry exactly one block param"
        let some inductionParam := header.params[0]? |
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop header must carry exactly one block param"
        let inductionVid := inductionParam.valueId
        unless inductionVid.toNat < values.size do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: induction ValueId slot was not pre-allocated"
        let varTemp := nextLocal0
        let nextLocal1 := nextLocal0 + 1
        let inductionSlot : LoweredValueV1 := {
          expr := .localTemp varTemp
          kind := .uint64
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
        let mut valuesH := values.set! inductionVid.toNat inductionSlot
        let loweredH ← lowerBlockInstructionsV1
          owner mode types layout fnEnv loopStable armReadables header valuesH
        valuesH := loweredH.values
        let headerSeg := loweredH.segmentStart
        unless loweredH.statements.isEmpty do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop header may not contain effect instructions"
        let loopResult ← match header.terminator with
          | .branch condId thenT elseT => do
              let condRoot ←
                currentValueWithArmsV1 valuesH loopStable headerSeg armReadables condId
              unless condRoot.kind == .bool do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: loop condition must be Bool"
              let cond ← consumeCurrentSegmentV1 valuesH loopStable headerSeg condId
              unless thenT.args.isEmpty && elseT.args.isEmpty do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: loop branch targets must carry empty args"
              -- Body region ends at the latch (jump back to this header).
              let (bodyStmts, valuesB, nextLocal2, bodyCont) ←
                emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
                  loopStable nextLocal1 (some targetId) armReadables (fuel - 1)
                  thenT.blockId.toNat valuesH
              let updateArgs ← match bodyCont with
                | .latch args => pure args
                | .closed =>
                    throw <| .planInvariant .near
                      "unsupported NEAR semantic shape: loop body closed without a latch (degenerate one-shot loops are out of pilot)"
                | .join _ =>
                    throw <| .planInvariant .near
                      "unsupported NEAR semantic shape: loop body must end at its latch jump"
              unless updateArgs.size == 1 do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: loop latch must carry exactly one update arg"
              -- Re-derive the update expr from the already-lowered value table
              -- (latch increment is left in valuesB by the body walk).
              let updateRoot ← findValueV1 valuesB updateArgs[0]!
              unless updateRoot.kind == .uint64 do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: loop update must be UInt64"
              let update := updateRoot.expr
              let forStmt : Statement :=
                .forLoop varTemp initial cond update lb.maxIterations.toNat bodyStmts
              -- Continue the enclosing walk at the exit (else target).
              let (rest, valuesE, nextLocal3, exitCont) ←
                emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
                  loopStable nextLocal2 enclosingHeader armReadables (fuel - 1)
                  elseT.blockId.toNat valuesB
              pure (instrs ++ #[forStmt] ++ rest, valuesE, nextLocal3, exitCont)
          | _ =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: loop header terminator must be a branch"
        pure loopResult
      else
        -- Forward join: no phi / block args in the non-loop pilot.
        unless target.args.isEmpty do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: non-loop jump targets must carry empty args"
        unless segmentStart == values.size do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: block has unconsumed values"
        pure (instrs, values, nextLocal0, .join targetId)
  | .branch condId thenT elseT =>
      let condRoot ← currentValueWithArmsV1 values stableCount segmentStart armReadables condId
      unless condRoot.kind == .bool do
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values stableCount segmentStart condId
      let (thenBody, values1, nextLocal1, thenNext) ←
        emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
          stableCount nextLocal0 enclosingHeader armReadables (fuel - 1)
          thenT.blockId.toNat values
      -- A latch may only arise on the then-arm of a loop header (handled
      -- above); diamond arms must not latch.
      let thenJoin ← match thenNext with
        | .latch _ =>
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: loop latch outside loop-body walk"
        | .closed => pure (none : Option Nat)
        | .join j => pure (some j)
      match thenJoin with
      | some j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, nextLocal2, next) ←
              emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
                stableCount nextLocal1 enclosingHeader armReadables (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, nextLocal2, next)
          else
            let (elseBody, values2, nextLocal2, elseNext) ←
              emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
                stableCount nextLocal1 enclosingHeader armReadables (fuel - 1)
                elseT.blockId.toNat values1
            let elseJoin ← match elseNext with
              | .latch _ =>
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: loop latch outside loop-body walk"
              | .closed => pure (none : Option Nat)
              | .join j2 => pure (some j2)
            match elseJoin with
            | some j2 =>
                unless j == j2 do
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: branch arms converge on divergent joins"
                let (rest, values3, nextLocal3, next) ←
                  emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
                    stableCount nextLocal2 enclosingHeader armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, nextLocal3, next)
            | none =>
                let (rest, values3, nextLocal3, next) ←
                  emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
                    stableCount nextLocal2 enclosingHeader armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest,
                  values3, nextLocal3, next)
      | none =>
          let (elseBody, values2, nextLocal2, elseNext) ←
            emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
              stableCount nextLocal1 enclosingHeader armReadables (fuel - 1)
              elseT.blockId.toNat values1
          match elseNext with
          | .latch _ =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: loop latch outside loop-body walk"
          | .closed =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, nextLocal2, .closed)
          | .join j =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, nextLocal2, .join j)
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values stableCount segmentStart armReadables scrutId
      let scrut ← consumeCurrentSegmentV1 values stableCount segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .near
          "unsupported NEAR semantic shape: switch must carry a default target")
      let scrutIsBool := scrutVal.kind == .bool
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      let mut nextLocalA := nextLocal0
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutIsBool switchCase.valueBytes
        let (body, values1, nextLocal1, armNext) ←
          emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
            stableCount nextLocalA enclosingHeader (armReadables.push scrutId) (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        nextLocalA := nextLocal1
        match armNext, joinAcc with
        | .closed, _ => pure ()
        | .latch _, _ =>
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: loop latch outside loop-body walk"
        | .join j, none => joinAcc := some j
        | .join j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: switch arms converge on divergent joins"
      let (defaultBody, values2, nextLocal2, defaultNext) ←
        emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
          stableCount nextLocalA enclosingHeader (armReadables.push scrutId) (fuel - 1)
          defaultT.blockId.toNat valuesA
      match defaultNext, joinAcc with
      | .closed, _ => pure ()
      | .latch _, _ =>
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: loop latch outside loop-body walk"
      | .join j, none => joinAcc := some j
      | .join j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: switch arms converge on divergent joins"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, nextLocal2, .closed)
      | some j =>
          let (rest, values3, nextLocal3, next) ←
            emitRegionV1 owner mode expectedReturn types layout fnEnv blocks loopBounds
              stableCount nextLocal2 enclosingHeader armReadables (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest,
            values3, nextLocal3, next)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables argId
        unless root.kind == .uint64 do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values stableCount segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, nextLocal0, .closed)
  | .trap _ =>
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: trap terminators are outside the current pilot"

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectedReturn : Option NearValueKindV1)
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (fnEnv : NearFnEnvV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.invariantSteps.isNone do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: callable must start at dense entry block 0"
  let blockParamCount ← validateCallableLoopsV1 types callable
  let (params, initialValues) ← makeParamsV1 owner types.uint64TypeId callable.params
  -- Pre-allocate dense ValueId slots for every loop induction (canonical
  -- order: callable params < all block params < instruction results).
  let mut valuesInit := initialValues
  for _ in [0:blockParamCount] do
    valuesInit := valuesInit.push {
      expr := .literal 0
      kind := .uint64
      depth := 1
      expandedNodes := 1
      dependencies := #[]
    }
  let stableCount0 := valuesInit.size
  let (body0, values0, _nextLocal0, cont0) ←
    emitRegionV1 owner mode expectedReturn types layout fnEnv callable.blocks
      callable.loopBounds stableCount0 0 none #[] callable.blocks.size 0 valuesInit
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG, so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextLocal := _nextLocal0
  let mut cont := cont0
  for _ in [0:callable.blocks.size] do
    match cont with
    | .closed => break
    | .latch _ =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: loop latch escaped its body walk"
    | .join j =>
        let (rest, values1, nextLocal1, next1) ←
          emitRegionV1 owner mode expectedReturn types layout fnEnv callable.blocks
            callable.loopBounds stableCount0 nextLocal none #[]
            callable.blocks.size j values
        body := body ++ rest
        values := values1
        nextLocal := nextLocal1
        cont := next1
  match cont with
  | .closed => pure ()
  | _ =>
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: callable does not end in return on all paths"
  if body.size > maxBodyStatements then
    throw <| .planInvariant .near s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (fnEnv : NearFnEnvV1)
    (callable : CallableV1) : CompileResult Method := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: initializer result is not Unit"
  let lowered ← lowerCallableV1 "initializer" .initialize none types layout fnEnv callable
  pure {
    name := "init"
    params := lowered.params
    exactInputLen := lowered.params.size * 8
    mode := .initialize
    depositPolicy := .requireZero
    resultKind := .unit
    body := lowered.body
  }

private def makeEntryV1
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (fnEnv : NearFnEnvV1)
    (callable : CallableV1) : CompileResult Method := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .near s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .near s!"entry '{name}' does not return a public result"
  let (resultKind, expectedReturn) ←
    if callable.result.typeId == types.uint64TypeId then
      pure (MethodResultKind.uint64, some NearValueKindV1.uint64)
    else if types.boolTypeId == some callable.result.typeId then
      pure (MethodResultKind.bool, some NearValueKindV1.bool)
    else
      throw <| .planInvariant .near
        s!"entry '{name}' does not return public UInt64 or Bool"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .near
        "unsupported NEAR semantic shape: callable is not an entry or view")
  let mode : MethodMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
    | .pureFn => .mutate
  let lowered ←
    lowerCallableV1 s!"entry '{name}'" semanticMode expectedReturn types layout fnEnv callable
  pure {
    name
    params := lowered.params
    exactInputLen := lowered.params.size * 8
    mode
    depositPolicy := if mode == .view then .queryOnly else .requireZero
    resultKind
    body := lowered.body
  }

private def makePureFnV1
    (types : NearTypeClosureV1)
    (layout : StorageLayout)
    (fnEnv : NearFnEnvV1)
    (callable : CallableV1) : CompileResult FnBinding := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .near
        "unsupported NEAR semantic shape: pureFn is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .near s!"pureFn name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .near s!"pureFn '{name}' does not return a public result"
  let (resultIsBool, expectedReturn) ←
    if callable.result.typeId == types.uint64TypeId then
      pure (false, NearValueKindV1.uint64)
    else if types.boolTypeId == some callable.result.typeId then
      pure (true, NearValueKindV1.bool)
    else
      throw <| .planInvariant .near
        s!"pureFn '{name}' does not return public UInt64 or Bool"
  let lowered ←
    lowerCallableV1 s!"pureFn '{name}'" .pureFn (some expectedReturn) types layout fnEnv callable
  pure {
    name
    params := lowered.params
    resultIsBool
    body := lowered.body
  }

/-- UInt64-compatible plan expression (comparison / boolNot / boolAnd / boolOr /
    Bool callFn results are not; shift/bitwise trees are). -/
private def exprIsUInt64CompatibleV1 (fns : Array FnBinding) : Expr → Bool
  | .compare .. => false
  | .boolNot _ => false
  | .boolAnd .. => false
  | .boolOr .. => false
  | .callFn fnIndex _ =>
      match fns[fnIndex]? with
      | some fn => !fn.resultIsBool
      | none => false
  | _ => true

private partial def planExprNodes? (layout : StorageLayout) (params : Array Param)
    (fns : Array FnBinding) (depthLeft nodeBudget : Nat) (expr : Expr) : Option Nat :=
  if depthLeft == 0 || nodeBudget == 0 then
    none
  else
    let binaryNodes (lhs rhs : Expr) : Option Nat :=
      let childDepth := depthLeft - 1
      let available := nodeBudget - 1
      match planExprNodes? layout params fns childDepth available lhs with
      | none => none
      | some lhsNodes =>
          match planExprNodes? layout params fns childDepth (available - lhsNodes) rhs with
          | none => none
          | some rhsNodes => some (1 + lhsNodes + rhsNodes)
    let unaryNodes (operand : Expr) : Option Nat :=
      let childDepth := depthLeft - 1
      let available := nodeBudget - 1
      match planExprNodes? layout params fns childDepth available operand with
      | none => none
      | some nodes => some (1 + nodes)
    match expr with
    | .literal .. => some 1
    | .param inputOffset => if params.any (·.inputOffset == inputOffset) then some 1 else none
    | .stateLoad fieldIndex => if fieldIndex < layout.fields.size then some 1 else none
    | .localTemp _ => some 1
    | .checkedAdd lhs rhs => binaryNodes lhs rhs
    | .checkedSub lhs rhs => binaryNodes lhs rhs
    | .checkedMul lhs rhs => binaryNodes lhs rhs
    | .checkedDiv lhs rhs => binaryNodes lhs rhs
    | .checkedMod lhs rhs => binaryNodes lhs rhs
    | .bitAnd lhs rhs => binaryNodes lhs rhs
    | .bitOr lhs rhs => binaryNodes lhs rhs
    | .bitXor lhs rhs => binaryNodes lhs rhs
    | .shl lhs rhs => binaryNodes lhs rhs
    | .shr lhs rhs => binaryNodes lhs rhs
    | .bitNot operand => unaryNodes operand
    | .boolNot operand => unaryNodes operand
    | .boolAnd lhs rhs => binaryNodes lhs rhs
    | .boolOr lhs rhs => binaryNodes lhs rhs
    | .compare _ lhs rhs => binaryNodes lhs rhs
    | .callFn fnIndex args => Id.run do
        match fns[fnIndex]? with
        | none => pure none
        | some fn =>
            if args.size != fn.params.size then pure none
            else
              let childDepth := depthLeft - 1
              let mut available := nodeBudget - 1
              let mut totalNodes : Nat := 1
              let mut ok := true
              for arg in args do
                unless exprIsUInt64CompatibleV1 fns arg do
                  ok := false
                match planExprNodes? layout params fns childDepth available arg with
                | none => ok := false
                | some n =>
                    totalNodes := totalNodes + n
                    available := available - n
              pure (if ok then some totalNodes else none)

private def addPlanExprNodes (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (fns : Array FnBinding) (total : Nat) (expr : Expr) :
    CompileResult Nat := do
  if total >= limits.maxPlanNodes then
    throw <| .planInvariant .near
      s!"plan exceeds aggregate node limit {limits.maxPlanNodes}"
  match planExprNodes? layout params fns limits.maxExprDepth
      (limits.maxPlanNodes - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .near
        s!"plan expression has a dangling reference or exceeds depth {limits.maxExprDepth}/node limit {limits.maxPlanNodes}"

private def addMethodExprTemps (limits : ResourceLimits) (layout : StorageLayout)
    (params : Array Param) (fns : Array FnBinding) (total : Nat) (expr : Expr) :
    CompileResult Nat := do
  if total >= limits.maxMethodLocals then
    throw <| .planInvariant .near
      s!"method expression exceeds local limit {limits.maxMethodLocals}"
  match planExprNodes? layout params fns limits.maxExprDepth
      (limits.maxMethodLocals - total) expr with
  | some nodes => pure (total + nodes)
  | none =>
      throw <| .planInvariant .near
        s!"method expression has a dangling reference or exceeds depth {limits.maxExprDepth}/local limit {limits.maxMethodLocals}"

private def validateStorageLayout (limits : ResourceLimits)
    (layout : StorageLayout) : CompileResult Unit := do
  unless layout.markerKey == layoutMarkerKey && layout.markerValue != 0 &&
      layout.payloadInitialization == .zeroAllFields do
    throw <| .planInvariant .near "NEAR storage initialization/layout policy is not canonical"
  if layout.fields.isEmpty || layout.fields.size > limits.maxStateFields then
    throw <| .planInvariant .near "state field count is outside the profile limits"
  for index in [0:layout.fields.size] do
    let field := layout.fields[index]!
    unless field.sourceId == index && isIdentifier field.name &&
        field.key == stateKey index && field.byteWidth == 8 &&
        field.endianness == .little do
      throw <| .planInvariant .near "state field KV layout is not canonical UInt64 little-endian"
  if hasDuplicates (layout.fields.map (·.name)) ||
      hasDuplicates (layout.fields.map (·.key)) ||
      layout.fields.any (·.key == layout.markerKey) then
    throw <| .planInvariant .near "state field names/keys must be unique and distinct from the marker"
  unless layout.markerValue == layoutMarker layout.fields do
    throw <| .planInvariant .near "state layout marker is not bound to the canonical KV schema"

private def validateParams (limits : ResourceLimits) (owner : String)
    (params : Array Param) : CompileResult Unit := do
  if params.size > limits.maxParams then
    throw <| .planInvariant .near
      s!"parameter count in {owner} exceeds profile limit {limits.maxParams}"
  for index in [0:params.size] do
    let param := params[index]!
    unless param.sourceId == index && isIdentifier param.name &&
        param.inputOffset == index * 8 && param.byteWidth == 8 &&
        param.endianness == .little do
      throw <| .planInvariant .near
        s!"parameter binding in {owner} is not canonical UInt64 little-endian"
  if hasDuplicates (params.map (·.name)) then
    throw <| .planInvariant .near s!"parameter names in {owner} must be unique"

/-- Recursive statement-tree validator for one method or pureFn: view-write ban
    (including inside branches), pureFn state/event ban, node/temp accounting,
    and per-level return ordering. Returns (total, methodTemps, closed). A
    bare-return marker is accepted only at the top level of the initializer
    body (`allowReturnNone`); early bare returns inside branch arms fail closed
    (the initializer's layout-marking epilogue must run on every path). -/
private partial def checkMethodStatementsV1
    (limits : ResourceLimits) (layout : StorageLayout)
    (isInitializer : Bool) (isView : Bool) (isPureFn : Bool)
    (allowReturnNone : Bool)
    (eventCount : Nat) (eventFieldCounts : Array Nat)
    (errorCount : Nat) (errorFieldCounts : Array Nat)
    (params : Array Param) (fns : Array FnBinding)
    (statements : Array Statement)
    (total : Nat) (methodTemps : Nat) :
    CompileResult (Nat × Nat × Bool) := do
  let mut total := total
  let mut methodTemps := methodTemps
  let mut closed := false
  for statement in statements do
    if closed then
      throw <| .planInvariant .near s!"method has a statement after return"
    match statement with
    | .store store =>
        if isView then
          throw <| .planInvariant .near s!"view method writes state"
        if isPureFn then
          throw <| .planInvariant .near s!"pureFn body writes state"
        unless store.fieldIndex < layout.fields.size do
          throw <| .planInvariant .near s!"method stores to an unknown KV field"
        total ← addPlanExprNodes limits layout params fns total store.value
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps store.value
    | .returnValue value =>
        if isInitializer then
          throw <| .planInvariant .near "initializer cannot return a value"
        total ← addPlanExprNodes limits layout params fns total value
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps value
        closed := true
    | .returnNone =>
        unless allowReturnNone do
          throw <| .planInvariant .near "method has an early bare return inside a branch arm"
        total := total + 1
        closed := true
    | .emitEvent eventIndex args =>
        if isView then
          throw <| .planInvariant .near "view method emits an event"
        if isPureFn then
          throw <| .planInvariant .near s!"pureFn body emits an event"
        unless eventIndex < eventCount do
          throw <| .planInvariant .near "method emits an unknown event"
        unless args.size == eventFieldCounts[eventIndex]! do
          throw <| .planInvariant .near "method event argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .near "method event arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg
        total := total + 1
    | .promiseAccount receiver method args =>
        if isView then
          throw <| .planInvariant .near
            (nearScheduleDisallowedError "view callable schedules a workflow")
        if isPureFn then
          throw <| .planInvariant .near
            (nearScheduleDisallowedError "pureFn cannot schedule workflows")
        unless isNearAccountId receiver do
          throw <| .planInvariant .near (nearAccountIdError receiver)
        unless isIdentifier method do
          throw <| .planInvariant .near
            s!"schedule method '{method}' is not a safe identifier"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .near "method schedule arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg
        total := total + 1
    | .revertError errorIndex args =>
        unless errorIndex < errorCount do
          throw <| .planInvariant .near "method reverts with an unknown error"
        unless args.size == errorFieldCounts[errorIndex]! do
          throw <| .planInvariant .near "method error argument count mismatch"
        for arg in args do
          unless exprIsUInt64CompatibleV1 fns arg do
            throw <| .planInvariant .near "method error arguments must be UInt64 expressions"
          total ← addPlanExprNodes limits layout params fns total arg
          methodTemps ← addMethodExprTemps limits layout params fns methodTemps arg
        total := total + 1
        closed := true
    | .assert condition =>
        total ← addPlanExprNodes limits layout params fns total condition
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition
    | .ifThenElse condition thenBody elseBody =>
        total ← addPlanExprNodes limits layout params fns total condition
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition
        total := total + 1
        let (t1, m1, c1) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns thenBody total methodTemps
        let (t2, m2, c2) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns elseBody t1 m1
        total := t2
        methodTemps := m2
        closed := c1 && c2 && !elseBody.isEmpty
    | .switchOn scrutinee cases defaultBody =>
        total ← addPlanExprNodes limits layout params fns total scrutinee
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps scrutinee
        total := total + 1
        let mut allClosed := !defaultBody.isEmpty
        for (_caseValue, caseBody) in cases do
          total := total + 1
          let (t, m, c) ← checkMethodStatementsV1
            limits layout isInitializer isView isPureFn false
            eventCount eventFieldCounts errorCount errorFieldCounts
            params fns caseBody total methodTemps
          total := t
          methodTemps := m
          allClosed := allClosed && c
        let (td, md, cd) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns defaultBody total methodTemps
        total := td
        methodTemps := md
        closed := allClosed && cd
    | .forLoop _varTemp initial condition update _maxIterations body =>
        total ← addPlanExprNodes limits layout params fns total initial
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps initial
        total ← addPlanExprNodes limits layout params fns total condition
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps condition
        total ← addPlanExprNodes limits layout params fns total update
        methodTemps ← addMethodExprTemps limits layout params fns methodTemps update
        total := total + 1
        let (tb, mb, _cb) ← checkMethodStatementsV1
          limits layout isInitializer isView isPureFn false
          eventCount eventFieldCounts errorCount errorFieldCounts
          params fns body total methodTemps
        total := tb
        methodTemps := mb
        -- A for-loop itself does not close the enclosing method.
        closed := false
  pure (total, methodTemps, closed)

private def validateMethod (limits : ResourceLimits) (layout : StorageLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding)
    (isInitializer : Bool) (baseNodes : Nat) (method : Method) : CompileResult Nat := do
  unless isIdentifier method.name && method.name != "memory" do
    throw <| .planInvariant .near s!"method '{method.name}' is not a safe export name"
  if isInitializer then
    unless method.name == "init" && method.mode == .initialize &&
        method.depositPolicy == .requireZero && method.resultKind == .unit do
      throw <| .planInvariant .near "initializer export identity is not canonical"
  else if method.mode == .initialize then
    throw <| .planInvariant .near "entry method cannot use initialize mode"
  else unless method.resultKind == .uint64 || method.resultKind == .bool do
    throw <| .planInvariant .near
      s!"method '{method.name}' result kind must be UInt64 or Bool"
  unless method.depositPolicy ==
      (if method.mode == .view then .queryOnly else .requireZero) do
    throw <| .planInvariant .near s!"method '{method.name}' deposit policy is not canonical"
  validateParams limits s!"method '{method.name}'" method.params
  unless method.exactInputLen == method.params.size * 8 do
    throw <| .planInvariant .near s!"method '{method.name}' raw input length is not canonical"
  if method.body.size > limits.maxBodyStatements || (!isInitializer && method.body.isEmpty) then
    throw <| .planInvariant .near s!"method '{method.name}' has an invalid body size"
  let (total, _, closed) ← checkMethodStatementsV1
    limits layout isInitializer (method.mode == .view) false isInitializer
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    method.params fns method.body baseNodes 0
  unless closed do
    throw <| .planInvariant .near
      s!"method '{method.name}' does not terminate on all paths"
  return total

private def validateFnBinding (limits : ResourceLimits) (layout : StorageLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fns : Array FnBinding) (baseNodes : Nat) (fn : FnBinding) : CompileResult Nat := do
  unless isIdentifier fn.name && fn.name != "memory" do
    throw <| .planInvariant .near s!"pureFn '{fn.name}' is not a safe identifier"
  validateParams limits s!"pureFn '{fn.name}'" fn.params
  if fn.body.isEmpty || fn.body.size > limits.maxBodyStatements then
    throw <| .planInvariant .near s!"pureFn '{fn.name}' has an invalid body size"
  let (total, _, closed) ← checkMethodStatementsV1
    limits layout false false true false
    events.size (events.map (·.fieldCount)) errors.size (errors.map (·.fieldCount))
    fn.params fns fn.body baseNodes 0
  unless closed do
    throw <| .planInvariant .near
      s!"pureFn '{fn.name}' does not terminate on all paths"
  return total

/-- Whether any statement tree contains a schedule→promise lowering. -/
private partial def statementsUsePromiseV1 (statements : Array Statement) : Bool :=
  statements.any fun statement =>
    match statement with
    | .promiseAccount .. => true
    | .ifThenElse _ thenBody elseBody =>
        statementsUsePromiseV1 thenBody || statementsUsePromiseV1 elseBody
    | .switchOn _ cases defaultBody =>
        statementsUsePromiseV1 defaultBody ||
          cases.any fun (_, caseBody) => statementsUsePromiseV1 caseBody
    | .forLoop _ _ _ _ _ body => statementsUsePromiseV1 body
    | .store _ | .returnValue _ | .returnNone | .assert _ | .emitEvent ..
    | .revertError .. => false

private def planUsesPromiseV1 (plan : Plan) : Bool :=
  statementsUsePromiseV1 plan.initializer.body ||
    plan.entries.any (fun m => statementsUsePromiseV1 m.body) ||
    plan.fns.any (fun f => statementsUsePromiseV1 f.body)

/-- Validate the public target-owned NEAR Plan before recipe lowering. -/
def validatePlan (plan : Plan) : CompileResult Unit := do
  let expectedImports := hostImportsFor (planUsesPromiseV1 plan)
  unless plan.targetDescriptor == descriptor &&
      plan.semanticSchemaVersion == semanticProgramSchemaVersionV1 &&
      plan.codegenProfile == descriptor.codegenProfile.toString &&
      plan.hostAbi == hostAbiVersion && plan.inputAbi == rawInputAbi &&
      plan.layoutDomain == stateLayoutDomain &&
      plan.hostImports == expectedImports &&
      plan.failurePolicy == canonicalFailurePolicy &&
      plan.commitPolicy == .rollbackOnTrap &&
      plan.resourceLimits == canonicalResourceLimits do
    throw <| .planInvariant .near "NEAR Plan descriptor/schema/profile policies are not canonical"
  unless isIdentifier plan.programName do
    throw <| .planInvariant .near s!"program name '{plan.programName}' is not a safe identifier"
  if plan.programName.toUTF8.size > plan.resourceLimits.maxArtifactStemBytes then
    throw <| .planInvariant .near
      s!"program name exceeds artifact-stem limit {plan.resourceLimits.maxArtifactStemBytes} bytes"
  validateStorageLayout plan.resourceLimits plan.storage
  if plan.entries.isEmpty || plan.entries.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .near "entry count is outside the profile limits"
  if plan.fns.size > plan.resourceLimits.maxEntries then
    throw <| .planInvariant .near "pureFn count is outside the profile limits"
  let handlerCount := 1 + plan.entries.size + plan.fns.size
  let paramCount := plan.initializer.params.size +
    plan.entries.foldl (fun total method => total + method.params.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.params.size) 0
  let statementCount := plan.initializer.body.size +
    plan.entries.foldl (fun total method => total + method.body.size) 0 +
    plan.fns.foldl (fun total fn => total + fn.body.size) 0
  let mut total := plan.storage.fields.size + handlerCount + paramCount + statementCount
  if total > plan.resourceLimits.maxPlanNodes then
    throw <| .planInvariant .near
      s!"plan exceeds aggregate node limit {plan.resourceLimits.maxPlanNodes}"
  for fn in plan.fns do
    total ← validateFnBinding plan.resourceLimits plan.storage plan.events plan.errors
      plan.fns total fn
  total ← validateMethod plan.resourceLimits plan.storage plan.events plan.errors plan.fns
    true total plan.initializer
  for method in plan.entries do
    total ← validateMethod plan.resourceLimits plan.storage plan.events plan.errors plan.fns
      false total method
  let methods := #[plan.initializer] ++ plan.entries
  if hasDuplicates (methods.map (·.name)) then
    throw <| .planInvariant .near "NEAR export names must be unique"
  if hasDuplicates (plan.fns.map (·.name)) then
    throw <| .planInvariant .near "NEAR pureFn names must be unique"
  let exportAndFnNames := methods.map (·.name) ++ plan.fns.map (·.name)
  if hasDuplicates exportAndFnNames then
    throw <| .planInvariant .near "NEAR export and pureFn names must not collide"

/-- Validate one declared event/error binding: safe name and public UInt64
    fields (the NEAR pilot logs UInt64 args as hex words). -/
private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .near
      s!"unsupported NEAR semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .near
        s!"unsupported NEAR semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- Build the pureFn index environment from the unified callable table without
    lowering bodies (signatures only). -/
private def buildNearFnEnvV1
    (types : NearTypeClosureV1)
    (callables : Array CallableV1) : CompileResult NearFnEnvV1 := do
  let mut byCallable : Array (Option Nat) := Array.replicate callables.size none
  let mut sigs : Array NearFnSigV1 := #[]
  for callable in callables do
    match callable.kind with
    | .pureFn =>
        let resultKind ←
          if callable.result.typeId == types.uint64TypeId then
            pure NearValueKindV1.uint64
          else if types.boolTypeId == some callable.result.typeId then
            pure NearValueKindV1.bool
          else
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: pureFn result is not UInt64 or Bool"
        let fnIndex := sigs.size
        if callable.id.toNat < byCallable.size then
          byCallable := byCallable.set! callable.id.toNat (some fnIndex)
        else
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureFn CallableId is out of range"
        sigs := sigs.push { paramCount := callable.params.size, resultKind }
    | _ => pure ()
  pure { byCallable, sigs }

/-- NEAR-private retained SemanticProgramV1 data → target-owned Plan pilot. -/

private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.invariants.isEmpty then
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: constants/invariants are outside the current UInt64 pilot"
  -- init + entries + pureFns share the profile budget (maxEntries each class,
  -- plus one initializer); total still fails closed above 2·maxEntries + 1.
  if source.callables.size > maxEntries + maxEntries + 1 then
    throw <| .planInvariant .near
      s!"callable count exceeds NEAR profile limit {maxEntries + maxEntries + 1}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .near
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateNearTypeClosureV1 source.types
  let storage ← makeStorageLayoutV1 types.uint64TypeId source.logicalState
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let fnEnv ← buildNearFnEnvV1 types source.callables
  let mut initializer : Option Method := none
  let mut entries : Array Method := #[]
  let mut fns : Array FnBinding := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .near "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types storage fnEnv callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .near s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types storage fnEnv callable)
    | .pureFn =>
        if fns.size >= maxEntries then
          throw <| .planInvariant .near s!"pureFn count exceeds profile limit {maxEntries}"
        fns := fns.push (← makePureFnV1 types storage fnEnv callable)
    | .invariant =>
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .near "KV-state programs require an initializer"
  let usesPromise :=
    statementsUsePromiseV1 resolvedInitializer.body ||
      entries.any (fun m => statementsUsePromiseV1 m.body) ||
      fns.any (fun f => statementsUsePromiseV1 f.body)
  let plan : Plan := {
    targetDescriptor := descriptor
    semanticSchemaVersion := semanticProgramSchemaVersionV1
    codegenProfile := descriptor.codegenProfile.toString
    hostAbi := hostAbiVersion
    inputAbi := rawInputAbi
    layoutDomain := stateLayoutDomain
    hostImports := hostImportsFor usesPromise
    failurePolicy := canonicalFailurePolicy
    commitPolicy := .rollbackOnTrap
    resourceLimits := canonicalResourceLimits
    programName
    storage
    events
    errors
    fns
    initializer := resolvedInitializer
    entries
  }
  validatePlan plan
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
        throw <| .invalidProgram "NEAR received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Capability-gated public plan entry. Plan semantics consume retained V1 only. -/
def planFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .near do
    throw <| .planInvariant .near "engineering capability kind is not NEAR"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

private def align8 (value : Nat) : Nat :=
  ((value + 7) / 8) * 8

private def makeKeyRegions (plan : Plan) : Array KeyRegion := Id.run do
  let mut regions : Array KeyRegion := #[]
  let mut offset := 0
  let markerLength := plan.storage.markerKey.toUTF8.size
  regions := regions.push { key := plan.storage.markerKey, offset, length := markerLength }
  offset := offset + markerLength
  for field in plan.storage.fields do
    let length := field.key.toUTF8.size
    regions := regions.push { key := field.key, offset, length }
    offset := offset + length
  return regions

private def maxInputLen (plan : Plan) : Nat :=
  plan.entries.foldl (fun current method => max current method.exactInputLen)
    plan.initializer.exactInputLen

private def makeMemoryLayout (plan : Plan) (keys : Array KeyRegion) : MemoryLayout :=
  let keysEnd := keys.foldl (fun current key => max current (key.offset + key.length)) 0
  let inputOffset := align8 keysEnd
  let inputCapacity := maxInputLen plan
  let depositOffset := align8 (inputOffset + inputCapacity)
  {
    minPages := plan.resourceLimits.wasmMemoryPages
    inputOffset
    inputCapacity
    depositOffset
    valueOffset := depositOffset + 16
  }

private structure LoweredExpr where
  operations : Array Operation
  value : Nat
  next : Nat
  deriving Inhabited

private def fieldRegion (keys : Array KeyRegion) (fieldIndex : Nat) : KeyRegion :=
  keys[fieldIndex + 1]!

/-- `paramAsTemp`: pureFn bodies bind params to temps `0..n-1` (Wasm params),
    so `.param` is a direct temp reference rather than a host input load.
    `localEnv` maps plan `.localTemp` indices to IR temps (loop induction). -/
private partial def lowerExpr (keys : Array KeyRegion) (next : Nat)
    (paramAsTemp : Bool) (localEnv : Array (Nat × Nat)) : Expr → LoweredExpr
  | .literal value =>
      { operations := #[.literal next value], value := next, next := next + 1 }
  | .param inputOffset =>
      if paramAsTemp then
        { operations := #[], value := inputOffset / 8, next := next }
      else
        { operations := #[.loadParam next inputOffset], value := next, next := next + 1 }
  | .localTemp index =>
      match localEnv.find? (fun p => p.1 == index) with
      | some (_, irTemp) =>
          { operations := #[], value := irTemp, next := next }
      | none =>
          -- Unresolved local: allocate a sink temp so validation still binds;
          -- well-formed plans always resolve induction locals via forLoop.
          { operations := #[.literal next 0], value := next, next := next + 1 }
  | .stateLoad fieldIndex =>
      {
        operations := #[.loadState next (fieldRegion keys fieldIndex)]
        value := next
        next := next + 1
      }
  | .checkedAdd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedAdd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedSub lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedSub rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMul lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMul rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedDiv lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedDiv rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .checkedMod lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.checkedMod rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitXor lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.bitXor rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shl lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.shl rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .shr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.shr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .bitNot operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.bitNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .boolNot operand =>
      let operand := lowerExpr keys next paramAsTemp localEnv operand
      {
        operations := operand.operations ++ #[.boolNot operand.next operand.value]
        value := operand.next
        next := operand.next + 1
      }
  | .boolAnd lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolAnd rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .boolOr lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.boolOr rhs.next lhs.value rhs.value]
        value := rhs.next
        next := rhs.next + 1
      }
  | .compare op lhs rhs =>
      let lhs := lowerExpr keys next paramAsTemp localEnv lhs
      let rhs := lowerExpr keys lhs.next paramAsTemp localEnv rhs
      {
        operations := lhs.operations ++ rhs.operations ++
          #[.compare rhs.next lhs.value rhs.value op]
        value := rhs.next
        next := rhs.next + 1
      }
  | .callFn fnIndex args => Id.run do
      let mut operations : Array Operation := #[]
      let mut next := next
      let mut argTemps : Array Nat := #[]
      for arg in args do
        let lowered := lowerExpr keys next paramAsTemp localEnv arg
        operations := operations ++ lowered.operations
        argTemps := argTemps.push lowered.value
        next := lowered.next
      pure {
        operations := operations.push (.callFn fnIndex next argTemps)
        value := next
        next := next + 1
      }

/-- Whether every path through a statement list ends in a return (valued or
    bare marker), matching the region emitter's closedness: a list closes iff
    its last statement is a return or a region whose arms all close. An empty
    else/default arm is a fallthrough (open). Used to append a hard `return`
    after arms whose value_return would otherwise fall through into the
    region's continuation (the host call does not halt execution). -/
private partial def statementListClosesV1 : List Statement → Bool
  | [] => false
  | [statement] =>
      match statement with
      | .returnValue _ | .returnNone | .revertError .. => true
      | .ifThenElse _ thenBody elseBody =>
          !elseBody.isEmpty && statementListClosesV1 thenBody.toList &&
            statementListClosesV1 elseBody.toList
      | .switchOn _ cases defaultBody =>
          !defaultBody.isEmpty && statementListClosesV1 defaultBody.toList &&
            cases.all fun (_, caseBody) => statementListClosesV1 caseBody.toList
      | .store _ | .assert _ | .emitEvent .. | .forLoop .. | .promiseAccount .. => false
  | _ :: _ :: rest => statementListClosesV1 rest

/-- Append the hard return after a closed region arm, unless the arm already
    ends in a halting statement (the initializer's bare-return marker, a
    declared revert, or — in pureFn mode — a valued `return` which is already
    a Wasm `return`). -/
private def armOpsWithHardReturn (arm : Array Statement)
    (operations : Array Operation) (fnMode : Bool) : Array Operation :=
  let alreadyHalts := match arm.back? with
    | some .returnNone | some (.revertError ..) => true
    | some (.returnValue _) => fnMode
    | _ => false
  if statementListClosesV1 arm.toList && !alreadyHalts then
    operations.push .returnNone
  else
    operations

private partial def lowerBodyOps
    (keys : Array KeyRegion) (next : Nat) (statements : Array Statement)
    (fnMode : Bool) (localEnv : Array (Nat × Nat)) :
    Array Operation × Nat := Id.run do
  let mut operations : Array Operation := #[]
  let mut next := next
  let mut localEnv := localEnv
  for statement in statements do
    match statement with
    | .store store =>
        let value := lowerExpr keys next fnMode localEnv store.value
        operations := operations ++ value.operations
        operations := operations.push (.storeState (fieldRegion keys store.fieldIndex) value.value)
        next := value.next
    | .returnValue value =>
        let value := lowerExpr keys next fnMode localEnv value
        operations := operations ++ value.operations
        if fnMode then
          operations := operations.push (.returnValue value.value)
        else
          operations := operations.push (.setReturnData value.value)
        next := value.next
    | .returnNone =>
        -- Valid only inside region arms (validated); the initializer's own
        -- final marker is stripped by lowerMethod before lowering.
        operations := operations.push .returnNone
    | .emitEvent eventIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.emitEvent eventIndex argTemps)
    | .promiseAccount receiver method args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.promiseAccount receiver method argTemps)
    | .revertError errorIndex args =>
        let mut argTemps : Array Nat := #[]
        for arg in args do
          let value := lowerExpr keys next fnMode localEnv arg
          operations := operations ++ value.operations
          argTemps := argTemps.push value.value
          next := value.next
        operations := operations.push (.revertError errorIndex argTemps)
    | .assert condition =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        operations := operations.push (.assert value.value)
        next := value.next
    | .ifThenElse condition thenBody elseBody =>
        let value := lowerExpr keys next fnMode localEnv condition
        operations := operations ++ value.operations
        let (thenOps, next1) := lowerBodyOps keys value.next thenBody fnMode localEnv
        let (elseOps, next2) := lowerBodyOps keys next1 elseBody fnMode localEnv
        operations := operations.push (.ifRegion value.value
          (armOpsWithHardReturn thenBody thenOps fnMode)
          (armOpsWithHardReturn elseBody elseOps fnMode))
        next := next2
    | .switchOn scrutinee cases defaultBody =>
        let value := lowerExpr keys next fnMode localEnv scrutinee
        operations := operations ++ value.operations
        let mut caseOps : Array (UInt64 × Array Operation) := #[]
        let mut nextC := value.next
        for (caseValue, caseBody) in cases do
          let (ops, next1) := lowerBodyOps keys nextC caseBody fnMode localEnv
          caseOps := caseOps.push (caseValue, armOpsWithHardReturn caseBody ops fnMode)
          nextC := next1
        let (defaultOps, nextD) := lowerBodyOps keys nextC defaultBody fnMode localEnv
        operations := operations.push (.switchRegion value.value caseOps
          (armOpsWithHardReturn defaultBody defaultOps fnMode))
        next := nextD
    | .forLoop varTemp initial condition update maxIterations body =>
        let initL := lowerExpr keys next fnMode localEnv initial
        operations := operations ++ initL.operations
        let irVar := initL.next
        let counterTemp := initL.next + 1
        next := initL.next + 2
        -- Seed the induction temp from the initial expression.
        -- forRegion copies initial → varTemp at entry and zeroes counterTemp.
        let localEnv' := localEnv.push (varTemp, irVar)
        let condL := lowerExpr keys next fnMode localEnv' condition
        let condOps := condL.operations
        let condTemp := condL.value
        next := condL.next
        let (bodyOps, nextB) := lowerBodyOps keys next body fnMode localEnv'
        next := nextB
        let updateL := lowerExpr keys next fnMode localEnv' update
        let updateOps := updateL.operations
        let updateTemp := updateL.value
        next := updateL.next
        operations := operations.push
          (.forRegion irVar initL.value counterTemp maxIterations
            condOps condTemp bodyOps updateOps updateTemp)
        localEnv := localEnv'
  pure (operations, next)

private def lowerMethod (plan : Plan) (keys : Array KeyRegion)
    (method : Method) : MethodIR := Id.run do
  let marker := keys[0]!
  let mut operations : Array Operation := #[.checkInputLen method.exactInputLen]
  if method.depositPolicy == .requireZero then
    operations := operations.push .requireZeroAttachedDeposit
  if method.mode == .initialize then
    operations := operations.push (.requireLayoutAbsent marker)
    for index in [0:plan.storage.fields.size] do
      operations := operations.push (.zeroState (fieldRegion keys index))
  else
    operations := operations.push (.requireLayout marker plan.storage.markerValue)
  -- The initializer's final bare-return marker is the natural fall-through;
  -- in-arm markers are rejected by validatePlan and never reach this point.
  let body := if method.body.back? == some .returnNone then
    method.body.pop
  else
    method.body
  let (bodyOps, next) := lowerBodyOps keys 0 body false #[]
  operations := operations ++ bodyOps
  if method.mode == .initialize then
    operations := operations.push (.setLayout marker plan.storage.markerValue)
  return {
    name := method.name
    params := method.params
    mode := method.mode
    tempCount := next
    operations
  }

private def lowerFn (keys : Array KeyRegion) (fn : FnBinding) : FnIR :=
  let paramCount := fn.params.size
  -- Temps `0..paramCount-1` are the Wasm parameters; body lowering starts after.
  let (bodyOps, next) := lowerBodyOps keys paramCount fn.body true #[]
  {
    name := fn.name
    paramCount
    resultIsBool := fn.resultIsBool
    tempCount := next
    operations := bodyOps
  }

private def expectedMethods (plan : Plan) (keys : Array KeyRegion) : Array MethodIR :=
  #[lowerMethod plan keys plan.initializer] ++ plan.entries.map (lowerMethod plan keys)

private def expectedFns (plan : Plan) (keys : Array KeyRegion) : Array FnIR :=
  plan.fns.map (lowerFn keys)

/-- PureFn ops may not touch host storage, layout, deposits, or method returns. -/
private partial def opIsMethodOnlyV1 : Operation → Bool
  | .checkInputLen _ | .requireZeroAttachedDeposit
  | .requireLayoutAbsent _ | .requireLayout _ _
  | .zeroState _ | .loadState _ _ | .storeState _ _
  | .setLayout _ _ | .setReturnData _ | .loadParam _ _ => true
  | .ifRegion _ thenOps elseOps =>
      thenOps.any opIsMethodOnlyV1 || elseOps.any opIsMethodOnlyV1
  | .switchRegion _ cases defaultOps =>
      defaultOps.any opIsMethodOnlyV1 ||
        cases.any fun (_, ops) => ops.any opIsMethodOnlyV1
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.any opIsMethodOnlyV1 || bodyOps.any opIsMethodOnlyV1 ||
        updateOps.any opIsMethodOnlyV1
  | _ => false

private partial def opIsFnReturnValueV1 : Operation → Bool
  | .returnValue _ => true
  | .ifRegion _ thenOps elseOps =>
      thenOps.any opIsFnReturnValueV1 || elseOps.any opIsFnReturnValueV1
  | .switchRegion _ cases defaultOps =>
      defaultOps.any opIsFnReturnValueV1 ||
        cases.any fun (_, ops) => ops.any opIsFnReturnValueV1
  | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
      condOps.any opIsFnReturnValueV1 || bodyOps.any opIsFnReturnValueV1 ||
        updateOps.any opIsFnReturnValueV1
  | _ => false

/-- Validate the typed host-call recipe and bind it exactly to its source Plan. -/
def validateIR (ir : IR) : CompileResult Unit := do
  validatePlan ir.sourcePlan
  unless ir.name == ir.sourcePlan.programName do
    throw <| .planInvariant .near "typed NEAR IR identity is not bound to its source Plan"
  unless ir.imports == ir.sourcePlan.hostImports && ir.registers == canonicalRegisters do
    throw <| .planInvariant .near "typed NEAR IR host imports/registers are not canonical"
  let expectedKeys := makeKeyRegions ir.sourcePlan
  unless ir.keys == expectedKeys do
    throw <| .planInvariant .near "typed NEAR IR key regions are not bound to the Plan KV layout"
  let expectedMemory := makeMemoryLayout ir.sourcePlan expectedKeys
  unless ir.memory == expectedMemory &&
      ir.memory.minPages == ir.sourcePlan.resourceLimits.wasmMemoryPages &&
      ir.memory.valueOffset + 8 <= ir.memory.minPages * wasmPageBytes do
    throw <| .planInvariant .near "typed NEAR IR memory layout is not canonical or exceeds one page"
  if ir.methods.size != ir.sourcePlan.entries.size + 1 then
    throw <| .planInvariant .near "typed NEAR IR export count does not match its source Plan"
  if ir.fns.size != ir.sourcePlan.fns.size then
    throw <| .planInvariant .near "typed NEAR IR pureFn count does not match its source Plan"
  for method in ir.methods do
    if method.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if method.operations.any opIsFnReturnValueV1 then
      throw <| .planInvariant .near
        s!"typed NEAR IR method '{method.name}' must not use pureFn returnValue ops"
  for fn in ir.fns do
    if fn.tempCount > ir.sourcePlan.resourceLimits.maxMethodLocals then
      throw <| .planInvariant .near
        s!"typed NEAR IR pureFn '{fn.name}' exceeds local limit {ir.sourcePlan.resourceLimits.maxMethodLocals}"
    if fn.operations.any opIsMethodOnlyV1 then
      throw <| .planInvariant .near
        s!"typed NEAR IR pureFn '{fn.name}' must not use method-only host ops"
  let operationCount :=
    ir.methods.foldl (fun total method =>
      total + method.params.size + method.operations.size) 0 +
    ir.fns.foldl (fun total fn =>
      total + fn.paramCount + fn.operations.size) 0
  if operationCount > ir.sourcePlan.resourceLimits.maxRecipeNodes then
    throw <| .planInvariant .near
      s!"typed NEAR IR exceeds recipe node limit {ir.sourcePlan.resourceLimits.maxRecipeNodes}"
  let expected := expectedMethods ir.sourcePlan expectedKeys
  unless ir.methods == expected do
    throw <| .planInvariant .near
      "typed NEAR IR methods/operations are not the exact lowering of their source Plan"
  let expectedFnIR := expectedFns ir.sourcePlan expectedKeys
  unless ir.fns == expectedFnIR do
    throw <| .planInvariant .near
      "typed NEAR IR pureFn operations are not the exact lowering of their source Plan"

private def lower (plan : Plan) : CompileResult IR := do
  validatePlan plan
  let keys := makeKeyRegions plan
  let memory := makeMemoryLayout plan keys
  let ir : IR := {
    sourcePlan := plan
    name := plan.programName
    imports := plan.hostImports
    registers := canonicalRegisters
    keys
    memory
    methods := expectedMethods plan keys
    fns := expectedFns plan keys
  }
  validateIR ir
  return ir

private def uint64Hex (value : UInt64) : String :=
  let raw := String.ofList (Nat.toDigits 16 value.toNat)
  let raw := if raw.isEmpty then "0" else raw
  String.ofList (List.replicate (16 - raw.length) '0') ++ raw

private def renderImport : HostImport → String
  | .input => "  (import \"env\" \"input\" (func $pf_input (param i64)))\n"
  | .registerLen =>
      "  (import \"env\" \"register_len\" (func $pf_register_len (param i64) (result i64)))\n"
  | .readRegister =>
      "  (import \"env\" \"read_register\" (func $pf_read_register (param i64 i64)))\n"
  | .storageRead =>
      "  (import \"env\" \"storage_read\" (func $pf_storage_read (param i64 i64 i64) (result i64)))\n"
  | .storageWrite =>
      "  (import \"env\" \"storage_write\" (func $pf_storage_write (param i64 i64 i64 i64 i64) (result i64)))\n"
  | .valueReturn =>
      "  (import \"env\" \"value_return\" (func $pf_value_return (param i64 i64)))\n"
  | .attachedDeposit =>
      "  (import \"env\" \"attached_deposit\" (func $pf_attached_deposit (param i64)))\n"
  | .logUtf8 =>
      "  (import \"env\" \"log_utf8\" (func $pf_log_utf8 (param i64 i64)))\n"
  | .panicUtf8 =>
      "  (import \"env\" \"panic_utf8\" (func $pf_panic_utf8 (param i64 i64)))\n"
  | .promiseBatchCreate =>
      -- account_id_len, account_id_ptr → promise_index
      "  (import \"env\" \"promise_batch_create\" (func $pf_promise_batch_create (param i64 i64) (result i64)))\n"
  | .promiseBatchActionFunctionCall =>
      -- promise_idx, method_len, method_ptr, args_len, args_ptr,
      -- amount_low, amount_high, gas. Deposit/gas are always zero placeholders
      -- in this pilot (explicit in the call site, not silent economics).
      "  (import \"env\" \"promise_batch_action_function_call\" (func $pf_promise_batch_action_function_call (param i64 i64 i64 i64 i64 i64 i64 i64)))\n"

private def renderReadKey (registers : RegisterLayout) (memory : MemoryLayout)
    (indent : String) (destination : Nat) (field : KeyRegion) : String :=
  s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {field.length}) (i64.const {field.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
    s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
    s!"{indent}(call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
    s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.valueOffset})))\n"

/-- Offset of the transient interface-message scratch region (right after the
    8-byte value-return cell; bounded well inside the first memory page). -/
private def messageOffset (memory : MemoryLayout) : Nat :=
  memory.valueOffset + 8

/-- Render a u64 temp as 16 lowercase-hex chars (MSB first) at consecutive
    scratch offsets. `c = d + 48 + 39·(d > 9)` per nibble. -/
private def renderHexArg (indent : String) (offset : Nat) (arg : Nat) : String := Id.run do
  let mut output := ""
  for nibble in [0:16] do
    let shift := 60 - 4 * nibble
    let digit :=
      s!"(i64.and (i64.shr_u (local.get $t{arg}) (i64.const {shift})) (i64.const 15))"
    output := output ++
      s!"{indent}(i32.store8 (i32.const {offset + nibble}) (i32.add (i32.add (i32.const 48) (i32.wrap_i64 {digit})) (i32.mul (i32.const 39) (i64.gt_u {digit} (i64.const 9)))))\n"
  return output

/-- Render the canonical interface message `pf-{tag}:{name}:{hex,...}` into the
    scratch region and the host call consuming it. -/
private def renderInterfaceMessage (registers : RegisterLayout) (memory : MemoryLayout)
    (indent : String) (tag : String) (hostCall : String)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (isEvent : Bool) (declIndex : Nat) (args : Array Nat) : String := Id.run do
  let _ := registers
  let binding := (if isEvent then events else errors)[declIndex]!
  let prefixBytes := s!"pf-{tag}:{binding.name}".toUTF8
  let offset := messageOffset memory
  let mut output := ""
  for i in [0:prefixBytes.size] do
    output := output ++
      s!"{indent}(i32.store8 (i32.const {offset + i}) (i32.const {prefixBytes[i]!.toNat}))\n"
  let mut cursor := offset + prefixBytes.size
  if !args.isEmpty then
    output := output ++
      s!"{indent}(i32.store8 (i32.const {cursor}) (i32.const 58))\n"
    cursor := cursor + 1
    for j in [0:args.size] do
      if j > 0 then
        output := output ++
          s!"{indent}(i32.store8 (i32.const {cursor}) (i32.const 44))\n"
        cursor := cursor + 1
      output := output ++ renderHexArg indent cursor args[j]!
      cursor := cursor + 16
  output := output ++
    s!"{indent}(call ${hostCall} (i64.const {cursor - offset}) (i64.const {offset}))\n"
  return output

/-- First-seen order of schedule receiver/method strings across the IR, used to
    pin account-id/method bytes as `(data ...)` segments so the WAT artifact
    contains the literal strings (not only store8 immediates). -/
private partial def collectPromiseStringsFromOps (ops : Array Operation) : Array String :=
  ops.foldl (fun acc op =>
    match op with
    | .promiseAccount receiver method _ =>
        let acc := if acc.contains receiver then acc else acc.push receiver
        if acc.contains method then acc else acc.push method
    | .ifRegion _ thenOps elseOps =>
        acc ++ collectPromiseStringsFromOps thenOps ++ collectPromiseStringsFromOps elseOps
    | .switchRegion _ cases defaultOps =>
        cases.foldl (fun a (_, caseOps) => a ++ collectPromiseStringsFromOps caseOps)
          (acc ++ collectPromiseStringsFromOps defaultOps)
    | .forRegion _ _ _ _ condOps _ bodyOps updateOps _ =>
        acc ++ collectPromiseStringsFromOps condOps ++
          collectPromiseStringsFromOps bodyOps ++
          collectPromiseStringsFromOps updateOps
    | _ => acc) #[]

private def collectPromiseStrings (ir : IR) : Array String :=
  ir.methods.foldl (fun acc m => acc ++ collectPromiseStringsFromOps m.operations) #[] ++
    ir.fns.foldl (fun acc f => acc ++ collectPromiseStringsFromOps f.operations) #[]

/-- Place promise strings in a fixed free region after the value/scratch area so
    they never collide with KV key data, input packing, or deposit cells.
    Returns (string → offset) pairs in first-seen order. -/
private def layoutPromiseStrings (memory : MemoryLayout) (strings : Array String) :
    Array (String × Nat) := Id.run do
  -- valueOffset+8 is the interface-message scratch; leave 1 KiB for event/
  -- error/arg payloads, then pin schedule account/method bytes.
  let mut offset := memory.valueOffset + 1024
  let mut table : Array (String × Nat) := #[]
  for s in strings do
    unless table.any (fun p => p.1 == s) do
      table := table.push (s, offset)
      offset := offset + s.toUTF8.size
  pure table

private def promiseStringOffset (table : Array (String × Nat)) (s : String) : Nat :=
  match table.find? (fun p => p.1 == s) with
  | some (_, off) => off
  | none => 0

private partial def renderOperation (registers : RegisterLayout) (memory : MemoryLayout)
    (events : Array InterfaceBinding) (errors : Array InterfaceBinding)
    (fnNames : Array String) (promiseStr : Array (String × Nat))
    (indent : String) : Operation → String
  | .checkInputLen bytes =>
      s!"{indent}(call $pf_input (i64.const {registers.input}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.input})) (i64.const {bytes})) (then unreachable))\n" ++
        (if bytes == 0 then "" else
          s!"{indent}(call $pf_read_register (i64.const {registers.input}) (i64.const {memory.inputOffset}))\n")
  | .requireZeroAttachedDeposit =>
      s!"{indent}(call $pf_attached_deposit (i64.const {memory.depositOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset})) (i64.const 0)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.depositOffset + 8})) (i64.const 0)) (then unreachable))\n"
  | .requireLayoutAbsent marker =>
      s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 0)) (then unreachable))\n"
  | .requireLayout marker value =>
      s!"{indent}(if (i64.ne (call $pf_storage_read (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const {registers.storage})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.storage})) (i64.const 8)) (then unreachable))\n" ++
        s!"{indent}(call $pf_read_register (i64.const {registers.storage}) (i64.const {memory.valueOffset}))\n" ++
        s!"{indent}(if (i64.ne (i64.load (i32.const {memory.valueOffset})) (i64.const {value.toNat})) (then unreachable))\n"
  | .zeroState field =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (i64.const 0))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .literal destination value =>
      s!"{indent}(local.set $t{destination} (i64.const {value.toNat}))\n"
  | .loadParam destination inputOffset =>
      s!"{indent}(local.set $t{destination} (i64.load (i32.const {memory.inputOffset + inputOffset})))\n"
  | .loadState destination field =>
      renderReadKey registers memory indent destination field
  | .checkedAdd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.add (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.lt_u (local.get $t{destination}) (local.get $t{lhs})) (then unreachable))\n"
  | .checkedSub destination lhs rhs =>
      s!"{indent}(if (i64.lt_u (local.get $t{lhs}) (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.sub (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMul destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.mul (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (local.get $t{lhs}) (i64.const 0)) (then (if (i64.ne (i64.div_u (local.get $t{destination}) (local.get $t{lhs})) (local.get $t{rhs})) (then unreachable))))\n"
  | .checkedDiv destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.div_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .checkedMod destination lhs rhs =>
      s!"{indent}(if (i64.eqz (local.get $t{rhs})) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.rem_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitAnd destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitXor destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .shl destination lhs rhs =>
      -- Wasm i64.shl masks the count mod 64; guard count ≥ 64 first so the
      -- host trap matches the wire invalidShift semantics, then emit the
      -- shift and a round-trip overflow guard exact for k < 64.
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shl (local.get $t{lhs}) (local.get $t{rhs})))\n" ++
        s!"{indent}(if (i64.ne (i64.shr_u (local.get $t{destination}) (local.get $t{rhs})) (local.get $t{lhs})) (then unreachable))\n"
  | .shr destination lhs rhs =>
      s!"{indent}(if (i64.ge_u (local.get $t{rhs}) (i64.const 64)) (then unreachable))\n" ++
        s!"{indent}(local.set $t{destination} (i64.shr_u (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .bitNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.xor (local.get $t{source}) (i64.const -1)))\n"
  | .boolNot destination source =>
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u (i64.eqz (local.get $t{source}))))\n"
  | .boolAnd destination lhs rhs =>
      -- Bitwise == logical on 0/1 Bool words; both sides already evaluated.
      s!"{indent}(local.set $t{destination} (i64.and (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .boolOr destination lhs rhs =>
      s!"{indent}(local.set $t{destination} (i64.or (local.get $t{lhs}) (local.get $t{rhs})))\n"
  | .compare destination lhs rhs op =>
      let insn :=
        match op with
        | .eq => "i64.eq"
        | .ne => "i64.ne"
        | .lt => "i64.lt_u"
        | .le => "i64.le_u"
        | .gt => "i64.gt_u"
        | .ge => "i64.ge_u"
      s!"{indent}(local.set $t{destination} (i64.extend_i32_u ({insn} (local.get $t{lhs}) (local.get $t{rhs}))))\n"
  | .assert condition =>
      s!"{indent}(if (i64.eqz (local.get $t{condition})) (then unreachable))\n"
  | .returnNone =>
      s!"{indent}(return)\n"
  | .emitEvent eventIndex args =>
      renderInterfaceMessage registers memory indent "event" "pf_log_utf8"
        events errors true eventIndex args
  | .promiseAccount receiver method args =>
      -- Account id / method come from module `(data ...)` segments (literal
      -- strings in the WAT). Args are a deterministic u64-LE payload written
      -- into the interface-message scratch (each arg 8-byte LE via i64.store,
      -- source order). Deposit u128=(0,0) and gas=0 are explicit zero
      -- placeholders — not economics. Fire-and-forget: promise failure never
      -- propagates to the caller.
      Id.run do
        let _ := registers
        let _ := events
        let _ := errors
        let _ := fnNames
        let accountOffset := promiseStringOffset promiseStr receiver
        let methodOffset := promiseStringOffset promiseStr method
        let accountLen := receiver.toUTF8.size
        let methodLen := method.toUTF8.size
        let argsOffset := messageOffset memory
        let mut output := ""
        for j in [0:args.size] do
          output := output ++
            s!"{indent}(i64.store (i32.const {argsOffset + 8 * j}) (local.get $t{args[j]!}))\n"
        let argsLen := 8 * args.size
        pure <| output ++
          s!"{indent}(call $pf_promise_batch_action_function_call\n" ++
          s!"{indent}  (call $pf_promise_batch_create (i64.const {accountLen}) (i64.const {accountOffset}))\n" ++
          s!"{indent}  (i64.const {methodLen}) (i64.const {methodOffset})\n" ++
          s!"{indent}  (i64.const {argsLen}) (i64.const {argsOffset})\n" ++
          s!"{indent}  (i64.const 0) (i64.const 0) (i64.const 0))\n"
  | .revertError errorIndex args =>
      renderInterfaceMessage registers memory indent "error" "pf_panic_utf8"
        events errors false errorIndex args
  | .storeState field value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {field.length}) (i64.const {field.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 1)) (then unreachable))\n" ++
        s!"{indent}(if (i64.ne (call $pf_register_len (i64.const {registers.evicted})) (i64.const 8)) (then unreachable))\n"
  | .setLayout marker value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (i64.const {value.toNat}))\n" ++
        s!"{indent}(if (i64.ne (call $pf_storage_write (i64.const {marker.length}) (i64.const {marker.offset}) (i64.const 8) (i64.const {memory.valueOffset}) (i64.const {registers.evicted})) (i64.const 0)) (then unreachable))\n"
  | .setReturnData value =>
      s!"{indent}(i64.store (i32.const {memory.valueOffset}) (local.get $t{value}))\n" ++
        s!"{indent}(call $pf_value_return (i64.const 8) (i64.const {memory.valueOffset}))\n"
  | .callFn fnIndex destination args =>
      let name := match fnNames[fnIndex]? with
        | some n => n
        | none => "unknown"
      let argGets := String.intercalate " " <| args.toList.map fun a =>
        s!"(local.get $t{a})"
      let callArgs := if args.isEmpty then "" else " " ++ argGets
      s!"{indent}(local.set $t{destination} (call $fn_{name}{callArgs}))\n"
  | .returnValue value =>
      s!"{indent}(return (local.get $t{value}))\n"
  | .ifRegion condition thenOps elseOps =>
      let thenText := thenOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          (indent ++ "  ") operation) ""
      let elseText := elseOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          (indent ++ "  ") operation) ""
      s!"{indent}(if (local.get $t{condition})\n{indent}  (then\n" ++ thenText ++
        s!"{indent}  )\n" ++
        (if elseOps.isEmpty then "" else
          s!"{indent}  (else\n" ++ elseText ++ s!"{indent}  )\n") ++
        s!"{indent})\n"
  | .forRegion varTemp initial counterTemp maxIterations
        condOps condition bodyOps updateOps updateValue =>
      -- Canonical Wasm loop. Labels are deterministic from the induction temp
      -- index. Bound check sits at the back edge after the body (reference
      -- noteBackEdge): bodies 1..N pass; the (N+1)-th body runs then traps.
      -- A body return exits before the check. The latch `i := i+1` is
      -- unguarded: Normalize only runs the body while `i < end ≤ UInt64.max`.
      let inner := indent ++ "  "
      let deeper := indent ++ "    "
      let condText := condOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      let bodyText := bodyOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      let updateText := updateOps.foldl (fun output operation =>
        output ++ renderOperation registers memory events errors fnNames promiseStr
          deeper operation) ""
      s!"{indent}(local.set $t{varTemp} (local.get $t{initial}))\n" ++
        s!"{indent}(local.set $t{counterTemp} (i64.const 0))\n" ++
        s!"{indent}(block $pf_exit{varTemp}\n" ++
        s!"{inner}(loop $pf_loop{varTemp}\n" ++
        condText ++
        s!"{deeper}(br_if $pf_exit{varTemp} (i64.eqz (local.get $t{condition})))\n" ++
        bodyText ++
        s!"{deeper}(if (i64.ge_u (local.get $t{counterTemp}) (i64.const {maxIterations})) (then unreachable))\n" ++
        s!"{deeper}(local.set $t{counterTemp} (i64.add (local.get $t{counterTemp}) (i64.const 1)))\n" ++
        updateText ++
        s!"{deeper}(local.set $t{varTemp} (local.get $t{updateValue}))\n" ++
        s!"{deeper}(br $pf_loop{varTemp})\n" ++
        s!"{inner})\n" ++
        s!"{indent})\n"
  | .switchRegion scrutinee cases defaultOps =>
      -- Right-nested if/else chain: first matching case wins, else default.
      let rec renderCases (indent : String) (remaining : Array (UInt64 × Array Operation)) : String :=
        match remaining.toList with
        | [] =>
            let defaultText := defaultOps.foldl (fun output operation =>
              output ++ renderOperation registers memory events errors fnNames promiseStr
                (indent ++ "  ") operation) ""
            s!"{indent}(then\n" ++ defaultText ++ s!"{indent})\n"
        | (caseValue, caseOps) :: rest =>
            let caseText := caseOps.foldl (fun output operation =>
              output ++ renderOperation registers memory events errors fnNames promiseStr
                (indent ++ "  ") operation) ""
            s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
              s!"{indent}  (then\n" ++ caseText ++ s!"{indent}  )\n" ++
              s!"{indent}  (else\n" ++ renderCases (indent ++ "  ") rest.toArray ++
              s!"{indent})\n"
      match cases.toList with
      | [] =>
          defaultOps.foldl (fun output operation =>
            output ++ renderOperation registers memory events errors fnNames promiseStr
              indent operation) ""
      | (caseValue, caseOps) :: rest =>
          let caseText := caseOps.foldl (fun output operation =>
            output ++ renderOperation registers memory events errors fnNames promiseStr
              (indent ++ "  ") operation) ""
          s!"{indent}(if (i64.eq (local.get $t{scrutinee}) (i64.const {caseValue.toNat}))\n" ++
            s!"{indent}  (then\n" ++ caseText ++ s!"{indent}  )\n" ++
            s!"{indent}  (else\n" ++ renderCases (indent ++ "  ") rest.toArray ++
            s!"{indent})\n"

private def renderMethod (ir : IR) (promiseStr : Array (String × Nat))
    (method : MethodIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let locals := String.intercalate "" <| (Array.range method.tempCount).toList.map fun index =>
    s!" (local $t{index} i64)"
  let operations := String.intercalate "" <| method.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func (export \"{method.name}\"){locals}\n" ++ operations ++ "  )\n"

/-- PureFn WAT: params occupy the first local indices (`$t0..`), extra temps
    follow, and the body ends with Wasm `return` of the result value. -/
private def renderFn (ir : IR) (promiseStr : Array (String × Nat)) (fn : FnIR) : String :=
  let fnNames := ir.fns.map (·.name)
  let params := String.intercalate "" <| (Array.range fn.paramCount).toList.map fun index =>
    s!" (param $t{index} i64)"
  let extraLocals :=
    if fn.tempCount <= fn.paramCount then ""
    else
      String.intercalate "" <|
        (List.range (fn.tempCount - fn.paramCount)).map fun i =>
          s!" (local $t{fn.paramCount + i} i64)"
  let operations := String.intercalate "" <| fn.operations.toList.map
    (renderOperation ir.registers ir.memory
      ir.sourcePlan.events ir.sourcePlan.errors fnNames promiseStr "    ")
  s!"  (func $fn_{fn.name}{params} (result i64){extraLocals}\n" ++
    operations ++ "  )\n"

private def renderWat (ir : IR) : String :=
  let imports := String.intercalate "" <| ir.imports.toList.map renderImport
  let promiseStr := layoutPromiseStrings ir.memory (collectPromiseStrings ir)
  let keyData := String.intercalate "" <| ir.keys.toList.map fun key =>
    s!"  (data (i32.const {key.offset}) \"{key.key}\")\n"
  -- Escape is unnecessary: account-id grammar and identifier method names are
  -- restricted to safe ASCII (no quotes/backslashes).
  let promiseData := String.intercalate "" <| promiseStr.toList.map fun (s, off) =>
    s!"  (data (i32.const {off}) \"{s}\")\n"
  let fns := String.intercalate "" <| ir.fns.toList.map (renderFn ir promiseStr)
  let methods := String.intercalate "" <| ir.methods.toList.map (renderMethod ir promiseStr)
  "(module\n" ++ imports ++
    s!"  (memory (export \"memory\") {ir.memory.minPages})\n" ++
    keyData ++ promiseData ++ fns ++ methods ++ ")\n"

private def renderMode : MethodMode → String
  | .initialize => "initialize"
  | .mutate => "mutate"
  | .view => "view"

private def renderDepositPolicy : DepositPolicy → String
  | .requireZero => "zero-required"
  | .queryOnly => "query-only"

private def renderParamJson (param : Param) : String :=
  s!"\{\"name\":\"{Targets.escapeJson param.name}\",\"type\":\"u64-le\",\"inputOffset\":{param.inputOffset}}"

private def renderParamsJson (params : Array Param) : String :=
  String.intercalate "," (params.toList.map renderParamJson)

private def renderFieldJson (field : StorageField) : String :=
  s!"\{\"name\":\"{Targets.escapeJson field.name}\",\"sourceId\":{field.sourceId},\"key\":\"{Targets.escapeJson field.key}\",\"type\":\"u64-le\"}"

private def renderResultKindJson : MethodResultKind → String
  | .unit => "null"
  | .uint64 => "\"u64-le\""
  | .bool => "\"bool\""

private def renderMethodJson (method : Method) : String :=
  let returns := renderResultKindJson method.resultKind
  "{" ++
    s!"\"name\":\"{Targets.escapeJson method.name}\"," ++
    s!"\"mode\":\"{renderMode method.mode}\"," ++
    s!"\"depositPolicy\":\"{renderDepositPolicy method.depositPolicy}\"," ++
    s!"\"exactInputLen\":{method.exactInputLen}," ++
    s!"\"args\":[{renderParamsJson method.params}],\"returns\":{returns}" ++
    "}"

private def renderAbi (plan : Plan) : String :=
  let fields := String.intercalate "," (plan.storage.fields.toList.map renderFieldJson)
  let methods := #[plan.initializer] ++ plan.entries
  let exports := String.intercalate ",\n    " (methods.toList.map renderMethodJson)
  "{\n" ++
    "  \"schema\": \"proof-forge-near-abi/v1alpha1\",\n" ++
    s!"  \"program\": \"{Targets.escapeJson plan.programName}\",\n" ++
    s!"  \"codegenProfile\": \"{plan.codegenProfile}\",\n" ++
    s!"  \"hostAbi\": \"{plan.hostAbi}\",\n" ++
    s!"  \"encoding\": \"{plan.inputAbi}\",\n" ++
    "  \"storage\": {" ++
    s!"\"markerKey\":\"{plan.storage.markerKey}\"," ++
    s!"\"layoutMarker\":\"0x{uint64Hex plan.storage.markerValue}\"," ++
    "\"initializerPayloadPolicy\":\"zero-all-fields\"," ++
    s!"\"fields\":[{fields}]" ++
    "},\n" ++
    "  \"exports\": [\n    " ++ exports ++ "\n  ]\n" ++
    "}\n"

private def emitFromIR (ir : IR) : CompileResult (Array OutputFile) := do
  validateIR ir
  return #[
    {
      path := s!"{ir.name}.wat"
      mediaType := "application/wasm-text"
      contents := renderWat ir
    },
    {
      path := s!"{ir.name}.near-abi.json"
      mediaType := "application/json"
      contents := renderAbi ir.sourcePlan
    }
  ]

/-- Replace methods on an existing IR (private `mk`; for validateIR characterization). -/
def withMethods (ir : IR) (methods : Array MethodIR) : IR :=
  { ir with methods }

/-- Replace pureFns on an existing IR (private `mk`; for validateIR characterization). -/
def withFns (ir : IR) (fns : Array FnIR) : IR :=
  { ir with fns }

/-- Capability-gated public IR inspection (S6 repair). Input must be
    `ResolvedEngineeringBuildV1`; returns typed TargetIR without emitting files. -/
def irFromCapability (capability : ResolvedEngineeringBuildV1) : CompileResult IR := do
  let plan ← planFromCapability capability
  lower plan

/-- Capability-gated public materialize entry (S6). -/
def buildFromCapability (capability : ResolvedEngineeringBuildV1) :
    CompileResult (Array OutputFile) := do
  let ir ← irFromCapability capability
  emitFromIR ir

instance : Materializer .near where
  Plan := Plan
  TargetIR := IR

end ProofForgeV2.Targets.Near
