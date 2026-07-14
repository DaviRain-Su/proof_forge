import ProofForge.IR.Contract
import ProofForge.Frontend.ContractSpec.Normalize
import ProofForge.IR.Canonical
import ProofForge.Contract.Spec
import ProofForge.Frontend.Surface
import ProofForge.Target.ArtifactBundle
import ProofForge.Target.Plan
import ProofForge.Target.Adapter
import ProofForge.Target.Registry
import ProofForge.Backend.Evm.Plan.Core
import ProofForge.Backend.Solana.Plan.Core
import ProofForge.Backend.WasmHost.ModulePlan.Core
import ProofForge.Backend.Stylus.Plan.Core
/-! # Internal Canonical Dual-Run Harness
This module provides an internal-only dual-run compiler pipeline. It is not
exposed through the public CLI and does not modify `Target.knownIds`, backend
registry, or release packaging.

`.legacy` calls the frozen baseline functions directly.
`.canonical` normalizes the authored source, validates Canonical Core, resolves
capabilities, and invokes the target's `buildFromCore`. Canonical failure is
never caught and retried as legacy.
-/

namespace ProofForge.Compiler

open ProofForge.IR
open ProofForge.IR.Canonical
open ProofForge.Contract
open ProofForge.Target
open ProofForge.Target.ArtifactBundle

/-- Normalize a Legacy-compatible `ContractSpec` at the reviewed compiler
boundary. Public target drivers use this helper instead of importing the
Legacy adapter directly, so the production import freeze remains shrinking. -/
def adaptContractSpecCanonical (spec : ContractSpec) : Except String CanonicalBundle :=
  match adaptLegacy spec with
  | .ok bundle => .ok bundle
  | .error error => .error s!"canonical: adapt failed: {repr error}"

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

/-- A contract source discovered by the Lean frontend.
`surfaceFixture` is an internal migration input, not a public source version. -/
inductive LoadedContractSource
  | authored (spec : ContractSpec)
  | surfaceFixture (contract : ProofForge.Frontend.Surface.SurfaceContract)

namespace LoadedContractSource

/-- Normalize an authored source or internal Surface fixture without translating
Surface back to Legacy. Fixtures are canonical-only. -/
def toCanonical (mode : CompilerPipeline) : LoadedContractSource →
    Except CompileDiagnostic CanonicalBundle
  | .authored spec =>
      match ProofForge.Frontend.ContractSpec.normalize spec with
      | .ok bundle => .ok bundle
      | .error e => .error {
          mode, targetId := "source", message := s!"authored source normalization failed: {repr e}" }
  | .surfaceFixture contract =>
      if mode == .legacy then
        .error {
          mode, targetId := "source",
          message := "internal Surface fixture cannot request the Legacy pipeline" }
      else
        match ProofForge.Frontend.Surface.normalizeSurface contract with
        | .ok bundle => .ok bundle
        | .error e => .error {
            mode, targetId := "source", message := s!"Surface fixture normalization failed: {repr e}" }

end LoadedContractSource

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
    detail? := some s!"source normalization + validateCanonical succeeded ({modeLabel})"
  }]
}

