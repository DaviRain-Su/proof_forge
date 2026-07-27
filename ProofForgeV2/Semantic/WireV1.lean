import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

/-!
  ProofForgeV2.Semantic.WireV1 — closed SemanticProgramV1 model + root wire codec
  (SPEC-SEM-WIRE-001 engineering subset: D2-06 wire + first structural tables/reqs).

  Owns the SemanticProgramV1 / SemanticProvenanceV1 data model and strict
  little-endian tagged codecs. Does not import Source AST modules, Target, or
  Materialization. Does not replace alpha `Core/SemanticIR.lean`.

  Engineering limits for this slice:
  * Full nested encode/decode tables for records, TypeShape, Visibility,
    CallableKind, ops, terminators, entities, and requirement predicates.
  * Root round-trip + SHA-256 hash + provenance **envelope-only** encode/decode.
  * Nesting fuel: every tagged wire value shares `withTaggedNesting` (enter
    when `nesting < maxNesting` (=256), leave after body). Non-tagged scalars
    (u32/string/Digest/arrays of scalars) do not consume fuel. Current model
    has no recursive TypeShape-on-wire; fuel still applies on the shared path.
  * Structural subset (SPEC §4.5 / §5 / §6 / §6.2 + CAP SupportPredicate rank):
    - table `decl.id == array index` (`.duplicate` on mismatch)
    - shallow declaration-record TypeId / CallableId range (`.badReference`)
    - type-shape / FieldSpec / Map-key (SPEC §5), after shallow refs and
      before requirements:
        · `name=some` iff shape is `.struct`/`.enum`; other shapes
          require `name=none` (`.badType`)
        · struct fields / enum variants nonempty (`.badType`)
        · integer widths ∈ {8,16,32,64,128,256} (`.badType`)
        · Bytes/Array length ≤ 4096 (`.badType`)
        · FieldSpec catalog: only `proof-forge.field.bn254-fr.v1` with
          exact 32-byte modulusBE (`bn254FrFieldSpecV1`; `.badType`)
        · unique struct field / enum variant names within one decl
          (`.duplicate`)
        · Map key legality: Bool|UInt|Int|Principal|Bytes|Struct of
          recursively legal keys; reject Option/Array/Map/Enum/Unit/Field
          (`.badType`; recursion fuel = types.size)
    - requirement key order/uniqueness, RequirementId domain segment,
      predicate name+rank+wire order, `enumContains` nonempty unique ascending
      (`.badRequirement`)
  * API contracts (structure vs transport):
    - `decodeSemanticProgramDataV1`: transport/scalar only (magic, tags,
      limits/nesting, trailing). **No** structure gate.
    - `encodeSemanticProgramDataV1`: structure gate **before** any program
      bytes (`validateSemanticProgramStructureV1`).
    - `decodeSemanticProgramV1`: data decode → structure-gated re-encode →
      exact byte identity. Structurally invalid carriers fail on the re-encode
      path (structure error class or `.nonCanonical`); this is **not** a
      structure-free identity check.
    - `validateSemanticProgramV1` / `semanticHashV1`: re-encode identity plus
      explicit structure gate (hash only after both succeed).
  * Provenance engineering stub (not formal join):
    - `encodeSemanticProvenanceV1` / `decodeSemanticProvenanceV1`: closed
      envelope transport + re-encode identity only.
    - `semanticProvenanceDigestV1`: SHA-256 of envelope bytes after
      encode/decode round-trip of that envelope. **Does not** run source/
      NodeId inventory join and must not be read as formal provenance
      acceptance.
    - `validateSemanticProvenanceV1`: always `.badProvenance` in this slice
      (join unimplemented).
  * Not yet: CFG/dominance, full TypeKey anonymous ranking/interning,
    constant/literal valueBytes, provenance inventory join,
    ProgramV1 normalizer, product CheckV1/compile/CLI wiring.
-/

namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Schema / domain constants (SPEC-SEM-WIRE-001 §1). -/
def semanticProgramSchemaIdV1 : String := "proof-forge.semantic-program.v1"
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

/-- v1 Field catalog sole entry id (SPEC-SEM-WIRE-001 §5). -/
def bn254FrFieldIdV1 : String := "proof-forge.field.bn254-fr.v1"

/-- Exact bn254 Fr modulus big-endian bytes (SPEC-SEM-WIRE-001 §5). -/
def bn254FrModulusBEV1 : ByteArray :=
  ByteArray.mk #[
    0x30, 0x64, 0x4e, 0x72, 0xe1, 0x31, 0xa0, 0x29,
    0xb8, 0x50, 0x45, 0xb6, 0x81, 0x81, 0x58, 0x5d,
    0x28, 0x33, 0xe8, 0x48, 0x79, 0xb9, 0x70, 0x91,
    0x43, 0xe1, 0xf5, 0x93, 0xf0, 0x00, 0x00, 0x01
  ]

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

private def err (e : SemanticWireErrorV1) : Except SemanticWireErrorV1 α :=
  .error e

private def mapCommon (r : Except String α) : Except SemanticWireErrorV1 α :=
  match r with
  | .ok v => .ok v
  | .error _ => .error .badScalar

/-! ### Primitive encode -/

def encodeU8 (value : UInt8) : ByteArray :=
  ByteArray.empty.push value

def encodeU16le (value : UInt16) : ByteArray :=
  let v := value.toNat
  (ByteArray.empty.push (UInt8.ofNat (v % 256))).push (UInt8.ofNat ((v / 256) % 256))

def encodeU32le (value : UInt32) : ByteArray :=
  let v := value.toNat
  let b0 := UInt8.ofNat (v % 256)
  let b1 := UInt8.ofNat ((v / 256) % 256)
  let b2 := UInt8.ofNat ((v / 65536) % 256)
  let b3 := UInt8.ofNat ((v / 16777216) % 256)
  ((((ByteArray.empty.push b0).push b1).push b2).push b3)

def encodeU64le (value : UInt64) : ByteArray := Id.run do
  let v := value.toNat
  let mut out := ByteArray.emptyWithCapacity 8
  let mut n := v
  for _ in [:8] do
    out := out.push (UInt8.ofNat (n % 256))
    n := n / 256
  pure out

def encodeBool (value : Bool) : ByteArray :=
  encodeU8 (if value then 1 else 0)

private def encodeNatAsU32le (count : Nat) : Except SemanticWireErrorV1 ByteArray := do
  unless count ≤ UInt32.size - 1 do
    return ← err .limitExceeded
  pure (encodeU32le (UInt32.ofNat count))

private def encodeNatAsU16le (count : Nat) : Except SemanticWireErrorV1 ByteArray := do
  unless count ≤ UInt16.size - 1 do
    return ← err .limitExceeded
  pure (encodeU16le (UInt16.ofNat count))

def encodeOption (encode : α → Except SemanticWireErrorV1 ByteArray) :
    Option α → Except SemanticWireErrorV1 ByteArray
  | none => pure (encodeU8 0)
  | some value => do
      let payload ← encode value
      pure ((encodeU8 1).append payload)

def encodeArray (encode : α → Except SemanticWireErrorV1 ByteArray)
    (values : Array α) : Except SemanticWireErrorV1 ByteArray := do
  unless values.size ≤ maxArrayElements do
    return ← err .limitExceeded
  let header ← encodeNatAsU32le values.size
  let mut payload := ByteArray.empty
  for value in values do
    let chunk ← encode value
    payload := payload.append chunk
  pure (header.append payload)

def encodeByteArray (value : ByteArray) : Except SemanticWireErrorV1 ByteArray := do
  unless value.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  let header ← encodeNatAsU32le value.size
  pure (header.append value)

def encodeString (value : String) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (requireNfc value)
  let raw := value.toUTF8
  unless raw.size ≤ maxStringBytes do
    return ← err .limitExceeded
  let header ← encodeNatAsU32le raw.size
  pure (header.append raw)

def encodeDigest (digest : Digest) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateDigest digest)
  pure digest.bytes

def encodeNodeId (nodeId : NodeId) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateNodeId nodeId)
  pure nodeId.bytes

def encodeSchemaId (schema : SchemaId) : Except SemanticWireErrorV1 ByteArray := do
  let s ← mapCommon (renderSchemaId schema)
  encodeString s

def encodeSemVer (version : SemVer) : Except SemanticWireErrorV1 ByteArray := do
  let s ← mapCommon (renderSemVer version)
  encodeString s

def encodeQualifiedName (name : QualifiedName) : Except SemanticWireErrorV1 ByteArray := do
  let components ← mapCommon (renderQualifiedNameComponents name)
  encodeArray encodeString components

def encodeProjectRelativePath (path : ProjectRelativePath) :
    Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateProjectRelativePath path)
  encodeString path.value

def encodeSourceOrigin (origin : SourceOrigin) : Except SemanticWireErrorV1 ByteArray := do
  mapCommon (validateSourceOrigin origin)
  let pathB ← encodeProjectRelativePath origin.sourcePath
  let startB := encodeU64le origin.startByte
  let endB := encodeU64le origin.endByte
  let nodeB ← encodeNodeId origin.nodeId
  pure (((pathB.append startB).append endB).append nodeB)

