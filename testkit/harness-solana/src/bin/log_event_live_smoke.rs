use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use base64::{engine::general_purpose::STANDARD as BASE64, Engine as _};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const DEFAULT_AMOUNT: u64 = 42_424_242;

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

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, 8)
        .context("failed to create program state account")?;
    let amount = amount()?;
    let event_tag = stable_event_tag("AmountEvent");

    let signature = rpc
        .send_and_confirm(
            &[emit_instruction(program_id, state.pubkey(), amount)],
            &[&payer],
        )
        .context("emit transaction failed")?;
    let recorded_amount = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state after emit")?;
    ensure!(
        recorded_amount == amount,
        "state last_logged_amount mismatch: expected {amount}, got {recorded_amount}"
    );

    let logs = rpc
        .transaction_logs(&signature)
        .context("failed to fetch emit transaction logs")?;
    ensure!(
        logs.iter().any(|line| line.contains("Program log:")),
        "expected at least one program log: {logs:?}"
    );
    ensure!(
        log_contains_number(&logs, event_tag),
        "logs missing AmountEvent tag {event_tag}: {logs:?}"
    );
    ensure!(
        log_contains_number(&logs, amount),
        "logs missing amount {amount}: {logs:?}"
    );

    let pubkey_signature = rpc
        .send_and_confirm(
            &[log_pubkey_instruction(program_id, state.pubkey())],
            &[&payer],
        )
        .context("log_state_pubkey transaction failed")?;
    let pubkey_logs = rpc
        .transaction_logs(&pubkey_signature)
        .context("failed to fetch log_state_pubkey transaction logs")?;
    let expected_pubkey = state.pubkey().to_string();
    ensure!(
        pubkey_logs
            .iter()
            .any(|line| line.contains(&expected_pubkey)),
        "logs missing state pubkey {expected_pubkey}: {pubkey_logs:?}"
    );

    let data_signature = rpc
        .send_and_confirm(
            &[log_data_instruction(program_id, state.pubkey())],
            &[&payer],
        )
        .context("log_state_data transaction failed")?;
    let data_logs = rpc
        .transaction_logs(&data_signature)
        .context("failed to fetch log_state_data transaction logs")?;
    let expected_data = amount_data_base64(amount);
    ensure!(
        data_logs
            .iter()
            .any(|line| line.contains("Program data:") && line.contains(&expected_data)),
        "logs missing Program data payload {expected_data}: {data_logs:?}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "pubkeySignature": pubkey_signature,
            "dataSignature": data_signature,
            "event": "AmountEvent",
            "eventTag": event_tag.to_string(),
            "amount": amount.to_string(),
            "dataPayloadBase64": expected_data,
            "recordedAmount": recorded_amount.to_string(),
            "logs": logs,
            "pubkeyLogs": pubkey_logs,
            "dataLogs": data_logs,
        })
    );

    Ok(())
}

fn amount() -> Result<u64> {
    env::var("PROOF_FORGE_SOLANA_LOG_AMOUNT")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid PROOF_FORGE_SOLANA_LOG_AMOUNT: {value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(DEFAULT_AMOUNT))
}

fn stable_event_tag(name: &str) -> u64 {
    let mut acc = 5381u64;
    for byte in name.bytes() {
        acc = acc.wrapping_mul(33).wrapping_add(u64::from(byte)) & 0xffff_ffff;
    }
    acc
}

fn amount_data_base64(amount: u64) -> String {
    BASE64.encode(amount.to_le_bytes())
}

fn log_contains_number(logs: &[String], value: u64) -> bool {
    let decimal = value.to_string();
    let hex = format!("0x{:x}", value);
    logs.iter()
        .any(|line| line.contains(&decimal) || line.to_ascii_lowercase().contains(hex.as_str()))
}

fn emit_instruction(program_id: Address, state: Address, amount: u64) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(0);
    data.extend_from_slice(&amount.to_le_bytes());
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data,
    }
}

fn log_pubkey_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![1],
    }
}

fn log_data_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![2],
    }
}
