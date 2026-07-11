use std::env;
use std::str::FromStr;

use anyhow::{Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
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
    let payer_address = payer.pubkey();
    let following = solana_system_interface::program::id();

    let instruction = Instruction {
        program_id,
        accounts: vec![
            AccountMeta::new_readonly(payer_address, true),
            AccountMeta::new_readonly(payer_address, true),
            AccountMeta::new_readonly(following, false),
        ],
        data: vec![0],
    };

    let signature = rpc
        .send_and_confirm(&[instruction], &[&payer])
        .context("duplicate-account probe transaction failed")?;

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "firstRole": payer_address.to_string(),
            "aliasRole": payer_address.to_string(),
            "followingRole": following.to_string(),
            "signature": signature,
        })
    );
    Ok(())
}
