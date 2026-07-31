import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import Std.Data.HashMap

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
  * Root round-trip + SHA-256 hash + provenance envelope encode/decode with
    complete fail-closed join validate (join-gated digest).
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
        · named-prefix rank: all `name=some` named Struct/Enum TypeDecls
          must occupy a contiguous prefix of the `types` table; any named
          declaration after an anonymous declaration is `.nonCanonical`
          (runs before leaf primitive interning and recursive anonymous
          structural-class uniqueness, after type-shape/FieldSpec/Map-key
          legality and shallow reference range)
        · leaf primitive anonymous TypeKeys are unique by exact shape for
          Bool/UInt/Int/Principal/Unit/Bytes/Field (`.nonCanonical`)
        · anonymous `.array`/`.map`/`.option` are interned by exact recursive
          child structural **class** identity (fixed-size structural-class
          signatures built from children's structural class IDs, not the
          final child TypeId and not nested child keys, so two structurally-
          equivalent child graphs receive the same class and the per-TypeId
          state stays constant-size — no Θ(n²) nested-byte expansion);
          signatures are interned to sequential class IDs via a `Std.HashMap`
          used only for lookup/insert (never iterated), with hash collisions
          resolved by exact byte equality; Named Struct/Enum are terminal
          `named(reserved TypeId)` anchors that terminate class expansion and
          keep two same-shape named declarations distinct; anonymous-container
          cycles that pass through no named anchor are rejected
          (`.nonCanonical`), via a bounded iterative gray/black DFS over the
          types table (explicit stack, no host map iteration, no nested
          structural rescans — only a constant number of bounded linear
          passes plus a private O(n log n) class-ID sort, no unbounded recursion
          or stack-depth risk). This slice rejects only
          anonymous-container cycles without a named anchor. The complete
          SPEC §5 cycle condition — that every recursive cycle must
          simultaneously pass through a reserved named key and an anonymous
          `Option` — is closed by the combination of this helper (rejects
          cycles with no named anchor) and a later `namedBodyCycle` subphase
          that removes every `Option` node and requires the induced TypeId
          graph to be acyclic (rejects cycles with no `Option`). The
          structural-class signature is an internal fixed-size
          equality token, **not** the SPEC canonical unsigned-lexicographic
          anonymous TypeKey/ranking bytes. Named contiguous-prefix rank is
          enforced above; anonymous canonical rank/order and the remaining
          full TypeKey closure (reachability/usage/provenance) remain
          deferred, but the named-body cycle condition itself is no longer
          deferred.
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
    - SPEC §6 declaration/field/parameter/invariant name grammar after
      uniqueness + InvariantDecl join and before CFG: every present name is
      validated by the shared SPEC-COMMON identifier component rule
      (`validateIdentifierComponent`: Unicode 17 NFC, UTF-8 1..240, not exact
      `_`, `Lean.isIdFirst`/`Lean.isIdRest`) via structure authority
      (`.badScalar`). Covers named Struct/Enum TypeDecl names, struct fields,
      enum variants, constants, logicalState, event/error declarations and
      their interface fields, named callables (`some` only; initializer
      `none` is not rejected), callable parameters, and InvariantDecl names.
      Transport `decodeString` remains NFC-only on bare strings; full
      identifier grammar is not applied at transport decode for those fields.
    - post-CFG transitive `Op.PureCall` reachability requires
      `invariantSteps=some` exactly for pureFns in an invariant closure and
      `none` for every other pureFn; the reachable closure call graph must be a
      DAG (bounded Kahn traversal; unreachable cycles remain out of scope), and
      every closure-member CFG must contain no back edge (`.badCfg`)
    - post-CFG invariant roots reject direct `Op.StateStore`, `Op.ContextRead`,
      `Op.Commit`, `Op.Emit`, `Op.ExternalCall`, and `Op.Schedule` while
      retaining direct `Op.StateLoad` (`.badCfg`)
    - post-CFG exact reachable invariant-closure pureFns reject `Op.StateLoad`,
      `Op.StateStore`, `Op.ContextRead`, `Op.Commit`, `Op.Emit`,
      `Op.ExternalCall`, and `Op.Schedule`; invariant-root direct StateLoad and
      unreachable pureFns retain their separate documented scope (`.badCfg`)
    - post-CFG `computedInvariantSteps` is exact over the closure DAG: checked
      local block/instruction/terminator cost plus every static PureCall
      occurrence, including duplicates, via a reverse Kahn pass; carried
      metadata must match and the computed value must stay ≤10M (`.badCfg`)
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
  * Provenance engineering subset (SPEC §6.1 fail-closed join for complete
    carriers; S2 Counter path produces accepted provenance via NormalizeV1
    authoritative APIs that rebuild from ValidatedSourceV1):
    - `encodeSemanticProvenanceV1` / `decodeSemanticProvenanceV1`: closed
      envelope transport + re-encode identity only.
    - `validateSemanticProvenanceJoinV1` / `semanticProvenanceDigestJoinV1`:
      **low-level caller-expected join helpers only** (not SPEC authority).
      Caller supplies expectedSourceHash + expectedOriginMap; checks schema,
      sourceModule prefix of sourceIdentity, qualifiedName, hash equality,
      exact originMap equality, inventory membership, entity coverage.
      Incomplete/foreign/wrong → `.badProvenance`. Production authority is
      `NormalizeV1.validateSemanticProvenanceV1` (source+path+spans rebuild
      inventory; never caller inventory; re-normalize + rebuild).
  * Not yet: recursive/full TypeKey closure beyond the enforced named-prefix
    rank, full anonymous ranking/reachability (the SPEC canonical unsigned-
    lexicographic anonymous TypeKey/ranking bytes), and usage
    closure/missing/unreferenced rejection, full formal provenance
    inventory construction from contained frontend, product
    CheckV1/compile/CLI wiring, op type contracts beyond
    the §5.1 value-producing subset. (Structural-class equality for anonymous
    `.array`/`.map`/`.option` and anonymous-container-cycle rejection (without
    a named anchor) are now covered via fixed-size structural-class signatures;
    CFG shape + reachability from entry,
    jump/branch/switch target arg arity == target block params, loopBounds
    back-edge coverage, per-callable EffectId contiguous canonical assignment,
    per-callable ValueId canonical assignment (parameters, then all block
    parameters, then all instruction results) / use-existence,
    dominance-of-use, def-site TypeId range, terminator
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
    args/void-result contract, the §5.1 ContextRead same-key result-TypeId
    consistency pass (one exact SchemaId key → one Instruction.result TypeId
    across the whole program, `.badCfg`, `.cfg` phase after generic CFG/op
    typing and before invariant closure/fuel/requirements), presence-only
    local result for ContextRead, exact Commit operand/result TypeId equality,
    and void-op result-presence plus the at-least-two-component callee shape
    for ExternalCall/Schedule are now covered; ContextRead and Commit each have
    a closed exact requirement row. ExternalCall/Schedule argument serializability,
    recursive/full TypeKey closure beyond the enforced named-prefix rank,
    full anonymous
    ranking/reachability (SPEC canonical unsigned-lexicographic anonymous
    TypeKey/ranking bytes), and usage
    closure/missing/unreferenced rejection, product
    wire remain out of scope pending later slices. The complete SPEC §5
    cycle condition is now closed by `recursiveAnonymous` + `namedBodyCycle`.)
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

/-- v1 Field catalog sole entry id (SPEC-SEM-WIRE-001 §5). -/
def bn254FrFieldIdV1 : String := "proof-forge.field.bn254-fr.v1"

/-- Sole statically admitted v1 ContextRead key. -/
def unixTimeSecondsContextKeyV1 : SchemaId :=
  { value := "proof-forge.context.unix-time-seconds.v1" }

/-- Requirement identity bound to the sole v1 ContextRead key. -/
def unixTimeSecondsContextRequirementIdV1 : String :=
  "context.unix-time-seconds"

/-- Exact requirement identity contributed by every v1 Commit operation. -/
def commitmentDisclosureRequirementIdV1 : String :=
  "disclosure.commitment"

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

