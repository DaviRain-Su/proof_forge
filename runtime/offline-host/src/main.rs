use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use sha2::{Digest, Sha256};
use wasmtime::{Caller, Engine, Extern, Instance, Linker, Module, Store};

const DEFAULT_HEAP_BASE: u32 = 60_000;
const WASM_PAGE_SIZE: u64 = 65_536;
const DEFAULT_FUEL_PER_RECEIPT: u64 = 10_000_000_000;

fn main() -> Result<()> {
    let config = Config::parse(env::args().skip(1))?;
    run(config)
}

#[derive(Debug)]
struct Config {
    module_path: PathBuf,
    exports: Vec<String>,
    repeat: u32,
    heap_base: u32,
    input: Vec<u8>,
    inputs: Option<Vec<Vec<u8>>>,
    current_account_id: Vec<u8>,
    predecessor_account_id: Vec<u8>,
    signer_account_id: Vec<u8>,
    attached_deposit: u64,
    block_index: u64,
    block_timestamp: u64,
    epoch_height: u64,
    random_seed: Vec<u8>,
    promise_result_u64: u64,
    fuel_per_receipt: u64,
}

impl Config {
    fn parse<I>(args: I) -> Result<Self>
    where
        I: IntoIterator<Item = String>,
    {
        let mut positionals = Vec::new();
        let mut repeat = 1;
        let mut heap_base = DEFAULT_HEAP_BASE;
        let mut input = Vec::new();
        let mut inputs = None;
        let mut current_account_id = b"proof-forge.testnet".to_vec();
        let mut predecessor_account_id = b"alice.testnet".to_vec();
        let mut signer_account_id = b"alice.testnet".to_vec();
        let mut attached_deposit: u64 = 0;
        let mut block_index = 0;
        let mut block_timestamp = 0;
        let mut epoch_height = 0;
        let mut random_seed = vec![0; 32];
        let mut promise_result_u64 = 42;
        let mut fuel_per_receipt = DEFAULT_FUEL_PER_RECEIPT;

        let mut args = args.into_iter().peekable();
        while let Some(arg) = args.next() {
            match arg.as_str() {
                "run" if positionals.is_empty() => {}
                "-h" | "--help" => {
                    print_usage();
                    std::process::exit(0);
                }
                "--repeat" => {
                    repeat = take_arg(&mut args, "--repeat")?
                        .parse()
                        .context("--repeat must be a positive integer")?;
                    if repeat == 0 {
                        bail!("--repeat must be greater than 0");
                    }
                }
                "--heap-base" => {
                    heap_base = parse_u32(&take_arg(&mut args, "--heap-base")?, "--heap-base")?;
                }
                "--input-hex" => {
                    input = parse_hex(&take_arg(&mut args, "--input-hex")?)?;
                }
                "--inputs-hex" => {
                    inputs = Some(parse_hex_sequence(&take_arg(&mut args, "--inputs-hex")?)?);
                }
                "--input-file" => {
                    let path = take_arg(&mut args, "--input-file")?;
                    input = fs::read(&path).with_context(|| format!("failed to read {path}"))?;
                }
                "--current-account-id" => {
                    current_account_id = take_arg(&mut args, "--current-account-id")?.into_bytes();
                }
                "--predecessor-account-id" => {
                    predecessor_account_id =
                        take_arg(&mut args, "--predecessor-account-id")?.into_bytes();
                }
                "--signer-account-id" => {
                    signer_account_id = take_arg(&mut args, "--signer-account-id")?.into_bytes();
                }
                "--attached-deposit" => {
                    attached_deposit = take_arg(&mut args, "--attached-deposit")?
                        .parse()
                        .context("--attached-deposit must be a non-negative integer")?;
                }
                "--block-index" => {
                    block_index = take_arg(&mut args, "--block-index")?
                        .parse()
                        .context("--block-index must be a non-negative integer")?;
                }
                "--block-timestamp" => {
                    block_timestamp = take_arg(&mut args, "--block-timestamp")?
                        .parse()
                        .context("--block-timestamp must be a non-negative integer")?;
                }
                "--epoch-height" => {
                    epoch_height = take_arg(&mut args, "--epoch-height")?
                        .parse()
                        .context("--epoch-height must be a non-negative integer")?;
                }
                "--random-seed-hex" => {
                    random_seed = parse_hex(&take_arg(&mut args, "--random-seed-hex")?)?;
                    if random_seed.len() != 32 {
                        bail!("--random-seed-hex must decode to exactly 32 bytes");
                    }
                }
                "--promise-result-u64" => {
                    promise_result_u64 = take_arg(&mut args, "--promise-result-u64")?
                        .parse()
                        .context("--promise-result-u64 must be a non-negative integer")?;
                }
                "--fuel" => {
                    fuel_per_receipt = take_arg(&mut args, "--fuel")?
                        .parse()
                        .context("--fuel must be a positive integer")?;
                    if fuel_per_receipt == 0 {
                        bail!("--fuel must be greater than 0");
                    }
                }
                _ if arg.starts_with('-') => bail!("unknown option `{arg}`"),
                _ => positionals.push(arg),
            }
        }

        if positionals.len() < 2 {
            print_usage();
            bail!("expected <module.wat|module.wasm> and at least one <export>");
        }

        if inputs.is_some() && !input.is_empty() {
            bail!("--inputs-hex cannot be combined with --input-hex or --input-file");
        }
        if let Some(call_inputs) = &inputs {
            let expected = positionals.len() - 1;
            if call_inputs.len() != expected {
                bail!(
                    "--inputs-hex provided {} item(s), but the export sequence has {expected} call(s)",
                    call_inputs.len()
                );
            }
        }

        Ok(Self {
            module_path: PathBuf::from(&positionals[0]),
            exports: positionals[1..].to_vec(),
            repeat,
            heap_base,
            input,
            inputs,
            current_account_id,
            predecessor_account_id,
            signer_account_id,
            attached_deposit,
            block_index,
            block_timestamp,
            epoch_height,
            random_seed,
            promise_result_u64,
            fuel_per_receipt,
        })
    }
}

