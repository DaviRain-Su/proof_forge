use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    approve_delegate, burn, create_empty_associated_token_account, create_mint, mint_to,
    parse_mint_account, parse_token_account, revoke_delegate, revoke_mint_authority,
    spl_token_program_id, transfer_checked, ASSOCIATED_TOKEN_PROGRAM_ID, SPL_TOKEN_PROGRAM_ID,
};
use serde::Deserialize;
use serde_json::json;
use solana_keypair::Keypair;
use solana_signer::Signer;

const SYSTEM_PROGRAM_ID: &str = "11111111111111111111111111111111";

#[derive(Debug, Deserialize)]
struct TokenPlan {
    format: String,
    token: TokenInfo,
    #[serde(rename = "targetFamily")]
    target_family: String,
    standard: String,
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
    name: String,
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
    let recipient = Keypair::new();
    let delegate = Keypair::new();
    let decimals = u8::try_from(plan.token.decimals).context("token decimals must fit in u8")?;
    let initial_supply = plan.token.initial_supply.unwrap_or(0);
    let mint_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_PLAN_MINT_AMOUNT", 125_000)?;
    let transfer_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_PLAN_TRANSFER_AMOUNT", 250_000)?;
    let approve_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_PLAN_APPROVE_AMOUNT", 333_000)?;
    let burn_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_PLAN_BURN_AMOUNT", 75_000)?;
    ensure!(
        initial_supply > transfer_amount.saturating_add(burn_amount),
        "initial supply {initial_supply} is too small for transfer {transfer_amount} and burn {burn_amount}"
    );

    let mint = create_mint(&rpc, &payer, decimals, mint_authority.pubkey())
        .context("failed to create SPL Token mint")?;
    let owner_ata =
        create_empty_associated_token_account(&rpc, &payer, owner.pubkey(), mint.pubkey())
            .context("failed to create owner associated token account")?;
    let recipient_ata =
        create_empty_associated_token_account(&rpc, &payer, recipient.pubkey(), mint.pubkey())
            .context("failed to create recipient associated token account")?;

    mint_to(
        &rpc,
        &payer,
        mint.pubkey(),
        owner_ata,
        mint_authority,
        initial_supply,
    )
    .context("failed to mint initial token supply")?;

