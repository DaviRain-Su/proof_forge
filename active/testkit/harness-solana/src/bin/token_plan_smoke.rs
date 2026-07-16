use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use serde::Deserialize;
use serde_json::json;
use solana_address::Address;

const SPL_TOKEN_PROGRAM_ID: &str = "TokenkegQfeZyiNwAJbNbGKPFXCWuBvf9Ss623VQ5DA";
const TOKEN_2022_PROGRAM_ID: &str = "TokenzQdBNbLqP5VEhdkAS6EPFLC1PHnBqCXEpPxuEb";
const ASSOCIATED_TOKEN_PROGRAM_ID: &str = "ATokenGPvbdGVxr1b2hvZbsiqW5xWH25efTNsLJA8knL";
const SYSTEM_PROGRAM_ID: &str = "11111111111111111111111111111111";
const RENT_SYSVAR_ID: &str = "SysvarRent111111111111111111111111111111111";

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
    #[serde(default)]
    validation: HashMap<String, String>,
}

#[derive(Debug, Deserialize)]
struct TokenInfo {
    decimals: u64,
    #[serde(rename = "initialSupply")]
    initial_supply: Option<u64>,
}

#[derive(Debug, Deserialize)]
struct SolanaPlan {
    standard: String,
    programs: SolanaPrograms,
    #[serde(default)]
    instructions: Vec<PlanInstruction>,
    #[serde(default)]
    extensions: Vec<TokenExtension>,
}

#[derive(Debug, Deserialize)]
struct SolanaPrograms {
    token: String,
    #[serde(rename = "associatedToken")]
    associated_token: String,
    system: String,
    #[serde(rename = "rentSysvar")]
    rent_sysvar: String,
}

#[derive(Debug, Deserialize)]
struct PlanInstruction {
    order: i64,
    name: String,
    operation: String,
    #[serde(rename = "programId")]
    program_id: String,
    #[serde(default)]
    accounts: Vec<String>,
    #[serde(default)]
    params: Vec<PlanParam>,
    #[serde(rename = "token2022Only", default)]
    token_2022_only: bool,
}

#[derive(Debug, Deserialize)]
struct PlanParam {
    name: String,
    #[serde(rename = "type")]
    param_type: String,
    source: String,
}

#[derive(Debug, Deserialize)]
struct TokenExtension {
    extension: String,
    #[serde(rename = "initInstruction")]
    init_instruction: String,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let plan_path = plan_path()?;
    let plan = load_plan(&plan_path)?;
    validate_plan_shape(&plan)?;
    validate_instruction_plan(&plan)?;

    println!(
        "{}",
        json!({
            "plan": plan_path,
            "standard": plan.standard,
            "tokenProgram": plan.solana.programs.token,
            "instructions": plan.solana.instructions.iter().map(|instruction| instruction.name.as_str()).collect::<Vec<_>>(),
            "extensions": plan.solana.extensions.iter().map(|extension| extension.extension.as_str()).collect::<Vec<_>>(),
        })
    );

    Ok(())
}

fn plan_path() -> Result<PathBuf> {
    env::args_os()
        .nth(1)
        .map(PathBuf::from)
        .context("usage: token_plan_smoke <token-plan.json>")
}

fn load_plan(path: &PathBuf) -> Result<TokenPlan> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("failed to read token plan: {}", path.display()))?;
    serde_json::from_str(&contents)
        .with_context(|| format!("failed to parse token plan: {}", path.display()))
}

