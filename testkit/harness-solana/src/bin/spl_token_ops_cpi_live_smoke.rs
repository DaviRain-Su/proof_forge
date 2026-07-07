use std::env;
use std::fs;
use std::path::Path;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    create_empty_associated_token_account, create_mint, mint_to, parse_mint_account,
    parse_token_account, spl_token_program_id,
};
use serde_json::{json, Value};
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;

const STATE_SPACE: u64 = 32;

#[derive(Clone)]
struct AccountSpec {
    name: String,
    signer: bool,
    writable: bool,
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
    let program_id_value = env::var("PROOF_FORGE_SOLANA_PROGRAM_ID")
        .context("missing PROOF_FORGE_SOLANA_PROGRAM_ID")?;
    let artifact_path =
        env::var("PROOF_FORGE_SOLANA_ARTIFACT").context("missing PROOF_FORGE_SOLANA_ARTIFACT")?;
    let decimals = env_u8("PROOF_FORGE_SOLANA_TOKEN_DECIMALS", 9)?;
    let initial_source_amount = env_u64(
        "PROOF_FORGE_SOLANA_TOKEN_INITIAL_SOURCE_AMOUNT",
        1_000_000_000,
    )?;
    let mint_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_MINT_AMOUNT", 125_000_000)?;
    let burn_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_BURN_AMOUNT", 75_000_000)?;
    let approve_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_APPROVE_AMOUNT", 333_000_000)?;
    ensure!(
        initial_source_amount >= burn_amount,
        "initial source amount {initial_source_amount} is smaller than burn amount {burn_amount}"
    );

    let account_specs = validate_instruction_schemas(&artifact_path)?;
    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;
    let recipient = Keypair::new();
    let delegate = Keypair::new();
    let mint = create_mint(&rpc, &payer, decimals, payer.pubkey())
        .context("failed to create SPL Token mint")?;
    let source = create_empty_associated_token_account(&rpc, &payer, payer.pubkey(), mint.pubkey())
        .context("failed to create source associated token account")?;
    let destination =
        create_empty_associated_token_account(&rpc, &payer, recipient.pubkey(), mint.pubkey())
            .context("failed to create destination associated token account")?;
    mint_to(
        &rpc,
        &payer,
        mint.pubkey(),
        source,
        &payer,
        initial_source_amount,
    )
    .context("failed to mint initial source token amount")?;

    let keys = build_keys(
        &account_specs,
        state.pubkey(),
        mint.pubkey(),
        destination,
        payer.pubkey(),
        source,
        delegate.pubkey(),
    )?;

    let source_before = parse_token_account(&rpc.account_data(source)?)?;
    let destination_before = parse_token_account(&rpc.account_data(destination)?)?;
    let mint_before = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;

    let mint_signature = invoke(&rpc, &payer, program_id, &keys, 0, Some(mint_amount))
        .context("SPL Token mint_to CPI transaction failed")?;
    let destination_after_mint = parse_token_account(&rpc.account_data(destination)?)?;
    let mint_after_mint = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    let expected_destination_after_mint = destination_before
        .amount
        .checked_add(mint_amount)
        .context("destination token amount overflow after mint")?;
    let expected_supply_after_mint = mint_before
        .supply
        .checked_add(mint_amount)
        .context("mint supply overflow after mint")?;
    ensure!(
        destination_after_mint.amount == expected_destination_after_mint,
        "destination after mint mismatch: expected {expected_destination_after_mint}, got {}",
        destination_after_mint.amount
    );
    ensure!(
        mint_after_mint.supply == expected_supply_after_mint,
        "mint supply after mint mismatch: expected {expected_supply_after_mint}, got {}",
        mint_after_mint.supply
    );

    let burn_signature = invoke(&rpc, &payer, program_id, &keys, 1, Some(burn_amount))
        .context("SPL Token burn CPI transaction failed")?;
    let source_after_burn = parse_token_account(&rpc.account_data(source)?)?;
    let mint_after_burn = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    let expected_source_after_burn = source_before
        .amount
        .checked_sub(burn_amount)
        .context("source token amount underflow after burn")?;
    let expected_supply_after_burn = mint_after_mint
        .supply
        .checked_sub(burn_amount)
        .context("mint supply underflow after burn")?;
    ensure!(
        source_after_burn.amount == expected_source_after_burn,
        "source after burn mismatch: expected {expected_source_after_burn}, got {}",
        source_after_burn.amount
    );
    ensure!(
        mint_after_burn.supply == expected_supply_after_burn,
        "mint supply after burn mismatch: expected {expected_supply_after_burn}, got {}",
        mint_after_burn.supply
    );

