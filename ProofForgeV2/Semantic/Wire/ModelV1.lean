import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementIdsV1

/-!
  ProofForgeV2.Semantic.Wire.ModelV1 — closed SemanticProgramV1 data model,
  schema/limits, requirement row builders, and shared internal helpers.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Schema / domain constants (SPEC-SEM-WIRE-001 §1). -/
def semanticProgramSchemaIdV1 : String := "proof-forge.semantic-program.v1"
/-- Numeric projection used only by transitional target Plan carriers. -/
def semanticProgramSchemaVersionV1 : Nat := 1
def semanticProgramMagicV1 : String := "pf.semantic.v1"
def semanticProvenanceSchemaIdV1 : String := "proof-forge.semantic-provenance.v1"
def semanticProvenanceMagicV1 : String := "pf.semantic-provenance.v1"

/-- Hard resource caps from SPEC §3 (decode checks before allocate). -/
def maxCanonicalProgramBytes : Nat := 64 * 1024 * 1024
def maxArrayElements : Nat := 1000000
def maxTableElements : Nat := 100000
def maxStringBytes : Nat := 1024 * 1024
def maxNesting : Nat := 256
def maxOriginBindings : Nat := 1000000
def maxOriginsPerBinding : Nat := 100000
def maxTagAsciiBytes : Nat := 64
/-- SPEC §5 Bytes/Array length upper bound. -/
def maxTypeLengthV1 : Nat := 4096
/-- SPEC §6 loopBounds `maxIterations` upper bound (per-loop iteration cap). -/
def maxLoopIterationsV1 : UInt32 := 4096
/-- SPEC §8 intrinsic invariant interpreter fuel ceiling. -/
def maxInvariantStepsV1 : UInt64 := 10000000
/-- SPEC §3 canonical valueBytes size upper bound (16 MiB). -/
def maxCanonicalValueBytes : Nat := 16 * 1024 * 1024
/-- SPEC §3 Map entry count upper bound (same as array elements). -/
def maxMapEntriesV1 : Nat := maxArrayElements

/-- v1 Field catalog entry id for the BN254 scalar field (SPEC-SEM-WIRE-001 §5).
    EVM (ADDMOD/MULMOD + Fermat inverse) and Noir (native Barretenberg bn254
    scalar `Field`) admit this exact spec. -/
def bn254FrFieldIdV1 : String := "proof-forge.field.bn254-fr.v1"

/-- v1 Field catalog entry id for the BLS12-377 scalar field (T14 catalog v2).
    Aleo native Leo `field` is the Edwards BLS / BLS12-377 scalar field — exact
    modulus match. Other targets stay fail-closed on this spec. -/
def bls12377FrFieldIdV1 : String := "proof-forge.field.bls12-377-fr.v1"

/-- v1 Field catalog entry id for the Goldilocks prime field (T14 catalog v2).
    Psy native `Felt` is plonky2 Goldilocks (`p = 2^64 − 2^32 + 1`) — exact
    modulus match. Other targets stay fail-closed on this spec. -/
def goldilocksFieldIdV1 : String := "proof-forge.field.goldilocks.v1"

/-- Closed v1 ContextRead key: immutable invocation wall-clock seconds. -/
def unixTimeSecondsContextKeyV1 : SchemaId :=
  { value := "proof-forge.context.unix-time-seconds.v1" }

/-- Closed v1 ContextRead key: invocation caller identity (N-2).
    Result shape is anonymous Principal. -/
def callerContextKeyV1 : SchemaId :=
  { value := "proof-forge.context.caller.v1" }

/-- Requirement identity bound to the unix-time ContextRead key.
    Thin alias of `RequirementIdsV1.wireContextUnixTimeSecondsIdV1`
    (domain `pf.context-read-requirement.v1`). -/
def unixTimeSecondsContextRequirementIdV1 : String :=
  RequirementIdsV1.wireContextUnixTimeSecondsIdV1

