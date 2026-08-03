/-
  D3/S7b engineering FinalizedArtifactsV1 finalization-authority tests.

  Real product path only:
    compileValidatedSourceV1 → resolveBuildSelectionV1 →
    resolveEngineeringRequirementsV1 → materializeResult →
    finalizeMaterializedArtifactsV1 / emitProgram

  Not formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity /
  SupportClaim / ToolchainIdentity. No forged private-ctor carriers;
  no reimplemented on-disk renderer.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.CLI.Main
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Semantic.WireV1
import ProofForgeV2.Targets.Evm.FinalizeV1
import ProofForgeV2.Targets.Near.FinalizeV1
import Tests.Language.ParserSession
import Lean
import Lean.Elab.Command

namespace Tests.Materialization.EngineeringFinalizationV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open System
open Lean
open Lean.Elab.Command

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def materializeOk (label : String) (capability : Targets.ResolvedEngineeringBuildV1) :
    IO MaterializedArtifactsV1 :=
  liftResult label (Targets.materializeResult capability)

private def accumulatorSourceTextV1 : String :=
  "import ProofForgeV2\n\n" ++
  "namespace ProofForgeV2.Examples\n\n" ++
  "open ProofForgeV2.Language\n\n" ++
  "program Accumulator where\n" ++
  "  state total : UInt64\n\n" ++
  "  init(seed : UInt64) do\n" ++
  "    total := seed\n\n" ++
  "  entry add(amount : UInt64) : UInt64 do\n" ++
  "    total := total + amount\n" ++
  "    return total\n\n" ++
  "  view current() : UInt64 do\n" ++
  "    return total\n\n" ++
  "end ProofForgeV2.Examples\n"

private def accumulatorModuleNameV1 : String := "Examples.Accumulator"

private unsafe def compileCounter : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<finalization-counter>"
    Examples.counterModuleNameV1 none)
  liftResult "compile Counter" (Compiler.compileValidatedSourceV1 source)

private unsafe def compileAccumulator : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Accumulator" (← session.selectProgramV1
    accumulatorSourceTextV1 "<finalization-accumulator>"
    accumulatorModuleNameV1 none)
  liftResult "compile Accumulator" (Compiler.compileValidatedSourceV1 source)

private def solanaNote : String :=
  "no pinned/approved sBPF assembler is configured; typed plan and IDL artifacts are non-executable"

private def noirNote : String :=
  "no approved and digest-pinned Noir compiler/proving backend is configured; relation source/schema were emitted without ACIR, witness execution, proof, or verification"

private def aleoNote : String :=
  "product finalization does not invoke the locked Leo compiler or a proving backend; emitted Leo source carries no leo build, execution, proof, or deployment evidence"

/-- Expect an IO error whose message contains `needle`. -/
private def expectIoErrorContains (label needle : String) (act : IO Unit) : IO Unit := do
  try
    act
    throw <| IO.userError s!"{label}: expected failure containing {needle}"
  catch e =>
    let msg := toString e
    expect ((msg.splitOn needle).length > 1)
      s!"{label}: expected '{needle}' in:\n{msg}"

