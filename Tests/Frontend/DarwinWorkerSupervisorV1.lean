/-
  Tests.Frontend.DarwinWorkerSupervisorV1 — B11b Darwin worker supervisor matrix.

  Focused process-level contract suite for the Darwin development-observed
  supervisor primitive and receipt composer.

  Scope boundary (explicit non-claims):
  * not process/session containment
  * not formal TST-RESOURCE-001 / TASK-D1-08 completion
  * not proof of CLI containment or formal executable/import identity
  * not safe-open integration (B11b2/B12 composition is tested separately)
  * not Linux `contained` assurance
-/
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
import ProofForgeV2.Frontend.DarwinSupervisorV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Frontend.WorkerV1

namespace Tests.Frontend.DarwinWorkerSupervisorV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
open ProofForgeV2.Frontend.DarwinSupervisorV1
open ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
open ProofForgeV2.Frontend.ProtocolV1
open System

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def fixtureRoot : FilePath :=
  FilePath.mk "build/v2/darwin-worker-supervisor-tests"

private def workerBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-frontend-worker-v1"

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

private def resetFixtureRoot : IO Unit := do
  try IO.FS.removeDirAll fixtureRoot catch _ => pure ()
  IO.FS.createDirAll fixtureRoot

private def cleanupFixtureRoot : IO Unit := do
  try IO.FS.removeDirAll fixtureRoot catch _ => pure ()

/-- Write a temporary executable under the build fixture root only. -/
private def writeExecutable (name : String) (body : String) : IO FilePath := do
  let path := fixtureRoot / name
  IO.FS.writeFile path body
  runTool "/bin/chmod" #["755", path.toString]
  pure path

private def lowerFrontendProfile
    (wall : Option UInt64 := none)
    (memory : Option UInt64 := none)
    (processes : Option UInt32 := none)
    (protocol : Option UInt64 := none)
    (stderr : Option UInt64 := none) : ResourceProfileV1 :=
  { hardFrontendProfile with
    maxWallMillis := wall.getD hardFrontendProfile.maxWallMillis
    maxAggregateMemoryBytes := memory.getD hardFrontendProfile.maxAggregateMemoryBytes
    maxProcesses := processes.getD hardFrontendProfile.maxProcesses
    maxProtocolBytes := protocol.getD hardFrontendProfile.maxProtocolBytes
    maxStderrBytes := stderr.getD hardFrontendProfile.maxStderrBytes }

private def languageVersion100 : SemVer := {
  major := 1
  minor := 0
  patch := 0
}

private def requestWith
    (source : ByteArray)
    (moduleName : String)
    (pathValue : String)
    (version : SemVer := languageVersion100)
    (programSelector : Option String := none) : IO FrontendRequestV1 := do
  let path ← lift "path" (parseProjectRelativePath pathValue)
  lift "request" <| mkFrontendRequestV1 version path moduleName programSelector source

private def counterRequest : IO FrontendRequestV1 :=
  requestWith Examples.counterSourceText.toUTF8 Examples.counterModuleNameV1
    "Examples/Counter.lean"

private def parserBadRequest : IO FrontendRequestV1 := do
  let source :=
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program Bad where\n  view get() : UInt64 do\n    return (\n"
  requestWith source.toUTF8 "Root" "tests/darwin-supervisor-parser-bad.lean"

private def expectOutcomeOk
    (label : String)
    (result : Except DarwinWorkerSupervisorFaultV1 DarwinWorkerSupervisorOutcomeV1) :
    IO DarwinWorkerSupervisorOutcomeV1 :=
  match result with
  | .ok outcome => pure outcome
  | .error fault =>
      throw <| IO.userError s!"{label}: unexpected supervisor fault {repr fault}"

private def expectSupervisedOk
    (label : String)
    (result : Except String SupervisedFrontendV1) : IO SupervisedFrontendV1 :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def expectEvent
    (label : String)
    (expected : DarwinWorkerSupervisorEventV1)
    (outcome : DarwinWorkerSupervisorOutcomeV1) : IO Unit :=
  expect (DarwinWorkerSupervisorOutcomeV1.event outcome == expected)
    s!"{label}: event expected {repr expected}, got {repr (DarwinWorkerSupervisorOutcomeV1.event outcome)}"

private def expectNoPartial
    (label : String) (outcome : DarwinWorkerSupervisorOutcomeV1) : IO Unit :=
  expect (DarwinWorkerSupervisorOutcomeV1.responseBytes outcome).isEmpty
    s!"{label}: partial responseBytes must be empty, size={
      (DarwinWorkerSupervisorOutcomeV1.responseBytes outcome).size}"

private def expectCleanupComplete
    (label : String) (outcome : DarwinWorkerSupervisorOutcomeV1) : IO Unit :=
  expect (DarwinWorkerSupervisorOutcomeV1.cleanup outcome == .observedComplete)
    s!"{label}: cleanup expected observed-complete, got {
      repr (DarwinWorkerSupervisorOutcomeV1.cleanup outcome)}"

