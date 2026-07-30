/-
  ProofForgeV2.Frontend.DarwinWorkerSupervisorV1 — B11b Darwin worker
  supervisor execution primitive.

  Spawns a single worker executable under a lower-only frontend ResourceProfile,
  observes wall/memory/process/output limits, and returns a closed event outcome
  plus an optional response-candidate byte payload. The native side produces a
  fixed binary observation frame; this module is the sole Lean decoder and
  private-ctor mint for that frame.

  B12 hardens each spawn with an fd-derived, bounded private worker snapshot:
  source and snapshot metadata are rechecked, Darwin starts the image suspended,
  vnode mutations fail closed, and only the verified snapshot is resumed.

  Explicit non-claims:
  * `darwin-development-observed` only — not process/session containment
  * not formal TST-RESOURCE-001 / TASK-D1-08 completion
  * not Linux `contained` assurance or formal executable identity
  * no stderr/path/PID retention; ambient Lean import closure remains engineering
  * B11b2 composes safe-open under one private native monotonic budget
    capability via `superviseFrontendSourceV1`; B12 consumes that composition,
    while this primitive remains transport-only for already-encoded frames.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Frontend.DarwinSupervisorReceiptV1

namespace ProofForgeV2.Frontend.DarwinWorkerSupervisorV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
open System

/-- Closed native/Lean fault class for the Darwin worker supervisor primitive. -/
inductive DarwinWorkerSupervisorFaultV1 where
  | unsupportedPlatform
  | invalidArgument
  | spawnFailed
  | io
  | nativeProtocol
  deriving DecidableEq, Repr

namespace DarwinWorkerSupervisorFaultV1

def wire : DarwinWorkerSupervisorFaultV1 → String
  | .unsupportedPlatform => "unsupported-platform"
  | .invalidArgument => "invalid-argument"
  | .spawnFailed => "spawn-failed"
  | .io => "io"
  | .nativeProtocol => "native-protocol"

def ofWire? : String → Option DarwinWorkerSupervisorFaultV1
  | "unsupported-platform" => some .unsupportedPlatform
  | "invalid-argument" => some .invalidArgument
  | "spawn-failed" => some .spawnFailed
  | "io" => some .io
  | "native-protocol" => some .nativeProtocol
  | _ => none

end DarwinWorkerSupervisorFaultV1

/-- Closed observation events. Controllers (process/memory/output/deadline) are
    mutually exclusive with responseCandidate; labels are not containment claims. -/
inductive DarwinWorkerSupervisorEventV1 where
  | responseCandidate
  | processLimit
  | memoryLimit
  | outputLimit
  | deadline
  | workerExit
  | workerSignal
  | supervisorFault
  deriving DecidableEq, Repr

/-- Private-ctor outcome of one supervised worker frame. Partial stdout is never
    retained except as an exact response-candidate payload under that event. -/
structure DarwinWorkerSupervisorOutcomeV1 where
  private mk ::
  private event_ : DarwinWorkerSupervisorEventV1
  private cleanup_ : DarwinFrontendCleanupResultV1
  private observations_ : DarwinFrontendPublicObservationsV1
  private responseBytes_ : ByteArray

namespace DarwinWorkerSupervisorOutcomeV1

def event (o : DarwinWorkerSupervisorOutcomeV1) : DarwinWorkerSupervisorEventV1 :=
  o.event_

def cleanup (o : DarwinWorkerSupervisorOutcomeV1) : DarwinFrontendCleanupResultV1 :=
  o.cleanup_

def observations (o : DarwinWorkerSupervisorOutcomeV1) :
    DarwinFrontendPublicObservationsV1 :=
  o.observations_

def responseBytes (o : DarwinWorkerSupervisorOutcomeV1) : ByteArray :=
  o.responseBytes_

end DarwinWorkerSupervisorOutcomeV1

/-- Private capability minted from the native CLOCK_MONOTONIC domain. Reusing
    one value across stages gives them an exact absolute wall origin. -/