private def isAsciiTag (tag : String) : Bool := Id.run do
  for c in tag.toList do
    unless (c : Char).val ≤ 127 do
      return false
  return true

def encodeTagged (tag : String) (fields : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  if tag.isEmpty then
    return ← err .badTag
  unless isAsciiTag tag do
    return ← err .badTag
  let tagBytes := tag.toUTF8
  unless tagBytes.size ≤ maxTagAsciiBytes do
    return ← err .limitExceeded
  let tagLen ← encodeNatAsU32le tagBytes.size
  let fieldCount ← encodeNatAsU16le fields.size
  let mut out := (tagLen.append tagBytes).append fieldCount
  for field in fields do
    out := out.append field
  pure out

def encodeNullary (tag : String) : Except SemanticWireErrorV1 ByteArray :=
  encodeTagged tag #[]

/-! ### Primitive decode cursor -/

structure Cursor where
  private mk ::
  private input : ByteArray
  private offset : Nat
  /-- Tagged-value nesting depth (0 at root entry). Shared by all tagged readers. -/
  private nesting : Nat

abbrev Decoder (α : Type) := Cursor → Except SemanticWireErrorV1 (α × Cursor)

def start (input : ByteArray) : Cursor :=
  ⟨input, 0, 0⟩

/-- Start a cursor at a synthetic nesting depth (nesting-limit tests). -/
def startAtNesting (input : ByteArray) (nesting : Nat) : Cursor :=
  ⟨input, 0, nesting⟩

def remaining (c : Cursor) : Nat :=
  c.input.size - c.offset

def cursorNesting (c : Cursor) : Nat :=
  c.nesting

def finish (c : Cursor) : Except SemanticWireErrorV1 Unit := do
  unless remaining c == 0 do
    return ← err .trailingBytes
  pure ()

private def takeByte (c : Cursor) : Except SemanticWireErrorV1 (UInt8 × Cursor) := do
  unless remaining c ≥ 1 do
    return ← err .truncated
  pure (c.input.get! c.offset, ⟨c.input, c.offset + 1, c.nesting⟩)

private def takeBytes (c : Cursor) (n : Nat) :
    Except SemanticWireErrorV1 (ByteArray × Cursor) := do
  unless remaining c ≥ n do
    return ← err .truncated
  pure (c.input.extract c.offset (c.offset + n), ⟨c.input, c.offset + n, c.nesting⟩)

/-- Shared nesting frame for every tagged wire value (records + sums).
    Enter fails with `.limitExceeded` when `nesting ≥ maxNesting`.
    Non-tagged scalar/array-header readers do not call this. -/
def withTaggedNesting (body : Decoder α) : Decoder α := fun c => do
  unless c.nesting < maxNesting do
    return ← err .limitExceeded
  let parent := c.nesting
  let c : Cursor := ⟨c.input, c.offset, parent + 1⟩
  let (v, c) ← body c
  pure (v, ⟨c.input, c.offset, parent⟩)

def decodeU8 : Decoder UInt8 := takeByte

def decodeU16le : Decoder UInt16 := fun c => do
  let (b0, c) ← takeByte c
  let (b1, c) ← takeByte c
  pure (UInt16.ofNat (b0.toNat + b1.toNat * 256), c)

def decodeU32le : Decoder UInt32 := fun c => do
  let (b0, c) ← takeByte c
  let (b1, c) ← takeByte c
  let (b2, c) ← takeByte c
  let (b3, c) ← takeByte c
  let v := b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat v, c)

