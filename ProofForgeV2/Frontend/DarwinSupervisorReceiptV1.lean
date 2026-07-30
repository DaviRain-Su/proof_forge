/-
  ProofForgeV2.Frontend.DarwinSupervisorReceiptV1 — B11a2 legacy-named
  Darwin/Linux development-observation receipt model.

  This module freezes a bounded, canonical, public-safe internal receipt
  projection for a future Darwin frontend supervisor. It is not the final CLI
  `receipts` envelope and is deliberately inert: it does not
  open files, spawn/measure/kill/reap processes, read stream tails, emit CLI
  JSON, or claim process/session containment. Assurance is host-specific
  development observation, never formal/hermetic
  evidence or a containment claim.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Frontend.ProtocolV1

namespace ProofForgeV2.Frontend.DarwinSupervisorReceiptV1

open ProofForgeV2.Core.Common
open ProofForgeV2.Frontend.ProtocolV1

private def hardFrontendProfile : ResourceProfileV1 :=
  hardFrontendProfileForHost

/-- Closed assurance class for supported development-only supervisor hosts. -/
inductive DarwinFrontendAssuranceV1 where
  | darwinDevelopmentObserved
  | linuxDevelopmentObserved
  deriving DecidableEq, Repr

namespace DarwinFrontendAssuranceV1

def wire : DarwinFrontendAssuranceV1 → String
  | .darwinDevelopmentObserved => "darwin-development-observed"
  | .linuxDevelopmentObserved => "linux-development-observed"

def ofWire? : String → Option DarwinFrontendAssuranceV1
  | "darwin-development-observed" => some .darwinDevelopmentObserved
  | "linux-development-observed" => some .linuxDevelopmentObserved
  | _ => none

end DarwinFrontendAssuranceV1

private def compiledHostAssuranceV1 : Option DarwinFrontendAssuranceV1 :=
  if System.Platform.isOSX then some .darwinDevelopmentObserved
  else if (System.Platform.target.splitOn "-").contains "linux" then
    some .linuxDevelopmentObserved
  else none

/-- Closed event classes observable by the future Darwin supervisor. These are
    observation labels, not claims of kernel-backed resource containment. -/
inductive DarwinFrontendSupervisorEventV1 where
  | responseAccepted
  | sourceOpenFailed
  | processLimitObserved
  | memoryLimitObserved
  | outputLimitObserved
  | deadlineObserved
  | workerExitObserved
  | workerSignalObserved
  | supervisorFault
  deriving DecidableEq, Repr

namespace DarwinFrontendSupervisorEventV1

def wire : DarwinFrontendSupervisorEventV1 → String
  | .responseAccepted => "response-accepted"
  | .sourceOpenFailed => "source-open-failed"
  | .processLimitObserved => "process-limit-observed"
  | .memoryLimitObserved => "memory-limit-observed"
  | .outputLimitObserved => "output-limit-observed"
  | .deadlineObserved => "deadline-observed"
  | .workerExitObserved => "worker-exit-observed"
  | .workerSignalObserved => "worker-signal-observed"
  | .supervisorFault => "supervisor-fault"

def ofWire? : String → Option DarwinFrontendSupervisorEventV1
  | "response-accepted" => some .responseAccepted
  | "source-open-failed" => some .sourceOpenFailed
  | "process-limit-observed" => some .processLimitObserved
  | "memory-limit-observed" => some .memoryLimitObserved
  | "output-limit-observed" => some .outputLimitObserved
  | "deadline-observed" => some .deadlineObserved
  | "worker-exit-observed" => some .workerExitObserved
  | "worker-signal-observed" => some .workerSignalObserved
  | "supervisor-fault" => some .supervisorFault
  | _ => none

end DarwinFrontendSupervisorEventV1

/-- Whether an accepted frontend response was success, a diagnostic failure, or
    absent. This does not duplicate the response frame itself. -/
inductive DarwinFrontendSupervisorResultV1 where
  | responseOk
  | responseError
  | noResponse
  deriving DecidableEq, Repr