private def expectReceipt
    (label : String)
    (supervised : SupervisedFrontendV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1 := .observedComplete) : IO Unit := do
  let receipt := SupervisedFrontendV1.receipt supervised
  expect (DarwinFrontendSupervisorReceiptV1.event receipt == event)
    s!"{label}: receipt event expected {repr event}, got {
      repr (DarwinFrontendSupervisorReceiptV1.event receipt)}"
  expect (DarwinFrontendSupervisorReceiptV1.result receipt == result)
    s!"{label}: receipt result expected {repr result}, got {
      repr (DarwinFrontendSupervisorReceiptV1.result receipt)}"
  expect (DarwinFrontendSupervisorReceiptV1.assurance receipt == .developmentObserved)
    s!"{label}: assurance must remain darwin-development-observed"
  expect (DarwinFrontendSupervisorReceiptV1.cleanup receipt == cleanup)
    s!"{label}: cleanup expected {repr cleanup}, got {
      repr (DarwinFrontendSupervisorReceiptV1.cleanup receipt)}"

private def superviseFrame
    (workerPath : FilePath)
    (input : ByteArray)
    (effective : ResourceProfileV1) :
    IO (Except DarwinWorkerSupervisorFaultV1 DarwinWorkerSupervisorOutcomeV1) :=
  superviseDarwinWorkerFrameV1 workerPath input effective

private def superviseRequest
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1) :
    IO (Except String SupervisedFrontendV1) :=
  superviseFrontendRequestV1 workerPath request effective

private def expectComposedNoResponse
    (label : String)
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1)
    (event : DarwinFrontendSupervisorEventV1) : IO Unit := do
  let supervised ← expectSupervisedOk label
    (← superviseRequest workerPath request effective)
  expectReceipt label supervised event .noResponse .observedComplete
  expect (SupervisedFrontendV1.response supervised).isNone
    s!"{label}: non-response event must not retain a response"
  let _ ← lift s!"{label}: receipt request binding"
    (bindDarwinFrontendSupervisorReceiptV1 request
      (SupervisedFrontendV1.receipt supervised))
  pure ()

/-- Closed event family is exhaustively named so GREEN cannot silently rename. -/
private def testClosedEventFamilyCompiles : IO Unit := do
  let events : Array DarwinWorkerSupervisorEventV1 := #[
    .responseCandidate, .processLimit, .memoryLimit, .outputLimit,
    .deadline, .workerExit, .workerSignal, .supervisorFault
  ]
  expect (events.size == 8) "worker supervisor event family is closed at 8 constructors"
  for event in events do
    expect (event == event) s!"event DecidableEq: {repr event}"

private unsafe def testRealWorkerCounterSuccess : IO Unit := do
  expect (← workerBin.pathExists) s!"worker binary missing: {workerBin}"
  let request ← counterRequest
  let requestBytes ← lift "counter request bytes" (encodeFrontendRequestV1 request)
  let transport ← expectOutcomeOk "counter transport"
    (← superviseFrame workerBin requestBytes hardFrontendProfile)
  expectEvent "counter transport" .responseCandidate transport
  expectCleanupComplete "counter transport" transport
  let transportResponse ← lift "counter transport response"
    (decodeFrontendResponseV1
      (DarwinWorkerSupervisorOutcomeV1.responseBytes transport))
  match transportResponse with
  | .failure failure =>
      throw <| IO.userError s!"counter transport: unexpected diagnostic response: {
        DiagnosticBundleV1.renderHuman (FrontendFailureV1.bundle failure)}"
  | .success success =>
      let _ ← lift "counter transport bind"
        (bindFrontendSuccessV1 request success)
  let supervised ← expectSupervisedOk "counter success"
    (← superviseRequest workerBin request hardFrontendProfile)
  expectReceipt "counter success" supervised .responseAccepted .responseOk
  let receipt := SupervisedFrontendV1.receipt supervised
  expect (DarwinFrontendSupervisorReceiptV1.cleanup receipt == .observedComplete)
    "counter success cleanup must be observed-complete"
  let _ ← lift "counter bind receipt"
    (bindDarwinFrontendSupervisorReceiptV1 request receipt)
  match SupervisedFrontendV1.response supervised with
  | none => throw <| IO.userError "counter success: response must be some"
  | some (.failure failure) =>
      throw <| IO.userError s!"counter success: unexpected diagnostic response: {
        DiagnosticBundleV1.renderHuman (FrontendFailureV1.bundle failure)}"
  | some (.success success) =>
      let _ ← lift "counter reconstruct"
        (reconstructFrontendSuccessV1 request success)
  let observations := DarwinFrontendSupervisorReceiptV1.observations receipt
  -- Equal-limit acceptance: a successful response may saturate but never exceed.
  expect (observations.elapsedMillis ≤ hardFrontendProfile.maxWallMillis)
    "counter success elapsed ≤ wall limit"
  expect (observations.peakAggregateMemoryBytes ≤
      hardFrontendProfile.maxAggregateMemoryBytes)
    "counter success memory ≤ memory limit"
  expect (observations.peakProcesses ≤ hardFrontendProfile.maxProcesses)
    "counter success processes ≤ process limit"

