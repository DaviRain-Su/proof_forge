import ProofForge.Target.Formal
import ProofForge.Contract.Examples.Counter
import ProofForge.Frontend.Authored.Canonicalize

namespace ProofForge.Target

/-! ## FV-5 checked-overflow capability gate

The direct Counter source uses checked addition. Authored normalization records
that semantic requirement as `arith.checked` in Canonical Core, and the target
capability boundary must accept it on every primary target without rebuilding a
v1 `IR.Module` or `ContractSpec`.

These `native_decide` theorems pin that gate:

- A checked-overflow module resolves on EVM (`.ok`).
- The same checked-overflow module resolves on Solana and NEAR.

This is the FV-5 capability-gate half: it makes the cross-target overflow
divergence a *rejected* mismatch rather than a silent behavioral difference.
The companion work — making the IR reference semantics itself width-aware
(revert/mask on overflow inside `evalNumericBinary`) — is the second FV-5 step
and lives in `ProofForge/IR/Semantics.lean`. -/

namespace FV5Overflow

def checkedCounterRequirements : Array CapabilityCall :=
  match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      ProofForge.Contract.Examples.Counter.contract with
  | .ok bundle => bundle.contract.contract.requirements
  | .error _ => #[]

def checkedCounterResolvesOn (profile : TargetProfile) : Bool :=
  match ProofForge.Frontend.Authored.Canonicalize.normalizeAuthored
      ProofForge.Contract.Examples.Counter.contract with
  | .ok bundle => resolveCanonicalCheckedBy profile bundle.contract
  | .error _ => false

/-- Direct normalization preserves the source's checked arithmetic. -/
theorem checkedCounterCanonical_declares_arith_checked :
    checkedCounterRequirements.any (fun call => call.capability == .checkedArithmetic) = true := by
  native_decide

/-- EVM declares and materializes checked arithmetic. -/
theorem checkedCounterCanonical_resolves_on_evm :
    checkedCounterResolvesOn evm = true := by
  native_decide

/-- Solana declares and materializes checked arithmetic. -/
theorem checkedCounterCanonical_resolves_on_solana :
    checkedCounterResolvesOn solanaSbpfAsm = true := by
  native_decide

/-- NEAR declares and materializes checked arithmetic. -/
theorem checkedCounterCanonical_resolves_on_near :
    checkedCounterResolvesOn wasmNear = true := by
  native_decide

end FV5Overflow

end ProofForge.Target