namespace DarwinFrontendSupervisorResultV1

def wire : DarwinFrontendSupervisorResultV1 → String
  | .responseOk => "response-ok"
  | .responseError => "response-error"
  | .noResponse => "no-response"

def ofWire? : String → Option DarwinFrontendSupervisorResultV1
  | "response-ok" => some .responseOk
  | "response-error" => some .responseError
  | "no-response" => some .noResponse
  | _ => none

end DarwinFrontendSupervisorResultV1

/-- Public cleanup observation. `observedComplete` is not a containment claim. -/
inductive DarwinFrontendCleanupResultV1 where
  | observedComplete
  | incomplete
  deriving DecidableEq, Repr

namespace DarwinFrontendCleanupResultV1

def wire : DarwinFrontendCleanupResultV1 → String
  | .observedComplete => "observed-complete"
  | .incomplete => "incomplete"

def ofWire? : String → Option DarwinFrontendCleanupResultV1
  | "observed-complete" => some .observedComplete
  | "incomplete" => some .incomplete
  | _ => none

end DarwinFrontendCleanupResultV1

/-- Bounded public observations only. No PID, signal, exit code, path, stderr,
    tail, or host-private detail is represented by this type. -/
structure DarwinFrontendPublicObservationsV1 where
  elapsedMillis : UInt64
  peakAggregateMemoryBytes : UInt64
  peakProcesses : UInt32
  deriving DecidableEq, Repr

/-- Closed schema/domain for the pure receipt projection. -/
def darwinFrontendSupervisorReceiptSchemaV1 : SchemaId :=
  { value := "proof-forge.frontend-darwin-supervisor-receipt.v1" }

/-- Parse allocation cap. The fixed projection is below 1 KiB today; 4 KiB
    leaves bounded schema headroom without accepting unbounded PF-JCS input. -/
def maxDarwinFrontendSupervisorReceiptJcsBytesV1 : Nat := 4096

/-- Smart-constructor-only receipt. Digests are retained explicitly so parsing
    can verify every identity before reconstituting the carrier. -/
structure DarwinFrontendSupervisorReceiptV1 where
  private mk ::
  private assurance_ : DarwinFrontendAssuranceV1
  private hardProfileId_ : SchemaId
  private hardProfileDigest_ : Digest
  private effectiveProfile_ : ResourceProfileV1
  private effectiveProfileDigest_ : Digest
  private requestDigest_ : Option Digest
  private observations_ : DarwinFrontendPublicObservationsV1
  private event_ : DarwinFrontendSupervisorEventV1
  private result_ : DarwinFrontendSupervisorResultV1
  private cleanup_ : DarwinFrontendCleanupResultV1
  deriving DecidableEq, Repr

namespace DarwinFrontendSupervisorReceiptV1

def assurance (r : DarwinFrontendSupervisorReceiptV1) : DarwinFrontendAssuranceV1 :=
  r.assurance_

def hardProfileId (r : DarwinFrontendSupervisorReceiptV1) : SchemaId :=
  r.hardProfileId_

def hardProfileDigest (r : DarwinFrontendSupervisorReceiptV1) : Digest :=
  r.hardProfileDigest_

def effectiveProfile (r : DarwinFrontendSupervisorReceiptV1) : ResourceProfileV1 :=
  r.effectiveProfile_

def effectiveProfileDigest (r : DarwinFrontendSupervisorReceiptV1) : Digest :=
  r.effectiveProfileDigest_

def requestDigest (r : DarwinFrontendSupervisorReceiptV1) : Option Digest :=
  r.requestDigest_

def observations (r : DarwinFrontendSupervisorReceiptV1) :
    DarwinFrontendPublicObservationsV1 :=
  r.observations_

def event (r : DarwinFrontendSupervisorReceiptV1) : DarwinFrontendSupervisorEventV1 :=
  r.event_

def result (r : DarwinFrontendSupervisorReceiptV1) : DarwinFrontendSupervisorResultV1 :=
  r.result_

