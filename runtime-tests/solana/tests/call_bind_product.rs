//! ADR-0053 Wave 3 product-path generic call-bind Mollusk closure.
//!
//! `CallBindCaller` is built with an explicit `proof-forge.call-bind.v1`
//! table. Its outer roles are caller state, bound callee state, and executable
//! callee program. `CallBindCallee` is independently product-built, so success
//! proves that the generic method discriminator, AccountMeta, AccountInfo
//! range (including the program account), executable/rent fields, and CPI
//! failure propagation agree with the Solana runtime. The caller Plan also
//! retains the exact inspected local callee OutputSet/ELF identity; this is not
//! a claim that the runtime program account proves those ELF bytes.

#[allow(dead_code)]
mod common;

use {
    common::{
        assert_failure_preserves_exact_accounts, instruction_data, instruction_discriminator,
        read_manifest_leaf_bytes, single_field, snapshot_exact_accounts, state_account, state_data,
        ASSERTION_FAILED, CHECK_OR_UNKNOWN,
    },
    mollusk_svm::{program::create_program_account_loader_v3, result::Check, Mollusk},
    sha2::{Digest, Sha256},
    solana_account::Account,
    solana_instruction::{AccountMeta, Instruction},
    solana_program_error::ProgramError,
    solana_pubkey::Pubkey,
    std::{env, fs, path::PathBuf},
};

const CALLER_NAME: &str = "CallBindCaller";
const CALLEE_NAME: &str = "CallBindCallee";
const MATERIALIZED_BASE: &str = "materialized-base";
const FINALIZED_EXTRA: &str = "finalized-extra";

fn fixed_key(byte: u8) -> Pubkey {
    Pubkey::new_from_array([byte; 32])
}

fn caller_id() -> Pubkey {
    fixed_key(0x42)
}

fn callee_id() -> Pubkey {
    fixed_key(0x43)
}

fn caller_output() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_CALL_BIND_CALLER_OUT")
            .expect("PROOF_FORGE_CALL_BIND_CALLER_OUT must point at CallBindCaller OutputSet"),
    )
}

fn callee_output() -> PathBuf {
    PathBuf::from(
        env::var("PROOF_FORGE_CALL_BIND_CALLEE_OUT")
            .expect("PROOF_FORGE_CALL_BIND_CALLEE_OUT must point at CallBindCallee OutputSet"),
    )
}

fn product_elf(output: &PathBuf, name: &str) -> Vec<u8> {
    read_manifest_leaf_bytes(output, name, &format!("{name}.so"), FINALIZED_EXTRA)
        .unwrap_or_else(|error| panic!("{name} ELF binding failed: {error}"))
}

fn make_mollusk() -> Mollusk {
    let caller_elf = product_elf(&caller_output(), CALLER_NAME);
    let callee_elf = product_elf(&callee_output(), CALLEE_NAME);
    let mut mollusk = Mollusk::default();
    mollusk.add_program_with_loader_and_elf(
        &caller_id(),
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &caller_elf,
    );
    mollusk.add_program_with_loader_and_elf(
        &callee_id(),
        &mollusk_svm::program::loader_keys::LOADER_V3,
        &callee_elf,
    );
    mollusk
}

fn caller_state(value: u64) -> Account {
    state_account(
        &caller_id(),
        state_data(&single_field("value"), true, &[value]),
    )
}

fn callee_state(value: u64) -> Account {
    state_account(
        &callee_id(),
        state_data(&single_field("count"), true, &[value]),
    )
}

#[derive(Clone)]
struct InvokeCase {
    caller_state_key: Pubkey,
    callee_state_key: Pubkey,
    callee_program_key: Pubkey,
    metas: Vec<AccountMeta>,
    accounts: Vec<(Pubkey, Account)>,
}

impl InvokeCase {
    fn new(caller_value: u64, callee_value: u64) -> Self {
        let caller_state_key = fixed_key(0x20);
        let callee_state_key = fixed_key(0x21);
        let callee_program_key = callee_id();
        Self {
            caller_state_key,
            callee_state_key,
            callee_program_key,
            metas: vec![
                AccountMeta::new(caller_state_key, false),
                AccountMeta::new(callee_state_key, false),
                AccountMeta::new_readonly(callee_program_key, false),
            ],
            accounts: vec![
                (caller_state_key, caller_state(caller_value)),
                (callee_state_key, callee_state(callee_value)),
                (
                    callee_program_key,
                    create_program_account_loader_v3(&callee_program_key),
                ),
            ],
        }
    }

    fn instruction(&self, delta: u64) -> Instruction {
        Instruction::new_with_bytes(
            caller_id(),
            &instruction_data(&instruction_discriminator("invoke", 1), &[delta]),
            self.metas.clone(),
        )
    }

