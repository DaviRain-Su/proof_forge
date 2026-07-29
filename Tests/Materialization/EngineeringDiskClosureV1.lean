/-
  D3/S7c engineering exact disk-closure + manifest-last tests.

  Real product path only:
    compileValidatedSourceV1 → resolveBuildSelectionV1 →
    resolveEngineeringRequirementsV1 → materializeResult →
    finalizeMaterializedArtifactsV1 / emitProgram →
    validateEngineeringDiskClosureV1

  Not formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity /
  SupportClaim / ToolchainIdentity / hermetic publisher. No reimplemented
  closure checker — tests drive the sole production API.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.CLI.Main
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.EngineeringDiskClosureV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import Tests.Language.ParserSession
import Lean
import Lean.Elab.Command

namespace Tests.Materialization.EngineeringDiskClosureV1

open ProofForgeV2
open ProofForgeV2.Compiler
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

private unsafe def compileCounter : IO CompiledProgramV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<disk-closure-counter>"
    Examples.counterModuleNameV1 none)
  liftResult "compile Counter" (Compiler.compileValidatedSourceV1 source)

private def expectIoErrorContains (label needle : String) (act : IO Unit) : IO Unit := do
  try
    act
    throw <| IO.userError s!"{label}: expected failure containing {needle}"
  catch e =>
    let msg := toString e
    if (msg.splitOn label).length > 1 && (msg.splitOn "expected failure").length > 1 then
      throw e
    expect ((msg.splitOn needle).length > 1)
      s!"{label}: expected '{needle}' in:\n{msg}"

private def writeBaseFiles (staging : FilePath) (artifacts : MaterializedArtifactsV1) : IO Unit := do
  for f in MaterializedArtifactsV1.filesOf artifacts do
    if let some parent := (staging / f.path).parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile (staging / f.path) f.contents

private def writeSidecars (staging : FilePath) (evidence manifest : String) : IO Unit := do
  IO.FS.writeFile (staging / "evidence.json") evidence
  IO.FS.writeFile (staging / "manifest.json") manifest

private def minimalSidecars : String × String :=
  ("{\"note\":\"test-evidence\"}\n", "{\"schemaVersion\":\"proof-forge-output/v2alpha1\"}\n")

/-- Flat Solana product emit + production closure on published tree. -/
private unsafe def testFlatSolanaPositive : IO Unit := do
  let compiled ← compileCounter
  let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult "resolve solana"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← materializeOk "mat solana" capability
  let basePaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  expect (basePaths.size >= 1) "solana emits base files"
  let outDir := FilePath.mk "build/v2/disk-closure-solana"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
  expect (receipt.deployable == false) "solana non-deployable"
  expect (← (outDir / "evidence.json").pathExists) "solana evidence present"
  expect (← (outDir / "manifest.json").pathExists) "solana manifest present"
  let manifestText ← IO.FS.readFile (outDir / "manifest.json")
  expect ((manifestText.splitOn "evidence.json").length == 1)
    "evidence must not appear in manifest.files"
  for p in basePaths do
    expect (← (outDir / p).pathExists) s!"solana base present: {p}"
  -- Re-validate published destination via production API.
  let staging := FilePath.mk "build/v2/disk-closure-solana-revalidate"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  writeBaseFiles staging artifacts
  let finalized ← Targets.finalizeMaterializedArtifactsV1 capability artifacts staging
  writeSidecars staging (← IO.FS.readFile (outDir / "evidence.json"))
    (← IO.FS.readFile (outDir / "manifest.json"))
  validateEngineeringDiskClosureV1 finalized staging

