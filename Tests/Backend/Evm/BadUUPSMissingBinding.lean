/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Negative fixture: implementation-only initialization leaves the proxy owner
unbound and must fail before EVM code generation.
-/
import ProofForge.Contract.Stdlib.UUPSProxy

namespace BadUUPSMissingBinding

private def base := ProofForge.Contract.Stdlib.UUPSProxy.spec

def spec : ProofForge.Contract.ContractSpec :=
  { base with
    name := "BadUUPSMissingBinding"
    module := { base.module with name := "BadUUPSMissingBinding" }
    constructorInitBindings := #[
      {
        stateId := ProofForge.Contract.Stdlib.UUPSProxy.eip1967Implementation.id
        paramName := "implementation"
        kind := .addressWord
      }
    ]
  }

def module : ProofForge.IR.Module := spec.module

end BadUUPSMissingBinding
