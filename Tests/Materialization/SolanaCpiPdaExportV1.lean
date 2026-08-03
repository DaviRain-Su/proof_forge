/-
  Test-only #120 exporter.

  Reads the CompanionPdaCpi source fixture, follows the real
  Loader → product compile → exact CPI preflight capability → Semantic-derived
  Plan → resolved PDA IR → PDA emitter chain, and writes the resulting
  test-preactivation assembly. Cannot mint OutputFile or product artifacts.

  Note: the private chain starts from SolanaCpiPreflightPlanV1 (not
  ResolvedSolanaCpiPreflightIRV1, which rejects PDA).
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPdaIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPdaSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiPdaExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-pda-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiPdaAssemblyV1 := do
  let session ← Tests.Language.ParserSession.shared
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.CompanionPdaCpi" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected CompanionPdaCpi"
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
  let pdaIr ← requireCompile
    (resolveSolanaCpiPdaIRV1 plan)
    "resolve PDA-signed CPI IR"
  let assembly ← requireCompile
    (emitCpiPdaSbpfV1 pdaIr)
    "emit PDA-signed CPI SBPF"
  unless !SolanaCpiPdaAssemblyV1.isProductArtifact assembly &&
      SolanaCpiPdaAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiPdaAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiPdaExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiPdaExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiPdaExportV1 <CompanionPdaCpi.lean> <output.s>"