def decodeU64le : Decoder UInt64 := fun c => do
  let mut n : Nat := 0
  let mut place : Nat := 1
  let mut c := c
  for _ in [:8] do
    let (b, c') ← takeByte c
    c := c'
    n := n + b.toNat * place
    place := place * 256
  pure (UInt64.ofNat n, c)

def decodeBool : Decoder Bool := fun c => do
  let (m, c) ← decodeU8 c
  match m.toNat with
  | 0 => pure (false, c)
  | 1 => pure (true, c)
  | _ => err .badScalar

def decodeOption (decode : Decoder α) : Decoder (Option α) := fun c => do
  let (m, c) ← decodeU8 c
  match m.toNat with
  | 0 => pure (none, c)
  | 1 =>
    let (v, c) ← decode c
    pure (some v, c)
  | _ => err .badScalar

def decodeArray (maxCount : Nat) (decode : Decoder α) : Decoder (Array α) := fun c => do
  let (countU, c) ← decodeU32le c
  let count := countU.toNat
  if count > maxCount then
    return ← err .limitExceeded
  let mut acc : Array α := Array.empty
  let mut c := c
  for _ in [:count] do
    let (v, c') ← decode c
    acc := acc.push v
    c := c'
  pure (acc, c)

def decodeByteArray (maxLen : Nat) : Decoder ByteArray := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  if len > maxLen then
    return ← err .limitExceeded
  unless remaining c ≥ len do
    return ← err .truncated
  takeBytes c len

def decodeString : Decoder String := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  if len > maxStringBytes then
    return ← err .limitExceeded
  unless remaining c ≥ len do
    return ← err .truncated
  let (raw, c) ← takeBytes c len
  match String.fromUTF8? raw with
  | none => err .badScalar
  | some s => do
      match requireNfc s with
      | .error _ => err .badScalar
      | .ok _ => pure (s, c)

def decodeDigest : Decoder Digest := fun c => do
  let (bytes, c) ← takeBytes c 32
  let digest : Digest := { algorithm := .sha256, bytes }
  match validateDigest digest with
  | .error _ => err .badScalar
  | .ok _ => pure (digest, c)

def decodeNodeId : Decoder NodeId := fun c => do
  let (bytes, c) ← takeBytes c 16
  let nodeId : NodeId := { bytes }
  match validateNodeId nodeId with
  | .error _ => err .badScalar
  | .ok _ => pure (nodeId, c)

def decodeSchemaId : Decoder SchemaId := fun c => do
  let (s, c) ← decodeString c
  match parseSchemaId s with
  | .error _ => err .badScalar
  | .ok schema => pure (schema, c)

def decodeSemVer : Decoder SemVer := fun c => do
  let (s, c) ← decodeString c
  match parseSemVer s with
  | .error _ => err .badScalar
  | .ok version => pure (version, c)

def decodeQualifiedName : Decoder QualifiedName := fun c => do
  let (components, c) ← decodeArray 256 decodeString c
  match parseQualifiedName components with
  | .error _ => err .badScalar
  | .ok name => pure (name, c)

def decodeProjectRelativePath : Decoder ProjectRelativePath := fun c => do
  let (s, c) ← decodeString c
  match parseProjectRelativePath s with
  | .error _ => err .badScalar
  | .ok path => pure (path, c)

def decodeSourceOrigin : Decoder SourceOrigin := fun c => do
  let (sourcePath, c) ← decodeProjectRelativePath c
  let (startByte, c) ← decodeU64le c
  let (endByte, c) ← decodeU64le c
  let (nodeId, c) ← decodeNodeId c
  let origin : SourceOrigin := { sourcePath, startByte, endByte, nodeId }
  match validateSourceOrigin origin with
  | .error _ => err .badScalar
  | .ok _ => pure (origin, c)

def decodeTag : Decoder String := fun c => do
  let (lenU, c) ← decodeU32le c
  let len := lenU.toNat
  unless 1 ≤ len && len ≤ maxTagAsciiBytes do
    return ← err .badTag
  unless remaining c ≥ len do
    return ← err .truncated
  let (raw, c) ← takeBytes c len
  match String.fromUTF8? raw with
  | none => err .badTag
  | some tag => do
      unless isAsciiTag tag do
        return ← err .badTag
      pure (tag, c)

def decodeFieldCount (expected : Nat) : Decoder Unit := fun c => do
  let (count, c) ← decodeU16le c
  unless count.toNat == expected do
    return ← err .badFieldCount
  pure ((), c)

def expectTag (want : String) (fieldCount : Nat) : Decoder Unit := fun c => do
  let (tag, c) ← decodeTag c
  unless tag == want do
    return ← err .badTag
  decodeFieldCount fieldCount c

private def decodeNullary (want : String) : Decoder Unit :=
  expectTag want 0

/-! ### Visibility / type / callable kind encode+decode -/

def encodeVisibilityV1 : VisibilityV1 → Except SemanticWireErrorV1 ByteArray
  | .public_ => encodeNullary "Visibility.Public"
  | .private_ => encodeNullary "Visibility.Private"
  | .commitment => encodeNullary "Visibility.Commitment"

def decodeVisibilityV1 : Decoder VisibilityV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Visibility.Public" => pure (.public_, c)
  | "Visibility.Private" => pure (.private_, c)
  | "Visibility.Commitment" => pure (.commitment, c)
  | _ => err .badTag

def encodeFieldSpecV1 (spec : FieldSpecV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB ← encodeSchemaId spec.id
  let modB ← encodeByteArray spec.modulusBE
  encodeTagged "FieldSpec" #[idB, modB]

def decodeFieldSpecV1 : Decoder FieldSpecV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "FieldSpec" 2 c
  let (id, c) ← decodeSchemaId c
  let (modulusBE, c) ← decodeByteArray maxCanonicalProgramBytes c
  pure ({ id, modulusBE }, c)

def encodeStructFieldV1 (f : StructFieldV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString f.name
  let typeB := encodeU32le f.typeId
  encodeTagged "StructField" #[nameB, typeB]

def decodeStructFieldV1 : Decoder StructFieldV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "StructField" 2 c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  pure ({ name, typeId }, c)

def encodeEnumVariantV1 (v : EnumVariantV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString v.name
  let payloadB ← encodeArray (fun id => pure (encodeU32le id)) v.payloadTypes
  encodeTagged "EnumVariant" #[nameB, payloadB]

def decodeEnumVariantV1 : Decoder EnumVariantV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "EnumVariant" 2 c
  let (name, c) ← decodeString c
  let (payloadTypes, c) ← decodeArray maxArrayElements decodeU32le c
  pure ({ name, payloadTypes }, c)

def encodeTypeShapeV1 : TypeShapeV1 → Except SemanticWireErrorV1 ByteArray
  | .bool => encodeNullary "Type.Bool"
  | .uint w => do
      encodeTagged "Type.UInt" #[encodeU16le w]
  | .int w => do
      encodeTagged "Type.Int" #[encodeU16le w]
  | .principal => encodeNullary "Type.Principal"
  | .unit => encodeNullary "Type.Unit"
  | .bytes len => do
      encodeTagged "Type.Bytes" #[encodeU32le len]
  | .array element length => do
      encodeTagged "Type.Array" #[encodeU32le element, encodeU32le length]
  | .map key value => do
      encodeTagged "Type.Map" #[encodeU32le key, encodeU32le value]
  | .option element => do
      encodeTagged "Type.Option" #[encodeU32le element]
  | .field spec => do
      let specB ← encodeFieldSpecV1 spec
      encodeTagged "Type.Field" #[specB]
  | .struct fields => do
      let fieldsB ← encodeArray encodeStructFieldV1 fields
      encodeTagged "Type.Struct" #[fieldsB]
  | .enum variants => do
      let variantsB ← encodeArray encodeEnumVariantV1 variants
      encodeTagged "Type.Enum" #[variantsB]

def decodeTypeShapeV1 : Decoder TypeShapeV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Type.Bool" => do
      let ((), c) ← decodeFieldCount 0 c
      pure (.bool, c)
  | "Type.UInt" => do
      let ((), c) ← decodeFieldCount 1 c
      let (w, c) ← decodeU16le c
      pure (.uint w, c)
  | "Type.Int" => do
      let ((), c) ← decodeFieldCount 1 c
      let (w, c) ← decodeU16le c
      pure (.int w, c)
  | "Type.Principal" => do
      let ((), c) ← decodeFieldCount 0 c
      pure (.principal, c)
  | "Type.Unit" => do
      let ((), c) ← decodeFieldCount 0 c
      pure (.unit, c)
  | "Type.Bytes" => do
      let ((), c) ← decodeFieldCount 1 c
      let (len, c) ← decodeU32le c
      pure (.bytes len, c)
  | "Type.Array" => do
      let ((), c) ← decodeFieldCount 2 c
      let (element, c) ← decodeU32le c
      let (length, c) ← decodeU32le c
      pure (.array element length, c)
  | "Type.Map" => do
      let ((), c) ← decodeFieldCount 2 c
      let (key, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.map key value, c)
  | "Type.Option" => do
      let ((), c) ← decodeFieldCount 1 c
      let (element, c) ← decodeU32le c
      pure (.option element, c)
  | "Type.Field" => do
      let ((), c) ← decodeFieldCount 1 c
      let (spec, c) ← decodeFieldSpecV1 c
      pure (.field spec, c)
  | "Type.Struct" => do
      let ((), c) ← decodeFieldCount 1 c
      let (fields, c) ← decodeArray maxArrayElements decodeStructFieldV1 c
      pure (.struct fields, c)
  | "Type.Enum" => do
      let ((), c) ← decodeFieldCount 1 c
      let (variants, c) ← decodeArray maxArrayElements decodeEnumVariantV1 c
      pure (.enum variants, c)
  | _ => err .badTag

def encodeTypeDeclV1 (d : TypeDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeOption encodeString d.name
  let shapeB ← encodeTypeShapeV1 d.shape
  encodeTagged "TypeDecl" #[idB, nameB, shapeB]

def decodeTypeDeclV1 : Decoder TypeDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "TypeDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeOption decodeString c
  let (shape, c) ← decodeTypeShapeV1 c
  pure ({ id, name, shape }, c)

def encodeConstantV1 (d : ConstantV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let typeB := encodeU32le d.typeId
  let valueB ← encodeByteArray d.valueBytes
  encodeTagged "Constant" #[idB, nameB, typeB, valueB]

def decodeConstantV1 : Decoder ConstantV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Constant" 4 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (valueBytes, c) ← decodeByteArray maxCanonicalProgramBytes c
  pure ({ id, name, typeId, valueBytes }, c)

def encodeStateDeclV1 (d : StateDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let typeB := encodeU32le d.typeId
  let visB ← encodeVisibilityV1 d.visibility
  encodeTagged "StateDecl" #[idB, nameB, typeB, visB]

def decodeStateDeclV1 : Decoder StateDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "StateDecl" 4 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ id, name, typeId, visibility }, c)

def encodeInterfaceFieldV1 (f : InterfaceFieldV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString f.name
  let typeB := encodeU32le f.typeId
  let visB ← encodeVisibilityV1 f.visibility
  encodeTagged "InterfaceField" #[nameB, typeB, visB]

def decodeInterfaceFieldV1 : Decoder InterfaceFieldV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "InterfaceField" 3 c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ name, typeId, visibility }, c)

def encodeEventDeclV1 (d : EventDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let fieldsB ← encodeArray encodeInterfaceFieldV1 d.fields
  encodeTagged "EventDecl" #[idB, nameB, fieldsB]

def decodeEventDeclV1 : Decoder EventDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "EventDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (fields, c) ← decodeArray maxArrayElements decodeInterfaceFieldV1 c
  pure ({ id, name, fields }, c)

def encodeErrorDeclV1 (d : ErrorDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let idB := encodeU32le d.id
  let nameB ← encodeString d.name
  let fieldsB ← encodeArray encodeInterfaceFieldV1 d.fields
  encodeTagged "ErrorDecl" #[idB, nameB, fieldsB]

def decodeErrorDeclV1 : Decoder ErrorDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "ErrorDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (fields, c) ← decodeArray maxArrayElements decodeInterfaceFieldV1 c
  pure ({ id, name, fields }, c)

def encodeCallableKindV1 : CallableKindV1 → Except SemanticWireErrorV1 ByteArray
  | .initializer => encodeNullary "Callable.Initializer"
  | .entry => encodeNullary "Callable.Entry"
  | .view => encodeNullary "Callable.View"
  | .pureFn => encodeNullary "Callable.PureFn"
  | .invariant => encodeNullary "Callable.Invariant"

def decodeCallableKindV1 : Decoder CallableKindV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Callable.Initializer" => pure (.initializer, c)
  | "Callable.Entry" => pure (.entry, c)
  | "Callable.View" => pure (.view, c)
  | "Callable.PureFn" => pure (.pureFn, c)
  | "Callable.Invariant" => pure (.invariant, c)
  | _ => err .badTag

def encodeParameterV1 (p : ParameterV1) : Except SemanticWireErrorV1 ByteArray := do
  let valueB := encodeU32le p.valueId
  let nameB ← encodeString p.name
  let typeB := encodeU32le p.typeId
  let visB ← encodeVisibilityV1 p.visibility
  encodeTagged "Parameter" #[valueB, nameB, typeB, visB]

def decodeParameterV1 : Decoder ParameterV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Parameter" 4 c
  let (valueId, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ valueId, name, typeId, visibility }, c)

def encodeCallableResultV1 (r : CallableResultV1) : Except SemanticWireErrorV1 ByteArray := do
  let typeB := encodeU32le r.typeId
  let visB ← encodeVisibilityV1 r.visibility
  encodeTagged "CallableResult" #[typeB, visB]

def decodeCallableResultV1 : Decoder CallableResultV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "CallableResult" 2 c
  let (typeId, c) ← decodeU32le c
  let (visibility, c) ← decodeVisibilityV1 c
  pure ({ typeId, visibility }, c)

def encodeValueDefV1 (v : ValueDefV1) : Except SemanticWireErrorV1 ByteArray := do
  encodeTagged "ValueDef" #[encodeU32le v.valueId, encodeU32le v.typeId]

def decodeValueDefV1 : Decoder ValueDefV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "ValueDef" 2 c
  let (valueId, c) ← decodeU32le c
  let (typeId, c) ← decodeU32le c
  pure ({ valueId, typeId }, c)

def encodeBlockParameterV1 (p : BlockParameterV1) : Except SemanticWireErrorV1 ByteArray := do
  encodeTagged "BlockParameter" #[encodeU32le p.valueId, encodeU32le p.typeId]

def decodeBlockParameterV1 : Decoder BlockParameterV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "BlockParameter" 2 c
  let (valueId, c) ← decodeU32le c
  let (typeId, c) ← decodeU32le c
  pure ({ valueId, typeId }, c)

def encodeUnaryOpV1 : UnaryOpV1 → Except SemanticWireErrorV1 ByteArray
  | .neg => encodeNullary "Unary.Neg"
  | .not => encodeNullary "Unary.Not"
  | .bitNot => encodeNullary "Unary.BitNot"

def decodeUnaryOpV1 : Decoder UnaryOpV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Unary.Neg" => pure (.neg, c)
  | "Unary.Not" => pure (.not, c)
  | "Unary.BitNot" => pure (.bitNot, c)
  | _ => err .badTag

def encodeBinaryOpV1 : BinaryOpV1 → Except SemanticWireErrorV1 ByteArray
  | .add => encodeNullary "Binary.Add"
  | .sub => encodeNullary "Binary.Sub"
  | .mul => encodeNullary "Binary.Mul"
  | .div => encodeNullary "Binary.Div"
  | .mod => encodeNullary "Binary.Mod"
  | .eq => encodeNullary "Binary.Eq"
  | .ne => encodeNullary "Binary.Ne"
  | .lt => encodeNullary "Binary.Lt"
  | .le => encodeNullary "Binary.Le"
  | .gt => encodeNullary "Binary.Gt"
  | .ge => encodeNullary "Binary.Ge"
  | .and => encodeNullary "Binary.And"
  | .or => encodeNullary "Binary.Or"
  | .bitAnd => encodeNullary "Binary.BitAnd"
  | .bitOr => encodeNullary "Binary.BitOr"
  | .bitXor => encodeNullary "Binary.BitXor"
  | .shl => encodeNullary "Binary.Shl"
  | .shr => encodeNullary "Binary.Shr"

def decodeBinaryOpV1 : Decoder BinaryOpV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Binary.Add" => pure (.add, c)
  | "Binary.Sub" => pure (.sub, c)
  | "Binary.Mul" => pure (.mul, c)
  | "Binary.Div" => pure (.div, c)
  | "Binary.Mod" => pure (.mod, c)
  | "Binary.Eq" => pure (.eq, c)
  | "Binary.Ne" => pure (.ne, c)
  | "Binary.Lt" => pure (.lt, c)
  | "Binary.Le" => pure (.le, c)
  | "Binary.Gt" => pure (.gt, c)
  | "Binary.Ge" => pure (.ge, c)
  | "Binary.And" => pure (.and, c)
  | "Binary.Or" => pure (.or, c)
  | "Binary.BitAnd" => pure (.bitAnd, c)
  | "Binary.BitOr" => pure (.bitOr, c)
  | "Binary.BitXor" => pure (.bitXor, c)
  | "Binary.Shl" => pure (.shl, c)
  | "Binary.Shr" => pure (.shr, c)
  | _ => err .badTag

def encodeValueIdArray (args : Array ValueIdV1) : Except SemanticWireErrorV1 ByteArray :=
  encodeArray (fun id => pure (encodeU32le id)) args

def encodeSemanticOpV1 : SemanticOpV1 → Except SemanticWireErrorV1 ByteArray
  | .literal typeId valueBytes => do
      let vb ← encodeByteArray valueBytes
      encodeTagged "Op.Literal" #[encodeU32le typeId, vb]
  | .constant constantId =>
      encodeTagged "Op.Constant" #[encodeU32le constantId]
  | .stateLoad stateId =>
      encodeTagged "Op.StateLoad" #[encodeU32le stateId]
  | .stateStore stateId value =>
      encodeTagged "Op.StateStore" #[encodeU32le stateId, encodeU32le value]
  | .construct typeId constructorIndex args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Construct" #[encodeU32le typeId, encodeU32le constructorIndex, argsB]
  | .fieldGet base fieldIndex =>
      encodeTagged "Op.FieldGet" #[encodeU32le base, encodeU32le fieldIndex]
  | .fieldSet base fieldIndex value =>
      encodeTagged "Op.FieldSet" #[encodeU32le base, encodeU32le fieldIndex, encodeU32le value]
  | .variantTag base =>
      encodeTagged "Op.VariantTag" #[encodeU32le base]
  | .variantPayload base variantIndex payloadIndex =>
      encodeTagged "Op.VariantPayload"
        #[encodeU32le base, encodeU32le variantIndex, encodeU32le payloadIndex]
  | .indexGet base index =>
      encodeTagged "Op.IndexGet" #[encodeU32le base, encodeU32le index]
  | .indexSet base index value =>
      encodeTagged "Op.IndexSet" #[encodeU32le base, encodeU32le index, encodeU32le value]
  | .checkedCast value toType =>
      encodeTagged "Op.CheckedCast" #[encodeU32le value, encodeU32le toType]
  | .unary op operand => do
      let opB ← encodeUnaryOpV1 op
      encodeTagged "Op.Unary" #[opB, encodeU32le operand]
  | .binary op lhs rhs => do
      let opB ← encodeBinaryOpV1 op
      encodeTagged "Op.Binary" #[opB, encodeU32le lhs, encodeU32le rhs]
  | .pureCall callableId args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.PureCall" #[encodeU32le callableId, argsB]
  | .contextRead key => do
      let keyB ← encodeSchemaId key
      encodeTagged "Op.ContextRead" #[keyB]
  | .commit value =>
      encodeTagged "Op.Commit" #[encodeU32le value]
  | .assert_ condition errorId args => do
      let errB ← encodeOption (fun id => pure (encodeU32le id)) errorId
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Assert" #[encodeU32le condition, errB, argsB]
  | .emit effectId eventId args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Emit" #[encodeU32le effectId, encodeU32le eventId, argsB]
  | .externalCall effectId callee args => do
      let calleeB ← encodeQualifiedName callee
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.ExternalCall" #[encodeU32le effectId, calleeB, argsB]
  | .schedule effectId callee args => do
      let calleeB ← encodeQualifiedName callee
      let argsB ← encodeValueIdArray args
      encodeTagged "Op.Schedule" #[encodeU32le effectId, calleeB, argsB]

def decodeSemanticOpV1 : Decoder SemanticOpV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Op.Literal" => do
      let ((), c) ← decodeFieldCount 2 c
      let (typeId, c) ← decodeU32le c
      let (valueBytes, c) ← decodeByteArray maxCanonicalProgramBytes c
      pure (.literal typeId valueBytes, c)
  | "Op.Constant" => do
      let ((), c) ← decodeFieldCount 1 c
      let (constantId, c) ← decodeU32le c
      pure (.constant constantId, c)
  | "Op.StateLoad" => do
      let ((), c) ← decodeFieldCount 1 c
      let (stateId, c) ← decodeU32le c
      pure (.stateLoad stateId, c)
  | "Op.StateStore" => do
      let ((), c) ← decodeFieldCount 2 c
      let (stateId, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.stateStore stateId value, c)
  | "Op.Construct" => do
      let ((), c) ← decodeFieldCount 3 c
      let (typeId, c) ← decodeU32le c
      let (constructorIndex, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.construct typeId constructorIndex args, c)
  | "Op.FieldGet" => do
      let ((), c) ← decodeFieldCount 2 c
      let (base, c) ← decodeU32le c
      let (fieldIndex, c) ← decodeU32le c
      pure (.fieldGet base fieldIndex, c)
  | "Op.FieldSet" => do
      let ((), c) ← decodeFieldCount 3 c
      let (base, c) ← decodeU32le c
      let (fieldIndex, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.fieldSet base fieldIndex value, c)
  | "Op.VariantTag" => do
      let ((), c) ← decodeFieldCount 1 c
      let (base, c) ← decodeU32le c
      pure (.variantTag base, c)
  | "Op.VariantPayload" => do
      let ((), c) ← decodeFieldCount 3 c
      let (base, c) ← decodeU32le c
      let (variantIndex, c) ← decodeU32le c
      let (payloadIndex, c) ← decodeU32le c
      pure (.variantPayload base variantIndex payloadIndex, c)
  | "Op.IndexGet" => do
      let ((), c) ← decodeFieldCount 2 c
      let (base, c) ← decodeU32le c
      let (index, c) ← decodeU32le c
      pure (.indexGet base index, c)
  | "Op.IndexSet" => do
      let ((), c) ← decodeFieldCount 3 c
      let (base, c) ← decodeU32le c
      let (index, c) ← decodeU32le c
      let (value, c) ← decodeU32le c
      pure (.indexSet base index value, c)
  | "Op.CheckedCast" => do
      let ((), c) ← decodeFieldCount 2 c
      let (value, c) ← decodeU32le c
      let (toType, c) ← decodeU32le c
      pure (.checkedCast value toType, c)
  | "Op.Unary" => do
      let ((), c) ← decodeFieldCount 2 c
      let (op, c) ← decodeUnaryOpV1 c
      let (operand, c) ← decodeU32le c
      pure (.unary op operand, c)
  | "Op.Binary" => do
      let ((), c) ← decodeFieldCount 3 c
      let (op, c) ← decodeBinaryOpV1 c
      let (lhs, c) ← decodeU32le c
      let (rhs, c) ← decodeU32le c
      pure (.binary op lhs rhs, c)
  | "Op.PureCall" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.pureCall callableId args, c)
  | "Op.ContextRead" => do
      let ((), c) ← decodeFieldCount 1 c
      let (key, c) ← decodeSchemaId c
      pure (.contextRead key, c)
  | "Op.Commit" => do
      let ((), c) ← decodeFieldCount 1 c
      let (value, c) ← decodeU32le c
      pure (.commit value, c)
  | "Op.Assert" => do
      let ((), c) ← decodeFieldCount 3 c
      let (condition, c) ← decodeU32le c
      let (errorId, c) ← decodeOption decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.assert_ condition errorId args, c)
  | "Op.Emit" => do
      let ((), c) ← decodeFieldCount 3 c
      let (effectId, c) ← decodeU32le c
      let (eventId, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.emit effectId eventId args, c)
  | "Op.ExternalCall" => do
      let ((), c) ← decodeFieldCount 3 c
      let (effectId, c) ← decodeU32le c
      let (callee, c) ← decodeQualifiedName c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.externalCall effectId callee args, c)
  | "Op.Schedule" => do
      let ((), c) ← decodeFieldCount 3 c
      let (effectId, c) ← decodeU32le c
      let (callee, c) ← decodeQualifiedName c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.schedule effectId callee args, c)
  | _ => err .badTag

def encodeInstructionV1 (i : InstructionV1) : Except SemanticWireErrorV1 ByteArray := do
  let resultB ← encodeOption encodeValueDefV1 i.result
  let opB ← encodeSemanticOpV1 i.op
  encodeTagged "Instruction" #[resultB, opB]

def decodeInstructionV1 : Decoder InstructionV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Instruction" 2 c
  let (result, c) ← decodeOption decodeValueDefV1 c
  let (op, c) ← decodeSemanticOpV1 c
  pure ({ result, op }, c)

def encodeJumpTargetV1 (t : JumpTargetV1) : Except SemanticWireErrorV1 ByteArray := do
  let argsB ← encodeValueIdArray t.args
  encodeTagged "JumpTarget" #[encodeU32le t.blockId, argsB]

def decodeJumpTargetV1 : Decoder JumpTargetV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "JumpTarget" 2 c
  let (blockId, c) ← decodeU32le c
  let (args, c) ← decodeArray maxArrayElements decodeU32le c
  pure ({ blockId, args }, c)

def encodeSwitchCaseV1 (sc : SwitchCaseV1) : Except SemanticWireErrorV1 ByteArray := do
  let vb ← encodeByteArray sc.valueBytes
  let tb ← encodeJumpTargetV1 sc.target
  encodeTagged "SwitchCase" #[encodeU32le sc.typeId, vb, tb]

def decodeSwitchCaseV1 : Decoder SwitchCaseV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "SwitchCase" 3 c
  let (typeId, c) ← decodeU32le c
  let (valueBytes, c) ← decodeByteArray maxCanonicalProgramBytes c
  let (target, c) ← decodeJumpTargetV1 c
  pure ({ typeId, valueBytes, target }, c)

def encodeSemanticTrapCodeV1 : SemanticTrapCodeV1 → Except SemanticWireErrorV1 ByteArray
  | .unreachable => encodeNullary "Trap.Unreachable"
  | .invalidExternalResponse => encodeNullary "Trap.InvalidExternalResponse"
  | .resourceExhausted => encodeNullary "Trap.ResourceExhausted"
  | .internalInvariant => encodeNullary "Trap.InternalInvariant"

def decodeSemanticTrapCodeV1 : Decoder SemanticTrapCodeV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  let ((), c) ← decodeFieldCount 0 c
  match tag with
  | "Trap.Unreachable" => pure (.unreachable, c)
  | "Trap.InvalidExternalResponse" => pure (.invalidExternalResponse, c)
  | "Trap.ResourceExhausted" => pure (.resourceExhausted, c)
  | "Trap.InternalInvariant" => pure (.internalInvariant, c)
  | _ => err .badTag

def encodeTerminatorV1 : TerminatorV1 → Except SemanticWireErrorV1 ByteArray
  | .jump target => do
      let tb ← encodeJumpTargetV1 target
      encodeTagged "Term.Jump" #[tb]
  | .branch condition thenTarget elseTarget => do
      let tB ← encodeJumpTargetV1 thenTarget
      let eB ← encodeJumpTargetV1 elseTarget
      encodeTagged "Term.Branch" #[encodeU32le condition, tB, eB]
  | .switch scrutinee cases defaultTarget => do
      let casesB ← encodeArray encodeSwitchCaseV1 cases
      let defB ← encodeOption encodeJumpTargetV1 defaultTarget
      encodeTagged "Term.Switch" #[encodeU32le scrutinee, casesB, defB]
  | .return_ value => do
      let vB ← encodeOption (fun id => pure (encodeU32le id)) value
      encodeTagged "Term.Return" #[vB]
  | .revert errorId args => do
      let argsB ← encodeValueIdArray args
      encodeTagged "Term.Revert" #[encodeU32le errorId, argsB]
  | .trap code => do
      let codeB ← encodeSemanticTrapCodeV1 code
      encodeTagged "Term.Trap" #[codeB]

def decodeTerminatorV1 : Decoder TerminatorV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Term.Jump" => do
      let ((), c) ← decodeFieldCount 1 c
      let (target, c) ← decodeJumpTargetV1 c
      pure (.jump target, c)
  | "Term.Branch" => do
      let ((), c) ← decodeFieldCount 3 c
      let (condition, c) ← decodeU32le c
      let (thenTarget, c) ← decodeJumpTargetV1 c
      let (elseTarget, c) ← decodeJumpTargetV1 c
      pure (.branch condition thenTarget elseTarget, c)
  | "Term.Switch" => do
      let ((), c) ← decodeFieldCount 3 c
      let (scrutinee, c) ← decodeU32le c
      let (cases, c) ← decodeArray maxArrayElements decodeSwitchCaseV1 c
      let (defaultTarget, c) ← decodeOption decodeJumpTargetV1 c
      pure (.switch scrutinee cases defaultTarget, c)
  | "Term.Return" => do
      let ((), c) ← decodeFieldCount 1 c
      let (value, c) ← decodeOption decodeU32le c
      pure (.return_ value, c)
  | "Term.Revert" => do
      let ((), c) ← decodeFieldCount 2 c
      let (errorId, c) ← decodeU32le c
      let (args, c) ← decodeArray maxArrayElements decodeU32le c
      pure (.revert errorId args, c)
  | "Term.Trap" => do
      let ((), c) ← decodeFieldCount 1 c
      let (code, c) ← decodeSemanticTrapCodeV1 c
      pure (.trap code, c)
  | _ => err .badTag

def encodeBlockV1 (b : BlockV1) : Except SemanticWireErrorV1 ByteArray := do
  let paramsB ← encodeArray encodeBlockParameterV1 b.params
  let instrB ← encodeArray encodeInstructionV1 b.instructions
  let termB ← encodeTerminatorV1 b.terminator
  encodeTagged "Block" #[encodeU32le b.id, paramsB, instrB, termB]

def decodeBlockV1 : Decoder BlockV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Block" 4 c
  let (id, c) ← decodeU32le c
  let (params, c) ← decodeArray maxArrayElements decodeBlockParameterV1 c
  let (instructions, c) ← decodeArray maxArrayElements decodeInstructionV1 c
  let (terminator, c) ← decodeTerminatorV1 c
  pure ({ id, params, instructions, terminator }, c)

def encodeLoopBoundV1 (lb : LoopBoundV1) : Except SemanticWireErrorV1 ByteArray := do
  encodeTagged "LoopBound"
    #[encodeU32le lb.header, encodeU32le lb.backEdgeFrom, encodeU32le lb.maxIterations]

def decodeLoopBoundV1 : Decoder LoopBoundV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "LoopBound" 3 c
  let (header, c) ← decodeU32le c
  let (backEdgeFrom, c) ← decodeU32le c
  let (maxIterations, c) ← decodeU32le c
  pure ({ header, backEdgeFrom, maxIterations }, c)

def encodeCallableV1 (c : CallableV1) : Except SemanticWireErrorV1 ByteArray := do
  let kindB ← encodeCallableKindV1 c.kind
  let nameB ← encodeOption encodeString c.name
  let paramsB ← encodeArray encodeParameterV1 c.params
  let resultB ← encodeCallableResultV1 c.result
  let blocksB ← encodeArray encodeBlockV1 c.blocks
  let loopB ← encodeArray encodeLoopBoundV1 c.loopBounds
  let stepsB ← encodeOption (fun v => pure (encodeU64le v)) c.invariantSteps
  encodeTagged "Callable" #[
    encodeU32le c.id, kindB, nameB, paramsB, resultB,
    encodeU32le c.entryBlock, blocksB, loopB, stepsB
  ]

def decodeCallableV1 : Decoder CallableV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "Callable" 9 c
  let (id, c) ← decodeU32le c
  let (kind, c) ← decodeCallableKindV1 c
  let (name, c) ← decodeOption decodeString c
  let (params, c) ← decodeArray maxArrayElements decodeParameterV1 c
  let (result, c) ← decodeCallableResultV1 c
  let (entryBlock, c) ← decodeU32le c
  let (blocks, c) ← decodeArray maxArrayElements decodeBlockV1 c
  let (loopBounds, c) ← decodeArray maxArrayElements decodeLoopBoundV1 c
  let (invariantSteps, c) ← decodeOption decodeU64le c
  pure ({ id, kind, name, params, result, entryBlock, blocks, loopBounds, invariantSteps }, c)

def encodeInvariantDeclV1 (d : InvariantDeclV1) : Except SemanticWireErrorV1 ByteArray := do
  let nameB ← encodeString d.name
  encodeTagged "InvariantDecl" #[encodeU32le d.id, nameB, encodeU32le d.callableId]

def decodeInvariantDeclV1 : Decoder InvariantDeclV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "InvariantDecl" 3 c
  let (id, c) ← decodeU32le c
  let (name, c) ← decodeString c
  let (callableId, c) ← decodeU32le c
  pure ({ id, name, callableId }, c)

def encodeRequirementPredicateV1 :
    RequirementPredicateV1 → Except SemanticWireErrorV1 ByteArray
  | .uintAtLeast name value => do
      let nameB ← encodeString name
      encodeTagged "Req.UintAtLeast" #[nameB, encodeU64le value]
  | .uintAtMost name value => do
      let nameB ← encodeString name
      encodeTagged "Req.UintAtMost" #[nameB, encodeU64le value]
  | .boolEquals name value => do
      let nameB ← encodeString name
      encodeTagged "Req.BoolEquals" #[nameB, encodeBool value]
  | .enumContains name values => do
      let nameB ← encodeString name
      let valuesB ← encodeArray encodeString values
      encodeTagged "Req.EnumContains" #[nameB, valuesB]
  | .digestEquals name value => do
      let nameB ← encodeString name
      let digB ← encodeDigest value
      encodeTagged "Req.DigestEquals" #[nameB, digB]

def decodeRequirementPredicateV1 : Decoder RequirementPredicateV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Req.UintAtLeast" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeU64le c
      pure (.uintAtLeast name value, c)
  | "Req.UintAtMost" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeU64le c
      pure (.uintAtMost name value, c)
  | "Req.BoolEquals" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeBool c
      pure (.boolEquals name value, c)
  | "Req.EnumContains" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (values, c) ← decodeArray maxArrayElements decodeString c
      pure (.enumContains name values, c)
  | "Req.DigestEquals" => do
      let ((), c) ← decodeFieldCount 2 c
      let (name, c) ← decodeString c
      let (value, c) ← decodeDigest c
      pure (.digestEquals name value, c)
  | _ => err .badTag

def encodeRequirementRequestV1 (r : RequirementRequestV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let idB ← encodeString r.id
  let verB ← encodeSemVer r.version
  let digB ← encodeDigest r.digest
  let predB ← encodeArray encodeRequirementPredicateV1 r.predicates
  encodeTagged "RequirementRequest" #[idB, verB, digB, predB]

def decodeRequirementRequestV1 : Decoder RequirementRequestV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "RequirementRequest" 4 c
  let (id, c) ← decodeString c
  let (version, c) ← decodeSemVer c
  let (digest, c) ← decodeDigest c
  let (predicates, c) ← decodeArray maxArrayElements decodeRequirementPredicateV1 c
  pure ({ id, version, digest, predicates }, c)

def encodeProgramRequirementsV1 (r : ProgramRequirementsV1) :
    Except SemanticWireErrorV1 ByteArray := do
  let itemsB ← encodeArray encodeRequirementRequestV1 r.items
  encodeTagged "ProgramRequirements" #[itemsB]

def decodeProgramRequirementsV1 : Decoder ProgramRequirementsV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "ProgramRequirements" 1 c
  let (items, c) ← decodeArray maxArrayElements decodeRequirementRequestV1 c
  pure ({ items }, c)

def encodeSemanticEntityRefV1 : SemanticEntityRefV1 → Except SemanticWireErrorV1 ByteArray
  | .typeRef id => encodeTagged "Entity.Type" #[encodeU32le id]
  | .constant id => encodeTagged "Entity.Constant" #[encodeU32le id]
  | .state id => encodeTagged "Entity.State" #[encodeU32le id]
  | .event id => encodeTagged "Entity.Event" #[encodeU32le id]
  | .errorRef id => encodeTagged "Entity.Error" #[encodeU32le id]
  | .callable id => encodeTagged "Entity.Callable" #[encodeU32le id]
  | .block callableId blockId =>
      encodeTagged "Entity.Block" #[encodeU32le callableId, encodeU32le blockId]
  | .instruction callableId blockId instructionIndex =>
      encodeTagged "Entity.Instruction"
        #[encodeU32le callableId, encodeU32le blockId, encodeU32le instructionIndex]
  | .terminator callableId blockId =>
      encodeTagged "Entity.Terminator" #[encodeU32le callableId, encodeU32le blockId]
  | .value callableId valueId =>
      encodeTagged "Entity.Value" #[encodeU32le callableId, encodeU32le valueId]
  | .effect callableId effectId =>
      encodeTagged "Entity.Effect" #[encodeU32le callableId, encodeU32le effectId]
  | .invariant id => encodeTagged "Entity.Invariant" #[encodeU32le id]
  | .requirement index => encodeTagged "Entity.Requirement" #[encodeU32le index]

def decodeSemanticEntityRefV1 : Decoder SemanticEntityRefV1 := withTaggedNesting fun c => do
  let (tag, c) ← decodeTag c
  match tag with
  | "Entity.Type" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.typeRef id, c)
  | "Entity.Constant" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.constant id, c)
  | "Entity.State" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.state id, c)
  | "Entity.Event" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.event id, c)
  | "Entity.Error" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.errorRef id, c)
  | "Entity.Callable" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.callable id, c)
  | "Entity.Block" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (blockId, c) ← decodeU32le c
      pure (.block callableId blockId, c)
  | "Entity.Instruction" => do
      let ((), c) ← decodeFieldCount 3 c
      let (callableId, c) ← decodeU32le c
      let (blockId, c) ← decodeU32le c
      let (instructionIndex, c) ← decodeU32le c
      pure (.instruction callableId blockId instructionIndex, c)
  | "Entity.Terminator" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (blockId, c) ← decodeU32le c
      pure (.terminator callableId blockId, c)
  | "Entity.Value" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (valueId, c) ← decodeU32le c
      pure (.value callableId valueId, c)
  | "Entity.Effect" => do
      let ((), c) ← decodeFieldCount 2 c
      let (callableId, c) ← decodeU32le c
      let (effectId, c) ← decodeU32le c
      pure (.effect callableId effectId, c)
  | "Entity.Invariant" => do
      let ((), c) ← decodeFieldCount 1 c
      let (id, c) ← decodeU32le c
      pure (.invariant id, c)
  | "Entity.Requirement" => do
      let ((), c) ← decodeFieldCount 1 c
      let (index, c) ← decodeU32le c
      pure (.requirement index, c)
  | _ => err .badTag

