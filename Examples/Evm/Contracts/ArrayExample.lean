/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM compatibility wrapper for the canonical portable ArrayExample.

The contract logic lives in `Examples.Shared.ArrayExample`; this file preserves
the historical EVM example path next to its golden Yul fixture.
-/
import Examples.Shared.ArrayExample

namespace ArrayExample

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.ArrayExample.spec

def module : ProofForge.IR.Module :=
  spec.module

end ArrayExample