/-- Requirement identity bound to the caller ContextRead key (N-2). -/
def callerContextRequirementIdV1 : String :=
  RequirementIdsV1.wireContextCallerIdV1

/-- Exact requirement identity contributed by every v1 Commit operation.
    Thin alias of `RequirementIdsV1.wireCommitmentDisclosureIdV1`
    (domain `pf.commit-requirement.v1`). Same spelling as the infer-only
    `inferDisclosureCommitmentIdV1` contribution — dual meaning; see
    `RequirementIdsV1` module doc. -/
def commitmentDisclosureRequirementIdV1 : String :=
  RequirementIdsV1.wireCommitmentDisclosureIdV1
/-- Exact bn254 Fr modulus big-endian bytes (SPEC-SEM-WIRE-001 §5). -/
def bn254FrModulusBEV1 : ByteArray :=
  ByteArray.mk #[
    0x30, 0x64, 0x4e, 0x72, 0xe1, 0x31, 0xa0, 0x29,
    0xb8, 0x50, 0x45, 0xb6, 0x81, 0x81, 0x58, 0x5d,
    0x28, 0x33, 0xe8, 0x48, 0x79, 0xb9, 0x70, 0x91,
    0x43, 0xe1, 0xf5, 0x93, 0xf0, 0x00, 0x00, 0x01
  ]

/-- Exact BLS12-377 Fr modulus big-endian bytes (T14 catalog v2). The 253-bit
    scalar-field prime of the BLS12-377 pairing-friendly curve
    (`r = 0x12ab655e9a2ca55660b44d1e5c37b00159aa76fed00000010a11800000000001`),
    the native modulus of Aleo's Leo `field` (Edwards BLS scalar = BLS12-377 Fr).
    Stored as 32 big-endian bytes (leading zero is the 253→256-bit pad). -/
def bls12377FrModulusBEV1 : ByteArray :=
  ByteArray.mk #[
    0x12, 0xab, 0x65, 0x5e, 0x9a, 0x2c, 0xa5, 0x56,
    0x60, 0xb4, 0x4d, 0x1e, 0x5c, 0x37, 0xb0, 0x01,
    0x59, 0xaa, 0x76, 0xfe, 0xd0, 0x00, 0x00, 0x00,
    0x10, 0xa1, 0x18, 0x00, 0x00, 0x00, 0x00, 0x01
  ]

/-- Exact Goldilocks prime modulus big-endian bytes (T14 catalog v2).
    `p = 2^64 − 2^32 + 1 = 0xFFFFFFFF00000001`, the native modulus of Psy's
    plonky2 `Felt`. Stored as 8 big-endian bytes (64-bit prime, no pad). -/
def goldilocksModulusBEV1 : ByteArray :=
  ByteArray.mk #[0xFF, 0xFF, 0xFF, 0xFF, 0x00, 0x00, 0x00, 0x01]

abbrev TypeIdV1 := UInt32
abbrev ConstantIdV1 := UInt32
abbrev StateIdV1 := UInt32
abbrev EventIdV1 := UInt32
abbrev ErrorIdV1 := UInt32
abbrev CallableIdV1 := UInt32
abbrev BlockIdV1 := UInt32
abbrev ValueIdV1 := UInt32
abbrev EffectIdV1 := UInt32
abbrev InvariantIdV1 := UInt32

/-- Local Repr for ByteArray so wire model structures can derive Repr. -/
private instance : Repr ByteArray where
  reprPrec bytes _ :=
    (Std.Format.text "ByteArray.size=").append (repr bytes.size)

structure EffectOccurrenceV1 where
  effectId : EffectIdV1
  occurrence : UInt32
  deriving BEq, Repr

structure SourceNodeInventoryV1 where
  sourceHash : Digest
  nodes : Array SourceOrigin
  deriving BEq

/-- Lean spelling of SPEC `public` (reserved keyword) → wire tag `Visibility.Public`. -/
inductive VisibilityV1 where
  | public_
  | private_
  | commitment
  deriving BEq, Repr, DecidableEq