fn validate_plan_shape(plan: &TokenPlan) -> Result<()> {
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
        plan.solana.standard == plan.standard,
        "Solana plan standard mismatch: top-level={} solana={}",
        plan.standard,
        plan.solana.standard
    );

    let token_program = expected_token_program(plan)?;
    ensure!(
        plan.solana.programs.token == token_program,
        "token program id mismatch: expected {token_program}, got {}",
        plan.solana.programs.token
    );
    ensure!(
        plan.solana.programs.associated_token == ASSOCIATED_TOKEN_PROGRAM_ID,
        "associated token program id mismatch"
    );
    ensure!(
        plan.solana.programs.system == SYSTEM_PROGRAM_ID,
        "system program id mismatch"
    );
    ensure!(
        plan.solana.programs.rent_sysvar == RENT_SYSVAR_ID,
        "rent sysvar id mismatch"
    );
    ensure!(
        plan.validation.get("planGeneration").map(String::as_str) == Some("passed"),
        "planGeneration validation is not passed"
    );
    ensure!(
        plan.token.decimals <= u8::MAX as u64,
        "token decimals must fit in u8"
    );
    let _initial_supply = plan.token.initial_supply.unwrap_or(0);

    let orders = plan
        .solana
        .instructions
        .iter()
        .map(|instruction| instruction.order)
        .collect::<Vec<_>>();
    ensure!(
        orders.windows(2).all(|window| window[0] <= window[1]),
        "instruction order is not sorted: {:?}",
        orders
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
        "revoke_delegate",
        "set_mint_authority",
    ] {
        instruction_by_name(plan, name)?;
    }
    let burn_enabled = has_operation(plan, "spl-token.burn");
    ensure!(
        instruction_by_name(plan, "burn").is_ok() == burn_enabled,
        "burn instruction presence must match the TokenSpec burnable operation"
    );

    if plan.standard == "spl-token-2022" {
        ensure!(
            !plan.solana.extensions.is_empty(),
            "Token-2022 plan missing extension metadata"
        );
        for extension in &plan.solana.extensions {
            instruction_by_name(plan, &extension.init_instruction)
                .with_context(|| format!("missing init instruction for {}", extension.extension))?;
        }
        if has_extension(plan, "transfer_fee_config") {
            for name in [
                "transfer_checked_with_fee",
                "withdraw_withheld_tokens_from_accounts",
                "harvest_withheld_tokens_to_mint",
                "withdraw_withheld_tokens_from_mint",
            ] {
                instruction_by_name(plan, name)?;
            }
        }
    }

    Ok(())
}

fn validate_instruction_plan(plan: &TokenPlan) -> Result<()> {
    let token_program = expected_token_program(plan)?;
    let token_program_address = parse_address(token_program)?;
    let associated_token_program = parse_address(ASSOCIATED_TOKEN_PROGRAM_ID)?;
    let mint = deterministic_address_from_byte(2);
    let owner = deterministic_address_from_byte(4);
    let recipient = deterministic_address_from_byte(5);
    let owner_ata = associated_token_address(
        &owner,
        &token_program_address,
        &mint,
        &associated_token_program,
    );
    let recipient_ata = associated_token_address(
        &recipient,
        &token_program_address,
        &mint,
        &associated_token_program,
    );
    ensure!(
        owner_ata != recipient_ata,
        "owner and recipient ATA collided"
    );

    assert_program(plan, "create_mint_account", SYSTEM_PROGRAM_ID)?;
    assert_accounts(
        plan,
        "create_mint_account",
        &["payer", "mint", "system_program"],
    )?;
    assert_params(
        plan,
        "create_mint_account",
        &[
            ("space", "usize", "mint_size(extensions)"),
            ("lamports", "u64", "rent_exemption"),
        ],
    )?;

    assert_token_instruction(plan, "initialize_mint")?;
    assert_accounts(
        plan,
        "initialize_mint",
        &["mint", "rent_sysvar", "token_program"],
    )?;
    assert_params(
        plan,
        "initialize_mint",
        &[
            ("decimals", "u8", "token.decimals"),
            ("mintAuthority", "pubkey", "mint_authority"),
        ],
    )?;

    for name in ["create_owner_ata", "create_recipient_ata"] {
        assert_program(plan, name, ASSOCIATED_TOKEN_PROGRAM_ID)?;
        assert_operation(plan, name, "associated-token.create")?;
    }
    assert_accounts(
        plan,
        "create_owner_ata",
        &[
            "payer",
            "owner_ata",
            "owner",
            "mint",
            "system_program",
            "token_program",
            "associated_token_program",
        ],
    )?;
    assert_accounts(
        plan,
        "create_recipient_ata",
        &[
            "payer",
            "recipient_ata",
            "recipient",
            "mint",
            "system_program",
            "token_program",
            "associated_token_program",
        ],
    )?;

    assert_token_amount_instruction(
        plan,
        "mint_to_initial_supply",
        "spl-token.mint_to",
        &["mint", "owner_ata", "mint_authority", "token_program"],
        "token.initialSupply",
    )?;
    assert_token_amount_instruction(
        plan,
        "mint_to",
        "spl-token.mint_to",
        &["mint", "owner_ata", "mint_authority", "token_program"],
        "instruction.amount",
    )?;
    assert_token_amount_instruction(
        plan,
        "approve_delegate",
        "spl-token.approve",
        &["owner_ata", "delegate", "owner", "token_program"],
        "instruction.amount",
    )?;
    if has_operation(plan, "spl-token.burn") {
        assert_token_amount_instruction(
            plan,
            "burn",
            "spl-token.burn",
            &["owner_ata", "mint", "owner", "token_program"],
            "instruction.amount",
        )?;
    }

    assert_token_instruction(plan, "transfer_checked")?;
    assert_operation(plan, "transfer_checked", "spl-token.transfer_checked")?;
    assert_accounts(
        plan,
        "transfer_checked",
        &[
            "owner_ata",
            "mint",
            "recipient_ata",
            "owner",
            "token_program",
        ],
    )?;
    assert_params(
        plan,
        "transfer_checked",
        &[
            ("amount", "u64", "instruction.amount"),
            ("decimals", "u8", "token.decimals"),
        ],
    )?;

    assert_token_instruction(plan, "revoke_delegate")?;
    assert_operation(plan, "revoke_delegate", "spl-token.revoke")?;
    assert_accounts(
        plan,
        "revoke_delegate",
        &["owner_ata", "owner", "token_program"],
    )?;
    assert_params(plan, "revoke_delegate", &[])?;

    assert_token_instruction(plan, "set_mint_authority")?;
    assert_operation(plan, "set_mint_authority", "spl-token.set_authority")?;
    assert_accounts(
        plan,
        "set_mint_authority",
        &["mint", "mint_authority", "token_program"],
    )?;
    assert_params(
        plan,
        "set_mint_authority",
        &[
            ("authorityType", "enum", "mint_tokens"),
            ("newAuthority", "pubkey|null", "token.authorityPolicy"),
        ],
    )?;

    if plan.standard == "spl-token-2022" {
        for instruction in &plan.solana.instructions {
            if instruction.token_2022_only {
                ensure!(
                    instruction.program_id == TOKEN_2022_PROGRAM_ID,
                    "{} token-2022 instruction must use Token-2022 program",
                    instruction.name
                );
            }
        }
        if has_extension(plan, "non_transferable") {
            assert_token_instruction(plan, "initialize_non_transferable_mint")?;
        }
        if has_extension(plan, "transfer_fee_config") {
            validate_transfer_fee_plan(plan)?;
        }
    }

    Ok(())
}

