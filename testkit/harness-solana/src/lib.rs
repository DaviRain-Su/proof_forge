use std::collections::HashMap;
use std::env;
use std::fs;
use std::io::ErrorKind;
use std::path::{Path, PathBuf};
use std::process::{Command, Output, Stdio};

use anyhow::{bail, ensure, Context, Result};
use mollusk_svm::Mollusk;
use proof_forge_testkit_core::{
    assert_artifact_expectations, ArtifactOutput, CallOutcome, ChainHarness, DiagnosticExpectation,
    DiagnosticRun, HarnessRun, ScenarioCase,
};
use serde::Deserialize;
use solana_account::Account;
use solana_address::Address;
use solana_instruction::{error::InstructionError, AccountMeta, Instruction};

pub mod live_rpc;
pub mod spl_token;
pub mod token_2022;

const COUNTER_PROJECT_NAME: &str = "proofforge-counter";
const VALUE_VAULT_PROJECT_NAME: &str = "proofforge-value-vault";
const ERROR_REF_PROJECT_NAME: &str = "proofforge-error-ref";
const COUNTER_DATA_LEN: usize = 8;
const VALUE_VAULT_DATA_LEN: usize = 48;
const ERROR_REF_DATA_LEN: usize = 8;

pub struct SolanaHarness;

impl SolanaHarness {
    pub fn new() -> Self {
        Self
    }
}

impl Default for SolanaHarness {
    fn default() -> Self {
        Self::new()
    }
}

impl ChainHarness for SolanaHarness {
    fn target_id(&self) -> &'static str {
        "solana-sbpf-asm"
    }

    fn run_scenario(&self, case: &ScenarioCase, repo_root: &Path) -> Result<HarnessRun> {
        let sbpf = tool("SBPF", "sbpf");
        if !command_available(&sbpf) {
            return Ok(HarnessRun::skipped(format!(
                "sbpf not on PATH (set SBPF or install blueshift-gg/sbpf)"
            )));
        }

        let keygen = tool("SOLANA_KEYGEN", "solana-keygen");
        if !command_available(&keygen) {
            return Ok(HarnessRun::skipped(
                "solana-keygen not on PATH (set SOLANA_KEYGEN)",
            ));
        }

        match case.manifest.scenario.fixture.as_str() {
            "counter" => run_counter_scenario(case, repo_root, &sbpf, &keygen),
            "value-vault" => run_value_vault_scenario(case, repo_root, &sbpf, &keygen),
            "error-ref" => run_error_ref_scenario(case, repo_root, &sbpf, &keygen),
            fixture => {
                bail!("solana-sbpf-asm testkit harness does not support fixture `{fixture}` yet")
            }
        }
    }

    fn run_diagnostic(
        &self,
        case: &ScenarioCase,
        diagnostic: &DiagnosticExpectation,
        repo_root: &Path,
    ) -> Result<DiagnosticRun> {
        match diagnostic.name.as_str() {
            "crosscall.invoke unsupported" => run_lean_diagnostic(
                case,
                diagnostic,
                repo_root,
                "Tests/TestkitSolanaCapabilityDiagnostic.lean",
            ),
            name => {
                bail!("solana-sbpf-asm testkit harness does not support diagnostic `{name}` yet")
            }
        }
    }
}

fn run_lean_diagnostic(
    case: &ScenarioCase,
    diagnostic: &DiagnosticExpectation,
    repo_root: &Path,
    file: &str,
) -> Result<DiagnosticRun> {
    let output = Command::new("lake")
        .current_dir(repo_root)
        .args(["env", "lean", "--run", file])
        .output()
        .with_context(|| format!("failed to run `{file}`"))?;
    let combined = command_output_text(&output);
    if !output.status.success() {
        bail!(
            "diagnostic `{}` failed for scenario `{}`\n{}",
            diagnostic.name,
            case.manifest.scenario.name,
            combined
        );
    }
    for needle in &diagnostic.contains {
        ensure!(
            combined.contains(needle),
            "diagnostic `{}` for scenario `{}` missing `{needle}` in output:\n{}",
            diagnostic.name,
            case.manifest.scenario.name,
            combined
        );
    }
    Ok(DiagnosticRun::passed())
}