/-- Sole mint + capability/artifact binding positives/negatives. -/
private unsafe def testSoleMintBinding : IO Unit := do
  let compiled ← compileCounter
  let artifactName := CompiledSemanticV1.artifactProgramNameOf compiled
  let sourceDigest := CompiledSemanticV1.sourceDigestOf compiled
  let semanticDigest := CompiledSemanticV1.semanticDigestOf compiled
  let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult "resolve solana"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← materializeOk "materialize solana" capability
  let draft : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #[]
    evidenceNote := solanaNote
  }
  let ok ← liftResult "mint ok" (mintFinalizedArtifactsV1 capability artifacts draft)
  expect (FinalizedArtifactsV1.deployableOf ok == false) "solana mint deployable false"
  expect (FinalizedArtifactsV1.extraFilesOf ok == #[]) "solana mint empty extras"
  expect (FinalizedArtifactsV1.evidenceNoteOf ok == solanaNote) "solana mint note exact"
  expect (MaterializedArtifactsV1.targetIdOf (FinalizedArtifactsV1.artifactsOf ok) ==
      TargetId.solana) "mint binds solana artifacts"
  expect (Targets.ResolvedEngineeringBuildV1.targetIdOf
      (FinalizedArtifactsV1.capabilityOf ok) == TargetId.solana)
    "mint binds solana capability"
  -- Empty extras + base files preserved.
  expect (MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf ok) ==
      MaterializedArtifactsV1.filesOf artifacts)
    "mint does not alter base files"
  -- Extra path collision with base → reject.
  let collide : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #["Counter.sbpf-plan"]
    evidenceNote := solanaNote
  }
  match mintFinalizedArtifactsV1 capability artifacts collide with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "base-path collision → invalidProgram"
  | .ok _ => throw <| IO.userError "extra colliding with base must not mint"
  -- Unsafe extra path → reject.
  let unsafeExtra : EngineeringFinalizationDraftV1 := {
    deployable := false
    extraFiles := #["../escape.bin"]
    evidenceNote := solanaNote
  }
  match mintFinalizedArtifactsV1 capability artifacts unsafeExtra with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "unsafe extra → invalidProgram"
  | .ok _ => throw <| IO.userError "unsafe extra must not mint"
  -- Duplicate extras → reject.
  let dupExtra : EngineeringFinalizationDraftV1 := {
    deployable := true
    extraFiles := #["Counter.bin", "Counter.bin"]
    evidenceNote := "x"
  }
  match mintFinalizedArtifactsV1 capability artifacts dupExtra with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "duplicate extra → invalidProgram"
  | .ok _ => throw <| IO.userError "duplicate extra must not mint"
  -- Capability/artifact target drift via foreign capability.
  let nearSel ← liftResult "select near" (resolveBuildSelectionV1 TargetId.near none)
  let nearCap ← liftResult "resolve near"
    (Targets.resolveEngineeringRequirementsV1 nearSel compiled)
  match mintFinalizedArtifactsV1 nearCap artifacts draft with
  | .error e =>
      expect (e.code == "PF-REGISTRY-INVALID") "target drift → registryInvalid"
  | .ok _ => throw <| IO.userError "capability/artifact target drift must not mint"
  expect (MaterializedArtifactsV1.artifactProgramNameOf artifacts == artifactName &&
      MaterializedArtifactsV1.sourceDigestOf artifacts == sourceDigest &&
      MaterializedArtifactsV1.semanticDigestOf artifacts == semanticDigest)
    "materialized carrier must preserve compiled semantic identity"
  -- Same-target identity gates: Counter artifacts + Accumulator capability.
  let accCompiled ← compileAccumulator
  expect (CompiledSemanticV1.artifactProgramNameOf accCompiled != artifactName)
    "Accumulator name diverges from Counter"
  expect (CompiledSemanticV1.sourceDigestOf accCompiled != sourceDigest)
    "Accumulator source digest diverges from Counter"
  expect (CompiledSemanticV1.semanticDigestOf accCompiled != semanticDigest)
    "Accumulator semantic digest diverges from Counter"
  let accSel ← liftResult "select solana acc" (resolveBuildSelectionV1 TargetId.solana none)
  let accCap ← liftResult "resolve solana acc"
    (Targets.resolveEngineeringRequirementsV1 accSel accCompiled)
  -- Same targetId; artifact name/digests must still fail closed.
  match mintFinalizedArtifactsV1 accCap artifacts draft with
  | .error e =>
      expect (e.code == "PF-SRC-INVALID") "compiled identity drift → invalidProgram"
      expect (((e.render.splitOn "artifact program name").length > 1) ||
          ((e.render.splitOn "source digest").length > 1) ||
          ((e.render.splitOn "semantic digest").length > 1))
        s!"identity drift message expected name/digest, got:\n{e.render}"
  | .ok _ =>
      throw <| IO.userError "same-target different-program identity drift must not mint"
  -- Publisher dual-defense extras (would catch mint skip of path uniqueness).
  let basePaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  expectIoErrorContains "publisher collide base" "PF-OUTPUT-PATH" do
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["Counter.sbpf-plan"]
  expectIoErrorContains "publisher unsafe" "PF-OUTPUT-PATH" do
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["../escape.bin"]
  expectIoErrorContains "publisher dup extra" "PF-OUTPUT-PATH" do
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["extra.bin", "extra.bin"]
  -- Happy path dual-defense accepts safe unique extras.
  ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["Counter.bin"]

