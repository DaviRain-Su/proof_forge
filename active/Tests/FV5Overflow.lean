import ProofForge.Target.FV5Overflow

/-! ## FV-5 checked-overflow capability gate smoke

Verifies that a module declaring `overflowChecked` (the `arith.checked`
capability) is routed correctly by the capability gate:

- Resolves on EVM (EVM declares `arith.checked`).
- Resolves on Solana and NEAR, which now declare checked arithmetic.

This pins the capability gate to the current primary-target registry.
-/

namespace ProofForge.Tests.FV5Overflow

open ProofForge.Target.FV5Overflow

-- A checked-overflow module declares the `arith.checked` capability.
#check checkedCounterModule_declares_arith_checked

-- A checked-overflow module resolves on EVM.
#check checkedCounterModule_resolves_on_evm

-- A checked-overflow module resolves on Solana.
#check checkedCounterModule_resolves_on_solana

-- A checked-overflow module resolves on NEAR.
#check checkedCounterModule_resolves_on_near

end ProofForge.Tests.FV5Overflow

def main : IO UInt32 := do
  IO.println "fv5-overflow-smoke: arith.checked capability gate accepts all primary targets via native_decide"
  return 0
