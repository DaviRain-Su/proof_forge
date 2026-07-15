---
id: PHASE-7
title: 评审与发布报告
status: draft
owner: release
updated: 2026-07-16
normative: false
---

# Phase 7：评审与发布报告

本报告基于已执行命令与已记录 `EV-*` 填写，不是预填通过。正式 release channel
与 formal hermetic clean-room（`TST-ISO-002`/`TST-ISO-003`）在本 host 上仍未打开。

## 评审记录（2026-07-16，development candidate）

| 领域 | Reviewer | 输入 | 结论 | Finding IDs |
|---|---|---|---|---|
| Spec conformance | implementer | ADR-0013、SPEC-REPRO/TOOL、task table、diff | pass with limits | F-REL-001 |
| Semantic correctness | implementer | `proof-forge-next-tests`、Counter reference interpreter、EVM Anvil | pass (Phase-1 Counter surface) | |
| Security/privacy | implementer | output-security、toolchain negatives、deny-default isolation、privateWitness reject | pass with limits | F-SEC-001 |
| Dependencies/licenses | implementer | toolchains.lock.json、host-profiles.lock.json | pass (locked assets) | |
| Performance/resources | implementer | clean-room 61-job build timing only | deferred | F-PERF-001 |
| Reproducibility/isolation | implementer | reproducibility 19-file、H1 deny-default clean-room EV-20260715-0012 | pass development; formal hermetic blocked | F-ISO-001 |
| Target maturity honesty | implementer | target dossiers + smoke | pass (no ELF/proof/receipt overclaim) | |
| Release/rollback | implementer | no signed candidate channel | not_ready for public release | F-REL-002 |

Finding severity：P0 安全/语义破坏、P1 发布阻断、P2 可带明确跟踪发布、P3 文档/优化。

### Findings

| ID | Severity | Summary | Status |
|---|---|---|---|
| F-ISO-001 | P1 | Host `eligibleForHermetic=false`（APFS Sealed: Broken；Xcode pathname current-user-mutable）。`TASK-D0-04`/`TST-ISO-002`/`TST-ISO-003` blocked。H1 deny-default + schema EV 已落地，不得称为 formal hermetic。 | open (host) |
| F-REL-001 | P2 | 多数 specs/ADR 仍为 `proposed`，尚未 `accepted` 发布治理闭环。 | open |
| F-SEC-001 | P2 | deny-default 仍允许系统 `/private/var/folders` 读以便 Python/Lean 运行；用户 HOME/父 repo/`/opt/homebrew` 已 deny。同 UID TOCTOU 边界未闭合。 | open |
| F-PERF-001 | P3 | 无正式 cold/incremental benchmark budgets 证据。 | open |
| F-REL-002 | P1 | 无 signed release bundle / rollback drill；development candidate only。 | open |
| F-TGT-001 | P2 | Solana ELF/runtime、NEAR sandbox receipt、Noir prove/verify 工具未冻结；maturity 保持 non-deployable/static。 | open |

## 证据集

| EV ID | Gate | Result | Closes / scope |
|---|---|---|---|
| EV-20260715-0001 | docs-check | passed | TST-DOC-001 / NFR-005 |
| EV-20260715-0002 | unit tests | passed | alpha unit baseline |
| EV-20260715-0003/0006 | target-smoke / just check | passed | early four-target / product gate |
| EV-20260715-0004 | EVM Anvil runtime | passed | TST-EVM-005 baseline |
| EV-20260715-0009/0010 | toolchain + clean-room alpha | passed (development) | tool closure / isolation alpha |
| EV-20260715-0011 | Stage-0 development + formal rejection | passed / expected fail closed | TST-HOST-001；formal `PF-HOST-INELIGIBLE` |
| EV-20260715-0012 | H1 deny-default clean-room + schema EV | passed (`eligibleForHermetic=false`) | TASK-D0-03/H1；not TST-ISO-002 |
| EV-20260716-0013 | SourceIdentity (NodeId/span/tokenize/limits) | passed | TASK-D1-01 / TST-SRC-001/002 |
| EV-20260716-0014 | program parser + kind negative | passed | TASK-D1-02 / TST-SRC-003 / FR-001 |
| EV-20260716-0015 | Declarations (state/init/entry/stmt) | passed | TASK-D1-03/04 / TST-SRC-004/005 / FR-002 |
| EV-20260716-0016 | Export + PF-EXPORT-001/002 | passed | TASK-D1-05/06/07 / TST-SRC-006..008 / TST-DIAG-001 / FR-010 / NFR-002 |
| EV-20260716-0017 | Pipeline/Bound/Semantics/Targets | passed | TASK-D2-01..07 / TYPE/EFFECT/BOUND/VIS/SEM/REQ / FR-003/004/006/012/013 / NFR-008 |
| EV-20260716-0018 | target-smoke/negatives/Anvil/repro/output-security | passed | runnable D3–D8 / FR-005..009/011/014 / NFR-001/003/009/010 at proven maturity |

## 最终决策

- Candidate version/commit：formal D1 NodeId/export through D3–D8 maturity closeout (`2a21a962`+)
- Evidence set：EV-20260715-0001..0012 + EV-20260716-0013..0018；Merkle root 未做 release 级汇总
- Supported targets/profiles（Phase-1 engineering maturity）：
  - `evm`：solc bytecode + Anvil Counter（local_runtime）
  - `near`：Wasm structural validate（artifact_validated；无 sandbox receipt）
  - `solana`：`.s` + IDL（non-deployable）
  - `noir`：`.nr` + Prover input（non-deployable；无 proof）
- Unsupported claims：formal hermetic、Solana ELF/runtime、NEAR sandbox、Noir prove/verify、公网部署、signed release
- Rollback version/drill：未执行（无 release 通道）
- Decision：`not_ready`（runnable Phase-1 formal tasks closed with TST/EV；blocked host/tool rows remain；**不**批准 public release）
- Approvers/date：implementer self-review 2026-07-16；独立 multi-party release approval 未进行

## Rollback 笔记（若未来 release）

1. 保留上一 signed candidate tag 与 evidence set。
2. 回滚 CLI/package 分发到该 tag；撤销错误 maturity 声明。
3. 重新跑 `just check` 与 eligible-host formal clean-room 后再发布。
