use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

use anyhow::{bail, ensure, Context as _, Result};
use proof_forge_testkit_core::{
    assert_artifact_expectations, ArtifactOutput, CallOutcome, ChainHarness, HarnessRun,
    ScenarioCase, Step,
};
use revm::{
    bytecode::Bytecode,
    context::TxEnv,
    database::{CacheDB, EmptyDB},
    primitives::{Address, Bytes, TxKind, U256},
    state::AccountInfo,
    Context, ExecuteCommitEvm, MainBuilder, MainContext,
};
use serde::Deserialize;

const CONTRACT_ADDRESS: Address = Address::with_last_byte(0xC0);
const CALLER_ADDRESS: Address = Address::with_last_byte(0xA1);
const CALL_GAS_LIMIT: u64 = 1_000_000;

pub struct EvmHarness;

impl EvmHarness {
    pub fn new() -> Self {
        Self
    }
}

impl Default for EvmHarness {
    fn default() -> Self {
        Self::new()
    }
}

impl ChainHarness for EvmHarness {
    fn target_id(&self) -> &'static str {
        "evm"
    }

    fn run_scenario(&self, case: &ScenarioCase, repo_root: &Path) -> Result<HarnessRun> {
        if case.manifest.scenario.fixture == "value-vault" {
            let cast = cast_tool(repo_root)?;
            if !command_available(&cast) {
                return Ok(HarnessRun::skipped(
                    "cast not on PATH (set CAST or install Foundry)",
                ));
            }
        }

        let artifact = build_fixture(case, repo_root)?;
        let mut artifacts = vec![
            ArtifactOutput {
                name: "bytecode",
                path: &artifact.bytecode_path,
            },
            ArtifactOutput {
                name: "metadata",
                path: &artifact.metadata_path,
            },
            ArtifactOutput {
                name: "yul",
                path: &artifact.yul_path,
            },
            ArtifactOutput {
                name: "init-code",
                path: &artifact.init_code_path,
            },
            ArtifactOutput {
                name: "deploy-manifest",
                path: &artifact.deploy_manifest_path,
            },
        ];
        if let Some(ref path) = artifact.contract_spec_path {
            artifacts.push(ArtifactOutput {
                name: "contract-spec",
                path: path,
            });
        }
        if let Some(ref path) = artifact.evm_abi_path {
            artifacts.push(ArtifactOutput {
                name: "evm-abi",
                path: path,
            });
        }
        assert_artifact_expectations(case, self.target_id(), repo_root, &artifacts)?;
        let selectors = load_selectors(&artifact.metadata_path)?;
        let bytecode = read_bytecode(&artifact.bytecode_path)?;

        let mut db = CacheDB::new(EmptyDB::new());
        db.insert_account_info(
            CONTRACT_ADDRESS,
            AccountInfo::from_bytecode(Bytecode::new_raw(Bytes::from(bytecode))),
        );
        db.insert_account_info(CALLER_ADDRESS, AccountInfo::default());

        let mut evm = Context::mainnet().with_db(db).build_mainnet();
        let mut outcomes = Vec::new();
        let mut sequence = 1u32;
        let mut nonce = 0u64;

        for step in &case.manifest.steps {
            let selector = selectors
                .get(&step.call)
                .with_context(|| {
                    format!(
                        "EVM metadata for fixture `{}` does not contain call `{}`",
                        case.manifest.scenario.fixture, step.call
                    )
                })?
                .clone();
            for _ in 0..step.repeat.unwrap_or(1) {
                let calldata = calldata_for_step(&selector, step)?;
                let tx = TxEnv::builder()
                    .caller(CALLER_ADDRESS)
                    .gas_limit(CALL_GAS_LIMIT)
                    .gas_price(0)
                    .kind(TxKind::Call(CONTRACT_ADDRESS))
                    .value(U256::ZERO)
                    .data(Bytes::from(calldata))
                    .nonce(nonce)
                    .build()
                    .context("failed to build EVM transaction")?;
                nonce += 1;

                let result = evm
                    .transact_commit(tx)
                    .with_context(|| format!("EVM call `{}` failed before execution", step.call))?;
                let gas_used = result.tx_gas_used();
                let outcome = match result {
                    revm::context_interface::result::ExecutionResult::Success {
                        output, ..
                    } => {
                        outcome_from_output(sequence, &step.call, output.data().as_ref(), gas_used)
                    }
                    revm::context_interface::result::ExecutionResult::Revert { output, .. } => {
                        outcome_from_revert(sequence, &step.call, output.as_ref(), gas_used)
                    }
                    revm::context_interface::result::ExecutionResult::Halt { reason, .. } => {
                        bail!("EVM call `{}` halted: {reason}", step.call);
                    }
                };
                outcomes.push(outcome);
                sequence += 1;
            }
        }

        Ok(HarnessRun::passed(outcomes))
    }
}