    let approve_signature = invoke(&rpc, &payer, program_id, &keys, 2, Some(approve_amount))
        .context("SPL Token approve CPI transaction failed")?;
    let source_after_approve = parse_token_account(&rpc.account_data(source)?)?;
    ensure!(
        source_after_approve.delegate == Some(delegate.pubkey()),
        "source delegate mismatch after approve: expected {}, got {:?}",
        delegate.pubkey(),
        source_after_approve.delegate
    );
    ensure!(
        source_after_approve.delegated_amount == approve_amount,
        "delegated amount mismatch: expected {approve_amount}, got {}",
        source_after_approve.delegated_amount
    );

    let revoke_signature = invoke(&rpc, &payer, program_id, &keys, 3, None)
        .context("SPL Token revoke CPI transaction failed")?;
    let source_after_revoke = parse_token_account(&rpc.account_data(source)?)?;
    ensure!(
        source_after_revoke.delegate.is_none(),
        "delegate should be cleared after revoke: {:?}",
        source_after_revoke.delegate
    );
    ensure!(
        source_after_revoke.delegated_amount == 0,
        "delegated amount should be zero after revoke: {}",
        source_after_revoke.delegated_amount
    );

    let state_data = rpc
        .account_data(state.pubkey())
        .context("failed to read state account after SPL Token ops")?;
    let recorded_mint = read_u64_le_at(&state_data, 0, "last_mint_amount")?;
    let recorded_burn = read_u64_le_at(&state_data, 8, "last_burn_amount")?;
    let recorded_approve = read_u64_le_at(&state_data, 16, "last_approve_amount")?;
    let recorded_revoke = read_u64_le_at(&state_data, 24, "last_revoke_marker")?;
    ensure!(
        recorded_mint == mint_amount,
        "state last_mint_amount mismatch: expected {mint_amount}, got {recorded_mint}"
    );
    ensure!(
        recorded_burn == burn_amount,
        "state last_burn_amount mismatch: expected {burn_amount}, got {recorded_burn}"
    );
    ensure!(
        recorded_approve == approve_amount,
        "state last_approve_amount mismatch: expected {approve_amount}, got {recorded_approve}"
    );
    ensure!(
        recorded_revoke == 1,
        "state last_revoke_marker mismatch: expected 1, got {recorded_revoke}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "mint": mint.pubkey().to_string(),
            "source": source.to_string(),
            "destination": destination.to_string(),
            "delegate": delegate.pubkey().to_string(),
            "tokenProgram": spl_token_program_id().to_string(),
            "signatures": {
                "mint": mint_signature,
                "burn": burn_signature,
                "approve": approve_signature,
                "revoke": revoke_signature,
            },
            "decimals": decimals,
            "mintAmount": mint_amount.to_string(),
            "burnAmount": burn_amount.to_string(),
            "approveAmount": approve_amount.to_string(),
            "sourceBefore": source_before.amount.to_string(),
            "sourceAfterBurn": source_after_burn.amount.to_string(),
            "destinationBefore": destination_before.amount.to_string(),
            "destinationAfterMint": destination_after_mint.amount.to_string(),
            "supplyBefore": mint_before.supply.to_string(),
            "supplyAfterMint": mint_after_mint.supply.to_string(),
            "supplyAfterBurn": mint_after_burn.supply.to_string(),
            "recordedMint": recorded_mint.to_string(),
            "recordedBurn": recorded_burn.to_string(),
            "recordedApprove": recorded_approve.to_string(),
            "recordedRevoke": recorded_revoke.to_string(),
        })
    );

    Ok(())
}

