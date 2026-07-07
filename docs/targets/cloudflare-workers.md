# Cloudflare Workers Target

Target id: **`wasm-cloudflare-workers`**

Family: **Wasm host**

Stage: **Spike** — target profile in the registry; Counter IR lowers to
TypeScript via `ProofForge.Compiler.TS.Emit` (`scripts/ts/counter-ir-smoke.sh`,
optional GitHub `cloudflare-smoke` job). A future Zig/Wasm host-bridge route
remains **Planned** research, not the current product path.

Related: [Wasm family](wasm-family.md), [Capability registry](../capability-registry.md), [Shared scenario](../shared-scenario.md), [RFC 0002](../rfcs/0002-target-implementation-design.md).

## Summary

Cloudflare Workers is a non-blockchain Wasm-host target. It lets the same
portable business core that compiles to blockchain Wasm targets (NEAR,
CosmWasm) also run as an off-chain edge worker. The goal is to share verified
Lean business logic between on-chain contracts and chain-side services such as
oracles, keepers, indexers, simulators, and hybrid dApp backends.

Because Workers is not a blockchain, many chain-specific capabilities are
reinterpreted or unsupported. The portable core (pure logic, state transitions,
types, proofs) stays identical; only the capability adapter changes.

## Pipeline (landed spike)

```text
portable IR (Counter fixture)
  -> ProofForge.Compiler.TS.Emit
  -> TypeScript Worker module (build/ts/Counter.ts)
  -> tsc type-check + wrangler dry-run
  -> optional wrangler dev smoke
```

A longer-term Zig/Wasm host-bridge route (EmitZig → wasm32 → Wrangler) is
**Planned** research documented below for comparison; it is not what `main`
runs today.

## Pipeline (Planned — Zig/Wasm research)

```text
Lean contract
  -> Lean frontend / LCNF
  -> EmitZig
  -> generated Zig contract module
  -> Cloudflare Workers Zig runtime + host bridge
  -> wasm32-freestanding or wasm32-wasi Wasm (WASI imports stripped/stubbed)
  -> Wrangler package (.wasm + wrangler.toml + metadata)
  -> wrangler dev / wrangler deploy
  -> Workers smoke (Miniflare or remote)
```

The host bridge exposes Workers platform APIs to Lean
`@[extern "lean_cf_*"]` declarations:

- KV read/write for persistent scalar/map storage.
- Request metadata / `Date.now()` for environment reads.
- `fetch()` for cross-call invoke.
- `console.log` for events.

## Target Profile

```lean
def wasmCloudflareWorkers : TargetProfile := {
  id := "wasm-cloudflare-workers",
  family := .wasmHost,
  artifactKind := .wasm,
  capabilities := #[
    .storageScalar,
    .storageMap,
    .callerSender,
    .eventsEmit,
    .crosscallInvoke,
    .envBlock,
    .cryptoHash,
    .controlConditional,
    .controlBoundedLoop,
    .dataFixedArray,
    .dataStruct,
    .assertions
  ],
  requiredTools := #["tsc", "wrangler"]
}
```

## Capability Mapping

| Capability id | Cloudflare Workers mapping | Notes |
|---|---|---|
| `storage.scalar` | Workers KV `get`/`put` or Durable Object state field | KV is eventually consistent; DO gives strong consistency per object |
| `storage.map` | KV with key prefix, or DO in-memory `Map` | First implementation can use string-keyed KV |
| `caller.sender` | Request header, JWT claim, or `env` binding | Configurable per deployment; no built-in signer concept |
| `events.emit` | `console.log` with structured JSON | Also routable to Workers Logs / Tail Workers |
| `crosscall.invoke` | `fetch()` to another Worker, service binding, or external HTTP endpoint | Returns HTTP response, not blockchain call result |
| `env.block` | `Date.now()` | No block height; only timestamp |
| `crypto.hash` | Web Crypto `crypto.subtle.digest` or Zig implementation | SHA-256 first; keccak256 via library if needed |
| `control.conditional` | Lean/Zig lowering | Native support |
| `control.bounded_loop` | Lean/Zig lowering | Native support |
| `data.fixed_array` | Lean/Zig value type | Native support |
| `data.struct` | Lean/Zig value type | Native support |
| `assertions.check` | Runtime panic / error response | Returns HTTP 500 or structured error |

Not supported by design:

- `value.native` — Workers has no native token transfer semantics.
- `storage.pda`, `crosscall.cpi` — Solana-specific.
- `zk.circuit`, `zk.proof` — not a ZK target.

## Runtime Profile

Strategy B from [RFC 0003](../rfcs/0003-portable-ir-and-runtime.md): full Lean
runtime plus a Cloudflare-specific host bridge.

Constraints:

- Single-threaded; no POSIX/libuv assumptions.
- No filesystem; all I/O through host bridge imports.
- Wasm-safe allocator (bump or custom).
- No native GMP; use Zig bigint or restrict arithmetic.
- HTTP request/response is the entry boundary, not a blockchain transaction.

## Entrypoint Shape

Exported Wasm function:

```text
fetch(request_ptr, request_len, env_ptr, ctx_ptr) -> response_ptr
```

The bridge:

1. Deserializes the incoming request (method, path, headers, body).
2. Dispatches to a contract entrypoint based on path or JSON message.
3. Runs the portable core with capabilities bound to Workers APIs.
4. Serializes the result into an HTTP response.

Example HTTP mapping for Counter:

- `POST /initialize` → `initialize`
- `POST /increment` → `increment`
- `GET /count` → `get`

## Storage Backend Options

### Option A: Workers KV (default for v0)

- Pros: simple, global, cheap.
- Cons: eventual consistency, no transactions, no numeric increment atomicity
  guarantees across simultaneous edge invocations.

### Option B: Durable Objects

- Pros: strong consistency, single-object atomicity, in-memory state.
- Cons: requires object ID routing, more complex binding setup.

v0 should use KV for Counter; v1 should introduce DO as an optional
`storage.scalar.strong` capability.

## Build Commands

```sh
lake env proof-forge emit --target wasm-cloudflare-workers \
  --fixture counter --format ts -o build/ts/Counter.ts
scripts/ts/counter-ir-smoke.sh
```

Smoke (package under `Examples/CloudflareWorkers/Counter/`):

```sh
scripts/ts/counter-ir-smoke.sh
# or, after emit:
npx wrangler deploy --dry-run
```

## Example Location

| Target | Path | Status |
|---|---|---|
| Cloudflare Workers | `Examples/CloudflareWorkers/Counter/` + IR emit `--format ts` | **In repo (Spike)** |

## Open Questions

1. Should the host bridge be written in Zig (consistent with NEAR/CosmWasm) or
   in Rust (better Cloudflare ecosystem)?
2. Should KV or DO be the default storage backend for the Counter spike?
3. How should authentication/caller identity be configured in `wrangler.toml`?
4. Should `crosscall.invoke` support service bindings only, or any HTTP URL?
5. How do we test atomicity and consistency in the shared scenario when Workers
   is not transaction-based?

## Acceptance Criteria for Spike Exit

- [x] `wasm-cloudflare-workers` target profile is in the registry.
- [x] Counter IR emits TypeScript accepted by `tsc` and `wrangler` dry-run.
- [ ] `wrangler dev` serves `POST /increment` and `GET /count` correctly.
- [x] Artifact metadata records `target: wasm-cloudflare-workers` and
      capabilities used (emit path).
- [ ] Wasm/Zig host-bridge route (optional research exit).
