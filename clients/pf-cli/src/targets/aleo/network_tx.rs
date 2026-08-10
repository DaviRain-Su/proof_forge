//! Wave-C: deploy/execute transaction materialization (default save-only).

use crate::artifact::AleoArtifact;
use crate::error::{PfError, PfResult};
use crate::safety::{self, NetworkKind};
use crate::targets::aleo::twin_statecell;
use crate::tools_leo;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{SystemTime, UNIX_EPOCH};

pub struct NetworkTxOutcome {
    pub program_id_stem: String,
    pub network: String,
    pub endpoint: String,
    pub broadcast: bool,
    pub saved: Vec<PathBuf>,
    #[allow(dead_code)] // Retained for diagnostics and future receipt reporting.
    pub work_dir: PathBuf,
}

pub struct DeployRequest<'a> {
    pub artifact: &'a AleoArtifact,
    pub network: NetworkKind,
    pub endpoint: Option<&'a str>,
    pub broadcast: bool,
    pub private_key_env: Option<&'a str>,
    pub save_dir: Option<&'a Path>,
}

pub fn deploy(req: DeployRequest<'_>) -> PfResult<NetworkTxOutcome> {
    safety::refuse_mainnet(req.network)?;
    let key = safety::resolve_private_key_for_mode(req.broadcast, req.private_key_env)?;
    let endpoint = req
        .endpoint
        .unwrap_or_else(|| req.network.default_endpoint())
        .to_string();
    probe_endpoint(&endpoint, req.network)?;

    let leo = tools_leo::resolve_leo()?;
    let tmp = work_dir("deploy")?;
    let home = tmp.join("home");
    fs::create_dir_all(home.join(".aleo"))?;

    let stem = fresh_program_stem();
    let pkg = tmp.join(&stem);
    twin_statecell::materialize_and_verify_twin(&leo, &pkg, &stem, req.artifact)?;

    let save = req
        .save_dir
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| tmp.join("tx"));
    fs::create_dir_all(&save)?;

    let mut args: Vec<String> = vec![
        "deploy".into(),
        "--disable-update-check".into(),
        "--path".into(),
        pkg.to_string_lossy().into_owned(),
        "--network".into(),
        req.network.as_str().into(),
        "--endpoint".into(),
        endpoint.clone(),
        "--network-retries".into(),
        "2".into(),
        "--private-key".into(),
        key.clone(),
        "--skip-deploy-certificate".into(),
        "--save".into(),
        save.to_string_lossy().into_owned(),
        "-y".into(),
    ];
    if req.broadcast {
        args.push("--broadcast".into());
    }

    let out = Command::new(&leo)
        .args(&args)
        .env("HOME", &home)
        .env_remove("VIEW_KEY")
        .output()
        .map_err(|e| PfError::Network(format!("leo deploy spawn: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        return Err(PfError::Network(format!(
            "leo deploy failed (exit {:?})\n{stderr}{stdout}",
            out.status.code()
        )));
    }
    if !req.broadcast
        && !stdout.contains("will NOT be broadcast")
        && !stderr.contains("will NOT be broadcast")
    {
        // soft: leo may change wording; still require a deployment json
    }

    let saved = find_json_files(&save)?;
    if saved.is_empty() {
        return Err(PfError::Network(
            "leo deploy produced no saved JSON under --save dir".into(),
        ));
    }
    // Ensure deployment embeds not-guard when present on PF.
    if req.artifact.content.contains("not r1 into r2") {
        let any = saved.iter().any(|p| {
            fs::read_to_string(p)
                .map(|s| s.contains("not r1 into r2"))
                .unwrap_or(false)
        });
        if !any {
            return Err(PfError::Network(
                "deployment JSON missing PF not-guard in program body".into(),
            ));
        }
    }

    Ok(NetworkTxOutcome {
        program_id_stem: stem,
        network: req.network.as_str().into(),
        endpoint,
        broadcast: req.broadcast,
        saved,
        work_dir: tmp,
    })
}

pub struct ExecuteRequest<'a> {
    pub artifact: &'a AleoArtifact,
    pub network: NetworkKind,
    pub endpoint: Option<&'a str>,
    pub broadcast: bool,
    pub private_key_env: Option<&'a str>,
    pub save_dir: Option<&'a Path>,
    pub fn_name: &'a str,
    pub inputs: &'a [String],
}

