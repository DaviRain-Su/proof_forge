pub mod build;
pub mod check;
pub mod clean;
pub mod deploy;
pub mod doctor;
pub mod execute;
pub mod inspect;
pub mod list_targets;
pub mod local_run;
pub mod new;
pub mod verify;
pub mod version;

use crate::error::{PfError, PfResult};
use crate::result_json::{print_ok, PfOk};

pub fn emit(ok: PfOk, json: bool, human: impl FnOnce()) -> PfResult<()> {
    if json {
        print_ok(&ok);
    } else {
        human();
    }
    Ok(())
}

pub fn compiler_json(output: &[u8]) -> PfResult<serde_json::Value> {
    serde_json::from_slice(output)
        .map_err(|e| PfError::Compiler(format!("compiler returned invalid JSON: {e}")))
}
