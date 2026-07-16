import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader

namespace ProofForgeV2.CLI

open ProofForgeV2 System

private def usage : String :=
  "ProofForge V2 alpha\n\n" ++
  "Usage:\n" ++
  "  proof-forge-next list-targets\n" ++
  "  proof-forge-next describe-target <target>\n" ++
  "  proof-forge-next build <source.lean> --target <target> [-o <dir>] [--program <Name>] [--root <dir>]\n" ++
  "  proof-forge-next build-counter --target <target> [-o <dir>]\n"

private structure BuildOptions where
  source : Option String := none
  target : Option TargetId := none
  output : String := "build/v2"
  programName : Option String := none
  root : String := "."

private def parseTarget (value : String) : IO TargetId :=
  match TargetId.parse? value with
  | some target => pure target
  | none => throw <| IO.userError <| (CompileError.unknownTarget value).render

private partial def parseBuildArgs (args : List String) (options : BuildOptions := {}) : IO BuildOptions := do
  match args with
  | [] => pure options
  | "--target" :: value :: rest => parseBuildArgs rest { options with target := some (← parseTarget value) }
  | "-o" :: value :: rest | "--output" :: value :: rest => parseBuildArgs rest { options with output := value }
  | "--program" :: value :: rest => parseBuildArgs rest { options with programName := some value }
  | "--root" :: value :: rest => parseBuildArgs rest { options with root := value }
  | value :: rest =>
      if value.startsWith "-" then
        throw <| IO.userError s!"unknown option '{value}'"
      else if options.source.isSome then
        throw <| IO.userError "only one source file may be compiled"
      else
        parseBuildArgs rest { options with source := some value }

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

private unsafe def buildSource (options : BuildOptions) : IO Unit := do
  let target ← match options.target with
    | some target => pure target
    | none => throw <| IO.userError "--target is required"
  let source ← match options.source with
    | some source => pure source
    | none => throw <| IO.userError "source file is required"
  validateSourceArgument source
  let root := FilePath.mk options.root
  unless ← root.pathExists do
    throw <| IO.userError s!"root directory not found: {root}"
  let sourcePath ← ensureContainedSource root (FilePath.mk source)
  let sourceText ← IO.FS.readFile sourcePath
  let sourceProgram ← liftCompileResult (←
    Language.Loader.selectProgram sourceText sourcePath.toString options.programName)
  let semanticProgram ← liftCompileResult (Compiler.compile sourceProgram)
  let requestedOutput := FilePath.mk options.output
  let outputPath := if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
  let manifest ← emitProgram target semanticProgram outputPath
  IO.println s!"built target={manifest.target} deployable={manifest.deployable}"

private def buildCounter (options : BuildOptions) : IO Unit := do
  let target ← match options.target with
    | some target => pure target
    | none => throw <| IO.userError "--target is required"
  let outputDir := FilePath.mk options.output
  let semanticProgram ← liftCompileResult (Compiler.compile Examples.counter)
  let manifest ← emitProgram target semanticProgram outputDir
  IO.println s!"built Counter target={manifest.target} deployable={manifest.deployable}"

private def listTargets : IO Unit := do
  for target in Targets.phase1 do
    IO.println s!"{target}\t{Targets.maturity target}"
  for target in Targets.researched do
    IO.println s!"{target}\tresearch-only"

private def describeTarget (value : String) : IO Unit := do
  let target ← parseTarget value
  match Targets.descriptor? target with
  | some descriptor =>
      IO.println s!"target={target}\nprofile={descriptor.codegenProfile}\nrequirements={repr descriptor.supportedRequirements}"
  | none => IO.println s!"target={target}\nstatus=research-only"

unsafe def run (args : List String) : IO Unit := do
  match args with
  | ["list-targets"] => listTargets
  | ["describe-target", target] => describeTarget target
  | "build" :: rest => buildSource (← parseBuildArgs rest)
  | "build-counter" :: rest => buildCounter (← parseBuildArgs rest)
  | _ => IO.println usage

end ProofForgeV2.CLI

unsafe def main (args : List String) : IO Unit := ProofForgeV2.CLI.run args
