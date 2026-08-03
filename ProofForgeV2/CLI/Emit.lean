/-
  ProofForgeV2.CLI.Emit — product emit + pure CLI command surface.

  Product commands (C1 + inspect-output):
    list-targets [--all] [--json]
    inspect <target> [--json]
    inspect <output-dir> [--json]
    inspect --output-dir <dir> [--json]
    check <source.lean> --module <Name> [--root] [--program] [--target]
      [--profile] [--language-version] [--json]
    build <source.lean> --module <Name> --target <t> [-o <dir>]
      [--program] [--root] [--profile] [--language-version] [--json]

  Disambiguation for positional `inspect <arg>`:
    * If `<arg>` is a registered TargetId (frozen registry membership), treat as
      target inspect (`proof-forge.cli.inspect.v1`).
    * Otherwise treat as output-dir inspect (`proof-forge.cli.inspect-output.v1`).
    * Explicit `inspect --output-dir <dir>` always selects output-dir mode.
    * Ambiguous names that are both a registered target and a directory prefer
      the registry target (document this; use `--output-dir` to force a path).

  Stable JSON uses sole PF-JCS (`renderPfJcs` / `PfJson`). Schemas:
    proof-forge.cli.list-targets.v1
    proof-forge.cli.inspect.v1
    proof-forge.cli.inspect-output.v1
    proof-forge.cli.check.v1
    proof-forge.cli.build.v1

  Output-dir validation scope (engineering, not formal OutputSetV1):
    * Stable-read `manifest.json` + `evidence.json` via ArtifactContentV1 helper
      (regular single-link, bounded; no ad-hoc readFile content authority).
    * Parse pretty-printed engineering JSON (whitespace-tolerant; not PF-JCS).
    * Exact key set for `proof-forge.output.v1` + schemaVersion exact.
    * Digest fields: 64-char lowercase hex; re-encode to Digest via `sha256:`.
    * files: non-empty array of exact-key objects
      `{role,path,size,contentSha256}`; path-only string arrays fail closed.
    * Top-level `evidenceSha256` (bare hex of exact evidence.json UTF-8).
    * Derive untrusted claims from manifest descriptors → sole
      `scanArtifactContentClosureV1` with fixed sidecars → exact inventory
      compare to manifest descriptors; evidence digest + identity join;
      recompute `outputSetDigest`. Rejects artifact/byte/size/role/path
      mutation, extra/missing leaves, symlink/FIFO/hardlink, evidence note-only
      mutation, legacy path-only manifests.
    * Does NOT forge FinalizedArtifactsV1 or re-run materializers.

  Deleted product commands: `build-counter`, `describe-target` (use
  `build Examples/Counter.lean --module Examples.Counter` and `inspect`).
  `--network` remains a usage error (no network registry).
  Engineering only — not formal CLI / OutputSetV1 / SupportClaim completion.
-/
import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Targets.RegistryRootV1
import ProofForgeV2.Targets.SupportClaimV1
import ProofForgeV2.Targets.EngineeringBuildIdentityV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.ArtifactContentV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.EngineeringDiskClosureV1
import ProofForgeV2.Materialization.OutputSetV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.CLI

open ProofForgeV2 Targets System
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1
open ProofForgeV2.Targets.RegistryRootV1
open ProofForgeV2.Targets.SupportClaimV1
open ProofForgeV2.Targets.EngineeringBuildIdentityV1

private def writeFileCreatingParent (path : FilePath) (contents : String) : IO Unit := do
  if let some parent := path.parent then
    IO.FS.createDirAll parent
  IO.FS.writeFile path contents

/-- Package-visible path-safety predicate for program artifact names.
    Non-capability inspection only — does not mint carriers or emit. -/
def validProgramArtifactNameV1 (value : String) : Bool :=
  match value.toList with
  | [] => false
  | first :: rest =>
      (first.isAlpha || first == '_') &&
        rest.all (fun char => char.isAlphanum || char == '_' || char == '-')

private def validArtifactName (value : String) : Bool :=
  validProgramArtifactNameV1 value

/-- CLI path dual defense uses the sole package helper (no local reimplementation). -/
private def safeRelativePath (value : String) : Bool :=
  safeRelativeArtifactPathV1 value

private def pathType? (path : FilePath) : IO (Option IO.FS.FileType) :=
  try
    return some (← path.symlinkMetadata).type
  catch _ =>
    return none

private def removePathIfPresent (path : FilePath) : IO Unit := do
  match ← pathType? path with
  | none => pure ()
  | some .dir => IO.FS.removeDirAll path
  | some _ => IO.FS.removeFile path

private partial def createSiblingStaging (parent : FilePath) (name : String)
    (pid attempt : Nat) : IO FilePath := do
  if attempt >= 128 then
    throw <| IO.userError "PF-OUTPUT-PATH: could not allocate an atomic staging directory"
  let candidate := parent / s!".{name}.staging-{pid}-{attempt}"
  try
    IO.FS.createDir candidate
    return candidate
  catch _ =>
    createSiblingStaging parent name pid (attempt + 1)

private def digestHexForOutputV1 (label : String) (digest : Digest) : IO String := do
  let rendered ← match renderDigest digest with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"PF-OUTPUT-MANIFEST: {label} digest render failed: {error}"
  unless rendered.startsWith "sha256:" do
    throw <| IO.userError s!"PF-OUTPUT-MANIFEST: {label} digest is not sha256"
  let suffix := (rendered.drop 7).toString
  unless suffix.length == 64 do
    throw <| IO.userError s!"PF-OUTPUT-MANIFEST: {label} digest has invalid length"
  pure suffix

/-- CLI dual-defense for the capability-bound non-alpha identity and paths.
    The materialized mint already validates these joins; this preserves stable
    PF-OUTPUT-MANIFEST / PF-OUTPUT-PATH ordering at the publish boundary. -/
private def validateMaterializedCarrier
    (compiled : CompiledSemanticV1) (artifacts : MaterializedArtifactsV1) : IO Unit := do
  unless MaterializedArtifactsV1.sourceDigestOf artifacts ==
        CompiledSemanticV1.sourceDigestOf compiled &&
      MaterializedArtifactsV1.semanticDigestOf artifacts ==
        CompiledSemanticV1.semanticDigestOf compiled do
    throw <| IO.userError
      "PF-OUTPUT-MANIFEST: materializer manifest does not bind the compiled program"
  let programName := CompiledSemanticV1.artifactProgramNameOf compiled
  unless MaterializedArtifactsV1.artifactProgramNameOf artifacts == programName do
    throw <| IO.userError
      "PF-OUTPUT-MANIFEST: materializer program name does not bind the compiled program"
  unless validArtifactName programName do
    throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe program artifact name '{programName}'"
  let mut paths : Array String := #[]
  for file in MaterializedArtifactsV1.filesOf artifacts do
    unless safeRelativePath file.path do
      throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe artifact path '{file.path}'"
    if paths.contains file.path then
      throw <| IO.userError s!"PF-OUTPUT-PATH: duplicate artifact path '{file.path}'"
    paths := paths.push file.path

/-- CLI emit receipt (stdout / tests). Not formal OutputManifest / OutputSetV1. -/
structure EmitReceiptV1 where
  target : TargetId
  codegenProfile : CodegenProfileId
  deployable : Bool
  deriving BEq, Repr

/-- One SPEC-CLI `--resource-limit <stage>.<field>=<n>` override (D3-E5).
Stage/field use CLI spelling (`compiler-core`, `wall-ms`, …). Hoisted before
`emitProgram` so the publisher can consume the same array for published-byte
and pre-rename wall gates without a second authority. -/
structure ResourceLimitOverrideV1 where
  stage : String
  field : String
  value : UInt64
  deriving BEq, Repr, Inhabited

/-- RES-1B effective artifact-output published-byte cap. A legal CLI
    override is lower-only; omission uses the frozen hard output maximum. -/
def effectivePublishedBytesLimitV1
    (limits : Array ResourceLimitOverrideV1) : UInt64 :=
  match limits.find? fun l =>
      l.stage == "artifact-output" && l.field == "published-bytes" with
  | some lim => lim.value
  | none => hardOutputProfile.maxPublishedBytes

/-- First `stage.wall-ms` override value if present (RES-1). -/
def wallMsOverrideV1
    (limits : Array ResourceLimitOverrideV1) (stage : String) : Option UInt64 :=
  match limits.find? (fun l => l.stage == stage && l.field == "wall-ms") with
  | some lim => some lim.value
  | none => none

/-- RES-1 pure wall-clock gate: when a `wall-ms` override is present for `stage`,
    `elapsedMs` must be ≤ the override. Fail closed with a stable PF-RESOURCE-TIME
    message (exit 6 at product boundary). No override ⇒ ok. -/
def enforceWallMsLimitV1
    (stage : String) (limit? : Option UInt64) (elapsedMs : UInt64) :
    Except String Unit :=
  match limit? with
  | none => pure ()
  | some lim =>
      if elapsedMs > lim then
        .error s!"PF-RESOURCE-TIME: {stage}.wall-ms limit {lim} exceeded (elapsed {elapsedMs} ms)"
      else
        pure ()

/-- Enforce all present wall-ms overrides against one measured elapsed budget.
    Product path measures load+compile (+ materialize for build) as one wall. -/
def enforceAllWallMsLimitsV1
    (limits : Array ResourceLimitOverrideV1) (elapsedMs : UInt64) :
    Except String Unit := do
  for stage in #["frontend", "compiler-core", "external-tool", "artifact-output"] do
    enforceWallMsLimitV1 stage (wallMsOverrideV1 limits stage) elapsedMs

/-- RES-1B engineering published-byte observation: all scanned base/finalized
    artifact bytes plus the exact UTF-8 bytes of both fixed sidecars. The sole
    physical artifact-size observations remain `ArtifactContentV1`; this helper
    only combines those sizes with sidecar bytes already rendered in memory. -/
def engineeringPublishedBytesV1
    (artifactSizes : Array Nat) (evidence manifest : String) : Nat :=
  artifactSizes.foldl (init := 0) (· + ·) +
    evidence.toUTF8.size + manifest.toUTF8.size

