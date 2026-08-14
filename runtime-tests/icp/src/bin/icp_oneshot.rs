//! Engineering oneshot: install StateCell.wasm into PocketIC, init/update/query.
//!
//! Honesty: not mainnet, not formal, not ordinary `just ci`. Requires
//! `POCKET_IC_BIN` (PocketIC server 15.0.0) and a product artifact dir with
//! `StateCell.wasm`.
//!
//! Exit: 0 ok · 2 skip/missing tools · 1 failure.

use candid::{Decode, Encode, Principal};
use pocket_ic::PocketIc;
use std::env;
use std::fs;
use std::path::PathBuf;
use std::process::ExitCode;

fn skip(msg: &str) -> ExitCode {
    eprintln!("icp-oneshot: skipped: {msg}");
    ExitCode::from(2)
}

fn fail(msg: &str) -> ExitCode {
    eprintln!("icp-oneshot: FAIL: {msg}");
    ExitCode::from(1)
}

fn artifact_dir() -> Result<PathBuf, String> {
    if let Ok(p) = env::var("PF_ICP_ARTIFACT_DIR") {
        return Ok(PathBuf::from(p));
    }
    if let Some(a) = env::args().nth(1) {
        return Ok(PathBuf::from(a));
    }
    Err("set PF_ICP_ARTIFACT_DIR or pass artifact dir as argv[1]".into())
}

fn main() -> ExitCode {
    eprintln!("icp-oneshot: engineering PocketIC StateCell gate (not formal/mainnet)");

    match env::var("POCKET_IC_BIN") {
        Ok(p) if PathBuf::from(&p).is_file() => {
            eprintln!("icp-oneshot: POCKET_IC_BIN={p}");
        }
        Ok(p) => return skip(&format!("POCKET_IC_BIN not a file: {p}")),
        Err(_) => {
            return skip("POCKET_IC_BIN unset (install PocketIC server 15.0.0; re-run)");
        }
    }

    let dir = match artifact_dir() {
        Ok(d) => d,
        Err(e) => return skip(&e),
    };
    let wasm_path = dir.join("StateCell.wasm");
    if !wasm_path.is_file() {
        return skip(&format!("missing {}", wasm_path.display()));
    }
    let wasm = match fs::read(&wasm_path) {
        Ok(b) => b,
        Err(e) => return fail(&format!("read wasm: {e}")),
    };
    if wasm.len() < 8 || &wasm[0..4] != b"\0asm" {
        return fail("StateCell.wasm missing Wasm magic");
    }

    let pic = PocketIc::new();
    let canister_id = pic.create_canister();
    pic.add_cycles(canister_id, 2_000_000_000_000);

    // candid install arg: single nat64 initial = 7
    let init_arg = match Encode!(&7u64) {
        Ok(b) => b,
        Err(e) => return fail(&format!("encode init: {e}")),
    };
    pic.install_canister(canister_id, wasm, init_arg, None);

    // update increment(delta=3) → expect 10
    let inc_arg = match Encode!(&3u64) {
        Ok(b) => b,
        Err(e) => return fail(&format!("encode increment: {e}")),
    };
    let reply = match pic.update_call(canister_id, Principal::anonymous(), "increment", inc_arg)
    {
        Ok(r) => r,
        Err(e) => return fail(&format!("update increment rejected: {e:?}")),
    };
    let after_inc: u64 = match Decode!(&reply, u64) {
        Ok(v) => v,
        Err(e) => return fail(&format!("decode increment reply: {e}")),
    };
    if after_inc != 10 {
        return fail(&format!("increment: want 10 got {after_inc}"));
    }

    // query get() → 10 (zero candid args)
    let get_arg = match Encode!() {
        Ok(b) => b,
        Err(e) => return fail(&format!("encode get: {e}")),
    };
    let reply = match pic.query_call(canister_id, Principal::anonymous(), "get", get_arg) {
        Ok(r) => r,
        Err(e) => return fail(&format!("query get rejected: {e:?}")),
    };
    let got: u64 = match Decode!(&reply, u64) {
        Ok(v) => v,
        Err(e) => return fail(&format!("decode get reply: {e}")),
    };
    if got != 10 {
        return fail(&format!("get: want 10 got {got}"));
    }

    eprintln!("icp-oneshot: ok (init=7, increment(+3)=10, get=10)");
    ExitCode::SUCCESS
}