structure DarwinFrontendBudgetV1 where
  private mk ::
  private startedAtMillis_ : UInt64

@[extern "proof_forge_start_frontend_budget_v1"]
private opaque nativeStartFrontendBudgetV1 : IO (Except String ByteArray)

/-- Native Darwin supervisor: worker path, full stdin frame, five effective caps,
    plus the absolute native monotonic start carried by a private capability.
    Native open is the sole worker-byte snapshot authority; the caller pathname
    is never passed directly to `posix_spawn`. Returns either a closed wire fault
    label or a `PFSUPV1\0` observation frame. -/
@[extern "proof_forge_supervise_worker_v1"]
private opaque nativeSuperviseWorkerV1
    (workerPath : @& String)
    (input : @& ByteArray)
    (maxWallMillis maxAggregateMemoryBytes : UInt64)
    (maxProcesses : UInt32)
    (maxProtocolBytes maxStderrBytes budgetStartMillis : UInt64) :
    IO (Except String ByteArray)

private def containsNul (value : String) : Bool :=
  value.toList.any (· == '\x00')

/-- Exact 8-byte magic: `PFSUPV1` + NUL. -/
private def supervisorFrameMagicV1 : ByteArray :=
  let base := "PFSUPV1".toUTF8
  base.push 0

private def frameHeaderBytesV1 : Nat := 36

private def readU8
    (bytes : ByteArray) (offset : Nat) :
    Except DarwinWorkerSupervisorFaultV1 UInt8 := do
  unless offset < bytes.size do
    throw .nativeProtocol
  pure (bytes.get! offset)

private def readU32le
    (bytes : ByteArray) (offset : Nat) :
    Except DarwinWorkerSupervisorFaultV1 UInt32 := do
  let b0 ← readU8 bytes offset
  let b1 ← readU8 bytes (offset + 1)
  let b2 ← readU8 bytes (offset + 2)
  let b3 ← readU8 bytes (offset + 3)
  let v :=
    b0.toNat + b1.toNat * 256 + b2.toNat * 65536 + b3.toNat * 16777216
  pure (UInt32.ofNat v)

private def readU64le
    (bytes : ByteArray) (offset : Nat) :
    Except DarwinWorkerSupervisorFaultV1 UInt64 := do
  let b0 ← readU8 bytes offset
  let b1 ← readU8 bytes (offset + 1)
  let b2 ← readU8 bytes (offset + 2)
  let b3 ← readU8 bytes (offset + 3)
  let b4 ← readU8 bytes (offset + 4)
  let b5 ← readU8 bytes (offset + 5)
  let b6 ← readU8 bytes (offset + 6)
  let b7 ← readU8 bytes (offset + 7)
  let mut v : Nat := 0
  let mut place : Nat := 1
  for b in #[b0, b1, b2, b3, b4, b5, b6, b7] do
    v := v + b.toNat * place
    place := place * 256
  -- 8-byte LE always fits UInt64; reject if Nat construction exceeded (defensive).
  unless v < UInt64.size do
    throw .nativeProtocol
  pure (UInt64.ofNat v)

private def eventOfByte
    (b : UInt8) : Except DarwinWorkerSupervisorFaultV1 DarwinWorkerSupervisorEventV1 :=
  match b.toNat with
  | 0 => pure .responseCandidate
  | 1 => pure .processLimit
  | 2 => pure .memoryLimit
  | 3 => pure .outputLimit
  | 4 => pure .deadline
  | 5 => pure .workerExit
  | 6 => pure .workerSignal
  | 7 => pure .supervisorFault
  | _ => throw .nativeProtocol

private def cleanupOfByte
    (b : UInt8) : Except DarwinWorkerSupervisorFaultV1 DarwinFrontendCleanupResultV1 :=
  match b.toNat with
  | 0 => pure .observedComplete
  | 1 => pure .incomplete
  | _ => throw .nativeProtocol

