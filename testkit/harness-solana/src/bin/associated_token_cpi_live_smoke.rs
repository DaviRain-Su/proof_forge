use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    associated_token_address, associated_token_program_id, create_mint, create_system_wallet,
    parse_token_account, spl_token_program_id,
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
    let wallet = create_system_wallet(&rpc, &payer).context("failed to create wallet")?;
    let mint = create_mint(&rpc, &payer, decimals, payer.pubkey())
        .context("failed to create SPL Token mint")?;
    let associated_account = associated_token_address(
        &wallet.pubkey(),
        &spl_token_program_id(),
        &mint.pubkey(),
        &associated_token_program_id(),
    );

    ensure!(
        rpc.account_info_optional(associated_account)?.is_none(),
        "associated token account already exists: {associated_account}"
    );

    let signature = rpc
        .send_and_confirm(
            &[create_associated_instruction(
                program_id,
                state.pubkey(),
                payer.pubkey(),
                associated_account,
                wallet.pubkey(),
                mint.pubkey(),
            )],
            &[&payer],
        )
        .context("Associated Token create_idempotent CPI transaction failed")?;
    let second_signature = rpc
        .send_and_confirm(
            &[create_associated_instruction(
                program_id,
                state.pubkey(),
                payer.pubkey(),
                associated_account,
                wallet.pubkey(),
                mint.pubkey(),
            )],
            &[&payer],
        )
        .context("Associated Token create_idempotent CPI retry failed")?;

    let account_info = rpc
        .account_info(associated_account)
        .context("associated token account missing after create")?;
    ensure!(
        account_info.owner == spl_token_program_id(),
        "associated token account owner program mismatch: expected {}, got {}",
        spl_token_program_id(),
        account_info.owner
    );
    let token_account = parse_token_account(&account_info.data)?;
    ensure!(
        token_account.owner == wallet.pubkey(),
        "associated token account owner mismatch: expected {}, got {}",
        wallet.pubkey(),
        token_account.owner
    );
    ensure!(
        token_account.mint == mint.pubkey(),
        "associated token account mint mismatch: expected {}, got {}",
        mint.pubkey(),
        token_account.mint
    );
    ensure!(
        token_account.amount == 0,
        "associated token account amount mismatch: expected 0, got {}",
        token_account.amount
    );

    let recorded_marker = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after associated token create")?;
    ensure!(
        recorded_marker == 1,
        "state last_created_marker mismatch: expected 1, got {recorded_marker}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "wallet": wallet.pubkey().to_string(),
            "mint": mint.pubkey().to_string(),
            "associatedAccount": associated_account.to_string(),
            "tokenProgram": spl_token_program_id().to_string(),
            "associatedTokenProgram": associated_token_program_id().to_string(),
            "signature": signature,
            "secondSignature": second_signature,
            "decimals": decimals,
            "recordedMarker": recorded_marker.to_string(),
            "associatedAccountOwner": token_account.owner.to_string(),
            "associatedAccountMint": token_account.mint.to_string(),
            "associatedAccountAmount": token_account.amount.to_string(),
        })
    );

    Ok(())
}

fn create_associated_instruction(
    program_id: Address,
    state: Address,
    payer: Address,
    associated_account: Address,
    wallet: Address,
    mint: Address,
) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(payer, true),
            AccountMeta::new(associated_account, false),
            AccountMeta::new_readonly(wallet, false),
            AccountMeta::new_readonly(mint, false),
            AccountMeta::new_readonly(solana_system_interface::program::id(), false),
            AccountMeta::new_readonly(spl_token_program_id(), false),
            AccountMeta::new_readonly(associated_token_program_id(), false),
        ],
        data: vec![0],
    }
}
