import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.BuildSelectionV1

namespace ProofForgeV2.CLI

open ProofForgeV2 System
open ProofForgeV2.Core.DiagnosticBundleV1
open ProofForgeV2.Targets.BuildSelectionV1

private def usage : String :=
  "ProofForge V2 alpha\n\n" ++
  "Usage:\n" ++
  "  proof-forge-next list-targets [--all]\n" ++
  "  proof-forge-next describe-target <target>\n" ++
  "  proof-forge-next build <source.lean> --module <Lean.Name> --target <target> [-o <dir>] [--program <Name>] [--root <dir>] [--profile <id>]\n" ++
  "  proof-forge-next build-counter --target <target> [-o <dir>] [--profile <id>]\n"

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

private def validateSourceArgument (source : String) : IO Unit := do
  unless source.endsWith ".lean" do
    failUsage "source path must end in .lean"
  unless !source.startsWith "/" && !(source.splitOn "/").contains ".." do
    failUsage "source path must be relative to --root and cannot traverse parents"

private def ensureContainedSource (root source : FilePath) : IO FilePath := do
  let rootPath ← IO.FS.realPath root
  let sourcePath ← IO.FS.realPath (root / source)
  let pathPrefix := rootPath.toString ++ "/"
  unless sourcePath.toString.startsWith pathPrefix do
    failUsage "source symlink escapes --root"
  return sourcePath

private def liftCompileResult (result : Except CompileError α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

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
  let source ← match options.source with
    | some source => pure source
    | none => failUsage "source file is required"
  let moduleName ← match options.moduleName with
    | some moduleName => pure moduleName
    | none => failUsage "--module is required for canonical ProgramV1 identity"
  validateSourceArgument source
  let root := FilePath.mk (options.root.getD ".")
  unless ← root.pathExists do
    failUsage s!"root directory not found: {root}"
  let sourcePath ← ensureContainedSource root (FilePath.mk source)
  let sourceText ← IO.FS.readFile sourcePath
  match ← Language.Loader.selectProgramV1Product
      sourceText source moduleName options.programName with
  | .error bundle => failBundle bundle
  | .ok (sourceProgram, origins) =>
      match Compiler.compileProgramProductV1 sourceProgram origins with
      | .error bundle => failBundle bundle
      | .ok compiled =>
          -- Product phase: located compile → exact requirement capability →
          -- emit/finalize/disk closure. Resolver precedes output staging.
          let capability ← liftCompileResult
            (Targets.resolveEngineeringRequirementsV1 selection compiled)
          let requestedOutput := FilePath.mk (options.output.getD "build/v2")
          let outputPath :=
            if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
          let manifest ← emitProgram capability outputPath
          IO.println s!"built target={manifest.target} deployable={manifest.deployable}"

private unsafe def buildCounter (options : BuildOptions) : IO Unit := do
  let selection ← resolveBuildSelectionForCli options
  match ← Language.Loader.selectProgramV1Product
      Examples.counterSourceText counterLogicalSourcePath
      Examples.counterModuleNameV1 none with
  | .error bundle => failBundle bundle
  | .ok (sourceProgram, origins) =>
      match Compiler.compileProgramProductV1 sourceProgram origins with
      | .error bundle => failBundle bundle
      | .ok compiled =>
          -- Resolver before output staging.
          let capability ← liftCompileResult
            (Targets.resolveEngineeringRequirementsV1 selection compiled)
          let outputDir := FilePath.mk (options.output.getD "build/v2")
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
