/-
  M3c / D3-E7 engineering OutputSet carrier + CLI publisher suite.

  Pins:
  * domain / schema surface (engineering-only names)
  * mint determinism from FinalizedArtifactsV1 + ArtifactContentInventoryV1
  * outputSetDigest sensitivity to role/path/size/hash / evidence / deployable
  * product-path recompute: emit → on-disk manifest == render(mint)
  * evidence→manifest-last + pre/post inventory + exact disk closure
  * sole-mint / forbidden public names (OutputSet/makeOutput/manifestJson/…)

  **Not** formal TASK-D3-05 / formal OutputSetV1 / hermetic publish.
-/
import ProofForgeV2
import ProofForgeV2.CLI.Emit
import ProofForgeV2.Core.Common
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Materialization.ArtifactContentV1
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

private unsafe def mintFromStaging
    (finalized : FinalizedArtifactsV1) (staging : FilePath) :
    IO EngineeringOutputSetV1 := do
  let inv ← scanEngineeringArtifactContentOnlyV1 finalized staging
  liftResult "mint" (mintEngineeringOutputSetV1 finalized inv)

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

private def testEngineeringJsonAndEvidenceBoundaries : IO Unit := do
  expect (Targets.escapeJson "a\tb\rc" == "a\\tb\\rc")
    "engineering JSON escapes tab/carriage return"
  let digest := sha256Bytes ByteArray.empty
  match renderEngineeringEvidenceBodyV1 TargetId.solana digest digest false "bad\u0001note" with
  | .ok _ => throw <| IO.userError "evidence control character must fail closed"
  | .error e =>
      expect ((e.splitOn "unsupported control character").length > 1)
        s!"evidence control diagnostic: {e}"
  let mut atNestingBound := ""
  for _ in [:64] do
    atNestingBound := atNestingBound ++ "["
  atNestingBound := atNestingBound ++ "null"
  for _ in [:64] do
    atNestingBound := atNestingBound ++ "]"
  match ProofForgeV2.CLI.parseEngineeringJsonDocumentV1 atNestingBound with
  | .ok _ => pure ()
  | .error e => throw <| IO.userError s!"depth-64 JSON must be accepted: {e}"
  let mut deeplyNested := ""
  for _ in [:65] do
    deeplyNested := deeplyNested ++ "["
  deeplyNested := deeplyNested ++ "null"
  for _ in [:65] do
    deeplyNested := deeplyNested ++ "]"
  match ProofForgeV2.CLI.parseEngineeringJsonDocumentV1 deeplyNested with
  | .ok _ => throw <| IO.userError "deep engineering JSON must fail closed"
  | .error e =>
      expect ((e.splitOn "json nesting exceeds bound").length > 1)
        s!"deep engineering JSON diagnostic: {e}"

private unsafe def testMintDeterminismFourTargets : IO Unit := do
  let compiled ← compileCounter
  for tid in #[TargetId.solana, TargetId.noir] do
    let (cap, arts) ← materializeTarget compiled tid
    let scratch := FilePath.mk s!"build/v2/output-set-mint-{tid}"
    let finalized ← finalizeScratch cap arts scratch
    let a ← mintFromStaging finalized scratch
    let b ← mintFromStaging finalized scratch
    expect (EngineeringOutputSetV1.beq a b) s!"{tid} output set mint deterministic"
    expect (EngineeringOutputSetV1.targetIdOf a == tid) s!"{tid} target"
    expect (EngineeringOutputSetV1.artifactProgramNameOf a == "Counter")
      s!"{tid} artifact name"
    let expectedDeployable := tid == TargetId.solana
    expect (EngineeringOutputSetV1.deployableOf a == expectedDeployable)
      s!"{tid} deployable must match target finalization"
    expect (!(EngineeringOutputSetV1.filesOf a).isEmpty) s!"{tid} files nonempty"
    -- Sidecars never enter files.
    let paths := (EngineeringOutputSetV1.filesOf a).map (·.path)
    expect (!(paths.contains "manifest.json")) s!"{tid} no manifest in files"
    expect (!(paths.contains "evidence.json")) s!"{tid} no evidence in files"
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
        (EngineeringOutputSetV1.planDigestOf a)
        (EngineeringOutputSetV1.deployableOf a)
        (EngineeringOutputSetV1.evidenceSha256Of a))
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
    -- evidenceSha256 matches render(evidence) UTF-8.
    let evidence ← liftExcept s!"evidence {tid}"
      (renderEngineeringOutputSetEvidenceV1 a)
    let evidenceDigest := sha256Bytes evidence.toUTF8
    expect (EngineeringOutputSetV1.evidenceSha256Of a == evidenceDigest)
      s!"{tid} evidenceSha256 binds exact evidence UTF-8"
    if ← scratch.pathExists then IO.FS.removeDirAll scratch