fn command_output_text(output: &Output) -> String {
    format!(
        "stdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}

fn run_counter_scenario(
    case: &ScenarioCase,
    repo_root: &Path,
    sbpf: &str,
    keygen: &str,
) -> Result<HarnessRun> {
    let artifact = build_counter_fixture(case, repo_root, sbpf, keygen)?;
    run_state_account_scenario(case, repo_root, artifact, COUNTER_DATA_LEN)
}

fn run_value_vault_scenario(
    case: &ScenarioCase,
    repo_root: &Path,
    sbpf: &str,
    keygen: &str,
) -> Result<HarnessRun> {
    let artifact = build_value_vault_fixture(case, repo_root, sbpf, keygen)?;
    run_state_account_scenario(case, repo_root, artifact, VALUE_VAULT_DATA_LEN)
}

fn run_error_ref_scenario(
    case: &ScenarioCase,
    repo_root: &Path,
    sbpf: &str,
    keygen: &str,
) -> Result<HarnessRun> {
    let artifact = build_error_ref_fixture(repo_root, sbpf, keygen)?;
    run_state_account_scenario(case, repo_root, artifact, ERROR_REF_DATA_LEN)
}

fn run_state_account_scenario(
    case: &ScenarioCase,
    repo_root: &Path,
    artifact: SolanaFixtureArtifact,
    account_data_len: usize,
) -> Result<HarnessRun> {
    let mut outputs = vec![
        ArtifactOutput {
            name: "sbpf-asm",
            path: &artifact.asm_path,
        },
        ArtifactOutput {
            name: "manifest",
            path: &artifact.manifest_path,
        },
        ArtifactOutput {
            name: "metadata",
            path: &artifact.metadata_path,
        },
    ];
    if let Some(idl_path) = &artifact.idl_path {
        outputs.push(ArtifactOutput {
            name: "idl",
            path: idl_path,
        });
    }
    if let Some(client_path) = &artifact.client_path {
        outputs.push(ArtifactOutput {
            name: "client",
            path: client_path,
        });
    }
    if let Some(contract_spec_path) = &artifact.contract_spec_path {
        outputs.push(ArtifactOutput {
            name: "contract-spec",
            path: contract_spec_path,
        });
    }
    if let Some(source_path) = &artifact.source_path {
        outputs.push(ArtifactOutput {
            name: "source",
            path: source_path,
        });
    }
    assert_artifact_expectations(case, "solana-sbpf-asm", repo_root, &outputs)?;

    let tags = load_instruction_tags(&artifact.manifest_path)?;
    let pid = program_id(&artifact.keypair_path)?;
    let mollusk = mollusk(pid, &artifact.program_path)?;
    let state = Address::new_unique();
    let mut state_account = Account::new(0, account_data_len, &pid);

    let mut outcomes = Vec::new();
    let mut sequence = 1u32;
    for step in &case.manifest.steps {
        let tag = tags
            .get(&step.call)
            .with_context(|| format!("Solana manifest does not contain call `{}`", step.call))?;
        let mut instruction_data = vec![*tag];
        instruction_data.extend(step.portable_input_bytes_le().with_context(|| {
            format!(
                "failed to encode solana-sbpf-asm instruction data for call `{}`",
                step.call
            )
        })?);
        for _ in 0..step.repeat.unwrap_or(1) {
            let result = mollusk.process_instruction(
                &ix(pid, instruction_data.clone(), state),
                &[(state, state_account.clone())],
            );
            let error = extract_solana_error(&result.raw_result);
            if error.is_none() {
                state_account = result
                    .get_account(&state)
                    .with_context(|| {
                        format!("Solana call `{}` did not return state account", step.call)
                    })?
                    .clone();
            }
            outcomes.push(outcome_from_mollusk_result(
                sequence, &step.call, &result, error,
            ));
            sequence += 1;
        }
    }

    Ok(HarnessRun::passed(outcomes))
}

struct SolanaFixtureArtifact {
    asm_path: PathBuf,
    manifest_path: PathBuf,
    metadata_path: PathBuf,
    idl_path: Option<PathBuf>,
    client_path: Option<PathBuf>,
    contract_spec_path: Option<PathBuf>,
    source_path: Option<PathBuf>,
    keypair_path: PathBuf,
    program_path: PathBuf,
}

fn build_counter_fixture(
    case: &ScenarioCase,
    repo_root: &Path,
    sbpf: &str,
    keygen: &str,
) -> Result<SolanaFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/solana/counter");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let mut build = Command::new("lake");
    build.current_dir(repo_root).args(["build", "proof-forge"]);
    run_required(&mut build, "lake build proof-forge")?;

    let asm_path = out_dir.join("Counter.s");
    let artifact_path = out_dir.join("proof-forge-artifact.json");
    if let Some(source_path) = scenario_source(case, repo_root)? {
        build_contract_source_fixture(case, repo_root, &source_path, &asm_path, &artifact_path)?;
        return finish_solana_fixture(
            "Counter",
            &out_dir,
            &asm_path,
            &artifact_path,
            COUNTER_PROJECT_NAME,
            Some(source_path),
            true,
            sbpf,
            keygen,
        );
    }

    let proof_forge = repo_root.join(".lake/build/bin/proof-forge");
    let mut emit = Command::new(&proof_forge);
    emit.current_dir(repo_root).args([
        "emit",
        "--target",
        "solana-sbpf-asm",
        "--fixture",
        "counter",
        "--format",
        "s",
        "-o",
        path_str(&asm_path)?,
        "--artifact-output",
        path_str(&artifact_path)?,
    ]);
    run_required(
        &mut emit,
        "proof-forge emit --target solana-sbpf-asm --fixture counter",
    )?;

    finish_solana_fixture(
        "Counter",
        &out_dir,
        &asm_path,
        &artifact_path,
        COUNTER_PROJECT_NAME,
        None,
        false,
        sbpf,
        keygen,
    )
}

fn build_value_vault_fixture(
    case: &ScenarioCase,
    repo_root: &Path,
    sbpf: &str,
    keygen: &str,
) -> Result<SolanaFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/solana/value-vault");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let mut build = Command::new("lake");
    build.current_dir(repo_root).args(["build", "proof-forge"]);
    run_required(&mut build, "lake build proof-forge")?;

    let asm_path = out_dir.join("ValueVault.s");
    let artifact_path = out_dir.join("proof-forge-artifact.json");
    if let Some(source_path) = scenario_source(case, repo_root)? {
        build_contract_source_fixture(case, repo_root, &source_path, &asm_path, &artifact_path)?;
        return finish_solana_fixture(
            "ValueVault",
            &out_dir,
            &asm_path,
            &artifact_path,
            VALUE_VAULT_PROJECT_NAME,
            Some(source_path),
            true,
            sbpf,
            keygen,
        );
    }

    let proof_forge = repo_root.join(".lake/build/bin/proof-forge");
    let mut emit = Command::new(&proof_forge);
    emit.current_dir(repo_root).args([
        "emit",
        "--target",
        "solana-sbpf-asm",
        "--fixture",
        "value-vault",
        "--format",
        "s",
        "-o",
        path_str(&asm_path)?,
        "--artifact-output",
        path_str(&artifact_path)?,
    ]);
    run_required(
        &mut emit,
        "proof-forge emit --target solana-sbpf-asm --fixture value-vault",
    )?;

    finish_solana_fixture(
        "ValueVault",
        &out_dir,
        &asm_path,
        &artifact_path,
        VALUE_VAULT_PROJECT_NAME,
        None,
        true,
        sbpf,
        keygen,
    )
}

