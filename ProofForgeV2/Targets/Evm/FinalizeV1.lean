/-
  EVM engineering finalization adapter (D3/S7b).

  Exact locked-solc path formerly in CLI.Emit.finalizeEvm:
  resolve `solc`, run profile-selected args, parse
  `Binary representation:\n`, write `{name}.bin` + `\n`.

  Profile selection (capability-bound, no ambient fallback):
  - `evm-yul-solc-0.8.34-v1` (default, hashed Map storage):
      `#['--strict-assembly','--optimize','--bin', source]`;
      evidence note ` map-storage=hashed`
  - `evm-yul-solc-0.8.34-cancun-v1`: adds `--evm-version cancun` before `--bin`
    (same hashed Map storage; hardfork pin only)
    All EVM profiles enable solc's Yul optimizer (same pipeline Solidity uses for
    `--optimize` on IR). Source Yul stays unoptimized for readability/debug.

  Same locked solc 0.8.34 binary for all EVM profiles. PATH is never consulted.
  Separate from pure `Targets.Evm` Plan/IR core (no tool runner in Evm.lean).
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Core.TargetIdentityV1
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

/-- Pure solc argv for a known EVM codegen profile.
    Explicit branches only: all EVM profiles always pass `--optimize`;
    Cancun additionally pins `--evm-version cancun`. Unknown profiles fail
    closed (defense in depth; capability selection should already reject them). -/
def solcArgsForProfile (profile : CodegenProfileId) (source : String) :
    Except String (Array String) :=
  if profile == CodegenProfileId.evmYulSolc0834CancunV1 then
    pure #["--strict-assembly", "--optimize", "--evm-version", "cancun",
      "--bin", source]
  else if profile == CodegenProfileId.evmYulSolc0834V1 then
    pure #["--strict-assembly", "--optimize", "--bin", source]
  else
    throw s!"unsupported EVM finalize profile '{profile}'"

/-- Pure evidence-note fragment for a known EVM profile's hardfork pin. -/
def evidenceHardforkNote (profile : CodegenProfileId) : Except String String :=
  if profile == CodegenProfileId.evmYulSolc0834CancunV1 then
    pure " evm-version=cancun map-storage=hashed"
  else if profile == CodegenProfileId.evmYulSolc0834V1 then
    pure " map-storage=hashed"
  else
    throw s!"unsupported EVM finalize profile '{profile}'"

/-- Exact EVM solc finalization: write `{programName}.bin` under stagingDir.
    Requires base `{programName}.yul` already present (CLI publisher writes base
    files first). Args and evidence note are selected from capability profile. -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let source := s!"{programName}.yul"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  let args ← match solcArgsForProfile profile source with
    | .ok value => pure value
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}"
  let hardforkNote ← match evidenceHardforkNote profile with
    | .ok value => pure value
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}"
  let solc ← resolve "solc"
  let process ← solc.run args (some stagingDir)
  if process.exitCode == 0 then
    let binary := (process.stdout.splitOn "Binary representation:\n").getLast!.trimAscii.copy
    requireNonemptySolcBytecode binary
    IO.FS.writeFile (stagingDir / s!"{programName}.bin") (binary ++ "\n")
    pure {
      deployable := true
      extraFiles := #[s!"{programName}.bin"]
      evidenceNote :=
        s!"solc {solc.version} sha256={solc.executableSha256} completed successfully{hardforkNote}"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: solc failed\n{process.stderr}"

end ProofForgeV2.Targets.Evm.FinalizeV1
