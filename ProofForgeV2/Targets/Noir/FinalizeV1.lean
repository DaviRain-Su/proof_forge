/-
  Noir engineering finalization adapter (D3/S7b / NOIR-IR-6).

  Profile branches (exhaustive):
  * `noir-source-u64-relations-v1` (default): zero tools; transitional `.nr`
    relation packages + relations JSON as materialized base only. Evidence
    notes that ACIR product dual-write is opt-in. `deployable=false`.
  * `noir-nargo-1.0.0-beta.26-acir-v1`: resolve nargo (same capture path as
    CaptureV1), compile each staged relation package, path-normalize
    ProgramArtifact JSON (`file_map.path` → `src/main.nr`), and stage extras
    under `nargo-compile/{stem}/{pf_relation_N}.json`. Missing nargo fails
    closed (`PF-TOOLCHAIN-MISSING`). Still `deployable=false`; no prove/VK.
  * unknown profile: fail closed.

  Separate from pure `Targets.Noir` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1 / hermetic finalization.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.Noir.Acir.CaptureV1
import ProofForgeV2.Targets.Noir.Acir.InventoryV1
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.Noir.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Targets.Noir.Acir.CaptureV1
open ProofForgeV2.Targets.Noir.Acir.InventoryV1
open System

private def sourceProfileNote : String := finalizeEvidenceNoteV1

private def finalizeSourceProfile : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote := sourceProfileNote
  }

private def requireRegularNonemptyFile
    (label : String) (path : FilePath) : IO ByteArray := do
  unless ← path.pathExists do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: missing {label} '{path}'"
  let metadata ← path.symlinkMetadata
  unless metadata.type == .file do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: {label} is not a regular file"
  let bytes ← IO.FS.readBinFile path
  if bytes.isEmpty then
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: {label} is empty"
  pure bytes

private def requireExactStagingBase
    (stagingDir : FilePath) (file : OutputFile) : IO Unit := do
  let path := stagingDir / file.path
  let bytes ← requireRegularNonemptyFile s!"staging base {file.path}" path
  unless bytes == file.contents.toUTF8 do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: staging base '{file.path}' diverges from materialized bytes"

/-- Collect unique relation package stems from materialized base paths
    (`relations/{stem}/…`). Order is first-seen (materialize order). -/
private def relationStemsFromFiles (files : Array OutputFile) : Array String :=
  Id.run do
    let mut stems : Array String := #[]
    for f in files do
      match f.path.splitOn "/" with
      | "relations" :: stem :: _rest =>
          if !stems.contains stem then
            stems := stems.push stem
      | _ => pure ()
    pure stems

private def finalizeAcirProfile
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := CodegenProfileId.noirNargoAcirV1
  unless ResolvedEngineeringBuildV1.codegenProfileOf capability == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Noir ACIR finalize capability profile mismatch"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Noir ACIR finalize artifact profile mismatch"
  unless ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.noir &&
      ResolvedEngineeringBuildV1.kindOf capability == .noir do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Noir ACIR finalize capability target mismatch"
  unless MaterializedArtifactsV1.targetIdOf artifacts == TargetId.noir &&
      MaterializedArtifactsV1.kindOf artifacts == .noir do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Noir ACIR finalize artifact target mismatch"

  let files := MaterializedArtifactsV1.filesOf artifacts
  for f in files do
    requireExactStagingBase stagingDir f

  let stems := relationStemsFromFiles files
  if stems.isEmpty then
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Noir ACIR finalize requires at least one relations/* package"

  let nargo? ← resolveNargoPathV1
  let nargo ← match nargo? with
    | some path => pure path
    | none =>
        throw <| IO.userError
          ("PF-TOOLCHAIN-MISSING: noir-nargo-1.0.0-beta.26-acir-v1 requires " ++
            "locked/ambient nargo 1.0.0-beta.26; pure-Lean ACIR encoder is not " ++
            "implemented (NOIR-IR-6 host-dependent dual-write)")

  -- Compile outside product staging so nargo `target/` never pollutes the
  -- exact disk-closure inventory (publisher rejects unexpected directories).
  IO.FS.withTempDir fun tempRoot => do
    let mut extras : Array String := #[]
    for stem in stems do
      let packageDir := stagingDir / "relations" / stem
      let tomlPath := packageDir / "Nargo.toml"
      let mainPath := packageDir / "src" / "main.nr"
      let tomlBytes ← requireRegularNonemptyFile s!"Nargo.toml for {stem}" tomlPath
      let mainBytes ← requireRegularNonemptyFile s!"main.nr for {stem}" mainPath
      let toml ← match String.fromUTF8? tomlBytes with
        | some text => pure text
        | none =>
            throw <| IO.userError
              s!"PF-ARTIFACT-NONDEPLOYABLE: Nargo.toml for {stem} is not UTF-8"
      let packageName ← match extractNargoPackageNameV1 toml with
        | some name => pure name
        | none =>
            throw <| IO.userError
              s!"PF-ARTIFACT-NONDEPLOYABLE: cannot parse package name in {tomlPath}"
      let artifactName := s!"{packageName}.json"
      let workDir := tempRoot / stem
      IO.FS.createDirAll (workDir / "src")
      IO.FS.writeBinFile (workDir / "Nargo.toml") tomlBytes
      IO.FS.writeBinFile (workDir / "src" / "main.nr") mainBytes
      let (normalized, core) ←
        compilePackageCaptureProgramArtifactV1 nargo workDir artifactName
      unless core.noirVersion == noirVersionExactV1 do
        throw <| IO.userError
          (s!"PF-TOOLCHAIN-MISMATCH: nargo noir_version '{core.noirVersion}' " ++
            s!"≠ pinned '{noirVersionExactV1}' for relation {stem}")
      unless envelopeKeysPresentV1 normalized do
        throw <| IO.userError
          s!"PF-ARTIFACT-NONDEPLOYABLE: ProgramArtifact envelope incomplete for {stem}"
      unless normalizedPathPresentV1 normalized do
        throw <| IO.userError
          s!"PF-ARTIFACT-NONDEPLOYABLE: path-normalized file_map missing for {stem}"
      let extraRel := acirExtraRelPathV1 stem artifactName
      let outDir := stagingDir / "nargo-compile" / stem
      IO.FS.createDirAll outDir
      IO.FS.writeFile (outDir / artifactName) normalized
      extras := extras.push extraRel

    pure {
      deployable := false
      extraFiles := extras
      evidenceNote :=
        finalizeAcirEvidenceNotePrefixV1 ++
          s!"; nargo={nargo}; noir_version_pin={noirVersionExactV1}; " ++
          s!"relationCount={stems.size}; extraCount={extras.size}"
    }

private def finalizeUnknownProfile
    (profile : CodegenProfileId) : IO EngineeringFinalizationDraftV1 :=
  throw <| IO.userError
    s!"PF-ARTIFACT-NONDEPLOYABLE: unknown Noir codegen profile '{profile}'"

/-- Noir finalization is profile-exhaustive: the default stays zero-tool while
    the explicit ACIR profile dual-writes nargo-assisted ProgramArtifact extras. -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.noirSourceU64RelationsV1 then
    finalizeSourceProfile
  else if profile == CodegenProfileId.noirNargoAcirV1 then
    finalizeAcirProfile capability artifacts stagingDir
  else
    finalizeUnknownProfile profile

end ProofForgeV2.Targets.Noir.FinalizeV1
