import ProofForgeV2.CLI.Emit
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.CLI.Emit

open ProofForgeV2 System
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

unsafe def run : IO Unit := do
  -- Path-safety pure seam (package-visible). Forged residual names cannot mint
  -- private-ctor CompiledProgramV1, so PF-OUTPUT-PATH on emitProgram is unreachable
  -- without a public two-carrier factory; emitProgram still dual-calls
  -- validProgramArtifactNameV1 on residual name then materializeResult.
  expect (!ProofForgeV2.CLI.validProgramArtifactNameV1 "../escaped")
    "artifact names must not escape the staging root"
  expect (!ProofForgeV2.CLI.validProgramArtifactNameV1 "")
    "empty artifact names are unsafe"
  expect (ProofForgeV2.CLI.validProgramArtifactNameV1 "Counter")
    "legal Counter artifact name must pass path safety"

  let session ← Tests.Language.ParserSession.shared
  let source ← match ← session.selectProgramV1
      Examples.counterSourceText "<cli-emit-counter>" Examples.counterModuleNameV1 none with
    | .ok s => pure s
    | .error e => throw <| IO.userError e.render
  let compiled ← match Compiler.compileValidatedSourceV1 source with
    | .ok c => pure c
    | .error e => throw <| IO.userError e.render
  -- Real product carrier: residual name is the identity emitProgram gates via
  -- validArtifactName; Counter must be accepted so later PF-OUTPUT-COLLISION is
  -- not masked by a path-safety failure.
  let residual := CompiledProgramV1.alphaResidualOf compiled
  expect (residual.name == "Counter")
    "Counter residual alpha name must be the product artifact identity"
  expect (ProofForgeV2.CLI.validProgramArtifactNameV1 residual.name)
    "emitProgram residual name must pass the same path-safety predicate"

  let collision := FilePath.mk "build/v2/existing-output"
  if ← collision.pathExists then IO.FS.removeDirAll collision
  IO.FS.createDirAll collision
  IO.FS.writeFile (collision / "important.txt") "preserve-me\n"
  let collisionRejected ←
    try
      let sel ← match resolveBuildSelectionV1 TargetId.solana none with
        | .ok s => pure s
        | .error e => throw <| IO.userError e.render
      let _ ← ProofForgeV2.CLI.emitProgram sel compiled collision
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
