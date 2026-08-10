use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::targets::{self, aleo::local_run, psy};
use std::path::Path;

/// `pf run -- <fn> [inputs...]` or `pf local run ...`
pub fn run(
    target_cli: Option<&str>,
    artifact_cli: Option<&Path>,
    call_args: &[String],
    json: bool,
    verbose: bool,
) -> PfResult<()> {
    if call_args.is_empty() {
        return Err(PfError::Usage(
            "missing function after `--` (example: pf run -- initialize 5u64)".into(),
        ));
    }
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);
    let tid = targets::TargetId::parse(&target);
    if tid == targets::TargetId::Evm {
        return Err(PfError::NotImplemented(
            "evm: use `pf test -t evm` (local Anvil); `pf run` is Aleo/Psy in v0".into(),
        ));
    }
    if tid == targets::TargetId::Solana {
        return Err(PfError::NotImplemented(
            "solana: use `pf verify -t solana` (offline) or `pf test -t solana` (Mollusk)".into(),
        ));
    }
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build` first)",
            dir.display()
        )));
    }
    let function = &call_args[0];
    let inputs = call_args[1..].to_vec();

    if tid == targets::TargetId::Psy {
        let outcome = psy::simulate::simulate(&dir, function, &inputs)?;
        let mut ok = PfOk::new("run");
        ok.target = Some(target.clone());
        ok.artifact_dir = Some(dir.display().to_string());
        ok.extra = Some(serde_json::json!({
            "lane": "psy_user_cli-simulate",
            "dpn": outcome.dpn_path.display().to_string(),
            "method": outcome.method,
            "inputs": outcome.inputs,
            "result": outcome.result,
            "note": "ephemeral InMemoryStateBackend; not network/UPS/proof",
        }));
        return emit(ok, json, || {
            println!("    Finished `run` {target}::{function} (official DPN simulate)");
            if verbose {
                println!("{}", outcome.raw_stdout);
            } else if let Some(outs) = outcome.result.get("outputs") {
                println!("outputs: {outs}");
            }
            if let Some(delta) = outcome.result.get("state_delta") {
                if delta.as_array().map(|a| !a.is_empty()).unwrap_or(false) {
                    println!("state_delta: {delta}");
                }
            }
        });
    }

    targets::require_aleo(&target)?;
    let artifact = load_aleo_artifact(&dir)?;
    let outcome = local_run::run_local(&artifact, function, &inputs)?;
    let summary = summarize_leo_output(&outcome.stdout);
    let mut ok = PfOk::new("run");
    ok.target = Some(target.clone());
    ok.artifact_dir = Some(dir.display().to_string());
    ok.extra = Some(serde_json::json!({
        "stdout": outcome.stdout,
        "summary": summary,
        "importSha256": outcome.import_sha256_hex,
        "function": function,
        "inputs": inputs,
    }));
    emit(ok, json, || {
        if verbose {
            print!("{}", outcome.stdout);
            eprint!("{}", outcome.stderr);
        } else {
            println!("    Finished `run` {target}::{function}");
            if !summary.trim().is_empty() {
                println!("{summary}");
            }
        }
    })
}

/// Keep the useful VM result; drop Leo compile chatter for default UX.
fn summarize_leo_output(stdout: &str) -> String {
    // Prefer structured result block (program_id / function_name).
    if let Some(idx) = stdout.find("program_id:") {
        let slice = &stdout[idx..];
        // Take a bounded window after the first program_id hit.
        let mut lines = Vec::new();
        for (i, line) in slice.lines().enumerate() {
            if i > 24 {
                break;
            }
            lines.push(line);
            if line.trim() == "}" && i > 0 {
                break;
            }
        }
        return lines.join("\n");
    }

    let mut out = String::new();
    let mut capture = false;
    for line in stdout.lines() {
        let is_output_header = line.contains("Output")
            && (line.contains('•') || line.contains("➡️") || line.contains("=>"));
        if is_output_header {
            capture = true;
        }
        if capture {
            out.push_str(line);
            out.push('\n');
        }
        if line.contains("Error [") && !capture {
            out.push_str(line);
            out.push('\n');
        }
    }
    if out.is_empty() {
        // Last resort: only lines that look like results, never compile stats.
        stdout
            .lines()
            .filter(|l| {
                let t = l.trim();
                t.contains("function_name")
                    || t.contains("program_id")
                    || t.starts_with('•')
                    || t.contains("Error [")
            })
            .collect::<Vec<_>>()
            .join("\n")
    } else {
        out
    }
}

#[cfg(test)]
mod tests {
    use super::summarize_leo_output;

    #[test]
    fn summary_prefers_program_id_block() {
        let raw = "\
Leo Compiling\n\
statements before dead code elimination.\n\
➡️  Output\n\
 • {\n\
  program_id: hello.aleo,\n\
  function_name: initialize,\n\
  arguments: [\n\
    5u64\n\
  ]\n\
}\n";
        let s = summarize_leo_output(raw);
        assert!(s.contains("program_id: hello.aleo"));
        assert!(s.contains("initialize"));
        assert!(!s.contains("dead code"));
    }
}
