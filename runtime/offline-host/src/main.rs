use std::collections::HashMap;
use std::env;
use std::fs;
use std::path::{Path, PathBuf};

use anyhow::{anyhow, bail, Context, Result};
use sha2::{Digest, Sha256};
use wasmtime::{Caller, Engine, Extern, Linker, Module, Store};

const DEFAULT_HEAP_BASE: u32 = 60_000;
const WASM_PAGE_SIZE: u64 = 65_536;

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
           --promise-result-u64 N        Borsh U64 returned by promise_result (default: 42)"
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
    let initial_fuel: u64 = 10_000_000_000;
    store.set_fuel(initial_fuel).context("failed to set fuel")?;
    let instance = linker
        .instantiate(&mut store, &module)
        .context("failed to instantiate module")?;
    let mut entries = Vec::with_capacity(config.exports.len());
    for export in &config.exports {
        let entry = instance
            .get_typed_func::<(), ()>(&mut store, export)
            .with_context(|| format!("export `{export}` is missing or is not a no-arg function"))?;
        entries.push((export.clone(), entry));
    }

    println!(
        "loaded {} (exports `{}`, repeat {}, heap_base {})",
        config.module_path.display(),
        config.exports.join(","),
        config.repeat,
        config.heap_base
    );

    // PF-P0-06: track Wasmtime fuel honestly — cumulative vs per-call delta.
    // This is not NEAR VM gas; product budgets must not call it `near_gas`.
    let mut previous_consumed_fuel: u64 = 0;
    for sequence_index in 1..=config.repeat {
        for (call_index, (export, entry)) in entries.iter().enumerate() {
            store.data_mut().input = call_inputs[call_index].clone();
            store.data_mut().begin_call();
            let trap = entry.call(&mut store, ()).err();
            let consumed_fuel = initial_fuel - store.get_fuel().unwrap_or(0);
            let fuel_delta = consumed_fuel.saturating_sub(previous_consumed_fuel);
            previous_consumed_fuel = consumed_fuel;
            let state = store.data();
            if let Some(message) = &state.panic_message {
                let error = parse_panic_error(message);
                println!(
                    "call {sequence_index}:{export}: error={error} heap_next={} allocations={} reuses={} deallocations={} storage_keys={} logs={} wasmtimeFuelCumulative={consumed_fuel} wasmtimeFuelDelta={fuel_delta}",
                    state.allocator.next,
                    state.allocator.allocations,
                    state.allocator.reuses,
                    state.allocator.deallocations,
                    state.storage.len(),
                    state.logs.len()
                );
            } else if let Some(err) = trap {
                return Err(err).with_context(|| format!("call {sequence_index}:{export} trapped"));
            } else {
                println!(
                    "call {sequence_index}:{export}: {} heap_next={} allocations={} reuses={} deallocations={} storage_keys={} logs={} wasmtimeFuelCumulative={consumed_fuel} wasmtimeFuelDelta={fuel_delta}",
                    describe_return(&state.return_value),
                    state.allocator.next,
                    state.allocator.allocations,
                    state.allocator.reuses,
                    state.allocator.deallocations,
                    state.storage.len(),
                    state.logs.len()
                );
            }
            for log in &state.logs {
                println!("  log: {log}");
            }
            for trace in &state.promise_trace {
                println!("  promise: {trace}");
            }
        }
    }

    Ok(())
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
        self.panic_message = None;
    }
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

    linker.func_wrap(
        "env",
        "attached_deposit",
        |caller: Caller<'_, HostState>| -> i64 { caller.data().attached_deposit as i64 },
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

    // Promise API stubs
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
         amount: i64,
         gas: i64|
         -> Result<i64> {
            let account = read_utf8_lossy(&mut caller, account_ptr, account_len)?;
            let method = read_utf8_lossy(&mut caller, method_ptr, method_len)?;
            let args = read_utf8_lossy(&mut caller, args_ptr, args_len)?;
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
         amount: i64,
         gas: i64|
         -> Result<i64> {
            let account = read_utf8_lossy(&mut caller, account_ptr, account_len)?;
            let method = read_utf8_lossy(&mut caller, method_ptr, method_len)?;
            let args = read_utf8_lossy(&mut caller, args_ptr, args_len)?;
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
    linker.func_wrap(
        "env",
        "promise_return",
        |mut caller: Caller<'_, HostState>, promise_id: i64| {
            caller
                .data_mut()
                .promise_trace
                .push(format!("promise_return id={promise_id}"));
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
