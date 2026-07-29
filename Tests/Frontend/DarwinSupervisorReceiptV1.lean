/-
  Tests.Frontend.DarwinSupervisorReceiptV1 — B11a2 pure Darwin receipt model.

  This suite freezes only a bounded, public-safe development-observation
  projection. It does not spawn, measure, kill, reap, emit CLI JSON, represent
  Linux `contained`, or claim formal TST-RESOURCE-001 completion.
-/
import ProofForgeV2.Frontend.DarwinSupervisorReceiptV1

namespace Tests.Frontend.DarwinSupervisorReceiptV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1

private def expect (condition : Bool) (message : String) : IO Unit := do
  unless condition do throw <| IO.userError message

private def lift (label : String) (value : Except String α) : IO α :=
  match value with
  | .ok result => pure result
  | .error error => throw <| IO.userError s!"{label}: unexpected error: {error}"

private def expectErr (label : String) (value : Except String α) : IO Unit :=
  match value with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def languageVersion100 : SemVer := {
  major := 1
  minor := 0
  patch := 0
}

private def requestA : IO FrontendRequestV1 := do
  let path ← lift "request A path" (parseProjectRelativePath "tests/a.pf")
  lift "request A"
    (mkFrontendRequestV1 languageVersion100 path "M" none (ByteArray.mk #[0x78]))

private def requestB : IO FrontendRequestV1 := do
  let path ← lift "request B path" (parseProjectRelativePath "tests/b.pf")
  lift "request B"
    (mkFrontendRequestV1 languageVersion100 path "M" none (ByteArray.mk #[0x78]))

private def successObservations : DarwinFrontendPublicObservationsV1 := {
  elapsedMillis := 7
  peakAggregateMemoryBytes := 4096
  peakProcesses := 1
}

private def zeroObservations : DarwinFrontendPublicObservationsV1 := {
  elapsedMillis := 0
  peakAggregateMemoryBytes := 0
  peakProcesses := 0
}

private def goldenJcs : String :=
  "{\"assurance\":\"darwin-development-observed\",\"cleanup\":\"observed-complete\",\"effectiveProfile\":{\"maxAggregateMemoryBytes\":2147483648,\"maxProcesses\":1,\"maxProtocolBytes\":67108864,\"maxPublishedBytes\":0,\"maxStderrBytes\":65536,\"maxWallMillis\":10000,\"memoryMetric\":\"darwinPhysFootprintAggregate\",\"profileId\":\"proof-forge.resource.frontend.v1\",\"schema\":\"proof-forge.resource-profile.v1\",\"stage\":\"frontend\"},\"effectiveProfileDigest\":\"sha256:5f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17\",\"event\":\"response-accepted\",\"hardProfileDigest\":\"sha256:5f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17\",\"hardProfileId\":\"proof-forge.resource.frontend.v1\",\"observations\":{\"elapsedMillis\":7,\"peakAggregateMemoryBytes\":4096,\"peakProcesses\":1},\"requestDigest\":\"sha256:239ae8053f1d8b2b25aedea7471f3d96ef2ecb072948449b60afb0d6e3d25f25\",\"result\":\"response-ok\",\"schema\":\"proof-forge.frontend-darwin-supervisor-receipt.v1\"}"

private def goldenDigest : String :=
  "sha256:a0c5872f1f0f0e8a2575cd71a65bacd5bab889ae5505632c25f8b3b33d14459b"

private def successReceipt : IO DarwinFrontendSupervisorReceiptV1 := do
  mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile (some (← requestA))
    successObservations .responseAccepted .responseOk .observedComplete
    |> lift "success receipt"

private def injectTopLevelField
    (input key : String) (value : PfJson) : Except String String := do
  match ← parsePfJcs input with
  | .object fields => renderPfJcs (.object (fields.push (key, value)))
  | _ => throw "receipt fixture must be an object"

private def testEnumWires : IO Unit := do
  let assurances : Array DarwinFrontendAssuranceV1 := #[.developmentObserved]
  for value in assurances do
    expect (DarwinFrontendAssuranceV1.ofWire? value.wire == some value)
      s!"assurance wire: {value.wire}"
  expect (DarwinFrontendAssuranceV1.ofWire? "contained" == none)
    "Darwin receipt cannot represent contained"
  expect (DarwinFrontendAssuranceV1.ofWire? "linux-contained" == none)
    "Darwin receipt rejects Linux assurance"

  let events : Array DarwinFrontendSupervisorEventV1 := #[
    .responseAccepted, .sourceOpenFailed, .processLimitObserved,
    .memoryLimitObserved, .outputLimitObserved, .deadlineObserved,
    .workerExitObserved, .workerSignalObserved, .supervisorFault
  ]
  for value in events do
    expect (DarwinFrontendSupervisorEventV1.ofWire? value.wire == some value)
      s!"event wire: {value.wire}"
  expect (DarwinFrontendSupervisorEventV1.ofWire? "unknown" == none)
    "unknown event rejected"

  let results : Array DarwinFrontendSupervisorResultV1 := #[
    .responseOk, .responseError, .noResponse
  ]
  for value in results do
    expect (DarwinFrontendSupervisorResultV1.ofWire? value.wire == some value)
      s!"result wire: {value.wire}"
  expect (DarwinFrontendSupervisorResultV1.ofWire? "ok" == none)
    "unknown result rejected"

  let cleanups : Array DarwinFrontendCleanupResultV1 := #[.observedComplete, .incomplete]
  for value in cleanups do
    expect (DarwinFrontendCleanupResultV1.ofWire? value.wire == some value)
      s!"cleanup wire: {value.wire}"
  expect (DarwinFrontendCleanupResultV1.ofWire? "contained-complete" == none)
    "cleanup cannot claim containment"

private def testGoldenAndAccessors : IO Unit := do
  let receipt ← successReceipt
  let rendered ← lift "golden render" (renderDarwinFrontendSupervisorReceiptJcsV1 receipt)
  expect (rendered == goldenJcs) "receipt exact PF-JCS golden"
  expect (rendered.toUTF8.size == 929) "receipt golden byte length"
  let digest ← lift "receipt digest" (darwinFrontendSupervisorReceiptDigestV1 receipt)
  expect ((← lift "receipt digest wire" (renderDigest digest)) == goldenDigest)
    "receipt independent digest KAT"

  expect (DarwinFrontendSupervisorReceiptV1.assurance receipt == .developmentObserved)
    "assurance accessor"
  expect (DarwinFrontendSupervisorReceiptV1.hardProfileId receipt ==
    hardFrontendProfile.profileId) "hard profile id accessor"
  expect (DarwinFrontendSupervisorReceiptV1.effectiveProfile receipt == hardFrontendProfile)
    "effective profile accessor"
  expect (DarwinFrontendSupervisorReceiptV1.observations receipt == successObservations)
    "observations accessor"
  expect (DarwinFrontendSupervisorReceiptV1.event receipt == .responseAccepted)
    "event accessor"
  expect (DarwinFrontendSupervisorReceiptV1.result receipt == .responseOk)
    "result accessor"
  expect (DarwinFrontendSupervisorReceiptV1.cleanup receipt == .observedComplete)
    "cleanup accessor"
  expect (DarwinFrontendSupervisorReceiptV1.requestDigest receipt ==
    some (← lift "request A digest" (requestDigestOfV1 (← requestA))))
    "request digest accessor"
  expect (DarwinFrontendSupervisorReceiptV1.hardProfileDigest receipt ==
    DarwinFrontendSupervisorReceiptV1.effectiveProfileDigest receipt)
    "hard/effective digest equality for hard profile"

  let parsed ← lift "golden parse" (parseDarwinFrontendSupervisorReceiptJcsV1 goldenJcs)
  let rerendered ← lift "golden rerender" (renderDarwinFrontendSupervisorReceiptJcsV1 parsed)
  expect (rerendered == goldenJcs) "parse/render byte identity"
  let rebound ← lift "bind request A" (bindDarwinFrontendSupervisorReceiptV1 (← requestA) parsed)
  expect ((← lift "rebound render" (renderDarwinFrontendSupervisorReceiptJcsV1 rebound)) == goldenJcs)
    "request binding preserves receipt"
  expectErr "cross-request replay"
    (bindDarwinFrontendSupervisorReceiptV1 (← requestB) parsed)

  let requestDigest ← lift "request digest" (requestDigestOfV1 (← requestA))
  let hardDigest ← lift "hard digest" (resourceProfileDigest hardFrontendProfile)
  expect (digest != requestDigest && digest != hardDigest)
    "receipt digest domain separated from request/profile"

private def testProfiles : IO Unit := do
  let request := some (← requestA)
  let lowered := {
    hardFrontendProfile with
    maxWallMillis := 9000
    maxAggregateMemoryBytes := 1024 * 1024 * 1024
    maxProtocolBytes := 32 * 1024 * 1024
    maxStderrBytes := 32 * 1024
  }
  let receipt ← lift "lowered profile receipt"
    (mkDarwinFrontendSupervisorReceiptV1 lowered request successObservations
      .responseAccepted .responseOk .observedComplete)
  expect (DarwinFrontendSupervisorReceiptV1.effectiveProfile receipt == lowered)
    "lowered effective profile retained"
  expect (DarwinFrontendSupervisorReceiptV1.hardProfileDigest receipt !=
    DarwinFrontendSupervisorReceiptV1.effectiveProfileDigest receipt)
    "lowered profile digest differs from hard"

  expectErr "raised wall rejected"
    (mkDarwinFrontendSupervisorReceiptV1
      { hardFrontendProfile with maxWallMillis := hardFrontendProfile.maxWallMillis + 1 }
      request successObservations .responseAccepted .responseOk .observedComplete)
  expectErr "wrong stage rejected"
    (mkDarwinFrontendSupervisorReceiptV1
      { hardFrontendProfile with stage := .compilerCore }
      request successObservations .responseAccepted .responseOk .observedComplete)
  expectErr "wrong metric rejected"
    (mkDarwinFrontendSupervisorReceiptV1
      { hardFrontendProfile with memoryMetric := .linuxCgroupMemoryCurrent }
      request successObservations .responseAccepted .responseOk .observedComplete)
  expectErr "wrong profile id rejected"
    (mkDarwinFrontendSupervisorReceiptV1
      { hardFrontendProfile with profileId := { value := "proof-forge.resource.other.v1" } }
      request successObservations .responseAccepted .responseOk .observedComplete)
  expectErr "published zero cannot rise"
    (mkDarwinFrontendSupervisorReceiptV1
      { hardFrontendProfile with maxPublishedBytes := 1 }
      request successObservations .responseAccepted .responseOk .observedComplete)

private def testCrossFieldInvariants : IO Unit := do
  let request := some (← requestA)
  let _ ← lift "accepted frontend error"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request successObservations
      .responseAccepted .responseError .observedComplete)
  expectErr "accepted response requires request"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile none successObservations
      .responseAccepted .responseOk .observedComplete)
  expectErr "accepted event requires response result"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request successObservations
      .responseAccepted .noResponse .observedComplete)
  expectErr "accepted response requires complete cleanup"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request successObservations
      .responseAccepted .responseOk .incomplete)
  expectErr "non-response event rejects response result"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .workerExitObserved .responseOk .observedComplete)
  let preRequest ← lift "pre-request source-open failure"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile none zeroObservations
      .sourceOpenFailed .noResponse .observedComplete)
  let preRequestWire ← lift "pre-request render"
    (renderDarwinFrontendSupervisorReceiptJcsV1 preRequest)
  expect (preRequestWire.contains "\"requestDigest\":null")
    "pre-request receipt renders explicit null digest"
  let preRequestParsed ← lift "pre-request parse"
    (parseDarwinFrontendSupervisorReceiptJcsV1 preRequestWire)
  expect ((← lift "pre-request rerender"
      (renderDarwinFrontendSupervisorReceiptJcsV1 preRequestParsed)) == preRequestWire)
    "pre-request null digest round-trip"
  expectErr "source-open failure cannot carry request"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .sourceOpenFailed .noResponse .observedComplete)
  let _ ← lift "post-request worker exit"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .workerExitObserved .noResponse .incomplete)
  let _ ← lift "pre-request supervisor fault"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile none zeroObservations
      .supervisorFault .noResponse .incomplete)
  pure ()

