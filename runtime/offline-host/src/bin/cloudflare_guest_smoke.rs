use std::collections::HashMap;
use std::env;
use std::path::PathBuf;

use anyhow::{anyhow, ensure, Context, Result};
use wasmtime::{Caller, Engine, Extern, Linker, Memory, Module, Store, TypedFunc};

const DEFAULT_WASM_PATH: &str = "Examples/cloudflare-workers-spike/build/counter.wasm";

fn main() -> Result<()> {
    let wasm_path = match env::args_os().nth(1) {
        Some(path) => PathBuf::from(path),
        None => PathBuf::from(DEFAULT_WASM_PATH),
    };
    run(&wasm_path)
}

#[derive(Default)]
struct HostState {
    kv: HashMap<String, String>,
    logs: Vec<String>,
}

fn run(wasm_path: &PathBuf) -> Result<()> {
    let engine = Engine::default();
    let module = Module::from_file(&engine, wasm_path)
        .with_context(|| format!("failed to compile {}", wasm_path.display()))?;
    let mut linker = Linker::new(&engine);
    define_host_imports(&mut linker)?;

    let mut store = Store::new(&engine, HostState::default());
    let instance = linker
        .instantiate(&mut store, &module)
        .context("failed to instantiate Cloudflare guest module")?;
    let memory = instance
        .get_memory(&mut store, "memory")
        .ok_or_else(|| anyhow!("guest does not export `memory`"))?;
    let malloc = instance
        .get_typed_func::<i32, i32>(&mut store, "malloc")
        .context("guest does not export `malloc(size) -> ptr`")?;
    let fetch = instance
        .get_typed_func::<(i32, i32), i32>(&mut store, "fetch")
        .context("guest does not export `fetch(ptr, len) -> ptr`")?;

    let cases = [
        ("initialize", "OK\n0"),
        ("get", "OK\n0"),
        ("increment", "OK\n1"),
        ("increment", "OK\n2"),
        ("get", "OK\n2"),
    ];
    for (method, expected) in cases {
        let response = call_fetch(&mut store, memory, &malloc, &fetch, method)?;
        println!("cloudflare guest {method}: {}", response.escape_default());
        ensure!(
            response == expected,
            "{method} returned {:?}, expected {:?}",
            response,
            expected
        );
    }

    println!("cloudflare guest smoke: ok");
    Ok(())
}

fn define_host_imports(linker: &mut Linker<HostState>) -> Result<()> {
    linker.func_wrap(
        "env",
        "kv_get",
        |mut caller: Caller<'_, HostState>, key_ptr: i32, key_len: i32| -> Result<i32> {
            let key = read_utf8(&mut caller, key_ptr, key_len)?;
            let Some(value) = caller.data().kv.get(&key).cloned() else {
                return Ok(0);
            };
            let mut value_bytes = value.into_bytes();
            value_bytes.push(0);
            let ptr = guest_malloc(&mut caller, value_bytes.len())?;
            write_memory(&mut caller, ptr, &value_bytes)?;
            Ok(ptr)
        },
    )?;
    linker.func_wrap(
        "env",
        "kv_put",
        |mut caller: Caller<'_, HostState>,
         key_ptr: i32,
         key_len: i32,
         value_ptr: i32,
         value_len: i32|
         -> Result<()> {
            let key = read_utf8(&mut caller, key_ptr, key_len)?;
            let value = read_utf8(&mut caller, value_ptr, value_len)?;
            caller.data_mut().kv.insert(key, value);
            Ok(())
        },
    )?;
    linker.func_wrap(
        "env",
        "console_log",
        |mut caller: Caller<'_, HostState>, msg_ptr: i32, msg_len: i32| -> Result<()> {
            let message = read_utf8(&mut caller, msg_ptr, msg_len)?;
            caller.data_mut().logs.push(message);
            Ok(())
        },
    )?;
    linker.func_wrap(
        "env",
        "get_caller",
        |mut caller: Caller<'_, HostState>, buf_ptr: i32, buf_len: i32| -> Result<i32> {
            let caller_id = b"127.0.0.1";
            let buf_len = usize::try_from(buf_len).context("caller buffer length is negative")?;
            let write_len = caller_id.len().min(buf_len);
            write_memory(&mut caller, buf_ptr, &caller_id[..write_len])?;
            Ok(i32::try_from(write_len).context("caller id length does not fit i32")?)
        },
    )?;
    Ok(())
}

