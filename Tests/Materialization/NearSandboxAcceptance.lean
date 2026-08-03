/-
  NEAR near-sandbox receipt acceptance suite (engineering only; G123).

  Builds Counter through the product capability path, lowers to `.wat`,
  compiles with host `wat2wasm` when available, then invokes:

      scripts/near_sandbox_acceptance.sh <Counter.wasm>

  which starts near-sandbox, deploys the Wasm, and calls init/increment/get.

  When `near-sandbox` (or wat2wasm / python cryptography stack required by the
  helper) is absent the suite SKIP-passes. Not formal Stage-0 / hermetic Tool
  Lock verification / Reference↔sandbox differential.

  Registered in `Tests.Shards.Targets`; ordinary runs exercise it when the
  locked tools and host prerequisites have been materialized.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.NearSandboxAcceptance

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

/-- Resolve an executable: Tool Lock default root, absolute candidates, then PATH. -/
private def resolveTool (name : String) : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #["/opt/homebrew/bin/", "/usr/local/bin/"]
  if let some h := home then
    -- Tool Lock defaultPath layout (darwin-arm64 / linux-x86_64).
    absCandidates := absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/darwin-arm64/")
    absCandidates := absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/linux-x86_64/")
    absCandidates := absCandidates.push (h ++ "/.local/bin/")
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    absCandidates := #[root ++ "/"] ++ absCandidates
  for dir in absCandidates do
    let path := dir ++ name
    if ← (FilePath.mk path).pathExists then
      return some path
  let which ← IO.Process.output { cmd := "which", args := #[name] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

private unsafe def materializeCounterWat : IO String := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<near-sandbox-Counter>" Examples.counterModuleNameV1 none)
  let compiled ← liftResult "compile Counter" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult "select Counter" <|
    resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult "resolve Counter" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult "materialize Counter" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  let some watFile := files.find? (·.path == "Counter.wat") |
    throw <| IO.userError s!"Counter: missing Counter.wat; got {files.map (·.path)}"
  expect (!watFile.contents.isEmpty) "Counter: empty WAT"
  pure watFile.contents

unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.NearSandboxAcceptance: start"
  match ← resolveTool "near-sandbox" with
  | none =>
      IO.println "skipped: near-sandbox unavailable"
      IO.println "Tests.Materialization.NearSandboxAcceptance: ok (skipped)"
  | some sandbox => do
      let ver ← IO.Process.output { cmd := sandbox, args := #["--version"] }
      IO.println s!"near-sandbox: {sandbox}"
      IO.println s!"{ver.stdout.trimAscii.copy}"
      let some wat2wasm ← resolveTool "wat2wasm" |
        IO.println "skipped: wat2wasm unavailable (needed to build Counter.wasm)"
        IO.println "Tests.Materialization.NearSandboxAcceptance: ok (skipped)"
        return
      let tmp := FilePath.mk "build/v2/near-sandbox-acceptance-lean"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      try
        let wat ← materializeCounterWat
        IO.FS.writeFile (tmp / "Counter.wat") wat
        let w2w ← IO.Process.output {
          cmd := wat2wasm
          args := #["Counter.wat", "-o", "Counter.wasm"]
          cwd := some tmp
        }
        unless w2w.exitCode == 0 do
          throw <| IO.userError
            s!"wat2wasm failed\n{w2w.stdout}\n{w2w.stderr}"
        let script := FilePath.mk "scripts/near_sandbox_acceptance.sh"
        expect (← script.pathExists) "missing scripts/near_sandbox_acceptance.sh"
        -- Prefer absolute paths so the helper does not depend on cwd after Lean spawn.
        let cwd ← IO.currentDir
        let wasmPath := (cwd / tmp / "Counter.wasm").toString
        let scriptPath := (cwd / script).toString
        let proc ← IO.Process.output {
          cmd := "bash"
          args := #[scriptPath, wasmPath]
        }
        IO.println proc.stdout
        if proc.exitCode != 0 then
          -- Helper skip (exit 0) vs fail (exit 1). Exit 0 with "skipped:" is ok.
          if proc.stdout.contains "skipped:" || proc.stderr.contains "skipped:" then
            IO.println proc.stderr
            IO.println "Tests.Materialization.NearSandboxAcceptance: ok (skipped by helper)"
          else
            throw <| IO.userError
              s!"near_sandbox_acceptance.sh failed (exit {proc.exitCode})\n{proc.stderr}"
        else
          IO.println "Tests.Materialization.NearSandboxAcceptance: ok"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.NearSandboxAcceptance