/-- RES-1B lower-only artifact-output gate. Equality is accepted; the first
    byte over the effective limit fails with the resource diagnostic family,
    distinct from the fixed S7c `PF-OUTPUT-LIMIT` closure defense. -/
def enforcePublishedBytesLimitV1
    (limit : UInt64) (publishedBytes : Nat) : Except String Unit :=
  if publishedBytes > limit.toNat then
    .error s!"PF-RESOURCE-OUTPUT: artifact-output.published-bytes limit {limit} exceeded (published {publishedBytes} bytes)"
  else
    pure ()

/-- Publisher dual-defense for finalized extra paths (D3/S7b + S7c).

    Mirrors `validateMaterializedCarrier` path ownership: safety, uniqueness vs
    base files, uniqueness among extras, and rejection of transitional sidecar
    names (`evidence.json` / `manifest.json`) before any sidecar write. Mint and
    disk-closure also gate collisions; this is defense-in-depth with historical
    PF-OUTPUT-PATH wires so a mint regression cannot publish colliding/dup
    lists or overwrite tool extras that reuse sidecar names. Package-visible
    for focused tests. -/
def validateFinalizedExtraPathsForPublishV1
    (basePaths : Array String) (extraFiles : Array String) : IO Unit := do
  let mut paths : Array String := basePaths
  for file in extraFiles do
    unless safeRelativePath file do
      throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe finalized artifact path '{file}'"
    -- Dual-defense: reject transitional sidecar names before any sidecar write so a
    -- tool extra named evidence.json/manifest.json cannot be overwritten later.
    if file == evidenceSidecarNameV1 || file == manifestSidecarNameV1 then
      throw <| IO.userError
        s!"PF-OUTPUT-PATH: finalized extra path collides with sidecar '{file}'"
    if paths.contains file then
      throw <| IO.userError s!"PF-OUTPUT-PATH: duplicate finalized artifact path '{file}'"
    paths := paths.push file

/-- Publisher-only staging render (D3/S7b + S7c + D3-E7 artifact-content OutputSet).

    Owns base-file writes, dual-defense extra-path checks, artifact-only scan →
    pure `mintEngineeringOutputSetV1` + engineering `proof-forge.output.v1`
    manifest/evidence rendering. Finalization authority (tools, deployability,
    notes) is sole Registry `finalizeMaterializedArtifactsV1` → target adapters
    → `FinalizedArtifactsV1`. Write order: base → finalize extras → artifact-only
    scan → pure OutputSet mint → render evidence → render manifest → enforce
    effective published-byte limit → write evidence → write manifest last →
    full scan with sidecars → exact pre/post inventory compare → verify evidence
    bytes digest → rename. Sole content walker/hash is ArtifactContentV1.
    Not formal OutputSetV1 or memory/process containment. -/
