/-
  ProofForgeV2.Core.DiagnosticV1 — structured diagnostic carrier (B6 / ADR-0022 /
  SPEC-DIAG-001).

  Closed code catalog with exact wire strings, severity/phase defaults, and
  stable ranks.  Origins are diagnostic-only `DiagnosticOriginV1` with nullable
  `nodeId` (common `SourceOrigin` is unchanged).  Canonical PF-JCS encode/decode
  is fail-closed (unknown fields/enums/schema, trailing, noncanonical).  Order
  and dedupe keys are message-independent:
    (primary.sourcePath or "", primary.startByte or 0, code.wire, stableContext none→"").

  `errorSentinelNodeId` remains until B7 retires zero-sentinel attribution.
  `normalizeDiagnosticBundleV1` is shipped but unused by product until B7/B8.
-/
import ProofForgeV2.Core.Common
import ProofForgeV2.Core.Diagnostic

open ProofForgeV2.Core.Common
open ProofForgeV2 (TargetId)

namespace ProofForgeV2.Core.DiagnosticV1

/-- Documented zero-filled 16-byte sentinel used for error-time origins when a
    canonical traversal `NodeId` has not been assigned.  Retired to explicit
    `nodeId = none` only in B7. -/
def errorSentinelNodeId : NodeId where
  bytes := ByteArray.mk (Array.replicate 16 (0 : UInt8))

/-- Diagnostic severity enum (SPEC-DIAG-001). -/
inductive DiagnosticSeverityV1 where
  | error
  | warning
  | note
  deriving BEq, DecidableEq, Repr, Inhabited

namespace DiagnosticSeverityV1

def wire : DiagnosticSeverityV1 → String
  | .error => "error"
  | .warning => "warning"
  | .note => "note"

def parse (s : String) : Option DiagnosticSeverityV1 :=
  match s with
  | "error" => some .error
  | "warning" => some .warning
  | "note" => some .note
  | _ => none

def rank : DiagnosticSeverityV1 → Nat
  | .error => 0
  | .warning => 1
  | .note => 2

end DiagnosticSeverityV1

/-- Diagnostic phase enum (SPEC-DIAG-001). -/
inductive DiagnosticPhaseV1 where
  | source
  | type
  | effect
  | semantic
  | resolve
  | plan
  | lower
  | emit
  | tool
  | deploy
  | verify
  deriving BEq, DecidableEq, Repr, Inhabited

namespace DiagnosticPhaseV1

def wire : DiagnosticPhaseV1 → String
  | .source => "source"
  | .type => "type"
  | .effect => "effect"
  | .semantic => "semantic"
  | .resolve => "resolve"
  | .plan => "plan"
  | .lower => "lower"
  | .emit => "emit"
  | .tool => "tool"
  | .deploy => "deploy"
  | .verify => "verify"

def parse (s : String) : Option DiagnosticPhaseV1 :=
  match s with
  | "source" => some .source
  | "type" => some .type
  | "effect" => some .effect
  | "semantic" => some .semantic
  | "resolve" => some .resolve
  | "plan" => some .plan
  | "lower" => some .lower
  | "emit" => some .emit
  | "tool" => some .tool
  | "deploy" => some .deploy
  | "verify" => some .verify
  | _ => none

def rank : DiagnosticPhaseV1 → Nat
  | .source => 0
  | .type => 1
  | .effect => 2
  | .semantic => 3
  | .resolve => 4
  | .plan => 5
  | .lower => 6
  | .emit => 7
  | .tool => 8
  | .deploy => 9
  | .verify => 10

end DiagnosticPhaseV1

/-- Closed SPEC-DIAG-001 initial error-code catalog (no alpha `PF-SEM-*` runtime
    codes, no `PF-CLI-USAGE` / `PF-OUTPUT-MANIFEST`). -/
inductive DiagnosticCodeV1 where
  | src001
  | src010
  | src020
  | srcNodeIdCollision
  | type001
  | type002
  | type003
  | type004
  | effectDisallowed
  | effect002
  | resourceBound
  | sourceInvalid
  | resourceTime
  | resourceMemory
  | resourceProcess
  | resourceOutput
  | frontendProtocol
  | languageVersionUnknown
  | languageVersionDisabled
  | languageDefault
  | migrationFailed
  | visibilityViolation
  | ext001
  | export001
  | export002
  | export003
  | export004
  | targetUnknown
  | targetNotImplemented
  | profileUnknown
  | profileRevoked
  | registryDuplicate
  | registryInvalid
  | reqUnsupported
  | reqPrecondition
  | reqEvidence
  | reqConflict
  | evidenceBinding
  | semanticsMismatch
  | semanticInvalid
  | semanticInternal
  | extensionVersion
  | planInvariant
  | lowerInvariant
  | toolchainMismatch
  | toolchainMissing
  | toolUntrusted
  | toolProtocol
  | hostStage0
  | hostIneligible
  | artifactInvalid
  | artifactNondeployable
  | settlementUnavailable
  | outputPath
  | outputCollision
  | outputLimit
  | outputAtomicity
  | diagLimit
  | internal
  deriving BEq, DecidableEq, Repr, Inhabited

namespace DiagnosticCodeV1

