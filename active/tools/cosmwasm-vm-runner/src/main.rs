use cosmwasm_vm::testing::{instantiate, execute, query, mock_env, mock_info, mock_instance};
use cosmwasm_std::Empty;
use serde_json::Value;
use std::env;
use std::process;

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() != 2 {
        eprintln!("Usage: cosmwasm-vm-runner <wasm-file>");
        process::exit(2);
    }
    let wasm_path = &args[1];

    let wasm = std::fs::read(wasm_path).expect("failed to read wasm file");
    let mut instance = mock_instance(&wasm, &[]);

    let env = mock_env();
    let info = mock_info("creator", &[]);

    // Instantiate with empty message
    let init_msg: Value = serde_json::from_str("{}").expect("invalid init JSON");
    let _init_response: cosmwasm_std::Response<Empty> = instantiate(&mut instance, env.clone(), info.clone(), init_msg)
        .unwrap();

    // Execute increment with empty message
    let exec_msg: Value = serde_json::from_str("{}").expect("invalid execute JSON");
    let _exec_response: cosmwasm_std::Response<Empty> = execute(&mut instance, env.clone(), info.clone(), exec_msg)
        .unwrap();

    // Query count
    let query_msg: Value = serde_json::from_str(r#"{"get_count":{}}"#).expect("invalid query JSON");
    let query_response = query(&mut instance, env.clone(), query_msg)
        .unwrap();

    let count: Value = serde_json::from_slice(&query_response).expect("invalid JSON response");
    let actual = count["count"].as_str().expect("count field missing");
    assert_eq!(actual, "1", "expected count 1 after one increment, got {}", actual);

    println!("[cosmwasm-vm-runner] Counter lifecycle passed: count = {}", actual);
}
