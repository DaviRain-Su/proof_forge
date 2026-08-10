//! Psy host adapter: official `psy_user_cli` over PF `*.dpn.json`.
//!
//! - simulate / run → psy_user_cli simulate
//! - deploy → psy_user_cli deploy-contract (+ uuid/id receipt)
//! - execute/call → psy_user_cli call
//! - test → multi-step session harness + optional simulate sanity

pub mod call;
pub mod deploy;
pub mod simulate;
pub mod test;
