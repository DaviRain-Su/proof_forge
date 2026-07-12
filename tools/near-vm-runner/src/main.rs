// near-vm-runner: execute ProofForge-generated NEAR Wasm on the real NEAR VM.
//
// Uses MockedExternal from near-vm-runner for in-memory storage. The real NEAR
// Protocol VM (Wasmtime backend) prepares, links, and executes the contract.
//
// This is a *conformance* runner: its job is to prove that ProofForge's
// EmitWat output is accepted and executed by the unmodified upstream NEAR VM,
// not to model NEAR transaction/action receipt semantics. State (storage and
// storage_usage) is carried across method calls so write-then-read sequences
// exercise real storage eviction accounting.
//
// Per-method Borsh `input` (`--input-hex` / `--inputs-hex`) lets parameterized
// entrypoints (e.g. NEP-141 `ft_transfer`) run to the semantic layer on the
// real VM, mirroring `runtime/offline-host`. `--promise-result-u64 N` injects a
// single `PromiseResult::Successful(Borsh U64)` into every call's context so
// callback dispatch entrypoints (`promise_results_count` / `promise_result`,
// e.g. `ft_resolve_transfer`) exercise the *real* near-vm-logic promise-result
// host functions. This is a conformance approximation: it does NOT schedule or
// execute the receipts that `promise_create`/`promise_then` produce — only the
// callback-side read is validated against the real VM.
//
// Exit codes: 0 = every method executed without abort; 1 = I/O or execution
// failure (including `outcome.aborted`, which the VM reports as `Ok`); 2 =
// usage error.

use near_parameters::ExtCostsConfig;
use near_parameters::{RuntimeConfigStore, RuntimeFeesConfig};
use near_parameters::vm::Config;
use near_primitives_core::account::AccountContract;
use near_primitives_core::hash::CryptoHash;
use near_primitives_core::types::{Gas, StorageUsage};
use near_primitives_core::version::PROTOCOL_VERSION;
use near_vm_runner::logic::mocks::mock_external::MockedExternal;
use near_vm_runner::logic::types::{PromiseResult, ReturnData};
use near_vm_runner::logic::VMContext;
use near_vm_runner::{prepare, run, ContractCode};
use std::env;
use std::fs;
use std::process;
use std::rc::Rc;
use std::sync::Arc;

const PREPAID_GAS: u64 = 300_000_000_000_000; // 300 Tgas

/// Parsed CLI configuration.
struct Cli {
    wasm_path: String,
    methods: Vec<String>,
    /// One Borsh input blob per method (defaults to empty input per method).
    inputs: Vec<Vec<u8>>,
    /// Injected promise results applied to every call's VMContext (empty by
    /// default, matching real receipt-free execution).
    promise_results: Arc<[PromiseResult]>,
}

impl Cli {
    fn parse(args: Vec<String>) -> Result<Self, String> {
        let mut positionals: Vec<String> = Vec::new();
        let mut single_input: Option<Vec<u8>> = None;
        let mut inputs_seq: Option<Vec<Vec<u8>>> = None;
        let mut promise_result_u64: Option<u64> = None;

        let mut it = args.into_iter().peekable();
        while let Some(arg) = it.next() {
            match arg.as_str() {
                "-h" | "--help" => {
                    print_usage();
                    process::exit(0);
                }
                "--input-hex" => {
                    single_input = Some(parse_hex(&take_value(&mut it, "--input-hex")?)?);
                }
                "--inputs-hex" => {
                    inputs_seq = Some(parse_hex_sequence(&take_value(&mut it, "--inputs-hex")?)?);
                }
                "--promise-result-u64" => {
                    let raw = take_value(&mut it, "--promise-result-u64")?;
                    promise_result_u64 = Some(
                        raw.parse::<u64>()
                            .map_err(|_| format!("--promise-result-u64 must be a u64, got `{raw}`"))?,
                    );
                }
                s if s.starts_with('-') => return Err(format!("unknown option `{s}`")),
                s => positionals.push(s.to_string()),
            }
        }

        if positionals.len() < 2 {
            print_usage();
            return Err("expected <wasm-file> and at least one <method>".to_string());
        }

        let wasm_path = positionals.remove(0);
        let methods = positionals;

        if single_input.is_some() && inputs_seq.is_some() {
            return Err("--input-hex cannot be combined with --inputs-hex".to_string());
        }

        let inputs = match (inputs_seq, single_input) {
            (Some(seq), _) => {
                if seq.len() != methods.len() {
                    return Err(format!(
                        "--inputs-hex provided {} item(s), but the method sequence has {} call(s)",
                        seq.len(),
                        methods.len()
                    ));
                }
                seq
            }
            (_, Some(one)) => vec![one; methods.len()],
            _ => vec![Vec::new(); methods.len()],
        };

        let promise_results: Arc<[PromiseResult]> = match promise_result_u64 {
            Some(value) => Arc::from(vec![PromiseResult::Successful(Rc::from(
                value.to_le_bytes().as_slice(),
            ))]),
            None => Arc::from(Vec::new()),
        };

        Ok(Self { wasm_path, methods, inputs, promise_results })
    }
}

fn take_value<I: Iterator<Item = String>>(it: &mut std::iter::Peekable<I>, option: &str) -> Result<String, String> {
    it.next().ok_or_else(|| format!("{option} requires a value"))
}

fn print_usage() {
    eprintln!(
        "usage: near-vm-runner <wasm-file> <method> [<method> ...] [options]\n\
         \n\
         options:\n\
           --input-hex HEX           Borsh input bytes (hex) applied to every method call\n\
           --inputs-hex HEX[,HEX...]  one Borsh input blob per method in the sequence\n\
           --promise-result-u64 N    inject one Successful promise_result (Borsh U64 LE) into every call\n\
         \n\
         exit codes: 0 = all methods executed without abort; 1 = failure; 2 = usage error"
    );
}

