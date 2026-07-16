# ProofForge Offline Wasm Host

This crate is a local wasmtime runner for `EmitWat` output. It loads a `.wat` or
`.wasm` module, injects the NEAR-style host imports used by `EmitWat`, and runs
one or more exported entrypoints in the same instance. It is not part of the
chain artifact.

The allocator boundary is intentional: `pf_alloc(n) -> i32` returns an offset in
the guest wasm linear memory. It never returns a native host pointer. The current
host implementation manages that linear memory with a bump allocator plus a
reserved free-list path for future `pf_dealloc` call sites.

`alloc.offline.host_bump` uses the `pf_alloc` / `pf_dealloc` import ABI. It is
the only offline allocator advertised by the current `wasm-near` target
profile. Jemalloc-shaped experiments remain a future wasm-linking path: a real
jemalloc experiment must compile/link jemalloc into wasm so it allocates from
the same linear memory; host-process jemalloc cannot be used directly by guest
wasm.

Chain deployment allocators such as `alloc.near_wee_model` and
`alloc.minimal_malloc` are different: `EmitWat` emits allocator code into the
module itself. The offline host does not provide `pf_alloc` for those paths; it
only provides the NEAR-style environment imports. See
`docs/targets/wasm-allocators.md` for the strategy split.

## Usage

Generate allocator WAT fixtures:

```sh
lake env lean --run Tests/Backend/Wasm/EmitWatAlloc.lean
```

Run the wasm-internal `minimalMalloc` fixture:

```sh
cargo run --manifest-path runtime/offline-host/Cargo.toml -- \
  run build/wasm-near/emitwat-alloc-minimal.wat sum_literal --repeat 2
```

Run the NEAR deployment allocator fixture:

```sh
cargo run --manifest-path runtime/offline-host/Cargo.toml -- \
  run build/wasm-near/emitwat-alloc-near.wat sum_literal --repeat 2
```

Run a fixture that explicitly releases one fixed-array local before allocating
the next:

```sh
cargo run --manifest-path runtime/offline-host/Cargo.toml -- \
  run build/wasm-near/emitwat-release-minimal.wat release_then_sum --repeat 2
```

Compile WAT to wasm with wabt and run the binary path:

```sh
wat2wasm build/wasm-near/emitwat-alloc-near.wat \
  -o build/wasm-near/emitwat-alloc-near.wasm
cargo run --manifest-path runtime/offline-host/Cargo.toml -- \
  run build/wasm-near/emitwat-alloc-near.wasm sum_literal --repeat 2
```

Multiple exports can be listed to exercise one module instance with shared host
storage:

```sh
cargo run --manifest-path runtime/offline-host/Cargo.toml -- \
  run build/wasm-near/emitwat-features.wat init bump bump getN getFlag
```
