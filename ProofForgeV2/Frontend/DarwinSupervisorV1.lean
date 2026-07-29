/-
  ProofForgeV2.Frontend.DarwinSupervisorV1 — B11b Darwin frontend composer.

  Layers the transport-only `DarwinWorkerSupervisorV1` primitive under the pure
  `DarwinFrontendSupervisorReceiptV1` model and the frontend request/response
  protocol. Sole public entry encodes a canonical Frontend.Req.v1, supervises
  the worker, and mints a private-ctor supervised result with a receipt.

  Explicit non-claims:
  * assurance remains `darwin-development-observed` — not process/session
    containment and not formal TST-RESOURCE-001 / TASK-D1-08 completion
  * does not import WorkerV1 or SafeOpen; does not open sources, publish CLI
    envelopes, or retain stderr/path/PID/host-private detail
-/
import ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
import ProofForgeV2.Frontend.ProtocolV1

namespace ProofForgeV2.Frontend.DarwinSupervisorV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
open ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
open ProofForgeV2.Frontend.ProtocolV1
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

/-- Native closed-fault path: supervisorFault + noResponse + incomplete cleanup,
    request digest present, observations zeroed. No host-private detail. -/
private def mintNativeFaultSupervised
    (effective : ResourceProfileV1)
    (request : FrontendRequestV1) :
    Except String SupervisedFrontendV1 := do
  let receipt ← mkDarwinFrontendSupervisorReceiptV1
    effective
    (some request)
    zeroObservations
    .supervisorFault
    .noResponse
    .incomplete
  pure ⟨receipt, none⟩

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

private def mintReceipt
    (effective : ResourceProfileV1)
    (request : FrontendRequestV1)
    (observations : DarwinFrontendPublicObservationsV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1)
    (response : Option FrontendResponseV1) :
    Except String SupervisedFrontendV1 := do
  let receipt ← mkDarwinFrontendSupervisorReceiptV1
    effective
    (some request)
    observations
    event
    result
    cleanup
  pure ⟨receipt, response⟩

/-- Map a transport outcome into a receipt-backed supervised frontend result.
    Protocol decoding of response candidates is owned only by this composer. -/
private def mintFromOutcome
    (effective : ResourceProfileV1)
    (request : FrontendRequestV1)
    (outcome : DarwinWorkerSupervisorOutcomeV1) :
    Except String SupervisedFrontendV1 :=
  let observations := DarwinWorkerSupervisorOutcomeV1.observations outcome
  let cleanup := DarwinWorkerSupervisorOutcomeV1.cleanup outcome
  match DarwinWorkerSupervisorOutcomeV1.event outcome with
  | .responseCandidate =>
      if cleanup == .incomplete then
        -- A response is not accepted while the supervised process unit may
        -- still be live. Preserve the closed cleanup fact and withhold bytes.
        mintReceipt effective request observations .supervisorFault .noResponse
          cleanup none
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
            mintReceipt effective request observations .responseAccepted result
              cleanup (some response)
        | .error _ =>
            -- Malformed, cross-request, or request-inconsistent candidate:
            -- transport retained bytes; composer records worker-exit/no-response
            -- without exposing partial protocol state.
            mintReceipt effective request observations .workerExitObserved .noResponse
              cleanup none
  | .processLimit =>
      mintReceipt effective request observations .processLimitObserved .noResponse
        cleanup none
  | .memoryLimit =>
      mintReceipt effective request observations .memoryLimitObserved .noResponse
        cleanup none
  | .outputLimit =>
      mintReceipt effective request observations .outputLimitObserved .noResponse
        cleanup none
  | .deadline =>
      mintReceipt effective request observations .deadlineObserved .noResponse
        cleanup none
  | .workerExit =>
      mintReceipt effective request observations .workerExitObserved .noResponse
        cleanup none
  | .workerSignal =>
      mintReceipt effective request observations .workerSignalObserved .noResponse
        cleanup none
  | .supervisorFault =>
      mintReceipt effective request observations .supervisorFault .noResponse
        cleanup none

/-- Supervise one frontend request under a lower-only effective profile.

    Flow: lower-only validate → encode canonical Frontend.Req.v1 → native
    primitive → receipt mint. `unsupportedPlatform` is a String error; every
    other closed native fault mints supervisorFault/noResponse/incomplete with
    the request digest and zero observations. Response candidates are decoded
    only here; legal success/failure become responseAccepted + responseOk/Error,
    malformed candidates become workerExitObserved + noResponse.

    Assurance is development-observed only — not containment or formal evidence. -/
def superviseFrontendRequestV1
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1) :
    IO (Except String SupervisedFrontendV1) := do
  match validateLowerOnlyResourceProfile hardFrontendProfile effective with
  | .error detail => return .error detail
  | .ok () => pure ()
  let input ←
    match encodeFrontendRequestV1 request with
    | .error detail => return .error detail
    | .ok bytes => pure bytes
  if input.size > effective.maxProtocolBytes.toNat then
    return .error "frontend request exceeds effective maxProtocolBytes"
  match ← superviseDarwinWorkerFrameV1 workerPath input effective with
  | .error .unsupportedPlatform =>
      return .error DarwinWorkerSupervisorFaultV1.unsupportedPlatform.wire
  | .error _ =>
      pure (mintNativeFaultSupervised effective request)
  | .ok outcome =>
      pure (mintFromOutcome effective request outcome)

end ProofForgeV2.Frontend.DarwinSupervisorV1
