//! Wave-B: PF bytecode local VM via Leo runner imports pin.

use crate::artifact::AleoArtifact;
use crate::error::{PfError, PfResult};
use crate::tools_leo;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct LocalRunOutcome {
    pub stdout: String,
    pub stderr: String,
    pub import_sha256_hex: String,
}

pub fn run_local(pf: &AleoArtifact, fn_name: &str, inputs: &[String]) -> PfResult<LocalRunOutcome> {
    let leo = tools_leo::resolve_leo()?;
    let tmp = tempfile_dir()?;
    let home = tmp.join("home");
    fs::create_dir_all(home.join(".aleo"))?;

    let stem = &pf.program_stem;
    let dep = tmp.join(stem);
    let runner = tmp.join("runner");

    // Dependency package metadata only.
    leo_new(&leo, &tmp, stem, &home)?;
    write_structural_dep_src(&dep.join("src").join("main.leo"), stem)?;
    leo_build(&leo, &dep, &home)?;

    leo_new(&leo, &tmp, "runner", &home)?;
    leo_add_local(&leo, &runner, &dep, &format!("{stem}.aleo"), &home)?;

    let imports = runner.join("build").join("imports");
    fs::create_dir_all(&imports)?;
    let import_aleo = imports.join(format!("{stem}.aleo"));
    fs::copy(&pf.aleo_path, &import_aleo)?;

    let fq = format!("{stem}.aleo::{fn_name}");
    let mut cmd = Command::new(&leo);
    cmd.args(["run", "--offline", "--disable-update-check", "--path"])
        .arg(&runner)
        .args([
            "--network",
            "testnet",
            "--endpoint",
            "http://127.0.0.1:9",
            "--network-retries",
            "0",
            &fq,
        ])
        .args(inputs)
        .env("HOME", &home)
        .env_remove("PRIVATE_KEY")
        .env_remove("VIEW_KEY")
        .env_remove("NETWORK")
        .env_remove("ENDPOINT");

    let out = cmd
        .output()
        .map_err(|e| PfError::Tool(format!("leo run spawn failed: {e}")))?;
    let stdout = String::from_utf8_lossy(&out.stdout).to_string();
    let stderr = String::from_utf8_lossy(&out.stderr).to_string();
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "leo run failed (exit {:?})\n{stderr}{stdout}",
            out.status.code()
        )));
    }

    // Import integrity: must remain PF bytes.
    let import_bytes = fs::read(&import_aleo)?;
    let import_sha = crate::artifact::sha256_hex(&import_bytes);
    if import_sha != pf.sha256_hex {
        return Err(PfError::Artifact(
            "imports bytecode diverged from PF emission after leo run".into(),
        ));
    }
    if !String::from_utf8_lossy(&import_bytes).contains("not r1 into r2")
        && pf.content.contains("not r1 into r2")
    {
        return Err(PfError::Artifact("imports lost PF not-guard shape".into()));
    }

    // cleanup best-effort
    let _ = fs::remove_dir_all(&tmp);

    Ok(LocalRunOutcome {
        stdout,
        stderr,
        import_sha256_hex: import_sha,
    })
}

fn tempfile_dir() -> PfResult<PathBuf> {
    let base = std::env::temp_dir().join(format!("pf-aleo-local-{}", std::process::id()));
    // unique
    let dir = base.join(format!(
        "{}",
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .map(|d| d.as_nanos())
            .unwrap_or(0)
    ));
    fs::create_dir_all(&dir)?;
    Ok(dir)
}

fn leo_new(leo: &Path, parent: &Path, name: &str, home: &Path) -> PfResult<()> {
    // Capture output so default `pf run` stays quiet (setup chatter is not product UX).
    let out = Command::new(leo)
        .current_dir(parent)
        .args(["new", name, "--disable-update-check"])
        .env("HOME", home)
        .output()
        .map_err(|e| PfError::Tool(format!("leo new: {e}")))?;
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "leo new {name} failed (exit {:?})\n{}{}",
            out.status.code(),
            String::from_utf8_lossy(&out.stderr),
            String::from_utf8_lossy(&out.stdout)
        )));
    }
    Ok(())
}

fn leo_build(leo: &Path, pkg: &Path, home: &Path) -> PfResult<()> {
    let out = Command::new(leo)
        .args(["build", "--offline", "--disable-update-check", "--path"])
        .arg(pkg)
        .args(["--network", "testnet"])
        .env("HOME", home)
        .output()
        .map_err(|e| PfError::Tool(format!("leo build: {e}")))?;
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "leo build failed (exit {:?})\n{}{}",
            out.status.code(),
            String::from_utf8_lossy(&out.stderr),
            String::from_utf8_lossy(&out.stdout)
        )));
    }
    Ok(())
}

fn leo_add_local(leo: &Path, runner: &Path, dep: &Path, name: &str, home: &Path) -> PfResult<()> {
    let out = Command::new(leo)
        .args(["add", "--disable-update-check", "--path"])
        .arg(runner)
        .arg("--local")
        .arg(dep)
        .arg(name)
        .env("HOME", home)
        .output()
        .map_err(|e| PfError::Tool(format!("leo add: {e}")))?;
    if !out.status.success() {
        return Err(PfError::Tool(format!(
            "leo add --local failed (exit {:?})\n{}{}",
            out.status.code(),
            String::from_utf8_lossy(&out.stderr),
            String::from_utf8_lossy(&out.stdout)
        )));
    }
    Ok(())
}

fn write_structural_dep_src(path: &Path, stem: &str) -> PfResult<()> {
    if let Some(p) = path.parent() {
        fs::create_dir_all(p)?;
    }
    // Minimal twin for dependency package compile only.
    let src = crate::targets::aleo::twin_statecell::statecell_twin_leo_source(stem);
    fs::write(path, src)?;
    Ok(())
}
