/-
  Test-only #119 exporter.

  Reads the CompanionCpi source fixture, follows the real
  Loader → product compile → exact CPI preflight capability → Semantic-derived
  Plan → resolved preflight IR → resolved unsigned IR → unsigned emitter chain,
  and writes the resulting test-preactivation assembly. Cannot mint OutputFile
  or product artifacts.
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.CpiUnsignedIRV1
import ProofForgeV2.Targets.Solana.EmitCpiUnsignedSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Materialization.SolanaCpiUnsignedExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-unsigned-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiUnsignedAssemblyV1 := do
  let session ← Language.Loader.ParserSession.create
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.CompanionCpi" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected CompanionCpi"
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
  let preflightIr ← requireCompile
    (resolveSolanaCpiPreflightIRV1 plan)
    "resolve preflight IR"
  let unsignedIr ← requireCompile
    (resolveSolanaCpiUnsignedIRV1 preflightIr)
    "resolve unsigned CPI IR"
  let assembly ← requireCompile
    (emitCpiUnsignedSbpfV1 unsignedIr)
    "emit unsigned CPI SBPF"
  unless !SolanaCpiUnsignedAssemblyV1.isProductArtifact assembly &&
      SolanaCpiUnsignedAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiUnsignedAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiUnsignedExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiUnsignedExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiUnsignedExportV1 <CompanionCpi.lean> <output.s>"