private def validateWithinEffective
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) :
    Except DarwinWorkerSupervisorFaultV1 Unit := do
  unless observations.elapsedMillis ≤ effective.maxWallMillis do
    throw .nativeProtocol
  unless observations.peakAggregateMemoryBytes ≤ effective.maxAggregateMemoryBytes do
    throw .nativeProtocol
  unless observations.peakProcesses ≤ effective.maxProcesses do
    throw .nativeProtocol

/-- Deadline: elapsed must be exact limit+1 (no Nat/UInt wrap theater); others ≤. -/
private def validateDeadlineObservations
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) :
    Except DarwinWorkerSupervisorFaultV1 Unit := do
  -- Reject unrepresentable limit+1 (UInt64 saturation would be non-canonical).
  unless effective.maxWallMillis.toNat + 1 < UInt64.size do
    throw .nativeProtocol
  unless observations.elapsedMillis.toNat = effective.maxWallMillis.toNat + 1 do
    throw .nativeProtocol
  unless observations.peakAggregateMemoryBytes ≤ effective.maxAggregateMemoryBytes do
    throw .nativeProtocol
  unless observations.peakProcesses ≤ effective.maxProcesses do
    throw .nativeProtocol

private def validateMemoryLimitObservations
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) :
    Except DarwinWorkerSupervisorFaultV1 Unit := do
  unless effective.maxAggregateMemoryBytes.toNat + 1 < UInt64.size do
    throw .nativeProtocol
  unless observations.peakAggregateMemoryBytes.toNat =
      effective.maxAggregateMemoryBytes.toNat + 1 do
    throw .nativeProtocol
  unless observations.elapsedMillis ≤ effective.maxWallMillis do
    throw .nativeProtocol
  unless observations.peakProcesses ≤ effective.maxProcesses do
    throw .nativeProtocol

private def validateProcessLimitObservations
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) :
    Except DarwinWorkerSupervisorFaultV1 Unit := do
  unless effective.maxProcesses.toNat + 1 < UInt32.size do
    throw .nativeProtocol
  unless observations.peakProcesses.toNat = effective.maxProcesses.toNat + 1 do
    throw .nativeProtocol
  unless observations.elapsedMillis ≤ effective.maxWallMillis do
    throw .nativeProtocol
  unless observations.peakAggregateMemoryBytes ≤ effective.maxAggregateMemoryBytes do
    throw .nativeProtocol

private def validateObservationsForEvent
    (event : DarwinWorkerSupervisorEventV1)
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) :
    Except DarwinWorkerSupervisorFaultV1 Unit :=
  match event with
  | .deadline => validateDeadlineObservations observations effective
  | .memoryLimit => validateMemoryLimitObservations observations effective
  | .processLimit => validateProcessLimitObservations observations effective
  | .responseCandidate | .outputLimit | .workerExit | .workerSignal
    | .supervisorFault =>
      validateWithinEffective observations effective

/-- Decode and re-validate a native `PFSUPV1\0` observation frame. -/
private def decodeSupervisorFrameV1
    (frame : ByteArray)
    (effective : ResourceProfileV1) :
    Except DarwinWorkerSupervisorFaultV1 DarwinWorkerSupervisorOutcomeV1 := do
  unless frame.size ≥ frameHeaderBytesV1 do
    throw .nativeProtocol
  let magic := frame.extract 0 8
  unless magic == supervisorFrameMagicV1 do
    throw .nativeProtocol
  let eventByte ← readU8 frame 8
  let cleanupByte ← readU8 frame 9
  let reserved0 ← readU8 frame 10
  let reserved1 ← readU8 frame 11
  unless reserved0 == 0 && reserved1 == 0 do
    throw .nativeProtocol
  let elapsedMillis ← readU64le frame 12
  let peakAggregateMemoryBytes ← readU64le frame 20
  let peakProcesses ← readU32le frame 28
  let payloadLenU ← readU32le frame 32
  let payloadLen := payloadLenU.toNat
  unless frame.size = frameHeaderBytesV1 + payloadLen do
    throw .nativeProtocol
  let event ← eventOfByte eventByte
  let cleanup ← cleanupOfByte cleanupByte
  let payload :=
    if payloadLen == 0 then ByteArray.empty
    else frame.extract frameHeaderBytesV1 frame.size
  -- Only responseCandidate may carry a payload; all others must be empty.
  match event with
  | .responseCandidate =>
      unless payloadLen ≤ effective.maxProtocolBytes.toNat do
        throw .nativeProtocol
  | _ =>
      unless payloadLen == 0 do
        throw .nativeProtocol
  let observations : DarwinFrontendPublicObservationsV1 :=
    { elapsedMillis, peakAggregateMemoryBytes, peakProcesses }
  validateObservationsForEvent event observations effective
  pure {
    event_ := event
    cleanup_ := cleanup
    observations_ := observations
    responseBytes_ :=
      match event with
      | .responseCandidate => payload
      | _ => ByteArray.empty
  }

