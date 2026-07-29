/-
  Tests.Frontend.DarwinSourceSupervisorV1 — B11b2 shared safe-open + worker budget.

  Architecture under test:
  * pinned safe-open helper executable (SafeOpen.Req/Ok/Err.v1) supervised by
    the B11b1 Darwin process-group primitive
  * overall monotonic wall from open construction through frontend worker
  * live sourceOpenFailed only for canonical SafeOpenFault + complete cleanup
  * hang/deadline via test-only hang helper path (no product filename hooks)

  Explicit non-claims: not containment, not formal TST-RESOURCE-001 / TASK-D1-08,
  not CLI cutover, not Linux contained.
-/
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
import ProofForgeV2.Frontend.DarwinSupervisorV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Frontend.SafeOpenV1
import ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1
import Tests.Frontend.DarwinWorkerSupervisorV1

namespace Tests.Frontend.DarwinSourceSupervisorV1

open ProofForgeV2
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
open ProofForgeV2.Frontend.DarwinSupervisorV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.SafeOpenV1
open ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1
open System

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def lift (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

private def fixtureRoot : FilePath :=
  FilePath.mk "build/v2/darwin-source-supervisor-tests"

private def frontendWorkerBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-frontend-worker-v1"

private def safeOpenWorkerBin : FilePath :=
  FilePath.mk ".lake/build/bin/proof-forge-frontend-safe-open-worker-v1"

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

private def liftPath (value : String) : IO ProjectRelativePath :=
  match parseProjectRelativePath value with
  | .ok path => pure path
  | .error error => throw <| IO.userError s!"path '{value}': {error}"

private def expectSupervisedOk
    (label : String)
    (result : Except String SupervisedFrontendV1) : IO SupervisedFrontendV1 :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error}"

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
  if result == .noResponse then
    expect (SupervisedFrontendV1.response supervised).isNone
      s!"{label}: noResponse events must not retain a response"

private def expectSourceOpenFailed
    (label : String) (supervised : SupervisedFrontendV1) : IO Unit := do
  expectReceipt label supervised .sourceOpenFailed .noResponse .observedComplete
  let receipt := SupervisedFrontendV1.receipt supervised
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest receipt).isNone
    s!"{label}: sourceOpenFailed must carry requestDigest=none"
  expect (SupervisedFrontendV1.response supervised).isNone
    s!"{label}: sourceOpenFailed must not retain a worker response"

private def superviseSource
    (root : FilePath)
    (rel : String)
    (moduleName : String)
    (effective : ResourceProfileV1 := hardFrontendProfile)
    (programSelector : Option String := none)
    (safeOpenPath : FilePath := safeOpenWorkerBin)
    (frontendPath : FilePath := frontendWorkerBin) :
    IO (Except String SupervisedFrontendV1) := do
  let path ← liftPath rel
  superviseFrontendSourceV1
    safeOpenPath frontendPath root languageVersion100 path moduleName
    programSelector effective

private def writeCounterSource (path : FilePath) : IO Unit :=
  IO.FS.writeFile path Examples.counterSourceText

private def writeParserBadSource (path : FilePath) : IO Unit :=
  IO.FS.writeFile path <|
    "import ProofForgeV2\nopen ProofForgeV2.Language\n" ++
    "program Bad where\n  view get() : UInt64 do\n    return (\n"

private def writeExecutable (name : String) (body : String) : IO FilePath := do
  let path := fixtureRoot / name
  IO.FS.writeFile path body
  runTool "/bin/chmod" #["755", path.toString]
  pure path

private def repeatedByte (size : Nat) (value : UInt8) : ByteArray :=
  ByteArray.mk (Array.replicate size value)

private unsafe def testRegularFileWorkerOk : IO Unit := do
  expect (← safeOpenWorkerBin.pathExists) s!"safe-open worker missing: {safeOpenWorkerBin}"
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "Counter.lean")
  let supervised ← expectSupervisedOk "regular Ok"
    (← superviseSource root "Counter.lean" Examples.counterModuleNameV1)
  expectReceipt "regular Ok" supervised .responseAccepted .responseOk
  let receipt := SupervisedFrontendV1.receipt supervised
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest receipt).isSome
    "regular Ok: requestDigest must be present after request construction"
  match SupervisedFrontendV1.response supervised with
  | none => throw <| IO.userError "regular Ok: response must be some"
  | some (.failure failure) =>
      throw <| IO.userError s!"regular Ok: unexpected diagnostic response: {
        DiagnosticBundleV1.renderHuman (FrontendFailureV1.bundle failure)}"
  | some (.success success) =>
      let path ← liftPath "Counter.lean"
      let request ← lift "regular Ok request" <|
        mkFrontendRequestV1 languageVersion100 path Examples.counterModuleNameV1
          none Examples.counterSourceText.toUTF8
      let _ ← lift "regular Ok reconstruct"
        (reconstructFrontendSuccessV1 request success)
      let _ ← lift "regular Ok receipt bind"
        (bindDarwinFrontendSupervisorReceiptV1 request receipt)

