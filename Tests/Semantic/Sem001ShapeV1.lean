/-
  Tests.Semantic.Sem001ShapeV1 — engineering TST-SEM-001 *shape* pin.

  Pins the accepted paragraph's isolated identity split:
    * canonical `.pfsem` bytes == `SemanticProgramV1.canonicalBytes`
    * `semanticHashV1` = SHA-256 of those bytes (after structure gate)
    * same `Source.Program`, different project-relative path → identical
      `.pfsem` / `semanticHash` / `sourceHash`; only `.pfprov` bytes and
      `semanticProvenanceDigestV1` change
    * business-semantic change → `semanticHash` changes
    * path-swapped provenance fails `validateSemanticProvenanceV1`
    * layout/span-only comment shift keeps `.pfsem` / `semanticHash` /
      `sourceHash`; only `.pfprov` and provenance digest change
    * consumers do not mix provenance fields back into `semanticHash`

  Does **not** close formal TASK-D2-06 / TST-SEM-001 / TST-PROOF-001.
  Does **not** edit docs/04-task-breakdown.md or docs/05-test-spec.md status.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Language.Loader
import ProofForgeV2.Semantic.NormalizeV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Source.SpanV1
import ProofForgeV2.Source.ValidatedSourceV1
import ProofForgeV2.Source.WireV1
import Tests.Language.ParserSession

namespace Tests.Semantic.Sem001ShapeV1

set_option maxRecDepth 4096

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1

private def expect (cond : Bool) (msg : String) : IO Unit := do
  unless cond do
    throw <| IO.userError msg

