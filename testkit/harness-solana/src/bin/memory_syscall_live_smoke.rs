use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{
    create_program_state, read_keypair, read_u64_le_at, LiveRpc,
};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const STATE_SPACE: u64 = 40;
const SOURCE_VALUE: u64 = 0x1122_3344_5566_7788;
const FILLED_PATTERN: [u8; 8] = [0xaa; 8];

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
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;

    let set_source_signature = rpc
        .send_and_confirm(
            &[set_source_instruction(
                program_id,
                state.pubkey(),
                SOURCE_VALUE,
            )],
            &[&payer],
        )
        .context("memory set_source transaction failed")?;
    let memory_signature = rpc
        .send_and_confirm(&[memory_instruction(program_id, state.pubkey())], &[&payer])
        .context("memory syscall transaction failed")?;

    let state_data = rpc
        .account_data(state.pubkey())
        .context("failed to read state account after memory syscall call")?;
    let source = read_u64_le_at(&state_data, 0)?;
    let copied = read_u64_le_at(&state_data, 8)?;
    let filled = state_data
        .get(16..24)
        .context("expected at least 24 bytes for filled memory slice")?;
    let cmp_result = read_u64_le_at(&state_data, 24)?;
    let moved = read_u64_le_at(&state_data, 32)?;

    ensure!(
        source == SOURCE_VALUE,
        "source mismatch: expected {SOURCE_VALUE}, got {source}"
    );
    ensure!(
        copied == SOURCE_VALUE,
        "copied mismatch: expected {SOURCE_VALUE}, got {copied}"
    );
    ensure!(
        moved == SOURCE_VALUE,
        "moved mismatch: expected {SOURCE_VALUE}, got {moved}"
    );
    ensure!(
        cmp_result == 0,
        "memcmp result mismatch: expected 0, got {cmp_result}"
    );
    ensure!(
        filled == FILLED_PATTERN.as_slice(),
        "memset bytes mismatch: expected {}, got {}",
        hex::encode(FILLED_PATTERN),
        hex::encode(filled)
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "setSourceSignature": set_source_signature,
            "memorySignature": memory_signature,
            "source": source.to_string(),
            "copied": copied.to_string(),
            "moved": moved.to_string(),
            "cmpResult": cmp_result.to_string(),
            "filledHex": hex::encode(filled),
        })
    );

    Ok(())
}

fn set_source_instruction(program_id: Address, state: Address, source_value: u64) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(0);
    data.extend_from_slice(&source_value.to_le_bytes());
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data,
    }
}

fn memory_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![1],
    }
}