def cleanup (r : DarwinFrontendSupervisorReceiptV1) : DarwinFrontendCleanupResultV1 :=
  r.cleanup_

end DarwinFrontendSupervisorReceiptV1

private def uint64ToPfInt (label : String) (value : UInt64) : Except String Int := do
  let result := Int.ofNat value.toNat
  -- Delegate the signed I-JSON safe-integer bound to the sole PF-JCS renderer
  -- instead of copying its numeric maximum into this module.
  match renderPfJcs (.int result) with
  | .ok _ => pure result
  | .error error => throw s!"{label}: {error}"

private def pfIntToUInt64 (label : String) (value : Int) : Except String UInt64 := do
  if value < 0 then throw s!"{label} must be nonnegative"
  let _ ← renderPfJcs (.int value)
  let natural := value.toNat
  unless natural < UInt64.size do throw s!"{label} exceeds UInt64"
  pure (UInt64.ofNat natural)

private def pfIntToUInt32 (label : String) (value : Int) : Except String UInt32 := do
  if value < 0 then throw s!"{label} must be nonnegative"
  let _ ← renderPfJcs (.int value)
  let natural := value.toNat
  unless natural < UInt32.size do throw s!"{label} exceeds UInt32"
  pure (UInt32.ofNat natural)

private def observationsToPfJson
    (observations : DarwinFrontendPublicObservationsV1) : Except String PfJson := do
  let elapsed ← uint64ToPfInt "elapsedMillis" observations.elapsedMillis
  let memory ← uint64ToPfInt
    "peakAggregateMemoryBytes" observations.peakAggregateMemoryBytes
  pure (.object #[
    ("elapsedMillis", .int elapsed),
    ("peakAggregateMemoryBytes", .int memory),
    ("peakProcesses", .int (Int.ofNat observations.peakProcesses.toNat))
  ])

private def observationsFromPfJson
    (value : PfJson) : Except String DarwinFrontendPublicObservationsV1 := do
  match value with
  | .object fields =>
      match fields.toList with
      | [("elapsedMillis", .int elapsedValue),
          ("peakAggregateMemoryBytes", .int memoryValue),
          ("peakProcesses", .int processValue)] =>
          let elapsedMillis ← pfIntToUInt64 "elapsedMillis" elapsedValue
          let peakAggregateMemoryBytes ←
            pfIntToUInt64 "peakAggregateMemoryBytes" memoryValue
          let peakProcesses ← pfIntToUInt32 "peakProcesses" processValue
          pure { elapsedMillis, peakAggregateMemoryBytes, peakProcesses }
      | _ => throw "observations must contain exactly its three closed fields"
  | _ => throw "observations must be an object"

private def profileToPfJson (profile : ResourceProfileV1) : Except String PfJson := do
  let rendered ← renderResourceProfileJcs profile
  parsePfJcs rendered

private def profileFromPfJson (value : PfJson) : Except String ResourceProfileV1 := do
  let rendered ← renderPfJcs value
  parseResourceProfileJcs rendered

private def validateWithinEffective
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) : Except String Unit := do
  unless observations.elapsedMillis ≤ effective.maxWallMillis do
    throw "elapsedMillis exceeds effective frontend wall limit"
  unless observations.peakAggregateMemoryBytes ≤ effective.maxAggregateMemoryBytes do
    throw "peakAggregateMemoryBytes exceeds effective frontend memory limit"
  unless observations.peakProcesses ≤ effective.maxProcesses do
    throw "peakProcesses exceeds effective frontend process limit"

private def validateDeadlineObservation
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) : Except String Unit := do
  unless observations.elapsedMillis.toNat = effective.maxWallMillis.toNat + 1 do
    throw "deadline event must saturate elapsedMillis at effective limit plus one"
  unless observations.peakAggregateMemoryBytes ≤ effective.maxAggregateMemoryBytes do
    throw "deadline event carries memory above its effective limit"
  unless observations.peakProcesses ≤ effective.maxProcesses do
    throw "deadline event carries processes above its effective limit"

