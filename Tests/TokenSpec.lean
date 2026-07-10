import ProofForge.Contract.Token
import ProofForge.Target.Registry

namespace ProofForge.Tests.TokenSpec

open ProofForge.Contract.Token
open ProofForge.Target

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then
    pure ()
  else
    throw <| IO.userError message

def hasCapability (plan : TokenPlan) (capability : Capability) : Bool :=
  plan.capabilities.any (fun item => item == capability)

def hasOperation (plan : TokenPlan) (operation : String) : Bool :=
  plan.operations.any (fun item => item == operation)

def hasInstruction (deployment : SolanaTokenDeploymentPlan) (name : String) : Bool :=
  deployment.instructions.any (fun instruction => instruction.name == name)

def hasExtension (deployment : SolanaTokenDeploymentPlan) (name : String) : Bool :=
  deployment.extensions.any (fun extension => extension.extension == name)

def fungibleToken : TokenSpec := {
  name := "Proof Token"
  symbol := "PRF"
  decimals := 9
  initialSupply? := some 1000000
  features := #[.mintable, .burnable]
}

def transferFeeToken : TokenSpec := {
  name := "Fee Token"
  symbol := "FEE"
  decimals := 6
  initialSupply? := some 1000000
  features := #[.mintable, .transferFee]
}

def nonTransferableToken : TokenSpec := {
  name := "Soulbound Token"
  symbol := "SBT"
  decimals := 0
  initialSupply? := some 1
  features := #[.mintable, .burnable, .nonTransferable]
}

