/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Negative fixture: renaming a post-deploy initializer must not bypass the
constructor-only UUPS proxy-shell policy.
-/
import ProofForge.Contract.Stdlib.UUPSProxy

namespace BadUUPSAlternateInitializer

open ProofForge.IR

private def base := ProofForge.Contract.Stdlib.UUPSProxy.spec

private def unsafeInitialize : Entrypoint := {
  name := "initialize"
  params := #[("implementation", .u64)]
  paramAbiWords := #[some "address"]
  body := #[]
}

def spec : ProofForge.Contract.ContractSpec :=
  { base with
    name := "BadUUPSAlternateInitializer"
    module := {
      base.module with
        name := "BadUUPSAlternateInitializer"
        entrypoints := #[unsafeInitialize]
    }
  }

def module : ProofForge.IR.Module := spec.module

end BadUUPSAlternateInitializer
