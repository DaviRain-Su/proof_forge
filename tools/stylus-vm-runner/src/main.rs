use anyhow::{anyhow, bail, Context, Result};
use serde_json::{json, Value};
use sha3::{Digest, Keccak256};
use std::collections::BTreeMap;
use std::env;
use std::fs;
use wasmtime::{Caller, Engine, Linker, Memory, Module, Store};

#[derive(Default)]
struct HostState {
    storage: BTreeMap<[u8; 32], [u8; 32]>,
    cache: BTreeMap<[u8; 32], [u8; 32]>,
    sender: [u8; 20],
    value: [u8; 32],
    contract: [u8; 20],
    block_number: u64,
    block_timestamp: u64,
    calldata: Vec<u8>,
    result: Vec<u8>,
    return_data: Vec<u8>,
    mock_calls: BTreeMap<[u8; 20], (i32, Vec<u8>)>,
    trace: Vec<Value>,
}

fn memory(caller: &mut Caller<'_, HostState>) -> wasmtime::Result<Memory> {
    caller
        .get_export("memory")
        .and_then(|export| export.into_memory())
        .ok_or_else(|| wasmtime::Error::msg("Stylus module does not export memory"))
}

fn read<const N: usize>(caller: &mut Caller<'_, HostState>, ptr: i32) -> wasmtime::Result<[u8; N]> {
    if ptr < 0 {
        return Err(wasmtime::Error::msg(format!("negative Wasm pointer {ptr}")));
    }
    let memory = memory(caller)?;
    let mut bytes = [0_u8; N];
    memory
        .read(&*caller, ptr as usize, &mut bytes)
        .map_err(|error| {
            wasmtime::Error::msg(format!("Wasm memory read is out of bounds: {error}"))
        })?;
    Ok(bytes)
}

fn read_vec(caller: &mut Caller<'_, HostState>, ptr: i32, len: i32) -> wasmtime::Result<Vec<u8>> {
    if ptr < 0 || len < 0 {
        return Err(wasmtime::Error::msg(format!(
            "negative Wasm pointer/length {ptr}/{len}"
        )));
    }
    let memory = memory(caller)?;
    let mut bytes = vec![0_u8; len as usize];
    memory
        .read(&*caller, ptr as usize, &mut bytes)
        .map_err(|error| {
            wasmtime::Error::msg(format!("Wasm memory read is out of bounds: {error}"))
        })?;
    Ok(bytes)
}

fn write(caller: &mut Caller<'_, HostState>, ptr: i32, bytes: &[u8]) -> wasmtime::Result<()> {
    if ptr < 0 {
        return Err(wasmtime::Error::msg(format!("negative Wasm pointer {ptr}")));
    }
    let memory = memory(caller)?;
    memory.write(caller, ptr as usize, bytes).map_err(|error| {
        wasmtime::Error::msg(format!("Wasm memory write is out of bounds: {error}"))
    })
}

fn hex(bytes: &[u8]) -> String {
    const DIGITS: &[u8; 16] = b"0123456789abcdef";
    let mut output = String::with_capacity(bytes.len() * 2);
    for byte in bytes {
        output.push(DIGITS[(byte >> 4) as usize] as char);
        output.push(DIGITS[(byte & 0x0f) as usize] as char);
    }
    output
}

fn hex_nibble(byte: u8) -> Result<u8> {
    match byte {
        b'0'..=b'9' => Ok(byte - b'0'),
        b'a'..=b'f' => Ok(byte - b'a' + 10),
        b'A'..=b'F' => Ok(byte - b'A' + 10),
        _ => bail!("invalid hex digit `{}`", byte as char),
    }
}

fn parse_hex<const N: usize>(text: &str, label: &str) -> Result<[u8; N]> {
    let text = text.strip_prefix("0x").unwrap_or(text);
    if text.len() != N * 2 {
        bail!("{label} must contain exactly {} hex bytes", N);
    }
    let mut output = [0_u8; N];
    for (index, pair) in text.as_bytes().chunks_exact(2).enumerate() {
        output[index] = hex_nibble(pair[0])? * 16 + hex_nibble(pair[1])?;
    }
    Ok(output)
}