fn take_arg<I>(args: &mut std::iter::Peekable<I>, option: &str) -> Result<String>
where
    I: Iterator<Item = String>,
{
    args.next()
        .ok_or_else(|| anyhow!("{option} requires a value"))
}

fn print_usage() {
    eprintln!(
        "usage: pf-offline-host [run] <module.wat|module.wasm> <export> [<export> ...] [options]\n\
         \n\
         options:\n\
           --repeat N                    call the export sequence N times (default: 1)\n\
           --heap-base N                 first host-managed wasm heap offset (default: 60000)\n\
           --input-hex HEX               Borsh input bytes, hex encoded\n\
           --inputs-hex HEX[,HEX...]      one Borsh input blob per export in the sequence\n\
           --input-file PATH             Borsh input bytes from a file\n\
           --current-account-id ID       current_account_id stub value\n\
           --predecessor-account-id ID   predecessor_account_id stub value\n\
           --signer-account-id ID        signer_account_id stub value\n\
           --attached-deposit N          attached_deposit stub value\n\
           --block-index N               block_index stub value\n\
           --block-timestamp N           block_timestamp stub value\n\
           --epoch-height N              epoch_height stub value\n\
           --random-seed-hex HEX         32-byte random_seed stub value\n\
           --promise-result-u64 N        Borsh U64 returned by promise_result (default: 42)
           --fuel N                      Wasmtime fuel budget per receipt (default: 10000000000)"
    );
}

fn parse_u32(value: &str, name: &str) -> Result<u32> {
    value
        .parse()
        .with_context(|| format!("{name} must fit in u32"))
}

fn parse_hex(input: &str) -> Result<Vec<u8>> {
    let compact: String = input.chars().filter(|c| !c.is_whitespace()).collect();
    if compact.len() % 2 != 0 {
        bail!("hex input must have an even number of digits");
    }

    let mut out = Vec::with_capacity(compact.len() / 2);
    for chunk in compact.as_bytes().chunks_exact(2) {
        let s = std::str::from_utf8(chunk)?;
        out.push(u8::from_str_radix(s, 16).with_context(|| format!("invalid hex byte `{s}`"))?);
    }
    Ok(out)
}

fn parse_hex_sequence(input: &str) -> Result<Vec<Vec<u8>>> {
    input.split(',').map(parse_hex).collect()
}

