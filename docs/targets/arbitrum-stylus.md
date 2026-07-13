# Arbitrum Stylus Target

## Status

`wasm-arbitrum-stylus` is a **research** `contract_source` target. It is present
in the target registry, `--list-targets`, and the CLI build route, but it is not
part of the primary triad. The public route defaults to a direct HostIO Wasm
bundle and retains the pinned Rust SDK renderer as an explicit oracle. Bundles
are locally executable and hash-bound, but absent live Nitro evidence is
published as `unavailable`; research artifacts are not release promotion.

## Classification

Stylus contracts are Wasm programs that execute with Ethereum contract
semantics. ProofForge classifies Stylus under the `wasmHost` family because its
deployable program is Wasm, but it must not reuse the NEAR/Soroban ABI or
string-key storage plan.

The target owns a `StylusPlan` with Solidity ABI selectors and calldata,
EVM-compatible 256-bit slots and 32-byte storage words, EVM events and calls,
Stylus HostIO, storage-cache flushes, gas/ink, and artifact metadata.

## Final Pipeline

```text
Canonical Contract
  -> Stylus capability validation
  -> StylusPlan
       |-> Rust SDK renderer -> cargo stylus -> Wasm
       `-> Direct Wasm renderer -> Stylus HostIO Wasm
```

**Direct Wasm** is the final canonical renderer. The **Rust SDK** renderer is
the bootstrap implementation, compatibility route, and differential oracle.
Both renderers consume the same immutable plan; neither may re-derive contract
semantics from source text or legacy IR.

## Toolchain Pin

The bootstrap baseline is exact:

- `stylus-sdk = "=0.10.8"`
- `cargo-stylus = "=0.10.8"`
- Rust `1.91.0`
- target `wasm32-unknown-unknown`

Version ranges, `latest`, and unbounded git dependencies are not accepted. A
pin change requires regenerated Rust/direct differential evidence.

## Semantic Differences

| Concern | Stylus | NEAR/Soroban paths |
|---|---|---|
| Public ABI | Solidity ABI and four-byte selectors | Borsh/JSON or Soroban spike ABI |
| Persistent state | EVM State Trie, 256-bit slots, 32-byte words | Host key-value bindings |
| Write lifecycle | cache word, then flush | target-specific direct host write |
| Events | up to four EVM topics plus data | target-native log/event ABI |
| Calls | EVM call modes and return-data buffer | promise/invoke host models |
| Resources | EVM gas plus Stylus ink | target-native units |

The reusable pieces are canonical IR, neutral Solidity ABI/storage planning,
the Wasm AST/printer, artifacts, and generic refinement infrastructure. The
Stylus backend must not route through `NearModulePlan`.

## Implemented And Open Fragment

1. Counter (research implementation): `u64` scalar storage, ABI dispatch,
   checked arithmetic, cache flush, direct WAT compilation, and abstract/direct
   normalized trace parity. Static `bool`/`u8`/`u32`/`u64` function parameters
   are plan-owned and lowered by both renderers; direct dispatch rejects
   non-canonical ABI padding before the call.
   Direct `uint128` parameters and `msg.value` use checked 16-byte big-endian
   memory values, with ABI return, equality, literal, checked/wrapping add, and
   scalar storage support, including wide ordering and checked scratch bounds.
2. ValueVault: address, sender, value, block context, authorization, payable,
   canonical Core planning, local rollback, and event traces.
3. Token (research implementation): shared `TokenSpec` materializes through the
   canonical ERC-20 body, address-keyed balances and nested allowances, indexed
   events, standard Solidity selectors, Rust SDK/direct Wasm renderers, and a
   local VM lifecycle. The public CLI route is
   `proof-forge build --target wasm-arbitrum-stylus --token ...`.
4. RemoteCall: call/static/delegate modes, value/gas, bounded static/dynamic
   return data, revert propagation, cache transitions, and local nested frames.
   Generated Rust and the direct local runner produce equal versioned common
   traces for target, mode, calldata, value, status, and result. Cache and frame
   traces are runner-only because the pinned upstream TestVM does not expose
   them. Nitro two-contract evidence remains.
5. Aggregates: bytes/string and fixed-array ABI carriers are product/CLI covered;
   local fixtures cover bounded tuples and dynamic arrays. Recursive dynamic
   children, dynamic storage transitions, and allocation/page exhaustion remain.

"Any contract" means any validated canonical contract entirely inside the
implemented Stylus capability fragment. Unsupported operations fail before
artifact emission with a named target/function/operation diagnostic.

## Promotion Gates

Promotion beyond research requires `cargo stylus check`, target-native direct
`vm_hooks` execution, exact Solidity ABI and storage vectors, complete
deployable artifacts, Rust/direct runtime trace parity, resource evidence, and
static CI. Direct WAT compilation plus abstract trace parity is only an
intermediate gate. Pinned local Nitro activation/deployment is required for
promotion; public Sepolia and mainnet deployment remain optional/manual.

Passing `cargo stylus check` alone is not runtime or deployment evidence.

## Local Wasm Runner

`tools/stylus-vm-runner` executes generated direct Wasm with Wasmtime and the
currently implemented `vm_hooks` fragment. It preserves storage/cache across
multiple exports and accepts sender, value, contract, block, and initial slot
injection. For example:

```bash
cargo run --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  build/stylus/counter-differential/counter.wasm \
  __pf_initialize __pf_increment __pf_get
