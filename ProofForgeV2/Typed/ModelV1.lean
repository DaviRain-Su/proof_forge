import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.QualifiedNameV1
import ProofForgeV2.Source.WireV1
import ProofForgeV2.Typed.DiagnosticDraftV1

namespace ProofForgeV2.Typed.ModelV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.QualifiedNameV1
open ProofForgeV2.Source.WireV1
open ProofForgeV2.Typed.DiagnosticDraftV1

/-- One of the thirteen top-level ProgramV1 declaration alternatives. -/
inductive DeclKindV1 where
  | state
  | struct
  | enum
  | const
  | event
  | error
  | init
  | entry
  | view
  | fn
  | invariant
  | extensionReq
  | proof
deriving BEq, DecidableEq, Repr, Inhabited

namespace DeclKindV1

def toString : DeclKindV1 → String
  | .state => "state"
  | .struct => "struct"
  | .enum => "enum"
  | .const => "const"
  | .event => "event"
  | .error => "error"
  | .init => "init"
  | .entry => "entry"
  | .view => "view"
  | .fn => "fn"
  | .invariant => "invariant"
  | .extensionReq => "extension"
  | .proof => "proof"

end DeclKindV1

instance : ToString DeclKindV1 := ⟨DeclKindV1.toString⟩

/-- Generic source-order declaration table: key to (ordinal, payload). -/
structure DeclTableV1 (K V : Type) [BEq K] where
  entries : Array (K × Nat × V)
deriving Repr

namespace DeclTableV1

variable {K V : Type} [BEq K]

def empty : DeclTableV1 K V := ⟨#[]⟩

def insert (table : DeclTableV1 K V) (key : K) (ordinal : Nat) (value : V) :
    DeclTableV1 K V :=
  ⟨table.entries.push (key, ordinal, value)⟩

/-- First matching entry, preserving source order. -/
def find? (table : DeclTableV1 K V) (key : K) : Option (Nat × V) :=
  table.entries.findSome? fun (k, o, v) =>
    if k == key then some (o, v) else none

def toArray (table : DeclTableV1 K V) : Array (K × Nat × V) := table.entries

def size (table : DeclTableV1 K V) : Nat := table.entries.size

/-- True iff any key appears more than once in source order. -/
def hasDuplicateKey (table : DeclTableV1 K V) : Bool :=
  go table.entries.toList []
where
  go : List (K × Nat × V) → List K → Bool
    | [], _ => false
    | (k, _, _) :: rest, seen => if seen.contains k then true else go rest (k :: seen)

/-- All table ordinals for `key` in source order. -/
def ordinalsForKey (table : DeclTableV1 K V) (key : K) : Array Nat :=
  table.entries.filterMap fun (k, o, _) => if k == key then some o else none

end DeclTableV1

/-- Aligned Program.items indices for each declaration table entry (source order).
    Invariant: for each kind, `indices.size == table.size` and
    `indices[ordinal]` is the Program.items index of that entry. -/
structure DeclItemIndicesV1 where
  state : Array Nat
  struct : Array Nat
  enum : Array Nat
  const : Array Nat
  event : Array Nat
  error : Array Nat
  init : Array Nat
  entry : Array Nat
  view : Array Nat
  fn : Array Nat
  invariant : Array Nat
  extensionReq : Array Nat
  proof : Array Nat
deriving Repr, Inhabited

