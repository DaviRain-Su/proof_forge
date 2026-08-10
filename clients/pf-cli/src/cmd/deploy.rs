use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::safety::NetworkKind;
use crate::targets::{self, aleo, evm, solana};
use std::path::Path;

pub fn run(
    target_cli: Option<&str>,
    artifact_cli: Option<&Path>,
    network_cli: Option<&str>,
    endpoint: Option<&str>,
    broadcast: bool,
    key_env: Option<&str>,
    save: Option<&Path>,
    program_id: Option<&str>,
    priority_fee: Option<u64>,
    json: bool,
) -> PfResult<()> {
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build` first)",
            dir.display()
        )));
    }

    match targets::TargetId::parse(&target) {
        targets::TargetId::Aleo => {
            // Aleo keeps historical default network=testnet for save-only packaging.
            let network = NetworkKind::parse(
                &network_cli
                    .map(|s| s.to_string())
                    .unwrap_or_else(|| project.resolve_network(None)),
            )?;
            crate::safety::refuse_mainnet(network)?;
            let artifact = load_aleo_artifact(&dir)?;
            let save_default = dir.join("tx");
            let save_dir = save.unwrap_or(save_default.as_path());
            let out = aleo::network_tx::deploy(aleo::network_tx::DeployRequest {
                artifact: &artifact,
                network,
                endpoint,
                broadcast,
                private_key_env: key_env,
                save_dir: Some(save_dir),
                program_id,
                priority_fee_microcredits: priority_fee,
            })?;
            let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
            let mut ok = PfOk::new("deploy");
            ok.target = Some(target);
            ok.network = Some(out.network.clone());
            ok.broadcast = Some(out.broadcast);
            ok.artifact_dir = Some(dir.display().to_string());
            ok.saved = Some(saved.clone());
            ok.extra = Some(serde_json::json!({
                "lane": "aleo-leo",
                "programId": out.program_id_stem,
                "endpoint": out.endpoint,
            }));
            emit(ok, json, || {
                println!(
                    "    Finished `deploy` aleo (broadcast={}): {}",
                    out.broadcast,
                    saved.join(", ")
                );
            })
        }
        targets::TargetId::Evm => {
            // EVM default network for deploy packaging is local (not public testnet).
            let net_s = network_cli.unwrap_or("local");
            let network = NetworkKind::parse(net_s)?;
            let save_default = dir.join("tx");
            let save_dir = save.unwrap_or(save_default.as_path());
            let out = evm::deploy::deploy(evm::deploy::DeployRequest {
                artifact_dir: &dir,
                network,
                endpoint,
                broadcast,
                private_key_env: key_env,
                save_dir,
                constructor_initial: 0,
            })?;
            let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
            let mut ok = PfOk::new("deploy");
            ok.target = Some(target);
            ok.network = Some(out.network.clone());
            ok.broadcast = Some(out.broadcast);
            ok.artifact_dir = Some(dir.display().to_string());
            ok.saved = Some(saved.clone());
            ok.notes = Some(out.notes.clone());
            ok.extra = Some(serde_json::json!({
                "lane": "evm-anvil-or-package",
                "contractAddress": out.contract_address,
                "endpoint": out.endpoint,
            }));
            emit(ok, json, || {
                println!(
                    "    Finished `deploy` evm (broadcast={}) → {}",
                    out.broadcast,
                    saved.join(", ")
                );
                if let Some(a) = &out.contract_address {
                    println!("      contract: {a}");
                }
                for n in &out.notes {
                    println!("      note: {n}");
                }
            })
        }
        targets::TargetId::Solana => {
            let net_s = network_cli.unwrap_or("local");
            let network = NetworkKind::parse(net_s)?;
            let save_default = dir.join("tx");
            let save_dir = save.unwrap_or(save_default.as_path());
            let out = solana::deploy::deploy(solana::deploy::DeployRequest {
                artifact_dir: &dir,
                network,
                endpoint,
                broadcast,
                private_key_env: key_env,
                save_dir,
            })?;
            let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
            let mut ok = PfOk::new("deploy");
            ok.target = Some(target);
            ok.network = Some(out.network.clone());
            ok.broadcast = Some(out.broadcast);
            ok.artifact_dir = Some(dir.display().to_string());
            ok.saved = Some(saved.clone());
            ok.notes = Some(out.notes.clone());
            ok.extra = Some(serde_json::json!({
                "lane": "solana-local-or-package",
                "programId": out.program_id,
                "endpoint": out.endpoint,
            }));
            emit(ok, json, || {
                println!(
                    "    Finished `deploy` solana (broadcast={}) → {}",
                    out.broadcast,
                    saved.join(", ")
                );
                if let Some(id) = &out.program_id {
                    println!("      programId: {id}");
                }
                for n in &out.notes {
                    println!("      note: {n}");
                }
            })
        }
        targets::TargetId::Psy => Err(PfError::NotImplemented(
            "psy: PF does not deploy DPN packages. Use official:\n  \
             psy_user_cli deploy-contract --contract-path <out>/*.dpn.json \\\n  \
             [--rpc-config ~/.psy/config.json] [--is-deploy] --private-key-env KEY\n  \
             Local VM: `pf test -t psy` / `pf run -t psy -- <method> [inputs…]` (psy_user_cli simulate)."
                .into(),
        )),
        targets::TargetId::Other => Err(PfError::NotImplemented(format!(
            "target '{target}': {}",
            targets::capability_note(&target)
        ))),
    }
}
