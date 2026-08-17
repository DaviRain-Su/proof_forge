# Agent Note: XRPL Bedrock WASM is a new research leaf, not OpenVM and not the next default slice

Status: superseded by implemented note
`2026-08-17-xrpl-bedrock-source-q0.md` (ADR-0049 Q0 shipped)

## Problem

Bedrock compiles Rust to WASM and deploys via `ContractCreate` on
AlphaNet / local rippled. It is tempting to treat that as “we already
have Wasm hosts and OpenVM, just add another profile” or to jump it
ahead of CAP-1a / formal lighthouse because it looks like a new chain.

The host, account model, and networks are not NEAR, not OpenVM, and
not the XRPL EVM sidechain. Mainnet XRPL cannot take this bytecode.

## Proposal

Keep support as **research → optional source-only Q0**
([`docs/plan/xrpl-bedrock-wasm-gap.md`](../../../../docs/plan/xrpl-bedrock-wasm-gap.md)
option A). Dossier [`docs/targets/16-xrpl.md`](../../../../docs/targets/16-xrpl.md).
No `TargetId` until an implementation ADR. Do not schedule Wave 2 as
the default Next task.

Hooks and EVM sidechain stay out of this TargetId.

## Alternatives considered

- **Reuse `OpenVmPlan` / guest Rust templates** — rejected: OpenVM is
  RV32IM + prove; Bedrock is XRPL host + `ContractCall`. Same language
  family, different ISA/host/settlement.
- **Reuse `IcpPlan` / `NearPlan` because “WASM”** — rejected: RPT-025
  already forbids `GenericWasmHostPlan`.
- **Start at AlphaNet `ContractCreate` in product Finalize** — rejected:
  experimental net, 100 XRP reserve, unlocked bedrock/xrpl.js. Same class
  of silent host ADR-0044 forbids on Soroban S0.
- **One `xrpl` target covering Hooks + EVM sidechain + Bedrock** — rejected:
  three transaction systems and two ledgers.
- **Make this the default Next instead of CAP-1a** — rejected unless
  the owner reorders: CAP-1a deepens an existing implemented leaf.

## Acceptance criteria

- Live docs point at the dossier + gap + tasks.
- Registry unchanged (still 12+0).
- Next coding default remains CAP-1a unless the owner says otherwise.
- Wave 2 does not start without a proposed implementation ADR.
