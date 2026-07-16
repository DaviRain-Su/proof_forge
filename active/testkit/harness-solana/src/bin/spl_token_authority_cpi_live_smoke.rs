use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::{
    create_mint, parse_mint_account, spl_token_program_id,
};
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
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
    let new_authority = Keypair::new();
    let mint = create_mint(&rpc, &payer, decimals, payer.pubkey())
        .context("failed to create SPL Token mint")?;

    let mint_before = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    ensure!(
        mint_before.mint_authority == Some(payer.pubkey()),
        "initial mint authority mismatch: expected {}, got {:?}",
        payer.pubkey(),
        mint_before.mint_authority
    );
    ensure!(
        mint_before.is_initialized,
        "mint account must be initialized before set_authority"
    );

    let signature = rpc
        .send_and_confirm(
            &[set_authority_instruction(
                program_id,
                state.pubkey(),
                mint.pubkey(),
                payer.pubkey(),
                new_authority.pubkey(),
            )],
            &[&payer],
        )
        .context("SPL Token set_authority CPI transaction failed")?;

    let mint_after = parse_mint_account(&rpc.account_data(mint.pubkey())?)?;
    ensure!(
        mint_after.mint_authority == Some(new_authority.pubkey()),
        "mint authority mismatch after set_authority: expected {}, got {:?}",
        new_authority.pubkey(),
        mint_after.mint_authority
    );
    ensure!(
        mint_after.decimals == decimals,
        "mint decimals changed after set_authority: expected {decimals}, got {}",
        mint_after.decimals
    );
    ensure!(
        mint_after.supply == mint_before.supply,
        "mint supply changed after set_authority: expected {}, got {}",
        mint_before.supply,
        mint_after.supply
    );

    let recorded_marker = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state account after set_authority")?;
    ensure!(
        recorded_marker == 1,
        "state last_authority_marker mismatch: expected 1, got {recorded_marker}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "mint": mint.pubkey().to_string(),
            "tokenProgram": spl_token_program_id().to_string(),
            "oldAuthority": payer.pubkey().to_string(),
            "newAuthority": new_authority.pubkey().to_string(),
            "signature": signature,
            "decimals": decimals,
            "recordedMarker": recorded_marker.to_string(),
            "mintAuthorityBefore": mint_before.mint_authority.map(|address| address.to_string()),
            "mintAuthorityAfter": mint_after.mint_authority.map(|address| address.to_string()),
        })
    );

    Ok(())
}

fn set_authority_instruction(
    program_id: Address,
    state: Address,
    mint: Address,
    authority: Address,
    new_authority: Address,
) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(mint, false),
            AccountMeta::new_readonly(authority, true),
            AccountMeta::new_readonly(spl_token_program_id(), false),
            AccountMeta::new_readonly(new_authority, false),
        ],
        data: vec![0],
    }
}
