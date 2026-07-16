/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM compatibility wrapper for the portable Pausable shared example.
-/
import Examples.Product.Pausable

namespace Pausable

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Product.Pausable.spec

def module : ProofForge.IR.Module :=
  spec.module

end Pausable
