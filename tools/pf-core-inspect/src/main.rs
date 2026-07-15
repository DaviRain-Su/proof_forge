//! Experimental `core.v0` inspector (Seam A / LR-1).
//!
//! Zero chain SDK dependencies. Validates the export envelope fields documented
//! in `docs/superpowers/specs/2026-07-15-core-export-v0-draft.md` and recomputes
//! a content hash over the semantic bodies when present.

use anyhow::{bail, Context, Result};
use serde_json::Value;
use sha2::{Digest, Sha256};
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

fn main() -> Result<()> {
    let mut args = env::args().skip(1);
    let cmd = args.next().unwrap_or_else(|| "help".into());
    match cmd.as_str() {
        "check" => {
            let dir = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect check <export-dir>")?;
            check_export_dir(&dir)?;
            Ok(())
        }
        "compare" => {
            let left = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect compare <export-dir-a> <export-dir-b>")?;
            let right = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect compare <export-dir-a> <export-dir-b>")?;
            compare_export_dirs(&left, &right)
        }
        "hash-file" => {
            let path = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect hash-file <path>")?;
            let digest = sha256_file(&path)?;
            println!("{digest}");
            Ok(())
        }
        "help" | "-h" | "--help" => {
            print_usage();
            Ok(())
        }
        other => bail!("unknown command `{other}` (try `help`)"),
    }
}

fn print_usage() {
    eprintln!(
        "\
pf-core-inspect — experimental core.v0 reader (no chain SDKs)

USAGE:
  pf-core-inspect check <export-dir>
  pf-core-inspect compare <export-dir-a> <export-dir-b>
  pf-core-inspect hash-file <path>

Expected files in <export-dir>:
  core.v0.json
  capability-plan.v0.json
  interface.v0.json         (optional)
  export-meta.json          (optional)

compare checks:
  - both packages pass `check`
  - core.v0.json byte identity (target-neutral Core)
  - reports targetId / contentHash / used hostOpHandlers counts"
    );
}

/// Compare two Seam A packages: Core must match; plans may differ by target.
fn compare_export_dirs(left: &Path, right: &Path) -> Result<()> {
    check_export_dir(left)?;
    check_export_dir(right)?;

    let left_core = fs::read(left.join("core.v0.json"))
        .with_context(|| format!("read `{}`", left.join("core.v0.json").display()))?;
    let right_core = fs::read(right.join("core.v0.json"))
        .with_context(|| format!("read `{}`", right.join("core.v0.json").display()))?;
    let core_same = left_core == right_core;

    let left_plan: Value = serde_json::from_str(&fs::read_to_string(
        left.join("capability-plan.v0.json"),
    )?)?;
    let right_plan: Value = serde_json::from_str(&fs::read_to_string(
        right.join("capability-plan.v0.json"),
    )?)?;
    let left_target = left_plan
        .get("targetId")
        .and_then(Value::as_str)
        .unwrap_or("?");
    let right_target = right_plan
        .get("targetId")
        .and_then(Value::as_str)
        .unwrap_or("?");
    let left_handlers = left_plan
        .get("hostOpHandlers")
        .and_then(Value::as_array)
        .map(|a| a.len())
        .unwrap_or(0);
    let right_handlers = right_plan
        .get("hostOpHandlers")
        .and_then(Value::as_array)
        .map(|a| a.len())
        .unwrap_or(0);
    let left_catalog = left_plan
        .get("targetHostOpCatalog")
        .and_then(Value::as_array)
        .map(|a| a.len())
        .unwrap_or(0);
    let right_catalog = right_plan
        .get("targetHostOpCatalog")
        .and_then(Value::as_array)
        .map(|a| a.len())
        .unwrap_or(0);

    let left_hash = read_content_hash(left)?;
    let right_hash = read_content_hash(right)?;

    println!("pf-core-inspect compare:");
    println!(
        "  left:  {} target={} usedHostOps={} catalog={} contentHash={}",
        left.display(),
        left_target,
        left_handlers,
        left_catalog,
        left_hash
    );
    println!(
        "  right: {} target={} usedHostOps={} catalog={} contentHash={}",
        right.display(),
        right_target,
        right_handlers,
        right_catalog,
        right_hash
    );
    println!(
        "  core.v0.json identical: {}",
        if core_same { "yes" } else { "NO" }
    );

    if !core_same {
        bail!(
            "core.v0.json differs between packages (Core must be target-neutral for the same module)"
        );
    }
    println!("pf-core-inspect: compare ok (Core match)");
    Ok(())
}

fn read_content_hash(dir: &Path) -> Result<String> {
    let meta_path = dir.join("export-meta.json");
    if !meta_path.exists() {
        return Ok("missing".into());
    }
    let meta: Value = serde_json::from_str(&fs::read_to_string(meta_path)?)?;
    Ok(meta
        .get("contentHash")
        .and_then(Value::as_str)
        .unwrap_or("unset")
        .to_string())
}

