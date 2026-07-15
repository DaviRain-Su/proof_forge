import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter

namespace Tests.CLI.Emit

open ProofForgeV2 System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def run : IO Unit := do
  let counter ← match Compiler.compile Examples.counter with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let unsafeProgram := { counter with name := "../escaped" }
  let output := FilePath.mk "build/v2/path-guard/output"
  let rejected ←
    try
      let _ ← ProofForgeV2.CLI.emitProgram .evm unsafeProgram output
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
      let _ ← ProofForgeV2.CLI.emitProgram .solana counter collision
      pure false
    catch error =>
      pure (decide (((toString error).splitOn "PF-OUTPUT-COLLISION").length > 1))
  expect collisionRejected "an existing output directory must be rejected without replacement"
  expect ((← IO.FS.readFile (collision / "important.txt")) == "preserve-me\n")
    "output collision must preserve pre-existing files"

end Tests.CLI.Emit
