import ProofForge.IR.Contract
import ProofForge.IR.Legacy.Adapter
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.Plan
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.Core
import ProofForge.Backend.WasmHost.NearModulePlan.HostOps
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

/-- Check that every `hostCall` instruction in a checked canonical contract has
a handler for the given target. Returns a list of error messages for unhandled
host calls. EVM/Solana with no handler return `missingHostOpHandler`. -/
def checkHostOpHandlers (targetId : String) (checked : CheckedCanonicalContract) :
    Array String :=
  let m := checked.contract.module
  m.functions.foldl (init := #[]) fun errs func =>
    func.blocks.foldl (init := errs) fun errs block =>
      block.instructions.foldl (init := errs) fun errs instr =>
        match instr.op with
        | .hostCall call =>
          if ProofForge.Backend.WasmHost.NearModulePlan.HostOps.hasHandlerFor targetId call.id then
            errs
          else
            errs.push s!"missingHostOpHandler: {call.id.render} on target {targetId}"
        | _ => errs

/-- Internal dual-run compile function. Not exposed via public CLI. -/
def compileForTest
    (mode : CompilerPipeline)
    (targetId : String)
    (spec : ContractSpec) :
    IO (Except CompileDiagnostic ArtifactBundle) := do
  match mode with
  | .legacy =>
      -- The legacy artifact renderer is invoked by `Tests/Canonical/Emit`.
      -- Keep this branch independent of the canonical adapter.
      match ProofForge.Target.find? targetId with
      | none => pure <| .error { mode := .legacy, targetId, message := "unknown target" }
      | some _ => pure <| .ok (makeBundle targetId spec "legacy")
  | .canonical =>
      match adaptLegacy spec with
      | .error e => pure <| .error { mode := .canonical, targetId, message := s!"adapt failed: {repr e}" }
      | .ok bundle =>
          match validateCanonical bundle.contract.contract with
          | .error e => pure <| .error { mode := .canonical, targetId, message := s!"validation failed: {repr e}" }
          | .ok checked =>
              let profile <- match ProofForge.Target.find? targetId with
                | some profile => pure profile
                | none => return .error { mode := .canonical, targetId, message := "unknown target" }
              let rawPlan : CapabilityPlan := {
                targetId, calls := checked.contract.requirements, metadata := #[]
              }
              let capPlan <- match requireCapabilityPlan profile rawPlan with
                | .ok plan => pure plan
                | .error diagnostic =>
                    return .error { mode := .canonical, targetId, message := diagnostic.render }
              let hostCallErrors := checkHostOpHandlers targetId checked
              if hostCallErrors.size > 0 then
                pure <| .error { mode := .canonical, targetId, message := String.intercalate "; " hostCallErrors.toList }
              else if targetId == "evm" then
                match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
                | .error e => pure <| .error { mode := .canonical, targetId, message := s!"EVM buildFromCore failed: {e.message}" }
                | .ok _ => pure <| .ok (makeBundle targetId spec "canonical")
              else if targetId == "solana-sbpf-asm" then
                match ProofForge.Backend.Solana.Plan.Core.buildFromCore checked capPlan with
                | .error e => pure <| .error { mode := .canonical, targetId, message := s!"Solana buildFromCore failed: {e.message}" }
                | .ok _ => pure <| .ok (makeBundle targetId spec "canonical")
              else if targetId == "wasm-near" then
                match ProofForge.Backend.WasmHost.NearModulePlan.Core.buildFromCore checked capPlan with
                | .error e => pure <| .error { mode := .canonical, targetId, message := s!"NEAR buildFromCore failed: {e.message}" }
                | .ok _ => pure <| .ok (makeBundle targetId spec "canonical")
              else
                pure <| .error {
                  mode := .canonical, targetId,
                  message := "canonical buildFromCore is unavailable for this target"
                }

end ProofForge.Compiler
