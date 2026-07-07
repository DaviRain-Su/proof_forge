use std::env;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{
    create_program_state, read_keypair, read_u64_le_at, LiveRpc,
};
use serde_json::{json, Map, Value};
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_signer::Signer;

const SYSVAR_EPOCH_REWARDS_PUBKEY: &str = "SysvarEpochRewards1111111111111111111111111";
const STATE_SPACE: u64 = 88;

const EPOCH_REWARDS_FIELDS: [EpochRewardsField; 11] = [
    EpochRewardsField::u64("distribution_starting_block_height", 0),
    EpochRewardsField::u64("num_partitions", 8),
    EpochRewardsField::u64("parent_blockhash_word0", 16),
    EpochRewardsField::u64("parent_blockhash_word1", 24),
    EpochRewardsField::u64("parent_blockhash_word2", 32),
    EpochRewardsField::u64("parent_blockhash_word3", 40),
    EpochRewardsField::u64("total_points_low", 48),
    EpochRewardsField::u64("total_points_high", 56),
    EpochRewardsField::u64("total_rewards", 64),
    EpochRewardsField::u64("distributed_rewards", 72),
    EpochRewardsField::bool_as_u64("active", 80),
];

#[derive(Clone, Copy)]
struct EpochRewardsField {
    name: &'static str,
    sysvar_offset: usize,
    read: EpochRewardsRead,
}

impl EpochRewardsField {
    const fn u64(name: &'static str, sysvar_offset: usize) -> Self {
        Self {
            name,
            sysvar_offset,
            read: EpochRewardsRead::U64,
        }
    }

    const fn bool_as_u64(name: &'static str, sysvar_offset: usize) -> Self {
        Self {
            name,
            sysvar_offset,
            read: EpochRewardsRead::BoolAsU64,
        }
    }
}

#[derive(Clone, Copy)]
enum EpochRewardsRead {
    U64,
    BoolAsU64,
}

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
    let epoch_rewards_sysvar = Address::from_str(SYSVAR_EPOCH_REWARDS_PUBKEY)
        .context("invalid EpochRewards sysvar pubkey")?;
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;

    let sysvar_data = rpc
        .account_data(epoch_rewards_sysvar)
        .context("failed to read EpochRewards sysvar account")?;
    let expected = expected_epoch_rewards_words(&sysvar_data)?;

    let signature = rpc
        .send_and_confirm(
            &[epoch_rewards_instruction(program_id, state.pubkey())],
            &[&payer],
        )
        .context("epoch rewards sysvar transaction failed")?;

    let state_data = rpc
        .account_data(state.pubkey())
        .context("failed to read state account after epoch rewards sysvar call")?;
    let mut recorded_json = Map::new();
    let mut expected_json = Map::new();
    for (index, (name, expected_value)) in expected.iter().enumerate() {
        let state_offset = index * 8;
        let recorded_value = read_u64_le_at(&state_data, state_offset)
            .with_context(|| format!("failed to read recorded EpochRewards.{name}"))?;
        ensure!(
            recorded_value == *expected_value,
            "EpochRewards.{name} mismatch: recorded={recorded_value} expected={expected_value}"
        );
        recorded_json.insert(
            (*name).to_string(),
            Value::String(recorded_value.to_string()),
        );
        expected_json.insert(
            (*name).to_string(),
            Value::String(expected_value.to_string()),
        );
    }

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "signature": signature,
            "sysvar": epoch_rewards_sysvar.to_string(),
            "recorded": recorded_json,
            "expected": expected_json,
        })
    );

    Ok(())
}

fn expected_epoch_rewards_words(sysvar_data: &[u8]) -> Result<Vec<(&'static str, u64)>> {
    EPOCH_REWARDS_FIELDS
        .iter()
        .map(|field| read_epoch_rewards_field(sysvar_data, *field).map(|value| (field.name, value)))
        .collect()
}

fn read_epoch_rewards_field(data: &[u8], field: EpochRewardsField) -> Result<u64> {
    match field.read {
        EpochRewardsRead::U64 => read_u64_le_at(data, field.sysvar_offset)
            .with_context(|| format!("failed to read EpochRewards.{}", field.name)),
        EpochRewardsRead::BoolAsU64 => {
            let byte = data
                .get(field.sysvar_offset)
                .with_context(|| format!("expected at least {} bytes", field.sysvar_offset + 1))?;
            Ok(if *byte == 0 { 0 } else { 1 })
        }
    }
}

fn epoch_rewards_instruction(program_id: Address, state: Address) -> Instruction {
    Instruction {
        program_id,
        accounts: vec![AccountMeta::new(state, false)],
        data: vec![0],
    }
}
