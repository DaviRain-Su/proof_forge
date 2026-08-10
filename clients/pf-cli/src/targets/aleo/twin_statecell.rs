//! Structural Leo twin that lowers to the same Instructions as PF StateCell.
//!
//! Empirically locked against Leo 4.0.2: `assert(!guard)` → `not`; increment
//! keeps dropped `get.or_use` re-read. See Wave-C acceptance.

use crate::artifact::{rewrite_program_id, AleoArtifact};
use crate::error::{PfError, PfResult};
use std::fs;
use std::path::Path;
use std::process::Command;

/// Leo source template. `{program_stem}` is substituted (no `.aleo` suffix).
pub fn statecell_twin_leo_source(program_stem: &str) -> String {
    format!(
        r#"// pf twin: exact Instructions match for PF StateCell (Leo 4.0.2).
// Product authority remains PF .aleo; this source is packaging-only.
program {program_stem}.aleo {{
    @noupgrade
    constructor() {{}}
    mapping pf_state_0: u8 => u64;
    mapping initialized: u8 => bool;
    fn initialize(public p0: u64) -> Final {{
        return final {{
            let r1: bool = Mapping::get_or_use(initialized, 0u8, false);
            assert(!r1);
            Mapping::set(pf_state_0, 0u8, p0);
            Mapping::set(initialized, 0u8, true);
        }};
    }}
    fn increment(public p0: u64) -> Final {{
        return final {{
            let r1: u64 = Mapping::get_or_use(pf_state_0, 0u8, 0u64);
            let r2: u64 = r1 + p0;
            Mapping::set(pf_state_0, 0u8, r2);
            let r3: u64 = Mapping::get_or_use(pf_state_0, 0u8, 0u64);
        }};
    }}
}}
"#
    )
}

/// True when PF artifact matches the StateCell Instructions shape (header-agnostic).
pub fn looks_like_statecell_instructions(content: &str) -> bool {
    content.contains("mapping pf_state_0:")
        && content.contains("mapping initialized:")
        && content.contains("function initialize:")
        && content.contains("function increment:")
        && content.contains("not r1 into r2")
        && content.contains("get.or_use pf_state_0[0u8] 0u64 into r3")
}

/// Build twin package at `pkg_dir` named `program_stem`, verify exact match to PF
/// content rewritten to that stem. Returns path to `build/main.aleo`.
pub fn materialize_and_verify_twin(
    leo: &Path,
    pkg_dir: &Path,
    program_stem: &str,
    pf: &AleoArtifact,
) -> PfResult<std::path::PathBuf> {
    if !looks_like_statecell_instructions(&pf.content) {
        return Err(PfError::Artifact(
            "pf deploy v0 only supports StateCell-shaped Aleo Instructions \
(initialize/increment + not-guard + dropped re-read); other programs fail closed"
                .into(),
        ));
    }

    fs::create_dir_all(pkg_dir.join("src"))?;
    let program_json = serde_json::json!({
        "program": format!("{program_stem}.aleo"),
        "version": "0.1.0",
        "description": "pf packaging twin",
        "license": "MIT",
        "leo": "4.0.2",
        "dependencies": null,
        "dev_dependencies": null
    });
    fs::write(
        pkg_dir.join("program.json"),
        serde_json::to_string_pretty(&program_json).unwrap(),
    )?;
    fs::write(
        pkg_dir.join("src").join("main.leo"),
        statecell_twin_leo_source(program_stem),
    )?;

    let status = Command::new(leo)
        .args(["build", "--offline", "--disable-update-check", "--path"])
        .arg(pkg_dir)
        .args(["--network", "testnet"])
        .status()
        .map_err(|e| PfError::Tool(format!("leo build spawn failed: {e}")))?;
    if !status.success() {
        return Err(PfError::Tool(format!(
            "leo build twin failed (exit {:?})",
            status.code()
        )));
    }

    let main_aleo = pkg_dir.join("build").join("main.aleo");
    if !main_aleo.is_file() {
        return Err(PfError::Tool(
            "leo build twin missing build/main.aleo".into(),
        ));
    }
    let twin = fs::read_to_string(&main_aleo)?;
    let expected = rewrite_program_id(&pf.content, &pf.program_stem, program_stem);
    if twin != expected {
        return Err(PfError::Artifact(format!(
            "twin bytecode does not exact-match PF Instructions after id rewrite \
(program_stem={program_stem})"
        )));
    }
    Ok(main_aleo)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn template_has_assert_not() {
        let s = statecell_twin_leo_source("statecell");
        assert!(s.contains("assert(!r1)"));
        assert!(s.contains("program statecell.aleo"));
    }
}
