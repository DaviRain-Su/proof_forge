import ProofForgeV2.Core.Common

namespace Tests.Core.Common

open ProofForgeV2.Core.Common

private def expectOk {α} [BEq α] [Repr α] (label : String) (got : Except String α) (want : α) : IO Unit := do
  match got with
  | .ok v =>
    unless v == want do
      throw <| IO.userError s!"{label}: expected {repr want}, got {repr v}"
  | .error e => throw <| IO.userError s!"{label}: unexpected error {e}"

private def expectErr {α} (label : String) (got : Except String α) : IO Unit := do
  match got with
  | .error _ => pure ()
  | .ok _ => throw <| IO.userError s!"{label}: expected error"

private def expectSemVerLt (left right : String) : IO Unit := do
  match parseSemVer left, parseSemVer right with
  | .ok leftVersion, .ok rightVersion =>
    match compareSemVerPrecedence leftVersion rightVersion with
    | .ok .lt => pure ()
    | .ok order =>
      throw <| IO.userError s!"semver precedence: expected {left} < {right}, got {repr order}"
    | .error e =>
      throw <| IO.userError s!"semver precedence unexpectedly rejected a parsed value: {e}"
  | .error e, _ | _, .error e =>
    throw <| IO.userError s!"semver precedence fixture failed to parse: {e}"

