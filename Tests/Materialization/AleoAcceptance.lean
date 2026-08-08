/-
  Aleo leo-build acceptance suite (engineering only; ALEO-I3 locked-Leo path).

  Builds representative ProgramV1 sources through the product capability path
  (select → compileValidatedSourceV1 → resolve → materializeResult with
  `emitLeoDebug := true`), wraps the dual-written transitional `{id}.leo`
  Leo 4 source (ALEO-IR-6: product primary `{id}.aleo` is Instructions when
  lower succeeds) into a temporary Leo 4 package (`program.json` +
  `src/main.leo`), and invokes:

      leo build --offline --disable-update-check

  Locked tool only (matches LockedToolchainV1.candidatePath):
    1) $PROOF_FORGE_TOOL_ROOT/leo when set
    2) else package default cache tool-root/<platform>/leo
  No PATH / cargo / homebrew fallback. Soft absence → clean skip (not a pass
  that claims compile acceptance). When a locked candidate is present, the
  suite hard-verifies via LockedToolchainV1.resolve (exact 4.0.2 + sha pin);
  any resolve error (including PF-TOOLCHAIN-MISSING from env/stat/lock
  corruption) fails closed and is never remapped to skip.

  Each compiler invocation uses a suite-owned HOME with an empty `.aleo`
  directory and inheritEnv := false (no ambient PRIVATE_KEY/VIEW_KEY/NETWORK
  or other Aleo secret/network env). Compile-only; no run/execute/deploy/query.

  Not formal Stage-0 / hermetic Tool Lock verification / snarkVM prove-deploy.
  This wider corpus gate remains host-optional; ALEO-I4 separately provides an
  opt-in product compile profile. Neither is runtime VM / proof completion.
  The default source-profile FinalizeV1 stays zero-tool.
-/
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import Tests.Language.ParserSession

namespace Tests.Materialization.AleoAcceptance

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Materialization.LockedToolchainV1
open ProofForgeV2.Targets.BuildSelectionV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

/-- Default product CodegenProfileId for Aleo source-only acceptance
    (lock requiredByProfiles join; compile profile is control-plane only here). -/
private def aleoCodegenProfileWire : String := CodegenProfileId.aleoLeoU64V1.toString

/-- Package-owned default cache path for locked leo (platform wire). -/
private def defaultLockedLeoPath (home platformWire : String) : String :=
  home ++ "/.cache/proof-forge-v2/tool-root/" ++ platformWire ++ "/leo"

private def toolRootLeoPath (root : String) : String :=
  root ++ "/leo"

/-- Isolation allowlist for leo build: suite HOME + portable locale only.
    Ambient secrets/network keys are never inherited (inheritEnv := false).
    Process env uses `Option String` (some = set). -/
private def aleoIsolatedEnv (leoHome : String) : Array (String × Option String) :=
  #[("HOME", some leoHome), ("LC_ALL", some "C"), ("TZ", some "UTC")]

private def isAleoSecretOrNetworkEnvKey (key : String) : Bool :=
  key == "PRIVATE_KEY" || key == "VIEW_KEY" || key == "ADDRESS" ||
  key == "NETWORK" || key == "ENDPOINT" || key == "DEVNET" ||
  key == "CONSENSUS_VERSION" || key == "CONSENSUS_VERSION_HEIGHTS" ||
  key == "CONSENSUS_HEIGHTS" || key == "NETWORK_RETRIES" ||
  key == "PRIORITY_FEE" || key == "FEE_RECORD"

/-- Soft locked-path probe only (no PATH/cargo/homebrew). Returns `none` when
    the locked candidate is absent so the suite can skip cleanly. When
    `PROOF_FORGE_TOOL_ROOT` is set, only that root is considered (no silent
    fall-through to the default cache), matching LockedToolchainV1. -/
