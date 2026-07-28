import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode

/-!
  ProofForgeV2.Semantic.WireV1 — closed SemanticProgramV1 model + root wire codec
  (SPEC-SEM-WIRE-001 engineering subset: D2-06 wire + structural tables/reqs +
  canonical valueBytes).

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
    Recursive **valueBytes** shapes (Array/Map/Option/Struct/Enum) also use
    fuel capped at `maxNesting` (fail closed with `.limitExceeded`).
  * Structural subset (SPEC §4.5 / §5 / §6 / §6.2 + CAP SupportPredicate rank):
    - program root `qualifiedName` has at least two components (`.badScalar`)
    - table `decl.id == array index` (`.duplicate` on mismatch)
    - shallow declaration-record TypeId / CallableId range (`.badReference`)
    - type-shape / FieldSpec / Map-key (SPEC §5), after shallow refs:
        · `name=some` iff shape is `.struct`/`.enum`; other shapes
          require `name=none` (`.badType`)
        · struct fields / enum variants nonempty (`.badType`)
        · integer widths ∈ {8,16,32,64,128,256} (`.badType`)
        · Bytes/Array length ≤ 4096 (`.badType`)
        · FieldSpec catalog: only `proof-forge.field.bn254-fr.v1` with
          exact 32-byte modulusBE (`bn254FrFieldSpecV1`; `.badType`)
        · unique struct field / enum variant names within one decl and unique
          exact names across named Struct/Enum TypeDecls (`.duplicate`)
        · Map key legality: Bool|UInt|Int|Principal|Bytes|Struct of
          recursively legal keys; reject Option/Array/Map/Enum/Unit/Field
          (`.badType`; recursion fuel = types.size)
    - canonical `valueBytes` (SPEC §5), after type-shape and before
      requirements: Constant / Op.Literal / SwitchCase reuse one type-driven
      decoder; full-consume + encode(decode)==bytes else `.nonCanonical`
      (OOR TypeId → `.badReference`; nesting/size limits → `.limitExceeded`)
    - declaration/signature name subset after canonical values and before CFG:
      exact Constant-name uniqueness within constants, exact StateDecl-name
      uniqueness within logicalState, exact EventDecl/ErrorDecl-name uniqueness
      within events/errors, per-event/per-error exact interface-field-name
      uniqueness, callable
      kind/name Option presence, exact named-callable uniqueness,
      per-callable exact parameter-name uniqueness, zero-or-one initializer,
      initializer result
      resolving to Unit/public, invariant root with zero parameters,
      `loopBounds=[]`, and a result resolving to Bool/public,
      `invariantSteps=none` for initializer/entry/view and for every pureFn
      when no invariant root exists, `invariantSteps=some` presence for every
      invariant root, plus exact source-order InvariantDecl callableId/kind/name
      join (`.badCfg`)
    - post-CFG transitive `Op.PureCall` reachability requires
      `invariantSteps=some` exactly for pureFns in an invariant closure and
      `none` for every other pureFn; the reachable closure call graph must be a
      DAG (bounded Kahn traversal; unreachable cycles remain out of scope), and
      every closure-member CFG must contain no back edge (`.badCfg`)
    - post-CFG invariant roots reject direct `Op.StateStore`, `Op.ContextRead`,
      `Op.Commit`, `Op.Emit`, `Op.ExternalCall`, and `Op.Schedule` while
      retaining direct `Op.StateLoad` (`.badCfg`)
    - post-CFG every present `invariantSteps ≤ maxInvariantStepsV1` (10M),
      before requirements (`.badCfg`)
    - requirement key order/uniqueness, RequirementId domain segment,
      predicate name+rank+wire order, `enumContains` nonempty unique ascending
      (`.badRequirement`)
  * API contracts (structure vs transport):
    - `decodeSemanticProgramDataV1`: transport/scalar only (magic, tags,
      limits/nesting, trailing). **No** structure gate (garbage valueBytes
      accepted on transport).
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
  * Not yet: full TypeKey
    anonymous ranking/interning, remaining invariant-closure pureFn op
    allowlist/exact checked step computation, provenance inventory
    join, ProgramV1 normalizer, product
    CheckV1/compile/CLI wiring, op type contracts beyond
    the §5.1 value-producing subset. (CFG shape + reachability from entry,
    jump/branch/switch target arg arity == target block params, loopBounds
    back-edge coverage, per-callable EffectId contiguous canonical assignment,
    ValueId SSA definition-table / exactly-once /
    use-existence, dominance-of-use, def-site TypeId range, terminator
    typing, the per-op §4.3/§5.1 type/result contract for value-producing ops
    (incl. exact result presence for Literal/Constant/StateLoad/Construct/
    FieldGet/IndexGet/Unary/Binary/PureCall, the full Op.FieldSet
    contract — base Struct, fieldIndex in range, type(value) == field.typeId,
    result.typeId == type(base), the full Op.VariantTag contract — base
    Enum/Option, result.typeId == unique UInt32 TypeId — and the static
    Op.VariantPayload Enum/Option index/result contract, Op.IndexSet
    Array/Bytes/Map operand/result contract, Op.CheckedCast UInt/Int
    source/destination/result contract, Op.StateStore state lookup/value
    type/void-result contract, and Op.Assert Bool/error/args/void-result
    contract), the Term.Revert ErrorDecl/args exact join, the Op.Emit EventDecl/
    args/void-result contract, presence-only result for ContextRead/Commit,
    and void-op result-presence plus the at-least-two-component callee shape
    for ExternalCall/Schedule are now covered; ExternalCall/Schedule argument
    serializability, exact contracts for the two presence-only families,
    TypeKey anonymous
    ranking, provenance inventory join, ProgramV1 normalizer, and product
    wire remain out of scope pending later slices.)
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
/-- SPEC §6 loopBounds `maxIterations` upper bound (per-loop iteration cap). -/
def maxLoopIterationsV1 : UInt32 := 4096
/-- SPEC §8 intrinsic invariant interpreter fuel ceiling. -/
def maxInvariantStepsV1 : UInt64 := 10000000
/-- SPEC §3 canonical valueBytes size upper bound (16 MiB). -/
def maxCanonicalValueBytes : Nat := 16 * 1024 * 1024
/-- SPEC §3 Map entry count upper bound (same as array elements). -/
def maxMapEntriesV1 : Nat := maxArrayElements

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

/-! ### Structural validation subset
    (tables / shallow refs / type-shape / valueBytes / requirements)

    Encode-before-output, `validateSemanticProgramV1`, and the re-encode leg of
    `decodeSemanticProgramV1` require this subset. `decodeSemanticProgramDataV1`
    does not (transport only). See module header API contracts.

    Stable order (SPEC §6.2 engineering subset): table id/index → shallow
    declaration refs → type-shape/FieldSpec/Map-key → named TypeDecl-name
    uniqueness → canonical valueBytes (Constant / Op.Literal / SwitchCase) →
    grouped same-error duplicate phase
    {Constant-name, logicalState-name, EventDecl/ErrorDecl-name,
    per-declaration interface-field-name uniqueness} → callable kind/name
    presence → named
    callable uniqueness → per-callable parameter-name uniqueness →
    initializer cardinality → initializer Unit/public result → invariant
    Bool/public result → invariant zero parameters → invariant empty loopBounds
    → InvariantDecl exact join → CFG → requirements.
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

/-- Switch case constants are unique as `(typeId,valueBytes)` within one
    terminator (SPEC §6). Canonical valueBytes have already been validated by
    the phase-4 callable walk before CFG validation. Sort private typed keys
    and compare adjacent entries, avoiding a quadratic scan while preserving
    source case order in the public model. Target block/args are deliberately
    absent from the key: they cannot disambiguate the same case constant. -/
private def validateSwitchCaseValuesUnique (cases : Array SwitchCaseV1) :
    Except SemanticWireErrorV1 Unit := do
  let keys := cases.map fun sc => (encodeU32le sc.typeId).append sc.valueBytes
  let sorted := keys.qsort fun left right => compareByteArrayLex left right == .lt
  let mut i : Nat := 1
  while i < sorted.size do
    if compareByteArrayLex sorted[i - 1]! sorted[i]! == .eq then
      return ← err .badCfg
    i := i + 1
  pure ()

private def checkIdEqualsIndex (id : UInt32) (index : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless id.toNat == index do
    return ← err .duplicate
  pure ()

/-! ### CFG shape + reachability + block-param arity + loopBounds + EffectId + ValueId SSA def-table + dominance-of-use (SPEC §6.2 — CFG layers)

    Per-callable: entryBlock == 0, block id == array index, Switch cases
    nonempty with unique typed canonical constants, terminator target range,
    jump/branch/switch target arg arity ==
    target block params, total reachability from entry, loopBounds back-edge
    coverage, contiguous EffectId
    assignment, ValueId definition-table / exactly-once / use-existence, and
    dominance-of-use.
    All CFG-shape failures use `.badCfg`. NOT block-param TYPE,
    or terminator typing (separate later slices). Reachability is total and
    non-recursive (worklist) to stay within nesting/stack limits. -/

private def checkBlockIdInRange (blockId : BlockIdV1) (blockCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless blockId.toNat < blockCount do
    return ← err .badCfg
  pure ()

/-- Check a single JumpTargetV1's arg arity == target block's params size.
    Only runs when the target blockId is in range — the existing terminator
    target range pass (step c) owns out-of-range reporting, so this helper
    stays silent on OOR to avoid double-reporting. Arity mismatch → `.badCfg`.
    Arg ValueId→type resolution is out of scope (needs block-param TYPE from
    a later slice; ValueId use-existence is now owned by step f). -/
private def checkJumpTargetArity (blocks : Array BlockV1) (blockCount : Nat)
    (target : JumpTargetV1) : Except SemanticWireErrorV1 Unit := do
  let bid := target.blockId.toNat
  if bid < blockCount then
    match blocks[bid]? with
    | some blk =>
        unless target.args.size == blk.params.size do
          return ← err .badCfg
    | none => pure ()
  pure ()

/-- Successor blockIds of a terminator (leaf terminators return empty). -/
private def terminatorSuccessors (term : TerminatorV1) : Array BlockIdV1 :=
  match term with
  | .jump target => #[target.blockId]
  | .branch _cond thenTarget elseTarget =>
      #[thenTarget.blockId, elseTarget.blockId]
  | .switch _scrut cases defaultTarget =>
      let fromCases := cases.map (·.target.blockId)
      match defaultTarget with
      | some t => fromCases.push t.blockId
      | none => fromCases
  | .return_ _ | .revert _ _ | .trap _ => #[]

/-- All JumpTargetV1s carried by a terminator (for arg-arity checks).
    Leaf terminators return empty. -/
private def terminatorJumpTargets (term : TerminatorV1) :
    Array JumpTargetV1 :=
  match term with
  | .jump target => #[target]
  | .branch _cond thenTarget elseTarget => #[thenTarget, elseTarget]
  | .switch _scrut cases defaultTarget =>
      let fromCases := cases.map (·.target)
      match defaultTarget with
      | some t => fromCases.push t
      | none => fromCases
  | .return_ _ | .revert _ _ | .trap _ => #[]

/-- CFG back edges as `(header, backEdgeFrom)` pairs (SPEC §6). SPEC assigns
    block IDs via preorder DFS from entry, so an edge `i -> s` is a back edge
    iff `s.toNat <= i`. We do not need a separate DFS/dominance pass — ID order
    already encodes preorder. Each distinct `(header, backEdgeFrom)` pair is
    reported once per occurrence; callers dedup by pair. Bounded,
    non-recursive. Only in-range successors are considered (out-of-range
    targets are owned by the terminator target range pass). -/
private def cfgBackEdges (blocks : Array BlockV1) (blockCount : Nat) :
    Array (BlockIdV1 × BlockIdV1) := Id.run do
  let mut acc : Array (BlockIdV1 × BlockIdV1) := #[]
  let mut i : Nat := 0
  for b in blocks do
    for succ in terminatorSuccessors (BlockV1.terminator b) do
      let s := succ.toNat
      if s < blockCount && s <= i then
        acc := acc.push (succ, UInt32.ofNat i)
    i := i + 1
  pure acc

/-- One fixed-point pass: for each visited block, mark its successors visited.
    Returns the updated visited array. -/
private def cfgReachPass (blocks : Array BlockV1) (blockCount : Nat)
    (visited : Array Bool) : Array Bool := Id.run do
  let mut v : Array Bool := visited
  let mut i : Nat := 0
  for b in blocks do
    if v[i]! then
      for succ in terminatorSuccessors (BlockV1.terminator b) do
        let s := succ.toNat
        if s < blockCount && v[s]? == some false then
          v := v.set! s true
    i := i + 1
  pure v

/-- Reachability fixed point: repeat passes until no change or blockCount
    passes (blockCount passes suffice for a finite graph). Bounded, no
    unbounded recursion or worklist dequeue. -/
private def cfgReachFixpoint (blocks : Array BlockV1) (blockCount : Nat)
    : (fuel : Nat) → (visited : Array Bool) → Array Bool
  | 0, visited => visited
  | fuel + 1, visited =>
    let next := cfgReachPass blocks blockCount visited
    if next == visited then next
    else cfgReachFixpoint blocks blockCount fuel next

/-- Per-callable loopBounds back-edge coverage (SPEC §6 / §6.2). Validates:
    a) each loopBound header/backEdgeFrom < blockCount (range owned here, not
       `.badReference`, because these are CFG-internal),
    b) maxIterations <= maxLoopIterationsV1 (4096),
    c) loopBounds strictly ascending and unique by (header, backEdgeFrom)
       lexicographic order,
    d) exact coverage: the multiset of (header, backEdgeFrom) pairs in
       loopBounds equals the multiset of actual CFG back edges (computed by
       `cfgBackEdges`), with duplicate actual edges to the same (header,
       backEdgeFrom) treated as a single back edge (SPEC says each pair is
       unique ascending). All failures → `.badCfg`. Bounded, total. -/
