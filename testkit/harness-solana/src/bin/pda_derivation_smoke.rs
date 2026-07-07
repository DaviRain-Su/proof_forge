use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::PathBuf;

use anyhow::{anyhow, bail, ensure, Context, Result};
use serde::Deserialize;
use serde_json::json;
use solana_address::Address;

#[derive(Debug, Deserialize)]
struct Artifact {
    #[serde(rename = "solanaExtensions")]
    solana_extensions: Option<SolanaExtensions>,
}

#[derive(Debug, Deserialize)]
struct SolanaExtensions {
    #[serde(default)]
    pdas: Vec<PdaDescriptor>,
}

#[derive(Debug, Deserialize)]
struct PdaDescriptor {
    name: String,
    #[serde(default)]
    seeds: Vec<String>,
    #[serde(rename = "typedSeeds", default)]
    typed_seeds: Vec<SeedDescriptor>,
}

#[derive(Clone, Debug, Deserialize, PartialEq, Eq)]
#[serde(tag = "kind", rename_all = "kebab-case")]
enum SeedDescriptor {
    Literal { value: String },
    Utf8 { value: String },
    Account { value: String },
    Bump { value: String },
    InstructionParam { value: String },
}

struct SeedContext {
    accounts: HashMap<String, Address>,
    bumps: HashMap<String, u8>,
    params: HashMap<String, Vec<u8>>,
}

