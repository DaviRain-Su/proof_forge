import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.RequirementIdsV1
import ProofForgeV2.Semantic.Wire.ModelV1
import ProofForgeV2.Semantic.Wire.CodecV1
import ProofForgeV2.Semantic.Wire.ValueBytesV1
import ProofForgeV2.Semantic.Wire.TypeKeyV1
import ProofForgeV2.Semantic.Wire.NamesV1
import ProofForgeV2.Semantic.Wire.SignatureV1
import ProofForgeV2.Semantic.Wire.CfgShapeV1
import ProofForgeV2.Semantic.Wire.CfgTypingV1
import ProofForgeV2.Semantic.Wire.InvariantClosureV1
import ProofForgeV2.Semantic.Wire.RequirementsGateV1
import ProofForgeV2.Semantic.Wire.StructureV1
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
        · FieldSpec catalog: exact membership in the three-entry v1 catalog
          (`proof-forge.field.bn254-fr.v1`,
          `proof-forge.field.bls12-377-fr.v1`, or
          `proof-forge.field.goldilocks.v1`) with the catalog's exact
          modulusBE (`fieldSpecCatalogV1`; `.badType`)
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

/-- Compose a successful root encoding from the exact results of every sole
    production gate and field encoder. This theorem exposes no alternate
    traversal: all semantic fields and the root framing are still produced by
    the existing encoder authorities in their original error order. -/
theorem encodeSemanticProgramDataV1_eq_of_fields
    (p : SemanticProgramDataV1)
    (qualifiedNameB typesB constantsB stateB eventsB errorsB callablesB invariantsB
      requirementsB body : ByteArray)
    (hnameShape : validateProgramQualifiedNameShapeV1 p.qualifiedName = .ok ())
    (htypesSize : checkTableSize p.types.size = .ok ())
    (hconstantsSize : checkTableSize p.constants.size = .ok ())
    (hstateSize : checkTableSize p.logicalState.size = .ok ())
    (heventsSize : checkTableSize p.events.size = .ok ())
    (herrorsSize : checkTableSize p.errors.size = .ok ())
    (hcallablesSize : checkTableSize p.callables.size = .ok ())
    (hinvariantsSize : checkTableSize p.invariants.size = .ok ())
    (hstructure : validateSemanticProgramStructureV1 p = .ok ())
    (hname : encodeQualifiedName p.qualifiedName = .ok qualifiedNameB)
    (htypes : encodeArray encodeTypeDeclV1 p.types = .ok typesB)
    (hconstants : encodeArray encodeConstantV1 p.constants = .ok constantsB)
    (hstate : encodeArray encodeStateDeclV1 p.logicalState = .ok stateB)
    (hevents : encodeArray encodeEventDeclV1 p.events = .ok eventsB)
    (herrors : encodeArray encodeErrorDeclV1 p.errors = .ok errorsB)
    (hcallables : encodeArray encodeCallableV1 p.callables = .ok callablesB)
    (hinvariants : encodeArray encodeInvariantDeclV1 p.invariants = .ok invariantsB)
    (hrequirements : encodeProgramRequirementsV1 p.requirements = .ok requirementsB)
    (hbody : encodeTagged "SemanticProgram.Data" #[qualifiedNameB, typesB, constantsB,
      stateB, eventsB, errorsB, callablesB, invariantsB, requirementsB] = .ok body)
    (houtSize : ((encodeMagicPrefix semanticProgramMagicV1).append body).size ≤
      maxCanonicalProgramBytes) :
    encodeSemanticProgramDataV1 p =
      .ok ((encodeMagicPrefix semanticProgramMagicV1).append body) := by
  simp only [encodeSemanticProgramDataV1, hnameShape, htypesSize, hconstantsSize,
    hstateSize, heventsSize, herrorsSize, hcallablesSize, hinvariantsSize, hstructure,
    hname, htypes, hconstants, hstate, hevents, herrors, hcallables, hinvariants,
    hrequirements, hbody, houtSize, ↓reduceIte, Bind.bind, Pure.pure, Except.bind,
    Except.pure]

/-- Sole production body for the nine-field `SemanticProgram.Data` record. -/
def decodeSemanticProgramDataBodyV1 : Decoder SemanticProgramDataV1 := fun c => do
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

/-- Sole tagged production decoder for the root data record. -/
def decodeSemanticProgramDataTaggedV1 : Decoder SemanticProgramDataV1 :=
  withTaggedNesting decodeSemanticProgramDataBodyV1

/-- Compose the root body from the actual production field decoders in exact
    wire order. -/