private def validateCallableLoopBounds (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  -- a) range check on header / backEdgeFrom
  for lb in c.loopBounds do
    unless lb.header.toNat < blockCount do
      return ← err .badCfg
    unless lb.backEdgeFrom.toNat < blockCount do
      return ← err .badCfg
  -- b) maxIterations <= 4096
  for lb in c.loopBounds do
    unless lb.maxIterations <= maxLoopIterationsV1 do
      return ← err .badCfg
  -- c) strictly ascending + unique by (header, backEdgeFrom) lexicographic.
  --   Compare adjacent pairs by (header, backEdgeFrom) lexicographic order;
  --   equal or out-of-order → `.badCfg`.
  let mut i : Nat := 0
  for lb in c.loopBounds do
    if i + 1 < c.loopBounds.size then
      match c.loopBounds[i + 1]? with
      | some next =>
          let ch := lb.header.toNat
          let cb := lb.backEdgeFrom.toNat
          let nh := next.header.toNat
          let nb := next.backEdgeFrom.toNat
          let ok := ch < nh || (ch == nh && cb < nb)
          unless ok do
            return ← err .badCfg
      | none => pure ()
    i := i + 1
  -- d) exact coverage. Build deduped actual back-edge pair list, then compare
  --   sizes and membership (blockCount is small; bounded Array membership).
  let actualAll := cfgBackEdges c.blocks blockCount
  let mut actual : Array (Nat × Nat) := #[]
  for p in actualAll do
    let key := (p.1.toNat, p.2.toNat)
    unless actual.any (· == key) do
      actual := actual.push key
  unless actual.size == c.loopBounds.size do
    return ← err .badCfg
  for lb in c.loopBounds do
    let key := (lb.header.toNat, lb.backEdgeFrom.toNat)
    unless actual.any (· == key) do
      return ← err .badCfg
  pure ()

/-! ### EffectId canonical assignment (SPEC §6 — CFG layer e.5)

    Within each callable, Emit/ExternalCall/Schedule instructions receive
    contiguous EffectIds 0..n-1 in BlockId/instruction order. Block IDs have
    already been checked against array index, so nested array traversal is the
    exact canonical order. IDs reset per callable. Any gap, duplicate, wrong
    start, or reordering fails `.badCfg`. Bounded, non-recursive, total. -/
