//! Psy host adapter: official `psy_user_cli` over PF `*.dpn.json`.
//!
//! - simulate / run → psy_user_cli simulate
//! - deploy → psy_user_cli deploy-contract
//! - test → multi-step session harness + official single-call sanity
//!
//! Engineering only — OutputSet deployable remains false.

pub mod deploy;
pub mod simulate;
pub mod test;
