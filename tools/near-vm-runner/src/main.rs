// near-vm-runner: execute ProofForge-generated NEAR Wasm on the real NEAR VM.
//
// STATUS: WORK IN PROGRESS — External trait implementation needs more methods.
//
// The real near-vm-runner requires a full External trait implementation
// (~20 methods: storage, trie, validators, promises, etc.).
// ProofForge's runtime/offline-host already provides NEAR execution
// via Wasmtime with NEAR host handlers.
//
// For NEAR runtime verification, use:
//   just near-offline-host-fuel
//   just near-offline-host-transaction
//   just near-compare-matrix-test
//
// This runner will provide stronger verification once the External trait
// is fully implemented — it uses the actual NEAR Protocol VM, not Wasmtime.

use std::env;
use std::process;

fn main() {
    eprintln!("near-vm-runner: WORK IN PROGRESS");
    eprintln!();
    eprintln!("The real near-vm-runner crate requires a full External trait");
    eprintln!("implementation (~20 methods). This is a structural placeholder.");
    eprintln!();
    eprintln!("For NEAR runtime verification, use:");
    eprintln!("  just near-offline-host-fuel");
    eprintln!("  just near-offline-host-transaction");
    eprintln!("  just near-compare-matrix-test");
    eprintln!();
    eprintln!("To complete this runner, implement the External trait from");
    eprintln!("near_vm_runner::logic with in-memory storage and promise tracking.");

    let _args: Vec<String> = env::args().collect();
    process::exit(3);
}