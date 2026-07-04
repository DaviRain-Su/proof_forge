/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEAR NEP-141 Fungible Token example.

Compile to Wasm/NEAR:
  lake env proof-forge build --target wasm-near --root . \
    -o build/wasm-near/FungibleToken Examples/WasmNear/FungibleToken.lean
-/
import ProofForge.Contract.Stdlib.NearFungibleToken

namespace Examples.WasmNear.FungibleToken

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.NearFungibleToken.spec

def module : ProofForge.IR.Module :=
  ProofForge.Contract.Stdlib.NearFungibleToken.module

end Examples.WasmNear.FungibleToken