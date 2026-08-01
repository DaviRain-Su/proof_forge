/-
  M3c engineering OutputSet carrier + CLI publisher suite.

  Pins:
  * domain / schema surface (engineering-only names)
  * mint determinism from FinalizedArtifactsV1
  * outputSetDigest sensitivity to files / identity digests / deployable
  * product-path recompute: emit → on-disk manifest == render(mint)
  * evidence→manifest-last + exact disk closure still holds
  * sole-mint / forbidden public names (OutputSet/makeOutput/manifestJson/…)

  **Not** formal TASK-D3-05 / formal OutputSetV1 / hermetic publish.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Core.Common
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.EngineeringDiskClosureV1
import ProofForgeV2.Materialization.OutputSetV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Targets.SupportClaimV1
import Tests.Language.ParserSession

namespace Tests.Materialization.OutputSetV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Core.Common
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.SupportClaimV1
open System

private def expect (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

private def liftResult (label : String) (result : CompileResult α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError s!"{label}: {error.render}"

private def liftExcept (label : String) (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error e => throw <| IO.userError s!"{label}: {e}"

private def expectDigestDiff (label : String) (base alt : Digest) : IO Unit :=
  expect (!(base.bytes == alt.bytes)) s!"{label}: digest must change"

private unsafe def compileCounter : IO CompiledSemanticV1 := do
  let session ← Tests.Language.ParserSession.shared
  let source ← liftResult "load Counter" (← session.selectProgramV1
    Examples.counterSourceText "<output-set-counter>"
    Examples.counterModuleNameV1 none)
  liftResult "compile Counter" (Compiler.compileValidatedSourceV1 source)

private unsafe def materializeTarget
    (compiled : CompiledSemanticV1) (tid : TargetId) :
    IO (Targets.ResolvedEngineeringBuildV1 × MaterializedArtifactsV1) := do
  let selection ← liftResult s!"select {tid}" (resolveBuildSelectionV1 tid none)
  let capability ← liftResult s!"resolve {tid}"
    (Targets.resolveEngineeringRequirementsV1 selection compiled)
  let artifacts ← liftResult s!"materialize {tid}"
    (Targets.materializeResult capability)
  pure (capability, artifacts)

/-- Finalize plan-only targets without tool extras into a scratch staging dir. -/
private unsafe def finalizeScratch
    (capability : Targets.ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (scratch : FilePath) : IO FinalizedArtifactsV1 := do
  if ← scratch.pathExists then IO.FS.removeDirAll scratch
  IO.FS.createDirAll scratch
  for file in MaterializedArtifactsV1.filesOf artifacts do
    let path := scratch / file.path
    if let some parent := path.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile path file.contents
  Targets.finalizeMaterializedArtifactsV1 capability artifacts scratch

private def testDomainsAndSchema : IO Unit := do
  expect (engineeringOutputSchemaVersionV1 == "proof-forge.output.v1")
    "engineering schema version"
  expect (engineeringOutputSetDomainV1 == "pf.output-set.engineering.v1")
    "engineering output-set domain"
  expect (engineeringOutputSetDomainV1.endsWith ".engineering.v1")
    "engineering domain suffix"
  match validateProfileIdValue engineeringOutputSetDomainV1 with
  | .ok () => pure ()
  | .error e => throw <| IO.userError s!"output-set domain grammar: {e}"

private unsafe def testMintDeterminismFourTargets : IO Unit := do
  let compiled ← compileCounter
  for tid in #[TargetId.solana, TargetId.noir] do
    let (cap, arts) ← materializeTarget compiled tid
    let scratch := FilePath.mk s!"build/v2/output-set-mint-{tid}"
    let finalized ← finalizeScratch cap arts scratch
    let a ← liftResult s!"mint {tid} a" (mintEngineeringOutputSetV1 finalized)
    let b ← liftResult s!"mint {tid} b" (mintEngineeringOutputSetV1 finalized)
    expect (EngineeringOutputSetV1.beq a b) s!"{tid} output set mint deterministic"
    expect (EngineeringOutputSetV1.targetIdOf a == tid) s!"{tid} target"
    expect (EngineeringOutputSetV1.artifactProgramNameOf a == "Counter")
      s!"{tid} artifact name"
    expect (EngineeringOutputSetV1.deployableOf a == false)
      s!"{tid} plan/source-only non-deployable"
    expect (!(EngineeringOutputSetV1.filesOf a).isEmpty) s!"{tid} files nonempty"
    -- Sidecars never enter files.
    expect (!((EngineeringOutputSetV1.filesOf a).contains "manifest.json"))
      s!"{tid} no manifest in files"
    expect (!((EngineeringOutputSetV1.filesOf a).contains "evidence.json"))
      s!"{tid} no evidence in files"
    -- Digest recomputes from fields.
    let recomputed ← liftExcept s!"recompute {tid}"
      (engineeringOutputSetDigestV1
        (EngineeringOutputSetV1.targetIdOf a)
        (EngineeringOutputSetV1.codegenProfileOf a)
        (EngineeringOutputSetV1.artifactProgramNameOf a)
        (EngineeringOutputSetV1.filesOf a)
        (EngineeringOutputSetV1.sourceDigestOf a)
        (EngineeringOutputSetV1.semanticDigestOf a)
        (EngineeringOutputSetV1.engineeringRegistryRootDigestOf a)
        (EngineeringOutputSetV1.supportClaimDigestOf a)
        (EngineeringOutputSetV1.buildIdentityDigestOf a)
        (EngineeringOutputSetV1.deployableOf a))
    expect (EngineeringOutputSetV1.outputSetDigestOf a == recomputed)
      s!"{tid} outputSetDigest recomputes"
    -- Nested build-identity digest matches materialization.
    expect (EngineeringOutputSetV1.buildIdentityDigestOf a ==
        EngineeringBuildIdentityV1.identityDigestOf
          (MaterializedArtifactsV1.buildIdentityOf arts))
      s!"{tid} buildIdentityDigest bound from materialization"
    let claim := Targets.ResolvedEngineeringBuildV1.supportClaimOf cap
    expect (EngineeringOutputSetV1.supportClaimDigestOf a ==
        EngineeringSupportClaimV1.claimDigestOf claim)
      s!"{tid} supportClaimDigest bound from capability"
    if ← scratch.pathExists then IO.FS.removeDirAll scratch

private unsafe def testDigestTamperMatrix : IO Unit := do
  let compiled ← compileCounter
  let (cap, arts) ← materializeTarget compiled TargetId.solana
  let scratch := FilePath.mk "build/v2/output-set-tamper"
  let finalized ← finalizeScratch cap arts scratch
  let base ← liftResult "base mint" (mintEngineeringOutputSetV1 finalized)
  let baseDigest := EngineeringOutputSetV1.outputSetDigestOf base
  -- File list mutation (append synthetic path) changes digest.
  let altFiles := EngineeringOutputSetV1.filesOf base |>.push "extra.shadow"
  let filesDigest ← liftExcept "files tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      altFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.deployableOf base))
  expectDigestDiff "files list" baseDigest filesDigest
  -- Deployable flip.
  let deployDigest ← liftExcept "deployable tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      (EngineeringOutputSetV1.filesOf base)
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      true)
  expectDigestDiff "deployable" baseDigest deployDigest
  -- Build-identity digest field flip (use semantic digest bytes as stand-in).
  let flippedIdentity := EngineeringOutputSetV1.semanticDigestOf base
  expectDigestDiff "identity field stand-in distinct"
    (EngineeringOutputSetV1.buildIdentityDigestOf base) flippedIdentity
  let identityDigest ← liftExcept "identity tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      (EngineeringOutputSetV1.filesOf base)
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      flippedIdentity
      (EngineeringOutputSetV1.deployableOf base))
  expectDigestDiff "buildIdentityDigest field" baseDigest identityDigest
  -- Artifact name change.
  let nameDigest ← liftExcept "name tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      "NotCounter"
      (EngineeringOutputSetV1.filesOf base)
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.deployableOf base))
  expectDigestDiff "artifactProgramName" baseDigest nameDigest
  if ← scratch.pathExists then IO.FS.removeDirAll scratch