fn main() {
    if let Err(err) = run() {
        eprintln!("{err:#}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let artifact_path = artifact_path()?;
    let artifact = load_artifact(&artifact_path)?;
    let vault = artifact
        .solana_extensions
        .as_ref()
        .context("artifact missing solanaExtensions")?
        .pdas
        .iter()
        .find(|pda| pda.name == "vault")
        .context("artifact missing vault PDA extension")?;

    let expected_seeds = vec!["vault".to_string(), "authority".to_string()];
    ensure!(
        vault.seeds == expected_seeds,
        "unexpected compatibility seeds: {:?}",
        vault.seeds
    );

    let expected_typed_seeds = vec![
        SeedDescriptor::Literal {
            value: "vault".to_string(),
        },
        SeedDescriptor::Account {
            value: "authority".to_string(),
        },
        SeedDescriptor::Bump {
            value: "vault_bump".to_string(),
        },
    ];
    ensure!(
        vault.typed_seeds == expected_typed_seeds,
        "unexpected typed seeds: {:?}",
        vault.typed_seeds
    );

    let literal = vault
        .typed_seeds
        .iter()
        .find_map(|seed| match seed {
            SeedDescriptor::Literal { value } => Some(value.as_str()),
            _ => None,
        })
        .context("vault PDA fixture should start with literal seed `vault`")?;
    ensure!(
        literal == "vault",
        "vault PDA fixture should start with literal seed `vault`"
    );

    let program_id = deterministic_address_from_byte(42);
    let (authority, pda, bump, attempt) = find_authority_with_bump_255(&program_id, literal)?;
    let context = SeedContext {
        accounts: HashMap::from([("authority".to_string(), authority)]),
        bumps: HashMap::from([("vault_bump".to_string(), bump)]),
        params: HashMap::new(),
    };

    let resolved_seeds = vault
        .typed_seeds
        .iter()
        .map(|seed| resolve_seed(seed, &context))
        .collect::<Result<Vec<_>>>()?;
    let seed_refs = resolved_seeds.iter().map(Vec::as_slice).collect::<Vec<_>>();
    let created = Address::create_program_address(&seed_refs, &program_id)
        .map_err(|err| anyhow!("create_program_address failed: {err:?}"))?;
    ensure!(
        created == pda,
        "create_program_address mismatch: created={} expected={}",
        hex::encode(created.as_ref()),
        hex::encode(pda.as_ref())
    );

    let utf8_seed = resolve_seed(
        &SeedDescriptor::Utf8 {
            value: "unicode-ok".to_string(),
        },
        &context,
    )?;
    ensure!(utf8_seed == b"unicode-ok", "utf8 seed resolver mismatch");

    let param_value = 42u64.to_le_bytes().to_vec();
    let param_seed = resolve_seed(
        &SeedDescriptor::InstructionParam {
            value: "amount".to_string(),
        },
        &SeedContext {
            params: HashMap::from([("amount".to_string(), param_value.clone())]),
            ..context
        },
    )?;
    ensure!(
        param_seed == param_value,
        "instruction-param seed resolver mismatch"
    );

    println!(
        "{}",
        json!({
            "pda": vault.name,
            "programIdHex": hex::encode(program_id.as_ref()),
            "authorityHex": hex::encode(authority.as_ref()),
            "bump": bump,
            "bumpSearchAttempt": attempt,
            "derivedHex": hex::encode(pda.as_ref()),
            "createdHex": hex::encode(created.as_ref()),
            "typedSeedKinds": vault.typed_seeds.iter().map(seed_kind).collect::<Vec<_>>(),
        })
    );

    Ok(())
}

fn artifact_path() -> Result<PathBuf> {
    if let Some(path) = env::args_os().nth(1) {
        return Ok(PathBuf::from(path));
    }
    env::var_os("PROOF_FORGE_SOLANA_ARTIFACT")
        .map(PathBuf::from)
        .context("missing artifact path argument or PROOF_FORGE_SOLANA_ARTIFACT")
}

fn load_artifact(path: &PathBuf) -> Result<Artifact> {
    let contents = fs::read_to_string(path)
        .with_context(|| format!("failed to read artifact metadata: {}", path.display()))?;
    serde_json::from_str(&contents)
        .with_context(|| format!("failed to parse artifact metadata: {}", path.display()))
}

fn deterministic_address_from_byte(byte: u8) -> Address {
    Address::new_from_array([byte; 32])
}

fn deterministic_address_from_counter(counter: u32) -> Address {
    let mut seed = [0u8; 32];
    seed[0..4].copy_from_slice(&counter.to_le_bytes());
    for (index, byte) in seed.iter_mut().enumerate().skip(4) {
        *byte = counter.wrapping_add((index as u32).wrapping_mul(17)) as u8;
    }
    Address::new_from_array(seed)
}

fn find_authority_with_bump_255(
    program_id: &Address,
    literal_seed: &str,
) -> Result<(Address, Address, u8, u32)> {
    for attempt in 0..4096 {
        let authority = deterministic_address_from_counter(attempt);
        let seeds = [literal_seed.as_bytes(), authority.as_ref()];
        let (pda, bump) = Address::find_program_address(&seeds, program_id);
        if bump == u8::MAX {
            return Ok((authority, pda, bump, attempt));
        }
    }
    bail!("failed to find deterministic authority with PDA bump=255")
}

fn resolve_seed(descriptor: &SeedDescriptor, context: &SeedContext) -> Result<Vec<u8>> {
    match descriptor {
        SeedDescriptor::Literal { value } | SeedDescriptor::Utf8 { value } => {
            Ok(value.as_bytes().to_vec())
        }
        SeedDescriptor::Account { value } => context
            .accounts
            .get(value)
            .map(|account| account.as_ref().to_vec())
            .with_context(|| format!("missing account seed source: {value}")),
        SeedDescriptor::Bump { value } => context
            .bumps
            .get(value)
            .copied()
            .map(|bump| vec![bump])
            .with_context(|| format!("missing u8 bump seed source: {value}")),
        SeedDescriptor::InstructionParam { value } => context
            .params
            .get(value)
            .cloned()
            .with_context(|| format!("missing instruction parameter seed source: {value}")),
    }
}

fn seed_kind(descriptor: &SeedDescriptor) -> &'static str {
    match descriptor {
        SeedDescriptor::Literal { .. } => "literal",
        SeedDescriptor::Utf8 { .. } => "utf8",
        SeedDescriptor::Account { .. } => "account",
        SeedDescriptor::Bump { .. } => "bump",
        SeedDescriptor::InstructionParam { .. } => "instruction-param",
    }
}
