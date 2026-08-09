/-
  ALEO-I4 opt-in compiled-profile product finalization tests.

  The default `aleo-leo-4.0.2-u64-v1` profile remains zero-tool. When locked
  Leo 4.0.2 is present, the explicit `aleo-leo-4.0.2-u64-compile-v1` profile
  drives the real publisher/finalizer and freezes exactly two materialized base
  files plus three finalized compile outputs. Full output-dir inspection and
  same-host repeat bytes are checked through production APIs.

  Missing or mismatched locked tools fail with zero published destination.
  Compile acceptance is not execution/proof/deploy/query evidence and remains
  `deployable=false`. Not formal/hermetic/release qualification.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Examples.StateCell
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.ArtifactContentV1
import ProofForgeV2.Materialization.LockedToolchainV1
import Tests.Language.ParserSession

namespace Tests.Materialization.AleoCompiledFinalizationV1

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

private unsafe def compileStateCell : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load StateCell" (← session.selectProgramV1
    Examples.stateCellSourceText "<aleo-compiled-finalization-stateCell>"
    Examples.stateCellModuleNameV1 none)
  liftResult "compile StateCell" (Compiler.compileValidatedSourceV1 source)

private def capabilityFor
    (compiled : CompiledSemanticV1) (profile? : Option CodegenProfileId) :
    IO Targets.ResolvedEngineeringBuildV1 := do
  let selection ← liftResult "select Aleo" <|
    resolveBuildSelectionV1 TargetId.aleo profile?
  liftResult "resolve Aleo" <|
    Targets.resolveEngineeringRequirementsV1 selection compiled

private def lockedLeoCandidate : IO FilePath := do
  match ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" with
  | some root =>
      let path := FilePath.mk root
      unless path.isAbsolute do
        throw <| IO.userError
          "PF-TOOLCHAIN-MISMATCH: PROOF_FORGE_TOOL_ROOT must be absolute"
      pure (path / "leo")
  | none =>
      let homeValue? ← IO.getEnv "HOME"
      let home ← match homeValue? with
        | some value => pure (FilePath.mk value)
        | none =>
            throw <| IO.userError
              "PF-TOOLCHAIN-MISSING: HOME is required for the default tool cache"
      let platform ← match ProofForgeV2.Core.ToolLockV4.activeToolLockPlatformV4 with
        | .ok value => pure value
        | .error message => throw <| IO.userError message
      pure <| home / ".cache" / "proof-forge-v2" / "tool-root" /
        ProofForgeV2.Core.ToolLockV4.ToolLockPlatformV4.wire platform / "leo"

private def resolveLockedLeo? : IO (Option VerifiedTool) := do
  let candidate ← lockedLeoCandidate
  if ← candidate.pathExists then
    -- Candidate presence makes every resolver/version/hash/closure failure hard.
    pure (some (← resolve "leo"))
  else
    pure none

private def readBytes (root : FilePath) (path : String) : IO ByteArray :=
  IO.FS.readBinFile (root / path)

private def expectRegularNonempty (root : FilePath) (path : String) : IO Unit := do
  let full := root / path
  expect (← full.pathExists) s!"missing output {path}"
  let metadata ← full.symlinkMetadata
  expect (metadata.type == .file) s!"output is not regular: {path}"
  expect (!(← IO.FS.readBinFile full).isEmpty) s!"output is empty: {path}"

private def expectRole
    (manifest : ProofForgeV2.CLI.InspectedOutputManifestV1)
    (path : String) (role : ArtifactContentRoleV1) : IO Unit := do
  let some descriptor := manifest.files.find? (·.path == path) |
    throw <| IO.userError s!"manifest missing {path}"
  expect (descriptor.role == role) s!"manifest role mismatch for {path}"
  expect (descriptor.size > 0) s!"manifest size must be nonzero for {path}"

/-- Default source profile bases (ALEO-IR-6: Instructions + query; no Leo). -/
private def sourceBasePaths : Array String :=
  #["statecell.aleo", "statecell.aleo-query-contract.json"]

/-- Compile profile dual-writes Leo for locked-leo compare finalize. -/
private def compileBasePaths : Array String :=
  #["statecell.aleo", "statecell.aleo-query-contract.json", "statecell.leo"]

private def compiledExtraPaths : Array String :=
  #["statecell.compiled.aleo", "statecell.abi.json", "statecell.leo-program.json"]

private def publishedPaths : Array String :=
  compileBasePaths ++ compiledExtraPaths ++ #["evidence.json", "manifest.json"]

