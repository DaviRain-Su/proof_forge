import ProofForgeV2.CLI.Emit
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Core.DiagnosticBundleV1
import ProofForgeV2.Examples.Counter
import ProofForgeV2.Language.Loader

namespace ProofForgeV2.CLI

open ProofForgeV2 System
open ProofForgeV2.Core.DiagnosticBundleV1

private def usage : String :=
  "ProofForge V2 alpha\n\n" ++
  "Usage:\n" ++
  "  proof-forge-next list-targets\n" ++
  "  proof-forge-next describe-target <target>\n" ++
  "  proof-forge-next build <source.lean> --module <Lean.Name> --target <target> [-o <dir>] [--program <Name>] [--root <dir>]\n" ++
  "  proof-forge-next build-counter --target <target> [-o <dir>]\n"

/-- Deterministic project-relative path for the built-in Counter product path. -/
private def counterLogicalSourcePath : String := "Examples/Counter.lean"

private structure BuildOptions where
  source : Option String := none
  target : Option TargetId := none
  output : String := "build/v2"
  moduleName : Option String := none
  programName : Option String := none
  root : String := "."

/-- CLI usage/config failure: exit 2, plain message on stderr (not a diagnostic). -/
private def failUsage (message : String) : IO α := do
  IO.eprintln message
  IO.Process.exit 2

/-- Product diagnostic failure: full human bundle on stderr, no success stdout,
    exact `DiagnosticBundleV1.selectExitCode`. -/
private def failBundle (bundle : DiagnosticBundleV1) : IO α := do
  let text := DiagnosticBundleV1.renderHuman bundle
  unless text.isEmpty do
    IO.eprintln text
  let code := DiagnosticBundleV1.selectExitCode bundle
  let exitByte : UInt8 :=
    if code ≥ 256 then 70 else UInt8.ofNat code
  IO.Process.exit exitByte

/-- Argv target parse: usage/config exit 2 (plain message). Not a product
    diagnostic and must not throw `IO.userError` / uncaught-exception exit 1. -/
private def parseTarget (value : String) : IO TargetId :=
  match TargetId.parse? value with
  | some target => pure target
  | none => failUsage s!"unknown target '{value}'"

private partial def parseBuildArgs (args : List String) (options : BuildOptions := {}) : IO BuildOptions := do
  match args with
  | [] => pure options
  | "--target" :: value :: rest => parseBuildArgs rest { options with target := some (← parseTarget value) }
  | "-o" :: value :: rest | "--output" :: value :: rest => parseBuildArgs rest { options with output := value }
  | "--module" :: value :: rest => parseBuildArgs rest { options with moduleName := some value }
  | "--program" :: value :: rest => parseBuildArgs rest { options with programName := some value }
  | "--root" :: value :: rest => parseBuildArgs rest { options with root := value }
  | value :: rest =>
      if value.startsWith "-" then
        failUsage s!"unknown option '{value}'"
      else if options.source.isSome then
        failUsage "only one source file may be compiled"
      else
        parseBuildArgs rest { options with source := some value }

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

private unsafe def buildSource (options : BuildOptions) : IO Unit := do
  let target ← match options.target with
    | some target => pure target
    | none => failUsage "--target is required"
  let source ← match options.source with
    | some source => pure source
    | none => failUsage "source file is required"
  let moduleName ← match options.moduleName with
    | some moduleName => pure moduleName
    | none => failUsage "--module is required for canonical ProgramV1 identity"
  validateSourceArgument source
  let root := FilePath.mk options.root
  unless ← root.pathExists do
    failUsage s!"root directory not found: {root}"
  let sourcePath ← ensureContainedSource root (FilePath.mk source)
  let sourceText ← IO.FS.readFile sourcePath
  -- Logical project-relative path for diagnostic origins (not absolute realPath).
  let logicalPath := source
  match ← Language.Loader.selectProgramV1Product
      sourceText logicalPath moduleName options.programName with
  | .error bundle => failBundle bundle
  | .ok (sourceProgram, origins) =>
      match Compiler.compileProgramProductV1 sourceProgram origins with
      | .error bundle => failBundle bundle
      | .ok semanticProgram =>
          let requestedOutput := FilePath.mk options.output
          let outputPath :=
            if requestedOutput.isAbsolute then requestedOutput else root / requestedOutput
          let manifest ← emitProgram target semanticProgram outputPath
          IO.println s!"built target={manifest.target} deployable={manifest.deployable}"

private unsafe def buildCounter (options : BuildOptions) : IO Unit := do
  let target ← match options.target with
    | some target => pure target
    | none => failUsage "--target is required"
  let outputDir := FilePath.mk options.output
  match ← Language.Loader.selectProgramV1Product
      Examples.counterSourceText counterLogicalSourcePath
      Examples.counterModuleNameV1 none with
  | .error bundle => failBundle bundle
  | .ok (sourceProgram, origins) =>
      match Compiler.compileProgramProductV1 sourceProgram origins with
      | .error bundle => failBundle bundle
      | .ok semanticProgram =>
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
  | _ =>
      IO.eprintln usage
      IO.Process.exit 2

end ProofForgeV2.CLI

unsafe def main (args : List String) : IO Unit := ProofForgeV2.CLI.run args
