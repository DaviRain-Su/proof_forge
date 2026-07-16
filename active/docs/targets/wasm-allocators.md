# Wasm Allocators

This note separates three allocator surfaces that are easy to conflate.

## Where allocation happens

Wasm guest code can only dereference offsets inside its own linear memory.
Any allocator used by generated contract code must therefore return a wasm
linear-memory offset. A native host pointer from the runner process is not a
valid contract pointer.

That gives ProofForge two allocator modes:

| Mode | Strategy | Where it lives | Chain deployable | Current role |
|---|---|---:|---|
| chain deployment | `alloc.bump` | generated wasm module | yes | simplest no-free allocator |
| chain deployment | `alloc.bump_reset` | generated wasm module | yes | resets the bump frontier at each entrypoint |
| chain deployment | `alloc.near_wee_model` | generated wasm module | yes | NEAR deployment profile; Rust sourcegen maps to near-sdk `wee_alloc`, direct WAT maps to internal allocator code |
| chain deployment | `alloc.minimal_malloc` | generated wasm module | yes | first-fit free-list allocator skeleton for direct WAT output |
| chain deployment | `alloc.cosmwasm_region` | exported region ABI | yes for CosmWasm | adapter-specific `allocate` / `deallocate` exports |
| offline experiment | `alloc.offline.host_bump` | offline host import ABI | no on NEAR | simulator hook for allocator experiments |
| offline experiment | `alloc.offline.host_jemalloc_shape` / `alloc.offline.host_mimalloc_shape` | imported or wasm-linked allocator ABI | no on NEAR unless linked into the final wasm | future experiments |

The current `wasm-near` target profile advertises only
`alloc.near_wee_model` for deployment and `alloc.offline.host_bump` for offline
experiments. Jemalloc/mimalloc-shaped strategies remain generic future
experiments, not NEAR-supported allocators. CosmWasm allocation remains
deferred while NEAR is the active Wasm target.

The offline runner in `runtime/offline-host` is not the chain allocator. It
only supplies host imports for local execution. For imported allocator
strategies, it also implements `pf_alloc` / `pf_dealloc` by managing offsets in
the guest memory. For chain deployment allocators such as
`alloc.near_wee_model` and `alloc.minimal_malloc`, those imports are absent and
the allocation happens inside the generated wasm module.

## NEAR and `wee_alloc`

NEAR Rust SDK contracts use the Rust compiler path: Rust code plus SDK crates
compile into one wasm module, and the selected global allocator is linked into
that same module. In current `near-sdk-rs`, `wee_alloc` is an optional wasm32
dependency and the default feature set enables `wee_alloc`; the deprecated
`setup_alloc` macro documentation says allocator setup is already done by
default when that feature is enabled.

`EmitWat` does not go through Rust, so it cannot directly depend on the Rust
`wee_alloc` crate. Its NEAR deployment allocator is `alloc.near_wee_model`,
which lowers to the same direct-WAT shape as `alloc.minimal_malloc`: allocator
code is emitted into the module, returns linear-memory offsets, and uses
`memory.grow` when the module needs more pages. This follows the same placement
model as NEAR's Rust path without claiming byte-for-byte parity with the
`wee_alloc` crate.

## Current `minimalMalloc`

`alloc.minimal_malloc` emits:

- `global $arr_ptr`: bump frontier for new blocks
- `global $arr_free`: head of a singly linked free list
- `func $__pf_arr_alloc(n: i64) -> i32`
- `func $__pf_arr_dealloc(p: i32, n: i64)`

Block layout:

```text
block_ptr + 0: u32 total_block_size
block_ptr + 4: u32 next_free_block
block_ptr + 8: payload returned to generated contract code
```

Allocation first scans the free list for a block large enough. If none exists,
it extends `arr_ptr`; if the new frontier exceeds the current memory size, it
uses `memory.grow`. The current version does not split or coalesce blocks.

The portable IR has an explicit `release name` statement for owned heap-backed
locals. EmitWat lowers `release` of fixed-array and struct locals to
`__pf_arr_dealloc`; scalar releases are rejected. This gives later IR checkers a
name-based ownership boundary for proving no use-after-release and no
double-release properties.

The IR ownership checker now enforces that boundary before EmitWat lowering:
release must target an owned heap-backed local, released locals cannot be used
again, double release is rejected, and conditional branches must agree on the
release status of pre-existing locals.

The current implementation is intentionally simple: it does not split or
coalesce blocks, and broader lifetime inference is still future work.

## What not to do

- Do not wire host-process `jemalloc` directly to `pf_alloc` for chain code.
  It would return native pointers, which wasm cannot dereference.
- Do not require `pf_alloc` / `pf_dealloc` imports for NEAR deployable output.
  NEAR does not provide those imports.
- Do not call the direct-WAT allocator `wee_alloc` unless the actual Rust crate
  is compiled and linked into the final wasm artifact.
- Do not model IR release as raw pointer free. Use name-based `release` so the
  IR checker can reason about local ownership.
