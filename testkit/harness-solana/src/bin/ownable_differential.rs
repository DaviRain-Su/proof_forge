use std::env;
use std::path::Path;

use anyhow::{bail, Context, Result};
use mollusk_svm::Mollusk;
use serde_json::json;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};

#[derive(Clone, Copy)]
enum Actor {
    Alice,
    Bob,
}

const STEPS: [(&str, &str, u8, Actor, Option<&str>); 10] = [
    ("initialize-alice", "initialize", 0, Actor::Alice, None),
    ("owner-alice", "owner", 1, Actor::Alice, None),
    (
        "unauthorized-transfer",
        "transfer_ownership",
        2,
        Actor::Bob,
        Some("bob"),
    ),
    (
        "zero-address-transfer",
        "transfer_ownership",
        2,
        Actor::Alice,
        Some("zero"),
    ),
    (
        "transfer-to-bob",
        "transfer_ownership",
        2,
        Actor::Alice,
        Some("bob"),
    ),
    ("owner-bob", "owner", 1, Actor::Bob, None),
    (
        "old-owner-renounce",
        "renounce_ownership",
        3,
        Actor::Alice,
        None,
    ),
    (
        "renounce-bob",
        "renounce_ownership",
        3,
        Actor::Bob,
        None,
    ),
    ("owner-zero", "owner", 1, Actor::Alice, None),
    (
        "reinitialize-after-renounce",
        "initialize",
        0,
        Actor::Alice,
        None,
    ),
];

fn read_u64(data: &[u8], offset: usize) -> Result<u64> {
    Ok(u64::from_le_bytes(
        data.get(offset..offset + 8)
            .context("Ownable state account is shorter than 16 bytes")?
            .try_into()
            .expect("slice length is eight bytes"),
    ))
}

fn handle(address: &Address) -> u64 {
    u64::from_le_bytes(address.as_array()[..8].try_into().expect("address prefix is eight bytes"))
}

fn main() -> Result<()> {
    let program = env::args()
        .nth(1)
        .context("usage: ownable_differential <ownable.so> <runner-name>")?;
    let runner_name = env::args()
        .nth(2)
        .context("usage: ownable_differential <ownable.so> <runner-name>")?;
    let program_path = Path::new(&program);
    if !program_path.is_file() {
        bail!("Ownable ELF does not exist: {}", program_path.display());
    }
    let stem = program_path.with_extension("");
    let stem = stem.to_str().context("Ownable ELF path is not valid UTF-8")?;

    let program_id = Address::new_from_array([17; 32]);
    let state_id = Address::new_from_array([19; 32]);
    let alice_id = Address::new_from_array([21; 32]);
    let bob_id = Address::new_from_array([22; 32]);
    let system_owner = Address::default();
    let alice = Account::new(1_000_000, 0, &system_owner);
    let bob = Account::new(1_000_000, 0, &system_owner);
    let mut state = Account::new(1_000_000, 16, &program_id);
    let mut mollusk = Mollusk::new(&program_id, stem);
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;
    mollusk.logger = Some(Default::default());
    let logger = mollusk.logger.as_ref().expect("logger installed").clone();

    let mut observations = Vec::new();
    for (id, call, tag, actor, destination) in STEPS {
        let (authority_id, authority) = match actor {
            Actor::Alice => (alice_id, alice.clone()),
            Actor::Bob => (bob_id, bob.clone()),
        };
        let mut instruction_data = vec![tag];
        if call == "transfer_ownership" {
            let value = match destination.expect("transfer steps declare a destination") {
                "bob" => handle(&bob_id),
                "zero" => 0,
                value => bail!("unsupported Ownable destination {value}"),
            };
            instruction_data.extend(value.to_le_bytes());
        }
        let instruction = Instruction::new_with_bytes(
            program_id,
            &instruction_data,
            vec![
                AccountMeta::new_readonly(authority_id, true),
                AccountMeta::new(state_id, false),
            ],
        );
        let log_start = logger.borrow().messages.len();
        let result = mollusk.process_instruction(
            &instruction,
            &[(authority_id, authority), (state_id, state.clone())],
        );
        let success = result.raw_result.is_ok();
        if success {
            state = result
                .get_account(&state_id)
                .with_context(|| format!("Ownable call {call} did not return its state account"))?
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
                "Ownable call {call} returned {} bytes, expected zero or eight",
                result.return_data.len()
            );
        };
        observations.push(json!({
            "id": id,
            "call": call,
            "actor": match actor { Actor::Alice => "alice", Actor::Bob => "bob" },
            "newOwner": destination,
            "success": success,
            "error": if success { None } else { Some(format!("{:?}", result.raw_result)) },
            "returnU64": return_u64,
            "state": {
                "owner": read_u64(&state.data, 0)?,
                "initialized": read_u64(&state.data, 8)?,
            },
            "logs": raw_logs,
            "computeUnits": result.compute_units_consumed,
        }));
    }

    println!(
        "{}",
        serde_json::to_string(&json!({
            "schema": "proof-forge.native-ownable.solana.v1",
            "runner": runner_name,
            "roles": {
                "alice": handle(&alice_id),
                "bob": handle(&bob_id),
                "zero": 0,
            },
            "steps": observations,
        }))?
    );
    Ok(())
}
