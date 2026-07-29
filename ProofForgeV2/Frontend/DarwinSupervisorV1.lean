/-
  ProofForgeV2.Frontend.DarwinSupervisorV1 — B11b Darwin frontend composer.

  B11b1: `superviseFrontendRequestV1` encodes Frontend.Req.v1 and supervises the
  B10 frontend worker under a lower-only effective profile.

  B11b2: `superviseFrontendSourceV1` first supervises a pinned safe-open helper
  executable (SafeOpen.Req/Ok/Err.v1) via the same hardened Darwin process-group
  primitive, then (on Ok) constructs Frontend.Req.v1 and supervises the frontend
  worker. A single overall monotonic wall start covers open → parent decode /
  request construction → frontend worker. Prior elapsed is recomputed from that
  start before each supervise call; prior ≥ wall mints deadlineObserved without
  spawn. No parent-side fork of safe-open; no product test hooks.

  Explicit non-claims:
  * assurance remains `darwin-development-observed`
  * not process/session containment, not formal TST-RESOURCE-001 / TASK-D1-08
  * not CLI product cutover; not Linux `contained`
-/
import ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1

namespace ProofForgeV2.Frontend.DarwinSupervisorV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
open ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1
open System

/-- Private-ctor supervised frontend result: receipt + optional decoded response. -/
structure SupervisedFrontendV1 where
  private mk ::
  private receipt_ : DarwinFrontendSupervisorReceiptV1
  private response_ : Option FrontendResponseV1

namespace SupervisedFrontendV1

def receipt (s : SupervisedFrontendV1) : DarwinFrontendSupervisorReceiptV1 :=
  s.receipt_

def response (s : SupervisedFrontendV1) : Option FrontendResponseV1 :=
  s.response_

end SupervisedFrontendV1

private def zeroObservations : DarwinFrontendPublicObservationsV1 :=
  { elapsedMillis := 0
    peakAggregateMemoryBytes := 0
    peakProcesses := 0 }

/-- Compose phase observations without summing peaks. The second-phase elapsed
    already includes prior wall consumption; max also keeps this total if a
    native fault returns only the retained open observation. -/
private def maxPhaseObservations
    (openPhase frontendPhase : DarwinFrontendPublicObservationsV1) :
    DarwinFrontendPublicObservationsV1 :=
  { elapsedMillis := max openPhase.elapsedMillis frontendPhase.elapsedMillis
    peakAggregateMemoryBytes := max openPhase.peakAggregateMemoryBytes
      frontendPhase.peakAggregateMemoryBytes
    peakProcesses := max openPhase.peakProcesses frontendPhase.peakProcesses }

private def deadlineObservations
    (effective : ResourceProfileV1)
    (prior : DarwinFrontendPublicObservationsV1) :
    DarwinFrontendPublicObservationsV1 :=
  { elapsedMillis := effective.maxWallMillis + 1
    peakAggregateMemoryBytes := prior.peakAggregateMemoryBytes
    peakProcesses := prior.peakProcesses }

private def mintNativeFaultSupervised
    (effective : ResourceProfileV1)
    (request : FrontendRequestV1)
    (prior : DarwinFrontendPublicObservationsV1) :
    Except String SupervisedFrontendV1 := do
  let receipt ← mkDarwinFrontendSupervisorReceiptV1
    effective (some request) prior
    .supervisorFault .noResponse .incomplete
  pure ⟨receipt, none⟩

private def mintReceipt
    (effective : ResourceProfileV1)
    (request : Option FrontendRequestV1)
    (observations : DarwinFrontendPublicObservationsV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1)
    (response : Option FrontendResponseV1) :
    Except String SupervisedFrontendV1 := do
  let receipt ← mkDarwinFrontendSupervisorReceiptV1
    effective request observations event result cleanup
  pure ⟨receipt, response⟩