def emptyDeclItemIndicesV1 : DeclItemIndicesV1 :=
  { state := #[], struct := #[], enum := #[], const := #[], event := #[],
    error := #[], init := #[], entry := #[], view := #[], fn := #[],
    invariant := #[], extensionReq := #[], proof := #[] }

/-- Typed declaration skeletons directly over ProgramV1, one table per kind,
    plus aligned item-index sidecar for exact Program.items path lookup. -/
structure TypedDeclTablesV1 where
  state : DeclTableV1 SourceNameComponentV1 StateDeclV1
  struct : DeclTableV1 SourceNameComponentV1 StructDeclV1
  enum : DeclTableV1 SourceNameComponentV1 EnumDeclV1
  const : DeclTableV1 SourceNameComponentV1 ConstDeclV1
  event : DeclTableV1 SourceNameComponentV1 EventDeclV1
  error : DeclTableV1 SourceNameComponentV1 ErrorDeclV1
  init : DeclTableV1 Unit InitDeclV1
  entry : DeclTableV1 SourceNameComponentV1 EntryDeclV1
  view : DeclTableV1 SourceNameComponentV1 ViewDeclV1
  fn : DeclTableV1 SourceNameComponentV1 FnDeclV1
  invariant : DeclTableV1 SourceNameComponentV1 InvariantDeclV1
  extensionReq : DeclTableV1 SourceQualifiedNameV1 ExtensionReqV1
  proof : DeclTableV1 SourceNameComponentV1 ProofDeclV1
  itemIndices : DeclItemIndicesV1
deriving Repr

/-- Result of name resolution over a validated ProgramV1 source unit. -/
structure NameResolutionResultV1 where
  tables : TypedDeclTablesV1
  diagnostics : Array DiagnosticV1
  ok : Bool
deriving Repr

/-- Canonical Program.items[index] path (sole childPath helper). -/
def programItemPathV1 (itemIndex : Nat) :
    Except String NormalizedSyntacticPathV1 :=
  indexChildPathV1 #[] "Program" "items" itemIndex

/-- Item-index array for a declaration kind. -/
def itemIndicesForKind (tables : TypedDeclTablesV1) (kind : DeclKindV1) : Array Nat :=
  match kind with
  | .state => tables.itemIndices.state
  | .struct => tables.itemIndices.struct
  | .enum => tables.itemIndices.enum
  | .const => tables.itemIndices.const
  | .event => tables.itemIndices.event
  | .error => tables.itemIndices.error
  | .init => tables.itemIndices.init
  | .entry => tables.itemIndices.entry
  | .view => tables.itemIndices.view
  | .fn => tables.itemIndices.fn
  | .invariant => tables.itemIndices.invariant
  | .extensionReq => tables.itemIndices.extensionReq
  | .proof => tables.itemIndices.proof

/-- Lookup Program.items index for (kind, ordinal). -/
def itemIndexForOrdinal? (tables : TypedDeclTablesV1) (kind : DeclKindV1)
    (ordinal : Nat) : Option Nat :=
  (itemIndicesForKind tables kind)[ordinal]?

/-- Exact item path for (kind, ordinal). -/
def itemPathForOrdinal? (tables : TypedDeclTablesV1) (kind : DeclKindV1)
    (ordinal : Nat) : Option NormalizedSyntacticPathV1 :=
  match itemIndexForOrdinal? tables kind ordinal with
  | none => none
  | some idx =>
      match programItemPathV1 idx with
      | .ok p => some p
      | .error _ => none

/-- First matching named declaration's item path (state/const/fn/…). -/
def itemPathForNamed? (tables : TypedDeclTablesV1) (kind : DeclKindV1)
    (name : SourceNameComponentV1) : Option NormalizedSyntacticPathV1 :=
  let ordinal? : Option Nat :=
    match kind with
    | .state => tables.state.find? name |>.map (·.1)
    | .struct => tables.struct.find? name |>.map (·.1)
    | .enum => tables.enum.find? name |>.map (·.1)
    | .const => tables.const.find? name |>.map (·.1)
    | .event => tables.event.find? name |>.map (·.1)
    | .error => tables.error.find? name |>.map (·.1)
    | .entry => tables.entry.find? name |>.map (·.1)
    | .view => tables.view.find? name |>.map (·.1)
    | .fn => tables.fn.find? name |>.map (·.1)
    | .invariant => tables.invariant.find? name |>.map (·.1)
    | .proof => tables.proof.find? name |>.map (·.1)
    | .init | .extensionReq => none
  ordinal?.bind (itemPathForOrdinal? tables kind)

/-- All item paths for a named key in a table (source-order ordinals). -/
def itemPathsForNamedKey {V} (table : DeclTableV1 SourceNameComponentV1 V)
    (indices : Array Nat) (name : SourceNameComponentV1) :
    Array NormalizedSyntacticPathV1 :=
  (table.ordinalsForKey name).filterMap fun o =>
    match indices[o]? with
    | none => none
    | some idx =>
        match programItemPathV1 idx with
        | .ok p => some p
        | .error _ => none

/-- Sole-helper wrappers for declaration sub-paths (B7b2 TypeCheck related).
    Fail closed to `none` — callers must not fabricate paths. -/
private def directChildPath?
    (parent : NormalizedSyntacticPathV1) (parentTag fieldTag : String) :
    Option NormalizedSyntacticPathV1 :=
  match directChildPathV1 parent parentTag fieldTag with
  | .ok p => some p
  | .error _ => none

private def indexChildPath?
    (parent : NormalizedSyntacticPathV1) (parentTag fieldTag : String) (index : Nat) :
    Option NormalizedSyntacticPathV1 :=
  match indexChildPathV1 parent parentTag fieldTag index with
  | .ok p => some p
  | .error _ => none

/-- ConstDecl type child path (const value expected-type related).
    State assign/place related uses StateDecl item paths via itemPathForNamed?
    (not StateDecl.type) — no stateTypePath? helper. -/
def constTypePath? (tables : TypedDeclTablesV1) (name : SourceNameComponentV1) :
    Option NormalizedSyntacticPathV1 :=
  (itemPathForNamed? tables .const name).bind fun ip =>
    directChildPath? ip "ConstDecl" "type"

/-- Struct field path by field name (StructDecl.fields[i]). -/
def structFieldPath? (tables : TypedDeclTablesV1)
    (structName fieldName : SourceNameComponentV1) :
    Option NormalizedSyntacticPathV1 :=
  match tables.struct.find? structName with
  | none => none
  | some (ord, decl) =>
      match decl.fields.findIdx? (·.name == fieldName) with
      | none => none
      | some fi =>
          (itemPathForOrdinal? tables .struct ord).bind fun ip =>
            indexChildPath? ip "StructDecl" "fields" fi

/-- Enum variant path by variant name (EnumDecl.variants[i]). -/
def enumVariantPath? (tables : TypedDeclTablesV1)
    (enumName variantName : SourceNameComponentV1) :
    Option NormalizedSyntacticPathV1 :=
  match tables.enum.find? enumName with
  | none => none
  | some (ord, decl) =>
      match decl.variants.findIdx? (·.name == variantName) with
      | none => none
      | some vi =>
          (itemPathForOrdinal? tables .enum ord).bind fun ip =>
            indexChildPath? ip "EnumDecl" "variants" vi

/-- Callable result type path for entry/view/fn by name. -/
def callableResultPath? (tables : TypedDeclTablesV1)
    (kind : DeclKindV1) (name : SourceNameComponentV1) :
    Option NormalizedSyntacticPathV1 :=
  let tag? : Option String :=
    match kind with
    | .entry => some "EntryDecl"
    | .view => some "ViewDecl"
    | .fn => some "FnDecl"
    | _ => none
  match tag? with
  | none => none
  | some tag =>
      (itemPathForNamed? tables kind name).bind fun ip =>
        directChildPath? ip tag "result"

/-- Fn parameter path at index. -/
def fnParamPath? (tables : TypedDeclTablesV1)
    (fnName : SourceNameComponentV1) (paramIndex : Nat) :
    Option NormalizedSyntacticPathV1 :=
  (itemPathForNamed? tables .fn fnName).bind fun ip =>
    indexChildPath? ip "FnDecl" "params" paramIndex

/-- ErrorDecl parameter path at index. -/
def errorParamPath? (tables : TypedDeclTablesV1)
    (errorName : SourceNameComponentV1) (paramIndex : Nat) :
    Option NormalizedSyntacticPathV1 :=
  (itemPathForNamed? tables .error errorName).bind fun ip =>
    indexChildPath? ip "ErrorDecl" "params" paramIndex

/-- EventDecl parameter path at index. -/
def eventParamPath? (tables : TypedDeclTablesV1)
    (eventName : SourceNameComponentV1) (paramIndex : Nat) :
    Option NormalizedSyntacticPathV1 :=
  (itemPathForNamed? tables .event eventName).bind fun ip =>
    indexChildPath? ip "EventDecl" "params" paramIndex

/-- Optional path as 0-or-1 array (related helper). -/
def optRelatedPath (p? : Option NormalizedSyntacticPathV1) :
    Array NormalizedSyntacticPathV1 :=
  match p? with
  | some p => #[p]
  | none => #[]

/-- Sidecar size invariant (engineering check). -/
def itemIndicesAligned (tables : TypedDeclTablesV1) : Bool :=
  tables.itemIndices.state.size == tables.state.size &&
  tables.itemIndices.struct.size == tables.struct.size &&
  tables.itemIndices.enum.size == tables.enum.size &&
  tables.itemIndices.const.size == tables.const.size &&
  tables.itemIndices.event.size == tables.event.size &&
  tables.itemIndices.error.size == tables.error.size &&
  tables.itemIndices.init.size == tables.init.size &&
  tables.itemIndices.entry.size == tables.entry.size &&
  tables.itemIndices.view.size == tables.view.size &&
  tables.itemIndices.fn.size == tables.fn.size &&
  tables.itemIndices.invariant.size == tables.invariant.size &&
  tables.itemIndices.extensionReq.size == tables.extensionReq.size &&
  tables.itemIndices.proof.size == tables.proof.size

/-- Fixed stableContext tokens per resolution diagnostic family. -/
def stableUnknownName : String := "typed.nr.unknown-name"
def stableWrongCategory : String := "typed.nr.wrong-category"
def stableAmbiguousName : String := "typed.nr.ambiguous-name"
def stableDuplicateDecl : String := "typed.nr.duplicate-declaration"
def stableDuplicateInit : String := "typed.nr.duplicate-init"
def stableDuplicateExtension : String := "typed.nr.duplicate-extension"
def stableLocalAsFunction : String := "typed.nr.local-as-function"
def stableUnknownQualified : String := "typed.nr.unknown-qualified-name"

/-- Typed name-resolution diagnostic drafts (location attached by NameResolution). -/
def unknownNameDiagnosticDraft (name : SourceNameComponentV1) (expected : String) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"unknown name '{name.raw}' (expected {expected})"
    (expected := some (.string expected))
    (actual := some (.string name.raw))
    (stableContext := some stableUnknownName)

def wrongCategoryDiagnosticDraft (name : SourceNameComponentV1) (actual : DeclKindV1)
    (expected : String) : TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"name '{name.raw}' resolved to {actual} but expected {expected}"
    (expected := some (.string expected))
    (actual := some (.string actual.toString))
    (context := some (.object #[
      ("name", .string name.raw),
      ("resolvedKind", .string actual.toString)
    ]))
    (stableContext := some stableWrongCategory)