theorem decodeSemanticProgramDataBodyV1_eq_of_fields
    (c cTag cName cTypes cConstants cState cEvents cErrors cCallables cInvariants
      cRequirements : Cursor)
    (qualifiedName : QualifiedName) (types : Array TypeDeclV1)
    (constants : Array ConstantV1) (logicalState : Array StateDeclV1)
    (events : Array EventDeclV1) (errors : Array ErrorDeclV1)
    (callables : Array CallableV1) (invariants : Array InvariantDeclV1)
    (requirements : ProgramRequirementsV1)
    (htag : expectTag "SemanticProgram.Data" 9 c = .ok ((), cTag))
    (hname : decodeQualifiedName cTag = .ok (qualifiedName, cName))
    (htypes : decodeArray maxTableElements decodeTypeDeclV1 cName = .ok (types, cTypes))
    (hconstants : decodeArray maxTableElements decodeConstantV1 cTypes =
      .ok (constants, cConstants))
    (hstate : decodeArray maxTableElements decodeStateDeclV1 cConstants =
      .ok (logicalState, cState))
    (hevents : decodeArray maxTableElements decodeEventDeclV1 cState = .ok (events, cEvents))
    (herrors : decodeArray maxTableElements decodeErrorDeclV1 cEvents = .ok (errors, cErrors))
    (hcallables : decodeArray maxTableElements decodeCallableV1 cErrors =
      .ok (callables, cCallables))
    (hinvariants : decodeArray maxTableElements decodeInvariantDeclV1 cCallables =
      .ok (invariants, cInvariants))
    (hrequirements : decodeProgramRequirementsV1 cInvariants =
      .ok (requirements, cRequirements)) :
    decodeSemanticProgramDataBodyV1 c = .ok ({
      qualifiedName, types, constants, logicalState, events, errors,
      callables, invariants, requirements
    }, cRequirements) := by
  simp only [decodeSemanticProgramDataBodyV1, htag, hname, htypes, hconstants,
    hstate, hevents, herrors, hcallables, hinvariants, hrequirements, Bind.bind,
    Pure.pure, Except.bind, Except.pure]