private def validateMemoryLimitObservation
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) : Except String Unit := do
  unless observations.peakAggregateMemoryBytes.toNat =
      effective.maxAggregateMemoryBytes.toNat + 1 do
    throw "memory event must saturate peak memory at effective limit plus one"
  unless observations.elapsedMillis ≤ effective.maxWallMillis do
    throw "memory event carries elapsedMillis above its effective limit"
  unless observations.peakProcesses ≤ effective.maxProcesses do
    throw "memory event carries processes above its effective limit"

private def validateProcessLimitObservation
    (observations : DarwinFrontendPublicObservationsV1)
    (effective : ResourceProfileV1) : Except String Unit := do
  unless observations.peakProcesses.toNat = effective.maxProcesses.toNat + 1 do
    throw "process event must saturate peakProcesses at effective limit plus one"
  unless observations.elapsedMillis ≤ effective.maxWallMillis do
    throw "process event carries elapsedMillis above its effective limit"
  unless observations.peakAggregateMemoryBytes ≤ effective.maxAggregateMemoryBytes do
    throw "process event carries memory above its effective limit"

private def validateEventAndResult
    (requestDigest : Option Digest)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1) : Except String Unit := do
  match event with
  | .responseAccepted =>
      unless requestDigest.isSome do
        throw "response-accepted requires a request digest"
      if result == .noResponse then
        throw "response-accepted requires response-ok or response-error"
      unless cleanup == .observedComplete do
        throw "response-accepted requires observed-complete cleanup"
  | .sourceOpenFailed =>
      unless requestDigest.isNone do
        throw "source-open-failed must precede request construction"
      unless result == .noResponse do
        throw "source-open-failed cannot carry a response result"
      unless cleanup == .observedComplete do
        throw "source-open-failed requires observed-complete cleanup"
  | _ =>
      unless result == .noResponse do
        throw "non-response supervisor event cannot carry a response result"

private def validateReceiptData
    (effectiveProfile : ResourceProfileV1)
    (requestDigest : Option Digest)
    (observations : DarwinFrontendPublicObservationsV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1) : Except String Unit := do
  validateLowerOnlyResourceProfile hardFrontendProfile effectiveProfile
  -- Force the public observations through the same bounded PF-JCS integer
  -- domain used by rendering, even when no render follows this helper.
  let _ ← observationsToPfJson observations
  match requestDigest with
  | some digest => validateDigest digest
  | none => pure ()
  validateEventAndResult requestDigest event result cleanup
  match event with
  | .deadlineObserved => validateDeadlineObservation observations effectiveProfile
  | .memoryLimitObserved =>
      validateMemoryLimitObservation observations effectiveProfile
  | .processLimitObserved =>
      validateProcessLimitObservation observations effectiveProfile
  | .outputLimitObserved =>
      -- The public-safe internal projection intentionally carries no stream
      -- byte count or tail. B11b owns output-cap attribution; this model only
      -- requires all represented resource dimensions to remain bounded.
      validateWithinEffective observations effectiveProfile
  | _ => validateWithinEffective observations effectiveProfile

private def makeReceiptFromDigest
    (effectiveProfile : ResourceProfileV1)
    (requestDigest : Option Digest)
    (observations : DarwinFrontendPublicObservationsV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1) :
    Except String DarwinFrontendSupervisorReceiptV1 := do
  validateReceiptData effectiveProfile requestDigest observations event result cleanup
  let hardProfileDigest ← resourceProfileDigest hardFrontendProfile
  let effectiveProfileDigest ← resourceProfileDigest effectiveProfile
  let assurance ← match compiledHostAssuranceV1 with
    | some value => pure value
    | none => throw "unsupported-platform"
  pure {
    assurance_ := assurance
    hardProfileId_ := hardFrontendProfile.profileId
    hardProfileDigest_ := hardProfileDigest
    effectiveProfile_ := effectiveProfile
    effectiveProfileDigest_ := effectiveProfileDigest
    requestDigest_ := requestDigest
    observations_ := observations
    event_ := event
    result_ := result
    cleanup_ := cleanup
  }

