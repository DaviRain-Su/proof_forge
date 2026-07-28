/-
  ProofForgeV2.Source.DiagnosticLocateV1 — Source-owned path-draft materializer
  for B7a located diagnostics.

  Applies a location-only draft `{primaryPath, relatedPaths}` to an existing
  B6 `DiagnosticV1` whose primary/related are empty, exact-resolving every path
  through opaque `OriginInventoryV1` into `DiagnosticOriginV1` with
  `nodeId = some real NodeId`. Fail closed on nonempty input origins or any
  missing/foreign path (all-or-nothing; no partial diagnostic). Related
  duplicates are collapsed via `DiagnosticV1.normalizeRelated`. Non-location
  fields are preserved byte-for-byte.

  Imports Core.Common + Core.DiagnosticV1 + Source OriginJoinV1/WireV1 only —
  no Semantic, no NodeTraversal (path helpers stay in NodeTraversalV1 for B7b
  callers; drafts carry already-built paths).
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.WireV1

namespace ProofForgeV2.Source.DiagnosticLocateV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.WireV1

/-- Location-only draft applied to an existing empty-origin DiagnosticV1.
    Does not carry code/message/context (those stay on the B6 carrier). -/
structure DiagnosticLocationDraftV1 where
  primaryPath : NormalizedSyntacticPathV1
  relatedPaths : Array NormalizedSyntacticPathV1
  deriving Repr

inductive DiagnosticLocateErrorV1 where
  | nonemptyOrigin (detail : String)
  | missingPath (detail : String)
  | emptyInventory (detail : String)
  deriving Repr

private def failNonempty (detail : String) : Except DiagnosticLocateErrorV1 α :=
  .error (.nonemptyOrigin detail)

private def failMissing (detail : String) : Except DiagnosticLocateErrorV1 α :=
  .error (.missingPath detail)

private def failEmpty (detail : String) : Except DiagnosticLocateErrorV1 α :=
  .error (.emptyInventory detail)

/-- Convert a production SourceOrigin into a diagnostic origin with real NodeId. -/
def sourceOriginToDiagnosticOriginV1 (origin : SourceOrigin) : DiagnosticOriginV1 := {
  sourcePath := origin.sourcePath
  startByte := origin.startByte
  endByte := origin.endByte
  nodeId := some origin.nodeId
}

private def resolvePath
    (inv : OriginInventoryV1) (path : NormalizedSyntacticPathV1) (role : String) :
    Except DiagnosticLocateErrorV1 DiagnosticOriginV1 :=
  match originInventoryLookupPathV1 inv path with
  | none =>
      failMissing s!"{role}: no origin for path key={pathLookupKeyV1 path}"
  | some origin => pure (sourceOriginToDiagnosticOriginV1 origin)

/-- Sole located materializer: require empty primary/related on `diag`, resolve
    every draft path against `inv` before returning, set
    `nodeId = some real NodeId`, normalize related, preserve all non-location
    fields. Fails closed on empty inventory, nonempty input origins, or any
    missing/foreign path (no silent overwrite/merge, no partial diagnostic). -/
def locateDiagnosticV1
    (inv : OriginInventoryV1)
    (diag : DiagnosticV1)
    (draft : DiagnosticLocationDraftV1) :
    Except DiagnosticLocateErrorV1 DiagnosticV1 := do
  if (originInventoryOriginsV1 inv).isEmpty then
    return ← failEmpty "origin inventory is empty"
  match diag.primary with
  | some _ => return ← failNonempty "diagnostic primary origin is already set"
  | none => pure ()
  unless diag.related.isEmpty do
    return ← failNonempty "diagnostic related origins are already set"
  -- Resolve all paths first (all-or-nothing).
  let primary ← resolvePath inv draft.primaryPath "primary"
  let mut relatedRaw : Array DiagnosticOriginV1 :=
    Array.mkEmpty draft.relatedPaths.size
  for (path, i) in draft.relatedPaths.zipIdx do
    let origin ← resolvePath inv path s!"related[{i}]"
    relatedRaw := relatedRaw.push origin
  let related := DiagnosticV1.normalizeRelated relatedRaw
  -- Preserve every non-location field; only primary/related change.
  pure {
    schemaVersion := diag.schemaVersion
    code := diag.code
    severity := diag.severity
    phase := diag.phase
    message := diag.message
    primary := some primary
    related := related
    program := diag.program
    target := diag.target
    requirement := diag.requirement
    extension := diag.extension
    expected := diag.expected
    actual := diag.actual
    context := diag.context
    stableContext := diag.stableContext
    suggestion := diag.suggestion
  }

end ProofForgeV2.Source.DiagnosticLocateV1
