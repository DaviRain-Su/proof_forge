import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Unicode
import ProofForgeV2.Semantic.Wire.ModelV1

/-!
  ProofForgeV2.Semantic.Wire.NamesV1 — declaration/field/parameter name
  uniqueness gates and SPEC §6 identifier grammar.

  Public declarations live in namespace `ProofForgeV2.Semantic.WireV1`.
-/
namespace ProofForgeV2.Semantic.WireV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.Unicode

/-- Exact declaration/field names are checked on a private UTF-8 sort so
    public source-order arrays remain unchanged and duplicate detection stays
    non-quadratic at the wire table limit. -/
-- Internal production exact-name uniqueness phase exposed for refinement.
-- Complete declaration-name acceptance remains owned by the structure gate.
def checkUniqueDeclarationNamesV1 (names : Array String) :
    Except SemanticWireErrorV1 Unit := do
  -- Empty/singleton tables are unique without allocating a private sort.
  if names.size ≤ 1 then return
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
def validateNamedTypeNameUniquenessV1 (types : Array TypeDeclV1) :
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
def validateConstantNameUniquenessV1 (constants : Array ConstantV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (constants.map (·.name))

/-- StateDecl names are exact-string unique within logicalState (SPEC §6).
    Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
def validateLogicalStateNameUniquenessV1
    (logicalState : Array StateDeclV1) : Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (logicalState.map (·.name))

/-- EventDecl names are exact-string unique within events (SPEC §6).
    Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
def validateEventNameUniquenessV1 (events : Array EventDeclV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (events.map (·.name))

/-- ErrorDecl names are exact-string unique within errors (SPEC §6).
    Identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
def validateErrorNameUniquenessV1 (errors : Array ErrorDeclV1) :
    Except SemanticWireErrorV1 Unit :=
  checkUniqueDeclarationNamesV1 (errors.map (·.name))

/-- Event/error interface-field names are exact-string unique within each
    declaration (SPEC §6). Each declaration gets an independent namespace;
    identifier grammar/NFC is enforced by the later declaration-name
    structure gate. -/
def validateInterfaceFieldNameUniquenessV1
    (events : Array EventDeclV1) (errors : Array ErrorDeclV1) :
    Except SemanticWireErrorV1 Unit := do
  for eventDecl in events do
    checkUniqueDeclarationNamesV1 (eventDecl.fields.map (·.name))
  for errorDecl in errors do
    checkUniqueDeclarationNamesV1 (errorDecl.fields.map (·.name))
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

/-- Internal WireV1-family phase entry (not a public contract; see `validateSemanticProgramStructureV1`). -/
def validateDeclarationIdentifierNamesV1
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

end ProofForgeV2.Semantic.WireV1
