import Init.Meta
import ProofForgeV2.Core.Canonical
import ProofForgeV2.Core.Crypto
import ProofForgeV2.Core.Unicode

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

instance : Repr Digest where
  reprPrec digest _ :=
    (Std.Format.text "{ algorithm := ").append (repr digest.algorithm)
      |>.append (Std.Format.text ", bytes := ")
      |>.append (repr digest.bytes.data)
      |>.append (Std.Format.text " }")

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

structure NonEmptyArray (α : Type u) where
  head : α
  tail : Array α
  deriving DecidableEq, Repr

namespace NonEmptyArray

def ofArray (values : Array α) : Except String (NonEmptyArray α) :=
  if h : 0 < values.size then
    .ok { head := values[0], tail := values.extract 1 values.size }
  else
    .error "array must contain at least one value"

def toArray (values : NonEmptyArray α) : Array α :=
  #[values.head] ++ values.tail

end NonEmptyArray

structure SchemaId where
  value : String
  deriving DecidableEq, Repr

structure EvidenceId where
  value : String
  deriving DecidableEq, Repr

structure AcceptanceProfileId where
  value : String
  deriving DecidableEq, Repr

structure NodeId where
  bytes : ByteArray
  deriving DecidableEq

instance : Repr NodeId where
  reprPrec nodeId _ :=
    (Std.Format.text "{ bytes := ").append (repr nodeId.bytes.data)
      |>.append (Std.Format.text " }")

structure ProjectRelativePath where
  value : String
  deriving DecidableEq, Repr

structure QualifiedName where
  components : NonEmptyArray String
  deriving DecidableEq, Repr

structure ContentRef where
  schema : SchemaId
  id : String
  version : SemVer
  digest : Digest
  deriving DecidableEq, Repr

structure SourceOrigin where
  sourcePath : ProjectRelativePath
  startByte : UInt64
  endByte : UInt64
  nodeId : NodeId
  deriving DecidableEq, Repr

structure UtcInstant where
  value : String
  deriving DecidableEq, Repr

private def isLowerAsciiLetter (c : Char) : Bool :=
  'a' ≤ c && c ≤ 'z'

private def isLowerAsciiAlphanumeric (c : Char) : Bool :=
  isLowerAsciiLetter c || isAsciiDigit c

private def validSeparatedRest
    (isSeparator : Char → Bool) : List Char → Bool → Bool
  | [], previousWasSeparator => !previousWasSeparator
  | c :: rest, previousWasSeparator =>
    if isLowerAsciiAlphanumeric c then
      validSeparatedRest isSeparator rest false
    else if isSeparator c && !previousWasSeparator then
      validSeparatedRest isSeparator rest true
    else
      false

private def validSeparatedId (value : String) (isSeparator : Char → Bool) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
    isLowerAsciiLetter first && validSeparatedRest isSeparator rest false

private def validSchemaSegment (value : String) : Bool :=
  validSeparatedId value (· == '-')

def validateSchemaId (schema : SchemaId) : Except String Unit := do
  let value := schema.value
  unless 1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 127 do
    throw "schema id must contain 1..127 UTF-8 bytes"
  unless value.toList.any (· == '.') do
    throw "schema id must contain at least one dot"
  unless (value.splitOn ".").all validSchemaSegment do
    throw "schema id has an invalid segment"

def parseSchemaId (value : String) : Except String SchemaId := do
  let schema := { value }
  validateSchemaId schema
  pure schema

def renderSchemaId (schema : SchemaId) : Except String String := do
  validateSchemaId schema
  pure schema.value

def validateProfileIdValue (value : String) : Except String Unit := do
  unless 1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 127 do
    throw "profile id must contain 1..127 UTF-8 bytes"
  unless validSeparatedId value (fun c => c == '-' || c == '.') do
    throw "profile id has an invalid spelling"

def validateAcceptanceProfileId (profile : AcceptanceProfileId) : Except String Unit :=
  validateProfileIdValue profile.value

def parseAcceptanceProfileId (value : String) : Except String AcceptanceProfileId := do
  let profile := { value }
  validateAcceptanceProfileId profile
  pure profile

def renderAcceptanceProfileId (profile : AcceptanceProfileId) : Except String String := do
  validateAcceptanceProfileId profile
  pure profile.value

private def isGregorianLeapYear (year : Nat) : Bool :=
  year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)