private def renderIntoStaging (capability : Targets.ResolvedEngineeringBuildV1)
    (compiled : CompiledSemanticV1) (artifacts : MaterializedArtifactsV1)
    (publishedBytesLimit : UInt64) (stagingDir : FilePath) : IO EmitReceiptV1 := do
  -- Dual-defense: compiled digests still gate before any disk write.
  let _ ← digestHexForOutputV1 "source" (CompiledSemanticV1.sourceDigestOf compiled)
  let _ ← digestHexForOutputV1 "semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  for file in MaterializedArtifactsV1.filesOf artifacts do
    writeFileCreatingParent (stagingDir / file.path) file.contents
  let finalized ← Targets.finalizeMaterializedArtifactsV1 capability artifacts stagingDir
  let basePaths :=
    (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  -- Dual-defense: safety + uniqueness vs base + uniqueness among extras.
  validateFinalizedExtraPathsForPublishV1 basePaths
    (FinalizedArtifactsV1.extraFilesOf finalized)
  -- Artifact-only scan (no sidecars yet) → pure OutputSet mint.
  let preInv ← scanEngineeringArtifactContentOnlyV1 finalized stagingDir
  let outputSet ← match mintEngineeringOutputSetV1 finalized preInv with
    | .ok value => pure value
    | .error error => throw <| IO.userError error.render
  let evidence ← match renderEngineeringOutputSetEvidenceV1 outputSet with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"PF-OUTPUT-MANIFEST: evidence render failed: {error}"
  let manifest ← match renderEngineeringOutputSetManifestV1 outputSet with
    | .ok value => pure value
    | .error error =>
        throw <| IO.userError s!"PF-OUTPUT-MANIFEST: output-set manifest render failed: {error}"
  -- RES-1B: enforce the lower-only effective cap after all artifact sizes and
  -- exact sidecar bytes are known, but before either sidecar write or rename.
  let artifactSizes :=
    (ArtifactContentInventoryV1.descriptorsOf preInv).map (·.size)
  let publishedBytes := engineeringPublishedBytesV1 artifactSizes evidence manifest
  match enforcePublishedBytesLimitV1 publishedBytesLimit publishedBytes with
  | .ok () => pure ()
  | .error error => throw <| IO.userError error
  -- Dual-defense: rendered evidence UTF-8 digest must match mint-time evidenceSha256.
  let evidenceDigest := sha256Bytes evidence.toUTF8
  let recordedEvidence := EngineeringOutputSetV1.evidenceSha256Of outputSet
  unless evidenceDigest.algorithm == recordedEvidence.algorithm &&
      evidenceDigest.bytes == recordedEvidence.bytes do
    throw <| IO.userError
      "PF-OUTPUT-MANIFEST: evidence bytes digest diverges from output-set evidenceSha256"
  -- S7c: evidence before manifest; manifest is the last file write.
  IO.FS.writeFile (stagingDir / evidenceSidecarNameV1) evidence
  IO.FS.writeFile (stagingDir / manifestSidecarNameV1) manifest
  -- Full scan with fixed sidecars; exact pre/post artifact inventory compare.
  let postInv ← scanEngineeringArtifactContentWithSidecarsV1 finalized stagingDir
  unless ArtifactContentInventoryV1.beq preInv postInv do
    throw <| IO.userError
      "PF-OUTPUT-MANIFEST: artifact content inventory changed after sidecar write"
  -- Re-verify evidence.json exact bytes digest via sole stable-read authority.
  let (_sz, evidenceBytes, evidenceOnDiskDigest) ←
    readStableArtifactLeafBytesV1 stagingDir evidenceSidecarNameV1
  unless evidenceOnDiskDigest.algorithm == recordedEvidence.algorithm &&
      evidenceOnDiskDigest.bytes == recordedEvidence.bytes do
    throw <| IO.userError
      "PF-OUTPUT-MANIFEST: on-disk evidence content digest diverges from evidenceSha256"
  unless evidenceBytes == evidence.toUTF8 do
    throw <| IO.userError
      "PF-OUTPUT-MANIFEST: on-disk evidence bytes diverge from rendered evidence"
  return {
    target := EngineeringOutputSetV1.targetIdOf outputSet
    codegenProfile := EngineeringOutputSetV1.codegenProfileOf outputSet
    deployable := EngineeringOutputSetV1.deployableOf outputSet
  }

/-- Product emit path: private engineering capability only.
    Mints engineering `EngineeringOutputSetV1` after finalization and publishes
    `proof-forge.output.v1` manifest + evidence sidecars. No public
    `(selection, compiled)` overload. Not formal OutputSetV1.

    Third argument is the CLI resource-limit array (defaults empty ⇒ hard
    published-byte max, no wall overrides). Optional `wallStartedMs` enables
    RES-1 wall enforcement immediately before atomic rename so over-budget
    builds throw, clean staging, and never publish. Two-argument callers remain
    compatible. -/
def emitProgram (capability : Targets.ResolvedEngineeringBuildV1)
    (outputDir : FilePath)
    (resourceLimits : Array ResourceLimitOverrideV1 := #[])
    (wallStartedMs : Option Nat := none) :
    IO EmitReceiptV1 := do
  let publishedBytesLimit := effectivePublishedBytesLimitV1 resourceLimits
  let compiled := Targets.ResolvedEngineeringBuildV1.compiledOf capability
  let programName := CompiledSemanticV1.artifactProgramNameOf compiled
  -- Reject unsafe artifact identity before entering a target materializer. A
  -- backend may impose stricter ABI identifier rules, but path safety is a CLI
  -- boundary and retains its stable diagnostic independently of target.
  unless validArtifactName programName do
    throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe program artifact name '{programName}'"
  let artifacts ← match Targets.materializeResult capability with
    | .ok output => pure output
    | .error error => throw <| IO.userError error.render
  validateMaterializedCarrier compiled artifacts
  let name ← match outputDir.fileName with
    | some name => pure name
    | none => throw <| IO.userError "PF-OUTPUT-PATH: output directory must have a final component"
  unless name != "." && name != ".." && !name.isEmpty do
    throw <| IO.userError "PF-OUTPUT-PATH: unsafe output directory"
  let parentInput := outputDir.parent.getD "."
  IO.FS.createDirAll parentInput
  let parent ← IO.FS.realPath parentInput
  let destination := parent / name
  match ← pathType? destination with
  | some .symlink =>
      throw <| IO.userError "PF-OUTPUT-PATH: output directory cannot be a symbolic link"
  | some _ =>
      throw <| IO.userError
        s!"PF-OUTPUT-COLLISION: output already exists: {destination}; choose a fresh directory"
  | none => pure ()
  let pid ← IO.Process.getPID
  let staging ← createSiblingStaging parent name pid.toNat 0
  try
    let receipt ←
      renderIntoStaging capability compiled artifacts publishedBytesLimit staging
    -- RES-1: wall before rename. Over-budget throws; catch cleans staging so
    -- destination is never published. Stage/order of enforceAllWallMsLimitsV1
    -- is unchanged (frontend → compiler-core → external-tool → artifact-output).
    match wallStartedMs with
    | none => pure ()
    | some startedMs =>
        let now ← IO.monoMsNow
        let elapsed := UInt64.ofNat (now - startedMs)
        match enforceAllWallMsLimitsV1 resourceLimits elapsed with
        | .ok () => pure ()
        | .error msg => throw <| IO.userError msg
    -- Recheck immediately before publish. This closes the cooperative writer
    -- race and ensures a build without an explicit future `--force` mode never
    -- replaces user data. A non-empty destination created by another process
    -- also makes the platform rename fail closed.
    if (← pathType? destination).isSome then
      throw <| IO.userError
        s!"PF-OUTPUT-COLLISION: output appeared during build: {destination}"
    IO.FS.rename staging destination
    return receipt
  catch error =>
    removePathIfPresent staging
    throw error

/-- Full build/check option bag (CLI internal + test-facing parse).
`output`/`root` are `Option` so duplicate flags are detectable (defaults applied
at product path: `build/v2` and `.`). `json` selects PF-JCS stdout.
D3-E5: `resourceLimits` / `minimumEvidence` / proof-bundle pair are parsed and
validated fail-closed before source open. RES-1 enforces wall clocks (build:
pre-rename inside emitProgram; check: post-success path). The RES-1B
output-only slice enforces `artifact-output.published-bytes` before
publication. Memory/process/protocol/stderr remain observation-only gaps. -/
structure BuildOptions where
  source : Option String := none
  target : Option TargetId := none
  profile : Option CodegenProfileId := none
  languageVersion : Option String := none
  output : Option String := none
  moduleName : Option String := none
  programName : Option String := none
  root : Option String := none
  json : Bool := false
  resourceLimits : Array ResourceLimitOverrideV1 := #[]
  minimumEvidence : Option String := none
  proofBundle : Option String := none
  proofBundleDigest : Option String := none
  deriving Repr

/-- Product command kind for post-parse resource/evidence flag validation. -/
inductive CliBuildCommandKindV1 where
  | check
  | build
  deriving DecidableEq, Repr

/-- Selection-relevant CLI flags exposed for focused tests. -/
structure BuildSelectionCliFlags where
  target : Option TargetId := none
  profile : Option CodegenProfileId := none
  deriving BEq, Repr

/-- Parsed `list-targets` trailing flags. -/
structure ListTargetsOptions where
  includeDesignOnly : Bool := false
  json : Bool := false
  deriving BEq, Repr

/-- Typed product CLI command surface. `CLI.run` matches only this enum.
Deleted: `build-counter`, `describe-target` (use build + inspect).
`inspect` keeps the historical `(String, Bool)` shape so pure parse tests stay
stable; product `CLI.run` disambiguates registered target vs output-dir path.
`inspectOutput` is the explicit `--output-dir` form (always output-dir mode). -/
inductive CliCommandV1 where
  | listTargets (options : ListTargetsOptions)
  | inspect (target : String) (json : Bool)
  | inspectOutput (dir : String) (json : Bool)
  | check (options : BuildOptions)
  | build (options : BuildOptions)
  | usage
  deriving Repr

private def parseTargetExcept (value : String) : Except String TargetId :=
  match TargetId.parse? value with
  | some target => .ok target
  | none => .error s!"unknown target '{value}'"

private def parseProfileExcept (value : String) : Except String CodegenProfileId :=
  match CodegenProfileId.parse? value with
  | some profile => .ok profile
  | none => .error s!"unknown profile '{value}'"

/-- CLI stage spelling → hard ResourceProfileV1 (SPEC-CLI / SPEC-COMMON-001). -/
def hardResourceProfileForCliStageV1 (stage : String) : Except String ResourceProfileV1 :=
  match stage with
  | "frontend" => pure hardFrontendProfile
  | "compiler-core" => pure hardCoreProfile
  | "external-tool" => pure hardToolProfile
  | "artifact-output" => pure hardOutputProfile
  | _ => throw s!"unknown resource-limit stage '{stage}'"

/-- Field spelling → hard max for the stage profile (0 means only 0 is legal). -/
def hardMaxForResourceFieldV1 (profile : ResourceProfileV1) (field : String) :
    Except String UInt64 :=
  match field with
  | "wall-ms" => pure profile.maxWallMillis
  | "memory-bytes" => pure profile.maxAggregateMemoryBytes
  | "processes" => pure (UInt64.ofNat profile.maxProcesses.toNat)
  | "protocol-bytes" => pure profile.maxProtocolBytes
  | "stderr-bytes" => pure profile.maxStderrBytes
  | "published-bytes" => pure profile.maxPublishedBytes
  | _ => throw s!"unknown resource-limit field '{field}'"

/-- Parse `stage.field=n` (unsigned decimal). Fail closed on shape / zero / over hard max. -/
def parseResourceLimitSpecV1 (spec : String) : Except String ResourceLimitOverrideV1 := do
  let eqParts := spec.splitOn "="
  unless eqParts.length == 2 do
    throw s!"invalid --resource-limit '{spec}' (want stage.field=n)"
  let lhs := eqParts[0]!
  let rhs := eqParts[1]!
  let dotParts := lhs.splitOn "."
  unless dotParts.length == 2 do
    throw s!"invalid --resource-limit '{spec}' (want stage.field=n)"
  let stage := dotParts[0]!
  let field := dotParts[1]!
  unless stage.length > 0 && field.length > 0 do
    throw s!"invalid --resource-limit '{spec}' (empty stage or field)"
  unless rhs.length > 0 do
    throw s!"invalid --resource-limit '{spec}' (empty value)"
  -- Unsigned decimal only; reject signs, underscores, exponents, hex.
  for c in rhs.toList do
    unless c.isDigit do
      throw s!"invalid --resource-limit value '{rhs}' (unsigned decimal required)"
  let n ← match rhs.toNat? with
    | some n => pure n
    | none => throw s!"invalid --resource-limit value '{rhs}' (unsigned decimal required)"
  unless n > 0 do
    throw s!"resource-limit value must be a positive integer"
  unless n < 2 ^ 64 do
    throw s!"resource-limit value overflows UInt64"
  let hard ← hardResourceProfileForCliStageV1 stage
  let hardMax ← hardMaxForResourceFieldV1 hard field
  if hardMax == 0 then
    throw s!"resource-limit {stage}.{field} hard maximum is 0; override rejected"
  unless n ≤ hardMax.toNat do
    throw s!"resource-limit {stage}.{field}={n} exceeds hard maximum {hardMax.toNat}"
  pure { stage, field, value := UInt64.ofNat n }

/-- Closed SPEC-CLI `--minimum-evidence` grades (engineering accept list). -/
def isValidMinimumEvidenceGradeV1 (grade : String) : Bool :=
  grade == "specified" ||
  grade == "artifact_validated" ||
  grade == "local_runtime" ||
  grade == "network_or_proof_validated"

/-- Exact SPEC-COMMON-001 lowercase SHA-256 wire: `sha256:` + 64 hex digits. -/
def isValidProofBundleDigestWireV1 (wire : String) : Bool :=
  let cs := wire.toList
  let pfx := ("sha256:").toList
  if !pfx.isPrefixOf cs then false
  else
    let hexChars := cs.drop pfx.length
    if hexChars.length != 64 then false
    else
      hexChars.all fun c =>
        ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

/-- Post-parse validation for check vs build (SPEC-CLI resource/evidence/proof-bundle).
Runs before source open / materialize. Wall-clock **enforcement** is RES-1
(`enforceWallMsLimitV1` after product stages). -/
def validateBuildOptionsCliV1
    (kind : CliBuildCommandKindV1) (options : BuildOptions) :
    Except String BuildOptions := do
  -- Resource limits: stage allowlist by command; no duplicate (stage,field).
  let mut seen : Array (String × String) := #[]
  for lim in options.resourceLimits do
    match kind with
    | .check =>
        if lim.stage == "external-tool" || lim.stage == "artifact-output" then
          throw s!"check rejects --resource-limit stage '{lim.stage}'"
    | .build => pure ()
    -- Re-validate against hard profiles (parser already did; belt-and-braces).
    let _ ← hardResourceProfileForCliStageV1 lim.stage
    let key := (lim.stage, lim.field)
    if seen.any (· == key) then
      throw s!"duplicate --resource-limit {lim.stage}.{lim.field}"
    seen := seen.push key
  -- minimum-evidence: build only
  match options.minimumEvidence with
  | none => pure ()
  | some grade =>
      match kind with
      | .check => throw "--minimum-evidence is not accepted on check"
      | .build =>
          unless isValidMinimumEvidenceGradeV1 grade do
            throw s!"unknown --minimum-evidence grade '{grade}'"
  -- proof-bundle pair
  match options.proofBundle, options.proofBundleDigest with
  | none, none => pure ()
  | some _, none => throw "--proof-bundle requires --proof-bundle-digest"
  | none, some _ => throw "--proof-bundle-digest requires --proof-bundle"
  | some dir, some dig =>
      if dir.isEmpty then throw "--proof-bundle path must be nonempty"
      unless isValidProofBundleDigestWireV1 dig do
        throw "invalid --proof-bundle-digest (want sha256:<64 lowercase hex>)"
      -- INV-1: pair shape accepted here; product path joins after compile using
      -- ProofReferenceJoinV1 (unused pair / missing pair / export join fail closed).
      pure ()
  pure options

/-- Shared build/check argument parser (pure Except).
`--network` and any other unknown dashed option fail as usage errors.
`--json` is a bare flag. Duplicate selection and common flags fail closed.
D3-E5: `--resource-limit` (repeatable), `--minimum-evidence`, proof-bundle pair. -/
partial def parseBuildArgsExcept (args : List String) (options : BuildOptions := {}) :
    Except String BuildOptions := do
  match args with
  | [] => pure options
  | "--target" :: value :: rest =>
      if options.target.isSome then throw "duplicate --target"
      parseBuildArgsExcept rest { options with target := some (← parseTargetExcept value) }
  | "--profile" :: value :: rest =>
      if options.profile.isSome then throw "duplicate --profile"
      parseBuildArgsExcept rest { options with profile := some (← parseProfileExcept value) }
  | "--language-version" :: value :: rest =>
      if options.languageVersion.isSome then throw "duplicate --language-version"
      parseBuildArgsExcept rest { options with languageVersion := some value }
  | "-o" :: value :: rest | "--output" :: value :: rest =>
      if options.output.isSome then throw "duplicate --output"
      parseBuildArgsExcept rest { options with output := some value }
  | "--module" :: value :: rest =>
      if options.moduleName.isSome then throw "duplicate --module"
      parseBuildArgsExcept rest { options with moduleName := some value }
  | "--program" :: value :: rest =>
      if options.programName.isSome then throw "duplicate --program"
      parseBuildArgsExcept rest { options with programName := some value }
  | "--root" :: value :: rest =>
      if options.root.isSome then throw "duplicate --root"
      parseBuildArgsExcept rest { options with root := some value }
  | "--json" :: rest =>
      if options.json then throw "duplicate --json"
      parseBuildArgsExcept rest { options with json := true }
  | "--resource-limit" :: value :: rest =>
      if value.startsWith "-" then throw "missing --resource-limit value"
      let lim ← parseResourceLimitSpecV1 value
      parseBuildArgsExcept rest
        { options with resourceLimits := options.resourceLimits.push lim }
  | "--minimum-evidence" :: value :: rest =>
      if options.minimumEvidence.isSome then throw "duplicate --minimum-evidence"
      if value.startsWith "-" then throw "missing --minimum-evidence value"
      parseBuildArgsExcept rest { options with minimumEvidence := some value }
  | "--proof-bundle" :: value :: rest =>
      if options.proofBundle.isSome then throw "duplicate --proof-bundle"
      if value.startsWith "-" then throw "missing --proof-bundle value"
      parseBuildArgsExcept rest { options with proofBundle := some value }
  | "--proof-bundle-digest" :: value :: rest =>
      if options.proofBundleDigest.isSome then throw "duplicate --proof-bundle-digest"
      if value.startsWith "-" then throw "missing --proof-bundle-digest value"
      parseBuildArgsExcept rest { options with proofBundleDigest := some value }
  | value :: rest =>
      if value.startsWith "-" then
        throw s!"unknown option '{value}'"
      else if options.source.isSome then
        throw "only one source file may be compiled"
      else
        parseBuildArgsExcept rest { options with source := some value }

/-- IO wrapper for product CLI (lifts `Except` parse errors). -/
def parseBuildArgs (args : List String) (options : BuildOptions := {}) : IO BuildOptions :=
  match parseBuildArgsExcept args options with
  | .ok opts => pure opts
  | .error msg => throw <| IO.userError msg

/-- Test-facing parse of build/check args for selection fields. -/
def parseBuildSelectionCliFlags (args : List String) : IO BuildSelectionCliFlags := do
  let options ← parseBuildArgs args
  pure { target := options.target, profile := options.profile }

/-- Test-facing typed selection resolver after argv parsing. It preserves
`CompileError.render` for all registry failures; product `CLI.run` additionally
classifies an unregistered argv target as plain usage via
`resolveBuildSelectionForCli`. -/
def resolveSelectionFromFlags (flags : BuildSelectionCliFlags) :
    IO ResolvedBuildSelectionV1 := do
  let target ← match flags.target with
    | some target => pure target
    | none => throw <| IO.userError "--target is required"
  match resolveBuildSelectionV1 target flags.profile with
  | .ok selection => pure selection
  | .error error => throw <| IO.userError error.render

/-- One `list-targets` line: `id\tmaturityLabel`. -/
def renderListTargetLine (reg : TargetRegistrationDataV1) : String :=
  s!"{reg.targetId}\t{reg.maturityLabel}"

/-- Pure list body against a supplied validated registry (rows only). -/
def listTargetLinesInRegistry (includeDesignOnly : Bool) (registry : TargetRegistryV1) :
    Array String :=
  if includeDesignOnly then
    (TargetRegistryV1.registrationsOf registry).map renderListTargetLine
  else
    (implementedRegistrationsInRegistry registry).map renderListTargetLine

/-- DI list body over a registry seed Result (propagates seed errors; no capability). -/
def listTargetLinesWithSeedV1
    (seed : CompileResult TargetRegistryV1) (includeDesignOnly : Bool) :
    CompileResult (Array String) := do
  let registry ← seed
  return listTargetLinesInRegistry includeDesignOnly registry

/-- Product `list-targets` body — binds frozen TargetRegistryV1 seed.
- Default: implemented-only, filter preserving canonical TargetId order.
- `--all`: full registry map in canonical TargetId order (not implemented-first). -/
def listTargetLines (includeDesignOnly : Bool) : CompileResult (Array String) :=
  listTargetLinesWithSeedV1 initialTargetRegistryV1Result includeDesignOnly

/-- Parse `list-targets` trailing args (pure). Accepts `--all` / `--json` any order. -/
partial def parseListTargetsArgsExcept
    (args : List String) (options : ListTargetsOptions := {}) :
    Except String ListTargetsOptions := do
  match args with
  | [] => pure options
  | "--all" :: rest =>
      if options.includeDesignOnly then throw "duplicate --all"
      parseListTargetsArgsExcept rest { options with includeDesignOnly := true }
  | "--json" :: rest =>
      if options.json then throw "duplicate --json"
      parseListTargetsArgsExcept rest { options with json := true }
  | other =>
      .error s!"unknown list-targets argument '{String.intercalate " " other}'"

def parseListTargetsArgs (args : List String) : IO ListTargetsOptions :=
  match parseListTargetsArgsExcept args with
  | .ok b => pure b
  | .error msg => throw <| IO.userError msg

/-- Parse trailing args that only allow optional `--json`. -/
def parseJsonOnlyArgsExcept (args : List String) : Except String Bool :=
  match args with
  | [] => .ok false
  | ["--json"] => .ok true
  | other =>
      .error s!"unknown argument '{String.intercalate " " other}'"

/-- Parse `inspect` trailing flags for the explicit `--output-dir` form.
Accepts `--json` / `--output-dir <dir>` in either order; duplicates fail closed. -/
partial def parseInspectOutputArgsExcept
    (args : List String) (dir? : Option String := none) (json : Bool := false) :
    Except String (String × Bool) := do
  match args with
  | [] =>
      match dir? with
      | some dir => pure (dir, json)
      | none => throw "inspect --output-dir requires a directory path"
  | "--output-dir" :: value :: rest =>
      if dir?.isSome then throw "duplicate --output-dir"
      if value.isEmpty then throw "inspect --output-dir requires a directory path"
      if value.startsWith "-" then throw s!"invalid --output-dir path '{value}'"
      parseInspectOutputArgsExcept rest (some value) json
  | "--json" :: rest =>
      if json then throw "duplicate --json"
      parseInspectOutputArgsExcept rest dir? true
  | other =>
      .error s!"unknown inspect argument '{String.intercalate " " other}'"

/-- Format exact S2 request identities for inspect/describe product text. -/
private def formatS2RequirementIds (ids : Array String) : String :=
  let body := String.intercalate ", " ids.toList
  s!"#[{body}]"

private def formatProfileList (profiles : Array CodegenProfileId) : String :=
  let body := String.intercalate ", " (profiles.map (·.toString)).toList
  s!"#[{body}]"

private def digestWireExcept (label : String) (digest : Digest) : Except String String :=
  match renderDigest digest with
  | .ok value => pure value
  | .error error => throw s!"{label} digest render failed: {error}"

private def digestWireCompile (label : String) (digest : Digest) : CompileResult String :=
  match digestWireExcept label digest with
  | .ok value => pure value
  | .error error => throw <| .registryInvalid error

/-- Render PF-JCS or surface a stable registry-invalid product error. -/
def renderCliJsonV1 (value : PfJson) : CompileResult String :=
  match renderPfJcs value with
  | .ok text => pure text
  | .error error => throw <| .registryInvalid s!"cli json render failed: {error}"

/-- Product list-targets JSON (`proof-forge.cli.list-targets.v1`). -/
def listTargetsJsonInRegistry
    (includeDesignOnly : Bool) (registry : TargetRegistryV1) : CompileResult String := do
  let regs :=
    if includeDesignOnly then TargetRegistryV1.registrationsOf registry
    else implementedRegistrationsInRegistry registry
  let targets := regs.map fun reg =>
    PfJson.object #[
      ("id", .string reg.targetId.toString),
      ("maturity", .string reg.maturityLabel)
    ]
  renderCliJsonV1 <|
    PfJson.object #[
      ("schema", .string "proof-forge.cli.list-targets.v1"),
      ("includeAll", .bool includeDesignOnly),
      ("targets", .array targets)
    ]

