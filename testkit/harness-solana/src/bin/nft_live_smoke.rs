use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{read_keypair, LiveRpc};
use serde_json::json;
use sha2::{Digest, Sha256};
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
    let rpc = LiveRpc::new(env::var("PROOF_FORGE_SOLANA_RPC_URL")?);
    let payer = read_keypair(&env::var("PROOF_FORGE_SOLANA_PAYER")?)?;
    let program_id = Address::from_str(&env::var("PROOF_FORGE_SOLANA_PROGRAM_ID")?)?;
    let state = Keypair::new();
    let recipient = Keypair::new();
    let state_bytes = 65_536u64;

    let create_state = solana_system_interface::instruction::create_account(
        &payer.pubkey(),
        &state.pubkey(),
        rpc.minimum_balance_for_rent_exemption(state_bytes)?,
        state_bytes,
        &program_id,
    );
    rpc.send_and_confirm(&[create_state], &[&payer, &state])?;

    send_mutation(&rpc, &payer, program_id, state.pubkey(), vec![5]).context("NFT init failed")?;

    let payer_handle = identity_handle(payer.pubkey());
    let recipient_handle = identity_handle(recipient.pubkey());
    let token_id = 7u64;
    let mut mint = vec![3];
    push_u64(&mut mint, payer_handle);
    push_u64(&mut mint, token_id);
    push_u64(&mut mint, payer_handle);
    send_mutation(&rpc, &payer, program_id, state.pubkey(), mint.clone())
        .context("NFT mint failed")?;

    ensure!(
        send_mutation(&rpc, &payer, program_id, state.pubkey(), mint).is_err(),
        "duplicate mint unexpectedly succeeded"
    );
    let owner_after_mint = query(
        &rpc,
        &payer,
        program_id,
        state.pubkey(),
        query_data(2, token_id),
    )?;
    ensure!(
        owner_after_mint == payer_handle,
        "owner after mint {owner_after_mint} does not match payer identity handle {payer_handle}"
    );
    ensure!(
        query(
            &rpc,
            &payer,
            program_id,
            state.pubkey(),
            query_data(1, payer_handle)
        )? == 1,
        "payer balance after mint is not one"
    );

    let mut transfer = vec![4];
    push_u64(&mut transfer, recipient_handle);
    push_u64(&mut transfer, token_id);
    send_mutation(&rpc, &payer, program_id, state.pubkey(), transfer)
        .context("authorized NFT transfer failed")?;

    ensure!(
        query(
            &rpc,
            &payer,
            program_id,
            state.pubkey(),
            query_data(2, token_id)
        )? == recipient_handle,
        "owner after transfer does not match recipient identity handle"
    );
    ensure!(
        query(
            &rpc,
            &payer,
            program_id,
            state.pubkey(),
            query_data(1, payer_handle)
        )? == 0,
        "payer balance after transfer is not zero"
    );
    ensure!(
        query(
            &rpc,
            &payer,
            program_id,
            state.pubkey(),
            query_data(1, recipient_handle),
        )? == 1,
        "recipient balance after transfer is not one"
    );

    let mut unauthorized = vec![4];
    push_u64(&mut unauthorized, payer_handle);
    push_u64(&mut unauthorized, token_id);
    ensure!(
        send_mutation(&rpc, &payer, program_id, state.pubkey(), unauthorized).is_err(),
        "non-owner transfer unexpectedly succeeded"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "tokenId": token_id,
            "mintOwner": payer_handle,
            "transferOwner": recipient_handle,
            "duplicateMintRejected": true,
            "unauthorizedTransferRejected": true,
        })
    );
    Ok(())
}

fn identity_handle(address: Address) -> u64 {
    let digest = Sha256::digest(address.as_ref());
    u64::from_le_bytes(digest[..8].try_into().expect("sha256 limb"))
}

fn push_u64(data: &mut Vec<u8>, value: u64) {
    data.extend_from_slice(&value.to_le_bytes());
}

fn query_data(tag: u8, value: u64) -> Vec<u8> {
    let mut data = vec![tag];
    push_u64(&mut data, value);
    data
}

fn send_mutation(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    state: Address,
    data: Vec<u8>,
) -> Result<String> {
    rpc.send_and_confirm(
        &[Instruction {
            program_id,
            accounts: vec![
                AccountMeta::new_readonly(payer.pubkey(), true),
                AccountMeta::new(state, false),
            ],
            data,
        }],
        &[payer],
    )
}

fn query(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    state: Address,
    data: Vec<u8>,
) -> Result<u64> {
    rpc.simulate_return_u64(
        &[Instruction {
            program_id,
            accounts: vec![
                AccountMeta::new_readonly(payer.pubkey(), true),
                AccountMeta::new(state, false),
            ],
            data,
        }],
        &[payer],
        program_id,
    )
}
