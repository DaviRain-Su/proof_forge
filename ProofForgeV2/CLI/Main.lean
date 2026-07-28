import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader
import ProofForgeV2.Targets.BuildSelectionV1

namespace ProofForgeV2.CLI

open ProofForgeV2 System
open ProofForgeV2.Targets.BuildSelectionV1

private def usage : String :=
  "ProofForge V2 alpha\n\n" ++
  "Usage:\n" ++
  "  proof-forge-next list-targets [--all]\n" ++
  "  proof-forge-next describe-target <target>\n" ++
  "  proof-forge-next build <source.lean> --module <Lean.Name> --target <target> [-o <dir>] [--program <Name>] [--root <dir>] [--profile <id>]\n" ++
  "  proof-forge-next build-counter --target <target> [-o <dir>] [--profile <id>]\n"

private def validateSourceArgument (source : String) : IO Unit := do
  unless source.endsWith ".lean" do
    throw <| IO.userError "source path must end in .lean"
  unless !source.startsWith "/" && !(source.splitOn "/").contains ".." do
    throw <| IO.userError "source path must be relative to --root and cannot traverse parents"

private def ensureContainedSource (root source : FilePath) : IO FilePath := do
  let rootPath ← IO.FS.realPath root
  let sourcePath ← IO.FS.realPath (root / source)
  let pathPrefix := rootPath.toString ++ "/"
  unless sourcePath.toString.startsWith pathPrefix do
    throw <| IO.userError "source symlink escapes --root"
  return sourcePath

private def liftCompileResult (result : Except CompileError α) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => throw <| IO.userError error.render

private def liftExcept (result : Except String α) : IO α :=
  match result with
  | .ok value => pure value
  | .error msg => throw <| IO.userError msg

private unsafe def buildSource (options : BuildOptions) : IO Unit := do
  let selection ← resolveSelectionFromFlags
    { target := options.target, profile := options.profile }
  let source ← match options.source with
    | some source => pure source
    | none => throw <| IO.userError "source file is required"
  let moduleName ← match options.moduleName with
    | some moduleName => pure moduleName
    | none => throw <| IO.userError "--module is required for canonical ProgramV1 identity"
  validateSourceArgument source
  let root := FilePath.mk (options.root.getD ".")
  unless ← root.pathExists do
    throw <| IO.userError s!"root directory not found: {root}"
  let sourcePath ← ensureContainedSource root (FilePath.mk source)
  let sourceText ← IO.FS.readFile sourcePath
  let sourceProgram ← liftCompileResult (←
    Language.Loader.selectProgramV1 sourceText sourcePath.toString moduleName
      options.programName)
  let semanticProgram ← liftCompileResult
    (Compiler.compileValidatedSourceV1 sourceProgram)
  let requestedOutput := FilePath.mk (options.output.getD "build/v2")
  let outputPath := if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
  let manifest ← emitProgram selection semanticProgram outputPath
  IO.println s!"built target={manifest.target} deployable={manifest.deployable}"

private unsafe def buildCounter (options : BuildOptions) : IO Unit := do
  let selection ← resolveSelectionFromFlags
    { target := options.target, profile := options.profile }
  let outputDir := FilePath.mk (options.output.getD "build/v2")
  let sourceProgram ← liftCompileResult (← Language.Loader.selectProgramV1
    Examples.counterSourceText "<built-in-counter>" Examples.counterModuleNameV1 none)
  let semanticProgram ← liftCompileResult
    (Compiler.compileValidatedSourceV1 sourceProgram)
  let manifest ← emitProgram selection semanticProgram outputDir
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
  match ← liftExcept (parseProductCliCommandV1 args) with
  | .listTargets includeDesignOnly => listTargets includeDesignOnly
  | .describeTarget target => describeTarget target
  | .build options => buildSource options
  | .buildCounter options => buildCounter options
  | .usage => IO.println usage

end ProofForgeV2.CLI

unsafe def main (args : List String) : IO Unit := ProofForgeV2.CLI.run args
