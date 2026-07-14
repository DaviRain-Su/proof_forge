import Examples.Product.FungibleToken
import ProofForge.Contract.Token
import ProofForge.Contract.Token.NearSpec
import ProofForge.Target.Registry

namespace ProofForge.Tests.NearTokenSpecRuntime

open ProofForge.IR

def require (condition : Bool) (message : String) : IO Unit :=
  unless condition do throw <| IO.userError message

def hasScalarWrite (body : Array Statement) (stateId : String) (expected : Literal) : Bool :=
  body.any fun statement =>
    match statement with
    | .effect (.storageScalarWrite actual (.literal value)) =>
        actual == stateId && value == expected
    | _ => false

def hasMapWrite (body : Array Statement) (stateId : String) (expected : Literal) : Bool :=
  body.any fun statement =>
    match statement with
    | .effect (.storageMapSet actual (.effect (.contextRead .accountId)) (.literal value)) =>
        actual == stateId && value == expected
    | _ => false

def run : IO Unit := do
  let token := Examples.Product.FungibleToken.spec
  let mod := ProofForge.Contract.Token.NearSpec.moduleFor token
  require (mod.name == "PRF") "TokenSpec symbol must name the NEAR module"
  let some init := mod.entrypoints.find? (fun entrypoint => entrypoint.name == "init")
    | throw <| IO.userError "TokenSpec NEAR runtime omitted init"
  require (hasScalarWrite init.body "totalSupply" (.u128 1000000))
    "TokenSpec initialSupply did not initialize totalSupply"
  require (hasScalarWrite init.body "decimals" (.u64 9))
    "TokenSpec decimals did not initialize metadata state"
  require (hasMapWrite init.body "balances" (.u128 1000000))
    "TokenSpec initialSupply did not initialize the deployer balance"
  let some metadata := mod.entrypoints.find? (fun entrypoint => entrypoint.name == "ft_metadata")
    | throw <| IO.userError "TokenSpec NEAR runtime omitted ft_metadata"
  match metadata.body with
  | #[.return (.structLit "FungibleTokenMetadata" fields)] =>
      require (fields.any (fun field => field == ("name", .literal (.string "Proof Token"))))
        "TokenSpec name did not reach ft_metadata"
      require (fields.any (fun field => field == ("symbol", .literal (.string "PRF"))))
        "TokenSpec symbol did not reach ft_metadata"
  | _ => throw <| IO.userError "TokenSpec ft_metadata body is not parameterized"
  require (mod.entrypoints.any (fun entrypoint => entrypoint.name == "ft_mint"))
    "mintable TokenSpec omitted ft_mint"
  require (mod.entrypoints.any (fun entrypoint => entrypoint.name == "ft_burn"))
    "burnable TokenSpec omitted ft_burn"
  let plain : ProofForge.Contract.Token.TokenSpec := {
    name := "Plain Token", symbol := "PLN", decimals := 6, initialSupply? := some 7
  }
  let plainModule := ProofForge.Contract.Token.NearSpec.moduleFor plain
  require (!plainModule.entrypoints.any (fun entrypoint => entrypoint.name == "ft_mint"))
    "TokenSpec without mintable retained ft_mint"
  require (!plainModule.entrypoints.any (fun entrypoint => entrypoint.name == "ft_burn"))
    "TokenSpec without burnable retained ft_burn"
  let overflow : ProofForge.Contract.Token.TokenSpec := {
    plain with initialSupply? := some 340282366920938463463374607431768211456
  }
  match ProofForge.Contract.Token.planForTarget ProofForge.Target.wasmNear overflow with
  | .error message =>
      require (message.contains "exceeds the U128 maximum")
        "oversized NEAR TokenSpec returned the wrong diagnostic"
  | .ok _ => throw <| IO.userError "oversized NEAR TokenSpec initial supply was accepted"
  IO.println "near-token-spec-runtime: ok"

end ProofForge.Tests.NearTokenSpecRuntime

def main : IO Unit :=
  ProofForge.Tests.NearTokenSpecRuntime.run