private unsafe def testParserSourceErr : IO Unit := do
  expect (← safeOpenWorkerBin.pathExists) s!"safe-open worker missing: {safeOpenWorkerBin}"
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeParserBadSource (fixtureRoot / "parser-bad.lean")
  let supervised ← expectSupervisedOk "parser Err"
    (← superviseSource root "parser-bad.lean" "Root")
  expectReceipt "parser Err" supervised .responseAccepted .responseError
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt supervised)).isSome
    "parser Err: requestDigest must be present"
  match SupervisedFrontendV1.response supervised with
  | none => throw <| IO.userError "parser Err: response must be some"
  | some (.success _) =>
      throw <| IO.userError "parser Err: expected Frontend.Err.v1 response"
  | some (.failure failure) =>
      let diagnostics := FrontendFailureV1.diagnostics failure
      expect (!diagnostics.isEmpty) "parser Err: empty diagnostics"
      expect (diagnostics.any (fun d => d.code == .sourceInvalid))
        s!"parser Err: missing PF-SRC-INVALID in {diagnostics.map (·.code.wire)}"

/-- Frontend worker is a marker script that creates a side file when spawned. -/
private def markerFrontendWorker (marker : FilePath) : IO FilePath :=
  writeExecutable "marker-frontend.sh" <|
    "#!/bin/sh\n" ++
    s!"/usr/bin/touch '{marker}'\n" ++
    "exit 7\n"

private unsafe def expectSafeOpenFaultNoFrontendSpawn
    (label : String) (rel : String) : IO Unit := do
  let root ← IO.FS.realPath fixtureRoot
  let marker := fixtureRoot / s!"marker-{label}.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let supervised ← expectSupervisedOk label
    (← superviseSource root rel "Root" hardFrontendProfile none
      safeOpenWorkerBin frontend)
  expectSourceOpenFailed label supervised
  expect (!(← marker.pathExists))
    s!"{label}: frontend worker must not be spawned (marker present)"

private unsafe def testPracticalSafeOpenFaults : IO Unit := do
  expect (← safeOpenWorkerBin.pathExists) s!"safe-open worker missing: {safeOpenWorkerBin}"
  writeCounterSource (fixtureRoot / "good.lean")
  runTool "/bin/ln" #["-s", "good.lean", (fixtureRoot / "leaf-link.lean").toString]
  runTool "/bin/ln" #["-s", "nested", (fixtureRoot / "linked-dir").toString]
  IO.FS.createDirAll (fixtureRoot / "nested")
  writeCounterSource (fixtureRoot / "nested" / "good.lean")
  IO.FS.writeFile (fixtureRoot / "hard-source.lean") "hard\n"
  runTool "/bin/ln" #[
    (fixtureRoot / "hard-source.lean").toString,
    (fixtureRoot / "hard-link.lean").toString
  ]
  IO.FS.writeFile (fixtureRoot / "denied.lean") "denied\n"
  runTool "/bin/chmod" #["000", (fixtureRoot / "denied.lean").toString]
  IO.FS.createDirAll (fixtureRoot / "directory.lean")
  try IO.FS.removeFile (fixtureRoot / "fifo.lean") catch _ => pure ()
  runTool "/usr/bin/mkfifo" #[(fixtureRoot / "fifo.lean").toString]
  try IO.FS.removeFile (fixtureRoot / "socket.lean") catch _ => pure ()
  let socketPath := (fixtureRoot / "socket.lean").toString
  runTool "/usr/bin/python3" #[
    "-c",
    s!"import socket; p={repr socketPath}; s=socket.socket(socket.AF_UNIX); s.bind(p); s.listen(1)"
  ]

  expectSafeOpenFaultNoFrontendSpawn "missing" "missing.lean"
  expectSafeOpenFaultNoFrontendSpawn "leaf symlink" "leaf-link.lean"
  expectSafeOpenFaultNoFrontendSpawn "intermediate symlink" "linked-dir/good.lean"
  expectSafeOpenFaultNoFrontendSpawn "hardlink" "hard-link.lean"
  expectSafeOpenFaultNoFrontendSpawn "permission" "denied.lean"
  runTool "/bin/chmod" #["600", (fixtureRoot / "denied.lean").toString]
  expectSafeOpenFaultNoFrontendSpawn "directory" "directory.lean"
  expectSafeOpenFaultNoFrontendSpawn "fifo" "fifo.lean"
  expectSafeOpenFaultNoFrontendSpawn "socket" "socket.lean"

  let relRoot := FilePath.mk "build/v2/darwin-source-supervisor-tests"
  let marker := fixtureRoot / "marker-relative.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let supervisedRel ← expectSupervisedOk "relative root"
    (← superviseSource relRoot "good.lean" "Root" hardFrontendProfile none
      safeOpenWorkerBin frontend)
  expectSourceOpenFailed "relative root" supervisedRel
  expect (!(← marker.pathExists)) "relative root: no frontend spawn"

