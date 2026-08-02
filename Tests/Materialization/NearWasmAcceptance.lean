/-
  NEAR Wasm acceptance suite (engineering only; gap C-1).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult), writes the
  emitted `.wat` to a staging directory, then invokes host tools:

      wat2wasm <name>.wat -o <name>.wasm
      wasm-interp --dummy-import-func <name>.wasm

  matching FinalizeV1 / product WAT emission + a real WABT interpreter load
  with stubbed NEAR `env.*` host imports.

  Tool resolution (any absolute path that exists, then PATH):
  - wat2wasm: /opt/homebrew/bin, /usr/local/bin, PATH
  - runtime: wasm-interp preferred (WABT --dummy-import-func); else wasmtime
    (`wasmtime compile`); else wasmer (`wasmer validate` / compile)

  When the required tools are absent the suite SKIP-passes with a clear log
  line so ordinary Linux CI stays green. When tools are present the suite is
  fail-closed on non-zero exit, missing Wasm magic, or empty artifacts.

  Not formal Stage-0 / hermetic tool lock / NEAR sandbox receipt differential.
  Dummy host stubs return zero — export *execution* semantics remain the Lean
  NearHostModel authority; this gate proves product WAT is well-formed Wasm
  that compiles and instantiates under a real engine.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.NearWasmAcceptance

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

/-- Resolve an executable: absolute candidates first, then PATH `which`. -/
private def resolveTool (names : Array String) : IO (Option String) := do
  let absCandidates := #["/opt/homebrew/bin/", "/usr/local/bin/"]
  for name in names do
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

private structure Toolchain where
  wat2wasm : String
  /-- Runtime engine path. -/
  runtime : String
  /-- `wasm-interp` | `wasmtime` | `wasmer` -/
  runtimeKind : String

/-- Prefer WABT wat2wasm + wasm-interp (product finalize already needs wat2wasm).
    Fall back to wasmtime/wasmer for the runtime half when wasm-interp missing. -/
private def resolveToolchain : IO (Option Toolchain) := do
  let some wat2wasm ← resolveTool #["wat2wasm"] | return none
  if let some interp ← resolveTool #["wasm-interp"] then
    return some {
      wat2wasm
      runtime := interp
      runtimeKind := "wasm-interp"
    }
  if let some wt ← resolveTool #["wasmtime"] then
    return some {
      wat2wasm
      runtime := wt
      runtimeKind := "wasmtime"
    }
  if let some wm ← resolveTool #["wasmer"] then
    return some {
      wat2wasm
      runtime := wm
      runtimeKind := "wasmer"
    }
  return none

/-- Product materialize for the default NEAR profile; returns WAT + file name. -/
private unsafe def materializeWat
    (label : String) (sourceText : String) (moduleName : String)
    (expectedWatPath : String) : IO (String × String) := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult s!"load {label}" (← session.selectProgramV1
    sourceText s!"<near-wasm-{label}>" moduleName none)
  let compiled ← liftResult s!"compile {label}" <|
    Compiler.compileValidatedSourceV1 source
  let selection ← liftResult s!"select {label}" <|
    resolveBuildSelectionV1 TargetId.near none
  let capability ← liftResult s!"resolve {label}" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled
  let output ← liftResult s!"materialize {label}" <|
    Targets.materializeResult capability
  let files := MaterializedArtifactsV1.filesOf output
  let some watFile := files.find? (·.path == expectedWatPath) |
    throw <| IO.userError s!"{label}: missing {expectedWatPath}; got {files.map (·.path)}"
  expect (!watFile.contents.isEmpty) s!"{label}: empty WAT"
  expect (watFile.contents.contains "(module")
    s!"{label}: WAT must contain top-level module"
  pure (watFile.contents, expectedWatPath)

/-- Assert binary starts with Wasm magic `\0asm`. -/
private def expectWasmMagic (label : String) (wasmPath : FilePath) : IO Unit := do
  let bytes ← IO.FS.readBinFile wasmPath
  expect (bytes.size >= 8)
    s!"{label}: wasm smaller than header ({bytes.size} bytes)"
  expect (
      bytes[0]! == 0 &&
      bytes[1]! == 'a'.toUInt8 &&
      bytes[2]! == 's'.toUInt8 &&
      bytes[3]! == 'm'.toUInt8)
    s!"{label}: missing Wasm magic \\0asm"

/-- Run wat2wasm in `cwd`; fail closed. -/
private def runWat2Wasm (wat2wasm : String) (cwd : FilePath)
    (watName wasmName : String) (label : String) : IO Unit := do
  let process ← IO.Process.output {
    cmd := wat2wasm
    args := #[watName, "-o", wasmName]
    cwd := some cwd
  }
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": wat2wasm failed (exit " ++ toString process.exitCode ++
        ")\nstdout:\n" ++ process.stdout ++ "\nstderr:\n" ++ process.stderr)
  expectWasmMagic label (cwd / wasmName)

