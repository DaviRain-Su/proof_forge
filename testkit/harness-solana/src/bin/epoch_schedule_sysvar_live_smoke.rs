use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{
    create_program_state, read_keypair, read_u64_le_at, LiveRpc,
};
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
    let state = create_program_state(&rpc, &payer, program_id, 40)
        .context("failed to create program state account")?;
    let expected = rpc
        .epoch_schedule()
        .context("failed to fetch epoch schedule")?;
    ensure!(
        expected.slots_per_epoch != 0,
        "RPC EpochSchedule.slotsPerEpoch was zero"
    );
    ensure!(
        expected.leader_schedule_slot_offset != 0,
        "RPC EpochSchedule.leaderScheduleSlotOffset was zero"
    );

    let signature = rpc
        .send_and_confirm(
            &[epoch_schedule_instruction(program_id, state.pubkey())],
            &[&payer],
        )
        .context("epoch schedule sysvar transaction failed")?;

    let state_data = rpc
        .account_data(state.pubkey())
        .context("failed to read state account after epoch schedule sysvar call")?;
    let recorded_slots_per_epoch = read_u64_le_at(&state_data, 0)?;
    ensure!(
        recorded_slots_per_epoch == expected.slots_per_epoch,
        "EpochSchedule.slots_per_epoch mismatch: recorded={recorded_slots_per_epoch} expected={}",
        expected.slots_per_epoch
    );
    let recorded_leader_schedule_slot_offset = read_u64_le_at(&state_data, 8)?;
    ensure!(
        recorded_leader_schedule_slot_offset == expected.leader_schedule_slot_offset,
        "EpochSchedule.leader_schedule_slot_offset mismatch: recorded={recorded_leader_schedule_slot_offset} expected={}",
        expected.leader_schedule_slot_offset
    );
    let expected_warmup = if expected.warmup { 1 } else { 0 };
    let recorded_warmup = read_u64_le_at(&state_data, 16)?;
    ensure!(
        recorded_warmup == expected_warmup,
        "EpochSchedule.warmup mismatch: recorded={recorded_warmup} expected={expected_warmup}"
    );
    let recorded_first_normal_epoch = read_u64_le_at(&state_data, 24)?;
    ensure!(
        recorded_first_normal_epoch == expected.first_normal_epoch,
        "EpochSchedule.first_normal_epoch mismatch: recorded={recorded_first_normal_epoch} expected={}",
        expected.first_normal_epoch
    );
    let recorded_first_normal_slot = read_u64_le_at(&state_data, 32)?;
    ensure!(
        recorded_first_normal_slot == expected.first_normal_slot,
        "EpochSchedule.first_normal_slot mismatch: recorded={recorded_first_normal_slot} expected={}",
        expected.first_normal_slot
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "recordedSlotsPerEpoch": recorded_slots_per_epoch.to_string(),
            "expectedSlotsPerEpoch": expected.slots_per_epoch.to_string(),
            "recordedLeaderScheduleSlotOffset": recorded_leader_schedule_slot_offset.to_string(),
            "expectedLeaderScheduleSlotOffset": expected.leader_schedule_slot_offset.to_string(),
            "recordedWarmup": recorded_warmup.to_string(),
            "expectedWarmup": expected_warmup.to_string(),
            "recordedFirstNormalEpoch": recorded_first_normal_epoch.to_string(),
            "expectedFirstNormalEpoch": expected.first_normal_epoch.to_string(),
            "recordedFirstNormalSlot": recorded_first_normal_slot.to_string(),
            "expectedFirstNormalSlot": expected.first_normal_slot.to_string(),
        })
    );

    Ok(())
}

fn epoch_schedule_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![0],
    }
}
