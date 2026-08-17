---
id: PLAN-XRPL-BEDROCK-WASM-TASKS
title: XRPL Bedrock WASM — task breakdown
status: draft
owner: engineering
updated: 2026-08-17
normative: false
---

# XRPL Bedrock WASM：任务拆分

> Engineering / research tasks. **Not** formal `TASK-*`.
> Design: [`xrpl-bedrock-wasm-gap.md`](xrpl-bedrock-wasm-gap.md).
> Verify docs with `just docs-check`. Do **not**
> `lake build proof_forge_next_tests_shard_*`.

Wave 2 (option A, source-only Q0) shipped as ADR-0049.
Wave 3 XRPL-9 (option B, opt-in WASM) shipped as ADR-0050.
XRPL-10+ still needs a second yes.

## Wave 0 — inventory (this change)

| ID | Status | Objective | Verify |
|---|---|---|---|
| **XRPL-0** | **this PR** | Dossier + gap + tasks + live pointers. No registry. | `just docs-check` |

## Wave 1 — freeze identity (docs / ADR draft)

| ID | Objective | Allowlist | Done when | Not |
|---|---|---|---|---|
| **XRPL-1** | Implementation ADR draft (identity, 4-key, family ban, AlphaNet≠mainnet, Hooks/EVM out) | `docs/adr/0049-xrpl-bedrock-source-u64-target.md` proposed | **done** (ADR-0049 `proposed`) | accepted PRD |
| **XRPL-2** | Pin Bedrock / XLS-0101 / AlphaNet facts as `SRC-*`/`CLM-*` if entering claim register | `docs/research/source-register.json` only if required | claims point at primary URLs | inventing Tool Lock versions |
| **XRPL-3** | Decide option A vs B (source-only vs locked rustc WASM extra) | product note | **done** (A; B/C later) | doing both silently |

## Wave 2 — source-only Q0 (only after XRPL-1)

Same skeleton as Soroban S0 / OpenVM O0:

| ID | Objective | Expected files | Done when |
|---|---|---|---|
| **XRPL-4** | `TargetId.xrpl` + sole profile `xrpl-bedrock-source-u64-v1` + 4-key resolver row | `TargetIdentity` / `TargetRegistry` / `RequirementResolver` / descriptor | **done** (13th engineering materializer; accepted PRD still 4) |
| **XRPL-5** | target-owned Plan/IR → one `{name}.rs` Bedrock-shaped guest | `Targets/Xrpl/**` | **done** (StateCell UInt64; unknown profile `PF-PROFILE-UNKNOWN`) |
| **XRPL-6** | Finalize zero-tool: `extraFiles=[]`, `deployable=false`, evidence names no bedrock/rustc/AlphaNet | `FinalizeV1` + `XrplPlanV1` | **done** (honesty pin) |
| **XRPL-7** | Named FC: ContextRead, `pf.crypto.*`, call/schedule, escrow/vault, Hooks, EVM | same suite | **done** (diagnostics cite QN / shape) |
| **XRPL-8** | docs: TARGET-INDEX row, matrix §1e, ADR-0036 count, SBOM | docs + surgical SBOM rehash | **done**（§1e 钉 4-key / Q0 语言 FC / Q1 extra / 非 AlphaNet·T9·CAP） |

## Wave 3 — opt-in only (product yes)

| ID | Objective | Gate |
|---|---|---|
| **XRPL-9** | **done** (ADR-0050)：opt-in `xrpl-bedrock-wasm-u64-v1`；ambient rustc → `.wasm` extra；`deployable` still false | XRPL-3 = B |
| **XRPL-10** | host-optional AlphaNet `ContractCreate` companion | never ordinary `just ci`; never mainnet |
| **XRPL-11** | Smart Escrow / Vault as **separate** profiles or TargetIds | not folded into XRPL-4 |

## Explicitly out

| ID | Why |
|---|---|
| **XRPL-X-HOOKS** | Different tx (`SetHook`); XRPL Labs, not Bedrock deploy |
| **XRPL-X-EVM-SIDECHAIN** | Already covered by `evm` + a bridge; not this TargetId |
| **XRPL-X-MAINNET** | `ContractCreate` not on XRPL mainnet |
| **XRPL-X-GENERIC-WASM** | No shared Plan with NEAR/CW/ICP/OpenVM |
| **XRPL-X-FORMAL** | Does not move D1–D4 0/27 |
| **XRPL-X-CAP-LAYER** | CAP-1a… stays on the existing 12 |

## Serial order

```text
XRPL-0 (now)
  → XRPL-1 ADR draft  (stop for review)
  → XRPL-3 A/B
  → XRPL-4…8 source-only Q0   if A
  → XRPL-9 / XRPL-10          only if separately approved
```

Wave 2 (XRPL-4…8) is the current XRPL coding slice. CAP-1a remains
available on the prior 12 leaves and is not closed by this wave.