fn run(config: Config) -> Result<()> {
    let mut engine_config = wasmtime::Config::new();
    engine_config.consume_fuel(true);
    let engine = Engine::new(&engine_config).context("failed to create wasmtime engine")?;
    let bytes = load_wasm_or_wat(&config.module_path)?;
    let module = Module::from_binary(&engine, &bytes)
        .with_context(|| format!("failed to compile {}", config.module_path.display()))?;

    let mut linker = Linker::new(&engine);
    define_host_imports(&mut linker)?;

    let call_inputs = config
        .inputs
        .clone()
        .unwrap_or_else(|| vec![config.input.clone(); config.exports.len()]);
    let host = HostState::new(
        config.heap_base,
        config.input,
        config.current_account_id,
        config.predecessor_account_id,
        config.signer_account_id,
        config.attached_deposit,
        config.block_index,
        config.block_timestamp,
        config.epoch_height,
        config.random_seed,
        config.promise_result_u64,
    );
    let mut store = Store::new(&engine, host);
    let initial_fuel = config.fuel_per_receipt;

    println!(
        "loaded {} (exports `{}`, repeat {}, heap_base {})",
        config.module_path.display(),
        config.exports.join(","),
        config.repeat,
        config.heap_base
    );

    // PF-P0-06: track Wasmtime fuel honestly — cumulative vs per-call delta.
    // This is not NEAR VM gas; product budgets must not call it `near_gas`.
    let mut cumulative_consumed_fuel: u64 = 0;
    let mut contract_failures: u64 = 0;
    for sequence_index in 1..=config.repeat {
        for (call_index, export) in config.exports.iter().enumerate() {
            store.data_mut().input = call_inputs[call_index].clone();
            store.data_mut().begin_call();
            store
                .set_fuel(initial_fuel)
                .context("failed to reset fuel for receipt")?;
            let checkpoint = store.data().call_checkpoint();
            // NEAR creates a fresh Wasm instance for each receipt. Re-instantiation
            // prevents memory and mutable globals from leaking across contract calls;
            // only host-backed storage and execution context intentionally persist.
            let instance = instantiate_receipt(&linker, &mut store, &module, &checkpoint, export)?;
            let entry = match instance.get_typed_func::<(), ()>(&mut store, export) {
                Ok(entry) => entry,
                Err(err) => {
                    store.data_mut().rollback_call(checkpoint);
                    return Err(err).with_context(|| {
                        format!("export `{export}` is missing or is not a no-arg function")
                    });
                }
            };
            let trap = entry.call(&mut store, ()).err();
            let fuel_delta = initial_fuel.saturating_sub(store.get_fuel().unwrap_or(0));
            cumulative_consumed_fuel = cumulative_consumed_fuel.saturating_add(fuel_delta);
            if let Some(message) = store.data().panic_message.clone() {
                let error = parse_panic_error(&message);
                store.data_mut().rollback_call(checkpoint);
                contract_failures += 1;
                let state = store.data();
                println!(
                    "call {sequence_index}:{export}: error={error} heap_next={} allocations={} reuses={} deallocations={} storage_keys={} logs={} wasmtimeFuelCumulative={cumulative_consumed_fuel} wasmtimeFuelDelta={fuel_delta}",
                    state.allocator.next,
                    state.allocator.allocations,
                    state.allocator.reuses,
                    state.allocator.deallocations,
                    state.storage.len(),
                    state.logs.len()
                );
            } else if let Some(err) = trap {
                store.data_mut().rollback_call(checkpoint);
                return Err(err).with_context(|| format!("call {sequence_index}:{export} trapped"));
            } else {
                let state = store.data();
                println!(
                    "call {sequence_index}:{export}: {} heap_next={} allocations={} reuses={} deallocations={} storage_keys={} logs={} wasmtimeFuelCumulative={cumulative_consumed_fuel} wasmtimeFuelDelta={fuel_delta}",
                    describe_return(&state.return_value),
                    state.allocator.next,
                    state.allocator.allocations,
                    state.allocator.reuses,
                    state.allocator.deallocations,
                    state.storage.len(),
                    state.logs.len()
                );
            }
            let state = store.data();
            for log in &state.logs {
                println!("  log: {log}");
            }
            for trace in &state.promise_trace {
                println!("  promise: {trace}");
            }
        }
    }

    if contract_failures != 0 {
        bail!("{contract_failures} contract call(s) panicked; failed calls were rolled back");
    }
    Ok(())
}

fn instantiate_receipt(
    linker: &Linker<HostState>,
    store: &mut Store<HostState>,
    module: &Module,
    checkpoint: &CallCheckpoint,
    export: &str,
) -> Result<Instance> {
    match linker.instantiate(&mut *store, module) {
        Ok(instance) => Ok(instance),
        Err(err) => {
            store.data_mut().rollback_call(checkpoint.clone());
            Err(err).with_context(|| format!("failed to instantiate module for `{export}`"))
        }
    }
}

fn parse_panic_error(message: &str) -> String {
    let Some(rest) = message.strip_prefix("PF:") else {
        return format!("panic={message}");
    };
    let Some((id, code)) = rest.split_once(':') else {
        return format!("panic={message}");
    };
    match code.is_empty() {
        true => format!("assertion_id={id}"),
        false => format!("assertion_id={id} user_code={code}"),
    }
}

fn load_wasm_or_wat(path: &Path) -> Result<Vec<u8>> {
    let bytes = fs::read(path).with_context(|| format!("failed to read {}", path.display()))?;
    match path.extension().and_then(|s| s.to_str()) {
        Some("wat") => wat::parse_bytes(&bytes)
            .map(|cow| cow.into_owned())
            .with_context(|| format!("failed to parse WAT {}", path.display())),
        _ => Ok(bytes),
    }
}

#[derive(Debug)]
struct HostState {
    registers: HashMap<u64, Vec<u8>>,
    storage: HashMap<Vec<u8>, Vec<u8>>,
    return_value: Vec<u8>,
    logs: Vec<String>,
    input: Vec<u8>,
    current_account_id: Vec<u8>,
    predecessor_account_id: Vec<u8>,
    signer_account_id: Vec<u8>,
    attached_deposit: u64,
    block_index: u64,
    block_timestamp: u64,
    epoch_height: u64,
    random_seed: Vec<u8>,
    promise_result_u64: u64,
    promise_trace: Vec<String>,
    next_promise_id: u64,
    allocator: LinearMemoryAllocator,
    panic_message: Option<String>,
}

