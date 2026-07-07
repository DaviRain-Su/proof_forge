use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::token_2022::{
    account_withheld_amount, assert_transfer_fee_config, calculate_epoch_fee,
    create_empty_associated_token_account, create_transfer_fee_mint,
    harvest_withheld_tokens_to_mint, mint_to, mint_withheld_amount, parse_account, parse_mint,
    token_2022_program_id, transfer_checked_with_fee, withdraw_withheld_tokens_from_accounts,
    withdraw_withheld_tokens_from_mint, TOKEN_2022_PROGRAM_ID,
};
use serde::Deserialize;
use serde_json::json;
use solana_address::Address;
use solana_keypair::Keypair;
use solana_signer::Signer;

const ASSOCIATED_TOKEN_PROGRAM_ID: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
const SYSTEM_PROGRAM_ID: &str = "11111111111111111111111111111111";

#[derive(Debug, Deserialize)]
struct TokenPlan {
    format: String,
    token: TokenInfo,
    #[serde(rename = "targetFamily")]
    target_family: String,
    standard: String,
    #[serde(default)]
    operations: Vec<String>,
    solana: SolanaPlan,
}

#[derive(Debug, Deserialize)]
struct TokenInfo {
    id: String,
    decimals: u64,
    #[serde(rename = "initialSupply")]
    initial_supply: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct SolanaPlan {
    programs: SolanaPrograms,
    #[serde(default)]
    instructions: Vec<PlanInstruction>,
    #[serde(default)]
    extensions: Vec<PlanExtension>,
}

#[derive(Debug, Deserialize)]
struct SolanaPrograms {
    token: String,
    #[serde(rename = "associatedToken")]
    associated_token: String,
    system: String,
}

#[derive(Debug, Deserialize)]
struct PlanInstruction {
    order: i64,
    name: String,
}

#[derive(Debug, Deserialize)]
struct PlanExtension {
    extension: String,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let rpc_url =
        env::var("PROOF_FORGE_SOLANA_RPC_URL").context("missing PROOF_FORGE_SOLANA_RPC_URL")?;
    let payer_path =
        env::var("PROOF_FORGE_SOLANA_PAYER").context("missing PROOF_FORGE_SOLANA_PAYER")?;
    let plan_path = env::var("PROOF_FORGE_SOLANA_TOKEN_PLAN")
        .context("missing PROOF_FORGE_SOLANA_TOKEN_PLAN")?;
    let plan_path = PathBuf::from(plan_path);
    let plan = load_plan(&plan_path)?;
    validate_plan(&plan)?;

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let owner = &payer;
    let mint_authority = &payer;
    let withdraw_withheld_authority = &payer;
    let recipient = Keypair::new();
    let harvest_recipient = Keypair::new();
    let fee_receiver = Keypair::new();
    let decimals = u8::try_from(plan.token.decimals).context("token decimals must fit in u8")?;
    let initial_supply = plan.token.initial_supply.unwrap_or(0);
    let transfer_fee_basis_points = env_u16("PROOF_FORGE_SOLANA_TRANSFER_FEE_BPS", 125)?;
    ensure!(
        transfer_fee_basis_points <= 10_000,
        "invalid transfer fee basis points: {transfer_fee_basis_points}"
    );
    let maximum_fee = env_u64("PROOF_FORGE_SOLANA_TRANSFER_FEE_MAX_FEE", 10_000)?;
    let transfer_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_PLAN_TRANSFER_AMOUNT", 250_000)?;
    let required_supply = transfer_amount
        .checked_mul(2)
        .context("transfer amount overflow")?;
    ensure!(
        initial_supply > required_supply,
        "initial supply {initial_supply} is too small for two transfers of {transfer_amount}"
    );