private def softLockedLeoPath : IO (Option String) := do
  match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
  | some root =>
      let path := toolRootLeoPath root
      if ← (FilePath.mk path).pathExists then
        pure (some path)
      else
        pure none
  | none =>
      match ← IO.getEnv "HOME" with
      | none => pure none
      | some home =>
          let platformWire :=
            if System.Platform.isOSX then "darwin-arm64" else "linux-x86_64"
          let path := defaultLockedLeoPath home platformWire
          if ← (FilePath.mk path).pathExists then
            pure (some path)
          else
            pure none

/-- Soft-skip is legal only when the soft locked candidate is absent.
    Once a candidate exists, every LockedToolchainV1.resolve error
    (including PF-TOOLCHAIN-MISSING from env/stat/lock corruption) is
    fail-closed — never remapped to skip. -/
private def maySoftSkip (softPresent : Bool) : Bool := !softPresent

/-- Hard resolve: Tool Lock identity/sha/version via LockedToolchainV1.resolve.
    Soft absence → `none` (host-optional skip). Soft presence + any resolve
    error fails closed (does not catch/remap PF-TOOLCHAIN-MISSING). -/
private def resolveLockedLeo : IO (Option String) := do
  match ← softLockedLeoPath with
  | none => pure none
  | some _ =>
      -- No catch-to-skip: soft-hit requires successful hard resolve.
      let verified : VerifiedTool ← resolve "leo"
      expect (verified.version == "4.0.2")
        s!"locked leo version must be 4.0.2, got {verified.version}"
      expect (verified.id == "leo") "locked tool id must be leo"
      pure (some verified.path.toString)

/-- Policy unit tests: locked path shape, no PATH fallback surface, isolation
    allowlist, sole CodegenProfileId pin, soft-skip-only-when-absent contract.
    Does not require a materialized leo. -/
