use std::env;
use std::path::Path;

use anyhow::{bail, Context, Result};
use mollusk_svm::Mollusk;
use serde_json::json;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};

const STEPS: [(&str, &str, u8, &[u64]); 13] = [
    ("initialize", "initialize", 0, &[100]),
    ("get-initial", "get_balance", 5, &[]),
    ("deposit", "deposit", 1, &[25]),
    ("get-deposited", "get_balance", 5, &[]),
    ("charge-fee", "charge_fee", 2, &[100, 250]),
    ("get-charged", "get_balance", 5, &[]),
    ("get-net-charged", "get_net_value", 6, &[]),
    ("release", "release", 3, &[23]),
    ("get-released", "get_balance", 5, &[]),
    ("snapshot", "snapshot", 4, &[]),
    ("get-net-final", "get_net_value", 6, &[]),
    ("release-too-much", "release", 3, &[201]),
    ("get-after-rejected", "get_balance", 5, &[]),
];

fn read_u64(data: &[u8], offset: usize) -> Result<u64> {
    Ok(u64::from_le_bytes(
        data.get(offset..offset + 8)
            .context("ValueVault state account is shorter than 48 bytes")?
            .try_into()
            .expect("slice length is eight bytes"),
    ))
}

fn main() -> Result<()> {
    let program = env::args()
        .nth(1)
        .context("usage: value_vault_differential <value-vault.so> <runner-name>")?;
    let runner_name = env::args()
        .nth(2)
        .context("usage: value_vault_differential <value-vault.so> <runner-name>")?;
    let program_path = Path::new(&program);
    if !program_path.is_file() {
        bail!("ValueVault ELF does not exist: {}", program_path.display());
    }
    let stem = program_path.with_extension("");
    let stem = stem
        .to_str()
        .context("ValueVault ELF path is not valid UTF-8")?;

    let program_id = Address::new_from_array([17; 32]);
    let state_id = Address::new_from_array([19; 32]);
    let mut state = Account::new(1_000_000, 48, &program_id);
    let mut mollusk = Mollusk::new(&program_id, stem);
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;
    mollusk.logger = Some(Default::default());
    let logger = mollusk.logger.as_ref().expect("logger installed").clone();

    let mut observations = Vec::new();
    for (id, call, tag, args) in STEPS {
        let mut instruction_data = vec![tag];
        for value in args {
            instruction_data.extend(value.to_le_bytes());
        }
        let instruction = Instruction::new_with_bytes(
            program_id,
            &instruction_data,
            vec![AccountMeta::new(state_id, false)],
        );
        let log_start = logger.borrow().messages.len();
        let result = mollusk.process_instruction(&instruction, &[(state_id, state.clone())]);
        let success = result.raw_result.is_ok();
        if success {
            state = result
                .get_account(&state_id)
                .with_context(|| {
                    format!("ValueVault call {call} did not return its state account")
                })?
                .clone();
        }
        let raw_logs = logger.borrow().messages[log_start..].to_vec();
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
                "ValueVault call {call} returned {} bytes, expected zero or eight",
                result.return_data.len()
            );
        };
        observations.push(json!({
            "id": id,
            "call": call,
            "success": success,
            "error": if success { None } else { Some(format!("{:?}", result.raw_result)) },
            "returnU64": return_u64,
            "state": {
                "balance": read_u64(&state.data, 0)?,
                "released": read_u64(&state.data, 8)?,
                "fees": read_u64(&state.data, 16)?,
                "lastValue": read_u64(&state.data, 24)?,
                "lastCheckpoint": read_u64(&state.data, 32)?,
                "operations": read_u64(&state.data, 40)?,
            },
            "logs": raw_logs,
            "computeUnits": result.compute_units_consumed,
        }));
    }

    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": "proof-forge.native-value-vault.solana.v1",
            "runner": runner_name,
            "steps": observations,
        }))?
    );
    Ok(())
}