private unsafe def testFifoDoesNotHangParent : IO Unit := do
  expect (← safeOpenWorkerBin.pathExists) s!"safe-open worker missing: {safeOpenWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  try IO.FS.removeFile (fixtureRoot / "fifo-hang.lean") catch _ => pure ()
  runTool "/usr/bin/mkfifo" #[(fixtureRoot / "fifo-hang.lean").toString]
  let profile := lowerFrontendProfile (wall := some 2000)
  let start ← IO.monoMsNow
  let supervised ← expectSupervisedOk "fifo non-hang"
    (← superviseSource root "fifo-hang.lean" "Root" profile)
  let elapsed := (← IO.monoMsNow) - start
  expectSourceOpenFailed "fifo non-hang" supervised
  expect (elapsed < 1500)
    s!"fifo non-hang: parent spent {elapsed}ms; must fail well under wall budget"

private unsafe def testExactAndOverSourceLimit : IO Unit := do
  expect (← safeOpenWorkerBin.pathExists) s!"safe-open worker missing: {safeOpenWorkerBin}"
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  IO.FS.writeBinFile (fixtureRoot / "exact-limit.lean") (repeatedByte maxSourceBytes 0x61)
  let exact ← expectSupervisedOk "exact 16 MiB open"
    (← superviseSource root "exact-limit.lean" "Root")
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt exact)).isSome
    "exact 16 MiB: request must be constructed after successful open"
  expect (DarwinFrontendSupervisorReceiptV1.event
      (SupervisedFrontendV1.receipt exact) != .sourceOpenFailed)
    "exact 16 MiB: must not mint sourceOpenFailed"

  IO.FS.writeBinFile (fixtureRoot / "over-limit.lean")
    (repeatedByte (maxSourceBytes + 1) 0x62)
  let marker := fixtureRoot / "marker-over.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let over ← expectSupervisedOk "over 16 MiB"
    (← superviseSource root "over-limit.lean" "Root" hardFrontendProfile none
      safeOpenWorkerBin frontend)
  expectSourceOpenFailed "over 16 MiB" over
  expect (!(← marker.pathExists)) "over 16 MiB: no frontend spawn"

private unsafe def testOpenHangDeadlineViaHelper : IO Unit := do
  -- Test-only hang opener: single-process sleep past wall (no product hooks).
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "hang-target.lean")
  let hangOpener ← writeExecutable "hang-opener.py" <|
    "#!/usr/bin/python3\n" ++
    "import time\n" ++
    "time.sleep(5)\n"
  let profile := lowerFrontendProfile (wall := some 150)
  let start ← IO.monoMsNow
  let supervised ← expectSupervisedOk "open hang deadline"
    (← superviseSource root "hang-target.lean" "Root" profile none
      hangOpener frontendWorkerBin)
  let parentElapsed := (← IO.monoMsNow) - start
  expectReceipt "open hang deadline" supervised .deadlineObserved .noResponse
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt supervised)).isNone
    "open hang deadline: pre-request deadline must keep requestDigest=none"
  let obs := DarwinFrontendSupervisorReceiptV1.observations
    (SupervisedFrontendV1.receipt supervised)
  expect (obs.elapsedMillis.toNat == profile.maxWallMillis.toNat + 1)
    s!"open hang deadline: elapsed must saturate limit+1, got {obs.elapsedMillis}"
  expect (parentElapsed < 2000)
    s!"open hang deadline: parent wall {parentElapsed}ms looks unbounded"