struct EvmFixtureArtifact {
    bytecode_path: PathBuf,
    metadata_path: PathBuf,
    yul_path: PathBuf,
    init_code_path: PathBuf,
    deploy_manifest_path: PathBuf,
    contract_spec_path: Option<PathBuf>,
    evm_abi_path: Option<PathBuf>,
}

fn build_fixture(case: &ScenarioCase, repo_root: &Path) -> Result<EvmFixtureArtifact> {
    match case.manifest.scenario.fixture.as_str() {
        "counter" => build_counter_fixture(case, repo_root),
        "value-vault" => build_value_vault_fixture(case, repo_root),
        "error-ref" => build_error_ref_fixture(repo_root),
        "role-gated-token" => build_contract_source_fixture_by_name(case, repo_root, "RoleGatedToken"),
        "staking-vault" => build_contract_source_fixture_by_name(case, repo_root, "StakingVault"),
        fixture => bail!("EVM testkit harness does not support fixture `{fixture}` yet"),
    }
}

fn build_counter_fixture(case: &ScenarioCase, repo_root: &Path) -> Result<EvmFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/evm");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let build = Command::new("lake")
        .current_dir(repo_root)
        .args(["build", "proof-forge"])
        .output()
        .context("failed to build proof-forge executable")?;
    if !build.status.success() {
        bail!(
            "lake build proof-forge failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&build.stdout),
            String::from_utf8_lossy(&build.stderr)
        );
    }

    let bytecode_path = out_dir.join("Counter.bin");
    let yul_path = out_dir.join("Counter.yul");
    let metadata_path = out_dir.join("Counter.proof-forge-artifact.json");
    let init_code_path = out_dir.join("Counter.init.bin");
    let deploy_manifest_path = out_dir.join("Counter.proof-forge-deploy.json");
    if let Some(source_path) = scenario_source(case, repo_root)? {
        build_contract_source_fixture(
            case,
            repo_root,
            &source_path,
            &bytecode_path,
            &yul_path,
            &metadata_path,
        )?;
        ensure_evm_outputs(
            "Counter",
            &bytecode_path,
            &metadata_path,
            &init_code_path,
            &deploy_manifest_path,
        )?;
        return Ok(EvmFixtureArtifact {
            bytecode_path,
            metadata_path,
            yul_path,
            init_code_path,
            deploy_manifest_path,
            contract_spec_path: None,
            evm_abi_path: None,
        });
    }

    let proof_forge = repo_root.join(".lake/build/bin/proof-forge");
    let output = Command::new(&proof_forge)
        .current_dir(repo_root)
        .args([
            "emit",
            "--target",
            "evm",
            "--fixture",
            "counter",
            "--format",
            "bytecode",
            "--yul-output",
            path_str(&yul_path)?,
            "--artifact-output",
            path_str(&metadata_path)?,
            "-o",
            path_str(&bytecode_path)?,
        ])
        .output()
        .with_context(|| format!("failed to run `{}`", proof_forge.display()))?;
    if !output.status.success() {
        bail!(
            "Counter EVM bytecode emission failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    ensure_evm_outputs(
        "Counter",
        &bytecode_path,
        &metadata_path,
        &init_code_path,
        &deploy_manifest_path,
    )?;

    Ok(EvmFixtureArtifact {
        bytecode_path,
        metadata_path,
        yul_path,
        init_code_path,
        deploy_manifest_path,
        contract_spec_path: None,
        evm_abi_path: None,
    })
}