fn env_u8(name: &str, default: u8) -> Result<u8> {
    env::var(name)
        .ok()
        .map(|value| {
            value
                .parse::<u8>()
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

fn validate_instruction_schemas(path: impl AsRef<Path>) -> Result<Vec<AccountSpec>> {
    let artifact: Value = serde_json::from_str(
        &fs::read_to_string(path.as_ref())
            .with_context(|| format!("failed to read artifact {}", path.as_ref().display()))?,
    )
    .context("failed to parse artifact JSON")?;
    let instructions = artifact
        .get("solanaInstructions")
        .and_then(Value::as_array)
        .context("artifact missing solanaInstructions array")?;
    let expected_names = ["mint", "burn", "approve", "revoke"];
    let names = instructions
        .iter()
        .map(|instruction| {
            instruction
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("")
        })
        .collect::<Vec<_>>();
    ensure!(
        names == expected_names,
        "instruction names mismatch: {:?}",
        names
    );

    let base_accounts = parse_account_specs(&instructions[0])?;
    let expected_accounts = [
        "last_mint_amount",
        "mint",
        "destination",
        "authority",
        "spl_token",
        "source",
        "delegate",
    ];
    ensure!(
        base_accounts
            .iter()
            .map(|account| account.name.as_str())
            .collect::<Vec<_>>()
            == expected_accounts,
        "base account schema mismatch"
    );
    for instruction in instructions {
        let accounts = parse_account_specs(instruction)?;
        ensure!(
            accounts
                .iter()
                .map(|account| account.name.as_str())
                .collect::<Vec<_>>()
                == expected_accounts,
            "instruction {} account schema mismatch",
            instruction
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("<unknown>")
        );
    }

    for instruction in instructions.iter().take(3) {
        ensure!(
            instruction.get("params")
                == Some(&json!([{
                    "name": "amount",
                    "type": "U64",
                    "offset": 1,
                    "byteSize": 8,
                    "encoding": "le-u64"
                }])),
            "instruction {} params mismatch",
            instruction
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or("<unknown>")
        );
    }
    ensure!(
        instructions[3]
            .get("params")
            .and_then(Value::as_array)
            .map(Vec::is_empty)
            .unwrap_or(false),
        "revoke should not declare params"
    );

    Ok(base_accounts)
}

fn parse_account_specs(instruction: &Value) -> Result<Vec<AccountSpec>> {
    instruction
        .get("accounts")
        .and_then(Value::as_array)
        .context("instruction missing accounts array")?
        .iter()
        .map(|account| {
            Ok(AccountSpec {
                name: account
                    .get("name")
                    .and_then(Value::as_str)
                    .context("account missing name")?
                    .to_owned(),
                signer: account
                    .get("signer")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
                writable: account
                    .get("writable")
                    .and_then(Value::as_bool)
                    .unwrap_or(false),
            })
        })
        .collect()
}

fn build_keys(
    accounts: &[AccountSpec],
    state: Address,
    mint: Address,
    destination: Address,
    authority: Address,
    source: Address,
    delegate: Address,
) -> Result<Vec<AccountMeta>> {
    accounts
        .iter()
        .map(|account| {
            let pubkey = match account.name.as_str() {
                "last_mint_amount" => state,
                "mint" => mint,
                "destination" => destination,
                "authority" => authority,
                "spl_token" => spl_token_program_id(),
                "source" => source,
                "delegate" => delegate,
                name => anyhow::bail!("unknown account name in artifact schema: {name}"),
            };
            Ok(if account.writable {
                AccountMeta::new(pubkey, account.signer)
            } else {
                AccountMeta::new_readonly(pubkey, account.signer)
            })
        })
        .collect()
}

fn invoke(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    keys: &[AccountMeta],
    tag: u8,
    amount: Option<u64>,
) -> Result<String> {
    let mut data = Vec::with_capacity(9);
    data.push(tag);
    if let Some(amount) = amount {
        data.extend_from_slice(&amount.to_le_bytes());
    }
    rpc.send_and_confirm(
        &[Instruction {
            program_id,
            accounts: keys.to_vec(),
            data,
        }],
        &[payer],
    )
}

fn read_u64_le_at(data: &[u8], offset: usize, label: &str) -> Result<u64> {
    let end = offset.checked_add(8).context("u64 offset overflow")?;
    let bytes: [u8; 8] = data
        .get(offset..end)
        .with_context(|| format!("{label} requires bytes {offset}..{end}"))?
        .try_into()
        .expect("slice length is fixed");
    Ok(u64::from_le_bytes(bytes))
}
