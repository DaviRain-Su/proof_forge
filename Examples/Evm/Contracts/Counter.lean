/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM compatibility wrapper for the canonical portable Counter.

The contract logic lives in `Examples.Shared.Counter`; this file preserves the
historical EVM example path and adds only EVM deploy-time constructor metadata.
-/
import Examples.Shared.Counter

namespace Counter

def spec : ProofForge.Contract.ContractSpec :=
  { Examples.Shared.Counter.spec with
    evmConstructorParams := #[
      { name := "initial", abiType := "uint256" }
    ]
    evmConstructorInitBindings := #[
      { stateId := "count", paramName := "initial", kind := .scalarU64 }
    ]
  }

def module : ProofForge.IR.Module :=
  spec.module

end Counter
