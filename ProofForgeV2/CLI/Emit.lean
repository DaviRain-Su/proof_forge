import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Targets.TargetRegistryV1
import ProofForgeV2.Targets.RequirementResolverV1
import ProofForgeV2.Materialization.MaterializedArtifactsV1
import ProofForgeV2.Materialization.EngineeringFinalizationV1
import ProofForgeV2.Materialization.EngineeringDiskClosureV1
import ProofForgeV2.Compiler.Pipeline

namespace ProofForgeV2.CLI

open ProofForgeV2 Targets System
open ProofForgeV2.Core.Common
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.TargetRegistryV1
open ProofForgeV2.Targets.RequirementResolverV1

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

/-- Private legacy-engineering on-disk v2alpha1 field bag (CLI publisher only).
    Not a public product carrier; exact wire bytes match pre-S7a `manifestJson`. -/
private structure LegacyOutputManifestV2Alpha1 where
  schemaVersion : String := "proof-forge-output/v2alpha1"
  target : TargetId
  codegenProfile : CodegenProfileId
  sourceHash : String
  semanticHash : String
  deployable : Bool
  files : Array String

/-- Private legacy-engineering renderer — byte-identical to pre-S7a public
    `Targets.manifestJson` for `proof-forge-output/v2alpha1`. -/
private def renderLegacyManifestJsonV2Alpha1 (manifest : LegacyOutputManifestV2Alpha1) :
    String :=
  let files := String.intercalate "," <|
    manifest.files.toList.map fun path => s!"\"{Targets.escapeJson path}\""
  let deployable := if manifest.deployable then "true" else "false"
  "{\n" ++
    s!"  \"schemaVersion\": \"{manifest.schemaVersion}\",\n" ++
    s!"  \"target\": \"{manifest.target}\",\n" ++
    s!"  \"codegenProfile\": \"{Targets.escapeJson manifest.codegenProfile.toString}\",\n" ++
    s!"  \"sourceHash\": \"{manifest.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{manifest.semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"files\": [{files}]\n" ++
    "}\n"

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

/-- Publisher-only staging render (D3/S7b + S7c).

    Owns base-file writes, dual-defense extra-path checks, private v2alpha1
    manifest/evidence rendering from finalized-carrier fields only. Finalization
    authority (tools, deployability, notes) is sole Registry
    `finalizeMaterializedArtifactsV1` → target adapters → `FinalizedArtifactsV1`.
    Write order: base → finalize extras → evidence.json → manifest.json (last) →
    exact disk-closure validation before destination race recheck/rename. -/
private def renderIntoStaging (capability : Targets.ResolvedEngineeringBuildV1)
    (compiled : CompiledSemanticV1) (artifacts : MaterializedArtifactsV1)
    (stagingDir : FilePath) : IO EmitReceiptV1 := do
  let selection := Targets.ResolvedEngineeringBuildV1.selectionOf capability
  let sourceHash ← digestHexForOutputV1 "source" (CompiledSemanticV1.sourceDigestOf compiled)
  let semanticHash ← digestHexForOutputV1 "semantic" (CompiledSemanticV1.semanticDigestOf compiled)
  for file in MaterializedArtifactsV1.filesOf artifacts do
    writeFileCreatingParent (stagingDir / file.path) file.contents
  let finalized ← Targets.finalizeMaterializedArtifactsV1 capability artifacts stagingDir
  let basePaths :=
    (MaterializedArtifactsV1.filesOf artifacts).map (·.path)
  -- Dual-defense: safety + uniqueness vs base + uniqueness among extras.
  validateFinalizedExtraPathsForPublishV1 basePaths
    (FinalizedArtifactsV1.extraFilesOf finalized)
  let manifest : LegacyOutputManifestV2Alpha1 := {
    target := MaterializedArtifactsV1.targetIdOf artifacts
    codegenProfile := MaterializedArtifactsV1.codegenProfileIdOf artifacts
    sourceHash
    semanticHash
    deployable := FinalizedArtifactsV1.deployableOf finalized
    files := basePaths ++ FinalizedArtifactsV1.extraFilesOf finalized
  }
  let deployable := if manifest.deployable then "true" else "false"
  let evidence := "{\n" ++
    s!"  \"target\": \"{selection.targetId}\",\n" ++
    s!"  \"sourceHash\": \"{sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"note\": \"{Targets.escapeJson (FinalizedArtifactsV1.evidenceNoteOf finalized)}\"\n" ++
    "}\n"
  -- S7c: evidence before manifest; manifest is the last file write.
  IO.FS.writeFile (stagingDir / "evidence.json") evidence
  IO.FS.writeFile (stagingDir / "manifest.json") (renderLegacyManifestJsonV2Alpha1 manifest)
  -- Exact disk closure after manifest and before destination race recheck/rename.
  validateEngineeringDiskClosureV1 finalized stagingDir
  return {
    target := manifest.target
    codegenProfile := manifest.codegenProfile
    deployable := manifest.deployable
  }

