//! Shared helpers for CosmWasm mock-runtime differentials.
//!
//! Engineering only: cosmwasm-vm 3.0.9 with MockStorage / MockApi / MockQuerier.
//! Not wasmd chain execution, not formal Reference↔host closure.
//!
//! Env (required; no hard-coded product paths):
//! - `PROOF_FORGE_FIXTURES_DIR` — directory containing `<Name>/<Name>.wasm`
//!   (and optional `<Name>.cosmwasm-abi.json`) produced by the product CLI.
//!
//! Product JSON ABI subset (A1 emitter):
//! - instantiate: flat `{ "param": <decimal u64>, ... }`
//! - execute/query: message must contain `"methodName"` needle; params scanned
//!   as `"paramName": <decimal>` (byte-scan, not full JSON schema)
//! - execute/instantiate ok: `{"ok":{"messages":[],"attributes":[...],"events":[],"data":null}}`
//! - execute valued return: synthetic attribute `{"key":"result","value":"<decimal>"}`
//! - emit → attributes with event name as key, first UInt64 arg as decimal value
//! - revert → `{"error":"<ErrorDecl name>"}`
//! - query ok (MVP): `{"ok":"<decimal>"}` as UTF-8 text (NOT cosmwasm-std Binary base64)
//! - arithmetic overflow: Wasm `unreachable` trap → `VmError` (not ContractResult::Err);
//!   store is skipped so MockStorage value is unchanged

#![allow(dead_code)]

use {
    cosmwasm_std::{to_json_vec, ContractResult, Empty, Response},
    cosmwasm_vm::{
        call_execute, call_instantiate, call_query_raw,
        testing::{mock_env, mock_info, mock_instance_with_gas_limit, MockApi, MockQuerier, MockStorage},
        Instance, Storage, VmError, VmResult,
    },
    serde_json::{json, Value},
    std::{
        env, fs,
        path::{Path, PathBuf},
    },
};

/// CosmWasm gas budget high enough for Counter-style bodies + JSON builders.
pub const GAS_LIMIT: u64 = 2_000_000_000;

/// Layout marker key written by CosmWasm LowerSemanticV1 (`layoutMarkerKey`).
pub const LAYOUT_MARKER_KEY: &str = "pf:cw:v1:layout";

/// State key for field sourceId 0 (`stateKey 0`).
pub const STATE_KEY_0: &str = "pf:cw:v1:state:0";

pub type CwInstance = Instance<MockApi, MockStorage, MockQuerier>;

/// Resolve fixture root (`PROOF_FORGE_FIXTURES_DIR`).
pub fn fixtures_dir() -> PathBuf {
    env::var("PROOF_FORGE_FIXTURES_DIR")
        .map(PathBuf::from)
        .expect("PROOF_FORGE_FIXTURES_DIR must point at product build output root")
}

/// Path to `{fixtures}/{name}/{name}.wasm`.
pub fn wasm_path(name: &str) -> PathBuf {
    fixtures_dir().join(name).join(format!("{name}.wasm"))
}

/// Load product WASM bytes for a program name.
pub fn load_wasm(name: &str) -> Vec<u8> {
    let path = wasm_path(name);
    assert!(
        path.is_file(),
        "missing product WASM at {} (run scripts/cosmwasm_runtime_test.sh first)",
        path.display()
    );
    fs::read(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()))
}

/// Optional ABI sidecar path (cross-check only).
pub fn abi_path(name: &str) -> PathBuf {
    fixtures_dir()
        .join(name)
        .join(format!("{name}.cosmwasm-abi.json"))
}