/-- Pre-IO bind: mismatched capability/artifacts fail before tool invocation. -/
private unsafe def testPreIoBindBeforeTools : IO Unit := do
  let counter ← compileCounter
  let accumulator ← compileAccumulator
  let counterSel ← liftResult "select evm counter"
    (resolveBuildSelectionV1 TargetId.evm none)
  let counterCap ← liftResult "resolve evm counter"
    (Targets.resolveEngineeringRequirementsV1 counterSel counter)
  let counterArtifacts ← materializeOk "mat counter evm" counterCap
  let accSel ← liftResult "select evm acc" (resolveBuildSelectionV1 TargetId.evm none)
  let accCap ← liftResult "resolve evm acc"
    (Targets.resolveEngineeringRequirementsV1 accSel accumulator)
  -- Pre-IO compiled identity bind must fail before writing extras.
  -- (If tools ran first with valid Counter.yul, solc would write Counter.bin.)
  let staging := FilePath.mk "build/v2/finalization-preio-bind"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  for f in MaterializedArtifactsV1.filesOf counterArtifacts do
    IO.FS.writeFile (staging / f.path) f.contents
  try
    let _ ← Targets.finalizeMaterializedArtifactsV1 accCap counterArtifacts staging
    throw <| IO.userError "mismatched program pair must fail finalize pre-IO"
  catch e =>
    let msg := toString e
    -- If this was a re-throw of our own assertion, surface it.
    if (msg.splitOn "mismatched program pair").length > 1 then
      throw e
    expect ((msg.splitOn "PF-TOOLCHAIN-MISSING").length == 1)
      s!"pre-IO bind must not invoke tools (TOOLCHAIN-MISSING):\n{msg}"
    expect ((msg.splitOn "PF-TOOLCHAIN-MISMATCH").length == 1)
      s!"pre-IO bind must not invoke tools (TOOLCHAIN-MISMATCH):\n{msg}"
    expect ((msg.splitOn "PF-SRC-INVALID").length > 1)
      s!"pre-IO bind must surface compiled identity failure:\n{msg}"
    expect (!(← (staging / "Counter.bin").pathExists))
      "pre-IO bind failure must not write .bin extra"

