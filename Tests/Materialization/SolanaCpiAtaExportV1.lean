/-
  Test-only #123 exporter.

  Reads the classic ATA CPI fixture and follows Loader → product compile →
  exact CPI preflight capability → Semantic-derived Plan → private ATA IR →
  ATA emitter. It can only write test-preactivation assembly and cannot mint
  OutputFile or product artifacts.
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiAtaIRV1
import ProofForgeV2.Targets.Solana.EmitCpiAtaSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Materialization.SolanaCpiAtaExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-ata-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiAtaAssemblyV1 := do
  let session ← Language.Loader.ParserSession.create
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.AtaCpi" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected AtaCpi"
  let selection ← requireCompile
    (resolveBuildSelectionV1 TargetId.solana
      (some CodegenProfileId.solanaSbpfCpiElfV1))
    "resolve exact CPI profile"
  let preflight ← requireCompile
    (resolveSolanaCpiPreflightV1 selection compiled)
    "resolve preflight capability"
  let plan ← requireCompile
    (deriveSolanaCpiPlanFromPreflightV1 preflight)
    "derive Semantic-bound CPI Plan"
  let ataIr ← requireCompile
    (resolveSolanaCpiAtaIRV1 plan)
    "resolve ATA CPI IR"
  let assembly ← requireCompile
    (emitCpiAtaSbpfV1 ataIr)
    "emit ATA CPI SBPF"
  unless !SolanaCpiAtaAssemblyV1.isProductArtifact assembly &&
      SolanaCpiAtaAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiAtaAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiAtaExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiAtaExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiAtaExportV1 <AtaCpi.lean> <output.s>"
