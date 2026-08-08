/-
  Aleo engineering finalization adapter (D3/S7b / ALEO-I4 / ALEO-IR-6).

  Profile branches (exhaustive):
  * `aleo-leo-4.0.2-u64-v1` (default): zero tools; primary is Aleo Instructions
    text (`{id}.aleo` when Plan→Instructions succeeds) plus network-state
    query descriptor. Transitional Leo 4 source is debug-only
    (`PROOF_FORGE_ALEO_EMIT_LEO=1` / `emitLeoDebug`) and not required here.
  * `aleo-leo-4.0.2-u64-compile-v1`: resolve locked Leo 4.0.2, compile the
    dual-written transitional `{id}.leo` (preferred) or residual Leo-primary
    `{id}.aleo` inside a temporary package and isolated HOME, then stage
    exactly three finalized extras: compiled Aleo instructions, ABI JSON, and
    Leo program JSON. Primary product Instructions base is **not** fed to
    `leo` (it is already Instructions). Query-contract never enters the Leo
    package. Compile success is a **compare** path, not sole authority, and
    does not imply execute/proof/deploy/query, so `deployable=false` remains
    exact.
  * unknown profile: fail closed.

  Separate from pure `Targets.Aleo` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1 / hermetic finalization.
-/
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.Aleo.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Materialization.LockedToolchainV1
open System

private def sourceProfileNote : String :=
  "product finalization does not invoke the locked Leo compiler or a proving backend; ALEO-IR-6 primary is Aleo Instructions text ({id}.aleo when Plan→Instructions succeeds) plus network-state query descriptor; transitional Leo 4 source is debug-only (PROOF_FORGE_ALEO_EMIT_LEO=1 or emitLeoDebug build flag, or compile-profile dual-write for compare); residual Plan shapes not yet on Instructions keep Leo as .aleo primary until G5 hard-require; no leo build, execution, proof, or deployment evidence (deployable=false)"

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

private def leoPackageJson (programName : String) : String :=
  "{\n" ++
  s!"  \"program\": \"{programName}.aleo\",\n" ++
  "  \"version\": \"0.1.0\",\n" ++
  "  \"description\": \"proof-forge-next Aleo compiled finalization\",\n" ++
  "  \"license\": \"MIT\",\n" ++
  "  \"leo\": \"4.0.2\",\n" ++
  "  \"dependencies\": null,\n" ++
  "  \"dev_dependencies\": null\n" ++
  "}\n"

/-- Leo source uses `program id.aleo {`; Instructions uses `program id.aleo;`. -/
private def looksLikeLeoSourceV1 (contents : String) : Bool :=
  contents.contains ".aleo {"

/-- Resolve Leo 4 source bytes for locked compile compare:
    1. Prefer dual-written `{id}.leo` (Instructions-primary path).
    2. Else residual Leo-primary `{id}.aleo` when contents are Leo source.
    Never feed Instructions text to `leo`. -/
private def resolveLeoSourceForCompileV1
    (programId : String) (files : Array OutputFile) : IO OutputFile := do
  let leoPath := s!"{programId}.leo"
  let aleoPath := s!"{programId}.aleo"
  match files.find? (·.path == leoPath) with
  | some leoFile =>
      unless looksLikeLeoSourceV1 leoFile.contents do
        throw <| IO.userError
          s!"PF-ARTIFACT-NONDEPLOYABLE: dual-written '{leoPath}' is not Leo 4 source"
      pure leoFile
  | none =>
      match files.find? (·.path == aleoPath) with
      | none =>
          throw <| IO.userError
            s!"PF-ARTIFACT-NONDEPLOYABLE: missing primary '{aleoPath}' for compile compare"
      | some aleoFile =>
          unless looksLikeLeoSourceV1 aleoFile.contents do
            throw <| IO.userError
              ("PF-ARTIFACT-NONDEPLOYABLE: compile profile requires dual-written " ++
                s!"'{leoPath}' (or residual Leo-primary '{aleoPath}'); primary " ++
                "Instructions text cannot be fed to leo")
          pure aleoFile

