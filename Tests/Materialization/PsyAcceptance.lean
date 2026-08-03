/-
  Psy dargo/psyup acceptance suite (engineering only; J3 PsyEmissionFix).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult), writes the
  emitted `.psy` into a minimal Dargo project (`Dargo.toml` + `src/main.psy`),
  and invokes:

      psyup build

  which wraps `dargo compile` + `dargo generate-abi` with the local
  `DARGO_STD_PATH` (bundled psy-std under `~/.psy/toolchains/…`).

  When `psyup`/`dargo` are absent the suite SKIP-passes with a clear log line so
  ordinary Linux CI stays green. When present the suite is fail-closed on any
  non-zero exit or missing ABI artifact.

  Goldilocks bound: every Felt decimal literal in emitted source must be in
  `0 .. p-1` (p = 2^64−2^32+1). The EmitIRV1 overflow guards no longer emit the
  illegal `2^64` literal.

  Not formal Stage-0 / hermetic tool lock / Psy VM prove gate. Maturity remains
  source-only with a real toolchain *compilation* acceptance check.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.PsyAcceptance

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

/-- Single-quote a string for POSIX `sh` (no expansion). -/
private def shQuote (s : String) : String :=
  "'" ++ s.replace "'" "'\\''" ++ "'"

/-- Resolved local Psy toolchain (psyup + dargo + bundled std). -/
private structure PsyToolchain where
  psyup : String
  dargo : String
  stdPath : String
  binDir : String
  deriving Repr

/-- Prefer `$HOME/.psy/bin`, then PATH. Requires both psyup and dargo plus a
    readable `DARGO_STD_PATH` (bundled under `~/.psy/toolchains/psy-*/lib/psy-std`). -/
