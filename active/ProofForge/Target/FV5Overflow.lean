import ProofForge.Target.Formal
import ProofForge.Contract.Examples.Counter
import ProofForge.IR.Examples.Counter

namespace ProofForge.Target

/-! ## FV-5 checked-overflow capability gate

`Module.overflowChecked` is the portable IR's integer-overflow mode. When a
module sets `overflowChecked := true`, it declares the `arith.checked`
capability (Solidity-0.8-style revert-on-overflow). The platform's core
"reject rather than silently change semantics" promise then requires that such
a module can only resolve to a target profile that declares `arith.checked`.
All three primary targets now declare and materialize that capability.

These `native_decide` theorems pin that gate:

- A checked-overflow module resolves on EVM (`.ok`).
- The same checked-overflow module resolves on Solana and NEAR.

This is the FV-5 capability-gate half: it makes the cross-target overflow
divergence a *rejected* mismatch rather than a silent behavioral difference.
The companion work — making the IR reference semantics itself width-aware
(revert/mask on overflow inside `evalNumericBinary`) — is the second FV-5 step
and lives in `ProofForge/IR/Semantics.lean`. -/

namespace FV5Overflow

open ProofForge.IR

/-- The canonical Counter module with `overflowChecked := true`. This is the
fixture for the FV-5 gate: it declares `arith.checked`. -/
def checkedCounterModule : Module :=
  { ProofForge.IR.Examples.Counter.module with overflowChecked := true }

/-- Keep the capability-intent view synchronized with the replaced module. -/
def checkedCounterSpec : ProofForge.Contract.ContractSpec :=
  { ProofForge.Contract.Examples.Counter.spec with
    module := checkedCounterModule
    intents := ProofForge.Contract.intentsFromIR checkedCounterModule }

/-- `checkedCounterModule` declares the `arith.checked` capability. -/
theorem checkedCounterModule_declares_arith_checked :
    checkedCounterModule.capabilities.contains .checkedArithmetic = true := by
  native_decide

/-- A checked-overflow module resolves to `.ok` on EVM (EVM declares
`arith.checked`). -/
theorem checkedCounterModule_resolves_on_evm :
    resolveSpecCheckedBy evm checkedCounterSpec = true := by
  native_decide

/-- Solana declares and materializes checked arithmetic. -/
theorem checkedCounterModule_resolves_on_solana :
    resolveSpecCheckedBy solanaSbpfAsm checkedCounterSpec = true := by
  native_decide

/-- NEAR declares and materializes checked arithmetic. -/
theorem checkedCounterModule_resolves_on_near :
    resolveSpecCheckedBy wasmNear checkedCounterSpec = true := by
  native_decide

end FV5Overflow

end ProofForge.Target
