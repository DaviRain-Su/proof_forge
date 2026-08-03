/-
  Ton engineering finalization adapter (D3/S7b).

  Pipeline:
  1. resolve locked `tolk` (content-addressed Tool Lock; tool-root must stay
     lock-closure clean — no companion dirs inside PROOF_FORGE_TOOL_ROOT)
  2. compile `{name}.tolk` → `{name}.fif` + `{name}.abi.json` (tolk artifacts)
  3. companion `fift` (outside tool-root) runs the generated Fift to write
     `{name}.compiled.boc`
  4. stage .fif / .abi.json / .boc as finalized extras; deployable when BoC present

  Companion discovery (first hit wins; must be absolute paths outside tool-root):
  * stdlib: `$PROOF_FORGE_TOLK_STDLIB` or `$PROOF_FORGE_TON_TOOLS/tolk-stdlib`
  * fift:   `$PROOF_FORGE_FIFT` or `$PROOF_FORGE_TON_TOOLS/fift`
  * fiftlib:`$PROOF_FORGE_FIFTLIB` or `$PROOF_FORGE_TON_TOOLS/fiftlib`

  Not formal ToolchainIdentity / OutputSetV1. Not sandbox/mainnet deploy.
-/
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Core.Crypto

namespace ProofForgeV2.Targets.Ton.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Crypto
open ProofForgeV2.Materialization.LockedToolchainV1
open System

private def requireAbsolute (label path : String) : IO FilePath := do
  let p := FilePath.mk path
  unless p.isAbsolute do
    throw <| IO.userError
      s!"PF-TOOLCHAIN-MISMATCH: {label} must be an absolute path, got '{path}'"
  pure p

/-- Resolve a companion directory/file from explicit env or TON tools root. -/
private def resolveCompanion (explicitEnv _tonToolsKey leaf : String) :
    IO (Option FilePath) := do
  match ← IO.getEnv explicitEnv with
  | some p =>
      let path ← requireAbsolute explicitEnv p
      if ← path.pathExists then pure (some path) else pure none
  | none =>
      match ← IO.getEnv "PROOF_FORGE_TON_TOOLS" with
      | some root =>
          let base ← requireAbsolute "PROOF_FORGE_TON_TOOLS" root
          let path := base / leaf
          if ← path.pathExists then pure (some path) else pure none
      | none => pure none

/-- Run locked tolk with isolated env + TOLK_STDLIB injected (VerifiedTool.run
    only allows LC_ALL/TZ; stdlib discovery needs TOLK_STDLIB). Re-uses the
    resolved path/hash for evidence. -/
private def runTolk (tolk : VerifiedTool) (args : Array String)
    (cwd : FilePath) (stdlib : FilePath) : IO IO.Process.Output := do
  let launcher := tolk.launcher
  let envArgs : Array String := #[
    "LC_ALL=C", "TZ=UTC",
    s!"TOLK_STDLIB={stdlib}"
  ]
  IO.Process.output {
    cmd := launcher.toString
    args := #["-i"] ++ envArgs ++ #[tolk.path.toString] ++ args
    cwd := some cwd
    inheritEnv := false
  }

private def runFift (fift : FilePath) (fiftlib : FilePath) (fifPath : FilePath)
    (cwd : FilePath) : IO IO.Process.Output := do
  IO.Process.output {
    cmd := fift.toString
    args := #["-I", fiftlib.toString, "-s", fifPath.toString]
    cwd := some cwd
    inheritEnv := false
  }

private def fileSha256Hex (path : FilePath) : IO String := do
  let bytes ← IO.FS.readBinFile path
  pure (sha256Hex bytes)

/-- Exact Ton tolk(+fift) finalization: produce fif/abi/boc under stagingDir.
    Requires base `{programName}.tolk` already present. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let source := s!"{programName}.tolk"
  let sourcePath := stagingDir / source
  unless ← sourcePath.pathExists do
    throw <| IO.userError s!"PF-ARTIFACT-NONDEPLOYABLE: missing Tolk source '{source}'"
  let stdlib? ← resolveCompanion "PROOF_FORGE_TOLK_STDLIB" "tolk-stdlib" "tolk-stdlib"
  let stdlib ← match stdlib? with
    | some p => pure p
    | none =>
        throw <| IO.userError
          "PF-TOOLCHAIN-MISSING: Tolk stdlib not found (set PROOF_FORGE_TOLK_STDLIB or PROOF_FORGE_TON_TOOLS/tolk-stdlib; must be outside PROOF_FORGE_TOOL_ROOT)"
  let tolk ← resolve "tolk"
  let fifName := s!"{programName}.fif"
  let abiName := s!"{programName}.abi.json"
  let bocName := s!"{programName}.compiled.boc"
  let process ← runTolk tolk #["-o", fifName, source] stagingDir stdlib
  if process.exitCode != 0 then
    throw <| IO.userError
      s!"PF-TOOLCHAIN-MISMATCH: tolk failed\n{process.stderr}{process.stdout}"
  let fifPath := stagingDir / fifName
  unless ← fifPath.pathExists do
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: tolk returned no .fif artifact"
  let mut extras : Array String := #[fifName]
  let mut notes : Array String := #[
    s!"tolk {tolk.version} sha256={tolk.executableSha256}"
  ]
  let tolkAbi := stagingDir / abiName
  if ← tolkAbi.pathExists then
    extras := extras.push abiName
  let symbolTypes := stagingDir / s!"{programName}.symbolTypes.json"
  if ← symbolTypes.pathExists then
    extras := extras.push s!"{programName}.symbolTypes.json"
  let fift? ← resolveCompanion "PROOF_FORGE_FIFT" "fift" "fift"
  let fiftlib? ← resolveCompanion "PROOF_FORGE_FIFTLIB" "fiftlib" "fiftlib"
  let mut deployable := false
  match fift?, fiftlib? with
  | some fift, some fiftlib =>
      let fiftProc ← runFift fift fiftlib fifPath stagingDir
      if fiftProc.exitCode != 0 then
        throw <| IO.userError
          s!"PF-TOOLCHAIN-MISMATCH: fift failed to produce BoC\n{fiftProc.stderr}{fiftProc.stdout}"
      let bocPath := stagingDir / bocName
      if ← bocPath.pathExists then
        extras := extras.push bocName
        let bocHash ← fileSha256Hex bocPath
        notes := notes.push s!"boc sha256={bocHash}"
        deployable := true
      else
        let entries ← stagingDir.readDir
        let mut found := false
        for ent in entries do
          let name := ent.fileName
          if name.endsWith ".compiled.boc" then
            let dest := stagingDir / bocName
            if ent.path != dest then
              let bytes ← IO.FS.readBinFile ent.path
              IO.FS.writeBinFile dest bytes
            extras := extras.push bocName
            let bocHash ← fileSha256Hex dest
            notes := notes.push s!"boc sha256={bocHash}"
            deployable := true
            found := true
        unless found do
          throw <| IO.userError
            "PF-ARTIFACT-NONDEPLOYABLE: fift completed but no .compiled.boc was written"
  | _, _ =>
      notes := notes.push
        "fift/fiftlib companions absent (set PROOF_FORGE_FIFT + PROOF_FORGE_FIFTLIB or PROOF_FORGE_TON_TOOLS); .fif emitted without BoC (deployable=false)"
  pure {
    deployable
    extraFiles := extras
    evidenceNote :=
      (String.intercalate "; " notes.toList) ++
        "; sandbox/mainnet runtime remains separate (TON-3)"
  }

end ProofForgeV2.Targets.Ton.FinalizeV1
