/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Negative fixture: a UUPS proxy with the expected constructor schema but no
deploy-time storage bindings must fail before EVM code generation.
-/
import ProofForge.Contract.Stdlib.UUPSProxy

namespace BadUUPSNoBindings

private def base := ProofForge.Contract.Stdlib.UUPSProxy.spec

def spec : ProofForge.Contract.ContractSpec :=
  { base with
    name := "BadUUPSNoBindings"
    module := { base.module with name := "BadUUPSNoBindings" }
    constructorInitBindings := #[]
  }

def module : ProofForge.IR.Module := spec.module

end BadUUPSNoBindings