private unsafe def testRealWorkerParserError : IO Unit := do
  expect (← workerBin.pathExists) s!"worker binary missing: {workerBin}"
  let request ← parserBadRequest
  let supervised ← expectSupervisedOk "parser error"
    (← superviseRequest workerBin request hardFrontendProfile)
  expectReceipt "parser error" supervised .responseAccepted .responseError
  let _ ← lift "parser bind receipt"
    (bindDarwinFrontendSupervisorReceiptV1 request
      (SupervisedFrontendV1.receipt supervised))
  match SupervisedFrontendV1.response supervised with
  | none => throw <| IO.userError "parser error: response must be some"
  | some (.success _) =>
      throw <| IO.userError "parser error: expected Frontend.Err.v1 response"
  | some (.failure failure) =>
      let diagnostics := FrontendFailureV1.diagnostics failure
      expect (!diagnostics.isEmpty) "parser error: empty diagnostics"
      expect (diagnostics.any (fun d => d.code == .sourceInvalid))
        s!"parser error: missing PF-SRC-INVALID in {diagnostics.map (·.code.wire)}"

private unsafe def testPrimitiveDeadline : IO Unit := do
  -- Distinct fixture: long sleep under a tiny lower-only wall budget.
  let script ← writeExecutable "deadline-sleep.sh" <|
    "#!/bin/sh\n" ++
    "exec /bin/sleep 5\n"
  let profile := lowerFrontendProfile (wall := some 100)
  let outcome ← expectOutcomeOk "deadline"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "deadline" .deadline outcome
  expectNoPartial "deadline" outcome
  expectCleanupComplete "deadline" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.elapsedMillis.toNat == profile.maxWallMillis.toNat + 1)
    s!"deadline: elapsed must saturate limit+1, got {obs.elapsedMillis}"
  expect (obs.peakAggregateMemoryBytes ≤ profile.maxAggregateMemoryBytes)
    "deadline: must not co-report memory over-limit (no test theater)"
  expect (obs.peakProcesses ≤ profile.maxProcesses)
    "deadline: must not co-report process over-limit (no test theater)"
  let request ← counterRequest
  expectComposedNoResponse "deadline composer" script request profile
    .deadlineObserved

private unsafe def testAbsoluteBudgetExpiresBeforeSpawn : IO Unit := do
  let marker := fixtureRoot / "expired-budget-spawned.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let script ← writeExecutable "expired-budget-worker.sh" <|
    "#!/bin/sh\n" ++
    s!"/usr/bin/touch '{marker}'\n" ++
    "exit 0\n"
  let profile := lowerFrontendProfile (wall := some 100)
  let budget ← match ← startDarwinFrontendBudgetV1 with
    | .error fault =>
        throw <| IO.userError s!"absolute budget mint failed: {repr fault}"
    | .ok budget => pure budget
  IO.sleep 150
  let outcome ← expectOutcomeOk "expired absolute budget"
    (← superviseDarwinWorkerFrameWithBudgetV1 script ByteArray.empty profile budget)
  expectEvent "expired absolute budget" .deadline outcome
  expectNoPartial "expired absolute budget" outcome
  expectCleanupComplete "expired absolute budget" outcome
  expect (!(← marker.pathExists))
    "expired absolute budget must be rejected before worker spawn"
  let observations := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (observations.elapsedMillis.toNat == profile.maxWallMillis.toNat + 1)
    "expired absolute budget must saturate the original wall limit"

private unsafe def testWorkerExecutesPrivateSnapshot : IO Unit := do
  let observedPath := fixtureRoot / "snapshot-observed-path.txt"
  try IO.FS.removeFile observedPath catch _ => pure ()
  let script ← writeExecutable "snapshot-origin.sh" <|
    "#!/bin/sh\n" ++
    s!"printf '%s' \"$0\" > '{observedPath}'\n" ++
    "exit 7\n"
  let outcome ← expectOutcomeOk "private worker snapshot"
    (← superviseFrame script ByteArray.empty hardFrontendProfile)
  expectEvent "private worker snapshot" .workerExit outcome
  expectCleanupComplete "private worker snapshot" outcome
  let executedPath ← IO.FS.readFile observedPath
  expect ((executedPath.splitOn "/.proof-forge-worker-").length == 2)
    s!"worker must execute an adjacent fd-derived private snapshot, got {executedPath}"
  expect (executedPath.endsWith "/worker")
    s!"worker snapshot leaf must be fixed, got {executedPath}"
  expect (executedPath != script.toString)
    "supervisor must never execute the caller pathname directly"
  expect (!(← (FilePath.mk executedPath).pathExists))
    "private worker snapshot must be removed after process cleanup"