fn parse_hex(input: &str) -> Result<Vec<u8>, String> {
    let compact: String = input.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.is_empty() {
        return Ok(Vec::new());
    }
    if compact.len() % 2 != 0 {
        return Err("hex input must have an even number of digits".to_string());
    }
    let mut out = Vec::with_capacity(compact.len() / 2);
    for chunk in compact.as_bytes().chunks_exact(2) {
        let s = std::str::from_utf8(chunk).map_err(|_| "invalid hex byte".to_string())?;
        out.push(
            u8::from_str_radix(s, 16).map_err(|_| format!("invalid hex byte `{s}`"))?,
        );
    }
    Ok(out)
}

fn parse_hex_sequence(input: &str) -> Result<Vec<Vec<u8>>, String> {
    input.split(',').map(parse_hex).collect()
}

fn make_context(
    storage_usage: StorageUsage,
    input: Rc<[u8]>,
    promise_results: Arc<[PromiseResult]>,
) -> VMContext {
    // All three account ids default to the contract account, matching the
    // `runtime/offline-host` defaults used by the NEP-141 fixture flow (where
    // the input's sender hash is sha256("proof-forge.testnet")). The Counter
    // conformance fixture is account-id-agnostic, so this default is safe.
    let account_id: near_primitives_core::types::AccountId =
        "proof-forge.testnet".parse().unwrap();
    VMContext {
        current_account_id: account_id.clone(),
        signer_account_id: account_id.clone(),
        signer_account_pk: vec![0u8; 32],
        predecessor_account_id: account_id.clone(),
        refund_to_account_id: account_id,
        input,
        promise_results,
        block_height: 1,
        block_timestamp: 1000,
        epoch_height: 0,
        account_balance: near_primitives_core::types::Balance::from_yoctonear(10u128.pow(24)),
        account_locked_balance: near_primitives_core::types::Balance::ZERO,
        storage_usage,
        account_contract: AccountContract::from_local_code_hash(CryptoHash::default()),
        attached_deposit: near_primitives_core::types::Balance::ZERO,
        prepaid_gas: Gas::from_gas(PREPAID_GAS),
        random_seed: vec![0u8; 32],
        view_config: None,
        output_data_receivers: vec![],
    }
}

fn main() {
    let args: Vec<String> = env::args().skip(1).collect();
    let config = match Cli::parse(args) {
        Ok(c) => c,
        Err(message) => {
            eprintln!("near-vm-runner: {message}");
            process::exit(2);
        }
    };

    let wasm = fs::read(&config.wasm_path).unwrap_or_else(|e| {
        eprintln!("failed to read {}: {}", config.wasm_path, e);
        process::exit(1);
    });

    let code = ContractCode::new(wasm, None);
    let mut ext = MockedExternal::with_code(code);

    let runtime_config = RuntimeConfigStore::test()
        .get_config(PROTOCOL_VERSION)
        .clone();
    let mut wasm_config = Config::clone(&runtime_config.wasm_config);
    wasm_config.vm_kind = wasm_config.vm_kind.replace_with_wasmtime_if_unsupported();
    let wasm_config = Arc::new(wasm_config);
    let fees_config: Arc<RuntimeFeesConfig> = Arc::clone(&runtime_config.fees);

    // Storage usage is carried across calls: a write that evicts a value left
    // by a previous call must see the prior usage in its VMContext, otherwise
    // the VM's eviction accounting (`usage - evicted_len`) underflows.
    let mut storage_usage: StorageUsage = 0;

    for (call_index, method) in config.methods.iter().enumerate() {
        let input: Rc<[u8]> = Rc::from(config.inputs[call_index].as_slice());
        let context = make_context(
            storage_usage,
            Rc::clone(&input),
            Arc::clone(&config.promise_results),
        );
        let gas_counter = near_vm_runner::logic::GasCounter::new(
            ExtCostsConfig::test(),
            Gas::from_gas(PREPAID_GAS),
            1,
            Gas::from_gas(PREPAID_GAS),
            false,
        );
        let prepared = prepare(&ext, Arc::clone(&wasm_config), None, gas_counter, method);

        let result = run(prepared, &mut ext, &context, Arc::clone(&fees_config));

        match result {
            Ok(outcome) => {
                // The VM reports preparation/linking/trapping failures as
                // `Ok(outcome)` with `outcome.aborted = Some(...)`. Treating
                // these as success would hide every conformance failure, so
                // inspect `aborted` before anything else.
                if let Some(err) = &outcome.aborted {
                    eprintln!("call {}: ABORTED: {:?}", method, err);
                    process::exit(1);
                }
                storage_usage = outcome.storage_usage;
                match &outcome.return_data {
                    ReturnData::Value(v) => {
                        let hex: String = v.iter().map(|b| format!("{:02x}", b)).collect();
                        println!(
                            "call {}: return_hex={} gas={}",
                            method,
                            hex,
                            outcome.burnt_gas.as_gas()
                        );
                    }
                    ReturnData::None => {
                        println!(
                            "call {}: return=<none> gas={}",
                            method,
                            outcome.burnt_gas.as_gas()
                        );
                    }
                    ReturnData::ReceiptIndex(idx) => {
                        println!(
                            "call {}: return=receipt({}) gas={}",
                            method,
                            idx,
                            outcome.burnt_gas.as_gas()
                        );
                    }
                }
            }
            Err(err) => {
                eprintln!("call {} failed: {:?}", method, err);
                process::exit(1);
            }
        }
    }

    println!(
        "[near-vm-runner] {} methods executed successfully on real NEAR VM",
        config.methods.len()
    );
}