def ambiguousNameDiagnosticDraft (name : SourceNameComponentV1) (expected : String) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"ambiguous name '{name.raw}' (expected {expected})"
    (expected := some (.string expected))
    (actual := some (.string name.raw))
    (stableContext := some stableAmbiguousName)

def duplicateDeclarationDiagnosticDraft (name : SourceNameComponentV1)
    (kind : DeclKindV1) : TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"duplicate {kind} declaration '{name.raw}'"
    (expected := some (.string "unique declaration name"))
    (actual := some (.string name.raw))
    (context := some (.object #[
      ("kind", .string kind.toString),
      ("name", .string name.raw)
    ]))
    (stableContext := some stableDuplicateDecl)

def sourceQualifiedNameV1ToString (name : SourceQualifiedNameV1) : String :=
  String.intercalate "." ((NonEmptyArray.toArray name.components).map (·.raw) |>.toList)

def unknownQualifiedNameDiagnosticDraft (name : SourceQualifiedNameV1)
    (expected : String) : TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"unknown name '{sourceQualifiedNameV1ToString name}' (expected {expected})"
    (expected := some (.string expected))
    (actual := some (.string (sourceQualifiedNameV1ToString name)))
    (stableContext := some stableUnknownQualified)

def localAsFunctionDiagnosticDraft (name : SourceNameComponentV1) (kind : String) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"name '{name.raw}' is bound as a {kind} but used as a function"
    (expected := some (.string "function"))
    (actual := some (.string kind))
    (context := some (.object #[
      ("name", .string name.raw),
      ("binding", .string kind)
    ]))
    (stableContext := some stableLocalAsFunction)