private def testLockedResolverPolicy : IO Unit := do
  expect (aleoCodegenProfileWire == "aleo-leo-4.0.2-u64-v1")
    "default Aleo source CodegenProfileId must be aleo-leo-4.0.2-u64-v1"
  expect (CodegenProfileId.aleoLeoU64CompileV1.toString ==
      "aleo-leo-4.0.2-u64-compile-v1")
    "compile profile constant must be aleo-leo-4.0.2-u64-compile-v1"
  expect (aleoCodegenProfileWire != "aleo-leo-build-v1")
    "phantom acceptance-lane profile id must not be the product pin"
  let fromRoot := toolRootLeoPath "/tmp/pf-tool-root"
  expect (fromRoot == "/tmp/pf-tool-root/leo") "tool-root leo path shape"
  expect (!fromRoot.contains ".cargo" && !fromRoot.contains "homebrew" &&
      !fromRoot.contains "/usr/local" && !fromRoot.contains "/opt/")
    "tool-root path must not encode PATH/cargo/homebrew fallbacks"
  let defDarwin := defaultLockedLeoPath "/Users/x" "darwin-arm64"
  expect (defDarwin ==
      "/Users/x/.cache/proof-forge-v2/tool-root/darwin-arm64/leo")
    "darwin default cache path"
  let defLinux := defaultLockedLeoPath "/home/x" "linux-x86_64"
  expect (defLinux ==
      "/home/x/.cache/proof-forge-v2/tool-root/linux-x86_64/leo")
    "linux default cache path"
  for p in #[defDarwin, defLinux] do
    expect (!p.contains ".cargo" && !p.contains "homebrew")
      s!"default cache must not use cargo/homebrew: {p}"
  let env := aleoIsolatedEnv "/tmp/aleo-suite-home"
  expect (env.size == 3) "isolation allowlist is HOME+LC_ALL+TZ only"
  expect (env.any (fun p => p.1 == "HOME" && p.2.isSome) &&
      env.any (fun p => p.1 == "LC_ALL" && p.2.isSome) &&
      env.any (fun p => p.1 == "TZ" && p.2.isSome))
    "isolation allowlist keys"
  for (k, _) in env do
    expect (!isAleoSecretOrNetworkEnvKey k)
      s!"isolation allowlist must not carry secret/network key {k}"
  for k in #["PRIVATE_KEY", "VIEW_KEY", "ADDRESS", "NETWORK", "ENDPOINT",
      "DEVNET", "PRIORITY_FEE", "FEE_RECORD"] do
    expect (isAleoSecretOrNetworkEnvKey k)
      s!"secret/network key table must recognize {k}"
    expect (!env.any (fun p => p.1 == k)) s!"allowlist must omit ambient key {k}"
  -- Soft-skip contract (P2): only soft absence may skip; soft-hit + any
  -- resolve error (including PF-TOOLCHAIN-MISSING) must fail closed.
  expect (maySoftSkip false == true)
    "soft absence may skip"
  expect (maySoftSkip true == false)
    "soft presence must not soft-skip"
  -- Simulated resolve error messages after soft-hit remain fail-closed inputs.
  for msg in #["PF-TOOLCHAIN-MISSING: required toolchain 'leo' is not available",
      "PF-TOOLCHAIN-MISMATCH: toolchain 'leo' expected '4.0.2', found 'x'",
      "PF-TOOLCHAIN-MISMATCH: invalid embedded lock: corrupted"] do
    expect (!maySoftSkip true)
      s!"soft-hit + resolve error must not skip ({msg.take 32}…)"
  -- Locked bundle surface: executable-only leo (no runtime dylib closure).
  match requiredBundlePaths "leo" with
  | .error error =>
      throw <| IO.userError s!"locked leo closure could not be resolved: {error}"
  | .ok paths =>
      expect (paths == #["leo"])
        "leo requiredBundlePaths must be the single executable"
  IO.println "  locked-resolver policy ok (no PATH fallback; soft-skip-only-when-absent; env allowlist)"

/-- Product materialize with ALEO-IR-6 Leo debug dual-write; returns Leo 4
    source for locked `leo build` acceptance (not the Instructions primary).
    `expectedAleoPath` is the primary `{id}.aleo` path used to derive program id. -/
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
    Targets.materializeResult capability (emitLeoDebug := true)
  let files := MaterializedArtifactsV1.filesOf output
  let some primaryFile := files.find? (·.path == expectedAleoPath) |
    throw <| IO.userError s!"{label}: missing primary {expectedAleoPath}; got {files.map (·.path)}"
  expect (!primaryFile.contents.isEmpty) s!"{label}: empty primary .aleo"
  expect (primaryFile.contents.contains "program ")
    s!"{label}: primary must declare a program"
  let programId :=
    if expectedAleoPath.endsWith ".aleo" then (expectedAleoPath.dropEnd 5).copy
    else expectedAleoPath
  let leoPath := s!"{programId}.leo"
  let some leoFile := files.find? (·.path == leoPath) |
    throw <| IO.userError s!"{label}: missing dual-write {leoPath}; got {files.map (·.path)}"
  expect (!leoFile.contents.isEmpty) s!"{label}: empty Leo debug source"
  expect (leoFile.contents.contains "program ")
    s!"{label}: Leo debug source must declare a program"
  expect (leoFile.contents.contains ".aleo {")
    s!"{label}: Leo debug source must be brace-form Leo 4"
  expect (!leoFile.contents.contains "boolean")
    s!"{label}: Leo 4 uses bool, not boolean"
  expect (!leoFile.contents.contains "return ();")
    s!"{label}: Leo 4 rejects return ()"
  pure (leoFile.contents, expectedAleoPath)

/-- Stem of `{id}.aleo` → `{id}` for package layout. -/
private def programStem (aleoPath : String) : String :=
  if aleoPath.endsWith ".aleo" then (aleoPath.dropEnd 5).copy else aleoPath

/-- Write a Leo 4 package around dual-written `.leo` source and run locked
    `leo build --offline --disable-update-check` under isolated env. -/
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
  -- ALEO-IR-6: feed dual-written Leo 4 source, not Instructions primary.
  IO.FS.writeFile (pkgRoot / "src" / "main.leo") leoSource
  -- True empty-env isolation via `/usr/bin/env -i` (matches LockedToolchainV1
  -- runIsolated discipline). Suite HOME only — no ambient secrets/network keys.
  let process ← IO.Process.output {
    cmd := "/usr/bin/env"
    args := #[
      "-i",
      s!"HOME={leoHome.toString}",
      "LC_ALL=C",
      "TZ=UTC",
      leo,
      "build",
      "--offline",
      "--disable-update-check"
    ]
    cwd := some pkgRoot
    inheritEnv := false
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

/-- N-ANON-RESULT: anonymous Array UInt64 2 Final entry return (state
    IndexSet + StateLoad; source has no Array value constructor). Plan form
    is `.array`; Final evaluates leaves and drops. `leo build` must accept. -/
private def arrayRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program ArrayRet where\n" ++
  "  state slots : Array UInt64 2\n" ++
  "  init() do\n" ++
  "    slots[0] := 0\n" ++
  "    slots[1] := 0\n" ++
  "  entry setArr(a : UInt64, b : UInt64) : Array UInt64 2 do\n" ++
  "    slots[0] := a\n" ++
  "    slots[1] := b\n" ++
  "    return slots\n"

/-- N-ANON-RESULT: anonymous Option UInt64 non-state entries as Leo
    `(bool, u64)`. Verified end-to-end by `leo build`. -/
private def optionRetSourceText : String :=
  "import ProofForgeV2\n" ++
  "open ProofForgeV2.Language\n" ++
  "program OptionRet where\n" ++
  "  entry put(v : UInt64) : Option UInt64 do\n" ++
  "    return Option.some(v)\n" ++
  "  entry clear() : Option UInt64 do\n" ++
  "    return Option.none()\n"

/-- B-OPT-STATE / BL-35: Option UInt64 state as 2 mapping leaves
    (tag + payload). Match-on-state is an entry (computed views stay FC on
    Aleo). Verified end-to-end by `leo build`. -/
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
  "  entry peek() : UInt64 do\n" ++
  "    match slot with\n" ++
  "    | Option.some(x) => do\n" ++
  "      return x\n" ++
  "    | _ => do\n" ++
  "      return 0\n"

/-- Suite entry. Policy tests always run. Compile acceptance skips cleanly when
    locked leo is unavailable (never PATH-fallback; never pretends pass). -/
unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.AleoAcceptance: start"
  testLockedResolverPolicy
  match ← resolveLockedLeo with
  | none =>
      IO.println "skipped: locked leo unavailable"
      IO.println s!"  profile pin: {aleoCodegenProfileWire}"
      IO.println "  no PATH/cargo/homebrew fallback; host-optional skip-clean"
      IO.println "Tests.Materialization.AleoAcceptance: ok (skipped)"
  | some leo => do
      -- Version identity + executable sha already hard-checked by
      -- LockedToolchainV1.resolve (exact expectedVersion 4.0.2). Re-probe via
      -- env -i for the log line (same isolation as runLeoBuild).
      let ver ← IO.Process.output {
        cmd := "/usr/bin/env"
        args := #["-i", "LC_ALL=C", "TZ=UTC", leo, "--version"]
        inheritEnv := false
      }
      let verText := (ver.stdout ++ ver.stderr).trimAscii.copy
      IO.println s!"leo: {leo}"
      IO.println s!"profile: {aleoCodegenProfileWire}"
      IO.println s!"{verText}"
      expect (ver.exitCode == 0 && verText.contains "4.0.2")
        s!"locked leo --version must contain 4.0.2 (exit {ver.exitCode})\n{verText}"
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
        acceptProgram leo leoHome tmp "ArrayRet"
          arrayRetSourceText "Tests.AleoAccept.ArrayRet" "arrayret.aleo"
        acceptProgram leo leoHome tmp "OptionRet"
          optionRetSourceText "Tests.AleoAccept.OptionRet" "optionret.aleo"
        acceptProgram leo leoHome tmp "OptionState"
          optionStateSourceText "Tests.AleoAccept.OptionState" "optionstate.aleo"
        IO.println "Tests.Materialization.AleoAcceptance: ok"
      finally
        if ← tmp.pathExists then IO.FS.removeDirAll tmp

end Tests.Materialization.AleoAcceptance