private def resolvePsyToolchain : IO (Option PsyToolchain) := do
  let home? ← IO.getEnv "HOME"
  let home := home?.getD ""
  let psyHomeCandidates : Array String :=
    if home.isEmpty then #[] else #[home ++ "/.psy"]
  let mut binDirs : Array String := #[]
  for h in psyHomeCandidates do
    binDirs := binDirs.push (h ++ "/bin")
  binDirs := binDirs ++ #["/opt/homebrew/bin", "/usr/local/bin"]

  let resolveIn (name : String) : IO (Option String) := do
    for dir in binDirs do
      let path := dir ++ "/" ++ name
      if ← (FilePath.mk path).pathExists then
        return some path
    let which ← IO.Process.output { cmd := "which", args := #[name] }
    if which.exitCode == 0 then
      let path := which.stdout.trimAscii.copy
      if !path.isEmpty && (← (FilePath.mk path).pathExists) then
        return some path
    return none

  let some psyup ← resolveIn "psyup" | return none
  let some dargo ← resolveIn "dargo" | return none

  -- Locate bundled std.psy (psyup sets DARGO_STD_PATH from the active toolchain).
  let mut stdPath : Option String := none
  if let some envStd ← IO.getEnv "DARGO_STD_PATH" then
    if ← (FilePath.mk envStd).pathExists then
      stdPath := some envStd
  if stdPath.isNone && !home.isEmpty then
    let toolchains := FilePath.mk (home ++ "/.psy/toolchains")
    if ← toolchains.pathExists then
      -- Prefer the conventional 0.1.0 layout, then any psy-* directory.
      let preferred :=
        home ++ "/.psy/toolchains/psy-0.1.0/lib/psy-std/std.psy"
      if ← (FilePath.mk preferred).pathExists then
        stdPath := some preferred
      else
        let entries ← toolchains.readDir
        for ent in entries do
          let candidate :=
            (ent.path / "lib" / "psy-std" / "std.psy").toString
          if ← (FilePath.mk candidate).pathExists then
            stdPath := some candidate
            break
  let some std := stdPath | return none

  let binDir :=
    let p := FilePath.mk psyup
    match p.parent with
    | some parent => parent.toString
    | none => home ++ "/.psy/bin"
  pure (some {
    psyup
    dargo
    stdPath := std
    binDir
  })

/-- Product materialize for the default Psy profile; returns `.psy` contents + path. -/
private unsafe def materializePsy
    (label : String) (sourceText : String) (moduleName : String)
    (expectedPsyPath : String) : IO (String × String) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<psy-accept-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.psy none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  let some psyFile := files.find? (·.path == expectedPsyPath) |
    throw <| IO.userError s!"{label}: missing {expectedPsyPath}; got {files.map (·.path)}"
  expect (!psyFile.contents.isEmpty) s!"{label}: empty .psy"
  expect (psyFile.contents.contains "#[contract]")
    s!"{label}: .psy must declare #[contract]"
  -- Goldilocks pin: the illegal 2^64 bound must never reappear.
  expect (!psyFile.contents.contains "18446744073709551616")
    s!"{label}: emitted .psy must not contain illegal 2^64 Felt literal"
  pure (psyFile.contents, expectedPsyPath)

/-- Write a minimal Dargo project and run `psyup build`. -/
private def runPsyupBuild (tc : PsyToolchain) (projectDir : FilePath)
    (packageName : String) (psySource : String) (label : String) : IO Unit := do
  if ← projectDir.pathExists then IO.FS.removeDirAll projectDir
  IO.FS.createDirAll (projectDir / "src")
  let dargoToml :=
    "[package]\n" ++
    s!"name = \"{packageName}\"\n" ++
    "type = \"bin\"\n" ++
    "authors = [\"proof-forge-next\"]\n" ++
    "\n[dependencies]\n"
  IO.FS.writeFile (projectDir / "Dargo.toml") dargoToml
  IO.FS.writeFile (projectDir / "src" / "main.psy") psySource

  -- Inherit the host environment; only prepend ~/.psy/bin and pin std so
  -- `dargo` does not try to clone the missing PsyProtocol/psy-v1 git repo.
  let oldPath := (← IO.getEnv "PATH").getD "/usr/bin:/bin"
  let newPath := tc.binDir ++ ":" ++ oldPath
  let script :=
    "export PATH=" ++ shQuote newPath ++ "\n" ++
    "export DARGO_STD_PATH=" ++ shQuote tc.stdPath ++ "\n" ++
    "exec " ++ shQuote tc.psyup ++ " build\n"
  let process ← IO.Process.output {
    cmd := "/bin/bash"
    args := #["--noprofile", "--norc", "-c", script]
    cwd := some projectDir
  }
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": psyup build failed (exit " ++ toString process.exitCode ++
        ")\nstdout:\n" ++ process.stdout ++ "\nstderr:\n" ++ process.stderr)
  -- dargo generate-abi writes target/<package>.abi.json (or .json).
  let abiJson := projectDir / "target" / s!"{packageName}.abi.json"
  let abiAlt := projectDir / "target" / s!"{packageName}.json"
  let hasAbiJson ← abiJson.pathExists
  let hasAbiAlt ← abiAlt.pathExists
  expect (hasAbiJson || hasAbiAlt)
    s!"{label}: psyup build produced no ABI under target/ ({packageName}.abi.json|.json)"
  -- Reject the Goldilocks failure mode even if dargo exit code were misreported.
  expect (!process.stdout.contains "number too large" &&
      !process.stderr.contains "number too large")
    s!"{label}: dargo still rejected a Felt literal as too large"
  IO.println s!"  psyup ok: {label}"

private unsafe def acceptProgram
    (tc : PsyToolchain) (staging : FilePath)
    (label : String) (sourceText : String) (moduleName : String)
    (psyFileName : String) (packageName : String) : IO Unit := do
  let (psy, _path) ← materializePsy label sourceText moduleName psyFileName
  let projectDir := staging / packageName
  runPsyupBuild tc projectDir packageName psy label

private def pointBoxSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PsyPoint where\n" ++
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

private def arrayStateSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PsyArr where\n" ++
  "  state slots : Array UInt64 2\n" ++
  "  init() do\n" ++
  "    slots[0] := 0\n" ++
  "    slots[1] := 0\n" ++
  "  entry set0(v : UInt64) : UInt64 do\n" ++
  "    slots[0] := v\n" ++
  "    return slots[0]\n"

