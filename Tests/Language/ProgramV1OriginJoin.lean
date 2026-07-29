/-
  Source-owned exact NodeId × span join (B5).

  Sole production authority for production ProgramV1 NodeIds joined to the same
  immutable parser-snapshot span table is ProofForgeV2.Source.OriginJoinV1.
  This suite is Source-only: no Semantic imports.
-/
import Lean
import Tests.Language.ParserSession
import ProofForgeV2.Core.Common
import ProofForgeV2.Source.NodeAssignmentV1
import ProofForgeV2.Source.NodeTraversalV1
import ProofForgeV2.Source.OriginJoinV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1

namespace Tests.Language.ProgramV1OriginJoin

open Lean
open ProofForgeV2
open ProofForgeV2.Core.Common
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

private def compareNodeIdBytes (left right : ByteArray) : Ordering :=
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

/-- Test-only reconstruction of the retired delimiter key, used to exhibit the
    alias that production length framing must distinguish. -/
private def legacyDelimiterPathKey
    (path : NormalizedSyntacticPathV1) : String :=
  Id.run do
    let mut parts : Array String := Array.mkEmpty path.size
    for seg in path do
      parts := parts.push
        s!"{seg.parentTag}\x1f{seg.fieldTag}\x1f{seg.index.toNat}"
    pure (String.intercalate "\x1e" parts.toList)

private def counterSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program OriginJoinCounter where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry increment(delta : UInt64) : UInt64 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private def testSourcePath : String := "tests/origin-join-counter.pf"

