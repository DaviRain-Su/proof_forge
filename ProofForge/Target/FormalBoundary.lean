import ProofForge.Target.Formal
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault
import ProofForge.Frontend.Authored.Canonicalize

namespace ProofForge.Target

/-! ## FV-1 full-boundary soundness

`Target.Formal` pins the `requireCapabilityPlan` layer with structural,
universally-quantified theorems. The checks below extend soundness across the
full `defaultResolve` / `resolveSpec` boundary that drivers and the CLI
actually call. The only additional step `defaultResolve` performs beyond
`requireCapabilityPlan` is the `UpgradePolicy.checkSupported` rejection gate,
which returns `.ok ()` or `.error` and therefore cannot weaken the capability
boundary when it succeeds.

This module is deliberately kept **outside** `ProofForge.Target`'s import
graph (it is not re-exported by `ProofForge/Target.lean`). The example
contracts transitively import `ProofForge.Target` (via the Solana surface),
so importing them from `Target.Formal` would create a cycle. Hosting the
full-boundary theorems here breaks that cycle while still living in the
`ProofForge.Target` namespace.

Counter now enters through direct Authored normalization and
`resolveCanonicalCheckedBy`; ValueVault remains explicit deletion inventory on
the old boundary until A-CUT3 migrates it. -/

def authoredCounterCheckedBy (profile : TargetProfile) : Bool :=
  match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      ProofForge.Contract.Examples.Counter.contract with
  | .ok bundle => resolveCanonicalCheckedBy profile bundle.contract
  | .error _ => false

/-- The direct Counter Canonical requirements yield a checked EVM plan. -/
theorem resolveCanonical_sound_counter_evm :
    authoredCounterCheckedBy evm = true := by
  native_decide

/-- The direct Counter Canonical requirements yield a checked Solana plan. -/
theorem resolveCanonical_sound_counter_solana :
    authoredCounterCheckedBy solanaSbpfAsm = true := by
  native_decide

/-- The direct Counter Canonical requirements yield a checked NEAR plan. -/
theorem resolveCanonical_sound_counter_near :
    authoredCounterCheckedBy wasmNear = true := by
  native_decide

/-- Resolving the ValueVault spec against the EVM profile yields a checked
plan. -/
theorem resolveSpec_sound_value_vault_evm :
    resolveSpecCheckedBy evm ProofForge.Contract.Examples.ValueVault.spec = true := by
  native_decide

/-- Resolving the ValueVault spec against the NEAR Wasm profile yields a
checked plan. -/
theorem resolveSpec_sound_value_vault_near :
    resolveSpecCheckedBy wasmNear ProofForge.Contract.Examples.ValueVault.spec = true := by
  native_decide

end ProofForge.Target
