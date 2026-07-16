use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

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

    let signature = rpc
        .send_and_confirm(&[clock_instruction(program_id, state.pubkey())], &[&payer])
        .context("clock sysvar transaction failed")?;
    let transaction_slot = rpc
        .transaction_slot(&signature)
        .context("failed to fetch transaction slot")?;

    let recorded_slot = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after clock sysvar call")?;
    ensure!(recorded_slot != 0, "recorded Clock.slot was zero");

    let delta = recorded_slot.abs_diff(transaction_slot);
    ensure!(
        delta <= 2,
        "Clock.slot {recorded_slot} is too far from transaction slot {transaction_slot}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "recordedSlot": recorded_slot.to_string(),
            "transactionSlot": transaction_slot.to_string(),
            "slotDelta": delta.to_string(),
        })
    );

    Ok(())
}

fn clock_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![0],
    }
}