/-- Hermetic PF-ARTIFACT-NONDEPLOYABLE gates (empty solc bytecode + bad Wasm). -/
private unsafe def testNonDeployablePhases : IO Unit := do
  -- Empty solc bytecode presence gate.
  expectIoErrorContains "empty solc bytecode" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Evm.FinalizeV1.requireNonemptySolcBytecode ""
  -- Non-empty bytecode accepts (gate is post-trim in finalize).
  Targets.Evm.FinalizeV1.requireNonemptySolcBytecode "6000"
  -- Missing Wasm artifact path.
  let staging := FilePath.mk "build/v2/finalization-nondeployable"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  expectIoErrorContains "missing wasm" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "Counter.wasm")
  -- Non-file (directory) Wasm path.
  IO.FS.createDirAll (staging / "Counter.wasm")
  expectIoErrorContains "wasm dir not file" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "Counter.wasm")
  IO.FS.removeDirAll (staging / "Counter.wasm")
  -- Invalid Wasm header (too short / wrong magic).
  IO.FS.writeBinFile (staging / "Counter.wasm") (ByteArray.mk #[0x00, 0x01, 0x02, 0x03])
  expectIoErrorContains "bad wasm header" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "Counter.wasm")
  expectIoErrorContains "bad wasm magic bytes" "PF-ARTIFACT-NONDEPLOYABLE" do
    Targets.Near.FinalizeV1.requireValidWasmHeader (ByteArray.mk #[0x00, 0x61, 0x73, 0x6d])
  -- Valid minimal header accepts.
  let validHeader := ByteArray.mk #[0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]
  Targets.Near.FinalizeV1.requireValidWasmHeader validHeader
  IO.FS.writeBinFile (staging / "Counter.wasm") validHeader
  Targets.Near.FinalizeV1.requireDeployableWasmArtifact (staging / "Counter.wasm")

/-- Exact finalization paths/deployable/evidence notes via the product path. -/
private unsafe def testFourTargetFinalization : IO Unit := do
  let compiled ← compileCounter
  let sourceHash ← liftResult "derive Counter source hash"
    (CompiledSemanticV1.artifactSourceHashHexOf compiled)
  -- Solana: zero-tool product emit.
  do
    let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve solana"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat solana" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    let outDir := FilePath.mk "build/v2/finalization-solana"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == false) "solana emit non-deployable"
    expect (receipt.target == TargetId.solana) "solana emit target"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"solana base byte preservation {f.path}"
    expect (!(← (outDir / "Counter.bin").pathExists)) "solana no .bin"
    expect (!(← (outDir / "Counter.wasm").pathExists)) "solana no .wasm"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn solanaNote).length > 1) "solana exact note on disk"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "\"deployable\": false").length > 1) "solana manifest non-deployable"
    expect ((manifest.splitOn "Counter.sbpf-plan").length > 1) "solana base in manifest"
  -- Noir: zero-tool product emit.
  do
    let selection ← liftResult "select noir" (resolveBuildSelectionV1 TargetId.noir none)
    let capability ← liftResult "resolve noir"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat noir" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    let outDir := FilePath.mk "build/v2/finalization-noir"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == false) "noir emit non-deployable"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"noir base byte preservation {f.path}"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn noirNote).length > 1) "noir exact note on disk"
  -- Aleo: product finalization remains zero-tool even though compile-only
  -- acceptance can resolve locked Leo 4.0.2 independently.
  do
    let selection ← liftResult "select aleo" (resolveBuildSelectionV1 TargetId.aleo none)
    let capability ← liftResult "resolve aleo"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let outDir := FilePath.mk "build/v2/finalization-aleo"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == false) "aleo emit non-deployable"
    expect (receipt.target == TargetId.aleo) "aleo emit target"
    expect (!(← (outDir / "Counter.wasm").pathExists)) "aleo no compiled wasm"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn aleoNote).length > 1) "aleo exact zero-tool note on disk"
    expect ((evidence.splitOn "no approved and digest-pinned Leo compiler").length == 1)
      "aleo evidence must not deny the separate locked Leo acceptance tool"
  -- EVM: real solc .bin extra + base preservation.
  do
    let selection ← liftResult "select evm" (resolveBuildSelectionV1 TargetId.evm none)
    let capability ← liftResult "resolve evm"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat evm" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    expect (baseFiles.map (·.path) == #["Counter.yul", "Counter.abi.json"])
      "evm base paths"
    let outDir := FilePath.mk "build/v2/finalization-evm"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == true) "evm emit deployable"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"evm base byte preservation {f.path}"
    let binPath := outDir / "Counter.bin"
    expect (← binPath.pathExists) "evm writes Counter.bin"
    let bin ← IO.FS.readFile binPath
    expect (!bin.isEmpty && bin.endsWith "\n") "evm .bin nonempty trailing newline"
    let hexBody := if bin.endsWith "\n" then bin.dropEnd 1 |>.copy else bin
    expect (hexBody.all fun c =>
        ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f') || ('A' ≤ c && c ≤ 'F'))
      "evm .bin is hex bytecode + newline"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn "solc ").length > 1) "evm evidence solc note"
    expect ((evidence.splitOn "completed successfully").length > 1)
      "evm evidence success phrase"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "\"deployable\": true").length > 1) "evm manifest deployable"
    expect ((manifest.splitOn "Counter.bin").length > 1) "evm manifest includes .bin"
    expect ((manifest.splitOn sourceHash).length > 1) "evm manifest sourceHash"
  -- NEAR: real wat2wasm .wasm + base wat preservation.
  do
    let selection ← liftResult "select near" (resolveBuildSelectionV1 TargetId.near none)
    let capability ← liftResult "resolve near"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat near" capability
    let baseFiles := MaterializedArtifactsV1.filesOf artifacts
    expect (baseFiles.map (·.path) == #["Counter.wat", "Counter.near-abi.json"])
      "near base paths"
    let outDir := FilePath.mk "build/v2/finalization-near"
    if ← outDir.pathExists then IO.FS.removeDirAll outDir
    let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
    expect (receipt.deployable == true) "near emit deployable"
    for f in baseFiles do
      let disk ← IO.FS.readFile (outDir / f.path)
      expect (disk == f.contents) s!"near base byte preservation {f.path}"
    let wasmPath := outDir / "Counter.wasm"
    expect (← wasmPath.pathExists) "near writes Counter.wasm"
    let wasm ← IO.FS.readBinFile wasmPath
    expect (wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
        wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
        wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00)
      "near wasm magic/version header"
    let evidence ← IO.FS.readFile (outDir / "evidence.json")
    expect ((evidence.splitOn "wat2wasm ").length > 1) "near evidence wat2wasm note"
    expect ((evidence.splitOn "runtime remains separate").length > 1)
      "near evidence runtime phrase"
    let manifest ← IO.FS.readFile (outDir / "manifest.json")
    expect ((manifest.splitOn "Counter.wasm").length > 1) "near manifest includes .wasm"

/-- Spawn product CLI with an isolated tool-root override (no process-global setEnv). -/
private def runProductCliWithToolRoot (toolRoot : String) (args : Array String) :
    IO IO.Process.Output :=
  IO.Process.output {
    cmd := "lake"
    args := #["env", ".lake/build/bin/proof-forge-next"] ++ args
    env := #[("PROOF_FORGE_TOOL_ROOT", toolRoot)]
    inheritEnv := true
  }

/-- Tool-failure zero publish (EVM missing tool root via CLI child process). -/
private unsafe def testToolFailureZeroPublish : IO Unit := do
  -- Ensure product CLI exists for this focused suite.
  let build ← IO.Process.output { cmd := "lake", args := #["build", "proof_forge_next"] }
  expect (build.exitCode == 0) s!"proof_forge_next build failed:\n{build.stderr}"
  let outDir := FilePath.mk "build/v2/finalization-tool-fail"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let result ← runProductCliWithToolRoot "/definitely/missing-s7b-tool-root" #[
    "build", "Examples/Counter.lean", "--module", "Examples.Counter",
    "--target", "evm", "-o", outDir.toString
  ]
  expect (result.exitCode != 0) "missing solc must fail closed"
  let combined := result.stdout ++ result.stderr
  expect (((combined.splitOn "PF-TOOLCHAIN-MISSING").length > 1) ||
      ((combined.splitOn "PF-TOOLCHAIN-MISMATCH").length > 1))
    s!"missing solc must surface toolchain diagnostic:\n{combined}"
  expect (!(← outDir.pathExists)) "tool failure must not publish output directory"

/-- NEAR missing/mismatch zero-output without weakening EVM. -/
private unsafe def testNearToolFailureZeroPublish : IO Unit := do
  let outDir := FilePath.mk "build/v2/finalization-near-tool-fail"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let result ← runProductCliWithToolRoot "/definitely/missing-s7b-near-tool-root" #[
    "build", "Examples/Counter.lean", "--module", "Examples.Counter",
    "--target", "near", "-o", outDir.toString
  ]
  expect (result.exitCode != 0) "missing wat2wasm must fail closed"
  let combined := result.stdout ++ result.stderr
  expect (((combined.splitOn "PF-TOOLCHAIN-MISSING").length > 1) ||
      ((combined.splitOn "PF-TOOLCHAIN-MISMATCH").length > 1))
    s!"missing wat2wasm must surface toolchain diagnostic:\n{combined}"
  expect (!(← outDir.pathExists)) "NEAR tool failure must not publish"
  -- EVM product path still works with normal tool root (no weakening).
  let compiled ← compileCounter
  let evmSel ← liftResult "select evm restore" (resolveBuildSelectionV1 TargetId.evm none)
  let evmCap ← liftResult "resolve evm restore"
    (Targets.resolveEngineeringRequirementsV1 evmSel compiled)
  let evmOut := FilePath.mk "build/v2/finalization-evm-after-near-fail"
  if ← evmOut.pathExists then IO.FS.removeDirAll evmOut
  let receipt ← ProofForgeV2.CLI.emitProgram evmCap evmOut
  expect (receipt.deployable == true) "EVM still deployable after NEAR tool-fail case"
  expect (← (evmOut / "Counter.bin").pathExists) "EVM still emits .bin"