def listTargetsJson (includeDesignOnly : Bool) : CompileResult String := do
  let registry ← initialTargetRegistryV1Result
  listTargetsJsonInRegistry includeDesignOnly registry

/-- Implemented-registration describe join (shared by product inspect + tests).
Checks residual descriptor `targetId` and `codegenProfile` against the
registration row, then derives exact supported S2 request identities from the
frozen engineering support index. `TargetDescriptor` carries no requirement
list; design-only targets must not call this. -/
def describeImplementedJoin
    (reg : TargetRegistrationDataV1) (descriptor : TargetDescriptor) :
    CompileResult String := do
  unless reg.implemented do
    throw <| .registryInvalid
      "describeImplementedJoin requires an implemented registration"
  let profile ← match reg.defaultProfile with
    | some p => pure p
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' is missing a registered default profile"
  unless descriptor.targetId == reg.targetId do
    throw <| .registryInvalid
      s!"descriptor target identity diverges from registration '{reg.targetId}'"
  unless descriptor.codegenProfile == profile do
    throw <| .registryInvalid
      s!"descriptor profile diverges from static selection for '{reg.targetId}'"
  Targets.DescriptorDataV1.validateDescriptorAxesJoinV1 reg descriptor
  let s2Ids ← supportedS2RequestIdsForRegistrationV1 reg
  pure s!"target={reg.targetId}\nprofile={profile}\nrequirements={formatS2RequirementIds s2Ids}"

/-- Legacy three-line describe body (tests + inspect prefix for implemented rows). -/
def describeRegistrationText (reg : TargetRegistrationDataV1) : CompileResult String := do
  if reg.implemented then
    match Targets.descriptorForKind? reg.kind with
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' has no residual descriptor"
    | some descriptor => describeImplementedJoin reg descriptor
  else
    pure s!"target={reg.targetId}\nstatus=research-only"