/-- Exact requirement row for the sole v1 ContextRead key. -/
def unixTimeSecondsContextRequirementV1 : Except String RequirementRequestV1 := do
  let digest ← domainSeparatedSha256 "pf.context-read-requirement.v1"
    unixTimeSecondsContextRequirementIdV1.toUTF8
  pure {
    id := unixTimeSecondsContextRequirementIdV1
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
    declaration refs → type-shape/FieldSpec/Map-key → named TypeDecl contiguous-
    prefix rank → primitive leaf anonymous TypeKey uniqueness → recursive
    anonymous container structural-class uniqueness (anonymous-container-cycle
    rejection without a named anchor) → named TypeDecl-name
    uniqueness → canonical valueBytes (Constant / Op.Literal / SwitchCase) →
    grouped same-error duplicate phase
    {Constant-name, logicalState-name, EventDecl/ErrorDecl-name,
    per-declaration interface-field-name uniqueness} → callable kind/name
    presence → named
    callable uniqueness → per-callable parameter-name uniqueness →
    initializer cardinality → initializer Unit/public result → invariant
    Bool/public result → invariant zero parameters → invariant empty loopBounds
    → InvariantDecl exact join → declaration/field/parameter/invariant name
    NFC + common identifier grammar (`.badScalar`) → CFG → requirements.
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

/-- Collect every ValueId definition site in the three global allocation
    passes required by SPEC §6: callable params first; then every block param
    in BlockId/array order; then every instruction result in
    BlockId/instruction order. This is deliberately not per-block
    param/result interleaving. CFG step b has already established
    `block.id == array index` before production consumes this order. Returns
    `(valueId, definingBlockId)` pairs. Bounded, non-recursive. -/
def collectValueDefSites (c : CallableV1) : Array (ValueIdV1 × BlockIdV1) :=
  Id.run do
    let mut sites : Array (ValueIdV1 × BlockIdV1) := #[]
    let entryBlock := c.entryBlock
    for p in c.params do
      sites := sites.push (p.valueId, entryBlock)
    for b in c.blocks do
      for bp in b.params do
        sites := sites.push (bp.valueId, b.id)
    for b in c.blocks do
      for instr in b.instructions do
        match instr.result with
        | some vdef => sites := sites.push (vdef.valueId, b.id)
        | none => pure ()
    pure sites

/-- Enforce canonical per-callable ValueId assignment over the exact
    `collectValueDefSites` traversal: encountered IDs are `0,1,...,n-1`.
    This single O(definitions)-time/O(1)-extra-space check subsumes duplicate,
    gap, wrong-start, and reordered-definition rejection. It does not claim
    whole-CFG validation is linear; later ValueId lookups retain their existing
    bounded complexity. Any mismatch → `.badCfg`. -/
def checkValueIdCanonicalAssignment
    (defSites : Array (ValueIdV1 × BlockIdV1)) :
    Except SemanticWireErrorV1 Unit := do
  let mut next : Nat := 0
  for (valueId, _) in defSites do
    unless valueId.toNat == next do
      return ← err .badCfg
    next := next + 1
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

/-- Per-callable ValueId SSA def-table: canonical contiguous assignment plus
    use-existence. Builds `defSites` once via the SPEC §6 three-pass collector,
    validates `0..n-1`, then checks uses against the same array. Canonical
    assignment subsumes exactly-once. Dominance remains step g. -/
def validateCallableValueIdSsa (c : CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let defSites := collectValueDefSites c
  checkValueIdCanonicalAssignment defSites
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

/-- Collect every ValueId → TypeId definition in the same three global
    SPEC §6 passes as `collectValueDefSites`: callable params; all block params;
    all instruction results. Bounded and non-recursive. Production reaches this
    only after step-f canonical assignment; no duplicate check is repeated. -/
def collectValueTypeDefs (c : CallableV1) : Array (ValueIdV1 × TypeIdV1) :=
  Id.run do
    let mut defs : Array (ValueIdV1 × TypeIdV1) := #[]
    for p in c.params do
      defs := defs.push (p.valueId, p.typeId)
    for b in c.blocks do
      for bp in b.params do
        defs := defs.push (bp.valueId, bp.typeId)
    for b in c.blocks do
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
    and carries no result. `Op.ContextRead` carries result presence here plus
    the §5.1 same-key result-TypeId global consistency pass (a separate
    post-CFG gate), followed by its closed key/result/requirement catalog.
    `Op.Commit` requires its operand to resolve and its result TypeId to equal
    the operand TypeId; its exact disclosure requirement row is checked after
    generic requirement validation.
    ExternalCall/
    Schedule MUST carry `result := none` and a callee with at least two
    qualified-name components; a spurious result, short callee, or missing
    result on a value-producing op is an invalid Core trap → `.badCfg`. All
    step j failures → `.badCfg`. Bounded, non-recursive, total. Out of scope:
    ExternalCall/Schedule argument serializability, recursive/full TypeKey
    closure/ranking/reachability,
    provenance join, normalizer, product wire. -/

/-- The unique TypeId whose shape is `.uint 32`, if exactly one exists.
    Bounded, non-recursive. Like `uint8TypeId` (and unlike first-match
    `boolTypeId`), this defensive resolver returns `some` only when exactly
    one `.uint 32` declaration is present, and `none` otherwise. The earlier
    primitive anonymous TypeKey gate is authoritative: duplicates fail there
    as `.nonCanonical` before step j. This helper still fails closed for direct
    internal use; recursive/full TypeKey closure and ranking remain pending. -/
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
    structurally interned UInt8 TypeId. The earlier primitive anonymous
    TypeKey gate rejects duplicates as `.nonCanonical`; this defensive helper
    still returns `none` for zero or duplicate matches. -/
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
    result.typeId == the unique UInt32 TypeId). Duplicate anonymous UInt32
    declarations are rejected earlier by primitive TypeKey interning as
    `.nonCanonical`; step j reports `.badCfg` for a missing UInt32 closure
    type, missing result, non-Enum/Option base, or wrong result type. The remaining
    `Op.VariantPayload` carries its static §5.1 contract (Enum variant/payload
    indices or Option `(1,0)`, with the selected payload/element result type).
    `Op.IndexSet` and `Op.CheckedCast` carry their exact static contracts.
    `Op.ContextRead` MUST carry `result := some _` presence-only here and
    additionally
    carries the §5.1 same-key result-TypeId consistency pass (a separate
    post-CFG global catalog gate). `Op.Commit` resolves its operand and requires
    `result.typeId == type(value)`; its exact disclosure requirement binding
    remains deferred to later slices.
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
  -- Helper: require result present for the value-producing families whose
  --   local op branch here is presence-only (ContextRead). SPEC
  --   §4.3/§5.1 mandates a result; a missing result is `.badCfg`.
  --   `Op.ContextRead` additionally carries the §5.1 same-key result-TypeId
  --   global closed-catalog pass (a separate post-CFG gate), including exact
  --   key/result shape and later requirement binding. FieldSet, VariantTag,
  --   VariantPayload, IndexSet, and CheckedCast have their own exact static
  --   contracts below.
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
  -- Op.Commit (SPEC-SEM-WIRE-001 §5.1): the operand ValueId MUST resolve and
  --   the result TypeId MUST exactly equal type(value). Every structure-valid
  --   TypeShape has canonical value bytes, so this branch deliberately does
  --   not reuse the narrower Eq/Ne `serializableType` predicate. The exact
  --   disclosure requirement row is enforced after generic requirements.
  | .commit value =>
      let valueT ← requireOperandType value
      requireResult valueT
  -- ContextRead carries presence-only local typing; its exact key/type and
  --   requirement binding are enforced by the later closed-catalog passes.
  | .contextRead _ => requireResultPresent

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
  -- c.5) jump/branch/switch target arg arity == target block params.
  --   Only in-range targets reach this step; step c owns OOR. Positional
  --   argument TypeId equality is checked later by terminator typing (step i).
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
  -- f) Canonical ValueId assignment + use-existence (SPEC §6/§6.2):
  --   callable params, then all block params, then all instruction results
  --   must be exactly `0..n-1`, independently per callable. Build defSites
  --   once and reuse for step g; build defTypes once for h–j.
  let defSites := collectValueDefSites c
  checkValueIdCanonicalAssignment defSites
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
  --   CheckedCast have exact static contracts; `Op.ContextRead` carries
  --   result presence here plus the §5.1 same-key result-TypeId global
  --   consistency and closed exact key/anonymous UInt64 catalog in a separate
  --   post-CFG gate; its exact requirement row is checked after generic
  --   requirement structure. `Op.Commit` resolves its operand and requires
  --   result.typeId == type(value); exact disclosure requirement binding is
  --   deferred. All failures → `.badCfg`. Reuses `defTypes`
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

/-- SPEC §5 named TypeDecl contiguous-prefix rank: all `name=some` named
    Struct/Enum declarations must occupy a contiguous prefix of the `types`
    table (indices `0 .. namedCount-1`). Any named declaration appearing
    after an anonymous declaration is `.nonCanonical`. This is the
    `namedPrefix` subphase of `validateTypeKeyPhasesV1`, ordered before the
    `primitiveLeaf` and `recursiveAnonymous` subphases; it shares the public
    `.nonCanonical` wire error while the phase seam makes precedence
    observable. Runs only after table id/index, shallow reference range, and
    type-shape/Map-key legality succeed. Named-name uniqueness, canonical
    valueBytes, callable signature, and requirements are later successors.
    The SPEC canonical anonymous sort/rank bytes and usage closure remain
    deferred; named-body cycle legality is now enforced by a later
    `namedBodyCycle` subphase (after `recursiveAnonymous`), not here. The
    scan is a single forward pass with
    O(n) time and O(1) extra space: once an anonymous declaration is seen, a
    `seenAnonymous` flag is set and any subsequent `name=some` declaration is
    rejected. -/
private def validateNamedPrefixRankV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let mut seenAnonymous := false
  for decl in types do
    match decl.name with
    | some _ =>
      if seenAnonymous then
        return ← err .nonCanonical
    | none =>
      seenAnonymous := true
  pure ()

/-- Leaf primitive anonymous TypeKeys are structurally interned (SPEC §5):
    Bool, width-specific UInt/Int, Principal, Unit, length-specific Bytes, and
    the exact catalog Field shape each have at most one TypeId. Their existing
    canonical TypeShape wire is injective for this leaf subset, so a private
    byte sort detects duplicates without changing public table order. This is
    the `primitiveLeaf` subphase of `validateTypeKeyPhasesV1`, ordered before
    the `recursiveAnonymous` subphase; both report the same public
    `.nonCanonical` wire error while the phase seam makes precedence
    observable. Full anonymous rank/reachability remains pending. Runs only
    after every declaration shape/catalog check succeeds. -/
private def validatePrimitiveAnonymousTypeKeyUniquenessV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let mut keys : Array ByteArray := #[]
  for decl in types do
    let isPrimitive := match decl.shape with
      | .bool | .uint _ | .int _ | .principal | .unit | .bytes _ | .field _ => true
      | .array _ _ | .map _ _ | .option _ | .struct _ | .enum _ => false
    if isPrimitive then
      keys := keys.push (← encodeTypeShapeV1 decl.shape)
  let sorted := keys.qsort fun left right =>
    compareByteArrayLex left right == .lt
  let mut index : Nat := 1
  while index < sorted.size do
    if compareByteArrayLex sorted[index - 1]! sorted[index]! == .eq then
      return ← err .nonCanonical
    index := index + 1
  pure ()

/-- Fixed-size internal structural-class signature builder (SPEC §5
    engineering subset). This is **not** the SPEC canonical unsigned-
    lexicographic anonymous TypeKey/ranking bytes; that ranking/order is a
    separate normalizer concern and remains deferred. The signature is a
    deterministic, injective, fixed-size byte encoding used only for exact
    structural-class equality and interning, so the per-TypeId state stays
    constant size regardless of recursion depth (avoiding the Θ(n²)
    nested-byte expansion of inlining full child structural keys). Tag framing
    follows the SPEC `typeKey` shape: `u16le(tagLen) || tag || u32le(fieldCount)
    || concat(u32le(fieldLen) || field)`; the Field SchemaId field uses
    canonical length-prefixed UTF-8 bytes (`u32le len || utf8`) matching
    `encodeString` framing (the outer field length wraps it again).

    Signatures are:
    · primitive leaves: tag + exact shape params (uint/int width, bytes
      length, field SchemaId + modulusBE);
    · named Struct/Enum: `tag("named", [u32le reservedId])` — a terminal
      anchor that does not recurse into the named body, so two same-shape
      named declarations keep distinct reserved identity;
    · anonymous `.array`/`.map`/`.option`: tag + child **structural class
      IDs** (not final child TypeIds, not nested child keys) plus the
      container's own shape params (Array length). Two different child TypeIds
      whose reachable structure is identical receive the same child class ID
      and therefore the same container signature/class. -/
private def structuralClassSignatureTag (tag : String)
    (fields : Array ByteArray) : ByteArray := Id.run do
  let tagBytes := tag.toUTF8
  let tagLen := encodeU16le (UInt16.ofNat tagBytes.size)
  let fieldCount := encodeU32le (UInt32.ofNat fields.size)
  let mut out := (tagLen.append tagBytes).append fieldCount
  for field in fields do
    out := out.append ((encodeU32le (UInt32.ofNat field.size)).append field)
  pure out

private def lengthPrefixedUtf8 (s : String) : ByteArray :=
  let raw := s.toUTF8
  (encodeU32le (UInt32.ofNat raw.size)).append raw

/-- Fixed-size signature for a terminal (non-anonymous-container) node. Named
    Struct/Enum and primitive leaves resolve here without recursion. -/
private def terminalStructuralSignature (decl : TypeDeclV1) : ByteArray :=
  match decl.shape with
  | .bool => structuralClassSignatureTag "bool" #[]
  | .uint w => structuralClassSignatureTag "uint" #[encodeU16le w]
  | .int w => structuralClassSignatureTag "int" #[encodeU16le w]
  | .principal => structuralClassSignatureTag "principal" #[]
  | .unit => structuralClassSignatureTag "unit" #[]
  | .bytes len => structuralClassSignatureTag "bytes" #[encodeU32le len]
  | .field spec =>
      structuralClassSignatureTag "field"
        #[lengthPrefixedUtf8 spec.id.value, spec.modulusBE]
  | .struct _ | .enum _ =>
      -- Named Struct/Enum: terminal anchor keyed by reserved TypeId only.
      structuralClassSignatureTag "named" #[encodeU32le (UInt32.ofNat decl.id.toNat)]
  | _ => structuralClassSignatureTag "unknown" #[]

/-- Children TypeIds that an anonymous container recurses through. Named
    Struct/Enum and primitive leaves have no recursive children: their
    signature is terminal. -/
private def anonymousContainerChildren (shape : TypeShapeV1) :
    Option (Array TypeIdV1) :=
  match shape with
  | .array element _ => some #[element]
  | .map key value => some #[key, value]
  | .option element => some #[element]
  | _ => none

/-- Compose a fixed-size anonymous-container signature from black children's
    structural class IDs plus the container's own shape params. The signature
    is constant-size (tag + one u32 per child class ID + Array length); it
    never inlines nested child keys. -/
