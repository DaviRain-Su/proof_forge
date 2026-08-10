use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::PfResult;
use crate::result_json::PfOk;
use crate::safety::NetworkKind;
use crate::targets::{
    self,
    aleo::network_tx::{self, DeployRequest},
};
use std::path::Path;

pub fn run(
    target_id: &str,
    dir: &Path,
    network: &str,
    endpoint: Option<&str>,
    broadcast: bool,
    key_env: Option<&str>,
    save: Option<&Path>,
    json: bool,
) -> PfResult<()> {
    targets::require_aleo(target_id)?;
    let network = NetworkKind::parse(network)?;
    crate::safety::refuse_mainnet(network)?;
    let artifact = load_aleo_artifact(dir)?;
    let out = network_tx::deploy(DeployRequest {
        artifact: &artifact,
        network,
        endpoint,
        broadcast,
        private_key_env: key_env,
        save_dir: save,
    })?;
    let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
    let mut ok = PfOk::new("deploy");
    ok.target = Some(target_id.into());
    ok.network = Some(out.network.clone());
    ok.broadcast = Some(out.broadcast);
    ok.artifact_dir = Some(dir.display().to_string());
    ok.saved = Some(saved.clone());
    ok.extra = Some(
        serde_json::json!({"programId": out.program_id_stem, "endpoint": out.endpoint, "workDir": out.work_dir}),
    );
    emit(ok, json, || {
        println!(
            "deployment saved (broadcast={}): {}",
            out.broadcast,
            saved.join(", ")
        )
    })
}
