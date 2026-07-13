/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

NEAR NEP-141 Fungible Token example.

Compile to Wasm/NEAR:
  lake env proof-forge build --target wasm-near --root . \
    -o build/wasm-near/FungibleToken Examples/Backend/WasmNear/FungibleToken.lean

The exported standard
`ft_transfer_call(receiver_id, amount, memo, msg)` entrypoint accepts a JSON
object, requires exactly one yoctoNEAR, checks receiver registration, and uses
the runtime `receiver_id` directly when it emits:

  ft_transfer_call
    -> promise_create(receiver, "ft_on_transfer", {sender_id, amount, msg})
    -> promise_then(current_account_id, "ft_resolve_transfer",
         {transfer_id, sender, receiver})
-/
import ProofForge.Contract.Stdlib.NearFungibleToken

namespace Examples.Backend.WasmNear.FungibleToken

def demoReceiverAccount : String :=
  "demo.receiver.testnet"

def demoTransferAmount : Nat :=
  70

def spec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.NearFungibleToken.spec

def module : ProofForge.IR.Module :=
  ProofForge.Contract.Stdlib.NearFungibleToken.module

end Examples.Backend.WasmNear.FungibleToken
