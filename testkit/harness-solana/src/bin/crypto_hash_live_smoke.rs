use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{create_program_state, read_keypair, LiveRpc};
use serde_json::json;
use sha2::{Digest, Sha256};
use sha3::Keccak256;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const STATE_SPACE: u64 = 104;
const PREIMAGE_VALUE: u64 = 0x1122_3344_5566_7788;

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
    let preimage_bytes = PREIMAGE_VALUE.to_le_bytes();

    let set_preimage_signature = rpc
        .send_and_confirm(
            &[set_preimage_instruction(
                program_id,
                state.pubkey(),
                preimage_bytes,
            )],
            &[&payer],
        )
        .context("set_preimage transaction failed")?;
    let hash_signature = send_tagged(&rpc, &payer, program_id, state.pubkey(), 1, "hash_preimage")?;
    let keccak_signature = send_tagged(
        &rpc,
        &payer,
        program_id,
        state.pubkey(),
        2,
        "keccak_preimage",
    )?;
    let blake3_signature = send_tagged(
        &rpc,
        &payer,
        program_id,
        state.pubkey(),
        3,
        "blake3_preimage",
    )?;

    let account_data = rpc
        .account_data(state.pubkey())
        .context("failed to fetch state account")?;
    require_bytes_equal(
        account_data
            .get(0..8)
            .context("state missing preimage bytes")?,
        &preimage_bytes,
        "preimage state",
    )?;

    let actual_digest = account_data
        .get(8..40)
        .context("state missing SHA-256 digest")?;
    let expected_digest = Sha256::digest(preimage_bytes);
    require_bytes_equal(actual_digest, expected_digest.as_ref(), "sha256 digest")?;

    let actual_keccak = account_data
        .get(40..72)
        .context("state missing Keccak-256 digest")?;
    let expected_keccak = Keccak256::digest(preimage_bytes);
    require_bytes_equal(actual_keccak, expected_keccak.as_ref(), "keccak256 digest")?;

    let actual_blake3 = account_data
        .get(72..104)
        .context("state missing Blake3 digest")?;
    let expected_blake3 = blake3::hash(&preimage_bytes);
    require_bytes_equal(actual_blake3, expected_blake3.as_bytes(), "blake3 digest")?;

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "setPreimageSignature": set_preimage_signature,
            "hashSignature": hash_signature,
            "keccakSignature": keccak_signature,
            "blake3Signature": blake3_signature,
            "preimageHex": hex::encode(preimage_bytes),
            "digestHex": hex::encode(actual_digest),
            "keccakDigestHex": hex::encode(actual_keccak),
            "blake3DigestHex": hex::encode(actual_blake3),
        })
    );

    Ok(())
}

fn send_tagged(
    rpc: &LiveRpc,
    payer: &solana_keypair::Keypair,
    program_id: Address,
    state: Address,
    tag: u8,
    name: &str,
) -> Result<String> {
    rpc.send_and_confirm(&[tagged_instruction(program_id, state, tag)], &[payer])
        .with_context(|| format!("{name} transaction failed"))
}

fn require_bytes_equal(actual: &[u8], expected: &[u8], label: &str) -> Result<()> {
    ensure!(
        actual == expected,
        "{label} mismatch: expected {}, got {}",
        hex::encode(expected),
        hex::encode(actual)
    );
    Ok(())
}

fn set_preimage_instruction(program_id: Address, state: Address, preimage: [u8; 8]) -> Instruction {
    let mut data = Vec::with_capacity(9);
    data.push(0);
    data.extend_from_slice(&preimage);
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data,
    }
}

fn tagged_instruction(program_id: Address, state: Address, tag: u8) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![tag],
    }
}