/-- CLI authority deletion pins (source + Environment). -/
private unsafe def testCliAuthorityDeletion : IO Unit := do
  let rg (pat : String) (paths : Array String) : IO (UInt32 × String) := do
    let args := #["--glob", "*.lean", "-n", "--no-heading", pat] ++ paths
    let out ← IO.Process.output { cmd := "rg", args }
    pure (out.exitCode, out.stdout)
  -- Deleted CLI tool/finalize product surfaces.
  for pat in #[
      "finalizeEvm",
      "finalizeNear",
      "CLI\\.Toolchain",
      "import ProofForgeV2\\.CLI\\.Toolchain",
      "resolve \"solc\"",
      "resolve \"wat2wasm\""
    ] do
    let (ec, hits) ← rg pat #["ProofForgeV2/CLI"]
    expect (ec == 1) s!"CLI deletion: forbidden pattern still present for {pat}:\n{hits}"
  -- CLI/Toolchain.lean file must not exist.
  expect (!(← (FilePath.mk "ProofForgeV2/CLI/Toolchain.lean").pathExists))
    "CLI/Toolchain.lean must be deleted"
  -- Sole FinalizedArtifactsV1.mk near mint.
  let (ecMk, hitsMk) ← rg "FinalizedArtifactsV1\\.mk" #["ProofForgeV2"]
  expect (ecMk == 0) s!"sole mint: expected FinalizedArtifactsV1.mk hits:\n{hitsMk}"
  let lines := (hitsMk.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (lines.length == 1)
    s!"sole mint: expected exactly one FinalizedArtifactsV1.mk, got {lines.length}:\n{hitsMk}"
  expect ((hitsMk.splitOn "EngineeringFinalizationV1.lean").length > 1)
    "sole mint must live in EngineeringFinalizationV1.lean"
  -- Sole finalizeMaterializedArtifactsV1 in Registry.
  let (ecFin, hitsFin) ← rg "^\\s*def finalizeMaterializedArtifactsV1\\b" #["ProofForgeV2"]
  expect (ecFin == 0) s!"finalizeMaterializedArtifactsV1 must exist:\n{hitsFin}"
  let finLines := (hitsFin.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (finLines.length == 1)
    s!"sole finalizeMaterializedArtifactsV1, got {finLines.length}:\n{hitsFin}"
  expect ((hitsFin.splitOn "Registry.lean").length > 1)
    "finalizeMaterializedArtifactsV1 must live in Registry.lean"
  -- LockedToolchainV1 present; no Core.Source import.
  let (ecSrc, hitsSrc) ← rg
    "^\\s*import ProofForgeV2\\.Core\\.Source\\b"
    #["ProofForgeV2/Materialization/LockedToolchainV1.lean"]
  expect (ecSrc == 1)
    s!"LockedToolchainV1 must not import Core.Source:\n{hitsSrc}"

private def assertFinalizationEnv (env : Environment) : Except String Unit := do
  let carrier := Name.mkStr2 "ProofForgeV2" "FinalizedArtifactsV1"
  unless env.contains carrier do
    throw "FinalizedArtifactsV1 missing from Environment"
  let mint := Name.mkStr2 "ProofForgeV2" "mintFinalizedArtifactsV1"
  unless env.contains mint do
    throw "mintFinalizedArtifactsV1 missing from Environment"
  -- Module namespace may not appear as a declaration; check resolve symbol.
  let resolveName := Name.mkStr4 "ProofForgeV2" "Materialization" "LockedToolchainV1" "resolve"
  unless env.contains resolveName do
    throw "LockedToolchainV1.resolve missing from Environment"
  -- Deleted CLI tool-runner symbols must be absent.
  let oldEnvTest := Name.mkStr4 "ProofForgeV2" "CLI" "Toolchain" "resolve"
  if env.contains oldEnvTest then
    throw s!"deleted CLI tool-runner resolve still present: {oldEnvTest}"
  pure ()

run_cmd do
  let env ← getEnv
  match assertFinalizationEnv env with
  | .ok () => pure ()
  | .error e => throwError e

unsafe def run : IO Unit := do
  testSoleMintBinding
  testPreIoBindBeforeTools
  testNonDeployablePhases
  testFourTargetFinalization
  testToolFailureZeroPublish
  testNearToolFailureZeroPublish
  testCliAuthorityDeletion
  IO.println "Tests.Materialization.EngineeringFinalizationV1: ok"

end Tests.Materialization.EngineeringFinalizationV1