def encodeOriginBindingV1 (b : OriginBindingV1) : Except SemanticWireErrorV1 ByteArray := do
  let entityB ← encodeSemanticEntityRefV1 b.entity
  unless b.origins.size ≤ maxOriginsPerBinding do
    return ← err .limitExceeded
  let originsB ← encodeArray encodeSourceOrigin b.origins
  encodeTagged "OriginBinding" #[entityB, originsB]

def decodeOriginBindingV1 : Decoder OriginBindingV1 := withTaggedNesting fun c => do
  let ((), c) ← expectTag "OriginBinding" 2 c
  let (entity, c) ← decodeSemanticEntityRefV1 c
  let (origins, c) ← decodeArray maxOriginsPerBinding decodeSourceOrigin c
  pure ({ entity, origins }, c)

/-! ### Root program / provenance encode+decode -/

private def encodeMagicPrefix (magic : String) : ByteArray :=
  magic.toUTF8.push 0

private def consumeMagic (magic : String) : Decoder Unit := fun c => do
  let want := encodeMagicPrefix magic
  unless remaining c ≥ want.size do
    return ← err .truncated
  let (got, c) ← takeBytes c want.size
  unless got == want do
    return ← err .badMagic
  pure ((), c)

private def checkTableSize (size : Nat) : Except SemanticWireErrorV1 Unit := do
  unless size ≤ maxTableElements do
    return ← err .limitExceeded
  pure ()