def main : IO UInt32 := do
  let evmPlan ←
    match planForTarget evm fungibleToken with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (evmPlan.standard == .erc20) "EVM token plan should use ERC-20"
  require (evmPlan.artifactKind == .evmErc20Contract) "EVM token plan should emit ERC-20 contract artifact"
  require (hasCapability evmPlan .storageMap) "EVM ERC-20 plan should use mapping storage"
  require (hasOperation evmPlan "erc20.transfer") "EVM ERC-20 plan missing transfer"
  require (hasOperation evmPlan "erc20.approve") "EVM ERC-20 plan missing approve"
  require (hasOperation evmPlan "erc20.mint") "EVM ERC-20 plan missing mintable extension"

  let oversizedEvmSupply : TokenSpec := {
    name := "Oversized EVM Supply"
    symbol := "BIG"
    decimals := 18
    initialSupply? := some 18446744073709551616
  }
  match planForTarget evm oversizedEvmSupply with
  | .ok _ =>
      throw <| IO.userError "EVM TokenSpec accepted initial supply above its u64 storage contract"
  | .error err =>
      require (err.contains "initialSupply" && err.contains "u64")
        s!"unexpected oversized EVM initial-supply diagnostic: {err}"

  let solanaPlan ←
    match planForTarget solanaSbpfAsm fungibleToken with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (solanaPlan.standard == .splToken) "Solana token plan should use SPL Token by default"
  require (solanaPlan.artifactKind == .solanaSplTokenPlan) "Solana token plan should emit SPL Token plan"
  require (hasCapability solanaPlan .crosscallCpi) "Solana SPL Token plan should use CPI"
  require (hasCapability solanaPlan .accountExplicit) "Solana SPL Token plan should use explicit accounts"
  require (hasOperation solanaPlan "spl-token.create_mint") "Solana SPL Token plan missing create_mint"
  require (hasOperation solanaPlan "spl-token.transfer_checked") "Solana SPL Token plan missing transfer_checked"
  require (hasOperation solanaPlan "spl-token.revoke") "Solana SPL Token plan missing revoke"
  require (hasOperation solanaPlan "spl-token.set_authority") "Solana SPL Token plan missing set_authority"

  let splDeployment ←
    match solanaTokenDeploymentPlan fungibleToken with
    | .ok deployment => pure deployment
    | .error err => throw <| IO.userError err
  require (splDeployment.standard == .splToken) "Lean TokenSpec should produce SPL Token deployment plan"
  require (splDeployment.tokenProgramId == solanaSplTokenProgramId) "SPL Token deployment uses wrong token program"
  require (splDeployment.associatedTokenProgramId == solanaAssociatedTokenProgramId)
    "SPL Token deployment uses wrong associated token program"
  require (hasInstruction splDeployment "create_mint_account")
    "SPL Token deployment missing mint account creation"
  require (hasInstruction splDeployment "initialize_mint")
    "SPL Token deployment missing initialize_mint"
  require (hasInstruction splDeployment "create_owner_ata")
    "SPL Token deployment missing owner associated token account creation"
  require (hasInstruction splDeployment "mint_to_initial_supply")
    "SPL Token deployment missing initial mint_to"
  require (hasInstruction splDeployment "mint_to")
    "SPL Token deployment missing mint_to interaction"
  require (hasInstruction splDeployment "transfer_checked")
    "SPL Token deployment missing transfer_checked"
  require (hasInstruction splDeployment "approve_delegate")
    "SPL Token deployment missing approve"
  require (hasInstruction splDeployment "burn")
    "SPL Token deployment missing burn"
  require (hasInstruction splDeployment "revoke_delegate")
    "SPL Token deployment missing revoke"
  require (hasInstruction splDeployment "set_mint_authority")
    "SPL Token deployment missing authority change"

  let token2022Plan ←
    match planForTarget solanaSbpfAsm transferFeeToken with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (token2022Plan.standard == .splToken2022) "Solana transfer-fee token should use Token-2022"
  require (token2022Plan.artifactKind == .solanaToken2022Plan) "Solana transfer-fee token should emit Token-2022 plan"
  require (hasOperation token2022Plan "token-2022.extension.transfer_fee")
    "Token-2022 plan missing transfer-fee extension"
  require (hasOperation token2022Plan "token-2022.transfer_checked_with_fee")
    "Token-2022 plan missing transfer_checked_with_fee operation"
  require (hasOperation token2022Plan "token-2022.withdraw_withheld_tokens_from_accounts")
    "Token-2022 plan missing direct withheld-fee withdraw operation"
  require (hasOperation token2022Plan "token-2022.harvest_withheld_tokens_to_mint")
    "Token-2022 plan missing withheld-fee harvest operation"
  require (hasOperation token2022Plan "token-2022.withdraw_withheld_tokens_from_mint")
    "Token-2022 plan missing mint withheld-fee withdraw operation"
  let token2022Deployment ←
    match solanaTokenDeploymentPlan transferFeeToken with
    | .ok deployment => pure deployment
    | .error err => throw <| IO.userError err
  require (token2022Deployment.standard == .splToken2022)
    "Lean transfer-fee TokenSpec should produce Token-2022 deployment plan"
  require (token2022Deployment.tokenProgramId == solanaToken2022ProgramId)
    "Token-2022 deployment uses wrong token program"
  require (hasExtension token2022Deployment "transfer_fee_config")
    "Token-2022 deployment missing transfer-fee extension"
  require (hasInstruction token2022Deployment "initialize_transfer_fee_config")
    "Token-2022 deployment missing transfer-fee init instruction"
  require (hasInstruction token2022Deployment "initialize_mint")
    "Token-2022 deployment missing initialize_mint after extension setup"
  require (hasInstruction token2022Deployment "transfer_checked_with_fee")
    "Token-2022 deployment missing transfer_checked_with_fee instruction"
  require (hasInstruction token2022Deployment "withdraw_withheld_tokens_from_accounts")
    "Token-2022 deployment missing direct withheld-fee withdraw instruction"
  require (hasInstruction token2022Deployment "harvest_withheld_tokens_to_mint")
    "Token-2022 deployment missing withheld-fee harvest instruction"
  require (hasInstruction token2022Deployment "withdraw_withheld_tokens_from_mint")
    "Token-2022 deployment missing mint withheld-fee withdraw instruction"

  let nonTransferablePlan ←
    match planForTarget solanaSbpfAsm nonTransferableToken with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError err
  require (nonTransferablePlan.standard == .splToken2022)
    "Solana non-transferable token should use Token-2022"
  require (nonTransferablePlan.artifactKind == .solanaToken2022Plan)
    "Solana non-transferable token should emit Token-2022 plan"
  require (hasOperation nonTransferablePlan "token-2022.extension.non_transferable")
    "Token-2022 plan missing non-transferable extension"
  let nonTransferableDeployment ←
    match solanaTokenDeploymentPlan nonTransferableToken with
    | .ok deployment => pure deployment
    | .error err => throw <| IO.userError err
  require (nonTransferableDeployment.standard == .splToken2022)
    "Lean non-transferable TokenSpec should produce Token-2022 deployment plan"
  require (hasExtension nonTransferableDeployment "non_transferable")
    "Token-2022 deployment missing non-transferable extension"
  require (hasInstruction nonTransferableDeployment "initialize_non_transferable_mint")
    "Token-2022 deployment missing non-transferable init instruction"
  require (hasInstruction nonTransferableDeployment "initialize_mint")
    "Token-2022 deployment missing initialize_mint after non-transferable setup"

  let incompatibleToken : TokenSpec := {
    name := "Bad Fee Soulbound Token"
    symbol := "BAD"
    decimals := 9
    features := #[.transferFee, .nonTransferable]
  }
  match solanaTokenDeploymentPlan incompatibleToken with
  | .ok _ => throw <| IO.userError "incompatible Token-2022 feature set unexpectedly planned"
  | .error err =>
      require (err.contains "transfer_fee")
        s!"unexpected incompatible-feature diagnostic: {err}"

  let nearPlan ←
    match planForTarget wasmNear fungibleToken with
    | .ok plan => pure plan
    | .error err => throw <| IO.userError s!"wasm-near TokenSpec plan failed: {err}"
  require (nearPlan.standard == .nep141) "NEAR token plan should use NEP-141"
  require (nearPlan.artifactKind == .nearNep141Plan) "NEAR token plan should emit NEP-141 plan"
  require (hasOperation nearPlan "ft_transfer") "NEAR NEP-141 plan missing ft_transfer"
  require (hasOperation nearPlan "ft_balance_of") "NEAR NEP-141 plan missing ft_balance_of"
  require (hasOperation nearPlan "ft_mint") "NEAR NEP-141 plan missing mintable ft_mint"
  -- Token-2022-shaped features still reject on NEAR (no silent drop).
  match planForTarget wasmNear transferFeeToken with
  | .ok _ => throw <| IO.userError "wasm-near unexpectedly accepted transferFee TokenSpec"
  | .error err =>
      require (err.contains "transfer" || err.contains "Token-2022" || err.contains "feature" ||
          err.contains "near" || err.contains "NEAR" || err.contains "wasm-near")
        s!"unexpected NEAR transferFee reject: {err}"
  -- Hosts without a TokenSpec lane still fail closed.
  match planForTarget wasmStellarSoroban fungibleToken with
  | .ok _ => throw <| IO.userError "soroban unexpectedly accepted TokenSpec"
  | .error err =>
      require (err.contains "no TokenSpec lane" || err.contains "wasm-stellar-soroban")
        s!"unexpected no-lane diagnostic: {err}"

  IO.println "token-spec: ok"
  return 0

end ProofForge.Tests.TokenSpec

def main : IO UInt32 :=
  ProofForge.Tests.TokenSpec.main