impl HostState {
    fn new(
        heap_base: u32,
        input: Vec<u8>,
        current_account_id: Vec<u8>,
        predecessor_account_id: Vec<u8>,
        signer_account_id: Vec<u8>,
        attached_deposit: u64,
        block_index: u64,
        block_timestamp: u64,
        epoch_height: u64,
        random_seed: Vec<u8>,
        promise_result_u64: u64,
    ) -> Self {
        Self {
            registers: HashMap::new(),
            storage: HashMap::new(),
            return_value: Vec::new(),
            logs: Vec::new(),
            input,
            current_account_id,
            predecessor_account_id,
            signer_account_id,
            attached_deposit,
            block_index,
            block_timestamp,
            epoch_height,
            random_seed,
            promise_result_u64,
            promise_trace: Vec::new(),
            next_promise_id: 0,
            allocator: LinearMemoryAllocator::new(heap_base),
            panic_message: None,
        }
    }

    fn begin_call(&mut self) {
        self.registers.clear();
        self.return_value.clear();
        self.logs.clear();
        self.promise_trace.clear();
        self.next_promise_id = 0;
        self.allocator = LinearMemoryAllocator::new(self.allocator.heap_base);
        self.panic_message = None;
    }

    fn call_checkpoint(&self) -> CallCheckpoint {
        CallCheckpoint {
            storage: self.storage.clone(),
        }
    }

    fn rollback_call(&mut self, checkpoint: CallCheckpoint) {
        self.storage = checkpoint.storage;
        self.begin_call();
    }
}

#[derive(Clone)]
struct CallCheckpoint {
    storage: HashMap<Vec<u8>, Vec<u8>>,
}

#[derive(Debug)]
struct LinearMemoryAllocator {
    heap_base: u32,
    next: u32,
    free_list: Vec<FreeBlock>,
    allocations: u64,
    reuses: u64,
    deallocations: u64,
}

#[derive(Debug)]
struct FreeBlock {
    ptr: u32,
    size: u64,
}

impl LinearMemoryAllocator {
    fn new(heap_base: u32) -> Self {
        Self {
            heap_base,
            next: heap_base,
            free_list: Vec::new(),
            allocations: 0,
            reuses: 0,
            deallocations: 0,
        }
    }

    fn alloc(&mut self, size: u64) -> Result<(u32, u64)> {
        let size = align_up(size, 8)?;
        if size == 0 {
            self.allocations += 1;
            return Ok((self.next, u64::from(self.next)));
        }

        if let Some(index) = self.free_list.iter().position(|block| block.size >= size) {
            let block = self.free_list.swap_remove(index);
            self.allocations += 1;
            self.reuses += 1;
            return Ok((block.ptr, u64::from(block.ptr) + size));
        }

        let ptr = self.next;
        let end = u64::from(ptr)
            .checked_add(size)
            .ok_or_else(|| anyhow!("linear-memory allocation overflow"))?;
        if end > u64::from(u32::MAX) {
            bail!("linear-memory allocation exceeds i32 address space");
        }
        self.next = end as u32;
        self.allocations += 1;
        Ok((ptr, end))
    }

    fn dealloc(&mut self, ptr: u32, size: u64) -> Result<()> {
        let size = align_up(size, 8)?;
        self.deallocations += 1;
        if size == 0 {
            return Ok(());
        }
        if ptr < self.heap_base {
            bail!(
                "pf_dealloc pointer {ptr} is below heap base {}",
                self.heap_base
            );
        }
        self.free_list.push(FreeBlock { ptr, size });
        Ok(())
    }
}

fn align_up(value: u64, alignment: u64) -> Result<u64> {
    debug_assert!(alignment.is_power_of_two());
    let mask = alignment - 1;
    value
        .checked_add(mask)
        .map(|v| v & !mask)
        .ok_or_else(|| anyhow!("allocation size overflow"))
}