/-- DI describe body over a registry seed Result (propagates seed errors; no capability).
**Seed is bound first** so a failed catalog always surfaces as the seed's
`PF-REGISTRY-INVALID` even when `value` is malformed/case-invalid. Product
success-seed path still maps unknown/malformed targets to `PF-TARGET-UNKNOWN`. -/
def describeTargetWithSeedV1
    (seed : CompileResult TargetRegistryV1) (value : String) :
    CompileResult String := do
  let registry ← seed
  let target ← match TargetId.parse? value with
    | some target => pure target
    | none => throw <| .unknownTarget value
  match registrationInRegistry? registry target with
  | none => throw <| .unknownTarget value
  | some reg => describeRegistrationText reg

/-- Inspection-only three-line describe helper (not a product CLI command). -/
def describeTargetText (value : String) : CompileResult String :=
  describeTargetWithSeedV1 initialTargetRegistryV1Result value

/-- Support-claim digest for an implemented (target, default profile) pair. -/
private def supportClaimDigestForRegistrationV1
    (registry : TargetRegistryV1) (reg : TargetRegistrationDataV1) :
    CompileResult String := do
  unless reg.implemented do
    throw <| .registryInvalid
      "supportClaimDigestForRegistrationV1 requires an implemented registration"
  let profile ← match reg.defaultProfile with
    | some p => pure p
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' is missing a registered default profile"
  let supportIndex ← initialStaticRequirementSupportIndexV1Result
  let claims ← match mintEngineeringSupportClaimsV1 registry supportIndex with
    | .ok value => pure value
    | .error e => throw <| .registryInvalid s!"engineering support claim mint failed: {e}"
  let claim ← match findEngineeringSupportClaimV1 claims reg.targetId profile with
    | some c => pure c
    | none =>
        throw <| .registryInvalid
          s!"no engineering support claim for target '{reg.targetId}' profile '{profile}'"
  digestWireCompile "supportClaim" (EngineeringSupportClaimV1.claimDigestOf claim)

/-- Product `inspect` human body — registry descriptor + identity chain summary.
Covers former describe-target fields plus profiles, maturity, status, registry
root digest, support-claim digest (implemented default profile), and the
engineering build-identity domain shape (no mint without a compiled program). -/
def inspectRegistrationText
    (registry : TargetRegistryV1) (reg : TargetRegistrationDataV1) :
    CompileResult String := do
  let rootDigest ← match engineeringRegistryRootDigestV1 registry with
    | .ok d => digestWireCompile "registryRoot" d
    | .error e => throw <| .registryInvalid s!"registry root digest failed: {e}"
  let domain := engineeringBuildIdentityDomainV1
  if reg.implemented then
    match Targets.descriptorForKind? reg.kind with
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' has no residual descriptor"
    | some descriptor =>
        let base ← describeImplementedJoin reg descriptor
        let claimDigest ← supportClaimDigestForRegistrationV1 registry reg
        pure <|
          base ++
          s!"\nprofiles={formatProfileList reg.profiles}" ++
          s!"\nstatus=implemented" ++
          s!"\nmaturity={reg.maturityLabel}" ++
          s!"\nregistryRootDigest={rootDigest}" ++
          s!"\nsupportClaimDigest={claimDigest}" ++
          s!"\nbuildIdentityDomain={domain}"
  else
    pure <|
      s!"target={reg.targetId}" ++
      s!"\nstatus=research-only" ++
      s!"\nmaturity={reg.maturityLabel}" ++
      s!"\nprofiles={formatProfileList reg.profiles}" ++
      s!"\nregistryRootDigest={rootDigest}" ++
      s!"\nbuildIdentityDomain={domain}"

/-- Product `inspect` JSON (`proof-forge.cli.inspect.v1`). -/
def inspectRegistrationJson
    (registry : TargetRegistryV1) (reg : TargetRegistrationDataV1) :
    CompileResult String := do
  let rootDigest ← match engineeringRegistryRootDigestV1 registry with
    | .ok d => digestWireCompile "registryRoot" d
    | .error e => throw <| .registryInvalid s!"registry root digest failed: {e}"
  let profiles := (reg.profiles.map fun p => PfJson.string p.toString)
  if reg.implemented then
    match Targets.descriptorForKind? reg.kind with
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' has no residual descriptor"
    | some descriptor =>
        -- Join checks keep inspect fail-closed on descriptor drift.
        let _ ← describeImplementedJoin reg descriptor
        let profile ← match reg.defaultProfile with
          | some p => pure p
          | none =>
              throw <| .registryInvalid
                s!"implemented target '{reg.targetId}' is missing a registered default profile"
        let s2Ids ← supportedS2RequestIdsForRegistrationV1 reg
        let claimDigest ← supportClaimDigestForRegistrationV1 registry reg
        let reqJson := s2Ids.map PfJson.string
        renderCliJsonV1 <|
          PfJson.object #[
            ("schema", .string "proof-forge.cli.inspect.v1"),
            ("target", .string reg.targetId.toString),
            ("defaultProfile", .string profile.toString),
            ("profiles", .array profiles),
            ("requirements", .array reqJson),
            ("implemented", .bool true),
            ("maturity", .string reg.maturityLabel),
            ("registryRootDigest", .string rootDigest),
            ("supportClaimDigest", .string claimDigest),
            ("buildIdentityDomain", .string engineeringBuildIdentityDomainV1)
          ]
  else
    renderCliJsonV1 <|
      PfJson.object #[
        ("schema", .string "proof-forge.cli.inspect.v1"),
        ("target", .string reg.targetId.toString),
        ("defaultProfile", .null),
        ("profiles", .array profiles),
        ("requirements", .null),
        ("implemented", .bool false),
        ("maturity", .string reg.maturityLabel),
        ("registryRootDigest", .string rootDigest),
        ("supportClaimDigest", .null),
        ("buildIdentityDomain", .string engineeringBuildIdentityDomainV1)
      ]

def inspectTargetWithSeedV1
    (seed : CompileResult TargetRegistryV1) (value : String) (json : Bool) :
    CompileResult String := do
  let registry ← seed
  let target ← match TargetId.parse? value with
    | some target => pure target
    | none => throw <| .unknownTarget value
  match registrationInRegistry? registry target with
  | none => throw <| .unknownTarget value
  | some reg =>
      if json then inspectRegistrationJson registry reg
      else inspectRegistrationText registry reg

/-- Product `inspect` body — binds frozen TargetRegistryV1 seed. -/
def inspectTargetText (value : String) (json : Bool := false) : CompileResult String :=
  inspectTargetWithSeedV1 initialTargetRegistryV1Result value json

/-- Product check success human body. -/
def renderCheckOkHumanV1
    (programName : String) (sourceDigest semanticDigest : Digest)
    (target? : Option TargetId) (profile? : Option CodegenProfileId) :
    CompileResult String := do
  let sourceWire ← digestWireCompile "source" sourceDigest
  let semanticWire ← digestWireCompile "semantic" semanticDigest
  let mut lines :=
    #["ok",
      s!"program={programName}",
      s!"sourceDigest={sourceWire}",
      s!"semanticDigest={semanticWire}"]
  match target?, profile? with
  | some tid, some pid =>
      lines := lines.push s!"target={tid}"
      lines := lines.push s!"profile={pid}"
  | some tid, none =>
      lines := lines.push s!"target={tid}"
  | none, _ => pure ()
  pure (String.intercalate "\n" lines.toList)

/-- Render one resource-limit override as PF-JCS object for check/build observation. -/
private def renderResourceLimitJsonV1 (lim : ResourceLimitOverrideV1) : PfJson :=
  PfJson.object #[
    ("stage", .string lim.stage),
    ("field", .string lim.field),
    ("value", .int (Int.ofNat lim.value.toNat))
  ]

/-- Product check success JSON (`proof-forge.cli.check.v1`). -/
def renderCheckOkJsonV1
    (programName : String) (sourceDigest semanticDigest : Digest)
    (target? : Option TargetId) (profile? : Option CodegenProfileId)
    (resourceLimits : Array ResourceLimitOverrideV1 := #[]) :
    CompileResult String := do
  let sourceWire ← digestWireCompile "source" sourceDigest
  let semanticWire ← digestWireCompile "semantic" semanticDigest
  let targetJson :=
    match target? with
    | some tid => PfJson.string tid.toString
    | none => PfJson.null
  let profileJson :=
    match profile? with
    | some pid => PfJson.string pid.toString
    | none => PfJson.null
  let limitsJson := PfJson.array (resourceLimits.map renderResourceLimitJsonV1)
  renderCliJsonV1 <|
    PfJson.object #[
      ("schema", .string "proof-forge.cli.check.v1"),
      ("ok", .bool true),
      ("program", .string programName),
      ("sourceDigest", .string sourceWire),
      ("semanticDigest", .string semanticWire),
      ("target", targetJson),
      ("codegenProfile", profileJson),
      ("resourceLimits", limitsJson)
    ]

/-- Product build success human body (includes selected profile). -/
def renderBuildOkHumanV1 (receipt : EmitReceiptV1) : String :=
  s!"built target={receipt.target} profile={receipt.codegenProfile} deployable={receipt.deployable}"

/-- Product build success JSON (`proof-forge.cli.build.v1`). -/
def renderBuildOkJsonV1
    (receipt : EmitReceiptV1)
    (resourceLimits : Array ResourceLimitOverrideV1 := #[])
    (minimumEvidence : Option String := none) :
    CompileResult String :=
  let limitsJson := PfJson.array (resourceLimits.map renderResourceLimitJsonV1)
  let evidenceJson :=
    match minimumEvidence with
    | some g => PfJson.string g
    | none => PfJson.null
  renderCliJsonV1 <|
    PfJson.object #[
      ("schema", .string "proof-forge.cli.build.v1"),
      ("target", .string receipt.target.toString),
      ("codegenProfile", .string receipt.codegenProfile.toString),
      ("deployable", .bool receipt.deployable),
      ("resourceLimits", limitsJson),
      ("minimumEvidence", evidenceJson)
    ]

-- ---------------------------------------------------------------------------
-- Output-dir inspect (proof-forge.cli.inspect-output.v1)
-- ---------------------------------------------------------------------------

