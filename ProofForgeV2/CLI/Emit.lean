import ProofForgeV2.Targets.Registry
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.CLI.Toolchain

namespace ProofForgeV2.CLI

open ProofForgeV2 Targets System
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1

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

private def safeRelativePath (value : String) : Bool :=
  let path := FilePath.mk value
  !value.isEmpty && value.toUTF8.size <= 240 && !path.isAbsolute &&
    !(path.components.contains "..") && !(path.components.contains ".") &&
    !value.contains "\u0000" && !value.contains "\r" && !value.contains "\n"

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

private def validateOutputSet (program : SemanticProgram) (output : OutputSet) : IO Unit := do
  unless output.manifest.sourceHash == program.sourceHash &&
      output.manifest.semanticHash == program.semanticHash do
    throw <| IO.userError "PF-OUTPUT-MANIFEST: materializer manifest does not bind the compiled program"
  unless validArtifactName program.name do
    throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe program artifact name '{program.name}'"
  let mut paths : Array String := #[]
  for file in output.files do
    unless safeRelativePath file.path do
      throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe artifact path '{file.path}'"
    if paths.contains file.path then
      throw <| IO.userError s!"PF-OUTPUT-PATH: duplicate artifact path '{file.path}'"
    paths := paths.push file.path

private structure Finalization where
  deployable : Bool
  extraFiles : Array String := #[]
  evidence : String