private unsafe def testSharedBudgetNoRearm : IO Unit := do
  -- Two robust 1800ms segments: each is below the 3000ms wall, while their
  -- 3600ms sum is above it. The marker proves the frontend phase really began;
  -- requestDigest=some proves open/decode/request construction completed.
  expect (← safeOpenWorkerBin.pathExists) s!"safe-open worker missing: {safeOpenWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "budget-counter.lean")
  let wall : UInt64 := 3000
  let phaseDelayMillis : Nat := 1800
  expect (phaseDelayMillis < wall.toNat &&
      phaseDelayMillis * 2 > wall.toNat)
    "shared budget fixture must keep each phase below wall and sum above wall"
  let profile := lowerFrontendProfile (wall := some wall)
  let openerPath := safeOpenWorkerBin.toString
  let slowOpener ← writeExecutable "slow-opener.py" <|
    "#!/usr/bin/python3\n" ++
    "import os, time\n" ++
    "time.sleep(1.80)\n" ++
    s!"os.execv({repr openerPath}, [{repr openerPath}])\n"
  let marker := fixtureRoot / "budget-marker.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let markerS := marker.toString
  let slowFrontend ← writeExecutable "slow-frontend.py" <|
    "#!/usr/bin/python3\n" ++
    "import time\n" ++
    s!"open({repr markerS}, 'w').close()\n" ++
    "time.sleep(1.80)\n"
  let start ← IO.monoMsNow
  let supervised ← expectSupervisedOk "shared budget"
    (← superviseSource root "budget-counter.lean" Examples.counterModuleNameV1
      profile none slowOpener slowFrontend)
  let parentElapsed := (← IO.monoMsNow) - start
  expectReceipt "shared budget" supervised .deadlineObserved .noResponse
  let receipt := SupervisedFrontendV1.receipt supervised
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest receipt).isSome
    "shared budget: requestDigest must exist after successful open phase"
  expect (← marker.pathExists)
    "shared budget: frontend marker must exist before shared deadline fires"
  let obs := DarwinFrontendSupervisorReceiptV1.observations receipt
  expect (obs.elapsedMillis.toNat == wall.toNat + 1)
    s!"shared budget: elapsed must saturate *original* wall+1 (no re-arm), got {
      obs.elapsedMillis}"
  expect (parentElapsed < wall.toNat + 1200)
    s!"shared budget: parent elapsed {parentElapsed}ms suggests re-arm or hang"

private unsafe def testFinalReceiptRetainsOpenPeaks : IO Unit := do
  -- The opener deliberately reaches a much larger footprint than the tiny
  -- response-replay frontend. The final receipt must retain the phase maximum.
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "peak-counter.lean")
  let path ← liftPath "peak-counter.lean"
  let request ← lift "peak request" <|
    mkFrontendRequestV1 languageVersion100 path Examples.counterModuleNameV1
      none Examples.counterSourceText.toUTF8
  let requestBytes ← lift "peak request bytes" (encodeFrontendRequestV1 request)
  let responseBytes ←
    match ← ProofForgeV2.Frontend.WorkerV1.processFrameV1 requestBytes with
    | .error fault =>
        throw <| IO.userError s!"peak response fixture fault: {repr fault}"
    | .ok bytes => pure bytes
  let responsePath := fixtureRoot / "peak-response.bin"
  IO.FS.writeBinFile responsePath responseBytes
  let replayFrontend ← writeExecutable "peak-frontend.sh" <|
    "#!/bin/sh\n" ++
    s!"exec /bin/cat '{responsePath}'\n"

  let openerPath := safeOpenWorkerBin.toString
  let peakOpener ← writeExecutable "peak-opener.py" <|
    "#!/usr/bin/python3\n" ++
    "import os, time\n" ++
    "payload = bytearray(96 * 1024 * 1024)\n" ++
    "for i in range(0, len(payload), 4096): payload[i] = 1\n" ++
    "time.sleep(0.25)\n" ++
    s!"os.execv({repr openerPath}, [{repr openerPath}])\n"
  let profile := lowerFrontendProfile (wall := some 5000)
    (memory := some (256 * 1024 * 1024)) (processes := some 1)
  let supervised ← expectSupervisedOk "final phase peaks"
    (← superviseSource root "peak-counter.lean" Examples.counterModuleNameV1
      profile none peakOpener replayFrontend)
  expectReceipt "final phase peaks" supervised .responseAccepted .responseOk
  let receipt := SupervisedFrontendV1.receipt supervised
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest receipt).isSome
    "final phase peaks: request digest present"
  let obs := DarwinFrontendSupervisorReceiptV1.observations receipt
  expect (obs.peakAggregateMemoryBytes ≥ 64 * 1024 * 1024)
    s!"final phase peaks: open peak was discarded ({obs.peakAggregateMemoryBytes})"
  expect (obs.peakProcesses == 1)
    s!"final phase peaks: process maximum expected 1, got {obs.peakProcesses}"