fn define_host_imports(linker: &mut Linker<HostState>) -> Result<()> {
    linker.func_wrap(
        "env",
        "pf_alloc",
        |mut caller: Caller<'_, HostState>, size: i64| -> Result<i32> {
            let size = u64::try_from(size).context("pf_alloc size must be non-negative")?;
            let (ptr, end) = caller.data_mut().allocator.alloc(size)?;
            ensure_memory(&mut caller, end)?;
            Ok(ptr as i32)
        },
    )?;

    linker.func_wrap(
        "env",
        "pf_dealloc",
        |mut caller: Caller<'_, HostState>, ptr: i32, size: i64| -> Result<()> {
            let ptr = ptr as u32;
            let size = u64::try_from(size).context("pf_dealloc size must be non-negative")?;
            caller.data_mut().allocator.dealloc(ptr, size)
        },
    )?;

    linker.func_wrap(
        "env",
        "input",
        |mut caller: Caller<'_, HostState>, register_id: i64| -> Result<()> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let input = caller.data().input.clone();
            caller.data_mut().registers.insert(register_id, input);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "read_register",
        |mut caller: Caller<'_, HostState>, register_id: i64, ptr: i64| -> Result<()> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let Some(bytes) = caller.data().registers.get(&register_id).cloned() else {
                return Ok(());
            };
            write_memory(&mut caller, ptr, &bytes)
        },
    )?;

    linker.func_wrap(
        "env",
        "register_len",
        |caller: Caller<'_, HostState>, register_id: i64| -> Result<i64> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            Ok(caller
                .data()
                .registers
                .get(&register_id)
                .map(|bytes| bytes.len() as i64)
                .unwrap_or(-1))
        },
    )?;

    linker.func_wrap(
        "env",
        "value_return",
        |mut caller: Caller<'_, HostState>, len: i64, ptr: i64| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr, len)?;
            caller.data_mut().return_value = bytes;
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "log_utf8",
        |mut caller: Caller<'_, HostState>, len: i64, ptr: i64| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr, len)?;
            let log = String::from_utf8_lossy(&bytes).into_owned();
            caller.data_mut().logs.push(log);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "panic",
        |mut caller: Caller<'_, HostState>, len: i64, ptr: i64| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr, len)?;
            let message = String::from_utf8_lossy(&bytes).into_owned();
            caller.data_mut().panic_message = Some(message);
            bail!("contract panicked")
        },
    )?;

    linker.func_wrap(
        "env",
        "storage_read",
        |mut caller: Caller<'_, HostState>,
         key_len: i64,
         key_ptr: i64,
         register_id: i64|
         -> Result<i64> {
            let key = read_memory(&mut caller, key_ptr, key_len)?;
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let value = caller.data().storage.get(&key).cloned();
            match value {
                Some(value) => {
                    caller.data_mut().registers.insert(register_id, value);
                    Ok(1)
                }
                None => Ok(0),
            }
        },
    )?;

    linker.func_wrap(
        "env",
        "storage_write",
        |mut caller: Caller<'_, HostState>,
         key_len: i64,
         key_ptr: i64,
         value_len: i64,
         value_ptr: i64,
         register_id: i64|
         -> Result<i64> {
            let key = read_memory(&mut caller, key_ptr, key_len)?;
            let value = read_memory(&mut caller, value_ptr, value_len)?;
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let old = caller.data_mut().storage.insert(key, value);
            match old {
                Some(old) => {
                    caller.data_mut().registers.insert(register_id, old);
                    Ok(1)
                }
                None => Ok(0),
            }
        },
    )?;

    // CosmWasm HostBridge (PF-P3-02): `db_read` / `db_write` share offline storage.
    // EmitWat uses (ptr,len) and `db_read` returns **i64** (full LE scalar).
    linker.func_wrap(
        "env",
        "db_read",
        |mut caller: Caller<'_, HostState>, key_ptr: i32, key_len: i32| -> Result<i64> {
            let key = read_memory(&mut caller, key_ptr as i64, key_len as i64)?;
            match caller.data().storage.get(&key) {
                Some(value) if !value.is_empty() => {
                    let mut buf = [0u8; 8];
                    let n = value.len().min(8);
                    buf[..n].copy_from_slice(&value[..n]);
                    Ok(i64::from_le_bytes(buf))
                }
                _ => Ok(0),
            }
        },
    )?;

    linker.func_wrap(
        "env",
        "db_write",
        |mut caller: Caller<'_, HostState>,
         key_ptr: i32,
         key_len: i32,
         value_ptr: i32,
         value_len: i32|
         -> Result<()> {
            let key = read_memory(&mut caller, key_ptr as i64, key_len as i64)?;
            let value = read_memory(&mut caller, value_ptr as i64, value_len as i64)?;
            caller.data_mut().storage.insert(key, value);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "db_remove",
        |mut caller: Caller<'_, HostState>, key_ptr: i32, key_len: i32| -> Result<()> {
            let key = read_memory(&mut caller, key_ptr as i64, key_len as i64)?;
            caller.data_mut().storage.remove(&key);
            Ok(())
        },
    )?;

    // CosmWasm EmitWat `set_return_data` is (ptr, len) — order differs from NEAR value_return (len, ptr).
    linker.func_wrap(
        "env",
        "set_return_data",
        |mut caller: Caller<'_, HostState>, ptr: i32, len: i32| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr as i64, len as i64)?;
            caller.data_mut().return_value = bytes;
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "log",
        |mut caller: Caller<'_, HostState>, ptr: i32, len: i32| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr as i64, len as i64)?;
            let log = String::from_utf8_lossy(&bytes).into_owned();
            caller.data_mut().logs.push(log);
            Ok(())
        },
    )?;

    // Portable peer stub (records nothing extra in offline host; returns 0).
    linker.func_wrap(
        "env",
        "execute_msg",
        |_caller: Caller<'_, HostState>,
         _c_len: i32,
         _c_ptr: i32,
         _m_len: i32,
         _m_ptr: i32,
         _a_len: i32,
         _a_ptr: i32|
         -> i32 { 0 },
    )?;

    // Soroban HostBridge (PF-P3-02): `_get` / `_put` share the offline storage map.
    // `_get` returns the first 4 LE bytes as i32 (matches EmitWat `__pf_read_u64`
    // which zero-extends i32→i64 for Counter-scale scalars). Missing key → 0.
    linker.func_wrap(
        "env",
        "_get",
        |mut caller: Caller<'_, HostState>, key_ptr: i32, key_len: i32| -> Result<i32> {
            let key = read_memory(&mut caller, key_ptr as i64, key_len as i64)?;
            match caller.data().storage.get(&key) {
                Some(value) if !value.is_empty() => {
                    let mut buf = [0u8; 4];
                    let n = value.len().min(4);
                    buf[..n].copy_from_slice(&value[..n]);
                    Ok(i32::from_le_bytes(buf))
                }
                _ => Ok(0),
            }
        },
    )?;

    linker.func_wrap(
        "env",
        "_put",
        |mut caller: Caller<'_, HostState>,
         key_ptr: i32,
         key_len: i32,
         value_ptr: i32,
         value_len: i32|
         -> Result<()> {
            let key = read_memory(&mut caller, key_ptr as i64, key_len as i64)?;
            let value = read_memory(&mut caller, value_ptr as i64, value_len as i64)?;
            caller.data_mut().storage.insert(key, value);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "log_from_slice",
        |mut caller: Caller<'_, HostState>, ptr: i32, len: i32| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr as i64, len as i64)?;
            let log = String::from_utf8_lossy(&bytes).into_owned();
            caller.data_mut().logs.push(log);
            Ok(())
        },
    )?;

    // Spike honesty: offline host always authorises (matches Lean interpreter default).
    linker.func_wrap(
        "env",
        "require_auth_for_args",
        |_caller: Caller<'_, HostState>, _ptr: i32, _len: i32| -> i32 { 1 },
    )?;

    // Spike stub: record nothing extra; return handle 0 (matches WasmInterpreter).
    linker.func_wrap(
        "env",
        "invoke_contract",
        |_caller: Caller<'_, HostState>,
         _c_len: i32,
         _c_ptr: i32,
         _m_len: i32,
         _m_ptr: i32,
         _a_len: i32,
         _a_ptr: i32|
         -> i32 { 0 },
    )?;

    linker.func_wrap(
        "env",
        "storage_has_key",
        |mut caller: Caller<'_, HostState>, key_len: i64, key_ptr: i64| -> Result<i64> {
            let key = read_memory(&mut caller, key_ptr, key_len)?;
            Ok(i64::from(caller.data().storage.contains_key(&key)))
        },
    )?;

    linker.func_wrap(
        "env",
        "sha256",
        |mut caller: Caller<'_, HostState>, len: i64, ptr: i64, register_id: i64| -> Result<()> {
            let bytes = read_memory(&mut caller, ptr, len)?;
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let digest = Sha256::digest(&bytes).to_vec();
            caller.data_mut().registers.insert(register_id, digest);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "current_account_id",
        |mut caller: Caller<'_, HostState>, register_id: i64| -> Result<()> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let value = caller.data().current_account_id.clone();
            caller.data_mut().registers.insert(register_id, value);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "predecessor_account_id",
        |mut caller: Caller<'_, HostState>, register_id: i64| -> Result<()> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let value = caller.data().predecessor_account_id.clone();
            caller.data_mut().registers.insert(register_id, value);
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "signer_account_id",
        |mut caller: Caller<'_, HostState>, register_id: i64| -> Result<()> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let value = caller.data().signer_account_id.clone();
            caller.data_mut().registers.insert(register_id, value);
            Ok(())
        },
    )?;

    // near-sys: attached_deposit(balance_ptr) writes little-endian u128 (16 bytes).
    linker.func_wrap(
        "env",
        "attached_deposit",
        |mut caller: Caller<'_, HostState>, balance_ptr: i64| -> Result<()> {
            let ptr = usize::try_from(balance_ptr).context("attached_deposit ptr")?;
            let amount = caller.data().attached_deposit as u128;
            let bytes = amount.to_le_bytes();
            let mem = caller
                .get_export("memory")
                .and_then(|e| e.into_memory())
                .context("missing memory export for attached_deposit")?;
            mem.write(&mut caller, ptr, &bytes)
                .context("attached_deposit memory write")?;
            Ok(())
        },
    )?;

    linker.func_wrap(
        "env",
        "block_index",
        |caller: Caller<'_, HostState>| -> i64 { caller.data().block_index as i64 },
    )?;

    linker.func_wrap(
        "env",
        "block_timestamp",
        |caller: Caller<'_, HostState>| -> i64 { caller.data().block_timestamp as i64 },
    )?;

    linker.func_wrap(
        "env",
        "epoch_height",
        |caller: Caller<'_, HostState>| -> i64 { caller.data().epoch_height as i64 },
    )?;

    linker.func_wrap(
        "env",
        "random_seed",
        |mut caller: Caller<'_, HostState>, register_id: i64| -> Result<()> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let value = caller.data().random_seed.clone();
            caller.data_mut().registers.insert(register_id, value);
            Ok(())
        },
    )?;

    // Promise API stubs.
    // near-sys: amount is a *pointer* to little-endian u128 (16 bytes), not a
    // raw yocto value (matches EmitWat.lowerNearDeposit). Trace preserves the
    // full u128 value so pointer decoding cannot silently truncate deposits.
    linker.func_wrap(
        "env",
        "promise_create",
        |mut caller: Caller<'_, HostState>,
         account_len: i64,
         account_ptr: i64,
         method_len: i64,
         method_ptr: i64,
         args_len: i64,
         args_ptr: i64,
         amount_ptr: i64,
         gas: i64|
         -> Result<i64> {
            let account = read_utf8_lossy(&mut caller, account_ptr, account_len)?;
            let method = read_utf8_lossy(&mut caller, method_ptr, method_len)?;
            let args = read_utf8_lossy(&mut caller, args_ptr, args_len)?;
            let amount = read_u128_le(&mut caller, amount_ptr)?;
            let state = caller.data_mut();
            let id = state.next_promise_id;
            state.next_promise_id += 1;
            state.promise_trace.push(format!(
                "promise_create id={id} account={account} method={method} args={args} deposit={amount} gas={gas}"
            ));
            Ok(id as i64)
        },
    )?;
    linker.func_wrap(
        "env",
        "promise_then",
        |mut caller: Caller<'_, HostState>,
         parent: i64,
         account_len: i64,
         account_ptr: i64,
         method_len: i64,
         method_ptr: i64,
         args_len: i64,
         args_ptr: i64,
         amount_ptr: i64,
         gas: i64|
         -> Result<i64> {
            let account = read_utf8_lossy(&mut caller, account_ptr, account_len)?;
            let method = read_utf8_lossy(&mut caller, method_ptr, method_len)?;
            let args = read_utf8_lossy(&mut caller, args_ptr, args_len)?;
            let amount = read_u128_le(&mut caller, amount_ptr)?;
            let state = caller.data_mut();
            let id = state.next_promise_id;
            state.next_promise_id += 1;
            state.promise_trace.push(format!(
                "promise_then id={id} parent={parent} account={account} method={method} args={args} deposit={amount} gas={gas}"
            ));
            Ok(id as i64)
        },
    )?;
    linker.func_wrap(
        "env",
        "promise_results_count",
        |_: Caller<'_, HostState>| -> i64 { 1 },
    )?;
    linker.func_wrap(
        "env",
        "promise_result",
        |mut caller: Caller<'_, HostState>, index: i64, register_id: i64| -> Result<i64> {
            let register_id =
                u64::try_from(register_id).context("register id must be non-negative")?;
            let result = caller.data().promise_result_u64;
            let state = caller.data_mut();
            state
                .registers
                .insert(register_id, result.to_le_bytes().to_vec());
            state.promise_trace.push(format!(
                "promise_result index={index} status=1 return_u64={result}"
            ));
            Ok(1)
        },
    )?;
    // NEAR `promise_return` schedules the promise result as the transaction
    // return. Offline host does not run a real peer VM; when a promise was
    // created in this call, materialize a Borsh U64 peer result so product
    // RemoteCall / NEP-141 callback paths can assert return values (N1.4).
    //
    // Heuristic: if the last promise_create args look like a JSON array of
    // two decimal numbers `[a,b]`, return a+b (PeerOracle remote_call shape).
    // Otherwise use `--promise-result-u64` (default 42).
    linker.func_wrap(
        "env",
        "promise_return",
        |mut caller: Caller<'_, HostState>, promise_id: i64| {
            let state = caller.data_mut();
            state
                .promise_trace
                .push(format!("promise_return id={promise_id}"));
            if let Some(result) = offline_promise_return_u64(state) {
                state.return_value = result.to_le_bytes().to_vec();
                state.promise_trace.push(format!(
                    "promise_return_value u64={result} (offline peer stub)"
                ));
            }
        },
    )?;

    Ok(())
}

