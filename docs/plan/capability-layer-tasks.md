---
id: PLAN-CAP-LAYER-TASKS
title: 十二 target 同一能力层 — 任务拆分
status: draft
owner: engineering
updated: 2026-08-15
normative: false
---

# 十二 target 同一能力层：任务拆分

> Engineering tasks only. **Not** `docs/04-task-breakdown.md` formal
> `TASK-*`. Do not mark TST/EV done. Design:
> [`capability-layer-parity.md`](capability-layer-parity.md).
> Verify with focused `lake env lean <suite>`, never
> `lake build proof_forge_next_tests_shard_*`.

Shared-core stays serial. Target leaves may run in parallel when
allowlists do not overlap. Skip a row rather than invent a host.

## Wave 0 — entry (this change)

| ID | Status | Objective | Allowlist | Verify |
|---|---|---|---|---|
| **CAP-0** | **this PR** | Point live entry at the design + this breakdown | `docs/index.md` · `AGENTS.md` · `RECOVERY.md` · `docs/document-status.md` · `docs/engineering-backlog.md` · `docs/research/README.md` · `docs/research/28-project-wide-honesty-audit.md` · `.grok/next-wave-queue.md` | `just docs-check` |

## Wave 1 — do not code until a human picks

These are product decisions. Goal / Amp must **stop** and ask.

| ID | Decision | If yes | If no |
|---|---|---|---|
| **CAP-D-SOL-TIME** | Solana `unixTimeSeconds` ← `Clock.unix_timestamp` (i64, stake-weighted)? | CAP-2 | keep named FC |
| **CAP-D-TON-SHA** | Lift TON feature freeze for honest stdlib sha256 (not `string_hash`)? | CAP-5 | keep FC |
| **CAP-D-SOR-LEDGER** | Allow S0 Plan to emit `env.ledger()` / `env.crypto.sha256` without Wasm Finalize? | CAP-3 / CAP-4 | keep named FC |
| **CAP-D-ICP-PRINCIPAL** | ICP caller valueBytes = ADR-0025-class `u32le(len)‖principal`? | CAP-1b | keep FC |

Default if nobody answers: **only CAP-1a** (ICP time) is unblocked.

## Wave 2 — state-class deepen (existing targets)

| ID | Pri | Objective | Files (expected) | Done when | Not |
|---|---|---|---|---|---|
| **CAP-1a** | P1 | **done 2026-08-15**: ICP `context.unixTimeSeconds` → `ic0.time` ns÷10⁹ on init/entry/query | `Targets/Icp/{Lower,Emit,Validate}*` · `IcpPlanV1` · `Targets.lean` needle · matrix §1d | Plan/IR/WAT pin + named diagnostic gone for this key only | PocketIC formal; blockHeight |
| **CAP-1b** | P1 | ICP `context.caller` → `msg_caller` after CAP-D-ICP-PRINCIPAL | same + Principal codec comment | S1-shaped pin; view policy named | mapping Principal→account-id globally |
| **CAP-2** | P1 | Solana `unixTimeSeconds` → Clock sysvar after CAP-D-SOL-TIME | `Targets/Solana/CpiDeriveV1.lean` · Mollusk companion if host-optional | product profile admits; `unixTime` FC pin removed; `blockHeight` unchanged | Clock.slot alias; formal D5 |
| **CAP-3** | P2 | Soroban S0 `unixTimeSeconds` / `blockHeight` → `env.ledger().timestamp/sequence` after CAP-D-SOR-LEDGER | `Targets/Soroban/LowerSemanticV1.lean` · `SorobanPlanV1` | `.rs` contains ledger reads; Finalize still zero-tool | SOR-1 Wasm / auth / TTL |
| **CAP-4** | P2 | Soroban S0 `pf.crypto.sha256` UInt256→UInt256 → `env.crypto.sha256` after CAP-D-SOR-LEDGER | same + crypto FC test rewrite | exact QN lowered; other `pf.crypto.*` still named FC | Bytes ABI; stellar-cli |
| **CAP-5** | P2 | TON honest SHA-256 after CAP-D-TON-SHA | `Targets/Ton/LowerSemanticV1.lean` · `TonPlanV1` | stdlib sha256 (document which); `string_hash` still not used | keccak; pf.assets; unfreeze whole TON |
| **CAP-6** | P3 | **done 2026-08-15** (unixTime leaf): N5 matrix admits ICP; decline list +Quint/Soroban. Focused `/tmp/run_Cap6UnixTimeMatrix.lean` | `Tests/Materialization/Targets.lean` | focused driver, not shard / full Targets.run | opening `Tests.lean` in LSP |

## Wave 3 — explicitly out

| ID | Why skip |
|---|---|
| **CAP-X-NEW-TARGET** | No cairo/risc0/sp1/Move/Bitcoin this wave (RPT-025/026) |
| **CAP-X-MERKLE** | [EXT-CRYPTO auto-open rejected](../../.agents/notes/rejected/architecture/2026-08-15-ext-crypto-auto-open.md) |
| **CAP-X-BYTES** | Shared-core `sha256Bytes`; separate cutover |
| **CAP-X-CW-SHA** | CosmWasm has no sha256 host — keep F |
| **CAP-X-ICP-HEIGHT** | ICP has no block-height API — keep F |
| **CAP-X-CIRCUIT** | Noir/OpenVM/Psy chain-anchored keys stay F |
| **CAP-X-FORMAL** | [Goal ↛ formal](../../.agents/notes/implemented/process/2026-08-15-goal-must-not-close-formal.md) |

## Suggested serial order once P1a is picked

```text
CAP-0 (docs, now)
  → CAP-1a (ICP time)
  → CAP-6 needles
  → wait CAP-D-*
      → CAP-1b / CAP-2 / CAP-3+4 / CAP-5  (disjoint allowlists, parallel OK)
  → stop
```

One local commit per ID. Touch `ProofForgeV2/**` → `just sbom-package-files-refresh`.
Docs → `just docs-check`. Do not push unless asked.