private unsafe def testMalformedOpenerResponse : IO Unit := do
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "malformed-target.lean")
  let badOpener ← writeExecutable "malformed-opener.sh" <|
    "#!/bin/sh\n" ++
    "printf 'not-a-safe-open-frame'\n" ++
    "exit 0\n"
  let marker := fixtureRoot / "malformed-marker.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let supervised ← expectSupervisedOk "malformed opener"
    (← superviseSource root "malformed-target.lean" "Root" hardFrontendProfile
      none badOpener frontend)
  expectReceipt "malformed opener" supervised .supervisorFault .noResponse
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt supervised)).isNone
    "malformed opener: no request digest"
  expect (SupervisedFrontendV1.response supervised).isNone
    "malformed opener: no response"
  expect (!(← marker.pathExists)) "malformed opener: no frontend spawn"

private unsafe def testOpenerNonzeroExit : IO Unit := do
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "exit-target.lean")
  let badOpener ← writeExecutable "exit-opener.sh" <|
    "#!/bin/sh\n" ++
    "exit 9\n"
  let marker := fixtureRoot / "exit-marker.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let supervised ← expectSupervisedOk "opener exit"
    (← superviseSource root "exit-target.lean" "Root" hardFrontendProfile none
      badOpener frontend)
  expectReceipt "opener exit" supervised .workerExitObserved .noResponse
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt supervised)).isNone
    "opener exit: no request digest"
  expect (!(← marker.pathExists)) "opener exit: no frontend spawn"

private unsafe def expectOpenTransportEvent
    (label : String)
    (opener : FilePath)
    (profile : ResourceProfileV1)
    (expectedEvent : DarwinFrontendSupervisorEventV1) : IO Unit := do
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "transport-target.lean")
  let marker := fixtureRoot / s!"transport-{label}.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let supervised ← expectSupervisedOk label
    (← superviseSource root "transport-target.lean" "Root" profile none
      opener frontend)
  expectReceipt label supervised expectedEvent .noResponse
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt supervised)).isNone
    s!"{label}: open transport event must precede request construction"
  expect (!(← marker.pathExists))
    s!"{label}: frontend must not spawn after open transport event"

private unsafe def testOpenPhaseTransportEvents : IO Unit := do
  let signalOpener ← writeExecutable "signal-opener.sh" <|
    "#!/bin/sh\n" ++
    "kill -TERM $$\n" ++
    "wait\n"
  expectOpenTransportEvent "opener signal" signalOpener hardFrontendProfile
    .workerSignalObserved

  let outputCap : UInt64 := 1024
  let outputOpener ← writeExecutable "output-opener.py" <|
    "#!/usr/bin/python3\n" ++
    "import sys\n" ++
    s!"sys.stdout.buffer.write(b'X' * {outputCap.toNat + 1})\n"
  expectOpenTransportEvent "opener output" outputOpener
    (lowerFrontendProfile (wall := some 5000) (protocol := some outputCap))
    .outputLimitObserved

  let processOpener ← writeExecutable "process-opener.sh" <|
    "#!/bin/sh\n" ++
    "/bin/sleep 30 &\n" ++
    "wait\n"
  expectOpenTransportEvent "opener process" processOpener
    (lowerFrontendProfile (wall := some 5000) (processes := some 1))
    .processLimitObserved

  let memoryOpener ← writeExecutable "memory-opener.py" <|
    "#!/usr/bin/python3\n" ++
    "import time\n" ++
    "payload = bytearray(48 * 1024 * 1024)\n" ++
    "time.sleep(30)\n"
  expectOpenTransportEvent "opener memory" memoryOpener
    (lowerFrontendProfile (wall := some 10000)
      (memory := some (8 * 1024 * 1024)) (processes := some 1))
    .memoryLimitObserved

