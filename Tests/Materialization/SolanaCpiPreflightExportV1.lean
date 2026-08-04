/-
  Test-only #118 exporter.

  Reads the AccountRoles source fixture, follows the real
  Loader → product compile → exact CPI preflight capability → Semantic-derived
  Plan → resolved preflight IR → production emitter chain, and writes the
  resulting test-preactivation assembly. This module cannot mint OutputFile or
  product artifacts; scripts bind the generated text and locked-sbpf ELF only
  as runtime-test evidence.
-/
import ProofForgeV2.Targets.Solana.CpiPreflightCapabilityV1
import ProofForgeV2.Targets.Solana.CpiDeriveV1
import ProofForgeV2.Targets.Solana.CpiPreflightIRV1
import ProofForgeV2.Targets.Solana.EmitCpiPreflightSbpfV1
import ProofForgeV2.Targets.BuildSelectionV1
import ProofForgeV2.Compiler.Pipeline
import ProofForgeV2.Language.Loader

namespace Tests.Materialization.SolanaCpiPreflightExportV1

open ProofForgeV2
open ProofForgeV2.Compiler
open ProofForgeV2.Targets.BuildSelectionV1
open ProofForgeV2.Targets.Solana.CpiV1

private def fail (message : String) : IO α :=
  throw <| IO.userError s!"solana-cpi-preflight-export: {message}"

private def requireCompile {α : Type} (result : CompileResult α)
    (label : String) : IO α :=
  match result with
  | .ok value => pure value
  | .error error => fail s!"{label}: {error.render}"

private unsafe def generateAssembly
    (sourceText sourcePath : String) : IO SolanaCpiPreflightAssemblyV1 := do
  let session ← Language.Loader.ParserSession.create
  let (source, origins) ← match ← session.selectProgramV1WithOrigins
      sourceText sourcePath "Examples.AccountRoles" none with
    | .ok value => pure value
    | .error error => fail s!"load fixture: {error.render}"
  let compiled ← match Compiler.compileProgramProductV1 source origins with
    | .ok value => pure value
    | .error _ => fail "product compile rejected AccountRoles"
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
  let ir ← requireCompile
    (resolveSolanaCpiPreflightIRV1 plan)
    "resolve preflight IR"
  let assembly ← requireCompile
    (emitCpiPreflightSbpfV1 ir)
    "emit preflight SBPF"
  unless !SolanaCpiPreflightAssemblyV1.isProductArtifact assembly &&
      SolanaCpiPreflightAssemblyV1.isTestPreactivation assembly do
    fail "emitter boundary flags diverged"
  pure assembly

unsafe def run (sourcePath outputPath : String) : IO Unit := do
  let source ← IO.FS.readFile sourcePath
  let assembly ← generateAssembly source sourcePath
  IO.FS.writeFile outputPath (SolanaCpiPreflightAssemblyV1.textOf assembly)

end Tests.Materialization.SolanaCpiPreflightExportV1

unsafe def main (args : List String) : IO Unit :=
  match args with
  | [sourcePath, outputPath] =>
      Tests.Materialization.SolanaCpiPreflightExportV1.run sourcePath outputPath
  | _ =>
      throw <| IO.userError
        "usage: SolanaCpiPreflightExportV1 <AccountRoles.lean> <output.s>"
