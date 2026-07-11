/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

ERC-165 interface introspection mixin for `contract_source` composition.
-/
import ProofForge.Contract.Source

namespace ProofForge.Contract.Stdlib.ERC165

open ProofForge.Contract.Source

def erc165InterfaceId : Nat := 0x01ffc9a7

def erc165InterfaceWord : ProofForge.IR.Expr :=
  .shiftLeft (.literal (.u64 erc165InterfaceId)) (.literal (.u64 224))

def invalidInterfaceId : Nat := 0xffffffff

def interfaceWord (interfaceId : Nat) : ProofForge.IR.Expr :=
  .shiftLeft (.literal (.u64 interfaceId)) (.literal (.u64 224))

/-- Build an immutable interface predicate from compile-time IDs. The reserved
`0xffffffff` value is filtered even if a caller accidentally includes it. -/
def supportsInterfaceExpr (interfaceId : ProofForge.IR.Expr)
    (additionalIds : Array Nat := #[]) : ProofForge.IR.Expr :=
  additionalIds.foldl
    (fun supported id =>
      if id == invalidInterfaceId then supported
      else ProofForge.Contract.Surface.boolOr supported
        (ProofForge.Contract.Surface.eq interfaceId (interfaceWord id)))
    (ProofForge.Contract.Surface.eq interfaceId erc165InterfaceWord)

contract_mixin ERC165Mixin do
  query supportsInterface (interfaceId : .bytes4) returns(.bool) do
    return supportsInterfaceExpr (ProofForge.Contract.Surface.ref interfaceId);

contract_source ERC165 do
  use mixin

end ProofForge.Contract.Stdlib.ERC165
