/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable ReentrancyGuard example facade.

The canonical reusable mixin lives in
`ProofForge.Contract.Stdlib.ReentrancyGuard`. This module gives the examples
tree a shared source path that can be routed to EVM, Solana sBPF, and NEAR/Wasm
by changing only `--target`.
-/
import ProofForge.Contract.Stdlib.ReentrancyGuard

namespace Examples.Product.ReentrancyGuard

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.ReentrancyGuard.spec

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Product.ReentrancyGuard
