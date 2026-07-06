/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEAR NEP-141 Fungible Token example.

Compile to Wasm/NEAR:
  lake env proof-forge build --target wasm-near --root . \
    -o build/wasm-near/FungibleToken Examples/WasmNear/FungibleToken.lean

The exported `ft_transfer_call(receiver_id, receiver_idx, amount)` entrypoint
uses Borsh input layout `Hash || U32 || U64`. `receiver_idx = 0` selects the
demo receiver account registered by the stdlib (`demo.receiver.testnet`) and
emits:

  ft_transfer_call
    -> promise_create(receiver, "ft_on_transfer", [callerHash, amount])
    -> promise_then(current_account_id, "ft_resolve_transfer", [])
-/
import ProofForge.Contract.Stdlib.NearFungibleToken

namespace Examples.WasmNear.FungibleToken

def demoReceiverAccount : String :=
  "demo.receiver.testnet"

def demoReceiverIdx : Nat :=
  0

def demoTransferAmount : Nat :=
  70

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.NearFungibleToken.spec

def module : ProofForge.IR.Module :=
  ProofForge.Contract.Stdlib.NearFungibleToken.module

end Examples.WasmNear.FungibleToken
