import Examples.Product.Counter
import ProofForge.Backend.Evm.Plan

/-! Direct Authored backend fixture for scalar constructor initialization.

The Product Counter remains the only business source. This fixture adds only
the constructor ABI/binding needed by the EVM init-code runtime gate and still
normalizes directly to checked Canonical Core.
-/

namespace Examples.Backend.Evm.Contracts.CounterConstructorProbe

def contract : ProofForge.Frontend.Authored.AuthoredContract :=
  Examples.Product.Counter.contract

def evmConstructor : ProofForge.Backend.Evm.Plan.ConstructorConfigPlan := {
  params := #[{ name := "initial", abiType := "uint256" }]
  bindings := #[{
    stateName := "count"
    paramName := "initial"
    kind := .scalarU64
  }]
}

end Examples.Backend.Evm.Contracts.CounterConstructorProbe
