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
    * Load `manifest.json` + require `evidence.json` as regular files.
    * Parse pretty-printed engineering JSON (whitespace-tolerant; not PF-JCS).
    * Exact key set for `proof-forge.output.v1` + schemaVersion exact.
    * Digest fields: 64-char lowercase hex; re-encode to Digest via `sha256:`.
    * files: non-empty unique relative strings; sidecars excluded.
    * evidence.json target/sourceHash/semanticHash/deployable exact match.
    * Recompute `outputSetDigest` via public `engineeringOutputSetDigestV1`
      from parsed binding fields and require byte identity with recorded digest.
    * Does NOT re-walk disk closure, re-mint OutputSet, or re-run materializers.

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

/-- Publisher-only staging render (D3/S7b + S7c + M3c OutputSet).

    Owns base-file writes, dual-defense extra-path checks, sole
    `mintEngineeringOutputSetV1` + engineering `proof-forge.output.v1`
    manifest/evidence rendering. Finalization authority (tools, deployability,
    notes) is sole Registry `finalizeMaterializedArtifactsV1` → target adapters
    → `FinalizedArtifactsV1`. Write order: base → finalize extras → mint
    OutputSet → evidence.json → manifest.json (last) → exact disk-closure
    validation before destination race recheck/rename. Not formal OutputSetV1. -/
private def renderIntoStaging (capability : Targets.ResolvedEngineeringBuildV1)
    (compiled : CompiledSemanticV1) (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EmitReceiptV1 := do
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
  let outputSet ← match mintEngineeringOutputSetV1 finalized with
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
  -- S7c: evidence before manifest; manifest is the last file write.
  IO.FS.writeFile (stagingDir / "evidence.json") evidence
  IO.FS.writeFile (stagingDir / "manifest.json") manifest
  -- Exact disk closure after manifest and before destination race recheck/rename.
  validateEngineeringDiskClosureV1 finalized stagingDir
  return {
    target := EngineeringOutputSetV1.targetIdOf outputSet
    codegenProfile := EngineeringOutputSetV1.codegenProfileOf outputSet
    deployable := EngineeringOutputSetV1.deployableOf outputSet
  }

/-- Product emit path: private engineering capability only.
    Mints engineering `EngineeringOutputSetV1` after finalization and publishes
    `proof-forge.output.v1` manifest + evidence sidecars. No public
    `(selection, compiled)` overload. Not formal OutputSetV1. -/
def emitProgram (capability : Targets.ResolvedEngineeringBuildV1)
    (outputDir : FilePath) : IO EmitReceiptV1 := do
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
    let receipt ← renderIntoStaging capability compiled artifacts staging
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
at product path: `build/v2` and `.`). `json` selects PF-JCS stdout. -/
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
  deriving Repr

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

/-- Shared build/check argument parser (pure Except).
`--network` and any other unknown dashed option fail as usage errors.
`--json` is a bare flag. Duplicate selection and common flags fail closed. -/
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

/-- Product check success JSON (`proof-forge.cli.check.v1`). -/
def renderCheckOkJsonV1
    (programName : String) (sourceDigest semanticDigest : Digest)
    (target? : Option TargetId) (profile? : Option CodegenProfileId) :
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
  renderCliJsonV1 <|
    PfJson.object #[
      ("schema", .string "proof-forge.cli.check.v1"),
      ("ok", .bool true),
      ("program", .string programName),
      ("sourceDigest", .string sourceWire),
      ("semanticDigest", .string semanticWire),
      ("target", targetJson),
      ("codegenProfile", profileJson)
    ]

/-- Product build success human body (includes selected profile). -/
def renderBuildOkHumanV1 (receipt : EmitReceiptV1) : String :=
  s!"built target={receipt.target} profile={receipt.codegenProfile} deployable={receipt.deployable}"

/-- Product build success JSON (`proof-forge.cli.build.v1`). -/
def renderBuildOkJsonV1 (receipt : EmitReceiptV1) : CompileResult String :=
  renderCliJsonV1 <|
    PfJson.object #[
      ("schema", .string "proof-forge.cli.build.v1"),
      ("target", .string receipt.target.toString),
      ("codegenProfile", .string receipt.codegenProfile.toString),
      ("deployable", .bool receipt.deployable)
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
  deployable : Bool
  files : Array String
  deriving BEq, Repr

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
  "deployable",
  "files"
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
  -- Engineering sidecars only use booleans for non-string scalars; reject
  -- non-zero integers so deployable cannot be smuggled as 0/1.
  let mut value : Nat := 0
  for d in digits do
    value := value * 10 + (d.toNat - '0'.toNat)
  if negative && value = 0 then
    throw "json forbids negative zero"
  if value ≠ 0 then
    throw "json integer non-zero is not accepted in engineering sidecars"
  pure (.int 0, rest)

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

private def expectJsonStringArray (label : String) (value : PfJson) :
    Except String (Array String) := do
  match value with
  | .array values =>
      let mut out : Array String := #[]
      for v in values do
        match v with
        | .string s => out := out.push s
        | _ => throw s!"{label} must be an array of strings"
      pure out
  | _ => throw s!"{label} must be an array"

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

/-- Validate on-disk `manifest.json` body into a typed carrier.
Structure + hex format + public `engineeringOutputSetDigestV1` recompute. -/
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
  let deployable ← expectJsonBool "deployable"
    (jsonField? fields "deployable" |>.getD .null)
  let files ← expectJsonStringArray "files" (jsonField? fields "files" |>.getD .null)
  if files.isEmpty then throw "files must be non-empty"
  let mut seen : Array String := #[]
  for path in files do
    if path.isEmpty then throw "files entries must be nonempty"
    if path == evidenceSidecarNameV1 || path == manifestSidecarNameV1 then
      throw "sidecars must not appear in files"
    unless safeRelativeArtifactPathV1 path do
      throw s!"unsafe artifact path '{path}'"
    if seen.contains path then throw s!"duplicate file path '{path}'"
    seen := seen.push path
  -- Public recompute of outputSetDigest from binding fields.
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
  let recordedSetDigest ← digestFromBareHex "outputSetDigest" outputSetDigest
  let recomputed ← match engineeringOutputSetDigestV1
      tid pid artifactProgramName files
      sourceDigest semanticDigest
      registryRootDigest claimDigest identityDigest
      planDigestValue
      deployable with
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
    deployable
    files
  }

/-- Validate evidence.json and cross-check identity fields against the manifest. -/
def validateEngineeringEvidenceAgainstManifestV1
    (evidenceText : String) (manifest : InspectedOutputManifestV1) :
    Except String Unit := do
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

private def formatFileList (files : Array String) : String :=
  let body := String.intercalate ", " files.toList
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
    s!"deployable={manifest.deployable}",
    s!"files={formatFileList manifest.files}",
    "validation=structure+evidence+digest-format+outputSetDigest-recompute"
  ]

/-- Product inspect-output JSON (`proof-forge.cli.inspect-output.v1`). -/
def renderInspectOutputJsonV1
    (outputDir : String) (manifest : InspectedOutputManifestV1) :
    CompileResult String :=
  let fileJson := manifest.files.map PfJson.string
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
      ("deployable", .bool manifest.deployable),
      ("files", .array fileJson),
      ("validation",
        .string "structure+evidence+digest-format+outputSetDigest-recompute")
    ]

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
      pure (.check options)
  | "build" :: rest =>
      let options ← parseBuildArgsExcept rest
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
