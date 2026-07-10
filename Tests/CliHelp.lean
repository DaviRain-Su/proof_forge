/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

# CLI `--help` / `-h` surface tests (Task 2)

Verifies that the global and per-verb usage strings are wired correctly and
that the helper predicate identifies help requests.
-/
import ProofForge.Cli

namespace ProofForge.Tests.CliHelp

def require (cond : Bool) (msg : String) : IO Unit :=
  if cond then pure () else throw (IO.userError msg)

def main : IO UInt32 := do
  -- Help-request detection.
  require (!wantsHelp []) "wantsHelp [] should be false"
  require (wantsHelp ["--help"]) "wantsHelp [--help] should be true"
  require (wantsHelp ["-h"]) "wantsHelp [-h] should be true"
  require (wantsHelp ["--target", "evm", "-h"]) "wantsHelp mixed args should be true"
  require (!wantsHelp ["--target", "evm"]) "wantsHelp non-help args should be false"

  -- Global usage contains the program tagline.
  require (ProofForge.Cli.usage.contains "ProofForge — portable contract SDK")
    "global usage should contain the program tagline"
  require (ProofForge.Cli.usage.contains "proof-forge build --target <id>")
    "global usage should mention the build product path"

  -- Per-verb usage strings contain their Usage lines.
  require (ProofForge.Cli.buildUsage.contains "Usage: proof-forge build --target <id>")
    "buildUsage should contain its usage line"
  require (ProofForge.Cli.buildUsage.contains "--target <id>")
    "buildUsage should mention --target"

  require (ProofForge.Cli.emitUsage.contains "Usage: proof-forge emit --target <id> --fixture <id>")
    "emitUsage should contain its usage line"
  require (ProofForge.Cli.emitUsage.contains "--fixture <id>")
    "emitUsage should mention --fixture"

  require (ProofForge.Cli.checkUsage.contains "Usage: proof-forge check --target <id>")
    "checkUsage should contain its usage line"
  require (ProofForge.Cli.checkUsage.contains "--report-format json|text")
    "checkUsage should mention --report-format"

  -- Each per-verb usage should point back to the global help.
  require (ProofForge.Cli.buildUsage.contains "Use `proof-forge --help` for the full command list.")
    "buildUsage should reference global help"
  require (ProofForge.Cli.emitUsage.contains "Use `proof-forge --help` for the full command list.")
    "emitUsage should reference global help"
  require (ProofForge.Cli.checkUsage.contains "Use `proof-forge --help` for the full command list.")
    "checkUsage should reference global help"

  IO.println "cli-help: ok"
  pure 0

end ProofForge.Tests.CliHelp

-- This test imports the executable CLI module, whose root `main` would otherwise
-- run after elaboration and print usage. Exit from the test result instead.
#eval (do
  let exitCode ← ProofForge.Tests.CliHelp.main
  IO.Process.exit exitCode.toUInt8
  pure () : IO Unit)