private def faultFromNativeLabel (label : String) : DarwinWorkerSupervisorFaultV1 :=
  match DarwinWorkerSupervisorFaultV1.ofWire? label with
  | some fault => fault
  | none => .nativeProtocol

/-- Mint one private Darwin native monotonic wall origin. -/
def startDarwinFrontendBudgetV1 :
    IO (Except DarwinWorkerSupervisorFaultV1 DarwinFrontendBudgetV1) := do
  match ← nativeStartFrontendBudgetV1 with
  | .error label => pure (.error (faultFromNativeLabel label))
  | .ok frame =>
      if frame.size != 8 then
        pure (.error .nativeProtocol)
      else
        match readU64le frame 0 with
        | .error fault => pure (.error fault)
        | .ok startedAtMillis =>
            if startedAtMillis == UInt64.ofNat (UInt64.size - 1) then
              pure (.error .nativeProtocol)
            else
              pure (.ok ⟨startedAtMillis⟩)

/-- Supervise one encoded frame against an existing native monotonic budget.
    The private capability prevents callers from substituting a smaller elapsed
    value; native checks the absolute start across fd-bound worker snapshot,
    allocation, pipe, suspended spawn, execution, and cleanup. -/
def superviseDarwinWorkerFrameWithBudgetV1
    (workerPath : FilePath)
    (input : ByteArray)
    (effective : ResourceProfileV1)
    (budget : DarwinFrontendBudgetV1) :
    IO (Except DarwinWorkerSupervisorFaultV1 DarwinWorkerSupervisorOutcomeV1) := do
  match validateLowerOnlyResourceProfile hardFrontendProfile effective with
  | .error _ => return .error .invalidArgument
  | .ok () => pure ()
  let pathString := workerPath.toString
  if pathString.isEmpty || containsNul pathString then
    return .error .invalidArgument
  if input.size > effective.maxProtocolBytes.toNat then
    return .error .invalidArgument
  match ← nativeSuperviseWorkerV1
      pathString
      input
      effective.maxWallMillis
      effective.maxAggregateMemoryBytes
      effective.maxProcesses
      effective.maxProtocolBytes
      effective.maxStderrBytes
      budget.startedAtMillis_ with
  | .error label =>
      pure (.error (faultFromNativeLabel label))
  | .ok frame =>
      pure (decodeSupervisorFrameV1 frame effective)

/-- Public fresh-budget Darwin development-observed supervision primitive. -/
def superviseDarwinWorkerFrameV1
    (workerPath : FilePath)
    (input : ByteArray)
    (effective : ResourceProfileV1) :
    IO (Except DarwinWorkerSupervisorFaultV1 DarwinWorkerSupervisorOutcomeV1) := do
  match ← startDarwinFrontendBudgetV1 with
  | .error fault => pure (.error fault)
  | .ok budget =>
      superviseDarwinWorkerFrameWithBudgetV1 workerPath input effective budget

end ProofForgeV2.Frontend.DarwinWorkerSupervisorV1