structure FieldSpecV1 where
  id : SchemaId
  modulusBE : ByteArray
  deriving BEq

/-- Sole v1 FieldSpec catalog entry for structure validation and tests. -/
def bn254FrFieldSpecV1 : FieldSpecV1 :=
  { id := { value := bn254FrFieldIdV1 }, modulusBE := bn254FrModulusBEV1 }

/-- v1 FieldSpec catalog entry for the BLS12-377 scalar field (T14 catalog v2).
    Admitted by Aleo (Leo native `field`); fail-closed on every other target
    via the target-owned type-closure `PilotFieldPolicy`. -/
def bls12377FrFieldSpecV1 : FieldSpecV1 :=
  { id := { value := bls12377FrFieldIdV1 }, modulusBE := bls12377FrModulusBEV1 }

/-- v1 FieldSpec catalog entry for the Goldilocks prime field (T14 catalog v2).
    Admitted by Psy (plonky2 `Felt`); fail-closed on every other target via
    the target-owned type-closure `PilotFieldPolicy`. -/
def goldilocksFieldSpecV1 : FieldSpecV1 :=
  { id := { value := goldilocksFieldIdV1 }, modulusBE := goldilocksModulusBEV1 }

/-- Closed v1 FieldSpec catalog (T14 catalog v2): the three exact (id, modulusBE)
    entries admitted by Wire structure validation. No arbitrary modulus is
    accepted; a FieldSpec must match one of these exactly. Membership is checked
    by `validateFieldSpecCatalogV1`. -/
def fieldSpecCatalogV1 : Array FieldSpecV1 :=
  #[bn254FrFieldSpecV1, bls12377FrFieldSpecV1, goldilocksFieldSpecV1]

structure StructFieldV1 where
  name : String
  typeId : TypeIdV1
  deriving BEq, Repr

structure EnumVariantV1 where
  name : String
  payloadTypes : Array TypeIdV1
  deriving BEq, Repr

inductive TypeShapeV1 where
  | bool
  | uint (width : UInt16)
  | int (width : UInt16)
  | principal
  | unit
  /-- Variable-length NFC UTF-8 string (N4 engineering TypeShape).
      Canonical valueBytes = `u32le(byteLen) || UTF-8` with `0 ≤ byteLen ≤ maxTypeLengthV1`
      (empty string admitted; invalid UTF-8 / non-NFC → `.nonCanonical`).
      Not a formal SPEC §4.2 tag yet; engineering extension for ProgramV1
      `String` / string-literal product surface. -/
  | string
  | bytes (length : UInt32)
  | array (element : TypeIdV1) (length : UInt32)
  | map (key : TypeIdV1) (value : TypeIdV1)
  | option (element : TypeIdV1)
  | field (spec : FieldSpecV1)
  | struct (fields : Array StructFieldV1)
  | enum (variants : Array EnumVariantV1)
  deriving BEq

structure TypeDeclV1 where
  id : TypeIdV1
  name : Option String
  shape : TypeShapeV1
  deriving BEq

structure ConstantV1 where
  id : ConstantIdV1
  name : String
  typeId : TypeIdV1
  valueBytes : ByteArray
  deriving BEq

structure StateDeclV1 where
  id : StateIdV1
  name : String
  typeId : TypeIdV1
  visibility : VisibilityV1
  deriving BEq, Repr

structure InterfaceFieldV1 where
  name : String
  typeId : TypeIdV1
  visibility : VisibilityV1
  deriving BEq, Repr

structure EventDeclV1 where
  id : EventIdV1
  name : String
  fields : Array InterfaceFieldV1
  deriving BEq, Repr

structure ErrorDeclV1 where
  id : ErrorIdV1
  name : String
  fields : Array InterfaceFieldV1
  deriving BEq, Repr

inductive CallableKindV1 where
  | initializer
  | entry
  | view
  | pureFn
  | invariant
  deriving BEq, Repr, DecidableEq