def duplicateInitDiagnosticDraft : TypedDiagnosticDraftV1 :=
  make .sourceInvalid "duplicate init declaration"
    (expected := some (.string "at most one init"))
    (actual := some (.string "init"))
    (stableContext := some stableDuplicateInit)

def duplicateExtensionReqDiagnosticDraft (name : SourceQualifiedNameV1) :
    TypedDiagnosticDraftV1 :=
  make .sourceInvalid
    s!"duplicate extension requirement '{sourceQualifiedNameV1ToString name}'"
    (expected := some (.string "unique extension requirement"))
    (actual := some (.string (sourceQualifiedNameV1ToString name)))
    (stableContext := some stableDuplicateExtension)

/-- Public unlocated helpers: erase projections of the draft builders. -/
def unknownNameDiagnostic (name : SourceNameComponentV1) (expected : String) :
    DiagnosticV1 :=
  erase (unknownNameDiagnosticDraft name expected)

def wrongCategoryDiagnostic (name : SourceNameComponentV1) (actual : DeclKindV1)
    (expected : String) : DiagnosticV1 :=
  erase (wrongCategoryDiagnosticDraft name actual expected)

def ambiguousNameDiagnostic (name : SourceNameComponentV1) (expected : String) :
    DiagnosticV1 :=
  erase (ambiguousNameDiagnosticDraft name expected)

def duplicateDeclarationDiagnostic (name : SourceNameComponentV1)
    (kind : DeclKindV1) : DiagnosticV1 :=
  erase (duplicateDeclarationDiagnosticDraft name kind)

def unknownQualifiedNameDiagnostic (name : SourceQualifiedNameV1) (expected : String) :
    DiagnosticV1 :=
  erase (unknownQualifiedNameDiagnosticDraft name expected)

def localAsFunctionDiagnostic (name : SourceNameComponentV1) (kind : String) :
    DiagnosticV1 :=
  erase (localAsFunctionDiagnosticDraft name kind)

def duplicateInitDiagnostic : DiagnosticV1 :=
  erase duplicateInitDiagnosticDraft

def duplicateExtensionReqDiagnostic (name : SourceQualifiedNameV1) : DiagnosticV1 :=
  erase (duplicateExtensionReqDiagnosticDraft name)

end ProofForgeV2.Typed.ModelV1
