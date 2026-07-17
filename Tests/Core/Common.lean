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

def run : IO Unit := do
  expectOk "digest happy"
    (parseDigest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
    { algorithm := .sha256
      hex := "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef" }
  expectErr "digest uppercase" (parseDigest "sha256:0123456789ABCDEF0123456789abcdef0123456789abcdef0123456789abcdef")
  expectErr "digest bare hex" (parseDigest "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef")
  expectErr "digest short" (parseDigest "sha256:abcd")
  expectOk "semver core" (parseSemVerCore "1.2.3") { major := 1, minor := 2, patch := 3 }
  expectErr "semver v prefix" (parseSemVerCore "v1.2.3")
  expectErr "semver leading zero" (parseSemVerCore "01.2.3")
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
  expectErr "semver numeric prerelease leading zero" (parseSemVer "1.2.3-01")
  expectErr "semver empty prerelease identifier" (parseSemVer "1.2.3-alpha..1")
  expectErr "semver empty build identifier" (parseSemVer "1.2.3+build..1")
  expectErr "semver invalid identifier character" (parseSemVer "1.2.3-alpha_beta")
  expectErr "semver missing patch" (parseSemVer "1.2")
  match parseSemVer "1.2.3-alpha.1+build.005", parseSemVer "1.2.3-alpha.1+other" with
  | .ok left, .ok right =>
    unless renderSemVer left == "1.2.3-alpha.1+build.005" do
      throw <| IO.userError "semver canonical rendering lost prerelease/build"
    unless left != right do
      throw <| IO.userError "semver exact identity must include build metadata"
    unless compareSemVerPrecedence left right == .eq do
      throw <| IO.userError "semver precedence must ignore build metadata"
  | .error e, _ | _, .error e =>
    throw <| IO.userError s!"semver precedence fixture failed to parse: {e}"
  match validateNotAboveHardMax frontendProfile frontendProfile with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"frontend hard max self: {e}"
  let raised := { frontendProfile with maxWallMillis := frontendProfile.maxWallMillis + 1 }
  expectErr "wall over hard max" (validateNotAboveHardMax frontendProfile raised)
  IO.println "Tests.Core.Common: ok"

end Tests.Core.Common