private def wrap (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program " ++ name ++ " where\n" ++ body

/-- Same ProgramV1 as `wrap`, with a leading comment that shifts every span. -/
private def wrapCommented (name body : String) : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "-- layout-only span shift\n" ++
  "program " ++ name ++ " where\n" ++ body

private def counterBody (delta : String) : String :=
  "  state count : UInt64\n" ++
  "  entry increment() : UInt64 do\n" ++
  "    count := count + " ++ delta ++ "\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

private def parsePath (label : String) : IO ProjectRelativePath := do
  match parseProjectRelativePath label with
  | .ok path => pure path
  | .error e => throw <| IO.userError s!"path {label}: {e}"

private unsafe def loadWithSpans
    (session : Language.Loader.ParserSession)
    (relPath moduleName src : String) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans src relPath moduleName none with
  | .ok pair => pure pair
  | .error e => throw <| IO.userError s!"{moduleName}: load: {e.render}"

private def hashOf (carrier : SemanticProgramV1) : IO Digest := do
  match semanticHashV1 carrier with
  | .ok h => pure h
  | .error e => throw <| IO.userError s!"semanticHash: {repr e}"

private def sourceHashOf (source : ValidatedSourceV1) : IO Digest := do
  match sourceHashV1 source with
  | .ok h => pure h
  | .error e => throw <| IO.userError s!"sourceHash: {e}"

private def pairAt
    (source : ValidatedSourceV1)
    (path : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) :
    IO (SemanticProgramV1 × SemanticProvenanceV1) := do
  match normalizeProgramWithProvenanceV1 source path spans with
  | .ok pair => pure pair
  | .error e => throw <| IO.userError s!"normalize+prov {path.value}: {repr e}"

private def provDigest
    (source : ValidatedSourceV1)
    (path : ProjectRelativePath)
    (spans : Array (NormalizedSyntacticPathV1 × SourceByteSpanV1))
    (carrier : SemanticProgramV1)
    (provenance : SemanticProvenanceV1) :
    IO Digest := do
  match semanticProvenanceDigestV1 source path spans carrier provenance with
  | .ok d => pure d
  | .error e => throw <| IO.userError s!"prov digest {path.value}: {repr e}"

/-- Path-only change keeps `.pfsem` / hashes; only `.pfprov` moves. -/
private unsafe def testPathDoesNotEnterSemanticHash
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src := wrap "Sem001Path" (counterBody "2")
  let (validated, spans) ←
    loadWithSpans session "tests/sem001-a.pf" "Sem001Path" src
  let pathA ← parsePath "tests/sem001-a.pf"
  let pathB ← parsePath "tests/sem001-b.pf"
  expect (pathA != pathB) "SEM-001 shape: paths differ"
  let (carrierA, provA) ← pairAt validated pathA spans
  let (carrierB, provB) ← pairAt validated pathB spans
  expect (carrierA.canonicalBytes == carrierB.canonicalBytes)
    "SEM-001 shape: path change keeps .pfsem bytes"
  match decodeSemanticProgramV1 carrierA.canonicalBytes with
  | .ok again =>
      expect (again.canonicalBytes == carrierA.canonicalBytes)
        "SEM-001 shape: .pfsem re-encode identity"
  | .error e =>
      throw <| IO.userError s!"SEM-001 shape: .pfsem decode: {repr e}"
  let semA ← hashOf carrierA
  let semB ← hashOf carrierB
  expect (semA == semB) "SEM-001 shape: path change keeps semanticHash"
  expect (semA == sha256Bytes carrierA.canonicalBytes)
    "SEM-001 shape: semanticHash is SHA-256 of .pfsem"
  expect (provA.semanticHash == semA)
    "SEM-001 shape: provenance.semanticHash matches carrier"
  expect (provB.semanticHash == semA)
    "SEM-001 shape: path-B provenance.semanticHash still matches"
  let srcHash ← sourceHashOf validated
  expect (provA.sourceHash == srcHash)
    "SEM-001 shape: provenance.sourceHash matches source"
  expect (provB.sourceHash == srcHash)
    "SEM-001 shape: path change keeps sourceHash"
  let encA ← match encodeSemanticProvenanceV1 provA with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"prov A encode: {repr e}"
  let encB ← match encodeSemanticProvenanceV1 provB with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"prov B encode: {repr e}"
  expect (encA != encB) "SEM-001 shape: path change changes .pfprov bytes"
  let digA ← provDigest validated pathA spans carrierA provA
  let digB ← provDigest validated pathB spans carrierB provB
  expect (digA != digB) "SEM-001 shape: path change changes provenance digest"
  expect (digA == sha256Bytes encA)
    "SEM-001 shape: provenance digest is SHA-256 of .pfprov"
  match validateSemanticProvenanceV1 validated pathB spans carrierA provA with
  | .error _ => pure ()
  | .ok () =>
      throw <| IO.userError
        "SEM-001 shape: path-swapped provenance must fail closed"

/-- Changing the increment constant changes business semanticHash. -/
private unsafe def testBusinessChangeMovesSemanticHash
    (session : Language.Loader.ParserSession) : IO Unit := do
  let src2 := wrap "Sem001Biz" (counterBody "2")
  let src3 := wrap "Sem001Biz" (counterBody "3")
  let (v2, spans2) ←
    loadWithSpans session "tests/sem001-biz.pf" "Sem001Biz" src2
  let (v3, spans3) ←
    loadWithSpans session "tests/sem001-biz.pf" "Sem001Biz" src3
  let path ← parsePath "tests/sem001-biz.pf"
  let (c2, _) ← pairAt v2 path spans2
  let (c3, _) ← pairAt v3 path spans3
  expect (c2.canonicalBytes != c3.canonicalBytes)
    "SEM-001 shape: business change changes .pfsem"
  let h2 ← hashOf c2
  let h3 ← hashOf c3
  expect (h2 != h3) "SEM-001 shape: business change changes semanticHash"
  let s2 ← sourceHashOf v2
  let s3 ← sourceHashOf v3
  expect (s2 != s3) "SEM-001 shape: business change changes sourceHash"

/-- Layout-only leading comment shifts spans but not the ProgramV1 AST.
    `.pfsem` / `semanticHash` / `sourceHash` stay identical; `.pfprov` moves.
    Cross-applying the other snapshot's spans fails closed. -/
private unsafe def testSpanOnlyDoesNotEnterSemanticHash
    (session : Language.Loader.ParserSession) : IO Unit := do
  let body := counterBody "2"
  let src := wrap "Sem001Span" body
  let srcShifted := wrapCommented "Sem001Span" body
  expect (src != srcShifted) "SEM-001 span: raw source texts differ"
  let (v0, spans0) ←
    loadWithSpans session "tests/sem001-span.pf" "Sem001Span" src
  let (v1, spans1) ←
    loadWithSpans session "tests/sem001-span.pf" "Sem001Span" srcShifted
  expect (v0.program == v1.program)
    "SEM-001 span: comment shift keeps ProgramV1"
  expect (spans0.size == spans1.size)
    "SEM-001 span: comment shift keeps span count"
  expect (spans0 != spans1) "SEM-001 span: comment shift moves spans"
  let srcHash0 ← sourceHashOf v0
  let srcHash1 ← sourceHashOf v1
  expect (srcHash0 == srcHash1)
    "SEM-001 span: comment shift keeps sourceHash"
  let path ← parsePath "tests/sem001-span.pf"
  let (c0, p0) ← pairAt v0 path spans0
  let (c1, p1) ← pairAt v1 path spans1
  expect (c0.canonicalBytes == c1.canonicalBytes)
    "SEM-001 span: comment shift keeps .pfsem bytes"
  let h0 ← hashOf c0
  let h1 ← hashOf c1
  expect (h0 == h1) "SEM-001 span: comment shift keeps semanticHash"
  expect (p0.semanticHash == h0)
    "SEM-001 span: provenance.semanticHash matches carrier"
  expect (p1.semanticHash == h0)
    "SEM-001 span: shifted provenance.semanticHash still matches"
  expect (p0.sourceHash == srcHash0)
    "SEM-001 span: provenance.sourceHash matches source"
  expect (p1.sourceHash == srcHash0)
    "SEM-001 span: comment shift keeps provenance.sourceHash"
  let enc0 ← match encodeSemanticProvenanceV1 p0 with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"span prov 0 encode: {repr e}"
  let enc1 ← match encodeSemanticProvenanceV1 p1 with
    | .ok b => pure b
    | .error e => throw <| IO.userError s!"span prov 1 encode: {repr e}"
  expect (enc0 != enc1)
    "SEM-001 span: comment shift changes .pfprov bytes"
  let d0 ← provDigest v0 path spans0 c0 p0
  let d1 ← provDigest v1 path spans1 c1 p1
  expect (d0 != d1)
    "SEM-001 span: comment shift changes provenance digest"
  match validateSemanticProvenanceV1 v0 path spans1 c0 p0 with
  | .error _ => pure ()
  | .ok () =>
      throw <| IO.userError
        "SEM-001 span: span-swapped provenance must fail closed"

unsafe def run : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  testPathDoesNotEnterSemanticHash session
  testBusinessChangeMovesSemanticHash session
  testSpanOnlyDoesNotEnterSemanticHash session
  IO.println "Tests.Semantic.Sem001ShapeV1: ok (engineering; not formal TST-SEM-001)"

end Tests.Semantic.Sem001ShapeV1