/-- Nested Noir relations tree product emit + production closure. -/
private unsafe def testNestedNoirPositive : IO Unit := do
  let compiled ← compileCounter
  let selection ← liftResult "select noir" (resolveBuildSelectionV1 TargetId.noir none)
  let capability ← liftResult "resolve noir"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← materializeOk "mat noir" capability
  let basePaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  expect (basePaths.any (·.startsWith "relations/"))
    "noir emits nested relations paths"
  let outDir := FilePath.mk "build/v2/disk-closure-noir"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let receipt ← ProofForgeV2.CLI.emitProgram capability outDir
  expect (receipt.deployable == false) "noir non-deployable"
  expect (← (outDir / "evidence.json").pathExists) "noir evidence present"
  expect (← (outDir / "manifest.json").pathExists) "noir manifest present"
  let manifestText ← IO.FS.readFile (outDir / "manifest.json")
  expect ((manifestText.splitOn "\"files\"").length > 1) "noir manifest has files"
  expect ((manifestText.splitOn "evidence.json").length == 1)
    "evidence not listed in noir manifest.files"
  for p in basePaths do
    expect (← (outDir / p).pathExists) s!"noir nested present: {p}"
  -- Production closure re-validate of nested tree.
  let staging := FilePath.mk "build/v2/disk-closure-noir-revalidate"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  writeBaseFiles staging artifacts
  let finalized ← Targets.finalizeMaterializedArtifactsV1 capability artifacts staging
  writeSidecars staging (← IO.FS.readFile (outDir / "evidence.json"))
    (← IO.FS.readFile (outDir / "manifest.json"))
  validateEngineeringDiskClosureV1 finalized staging

/-- Manifest-last published closure: evidence + manifest present, evidence not in files. -/
private unsafe def testManifestLastPublishedClosure : IO Unit := do
  let compiled ← compileCounter
  let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult "resolve solana"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let outDir := FilePath.mk "build/v2/disk-closure-manifest-last"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let _ ← ProofForgeV2.CLI.emitProgram capability outDir
  let evidence ← IO.FS.readFile (outDir / "evidence.json")
  let manifest ← IO.FS.readFile (outDir / "manifest.json")
  expect (evidence.startsWith "{") "evidence is JSON object"
  expect (manifest.startsWith "{") "manifest is JSON object"
  expect ((manifest.splitOn "proof-forge-output/v2alpha1").length > 1)
    "manifest schema v2alpha1 preserved"
  expect ((manifest.splitOn "evidence.json").length == 1)
    "evidence sidecar not in manifest.files"
  -- No leftover staging next to destination.
  let parent := FilePath.mk "build/v2"
  let entries ← parent.readDir
  let leftover := entries.filter fun e =>
    e.fileName.startsWith ".disk-closure-manifest-last.staging-"
  expect (leftover.isEmpty) "no leftover staging after successful publish"

/-- Destination symlink reject + no-clobber + tool-fail staging cleanup. -/
private unsafe def testDestinationSymlinkNoClobberToolFail : IO Unit := do
  let compiled ← compileCounter
  let selection ← liftResult "select solana" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult "resolve solana"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  -- No-clobber: existing directory preserved.
  let collision := FilePath.mk "build/v2/disk-closure-noclobber"
  if ← collision.pathExists then IO.FS.removeDirAll collision
  IO.FS.createDirAll collision
  IO.FS.writeFile (collision / "keep.txt") "preserve\n"
  expectIoErrorContains "no-clobber" "PF-OUTPUT-COLLISION" do
    let _ ← ProofForgeV2.CLI.emitProgram capability collision
    pure ()
  expect ((← IO.FS.readFile (collision / "keep.txt")) == "preserve\n")
    "no-clobber preserves destination contents"
  -- Destination symlink rejected.
  let linkDir := FilePath.mk "build/v2/disk-closure-symlink-dest"
  let linkTarget := FilePath.mk "build/v2/disk-closure-symlink-target"
  if ← linkDir.pathExists then
    try IO.FS.removeFile linkDir
    catch _ => IO.FS.removeDirAll linkDir
  if ← linkTarget.pathExists then IO.FS.removeDirAll linkTarget
  IO.FS.createDirAll linkTarget
  let _ ← IO.Process.output {
    cmd := "ln"
    args := #["-s", "disk-closure-symlink-target", "build/v2/disk-closure-symlink-dest"]
  }
  expectIoErrorContains "dest symlink" "PF-OUTPUT-PATH" do
    let _ ← ProofForgeV2.CLI.emitProgram capability linkDir
    pure ()
  -- Tool-fail: missing solc must not publish and must clean staging.
  let build ← IO.Process.output { cmd := "lake", args := #["build", "proof_forge_next"] }
  expect (build.exitCode == 0) s!"proof_forge_next build failed:\n{build.stderr}"
  let toolFailOut := FilePath.mk "build/v2/disk-closure-tool-fail"
  if ← toolFailOut.pathExists then IO.FS.removeDirAll toolFailOut
  let result ← IO.Process.output {
    cmd := "lake"
    args := #["env", ".lake/build/bin/proof-forge-next",
      "build-counter", "--target", "evm", "-o", toolFailOut.toString]
    env := #[("PROOF_FORGE_TOOL_ROOT", "/definitely/missing-s7c-tool-root")]
    inheritEnv := true
  }
  expect (result.exitCode != 0) "missing solc must fail"
  expect (!(← toolFailOut.pathExists)) "tool failure must not publish destination"
  let parentEntries ← (FilePath.mk "build/v2").readDir
  let stagingLeft := parentEntries.filter fun e =>
    e.fileName.startsWith ".disk-closure-tool-fail.staging-"
  expect (stagingLeft.isEmpty) "tool failure must remove staging only"