fn validate_transfer_fee_plan(plan: &TokenPlan) -> Result<()> {
    assert_token_instruction(plan, "initialize_transfer_fee_config")?;
    assert_operation(
        plan,
        "initialize_transfer_fee_config",
        "token-2022.extension.transfer_fee",
    )?;
    assert_accounts(
        plan,
        "initialize_transfer_fee_config",
        &["mint", "mint_authority", "token_program"],
    )?;

    assert_token_instruction(plan, "transfer_checked_with_fee")?;
    assert_operation(
        plan,
        "transfer_checked_with_fee",
        "token-2022.transfer_checked_with_fee",
    )?;
    assert_accounts(
        plan,
        "transfer_checked_with_fee",
        &[
            "owner_ata",
            "mint",
            "recipient_ata",
            "owner",
            "token_program",
        ],
    )?;
    assert_params(
        plan,
        "transfer_checked_with_fee",
        &[
            ("amount", "u64", "instruction.amount"),
            ("decimals", "u8", "token.decimals"),
            ("fee", "u64", "calculated_transfer_fee"),
        ],
    )?;

    assert_token_instruction(plan, "withdraw_withheld_tokens_from_accounts")?;
    assert_operation(
        plan,
        "withdraw_withheld_tokens_from_accounts",
        "token-2022.withdraw_withheld_tokens_from_accounts",
    )?;
    assert_accounts(
        plan,
        "withdraw_withheld_tokens_from_accounts",
        &[
            "mint",
            "fee_receiver_ata",
            "withdraw_withheld_authority",
            "recipient_ata",
            "token_program",
        ],
    )?;

    assert_token_instruction(plan, "harvest_withheld_tokens_to_mint")?;
    assert_operation(
        plan,
        "harvest_withheld_tokens_to_mint",
        "token-2022.harvest_withheld_tokens_to_mint",
    )?;
    assert_accounts(
        plan,
        "harvest_withheld_tokens_to_mint",
        &["mint", "recipient_ata", "token_program"],
    )?;

    assert_token_instruction(plan, "withdraw_withheld_tokens_from_mint")?;
    assert_operation(
        plan,
        "withdraw_withheld_tokens_from_mint",
        "token-2022.withdraw_withheld_tokens_from_mint",
    )?;
    assert_accounts(
        plan,
        "withdraw_withheld_tokens_from_mint",
        &[
            "mint",
            "fee_receiver_ata",
            "withdraw_withheld_authority",
            "token_program",
        ],
    )
}

