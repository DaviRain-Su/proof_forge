/-
  XRPL engineering finalization adapter (ADR-0049 Q0 + ADR-0050 Q1).

  Profile branches (exhaustive):
  * `xrpl-bedrock-source-u64-v1` (default): zero tools; Bedrock-shaped Rust
    `{name}.rs` stays materialized base only. `deployable=false`; no
    rustc/wasm-opt/bedrock/rippled/ContractCreate/ContractCall/AlphaNet/mainnet
    evidence.
  * `xrpl-bedrock-wasm-u64-v1`: resolve ambient rustc/cargo, wrap the staged
    `{name}.rs` in a temp cdylib crate pinned to craft
    `ffbe88da26df27e59a72b6202883f42f696933cc`, run
    `cargo build --target wasm32-unknown-unknown --release`, and stage the
    produced `.wasm` as extra `xrpl-build/{program}.wasm`. Missing rustc/cargo
    or the wasm target fails closed (`PF-TOOLCHAIN-MISSING`). Still
    `deployable=false`; no bedrock / ContractCreate / AlphaNet / mainnet.
  * unknown profile: fail closed.

  Ambient (not `LockedToolchainV1.resolve`): rustc/cargo come from the caller's
  rustup. There is no content-addressed rustc Tool Lock member. This mirrors
  OpenVM's ambient `cargo`/`rustup` prerequisite for `cargo-openvm`.

  Separate from pure `Targets.Xrpl` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1 / hermetic finalization.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.Xrpl.FinalizeV1

open ProofForgeV2
open System

/-- Frozen craft commit that publishes `xrpl-wasm-std` (ADR-0050). -/
def xrplWasmStdGitRevV1 : String :=
  "ffbe88da26df27e59a72b6202883f42f696933cc"

def xrplWasmStdGitUrlV1 : String :=
  "https://github.com/Transia-RnD/craft.git"

def xrplWasmTargetTripleV1 : String :=
  "wasm32-unknown-unknown"

private def sourceProfileNote : String :=
  "no rustc, wasm-opt, bedrock, rippled, ContractCreate, ContractCall, AlphaNet, or mainnet was invoked; emitted XRPL Bedrock Rust source carries no compile, test, deploy, or settlement evidence"

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

/-- Resolve ambient `cargo` binary path. Returns `none` when absent (callers
    must fail closed with `PF-TOOLCHAIN-MISSING`; never invent a backend). -/