/-- T8 multi-width: UInt32 bitNot as Felt-carried XOR mask (not native u32).
    The acceptance gate compiles the emitted `.psy` with the real dargo toolchain. -/
private def u32BitNotSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PsyFlip32 where\n" ++
  "  entry flip(x : UInt32) : UInt32 do\n" ++
  "    return ~x\n"

/-- T8 multi-width: scalar UInt8 counter with Felt-carried state/params/body
    and explicit width guards. Real psyup must accept the emitted source. -/
private def u8CounterSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program U8Ctr where\n" ++
  "  state count : UInt8\n" ++
  "  init(seed : UInt8) do\n" ++
  "    count := seed\n" ++
  "  entry increment(delta : UInt8) : UInt8 do\n" ++
  "    count := count + delta\n" ++
  "    return count\n" ++
  "  entry flip() : UInt8 do\n" ++
  "    return ~count\n" ++
  "  view get() : UInt8 do\n" ++
  "    return count\n"

/-- B-RET-ABI PairRet: named Struct view return emitted as `-> [Felt; 2]`.
    Real psyup/dargo must accept the multi-leaf array return form. -/
private def pairRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PairRet where\n" ++
  "  struct Pair where\n" ++
  "    a : UInt64\n" ++
  "    b : UInt64\n" ++
  "  state p : Pair\n" ++
  "  init(x : UInt64, y : UInt64) do\n" ++
  "    p := Pair.new(x, y)\n" ++
  "  view getPair() : Pair do\n" ++
  "    return p\n"

/-- Suite entry. Skips cleanly when psyup/dargo/std are unavailable. -/
unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.PsyAcceptance: start"
  match ← resolvePsyToolchain with
  | none =>
      IO.println "skipped: psyup/dargo (or bundled psy-std) unavailable"
      IO.println "Tests.Materialization.PsyAcceptance: ok (skipped)"
  | some tc => do
      IO.println s!"psyup: {tc.psyup}"
      IO.println s!"dargo: {tc.dargo}"
      IO.println s!"DARGO_STD_PATH: {tc.stdPath}"
      let pathEnv := tc.binDir ++ ":" ++ (← IO.getEnv "PATH").getD "/usr/bin:/bin"
      let ver ← IO.Process.output {
        cmd := "/bin/bash"
        args := #["--noprofile", "--norc", "-c",
          "export PATH=" ++ shQuote pathEnv ++ "; " ++ shQuote tc.psyup ++ " version"]
      }
      IO.println s!"{ver.stdout.trimAscii.copy}"
      let staging := FilePath.mk "build/v2/psy-acceptance"
      if ← staging.pathExists then IO.FS.removeDirAll staging
      IO.FS.createDirAll staging
      try
        acceptProgram tc staging "Counter"
          Examples.counterSourceText Examples.counterModuleNameV1
          "Counter.psy" "counter"
        acceptProgram tc staging "PsyPoint"
          pointBoxSourceText "Tests.PsyAccept.PsyPoint"
          "PsyPoint.psy" "psy_point"
        acceptProgram tc staging "PsyArr"
          arrayStateSourceText "Tests.PsyAccept.PsyArr"
          "PsyArr.psy" "psy_arr"
        acceptProgram tc staging "PsyFlip32"
          u32BitNotSourceText "Tests.PsyAccept.PsyFlip32"
          "PsyFlip32.psy" "psy_flip32"
        acceptProgram tc staging "U8Ctr"
          u8CounterSourceText "Tests.PsyAccept.U8Ctr"
          "U8Ctr.psy" "u8ctr"
        acceptProgram tc staging "PairRet"
          pairRetSourceText "Tests.PsyAccept.PairRet"
          "PairRet.psy" "pair_ret"
        IO.println "Tests.Materialization.PsyAcceptance: ok"
      finally
        if ← staging.pathExists then IO.FS.removeDirAll staging

end Tests.Materialization.PsyAcceptance
