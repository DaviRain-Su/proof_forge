# ProofForge Documentation Index

ProofForge is a Lean-first multi-chain smart contract platform. The trunk
contains the EVM baseline plus Solana (sBPF assembly), NEAR (EmitWat), Psy/DPN,
Aleo Leo, and Cloudflare Workers backends behind one portable IR and capability
registry, following the 2026-07 branch consolidation.

**Current phase:** Gate P0 is closed for the three primary product chains:
`solana-sbpf-asm`, `evm`, and `wasm-near`. The next hardening lane is the
CLI M3/M4 migration from legacy flags to
`proof-forge build|emit|check --target ...`; Tier-1 M3/M4 work waits behind
that cleanup.

## Documentation Map

| If you are… | Start here | Then read |
|---|---|---|
| New contributor | This page + [README](../README.md) + [Onboarding](onboarding.md) | [Portable three-target tutorial](tutorials/portable-contract-three-targets.md), [Validation gates](validation-gates.md), [backlog](implementation-backlog.md) |
| Implementing a backend | [RFC 0002](rfcs/0002-target-implementation-design.md) | [decisions](decisions.md), [portable IR](portable-ir.md), target notes |
| Reviewing design | [review-checklist](review-checklist.md) | RFCs, [capability registry](capability-registry.md), [shared scenario](shared-scenario.md) |
| Strategy / 中文读者 | [zh/README](zh/README.md) | [可行性分析](zh/feasibility-analysis.md), [decisions](decisions.md) |

```mermaid
flowchart TB
  INDEX[INDEX.md]
  RFC1[RFC 0001 vision]
  RFC2[RFC 0002 engineering]
  DEC[decisions.md]
  IR[portable-ir.md]
  CAP[capability-registry.md]
  SCN[shared-scenario.md]
  BL[implementation-backlog]
  TGT[targets/*]
  INDEX --> RFC1
  INDEX --> RFC2
  INDEX --> DEC
  RFC2 --> IR
  RFC2 --> CAP
  DEC --> BL
  IR --> SCN
  BL --> TGT
```

## Specs and Decisions

- [Design decisions](decisions.md): settled architecture choices and roadmap summary.
- [Portable Contract IR](portable-ir.md): IR sketch and Phase 1 acceptance criteria.
- [RFC 0003: Portable IR and runtime](rfcs/0003-portable-ir-and-runtime.md): detailed IR/capability/runtime draft.
- [RFC 0004: EVM semantic plan and Yul AST boundary](rfcs/0004-evm-semantic-plan.md): target-semantic EVM plan layer between portable IR and low-level Yul syntax.
- [Capability registry](capability-registry.md): canonical capability ids.
- [Shared scenario: Counter](shared-scenario.md): cross-target acceptance test.
- [Tutorial: one module, three targets](tutorials/portable-contract-three-targets.md): portable `contract_source` walkthrough (CS-5.3).

## RFCs

Accepted engineering direction ([rfcs/README](rfcs/README.md)):

- [RFC 0001: Lean-first multi-chain contract platform](rfcs/0001-multichain-platform.md)
- [RFC 0002: Target implementation design](rfcs/0002-target-implementation-design.md)
- [RFC 0003: Portable IR and runtime profiles](rfcs/0003-portable-ir-and-runtime.md) (Draft — extends 0001/0002)
- [RFC 0004: EVM semantic plan and Yul AST boundary](rfcs/0004-evm-semantic-plan.md) (Draft — EVM backend internal architecture)
- [RFC 0005: Solana sBPF assembly backend](rfcs/0005-solana-sbpf-assembly-backend.md) (Accepted — canonical Solana route, D-026)
- [RFC 0006: Multi-chain Token SDK](rfcs/0006-multichain-token-sdk.md) (Draft)
- [RFC 0007: Unified Rust test framework](rfcs/0007-unified-rust-test-framework.md) (Draft — testkit scenarios over revm/Mollusk/wasmtime)
- [RFC 0008: Chain-decoupled allocator abstraction](rfcs/0008-allocator-abstraction.md) (Draft — one allocator model bound per target)

## Engineering

- [Development standards](development-standards.md): contributor rules and source-of-truth map.
- [Onboarding](onboarding.md): local setup path, editor notes, and the minimum
  validation loop for new contributors.
