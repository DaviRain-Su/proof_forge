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
  bytes : ByteArray
  deriving DecidableEq

/-- Validate the fixed-width invariant after any direct `Digest` construction. -/
def validateDigest (digest : Digest) : Except String Unit := do
  unless digest.bytes.size = 32 do
    throw "digest must contain exactly 32 raw bytes"

private def isLowerHex (c : Char) : Bool :=
  ('0' ≤ c ∧ c ≤ '9') ∨ ('a' ≤ c ∧ c ≤ 'f')

private def lowerHexNibble? (c : Char) : Option UInt8 :=
  if '0' ≤ c && c ≤ '9' then
    some (UInt8.ofNat (c.toNat - '0'.toNat))
  else if 'a' ≤ c && c ≤ 'f' then
    some (UInt8.ofNat (10 + c.toNat - 'a'.toNat))
  else
    none

private def decodeLowerHex : List Char → Except String (List UInt8)
  | [] => pure []
  | high :: low :: rest => do
    let highNibble ← match lowerHexNibble? high with
      | some value => pure value
      | none => throw "digest hex must be lowercase [0-9a-f]"
    let lowNibble ← match lowerHexNibble? low with
      | some value => pure value
      | none => throw "digest hex must be lowercase [0-9a-f]"
    let tail ← decodeLowerHex rest
    pure ((highNibble * 16 + lowNibble) :: tail)
  | _ => throw "digest hex must contain complete byte pairs"

private def lowerHexDigit (n : Nat) : Char :=
  if n < 10 then Char.ofNat ('0'.toNat + n)
  else Char.ofNat ('a'.toNat + n - 10)

private def encodeLowerHex (bytes : ByteArray) : String :=
  bytes.foldl (fun result byte =>
    let value := byte.toNat
    (result.push (lowerHexDigit (value / 16))).push (lowerHexDigit (value % 16))) ""

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
  let raw ← decodeLowerHex hex.toList
  let bytes := ByteArray.mk raw.toArray
  let digest := { algorithm := .sha256, bytes }
  validateDigest digest
  pure digest

/-- Render the exact lowercase digest wire form, rejecting invalid direct construction. -/
def renderDigest (digest : Digest) : Except String String := do
  validateDigest digest
  match digest.algorithm with
  | .sha256 => pure ("sha256:" ++ encodeLowerHex digest.bytes)

structure SemVer where
  major : UInt64
  minor : UInt64
  patch : UInt64
  prerelease : Array String := #[]
  build : Array String := #[]
  deriving DecidableEq, Repr

private def isAsciiDigit (c : Char) : Bool :=
  '0' ≤ c && c ≤ '9'

private def isAsciiLetter (c : Char) : Bool :=
  ('a' ≤ c && c ≤ 'z') || ('A' ≤ c && c ≤ 'Z')

private def isSemVerIdentifierChar (c : Char) : Bool :=
  isAsciiDigit c || isAsciiLetter c || c = '-'

private def parseUInt64NoLeadingZero (s : String) : Except String UInt64 := do
  if s.isEmpty then throw "empty numeric component"
  if s ≠ "0" && s.startsWith "0" then throw "leading zero forbidden"
  unless s.all isAsciiDigit do
    throw "numeric component must contain ASCII digits only"
  if s.length > 20 || (s.length = 20 && s > "18446744073709551615") then
    throw "numeric component exceeds UInt64"
  match s.toNat? with
  | some n =>
    unless n < UInt64.size do
      throw "numeric component exceeds UInt64"
    pure (UInt64.ofNat n)
  | none => throw "invalid numeric component"

private def splitOnce (s : String) (separator : Char) : String × Option String :=
  let (before, rest) := s.toList.span (fun c => c != separator)
  match rest with
  | [] => (String.ofList before, none)
  | _ :: suffix => (String.ofList before, some (String.ofList suffix))

private def validateSemVerIdentifier
    (kind identifier : String) (numericLeadingZerosAllowed : Bool) : Except String Unit := do
  if identifier.isEmpty then
    throw s!"semver {kind} identifier must not be empty"
  unless identifier.all isSemVerIdentifierChar do
    throw s!"semver {kind} identifier contains an invalid character"
  if !numericLeadingZerosAllowed && identifier.all isAsciiDigit &&
      identifier.length > 1 && identifier.startsWith "0" then
    throw "numeric prerelease identifier must not contain a leading zero"