/-- Default profile is unchanged: no locked tool and no compiled extras. -/
private unsafe def testDefaultSourceProfile : IO Unit := do
  let compiled ← compileStateCell
  let capability ← capabilityFor compiled none
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf capability ==
      CodegenProfileId.aleoLeoU64V1)
    "default Aleo capability must remain the source profile"
  let outDir := FilePath.mk "build/v2/aleo-source-finalization"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
  expect (!receipt.deployable) "default Aleo source profile remains non-deployable"
  expect (receipt.codegenProfile == CodegenProfileId.aleoLeoU64V1)
    "default receipt profile"
  let manifest ← ProofForgeV2.CLI.inspectEngineeringOutputDirV1 outDir
  expect (manifest.codegenProfile == CodegenProfileId.aleoLeoU64V1.toString)
    "default inspected profile"
  expect (!manifest.deployable) "default inspected deployable=false"
  expect (manifest.files.size == 2) "default profile has exactly two base artifacts"
  for path in sourceBasePaths do
    expectRole manifest path .materializedBase
  -- ALEO-IR-6: primary .aleo is Instructions text, not Leo brace source.
  let primary ← IO.FS.readFile (outDir / "statecell.aleo")
  expect (primary.contains "program statecell.aleo;")
    "default primary must be Aleo Instructions"
  expect (!primary.contains "program statecell.aleo {")
    "default primary must not be Leo brace source"
  expect (!(← (outDir / "statecell.leo").pathExists))
    "default profile must not dual-write statecell.leo without debug env"
  for path in compiledExtraPaths do
    expect (!(← (outDir / path).pathExists)) s!"default profile must not emit {path}"

/-- Real locked Leo product finalize, exact outputs, inspection, and repeat. -/
private unsafe def testCompiledProfile (leo : VerifiedTool) : IO Unit := do
  let compiled ← compileStateCell
  let capability ← capabilityFor compiled (some CodegenProfileId.aleoLeoU64CompileV1)
  expect (Targets.ResolvedEngineeringBuildV1.codegenProfileOf capability ==
      CodegenProfileId.aleoLeoU64CompileV1)
    "compiled capability profile"
  let first := FilePath.mk "build/v2/aleo-compiled-finalization-1"
  let second := FilePath.mk "build/v2/aleo-compiled-finalization-2"
  if ← first.pathExists then IO.FS.removeDirAll first
  if ← second.pathExists then IO.FS.removeDirAll second
  let firstReceipt ← ProofForgeV2.CLI.emitProgram capability first
  let secondReceipt ← ProofForgeV2.CLI.emitProgram capability second
  for receipt in #[firstReceipt, secondReceipt] do
    expect (receipt.target == TargetId.aleo) "compiled receipt target"
    expect (receipt.codegenProfile == CodegenProfileId.aleoLeoU64CompileV1)
      "compiled receipt profile"
    expect (!receipt.deployable) "Leo compile-only output is never deployable"

  let firstManifest ← ProofForgeV2.CLI.inspectEngineeringOutputDirV1 first
  let secondManifest ← ProofForgeV2.CLI.inspectEngineeringOutputDirV1 second
  for manifest in #[firstManifest, secondManifest] do
    expect (manifest.target == TargetId.aleo.toString) "compiled inspected target"
    expect (manifest.codegenProfile == CodegenProfileId.aleoLeoU64CompileV1.toString)
      "compiled inspected profile"
    expect (!manifest.deployable) "compiled inspected deployable=false"
    expect (manifest.files.size == 6)
      s!"compiled profile must have exactly six artifacts (3 base + 3 extra), got {manifest.files.size}"
    for path in compileBasePaths do
      expectRole manifest path .materializedBase
    for path in compiledExtraPaths do
      expectRole manifest path .finalizedExtra

  for path in compileBasePaths ++ compiledExtraPaths do
    expectRegularNonempty first path
    expectRegularNonempty second path
  let primary ← IO.FS.readFile (first / "statecell.aleo")
  expect (primary.contains "program statecell.aleo;")
    "compile primary must be Aleo Instructions"
  expect (!primary.contains "program statecell.aleo {")
    "compile primary must not be Leo brace source"
  let leoSrc ← IO.FS.readFile (first / "statecell.leo")
  expect (leoSrc.contains "program statecell.aleo {")
    "compile dual-write must be Leo 4 source for leo-build compare"
  let evidence ← IO.FS.readFile (first / "evidence.json")
  expect (evidence.contains CodegenProfileId.aleoLeoU64CompileV1.toString)
    "compiled evidence profile"
  expect (evidence.contains s!"locked Leo {leo.version}")
    "compiled evidence locked Leo version"
  expect (evidence.contains s!"sha256={leo.executableSha256}")
    "compiled evidence locked Leo executable hash"
  expect (evidence.contains "offline compile-only finalization")
    "compiled evidence compile-only wording"
  expect (evidence.contains "compare path" || evidence.contains "dual-written")
    "compiled evidence must note leo-build is compare / dual-write path"
  expect (evidence.contains "no execution, proof, deployment, or network query")
    "compiled evidence denies stronger runtime/proof claims"

  -- Same-host repeat: all artifacts and sidecars are exact-byte identical.
  for path in publishedPaths do
    let left ← readBytes first path
    let right ← readBytes second path
    expect (left == right) s!"compiled repeat differs at {path}"
  expect (firstManifest.outputSetDigest == secondManifest.outputSetDigest)
    "compiled repeat outputSetDigest"
  IO.println s!"  locked Leo compile profile ok ({leo.version}; 6 artifacts; repeat exact)"

