/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Negative fixture: narrowing the ERC-1967 address through a scalar-u64 binding
would initialize an ordinary layout slot instead of the fixed proxy slot.
-/
import ProofForge.Contract.Stdlib.UUPSProxy

namespace BadUUPSWrongBinding

private def base := ProofForge.Contract.Stdlib.UUPSProxy.spec

def spec : ProofForge.Contract.ContractSpec :=
  { base with
    name := "BadUUPSWrongBinding"
    module := { base.module with name := "BadUUPSWrongBinding" }
    constructorInitBindings := #[
      {
        stateId := ProofForge.Contract.Stdlib.UUPSProxy.eip1967Implementation.id
        paramName := "implementation"
        kind := .scalarU64
      },
      {
        stateId := ProofForge.Contract.Stdlib.UUPSProxy.owner.id
        paramName := "admin"
        kind := .addressKeccak
      }
    ]
  }

def module : ProofForge.IR.Module := spec.module

end BadUUPSWrongBinding
