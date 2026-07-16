use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
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

    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let counter = Keypair::new();

    let rent_lamports = rpc.minimum_balance_for_rent_exemption(8)?;
    let create_counter = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &counter.pubkey(),
        rent_lamports,
        8,
        &program_id,
    );
    rpc.send_and_confirm(&[create_counter], &[&payer, &counter])
        .context("failed to create counter account")?;

    send_counter_instruction(&rpc, &payer, program_id, counter.pubkey(), 0)
        .context("initialize transaction failed")?;
    let after_initialize = rpc
        .account_data_u64(counter.pubkey())
        .context("failed to fetch counter after initialize")?;
    ensure!(
        after_initialize == 0,
        "initialize expected counter=0, got {after_initialize}"
    );

    send_counter_instruction(&rpc, &payer, program_id, counter.pubkey(), 1)
        .context("first increment transaction failed")?;
    let after_increment = rpc
        .account_data_u64(counter.pubkey())
        .context("failed to fetch counter after first increment")?;
    ensure!(
        after_increment == 1,
        "increment expected counter=1, got {after_increment}"
    );

    send_counter_instruction(&rpc, &payer, program_id, counter.pubkey(), 1)
        .context("second increment transaction failed")?;
    let after_second_increment = rpc
        .account_data_u64(counter.pubkey())
        .context("failed to fetch counter after second increment")?;
    ensure!(
        after_second_increment == 2,
        "second increment expected counter=2, got {after_second_increment}"
    );

    let get_ix = counter_instruction(program_id, counter.pubkey(), 2);
    let returned = rpc
        .simulate_return_u64(&[get_ix], &[&payer], program_id)
        .context("get simulation failed")?;
    ensure!(returned == 2, "get expected return_data=2, got {returned}");

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "counter": counter.pubkey().to_string(),
            "afterInitialize": after_initialize,
            "afterIncrement": after_increment,
            "afterSecondIncrement": after_second_increment,
            "getReturnData": returned,
        })
    );

    Ok(())
}

fn send_counter_instruction(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    counter: Address,
    tag: u8,
) -> Result<String> {
    rpc.send_and_confirm(&[counter_instruction(program_id, counter, tag)], &[payer])
}

fn counter_instruction(program_id: Address, counter: Address, tag: u8) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(counter, false)],
        data: vec![tag],
    }
}
