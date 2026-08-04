/-
  Test-only #122 exporter.

  Reads a classic Token CPI source fixture, follows the real
  Loader → product compile → exact CPI preflight capability → Semantic-derived
  Plan → resolved Token IR → Token emitter chain, and writes the resulting
  test-preactivation assembly. Cannot mint OutputFile or product artifacts.

  Note: the private chain starts from SolanaCpiPreflightPlanV1 (not
  ResolvedSolanaCpiPreflightIRV1, which rejects classicTokenAccount/mint).
  CLI entry is top-level `main` (exporter is not shard-imported); ordinary
  unit suite SolanaCpiTokenV1 remains run-only.
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiTokenIRV1
import ProofForgeV2.Targets.Solana.EmitCpiTokenSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Materialization.SolanaCpiTokenExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-token-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiTokenAssemblyV1 := do
  let session ← Language.Loader.ParserSession.create
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.TokenCpi" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected TokenCpi"
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
  let tokenIr ← requireCompile
    (resolveSolanaCpiTokenIRV1 plan)
    "resolve Token CPI IR"
  let assembly ← requireCompile
    (emitCpiTokenSbpfV1 tokenIr)
    "emit Token CPI SBPF"
  unless !SolanaCpiTokenAssemblyV1.isProductArtifact assembly &&
      SolanaCpiTokenAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiTokenAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiTokenExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiTokenExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiTokenExportV1 <TokenCpi.lean> <output.s>"
