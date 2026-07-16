/-
Wave γ: portable protocol materialize catalog + ExternalToken product surface.
-/
import ProofForge.Target.ProtocolMaterialize
import ProofForge.Contract.Protocol
import ProofForge.Contract.Builder
import Examples.Product.ExternalTokenTransfer

namespace ProofForge.Tests.ProtocolMaterialize

open ProofForge.Target.ProtocolMaterialize
open ProofForge.Contract.Builder
open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def main : IO UInt32 := do
  require (catalogId == "target.protocol_materialize") "catalog id"
  require (evmSelector? "ft_transfer" == some 0xa9059cbb) "ft_transfer → IERC20 transfer"
  require (evmSelector? "transfer" == some 0xa9059cbb) "transfer alias"
  require (evmSelector? "ft_balance_of" == some 0x70a08231) "balanceOf selector"
  require (evmSelector? "ft_total_supply" == some 0x18160ddd) "totalSupply selector"
  require (nearMethod? "transfer" == some "ft_transfer") "NEAR alias transfer"
  require (nearUsesNep141JsonObject? "ft_transfer") "NEP-141 packing for ft_transfer"
  require (hostNotes.size >= 3) "host notes for three primary hosts"
  require (parseEvmWordHex?
      "0xffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" ==
      some (2 ^ 256 - 1)) "32-byte EVM word literal"
  require (parseEvmWordHex?
      "0x1ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff" == none)
    "reject EVM word wider than 32 bytes"
  require (parseEvmAddressHex?
      "0x10000000000000000000000000000000000000000" == none)
    "reject EVM address wider than 20 bytes"

  -- resolveEvmMethodExpr: address pool handle → selector word
  let pool := #["usdc.peer", "ft_transfer", "ft_balance_of"]
  let resolved := resolveEvmMethodExpr pool (.literal (.address 1))
  match resolved with
  | .literal (.u64 n) => require (n == 0xa9059cbb) s!"resolved selector got {n}"
  | _ => throw (IO.userError "expected u64 selector literal")

  let unknown := resolveEvmMethodExpr pool (.literal (.address 0))
  match unknown with
  | .literal (.address 0) => pure ()
  | _ => throw (IO.userError "unknown peer id must stay address handle")

  -- Product ExternalTokenTransfer module has protocol method pool strings
  let mod := Examples.Product.ExternalTokenTransfer.module
  require (mod.crosscallStrings.any (· == "usdc.peer")) "registers usdc.peer"
  require (mod.crosscallStrings.any (· == "ft_transfer")) "registers ft_transfer"
  require (mod.crosscallStrings.any (· == "ft_balance_of")) "registers ft_balance_of"
  require (mod.crosscallStrings.any (· == "ft_total_supply")) "registers ft_total_supply"
  -- Product path must not require Protocols import (surface is Contract.Protocol)
  require (!(mod.crosscallStrings.any (· == "protocols.evm.ierc20"))) "no Layer B catalog id in pool"

  IO.println "ProtocolMaterialize: ok"
  pure 0

end ProofForge.Tests.ProtocolMaterialize

def main : IO UInt32 :=
  ProofForge.Tests.ProtocolMaterialize.main