private def finalizeCompileProfile
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := CodegenProfileId.aleoLeoU64CompileV1
  unless ResolvedEngineeringBuildV1.codegenProfileOf capability == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize capability profile mismatch"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize artifact profile mismatch"
  unless ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.aleo &&
      ResolvedEngineeringBuildV1.kindOf capability == .aleo do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize capability target mismatch"
  unless MaterializedArtifactsV1.targetIdOf artifacts == TargetId.aleo &&
      MaterializedArtifactsV1.kindOf artifacts == .aleo do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize artifact target mismatch"

  let files := MaterializedArtifactsV1.filesOf artifacts
  -- ALEO-IR-6 bases: primary `.aleo` + query (+ optional dual-write `.leo`).
  unless files.size == 2 || files.size == 3 do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize expects 2 or 3 base files, got {files.size}"
  unless files[0]!.path.endsWith ".aleo" do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize requires primary .aleo first"
  let primaryFile := files[0]!
  let programId := (primaryFile.path.dropEnd 5).copy
  let sourceName := s!"{programId}.aleo"
  let queryName := s!"{programId}.aleo-query-contract.json"
  let leoName := s!"{programId}.leo"
  unless !programId.isEmpty && primaryFile.path == sourceName do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: Aleo compiled finalize primary path must be {id}.aleo"
  unless (files.find? (·.path == queryName)).isSome do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: missing query-contract base '{queryName}'"
  for f in files do
    requireExactStagingBase stagingDir f

  let leoSourceFile ← resolveLeoSourceForCompileV1 programId files
  -- Optional consistency: if dual-write present, path must match program id.
  if let some leoFile := files.find? (·.path == leoName) then
    unless leoFile.path == leoSourceFile.path do
      throw <| IO.userError
        "PF-ARTIFACT-NONDEPLOYABLE: dual-written Leo path mismatch"

  let leo ← resolve "leo"
  IO.FS.withTempDir fun tempRoot => do
    let home := tempRoot / "home"
    let projectRoot := tempRoot / "package"
    IO.FS.createDirAll (home / ".aleo")
    IO.FS.createDirAll (projectRoot / "src")
    IO.FS.writeFile (projectRoot / "program.json") (leoPackageJson programId)
    -- Consume dual-written / residual Leo 4 source only. Primary Instructions
    -- `{id}.aleo` and query descriptor are not compiler input.
    IO.FS.writeFile (projectRoot / "src" / "main.leo") leoSourceFile.contents

    -- Keep the actual compile on the LockedToolchainV1 authority path so the
    -- executable, launcher, bundle closure, and process environment are
    -- revalidated immediately before execution. Leo's explicit `--home`
    -- isolates wallet/network registry state without adding ambient env keys.
    let process ← leo.run #[
      "build",
      "--offline",
      "--disable-update-check",
      "--path",
      projectRoot.toString,
      "--home",
      (home / ".aleo").toString
    ] (some projectRoot)
    unless process.exitCode == 0 do
      throw <| IO.userError
        s!"PF-TOOLCHAIN-MISMATCH: leo build failed\n{process.stderr}{process.stdout}"

    let compiledName := s!"{programId}.compiled.aleo"
    let abiName := s!"{programId}.abi.json"
    let programJsonName := s!"{programId}.leo-program.json"
    let compiledBytes ← requireRegularNonemptyFile
      "Leo build/main.aleo output" (projectRoot / "build" / "main.aleo")
    let abiBytes ← requireRegularNonemptyFile
      "Leo build/abi.json output" (projectRoot / "build" / "abi.json")
    let programJsonBytes ← requireRegularNonemptyFile
      "Leo build/program.json output" (projectRoot / "build" / "program.json")
    IO.FS.writeBinFile (stagingDir / compiledName) compiledBytes
    IO.FS.writeBinFile (stagingDir / abiName) abiBytes
    IO.FS.writeBinFile (stagingDir / programJsonName) programJsonBytes
    pure {
      deployable := false
      extraFiles := #[compiledName, abiName, programJsonName]
      evidenceNote :=
        s!"{profile} locked Leo {leo.version} sha256={leo.executableSha256} " ++
        "completed offline compile-only finalization from dual-written/residual Leo 4 source " ++
        "(ALEO-IR-6: primary product authority is Plan→Instructions when lower succeeds; " ++
        "leo-build extras are compare path, not sole Instructions authority); " ++
        "exact outputs are compiled Aleo instructions, ABI JSON, and Leo program JSON; " ++
        "no execution, proof, deployment, or network query was performed (deployable=false)"
    }

private def finalizeUnknownProfile
    (profile : CodegenProfileId) : IO EngineeringFinalizationDraftV1 :=
  throw <| IO.userError
    s!"PF-ARTIFACT-NONDEPLOYABLE: unknown Aleo codegen profile '{profile}'"

/-- Aleo finalization is profile-exhaustive: the default stays zero-tool while
    the explicit compile profile invokes only locked Leo 4.0.2 offline. -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.aleoLeoU64V1 then
    finalizeSourceProfile
  else if profile == CodegenProfileId.aleoLeoU64CompileV1 then
    finalizeCompileProfile capability artifacts stagingDir
  else
    finalizeUnknownProfile profile

end ProofForgeV2.Targets.Aleo.FinalizeV1