private unsafe def testDigestTamperMatrix : IO Unit := do
  let compiled ← compileCounter
  let (cap, arts) ← materializeTarget compiled TargetId.solana
  let scratch := FilePath.mk "build/v2/output-set-tamper"
  let finalized ← finalizeScratch cap arts scratch
  let base ← mintFromStaging finalized scratch
  let baseDigest := EngineeringOutputSetV1.outputSetDigestOf base
  let baseFiles := EngineeringOutputSetV1.filesOf base
  expect (baseFiles.size ≥ 1) "tamper fixture nonempty files"
  let d0 ← match baseFiles.toList with
    | h :: _ => pure h
    | [] => throw <| IO.userError "tamper fixture empty"
  -- Path mutation on first descriptor.
  let altPathFiles := baseFiles.set! 0 { d0 with path := "extra.shadow" }
  let pathDigest ← liftExcept "path tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      altPathFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (EngineeringOutputSetV1.deployableOf base)
      (EngineeringOutputSetV1.evidenceSha256Of base))
  expectDigestDiff "descriptor path" baseDigest pathDigest
  -- Size mutation.
  let altSizeFiles := baseFiles.set! 0 { d0 with size := d0.size + 1 }
  let sizeDigest ← liftExcept "size tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      altSizeFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (EngineeringOutputSetV1.deployableOf base)
      (EngineeringOutputSetV1.evidenceSha256Of base))
  expectDigestDiff "descriptor size" baseDigest sizeDigest
  -- Content hash mutation (use source digest as stand-in).
  let altHashFiles := baseFiles.set! 0
    { d0 with contentSha256 := EngineeringOutputSetV1.sourceDigestOf base }
  let hashDigest ← liftExcept "content hash tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      altHashFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (EngineeringOutputSetV1.deployableOf base)
      (EngineeringOutputSetV1.evidenceSha256Of base))
  expectDigestDiff "descriptor contentSha256" baseDigest hashDigest
  -- Role flip (only if single role present; always flip first to opposite).
  let flippedRole : ArtifactContentRoleV1 :=
    match d0.role with
    | .materializedBase => .finalizedExtra
    | .finalizedExtra => .materializedBase
  let altRoleFiles := baseFiles.set! 0 { d0 with role := flippedRole }
  let roleDigest ← liftExcept "role tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      altRoleFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (EngineeringOutputSetV1.deployableOf base)
      (EngineeringOutputSetV1.evidenceSha256Of base))
  expectDigestDiff "descriptor role" baseDigest roleDigest
  -- Evidence digest flip.
  let flippedEvidence := EngineeringOutputSetV1.semanticDigestOf base
  expectDigestDiff "evidence stand-in distinct"
    (EngineeringOutputSetV1.evidenceSha256Of base) flippedEvidence
  let evidenceDigest ← liftExcept "evidence tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      baseFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (EngineeringOutputSetV1.deployableOf base)
      flippedEvidence)
  expectDigestDiff "evidenceSha256 field" baseDigest evidenceDigest
  -- Deployable flip.
  let deployDigest ← liftExcept "deployable tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      (EngineeringOutputSetV1.artifactProgramNameOf base)
      baseFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (!EngineeringOutputSetV1.deployableOf base)
      (EngineeringOutputSetV1.evidenceSha256Of base))
  expectDigestDiff "deployable" baseDigest deployDigest
  -- Artifact name change.
  let nameDigest ← liftExcept "name tamper"
    (engineeringOutputSetDigestV1
      (EngineeringOutputSetV1.targetIdOf base)
      (EngineeringOutputSetV1.codegenProfileOf base)
      "NotCounter"
      baseFiles
      (EngineeringOutputSetV1.sourceDigestOf base)
      (EngineeringOutputSetV1.semanticDigestOf base)
      (EngineeringOutputSetV1.engineeringRegistryRootDigestOf base)
      (EngineeringOutputSetV1.supportClaimDigestOf base)
      (EngineeringOutputSetV1.buildIdentityDigestOf base)
      (EngineeringOutputSetV1.planDigestOf base)
      (EngineeringOutputSetV1.deployableOf base)
      (EngineeringOutputSetV1.evidenceSha256Of base))
  expectDigestDiff "artifactProgramName" baseDigest nameDigest
  if ← scratch.pathExists then IO.FS.removeDirAll scratch

