/-
  Tests.Frontend.SafeOpenV1 — B11a native source safe-open foundation.

  The ordinary suite proves component-by-component no-follow behavior and stable,
  bounded reads. It does not claim a read deadline, process containment, a
  supervisor receipt, CLI cutover, or formal TST-RESOURCE-001 completion.
  Host-isolated concurrent truncate/grow/rebind and device/socket cases remain in
  the B11b resource/supervisor matrix rather than this deterministic fast suite.
-/
import ProofForgeV2.Frontend.SafeOpenV1

namespace Tests.Frontend.SafeOpenV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.SafeOpenV1
open System

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def liftPath (value : String) : IO ProjectRelativePath :=
  match parseProjectRelativePath value with
  | .ok path => pure path
  | .error error => throw <| IO.userError s!"path '{value}': {error}"

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
      s!"fixture tool failed: {cmd} {args}, exit={output.exitCode}, stderr={output.stderr}"

private def expectFault (label : String) (expected : SafeOpenFaultV1)
    (root : FilePath) (path : ProjectRelativePath) : IO Unit := do
  match ← safeOpenSourceV1 root path with
  | .error actual =>
      expect (actual == expected)
        s!"{label}: expected {repr expected}, got {repr actual}"
  | .ok snapshot =>
      throw <| IO.userError
        s!"{label}: unexpectedly opened {SafeSourceSnapshotV1.size snapshot} bytes"

private def testFaultWires : IO Unit := do
  let faults : Array SafeOpenFaultV1 := #[
    .invalidRoot, .notFound, .permissionDenied, .unsafePath, .nonRegular,
    .multipleLinks, .tooLarge, .shortRead, .grewDuringRead,
    .changedDuringRead, .io, .nativeProtocol
  ]
  for fault in faults do
    expect (SafeOpenFaultV1.ofWire? fault.wire == some fault)
      s!"fault wire round-trip: {fault.wire}"
  expect (SafeOpenFaultV1.ofWire? "unknown" == none) "unknown fault wire rejected"

private def prepareFixture : IO (FilePath × FilePath) := do
  let cwd ← IO.currentDir
  let rootInput := FilePath.mk "build/frontend-safe-open-v1"
  let rootLinkInput := FilePath.mk "build/frontend-safe-open-v1-root-link"
  try IO.FS.removeFile rootLinkInput catch _ => pure ()
  try IO.FS.removeDirAll rootInput catch _ => pure ()
  IO.FS.createDirAll (rootInput / "nested")
  IO.FS.writeBinFile (rootInput / "nested/good.lean") "program Good where\n".toUTF8
  IO.FS.writeBinFile (rootInput / "empty.lean") ByteArray.empty
  IO.FS.writeBinFile (rootInput / "hard-source.lean") "hard link fixture\n".toUTF8
  IO.FS.writeBinFile (rootInput / "denied.lean") "permission fixture\n".toUTF8
  runTool "/bin/chmod" #["000", (rootInput / "denied.lean").toString]
  IO.FS.createDirAll (rootInput / "directory.lean")
  runTool "/bin/ln" #["-s", "nested/good.lean", (rootInput / "leaf-link.lean").toString]
  runTool "/bin/ln" #["-s", "nested", (rootInput / "linked-dir").toString]
  runTool "/bin/ln" #[(rootInput / "hard-source.lean").toString,
    (rootInput / "hard-link.lean").toString]
  runTool "/usr/bin/mkfifo" #[(rootInput / "fifo.lean").toString]
  runTool "/bin/ln" #["-s", rootInput.toString, rootLinkInput.toString]
  pure (← IO.FS.realPath rootInput, cwd / rootLinkInput)

private def testRegularEmptyAndDeterminism (root : FilePath) : IO Unit := do
  let good ← liftPath "nested/good.lean"
  let expected := "program Good where\n".toUTF8
  let first ← safeOpenSourceV1 root good
  let second ← safeOpenSourceV1 root good
  match first, second with
  | .ok a, .ok b =>
      expect (SafeSourceSnapshotV1.bytes a == expected) "regular file exact bytes"
      expect (SafeSourceSnapshotV1.bytes b == expected) "repeat exact bytes"
      expect (SafeSourceSnapshotV1.bytes a == SafeSourceSnapshotV1.bytes b)
        "repeat deterministic bytes"
      expect (SafeSourceSnapshotV1.size a == expected.size) "snapshot size"
  | .error error, _ | _, .error error =>
      throw <| IO.userError s!"regular file rejected: {repr error}"

  let empty ← liftPath "empty.lean"
  match ← safeOpenSourceV1 root empty with
  | .ok snapshot => expect (SafeSourceSnapshotV1.bytes snapshot).isEmpty "empty file accepted"
  | .error error => throw <| IO.userError s!"empty file rejected: {repr error}"

private def testUnsafeNodes (root rootLink : FilePath) : IO Unit := do
  expectFault "relative root" .invalidRoot (FilePath.mk "build/frontend-safe-open-v1")
    (← liftPath "nested/good.lean")
  expectFault "root symlink" .unsafePath rootLink (← liftPath "nested/good.lean")
  expectFault "leaf symlink" .unsafePath root (← liftPath "leaf-link.lean")
  expectFault "intermediate symlink" .unsafePath root (← liftPath "linked-dir/good.lean")
  expectFault "hard link" .multipleLinks root (← liftPath "hard-link.lean")
  expectFault "permission denied" .permissionDenied root (← liftPath "denied.lean")
  runTool "/bin/chmod" #["600", (root / "denied.lean").toString]
  expectFault "directory leaf" .nonRegular root (← liftPath "directory.lean")
  expectFault "fifo leaf" .nonRegular root (← liftPath "fifo.lean")
  expectFault "missing leaf" .notFound root (← liftPath "missing.lean")

private def repeatedByte (size : Nat) (value : UInt8) : ByteArray :=
  ByteArray.mk (Array.replicate size value)

private def testExactAndOverSourceLimit (root : FilePath) : IO Unit := do
  let exactPath := root / "exact-limit.lean"
  let overPath := root / "over-limit.lean"
  IO.FS.writeBinFile exactPath (repeatedByte maxSourceBytes 0x61)
  IO.FS.writeBinFile overPath (repeatedByte (maxSourceBytes + 1) 0x62)
  match ← safeOpenSourceV1 root (← liftPath "exact-limit.lean") with
  | .ok snapshot =>
      expect (SafeSourceSnapshotV1.size snapshot == maxSourceBytes)
        "exact 16 MiB accepted"
      expect ((SafeSourceSnapshotV1.bytes snapshot)[0]? == some 0x61)
        "exact boundary first byte"
      expect ((SafeSourceSnapshotV1.bytes snapshot)[maxSourceBytes - 1]? == some 0x61)
        "exact boundary last byte"
  | .error error => throw <| IO.userError s!"exact source limit rejected: {repr error}"
  expectFault "source limit + 1" .tooLarge root (← liftPath "over-limit.lean")

unsafe def runFast : IO Unit := do
  testFaultWires
  let (root, rootLink) ← prepareFixture
  testRegularEmptyAndDeterminism root
  testUnsafeNodes root rootLink
  IO.println "Tests.Frontend.SafeOpenV1 (fast): ok"

unsafe def run : IO Unit := do
  testFaultWires
  let (root, rootLink) ← prepareFixture
  testRegularEmptyAndDeterminism root
  testUnsafeNodes root rootLink
  testExactAndOverSourceLimit root
  IO.println "Tests.Frontend.SafeOpenV1: ok"

end Tests.Frontend.SafeOpenV1