structure ParameterV1 where
  valueId : ValueIdV1
  name : String
  typeId : TypeIdV1
  visibility : VisibilityV1
  deriving BEq, Repr

structure CallableResultV1 where
  typeId : TypeIdV1
  visibility : VisibilityV1
  deriving BEq, Repr

structure ValueDefV1 where
  valueId : ValueIdV1
  typeId : TypeIdV1
  deriving BEq, Repr

structure BlockParameterV1 where
  valueId : ValueIdV1
  typeId : TypeIdV1
  deriving BEq, Repr

inductive UnaryOpV1 where
  | neg | not | bitNot
  deriving BEq, Repr, DecidableEq

inductive BinaryOpV1 where
  | add | sub | mul | div | mod
  | eq | ne | lt | le | gt | ge
  | and | or | bitAnd | bitOr | bitXor | shl | shr
  deriving BEq, Repr, DecidableEq

inductive SemanticOpV1 where
  | literal (typeId : TypeIdV1) (valueBytes : ByteArray)
  | constant (constantId : ConstantIdV1)
  | stateLoad (stateId : StateIdV1)
  | stateStore (stateId : StateIdV1) (value : ValueIdV1)
  | construct (typeId : TypeIdV1) (constructorIndex : UInt32) (args : Array ValueIdV1)
  | fieldGet (base : ValueIdV1) (fieldIndex : UInt32)
  | fieldSet (base : ValueIdV1) (fieldIndex : UInt32) (value : ValueIdV1)
  | variantTag (base : ValueIdV1)
  | variantPayload (base : ValueIdV1) (variantIndex payloadIndex : UInt32)
  | indexGet (base : ValueIdV1) (index : ValueIdV1)
  | indexSet (base : ValueIdV1) (index : ValueIdV1) (value : ValueIdV1)
  | checkedCast (value : ValueIdV1) (toType : TypeIdV1)
  | unary (op : UnaryOpV1) (operand : ValueIdV1)
  | binary (op : BinaryOpV1) (lhs : ValueIdV1) (rhs : ValueIdV1)
  | pureCall (callableId : CallableIdV1) (args : Array ValueIdV1)
  | contextRead (key : SchemaId)
  | commit (value : ValueIdV1)
  | assert_ (condition : ValueIdV1) (errorId : Option ErrorIdV1) (args : Array ValueIdV1)
  | emit (effectId : EffectIdV1) (eventId : EventIdV1) (args : Array ValueIdV1)
  | externalCall (effectId : EffectIdV1) (callee : QualifiedName) (args : Array ValueIdV1)
  | schedule (effectId : EffectIdV1) (callee : QualifiedName) (args : Array ValueIdV1)
  deriving BEq

structure InstructionV1 where
  result : Option ValueDefV1
  op : SemanticOpV1
  deriving BEq

structure JumpTargetV1 where
  blockId : BlockIdV1
  args : Array ValueIdV1
  deriving BEq, Repr

structure SwitchCaseV1 where
  typeId : TypeIdV1
  valueBytes : ByteArray
  target : JumpTargetV1
  deriving BEq

inductive SemanticTrapCodeV1 where
  | unreachable
  | invalidExternalResponse
  | resourceExhausted
  | internalInvariant
  deriving BEq, Repr, DecidableEq

inductive TerminatorV1 where
  | jump (target : JumpTargetV1)
  | branch (condition : ValueIdV1) (thenTarget elseTarget : JumpTargetV1)
  | switch (scrutinee : ValueIdV1) (cases : Array SwitchCaseV1)
      (defaultTarget : Option JumpTargetV1)
  | return_ (value : Option ValueIdV1)
  | revert (errorId : ErrorIdV1) (args : Array ValueIdV1)
  | trap (code : SemanticTrapCodeV1)
  deriving BEq

structure BlockV1 where
  id : BlockIdV1
  params : Array BlockParameterV1
  instructions : Array InstructionV1
  terminator : TerminatorV1
  deriving BEq