private def validateCallableEffectIds (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut next : Nat := 0
  for b in c.blocks do
    for instr in b.instructions do
      let effectId? : Option EffectIdV1 :=
        match instr.op with
        | .emit effectId _ _ => some effectId
        | .externalCall effectId _ _ => some effectId
        | .schedule effectId _ _ => some effectId
        | _ => none
      match effectId? with
      | none => pure ()
      | some effectId =>
          unless effectId.toNat == next do return ← err .badCfg
          next := next + 1
  pure ()

/-! ### ValueId SSA definition-table + dominance-of-use (SPEC §6.2)

    Implements the 'each ValueId is defined exactly once' portion plus
    use-existence (every used ValueId has a def site) plus dominance-of-use
    (every use is in a block dominated by its def's block). All SSA-def-table
    and dominance failures use `.badCfg`. Bounded, non-recursive, total. -/

/-- Collect every ValueId definition site in source order: callable params
    (defBlockId := entryBlock, i.e. 0), then per block in `c.blocks`: block
    params (defBlockId := block.id), then each instruction with
    `result := some vdef` (defBlockId := block.id). Returns `(valueId, blockId)`
    pairs in source order. Bounded, non-recursive. -/
def collectValueDefSites (c : CallableV1) : Array (ValueIdV1 × BlockIdV1) :=
  Id.run do
    let mut sites : Array (ValueIdV1 × BlockIdV1) := #[]
    -- callable params: defined at entry block (SPEC §6.2 param order first).
    let entryBlock := c.entryBlock
    for p in c.params do
      sites := sites.push (p.valueId, entryBlock)
    -- block params + instruction results, in block array order.
    for b in c.blocks do
      for bp in b.params do
        sites := sites.push (bp.valueId, b.id)
      for instr in b.instructions do
        match instr.result with
        | some vdef => sites := sites.push (vdef.valueId, b.id)
        | none => pure ()
    pure sites

/-- Check that every ValueId is defined exactly once across the supplied def
    sites (callable params + block params + instruction results, as produced
    by `collectValueDefSites`). Duplicate → `.badCfg`. Uses a bounded Array
    membership scan; callable value count is bounded by maxArrayElements per
    block and maxTableElements callables. Accepting a precomputed sites array
    lets the caller build the def table once and reuse it for both
    exactly-once and use-existence checks. -/
def checkValueIdDefUniqueness (defSites : Array (ValueIdV1 × BlockIdV1)) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Array ValueIdV1 := #[]
  for (vid, _) in defSites do
    if seen.any (· == vid) then
      return ← err .badCfg
    seen := seen.push vid
  pure ()

/-- Every ValueId referenced by a `SemanticOpV1` (uses only; defs are owned by
    `collectValueDefSites`). Bounded, total. -/
def opValueUses (op : SemanticOpV1) : Array ValueIdV1 :=
  match op with
  | .literal _ _ | .constant _ | .stateLoad _ | .contextRead _ => #[]
  | .stateStore _ v => #[v]
  | .construct _ _ args => args
  | .fieldGet base _ => #[base]
  | .fieldSet base _ value => #[base, value]
  | .variantTag base => #[base]
  | .variantPayload base _ _ => #[base]
  | .indexGet base index => #[base, index]
  | .indexSet base index value => #[base, index, value]
  | .checkedCast value _ => #[value]
  | .unary _ operand => #[operand]
  | .binary _ lhs rhs => #[lhs, rhs]
  | .pureCall _ args => args
  | .commit value => #[value]
  | .assert_ cond _ args => #[cond] ++ args
  | .emit _ _ args => args
  | .externalCall _ _ args => args
  | .schedule _ _ args => args

/-- Every ValueId referenced by a `TerminatorV1` (condition / scrutinee /
    return / revert args / jump-target args). Leaf `trap` returns empty.
    Bounded, total. -/
def terminatorValueUses (term : TerminatorV1) : Array ValueIdV1 :=
  match term with
  | .jump target => target.args
  | .branch cond thenTarget elseTarget =>
      #[cond] ++ thenTarget.args ++ elseTarget.args
  | .switch scrut cases default =>
      let caseArgs := cases.flatMap (·.target.args)
      let defArgs := match default with
        | some t => t.args
        | none => #[]
      #[scrut] ++ caseArgs ++ defArgs
  | .return_ (some v) => #[v]
  | .return_ none => #[]
  | .revert _ args => args
  | .trap _ => #[]

/-- Check that every ValueId use (in ops and terminators) has a corresponding
    def site. Missing def → `.badCfg`. Bounded, total. -/
def checkValueIdUsesExist (c : CallableV1)
    (defSites : Array (ValueIdV1 × BlockIdV1)) :
    Except SemanticWireErrorV1 Unit := do
  let defIds : Array ValueIdV1 := defSites.map (·.1)
  let isDef (vid : ValueIdV1) : Bool := defIds.any (· == vid)
  for b in c.blocks do
    for instr in b.instructions do
      for use in opValueUses instr.op do
        unless isDef use do
          return ← err .badCfg
    for use in terminatorValueUses b.terminator do
      unless isDef use do
        return ← err .badCfg
  pure ()

/-- Per-callable ValueId SSA def-table: exactly-once def + use-existence.
    Builds `defSites` once via `collectValueDefSites`, runs
    `checkValueIdDefUniqueness` on it, then runs `checkValueIdUsesExist` with
    the same array. Dominance-of-use is owned by `validateCallableDominanceOfUse`
    (step g in `validateCallableCfgShape`); this helper keeps the def-table-only
    contract for callers that do not yet need dominance. -/
def validateCallableValueIdSsa (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let defSites := collectValueDefSites c
  checkValueIdDefUniqueness defSites
  checkValueIdUsesExist c defSites

/-! ### Dominance-of-use (SPEC §6.2 — CFG layer g)

    A block D dominates block B iff every path from entry (block 0) to B
    passes through D. After step f (ValueId SSA def-table: exactly-once +
    use-existence), enforce that every ValueId USE is in a block dominated by
    the def's block. Failure → `.badCfg`. Bounded, non-recursive, total. -/

/-- For each block id b in [0, blockCount), the sorted-ascending unique list of
    predecessor block ids whose terminator lists b as an in-range successor
    (uses `terminatorSuccessors`). Bounded, non-recursive. -/
private def cfgPredecessors (blocks : Array BlockV1) (blockCount : Nat) :
    Array (Array Nat) := Id.run do
  let mut preds : Array (Array Nat) := Array.mk (List.replicate blockCount #[])
  let mut i : Nat := 0
  for b in blocks do
    for succ in terminatorSuccessors (BlockV1.terminator b) do
      let s := succ.toNat
      if s < blockCount then
        match preds[s]? with
        | some ps =>
            -- dedup + keep ascending (i is monotonically increasing, so a
            -- fresh predecessor is always larger than any already recorded;
            -- a single linear scan preserves uniqueness + ordering).
            unless ps.any (· == i) do
              preds := preds.set! s (ps.push i)
        | none => pure ()
    i := i + 1
  pure preds

/-- Iterative dataflow dominator computation. `dom[0] = {0}` if `reachable[0]`.
    For reachable b != 0: `dom[b]` initialized to all-true, then fixed-point
    `dom[b] = {b} ∪ (∩ over reachable preds p of dom[p])`. For unreachable b:
    `dom[b] = all-false`. Iterates up to `blockCount+1` passes or until stable.
    Bounded, non-recursive. -/
private def computeDominators (blocks : Array BlockV1) (blockCount : Nat)
    (reachable : Array Bool) : Array (Array Bool) := Id.run do
  if blockCount == 0 then pure #[] else do
    let preds := cfgPredecessors blocks blockCount
    -- Initial dominator sets (each row is full blockCount-sized for uniform
    -- indexing in the fixed-point intersection).
    let allTrue : Array Bool := Array.mk (List.replicate blockCount true)
    let allFalse : Array Bool := Array.mk (List.replicate blockCount false)
    let entryDom : Array Bool := allFalse.set! 0 true
    let mut dom : Array (Array Bool) := Array.empty
    let mut j : Nat := 0
    for _ in [:blockCount] do
      if j == 0 then
        dom := dom.push (if reachable[0]! then entryDom else allFalse)
      else if reachable[j]! then
        dom := dom.push allTrue
      else
        dom := dom.push allFalse
      j := j + 1
    -- Fixed-point: at most blockCount+1 passes suffice for a finite graph.
    let mut fuel : Nat := blockCount + 1
    let mut stable : Bool := false
    while !stable && fuel > 0 do
      fuel := fuel - 1
      stable := true
      let mut b : Nat := 0
      while b < blockCount do
        if b == 0 then
          b := b + 1
        else if !reachable[b]! then
          b := b + 1
        else
          -- dom[b] := {b} ∪ (∩ over reachable preds p of dom[p])
          match preds[b]? with
          | some ps =>
              if ps.size == 0 then
                -- Reachable but no predecessors: only the entry can be so, and
                -- entry is handled above. Treat as no dominator info beyond
                -- self; keep all-false except self to force a use here to fail
                -- dominance (consistent with reachability already pinning
                -- entry==0). Set dom[b] = {b} only.
                let selfOnly := allFalse.set! b true
                unless dom[b]! == selfOnly do
                  dom := dom.set! b selfOnly
                  stable := false
              else
                let mut inter : Array Bool := allTrue
                for p in ps do
                  if reachable[p]! then
                    let dp := dom[p]!
                    let mut k : Nat := 0
                    let mut acc : Array Bool := Array.empty
                    for _ in [:blockCount] do
                      acc := acc.push (inter[k]! && dp[k]!)
                      k := k + 1
                    inter := acc
                let selfInter := inter.set! b true
                unless dom[b]! == selfInter do
                  dom := dom.set! b selfInter
                  stable := false
          | none => pure ()
          b := b + 1
    pure dom

/-- Check that every ValueId use (op uses + terminator uses) in each reachable
    block B is dominated by its def's block D. `defSites` is already
    exactly-once (step f), so a ValueId maps to a single def block. Missing
    def site is step f's responsibility (already caught); to stay total, treat
    a missing def as `.badCfg`. Requires `dom[B][D.toNat] == true` else
    `.badCfg`. Unreachable blocks are skipped (step d owns those). -/
private def checkDominanceOfUse (c : CallableV1)
    (defSites : Array (ValueIdV1 × BlockIdV1))
    (dom : Array (Array Bool)) (reachable : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  -- Bounded ValueId→defBlockId lookup (defSites is exactly-once by step f).
  let defBlock (vid : ValueIdV1) : Option BlockIdV1 := Id.run do
    let mut r : Option BlockIdV1 := none
    for (v, b) in defSites do
      if v == vid then
        r := some b
        break
    pure r
  let mut b : Nat := 0
  for blk in c.blocks do
    if reachable[b]! then
      -- op uses
      for instr in blk.instructions do
        for use in opValueUses instr.op do
          match defBlock use with
          | none => return ← err .badCfg
          | some d =>
              let dn := d.toNat
              unless dn < blockCount do
                return ← err .badCfg
              match dom[b]? with
              | some row =>
                  unless row[dn]! do
                    return ← err .badCfg
              | none => return ← err .badCfg
      -- terminator uses
      for use in terminatorValueUses blk.terminator do
        match defBlock use with
        | none => return ← err .badCfg
        | some d =>
            let dn := d.toNat
            unless dn < blockCount do
              return ← err .badCfg
            match dom[b]? with
            | some row =>
                unless row[dn]! do
                  return ← err .badCfg
            | none => return ← err .badCfg
    b := b + 1
  pure ()

/-- Per-callable dominance-of-use: compute predecessors + dominators from the
    reachability array (already produced by step d), then check every use is
    dominated by its def's block. Failure → `.badCfg`. -/
def validateCallableDominanceOfUse (c : CallableV1)
    (defSites : Array (ValueIdV1 × BlockIdV1)) (reachable : Array Bool) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  let dom := computeDominators c.blocks blockCount reachable
  checkDominanceOfUse c defSites dom reachable

private def checkTypeIdInRange (typeId : TypeIdV1) (typeCount : Nat) :
    Except SemanticWireErrorV1 Unit := do
  unless typeId.toNat < typeCount do
    return ← err .badReference
  pure ()

/-! ### Def-site TypeId range + terminator typing (SPEC §6.2 — CFG layers h/i)

    Step h: every block-param TypeId and every instruction-result ValueDef
    TypeId is in `[0, types.size)`. Callable `ParameterV1.typeId` and
    `CallableResultV1.typeId` are already checked at step 2 of
    `validateSemanticProgramStructureV1`; do NOT duplicate. Failure →
    `.badReference` (same as `checkTypeIdInRange`).

    Step i: terminator typing against a ValueId→TypeId table built from def
    sites. Branch condition must be the Bool TypeId; switch case TypeId must
    equal the scrutinee's TypeId; jump/branch/switch target args must match
    the target block params positionally; `return_ (some v)` must match the
    callable result TypeId. `Term.Revert` errorId must resolve and args must
    positionally match ErrorDecl fields. `return_ none` / `trap` need no
    additional type check. All step i failures → `.badCfg`. Bounded,
    non-recursive, total. Emit/externalCall/schedule declaration joins,
    TypeKey anonymous ranking, and provenance join remain out of scope. -/

/-- Collect every ValueId → TypeId definition in source order: callable params
    (p.valueId, p.typeId), then per block: block params (bp.valueId,
    bp.typeId), then instruction results (vdef.valueId, vdef.typeId). Source
    order, bounded, non-recursive. Reuses the step-f exactly-once guarantee;
    does NOT re-run uniqueness. -/
def collectValueTypeDefs (c : CallableV1) : Array (ValueIdV1 × TypeIdV1) :=
  Id.run do
    let mut defs : Array (ValueIdV1 × TypeIdV1) := #[]
    for p in c.params do
      defs := defs.push (p.valueId, p.typeId)
    for b in c.blocks do
      for bp in b.params do
        defs := defs.push (bp.valueId, bp.typeId)
      for instr in b.instructions do
        match instr.result with
        | some vdef => defs := defs.push (vdef.valueId, vdef.typeId)
        | none => pure ()
    pure defs

/-- First TypeId whose shape is `.bool`, if any. Bounded, non-recursive. -/
def boolTypeId (types : Array TypeDeclV1) : Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  let mut i : Nat := 0
  for t in types do
    if r.isNone then
      match t.shape with
      | .bool => r := some (UInt32.ofNat i)
      | _ => pure ()
    i := i + 1
  pure r

/-- Step h: every def-site TypeId (block params + instruction results) is in
    `[0, typeCount)`. Callable param/result TypeIds are already checked at
    step 2; do NOT duplicate. Failure → `.badReference`. -/
def checkDefSiteTypeIdsInRange (defTypes : Array (ValueIdV1 × TypeIdV1))
    (typeCount : Nat) : Except SemanticWireErrorV1 Unit := do
  for (_, tid) in defTypes do
    checkTypeIdInRange tid typeCount

/-- Step i: terminator typing against a ValueId→TypeId table built from def
    sites plus the ErrorDecl table for Term.Revert. Bounded lookup of
    `typeOf vid`; missing def → `.badCfg` (step f owns existence, but we stay
    total). All failures → `.badCfg`. -/
def checkTerminatorTyping (c : CallableV1)
    (defTypes : Array (ValueIdV1 × TypeIdV1)) (types : Array TypeDeclV1)
    (errors : Array ErrorDeclV1) : Except SemanticWireErrorV1 Unit := do
  let boolT := boolTypeId types
  -- Bounded ValueId→TypeId lookup (defTypes is exactly-once by step f).
  let typeOf (vid : ValueIdV1) : Option TypeIdV1 := Id.run do
    let mut r : Option TypeIdV1 := none
    for (v, t) in defTypes do
      if v == vid then
        r := some t
        break
    pure r
  -- Block params of block id `bid`, if in range (step c owns OOR).
  let blockParams (bid : BlockIdV1) : Array BlockParameterV1 := Id.run do
    let mut r : Array BlockParameterV1 := #[]
    let n := bid.toNat
    if n < c.blocks.size then
      match c.blocks[n]? with
      | some b => r := b.params
      | none => pure ()
    pure r
  -- Positional arg-type check against target block params (min-length guard
  -- to stay total; arity is owned by step c.5).
  let checkTargetArgs (target : JumpTargetV1) :
      Except SemanticWireErrorV1 Unit := do
    let params := blockParams target.blockId
    let n := min target.args.size params.size
    let mut i : Nat := 0
    while i < n do
      match typeOf target.args[i]! with
      | none => return ← err .badCfg
      | some argT =>
          match params[i]? with
          | none => return ← err .badCfg
          | some bp =>
              unless argT == bp.typeId do
                return ← err .badCfg
      i := i + 1
    pure ()
  -- Exact declared-error join for Term.Revert: errorId must resolve and args
  -- must match ErrorDecl fields positionally by TypeId.
  let checkErrorArgs (errorId : ErrorIdV1) (args : Array ValueIdV1) :
      Except SemanticWireErrorV1 Unit := do
    match errors[errorId.toNat]? with
    | none => err .badCfg
    | some errorDecl =>
        unless args.size == errorDecl.fields.size do
          return ← err .badCfg
        let mut i : Nat := 0
        while i < args.size do
          match typeOf args[i]! with
          | none => return ← err .badCfg
          | some argT =>
              match errorDecl.fields[i]? with
              | none => return ← err .badCfg
              | some field =>
                  unless argT == field.typeId do return ← err .badCfg
          i := i + 1
        pure ()
  for b in c.blocks do
    match b.terminator with
    | .jump target => checkTargetArgs target
    | .branch cond thenT elseT => do
        -- condition must be the Bool TypeId
        match boolT with
        | none => return ← err .badCfg
        | some boolId =>
            match typeOf cond with
            | none => return ← err .badCfg
            | some condT => unless condT == boolId do return ← err .badCfg
        checkTargetArgs thenT
        checkTargetArgs elseT
    | .switch scrut cases default => do
        -- scrutinee type
        match typeOf scrut with
        | none => return ← err .badCfg
        | some scrutT =>
            -- every case typeId == scrutinee type
            for cs in cases do
              unless cs.typeId == scrutT do
                return ← err .badCfg
              checkTargetArgs cs.target
            match default with
            | some dt => checkTargetArgs dt
            | none => pure ()
    | .return_ (some v) =>
        match typeOf v with
        | none => return ← err .badCfg
        | some vt => unless vt == c.result.typeId do return ← err .badCfg
    | .revert errorId args => checkErrorArgs errorId args
    | .return_ none | .trap _ => pure ()
  pure ()

/-! ### Per-op type/result contract (SPEC-SEM-WIRE-001 §4.3/§5.1 — CFG layer j)

    Step j: every value-producing op MUST carry `result := some _`
    (SPEC §4.3). The typed families (literal/constant/stateLoad/construct/
    fieldGet/indexGet/unary/binary/pureCall/fieldSet/variantTag/
    variantPayload/indexSet) must additionally have a result TypeId matching
    the op's exact type contract,
    with ValueId operand types matching the declared operand contract.
    `Op.FieldSet` carries the full §5.1 contract (base resolves to Struct,
    fieldIndex in range, type(value) == selected field.typeId,
    result.typeId == type(base)). `Op.VariantTag` carries the full §5.1
    contract (base resolves to Enum or Option, result.typeId == the unique
    structurally interned UInt32 TypeId) plus the static VariantPayload
    Enum/Option index/result contract plus the exact static IndexSet
    Array/Bytes/Map operand/result contract and CheckedCast UInt/Int
    source/destination/result contract. StateStore resolves stateId, requires
    type(value) == state.typeId, and carries no result. Assert requires a Bool
    condition plus an exact optional ErrorDecl/args join and carries no result.
    Emit resolves eventId, matches args positionally against EventDecl fields,
    and carries no result. The two deferred families (ContextRead/Commit) carry
    presence-only result; their exact contracts are deferred. ExternalCall/
    Schedule MUST carry `result := none` and a callee with at least two
    qualified-name components; a spurious result, short callee, or missing
    result on a value-producing op is an invalid Core trap → `.badCfg`. All
    step j failures → `.badCfg`. Bounded, non-recursive, total. Out of scope:
    ExternalCall/Schedule argument serializability, exact typing for
    ContextRead/Commit, TypeKey anonymous
    ranking/interning, provenance join, normalizer, product wire. -/

/-- The unique TypeId whose shape is `.uint 32`, if exactly one exists.
    Bounded, non-recursive. Like `uint8TypeId` (and unlike first-match
    `boolTypeId`), this resolver returns `some` only when
    exactly one `.uint 32` declaration is present, and `none` otherwise
    (zero or duplicate). SPEC-SEM-WIRE-001 §5.1 `Op.VariantTag` resolves the
    unique structurally interned UInt32 TypeId; in the absence of TypeKey
    structural interning (still pending), a duplicate anonymous `.uint 32`
    declaration is ambiguous and MUST be rejected here rather than silently
    picking the first. Parallel to `boolTypeId` in shape; the uniqueness
    gate is what VariantTag's claimed unique-UInt32 contract rests on. -/
def uint32TypeId (types : Array TypeDeclV1) : Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  let mut dup : Bool := false
  let mut i : Nat := 0
  for t in types do
    match t.shape with
    | .uint 32 =>
        match r with
        | none => r := some (UInt32.ofNat i)
        | some _ => dup := true
    | _ => pure ()
    i := i + 1
  if dup then pure none else pure r

/-- The unique TypeId whose shape is `.uint 8`, if exactly one exists.
    Bounded and non-recursive. Bytes IndexGet/IndexSet require the unique
    structurally interned UInt8 TypeId; while TypeKey interning is pending,
    duplicate anonymous UInt8 declarations fail closed as `none`. -/
def uint8TypeId (types : Array TypeDeclV1) : Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  let mut dup : Bool := false
  let mut i : Nat := 0
  for t in types do
    match t.shape with
    | .uint 8 =>
        match r with
        | none => r := some (UInt32.ofNat i)
        | some _ => dup := true
    | _ => pure ()
    i := i + 1
  if dup then pure none else pure r

/-- First TypeId whose shape is `.option element` with the given element
    TypeId, if any. Bounded, non-recursive. Used by `indexGet` on Map to
    resolve the unique `Option(map.value)` result TypeId. -/
def optionTypeId (types : Array TypeDeclV1) (element : TypeIdV1) :
    Option TypeIdV1 := Id.run do
  let mut r : Option TypeIdV1 := none
  let mut i : Nat := 0
  for t in types do
    if r.isNone then
      match t.shape with
      | .option e => if e == element then r := some (UInt32.ofNat i) else pure ()
      | _ => pure ()
    i := i + 1
  pure r

/-- Whether a TypeId resolves to a shape that is a valid `eq`/`ne` operand
    (SPEC §5.1 'serializable'): Bool/UInt/Int/Principal/Bytes/Field, or a
    Struct/Enum whose recursively-referenced types are all serializable.
    Array/Map/Option/Unit are NOT serializable. Bounded, fuel-bounded
    recursion (fuel = types.size). Out-of-range TypeId → false (caller owns
    range via step h). -/
private def serializableType (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel : Nat) → Bool
  | 0 => false
  | fuel + 1 =>
    match types[typeId.toNat]? with
    | none => false
    | some decl =>
      match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .bytes _ | .field _ => true
      | .struct fields =>
          fields.all (fun f => serializableType types f.typeId fuel)
      | .enum variants =>
          variants.all (fun v =>
            v.payloadTypes.all (fun t => serializableType types t fuel))
      | .array _ _ | .map _ _ | .option _ | .unit => false

/-- Step j: per-op type/result contract for one instruction. `defTypes` is the
    ValueId→TypeId def-site table (exactly-once by step f). `data` provides
    declaration tables for constant/stateLoad/construct/pureCall resolution.
    Value-producing ops (`Literal`/`Constant`/`StateLoad`/`Construct`/`FieldGet`/
    `IndexGet`/`Unary`/`Binary`/`PureCall`) MUST carry `result := some _` and
    the result TypeId must equal the op's exact result type; a missing result
    or mismatched TypeId is `.badCfg` (SPEC-SEM-WIRE-001 §4.3/§5.1).
    `Op.StateStore` resolves stateId, requires type(value) == state.typeId, and
    MUST carry `result := none`. `Op.Assert` requires a Bool condition,
    `errorId = none` with empty args or an exact ErrorDecl/args join, and no
    result. `Op.Emit` resolves eventId, matches args exactly against EventDecl
    fields, and requires no result. The other void ops (`ExternalCall`/
    `Schedule`) also require no result and require a callee with at least two
    qualified-name components; a spurious result or short callee is `.badCfg`.
    Their argument serializability contract remains deferred.
    `Op.FieldSet` carries the full §5.1 contract (base must resolve to a Struct, fieldIndex in
    range, type(value) == selected field.typeId, result.typeId == type(base));
    a missing result or any mismatch is `.badCfg`. `Op.VariantTag` carries
    the full §5.1 contract (base must resolve to an Enum or Option,
    result.typeId == the unique UInt32 TypeId — `uint32TypeId` returns `some`
    only when exactly one `.uint 32` declaration exists, so a duplicate
    anonymous UInt32 declaration resolves to `none` and is rejected); a
    missing result, a non-Enum/Option base, a missing/duplicate UInt32
    closure type, or a wrong result type is `.badCfg`. The remaining
    `Op.VariantPayload` carries its static §5.1 contract (Enum variant/payload
    indices or Option `(1,0)`, with the selected payload/element result type).
    `Op.IndexSet` and `Op.CheckedCast` carry their exact static contracts.
    The remaining result-producing ops (`ContextRead`/`Commit`) MUST carry
    `result := some _` presence-only; their exact contracts are deferred to
    later step-j extensions.
    All failures → `.badCfg`. Bounded, non-recursive (serializableType is
    fuel-bounded). -/
def checkOpTyping (instr : InstructionV1)
    (defTypes : Array (ValueIdV1 × TypeIdV1)) (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  let types := data.types
  let typeCount := types.size
  -- Bounded ValueId→TypeId lookup (defTypes is exactly-once by step f).
  let typeOf (vid : ValueIdV1) : Option TypeIdV1 := Id.run do
    let mut r : Option TypeIdV1 := none
    for (v, t) in defTypes do
      if v == vid then
        r := some t
        break
    pure r
  -- Shape of a TypeId, if in range.
  let shapeOf (tid : TypeIdV1) : Option TypeShapeV1 := Id.run do
    let mut r : Option TypeShapeV1 := none
    let n := tid.toNat
    if n < typeCount then
      match types[n]? with
      | some d => r := some d.shape
      | none => pure ()
    pure r
  -- The declared result TypeId of this instruction (only when result=some).
  let resultTypeId : Option TypeIdV1 :=
    match instr.result with
    | some vdef => some vdef.typeId
    | none => none
  -- Helper: require result present and equal to `tid`. SPEC-SEM-WIRE-001
  --   §4.3/§5.1: every value-producing op carries exactly one result
  --   (`Instruction.result = some ValueDefV1`); a missing result on a
  --   value-producing op is an invalid Core trap → `.badCfg`. When present,
  --   the result TypeId must equal the op's exact result type `tid`.
  let requireResult (tid : TypeIdV1) : Except SemanticWireErrorV1 Unit :=
    match resultTypeId with
    | some rT => unless rT == tid do err .badCfg
    | none => err .badCfg
  -- Helper: require result present for the two value-producing families
  --   whose exact contracts are deferred to later step-j extensions
  --   (ContextRead/Commit). SPEC §4.3/§5.1 mandates a result; a missing result
  --   is `.badCfg`. FieldSet, VariantTag, VariantPayload, IndexSet, and
  --   CheckedCast have their own exact static contracts below.
  let requireResultPresent : Except SemanticWireErrorV1 Unit :=
    match instr.result with
    | some _ => pure ()
    | none => err .badCfg
  -- Helper: resolve a ValueId operand's TypeId (missing def → .badCfg).
  let requireOperandType (vid : ValueIdV1) :
      Except SemanticWireErrorV1 TypeIdV1 :=
    match typeOf vid with
    | none => err .badCfg
    | some t => pure t
  -- Helper: positional arg type check against an expected TypeId list.
  let checkArgTypes (args : Array ValueIdV1) (expected : Array TypeIdV1) :
      Except SemanticWireErrorV1 Unit := do
    unless args.size == expected.size do
      return ← err .badCfg
    let mut i : Nat := 0
    while i < args.size do
      let argT ← requireOperandType args[i]!
      match expected[i]? with
      | none => return ← err .badCfg
      | some expT => unless argT == expT do return ← err .badCfg
      i := i + 1
    pure ()
  match instr.op with
  | .literal tid _ =>
      -- result.typeId == op.typeId; no ValueId uses.
      requireResult tid
  | .constant cid =>
      -- constantId in range → result.typeId == constants[cid].typeId.
      match data.constants[cid.toNat]? with
      | none => err .badCfg
      | some c => requireResult c.typeId
  | .stateLoad sid =>
      -- stateId in range → result.typeId == logicalState[sid].typeId.
      match data.logicalState[sid.toNat]? with
      | none => err .badCfg
      | some s => requireResult s.typeId
  | .construct tid ctorIdx args =>
      -- op.typeId in range; resolve type shape; reject primitives that
      -- cannot be Constructed.
      match shapeOf tid with
      | none => err .badCfg
      | some shape =>
        match shape with
        | .struct fields =>
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == fields.size do return ← err .badCfg
            let expected := fields.map (·.typeId)
            checkArgTypes args expected
            requireResult tid
        | .enum variants =>
            unless ctorIdx.toNat < variants.size do return ← err .badCfg
            match variants[ctorIdx.toNat]? with
            | none => err .badCfg
            | some v =>
                unless args.size == v.payloadTypes.size do return ← err .badCfg
                checkArgTypes args v.payloadTypes
                requireResult tid
        | .array element length =>
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == length.toNat do return ← err .badCfg
            let expected := Array.mk (List.replicate args.size element)
            checkArgTypes args expected
            requireResult tid
        | .option element =>
            match ctorIdx.toNat with
            | 0 =>
                -- none: args == #[]
                unless args.size == 0 do return ← err .badCfg
                requireResult tid
            | 1 =>
                -- some: args.count == 1, arg type == element
                unless args.size == 1 do return ← err .badCfg
                checkArgTypes args #[element]
                requireResult tid
            | _ => err .badCfg
        | .unit =>
            -- Unit/empty Map shape: constructorIndex==0, args==#[].
            -- (`.map` with nonempty cannot be Constructed; empty Map uses
            -- constructorIndex 0, args #[] — handled under .map below.)
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == 0 do return ← err .badCfg
            requireResult tid
        | .map _ _ =>
            -- Only the empty Map (constructorIndex 0, args #[]) can be
            -- Constructed this slice; nonempty Map construction is out of
            -- scope. constructorIndex != 0 → .badCfg.
            unless ctorIdx == 0 do return ← err .badCfg
            unless args.size == 0 do return ← err .badCfg
            requireResult tid
        | .bool | .uint _ | .int _ | .principal | .bytes _ | .field _ =>
            -- primitives/Bytes/Principal/Field/uint/int/bool cannot be Constructed
            err .badCfg
  | .fieldGet base fieldIdx =>
      -- base ValueId type resolves to Struct via defTypes; fieldIndex < fields.size;
      -- result.typeId == fields[fieldIdx].typeId.
    match requireOperandType base with
    | .error e => err e
    | .ok baseT =>
        match shapeOf baseT with
        | none => err .badCfg
        | some (.struct fields) =>
            unless fieldIdx.toNat < fields.size do return ← err .badCfg
            match fields[fieldIdx.toNat]? with
            | none => err .badCfg
            | some f => requireResult f.typeId
        | some _ => err .badCfg
  | .indexGet base index =>
      -- base ValueId type resolves to Array/Bytes/Map; index type and result
      --   depend on base kind.
    let baseT ← requireOperandType base
    let idxT ← requireOperandType index
    match shapeOf baseT with
    | none => err .badCfg
    | some (.array element _length) =>
        -- index must be the unique UInt32 TypeId; result == element.
        match uint32TypeId types with
        | none => err .badCfg
        | some u32 =>
            unless idxT == u32 do return ← err .badCfg
            requireResult element
    | some (.bytes _length) =>
        -- index UInt32; result == unique UInt8 TypeId.
        match uint32TypeId types, uint8TypeId types with
        | some u32, some u8 =>
            unless idxT == u32 do return ← err .badCfg
            requireResult u8
        | _, _ => err .badCfg
    | some (.map key value) =>
        -- index type == map.key TypeId; result == unique Option(map.value).
        unless idxT == key do return ← err .badCfg
        match optionTypeId types value with
        | none => err .badCfg
        | some optT => requireResult optT
    | some _ => err .badCfg
  | .unary op operand =>
      let opT ← requireOperandType operand
      match op with
      | .neg =>
          -- operand type Int or Field; result == operand type.
          match shapeOf opT with
          | some (.int _) | some (.field _) => requireResult opT
          | _ => err .badCfg
      | .not =>
          -- operand type Bool; result == Bool.
          match shapeOf opT with
          | some .bool => requireResult opT
          | _ => err .badCfg
      | .bitNot =>
          -- operand type UInt or Int; result == operand type.
          match shapeOf opT with
          | some (.uint _) | some (.int _) => requireResult opT
          | _ => err .badCfg
  | .binary op lhs rhs =>
      let lhsT ← requireOperandType lhs
      let rhsT ← requireOperandType rhs
      match op with
      | .add | .sub | .mul | .div | .mod =>
          -- arithmetic: lhs==rhs same UInt/Int (Field only add/sub/mul/div);
          --   result == lhs type.
          let lhsShape := shapeOf lhsT
          let okArith : Bool :=
            lhsT == rhsT &&
            (match lhsShape with
             | some (.uint _) | some (.int _) => true
             | some (.field _) =>
                 -- Field allows add/sub/mul/div but NOT mod.
                 match op with | .mod => false | _ => true
             | _ => false)
          unless okArith do return ← err .badCfg
          requireResult lhsT
      | .eq | .ne =>
          -- lhs==rhs same serializable type; result == Bool.
          unless lhsT == rhsT do return ← err .badCfg
          unless serializableType types lhsT typeCount do return ← err .badCfg
          match boolTypeId types with
          | none => err .badCfg
          | some boolT => requireResult boolT
      | .lt | .le | .gt | .ge =>
          -- lhs==rhs same UInt/Int; result == Bool.
          let sameInt : Bool := lhsT == rhsT &&
            (match shapeOf lhsT with
             | some (.uint _) | some (.int _) => true
             | _ => false)
          unless sameInt do return ← err .badCfg
          match boolTypeId types with
          | none => err .badCfg
          | some boolT => requireResult boolT
      | .and | .or =>
          -- lhs==rhs Bool; result == Bool.
          let bothBool : Bool := lhsT == rhsT &&
            (match shapeOf lhsT with | some .bool => true | _ => false)
          unless bothBool do return ← err .badCfg
          match boolTypeId types with
          | none => err .badCfg
          | some boolT => requireResult boolT
      | .bitAnd | .bitOr | .bitXor =>
          -- lhs==rhs same UInt/Int; result == lhs type.
          let sameInt : Bool := lhsT == rhsT &&
            (match shapeOf lhsT with
             | some (.uint _) | some (.int _) => true
             | _ => false)
          unless sameInt do return ← err .badCfg
          requireResult lhsT
      | .shl | .shr =>
          -- lhs UInt/Int, rhs UInt32; result == lhs type.
          let lhsInt : Bool :=
            match shapeOf lhsT with
            | some (.uint _) | some (.int _) => true
            | _ => false
          unless lhsInt do return ← err .badCfg
          match uint32TypeId types with
          | none => err .badCfg
          | some u32 =>
              unless rhsT == u32 do return ← err .badCfg
              requireResult lhsT
  | .pureCall calleeId args =>
      -- calleeId in range, callee.kind == .pureFn, args count == params size,
      --   each arg type == params[i].typeId; result == callee.result.typeId.
    match data.callables[calleeId.toNat]? with
    | none => err .badCfg
    | some callee =>
        unless callee.kind == .pureFn do return ← err .badCfg
        unless args.size == callee.params.size do return ← err .badCfg
        let expected := callee.params.map (·.typeId)
        checkArgTypes args expected
        requireResult callee.result.typeId
  -- Op.StateStore (SPEC-SEM-WIRE-001 §5.1): stateId MUST resolve, the value
  --   operand TypeId MUST exactly equal the selected state.typeId, and this
  --   op is void (`Instruction.result = none`). Any mismatch → `.badCfg`.
  | .stateStore stateId value =>
      match instr.result with
      | some _ => err .badCfg
      | none =>
          match data.logicalState[stateId.toNat]? with
          | none => err .badCfg
          | some state =>
              let valueT ← requireOperandType value
              unless valueT == state.typeId do return ← err .badCfg
              pure ()
  -- Op.Assert (SPEC-SEM-WIRE-001 §5.1/§6): result MUST be none; condition
  --   MUST be Bool. `errorId = none` requires no args; `some errorId` MUST
  --   resolve and args MUST match ErrorDecl fields positionally and exactly.
  | .assert_ condition errorId args =>
      match instr.result with
      | some _ => err .badCfg
      | none =>
          let conditionT ← requireOperandType condition
          match shapeOf conditionT with
          | some .bool =>
              match errorId with
              | none =>
                  unless args.isEmpty do return ← err .badCfg
                  pure ()
              | some eid =>
                  match data.errors[eid.toNat]? with
                  | none => err .badCfg
                  | some errorDecl =>
                      checkArgTypes args (errorDecl.fields.map (·.typeId))
          | _ => err .badCfg
  -- Op.Emit (SPEC-SEM-WIRE-001 §5.1): result MUST be none; eventId MUST
  --   resolve; args MUST match EventDecl fields positionally and exactly.
  --   EffectId canonical numbering/uniqueness is owned by CFG step e.5.
  | .emit _effectId eventId args =>
      match instr.result with
      | some _ => err .badCfg
      | none =>
          match data.events[eventId.toNat]? with
          | none => err .badCfg
          | some eventDecl =>
              checkArgTypes args (eventDecl.fields.map (·.typeId))
  -- Remaining void ops (SPEC §5.1/§6): ExternalCall/Schedule are genuinely
  --   void, and their callee MUST contain at least two qualified-name
  --   components. Result presence is checked before callee shape to preserve
  --   the existing fail-closed order. Arg serializability is a later slice;
  --   EffectId canonical assignment is owned by CFG step e.5.
  | .externalCall _effectId callee _args | .schedule _effectId callee _args =>
      match instr.result with
      | some _ => err .badCfg
      | none =>
          unless 2 ≤ callee.components.toArray.size do return ← err .badCfg
          pure ()
  -- Op.FieldSet (SPEC-SEM-WIRE-001 §5.1): base ValueId type MUST resolve to
  --   a Struct; fieldIndex MUST be in range; type(value) MUST exactly equal
  --   the selected field.typeId; `Instruction.result` MUST be present and
  --   its typeId MUST exactly equal type(base) (the whole struct). Any
  --   failure → `.badCfg`. (Presence is enforced by `requireResult baseT`,
  --   which fails `.badCfg` on a missing result, preserving the prior
  --   missing-result gate.)
  | .fieldSet base fieldIndex value =>
      let baseT ← requireOperandType base
      match shapeOf baseT with
      | none => err .badCfg
      | some (.struct fields) =>
          unless fieldIndex.toNat < fields.size do return ← err .badCfg
          match fields[fieldIndex.toNat]? with
          | none => err .badCfg
          | some f =>
              let valueT ← requireOperandType value
              unless valueT == f.typeId do return ← err .badCfg
              requireResult baseT
      | some _ => err .badCfg
  -- Op.VariantTag (SPEC-SEM-WIRE-001 §5.1): base ValueId type MUST resolve
  --   to a Type.Enum or Type.Option; the unique UInt32 TypeId (resolved via
  --   the `uint32TypeId` helper, which returns `some` only when exactly one
  --   `.uint 32` declaration exists) MUST exist; `Instruction.result` MUST
  --   be present and its typeId MUST exactly equal that UInt32 TypeId. Any
  --   failure → `.badCfg`. (Presence is enforced by `requireResult u32`,
  --   which fails `.badCfg` on a missing result, preserving the prior
  --   missing-result gate.)
  | .variantTag base =>
      let baseT ← requireOperandType base
      match shapeOf baseT with
      | some (.enum _) | some (.option _) =>
          match uint32TypeId types with
          | none => err .badCfg
          | some u32 => requireResult u32
      | _ => err .badCfg
  -- Op.VariantPayload (SPEC-SEM-WIRE-001 §5.1): Enum bases require an
  --   in-range variantIndex and payloadIndex and return the selected payload
  --   TypeId. Option bases permit only `(variantIndex=1,payloadIndex=0)` and
  --   return the element TypeId. Agreement between an Enum value's runtime
  --   tag and `variantIndex` is not checked here; D2-07 must implement it as
  --   an interpreter trap. This gate validates the static contract. Failure →
  --   `.badCfg`; `requireResult` preserves the exact result-presence gate.
  | .variantPayload base variantIndex payloadIndex =>
      let baseT ← requireOperandType base
      match shapeOf baseT with
      | some (.enum variants) =>
          unless variantIndex.toNat < variants.size do return ← err .badCfg
          match variants[variantIndex.toNat]? with
          | none => err .badCfg
          | some variant =>
              unless payloadIndex.toNat < variant.payloadTypes.size do
                return ← err .badCfg
              match variant.payloadTypes[payloadIndex.toNat]? with
              | none => err .badCfg
              | some payloadT => requireResult payloadT
      | some (.option element) =>
          unless variantIndex.toNat == 1 && payloadIndex.toNat == 0 do
            return ← err .badCfg
          requireResult element
      | _ => err .badCfg
  -- Op.IndexSet (SPEC-SEM-WIRE-001 §5.1): Array/Bytes indices must be the
  --   unique UInt32 TypeId; Array values match element, Bytes values match
  --   UInt8; Map key/value operands match the declared key/value TypeIds.
  --   Every valid IndexSet returns type(base). Runtime bounds are not checked
  --   here and must be handled by D2-07. Any static mismatch → `.badCfg`.
  | .indexSet base index value =>
      let baseT ← requireOperandType base
      let indexT ← requireOperandType index
      let valueT ← requireOperandType value
      match shapeOf baseT with
      | some (.array element _) =>
          match uint32TypeId types with
          | none => err .badCfg
          | some u32 =>
              unless indexT == u32 && valueT == element do
                return ← err .badCfg
              requireResult baseT
      | some (.bytes _) =>
          match uint32TypeId types, uint8TypeId types with
          | some u32, some u8 =>
              unless indexT == u32 && valueT == u8 do
                return ← err .badCfg
              requireResult baseT
          | _, _ => err .badCfg
      | some (.map key mapValue) =>
          unless indexT == key && valueT == mapValue do
            return ← err .badCfg
          requireResult baseT
      | _ => err .badCfg
  -- Op.CheckedCast (SPEC-SEM-WIRE-001 §5.1): both the source ValueId type
  --   and `toType` MUST resolve to UInt/Int shapes, and the instruction
  --   result TypeId MUST exactly equal `toType`. Runtime representability is
  --   not a static property and remains a D2-07 checked-revert concern.
  | .checkedCast value toType =>
      let valueT ← requireOperandType value
      let sourceIsInteger : Bool :=
        match shapeOf valueT with
        | some (.uint _) | some (.int _) => true
        | _ => false
      let destinationIsInteger : Bool :=
        match shapeOf toType with
        | some (.uint _) | some (.int _) => true
        | _ => false
      unless sourceIsInteger && destinationIsInteger do
        return ← err .badCfg
      requireResult toType
  -- Remaining result-producing ops (ContextRead/Commit) carry
  --   `Instruction.result = some _` presence-only. Their exact contracts are
  --   deferred to later step-j extensions.
  | .contextRead _ | .commit _ => requireResultPresent

/-- Per-callable CFG shape + reachability + loopBounds + EffectId assignment
    + ValueId SSA def-table + dominance-of-use + def-site TypeId range +
    terminator typing + per-op type/result contract. Deterministic, bounded.
    Steps a–e are CFG shape (including Switch cases nonempty and typed-value
    uniqueness), reachability, arity, and loopBounds; step e.5 checks
    per-callable EffectIds; step f runs
    the ValueId SSA def-table
    (exactly-once def + use-existence); step g runs dominance-of-use;
    step h runs def-site TypeId range (`.badReference`); step i runs
    terminator typing (`.badCfg`); step j runs the per-op type/result
    contract (§5.1, `.badCfg`) for value-producing ops. The reachability
    array computed in step d is shared with step g; the `defTypes` table
    built in step h is shared with steps i and j. -/
private def validateCallableCfgShape (c : CallableV1)
    (typeCount : Nat) (types : Array TypeDeclV1)
    (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  let blockCount := c.blocks.size
  -- a) entryBlock == 0
  unless c.entryBlock.toNat == 0 do
    return ← err .badCfg
  -- b) block id == array index
  let mut idx : Nat := 0
  for b in c.blocks do
    unless b.id.toNat == idx do
      return ← err .badCfg
    idx := idx + 1
  -- b.5/b.6) Canonical Switch shape: zero cases must normalize to Jump, and
  --   typed canonical case constants must be unique within each Switch.
  for b in c.blocks do
    match b.terminator with
    | .switch _ cases _ =>
        if cases.isEmpty then return ← err .badCfg
        validateSwitchCaseValuesUnique cases
    | _ => pure ()
  -- c) terminator target range
  for b in c.blocks do
    for succ in terminatorSuccessors (BlockV1.terminator b) do
      checkBlockIdInRange succ blockCount
  -- c.5) jump/branch/switch target arg arity == target block params
  --   (only for in-range targets; step c owns OOR. Arg ValueId→type is
  --   out of scope — needs the ValueId-definition table from a later slice.)
  for b in c.blocks do
    for target in terminatorJumpTargets (BlockV1.terminator b) do
      checkJumpTargetArity c.blocks blockCount target
  -- d) reachability from entry (bounded fixed-point passes). The reachable
  --   array is hoisted so steps d, f, g share it (when blockCount==0 it is
  --   empty and dominance is a no-op).
  let reachable : Array Bool :=
    if blockCount == 0 then
      #[]
    else
      let visited0 : Array Bool := Array.mk (List.replicate blockCount false)
      let visited1 := visited0.set! 0 true
      cfgReachFixpoint c.blocks blockCount blockCount visited1
  for v in reachable do
    unless v do
      return ← err .badCfg
  -- e) loopBounds back-edge coverage (SPEC §6 / §6.2)
  validateCallableLoopBounds c
  -- e.5) EffectId assignment: Emit/ExternalCall/Schedule IDs are contiguous
  --   from zero in BlockId/instruction order, independently per callable.
  validateCallableEffectIds c
  -- f) ValueId SSA definition-table: exactly-once def + use-existence
  --   (SPEC §6.2). Build defSites once and reuse for step g; build defTypes
  --   once and reuse for steps h and i.
  let defSites := collectValueDefSites c
  checkValueIdDefUniqueness defSites
  checkValueIdUsesExist c defSites
  -- g) dominance-of-use (SPEC §6.2): every ValueId use is in a block
  --   dominated by its def's block.
  validateCallableDominanceOfUse c defSites reachable
  -- h) def-site TypeId range (SPEC §6.2): block params + instruction result
  --   ValueDef TypeIds must be in [0, typeCount). Callable param/result
  --   TypeIds are already checked at step 2. Failure → `.badReference`.
  let defTypes := collectValueTypeDefs c
  checkDefSiteTypeIdsInRange defTypes typeCount
  -- i) terminator typing (SPEC §6.2): branch cond Bool, switch case type ==
  --   scrutinee type, jump/branch/switch target arg types == target block
  --   param types positionally, return (some v) type == result type, and
  --   Term.Revert errorId/args == selected ErrorDecl fields. All `.badCfg`.
  checkTerminatorTyping c defTypes types data.errors
  -- j) per-op type/result contract (SPEC-SEM-WIRE-001 §4.3/§5.1): every
  --   value-producing op (literal/constant/stateLoad/construct/fieldGet/
  --   indexGet/unary/binary/pureCall/fieldSet/variantTag) must carry
  --   `result := some _` whose declared TypeId matches the op's type
  --   contract, and ValueId operand types must match the declared operand
  --   contract. `Op.FieldSet` carries the full §5.1 contract (base Struct,
  --   fieldIndex in range, type(value) == field.typeId, result.typeId ==
  --   type(base)). `Op.VariantTag` carries the full §5.1 contract (base
  --   Enum/Option, result.typeId == unique UInt32 TypeId). `Op.StateStore`
  --   resolves stateId, checks value type, and requires no result. `Op.Assert`
  --   checks Bool condition plus exact optional ErrorDecl/args and no result.
  --   `Op.Emit` resolves EventDecl, checks positional args, and requires no
  --   result. The remaining void ops (ExternalCall/Schedule) require no result;
  --   a spurious result is `.badCfg`. VariantPayload, IndexSet, and
  --   CheckedCast have exact static contracts; ContextRead and
  --   Commit must each carry `result := some _` presence-only and retain
  --   deferred exact contracts. All failures → `.badCfg`. Reuses `defTypes`
  --   from step h.
  for b in c.blocks do
    for instr in b.instructions do
      checkOpTyping instr defTypes data

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

