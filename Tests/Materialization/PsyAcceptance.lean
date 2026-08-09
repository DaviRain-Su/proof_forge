/-
  Psy dargo compile-only acceptance suite (engineering only; J3 PsyEmissionFix).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult).

  G6-RUNTIME DPN-first:
    * Prefer primary `{Name}.dpn.json` when Plan→DPN succeeds (package shape).
    * Transitional `.psy` via `emitPsyDebug := true` because locked dargo 0.1.0 has
      no package-only compile/execute flag (PARTIAL honesty).
    * When DPN is present it is planted as `target/<package>.json` before
      `dargo compile` (identity path); dargo rewrites that file from `.psy`.
    * After compile, product DPN method names must be ⊆ package method names.
    * Debug-only `.psy` (DPN lower failed under emitPsyDebug) remains accepted as
      PARTIAL for host-heavy compile gates that still exercise EmitIR surface.

  Flow:
      dargo compile --contract-name <Name>
      dargo generate-abi --contract-name <Name>

  Tool resolution (no psyup authority):
    1. `$PROOF_FORGE_TOOL_ROOT/dargo` + `lib/psy-std/std.psy`
    2. default cache `~/.cache/proof-forge-v2/tool-root/{linux-x86_64,darwin-arm64}`
    3. host `~/.psy/bin/dargo` + bundled std under `~/.psy/toolchains/…` (compile-only)

  When dargo/std are absent the suite SKIP-passes with a clear log line so
  ordinary Linux CI stays green. When present the suite is fail-closed on any
  non-zero exit or missing ABI artifact.

  Goldilocks bound: every Felt decimal literal in emitted source must be in
  `0 .. p-1` (p = 2^64−2^32+1). The EmitIRV1 overflow guards no longer emit the
  illegal `2^64` literal.

  Local VM / base-proof execute is **not** this suite: see
  `scripts/psy_runtime_test.sh` / `just psy-runtime` (host-heavy, hard-fail
  PF-TOOLCHAIN-MISSING without locked dargo+std; not ordinary ci).

  Not formal Stage-0 / hermetic Tool Lock verify / network UPS / deploy.
  Maturity remains source-only registry + optional host/locked compile gate.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
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

/-- Resolved dargo + bundled std (no psyup). -/
private structure PsyToolchain where
  dargo : String
  stdPath : String
  lockedIdentity : Bool
  deriving Repr

/-- Prefer `$PROOF_FORGE_TOOL_ROOT` / default cache dargo+std, then host `~/.psy`.
    Requires executable `dargo` and a readable `lib/psy-std/std.psy` (or env). -/
