//! `pf test` — host-optional local runtime checks (D8 multi-target report).
//!
//! ```text
//! pf test                     # pf.toml default-target
//! pf test -t solana
//! pf test -t evm,solana       # sequential; any hard fail → non-zero
//! ```

use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::targets::{self, evm, solana};
use serde_json::{json, Value};
use std::path::Path;

#[derive(Debug, Clone)]
struct TargetReport {
    target: String,
    status: &'static str, // "ok" | "skipped" | "failed" | "not_implemented"
    artifact_dir: Option<String>,
    lane: Option<String>,
    message: String,
    detail: Option<Value>,
}

/// Split `-t a,b` / `-t a -t b` style input into ordered unique targets.
pub fn parse_target_list(raw: Option<&str>, fallback: &str) -> Vec<String> {
    let src = raw
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .unwrap_or(fallback);
    let mut out = Vec::new();
    for part in src.split(|c: char| c == ',' || c.is_whitespace()) {
        let t = part.trim();
        if t.is_empty() {
            continue;
        }
        let lower = t.to_ascii_lowercase();
        if !out.iter().any(|x: &String| x == &lower) {
            out.push(lower);
        }
    }
    if out.is_empty() {
        out.push(fallback.to_ascii_lowercase());
    }
    out
}

pub fn run(target_cli: Option<&str>, artifact_cli: Option<&Path>, json: bool) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let default_target = project.resolve_target(None);
    let targets_list = parse_target_list(target_cli, &default_target);

    let mut reports: Vec<TargetReport> = Vec::with_capacity(targets_list.len());
    let mut hard_fail: Option<PfError> = None;

    for target in &targets_list {
        // Per-target artifact: only honor --artifact when a single target is requested.
        let artifact_override = if targets_list.len() == 1 {
            artifact_cli
        } else {
            None
        };
        let dir = project.resolve_artifact_dir(target, artifact_override, None);
        match run_one(target, &dir) {
            Ok(rep) => {
                if !json {
                    print_human_one(&rep);
                }
                reports.push(rep);
            }
            Err(err) => {
                let rep = TargetReport {
                    target: target.clone(),
                    status: if matches!(err, PfError::NotImplemented(_)) {
                        "not_implemented"
                    } else {
                        "failed"
                    },
                    artifact_dir: Some(dir.display().to_string()),
                    lane: None,
                    message: err.to_string(),
                    detail: None,
                };
                if !json {
                    print_human_one(&rep);
                }
                reports.push(rep);
                if hard_fail.is_none() {
                    hard_fail = Some(err);
                }
            }
        }
    }

    let any_failed = reports
        .iter()
        .any(|r| r.status == "failed" || r.status == "not_implemented");
    let all_skipped = !reports.is_empty() && reports.iter().all(|r| r.status == "skipped");

    let mut ok = PfOk::new("test");
    ok.target = Some(targets_list.join(","));
    if targets_list.len() == 1 {
        ok.artifact_dir = reports.first().and_then(|r| r.artifact_dir.clone());
    }
    ok.extra = Some(json!({
        "targets": targets_list,
        "summary": {
            "total": reports.len(),
            "ok": reports.iter().filter(|r| r.status == "ok").count(),
            "skipped": reports.iter().filter(|r| r.status == "skipped").count(),
            "failed": reports.iter().filter(|r| r.status == "failed").count(),
            "notImplemented": reports.iter().filter(|r| r.status == "not_implemented").count(),
        },
        "results": reports.iter().map(|r| json!({
            "target": r.target,
            "status": r.status,
            "artifactDir": r.artifact_dir,
            "lane": r.lane,
            "message": r.message,
            "detail": r.detail,
        })).collect::<Vec<_>>(),
    }));
    ok.notes = Some(vec![
        "multi-target: sequential; any failed/not_implemented → non-zero".into(),
        "skipped = host-optional tools missing (not a pass claim)".into(),
        "deployable not rewritten".into(),
        "not formal/hermetic/mainnet".into(),
    ]);

    if any_failed {
        // Prefer first hard error for exit mapping / --json error path via caller.
        return Err(
            hard_fail.unwrap_or_else(|| PfError::Tool("one or more pf test targets failed".into()))
        );
    }

    emit(ok, json, || {
        println!();
        let ok_n = reports.iter().filter(|r| r.status == "ok").count();
        let sk_n = reports.iter().filter(|r| r.status == "skipped").count();
        if all_skipped {
            println!(
                "    Finished `test` ({} target(s): all skipped — host tools missing)",
                reports.len()
            );
        } else {
            println!(
                "    Finished `test` ({} target(s): {ok_n} ok, {sk_n} skipped)",
                reports.len()
            );
        }
        for r in &reports {
            let art = r.artifact_dir.as_deref().unwrap_or("-");
            let lane = r.lane.as_deref().unwrap_or("-");
            println!(
                "      - {:8} status={:<16} lane={lane} → {art}",
                r.target, r.status
            );
        }
    })
}

fn print_human_one(rep: &TargetReport) {
    match rep.status {
        "ok" => {
            println!(
                "    Finished `test` {} → {}",
                rep.target,
                rep.artifact_dir.as_deref().unwrap_or("?")
            );
            if let Some(lane) = &rep.lane {
                println!("      lane: {lane}");
            }
            if !rep.message.is_empty() {
                for line in rep.message.lines().take(4) {
                    println!("      {line}");
                }
            }
        }
        "skipped" => {
            println!(
                "    Skipped `test` {} → {} ({})",
                rep.target,
                rep.artifact_dir.as_deref().unwrap_or("?"),
                rep.message
            );
        }
        "failed" | "not_implemented" => {
            eprintln!(
                "    Failed `test` {} ({}) — {}",
                rep.target, rep.status, rep.message
            );
        }
        _ => {
            println!("    `test` {} — {}", rep.target, rep.message);
        }
    }
}