    let mint = create_transfer_fee_mint(
        &rpc,
        &payer,
        decimals,
        mint_authority.pubkey(),
        mint_authority.pubkey(),
        withdraw_withheld_authority.pubkey(),
        transfer_fee_basis_points,
        maximum_fee,
    )
    .context("failed to create Token-2022 transfer-fee mint")?;
    let mut mint_data = rpc.account_data(mint.pubkey())?;
    assert_transfer_fee_config(
        &mint_data,
        mint_authority.pubkey(),
        withdraw_withheld_authority.pubkey(),
        transfer_fee_basis_points,
        maximum_fee,
    )?;
    let mut mint_account = parse_mint(&mint_data)?;
    ensure!(
        mint_account.is_initialized,
        "Token-2022 mint should be initialized"
    );
    ensure!(
        mint_account.decimals == decimals,
        "Token-2022 mint decimals mismatch: expected {decimals}, got {}",
        mint_account.decimals
    );
    ensure!(
        mint_account.supply == 0,
        "Token-2022 mint should start with zero supply, got {}",
        mint_account.supply
    );

    let owner_ata =
        create_empty_associated_token_account(&rpc, &payer, owner.pubkey(), mint.pubkey())
            .context("failed to create owner Token-2022 ATA")?;
    let recipient_ata =
        create_empty_associated_token_account(&rpc, &payer, recipient.pubkey(), mint.pubkey())
            .context("failed to create recipient Token-2022 ATA")?;
    let harvest_recipient_ata = create_empty_associated_token_account(
        &rpc,
        &payer,
        harvest_recipient.pubkey(),
        mint.pubkey(),
    )
    .context("failed to create harvest-recipient Token-2022 ATA")?;
    let fee_receiver_ata =
        create_empty_associated_token_account(&rpc, &payer, fee_receiver.pubkey(), mint.pubkey())
            .context("failed to create fee-receiver Token-2022 ATA")?;
    verify_empty_transfer_fee_account(
        &rpc.account_data(owner_ata)?,
        mint.pubkey(),
        owner.pubkey(),
        "owner",
    )?;
    verify_empty_transfer_fee_account(
        &rpc.account_data(recipient_ata)?,
        mint.pubkey(),
        recipient.pubkey(),
        "recipient",
    )?;
    verify_empty_transfer_fee_account(
        &rpc.account_data(harvest_recipient_ata)?,
        mint.pubkey(),
        harvest_recipient.pubkey(),
        "harvest recipient",
    )?;
    verify_empty_transfer_fee_account(
        &rpc.account_data(fee_receiver_ata)?,
        mint.pubkey(),
        fee_receiver.pubkey(),
        "fee receiver",
    )?;

    let mint_to_signature = mint_to(
        &rpc,
        &payer,
        mint.pubkey(),
        owner_ata,
        mint_authority,
        initial_supply,
    )
    .context("failed to mint initial Token-2022 supply")?;
    let mut owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    let mut recipient_account = parse_account(&rpc.account_data(recipient_ata)?)?;
    let mut harvest_recipient_account = parse_account(&rpc.account_data(harvest_recipient_ata)?)?;
    let mut fee_receiver_account = parse_account(&rpc.account_data(fee_receiver_ata)?)?;
    mint_data = rpc.account_data(mint.pubkey())?;
    mint_account = parse_mint(&mint_data)?;
    ensure!(
        owner_account.amount == initial_supply,
        "owner after initial mint mismatch: expected {initial_supply}, got {}",
        owner_account.amount
    );
    ensure!(
        recipient_account.amount == 0,
        "recipient initial amount mismatch: expected 0, got {}",
        recipient_account.amount
    );
    ensure!(
        harvest_recipient_account.amount == 0,
        "harvest recipient initial amount mismatch: expected 0, got {}",
        harvest_recipient_account.amount
    );
    ensure!(
        fee_receiver_account.amount == 0,
        "fee receiver initial amount mismatch: expected 0, got {}",
        fee_receiver_account.amount
    );
    ensure!(
        mint_account.supply == initial_supply,
        "supply after initial mint mismatch: expected {initial_supply}, got {}",
        mint_account.supply
    );