fn memory(caller: &mut Caller<'_, HostState>) -> Result<wasmtime::Memory> {
    caller
        .get_export("memory")
        .and_then(Extern::into_memory)
        .ok_or_else(|| anyhow!("module does not export linear memory as `memory`"))
}

fn ensure_memory(caller: &mut Caller<'_, HostState>, end: u64) -> Result<()> {
    let memory = memory(caller)?;
    let current = memory.data_size(&mut *caller) as u64;
    if end <= current {
        return Ok(());
    }

    let needed = end - current;
    let pages = needed.div_ceil(WASM_PAGE_SIZE);
    memory
        .grow(&mut *caller, pages)
        .context("failed to grow wasm linear memory")?;
    Ok(())
}

/// Offline peer stub for `promise_return` (N1.4).
///
/// Only fills `value_return` for a **simple** promise chain (promise_create
/// without promise_then). NEP-141 `ft_transfer_call` uses create+then and keeps
/// the host's empty return until `ft_resolve_transfer` runs.
///
/// When `args` is a JSON array of two decimal integers, returns their sum
/// (PeerOracle `remote_call` / sandbox-peer `call_with_args → 49`). Otherwise
/// returns `promise_result_u64`.
fn offline_promise_return_u64(state: &HostState) -> Option<u64> {
    let has_then = state
        .promise_trace
        .iter()
        .any(|line| line.starts_with("promise_then "));
    if has_then {
        return None;
    }
    let create = state
        .promise_trace
        .iter()
        .rev()
        .find(|line| line.starts_with("promise_create "))?;
    // Format: promise_create id=… account=… method=… args=… deposit=… gas=…
    let args = create
        .split(" args=")
        .nth(1)?
        .split(" deposit=")
        .next()?
        .trim();
    if let Some(sum) = parse_two_decimal_sum(args) {
        return Some(sum);
    }
    // Empty-args remote still needs a return for product call_remote paths.
    Some(state.promise_result_u64)
}