    fn account_mut(&mut self, key: Pubkey) -> &mut Account {
        &mut self
            .accounts
            .iter_mut()
            .find(|(candidate, _)| *candidate == key)
            .unwrap_or_else(|| panic!("missing InvokeCase account {key}"))
            .1
    }
}

#[test]
fn product_artifacts_pin_outer_join_surface() {
    let output = caller_output();
    let plan: serde_json::Value = serde_json::from_slice(
        &read_manifest_leaf_bytes(
            &output,
            CALLER_NAME,
            &format!("{CALLER_NAME}.cpi-plan.json"),
            MATERIALIZED_BASE,
        )
        .expect("caller Plan binding"),
    )
    .expect("caller Plan JSON");
    let idl: serde_json::Value = serde_json::from_slice(
        &read_manifest_leaf_bytes(
            &output,
            CALLER_NAME,
            &format!("{CALLER_NAME}.idl.json"),
            MATERIALIZED_BASE,
        )
        .expect("caller IDL binding"),
    )
    .expect("caller IDL JSON");
    let roles = plan["accountRoles"].as_array().expect("Plan accountRoles");
    assert_eq!(roles.len(), 3, "Plan must expose the runtime role table");
    assert_eq!(roles[0]["name"], "state");
    assert_eq!(roles[0]["keyPolicy"]["kind"], "state");
    assert_eq!(roles[1]["name"], "callee_state");
    assert_eq!(roles[1]["keyPolicy"]["kind"], "callBindAccount");
    assert_eq!(roles[1]["keyPolicy"]["pubkey"], "21".repeat(32));
    assert_eq!(roles[1]["keyPolicy"]["signer"], false);
    assert_eq!(roles[1]["keyPolicy"]["writable"], true);
    assert_eq!(roles[1]["constraint"]["data"]["kind"], "notRead");
    assert_eq!(roles[1]["constraint"]["executable"], "forbidden");
    assert_eq!(roles[2]["keyPolicy"]["kind"], "callBindProgram");
    assert_eq!(roles[2]["keyPolicy"]["programId"], "43".repeat(32));
    let callee_output = callee_output();
    let callee_manifest: serde_json::Value = serde_json::from_slice(
        &fs::read(callee_output.join("manifest.json")).expect("callee manifest bytes"),
    )
    .expect("callee manifest JSON");
    let callee_elf = product_elf(&callee_output, CALLEE_NAME);
    let callee_elf_sha256 = hex::encode(Sha256::digest(&callee_elf));
    let output_identity = &roles[2]["callBindOutputIdentity"];
    assert_eq!(
        output_identity["sourceHash"],
        format!(
            "sha256:{}",
            callee_manifest["sourceHash"]
                .as_str()
                .expect("callee manifest sourceHash")
        )
    );
    assert_eq!(
        output_identity["semanticHash"],
        format!(
            "sha256:{}",
            callee_manifest["semanticHash"]
                .as_str()
                .expect("callee manifest semanticHash")
        )
    );
    assert_eq!(
        output_identity["artifactSha256"],
        format!("sha256:{callee_elf_sha256}")
    );
    assert_eq!(roles[2]["constraint"]["data"]["kind"], "notRead");
    assert_eq!(roles[2]["constraint"]["executable"], "required");
    assert_eq!(plan["cpiSites"].as_array().map(Vec::len), Some(0));
    assert_eq!(idl["cpiSites"].as_array().map(Vec::len), Some(0));
    let handlers = plan["handlers"].as_array().expect("Plan handlers");
    let instructions = idl["instructions"].as_array().expect("IDL instructions");
    assert_eq!(instructions.len(), handlers.len());
    for (handler_index, (handler, instruction)) in handlers.iter().zip(instructions).enumerate() {
        let uses = handler["accountUses"].as_array().expect("accountUses");
        let accounts = instruction["accounts"].as_array().expect("IDL accounts");
        assert_eq!(uses.len(), 3, "handler {handler_index} Plan role count");
        assert_eq!(accounts.len(), 3, "handler {handler_index} IDL role count");
        for role_index in 0..3 {
            assert_eq!(uses[role_index]["roleId"], role_index);
            assert_eq!(uses[role_index]["position"], role_index);
            assert_eq!(accounts[role_index]["roleId"], role_index);
            assert_eq!(accounts[role_index]["position"], role_index);
            assert_eq!(accounts[role_index]["name"], roles[role_index]["name"]);
            assert_eq!(
                accounts[role_index]["keyPolicy"], roles[role_index]["keyPolicy"],
                "handler {handler_index} role {role_index} key policy projection"
            );
            assert_eq!(
                accounts[role_index]["constraint"], roles[role_index]["constraint"],
                "handler {handler_index} role {role_index} constraint projection"
            );
            for privilege in ["outerSigner", "outerWritable"] {
                assert_eq!(
                    accounts[role_index][privilege], uses[role_index][privilege],
                    "handler {handler_index} role {role_index} {privilege} projection"
                );
            }
        }
    }

    let assembly = read_manifest_leaf_bytes(
        &output,
        CALLER_NAME,
        &format!("{CALLER_NAME}.s"),
        MATERIALIZED_BASE,
    )
    .expect("caller assembly binding");
    let text = std::str::from_utf8(&assembly).expect("caller assembly UTF-8");
    assert!(text.contains("call-bind outer AccountInfo join"));
    assert!(text.contains("call-bind AccountInfos startLocal=1 n=2"));
    assert!(text.contains("call-bind callee program local=2 exact program id executable=1"));
    assert!(text.contains("ROLE_FLAGS (signer|writable<<8|executable<<16)"));
    assert!(text.contains("ROLE_RENT"));
    assert!(text.contains("call sol_invoke_signed_c"));
}