fn check_export_dir(dir: &Path) -> Result<()> {
    let core_path = dir.join("core.v0.json");
    let core_text = fs::read_to_string(&core_path)
        .with_context(|| format!("missing `{}`", core_path.display()))?;
    let core: Value = serde_json::from_str(&core_text)
        .with_context(|| format!("invalid JSON in `{}`", core_path.display()))?;

    let schema = core
        .get("coreSchema")
        .and_then(Value::as_str)
        .context("core.v0.json missing string `coreSchema`")?;
    if schema != "core.v0" {
        bail!("unexpected coreSchema `{schema}` (want core.v0)");
    }
    let version = core
        .get("schemaVersion")
        .context("core.v0.json missing `schemaVersion`")?;
    ensure_version_zero(version, "core.v0.json schemaVersion")?;

    let module = core
        .get("module")
        .and_then(Value::as_object)
        .context("core.v0.json missing object `module`")?;
    let name = module
        .get("name")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .context("core.v0.json module.name must be non-empty")?;
    let functions = module
        .get("functions")
        .and_then(Value::as_array)
        .context("core.v0.json module.functions must be an array")?;

    let cap_path = dir.join("capability-plan.v0.json");
    if cap_path.exists() {
        let cap_text = fs::read_to_string(&cap_path)?;
        let cap: Value = serde_json::from_str(&cap_text)
            .with_context(|| format!("invalid JSON in `{}`", cap_path.display()))?;
        let cap_schema = cap
            .get("capabilityPlanSchema")
            .and_then(Value::as_str)
            .context("capability-plan.v0.json missing capabilityPlanSchema")?;
        if cap_schema != "capability-plan.v0" {
            bail!("unexpected capabilityPlanSchema `{cap_schema}`");
        }
        let _target = cap
            .get("targetId")
            .and_then(Value::as_str)
            .filter(|s| !s.is_empty())
            .context("capability-plan.v0.json missing non-empty targetId")?;
        let handlers = cap
            .get("hostOpHandlers")
            .and_then(Value::as_array)
            .context("capability-plan.v0.json missing hostOpHandlers array")?;
        for (i, handler) in handlers.iter().enumerate() {
            check_handler_entry(handler, &format!("hostOpHandlers[{i}]"))?;
        }
        if let Some(catalog) = cap.get("targetHostOpCatalog") {
            let catalog = catalog
                .as_array()
                .context("targetHostOpCatalog must be an array")?;
            for (i, handler) in catalog.iter().enumerate() {
                check_handler_entry(handler, &format!("targetHostOpCatalog[{i}]"))?;
            }
        }
        if let Some(reqs) = cap.get("requirements") {
            let reqs = reqs.as_array().context("requirements must be an array")?;
            for (i, req) in reqs.iter().enumerate() {
                let _cap = req
                    .get("capability")
                    .and_then(Value::as_str)
                    .with_context(|| format!("requirements[{i}].capability missing"))?;
                let _op = req
                    .get("operation")
                    .and_then(Value::as_str)
                    .with_context(|| format!("requirements[{i}].operation missing"))?;
            }
        }
    }

    let iface_path = dir.join("interface.v0.json");
    if iface_path.exists() {
        let iface_text = fs::read_to_string(&iface_path)?;
        let iface: Value = serde_json::from_str(&iface_text)
            .with_context(|| format!("invalid JSON in `{}`", iface_path.display()))?;
        let schema = iface
            .get("interfaceSchema")
            .and_then(Value::as_str)
            .context("interface.v0.json missing interfaceSchema")?;
        if schema != "interface.v0" {
            bail!("unexpected interfaceSchema `{schema}`");
        }
        let _eps = iface
            .get("entrypoints")
            .and_then(Value::as_array)
            .context("interface.v0.json missing entrypoints array")?;
    }

    let meta_path = dir.join("export-meta.json");
    if meta_path.exists() {
        let meta_text = fs::read_to_string(&meta_path)?;
        let meta: Value = serde_json::from_str(&meta_text)
            .with_context(|| format!("invalid JSON in `{}`", meta_path.display()))?;
        if let Some(declared) = meta.get("contentHash").and_then(Value::as_str) {
            let mut bodies = core_text.as_bytes().to_vec();
            if cap_path.exists() {
                bodies.extend(fs::read(&cap_path)?);
            }
            let actual = format!("{:x}", Sha256::digest(&bodies));
            if declared != actual && declared != "unset" && !declared.is_empty() {
                // LR-1a may write "unset" until Lean hashes the package.
                bail!(
                    "export-meta contentHash mismatch: declared={declared} actual={actual}"
                );
            }
        }
    }

    println!(
        "pf-core-inspect: ok module={name} functions={} coreSchema=core.v0",
        functions.len()
    );
    Ok(())
}

fn check_handler_entry(handler: &Value, label: &str) -> Result<()> {
    let available = handler
        .get("available")
        .and_then(Value::as_bool)
        .with_context(|| format!("{label}.available must be bool"))?;
    if !available {
        bail!("{label} is not available (fail-closed)");
    }
    let _handler = handler
        .get("handler")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .with_context(|| format!("{label}.handler must be non-empty"))?;
    let _id = handler
        .get("id")
        .with_context(|| format!("{label}.id missing"))?;
    Ok(())
}

fn ensure_version_zero(value: &Value, label: &str) -> Result<()> {
    match value {
        Value::Number(n) if n.as_u64() == Some(0) || n.as_i64() == Some(0) => Ok(()),
        Value::String(s) if s == "0" => Ok(()),
        other => bail!("{label} must be 0 or \"0\", got {other}"),
    }
}

fn sha256_file(path: &Path) -> Result<String> {
    let data = fs::read(path).with_context(|| format!("read `{}`", path.display()))?;
    Ok(format!("{:x}", Sha256::digest(data)))
}
