/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Shared facade for hash-width Ownable (NEAR · EVM · Solana identity path).

  lake env proof-forge build --target wasm-near --root . \
    -o build/portable-ownable-hash/near \
    Examples/Product/OwnableHash.lean

  lake env proof-forge build --target evm --root . \
    -o build/portable-ownable-hash/OwnableHash.yul \
    Examples/Product/OwnableHash.lean

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/portable-ownable-hash/OwnableHash.s \
    Examples/Product/OwnableHash.lean

u64 triad (no hash): Examples/Product/Ownable.
-/
import ProofForge.Contract.Stdlib.OwnableHash

namespace Examples.Product.OwnableHash

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.OwnableHash.spec

def module : ProofForge.IR.Module :=
  spec.module

end Examples.Product.OwnableHash
