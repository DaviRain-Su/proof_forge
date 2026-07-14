/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable **caller + transfer-style debit + remote** intent (T3.2).

Authors never declare Solana accounts: `--target solana-sbpf-asm` auto-fills
`authority` (leading signer for `caller`), program state, and `callee_program`
for the remote CPI. No Solana Surface / account DSL import.

  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o build/portable-auth-remote/AuthRemoteCall.s \
    Examples/Product/AuthRemoteCall.lean

Also builds on EVM / NEAR / Soroban (remote materializes as CALL / promise /
invoke_contract). See `Tests/Product/Accounts.lean` and
`just portable-solana-accounts`.
-/
import ProofForge.Contract.Source

namespace Examples.Product.AuthRemoteCall

open ProofForge.Contract.Source

contract_source AuthRemoteCall do
  remote callee "peer.callee" "receive";

  state balance : .u64

  entry «initialize» do
    balance := u64 100;

  -- Debit local balance (transfer-style) then forward remotely.
  -- `caller` makes Solana synthesize a leading authority signer.
  entry debit_and_forward (amount : .u64) returns(.u64) do
    let _sender : .u64 := caller;
    let n : .u64 := balance;
    do ProofForge.Contract.Source.requireGe (ProofForge.Contract.Source.ref n)
      (ProofForge.Contract.Source.ref amount) "insufficient balance";
    balance := n -! amount;
    return ProofForge.Contract.Source.remoteCallRef callee
      #[ProofForge.Contract.Source.ref amount];

end Examples.Product.AuthRemoteCall