    let current_epoch = rpc.epoch_info()?.epoch;
    let expected_fee = calculate_epoch_fee(&mint_data, current_epoch, transfer_amount)
        .context("failed to calculate expected transfer fee")?;
    let transfer_signature = transfer_checked_with_fee(
        &rpc,
        &payer,
        owner_ata,
        mint.pubkey(),
        recipient_ata,
        owner,
        transfer_amount,
        decimals,
        expected_fee,
    )
    .context("transfer_checked_with_fee failed")?;
    owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    recipient_account = parse_account(&rpc.account_data(recipient_ata)?)?;
    let recipient_withheld_fee =
        account_withheld_amount(&rpc.account_data(recipient_ata)?, "recipient")?;
    let recipient_net = transfer_amount
        .checked_sub(expected_fee)
        .context("recipient transfer amount underflow")?;
    ensure!(
        owner_account.amount == initial_supply - transfer_amount,
        "owner after transfer_checked_with_fee mismatch: expected {}, got {}",
        initial_supply - transfer_amount,
        owner_account.amount
    );
    ensure!(
        recipient_account.amount == recipient_net,
        "recipient after transfer_checked_with_fee mismatch: expected {recipient_net}, got {}",
        recipient_account.amount
    );
    ensure!(
        recipient_withheld_fee == expected_fee,
        "recipient withheld transfer fee mismatch: expected {expected_fee}, got {recipient_withheld_fee}"
    );

    let withdraw_from_accounts_signature = withdraw_withheld_tokens_from_accounts(
        &rpc,
        &payer,
        mint.pubkey(),
        fee_receiver_ata,
        withdraw_withheld_authority,
        &[recipient_ata],
    )
    .context("withdraw_withheld_tokens_from_accounts failed")?;
    recipient_account = parse_account(&rpc.account_data(recipient_ata)?)?;
    fee_receiver_account = parse_account(&rpc.account_data(fee_receiver_ata)?)?;
    let recipient_withheld_after_withdraw =
        account_withheld_amount(&rpc.account_data(recipient_ata)?, "recipient")?;
    ensure!(
        recipient_withheld_after_withdraw == 0,
        "recipient withheld fee after direct withdraw mismatch: expected 0, got {recipient_withheld_after_withdraw}"
    );
    ensure!(
        fee_receiver_account.amount == expected_fee,
        "fee receiver after direct withdraw mismatch: expected {expected_fee}, got {}",
        fee_receiver_account.amount
    );

    let harvest_transfer_signature = transfer_checked_with_fee(
        &rpc,
        &payer,
        owner_ata,
        mint.pubkey(),
        harvest_recipient_ata,
        owner,
        transfer_amount,
        decimals,
        expected_fee,
    )
    .context("harvest-path transfer_checked_with_fee failed")?;
    owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    harvest_recipient_account = parse_account(&rpc.account_data(harvest_recipient_ata)?)?;
    let harvest_recipient_withheld_fee = account_withheld_amount(
        &rpc.account_data(harvest_recipient_ata)?,
        "harvest recipient",
    )?;
    ensure!(
        owner_account.amount == initial_supply - required_supply,
        "owner after harvest-path transfer mismatch: expected {}, got {}",
        initial_supply - required_supply,
        owner_account.amount
    );
    ensure!(
        harvest_recipient_account.amount == recipient_net,
        "harvest recipient after transfer_checked_with_fee mismatch: expected {recipient_net}, got {}",
        harvest_recipient_account.amount
    );
    ensure!(
        harvest_recipient_withheld_fee == expected_fee,
        "harvest recipient withheld transfer fee mismatch: expected {expected_fee}, got {harvest_recipient_withheld_fee}"
    );