private unsafe def testSnapshotMutationFailsClosed : IO Unit := do
  let observedPath := fixtureRoot / "mutation-observed-path.txt"
  try IO.FS.removeFile observedPath catch _ => pure ()
  let observedPathS := observedPath.toString
  -- Single-process fixture: the snapshot copy is mode 0500, so the mutation
  -- needs an in-process chmod; zsh + zmodload zsh/files provides builtin
  -- chmod/print (no child under maxProcesses=1), and `exec /bin/sleep`
  -- reuses the leader image. A `#!/usr/bin/python3` shebang empirically
  -- trips processLimit on Darwin/Xcode-CLT before its mutation is observed.
  let script ← writeExecutable "snapshot-self-mutate.zsh" <|
    "#!/bin/zsh\n" ++
    "zmodload zsh/files || exit 43\n" ++
    s!"print -n \"$0\" > '{observedPathS}' || exit 44\n" ++
    "chmod 0700 \"$0\" || exit 45\n" ++
    "print '\\n# changed after suspended-spawn verification\\n' >> \"$0\" || exit 46\n" ++
    "exec /bin/sleep 5\n"
  let originalBytes ← IO.FS.readBinFile script
  let outcome ← expectOutcomeOk "snapshot mutation"
    (← superviseFrame script ByteArray.empty hardFrontendProfile)
  expectEvent "snapshot mutation" .supervisorFault outcome
  expectNoPartial "snapshot mutation" outcome
  expectCleanupComplete "snapshot mutation" outcome
  expect ((← IO.FS.readBinFile script) == originalBytes)
    "snapshot mutation must not modify the caller worker inode"
  let executedPath ← IO.FS.readFile observedPath
  expect (!(← (FilePath.mk executedPath).pathExists))
    "mutated worker snapshot must still be removed"

private unsafe def testWorkerSymlinkRejectedBeforeSpawn : IO Unit := do
  let marker := fixtureRoot / "symlink-worker-ran.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let target ← writeExecutable "symlink-target.sh" <|
    "#!/bin/sh\n" ++ s!": > '{marker}'\n" ++ "exit 0\n"
  let link := fixtureRoot / "symlink-worker.sh"
  runTool "/bin/ln" #["-s", target.fileName.getD "symlink-target.sh", link.toString]
  match ← superviseFrame link ByteArray.empty hardFrontendProfile with
  | .error .spawnFailed => pure ()
  | .error fault =>
      throw <| IO.userError s!"worker symlink: expected spawnFailed, got {repr fault}"
  | .ok outcome =>
      throw <| IO.userError s!"worker symlink unexpectedly spawned: {
        repr (DarwinWorkerSupervisorOutcomeV1.event outcome)}"
  expect (!(← marker.pathExists))
    "worker symlink must be rejected before any worker code runs"

private unsafe def testInvalidWorkerMetadataRejected : IO Unit := do
  let marker := fixtureRoot / "invalid-worker-ran.flag"
  try IO.FS.removeFile marker catch _ => pure ()

  let nonExecutable := fixtureRoot / "non-executable-worker.sh"
  IO.FS.writeFile nonExecutable <|
    "#!/bin/sh\n" ++ s!": > '{marker}'\n" ++ "exit 0\n"
  runTool "/bin/chmod" #["600", nonExecutable.toString]
  match ← superviseFrame nonExecutable ByteArray.empty hardFrontendProfile with
  | .error .spawnFailed => pure ()
  | .error fault =>
      throw <| IO.userError s!"non-executable worker: expected spawnFailed, got {repr fault}"
  | .ok _ => throw <| IO.userError "non-executable worker unexpectedly spawned"

  let hardlinkSource ← writeExecutable "hardlink-source.sh" <|
    "#!/bin/sh\n" ++ s!": > '{marker}'\n" ++ "exit 0\n"
  let hardlinkWorker := fixtureRoot / "hardlink-worker.sh"
  runTool "/bin/ln" #[hardlinkSource.toString, hardlinkWorker.toString]
  match ← superviseFrame hardlinkWorker ByteArray.empty hardFrontendProfile with
  | .error .spawnFailed => pure ()
  | .error fault =>
      throw <| IO.userError s!"hardlink worker: expected spawnFailed, got {repr fault}"
  | .ok _ => throw <| IO.userError "hardlink worker unexpectedly spawned"

  let oversizeWorker := fixtureRoot / "oversize-worker"
  runTool "/usr/bin/truncate" #["-s", "536870913", oversizeWorker.toString]
  runTool "/bin/chmod" #["700", oversizeWorker.toString]
  match ← superviseFrame oversizeWorker ByteArray.empty hardFrontendProfile with
  | .error .spawnFailed => pure ()
  | .error fault =>
      throw <| IO.userError s!"oversize worker: expected spawnFailed, got {repr fault}"
  | .ok _ => throw <| IO.userError "oversize worker unexpectedly spawned"

  expect (!(← marker.pathExists))
    "invalid worker metadata must be rejected before any worker code runs"

