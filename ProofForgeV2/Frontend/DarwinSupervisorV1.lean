/-
  ProofForgeV2.Frontend.DarwinSupervisorV1 — B11b Darwin frontend composer.

  B11b1: `superviseFrontendRequestV1` encodes Frontend.Req.v1 and supervises the
  B10 frontend worker under a lower-only effective profile.

  B11b2: `superviseFrontendSourceV1` first supervises a pinned safe-open helper
  executable (SafeOpen.Req/Ok/Err.v1) via the same hardened Darwin process-group
  primitive, then (on Ok) constructs Frontend.Req.v1 and supervises the frontend
  worker. A private capability minted from native CLOCK_MONOTONIC carries one
  absolute wall origin across open → parent decode/request construction → worker;
  native checks expiry before each stage allocation/pipe/spawn. SafeOpen Ok/Err
  responses are request-digest bound. B12 routes CLI source authority through the
  success-only product carrier and runs both workers from fd-derived private
  snapshots. No parent-side fork or product test hooks.

  Explicit non-claims:
  * assurance remains `darwin-development-observed`
  * not process/session containment, not formal TST-RESOURCE-001 / TASK-D1-08
  * not Linux `contained`, formal executable identity, or locked import closure
-/
import ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1

namespace ProofForgeV2.Frontend.DarwinSupervisorV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
open ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Frontend.SafeOpenV1
open ProofForgeV2.Frontend.SafeOpenWorkerProtocolV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open System

/-- Private-ctor supervised frontend result. A successful response retains the
    sole reconstructed product input. A canonical pre-request SafeOpen.Err.v1
    retains only its closed fault class so the CLI can preserve source-limit
    diagnostics without reopening or restating filesystem authority. -/
structure SupervisedFrontendV1 where
  private mk ::
  private receipt_ : DarwinFrontendSupervisorReceiptV1
  private response_ : Option FrontendResponseV1
  private productInput_ : Option (ValidatedSourceV1 × OriginInventoryV1)
  private sourceOpenFault_ : Option SafeOpenFaultV1

namespace SupervisedFrontendV1

def receipt (s : SupervisedFrontendV1) : DarwinFrontendSupervisorReceiptV1 :=
  s.receipt_

def response (s : SupervisedFrontendV1) : Option FrontendResponseV1 :=
  s.response_

/-- Product compiler input reconstructed exactly once inside the request-bound
    supervisor success path. Callers must not reopen or reparse source. -/
def productInput (s : SupervisedFrontendV1) :
    Option (ValidatedSourceV1 × OriginInventoryV1) :=
  s.productInput_

/-- Closed source-open fault retained only for a request-bound canonical
    SafeOpen.Err.v1 with complete cleanup. No path or native prose is retained. -/
def sourceOpenFault (s : SupervisedFrontendV1) : Option SafeOpenFaultV1 :=
  s.sourceOpenFault_

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

private def mintNativeFaultSupervised
    (effective : ResourceProfileV1)
    (request : FrontendRequestV1)
    (prior : DarwinFrontendPublicObservationsV1) :
    Except String SupervisedFrontendV1 := do
  let receipt ← mkDarwinFrontendSupervisorReceiptV1
    effective (some request) prior
    .supervisorFault .noResponse .incomplete
  pure ⟨receipt, none, none, none⟩

private def mintReceipt
    (effective : ResourceProfileV1)
    (request : Option FrontendRequestV1)
    (observations : DarwinFrontendPublicObservationsV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1)
    (response : Option FrontendResponseV1)
    (productInput : Option (ValidatedSourceV1 × OriginInventoryV1) := none)
    (sourceOpenFault : Option SafeOpenFaultV1 := none) :
    Except String SupervisedFrontendV1 := do
  match event, result, response, productInput, sourceOpenFault with
  | .sourceOpenFailed, .noResponse, none, none, some _ => pure ()
  | .sourceOpenFailed, _, _, _, _ =>
      throw "source-open failure/fault join is inconsistent"
  | _, .responseOk, some (.success _), some _, none => pure ()
  | _, .responseError, some (.failure _), none, none => pure ()
  | _, .noResponse, none, none, none => pure ()
  | _, _, _, _, _ =>
      throw "supervised frontend response/product/fault join is inconsistent"
  let receipt ← mkDarwinFrontendSupervisorReceiptV1
    effective request observations event result cleanup
  pure ⟨receipt, response, productInput, sourceOpenFault⟩

