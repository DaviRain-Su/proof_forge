use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    create_empty_associated_token_account, create_mint, mint_to, parse_token_account,
    spl_token_program_id,
};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;

const STATE_SPACE: u64 = 8;

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
    let decimals = env_u8("PROOF_FORGE_SOLANA_TOKEN_DECIMALS", 9)?;
    let transfer_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_TRANSFER_AMOUNT", 250_000_000)?;
    let initial_amount = env_u64("PROOF_FORGE_SOLANA_TOKEN_INITIAL_AMOUNT", 1_000_000_000)?;
    ensure!(
        transfer_amount > 0,
        "transfer amount must be positive: {transfer_amount}"
    );
    ensure!(
        initial_amount >= transfer_amount,
        "initial amount {initial_amount} is smaller than transfer amount {transfer_amount}"
    );

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;
    let recipient = Keypair::new();
    let mint = create_mint(&rpc, &payer, decimals, payer.pubkey())
        .context("failed to create SPL Token mint")?;
    let source = create_empty_associated_token_account(&rpc, &payer, payer.pubkey(), mint.pubkey())
        .context("failed to create source associated token account")?;
    let destination =
        create_empty_associated_token_account(&rpc, &payer, recipient.pubkey(), mint.pubkey())
            .context("failed to create destination associated token account")?;
    mint_to(&rpc, &payer, mint.pubkey(), source, &payer, initial_amount)
        .context("failed to mint initial source token amount")?;

    let source_before = parse_token_account(&rpc.account_data(source)?)?;
    let destination_before = parse_token_account(&rpc.account_data(destination)?)?;
    ensure!(
        source_before.amount >= transfer_amount,
        "source amount {} is smaller than transfer amount {transfer_amount}",
        source_before.amount
    );

    let signature = rpc
        .send_and_confirm(
            &[transfer_checked_instruction(
                program_id,
                state.pubkey(),
                source,
                mint.pubkey(),
                destination,
                payer.pubkey(),
                transfer_amount,
            )],
            &[&payer],
        )
        .context("SPL Token transfer_checked CPI transaction failed")?;

    let source_after = parse_token_account(&rpc.account_data(source)?)?;
    let destination_after = parse_token_account(&rpc.account_data(destination)?)?;
    let expected_source_after = source_before
        .amount
        .checked_sub(transfer_amount)
        .context("source token amount underflow")?;
    let expected_destination_after = destination_before
        .amount
        .checked_add(transfer_amount)
        .context("destination token amount overflow")?;
    ensure!(
        source_after.amount == expected_source_after,
        "source amount mismatch: expected {expected_source_after}, got {}",
        source_after.amount
    );
    ensure!(
        destination_after.amount == expected_destination_after,
        "destination amount mismatch: expected {expected_destination_after}, got {}",
        destination_after.amount
    );

    let recorded_amount = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after transfer_checked")?;
    ensure!(
        recorded_amount == transfer_amount,
        "state last_transfer_amount mismatch: expected {transfer_amount}, got {recorded_amount}"
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
            "tokenProgram": spl_token_program_id().to_string(),
            "signature": signature,
            "decimals": decimals,
            "transferAmount": transfer_amount.to_string(),
            "sourceBefore": source_before.amount.to_string(),
            "sourceAfter": source_after.amount.to_string(),
            "destinationBefore": destination_before.amount.to_string(),
            "destinationAfter": destination_after.amount.to_string(),
            "recordedAmount": recorded_amount.to_string(),
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

fn transfer_checked_instruction(
    program_id: Address,
    state: Address,
    source: Address,
    mint: Address,
    destination: Address,
    authority: Address,
    amount: u64,
) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(0);
    data.extend_from_slice(&amount.to_le_bytes());
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(source, false),
            AccountMeta::new_readonly(mint, false),
            AccountMeta::new(destination, false),
            AccountMeta::new_readonly(authority, true),
            AccountMeta::new_readonly(spl_token_program_id(), false),
        ],
        data,
    }
}
