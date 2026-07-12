/-
Atomic ERC-2612 TokenSpec fixture. This remains under Backend/Evm because
`permit` is an EVM-specific standard feature; the portable router rejects it
on NEAR and Solana.
-/
import ProofForge.Contract.Token

namespace Examples.Backend.Evm.TokenPermit

open ProofForge.Contract.Token

def spec : TokenSpec := {
  name := "Permit Token"
  symbol := "PMT"
  decimals := 18
  features := #[.permit]
}

end Examples.Backend.Evm.TokenPermit
