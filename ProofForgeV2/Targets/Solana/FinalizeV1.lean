/-
  Solana engineering finalization adapter (D3/S7b / S2a).

  Profile branches:
  * `solana-sbpf-plan-v1` (default): zero tools; non-deployable plan/IDL note.
  * `solana-sbpf-elf-v1`: resolve locked `sbpf`, assemble staging `{name}.s`
    via a temporary `src/<name>/<name>.s` project, copy `{name}.so` into
    staging as an extra. Tool lock registration is S2b; missing `sbpf`
    fails closed with `PF-TOOLCHAIN-MISSING`.

  Separate from pure `Targets.Solana` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.Solana.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Materialization.LockedToolchainV1
open System

/-- Pure post-sbpf ELF presence gate (mirror of EVM nonempty bytecode).
    Package-visible for hermetic non-deployable negatives without tool stubs. -/
def requireNonemptySbpfElf (soBytes : ByteArray) : IO Unit := do
  if soBytes.isEmpty then
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: sbpf returned an empty .so"

/-- Derive the expected deploy-leaf path under a project root for program `name`.
    Package-visible pure helper (unit-testable without invoking the tool). -/
def deploySoPathV1 (projectRoot : FilePath) (programName : String) : FilePath :=
  projectRoot / "deploy" / s!"{programName}.so"

/-- Derive the sbpf source layout path `src/<name>/<name>.s` under a project root.
    Package-visible pure helper. -/
def projectAsmPathV1 (projectRoot : FilePath) (programName : String) : FilePath :=
  projectRoot / "src" / programName / s!"{programName}.s"

/-- Exact Solana plan-profile zero-tool finalization: no extras, fixed note. -/
private def finalizePlanProfile : IO EngineeringFinalizationDraftV1 :=
  pure {
    deployable := false
    extraFiles := #[]
    evidenceNote :=
      "no pinned/approved sBPF assembler is configured; typed plan and IDL artifacts are non-executable"
  }

/-- ELF-profile finalization: locked `sbpf build` over a temp project that
    mirrors `src/<name>/<name>.s`, then stage `{name}.so` as an extra. -/
private def finalizeElfProfile
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let stagingAsm := stagingDir / s!"{programName}.s"
  unless ← stagingAsm.pathExists do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: missing staging assembly '{programName}.s' for solana-sbpf-elf-v1"
  let asmText ← IO.FS.readFile stagingAsm
  if asmText.isEmpty then
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: staging assembly '{programName}.s' is empty"
  let sbpf ← resolve "sbpf"
  -- Temporary project lives outside staging; disk-closure only observes staging.
  IO.FS.withTempDir fun projectRoot => do
    let asmPath := projectAsmPathV1 projectRoot programName
    if let some parent := asmPath.parent then
      IO.FS.createDirAll parent
    IO.FS.writeFile asmPath asmText
    let deployDir := projectRoot / "deploy"
    IO.FS.createDirAll deployDir
    let process ← sbpf.run #["build", "-d", deployDir.toString] (some projectRoot)
    if process.exitCode != 0 then
      throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: sbpf failed\n{process.stderr}"
    let soPath := deploySoPathV1 projectRoot programName
    unless ← soPath.pathExists do
      throw <| IO.userError
        s!"PF-ARTIFACT-NONDEPLOYABLE: sbpf did not produce '{programName}.so'"
    let soMeta ← soPath.symlinkMetadata
    unless soMeta.type == .file do
      throw <| IO.userError
        "PF-ARTIFACT-NONDEPLOYABLE: sbpf output is not a regular file"
    let soBytes ← IO.FS.readBinFile soPath
    requireNonemptySbpfElf soBytes
    let stagingSo := stagingDir / s!"{programName}.so"
    IO.FS.writeBinFile stagingSo soBytes
    pure {
      deployable := true
      extraFiles := #[s!"{programName}.so"]
      evidenceNote :=
        s!"sbpf {sbpf.version} sha256={sbpf.executableSha256} completed successfully"
    }

/-- Solana finalization: plan profile stays zero-tool; elf profile runs locked sbpf. -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfElfV1 then
    finalizeElfProfile artifacts stagingDir
  else
    finalizePlanProfile

end ProofForgeV2.Targets.Solana.FinalizeV1
