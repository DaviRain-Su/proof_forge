/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Negative fixture: a minimal UUPS transport shell must not expose an arbitrary
runtime entrypoint that mutates constructor-bound state.
-/
import ProofForge.Contract.Stdlib.UUPSProxy

namespace BadUUPSRuntimeWriter

open ProofForge.IR

private def base := ProofForge.Contract.Stdlib.UUPSProxy.spec

private def overwriteOwner : Entrypoint := {
  name := "overwrite_owner"
  body := #[
    .effect (.storageScalarWrite "owner" (.literal (.hash4 1 2 3 4)))
  ]
}

def spec : ProofForge.Contract.ContractSpec :=
  { base with
    name := "BadUUPSRuntimeWriter"
    module := {
      base.module with
        name := "BadUUPSRuntimeWriter"
        entrypoints := #[overwriteOwner]
    }
  }

def module : ProofForge.IR.Module := spec.module

end BadUUPSRuntimeWriter
