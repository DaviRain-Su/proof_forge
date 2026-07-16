/-
Copyright (c) 2026 DaviRain. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.

Build executable NEP-141 `ContractSpec` values from Lean `TokenSpec` metadata.

This mirrors `EvmSpec.lean` for EVM: it takes a portable `TokenSpec` and produces
a `ContractSpec` whose module is the `NearFungibleToken` stdlib with feature-gated
entrypoints (mint/burn) and token-specific metadata/initial supply.
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
  (entrypoint.name != "ft_mint" || token.hasFeature .mintable) &&
    (entrypoint.name != "ft_burn" || token.hasFeature .burnable)

private def initialSupply (token : TokenSpec) : Nat :=
  token.initialSupply?.getD 0

private def metadataValue (token : TokenSpec) : Expr :=
  .structLit "FungibleTokenMetadata" #[
    ("spec", .literal (.string "ft-1.0.0")),
    ("name", .literal (.string token.name)),
    ("symbol", .literal (.string token.symbol)),
    ("icon", .literal (.string "")),
    ("reference", .literal (.string "")),
    ("decimals", .effect (.storageScalarRead "decimals"))
  ]

private def parameterizeInitStatement (token : TokenSpec) : Statement → Statement
  | .effect (.storageScalarWrite "totalSupply" _) =>
      .effect (.storageScalarWrite "totalSupply" (.literal (.u128 (initialSupply token))))
  | .effect (.storageScalarWrite "decimals" _) =>
      .effect (.storageScalarWrite "decimals" (.literal (.u64 token.decimals)))
  | statement => statement

private def initialOwnerStatements (token : TokenSpec) : Array Statement :=
  let owner := Expr.effect (.contextRead .accountId)
  #[
    .effect (.storageMapSet "balances" owner (.literal (.u128 (initialSupply token)))),
    .effect (.storageMapSet "storageDeposits" owner
      (.effect (.storageScalarRead "storageRequired"))),
    .effect (.storageMapSet "storageBytes" owner (.literal (.u64 1)))
  ]

private def parameterizeEntrypoint (token : TokenSpec) (entrypoint : Entrypoint) : Entrypoint :=
  if entrypoint.name == "init" then
    { entrypoint with
      body := entrypoint.body.map (parameterizeInitStatement token) ++
        initialOwnerStatements token }
  else if entrypoint.name == "ft_metadata" then
    { entrypoint with body := #[.return (metadataValue token)] }
  else
    entrypoint

def moduleFor (token : TokenSpec) : Module :=
  let base := fungibleSpec.module
  { base with
    name := token.symbol
    entrypoints := base.entrypoints.filter (keepEntrypoint token) |>.map
      (parameterizeEntrypoint token) }

def specFor (token : TokenSpec) : ProofForge.Contract.ContractSpec :=
  { fungibleSpec with
    name := token.symbol
    module := moduleFor token }

end ProofForge.Contract.Token.NearSpec
