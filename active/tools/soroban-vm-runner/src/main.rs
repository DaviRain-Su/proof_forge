// soroban-vm-runner: execute ProofForge-generated Soroban Wasm on the real
// Soroban Env Host.
//
// STATUS: NOT YET FUNCTIONAL.
//
// ProofForge's current Soroban bridge uses a custom simplified host ABI
// (_get, _put, set_return_data, require_auth_for_args, invoke_contract,
// log_from_slice) plus retained NEAR-style imports (read_register, input,
// signer_account_id, block_timestamp, sha256).
//
// The real Soroban Env Host uses a completely different import set based on
// Val objects, ScVal types, and object handles — not raw pointer/length host
// calls. ProofForge's Soroban Wasm cannot execute on the real Soroban Env
// Host until the bridge is migrated to real Soroban Env ABI.
//
// This runner is a placeholder that documents the gap. When the Soroban Env
// ABI migration is complete, this runner will:
// 1. Load .wasm produced by `proof-forge build --target wasm-stellar-soroban`
// 2. Create a soroban-env-host Env with storage
// 3. Register the contract
// 4. Call initialize, increment, get
// 5. Verify state transitions
//
// For now, use `just soroban-counter-offline` (offline-host Wasmtime) for
// runtime verification — it implements ProofForge's custom bridge ABI.

use std::env;
use std::process;

fn main() {
    eprintln!("soroban-vm-runner: NOT YET FUNCTIONAL");
    eprintln!();
    eprintln!("ProofForge's Soroban Wasm uses a custom bridge ABI (_get/_put/");
    eprintln!("set_return_data/require_auth_for_args/invoke_contract) that does");
    eprintln!("not match the real Soroban Env Host import set.");
    eprintln!();
    eprintln!("For runtime verification, use:");
    eprintln!("  just soroban-counter-offline  (offline-host Wasmtime)");
    eprintln!();
    eprintln!("This runner will be functional after the Soroban Env ABI migration");
    eprintln!("is complete (replacing NEAR hybrid imports with real Soroban Env");
    eprintln!("functions: get_caller, get_ledger_timestamp, sha256_hash, etc.)");

    let _args: Vec<String> = env::args().collect();
    process::exit(3);
}