private def bindResponseToRequest
    (request : FrontendRequestV1)
    (response : FrontendResponseV1) :
    Except String (FrontendResponseV1 ×
      Option (ValidatedSourceV1 × OriginInventoryV1)) := do
  match response with
  | .success success =>
      let bound ← bindFrontendSuccessV1 request success
      let productInput ← reconstructFrontendSuccessV1 request bound
      pure (.success bound, some productInput)
  | .failure failure =>
      pure (.failure (← bindFrontendFailureV1 request failure), none)

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
        | .ok (response, productInput) =>
            let result :=
              match response with
              | .success _ => DarwinFrontendSupervisorResultV1.responseOk
              | .failure _ => DarwinFrontendSupervisorResultV1.responseError
            mintReceipt effective (some request) observations .responseAccepted
              result cleanup (some response) productInput
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

private def superviseFrontendRequestWithBudgetV1
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1)
    (budget : DarwinFrontendBudgetV1)
    (priorObservations : DarwinFrontendPublicObservationsV1) :
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
  match ← superviseDarwinWorkerFrameWithBudgetV1 workerPath input effective budget with
  | .error .unsupportedPlatform =>
      return .error DarwinWorkerSupervisorFaultV1.unsupportedPlatform.wire
  | .error _ =>
      pure (mintNativeFaultSupervised effective request priorObservations)
  | .ok outcome =>
      pure (mintFromOutcome effective request priorObservations outcome)

/-- Supervise one already-built frontend request (B11b1) under a freshly minted
    native monotonic budget that starts before canonical request encoding. -/
def superviseFrontendRequestV1
    (workerPath : FilePath)
    (request : FrontendRequestV1)
    (effective : ResourceProfileV1) :
    IO (Except String SupervisedFrontendV1) := do
  match ← startDarwinFrontendBudgetV1 with
  | .error .unsupportedPlatform =>
      return .error DarwinWorkerSupervisorFaultV1.unsupportedPlatform.wire
  | .error _ => pure (mintNativeFaultSupervised effective request zeroObservations)
  | .ok budget =>
      superviseFrontendRequestWithBudgetV1 workerPath request effective budget
        zeroObservations

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

  -- One private CLOCK_MONOTONIC origin covers request construction, both child
  -- stages, and the Lean/FFI seams between them.
  let budget ← match ← startDarwinFrontendBudgetV1 with
    | .error .unsupportedPlatform =>
        return .error DarwinWorkerSupervisorFaultV1.unsupportedPlatform.wire
    | .error _ =>
        return (mintReceipt effective none zeroObservations .supervisorFault
          .noResponse .incomplete none)
    | .ok budget => pure budget

  -- Invalid trusted-root metadata is a caller argument fault, not an observed
  -- source-open failure. In particular, it must not mint sourceOpenFailed
  -- without a canonical SafeOpen.Err.v1 produced by the supervised child.
  let openReq ←
    match mkSafeOpenWorkerRequestV1 projectRoot sourcePath with
    | .error detail => return .error detail
    | .ok req => pure req
  let openInput ←
    match encodeSafeOpenWorkerRequestV1 openReq with
    | .error _ =>
        return (mintReceipt effective none zeroObservations .supervisorFault
          .noResponse .observedComplete none)
    | .ok bytes => pure bytes
  if openInput.size > effective.maxProtocolBytes.toNat then
    return .error "safe-open request exceeds effective maxProtocolBytes"

  let openOutcome ←
    match ← superviseDarwinWorkerFrameWithBudgetV1 safeOpenWorkerPath openInput
        effective budget with
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
  let openResponse ←
    match bindSafeOpenWorkerResponseV1 openReq openResponse with
    | .error _ =>
        -- A canonical response for another SafeOpen.Req.v1 is still a replay,
        -- never sourceOpenFailed and never a source snapshot authority.
        return (mintReceipt effective none
          (DarwinWorkerSupervisorOutcomeV1.observations openOutcome)
          .supervisorFault .noResponse
          (DarwinWorkerSupervisorOutcomeV1.cleanup openOutcome) none)
    | .ok r => pure r

  match openResponse with
  | .failure failure =>
      -- Canonical closed SafeOpenFault + complete cleanup → sourceOpenFailed.
      -- Retain the closed class (never a path/errno string) so the product CLI
      -- can preserve the specified 16 MiB diagnostic without reopening source.
      pure (mintReceipt effective none
        (DarwinWorkerSupervisorOutcomeV1.observations openOutcome)
        .sourceOpenFailed .noResponse
        (DarwinWorkerSupervisorOutcomeV1.cleanup openOutcome) none
        (sourceOpenFault := some (SafeOpenWorkerFailureV1.fault failure)))
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

      -- The same private absolute budget reaches native after request encoding;
      -- an exhausted budget yields deadline before worker allocation/spawn.
      match ← superviseFrontendRequestWithBudgetV1 frontendWorkerPath request
          effective budget openObservations with
      | .error e => return .error e
      | .ok supervised => pure (.ok supervised)

end ProofForgeV2.Frontend.DarwinSupervisorV1
