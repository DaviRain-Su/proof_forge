/-
  Tests.Compiler.ProofSubjectFilesV1 — proof-specific native stable-read pins.

  Exercises the compiler-owned fixed pair reader. This is engineering coverage,
  not a contained compiler-core worker or formal TST-PROOF-001 evidence.
-/
import Tests.Language.ParserSession
import ProofForgeV2.Compiler.ProofSubjectFilesV1
import ProofForgeV2.Semantic.NormalizeV1

namespace Tests.Compiler.ProofSubjectFilesV1

open ProofForgeV2
open ProofForgeV2.Compiler.ProofSubjectFilesV1
open ProofForgeV2.Core.Common
open ProofForgeV2.Semantic.NormalizeV1
open ProofForgeV2.Semantic.ProofSubjectV1
open ProofForgeV2.Semantic.WireV1
open ProofForgeV2.Source.SpanV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Source.WireV1
open System

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def runTool (cmd : String) (args : Array String) : IO Unit := do
  let output ← IO.Process.output {
    cmd
    args
    stdin := .null
    stdout := .piped
    stderr := .piped
    inheritEnv := false
  }
  unless output.exitCode == 0 do
    throw <| IO.userError
      s!"fixture tool failed: {cmd}, exit={output.exitCode}, stderr={output.stderr}"

private def sourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program SubjectFiles where\n" ++
  "  entry truth() : UInt64 do\n" ++
  "    return 11\n"

private def sourcePathString : String := "tests/proof-subject-files-source.pf"

private unsafe def loadSourceWithSpans
    (session : Language.Loader.ParserSession) :
    IO (ValidatedSourceV1 × Array (NormalizedSyntacticPathV1 × SourceByteSpanV1)) := do
  match ← session.selectProgramV1WithSpans
      sourceText sourcePathString "Tests.ProofSubjectFilesV1" none with
  | .ok pair => pure pair
  | .error error => throw <| IO.userError s!"source load: {error.render}"

private def sourcePath : IO ProjectRelativePath := do
  match parseProjectRelativePath sourcePathString with
  | .ok path => pure path
  | .error error => throw <| IO.userError error

private def resetRoot (path : FilePath) : IO FilePath := do
  try IO.FS.removeDirAll path catch _ => pure ()
  IO.FS.createDirAll path
  IO.FS.realPath path

private def writePair
    (root : FilePath) (semantic provenance : ByteArray) : IO Unit := do
  IO.FS.writeBinFile (root / semanticProgramFileNameV1) semantic
  IO.FS.writeBinFile (root / semanticProvenanceFileNameV1) provenance

private def expectFileFault
    (label : String) (expectedFile : ProofSubjectFileV1)
    (expectedFault : StableFileFaultV1)
    (result : Except ProofSubjectFilesErrorV1 ProofSubjectV1) : IO Unit :=
  match result with
  | .error (.file actualFile actualFault) =>
      expect (actualFile == expectedFile && actualFault == expectedFault)
        (s!"{label}: expected {repr expectedFile}/{repr expectedFault}, got " ++
          s!"{repr actualFile}/{repr actualFault}")
  | .error error => throw <| IO.userError s!"{label}: wrong error {repr error}"
  | .ok _ => throw <| IO.userError s!"{label}: unexpectedly succeeded"

