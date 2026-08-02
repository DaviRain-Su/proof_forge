import ProofForgeV2.Targets.Common
import ProofForgeV2.Targets.DescriptorDataV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EnvelopeV1
import ProofForgeV2.Compiler.Pipeline

/-!
# Solana LowerSemanticV1 — Plan types + SemanticProgramV1 → Plan lowering

Owns the Solana-owned Plan surface and Semantic→Plan body.
-/

namespace ProofForgeV2.Targets.Solana

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Targets.DescriptorDataV1
open ProofForgeV2.Targets.EnvelopeV1

/-- Shared descriptor data (single source: DescriptorDataV1). -/
def descriptor : TargetDescriptor := DescriptorDataV1.solana

def discriminatorDomain : String := "proof-forge-solana-v1:"
def layoutDomain : String := "proof-forge-solana-layout-v1:"
def discriminatorBytes : Nat := 8
def stateHeaderBytes : Nat := 8
/-- Policy program_error codes for the plan-only sBPF surface. Disjoint ranges:
    `0x1001` arithmetic overflow (checked add/sub/mul/div/mod and `shl` result
    ≥ 2^64), `0x1002` bare assert failure, `0x1003` static loop-bound exceeded
    (reference `boundExceeded` at the latch back edge), `0x1004` invalid shift
    count (reference `invalidShift` when the UInt32 count is ≥ 64 for `shl`/
    `shr`), and `declaredErrorBase + i` for declared program errors. -/
def arithmeticOverflowError : Nat := 0x1001
def assertionFailedError : Nat := 0x1002
/-- Static `for ... bounded N` exceeded: the (N+1)-th body has executed and the
    back edge is taken (reference `boundExceeded`). Distinct from arithmetic
    overflow and bare assert. -/
def loopBoundExceededError : Nat := 0x1003
/-- Shift count ≥ 64 (reference `invalidShift`). Distinct from arithmetic
    overflow; `shl` may still raise `arithmeticOverflowError` when the shifted
    result does not fit in UInt64. -/
def invalidShiftError : Nat := 0x1004

inductive Endianness where
  | little
  deriving BEq, Inhabited, Repr

inductive OwnerPolicy where
  | currentProgram
  deriving BEq, Inhabited, Repr

inductive InitializationPolicy where
  | mustBeUninitialized
  | mustBeInitialized
  deriving BEq, Inhabited, Repr

inductive PayloadInitializationPolicy where
  | zeroAllFields
  deriving BEq, Inhabited, Repr

inductive HandlerMode where
  | initialize
  | mutate
  | view
  deriving BEq, Inhabited, Repr

/-- Entry/view return ABI kind. Init handlers ignore this field (IDL `null`).
    Bool is a single-byte 0/1 return-data payload; UInt64/Int64 are 8-byte LE;
    UInt{8,16,32} are 1/2/4-byte LE (T9a); UInt128/256 are 16/32-byte LE multiword (T9e). -/
inductive ResultKind where
  | u64
  | bool
  | i64
  | u8
  | u16
  | u32
  /-- T9c-2: narrow public Int entry/view results. -/
  | i8
  | i16
  | i32
  /-- T9e: multiword public UInt entry/view results (16/32-byte LE). -/
  | u128
  | u256
  deriving BEq, Inhabited, Repr

structure StateField where
  sourceId : Nat
  name : String
  accountIndex : Nat
  byteOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  /-- T9c-2: signed Int field (layout marker i*-le for narrow widths). -/
  isInt : Bool := false
  deriving BEq, Inhabited, Repr

structure StateAccount where
  index : Nat
  name : String
  ownerPolicy : OwnerPolicy
  exactDataLen : Nat
  headerOffset : Nat
  headerWidth : Nat
  initializedMarker : UInt64
  payloadInitialization : PayloadInitializationPolicy
  fields : Array StateField
  /-- ArrayState: `stateLeaves[stateId]` lists physical field indices for that
      logical state (scalar → singleton; fixed `Array UInt64 N` → N consecutive
      slots). Empty array means legacy 1:1 `fields[stateId]`. -/
  stateLeaves : Array (Array Nat) := #[]
  deriving BEq, Inhabited, Repr

structure AccountAccess where
  accountIndex : Nat
  ownerPolicy : OwnerPolicy
  exactDataLen : Nat
  signerRequired : Bool
  writableRequired : Bool
  initialization : InitializationPolicy
  deriving BEq, Inhabited, Repr

structure Param where
  sourceId : Nat
  name : String
  dataOffset : Nat
  byteWidth : Nat
  endianness : Endianness
  /-- True when the parameter is Int64 (same 8-byte LE layout). -/
  isInt : Bool := false
  deriving BEq, Inhabited, Repr

inductive ComparisonOp where
  | eq | ne | lt | le | gt | ge
  deriving BEq, Inhabited, Repr

