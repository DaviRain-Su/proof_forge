import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Core.DiagnosticV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Frontend.ProtocolV1
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.BuildSelectionV1

namespace ProofForgeV2.CLI

open ProofForgeV2 System
open ProofForgeV2.Core.Common
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Core.DiagnosticV1
open ProofForgeV2.Frontend.ProtocolV1
open ProofForgeV2.Source.OriginJoinV1
open ProofForgeV2.Source.ValidatedSourceV1
open ProofForgeV2.Targets.BuildSelectionV1

private def usage : String :=
  "ProofForge V2 alpha\n\n" ++
  "Usage:\n" ++
  "  proof-forge-next list-targets [--all]\n" ++
  "  proof-forge-next describe-target <target>\n" ++
  "  proof-forge-next build <source.lean> --module <Lean.Name> --target <target> [-o <dir>] [--program <Name>] [--root <dir>] [--profile <id>] [--language-version <semver>]\n" ++
  "  proof-forge-next build-counter --target <target> [-o <dir>] [--profile <id>] [--language-version <semver>]\n"

/-- Stable project-relative path for the built-in Counter diagnostic origins. -/
private def counterLogicalSourcePath : String := "Examples/Counter.lean"

/-- CLI usage/config failure: plain stderr and exit 2, not a diagnostic bundle. -/
private def failUsage (message : String) : IO α := do
  IO.eprintln message
  IO.Process.exit 2

/-- Product source/type/effect failure: full human bundle and catalog exit code. -/
private def failBundle (bundle : DiagnosticBundleV1) : IO α := do
  let text := DiagnosticBundleV1.renderHuman bundle
  unless text.isEmpty do
    IO.eprintln text
  let code := DiagnosticBundleV1.selectExitCode bundle
  let exitByte : UInt8 := if code ≥ 256 then 70 else UInt8.ofNat code
  IO.Process.exit exitByte

private def validateSourceArgument (source : String) : IO ProjectRelativePath := do
  unless source.endsWith ".lean" do
    failUsage "source path must end in .lean"
  match parseProjectRelativePath source with
  | .ok path => pure path
  | .error _ =>
      failUsage "source path must be a canonical project-relative path under --root"

/-- Resolve only the caller-selected trusted root lexically. Source lookup is
    performed by the in-process Loader under this root. -/
private def resolveProjectRoot (value : String) : IO FilePath := do
  if value.isEmpty || value.toList.any (· == '\x00') then
    failUsage "--root must be a nonempty filesystem path"
  let cwd ← IO.currentDir
  if value == "." then
    return cwd
  let input := FilePath.mk value
  if input.isAbsolute then
    if value == "/" then
      return input
    let tail := String.intercalate "/" ((value.splitOn "/").drop 1)
    match parseProjectRelativePath tail with
    | .error _ =>
        failUsage "absolute --root must use canonical non-dot path components"
    | .ok canonical =>
        let rendered ← match renderProjectRelativePath canonical with
          | .ok rendered => pure rendered
          | .error _ => failUsage "absolute --root is not canonical"
        return FilePath.mk ("/" ++ rendered)
  match parseProjectRelativePath value with
  | .error _ =>
      failUsage "relative --root must be a canonical project-relative path or ."
  | .ok canonical =>
      let rendered ← match renderProjectRelativePath canonical with
        | .ok rendered => pure rendered
        | .error _ => failUsage "relative --root is not canonical"
      pure (cwd / FilePath.mk rendered)

private partial def absolutePathChain (path : FilePath) : List FilePath :=
  match path.parent with
  | none => [path]
  | some parent =>
      if parent == path then [path]
      else absolutePathChain parent ++ [path]

/-- Validate the physical compiler location without following a caller-provided
    symlink. This is an engineering pin, not a formal executable digest. -/
private def checkedCompilerBinDir : IO FilePath := do
  let appPath := ← IO.appPath
  unless appPath.isAbsolute do
    failUsage "compiler executable path is not absolute"
  for component in absolutePathChain appPath do
    let metadata ← try component.symlinkMetadata
      catch _ => failUsage "compiler executable path metadata is unavailable"
    if metadata.type == .symlink then
      failUsage "compiler executable path contains a symbolic link"
  let appMetadata ← try appPath.symlinkMetadata
    catch _ => failUsage "compiler executable metadata is unavailable"
  unless appMetadata.type == .file do
    failUsage "compiler executable is not a regular file"
  match appPath.parent with
  | some parent => pure parent
  | none => failUsage "compiler executable has no package bin directory"

private def builtInSourceRoot : IO FilePath := do
  let binDir ← checkedCompilerBinDir
  unless binDir.fileName == some "bin" do
    failUsage "built-in Counter source is unavailable in this installation"
  let buildDir ← match binDir.parent with
    | some parent => pure parent
    | none => failUsage "built-in Counter source is unavailable in this installation"
  unless buildDir.fileName == some "build" do
    failUsage "built-in Counter source is unavailable in this installation"
  let lakeDir ← match buildDir.parent with
    | some parent => pure parent
    | none => failUsage "built-in Counter source is unavailable in this installation"
  unless lakeDir.fileName == some ".lake" do
    failUsage "built-in Counter source is unavailable in this installation"
  match lakeDir.parent with
  | some root => pure root
  | none => failUsage "built-in Counter source is unavailable in this installation"

private def sourceStartOrigin (sourcePath : ProjectRelativePath) : DiagnosticOriginV1 := {
  sourcePath
  startByte := 0
  endByte := 0
  nodeId := none
}