fn call_fetch(
    store: &mut Store<HostState>,
    memory: Memory,
    malloc: &TypedFunc<i32, i32>,
    fetch: &TypedFunc<(i32, i32), i32>,
    method: &str,
) -> Result<String> {
    let request = format!("{method}\n");
    let ptr = malloc
        .call(&mut *store, usize_to_i32(request.len(), "request length")?)
        .context("guest malloc failed for request")?;
    memory
        .write(
            &mut *store,
            ptr_to_usize(ptr, "request pointer")?,
            request.as_bytes(),
        )
        .context("failed to write guest request")?;
    let response_ptr = fetch
        .call(
            &mut *store,
            (ptr, usize_to_i32(request.len(), "request length")?),
        )
        .context("guest fetch failed")?;
    read_c_string(store, memory, response_ptr)
}

fn guest_malloc(caller: &mut Caller<'_, HostState>, len: usize) -> Result<i32> {
    let malloc = caller
        .get_export("malloc")
        .and_then(Extern::into_func)
        .ok_or_else(|| anyhow!("guest does not export `malloc`"))?
        .typed::<i32, i32>(&mut *caller)
        .context("guest malloc has unexpected type")?;
    let ptr = malloc
        .call(&mut *caller, usize_to_i32(len, "allocation length")?)
        .context("guest malloc failed")?;
    ensure!(ptr != 0, "guest malloc returned null");
    Ok(ptr)
}

fn memory(caller: &mut Caller<'_, HostState>) -> Result<Memory> {
    caller
        .get_export("memory")
        .and_then(Extern::into_memory)
        .ok_or_else(|| anyhow!("guest does not export `memory`"))
}

fn read_utf8(caller: &mut Caller<'_, HostState>, ptr: i32, len: i32) -> Result<String> {
    let bytes = read_memory(caller, ptr, len)?;
    String::from_utf8(bytes).context("guest string is not valid UTF-8")
}

fn read_memory(caller: &mut Caller<'_, HostState>, ptr: i32, len: i32) -> Result<Vec<u8>> {
    let ptr = ptr_to_usize(ptr, "memory pointer")?;
    let len = ptr_to_usize(len, "memory length")?;
    let memory = memory(caller)?;
    let mut bytes = vec![0; len];
    memory
        .read(&mut *caller, ptr, &mut bytes)
        .context("failed to read guest memory")?;
    Ok(bytes)
}

fn write_memory(caller: &mut Caller<'_, HostState>, ptr: i32, bytes: &[u8]) -> Result<()> {
    let ptr = ptr_to_usize(ptr, "memory pointer")?;
    let memory = memory(caller)?;
    memory
        .write(&mut *caller, ptr, bytes)
        .context("failed to write guest memory")
}

fn read_c_string(store: &mut Store<HostState>, memory: Memory, ptr: i32) -> Result<String> {
    let ptr = ptr_to_usize(ptr, "response pointer")?;
    let data = memory.data(&mut *store);
    let tail = data
        .get(ptr..)
        .ok_or_else(|| anyhow!("response pointer {ptr} is outside guest memory"))?;
    let end = tail
        .iter()
        .position(|byte| *byte == 0)
        .ok_or_else(|| anyhow!("guest response is not null-terminated"))?;
    String::from_utf8(tail[..end].to_vec()).context("guest response is not valid UTF-8")
}

fn ptr_to_usize(value: i32, label: &str) -> Result<usize> {
    usize::try_from(value).with_context(|| format!("{label} must be non-negative"))
}

fn usize_to_i32(value: usize, label: &str) -> Result<i32> {
    i32::try_from(value).with_context(|| format!("{label} does not fit i32"))
}