/-- Explicit stable rank constants (table order of SPEC-DIAG-001). -/
def rank : DiagnosticCodeV1 → Nat
  | .src001 => 0
  | .src010 => 1
  | .src020 => 2
  | .srcNodeIdCollision => 3
  | .type001 => 4
  | .type002 => 5
  | .type003 => 6
  | .type004 => 7
  | .effectDisallowed => 8
  | .effect002 => 9
  | .resourceBound => 10
  | .sourceInvalid => 11
  | .resourceTime => 12
  | .resourceMemory => 13
  | .resourceProcess => 14
  | .resourceOutput => 15
  | .frontendProtocol => 16
  | .languageVersionUnknown => 17
  | .languageVersionDisabled => 18
  | .languageDefault => 19
  | .migrationFailed => 20
  | .visibilityViolation => 21
  | .ext001 => 22
  | .export001 => 23
  | .export002 => 24
  | .export003 => 25
  | .export004 => 26
  | .targetUnknown => 27
  | .targetNotImplemented => 28
  | .profileUnknown => 29
  | .profileRevoked => 30
  | .registryDuplicate => 31
  | .registryInvalid => 32
  | .reqUnsupported => 33
  | .reqPrecondition => 34
  | .reqEvidence => 35
  | .reqConflict => 36
  | .evidenceBinding => 37
  | .semanticsMismatch => 38
  | .semanticInvalid => 39
  | .semanticInternal => 40
  | .extensionVersion => 41
  | .planInvariant => 42
  | .lowerInvariant => 43
  | .toolchainMismatch => 44
  | .toolchainMissing => 45
  | .toolUntrusted => 46
  | .toolProtocol => 47
  | .hostStage0 => 48
  | .hostIneligible => 49
  | .artifactInvalid => 50
  | .artifactNondeployable => 51
  | .settlementUnavailable => 52
  | .outputPath => 53
  | .outputCollision => 54
  | .outputLimit => 55
  | .outputAtomicity => 56
  | .diagLimit => 57
  | .internal => 58

/-- Exact wire code string for each diagnostic code. -/
def wire : DiagnosticCodeV1 → String
  | .src001 => "PF-SRC-001"
  | .src010 => "PF-SRC-010"
  | .src020 => "PF-SRC-020"
  | .srcNodeIdCollision => "PF-SRC-NODEID-COLLISION"
  | .type001 => "PF-TYPE-001"
  | .type002 => "PF-TYPE-002"
  | .type003 => "PF-TYPE-003"
  | .type004 => "PF-TYPE-004"
  | .effectDisallowed => "PF-EFFECT-001"
  | .effect002 => "PF-EFFECT-002"
  | .resourceBound => "PF-BOUND-001"
  | .sourceInvalid => "PF-SRC-INVALID"
  | .resourceTime => "PF-RESOURCE-TIME"
  | .resourceMemory => "PF-RESOURCE-MEMORY"
  | .resourceProcess => "PF-RESOURCE-PROCESS"
  | .resourceOutput => "PF-RESOURCE-OUTPUT"
  | .frontendProtocol => "PF-FRONTEND-PROTOCOL"
  | .languageVersionUnknown => "PF-LANGUAGE-VERSION-UNKNOWN"
  | .languageVersionDisabled => "PF-LANGUAGE-VERSION-DISABLED"
  | .languageDefault => "PF-LANGUAGE-DEFAULT"
  | .migrationFailed => "PF-MIGRATION-FAILED"
  | .visibilityViolation => "PF-VIS-001"
  | .ext001 => "PF-EXT-001"
  | .export001 => "PF-EXPORT-001"
  | .export002 => "PF-EXPORT-002"
  | .export003 => "PF-EXPORT-003"
  | .export004 => "PF-EXPORT-004"
  | .targetUnknown => "PF-TARGET-UNKNOWN"
  | .targetNotImplemented => "PF-TARGET-NOT-IMPLEMENTED"
  | .profileUnknown => "PF-PROFILE-UNKNOWN"
  | .profileRevoked => "PF-PROFILE-REVOKED"
  | .registryDuplicate => "PF-REGISTRY-DUPLICATE"
  | .registryInvalid => "PF-REGISTRY-INVALID"
  | .reqUnsupported => "PF-REQ-UNSUPPORTED"
  | .reqPrecondition => "PF-REQ-PRECONDITION"
  | .reqEvidence => "PF-REQ-EVIDENCE"
  | .reqConflict => "PF-REQ-CONFLICT"
  | .evidenceBinding => "PF-EVIDENCE-BINDING"
  | .semanticsMismatch => "PF-SEMANTICS-MISMATCH"
  | .semanticInvalid => "PF-SEMANTIC-INVALID"
  | .semanticInternal => "PF-SEMANTIC-INTERNAL"
  | .extensionVersion => "PF-EXTENSION-VERSION"
  | .planInvariant => "PF-PLAN-INVARIANT"
  | .lowerInvariant => "PF-LOWER-INVARIANT"
  | .toolchainMismatch => "PF-TOOLCHAIN-MISMATCH"
  | .toolchainMissing => "PF-TOOLCHAIN-MISSING"
  | .toolUntrusted => "PF-TOOL-UNTRUSTED"
  | .toolProtocol => "PF-TOOL-PROTOCOL"
  | .hostStage0 => "PF-HOST-STAGE0"
  | .hostIneligible => "PF-HOST-INELIGIBLE"
  | .artifactInvalid => "PF-ARTIFACT-INVALID"
  | .artifactNondeployable => "PF-ARTIFACT-NONDEPLOYABLE"
  | .settlementUnavailable => "PF-SETTLEMENT-UNAVAILABLE"
  | .outputPath => "PF-OUTPUT-PATH"
  | .outputCollision => "PF-OUTPUT-COLLISION"
  | .outputLimit => "PF-OUTPUT-LIMIT"
  | .outputAtomicity => "PF-OUTPUT-ATOMICITY"
  | .diagLimit => "PF-DIAG-LIMIT"
  | .internal => "PF-INTERNAL"