pub fn execute(req: ExecuteRequest<'_>) -> PfResult<NetworkTxOutcome> {
    safety::refuse_mainnet(req.network)?;
    let key = safety::resolve_private_key_for_mode(req.broadcast, req.private_key_env)?;
    let endpoint = req
        .endpoint
        .unwrap_or_else(|| req.network.default_endpoint())
        .to_string();
    probe_endpoint(&endpoint, req.network)?;

    let leo = tools_leo::resolve_leo()?;
    let tmp = work_dir("execute")?;
    let home = tmp.join("home");
    fs::create_dir_all(home.join(".aleo"))?;

    let stem = fresh_program_stem();
    let pkg = tmp.join(&stem);
    twin_statecell::materialize_and_verify_twin(&leo, &pkg, &stem, req.artifact)?;

    let save = req
        .save_dir
        .map(|p| p.to_path_buf())
        .unwrap_or_else(|| tmp.join("ex"));
    fs::create_dir_all(&save)?;

    let mut args: Vec<String> = vec![
        "execute".into(),
        "--disable-update-check".into(),
        "--path".into(),
        pkg.to_string_lossy().into_owned(),
        "--network".into(),
        req.network.as_str().into(),
        "--endpoint".into(),
        endpoint.clone(),
        "--network-retries".into(),
        "2".into(),
        "--private-key".into(),
        key,
        "--skip-execute-proof".into(),
        "--save".into(),
        save.to_string_lossy().into_owned(),
        "-y".into(),
        req.fn_name.into(),
    ];
    for i in req.inputs {
        args.push(i.clone());
    }
    if req.broadcast {
        args.push("--broadcast".into());
    }

    let out = Command::new(&leo)
        .args(&args)
        .env("HOME", &home)
        .env_remove("VIEW_KEY")
        .output()
        .map_err(|e| PfError::Network(format!("leo execute spawn: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout);
    let stderr = String::from_utf8_lossy(&out.stderr);
    if !out.status.success() {
        return Err(PfError::Network(format!(
            "leo execute failed (exit {:?})\n{stderr}{stdout}",
            out.status.code()
        )));
    }
    let saved = find_json_files(&save)?;
    if saved.is_empty() {
        return Err(PfError::Network(
            "leo execute produced no saved JSON under --save dir".into(),
        ));
    }
    Ok(NetworkTxOutcome {
        program_id_stem: stem,
        network: req.network.as_str().into(),
        endpoint,
        broadcast: req.broadcast,
        saved,
        work_dir: tmp,
    })
}

fn probe_endpoint(endpoint: &str, network: NetworkKind) -> PfResult<()> {
    let url = format!(
        "{}/{}/block/height/latest",
        endpoint.trim_end_matches('/'),
        network.as_str()
    );
    // Use curl for zero extra deps; skip-clean if missing/unreachable is policy for scripts,
    // but pf deploy should fail clearly if user asked for network.
    let out = Command::new("curl")
        .args(["-sS", "-m", "20", &url])
        .output();
    let out = match out {
        Ok(o) => o,
        Err(_) => {
            return Err(PfError::Network(
                "curl not available to probe endpoint".into(),
            ))
        }
    };
    if !out.status.success() {
        return Err(PfError::Network(format!("endpoint probe failed: {url}")));
    }
    let body = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if body.is_empty() || !body.chars().all(|c| c.is_ascii_digit()) {
        return Err(PfError::Network(format!(
            "endpoint did not return numeric height from {url}: {body}"
        )));
    }
    Ok(())
}

fn fresh_program_stem() -> String {
    let t = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs())
        .unwrap_or(0);
    // must not contain substring "aleo"
    format!("pfsc{}", t % 1_000_000)
}

fn work_dir(tag: &str) -> PfResult<PathBuf> {
    let t = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_nanos())
        .unwrap_or(0);
    let dir = std::env::temp_dir().join(format!("pf-aleo-{tag}-{t}"));
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

fn find_json_files(dir: &Path) -> PfResult<Vec<PathBuf>> {
    let mut out = Vec::new();
    if !dir.is_dir() {
        return Ok(out);
    }
    for ent in fs::read_dir(dir)? {
        let p = ent?.path();
        if p.extension().and_then(|e| e.to_str()) == Some("json") {
            out.push(p);
        }
    }
    out.sort();
    Ok(out)
}
