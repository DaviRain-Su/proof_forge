/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Portable **hash-width** Ownable mixin — owner stored as `.hash`, checks use
`callerHash` / `requireOwnerHash`.

Product path for identity-width owner:
- NEAR: predecessor account id → sha256 Hash
- EVM: `keccak256` of zero-padded `msg.sender` (`hashWord(caller)`)
- Solana: sha256(full authority pubkey) limb0 handle + `hash4` zero for renounce

Prefer `Stdlib.Ownable` (u64 handle) when the triad only needs address-width
handles without hashing.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.OwnableHash

open ProofForge.Contract.Source

def «owner» : ScalarRef :=
  ProofForge.Contract.Source.slot "owner" .hash

contract_mixin OwnableHashMixin do
  use ProofForge.Contract.Source.scalar «owner»

  query «owner» returns(.hash) do
    return «owner»;

  -- Note: no `transferOwnership (newOwner : .hash)` — Solana IR v0 cannot take
  -- Hash entrypoint params. Renounce + re-init patterns, or NEAR-only extension
  -- mixins, cover transfer for now.
  entry renounceOwnership do
    do ProofForge.Contract.Source.requireOwnerHash «owner»;
    «owner» := ProofForge.Contract.Source.hash4 0 0 0 0;

contract_source OwnableHash do
  use mixin
  entry init do
    do ProofForge.Contract.Source.assertCondition
      (ProofForge.Contract.Source.eq
        (ProofForge.Contract.Source.read «owner»)
        (ProofForge.Contract.Source.hash4 0 0 0 0))
      "already initialized";
    «owner» := callerHash;

end ProofForge.Contract.Stdlib.OwnableHash