private unsafe def testUnknownFaultWireRejected : IO Unit := do
  -- Hand-built Err frame with unknown fault label must not become sourceOpenFailed.
  expect (← frontendWorkerBin.pathExists) s!"frontend worker missing: {frontendWorkerBin}"
  let root ← IO.FS.realPath fixtureRoot
  writeCounterSource (fixtureRoot / "unknown-fault-target.lean")
  -- Build a noncanonical failure by writing a forged frame via Python/shell is
  -- fragile; instead emit a valid-looking tagged frame with bogus wire using a
  -- tiny Lean-encoded fixture written to disk by the test process.
  let forged ← do
    -- Encode a failure with a known fault, then mutate the wire bytes in the
    -- payload region is complex. Simpler: opener prints a complete Ok-shaped
    -- garbage tag that fails decode (already covered). For unknown wire:
    -- use a shell that runs a precomputed binary blob.
    let failure ← lift "known failure" (mkSafeOpenWorkerFailureV1 .notFound)
    let bytes ← lift "failure bytes" (encodeSafeOpenWorkerFailureV1 failure)
    -- Mutate the UTF-8 payload of the fault wire to an unknown label while
    -- keeping length: "not-found" (9) → "not-foundX" won't fit. Replace with
    -- same-length unknown "not-found" → use "bad-fault" if same len...
    -- "not-found" is 9; "undefined" is 9.
    let wire := "not-found".toUTF8
    let alt := "undefined".toUTF8
    expect (wire.size == alt.size) "unknown-fault fixture length"
    let mut out := ByteArray.empty
    let mut i := 0
    let mut replaced := false
    -- Naive search/replace of the wire bytes inside the frame.
    while i < bytes.size do
      if !replaced && i + wire.size ≤ bytes.size then
        let slice := bytes.extract i (i + wire.size)
        if slice == wire then
          out := out.append alt
          i := i + wire.size
          replaced := true
        else
          out := out.push (bytes.get! i)
          i := i + 1
      else
        out := out.push (bytes.get! i)
        i := i + 1
    expect replaced "unknown-fault fixture must replace wire"
    pure out
  let blob := fixtureRoot / "unknown-fault.bin"
  IO.FS.writeBinFile blob forged
  let badOpener ← writeExecutable "unknown-fault-opener.sh" <|
    "#!/bin/sh\n" ++
    s!"exec /bin/cat '{blob}'\n"
  let marker := fixtureRoot / "unknown-fault-marker.flag"
  try IO.FS.removeFile marker catch _ => pure ()
  let frontend ← markerFrontendWorker marker
  let supervised ← expectSupervisedOk "unknown fault wire"
    (← superviseSource root "unknown-fault-target.lean" "Root"
      hardFrontendProfile none badOpener frontend)
  -- Decoder rejects unknown wire → supervisorFault, not sourceOpenFailed.
  expect (DarwinFrontendSupervisorReceiptV1.event
      (SupervisedFrontendV1.receipt supervised) == .supervisorFault)
    "unknown fault wire must not mint sourceOpenFailed"
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest
      (SupervisedFrontendV1.receipt supervised)).isNone
    "unknown fault wire: no request digest"
  expect (!(← marker.pathExists)) "unknown fault wire: no frontend spawn"

private unsafe def runDarwinMatrix : IO Unit := do
  resetFixtureRoot
  try
    testRegularFileWorkerOk
    testParserSourceErr
    testPracticalSafeOpenFaults
    testFifoDoesNotHangParent
    testExactAndOverSourceLimit
    testOpenHangDeadlineViaHelper
    testSharedBudgetNoRearm
    testFinalReceiptRetainsOpenPeaks
    testMalformedOpenerResponse
    testOpenerNonzeroExit
    testOpenPhaseTransportEvents
    testUnknownFaultWireRejected
  finally
    cleanupFixtureRoot

unsafe def runFast : IO Unit := do
  if !System.Platform.isOSX then
    IO.println "Tests.Frontend.DarwinSourceSupervisorV1 (fast): skip (non-Darwin host)"
  else
    resetFixtureRoot
    try
      testRegularFileWorkerOk
      testParserSourceErr
      testPracticalSafeOpenFaults
      testFifoDoesNotHangParent
      testMalformedOpenerResponse
      testOpenerNonzeroExit
      testOpenPhaseTransportEvents
      testUnknownFaultWireRejected
    finally
      cleanupFixtureRoot
    IO.println "Tests.Frontend.DarwinSourceSupervisorV1 (fast): ok"

unsafe def run : IO Unit := do
  if !System.Platform.isOSX then
    IO.println "Tests.Frontend.DarwinSourceSupervisorV1: skip (non-Darwin host)"
  else
    runDarwinMatrix
    IO.println "Tests.Frontend.DarwinSourceSupervisorV1: ok"

end Tests.Frontend.DarwinSourceSupervisorV1
