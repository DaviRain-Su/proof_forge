use std::env;
use std::fs;
use std::path::Path;
use std::str::FromStr;

use anyhow::{ensure, Context, Result};
use proof_forge_testkit_harness_solana::live_rpc::{
    create_program_state, read_keypair, read_u64_le_at, LiveRpc,
};
use serde::Deserialize;
use serde_json::json;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use solana_keypair::Keypair;
use solana_signer::Signer;

const STATE_SPACE: u64 = 64;
const DEFAULT_RESULT_VALUE: u64 = 72_623_859_790_382_856;

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
    let artifact_path =
        env::var("PROOF_FORGE_SOLANA_ARTIFACT").context("missing PROOF_FORGE_SOLANA_ARTIFACT")?;

    let artifact = load_artifact(&artifact_path)?;
    let rpc = LiveRpc::new(rpc_url);
    let payer = read_keypair(&payer_path)?;
    let program_id = Address::from_str(&program_id_value)
        .with_context(|| format!("invalid program id {program_id_value}"))?;
    let state = create_program_state(&rpc, &payer, program_id, STATE_SPACE)
        .context("failed to create program state account")?;
    let result_value = result_value()?;

    let set_signature = invoke(
        &rpc,
        &payer,
        program_id,
        &artifact,
        state.pubkey(),
        "set_result",
        Some(result_value),
    )?;
    let mut state_data = rpc
        .account_data(state.pubkey())
        .context("failed to fetch state after set_result")?;
    assert_state_words(
        &state_data,
        &[
            ("result", 0, result_value),
            ("last_return", 8, 0),
            ("return_len", 16, 0),
            ("return_program0", 24, 0),
            ("return_program1", 32, 0),
            ("return_program2", 40, 0),
            ("return_program3", 48, 0),
            ("remaining", 56, 0),
        ],
    )?;

    let empty_read_signature = invoke(
        &rpc,
        &payer,
        program_id,
        &artifact,
        state.pubkey(),
        "read_return_data",
        None,
    )?;
    state_data = rpc
        .account_data(state.pubkey())
        .context("failed to fetch state after read_return_data")?;
    assert_state_words(
        &state_data,
        &[
            ("result", 0, result_value),
            ("last_return", 8, 0),
            ("return_len", 16, 0),
            ("return_program0", 24, 0),
            ("return_program1", 32, 0),
            ("return_program2", 40, 0),
            ("return_program3", 48, 0),
        ],
    )?;

    let publish_return_data = rpc
        .simulate_return_data(
            &[instruction(
                program_id,
                &artifact,
                state.pubkey(),
                "publish_result",
                None,
            )?],
            &[&payer],
            program_id,
        )
        .context("publish_result simulation failed")?;
    let published_value = read_u64_le_at(&publish_return_data, 0)?;
    ensure!(
        published_value == result_value,
        "publish_result return data mismatch: value={published_value} expected={result_value}"
    );

    let roundtrip_signature = invoke(
        &rpc,
        &payer,
        program_id,
        &artifact,
        state.pubkey(),
        "roundtrip_return_data",
        None,
    )?;
    state_data = rpc
        .account_data(state.pubkey())
        .context("failed to fetch state after roundtrip_return_data")?;
    let program_words = address_words(program_id)?;
    assert_state_words(
        &state_data,
        &[
            ("result", 0, result_value),
            ("last_return", 8, result_value),
            ("return_len", 16, 8),
            ("return_program0", 24, program_words[0]),
            ("return_program1", 32, program_words[1]),
            ("return_program2", 40, program_words[2]),
            ("return_program3", 48, program_words[3]),
        ],
    )?;

    let record_compute_signature = invoke(
        &rpc,
        &payer,
        program_id,
        &artifact,
        state.pubkey(),
        "record_compute",
        None,
    )?;
    state_data = rpc
        .account_data(state.pubkey())
        .context("failed to fetch state after record_compute")?;
    let remaining = read_u64_le_at(&state_data, 56)?;
    ensure!(remaining != 0, "remaining compute units should be nonzero");

    let log_compute_signature = invoke(
        &rpc,
        &payer,
        program_id,
        &artifact,
        state.pubkey(),
        "log_compute",
        None,
    )?;
    let log_lines = rpc
        .transaction_logs(&log_compute_signature)
        .context("failed to fetch log_compute transaction logs")?;
    let has_compute_log = log_lines.iter().any(|line| {
        let normalized = line.to_lowercase();
        normalized.contains("remaining") || normalized.contains("consumed")
    });
    ensure!(
        has_compute_log,
        "compute-unit logs missing remaining/consumed marker: {log_lines:?}"
    );

    println!(
        "{}",
        json!({
            "programId": program_id.to_string(),
            "state": state.pubkey().to_string(),
            "payer": payer.pubkey().to_string(),
            "setSignature": set_signature,
            "emptyReadSignature": empty_read_signature,
            "roundtripSignature": roundtrip_signature,
            "recordComputeSignature": record_compute_signature,
            "logComputeSignature": log_compute_signature,
            "publishedValue": published_value.to_string(),
            "roundtripValue": read_u64_le_at(&state_data, 8)?.to_string(),
            "returnLen": read_u64_le_at(&state_data, 16)?.to_string(),
            "remaining": remaining.to_string(),
        })
    );

    Ok(())
}