private def failFrontendDiagnostic
    (sourcePath : ProjectRelativePath)
    (code : DiagnosticCodeV1)
    (message expected actual stableClass : String) : IO α := do
  let diagnostic := DiagnosticV1.make code message
    (primary := some (sourceStartOrigin sourcePath))
    (expected := some (PfJson.string expected))
    (actual := some (PfJson.string actual))
    (stableContext := some stableClass)
  failBundle (mkFailureBundleV1 #[diagnostic])

/-- Sole CLI source authority: in-process Loader read of the source file
    under the resolved project root. Product compilation consumes the
    reconstructed ValidatedSourceV1 + OriginInventoryV1 pair. -/
private unsafe def loadSourceProduct
    (projectRoot : FilePath)
    (sourcePath : ProjectRelativePath)
    (moduleSelector : String)
    (programSelector : Option String) :
    IO (ValidatedSourceV1 × OriginInventoryV1) := do
  let logicalPath ← match renderProjectRelativePath sourcePath with
    | .ok path => pure path
    | .error _ => failUsage "source path is not canonical"
  let sourceFile := projectRoot / FilePath.mk logicalPath
  let source ← IO.FS.readFile sourceFile
  match ← ProofForgeV2.Language.Loader.selectProgramV1Product
      source logicalPath moduleSelector programSelector with
  | .error bundle => failBundle bundle
  | .ok product => pure product

private def liftCompileResult (result : Except CompileError α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def resolveLanguageVersionForCli (requested : Option String) : IO SemVer :=
  match resolveLanguageParserDescriptorV1 requested with
  | .ok descriptor => pure (LanguageParserDescriptorV1.version descriptor)
  | .error diagnostic => failBundle (mkFailureBundleV1 #[diagnostic])

/-- Build argv selection. An ID absent from the frozen target catalog is a
usage/config error; registered design-only targets and profile-selection
failures remain typed product-selection errors. -/
private def resolveBuildSelectionForCli (options : BuildOptions) : IO ResolvedBuildSelectionV1 := do
  let target ← match options.target with
    | some target => pure target
    | none => failUsage "--target is required"
  match resolveBuildSelectionV1 target options.profile with
  | .ok selection => pure selection
  | .error (.unknownTarget input) => failUsage s!"unknown target '{input}'"
  | .error error => throw <| IO.userError error.render

private unsafe def buildSource (options : BuildOptions) : IO Unit := do
  let selection ← resolveBuildSelectionForCli options
  let languageVersion ← resolveLanguageVersionForCli options.languageVersion
  let source ← match options.source with
    | some source => pure source
    | none => failUsage "source file is required"
  let moduleName ← match options.moduleName with
    | some moduleName => pure moduleName
    | none => failUsage "--module is required for canonical ProgramV1 identity"
  let sourcePath ← validateSourceArgument source
  let root ← resolveProjectRoot (options.root.getD ".")
  let (sourceProgram, origins) ←
    loadSourceProduct root sourcePath moduleName options.programName
  match Compiler.compileProgramProductV1 sourceProgram origins with
  | .error bundle => failBundle bundle
  | .ok compiled =>
      -- Product phase: in-process Loader read → located compile → exact
      -- requirement capability → emit/finalize/disk closure.
      let capability ← liftCompileResult
        (Targets.resolveEngineeringRequirementsV1 selection compiled)
      let requestedOutput := FilePath.mk (options.output.getD "build/v2")
      let outputPath :=
        if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
      let manifest ← emitProgram capability outputPath
      IO.println s!"built target={manifest.target} deployable={manifest.deployable}"

private unsafe def buildCounter (options : BuildOptions) : IO Unit := do
  let selection ← resolveBuildSelectionForCli options
  let languageVersion ← resolveLanguageVersionForCli options.languageVersion
  let root ← builtInSourceRoot
  let sourcePath ← validateSourceArgument counterLogicalSourcePath
  let (sourceProgram, origins) ←
    loadSourceProduct root sourcePath Examples.counterModuleNameV1 none
  match Compiler.compileProgramProductV1 sourceProgram origins with
  | .error bundle => failBundle bundle
  | .ok compiled =>
      -- Resolver before output staging.
      let capability ← liftCompileResult
        (Targets.resolveEngineeringRequirementsV1 selection compiled)
      let requestedOutput := FilePath.mk (options.output.getD "build/v2")
      let outputDir :=
        if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
      let manifest ← emitProgram capability outputDir
      IO.println s!"built Counter target={manifest.target} deployable={manifest.deployable}"

private def listTargets (includeDesignOnly : Bool) : IO Unit := do
  let lines ← liftCompileResult (listTargetLines includeDesignOnly)
  for line in lines do
    IO.println line

private def describeTarget (value : String) : IO Unit := do
  IO.println (← liftCompileResult (describeTargetText value))

/-- Product CLI entry. Sole dispatcher: `parseProductCliCommandV1` =
seed-first preflight (`parseCliCommandWithSeedV1` on frozen seed) then
`parseCliCommandV1`. Does not mint selection capability; bodies bind seed again. -/
unsafe def run (args : List String) : IO Unit := do
  match parseProductCliCommandV1 args with
  | .error msg => failUsage msg
  | .ok command =>
      match command with
      | .listTargets includeDesignOnly => listTargets includeDesignOnly
      | .describeTarget target => describeTarget target
      | .build options => buildSource options
      | .buildCounter options => buildCounter options
      | .usage => failUsage usage

end ProofForgeV2.CLI

-- Top-level `main` lives in `ProofForgeV2.CLI.Exe` (lean_exe root) so this
-- module can be imported by library/tests without colliding with test mains.
