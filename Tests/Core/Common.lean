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
  match validateNotAboveHardMax frontendProfile frontendProfile with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"frontend hard max self: {e}"
  let raised := { frontendProfile with maxWallMillis := frontendProfile.maxWallMillis + 1 }
  expectErr "wall over hard max" (validateNotAboveHardMax frontendProfile raised)
  IO.println "Tests.Core.Common: ok"

end Tests.Core.Common
