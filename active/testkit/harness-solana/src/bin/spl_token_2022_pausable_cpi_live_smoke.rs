use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use proof_forge_testkit_harness_solana::spl_token::create_system_wallet;
use proof_forge_testkit_harness_solana::token_2022::{
    assert_pausable_config, create_pausable_mint_account, initialize_mint, parse_mint,
    token_2022_program_id,
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
    let pausable_mint = create_pausable_mint_account(&rpc, &payer)
        .context("failed to create pausable mint account")?;
    let pausable_authority =
        create_system_wallet(&rpc, &payer).context("failed to create pausable authority")?;

    let initialize_pausable_config_signature = rpc
        .send_and_confirm(
            &[generated_instruction(
                program_id,
                state.pubkey(),
                pausable_mint.pubkey(),
                pausable_authority.pubkey(),
                0,
            )],
            &[&payer, &pausable_authority],
        )
        .context("generated initialize_pausable_config CPI failed")?;
    let initialize_pausable_mint_signature = initialize_mint(
        &rpc,
        &payer,
        pausable_mint.pubkey(),
        decimals,
        payer.pubkey(),
    )
    .context("failed to initialize pausable Token-2022 mint")?;
    let mut mint_data = rpc.account_data(pausable_mint.pubkey())?;
    let mint_account = parse_mint(&mint_data)?;
    ensure!(
        mint_account.is_initialized,
        "pausable mint should be initialized"
    );
    ensure!(
        mint_account.decimals == decimals,
        "pausable mint decimals mismatch: expected {decimals}, got {}",
        mint_account.decimals
    );
    assert_pausable_config(&mint_data, pausable_authority.pubkey(), false)?;
    let mut recorded_marker = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state after initialize_pausable_config")?;
    ensure!(
        recorded_marker == 1,
        "state marker after initialize_pausable_config mismatch: expected 1, got {recorded_marker}"
    );

    let pause_signature = rpc
        .send_and_confirm(
            &[generated_instruction(
                program_id,
                state.pubkey(),
                pausable_mint.pubkey(),
                pausable_authority.pubkey(),
                1,
            )],
            &[&payer, &pausable_authority],
        )
        .context("generated pause CPI failed")?;
    mint_data = rpc.account_data(pausable_mint.pubkey())?;
    assert_pausable_config(&mint_data, pausable_authority.pubkey(), true)?;
    recorded_marker = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state after pause")?;
    ensure!(
        recorded_marker == 2,
        "state marker after pause mismatch: expected 2, got {recorded_marker}"
    );

    let resume_signature = rpc
        .send_and_confirm(
            &[generated_instruction(
                program_id,
                state.pubkey(),
                pausable_mint.pubkey(),
                pausable_authority.pubkey(),
                2,
            )],
            &[&payer, &pausable_authority],
        )
        .context("generated resume CPI failed")?;
    mint_data = rpc.account_data(pausable_mint.pubkey())?;
    assert_pausable_config(&mint_data, pausable_authority.pubkey(), false)?;
    recorded_marker = rpc
        .account_data_u64(state.pubkey())
        .context("failed to read state after resume")?;
    ensure!(
        recorded_marker == 3,
        "state marker after resume mismatch: expected 3, got {recorded_marker}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "pausableMint": pausable_mint.pubkey().to_string(),
            "pausableAuthority": pausable_authority.pubkey().to_string(),
            "tokenProgram": token_2022_program_id().to_string(),
            "decimals": decimals,
            "recordedMarker": recorded_marker.to_string(),
            "signatures": {
                "initializePausableConfig": initialize_pausable_config_signature,
                "initializePausableMint": initialize_pausable_mint_signature,
                "pause": pause_signature,
                "resume": resume_signature,
            },
        })
    );

    Ok(())
}

fn generated_instruction(
    program_id: Address,
    state: Address,
    pausable_mint: Address,
    pausable_authority: Address,
    tag: u8,
) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new(state, false),
            AccountMeta::new(pausable_mint, false),
            AccountMeta::new_readonly(token_2022_program_id(), false),
            AccountMeta::new_readonly(pausable_authority, true),
        ],
        data: vec![tag],
    }
}