    let harvest_to_mint_signature =
        harvest_withheld_tokens_to_mint(&rpc, &payer, mint.pubkey(), &[harvest_recipient_ata])
            .context("harvest_withheld_tokens_to_mint failed")?;
    let harvest_recipient_withheld_after_harvest = account_withheld_amount(
        &rpc.account_data(harvest_recipient_ata)?,
        "harvest recipient",
    )?;
    mint_data = rpc.account_data(mint.pubkey())?;
    let mint_withheld_after_harvest = mint_withheld_amount(&mint_data)?;
    ensure!(
        harvest_recipient_withheld_after_harvest == 0,
        "harvest recipient withheld fee after harvest mismatch: expected 0, got {harvest_recipient_withheld_after_harvest}"
    );
    ensure!(
        mint_withheld_after_harvest == expected_fee,
        "mint withheld fee after harvest mismatch: expected {expected_fee}, got {mint_withheld_after_harvest}"
    );

    let withdraw_from_mint_signature = withdraw_withheld_tokens_from_mint(
        &rpc,
        &payer,
        mint.pubkey(),
        fee_receiver_ata,
        withdraw_withheld_authority,
    )
    .context("withdraw_withheld_tokens_from_mint failed")?;
    fee_receiver_account = parse_account(&rpc.account_data(fee_receiver_ata)?)?;
    mint_data = rpc.account_data(mint.pubkey())?;
    let mint_withheld_after_withdraw = mint_withheld_amount(&mint_data)?;
    let total_expected_fee = expected_fee
        .checked_mul(2)
        .context("expected fee overflow")?;
    ensure!(
        fee_receiver_account.amount == total_expected_fee,
        "fee receiver after mint withdraw mismatch: expected {total_expected_fee}, got {}",
        fee_receiver_account.amount
    );
    ensure!(
        mint_withheld_after_withdraw == 0,
        "mint withheld fee after mint withdraw mismatch: expected 0, got {mint_withheld_after_withdraw}"
    );

    println!(
        "{}",
        json!({
            "standard": plan.standard,
            "token": plan.token.id,
            "mint": mint.pubkey().to_string(),
            "owner": owner.pubkey().to_string(),
            "ownerAta": owner_ata.to_string(),
            "recipient": recipient.pubkey().to_string(),
            "recipientAta": recipient_ata.to_string(),
            "harvestRecipient": harvest_recipient.pubkey().to_string(),
            "harvestRecipientAta": harvest_recipient_ata.to_string(),
            "feeReceiver": fee_receiver.pubkey().to_string(),
            "feeReceiverAta": fee_receiver_ata.to_string(),
            "tokenProgram": token_2022_program_id().to_string(),
            "decimals": decimals,
            "initialSupply": initial_supply.to_string(),
            "transferAmount": transfer_amount.to_string(),
            "transferFeeBasisPoints": transfer_fee_basis_points,
            "maximumFee": maximum_fee.to_string(),
            "currentEpoch": current_epoch,
            "expectedFee": expected_fee.to_string(),
            "ownerFinal": owner_account.amount.to_string(),
            "recipientFinal": recipient_account.amount.to_string(),
            "harvestRecipientFinal": harvest_recipient_account.amount.to_string(),
            "feeReceiverFinal": fee_receiver_account.amount.to_string(),
            "recipientWithheldFeeAfterWithdraw": recipient_withheld_after_withdraw.to_string(),
            "harvestRecipientWithheldFeeAfterHarvest": harvest_recipient_withheld_after_harvest.to_string(),
            "mintWithheldFeeAfterWithdraw": mint_withheld_after_withdraw.to_string(),
            "signatures": {
                "mintTo": mint_to_signature,
                "transfer": transfer_signature,
                "withdrawFromAccounts": withdraw_from_accounts_signature,
                "harvestTransfer": harvest_transfer_signature,
                "harvestToMint": harvest_to_mint_signature,
                "withdrawFromMint": withdraw_from_mint_signature,
            },
        })
    );

