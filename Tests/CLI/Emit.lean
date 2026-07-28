import ProofForgeV2.CLI.Emit
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import Tests.Fixtures.SourcePrograms

namespace Tests.CLI.Emit

open ProofForgeV2 System
open ProofForgeV2.Targets.BuildSelectionV1
open Tests.Fixtures.SourcePrograms

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let counter ← match Compiler.compile counterQualified with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let unsafeProgram := { counter with name := "../escaped" }
  let output := FilePath.mk "build/v2/path-guard/output"
  let rejected ←
    try
      let sel ← match resolveBuildSelectionV1 TargetId.evm none with
        | .ok s => pure s
        | .error e => throw <| IO.userError e.render
      let _ ← ProofForgeV2.CLI.emitProgram sel unsafeProgram output
      pure false
    catch error =>
      pure (decide (((toString error).splitOn "PF-OUTPUT-PATH").length > 1))
  expect rejected "artifact names must not escape the staging root"
  expect (!(← (FilePath.mk "build/v2/path-guard/escaped.yul").pathExists))
    "path traversal must not create an artifact outside the destination"

  let collision := FilePath.mk "build/v2/existing-output"
  if ← collision.pathExists then IO.FS.removeDirAll collision
  IO.FS.createDirAll collision
  IO.FS.writeFile (collision / "important.txt") "preserve-me\n"
  let collisionRejected ←
    try
      let sel ← match resolveBuildSelectionV1 TargetId.solana none with
        | .ok s => pure s
        | .error e => throw <| IO.userError e.render
      let _ ← ProofForgeV2.CLI.emitProgram sel counter collision
      pure false
    catch error =>
      pure (decide (((toString error).splitOn "PF-OUTPUT-COLLISION").length > 1))
  expect collisionRejected "an existing output directory must be rejected without replacement"
  expect ((← IO.FS.readFile (collision / "important.txt")) == "preserve-me\n")
    "output collision must preserve pre-existing files"

  -- Host-locked env isolation pins darwin-arm64 system tool digests
  -- (host:stat / env). Portable Linux CI and unprofiled hosts must not run it.
  -- Full local gate: `PROOF_FORGE_HOST_ISOLATION_TEST=1 just test` or `just check`.
  match ← IO.getEnv "PROOF_FORGE_HOST_ISOLATION_TEST" with
  | some "1" =>
      ProofForgeV2.CLI.Toolchain.environmentIsolationSelfTest
  | _ => pure ()

end Tests.CLI.Emit