fn build_value_vault_fixture(case: &ScenarioCase, repo_root: &Path) -> Result<EvmFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/evm/value-vault");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let build = Command::new("lake")
        .current_dir(repo_root)
        .args(["build", "proof-forge"])
        .output()
        .context("failed to build proof-forge executable")?;
    if !build.status.success() {
        bail!(
            "lake build proof-forge failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&build.stdout),
            String::from_utf8_lossy(&build.stderr)
        );
    }

    let bytecode_path = out_dir.join("ValueVault.bin");
    let yul_path = out_dir.join("ValueVault.yul");
    let metadata_path = out_dir.join("ValueVault.proof-forge-artifact.json");
    let init_code_path = out_dir.join("ValueVault.init.bin");
    let deploy_manifest_path = out_dir.join("ValueVault.proof-forge-deploy.json");
    if let Some(source_path) = scenario_source(case, repo_root)? {
        build_contract_source_fixture(
            case,
            repo_root,
            &source_path,
            &bytecode_path,
            &yul_path,
            &metadata_path,
        )?;
        ensure_evm_outputs(
            "ValueVault",
            &bytecode_path,
            &metadata_path,
            &init_code_path,
            &deploy_manifest_path,
        )?;
        return Ok(EvmFixtureArtifact {
            bytecode_path,
            metadata_path,
            yul_path,
            init_code_path,
            deploy_manifest_path,
            contract_spec_path: None,
            evm_abi_path: None,
        });
    }

    let proof_forge = repo_root.join(".lake/build/bin/proof-forge");
    let cast = cast_tool(repo_root)?;
    let mut emit = Command::new(&proof_forge);
    emit.current_dir(repo_root)
        .args([
            "emit",
            "--target",
            "evm",
            "--fixture",
            "value-vault",
            "--format",
            "bytecode",
            "--yul-output",
            path_str(&yul_path)?,
            "--artifact-output",
            path_str(&metadata_path)?,
            "-o",
            path_str(&bytecode_path)?,
        ])
        .args(["--cast", cast.as_str()]);
    let output = emit
        .output()
        .with_context(|| format!("failed to run `{}`", proof_forge.display()))?;
    if !output.status.success() {
        bail!(
            "ValueVault EVM bytecode emission failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    ensure_evm_outputs(
        "ValueVault",
        &bytecode_path,
        &metadata_path,
        &init_code_path,
        &deploy_manifest_path,
    )?;

    Ok(EvmFixtureArtifact {
        bytecode_path,
        metadata_path,
        yul_path,
        init_code_path,
        deploy_manifest_path,
        contract_spec_path: None,
        evm_abi_path: None,
    })
}

