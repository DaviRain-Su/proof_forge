//! No-runtime tests for manifest-bound artifact loading and exact account snapshots.

#[allow(dead_code)]
mod common;

use {
    common::*,
    serde_json::{json, Value},
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_pubkey::Pubkey,
    std::{
        fs,
        path::{Path, PathBuf},
        sync::atomic::{AtomicU64, Ordering},
    },
};

static NEXT_TEMP: AtomicU64 = AtomicU64::new(0);
const ZERO: &str = "0000000000000000000000000000000000000000000000000000000000000000";

struct TempRoot(PathBuf);

impl TempRoot {
    fn new(label: &str) -> Self {
        let id = NEXT_TEMP.fetch_add(1, Ordering::Relaxed);
        let path = std::env::temp_dir().join(format!(
            "proof-forge-solana-artifacts-{label}-{}-{id}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&path);
        fs::create_dir_all(&path).expect("create artifact temp root");
        Self(path)
    }

    fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempRoot {
    fn drop(&mut self) {
        let _ = fs::remove_dir_all(&self.0);
    }
}

fn sha256(bytes: &[u8]) -> String {
    hex::encode(Sha256::digest(bytes))
}

fn write_json(path: &Path, value: &Value) {
    let mut bytes = serde_json::to_vec_pretty(value).expect("render manifest");
    bytes.push(b'\n');
    fs::write(path, bytes).expect("write manifest");
}

fn write_artifact_fixture(root: &Path, name: &str) -> Value {
    let leaves = [
        (format!("{name}.idl.json"), b"{}\n".to_vec(), "materialized-base"),
        (format!("{name}.s"), b"; asm\n".to_vec(), "materialized-base"),
        (
            format!("{name}.sbpf-plan"),
            format!(".program {name}\n").into_bytes(),
            "materialized-base",
        ),
        (
            format!("{name}.so"),
            [b"\x7fELF".as_slice(), name.as_bytes()].concat(),
            "finalized-extra",
        ),
    ];
    let files: Vec<Value> = leaves
        .iter()
        .map(|(path, bytes, role)| {
            fs::write(root.join(path), bytes).expect("write artifact leaf");
            json!({
                "role": role,
                "path": path,
                "size": bytes.len(),
                "contentSha256": sha256(bytes),
            })
        })
        .collect();
    fs::write(root.join("evidence.json"), b"{}\n").expect("write evidence");
    let manifest = json!({
        "schemaVersion": "proof-forge.output.v1",
        "target": "solana",
        "codegenProfile": "solana-sbpf-elf-v1",
        "artifactProgramName": name,
        "sourceHash": ZERO,
        "semanticHash": ZERO,
        "buildIdentityDigest": ZERO,
        "planDigest": ZERO,
        "supportClaimDigest": ZERO,
        "engineeringRegistryRootDigest": ZERO,
        "outputSetDigest": ZERO,
        "evidenceSha256": sha256(b"{}\n"),
        "deployable": true,
        "files": files,
    });
    write_json(&root.join("manifest.json"), &manifest);
    manifest
}

#[test]
fn manifest_bytes_accept_exact_role_path_size_and_hash_without_reopen() {
    let root = TempRoot::new("accept");
    write_artifact_fixture(root.path(), "Bound");
    let bytes = read_manifest_leaf_bytes(
        root.path(),
        "Bound",
        "Bound.so",
        "finalized-extra",
    )
    .expect("exact manifest leaf");
    fs::remove_file(root.path().join("Bound.so")).expect("remove bound path after read");
    assert_eq!(bytes, b"\x7fELFBound");
}

#[test]
fn manifest_leaf_rejects_tamper_role_size_hash_and_cross_fixture() {
    let root = TempRoot::new("tamper");
    write_artifact_fixture(root.path(), "Bound");

    let so = root.path().join("Bound.so");
    let original = fs::read(&so).expect("read ELF");
    fs::write(&so, vec![b'x'; original.len()]).expect("same-size tamper");
    let error = read_manifest_leaf_bytes(
        root.path(),
        "Bound",
        "Bound.so",
        "finalized-extra",
    )
    .expect_err("same-size content tamper must fail");
    assert!(error.contains("contentSha256 mismatch"), "{error}");

    let mut manifest = write_artifact_fixture(root.path(), "Bound");
    let files = manifest["files"].as_array_mut().expect("files array");
    let so_descriptor = files
        .iter_mut()
        .find(|item| item["path"] == "Bound.so")
        .expect("ELF descriptor");
    so_descriptor["role"] = json!("materialized-base");
    write_json(&root.path().join("manifest.json"), &manifest);
    let error = read_manifest_leaf_bytes(
        root.path(),
        "Bound",
        "Bound.so",
        "finalized-extra",
    )
    .expect_err("wrong role must fail");
    assert!(error.contains("role mismatch"), "{error}");

    manifest = write_artifact_fixture(root.path(), "Bound");
    let files = manifest["files"].as_array_mut().expect("files array");
    let plan_descriptor = files
        .iter_mut()
        .find(|item| item["path"] == "Bound.sbpf-plan")
        .expect("plan descriptor");
    plan_descriptor["size"] = json!(999);
    write_json(&root.path().join("manifest.json"), &manifest);
    let error = read_manifest_leaf_bytes(
        root.path(),
        "Bound",
        "Bound.sbpf-plan",
        "materialized-base",
    )
    .expect_err("wrong size must fail");
    assert!(error.contains("size mismatch"), "{error}");

    write_artifact_fixture(root.path(), "Bound");
    let error = read_manifest_leaf_bytes(
        root.path(),
        "Other",
        "Other.so",
        "finalized-extra",
    )
    .expect_err("cross-fixture manifest must fail");
    assert!(error.contains("identity mismatch"), "{error}");
}

#[test]
fn exact_account_snapshot_covers_presence_and_all_account_bytes() {
    let present_key = Pubkey::new_unique();
    let absent_key = Pubkey::new_unique();
    let owner = Pubkey::new_unique();
    let mut account = Account::new(41, 3, &owner);
    account.data = vec![1, 2, 3];
    account.executable = true;
    account.rent_epoch = 77;

    let snapshot = snapshot_exact_accounts(
        &[present_key, absent_key],
        &[(present_key, Some(account.clone())), (absent_key, None)],
    )
    .expect("exact account snapshot");
    assert_eq!(snapshot.len(), 2);
    assert_eq!(snapshot[&absent_key], AccountPresenceSnapshot::Absent);
    assert_eq!(
        snapshot[&present_key],
        AccountPresenceSnapshot::Present(PresentAccountSnapshot {
            lamports: 41,
            data: vec![1, 2, 3],
            owner,
            executable: true,
            rent_epoch: 77,
        })
    );

    for mutation in 0..5 {
        let mut changed = account.clone();
        match mutation {
            0 => changed.lamports += 1,
            1 => changed.data[0] ^= 0xff,
            2 => changed.owner = Pubkey::new_unique(),
            3 => changed.executable = false,
            4 => changed.rent_epoch += 1,
            _ => unreachable!(),
        }
        let changed_snapshot = snapshot_exact_accounts(
            &[present_key, absent_key],
            &[(present_key, Some(changed)), (absent_key, None)],
        )
        .expect("changed account snapshot");
        assert_ne!(snapshot, changed_snapshot, "mutation {mutation} was missed");
    }

    let extra_key = Pubkey::new_unique();
    assert!(snapshot_exact_accounts(
        &[present_key],
        &[(present_key, Some(account.clone())), (extra_key, None)],
    )
    .expect_err("extra key must fail")
    .contains("unexpected account key"));
    assert!(snapshot_exact_accounts(&[present_key, absent_key], &[(present_key, Some(account))])
        .expect_err("missing explicit absence must fail")
        .contains("missing explicit present/absent"));
}
