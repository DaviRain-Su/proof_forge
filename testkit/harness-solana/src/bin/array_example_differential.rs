use std::env;
use std::path::Path;

use anyhow::{bail, Context, Result};
use mollusk_svm::Mollusk;
use serde_json::json;
use solana_address::Address;
use solana_instruction::Instruction;

const STEPS: [(&str, &str, u8); 4] = [
    ("size-of-3", "sizeOf3", 0),
    ("get-element", "getElem", 1),
    ("sum-of-3", "sumOf3", 2),
    ("out-of-bounds", "outOfBounds", 3),
];

fn main() -> Result<()> {
    let program = env::args()
        .nth(1)
        .context("usage: array_example_differential <array-example.so> <runner-name>")?;
    let runner_name = env::args()
        .nth(2)
        .context("usage: array_example_differential <array-example.so> <runner-name>")?;
    let program_path = Path::new(&program);
    if !program_path.is_file() {
        bail!(
            "ArrayExample ELF does not exist: {}",
            program_path.display()
        );
    }
    let stem = program_path.with_extension("");
    let stem = stem
        .to_str()
        .context("ArrayExample ELF path is not valid UTF-8")?;

    let program_id = Address::new_from_array([43; 32]);
    let mut mollusk = Mollusk::new(&program_id, stem);
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;

    let mut observations = Vec::new();
    for (id, call, tag) in STEPS {
        let instruction = Instruction::new_with_bytes(program_id, &[tag], vec![]);
        let result = mollusk.process_instruction(&instruction, &[]);
        let success = result.raw_result.is_ok();
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
                "ArrayExample call {call} returned {} bytes, expected zero or eight",
                result.return_data.len()
            );
        };
        observations.push(json!({
            "id": id,
            "call": call,
            "success": success,
            "error": if success { None } else { Some(format!("{:?}", result.raw_result)) },
            "returnU64": return_u64,
            "computeUnits": result.compute_units_consumed,
        }));
    }

    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": "proof-forge.native-array-example.solana.v1",
            "runner": runner_name,
            "steps": observations,
        }))?
    );
    Ok(())
}