/-- Instantiate/validate the Wasm with the resolved runtime engine. -/
private def runRuntime (tc : Toolchain) (cwd : FilePath) (wasmName : String)
    (label : String) : IO Unit := do
  let process ← match tc.runtimeKind with
    | "wasm-interp" =>
        -- Load + instantiate with dummy NEAR env.* stubs (return zero).
        -- Does not assert host-storage semantics (see NearHostModel).
        IO.Process.output {
          cmd := tc.runtime
          args := #["--dummy-import-func", wasmName]
          cwd := some cwd
        }
    | "wasmtime" =>
        -- Cranelift compile validates structure without requiring host imports.
        IO.Process.output {
          cmd := tc.runtime
          args := #["compile", wasmName]
          cwd := some cwd
        }
    | "wasmer" =>
        IO.Process.output {
          cmd := tc.runtime
          args := #["validate", wasmName]
          cwd := some cwd
        }
    | other =>
        throw <| IO.userError s!"{label}: unknown runtime kind {other}"
  unless process.exitCode == 0 do
    throw <| IO.userError
      (label ++ ": " ++ tc.runtimeKind ++ " failed (exit " ++
        toString process.exitCode ++ ")\nstdout:\n" ++ process.stdout ++
        "\nstderr:\n" ++ process.stderr)
  IO.println s!"  {tc.runtimeKind} ok: {label} ({wasmName})"

private unsafe def acceptProgram
    (tc : Toolchain) (tmp : FilePath)
    (label : String) (sourceText : String) (moduleName : String)
    (watFileName : String) : IO Unit := do
  let (wat, path) ← materializeWat label sourceText moduleName watFileName
  let outPath := tmp / path
  IO.FS.writeFile outPath wat
  -- Artifact stems are ASCII program identifiers (Counter.wat → Counter.wasm).
  let wasmName :=
    if path.endsWith ".wat" then
      (path.dropEnd 4).copy ++ ".wasm"
    else
      path ++ ".wasm"
  runWat2Wasm tc.wat2wasm tmp path wasmName label
  runRuntime tc tmp wasmName label

/-- Multi-field public UInt64 state (NEAR KV aggregate surface). Named Struct
    state remains fail-closed on NEAR Plan (see Targets N3); scalar multi-field
    is the shipped aggregate-state path for this acceptance gate. -/
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
  "  entry setY(v : UInt64) : UInt64 do\n" ++
  "    y := v\n" ++
  "    return y\n" ++
  "  view getX() : UInt64 do\n" ++
  "    return x\n" ++
  "  view getY() : UInt64 do\n" ++
  "    return y\n"

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

/-- Software multiword UInt128 add/sub/mul surface: exact literal products
    (base-2^32 schoolbook in the WAT) compared with wide equality. Structural
    wat2wasm validation only — the host model owns arithmetic semantics. -/
private def wideArithSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program WideArith where\n" ++
  "  state p : UInt128\n" ++
  "  init() do\n" ++
  "    p := 0\n" ++
  "  entry mul128() : Bool do\n" ++
  "    let r : UInt128 := 0x10000000100000003 * 0x100000002\n" ++
  "    p := r\n" ++
  "    return p == 0x1000000030000000500000006\n" ++
  "  entry add128() : Bool do\n" ++
  "    let r : UInt128 := 0x10000000100000003 + 0x100000002\n" ++
  "    return r == 0x10000000200000005\n" ++
  "  entry sub128() : Bool do\n" ++
  "    let r : UInt128 := 0x10000000100000003 - 0x100000002\n" ++
  "    return r == 0x10000000000000001\n"

/-- Bytes 2 state flattened to 1-byte UInt8 KV leaves (index store/load). -/
private def byteBoxSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ByteBox where\n" ++
  "  state data : Bytes 2\n" ++
  "  init() do\n" ++
  "    data[0] := 0\n" ++
  "    data[1] := 0\n" ++
  "  entry set0(v : UInt8) : UInt8 do\n" ++
  "    data[0] := v\n" ++
  "    return data[0]\n" ++
  "  view get1() : UInt8 do\n" ++
  "    return data[1]\n"

/-- Suite entry. Skips cleanly when wat2wasm + a Wasm runtime are unavailable. -/
unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.NearWasmAcceptance: start"
  match ← resolveToolchain with
  | none =>
      IO.println "skipped: wat2wasm + wasm runtime (wasm-interp|wasmtime|wasmer) unavailable"
      IO.println "Tests.Materialization.NearWasmAcceptance: ok (skipped)"
  | some tc => do
      let ver ← IO.Process.output { cmd := tc.wat2wasm, args := #["--version"] }
      IO.println s!"wat2wasm: {tc.wat2wasm}"
      IO.println s!"{ver.stdout.trimAscii.copy}"
      IO.println s!"runtime: {tc.runtimeKind} @ {tc.runtime}"
      let tmp := FilePath.mk "build/v2/near-wasm-acceptance"
      if ← tmp.pathExists then IO.FS.removeDirAll tmp
      IO.FS.createDirAll tmp
      try
        acceptProgram tc tmp "Counter"
          Examples.counterSourceText Examples.counterModuleNameV1 "Counter.wat"
        acceptProgram tc tmp "DualField"
          dualFieldSourceText "Tests.NearWasm.DualField" "DualField.wat"
        acceptProgram tc tmp "LoopSum"
          loopSumSourceText "Tests.NearWasm.LoopSum" "LoopSum.wat"
        acceptProgram tc tmp "WideArith"
          wideArithSourceText "Tests.NearWasm.WideArith" "WideArith.wat"
        acceptProgram tc tmp "ByteBox"
          byteBoxSourceText "Tests.NearWasm.ByteBox" "ByteBox.wat"
        IO.println "Tests.Materialization.NearWasmAcceptance: ok"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.NearWasmAcceptance
