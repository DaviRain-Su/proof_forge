//! One-shot cosmwasm-vm mock runner for `pf run -t cosmwasm -- <method> [u64…]`.
//!
//! Engineering only. Not wasmd / mainnet / formal.
//!
//! Env:
//!   PF_CW_WASM          — path to product .wasm (required)
//!   PF_CW_ABI           — optional *.cosmwasm-abi.json (mode selection)
//!   PF_CW_METHOD        — method name (required)
//!   PF_CW_MODE          — instantiate | execute | query | auto (default auto)
//!   PF_CW_ARGS          — space-separated u64 decimals (positional → a0,a1,…)
//!   PF_CW_SENDER        — MessageInfo.sender (default creator)
//!
//! Protocol (A1 jsonSubset):
//!   instantiate: flat `{param: decimal, …}` or `{}`
//!   execute/query: `{"method":{…params}}`
//!
//! Exit 0 on success; non-zero on trap / ContractResult::Err / usage.

use {
    cosmwasm_std::{to_json_vec, ContractResult, Empty, Response},
    cosmwasm_vm::{
        call_execute, call_instantiate, call_query_raw,
        testing::{mock_env, mock_info, mock_instance_with_gas_limit},
        VmError,
    },
    serde_json::{json, Value},
    std::{
        env, fs,
        path::PathBuf,
        process,
    },
};

const GAS_LIMIT: u64 = 2_000_000_000;

fn die(msg: impl AsRef<str>) -> ! {
    eprintln!("cw-oneshot: FAIL: {}", msg.as_ref());
    process::exit(1);
}

fn env_req(name: &str) -> String {
    env::var(name).unwrap_or_else(|_| die(format!("missing env {name}")))
}

fn env_opt(name: &str) -> Option<String> {
    env::var(name).ok().filter(|s| !s.is_empty())
}

/// ABI method entry: name + mode.
#[derive(Debug, Clone)]
struct AbiMethod {
    name: String,
    mode: String,
    arg_names: Vec<String>,
}

fn load_abi_methods(path: &str) -> Vec<AbiMethod> {
    let text = fs::read_to_string(path).unwrap_or_else(|e| die(format!("read abi {path}: {e}")));
    let v: Value = serde_json::from_str(&text).unwrap_or_else(|e| die(format!("abi json: {e}")));
    let methods = v
        .get("methods")
        .and_then(|m| m.as_array())
        .cloned()
        .unwrap_or_default();
    methods
        .into_iter()
        .filter_map(|m| {
            let name = m.get("name")?.as_str()?.to_string();
            let mode = m
                .get("mode")
                .and_then(|x| x.as_str())
                .unwrap_or("execute")
                .to_string();
            let arg_names = m
                .get("args")
                .and_then(|a| a.as_array())
                .map(|arr| {
                    arr.iter()
                        .filter_map(|a| a.get("name").and_then(|n| n.as_str()).map(str::to_string))
                        .collect()
                })
                .unwrap_or_default();
            Some(AbiMethod {
                name,
                mode,
                arg_names,
            })
        })
        .collect()
}

fn resolve_mode(method: &str, mode_req: &str, abi: &[AbiMethod]) -> String {
    if mode_req != "auto" {
        return mode_req.to_string();
    }
    if let Some(m) = abi.iter().find(|m| m.name == method) {
        return match m.mode.as_str() {
            "instantiate" | "init" => "instantiate".into(),
            "query" | "view" => "query".into(),
            _ => "execute".into(),
        };
    }
    // Heuristics when ABI missing.
    if method == "init" || method.starts_with("init") {
        return "instantiate".into();
    }
    if method.starts_with("get")
        || method.starts_with("view")
        || method.starts_with("query")
        || matches!(
            method,
            "seconds" | "height" | "answer" | "dump" | "selfIsContract" | "callerIsContract"
        )
    {
        return "query".into();
    }
    "execute".into()
}

fn parse_u64_args(s: &str) -> Vec<u64> {
    if s.trim().is_empty() {
        return vec![];
    }
    s.split_whitespace()
        .map(|tok| {
            let cleaned = tok.trim_end_matches("u64").trim_end_matches('u');
            cleaned
                .parse::<u64>()
                .unwrap_or_else(|_| die(format!("arg must be u64 decimal, got {tok}")))
        })
        .collect()
}

/// Build flat instantiate JSON. Prefer ABI arg names; else a0,a1… or single
/// conventional names when one arg.
fn instantiate_msg(arg_names: &[String], args: &[u64]) -> Vec<u8> {
    if args.is_empty() {
        return br"{}".to_vec();
    }
    let mut map = serde_json::Map::new();
    for (i, v) in args.iter().enumerate() {
        let key = if i < arg_names.len() {
            arg_names[i].clone()
        } else if args.len() == 1 {
            // Common PF fixtures use `initial`.
            "initial".into()
        } else {
            format!("a{i}")
        };
        map.insert(key, json!(v));
    }
    serde_json::to_vec(&Value::Object(map)).expect("instantiate json")
}

fn method_msg(method: &str, arg_names: &[String], args: &[u64]) -> Vec<u8> {
    let mut map = serde_json::Map::new();
    for (i, v) in args.iter().enumerate() {
        let key = if i < arg_names.len() {
            arg_names[i].clone()
        } else {
            format!("a{i}")
        };
        map.insert(key, json!(v));
    }
    let body = Value::Object(map);
    serde_json::to_vec(&json!({ method: body })).expect("method json")
}

