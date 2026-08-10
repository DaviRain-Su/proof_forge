use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::safety::NetworkKind;
use crate::targets::{
    self,
    aleo::network_tx::{self, DeployRequest},
};
use std::path::Path;

pub fn run(
    target_cli: Option<&str>,
    artifact_cli: Option<&Path>,
    network_cli: Option<&str>,
    endpoint: Option<&str>,
    broadcast: bool,
    key_env: Option<&str>,
    save: Option<&Path>,
    json: bool,
) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);
    targets::require_aleo(&target)?;
    let network = NetworkKind::parse(&project.resolve_network(network_cli))?;
    crate::safety::refuse_mainnet(network)?;
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build` first)",
            dir.display()
        )));
    }
    let artifact = load_aleo_artifact(&dir)?;
    let save_default = dir.join("tx");
    let save_dir = save.unwrap_or(save_default.as_path());
    let out = network_tx::deploy(DeployRequest {
        artifact: &artifact,
        network,
        endpoint,
        broadcast,
        private_key_env: key_env,
        save_dir: Some(save_dir),
    })?;
    let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
    let mut ok = PfOk::new("deploy");
    ok.target = Some(target);
    ok.network = Some(out.network.clone());
    ok.broadcast = Some(out.broadcast);
    ok.artifact_dir = Some(dir.display().to_string());
    ok.saved = Some(saved.clone());
    ok.extra = Some(serde_json::json!({
        "programId": out.program_id_stem,
        "endpoint": out.endpoint,
    }));
    emit(ok, json, || {
        println!(
            "    Finished deploy (broadcast={}): {}",
            out.broadcast,
            saved.join(", ")
        );
    })
}
