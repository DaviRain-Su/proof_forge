import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.AstDeclV1
import ProofForgeV2.Source.AstProgramItemV1
import ProofForgeV2.Source.AstSpineDeclV1
import ProofForgeV2.Source.NameComponentV1
import ProofForgeV2.Source.QualifiedNameV1

namespace ProofForgeV2.Typed.ModelV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.AstDeclV1
open ProofForgeV2.Source.AstProgramItemV1
open ProofForgeV2.Source.AstSpineDeclV1
open ProofForgeV2.Source.NameComponentV1
open ProofForgeV2.Source.QualifiedNameV1

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

end DeclTableV1

/-- Typed declaration skeletons directly over ProgramV1, one table per kind. -/
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
deriving Repr

/-- Result of name resolution over a validated ProgramV1 source unit. -/
structure NameResolutionResultV1 where
  tables : TypedDeclTablesV1
  diagnostics : Array DiagnosticV1
  ok : Bool
deriving Repr

/-- Empty diagnostics origin: NameResolutionV1 does not own source spans. -/
def emptyOrigins : Array SourceOrigin := #[]

def unknownNameDiagnostic (name : SourceNameComponentV1) (expected : String) : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"unknown name '{name.raw}' (expected {expected})",
    origins := emptyOrigins }

def wrongCategoryDiagnostic (name : SourceNameComponentV1) (actual : DeclKindV1)
    (expected : String) : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"name '{name.raw}' resolved to {actual} but expected {expected}",
    origins := emptyOrigins }

def ambiguousNameDiagnostic (name : SourceNameComponentV1) (expected : String) : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"ambiguous name '{name.raw}' (expected {expected})",
    origins := emptyOrigins }

def duplicateDeclarationDiagnostic (name : SourceNameComponentV1)
    (kind : DeclKindV1) : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"duplicate {kind} declaration '{name.raw}'",
    origins := emptyOrigins }

def sourceQualifiedNameV1ToString (name : SourceQualifiedNameV1) : String :=
  String.intercalate "." ((NonEmptyArray.toArray name.components).map (·.raw) |>.toList)

def unknownQualifiedNameDiagnostic (name : SourceQualifiedNameV1) (expected : String) :
    DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"unknown name '{sourceQualifiedNameV1ToString name}' (expected {expected})",
    origins := emptyOrigins }

def localAsFunctionDiagnostic (name : SourceNameComponentV1) (kind : String) : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"name '{name.raw}' is bound as a {kind} but used as a function",
    origins := emptyOrigins }

def duplicateInitDiagnostic : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := "duplicate init declaration",
    origins := emptyOrigins }

def duplicateExtensionReqDiagnostic (name : SourceQualifiedNameV1) : DiagnosticV1 :=
  { code := .sourceInvalid,
    message := s!"duplicate extension requirement '{sourceQualifiedNameV1ToString name}'",
    origins := emptyOrigins }

end ProofForgeV2.Typed.ModelV1
