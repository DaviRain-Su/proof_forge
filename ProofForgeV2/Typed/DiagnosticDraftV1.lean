/-
  ProofForgeV2.Typed.DiagnosticDraftV1 — sole Typed wrapper over B6 DiagnosticV1
  plus optional B7a DiagnosticLocationDraftV1 (B7b1).

  Carries code/message/context on the DiagnosticV1 payload and optional
  path-only location drafts. Public unlocated product surfaces erase drafts
  (drop location). Located materialization goes only through
  Source.locateDiagnosticV1 in this module — no other Typed file may call it.

  APIs preserve diagnostic array order (no sort/dedupe/cap). A draft with no
  location erases/locates as the bare diagnostic (primary/related stay empty).
  All-or-nothing locateArray fails closed on the first path/origin error.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.DiagnosticLocateV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.WireV1

namespace ProofForgeV2.Typed.DiagnosticDraftV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.DiagnosticLocateV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.WireV1

/-- Typed diagnostic draft: B6 carrier (empty primary/related) + optional paths. -/
structure TypedDiagnosticDraftV1 where
  diagnostic : DiagnosticV1
  location : Option DiagnosticLocationDraftV1
  deriving Repr

instance : Inhabited TypedDiagnosticDraftV1 where
  default := {
    diagnostic := default
    location := none
  }

/-- Errors from Typed locate materialization. -/
inductive TypedDiagnosticLocateErrorV1 where
  | locate (err : DiagnosticLocateErrorV1)
  | internal (detail : String)
  deriving Repr

/-- Build a draft. Forces empty primary/related on the carrier so locate can apply. -/
def make
    (code : DiagnosticCodeV1)
    (message : String)
    (program : Option QualifiedName := none)
    (target : Option TargetId := none)
    (requirement : Option RequirementKeyV1 := none)
    (extension : Option ExtensionKeyV1 := none)
    (expected : Option PfJson := none)
    (actual : Option PfJson := none)
    (context : Option PfJson := none)
    (stableContext : Option String := none)
    (suggestion : Option String := none)
    (severity : Option DiagnosticSeverityV1 := none)
    (phase : Option DiagnosticPhaseV1 := none)
    (location : Option DiagnosticLocationDraftV1 := none) :
    TypedDiagnosticDraftV1 :=
  {
    diagnostic := DiagnosticV1.make code message
      (primary := none)
      (related := #[])
      (program := program)
      (target := target)
      (requirement := requirement)
      (extension := extension)
      (expected := expected)
      (actual := actual)
      (context := context)
      (stableContext := stableContext)
      (suggestion := suggestion)
      (severity := severity)
      (phase := phase)
    location
  }

/-- Attach or replace a location draft (primary + related paths). -/
def withLocation
    (draft : TypedDiagnosticDraftV1) (location : DiagnosticLocationDraftV1) :
    TypedDiagnosticDraftV1 :=
  { draft with location := some location }

/-- Convenience: primary path with optional related paths. -/
def withPaths
    (draft : TypedDiagnosticDraftV1)
    (primaryPath : NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1 := #[]) :
    TypedDiagnosticDraftV1 :=
  withLocation draft { primaryPath, relatedPaths }

/-- Located smart constructor. -/
def makeLocated
    (code : DiagnosticCodeV1)
    (message : String)
    (primaryPath : NormalizedSyntacticPathV1)
    (relatedPaths : Array NormalizedSyntacticPathV1 := #[])
    (program : Option QualifiedName := none)
    (target : Option TargetId := none)
    (requirement : Option RequirementKeyV1 := none)
    (extension : Option ExtensionKeyV1 := none)
    (expected : Option PfJson := none)
    (actual : Option PfJson := none)
    (context : Option PfJson := none)
    (stableContext : Option String := none)
    (suggestion : Option String := none)
    (severity : Option DiagnosticSeverityV1 := none)
    (phase : Option DiagnosticPhaseV1 := none) :
    TypedDiagnosticDraftV1 :=
  make code message
    (program := program)
    (target := target)
    (requirement := requirement)
    (extension := extension)
    (expected := expected)
    (actual := actual)
    (context := context)
    (stableContext := stableContext)
    (suggestion := suggestion)
    (severity := severity)
    (phase := phase)
    (location := some { primaryPath, relatedPaths })

/-- Deterministic internal fail-closed draft for impossible canonical child paths. -/
def pathInternalDraft (detail : String) : TypedDiagnosticDraftV1 :=
  make .internal
    s!"typed diagnostic path construction failed: {detail}"
    (stableContext := some "typed.path.internal")
    (actual := some (.string detail))

/-- Erase location; product unlocated projection. -/
def erase (draft : TypedDiagnosticDraftV1) : DiagnosticV1 :=
  draft.diagnostic

/-- Order-preserving erase of an array (no sort/dedupe/cap). -/
def eraseArray (drafts : Array TypedDiagnosticDraftV1) : Array DiagnosticV1 :=
  drafts.map erase

/-- Materialize one draft through OriginInventoryV1.
    No location → return carrier unchanged (still empty primary/related). -/
def locate
    (inv : OriginInventoryV1) (draft : TypedDiagnosticDraftV1) :
    Except TypedDiagnosticLocateErrorV1 DiagnosticV1 :=
  match draft.location with
  | none => pure draft.diagnostic
  | some loc =>
      match locateDiagnosticV1 inv draft.diagnostic loc with
      | .ok diag => pure diag
      | .error err => .error (.locate err)

/-- All-or-nothing order-preserving locate of an array. -/
def locateArray
    (inv : OriginInventoryV1) (drafts : Array TypedDiagnosticDraftV1) :
    Except TypedDiagnosticLocateErrorV1 (Array DiagnosticV1) := do
  let mut out : Array DiagnosticV1 := Array.mkEmpty drafts.size
  for draft in drafts do
    let located ← locate inv draft
    out := out.push located
  pure out

end ProofForgeV2.Typed.DiagnosticDraftV1
