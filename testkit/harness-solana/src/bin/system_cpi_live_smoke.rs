use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
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
    let lamports = env::var("PROOF_FORGE_SOLANA_TRANSFER_LAMPORTS")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid PROOF_FORGE_SOLANA_TRANSFER_LAMPORTS={value}"))
        })
        .transpose()?
        .unwrap_or(5000);

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, 8)
        .context("failed to create program state account")?;
    let recipient =
        create_system_recipient(&rpc, &payer).context("failed to create system recipient")?;

    let recipient_before = rpc
        .balance(recipient.pubkey())
        .context("failed to read recipient balance before transfer")?;
    let payer_before = rpc
        .balance(payer.pubkey())
        .context("failed to read payer balance before transfer")?;
    let signature = rpc
        .send_and_confirm(
            &[transfer_instruction(
                program_id,
                state.pubkey(),
                payer.pubkey(),
                recipient.pubkey(),
                lamports,
            )],
            &[&payer],
        )
        .context("system CPI transfer transaction failed")?;

    let recipient_after = rpc
        .balance(recipient.pubkey())
        .context("failed to read recipient balance after transfer")?;
    let payer_after = rpc
        .balance(payer.pubkey())
        .context("failed to read payer balance after transfer")?;
    let delta = recipient_after
        .checked_sub(recipient_before)
        .context("recipient balance decreased")?;
    ensure!(
        delta == lamports,
        "recipient lamports delta mismatch: expected {lamports}, got {delta}"
    );
    ensure!(
        payer_after < payer_before,
        "payer balance did not decrease: before={payer_before} after={payer_after}"
    );

    let recorded = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after transfer")?;
    ensure!(
        recorded == lamports,
        "state last_transfer_lamports mismatch: expected {lamports}, got {recorded}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "recipient": recipient.pubkey().to_string(),
            "signature": signature,
            "lamports": lamports,
            "recipientBefore": recipient_before,
            "recipientAfter": recipient_after,
            "recorded": recorded,
        })
    );

    Ok(())
}

fn create_system_recipient(rpc: &LiveRpc, payer: &Keypair) -> Result<Keypair> {
    let recipient = Keypair::new();
    let lamports = rpc.minimum_balance_for_rent_exemption(0)?;
    let ix = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &recipient.pubkey(),
        lamports,
        0,
        &solana_system_interface::program::id(),
    );
    rpc.send_and_confirm(&[ix], &[payer, &recipient])?;
    Ok(recipient)
}

fn transfer_instruction(
    program_id: Address,
    state: Address,
    payer: Address,
    recipient: Address,
    lamports: u64,
) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(0);
    data.extend_from_slice(&lamports.to_le_bytes());
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(payer, true),
            AccountMeta::new(recipient, false),
            AccountMeta::new_readonly(solana_system_interface::program::id(), false),
        ],
        data,
    }
}