structure LoopBoundV1 where
  header : BlockIdV1
  backEdgeFrom : BlockIdV1
  maxIterations : UInt32
  deriving BEq, Repr

structure CallableV1 where
  id : CallableIdV1
  kind : CallableKindV1
  name : Option String
  params : Array ParameterV1
  result : CallableResultV1
  entryBlock : BlockIdV1
  blocks : Array BlockV1
  loopBounds : Array LoopBoundV1
  invariantSteps : Option UInt64
  deriving BEq

structure InvariantDeclV1 where
  id : InvariantIdV1
  name : String
  callableId : CallableIdV1
  deriving BEq, Repr

inductive RequirementPredicateV1 where
  | uintAtLeast (name : String) (value : UInt64)
  | uintAtMost (name : String) (value : UInt64)
  | boolEquals (name : String) (value : Bool)
  | enumContains (name : String) (values : Array String)
  | digestEquals (name : String) (value : Digest)
  deriving BEq

structure RequirementRequestV1 where
  id : String
  version : SemVer
  digest : Digest
  predicates : Array RequirementPredicateV1
  deriving BEq

structure ProgramRequirementsV1 where
  items : Array RequirementRequestV1
  deriving BEq

/-- Exact requirement row for the unix-time ContextRead key. -/
def unixTimeSecondsContextRequirementV1 : Except String RequirementRequestV1 := do
  let digest ← domainSeparatedSha256 "pf.context-read-requirement.v1"
    unixTimeSecondsContextRequirementIdV1.toUTF8
  pure {
    id := unixTimeSecondsContextRequirementIdV1
    version := { major := 1, minor := 0, patch := 0 }
    digest
    predicates := #[]
  }

/-- Exact requirement row for the caller ContextRead key (N-2). -/
def callerContextRequirementV1 : Except String RequirementRequestV1 := do
  let digest ← domainSeparatedSha256 "pf.context-read-requirement.v1"
    callerContextRequirementIdV1.toUTF8
  pure {
    id := callerContextRequirementIdV1
    version := { major := 1, minor := 0, patch := 0 }
    digest
    predicates := #[]
  }

/-- Exact requirement row for the v1 Commit disclosure boundary. Recognition
    here does not imply support by any target catalog. -/
def commitmentDisclosureRequirementV1 : Except String RequirementRequestV1 := do
  let digest ← domainSeparatedSha256 "pf.commit-requirement.v1"
    commitmentDisclosureRequirementIdV1.toUTF8
  pure {
    id := commitmentDisclosureRequirementIdV1
    version := { major := 1, minor := 0, patch := 0 }
    digest
    predicates := #[]
  }

inductive SemanticEntityRefV1 where
  | typeRef (id : TypeIdV1)
  | constant (id : ConstantIdV1)
  | state (id : StateIdV1)
  | event (id : EventIdV1)
  | errorRef (id : ErrorIdV1)
  | callable (id : CallableIdV1)
  | block (callableId : CallableIdV1) (blockId : BlockIdV1)
  | instruction (callableId : CallableIdV1) (blockId : BlockIdV1)
      (instructionIndex : UInt32)
  | terminator (callableId : CallableIdV1) (blockId : BlockIdV1)
  | value (callableId : CallableIdV1) (valueId : ValueIdV1)
  | effect (callableId : CallableIdV1) (effectId : EffectIdV1)
  | invariant (id : InvariantIdV1)
  | requirement (index : UInt32)
  deriving BEq

structure OriginBindingV1 where
  entity : SemanticEntityRefV1
  origins : Array SourceOrigin
  deriving BEq

structure SemanticProgramDataV1 where
  qualifiedName : QualifiedName
  types : Array TypeDeclV1
  constants : Array ConstantV1
  logicalState : Array StateDeclV1
  events : Array EventDeclV1
  errors : Array ErrorDeclV1
  callables : Array CallableV1
  invariants : Array InvariantDeclV1
  requirements : ProgramRequirementsV1
  deriving BEq

