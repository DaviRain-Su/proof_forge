import ProofForge.Contract.Token.Learn
import ProofForge.Target.Registry

namespace ProofForge.Tests.TokenLearn

open ProofForge.Contract.Token
open ProofForge.Contract.Token.Learn
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def hasOperation (plan : TokenPlan) (operation : String) : Bool :=
  plan.operations.any (fun item => item == operation)

def parseFixture (path : String) : IO TokenDecl := do
  match (← parseFile (System.FilePath.mk path)) with
  | .ok decl => pure decl
  | .error err => throw <| IO.userError err

def main : IO UInt32 := do
  let proofToken ← parseFixture "Examples/Backend/Learn/ProofToken.learn"
  require (proofToken.id == "ProofToken") "ProofToken id did not parse"
  require (proofToken.spec.name == "Proof Token") "ProofToken display name did not parse"
  require (proofToken.spec.symbol == "PRF") "ProofToken symbol did not parse"
  require (proofToken.spec.decimals == 9) "ProofToken decimals did not parse"
  require (proofToken.spec.initialSupply? == some 1000000) "ProofToken initial supply did not parse"
  require (proofToken.spec.hasFeature .mintable) "ProofToken missing mintable feature"
  require (proofToken.spec.hasFeature .burnable) "ProofToken missing burnable feature"

  let evmPlan ←
    match planForTarget evm proofToken.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (evmPlan.standard == .erc20) "ProofToken EVM plan should use ERC-20"
  require (evmPlan.artifactKind == .evmErc20Contract)
    "ProofToken EVM plan should emit ERC-20 contract artifact"
  require (hasOperation evmPlan "erc20.mint") "ProofToken EVM plan missing mint operation"

  let solanaPlan ←
    match planForTarget solanaSbpfAsm proofToken.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (solanaPlan.standard == .splToken) "ProofToken Solana plan should use SPL Token"
  require (solanaPlan.artifactKind == .solanaSplTokenPlan)
    "ProofToken Solana plan should emit SPL Token plan"

  let feeToken ← parseFixture "Examples/Backend/Learn/FeeToken.learn"
  require (feeToken.spec.hasFeature .transferFee) "FeeToken missing transfer_fee feature"
  let feePlan ←
    match planForTarget solanaSbpfAsm feeToken.spec with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (feePlan.standard == .splToken2022) "FeeToken Solana plan should use Token-2022"
  require (hasOperation feePlan "token-2022.extension.transfer_fee")
    "FeeToken plan missing Token-2022 transfer-fee extension"

  match parse "token Bad { name \"Bad\" symbol \"BAD\" decimals 9 feature weird }" with
  | .ok _ => throw <| IO.userError "unknown token feature unexpectedly parsed"
  | .error err =>
      require (err.contains "unknown token feature `weird`")
        s!"unexpected unknown-feature diagnostic: {err}"

  IO.println "token-learn: ok"
  return 0

end ProofForge.Tests.TokenLearn

def main : IO UInt32 :=
  ProofForge.Tests.TokenLearn.main