/-- Engineering on-disk manifest fields accepted by product inspect-output. -/
structure InspectedOutputManifestV1 where
  target : String
  codegenProfile : String
  artifactProgramName : String
  sourceHash : String
  semanticHash : String
  buildIdentityDigest : String
  planDigest : String
  supportClaimDigest : String
  engineeringRegistryRootDigest : String
  outputSetDigest : String
  evidenceSha256 : String
  deployable : Bool
  files : Array ArtifactContentDescriptorV1
  deriving Repr

private def engineeringManifestRequiredKeysV1 : Array String := #[
  "schemaVersion",
  "target",
  "codegenProfile",
  "artifactProgramName",
  "sourceHash",
  "semanticHash",
  "buildIdentityDigest",
  "planDigest",
  "supportClaimDigest",
  "engineeringRegistryRootDigest",
  "outputSetDigest",
  "evidenceSha256",
  "deployable",
  "files"
]

private def engineeringFileDescriptorRequiredKeysV1 : Array String := #[
  "role",
  "path",
  "size",
  "contentSha256"
]

private def engineeringEvidenceRequiredKeysV1 : Array String := #[
  "target",
  "sourceHash",
  "semanticHash",
  "deployable",
  "note"
]

/-- Whitespace-tolerant engineering JSON parser for pretty-printed on-disk
    sidecars. Does **not** enforce PF-JCS re-encode identity (manifest/evidence
    are pretty-printed by the publisher). Duplicate keys fail closed. -/
private partial def skipJsonWs (input : List Char) : List Char :=
  match input with
  | [] => []
  | c :: rest =>
      if c == ' ' || c == '\n' || c == '\r' || c == '\t' then skipJsonWs rest
      else input

private def isJsonAsciiDigit (c : Char) : Bool :=
  '0' ≤ c && c ≤ '9'

private partial def parseJsonStringBody
    (input : List Char) (reversed : List Char) : Except String (String × List Char) :=
  match input with
  | [] => throw "json string is unterminated"
  | '\x22' :: rest => pure (String.ofList reversed.reverse, rest)
  | '\\' :: '\x22' :: rest => parseJsonStringBody rest ('\x22' :: reversed)
  | '\\' :: '\\' :: rest => parseJsonStringBody rest ('\\' :: reversed)
  | '\\' :: '/' :: rest => parseJsonStringBody rest ('/' :: reversed)
  | '\\' :: 'n' :: rest => parseJsonStringBody rest ('\x0a' :: reversed)
  | '\\' :: 'r' :: rest => parseJsonStringBody rest ('\x0d' :: reversed)
  | '\\' :: 't' :: rest => parseJsonStringBody rest ('\x09' :: reversed)
  | '\\' :: _ => throw "json string contains an unsupported escape"
  | c :: rest =>
      if c.toNat < 0x20 then
        throw "json string contains an unescaped control character"
      else
        parseJsonStringBody rest (c :: reversed)

private def parseJsonStringValue : List Char → Except String (String × List Char)
  | '\x22' :: rest => parseJsonStringBody rest []
  | _ => throw "json expected a string"

private def consumeJsonLiteral : List Char → List Char → Option (List Char)
  | [], input => some input
  | wanted :: wantedRest, actual :: actualRest =>
      if wanted == actual then consumeJsonLiteral wantedRest actualRest else none
  | _ :: _, [] => none

private def parseJsonLiteral
    (spelling : String) (value : PfJson) (input : List Char) :
    Except String (PfJson × List Char) :=
  match consumeJsonLiteral spelling.toList input with
  | some rest => pure (value, rest)
  | none => throw "json contains an invalid literal"

/-- Max decimal digits for engineering JSON integers (UInt64 bound, size fields). -/
private def maxEngineeringJsonIntegerDigitsV1 : Nat := 20

/-- Max JSON array elements before fail-closed (matches file-cap; untrusted input). -/
private def maxEngineeringJsonArrayElemsV1 : Nat := maxEngineeringDiskClosureFilesV1

/-- Max JSON object members before fail-closed (untrusted input). -/
private def maxEngineeringJsonObjectKeysV1 : Nat := 64

/-- Max structural JSON nesting before the recursive parser runs. -/
private def maxEngineeringJsonNestingV1 : Nat := 64

/-- O(n) lexical nesting pre-scan (brackets inside strings are ignored).

    Syntax remains authoritative in the JSON parser; this guard only prevents
    attacker-controlled deeply nested sidecars from exhausting the call stack. -/
private def validateEngineeringJsonNestingV1 (input : String) : Except String Unit := do
  let mut depth : Nat := 0
  let mut inString := false
  let mut escaped := false
  for c in input.toList do
    if inString then
      if escaped then
        escaped := false
      else if c == '\\' then
        escaped := true
      else if c == '"' then
        inString := false
    else if c == '"' then
      inString := true
    else if c == '{' || c == '[' then
      depth := depth + 1
      if depth > maxEngineeringJsonNestingV1 then
        throw "json nesting exceeds bound"
    else if c == '}' || c == ']' then
      if depth > 0 then
        depth := depth - 1
  pure ()

private def parseJsonNumber (input : List Char) : Except String (PfJson × List Char) := do
  let (negative, unsignedInput) :=
    match input with
    | '-' :: rest => (true, rest)
    | _ => (false, input)
  let (digits, rest) := unsignedInput.span isJsonAsciiDigit
  if digits.isEmpty then
    throw "json integer requires at least one digit"
  if digits.length > 1 && digits.head? == some '0' then
    throw "json integer contains a leading zero"
  -- Cap digit count before Nat accumulation (UInt64-sized bound is sufficient).
  if digits.length > maxEngineeringJsonIntegerDigitsV1 then
    throw "json integer digit count exceeds bound"
  -- Non-negative integers only (file size fields). Deployable remains bool-only
  -- via expectJsonBool; negative / non-zero-as-bool smuggling fails there.
  let mut value : Nat := 0
  for d in digits do
    value := value * 10 + (d.toNat - '0'.toNat)
  if negative then
    if value = 0 then
      throw "json forbids negative zero"
    else
      throw "json negative integer is not accepted in engineering sidecars"
  pure (.int (Int.ofNat value), rest)

private def hasJsonObjectKey (fields : Array (String × PfJson)) (key : String) : Bool :=
  fields.any (fun field => field.1 == key)

mutual

private partial def parseJsonValue (input : List Char) : Except String (PfJson × List Char) :=
  let input := skipJsonWs input
  match input with
  | [] => throw "json input ended before a value"
  | 'n' :: _ => parseJsonLiteral "null" .null input
  | 't' :: _ => parseJsonLiteral "true" (.bool true) input
  | 'f' :: _ => parseJsonLiteral "false" (.bool false) input
  | '\x22' :: _ => do
      let (value, rest) ← parseJsonStringValue input
      pure (.string value, rest)
  | '[' :: rest => parseJsonArray (skipJsonWs rest)
  | '{' :: rest => parseJsonObject (skipJsonWs rest)
  | '-' :: _ => parseJsonNumber input
  | c :: _ =>
      if isJsonAsciiDigit c then parseJsonNumber input
      else throw "json contains an invalid value"

private partial def parseJsonArrayTail
    (input : List Char) (values : Array PfJson) : Except String (PfJson × List Char) :=
  let input := skipJsonWs input
  match input with
  | ']' :: rest => pure (.array values, rest)
  | ',' :: rest => do
      if values.size >= maxEngineeringJsonArrayElemsV1 then
        throw "json array exceeds element bound"
      let (value, tail) ← parseJsonValue rest
      parseJsonArrayTail tail (values.push value)
  | _ => throw "json array requires ',' or ']'"