/-! ### Canonical valueBytes (SPEC-SEM-WIRE-001 §5)

    Type-driven encode/decode/validate shared by Constant, Op.Literal, and
    SwitchCase. Transport decode does not call this. Short/leftover/bad marker/
    range failures are `.nonCanonical` (not `.truncated`/`.trailingBytes`/
    `.badType` when the TypeId/shape is legal). OOR TypeId → `.badReference`.
    Nesting/size/map-count limits → `.limitExceeded`.
-/

private def takeByteNC (c : Cursor) :
    Except SemanticWireErrorV1 (UInt8 × Cursor) := do
  unless remaining c ≥ 1 do
    return ← err .nonCanonical
  pure (c.input.get! c.offset, ⟨c.input, c.offset + 1, c.nesting⟩)

private def takeBytesNC (c : Cursor) (n : Nat) :
    Except SemanticWireErrorV1 (ByteArray × Cursor) := do
  unless remaining c ≥ n do
    return ← err .nonCanonical
  pure (c.input.extract c.offset (c.offset + n), ⟨c.input, c.offset + n, c.nesting⟩)

private def takeU32leNC (c : Cursor) :
    Except SemanticWireErrorV1 (UInt32 × Cursor) := do
  let (b0, c) ← takeByteNC c
  let (b1, c) ← takeByteNC c
  let (b2, c) ← takeByteNC c
  let (b3, c) ← takeByteNC c
  let v := b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat v, c)