def parse (s : String) : Option DiagnosticCodeV1 :=
  match s with
  | "PF-SRC-001" => some .src001
  | "PF-SRC-010" => some .src010
  | "PF-SRC-020" => some .src020
  | "PF-SRC-NODEID-COLLISION" => some .srcNodeIdCollision
  | "PF-TYPE-001" => some .type001
  | "PF-TYPE-002" => some .type002
  | "PF-TYPE-003" => some .type003
  | "PF-TYPE-004" => some .type004
  | "PF-EFFECT-001" => some .effectDisallowed
  | "PF-EFFECT-002" => some .effect002
  | "PF-BOUND-001" => some .resourceBound
  | "PF-SRC-INVALID" => some .sourceInvalid
  | "PF-RESOURCE-TIME" => some .resourceTime
  | "PF-RESOURCE-MEMORY" => some .resourceMemory
  | "PF-RESOURCE-PROCESS" => some .resourceProcess
  | "PF-RESOURCE-OUTPUT" => some .resourceOutput
  | "PF-FRONTEND-PROTOCOL" => some .frontendProtocol
  | "PF-LANGUAGE-VERSION-UNKNOWN" => some .languageVersionUnknown
  | "PF-LANGUAGE-VERSION-DISABLED" => some .languageVersionDisabled
  | "PF-LANGUAGE-DEFAULT" => some .languageDefault
  | "PF-MIGRATION-FAILED" => some .migrationFailed
  | "PF-VIS-001" => some .visibilityViolation
  | "PF-EXT-001" => some .ext001
  | "PF-EXPORT-001" => some .export001
  | "PF-EXPORT-002" => some .export002
  | "PF-EXPORT-003" => some .export003
  | "PF-EXPORT-004" => some .export004
  | "PF-TARGET-UNKNOWN" => some .targetUnknown
  | "PF-TARGET-NOT-IMPLEMENTED" => some .targetNotImplemented
  | "PF-PROFILE-UNKNOWN" => some .profileUnknown
  | "PF-PROFILE-REVOKED" => some .profileRevoked
  | "PF-REGISTRY-DUPLICATE" => some .registryDuplicate
  | "PF-REGISTRY-INVALID" => some .registryInvalid
  | "PF-REQ-UNSUPPORTED" => some .reqUnsupported
  | "PF-REQ-PRECONDITION" => some .reqPrecondition
  | "PF-REQ-EVIDENCE" => some .reqEvidence
  | "PF-REQ-CONFLICT" => some .reqConflict
  | "PF-EVIDENCE-BINDING" => some .evidenceBinding
  | "PF-SEMANTICS-MISMATCH" => some .semanticsMismatch
  | "PF-SEMANTIC-INVALID" => some .semanticInvalid
  | "PF-SEMANTIC-INTERNAL" => some .semanticInternal
  | "PF-EXTENSION-VERSION" => some .extensionVersion
  | "PF-PLAN-INVARIANT" => some .planInvariant
  | "PF-LOWER-INVARIANT" => some .lowerInvariant
  | "PF-TOOLCHAIN-MISMATCH" => some .toolchainMismatch
  | "PF-TOOLCHAIN-MISSING" => some .toolchainMissing
  | "PF-TOOL-UNTRUSTED" => some .toolUntrusted
  | "PF-TOOL-PROTOCOL" => some .toolProtocol
  | "PF-HOST-STAGE0" => some .hostStage0
  | "PF-HOST-INELIGIBLE" => some .hostIneligible
  | "PF-ARTIFACT-INVALID" => some .artifactInvalid
  | "PF-ARTIFACT-NONDEPLOYABLE" => some .artifactNondeployable
  | "PF-SETTLEMENT-UNAVAILABLE" => some .settlementUnavailable
  | "PF-OUTPUT-PATH" => some .outputPath
  | "PF-OUTPUT-COLLISION" => some .outputCollision
  | "PF-OUTPUT-LIMIT" => some .outputLimit
  | "PF-OUTPUT-ATOMICITY" => some .outputAtomicity
  | "PF-DIAG-LIMIT" => some .diagLimit
  | "PF-INTERNAL" => some .internal
  | _ => none

/-- Default severity for every catalog code is `error` (initial table). -/
def defaultSeverity (_ : DiagnosticCodeV1) : DiagnosticSeverityV1 := .error

/-- Default phase for each catalog code (table-driven). -/
def defaultPhase : DiagnosticCodeV1 → DiagnosticPhaseV1
  | .src001 | .src010 | .src020 | .srcNodeIdCollision | .sourceInvalid
  | .resourceBound | .frontendProtocol | .languageVersionUnknown
  | .languageVersionDisabled | .languageDefault | .migrationFailed
  | .ext001 | .export001 | .export002 | .export003 | .export004 => .source
  | .type001 | .type002 | .type003 | .type004 => .type
  | .effectDisallowed | .effect002 | .visibilityViolation => .effect
  | .semanticsMismatch | .semanticInvalid | .semanticInternal => .semantic
  | .targetUnknown | .targetNotImplemented | .profileUnknown | .profileRevoked
  | .registryDuplicate | .registryInvalid | .reqUnsupported | .reqPrecondition
  | .reqEvidence | .reqConflict | .evidenceBinding | .extensionVersion => .resolve
  | .planInvariant => .plan
  | .lowerInvariant => .lower
  | .artifactInvalid | .artifactNondeployable | .settlementUnavailable
  | .outputPath | .outputCollision | .outputLimit | .outputAtomicity => .emit
  | .resourceTime | .resourceMemory | .resourceProcess | .resourceOutput
  | .toolchainMismatch | .toolchainMissing | .toolUntrusted | .toolProtocol
  | .hostStage0 | .hostIneligible | .diagLimit | .internal => .tool