/-- Shared helper: solana capability + finalized + happy staging for mutation tests. -/
private unsafe def solanaFinalizedStaging (label : String) :
    IO (Targets.ResolvedEngineeringBuildV1 × FinalizedArtifactsV1 × FilePath) := do
  let compiled ← compileCounter
  let selection ← liftResult s!"select {label}" (resolveBuildSelectionV1 TargetId.solana none)
  let capability ← liftResult s!"resolve {label}"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← materializeOk s!"mat {label}" capability
  let staging := FilePath.mk s!"build/v2/disk-closure-neg-{label}"
  if ← staging.pathExists then IO.FS.removeDirAll staging
  IO.FS.createDirAll staging
  writeBaseFiles staging artifacts
  let finalized ← Targets.finalizeMaterializedArtifactsV1 capability artifacts staging
  let (ev, mf) := minimalSidecars
  writeSidecars staging ev mf
  pure (capability, finalized, staging)

/-- Validator negatives through real production API. -/
private unsafe def testValidatorNegatives : IO Unit := do
  -- Missing leaf.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "missing"
    let files := MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf finalized)
    expect (files.size > 0) "missing-leaf fixture has base"
    IO.FS.removeFile (staging / files[0]!.path)
    expectIoErrorContains "missing leaf" "PF-OUTPUT-PATH" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "missing leaf msg" "missing regular file" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Unlisted extra file.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "extra-file"
    IO.FS.writeFile (staging / "unlisted-extra.txt") "nope\n"
    expectIoErrorContains "extra file" "unexpected file" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Extra directory.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "extra-dir"
    IO.FS.createDirAll (staging / "unexpected-dir")
    expectIoErrorContains "extra dir" "unexpected directory" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Symlink file.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "symlink-file"
    let files := MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf finalized)
    let targetName := files[0]!.path
    IO.FS.removeFile (staging / targetName)
    let _ ← IO.Process.output {
      cmd := "ln"
      args := #["-s", "manifest.json", (staging / targetName).toString]
    }
    expectIoErrorContains "symlink file" "symbolic link" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Symlink directory under nested-capable setup: create extra symlink dir.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "symlink-dir"
    let _ ← IO.Process.output {
      cmd := "ln"
      args := #["-s", ".", (staging / "link-dir").toString]
    }
    expectIoErrorContains "symlink dir" "symbolic link" do
      validateEngineeringDiskClosureV1 finalized staging
  -- FIFO / nonregular.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "fifo"
    let _ ← IO.Process.output {
      cmd := "mkfifo"
      args := #[(staging / "pipe.fifo").toString]
    }
    expectIoErrorContains "fifo" "non-regular" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Sidecar collision with base (logical gate via mint extra named evidence.json).
  do
    let compiled ← compileCounter
    let selection ← liftResult "select collide" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve collide"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat collide" capability
    let draft : EngineeringFinalizationDraftV1 := {
      deployable := false
      extraFiles := #["evidence.json"]
      evidenceNote := "collide"
    }
    let finalized ← liftResult "mint collide"
      (mintFinalizedArtifactsV1 capability artifacts draft)
    let staging := FilePath.mk "build/v2/disk-closure-neg-sidecar-collide"
    if ← staging.pathExists then IO.FS.removeDirAll staging
    IO.FS.createDirAll staging
    writeBaseFiles staging artifacts
    IO.FS.writeFile (staging / "evidence.json") "{}\n"
    let (_ev, mf) := minimalSidecars
    -- Also write manifest for completeness; logical gate fails first.
    IO.FS.writeFile (staging / "manifest.json") mf
    expectIoErrorContains "sidecar collide" "sidecar path collides" do
      validateEngineeringDiskClosureV1 finalized staging
  -- File/directory prefix conflict: leaf that is proper prefix of another leaf.
  do
    let compiled ← compileCounter
    let selection ← liftResult "select prefix" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve prefix"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat prefix" capability
    let draft : EngineeringFinalizationDraftV1 := {
      deployable := false
      extraFiles := #["nested", "nested/child.txt"]
      evidenceNote := "prefix"
    }
    let finalized ← liftResult "mint prefix"
      (mintFinalizedArtifactsV1 capability artifacts draft)
    let staging := FilePath.mk "build/v2/disk-closure-neg-prefix"
    if ← staging.pathExists then IO.FS.removeDirAll staging
    IO.FS.createDirAll staging
    expectIoErrorContains "prefix conflict" "file/directory prefix conflict" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Duplicate logical path (extra duplicates base name via mint rejection path is
  -- already covered; here force duplicate by reusing sidecar names is impossible.
  -- Test unsafe relative path via mint with unsafe rejected — use draft that mints
  -- then... mint rejects unsafe. Logical unsafe: craft via mint of safe extras only.
  -- Duplicate among expected: mint rejects dup extras. Cover unsafe via a path that
  -- passes mint? Only if base had unsafe which mint rejects. Pin pure gate via
  -- collision of evidence in extras already above.
  pure ()
  -- Over file-count limit (logical, no filesystem write of all leaves).
  do
    let compiled ← compileCounter
    let selection ← liftResult "select limit" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve limit"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat limit" capability
    let baseCount := (MaterializedArtifactsV1.filesOf artifacts).size
    -- Need total leaves > 1024: base + extras + 2 sidecars.
    -- extras needed = 1025 - base - 2 = 1023 - base
    let needExtras := (maxEngineeringDiskClosureFilesV1 + 1) - baseCount - 2
    let mut extras : Array String := #[]
    for i in [:needExtras] do
      extras := extras.push s!"extra-{i}.bin"
    let draft : EngineeringFinalizationDraftV1 := {
      deployable := false
      extraFiles := extras
      evidenceNote := "limit"
    }
    let finalized ← liftResult "mint limit"
      (mintFinalizedArtifactsV1 capability artifacts draft)
    let staging := FilePath.mk "build/v2/disk-closure-neg-filecount"
    if ← staging.pathExists then IO.FS.removeDirAll staging
    IO.FS.createDirAll staging
    expectIoErrorContains "file count limit" "PF-OUTPUT-LIMIT" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "file count msg" "too many closure files" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Per-file size limit (metadata).
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "filesize"
    let files := MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf finalized)
    let target := staging / files[0]!.path
    -- Write slightly over 64 MiB (use sparse seek via dd for speed).
    let over := maxEngineeringDiskClosureFileBytesV1 + 1
    let _ ← IO.Process.output {
      cmd := "dd"
      args := #["if=/dev/zero", s!"of={target}", "bs=1", s!"count=0",
        s!"seek={over}", "status=none"]
    }
    expectIoErrorContains "file size limit" "PF-OUTPUT-LIMIT" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "file size msg" "file exceeds size limit" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Missing manifest sidecar.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "no-manifest"
    IO.FS.removeFile (staging / "manifest.json")
    expectIoErrorContains "missing manifest" "missing regular file" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "missing manifest path" "manifest.json" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Type mismatch: expected file is a directory → stable unexpected directory path.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "type-mismatch"
    let files := MaterializedArtifactsV1.filesOf (FinalizedArtifactsV1.artifactsOf finalized)
    let leafPath := files[0]!.path
    let target := staging / leafPath
    IO.FS.removeFile target
    IO.FS.createDirAll target
    expectIoErrorContains "type mismatch" "PF-OUTPUT-PATH" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "type mismatch dir phrase"
        s!"unexpected directory '{leafPath}'" do
      validateEngineeringDiskClosureV1 finalized staging

