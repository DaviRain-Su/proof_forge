import ProofForgeV2.Core.Canonical
import ProofForgeV2.Core.Common
import Lean.Data.Json.Parser

/-! Compile-time authority for the two supported platform Tool Lock v4 files. -/

namespace ProofForgeV2.Core.ToolLockV4

open ProofForgeV2.Core.Common

inductive ToolLockPlatformV4 where
  | darwinArm64
  | linuxX86_64
  deriving BEq, DecidableEq, Repr

namespace ToolLockPlatformV4

def wire : ToolLockPlatformV4 → String
  | .darwinArm64 => "darwin-arm64"
  | .linuxX86_64 => "linux-x86_64"

end ToolLockPlatformV4

structure ToolLockV4Identity where
  platform : ToolLockPlatformV4
  digest : Digest
  deriving DecidableEq, Repr

def toolLockV4Schema : String := "proof-forge.toolchains.v4"

private def embeddedDarwin : String := include_str "../../toolchains.lock.json"
private def embeddedLinux : String := include_str "../../toolchains-linux-x86_64.lock.json"

/-- Package-owned lock text for an explicitly supported platform. -/
def embeddedToolLockV4Text : ToolLockPlatformV4 → String
  | .darwinArm64 => embeddedDarwin
  | .linuxX86_64 => embeddedLinux

private def expectedRawDigestWire : ToolLockPlatformV4 → String
  | .darwinArm64 =>
      "sha256:e729ea8b024703297542802b49ae186b07e87848696d8fd4809a15c8021565a7"
  | .linuxX86_64 =>
      "sha256:eabdd5bf38ff10af015c32b98e6b38a6a981e5aaf34998b5223127344995619d"

/-- Raw retained-file identity, kept distinct from ToolLockV4Digest. -/
def embeddedToolLockV4RawDigest (platform : ToolLockPlatformV4) : Digest :=
  sha256Bytes (embeddedToolLockV4Text platform).toUTF8

private def isAsciiDecimalComponent (value : String) : Bool :=
  !value.isEmpty && value.toList.all fun c => '0' ≤ c && c ≤ '9'

private def isDarwinOsComponent (value : String) : Bool :=
  if value == "darwin" then
    true
  else if value.startsWith "darwin" then
    let suffix := (value.drop 6).copy
    !suffix.isEmpty && (suffix.splitOn ".").all isAsciiDecimalComponent
  else
    false

/-- Exact supported-target selection; unknown architectures/OSes do not fall
    back to a different platform lock. Lean's Darwin target includes the host
    kernel version (for example `arm64-apple-darwin24.6.0`), so that suffix is
    admitted only as nonempty dot-separated decimal components. -/
def toolLockPlatformForTarget? (target : String) : Option ToolLockPlatformV4 :=
  match target.splitOn "-" with
  | [arch, vendor, os] =>
      if (arch == "aarch64" || arch == "arm64") && vendor == "apple" &&
          isDarwinOsComponent os then
        some .darwinArm64
      else
        none
  | [arch, vendor, os, abi] =>
      if arch == "x86_64" && vendor == "unknown" && os == "linux" && abi == "gnu" then
        some .linuxX86_64
      else
        none
  | _ => none

private def requireSingleStringField
    (fields : Array (String × PfJson)) (key expected : String) : Except String Unit := do
  let matchingFields := fields.filter (·.1 == key)
  unless matchingFields.size == 1 do
    throw s!"Tool Lock v4 root must contain exactly one '{key}'"
  match matchingFields[0]? with
  | some field =>
      match field.2 with
      | .string value =>
          unless value == expected do
            throw s!"Tool Lock v4 '{key}' must be '{expected}'"
      | _ => throw s!"Tool Lock v4 '{key}' must be a string"
  | _ => throw s!"Tool Lock v4 '{key}' must be a string"

private def jsonToPfJson : Nat → Lean.Json → Except String PfJson
  | 0, _ => throw "Tool Lock v4 JSON nesting exceeds 256"
  | _ + 1, .null => pure .null
  | _ + 1, .bool value => pure (.bool value)
  | _ + 1, .num value => do
      let mut integer := value.mantissa
      for _ in List.range value.exponent do
        unless integer % 10 == 0 do
          throw "Tool Lock v4 numbers must have exact integer values"
        integer := integer / 10
      let limit : Int := 9007199254740991
      unless -limit ≤ integer && integer ≤ limit do
        throw "Tool Lock v4 integer exceeds I-JSON safe range"
      pure (.int integer)
  | _ + 1, .str value => pure (.string value)
  | fuel + 1, .arr values => do
      let converted ← values.mapM (jsonToPfJson fuel)
      pure (.array converted)
  | fuel + 1, .obj fields => do
      let converted ← fields.toArray.mapM fun field => do
        pure (field.1, ← jsonToPfJson fuel field.2)
      pure (.object converted)

/-- Recompute one embedded platform lock's PF-JCS identity. Caller-provided
    lock text is intentionally not accepted by this API. -/
def toolLockV4IdentityForPlatform
    (platform : ToolLockPlatformV4) : Except String ToolLockV4Identity := do
  let expectedRaw ← parseDigest (expectedRawDigestWire platform)
  unless (embeddedToolLockV4RawDigest platform).bytes == expectedRaw.bytes do
    throw s!"embedded {platform.wire} Tool Lock v4 raw digest mismatch"
  let value ← Lean.Json.parse (embeddedToolLockV4Text platform) >>= jsonToPfJson 256
  let fields ← match value with
    | .object fields => pure fields
    | _ => throw "Tool Lock v4 root must be an object"
  requireSingleStringField fields "schema" toolLockV4Schema
  requireSingleStringField fields "platform" platform.wire
  let canonical ← renderPfJcs value
  let digest ← domainSeparatedSha256 toolLockV4Schema canonical.toUTF8
  pure { platform, digest }

def activeToolLockPlatformV4 : Except String ToolLockPlatformV4 :=
  match toolLockPlatformForTarget? System.Platform.target with
  | some platform => pure platform
  | none => throw s!"unsupported Tool Lock v4 target '{System.Platform.target}'"

def embeddedToolLockV4Identity : Except String ToolLockV4Identity := do
  toolLockV4IdentityForPlatform (← activeToolLockPlatformV4)

end ProofForgeV2.Core.ToolLockV4