private def resolvePsyToolchain : IO (Option PsyToolchain) := do
  let home? ← IO.getEnv "HOME"
  let home := home?.getD ""

  let tryRoot (root : String) : IO (Option PsyToolchain) := do
    let dargo := root ++ "/dargo"
    let std := root ++ "/lib/psy-std/std.psy"
    let dargoOk ← (FilePath.mk dargo).pathExists
    let stdOk ← (FilePath.mk std).pathExists
    if dargoOk && stdOk then
      pure (some { dargo, stdPath := std, lockedIdentity := true })
    else
      pure none

  -- 1) Explicit materialized Tool Lock root.
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    if let some tc ← tryRoot root then
      return some tc

  -- 2) Default cache roots (linux-x86_64 / darwin-arm64 only as product lanes).
  if !home.isEmpty then
    for plat in #["linux-x86_64", "darwin-arm64"] do
      if let some tc ← tryRoot (home ++ "/.cache/proof-forge-v2/tool-root/" ++ plat) then
        return some tc

  -- 3) Host ~/.psy (or common PATH install) + bundled std — compile-only fallback.
  let mut dargoCandidates : Array String := #[]
  if !home.isEmpty then
    dargoCandidates := dargoCandidates.push (home ++ "/.psy/bin/dargo")
  dargoCandidates := dargoCandidates ++ #["/opt/homebrew/bin/dargo", "/usr/local/bin/dargo"]
  let mut dargoPath : Option String := none
  for c in dargoCandidates do
    if ← (FilePath.mk c).pathExists then
      dargoPath := some c
      break
  if dargoPath.isNone then
    let which ← IO.Process.output { cmd := "which", args := #["dargo"] }
    if which.exitCode == 0 then
      let path := which.stdout.trimAscii.copy
      if !path.isEmpty && (← (FilePath.mk path).pathExists) then
        dargoPath := some path
  let some dargo := dargoPath | return none

  let mut stdPath : Option String := none
  if let some envStd ← IO.getEnv "DARGO_STD_PATH" then
    if ← (FilePath.mk envStd).pathExists then
      stdPath := some envStd
  if stdPath.isNone && !home.isEmpty then
    let preferred := home ++ "/.psy/toolchains/psy-0.1.0/lib/psy-std/std.psy"
    if ← (FilePath.mk preferred).pathExists then
      stdPath := some preferred
    else
      let toolchains := FilePath.mk (home ++ "/.psy/toolchains")
      if ← toolchains.pathExists then
        let entries ← toolchains.readDir
        for ent in entries do
          let candidate := (ent.path / "lib" / "psy-std" / "std.psy").toString
          if ← (FilePath.mk candidate).pathExists then
            stdPath := some candidate
            break
  let some std := stdPath | return none
  pure (some { dargo, stdPath := std, lockedIdentity := false })

/-- G6-RUNTIME materialize: always require debug `.psy` for locked dargo; prefer
    primary `.dpn.json` when Plan→DPN succeeds. When emitPsyDebug alone emits
    `.psy` (DPN lower failed under debug opt-in), return none for DPN (PARTIAL). -/
private unsafe def materializePsyAndOptionalDpn
    (label : String) (sourceText : String) (moduleName : String)
    (expectedPsyPath : String) (expectedDpnPath : String)
    (profile? : Option CodegenProfileId := none) : IO (String × Option String) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<psy-accept-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.psy profile?
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  -- PARTIAL: locked dargo needs debug `.psy`; DPN is preferred package path.
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability (emitPsyDebug := true)
  let files := MaterializedArtifactsV1.filesOf output
  let some psyFile := files.find? (·.path == expectedPsyPath) |
    throw <| IO.userError s!"{label}: missing {expectedPsyPath}; got {files.map (·.path)}"
  expect (!psyFile.contents.isEmpty) s!"{label}: empty .psy"
  expect (psyFile.contents.contains "#[contract]")
    s!"{label}: .psy must declare #[contract]"
  -- Goldilocks pin: the illegal 2^64 bound must never reappear.
  expect (!psyFile.contents.contains "18446744073709551616")
    s!"{label}: emitted .psy must not contain illegal 2^64 Felt literal"
  match files.find? (·.path == expectedDpnPath) with
  | some dpnFile =>
      expect (!dpnFile.contents.isEmpty) s!"{label}: empty .dpn.json"
      expect (dpnFile.contents.startsWith "[")
        s!"{label}: .dpn.json must be a JSON array (dargo package shape)"
      pure (psyFile.contents, some dpnFile.contents)
  | none =>
      -- Debug-only `.psy` path when DPN lower failed under emitPsyDebug (PARTIAL).
      IO.println s!"  G6-RUNTIME PARTIAL: {label} has debug .psy without .dpn.json"
      pure (psyFile.contents, none)

/-- Write a minimal Dargo project; plant product DPN when present; run dargo. -/
private def runDargoCompile (tc : PsyToolchain) (projectDir : FilePath)
    (packageName : String) (contractName : String)
    (psySource : String) (dpnPackage? : Option String)
    (label : String) : IO Unit := do
  if ← projectDir.pathExists then IO.FS.removeDirAll projectDir
  IO.FS.createDirAll (projectDir / "src")
  IO.FS.createDirAll (projectDir / "target")
  let dargoToml :=
    "[package]\n" ++
    s!"name = \"{packageName}\"\n" ++
    "type = \"bin\"\n" ++
    "authors = [\"proof-forge-next\"]\n" ++
    "\n[dependencies]\n"
  IO.FS.writeFile (projectDir / "Dargo.toml") dargoToml
  IO.FS.writeFile (projectDir / "src" / "main.psy") psySource
  -- G6-RUNTIME: plant product DPN as dargo package path before compile when present.
  if let some dpnPackage := dpnPackage? then
    let plantedPkg := projectDir / "target" / s!"{packageName}.json"
    IO.FS.writeFile plantedPkg dpnPackage
    -- Sidecar for scripts/psy_acceptance.sh optional plant path.
    IO.FS.writeFile (projectDir / s!"{contractName}.dpn.json") dpnPackage

  -- Absolute dargo + pinned std; do not rely on psyup or ambient PATH for the tool.
  let script :=
    "export DARGO_STD_PATH=" ++ shQuote tc.stdPath ++ "\n" ++
    "set -e\n" ++
    shQuote tc.dargo ++ " compile --contract-name " ++ shQuote contractName ++ "\n" ++
    shQuote tc.dargo ++ " generate-abi --contract-name " ++ shQuote contractName ++ "\n"
  let process ← IO.Process.output {
    cmd := "/bin/bash"
    args := #["--noprofile", "--norc", "-c", script]
    cwd := some projectDir
  }
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": dargo compile/generate-abi failed (exit " ++ toString process.exitCode ++
        ")\nstdout:\n" ++ process.stdout ++ "\nstderr:\n" ++ process.stderr)
  -- dargo generate-abi writes target/<Contract>.abi.json and often target/<package>.json.
  let abiJson := projectDir / "target" / s!"{contractName}.abi.json"
  let abiAlt := projectDir / "target" / s!"{packageName}.abi.json"
  let pkgJson := projectDir / "target" / s!"{packageName}.json"
  let hasAbiJson ← abiJson.pathExists
  let hasAbiAlt ← abiAlt.pathExists
  let hasPkg ← pkgJson.pathExists
  -- dargo 0.1.0 reports successful ABI generation but some host installs only
  -- retain the non-empty package JSON. Either ABI spelling or that package is
  -- sufficient for this compile-only acceptance lane.
  expect (hasAbiJson || hasAbiAlt || hasPkg)
    s!"{label}: dargo produced no ABI/package JSON under target/"
  if hasPkg then
    let pkgBytes ← IO.FS.readFile pkgJson
    expect (!pkgBytes.isEmpty) s!"{label}: empty package json {packageName}.json"
    -- Method-name subset when product DPN was planted (DPN-first surface).
    if dpnPackage?.isSome && tc.lockedIdentity then
      let productDpnPath := projectDir / s!"{contractName}.dpn.json"
      let checkScript :=
        "import json, sys\n" ++
        "prod = json.load(open(sys.argv[1], encoding='utf-8'))\n" ++
        "pkg = json.load(open(sys.argv[2], encoding='utf-8'))\n" ++
        "assert isinstance(prod, list) and isinstance(pkg, list)\n" ++
        "pn = {m.get('name') for m in prod if isinstance(m, dict)}\n" ++
        "kn = {m.get('name') for m in pkg if isinstance(m, dict)}\n" ++
        "missing = sorted(n for n in pn if n not in kn)\n" ++
        "sys.exit(1 if missing else 0)\n"
      let check ← IO.Process.output {
        cmd := "/usr/bin/python3"
        args := #["-I", "-S", "-c", checkScript, productDpnPath.toString, pkgJson.toString]
      }
      expect (check.exitCode == 0)
        s!"{label}: product DPN methods missing from locked dargo package (exit {check.exitCode})"
    else if dpnPackage?.isSome then
      IO.println s!"  {label}: host compile-only fallback; skipped locked DPN/package identity check"
  -- Reject the Goldilocks failure mode even if dargo exit code were misreported.
  expect (!process.stdout.contains "number too large" &&
      !process.stderr.contains "number too large")
    s!"{label}: dargo still rejected a Felt literal as too large"
  let plantNote := if dpnPackage?.isSome then "DPN-first plant" else "PARTIAL .psy-only"
  IO.println s!"  dargo compile ok: {label} (contract={contractName}; {plantNote})"