    let mut owner_account = parse_token_account(&rpc.account_data(owner_ata)?)?;
    let mut recipient_account = parse_token_account(&rpc.account_data(recipient_ata)?)?;
    let mut mint_account = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
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
        mint_account.supply == initial_supply,
        "supply after initial mint mismatch: expected {initial_supply}, got {}",
        mint_account.supply
    );

    let mint_signature = mint_to(
        &rpc,
        &payer,
        mint.pubkey(),
        owner_ata,
        mint_authority,
        mint_amount,
    )
    .context("planned mint_to failed")?;
    owner_account = parse_token_account(&rpc.account_data(owner_ata)?)?;
    mint_account = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    let expected_owner_after_mint = initial_supply
        .checked_add(mint_amount)
        .context("owner amount overflow after mint_to")?;
    ensure!(
        owner_account.amount == expected_owner_after_mint,
        "owner after planned mint_to mismatch: expected {expected_owner_after_mint}, got {}",
        owner_account.amount
    );
    ensure!(
        mint_account.supply == expected_owner_after_mint,
        "supply after planned mint_to mismatch: expected {expected_owner_after_mint}, got {}",
        mint_account.supply
    );

    let transfer_signature = transfer_checked(
        &rpc,
        &payer,
        owner_ata,
        mint.pubkey(),
        recipient_ata,
        owner,
        transfer_amount,
        decimals,
    )
    .context("planned transfer_checked failed")?;
    owner_account = parse_token_account(&rpc.account_data(owner_ata)?)?;
    recipient_account = parse_token_account(&rpc.account_data(recipient_ata)?)?;
    let expected_owner_after_transfer = expected_owner_after_mint
        .checked_sub(transfer_amount)
        .context("owner amount underflow after transfer_checked")?;
    ensure!(
        owner_account.amount == expected_owner_after_transfer,
        "owner after transfer_checked mismatch: expected {expected_owner_after_transfer}, got {}",
        owner_account.amount
    );
    ensure!(
        recipient_account.amount == transfer_amount,
        "recipient after transfer_checked mismatch: expected {transfer_amount}, got {}",
        recipient_account.amount
    );

    let approve_signature = approve_delegate(
        &rpc,
        &payer,
        owner_ata,
        delegate.pubkey(),
        owner,
        approve_amount,
    )
    .context("planned approve_delegate failed")?;
    owner_account = parse_token_account(&rpc.account_data(owner_ata)?)?;
    ensure!(
        owner_account.delegate == Some(delegate.pubkey()),
        "delegate mismatch after approve: expected {}, got {:?}",
        delegate.pubkey(),
        owner_account.delegate
    );
    ensure!(
        owner_account.delegated_amount == approve_amount,
        "delegated amount after approve mismatch: expected {approve_amount}, got {}",
        owner_account.delegated_amount
    );

    let burn_signature = burn(&rpc, &payer, owner_ata, mint.pubkey(), owner, burn_amount)
        .context("planned burn failed")?;
    owner_account = parse_token_account(&rpc.account_data(owner_ata)?)?;
    mint_account = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    let expected_owner_after_burn = expected_owner_after_transfer
        .checked_sub(burn_amount)
        .context("owner amount underflow after burn")?;
    let expected_supply_after_burn = expected_owner_after_mint
        .checked_sub(burn_amount)
        .context("mint supply underflow after burn")?;
    ensure!(
        owner_account.amount == expected_owner_after_burn,
        "owner after burn mismatch: expected {expected_owner_after_burn}, got {}",
        owner_account.amount
    );
    ensure!(
        mint_account.supply == expected_supply_after_burn,
        "supply after burn mismatch: expected {expected_supply_after_burn}, got {}",
        mint_account.supply
    );

    let revoke_signature = revoke_delegate(&rpc, &payer, owner_ata, owner)
        .context("planned revoke_delegate failed")?;
    owner_account = parse_token_account(&rpc.account_data(owner_ata)?)?;
    ensure!(
        owner_account.delegate.is_none(),
        "delegate should be cleared after revoke: {:?}",
        owner_account.delegate
    );
    ensure!(
        owner_account.delegated_amount == 0,
        "delegated amount should be zero after revoke: {}",
        owner_account.delegated_amount
    );

    let set_authority_signature =
        revoke_mint_authority(&rpc, &payer, mint.pubkey(), mint_authority)
            .context("planned set_mint_authority failed")?;
    mint_account = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    ensure!(
        mint_account.mint_authority.is_none(),
        "mint authority should be revoked after set_authority: {:?}",
        mint_account.mint_authority
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
            "delegate": delegate.pubkey().to_string(),
            "tokenProgram": spl_token_program_id().to_string(),
            "decimals": decimals,
            "initialSupply": initial_supply.to_string(),
            "mintAmount": mint_amount.to_string(),
            "transferAmount": transfer_amount.to_string(),
            "approveAmount": approve_amount.to_string(),
            "burnAmount": burn_amount.to_string(),
            "ownerFinal": owner_account.amount.to_string(),
            "recipientFinal": recipient_account.amount.to_string(),
            "supplyFinal": mint_account.supply.to_string(),
            "signatures": {
                "mint": mint_signature,
                "transfer": transfer_signature,
                "approve": approve_signature,
                "burn": burn_signature,
                "revoke": revoke_signature,
                "setAuthority": set_authority_signature,
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
        plan.standard == "spl-token",
        "live token plan smoke currently executes legacy SPL Token plans only, got {}",
        plan.standard
    );
    ensure!(
        plan.solana.programs.token == SPL_TOKEN_PROGRAM_ID,
        "SPL Token program id mismatch: {}",
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
    for name in [
        "create_mint_account",
        "initialize_mint",
        "create_owner_ata",
        "create_recipient_ata",
        "mint_to_initial_supply",
        "mint_to",
        "transfer_checked",
        "approve_delegate",
        "burn",
        "revoke_delegate",
        "set_mint_authority",
    ] {
        ensure!(
            plan.solana
                .instructions
                .iter()
                .any(|instruction| instruction.name == name),
            "missing Solana token instruction plan: {name}"
        );
    }
    Ok(())
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