fn print_response(resp: &Response<Empty>) {
    // Prefer synthetic `result` attribute (valued entry return).
    if let Some(a) = resp.attributes.iter().find(|a| a.key == "result") {
        println!("{}", a.value);
        return;
    }
    if !resp.attributes.is_empty() {
        let parts: Vec<String> = resp
            .attributes
            .iter()
            .map(|a| format!("{}={}", a.key, a.value))
            .collect();
        println!("{}", parts.join(" "));
        return;
    }
    if !resp.messages.is_empty() {
        println!("ok messages={}", resp.messages.len());
        return;
    }
    println!("ok");
}

type CwInst = cosmwasm_vm::Instance<
    cosmwasm_vm::testing::MockApi,
    cosmwasm_vm::testing::MockStorage,
    cosmwasm_vm::testing::MockQuerier,
>;

/// Auto-instantiate. Tries empty `{}` first, then `{"initial":0}` for the
/// common PF UInt64 pad constructor. Rebuilds the mock instance on each
/// attempt so a failed first try cannot poison storage.
fn ensure_instantiated(
    wasm: &[u8],
    info: &cosmwasm_std::MessageInfo,
) -> CwInst {
    let attempts: [&[u8]; 2] = [br"{}", br#"{"initial":0}"#];
    let mut last_err = String::new();
    for msg in attempts {
        let mut instance = mock_instance_with_gas_limit(wasm, GAS_LIMIT);
        match call_instantiate::<_, _, _, Empty>(&mut instance, &mock_env(), info, msg) {
            Ok(ContractResult::Ok(_)) => return instance,
            Ok(ContractResult::Err(e)) => last_err = format!("ContractResult::Err({e})"),
            Err(e) => last_err = format!("VmError: {e:?}"),
        }
    }
    die(format!(
        "auto-instantiate failed ({last_err}); try explicit: pf run -t cosmwasm -- init <args>"
    ));
}

fn print_query(raw: &[u8]) {
    let v: Value = serde_json::from_slice(raw).unwrap_or_else(|e| {
        die(format!(
            "query json: {e}; raw={}",
            String::from_utf8_lossy(raw)
        ))
    });
    match v {
        Value::Object(map) => {
            if let Some(Value::String(s)) = map.get("ok") {
                // MVP: decimal string, or JSON-array string for aggregates.
                println!("{s}");
                return;
            }
            if let Some(ok) = map.get("ok") {
                println!("{ok}");
                return;
            }
            if let Some(Value::String(err)) = map.get("error") {
                die(format!("query Err({err})"));
            }
            die(format!(
                "query missing ok/error: {}",
                String::from_utf8_lossy(raw)
            ));
        }
        other => die(format!("query not object: {other:?}")),
    }
}

fn main() {
    let wasm_path = PathBuf::from(env_req("PF_CW_WASM"));
    let method = env_req("PF_CW_METHOD");
    let mode_req = env_opt("PF_CW_MODE").unwrap_or_else(|| "auto".into());
    let args = parse_u64_args(&env_opt("PF_CW_ARGS").unwrap_or_default());
    let sender = env_opt("PF_CW_SENDER").unwrap_or_else(|| "creator".into());

    let abi_methods = env_opt("PF_CW_ABI")
        .map(|p| load_abi_methods(&p))
        .unwrap_or_default();
    let mode = resolve_mode(&method, &mode_req, &abi_methods);
    let arg_names = abi_methods
        .iter()
        .find(|m| m.name == method)
        .map(|m| m.arg_names.clone())
        .unwrap_or_default();

    let wasm = fs::read(&wasm_path).unwrap_or_else(|e| {
        die(format!("read wasm {}: {e}", wasm_path.display()))
    });
    let info = mock_info(&sender, &[]);

    match mode.as_str() {
        "instantiate" => {
            let mut instance = mock_instance_with_gas_limit(&wasm, GAS_LIMIT);
            let msg = instantiate_msg(&arg_names, &args);
            match call_instantiate::<_, _, _, Empty>(&mut instance, &mock_env(), &info, &msg) {
                Ok(ContractResult::Ok(resp)) => print_response(&resp),
                Ok(ContractResult::Err(e)) => die(format!("instantiate Err({e})")),
                Err(VmError::RuntimeErr { msg, .. }) => die(format!("instantiate trap: {msg}")),
                Err(e) => die(format!("instantiate VmError: {e:?}")),
            }
        }
        "execute" => {
            // Fresh mock instance: auto-instantiate before mutate.
            let mut instance = ensure_instantiated(&wasm, &info);
            let msg = method_msg(&method, &arg_names, &args);
            match call_execute::<_, _, _, Empty>(&mut instance, &mock_env(), &info, &msg) {
                Ok(ContractResult::Ok(resp)) => print_response(&resp),
                Ok(ContractResult::Err(e)) => die(format!("execute Err({e})")),
                Err(VmError::RuntimeErr { msg, .. }) => die(format!("execute trap: {msg}")),
                Err(e) => die(format!("execute VmError: {e:?}")),
            }
        }
        "query" => {
            let mut instance = ensure_instantiated(&wasm, &info);
            let msg = method_msg(&method, &arg_names, &args);
            let env_bytes = to_json_vec(&mock_env()).expect("env json");
            match call_query_raw(&mut instance, &env_bytes, &msg) {
                Ok(raw) => print_query(&raw),
                Err(e) => die(format!("query VmError: {e:?}")),
            }
        }
        other => die(format!("unknown mode {other} (want instantiate|execute|query|auto)")),
    }
    eprintln!("cw-oneshot: ok mode={mode} method={method}");
}