fn result_value() -> Result<u64> {
    env::var("PROOF_FORGE_SOLANA_RETURN_DATA_VALUE")
        .ok()
        .map(|value| {
            value
                .parse::<u64>()
                .with_context(|| format!("invalid PROOF_FORGE_SOLANA_RETURN_DATA_VALUE: {value}"))
        })
        .transpose()
        .map(|value| value.unwrap_or(DEFAULT_RESULT_VALUE))
}

fn invoke(
    rpc: &LiveRpc,
    payer: &Keypair,
    program_id: Address,
    artifact: &Artifact,
    state: Address,
    name: &str,
    value: Option<u64>,
) -> Result<String> {
    rpc.send_and_confirm(
        &[instruction(program_id, artifact, state, name, value)?],
        &[payer],
    )
    .with_context(|| format!("{name} transaction failed"))
}

fn instruction(
    program_id: Address,
    artifact: &Artifact,
    state: Address,
    name: &str,
    value: Option<u64>,
) -> Result<Instruction> {
    let schema = artifact.instruction(name)?;
    let mut data = Vec::with_capacity(if value.is_some() { 9 } else { 1 });
    data.push(schema.tag);
    if let Some(value) = value {
        data.extend_from_slice(&value.to_le_bytes());
    }
    Ok(Instruction {
        program_id,
        accounts: build_accounts(schema, state)?,
        data,
    })
}

fn build_accounts(schema: &InstructionSchema, state: Address) -> Result<Vec<AccountMeta>> {
    let account_names = schema
        .accounts
        .iter()
        .map(|account| account.name.as_str())
        .collect::<Vec<_>>();
    ensure!(
        account_names == ["result"],
        "unexpected account schema for {}: {account_names:?}",
        schema.name
    );
    Ok(schema
        .accounts
        .iter()
        .map(|account| {
            if account.writable {
                AccountMeta::new(state, account.signer)
            } else {
                AccountMeta::new_readonly(state, account.signer)
            }
        })
        .collect())
}

fn assert_state_words(data: &[u8], expected: &[(&str, usize, u64)]) -> Result<()> {
    for (name, offset, expected_value) in expected {
        let actual = read_u64_le_at(data, *offset)
            .with_context(|| format!("failed to read state word {name}"))?;
        ensure!(
            actual == *expected_value,
            "{name} mismatch: expected {expected_value}, got {actual}"
        );
    }
    Ok(())
}

fn address_words(address: Address) -> Result<[u64; 4]> {
    let bytes = address.as_ref();
    Ok([
        read_u64_le_at(bytes, 0)?,
        read_u64_le_at(bytes, 8)?,
        read_u64_le_at(bytes, 16)?,
        read_u64_le_at(bytes, 24)?,
    ])
}

fn load_artifact(path: impl AsRef<Path>) -> Result<Artifact> {
    let path = path.as_ref();
    let contents = fs::read_to_string(path)
        .with_context(|| format!("failed to read artifact metadata: {}", path.display()))?;
    serde_json::from_str(&contents)
        .with_context(|| format!("failed to parse artifact metadata: {}", path.display()))
}

#[derive(Debug, Deserialize)]
struct Artifact {
    #[serde(rename = "solanaInstructions")]
    solana_instructions: Vec<InstructionSchema>,
}

impl Artifact {
    fn instruction(&self, name: &str) -> Result<&InstructionSchema> {
        self.solana_instructions
            .iter()
            .find(|instruction| instruction.name == name)
            .with_context(|| format!("instruction {name} not found in artifact"))
    }
}

#[derive(Debug, Deserialize)]
struct InstructionSchema {
    name: String,
    tag: u8,
    #[serde(default)]
    accounts: Vec<AccountSchema>,
}

#[derive(Debug, Deserialize)]
struct AccountSchema {
    name: String,
    #[serde(default)]
    signer: bool,
    #[serde(default)]
    writable: bool,
}