private unsafe def testSnapshotClearsInheritedAcl : IO Unit := do
  let aclParent := fixtureRoot / "acl-parent"
  IO.FS.createDirAll aclParent
  runTool "/bin/chmod" #["+a",
    "everyone allow read,write,execute,file_inherit,directory_inherit",
    aclParent.toString]
  let observed := fixtureRoot / "snapshot-acl-observed.txt"
  let source := aclParent / "acl-source.sh"
  IO.FS.writeFile source <|
    "#!/bin/sh\n" ++
    "if [ -w \"$0\" ]; then file=writable; else file=sealed; fi\n" ++
    "dir=${0%/*}\n" ++
    "if [ -w \"$dir\" ]; then dir_state=writable; else dir_state=sealed; fi\n" ++
    s!"printf 'file=%s dir=%s' \"$file\" \"$dir_state\" > '{observed}'\n" ++
    "exit 7\n"
  runTool "/bin/chmod" #["755", source.toString]
  let outcome ← expectOutcomeOk "snapshot inherited ACL"
    (← superviseFrame source ByteArray.empty hardFrontendProfile)
  expectEvent "snapshot inherited ACL" .workerExit outcome
  expectCleanupComplete "snapshot inherited ACL" outcome
  expect ((← IO.FS.readFile observed) == "file=sealed dir=sealed")
    "snapshot file and directory must clear inherited extended ACL write access"

private unsafe def testPrimitiveProcessLimit : IO Unit := do
  -- Distinct fixture: background child under maxProcesses=1 → peak = max+1.
  let script ← writeExecutable "process-bg-child.sh" <|
    "#!/bin/sh\n" ++
    "/bin/sleep 30 &\n" ++
    "wait\n"
  let profile := lowerFrontendProfile (processes := some 1) (wall := some 5000)
  let outcome ← expectOutcomeOk "process limit"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "process limit" .processLimit outcome
  expectNoPartial "process limit" outcome
  expectCleanupComplete "process limit" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.peakProcesses.toNat == profile.maxProcesses.toNat + 1)
    s!"process limit: peakProcesses must saturate max+1, got {obs.peakProcesses}"
  expect (obs.elapsedMillis ≤ profile.maxWallMillis)
    "process limit: must not co-report wall over-limit"
  expect (obs.peakAggregateMemoryBytes ≤ profile.maxAggregateMemoryBytes)
    "process limit: must not co-report memory over-limit"
  let request ← counterRequest
  expectComposedNoResponse "process limit composer" script request profile
    .processLimitObserved

private unsafe def testPrimitiveMemoryLimit : IO Unit := do
  -- Distinct fixture: single-process in-process allocation (no children).
  -- zsh parameter expansion holds ~48MiB without any external helper;
  -- `/usr/bin/python3` empirically peaks at 2 pgroup members under the
  -- supervisor on Darwin/Xcode-CLT and would trip processLimit first.
  let script ← writeExecutable "memory-alloc.zsh" <|
    "#!/bin/zsh\n" ++
    "big=${(l[50331648][x])}\n" ++
    "while true; do :; done\n"
  let profile := lowerFrontendProfile
    (memory := some (8 * 1024 * 1024)) (wall := some 10000) (processes := some 1)
  let outcome ← expectOutcomeOk "memory limit"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "memory limit" .memoryLimit outcome
  expectNoPartial "memory limit" outcome
  expectCleanupComplete "memory limit" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.peakAggregateMemoryBytes.toNat ==
      profile.maxAggregateMemoryBytes.toNat + 1)
    s!"memory limit: peak memory must saturate max+1, got {obs.peakAggregateMemoryBytes}"
  expect (obs.elapsedMillis ≤ profile.maxWallMillis)
    "memory limit: must not co-report wall over-limit"
  expect (obs.peakProcesses ≤ profile.maxProcesses)
    "memory limit: must not co-report process over-limit"
  let request ← counterRequest
  expectComposedNoResponse "memory limit composer" script request profile
    .memoryLimitObserved

