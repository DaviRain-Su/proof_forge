use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::Path;

use anyhow::{bail, ensure, Context as _, Result};
use revm::{
    context::{BlockEnv, CfgEnv, TxEnv},
    database::{CacheDB, EmptyDB},
    primitives::{Address, Bytes, TxKind, B256, U256},
    state::AccountInfo,
    Context, ExecuteCommitEvm, MainBuilder, MainContext,
};
use serde_json::Value;

const DEPLOYER: Address = Address::new([
    0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
const BOB: Address = Address::new([
    0x20, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
const SPENDER: Address = Address::new([
    0x30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
const CAROL: Address = Address::new([
    0x40, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
const ZERO_ADDRESS: Address = Address::ZERO;
const ACCOUNT_BALANCE: u128 = 1_000_000_000_000_000_000;
const DEPLOY_GAS_LIMIT: u64 = 10_000_000;
const CALL_GAS_LIMIT: u64 = 5_000_000;

type TokenIntentEvm = revm::MainnetEvm<Context<BlockEnv, TxEnv, CfgEnv, CacheDB<EmptyDB>>>;

fn main() -> Result<()> {
    let mut args = env::args().skip(1);
    let Some(bin_path) = args.next() else {
        bail!("usage: token_intent_erc20_vm_smoke <creation-bin> <artifact-json>");
    };
    let Some(artifact_path) = args.next() else {
        bail!("usage: token_intent_erc20_vm_smoke <creation-bin> <artifact-json>");
    };
    ensure!(args.next().is_none(), "unexpected extra arguments");

    let artifact = read_json(Path::new(&artifact_path))?;
    ensure!(
        string_at(&artifact, &["format"])? == "proof-forge-token-artifact-v0",
        "unexpected token artifact format"
    );
    ensure!(
        string_at(&artifact, &["target"])? == "evm",
        "expected EVM token artifact"
    );
    ensure!(
        string_at(&artifact, &["standard"])? == "erc20",
        "expected ERC-20 token artifact"
    );

    let selectors = selector_map(&artifact)?;
    let events = event_map(&artifact)?;
    let operations = operation_map(&artifact)?;
    let creation_bytecode = read_hex_file(Path::new(&bin_path))?;

    let mut db = CacheDB::new(EmptyDB::new());
    for address in [DEPLOYER, BOB, SPENDER, CAROL] {
        db.insert_account_info(
            address,
            AccountInfo {
                balance: U256::from(ACCOUNT_BALANCE),
                ..AccountInfo::default()
            },
        );
    }

    let mut evm = Context::mainnet().with_db(db).build_mainnet();
    let mut nonces = HashMap::new();
    let contract = deploy(&mut evm, creation_bytecode, &mut nonces)?;

    let initial_supply = u256_at(&artifact, &["token", "initialSupply"])?;
    let decimals = u256_at(&artifact, &["token", "decimals"])?;
    let mut expected_total_supply = initial_supply;
    let mut expected_bob_balance = U256::ZERO;
    let mut expected_carol_balance = U256::ZERO;

    ensure!(
        read_uint(
            &mut evm,
            &selectors,
            contract,
            "totalSupply",
            &[],
            &mut nonces
        )? == initial_supply,
        "initial total supply mismatch"
    );
    ensure!(
        balance_of(&mut evm, &selectors, contract, DEPLOYER, &mut nonces)? == initial_supply,
        "deployer initial balance mismatch"
    );
    ensure!(
        balance_of(&mut evm, &selectors, contract, BOB, &mut nonces)? == U256::ZERO,
        "recipient should start with zero balance"
    );
    ensure!(
        read_uint(&mut evm, &selectors, contract, "decimals", &[], &mut nonces)? == decimals,
        "decimals mismatch"
    );

    let mut result = call(
        &mut evm,
        &selectors,
        contract,
        DEPLOYER,
        "transfer",
        &[address_word(BOB), word(U256::from(300_000u64))],
        false,
        &mut nonces,
    )?;
    require_bool_return(&result.output, "transfer")?;
    ensure!(result.logs.len() == 1, "transfer should emit one event");
    require_transfer_log(
        &result.logs[0],
        &events,
        DEPLOYER,
        BOB,
        U256::from(300_000u64),
        "transfer",
    )?;
    expected_bob_balance += U256::from(300_000u64);
    ensure!(
        balance_of(&mut evm, &selectors, contract, DEPLOYER, &mut nonces)?
            == U256::from(700_000u64),
        "deployer balance after transfer mismatch"
    );
    ensure!(
        balance_of(&mut evm, &selectors, contract, BOB, &mut nonces)? == expected_bob_balance,
        "recipient balance after transfer mismatch"
    );
    ensure!(
        read_uint(
            &mut evm,
            &selectors,
            contract,
            "totalSupply",
            &[],
            &mut nonces
        )? == expected_total_supply,
        "transfer changed total supply"
    );

    result = call(
        &mut evm,
        &selectors,
        contract,
        DEPLOYER,
        "approve",
        &[address_word(SPENDER), word(U256::from(12_345u64))],
        false,
        &mut nonces,
    )?;
    require_bool_return(&result.output, "approve")?;
    ensure!(result.logs.len() == 1, "approve should emit one event");
    require_approval_log(
        &result.logs[0],
        &events,
        DEPLOYER,
        SPENDER,
        U256::from(12_345u64),
    )?;
    ensure!(
        read_uint(
            &mut evm,
            &selectors,
            contract,
            "allowance",
            &[address_word(DEPLOYER), address_word(SPENDER)],
            &mut nonces,
        )? == U256::from(12_345u64),
        "allowance after approve mismatch"
    );

    result = call(
        &mut evm,
        &selectors,
        contract,
        SPENDER,
        "transferFrom",
        &[
            address_word(DEPLOYER),
            address_word(CAROL),
            word(U256::from(10_000u64)),
        ],
        false,
        &mut nonces,
    )?;
    require_bool_return(&result.output, "transferFrom")?;
    ensure!(result.logs.len() == 1, "transferFrom should emit one event");
    require_transfer_log(
        &result.logs[0],
        &events,
        DEPLOYER,
        CAROL,
        U256::from(10_000u64),
        "transferFrom",
    )?;
    ensure!(
        read_uint(
            &mut evm,
            &selectors,
            contract,
            "allowance",
            &[address_word(DEPLOYER), address_word(SPENDER)],
            &mut nonces,
        )? == U256::from(2_345u64),
        "allowance after transferFrom mismatch"
    );
    expected_carol_balance += U256::from(10_000u64);
    ensure!(
        balance_of(&mut evm, &selectors, contract, DEPLOYER, &mut nonces)?
            == U256::from(690_000u64),
        "deployer balance after transferFrom mismatch"
    );
    ensure!(
        balance_of(&mut evm, &selectors, contract, CAROL, &mut nonces)? == expected_carol_balance,
        "transferFrom recipient balance mismatch"
    );

    if operations.contains_key("erc20.burn") {
        result = call(
            &mut evm,
            &selectors,
            contract,
            CAROL,
            "burn",
            &[word(U256::from(5_000u64))],
            false,
            &mut nonces,
        )?;
        require_bool_return(&result.output, "burn")?;
        ensure!(result.logs.len() == 1, "burn should emit one event");
        require_transfer_log(
            &result.logs[0],
            &events,
            CAROL,
            ZERO_ADDRESS,
            U256::from(5_000u64),
            "burn",
        )?;
        expected_total_supply -= U256::from(5_000u64);
        expected_carol_balance -= U256::from(5_000u64);
        ensure!(
            read_uint(
                &mut evm,
                &selectors,
                contract,
                "totalSupply",
                &[],
                &mut nonces
            )? == expected_total_supply,
            "total supply after burn mismatch"
        );
        ensure!(
            balance_of(&mut evm, &selectors, contract, CAROL, &mut nonces)?
                == expected_carol_balance,
            "burner balance after burn mismatch"
        );
    }

    if operations.contains_key("erc20.mint") {
        result = call(
            &mut evm,
            &selectors,
            contract,
            DEPLOYER,
            "mint",
            &[address_word(BOB), word(U256::from(7_000u64))],
            false,
            &mut nonces,
        )?;
        require_bool_return(&result.output, "mint")?;
        ensure!(result.logs.len() == 1, "mint should emit one event");
        require_transfer_log(
            &result.logs[0],
            &events,
            ZERO_ADDRESS,
            BOB,
            U256::from(7_000u64),
            "mint",
        )?;
        expected_total_supply += U256::from(7_000u64);
        expected_bob_balance += U256::from(7_000u64);
        ensure!(
            read_uint(
                &mut evm,
                &selectors,
                contract,
                "totalSupply",
                &[],
                &mut nonces
            )? == expected_total_supply,
            "total supply after mint mismatch"
        );
        ensure!(
            balance_of(&mut evm, &selectors, contract, BOB, &mut nonces)? == expected_bob_balance,
            "mint recipient balance mismatch"
        );
    }

    call(
        &mut evm,
        &selectors,
        contract,
        CAROL,
        "transfer",
        &[address_word(BOB), word(U256::from(999_999u64))],
        true,
        &mut nonces,
    )?;
    ensure!(
        balance_of(&mut evm, &selectors, contract, CAROL, &mut nonces)? == expected_carol_balance,
        "reverted transfer changed sender balance"
    );

    println!("token-intent-erc20-vm: ok ({contract})");
    Ok(())
}

struct CallResult {
    output: Bytes,
    logs: Vec<revm::primitives::Log>,
}

fn deploy(
    evm: &mut TokenIntentEvm,
    creation_bytecode: Vec<u8>,
    nonces: &mut HashMap<Address, u64>,
) -> Result<Address> {
    let nonce = next_nonce(nonces, DEPLOYER);
    let tx = TxEnv::builder()
        .caller(DEPLOYER)
        .gas_limit(DEPLOY_GAS_LIMIT)
        .gas_price(0)
        .kind(TxKind::Create)
        .value(U256::ZERO)
        .data(Bytes::from(creation_bytecode))
        .nonce(nonce)
        .build()
        .context("failed to build deploy transaction")?;
    match evm
        .transact_commit(tx)
        .context("deployment failed before execution")?
    {
        revm::context_interface::result::ExecutionResult::Success { output, .. } => {
            let address = output
                .address()
                .copied()
                .context("deployment did not create a contract address")?;
            Ok(address)
        }
        revm::context_interface::result::ExecutionResult::Revert { output, .. } => {
            bail!("deploy reverted with {} byte(s)", output.len())
        }
        revm::context_interface::result::ExecutionResult::Halt { reason, .. } => {
            bail!("deploy halted: {reason}")
        }
    }
}

fn call(
    evm: &mut TokenIntentEvm,
    selectors: &HashMap<String, String>,
    contract: Address,
    caller: Address,
    name: &str,
    args: &[Vec<u8>],
    expect_revert: bool,
    nonces: &mut HashMap<Address, u64>,
) -> Result<CallResult> {
    let selector = selectors
        .get(name)
        .with_context(|| format!("artifact missing selector for `{name}`"))?;
    let mut calldata = decode_hex(selector)?;
    for arg in args {
        calldata.extend_from_slice(arg);
    }
    let nonce = next_nonce(nonces, caller);
    let tx = TxEnv::builder()
        .caller(caller)
        .gas_limit(CALL_GAS_LIMIT)
        .gas_price(0)
        .kind(TxKind::Call(contract))
        .value(U256::ZERO)
        .data(Bytes::from(calldata))
        .nonce(nonce)
        .build()
        .with_context(|| format!("failed to build `{name}` transaction"))?;
    match evm
        .transact_commit(tx)
        .with_context(|| format!("call `{name}` failed before execution"))?
    {
        revm::context_interface::result::ExecutionResult::Success { output, logs, .. } => {
            ensure!(!expect_revert, "{name} did not revert");
            Ok(CallResult {
                output: output.into_data(),
                logs,
            })
        }
        revm::context_interface::result::ExecutionResult::Revert { output, .. } => {
            ensure!(
                expect_revert,
                "{name} reverted with {} byte(s)",
                output.len()
            );
            Ok(CallResult {
                output,
                logs: Vec::new(),
            })
        }
        revm::context_interface::result::ExecutionResult::Halt { reason, .. } => {
            bail!("{name} halted: {reason}")
        }
    }
}

fn read_uint(
    evm: &mut TokenIntentEvm,
    selectors: &HashMap<String, String>,
    contract: Address,
    name: &str,
    args: &[Vec<u8>],
    nonces: &mut HashMap<Address, u64>,
) -> Result<U256> {
    let result = call(
        evm, selectors, contract, DEPLOYER, name, args, false, nonces,
    )?;
    ensure!(result.output.len() == 32, "{name} did not return one word");
    Ok(U256::from_be_slice(&result.output))
}

fn balance_of(
    evm: &mut TokenIntentEvm,
    selectors: &HashMap<String, String>,
    contract: Address,
    owner: Address,
    nonces: &mut HashMap<Address, u64>,
) -> Result<U256> {
    read_uint(
        evm,
        selectors,
        contract,
        "balanceOf",
        &[address_word(owner)],
        nonces,
    )
}

fn next_nonce(nonces: &mut HashMap<Address, u64>, caller: Address) -> u64 {
    let entry = nonces.entry(caller).or_insert(0);
    let nonce = *entry;
    *entry += 1;
    nonce
}

fn require_bool_return(output: &[u8], label: &str) -> Result<()> {
    ensure!(output.len() == 32, "{label} did not return one word");
    ensure!(
        U256::from_be_slice(output) == U256::from(1u8),
        "{label} did not return true"
    );
    Ok(())
}

fn require_transfer_log(
    log: &revm::primitives::Log,
    events: &HashMap<String, B256>,
    from: Address,
    to: Address,
    amount: U256,
    label: &str,
) -> Result<()> {
    let transfer = events
        .get("Transfer")
        .context("artifact missing Transfer event topic")?;
    let topics = log.topics();
    ensure!(topics.len() == 3, "{label} Transfer topic count mismatch");
    ensure!(&topics[0] == transfer, "{label} Transfer topic mismatch");
    ensure!(
        topic_address(&topics[1]) == from,
        "{label} from topic mismatch"
    );
    ensure!(topic_address(&topics[2]) == to, "{label} to topic mismatch");
    ensure!(log_data_word(log) == amount, "{label} amount log mismatch");
    Ok(())
}

fn require_approval_log(
    log: &revm::primitives::Log,
    events: &HashMap<String, B256>,
    owner: Address,
    spender: Address,
    amount: U256,
) -> Result<()> {
    let approval = events
        .get("Approval")
        .context("artifact missing Approval event topic")?;
    let topics = log.topics();
    ensure!(topics.len() == 3, "Approval topic count mismatch");
    ensure!(&topics[0] == approval, "Approval topic mismatch");
    ensure!(
        topic_address(&topics[1]) == owner,
        "Approval owner topic mismatch"
    );
    ensure!(
        topic_address(&topics[2]) == spender,
        "Approval spender topic mismatch"
    );
    ensure!(log_data_word(log) == amount, "Approval amount log mismatch");
    Ok(())
}

fn word(value: U256) -> Vec<u8> {
    value.to_be_bytes::<32>().to_vec()
}

fn address_word(address: Address) -> Vec<u8> {
    let mut bytes = vec![0u8; 32];
    bytes[12..].copy_from_slice(address.as_slice());
    bytes
}

fn topic_address(topic: &B256) -> Address {
    Address::from_slice(&topic.as_slice()[12..])
}

fn log_data_word(log: &revm::primitives::Log) -> U256 {
    U256::from_be_slice(&log.data.data)
}

fn read_json(path: &Path) -> Result<Value> {
    let text =
        fs::read_to_string(path).with_context(|| format!("failed to read `{}`", path.display()))?;
    serde_json::from_str(&text).with_context(|| format!("failed to parse `{}`", path.display()))
}

fn read_hex_file(path: &Path) -> Result<Vec<u8>> {
    let text =
        fs::read_to_string(path).with_context(|| format!("failed to read `{}`", path.display()))?;
    decode_hex(text.trim())
}

fn decode_hex(value: &str) -> Result<Vec<u8>> {
    let trimmed = value.strip_prefix("0x").unwrap_or(value);
    hex::decode(trimmed).with_context(|| format!("failed to decode hex `{value}`"))
}

fn string_at<'a>(value: &'a Value, path: &[&str]) -> Result<&'a str> {
    let mut cursor = value;
    for key in path {
        cursor = cursor
            .get(*key)
            .with_context(|| format!("artifact missing `{}`", path.join(".")))?;
    }
    cursor
        .as_str()
        .with_context(|| format!("artifact `{}` is not a string", path.join(".")))
}

fn u256_at(value: &Value, path: &[&str]) -> Result<U256> {
    let mut cursor = value;
    for key in path {
        cursor = cursor
            .get(*key)
            .with_context(|| format!("artifact missing `{}`", path.join(".")))?;
    }
    if let Some(number) = cursor.as_u64() {
        return Ok(U256::from(number));
    }
    if let Some(text) = cursor.as_str() {
        return U256::from_str_radix(text, 10)
            .with_context(|| format!("artifact `{}` is not a decimal integer", path.join(".")));
    }
    bail!("artifact `{}` is not an integer", path.join("."))
}

fn selector_map(artifact: &Value) -> Result<HashMap<String, String>> {
    let entrypoints = artifact
        .pointer("/abi/entrypoints")
        .and_then(Value::as_array)
        .context("artifact missing abi.entrypoints array")?;
    let mut map = HashMap::new();
    for entry in entrypoints {
        let name = string_at(entry, &["name"])?.to_string();
        let selector = string_at(entry, &["selector"])?.to_string();
        map.insert(name, selector);
    }
    Ok(map)
}

fn event_map(artifact: &Value) -> Result<HashMap<String, B256>> {
    let events = artifact
        .pointer("/abi/events")
        .and_then(Value::as_array)
        .context("artifact missing abi.events array")?;
    let mut map = HashMap::new();
    for event in events {
        let name = string_at(event, &["name"])?.to_string();
        let topic = decode_hex(string_at(event, &["topic0"])?)?;
        ensure!(topic.len() == 32, "event `{name}` topic0 must be 32 bytes");
        map.insert(name, B256::from_slice(&topic));
    }
    Ok(map)
}

fn operation_map(artifact: &Value) -> Result<HashMap<String, ()>> {
    let operations = artifact
        .get("operations")
        .and_then(Value::as_array)
        .context("artifact missing operations array")?;
    let mut map = HashMap::new();
    for operation in operations {
        let operation = operation
            .as_str()
            .context("artifact operations entry is not a string")?;
        map.insert(operation.to_string(), ());
    }
    Ok(map)
}