private def testObservationBounds : IO Unit := do
  let request := some (← requestA)
  let atLimit : DarwinFrontendPublicObservationsV1 := {
    elapsedMillis := hardFrontendProfile.maxWallMillis
    peakAggregateMemoryBytes := hardFrontendProfile.maxAggregateMemoryBytes
    peakProcesses := hardFrontendProfile.maxProcesses
  }
  let _ ← lift "accepted at exact limits"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request atLimit
      .responseAccepted .responseOk .observedComplete)
  expectErr "accepted elapsed over limit"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { atLimit with elapsedMillis := hardFrontendProfile.maxWallMillis + 1 }
      .responseAccepted .responseOk .observedComplete)
  expectErr "accepted memory over limit"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { atLimit with peakAggregateMemoryBytes :=
          hardFrontendProfile.maxAggregateMemoryBytes + 1 }
      .responseAccepted .responseOk .observedComplete)
  expectErr "accepted process over limit"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { atLimit with peakProcesses := hardFrontendProfile.maxProcesses + 1 }
      .responseAccepted .responseOk .observedComplete)

  let deadline := {
    zeroObservations with elapsedMillis := hardFrontendProfile.maxWallMillis + 1
  }
  let _ ← lift "deadline saturated limit plus one"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request deadline
      .deadlineObserved .noResponse .observedComplete)
  expectErr "deadline event rejects simultaneous memory over"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { deadline with peakAggregateMemoryBytes :=
          hardFrontendProfile.maxAggregateMemoryBytes + 1 }
      .deadlineObserved .noResponse .observedComplete)
  expectErr "deadline event rejects simultaneous process over"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { deadline with peakProcesses := hardFrontendProfile.maxProcesses + 1 }
      .deadlineObserved .noResponse .observedComplete)
  expectErr "deadline limit plus two rejected"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { deadline with elapsedMillis := hardFrontendProfile.maxWallMillis + 2 }
      .deadlineObserved .noResponse .observedComplete)
  expectErr "deadline must saturate elapsed"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .deadlineObserved .noResponse .observedComplete)

  let memory := {
    zeroObservations with
    peakAggregateMemoryBytes := hardFrontendProfile.maxAggregateMemoryBytes + 1
  }
  let _ ← lift "memory saturated limit plus one"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request memory
      .memoryLimitObserved .noResponse .observedComplete)
  expectErr "memory event rejects simultaneous deadline over"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { memory with elapsedMillis := hardFrontendProfile.maxWallMillis + 1 }
      .memoryLimitObserved .noResponse .observedComplete)
  expectErr "memory event rejects simultaneous process over"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { memory with peakProcesses := hardFrontendProfile.maxProcesses + 1 }
      .memoryLimitObserved .noResponse .observedComplete)
  expectErr "memory limit plus two rejected"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { memory with peakAggregateMemoryBytes :=
          hardFrontendProfile.maxAggregateMemoryBytes + 2 }
      .memoryLimitObserved .noResponse .observedComplete)
  expectErr "memory event must saturate memory"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .memoryLimitObserved .noResponse .observedComplete)

  let processes := {
    zeroObservations with peakProcesses := hardFrontendProfile.maxProcesses + 1
  }
  let _ ← lift "process saturated limit plus one"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request processes
      .processLimitObserved .noResponse .observedComplete)
  expectErr "process event rejects simultaneous deadline over"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { processes with elapsedMillis := hardFrontendProfile.maxWallMillis + 1 }
      .processLimitObserved .noResponse .observedComplete)
  expectErr "process event rejects simultaneous memory over"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { processes with peakAggregateMemoryBytes :=
          hardFrontendProfile.maxAggregateMemoryBytes + 1 }
      .processLimitObserved .noResponse .observedComplete)
  expectErr "process limit plus two rejected"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { processes with peakProcesses := hardFrontendProfile.maxProcesses + 2 }
      .processLimitObserved .noResponse .observedComplete)
  expectErr "process event must saturate processes"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .processLimitObserved .noResponse .observedComplete)

  let _ ← lift "output event bounded without stream detail"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request zeroObservations
      .outputLimitObserved .noResponse .observedComplete)
  expectErr "PF-JCS unsafe observation rejected"
    (mkDarwinFrontendSupervisorReceiptV1 hardFrontendProfile request
      { zeroObservations with elapsedMillis := UInt64.ofNat (UInt64.size - 1) }
      .workerSignalObserved .noResponse .observedComplete)
  pure ()

