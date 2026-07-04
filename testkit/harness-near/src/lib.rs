use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

use anyhow::{bail, ensure, Context, Result};
use proof_forge_testkit_core::{
    assert_artifact_expectations, parse_offline_host_outcomes, ArtifactOutput, ChainHarness,
    HarnessRun, ScenarioCase,
};

pub struct NearHarness;

struct NearFixtureArtifact {
    wat_path: PathBuf,
    metadata_path: Option<PathBuf>,
    deploy_manifest_path: Option<PathBuf>,
    contract_spec_path: Option<PathBuf>,
    near_wrapper_path: Option<PathBuf>,
}

impl NearHarness {
    pub fn new() -> Self {
        Self
    }
}

impl Default for NearHarness {
    fn default() -> Self {
        Self::new()
    }
}

impl ChainHarness for NearHarness {
    fn target_id(&self) -> &'static str {
        "wasm-near"
    }

    fn run_scenario(&self, case: &ScenarioCase, repo_root: &Path) -> Result<HarnessRun> {
        let artifact = build_fixture(case, repo_root)?;
        let mut outputs = vec![ArtifactOutput {
            name: "wat",
            path: &artifact.wat_path,
        }];
        if let Some(ref path) = artifact.metadata_path {
            outputs.push(ArtifactOutput {
                name: "metadata",
                path,
            });
        }
        if let Some(ref path) = artifact.deploy_manifest_path {
            outputs.push(ArtifactOutput {
                name: "deploy-manifest",
                path,
            });
        }
        if let Some(ref path) = artifact.contract_spec_path {
            outputs.push(ArtifactOutput {
                name: "contract-spec",
                path: path,
            });
        }
        if let Some(ref path) = artifact.near_wrapper_path {
            outputs.push(ArtifactOutput {
                name: "near-wrapper",
                path: path,
            });
        }
        assert_artifact_expectations(case, self.target_id(), repo_root, &outputs)?;
        let mut args = vec!["run".to_string(), artifact.wat_path.display().to_string()];
        let mut inputs = Vec::new();
        let mut has_inputs = false;
        for step in &case.manifest.steps {
            let input = step.portable_input_bytes_le().with_context(|| {
                format!("failed to encode wasm-near input for call `{}`", step.call)
            })?;
            has_inputs |= !input.is_empty() || step.input_hex.is_some() || !step.args.is_empty();
            for _ in 0..step.repeat.unwrap_or(1) {
                args.push(step.call.clone());
                inputs.push(hex::encode(&input));
            }
        }
        if has_inputs {
            args.push("--inputs-hex".to_string());
            args.push(inputs.join(","));
        }

        let output = Command::new("cargo")
            .current_dir(repo_root)
            .args([
                "run",
                "--quiet",
                "--manifest-path",
                "runtime/offline-host/Cargo.toml",
                "--",
            ])
            .args(&args)
            .output()
            .context("failed to run runtime/offline-host")?;

        if !output.status.success() {
            bail!(
                "runtime/offline-host failed for scenario `{}`\nstdout:\n{}\nstderr:\n{}",
                case.manifest.scenario.name,
                String::from_utf8_lossy(&output.stdout),
                String::from_utf8_lossy(&output.stderr)
            );
        }

        parse_offline_host_outcomes(&String::from_utf8_lossy(&output.stdout))
            .map(HarnessRun::passed)
    }
}

fn build_fixture(case: &ScenarioCase, repo_root: &Path) -> Result<NearFixtureArtifact> {
    match case.manifest.scenario.fixture.as_str() {
        "counter" => {
            if let Some(source_path) = scenario_source(case, repo_root)? {
                build_contract_source_wat(
                    case,
                    repo_root,
                    &source_path,
                    "Counter",
                    "build/testkit/near/counter",
                    "counter.wat",
                    "Counter.near-artifact.json",
                )
            } else {
                emit_wat_fixture(
                    repo_root,
                    "Tests/EmitWatSmoke.lean",
                    "Counter",
                    "build/wasm-near/emitwat-counter.wat",
                    None,
                    None,
                )
            }
        }
        "value-vault" => {
            if let Some(source_path) = scenario_source(case, repo_root)? {
                build_contract_source_wat(
                    case,
                    repo_root,
                    &source_path,
                    "ValueVault",
                    "build/testkit/near/value-vault",
                    "valuevault.wat",
                    "ValueVault.near-artifact.json",
                )
            } else {
                emit_wat_fixture(
                    repo_root,
                    "Tests/EmitWatValueVault.lean",
                    "ValueVault",
                    "build/wasm-near/emitwat-value-vault.wat",
                    None,
                    None,
                )
            }
        }
        "alloc-release" => emit_wat_fixture(
            repo_root,
            "Tests/EmitWatAlloc.lean",
            "ArrayProbe",
            "build/wasm-near/emitwat-release-external.wat",
            None,
            None,
        ),
        "error-ref" => emit_wat_fixture(
            repo_root,
            "Tests/EmitWatErrorRef.lean",
            "ErrorRefProbe",
            "build/wasm-near/emitwat-error-ref.wat",
            Some("build/wasm-near/emitwat-error-ref.contract-spec.json"),
            Some("build/wasm-near/proof-forge-near.ts"),
        ),
        fixture => bail!("wasm-near testkit harness does not support fixture `{fixture}` yet"),
    }
}

