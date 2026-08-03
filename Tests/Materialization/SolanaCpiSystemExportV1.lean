/-
  Test-only #121 exporter.

  Reads a System CPI source fixture, follows the real
  Loader → product compile → exact CPI preflight capability → Semantic-derived
  Plan → resolved System IR → System emitter chain, and writes the resulting
  test-preactivation assembly. Cannot mint OutputFile or product artifacts.

  Note: the private chain starts from SolanaCpiPreflightPlanV1 (not
  ResolvedSolanaCpiPreflightIRV1, which rejects PDA/systemCreateAccount).
  CLI entry is top-level `main` (exporter is not shard-imported); ordinary
  unit suite SolanaCpiSystemV1 remains run-only.
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiSystemIRV1
import ProofForgeV2.Targets.Solana.EmitCpiSystemSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader
import Tests.Language.ParserSession

namespace Tests.Materialization.SolanaCpiSystemExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-system-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiSystemAssemblyV1 := do
  let session ← Tests.Language.ParserSession.shared
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.SystemCpi" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected SystemCpi"
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
  let systemIr ← requireCompile
    (resolveSolanaCpiSystemIRV1 plan)
    "resolve System CPI IR"
  let assembly ← requireCompile
    (emitCpiSystemSbpfV1 systemIr)
    "emit System CPI SBPF"
  unless !SolanaCpiSystemAssemblyV1.isProductArtifact assembly &&
      SolanaCpiSystemAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiSystemAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiSystemExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiSystemExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiSystemExportV1 <SystemCpi.lean> <output.s>"