private def anonymousContainerSignature (shape : TypeShapeV1)
    (childClassIds : Array UInt32) : ByteArray := Id.run do
  match shape with
  | .array _ length =>
      let mut fieldBytes : Array ByteArray := #[]
      for cid in childClassIds do fieldBytes := fieldBytes.push (encodeU32le cid)
      fieldBytes := fieldBytes.push (encodeU32le length)
      pure (structuralClassSignatureTag "array" fieldBytes)
  | .map _ _ =>
      let mut fieldBytes : Array ByteArray := #[]
      for cid in childClassIds do fieldBytes := fieldBytes.push (encodeU32le cid)
      pure (structuralClassSignatureTag "map" fieldBytes)
  | .option _ =>
      let mut fieldBytes : Array ByteArray := #[]
      for cid in childClassIds do fieldBytes := fieldBytes.push (encodeU32le cid)
      pure (structuralClassSignatureTag "option" fieldBytes)
  | _ => pure (structuralClassSignatureTag "unknown" #[])

/-- Is this TypeDecl a named Struct/Enum (terminal structural anchor)? -/
private def isNamedStructOrEnum (decl : TypeDeclV1) : Bool :=
  match decl.shape with
  | .struct _ | .enum _ => decl.name.isSome
  | _ => false

/-- Compute a structural class ID per TypeId (SPEC §5 engineering subset).
    Each TypeId receives a fixed-size structural-class signature:
    · primitive leaves and named Struct/Enum get a terminal signature;
    · anonymous `.array`/`.map`/`.option` get a signature built from their
      children's already-computed structural class IDs (not final child
      TypeIds), so two structurally-equivalent child graphs receive the same
      child class ID and the same container class. Identical signatures are
    interned to a single sequential class ID via a `Std.HashMap` used only for
    lookup/insert (never iterated); hash collisions are resolved by exact
    byte equality (`ByteArray.instBEq`), so distinct signatures never collapse.

    Anonymous-container cycle rejection (SPEC §5): a bounded iterative DFS
    over the types table assigns each TypeId a memoized class ID. Only
    anonymous containers are marked in-progress (gray); primitive leaves and
    named anchors resolve to a terminal signature and become black without
    recursion, so reaching a gray node is always an anonymous-container cycle
    with no named anchor, rejected as `.nonCanonical`. Each node is entered
    and exited at most once (memoization short-circuits re-entry to black);
    there are no nested structural rescans — the DFS visits each node a
    constant number of times and class materialization is one bounded linear
    pass. This class computation uses expected `O(n)` time and `O(n)` space
    (one HashMap lookup/insert per node, constant-size signature composition);
    the consuming validator separately collects class IDs linearly and sorts
    them in `O(n log n)`. There is no host map iteration, unbounded recursion,
    stack-depth risk (explicit stack array), or nested-byte expansion.

    Prerequisites: the production caller has already validated table IDs,
    shallow references, type shapes/FieldSpec/Map-key legality, and primitive
    leaf uniqueness. This helper defensively rejects OOR/cycles but does not
    replace those earlier structure phases.

    Scope: this helper rejects only anonymous-container cycles that pass
    through no named anchor. It does not itself enforce the named-body
    `Option`-cycle condition; a later `namedBodyCycle` subphase removes every
    `Option` node and requires the induced TypeId graph to be acyclic, and
    together with this helper that closes the complete SPEC §5 cycle
    condition (every recursive cycle passes simultaneously through a
    reserved named key and an `Option`). Runs after leaf
    primitive interning. -/
