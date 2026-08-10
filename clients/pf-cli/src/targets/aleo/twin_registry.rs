//! Aleo packaging twin registry (D10).
//!
//! Deploy packaging requires a **registered structural twin** that Leo can
//! rebuild to bytecode exact-matching PF Instructions (after program-id rewrite).
//! Silent approximate twins are forbidden.
//!
//! v0 registered ids:
//! - `statecell-v1` — initialize + increment + not-guard + dropped re-read
//!
//! To extend (product decision):
//! 1. Add a new twin source generator + `looks_like_*` predicate.
//! 2. Register it in [`REGISTRY`] with a stable id.
//! 3. Expand acceptance tests; never fall through to "close enough".

use super::twin_statecell;

/// Stable registry id for the StateCell packaging twin.
pub const TWIN_STATECELL_V1: &str = "statecell-v1";

#[derive(Debug, Clone, Copy)]
pub struct TwinEntry {
    pub id: &'static str,
    #[allow(dead_code)]
    pub summary: &'static str,
    pub detect: fn(&str) -> bool,
}

/// Ordered registry. First match wins.
pub static REGISTRY: &[TwinEntry] = &[TwinEntry {
    id: TWIN_STATECELL_V1,
    summary: "StateCell-shaped: initialize/increment, not-guard, dropped get.or_use re-read",
    detect: twin_statecell::looks_like_statecell_instructions,
}];

/// Detect which registered twin (if any) matches PF Aleo Instructions text.
pub fn detect_twin_id(instructions: &str) -> Option<&'static str> {
    REGISTRY
        .iter()
        .find(|e| (e.detect)(instructions))
        .map(|e| e.id)
}

/// Human list for error messages / `pf` guidance.
pub fn registered_ids() -> Vec<&'static str> {
    REGISTRY.iter().map(|e| e.id).collect()
}

pub fn require_registered(instructions: &str) -> Result<&'static str, String> {
    detect_twin_id(instructions).ok_or_else(|| {
        format!(
            "no registered Aleo packaging twin matches this program \
             (registered: {}); refuse silent approximate twins — see D10",
            registered_ids().join(", ")
        )
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn statecell_template_detects() {
        // Minimal shape markers used by looks_like_statecell_instructions.
        let sample = r#"
mapping pf_state_0: as u8 => u64;
mapping initialized: as u8 => bool;
function initialize:
function increment:
    not r1 into r2
    get.or_use pf_state_0[0u8] 0u64 into r3
"#;
        assert_eq!(detect_twin_id(sample), Some(TWIN_STATECELL_V1));
    }

    #[test]
    fn unknown_fails_closed() {
        assert!(require_registered("program foo.aleo;").is_err());
    }
}