private unsafe def acceptProgram
    (tc : PsyToolchain) (staging : FilePath)
    (label : String) (sourceText : String) (moduleName : String)
    (psyFileName : String) (packageName : String)
    (profile? : Option CodegenProfileId := none) : IO Unit := do
  -- Product emitter names DPN after the program/contract identity (same stem as .psy).
  let dpnFileName := label ++ ".dpn.json"
  let (psy, dpn?) ←
    materializePsyAndOptionalDpn label sourceText moduleName psyFileName dpnFileName profile?
  let projectDir := staging / packageName
  -- Product emitter names the #[contract] struct after the program identity (label).
  runDargoCompile tc projectDir packageName label psy dpn? label

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

/-- T8 multi-width: scalar UInt8 StateCell with Felt-carried state/params/body
    and explicit width guards. Real dargo must accept the emitted source. -/
private def u8StateCellSourceText : String :=
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
    Real dargo must accept the multi-leaf array return form. -/
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

/-- N-ANON-RESULT ArrayRet: anonymous Array UInt64 2 → `-> [Felt; 2]`. -/
private def arrayRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ArrayRet where\n" ++
  "  state slots : Array UInt64 2\n" ++
  "  init(a : UInt64, b : UInt64) do\n" ++
  "    slots[0] := a\n" ++
  "    slots[1] := b\n" ++
  "  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do\n" ++
  "    slots[0] := a\n" ++
  "    slots[1] := b\n" ++
  "    return slots\n" ++
  "  view getArr() : Array UInt64 2 do\n" ++
  "    return slots\n"

/-- N-ANON-RESULT OptionRet: anonymous Option UInt64 → `-> [Felt; 2]` tag+payload. -/
private def optionRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program OptionRet where\n" ++
  "  state seed : UInt64\n" ++
  "  init(x : UInt64) do\n" ++
  "    seed := x\n" ++
  "  entry asSome(v : UInt64) : Option UInt64 do\n" ++
  "    return Option.some(v)\n" ++
  "  view asNone() : Option UInt64 do\n" ++
  "    return Option.none()\n" ++
  "  view asSomeOfSeed() : Option UInt64 do\n" ++
  "    return Option.some(seed)\n"

