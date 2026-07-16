/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM compatibility wrapper for the portable Ownable shared example.
-/
import Examples.Product.Ownable

namespace Ownable

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Product.Ownable.spec

def module : ProofForge.IR.Module :=
  spec.module

end Ownable
