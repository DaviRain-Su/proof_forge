# Arbitrum Stylus Target

## Status

`wasm-arbitrum-stylus` is a **docs-only** research target. It is not present in
the target registry, `--list-targets`, the CLI build whitelist, or the primary
triad. This document classifies the target and freezes its toolchain and
architecture before implementation.

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

## Planned Supported Fragment

1. Counter: `u256` scalar storage, ABI dispatch, checked arithmetic, cache flush.
2. ValueVault: address, sender, value, block context, authorization, payable.
3. Token: mappings, indexed events, allowance, EVM ABI interoperability.
4. RemoteCall: call modes, value/gas, return data, revert, reentrancy.
5. Aggregates: structs, arrays, bytes, string, dynamic ABI and storage layouts.

"Any contract" means any validated canonical contract entirely inside the
implemented Stylus capability fragment. Unsupported operations fail before
artifact emission with a named target/function/operation diagnostic.

## Promotion Gates

Registry work remains blocked until the plan contract and strict validator
exist. Later promotion requires deterministic Rust SDK generation, Rust tests,
`cargo stylus check`, target-native local execution, exact Solidity ABI and
storage vectors, complete artifacts, direct Wasm compilation, Rust/direct trace
parity, resource evidence, and static CI. Live RPC/deployment remains optional.

Passing `cargo stylus check` alone is not runtime or deployment evidence.

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
