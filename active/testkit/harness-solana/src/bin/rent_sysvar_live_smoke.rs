use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const SYSVAR_RENT_PUBKEY: &str = "SysvarRent111111111111111111111111111111111";

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
    let rent_sysvar =
        Address::from_str(SYSVAR_RENT_PUBKEY).context("invalid Rent sysvar pubkey")?;
    let state = create_program_state(&rpc, &payer, program_id, 8)
        .context("failed to create program state account")?;

    let expected_lamports_per_byte_year = rpc
        .account_data_u64(rent_sysvar)
        .context("failed to read Rent sysvar account")?;
    ensure!(
        expected_lamports_per_byte_year != 0,
        "Rent.lamports_per_byte_year from sysvar account was zero"
    );

    let signature = rpc
        .send_and_confirm(&[rent_instruction(program_id, state.pubkey())], &[&payer])
        .context("rent sysvar transaction failed")?;

    let recorded_lamports_per_byte_year = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after rent sysvar call")?;
    ensure!(
        recorded_lamports_per_byte_year == expected_lamports_per_byte_year,
        "Rent.lamports_per_byte_year mismatch: recorded={recorded_lamports_per_byte_year} expected={expected_lamports_per_byte_year}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "recordedLamportsPerByteYear": recorded_lamports_per_byte_year.to_string(),
            "expectedLamportsPerByteYear": expected_lamports_per_byte_year.to_string(),
        })
    );

    Ok(())
}

fn rent_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![0],
    }
}