inductive Expr where
  | literal (value : UInt64)
  /-- Multi-limb literal for UInt128/256 (T9e). `bitWidth ∈ {128,256}`; Emit
      lowers to LE u64 limbs (`bitWidth/64` consecutive temps). -/
  | bigLiteral (bitWidth : Nat) (value : Nat)
  | param (dataOffset : Nat)
  /-- Narrow/wide ABI param load (`bitWidth ∈ {8,16,32,128,256}`); UInt64/Int64 keep `param`. -/
  | narrowParam (bitWidth : Nat) (dataOffset : Nat)
  | stateLoad (accountIndex byteOffset : Nat)
  /-- Narrow/wide ABI state load (`bitWidth ∈ {8,16,32,128,256}`); UInt64/Int64 keep `stateLoad`. -/
  | narrowStateLoad (bitWidth : Nat) (accountIndex byteOffset : Nat)
  | checkedAdd (lhs rhs : Expr)
  | checkedSub (lhs rhs : Expr)
  | checkedMul (lhs rhs : Expr)
  | checkedDiv (lhs rhs : Expr)
  | checkedMod (lhs rhs : Expr)
  /-- Checked Int64 arithmetic (sBPF software guards / signed ops). -/
  | signedCheckedAdd (lhs rhs : Expr)
  | signedCheckedSub (lhs rhs : Expr)
  | signedCheckedMul (lhs rhs : Expr)
  | signedCheckedDiv (lhs rhs : Expr)
  | signedCheckedMod (lhs rhs : Expr)
  /-- Plain UInt64 bitwise AND (no failure mode). -/
  | bitAnd (lhs rhs : Expr)
  /-- Plain UInt64 bitwise OR (no failure mode). -/
  | bitOr (lhs rhs : Expr)
  /-- Plain UInt64 bitwise XOR (no failure mode). -/
  | bitXor (lhs rhs : Expr)
  /-- UInt64 `<<` with UInt32 count: count ≥ 64 → invalidShift; result ≥ 2^64
      → arithmeticOverflow. -/
  | shl (lhs rhs : Expr)
  /-- UInt64 `>>` with UInt32 count: count ≥ 64 → invalidShift. -/
  | shr (lhs rhs : Expr)
  /-- Int64 arithmetic right shift; count ≥ 64 → invalidShift. -/
  | sar (lhs rhs : Expr)
  | bitNot (operand : Expr)
  | boolNot (operand : Expr)
  /-- Checked Int64 negation (reverts on intMin). -/
  | checkedNeg (operand : Expr)
  /-- Strict Bool `&&` (both operands always evaluated; no failure mode). -/
  | boolAnd (lhs rhs : Expr)
  /-- Strict Bool `||` (both operands always evaluated; no failure mode). -/
  | boolOr (lhs rhs : Expr)
  | compare (op : ComparisonOp) (lhs rhs : Expr)
  /-- Multiword unsigned compare (`bitWidth ∈ {128,256}`); result is Bool. -/
  | wideCompare (bitWidth : Nat) (op : ComparisonOp) (lhs rhs : Expr)
  | signedCompare (op : ComparisonOp) (lhs rhs : Expr)
  | callFn (fnIndex : Nat) (args : Array Expr)
  /-- Plan-level loop induction temporary (bound by `Statement.forLoop`). -/
  | temp (id : Nat)
  /-- Checked add at `bitWidth ∈ {8,16,32}` (body multi-width). UInt64 keeps
      historical `checkedAdd` so plan/IR goldens stay byte-identical. -/
  | narrowCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitAnd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitOr (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitXor (bitWidth : Nat) (lhs rhs : Expr)
  | narrowBitNot (bitWidth : Nat) (operand : Expr)
  /-- Left shift of a narrow UInt value; count is UInt32. Count ≥ 64 →
      invalidShift; shifted result exceeding the width mask → overflow. -/
  | narrowShl (bitWidth : Nat) (lhs rhs : Expr)
  | narrowShr (bitWidth : Nat) (lhs rhs : Expr)
  /-- T9c-2: checked signed arithmetic on Int{8,16,32}; Int64 keeps signedChecked*. -/
  | narrowSignedCheckedAdd (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedSub (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMul (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedDiv (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCheckedMod (bitWidth : Nat) (lhs rhs : Expr)
  | narrowSignedCompare (bitWidth : Nat) (op : ComparisonOp) (lhs rhs : Expr)
  | narrowCheckedNeg (bitWidth : Nat) (operand : Expr)
  /-- Arithmetic right shift of Int{8,16,32}; count ≥ bitWidth → invalidShift. -/
  | narrowSar (bitWidth : Nat) (lhs rhs : Expr)
  deriving BEq, Inhabited, Repr

structure Store where
  accountIndex : Nat
  byteOffset : Nat
  value : Expr
  /-- Physical store width in bytes (`1/2/4/8/16/32`). Default 8 keeps historical
      UInt64/Int64 Plan literals byte-identical. T9e: 16/32 for UInt128/256. -/
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
      array (≥2). Program id for the CPI-shaped site is the first 32 bytes of
      SHA-256(UTF-8 of the target path = all-but-last components joined by
      "."); method is the last component. Not a dynamic pubkey ValueId
      (B-3 Principal remains fail-closed). -/
  | externalCall (callee : Array String) (args : Array Expr)
  /-- Async fire-and-forget schedule (void). Same static-callee program-id
      derivation; no response channel (matches Reference schedule). -/
  | schedule (callee : Array String) (args : Array Expr)
  | ifThenElse (condition : Expr) (thenBody elseBody : Array Statement)
  | switchOn (scrutinee : Expr) (cases : Array (UInt64 × Array Statement))
      (defaultBody : Array Statement)
  /-- Bounded `for` recovered from a Normalize loop header/latch/exit CFG.
      `varTemp` is the induction temporary; `initial` seeds it; `cond` is the
      header predicate (references `.temp varTemp`); `update` is the latch
      expression (also may reference `.temp varTemp`); `maxIterations` is the
      static bound from `loopBounds` (reference enforces it at the back edge:
      the (N+1)-th body executes, then reverts); `body` is the then-arm region
      ending at the back edge. After the loop, control falls through. -/
  | forLoop (varTemp : Nat) (initial cond update : Expr) (maxIterations : Nat)
      (body : Array Statement)
  deriving BEq, Inhabited, Repr

structure Handler where
  name : String
  discriminator : String
  params : Array Param
  mode : HandlerMode
  resultKind : ResultKind
  accountAccess : AccountAccess
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- Pure local function binding (retained Semantic pureFn). Params reuse the
    handler Param layout; `resultIsBool` selects UInt64 vs Bool return. -/
structure FnBinding where
  name : String
  params : Array Param
  resultIsBool : Bool
  resultIsInt : Bool := false
  body : Array Statement
  deriving BEq, Inhabited, Repr

/-- One declared event/error binding: its name and UInt64 argument count. -/
structure InterfaceBinding where
  name : String
  fieldCount : Nat
  deriving BEq, Inhabited, Repr

/-- Every Solana-specific ABI, account, layout, and dispatch decision for the
current UInt64 planning fragment. It deliberately retains no SemanticProgram. -/
structure Plan where
  codegenProfile : String
  instructionDiscriminatorDomain : String
  instructionDiscriminatorBytes : Nat
  stateLayoutDomain : String
  arithmeticOverflowError : Nat
  assertionFailedError : Nat
  loopBoundExceededError : Nat
  invalidShiftError : Nat
  programName : String
  stateAccount : StateAccount
  events : Array InterfaceBinding
  errors : Array InterfaceBinding
  fns : Array FnBinding
  initializer : Handler
  entries : Array Handler
  deriving BEq, Inhabited, Repr
private def planError (message : String) : CompileResult α :=
  .error <| .planInvariant .solana message

private def maxIdentifierBytes : Nat := 240
-- `.sbpf-plan` is the longest emitted suffix (10 bytes) under the CLI's
-- 240-byte relative-path ceiling.
def maxArtifactStemBytes : Nat := 230
def maxStateFields : Nat := 1024
def maxEntries : Nat := 255
def maxParams : Nat := 64
def maxBodyStatements : Nat := 4096
def maxExprDepth : Nat := 256
def maxPlanNodes : Nat := 100000

/-- Thin adapter: binds Solana's `maxIdentifierBytes` (240) to the shared grammar. -/
def isIdentifier (value : String) : Bool :=
  isAsciiIdentifier maxIdentifierBytes value

def validDiscriminator (value : String) : Bool :=
  value.length == 2 * discriminatorBytes && value.toList.all (fun character =>
    "0123456789abcdef".contains character)

/-- Layout field type suffix. Unsigned: u*-le. Signed narrow: i8/i16/i32-le;
    Int64 keeps historical u64-le. T9e: u128-le / u256-le. -/
def layoutFieldTypeSuffix (byteWidth : Nat) (isInt : Bool := false) : String :=
  if isInt then
    match byteWidth with
    | 1 => "i8-le"
    | 2 => "i16-le"
    | 4 => "i32-le"
    | _ => "u64-le"
  else
    match byteWidth with
    | 1 => "u8-le"
    | 2 => "u16-le"
    | 4 => "u32-le"
    | 16 => "u128-le"
    | 32 => "u256-le"
    | _ => "u64-le"

/-- Instruction-arg type string for discriminator signature and IDL.
    Int64 keeps historical `"u64"`; narrow Int uses i8/i16/i32; T9e u128/u256. -/
def abiParamTypeString (p : Param) : String :=
  if p.isInt then
    match p.byteWidth with
    | 1 => "i8"
    | 2 => "i16"
    | 4 => "i32"
    | _ => "u64"
  else match p.byteWidth with
  | 1 => "u8"
  | 2 => "u16"
  | 4 => "u32"
  | 16 => "u128"
  | 32 => "u256"
  | _ => "u64"

/-- Account/instruction slot pitch for a physical field/param width.
    UInt{8,16,32,64} keep 8-byte pitch; UInt128 → 16; UInt256 → 32. -/
def slotPitchOfByteWidth (byteWidth : Nat) : Nat :=
  let limbs := (byteWidth + 7) / 8
  if limbs ≤ 1 then 8 else limbs * 8

private def layoutFieldSignature (field : StateField) : String :=
  s!"{field.sourceId}:{field.name}:{field.accountIndex}:{field.byteOffset}:{field.byteWidth}:{layoutFieldTypeSuffix field.byteWidth field.isInt}"

private def layoutSignature (fields : Array StateField) : String :=
  s!"{fields.size}|{String.intercalate "|" (fields.toList.map layoutFieldSignature)}"

private def firstWordBE (bytes : ByteArray) : UInt64 := Id.run do
  let mut value : UInt64 := 0
  for index in [0:8] do
    value := UInt64.shiftLeft value 8 ||| bytes[index]!.toUInt64
  return value

def layoutMarker (fields : Array StateField) : UInt64 :=
  firstWordBE <| Crypto.sha256 (layoutDomain ++ layoutSignature fields).toUTF8

def signature (name : String) (params : Array Param) : String :=
  s!"{name}({String.intercalate "," (params.toList.map abiParamTypeString)})"

def instructionDiscriminator (name : String) (params : Array Param) : String :=
  ((Crypto.sha256Hex (discriminatorDomain ++ signature name params).toUTF8).take
    (2 * discriminatorBytes)).copy

def accessFor (account : StateAccount) (mode : HandlerMode) : AccountAccess := {
  accountIndex := account.index
  ownerPolicy := account.ownerPolicy
  exactDataLen := account.exactDataLen
  signerRequired := mode == .initialize
  writableRequired := mode != .view
  initialization := if mode == .initialize then
    .mustBeUninitialized
  else
    .mustBeInitialized
}

/-! ### Retained SemanticProgramV1 public-UInt64 Plan lowering

The Solana pilot lowers public-UInt64 state, checked arith/bitwise/shift,
Bool compare/logical, bare assert, emit/revert, pureFn localCall, if/match
regions, bounded for, and **static-callee** external call / schedule
(AddressBearing followup). Wire `Op.ExternalCall`/`Op.Schedule` take a
compile-time `QualifiedName` (not a ValueId address); program id is the
first 32 bytes of SHA-256(UTF-8 target path). B-3 Principal remains
fail-closed (u32-prefixed variable-length identity ≠ 32-byte pubkey). -/

/-- Solana pilot type-closure carrier (shared `PilotTypeClosureV1`).
    Body multi-width admits UInt8/16/32/64; state/params admit
    UInt8/16/32/64 or Int64 (T8b ABI multi-width). -/
private abbrev SolanaTypeClosureV1 := PilotTypeClosureV1

private def solanaPlanErr (message : String) : CompileError :=
  .planInvariant .solana message

/-- Solana pilot accepts anonymous UInt8/16/32/64/128/256/Unit/Bool/Int{8,16,32,64}
    under `pilotUintWidthPolicySolanaBody` + `pilotIntWidthPolicyNarrow`. Body
    multi-width UInt values are allowed; **top-level state and ABI parameters
    admit UInt8/16/32/64/128/256 or Int{8,16,32,64}** via
    `requirePublicSolanaUintAbiOrInt64*` (T8b+T9e) with `allowNonPublic := true`
    (N1). ArrayState: anonymous **Array** shapes are admitted via
    `pilotContainerStatePolicyArrayOnly` (element/layout gated at state planning
    to fixed-length `Array UInt64 N` leaf slots). UInt128/256 use multiword
    software limbs. B-3 / N2c: Principal remains fail-closed (wire identity
    is variable-length u32-prefixed 1..4096 body; not a fixed 32-byte
    Solana pubkey / program id — no silent reinterpret). -/
private def validateSolanaTypeClosureV1
    (types : Array TypeDeclV1) : CompileResult SolanaTypeClosureV1 :=
  validatePilotTypeClosure solanaPlanErr solanaTypeClosureWording types
    pilotUintWidthPolicySolanaBody
    (intPolicy := pilotIntWidthPolicyNarrow)
    (principalPolicy := pilotPrincipalPolicyNone)
    (containerPolicy := pilotContainerStatePolicyArrayOnly)

/-- Resolve admitted scalar state/param TypeId to physical byte width
    (1/2/4/8/16/32). -/
private def abiByteWidthOfTypeV1
    (types : SolanaTypeClosureV1) (typeId : TypeIdV1) : CompileResult Nat := do
  match types.uintWidthOf typeId with
  | some w =>
      unless isSolanaAbiUintWidth w do
        throw <| .planInvariant .solana
          s!"unsupported Solana semantic shape: ABI UInt{w} is not admitted"
      pure (byteWidthOfBitWidth w)
  | none =>
      match types.intWidthOf typeId with
      | some w =>
          unless isAbiIntWidth w do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: ABI Int{w} is not admitted"
          pure (byteWidthOfBitWidth w)
      | none =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: ABI type must be UInt8/16/32/64/128/256 or Int8/16/32/64"

/-- Width-dispatch for ABI param loads: UInt64/Int64 keep historical `param`. -/
private def mkParamExpr (bitWidth : Nat) (dataOffset : Nat) : Expr :=
  if bitWidth == 64 then .param dataOffset else .narrowParam bitWidth dataOffset

/-- Width-dispatch for state loads: UInt64/Int64 keep historical `stateLoad`. -/
private def mkStateLoadExpr (bitWidth : Nat) (accountIndex byteOffset : Nat) : Expr :=
  if bitWidth == 64 then .stateLoad accountIndex byteOffset
  else .narrowStateLoad bitWidth accountIndex byteOffset

/-- ArrayState positive layout: fixed-length `Array UInt64 N` (1 ≤ N ≤ remaining
    state slots). Other container shapes (Map/Bytes/non-UInt64 element/zero
    length) fail closed. -/
private def arrayUInt64LeafCountV1
    (typeDecls : Array TypeDeclV1) (types : SolanaTypeClosureV1)
    (typeId : TypeIdV1) : CompileResult (Option Nat) := do
  unless types.isContainer typeId do
    return none
  match typeDecls[typeId.toNat]? with
  | some { shape := .array elTid len, .. } =>
      unless elTid == types.uint64TypeId do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: Array state element must be UInt64"
      let n := len.toNat
      unless n ≥ 1 do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: Array state length must be ≥ 1"
      pure (some n)
  | some { shape := .map .., .. } =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: Map state is outside the Solana Array-only container pilot"
  | some { shape := .bytes _, .. } =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: Bytes state is outside the Solana Array-only container pilot"
  | _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: container TypeId is not Array/Map/Bytes"

private def makeStateAccountV1
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (states : Array StateDeclV1) : CompileResult StateAccount := do
  if states.isEmpty || states.size > maxStateFields then
    throw <| .planInvariant .solana "state count is outside the profile limits"
  let mut fields : Array StateField := #[]
  let mut stateLeaves : Array (Array Nat) := #[]
  -- Cumulative payload offset (after header). Narrow UInt keep 8-byte pitch;
  -- T9e UInt128/256 advance 16/32 so multiword limbs do not overlap.
  let mut nextOffset : Nat := stateHeaderBytes
  for state in states do
    unless state.id.toNat == stateLeaves.size do
      throw <| .planInvariant .solana "semantic state ids must match declaration order"
    unless isIdentifier state.name do
      throw <| .planInvariant .solana s!"state name '{state.name}' is not a safe identifier"
    match ← arrayUInt64LeafCountV1 typeDecls types state.typeId with
    | some n =>
        -- ArrayState: N consecutive 8-byte UInt64 slots; physical field names
        -- `name_0`..`name_{n-1}` keep layout markers deterministic.
        -- Visibility: same N1 allowNonPublic as scalar state (physical account
        -- bytes are opaque; product disclosure remains CheckV1 authority).
        if fields.size + n > maxStateFields then
          throw <| .planInvariant .solana "state count is outside the profile limits"
        let mut leaves : Array Nat := #[]
        for i in [0:n] do
          let leafName := state.name ++ "_" ++ toString i
          unless isIdentifier leafName do
            throw <| .planInvariant .solana
              s!"state name '{leafName}' is not a safe identifier"
          leaves := leaves.push fields.size
          fields := fields.push {
            sourceId := state.id.toNat
            name := leafName
            accountIndex := 0
            byteOffset := nextOffset
            byteWidth := 8
            endianness := .little
          }
          nextOffset := nextOffset + 8
        stateLeaves := stateLeaves.push leaves
    | none =>
        -- T8b+T9e: scalar state admits UInt{8,16,32,64,128,256}/Int{8,16,32,64}
        -- with byteWidth 1/2/4/8/16/32. Pitch = slotPitchOfByteWidth.
        requirePublicSolanaUintAbiOrInt64State solanaPlanErr types state
          (allowNonPublic := true)
        let byteWidth ← abiByteWidthOfTypeV1 types state.typeId
        let leafIdx := fields.size
        fields := fields.push {
          sourceId := state.id.toNat
          name := state.name
          accountIndex := 0
          byteOffset := nextOffset
          byteWidth
          endianness := .little
          isInt := (types.intWidthOf state.typeId).isSome
        }
        nextOffset := nextOffset + slotPitchOfByteWidth byteWidth
        stateLeaves := stateLeaves.push #[leafIdx]
  let marker := layoutMarker fields
  if marker == 0 then
    throw <| .planInvariant .solana
      "state layout marker collides with the reserved uninitialized zero value"
  pure {
    index := 0
    name := "state"
    ownerPolicy := .currentProgram
    exactDataLen := nextOffset
    headerOffset := 0
    headerWidth := stateHeaderBytes
    initializedMarker := marker
    payloadInitialization := .zeroAllFields
    fields
    stateLeaves
  }

private structure LoweredValueV1 where
  expr : Expr
  depth : Nat
  expandedNodes : Nat
  dependencies : Array ValueIdV1
  isBool : Bool
  /-- True for anonymous UInt32 values (shift counts and body UInt32 temps).
      Never simultaneously Bool or Int. Prefer `bitWidth` for width gates. -/
  isUInt32 : Bool := false
  /-- True for Int64-typed values (mutually exclusive with isBool/isUInt32). -/
  isInt : Bool := false
  /-- Bit width of non-Bool values: 8/16/32/64/128/256. Bool uses 1. -/
  bitWidth : Nat := 64
  /-- ArrayState multi-leaf carrier: `some` = fixed Array UInt64 N; `expr`
      mirrors `leaves[0]!` (or literal 0). Scalar values keep `none`. -/
  aggregateLeaves : Option (Array Expr) := none
  deriving Inhabited

private def LoweredValueV1.isAggregate (v : LoweredValueV1) : Bool :=
  v.aggregateLeaves.isSome

private def LoweredValueV1.leafExprs (v : LoweredValueV1) : Array Expr :=
  match v.aggregateLeaves with
  | some ls => ls
  | none => #[v.expr]

private def mkAggregateValueV1 (leaves : Array Expr) (deps : Array ValueIdV1)
    (depth expandedNodes : Nat) : LoweredValueV1 :=
  let head := match leaves[0]? with | some e => e | none => .literal 0
  { expr := head
    depth
    expandedNodes
    dependencies := deps
    isBool := false
    isUInt32 := false
    isInt := false
    bitWidth := 64
    aggregateLeaves := some leaves }

private def makeParamsV1 (owner : String) (types : SolanaTypeClosureV1)
    (params : Array ParameterV1) :
    CompileResult (Array Param × Array LoweredValueV1) := do
  if params.size > maxParams then
    throw <| .planInvariant .solana s!"parameter count in {owner} exceeds profile limit {maxParams}"
  let mut planned : Array Param := #[]
  let mut values : Array LoweredValueV1 := #[]
  -- Cumulative instruction-data offset after discriminator (T9e multiword pitch).
  let mut nextDataOffset : Nat := discriminatorBytes
  for param in params do
    unless param.valueId.toNat == planned.size do
      throw <| .planInvariant .solana
        s!"semantic parameter ValueIds in {owner} must match declaration order"
    -- T8b+T9e: ABI params admit UInt{8,16,32,64,128,256}/Int{8,16,32,64}.
    requirePublicSolanaUintAbiOrInt64Param solanaPlanErr types owner param
      (allowNonPublic := true)
    unless isIdentifier param.name do
      throw <| .planInvariant .solana
        s!"parameter name '{param.name}' in {owner} is not a safe identifier"
    let isInt := (types.intWidthOf param.typeId).isSome
    let byteWidth ← abiByteWidthOfTypeV1 types param.typeId
    let bitWidth := bitWidthOfByteWidth byteWidth
    let binding : Param := {
      sourceId := param.valueId.toNat
      name := param.name
      dataOffset := nextDataOffset
      byteWidth
      endianness := .little
      isInt
    }
    nextDataOffset := nextDataOffset + slotPitchOfByteWidth byteWidth
    planned := planned.push binding
    values := values.push {
      expr := mkParamExpr bitWidth binding.dataOffset
      depth := 1
      expandedNodes := 1
      dependencies := #[]
      isBool := false
      isInt
      isUInt32 := !isInt && bitWidth == 32
      bitWidth
    }
  pure (planned, values)

private def findFieldV1 (account : StateAccount)
    (id : StateIdV1) : CompileResult StateField :=
  -- Scalar 1:1 path: prefer stateLeaves singleton when present.
  match account.stateLeaves[id.toNat]? with
  | some leaves =>
      match leaves[0]? with
      | some fi =>
          match account.fields[fi]? with
          | some field =>
              if field.sourceId == id.toNat && leaves.size == 1 then .ok field
              else if leaves.size != 1 then
                planError s!"semantic expression references multi-leaf state id {id.toNat} as scalar"
              else planError s!"semantic expression references noncanonical state id {id.toNat}"
          | none => planError s!"semantic expression references unknown state id {id.toNat}"
      | none => planError s!"semantic expression references empty leaf list for state id {id.toNat}"
  | none =>
      match account.fields[id.toNat]? with
      | some field =>
          if field.sourceId == id.toNat then .ok field
          else planError s!"semantic expression references noncanonical state id {id.toNat}"
      | none => planError s!"semantic expression references unknown state id {id.toNat}"

/-- Resolve all physical leaf fields for a logical state id (ArrayState). -/
private def findStateLeafFieldsV1 (account : StateAccount)
    (id : StateIdV1) : CompileResult (Array StateField) := do
  match account.stateLeaves[id.toNat]? with
  | some leaves =>
      let mut out : Array StateField := #[]
      for fi in leaves do
        match account.fields[fi]? with
        | some field =>
            unless field.sourceId == id.toNat do
              throw <| .planInvariant .solana
                s!"semantic expression references noncanonical state id {id.toNat}"
            out := out.push field
        | none =>
            throw <| .planInvariant .solana
              s!"semantic expression references unknown state leaf {fi}"
      pure out
  | none =>
      let field ← findFieldV1 account id
      pure #[field]

/-- Require a compile-time UInt32/UInt64 literal index for ArrayState
    IndexGet/IndexSet (dynamic index needs a Plan select surface). -/
private def literalIndexNatV1 (v : LoweredValueV1) : CompileResult Nat := do
  unless !v.isBool && !v.isInt && (v.isUInt32 || v.bitWidth == 32 || v.bitWidth == 64) do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: Array index must be a UInt32/UInt64 literal"
  match v.expr with
  | .literal n => pure n.toNat
  | _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: Array IndexGet/IndexSet requires a compile-time constant index"

private def findValueV1 (values : Array LoweredValueV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 :=
  match values[id.toNat]? with
  | some value => .ok value
  | none => planError s!"semantic expression references unknown ValueId {id.toNat}"

private def decodeUInt64LiteralV1 (bytes : ByteArray) : CompileResult UInt64 :=
  decodeUInt64LiteralLe solanaPlanErr "Solana" bytes

private def decodeBoolLiteralV1 (bytes : ByteArray) : CompileResult Bool :=
  decodeBoolLiteralBit solanaPlanErr "Solana" bytes

/-- Decode a 4-byte little-endian UInt32 shift-count literal into a UInt64
    carrier (plan temps remain 64-bit words; the type flag carries the width).
    Hand-rolled LE without trailing-byte finish check — intentionally not the
    shared `decodeUInt32LiteralLe` (EVM/NEAR path). -/
private def decodeUInt32LiteralV1 (bytes : ByteArray) : CompileResult UInt64 := do
  unless bytes.size == 4 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: UInt32 literal must contain exactly 4 bytes"
  let b0 := bytes[0]!.toNat
  let b1 := bytes[1]!.toNat
  let b2 := bytes[2]!.toNat
  let b3 := bytes[3]!.toNat
  pure (UInt64.ofNat (b0 + b1 * 256 + b2 * 65536 + b3 * 16777216))

/-- Effect-boundary gate: values defined before `blockEntry` dominate this
    block (params, block-param slots, earlier pure SSA). Only in-block pure
    values between `blockEntry` and `segmentStart` are sealed by an effect. -/
private def currentValueV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= blockEntry && index < segmentStart then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Match-bind arm readability: the scrutinee of an enclosing switch may be
    referenced by its arm bodies across the (dominating) scrut-block boundary.
    Dominating pure SSA (`index < blockEntry`) is always readable so loop
    headers may consume pre-header values (e.g. the exclusive end bound). -/
private def currentValueWithArmsV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (id : ValueIdV1) : CompileResult LoweredValueV1 := do
  let index := id.toNat
  if index >= blockEntry && index < segmentStart && !armReadables.contains id then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: computed ValueId crosses an effect boundary"
  findValueV1 values id

/-- Admitted body UInt widths for Solana sBPF (T9e: includes UInt128/256). -/
private def isSolanaBodyUintWidth (w : Nat) : Bool :=
  EnvelopeV1.isSolanaBodyUintWidth w

/-- Shared bounded SSA-tree cost for binary Expr constructors. Operands must
    be non-Bool and share `bitWidth` (+ signedness for non-Bool results).
    Comparison results are Bool (`bitWidth=1`). -/
private def makeBinaryTreeValueV1
    (mk : Expr → Expr → Expr)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1)
    (isBool : Bool)
    (resultBitWidth : Nat)
    (isInt : Bool := false) : CompileResult LoweredValueV1 := do
  unless isBool || (lhs.bitWidth == rhs.bitWidth && lhs.bitWidth == resultBitWidth) do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: binary operands must share integer width"
  unless isBool || isInt || isSolanaBodyUintWidth resultBitWidth do
    throw <| .planInvariant .solana
      s!"unsupported Solana semantic shape: width {resultBitWidth} is not an admitted body width"
  unless isBool || !isInt || isAbiIntWidth resultBitWidth do
    throw <| .planInvariant .solana
      s!"unsupported Solana semantic shape: Int{resultBitWidth} is not an admitted body Int width"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
    isBool
    isUInt32 := !isBool && !isInt && resultBitWidth == 32
    isInt := !isBool && isInt
    bitWidth := if isBool then 1 else resultBitWidth
  }

/-- Admit a wire result TypeId for UInt-width arithmetic/bitwise and return
    `(typeId, bitWidth)`. UInt8/16/32/64 only; UInt128/256 fail closed. -/
private def admitUIntWidthResultTypeV1
    (types : SolanaTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × Nat) := do
  match types.uintWidthOf resultTypeId with
  | some w =>
      unless isSolanaBodyUintWidth w do
        throw <| .planInvariant .solana
          s!"unsupported Solana semantic shape: arithmetic/bitwise result UInt{w} is not admitted"
      pure (resultTypeId, w)
  | none =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: arithmetic/bitwise result must be admitted UInt width"

private def admitIntWidthResultTypeV1
    (types : SolanaTypeClosureV1) (resultTypeId : TypeIdV1) :
    CompileResult (TypeIdV1 × Nat) := do
  match types.intWidthOf resultTypeId with
  | some w =>
      unless isAbiIntWidth w do
        throw <| .planInvariant .solana
          s!"unsupported Solana semantic shape: signed arithmetic result Int{w} is not admitted"
      pure (resultTypeId, w)
  | none =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: signed arithmetic result must be admitted Int width"

/-- Width-dispatch: UInt64 keeps historical constructors; narrow (8/16/32) and
    multiword (128/256) widths use `narrow*` so Emit attaches width guards /
    multi-limb software sequences (T9e). -/
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

private def makeCheckedAddValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedAdd bitWidth) lhsId rhsId lhs rhs false bitWidth (isInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedAdd bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedSubValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedSub bitWidth) lhsId rhsId lhs rhs false bitWidth (isInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedSub bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedMulValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedMul bitWidth) lhsId rhsId lhs rhs false bitWidth (isInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedMul bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedDivValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedDiv bitWidth) lhsId rhsId lhs rhs false bitWidth (isInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedDiv bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeCheckedModValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  if lhs.isInt || rhs.isInt then
    makeBinaryTreeValueV1 (mkSignedCheckedMod bitWidth) lhsId rhsId lhs rhs false bitWidth (isInt := true)
  else
    makeBinaryTreeValueV1 (mkCheckedMod bitWidth) lhsId rhsId lhs rhs false bitWidth

private def makeBitAndValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (mkBitAnd bitWidth) lhsId rhsId lhs rhs false bitWidth
    (isInt := lhs.isInt)

private def makeBitOrValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (mkBitOr bitWidth) lhsId rhsId lhs rhs false bitWidth
    (isInt := lhs.isInt)

private def makeBitXorValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 (mkBitXor bitWidth) lhsId rhsId lhs rhs false bitWidth
    (isInt := lhs.isInt)

/-- Shift tree cost: lhs carries `bitWidth`, count is UInt32 (distinct width). -/
private def makeShiftTreeValueV1
    (mk : Expr → Expr → Expr)
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: shift operands must be integer"
  unless !rhs.isInt do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: shift count must be UInt32"
  unless lhs.bitWidth == bitWidth && isSolanaBodyUintWidth bitWidth do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: shift lhs width mismatch"
  unless rhs.bitWidth == 32 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: shift count must be UInt32"
  let depth := 1 + max lhs.depth rhs.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  if lhs.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  let remaining := maxPlanNodes - 1 - lhs.expandedNodes
  if rhs.expandedNodes > remaining then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk lhs.expr rhs.expr
    depth
    expandedNodes := 1 + lhs.expandedNodes + rhs.expandedNodes
    dependencies := #[lhsId, rhsId]
    isBool := false
    isUInt32 := !lhs.isInt && bitWidth == 32
    isInt := lhs.isInt
    bitWidth
  }

private def makeShlValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  let v ← makeShiftTreeValueV1 (mkShl bitWidth) bitWidth lhsId rhsId lhs rhs
  pure { v with isInt := lhs.isInt }

private def makeShrValueV1
    (bitWidth : Nat)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  if lhs.isInt then
    unless bitWidth == 64 do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: only Int64 arithmetic shift is admitted"
    let v ← makeShiftTreeValueV1 .sar bitWidth lhsId rhsId lhs rhs
    pure { v with isInt := true }
  else
    makeShiftTreeValueV1 (mkShr bitWidth) bitWidth lhsId rhsId lhs rhs

private def makeBoolAndValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .boolAnd lhsId rhsId lhs rhs true 1

private def makeBoolOrValueV1
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeBinaryTreeValueV1 .boolOr lhsId rhsId lhs rhs true 1

private def makeCompareValueV1
    (op : ComparisonOp)
    (lhsId rhsId : ValueIdV1)
    (lhs rhs : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless !lhs.isBool && !rhs.isBool do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: comparison operands must be integer"
  unless lhs.bitWidth == rhs.bitWidth && isSolanaBodyUintWidth lhs.bitWidth do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: comparison operands must share admitted width"
  unless lhs.isInt == rhs.isInt do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: comparison operands must share signedness"
  if lhs.isInt then
    unless isAbiIntWidth lhs.bitWidth do
      throw <| .planInvariant .solana
        s!"unsupported Solana semantic shape: Int{lhs.bitWidth} comparison is not admitted"
    makeBinaryTreeValueV1 (mkSignedCompare lhs.bitWidth op) lhsId rhsId lhs rhs true 1
  else if lhs.bitWidth > 64 then
    makeBinaryTreeValueV1 (.wideCompare lhs.bitWidth op) lhsId rhsId lhs rhs true 1
  else
    makeBinaryTreeValueV1 (.compare op) lhsId rhsId lhs rhs true 1

/-- Unary plan-value constructor (depth/node accounting for bitNot/boolNot/neg). -/
private def makeUnaryTreeValueV1
    (mk : Expr → Expr)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1)
    (isBool : Bool)
    (resultBitWidth : Nat)
    (isInt : Bool := false) : CompileResult LoweredValueV1 := do
  unless isBool || operand.bitWidth == resultBitWidth do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: unary bitNot width mismatch"
  let depth := 1 + operand.depth
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  if operand.expandedNodes > maxPlanNodes - 1 then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
  pure {
    expr := mk operand.expr
    depth
    expandedNodes := 1 + operand.expandedNodes
    dependencies := #[operandId]
    isBool
    isUInt32 := !isBool && !isInt && resultBitWidth == 32
    isInt := !isBool && isInt
    bitWidth := if isBool then 1 else resultBitWidth
  }

private def makeBitNotValueV1
    (bitWidth : Nat)
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 (mkBitNot bitWidth) operandId operand false bitWidth
    (isInt := operand.isInt)

private def makeBoolNotValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 :=
  makeUnaryTreeValueV1 .boolNot operandId operand true 1

private def makeCheckedNegValueV1
    (operandId : ValueIdV1)
    (operand : LoweredValueV1) : CompileResult LoweredValueV1 := do
  unless operand.isInt && !operand.isBool && isAbiIntWidth operand.bitWidth do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: checkedNeg requires admitted Int width operand"
  makeUnaryTreeValueV1 (mkCheckedNeg operand.bitWidth) operandId operand false operand.bitWidth
    (isInt := true)

/-- Pure local-call value: n-ary args, pure expression (not an effect boundary). -/
private def makeCallFnValueV1
    (fnIndex : Nat)
    (argIds : Array ValueIdV1)
    (args : Array LoweredValueV1)
    (isBool : Bool) : CompileResult LoweredValueV1 := do
  let mut depth : Nat := 1
  let mut expandedNodes : Nat := 1
  for arg in args do
    depth := Nat.max depth (1 + arg.depth)
    if arg.expandedNodes > maxPlanNodes - expandedNodes then
      throw <| .planInvariant .solana s!"Solana plan expression exceeds node limit {maxPlanNodes}"
    expandedNodes := expandedNodes + arg.expandedNodes
  if depth > maxExprDepth then
    throw <| .planInvariant .solana s!"Solana plan expression exceeds depth {maxExprDepth}"
  pure {
    expr := .callFn fnIndex (args.map (·.expr))
    depth
    expandedNodes
    dependencies := argIds
    isBool
    bitWidth := if isBool then 1 else 64
  }

/-- Signature index for pureFn callables: CallableId → fnIndex, arity, result kind. -/
private structure PureFnTableV1 where
  byCallableId : Array (Option Nat)
  paramCounts : Array Nat
  resultIsBool : Array Bool
  resultIsInt : Array Bool

private def buildPureFnTableV1
    (types : SolanaTypeClosureV1)
    (callables : Array CallableV1) : CompileResult PureFnTableV1 := do
  let mut byCallableId : Array (Option Nat) := Array.mk (List.replicate callables.size none)
  let mut paramCounts : Array Nat := #[]
  let mut resultIsBool : Array Bool := #[]
  let mut resultIsInt : Array Bool := #[]
  let mut i : Nat := 0
  for callable in callables do
    match callable.kind with
    | .pureFn =>
        if paramCounts.size >= maxEntries then
          throw <| .planInvariant .solana s!"pureFn count exceeds profile limit {maxEntries}"
        let name ← match callable.name with
          | some value => pure value
          | none => throw (.planInvariant .solana
              "unsupported Solana semantic shape: pureFn is missing its name")
        unless isIdentifier name do
          throw <| .planInvariant .solana s!"fn name '{name}' is not a safe identifier"
        unless callable.result.visibility == .public_ do
          throw <| .planInvariant .solana s!"fn '{name}' result is not public"
        let isBool := types.boolTypeId == some callable.result.typeId
        let isInt := (types.intWidthOf callable.result.typeId).isSome
        unless callable.result.typeId == types.uint64TypeId || isBool || isInt do
          throw <| .planInvariant .solana
            s!"fn '{name}' does not return public UInt64, Int64, or Bool"
        for param in callable.params do
          -- N1: pureFn params may be private/commitment; type is UInt64 or Int64.
          unless types.isUInt64OrInt64 param.typeId do
            throw <| .planInvariant .solana
              s!"fn '{name}' parameters must be UInt64 or Int64"
        byCallableId := byCallableId.set! i (some paramCounts.size)
        paramCounts := paramCounts.push callable.params.size
        resultIsBool := resultIsBool.push isBool
        resultIsInt := resultIsInt.push isInt
    | .invariant =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: invariants are outside the current UInt64 pilot"
    | .initializer | .entry | .view => pure ()
    i := i + 1
  pure { byCallableId, paramCounts, resultIsBool, resultIsInt }

private def consumeCurrentSegmentV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (root : ValueIdV1) : CompileResult Expr := do
  let rootValue ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  -- Only walk in-block segment values; dominating SSA is already closed.
  if root.toNat >= segmentStart then
    stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: dead or reordered value instructions"
  pure rootValue.expr

/-- Multi-root effect-boundary consumption (event/revert argument lists):
    every value produced in the current segment must be reachable from at
    least one sink root, mirroring the single-root discipline. -/
private def consumeSegmentRootsV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (roots : Array ValueIdV1) : CompileResult Unit := do
  for root in roots do
    let _ ← currentValueV1 values blockEntry segmentStart root
  let segmentCount := values.size - segmentStart
  let mut visited : Array Bool := Array.mk (List.replicate segmentCount false)
  let mut stack : Array Nat := #[]
  for root in roots do
    if root.toNat >= segmentStart then
      stack := stack.push root.toNat
  let mut visitedCount := 0
  while !stack.isEmpty do
    let index := stack.back!
    stack := stack.pop
    unless segmentStart <= index && index < values.size do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: sink references a stale ValueId"
    let localIndex := index - segmentStart
    if visited[localIndex]? == some false then
      visited := visited.set! localIndex true
      visitedCount := visitedCount + 1
      let value := values[index]!
      for dependency in value.dependencies do
        let dependencyIndex := dependency.toNat
        if dependencyIndex >= segmentStart then
          unless dependencyIndex < values.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: expression crosses an effect boundary"
          stack := stack.push dependencyIndex
        else if dependencyIndex >= blockEntry then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: expression crosses an effect boundary"
  unless visitedCount == segmentCount do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: dead or reordered value instructions"
  pure ()

private def appendResultValueV1
    (expectedTypeId : TypeIdV1)
    (values : Array LoweredValueV1)
    (result : ValueDefV1)
    (value : LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  unless result.valueId.toNat == values.size && result.typeId == expectedTypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: result ValueId/type is not canonical"
  if values.size >= maxPlanNodes then
    throw <| .planInvariant .solana s!"Solana value table exceeds node limit {maxPlanNodes}"
  pure (values.push value)

private def comparisonOpOfV1 : BinaryOpV1 → Option ComparisonOp
  | .eq => some .eq
  | .ne => some .ne
  | .lt => some .lt
  | .le => some .le
  | .gt => some .gt
  | .ge => some .ge
  | _ => none

private inductive SemanticCallableModeV1 where
  | initialize
  | mutate
  | view
  deriving BEq

private structure LoweredCallableV1 where
  params : Array Param
  body : Array Statement

private structure LoweredBlockV1 where
  statements : Array Statement
  values : Array LoweredValueV1
  segmentStart : Nat

/-- Lower one block's instruction sequence (terminator handled by the region
    walker). Each block starts a fresh effect segment; dominating pure SSA
    (callable params, pre-allocated block-param slots, earlier blocks) remains
    readable. Block parameters are only legal on loop headers and are slotted
    before instruction lowering (see `allocateBlockParamSlotsV1`). -/
private def lowerBlockInstructionsV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (armReadables : Array ValueIdV1)
    (block : BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult LoweredBlockV1 := do
  if block.instructions.size > maxBodyStatements then
    throw <| .planInvariant .solana
      s!"{owner} instruction count exceeds profile limit {maxBodyStatements}"
  let mut values := values0
  let blockEntry := values0.size
  let mut segmentStart := values0.size
  let mut body : Array Statement := #[]
  for instruction in block.instructions do
    match instruction.op, instruction.result with
    | .literal typeId bytes, some result =>
        if typeId == types.uint64TypeId then
          let value ← decodeUInt64LiteralV1 bytes
          values := ← appendResultValueV1 types.uint64TypeId values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := false
            isUInt32 := false
            isInt := false
            bitWidth := 64
          }
        else if let some bitWidth := types.intWidthOf typeId then
          unless isAbiIntWidth bitWidth do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: Int{bitWidth} literal is not admitted"
          let value ← decodeIntWidthLiteralLe solanaPlanErr "Solana" bitWidth bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal value
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := false
            isUInt32 := false
            isInt := true
            bitWidth
          }
        else if types.boolTypeId == some typeId then
          let bit ← decodeBoolLiteralV1 bytes
          values := ← appendResultValueV1 typeId values result {
            expr := .literal (if bit then 1 else 0)
            depth := 1
            expandedNodes := 1
            dependencies := #[]
            isBool := true
            isUInt32 := false
            isInt := false
            bitWidth := 1
          }
        else if let some bitWidth := types.uintWidthOf typeId then
          unless isSolanaBodyUintWidth bitWidth do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: UInt{bitWidth} literal is not admitted"
          if bitWidth ≤ 64 then
            let value ← decodeUIntWidthLiteralLe solanaPlanErr "Solana" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .literal value
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isUInt32 := bitWidth == 32
              isInt := false
              bitWidth
            }
          else
            let n ← decodeUIntWideLiteralLe solanaPlanErr "Solana" bitWidth bytes
            values := ← appendResultValueV1 typeId values result {
              expr := .bigLiteral bitWidth n
              depth := 1
              expandedNodes := 1
              dependencies := #[]
              isBool := false
              isUInt32 := false
              isInt := false
              bitWidth
            }
        else
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: literal is not admitted UInt width, Int64, or Bool"
    | .stateLoad stateId, some result =>
        let leafFields ← findStateLeafFieldsV1 account stateId
        if types.isContainer result.typeId then
          let n ← match ← arrayUInt64LeafCountV1 typeDecls types result.typeId with
            | some n => pure n
            | none =>
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: container state load is not Array UInt64"
          unless leafFields.size == n do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: Array state load leaf count mismatch"
          let mut leafExprs : Array Expr := #[]
          for field in leafFields do
            leafExprs := leafExprs.push
              (.stateLoad field.accountIndex field.byteOffset)
          let value := mkAggregateValueV1 leafExprs #[] 1 leafExprs.size
          values := ← appendResultValueV1 result.typeId values result value
        else
          let field ← match leafFields[0]? with
            | some f =>
                unless leafFields.size == 1 do
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: scalar state load saw multi-leaf layout"
                pure f
            | none =>
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: state load has no leaf fields"
          let expectedBitWidth := bitWidthOfByteWidth field.byteWidth
          let intW := types.intWidthOf result.typeId
          if let some bitWidth := intW then
            unless field.byteWidth == byteWidthOfBitWidth bitWidth do
              throw <| .planInvariant .solana
                s!"unsupported Solana semantic shape: Int{bitWidth} state load requires {byteWidthOfBitWidth bitWidth}-byte field"
            values := ← appendResultValueV1 result.typeId values result {
              expr := mkStateLoadExpr bitWidth field.accountIndex field.byteOffset
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
                  throw <| .planInvariant .solana
                    s!"unsupported Solana semantic shape: state load result UInt{bitWidth} does not match field byteWidth {field.byteWidth}"
                unless isSolanaAbiUintWidth bitWidth do
                  throw <| .planInvariant .solana
                    s!"unsupported Solana semantic shape: state load result UInt{bitWidth} is not admitted"
                values := ← appendResultValueV1 result.typeId values result {
                  expr := mkStateLoadExpr bitWidth field.accountIndex field.byteOffset
                  depth := 1
                  expandedNodes := 1
                  dependencies := #[]
                  isBool := false
                  isInt := false
                  isUInt32 := bitWidth == 32
                  bitWidth
                }
            | none =>
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: state load must be UInt8/16/32/64 or Int64"
    | .binary op lhsId rhsId, some result =>
        let lhs ← currentValueWithArmsV1 values blockEntry segmentStart armReadables lhsId
        let rhs ← currentValueWithArmsV1 values blockEntry segmentStart armReadables rhsId
        if lhs.isAggregate || rhs.isAggregate then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: binary ops do not accept Array aggregate operands"
        -- Strict Bool logical ops: both operands Bool, result Bool.
        if op == .and || op == .or then
          unless lhs.isBool && rhs.isBool do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: logical operands must be Bool"
          let boolTypeId ← match types.boolTypeId with
            | some value => pure value
            | none => throw (.planInvariant .solana
                "unsupported Solana semantic shape: Bool type is missing for logical op")
          unless result.typeId == boolTypeId do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: logical result must be Bool"
          let value ←
            if op == .and then makeBoolAndValueV1 lhsId rhsId lhs rhs
            else makeBoolOrValueV1 lhsId rhsId lhs rhs
          values := ← appendResultValueV1 boolTypeId values result value
        -- Shifts: admitted body UInt/Int64 operand, UInt32 count; result matches lhs.
        else if op == .shl || op == .shr then
          unless !lhs.isBool && (lhs.isInt || isSolanaBodyUintWidth lhs.bitWidth) do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: shift operand must be admitted integer width"
          unless !rhs.isBool && !rhs.isInt && rhs.bitWidth == 32 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: shift count must be UInt32"
          if lhs.isInt then
            let (resultTid, w) ← admitIntWidthResultTypeV1 types result.typeId
            unless lhs.bitWidth == w do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: Int shift result width mismatch"
            let value ←
              if op == .shl then makeShlValueV1 w lhsId rhsId lhs rhs
              else makeShrValueV1 w lhsId rhsId lhs rhs
            values := ← appendResultValueV1 resultTid values result value
          else
            let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
            unless bitWidth == lhs.bitWidth do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: shift result width mismatch"
            let value ←
              if op == .shl then makeShlValueV1 bitWidth lhsId rhsId lhs rhs
              else makeShrValueV1 bitWidth lhsId rhsId lhs rhs
            values := ← appendResultValueV1 widthTid values result value
        -- Body multi-width UInt arithmetic / bitwise / comparison, or Int64.
        else
          unless !lhs.isBool && !rhs.isBool do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: binary operands must be integer"
          unless lhs.isInt == rhs.isInt do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: binary operands must share signedness"
          if lhs.isInt then
            let intBitWidth := lhs.bitWidth
            unless isAbiIntWidth intBitWidth && rhs.bitWidth == intBitWidth && rhs.isInt do
              throw <| .planInvariant .solana
                s!"unsupported Solana semantic shape: Int arithmetic operands must share admitted width"
            -- Result TypeId is trusted from typed Semantic; width comes from operands.
            let wordTid := result.typeId
            if op == .add then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: arithmetic result type mismatch"
              let value ← makeCheckedAddValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .sub then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: arithmetic result type mismatch"
              let value ← makeCheckedSubValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .mul then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: arithmetic result type mismatch"
              let value ← makeCheckedMulValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .div then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: arithmetic result type mismatch"
              let value ← makeCheckedDivValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .mod then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: arithmetic result type mismatch"
              let value ← makeCheckedModValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .bitAnd then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: bitwise result type mismatch"
              let value ← makeBitAndValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .bitOr then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: bitwise result type mismatch"
              let value ← makeBitOrValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else if op == .bitXor then
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: bitwise result type mismatch"
              let value ← makeBitXorValueV1 intBitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 wordTid values result value
            else
              match comparisonOpOfV1 op with
              | some cmpOp =>
                  let boolTypeId ← match types.boolTypeId with
                    | some value => pure value
                    | none => throw (.planInvariant .solana
                        "unsupported Solana semantic shape: Bool type is missing for comparison")
                  unless result.typeId == boolTypeId do
                    throw <| .planInvariant .solana
                      "unsupported Solana semantic shape: comparison result must be Bool"
                  let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: only checked Int64 arith/bitwise and comparisons are supported"
          else
            -- Unsigned body multi-width path (UInt8/16/32/64).
            unless isSolanaBodyUintWidth lhs.bitWidth &&
                lhs.bitWidth == rhs.bitWidth do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: binary operands must share admitted UInt width"
            if op == .add || op == .sub || op == .mul || op == .div ||
                op == .mod || op == .bitAnd || op == .bitOr || op == .bitXor then
              let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
              unless bitWidth == lhs.bitWidth do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: arithmetic/bitwise result width mismatch"
              let value ←
                if op == .add then makeCheckedAddValueV1 bitWidth lhsId rhsId lhs rhs
                else if op == .sub then makeCheckedSubValueV1 bitWidth lhsId rhsId lhs rhs
                else if op == .mul then makeCheckedMulValueV1 bitWidth lhsId rhsId lhs rhs
                else if op == .div then makeCheckedDivValueV1 bitWidth lhsId rhsId lhs rhs
                else if op == .mod then makeCheckedModValueV1 bitWidth lhsId rhsId lhs rhs
                else if op == .bitAnd then makeBitAndValueV1 bitWidth lhsId rhsId lhs rhs
                else if op == .bitOr then makeBitOrValueV1 bitWidth lhsId rhsId lhs rhs
                else makeBitXorValueV1 bitWidth lhsId rhsId lhs rhs
              values := ← appendResultValueV1 widthTid values result value
            else
              match comparisonOpOfV1 op with
              | some cmpOp =>
                  let boolTypeId ← match types.boolTypeId with
                    | some value => pure value
                    | none => throw (.planInvariant .solana
                        "unsupported Solana semantic shape: Bool type is missing for comparison")
                  unless result.typeId == boolTypeId do
                    throw <| .planInvariant .solana
                      "unsupported Solana semantic shape: comparison result must be Bool"
                  let value ← makeCompareValueV1 cmpOp lhsId rhsId lhs rhs
                  values := ← appendResultValueV1 boolTypeId values result value
              | none =>
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: only checked multi-width UInt arith/bitwise, shift, Bool logical, and comparisons are supported"
    | .unary op operandId, some result =>
        let operand ← currentValueWithArmsV1 values blockEntry segmentStart armReadables operandId
        if operand.isAggregate then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: unary ops do not accept Array aggregate operands"
        match op with
        | .bitNot =>
            unless !operand.isBool && (operand.isInt || isSolanaBodyUintWidth operand.bitWidth) do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: bitNot operand must be admitted integer width"
            if operand.isInt then
              let (wordTid, intBitWidth) ← admitIntWidthResultTypeV1 types result.typeId
              unless result.typeId == wordTid do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: bitNot result type mismatch"
              let value ← makeBitNotValueV1 64 operandId operand
              values := ← appendResultValueV1 wordTid values result value
            else
              let (widthTid, bitWidth) ← admitUIntWidthResultTypeV1 types result.typeId
              unless bitWidth == operand.bitWidth do
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: bitNot result width mismatch"
              let value ← makeBitNotValueV1 bitWidth operandId operand
              values := ← appendResultValueV1 widthTid values result value
        | .not =>
            unless operand.isBool do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: boolNot operand must be Bool"
            let boolTypeId ← match types.boolTypeId with
              | some value => pure value
              | none => throw (.planInvariant .solana
                  "unsupported Solana semantic shape: Bool type is missing for boolNot")
            unless result.typeId == boolTypeId do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: boolNot result must be Bool"
            let value ← makeBoolNotValueV1 operandId operand
            values := ← appendResultValueV1 boolTypeId values result value
        | .neg =>
            let (tid, _) ← admitIntWidthResultTypeV1 types result.typeId
            unless result.typeId == tid do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: checkedNeg result type mismatch"
            let value ← makeCheckedNegValueV1 operandId operand
            values := ← appendResultValueV1 tid values result value
    | .pureCall callableId argIds, some result =>
        -- Pure local call: value-producing, not an effect boundary (like checkedAdd).
        let fnIndex ← match pureFns.byCallableId[callableId.toNat]? with
          | some (some index) => pure index
          | _ =>
              throw <| .planInvariant .solana
                s!"unsupported Solana semantic shape: pureCall targets unknown pureFn {callableId.toNat}"
        unless argIds.size == pureFns.paramCounts[fnIndex]! do
          throw <| .planInvariant .solana
            s!"unsupported Solana semantic shape: pureCall arity mismatch for pureFn {fnIndex}"
        let mut argValues : Array LoweredValueV1 := #[]
        for argId in argIds do
          let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !arg.isBool && arg.bitWidth == 64 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: pureCall arguments must be UInt64 or Int64"
          argValues := argValues.push arg
        let resultIsBool := pureFns.resultIsBool[fnIndex]!
        let resultIsInt := pureFns.resultIsInt[fnIndex]!
        let expectedTypeId ←
          if resultIsBool then
            match types.boolTypeId with
            | some value => pure value
            | none => throw (.planInvariant .solana
                "unsupported Solana semantic shape: Bool type is missing for pureCall result")
          else if resultIsInt then
            -- Callee may return any admitted Int width; accept the wire result TypeId.
            pure result.typeId
          else
            pure types.uint64TypeId
        unless result.typeId == expectedTypeId do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: pureCall result type does not match callee"
        let value ← makeCallFnValueV1 fnIndex argIds argValues resultIsBool
        let value := { value with isInt := resultIsInt, bitWidth := if resultIsBool then 1 else 64 }
        values := ← appendResultValueV1 expectedTypeId values result value
    | .stateStore stateId valueId, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable writes state"
        let leafFields ← findStateLeafFieldsV1 account stateId
        let stored ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        if stored.isAggregate then
          let leaves := stored.leafExprs
          unless leaves.size == leafFields.size do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: Array state store leaf count mismatch"
          let _ ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
          for i in [0:leaves.size] do
            let some field := leafFields[i]? |
              throw <| .planInvariant .solana "Array state store field missing"
            let some leafExpr := leaves[i]? |
              throw <| .planInvariant .solana "Array state store leaf missing"
            body := body.push (.store {
              accountIndex := field.accountIndex
              byteOffset := field.byteOffset
              value := leafExpr
              byteWidth := field.byteWidth
            })
          segmentStart := values.size
        else
          let field ← match leafFields[0]? with
            | some f =>
                unless leafFields.size == 1 do
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: scalar store to multi-leaf state"
                pure f
            | none =>
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: state store has no leaf fields"
          let expectedBitWidth := bitWidthOfByteWidth field.byteWidth
          unless !stored.isBool && stored.bitWidth == expectedBitWidth do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: state store value width {stored.bitWidth} must match field bitWidth {expectedBitWidth}"
          unless stored.isInt || isSolanaAbiUintWidth stored.bitWidth do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: state store value must be admitted UInt/Int width"
          unless !stored.isInt || isAbiIntWidth stored.bitWidth do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: Int state store requires admitted Int width"
          let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
          body := body.push (.store {
            accountIndex := field.accountIndex
            byteOffset := field.byteOffset
            value
            byteWidth := field.byteWidth
          })
          segmentStart := values.size
    | .assert_ condId errorId args, none =>
        unless errorId.isNone && args.isEmpty do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert requires errorId=none and empty args"
        let cond ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
        unless cond.isBool do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: assert condition must be Bool"
        let value ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
        body := body.push (.assert value)
        segmentStart := values.size
    | .emit _effectId eventId argIds, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable emits an event"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !root.isBool && !root.isInt && root.bitWidth == 64 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: event arguments must be UInt64"
          argExprs := argExprs.push root.expr
        -- Multi-root effect boundary: every value produced in the current
        -- segment must be reachable from at least one argument tree.
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.emitEvent eventId.toNat argExprs)
        segmentStart := values.size
    -- AddressBearing: static QualifiedName callees (wire takes QN, not a
    -- ValueId pubkey). Principal remains fail-closed. View banned.
    | .externalCall _effectId callee argIds, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable makes an external call"
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: external call callee must have at least two components"
        for c in components do
          unless isIdentifier c do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: external call callee component '{c}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !root.isBool && !root.isInt && root.bitWidth == 64 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: external call arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.externalCall components argExprs)
        segmentStart := values.size
    | .schedule _effectId callee argIds, none =>
        if mode == .view then
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: view callable schedules a workflow"
        let components := callee.components.toArray
        unless components.size ≥ 2 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: schedule callee must have at least two components"
        for c in components do
          unless isIdentifier c do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: schedule callee component '{c}' is not a safe identifier"
        let mut argExprs : Array Expr := #[]
        for argId in argIds do
          let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !root.isBool && !root.isInt && root.bitWidth == 64 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: schedule arguments must be UInt64"
          argExprs := argExprs.push root.expr
        let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
        body := body.push (.schedule components argExprs)
        segmentStart := values.size
    | .externalCall _ _ _, some _ | .schedule _ _ _, some _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: external call/schedule must be void"
    -- ArrayState: construct fixed Array UInt64 N from N scalar UInt64 args.
    | .construct typeId ctorIdx argIds, some result => do
        unless result.typeId == typeId do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: construct result typeId must match op typeId"
        let n ← match ← arrayUInt64LeafCountV1 typeDecls types typeId with
          | some n => pure n
          | none =>
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: construct admits only Array UInt64 on Solana"
        unless ctorIdx == 0 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Array construct ctorIdx must be 0"
        unless argIds.size == n do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Array construct arity mismatch"
        let mut leafExprs : Array Expr := #[]
        let mut deps : Array ValueIdV1 := #[]
        let mut depth : Nat := 1
        let mut nodes : Nat := 0
        for argId in argIds do
          let arg ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
          unless !arg.isBool && !arg.isInt && !arg.isAggregate && arg.bitWidth == 64 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: Array construct args must be scalar UInt64"
          leafExprs := leafExprs.push arg.expr
          deps := deps.push argId
          depth := Nat.max depth (arg.depth + 1)
          nodes := nodes + arg.expandedNodes
        let value := mkAggregateValueV1 leafExprs deps depth (nodes + n)
        values := ← appendResultValueV1 result.typeId values result value
    | .indexGet baseId idxId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: IndexGet base must be an Array UInt64 aggregate"
        let idx ← currentValueWithArmsV1 values blockEntry segmentStart armReadables idxId
        let i ← literalIndexNatV1 idx
        let leaves := base.leafExprs
        unless i < leaves.size do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Array IndexGet index out of range"
        let some leaf := leaves[i]? |
          throw <| .planInvariant .solana "Array IndexGet leaf missing"
        unless result.typeId == types.uint64TypeId do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Array IndexGet result must be UInt64"
        values := ← appendResultValueV1 result.typeId values result {
          expr := leaf
          depth := base.depth + 1
          expandedNodes := base.expandedNodes + 1
          dependencies := #[baseId, idxId]
          isBool := false
          isUInt32 := false
          isInt := false
          bitWidth := 64
        }
    | .indexSet baseId idxId valueId, some result => do
        let base ← currentValueWithArmsV1 values blockEntry segmentStart armReadables baseId
        unless base.isAggregate do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: IndexSet base must be an Array UInt64 aggregate"
        unless types.isContainer result.typeId do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: IndexSet result must be Array container"
        let idx ← currentValueWithArmsV1 values blockEntry segmentStart armReadables idxId
        let i ← literalIndexNatV1 idx
        let val ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
        unless !val.isBool && !val.isInt && !val.isAggregate && val.bitWidth == 64 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Array IndexSet value must be scalar UInt64"
        let leaves := base.leafExprs
        unless i < leaves.size do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Array IndexSet index out of range"
        let mut outLeaves : Array Expr := #[]
        for j in [0:leaves.size] do
          if j == i then
            outLeaves := outLeaves.push val.expr
          else
            let some e := leaves[j]? |
              throw <| .planInvariant .solana "Array IndexSet leaf missing"
            outLeaves := outLeaves.push e
        let value := mkAggregateValueV1 outLeaves #[baseId, idxId, valueId]
          (Nat.max base.depth val.depth + 1)
          (base.expandedNodes + val.expandedNodes + 1)
        values := ← appendResultValueV1 result.typeId values result value
    | .fieldGet .., some _ | .fieldSet .., some _
    | .variantTag .., some _ | .variantPayload .., some _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: named Struct/Enum field ops are outside the Solana container pilot (named aggregates declined)"
    -- N5: Commit = identity passthrough; ContextRead declined (no clock ABI).
    | .commit valueId, some result => do
        unless pilotContextPolicyCommitIdentity.admitCommitIdentity do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: Commit is not admitted by pilot context policy"
        let operand ← findValueV1 values valueId
        values := ← appendResultValueV1 result.typeId values result {
          expr := operand.expr
          depth := operand.depth + 1
          expandedNodes := operand.expandedNodes + 1
          dependencies := operand.dependencies.push valueId
          isBool := operand.isBool
          isUInt32 := operand.isUInt32
          isInt := operand.isInt
          bitWidth := operand.bitWidth
          aggregateLeaves := operand.aggregateLeaves
        }
    | .contextRead key, some _ =>
        unless key == unixTimeSecondsContextKeyV1 do
          throw <| .planInvariant .solana
            s!"unsupported Solana semantic shape: unknown ContextRead key '{key.value}'"
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: ContextRead is not admitted by pilot context policy"
    | _, _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: instruction op/result is outside the current UInt64 pilot"
  pure { statements := body, values, segmentStart }

/-- Decode a switch case constant against the scrutinee kind. -/
private def decodeSwitchCaseValueV1 (scrutIsBool : Bool) (bytes : ByteArray) :
    CompileResult UInt64 := do
  if scrutIsBool then
    let bit ← decodeBoolLiteralV1 bytes
    pure (if bit then 1 else 0)
  else
    decodeUInt64LiteralV1 bytes

/-- Region exit: forward join, path closed, or latch back-edge update. -/
private inductive RegionExitV1 where
  | join (blockId : Nat)
  | closed
  | latch (update : Expr)
  deriving Inhabited

private def findLoopBoundV1 (loopBounds : Array LoopBoundV1) (headerId : Nat) :
    Option LoopBoundV1 :=
  loopBounds.find? (fun lb => lb.header.toNat == headerId)

private def isLoopHeaderV1 (loopBounds : Array LoopBoundV1) (blockId : Nat) : Bool :=
  (findLoopBoundV1 loopBounds blockId).isSome

/-- Pre-allocate canonical block-parameter ValueId slots as plan `.temp`
    placeholders. Normalize places all block params (BlockId order) after
    callable params and before instruction results; only loop headers may
    carry the single UInt64 induction parameter. -/
private def allocateBlockParamSlotsV1
    (uint64TypeId : TypeIdV1)
    (loopBounds : Array LoopBoundV1)
    (blocks : Array BlockV1)
    (values0 : Array LoweredValueV1) : CompileResult (Array LoweredValueV1) := do
  let mut values := values0
  for block in blocks do
    if block.params.isEmpty then
      pure ()
    else
      unless isLoopHeaderV1 loopBounds block.id.toNat do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block parameters are only admitted on loop headers"
      unless block.params.size == 1 do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
      let some p := block.params[0]? |
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
      unless p.valueId.toNat == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block parameter ValueIds are not canonical"
      unless p.typeId == uint64TypeId do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop induction parameter must be UInt64"
      values := values.push {
        expr := .temp p.valueId.toNat
        depth := 1
        expandedNodes := 1
        dependencies := #[]
        isBool := false
        bitWidth := 64
      }
  pure values

/-- Read a jump-arg expression: args may be params, block-param temps, or
    dominating pure SSA (including the current block's open segment). When the
    arg is the sole sink of the current segment, consume that segment. -/
private def readJumpArgExprV1
    (values : Array LoweredValueV1)
    (blockEntry segmentStart : Nat)
    (armReadables : Array ValueIdV1)
    (argId : ValueIdV1) : CompileResult (Expr × Array LoweredValueV1 × Nat) := do
  let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
  unless !root.isBool && !root.isInt && root.bitWidth == 64 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: jump argument must be UInt64"
  if argId.toNat >= segmentStart then
    let expr ← consumeCurrentSegmentV1 values blockEntry segmentStart argId
    pure (expr, values, values.size)
  else if segmentStart == values.size then
    pure (root.expr, values, segmentStart)
  else
    -- Dominating arg with an open pure segment: leave the segment for a later
    -- consumer (e.g. pre-header limit used by the loop condition).
    pure (root.expr, values, segmentStart)

mutual
/-- Structured emission of multi-block CFGs: forward diamonds (branch/switch)
    and bounded for-loops recovered from `loopBounds` headers/latches.
    `enclosingHeaders` is the stack of active loop header ids (innermost last);
    a jump back to the innermost header ends the body with a latch update.
    Nested loop headers expand recursively. Returns (statements, values, exit).
    Mutually recursive with `lowerForLoopV1`. -/
private partial def emitRegionV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (expectedReturnBitWidth : Nat)
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (enclosingHeaders : Array Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (start : Nat)
    (values0 : Array LoweredValueV1) :
    CompileResult (Array Statement × Array LoweredValueV1 × RegionExitV1) := do
  if fuel == 0 then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: CFG region exceeds block bound"
  -- Starting directly on a loop header is only legal when the predecessor
  -- jump already expanded the loop; landing here otherwise is out of pilot.
  if isLoopHeaderV1 loopBounds start && !enclosingHeaders.contains start then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header must be entered via its pre-header jump"
  let block ← match blocks[start]? with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: region references a missing block")
  unless block.id.toNat == start do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: block ids are not dense"
  let lowered ← lowerBlockInstructionsV1
    owner mode types typeDecls account pureFns armReadables block values0
  let instrs := lowered.statements
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  let blockEntry := values0.size
  match block.terminator with
  | .return_ (some valueId) =>
      match mode with
      | .initialize =>
          throw <| .planInvariant .solana "initializer cannot return a value"
      | .mutate | .view =>
          let returned ← currentValueWithArmsV1 values blockEntry segmentStart armReadables valueId
          if returned.isAggregate then
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: Array aggregate cannot be returned (ABI is scalar)"
          unless returned.isBool == expectsBoolReturn do
            throw <| .planInvariant .solana
              (if expectsBoolReturn then
                "unsupported Solana semantic shape: Bool entry/view must return a Bool value"
               else
                "unsupported Solana semantic shape: integer entry/view must not return a Bool value")
          -- T9a: entry/view may return UInt8/16/32/64/Int64/Bool; width must match.
          unless expectsBoolReturn || returned.bitWidth == expectedReturnBitWidth do
            throw <| .planInvariant .solana
              s!"unsupported Solana semantic shape: entry/view return bitWidth must be {expectedReturnBitWidth} (or Bool) matching declared result"
          let value ← consumeCurrentSegmentV1 values blockEntry segmentStart valueId
          pure (instrs.push (.returnValue value), values, .closed)
  | .return_ none =>
      unless segmentStart == values.size do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: block has unconsumed values"
      -- Explicit marker: an early bare `return` inside a branch arm is
      -- otherwise indistinguishable from a fallthrough arm once the join
      -- continuation is emitted after the region.
      pure (instrs.push .returnNone, values, .closed)
  | .jump target =>
      let tid := target.blockId.toNat
      -- Latch back-edge: jump to the innermost enclosing loop header.
      if enclosingHeaders.back? == some tid then
        unless target.args.size == 1 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop latch must pass exactly one induction argument"
        let (update, values1, _) ←
          readJumpArgExprV1 values blockEntry segmentStart armReadables target.args[0]!
        pure (instrs, values1, .latch update)
      else if let some lb := findLoopBoundV1 loopBounds tid then
        -- Enter a (possibly nested) bounded for-loop at its pre-header jump.
        unless target.args.size == 1 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop entry must pass exactly one induction argument"
        let (initial, values1, _) ←
          readJumpArgExprV1 values blockEntry segmentStart armReadables target.args[0]!
        let (loopStmt, values2, exitId) ←
          lowerForLoopV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
            loopBounds enclosingHeaders armReadables (fuel - 1) lb initial values1
        let (rest, values3, exit) ←
          emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
            loopBounds enclosingHeaders armReadables (fuel - 1) exitId values2
        pure (instrs ++ #[loopStmt] ++ rest, values3, exit)
      else
        -- Forward join: pure dominating values may remain for successors.
        pure (instrs, values, .join tid)
  | .branch condId thenT elseT =>
      let condVal ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
      unless condVal.isBool do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: branch condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
      let (thenBody, values1, thenExit) ←
        emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
          loopBounds enclosingHeaders armReadables (fuel - 1) thenT.blockId.toNat values
      match thenExit with
      | .latch _ =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: branch then-arm cannot be a raw loop latch"
      | .closed =>
          let (elseBody, values2, elseExit) ←
            emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
              loopBounds enclosingHeaders armReadables (fuel - 1) elseT.blockId.toNat values1
          match elseExit with
          | .closed =>
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody], values2, .closed)
          | .join j =>
              let (rest, values3, exit) ←
                emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
                  loopBounds enclosingHeaders armReadables (fuel - 1) j values2
              pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, exit)
          | .latch _ =>
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: branch else-arm cannot be a raw loop latch"
      | .join j =>
          if elseT.blockId.toNat == j then
            let (rest, values2, exit) ←
              emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
                loopBounds enclosingHeaders armReadables (fuel - 1) j values1
            pure (instrs ++ #[.ifThenElse cond thenBody #[]] ++ rest, values2, exit)
          else
            let (elseBody, values2, elseExit) ←
              emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
                loopBounds enclosingHeaders armReadables (fuel - 1) elseT.blockId.toNat values1
            match elseExit with
            | .join j2 =>
                unless j == j2 do
                  throw <| .planInvariant .solana
                    "unsupported Solana semantic shape: branch arms converge on divergent joins"
                let (rest, values3, exit) ←
                  emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
                    loopBounds enclosingHeaders armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, exit)
            | .closed =>
                let (rest, values3, exit) ←
                  emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
                    loopBounds enclosingHeaders armReadables (fuel - 1) j values2
                pure (instrs ++ #[.ifThenElse cond thenBody elseBody] ++ rest, values3, exit)
            | .latch _ =>
                throw <| .planInvariant .solana
                  "unsupported Solana semantic shape: branch else-arm cannot be a raw loop latch"
  | .switch scrutId cases defaultTarget =>
      let scrutVal ← currentValueWithArmsV1 values blockEntry segmentStart armReadables scrutId
      let scrut ← consumeCurrentSegmentV1 values blockEntry segmentStart scrutId
      let some defaultT := defaultTarget |
        throw (.planInvariant .solana
          "unsupported Solana semantic shape: switch must carry a default target")
      let mut caseBodies : Array (UInt64 × Array Statement) := #[]
      let mut joinAcc : Option Nat := none
      let mut valuesA := values
      for switchCase in cases do
        let caseValue ← decodeSwitchCaseValueV1 scrutVal.isBool switchCase.valueBytes
        let (body, values1, armExit) ←
          emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
            loopBounds enclosingHeaders (armReadables.push scrutId) (fuel - 1)
            switchCase.target.blockId.toNat valuesA
        caseBodies := caseBodies.push (caseValue, body)
        valuesA := values1
        match armExit, joinAcc with
        | .closed, _ => pure ()
        | .join j, none => joinAcc := some j
        | .join j, some j0 =>
            unless j == j0 do
              throw <| .planInvariant .solana
                "unsupported Solana semantic shape: switch arms converge on divergent joins"
        | .latch _, _ =>
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: switch arm cannot be a loop latch"
      let (defaultBody, values2, defaultExit) ←
        emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
          loopBounds enclosingHeaders (armReadables.push scrutId) (fuel - 1)
          defaultT.blockId.toNat valuesA
      match defaultExit, joinAcc with
      | .closed, _ => pure ()
      | .join j, none => joinAcc := some j
      | .join j, some j0 =>
          unless j == j0 do
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: switch arms converge on divergent joins"
      | .latch _, _ =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: switch default cannot be a loop latch"
      match joinAcc with
      | none =>
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody], values2, .closed)
      | some j =>
          let (rest, values3, exit) ←
            emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
              loopBounds enclosingHeaders armReadables (fuel - 1) j values2
          pure (instrs ++ #[.switchOn scrut caseBodies defaultBody] ++ rest, values3, exit)
  | .revert errorId argIds =>
      let mut argExprs : Array Expr := #[]
      for argId in argIds do
        let root ← currentValueWithArmsV1 values blockEntry segmentStart armReadables argId
        unless !root.isBool && !root.isInt && root.bitWidth == 64 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: revert arguments must be UInt64"
        argExprs := argExprs.push root.expr
      let _ ← consumeSegmentRootsV1 values blockEntry segmentStart argIds
      pure (instrs.push (.revertError errorId.toNat argExprs), values, .closed)
  | .trap _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: trap terminators are outside the current pilot"

/-- Recover one bounded for-loop from its `loopBounds` entry: bind the header
    induction temp from `initial`, lower the header condition, walk the body
    until the latch back-edge, and return the exit block id (branch else). -/
private partial def lowerForLoopV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (expectedReturnBitWidth : Nat)
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (blocks : Array BlockV1)
    (loopBounds : Array LoopBoundV1)
    (enclosingHeaders : Array Nat)
    (armReadables : Array ValueIdV1)
    (fuel : Nat)
    (lb : LoopBoundV1)
    (initial : Expr)
    (values0 : Array LoweredValueV1) :
    CompileResult (Statement × Array LoweredValueV1 × Nat) := do
  if fuel == 0 then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: CFG region exceeds block bound"
  let headerId := lb.header.toNat
  let header ← match blocks[headerId]? with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: loop header block is missing")
  unless header.id.toNat == headerId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header block id is not dense"
  unless header.params.size == 1 do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
  let some induction := header.params[0]? |
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
  let varTemp := induction.valueId.toNat
  unless induction.typeId == types.uint64TypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop induction parameter must be UInt64"
  unless varTemp < values0.size do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop induction temp is not pre-allocated"
  -- Re-bind the induction slot to the plan temp (identity already `.temp`).
  let valuesBound := values0.set! varTemp {
    expr := .temp varTemp
    depth := 1
    expandedNodes := 1
    dependencies := #[]
    isBool := false
    bitWidth := 64
  }
  let lowered ← lowerBlockInstructionsV1
    owner mode types typeDecls account pureFns armReadables header valuesBound
  unless lowered.statements.isEmpty do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: loop header may not contain effectful statements"
  let values := lowered.values
  let segmentStart := lowered.segmentStart
  let blockEntry := valuesBound.size
  match header.terminator with
  | .branch condId thenT elseT =>
      let condVal ← currentValueWithArmsV1 values blockEntry segmentStart armReadables condId
      unless condVal.isBool do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop condition must be Bool"
      let cond ← consumeCurrentSegmentV1 values blockEntry segmentStart condId
      let bodyId := thenT.blockId.toNat
      let exitId := elseT.blockId.toNat
      let headers' := enclosingHeaders.push headerId
      let (bodyStmts, values1, bodyExit) ←
        emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns blocks
          loopBounds headers' armReadables (fuel - 1) bodyId values
      match bodyExit with
      | .latch update =>
          pure (.forLoop varTemp initial cond update lb.maxIterations.toNat bodyStmts,
            values1, exitId)
      | .join _ | .closed =>
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop body must end at its latch back-edge"
  | _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loop header must terminate in a branch"
end

private def lowerCallableV1
    (owner : String)
    (mode : SemanticCallableModeV1)
    (expectsBoolReturn : Bool)
    (expectedReturnBitWidth : Nat)
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (callable : CallableV1) : CompileResult LoweredCallableV1 := do
  unless callable.entryBlock.toNat == 0 && !callable.blocks.isEmpty &&
      callable.invariantSteps.isNone do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: callable must enter at block 0 without invariant fuel"
  -- Loop headers: exactly one UInt64 param and a matching loopBounds row.
  -- Non-header blocks must remain param-free. Degenerate param'd blocks
  -- without loopBounds stay fail-closed.
  for block in callable.blocks do
    if block.params.isEmpty then
      pure ()
    else if isLoopHeaderV1 callable.loopBounds block.id.toNat then
      unless block.params.size == 1 do
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop header must carry exactly one block parameter"
    else
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: block parameters are only admitted on loop headers"
  for lb in callable.loopBounds do
    let headerId := lb.header.toNat
    let latchId := lb.backEdgeFrom.toNat
    let some header := callable.blocks[headerId]? |
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loopBounds header is out of range"
    unless header.id.toNat == headerId && header.params.size == 1 do
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loopBounds header is not a single-param loop header"
    let some latch := callable.blocks[latchId]? |
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: loopBounds latch is out of range"
    match latch.terminator with
    | .jump target =>
        unless target.blockId.toNat == headerId && target.args.size == 1 do
          throw <| .planInvariant .solana
            "unsupported Solana semantic shape: loop latch must jump back with one induction arg"
    | _ =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: loop latch must be a jump back to its header"
  let (params, initialValues) ← makeParamsV1 owner types callable.params
  let valuesPadded ← allocateBlockParamSlotsV1 types.uint64TypeId callable.loopBounds
    callable.blocks initialValues
  let (body0, values0, exit0) ←
    emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns callable.blocks
      callable.loopBounds #[] #[] callable.blocks.size 0 valuesPadded
  -- Fold trailing join continuations (an arm that returned early leaves the
  -- remaining open path's join to the caller). Join targets strictly increase
  -- in the forward-only CFG (loop headers are expanded at their entry jump),
  -- so this terminates within blocks.size folds.
  let mut body := body0
  let mut values := values0
  let mut nextJoin : Option Nat :=
    match exit0 with
    | .join j => some j
    | .closed => none
    | .latch _ => none
  match exit0 with
  | .latch _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: top-level region cannot end in a loop latch"
  | _ => pure ()
  for _ in [0:callable.blocks.size] do
    match nextJoin with
    | none => break
    | some j =>
        let (rest, values1, exit1) ←
          emitRegionV1 owner mode expectsBoolReturn expectedReturnBitWidth types typeDecls account pureFns callable.blocks
            callable.loopBounds #[] #[] callable.blocks.size j values
        body := body ++ rest
        values := values1
        match exit1 with
        | .join j2 => nextJoin := some j2
        | .closed => nextJoin := none
        | .latch _ =>
            throw <| .planInvariant .solana
              "unsupported Solana semantic shape: top-level region cannot end in a loop latch"
  match nextJoin with
  | some _ =>
      throw <| .planInvariant .solana
        "unsupported Solana semantic shape: callable does not end in return on all paths"
  | none => pure ()
  if body.size > maxBodyStatements then
    throw <| .planInvariant .solana s!"{owner} body exceeds profile limit {maxBodyStatements}"
  pure { params, body }

private def makeInitializerV1
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (callable : CallableV1) : CompileResult Handler := do
  unless callable.name.isNone && callable.result.visibility == .public_ do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: initializer signature is invalid"
  let unitTypeId ← match types.unitTypeId with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: initializer Unit type is missing")
  unless callable.result.typeId == unitTypeId do
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: initializer result is not Unit"
  let lowered ← lowerCallableV1 "initializer" .initialize false 64 types typeDecls account pureFns callable
  let handler : Handler := {
    name := "initialize"
    discriminator := ""
    params := lowered.params
    mode := .initialize
    resultKind := .u64
    accountAccess := accessFor account .initialize
    body := lowered.body
  }
  pure { handler with discriminator := instructionDiscriminator handler.name handler.params }

private def makeEntryV1
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (callable : CallableV1) : CompileResult Handler := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: named entry is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .solana s!"entry name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .solana s!"entry '{name}' result is not public"
  let resultKind : ResultKind ←
    match types.uintWidthOf callable.result.typeId with
    | some 8 => pure .u8
    | some 16 => pure .u16
    | some 32 => pure .u32
    | some 64 => pure .u64
    | some 128 => pure .u128
    | some 256 => pure .u256
    | some _ =>
        throw <| .planInvariant .solana
          s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int64, or Bool"
    | none =>
        match types.intWidthOf callable.result.typeId with
        | some 8 => pure .i8
        | some 16 => pure .i16
        | some 32 => pure .i32
        | some 64 => pure .i64
        | some w =>
            throw <| .planInvariant .solana
              s!"entry '{name}' does not return public Int{w}"
        | none =>
          if types.boolTypeId == some callable.result.typeId then
            pure .bool
          else
            throw <| .planInvariant .solana
              s!"entry '{name}' does not return public UInt8/16/32/64/128/256, Int8/16/32/64, or Bool"
  let semanticMode : SemanticCallableModeV1 ← match callable.kind with
    | .entry => pure .mutate
    | .view => pure .view
    | _ => throw (.planInvariant .solana
        "unsupported Solana semantic shape: callable is not an entry or view")
  let mode : HandlerMode := match semanticMode with
    | .mutate => .mutate
    | .view => .view
    | .initialize => .initialize
  let expectsBoolReturn := resultKind == .bool
  let expectedReturnBitWidth : Nat :=
    match resultKind with
    | .u8 | .i8 => 8 | .u16 | .i16 => 16 | .u32 | .i32 => 32
    | .u64 | .i64 => 64 | .u128 => 128 | .u256 => 256 | .bool => 64
  let lowered ← lowerCallableV1 s!"entry '{name}'" semanticMode expectsBoolReturn
    expectedReturnBitWidth types typeDecls account pureFns callable
  let handler : Handler := {
    name
    discriminator := ""
    params := lowered.params
    mode
    resultKind
    accountAccess := accessFor account mode
    body := lowered.body
  }
  pure { handler with discriminator := instructionDiscriminator handler.name handler.params }

private def makePureFnV1
    (types : SolanaTypeClosureV1)
    (typeDecls : Array TypeDeclV1)
    (account : StateAccount)
    (pureFns : PureFnTableV1)
    (callable : CallableV1) : CompileResult FnBinding := do
  let name ← match callable.name with
    | some value => pure value
    | none => throw (.planInvariant .solana
        "unsupported Solana semantic shape: pureFn is missing its name")
  unless isIdentifier name do
    throw <| .planInvariant .solana s!"fn name '{name}' is not a safe identifier"
  unless callable.result.visibility == .public_ do
    throw <| .planInvariant .solana s!"fn '{name}' result is not public"
  let resultIsBool := types.boolTypeId == some callable.result.typeId
  let resultIsInt := (types.intWidthOf callable.result.typeId).isSome
  unless callable.result.typeId == types.uint64TypeId || resultIsBool || resultIsInt do
    throw <| .planInvariant .solana
      s!"fn '{name}' does not return public UInt64, Int8/16/32/64, or Bool"
  -- pureFn bodies use view mode so store/emit fail closed at the lowerer.
  let lowered ← lowerCallableV1 s!"fn '{name}'" .view resultIsBool
    64 types typeDecls account pureFns callable
  pure {
    name
    params := lowered.params
    resultIsBool
    resultIsInt
    body := lowered.body
  }

private def makeInterfaceBindingV1 (label : String) (name : String)
    (fields : Array InterfaceFieldV1) (uint64TypeId : TypeIdV1) :
    CompileResult InterfaceBinding := do
  unless isIdentifier name do
    throw <| .planInvariant .solana
      s!"unsupported Solana semantic shape: {label} name '{name}' is not a safe identifier"
  for field in fields do
    unless field.typeId == uint64TypeId && field.visibility == .public_ do
      throw <| .planInvariant .solana
        s!"unsupported Solana semantic shape: {label} '{name}' fields must be public UInt64"
  pure { name, fieldCount := fields.size }

/-- Solana-private retained SemanticProgramV1 data → target-owned Plan pilot. -/

private def makePlanFromSemanticDataV1
    (source : SemanticProgramDataV1) : CompileResult Plan := do
  if !source.constants.isEmpty || !source.invariants.isEmpty then
    throw <| .planInvariant .solana
      "unsupported Solana semantic shape: constants/invariants are outside the current UInt64 pilot"
  -- init+entries ≤ maxEntries+1; pureFns ≤ maxEntries (checked in buildPureFnTableV1).
  if source.callables.size > maxEntries + 1 + maxEntries then
    throw <| .planInvariant .solana
      s!"callable count exceeds Solana profile limit {maxEntries + 1 + maxEntries}"
  if source.requirements.items.size > Targets.maxRequirementKinds then
    throw <| .planInvariant .solana
      s!"requirement count exceeds canonical limit {Targets.maxRequirementKinds}"
  let types ← validateSolanaTypeClosureV1 source.types
  let typeDecls := source.types
  let stateAccount ← makeStateAccountV1 types typeDecls source.logicalState
  let events ← source.events.mapM (fun d =>
    makeInterfaceBindingV1 "event" d.name d.fields types.uint64TypeId)
  let errors ← source.errors.mapM (fun d =>
    makeInterfaceBindingV1 "error" d.name d.fields types.uint64TypeId)
  let pureFnTable ← buildPureFnTableV1 types source.callables
  let components := source.qualifiedName.components.toArray
  let programName := components.back!
  let mut initializer : Option Handler := none
  let mut entries : Array Handler := #[]
  let mut fns : Array FnBinding := #[]
  for callable in source.callables do
    match callable.kind with
    | .initializer =>
        if initializer.isSome then
          throw <| .planInvariant .solana "semantic program has multiple initializers"
        initializer := some (← makeInitializerV1 types typeDecls stateAccount pureFnTable callable)
    | .entry | .view =>
        if entries.size >= maxEntries then
          throw <| .planInvariant .solana s!"entry count exceeds profile limit {maxEntries}"
        entries := entries.push (← makeEntryV1 types typeDecls stateAccount pureFnTable callable)
    | .pureFn =>
        fns := fns.push (← makePureFnV1 types typeDecls stateAccount pureFnTable callable)
    | .invariant =>
        throw <| .planInvariant .solana
          "unsupported Solana semantic shape: invariants are outside the current UInt64 pilot"
  let resolvedInitializer ← match initializer with
    | some value => pure value
    | none => throw <| .planInvariant .solana "state-account programs require an initializer"
  let plan : Plan := {
    codegenProfile := descriptor.codegenProfile.toString
    instructionDiscriminatorDomain := discriminatorDomain
    instructionDiscriminatorBytes := discriminatorBytes
    stateLayoutDomain := layoutDomain
    arithmeticOverflowError
    assertionFailedError
    loopBoundExceededError
    invalidShiftError
    programName
    stateAccount
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
        throw <| .invalidProgram "Solana received an invalid SemanticProgramV1 carrier"
  makePlanFromSemanticDataV1 data

/-- Internal Solana family phase entry: capability → Plan (pre-canonicity). -/
def materializePlanFromCapabilityV1 (capability : ResolvedEngineeringBuildV1) : CompileResult Plan := do
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| .planInvariant .solana "engineering capability kind is not Solana"
  let source := CompiledSemanticV1.semanticV1Of
    (ResolvedEngineeringBuildV1.compiledOf capability)
  makePlanFromSemanticV1 source

end ProofForgeV2.Targets.Solana