fn emit_wat_fixture(
    repo_root: &Path,
    emitter: &str,
    fixture_name: &str,
    artifact_path: &str,
    contract_spec_path: Option<&str>,
    near_wrapper_path: Option<&str>,
) -> Result<NearFixtureArtifact> {
    let output = Command::new("lake")
        .current_dir(repo_root)
        .args(["env", "lean", "--run", emitter])
        .output()
        .with_context(|| format!("failed to emit {fixture_name} WAT through Lean"))?;
    if !output.status.success() {
        bail!(
            "{fixture_name} WAT emission failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let wat_path = repo_root.join(artifact_path);
    ensure!(
        wat_path.exists(),
        "{fixture_name} WAT emission did not create `{}`",
        wat_path.display()
    );
    let contract_spec_path = contract_spec_path.map(|p| repo_root.join(p));
    if let Some(ref path) = contract_spec_path {
        ensure!(
            path.exists(),
            "{fixture_name} WAT emission did not create `{}`",
            path.display()
        );
    }
    let near_wrapper_path = near_wrapper_path.map(|p| repo_root.join(p));
    if let Some(ref path) = near_wrapper_path {
        ensure!(
            path.exists(),
            "{fixture_name} WAT emission did not create `{}`",
            path.display()
        );
    }
    Ok(NearFixtureArtifact {
        wat_path,
        metadata_path: None,
        deploy_manifest_path: None,
        contract_spec_path,
        near_wrapper_path,
    })
}

fn build_contract_source_wat(
    case: &ScenarioCase,
    repo_root: &Path,
    source_path: &Path,
    fixture_name: &str,
    output_dir: &str,
    wat_file: &str,
    metadata_file: &str,
) -> Result<NearFixtureArtifact> {
    let output_dir = repo_root.join(output_dir);
    fs::create_dir_all(&output_dir)
        .with_context(|| format!("failed to create `{}`", output_dir.display()))?;
    let metadata_path = output_dir.join(metadata_file);
    let output = Command::new("lake")
        .current_dir(repo_root)
        .args([
            "env",
            "proof-forge",
            "build",
            "--target",
            "wasm-near",
            "--root",
            ".",
            "-o",
            path_str(&output_dir)?,
            "--artifact-output",
            path_str(&metadata_path)?,
            path_str(source_path)?,
        ])
        .output()
        .with_context(|| {
            format!(
                "failed to build wasm-near contract_source for scenario `{}`",
                case.manifest.scenario.name
            )
        })?;
    if !output.status.success() {
        bail!(
            "{fixture_name} contract_source WAT build failed\nstdout:\n{}\nstderr:\n{}",
            String::from_utf8_lossy(&output.stdout),
            String::from_utf8_lossy(&output.stderr)
        );
    }
    let wat_path = output_dir.join(wat_file);
    ensure!(
        wat_path.exists(),
        "{fixture_name} WAT build did not create `{}`",
        wat_path.display()
    );
    ensure!(
        metadata_path.exists(),
        "{fixture_name} WAT build did not create `{}`",
        metadata_path.display()
    );
    let deploy_manifest_path = default_deploy_manifest_output(&metadata_path);
    ensure!(
        deploy_manifest_path.exists(),
        "{fixture_name} WAT build did not create `{}`",
        deploy_manifest_path.display()
    );
    Ok(NearFixtureArtifact {
        wat_path,
        metadata_path: Some(metadata_path),
        deploy_manifest_path: Some(deploy_manifest_path),
        contract_spec_path: None,
        near_wrapper_path: None,
    })
}

fn default_deploy_manifest_output(metadata_output: &Path) -> PathBuf {
    let file_name = metadata_output
        .file_name()
        .and_then(|name| name.to_str())
        .unwrap_or("proof-forge-artifact.json");
    let deploy_name = if file_name == "proof-forge-artifact.json" {
        "proof-forge-deploy.json".to_string()
    } else if let Some(stem) = file_name.strip_suffix(".proof-forge-artifact.json") {
        format!("{stem}.proof-forge-deploy.json")
    } else {
        format!("{file_name}.proof-forge-deploy.json")
    };
    metadata_output
        .parent()
        .map(|parent| parent.join(&deploy_name))
        .unwrap_or_else(|| PathBuf::from(deploy_name))
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

fn path_str(path: &Path) -> Result<&str> {
    path.to_str()
        .ok_or_else(|| anyhow::anyhow!("non-UTF-8 path `{}`", path.display()))
}