private def runProductCliWithToolRoot
    (toolRoot : String) (outDir : FilePath) : IO IO.Process.Output :=
  IO.Process.output {
    cmd := "lake"
    args := #[
      "env", ".lake/build/bin/proof-forge-next",
      "build", "Examples/StateCell.lean",
      "--module", "Examples.StateCell",
      "--target", "aleo",
      "--profile", CodegenProfileId.aleoLeoU64CompileV1.toString,
      "-o", outDir.toString
    ]
    env := #[("PROOF_FORGE_TOOL_ROOT", toolRoot)]
    inheritEnv := true
  }

private def expectNoStagingSibling (outDir : FilePath) : IO Unit := do
  let parent := outDir.parent.getD "."
  let leaf := outDir.fileName.getD ""
  let entries ← parent.readDir
  let leftovers := entries.filter fun ent =>
    ent.fileName.startsWith s!".{leaf}.staging-"
  expect leftovers.isEmpty s!"tool failure left staging for {leaf}"

/-- Missing and hash-mismatched locked Leo both fail without publication. -/
private unsafe def testToolFailuresZeroPublish : IO Unit := do
  let build ← IO.Process.output {
    cmd := "lake"
    args := #["build", "proof_forge_next"]
  }
  expect (build.exitCode == 0) s!"proof_forge_next build failed:\n{build.stderr}"

  let missingOut := FilePath.mk "build/v2/aleo-compiled-missing-tool"
  if ← missingOut.pathExists then IO.FS.removeDirAll missingOut
  let missing ← runProductCliWithToolRoot
    "/definitely/missing-aleo-compiled-tool-root" missingOut
  expect (missing.exitCode != 0) "missing locked Leo must fail product build"
  expect ((missing.stderr ++ missing.stdout).contains "PF-TOOLCHAIN-MISSING")
    s!"missing Leo diagnostic:\n{missing.stderr}{missing.stdout}"
  expect (!(← missingOut.pathExists)) "missing Leo must not publish destination"
  expectNoStagingSibling missingOut

  let badRootInput := FilePath.mk "build/v2/aleo-compiled-bad-tool-root"
  if ← badRootInput.pathExists then IO.FS.removeDirAll badRootInput
  IO.FS.createDirAll badRootInput
  IO.FS.writeFile (badRootInput / "leo") "not-the-locked-leo\n"
  let chmod ← IO.Process.output {
    cmd := "/bin/chmod"
    args := #["700", (badRootInput / "leo").toString]
  }
  expect (chmod.exitCode == 0) s!"chmod fake Leo failed: {chmod.stderr}"
  let badRoot ← IO.FS.realPath badRootInput
  let badOut := FilePath.mk "build/v2/aleo-compiled-bad-tool"
  if ← badOut.pathExists then IO.FS.removeDirAll badOut
  let bad ← runProductCliWithToolRoot badRoot.toString badOut
  expect (bad.exitCode != 0) "mismatched locked Leo must fail product build"
  expect ((bad.stderr ++ bad.stdout).contains "PF-TOOLCHAIN-MISMATCH")
    s!"mismatched Leo diagnostic:\n{bad.stderr}{bad.stdout}"
  expect (!(← badOut.pathExists)) "mismatched Leo must not publish destination"
  expectNoStagingSibling badOut

unsafe def run : IO Unit := do
  IO.println "Tests.Materialization.AleoCompiledFinalizationV1: start"
  testDefaultSourceProfile
  match ← resolveLockedLeo? with
  | none =>
      IO.println "  skipped positive compiled-profile run: locked Leo unavailable"
  | some leo =>
      testCompiledProfile leo
  testToolFailuresZeroPublish
  IO.println "Tests.Materialization.AleoCompiledFinalizationV1: ok"

end Tests.Materialization.AleoCompiledFinalizationV1
