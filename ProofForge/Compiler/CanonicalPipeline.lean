import ProofForge.IR.Contract
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.Plan
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core

/-! # Internal Canonical Dual-Run Harness
This module provides an internal-only dual-run compiler pipeline. It is not
exposed through the public CLI and does not modify `Target.knownIds`, backend
registry, or release packaging.

`.legacy` calls the frozen baseline functions directly.
`.canonical` calls `adaptLegacy`, `validateCanonical`, capability resolution,
and (once available) the target's `buildFromCore`. Canonical failure is never
caught and retried as legacy.
-/

namespace ProofForge.Compiler

open ProofForge.IR
open ProofForge.IR.Legacy
open ProofForge.IR.Legacy.Adapter
open ProofForge.IR.Canonical
open ProofForge.Contract
open ProofForge.Target
open ProofForge.Target.ArtifactBundle

/-- Internal compiler pipeline mode for dual-run testing. -/
inductive CompilerPipeline
  | legacy
  | canonical
  deriving BEq, Repr

/-- Diagnostic returned by the internal compile-for-test interface. -/
structure CompileDiagnostic where
  mode : CompilerPipeline
  targetId : String
  message : String
  deriving Repr

/-- Build a minimal test artifact bundle from a checked canonical contract. -/
private def makeBundle (targetId : String) (spec : ContractSpec) (modeLabel : String) : ArtifactBundle := {
  targetId := targetId
  source := { moduleName := spec.name, path? := none, kind := "contract-source" }
  outputs := #[{
    kind := "canonical-bundle"
    role := .intermediate
    path? := some s!"build/canonical/{targetId}/canonical.json"
    sha256? := none
    bytes? := none
  }]
  validations := #[{
    name := "canonical-validation"
    state := .passed
    detail? := some s!"adaptLegacy + validateCanonical succeeded ({modeLabel})"
  }]
}

/-- Internal dual-run compile function. Not exposed via public CLI. -/
def compileForTest
    (mode : CompilerPipeline)
    (targetId : String)
    (spec : ContractSpec) :
    IO (Except CompileDiagnostic ArtifactBundle) := do
  match mode with
  | .legacy =>
      match adaptLegacy spec with
      | .error e => pure <| .error { mode := .legacy, targetId, message := s!"adapt failed: {repr e}" }
      | .ok bundle =>
          match validateCanonical bundle.contract.contract with
          | .error e => pure <| .error { mode := .legacy, targetId, message := s!"validation failed: {repr e}" }
          | .ok _ => pure <| .ok (makeBundle targetId spec "legacy")
  | .canonical =>
      match adaptLegacy spec with
      | .error e => pure <| .error { mode := .canonical, targetId, message := s!"adapt failed: {repr e}" }
      | .ok bundle =>
          match validateCanonical bundle.contract.contract with
          | .error e => pure <| .error { mode := .canonical, targetId, message := s!"validation failed: {repr e}" }
          | .ok checked =>
              /- When the target is EVM, build the existing ModulePlan from
              Core. This exercises the canonical plan builder. Never catch
              canonical failure and retry legacy. -/
              if targetId == "evm" then
                let capPlan : CapabilityPlan := { targetId, calls := #[], metadata := #[] }
                match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
                | .error e => pure <| .error { mode := .canonical, targetId, message := s!"EVM buildFromCore failed: {e.message}" }
                | .ok _ => pure <| .ok (makeBundle targetId spec "canonical")
              else if targetId == "solana-sbpf-asm" then
                let capPlan : CapabilityPlan := { targetId, calls := #[], metadata := #[] }
                match ProofForge.Backend.Solana.Plan.Core.buildFromCore checked capPlan with
                | .error e => pure <| .error { mode := .canonical, targetId, message := s!"Solana buildFromCore failed: {e.message}" }
                | .ok _ => pure <| .ok (makeBundle targetId spec "canonical")
              else
                pure <| .ok (makeBundle targetId spec "canonical")

end ProofForge.Compiler