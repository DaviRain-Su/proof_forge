import ProofForge.Target.Formal
import ProofForge.Contract.Examples.Counter
import ProofForge.Contract.Examples.ValueVault

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

`resolveSpecCheckedBy` runs the full boundary. These `native_decide` checks
confirm that for the three primary-chain profiles, every resolved Counter and
ValueVault plan satisfies `checkedBy profile = true`, exercising both the
no-upgrade-policy path (Counter) and the with-upgrade-policy path (ValueVault)
through `defaultResolve`. -/

/-- Resolving the Counter spec against the EVM profile yields a checked plan. -/
theorem resolveSpec_sound_counter_evm :
    resolveSpecCheckedBy evm ProofForge.Contract.Examples.Counter.spec = true := by
  native_decide

/-- Resolving the Counter spec against the Solana sBPF profile yields a
checked plan. -/
theorem resolveSpec_sound_counter_solana :
    resolveSpecCheckedBy solanaSbpfAsm ProofForge.Contract.Examples.Counter.spec = true := by
  native_decide

/-- Resolving the Counter spec against the NEAR Wasm profile yields a checked
plan. -/
theorem resolveSpec_sound_counter_near :
    resolveSpecCheckedBy wasmNear ProofForge.Contract.Examples.Counter.spec = true := by
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
