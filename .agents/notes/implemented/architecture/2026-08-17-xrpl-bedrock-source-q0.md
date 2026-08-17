# Agent Note: XRPL Bedrock source-only Q0 is a new TargetId, not OpenVM and not AlphaNet

Status: implemented

## Problem

Bedrock compiles Rust to WASM and deploys via `ContractCreate` on AlphaNet /
local rippled. It is tempting to reuse `OpenVmPlan` / `NearPlan` or to call
bedrock/rustc from product Finalize.

## Proposal

Ship ADR-0049 Q0: `TargetId.xrpl` + sole `xrpl-bedrock-source-u64-v1`.
Independent Plan/IR emits a scaffold-xrp Counter-shaped `{name}.rs`
(`xrpl_wasm_std`, `get_data`/`set_data`, `#[unsafe(no_mangle)]`).
Zero-tool Finalize; `deployable=false`. Registry 13+0; resolver 16 rows.

## Alternatives considered

- **Reuse `OpenVmPlan` / guest Rust templates** — rejected: OpenVM is RV32IM
  + prove; Bedrock is XRPL host + `ContractCall`.
- **Reuse `IcpPlan` / `NearPlan` because “WASM”** — rejected: RPT-025 forbids
  `GenericWasmHostPlan`.
- **Start at AlphaNet `ContractCreate` in product Finalize** — rejected:
  experimental net; same class of silent host ADR-0044 forbids on Soroban S0.
- **One `xrpl` target covering Hooks + EVM sidechain + Bedrock** — rejected:
  three transaction systems and two ledgers.
- **Emit invented `#[xrpl_function]` / `host_storage`** — rejected: scaffold
  uses doc comments + `get_data`/`set_data`.

## Acceptance criteria

- `pf build --target xrpl` emits `{name}.rs`.
- Finalize evidence names rustc / bedrock / ContractCreate / AlphaNet / mainnet.
- Unknown profile is `PF-PROFILE-UNKNOWN`.
- Accepted PRD still four targets. Formal 0/27 unchanged.