/-- Sole public constructor. The optional request is immediately reduced to its
    canonical request digest; raw source bytes/selectors are never retained. -/
def mkDarwinFrontendSupervisorReceiptV1
    (effectiveProfile : ResourceProfileV1)
    (request : Option FrontendRequestV1)
    (observations : DarwinFrontendPublicObservationsV1)
    (event : DarwinFrontendSupervisorEventV1)
    (result : DarwinFrontendSupervisorResultV1)
    (cleanup : DarwinFrontendCleanupResultV1) :
    Except String DarwinFrontendSupervisorReceiptV1 := do
  let requestDigest ← match request with
    | some value => pure (some (← requestDigestOfV1 value))
    | none => pure none
  makeReceiptFromDigest effectiveProfile requestDigest observations event result cleanup

/-- Canonical closed PF-JCS projection. -/
def renderDarwinFrontendSupervisorReceiptJcsV1
    (receipt : DarwinFrontendSupervisorReceiptV1) : Except String String := do
  -- Revalidate direct internal values before rendering; the private constructor
  -- prevents external fabrication, but this keeps the encoder's authority local.
  validateReceiptData receipt.effectiveProfile_ receipt.requestDigest_
    receipt.observations_ receipt.event_ receipt.result_ receipt.cleanup_
  let hardProfileDigest ← resourceProfileDigest hardFrontendProfile
  let effectiveProfileDigest ← resourceProfileDigest receipt.effectiveProfile_
  unless some receipt.assurance_ == compiledHostAssuranceV1 do
    throw "frontend receipt assurance mismatch"
  unless receipt.hardProfileId_ == hardFrontendProfile.profileId do
    throw "Darwin receipt hard profile id mismatch"
  unless receipt.hardProfileDigest_ == hardProfileDigest do
    throw "Darwin receipt hard profile digest mismatch"
  unless receipt.effectiveProfileDigest_ == effectiveProfileDigest do
    throw "Darwin receipt effective profile digest mismatch"
  let effectiveProfile ← profileToPfJson receipt.effectiveProfile_
  let hardDigestWire ← renderDigest receipt.hardProfileDigest_
  let effectiveDigestWire ← renderDigest receipt.effectiveProfileDigest_
  let observations ← observationsToPfJson receipt.observations_
  let requestDigest ← match receipt.requestDigest_ with
    | some digest => pure (.string (← renderDigest digest))
    | none => pure .null
  let rendered ← renderPfJcs (.object #[
    ("schema", .string darwinFrontendSupervisorReceiptSchemaV1.value),
    ("assurance", .string receipt.assurance_.wire),
    ("hardProfileId", .string receipt.hardProfileId_.value),
    ("hardProfileDigest", .string hardDigestWire),
    ("effectiveProfile", effectiveProfile),
    ("effectiveProfileDigest", .string effectiveDigestWire),
    ("requestDigest", requestDigest),
    ("observations", observations),
    ("event", .string receipt.event_.wire),
    ("result", .string receipt.result_.wire),
    ("cleanup", .string receipt.cleanup_.wire)
  ])
  unless rendered.utf8ByteSize ≤ maxDarwinFrontendSupervisorReceiptJcsBytesV1 do
    throw "Darwin receipt exceeds its PF-JCS byte limit"
  pure rendered

private def requireEnum (label : String) (value : Option α) : Except String α :=
  match value with
  | some parsed => pure parsed
  | none => throw s!"unknown Darwin frontend {label} wire value"

/-- Strict decoder: byte cap before parse, exact closed fields, recomputed
    profile/request-independent digests, smart-constructor invariants, and exact
    re-encode identity. -/
