---
id: PHASE-4
title: 实施任务拆解
status: proposed
owner: engineering
updated: 2026-07-16
normative: true
---

# Phase 4：实施任务拆解

每项预计不超过四小时；先完成对应 `TST-*` 骨架，再实现。状态仅用 `pending`、
`in_progress`、`blocked`、`done`，同一时刻只能有一项 `in_progress`。
表中依赖是任务完成依赖；前置任务未完成时可以收集明确标注的 pre-acceptance evidence，
但不能据此把正式任务标为 `done`。

## Pre-acceptance alpha checkpoint

以下任务验证设计可行性，不等同于关闭后续完整任务；证据和限制见实现日志。

| ID | 输出 | Evidence | 状态 |
|---|---|---|---|
| TASK-A0-01 | 文档控制面与 docs-check | EV-20260715-0001 | done |
| TASK-A0-02 | 独立 Lake、统一 DSL/Core/需求推导最小切片 | EV-20260715-0002 | done |
| TASK-A0-03 | 四目标 alpha artifacts 与 EVM runtime | EV-20260715-0003/0004 | done |
| TASK-A0-04 | archive isolation smoke（非完整 clean-room） | EV-20260715-0005 | done |
| TASK-A0-05 | Lean parser 前端与独立 Typed/Semantic IR 集成 | EV-20260715-0006/0007 | done |
| TASK-A0-06 | network-denied clean-room alpha（非正式 hermetic） | EV-20260715-0008 | done |
| TASK-A0-07 | content-addressed external tool/Mach-O closure slice | EV-20260715-0009 | done |
| TASK-A0-08 | Host Stage-0 development attestation 与 formal-ineligible negative | EV-20260715-0011/0012 | done |
| TASK-A0-09 | strict development evidence schema/bundle/publication core | EV-20260715-0014 | done |
| TASK-A0-10 | deny-default materialize/core/exact-local-port runtime continuation | EV-20260715-0015 | done |
| TASK-A0-11 | evidence v1 exact-local-port 条件端口、current-reader legacy-v1 compatibility 与攻击 self-tests | EV-20260715-0016 | done |
| TASK-A0-12 | H1e-a opt-in run/invocation contexts、canonical metadata receipt 与 single-writer receipt-last publication | EV-20260716-0017 | done |
| TASK-A0-13 | 通用 UInt64 EvmPlan/Yul/ABI、动态 Keccak selector 与 Accumulator Anvil runtime | EV-20260716-0018 | done |
| TASK-A0-14 | 通用 UInt64 SolanaPlan/typed audit IR/plan text/IDL 与 Accumulator artifact | EV-20260716-0019 | done |
| TASK-A0-15 | 通用 UInt64 NearPlan/Wasm recipe/WAT 与 Accumulator artifact | EV-20260716-0020 | done |
| TASK-A0-16 | 通用 UInt64 NoirPlan/typed relation IR/source 与 Accumulator external-state relation artifact | EV-20260716-0021 | done |
| TASK-A0-17 | 递归 decode/type-check 前的共享 Syntax node/nesting preflight 与稳定 boundary diagnostics | EV-20260716-0022 | done |
| TASK-A0-18 | accepted-width `Source.Program` 的线性 duplicate/name index 与 typecheck complexity regression | EV-20260716-0023 | done |
| TASK-A0-19 | reusable Loader `ParserSession` 与 hosted `source-core` 重资源向量进程隔离 | TST-SRC-002 / `just ci` / GitHub `source-core` | in_progress |

## Milestone D0：文档与独立工程

| ID | 任务/输出 | 依赖 | 先行测试/验证 | 状态 |
|---|---|---|---|---|
| TASK-D0-01 | 建立文档 status、ID、link checker | accepted Phase 1–3 | TST-DOC-001 | pending |
| TASK-D0-02 | 建立独立 Lake package/namespace/exe | D0-01 | TST-ISO-001 | pending |
| TASK-D0-03 | 锁定 Lean/external closure、Host Profile/Stage-0、candidate/evidence core、deny-default continuation 与 exact-port schema；H1e 按 receipt→catalog core→retained bundle 实施，formal handoff/finalizer 待完成 | 完成依赖 D0-01/02；当前 alpha 输入 A0-02 | TST-TOOL-001/TST-HOST-001/TST-EVIDENCE-001/TST-ISO-002 | pending |
| TASK-D0-04 | 实现正式 hermetic archive clean-room harness；blocker：eligible host、formal handoff/process-session containment 与 gate-catalog finalizer 未闭合 | D0-02/03 | TST-ISO-002 | blocked |

## Milestone D1：语言前端

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D1-01 | source token、span、NodeId | D0 | TST-SRC-001/002 | pending |
| TASK-D1-02 | `program ... where` command parser | D1-01 | TST-SRC-003 | pending |
| TASK-D1-03 | declaration grammar/elaboration | D1-02 | TST-SRC-004 | pending |
| TASK-D1-04 | statement/expression grammar | D1-03 | TST-SRC-005 | pending |
| TASK-D1-05 | `Source.Program` stable attribute export/schema | D1-03 | TST-SRC-006/007 | pending |
| TASK-D1-06 | multi-program loader/selection | D1-05 | TST-SRC-008 | pending |
| TASK-D1-07 | stable source diagnostics | D1-02–06 | TST-DIAG-001 | pending |