private partial def parseJsonArray
    (input : List Char) : Except String (PfJson × List Char) :=
  let input := skipJsonWs input
  match input with
  | ']' :: rest => pure (.array #[], rest)
  | _ => do
      let (value, rest) ← parseJsonValue input
      parseJsonArrayTail rest #[value]

private partial def parseJsonObjectField
    (input : List Char) (fields : Array (String × PfJson)) :
    Except String ((Array (String × PfJson)) × List Char) := do
  if fields.size >= maxEngineeringJsonObjectKeysV1 then
    throw "json object exceeds key bound"
  let input := skipJsonWs input
  let (key, afterKey) ← parseJsonStringValue input
  if hasJsonObjectKey fields key then
    throw "json object contains a duplicate key"
  let afterKey := skipJsonWs afterKey
  let afterColon ← match afterKey with
    | ':' :: rest => pure rest
    | _ => throw "json object member requires ':'"
  let (value, rest) ← parseJsonValue afterColon
  pure (fields.push (key, value), rest)

private partial def parseJsonObjectTail
    (input : List Char) (fields : Array (String × PfJson)) :
    Except String (PfJson × List Char) :=
  let input := skipJsonWs input
  match input with
  | '}' :: rest => pure (.object fields, rest)
  | ',' :: rest => do
      let (nextFields, tail) ← parseJsonObjectField rest fields
      parseJsonObjectTail tail nextFields
  | _ => throw "json object requires ',' or '}'"

private partial def parseJsonObject
    (input : List Char) : Except String (PfJson × List Char) :=
  let input := skipJsonWs input
  match input with
  | '}' :: rest => pure (.object #[], rest)
  | _ => do
      let (fields, rest) ← parseJsonObjectField input #[]
      parseJsonObjectTail rest fields

end

/-- Parse a complete engineering JSON document (trailing whitespace allowed). -/
def parseEngineeringJsonDocumentV1 (input : String) : Except String PfJson := do
  validateEngineeringJsonNestingV1 input
  let (value, rest) ← parseJsonValue input.toList
  let rest := skipJsonWs rest
  unless rest.isEmpty do
    throw "json input contains trailing data"
  pure value

private def jsonObjectFields? : PfJson → Option (Array (String × PfJson))
  | .object fields => some fields
  | _ => none

private def jsonField? (fields : Array (String × PfJson)) (key : String) : Option PfJson :=
  match fields.find? (fun field => field.1 == key) with
  | some (_, value) => some value
  | none => none

private def expectJsonString (label : String) (value : PfJson) : Except String String :=
  match value with
  | .string s => pure s
  | _ => throw s!"{label} must be a string"

private def expectJsonBool (label : String) (value : PfJson) : Except String Bool :=
  match value with
  | .bool b => pure b
  | _ => throw s!"{label} must be a boolean"

private def expectJsonNat (label : String) (value : PfJson) : Except String Nat :=
  match value with
  | .int n =>
      if n < 0 then throw s!"{label} must be a non-negative integer"
      else pure n.toNat
  | _ => throw s!"{label} must be an integer"

private def isLowerHex64 (value : String) : Bool :=
  value.length == 64 && value.all fun c =>
    ('0' ≤ c && c ≤ '9') || ('a' ≤ c && c ≤ 'f')

private def expectHex64Digest (label : String) (value : String) : Except String String := do
  unless isLowerHex64 value do
    throw s!"{label} must be 64 lowercase hex characters"
  pure value

private def digestFromBareHex (label : String) (hex : String) : Except String Digest := do
  let _ ← expectHex64Digest label hex
  match parseDigest ("sha256:" ++ hex) with
  | .ok d => pure d
  | .error e => throw s!"{label} is not a valid sha256 digest: {e}"

private def exactKeySet
    (fields : Array (String × PfJson)) (required : Array String) : Except String Unit := do
  unless fields.size == required.size do
    throw s!"expected exactly {required.size} keys, got {fields.size}"
  for key in required do
    unless hasJsonObjectKey fields key do
      throw s!"missing required key '{key}'"
  for (key, _) in fields do
    unless required.contains key do
      throw s!"unexpected key '{key}'"

/-- Parse one exact-key file descriptor object; reject path-only strings. -/
private def parseFileDescriptorObjectV1 (value : PfJson) :
    Except String ArtifactContentDescriptorV1 := do
  let fields ← match jsonObjectFields? value with
    | some f => pure f
    | none =>
        throw "files entries must be objects {role,path,size,contentSha256} (path-only rejected)"
  exactKeySet fields engineeringFileDescriptorRequiredKeysV1
  let roleWire ← expectJsonString "role" (jsonField? fields "role" |>.getD .null)
  let role ← match ArtifactContentRoleV1.ofWire? roleWire with
    | some r => pure r
    | none => throw s!"unknown artifact role '{roleWire}'"
  let path ← expectJsonString "path" (jsonField? fields "path" |>.getD .null)
  if path.isEmpty then throw "files path must be nonempty"
  if path == evidenceSidecarNameV1 || path == manifestSidecarNameV1 then
    throw "sidecars must not appear in files"
  unless safeRelativeArtifactPathV1 path do
    throw s!"unsafe artifact path '{path}'"
  let size ← expectJsonNat "size" (jsonField? fields "size" |>.getD .null)
  if size > maxEngineeringDiskClosureFileBytesV1 then
    throw s!"file exceeds size limit '{path}'"
  let contentHex ← expectHex64Digest "contentSha256"
    (← expectJsonString "contentSha256" (jsonField? fields "contentSha256" |>.getD .null))
  let contentSha256 ← digestFromBareHex "contentSha256" contentHex
  pure { role, path, size, contentSha256 }

private def expectFileDescriptorArrayV1 (label : String) (value : PfJson) :
    Except String (Array ArtifactContentDescriptorV1) := do
  match value with
  | .array values =>
      if values.isEmpty then throw s!"{label} must be non-empty"
      if values.size > maxEngineeringDiskClosureFilesV1 then
        throw s!"{label} exceeds descriptor bound ({values.size} > {maxEngineeringDiskClosureFilesV1})"
      let mut out : Array ArtifactContentDescriptorV1 := #[]
      let mut seen : Array String := #[]
      let mut totalBytes : Nat := 0
      for v in values do
        -- Explicit path-only rejection for clear diagnostics.
        match v with
        | .string _ =>
            throw s!"{label} path-only string entries are rejected under proof-forge.output.v1"
        | _ => pure ()
        let d ← parseFileDescriptorObjectV1 v
        if seen.contains d.path then throw s!"duplicate file path '{d.path}'"
        seen := seen.push d.path
        totalBytes := totalBytes + d.size
        if totalBytes > maxEngineeringDiskClosureTotalBytesV1 then
          throw s!"{label} total size exceeds limit at '{d.path}'"
        out := out.push d
      -- Canonical order (role-rank then path).
      let sorted := sortArtifactContentDescriptorsV1 out
      unless out.size == sorted.size do
        throw s!"{label} order is noncanonical"
      for pair in out.zip sorted do
        unless ArtifactContentDescriptorV1.beq pair.1 pair.2 do
          throw s!"{label} order is noncanonical (role-rank then path required)"
      for a in out do
        for b in out do
          if a.path != b.path && b.path.startsWith (a.path ++ "/") then
            throw s!"file/directory prefix conflict '{a.path}'"
      pure out
  | _ => throw s!"{label} must be an array"

/-- Validate on-disk `manifest.json` body into a typed carrier.
Structure + descriptor objects + hex format + public `engineeringOutputSetDigestV1`
recompute. Path-only `files` arrays fail closed. -/
def validateEngineeringOutputManifestTextV1 (text : String) :
    Except String InspectedOutputManifestV1 := do
  let value ← match parseEngineeringJsonDocumentV1 text with
    | .ok v => pure v
    | .error e => throw s!"manifest is not valid JSON: {e}"
  let fields ← match jsonObjectFields? value with
    | some f => pure f
    | none => throw "manifest must be a JSON object"
  exactKeySet fields engineeringManifestRequiredKeysV1
  let schemaVersion ← expectJsonString "schemaVersion"
    (jsonField? fields "schemaVersion" |>.getD .null)
  unless schemaVersion == engineeringOutputSchemaVersionV1 do
    throw s!"schemaVersion must be '{engineeringOutputSchemaVersionV1}', got '{schemaVersion}'"
  let target ← expectJsonString "target" (jsonField? fields "target" |>.getD .null)
  unless !target.isEmpty do throw "target must be nonempty"
  let codegenProfile ← expectJsonString "codegenProfile"
    (jsonField? fields "codegenProfile" |>.getD .null)
  unless !codegenProfile.isEmpty do throw "codegenProfile must be nonempty"
  let artifactProgramName ← expectJsonString "artifactProgramName"
    (jsonField? fields "artifactProgramName" |>.getD .null)
  unless !artifactProgramName.isEmpty do throw "artifactProgramName must be nonempty"
  let sourceHash ← expectHex64Digest "sourceHash"
    (← expectJsonString "sourceHash" (jsonField? fields "sourceHash" |>.getD .null))
  let semanticHash ← expectHex64Digest "semanticHash"
    (← expectJsonString "semanticHash" (jsonField? fields "semanticHash" |>.getD .null))
  let buildIdentityDigest ← expectHex64Digest "buildIdentityDigest"
    (← expectJsonString "buildIdentityDigest"
      (jsonField? fields "buildIdentityDigest" |>.getD .null))
  let planDigest ← expectHex64Digest "planDigest"
    (← expectJsonString "planDigest"
      (jsonField? fields "planDigest" |>.getD .null))
  let supportClaimDigest ← expectHex64Digest "supportClaimDigest"
    (← expectJsonString "supportClaimDigest"
      (jsonField? fields "supportClaimDigest" |>.getD .null))
  let engineeringRegistryRootDigest ← expectHex64Digest "engineeringRegistryRootDigest"
    (← expectJsonString "engineeringRegistryRootDigest"
      (jsonField? fields "engineeringRegistryRootDigest" |>.getD .null))
  let outputSetDigest ← expectHex64Digest "outputSetDigest"
    (← expectJsonString "outputSetDigest"
      (jsonField? fields "outputSetDigest" |>.getD .null))
  let evidenceSha256 ← expectHex64Digest "evidenceSha256"
    (← expectJsonString "evidenceSha256"
      (jsonField? fields "evidenceSha256" |>.getD .null))
  let deployable ← expectJsonBool "deployable"
    (jsonField? fields "deployable" |>.getD .null)
  let files ← expectFileDescriptorArrayV1 "files" (jsonField? fields "files" |>.getD .null)
  -- Public recompute of outputSetDigest from binding fields + descriptors.
  let tid ← match TargetId.parse? target with
    | some t => pure t
    | none => throw s!"target '{target}' is not a valid TargetId"
  let pid ← match CodegenProfileId.parse? codegenProfile with
    | some p => pure p
    | none => throw s!"codegenProfile '{codegenProfile}' is not a valid CodegenProfileId"
  let sourceDigest ← digestFromBareHex "sourceHash" sourceHash
  let semanticDigest ← digestFromBareHex "semanticHash" semanticHash
  let registryRootDigest ←
    digestFromBareHex "engineeringRegistryRootDigest" engineeringRegistryRootDigest
  let claimDigest ← digestFromBareHex "supportClaimDigest" supportClaimDigest
  let identityDigest ← digestFromBareHex "buildIdentityDigest" buildIdentityDigest
  let planDigestValue ← digestFromBareHex "planDigest" planDigest
  let evidenceDigest ← digestFromBareHex "evidenceSha256" evidenceSha256
  let recordedSetDigest ← digestFromBareHex "outputSetDigest" outputSetDigest
  let recomputed ← match engineeringOutputSetDigestV1
      tid pid artifactProgramName files
      sourceDigest semanticDigest
      registryRootDigest claimDigest identityDigest
      planDigestValue
      deployable
      evidenceDigest with
    | .ok d => pure d
    | .error e => throw s!"outputSetDigest recompute failed: {e}"
  unless recomputed.algorithm == recordedSetDigest.algorithm &&
      recomputed.bytes == recordedSetDigest.bytes do
    throw "outputSetDigest does not match recomputed engineering preimage"
  pure {
    target
    codegenProfile
    artifactProgramName
    sourceHash
    semanticHash
    buildIdentityDigest
    planDigest
    supportClaimDigest
    engineeringRegistryRootDigest
    outputSetDigest
    evidenceSha256
    deployable
    files
  }

/-- Validation label for inspect-output human/JSON (artifact-content + disk closure). -/
def inspectOutputValidationLabelV1 : String :=
  "structure+evidence+artifact-content+exact-disk-closure+outputSetDigest-recompute"

/-- Validate evidence.json identity fields + exact UTF-8 digest vs manifest.evidenceSha256. -/
def validateEngineeringEvidenceAgainstManifestV1
    (evidenceText : String) (manifest : InspectedOutputManifestV1) :
    Except String Unit := do
  let evidenceDigest := sha256Bytes evidenceText.toUTF8
  let recorded ← digestFromBareHex "evidenceSha256" manifest.evidenceSha256
  unless evidenceDigest.algorithm == recorded.algorithm &&
      evidenceDigest.bytes == recorded.bytes do
    throw "evidence content digest diverges from manifest evidenceSha256"
  let value ← match parseEngineeringJsonDocumentV1 evidenceText with
    | .ok v => pure v
    | .error e => throw s!"evidence is not valid JSON: {e}"
  let fields ← match jsonObjectFields? value with
    | some f => pure f
    | none => throw "evidence must be a JSON object"
  exactKeySet fields engineeringEvidenceRequiredKeysV1
  let target ← expectJsonString "target" (jsonField? fields "target" |>.getD .null)
  let sourceHash ← expectHex64Digest "sourceHash"
    (← expectJsonString "sourceHash" (jsonField? fields "sourceHash" |>.getD .null))
  let semanticHash ← expectHex64Digest "semanticHash"
    (← expectJsonString "semanticHash" (jsonField? fields "semanticHash" |>.getD .null))
  let deployable ← expectJsonBool "deployable"
    (jsonField? fields "deployable" |>.getD .null)
  let _note ← expectJsonString "note" (jsonField? fields "note" |>.getD .null)
  unless target == manifest.target do
    throw s!"evidence target '{target}' diverges from manifest '{manifest.target}'"
  unless sourceHash == manifest.sourceHash do
    throw "evidence sourceHash diverges from manifest"
  unless semanticHash == manifest.semanticHash do
    throw "evidence semanticHash diverges from manifest"
  unless deployable == manifest.deployable do
    throw "evidence deployable diverges from manifest"

private def formatFileDescriptorList (files : Array ArtifactContentDescriptorV1) : String :=
  let body := String.intercalate ", " <|
    files.toList.map fun d =>
      let role := ArtifactContentRoleV1.toWire d.role
      s!"{role}:{d.path}:{d.size}"
  s!"#[{body}]"

private def sha256WireFromBareHex (hex : String) : String :=
  "sha256:" ++ hex

/-- Product inspect-output human body. -/
def renderInspectOutputHumanV1
    (outputDir : String) (manifest : InspectedOutputManifestV1) : String :=
  String.intercalate "\n" [
    s!"outputDir={outputDir}",
    s!"schemaVersion={engineeringOutputSchemaVersionV1}",
    s!"target={manifest.target}",
    s!"codegenProfile={manifest.codegenProfile}",
    s!"artifactProgramName={manifest.artifactProgramName}",
    s!"sourceHash={sha256WireFromBareHex manifest.sourceHash}",
    s!"semanticHash={sha256WireFromBareHex manifest.semanticHash}",
    s!"buildIdentityDigest={sha256WireFromBareHex manifest.buildIdentityDigest}",
    s!"planDigest={sha256WireFromBareHex manifest.planDigest}",
    s!"supportClaimDigest={sha256WireFromBareHex manifest.supportClaimDigest}",
    s!"engineeringRegistryRootDigest={sha256WireFromBareHex manifest.engineeringRegistryRootDigest}",
    s!"outputSetDigest={sha256WireFromBareHex manifest.outputSetDigest}",
    s!"evidenceSha256={sha256WireFromBareHex manifest.evidenceSha256}",
    s!"deployable={manifest.deployable}",
    s!"files={formatFileDescriptorList manifest.files}",
    s!"validation={inspectOutputValidationLabelV1}"
  ]

/-- Product inspect-output JSON (`proof-forge.cli.inspect-output.v1`). -/
def renderInspectOutputJsonV1
    (outputDir : String) (manifest : InspectedOutputManifestV1) :
    CompileResult String := do
  let mut fileJson : Array PfJson := #[]
  for d in manifest.files do
    let contentWire ← match renderDigest d.contentSha256 with
      | .ok w => pure w
      | .error e => throw <| .registryInvalid s!"content digest render failed: {e}"
    fileJson := fileJson.push <|
      PfJson.object #[
        ("role", .string (ArtifactContentRoleV1.toWire d.role)),
        ("path", .string d.path),
        ("size", .int (Int.ofNat d.size)),
        ("contentSha256", .string contentWire)
      ]
  renderCliJsonV1 <|
    PfJson.object #[
      ("schema", .string "proof-forge.cli.inspect-output.v1"),
      ("outputDir", .string outputDir),
      ("schemaVersion", .string engineeringOutputSchemaVersionV1),
      ("target", .string manifest.target),
      ("codegenProfile", .string manifest.codegenProfile),
      ("artifactProgramName", .string manifest.artifactProgramName),
      ("sourceHash", .string (sha256WireFromBareHex manifest.sourceHash)),
      ("semanticHash", .string (sha256WireFromBareHex manifest.semanticHash)),
      ("buildIdentityDigest",
        .string (sha256WireFromBareHex manifest.buildIdentityDigest)),
      ("planDigest",
        .string (sha256WireFromBareHex manifest.planDigest)),
      ("supportClaimDigest",
        .string (sha256WireFromBareHex manifest.supportClaimDigest)),
      ("engineeringRegistryRootDigest",
        .string (sha256WireFromBareHex manifest.engineeringRegistryRootDigest)),
      ("outputSetDigest",
        .string (sha256WireFromBareHex manifest.outputSetDigest)),
      ("evidenceSha256",
        .string (sha256WireFromBareHex manifest.evidenceSha256)),
      ("deployable", .bool manifest.deployable),
      ("files", .array fileJson),
      ("validation", .string inspectOutputValidationLabelV1)
    ]

