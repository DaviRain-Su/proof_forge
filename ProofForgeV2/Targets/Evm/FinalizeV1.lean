/-
  EVM engineering finalization adapter (D3/S7b).

  Exact locked-solc path formerly in CLI.Emit.finalizeEvm:
  resolve `solc`, run `#['--strict-assembly','--bin', source]`, parse
  `Binary representation:\n`, write `{name}.bin` + `\n`, notes/errors unchanged.

  Separate from pure `Targets.Evm` Plan/IR core (no tool runner in Evm.lean).
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1

namespace ProofForgeV2.Targets.Evm.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Materialization.LockedToolchainV1
open System

/-- Pure post-solc bytecode presence gate (exact historical wire).
    Package-visible for hermetic non-deployable negatives without tool stubs. -/
def requireNonemptySolcBytecode (binary : String) : IO Unit := do
  if binary.isEmpty then
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: solc returned no bytecode"

/-- Exact EVM solc finalization: write `{programName}.bin` under stagingDir.
    Requires base `{programName}.yul` already present (CLI publisher writes base
    files first). Preserves tool args, stdout parser, notes, and error ordering. -/
def finalize
    (_capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let source := s!"{programName}.yul"
  let solc ← resolve "solc"
  let process ← solc.run #["--strict-assembly", "--bin", source] (some stagingDir)
  if process.exitCode == 0 then
    let binary := (process.stdout.splitOn "Binary representation:\n").getLast!.trimAscii.copy
    requireNonemptySolcBytecode binary
    IO.FS.writeFile (stagingDir / s!"{programName}.bin") (binary ++ "\n")
    pure {
      deployable := true
      extraFiles := #[s!"{programName}.bin"]
      evidenceNote := s!"solc {solc.version} sha256={solc.executableSha256} completed successfully"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: solc failed\n{process.stderr}"

end ProofForgeV2.Targets.Evm.FinalizeV1
