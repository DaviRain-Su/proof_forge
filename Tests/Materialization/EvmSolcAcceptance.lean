/-
  EVM solc acceptance suite (engineering only).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult), writes the
  emitted `.yul` object to a staging directory, and invokes:

      solc --strict-assembly --optimize --bin <name>.yul

  matching FinalizeV1 / locked-solc product finalization args.

  When `solc` is absent from PATH the suite SKIP-passes with a clear log line so
  ordinary Linux CI stays green. When solc is present the suite is fail-closed
  on any non-zero exit or missing binary representation.

  Not formal TASK-D4-04 / hermetic tool lock / Anvil differential.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.EvmSolcAcceptance

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

/-- Resolve `solc` from PATH. Returns `none` when unavailable (skip path). -/
private def resolveSolcPath : IO (Option String) := do
  -- Prefer an explicit absolute path on this Darwin host, then PATH.
  let candidates := #["/opt/homebrew/bin/solc", "/usr/local/bin/solc", "solc"]
  for c in candidates do
    if c.startsWith "/" then
      if ← (FilePath.mk c).pathExists then
        return some c
    else
      let which ← IO.Process.output { cmd := "which", args := #[c] }
      if which.exitCode == 0 then
        let path := which.stdout.trimAscii.copy
        if !path.isEmpty && (← (FilePath.mk path).pathExists) then
          return some path
  return none

/-- Product materialize for the default EVM profile; returns Yul contents + file name. -/
private unsafe def materializeYul
    (label : String) (sourceText : String) (moduleName : String)
    (expectedYulPath : String) : IO (String × String) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<evm-solc-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.evm none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  let some yulFile := files.find? (·.path == expectedYulPath) |
    throw <| IO.userError s!"{label}: missing {expectedYulPath}; got {files.map (·.path)}"
  expect (!yulFile.contents.isEmpty) s!"{label}: empty Yul"
  expect (yulFile.contents.startsWith "object \"")
    s!"{label}: Yul must start with top-level object"
  pure (yulFile.contents, expectedYulPath)

/-- Run `solc --strict-assembly --optimize --bin <file>` in `cwd`; fail closed on error.
    B-EVM-MAP-STACK: stderr must never report StackTooDeep (dense Map/Token). -/
private def runSolc (solc : String) (cwd : FilePath) (yulFileName : String)
    (label : String) : IO Unit := do
  let process ← IO.Process.output {
    cmd := solc
    args := #["--strict-assembly", "--optimize", "--bin", yulFileName]
    cwd := some cwd
  }
  let combined := process.stdout ++ "\n" ++ process.stderr
  expect (!combined.contains "StackTooDeep" && !combined.contains "Stack too deep")
    s!"{label}: solc reported StackTooDeep (B-EVM-MAP-STACK regression)\n{combined}"
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": solc --strict-assembly --optimize --bin failed (exit " ++
        toString process.exitCode ++ ")\nstdout:\n" ++ process.stdout ++
        "\nstderr:\n" ++ process.stderr)
  expect (process.stdout.contains "Binary representation:")
    s!"{label}: solc stdout missing Binary representation header\n{process.stdout}"
  let binary := (process.stdout.splitOn "Binary representation:\n").getLast!.trimAscii.copy
  expect (!binary.isEmpty)
    s!"{label}: solc returned empty bytecode"
  -- Hex-only sanity (solc may append a trailing newline already trimmed).
  expect (binary.all fun c =>
      ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F'))
    s!"{label}: solc bytecode is not hex: {binary.take 64}…"
  IO.println s!"  solc ok: {label} → {binary.length / 2} bytes"

private unsafe def acceptProgram
    (solc : String) (tmp : FilePath)
    (label : String) (sourceText : String) (moduleName : String)
    (yulFileName : String) : IO Unit := do
  let (yul, path) ← materializeYul label sourceText moduleName yulFileName
  let outPath := tmp / path
  IO.FS.writeFile outPath yul
  runSolc solc tmp path label

private def fieldLaneSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program FieldLane where\n" ++
  "  state acc : Field bn254_fr\n" ++
  "  init(initial : Field bn254_fr) do\n" ++
  "    acc := initial\n" ++
  "  entry add(delta : Field bn254_fr) : Field bn254_fr do\n" ++
  "    acc := acc + delta\n" ++
  "    return acc\n" ++
  "  entry sub(delta : Field bn254_fr) : Field bn254_fr do\n" ++
  "    acc := acc - delta\n" ++
  "    return acc\n" ++
  "  entry mul(factor : Field bn254_fr) : Field bn254_fr do\n" ++
  "    acc := acc * factor\n" ++
  "    return acc\n" ++
  "  entry div(den : Field bn254_fr) : Field bn254_fr do\n" ++
  "    return acc / den\n" ++
  "  entry neg(x : Field bn254_fr) : Field bn254_fr do\n" ++
  "    return -x\n" ++
  "  entry eq(a : Field bn254_fr, b : Field bn254_fr) : Bool do\n" ++
  "    return a == b\n" ++
  "  view get() : Field bn254_fr do\n" ++
  "    return acc\n"

private def loopSumSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program LoopSum where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry addUp(n : UInt64) : UInt64 do\n" ++
  "    let limit : UInt64 := n + 4\n" ++
  "    for i in n ..< limit bounded 8 do\n" ++
  "      count := count + i\n" ++
  "    return count\n" ++
  "  entry scan(n : UInt64) : UInt64 do\n" ++
  "    for i in n ..< n bounded 2 do\n" ++
  "      count := count + 1\n" ++
  "    return count\n" ++
  "  view get() : UInt64 do\n" ++
  "    return count\n"

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

/-- String param ABI surface (N4 multi-word). Exercises 9×UInt64 leaf loads
    (len + 8 data words) in emitted Yul. String state storage routing and
    string-literal compare SSA consumption remain LowerSemantic gaps outside
    this wave's EmitIRV1 allowlist — see suite notes. -/
private def strBoxSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program StrBox where\n" ++
  "  state pad : UInt64\n" ++
  "  init(i : UInt64) do\n" ++
  "    pad := i\n" ++
  "  entry check(x : String) : Bool do\n" ++
  "    return true\n" ++
  "  view get() : UInt64 do\n" ++
  "    return pad\n"

/-- BL-18: anonymous Array UInt64 2 view return (tuple ABI / returnAggregate). -/
private def arrayRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ArrayRet where\n" ++
  "  state slots : Array UInt64 2\n" ++
  "  init() do\n" ++
  "    slots[0] := 0\n" ++
  "    slots[1] := 0\n" ++
  "  view getArr() : Array UInt64 2 do\n" ++
  "    return slots\n"

/-- BL-18: anonymous Option UInt64 none/some view returns (tag+payload tuple). -/
private def optionRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program OptionRet where\n" ++
  "  state flag : UInt64\n" ++
  "  init(f : UInt64) do\n" ++
  "    flag := f\n" ++
  "  view getNone() : Option UInt64 do\n" ++
  "    return Option.none()\n" ++
  "  view getSome(x : UInt64) : Option UInt64 do\n" ++
  "    return Option.some(x)\n"

/-- BL-31 / B-OPT-STATE: Option UInt64 state (tag+payload slots) + match read
    + none reset. Must compile under solc 0.8.34 strict-assembly. -/
private def optionStateSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program OptionState where\n" ++
  "  state slot : Option UInt64\n" ++
  "  init() do\n" ++
  "    slot := Option.none()\n" ++
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
  "      return 0\n"

/-- B-EVM-MAP-STACK: shipped Token dense Map must pass the suite-resolved
    host `solc` without StackTooDeep (24-leaf storeAtomic spill). The separate
    `Tests.Product.TokenV1` CLI path remains the locked-solc authority.
    Reads `Examples/Token.lean`. -/
private unsafe def acceptShippedToken
    (solc : String) (tmp : FilePath) : IO Unit := do
  let path := FilePath.mk "Examples/Token.lean"
  unless ← path.pathExists do
    throw <| IO.userError "Examples/Token.lean missing (B-EVM-MAP-STACK vector)"
  let text ← IO.FS.readFile path
  acceptProgram solc tmp "Token" text "Examples.Token" "Token.yul"

/-- Suite entry. Skips cleanly when solc is unavailable. -/
unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.EvmSolcAcceptance: start"
  match ← resolveSolcPath with
  | none =>
      IO.println "skipped: solc unavailable"
      IO.println "Tests.Materialization.EvmSolcAcceptance: ok (skipped)"
  | some solc => do
      let ver ← IO.Process.output { cmd := solc, args := #["--version"] }
      IO.println s!"solc: {solc}"
      IO.println s!"{ver.stdout.trimAscii.copy}"
      -- Deterministic staging under build/ (matches other CLI/materialization tests).
      let tmp := FilePath.mk "build/v2/evm-solc-acceptance"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      try
        acceptProgram solc tmp "StateCell"
          Examples.stateCellSourceText Examples.stateCellModuleNameV1 "StateCell.yul"
        acceptProgram solc tmp "PointBox"
          pointBoxSourceText "Tests.EvmSolc.PointBox" "PointBox.yul"
        acceptProgram solc tmp "FieldLane"
          fieldLaneSourceText "Tests.EvmSolc.FieldLane" "FieldLane.yul"
        acceptProgram solc tmp "StrBox"
          strBoxSourceText "Tests.EvmSolc.StrBox" "StrBox.yul"
        acceptProgram solc tmp "LoopSum"
          loopSumSourceText "Tests.EvmSolc.LoopSum" "LoopSum.yul"
        acceptProgram solc tmp "ArrayRet"
          arrayRetSourceText "Tests.EvmSolc.ArrayRet" "ArrayRet.yul"
        acceptProgram solc tmp "OptionRet"
          optionRetSourceText "Tests.EvmSolc.OptionRet" "OptionRet.yul"
        -- BL-31: Option UInt64 state (2-slot tag+payload) under solc strict-assembly.
        acceptProgram solc tmp "OptionState"
          optionStateSourceText "Tests.EvmSolc.OptionState" "OptionState.yul"
        -- Dense Map 24-leaf storeAtomic: spill must keep solc stack depth finite.
        -- Token stack budget must remain unaffected by Option state admission.
        acceptShippedToken solc tmp
        IO.println "Tests.Materialization.EvmSolcAcceptance: ok"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.EvmSolcAcceptance
