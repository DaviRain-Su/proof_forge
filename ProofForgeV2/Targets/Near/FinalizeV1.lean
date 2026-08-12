/-
  NEAR engineering finalization adapter (D3/S7b).

  Exact locked-wat2wasm path formerly in CLI.Emit.finalizeNear:
  resolve `wat2wasm`, run `#[source,'-o',target]`, existence/file-type/Wasm
  header checks, notes/errors unchanged.

  Separate from pure `Targets.Near` Plan/IR core (no tool runner in Near.lean).
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Near.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Crypto
open ProofForgeV2.Materialization.LockedToolchainV1
open System

private def requireExactStagingWATInputV1
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath)
    (source : String) : IO ByteArray := do
  let some sourceFile :=
      (MaterializedArtifactsV1.filesOf artifacts).find? (·.path == source) |
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: materialized set is missing WAT input '{source}'"
  unless sourceFile.mediaType == "application/wasm-text" do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: materialized WAT input '{source}' has an unexpected media type"
  let sourcePath := stagingDir / source
  unless ← sourcePath.pathExists do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: missing staging WAT input '{source}'"
  let metadata ← sourcePath.symlinkMetadata
  unless metadata.type == .file do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: staging WAT input '{source}' is not a regular file"
  let diskBytes ← IO.FS.readBinFile sourcePath
  unless diskBytes == sourceFile.contents.toUTF8 do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: staging WAT input '{source}' diverges from materialized bytes"
  pure diskBytes

/-- Pure Wasm magic/version gate (exact historical wire + 8-byte header).
    Package-visible for hermetic non-deployable negatives without tool stubs. -/
def requireValidWasmHeader (wasm : ByteArray) : IO Unit := do
  unless wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
      wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
      wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00 do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm output has an invalid Wasm header/version"

private def readDeployableWasmArtifactV1
    (targetPath : FilePath) : IO ByteArray := do
  unless ← targetPath.pathExists do
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm returned no Wasm artifact"
  let metadata ← targetPath.symlinkMetadata
  unless metadata.type == .file do
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm output is not a regular file"
  let wasm ← IO.FS.readBinFile targetPath
  requireValidWasmHeader wasm
  pure wasm

/-- Post-wat2wasm deployability gate: exists + regular file + Wasm header.
    Package-visible for hermetic fixtures (missing / non-file / bad header). -/
def requireDeployableWasmArtifact (targetPath : FilePath) : IO Unit := do
  let _ ← readDeployableWasmArtifactV1 targetPath
  pure ()

/-- Exact NEAR wat2wasm finalization: produce `{programName}.wasm` under stagingDir.
    Requires base `{programName}.wat` already present. Preserves tool args, header
    checks, notes, and error ordering. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let source := s!"{programName}.wat"
  let target := s!"{programName}.wasm"
  -- Bind the finalizer's exact consumer input to the in-memory materialized
  -- WAT before tool resolution or execution. This is byte provenance, not a
  -- claim that wat2wasm preserves the typed IR semantics.
  let sourceBytes ← requireExactStagingWATInputV1 artifacts stagingDir source
  let wat2wasm ← resolve "wat2wasm"
  let args := #[source, "-o", target]
  let process ← wat2wasm.run args (some stagingDir)
  if process.exitCode == 0 then
    let wasmBytes ← readDeployableWasmArtifactV1 (stagingDir / target)
    pure {
      deployable := true
      extraFiles := #[target]
      evidenceNote :=
        s!"near-wat2wasm-observation-v1 tool={wat2wasm.id} " ++
        s!"version={wat2wasm.version} executableSha256={wat2wasm.executableSha256} " ++
        s!"argv={source},-o,{target} inputPath={source} " ++
        s!"inputSha256={sha256Hex sourceBytes} outputPath={target} " ++
        s!"outputSha256={sha256Hex wasmBytes} validWasmHeader=true; " ++
        "translator correctness and runtime remain separate"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: wat2wasm failed\n{process.stderr}"

end ProofForgeV2.Targets.Near.FinalizeV1