private unsafe def testPrimitiveStdoutCap : IO Unit := do
  -- Distinct fixture: stdout size = protocol cap + 1.
  let cap : Nat := 64
  let script ← writeExecutable "stdout-over-cap.zsh" <|
    "#!/bin/zsh\n" ++
    "print -n -r -- ${(l[" ++ toString (cap + 1) ++ "][X])}\n"
  let profile := lowerFrontendProfile
    (protocol := some (UInt64.ofNat cap)) (wall := some 5000)
  let outcome ← expectOutcomeOk "stdout cap"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "stdout cap" .outputLimit outcome
  expectNoPartial "stdout cap" outcome
  expectCleanupComplete "stdout cap" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.elapsedMillis ≤ profile.maxWallMillis)
    "stdout cap: isolate from deadline theater"
  expect (obs.peakProcesses ≤ profile.maxProcesses)
    "stdout cap: isolate from process theater"
  expect (obs.peakAggregateMemoryBytes ≤ profile.maxAggregateMemoryBytes)
    "stdout cap: isolate from memory theater"

private unsafe def testPrimitiveStderrCap : IO Unit := do
  -- Distinct fixture: stderr size = stderr cap + 1 (stdout empty).
  let cap : Nat := 32
  let script ← writeExecutable "stderr-over-cap.zsh" <|
    "#!/bin/zsh\n" ++
    "print -n -r -- ${(l[" ++ toString (cap + 1) ++ "][Y])} >&2\n"
  let profile := lowerFrontendProfile
    (stderr := some (UInt64.ofNat cap)) (wall := some 5000)
  let outcome ← expectOutcomeOk "stderr cap"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "stderr cap" .outputLimit outcome
  expectNoPartial "stderr cap" outcome
  expectCleanupComplete "stderr cap" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.elapsedMillis ≤ profile.maxWallMillis)
    "stderr cap: isolate from deadline theater"
  expect (obs.peakProcesses ≤ profile.maxProcesses)
    "stderr cap: isolate from process theater"
  expect (obs.peakAggregateMemoryBytes ≤ profile.maxAggregateMemoryBytes)
    "stderr cap: isolate from memory theater"
  let request ← counterRequest
  expectComposedNoResponse "stderr cap composer" script request profile
    .outputLimitObserved

private unsafe def testPrimitiveExactStderrCapRemainsCandidate : IO Unit := do
  let cap : Nat := 32
  let script ← writeExecutable "stderr-exact-cap.zsh" <|
    "#!/bin/zsh\n" ++
    "print -n -r -- ${(l[" ++ toString cap ++ "][Y])} >&2\n"
  let profile := lowerFrontendProfile
    (stderr := some (UInt64.ofNat cap)) (wall := some 5000)
  let outcome ← expectOutcomeOk "exact stderr cap"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "exact stderr cap" .responseCandidate outcome
  expectCleanupComplete "exact stderr cap" outcome
  expect (DarwinWorkerSupervisorOutcomeV1.responseBytes outcome).isEmpty
    "exact stderr cap: stdout response candidate remains empty"

private unsafe def testPrimitiveExactStdoutCapRemainsCandidate : IO Unit := do
  -- Equal-limit acceptance: exact stdout size == maxProtocolBytes is still a candidate.
  let cap : Nat := 48
  let script ← writeExecutable "stdout-exact-cap.zsh" <|
    "#!/bin/zsh\n" ++
    "print -n -r -- ${(l[" ++ toString cap ++ "][Z])}\n"
  let profile := lowerFrontendProfile
    (protocol := some (UInt64.ofNat cap)) (wall := some 5000)
  let outcome ← expectOutcomeOk "exact stdout cap"
    (← superviseFrame script ByteArray.empty profile)
  expectEvent "exact stdout cap" .responseCandidate outcome
  expectCleanupComplete "exact stdout cap" outcome
  let bytes := DarwinWorkerSupervisorOutcomeV1.responseBytes outcome
  expect (bytes.size == cap)
    s!"exact stdout cap: responseBytes size expected {cap}, got {bytes.size}"
  expect (bytes == ByteArray.mk (Array.replicate cap (0x5a : UInt8)))
    "exact stdout cap: payload identity"

private unsafe def testPrimitiveNonzeroExit : IO Unit := do
  let script ← writeExecutable "nonzero-exit.sh" <|
    "#!/bin/sh\n" ++
    "exit 7\n"
  let outcome ← expectOutcomeOk "nonzero exit"
    (← superviseFrame script ByteArray.empty hardFrontendProfile)
  expectEvent "nonzero exit" .workerExit outcome
  expectNoPartial "nonzero exit" outcome
  expectCleanupComplete "nonzero exit" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.elapsedMillis ≤ hardFrontendProfile.maxWallMillis)
    "nonzero exit: isolate from deadline theater"
  expect (obs.peakProcesses ≤ hardFrontendProfile.maxProcesses)
    "nonzero exit: isolate from process theater"
  expect (obs.peakAggregateMemoryBytes ≤ hardFrontendProfile.maxAggregateMemoryBytes)
    "nonzero exit: isolate from memory theater"
  let request ← counterRequest
  expectComposedNoResponse "nonzero exit composer" script request
    hardFrontendProfile .workerExitObserved

