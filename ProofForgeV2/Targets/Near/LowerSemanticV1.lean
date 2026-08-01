import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline

/-!
# Near LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the NEAR-owned Plan surface and Semantic→Plan body.
-/

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
  /-- Multi-limb literal for UInt128/256 (T9e). `bitWidth ∈ {128,256}`. -/
  | bigLiteral (bitWidth : Nat) (value : Nat)
  | param (inputOffset : Nat)
  /-- Narrow ABI param load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `param`. -/
  | narrowParam (bitWidth : Nat) (inputOffset : Nat)
  | stateLoad (fieldIndex : Nat)
  /-- Narrow ABI state load (`bitWidth ∈ {8,16,32}`); UInt64/Int64 keep `stateLoad`. -/
  | narrowStateLoad (bitWidth : Nat) (fieldIndex : Nat)
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
  | signedCheckedAdd (lhs rhs : Expr)
  | signedCheckedSub (lhs rhs : Expr)
  | signedCheckedMul (lhs rhs : Expr)
  | signedCheckedDiv (lhs rhs : Expr)
  | signedCheckedMod (lhs rhs : Expr)
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  | checkedNeg (operand : Expr)
  | sar (lhs rhs : Expr)
  | bitNot (operand : Expr)
  /-- Narrow body checked arithmetic (`bitWidth ∈ {8,16,32}`); UInt64 keeps historical. -/
  | narrowCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitAnd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitOr (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitXor (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitNot (bitWidth : Nat) (operand : Expr)
  | narrowShl (bitWidth : Nat) (lhs rhs : Expr)
  | narrowShr (bitWidth : Nat) (lhs rhs : Expr)
  | boolNot (operand : Expr)
  /-- Strict Bool AND on 0/1 words (both sides always evaluate). -/
  | boolAnd (lhs rhs : Expr)
  /-- Strict Bool OR on 0/1 words (both sides always evaluate). -/
  | boolOr (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  /-- Multiword unsigned compare (`bitWidth ∈ {128,256}`); result Bool. -/
  | wideCompare (bitWidth : Nat) (op : ComparisonOp) (lhs rhs : Expr)
  | callFn (fnIndex : Nat) (args : Array Expr)
  /-- Mutable plan-local (loop induction). Index is method-local and unique per
      forLoop; IR lowering maps it to a stable Wasm temp rewritten each latch. -/
  | localTemp (index : Nat)
  deriving BEq, Inhabited, Repr

structure Store where
  fieldIndex : Nat
  value : Expr
  /-- Physical store width in bytes (`1/2/4/8/16/32`). Default 8 keeps historical
      UInt64/Int64 Plan literals byte-identical. -/
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
UInt{8,16,32,64}/Bool/Int64 (T9a). UInt64/Int64/Bool wire as 8-byte little-endian
i64 (Bool is 0/1); UInt{8,16,32} wire as 1/2/4-byte LE payloads. ABI JSON
`returns` distinguishes the declared type. -/
inductive MethodResultKind where
  | unit
  | uint64
  | bool
  | int64
  | uint8
  | uint16
  | uint32
  | int8
  | int16
  | int32
  /-- T9e: multiword public UInt entry/view results (16/32-byte LE). -/
  | uint128
  | uint256
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
private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .near message

private def maxIdentifierBytes : Nat := 240
-- `.near-abi.json` is the longest emitted suffix (14 bytes) under the CLI's
-- 240-byte relative-path ceiling.
def maxArtifactStemBytes : Nat := 226
def maxStateFields : Nat := 1024
def maxEntries : Nat := 255
def maxParams : Nat := 64
def maxBodyStatements : Nat := 4096
def maxExprDepth : Nat := 256
def maxPlanNodes : Nat := 100000
def maxRecipeNodes : Nat := 110000
def maxMethodLocals : Nat := 50000
def wasmPageBytes : Nat := 65536

def canonicalFailurePolicy : FailurePolicy := {
  invalidInput := .trap
  uninitializedLayout := .trap
  corruptStorage := .trap
  arithmeticOverflow := .trap
  nonzeroDeposit := .trap
}

def canonicalResourceLimits : ResourceLimits := {
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

def hostImportsFor (usesPromise : Bool) : Array HostImport :=
  if usesPromise then canonicalImports ++ promiseHostImports else canonicalImports

def canonicalRegisters : RegisterLayout := {
  input := 0
  storage := 1
  evicted := 2
}

/-- Thin adapter: binds NEAR's `maxIdentifierBytes` (240) to the shared grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

/-- NEAR account-id grammar for schedule receivers (pilot): lowercase ASCII
    letters, digits, `_`, `-`, `.`; UTF-8 length 2..64; no leading or trailing
    `.`. Uppercase is rejected (never case-normalized). This is intentionally
    stricter than DSL identifier components and matches the NEAR account-id
    character set for this envelope. -/
def isNearAccountId (value : String) : Bool :=
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
def nearAccountIdError (receiver : String) : String :=
  s!"schedule receiver '{receiver}' is not a valid NEAR account id (lowercase letters, digits, underscore, hyphen or dot, length 2..64, no leading/trailing dot)"

/-- Sole view/pureFn schedule-disallow error text (lowering + validatePlan).
    `kind` is the richer lowering form, e.g. `"view callable schedules a workflow"`
    or `"pureFn cannot schedule workflows"`. -/
def nearScheduleDisallowedError (kind : String) : String :=
  s!"unsupported NEAR semantic shape: {kind}"

def stateKey (sourceId : Nat) : String :=
  s!"pf:v1:state:{sourceId}"

/-- Layout field type suffix from physical byte width (`u8-le` … `u64-le`). -/
def layoutFieldTypeSuffix (byteWidth : Nat) : String :=
  match byteWidth with
  | 1 => "u8-le"
  | 2 => "u16-le"
  | 4 => "u32-le"
  | 16 => "u128-le"
  | 32 => "u256-le"
  | _ => "u64-le"

/-- Input slot pitch for a param physical width (T9e multiword). -/
def slotPitchOfByteWidth (byteWidth : Nat) : Nat :=
  let limbs := (byteWidth + 7) / 8
  if limbs ≤ 1 then 8 else limbs * 8

/-- Total raw input length for a param list (last offset + pitch, or 0). -/
def exactInputLenOfParams (params : Array Param) : Nat :=
  match params.back? with
  | none => 0
  | some p => p.inputOffset + slotPitchOfByteWidth p.byteWidth

/-- ABI / IDL type string for a param or storage field (Int64 keeps `u64-le`). -/
def abiScalarTypeString (byteWidth : Nat) : String :=
  layoutFieldTypeSuffix byteWidth

private def layoutFieldSignature (field : StorageField) : String :=
  s!"{field.sourceId}:{field.name}:{field.key}:{field.byteWidth}:{layoutFieldTypeSuffix field.byteWidth}"

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
values. Body multi-width (T8c) admits UInt{8,16,32,64} temps; UInt32 also
covers shift-count temps (zero-extended into the i64 plan surface). Top-level
state/params admit UInt{8,16,32,64}|Int64 (T8b). Initializer result stays Unit. -/
private inductive NearValueKindV1 where
  | uint64
  | uint32
  | uint16
  | uint8
  | bool
  | int64
  /-- T9e multiword body kinds. -/
  | uint128
  | uint256
  deriving BEq, Inhabited, Repr

/-- Map admitted body UInt width to plan value kind. -/
private def uintKindOfWidthV1 (w : Nat) : Option NearValueKindV1 :=
  match w with
  | 8 => some .uint8
  | 16 => some .uint16
  | 32 => some .uint32
  | 64 => some .uint64
  | 128 => some .uint128
  | 256 => some .uint256
  | _ => none


/-- Inverse of `uintKindOfWidthV1` for store/width gates. -/
private def widthOfUintKindV1 (k : NearValueKindV1) : Option Nat :=
  match k with
  | .uint8 => some 8
  | .uint16 => some 16
  | .uint32 => some 32
  | .uint64 => some 64
  | .uint128 => some 128
  | .uint256 => some 256
  | .bool | .int64 => none

/-- NEAR pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Bool/UInt32 optional; state/params admit UInt{8,16,32,64}|Int64 (T8b). -/
private abbrev NearTypeClosureV1 := PilotTypeClosureV1

private def nearPlanErr (message : String) : CompileError :=
  .planInvariant .near message

/-- NEAR pilot accepts anonymous UInt{8,16,32,64,128,256}/Unit/Bool/Int{8,16,32,64}
    under `pilotUintWidthPolicyNearBody` (T9e multiword + T8c/T8b). N2c: Principal
    remains fail-closed (wire identity is binary variable-length; not a NEAR
    account-id string). -/
private def validateNearTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult NearTypeClosureV1 :=
  -- ArrayState: container policy defaults to none — anonymous Array/Map/Bytes
  -- fail closed at type-closure with an explicit container-pilot diagnostic.
  validatePilotTypeClosure nearPlanErr nearTypeClosureWording types
    pilotUintWidthPolicyNearBody
    (intPolicy := pilotIntWidthPolicyNarrow)

/-- Resolve admitted scalar state/param TypeId to physical byte width (1/2/4/8). -/
private def abiByteWidthOfTypeV1
    (types : NearTypeClosureV1) (typeId : TypeIdV1) : CompileResult Nat := do
  match types.uintWidthOf typeId with
  | some w =>
      unless isNearAbiUintWidth w do
        throw <| .planInvariant .near
          s!"unsupported NEAR semantic shape: ABI UInt{w} is not admitted"
      pure (byteWidthOfBitWidth w)
  | none =>
      match types.intWidthOf typeId with
      | some w =>
          unless isAbiIntWidth w do
            throw <| .planInvariant .near
              s!"unsupported NEAR semantic shape: ABI Int{w} is not admitted"
          pure (byteWidthOfBitWidth w)
      | none =>
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: ABI type must be UInt8/16/32/64/128/256 or Int8/16/32/64"

/-- Width-dispatch for ABI param loads: UInt64/Int64 keep historical `param`. -/
private def mkParamExpr (bitWidth : Nat) (inputOffset : Nat) : Expr :=
  if bitWidth == 64 then .param inputOffset else .narrowParam bitWidth inputOffset

/-- Width-dispatch for state loads: UInt64/Int64 keep historical `stateLoad`. -/
private def mkStateLoadExpr (bitWidth : Nat) (fieldIndex : Nat) : Expr :=
  if bitWidth == 64 then .stateLoad fieldIndex
  else .narrowStateLoad bitWidth fieldIndex

private def makeStorageLayoutV1
    (types : NearTypeClosureV1)
    (states : Array StateDeclV1) : CompileResult StorageLayout := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .near "state count is outside the profile limits"
  let mut fields : Array StorageField := #[]
  for state in states do
    unless state.id.toNat == fields.size do
      throw <| .planInvariant .near "semantic state ids must match declaration order"
    -- T8b: scalar state admits UInt{8,16,32,64} / Int64 with byteWidth 1/2/4/8.
    -- KV keys stay one-per-field (no packing); value length is the ABI width.
    requirePublicNearUintAbiOrInt64State nearPlanErr types state (allowNonPublic := true)
    unless isIdentifier state.name do
      throw <| .planInvariant .near s!"state name '{state.name}' is not a safe identifier"
    let byteWidth ← abiByteWidthOfTypeV1 types state.typeId
    fields := fields.push {
      sourceId := state.id.toNat
      name := state.name
      key := stateKey state.id.toNat
      byteWidth
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

private def makeParamsV1 (owner : String) (types : NearTypeClosureV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .near s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  let mut nextInputOffset : Nat := 0
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .near
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    -- T8b+T9e: ABI params admit UInt{8,16,32,64,128,256}/Int{8..64}; cumulative pitch.
    requirePublicNearUintAbiOrInt64Param nearPlanErr types owner param
      (allowNonPublic := true)
    unless isIdentifier param.name do
      throw <| .planInvariant .near
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let isInt := (types.intWidthOf param.typeId).isSome
    let byteWidth ← abiByteWidthOfTypeV1 types param.typeId
    let bitWidth := bitWidthOfByteWidth byteWidth
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      inputOffset := nextInputOffset
      byteWidth
      endianness := .little
    }
    nextInputOffset := nextInputOffset + slotPitchOfByteWidth byteWidth
    planned := planned.push binding
    let kind ←
      if isInt then pure NearValueKindV1.int64
      else match uintKindOfWidthV1 bitWidth with
        | some k => pure k
        | none =>
            throw <| .planInvariant .near
              s!"unsupported NEAR semantic shape: ABI UInt{bitWidth} is not admitted"
    values := values.push {
      -- T8c: narrow ABI params retain semantic width for body arithmetic;
      -- IR loads still zero-extend into i64 temps.
      expr := mkParamExpr bitWidth binding.inputOffset
      kind
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

/-- Width-dispatch: UInt64 keeps historical constructors; narrow widths use
    `narrow*` so Emit can attach width overflow/mask guards. -/
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
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedAdd bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedSubValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedSub bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedMulValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedMul bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedDivValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedDiv bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeCheckedModValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkCheckedMod bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitAndValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitAnd bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitOrValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitOr bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeBitXorValueV1
    (kind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkBitXor bitWidth) kind kind kind lhsId rhsId lhs rhs

private def makeShlValueV1
    (lhsKind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkShl bitWidth) lhsKind .uint32 lhsKind
    lhsId rhsId lhs rhs

private def makeShrValueV1
    (lhsKind : NearValueKindV1) (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueKindsV1 (mkShr bitWidth) lhsKind .uint32 lhsKind
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
    (kind : NearValueKindV1) (bitWidth : Nat)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (mkBitNot bitWidth) kind kind operandId operand

private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (fun o => .boolNot o) .bool .bool operandId operand

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless lhs.kind == rhs.kind do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: comparison operand kinds do not match"
  unless (widthOfUintKindV1 lhs.kind).isSome do
    throw <| .planInvariant .near
      "unsupported NEAR semantic shape: unsigned comparison requires UInt operands"
  let bw := match widthOfUintKindV1 lhs.kind with | some w => w | none => 64
  if bw > 64 then
    makeBinaryTreeValueKindsV1 (fun l r => .wideCompare bw op l r) lhs.kind rhs.kind .bool
      lhsId rhsId lhs rhs
  else
    makeBinaryTreeValueKindsV1 (fun l r => .compare op l r) lhs.kind rhs.kind .bool
      lhsId rhsId lhs rhs

/-- Admit a wire result TypeId for UInt-width arithmetic/bitwise and return
    `(typeId, kind, bitWidth)`. UInt8/16/32/64 only; UInt128/256 fail closed. -/
private def admitUIntWidthResultTypeV1
    (types : NearTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × NearValueKindV1 × Nat) := do
  match types.uintWidthOf resultTypeId with
  | some w =>
      unless isNearBodyUintWidth w do
        throw <| .planInvariant .near
          s!"unsupported NEAR semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
      match uintKindOfWidthV1 w with
      | some k => pure (resultTypeId, k, w)
      | none =>
          throw <| .planInvariant .near
            s!"unsupported NEAR semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
  | none =>
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: arithmetic/bitwise result must be admitted UInt width"

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
    unless arg.kind == .uint64 || arg.kind == .int64 do
      throw <| .planInvariant .near
        "unsupported NEAR semantic shape: pureCall arguments must be UInt64 or Int64"
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
        if let some bitWidth := types.intWidthOf typeId then
          unless isAbiIntWidth bitWidth do
            throw <| .planInvariant .near
              s!"unsupported NEAR semantic shape: Int{bitWidth} literal is not admitted"
          let value ← decodeIntWidthLiteralLe nearPlanErr "NEAR" bitWidth bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            kind := .int64
            depth := 1
            expandedNodes := 1
            dependencies := #[]
          }
        else if let some bitWidth := types.uintWidthOf typeId then
          unless isNearBodyUintWidth bitWidth do
            throw <| .planInvariant .near
              s!"unsupported NEAR semantic shape: UInt{bitWidth} literal is not admitted"
          let kind ← match uintKindOfWidthV1 bitWidth with
            | some k => pure k
            | none =>
                throw <| .planInvariant .near
                  s!"unsupported NEAR semantic shape: UInt{bitWidth} literal is not admitted"
          if bitWidth ≤ 64 then
            let value ← decodeUIntWidthLiteralLe nearPlanErr "NEAR" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .literal value
              kind
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
          else
            let n ← decodeUIntWideLiteralLe nearPlanErr "NEAR" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .bigLiteral bitWidth n
              kind
              depth := 1
              expandedNodes := 1
              dependencies := #[]
            }
        else
          let boolTypeId ← match types.boolTypeId with
            | some tid =>
                unless typeId == tid do
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: literal is not admitted UInt width, Int64, or Bool"
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
        let isInt := (types.intWidthOf result.typeId).isSome
        let bitWidth ←
          if isInt then pure 64
          else match types.uintWidthOf result.typeId with
            | some w =>
                unless isNearAbiUintWidth w do
                  throw <| .planInvariant .near
                    s!"unsupported NEAR semantic shape: state load UInt{w} is not admitted"
                pure w
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: state load must be UInt{8,16,32,64} or Int64"
        unless field.byteWidth == byteWidthOfBitWidth bitWidth do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: state load width does not match field layout"
        let kind ←
          if isInt then pure NearValueKindV1.int64
          else match uintKindOfWidthV1 bitWidth with
            | some k => pure k
            | none =>
                throw <| .planInvariant .near
                  s!"unsupported NEAR semantic shape: state load UInt{bitWidth} is not admitted"
        values := ← appendResultValueV1 result.typeId values result {
          -- T8c: narrow ABI loads retain semantic width for body arithmetic;
          -- IR still zero-extends into i64 temps.
          expr := mkStateLoadExpr bitWidth field.sourceId
          kind
          depth := 1
          expandedNodes := 1
          dependencies := #[]
        }
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values stableCount segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values stableCount segmentStart armReadables rhsId
        if op == .and || op == .or then
          let boolTypeId ← match types.boolTypeId with
            | some tid => pure tid
            | none =>
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: Bool type is missing for logical op"
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: logical result must be Bool"
          let value ←
            if op == .and then makeBoolAndValueV1 lhsId rhsId lhs rhs
            else makeBoolOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        else if op == .shl || op == .shr then
          -- Shifts: admitted body UInt/Int64 operand, UInt32 count; result matches lhs.
          unless (widthOfUintKindV1 lhs.kind).isSome || lhs.kind == .int64 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: shift operand must be admitted integer width"
          unless rhs.kind == .uint32 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: shift count must be UInt32"
          if lhs.kind == .int64 then
            let resultTid ← match types.int64TypeId with
              | some tid =>
                  unless result.typeId == tid do
                    throw <| .planInvariant .near
                      "unsupported NEAR semantic shape: Int64 shift result type mismatch"
                  pure tid
              | none => throw (.planInvariant .near
                  "unsupported NEAR semantic shape: Int64 type is missing for shift")
            if op == .shl then
              let value ← makeShlValueV1 .int64 64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 resultTid values result value
            else
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .sar l r)
                .int64 .uint32 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 resultTid values result value
          else
            let (widthTid, kind, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            unless kind == lhs.kind do
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: shift result width mismatch"
            let value ←
              if op == .shl then makeShlValueV1 kind bitWidth lhsId rhsId lhs rhs
              else makeShrValueV1 kind bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        else
          -- Body multi-width UInt arithmetic / bitwise / comparison, or Int64.
          unless lhs.kind != .bool && rhs.kind != .bool do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: binary operands must be integer"
          unless (lhs.kind == .int64) == (rhs.kind == .int64) do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: binary operands must share signedness"
          if lhs.kind == .int64 then
            let wordTid ← match types.intWidthOf result.typeId with
              | some _ => pure result.typeId
              | none => throw (.planInvariant .near
                  "unsupported NEAR semantic shape: Int type is missing")
            if op == .add then
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedAdd l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .sub then
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedSub l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .mul then
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedMul l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .div then
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedDiv l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .mod then
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: arithmetic result type mismatch"
              let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCheckedMod l r)
                .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .bitAnd || op == .bitOr || op == .bitXor then
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: bitwise result type mismatch"
              let value ←
                if op == .bitAnd then
                  makeBinaryTreeValueKindsV1 (fun l r => .bitAnd l r)
                    .int64 .int64 .int64 lhsId rhsId lhs rhs
                else if op == .bitOr then
                  makeBinaryTreeValueKindsV1 (fun l r => .bitOr l r)
                    .int64 .int64 .int64 lhsId rhsId lhs rhs
                else
                  makeBinaryTreeValueKindsV1 (fun l r => .bitXor l r)
                    .int64 .int64 .int64 lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
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
                  let value ← makeBinaryTreeValueKindsV1 (fun l r => .signedCompare cmpOp l r)
                    .int64 .int64 .bool lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: only checked Int64 arith/bitwise and comparisons are supported"
          else
            -- Unsigned body multi-width path (UInt8/16/32/64).
            unless lhs.kind == rhs.kind do
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: binary operands must share admitted UInt width"
            let some bitWidth := widthOfUintKindV1 lhs.kind |
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: binary operands must be admitted UInt width"
            unless isNearBodyUintWidth bitWidth do
              throw <| .planInvariant .near
                s!"unsupported NEAR semantic shape: UInt{bitWidth} is not an admitted body width"
            if op == .add || op == .sub || op == .mul || op == .div ||
                op == .mod || op == .bitAnd || op == .bitOr || op == .bitXor then
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == lhs.kind && w == bitWidth do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: arithmetic/bitwise result width mismatch"
              let value ←
                if op == .add then makeCheckedAddValueV1 kind w lhsId rhsId lhs rhs
                else if op == .sub then makeCheckedSubValueV1 kind w lhsId rhsId lhs rhs
                else if op == .mul then makeCheckedMulValueV1 kind w lhsId rhsId lhs rhs
                else if op == .div then makeCheckedDivValueV1 kind w lhsId rhsId lhs rhs
                else if op == .mod then makeCheckedModValueV1 kind w lhsId rhsId lhs rhs
                else if op == .bitAnd then makeBitAndValueV1 kind w lhsId rhsId lhs rhs
                else if op == .bitOr then makeBitOrValueV1 kind w lhsId rhsId lhs rhs
                else makeBitXorValueV1 kind w lhsId rhsId lhs rhs
              values := ← appendResultValueV1 widthTid values result value
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
                    "unsupported NEAR semantic shape: only checked multi-width UInt arith/bitwise, shift, Bool logical, and comparisons are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values stableCount segmentStart armReadables operandId
        match op with
        | .bitNot =>
            if operand.kind == .int64 then
              let wordTid ← match types.intWidthOf result.typeId with
              | some _ => pure result.typeId
              | none => throw (.planInvariant .near
                  "unsupported NEAR semantic shape: Int type is missing")
              unless result.typeId == wordTid do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: bitNot result type mismatch"
              let value ← makeBitNotValueV1 .int64 64 operandId operand
              values := ← appendResultValueV1 wordTid values result value
            else
              let some bitWidth := widthOfUintKindV1 operand.kind |
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: bitNot operand must be admitted integer width"
              let (widthTid, kind, w) ← admitUIntWidthResultTypeV1 types result.typeId
              unless kind == operand.kind && w == bitWidth do
                throw <| .planInvariant .near
                  "unsupported NEAR semantic shape: bitNot result width mismatch"
              let value ← makeBitNotValueV1 kind w operandId operand
              values := ← appendResultValueV1 widthTid values result value
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
            unless operand.kind == .int64 do
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: Op.Unary.neg requires Int64"
            let tid ← match types.int64TypeId with
              | some t => pure t
              | none => throw (.planInvariant .near
                  "unsupported NEAR semantic shape: Int64 type is missing for neg")
            unless result.typeId == tid do
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: checkedNeg result must be Int64"
            let value ← makeUnaryTreeValueV1 (fun o => .checkedNeg o) .int64 .int64
              operandId operand
            values := ← appendResultValueV1 tid values result value
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
          | .int64 =>
              match types.int64TypeId with
              | some tid => pure tid
              | none => throw (.planInvariant .near
                  "unsupported NEAR semantic shape: Int64 type is missing for pureCall")
          | .bool =>
              match types.boolTypeId with
              | some tid => pure tid
              | none =>
                  throw <| .planInvariant .near
                    "unsupported NEAR semantic shape: Bool type is missing for pureCall result"
          | .uint32 | .uint16 | .uint8 | .uint128 | .uint256 =>
              throw <| .planInvariant .near
                "unsupported NEAR semantic shape: pureCall result cannot be narrow/multiword UInt"
        unless result.typeId == expectedTypeId do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: pureCall result type does not match the callee"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values stableCount segmentStart armReadables argId
          unless root.kind == .uint64 || root.kind == .int64 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: pureCall arguments must be UInt64 or Int64"
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
        let expectedBitWidth := bitWidthOfByteWidth field.byteWidth
        -- T8c: store value width must match field layout (narrow body temps OK).
        if root.kind == .int64 then
          unless field.byteWidth == 8 do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: Int state store requires 8-byte field"
        else
          let some valueWidth := widthOfUintKindV1 root.kind |
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: state store value must be admitted UInt width or Int64"
          unless valueWidth == expectedBitWidth do
            throw <| .planInvariant .near
              s!"unsupported NEAR semantic shape: state store value width {valueWidth} must match field bitWidth {expectedBitWidth}"
          unless isNearAbiUintWidth valueWidth do
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: state store value must be admitted UInt width or Int64"
        let value ← consumeCurrentSegmentV1 values stableCount segmentStart valueId
        body := body.push (.store {
          fieldIndex := field.sourceId
          value
          byteWidth := field.byteWidth
        })
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
    -- N5: Commit = identity passthrough; ContextRead declined (no clock ABI).
    | .commit valueId, some result => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          throw <| .planInvariant .near
            "unsupported NEAR semantic shape: Commit is not admitted by pilot context policy"
        let operand ← findValueV1 values valueId
        values := ← appendResultValueV1 result.typeId values result {
          expr := operand.expr
          kind := operand.kind
          depth := operand.depth + 1
          expandedNodes := operand.expandedNodes + 1
          dependencies := operand.dependencies.push valueId
        }
    | .contextRead key, some _ =>
        unless key == unixTimeSecondsContextKeyV1 do
          throw <| .planInvariant .near
            s!"unsupported NEAR semantic shape: unknown ContextRead key '{key.value}'"
        throw <| .planInvariant .near
          "unsupported NEAR semantic shape: ContextRead is not admitted by pilot context policy"
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
              | .uint16 => "UInt16"
              | .uint8 => "UInt8"
              | .uint128 => "UInt128"
              | .uint256 => "UInt256"
              | .bool => "Bool"
              | .int64 => "Int64"
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
  let (params, initialValues) ← makeParamsV1 owner types callable.params
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
    exactInputLen := exactInputLenOfParams lowered.params
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
    match types.uintWidthOf callable.result.typeId with
    | some 8 => pure (MethodResultKind.uint8, some NearValueKindV1.uint8)
    | some 16 => pure (MethodResultKind.uint16, some NearValueKindV1.uint16)
    | some 32 => pure (MethodResultKind.uint32, some NearValueKindV1.uint32)
    | some 64 => pure (MethodResultKind.uint64, some NearValueKindV1.uint64)
    | some 128 => pure (MethodResultKind.uint128, some NearValueKindV1.uint128)
    | some 256 => pure (MethodResultKind.uint256, some NearValueKindV1.uint256)
    | some _ =>
        throw <| .planInvariant .near
          s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int64, or Bool"
    | none =>
        match types.intWidthOf callable.result.typeId with
        | some 8 => pure (MethodResultKind.int8, some NearValueKindV1.int64)
        | some 16 => pure (MethodResultKind.int16, some NearValueKindV1.int64)
        | some 32 => pure (MethodResultKind.int32, some NearValueKindV1.int64)
        | some 64 => pure (MethodResultKind.int64, some NearValueKindV1.int64)
        | some w =>
            throw <| .planInvariant .near
              s!"entry '{name}' does not return public Int{w}"
        | none =>
          if types.boolTypeId == some callable.result.typeId then
            pure (MethodResultKind.bool, some NearValueKindV1.bool)
          else
            throw <| .planInvariant .near
              s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int8/16/32/64, or Bool"
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
    exactInputLen := exactInputLenOfParams lowered.params
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
partial def statementsUsePromiseV1 (statements : Array Statement) : Bool :=
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

def planUsesPromiseV1 (plan : Plan) : Bool :=
  statementsUsePromiseV1 plan.initializer.body ||
    plan.entries.any (fun m => statementsUsePromiseV1 m.body) ||
    plan.fns.any (fun f => statementsUsePromiseV1 f.body)
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
          else if types.int64TypeId == some callable.result.typeId then
            pure NearValueKindV1.int64
          else if types.boolTypeId == some callable.result.typeId then
            pure NearValueKindV1.bool
          else
            throw <| .planInvariant .near
              "unsupported NEAR semantic shape: pureFn result is not UInt64, Int64, or Bool"
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
  let storage ← makeStorageLayoutV1 types source.logicalState
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

/-- Internal Near family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .near do
    throw <| .planInvariant .near "engineering capability kind is not NEAR"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

end ProofForgeV2.Targets.Near