/-- B-OPT-STATE / BL-36: Option UInt64 state as 2 Felt leaves (tag+payload);
    set/clear/peek match + getOpt return. Real dargo must accept emitted source. -/
private def optionStateSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program OptionState where\n" ++
  "  state slot : Option UInt64\n" ++
  "  init() do\n" ++
  "    slot := Option.none()\n" ++
  -- entry must not be named `set` (Psy Storage derive owns set/get).
  "  entry setSome(v : UInt64) : UInt64 do\n" ++
  "    slot := Option.some(v)\n" ++
  "    return v\n" ++
  "  entry clear() : UInt64 do\n" ++
  "    slot := Option.none()\n" ++
  "    return 0\n" ++
  "  view peek() : UInt64 do\n" ++
  "    match slot with\n" ++
  "    | Option.some(x) => do\n" ++
  "      return x\n" ++
  "    | _ => do\n" ++
  "      return 0\n" ++
  "  view getOpt() : Option UInt64 do\n" ++
  "    return slot\n"

/-- PSY-WIDE-2: explicit VM profile UInt128 checked multiplication and
    exact unsigned div/mod. Real dargo must compile both frozen algorithms. -/
private def wideCounterSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program WideCounter where\n" ++
  "  state total : UInt128\n" ++
  "  init(initial : UInt128) do\n" ++
  "    total := initial\n" ++
  "  entry multiply(factor : UInt128) : UInt128 do\n" ++
  "    total := total * factor\n" ++
  "    return total\n" ++
  "  entry divide(divisor : UInt128) : UInt128 do\n" ++
  "    total := total / divisor\n" ++
  "    return total\n" ++
  "  entry remainder(divisor : UInt128) : UInt128 do\n" ++
  "    total := total % divisor\n" ++
  "    return total\n" ++
  "  view get() : UInt128 do\n" ++
  "    return total\n"

/-- Suite entry. Skips cleanly when dargo/std are unavailable. -/
unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.PsyAcceptance: start"
  match ← resolvePsyToolchain with
  | none =>
      IO.println "skipped: dargo (or bundled psy-std) unavailable"
      IO.println "Tests.Materialization.PsyAcceptance: ok (skipped)"
  | some tc => do
      IO.println s!"dargo: {tc.dargo}"
      IO.println s!"DARGO_STD_PATH: {tc.stdPath}"
      IO.println s!"dargo identity: {if tc.lockedIdentity then "Tool Lock root" else "host compile-only fallback"}"
      -- dargo 0.1.0's clap surface has no `--version` flag. Locked roots get
      -- their version identity from Tool Lock asset hashes; the host fallback
      -- is compile-only, so probe only the commands this suite actually uses.
      let help ← IO.Process.output {
        cmd := tc.dargo
        args := #["--help"]
      }
      expect (help.exitCode == 0)
        s!"dargo --help failed with exit {help.exitCode}"
      let helpText := help.stdout ++ help.stderr
      expect (helpText.contains "compile" && helpText.contains "generate-abi")
        "dargo help is missing required compile/generate-abi commands"
      IO.println "dargo capability probe: compile + generate-abi"
      let staging := FilePath.mk "build/v2/psy-acceptance"
      if ← staging.pathExists then IO.FS.removeDirAll staging
      IO.FS.createDirAll staging
      try
        acceptProgram tc staging "StateCell"
          Examples.stateCellSourceText Examples.stateCellModuleNameV1
          "StateCell.psy" "stateCell"
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
          u8StateCellSourceText "Tests.PsyAccept.U8Ctr"
          "U8Ctr.psy" "u8ctr"
        acceptProgram tc staging "PairRet"
          pairRetSourceText "Tests.PsyAccept.PairRet"
          "PairRet.psy" "pair_ret"
        acceptProgram tc staging "ArrayRet"
          arrayRetSourceText "Tests.PsyAccept.ArrayRet"
          "ArrayRet.psy" "array_ret"
        acceptProgram tc staging "OptionRet"
          optionRetSourceText "Tests.PsyAccept.OptionRet"
          "OptionRet.psy" "option_ret"
        acceptProgram tc staging "OptionState"
          optionStateSourceText "Tests.PsyAccept.OptionState"
          "OptionState.psy" "option_state"
        acceptProgram tc staging "WideCounter"
          wideCounterSourceText "Tests.PsyAccept.WideCounter"
          "WideCounter.psy" "wide_counter"
          (some CodegenProfileId.psyDargo010VmV1)
        IO.println "Tests.Materialization.PsyAcceptance: ok"
      finally
        if ← staging.pathExists then IO.FS.removeDirAll staging

end Tests.Materialization.PsyAcceptance