private def daysInGregorianMonth (year month : Nat) : Nat :=
  match month with
  | 1 | 3 | 5 | 7 | 8 | 10 | 12 => 31
  | 4 | 6 | 9 | 11 => 30
  | 2 => if isGregorianLeapYear year then 29 else 28
  | _ => 0

private def validateGregorianDate (year month day : Nat) : Except String Unit := do
  unless 1 ≤ month && month ≤ 12 do
    throw "Gregorian month is out of range"
  let maximumDay := daysInGregorianMonth year month
  unless 1 ≤ day && day ≤ maximumDay do
    throw "Gregorian day is out of range"

private def parseAsciiDecimalSlice
    (chars : List Char) (start count : Nat) : Except String Nat := do
  let slice := (chars.drop start).take count
  unless slice.length = count && slice.all isAsciiDigit do
    throw "expected fixed-width ASCII decimal digits"
  match (String.ofList slice).toNat? with
  | some value => pure value
  | none => throw "invalid fixed-width ASCII decimal digits"

def validateEvidenceId (evidence : EvidenceId) : Except String Unit := do
  let value := evidence.value
  unless value.utf8ByteSize = 16 && value.length = 16 do
    throw "evidence id must have exact EV-YYYYMMDD-NNNN width"
  let chars := value.toList
  unless value.startsWith "EV-" && chars[11]! == '-' do
    throw "evidence id must use EV-YYYYMMDD-NNNN spelling"
  let year ← parseAsciiDecimalSlice chars 3 4
  let month ← parseAsciiDecimalSlice chars 7 2
  let day ← parseAsciiDecimalSlice chars 9 2
  let _ ← parseAsciiDecimalSlice chars 12 4
  validateGregorianDate year month day

def parseEvidenceId (value : String) : Except String EvidenceId := do
  let evidence := { value }
  validateEvidenceId evidence
  pure evidence

def renderEvidenceId (evidence : EvidenceId) : Except String String := do
  validateEvidenceId evidence
  pure evidence.value

def validateUtcInstant (instant : UtcInstant) : Except String Unit := do
  let value := instant.value
  unless value.utf8ByteSize = 20 && value.length = 20 do
    throw "UTC instant must have exact YYYY-MM-DDTHH:MM:SSZ width"
  let chars := value.toList
  unless chars[4]! == '-' && chars[7]! == '-' && chars[10]! == 'T' &&
      chars[13]! == ':' && chars[16]! == ':' && chars[19]! == 'Z' do
    throw "UTC instant must use YYYY-MM-DDTHH:MM:SSZ spelling"
  let year ← parseAsciiDecimalSlice chars 0 4
  let month ← parseAsciiDecimalSlice chars 5 2
  let day ← parseAsciiDecimalSlice chars 8 2
  let hour ← parseAsciiDecimalSlice chars 11 2
  let minute ← parseAsciiDecimalSlice chars 14 2
  let second ← parseAsciiDecimalSlice chars 17 2
  validateGregorianDate year month day
  unless hour < 24 do throw "UTC hour is out of range"
  unless minute < 60 do throw "UTC minute is out of range"
  unless second < 60 do throw "UTC second is out of range"

def parseUtcInstant (value : String) : Except String UtcInstant := do
  let instant := { value }
  validateUtcInstant instant
  pure instant

def renderUtcInstant (instant : UtcInstant) : Except String String := do
  validateUtcInstant instant
  pure instant.value

def validateNodeId (nodeId : NodeId) : Except String Unit := do
  unless nodeId.bytes.size = 16 do
    throw "node id must contain exactly 16 raw bytes"

def parseNodeId (value : String) : Except String NodeId := do
  let tag := "nodeid:"
  unless value.startsWith tag do
    throw "node id must use nodeid: tag"
  unless value.length = tag.length + 32 do
    throw "node id hex must contain exactly 32 lowercase characters"
  let hex := String.ofList (value.toList.drop tag.length)
  unless hex.all isLowerHex do
    throw "node id hex must be lowercase [0-9a-f]"
  let raw ← decodeLowerHex hex.toList
  let nodeId := { bytes := ByteArray.mk raw.toArray }
  validateNodeId nodeId
  pure nodeId

def renderNodeId (nodeId : NodeId) : Except String String := do
  validateNodeId nodeId
  pure ("nodeid:" ++ encodeLowerHex nodeId.bytes)