def run : IO Unit := do
  let digestWire := "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  match parseDigest digestWire with
  | .ok digest =>
    unless digest.algorithm == .sha256 && digest.bytes.size == 32 do
      throw <| IO.userError "digest happy: expected sha256 with 32 raw bytes"
    unless digest.bytes[0]! == 0x01 && digest.bytes[31]! == 0xef do
      throw <| IO.userError "digest happy: hex was not decoded to raw bytes"
    match renderDigest digest with
    | .ok rendered =>
      unless rendered == digestWire do
        throw <| IO.userError s!"digest canonical rendering mismatch: {rendered}"
    | .error e => throw <| IO.userError s!"digest renderer rejected parsed value: {e}"
  | .error e => throw <| IO.userError s!"digest happy: unexpected error {e}"
  expectErr "digest uppercase" (parseDigest "sha256:0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef")
  expectErr "digest bare hex" (parseDigest "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
  expectErr "digest short" (parseDigest "sha256:abcd")
  expectErr "digest empty" (parseDigest "")
  expectErr "digest unknown algorithm"
    (parseDigest "sha512:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
  expectErr "digest invalid hex"
    (parseDigest "sha256:g123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
  expectErr "digest long"
    (parseDigest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef00")
  let invalidDigest : Digest := { algorithm := .sha256, bytes := ByteArray.empty }
  expectErr "digest validation rejects invalid raw length" (validateDigest invalidDigest)
  expectErr "digest render rejects invalid raw length" (renderDigest invalidDigest)
  let rawPattern := ByteArray.mk #[
    0x00, 0x09, 0x0a, 0x0f, 0x10, 0x7f, 0x80, 0xff,
    0x00, 0x09, 0x0a, 0x0f, 0x10, 0x7f, 0x80, 0xff,
    0x00, 0x09, 0x0a, 0x0f, 0x10, 0x7f, 0x80, 0xff,
    0x00, 0x09, 0x0a, 0x0f, 0x10, 0x7f, 0x80, 0xff]
  let rawPatternWire :=
    "sha256:00090a0f107f80ff00090a0f107f80ff00090a0f107f80ff00090a0f107f80ff"
  expectOk "digest direct raw golden"
    (renderDigest { algorithm := .sha256, bytes := rawPattern }) rawPatternWire
  match parseDigest rawPatternWire with
  | .ok digest =>
    unless digest.bytes == rawPattern do
      throw <| IO.userError "digest independent raw-byte golden mismatch"
  | .error e => throw <| IO.userError s!"digest raw-byte golden parse failed: {e}"
  expectErr "digest validation rejects 31 bytes"
    (validateDigest { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 31 0) })
  expectErr "digest validation rejects 33 bytes"
    (validateDigest { algorithm := .sha256, bytes := ByteArray.mk (Array.replicate 33 0) })
  expectOk "semver core" (parseSemVerCore "1.2.3") { major := 1, minor := 2, patch := 3 }
  expectErr "semver v prefix" (parseSemVerCore "v1.2.3")
  expectErr "semver leading zero" (parseSemVerCore "01.2.3")
  -- S2 catalog SemVer core exact fast path: production-preserving `1.0.0`.
  expectOk "semver s2 core fast path" (parseSemVer "1.0.0")
    { major := 1, minor := 0, patch := 0, prerelease := #[], build := #[] }
  expectOk "semver s2 core via parseSemVerCore" (parseSemVerCore "1.0.0")
    { major := 1, minor := 0, patch := 0, prerelease := #[], build := #[] }
  match parseSemVer "1.0.0" with
  | .ok v =>
    match renderSemVer v with
    | .ok rendered =>
      unless rendered == "1.0.0" do
        throw <| IO.userError
          s!"semver s2 core render must be exact 1.0.0, got {rendered}"
      unless v.prerelease.isEmpty && v.build.isEmpty do
        throw <| IO.userError "semver s2 core must have empty prerelease/build"
      unless v == s2CatalogSemVerCoreV1 do
        throw <| IO.userError "semver s2 core must equal s2CatalogSemVerCoreV1"
    | .error e =>
      throw <| IO.userError s!"semver s2 core renderer rejected: {e}"
  | .error e =>
    throw <| IO.userError s!"semver s2 core fast path failed: {e}"
  -- Near-neighbor spellings still use / reject via the general path.
  expectErr "semver near leading zero major" (parseSemVer "01.0.0")
  expectErr "semver near leading zero minor" (parseSemVer "1.00.0")
  expectErr "semver near leading zero patch" (parseSemVer "1.0.00")
  expectErr "semver near v prefix" (parseSemVer "v1.0.0")
  expectErr "semver near missing patch" (parseSemVer "1.0")
  expectErr "semver near trailing dot" (parseSemVer "1.0.0.")
  expectOk "semver near prerelease not exact core"
    (parseSemVer "1.0.0-alpha")
    { major := 1, minor := 0, patch := 0, prerelease := #["alpha"], build := #[] }
  expectOk "semver near build not exact core"
    (parseSemVer "1.0.0+build")
    { major := 1, minor := 0, patch := 0, prerelease := #[], build := #["build"] }
  expectOk "semver near different patch" (parseSemVer "1.0.1")
    { major := 1, minor := 0, patch := 1, prerelease := #[], build := #[] }
  expectOk "semver prerelease and build"
    (parseSemVer "1.2.3-alpha.1+build.005")
    { major := (1 : UInt64)
      minor := 2
      patch := 3
      prerelease := #["alpha", "1"]
      build := #["build", "005"] }
  expectOk "semver uint64 maximum"
    (parseSemVer "18446744073709551615.0.0")
    { major := (18446744073709551615 : UInt64)
      minor := 0
      patch := 0
      prerelease := #[]
      build := #[] }
  expectErr "semver uint64 overflow" (parseSemVer "18446744073709551616.0.0")
  expectErr "semver oversized numeric input"
    (parseSemVer "999999999999999999999999999999999999999999999999999999999999.0.0")
  expectErr "semver minor uint64 overflow" (parseSemVer "0.18446744073709551616.0")
  expectErr "semver patch uint64 overflow" (parseSemVer "0.0.18446744073709551616")
  expectErr "semver minor leading zero" (parseSemVer "1.02.3")
  expectErr "semver patch leading zero" (parseSemVer "1.2.03")
  expectErr "semver numeric prerelease leading zero" (parseSemVer "1.2.3-01")
  expectErr "semver empty prerelease identifier" (parseSemVer "1.2.3-alpha..1")
  expectErr "semver empty build identifier" (parseSemVer "1.2.3+build..1")
  expectErr "semver empty prerelease" (parseSemVer "1.2.3-")
  expectErr "semver empty build" (parseSemVer "1.2.3+")
  expectErr "semver invalid identifier character" (parseSemVer "1.2.3-alpha_beta")
  expectErr "semver non-ascii identifier" (parseSemVer "1.2.3-α")
  expectErr "semver duplicate build separator" (parseSemVer "1.2.3+a+b")
  expectErr "semver trailing prerelease dot" (parseSemVer "1.2.3-alpha.")
  expectErr "semver missing patch" (parseSemVer "1.2")
  expectErr "semver core rejects prerelease" (parseSemVerCore "1.2.3-alpha")
  expectErr "semver core rejects build" (parseSemVerCore "1.2.3+build")
  match parseSemVer "1.2.3-alpha.1+build.005", parseSemVer "1.2.3-alpha.1+other" with
  | .ok left, .ok right =>
    match renderSemVer left with
    | .ok rendered =>
      unless rendered == "1.2.3-alpha.1+build.005" do
        throw <| IO.userError "semver canonical rendering lost prerelease/build"
    | .error e =>
      throw <| IO.userError s!"semver renderer rejected parsed value: {e}"
    unless left != right do
      throw <| IO.userError "semver exact identity must include build metadata"
    match compareSemVerPrecedence left right with
    | .ok .eq => pure ()
    | .ok order =>
      throw <| IO.userError s!"semver precedence must ignore build metadata, got {repr order}"
    | .error e =>
      throw <| IO.userError s!"semver precedence rejected parsed values: {e}"
  | .error e, _ | _, .error e =>
    throw <| IO.userError s!"semver precedence fixture failed to parse: {e}"
  expectSemVerLt "1.0.0-alpha" "1.0.0-alpha.1"
  expectSemVerLt "1.0.0-alpha.1" "1.0.0-alpha.beta"
  expectSemVerLt "1.0.0-alpha.beta" "1.0.0-beta"
  expectSemVerLt "1.0.0-beta" "1.0.0-beta.2"
  expectSemVerLt "1.0.0-beta.2" "1.0.0-beta.11"
  expectSemVerLt "1.0.0-beta.11" "1.0.0-rc.1"
  expectSemVerLt "1.0.0-rc.1" "1.0.0"
  expectSemVerLt "1.0.0" "2.0.0"
  expectSemVerLt "2.0.0" "2.1.0"
  expectSemVerLt "2.1.0" "2.1.1"
  let invalidPrerelease : SemVer :=
    { major := 1, minor := 2, patch := 3, prerelease := #[""], build := #[] }
  let invalidBuild : SemVer :=
    { major := 1, minor := 2, patch := 3, prerelease := #[], build := #["bad+value"] }
  expectErr "semver render rejects direct invalid prerelease" (renderSemVer invalidPrerelease)
  expectErr "semver render rejects direct invalid build" (renderSemVer invalidBuild)
  expectErr "semver compare rejects direct invalid value"
    (compareSemVerPrecedence invalidPrerelease invalidBuild)
  match validateNotAboveHardMax frontendProfile frontendProfile with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"frontend hard max self: {e}"
  let raised := { frontendProfile with maxWallMillis := frontendProfile.maxWallMillis + 1 }
  expectErr "wall over hard max" (validateNotAboveHardMax frontendProfile raised)
  IO.println "Tests.Core.Common: ok"

end Tests.Core.Common
