use std::path::Path;
use std::process::Command;

use anyhow::{bail, ensure, Context, Result};
use proof_forge_testkit_core::{QuintMbtExpectation, ScenarioCase};

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum QuintRun {
    Passed,
    Skipped { reason: String },
}

impl QuintRun {
    pub fn passed() -> Self {
        Self::Passed
    }

    pub fn skipped(reason: impl Into<String>) -> Self {
        Self::Skipped {
            reason: reason.into(),
        }
    }
}

pub fn run_mbt(
    case: &ScenarioCase,
    expectation: &QuintMbtExpectation,
    repo_root: &Path,
) -> Result<QuintRun> {
    if !quint_available() {
        if ci_required() {
            bail!("quint not found on PATH (required in CI)");
        }
        return Ok(QuintRun::skipped("quint not found on PATH"));
    }

    let replay_test = expectation.replay_test_path(&case.manifest.scenario);
    ensure!(
        replay_test.is_absolute() || repo_root.join(&replay_test).is_file(),
        "scenario `{}` quint expectation `{}` replay test `{}` does not exist",
        case.manifest.scenario.name,
        expectation.name,
        replay_test.display()
    );

    let replay_arg = replay_test
        .to_str()
        .context("replay test path is not valid UTF-8")?;

    let output = Command::new("lake")
        .current_dir(repo_root)
        .args(["env", "lean", "--run", replay_arg])
        .output()
        .with_context(|| format!("failed to run `{replay_arg}`"))?;
    let combined = command_output_text(&output);
    if !output.status.success() {
        bail!(
            "quint expectation `{}` failed for scenario `{}` (fixture `{}`)\n{}",
            expectation.name,
            case.manifest.scenario.name,
            expectation.fixture_id(&case.manifest.scenario),
            combined
        );
    }

    let needles = if expectation.contains.is_empty() {
        vec!["PASS".to_string()]
    } else {
        expectation.contains.clone()
    };
    for needle in needles {
        ensure!(
            combined.contains(&needle),
            "quint expectation `{}` for scenario `{}` missing `{needle}` in output:\n{}",
            expectation.name,
            case.manifest.scenario.name,
            combined
        );
    }

    Ok(QuintRun::passed())
}

fn quint_available() -> bool {
    Command::new("quint")
        .arg("--help")
        .output()
        .map(|output| output.status.success())
        .unwrap_or(false)
}

fn ci_required() -> bool {
    matches!(
        std::env::var("CI").ok().as_deref(),
        Some("true") | Some("1")
    ) || matches!(
        std::env::var("GITHUB_ACTIONS").ok().as_deref(),
        Some("true") | Some("1")
    )
}

fn command_output_text(output: &std::process::Output) -> String {
    format!(
        "stdout:\n{}\nstderr:\n{}",
        String::from_utf8_lossy(&output.stdout),
        String::from_utf8_lossy(&output.stderr)
    )
}