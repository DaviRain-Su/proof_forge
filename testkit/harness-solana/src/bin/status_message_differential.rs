use std::env;
use std::path::Path;

use anyhow::{bail, Context, Result};
use mollusk_svm::Mollusk;
use serde_json::json;
use sha2::{Digest, Sha256};
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};

const STATE_LEN: usize = 20_000;
const STEPS: [(&str, &str, u8, Option<u64>); 5] = [
    ("initialize", "init", 0, None),
    ("set-seven", "set_status", 1, Some(7)),
    ("get-seven", "get_status", 2, None),
    ("set-ninety-nine", "set_status", 1, Some(99)),
    ("get-ninety-nine", "get_status", 2, None),
];

fn handle(address: &Address) -> u64 {
    let digest = Sha256::digest(address.as_array());
    u64::from_le_bytes(
        digest[..8]
            .try_into()
            .expect("digest prefix is eight bytes"),
    )
}

fn return_u64(data: &[u8], call: &str) -> Result<Option<u64>> {
    if data.is_empty() {
        return Ok(None);
    }
    if data.len() != 8 {
        bail!("StatusMessage call {call} returned {} bytes", data.len());
    }
    Ok(Some(u64::from_le_bytes(
        data.try_into().expect("return-data length checked"),
    )))
}

fn instruction(
    program_id: Address,
    authority_id: Address,
    state_id: Address,
    data: &[u8],
) -> Instruction {
    Instruction::new_with_bytes(
        program_id,
        data,
        vec![
            AccountMeta::new_readonly(authority_id, true),
            AccountMeta::new(state_id, false),
        ],
    )
}

fn main() -> Result<()> {
    let program = env::args()
        .nth(1)
        .context("usage: status_message_differential <status-message.so> <runner-name>")?;
    let runner_name = env::args()
        .nth(2)
        .context("usage: status_message_differential <status-message.so> <runner-name>")?;
    let program_path = Path::new(&program);
    if !program_path.is_file() {
        bail!(
            "StatusMessage ELF does not exist: {}",
            program_path.display()
        );
    }
    let stem = program_path.with_extension("");
    let stem = stem
        .to_str()
        .context("StatusMessage ELF path is not valid UTF-8")?;

    let program_id = Address::new_from_array([71; 32]);
    let state_id = Address::new_from_array([72; 32]);
    let alice_id = Address::new_from_array([73; 32]);
    let system_owner = Address::default();
    let alice = Account::new(1_000_000, 0, &system_owner);
    let mut state = Account::new(1_000_000, STATE_LEN, &program_id);
    let alice_handle = handle(&alice_id);

    let mut mollusk = Mollusk::new(&program_id, stem);
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;
    mollusk.logger = Some(Default::default());
    let logger = mollusk.logger.as_ref().expect("logger installed").clone();

    let mut observations = Vec::new();
    for (id, call, tag, status) in STEPS {
        let mut data = vec![tag];
        match call {
            "set_status" => data.extend(status.expect("set step has status").to_le_bytes()),
            "get_status" => data.extend(alice_handle.to_le_bytes()),
            _ => {}
        }
        let log_start = logger.borrow().messages.len();
        let result = mollusk.process_instruction(
            &instruction(program_id, alice_id, state_id, &data),
            &[(alice_id, alice.clone()), (state_id, state.clone())],
        );
        let success = result.raw_result.is_ok();
        if success {
            state = result
                .get_account(&state_id)
                .with_context(|| format!("StatusMessage call {call} did not return state"))?
                .clone();
        }
        let log_end = logger.borrow().messages.len();
        let logs = logger.borrow().messages[log_start..log_end].to_vec();
        let returned = return_u64(&result.return_data, call)?;

        let observed_status = if call == "get_status" {
            returned.context("get_status returned no value")?
        } else {
            let mut query = vec![2];
            query.extend(alice_handle.to_le_bytes());
            let snapshot = mollusk.process_instruction(
                &instruction(program_id, alice_id, state_id, &query),
                &[(alice_id, alice.clone()), (state_id, state.clone())],
            );
            if snapshot.raw_result.is_err() {
                bail!(
                    "StatusMessage snapshot after {call} failed: {:?}",
                    snapshot.raw_result
                );
            }
            return_u64(&snapshot.return_data, "get_status snapshot")?
                .context("get_status snapshot returned no value")?
        };

        observations.push(json!({
            "id": id,
            "call": call,
            "success": success,
            "error": if success { None } else { Some(format!("{:?}", result.raw_result)) },
            "returnU64": returned,
            "status": observed_status,
            "logs": logs,
            "computeUnits": result.compute_units_consumed,
        }));
    }

    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": "proof-forge.native-status-message.solana.v1",
            "runner": runner_name,
            "aliceHandle": alice_handle,
            "steps": observations,
        }))?
    );
    Ok(())
}