fn parse_value(text: &str) -> Result<[u8; 32]> {
    if text.starts_with("0x") || text.len() == 64 {
        return parse_hex(text, "msg.value");
    }
    let value: u128 = text
        .parse()
        .context("msg.value must be decimal u128 or 32-byte hex")?;
    let mut output = [0_u8; 32];
    output[16..].copy_from_slice(&value.to_be_bytes());
    Ok(output)
}

fn parse_hex_vec(text: &str, label: &str) -> Result<Vec<u8>> {
    let text = text.strip_prefix("0x").unwrap_or(text);
    if text.len() % 2 != 0 {
        bail!("{label} must contain an even number of hex digits");
    }
    text.as_bytes()
        .chunks_exact(2)
        .map(|pair| Ok(hex_nibble(pair[0])? * 16 + hex_nibble(pair[1])?))
        .collect()
}

fn register_hooks(linker: &mut Linker<HostState>) -> wasmtime::Result<()> {
    linker.func_wrap(
        "vm_hooks",
        "read_args",
        |mut caller: Caller<'_, HostState>, ptr: i32| -> wasmtime::Result<()> {
            let calldata = caller.data().calldata.clone();
            write(&mut caller, ptr, &calldata)?;
            caller
                .data_mut()
                .trace
                .push(json!({"event":"read_args","value":hex(&calldata)}));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "storage_load_bytes32",
        |mut caller: Caller<'_, HostState>, key_ptr: i32, value_ptr: i32| -> wasmtime::Result<()> {
            let key = read::<32>(&mut caller, key_ptr)?;
            let value = caller
                .data()
                .cache
                .get(&key)
                .or_else(|| caller.data().storage.get(&key))
                .copied()
                .unwrap_or([0_u8; 32]);
            write(&mut caller, value_ptr, &value)?;
            caller
                .data_mut()
                .trace
                .push(json!({"event":"storage_load","slot":hex(&key),"value":hex(&value)}));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "storage_cache_bytes32",
        |mut caller: Caller<'_, HostState>, key_ptr: i32, value_ptr: i32| -> wasmtime::Result<()> {
            let key = read::<32>(&mut caller, key_ptr)?;
            let value = read::<32>(&mut caller, value_ptr)?;
            caller.data_mut().cache.insert(key, value);
            caller
                .data_mut()
                .trace
                .push(json!({"event":"storage_cache","slot":hex(&key),"value":hex(&value)}));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "storage_flush_cache",
        |mut caller: Caller<'_, HostState>, clear: i32| {
            let writes = caller.data().cache.len();
            let pending = caller.data().cache.clone();
            caller.data_mut().storage.extend(pending);
            if clear != 0 {
                caller.data_mut().cache.clear();
            }
            caller
                .data_mut()
                .trace
                .push(json!({"event":"storage_flush","writes":writes,"clear":clear != 0}));
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "write_result",
        |mut caller: Caller<'_, HostState>, ptr: i32, len: i32| -> wasmtime::Result<()> {
            let result = read_vec(&mut caller, ptr, len)?;
            caller.data_mut().result = result.clone();
            caller
                .data_mut()
                .trace
                .push(json!({"event":"write_result","value":hex(&result)}));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "msg_sender",
        |mut caller: Caller<'_, HostState>, ptr: i32| -> wasmtime::Result<()> {
            let sender = caller.data().sender;
            write(&mut caller, ptr, &sender)
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "msg_value",
        |mut caller: Caller<'_, HostState>, ptr: i32| -> wasmtime::Result<()> {
            let value = caller.data().value;
            write(&mut caller, ptr, &value)
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "contract_address",
        |mut caller: Caller<'_, HostState>, ptr: i32| -> wasmtime::Result<()> {
            let contract = caller.data().contract;
            write(&mut caller, ptr, &contract)
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "block_number",
        |caller: Caller<'_, HostState>| caller.data().block_number as i64,
    )?;
    linker.func_wrap(
        "vm_hooks",
        "block_timestamp",
        |caller: Caller<'_, HostState>| caller.data().block_timestamp as i64,
    )?;
    linker.func_wrap(
        "vm_hooks",
        "native_keccak256",
        |mut caller: Caller<'_, HostState>, ptr: i32, len: i32, output: i32| -> wasmtime::Result<()> {
            let input = read_vec(&mut caller, ptr, len)?;
            let digest = Keccak256::digest(&input);
            write(&mut caller, output, &digest)?;
            caller.data_mut().trace.push(json!({
                "event":"native_keccak256", "input":hex(&input), "output":hex(&digest)
            }));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "emit_log",
        |mut caller: Caller<'_, HostState>, ptr: i32, len: i32, topics: i32| -> wasmtime::Result<()> {
            if !(0..=4).contains(&topics) {
                return Err(wasmtime::Error::msg(format!("invalid Stylus topic count {topics}")));
            }
            let data = read_vec(&mut caller, ptr, len)?;
            if data.len() < topics as usize * 32 {
                return Err(wasmtime::Error::msg("Stylus log buffer is shorter than its topics"));
            }
            caller.data_mut().trace.push(json!({
                "event":"emit_log", "topics":topics, "value":hex(&data)
            }));
            Ok(())
        },
    )?;
    linker.func_wrap(
        "vm_hooks",
        "call_contract",
        |mut caller: Caller<'_, HostState>, address_ptr: i32, calldata_ptr: i32,
         calldata_len: i32, value_ptr: i32, gas: i64, return_len_ptr: i32| -> wasmtime::Result<i32> {
            let address = read::<20>(&mut caller, address_ptr)?;
            let calldata = read_vec(&mut caller, calldata_ptr, calldata_len)?;
            let value = read::<32>(&mut caller, value_ptr)?;
            let (status, output) = caller.data().mock_calls.get(&address).cloned().unwrap_or((1, Vec::new()));
            write(&mut caller, return_len_ptr, &(output.len() as u32).to_le_bytes())?;
            caller.data_mut().return_data = output.clone();
            caller.data_mut().trace.push(json!({"event":"call_contract","address":hex(&address),
                "calldata":hex(&calldata),"value":hex(&value),"gas":gas as u64,
                "status":status,"returnData":hex(&output)}));
            Ok(status)
        },
    )?;
    for name in ["static_call_contract", "delegate_call_contract"] {
        linker.func_wrap(
            "vm_hooks", name,
            move |mut caller: Caller<'_, HostState>, address_ptr: i32, calldata_ptr: i32,
             calldata_len: i32, gas: i64, return_len_ptr: i32| -> wasmtime::Result<i32> {
                let address = read::<20>(&mut caller, address_ptr)?;
                let calldata = read_vec(&mut caller, calldata_ptr, calldata_len)?;
                let (status, output) = caller.data().mock_calls.get(&address).cloned().unwrap_or((1, Vec::new()));
                write(&mut caller, return_len_ptr, &(output.len() as u32).to_le_bytes())?;
                caller.data_mut().return_data = output.clone();
                caller.data_mut().trace.push(json!({"event":name,"address":hex(&address),
                    "calldata":hex(&calldata),"gas":gas as u64,"status":status,
                    "returnData":hex(&output)}));
                Ok(status)
            },
        )?;
    }
    linker.func_wrap(
        "vm_hooks", "read_return_data",
        |mut caller: Caller<'_, HostState>, dest: i32, offset: i32, size: i32| -> wasmtime::Result<i32> {
            if offset < 0 || size < 0 { return Err(wasmtime::Error::msg("negative return-data range")); }
            let start = offset as usize;
            let output = if start >= caller.data().return_data.len() { Vec::new() } else {
                let end = (start + size as usize).min(caller.data().return_data.len());
                caller.data().return_data[start..end].to_vec()
            };
            write(&mut caller, dest, &output)?;
            caller.data_mut().trace.push(json!({"event":"read_return_data","offset":offset,
                "requested":size,"copied":output.len(),"value":hex(&output)}));
            Ok(output.len() as i32)
        },
    )?;
    Ok(())
}