fn expected_token_program(plan: &TokenPlan) -> Result<&'static str> {
    match plan.standard.as_str() {
        "spl-token" => Ok(SPL_TOKEN_PROGRAM_ID),
        "spl-token-2022" => Ok(TOKEN_2022_PROGRAM_ID),
        other => anyhow::bail!("unsupported Solana token standard: {other}"),
    }
}

fn instruction_by_name<'a>(plan: &'a TokenPlan, name: &str) -> Result<&'a PlanInstruction> {
    plan.solana
        .instructions
        .iter()
        .find(|instruction| instruction.name == name)
        .with_context(|| format!("missing Solana token instruction plan: {name}"))
}

fn has_extension(plan: &TokenPlan, name: &str) -> bool {
    plan.solana
        .extensions
        .iter()
        .any(|extension| extension.extension == name)
}

fn has_operation(plan: &TokenPlan, name: &str) -> bool {
    plan.operations.iter().any(|operation| operation == name)
}

fn assert_token_instruction(plan: &TokenPlan, name: &str) -> Result<()> {
    assert_program(plan, name, expected_token_program(plan)?)
}

fn assert_program(plan: &TokenPlan, name: &str, expected: &str) -> Result<()> {
    let instruction = instruction_by_name(plan, name)?;
    ensure!(
        instruction.program_id == expected,
        "{name} program mismatch: expected {expected}, got {}",
        instruction.program_id
    );
    Ok(())
}

fn assert_operation(plan: &TokenPlan, name: &str, expected: &str) -> Result<()> {
    let instruction = instruction_by_name(plan, name)?;
    ensure!(
        instruction.operation == expected,
        "{name} operation mismatch: expected {expected}, got {}",
        instruction.operation
    );
    Ok(())
}

fn assert_accounts(plan: &TokenPlan, name: &str, expected: &[&str]) -> Result<()> {
    let instruction = instruction_by_name(plan, name)?;
    let expected = expected
        .iter()
        .map(|account| account.to_string())
        .collect::<Vec<_>>();
    ensure!(
        instruction.accounts == expected,
        "{name} accounts mismatch: expected {:?}, got {:?}",
        expected,
        instruction.accounts
    );
    Ok(())
}

fn assert_params(plan: &TokenPlan, name: &str, expected: &[(&str, &str, &str)]) -> Result<()> {
    let instruction = instruction_by_name(plan, name)?;
    let actual = instruction
        .params
        .iter()
        .map(|param| {
            (
                param.name.as_str(),
                param.param_type.as_str(),
                param.source.as_str(),
            )
        })
        .collect::<Vec<_>>();
    ensure!(
        actual == expected,
        "{name} params mismatch: expected {:?}, got {:?}",
        expected,
        actual
    );
    Ok(())
}

fn assert_token_amount_instruction(
    plan: &TokenPlan,
    name: &str,
    operation: &str,
    accounts: &[&str],
    amount_source: &str,
) -> Result<()> {
    assert_token_instruction(plan, name)?;
    assert_operation(plan, name, operation)?;
    assert_accounts(plan, name, accounts)?;
    assert_params(plan, name, &[("amount", "u64", amount_source)])
}

fn associated_token_address(
    owner: &Address,
    token_program: &Address,
    mint: &Address,
    associated_token_program: &Address,
) -> Address {
    let seeds = [owner.as_ref(), token_program.as_ref(), mint.as_ref()];
    let (address, _) = Address::find_program_address(&seeds, associated_token_program);
    address
}

fn parse_address(value: &str) -> Result<Address> {
    Address::from_str(value).with_context(|| format!("invalid Solana address: {value}"))
}

fn deterministic_address_from_byte(byte: u8) -> Address {
    Address::new_from_array([byte; 32])
}