structure SemanticProvenanceV1 where
  schema : SchemaId
  qualifiedName : QualifiedName
  sourceHash : Digest
  semanticHash : Digest
  originMap : Array OriginBindingV1
  deriving BEq

inductive SemanticWireErrorV1 where
  | truncated
  | limitExceeded
  | badMagic
  | badTag
  | badFieldCount
  | badScalar
  | nonCanonical
  | duplicate
  | badReference
  | badType
  | badCfg
  | badRequirement
  | badProvenance
  | trailingBytes
  deriving BEq, Repr, DecidableEq

structure SemanticProgramV1 where
  canonicalBytes : ByteArray
  deriving BEq

/-- Internal WireV1 error constructor (module-shared; not a public contract). -/
def err (e : SemanticWireErrorV1) : Except SemanticWireErrorV1 α :=
  .error e

/-- Internal WireV1 String-error map to `.badScalar` (not a public contract). -/
def mapCommon (r : Except String α) : Except SemanticWireErrorV1 α :=
  match r with
  | .ok v => .ok v
  | .error _ => .error .badScalar

/-- Internal production loop for unsigned byte-array lexicographic order.
    Naming the existing recursion exposes a refinement seam; the public
    comparator remains the sole ordering authority. -/
def compareByteArrayLexLoopV1 (left right : ByteArray) (n i : Nat) : Ordering :=
  if i < n then
    let bl := left.get! i
    let br := right.get! i
    if bl.toNat < br.toNat then .lt
    else if bl.toNat > br.toNat then .gt
    else compareByteArrayLexLoopV1 left right n (i + 1)
  else if left.size < right.size then .lt
  else if left.size > right.size then .gt
  else .eq
termination_by n - i
decreasing_by omega

/-- Refine one equal-byte step of the sole production lexicographic loop. -/
theorem compareByteArrayLexLoopV1_eq_next (left right : ByteArray) (n i : Nat)
    (hi : i < n) (heq : left.get! i = right.get! i) :
    compareByteArrayLexLoopV1 left right n i =
      compareByteArrayLexLoopV1 left right n (i + 1) := by
  rw [compareByteArrayLexLoopV1.eq_def]
  simp [hi, heq]

/-- Refine a less-than byte step of the sole production lexicographic loop. -/
theorem compareByteArrayLexLoopV1_eq_lt (left right : ByteArray) (n i : Nat)
    (hi : i < n) (hlt : (left.get! i).toNat < (right.get! i).toNat) :
    compareByteArrayLexLoopV1 left right n i = .lt := by
  rw [compareByteArrayLexLoopV1.eq_def]
  simp [hi, hlt]

/-- Refine a greater-than byte step of the sole production lexicographic loop. -/
theorem compareByteArrayLexLoopV1_eq_gt (left right : ByteArray) (n i : Nat)
    (hi : i < n) (hgt : (left.get! i).toNat > (right.get! i).toNat) :
    compareByteArrayLexLoopV1 left right n i = .gt := by
  have hnot : ¬(left.get! i).toNat < (right.get! i).toNat :=
    Nat.not_lt.mpr (Nat.le_of_lt hgt)
  rw [compareByteArrayLexLoopV1.eq_def]
  simp [hi, hnot, hgt]

/-- Unsigned lexicographic order on raw bytes (prefix, then length). -/
def compareByteArrayLex (left right : ByteArray) : Ordering :=
  compareByteArrayLexLoopV1 left right (Nat.min left.size right.size) 0

/-- Internal WireV1 table id==index helper (not a public contract). -/
def checkIdEqualsIndex (id : UInt32) (index : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless id.toNat == index do
    return ← err .duplicate
  pure ()

/-- Internal WireV1 TypeId range helper (not a public contract). -/
def checkTypeIdInRange (typeId : TypeIdV1) (typeCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless typeId.toNat < typeCount do
    return ← err .badReference
  pure ()

end ProofForgeV2.Semantic.WireV1
