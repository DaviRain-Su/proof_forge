use std::env;
use std::path::Path;

use anyhow::{bail, Context, Result};
use mollusk_svm::Mollusk;
use serde_json::json;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};

const STEPS: [(&str, &str, u8); 9] = [
    ("initial-paused", "paused", 0),
    ("unpause-while-unpaused", "unpause", 2),
    ("state-after-failed-unpause", "paused", 0),
    ("pause", "pause", 1),
    ("paused-after-pause", "paused", 0),
    ("pause-while-paused", "pause", 1),
    ("state-after-failed-pause", "paused", 0),
    ("unpause", "unpause", 2),
    ("final-paused", "paused", 0),
];

fn read_paused(data: &[u8]) -> Result<u64> {
    Ok(u64::from_le_bytes(
        data.get(..8)
            .context("Pausable state account is shorter than eight bytes")?
            .try_into()
            .expect("slice length is eight bytes"),
    ))
}

fn main() -> Result<()> {
    let program = env::args()
        .nth(1)
        .context("usage: pausable_differential <pausable.so> <runner-name>")?;
    let runner_name = env::args()
        .nth(2)
        .context("usage: pausable_differential <pausable.so> <runner-name>")?;
    let program_path = Path::new(&program);
    if !program_path.is_file() {
        bail!("Pausable ELF does not exist: {}", program_path.display());
    }
    let stem = program_path.with_extension("");
    let stem = stem
        .to_str()
        .context("Pausable ELF path is not valid UTF-8")?;

    let program_id = Address::new_from_array([31; 32]);
    let state_id = Address::new_from_array([37; 32]);
    let mut state = Account::new(1_000_000, 8, &program_id);
    let mut mollusk = Mollusk::new(&program_id, stem);
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;

    let mut observations = Vec::new();
    for (id, call, tag) in STEPS {
        let instruction = Instruction::new_with_bytes(
            program_id,
            &[tag],
            vec![AccountMeta::new(state_id, false)],
        );
        let result = mollusk.process_instruction(&instruction, &[(state_id, state.clone())]);
        let success = result.raw_result.is_ok();
        if success {
            state = result
                .get_account(&state_id)
                .with_context(|| format!("Pausable call {call} did not return its state account"))?
                .clone();
        }
        let return_u64 = if result.return_data.is_empty() {
            None
        } else if result.return_data.len() == 8 {
            Some(u64::from_le_bytes(
                result.return_data[..8]
                    .try_into()
                    .expect("return-data length checked"),
            ))
        } else {
            bail!(
                "Pausable call {call} returned {} bytes, expected zero or eight",
                result.return_data.len()
            );
        };
        observations.push(json!({
            "id": id,
            "call": call,
            "success": success,
            "error": if success { None } else { Some(format!("{:?}", result.raw_result)) },
            "returnU64": return_u64,
            "state": {"paused": read_paused(&state.data)?},
            "computeUnits": result.compute_units_consumed,
        }));
    }

    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": "proof-forge.native-pausable.solana.v1",
            "runner": runner_name,
            "steps": observations,
        }))?
    );
    Ok(())
}