/// Load and soft-assert ABI schema if the sidecar is present.
pub fn assert_abi_schema_if_present(name: &str) {
    let path = abi_path(name);
    if !path.is_file() {
        return;
    }
    let raw = fs::read_to_string(&path).expect("read abi json");
    let v: Value = serde_json::from_str(&raw).expect("abi json parse");
    assert_eq!(
        v.get("schema").and_then(|s| s.as_str()),
        Some("proof-forge-cosmwasm-abi/v1alpha1"),
        "unexpected cosmwasm-abi schema in {}",
        path.display()
    );
    assert_eq!(
        v.get("program").and_then(|s| s.as_str()),
        Some(name),
        "ABI program name mismatch"
    );
}

/// Fresh mock instance for a product WASM.
pub fn make_instance(name: &str) -> CwInstance {
    let wasm = load_wasm(name);
    mock_instance_with_gas_limit(&wasm, GAS_LIMIT)
}

pub fn creator_info() -> cosmwasm_std::MessageInfo {
    mock_info("creator", &[])
}

/// Flat instantiate JSON for a single u64 param.
pub fn instantiate_msg_u64(param: &str, value: u64) -> Vec<u8> {
    serde_json::to_vec(&json!({ param: value })).expect("instantiate msg json")
}

/// Execute/query message containing method needle + flat decimal params.
/// Shape matches A1 jsonSubset: `{"method":{...params}}` (byte-scan tolerant).
pub fn method_msg(method: &str, params: &[(&str, u64)]) -> Vec<u8> {
    let mut map = serde_json::Map::new();
    for (k, v) in params {
        map.insert((*k).to_string(), json!(v));
    }
    let body = Value::Object(map);
    serde_json::to_vec(&json!({ method: body })).expect("method msg json")
}

/// Zero-arg method message (`{"get":{}}`).
pub fn method_msg_empty(method: &str) -> Vec<u8> {
    method_msg(method, &[])
}

pub fn instantiate_ok(
    instance: &mut CwInstance,
    msg: &[u8],
) -> ContractResult<Response<Empty>> {
    call_instantiate::<_, _, _, Empty>(instance, &mock_env(), &creator_info(), msg)
        .unwrap_or_else(|e| panic!("instantiate VmError: {e:?}"))
}

pub fn execute_ok(
    instance: &mut CwInstance,
    msg: &[u8],
) -> ContractResult<Response<Empty>> {
    call_execute::<_, _, _, Empty>(instance, &mock_env(), &creator_info(), msg)
        .unwrap_or_else(|e| panic!("execute VmError: {e:?}"))
}

/// Execute that is expected to trap (overflow / assert / layout) → VmError.
pub fn execute_trap(instance: &mut CwInstance, msg: &[u8]) -> VmError {
    match call_execute::<_, _, _, Empty>(instance, &mock_env(), &creator_info(), msg) {
        Err(e) => e,
        Ok(cr) => panic!("expected Wasm trap VmError, got ContractResult {cr:?}"),
    }
}

/// Instantiate that is expected to trap (P0-2 parse overflow hardening).
pub fn instantiate_trap(instance: &mut CwInstance, msg: &[u8]) -> VmError {
    match call_instantiate::<_, _, _, Empty>(instance, &mock_env(), &creator_info(), msg) {
        Err(e) => e,
        Ok(cr) => panic!("expected Wasm trap VmError, got ContractResult {cr:?}"),
    }
}

/// Raw query JSON (MVP `{"ok":"<decimal>"}` is not cosmwasm-std Binary base64).
pub fn query_raw(instance: &mut CwInstance, msg: &[u8]) -> Vec<u8> {
    let env = to_json_vec(&mock_env()).expect("env json");
    call_query_raw(instance, &env, msg).unwrap_or_else(|e| panic!("query VmError: {e:?}"))
}

