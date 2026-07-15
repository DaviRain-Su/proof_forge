//! CLI front-end for `pf-core` (Seam A / D-057).
//! Zero chain SDK dependencies.

use anyhow::{Context, Result};
use pf_core::{compare_packages, ExportPackage};
use std::env;
use std::path::PathBuf;

fn main() -> Result<()> {
    let mut args = env::args().skip(1);
    let cmd = args.next().unwrap_or_else(|| "help".into());
    match cmd.as_str() {
        "check" => {
            let dir = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect check <export-dir>")?;
            let pkg = ExportPackage::load(&dir)?;
            println!(
                "pf-core-inspect: ok module={} functions={} target={} usedHostOps={} catalog={} coreSchema=core.v0",
                pkg.module_name(),
                pkg.function_count(),
                pkg.target_id(),
                pkg.used_host_op_count(),
                pkg.plan.target_host_op_catalog.len()
            );
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
            let left_pkg = ExportPackage::load(&left)?;
            let right_pkg = ExportPackage::load(&right)?;
            let report = compare_packages(&left_pkg, &right_pkg)?;
            println!("pf-core-inspect compare:\n{}", report.summary());
            println!("pf-core-inspect: compare ok (Core match)");
            Ok(())
        }
        "hash-file" => {
            let path = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect hash-file <path>")?;
            let data = std::fs::read(&path)
                .with_context(|| format!("read `{}`", path.display()))?;
            use sha2::{Digest, Sha256};
            println!("{:x}", Sha256::digest(&data));
            Ok(())
        }
        "summary" => {
            let dir = args
                .next()
                .map(PathBuf::from)
                .context("usage: pf-core-inspect summary <export-dir>")?;
            let pkg = ExportPackage::load(&dir)?;
            println!("module: {}", pkg.module_name());
            println!("target: {}", pkg.target_id());
            println!("functions: {}", pkg.function_count());
            println!("capabilities: {}", pkg.plan.capabilities.join(", "));
            println!("usedHostOps: {}", pkg.used_host_op_count());
            for h in &pkg.plan.host_op_handlers {
                println!("  - {} -> {}", h.id.render(), h.handler);
            }
            println!("targetCatalog: {}", pkg.plan.target_host_op_catalog.len());
            if let Some(iface) = &pkg.interface {
                println!(
                    "interface: {} entrypoints={}",
                    iface.contract_name,
                    iface.entrypoints.len()
                );
                for ep in &iface.entrypoints {
                    println!(
                        "  - {} ({}) -> {}",
                        ep.name, ep.mutability, ep.ret_type
                    );
                }
            }
            println!("contentHash: {}", pkg.content_hash());
            let walk = pkg.walk();
            for line in walk.lines() {
                println!("{line}");
            }
            let ready = pkg.dual_run_readiness();
            for line in ready.lines() {
                println!("{line}");
            }
            Ok(())
        }
        "help" | "-h" | "--help" => {
            print_usage();
            Ok(())
        }
        other => anyhow::bail!("unknown command `{other}` (try `help`)"),
    }
}

fn print_usage() {
    eprintln!(
        "\
pf-core-inspect — experimental core.v0 reader (via pf-core; no chain SDKs)

USAGE:
  pf-core-inspect check <export-dir>
  pf-core-inspect summary <export-dir>
  pf-core-inspect compare <export-dir-a> <export-dir-b>
  pf-core-inspect hash-file <path>"
    );
}