def computeStructuralTypeClassIdsV1 (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 (Array UInt32) := do
  let n := types.size
  let mut color : Array Nat := Array.replicate n 0
  let mut classIds : Array (Option UInt32) := Array.replicate n none
  let mut classes : Std.HashMap ByteArray UInt32 :=
    Std.HashMap.emptyWithCapacity n
  let mut nextClass : UInt32 := 0
  let mut stack : Array (Nat × Nat) := #[]
  let mut root := 0
  while h : root < n do
    if color[root]! == 0 then
      stack := stack.push (0, root)
      while stack.isEmpty == false do
        let (kind, tid) := stack.back!
        stack := stack.pop
        if kind == 1 then
          -- exit: compose anonymous-container signature from black child
          -- class IDs and intern to a class ID.
          match types[tid]? with
          | none => return ← err .badReference
          | some decl =>
            match anonymousContainerChildren decl.shape with
            | none => pure ()
            | some childIds =>
              let mut childClasses : Array UInt32 := #[]
              let mut missing := false
              let mut ci := 0
              while h2 : ci < childIds.size do
                let cid := childIds[ci]
                match classIds[cid.toNat]? with
                | some (some cls) => childClasses := childClasses.push cls
                | _ => missing := true
                ci := ci + 1
              if missing then return ← err .nonCanonical
              let sig := anonymousContainerSignature decl.shape childClasses
              let (existing, updated) := classes.getThenInsertIfNew? sig nextClass
              let cls := existing.getD nextClass
              classes := updated
              if existing.isNone then nextClass := nextClass + 1
              classIds := classIds.set! tid (some cls)
              color := color.set! tid 2
        else
          -- enter
          match color[tid]! with
          | 2 => pure ()  -- memoized
          | 1 => return ← err .nonCanonical  -- anonymous-container cycle
          | _ =>
            match types[tid]? with
            | none => return ← err .badReference
            | some decl =>
              if isNamedStructOrEnum decl then
                let sig := terminalStructuralSignature decl
                let (existing, updated) := classes.getThenInsertIfNew? sig nextClass
                let cls := existing.getD nextClass
                classes := updated
                if existing.isNone then nextClass := nextClass + 1
                classIds := classIds.set! tid (some cls)
                color := color.set! tid 2
              else match anonymousContainerChildren decl.shape with
                | none =>
                  let sig := terminalStructuralSignature decl
                  let (existing, updated) := classes.getThenInsertIfNew? sig nextClass
                  let cls := existing.getD nextClass
                  classes := updated
                  if existing.isNone then nextClass := nextClass + 1
                  classIds := classIds.set! tid (some cls)
                  color := color.set! tid 2
                | some childIds =>
                  color := color.set! tid 1
                  stack := stack.push (1, tid)
                  let mut ci := childIds.size
                  while h3 : ci > 0 do
                    ci := ci - 1
                    stack := stack.push (0, (childIds[ci]!).toNat)
    root := root + 1
  -- Materialize the per-TypeId class ID array (every node is black here).
  let mut out : Array UInt32 := Array.replicate n 0
  let mut i := 0
  while h : i < n do
    match classIds[i]? with
    | some (some cls) => out := out.set! i cls
    | _ => return ← err .nonCanonical
    i := i + 1
  pure out

/-- Recursive anonymous structural-class uniqueness (SPEC §5). Anonymous
    `.array`/`.map`/`.option` are interned by exact recursive child structural
    class identity, not by final child TypeId. Two anonymous containers with
    structurally-equivalent child graphs receive the same structural class;
    a duplicate anonymous container class is rejected as `.nonCanonical`.
    Anonymous-container cycles that pass through no named anchor are rejected
    during class computation (`.nonCanonical`). This helper does not itself
    enforce the named-body `Option`-cycle condition; a later `namedBodyCycle`
    subphase closes the complete SPEC §5 cycle condition. This is the
    `recursiveAnonymous` subphase of
    `validateTypeKeyPhasesV1`, ordered after the `primitiveLeaf` subphase and
    before `namedBodyCycle`; all three report the same public `.nonCanonical`
    wire error while the phase seam makes precedence observable. Runs after
    leaf primitive interning and
    before named-name/canonical-value/signature/requirement phases. -/
private def validateRecursiveAnonymousTypeKeyUniquenessV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let classIds ← computeStructuralTypeClassIdsV1 types
  -- Collect anonymous container class IDs and reject duplicates via a
  -- private sort + adjacent comparison. Public table order is unchanged.
  let mut anonClasses : Array UInt32 := #[]
  let mut i := 0
  while i < types.size do
    match types[i]? with
    | some decl =>
      match decl.shape with
      | .array _ _ | .map _ _ | .option _ =>
        anonClasses := anonClasses.push (classIds[i]!)
      | _ => pure ()
    | none => pure ()
    i := i + 1
  let sorted := anonClasses.qsort fun a b => a < b
  let mut j := 1
  while j < sorted.size do
    if sorted[j - 1]! == sorted[j]! then
      return ← err .nonCanonical
    j := j + 1
  pure ()

/-! ### named-body Option-cycle legality (SPEC §5)

    SPEC §5 requires that every recursive cycle in the type graph pass
    simultaneously through a reserved named Struct/Enum key and an anonymous
    `Option` node. The earlier `recursiveAnonymous` subphase rejects all
    anonymous-container cycles that pass through no named anchor. This slice
    closes the remaining gap: any cycle that passes through a reserved named
    key must also pass through at least one anonymous `Option`.

    Equivalent global algorithm: build the directed graph on TypeIds with an
    edge `u → v` for each child TypeId `v` referenced by a non-`Option`
    declaration `u` where `v` itself is not an `Option` declaration (i.e.
    remove every `.option` node and its incident edges), then require the
    induced subgraph to be acyclic. This rejects exactly the cycles that
    contain no `Option`; combined with `recursiveAnonymous` rejecting
    anonymous-only cycles, the two gates together ensure an accepted cycle
    simultaneously contains a named key and an `Option`. Per-named-root DFS
    and "path has seen an Option" walks are rejected because they miss the
    sibling-branch trap (a node can have both an Option branch and a direct
    non-Option branch; the direct branch forms an Option-free cycle the
    path-local walk would miss).

    Implementation: a single explicit-stack white/gray/black DFS over the
    types table. For each TypeId, the child set is collected from the
    declaration's Struct fields / Enum payloads / Array element / Map key +
    value, but `Option` declarations contribute no children (they are removed
    nodes), and any child TypeId that resolves to an `Option` declaration is
    skipped (its incident edges are removed). Primitive leaves have no
    children; named Struct/Enum contribute their fields/payloads (those are
    the edges that form a named-body cycle). A standard gray back-edge is
    `.nonCanonical`.
    O(V+E) time, O(V+stack) space, no recursion, no HashMap iteration, no
    nested TypeKey bytes, no public reorder. Defensive OOR → `.badReference`
    is retained but earlier shallow reference checks report first. Runs
    after `recursiveAnonymous` and before named-name uniqueness / canonical
    valueBytes / callable signature / CFG / requirements. The complete SPEC
    §5 cycle condition is closed by the combination of the earlier
    `recursiveAnonymous` anonymous-cycle gate and this `namedBodyCycle`
    gate; the full TypeKey closure (anonymous canonical key bytes/rank/order,
    reachability, usage closure) and normalizer/provenance/product wire
    remain deferred. -/

/-- Children TypeIds that a declaration contributes to the Option-removed
    induced graph. `Option` declarations return `none` (removed nodes). Any
    child reference whose target is an `Option` declaration is filtered by
    the caller. The Enum branch is a linear flatten over variants and their
    payloads (a single mutable `push` per child), preserving source order and
    keeping the whole helper O(E) — a high-fanout Enum does not degrade to
    quadratic accumulator copying. -/
private def nonOptionChildTypeIds
    (decl : TypeDeclV1) : Option (Array TypeIdV1) :=
  match decl.shape with
  | .option _ => none
  | .struct fields => some (fields.map (·.typeId))
  | .enum variants =>
    some (Id.run do
      let mut acc : Array TypeIdV1 := Array.emptyWithCapacity
        (variants.foldl (fun s v => s + v.payloadTypes.size) 0)
      for v in variants do
        for t in v.payloadTypes do
          acc := acc.push t
      pure acc)
  | .array element _ => some #[element]
  | .map key value => some #[key, value]
  | _ => none

/-- Is the declaration at the given index an anonymous `.option`? The
    induced graph removes Option nodes, so edges into or out of them are
    dropped. -/
private def isOptionDecl (types : Array TypeDeclV1) (id : TypeIdV1) : Bool :=
  match types[id.toNat]? with
  | some { shape := .option _, .. } => true
  | _ => false

/-- SPEC §5 named-body Option-cycle legality: remove every `Option` node and
    its incident edges from the TypeId directed graph, then require the
    induced subgraph to be acyclic. A standard gray back-edge in an
    explicit-stack white/gray/black DFS is `.nonCanonical`. Runs as the
    `namedBodyCycle` subphase of `validateTypeKeyPhasesV1`, ordered after
    `recursiveAnonymous`. -/
private def validateNamedBodyOptionCycleLegalityV1
    (types : Array TypeDeclV1) : Except SemanticWireErrorV1 Unit := do
  let n := types.size
  let mut color : Array Nat := Array.replicate n 0
  let mut stack : Array (Nat × Nat) := #[]
  let mut root := 0
  while _ : root < n do
    if color[root]! == 0 then
      -- Skip removed Option nodes entirely (no DFS entry).
      if isOptionDecl types (UInt32.ofNat root) then
        color := color.set! root 2
      else
        stack := stack.push (0, root)
        while stack.isEmpty == false do
          let (kind, tid) := stack.back!
          stack := stack.pop
          if kind == 1 then
            -- exit: black.
            color := color.set! tid 2
          else
            -- enter.
            match color[tid]! with
            | 2 => pure ()  -- memoized
            | 1 => return ← err .nonCanonical  -- gray back-edge: Option-free cycle
            | _ =>
              match types[tid]? with
              | none => return ← err .badReference
              | some decl =>
                -- Mark gray; push an exit marker, then push children.
                color := color.set! tid 1
                stack := stack.push (1, tid)
                match nonOptionChildTypeIds decl with
                | none => pure ()  -- no children (Option node / primitive leaf)
                | some childIds =>
                  let mut ci := childIds.size
                  while _ : ci > 0 do
                    ci := ci - 1
                    let child := childIds[ci]!
                    let childIdx := child.toNat
                    if childIdx ≥ n then
                      return ← err .badReference
                    -- Drop edges into removed Option nodes.
                    if isOptionDecl types child then
                      pure ()
                    else
                      stack := stack.push (0, childIdx)
    root := root + 1
  pure ()

/-! ### TypeKey validation phase seam (SPEC §5)

    Named-prefix rank, leaf primitive anonymous TypeKey uniqueness,
    recursive anonymous container structural-class uniqueness, and named-body
    `Option`-cycle legality all report the
    same public wire error `.nonCanonical`. To make their precedence
    observable to focused tests without changing the public wire contract,
    this closed phase seam mirrors the `CfgInvariantValidationPhaseV1`
    pattern: a non-serialized phase enum plus the unchanged public error,
    consumed exactly by the structure gate which erases only `phase`. The
    phase is not serialized and does not appear in any wire/CLI output. -/

/-- Closed non-wire phase distinguishing the TypeKey subphases that
    share the public `.nonCanonical` error: `namedPrefix` (named contiguous
    prefix rank), `primitiveLeaf`, `recursiveAnonymous`, and
    `namedBodyCycle` (the SPEC §5 rule that any recursive cycle must pass
    through an `Option`, enforced after `recursiveAnonymous`). -/
inductive TypeKeyValidationPhaseV1
  | namedPrefix
  | primitiveLeaf
  | recursiveAnonymous
  | namedBodyCycle
  deriving BEq, Repr

/-- Internal phase plus the unchanged public wire error. -/
structure TypeKeyValidationFailureV1 where
  phase : TypeKeyValidationPhaseV1
  error : SemanticWireErrorV1
  deriving BEq, Repr

private def liftTypeKeyValidationPhaseV1
    (phase : TypeKeyValidationPhaseV1)
    (result : Except SemanticWireErrorV1 Unit) :
    Except TypeKeyValidationFailureV1 Unit :=
  match result with
  | .ok () => .ok ()
  | .error error => .error { phase, error }

/-- Runs the exact stable §5 TypeKey segment used by the structure gate in
    the fixed order: named contiguous-prefix rank first, then leaf primitive
    anonymous TypeKey uniqueness, then recursive anonymous container
    structural-class uniqueness (anonymous-container-cycle rejection without
    a named anchor), then named-body `Option`-cycle legality (remove every
    `Option` node and require the induced TypeId graph to be acyclic).
    Type-shape/FieldSpec/Map-key legality and shallow reference range are
    earlier prerequisites. The public wire error is unchanged; only the phase
    is exposed for focused tests. -/
def validateTypeKeyPhasesV1 (types : Array TypeDeclV1) :
    Except TypeKeyValidationFailureV1 Unit := do
  liftTypeKeyValidationPhaseV1 .namedPrefix
    (validateNamedPrefixRankV1 types)
  liftTypeKeyValidationPhaseV1 .primitiveLeaf
    (validatePrimitiveAnonymousTypeKeyUniquenessV1 types)
  liftTypeKeyValidationPhaseV1 .recursiveAnonymous
    (validateRecursiveAnonymousTypeKeyUniquenessV1 types)
  liftTypeKeyValidationPhaseV1 .namedBodyCycle
    (validateNamedBodyOptionCycleLegalityV1 types)

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

/-- Spend canonical-value work before continuing traversal or allocation. -/
private def spendCanonicalValueWorkV1 (budget cost : Nat) :
    Except SemanticWireErrorV1 Nat :=
  if cost ≤ budget then pure (budget - cost) else err .limitExceeded

/-- Decode one type-driven value and return its re-encoded canonical bytes and
    remaining cumulative work. Fuel bounds recursive shapes; unlike fuel, work
    is shared by every child and sibling. Each node costs one on entry and its
    own canonical output size (at least one) after its children. -/
private def decodeAndReencodeValueBytesV1 (types : Array TypeDeclV1) (typeId : TypeIdV1) :
    (fuel budget : Nat) → (c : Cursor) →
      Except SemanticWireErrorV1 (ByteArray × Cursor × Nat)
  | 0, _, _ => err .limitExceeded
  | fuel + 1, budget, c => do
    let budget ← spendCanonicalValueWorkV1 budget 1
    let (out, c, budget) ←
    match types[typeId.toNat]? with
    | none => err .badReference
    | some decl =>
      match decl.shape with
      | .bool => do
          let (b, c) ← takeByteNC c
          unless b == 0 || b == 1 do
            return ← err .nonCanonical
          pure (encodeU8 b, c, budget)
      | .uint width => do
          let n := width.toNat / 8
          let (raw, c) ← takeBytesNC c n
          pure (raw, c, budget)
      | .int width => do
          let n := width.toNat / 8
          let (raw, c) ← takeBytesNC c n
          pure (raw, c, budget)
      | .principal => do
          let (lenU, c) ← takeU32leNC c
          let len := lenU.toNat
          unless 1 ≤ len && len ≤ maxTypeLengthV1 do
            return ← err .nonCanonical
          let (bodyBytes, c) ← takeBytesNC c len
          pure ((encodeU32le lenU).append bodyBytes, c, budget)
      | .unit =>
          pure (ByteArray.empty, c, budget)
      | .bytes length => do
          let (raw, c) ← takeBytesNC c length.toNat
          pure (raw, c, budget)
      | .array element length => do
          unless length.toNat ≤ maxTypeLengthV1 do return ← err .limitExceeded
          let mut out := ByteArray.empty
          let mut c := c
          let mut budget := budget
          for _ in [:length.toNat] do
            let (chunk, c', budget') ← decodeAndReencodeValueBytesV1 types element fuel budget c
            out := out.append chunk
            c := c'
            budget := budget'
          pure (out, c, budget)
      | .map keyType valueType => do
          let (countU, c) ← takeU32leNC c
          let count := countU.toNat
          unless count ≤ maxMapEntriesV1 do
            return ← err .limitExceeded
          let mut out := encodeU32le countU
          let mut c := c
          let mut budget := budget
          let mut prevKey? : Option ByteArray := none
          for _ in [:count] do
            let (keyLenU, c1) ← takeU32leNC c
            let keyLen := keyLenU.toNat
            let (keyBytes, c2) ← takeBytesNC c1 keyLen
            let (keyRe, keyC, budget') ←
              decodeAndReencodeValueBytesV1 types keyType fuel budget (start keyBytes)
            budget := budget'
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
            let (valRe, valC, budget') ←
              decodeAndReencodeValueBytesV1 types valueType fuel budget (start valBytes)
            budget := budget'
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
          pure (out, c, budget)
      | .option element => do
          let (m, c) ← takeByteNC c
          match m.toNat with
          | 0 => pure (encodeU8 0, c, budget)
          | 1 => do
              let (payload, c, budget) ← decodeAndReencodeValueBytesV1 types element fuel budget c
              pure ((encodeU8 1).append payload, c, budget)
          | _ => err .nonCanonical
      | .field spec => do
          let width := fieldValueByteLengthV1 spec.modulusBE
          let (raw, c) ← takeBytesNC c width
          let value := leBytesToNatV1 raw
          let modulus := beBytesToNatV1 spec.modulusBE
          unless value < modulus do
            return ← err .nonCanonical
          pure (raw, c, budget)
      | .struct fields => do
          let mut out := ByteArray.empty
          let mut c := c
          let mut budget := budget
          for f in fields do
            let (chunk, c', budget') ← decodeAndReencodeValueBytesV1 types f.typeId fuel budget c
            out := out.append chunk
            c := c'
            budget := budget'
          pure (out, c, budget)
      | .enum variants => do
          let (idxU, c) ← takeU32leNC c
          let idx := idxU.toNat
          match variants[idx]? with
          | none => err .nonCanonical
          | some variant => do
              let mut out := encodeU32le idxU
              let mut c := c
              let mut budget := budget
              for payloadType in variant.payloadTypes do
                let (chunk, c', budget') ←
                  decodeAndReencodeValueBytesV1 types payloadType fuel budget c
                out := out.append chunk
                c := c'
                budget := budget'
              pure (out, c, budget)
    let budget ← spendCanonicalValueWorkV1 budget (max 1 out.size)
    pure (out, c, budget)

/-- Validate a complete valueBytes slice with an explicit recursive-shape fuel
    budget. Kept private so public callers cannot select a weaker policy; the
    Struct assembler uses it only after reserving the outer Struct level. -/
private def validateValueBytesWithFuelV1 (types : Array TypeDeclV1)
    (typeId : TypeIdV1) (valueBytes : ByteArray) (fuel budget : Nat) :
    Except SemanticWireErrorV1 Nat := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let (reencoded, c, budget) ←
    decodeAndReencodeValueBytesV1 types typeId fuel budget (start valueBytes)
  unless remaining c == 0 do
    return ← err .nonCanonical
  unless reencoded == valueBytes do
    return ← err .nonCanonical
  pure budget

/-- Validate a complete valueBytes slice for `typeId` (full consume + re-encode). -/
def validateValueBytesV1 (types : Array TypeDeclV1) (typeId : TypeIdV1)
    (valueBytes : ByteArray) : Except SemanticWireErrorV1 Unit := do
  let _ ← validateValueBytesWithFuelV1 types typeId valueBytes maxNesting maxCanonicalProgramBytes
  pure ()

/-- Split one complete canonical Struct value into its canonical field byte
    slices. This is the narrow public aggregate-codec seam used by the
    reference machine: the outer Struct consumes one nesting level and every
    field is decoded by the sole type-driven canonical decoder above.
    Non-Struct types, malformed fields, trailing bytes, and oversized values
    fail closed. -/
def splitCanonicalStructValueV1 (types : Array TypeDeclV1)
    (structTypeId : TypeIdV1) (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 (Array ByteArray) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let fields ←
    match types[structTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .struct fields, .. } => pure fields
    | some _ => err .badType
  let mut chunks : Array ByteArray := #[]
  let mut c := start valueBytes
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for field in fields do
    let beginOffset := c.offset
    let (reencoded, c', budget') ←
      decodeAndReencodeValueBytesV1 types field.typeId (maxNesting - 1) budget c
    let source := valueBytes.extract beginOffset c'.offset
    unless reencoded == source do
      return ← err .nonCanonical
    chunks := chunks.push source
    c := c'
    budget := budget'
  unless remaining c == 0 do
    return ← err .nonCanonical
  let _ ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure chunks

/-- Assemble one canonical Struct value from exact source-order canonical
    field byte slices. Each field is validated against its declared TypeId;
    the aggregate cap is checked before allocation growth, and the outer node
    is charged under the same cumulative decoder work policy. -/
def encodeCanonicalStructValueV1 (types : Array TypeDeclV1)
    (structTypeId : TypeIdV1) (fieldBytes : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  let fields ←
    match types[structTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .struct fields, .. } => pure fields
    | some _ => err .badType
  unless fieldBytes.size == fields.size do
    return ← err .nonCanonical
  let mut out := ByteArray.empty
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  let mut i := 0
  while i < fields.size do
    match fields[i]?, fieldBytes[i]? with
    | some field, some bytes =>
        unless bytes.size ≤ maxCanonicalValueBytes - out.size do
          return ← err .limitExceeded
        budget ← validateValueBytesWithFuelV1 types field.typeId bytes
          (maxNesting - 1) budget
        out := out.append bytes
    | _, _ => return ← err .nonCanonical
    i := i + 1
  let _ ← spendCanonicalValueWorkV1 budget (max 1 out.size)
  pure out

/-- Split one complete canonical fixed-length Array value into exactly its
    declared number of canonical element slices. The outer Array reserves one
    nesting level and the sole type-driven decoder performs every split. -/
def splitCanonicalArrayValueV1 (types : Array TypeDeclV1)
    (arrayTypeId : TypeIdV1) (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 (Array ByteArray) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do return ← err .limitExceeded
  let (element, length) ←
    match types[arrayTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .array element length, .. } => pure (element, length.toNat)
    | some _ => err .badType
  unless length ≤ maxTypeLengthV1 do return ← err .limitExceeded
  let mut chunks : Array ByteArray := #[]
  let mut c := start valueBytes
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for _ in [:length] do
    let beginOffset := c.offset
    let (reencoded, c', budget') ←
      decodeAndReencodeValueBytesV1 types element (maxNesting - 1) budget c
    let source := valueBytes.extract beginOffset c'.offset
    unless reencoded == source do return ← err .nonCanonical
    chunks := chunks.push source
    c := c'
    budget := budget'
  unless chunks.size == length && remaining c == 0 do return ← err .nonCanonical
  let _ ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure chunks

/-- Assemble one fixed-length Array from exact canonical element slices,
    checking the canonical value cap before every append and revalidating the
    completed value through the sole decoder. -/
def encodeCanonicalArrayValueV1 (types : Array TypeDeclV1)
    (arrayTypeId : TypeIdV1) (elementBytes : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  let (element, length) ←
    match types[arrayTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .array element length, .. } => pure (element, length.toNat)
    | some _ => err .badType
  unless length ≤ maxTypeLengthV1 do return ← err .limitExceeded
  unless elementBytes.size == length do return ← err .nonCanonical
  let mut out := ByteArray.empty
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for bytes in elementBytes do
    unless bytes.size ≤ maxCanonicalValueBytes - out.size do
      return ← err .limitExceeded
    budget ← validateValueBytesWithFuelV1 types element bytes
      (maxNesting - 1) budget
    out := out.append bytes
  let _ ← spendCanonicalValueWorkV1 budget (max 1 out.size)
  pure out

/-- Canonical Map entry returned by the narrow public Map codec seam. -/
structure CanonicalMapEntryV1 where
  keyBytes   : ByteArray
  valueBytes : ByteArray
  deriving Inhabited

/-- Phase-aware Map mutation failure. Input failures retain their exact Wire
    error; only work/capacity failures after all inputs validate are resources. -/
inductive CanonicalMapUpdateErrorV1 where
  | invalidInput (error : SemanticWireErrorV1)
  | resourceExhausted
  deriving BEq, Repr

private def mapUpdateInputV1 (result : Except SemanticWireErrorV1 α) :
    Except CanonicalMapUpdateErrorV1 α :=
  match result with
  | .ok value => .ok value
  | .error error => .error (.invalidInput error)

private def canonicalMapShapeV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1) :
    Except SemanticWireErrorV1 (TypeIdV1 × TypeIdV1) := do
  match types[mapTypeId.toNat]? with
  | none => err .badReference
  | some { shape := .map key value, .. } =>
      -- Keep Map-key policy owned by Wire rather than duplicating or widening
      -- it in an evaluator.
      checkLegalMapKeyTypeV1 types key types.size
      pure (key, value)
  | some _ => err .badType

private def splitCanonicalMapValueWithBudgetV1 (types : Array TypeDeclV1)
    (mapTypeId : TypeIdV1) (valueBytes : ByteArray) (budget : Nat) :
    Except SemanticWireErrorV1 (Array CanonicalMapEntryV1 × Nat) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do return ← err .limitExceeded
  let (keyType, valueType) ← canonicalMapShapeV1 types mapTypeId
  let mut budget ← spendCanonicalValueWorkV1 budget 1
  let (countU, c0) ← takeU32leNC (start valueBytes)
  let count := countU.toNat
  unless count ≤ maxMapEntriesV1 do return ← err .limitExceeded
  let mut c := c0
  let mut entries : Array CanonicalMapEntryV1 := Array.emptyWithCapacity count
  let mut previous : Option ByteArray := none
  for _ in [:count] do
    let (keyLenU, c1) ← takeU32leNC c
    let (key, c2) ← takeBytesNC c1 keyLenU.toNat
    let (keyRe, keyCursor, budget') ←
      decodeAndReencodeValueBytesV1 types keyType (maxNesting - 1) budget (start key)
    budget := budget'
    unless remaining keyCursor == 0 && keyRe == key do return ← err .nonCanonical
    match previous with
    | some prior =>
        unless compareByteArrayLex prior key == .lt do return ← err .nonCanonical
    | none => pure ()
    previous := some key
    let (valueLenU, c3) ← takeU32leNC c2
    let (value, c4) ← takeBytesNC c3 valueLenU.toNat
    let (valueRe, valueCursor, budget') ←
      decodeAndReencodeValueBytesV1 types valueType (maxNesting - 1) budget (start value)
    budget := budget'
    unless remaining valueCursor == 0 && valueRe == value do return ← err .nonCanonical
    entries := entries.push { keyBytes := key, valueBytes := value }
    c := c4
  unless remaining c == 0 do return ← err .nonCanonical
  budget ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure (entries, budget)

/-- Split and validate one complete canonical Map under a single cumulative
    traversal budget. -/
def splitCanonicalMapValueV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1)
    (valueBytes : ByteArray) : Except SemanticWireErrorV1 (Array CanonicalMapEntryV1) := do
  let (entries, _) ← splitCanonicalMapValueWithBudgetV1 types mapTypeId valueBytes
    maxCanonicalProgramBytes
  pure entries

/-- Wire-owned canonical empty Map encoding. -/
def encodeCanonicalEmptyMapValueV1 (types : Array TypeDeclV1)
    (mapTypeId : TypeIdV1) : Except SemanticWireErrorV1 ByteArray := do
  let _ ← canonicalMapShapeV1 types mapTypeId
  let out := encodeU32le 0
  validateValueBytesV1 types mapTypeId out
  pure out

/-- Lookup an exact canonical key in a canonical Map. Both the map and key are
    validated against their exact TypeIds; ordering/framing remains private. -/
def lookupCanonicalMapValueV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1)
    (mapBytes keyBytes : ByteArray) : Except SemanticWireErrorV1 (Option ByteArray) := do
  let (keyType, _) ← canonicalMapShapeV1 types mapTypeId
  let budget ← validateValueBytesWithFuelV1 types keyType keyBytes (maxNesting - 1)
    maxCanonicalProgramBytes
  let (entries, budget) ←
    splitCanonicalMapValueWithBudgetV1 types mapTypeId mapBytes budget
  let mut budget := budget
  for entry in entries do
    budget ← spendCanonicalValueWorkV1 budget 1
    match compareByteArrayLex entry.keyBytes keyBytes with
    | .eq => return some entry.valueBytes
    | .gt => return none
    | .lt => pure ()
  pure none

/-- Immutable canonical Map upsert. Equal keys replace without count growth;
    otherwise insertion preserves strict unsigned-byte lexicographic order.
    Input validation and mutation resource failures remain distinguishable. -/
def upsertCanonicalMapValueV1 (types : Array TypeDeclV1) (mapTypeId : TypeIdV1)
    (mapBytes keyBytes valueBytes : ByteArray) :
    Except CanonicalMapUpdateErrorV1 ByteArray := do
  let (keyType, valueType) ← mapUpdateInputV1 (canonicalMapShapeV1 types mapTypeId)
  let budget ← mapUpdateInputV1 <|
    validateValueBytesWithFuelV1 types keyType keyBytes (maxNesting - 1)
      maxCanonicalProgramBytes
  let budget ← mapUpdateInputV1 <|
    validateValueBytesWithFuelV1 types valueType valueBytes (maxNesting - 1) budget
  let (entries, budget) ← mapUpdateInputV1 <|
    splitCanonicalMapValueWithBudgetV1 types mapTypeId mapBytes budget
  let mut budget := budget
  budget ←
    match spendCanonicalValueWorkV1 budget entries.size with
    | .ok updatedBudget => pure updatedBudget
    | .error _ => throw .resourceExhausted
  let replacing := entries.any (fun e => e.keyBytes == keyBytes)
  unless replacing || entries.size < maxMapEntriesV1 do
    throw .resourceExhausted
  let count := if replacing then entries.size else entries.size + 1
  let mut out := encodeU32le (UInt32.ofNat count)
  let appendEntry (out : ByteArray) (key value : ByteArray) :
      Except CanonicalMapUpdateErrorV1 ByteArray := do
    unless key.size ≤ maxCanonicalValueBytes - 8 do throw .resourceExhausted
    let keyFramed := key.size + 8
    unless value.size ≤ maxCanonicalValueBytes - keyFramed do throw .resourceExhausted
    let needed := keyFramed + value.size
    unless needed ≤ maxCanonicalValueBytes - out.size do
      throw .resourceExhausted
    pure ((((out.append (encodeU32le (UInt32.ofNat key.size))).append key).append
      (encodeU32le (UInt32.ofNat value.size))).append value)
  let mut inserted := false
  for entry in entries do
    budget ←
      match spendCanonicalValueWorkV1 budget 1 with
      | .ok updatedBudget => pure updatedBudget
      | .error _ => throw .resourceExhausted
    match compareByteArrayLex entry.keyBytes keyBytes with
    | .lt => out ← appendEntry out entry.keyBytes entry.valueBytes
    | .eq =>
        out ← appendEntry out keyBytes valueBytes
        inserted := true
    | .gt =>
        unless inserted do
          out ← appendEntry out keyBytes valueBytes
          inserted := true
        out ← appendEntry out entry.keyBytes entry.valueBytes
  unless inserted do out ← appendEntry out keyBytes valueBytes
  let _ ←
    match spendCanonicalValueWorkV1 budget (max 1 out.size) with
    | .ok remainingBudget => pure remainingBudget
    | .error _ => throw .resourceExhausted
  pure out

/-- Split one complete canonical Option/Enum value into its constructor tag and
    canonical payload slices. The outer variant reserves one nesting level;
    payloads are decoded by the sole canonical decoder. -/
def splitCanonicalVariantValueV1 (types : Array TypeDeclV1)
    (variantTypeId : TypeIdV1) (valueBytes : ByteArray) :
    Except SemanticWireErrorV1 (UInt32 × Array ByteArray) := do
  unless valueBytes.size ≤ maxCanonicalValueBytes do
    return ← err .limitExceeded
  let (tag, payloadTypes, payloadOffset) ←
    match types[variantTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .option element, .. } =>
        if valueBytes.size == 0 then err .nonCanonical
        else
          match valueBytes.get! 0 with
          | 0 => pure ((0 : UInt32), #[], 1)
          | 1 => pure ((1 : UInt32), #[element], 1)
          | _ => err .nonCanonical
    | some { shape := .enum variants, .. } => do
        let (tag, c) ← takeU32leNC (start valueBytes)
        match variants[tag.toNat]? with
        | some variant => pure (tag, variant.payloadTypes, c.offset)
        | none => err .nonCanonical
    | some _ => err .badType
  let mut chunks : Array ByteArray := #[]
  let mut c := { start valueBytes with offset := payloadOffset }
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  for payloadType in payloadTypes do
    let beginOffset := c.offset
    let (reencoded, c', budget') ←
      decodeAndReencodeValueBytesV1 types payloadType (maxNesting - 1) budget c
    let source := valueBytes.extract beginOffset c'.offset
    unless reencoded == source do return ← err .nonCanonical
    chunks := chunks.push source
    c := c'
    budget := budget'
  unless remaining c == 0 do return ← err .nonCanonical
  let _ ← spendCanonicalValueWorkV1 budget (max 1 valueBytes.size)
  pure (tag, chunks)

/-- Assemble one canonical Option/Enum from an exact constructor tag and exact
    canonical payload slices, checking the cap before every append and finally
    full-consuming/re-encoding the result through the sole value decoder. -/
def encodeCanonicalVariantValueV1 (types : Array TypeDeclV1)
    (variantTypeId : TypeIdV1) (tag : UInt32) (payloadBytes : Array ByteArray) :
    Except SemanticWireErrorV1 ByteArray := do
  let (headerBytes, payloadTypes) ←
    match types[variantTypeId.toNat]? with
    | none => err .badReference
    | some { shape := .option element, .. } =>
        if tag == 0 then pure (encodeU8 0, #[])
        else if tag == 1 then pure (encodeU8 1, #[element])
        else err .nonCanonical
    | some { shape := .enum variants, .. } =>
        match variants[tag.toNat]? with
        | some variant => pure (encodeU32le tag, variant.payloadTypes)
        | none => err .nonCanonical
    | some _ => err .badType
  unless payloadBytes.size == payloadTypes.size do return ← err .nonCanonical
  let mut out := headerBytes
  let mut budget ← spendCanonicalValueWorkV1 maxCanonicalProgramBytes 1
  let mut i := 0
  while i < payloadTypes.size do
    match payloadTypes[i]?, payloadBytes[i]? with
    | some payloadType, some bytes =>
        unless bytes.size ≤ maxCanonicalValueBytes - out.size do
          return ← err .limitExceeded
        budget ← validateValueBytesWithFuelV1 types payloadType bytes
          (maxNesting - 1) budget
        out := out.append bytes
    | _, _ => return ← err .nonCanonical
    i := i + 1
  let _ ← spendCanonicalValueWorkV1 budget (max 1 out.size)
  pure out

private def validateOpValueBytesV1 (types : Array TypeDeclV1) (op : SemanticOpV1)
    (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  match op with
  | .literal typeId valueBytes =>
      validateValueBytesWithFuelV1 types typeId valueBytes maxNesting budget
  | _ => pure budget

private def validateTerminatorValueBytesV1 (types : Array TypeDeclV1)
    (term : TerminatorV1) (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  match term with
  | .switch _scrutinee cases _default =>
      let mut budget := budget
      for sc in cases do
        budget ← validateValueBytesWithFuelV1 types sc.typeId sc.valueBytes
          maxNesting budget
      pure budget
  | _ => pure budget

private def validateConstantsValueBytesV1 (types : Array TypeDeclV1)
    (constants : Array ConstantV1) (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  let mut budget := budget
  for c in constants do
    budget ← validateValueBytesWithFuelV1 types c.typeId c.valueBytes maxNesting budget
  pure budget

/-- Walk callable blocks for Op.Literal and SwitchCase valueBytes only.
    Does not check CFG reachability, dominance, or ValueId SSA. -/
private def validateCallablesValueBytesV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) (budget : Nat) : Except SemanticWireErrorV1 Nat := do
  let mut budget := budget
  for callable in callables do
    for block in callable.blocks do
      for instr in block.instructions do
        budget ← validateOpValueBytesV1 types instr.op budget
      budget ← validateTerminatorValueBytesV1 types block.terminator budget
  pure budget

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
    Named contiguous-prefix rank and the named-body `Option`-cycle condition
    are enforced by earlier `namedPrefix` and `namedBodyCycle` subphases.
    Anonymous canonical rank/order, usage closure, and the remaining full
    TypeKey closure stay separate. Identifier grammar/NFC is enforced by the
    later declaration-name structure gate. -/
private def validateNamedTypeNameUniquenessV1 (types : Array TypeDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut names : Array String := #[]
  for decl in types do
    match decl.name with
    | some name => names := names.push name
    | none => pure ()
  checkUniqueDeclarationNamesV1 names

/-- Constant names are exact-string unique within the constants table (SPEC
    §6). Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
private def validateConstantNameUniquenessV1 (constants : Array ConstantV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (constants.map (·.name))

/-- StateDecl names are exact-string unique within logicalState (SPEC §6).
    Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
private def validateLogicalStateNameUniquenessV1
    (logicalState : Array StateDeclV1) : Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (logicalState.map (·.name))

/-- EventDecl names are exact-string unique within events (SPEC §6).
    Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
private def validateEventNameUniquenessV1 (events : Array EventDeclV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (events.map (·.name))

/-- ErrorDecl names are exact-string unique within errors (SPEC §6).
    Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
private def validateErrorNameUniquenessV1 (errors : Array ErrorDeclV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (errors.map (·.name))

/-- Event/error interface-field names are exact-string unique within each
    declaration (SPEC §6). Each declaration gets an independent namespace;
    identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
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
    name. Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. Runs after canonical values and before
    uniqueness/special signatures/CFG. -/
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
    Compare exact UTF-8 strings; identifier grammar/NFC is the later
    declaration-name structure gate. Sorting a private name array preserves
    public callable source order. -/
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
    Each callable gets a fresh private sort; identifier grammar/NFC is the
    later declaration-name structure gate. -/
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

/-- SPEC §6 declaration/field/parameter/invariant names must satisfy the shared
    SPEC-COMMON identifier component rule (NFC, 1..240 UTF-8, not `_`,
    `Lean.isIdFirst`/`Lean.isIdRest`). Structure authority maps Common
    failures to `.badScalar`. Walks tables in source order; initializer
    `name=none` is skipped (not rejected). Does not reorder tables or change
    exact uniqueness. Transport decode of bare `String` fields remains
    NFC-only; this gate is the sole full identifier authority for structure
    validate / structure-gated encode / carrier re-encode. -/
private def validateIdentifierNameV1 (name : String) :
    Except SemanticWireErrorV1 Unit :=
  mapCommon (validateIdentifierComponent name)

private def validateTypeShapeIdentifierNamesV1 (shape : TypeShapeV1) :
    Except SemanticWireErrorV1 Unit := do
  match shape with
  | .struct fields =>
      for field in fields do
        validateIdentifierNameV1 field.name
  | .enum variants =>
      for variant in variants do
        validateIdentifierNameV1 variant.name
  | _ => pure ()

private def validateDeclarationIdentifierNamesV1
    (data : SemanticProgramDataV1) : Except SemanticWireErrorV1 Unit := do
  -- Table walk order is declaration-table source order (types through
  -- invariants) then callables last. Invariants precede callables so an
  -- exact join pair that shares one illegal name fails on the InvariantDecl
  -- site first; named-callable/parameter grammar is still exercised on
  -- programs without invariants. Initializer `name=none` is skipped.
  for decl in data.types do
    match decl.name with
    | some name => validateIdentifierNameV1 name
    | none => pure ()
    validateTypeShapeIdentifierNamesV1 decl.shape
  for constant in data.constants do
    validateIdentifierNameV1 constant.name
  for state in data.logicalState do
    validateIdentifierNameV1 state.name
  for eventDecl in data.events do
    validateIdentifierNameV1 eventDecl.name
    for field in eventDecl.fields do
      validateIdentifierNameV1 field.name
  for errorDecl in data.errors do
    validateIdentifierNameV1 errorDecl.name
    for field in errorDecl.fields do
      validateIdentifierNameV1 field.name
  for inv in data.invariants do
    validateIdentifierNameV1 inv.name
  for callable in data.callables do
    match callable.name with
    | some name => validateIdentifierNameV1 name
    | none => pure ()
    for param in callable.params do
      validateIdentifierNameV1 param.name
  pure ()

/-- SPEC §6 aggregate callable requirement: `callables` must contain at least
    one callable of kind `.entry` or `.view`. A program with only
    initializers/pureFns/invariants (or zero callables) has no externally
    invokable surface and is structurally invalid. This bounded source-order
    scan is O(callables)/O(1) and runs after callable kind/name presence,
    callable-name uniqueness, and per-callable parameter-name uniqueness, but
    before initializer/invariant signature checks, CFG, and requirements, so
    those later gates only observe programs that already expose an entry/view.
    `decodeSemanticProgramDataV1` transport remains permissive. -/
private def validateCallableEntryViewPresenceV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let mut found := false
  for callable in callables do
    match callable.kind with
    | .entry | .view => found := true
    | _ => pure ()
  unless found do
    return ← err .badCfg
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
    checked post-CFG; op restrictions and exact checked step computation follow
    those structural gates. -/
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
    call-graph DAG, closure-CFG acyclicity, op restrictions, and exact checked
    step computation are checked post-CFG. This presence
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

/-- Stable non-serialized phases for the callable-signature segment. Several
    neighboring checks intentionally share the public `.badCfg` wire error;
    this seam makes their precedence observable to focused tests without
    changing serialized or CLI behavior. -/
inductive CallableSignatureValidationPhaseV1
  | kindName
  | callableName
  | parameterName
  | entryView
  | specialSignature
  deriving BEq, Repr

/-- Callable-signature phase plus the unchanged public wire error. -/
structure CallableSignatureValidationFailureV1 where
  phase : CallableSignatureValidationPhaseV1
  error : SemanticWireErrorV1
  deriving BEq, Repr

private def liftCallableSignatureValidationPhaseV1
    (phase : CallableSignatureValidationPhaseV1)
    (result : Except SemanticWireErrorV1 Unit) :
    Except CallableSignatureValidationFailureV1 Unit :=
  match result with
  | .ok () => .ok ()
  | .error wireError => .error { phase, error := wireError }

/-- Exact callable-signature phase sequence consumed by the production
    structure gate. The phase is never serialized; callers erase only it and
    retain the existing `SemanticWireErrorV1`. Invariant declaration join stays
    in its later post-signature position because it also depends on the
    dedicated invariant table. -/
def validateCallableSignaturePhasesV1 (types : Array TypeDeclV1)
    (callables : Array CallableV1) :
    Except CallableSignatureValidationFailureV1 Unit := do
  liftCallableSignatureValidationPhaseV1 .kindName
    (validateCallableKindNamePresenceV1 callables)
  liftCallableSignatureValidationPhaseV1 .callableName
    (validateCallableNameUniquenessV1 callables)
  liftCallableSignatureValidationPhaseV1 .parameterName
    (validateCallableParameterNameUniquenessV1 callables)
  liftCallableSignatureValidationPhaseV1 .entryView
    (validateCallableEntryViewPresenceV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInitializerCardinalityV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInitializerResultShapeV1 types callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantResultShapeV1 types callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantParameterShapeV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantLoopBoundsShapeV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateNonClosureCallableInvariantStepsV1 callables)
  liftCallableSignatureValidationPhaseV1 .specialSignature
    (validateInvariantRootStepsPresenceV1 callables)

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
    and closure-CFG acyclicity validation run next; op restrictions and exact
    checked step values follow in later post-CFG subphases. Other callable-kind
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
    Closure-CFG back edges and exact step computation run afterward. -/
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

/-- A pureFn in an invariant closure cannot access logical state or context,
    create commitments, emit events, perform synchronous external calls, or
    schedule asynchronous workflows (SPEC §8). Generic CFG/op typing and
    closure graph/CFG acyclicity have
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
                | .contextRead _ => return ← err .badCfg
                | .commit _ => return ← err .badCfg
                | .emit _ _ _ => return ← err .badCfg
                | .externalCall _ _ _ => return ← err .badCfg
                | .schedule _ _ _ => return ← err .badCfg
                | _ => pure ()
  pure ()

/-- Add one contribution to an invariant step total without wraparound. The
    schema-fixed 10M ceiling is stricter than UInt64 overflow, so rejecting as
    soon as this bound is crossed simultaneously enforces checked UInt64
    accumulation and the intrinsic limit (SPEC §8). -/
private def addInvariantStepsCheckedV1 (lhs rhs : UInt64) :
    Except SemanticWireErrorV1 UInt64 := do
  let total := lhs.toNat + rhs.toNat
  if maxInvariantStepsV1.toNat < total then return ← err .badCfg
  pure (UInt64.ofNat total)

/-- Compute and validate exact `computedInvariantSteps` for every callable in
    the already-validated invariant-closure DAG (SPEC §8). Local cost is
    `1 + sum(block.instructions.size + 1)`; every static PureCall occurrence
    adds its callee's full computed cost, including duplicate edges. A reverse
    adjacency Kahn pass starts at leaves, so each instruction edge and closure
    member is processed once. Generic CFG/op typing, exact closure membership,
    call-graph DAG, closure-CFG acyclicity, and op restrictions have already
    run; every fact is nevertheless rechecked fail-closed. -/
private def validateInvariantStepsExactV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  let members ← computeInvariantClosureMembershipV1 callables
  let callableCount := callables.size
  let mut remainingCalls := Array.mk (List.replicate callableCount 0)
  let mut callersByCallee : Array (Array Nat) :=
    Array.mk (List.replicate callableCount #[])
  let mut totals := Array.mk (List.replicate callableCount (0 : UInt64))
  let mut memberCount : Nat := 0
  for callerIndex in [:callableCount] do
    if members[callerIndex]! then
      memberCount := memberCount + 1
      match callables[callerIndex]? with
      | none => return ← err .badCfg
      | some caller =>
          let mut intrinsicTotal : UInt64 := 1
          for block in caller.blocks do
            let next ← addInvariantStepsCheckedV1 intrinsicTotal
              (UInt64.ofNat (block.instructions.size + 1))
            intrinsicTotal := next
            for instr in block.instructions do
              match instr.op with
              | .pureCall calleeId _ =>
                  let calleeIndex := calleeId.toNat
                  match callables[calleeIndex]? with
                  | none => return ← err .badCfg
                  | some callee =>
                      unless callee.kind == .pureFn && members[calleeIndex]! do
                        return ← err .badCfg
                      remainingCalls := remainingCalls.set! callerIndex
                        (remainingCalls[callerIndex]! + 1)
                      callersByCallee := callersByCallee.set! calleeIndex
                        (callersByCallee[calleeIndex]!.push callerIndex)
              | _ => pure ()
          totals := totals.set! callerIndex intrinsicTotal
  let mut ready : Array Nat := #[]
  for index in [:callableCount] do
    if members[index]! && remainingCalls[index]! == 0 then
      ready := ready.push index
  let mut cursor : Nat := 0
  let mut processed : Nat := 0
  while cursor < ready.size do
    let calleeIndex := ready[cursor]!
    cursor := cursor + 1
    processed := processed + 1
    match callables[calleeIndex]? with
    | none => return ← err .badCfg
    | some callee =>
        match callee.invariantSteps with
        | none => return ← err .badCfg
        | some carried =>
            unless carried == totals[calleeIndex]! do return ← err .badCfg
    let calleeSteps := totals[calleeIndex]!
    for callerIndex in callersByCallee[calleeIndex]! do
      let nextTotal ← addInvariantStepsCheckedV1 totals[callerIndex]! calleeSteps
      totals := totals.set! callerIndex nextTotal
      let remaining := remainingCalls[callerIndex]!
      if remaining == 0 then return ← err .badCfg
      let nextRemaining := remaining - 1
      remainingCalls := remainingCalls.set! callerIndex nextRemaining
      if nextRemaining == 0 then ready := ready.push callerIndex
  unless processed == memberCount do return ← err .badCfg
  pure ()

/-- Every present invariant fuel value is bounded by the schema-fixed 10M
    intrinsic ceiling (SPEC §8). Exact checked computation for closure members
    has already run. This residual scan keeps the scalar metadata boundary
    explicit and runs before requirements. -/
private def validateInvariantStepsIntrinsicCeilingV1
    (callables : Array CallableV1) : Except SemanticWireErrorV1 Unit := do
  for callable in callables do
    match callable.invariantSteps with
    | none => pure ()
    | some steps =>
        unless steps ≤ maxInvariantStepsV1 do return ← err .badCfg
  pure ()

/- SPEC-SEM-WIRE-001 §5.1 engineering subset (structure-gate-only): within one
    `SemanticProgramV1`, every `Op.ContextRead` carrying the same exact
    `SchemaId` key MUST use the same `Instruction.result` TypeId. Different
    callables/branches declaring different result types for the same key are
    invalid Core and cannot be rescued by an Invocation or target adapter.

    This is a bounded deterministic global pass that runs after every
    callable's generic CFG/op typing succeeds and before invariant-closure/
    fuel/requirements. Generic CFG already guarantees result presence and
    def-site TypeId range; this pass still defends a missing result as
    `.badCfg`. It scans callables → blocks → instructions in source order and
    performs exact-key lookup/insert only (`key.value` string equality); it
    never iterates the host map. Expected time O(number of ContextRead
    occurrences), space O(distinct keys). The wire-owned v1 catalog admits
    only the Unix-time-seconds key with anonymous UInt64 shape; exact
    requirement binding runs after generic requirement validation. Commit's
    disclosure contract remains deferred. -/
private def validateContextReadCatalogV1
    (types : Array TypeDeclV1) (callables : Array CallableV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut seen : Std.HashMap String TypeIdV1 := {}
  for callable in callables do
    for block in callable.blocks do
      for instr in block.instructions do
        match instr.op with
        | .contextRead key =>
            unless key == unixTimeSecondsContextKeyV1 do
              return ← err .badCfg
            match instr.result with
            | none => return ← err .badCfg
            | some rdef =>
                match types[rdef.typeId.toNat]? with
                | some { name := none, shape := .uint 64, .. } => pure ()
                | _ => return ← err .badCfg
                match seen.get? key.value with
                | none => seen := seen.insert key.value rdef.typeId
                | some prevT =>
                    unless prevT == rdef.typeId do
                      return ← err .badCfg
        | _ => pure ()
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
    callable's generic CFG/op validation, then the global ContextRead
    same-key result-TypeId consistency pass (SPEC §5.1, `.cfg` phase), then
    invariant closure restrictions, then intrinsic invariant fuel. Earlier
    structure phases are prerequisites. -/
def validateCfgInvariantPhasesV1 (data : SemanticProgramDataV1) :
    Except CfgInvariantValidationFailureV1 Unit := do
  for callable in data.callables do
    liftCfgInvariantValidationPhaseV1 .cfg
      (validateCallableCfgShape callable data.types.size data.types data)
  liftCfgInvariantValidationPhaseV1 .cfg
    (validateContextReadCatalogV1 data.types data.callables)
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
    (validateInvariantStepsExactV1 data.callables)
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

/-- Bind every used wire-owned ContextRead key to its one exact requirement
    row. Generic requirement structure/order is validated first. -/
private def validateContextReadRequirementsV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut used := false
  for callable in data.callables do
    for block in callable.blocks do
      for instr in block.instructions do
        match instr.op with
        | .contextRead _ => used := true
        | _ => pure ()
  unless used do return
  let expected ← match unixTimeSecondsContextRequirementV1 with
    | .ok row => pure row
    | .error _ => return ← err .badRequirement
  let mut found := false
  for item in data.requirements.items do
    if item.id == unixTimeSecondsContextRequirementIdV1 then
      unless item == expected do return ← err .badRequirement
      if found then return ← err .badRequirement
      found := true
  unless found do return ← err .badRequirement

/-- Bind every used Commit operation to the one exact disclosure.commitment
    requirement row. Generic requirement structure/order is validated first. -/
private def validateCommitRequirementsV1 (data : SemanticProgramDataV1) :
    Except SemanticWireErrorV1 Unit := do
  let mut used := false
  for callable in data.callables do
    for block in callable.blocks do
      for instr in block.instructions do
        match instr.op with
        | .commit _ => used := true
        | _ => pure ()
  unless used do return
  let expected ← match commitmentDisclosureRequirementV1 with
    | .ok row => pure row
    | .error _ => return ← err .badRequirement
  let mut found := false
  for item in data.requirements.items do
    if item.id == commitmentDisclosureRequirementIdV1 then
      unless item == expected do return ← err .badRequirement
      if found then return ← err .badRequirement
      found := true
  unless found do return ← err .badRequirement

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
    Map-key plus leaf primitive anonymous TypeKey uniqueness plus recursive
    anonymous `.array`/`.map`/`.option` structural-class uniqueness (fixed-size
    structural-class signatures, not nested child keys) with anonymous-
    container-cycle rejection (without a named anchor; SPEC §5), canonical
    valueBytes (Constant /
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
      Op.Emit exact EventDecl/args/void-result contract; Commit operand/result
      TypeId equality; ContextRead presence plus the closed exact key/anonymous
      UInt64 catalog in `.cfg` and exact requirement binding after generic
      requirement validation; ExternalCall/Schedule void-result plus
      at-least-two-component callee shape)
    (SPEC §6.2 CFG layers), requirement/predicate order
    (SPEC-SEM-WIRE-001 §4.5/§5/§6/§6.2 + CAP ranks).
    Empty tables and empty requirements remain legal. Walks callable bodies
    only for valueBytes sites and CFG shape/reachability/arity/loopBounds/SSA
    def-table/dominance-of-use/def-site TypeId range/terminator typing/per-op
    type/result contract (incl. value-producing result-presence and void-op
    result-presence) — NOT ExternalCall/Schedule argument serializability,
    runtime CheckedCast representability,
    Array/Bytes bounds and Enum tag agreement, recursive/full TypeKey closure
    beyond the enforced named-prefix rank and closed cycle condition,
    full anonymous ranking/reachability (SPEC
    canonical unsigned-lexicographic anonymous TypeKey/ranking bytes), and
    usage closure/missing/unreferenced rejection,
    provenance inventory join, or ProgramV1 normalizer. The named-body
    Option-cycle legality rule (SPEC §5: any recursive cycle must pass
    through an `Option`) is now closed by the combination of the earlier
    `recursiveAnonymous` anonymous-cycle gate and the `namedBodyCycle`
    subphase; anonymous canonical key bytes/rank/order, full TypeKey
    closure reachability/provenance, and product wiring remain deferred. -/
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
  -- 3) Type-shape / FieldSpec catalog / Map-key legality, then the TypeKey
  --   uniqueness segment via the exact phase seam: named contiguous-prefix
  --   rank first, then leaf primitive anonymous TypeKey uniqueness, then
  --   recursive anonymous container structural-class uniqueness
  --   (anonymous-container-cycle rejection without a named anchor), then
  --   named-body Option-cycle legality (SPEC §5: any recursive cycle must
  --   pass through an `Option`, enforced as acyclicity of the TypeId graph
  --   induced after removing every `Option` node), then named Struct/Enum
  --   exact-name uniqueness (SPEC §5/§6). The phase seam preserves the
  --   public `.nonCanonical` wire error while exposing the subphase to
  --   focused tests.
  validateTypesStructureV1 data.types
  match validateTypeKeyPhasesV1 data.types with
  | .ok () => pure ()
  | .error failure => throw failure.error
  validateNamedTypeNameUniquenessV1 data.types
  -- 4) Canonical valueBytes (Constant / Op.Literal / SwitchCase)
  let budget ← validateConstantsValueBytesV1 data.types data.constants maxCanonicalProgramBytes
  let _ ← validateCallablesValueBytesV1 data.types data.callables budget
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
  -- 4.25–4.3) Callable kind/name → callable-name uniqueness → per-callable
  --   parameter-name uniqueness → SPEC §6 entry/view aggregate presence →
  --   initializer/invariant special signatures and invariantSteps metadata.
  --   The production gate consumes the exact non-serialized phase seam so
  --   focused tests can distinguish neighboring checks that share `.badCfg`;
  --   only the phase is erased here. InvariantDecl exact join remains next.
  match validateCallableSignaturePhasesV1 data.types data.callables with
  | .ok () => pure ()
  | .error failure => throw failure.error
  validateInvariantDeclarationJoinV1 data.callables data.invariants
  -- 4.4) SPEC §6 declaration/field/parameter/invariant name NFC + common
  --   identifier grammar (shared `validateIdentifierComponent`). After
  --   uniqueness and InvariantDecl join so those phases retain priority when
  --   both fail; before CFG so bad names fail closed without CFG work.
  --   Transport decoder stays NFC-only on bare strings.
  validateDeclarationIdentifierNamesV1 data
  -- 4.5–4.75) Generic CFG/op typing → closed ContextRead exact key/anonymous
  --   UInt64 plus same-key result-TypeId consistency (§5.1, `.cfg`) → direct
  --   root restrictions + exact transitive pureFn closure membership +
  --   reachable call-graph/CFG acyclicity → intrinsic invariant fuel. Exact
  --   ContextRead requirement binding follows generic requirement structure
  --   validation below. The shared helper preserves the public wire error
  --   while exposing the stable subphase to focused tests.
  match validateCfgInvariantPhasesV1 data with
  | .ok () => pure ()
  | .error failure => throw failure.error
  -- 5) Requirement key + predicate order, then exact ContextRead/Commit rows
  validateProgramRequirementsStructure data.requirements
  validateContextReadRequirementsV1 data
  validateCommitRequirementsV1 data

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

/-! ### Provenance complete join (SPEC §6.1 engineering subset) -/

/-- Collect every semantic entity that must appear in a complete originMap. -/
def collectProgramEntityRefsV1 (data : SemanticProgramDataV1) :
    Array SemanticEntityRefV1 := Id.run do
  let mut out : Array SemanticEntityRefV1 := #[]
  for t in data.types do
    out := out.push (.typeRef t.id)
  for c in data.constants do
    out := out.push (.constant c.id)
  for s in data.logicalState do
    out := out.push (.state s.id)
  for e in data.events do
    out := out.push (.event e.id)
  for e in data.errors do
    out := out.push (.errorRef e.id)
  for c in data.callables do
    out := out.push (.callable c.id)
    for b in c.blocks do
      out := out.push (.block c.id b.id)
      let mut ii : Nat := 0
      for _instr in b.instructions do
        out := out.push (.instruction c.id b.id (UInt32.ofNat ii))
        ii := ii + 1
      out := out.push (.terminator c.id b.id)
    -- ValueIds: callable params → all block params → all instruction results
    for p in c.params do
      out := out.push (.value c.id p.valueId)
    for b in c.blocks do
      for bp in b.params do
        out := out.push (.value c.id bp.valueId)
    for b in c.blocks do
      for instr in b.instructions do
        match instr.result with
        | some vd => out := out.push (.value c.id vd.valueId)
        | none => pure ()
    -- EffectIds present on Emit/ExternalCall/Schedule
    for b in c.blocks do
      for instr in b.instructions do
        match instr.op with
        | .emit effectId _ _ => out := out.push (.effect c.id effectId)
        | .externalCall effectId _ _ => out := out.push (.effect c.id effectId)
        | .schedule effectId _ _ => out := out.push (.effect c.id effectId)
        | _ => pure ()
  for inv in data.invariants do
    out := out.push (.invariant inv.id)
  let mut ri : Nat := 0
  for _req in data.requirements.items do
    out := out.push (.requirement (UInt32.ofNat ri))
    ri := ri + 1
  pure out

private def compareSourceOriginWire
    (left right : SourceOrigin) : Except SemanticWireErrorV1 Ordering := do
  let lB ← encodeSourceOrigin left
  let rB ← encodeSourceOrigin right
  pure (compareByteArrayLex lB rB)

/-- O(1) inventory membership via wire-key HashMap (exact path/start/end/nodeId). -/
private def buildOriginMemberSetV1
    (inventory : SourceNodeInventoryV1) :
    Except SemanticWireErrorV1 (Std.HashMap ByteArray Unit) := do
  let mut m : Std.HashMap ByteArray Unit :=
    Std.HashMap.emptyWithCapacity inventory.nodes.size
  for n in inventory.nodes do
    mapCommon (validateSourceOrigin n)
    let kb ← encodeSourceOrigin n
    m := m.insert kb ()
  pure m

/-- sourceModule components must be a (possibly equal) prefix of sourceIdentity.

    Binds module identity into the join without importing Source AST into Wire.
    Production callers pass Common.QualifiedName projections of ValidatedSourceV1
    moduleName / programIdentity; incomplete transport tests may pass equal names.
-/
private def qualifiedNameIsPrefixV1
    (modName full : QualifiedName) : Bool :=
  let pc := modName.components.toArray
  let fc := full.components.toArray
  if pc.size > fc.size then
    false
  else
    Id.run do
      let mut i := 0
      while i < pc.size do
        match pc[i]?, fc[i]? with
        | some a, some b =>
            if a != b then return false
        | _, _ => return false
        i := i + 1
      pure true

/-- Exact originMap equality: same length, same entity+origins per index
    (caller supplies originMaps already sorted by entity wire key). -/
private def originMapsExactEqualV1
    (left right : Array OriginBindingV1) : Bool :=
  if left.size != right.size then
    false
  else
    Id.run do
      let mut i := 0
      while i < left.size do
        match left[i]?, right[i]? with
        | some a, some b =>
            if !(a.entity == b.entity) then return false
            if a.origins.size != b.origins.size then return false
            let mut j := 0
            while j < a.origins.size do
              match a.origins[j]?, b.origins[j]? with
              | some oa, some ob =>
                  if oa != ob then return false
              | _, _ => return false
              j := j + 1
        | _, _ => return false
        i := i + 1
      pure true

/-- Low-level join helper: accepts caller-supplied expectedSourceHash and
    expectedOriginMap. **Not** the source-bound SPEC authority — that is
    `NormalizeV1.validateSemanticProvenanceV1`, which recomputes both from
    ValidatedSourceV1. Callers can self-certify with this helper; production
    paths must not treat it as complete provenance acceptance. -/
def validateSemanticProvenanceJoinV1
    (sourceModule : QualifiedName)
    (sourceIdentity : QualifiedName)
    (expectedSourceHash : Digest)
    (expectedOriginMap : Array OriginBindingV1)
    (nodeInventory : SourceNodeInventoryV1)
    (program : SemanticProgramV1)
    (provenance : SemanticProvenanceV1) : Except SemanticWireErrorV1 Unit := do
  -- schema exact
  unless provenance.schema.value == semanticProvenanceSchemaIdV1 do
    return ← err .badProvenance
  mapCommon (validateSchemaId provenance.schema)
  -- sourceModule binds module identity (prefix of sourceIdentity)
  mapCommon (validateQualifiedName sourceModule)
  mapCommon (validateQualifiedName sourceIdentity)
  unless qualifiedNameIsPrefixV1 sourceModule sourceIdentity do
    return ← err .badProvenance
  -- program structure + data
  let data ← match validateSemanticProgramV1 program with
    | .ok d => pure d
    | .error _ => return ← err .badProvenance
  -- qualifiedName exact vs program and sourceIdentity
  unless provenance.qualifiedName == data.qualifiedName do
    return ← err .badProvenance
  unless provenance.qualifiedName == sourceIdentity do
    return ← err .badProvenance
  -- digests well-formed
  mapCommon (validateDigest provenance.sourceHash)
  mapCommon (validateDigest provenance.semanticHash)
  mapCommon (validateDigest nodeInventory.sourceHash)
  mapCommon (validateDigest expectedSourceHash)
  -- Authoritative sourceHash: expected (source snapshot) == provenance == inventory.
  -- Mutually replaced foreign hashes that only agree with each other fail here.
  unless provenance.sourceHash == expectedSourceHash do
    return ← err .badProvenance
  unless nodeInventory.sourceHash == expectedSourceHash do
    return ← err .badProvenance
  unless provenance.sourceHash == nodeInventory.sourceHash do
    return ← err .badProvenance
  -- semanticHash exact vs program
  let expectedSem ← match semanticHashV1 program with
    | .ok h => pure h
    | .error _ => return ← err .badProvenance
  unless provenance.semanticHash == expectedSem do
    return ← err .badProvenance
  -- Exact originMap vs caller-rebuilt attribution (not mere inventory membership).
  unless originMapsExactEqualV1 provenance.originMap expectedOriginMap do
    return ← err .badProvenance
  -- originMap size limit already on encode; nonempty coverage enforced below
  unless provenance.originMap.size ≤ maxOriginBindings do
    return ← err .badProvenance
  -- Expected entity set (exact coverage)
  let expected := collectProgramEntityRefsV1 data
  -- Build encode-keyed maps for expected entities
  let mut expectedKeys : Array ByteArray := #[]
  for e in expected do
    let kb ← match encodeSemanticEntityRefV1 e with
      | .ok b => pure b
      | .error _ => return ← err .badProvenance
    expectedKeys := expectedKeys.push kb
  -- Sort expected keys for membership / uniqueness checks
  let expectedSorted :=
    expectedKeys.qsort fun a b => compareByteArrayLex a b == .lt
  -- Detect duplicate expected keys (should not happen for well-formed programs)
  if expectedSorted.size > 0 then
    for i in [1:expectedSorted.size] do
      if compareByteArrayLex expectedSorted[i - 1]! expectedSorted[i]! == .eq then
        return ← err .badProvenance
  -- Walk originMap: entity order unique ascending, exact set match
  unless provenance.originMap.size == expected.size do
    return ← err .badProvenance
  let originMembers ← buildOriginMemberSetV1 nodeInventory
  let mut prevEntityKey? : Option ByteArray := none
  let mut seenKeys : Array ByteArray := #[]
  for binding in provenance.originMap do
    -- Requirement index range
    match binding.entity with
    | .requirement idx =>
        unless idx.toNat < data.requirements.items.size do
          return ← err .badProvenance
    | _ => pure ()
    let entityKey ← match encodeSemanticEntityRefV1 binding.entity with
      | .ok b => pure b
      | .error _ => return ← err .badProvenance
    -- unique ascending by entity encode
    match prevEntityKey? with
    | none => pure ()
    | some prev =>
        match compareByteArrayLex prev entityKey with
        | .lt => pure ()
        | .eq | .gt => return ← err .badProvenance
    prevEntityKey? := some entityKey
    seenKeys := seenKeys.push entityKey
    -- origins nonempty
    if binding.origins.isEmpty then
      return ← err .badProvenance
    unless binding.origins.size ≤ maxOriginsPerBinding do
      return ← err .badProvenance
    -- origins unique ascending by common SourceOrigin wire key
    let mut prevOrigin? : Option SourceOrigin := none
    for origin in binding.origins do
      mapCommon (validateSourceOrigin origin)
      let originKey ← encodeSourceOrigin origin
      unless originMembers.contains originKey do
        return ← err .badProvenance
      match prevOrigin? with
      | none => pure ()
      | some prev =>
          let cmp ← compareSourceOriginWire prev origin
          match cmp with
          | .lt => pure ()
          | .eq | .gt => return ← err .badProvenance
      prevOrigin? := some origin
  -- Exact set equality: seen keys (already ascending unique) == expected sorted
  unless seenKeys.size == expectedSorted.size do
    return ← err .badProvenance
  for i in [:seenKeys.size] do
    unless compareByteArrayLex seenKeys[i]! expectedSorted[i]! == .eq do
      return ← err .badProvenance
  pure ()

/-- Low-level join-gated digest helper (see `validateSemanticProvenanceJoinV1`).
    Not the source-bound SPEC authority; production uses
    `NormalizeV1.semanticProvenanceDigestV1`. -/
def semanticProvenanceDigestJoinV1
    (sourceModule : QualifiedName)
    (sourceIdentity : QualifiedName)
    (expectedSourceHash : Digest)
    (expectedOriginMap : Array OriginBindingV1)
    (nodeInventory : SourceNodeInventoryV1)
    (program : SemanticProgramV1)
    (p : SemanticProvenanceV1) : Except SemanticWireErrorV1 Digest := do
  validateSemanticProvenanceJoinV1
    sourceModule sourceIdentity expectedSourceHash expectedOriginMap
    nodeInventory program p
  let bytes ← encodeSemanticProvenanceV1 p
  let _ ← decodeSemanticProvenanceV1 bytes
  pure (sha256Bytes bytes)

end ProofForgeV2.Semantic.WireV1