private unsafe def testProductPathDiskRecompute : IO Unit := do
  let compiled ← compileCounter
  let (cap, arts) ← materializeTarget compiled TargetId.solana
  let outDir := FilePath.mk "build/v2/output-set-product-solana"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let receipt ← ProofForgeV2.CLI.emitProgram cap outDir
  expect (receipt.target == TargetId.solana) "receipt target"
  expect (receipt.deployable == false) "receipt deployable"
  -- Independent recompute via finalize + mint + render.
  let scratch := FilePath.mk "build/v2/output-set-product-scratch"
  let finalized ← finalizeScratch cap arts scratch
  let outputSet ← liftResult "mint" (mintEngineeringOutputSetV1 finalized)
  let expectedManifest ← liftExcept "render"
    (renderEngineeringOutputSetManifestV1 outputSet)
  let expectedEvidence ← liftExcept "evidence"
    (renderEngineeringOutputSetEvidenceV1 outputSet)
  let diskManifest ← IO.FS.readFile (outDir / "manifest.json")
  let diskEvidence ← IO.FS.readFile (outDir / "evidence.json")
  expect (diskManifest == expectedManifest)
    s!"product manifest byte identity:\n---got---\n{diskManifest}\n---want---\n{expectedManifest}"
  expect (diskEvidence == expectedEvidence)
    "product evidence byte identity"
  expect ((diskManifest.splitOn "\"schemaVersion\": \"proof-forge.output.v1\"").length > 1)
    "schema pin"
  -- Exact disk closure still holds (S7c).
  validateEngineeringDiskClosureV1 finalized outDir
  -- Sidecars present; files order exact.
  expect ((EngineeringOutputSetV1.filesOf outputSet) ==
      #["Counter.sbpf-plan", "Counter.idl.json"])
    "solana files order"
  if ← scratch.pathExists then IO.FS.removeDirAll scratch

private def testSoleMintAndForbiddenNames : IO Unit := do
  -- Forbidden public product surfaces from s7 gate must not reappear.
  let forbid : Array (String × String) := #[
    ("^\\s*structure OutputSet\\b", "no public structure OutputSet"),
    ("^\\s*structure OutputManifest\\b", "no public structure OutputManifest"),
    ("^\\s*def makeOutput\\b", "no public makeOutput"),
    ("^\\s*def manifestJson\\b", "no public manifestJson"),
    ("^\\s*def validateOutputSet\\b", "no public validateOutputSet")
  ]
  for (pat, label) in forbid do
    let out ← IO.Process.output {
      cmd := "rg"
      args := #["-n", "--glob", "*.lean", "-e", pat, "ProofForgeV2"]
    }
    if out.exitCode == 0 then
      throw <| IO.userError s!"{label}: residual matches:\n{out.stdout}"
    else if out.exitCode != 1 then
      throw <| IO.userError s!"{label}: rg failed ({out.exitCode}): {out.stderr}"
  -- Sole EngineeringOutputSetV1.mk in OutputSetV1.lean.
  let mk ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "EngineeringOutputSetV1\\.mk", "ProofForgeV2"]
  }
  unless mk.exitCode == 0 do
    throw <| IO.userError
      s!"expected EngineeringOutputSetV1.mk, rg exit {mk.exitCode}: {mk.stderr}"
  let lines := (mk.stdout.splitOn "\n").filter (fun s => !s.isEmpty)
  for line in lines do
    unless line.startsWith "ProofForgeV2/Materialization/OutputSetV1.lean:" do
      throw <| IO.userError
        s!"EngineeringOutputSetV1.mk only allowed in OutputSetV1.lean, got: {line}"
  -- Sole mint entry.
  let mint ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "^\\s*def mintEngineeringOutputSetV1\\b", "ProofForgeV2"]
  }
  unless mint.exitCode == 0 do
    throw <| IO.userError
      s!"expected mintEngineeringOutputSetV1, rg exit {mint.exitCode}: {mint.stderr}"
  let mintLines := (mint.stdout.splitOn "\n").filter (fun s => !s.isEmpty)
  expect (mintLines.length == 1)
    s!"sole mintEngineeringOutputSetV1: got {mintLines}"
  -- Legacy v2alpha1 renderer deleted.
  let legacy ← IO.Process.output {
    cmd := "rg"
    args := #["-n", "--glob", "*.lean", "-e",
      "LegacyOutputManifestV2Alpha1|renderLegacyManifestJsonV2Alpha1|proof-forge-output/v2alpha1",
      "ProofForgeV2"]
  }
  if legacy.exitCode == 0 then
    throw <| IO.userError s!"legacy v2alpha1 residual:\n{legacy.stdout}"
  else if legacy.exitCode != 1 then
    throw <| IO.userError s!"legacy scan rg failed ({legacy.exitCode}): {legacy.stderr}"

unsafe def run : IO Unit := do
  testDomainsAndSchema
  testMintDeterminismFourTargets
  testDigestTamperMatrix
  testProductPathDiskRecompute
  testSoleMintAndForbiddenNames
  IO.println "Tests.Materialization.OutputSetV1: ok"

end Tests.Materialization.OutputSetV1