private def testCanonicalAndPrivacyFailures : IO Unit := do
  expectErr "leading whitespace noncanonical"
    (parseDarwinFrontendSupervisorReceiptJcsV1 (" " ++ goldenJcs))
  expectErr "trailing data"
    (parseDarwinFrontendSupervisorReceiptJcsV1 (goldenJcs ++ "x"))
  expectErr "contained assurance rejected"
    (parseDarwinFrontendSupervisorReceiptJcsV1
      (goldenJcs.replace "darwin-development-observed" "contained"))
  expectErr "hard digest tamper"
    (parseDarwinFrontendSupervisorReceiptJcsV1
      (goldenJcs.replace
        "\"hardProfileDigest\":\"sha256:5f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17\""
        "\"hardProfileDigest\":\"sha256:0f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17\""))
  expectErr "effective digest tamper"
    (parseDarwinFrontendSupervisorReceiptJcsV1
      (goldenJcs.replace
        "\"effectiveProfileDigest\":\"sha256:5f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17\""
        "\"effectiveProfileDigest\":\"sha256:0f3181e0fc5f7f15931ae4227782e5c3204e11e9177e1cb949918cc5bdbedc17\""))
  expectErr "schema mismatch"
    (parseDarwinFrontendSupervisorReceiptJcsV1
      (goldenJcs.replace
        "proof-forge.frontend-darwin-supervisor-receipt.v1"
        "proof-forge.frontend-darwin-supervisor-receipt.v2"))
  expectErr "event/result mismatch wire"
    (parseDarwinFrontendSupervisorReceiptJcsV1
      (goldenJcs.replace "response-accepted" "worker-exit-observed"))
  expectErr "missing field"
    (parseDarwinFrontendSupervisorReceiptJcsV1
      (goldenJcs.replace "\"cleanup\":\"observed-complete\"," ""))

  for key in #["path", "stderr", "tail", "secret", "pid", "signal", "exitCode", "detail"] do
    let injected ← lift s!"inject {key}" (injectTopLevelField goldenJcs key (.string "private"))
    expectErr s!"unknown privacy field {key} rejected"
      (parseDarwinFrontendSupervisorReceiptJcsV1 injected)

  let oversized := String.ofList (List.replicate (maxDarwinFrontendSupervisorReceiptJcsBytesV1 + 1) 'x')
  expectErr "receipt input cap before PF-JCS parse"
    (parseDarwinFrontendSupervisorReceiptJcsV1 oversized)

unsafe def run : IO Unit := do
  testEnumWires
  testGoldenAndAccessors
  testProfiles
  testCrossFieldInvariants
  testObservationBounds
  testCanonicalAndPrivacyFailures
  IO.println "Tests.Frontend.DarwinSupervisorReceiptV1: ok"

end Tests.Frontend.DarwinSupervisorReceiptV1
