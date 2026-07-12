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
use near_vm_runner::logic::types::ReturnData;
use near_vm_runner::logic::VMContext;
use near_vm_runner::{prepare, run, ContractCode};
use std::env;
use std::fs;
use std::process;
use std::sync::Arc;

const PREPAID_GAS: u64 = 300_000_000_000_000; // 300 Tgas

fn make_context(storage_usage: StorageUsage) -> VMContext {
    let account_id: near_primitives_core::types::AccountId =
        "proof-forge.testnet".parse().unwrap();
    let caller: near_primitives_core::types::AccountId =
        "caller.testnet".parse().unwrap();
    VMContext {
        current_account_id: account_id,
        signer_account_id: caller.clone(),
        signer_account_pk: vec![0u8; 32],
        predecessor_account_id: caller.clone(),
        refund_to_account_id: caller,
        input: vec![].into(),
        promise_results: Arc::new([]),
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
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("Usage: near-vm-runner <wasm-file> <method1> [method2 ...]");
        process::exit(2);
    }
    let wasm_path = &args[1];
    let methods = &args[2..];

    let wasm = fs::read(wasm_path).unwrap_or_else(|e| {
        eprintln!("failed to read {}: {}", wasm_path, e);
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

    for method in methods {
        let context = make_context(storage_usage);
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
        methods.len()
    );
}
