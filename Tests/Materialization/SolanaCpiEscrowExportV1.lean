/-
  Test-only #124 exporter.

  Reads the composite escrow CPI fixture and follows Loader → product compile →
  exact CPI preflight capability → Semantic-derived Plan → private Escrow IR →
  Escrow emitter. It can only write test-preactivation assembly and cannot mint
  OutputFile or product artifacts.

  Usage: SolanaCpiEscrowExportV1 <EscrowCpi.lean> <output.s>
  The source path is typically runtime-tests/solana/fixtures/EscrowCpi.lean.
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiEscrowIRV1
import ProofForgeV2.Targets.Solana.EmitCpiEscrowSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiEscrowExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-escrow-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiEscrowAssemblyV1 := do
  let session ← Tests.Language.ParserSession.shared
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.EscrowCpi" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected EscrowCpi"
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
  let escrowIr ← requireCompile
    (resolveSolanaCpiEscrowIRV1 plan)
    "resolve Escrow CPI IR"
  let assembly ← requireCompile
    (emitCpiEscrowSbpfV1 escrowIr)
    "emit Escrow CPI SBPF"
  unless !SolanaCpiEscrowAssemblyV1.isProductArtifact assembly &&
      SolanaCpiEscrowAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiEscrowAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiEscrowExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiEscrowExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiEscrowExportV1 <EscrowCpi.lean> <output.s>"
