/-
  Noir nargo compile-only acceptance suite (engineering only; G123 / RPT-017).

  Builds Counter through the product Noir capability path, writes the emitted
  relation package(s) (`Nargo.toml` + `src/main.nr`) to staging, and invokes:

      nargo compile

  in each package directory. Compile-only — never prove/verify. Product
  `scripts/validate_artifacts.py` continues to reject proof-stage leaves.

  When `nargo` is absent the suite SKIP-passes. Not formal Stage-0 / hermetic
  Tool Lock verification / Noir prove path.

  Registered in `Tests.Shards.Targets`; ordinary runs exercise it when the
  locked nargo asset has been materialized.

  Note: product `Nargo.toml` intentionally omits `compiler_version`. Pin is
  Tool Lock `nargo` `1.0.0-beta.26`; whether emitters should pin
  `compiler_version` is a main-agent product decision (do not change
  `Targets/Noir/**` in this worker lane).
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.NoirCompileAcceptance

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

private def resolveNargoPath : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #["/opt/homebrew/bin/nargo", "/usr/local/bin/nargo"]
  if let some h := home then
    absCandidates := absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/darwin-arm64/nargo")
    absCandidates := absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/linux-x86_64/nargo")
    absCandidates := absCandidates.push (h ++ "/.nargo/bin/nargo")
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    absCandidates := #[root ++ "/nargo"] ++ absCandidates
  for c in absCandidates do
    if ← (FilePath.mk c).pathExists then
      return some c
  let which ← IO.Process.output { cmd := "which", args := #["nargo"] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

/-- Product materialize for default Noir profile; write files and return package roots
    (directories that contain `Nargo.toml`). -/
private unsafe def materializeNoirPackages
    (label : String) (sourceText : String) (moduleName : String)
    (tmp : FilePath) : IO (Array FilePath) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<noir-compile-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.noir none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  expect (!files.isEmpty) s!"{label}: no materialize files"
  let mut pkgRoots : Array FilePath := #[]
  for f in files do
    let path := tmp / f.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile path f.contents
    if f.path.endsWith "Nargo.toml" then
      if let some parent := path.parent then
        pkgRoots := pkgRoots.push parent
  expect (!pkgRoots.isEmpty)
    s!"{label}: missing Nargo.toml in materialize output; got {files.map (·.path)}"
  pure pkgRoots

private def runNargoCompile (nargo : String) (pkgRoot : FilePath) (label : String) : IO Unit := do
  let process ← IO.Process.output {
    cmd := nargo
    args := #["compile", "--silence-warnings"]
    cwd := some pkgRoot
  }
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": nargo compile failed (exit " ++ toString process.exitCode ++
        ")\nstdout:\n" ++ process.stdout ++ "\nstderr:\n" ++ process.stderr)
  IO.println s!"  nargo compile ok: {label} ({pkgRoot})"

unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.NoirCompileAcceptance: start"
  match ← resolveNargoPath with
  | none =>
      IO.println "skipped: nargo unavailable"
      IO.println "Tests.Materialization.NoirCompileAcceptance: ok (skipped)"
  | some nargo => do
      let ver ← IO.Process.output { cmd := nargo, args := #["--version"] }
      IO.println s!"nargo: {nargo}"
      IO.println s!"{ver.stdout.trimAscii.copy}"
      let tmp := FilePath.mk "build/v2/noir-compile-acceptance"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      try
        let pkgs ← materializeNoirPackages "Counter"
          Examples.counterSourceText Examples.counterModuleNameV1 tmp
        for pkg in pkgs do
          runNargoCompile nargo pkg pkg.toString
        IO.println s!"Tests.Materialization.NoirCompileAcceptance: ok ({pkgs.size} package(s))"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.NoirCompileAcceptance
