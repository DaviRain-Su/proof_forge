/-
  CosmWasm cosmwasm-check acceptance suite (engineering only; A2 Tool Lock).

  Invokes the host helper:

      scripts/cosmwasm_check_acceptance.sh

  which:
  1. Assembles hand-written minimal ABI WAT fixtures with locked/host wat2wasm
     and runs cosmwasm-check 3.0.9 positive/negative matrix.
  2. Conditionally builds product StateCell `--target cosmwasm` when the CLI and
     A1 emitter are available; otherwise skip-clean (expected pre-A1 merge).

  When `wat2wasm` or `cosmwasm-check` is absent the helper (and this suite)
  SKIP-passes. Not wasmd / cosmwasm-vm runtime / formal Stage-0.

  **Not registered in a Tests.Shards/* suite** — main agent must register
  (lakefile roots + shard + Tests.lean as appropriate).

  Fixture matrix (see `testdata/cosmwasm-check/`):
  - positive: minimal_abi.wat
  - negative: missing_interface_version.wat, multi_memory.wat,
    memory_with_maximum.wat
  Float opcodes are NOT rejected by cosmwasm-check 3.0.9 static validation
  (verified); third hard negative is memory-with-maximum instead of float.
-/

namespace Tests.Materialization.CosmWasmCheckAcceptance

open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

/-- Resolve `scripts/cosmwasm_check_acceptance.sh` relative to CWD (repo root). -/
private def resolveHelper : IO FilePath := do
  let script := FilePath.mk "scripts/cosmwasm_check_acceptance.sh"
  expect (← script.pathExists) "missing scripts/cosmwasm_check_acceptance.sh"
  pure script

/-- Suite entry. Helper exit 0 covers both real runs and tool-absent skip-clean. -/
def run : IO Unit := do
  IO.println "Tests.Materialization.CosmWasmCheckAcceptance: start"
  let script ← resolveHelper
  let cwd ← IO.currentDir
  let scriptPath := (cwd / script).toString
  let proc ← IO.Process.output {
    cmd := "bash"
    args := #[scriptPath]
    cwd := some cwd
  }
  -- Surface helper stdout/stderr for diagnosis (skip messages included).
  unless proc.stdout.isEmpty do
    IO.println proc.stdout.trimAscii.copy
  unless proc.stderr.isEmpty do
    IO.println proc.stderr.trimAscii.copy
  if proc.exitCode == 0 then
    if proc.stdout.contains "skipped:" &&
        !(proc.stdout.contains "fixture matrix ok") then
      IO.println "Tests.Materialization.CosmWasmCheckAcceptance: ok (skipped)"
    else
      IO.println "Tests.Materialization.CosmWasmCheckAcceptance: ok"
  else
    throw <| IO.userError
      s!"cosmwasm_check_acceptance.sh failed (exit {proc.exitCode})"

end Tests.Materialization.CosmWasmCheckAcceptance