/-- Closed catalog as a fixed array for uniqueness/registry tests. -/
def all : Array DiagnosticCodeV1 := #[
  .src001, .src010, .src020, .srcNodeIdCollision,
  .type001, .type002, .type003, .type004,
  .effectDisallowed, .effect002, .resourceBound, .sourceInvalid,
  .resourceTime, .resourceMemory, .resourceProcess, .resourceOutput,
  .frontendProtocol, .languageVersionUnknown, .languageVersionDisabled,
  .languageDefault, .migrationFailed, .visibilityViolation, .ext001,
  .export001, .export002, .export003, .export004,
  .targetUnknown, .targetNotImplemented, .profileUnknown, .profileRevoked,
  .registryDuplicate, .registryInvalid, .reqUnsupported, .reqPrecondition,
  .reqEvidence, .reqConflict, .evidenceBinding,
  .semanticsMismatch, .semanticInvalid, .semanticInternal, .extensionVersion,
  .planInvariant, .lowerInvariant, .toolchainMismatch, .toolchainMissing,
  .toolUntrusted, .toolProtocol, .hostStage0, .hostIneligible,
  .artifactInvalid, .artifactNondeployable, .settlementUnavailable,
  .outputPath, .outputCollision, .outputLimit, .outputAtomicity,
  .diagLimit, .internal
]

end DiagnosticCodeV1

/-- Diagnostic-only origin: `nodeId` is explicitly nullable (pre-node locations).
    Common `SourceOrigin` remains non-null NodeId and is not used here. -/
structure DiagnosticOriginV1 where
  sourcePath : ProjectRelativePath
  startByte : UInt64
  endByte : UInt64
  nodeId : Option NodeId
  deriving BEq, Repr

instance : Inhabited DiagnosticOriginV1 where
  default := {
    sourcePath := { value := "x" }
    startByte := 0
    endByte := 0
    nodeId := none
  }

/-- Core-local requirement identity for diagnostics (keeps Core free of Semantic). -/
structure RequirementKeyV1 where
  id : String
  version : SemVer
  digest : Digest
  deriving BEq, Repr

instance : Inhabited RequirementKeyV1 where
  default := {
    id := "x.y"
    version := { major := 0, minor := 0, patch := 0 }
    digest := { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }
  }

/-- Core-local extension identity for diagnostics (same shape as RequirementKeyV1). -/
structure ExtensionKeyV1 where
  id : String
  version : SemVer
  digest : Digest
  deriving BEq, Repr

instance : Inhabited ExtensionKeyV1 where
  default := {
    id := "x.y"
    version := { major := 0, minor := 0, patch := 0 }
    digest := { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 32 (0 : UInt8)) }
  }

/-- Structured diagnostic record (SPEC-DIAG-001). -/
structure DiagnosticV1 where
  schemaVersion : Nat
  code : DiagnosticCodeV1
  severity : DiagnosticSeverityV1
  phase : DiagnosticPhaseV1
  message : String
  primary : Option DiagnosticOriginV1
  related : Array DiagnosticOriginV1
  program : Option QualifiedName
  target : Option TargetId
  requirement : Option RequirementKeyV1
  extension : Option ExtensionKeyV1
  expected : Option PfJson
  actual : Option PfJson
  context : Option PfJson
  stableContext : Option String
  suggestion : Option String
  deriving BEq, Repr

instance : Inhabited DiagnosticV1 where
  default := {
    schemaVersion := 1
    code := .sourceInvalid
    severity := .error
    phase := .source
    message := ""
    primary := none
    related := #[]
    program := none
    target := none
    requirement := none
    extension := none
    expected := none
    actual := none
    context := none
    stableContext := none
    suggestion := none
  }

namespace DiagnosticOriginV1

private def compareByteArray (left right : ByteArray) : Ordering :=
  if left.size < right.size then .lt
  else if left.size > right.size then .gt
  else
    let rec loop (i : Nat) : Ordering :=
      if i < left.size then
        let byteL := left.get! i
        let byteR := right.get! i
        if byteL.toNat < byteR.toNat then .lt
        else if byteL.toNat > byteR.toNat then .gt
        else loop (i + 1)
      else
        .eq
    loop 0

/-- Total order: `(path, start, end, none < some raw NodeId)`. -/
def compare (left right : DiagnosticOriginV1) : Ordering :=
  if left.sourcePath.value < right.sourcePath.value then .lt
  else if left.sourcePath.value > right.sourcePath.value then .gt
  else if left.startByte.toNat < right.startByte.toNat then .lt
  else if left.startByte.toNat > right.startByte.toNat then .gt
  else if left.endByte.toNat < right.endByte.toNat then .lt
  else if left.endByte.toNat > right.endByte.toNat then .gt
  else
    match left.nodeId, right.nodeId with
    | none, none => .eq
    | none, some _ => .lt
    | some _, none => .gt
    | some l, some r => compareByteArray l.bytes r.bytes

/-- Structural validation only: project-relative path, range, optional NodeId.
    Does not claim secret detection. -/
def validate (origin : DiagnosticOriginV1) : Except String Unit := do
  validateProjectRelativePath origin.sourcePath
  unless origin.startByte ≤ origin.endByte do
    throw "diagnostic-origin startByte must not exceed endByte"
  match origin.nodeId with
  | none => pure ()
  | some nodeId => validateNodeId nodeId

private def uint64ToPfInt (label : String) (value : UInt64) : Except String Int := do
  let natural := value.toNat
  unless natural ≤ 9007199254740991 do
    throw s!"{label} exceeds the PF-JCS safe-integer range"
  pure (Int.ofNat natural)

