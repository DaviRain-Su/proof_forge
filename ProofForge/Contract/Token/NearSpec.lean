/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Build canonical NEP-141 `ContractSpec` values from Lean `TokenSpec` metadata.

This mirrors `EvmSpec.lean` for EVM: it takes a portable `TokenSpec` and produces
a `ContractSpec` whose module is the `NearFungibleToken` stdlib with feature-gated
entrypoints (mint/burn) and token-specific name/decimals.
-/
import ProofForge.Contract.Token
import ProofForge.Contract.Stdlib.NearFungibleToken
import ProofForge.IR.Contract

namespace ProofForge.Contract.Token.NearSpec

open ProofForge.Contract.Token
open ProofForge.IR

/-- Base NEP-141 spec from the stdlib. -/
def fungibleSpec : ProofForge.Contract.ContractSpec :=
  ProofForge.Contract.Stdlib.NearFungibleToken.spec

private def keepEntrypoint (token : TokenSpec) (entrypoint : Entrypoint) : Bool :=
  entrypoint.name != "init" &&
    (entrypoint.name != "ft_mint" || token.hasFeature .mintable) &&
    (entrypoint.name != "ft_burn" || token.hasFeature .burnable)

def moduleFor (token : TokenSpec) : Module :=
  let base := fungibleSpec.module
  { base with
    name := token.symbol
    entrypoints := base.entrypoints.filter (keepEntrypoint token) }

def specFor (token : TokenSpec) : ProofForge.Contract.ContractSpec :=
  { fungibleSpec with
    name := token.symbol
    module := moduleFor token }

end ProofForge.Contract.Token.NearSpec