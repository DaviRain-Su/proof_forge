/-
  EVM engineering finalization adapter (D3/S7b).

  Exact locked-solc path formerly in CLI.Emit.finalizeEvm:
  resolve `solc`, run profile-selected standard JSON, parse creation and
  deployed bytecode, write `{name}.bin` + `{name}.runtime.bin`.

  Profile selection (capability-bound, no ambient fallback):
  - `evm-yul-solc-0.8.34-v1` (default, hashed Map storage):
      standard JSON language=Yul, optimizer.enabled=true;
      evidence note ` map-storage=hashed`
  - `evm-yul-solc-0.8.34-cancun-v1`: adds settings.evmVersion=cancun
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
import Lean.Data.Json.Parser

namespace ProofForgeV2.Targets.Evm.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Materialization.LockedToolchainV1
open Lean
open System

/-- Pure post-solc bytecode presence gate (exact historical wire).
    Package-visible for hermetic non-deployable negatives without tool stubs. -/
def requireNonemptySolcBytecode (binary : String) : IO Unit := do
  if binary.isEmpty then
    throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: solc returned no bytecode"

/-- Pure solc argv for a known EVM codegen profile. Standard JSON is required
    because assembler mode rejects `--bin-runtime`. Profile semantics live in
    the request body, not ambient argv. -/
def solcArgsForProfile (profile : CodegenProfileId) (requestPath : String) :
    Except String (Array String) :=
  if profile == CodegenProfileId.evmYulSolc0834CancunV1 ||
      profile == CodegenProfileId.evmYulSolc0834V1 then
    pure #["--standard-json", requestPath]
  else
    throw s!"unsupported EVM finalize profile '{profile}'"

/-- Explicit EVM-version setting for standard JSON. The legacy profile omits
    the field and therefore retains solc 0.8.34's locked default. -/
def standardJsonEvmVersionForProfile (profile : CodegenProfileId) :
    Except String (Option String) :=
  if profile == CodegenProfileId.evmYulSolc0834CancunV1 then
    pure (some "cancun")
  else if profile == CodegenProfileId.evmYulSolc0834V1 then
    pure none
  else
    throw s!"unsupported EVM finalize profile '{profile}'"

/-- Deterministic solc standard-JSON request. Both bytecode forms come from one
    locked invocation and one exact Yul input. -/
def renderSolcStandardJsonInputV1
    (profile : CodegenProfileId) (sourcePath yul : String) :
    Except String String := do
  let evmVersion ← standardJsonEvmVersionForProfile profile
  let mut settings : List (String × Json) := [
    ("optimizer", Json.mkObj [("enabled", .bool true)]),
    ("outputSelection", Json.mkObj [
      ("*", Json.mkObj [
        ("*", .arr #[.str "evm.bytecode.object", .str "evm.deployedBytecode.object"])
      ])
    ])
  ]
  match evmVersion with
  | some version => settings := ("evmVersion", .str version) :: settings
  | none => pure ()
  pure <| (Json.mkObj [
    ("language", .str "Yul"),
    ("sources", Json.mkObj [(sourcePath, Json.mkObj [("content", .str yul)])]),
    ("settings", Json.mkObj settings)
  ]).compress

private def requireJsonFieldV1 (value : Json) (key context : String) :
    Except String Json :=
  match value.getObjVal? key with
  | .ok field => pure field
  | .error _ => throw s!"solc standard JSON missing {context}.{key}"

private def requireJsonStringV1 (value : Json) (context : String) :
    Except String String :=
  match value with
  | .str text => pure text
  | _ => throw s!"solc standard JSON {context} must be a string"

/-- Parse the exact nested standard-JSON bytecode pair. Missing contracts or
    compiler errors fail through the same output-shape gate. -/
def parseSolcStandardJsonBytecodesV1
    (text sourcePath objectName : String) : Except String (String × String) := do
  let root ← match Json.parse text with
    | .ok value => pure value
    | .error error => throw s!"solc standard JSON output is invalid: {error}"
  let contracts ← requireJsonFieldV1 root "contracts" "root"
  let source ← requireJsonFieldV1 contracts sourcePath "contracts"
  let contract ← requireJsonFieldV1 source objectName s!"contracts.{sourcePath}"
  let evm ← requireJsonFieldV1 contract "evm" s!"contracts.{sourcePath}.{objectName}"
  let bytecode ← requireJsonFieldV1 evm "bytecode" "evm"
  let deployed ← requireJsonFieldV1 evm "deployedBytecode" "evm"
  let creation ← requireJsonStringV1
    (← requireJsonFieldV1 bytecode "object" "evm.bytecode") "evm.bytecode.object"
  let runtime ← requireJsonStringV1
    (← requireJsonFieldV1 deployed "object" "evm.deployedBytecode")
    "evm.deployedBytecode.object"
  pure (creation, runtime)

/-- Pure evidence-note fragment for a known EVM profile's hardfork pin. -/
def evidenceHardforkNote (profile : CodegenProfileId) : Except String String :=
  if profile == CodegenProfileId.evmYulSolc0834CancunV1 then
    pure " evm-version=cancun map-storage=hashed"
  else if profile == CodegenProfileId.evmYulSolc0834V1 then
    pure " map-storage=hashed"
  else
    throw s!"unsupported EVM finalize profile '{profile}'"

/-- Exact EVM solc finalization: write `{programName}.bin` and
    `{programName}.runtime.bin` under stagingDir.
    Requires base `{programName}.yul` already present (CLI publisher writes base
    files first). One standard-JSON invocation binds both bytecode forms to the
    same exact Yul and profile. -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let source := s!"{programName}.yul"
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  let yul ← IO.FS.readFile (stagingDir / source)
  let requestName := s!".{programName}.solc-standard-input.json"
  let request ← match renderSolcStandardJsonInputV1 profile source yul with
    | .ok value => pure value
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}"
  IO.FS.writeFile (stagingDir / requestName) request
  let args ← match solcArgsForProfile profile requestName with
    | .ok value => pure value
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}"
  let hardforkNote ← match evidenceHardforkNote profile with
    | .ok value => pure value
    | .error message =>
        throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}"
  let solc ← resolve "solc"
  let process ← solc.run args (some stagingDir)
  IO.FS.removeFile (stagingDir / requestName)
  if process.exitCode == 0 then
    let (creation, runtime) ← match
        parseSolcStandardJsonBytecodesV1 process.stdout source programName with
      | .ok value => pure value
      | .error message =>
          throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: {message}\n{process.stdout}"
    requireNonemptySolcBytecode creation
    requireNonemptySolcBytecode runtime
    IO.FS.writeFile (stagingDir / s!"{programName}.bin") (creation ++ "\n")
    IO.FS.writeFile (stagingDir / s!"{programName}.runtime.bin") (runtime ++ "\n")
    pure {
      deployable := true
      extraFiles := #[s!"{programName}.bin", s!"{programName}.runtime.bin"]
      evidenceNote :=
        s!"solc {solc.version} sha256={solc.executableSha256} completed successfully; creation+runtime bytecode emitted{hardforkNote}"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: solc failed\n{process.stderr}"

end ProofForgeV2.Targets.Evm.FinalizeV1