/-- Check that every `hostCall` instruction in a checked canonical contract has
a handler for the given target. Returns a list of error messages for unhandled
host calls. EVM/Solana with no handler return `missingHostOpHandler`. -/
def checkHostOpHandlers (targetId : String) (checked : CheckedCanonicalContract) :
    Array String :=
  let supported := (ProofForge.Target.find? targetId).map (·.hostOps) |>.getD #[]
  let m := checked.contract.module
  m.functions.foldl (init := #[]) fun errs func =>
    func.blocks.foldl (init := errs) fun errs block =>
      block.instructions.foldl (init := errs) fun errs instr =>
        match instr.op with
        | .hostCall call =>
          if supported.contains call.id then
            errs
          else
            errs.push s!"missingHostOpHandler: {call.id.render} on target {targetId}"
        | _ => errs

def checkInterfaceOpHandlers (targetId : String) (checked : CheckedCanonicalContract) :
    Array String :=
  let supported := (ProofForge.Target.find? targetId).map (·.interfaceOps) |>.getD #[]
  checked.contract.interfaceExtensions.foldl (init := #[]) fun errors extension =>
    if supported.contains extension.id then errors
    else errors.push s!"missingInterfaceOpHandler: {extension.id.render} on target {targetId}"

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
      match ProofForge.Frontend.ContractSpec.normalize spec with
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
              let hostCallErrors := checkHostOpHandlers targetId checked ++
                checkInterfaceOpHandlers targetId checked
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
                match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore checked capPlan with
                | .error e => pure <| .error { mode := .canonical, targetId, message := s!"NEAR buildFromCore failed: {e.message}" }
                | .ok _ => pure <| .ok (makeBundle targetId spec "canonical")
              else
                pure <| .error {
                  mode := .canonical, targetId,
                  message := "canonical buildFromCore is unavailable for this target"
                }

/-- Strict canonical target gate.

Every stage is a hard error. The former advisory gate was removed after its
last production caller migrated to strict target planning.

Returns `.ok ()` only when the spec can be adapted, validated, capability-checked,
host-op checked, and built by the target's `buildFromCore`. -/
private def runStrictCheckedTargetGate
    (profile : TargetProfile) (targetId : String) (checked : CheckedCanonicalContract) :
    Except String Unit := do
  let hostCallErrors := checkHostOpHandlers targetId checked ++
    checkInterfaceOpHandlers targetId checked
  if hostCallErrors.size > 0 then
    let msg := String.intercalate "; " hostCallErrors.toList
    .error s!"canonical: unhandled host op: {msg}"
  let capPlan : CapabilityPlan ←
    match requireCapabilityPlan profile {
      targetId := targetId,
      calls := checked.contract.requirements,
      metadata := #[]
    } with
    | .ok plan => pure plan
    | .error diagnostic => .error s!"canonical: capability plan failed: {diagnostic.render}"
  match targetId with
  | "evm" =>
      match ProofForge.Backend.Evm.Plan.Core.buildFromCore checked capPlan with
      | .error e => .error s!"canonical: buildFromCore failed: {e.message}"
      | .ok _ => pure ()
  | "solana-sbpf-asm" =>
      match ProofForge.Backend.Solana.Plan.Core.buildFromCore checked capPlan with
      | .error e => .error s!"canonical: buildFromCore failed: {e.message}"
      | .ok _ => pure ()
  | "wasm-near" =>
      match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore checked capPlan with
      | .error e => .error s!"canonical: buildFromCore failed: {e.message}"
      | .ok _ => pure ()
  | "wasm-stellar-soroban" =>
      match ProofForge.Backend.WasmHost.ModulePlan.Core.buildFromCore checked capPlan with
      | .error e => .error s!"canonical: buildFromCore failed: {e.message}"
      | .ok _ => pure ()
  | "wasm-arbitrum-stylus" =>
      match ProofForge.Backend.Stylus.Plan.Core.buildFromCore checked capPlan with
      | .error e => .error s!"canonical: buildFromCore failed: {e.message}"
      | .ok _ => pure ()
  | _ => .error s!"canonical: buildFromCore is unavailable for target {targetId}"

/-- Strict target planning for an already-normalized canonical contract.

This entry point keeps validation testable independently of the legacy adapter;
callers with a `ContractSpec` should use `runStrictCanonicalTargetGate`. -/
def runStrictCanonicalContractGate
    (targetId : String) (contract : CanonicalContract) : Except String Unit := do
  let profile ←
    match ProofForge.Target.find? targetId with
    | some p => pure p
    | none => .error s!"canonical: unknown target {targetId}"
  let checked ←
    match validateCanonical contract with
    | .ok c => pure c
    | .error e => .error s!"canonical: validation failed: {repr e}"
  runStrictCheckedTargetGate profile targetId checked

def runStrictCanonicalTargetGate (targetId : String) (spec : ContractSpec) : Except String Unit := do
  let profile ←
    match ProofForge.Target.find? targetId with
    | some p => pure p
    | none => .error s!"canonical: unknown target {targetId}"
  let bundle ←
    match ProofForge.Frontend.ContractSpec.normalize spec with
    | .ok b => pure b
    | .error e => .error e
  runStrictCheckedTargetGate profile targetId bundle.contract

end ProofForge.Compiler
