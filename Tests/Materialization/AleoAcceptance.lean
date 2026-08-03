/-
  Aleo leo-build acceptance suite (engineering only; J2 AleoEmissionFix).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult), wraps the
  emitted `{id}.aleo` Leo source into a temporary Leo 4 package
  (`program.json` + `src/main.leo`), and invokes:

      leo build --offline --disable-update-check

  The suite prefers the materialized Tool Lock root, then known host
  candidates/PATH. Each compiler invocation uses a suite-owned HOME with an
  explicit empty `.aleo` directory, so ambient user configuration cannot make
  a clean runner pass or fail. If no `leo` is available it SKIP-passes with a
  clear log; once resolved, any non-zero compiler exit fails closed.

  Not formal Stage-0 / hermetic Tool Lock verification / snarkVM prove-deploy.
  Maturity remains source-package + engineering compilation acceptance — not
  runtime VM / proof completion.
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

/-- Resolve `leo`: prefer Tool Lock materialize root, then cargo/homebrew/PATH.
    Returns `none` when unavailable (skip path). -/
private def resolveLeoPath : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #["/opt/homebrew/bin/leo", "/usr/local/bin/leo"]
  if let some h := home then
    absCandidates := absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/darwin-arm64/leo")
    absCandidates := absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/linux-x86_64/leo")
    absCandidates := absCandidates.push (h ++ "/.cargo/bin/leo")
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    absCandidates := #[root ++ "/leo"] ++ absCandidates
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
private def runLeoBuild (leo : String) (leoHome pkgRoot : FilePath)
    (programId : String) (leoSource : String) (label : String) : IO Unit := do
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
    env := #[("HOME", leoHome.toString)]
    inheritEnv := true
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
    (leo : String) (leoHome tmp : FilePath)
    (label : String) (sourceText : String) (moduleName : String)
    (aleoFileName : String) : IO Unit := do
  let (source, path) ← materializeAleo label sourceText moduleName aleoFileName
  let programId := programStem path
  let pkg := tmp / programId
  if ← pkg.pathExists then IO.FS.removeDirAll pkg
  IO.FS.createDirAll pkg
  runLeoBuild leo leoHome pkg programId source label

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

/-- Int64 Counter: i64 state mapping + signed add/sub/mul/div/mod/comparison
    + unary neg + shifts, verified end-to-end by `leo build`. -/
private def int64SourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program IntBox where\n" ++
  "  state acc : Int64\n" ++
  "  init(seed : Int64) do\n" ++
  "    acc := seed\n" ++
  "  entry bump(delta : Int64) : Int64 do\n" ++
  "    acc := acc + delta\n" ++
  "    return acc\n" ++
  "  entry diff(a : Int64, b : Int64) : Int64 do\n" ++
  "    return a - b\n" ++
  "  entry quot(a : Int64, b : Int64) : Int64 do\n" ++
  "    return a / b\n" ++
  "  entry remainder(a : Int64, b : Int64) : Int64 do\n" ++
  "    return a % b\n" ++
  "  entry negate(a : Int64) : Int64 do\n" ++
  "    return -a\n" ++
  "  entry less(a : Int64, b : Int64) : Bool do\n" ++
  "    return a < b\n" ++
  "  entry shift(a : Int64) : Int64 do\n" ++
  "    return (a << 2) >> 2\n"

/-- Dense Map UInt64 UInt64 (capacity-2 pilot): mint + transfer with Option
    match arms, verified end-to-end by `leo build`. The computed
    `balanceOf` view (match on state) stays fail-closed on Aleo (only bare
    state reads map to the off-chain query model). -/
private def tokenMapSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program Token where\n" ++
  "  state balances : Map UInt64 UInt64\n" ++
  "  state supply : UInt64\n" ++
  "  init() do\n" ++
  "    balances := Map.empty()\n" ++
  "    supply := 0\n" ++
  "  entry mint(to : UInt64, amount : UInt64) : UInt64 do\n" ++
  "    match balances[to] with\n" ++
  "    | Option.some(v) => do\n" ++
  "      balances[to] := v + amount\n" ++
  "      supply := supply + amount\n" ++
  "      return supply\n" ++
  "    | _ => do\n" ++
  "      balances[to] := amount\n" ++
  "      supply := supply + amount\n" ++
  "      return supply\n" ++
  "  entry transfer(src : UInt64, dst : UInt64, amount : UInt64) : Bool do\n" ++
  "    match balances[src] with\n" ++
  "    | Option.some(fromBal) => do\n" ++
  "      assert fromBal >= amount\n" ++
  "      match balances[dst] with\n" ++
  "      | Option.some(toBal) => do\n" ++
  "        balances[src] := fromBal - amount\n" ++
  "        balances[dst] := toBal + amount\n" ++
  "        return true\n" ++
  "      | _ => do\n" ++
  "        balances[src] := fromBal - amount\n" ++
  "        balances[dst] := amount\n" ++
  "        return true\n" ++
  "    | _ => do\n" ++
  "      assert false\n" ++
  "      return false\n"

/-- Bounded for + Final-block loop (self-balanced brace rendering). -/
private def loopSumSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program LoopSum where\n" ++
  "  state count : UInt64\n" ++
  "  init(initial : UInt64) do\n" ++
  "    count := initial\n" ++
  "  entry sumUp(n : UInt64) : UInt64 do\n" ++
  "    let zero : UInt64 := 0\n" ++
  "    for i in zero ..< n bounded 8 do\n" ++
  "      count := count + i\n" ++
  "    return count\n"