fn parse_two_decimal_sum(args: &str) -> Option<u64> {
    let s = args.trim();
    let inner = s.strip_prefix('[')?.strip_suffix(']')?;
    let mut parts = inner.split(',').map(|p| p.trim());
    let a: u64 = parts.next()?.parse().ok()?;
    let b: u64 = parts.next()?.parse().ok()?;
    if parts.next().is_some() {
        return None;
    }
    Some(a.saturating_add(b))
}

fn read_memory(caller: &mut Caller<'_, HostState>, ptr: i64, len: i64) -> Result<Vec<u8>> {
    let ptr = usize::try_from(ptr).context("memory pointer must be non-negative")?;
    let len = usize::try_from(len).context("memory length must be non-negative")?;
    let memory = memory(caller)?;
    let mut buf = vec![0; len];
    memory
        .read(&mut *caller, ptr, &mut buf)
        .context("failed to read wasm linear memory")?;
    Ok(buf)
}

fn write_memory(caller: &mut Caller<'_, HostState>, ptr: i64, bytes: &[u8]) -> Result<()> {
    let ptr = usize::try_from(ptr).context("memory pointer must be non-negative")?;
    let memory = memory(caller)?;
    memory
        .write(&mut *caller, ptr, bytes)
        .context("failed to write wasm linear memory")
}