fn build_contract_source_fixture(
    case: &ScenarioCase,
    repo_root: &Path,
    source_path: &Path,
    asm_path: &Path,
    artifact_path: &Path,
) -> Result<()> {
    let mut build = Command::new("lake");
    // PF-P0-03: default Solana source build is ELF; testkit scaffolds its own
    // sbpf package from assembly, so request the toolchain-free intermediate.
    build.current_dir(repo_root).args([
        "env",
        "proof-forge",
        "build",
        "--target",
        "solana-sbpf-asm",
        "--format",
        "s",
        "--root",
        ".",
        "-o",
        path_str(asm_path)?,
        "--artifact-output",
        path_str(artifact_path)?,
        path_str(source_path)?,
    ]);
    run_required(
        &mut build,
        &format!(
            "proof-forge build --target solana-sbpf-asm --format s for scenario `{}`",
            case.manifest.scenario.name
        ),
    )?;
    Ok(())
}

fn finish_solana_fixture(
    fixture_name: &str,
    out_dir: &Path,
    asm_path: &Path,
    artifact_path: &Path,
    project_name: &str,
    source_path: Option<PathBuf>,
    has_idl_and_client: bool,
    sbpf: &str,
    keygen: &str,
) -> Result<SolanaFixtureArtifact> {
    ensure!(
        asm_path.exists(),
        "{fixture_name} Solana emission did not create `{}`",
        asm_path.display()
    );
    ensure!(
        artifact_path.exists(),
        "{fixture_name} Solana emission did not create `{}`",
        artifact_path.display()
    );
    let manifest_path = out_dir.join("manifest.toml");
    ensure!(
        manifest_path.exists(),
        "{fixture_name} Solana emission did not create `{}`",
        manifest_path.display()
    );
    let idl_path = has_idl_and_client.then(|| out_dir.join("proof-forge-idl.json"));
    if let Some(ref path) = idl_path {
        ensure!(
            path.exists(),
            "{fixture_name} Solana emission did not create `{}`",
            path.display()
        );
    }
    let client_path = has_idl_and_client.then(|| out_dir.join("proof-forge-client.ts"));
    if let Some(ref path) = client_path {
        ensure!(
            path.exists(),
            "{fixture_name} Solana emission did not create `{}`",
            path.display()
        );
    }

    let project_dir = out_dir.join("sbpf-project");
    let keypair_path = project_dir
        .join("deploy")
        .join(format!("{project_name}-keypair.json"));
    let program_path = project_dir.join("deploy").join(project_name);
    scaffold_sbpf_project(&project_dir, project_name, asm_path, keygen)?;

    let mut sbpf_build = Command::new(sbpf);
    sbpf_build.current_dir(&project_dir).arg("build");
    run_required(&mut sbpf_build, "sbpf build")?;

    let elf_path = program_path.with_extension("so");
    ensure!(
        elf_path.exists(),
        "Solana sbpf build did not create `{}`",
        elf_path.display()
    );

    Ok(SolanaFixtureArtifact {
        asm_path: asm_path.to_path_buf(),
        manifest_path,
        metadata_path: artifact_path.to_path_buf(),
        idl_path,
        client_path,
        contract_spec_path: None,
        source_path,
        keypair_path,
        program_path,
    })
}