## Milestone D2：检查与语义

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D2-01 | name/type checker | D1 | TST-TYPE-001/002 | pending |
| TASK-D2-02 | effect/call/view checker | D2-01 | TST-EFFECT-001 | pending |
| TASK-D2-03 | bound/termination checker | D2-01 | TST-BOUND-001 | pending |
| TASK-D2-04 | disclosure/authority/custody checker | D2-01 | TST-VIS-001/002 | pending |
| TASK-D2-05 | SemanticProgram canonical serializer | D2-01–04 | TST-SEM-001 | pending |
| TASK-D2-06 | reference step interpreter | D2-05 | TST-SEM-002/003 | pending |
| TASK-D2-07 | requirement inference + origin | D2-05 | TST-REQ-001/002 | pending |

## Milestone D3：目标解析与制品框架

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D3-01 | Target/Profile ID parsers | D2 | TST-REG-001 | pending |
| TASK-D3-02 | static registry duplicate/exact lookup | D3-01 | TST-REG-002 | pending |
| TASK-D3-03 | support resolver + aggregate rejection | D3-02/D2-07 | TST-REQ-003 | pending |
| TASK-D3-04 | materializer associated-type protocol | D3-03 | TST-MAT-001 | pending |
| TASK-D3-05 | OutputSet staging/manifest/schema | D3-04 | TST-OUT-001/002 | pending |
| TASK-D3-06 | CLI check/build/inspect/list-targets | D3-05 | TST-CLI-001–004 | pending |

## Milestone D4：EVM

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D4-01 | EvmPlan schema/invariants | D3 | TST-EVM-001 | pending |
| TASK-D4-02 | SemanticProgram → EvmPlan | D4-01 | TST-EVM-002 | pending |
| TASK-D4-03 | EvmPlan → Yul + ABI | D4-02 | TST-EVM-003 | pending |
| TASK-D4-04 | solc bytecode packaging | D4-03 | TST-EVM-004 | pending |
| TASK-D4-05 | Anvil Counter differential | D4-04 | TST-EVM-005 | pending |

## Milestone D5：Solana

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D5-01 | SolanaPlan account/layout schema | D3 | TST-SOL-001 | pending |
| TASK-D5-02 | semantic → SolanaPlan | D5-01 | TST-SOL-002 | pending |
| TASK-D5-03 | Plan → sBPF AST/text + IDL | D5-02 | TST-SOL-003 | pending |
| TASK-D5-04 | ELF packaging/validation | D5-03 | TST-SOL-004 | pending |
| TASK-D5-05 | local runtime Counter differential | D5-04 | TST-SOL-005 | pending |

## Milestone D6：NEAR

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D6-01 | NearPlan KV/ABI/import schema | D3 | TST-NEAR-001 | pending |
| TASK-D6-02 | semantic → NearPlan | D6-01 | TST-NEAR-002 | pending |
| TASK-D6-03 | Plan → WasmModuleRecipe | D6-02 | TST-NEAR-003 | pending |
| TASK-D6-04 | deterministic Wasm emit/validate | D6-03 | TST-NEAR-004 | pending |
| TASK-D6-05 | sandbox Counter differential | D6-04 | TST-NEAR-005 | pending |

## Milestone D7：Noir

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D7-01 | NoirPlan disclosure/state relation schema | D3 | TST-NOIR-001 | pending |
| TASK-D7-02 | semantic → NoirPlan | D7-01 | TST-NOIR-002 | pending |
| TASK-D7-03 | Plan → `.nr`/ABI | D7-02 | TST-NOIR-003 | pending |
| TASK-D7-04 | ACIR/witness/prove/verify pipeline | D7-03 | TST-NOIR-004 | pending |
| TASK-D7-05 | Counter + PrivateSum4 proof tests | D7-04 | TST-NOIR-005/006 | pending |

## Milestone D8：集成与评审

| ID | 任务/输出 | 依赖 | 先行测试 | 状态 |
|---|---|---|---|---|
| TASK-D8-01 | Counter four-target aggregate | D4–D7 | TST-XTARGET-001 | pending |
| TASK-D8-02 | unsupported/version/tool failure matrix | D3–D7 | TST-XTARGET-002 | pending |
| TASK-D8-03 | reproducibility/concurrency/path attacks | D3–D7 | TST-SEC-001 | pending |
| TASK-D8-04 | clean-room full gate | D8-01–03 | TST-ISO-003 | pending |
| TASK-D8-05 | review report + release/rollback drill | D8-04 | TST-REL-001 | pending |

任务完成记录必须包含 commit、精确命令、结果、制品/evidence 路径及已知限制。
