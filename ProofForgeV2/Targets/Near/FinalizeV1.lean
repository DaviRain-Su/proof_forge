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
open ProofForgeV2.Materialization.LockedToolchainV1
open System

/-- Pure Wasm magic/version gate (exact historical wire + 8-byte header).
    Package-visible for hermetic non-deployable negatives without tool stubs. -/
def requireValidWasmHeader (wasm : ByteArray) : IO Unit := do
  unless wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
      wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
      wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00 do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm output has an invalid Wasm header/version"

/-- Post-wat2wasm deployability gate: exists + regular file + Wasm header.
    Package-visible for hermetic fixtures (missing / non-file / bad header). -/
def requireDeployableWasmArtifact (targetPath : FilePath) : IO Unit := do
  unless ← targetPath.pathExists do
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm returned no Wasm artifact"
  let metadata ← targetPath.symlinkMetadata
  unless metadata.type == .file do
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm output is not a regular file"
  let wasm ← IO.FS.readBinFile targetPath
  requireValidWasmHeader wasm

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
  let wat2wasm ← resolve "wat2wasm"
  let process ← wat2wasm.run #[source, "-o", target] (some stagingDir)
  if process.exitCode == 0 then
    requireDeployableWasmArtifact (stagingDir / target)
    pure {
      deployable := true
      extraFiles := #[target]
      evidenceNote :=
        s!"wat2wasm {wat2wasm.version} sha256={wat2wasm.executableSha256} completed; runtime remains separate"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: wat2wasm failed\n{process.stderr}"

end ProofForgeV2.Targets.Near.FinalizeV1
