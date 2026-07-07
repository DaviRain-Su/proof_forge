/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

EVM compatibility wrapper for the portable ReentrancyGuard shared example.
-/
import Examples.Shared.ReentrancyGuard

namespace ReentrancyGuard

def spec : ProofForge.Contract.ContractSpec :=
  Examples.Shared.ReentrancyGuard.spec

def module : ProofForge.IR.Module :=
  spec.module

end ReentrancyGuard