fn read_u128_le(caller: &mut Caller<'_, HostState>, ptr: i64) -> Result<u128> {
    let bytes = read_memory(caller, ptr, 16)?;
    let bytes: [u8; 16] = bytes
        .try_into()
        .map_err(|_| anyhow!("promise amount must be a 16-byte little-endian u128"))?;
    Ok(u128::from_le_bytes(bytes))
}

fn read_utf8_lossy(caller: &mut Caller<'_, HostState>, ptr: i64, len: i64) -> Result<String> {
    let bytes = read_memory(caller, ptr, len)?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

fn describe_return(bytes: &[u8]) -> String {
    if bytes.is_empty() {
        return "return=<none>".to_string();
    }

    let hex = bytes
        .iter()
        .map(|byte| format!("{byte:02x}"))
        .collect::<Vec<_>>()
        .join("");
    match bytes.len() {
        1 => format!("return_hex={hex} return_bool={}", bytes[0] != 0),
        4 => {
            let mut arr = [0; 4];
            arr.copy_from_slice(bytes);
            format!("return_hex={hex} return_u32={}", u32::from_le_bytes(arr))
        }
        8 => {
            let mut arr = [0; 8];
            arr.copy_from_slice(bytes);
            format!("return_hex={hex} return_u64={}", u64::from_le_bytes(arr))
        }
        _ => format!("return_hex={hex} return_len={}", bytes.len()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn start_trap_rolls_back_host_storage() -> Result<()> {
        let engine = Engine::default();
        let bytes = wat::parse_str(
            r#"(module
              (import "env" "storage_write"
                (func $storage_write (param i64 i64 i64 i64 i64) (result i64)))
              (memory (export "memory") 1)
              (data (i32.const 0) "leak")
              (data (i32.const 8) "x")
              (func $start
                i64.const 4 i64.const 0
                i64.const 1 i64.const 8 i64.const 0
                call $storage_write drop
                unreachable)
              (start $start))"#,
        )?;
        let module = Module::from_binary(&engine, &bytes)?;
        let mut linker = Linker::new(&engine);
        define_host_imports(&mut linker)?;
        let mut host = HostState::new(
            DEFAULT_HEAP_BASE,
            Vec::new(),
            b"contract.near".to_vec(),
            b"caller.near".to_vec(),
            b"signer.near".to_vec(),
            0,
            0,
            0,
            0,
            vec![0; 32],
            0,
        );
        host.storage.insert(b"stable".to_vec(), b"value".to_vec());
        let mut store = Store::new(&engine, host);
        let checkpoint = store.data().call_checkpoint();

        let result = instantiate_receipt(&linker, &mut store, &module, &checkpoint, "start-trap");

        assert!(result.is_err());
        assert_eq!(store.data().storage.len(), 1);
        assert_eq!(
            store.data().storage.get(b"stable".as_slice()),
            Some(&b"value".to_vec())
        );
        assert!(!store.data().storage.contains_key(b"leak".as_slice()));
        Ok(())
    }
}