private def hasAsciiDrivePrefix (value : String) : Bool :=
  match value.toList with
  | first :: ':' :: '/' :: _ => isAsciiLetter first
  | _ => false

/-- Validate a lexical, NFC project-relative path without consulting a filesystem. -/
def validateProjectRelativePath (path : ProjectRelativePath) : Except String Unit := do
  let value := path.value
  unless 1 ≤ value.utf8ByteSize && value.utf8ByteSize ≤ 1024 do
    throw "project-relative path must contain 1..1024 UTF-8 bytes"
  ProofForgeV2.Core.Unicode.requireNfc value
  if value.startsWith "/" || hasAsciiDrivePrefix value then
    throw "project-relative path must not be absolute"
  if value.toList.any (· == '\\') then
    throw "project-relative path must use forward slashes"
  if value.toList.any ProofForgeV2.Core.Unicode.isUnicodeCc then
    throw "project-relative path must not contain a Cc code point"
  let segments := value.splitOn "/"
  if segments.any (fun segment => segment.isEmpty || segment == "." || segment == "..") then
    throw "project-relative path contains a forbidden segment"

def parseProjectRelativePath (value : String) : Except String ProjectRelativePath := do
  let path := { value }
  validateProjectRelativePath path
  pure path

def renderProjectRelativePath (path : ProjectRelativePath) : Except String String := do
  validateProjectRelativePath path
  pure path.value

/-- SPEC-COMMON-001 exact identifier component rule (Unicode 17 NFC, UTF-8
    length 1..240, not exact `_`, Lean.isIdFirst + Lean.isIdRest). Shared truth
    for QualifiedName components and SemanticProgramV1 declaration / field /
    parameter / invariant names (SPEC-SEM-WIRE-001 §6). Keyword reservation is
    owned by the producing syntax surface; this validator does not copy ambient
    parser keywords. -/
def validateIdentifierComponent (component : String) : Except String Unit := do
  unless 1 ≤ component.utf8ByteSize && component.utf8ByteSize ≤ 240 do
    throw "identifier component must contain 1..240 UTF-8 bytes"
  ProofForgeV2.Core.Unicode.requireNfc component
  if component == "_" then
    throw "identifier component must not be anonymous"
  match component.toList with
  | [] => throw "identifier component must not be empty"
  | first :: rest =>
    unless Lean.isIdFirst first && rest.all Lean.isIdRest do
      throw "identifier component must use Lean identifier characters"

/-- QualifiedName components use the exact shared identifier component rule. -/
private def validateQualifiedNameComponent (component : String) : Except String Unit :=
  validateIdentifierComponent component

def validateQualifiedName (name : QualifiedName) : Except String Unit := do
  let components := name.components.toArray
  unless components.size ≤ 256 do
    throw "qualified name must contain at most 256 components"
  for component in components do
    validateQualifiedNameComponent component

def parseQualifiedName (components : Array String) : Except String QualifiedName := do
  let nonempty ← NonEmptyArray.ofArray components
  let name := { components := nonempty }
  validateQualifiedName name
  pure name

def renderQualifiedNameComponents (name : QualifiedName) : Except String (Array String) := do
  validateQualifiedName name
  pure name.components.toArray

def renderQualifiedNameJcs (name : QualifiedName) : Except String String := do
  let components ← renderQualifiedNameComponents name
  renderPfJcs (.array (components.map PfJson.string))

def parseQualifiedNameJcs (input : String) : Except String QualifiedName := do
  let value ← parsePfJcs input
  match value with
  | .array values =>
    let mut components := #[]
    for value in values do
      match value with
      | .string component => components := components.push component
      | _ => throw "qualified-name wire components must be strings"
    parseQualifiedName components
  | _ => throw "qualified-name wire must be an array"

def validateContentRef (content : ContentRef) : Except String Unit := do
  validateSchemaId content.schema
  validateProfileIdValue content.id
  validateSemVer content.version
  validateDigest content.digest

def renderContentRefJcs (content : ContentRef) : Except String String := do
  validateContentRef content
  let digest ← renderDigest content.digest
  let schema ← renderSchemaId content.schema
  let version ← renderSemVer content.version
  renderPfJcs (.object #[
    ("schema", .string schema),
    ("id", .string content.id),
    ("version", .string version),
    ("digest", .string digest)
  ])

