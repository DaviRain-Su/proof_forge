---
id: PLAN-XRPL-BEDROCK-WASM-GAP
title: XRPL Bedrock WASM — research gap and Q0 shape
status: draft
owner: engineering
updated: 2026-08-17
normative: false
---

# XRPL Bedrock WASM：缺口与 Q0 形态

> Research / engineering inventory. Does **not** add `TargetId.xrpl`,
> does **not** implement a materializer, does **not** call bedrock /
> rustc / AlphaNet from product Finalize, does **not** expand accepted
> PRD, does **not** close formal TASK/TST.
> Dossier: [`../targets/16-xrpl.md`](../targets/16-xrpl.md).
> Tasks: [`xrpl-bedrock-wasm-tasks.md`](xrpl-bedrock-wasm-tasks.md).

## 1. Why this is worth a lane

Bedrock is the closest “Foundry for XRPL” surface: Rust → WASM →
`ContractCreate` on a **native** ledger VM with a dedicated host
(`ContractCall`, emit native txs, on-ledger ABI). That is a real
execution model PF does not have.

It is **not** a cheap OpenVM or CosmWasm clone. The host, account
model (pseudo-account), and networks (AlphaNet only) are unique.

## 2. What “support” may mean (pick one; default = A)

| Option | Shape | Honest ceiling | Cost |
|---|---|---|---|
| **A. Source-only Q0** (recommended) | Plan/IR → controlled Rust guest (`xrpl_wasm` dialect) + catalog; zero-tool Finalize; `deployable=false` | `pf build --target xrpl` emits `.rs`, not a live contract | Soroban S0 / OpenVM O0 sized |
| **B. Opt-in WASM** | locked rustc → `.wasm` extra; still `deployable=false` | artifact is bytecode, not an XRPL account | OpenVM O1 sized + rustc Tool Lock |
| **C. AlphaNet deploy** | product or host-optional `ContractCreate` | live `r…` contract on experimental net | new Tool Lock (bedrock or xrpl.js), faucet, 100 XRP reserve story |
| **D. Escrow/Vault too** | XLS-0100 predicates in the same TargetId | mixes three primitives | reject for first ADR |
| **E. Hooks or EVM sidechain under `xrpl`** | — | **forbidden** | different chains / txs |

Default until a product pick: **A only**. B/C need an explicit yes.
D/E stay out.

## 3. Mapping risk (why Q0 is narrow)

| PF surface | XRPL Bedrock fact | Q0 |
|---|---|---|
| `entry` / `view` | exported WASM fn + `ContractCall` | emit fn stubs; no live call |
| `state` | `ContractData` / host storage API | name-only slots in source |
| checked `+`/`-` | guest rust + host traps unknown | rust `checked_*` + `trace`; no silent wrap |
| `call` / `schedule` | emit Payment / OfferCreate / another `ContractCall` | **FC** (`B-CALL-SEM`) |
| ContextRead | ledger header / account fields via host | **FC** until CAP-D yes（ADR-0052 已冻 TIME/CALLER 符号） |
| `pf.crypto.sha256` | 无 host；仅 `compute_sha512_half` | **FC**（ADR-0052 keep-FC；不得冒充 sha256） |
| invariants | no XRPL equivalent | **FC** |
| deployable | AlphaNet / local only | `false` |

## 4. Family and reuse bans

- New family candidate: XRPL smart-features.
- **Do not** reuse `OpenVmPlan`, `NearPlan`, `IcpPlan`, `SorobanPlan`,
  `EvmPlan`, or a future `HooksPlan`.
- **Do not** put this row in `family-wasm-host.md` as “another import
  table”. Shared encoder is allowed later; shared Plan is not.
- CAP-layer (`capability-layer-tasks.md`) 的 **CAP-1a…5 叶**仍在既有 12。
  XRPL 只到 ADR-0052 / `CAP-D-XRPL-*`；**不开** XRPL CAP leaf。

## 5. Order versus other work

| Ahead of XRPL | Why |
|---|---|
| Formal D1-01 / D2 (human axis) | ADR-0036 lighthouse |
| CAP-1a ICP time | existing leaf, unbound host |
| Independent implementation ADR | RPT-025 档 C 门槛 |

XRPL does **not** jump the 12-target honesty queue or formal 0/27.

## 6. Non-claims

No registry row. No `just ci` shard. No mainnet. No “XRPL is WASM so
OpenVM guest works”. No Hooks. No EVM sidechain credit.
