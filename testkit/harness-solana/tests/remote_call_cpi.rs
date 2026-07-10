//! PF-P2-03: RemoteCall.call_with_args → PeerOracleSum via Mollusk CPI.
use mollusk_svm::program::{create_program_account_loader_v3, loader_keys};
use mollusk_svm::Mollusk;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn program_id_legacy(keypair_path: &Path) -> Address {
    let keypair_bytes = std::fs::read(keypair_path).unwrap();
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&keypair_bytes[..32]);
    Address::new_from_array(arr)
}

fn system_program() -> Address {
    Address::from_str_const("11111111111111111111111111111111")
}

#[test]
fn remote_call_with_args_cpi_peer_returns_49() {
    let root = repo_root();
    let host_deploy = root.join("build/testkit/solana/remote-call/sbpf-project/deploy");
    let peer_deploy = root.join("build/testkit/solana/peer-oracle-sum/sbpf-project/deploy");
    let host_stem = host_deploy.join("proofforge-remote-call");
    let peer_stem = peer_deploy.join("proofforge-peer-oracle-sum");
    assert!(host_stem.with_extension("so").exists(), "need remote-call build");
    assert!(peer_stem.with_extension("so").exists(), "need peer build");

    let host_pid = program_id_legacy(&host_deploy.join("proofforge-remote-call-keypair.json"));
    let peer_pid = program_id_legacy(&peer_deploy.join("proofforge-peer-oracle-sum-keypair.json"));

    let mut mollusk = Mollusk::new(&host_pid, host_stem.to_str().unwrap());
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;
    mollusk.add_program(&peer_pid, peer_stem.to_str().unwrap());

    let marker = Address::new_unique();
    let payer = Address::new_unique();
    let system = system_program();
    let callee = Address::new_unique();

    let mut marker_account = Account::new(0, 8, &host_pid);
    let peer_account = create_program_account_loader_v3(&peer_pid);
    let mut system_account = Account::new(1, 0, &system);
    system_account.executable = true;
    let mut callee_account = Account::new(0, 0, &Address::new_unique());
    callee_account.executable = true;

    // initialize first
    let init = Instruction::new_with_bytes(
        host_pid,
        &[0u8],
        vec![
            AccountMeta::new(marker, false),
            AccountMeta::new(payer, true),
            AccountMeta::new_readonly(peer_pid, false),
            AccountMeta::new_readonly(system, false),
            AccountMeta::new_readonly(callee, false),
        ],
    );
    let accounts = [
        (marker, marker_account.clone()),
        (payer, Account::new(1_000_000_000, 0, &system)),
        (peer_pid, peer_account.clone()),
        (system, system_account.clone()),
        (callee, callee_account.clone()),
    ];
    let init_res = mollusk.process_instruction(&init, &accounts);
    eprintln!("init raw={:?}", init_res.raw_result);
    assert!(init_res.raw_result.is_ok(), "initialize failed");
    marker_account = init_res.get_account(&marker).unwrap().clone();

    // call_with_args tag=2
    let call = Instruction::new_with_bytes(
        host_pid,
        &[2u8],
        vec![
            AccountMeta::new(marker, false),
            AccountMeta::new(payer, true),
            AccountMeta::new_readonly(peer_pid, false),
            AccountMeta::new_readonly(system, false),
            AccountMeta::new_readonly(callee, false),
        ],
    );
    let accounts = [
        (marker, marker_account),
        (payer, Account::new(1_000_000_000, 0, &system)),
        (peer_pid, peer_account),
        (system, system_account),
        (callee, callee_account),
    ];
    let result = mollusk.process_instruction(&call, &accounts);
    eprintln!(
        "call_with_args raw={:?} rd={:?} cu={}",
        result.raw_result, result.return_data, result.compute_units_consumed
    );
    assert!(
        result.raw_result.is_ok(),
        "call_with_args failed: {:?}",
        result.raw_result
    );
    assert_eq!(result.return_data.len(), 8);
    let v = u64::from_le_bytes(result.return_data[..8].try_into().unwrap());
    assert_eq!(v, 49, "expected peer return 49");
}

#[test]
fn remote_call_with_args_cpi_peer_v2_loader() {
    let root = repo_root();
    let host_deploy = root.join("build/testkit/solana/remote-call/sbpf-project/deploy");
    let peer_deploy = root.join("build/testkit/solana/peer-oracle-sum/sbpf-project/deploy");
    let host_stem = host_deploy.join("proofforge-remote-call");
    let peer_so = peer_deploy.join("proofforge-peer-oracle-sum.so");
    let host_pid = program_id_legacy(&host_deploy.join("proofforge-remote-call-keypair.json"));
    let peer_elf = std::fs::read(&peer_so).unwrap();
    let peer_pid = Address::new_unique();

    let mut mollusk = Mollusk::new(&host_pid, host_stem.to_str().unwrap());
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;
    mollusk.add_program_with_loader_and_elf(&peer_pid, &loader_keys::LOADER_V2, &peer_elf);

    let marker = Address::new_unique();
    let payer = Address::new_unique();
    let system = system_program();
    let callee = Address::new_unique();
    let mut marker_account = Account::new(0, 8, &host_pid);
    let peer_account = mollusk_svm::program::create_program_account_loader_v2(&peer_elf);
    let mut system_account = Account::new(1, 0, &system);
    system_account.executable = true;
    let mut callee_account = Account::new(0, 0, &Address::new_unique());
    callee_account.executable = true;

    let init = Instruction::new_with_bytes(
        host_pid,
        &[0u8],
        vec![
            AccountMeta::new(marker, false),
            AccountMeta::new(payer, true),
            AccountMeta::new_readonly(peer_pid, false),
            AccountMeta::new_readonly(system, false),
            AccountMeta::new_readonly(callee, false),
        ],
    );
    let accounts = [
        (marker, marker_account.clone()),
        (payer, Account::new(1_000_000_000, 0, &system)),
        (peer_pid, peer_account.clone()),
        (system, system_account.clone()),
        (callee, callee_account.clone()),
    ];
    let init_res = mollusk.process_instruction(&init, &accounts);
    assert!(init_res.raw_result.is_ok());
    marker_account = init_res.get_account(&marker).unwrap().clone();

    let call = Instruction::new_with_bytes(
        host_pid,
        &[2u8],
        vec![
            AccountMeta::new(marker, false),
            AccountMeta::new(payer, true),
            AccountMeta::new_readonly(peer_pid, false),
            AccountMeta::new_readonly(system, false),
            AccountMeta::new_readonly(callee, false),
        ],
    );
    let accounts = [
        (marker, marker_account),
        (payer, Account::new(1_000_000_000, 0, &system)),
        (peer_pid, peer_account),
        (system, system_account),
        (callee, callee_account),
    ];
    let result = mollusk.process_instruction(&call, &accounts);
    eprintln!(
        "v2 call_with_args raw={:?} rd={:?}",
        result.raw_result, result.return_data
    );
    assert!(result.raw_result.is_ok(), "{:?}", result.raw_result);
    assert_eq!(
        u64::from_le_bytes(result.return_data[..8].try_into().unwrap()),
        49
    );
}
