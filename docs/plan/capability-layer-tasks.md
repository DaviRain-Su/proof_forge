---
id: PLAN-CAP-LAYER-TASKS
title: 十二 target 同一能力层 — 任务拆分
status: draft
owner: engineering
updated: 2026-08-16
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

## Wave 1 — product decisions（**已全部拍板：2026-08-16 owner 决定全开**）

These are product decisions. Goal / Amp must **stop** and ask.

| ID | Decision | Decided | Unlocks |
|---|---|---|---|
| **CAP-D-SOL-TIME** | Solana `unixTimeSeconds` ← `Clock.unix_timestamp` (i64, stake-weighted)? | **yes（2026-08-16）** | CAP-2 |
| **CAP-D-TON-SHA** | Lift TON feature freeze for honest stdlib sha256 (not `string_hash`)? | **yes（2026-08-16；仅解冻 sha256 一项，不整体解冻 TON） ** | CAP-5 |
| **CAP-D-SOR-LEDGER** | Allow S0 Plan to emit `env.ledger()` / `env.crypto.sha256` without Wasm Finalize? | **yes（2026-08-16）** | CAP-3 / CAP-4 |
| **CAP-D-ICP-PRINCIPAL** | ICP caller valueBytes = ADR-0025-class `u32le(len)‖principal`? | **yes（2026-08-16）** | CAP-1b |

四项决策均只授权「绑定真实 host 或 named fail-closed」，不发明伪能力、不改 catalog、
不扩 accepted PRD、不关 formal TASK/TST。CAP-2 / CAP-1b / CAP-3 / CAP-4 / CAP-5 现为可编码行。

## Wave 2 — state-class deepen (existing targets)

| ID | Pri | Objective | Files (expected) | Done when | Not |
|---|---|---|---|---|---|
| **CAP-1a** | P1 | **done 2026-08-15**: ICP `context.unixTimeSeconds` → `ic0.time` ns÷10⁹ on init/entry/query | `Targets/Icp/{Lower,Emit,Validate}*` · `IcpPlanV1` · `Targets.lean` needle · matrix §1d | Plan/IR/WAT pin + named diagnostic gone for this key only | PocketIC formal; blockHeight |
| **CAP-1b** | P1 | **done 2026-08-16**: ICP `context.caller` → `ic0.msg_caller_size/copy`（ADR-0025-class `u32le(len)‖bytes`，max 29；9-leaf len+8×u64；Principal identity storage/param/`==`/`!=` S1-shaped；init/entry admit、query/view 名义 FC `ICP-VIEW-CALLER`；Principal result/`self` 仍 FC） | `Targets/Icp/{LowerSemantic,ValidatePlan,EmitIR}V1` + façade · `IcpPlanV1` pins · N5 caller matrix | S1-shaped pin; view policy named | mapping Principal→account-id globally |
| **CAP-2** | P1 | **done 2026-08-16**: Solana `unixTimeSeconds` → `Clock.unix_timestamp`（i64@32 raw bits as u64，同 `sol_get_clock_sysvar` 路径；escrow composite 仍 FC） | `Targets/Solana/{LowerSemantic,CpiDerive,EmitIR,EmitSbpfAsm,PlanSchema,ValidatePlan}V1` · `SolanaCpiDeriveV1`/`SolanaPlanV1`/`SolanaCpiPfAssetsV1` pins · N5 admit · Mollusk `unix_time_seconds.rs` 4/4 | product profile admits; `unixTime` FC pin removed; `blockHeight` unchanged | Clock.slot alias; formal D5 |
| **CAP-3** | P2 | **done 2026-08-16**: Soroban S0 `unixTimeSeconds`/`blockHeight` → `env.ledger().timestamp()`/`u64::from(env.ledger().sequence())`（init/entry/view；attachedValue/chainId/caller/self 仍名义 FC） | `Targets/Soroban/{LowerSemantic,ValidatePlan,EmitIR}V1` + façade · `SorobanPlanV1` pins · N5 admit | `.rs` contains ledger reads; Finalize still zero-tool | SOR-1 Wasm / auth / TTL |
| **CAP-4** | P2 | **done 2026-08-16**: Soroban S0 `pf.crypto.sha256` UInt256→UInt256 → `env.crypto().sha256`（32-byte LE wire image = 4×u64 LE limbs；UInt256 仅 sha256 plumbing，state/param/result/arith 仍 FC；keccak256/siblings 名义 FC） | `Targets/Soroban/{LowerSemantic,ValidatePlan,EmitIR}V1` · `SorobanPlanV1` pins | exact QN lowered; other `pf.crypto.*` still named FC | Bytes ABI; stellar-cli |
| **CAP-5** | P2 | **done 2026-08-16**: TON exact `pf.crypto.sha256` → Tolk `slice.bitsHash()`（TVM `SHA256U`）over Semantic UInt256 LE image；`string_hash`/`HASHCU`/`HASHBU` 负针 pin；keccak/siblings 名义 FC；freeze 其余不变 | `Targets/Ton/{LowerSemantic,ValidatePlan,PlanSchema,EmitIR}V1` · `TonPlanV1` pins | stdlib sha256 (document which); `string_hash` still not used | keccak; pf.assets; unfreeze whole TON |
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

## Suggested serial order（CAP-D-* 已于 2026-08-16 全开）

```text
CAP-0 (docs, done)
  → CAP-1a (ICP time, done 2026-08-15)
  → CAP-6 needles (done 2026-08-15)
  → CAP-D-* decided yes (2026-08-16)
      → CAP-2 → CAP-1b → CAP-3 → CAP-4 → CAP-5
        (disjoint allowlists, parallel worktree OK; shared Targets.lean/docs serial)
  → stop
```

One local commit per ID. Touch `ProofForgeV2/**` → `just sbom-package-files-refresh`.
Docs → `just docs-check`. Do not push unless asked.
