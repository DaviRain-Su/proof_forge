/-
  B7a: Source-owned located-diagnostic infrastructure.

  Covers additive Loader `selectProgramV1WithOrigins`, NodeTraversalV1
  `childPathV1` sole path helpers, and DiagnosticLocateV1 materializer that
  exact-resolves primary/related paths through opaque OriginInventoryV1 into
  DiagnosticOriginV1 with real NodeIds. No Typed producer rewrite (B7b).
-/
import Lean
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Source.DiagnosticLocateV1
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.ProgramV1DiagnosticLocate

open Lean
open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.DiagnosticLocateV1
open ProofForgeV2.Source.NodeAssignmentV1
open ProofForgeV2.Source.NodeTraversalV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error detail => throw <| IO.userError s!"{label}: unexpected error: {detail}"

private def counterSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program LocateCounter where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private def testSourcePath : String := "tests/locate-counter.pf"

private def moduleName : String := "Tests.Locate"

private unsafe def selectWithOrigins (session : Language.Loader.ParserSession)
    (source : String) (fileName : String := testSourcePath) :
    IO (ValidatedSourceV1 × OriginInventoryV1) := do
  match ← session.selectProgramV1WithOrigins source fileName moduleName none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def sourceToDiagOrigin (o : SourceOrigin) : DiagnosticOriginV1 := {
  sourcePath := o.sourcePath
  startByte := o.startByte
  endByte := o.endByte
  nodeId := some o.nodeId
}