private def finalizeEvm (outputDir : FilePath) (programName : String) : IO Finalization := do
  let source := s!"{programName}.yul"
  let solc ← Toolchain.resolve "solc"
  let process ← solc.run #["--strict-assembly", "--bin", source] (some outputDir)
  if process.exitCode == 0 then
    let binary := (process.stdout.splitOn "Binary representation:\n").getLast!.trimAscii.copy
    if binary.isEmpty then
      throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: solc returned no bytecode"
    IO.FS.writeFile (outputDir / s!"{programName}.bin") (binary ++ "\n")
    pure {
      deployable := true
      extraFiles := #[s!"{programName}.bin"]
      evidence := s!"solc {solc.version} sha256={solc.executableSha256} completed successfully"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: solc failed\n{process.stderr}"

private def finalizeNear (outputDir : FilePath) (programName : String) : IO Finalization := do
  let source := s!"{programName}.wat"
  let target := s!"{programName}.wasm"
  let wat2wasm ← Toolchain.resolve "wat2wasm"
  let process ← wat2wasm.run #[source, "-o", target] (some outputDir)
  if process.exitCode == 0 then
    let targetPath := outputDir / target
    unless ← targetPath.pathExists do
      throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm returned no Wasm artifact"
    let metadata ← targetPath.symlinkMetadata
    unless metadata.type == .file do
      throw <| IO.userError "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm output is not a regular file"
    let wasm ← IO.FS.readBinFile targetPath
    unless wasm.size >= 8 && wasm[0]! == 0x00 && wasm[1]! == 0x61 &&
        wasm[2]! == 0x73 && wasm[3]! == 0x6d && wasm[4]! == 0x01 &&
        wasm[5]! == 0x00 && wasm[6]! == 0x00 && wasm[7]! == 0x00 do
      throw <| IO.userError
        "PF-ARTIFACT-NONDEPLOYABLE: wat2wasm output has an invalid Wasm header/version"
    pure {
      deployable := true
      extraFiles := #[target]
      evidence := s!"wat2wasm {wat2wasm.version} sha256={wat2wasm.executableSha256} completed; runtime remains separate"
    }
  else
    throw <| IO.userError s!"PF-TOOLCHAIN-MISMATCH: wat2wasm failed\n{process.stderr}"

private def finalize (kind : TargetKind) (outputDir : FilePath) (programName : String) :
    IO Finalization :=
  match kind with
  | .evm => finalizeEvm outputDir programName
  | .near => finalizeNear outputDir programName
  | .solana => pure {
      deployable := false
      evidence := "no pinned/approved sBPF assembler is configured; typed plan and IDL artifacts are non-executable"
    }
  | .noir => pure {
      deployable := false
      evidence := "no approved and digest-pinned Noir compiler/proving backend is configured; relation source/schema were emitted without ACIR, witness execution, proof, or verification"
    }
  | other => pure {
      deployable := false
      evidence := s!"{other} is research-only and has no V2 materializer"
    }

private def renderIntoStaging (selection : ResolvedBuildSelectionV1) (program : SemanticProgram)
    (output : OutputSet) (stagingDir : FilePath) : IO OutputManifest := do
  for file in output.files do
    writeFileCreatingParent (stagingDir / file.path) file.contents
  let finalization ← finalize selection.kind stagingDir program.name
  for file in finalization.extraFiles do
    unless safeRelativePath file do
      throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe finalized artifact path '{file}'"
  let manifest := {
    output.manifest with
    deployable := finalization.deployable
    files := output.manifest.files ++ finalization.extraFiles
  }
  IO.FS.writeFile (stagingDir / "manifest.json") (Targets.manifestJson manifest)
  let deployable := if manifest.deployable then "true" else "false"
  let evidence := "{\n" ++
    s!"  \"target\": \"{selection.targetId}\",\n" ++
    s!"  \"sourceHash\": \"{program.sourceHash}\",\n" ++
    s!"  \"semanticHash\": \"{program.semanticHash}\",\n" ++
    s!"  \"deployable\": {deployable},\n" ++
    s!"  \"note\": \"{Targets.escapeJson finalization.evidence}\"\n" ++
    "}\n"
  IO.FS.writeFile (stagingDir / "evidence.json") evidence
  return manifest

/-- Product emit path: dual-carrier `CompiledProgramV1` only. Residual alpha
fields (name/sourceHash/semanticHash) keep artifact bytes and manifests stable. -/
def emitProgram (selection : ResolvedBuildSelectionV1) (compiled : CompiledProgramV1)
    (outputDir : FilePath) : IO OutputManifest := do
  let program := CompiledProgramV1.alphaResidualOf compiled
  -- Reject unsafe artifact identity before entering a target materializer. A
  -- backend may impose stricter ABI identifier rules, but path safety is a CLI
  -- boundary and must retain its stable diagnostic independently of target.
  unless validArtifactName program.name do
    throw <| IO.userError s!"PF-OUTPUT-PATH: unsafe program artifact name '{program.name}'"
  let output ← match Targets.materializeResult selection compiled with
    | .ok output => pure output
    | .error error => throw <| IO.userError error.render
  validateOutputSet program output
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
    let manifest ← renderIntoStaging selection program output staging
    -- Recheck immediately before publish. This closes the cooperative writer
    -- race and ensures a build without an explicit future `--force` mode never
    -- replaces user data. A non-empty destination created by another process
    -- also makes the platform rename fail closed.
    if (← pathType? destination).isSome then
      throw <| IO.userError
        s!"PF-OUTPUT-COLLISION: output appeared during build: {destination}"
    IO.FS.rename staging destination
    return manifest
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
  | none => .error (CompileError.unknownTarget value).render

private def parseProfileExcept (value : String) : Except String CodegenProfileId :=
  match CodegenProfileId.parse? value with
  | some profile => .ok profile
  | none => .error (CompileError.unknownProfile value).render

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

/-- Resolve a build selection from CLI selection flags (same path as `build` /
`build-counter` after arg parse). Missing `--target` is a usage error. -/
def resolveSelectionFromFlags (flags : BuildSelectionCliFlags) :
    IO ResolvedBuildSelectionV1 := do
  let target ← match flags.target with
    | some target => pure target
    | none => throw <| IO.userError "--target is required"
  match resolveBuildSelectionV1 target flags.profile with
  | .ok selection => pure selection
  | .error error => throw <| IO.userError error.render

/-- One `list-targets` line: `id\tmaturityLabel`. -/
def renderListTargetLine (reg : StaticBuildRegistrationV1) : String :=
  s!"{reg.targetId}\t{reg.maturityLabel}"

/-- Pure list body against a supplied validated index (rows only). -/
def listTargetLinesInIndex (includeDesignOnly : Bool) (index : StaticBuildSelectionIndexV1) :
    Array String :=
  if includeDesignOnly then
    index.toArray.map renderListTargetLine
  else
    (implementedRegistrationsInIndex index).map renderListTargetLine

/-- DI list body over a seed Result (propagates seed errors; no capability). -/
def listTargetLinesWithSeedV1
    (seed : CompileResult StaticBuildSelectionIndexV1) (includeDesignOnly : Bool) :
    CompileResult (Array String) := do
  let index ← seed
  return listTargetLinesInIndex includeDesignOnly index

/-- Product `list-targets` body — binds frozen seed Result.
- Default: implemented-only, filter preserving canonical TargetId order.
- `--all`: full index map in canonical TargetId order (not implemented-first). -/
def listTargetLines (includeDesignOnly : Bool) : CompileResult (Array String) :=
  listTargetLinesWithSeedV1 initialStaticBuildSelectionIndexV1Result includeDesignOnly

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

/-- Implemented-registration describe join (shared by product describe + tests).
Checks residual descriptor `targetId` and `codegenProfile` against the
registration row. Design-only must not call this. -/
def describeImplementedJoin
    (reg : StaticBuildRegistrationV1) (descriptor : TargetDescriptor) :
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
  pure s!"target={reg.targetId}\nprofile={profile}\nrequirements={repr descriptor.supportedRequirements}"

/-- Describe a registration row (product join path for residual descriptors). -/
def describeRegistrationText (reg : StaticBuildRegistrationV1) : CompileResult String := do
  if reg.implemented then
    match Targets.descriptorForKind? reg.kind with
    | none =>
        throw <| .registryInvalid
          s!"implemented target '{reg.targetId}' has no residual descriptor"
    | some descriptor => describeImplementedJoin reg descriptor
  else
    pure s!"target={reg.targetId}\nstatus=research-only"

/-- DI describe body over a seed Result (propagates seed errors; no capability).
**Seed is bound first** so a failed catalog always surfaces as the seed's
`PF-REGISTRY-INVALID` even when `value` is malformed/case-invalid. Product
success-seed path still maps unknown/malformed targets to `PF-TARGET-UNKNOWN`. -/
def describeTargetWithSeedV1
    (seed : CompileResult StaticBuildSelectionIndexV1) (value : String) :
    CompileResult String := do
  let index ← seed
  let target ← match TargetId.parse? value with
    | some target => pure target
    | none => throw <| .unknownTarget value
  -- Single lookup on the bound index (no second seed bind / no double lookup).
  match registrationInIndex? index target with
  | none => throw <| .unknownTarget value
  | some reg => describeRegistrationText reg

/-- Product `describe-target` body — binds frozen seed Result. -/
def describeTargetText (value : String) : CompileResult String :=
  describeTargetWithSeedV1 initialStaticBuildSelectionIndexV1Result value

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
    (seed : CompileResult StaticBuildSelectionIndexV1)
    (args : List String) : Except String CliCommandV1 := do
  match seed with
  | .error err => throw err.render
  | .ok _index => parseCliCommandV1 args

/-- Product preflight: frozen seed Result + args. -/
def parseProductCliCommandV1 (args : List String) : Except String CliCommandV1 :=
  parseCliCommandWithSeedV1 initialStaticBuildSelectionIndexV1Result args

end ProofForgeV2.CLI