def resolveCargoPathV1 : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #[]
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    absCandidates := absCandidates.push (root ++ "/cargo")
  if let some h := home then
    absCandidates := absCandidates.push (h ++ "/.cargo/bin/cargo")
  for c in absCandidates do
    if ← (FilePath.mk c).pathExists then
      return some c
  let which ← IO.Process.output { cmd := "which", args := #["cargo"] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

/-- Resolve ambient `rustc` binary path (presence probe only). -/
def resolveRustcPathV1 : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #[]
  if let some h := home then
    absCandidates := absCandidates.push (h ++ "/.cargo/bin/rustc")
  for c in absCandidates do
    if ← (FilePath.mk c).pathExists then
      return some c
  let which ← IO.Process.output { cmd := "which", args := #["rustc"] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

private def wasmExtraRelPathV1 (programName : String) : String :=
  s!"xrpl-build/{programName}.wasm"

private def cratePackageNameV1 (programName : String) : String :=
  s!"pf-xrpl-{programName}"

private def renderCargoTomlV1 (packageName : String) : String :=
  "[package]\n" ++
  s!"name = \"{packageName}\"\n" ++
  "version = \"0.1.0\"\n" ++
  "edition = \"2021\"\n" ++
  "\n" ++
  "[lib]\n" ++
  "crate-type = [\"cdylib\"]\n" ++
  "\n" ++
  "[dependencies]\n" ++
  "xrpl-wasm-std = { git = \"" ++ xrplWasmStdGitUrlV1 ++
    "\", rev = \"" ++ xrplWasmStdGitRevV1 ++
    "\", package = \"xrpl-wasm-std\" }\n" ++
  "\n" ++
  "[profile.release]\n" ++
  "opt-level = \"z\"\n" ++
  "lto = true\n" ++
  "strip = true\n" ++
  "panic = \"abort\"\n"

private def finalizeWasmProfile
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := CodegenProfileId.xrplBedrockWasmU64V1
  unless ResolvedEngineeringBuildV1.codegenProfileOf capability == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: XRPL wasm finalize capability profile mismatch"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: XRPL wasm finalize artifact profile mismatch"
  unless ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.xrpl &&
      ResolvedEngineeringBuildV1.kindOf capability == .xrpl do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: XRPL wasm finalize capability target mismatch"
  unless MaterializedArtifactsV1.targetIdOf artifacts == TargetId.xrpl &&
      MaterializedArtifactsV1.kindOf artifacts == .xrpl do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: XRPL wasm finalize artifact target mismatch"

  let files := MaterializedArtifactsV1.filesOf artifacts
  for f in files do
    requireExactStagingBase stagingDir f

  let cargo? ← resolveCargoPathV1
  let rustc? ← resolveRustcPathV1
  let cargo ← match cargo?, rustc? with
    | some path, some _ => pure path
    | _, _ =>
        throw <| IO.userError
          ("PF-TOOLCHAIN-MISSING: xrpl-bedrock-wasm-u64-v1 requires ambient " ++
            "rustc/cargo with wasm32-unknown-unknown (ADR-0050 Q1 host-dependent " ++
            "compile; not a Tool Lock rustc pin)")

  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let rsRel := s!"{programName}.rs"
  let rsBytes ←
    requireRegularNonemptyFile s!"staging {rsRel}" (stagingDir / rsRel)
  let packageName := cratePackageNameV1 programName
  let tomlText := renderCargoTomlV1 packageName

  -- Build outside product staging so cargo's `target/` never pollutes the
  -- exact disk-closure inventory; same discipline as OpenVM/Noir.
  IO.FS.withTempDir fun tempRoot => do
    let workDir := tempRoot / "crate"
    IO.FS.createDirAll (workDir / "src")
    IO.FS.writeFile (workDir / "Cargo.toml") tomlText
    IO.FS.writeBinFile (workDir / "src" / "lib.rs") rsBytes

    let runCargo (offline : Bool) : IO (UInt32 × String × String) := do
      let mut args : Array String :=
        #["build", "--target", xrplWasmTargetTripleV1, "--release",
          "--manifest-path", "crate/Cargo.toml"]
      if offline then
        args := args.push "--offline"
      let process ← IO.Process.output {
        cmd := cargo
        args
        cwd := some tempRoot
      }
      pure (process.exitCode, process.stdout, process.stderr)

    let (code0, out0, err0) ← runCargo (offline := true)
    let (code, out, err) ←
      if code0 == 0 then
        pure (code0, out0, err0)
      else
        -- First miss is usually an absent cargo git checkout of the pinned
        -- rev. A single non-offline retry is allowed; the rev stays frozen.
        runCargo (offline := false)
    unless code == 0 do
      let combined := out ++ err
      if combined.contains "wasm32-unknown-unknown" ||
          combined.contains "may not be installed" then
        throw <| IO.userError
          ("PF-TOOLCHAIN-MISSING: xrpl-bedrock-wasm-u64-v1 requires the " ++
            "wasm32-unknown-unknown rustc target (ADR-0050 Q1)")
      throw <| IO.userError
        (s!"cargo wasm32-unknown-unknown build failed in {workDir}\n" ++
          out ++ err)

    let wasmPath :=
      workDir / "target" / xrplWasmTargetTripleV1 / "release" /
        (packageName ++ ".wasm")
    let wasmBytes ← requireRegularNonemptyFile "XRPL WASM" wasmPath
    let wasmRel := wasmExtraRelPathV1 programName
    IO.FS.createDirAll (stagingDir / "xrpl-build")
    IO.FS.writeBinFile (stagingDir / wasmRel) wasmBytes

    pure {
      deployable := false
      extraFiles := #[wasmRel]
      evidenceNote :=
        ("ambient cargo built wasm32-unknown-unknown bytecode; " ++
          s!"cargo={cargo}; package={packageName}; " ++
          s!"xrpl-wasm-std rev={xrplWasmStdGitRevV1}; " ++
          "no bedrock, rippled, ContractCreate, ContractCall, AlphaNet, or mainnet was invoked")
    }

private def finalizeUnknownProfile
    (profile : CodegenProfileId) : IO EngineeringFinalizationDraftV1 :=
  throw <| IO.userError
    s!"PF-ARTIFACT-NONDEPLOYABLE: unknown XRPL codegen profile '{profile}'"

/-- XRPL finalization is profile-exhaustive: the default stays zero-tool
    while the explicit wasm profile compiles `.wasm` extras (ADR-0050 Q1). -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.xrplBedrockSourceU64V1 then
    finalizeSourceProfile
  else if profile == CodegenProfileId.xrplBedrockWasmU64V1 then
    finalizeWasmProfile capability artifacts stagingDir
  else
    finalizeUnknownProfile profile

end ProofForgeV2.Targets.Xrpl.FinalizeV1
