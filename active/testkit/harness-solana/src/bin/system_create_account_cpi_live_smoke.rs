use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{
    create_program_state, read_keypair, read_u64_le_at, LiveRpc,
};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;

const STATE_SPACE: u64 = 16;
const DEFAULT_CREATE_SPACE: u64 = 24;

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
    let new_account = Keypair::new();
    let space = create_space()?;
    let lamports = create_lamports(&rpc, space)?;

    ensure!(
        rpc.account_info_optional(new_account.pubkey())?.is_none(),
        "new account unexpectedly exists: {}",
        new_account.pubkey()
    );
    let payer_before = rpc
        .balance(payer.pubkey())
        .context("failed to read payer balance before create_account CPI")?;

    let signature = rpc
        .send_and_confirm(
            &[create_account_instruction(
                program_id,
                state.pubkey(),
                payer.pubkey(),
                new_account.pubkey(),
                lamports,
                space,
            )],
            &[&payer, &new_account],
        )
        .context("system create_account CPI transaction failed")?;

    let created = rpc
        .account_info(new_account.pubkey())
        .context("failed to read created account")?;
    ensure!(
        created.owner == program_id,
        "created account owner mismatch: expected {program_id}, got {}",
        created.owner
    );
    ensure!(
        created.data.len() == space as usize,
        "created account data length mismatch: expected {space}, got {}",
        created.data.len()
    );
    ensure!(
        created.lamports == lamports,
        "created account lamports mismatch: expected {lamports}, got {}",
        created.lamports
    );

    let payer_after = rpc
        .balance(payer.pubkey())
        .context("failed to read payer balance after create_account CPI")?;
    ensure!(
        payer_after < payer_before,
        "payer balance did not decrease: before={payer_before} after={payer_after}"
    );

    let state_data = rpc
        .account_data(state.pubkey())
        .context("failed to read state account after create_account CPI")?;
    let recorded_lamports =
        read_u64_le_at(&state_data, 0).context("failed to read recorded last_created_lamports")?;
    let recorded_space =
        read_u64_le_at(&state_data, 8).context("failed to read recorded last_created_space")?;
    ensure!(
        recorded_lamports == lamports,
        "state last_created_lamports mismatch: expected {lamports}, got {recorded_lamports}"
    );
    ensure!(
        recorded_space == space,
        "state last_created_space mismatch: expected {space}, got {recorded_space}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "created": new_account.pubkey().to_string(),
            "signature": signature,
            "lamports": lamports,
            "space": space,
            "recordedLamports": recorded_lamports,
            "recordedSpace": recorded_space,
        })
    );

    Ok(())
}

fn create_space() -> Result<u64> {
    env::var("PROOF_FORGE_SOLANA_CREATE_SPACE")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid PROOF_FORGE_SOLANA_CREATE_SPACE: {value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(DEFAULT_CREATE_SPACE))
}

fn create_lamports(rpc: &LiveRpc, space: u64) -> Result<u64> {
    env::var("PROOF_FORGE_SOLANA_CREATE_LAMPORTS")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid PROOF_FORGE_SOLANA_CREATE_LAMPORTS: {value}"))
        })
        .transpose()?
        .map(Ok)
        .unwrap_or_else(|| rpc.minimum_balance_for_rent_exemption(space))
}

fn create_account_instruction(
    program_id: Address,
    state: Address,
    payer: Address,
    new_account: Address,
    lamports: u64,
    space: u64,
) -> Instruction {
    let mut data = Vec::with_capacity(17);
    data.push(0);
    data.extend_from_slice(&lamports.to_le_bytes());
    data.extend_from_slice(&space.to_le_bytes());
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(payer, true),
            AccountMeta::new(new_account, true),
            AccountMeta::new_readonly(solana_system_interface::program::id(), false),
        ],
        data,
    }
}
