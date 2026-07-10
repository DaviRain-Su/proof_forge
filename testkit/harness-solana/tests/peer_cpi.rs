//! PF-P2-03: focused Mollusk experiments for PeerOracleSum CPI.
use mollusk_svm::program::{
    create_program_account_loader_v2, create_program_account_loader_v3, loader_keys,
};
use mollusk_svm::Mollusk;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{AccountMeta, Instruction};
use std::path::{Path, PathBuf};

fn repo_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../..")
}

fn peer_paths() -> (PathBuf, PathBuf) {
    let deploy = repo_root().join("build/testkit/solana/peer-oracle-sum/sbpf-project/deploy");
    (
        deploy.join("proofforge-peer-oracle-sum"),
        deploy.join("proofforge-peer-oracle-sum.so"),
    )
}

/// Match harness program_id: first 32 file bytes (JSON text prefix) — legacy.
fn program_id_legacy(keypair_path: &Path) -> Address {
    let keypair_bytes = std::fs::read(keypair_path).unwrap();
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&keypair_bytes[..32]);
    Address::new_from_array(arr)
}

/// Correct JSON keypair pubkey (bytes 32..64 of the 64-byte secret).
fn program_id_json(keypair_path: &Path) -> Address {
    let bytes = std::fs::read(keypair_path).unwrap();
    let arr: Vec<u8> = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(arr.len(), 64);
    let mut pk = [0u8; 32];
    pk.copy_from_slice(&arr[32..64]);
    Address::new_from_array(pk)
}

#[test]
fn peer_direct_legacy_id() {
    let (stem, so) = peer_paths();
    assert!(so.exists(), "build peer first: {}", so.display());
    let kp = stem
        .parent()
        .unwrap()
        .join("proofforge-peer-oracle-sum-keypair.json");
    let pid = program_id_legacy(&kp);
    let mut mollusk = Mollusk::new(&pid, stem.to_str().unwrap());
    let result = mollusk.process_instruction(&Instruction::new_with_bytes(pid, &[], vec![]), &[]);
    eprintln!("legacy direct: raw={:?} rd={:?}", result.raw_result, result.return_data);
    assert!(result.raw_result.is_ok());
    assert_eq!(
        u64::from_le_bytes(result.return_data[..8].try_into().unwrap()),
        49
    );
}

#[test]
fn peer_direct_json_id() {
    let (stem, so) = peer_paths();
    assert!(so.exists());
    let kp = stem
        .parent()
        .unwrap()
        .join("proofforge-peer-oracle-sum-keypair.json");
    let pid = program_id_json(&kp);
    let mut mollusk = Mollusk::new(&pid, stem.to_str().unwrap());
    let result = mollusk.process_instruction(&Instruction::new_with_bytes(pid, &[], vec![]), &[]);
    eprintln!("json direct: raw={:?} rd={:?}", result.raw_result, result.return_data);
    assert!(result.raw_result.is_ok());
    assert_eq!(
        u64::from_le_bytes(result.return_data[..8].try_into().unwrap()),
        49
    );
}

#[test]
fn peer_as_cpi_target_v3_account() {
    let (stem, so) = peer_paths();
    assert!(so.exists());
    let kp = stem
        .parent()
        .unwrap()
        .join("proofforge-peer-oracle-sum-keypair.json");
    // Use unique host program and add peer
    let host = Address::new_unique();
    // Need a host ELF — use peer as host too for direct-only check of add_program
    let mut mollusk = Mollusk::new(&host, stem.to_str().unwrap());
    let peer = program_id_legacy(&kp);
    // Re-add under peer id
    mollusk.add_program(&peer, stem.to_str().unwrap());

    // Direct call to peer via add_program id
    let result = mollusk.process_instruction(
        &Instruction::new_with_bytes(peer, &[], vec![]),
        &[(peer, create_program_account_loader_v3(&peer))],
    );
    eprintln!("peer via add_program v3: raw={:?} rd={:?}", result.raw_result, result.return_data);
    assert!(result.raw_result.is_ok());
}

#[test]
fn peer_as_cpi_target_v2_account() {
    let (stem, so) = peer_paths();
    let elf = std::fs::read(&so).unwrap();
    let peer = Address::new_unique();
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(&peer, &loader_keys::LOADER_V2, &elf);
    let result = mollusk.process_instruction(
        &Instruction::new_with_bytes(peer, &[], vec![]),
        &[(peer, create_program_account_loader_v2(&elf))],
    );
    eprintln!("peer v2: raw={:?} rd={:?}", result.raw_result, result.return_data);
    assert!(result.raw_result.is_ok());
    assert_eq!(
        u64::from_le_bytes(result.return_data[..8].try_into().unwrap()),
        49
    );
}
