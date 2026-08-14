/-
  OpenVM engineering finalization adapter (ADR-0045 O0 + ADR-0046 O1).

  Profile branches (exhaustive):
  * `openvm-guest-source-v1` (default): zero tools; guest Rust source +
    catalog JSON stay materialized base only. `deployable=false`; no
    build/transpile/keygen/execute/prove/verify evidence.
  * `openvm-guest-elf-v1`: resolve locked/ambient `cargo-openvm` 2.0.1, copy
    the staged guest tree into a temp dir, run `cargo openvm build
    --manifest-path guest/Cargo.toml`, and stage the produced RV32IM ELF +
    `.vmexe` as extras (`openvm-build/{program}` /
    `openvm-build/{program}.vmexe`). Missing cargo-openvm fails closed
    (`PF-TOOLCHAIN-MISSING`). Still `deployable=false`; no keygen, execute,
    or prove/verify.
  * unknown profile: fail closed.

  Ambient (not `LockedToolchainV1.resolve`): `cargo-openvm` itself shells out
  to `cargo`/`rustup` for the RV32IM cross-compile, so it needs the caller's
  PATH/HOME/CARGO_HOME/RUSTUP_HOME — the isolated Tool Lock runner's
  `env -i` launcher would strip exactly that. This mirrors Noir's
  `resolveNargoPathV1` + plain `IO.Process.output` (ambient env) precedent.

  Separate from pure `Targets.OpenVM` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1 / hermetic finalization.
-/
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Core.TargetIdentityV1

namespace ProofForgeV2.Targets.OpenVM.FinalizeV1

open ProofForgeV2
open System

private def sourceProfileNote : String :=
  "no cargo, openvm-transpiler, keygen, guest build, execute, or prove/verify toolchain was invoked; emitted guest source carries no build, transpile, keygen, execute, prove, or verify evidence"

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

/-- Resolve locked / ambient `cargo-openvm` binary path. Returns `none` when
    absent (callers must fail closed with `PF-TOOLCHAIN-MISSING`; never
    invent a backend). Same shape as Noir's `resolveNargoPathV1`. -/
