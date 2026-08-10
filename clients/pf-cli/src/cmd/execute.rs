use crate::artifact::load_aleo_artifact;
use crate::cmd::emit;
use crate::error::{PfError, PfResult};
use crate::project::Project;
use crate::result_json::PfOk;
use crate::safety::NetworkKind;
use crate::targets::{
    self,
    aleo::network_tx::{self, ExecuteRequest},
    psy,
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
    program_id: Option<&str>,
    priority_fee: Option<u64>,
    call_args: &[String],
    json: bool,
) -> PfResult<()> {
    if call_args.is_empty() {
        return Err(PfError::Usage(
            "missing function after `--` (example: pf execute -t psy -- initialize 5)".into(),
        ));
    }
    let project = Project::discover()?;
    project.apply_toolchain_env()?;
    let target = project.resolve_target(target_cli);
    let tid = targets::TargetId::parse(&target);
    let dir = project.resolve_artifact_dir(&target, artifact_cli, None);
    if !dir.is_dir() {
        return Err(PfError::Artifact(format!(
            "artifact dir missing: {} (run `pf build` first)",
            dir.display()
        )));
    }

    if tid == targets::TargetId::Psy {
        // On-chain call via official psy_user_cli call.
        // Usage:
        //   pf execute -t psy --network testnet --broadcast --private-key-env KEY -- initialize 7
        //   pf execute -t psy --network testnet --broadcast --private-key-env KEY -- --contract-id 21 increment 5
        if !broadcast {
            return Err(PfError::Usage(
                "psy execute is on-chain only — pass --broadcast (wraps psy_user_cli call). \
                 For local DPN use `pf run` / `pf test`"
                    .into(),
            ));
        }
        let network = NetworkKind::parse(network_cli.unwrap_or("testnet"))?;
        crate::safety::refuse_mainnet(network)?;
        let save_default = dir.join("tx");
        let save_dir = save.unwrap_or(save_default.as_path());

        let mut args = call_args.to_vec();
        let mut contract_id = None;
        // optional leading: --contract-id N
        if args.len() >= 2 && (args[0] == "--contract-id" || args[0] == "-c") {
            contract_id = Some(args[1].parse::<u64>().map_err(|_| {
                PfError::Usage(format!("invalid --contract-id '{}'", args[1]))
            })?);
            args.drain(0..2);
        }
        if args.is_empty() {
            return Err(PfError::Usage(
                "missing method after `--` (example: pf execute -t psy --broadcast -- initialize 7)"
                    .into(),
            ));
        }
        let method = args[0].clone();
        let inputs = args[1..].to_vec();
        let rpc_override = endpoint.map(Path::new).filter(|p| p.is_file());

        let out = psy::call::call(psy::call::CallRequest {
            artifact_dir: &dir,
            network,
            rpc_config: rpc_override,
            private_key_env: key_env,
            contract_id,
            method: &method,
            inputs: &inputs,
            wait: true,
            save_dir,
        })?;
        let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
        let mut ok = PfOk::new("execute");
        ok.target = Some(target);
        ok.network = Some(out.network.clone());
        ok.broadcast = Some(true);
        ok.artifact_dir = Some(dir.display().to_string());
        ok.saved = Some(saved.clone());
        ok.extra = Some(serde_json::json!({
            "lane": "psy_user_cli-call",
            "contractId": out.contract_id,
            "method": out.method,
            "inputs": out.inputs,
            "stdoutTail": out.stdout_tail,
        }));
        return emit(ok, json, || {
            println!(
                "    Finished `execute` psy contract_id={} method={}",
                out.contract_id, out.method
            );
            for s in &saved {
                println!("      saved: {s}");
            }
            if !out.stdout_tail.trim().is_empty() {
                // show last few lines
                for line in out.stdout_tail.lines().rev().take(8).collect::<Vec<_>>().into_iter().rev()
                {
                    println!("      | {line}");
                }
            }
        });
    }

    targets::require_aleo(&target)?;
    let network = NetworkKind::parse(&project.resolve_network(network_cli))?;
    crate::safety::refuse_mainnet(network)?;
    let artifact = load_aleo_artifact(&dir)?;
    let save_default = dir.join("tx");
    let save_dir = save.unwrap_or(save_default.as_path());
    let fn_name = &call_args[0];
    let inputs = &call_args[1..];
    let _ = program_id;
    let _ = priority_fee;
    let out = network_tx::execute(ExecuteRequest {
        artifact: &artifact,
        network,
        endpoint,
        broadcast,
        private_key_env: key_env,
        save_dir: Some(save_dir),
        fn_name,
        inputs,
        program_id,
        priority_fee_microcredits: priority_fee,
    })?;
    let saved: Vec<String> = out.saved.iter().map(|p| p.display().to_string()).collect();
    let mut ok = PfOk::new("execute");
    ok.target = Some(target);
    ok.network = Some(out.network.clone());
    ok.broadcast = Some(out.broadcast);
    ok.artifact_dir = Some(dir.display().to_string());
    ok.saved = Some(saved.clone());
    ok.extra = Some(serde_json::json!({
        "programId": out.program_id_stem,
        "function": fn_name,
        "inputs": inputs,
    }));
    emit(ok, json, || {
        println!(
            "    Finished execute (broadcast={}): {}",
            out.broadcast,
            saved.join(", ")
        );
    })
}
