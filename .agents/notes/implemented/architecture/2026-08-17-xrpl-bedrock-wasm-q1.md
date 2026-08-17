# Agent Note: XRPL Bedrock opt-in WASM Q1 shipped as ADR-0050

Status: implemented 2026-08-17

## What shipped

Dual profile on the existing `TargetId.xrpl` leaf:

- default remains `xrpl-bedrock-source-u64-v1` (ADR-0049 zero-tool)
- opt-in `xrpl-bedrock-wasm-u64-v1` wraps the same `{name}.rs` in a temp
  cdylib and runs ambient `cargo build --target wasm32-unknown-unknown --release`
- extra path `xrpl-build/{program}.wasm`
- `xrpl-wasm-std` git rev `ffbe88da26df27e59a72b6202883f42f696933cc`
- resolver 16 → 17; registry still 13+0
- `deployable=false`; no bedrock / ContractCreate / AlphaNet / mainnet

## Why not a Tool Lock rustc pin

There is no content-addressed rustc asset in `toolchains.lock.json`.
craft's own toolchain file wants `1.89.0` + `wasm32v1-none`; scaffold-xrp
builds with host rustc + `wasm32-unknown-unknown`. Q1 records that honestly
as ambient, same class as OpenVM's rustup prerequisite.

## Alternatives considered

- Fold rustc into the default source profile — rejected: breaks ADR-0049
  zero-tool and the OpenVM/Noir dual-profile precedent.
- Pin rustc as a Tool Lock binary — rejected: no content-addressed rustc
  asset exists; claiming one would be dishonest.
- Switch Q1 to official `ripple/xrpl-wasm-stdlib` + `wasm32v1-none` —
  rejected: A already emits the scaffold-xrp / `xrpl_wasm_std` dialect.
- Jump to AlphaNet `ContractCreate` — rejected: that is XRPL-10 / C.

## Not done

XRPL-10 AlphaNet `ContractCreate`. Official `xrpl-wasm-stdlib` /
`wasm32v1-none` switch. Formal 0/27.