private def pfIntToUInt64 (label : String) (value : Int) : Except String UInt64 := do
  if value < 0 then
    throw s!"{label} must be nonnegative"
  let natural := value.toNat
  unless natural ≤ 9007199254740991 do
    throw s!"{label} exceeds the PF-JCS safe-integer range"
  pure (UInt64.ofNat natural)

def toPfJson (origin : DiagnosticOriginV1) : Except String PfJson := do
  validate origin
  let sourcePath ← renderProjectRelativePath origin.sourcePath
  let startByte ← uint64ToPfInt "diagnostic-origin startByte" origin.startByte
  let endByte ← uint64ToPfInt "diagnostic-origin endByte" origin.endByte
  let nodeJson ← match origin.nodeId with
    | none => pure PfJson.null
    | some nodeId =>
        let rendered ← renderNodeId nodeId
        pure (.string rendered)
  pure (.object #[
    ("endByte", .int endByte),
    ("nodeId", nodeJson),
    ("sourcePath", .string sourcePath),
    ("startByte", .int startByte)
  ])

def fromPfJson (value : PfJson) : Except String DiagnosticOriginV1 := do
  match value with
  | .object fields =>
    match fields.toList with
    | [("endByte", .int endValue), ("nodeId", nodeJson),
        ("sourcePath", .string pathValue), ("startByte", .int startValue)] =>
      let sourcePath ← parseProjectRelativePath pathValue
      let startByte ← pfIntToUInt64 "diagnostic-origin startByte" startValue
      let endByte ← pfIntToUInt64 "diagnostic-origin endByte" endValue
      let nodeId ← match nodeJson with
        | .null => pure none
        | .string nodeValue => some <$> parseNodeId nodeValue
        | _ => throw "diagnostic-origin nodeId must be string or null"
      let origin := { sourcePath, startByte, endByte, nodeId }
      validate origin
      pure origin
    | _ => throw "diagnostic-origin wire must contain exactly endByte,nodeId,sourcePath,startByte"
  | _ => throw "diagnostic-origin wire must be an object"

end DiagnosticOriginV1

namespace RequirementKeyV1

def validate (key : RequirementKeyV1) : Except String Unit := do
  unless 1 ≤ key.id.utf8ByteSize && key.id.utf8ByteSize ≤ 127 do
    throw "requirement key id must contain 1..127 UTF-8 bytes"
  validateSemVer key.version
  validateDigest key.digest

def toPfJson (key : RequirementKeyV1) : Except String PfJson := do
  validate key
  let version ← renderSemVer key.version
  let digest ← renderDigest key.digest
  pure (.object #[
    ("digest", .string digest),
    ("id", .string key.id),
    ("version", .string version)
  ])

def fromPfJson (value : PfJson) : Except String RequirementKeyV1 := do
  match value with
  | .object fields =>
    match fields.toList with
    | [("digest", .string digestValue), ("id", .string id),
        ("version", .string versionValue)] =>
      let version ← parseSemVer versionValue
      let digest ← parseDigest digestValue
      let key := { id, version, digest }
      validate key
      pure key
    | _ => throw "requirement key wire must contain exactly digest,id,version"
  | _ => throw "requirement key wire must be an object"

end RequirementKeyV1

namespace ExtensionKeyV1

def validate (key : ExtensionKeyV1) : Except String Unit := do
  unless 1 ≤ key.id.utf8ByteSize && key.id.utf8ByteSize ≤ 127 do
    throw "extension key id must contain 1..127 UTF-8 bytes"
  validateSemVer key.version
  validateDigest key.digest

def toPfJson (key : ExtensionKeyV1) : Except String PfJson := do
  validate key
  let version ← renderSemVer key.version
  let digest ← renderDigest key.digest
  pure (.object #[
    ("digest", .string digest),
    ("id", .string key.id),
    ("version", .string version)
  ])

def fromPfJson (value : PfJson) : Except String ExtensionKeyV1 := do
  match value with
  | .object fields =>
    match fields.toList with
    | [("digest", .string digestValue), ("id", .string id),
        ("version", .string versionValue)] =>
      let version ← parseSemVer versionValue
      let digest ← parseDigest digestValue
      let key := { id, version, digest }
      validate key
      pure key
    | _ => throw "extension key wire must contain exactly digest,id,version"
  | _ => throw "extension key wire must be an object"

end ExtensionKeyV1

namespace DiagnosticV1

/-- Sort related origins and remove adjacent duplicates under origin total order. -/
def normalizeRelated (related : Array DiagnosticOriginV1) : Array DiagnosticOriginV1 :=
  let sorted := related.qsort (fun a b => DiagnosticOriginV1.compare a b == .lt)
  sorted.foldl (fun acc o =>
    if acc.size > 0 && acc[acc.size - 1]! == o then acc else acc.push o) #[]

/-- Smart constructor: default severity/phase from code; normalize related.
    Named `make` so it does not collide with the structure constructor `.mk`. -/