```

For independent calldata vectors against one compiled module, pass a file with
one hex payload per line via `--calldata-file`. The runner compiles the module
once, creates a fresh Store for every line, and returns results under `batch`;
this avoids cross-case state while keeping differential gates fast.

Run `just stylus-vm-runner` for the checked Counter and authorization smokes.
This proves that emitted Wasm bytecode instantiates and executes; it is a local
compatibility host, not Nitro activation, `cargo stylus check`, or deployment
evidence.

The official companion gate is `just stylus-official-check`. It passes the
same direct Wasm to `cargo stylus check --wasm-file`, which performs Arbitrum
instrumentation and activation validation through an RPC endpoint. It is a
named local skip when the pinned cargo-stylus tool is absent. The local runner
is retained because official `replay` consumes a chain transaction trace and
loads native shared libraries for debugging; it is not an offline Wasm
interpreter API.

## Full Nitro Development Chain

ProofForge pins the official Nitro Testnode revision in
`tools/stylus-nitro/nitro-testnode.rev`; the upstream `release` branch is not
followed implicitly because it may be force-pushed. Docker and Docker Compose
are required.

```bash
just stylus-nitro-install  # clone and verify the pinned revision
PROOF_FORGE_NITRO_RESET=1 just stylus-nitro-init  # destructive: fresh L1/L2 state
just stylus-nitro-doctor   # machine-readable toolchain and RPC readiness
just stylus-nitro-status   # wait for http://127.0.0.1:8547
just stylus-nitro-check    # cargo stylus check --wasm-file over local RPC
just stylus-nitro-deploy   # deploy and activate direct Wasm
just stylus-nitro-e2e      # initialize, increment, and ABI-read Counter == 1
just stylus-nitro-down
```

After the first initialization, use `just stylus-nitro-up` to restart without
resetting chain data. The local developer key written under `build/` is the
well-known Nitro Testnode key and must never be used on a public network.
For direct `--wasm-file` commands, the scripts create an ignored empty
Cargo/Stylus workspace under `build/`; cargo-stylus 0.10.8 otherwise attempts
to load project metadata even though it does not compile a Rust crate.
The doctor reports `ready`, exact Rust/cargo-stylus versions, Docker, Foundry,
the checked-out Nitro revision, endpoint, and chain ID as JSON. Docker and RPC
probes have hard timeouts so an unhealthy local VM produces evidence and a
nonzero exit instead of hanging indefinitely.

Sepolia is deliberately separate and requires an explicit key path:

```bash
PROOF_FORGE_STYLUS_PRIVATE_KEY_PATH=/secure/sepolia.key \
  just stylus-sepolia-e2e
```

There is no automatic mainnet deployment recipe. Mainnet uses the same
`cargo stylus check/deploy` protocol, but release approval, RPC selection, key
custody, and deployment must remain explicit operational actions.

## Authoritative Sources

- <https://github.com/OffchainLabs/stylus-sdk-rs>
- <https://github.com/OffchainLabs/cargo-stylus>
- <https://raw.githubusercontent.com/OffchainLabs/stylus-sdk-rs/main/stylus-sdk/src/hostio.rs>
- <https://raw.githubusercontent.com/OffchainLabs/stylus-sdk-rs/main/rust-toolchain.toml>

## Related Design

- [Hybrid backend design](../superpowers/specs/2026-07-12-arbitrum-stylus-hybrid-backend-design.md)
- [Implementation plan](../superpowers/plans/2026-07-12-arbitrum-stylus-hybrid-backend.md)
- [Wasm family](wasm-family.md)
- [EVM target](evm.md)
