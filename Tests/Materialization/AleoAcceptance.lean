/-
  Aleo leo-build acceptance suite (engineering only; J2 AleoEmissionFix).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult), wraps the
  emitted `{id}.aleo` Leo source into a temporary Leo 4 package
  (`program.json` + `src/main.leo`), and invokes:

      leo build --offline --disable-update-check

  When `leo` is absent from PATH the suite SKIP-passes with a clear log line so
  ordinary Linux CI stays green. When leo is present the suite is fail-closed
  on any non-zero exit.

  Not formal Stage-0 / hermetic Tool Lock pin / snarkVM prove-deploy.
  Maturity remains source-package + toolchain compilation acceptance when leo
  is available — not runtime VM / proof completion.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.AleoAcceptance

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

/-- Resolve `leo` from PATH. Returns `none` when unavailable (skip path). -/
private def resolveLeoPath : IO (Option String) := do
  -- Prefer cargo-installed leo (common on Darwin dev hosts), then PATH.
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #["/opt/homebrew/bin/leo", "/usr/local/bin/leo"]
  if let some h := home then
    absCandidates := absCandidates.push (h ++ "/.cargo/bin/leo")
  for c in absCandidates do
    if ← (FilePath.mk c).pathExists then
      return some c
  let which ← IO.Process.output { cmd := "which", args := #["leo"] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

/-- Product materialize for the default Aleo profile; returns Leo source + path. -/
private unsafe def materializeAleo
    (label : String) (sourceText : String) (moduleName : String)
    (expectedAleoPath : String) : IO (String × String) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<aleo-accept-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.aleo none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  let some aleoFile := files.find? (·.path == expectedAleoPath) |
    throw <| IO.userError s!"{label}: missing {expectedAleoPath}; got {files.map (·.path)}"
  expect (!aleoFile.contents.isEmpty) s!"{label}: empty Leo source"
  expect (aleoFile.contents.contains "program ")
    s!"{label}: Leo source must declare a program"
  expect (!aleoFile.contents.contains "boolean")
    s!"{label}: Leo 4 uses bool, not boolean"
  expect (!aleoFile.contents.contains "return ();")
    s!"{label}: Leo 4 rejects return ()"
  pure (aleoFile.contents, expectedAleoPath)

/-- Stem of `{id}.aleo` → `{id}` for package layout. -/
private def programStem (aleoPath : String) : String :=
  if aleoPath.endsWith ".aleo" then (aleoPath.dropEnd 5).copy else aleoPath

/-- Write a Leo 4 package around product-emitted source and run `leo build`. -/
private def runLeoBuild (leo : String) (pkgRoot : FilePath) (programId : String)
    (leoSource : String) (label : String) : IO Unit := do
  IO.FS.createDirAll (pkgRoot / "src")
  -- program.json must match the `program {id}.aleo` declaration.
  let programJson :=
    "{\n" ++
    s!"  \"program\": \"{programId}.aleo\",\n" ++
    "  \"version\": \"0.1.0\",\n" ++
    "  \"description\": \"proof-forge-next aleo acceptance\",\n" ++
    "  \"license\": \"MIT\",\n" ++
    "  \"leo\": \"4.0.2\",\n" ++
    "  \"dependencies\": null,\n" ++
    "  \"dev_dependencies\": null\n" ++
    "}\n"
  IO.FS.writeFile (pkgRoot / "program.json") programJson
  IO.FS.writeFile (pkgRoot / "src" / "main.leo") leoSource
  let process ← IO.Process.output {
    cmd := leo
    args := #["build", "--offline", "--disable-update-check"]
    cwd := some pkgRoot
  }
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": leo build failed (exit " ++ toString process.exitCode ++
        ")\nstdout:\n" ++ process.stdout ++ "\nstderr:\n" ++ process.stderr)
  expect
    (process.stdout.contains "Compiled" ||
      process.stdout.contains "into Aleo instructions")
    s!"{label}: leo build stdout missing success marker\n{process.stdout}"
  IO.println s!"  leo build ok: {label} ({programId}.aleo)"

private unsafe def acceptProgram
    (leo : String) (tmp : FilePath)
    (label : String) (sourceText : String) (moduleName : String)
    (aleoFileName : String) : IO Unit := do
  let (source, path) ← materializeAleo label sourceText moduleName aleoFileName
  let programId := programStem path
  let pkg := tmp / programId
  if ← pkg.pathExists then IO.FS.removeDirAll pkg
  IO.FS.createDirAll pkg
  runLeoBuild leo pkg programId source label

/-- Named Struct flatten-to-mapping leaves (H3 Aleo aggregate surface).
    Program id must not contain the substring "aleo" (Leo ENV03711001). -/
private def pointBoxSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PointBox where\n" ++
  "  struct Point where\n" ++
  "    x : UInt64\n" ++
  "    y : UInt64\n" ++
  "  state p : Point\n" ++
  "  init() do\n" ++
  "    p := Point.new(0, 0)\n" ++
  "  entry setX(v : UInt64) : UInt64 do\n" ++
  "    p.x := v\n" ++
  "    return p.x\n" ++
  "  view getX() : UInt64 do\n" ++
  "    return p.x\n"

/-- Fixed Array UInt64 2 flatten-to-mapping leaves. -/
private def arrayStateSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ArrBox where\n" ++
  "  state slots : Array UInt64 2\n" ++
  "  init() do\n" ++
  "    slots[0] := 0\n" ++
  "    slots[1] := 0\n" ++
  "  entry set0(v : UInt64) : UInt64 do\n" ++
  "    slots[0] := v\n" ++
  "    return slots[0]\n" ++
  "  view get0() : UInt64 do\n" ++
  "    return slots[0]\n"

/-- Multi-field scalar public UInt64 state (no named aggregate). -/
private def dualFieldSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program DualField where\n" ++
  "  state x : UInt64\n" ++
  "  state y : UInt64\n" ++
  "  init(seed : UInt64) do\n" ++
  "    x := seed\n" ++
  "    y := seed\n" ++
  "  entry setX(v : UInt64) : UInt64 do\n" ++
  "    x := v\n" ++
  "    return x\n" ++
  "  view getX() : UInt64 do\n" ++
  "    return x\n"

/-- Suite entry. Skips cleanly when leo is unavailable. -/
unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.AleoAcceptance: start"
  match ← resolveLeoPath with
  | none =>
      IO.println "skipped: leo unavailable"
      IO.println "Tests.Materialization.AleoAcceptance: ok (skipped)"
  | some leo => do
      let ver ← IO.Process.output { cmd := leo, args := #["--version"] }
      IO.println s!"leo: {leo}"
      IO.println s!"{ver.stdout.trimAscii.copy}"
      let tmp := FilePath.mk "build/v2/aleo-acceptance"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      try
        acceptProgram leo tmp "Counter"
          Examples.counterSourceText Examples.counterModuleNameV1 "counter.aleo"
        acceptProgram leo tmp "DualField"
          dualFieldSourceText "Tests.AleoAccept.DualField" "dualfield.aleo"
        acceptProgram leo tmp "PointBox"
          pointBoxSourceText "Tests.AleoAccept.PointBox" "pointbox.aleo"
        acceptProgram leo tmp "ArrBox"
          arrayStateSourceText "Tests.AleoAccept.ArrBox" "arrbox.aleo"
        IO.println "Tests.Materialization.AleoAcceptance: ok"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.AleoAcceptance
