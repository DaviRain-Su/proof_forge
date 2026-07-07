use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    create_empty_associated_token_account, create_mint, create_system_wallet, spl_token_program_id,
};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
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
    let decimals = env::var("PROOF_FORGE_SOLANA_TOKEN_DECIMALS")
        .ok()
        .map(|value| {
            value
                .parse::<u8>()
                .with_context(|| format!("invalid PROOF_FORGE_SOLANA_TOKEN_DECIMALS={value}"))
        })
        .transpose()?
        .unwrap_or(9);

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;
    let destination = create_system_wallet(&rpc, &payer).context("failed to create destination")?;
    let mint = create_mint(&rpc, &payer, decimals, payer.pubkey())
        .context("failed to create SPL Token mint")?;
    let token_account =
        create_empty_associated_token_account(&rpc, &payer, payer.pubkey(), mint.pubkey())
            .context("failed to create empty associated token account")?;

    let close_account_before = rpc
        .account_info(token_account)
        .context("token account missing before close")?;
    let destination_before = rpc
        .balance(destination.pubkey())
        .context("failed to read destination balance before close")?;

    let signature = rpc
        .send_and_confirm(
            &[close_account_instruction(
                program_id,
                state.pubkey(),
                token_account,
                destination.pubkey(),
                payer.pubkey(),
            )],
            &[&payer],
        )
        .context("SPL Token close_account CPI transaction failed")?;

    ensure!(
        rpc.account_info_optional(token_account)?.is_none(),
        "token account still exists after close: {token_account}"
    );

    let destination_after = rpc
        .balance(destination.pubkey())
        .context("failed to read destination balance after close")?;
    let expected_destination_after = destination_before
        .checked_add(close_account_before.lamports)
        .context("destination lamports overflow")?;
    ensure!(
        destination_after == expected_destination_after,
        "destination lamports mismatch: expected {expected_destination_after}, got {destination_after}"
    );

    let recorded_marker = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after close")?;
    ensure!(
        recorded_marker == 1,
        "state last_close_marker mismatch: expected 1, got {recorded_marker}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "mint": mint.pubkey().to_string(),
            "tokenAccount": token_account.to_string(),
            "destination": destination.pubkey().to_string(),
            "tokenProgram": spl_token_program_id().to_string(),
            "signature": signature,
            "decimals": decimals,
            "closedLamports": close_account_before.lamports.to_string(),
            "destinationBefore": destination_before.to_string(),
            "destinationAfter": destination_after.to_string(),
            "recordedMarker": recorded_marker.to_string(),
        })
    );

    Ok(())
}

fn close_account_instruction(
    program_id: Address,
    state: Address,
    token_account: Address,
    destination: Address,
    authority: Address,
) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(token_account, false),
            AccountMeta::new(destination, false),
            AccountMeta::new_readonly(authority, true),
            AccountMeta::new_readonly(spl_token_program_id(), false),
        ],
        data: vec![0],
    }
}