def parseContentRefJcs (input : String) : Except String ContentRef := do
  let value ← parsePfJcs input
  match value with
  | .object fields =>
    match fields.toList with
    | [("digest", .string digestValue), ("id", .string id),
        ("schema", .string schemaValue), ("version", .string versionValue)] =>
      let schema ← parseSchemaId schemaValue
      let version ← parseSemVer versionValue
      let digest ← parseDigest digestValue
      let content := { schema, id, version, digest }
      validateContentRef content
      pure content
    | _ => throw "content-ref wire must contain exactly digest,id,schema,version"
  | _ => throw "content-ref wire must be an object"

private def maxSafeJsonNat : Nat := 9007199254740991

private def uint64ToPfInt (label : String) (value : UInt64) : Except String Int := do
  let natural := value.toNat
  unless natural ≤ maxSafeJsonNat do
    throw s!"{label} exceeds the PF-JCS safe-integer range"
  pure (Int.ofNat natural)

private def pfIntToUInt64 (label : String) (value : Int) : Except String UInt64 := do
  if value < 0 then
    throw s!"{label} must be nonnegative"
  let natural := value.toNat
  unless natural ≤ maxSafeJsonNat do
    throw s!"{label} exceeds the PF-JCS safe-integer range"
  pure (UInt64.ofNat natural)

def validateSourceOrigin (origin : SourceOrigin) : Except String Unit := do
  validateProjectRelativePath origin.sourcePath
  validateNodeId origin.nodeId
  unless origin.startByte ≤ origin.endByte do
    throw "source-origin startByte must not exceed endByte"

def sourceOriginKey
    (origin : SourceOrigin) : Except String (String × UInt64 × UInt64 × ByteArray) := do
  validateSourceOrigin origin
  pure (origin.sourcePath.value, origin.startByte, origin.endByte, origin.nodeId.bytes)

def renderSourceOriginJcs (origin : SourceOrigin) : Except String String := do
  validateSourceOrigin origin
  let sourcePath ← renderProjectRelativePath origin.sourcePath
  let startByte ← uint64ToPfInt "source-origin startByte" origin.startByte
  let endByte ← uint64ToPfInt "source-origin endByte" origin.endByte
  let nodeId ← renderNodeId origin.nodeId
  renderPfJcs (.object #[
    ("sourcePath", .string sourcePath),
    ("startByte", .int startByte),
    ("endByte", .int endByte),
    ("nodeId", .string nodeId)
  ])

def parseSourceOriginJcs (input : String) : Except String SourceOrigin := do
  let value ← parsePfJcs input
  match value with
  | .object fields =>
    match fields.toList with
    | [("endByte", .int endValue), ("nodeId", .string nodeValue),
        ("sourcePath", .string pathValue), ("startByte", .int startValue)] =>
      let sourcePath ← parseProjectRelativePath pathValue
      let startByte ← pfIntToUInt64 "source-origin startByte" startValue
      let endByte ← pfIntToUInt64 "source-origin endByte" endValue
      let nodeId ← parseNodeId nodeValue
      let origin := { sourcePath, startByte, endByte, nodeId }
      validateSourceOrigin origin
      pure origin
    | _ => throw "source-origin wire must contain exactly endByte,nodeId,sourcePath,startByte"
  | _ => throw "source-origin wire must be an object"

/-- Raw SHA-256 over exact bytes. -/
def sha256Bytes (input : ByteArray) : Digest :=
  { algorithm := .sha256, bytes := ProofForgeV2.Crypto.sha256 input }

/-- SHA-256 over `UTF8(domainTag) || 0x00 || payload`. -/
def domainSeparatedSha256
    (domainTag : String) (payload : ByteArray) : Except String Digest := do
  validateProfileIdValue domainTag
  let preimage := (domainTag.toUTF8.push 0).append payload
  pure (sha256Bytes preimage)

inductive DocumentStatus where
  | notStarted
  | draft
  | proposed
  | inReview
  | accepted
  | superseded
  | archived
  deriving DecidableEq, Repr, Inhabited

def parseDocumentStatus : String → Except String DocumentStatus
  | "not_started" => pure .notStarted
  | "draft" => pure .draft
  | "proposed" => pure .proposed
  | "in_review" => pure .inReview
  | "accepted" => pure .accepted
  | "superseded" => pure .superseded
  | "archived" => pure .archived
  | _ => throw "unknown document status"

def renderDocumentStatus : DocumentStatus → String
  | .notStarted => "not_started"
  | .draft => "draft"
  | .proposed => "proposed"
  | .inReview => "in_review"
  | .accepted => "accepted"
  | .superseded => "superseded"
  | .archived => "archived"