private unsafe def testPositiveAndFaults
    (session : Language.Loader.ParserSession) : IO Unit := do
  let (source, spans) ← loadSourceWithSpans session
  let path ← sourcePath
  let (carrier, provenance) ← match
      normalizeProgramWithProvenanceV1 source path spans with
    | .ok pair => pure pair
    | .error error => throw <| IO.userError s!"normalize: {repr error}"
  let provenanceBytes ← match encodeSemanticProvenanceV1 provenance with
    | .ok bytes => pure bytes
    | .error error => throw <| IO.userError s!"provenance encode: {repr error}"
  let direct ← match buildProofSubjectV1 source path spans
      carrier.canonicalBytes provenanceBytes with
    | .ok subject => pure subject
    | .error error => throw <| IO.userError s!"direct subject: {repr error}"
  let cwd ← IO.currentDir
  let rootInput := cwd / "build/proof-subject-files-v1"
  let rootLink := cwd / "build/proof-subject-files-v1-link"
  let parentLink := cwd / "build/proof-subject-files-v1-parent-link"
  try IO.FS.removeFile rootLink catch _ => pure ()
  try IO.FS.removeFile parentLink catch _ => pure ()
  let root ← resetRoot rootInput
  writePair root carrier.canonicalBytes provenanceBytes
  match ← loadProofSubjectFilesV1 root source path spans with
  | .error error => throw <| IO.userError s!"positive stable-read: {repr error}"
  | .ok subject => do
      expect (subject.program == direct.program) "positive: semantic tuple order"
      expect (subject.provenance == direct.provenance) "positive: provenance tuple order"
      expect (subject.sourceHash == direct.sourceHash) "positive: sourceHash parity"
      expect (subject.semanticHash == direct.semanticHash) "positive: semanticHash parity"
      expect (subject.semanticProvenanceDigest == direct.semanticProvenanceDigest)
        "positive: provenance digest parity"
      expect (subject.closedLeanSource == direct.closedLeanSource)
        "positive: generated source parity"

  expect (match ← loadProofSubjectFilesV1
      (FilePath.mk "build/proof-subject-files-v1") source path spans with
    | .error .invalidRoot => true | _ => false)
    "relative root rejected"
  expect (match ← loadProofSubjectFilesV1
      (FilePath.mk (root.toString ++ "\x00suffix")) source path spans with
    | .error .invalidRoot => true | _ => false)
    "embedded-NUL root rejected"
  runTool "/bin/ln" #["-s", root.toString, rootLink.toString]
  expect (match ← loadProofSubjectFilesV1 rootLink source path spans with
    | .error (.root .unsafePath) => true | _ => false)
    "root symlink rejected"
  runTool "/bin/ln" #["-s", (cwd / "build").toString, parentLink.toString]
  expect (match ← loadProofSubjectFilesV1
      (parentLink / "proof-subject-files-v1") source path spans with
    | .error (.root .unsafePath) => true | _ => false)
    "intermediate root symlink rejected"

  -- Fixed names are authority: alternate valid files cannot substitute.
  let root ← resetRoot rootInput
  IO.FS.writeBinFile (root / "alternate.pfsem") carrier.canonicalBytes
  IO.FS.writeBinFile (root / "alternate.pfprov") provenanceBytes
  expectFileFault "fixed semantic filename" .semanticProgram .notFound
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  writePair root carrier.canonicalBytes provenanceBytes
  IO.FS.removeFile (root / semanticProgramFileNameV1)
  runTool "/bin/ln" #["-s", "alternate.pfsem",
    (root / semanticProgramFileNameV1).toString]
  IO.FS.writeBinFile (root / "alternate.pfsem") carrier.canonicalBytes
  expectFileFault "semantic symlink" .semanticProgram .unsafePath
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  IO.FS.writeBinFile (root / semanticProgramFileNameV1) carrier.canonicalBytes
  IO.FS.writeBinFile (root / "alternate.pfprov") provenanceBytes
  runTool "/bin/ln" #["-s", "alternate.pfprov",
    (root / semanticProvenanceFileNameV1).toString]
  expectFileFault "provenance symlink" .semanticProvenance .unsafePath
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  IO.FS.writeBinFile (root / "semantic-hard-source") carrier.canonicalBytes
  runTool "/bin/ln" #[(root / "semantic-hard-source").toString,
    (root / semanticProgramFileNameV1).toString]
  IO.FS.writeBinFile (root / semanticProvenanceFileNameV1) provenanceBytes
  expectFileFault "semantic hardlink" .semanticProgram .multipleLinks
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  IO.FS.createDirAll (root / semanticProgramFileNameV1)
  IO.FS.writeBinFile (root / semanticProvenanceFileNameV1) provenanceBytes
  expectFileFault "semantic directory" .semanticProgram .nonRegular
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  runTool "/usr/bin/mkfifo" #[(root / semanticProgramFileNameV1).toString]
  IO.FS.writeBinFile (root / semanticProvenanceFileNameV1) provenanceBytes
  expectFileFault "semantic fifo" .semanticProgram .nonRegular
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  IO.FS.writeBinFile (root / semanticProgramFileNameV1) carrier.canonicalBytes
  expectFileFault "missing provenance" .semanticProvenance .notFound
    (← loadProofSubjectFilesV1 root source path spans)

  let root ← resetRoot rootInput
  writePair root carrier.canonicalBytes ByteArray.empty
  expect (match ← loadProofSubjectFilesV1 root source path spans with
    | .error (.subject (.semanticProvenanceWire _)) => true
    | _ => false) "pure provenance decode failure preserved"

private def testFaultWires : IO Unit := do
  let faults : Array StableFileFaultV1 := #[
    .notFound, .permissionDenied, .unsafePath, .nonRegular, .multipleLinks,
    .tooLarge, .shortRead, .grewDuringRead, .changedDuringRead, .io]
  for fault in faults do
    expect (StableFileFaultV1.ofWire? fault.wire == some fault)
      s!"fault wire round-trip: {fault.wire}"
  expect (StableFileFaultV1.ofWire? "unknown" == none)
    "unknown native fault rejected"

unsafe def run : IO Unit := do
  testFaultWires
  let session ← Tests.Language.ParserSession.shared
  testPositiveAndFaults session
  IO.println "Tests.Compiler.ProofSubjectFilesV1: ok"

end Tests.Compiler.ProofSubjectFilesV1