private unsafe def selectWithSpans (session : Language.Loader.ParserSession)
    (source : String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans source testSourcePath
      "Tests.OriginJoin" none with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def parsePath : IO ProjectRelativePath := do
  match parseProjectRelativePath testSourcePath with
  | .ok p => pure p
  | .error e => throw <| IO.userError s!"path: {e}"

/-- B5: Source OriginJoin exact join ownership, path-key, determinism, fail-closed. -/
unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let (validated, spans) ← selectWithSpans session counterSource
  let path ← parsePath
  let hash ← liftResult "sourceHashV1" (sourceHashV1 validated)
  let table ← liftResult "assignNodeIdsV1"
    (assignNodeIdsV1 validated.moduleName validated.programIdentity validated.program)
  let assignments := nodeAssignmentsPreorderV1 table
  expect (!assignments.isEmpty) "origin-join: assignment table nonempty"
  expect (spans.size == assignments.size)
    s!"origin-join: span/assignment count {spans.size}/{assignments.size}"

  -- Positive join.
  let inv1 ← match joinOriginsV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"origin-join: join failed: {repr e}"
  let inv2 ← match joinOriginsV1 validated path spans with
    | .ok inv => pure inv
    | .error e => throw <| IO.userError s!"origin-join: re-join failed: {repr e}"

  -- sourceHash identity.
  expect (originInventorySourceHashV1 inv1 == hash)
    "origin-join: inventory sourceHash == sourceHashV1"
  expect (originInventorySourceHashV1 inv2 == hash)
    "origin-join: re-join sourceHash stable"

  -- NodeId-ordered unique ascending projection; count matches preorder.
  let origins1 := originInventoryOriginsV1 inv1
  let origins2 := originInventoryOriginsV1 inv2
  expect (origins1.size == assignments.size)
    s!"origin-join: origins count {origins1.size} vs assignments {assignments.size}"
  expect (origins1 == origins2) "origin-join: determinism (NodeId-ordered origins)"
  for i in [1:origins1.size] do
    match origins1[i - 1]?, origins1[i]? with
    | some prev, some cur =>
        match compareNodeIdBytes prev.nodeId.bytes cur.nodeId.bytes with
        | .lt => pure ()
        | .eq => throw <| IO.userError "origin-join: duplicate NodeId in projection"
        | .gt => throw <| IO.userError "origin-join: origins not ascending by NodeId"
    | _, _ => pure ()

  -- Exact span byte join: index production spans by length-framed path key,
  -- then for every NodeId assignment assert lookup origin binds that path's
  -- startByte/endByte and the assignment's nodeId (not merely path/NodeId
  -- self-consistency of the inventory projection).
  let mut spanByPath : Std.HashMap String SourceByteSpanV1 :=
    Std.HashMap.emptyWithCapacity spans.size
  for (p, sp) in spans do
    let key := pathLookupKeyV1 p
    expect (!spanByPath.contains key)
      s!"origin-join: fixture spans already have duplicate key={key}"
    spanByPath := spanByPath.insert key sp
  let mut nodeById : Std.HashMap ByteArray NodeIdAssignmentV1 :=
    Std.HashMap.emptyWithCapacity assignments.size
  for a in assignments do
    nodeById := nodeById.insert a.nodeId.bytes a
  for a in assignments do
    let key := pathLookupKeyV1 a.path
    let some span := spanByPath.get? key |
      throw <| IO.userError
        s!"origin-join: assignment path missing from span table key={key}"
    match originInventoryLookupPathV1 inv1 a.path with
    | none =>
        throw <| IO.userError
          s!"origin-join: missing path lookup key={key}"
    | some looked =>
        expect (looked.sourcePath == path)
          "origin-join: lookup origin sourcePath exact"
        expect (looked.nodeId == a.nodeId)
          "origin-join: lookup origin nodeId == assignment nodeId"
        expect (looked.startByte == span.startByte)
          s!"origin-join: lookup startByte {looked.startByte} != span {span.startByte}"
        expect (looked.endByte == span.endByte)
          s!"origin-join: lookup endByte {looked.endByte} != span {span.endByte}"
        match validateSourceOrigin looked with
        | .ok () => pure ()
        | .error e =>
            throw <| IO.userError s!"origin-join: invalid origin in inventory: {e}"
  -- NodeId-ordered projection carries only assignment NodeIds with exact spans.
  for o in origins1 do
    expect (o.sourcePath == path) "origin-join: origin sourcePath exact"
    let some a := nodeById.get? o.nodeId.bytes |
      throw <| IO.userError "origin-join: foreign NodeId in inventory"
    let some span := spanByPath.get? (pathLookupKeyV1 a.path) |
      throw <| IO.userError "origin-join: origin path missing from span table"
    expect (o.nodeId == a.nodeId)
      "origin-join: projection origin nodeId == assignment"
    expect (o.startByte == span.startByte)
      s!"origin-join: projection startByte {o.startByte} != span {span.startByte}"
    expect (o.endByte == span.endByte)
      s!"origin-join: projection endByte {o.endByte} != span {span.endByte}"
    match originInventoryLookupPathV1 inv1 a.path with
    | none =>
        throw <| IO.userError
          s!"origin-join: missing path lookup for projection key={pathLookupKeyV1 a.path}"
    | some looked =>
        expect (looked == o)
          "origin-join: path lookup returns NodeId-matched origin"

  -- Length-framed keys are collision-free vs legacy delimiter aliases.
  let aliasA : NormalizedSyntacticPathV1 := #[{
    parentTag := "X", fieldTag := "Y\x1fZ", index := 0 }]
  let aliasB : NormalizedSyntacticPathV1 := #[{
    parentTag := "X\x1fY", fieldTag := "Z", index := 0 }]
  expect (legacyDelimiterPathKey aliasA == legacyDelimiterPathKey aliasB)
    "origin-join: legacy delimiter keys collide for alias pair"
  expect (pathLookupKeyV1 aliasA != pathLookupKeyV1 aliasB)
    "origin-join: length-framed keys distinguish delimiter alias pair"

  -- Invalid project-relative path → identity fail closed.
  let badPath : ProjectRelativePath := { value := "/abs/not-relative.pf" }
  expect (match joinOriginsV1 validated badPath spans with
    | .error (.identity detail) => detail.startsWith "sourcePath:"
    | _ => false)
    "origin-join: absolute path → identity sourcePath error"

  -- Duplicate span path.
  let some (p0, sp0) := spans[0]? |
    throw <| IO.userError "origin-join: spans empty"
  let dupSpans := spans.push (p0, sp0)
  expect (match joinOriginsV1 validated path dupSpans with
    | .error (.inventory detail) => detail.startsWith "duplicate span path"
    | _ => false)
    "origin-join: duplicate span path rejected"

  -- Extra distinct span path absent from assignment table.
  let extraPath := p0.push {
    parentTag := "Foreign"
    fieldTag := "extra"
    index := UInt32.ofNat 0
  }
  let extraSpans := spans.push (extraPath, sp0)
  expect (match joinOriginsV1 validated path extraSpans with
    | .error (.inventory detail) => detail.startsWith "extra span path"
    | _ => false)
    "origin-join: extra span path rejected"

  -- Missing span: drop last entry.
  if spans.size > 0 then
    let missingSpans := spans.pop
    expect (match joinOriginsV1 validated path missingSpans with
      | .error (.inventory _) => true | _ => false)
      "origin-join: missing span path rejected"

  -- Count mismatch via swapped-in alias path (same size, wrong coverage).
  let mut replacedSpans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1) := #[]
  let mut replaced := false
  for (p, sp) in spans do
    if !replaced && p == p0 then
      replacedSpans := replacedSpans.push (aliasA, sp)
      replaced := true
    else
      replacedSpans := replacedSpans.push (p, sp)
  expect replaced "origin-join: replaced first span path with delimiter alias"
  expect (match joinOriginsV1 validated path replacedSpans with
    | .error (.inventory detail) =>
        detail.startsWith "missing span" || detail.startsWith "extra span path"
    | _ => false)
    "origin-join: delimiter-alias path swap → missing/extra detection"

  -- Invalid origin: inverted span bounds (start > end).
  let mut invertedSpans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1) := #[]
  let mut inverted := false
  for (p, sp) in spans do
    if !inverted && sp.startByte < sp.endByte then
      invertedSpans := invertedSpans.push (p, {
        startByte := sp.endByte
        endByte := sp.startByte
      })
      inverted := true
    else
      invertedSpans := invertedSpans.push (p, sp)
  expect inverted "origin-join: found invertible span for invalid-origin case"
  expect (match joinOriginsV1 validated path invertedSpans with
    | .error (.inventory detail) => detail.startsWith "invalid origin:"
    | _ => false)
    "origin-join: inverted span → invalid origin rejected"

  -- Unknown path lookup returns none (does not invent origins).
  expect (originInventoryLookupPathV1 inv1 aliasA).isNone
    "origin-join: foreign path lookup is none"

  IO.println "Tests.Language.ProgramV1OriginJoin: ok"

end Tests.Language.ProgramV1OriginJoin