/-! ### Structural validation subset (tables / shallow refs / type-shape / requirements)

    Encode-before-output, `validateSemanticProgramV1`, and the re-encode leg of
    `decodeSemanticProgramV1` require this subset. `decodeSemanticProgramDataV1`
    does not (transport only). See module header API contracts.

    Stable order (SPEC §6.2 engineering subset): table id/index → shallow
    declaration refs → type-shape/FieldSpec/Map-key → requirements.
-/

/-- Unsigned lexicographic order on raw bytes (prefix, then length). -/
private def compareByteArrayLex (left right : ByteArray) : Ordering :=
  let n := Nat.min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      let bl := left.get! i
      let br := right.get! i
      if bl.toNat < br.toNat then .lt
      else if bl.toNat > br.toNat then .gt
      else loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

private def checkIdEqualsIndex (id : UInt32) (index : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless id.toNat == index do
    return ← err .duplicate
  pure ()

private def checkTypeIdInRange (typeId : TypeIdV1) (typeCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless typeId.toNat < typeCount do
    return ← err .badReference
  pure ()

private def checkCallableIdInRange (callableId : CallableIdV1) (callableCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless callableId.toNat < callableCount do
    return ← err .badReference
  pure ()

private def checkTypeShapeRefs (shape : TypeShapeV1) (typeCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  match shape with
  | .array element _length =>
      checkTypeIdInRange element typeCount
  | .map key value => do
      checkTypeIdInRange key typeCount
      checkTypeIdInRange value typeCount
  | .option element =>
      checkTypeIdInRange element typeCount
  | .struct fields =>
      for f in fields do
        checkTypeIdInRange f.typeId typeCount
  | .enum variants =>
      for v in variants do
        for t in v.payloadTypes do
          checkTypeIdInRange t typeCount
  | .bool | .uint _ | .int _ | .principal | .unit | .bytes _ | .field _ =>
      pure ()

/-- Integer widths allowed by SPEC-SEM-WIRE-001 §5. -/
private def legalIntegerWidthV1 (width : UInt16) : Bool :=
  width == 8 || width == 16 || width == 32 || width == 64 ||
  width == 128 || width == 256

private def checkUniqueIntraTypeNames (names : Array String) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Array String := #[]
  for name in names do
    if seen.any (· == name) then
      return ← err .duplicate
    seen := seen.push name
  pure ()

private def validateFieldSpecCatalogV1 (spec : FieldSpecV1) :
    Except SemanticWireErrorV1 Unit := do
  unless spec.id.value == bn254FrFieldIdV1 do
    return ← err .badType
  unless spec.modulusBE == bn254FrModulusBEV1 do
    return ← err .badType
  pure ()

/-- Map key legality (SPEC §5): Bool|UInt|Int|Principal|Bytes|Struct of legal keys.
    Recursion fuel defaults to `types.size`; fuel exhaustion / illegal leaf → `.badType`.
    Out-of-range TypeId is `.badReference` (shallow range still owns that class). -/
private def checkLegalMapKeyTypeV1 (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel : Nat) → Except SemanticWireErrorV1 Unit
  | 0 => err .badType
  | fuel + 1 => do
    match types[typeId.toNat]? with
    | none => err .badReference
    | some decl =>
      match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .bytes _ =>
          pure ()
      | .struct fields =>
          for f in fields do
            checkLegalMapKeyTypeV1 types f.typeId fuel
      | .option _ | .array _ _ | .map _ _ | .enum _ | .unit | .field _ =>
          err .badType

/-- Named rule: `name=some` iff shape is struct|enum (SPEC §5). -/
private def validateTypeDeclNamedRuleV1 (decl : TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  let isNamedShape :=
    match decl.shape with
    | .struct _ | .enum _ => true
    | _ => false
  match decl.name, isNamedShape with
  | some _, true => pure ()
  | none, false => pure ()
  | some _, false | none, true => err .badType

private def validateTypeDeclShapeV1 (decl : TypeDeclV1) (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  validateTypeDeclNamedRuleV1 decl
  match decl.shape with
  | .bool | .principal | .unit | .option _ =>
      pure ()
  | .uint width | .int width =>
      unless legalIntegerWidthV1 width do
        return ← err .badType
  | .bytes length =>
      unless length.toNat ≤ maxTypeLengthV1 do
        return ← err .badType
  | .array _ length =>
      unless length.toNat ≤ maxTypeLengthV1 do
        return ← err .badType
  | .field spec =>
      validateFieldSpecCatalogV1 spec
  | .struct fields =>
      if fields.isEmpty then
        return ← err .badType
      checkUniqueIntraTypeNames (fields.map (·.name))
  | .enum variants =>
      if variants.isEmpty then
        return ← err .badType
      checkUniqueIntraTypeNames (variants.map (·.name))
  | .map key _value =>
      checkLegalMapKeyTypeV1 types key types.size

private def validateTypesStructureV1 (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  for decl in types do
    validateTypeDeclShapeV1 decl types
  pure ()

private def isKnownRequirementDomain (domain : String) : Bool :=
  domain == "value" || domain == "control" || domain == "state" ||
  domain == "effect" || domain == "context" || domain == "disclosure" ||
  domain == "authority" || domain == "state-custody" || domain == "failure" ||
  domain == "extension"

/-- Mechanical RequirementId domain gate (CAP first segment ∈ closed set).
    Requires at least two nonempty dotted segments; unknown domain →
    `.badRequirement`. Full segment grammar remains formal CAP work. -/
private def validateRequirementIdDomain (id : String) :
    Except SemanticWireErrorV1 Unit := do
  if id.isEmpty then
    return ← err .badRequirement
  let parts := id.splitOn "."
  unless parts.length ≥ 2 do
    return ← err .badRequirement
  for part in parts do
    if part.isEmpty then
      return ← err .badRequirement
  let domain := parts[0]!
  unless isKnownRequirementDomain domain do
    return ← err .badRequirement
  pure ()

private def predicateNameV1 : RequirementPredicateV1 → String
  | .uintAtLeast name _ | .uintAtMost name _ | .boolEquals name _
  | .enumContains name _ | .digestEquals name _ => name

private def predicateRankV1 : RequirementPredicateV1 → Nat
  | .uintAtLeast _ _ => 0
  | .uintAtMost _ _ => 1
  | .boolEquals _ _ => 2
  | .enumContains _ _ => 3
  | .digestEquals _ _ => 4

private def validateEnumContainsValues (values : Array String) :
    Except SemanticWireErrorV1 Unit := do
  if values.size = 0 then
    return ← err .badRequirement
  for i in [:values.size] do
    mapCommon (requireNfc values[i]!)
    if i > 0 then
      match compareByteArrayLex values[i - 1]!.toUTF8 values[i]!.toUTF8 with
      | .lt => pure ()
      | .eq | .gt => return ← err .badRequirement
  pure ()

private def validateRequirementPredicateStructure (p : RequirementPredicateV1) :
    Except SemanticWireErrorV1 Unit := do
  match p with
  | .enumContains _ values => validateEnumContainsValues values
  | _ => pure ()

private def comparePredicateOrder (left right : RequirementPredicateV1) :
    Except SemanticWireErrorV1 Ordering := do
  let nameCmp :=
    compareByteArrayLex (predicateNameV1 left).toUTF8 (predicateNameV1 right).toUTF8
  if nameCmp != .eq then
    return nameCmp
  let rL := predicateRankV1 left
  let rR := predicateRankV1 right
  if rL < rR then return .lt
  if rL > rR then return .gt
  let wireL ← encodeRequirementPredicateV1 left
  let wireR ← encodeRequirementPredicateV1 right
  pure (compareByteArrayLex wireL wireR)

private def validatePredicatesSorted (predicates : Array RequirementPredicateV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut prev? : Option RequirementPredicateV1 := none
  for p in predicates do
    validateRequirementPredicateStructure p
    match prev? with
    | none => pure ()
    | some prev =>
      let cmp ← comparePredicateOrder prev p
      match cmp with
      | .lt => pure ()
      | .eq | .gt => return ← err .badRequirement
    prev? := some p
  pure ()

private def compareRequirementKey (left right : RequirementRequestV1) :
    Except SemanticWireErrorV1 Ordering := do
  let idCmp := compareByteArrayLex left.id.toUTF8 right.id.toUTF8
  if idCmp != .eq then
    return idCmp
  let verL ← mapCommon (renderSemVer left.version)
  let verR ← mapCommon (renderSemVer right.version)
  let verCmp := compareByteArrayLex verL.toUTF8 verR.toUTF8
  if verCmp != .eq then
    return verCmp
  mapCommon (validateDigest left.digest)
  mapCommon (validateDigest right.digest)
  pure (compareByteArrayLex left.digest.bytes right.digest.bytes)

private def validateProgramRequirementsStructure (reqs : ProgramRequirementsV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut prev? : Option RequirementRequestV1 := none
  for item in reqs.items do
    validateRequirementIdDomain item.id
    validatePredicatesSorted item.predicates
    match prev? with
    | none => pure ()
    | some prev =>
      let cmp ← compareRequirementKey prev item
      match cmp with
      | .lt => pure ()
      | .eq | .gt => return ← err .badRequirement
    prev? := some item
  pure ()

private def checkTableIds (getId : α → UInt32) (table : Array α) :
    Except SemanticWireErrorV1 Unit := do
  let mut i : Nat := 0
  for item in table do
    checkIdEqualsIndex (getId item) i
    i := i + 1
  pure ()

/-- Post-wire structural subset: table IDs, shallow declaration refs,
    type-shape/FieldSpec/Map-key (SPEC §5), requirement/predicate order
    (SPEC-SEM-WIRE-001 §4.5/§5/§6/§6.2 + CAP ranks).
    Empty tables and empty requirements remain legal. Does not walk CFG bodies. -/
def validateSemanticProgramStructureV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  -- 1) Table ID == array index
  checkTableIds (·.id) data.types
  checkTableIds (·.id) data.constants
  checkTableIds (·.id) data.logicalState
  checkTableIds (·.id) data.events
  checkTableIds (·.id) data.errors
  checkTableIds (·.id) data.callables
  checkTableIds (·.id) data.invariants
  -- 2) Shallow reference range on declaration records only
  let typeCount := data.types.size
  let callableCount := data.callables.size
  for t in data.types do
    checkTypeShapeRefs t.shape typeCount
  for c in data.constants do
    checkTypeIdInRange c.typeId typeCount
  for s in data.logicalState do
    checkTypeIdInRange s.typeId typeCount
  for e in data.events do
    for f in e.fields do
      checkTypeIdInRange f.typeId typeCount
  for e in data.errors do
    for f in e.fields do
      checkTypeIdInRange f.typeId typeCount
  for c in data.callables do
    for p in c.params do
      checkTypeIdInRange p.typeId typeCount
    checkTypeIdInRange c.result.typeId typeCount
  for inv in data.invariants do
    checkCallableIdInRange inv.callableId callableCount
  -- 3) Type-shape / FieldSpec catalog / Map-key legality (SPEC §5)
  validateTypesStructureV1 data.types
  -- 4) Requirement key + predicate order
  validateProgramRequirementsStructure data.requirements

def encodeSemanticProgramDataV1 (p : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 ByteArray := do
  checkTableSize p.types.size
  checkTableSize p.constants.size
  checkTableSize p.logicalState.size
  checkTableSize p.events.size
  checkTableSize p.errors.size
  checkTableSize p.callables.size
  checkTableSize p.invariants.size
  -- SPEC §6.2: encoder validates structure before emitting any program bytes.
  validateSemanticProgramStructureV1 p
  let qnB ← encodeQualifiedName p.qualifiedName
  let typesB ← encodeArray encodeTypeDeclV1 p.types
  let constantsB ← encodeArray encodeConstantV1 p.constants
  let stateB ← encodeArray encodeStateDeclV1 p.logicalState
  let eventsB ← encodeArray encodeEventDeclV1 p.events
  let errorsB ← encodeArray encodeErrorDeclV1 p.errors
  let callablesB ← encodeArray encodeCallableV1 p.callables
  let invariantsB ← encodeArray encodeInvariantDeclV1 p.invariants
  let reqB ← encodeProgramRequirementsV1 p.requirements
  let body ← encodeTagged "SemanticProgram.Data" #[
    qnB, typesB, constantsB, stateB, eventsB, errorsB, callablesB, invariantsB, reqB
  ]
  let out := (encodeMagicPrefix semanticProgramMagicV1).append body
  unless out.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  pure out

/-- Transport decode only: magic/tags/limits/nesting/trailing. No structure gate. -/
def decodeSemanticProgramDataV1 (bytes : ByteArray) :
    Except SemanticWireErrorV1 SemanticProgramDataV1 := do
  unless bytes.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  let c := start bytes
  let ((), c) ← consumeMagic semanticProgramMagicV1 c
  let (data, c) ← withTaggedNesting (fun c => do
    let ((), c) ← expectTag "SemanticProgram.Data" 9 c
    let (qualifiedName, c) ← decodeQualifiedName c
    let (types, c) ← decodeArray maxTableElements decodeTypeDeclV1 c
    let (constants, c) ← decodeArray maxTableElements decodeConstantV1 c
    let (logicalState, c) ← decodeArray maxTableElements decodeStateDeclV1 c
    let (events, c) ← decodeArray maxTableElements decodeEventDeclV1 c
    let (errors, c) ← decodeArray maxTableElements decodeErrorDeclV1 c
    let (callables, c) ← decodeArray maxTableElements decodeCallableV1 c
    let (invariants, c) ← decodeArray maxTableElements decodeInvariantDeclV1 c
    let (requirements, c) ← decodeProgramRequirementsV1 c
    pure ({
      qualifiedName, types, constants, logicalState, events, errors,
      callables, invariants, requirements
    }, c)
  ) c
  finish c
  pure data

/-- Carrier decode: transport decode → structure-gated re-encode → exact bytes.
    Structurally invalid programs fail on the re-encode path (structure error
    or `.nonCanonical`). This is **not** structure-free identity. -/
def decodeSemanticProgramV1 (bytes : ByteArray) :
    Except SemanticWireErrorV1 SemanticProgramV1 := do
  let data ← decodeSemanticProgramDataV1 bytes
  let reencoded ← encodeSemanticProgramDataV1 data
  unless reencoded == bytes do
    return ← err .nonCanonical
  pure ⟨bytes⟩

/-- Decode + re-encode identity + explicit structure gate. -/
def validateSemanticProgramV1 (p : SemanticProgramV1) :
    Except SemanticWireErrorV1 SemanticProgramDataV1 := do
  let data ← decodeSemanticProgramDataV1 p.canonicalBytes
  let reencoded ← encodeSemanticProgramDataV1 data
  unless reencoded == p.canonicalBytes do
    return ← err .nonCanonical
  -- encode already ran structure; pin the public contract explicitly.
  validateSemanticProgramStructureV1 data
  pure data

def semanticHashV1 (p : SemanticProgramV1) : Except SemanticWireErrorV1 Digest := do
  let _ ← validateSemanticProgramV1 p
  pure (sha256Bytes p.canonicalBytes)

def SemanticProgramV1.invariants (p : SemanticProgramV1) : Array InvariantDeclV1 :=
  match validateSemanticProgramV1 p with
  | .ok data => data.invariants
  | .error _ => #[]

/-- Encode the provenance companion **envelope only** (magic + SemanticProvenance.Data).

    Does **not** join source module/identity, Source.ProgramV1, or
    SourceNodeInventoryV1. Envelope transport stub — not formal provenance
    acceptance. -/
def encodeSemanticProvenanceV1 (p : SemanticProvenanceV1) :
    Except SemanticWireErrorV1 ByteArray := do
  unless p.originMap.size ≤ maxOriginBindings do
    return ← err .limitExceeded
  let schemaB ← encodeSchemaId p.schema
  let qnB ← encodeQualifiedName p.qualifiedName
  let srcB ← encodeDigest p.sourceHash
  let semB ← encodeDigest p.semanticHash
  let mapB ← encodeArray encodeOriginBindingV1 p.originMap
  let body ← encodeTagged "SemanticProvenance.Data" #[schemaB, qnB, srcB, semB, mapB]
  let out := (encodeMagicPrefix semanticProvenanceMagicV1).append body
  unless out.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  pure out

/-- Provenance envelope transport decode + re-encode identity. No inventory join. -/
def decodeSemanticProvenanceV1 (bytes : ByteArray) :
    Except SemanticWireErrorV1 SemanticProvenanceV1 := do
  unless bytes.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  let c := start bytes
  let ((), c) ← consumeMagic semanticProvenanceMagicV1 c
  let (data, c) ← withTaggedNesting (fun c => do
    let ((), c) ← expectTag "SemanticProvenance.Data" 5 c
    let (schema, c) ← decodeSchemaId c
    let (qualifiedName, c) ← decodeQualifiedName c
    let (sourceHash, c) ← decodeDigest c
    let (semanticHash, c) ← decodeDigest c
    let (originMap, c) ← decodeArray maxOriginBindings decodeOriginBindingV1 c
    pure ({ schema, qualifiedName, sourceHash, semanticHash, originMap }, c)
  ) c
  finish c
  let reencoded ← encodeSemanticProvenanceV1 data
  unless reencoded == bytes do
    return ← err .nonCanonical
  pure data

/-- Envelope-only digest stub: SHA-256 of encode/decode-roundtripped envelope bytes.
    **Not** formal provenance acceptance — does not run source/NodeId inventory join. -/
def semanticProvenanceDigestV1 (p : SemanticProvenanceV1) :
    Except SemanticWireErrorV1 Digest := do
  let bytes ← encodeSemanticProvenanceV1 p
  let _ ← decodeSemanticProvenanceV1 bytes
  pure (sha256Bytes bytes)

/-- Fail-closed join stub for this engineering slice. Always `.badProvenance`.
    Full source/NodeId inventory join remains unimplemented (formal pending). -/
def validateSemanticProvenanceV1
    (_sourceModule : QualifiedName)
    (_sourceIdentity : QualifiedName)
    (_nodeInventory : SourceNodeInventoryV1)
    (_program : SemanticProgramV1)
    (_provenance : SemanticProvenanceV1) : Except SemanticWireErrorV1 Unit :=
  err .badProvenance

end ProofForgeV2.Semantic.WireV1