/// Parse MVP query ok decimal from raw `{"ok":"<decimal>"}`.
pub fn parse_query_ok_u64(raw: &[u8]) -> u64 {
    let v: Value = serde_json::from_slice(raw).expect("query json");
    match v {
        Value::Object(map) => {
            if let Some(Value::String(s)) = map.get("ok") {
                return s.parse::<u64>().unwrap_or_else(|_| {
                    panic!("query ok not decimal u64: {s:?} raw={}", String::from_utf8_lossy(raw))
                });
            }
            if let Some(Value::String(err)) = map.get("error") {
                panic!("query ContractResult::Err({err}) raw={}", String::from_utf8_lossy(raw));
            }
            panic!("query missing ok/error: {}", String::from_utf8_lossy(raw));
        }
        other => panic!("query not object: {other:?}"),
    }
}

pub fn query_u64(instance: &mut CwInstance, method: &str) -> u64 {
    let raw = query_raw(instance, &method_msg_empty(method));
    parse_query_ok_u64(&raw)
}

/// Require ContractResult::Ok and return Response.
pub fn expect_response_ok(cr: ContractResult<Response<Empty>>) -> Response<Empty> {
    match cr {
        ContractResult::Ok(r) => r,
        ContractResult::Err(e) => panic!("expected ContractResult::Ok, got Err({e})"),
    }
}

/// Require ContractResult::Err with exact message (revert path).
pub fn expect_contract_err(cr: ContractResult<Response<Empty>>, msg: &str) {
    match cr {
        ContractResult::Err(e) => assert_eq!(e, msg, "ContractResult::Err message"),
        ContractResult::Ok(r) => panic!("expected ContractResult::Err({msg}), got Ok({r:?})"),
    }
}

/// Find attribute value by key (order-preserving first match).
pub fn attr_value(resp: &Response<Empty>, key: &str) -> Option<String> {
    resp.attributes
        .iter()
        .find(|a| a.key == key)
        .map(|a| a.value.clone())
}

pub fn assert_attr(resp: &Response<Empty>, key: &str, value: &str) {
    let got = attr_value(resp, key).unwrap_or_else(|| {
        panic!(
            "missing attribute key={key:?}; attrs={:?}",
            resp.attributes
        )
    });
    assert_eq!(got, value, "attribute {key}");
}

/// Read state field 0 as little-endian u64 (MockStorage direct).
pub fn read_state0_u64(instance: &mut CwInstance) -> Option<u64> {
    instance
        .with_storage(|store| {
            let (val, _gas) = store.get(STATE_KEY_0.as_bytes());
            let val = val.map_err(VmError::from)?;
            Ok(val.map(|bytes| {
                assert_eq!(bytes.len(), 8, "state0 value must be 8 bytes");
                u64::from_le_bytes(bytes.try_into().unwrap())
            }))
        })
        .expect("with_storage")
}

/// Read an arbitrary state key as little-endian u64 (MockStorage direct).
pub fn read_state_u64_named(instance: &mut CwInstance, key: &str) -> Option<u64> {
    instance
        .with_storage(|store| {
            let (val, _gas) = store.get(key.as_bytes());
            let val = val.map_err(VmError::from)?;
            Ok(val.map(|bytes| {
                assert_eq!(bytes.len(), 8, "state value must be 8 bytes");
                u64::from_le_bytes(bytes.try_into().unwrap())
            }))
        })
        .expect("with_storage")
}

/// Read state field 0 as little-endian i64 (Int64 fixtures; MockStorage direct).
pub fn read_state0_i64(instance: &mut CwInstance) -> Option<i64> {
    read_state_u64_named(instance, STATE_KEY_0).map(|v| v as i64)
}

/// Read layout marker presence.
pub fn has_layout_marker(instance: &mut CwInstance) -> bool {
    instance
        .with_storage(|store| {
            let (val, _gas) = store.get(LAYOUT_MARKER_KEY.as_bytes());
            let val = val.map_err(VmError::from)?;
            Ok(val.is_some())
        })
        .expect("with_storage")
}

/// Ensure a path is a file (debug helper).
pub fn require_file(path: &Path) {
    assert!(path.is_file(), "expected file {}", path.display());
}

/// Type alias for tests that want VmResult explicitly.
pub type CwVmResult<T> = VmResult<T>;