/-- Fixed Bytes N: N×`u8 => u8` mappings with u8 params/results, native u8
    checked arithmetic (Leo trap-on-overflow), verified end-to-end by
    `leo build`. -/
private def bytesBoxSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program BytesBox where\n" ++
  "  state b : Bytes 2\n" ++
  "  init() do\n" ++
  "    b[0] := 0\n" ++
  "    b[1] := 0\n" ++
  "  entry set0(v : UInt8) : UInt8 do\n" ++
  "    b[0] := v\n" ++
  "    return b[0]\n" ++
  "  entry plus(v : UInt8) : UInt8 do\n" ++
  "    b[1] := b[1] + v\n" ++
  "    return b[1]\n" ++
  "  entry flip() : UInt8 do\n" ++
  "    return ~b[0]\n" ++
  "  entry shift(v : UInt8) : UInt8 do\n" ++
  "    b[0] := b[0] << 1\n" ++
  "    return b[0]\n"

/-- T8 multi-width: scalar UInt8 counter with native Leo u8 state/params/body,
    verified end-to-end by `leo build`. -/
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

/-- T8 multi-width: UInt16 + UInt32 dual state, verified by `leo build`. -/
private def multiWidthSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program MultiW where\n" ++
  "  state a : UInt16\n" ++
  "  state b : UInt32\n" ++
  "  init(x : UInt16, y : UInt32) do\n" ++
  "    a := x\n" ++
  "    b := y\n" ++
  "  entry add16(d : UInt16) : UInt16 do\n" ++
  "    a := a + d\n" ++
  "    return a\n" ++
  "  entry add32(d : UInt32) : UInt32 do\n" ++
  "    b := b + d\n" ++
  "    return b\n"

/-- B-RET-ABI: named Struct entry return as a native Leo `(u64, u64)` tuple
    (non-Final, no state). Verified end-to-end by `leo build`. -/
private def pairRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PairRet where\n" ++
  "  struct Pair where\n" ++
  "    a : UInt64\n" ++
  "    b : UInt64\n" ++
  "  entry makePair(x : UInt64, y : UInt64) : Pair do\n" ++
  "    return Pair.new(x, y)\n"

/-- B-RET-ABI: named Enum entry return as a Leo `(u64, u64)` tuple
    (tag + max-payload pad). Verified end-to-end by `leo build`. -/
private def maybeRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program MaybeRet where\n" ++
  "  enum Maybe where\n" ++
  "    | None\n" ++
  "    | Some(UInt64)\n" ++
  "  entry put(v : UInt64) : Maybe do\n" ++
  "    return Maybe.Some(v)\n" ++
  "  entry clear() : Maybe do\n" ++
  "    return Maybe.None()\n"

/-- B-RET-ABI: Final state-touching entry that stores and returns a named
    Struct (result dropped; leaf exprs still evaluated). `leo build` must
    accept the Final form. -/
private def pairStoreSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program PairStore where\n" ++
  "  struct Pair where\n" ++
  "    a : UInt64\n" ++
  "    b : UInt64\n" ++
  "  state p : Pair\n" ++
  "  init(x : UInt64, y : UInt64) do\n" ++
  "    p := Pair.new(x, y)\n" ++
  "  entry setPair(x : UInt64, y : UInt64) : Pair do\n" ++
  "    p := Pair.new(x, y)\n" ++
  "    return p\n"

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
      let leoHomePath := tmp / "home"
      IO.FS.createDirAll (leoHomePath / ".aleo")
      let leoHome ← IO.FS.realPath leoHomePath
      try
        acceptProgram leo leoHome tmp "Counter"
          Examples.counterSourceText Examples.counterModuleNameV1 "counter.aleo"
        acceptProgram leo leoHome tmp "DualField"
          dualFieldSourceText "Tests.AleoAccept.DualField" "dualfield.aleo"
        acceptProgram leo leoHome tmp "Token"
          tokenMapSourceText "Tests.AleoAccept.Token" "token.aleo"
        acceptProgram leo leoHome tmp "PointBox"
          pointBoxSourceText "Tests.AleoAccept.PointBox" "pointbox.aleo"
        acceptProgram leo leoHome tmp "ArrBox"
          arrayStateSourceText "Tests.AleoAccept.ArrBox" "arrbox.aleo"
        acceptProgram leo leoHome tmp "IntBox"
          int64SourceText "Tests.AleoAccept.IntBox" "intbox.aleo"
        acceptProgram leo leoHome tmp "LoopSum"
          loopSumSourceText "Tests.AleoAccept.LoopSum" "loopsum.aleo"
        acceptProgram leo leoHome tmp "BytesBox"
          bytesBoxSourceText "Tests.AleoAccept.BytesBox" "bytesbox.aleo"
        acceptProgram leo leoHome tmp "U8Ctr"
          u8CounterSourceText "Tests.AleoAccept.U8Ctr" "u8ctr.aleo"
        acceptProgram leo leoHome tmp "MultiW"
          multiWidthSourceText "Tests.AleoAccept.MultiW" "multiw.aleo"
        acceptProgram leo leoHome tmp "PairRet"
          pairRetSourceText "Tests.AleoAccept.PairRet" "pairret.aleo"
        acceptProgram leo leoHome tmp "MaybeRet"
          maybeRetSourceText "Tests.AleoAccept.MaybeRet" "mayberet.aleo"
        acceptProgram leo leoHome tmp "PairStore"
          pairStoreSourceText "Tests.AleoAccept.PairStore" "pairstore.aleo"
        IO.println "Tests.Materialization.AleoAcceptance: ok"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.AleoAcceptance