fn build_contract_source_fixture(
    case: &ScenarioCase,
    repo_root: &Path,
    source_path: &Path,
    bytecode_path: &Path,
    yul_path: &Path,
    metadata_path: &Path,
) -> Result<()> {
    let cast = cast_tool(repo_root)?;
    if !command_available(&cast) {
        bail!(
            "cast not available for `{}`; set CAST or install Foundry",
            cast
        );
    }
    let output = Command::new("lake")
        .current_dir(repo_root)
        .args([
            "env",
            "proof-forge",
            "build",
            "--target",
            "evm",
            "--root",
            ".",
            "--cast",
            cast.as_str(),
            "-o",
            path_str(bytecode_path)?,
            "--yul-output",
            path_str(yul_path)?,
            "--artifact-output",
            path_str(metadata_path)?,
            path_str(source_path)?,
        ])
        .output()
        .with_context(|| {
            format!(
                "failed to build EVM contract_source for scenario `{}`",
                case.manifest.scenario.name
            )
        })?;
    if !output.status.success() {
        bail!(
            "EVM contract_source build failed for scenario `{}`\nstdout:\n{}\nstderr:\n{}",
            case.manifest.scenario.name,
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(())
}

fn ensure_evm_outputs(
    fixture_name: &str,
    bytecode_path: &Path,
    metadata_path: &Path,
    init_code_path: &Path,
    deploy_manifest_path: &Path,
) -> Result<()> {
    ensure!(
        bytecode_path.exists(),
        "{fixture_name} EVM bytecode emission did not create `{}`",
        bytecode_path.display()
    );
    ensure!(
        metadata_path.exists(),
        "{fixture_name} EVM bytecode emission did not create `{}`",
        metadata_path.display()
    );
    ensure!(
        init_code_path.exists(),
        "{fixture_name} EVM bytecode emission did not create `{}`",
        init_code_path.display()
    );
    ensure!(
        deploy_manifest_path.exists(),
        "{fixture_name} EVM bytecode emission did not create `{}`",
        deploy_manifest_path.display()
    );
    Ok(())
}

fn build_contract_source_fixture_by_name(
    case: &ScenarioCase,
    repo_root: &Path,
    contract_name: &str,
) -> Result<EvmFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/evm");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let build = Command::new("lake")
        .current_dir(repo_root)
        .args(["build", "proof-forge"])
        .output()
        .context("failed to build proof-forge executable")?;
    if !build.status.success() {
        bail!(
            "lake build proof-forge failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&build.stdout),
            String::from_utf8_lossy(&build.stderr)
        );
    }

    let bytecode_path = out_dir.join(format!("{}.bin", contract_name));
    let yul_path = out_dir.join(format!("{}.yul", contract_name));
    let metadata_path = out_dir.join(format!("{}.proof-forge-artifact.json", contract_name));
    let init_code_path = out_dir.join(format!("{}.init.bin", contract_name));
    let deploy_manifest_path = out_dir.join(format!("{}.proof-forge-deploy.json", contract_name));

    if let Some(source_path) = scenario_source(case, repo_root)? {
        build_contract_source_fixture(
            case,
            repo_root,
            &source_path,
            &bytecode_path,
            &yul_path,
            &metadata_path,
        )?;
        ensure_evm_outputs(
            contract_name,
            &bytecode_path,
            &metadata_path,
            &init_code_path,
            &deploy_manifest_path,
        )?;
        return Ok(EvmFixtureArtifact {
            bytecode_path,
            metadata_path,
            yul_path,
            init_code_path,
            deploy_manifest_path,
            contract_spec_path: None,
            evm_abi_path: None,
        });
    }

    bail!("{contract_name} testkit fixture requires a contract source path");
}

fn build_error_ref_fixture(repo_root: &Path) -> Result<EvmFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/evm/error-ref");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let build = Command::new("lake")
        .current_dir(repo_root)
        .args(["build", "proof-forge"])
        .output()
        .context("failed to build proof-forge executable")?;
    if !build.status.success() {
        bail!(
            "lake build proof-forge failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&build.stdout),
            String::from_utf8_lossy(&build.stderr)
        );
    }

    let bytecode_path = out_dir.join("ErrorRefProbe.bin");
    let yul_path = out_dir.join("ErrorRefProbe.yul");
    let metadata_path = out_dir.join("ErrorRefProbe.proof-forge-artifact.json");
    let init_code_path = out_dir.join("ErrorRefProbe.init.bin");
    let deploy_manifest_path = out_dir.join("ErrorRefProbe.proof-forge-deploy.json");
    let contract_spec_path = out_dir.join("ErrorRefProbe.contract-spec.json");
    let evm_abi_path = out_dir.join("proof-forge-evm-abi.ts");
    let proof_forge = repo_root.join(".lake/build/bin/proof-forge");
    let output = Command::new(&proof_forge)
        .current_dir(repo_root)
        .args([
            "emit",
            "--target",
            "evm",
            "--fixture",
            "error-ref",
            "--format",
            "bytecode",
            "--yul-output",
            path_str(&yul_path)?,
            "--artifact-output",
            path_str(&metadata_path)?,
            "-o",
            path_str(&bytecode_path)?,
        ])
        .output()
        .with_context(|| format!("failed to run `{}`", proof_forge.display()))?;
    if !output.status.success() {
        bail!(
            "ErrorRefProbe EVM bytecode emission failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    ensure!(
        bytecode_path.exists(),
        "ErrorRefProbe EVM bytecode emission did not create `{}`",
        bytecode_path.display()
    );
    ensure!(
        metadata_path.exists(),
        "ErrorRefProbe EVM bytecode emission did not create `{}`",
        metadata_path.display()
    );
    ensure!(
        init_code_path.exists(),
        "ErrorRefProbe EVM bytecode emission did not create `{}`",
        init_code_path.display()
    );
    ensure!(
        deploy_manifest_path.exists(),
        "ErrorRefProbe EVM bytecode emission did not create `{}`",
        deploy_manifest_path.display()
    );
    ensure!(
        contract_spec_path.exists(),
        "ErrorRefProbe EVM bytecode emission did not create `{}`",
        contract_spec_path.display()
    );
    ensure!(
        evm_abi_path.exists(),
        "ErrorRefProbe EVM bytecode emission did not create `{}`",
        evm_abi_path.display()
    );

    Ok(EvmFixtureArtifact {
        bytecode_path,
        metadata_path,
        yul_path,
        init_code_path,
        deploy_manifest_path,
        contract_spec_path: Some(contract_spec_path),
        evm_abi_path: Some(evm_abi_path),
    })
}

fn read_bytecode(path: &Path) -> Result<Vec<u8>> {
    let text =
        fs::read_to_string(path).with_context(|| format!("failed to read `{}`", path.display()))?;
    decode_hex(text.trim()).with_context(|| format!("failed to decode `{}`", path.display()))
}

fn calldata_for_step(selector: &[u8; 4], step: &Step) -> Result<Vec<u8>> {
    let mut calldata = selector.to_vec();
    calldata.extend(step.evm_abi_input_bytes().with_context(|| {
        format!(
            "failed to encode EVM calldata arguments for call `{}`",
            step.call
        )
    })?);
    Ok(calldata)
}

fn decode_hex(value: &str) -> Result<Vec<u8>> {
    let normalized = value.strip_prefix("0x").unwrap_or(value);
    ensure!(
        normalized.len() % 2 == 0,
        "hex value must contain an even number of digits"
    );
    hex::decode(normalized).context("invalid hex")
}

fn outcome_from_output(sequence: u32, call: &str, output: &[u8], gas_used: u64) -> CallOutcome {
    let return_hex = if output.is_empty() {
        None
    } else {
        Some(hex::encode(output))
    };
    let word = if output.len() == 32 {
        Some(output)
    } else {
        None
    };
    let return_u64 = word.and_then(word_to_u64);
    let return_u32 = return_u64.and_then(|value| u32::try_from(value).ok());
    let return_bool = word.and_then(word_to_bool);
    let raw_line = match &return_hex {
        Some(hex) => format!("evm call {sequence}:{call}: return_hex={hex} evm_gas={gas_used}"),
        None => format!("evm call {sequence}:{call}: return_hex= evm_gas={gas_used}"),
    };

    CallOutcome {
        sequence,
        call: call.to_string(),
        return_hex,
        return_u64,
        return_u32,
        return_bool,
        allocations: None,
        reuses: None,
        deallocations: None,
        budget: Some(proof_forge_testkit_core::BudgetOutcome {
            solana_cu: None,
            evm_gas: Some(gas_used),
            near_gas: None,
        }),
        error: None,
        raw_line,
    }
}

fn outcome_from_revert(sequence: u32, call: &str, output: &[u8], gas_used: u64) -> CallOutcome {
    let error = decode_revert_error(output);
    let error_str = error
        .as_ref()
        .map(|e| {
            format!(
                "assertion_id={} user_code={}",
                e.assertion_id,
                e.user_code.as_deref().unwrap_or("")
            )
        })
        .unwrap_or_else(|| "revert".to_string());
    let raw_line = format!("evm call {sequence}:{call}: error={error_str} evm_gas={gas_used}");

    CallOutcome {
        sequence,
        call: call.to_string(),
        return_hex: None,
        return_u64: None,
        return_u32: None,
        return_bool: None,
        allocations: None,
        reuses: None,
        deallocations: None,
        budget: Some(proof_forge_testkit_core::BudgetOutcome {
            solana_cu: None,
            evm_gas: Some(gas_used),
            near_gas: None,
        }),
        error,
        raw_line,
    }
}

fn decode_revert_error(output: &[u8]) -> Option<proof_forge_testkit_core::ErrorOutcome> {
    // Expect ABI encoding of (uint32 assertion_id, string user_code):
    // word 0: assertion_id (right-aligned in 32 bytes)
    // word 1: offset to string data (in bytes, typically 64)
    // word at offset: string length
    // following words: string data
    if output.len() < 96 {
        return None;
    }
    let assertion_id = u32::from_be_bytes(output[28..32].try_into().ok()?);
    let offset = u64::from_be_bytes(output[56..64].try_into().ok()?);
    if offset.checked_add(32)? as usize > output.len() {
        return None;
    }
    let len = u64::from_be_bytes(
        output[(offset as usize + 24)..(offset as usize + 32)]
            .try_into()
            .ok()?,
    );
    let data_start = (offset as usize).checked_add(32)?;
    let data_end = data_start.checked_add(len as usize)?;
    if data_end > output.len() {
        return None;
    }
    let user_code = String::from_utf8(output[data_start..data_end].to_vec()).ok();
    Some(proof_forge_testkit_core::ErrorOutcome {
        assertion_id,
        user_code,
    })
}

fn word_to_u64(word: &[u8]) -> Option<u64> {
    if word.len() != 32 || word[..24].iter().any(|byte| *byte != 0) {
        return None;
    }
    Some(u64::from_be_bytes(word[24..32].try_into().ok()?))
}

fn word_to_bool(word: &[u8]) -> Option<bool> {
    match word_to_u64(word)? {
        0 => Some(false),
        1 => Some(true),
        _ => None,
    }
}

fn load_selectors(path: &Path) -> Result<HashMap<String, [u8; 4]>> {
    let text =
        fs::read_to_string(path).with_context(|| format!("failed to read `{}`", path.display()))?;
    let artifact: ArtifactMetadata = serde_json::from_str(&text)
        .with_context(|| format!("failed to parse `{}`", path.display()))?;

    let mut selectors = HashMap::new();
    for entrypoint in artifact.abi.entrypoints {
        selectors.insert(entrypoint.name, selector_bytes(&entrypoint.selector)?);
    }
    for method in artifact.abi.methods {
        let name = method
            .signature
            .as_deref()
            .and_then(|signature| signature.split_once('(').map(|(name, _)| name.to_string()))
            .unwrap_or(method.fn_name);
        selectors.insert(name, selector_bytes(&method.selector)?);
    }
    Ok(selectors)
}

fn selector_bytes(selector: &str) -> Result<[u8; 4]> {
    let bytes = decode_hex(selector).with_context(|| format!("invalid selector `{selector}`"))?;
    ensure!(
        bytes.len() == 4,
        "selector `{selector}` decoded to {} bytes, expected 4",
        bytes.len()
    );
    Ok(bytes.try_into().expect("selector length checked"))
}

fn command_available(command: &str) -> bool {
    Command::new(command)
        .arg("--version")
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .map(|status| status.success())
        .unwrap_or(false)
}

fn scenario_source(case: &ScenarioCase, repo_root: &Path) -> Result<Option<PathBuf>> {
    let Some(path) = case.manifest.scenario.source_path(repo_root) else {
        return Ok(None);
    };
    ensure!(
        path.exists(),
        "scenario `{}` source `{}` does not exist",
        case.manifest.scenario.name,
        path.display()
    );
    Ok(Some(path))
}

fn cast_tool(repo_root: &Path) -> Result<String> {
    if let Ok(path) = env::var("CAST") {
        return Ok(path);
    }
    let shim = repo_root.join("build/tools/cast-shim");
    if shim.exists() {
        return Ok(path_str(&shim)?.to_string());
    }
    Ok("cast".to_string())
}

fn path_str(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| anyhow::anyhow!("non-UTF-8 path `{}`", path.display()))
}

#[derive(Debug, Deserialize)]
struct ArtifactMetadata {
    abi: ArtifactAbi,
}

#[derive(Debug, Deserialize)]
struct ArtifactAbi {
    #[serde(default)]
    entrypoints: Vec<ArtifactEntrypoint>,
    #[serde(default)]
    methods: Vec<ArtifactMethod>,
}

#[derive(Debug, Deserialize)]
struct ArtifactEntrypoint {
    name: String,
    selector: String,
}

#[derive(Debug, Deserialize)]
struct ArtifactMethod {
    selector: String,
    #[serde(default)]
    signature: Option<String>,
    #[serde(rename = "fnName")]
    fn_name: String,
}