fn build_error_ref_fixture(
    repo_root: &Path,
    sbpf: &str,
    keygen: &str,
) -> Result<SolanaFixtureArtifact> {
    let out_dir = repo_root.join("build/testkit/solana/error-ref");
    fs::create_dir_all(&out_dir)
        .with_context(|| format!("failed to create `{}`", out_dir.display()))?;

    let mut build = Command::new("lake");
    build.current_dir(repo_root).args(["build", "proof-forge"]);
    run_required(&mut build, "lake build proof-forge")?;

    let asm_path = out_dir.join("ErrorRefProbe.s");
    let artifact_path = out_dir.join("proof-forge-artifact.json");
    let proof_forge = repo_root.join(".lake/build/bin/proof-forge");
    let mut emit = Command::new(&proof_forge);
    emit.current_dir(repo_root).args([
        "emit",
        "--target",
        "solana-sbpf-asm",
        "--fixture",
        "error-ref",
        "--format",
        "s",
        "-o",
        path_str(&asm_path)?,
        "--artifact-output",
        path_str(&artifact_path)?,
    ]);
    run_required(
        &mut emit,
        "proof-forge emit --target solana-sbpf-asm --fixture error-ref",
    )?;

    ensure!(
        asm_path.exists(),
        "ErrorRefProbe Solana emission did not create `{}`",
        asm_path.display()
    );
    ensure!(
        artifact_path.exists(),
        "ErrorRefProbe Solana emission did not create `{}`",
        artifact_path.display()
    );
    let manifest_path = out_dir.join("manifest.toml");
    ensure!(
        manifest_path.exists(),
        "ErrorRefProbe Solana emission did not create `{}`",
        manifest_path.display()
    );
    let contract_spec_path = out_dir.join("ErrorRefProbe.contract-spec.json");
    ensure!(
        contract_spec_path.exists(),
        "ErrorRefProbe Solana emission did not create `{}`",
        contract_spec_path.display()
    );
    let project_dir = out_dir.join("sbpf-project");
    let keypair_path = project_dir
        .join("deploy")
        .join(format!("{ERROR_REF_PROJECT_NAME}-keypair.json"));
    let program_path = project_dir.join("deploy").join(ERROR_REF_PROJECT_NAME);
    scaffold_sbpf_project(&project_dir, ERROR_REF_PROJECT_NAME, &asm_path, keygen)?;

    let mut sbpf_build = Command::new(sbpf);
    sbpf_build.current_dir(&project_dir).arg("build");
    run_required(&mut sbpf_build, "sbpf build")?;

    let elf_path = program_path.with_extension("so");
    ensure!(
        elf_path.exists(),
        "Solana sbpf build did not create `{}`",
        elf_path.display()
    );

    Ok(SolanaFixtureArtifact {
        asm_path,
        manifest_path,
        metadata_path: artifact_path,
        idl_path: None,
        client_path: None,
        contract_spec_path: Some(contract_spec_path),
        source_path: None,
        keypair_path,
        program_path,
    })
}