def documentStatusRank : DocumentStatus → Nat
  | .notStarted => 0
  | .draft => 1
  | .proposed => 2
  | .inReview => 3
  | .accepted => 4
  | .superseded => 5
  | .archived => 6

inductive ArtifactDeployability where
  | deployable
  | verifiableWorkload
  | intermediateOnly
  | nonDeployable
  deriving DecidableEq, Repr, Inhabited

def parseArtifactDeployability : String → Except String ArtifactDeployability
  | "deployable" => pure .deployable
  | "verifiable-workload" => pure .verifiableWorkload
  | "intermediate-only" => pure .intermediateOnly
  | "non-deployable" => pure .nonDeployable
  | _ => throw "unknown artifact deployability"

def renderArtifactDeployability : ArtifactDeployability → String
  | .deployable => "deployable"
  | .verifiableWorkload => "verifiable-workload"
  | .intermediateOnly => "intermediate-only"
  | .nonDeployable => "non-deployable"

def artifactDeployabilityRank : ArtifactDeployability → Nat
  | .deployable => 0
  | .verifiableWorkload => 1
  | .intermediateOnly => 2
  | .nonDeployable => 3

inductive ResourceStage where
  | frontend
  | compilerCore
  | externalTool
  | artifactOutput
  deriving DecidableEq, Repr

inductive MemoryMetric where
  | darwinPhysFootprintAggregate
  | linuxProcRssAggregate
  | linuxCgroupMemoryCurrent
  | jobObjectCommitAggregate
  deriving DecidableEq, Repr

structure ResourceProfileV1 where
  schema : SchemaId
  profileId : SchemaId
  stage : ResourceStage
  maxWallMillis : UInt64
  maxAggregateMemoryBytes : UInt64
  memoryMetric : MemoryMetric
  maxProcesses : UInt32
  maxProtocolBytes : UInt64
  maxStderrBytes : UInt64
  maxPublishedBytes : UInt64
  deriving DecidableEq, Repr

def resourceProfileSchema : SchemaId :=
  { value := "proof-forge.resource-profile.v1" }

def hardFrontendProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.frontend.v1" }
    stage := .frontend
    maxWallMillis := 10000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

/-- Linux development observation uses sampled aggregate `/proc` RSS. This is
    neither cgroup accounting nor a containment claim. -/
def hardLinuxObservedFrontendProfile : ResourceProfileV1 :=
  { hardFrontendProfile with
    profileId := { value := "proof-forge.resource.frontend-linux-observed.v1" }
    memoryMetric := .linuxProcRssAggregate }

/-- Hard frontend profile matching the native development supervisor on this
    supported host. Unsupported hosts retain the canonical profile and are
    rejected by the supervisor boundary. -/
def hardFrontendProfileForHost : ResourceProfileV1 :=
  if (System.Platform.target.splitOn "-").contains "linux" then
    hardLinuxObservedFrontendProfile
  else
    hardFrontendProfile

def hardCoreProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.core.v1" }
    stage := .compilerCore
    maxWallMillis := 30000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

def hardToolProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.tool.v1" }
    stage := .externalTool
    maxWallMillis := 600000
    maxAggregateMemoryBytes := 4 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 8
    maxProtocolBytes := 64 * 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 0 }

def hardOutputProfile : ResourceProfileV1 :=
  { schema := resourceProfileSchema
    profileId := { value := "proof-forge.resource.output.v1" }
    stage := .artifactOutput
    maxWallMillis := 60000
    maxAggregateMemoryBytes := 2 * 1024 * 1024 * 1024
    memoryMetric := .darwinPhysFootprintAggregate
    maxProcesses := 1
    maxProtocolBytes := 1024 * 1024
    maxStderrBytes := 64 * 1024
    maxPublishedBytes := 256 * 1024 * 1024 }

/-- Compatibility names retained for the earlier focused Common acceptance. -/
def frontendProfile : ResourceProfileV1 := hardFrontendProfile
def coreProfile : ResourceProfileV1 := hardCoreProfile

def parseResourceStage : String → Except String ResourceStage
  | "frontend" => pure .frontend
  | "compilerCore" => pure .compilerCore
  | "externalTool" => pure .externalTool
  | "artifactOutput" => pure .artifactOutput
  | _ => throw "unknown resource stage"

