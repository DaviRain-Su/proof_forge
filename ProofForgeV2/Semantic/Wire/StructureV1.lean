import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
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

/-!
  ProofForgeV2.Semantic.Wire.StructureV1 — sole
  `validateSemanticProgramStructureV1` orchestration over Wire phase modules.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

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
def validateProgramQualifiedNameShapeV1 (name : QualifiedName) :
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

end ProofForgeV2.Semantic.WireV1