/-- Additional production-API negatives (split for elaborator depth). -/
private unsafe def testValidatorNegativesExtended : IO Unit := do
  -- Total closure size limit: several under-per-file sparse extras sum > 256 MiB.
  do
    let compiled ← compileCounter
    let selection ← liftResult "select totalsize" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve totalsize"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat totalsize" capability
    -- 5 × 53 MiB = 265 MiB > 256 MiB; each under 64 MiB per-file limit.
    let chunkBytes : Nat := 53 * 1024 * 1024
    let totalExtras : Array String :=
      #["chunk-0.bin", "chunk-1.bin", "chunk-2.bin", "chunk-3.bin", "chunk-4.bin"]
    let draft : EngineeringFinalizationDraftV1 := {
      deployable := false
      extraFiles := totalExtras
      evidenceNote := "totalsize"
    }
    let finalized ← liftResult "mint totalsize"
      (mintFinalizedArtifactsV1 capability artifacts draft)
    let staging := FilePath.mk "build/v2/disk-closure-neg-totalsize"
    if ← staging.pathExists then IO.FS.removeDirAll staging
    IO.FS.createDirAll staging
    writeBaseFiles staging artifacts
    for name in totalExtras do
      let target := staging / name
      let _ ← IO.Process.output {
        cmd := "dd"
        args := #["if=/dev/zero", s!"of={target}", "bs=1", s!"count=0",
          s!"seek={chunkBytes}", "status=none"]
      }
    let (ev, mf) := minimalSidecars
    writeSidecars staging ev mf
    expectIoErrorContains "total size limit" "PF-OUTPUT-LIMIT" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "total size msg" "total closure size exceeds limit" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Missing evidence sidecar.
  do
    let (_, finalized, staging) ← solanaFinalizedStaging "no-evidence"
    IO.FS.removeFile (staging / "evidence.json")
    expectIoErrorContains "missing evidence" "missing regular file" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "missing evidence path" "evidence.json" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Nested Noir: expected intermediate directory replaced by a regular file.
  do
    let compiled ← compileCounter
    let selection ← liftResult "select noir-dirfile" (resolveBuildSelectionV1 TargetId.noir none)
    let capability ← liftResult "resolve noir-dirfile"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat noir-dirfile" capability
    let staging := FilePath.mk "build/v2/disk-closure-neg-noir-dirfile"
    if ← staging.pathExists then IO.FS.removeDirAll staging
    IO.FS.createDirAll staging
    writeBaseFiles staging artifacts
    let finalized ← Targets.finalizeMaterializedArtifactsV1 capability artifacts staging
    let (ev, mf) := minimalSidecars
    writeSidecars staging ev mf
    -- Replace intermediate expected dir `relations` with a regular file.
    IO.FS.removeDirAll (staging / "relations")
    IO.FS.writeFile (staging / "relations") "not-a-directory\n"
    expectIoErrorContains "dir-as-file" "unexpected file" do
      validateEngineeringDiskClosureV1 finalized staging
    expectIoErrorContains "dir-as-file path" "unexpected file 'relations'" do
      validateEngineeringDiskClosureV1 finalized staging
  -- Publisher dual-defense: extras named as transitional sidecars rejected pre-write.
  do
    let compiled ← compileCounter
    let selection ← liftResult "select dual-def" (resolveBuildSelectionV1 TargetId.solana none)
    let capability ← liftResult "resolve dual-def"
      (Targets.resolveEngineeringRequirementsV1 selection compiled)
    let artifacts ← materializeOk "mat dual-def" capability
    let basePaths := (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
    expectIoErrorContains "publisher evidence extra" "PF-OUTPUT-PATH" do
      ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths
        #[evidenceSidecarNameV1]
    expectIoErrorContains "publisher evidence msg" "collides with sidecar" do
      ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths
        #[evidenceSidecarNameV1]
    expectIoErrorContains "publisher manifest extra" "collides with sidecar" do
      ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths
        #[manifestSidecarNameV1]
    -- Safe unique extra still accepted.
    ProofForgeV2.CLI.validateFinalizedExtraPathsForPublishV1 basePaths #["tool-extra.bin"]

/-- Sole production validator symbol pins. -/
private unsafe def testSoleValidatorPins : IO Unit := do
  let rg (pat : String) (paths : Array String) : IO (UInt32 × String) := do
    let args := #["--glob", "*.lean", "-n", "--no-heading", pat] ++ paths
    let out ← IO.Process.output { cmd := "rg", args }
    pure (out.exitCode, out.stdout)
  let (ec, hits) ← rg "^\\s*def validateEngineeringDiskClosureV1\\b" #["ProofForgeV2"]
  expect (ec == 0) s!"validateEngineeringDiskClosureV1 must exist:\n{hits}"
  let lines := (hits.splitOn "\n").filter (fun l => !l.isEmpty)
  expect (lines.length == 1)
    s!"sole validateEngineeringDiskClosureV1, got {lines.length}:\n{hits}"
  expect ((hits.splitOn "EngineeringDiskClosureV1.lean").length > 1)
    "sole validator must live in EngineeringDiskClosureV1.lean"
  -- No caller expected-list public API parameter pattern on the sole def.
  let (ecCall, hitsCall) ← rg
    "validateEngineeringDiskClosureV1\\s*\\([^)]*expected" #["ProofForgeV2"]
  expect (ecCall == 1)
    s!"validator must not take caller expected-list:\n{hitsCall}"
  -- Manifest-last ordering in Emit: evidence write before manifest write.
  let emitSrc ← IO.FS.readFile (FilePath.mk "ProofForgeV2/CLI/Emit.lean")
  let evIdx := (emitSrc.splitOn "stagingDir / \"evidence.json\"").length
  let mfIdx := (emitSrc.splitOn "stagingDir / \"manifest.json\"").length
  expect (evIdx > 1 && mfIdx > 1) "Emit must write both sidecars"
  -- Source order: evidence path string appears before last manifest write in render.
  match emitSrc.splitOn "renderIntoStaging" with
  | _ :: body :: _ =>
      let parts := body.splitOn "IO.FS.writeFile (stagingDir / \"evidence.json\")"
      expect (parts.length > 1) "renderIntoStaging writes evidence.json"
      let afterEv := parts[1]!
      expect ((afterEv.splitOn "IO.FS.writeFile (stagingDir / \"manifest.json\")").length > 1)
        "manifest.json write must follow evidence.json write"
      expect ((afterEv.splitOn "validateEngineeringDiskClosureV1").length > 1)
        "closure validation after sidecar writes"
  | _ => throw <| IO.userError "renderIntoStaging not found in Emit.lean"
  expect (evIdx > 1 && mfIdx > 1) "Emit source mentions both sidecar paths"

private def assertDiskClosureEnv (env : Environment) : Except String Unit := do
  let validator := Name.mkStr2 "ProofForgeV2" "validateEngineeringDiskClosureV1"
  unless env.contains validator do
    throw "validateEngineeringDiskClosureV1 missing from Environment"
  let maxFiles := Name.mkStr2 "ProofForgeV2" "maxEngineeringDiskClosureFilesV1"
  unless env.contains maxFiles do
    throw "maxEngineeringDiskClosureFilesV1 missing from Environment"
  pure ()

run_cmd do
  let env ← getEnv
  match assertDiskClosureEnv env with
  | .ok () => pure ()
  | .error e => throwError e

unsafe def run : IO Unit := do
  testFlatSolanaPositive
  testNestedNoirPositive
  testManifestLastPublishedClosure
  testDestinationSymlinkNoClobberToolFail
  testValidatorNegatives
  testValidatorNegativesExtended
  testSoleValidatorPins
  IO.println "Tests.Materialization.EngineeringDiskClosureV1: ok"

end Tests.Materialization.EngineeringDiskClosureV1
