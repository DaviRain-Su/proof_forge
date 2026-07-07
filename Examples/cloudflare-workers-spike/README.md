# Cloudflare Workers Counter Spike

This is a hand-written end-to-end proof of concept for a ProofForge target that
compiles to a Cloudflare Worker. It demonstrates:

- A Zig guest module compiled to `wasm32-freestanding`.
- A JavaScript host bridge that loads the Wasm and wires Workers KV.
- HTTP routing: `POST /initialize`, `POST /increment`, `GET /count`.

This is **not** yet generated from `ProofForge/IR/Examples/Counter.lean`; it is a
manual prototype that the eventual EmitZig backend should be able to reproduce.

## Build

Requires [Zig](https://ziglang.org/) and [Wrangler](https://developers.cloudflare.com/workers/wrangler/).

```sh
./build.sh
```

## Guest smoke test (no Workers runtime needed)

```sh
cargo run --manifest-path ../../runtime/offline-host/Cargo.toml --bin cloudflare_guest_smoke -- build/counter.wasm
```

This directly instantiates the Wasm in Rust/Wasmtime and verifies the protocol:
`initialize`, `get`, `increment`, `increment`, `get` -> final count `2`.

## Configure KV

```sh
wrangler kv namespace create COUNTER_KV
wrangler kv namespace create COUNTER_KV --preview
```

Paste the returned ids into `wrangler.toml`.

## Run locally

```sh
wrangler dev
```

Then test:

```sh
curl -X POST http://localhost:8787/initialize
curl -X POST http://localhost:8787/increment
curl http://localhost:8787/count
```

## Guest/Host Protocol

See `src/counter.zig` for the full contract. Summary:

- Guest exports: `memory`, `malloc`, `free`, `fetch(req_ptr, req_len)`.
- Host imports: `kv_get`, `kv_put`, `console_log`, `get_caller`.
- Request line: `"initialize\n"`, `"increment\n"`, or `"get\n"`.
- Response line: `"OK\n<value\u003e"` or `"ERR\n<message\u003e"`.

## Mapping to ProofForge IR

This guest implements the semantics of `ProofForge/IR/Examples/Counter.lean`:

| IR construct | Guest/host behavior |
|---|---|
| `state count : u64` | `COUNT_KEY` in Workers KV |
| `initialize` | `kv_put(COUNT_KEY, "0")` |
| `increment` | `kv_get` → add 1 → `kv_put` |
| `get` | `kv_get` → return count |
| `caller.sender` | `request.headers.get("CF-Connecting-IP")` via `get_caller` |
| `events.emit` | `console_log` (guest) surfaced through Workers Logs |

## Notes / Open Questions

- KV is eventually consistent. For strong consistency per object, swap KV for a
  Durable Object.
- The current `kv_get`/`kv_put` host imports are synchronous because the spike
  buffers KV state for the lifetime of one request. A production target should
  decide whether to make storage async or keep synchronous DO state.
- `free` is currently a no-op; a real runtime needs a real allocator.
