use std::env;
use std::str::FromStr;

use anyhow::{bail, ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const MEMO_PROGRAM_ID: &str = "MemoSq4gqABAXKb96qnH8TysNcWxMyWCqXgDLGmfcHr";

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
    let memo_program = Address::from_str(MEMO_PROGRAM_ID).context("invalid memo program id")?;
    let state = create_program_state(&rpc, &payer, program_id, 8)
        .context("failed to create program state account")?;
    let memo_text = env::var("PROOF_FORGE_SOLANA_MEMO_TEXT").unwrap_or_else(|_| "pfmemo!!".into());
    let memo_payload = memo_payload_from_text(&memo_text)?;
    let memo_word = u64::from_le_bytes(memo_payload);

    let signature = rpc
        .send_and_confirm(
            &[memo_instruction(
                program_id,
                state.pubkey(),
                memo_program,
                memo_payload,
            )],
            &[&payer],
        )
        .context("memo CPI transaction failed")?;

    let recorded_word = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after memo CPI")?;
    ensure!(
        recorded_word == memo_word,
        "state last_memo_word mismatch: expected {memo_word}, got {recorded_word}"
    );

    let logs = rpc.transaction_logs(&signature)?;
    let memo_program_text = memo_program.to_string();
    ensure!(
        logs.iter().any(|line| line.contains(&memo_program_text)),
        "logs missing Memo program id {memo_program_text}: {logs:?}"
    );
    ensure!(
        logs.iter().any(|line| line.contains("Memo")),
        "logs missing Memo marker: {logs:?}"
    );
    ensure!(
        logs.iter().any(|line| line.contains(&memo_text)),
        "logs missing memo text {memo_text}: {logs:?}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "memoProgram": memo_program_text,
            "memoText": memo_text,
            "memoWord": memo_word.to_string(),
            "recordedWord": recorded_word.to_string(),
            "logs": logs,
        })
    );

    Ok(())
}

fn memo_payload_from_text(text: &str) -> Result<[u8; 8]> {
    let input = text.as_bytes();
    if input.len() > 8 {
        bail!("memo text must fit in 8 bytes for this fixture: {text}");
    }
    let mut payload = [0u8; 8];
    payload[..input.len()].copy_from_slice(input);
    Ok(payload)
}

fn memo_instruction(
    program_id: Address,
    state: Address,
    memo_program: Address,
    memo_payload: [u8; 8],
) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(0);
    data.extend_from_slice(&memo_payload);
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new_readonly(memo_program, false),
        ],
        data,
    }
}