/-- Pure sidecar-text validation only (manifest structure + evidence digest/identity).

    Not a directory walk; does not take a FilePath. Full on-disk closure is
    `inspectEngineeringOutputDirV1` only. -/
private def validateEngineeringOutputSidecarTextsV1
    (manifestText : String)
    (evidenceText : String) :
    Except String InspectedOutputManifestV1 := do
  let manifest ← validateEngineeringOutputManifestTextV1 manifestText
  validateEngineeringEvidenceAgainstManifestV1 evidenceText manifest
  pure manifest

/-- Sole product API for full engineering output-dir validation.

    Stable-reads sidecars via ArtifactContentV1, parses proof-forge.output.v1
    descriptors + evidenceSha256, sole-scan exact disk closure with fixed
    sidecars, exact inventory compare to manifest descriptors. Does not forge
    FinalizedArtifactsV1. Engineering only. -/
def inspectEngineeringOutputDirV1 (outputDir : FilePath) :
    IO InspectedOutputManifestV1 := do
  let manifestText ← readStableArtifactLeafUtf8V1 outputDir manifestSidecarNameV1
  let evidenceText ← readStableArtifactLeafUtf8V1 outputDir evidenceSidecarNameV1
  let manifest ← match validateEngineeringOutputSidecarTextsV1
      manifestText evidenceText with
    | .ok m => pure m
    | .error e => throw <| IO.userError e
  -- Derive untrusted claims from manifest descriptors; sole scanner rewalks.
  let claims := manifest.files.map fun d =>
    ({ role := d.role, path := d.path } : ArtifactPathClaimV1)
  let inv ← scanArtifactContentClosureV1 outputDir claims engineeringFixedSidecarLeavesV1
  let actual := ArtifactContentInventoryV1.descriptorsOf inv
  unless actual.size == manifest.files.size do
    throw <| IO.userError
      s!"artifact content inventory size {actual.size} diverges from manifest {manifest.files.size}"
  for pair in actual.zip manifest.files do
    unless ArtifactContentDescriptorV1.beq pair.1 pair.2 do
      throw <| IO.userError
        s!"artifact content diverges from manifest at '{pair.1.path}'"
  pure manifest

/-- Whether `value` is a registered TargetId in the frozen product registry.
Used solely for `inspect <arg>` disambiguation (registry wins over path). -/
def isRegisteredInspectTargetV1 (value : String) : Bool :=
  match TargetId.parse? value with
  | none => false
  | some tid =>
      match initialTargetRegistryV1Result with
      | .error _ => false
      | .ok registry => (registrationInRegistry? registry tid).isSome

/-- Argument parser only (no seed bind). Used after seed preflight succeeds. -/
def parseCliCommandV1 (args : List String) : Except String CliCommandV1 := do
  match args with
  | "list-targets" :: rest =>
      let options ← parseListTargetsArgsExcept rest
      pure (.listTargets options)
  | "inspect" :: rest =>
      -- Explicit output-dir form (any order of --output-dir / --json).
      if rest.any (· == "--output-dir") then
        let (dir, json) ← parseInspectOutputArgsExcept rest
        pure (.inspectOutput dir json)
      else
        match rest with
        | target :: tail =>
            let json ← parseJsonOnlyArgsExcept tail
            pure (.inspect target json)
        | [] => pure .usage
  | "check" :: rest =>
      let options ← parseBuildArgsExcept rest
      let options ← validateBuildOptionsCliV1 .check options
      pure (.check options)
  | "build" :: rest =>
      let options ← parseBuildArgsExcept rest
      let options ← validateBuildOptionsCliV1 .build options
      pure (.build options)
  | _ => pure .usage

/-- Product CLI preflight: **seed first**, then parse.
- Failed seed → exact `CompileError.render` (`PF-REGISTRY-INVALID: …`) before any
  usage/target/profile parse.
- Success seed → `parseCliCommandV1` (original usage/parse diagnostics).
Returns `CliCommandV1` only — never mints `ResolvedBuildSelectionV1`.
`CLI.run` is the sole product consumer of this helper. -/
def parseCliCommandWithSeedV1
    (seed : CompileResult TargetRegistryV1)
    (args : List String) : Except String CliCommandV1 := do
  match seed with
  | .error err => throw err.render
  | .ok _registry => parseCliCommandV1 args

/-- Product preflight: frozen TargetRegistryV1 seed Result + args. -/
def parseProductCliCommandV1 (args : List String) : Except String CliCommandV1 :=
  parseCliCommandWithSeedV1 initialTargetRegistryV1Result args

end ProofForgeV2.CLI