/-- Product emit path: private engineering capability only.
    Source/semantic hash fields are derived from the single non-alpha compiled
    carrier for the private v2alpha1 renderer. No public `(selection, compiled)`
    overload. Formal OutputSetV1 remains pending. -/
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

/-- Full build/build-counter option bag (CLI internal + test-facing parse).
`output`/`root` are `Option` so duplicate flags are detectable (defaults applied
at product path: `build/v2` and `.`). -/
structure BuildOptions where
  source : Option String := none
  target : Option TargetId := none
  profile : Option CodegenProfileId := none
  output : Option String := none
  moduleName : Option String := none
  programName : Option String := none
  root : Option String := none
  deriving Repr

/-- Selection-relevant CLI flags exposed for focused tests. -/
structure BuildSelectionCliFlags where
  target : Option TargetId := none
  profile : Option CodegenProfileId := none
  deriving BEq, Repr

/-- Typed product CLI command surface. `CLI.run` matches only this enum. -/
inductive CliCommandV1 where
  | listTargets (includeDesignOnly : Bool)
  | describeTarget (target : String)
  | build (options : BuildOptions)
  | buildCounter (options : BuildOptions)
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

/-- Shared build/build-counter argument parser (pure Except).
`--network` and any other unknown dashed option fail as usage errors.
Duplicate selection and common flags fail closed with stable messages. -/
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

/-- Test-facing parse of build/build-counter args for selection fields. -/
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

/-- Parse `list-targets` trailing args (pure). -/
def parseListTargetsArgsExcept (args : List String) : Except String Bool :=
  match args with
  | [] => .ok false
  | ["--all"] => .ok true
  | other =>
      .error s!"unknown list-targets argument '{String.intercalate " " other}'"

def parseListTargetsArgs (args : List String) : IO Bool :=
  match parseListTargetsArgsExcept args with
  | .ok b => pure b
  | .error msg => throw <| IO.userError msg

/-- Format exact S2 request identities for describe-target product text. -/
private def formatS2RequirementIds (ids : Array String) : String :=
  let body := String.intercalate ", " ids.toList
  s!"#[{body}]"

/-- Implemented-registration describe join (shared by product describe + tests).
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

/-- Describe a registration row (product join path for residual descriptors). -/
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
  -- Single lookup on the bound registry (no second seed bind / no double lookup).
  match registrationInRegistry? registry target with
  | none => throw <| .unknownTarget value
  | some reg => describeRegistrationText reg

/-- Product `describe-target` body — binds frozen TargetRegistryV1 seed. -/
def describeTargetText (value : String) : CompileResult String :=
  describeTargetWithSeedV1 initialTargetRegistryV1Result value

/-- Argument parser only (no seed bind). Used after seed preflight succeeds. -/
def parseCliCommandV1 (args : List String) : Except String CliCommandV1 := do
  match args with
  | "list-targets" :: rest =>
      let includeAll ← parseListTargetsArgsExcept rest
      pure (.listTargets includeAll)
  | ["describe-target", target] => pure (.describeTarget target)
  | "build" :: rest =>
      let options ← parseBuildArgsExcept rest
      pure (.build options)
  | "build-counter" :: rest =>
      let options ← parseBuildArgsExcept rest
      pure (.buildCounter options)
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
