use std::env;
use std::path::Path;

use anyhow::{bail, Context, Result};
use mollusk_svm::Mollusk;
use serde_json::json;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};

const STEPS: [(&str, &str, u8); 4] = [
    ("initialize", "initialize", 0),
    ("get-zero", "get", 2),
    ("increment", "increment", 1),
    ("get-one", "get", 2),
];

fn main() -> Result<()> {
    let program = env::args()
        .nth(1)
        .context("usage: native_counter <native-counter.so>")?;
    let program_path = Path::new(&program);
    if !program_path.is_file() {
        bail!("native Counter ELF does not exist: {}", program_path.display());
    }
    let stem = program_path.with_extension("");
    let stem = stem
        .to_str()
        .context("native Counter ELF path is not valid UTF-8")?;

    let program_id = Address::new_from_array([7; 32]);
    let state_id = Address::new_from_array([9; 32]);
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
        if let Err(error) = &result.raw_result {
            bail!("native Solana Counter {call} failed: {error:?}");
        }
        state = result
            .get_account(&state_id)
            .context("native Solana Counter did not return its state account")?
            .clone();
        let count = u64::from_le_bytes(
            state.data[..8]
                .try_into()
                .context("native Solana Counter state is shorter than eight bytes")?,
        );
        let return_u64 = if call == "get" {
            if result.return_data.len() != 8 {
                bail!(
                    "native Solana Counter get returned {} bytes, expected 8",
                    result.return_data.len()
                );
            }
            Some(u64::from_le_bytes(
                result.return_data[..8]
                    .try_into()
                    .expect("return-data length checked"),
            ))
        } else {
            None
        };
        observations.push(json!({
            "id": id,
            "call": call,
            "returnU64": return_u64,
            "state": {"count": count},
            "computeUnits": result.compute_units_consumed,
        }));
    }

    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": "proof-forge.native-counter.solana.v1",
            "runner": "pinocchio-mollusk",
            "steps": observations,
        }))?
    );
    Ok(())
}
