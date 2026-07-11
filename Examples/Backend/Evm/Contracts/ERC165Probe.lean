/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Example contract exercising an immutable generated ERC-165 interface set.
-/
import ProofForge.Contract.Source
import ProofForge.Contract.Stdlib.ERC165

namespace ERC165Probe

open ProofForge.Contract.Source
open ProofForge.Contract.Stdlib.ERC165

def sampleInterfaceId : Nat := 0x12345678

contract_source ERC165Probe do
  query supportsInterface (interfaceId : .bytes4) returns(.bool) do
    return supportsInterfaceExpr (ProofForge.Contract.Surface.ref interfaceId)
      #[sampleInterfaceId];

end ERC165Probe