#[test]
fn bound_call_updates_callee_and_commits_caller_source_order() {
    let mollusk = make_mollusk();
    let case = InvokeCase::new(10, 7);
    let result = mollusk.process_and_validate_instruction(
        &case.instruction(5),
        &case.accounts,
        &[Check::success(), Check::return_data(&13u64.to_le_bytes())],
    );
    let post_caller = result
        .resulting_accounts
        .iter()
        .find(|(key, _)| *key == case.caller_state_key)
        .map(|(_, account)| account)
        .expect("post caller state");
    let post_callee = result
        .resulting_accounts
        .iter()
        .find(|(key, _)| *key == case.callee_state_key)
        .map(|(_, account)| account)
        .expect("post callee state");
    assert_eq!(
        post_caller.data,
        state_data(&single_field("value"), true, &[13]),
        "caller must commit pre-CPI +1 and post-CPI +2"
    );
    assert_eq!(
        post_callee.data,
        state_data(&single_field("count"), true, &[12]),
        "callee must receive the exact UInt64 argument and mutate once"
    );

    let mut expected = case.accounts.clone();
    expected[0].1.data = state_data(&single_field("value"), true, &[13]);
    expected[1].1.data = state_data(&single_field("count"), true, &[12]);
    let keys: Vec<Pubkey> = expected.iter().map(|(key, _)| *key).collect();
    let expected_observed: Vec<(Pubkey, Option<Account>)> = expected
        .iter()
        .map(|(key, account)| (*key, Some(account.clone())))
        .collect();
    let actual_observed: Vec<(Pubkey, Option<Account>)> = result
        .resulting_accounts
        .iter()
        .map(|(key, account)| (*key, Some(account.clone())))
        .collect();
    assert_eq!(
        snapshot_exact_accounts(&keys, &actual_observed).expect("actual success snapshot"),
        snapshot_exact_accounts(&keys, &expected_observed).expect("expected success snapshot"),
        "success may change only the two state data payloads"
    );
}

#[test]
fn wrong_bound_account_key_fails_before_cpi_and_rolls_back() {
    let mollusk = make_mollusk();
    let mut case = InvokeCase::new(10, 7);
    let wrong = fixed_key(0x22);
    case.metas[1] = AccountMeta::new(wrong, false);
    case.accounts[1].0 = wrong;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn bound_privilege_mismatch_fails_before_cpi_and_rolls_back() {
    let mollusk = make_mollusk();
    let mut case = InvokeCase::new(10, 7);
    case.metas[1] = AccountMeta::new_readonly(case.callee_state_key, false);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn bound_signer_mismatch_fails_before_cpi_and_rolls_back() {
    let mollusk = make_mollusk();
    let mut case = InvokeCase::new(10, 7);
    case.metas[1] = AccountMeta::new(case.callee_state_key, true);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn nonexecutable_bound_program_fails_before_cpi_and_rolls_back() {
    let mollusk = make_mollusk();
    let mut case = InvokeCase::new(10, 7);
    case.account_mut(case.callee_program_key).executable = false;
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn wrong_bound_program_key_fails_before_cpi_and_rolls_back() {
    let mollusk = make_mollusk();
    let mut case = InvokeCase::new(10, 7);
    let wrong = fixed_key(0x44);
    case.metas[2] = AccountMeta::new_readonly(wrong, false);
    case.accounts[2] = (wrong, create_program_account_loader_v3(&wrong));
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(5),
        &case.accounts,
        Check::err(ProgramError::Custom(CHECK_OR_UNKNOWN)),
    );
}

#[test]
fn inner_failure_rolls_back_caller_prewrite_and_callee_accounts() {
    let mollusk = make_mollusk();
    let case = InvokeCase::new(10, 7);
    assert_failure_preserves_exact_accounts(
        &mollusk,
        &case.instruction(100),
        &case.accounts,
        Check::err(ProgramError::Custom(ASSERTION_FAILED)),
    );
}
