/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

CREATE2 factory template mixin for deterministic EVM deployments via `contract_source`.
Embeds fixed init-code hex and exposes `deploy(salt)` plus `templateInitCodeHash` metadata.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.Create2Factory

open ProofForge.Contract.Source

namespace Spec

/-- Init code that deploys runtime returning 42 for any call (EvmCrosscallProbe template). -/
def templateInitCodeHex : String :=
  "69602a60005260206000f3600052600a6016f3"

/-- `keccak256(initCode)` as four big-endian u64 limbs for portable IR hash values. -/
def templateInitCodeHash : ProofForge.IR.Expr :=
  hash4
    10963444922451000386
    11245698773504061611
    16766470442356870852
    8827259616279868619

end Spec

def deployedAddress : ProofForge.Contract.Surface.BindingRef :=
  ProofForge.Contract.Surface.binding "deployed" .address

contract_mixin Create2FactoryMixin do
  event Deployed

  query templateInitCodeHash returns(.hash) do
    return Spec.templateInitCodeHash;

  entry deploy (salt : .hash) returns(.address) do
    accepts_callvalue;
    do ProofForge.Contract.Surface.bind deployedAddress
      (ProofForge.Contract.Surface.cast
        (create2Deploy nativeValue (ProofForge.Contract.Surface.ref salt) Spec.templateInitCodeHex)
        .address);
    emit Deployed indexed #[
      fieldAsName "addr" (ProofForge.Contract.Surface.ref deployedAddress),
      fieldAsName "salt" salt
    ] data #[];
    return ProofForge.Contract.Surface.ref deployedAddress;

contract_source Create2Factory do
  use mixin

end ProofForge.Contract.Stdlib.Create2Factory