/-- B7a: WithOrigins parity, locate materializer, childPath helpers, fail-closed. -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (validated, inv) ← selectWithOrigins session counterSource
  let hash ← liftResult "sourceHashV1" (sourceHashV1 validated)
  expect (originInventorySourceHashV1 inv == hash)
    "locate: WithOrigins inventory sourceHash == sourceHashV1"

  -- Additive WithOrigins vs WithSpans: same validated unit + joinable inventory.
  match ← session.selectProgramV1WithSpans counterSource testSourcePath
      moduleName none with
  | .error e => throw <| IO.userError s!"locate: WithSpans failed: {e.render}"
  | .ok (validatedSpans, spans) =>
      expect (validatedSpans.programIdentity == validated.programIdentity)
        "locate: WithOrigins identity matches WithSpans"
      expect ((← liftResult "sourceHash spans" (sourceHashV1 validatedSpans)) == hash)
        "locate: WithOrigins sourceHash matches WithSpans"
      match parseProjectRelativePath testSourcePath with
      | .error e => throw <| IO.userError s!"locate: path: {e}"
      | .ok path =>
          match joinOriginsV1 validatedSpans path spans with
          | .error e => throw <| IO.userError s!"locate: re-join failed: {repr e}"
          | .ok inv2 =>
              expect (originInventoryOriginsV1 inv == originInventoryOriginsV1 inv2)
                "locate: WithOrigins inventory == joinOrigins(WithSpans)"
              expect (originInventorySourceHashV1 inv2 == hash)
                "locate: re-join sourceHash stable"

  -- Path lookup parity for every preorder assignment.
  let table ← liftResult "assignNodeIdsV1"
    (assignNodeIdsV1 validated.moduleName validated.programIdentity validated.program)
  let assignments := nodeAssignmentsPreorderV1 table
  expect (!assignments.isEmpty) "locate: assignment table nonempty"
  for a in assignments do
    match originInventoryLookupPathV1 inv a.path with
    | none =>
        throw <| IO.userError
          s!"locate: missing path lookup tag={a.constructorTag}"
    | some looked =>
        expect (looked.nodeId == a.nodeId)
          "locate: lookup nodeId == assignment"
        expect (looked.startByte ≤ looked.endByte)
          "locate: lookup span non-inverted"

  -- childPathV1 sole helper smoke (bounded canonical edges).
  let rootPath : NormalizedSyntacticPathV1 := #[]
  let item0Path ← liftResult "childPath item0"
    (childPathV1 rootPath "Program" "items" 0)
  let item0Direct ← liftResult "directChildPath item0"
    (directChildPathV1 rootPath "Program" "items")
  let item0Index ← liftResult "indexChildPath item0"
    (indexChildPathV1 rootPath "Program" "items" 0)
  expect (item0Path == item0Index)
    "locate: childPathV1 == indexChildPathV1 for same args"
  expect (item0Direct == item0Path)
    "locate: directChildPathV1 is index-0 form of childPathV1"
  let some stateAssign := assignments.find? (·.constructorTag == "StateDecl") |
    throw <| IO.userError "locate: fixture missing StateDecl"
  expect (stateAssign.path == item0Path)
    "locate: items[0] path is StateDecl for Counter fixture"
  let item1Path ← liftResult "childPath item1"
    (childPathV1 rootPath "Program" "items" 1)
  let some initAssign := assignments.find? (·.constructorTag == "InitDecl") |
    throw <| IO.userError "locate: fixture missing InitDecl"
  expect (initAssign.path == item1Path)
    "locate: items[1] path is InitDecl for Counter fixture"

  -- Materialize primary (program root) + related (item0, item1, duplicate item0).
  let some rootOrigin := originInventoryLookupPathV1 inv rootPath |
    throw <| IO.userError "locate: missing root origin"
  let some item0Origin := originInventoryLookupPathV1 inv item0Path |
    throw <| IO.userError "locate: missing item0 origin"
  let some item1Origin := originInventoryLookupPathV1 inv item1Path |
    throw <| IO.userError "locate: missing item1 origin"

  -- Note: do not pass named arg `program :=` here — Loader→Syntax makes `program`
  -- a command keyword in this module. Program field stays none; preservation still
  -- covers expected/actual/stableContext/suggestion and the none program slot.
  let baseDiag := DiagnosticV1.make .type001 "locate type mismatch"
    (expected := some (.string "UInt64"))
    (actual := some (.string "Bool"))
    (stableContext := some "locate-stable")
    (suggestion := some "fix the type")
  expect (baseDiag.primary == none) "locate: base primary empty"
  expect (baseDiag.related == #[]) "locate: base related empty"

  let draft : DiagnosticLocationDraftV1 := {
    primaryPath := rootPath
    relatedPaths := #[item0Path, item1Path, item0Path]
  }
  let located ← match locateDiagnosticV1 inv baseDiag draft with
    | .ok d => pure d
    | .error e => throw <| IO.userError s!"locate: materialize failed: {repr e}"

  -- Primary exact NodeId/span parity with inventory.
  match located.primary with
  | none => throw <| IO.userError "locate: primary must be some after materialize"
  | some primary =>
      expect (primary == sourceToDiagOrigin rootOrigin)
        "locate: primary origin exact (path/span/NodeId)"
      expect (primary.nodeId == some rootOrigin.nodeId)
        "locate: primary nodeId is real some NodeId"
      expect (primary.nodeId.isSome)
        "locate: primary nodeId.isSome"

  -- Related sort/dedupe: duplicate item0 collapsed; full origin order.
  let expectedRelated :=
    DiagnosticV1.normalizeRelated
      #[sourceToDiagOrigin item0Origin, sourceToDiagOrigin item1Origin]
  expect (located.related == expectedRelated)
    "locate: related sorted+deduped to inventory origins"
  expect (located.related.size == 2)
    "locate: related size 2 after dedupe of duplicate item0"
  for o in located.related do
    expect (o.nodeId.isSome) "locate: each related nodeId.isSome"

  -- Non-location fields preserved byte-for-byte.
  expect (located.schemaVersion == baseDiag.schemaVersion) "locate: schemaVersion"
  expect (located.code == baseDiag.code) "locate: code"
  expect (located.severity == baseDiag.severity) "locate: severity"
  expect (located.phase == baseDiag.phase) "locate: phase"
  expect (located.message == baseDiag.message) "locate: message"
  expect (located.program == baseDiag.program) "locate: program"
  expect (located.target == baseDiag.target) "locate: target"
  expect (located.requirement == baseDiag.requirement) "locate: requirement"
  expect (located.extension == baseDiag.extension) "locate: extension"
  expect (located.expected == baseDiag.expected) "locate: expected"
  expect (located.actual == baseDiag.actual) "locate: actual"
  expect (located.context == baseDiag.context) "locate: context"
  expect (located.stableContext == baseDiag.stableContext) "locate: stableContext"
  expect (located.suggestion == baseDiag.suggestion) "locate: suggestion"

  -- All-or-nothing: missing path fails closed with no partial diagnostic.
  let foreignPath : NormalizedSyntacticPathV1 := #[{
    parentTag := "Program"
    fieldTag := "items"
    index := 99999
  }]
  let missingDraft : DiagnosticLocationDraftV1 := {
    primaryPath := rootPath
    relatedPaths := #[item0Path, foreignPath]
  }
  match locateDiagnosticV1 inv baseDiag missingDraft with
  | .ok _ => throw <| IO.userError "locate: missing related path must fail closed"
  | .error (.missingPath _) => pure ()
  | .error e =>
      throw <| IO.userError s!"locate: expected missingPath, got {repr e}"

  let missingPrimaryDraft : DiagnosticLocationDraftV1 := {
    primaryPath := foreignPath
    relatedPaths := #[]
  }
  match locateDiagnosticV1 inv baseDiag missingPrimaryDraft with
  | .ok _ => throw <| IO.userError "locate: missing primary path must fail closed"
  | .error (.missingPath _) => pure ()
  | .error e =>
      throw <| IO.userError s!"locate: expected missingPath primary, got {repr e}"

  -- Empty-origin gate: refuse to overwrite/merge when primary/related already set.
  let alreadyLocated := located
  match locateDiagnosticV1 inv alreadyLocated draft with
  | .ok _ => throw <| IO.userError "locate: nonempty origin input must fail closed"
  | .error (.nonemptyOrigin _) => pure ()
  | .error e =>
      throw <| IO.userError s!"locate: expected nonemptyOrigin, got {repr e}"

  -- Related-only nonempty gate: primary=none with related already set must fail.
  -- Avoid named field `program` (Loader→Syntax makes it a command keyword here).
  let relatedOnly : DiagnosticV1 :=
    { baseDiag with
      primary := none
      related := #[sourceToDiagOrigin item0Origin] }
  match locateDiagnosticV1 inv relatedOnly draft with
  | .ok _ =>
      throw <| IO.userError
        "locate: primary=none + nonempty related must fail closed"
  | .error (.nonemptyOrigin detail) =>
      expect (detail == "diagnostic related origins are already set")
        s!"locate: related-only nonemptyOrigin message, got {detail}"
  | .error e =>
      throw <| IO.userError
        s!"locate: expected nonemptyOrigin for related-only, got {repr e}"

  -- Invalid caller path → source-invalid (PF-SRC-INVALID) CompileError.
  match ← session.selectProgramV1WithOrigins counterSource "/abs/not-relative.pf"
      moduleName none with
  | .ok _ => throw <| IO.userError "locate: absolute path must fail closed"
  | .error err =>
      expect (err.code == "PF-SRC-INVALID")
        "locate: invalid caller path → PF-SRC-INVALID"
      expect (err.message.length > 0)
        "locate: invalid path message nonempty"

  -- childPathV1 depth bound: 256 edges rejected.
  let mut deep : NormalizedSyntacticPathV1 := #[]
  for _ in [0:255] do
    deep ← liftResult "deep push"
      (childPathV1 deep "Type.Option" "element" 0)
  expect (deep.size == 255) "locate: 255 edges ok"
  match childPathV1 deep "Type.Option" "element" 0 with
  | .ok _ => throw <| IO.userError "locate: 256th edge must fail nesting bound"
  | .error detail =>
      expect (detail == "source node traversal exceeds the nesting bound")
        s!"locate: depth error message, got {detail}"

  -- childPathV1 index bound: index ≥ UInt32.size rejected (node limit).
  match childPathV1 rootPath "Program" "items" UInt32.size with
  | .ok _ => throw <| IO.userError "locate: index == UInt32.size must fail node limit"
  | .error detail =>
      expect (detail == "source node traversal exceeds the node limit")
        s!"locate: node-limit error message, got {detail}"
  match childPathV1 rootPath "Program" "items" (UInt32.size + 1) with
  | .ok _ => throw <| IO.userError "locate: index > UInt32.size must fail node limit"
  | .error detail =>
      expect (detail == "source node traversal exceeds the node limit")
        s!"locate: node-limit error message (+1), got {detail}"

  IO.println "Tests.Language.ProgramV1DiagnosticLocate: ok"

end Tests.Language.ProgramV1DiagnosticLocate