def renderResourceStage : ResourceStage → String
  | .frontend => "frontend"
  | .compilerCore => "compilerCore"
  | .externalTool => "externalTool"
  | .artifactOutput => "artifactOutput"

def parseMemoryMetric : String → Except String MemoryMetric
  | "darwinPhysFootprintAggregate" => pure .darwinPhysFootprintAggregate
  | "linuxProcRssAggregate" => pure .linuxProcRssAggregate
  | "linuxCgroupMemoryCurrent" => pure .linuxCgroupMemoryCurrent
  | "jobObjectCommitAggregate" => pure .jobObjectCommitAggregate
  | _ => throw "unknown resource memory metric"

def renderMemoryMetric : MemoryMetric → String
  | .darwinPhysFootprintAggregate => "darwinPhysFootprintAggregate"
  | .linuxProcRssAggregate => "linuxProcRssAggregate"
  | .linuxCgroupMemoryCurrent => "linuxCgroupMemoryCurrent"
  | .jobObjectCommitAggregate => "jobObjectCommitAggregate"

private def ensurePositiveUInt64 (label : String) (value : UInt64) : Except String Unit := do
  unless 0 < value do throw s!"{label} must be positive"

private def ensurePositiveUInt32 (label : String) (value : UInt32) : Except String Unit := do
  unless 0 < value do throw s!"{label} must be positive"

/-- Validate a closed ResourceProfileV1 value, including its PF-JCS integer domain. -/
def validateResourceProfileV1 (profile : ResourceProfileV1) : Except String Unit := do
  validateSchemaId profile.schema
  unless profile.schema == resourceProfileSchema do
    throw "resource profile schema mismatch"
  validateProfileIdValue profile.profileId.value
  ensurePositiveUInt64 "maxWallMillis" profile.maxWallMillis
  ensurePositiveUInt64 "maxAggregateMemoryBytes" profile.maxAggregateMemoryBytes
  ensurePositiveUInt32 "maxProcesses" profile.maxProcesses
  ensurePositiveUInt64 "maxProtocolBytes" profile.maxProtocolBytes
  ensurePositiveUInt64 "maxStderrBytes" profile.maxStderrBytes
  let _ ← uint64ToPfInt "maxWallMillis" profile.maxWallMillis
  let _ ← uint64ToPfInt "maxAggregateMemoryBytes" profile.maxAggregateMemoryBytes
  let _ ← uint64ToPfInt "maxProtocolBytes" profile.maxProtocolBytes
  let _ ← uint64ToPfInt "maxStderrBytes" profile.maxStderrBytes
  let _ ← uint64ToPfInt "maxPublishedBytes" profile.maxPublishedBytes

private def validateLowerUInt64
    (label : String) (hard effective : UInt64) : Except String Unit := do
  if hard == 0 then
    unless effective == 0 do throw s!"{label} must remain zero"
  else
    unless 0 < effective && effective ≤ hard do
      throw s!"{label} must be positive and not exceed its hard maximum"

private def validateLowerUInt32
    (label : String) (hard effective : UInt32) : Except String Unit := do
  if hard == 0 then
    unless effective == 0 do throw s!"{label} must remain zero"
  else
    unless 0 < effective && effective ≤ hard do
      throw s!"{label} must be positive and not exceed its hard maximum"

/-- Effective resource budgets may only lower a fixed hard-profile identity. -/
def validateLowerOnlyResourceProfile
    (hard effective : ResourceProfileV1) : Except String Unit := do
  validateResourceProfileV1 hard
  validateResourceProfileV1 effective
  unless effective.schema == hard.schema do throw "resource profile schema mismatch"
  unless effective.profileId == hard.profileId do throw "resource profile id mismatch"
  unless effective.stage == hard.stage do throw "resource profile stage mismatch"
  unless effective.memoryMetric == hard.memoryMetric do throw "resource memory metric mismatch"
  validateLowerUInt64 "maxWallMillis" hard.maxWallMillis effective.maxWallMillis
  validateLowerUInt64 "maxAggregateMemoryBytes"
    hard.maxAggregateMemoryBytes effective.maxAggregateMemoryBytes
  validateLowerUInt32 "maxProcesses" hard.maxProcesses effective.maxProcesses
  validateLowerUInt64 "maxProtocolBytes" hard.maxProtocolBytes effective.maxProtocolBytes
  validateLowerUInt64 "maxStderrBytes" hard.maxStderrBytes effective.maxStderrBytes
  validateLowerUInt64 "maxPublishedBytes" hard.maxPublishedBytes effective.maxPublishedBytes