def make
    (code : DiagnosticCodeV1)
    (message : String)
    (primary : Option DiagnosticOriginV1 := none)
    (related : Array DiagnosticOriginV1 := #[])
    (program : Option QualifiedName := none)
    (target : Option TargetId := none)
    (requirement : Option RequirementKeyV1 := none)
    (extension : Option ExtensionKeyV1 := none)
    (expected : Option PfJson := none)
    (actual : Option PfJson := none)
    (context : Option PfJson := none)
    (stableContext : Option String := none)
    (suggestion : Option String := none)
    (severity : Option DiagnosticSeverityV1 := none)
    (phase : Option DiagnosticPhaseV1 := none) :
    DiagnosticV1 :=
  { schemaVersion := 1
    code
    severity := severity.getD code.defaultSeverity
    phase := phase.getD code.defaultPhase
    message
    primary
    related := normalizeRelated related
    program
    target
    requirement
    extension
    expected
    actual
    context
    stableContext
    suggestion }

/-- Human rendering matching today's `{PF-*}: {message}` lines (byte-identical). -/
def renderHuman (diag : DiagnosticV1) : String :=
  s!"{diag.code.wire}: {diag.message}"

/-- Order-key stableContext: `none` and explicit `""` are the same key. -/
def orderStableContext (diag : DiagnosticV1) : String :=
  diag.stableContext.getD ""

def orderSourcePath (diag : DiagnosticV1) : String :=
  match diag.primary with
  | some o => o.sourcePath.value
  | none => ""

def orderStartByte (diag : DiagnosticV1) : UInt64 :=
  match diag.primary with
  | some o => o.startByte
  | none => 0

/-- Message-independent order/dedupe key. -/
def compareOrderKey (left right : DiagnosticV1) : Ordering :=
  let lp := orderSourcePath left
  let rp := orderSourcePath right
  if lp < rp then .lt
  else if lp > rp then .gt
  else if (orderStartByte left).toNat < (orderStartByte right).toNat then .lt
  else if (orderStartByte left).toNat > (orderStartByte right).toNat then .gt
  else if left.code.wire < right.code.wire then .lt
  else if left.code.wire > right.code.wire then .gt
  else if orderStableContext left < orderStableContext right then .lt
  else if orderStableContext left > orderStableContext right then .gt
  else .eq

private def compareOptionString (left right : Option String) : Ordering :=
  match left, right with
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some l, some r =>
      if l < r then .lt else if l > r then .gt else .eq

private def compareOptionOrigin (left right : Option DiagnosticOriginV1) : Ordering :=
  match left, right with
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some l, some r => DiagnosticOriginV1.compare l r

private def compareOriginArray (left right : Array DiagnosticOriginV1) : Ordering :=
  let n := min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      match DiagnosticOriginV1.compare left[i]! right[i]! with
      | .lt => .lt
      | .gt => .gt
      | .eq => loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

private def compareOptionTarget (left right : Option TargetId) : Ordering :=
  match left, right with
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some l, some r =>
      if l.toString < r.toString then .lt
      else if l.toString > r.toString then .gt
      else .eq

private def compareOptionQualified (left right : Option QualifiedName) : Ordering :=
  match left, right with
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some l, some r =>
      let ls := l.components.toArray
      let rs := r.components.toArray
      let n := min ls.size rs.size
      let rec loop (i : Nat) : Ordering :=
        if i < n then
          if ls[i]! < rs[i]! then .lt
          else if ls[i]! > rs[i]! then .gt
          else loop (i + 1)
        else if ls.size < rs.size then .lt
        else if ls.size > rs.size then .gt
        else .eq
      loop 0

/-- Lexicographic string-array order for SemVer prerelease/build wire identity. -/
private def compareStringArray (left right : Array String) : Ordering :=
  let n := min left.size right.size
  let rec loop (i : Nat) : Ordering :=
    if i < n then
      if left[i]! < right[i]! then .lt
      else if left[i]! > right[i]! then .gt
      else loop (i + 1)
    else if left.size < right.size then .lt
    else if left.size > right.size then .gt
    else .eq
  loop 0

/-- Full SemVer wire identity: major/minor/patch then prerelease then build arrays.
    Distinct from SemVer *precedence* (which ignores build); used for total order. -/
private def compareSemVerFields (l r : SemVer) : Ordering :=
  if l.major.toNat < r.major.toNat then .lt
  else if l.major.toNat > r.major.toNat then .gt
  else if l.minor.toNat < r.minor.toNat then .lt
  else if l.minor.toNat > r.minor.toNat then .gt
  else if l.patch.toNat < r.patch.toNat then .lt
  else if l.patch.toNat > r.patch.toNat then .gt
  else
    match compareStringArray l.prerelease r.prerelease with
    | .lt => .lt | .gt => .gt
    | .eq => compareStringArray l.build r.build

/-- ByteArray total order (local; DiagnosticOriginV1's helper is private). -/
private def compareByteArray (left right : ByteArray) : Ordering :=
  if left.size < right.size then .lt
  else if left.size > right.size then .gt
  else
    let rec loop (i : Nat) : Ordering :=
      if i < left.size then
        let byteL := left.get! i
        let byteR := right.get! i
        if byteL.toNat < byteR.toNat then .lt
        else if byteL.toNat > byteR.toNat then .gt
        else loop (i + 1)
      else
        .eq
    loop 0

/-- Digest total order: algorithm (sole `sha256` today) then raw 32-byte order. -/
private def compareDigest (left right : Digest) : Ordering :=
  match left.algorithm, right.algorithm with
  | .sha256, .sha256 => compareByteArray left.bytes right.bytes

private def compareOptionReq (left right : Option RequirementKeyV1) : Ordering :=
  match left, right with
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some l, some r =>
      if l.id < r.id then .lt
      else if l.id > r.id then .gt
      else
        match compareSemVerFields l.version r.version with
        | .lt => .lt | .gt => .gt
        | .eq => compareDigest l.digest r.digest

private def compareOptionExt (left right : Option ExtensionKeyV1) : Ordering :=
  match left, right with
  | none, none => .eq
  | none, some _ => .lt
  | some _, none => .gt
  | some l, some r =>
      if l.id < r.id then .lt
      else if l.id > r.id then .gt
      else
        match compareSemVerFields l.version r.version with
        | .lt => .lt | .gt => .gt
        | .eq => compareDigest l.digest r.digest

/-- Render optional PfJson for total-order tie-break (deterministic). -/
private def renderOptJson (v : Option PfJson) : String :=
  match v with
  | none => ""
  | some j =>
      match renderPfJcs j with
      | .ok s => s
      | .error _ => ""

/-- Total order used for stable sort: order key first, then structural fields,
    then message last.  Equal order keys never rely on qsort instability. -/
def compare (left right : DiagnosticV1) : Ordering :=
  match compareOrderKey left right with
  | .lt => .lt
  | .gt => .gt
  | .eq =>
    if left.severity.rank < right.severity.rank then .lt
    else if left.severity.rank > right.severity.rank then .gt
    else if left.phase.rank < right.phase.rank then .lt
    else if left.phase.rank > right.phase.rank then .gt
    else
      match compareOptionOrigin left.primary right.primary with
      | .lt => .lt | .gt => .gt
      | .eq =>
        match compareOriginArray
            (normalizeRelated left.related) (normalizeRelated right.related) with
        | .lt => .lt | .gt => .gt
        | .eq =>
          match compareOptionQualified left.program right.program with
          | .lt => .lt | .gt => .gt
          | .eq =>
            match compareOptionTarget left.target right.target with
            | .lt => .lt | .gt => .gt
            | .eq =>
              match compareOptionReq left.requirement right.requirement with
              | .lt => .lt | .gt => .gt
              | .eq =>
                match compareOptionExt left.extension right.extension with
                | .lt => .lt | .gt => .gt
                | .eq =>
                  let le := renderOptJson left.expected
                  let re := renderOptJson right.expected
                  if le < re then .lt else if le > re then .gt
                  else
                    let la := renderOptJson left.actual
                    let ra := renderOptJson right.actual
                    if la < ra then .lt else if la > ra then .gt
                    else
                      let lc := renderOptJson left.context
                      let rc := renderOptJson right.context
                      if lc < rc then .lt else if lc > rc then .gt
                      else
                        match compareOptionString left.suggestion right.suggestion with
                        | .lt => .lt | .gt => .gt
                        | .eq =>
                          if left.message < right.message then .lt
                          else if left.message > right.message then .gt
                          else .eq

/-- Stable sort by total `compare`, then adjacent dedupe by **order key only**
    (message-independent).  Representative is the total-order minimum. -/
def sortAndDedupe (diagnostics : Array DiagnosticV1) : Array DiagnosticV1 :=
  let sorted := diagnostics.qsort (fun a b => compare a b == .lt)
  sorted.foldl (fun acc d =>
    if acc.size > 0 && compareOrderKey acc[acc.size - 1]! d == .eq then acc
    else acc.push d) #[]

private def optionToPfJson
    (encode : α → Except String PfJson) (value : Option α) :
    Except String PfJson :=
  match value with
  | none => pure .null
  | some v => encode v

private def targetToPfJson (t : TargetId) : Except String PfJson :=
  pure (.string t.toString)

private def targetFromPfJson (value : PfJson) : Except String TargetId :=
  match value with
  | .string s =>
      match TargetId.parse? s with
      | some t => pure t
      | none => throw s!"unknown target id '{s}'"
  | _ => throw "target must be a string"

private def programToPfJson (name : QualifiedName) : Except String PfJson := do
  let components ← renderQualifiedNameComponents name
  pure (.array (components.map PfJson.string))

private def programFromPfJson (value : PfJson) : Except String QualifiedName := do
  match value with
  | .array values =>
    let mut components := #[]
    for v in values do
      match v with
      | .string c => components := components.push c
      | _ => throw "program wire components must be strings"
    parseQualifiedName components
  | _ => throw "program wire must be an array"

/-- Structural validation of a diagnostic (paths/ranges/ids/noncanonical
    identities).  No generic secret scanning. -/
def validate (diag : DiagnosticV1) : Except String Unit := do
  unless diag.schemaVersion == 1 do
    throw "diagnostic schemaVersion must be 1"
  match diag.primary with
  | none => pure ()
  | some o => DiagnosticOriginV1.validate o
  for o in diag.related do
    DiagnosticOriginV1.validate o
  match diag.program with
  | none => pure ()
  | some p => validateQualifiedName p
  match diag.requirement with
  | none => pure ()
  | some r => RequirementKeyV1.validate r
  match diag.extension with
  | none => pure ()
  | some e => ExtensionKeyV1.validate e

/-- Build the exact all-field PF-JCS object (Option fields as null). -/
def toPfJson (diag : DiagnosticV1) : Except String PfJson := do
  validate diag
  let primaryJson ← optionToPfJson DiagnosticOriginV1.toPfJson diag.primary
  let relatedJson ← (normalizeRelated diag.related).mapM DiagnosticOriginV1.toPfJson
  let programJson ← optionToPfJson programToPfJson diag.program
  let targetJson ← optionToPfJson targetToPfJson diag.target
  let requirementJson ← optionToPfJson RequirementKeyV1.toPfJson diag.requirement
  let extensionJson ← optionToPfJson ExtensionKeyV1.toPfJson diag.extension
  let expectedJson := match diag.expected with | none => PfJson.null | some v => v
  let actualJson := match diag.actual with | none => PfJson.null | some v => v
  let contextJson := match diag.context with | none => PfJson.null | some v => v
  let stableJson :=
    match diag.stableContext with
    | none => PfJson.null
    | some s => .string s
  let suggestionJson :=
    match diag.suggestion with
    | none => PfJson.null
    | some s => .string s
  pure (.object #[
    ("actual", actualJson),
    ("code", .string diag.code.wire),
    ("context", contextJson),
    ("expected", expectedJson),
    ("extension", extensionJson),
    ("message", .string diag.message),
    ("phase", .string diag.phase.wire),
    ("primary", primaryJson),
    ("program", programJson),
    ("related", .array relatedJson),
    ("requirement", requirementJson),
    ("schemaVersion", .int (Int.ofNat diag.schemaVersion)),
    ("severity", .string diag.severity.wire),
    ("stableContext", stableJson),
    ("suggestion", suggestionJson),
    ("target", targetJson)
  ])

def toCanonicalJson (diag : DiagnosticV1) : Except String String := do
  let value ← toPfJson diag
  renderPfJcs value

private def parseOptionField
    (parse : PfJson → Except String α)
    (value : PfJson) : Except String (Option α) :=
  match value with
  | .null => pure none
  | other => some <$> parse other

/-- Decode a PF-JCS diagnostic object.  Rejects unknown fields/enums/schema
    via exact field-set match; caller re-encodes for noncanonical identity. -/
def fromPfJson (value : PfJson) : Except String DiagnosticV1 := do
  match value with
  | .object fields =>
    -- Exact 16-field set in UTF-16 / string order (as required by PF-JCS).
    match fields.toList with
    | [("actual", actualJson),
        ("code", .string codeWire),
        ("context", contextJson),
        ("expected", expectedJson),
        ("extension", extensionJson),
        ("message", .string message),
        ("phase", .string phaseWire),
        ("primary", primaryJson),
        ("program", programJson),
        ("related", relatedJson),
        ("requirement", requirementJson),
        ("schemaVersion", .int schemaInt),
        ("severity", .string severityWire),
        ("stableContext", stableJson),
        ("suggestion", suggestionJson),
        ("target", targetJson)] =>
      unless schemaInt == 1 do
        throw "diagnostic schemaVersion must be 1"
      let code ← match DiagnosticCodeV1.parse codeWire with
        | some c => pure c
        | none => throw s!"unknown diagnostic code '{codeWire}'"
      let severity ← match DiagnosticSeverityV1.parse severityWire with
        | some s => pure s
        | none => throw s!"unknown diagnostic severity '{severityWire}'"
      let phase ← match DiagnosticPhaseV1.parse phaseWire with
        | some p => pure p
        | none => throw s!"unknown diagnostic phase '{phaseWire}'"
      let primary ← parseOptionField DiagnosticOriginV1.fromPfJson primaryJson
      let related ← match relatedJson with
        | .array arr => arr.mapM DiagnosticOriginV1.fromPfJson
        | _ => throw "related must be an array"
      let program ← parseOptionField programFromPfJson programJson
      let target ← parseOptionField targetFromPfJson targetJson
      let requirement ← parseOptionField RequirementKeyV1.fromPfJson requirementJson
      let extension ← parseOptionField ExtensionKeyV1.fromPfJson extensionJson
      let expected ← match expectedJson with
        | .null => pure none
        | v => pure (some v)
      let actual ← match actualJson with
        | .null => pure none
        | v => pure (some v)
      let context ← match contextJson with
        | .null => pure none
        | v => pure (some v)
      let stableContext ← match stableJson with
        | .null => pure none
        | .string s => pure (some s)
        | _ => throw "stableContext must be string or null"
      let suggestion ← match suggestionJson with
        | .null => pure none
        | .string s => pure (some s)
        | _ => throw "suggestion must be string or null"
      let diag : DiagnosticV1 := {
        schemaVersion := 1
        code
        severity
        phase
        message
        primary
        related := normalizeRelated related
        program
        target
        requirement
        extension
        expected
        actual
        context
        stableContext
        suggestion
      }
      validate diag
      pure diag
    | _ => throw "diagnostic wire must contain exactly the SPEC-DIAG-001 field set"
  | _ => throw "diagnostic wire must be an object"

/-- Parse canonical PF-JCS text; reject noncanonical spelling via re-encode identity. -/
def fromCanonicalJson (input : String) : Except String DiagnosticV1 := do
  let value ← parsePfJcs input
  let diag ← fromPfJson value
  let reencoded ← toCanonicalJson diag
  unless reencoded == input do
    throw "diagnostic JSON is noncanonical"
  pure diag

/-- Maximum retained diagnostics before the PF-DIAG-LIMIT sentinel. -/
def maxDiagnosticsV1 : Nat := 100

private def isDiagLimit (d : DiagnosticV1) : Bool :=
  d.code == .diagLimit

private def limitSentinel : DiagnosticV1 :=
  make .diagLimit "diagnostic limit exceeded; remaining diagnostics truncated"

/-- Sort/dedupe, then retain at most 100 non-limit diagnostics and append exactly
    one deterministic `PF-DIAG-LIMIT` when truncated.  Idempotent under re-run.
    Unused by product pipelines until B7/B8. -/
def normalizeDiagnosticBundleV1 (diagnostics : Array DiagnosticV1) : Array DiagnosticV1 :=
  let hadLimit := diagnostics.any isDiagLimit
  let core := sortAndDedupe (diagnostics.filter (fun d => !isDiagLimit d))
  let truncated := core.size > maxDiagnosticsV1 || (hadLimit && core.size ≥ maxDiagnosticsV1)
  let kept :=
    if core.size > maxDiagnosticsV1 then core.extract 0 maxDiagnosticsV1 else core
  if truncated then kept.push limitSentinel else kept

end DiagnosticV1

end ProofForgeV2.Core.DiagnosticV1
