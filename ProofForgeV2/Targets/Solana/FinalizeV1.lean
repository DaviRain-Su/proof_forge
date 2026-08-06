/-
  Solana engineering finalization adapter (D3/S7b / S2a / #125).

  Profile branches (exhaustive):
  * `solana-sbpf-plan-v1` (default): zero tools; non-deployable plan/IDL note.
  * `solana-sbpf-elf-v1`: resolve locked `sbpf`, assemble staging `{name}.s`
    via a temporary `src/<name>/<name>.s` project, copy `{name}.so` into
    staging as an extra. Tool lock registration is S2b; missing `sbpf`
    fails closed with `PF-TOOLCHAIN-MISSING`.
  * `solana-sbpf-cpi-elf-v1` (#125): before any tool IO, re-verify capability
    and artifacts bind exact CPI profile; recompute product Plan/IR digests
    and join staging base `.cpi-plan.json` / `.cpi-ir.json` / `.idl.json` /
    `.cpi-bindings.json` / `.s` contents plus BuildIdentity planDigest
    against product-core recomputation; then locked `sbpf` assemble.
    evidenceNote carries exact active profile / catalog / Plan / IR / tool
    digests. Never reads or copies arbitrary environment ELF — callee pins
    already live in bindings/catalog product base files.
  * unknown profile → fail closed.

  Separate from pure `Targets.Solana` Plan/IR core.
  Not formal ToolchainIdentity / OutputSetV1.
-/
import ProofForgeV2.Materialization.LockedToolchainV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Targets.EngineeringBuildV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Core.TargetIdentityV1
import ProofForgeV2.Core.Common
import ProofForgeV2.Targets.Solana.MaterializationV1
import ProofForgeV2.Targets.Solana.CpiContractV1
import ProofForgeV2.Targets.Solana.CpiPlanV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.CpiProductCapabilityV1
import ProofForgeV2.Targets.Solana.CpiProductV1
import ProofForgeV2.Targets.Solana.EmitSbpfAsmV1

namespace ProofForgeV2.Targets.Solana.FinalizeV1

open ProofForgeV2
open ProofForgeV2.Materialization.LockedToolchainV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1
open ProofForgeV2.Targets.Solana
open ProofForgeV2.Targets.Solana.CpiV1
open ProofForgeV2.Core.Common
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

/-- Shared locked-sbpf assemble of staging `{name}.s` → stage `{name}.so`.
    Returns (toolVersion, executableSha256). -/
private def assembleStagingSbpfV1
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath)
    (profileLabel : String) : IO (String × String) := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let stagingAsm := stagingDir / s!"{programName}.s"
  unless ← stagingAsm.pathExists do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: missing staging assembly '{programName}.s' for {profileLabel}"
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
    pure (sbpf.version, sbpf.executableSha256)

/-- ELF-profile finalization: locked `sbpf build` over a temp project that
    mirrors `src/<name>/<name>.s`, then stage `{name}.so` as an extra. -/
private def finalizeElfProfile
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let (version, sha) ← assembleStagingSbpfV1 artifacts stagingDir "solana-sbpf-elf-v1"
  pure {
    deployable := true
    extraFiles := #[s!"{programName}.so"]
    evidenceNote :=
      s!"sbpf {version} sha256={sha} completed successfully"
  }

private def digestsEqual (left right : Digest) : Bool :=
  left.algorithm == right.algorithm && left.bytes == right.bytes

private def digestWireIO (d : Digest) : IO String :=
  match renderDigest d with
  | .ok s => pure s
  | .error e => throw <| IO.userError s!"PF-ARTIFACT-NONDEPLOYABLE: digest render: {e}"

/-- Join one staging base file against recomputed product OutputFile contents. -/
private def joinStagingBaseFile
    (stagingDir : FilePath) (file : OutputFile) : IO Unit := do
  let path := stagingDir / file.path
  unless ← path.pathExists do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: missing staging product base '{file.path}'"
  let disk ← IO.FS.readFile path
  unless disk == file.contents do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: staging product base '{file.path}' diverges from recomputed product bytes"

/-- #125 CPI finalization: capability/profile recheck → product Plan/IR recompute
    → staging base join + planDigest join → locked sbpf → evidence digests.
    Never loads env ELF; callee pins are already in bindings/catalog bases. -/
private def finalizeCpiElfProfile
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  -- 1. Pre-IO identity: capability and artifacts must bind exact CPI profile.
  let capProfile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  unless capProfile == CodegenProfileId.solanaSbpfCpiElfV1 do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: CPI finalize requires profile solana-sbpf-cpi-elf-v1, got '{capProfile}'"
  let artProfile := MaterializedArtifactsV1.codegenProfileIdOf artifacts
  unless artProfile == CodegenProfileId.solanaSbpfCpiElfV1 do
    throw <| IO.userError
      s!"PF-ARTIFACT-NONDEPLOYABLE: artifacts profile is not solana-sbpf-cpi-elf-v1 ('{artProfile}')"
  unless MaterializedArtifactsV1.targetIdOf artifacts == TargetId.solana do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: CPI finalize artifacts target is not solana"
  unless ResolvedEngineeringBuildV1.kindOf capability == .solana do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: CPI finalize capability kind is not solana"
  -- Product capability refine (sync+extension exact; no preflight conversion).
  match resolveSolanaCpiProductCapabilityV1 capability with
  | .ok _ => pure ()
  | .error e =>
      throw <| IO.userError
        s!"PF-ARTIFACT-NONDEPLOYABLE: CPI product capability refine failed: {e.render}"

  -- 2. Recompute product Plan digest (always) and base files via sole
  -- materialize entry `buildFromCapability` (ADR-0032: includes full-body hybrid).
  let productPlan ← match productPlanFromCapabilityV1 capability with
    | .ok p => pure p
    | .error e =>
        throw <| IO.userError
          s!"PF-ARTIFACT-NONDEPLOYABLE: CPI product Plan recompute failed: {e.render}"
  let productDigest ← match productPlanDigestFromCapabilityV1 capability with
    | .ok d => pure d
    | .error e =>
        throw <| IO.userError
          s!"PF-ARTIFACT-NONDEPLOYABLE: CPI product plan digest recompute failed: {e.render}"
  let planDigest := SolanaCpiProductPlanV1.digestOf productPlan
  unless digestsEqual productDigest planDigest do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: product plan digest diverges from Plan carrier digest"

  -- Product IR: ordinary escrow path when available; full-body hybrid skips
  -- escrow IR (multi-block/Map) and records hybrid marker in evidence.
  let productIrResult := productIrFromCapabilityV1 capability
  let irDigestNote : String ←
    match productIrResult with
    | .ok productIr => do
        let irDigest := ResolvedSolanaCpiProductIRV1.digestOf productIr
        let irCand := ResolvedSolanaCpiProductIRV1.candidateOf productIr
        unless digestsEqual irCand.sourcePlanDigest planDigest do
          throw <| IO.userError
            "PF-ARTIFACT-NONDEPLOYABLE: product IR sourcePlanDigest diverges from Plan digest"
        digestWireIO irDigest
    | .error _ =>
        pure "full-body-hybrid"

  -- 3. Join BuildIdentity planDigest (bound at materialize) to product digest.
  let identity := MaterializedArtifactsV1.buildIdentityOf artifacts
  unless digestsEqual (EngineeringBuildIdentityV1.planDigestOf identity) productDigest do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: BuildIdentity planDigest diverges from recomputed CPI Plan digest"
  unless EngineeringBuildIdentityV1.codegenProfileOf identity ==
      CodegenProfileId.solanaSbpfCpiElfV1 do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: BuildIdentity profile is not solana-sbpf-cpi-elf-v1"

  -- 4. Join staging base files against recomputed materialize base set
  -- (same authority as publisher: buildFromCapability, hybrid-aware).
  let baseFiles ← match buildFromCapability capability with
    | .ok files => pure files
    | .error e =>
        throw <| IO.userError
          s!"PF-ARTIFACT-NONDEPLOYABLE: CPI product base files recompute failed: {e.render}"
  let matFiles := MaterializedArtifactsV1.filesOf artifacts
  unless matFiles.map (·.path) == baseFiles.map (·.path) do
    throw <| IO.userError
      "PF-ARTIFACT-NONDEPLOYABLE: materialized file paths diverge from recomputed product base paths"
  for file in baseFiles do
    joinStagingBaseFile stagingDir file
    -- Also join against materialized in-memory contents (publisher wrote them).
    let some mat := matFiles.find? (·.path == file.path) |
      throw <| IO.userError
        s!"PF-ARTIFACT-NONDEPLOYABLE: materialized set missing '{file.path}'"
    unless mat.contents == file.contents do
      throw <| IO.userError
        s!"PF-ARTIFACT-NONDEPLOYABLE: materialized '{file.path}' diverges from recomputed product bytes"

  -- 5. Locked sbpf assemble only after exact joins.
  let programName := MaterializedArtifactsV1.artifactProgramNameOf artifacts
  let (version, toolSha) ←
    assembleStagingSbpfV1 artifacts stagingDir "solana-sbpf-cpi-elf-v1"

  -- 6. evidenceNote: exact active profile/catalog/Plan/IR/tool digests.
  let planWire ← digestWireIO planDigest
  let cand := SolanaCpiProductPlanV1.candidateOf productPlan
  let candProfileWire ← digestWireIO cand.profileDigest
  let candCatalogWire ← digestWireIO cand.calleeCatalogDigest
  pure {
    deployable := true
    extraFiles := #[s!"{programName}.so"]
    evidenceNote :=
      s!"solana-sbpf-cpi-elf-v1 sbpf {version} sha256={toolSha} " ++
      s!"profile={CodegenProfileId.solanaSbpfCpiElfV1} " ++
      s!"profileDigest={candProfileWire} " ++
      s!"catalogDigest={candCatalogWire} " ++
      s!"planDigest={planWire} irDigest={irDigestNote} " ++
      "completed successfully (no env ELF copy; callee pins in bindings/catalog)"
  }
private def finalizeUnknownProfile (profile : CodegenProfileId) :
    IO EngineeringFinalizationDraftV1 :=
  throw <| IO.userError
    s!"PF-ARTIFACT-NONDEPLOYABLE: unknown Solana codegen profile '{profile}' (exhaustive plan/elf/cpi only)"

/-- Solana finalization: exhaustive profile dispatch (plan / elf / cpi). -/
def finalize
    (capability : ResolvedEngineeringBuildV1)
    (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EngineeringFinalizationDraftV1 := do
  let profile := ResolvedEngineeringBuildV1.codegenProfileOf capability
  if profile == CodegenProfileId.solanaSbpfPlanV1 then
    finalizePlanProfile
  else if profile == CodegenProfileId.solanaSbpfElfV1 then
    finalizeElfProfile artifacts stagingDir
  else if profile == CodegenProfileId.solanaSbpfCpiElfV1 then
    finalizeCpiElfProfile capability artifacts stagingDir
  else
    finalizeUnknownProfile profile

end ProofForgeV2.Targets.Solana.FinalizeV1