private def bindResponseToRequest
    (request : FrontendRequestV1)
    (response : FrontendResponseV1) : Except String FrontendResponseV1 := do
  match response with
  | .success success =>
      let bound ← bindFrontendSuccessV1 request success
      let _ ← reconstructFrontendSuccessV1 request bound
      pure (.success bound)
  | .failure failure =>
      pure (.failure (← bindFrontendFailureV1 request failure))

private def mintFromOutcome
    (effective : ResourceProfileV1)
    (request : FrontendRequestV1)
    (prior : DarwinFrontendPublicObservationsV1)
    (outcome : DarwinWorkerSupervisorOutcomeV1) :
    Except String SupervisedFrontendV1 :=
  let observations := maxPhaseObservations prior
    (DarwinWorkerSupervisorOutcomeV1.observations outcome)
  let cleanup := DarwinWorkerSupervisorOutcomeV1.cleanup outcome
  match DarwinWorkerSupervisorOutcomeV1.event outcome with
  | .responseCandidate =>
      if cleanup == .incomplete then
        mintReceipt effective (some request) observations .supervisorFault
          .noResponse cleanup none
      else
        let decoded := do
          let response ← decodeFrontendResponseV1
            (DarwinWorkerSupervisorOutcomeV1.responseBytes outcome)
          bindResponseToRequest request response
        match decoded with
        | .ok response =>
            let result :=
              match response with
              | .success _ => DarwinFrontendSupervisorResultV1.responseOk
              | .failure _ => DarwinFrontendSupervisorResultV1.responseError
            mintReceipt effective (some request) observations .responseAccepted
              result cleanup (some response)
        | .error _ =>
            mintReceipt effective (some request) observations
              .workerExitObserved .noResponse cleanup none
  | .processLimit =>
      mintReceipt effective (some request) observations .processLimitObserved
        .noResponse cleanup none
  | .memoryLimit =>
      mintReceipt effective (some request) observations .memoryLimitObserved
        .noResponse cleanup none
  | .outputLimit =>
      mintReceipt effective (some request) observations .outputLimitObserved
        .noResponse cleanup none
  | .deadline =>
      mintReceipt effective (some request) observations .deadlineObserved
        .noResponse cleanup none
  | .workerExit =>
      mintReceipt effective (some request) observations .workerExitObserved
        .noResponse cleanup none
  | .workerSignal =>
      mintReceipt effective (some request) observations .workerSignalObserved
        .noResponse cleanup none
  | .supervisorFault =>
      mintReceipt effective (some request) observations .supervisorFault
        .noResponse cleanup none

/-- Open-phase non-response transport events (pre-request). -/
private def mintOpenTransportEvent
    (effective : ResourceProfileV1)
    (outcome : DarwinWorkerSupervisorOutcomeV1) :
    Except String SupervisedFrontendV1 :=
  let observations := DarwinWorkerSupervisorOutcomeV1.observations outcome
  let cleanup := DarwinWorkerSupervisorOutcomeV1.cleanup outcome
  match DarwinWorkerSupervisorOutcomeV1.event outcome with
  | .deadline =>
      mintReceipt effective none observations .deadlineObserved .noResponse
        cleanup none
  | .processLimit =>
      mintReceipt effective none observations .processLimitObserved .noResponse
        cleanup none
  | .memoryLimit =>
      mintReceipt effective none observations .memoryLimitObserved .noResponse
        cleanup none
  | .outputLimit =>
      mintReceipt effective none observations .outputLimitObserved .noResponse
        cleanup none
  | .workerExit =>
      mintReceipt effective none observations .workerExitObserved .noResponse
        cleanup none
  | .workerSignal =>
      mintReceipt effective none observations .workerSignalObserved .noResponse
        cleanup none
  | .supervisorFault | .responseCandidate =>
      -- Only a native supervisor fault or a response candidate that fails the
      -- safe-open protocol may become supervisorFault. Exit/signal retain their
      -- closed transport attribution and never mint sourceOpenFailed.
      mintReceipt effective none observations .supervisorFault .noResponse
        cleanup none

