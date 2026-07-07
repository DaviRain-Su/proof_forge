use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const SYSVAR_LAST_RESTART_SLOT_PUBKEY: &str = "SysvarLastRestartS1ot1111111111111111111111";

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
    let last_restart_slot_sysvar = Address::from_str(SYSVAR_LAST_RESTART_SLOT_PUBKEY)
        .context("invalid LastRestartSlot sysvar pubkey")?;
    let state = create_program_state(&rpc, &payer, program_id, 8)
        .context("failed to create program state account")?;

    let expected_last_restart_slot = rpc
        .account_data_u64(last_restart_slot_sysvar)
        .context("failed to read LastRestartSlot sysvar account")?;

    let signature = rpc
        .send_and_confirm(
            &[last_restart_slot_instruction(program_id, state.pubkey())],
            &[&payer],
        )
        .context("last restart slot sysvar transaction failed")?;

    let recorded_last_restart_slot = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after last restart slot sysvar call")?;
    ensure!(
        recorded_last_restart_slot == expected_last_restart_slot,
        "LastRestartSlot mismatch: recorded={recorded_last_restart_slot} expected={expected_last_restart_slot}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "recordedLastRestartSlot": recorded_last_restart_slot.to_string(),
            "expectedLastRestartSlot": expected_last_restart_slot.to_string(),
        })
    );

    Ok(())
}

fn last_restart_slot_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![0],
    }
}