private def beBytesToNatV1 (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  for i in [:bytes.size] do
    n := n * 256 + (bytes.get! i).toNat
  pure n

private def leBytesToNatV1 (bytes : ByteArray) : Nat := Id.run do
  let mut n : Nat := 0
  let mut place : Nat := 1
  for i in [:bytes.size] do
    n := n + (bytes.get! i).toNat * place
    place := place * 256
  pure n

/-- `ceil(bitLength(p)/8)` for Field value width (SPEC §5). -/
private def fieldValueByteLengthV1 (modulusBE : ByteArray) : Nat :=
  let p := beBytesToNatV1 modulusBE
  if p == 0 then 0
  else
    let bitLength := Nat.log2 p + 1
    (bitLength + 7) / 8

/-- Decode one type-driven value and return its re-encoded canonical bytes.
    Fuel bounds recursive shapes (Array/Map/Option/Struct/Enum). -/
private def decodeAndReencodeValueBytesV1 (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel : Nat) → Decoder ByteArray
  | 0 => fun _ => err .limitExceeded
  | fuel + 1 => fun c => do
    match types[typeId.toNat]? with
    | none => err .badReference
    | some decl =>
      match decl.shape with
      | .bool => do
          let (b, c) ← takeByteNC c
          unless b == 0 || b == 1 do
            return ← err .nonCanonical
          pure (encodeU8 b, c)
      | .uint width => do
          let n := width.toNat / 8
          let (raw, c) ← takeBytesNC c n
          pure (raw, c)
      | .int width => do
          let n := width.toNat / 8
          let (raw, c) ← takeBytesNC c n
          pure (raw, c)
      | .principal => do
          let (lenU, c) ← takeU32leNC c
          let len := lenU.toNat
          unless 1 ≤ len && len ≤ maxTypeLengthV1 do
            return ← err .nonCanonical
          let (bodyBytes, c) ← takeBytesNC c len
          pure ((encodeU32le lenU).append bodyBytes, c)
      | .unit =>
          pure (ByteArray.empty, c)
      | .bytes length => do
          let (raw, c) ← takeBytesNC c length.toNat
          pure (raw, c)
      | .array element length => do
          let mut out := ByteArray.empty
          let mut c := c
          for _ in [:length.toNat] do
            let (chunk, c') ← decodeAndReencodeValueBytesV1 types element fuel c
            out := out.append chunk
            c := c'
          pure (out, c)
      | .map keyType valueType => do
          let (countU, c) ← takeU32leNC c
          let count := countU.toNat
          unless count ≤ maxMapEntriesV1 do
            return ← err .limitExceeded
          let mut out := encodeU32le countU
          let mut c := c
          let mut prevKey? : Option ByteArray := none
          for _ in [:count] do
            let (keyLenU, c1) ← takeU32leNC c
            let keyLen := keyLenU.toNat
            let (keyBytes, c2) ← takeBytesNC c1 keyLen
            let (keyRe, keyC) ←
              decodeAndReencodeValueBytesV1 types keyType fuel (start keyBytes)
            unless remaining keyC == 0 do
              return ← err .nonCanonical
            unless keyRe == keyBytes do
              return ← err .nonCanonical
            unless keyBytes.size == keyLen do
              return ← err .nonCanonical
            match prevKey? with
            | none => pure ()
            | some prev =>
              match compareByteArrayLex prev keyBytes with
              | .lt => pure ()
              | .eq | .gt => return ← err .nonCanonical
            prevKey? := some keyBytes
            let (valLenU, c3) ← takeU32leNC c2
            let valLen := valLenU.toNat
            let (valBytes, c4) ← takeBytesNC c3 valLen
            let (valRe, valC) ←
              decodeAndReencodeValueBytesV1 types valueType fuel (start valBytes)
            unless remaining valC == 0 do
              return ← err .nonCanonical
            unless valRe == valBytes do
              return ← err .nonCanonical
            unless valBytes.size == valLen do
              return ← err .nonCanonical
            out :=
              ((out.append (encodeU32le keyLenU)).append keyBytes).append
                ((encodeU32le valLenU).append valBytes)
            c := c4
          pure (out, c)
      | .option element => do
          let (m, c) ← takeByteNC c
          match m.toNat with
          | 0 => pure (encodeU8 0, c)
          | 1 => do
              let (payload, c) ← decodeAndReencodeValueBytesV1 types element fuel c
              pure ((encodeU8 1).append payload, c)
          | _ => err .nonCanonical
      | .field spec => do
          let width := fieldValueByteLengthV1 spec.modulusBE
          let (raw, c) ← takeBytesNC c width
          let value := leBytesToNatV1 raw
          let modulus := beBytesToNatV1 spec.modulusBE
          unless value < modulus do
            return ← err .nonCanonical
          pure (raw, c)
      | .struct fields => do
          let mut out := ByteArray.empty
          let mut c := c
          for f in fields do
            let (chunk, c') ← decodeAndReencodeValueBytesV1 types f.typeId fuel c
            out := out.append chunk
            c := c'
          pure (out, c)
      | .enum variants => do
          let (idxU, c) ← takeU32leNC c
          let idx := idxU.toNat
          match variants[idx]? with
          | none => err .nonCanonical
          | some variant => do
              let mut out := encodeU32le idxU
              let mut c := c
              for payloadType in variant.payloadTypes do
                let (chunk, c') ←
                  decodeAndReencodeValueBytesV1 types payloadType fuel c
                out := out.append chunk
                c := c'
              pure (out, c)

/-- Validate a complete valueBytes slice for `typeId` (full consume + re-encode). -/
def validateValueBytesV1 (types : Array TypeDeclV1) (typeId : TypeIdV1)
    (valueBytes : ByteArray) : Except SemanticWireErrorV1 Unit := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let (reencoded, c) ←
    decodeAndReencodeValueBytesV1 types typeId maxNesting (start valueBytes)
  unless remaining c == 0 do
    return ← err .nonCanonical
  unless reencoded == valueBytes do
    return ← err .nonCanonical
  pure ()

private def validateOpValueBytesV1 (types : Array TypeDeclV1) (op : SemanticOpV1) :
    Except SemanticWireErrorV1 Unit := do
  match op with
  | .literal typeId valueBytes =>
      validateValueBytesV1 types typeId valueBytes
  | _ => pure ()

private def validateTerminatorValueBytesV1 (types : Array TypeDeclV1)
    (term : TerminatorV1) : Except SemanticWireErrorV1 Unit := do
  match term with
  | .switch _scrutinee cases _default =>
      for sc in cases do
        validateValueBytesV1 types sc.typeId sc.valueBytes
  | _ => pure ()

private def validateConstantsValueBytesV1 (types : Array TypeDeclV1)
    (constants : Array ConstantV1) : Except SemanticWireErrorV1 Unit := do
  for c in constants do
    validateValueBytesV1 types c.typeId c.valueBytes
  pure ()

/-- Walk callable blocks for Op.Literal and SwitchCase valueBytes only.
    Does not check CFG reachability, dominance, or ValueId SSA. -/
private def validateCallablesValueBytesV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    for block in callable.blocks do
      for instr in block.instructions do
        validateOpValueBytesV1 types instr.op
      validateTerminatorValueBytesV1 types block.terminator
  pure ()

/-- Exact declaration/field names are checked on a private UTF-8 sort so
    public source-order arrays remain unchanged and duplicate detection stays
    non-quadratic at the wire table limit. -/
private def checkUniqueDeclarationNamesV1 (names : Array String) :
    Except SemanticWireErrorV1 Unit := do
  let sorted := names.qsort fun left right =>
    compareByteArrayLex left.toUTF8 right.toUTF8 == .lt
  let mut index : Nat := 1
  while index < sorted.size do
    if sorted[index - 1]! == sorted[index]! then
      return ← err .duplicate
    index := index + 1
  pure ()

/-- Named Struct/Enum TypeDecl names are exact-string unique (SPEC §5/§6).
    Full named-prefix/TypeKey closure and identifier grammar/NFC are separate. -/
private def validateNamedTypeNameUniquenessV1 (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut names : Array String := #[]
  for decl in types do
    match decl.name with
    | some name => names := names.push name
    | none => pure ()
  checkUniqueDeclarationNamesV1 names

/-- Constant names are exact-string unique within the constants table (SPEC
    §6). Identifier grammar/NFC remains a separate gate. -/
private def validateConstantNameUniquenessV1 (constants : Array ConstantV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (constants.map (·.name))

/-- StateDecl names are exact-string unique within logicalState (SPEC §6).
    Identifier grammar/NFC remains a separate gate. -/
private def validateLogicalStateNameUniquenessV1
    (logicalState : Array StateDeclV1) : Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (logicalState.map (·.name))

/-- EventDecl names are exact-string unique within events (SPEC §6).
    Identifier grammar/NFC remains a separate gate. -/
private def validateEventNameUniquenessV1 (events : Array EventDeclV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (events.map (·.name))

/-- ErrorDecl names are exact-string unique within errors (SPEC §6).
    Identifier grammar/NFC remains a separate gate. -/
private def validateErrorNameUniquenessV1 (errors : Array ErrorDeclV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (errors.map (·.name))

/-- Event/error interface-field names are exact-string unique within each
    declaration (SPEC §6). Each declaration gets an independent namespace;
    identifier grammar/NFC remains a separate gate. -/
private def validateInterfaceFieldNameUniquenessV1
    (events : Array EventDeclV1) (errors : Array ErrorDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  for eventDecl in events do
    checkUniqueDeclarationNamesV1 (eventDecl.fields.map (·.name))
  for errorDecl in errors do
    checkUniqueDeclarationNamesV1 (errorDecl.fields.map (·.name))
  pure ()

/-- Callable signature name presence (SPEC §6): initializer is the only
    anonymous callable kind; entry/view/pureFn/invariant must carry `some`
    name. String grammar/NFC remains a separate gate. Runs after canonical
    values and before uniqueness/special signatures/CFG. -/
private def validateCallableKindNamePresenceV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    match callable.kind, callable.name with
    | .initializer, none => pure ()
    | .entry, some _ | .view, some _ | .pureFn, some _
    | .invariant, some _ => pure ()
    | _, _ => return ← err .badCfg
  pure ()

/-- Named callables are unique within the unified callable table (SPEC §6).
    Compare exact UTF-8 strings; grammar/NFC is a separate gate. Sorting a
    private name array preserves public callable source order. -/
private def validateCallableNameUniquenessV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut names : Array String := #[]
  for callable in callables do
    match callable.name with
    | some name => names := names.push name
    | none => pure ()
  let sorted := names.qsort fun left right =>
    compareByteArrayLex left.toUTF8 right.toUTF8 == .lt
  let mut index : Nat := 1
  while index < sorted.size do
    if sorted[index - 1]! == sorted[index]! then
      return ← err .badCfg
    index := index + 1
  pure ()

/-- Parameter names are exact-string unique within each callable (SPEC §6).
    Each callable gets a fresh private sort; grammar/NFC remains separate. -/
private def validateCallableParameterNameUniquenessV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    let names := callable.params.map (·.name)
    let sorted := names.qsort fun left right =>
      compareByteArrayLex left.toUTF8 right.toUTF8 == .lt
    let mut index : Nat := 1
    while index < sorted.size do
      if sorted[index - 1]! == sorted[index]! then
        return ← err .badCfg
      index := index + 1
  pure ()

/-- At most one initializer callable may occur in source order (SPEC §6). -/
private def validateInitializerCardinalityV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Bool := false
  for callable in callables do
    if callable.kind == .initializer then
      if seen then return ← err .badCfg
      seen := true
  pure ()

/-- Every initializer result resolves to Type.Unit and has public visibility
    (SPEC §6). Shallow result TypeId range validation runs earlier; this helper
    remains total and fails closed if called with a missing type. -/
private def validateInitializerResultShapeV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .initializer then
      unless callable.result.visibility == .public_ do
        return ← err .badCfg
      match types[callable.result.typeId.toNat]? with
      | some decl =>
          match decl.shape with
          | .unit => pure ()
          | _ => return ← err .badCfg
      | none => return ← err .badCfg
  pure ()

/-- Every invariant callable result resolves to Type.Bool and has public
    visibility (SPEC §6). Declaration join, zero params, closure restrictions,
    and invariantSteps are separate gates. Shallow result TypeId range
    validation runs earlier; this helper stays total for missing types. -/
private def validateInvariantResultShapeV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant then
      unless callable.result.visibility == .public_ do
        return ← err .badCfg
      match types[callable.result.typeId.toNat]? with
      | some decl =>
          match decl.shape with
          | .bool => pure ()
          | _ => return ← err .badCfg
      | none => return ← err .badCfg
  pure ()

/-- Invariant roots carry no parameters (SPEC §8). Declaration join, closure
    restrictions, and invariantSteps are separate gates. Parameter TypeId range
    validation runs in the earlier shallow-reference phase. -/
private def validateInvariantParameterShapeV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant && !callable.params.isEmpty then
      return ← err .badCfg
  pure ()

/-- Invariant roots carry no loop bounds (SPEC §8). Their normalized closure
    must be acyclic; full closure validation and invariantSteps remain separate
    gates. Other callable kinds retain the generic bounded-loop contract. -/
private def validateInvariantLoopBoundsShapeV1 (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant && !callable.loopBounds.isEmpty then
      return ← err .badCfg
  pure ()

/-- Callables provably disjoint from every invariant closure carry no fuel
    metadata (SPEC §8). Initializer/entry/view are kind-disjoint from roots and
    `Op.PureCall` callees. When no invariant callable exists, every pureFn is
    also provably rootless and therefore outside all closures. Exact transitive
    pureFn membership, reachable call-graph DAG, and closure-CFG acyclicity are
    checked post-CFG; exact step computation and op validation remain separate. -/
private def validateNonClosureCallableInvariantStepsV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let hasInvariantRoot := callables.any (·.kind == .invariant)
  for callable in callables do
    match callable.kind with
    | .initializer | .entry | .view =>
        match callable.invariantSteps with
        | none => pure ()
        | some _ => return ← err .badCfg
    | .pureFn =>
        unless hasInvariantRoot do
          match callable.invariantSteps with
          | none => pure ()
          | some _ => return ← err .badCfg
    | .invariant => pure ()
  pure ()

/-- Every invariant root carries fuel metadata (SPEC §8). This bounded gate
    validates `some` presence only; exact pureFn membership, reachable
    call-graph DAG, and closure-CFG acyclicity are checked post-CFG, while exact
    step computation, op validation, and checked accumulation remain separate.
    The intrinsic ceiling is checked post-CFG. This presence
    gate runs after non-closure absence checks and before declaration join/CFG
    validation. -/
private def validateInvariantRootStepsPresenceV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant then
      match callable.invariantSteps with
      | some _ => pure ()
      | none => return ← err .badCfg
  pure ()

/-- SPEC §8 bounded direct-op subset for invariant roots. After generic
    CFG/op typing, reject direct logical-state writes, context reads,
    commitment creation, event emission, external calls, and scheduling.
    StateLoad remains allowed; the transitive pureFn closure op allowlist is a
    separate slice. -/
private def validateInvariantRootDirectOpsV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    if callable.kind == .invariant then
      for block in callable.blocks do
        for instr in block.instructions do
          match instr.op with
          | .stateStore _ _ => return ← err .badCfg
          | .contextRead _ => return ← err .badCfg
          | .commit _ => return ← err .badCfg
          | .emit _ _ _ => return ← err .badCfg
          | .externalCall _ _ _ => return ← err .badCfg
          | .schedule _ _ _ => return ← err .badCfg
          | _ => pure ()
  pure ()

/-- Compute exact transitive invariant-closure membership over `Op.PureCall`
    edges (SPEC §8). Generic CFG/op typing has already proved every edge is
    in-range and targets a pureFn; this helper rechecks those facts fail-closed.
    Each callable enters the worklist at most once, so traversal is bounded by
    callables plus PureCall instructions even when a cycle is present. The
    reachable call-graph DAG validator consumes this membership next. -/
private def computeInvariantClosureMembershipV1
    (callables : Array CallableV1) :
    Except SemanticWireErrorV1 (Array Bool) := do
  let mut members := Array.mk (List.replicate callables.size false)
  let mut worklist : Array Nat := #[]
  for index in [:callables.size] do
    match callables[index]? with
    | none => return ← err .badCfg
    | some callable =>
        if callable.kind == .invariant then
          members := members.set! index true
          worklist := worklist.push index
  let mut cursor : Nat := 0
  while cursor < worklist.size do
    let callerIndex := worklist[cursor]!
    cursor := cursor + 1
    match callables[callerIndex]? with
    | none => return ← err .badCfg
    | some caller =>
        for block in caller.blocks do
          for instr in block.instructions do
            match instr.op with
            | .pureCall calleeId _ =>
                let calleeIndex := calleeId.toNat
                match callables[calleeIndex]? with
                | none => return ← err .badCfg
                | some callee =>
                    unless callee.kind == .pureFn do
                      return ← err .badCfg
                    unless members[calleeIndex]! do
                      members := members.set! calleeIndex true
                      worklist := worklist.push calleeIndex
            | _ => pure ()
  pure members

/-- A pureFn carries invariant fuel metadata iff it is transitively reachable
    from an invariant root through `Op.PureCall` (SPEC §8). Presence is checked
    here after complete generic CFG/op validation; reachable call-graph DAG
    and closure-CFG acyclicity validation run next, while op allowlists and
    exact checked step values remain separate slices. Other callable-kind
    presence rules remain in the earlier signature gates. -/
private def validatePureFnInvariantClosureMembershipV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let members ← computeInvariantClosureMembershipV1 callables
  for index in [:callables.size] do
    match callables[index]? with
    | none => return ← err .badCfg
    | some callable =>
        if callable.kind == .pureFn then
          let hasSteps := match callable.invariantSteps with
            | some _ => true
            | none => false
          unless hasSteps == members[index]! do
            return ← err .badCfg
  pure ()

/-- Reject cycles in the reachable invariant-closure `Op.PureCall` graph
    (SPEC §8). Kahn traversal is restricted to exact closure members, counts
    duplicate static edges independently, and processes each member once.
    Generic CFG/op typing and exact membership already ran; all edge facts are
    rechecked fail-closed. Unreachable pureFn cycles are outside this gate.
    Closure-CFG back edges and exact step computation remain separate. -/
private def validateInvariantClosureCallGraphDagV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let members ← computeInvariantClosureMembershipV1 callables
  let callableCount := callables.size
  let mut indegree := Array.mk (List.replicate callableCount 0)
  let mut adjacency : Array (Array Nat) :=
    Array.mk (List.replicate callableCount #[])
  let mut memberCount : Nat := 0
  for callerIndex in [:callableCount] do
    if members[callerIndex]! then
      memberCount := memberCount + 1
      match callables[callerIndex]? with
      | none => return ← err .badCfg
      | some caller =>
          for block in caller.blocks do
            for instr in block.instructions do
              match instr.op with
              | .pureCall calleeId _ =>
                  let calleeIndex := calleeId.toNat
                  match callables[calleeIndex]? with
                  | none => return ← err .badCfg
                  | some callee =>
                      unless callee.kind == .pureFn && members[calleeIndex]! do
                        return ← err .badCfg
                      adjacency := adjacency.set! callerIndex
                        (adjacency[callerIndex]!.push calleeIndex)
                      indegree := indegree.set! calleeIndex
                        (indegree[calleeIndex]! + 1)
              | _ => pure ()
  let mut ready : Array Nat := #[]
  for index in [:callableCount] do
    if members[index]! && indegree[index]! == 0 then
      ready := ready.push index
  let mut cursor : Nat := 0
  let mut processed : Nat := 0
  while cursor < ready.size do
    let callerIndex := ready[cursor]!
    cursor := cursor + 1
    processed := processed + 1
    for calleeIndex in adjacency[callerIndex]! do
      let count := indegree[calleeIndex]!
      if count == 0 then return ← err .badCfg
      let next := count - 1
      indegree := indegree.set! calleeIndex next
      if next == 0 then ready := ready.push calleeIndex
  unless processed == memberCount do return ← err .badCfg
  pure ()

/-- Every callable in an invariant closure must have an acyclic CFG (SPEC §8).
    Generic per-callable loopBounds validation has already established exact
    back-edge metadata; this post-membership gate rejects any actual back edge
    in a closure member while leaving unreachable pureFn bounded loops under
    the generic contract. Bounded by callables plus CFG successor edges. -/
private def validateInvariantClosureCfgAcyclicV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let members ← computeInvariantClosureMembershipV1 callables
  for index in [:callables.size] do
    if members[index]! then
      match callables[index]? with
      | none => return ← err .badCfg
      | some callable =>
          unless (cfgBackEdges callable.blocks callable.blocks.size).isEmpty do
            return ← err .badCfg
  pure ()

/-- A pureFn in an invariant closure cannot read or write logical state
    (SPEC §8). Generic CFG/op typing and closure graph/CFG acyclicity have
    already run. Invariant roots remain allowed to use StateLoad directly, and
    unreachable pureFns remain outside this closure-only restriction. -/
private def validateInvariantClosurePureFnOpsV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let members ← computeInvariantClosureMembershipV1 callables
  for index in [:callables.size] do
    if members[index]! then
      match callables[index]? with
      | none => return ← err .badCfg
      | some callable =>
          if callable.kind == .pureFn then
            for block in callable.blocks do
              for instr in block.instructions do
                match instr.op with
                | .stateLoad _ => return ← err .badCfg
                | .stateStore _ _ => return ← err .badCfg
                | _ => pure ()
  pure ()

/-- Every present invariant fuel value is bounded by the schema-fixed 10M
    intrinsic ceiling (SPEC §8). This does not compute expected steps; exact
    closure membership has already been checked. The structure pipeline calls
    it after complete per-callable CFG and closure validation and before
    requirements. -/
private def validateInvariantStepsIntrinsicCeilingV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    match callable.invariantSteps with
    | none => pure ()
    | some steps =>
        unless steps ≤ maxInvariantStepsV1 do return ← err .badCfg
  pure ()

/-- Stable observable subphases for the CFG/invariant segment of structure
    validation. This is not serialized and does not change the public wire
    error contract; it lets tests distinguish precedence when multiple phases
    intentionally collapse to `.badCfg`. -/
inductive CfgInvariantValidationPhaseV1
  | cfg
  | invariantClosure
  | invariantFuel
  deriving BEq, Repr

/-- Internal phase plus the unchanged public wire error. The production
    structure validator consumes this exact result and erases only `phase`. -/
structure CfgInvariantValidationFailureV1 where
  phase : CfgInvariantValidationPhaseV1
  error : SemanticWireErrorV1
  deriving BEq, Repr

private def liftCfgInvariantValidationPhaseV1
    (phase : CfgInvariantValidationPhaseV1)
    (result : Except SemanticWireErrorV1 Unit) :
    Except CfgInvariantValidationFailureV1 Unit :=
  match result with
  | .ok () => .ok ()
  | .error error => .error { phase, error }

/-- Runs the exact stable §6.2 segment used by the structure gate: every
    callable's generic CFG/op validation, then invariant closure restrictions,
    then intrinsic invariant fuel. Earlier structure phases are prerequisites. -/
def validateCfgInvariantPhasesV1 (data : SemanticProgramDataV1) :
    Except CfgInvariantValidationFailureV1 Unit := do
  for callable in data.callables do
    liftCfgInvariantValidationPhaseV1 .cfg
      (validateCallableCfgShape callable data.types.size data.types data)
  liftCfgInvariantValidationPhaseV1 .invariantClosure
    (validateInvariantRootDirectOpsV1 data.callables)
  liftCfgInvariantValidationPhaseV1 .invariantClosure
    (validatePureFnInvariantClosureMembershipV1 data.callables)
  liftCfgInvariantValidationPhaseV1 .invariantClosure
    (validateInvariantClosureCallGraphDagV1 data.callables)
  liftCfgInvariantValidationPhaseV1 .invariantClosure
    (validateInvariantClosureCfgAcyclicV1 data.callables)
  liftCfgInvariantValidationPhaseV1 .invariantClosure
    (validateInvariantClosurePureFnOpsV1 data.callables)
  liftCfgInvariantValidationPhaseV1 .invariantFuel
    (validateInvariantStepsIntrinsicCeilingV1 data.callables)

/-- InvariantDecl rows correspond one-to-one with invariant callables in the
    latter's filtered source order (SPEC §6): exact callableId, invariant kind,
    and name. Table-id and callableId range checks run in earlier phases. -/
private def validateInvariantDeclarationJoinV1 (callables : Array CallableV1)
    (invariants : Array InvariantDeclV1) : Except SemanticWireErrorV1 Unit := do
  let mut invariantCallableIds : Array CallableIdV1 := #[]
  for callable in callables do
    if callable.kind == .invariant then
      invariantCallableIds := invariantCallableIds.push callable.id
  unless invariants.size == invariantCallableIds.size do
    return ← err .badCfg
  let mut index : Nat := 0
  for invariant in invariants do
    match invariantCallableIds[index]? with
    | none => return ← err .badCfg
    | some expectedCallableId =>
        unless invariant.callableId == expectedCallableId do
          return ← err .badCfg
        match callables[expectedCallableId.toNat]? with
        | some callable =>
            match callable.kind, callable.name with
            | .invariant, some name =>
                unless invariant.name == name do
                  return ← err .badCfg
            | _, _ => return ← err .badCfg
        | none => return ← err .badCfg
    index := index + 1
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

/-- SemanticProgram root identity shape (SPEC §6). Common QualifiedName
    intentionally permits one component, but a program root is module identity
    plus declaration name and therefore requires at least two. This helper is
    called before encoder size gates and again as structure step 0 so mixed-
    invalid values have stable `.badScalar` precedence. -/
private def validateProgramQualifiedNameShapeV1 (name : QualifiedName) :
    Except SemanticWireErrorV1 Unit := do
  unless 2 ≤ name.components.toArray.size do return ← err .badScalar
  pure ()

/-- Post-wire structural subset: program root qualifiedName has at least two
    components, table IDs, shallow declaration refs, type-shape/FieldSpec/
    Map-key (SPEC §5), canonical valueBytes (Constant /
    Op.Literal / SwitchCase), callable kind/name presence, initializer
    cardinality, per-callable CFG shape + reachability from entry
    + Switch cases nonempty with unique `(typeId,valueBytes)` constants
    + jump/branch/switch target arg arity == target block params
    + loopBounds back-edge coverage
    + per-callable Emit/ExternalCall/Schedule EffectId contiguous assignment
      in BlockId/instruction order
    + ValueId SSA definition-table / exactly-once / use-existence
    + dominance-of-use
    + def-site TypeId range (block params + instruction result ValueDefs)
    + terminator typing (branch cond Bool, switch case == scrutinee,
      target arg types == target block param types positional,
      return (some v) == result type, Term.Revert error/args exact join)
    + per-op type/result contract (§4.3/§5.1: literal/constant/stateLoad/
      construct/fieldGet/indexGet/unary/binary/pureCall result presence and
      exact result/operand types; Op.FieldSet full contract — base Struct,
      fieldIndex in range, type(value) == field.typeId, result.typeId ==
      type(base); Op.VariantTag full contract — base Enum/Option,
      result.typeId == unique UInt32 TypeId; Op.VariantPayload static
      Enum/Option index/result contract; Op.IndexSet exact Array/Bytes/Map
      operand/result contract; Op.CheckedCast exact UInt/Int source/
      destination/result contract; Op.StateStore exact state lookup/value type/
      void-result contract; Op.Assert exact Bool/error/args/void-result contract;
      Op.Emit exact EventDecl/args/void-result contract; presence-only result
      for ContextRead/Commit; ExternalCall/Schedule void-result plus
      at-least-two-component callee shape)
    (SPEC §6.2 CFG layers), requirement/predicate order
    (SPEC-SEM-WIRE-001 §4.5/§5/§6/§6.2 + CAP ranks).
    Empty tables and empty requirements remain legal. Walks callable bodies
    only for valueBytes sites and CFG shape/reachability/arity/loopBounds/SSA
    def-table/dominance-of-use/def-site TypeId range/terminator typing/per-op
    type/result contract (incl. value-producing result-presence and void-op
    result-presence) — NOT ExternalCall/Schedule argument serializability,
    ContextRead/Commit exact contracts, runtime CheckedCast representability,
    Array/Bytes bounds and Enum tag agreement, TypeKey anonymous ranking/interning, provenance
    inventory join, or ProgramV1 normalizer. -/
def validateSemanticProgramStructureV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  -- 0) Program root identity shape; intentionally precedes every table/ref/
  --   type/CFG/requirement gate.
  validateProgramQualifiedNameShapeV1 data.qualifiedName
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
  -- 3) Type-shape / FieldSpec catalog / Map-key legality, then named
  --   Struct/Enum TypeDecl exact-name uniqueness (SPEC §5/§6).
  validateTypesStructureV1 data.types
  validateNamedTypeNameUniquenessV1 data.types
  -- 4) Canonical valueBytes (Constant / Op.Literal / SwitchCase)
  validateConstantsValueBytesV1 data.types data.constants
  validateCallablesValueBytesV1 data.types data.callables
  -- 4.2) Constant, logicalState, EventDecl/ErrorDecl, and per-declaration
  --   interface-field names form one same-error `.duplicate` phase after
  --   canonical values.
  --   Calls retain table/field order, but the closed public error value
  --   intentionally exposes no intra-phase rank.
  validateConstantNameUniquenessV1 data.constants
  validateLogicalStateNameUniquenessV1 data.logicalState
  validateEventNameUniquenessV1 data.events
  validateErrorNameUniquenessV1 data.errors
  validateInterfaceFieldNameUniquenessV1 data.events data.errors
  -- 4.25) Callable name presence/uniqueness and per-callable parameter names.
  validateCallableKindNamePresenceV1 data.callables
  validateCallableNameUniquenessV1 data.callables
  validateCallableParameterNameUniquenessV1 data.callables
  -- 4.3) Special callable signatures: initializer is zero-or-one with a
  --   Unit/public result; invariant has zero params, empty loopBounds, a
  --   Bool/public result, and one source-order exact InvariantDecl row;
  --   initializer/entry/view always carry no invariantSteps metadata, as do
  --   all pureFns when no invariant root exists; every invariant root carries
  --   some steps metadata. These checks still precede per-callable CFG
  --   validation.
  validateInitializerCardinalityV1 data.callables
  validateInitializerResultShapeV1 data.types data.callables
  validateInvariantResultShapeV1 data.types data.callables
  validateInvariantParameterShapeV1 data.callables
  validateInvariantLoopBoundsShapeV1 data.callables
  validateNonClosureCallableInvariantStepsV1 data.callables
  validateInvariantRootStepsPresenceV1 data.callables
  validateInvariantDeclarationJoinV1 data.callables data.invariants
  -- 4.5–4.75) Generic CFG/op typing → direct root restrictions + exact
  --   transitive pureFn closure membership + reachable call-graph/CFG
  --   acyclicity → intrinsic invariant fuel. The shared helper preserves the
  --   public wire error while exposing the stable subphase to focused tests.
  match validateCfgInvariantPhasesV1 data with
  | .ok () => pure ()
  | .error failure => throw failure.error
  -- 5) Requirement key + predicate order
  validateProgramRequirementsStructure data.requirements

def encodeSemanticProgramDataV1 (p : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 ByteArray := do
  -- Root identity shape has stable precedence over even table-size failures.
  validateProgramQualifiedNameShapeV1 p.qualifiedName
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
