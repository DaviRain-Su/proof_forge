import Tests.Language.ParserSession
import ProofForgeV2.Language.Loader
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Core.Common

namespace Tests.Language.ProgramV1Diagnostics

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Source.SpanV1

private def fileName : String := "diagnostic.lean"

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def containsSubstr (s sub : String) : Bool :=
  let rec loop (cs : List Char) : Bool :=
    match cs with
    | [] => sub.isEmpty
    | _ :: rest =>
      if sub.toList.isPrefixOf cs then true else loop rest
  loop s.toList

private partial def byteIndexOfSubstr (s sub : String) (skip : Nat) : Option Nat :=
  let bytes := s.toUTF8
  let subBytes := sub.toUTF8
  let rec loop (i : Nat) : Option Nat :=
    if i + subBytes.size > bytes.size then none
    else if bytes.extract i (i + subBytes.size) == subBytes then some i
    else loop (i + 1)
  loop skip

private def parserBoundarySource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program X where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return (\n"

private def duplicateSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Dup where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 0\n" ++
  "program Dup where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 1\n"

private def mkOversizedSource : String :=
  "import ProofForgeV2\n" ++ String.ofList (List.replicate (16 * 1024 * 1024 + 1) ' ')

private def decoderInternalSource : String :=
  "import ProofForgeV2\n" ++
  "run_cmd IO.println \"forbidden\"\n"

private def validSingleSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Counter where\n" ++
  "  state value : UInt64\n" ++
  "  view get() : UInt64 do\n" ++
  "    return value\n"

private def multipleProgramsSource : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program A where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 0\n" ++
  "program B where\n" ++
  "  view get() : UInt64 do\n" ++
  "    return 1\n"

private unsafe def runResourceBoundTest : IO DiagnosticV1 := do
  let oversizedSource := mkOversizedSource
  let session ← Tests.Language.ParserSession.shared
  let legacy ← session.selectProgramV1 oversizedSource fileName "Root" none
  let (legacyMessage, legacyCode) ← match legacy with
    | .error e => pure (e.message, e.code)
    | .ok _ => throw <| IO.userError "oversized source unexpectedly passed legacy loader"
  match ← session.selectProgramV1WithDiagnostics oversizedSource fileName "Root" none with
  | .error diagnostics =>
      expect (diagnostics.size == 1) "resource-bound error must return exactly one diagnostic"
      let diag := diagnostics[0]!
      expect (diag.code.wire == "PF-SRC-INVALID")
        "oversized source diagnostic code must stay PF-SRC-INVALID per SPEC-DIAG-001"
      expect (diag.message == "source exceeds the 16 MiB limit")
        "source-size diagnostic message mismatch"
      expect (diag.primary == none)
        "source-size diagnostic must carry no primary origin"
      expect (diag.related == #[])
        "source-size diagnostic must carry empty related"
      expect (legacyCode == "PF-SRC-INVALID")
        "legacy loader must preserve PF-SRC-INVALID for source-size over-limit"
      expect (legacyMessage == diag.message)
        "source-size diagnostic message must match legacy message body"
      pure diag
  | .ok _ =>
      throw <| IO.userError "oversized source unexpectedly passed diagnostics loader"

private unsafe def runParserBoundaryTest : IO DiagnosticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let legacy ← session.selectProgramV1 parserBoundarySource fileName "Root" none
  let legacyRender ← match legacy with
    | .error e => pure e.render
    | .ok _ => throw <| IO.userError "parser-boundary source unexpectedly passed legacy loader"
  match ← session.selectProgramV1WithDiagnostics parserBoundarySource fileName "Root" none with
  | .error diagnostics =>
      expect (diagnostics.size == 1) "parser-boundary error must return exactly one diagnostic"
      let diag := diagnostics[0]!
      expect (diag.code.wire == "PF-SRC-INVALID")
        "parser-boundary diagnostic code must be PF-SRC-INVALID"
      expect (diag.message == "Lean parser rejected source: failed to parse file")
        "parser-boundary diagnostic message mismatch"
      expect (diag.renderHuman == legacyRender)
        "parser-boundary human rendering must match legacy CompileError.render"
      match diag.primary with
      | none => throw <| IO.userError "parser-boundary diagnostic must carry primary origin"
      | some origin =>
          expect (origin.sourcePath.value == fileName)
            "parser-boundary origin sourcePath must be the caller-provided label"
          expect (origin.nodeId.isNone)
            "parser-boundary origin nodeId must be none (B7a pre-node; no zero sentinel)"
          expect (origin.nodeId == none)
            "parser-boundary origin nodeId == none"
          let sourceLen := parserBoundarySource.toUTF8.size
          expect (origin.startByte ≤ origin.endByte)
            "parser-boundary origin span must be non-inverted"
          expect (origin.endByte.toNat ≤ sourceLen)
            "parser-boundary origin span must lie within the source snapshot"
      expect (diag.related == #[])
        "parser-boundary related must be empty"
      pure diag
  | .ok _ =>
      throw <| IO.userError "parser-boundary source unexpectedly passed diagnostics loader"

private unsafe def runDuplicateTest : IO DiagnosticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let legacy ← session.selectProgramV1 duplicateSource fileName "Root" none
  let legacyRender ← match legacy with
    | .error e => pure e.render
    | .ok _ => throw <| IO.userError "duplicate source unexpectedly passed legacy loader"
  let secondProgramStart ←
    match byteIndexOfSubstr duplicateSource "program" 0 with
    | some first =>
      match byteIndexOfSubstr duplicateSource "program" (first + 1) with
      | some second => pure second
      | none => throw <| IO.userError "could not locate second program keyword"
    | none => throw <| IO.userError "could not locate first program keyword"
  match ← session.selectProgramV1WithDiagnostics duplicateSource fileName "Root" none with
  | .error diagnostics =>
      expect (diagnostics.size == 1) "duplicate-program error must return exactly one diagnostic"
      let diag := diagnostics[0]!
      expect (diag.code.wire == "PF-SRC-INVALID")
        "duplicate-program diagnostic code must be PF-SRC-INVALID"
      expect (diag.message == "duplicate program 'Root.Dup'")
        "duplicate-program diagnostic message mismatch"
      expect (diag.renderHuman == legacyRender)
        "duplicate-program human rendering must match legacy CompileError.render"
      match diag.primary with
      | none => throw <| IO.userError "duplicate-program diagnostic must carry primary origin"
      | some origin =>
          expect (origin.sourcePath.value == fileName)
            "duplicate-program origin sourcePath must be the caller-provided label"
          expect (origin.nodeId.isNone)
            "duplicate-program origin nodeId must be none (B7a pre-node; no zero sentinel)"
          expect (origin.nodeId == none)
            "duplicate-program origin nodeId == none"
          let sourceLen := duplicateSource.toUTF8.size
          expect (origin.startByte.toNat ≥ secondProgramStart)
            "duplicate-program origin must start at or before the second program command"
          expect (origin.endByte.toNat ≤ sourceLen)
            "duplicate-program origin span must lie within the source snapshot"
          expect (origin.startByte < origin.endByte)
            "duplicate-program origin must be a non-empty span"
      expect (diag.related == #[])
        "duplicate-program related must be empty"
      pure diag
  | .ok _ =>
      throw <| IO.userError "duplicate source unexpectedly passed diagnostics loader"

private unsafe def runDecoderInternalTest : IO DiagnosticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let legacy ← session.selectProgramV1 decoderInternalSource fileName "Root" none
  let legacyRender ← match legacy with
    | .error e => pure e.render
    | .ok _ => throw <| IO.userError "decoder-internal source unexpectedly passed legacy loader"
  match ← session.selectProgramV1WithDiagnostics decoderInternalSource fileName "Root" none with
  | .error diagnostics =>
      expect (diagnostics.size == 1)
        "decoder-internal error must return exactly one diagnostic"
      let diag := diagnostics[0]!
      expect (diag.code.wire == "PF-SRC-INVALID")
        "decoder-internal diagnostic code must be PF-SRC-INVALID"
      expect (diag.message == "Lean command is outside the portable program DSL")
        "decoder-internal diagnostic message mismatch"
      expect (diag.renderHuman == legacyRender)
        "decoder-internal human rendering must match legacy CompileError.render"
      expect (diag.primary == none)
        "decoder-internal diagnostic must carry no primary origin"
      expect (diag.related == #[])
        "decoder-internal related must be empty"
      pure diag
  | .ok _ =>
      throw <| IO.userError "decoder-internal source unexpectedly passed diagnostics loader"

private unsafe def runMultipleProgramsSelectionTest : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let legacy ← session.selectProgramV1 multipleProgramsSource fileName "Root" none
  let legacyRender ← match legacy with
    | .error e => pure e.render
    | .ok _ => throw <| IO.userError "multiple-program source unexpectedly passed legacy loader"
  match ← session.selectProgramV1WithDiagnostics multipleProgramsSource fileName "Root" none with
  | .error diagnostics =>
      expect (diagnostics.size == 1) "multiple-program selection error must return exactly one diagnostic"
      let diag := diagnostics[0]!
      expect (diag.code.wire == "PF-SRC-INVALID")
        "multiple-program selection diagnostic code must be PF-SRC-INVALID"
      expect (diag.message == "source contains multiple programs; pass --program <qualified-name>")
        "multiple-program selection diagnostic message mismatch"
      expect (diag.renderHuman == legacyRender)
        "multiple-program selection human rendering must match legacy CompileError.render"
      expect (diag.primary == none)
        "multiple-program selection diagnostic must carry no primary origin"
  | .ok _ =>
      throw <| IO.userError "multiple-program source unexpectedly passed diagnostics loader"

private unsafe def runMissingProgramTest : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  let legacy ← session.selectProgramV1 validSingleSource fileName "Root" (some "Root.Missing")
  let legacyRender ← match legacy with
    | .error e => pure e.render
    | .ok _ => throw <| IO.userError "missing-program request unexpectedly passed legacy loader"
  match ← session.selectProgramV1WithDiagnostics validSingleSource fileName "Root" (some "Root.Missing") with
  | .error diagnostics =>
      expect (diagnostics.size == 1) "missing-program error must return exactly one diagnostic"
      let diag := diagnostics[0]!
      expect (diag.code.wire == "PF-SRC-INVALID")
        "missing-program diagnostic code must be PF-SRC-INVALID"
      expect (diag.message == "program 'Root.Missing' was not found")
        "missing-program diagnostic message mismatch"
      expect (diag.renderHuman == legacyRender)
        "missing-program human rendering must match legacy CompileError.render"
      expect (diag.primary == none)
        "missing-program diagnostic must carry no primary origin"
  | .ok _ =>
      throw <| IO.userError "missing-program request unexpectedly passed diagnostics loader"

private unsafe def runSuccessPathTest : IO Unit := do
  let session ← Tests.Language.ParserSession.shared
  match ← session.parseProgramsV1WithDiagnostics validSingleSource fileName "Root" with
  | .ok programs =>
      expect (programs.size == 1) "valid source must produce exactly one program"
      match programs[0]? with
      | some prog =>
          let identityComponents := NonEmptyArray.toArray prog.programIdentity.components
          match identityComponents with
          | #[_, c] =>
              expect (c.raw == "Counter")
                "valid program declaration name must be Counter"
          | _ => throw <| IO.userError "valid program identity must be module.name qualified"
      | none => throw <| IO.userError "valid source must produce exactly one program"
  | .error diagnostics =>
      throw <| IO.userError s!"valid source unexpectedly failed diagnostics loader: {diagnostics.map (·.message)}"

private def testCanonicalJsonRoundTrip (diag : DiagnosticV1) : IO Unit := do
  match diag.toCanonicalJson with
  | .ok rendered =>
      unless containsSubstr rendered "PF-SRC-INVALID" ||
             containsSubstr rendered "PF-BOUND-001" do
        throw <| IO.userError "canonical JSON missing wire code"
      if containsSubstr rendered "\"sourcePath\":\"/" then
        throw <| IO.userError "canonical JSON must not contain absolute host path"
      match DiagnosticV1.fromCanonicalJson rendered with
      | .ok decoded =>
          match decoded.toCanonicalJson with
          | .ok rendered2 =>
              expect (rendered == rendered2)
                "canonical JSON must re-render deterministically"
          | .error e => throw <| IO.userError s!"re-render failed: {e}"
      | .error e => throw <| IO.userError s!"decode of canonical JSON failed: {e}"
  | .error e => throw <| IO.userError s!"canonical JSON render failed: {e}"

private def testRedaction : IO Unit := do
  let badPath : ProjectRelativePath := { value := "/etc/passwd.lean" }
  let badOrigin : DiagnosticOriginV1 := {
    sourcePath := badPath,
    startByte := 0,
    endByte := 1,
    nodeId := none
  }
  let badDiag := DiagnosticV1.make .sourceInvalid "leak" (primary := some badOrigin)
  match badDiag.toCanonicalJson with
  | .ok _ => throw <| IO.userError "canonical JSON must redact absolute sourcePath"
  | .error _ => pure ()

private def testSortAndDedupe (parserBoundaryDiag duplicateDiag decoderInternalDiag : DiagnosticV1) :
    IO Unit := do
  let arr := #[parserBoundaryDiag, duplicateDiag, decoderInternalDiag, parserBoundaryDiag]
  let sorted := DiagnosticV1.sortAndDedupe arr
  expect (sorted.size == 3) "sortAndDedupe must collapse the duplicate parser-boundary diagnostic"
  let sortedAgain := DiagnosticV1.sortAndDedupe sorted
  expect (sorted == sortedAgain) "sortAndDedupe must be idempotent"
  -- Empty primary (path="", start=0) sorts before any primary-carrying diagnostic
  -- when codes and stableContext match.
  expect (sorted[0]! == decoderInternalDiag)
    "decoder-internal diagnostic must sort first (empty primary)"
  let originCarrying := #[parserBoundaryDiag, duplicateDiag]
  let ordered := Array.qsort originCarrying fun a b =>
    DiagnosticV1.compareOrderKey a b == .lt
  expect (sorted[1]! == ordered[0]!)
    "first origin-carrying diagnostic order must match order key"
  expect (sorted[2]! == ordered[1]!)
    "second origin-carrying diagnostic order must match order key"

unsafe def run : IO Unit := do
  let parserBoundaryDiag ← runParserBoundaryTest
  let duplicateDiag ← runDuplicateTest
  let decoderInternalDiag ← runDecoderInternalTest
  let resourceBoundDiag ← runResourceBoundTest
  runMultipleProgramsSelectionTest
  runMissingProgramTest
  runSuccessPathTest
  testCanonicalJsonRoundTrip parserBoundaryDiag
  testCanonicalJsonRoundTrip duplicateDiag
  testCanonicalJsonRoundTrip decoderInternalDiag
  testCanonicalJsonRoundTrip resourceBoundDiag
  testRedaction
  testSortAndDedupe parserBoundaryDiag duplicateDiag decoderInternalDiag
  IO.println "Tests.Language.ProgramV1Diagnostics: ok"

end Tests.Language.ProgramV1Diagnostics
