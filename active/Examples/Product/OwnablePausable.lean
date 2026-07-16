/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Shared facade for Ownable + Pausable (owner-gated pause) on portable path.

  lake env proof-forge build --target evm --root . \
    -o build/portable-ownable-pausable/OwnablePausable \
    Examples/Product/OwnablePausable.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/portable-ownable-pausable/OwnablePausable.s \
    Examples/Product/OwnablePausable.lean

  lake env proof-forge build --target wasm-near --root . \
    -o build/portable-ownable-pausable/near \
    Examples/Product/OwnablePausable.lean
-/
import ProofForge.Contract.Stdlib.OwnablePausable

namespace Examples.Product.OwnablePausable

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.OwnablePausable.spec

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Product.OwnablePausable