fn scaffold_sbpf_project(
    project_dir: &Path,
    project_name: &str,
    asm_path: &Path,
    keygen: &str,
) -> Result<()> {
    match fs::remove_dir_all(project_dir) {
        Ok(()) => {}
        Err(error) if error.kind() == ErrorKind::NotFound => {}
        Err(error) => {
            return Err(error)
                .with_context(|| format!("failed to remove `{}`", project_dir.display()));
        }
    }

    let src_dir = project_dir.join("src").join(project_name);
    let deploy_dir = project_dir.join("deploy");
    fs::create_dir_all(&src_dir)
        .with_context(|| format!("failed to create `{}`", src_dir.display()))?;
    fs::create_dir_all(&deploy_dir)
        .with_context(|| format!("failed to create `{}`", deploy_dir.display()))?;
    fs::copy(asm_path, src_dir.join(format!("{project_name}.s"))).with_context(|| {
        format!(
            "failed to copy `{}` into `{}`",
            asm_path.display(),
            src_dir.display()
        )
    })?;
    fs::write(
        project_dir.join("Cargo.toml"),
        format!("[package]\nname = \"{project_name}\"\nversion = \"0.1.0\"\nedition = \"2021\"\n"),
    )
    .with_context(|| {
        format!(
            "failed to write `{}`",
            project_dir.join("Cargo.toml").display()
        )
    })?;

    let keypair_path = deploy_dir.join(format!("{project_name}-keypair.json"));
    let mut keygen_cmd = Command::new(keygen);
    keygen_cmd.args([
        "new",
        "--no-bip39-passphrase",
        "--silent",
        "-o",
        path_str(&keypair_path)?,
        "--force",
    ]);
    run_required(&mut keygen_cmd, "solana-keygen new")?;
    Ok(())
}

fn mollusk(pid: Address, program_path: &Path) -> Result<Mollusk> {
    let program_path = path_str(program_path)?;
    let restore_log_env = env::var_os("RUST_LOG").is_none();
    if restore_log_env {
        env::set_var("RUST_LOG", "error");
    }
    let mut mollusk = Mollusk::new(&pid, program_path);
    if restore_log_env {
        env::remove_var("RUST_LOG");
    }
    // Match the checked-in Mollusk templates for the current Phase 1 ABI.
    mollusk.feature_set.account_data_direct_mapping = false;
    mollusk.feature_set.direct_account_pointers_in_program_input = false;
    mollusk.feature_set.virtual_address_space_adjustments = false;
    Ok(mollusk)
}