/-- Historical name retained as a strict lower-only compatibility alias. -/
def validateNotAboveHardMax (hard effective : ResourceProfileV1) : Except String Unit :=
  validateLowerOnlyResourceProfile hard effective

private def uint32ToPfInt (value : UInt32) : Int :=
  Int.ofNat value.toNat

private def pfIntToUInt32 (label : String) (value : Int) : Except String UInt32 := do
  if value < 0 then throw s!"{label} must be nonnegative"
  let natural := value.toNat
  unless natural ≤ 4294967295 do throw s!"{label} exceeds UInt32"
  pure (UInt32.ofNat natural)

def renderResourceProfileJcs (profile : ResourceProfileV1) : Except String String := do
  validateResourceProfileV1 profile
  let maxWallMillis ← uint64ToPfInt "maxWallMillis" profile.maxWallMillis
  let maxAggregateMemoryBytes ←
    uint64ToPfInt "maxAggregateMemoryBytes" profile.maxAggregateMemoryBytes
  let maxProtocolBytes ← uint64ToPfInt "maxProtocolBytes" profile.maxProtocolBytes
  let maxStderrBytes ← uint64ToPfInt "maxStderrBytes" profile.maxStderrBytes
  let maxPublishedBytes ← uint64ToPfInt "maxPublishedBytes" profile.maxPublishedBytes
  renderPfJcs (.object #[
    ("schema", .string profile.schema.value),
    ("profileId", .string profile.profileId.value),
    ("stage", .string (renderResourceStage profile.stage)),
    ("maxWallMillis", .int maxWallMillis),
    ("maxAggregateMemoryBytes", .int maxAggregateMemoryBytes),
    ("memoryMetric", .string (renderMemoryMetric profile.memoryMetric)),
    ("maxProcesses", .int (uint32ToPfInt profile.maxProcesses)),
    ("maxProtocolBytes", .int maxProtocolBytes),
    ("maxStderrBytes", .int maxStderrBytes),
    ("maxPublishedBytes", .int maxPublishedBytes)
  ])

def parseResourceProfileJcs (input : String) : Except String ResourceProfileV1 := do
  let value ← parsePfJcs input
  match value with
  | .object fields =>
    match fields.toList with
    | [("maxAggregateMemoryBytes", .int memoryValue),
        ("maxProcesses", .int processesValue),
        ("maxProtocolBytes", .int protocolValue),
        ("maxPublishedBytes", .int publishedValue),
        ("maxStderrBytes", .int stderrValue),
        ("maxWallMillis", .int wallValue),
        ("memoryMetric", .string metricValue),
        ("profileId", .string profileIdValue),
        ("schema", .string schemaValue),
        ("stage", .string stageValue)] =>
      let schema ← parseSchemaId schemaValue
      validateProfileIdValue profileIdValue
      let profileId : SchemaId := { value := profileIdValue }
      let stage ← parseResourceStage stageValue
      let maxWallMillis ← pfIntToUInt64 "maxWallMillis" wallValue
      let maxAggregateMemoryBytes ←
        pfIntToUInt64 "maxAggregateMemoryBytes" memoryValue
      let memoryMetric ← parseMemoryMetric metricValue
      let maxProcesses ← pfIntToUInt32 "maxProcesses" processesValue
      let maxProtocolBytes ← pfIntToUInt64 "maxProtocolBytes" protocolValue
      let maxStderrBytes ← pfIntToUInt64 "maxStderrBytes" stderrValue
      let maxPublishedBytes ← pfIntToUInt64 "maxPublishedBytes" publishedValue
      let profile :=
        { schema, profileId, stage, maxWallMillis, maxAggregateMemoryBytes,
          memoryMetric, maxProcesses, maxProtocolBytes, maxStderrBytes,
          maxPublishedBytes }
      validateResourceProfileV1 profile
      pure profile
    | _ => throw "resource-profile wire must contain exactly its ten closed fields"
  | _ => throw "resource-profile wire must be an object"

def resourceProfileDigest (profile : ResourceProfileV1) : Except String Digest := do
  let canonical ← renderResourceProfileJcs profile
  domainSeparatedSha256 resourceProfileSchema.value canonical.toUTF8

end ProofForgeV2.Core.Common