fn run_one(target: &str, dir: &Path) -> PfResult<TargetReport> {
    match targets::TargetId::parse(target) {
        targets::TargetId::Evm => {
            let outcome = evm::test::run_anvil_test(dir)?;
            if outcome.skipped {
                return Ok(TargetReport {
                    target: target.into(),
                    status: "skipped",
                    artifact_dir: Some(dir.display().to_string()),
                    lane: Some("anvil-statecell".into()),
                    message: outcome
                        .skip_reason
                        .unwrap_or_else(|| "host tools missing".into()),
                    detail: None,
                });
            }
            let summary = outcome
                .stdout
                .lines()
                .chain(outcome.stderr.lines())
                .find(|l| l.contains("pf-evm-test: ok"))
                .unwrap_or("pf-evm-test: ok")
                .to_string();
            Ok(TargetReport {
                target: target.into(),
                status: "ok",
                artifact_dir: Some(dir.display().to_string()),
                lane: Some("anvil-statecell".into()),
                message: summary,
                detail: Some(json!({
                    "script": outcome.script_path.display().to_string(),
                })),
            })
        }
        targets::TargetId::Solana => {
            let outcome = solana::test::run_mollusk_test(dir)?;
            let lane = detect_solana_lane(&outcome.stdout, &outcome.stderr);
            if outcome.skipped {
                return Ok(TargetReport {
                    target: target.into(),
                    status: "skipped",
                    artifact_dir: Some(dir.display().to_string()),
                    lane: Some(lane),
                    message: outcome
                        .skip_reason
                        .unwrap_or_else(|| "host tools missing".into()),
                    detail: None,
                });
            }
            let summary = outcome
                .stdout
                .lines()
                .chain(outcome.stderr.lines())
                .find(|l| l.contains("pf-solana-test: ok"))
                .unwrap_or("pf-solana-test: ok")
                .to_string();
            Ok(TargetReport {
                target: target.into(),
                status: "ok",
                artifact_dir: Some(dir.display().to_string()),
                lane: Some(lane),
                message: summary,
                detail: Some(json!({
                    "script": outcome.script_path.display().to_string(),
                })),
            })
        }
        targets::TargetId::Aleo => {
            // D8: lightweight local check — artifact present + optional leo offline run
            // of initialize(0) when leo is available; otherwise clear guidance.
            aleo_smoke(dir)
        }
        targets::TargetId::Other => Err(PfError::NotImplemented(format!(
            "target '{target}': {}",
            targets::capability_note(target)
        ))),
    }
}

fn detect_solana_lane(stdout: &str, stderr: &str) -> String {
    let combined = format!("{stdout}\n{stderr}");
    if let Some(lane) = combined.lines().find_map(|l| {
        l.split_whitespace()
            .find(|t| t.starts_with("lane="))
            .map(|t| t.trim_start_matches("lane=").to_string())
    }) {
        return lane;
    }
    if combined.contains("state-cell-shaped") {
        "state-cell-shaped".into()
    } else if combined.contains("transfer-sol") {
        "transfer-sol-cpi-gold".into()
    } else {
        "mollusk".into()
    }
}

fn aleo_smoke(dir: &Path) -> PfResult<TargetReport> {
    use crate::artifact::load_aleo_artifact;
    use crate::targets::aleo::local_run;
    use crate::tools_leo;

    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build` first)",
            dir.display()
        )));
    }
    let artifact = load_aleo_artifact(dir)?;

    match tools_leo::resolve_leo() {
        Ok(_) => {
            // Minimal structural smoke: initialize with 0 (StateCell-shaped).
            match local_run::run_local(&artifact, "initialize", &["0u64".into()]) {
                Ok(outcome) => Ok(TargetReport {
                    target: "aleo".into(),
                    status: "ok",
                    artifact_dir: Some(dir.display().to_string()),
                    lane: Some("leo-local-initialize".into()),
                    message: format!("initialize(0u64) ok program={}", artifact.program_id),
                    detail: Some(json!({
                        "programId": artifact.program_id,
                        "importSha256": outcome.import_sha256_hex,
                    })),
                }),
                Err(e) => {
                    // Non-StateCell or run failure: still report inspect-level ok? No — fail closed.
                    Err(PfError::Tool(format!(
                        "aleo local smoke failed: {e} (try `pf run -- <fn> …` for full control)"
                    )))
                }
            }
        }
        Err(_) => Ok(TargetReport {
            target: "aleo".into(),
            status: "skipped",
            artifact_dir: Some(dir.display().to_string()),
            lane: Some("leo-local".into()),
            message: format!(
                "leo not found; artifact ok program={} — install leo or use `pf run` when ready",
                artifact.program_id
            ),
            detail: Some(json!({ "programId": artifact.program_id })),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parse_comma_targets() {
        assert_eq!(
            parse_target_list(Some("evm,solana"), "aleo"),
            vec!["evm", "solana"]
        );
        assert_eq!(
            parse_target_list(Some("solana, solana,evm"), "aleo"),
            vec!["solana", "evm"]
        );
        assert_eq!(parse_target_list(None, "aleo"), vec!["aleo"]);
        assert_eq!(parse_target_list(Some("  "), "solana"), vec!["solana"]);
    }
}
