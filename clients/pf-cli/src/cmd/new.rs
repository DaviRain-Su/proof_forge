use crate::cmd::emit;
use crate::error::PfResult;
use crate::project::{self, DEFAULT_TARGET};
use crate::result_json::PfOk;
use std::path::PathBuf;

pub fn run(name: &str, target: Option<&str>, path: Option<&PathBuf>, json: bool) -> PfResult<()> {
    let target = target.unwrap_or(DEFAULT_TARGET);
    let dir = path.cloned().unwrap_or_else(|| PathBuf::from(name));
    project::write_new_project(&dir, name, target)?;
    let mut ok = PfOk::new("new");
    ok.target = Some(target.into());
    ok.extra = Some(serde_json::json!({
        "path": dir.display().to_string(),
        "config": dir.join(project::CONFIG_NAME).display().to_string(),
    }));
    emit(ok, json, || {
        println!("created {}", dir.display());
        println!("  config: {}/{}", dir.display(), project::CONFIG_NAME);
        println!("  default-target: {target}");
        println!("  depends-on: proof-forge-next (compiler binary) + ProofForgeV2 (source gate)");
        println!();
        println!(
            "note: this is not a Lake package; set PROOF_FORGE_CLI or toolchain.compiler-path"
        );
        println!();
        println!("next:");
        println!("  export PROOF_FORGE_CLI=/path/to/proof-forge-next");
        println!("  cd {}", dir.display());
        println!("  pf build");
        match target {
            "aleo" => {
                println!("  pf run -- initialize 5u64");
                println!("  pf deploy");
            }
            "evm" => {
                println!("  pf test              # local Anvil");
                println!("  pf deploy            # save-only package (tx/)");
                println!("  # pf deploy --broadcast --network local --private-key-env KEY");
            }
            "solana" => {
                println!("  pf test              # local Mollusk (StateCell-shaped)");
                println!("  pf deploy            # save-only package (tx/)");
                println!(
                    "  # pf deploy --broadcast --network local --endpoint http://127.0.0.1:8899"
                );
            }
            _ => {
                println!("  pf build -t <target>");
            }
        }
    })
}