/-- Compose a successful root body through its tagged nesting frame. -/
theorem decodeSemanticProgramDataTaggedV1_eq_of_bodyV1 (c : Cursor)
    (data : SemanticProgramDataV1) (c' : Cursor)
    (hdepth : c.nesting < maxNesting)
    (hbody : decodeSemanticProgramDataBodyV1 ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok (data, c')) :
    decodeSemanticProgramDataTaggedV1 c =
      .ok (data, ⟨c'.input, c'.offset, c.nesting⟩) := by
  unfold decodeSemanticProgramDataTaggedV1 withTaggedNesting
  simp only [hdepth, ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure, hbody]

/-- Compose all nine root fields directly through the tagged root decoder. -/
theorem decodeSemanticProgramDataTaggedV1_eq_of_fields
    (c cTag cName cTypes cConstants cState cEvents cErrors cCallables cInvariants
      cRequirements : Cursor)
    (qualifiedName : QualifiedName) (types : Array TypeDeclV1)
    (constants : Array ConstantV1) (logicalState : Array StateDeclV1)
    (events : Array EventDeclV1) (errors : Array ErrorDeclV1)
    (callables : Array CallableV1) (invariants : Array InvariantDeclV1)
    (requirements : ProgramRequirementsV1) (hdepth : c.nesting < maxNesting)
    (htag : expectTag "SemanticProgram.Data" 9 ⟨c.input, c.offset, c.nesting + 1⟩ =
      .ok ((), cTag))
    (hname : decodeQualifiedName cTag = .ok (qualifiedName, cName))
    (htypes : decodeArray maxTableElements decodeTypeDeclV1 cName = .ok (types, cTypes))
    (hconstants : decodeArray maxTableElements decodeConstantV1 cTypes =
      .ok (constants, cConstants))
    (hstate : decodeArray maxTableElements decodeStateDeclV1 cConstants =
      .ok (logicalState, cState))
    (hevents : decodeArray maxTableElements decodeEventDeclV1 cState = .ok (events, cEvents))
    (herrors : decodeArray maxTableElements decodeErrorDeclV1 cEvents = .ok (errors, cErrors))
    (hcallables : decodeArray maxTableElements decodeCallableV1 cErrors =
      .ok (callables, cCallables))
    (hinvariants : decodeArray maxTableElements decodeInvariantDeclV1 cCallables =
      .ok (invariants, cInvariants))
    (hrequirements : decodeProgramRequirementsV1 cInvariants =
      .ok (requirements, cRequirements)) :
    decodeSemanticProgramDataTaggedV1 c = .ok ({
      qualifiedName, types, constants, logicalState, events, errors,
      callables, invariants, requirements
    }, ⟨cRequirements.input, cRequirements.offset, c.nesting⟩) :=
  decodeSemanticProgramDataTaggedV1_eq_of_bodyV1 c {
    qualifiedName, types, constants, logicalState, events, errors,
    callables, invariants, requirements
  } cRequirements hdepth
    (decodeSemanticProgramDataBodyV1_eq_of_fields
      ⟨c.input, c.offset, c.nesting + 1⟩ cTag cName cTypes cConstants cState cEvents
      cErrors cCallables cInvariants cRequirements qualifiedName types constants logicalState
      events errors callables invariants requirements htag hname htypes hconstants hstate hevents
      herrors hcallables hinvariants hrequirements)

/-- Transport decode only: magic/tags/limits/nesting/trailing. No structure gate. -/
def decodeSemanticProgramDataV1 (bytes : ByteArray) :
    Except SemanticWireErrorV1 SemanticProgramDataV1 := do
  unless bytes.size ≤ maxCanonicalProgramBytes do
    return ← err .limitExceeded
  let c := start bytes
  let ((), c) ← consumeMagic semanticProgramMagicV1 c
  let (data, c) ← decodeSemanticProgramDataTaggedV1 c
  finish c
  pure data

/-- Compose a fully consumed transport carrier through the production size,
    magic, tagged-root, and finish authorities. -/
theorem decodeSemanticProgramDataV1_eq_of_framing (bytes : ByteArray)
    (afterMagic afterData : Cursor) (data : SemanticProgramDataV1)
    (hsize : bytes.size ≤ maxCanonicalProgramBytes)
    (hmagic : consumeMagic semanticProgramMagicV1 (start bytes) = .ok ((), afterMagic))
    (hdata : decodeSemanticProgramDataTaggedV1 afterMagic = .ok (data, afterData))
    (hfinish : finish afterData = .ok ()) :
    decodeSemanticProgramDataV1 bytes = .ok data := by
  simp only [decodeSemanticProgramDataV1, hsize, ↓reduceIte, hmagic, hdata, hfinish,
    Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Once size, magic, and root decode succeed, the production finish error is
    preserved exactly (including `.trailingBytes`). -/
theorem decodeSemanticProgramDataV1_eq_of_finish_error (bytes : ByteArray)
    (afterMagic afterData : Cursor) (data : SemanticProgramDataV1)
    (error : SemanticWireErrorV1)
    (hsize : bytes.size ≤ maxCanonicalProgramBytes)
    (hmagic : consumeMagic semanticProgramMagicV1 (start bytes) = .ok ((), afterMagic))
    (hdata : decodeSemanticProgramDataTaggedV1 afterMagic = .ok (data, afterData))
    (hfinish : finish afterData = .error error) :
    decodeSemanticProgramDataV1 bytes = .error error := by
  simp only [decodeSemanticProgramDataV1, hsize, ↓reduceIte, hmagic, hdata, hfinish,
    Bind.bind, Pure.pure, Except.bind, Except.pure]

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

/-- Compose carrier acceptance through transport decode and the actual
    structure-gated production encoder returning exact byte identity. -/
theorem decodeSemanticProgramV1_eq_of_identity (bytes reencoded : ByteArray)
    (data : SemanticProgramDataV1)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data)
    (hencode : encodeSemanticProgramDataV1 data = .ok reencoded)
    (hidentity : (reencoded == bytes) = true) :
    decodeSemanticProgramV1 bytes = .ok ⟨bytes⟩ := by
  simp only [decodeSemanticProgramV1, hdecode, hencode, hidentity, ↓reduceIte,
    Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Preserve the carrier's exact `.nonCanonical` result when the production
    structure-gated re-encode succeeds but differs from the input bytes. -/
theorem decodeSemanticProgramV1_eq_of_mismatch (bytes reencoded : ByteArray)
    (data : SemanticProgramDataV1)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data)
    (hencode : encodeSemanticProgramDataV1 data = .ok reencoded)
    (hmismatch : (reencoded == bytes) = false) :
    decodeSemanticProgramV1 bytes = .error .nonCanonical := by
  simp only [decodeSemanticProgramV1, hdecode, hencode, hmismatch, Bool.false_eq_true,
    ↓reduceIte, Bind.bind, Except.bind, err]

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

/-- Compose exact carrier validation from the sole production decoder,
    structure-gated encoder, byte identity, and explicit structure gate. -/
theorem validateSemanticProgramV1_eq_ok_of_identity
    (program : SemanticProgramV1)
    (data : SemanticProgramDataV1)
    (reencoded : ByteArray)
    (hdecode : decodeSemanticProgramDataV1 program.canonicalBytes = .ok data)
    (hencode : encodeSemanticProgramDataV1 data = .ok reencoded)
    (hidentity : (reencoded == program.canonicalBytes) = true)
    (hstructure : validateSemanticProgramStructureV1 data = .ok ()) :
    validateSemanticProgramV1 program = .ok data := by
  simp only [validateSemanticProgramV1, hdecode, hencode, hidentity, hstructure,
    ↓reduceIte, Bind.bind, Pure.pure, Except.bind, Except.pure]

/-- Reflexivity of `ByteArray` boolean equality (sole production `BEq`). -/
theorem byteArray_beq_self_v1 (bytes : ByteArray) : (bytes == bytes) = true := by
  cases bytes with
  | mk data =>
      change (data == data) = true
      exact beq_self_eq_true data

/-- Peel a successful Unit-discarding monadic step from the production
    `Except` encoder. Used only to recover gates already executed by
    `encodeSemanticProgramDataV1`; no alternate encoder. -/
private theorem except_bind_unit_ok_v1 {ε α}
    {x : Except ε Unit} {y : Except ε α} {a : α}
    (h : x >>= (fun _ => y) = .ok a) : x = .ok () ∧ y = .ok a := by
  cases x with
  | error e =>
      simp only [Bind.bind, Except.bind] at h
      cases h
  | ok u =>
      cases u
      simp only [Bind.bind, Except.bind] at h
      exact ⟨rfl, h⟩

/-- Successful structure-gated encode implies the explicit structure gate
    already returned `.ok ()`. Parametric over every admitted program data. -/
theorem encodeSemanticProgramDataV1_ok_implies_structure
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (h : encodeSemanticProgramDataV1 data = .ok bytes) :
    validateSemanticProgramStructureV1 data = .ok () := by
  simp only [encodeSemanticProgramDataV1] at h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨_, h⟩ := except_bind_unit_ok_v1 h
  obtain ⟨hstructure, _⟩ := except_bind_unit_ok_v1 h
  exact hstructure

/-- Parametric carrier validation from sole production encode + transport
    decode of the exact same data. Closes `validateSemanticProgramV1` without
    replaying structure phase-by-phase when the author already has both
    encode/decode witnesses (Normalize encode path + decode refinement).

    Full parametric `decode ∘ encode = id` remains a separate gap; this lemma
    consumes that witness rather than inventing a second semantic model. -/
theorem validateSemanticProgramV1_eq_ok_of_encode_decode
    (data : SemanticProgramDataV1) (bytes : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 bytes = .ok data) :
    validateSemanticProgramV1 ⟨bytes⟩ = .ok data :=
  validateSemanticProgramV1_eq_ok_of_identity
    ⟨bytes⟩ data bytes hdecode hencode
    (byteArray_beq_self_v1 bytes)
    (encodeSemanticProgramDataV1_ok_implies_structure data bytes hencode)

/-- When transport decode recovers the same data that re-encodes to different
    bytes, validation fails closed with `.nonCanonical`. Sound byte-mutation
    negative for any encode/decode pair. -/
theorem validateSemanticProgramV1_eq_error_of_encode_decode_mismatch
    (data : SemanticProgramDataV1) (bytes mutated : ByteArray)
    (hencode : encodeSemanticProgramDataV1 data = .ok bytes)
    (hdecode : decodeSemanticProgramDataV1 mutated = .ok data)
    (hmismatch : (bytes == mutated) = false) :
    validateSemanticProgramV1 ⟨mutated⟩ = .error .nonCanonical := by
  simp only [validateSemanticProgramV1, hdecode, hencode, hmismatch,
    Bool.false_eq_true, ↓reduceIte, Bind.bind, Except.bind, err]

def semanticHashV1 (p : SemanticProgramV1) : Except SemanticWireErrorV1 Digest := do
  let _ ← validateSemanticProgramV1 p
  pure (sha256Bytes p.canonicalBytes)

def SemanticProgramV1.invariants (p : SemanticProgramV1) : Array InvariantDeclV1 :=
  match validateSemanticProgramV1 p with
  | .ok data => data.invariants
  | .error _ => #[]

/-- Successful validation recovers the exact invariants table. -/
theorem SemanticProgramV1.invariants_eq_of_validate
    (program : SemanticProgramV1) (data : SemanticProgramDataV1)
    (h : validateSemanticProgramV1 program = .ok data) :
    program.invariants = data.invariants := by
  simp only [SemanticProgramV1.invariants, h]

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
