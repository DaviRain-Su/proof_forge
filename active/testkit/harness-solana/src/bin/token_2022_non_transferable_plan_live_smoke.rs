use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::token_2022::{
    assert_non_transferable_account, assert_non_transferable_mint, burn,
    create_empty_associated_token_account, create_non_transferable_mint,
    expect_transfer_checked_failure, mint_to, parse_account, parse_mint, token_2022_program_id,
    verify_empty_account, TOKEN_2022_PROGRAM_ID,
};
use serde::Deserialize;
use serde_json::json;
use solana_keypair::Keypair;
use solana_signer::Signer;

const ASSOCIATED_TOKEN_PROGRAM_ID: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
const SYSTEM_PROGRAM_ID: &str = "11111111111111111111111111111111";

#[derive(Debug, Deserialize)]
struct TokenPlan {
    format: String,
    #[serde(rename = "sourceKind")]
    source_kind: Option<String>,
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
    let recipient = Keypair::new();
    let decimals = u8::try_from(plan.token.decimals).context("token decimals must fit in u8")?;
    let initial_supply = plan.token.initial_supply.unwrap_or(0);
    let burn_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_PLAN_BURN_AMOUNT", 1)?;
    ensure!(
        burn_amount > 0,
        "burn amount must be positive: {burn_amount}"
    );
    ensure!(
        initial_supply >= burn_amount,
        "initial supply {initial_supply} is too small for burn {burn_amount}"
    );

    let mint = create_non_transferable_mint(&rpc, &payer, decimals, mint_authority.pubkey())
        .context("failed to create Token-2022 non-transferable mint")?;
    let mint_data = rpc.account_data(mint.pubkey())?;
    assert_non_transferable_mint(&mint_data)?;
    let mint_account = parse_mint(&mint_data)?;
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
    verify_empty_account(
        &rpc.account_data(owner_ata)?,
        mint.pubkey(),
        owner.pubkey(),
        "owner",
    )?;
    verify_empty_account(
        &rpc.account_data(recipient_ata)?,
        mint.pubkey(),
        recipient.pubkey(),
        "recipient",
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
    let mut mint_account = parse_mint(&rpc.account_data(mint.pubkey())?)?;
    assert_non_transferable_account(&rpc.account_data(owner_ata)?, "owner")?;
    assert_non_transferable_account(&rpc.account_data(recipient_ata)?, "recipient")?;
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

    let failed_transfer = expect_transfer_checked_failure(
        &rpc,
        &payer,
        owner_ata,
        mint.pubkey(),
        recipient_ata,
        owner,
        1,
        decimals,
    )
    .context("non-transferable transfer should fail")?;
    owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    recipient_account = parse_account(&rpc.account_data(recipient_ata)?)?;
    ensure!(
        owner_account.amount == initial_supply,
        "owner after rejected transfer mismatch: expected {initial_supply}, got {}",
        owner_account.amount
    );
    ensure!(
        recipient_account.amount == 0,
        "recipient after rejected transfer mismatch: expected 0, got {}",
        recipient_account.amount
    );

    let burn_signature = burn(&rpc, &payer, owner_ata, mint.pubkey(), owner, burn_amount)
        .context("failed to burn Token-2022 amount")?;
    owner_account = parse_account(&rpc.account_data(owner_ata)?)?;
    mint_account = parse_mint(&rpc.account_data(mint.pubkey())?)?;
    let expected_final_supply = initial_supply
        .checked_sub(burn_amount)
        .context("mint supply underflow after burn")?;
    ensure!(
        owner_account.amount == expected_final_supply,
        "owner after burn mismatch: expected {expected_final_supply}, got {}",
        owner_account.amount
    );
    ensure!(
        mint_account.supply == expected_final_supply,
        "supply after burn mismatch: expected {expected_final_supply}, got {}",
        mint_account.supply
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
            "tokenProgram": token_2022_program_id().to_string(),
            "decimals": decimals,
            "initialSupply": initial_supply.to_string(),
            "burnAmount": burn_amount.to_string(),
            "ownerFinal": owner_account.amount.to_string(),
            "recipientFinal": recipient_account.amount.to_string(),
            "supplyFinal": mint_account.supply.to_string(),
            "rejectedTransferErr": failed_transfer.err,
            "signatures": {
                "mintTo": mint_to_signature,
                "rejectedTransfer": failed_transfer.signature,
                "burn": burn_signature,
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
        plan.source_kind.as_deref() == Some("lean-token-source"),
        "live non-transferable smoke expects a Lean token source plan, got {:?}",
        plan.source_kind
    );
    ensure!(
        plan.target_family == "solana",
        "token plan is not a Solana plan: {}",
        plan.target_family
    );
    ensure!(
        plan.standard == "spl-token-2022",
        "live non-transferable smoke expects a Token-2022 plan, got {}",
        plan.standard
    );
    ensure!(
        plan.operations
            .iter()
            .any(|operation| operation == "token-2022.extension.non_transferable"),
        "plan is missing non-transferable operation"
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
            .any(|extension| extension.extension == "non_transferable"),
        "plan missing non_transferable extension"
    );
    for name in [
        "create_mint_account",
        "initialize_non_transferable_mint",
        "initialize_mint",
        "create_owner_ata",
        "create_recipient_ata",
        "mint_to_initial_supply",
        "transfer_checked",
        "burn",
    ] {
        ensure!(
            plan.solana
                .instructions
                .iter()
                .any(|instruction| instruction.name == name),
            "missing planned instruction: {name}"
        );
    }
    let non_transferable_order = instruction_order(plan, "initialize_non_transferable_mint")?;
    let initialize_mint_order = instruction_order(plan, "initialize_mint")?;
    ensure!(
        non_transferable_order < initialize_mint_order,
        "non-transferable mint must initialize before initialize_mint"
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