private unsafe def testProductPathDiskRecompute : IO Unit := do
  let compiled ← compileCounter
  let (cap, arts) ← materializeTarget compiled TargetId.solana
  let outDir := FilePath.mk "build/v2/output-set-product-solana"
  if ← outDir.pathExists then IO.FS.removeDirAll outDir
  let receipt ← ProofForgeV2.CLI.emitProgram cap outDir
  expect (receipt.target == TargetId.solana) "receipt target"
  expect (receipt.deployable == true) "sole-rail Solana receipt deployable"
  expect (← (outDir / "Counter.so").pathExists)
    "sole-rail Solana finalization must publish Counter.so"
  -- Independent recompute via finalize + scan + mint + render.
  let scratch := FilePath.mk "build/v2/output-set-product-scratch"
  let finalized ← finalizeScratch cap arts scratch
  let outputSet ← mintFromStaging finalized scratch
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
  expect ((diskManifest.splitOn "\"evidenceSha256\":").length > 1)
    "manifest binds evidenceSha256"
  expect ((diskManifest.splitOn "\"contentSha256\":").length > 1)
    "manifest files carry contentSha256"
  expect ((diskManifest.splitOn "\"role\": \"materialized-base\"").length > 1)
    "manifest files carry materialized-base role"
  expect ((diskManifest.splitOn "\"role\": \"finalized-extra\"").length > 1 &&
      (diskManifest.splitOn "\"path\": \"Counter.so\"").length > 1)
    "manifest must bind the locked-sbpf Counter.so finalized extra"
  expect ((diskManifest.splitOn "\"deployable\": true").length > 1)
    "manifest must mark sole-rail Solana deployable"
  -- Exact disk closure still holds (S7c).
  validateEngineeringDiskClosureV1 finalized outDir
  -- Files order is canonical role-rank then UTF-8 path (not materializer source order).
  let paths := (EngineeringOutputSetV1.filesOf outputSet).map (·.path)
  expect (paths == #[
      "Counter.cpi-bindings.json",
      "Counter.cpi-ir.json",
      "Counter.cpi-plan.json",
      "Counter.idl.json",
      "Counter.s",
      "Counter.so"])
    s!"solana files canonical path order, got {paths}"
  -- Inspect product path accepts the published dir.
  let inspected ← ProofForgeV2.CLI.inspectEngineeringOutputDirV1 outDir
  expect (inspected.target == "solana") "inspect target"
  expect (inspected.files.size == 6) "inspect file count"
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
  -- Path-only files accessor residual should not reappear as Array String files.
  -- (filesOf now returns Array ArtifactContentDescriptorV1)

private unsafe def testLegacyPathOnlyManifestRejected : IO Unit := do
  -- Hand-built path-only files array under proof-forge.output.v1 must fail closed.
  let legacy :=
    "{\n" ++
    "  \"schemaVersion\": \"proof-forge.output.v1\",\n" ++
    "  \"target\": \"solana\",\n" ++
    "  \"codegenProfile\": \"solana-sbpf-cpi-elf-v1\",\n" ++
    "  \"artifactProgramName\": \"Counter\",\n" ++
    "  \"sourceHash\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"semanticHash\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"buildIdentityDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"planDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"supportClaimDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"engineeringRegistryRootDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"outputSetDigest\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"evidenceSha256\": \"0000000000000000000000000000000000000000000000000000000000000000\",\n" ++
    "  \"deployable\": false,\n" ++
    "  \"files\": [\"Counter.s\",\"Counter.idl.json\"]\n" ++
    "}\n"
  match ProofForgeV2.CLI.validateEngineeringOutputManifestTextV1 legacy with
  | .ok _ => throw <| IO.userError "legacy path-only files must fail"
  | .error e =>
      expect ((e.splitOn "path-only").length > 1 ||
          (e.splitOn "must be objects").length > 1)
        s!"legacy rejection must mention path-only/objects: {e}"

unsafe def run : IO Unit := do
  testDomainsAndSchema
  testEngineeringJsonAndEvidenceBoundaries
  testMintDeterminismFourTargets
  testDigestTamperMatrix
  testProductPathDiskRecompute
  testSoleMintAndForbiddenNames
  testLegacyPathOnlyManifestRejected
  IO.println "Tests.Materialization.OutputSetV1: ok"

end Tests.Materialization.OutputSetV1