    Ok(())
}

fn load_plan(path: &Path) -> Result<TokenPlan> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("failed to read token plan {}", path.display()))?;
    serde_json::from_str(&contents)
        .with_context(|| format!("failed to parse token plan {}", path.display()))
}

fn validate_plan(plan: &TokenPlan) -> Result<()> {
    ensure!(
        plan.format == "proof-forge-token-plan-v0",
        "unexpected token plan format: {}",
        plan.format
    );
    ensure!(
        plan.target_family == "solana",
        "token plan is not a Solana plan: {}",
        plan.target_family
    );
    ensure!(
        plan.standard == "spl-token-2022",
        "live transfer-fee smoke expects a Token-2022 plan, got {}",
        plan.standard
    );
    ensure!(
        plan.operations
            .iter()
            .any(|operation| operation == "token-2022.extension.transfer_fee"),
        "plan is missing transfer-fee operation"
    );
    ensure!(
        plan.solana.programs.token == TOKEN_2022_PROGRAM_ID,
        "Token-2022 program id mismatch: {}",
        plan.solana.programs.token
    );
    ensure!(
        plan.solana.programs.associated_token == ASSOCIATED_TOKEN_PROGRAM_ID,
        "Associated Token program id mismatch: {}",
        plan.solana.programs.associated_token
    );
    ensure!(
        plan.solana.programs.system == SYSTEM_PROGRAM_ID,
        "System program id mismatch: {}",
        plan.solana.programs.system
    );
    ensure!(
        plan.solana
            .extensions
            .iter()
            .any(|extension| extension.extension == "transfer_fee_config"),
        "plan missing transfer_fee_config extension"
    );
    for name in [
        "create_mint_account",
        "initialize_transfer_fee_config",
        "initialize_mint",
        "create_owner_ata",
        "create_recipient_ata",
        "mint_to_initial_supply",
        "transfer_checked",
        "transfer_checked_with_fee",
        "withdraw_withheld_tokens_from_accounts",
        "harvest_withheld_tokens_to_mint",
        "withdraw_withheld_tokens_from_mint",
    ] {
        ensure!(
            plan.solana
                .instructions
                .iter()
                .any(|instruction| instruction.name == name),
            "missing planned instruction: {name}"
        );
    }
    let init_transfer_fee_order = instruction_order(plan, "initialize_transfer_fee_config")?;
    let initialize_mint_order = instruction_order(plan, "initialize_mint")?;
    ensure!(
        init_transfer_fee_order < initialize_mint_order,
        "transfer-fee config must be initialized before initialize_mint"
    );
    Ok(())
}

fn instruction_order(plan: &TokenPlan, name: &str) -> Result<i64> {
    plan.solana
        .instructions
        .iter()
        .find(|instruction| instruction.name == name)
        .map(|instruction| instruction.order)
        .with_context(|| format!("missing planned instruction: {name}"))
}

fn verify_empty_transfer_fee_account(
    data: &[u8],
    mint: Address,
    owner: Address,
    label: &str,
) -> Result<()> {
    let account = parse_account(data)?;
    ensure!(
        account.mint == mint,
        "{label} account mint mismatch: expected {mint}, got {}",
        account.mint
    );
    ensure!(
        account.owner == owner,
        "{label} account owner mismatch: expected {owner}, got {}",
        account.owner
    );
    ensure!(
        account.amount == 0,
        "{label} account should be empty, got {}",
        account.amount
    );
    let withheld_amount = account_withheld_amount(data, label)?;
    ensure!(
        withheld_amount == 0,
        "{label} account withheld fee should start at zero, got {withheld_amount}"
    );
    Ok(())
}

fn env_u16(name: &str, default: u16) -> Result<u16> {
    env::var(name)
        .ok()
        .map(|value| {
            value
                .parse::<u16>()
                .with_context(|| format!("invalid {name}={value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(default))
}

fn env_u64(name: &str, default: u64) -> Result<u64> {
    env::var(name)
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid {name}={value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(default))
}