fn main() -> Result<()> {
    let args: Vec<String> = env::args().skip(1).collect();
    if args.len() < 2 {
        bail!("usage: stylus-vm-runner <module.wasm> [context options] <export> [export ...]");
    }
    let mut host = HostState::default();
    let mut exports = Vec::new();
    let mut index = 1;
    while index < args.len() {
        let option = &args[index];
        let value = |index: usize| -> Result<&str> {
            args.get(index + 1)
                .map(String::as_str)
                .with_context(|| format!("{option} requires a value"))
        };
        match option.as_str() {
            "--sender" => {
                host.sender = parse_hex(value(index)?, "sender")?;
                index += 2;
            }
            "--value" => {
                host.value = parse_value(value(index)?)?;
                index += 2;
            }
            "--contract" => {
                host.contract = parse_hex(value(index)?, "contract")?;
                index += 2;
            }
            "--calldata" => {
                host.calldata = parse_hex_vec(value(index)?, "calldata")?;
                index += 2;
            }
            "--block-number" => {
                host.block_number = value(index)?.parse().context("invalid block number")?;
                index += 2;
            }
            "--block-timestamp" => {
                host.block_timestamp = value(index)?.parse().context("invalid block timestamp")?;
                index += 2;
            }
            "--storage" => {
                let binding = value(index)?;
                let (slot, word) = binding
                    .split_once('=')
                    .context("storage must be SLOT=WORD")?;
                host.storage.insert(
                    parse_hex(slot, "storage slot")?,
                    parse_hex(word, "storage word")?,
                );
                index += 2;
            }
            "--mock-call" => {
                let binding = value(index)?;
                let (address, response) = binding.split_once('=').context("mock call must be ADDRESS=STATUS:HEX")?;
                let (status, output) = response.split_once(':').context("mock call response must be STATUS:HEX")?;
                host.mock_calls.insert(parse_hex(address, "mock call address")?,
                    (status.parse().context("invalid mock call status")?, parse_hex_vec(output, "mock call output")?));
                index += 2;
            }
            "--invoke" => {
                exports.push(value(index)?.to_owned());
                index += 2;
            }
            unknown if unknown.starts_with("--") => bail!("unknown option `{unknown}`"),
            export => {
                exports.push(export.to_owned());
                index += 1;
            }
        }
    }
    if exports.is_empty() {
        bail!("at least one export must be invoked");
    }
    let wasm = fs::read(&args[0]).with_context(|| format!("failed to read {}", args[0]))?;
    let engine = Engine::default();
    let module = Module::new(&engine, wasm)
        .map_err(|error| anyhow!("failed to compile Stylus Wasm: {error}"))?;
    let mut linker = Linker::new(&engine);
    register_hooks(&mut linker).map_err(|error| anyhow!("failed to register vm_hooks: {error}"))?;
    let mut store = Store::new(&engine, host);
    let instance = linker
        .instantiate(&mut store, &module)
        .map_err(|error| anyhow!("failed to instantiate Stylus Wasm with vm_hooks: {error}"))?;

    let mut calls = Vec::new();
    for export in &exports {
        store.data_mut().result.clear();
        let status = if export == "user_entrypoint" {
            let calldata_len = store.data().calldata.len() as i32;
            let function = instance
                .get_typed_func::<i32, i32>(&mut store, export)
                .map_err(|error| anyhow!("missing Stylus entrypoint `{export}`: {error}"))?;
            function.call(&mut store, calldata_len)
        } else {
            let function = instance
                .get_typed_func::<(), i32>(&mut store, export)
                .map_err(|error| anyhow!("missing zero-argument i32 export `{export}`: {error}"))?;
            function.call(&mut store, ())
        }
        .map_err(|error| anyhow!("Stylus export `{export}` trapped: {error}"))?;
        if status != 0 {
            store.data_mut().cache.clear();
        }
        calls.push(json!({"export":export,"status":status,"result":hex(&store.data().result)}));
    }

    let storage = store
        .data()
        .storage
        .iter()
        .map(|(key, value)| (hex(key), Value::String(hex(value))))
        .collect::<serde_json::Map<_, _>>();
    println!(
        "{}",
        json!({
            "calls": calls,
            "storage": storage,
            "result": hex(&store.data().result),
            "trace": store.data().trace,
        })
    );
    Ok(())
}