/-- Overall monotonic elapsed since `startMs` (Nat millis from IO.monoMsNow). -/
private def elapsedSince (startMs : Nat) : IO UInt64 := do
  let now ← IO.monoMsNow
  let delta := if now ≥ startMs then now - startMs else 0
  if delta ≥ UInt64.size then
    pure (UInt64.ofNat (UInt64.size - 1))
  else
    pure (UInt64.ofNat delta)

/-- Mint deadline without spawning when overall prior already meets the wall. -/
private def mintDeadlineAtWall
    (effective : ResourceProfileV1)
    (request : Option FrontendRequestV1)
    (prior : DarwinFrontendPublicObservationsV1) :
    Except String SupervisedFrontendV1 :=
  mintReceipt effective request (deadlineObservations effective prior)
    .deadlineObserved .noResponse .observedComplete none

private def superviseFrontendRequestWithPriorV1
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1)
    (priorElapsedMillis : UInt64)
    (priorObservations : DarwinFrontendPublicObservationsV1) :
    IO (Except String SupervisedFrontendV1) := do
  match validateLowerOnlyResourceProfile hardFrontendProfile effective with
  | .error detail => return .error detail
  | .ok () => pure ()
  if priorElapsedMillis == UInt64.ofNat (UInt64.size - 1) ||
      priorElapsedMillis ≥ effective.maxWallMillis then
    return .error "prior elapsed meets or exceeds effective wall budget"
  let input ←
    match encodeFrontendRequestV1 request with
    | .error detail => return .error detail
    | .ok bytes => pure bytes
  if input.size > effective.maxProtocolBytes.toNat then
    return .error "frontend request exceeds effective maxProtocolBytes"
  match ← superviseDarwinWorkerFrameV1 workerPath input effective
      priorElapsedMillis with
  | .error .unsupportedPlatform =>
      return .error DarwinWorkerSupervisorFaultV1.unsupportedPlatform.wire
  | .error _ =>
      pure (mintNativeFaultSupervised effective request priorObservations)
  | .ok outcome =>
      pure (mintFromOutcome effective request priorObservations outcome)

/-- Supervise one already-built frontend request (B11b1).

    Optional `priorElapsedMillis` is wall already consumed under a shared
    overall budget. Callers that observe prior ≥ wall must mint deadline
    themselves; this entry also rejects prior ≥ wall / UINT64_MAX. -/
def superviseFrontendRequestV1
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1)
    (priorElapsedMillis : UInt64 := 0) :
    IO (Except String SupervisedFrontendV1) :=
  superviseFrontendRequestWithPriorV1 workerPath request effective
    priorElapsedMillis
    { zeroObservations with elapsedMillis := priorElapsedMillis }

/-- B11b2: supervised safe-open helper then frontend worker under one wall.

    `safeOpenWorkerPath` and `frontendWorkerPath` are pinned executable paths
    resolved by the caller (never ambient PATH lookup inside this module). -/