- [Development log](development-log.md): milestone log with validation notes and next steps.
- [Authoring model](authoring-model.md): Learn source, `contract_source`, and internal `ContractSpec` boundaries.
- [Validation gates](validation-gates.md): runnable gates and tool prerequisites.
- [Formal verification roadmap](formal-verification.md): existing formal anchors and staged proof targets.
- [Target portfolio roadmap](target-roadmap.md): tiered sequencing for the remaining research targets and the Bitcoin policy family (D-034).
- [Platform gap analysis 2026-07](platform-gaps-2026-07.md): unplanned dimensions (CLI surface, versioning, budgets, upgrades/signing, error model, clients) and their sequencing hooks.
- [Implementation backlog](implementation-backlog.md): staged tasks and acceptance criteria.
- [Review checklist (English)](review-checklist.md)
- [Target notes](targets/README.md): per-family research and spike plans.
  - [EVM](targets/evm.md)
  - [Wasm family](targets/wasm-family.md)
  - [Wasm-NEAR](targets/wasm-near.md)
  - [Cloudflare Workers target](targets/cloudflare-workers.md)
  - [Stellar Soroban target](targets/stellar-soroban.md)
  - [Internet Computer target](targets/internet-computer.md)
  - [Algorand AVM target](targets/algorand-avm.md)
  - [Solana sBPF Asm](targets/solana-sbpf-asm.md) (canonical direct-assembly route)
  - [Solana sBPF](targets/solana-sbf.md) (superseded Zig/sbpf-linker route)
  - [Move family](targets/move-family.md)
  - [Cardano Plutus/Aiken target](targets/cardano-plutus-aiken.md)
  - [Tezos Michelson/LIGO target](targets/tezos-michelson-ligo.md)
  - [Starknet Cairo target](targets/starknet-cairo.md)
  - [Aleo Leo target](targets/aleo-leo.md)
  - [Aleo Leo design spec](superpowers/specs/2026-07-01-aleo-leo-design.md)
  - [TON TVM target](targets/ton-tvm.md)
  - [Bitcoin Script/Miniscript target](targets/bitcoin-script-miniscript.md)
  - [Zcash Shielded target](targets/zcash-shielded.md)
  - [Bitcoin Cash CashScript target](targets/bitcoin-cash-cashscript.md)
  - [Psy DPN ZK target](targets/psy-dpn.md)
  - [Kaspa Toccata target](targets/kaspa-toccata.md)

## Chinese Notes

- [中文文档索引](zh/README.md)
- [架构评审 2026-07：统一 SDK 输入与分支收敛](zh/architecture-review-2026-07.md)
- [多链愿景可行性分析](zh/feasibility-analysis.md)
- [多链技术实现方案](zh/technical-implementation-plan.md) — summary; engineering detail in RFC 0002
- [多链方案 Review 清单](zh/review-checklist.md)
- [Psy/DPN ZK Target 初步分析](zh/zk-psy-target-analysis.md)

## Current Implementation Baseline

- The target registry (`ProofForge/Target/Registry.lean`), portable IR
  (`ProofForge/IR/Contract.lean`), capability routing, and
  `proof-forge-artifact.json` emission are implemented.
- EVM: `proof-forge build --target evm` compiles Lean contracts through LCNF,
  Yul, and `solc --strict-assembly`; portable-IR contracts lower through the
  EVM semantic plan (`Backend/Evm/Plan.lean`). Foundry and Anvil smokes
  validate runtime behavior.
- Solana: `proof-forge emit --target solana-sbpf-asm --format s|elf` emits
  sBPF assembly and ELF packages, validated by Mollusk, Surfpool/Web3.js, and
  Pinocchio equivalence gates.
- NEAR: `proof-forge emit|build --target wasm-near --format wat` lowers
  portable IR through the Wasm AST to WAT, with formal trace obligations
  (`Tests/NearWasmFormal.lean`), target-first metadata, and an offline host
  smoke.
- Psy/DPN, Aleo Leo, and Cloudflare Workers emit target sources from
  portable IR fixtures; see [validation-gates.md](validation-gates.md) for
  each gate's tool prerequisites.