def parseDarwinFrontendSupervisorReceiptJcsV1
    (input : String) : Except String DarwinFrontendSupervisorReceiptV1 := do
  unless input.utf8ByteSize ≤ maxDarwinFrontendSupervisorReceiptJcsBytesV1 do
    throw "Darwin receipt exceeds its PF-JCS byte limit"
  let value ← parsePfJcs input
  let receipt ← match value with
    | .object fields =>
        match fields.toList with
        | [("assurance", .string assuranceWire),
            ("cleanup", .string cleanupWire),
            ("effectiveProfile", effectiveProfileValue),
            ("effectiveProfileDigest", .string effectiveDigestWire),
            ("event", .string eventWire),
            ("hardProfileDigest", .string hardDigestWire),
            ("hardProfileId", .string hardProfileIdWire),
            ("observations", observationsValue),
            ("requestDigest", requestDigestValue),
            ("result", .string resultWire),
            ("schema", .string schemaWire)] => do
            unless schemaWire == darwinFrontendSupervisorReceiptSchemaV1.value do
              throw "Darwin receipt schema mismatch"
            let assurance ← requireEnum "assurance"
              (DarwinFrontendAssuranceV1.ofWire? assuranceWire)
            unless some assurance == compiledHostAssuranceV1 do
              throw "frontend receipt assurance mismatch"
            unless hardProfileIdWire == hardFrontendProfile.profileId.value do
              throw "Darwin receipt hard profile id mismatch"
            let hardDigest ← parseDigest hardDigestWire
            let expectedHardDigest ← resourceProfileDigest hardFrontendProfile
            unless hardDigest == expectedHardDigest do
              throw "Darwin receipt hard profile digest mismatch"
            let effectiveProfile ← profileFromPfJson effectiveProfileValue
            let effectiveDigest ← parseDigest effectiveDigestWire
            let expectedEffectiveDigest ← resourceProfileDigest effectiveProfile
            unless effectiveDigest == expectedEffectiveDigest do
              throw "Darwin receipt effective profile digest mismatch"
            let observations ← observationsFromPfJson observationsValue
            let requestDigest ← match requestDigestValue with
              | .null => pure none
              | .string digestWire => pure (some (← parseDigest digestWire))
              | _ => throw "Darwin receipt requestDigest must be digest string or null"
            let event ← requireEnum "event"
              (DarwinFrontendSupervisorEventV1.ofWire? eventWire)
            let result ← requireEnum "result"
              (DarwinFrontendSupervisorResultV1.ofWire? resultWire)
            let cleanup ← requireEnum "cleanup"
              (DarwinFrontendCleanupResultV1.ofWire? cleanupWire)
            makeReceiptFromDigest effectiveProfile requestDigest observations
              event result cleanup
        | _ => throw "Darwin receipt must contain exactly its eleven closed fields"
    | _ => throw "Darwin receipt must be an object"
  let canonical ← renderDarwinFrontendSupervisorReceiptJcsV1 receipt
  unless canonical == input do
    throw "Darwin receipt is noncanonical"
  pure receipt

/-- Domain-separated digest over exact canonical receipt bytes. -/
def darwinFrontendSupervisorReceiptDigestV1
    (receipt : DarwinFrontendSupervisorReceiptV1) : Except String Digest := do
  let canonical ← renderDarwinFrontendSupervisorReceiptJcsV1 receipt
  domainSeparatedSha256 darwinFrontendSupervisorReceiptSchemaV1.value canonical.toUTF8

/-- Bind a parsed receipt to the exact canonical request and reject replay. -/
def bindDarwinFrontendSupervisorReceiptV1
    (request : FrontendRequestV1)
    (receipt : DarwinFrontendSupervisorReceiptV1) :
    Except String DarwinFrontendSupervisorReceiptV1 := do
  let digest ← requestDigestOfV1 request
  unless receipt.requestDigest_ == some digest do
    throw "Darwin receipt requestDigest does not match request (cross-request replay)"
  pure receipt

end ProofForgeV2.Frontend.DarwinSupervisorReceiptV1
