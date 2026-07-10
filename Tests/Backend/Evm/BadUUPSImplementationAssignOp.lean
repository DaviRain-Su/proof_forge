/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Negative fixture: the ERC-1967 implementation pointer must never be mutated
through arithmetic compound assignment, which would bypass upgrade guards.
-/
import ProofForge.Contract.Stdlib.UUPSUpgradeable

namespace BadUUPSImplementationAssignOp

open ProofForge.IR

private def base := ProofForge.Contract.Stdlib.UUPSUpgradeable.spec

private def corruptImplementation : Entrypoint := {
  name := "corrupt_implementation"
  body := #[
    .effect (.storageScalarAssignOp
      ProofForge.Contract.Stdlib.UUPSUpgradeable.eip1967Implementation.id
      .add
      (.literal (.u64 1)))
  ]
}

def spec : ProofForge.Contract.ContractSpec :=
  { base with
    name := "BadUUPSImplementationAssignOp"
    module := {
      base.module with
        name := "BadUUPSImplementationAssignOp"
        entrypoints := #[corruptImplementation]
    }
  }

def module : ProofForge.IR.Module := spec.module

end BadUUPSImplementationAssignOp