private unsafe def testPrimitiveSignal : IO Unit := do
  let script ← writeExecutable "self-term.sh" <|
    "#!/bin/sh\n" ++
    "kill -TERM $$\n" ++
    "wait\n"
  let outcome ← expectOutcomeOk "signal"
    (← superviseFrame script ByteArray.empty hardFrontendProfile)
  expectEvent "signal" .workerSignal outcome
  expectNoPartial "signal" outcome
  expectCleanupComplete "signal" outcome
  let obs := DarwinWorkerSupervisorOutcomeV1.observations outcome
  expect (obs.elapsedMillis ≤ hardFrontendProfile.maxWallMillis)
    "signal: isolate from deadline theater"
  expect (obs.peakProcesses ≤ hardFrontendProfile.maxProcesses)
    "signal: isolate from process theater"
  expect (obs.peakAggregateMemoryBytes ≤ hardFrontendProfile.maxAggregateMemoryBytes)
    "signal: isolate from memory theater"
  let request ← counterRequest
  expectComposedNoResponse "signal composer" script request hardFrontendProfile
    .workerSignalObserved

private unsafe def testMalformedExit0StdoutComposer : IO Unit := do
  -- Distinct fixture: exit 0 with non-protocol stdout → workerExit + noResponse.
  let script ← writeExecutable "malformed-exit0.sh" <|
    "#!/bin/sh\n" ++
    "printf 'not-a-frontend-response-frame'\n" ++
    "exit 0\n"
  let request ← counterRequest
  let supervised ← expectSupervisedOk "malformed exit0"
    (← superviseRequest script request hardFrontendProfile)
  expectReceipt "malformed exit0" supervised .workerExitObserved .noResponse
  expect (SupervisedFrontendV1.response supervised).isNone
    "malformed exit0: response must be none"
  let _ ← lift "malformed bind receipt"
    (bindDarwinFrontendSupervisorReceiptV1 request
      (SupervisedFrontendV1.receipt supervised))
  -- The low-level primitive is transport-only: exact-cap bytes remain a
  -- response candidate. Only the frontend composer owns protocol decoding and
  -- converts this malformed candidate into workerExit/noResponse.
  let input ← lift "malformed request bytes" (encodeFrontendRequestV1 request)
  let outcome ← expectOutcomeOk "malformed frame"
    (← superviseFrame script input hardFrontendProfile)
  expectEvent "malformed frame" .responseCandidate outcome
  expect (DarwinWorkerSupervisorOutcomeV1.responseBytes outcome ==
      "not-a-frontend-response-frame".toUTF8)
    "malformed frame: primitive must retain the exact response candidate"

