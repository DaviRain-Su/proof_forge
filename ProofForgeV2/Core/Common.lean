/-
  SPEC-COMMON-001 minimal Lean surface for TASK-D0-06 / TST-COMMON-001.
  Full wire/JCS authority remains docs/specs/common-types.md; this module provides
  exact parse/validate helpers used by later stages.
-/
namespace ProofForgeV2.Core.Common

inductive DigestAlgorithm where
  | sha256
  deriving DecidableEq, Repr

structure Digest where
  algorithm : DigestAlgorithm
  hex : String
  deriving DecidableEq, Repr

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c ∧ c ≤ '9') ∨ ('a' ≤ c ∧ c ≤ 'f')

/-- Parse `sha256:<64 lowercase hex>`; reject uppercase, bare hex, and wrong lengths. -/
def parseDigest (s : String) : Except String Digest := do
  let tag := "sha256:"
  unless s.startsWith tag do
    throw "digest must use sha256: tag"
  unless s.length = tag.length + 64 do
    throw "digest hex must be exactly 64 lowercase characters"
  let hex := String.ofList (s.toList.drop tag.length)
  unless hex.all isLowerHex do
    throw "digest hex must be lowercase [0-9a-f]"
  pure { algorithm := .sha256, hex }

structure SemVer where
  major : Nat
  minor : Nat
  patch : Nat
  deriving DecidableEq, Repr

private def parseNatNoLeadingZero (s : String) : Except String Nat := do
  if s.isEmpty then throw "empty numeric component"
  if s ≠ "0" && s.startsWith "0" then throw "leading zero forbidden"
  match s.toNat? with
  | some n => pure n
  | none => throw "invalid numeric component"

/-- Minimal SemVer core `MAJOR.MINOR.PATCH` without prerelease/build. -/
def parseSemVerCore (s : String) : Except String SemVer := do
  if s.startsWith "v" then throw "v prefix forbidden"
  let parts := s.splitOn "."
  unless parts.length = 3 do
    throw "semver core requires major.minor.patch"
  let major ← parseNatNoLeadingZero parts[0]!
  let minor ← parseNatNoLeadingZero parts[1]!
  let patch ← parseNatNoLeadingZero parts[2]!
  pure { major, minor, patch }

inductive ResourceStage where
  | frontend
  | compilerCore
  | externalTool
  | artifactOutput
  deriving DecidableEq, Repr

inductive MemoryMetric where
  | darwinPhysFootprintAggregate
  | linuxCgroupMemoryCurrent
  | jobObjectCommitAggregate
  deriving DecidableEq, Repr

structure ResourceProfileV1 where
  schema : String
  profileId : String
  stage : ResourceStage
  maxWallMillis : UInt64
  maxAggregateMemoryBytes : UInt64
  memoryMetric : MemoryMetric
  maxProcesses : UInt32
  maxProtocolBytes : UInt64
  maxStderrBytes : UInt64
  maxPublishedBytes : UInt64
  deriving DecidableEq, Repr

def resourceProfileSchema : String := "proof-forge.resource-profile.v1"

def frontendProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := "proof-forge.resource.frontend.v1"
    stage := .frontend
    maxWallMillis := 10000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

def coreProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := "proof-forge.resource.core.v1"
    stage := .compilerCore
    maxWallMillis := 30000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

/-- Hard-maxima check: effective budgets must not exceed the named hard profile. -/
def validateNotAboveHardMax (hard effective : ResourceProfileV1) : Except String Unit := do
  unless effective.schema = resourceProfileSchema do
    throw "resource profile schema mismatch"
  unless effective.stage = hard.stage do
    throw "resource profile stage mismatch"
  unless effective.maxWallMillis ≤ hard.maxWallMillis do
    throw "wall budget exceeds hard maximum"
  unless effective.maxAggregateMemoryBytes ≤ hard.maxAggregateMemoryBytes do
    throw "memory budget exceeds hard maximum"
  unless effective.maxProcesses ≤ hard.maxProcesses do
    throw "process budget exceeds hard maximum"
  unless effective.maxProtocolBytes ≤ hard.maxProtocolBytes do
    throw "protocol budget exceeds hard maximum"
  unless effective.maxStderrBytes ≤ hard.maxStderrBytes do
    throw "stderr budget exceeds hard maximum"
  unless effective.maxPublishedBytes ≤ hard.maxPublishedBytes do
    throw "published budget exceeds hard maximum"
  pure ()

end ProofForgeV2.Core.Common