private def parseSemVerIdentifiers
    (kind value : String) (numericLeadingZerosAllowed : Bool) : Except String (Array String) := do
  if value.isEmpty then
    throw s!"semver {kind} must not be empty"
  let identifiers := value.splitOn "."
  for identifier in identifiers do
    validateSemVerIdentifier kind identifier numericLeadingZerosAllowed
  pure identifiers.toArray

/-- Parse the exact SemVer 2.0.0 wire grammar with UInt64 core components. -/
def parseSemVer (s : String) : Except String SemVer := do
  if s.startsWith "v" then
    throw "v prefix forbidden"
  let (versionAndPrerelease, buildValue) := splitOnce s '+'
  let build ← match buildValue with
    | none => pure #[]
    | some value => parseSemVerIdentifiers "build" value true
  let (coreValue, prereleaseValue) := splitOnce versionAndPrerelease '-'
  let prerelease ← match prereleaseValue with
    | none => pure #[]
    | some value => parseSemVerIdentifiers "prerelease" value false
  let core := coreValue.splitOn "."
  unless core.length = 3 do
    throw "semver core requires major.minor.patch"
  let major ← parseUInt64NoLeadingZero core[0]!
  let minor ← parseUInt64NoLeadingZero core[1]!
  let patch ← parseUInt64NoLeadingZero core[2]!
  pure { major, minor, patch, prerelease, build }

/-- Parse a SemVer core while rejecting prerelease and build suffixes. -/
def parseSemVerCore (s : String) : Except String SemVer := do
  let version ← parseSemVer s
  unless version.prerelease.isEmpty && version.build.isEmpty do
    throw "semver core must not contain prerelease or build metadata"
  pure version

/-- Reject directly constructed `SemVer` values that do not satisfy the wire grammar. -/
def validateSemVer (version : SemVer) : Except String Unit := do
  for identifier in version.prerelease do
    validateSemVerIdentifier "prerelease" identifier false
  for identifier in version.build do
    validateSemVerIdentifier "build" identifier true

private def renderSemVerUnchecked (version : SemVer) : String :=
  let core := s!"{version.major}.{version.minor}.{version.patch}"
  let withPrerelease :=
    if version.prerelease.isEmpty then core
    else core ++ "-" ++ String.intercalate "." version.prerelease.toList
  if version.build.isEmpty then withPrerelease
  else withPrerelease ++ "+" ++ String.intercalate "." version.build.toList

/-- Render the unique canonical SemVer ASCII wire form, failing closed on invalid values. -/
def renderSemVer (version : SemVer) : Except String String := do
  validateSemVer version
  pure (renderSemVerUnchecked version)

private def compareSemVerIdentifier (left right : String) : Ordering :=
  let leftNumeric := left.all isAsciiDigit
  let rightNumeric := right.all isAsciiDigit
  if leftNumeric && rightNumeric then
    match compare left.length right.length with
    | .eq => compare left right
    | order => order
  else if leftNumeric then
    .lt
  else if rightNumeric then
    .gt
  else
    compare left right

private def comparePrerelease : List String → List String → Ordering
  | [], [] => .eq
  | [], _ :: _ => .lt
  | _ :: _, [] => .gt
  | left :: leftRest, right :: rightRest =>
    match compareSemVerIdentifier left right with
    | .eq => comparePrerelease leftRest rightRest
    | order => order

/-- Compare validated SemVer precedence. Build metadata is intentionally ignored. -/
private def compareSemVerPrecedenceUnchecked (left right : SemVer) : Ordering :=
  match compare left.major right.major with
  | .lt => .lt
  | .gt => .gt
  | .eq =>
    match compare left.minor right.minor with
    | .lt => .lt
    | .gt => .gt
    | .eq =>
      match compare left.patch right.patch with
      | .lt => .lt
      | .gt => .gt
      | .eq =>
        if left.prerelease.isEmpty then
          if right.prerelease.isEmpty then .eq else .gt
        else if right.prerelease.isEmpty then
          .lt
        else
          comparePrerelease left.prerelease.toList right.prerelease.toList

/-- Compare SemVer precedence, failing closed on directly constructed invalid values. -/
def compareSemVerPrecedence (left right : SemVer) : Except String Ordering := do
  validateSemVer left
  validateSemVer right
  pure (compareSemVerPrecedenceUnchecked left right)

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