private unsafe def testCrossRequestResponseRejected : IO Unit := do
  let foreignRequest ← requestWith Examples.counterSourceText.toUTF8
    Examples.counterModuleNameV1 "tests/foreign-response.lean"
  let diagnostic := DiagnosticV1.make .sourceInvalid "foreign response fixture"
  let failure ← lift "foreign failure"
    (mkFrontendFailureV1 foreignRequest #[diagnostic])
  let responseBytes ← lift "foreign failure bytes"
    (encodeFrontendFailureV1 failure)
  let responsePath := fixtureRoot / "foreign-response.bin"
  IO.FS.writeBinFile responsePath responseBytes
  let script ← writeExecutable "foreign-response.sh" <|
    "#!/bin/sh\n" ++
    s!"exec /bin/cat '{responsePath}'\n"
  let request ← counterRequest
  let supervised ← expectSupervisedOk "cross-request response"
    (← superviseRequest script request hardFrontendProfile)
  expectReceipt "cross-request response" supervised .workerExitObserved .noResponse
  expect (SupervisedFrontendV1.response supervised).isNone
    "cross-request response must not be accepted"
  let _ ← lift "cross-request receipt binds current request"
    (bindDarwinFrontendSupervisorReceiptV1 request
      (SupervisedFrontendV1.receipt supervised))

  let foreignInput ← lift "foreign success request bytes"
    (encodeFrontendRequestV1 foreignRequest)
  let successBytes ←
    match ← ProofForgeV2.Frontend.WorkerV1.processFrameV1 foreignInput with
    | .error fault =>
        throw <| IO.userError s!"foreign success worker fault: {repr fault}"
    | .ok bytes => pure bytes
  match ← lift "foreign success decode" (decodeFrontendResponseV1 successBytes) with
  | .failure _ => throw <| IO.userError "foreign success fixture produced failure"
  | .success _ => pure ()
  let successPath := fixtureRoot / "foreign-success.bin"
  IO.FS.writeBinFile successPath successBytes
  let successScript ← writeExecutable "foreign-success.sh" <|
    "#!/bin/sh\n" ++
    s!"exec /bin/cat '{successPath}'\n"
  let successReplay ← expectSupervisedOk "cross-request success"
    (← superviseRequest successScript request hardFrontendProfile)
  expectReceipt "cross-request success" successReplay
    .workerExitObserved .noResponse
  expect (SupervisedFrontendV1.response successReplay).isNone
    "cross-request success must not be accepted"

private unsafe def testMissingWorkerMintsClosedFaultReceipt : IO Unit := do
  let request ← counterRequest
  let supervised ← expectSupervisedOk "missing worker"
    (← superviseRequest (fixtureRoot / "missing-worker") request hardFrontendProfile)
  expectReceipt "missing worker" supervised .supervisorFault .noResponse .incomplete
  expect (DarwinFrontendSupervisorReceiptV1.cleanup
      (SupervisedFrontendV1.receipt supervised) == .incomplete)
    "missing worker cleanup must be incomplete"
  expect (DarwinFrontendSupervisorReceiptV1.observations
      (SupervisedFrontendV1.receipt supervised) ==
      { elapsedMillis := 0, peakAggregateMemoryBytes := 0, peakProcesses := 0 })
    "missing worker observations must be redacted zeros"
  expect (SupervisedFrontendV1.response supervised).isNone
    "missing worker must not carry a response"
  let _ ← lift "missing worker receipt bind"
    (bindDarwinFrontendSupervisorReceiptV1 request
      (SupervisedFrontendV1.receipt supervised))

private unsafe def testRaisedProfileRejected : IO Unit := do
  expect (← workerBin.pathExists) s!"worker binary missing: {workerBin}"
  let request ← counterRequest
  let raisedWall := {
    hardFrontendProfile with
    maxWallMillis := hardFrontendProfile.maxWallMillis + 1
  }
  match ← superviseRequest workerBin request raisedWall with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "raised wall profile must be rejected"
  let raisedProcess := {
    hardFrontendProfile with
    maxProcesses := hardFrontendProfile.maxProcesses + 1
  }
  match ← superviseRequest workerBin request raisedProcess with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "raised process profile must be rejected"
  let raisedMemory := {
    hardFrontendProfile with
    maxAggregateMemoryBytes := hardFrontendProfile.maxAggregateMemoryBytes + 1
  }
  match ← superviseRequest workerBin request raisedMemory with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "raised memory profile must be rejected"
  let raisedProtocol := {
    hardFrontendProfile with
    maxProtocolBytes := hardFrontendProfile.maxProtocolBytes + 1
  }
  match ← superviseRequest workerBin request raisedProtocol with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "raised protocol profile must be rejected"
  let raisedStderr := {
    hardFrontendProfile with
    maxStderrBytes := hardFrontendProfile.maxStderrBytes + 1
  }
  match ← superviseRequest workerBin request raisedStderr with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "raised stderr profile must be rejected"
  let tooSmallProtocol := lowerFrontendProfile (protocol := some 64)
  match ← superviseRequest workerBin request tooSmallProtocol with
  | .error _ => pure ()
  | .ok _ =>
      throw <| IO.userError
        "request larger than effective protocol cap must fail before spawn"
  -- Frame-level closed fault rejection (any constructor; no theater on success path).
  let input ← lift "raised profile request bytes" (encodeFrontendRequestV1 request)
  match ← superviseFrame workerBin input raisedWall with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError "frame-level raised profile must yield a closed fault"

private unsafe def runDarwinMatrix : IO Unit := do
  resetFixtureRoot
  try
    testClosedEventFamilyCompiles
    testRealWorkerCounterSuccess
    testRealWorkerParserError
    testPrimitiveDeadline
    testAbsoluteBudgetExpiresBeforeSpawn
    testWorkerExecutesPrivateSnapshot
    testSnapshotMutationFailsClosed
    testWorkerSymlinkRejectedBeforeSpawn
    testInvalidWorkerMetadataRejected
    testSnapshotClearsInheritedAcl
    testPrimitiveProcessLimit
    testPrimitiveMemoryLimit
    testPrimitiveStdoutCap
    testPrimitiveStderrCap
    testPrimitiveExactStderrCapRemainsCandidate
    testPrimitiveExactStdoutCapRemainsCandidate
    testPrimitiveNonzeroExit
    testPrimitiveSignal
    testMalformedExit0StdoutComposer
    testCrossRequestResponseRejected
    testMissingWorkerMintsClosedFaultReceipt
    testRaisedProfileRejected
  finally
    cleanupFixtureRoot

unsafe def run : IO Unit := do
  if !System.Platform.isOSX then
    IO.println "Tests.Frontend.DarwinWorkerSupervisorV1: skip (non-Darwin host)"
  else
    runDarwinMatrix
    IO.println "Tests.Frontend.DarwinWorkerSupervisorV1: ok"

end Tests.Frontend.DarwinWorkerSupervisorV1