fn ix(pid: Address, data: Vec<u8>, state: Address) -> Instruction {
    Instruction::new_with_bytes(pid, &data, vec![AccountMeta::new(state, false)])
}

fn extract_solana_error(
    raw_result: &Result<(), InstructionError>,
) -> Option<proof_forge_testkit_core::ErrorOutcome> {
    match raw_result {
        Err(InstructionError::Custom(code)) => Some(proof_forge_testkit_core::ErrorOutcome {
            assertion_id: *code,
            user_code: None,
        }),
        _ => None,
    }
}

fn outcome_from_mollusk_result(
    sequence: u32,
    call: &str,
    result: &mollusk_svm::result::InstructionResult,
    error: Option<proof_forge_testkit_core::ErrorOutcome>,
) -> CallOutcome {
    let return_data = &result.return_data;
    let return_hex = if return_data.is_empty() {
        None
    } else {
        Some(hex::encode(return_data))
    };
    let return_u64 = if return_data.len() == 8 {
        Some(u64::from_le_bytes(
            return_data
                .as_slice()
                .try_into()
                .expect("return_data length checked"),
        ))
    } else {
        None
    };
    let return_u32 = return_u64.and_then(|value| u32::try_from(value).ok());
    let return_bool = match return_u64 {
        Some(0) => Some(false),
        Some(1) => Some(true),
        _ => None,
    };
    let compute_units = result.compute_units_consumed;
    let raw_line = if let Some(error) = &error {
        format!(
            "solana-sbpf-asm call {sequence}:{call}: error=assertion_id={} solana_cu={compute_units}",
            error.assertion_id
        )
    } else {
        match &return_hex {
            Some(hex) => format!(
                "solana-sbpf-asm call {sequence}:{call}: return_hex={hex} solana_cu={compute_units}"
            ),
            None => format!(
                "solana-sbpf-asm call {sequence}:{call}: return_hex= solana_cu={compute_units}"
            ),
        }
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
            solana_cu: Some(compute_units),
            evm_gas: None,
            wasmtime_fuel_cumulative: None,
            wasmtime_fuel_delta: None,
        }),
        error,
        raw_line,
    }
}

fn load_instruction_tags(path: &Path) -> Result<HashMap<String, u8>> {
    let text =
        fs::read_to_string(path).with_context(|| format!("failed to read `{}`", path.display()))?;
    let manifest: SolanaManifest =
        toml::from_str(&text).with_context(|| format!("failed to parse `{}`", path.display()))?;
    let mut tags = HashMap::new();
    for instruction in manifest.instruction {
        tags.insert(instruction.name, instruction.tag);
    }
    Ok(tags)
}

fn program_id(keypair_path: &Path) -> Result<Address> {
    let keypair_bytes = fs::read(keypair_path)
        .with_context(|| format!("failed to read `{}`", keypair_path.display()))?;
    ensure!(
        keypair_bytes.len() >= 32,
        "Solana keypair `{}` is shorter than 32 bytes",
        keypair_path.display()
    );
    let mut arr = [0u8; 32];
    arr.copy_from_slice(&keypair_bytes[..32]);
    Ok(Address::new_from_array(arr))
}

fn run_required(command: &mut Command, description: &str) -> Result<Output> {
    let output = command
        .output()
        .with_context(|| format!("failed to run {description}"))?;
    if !output.status.success() {
        bail!(
            "{description} failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    Ok(output)
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

fn tool(env_key: &str, default: &str) -> String {
    env::var(env_key).unwrap_or_else(|_| default.to_string())
}

fn path_str(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| anyhow::anyhow!("non-UTF-8 path `{}`", path.display()))
}

#[derive(Debug, Deserialize)]
struct SolanaManifest {
    instruction: Vec<ManifestInstruction>,
}

#[derive(Debug, Deserialize)]
struct ManifestInstruction {
    name: String,
    tag: u8,
}
