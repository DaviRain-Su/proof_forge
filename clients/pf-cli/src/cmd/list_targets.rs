use crate::cmd::{compiler_json, emit};
use crate::{compiler, error::PfResult, result_json::PfOk};

pub fn run(json: bool) -> PfResult<()> {
    let out = compiler::run_compiler_checked(&["list-targets", "--json"], None)?;
    let value = compiler_json(&out.stdout)?;
    let mut ok = PfOk::new("list-targets");
    ok.extra = Some(value);
    emit(ok, json, || {
        print!("{}", String::from_utf8_lossy(&out.stdout))
    })
}
