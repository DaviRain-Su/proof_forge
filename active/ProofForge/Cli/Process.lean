import ProofForge.Cli.HexUtil

open System
open ProofForge.Cli.HexUtil

namespace ProofForge.Cli

def runProcess (cmd : String) (args : Array String) (cwd? : Option FilePath := none) : IO String := do
  let output ← IO.Process.output { cmd := cmd, args := args, cwd := cwd? }
  if output.exitCode != 0 then
    let stderr := trimAsciiString output.stderr
    let detail := if stderr.isEmpty then trimAsciiString output.stdout else stderr
    throw <| IO.userError s!"{cmd} failed with exit code {output.exitCode}: {detail}"
  return output.stdout


end ProofForge.Cli