def resolveCargoOpenvmPathV1 : IO (Option String) := do
  let home ← IO.getEnv "HOME"
  let mut absCandidates : Array String := #[]
  if let some root ← IO.getEnv "PROOF_FORGE_TOOL_ROOT" then
    absCandidates := absCandidates.push (root ++ "/cargo-openvm")
  if let some h := home then
    absCandidates :=
      absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/darwin-arm64/cargo-openvm")
    absCandidates :=
      absCandidates.push (h ++ "/.cache/proof-forge-v2/tool-root/linux-x86_64/cargo-openvm")
    absCandidates := absCandidates.push (h ++ "/.cargo/bin/cargo-openvm")
  for c in absCandidates do
    if ← (FilePath.mk c).pathExists then
      return some c
  let which ← IO.Process.output { cmd := "which", args := #["cargo-openvm"] }
  if which.exitCode == 0 then
    let path := which.stdout.trimAscii.copy
    if !path.isEmpty && (← (FilePath.mk path).pathExists) then
      return some path
  return none

/-- Extract `[package] name = "…"` from the staged guest `Cargo.toml` text
    (default cargo bin-target name for a package with only `src/main.rs`). -/
private def extractCargoPackageNameV1 (toml : String) : Option String :=
  let needle := "name = \""
  match toml.splitOn needle with
  | [_, rest] =>
      match rest.splitOn "\"" with
      | name :: _ => if name.isEmpty then none else some name
      | [] => none
  | _ => none

private def elfExtraRelPathV1 (programName : String) : String :=
  s!"openvm-build/{programName}"

private def vmexeExtraRelPathV1 (programName : String) : String :=
  s!"openvm-build/{programName}.vmexe"

private def finalizeElfProfile
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := CodegenProfileId.openvmGuestElfV1
  unless ResolvedEngineeringBuildV1.codegenProfileOf capability == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: OpenVM elf finalize capability profile mismatch"
  unless MaterializedArtifactsV1.codegenProfileIdOf artifacts == profile do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: OpenVM elf finalize artifact profile mismatch"
  unless ResolvedEngineeringBuildV1.targetIdOf capability == TargetId.openvm &&
      ResolvedEngineeringBuildV1.kindOf capability == .openvm do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: OpenVM elf finalize capability target mismatch"
  unless MaterializedArtifactsV1.targetIdOf artifacts == TargetId.openvm &&
      MaterializedArtifactsV1.kindOf artifacts == .openvm do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: OpenVM elf finalize artifact target mismatch"

  let files := MaterializedArtifactsV1.filesOf artifacts
  for f in files do
    requireExactStagingBase stagingDir f

  let cargoOpenvm? ← resolveCargoOpenvmPathV1
  let cargoOpenvm ← match cargoOpenvm? with
    | some path => pure path
    | none =>
        throw <| IO.userError
          ("PF-TOOLCHAIN-MISSING: openvm-guest-elf-v1 requires locked/ambient " ++
            "cargo-openvm 2.0.1 (ADR-0046 O1 host-dependent build/transpile)")

  let tomlBytes ←
    requireRegularNonemptyFile "guest/Cargo.toml" (stagingDir / "guest" / "Cargo.toml")
  let toml ← match String.fromUTF8? tomlBytes with
    | some text => pure text
    | none =>
        throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: guest/Cargo.toml is not UTF-8"
  let packageName ← match extractCargoPackageNameV1 toml with
    | some name => pure name
    | none =>
        throw <| IO.userError
          "PF-ARTIFACT-NONDEPLOYABLE: cannot parse package name in guest/Cargo.toml"
  let openvmTomlBytes ←
    requireRegularNonemptyFile "guest/openvm.toml" (stagingDir / "guest" / "openvm.toml")
  let mainRsBytes ←
    requireRegularNonemptyFile "guest/src/main.rs" (stagingDir / "guest" / "src" / "main.rs")

  -- Build outside product staging so cargo's `target/` never pollutes the
  -- exact disk-closure inventory (publisher rejects unexpected directories);
  -- same discipline as Noir's nargo-assisted capture.
  IO.FS.withTempDir fun tempRoot => do
    let workDir := tempRoot / "guest"
    IO.FS.createDirAll (workDir / "src")
    IO.FS.writeBinFile (workDir / "Cargo.toml") tomlBytes
    IO.FS.writeBinFile (workDir / "openvm.toml") openvmTomlBytes
    IO.FS.writeBinFile (workDir / "src" / "main.rs") mainRsBytes

    let process ← IO.Process.output {
      cmd := cargoOpenvm
      args := #["openvm", "build", "--manifest-path", "guest/Cargo.toml"]
      cwd := some tempRoot
    }
    unless process.exitCode == 0 do
      throw <| IO.userError
        (s!"cargo-openvm build failed in {workDir}\n" ++ process.stdout ++ process.stderr)

    -- Fixed OpenVM CLI output layout (relative to the manifest directory,
    -- confirmed against actual `cargo openvm build` output; the transpiled
    -- `.vmexe` lands under manifest-relative `openvm/release/`, *not*
    -- `target/openvm/release/`): RV32IM ELF at
    -- target/riscv32im-risc0-zkvm-elf/release/{bin}; transpiled .vmexe at
    -- openvm/release/{bin}.vmexe.
    let elfPath := workDir / "target" / "riscv32im-risc0-zkvm-elf" / "release" / packageName
    let vmexePath := workDir / "openvm" / "release" / (packageName ++ ".vmexe")
    let elfBytes ← requireRegularNonemptyFile "OpenVM RV32IM ELF" elfPath
    let vmexeBytes ← requireRegularNonemptyFile "OpenVM .vmexe" vmexePath

    let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
    let elfRel := elfExtraRelPathV1 programName
    let vmexeRel := vmexeExtraRelPathV1 programName
    IO.FS.createDirAll (stagingDir / "openvm-build")
    IO.FS.writeBinFile (stagingDir / elfRel) elfBytes
    IO.FS.writeBinFile (stagingDir / vmexeRel) vmexeBytes

    pure {
      deployable := false
      extraFiles := #[elfRel, vmexeRel]
      evidenceNote :=
        ("cargo-openvm built and transpiled the guest into a RV32IM ELF and " ++
          s!".vmexe; cargoOpenvm={cargoOpenvm}; package={packageName}; " ++
          "no keygen, execute, or prove/verify toolchain was invoked")
    }

private def finalizeUnknownProfile
    (profile : CodegenProfileId) : IO EngineeringFinalizationDraftV1 :=
  throw <| IO.userError
    s!"PF-ARTIFACT-NONDEPLOYABLE: unknown OpenVM codegen profile '{profile}'"

/-- OpenVM finalization is profile-exhaustive: the default stays zero-tool
    while the explicit elf profile builds+transpiles ELF/VmExe extras
    (ADR-0046 O1). -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.openvmGuestSourceV1 then
    finalizeSourceProfile
  else if profile == CodegenProfileId.openvmGuestElfV1 then
    finalizeElfProfile capability artifacts stagingDir
  else
    finalizeUnknownProfile profile

end ProofForgeV2.Targets.OpenVM.FinalizeV1
