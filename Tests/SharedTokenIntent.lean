import Examples.Shared.FungibleToken
import Examples.Shared.FeeToken
import ProofForge.Contract.Token.Learn
import ProofForge.Target.Registry

namespace ProofForge.Tests.SharedTokenIntent

open ProofForge.Contract.Token
open ProofForge.Contract.Token.Learn
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def requireEq [BEq α] [Repr α] (label : String) (actual expected : α) : IO Unit :=
  require (actual == expected)
    s!"{label} mismatch\nactual:\n{repr actual}\nexpected:\n{repr expected}"

def hasOperation (plan : TokenPlan) (operation : String) : Bool :=
  plan.operations.any (fun item => item == operation)

def hasInstruction (deployment : SolanaTokenDeploymentPlan) (name : String) : Bool :=
  deployment.instructions.any (fun instruction => instruction.name == name)

def parseFixture (path : String) : IO TokenDecl := do
  match (← parseFile (System.FilePath.mk path)) with
  | .ok decl => pure decl
  | .error err => throw <| IO.userError err

def requireSameSpec (label : String) (actual expected : TokenSpec) : IO Unit := do
  requireEq s!"{label} name" actual.name expected.name
  requireEq s!"{label} symbol" actual.symbol expected.symbol
  requireEq s!"{label} decimals" actual.decimals expected.decimals
  requireEq s!"{label} initialSupply" actual.initialSupply? expected.initialSupply?
  requireEq s!"{label} features" actual.features expected.features

def requirePlanForTarget
    (target : TargetProfile) (spec : TokenSpec) : IO TokenPlan := do
  match planForTarget target spec with
  | .ok plan => pure plan
  | .error err => throw <| IO.userError err

def main : IO UInt32 := do
  requireEq "shared token id" Examples.Shared.FungibleToken.id "FungibleToken"
  requireEq "shared fee token id" Examples.Shared.FeeToken.id "FeeToken"

  let proofToken ← parseFixture "Examples/Learn/ProofToken.learn"
  requireSameSpec "legacy ProofToken vs shared FungibleToken"
    proofToken.spec Examples.Shared.FungibleToken.spec
  let feeToken ← parseFixture "Examples/Learn/FeeToken.learn"
  requireSameSpec "legacy FeeToken vs shared FeeToken"
    feeToken.spec Examples.Shared.FeeToken.spec

  let sharedEvmPlan ← requirePlanForTarget evm Examples.Shared.FungibleToken.spec
  let legacyEvmPlan ← requirePlanForTarget evm proofToken.spec
  requireEq "shared-vs-legacy EVM artifact kind"
    sharedEvmPlan.artifactKind legacyEvmPlan.artifactKind
  requireEq "shared-vs-legacy EVM operations"
    sharedEvmPlan.operations legacyEvmPlan.operations
  require (hasOperation sharedEvmPlan "erc20.transfer")
    "shared token EVM plan missing target-specific transfer operation"

  let sharedSolanaPlan ← requirePlanForTarget solanaSbpfAsm Examples.Shared.FungibleToken.spec
  let legacySolanaPlan ← requirePlanForTarget solanaSbpfAsm proofToken.spec
  requireEq "shared-vs-legacy Solana artifact kind"
    sharedSolanaPlan.artifactKind legacySolanaPlan.artifactKind
  requireEq "shared-vs-legacy Solana operations"
    sharedSolanaPlan.operations legacySolanaPlan.operations
  require (hasOperation sharedSolanaPlan "spl-token.transfer_checked")
    "shared token Solana plan missing target-specific transfer operation"

  let deployment ←
    match solanaTokenDeploymentPlan Examples.Shared.FungibleToken.spec with
    | .ok deployment => pure deployment
    | .error err => throw <| IO.userError err
  require (hasInstruction deployment "initialize_mint")
    "shared token Solana deployment missing initialize_mint"
  require (hasInstruction deployment "transfer_checked")
    "shared token Solana deployment missing transfer_checked"

  let sharedFeeSolanaPlan ← requirePlanForTarget solanaSbpfAsm Examples.Shared.FeeToken.spec
  let legacyFeeSolanaPlan ← requirePlanForTarget solanaSbpfAsm feeToken.spec
  requireEq "shared-vs-legacy fee Solana standard"
    sharedFeeSolanaPlan.standard legacyFeeSolanaPlan.standard
  requireEq "shared-vs-legacy fee Solana operations"
    sharedFeeSolanaPlan.operations legacyFeeSolanaPlan.operations
  require (sharedFeeSolanaPlan.standard == .splToken2022)
    "shared FeeToken Solana plan should use Token-2022"
  require (hasOperation sharedFeeSolanaPlan "token-2022.extension.transfer_fee")
    "shared FeeToken Solana plan missing transfer-fee extension"
  let feeDeployment ←
    match solanaTokenDeploymentPlan Examples.Shared.FeeToken.spec with
    | .ok deployment => pure deployment
    | .error err => throw <| IO.userError err
  require (hasInstruction feeDeployment "initialize_transfer_fee_config")
    "shared FeeToken deployment missing transfer-fee config init"
  require (hasInstruction feeDeployment "transfer_checked_with_fee")
    "shared FeeToken deployment missing transfer_checked_with_fee"

  match planForTarget wasmNear Examples.Shared.FungibleToken.spec with
  | .ok _ => throw <| IO.userError "shared token unexpectedly lowered to wasm-near"
  | .error err =>
      require (err == "target `wasm-near` does not have a TokenSpec lowering plan yet")
        s!"unexpected shared token NEAR diagnostic: {err}"

  IO.println "shared-token-intent: ok"
  return 0

end ProofForge.Tests.SharedTokenIntent

def main : IO UInt32 :=
  ProofForge.Tests.SharedTokenIntent.main