def superviseFrontendSourceV1
    (safeOpenWorkerPath : FilePath)
    (frontendWorkerPath : FilePath)
    (projectRoot : FilePath)
    (languageVersion : SemVer)
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String)
    (effective : ResourceProfileV1) :
    IO (Except String SupervisedFrontendV1) := do
  match validateLowerOnlyResourceProfile hardFrontendProfile effective with
  | .error detail => return .error detail
  | .ok () => pure ()

  -- Overall monotonic budget starts before open request construction.
  let startMs ← IO.monoMsNow

  -- Invalid root/path: deterministic sourceOpenFailed without spawn.
  let openReq ←
    match mkSafeOpenWorkerRequestV1 projectRoot sourcePath with
    | .error _ =>
        return (mintReceipt effective none zeroObservations .sourceOpenFailed
          .noResponse .observedComplete none)
    | .ok req => pure req
  let openInput ←
    match encodeSafeOpenWorkerRequestV1 openReq with
    | .error _ =>
        return (mintReceipt effective none zeroObservations .supervisorFault
          .noResponse .observedComplete none)
    | .ok bytes => pure bytes
  if openInput.size > effective.maxProtocolBytes.toNat then
    return .error "safe-open request exceeds effective maxProtocolBytes"

  -- Prior for open phase (usually ~0; includes any pre-spawn parent work).
  let priorOpen ← elapsedSince startMs
  if priorOpen ≥ effective.maxWallMillis then
    return (mintDeadlineAtWall effective none zeroObservations)

  let openOutcome ←
    match ← superviseDarwinWorkerFrameV1 safeOpenWorkerPath openInput effective
        priorOpen with
    | .error .unsupportedPlatform =>
        return .error DarwinWorkerSupervisorFaultV1.unsupportedPlatform.wire
    | .error _ =>
        return (mintReceipt effective none zeroObservations .supervisorFault
          .noResponse .incomplete none)
    | .ok outcome => pure outcome

  -- Incomplete cleanup never accepts open response bytes.
  if DarwinWorkerSupervisorOutcomeV1.cleanup openOutcome == .incomplete then
    return (mintReceipt effective none
      (DarwinWorkerSupervisorOutcomeV1.observations openOutcome)
      .supervisorFault .noResponse .incomplete none)

  match DarwinWorkerSupervisorOutcomeV1.event openOutcome with
  | .responseCandidate => pure ()
  | _ =>
      return (mintOpenTransportEvent effective openOutcome)

  -- Complete response candidate: require canonical SafeOpen Ok/Err.
  let openObservations := DarwinWorkerSupervisorOutcomeV1.observations openOutcome
  let responseBytes := DarwinWorkerSupervisorOutcomeV1.responseBytes openOutcome
  let openResponse ←
    match decodeSafeOpenWorkerResponseV1 responseBytes with
    | .error _ =>
        -- Malformed opener response: pre-request supervisor/protocol fail closed.
        return (mintReceipt effective none
          (DarwinWorkerSupervisorOutcomeV1.observations openOutcome)
          .supervisorFault .noResponse
          (DarwinWorkerSupervisorOutcomeV1.cleanup openOutcome) none)
    | .ok r => pure r

  match openResponse with
  | .failure _failure =>
      -- Canonical closed SafeOpenFault + complete cleanup → sourceOpenFailed.
      pure (mintReceipt effective none
        (DarwinWorkerSupervisorOutcomeV1.observations openOutcome)
        .sourceOpenFailed .noResponse
        (DarwinWorkerSupervisorOutcomeV1.cleanup openOutcome) none)
  | .success success =>
      -- Build Frontend.Req.v1 from snapshot (parent CPU; counts against wall).
      let request ←
        match mkFrontendRequestV1 languageVersion sourcePath moduleSelector
            programSelector (SafeOpenWorkerSuccessV1.bytes success) with
        | .error _ =>
            return (mintReceipt effective none
              (DarwinWorkerSupervisorOutcomeV1.observations openOutcome)
              .supervisorFault .noResponse .observedComplete none)
        | .ok req => pure req

      -- Recompute total prior from overall start (open + gap + construct).
      let priorWorker ← elapsedSince startMs
      let priorObservations :=
        { openObservations with elapsedMillis := priorWorker }
      if priorWorker ≥ effective.maxWallMillis then
        -- Request exists → digest some; retain open peaks and never spawn worker.
        return (mintDeadlineAtWall effective (some request) priorObservations)

      match ← superviseFrontendRequestWithPriorV1 frontendWorkerPath request
          effective priorWorker priorObservations with
      | .error e => return .error e
      | .ok supervised => pure (.ok supervised)

end ProofForgeV2.Frontend.DarwinSupervisorV1
