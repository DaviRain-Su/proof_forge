---
id: PHASE-4
title: 实施任务拆解
status: proposed
owner: engineering
updated: 2026-07-17
normative: true
---

# Phase 4：实施任务拆解

每项预计不超过四小时；先完成对应 `TST-*` 骨架，再实现。状态仅用 `pending`、
`in_progress`、`blocked`、`done`，同一时刻只能有一项 `in_progress`。
表中依赖是任务完成依赖；前置任务未完成时可以收集明确标注的 pre-acceptance evidence，
但不能据此把正式任务标为 `done`。

> **2026-07-17：** `TASK-D0-01` 经 `FX-2026-07-17-D0-01` 关闭为 `done`（pure consumer +
> docs-check；protected production positive 移交 D0-04）。`TASK-D0-02` 的实现与 development
> gate 已在 `2d9bb628` 通过，但缺受保护的 bootstrap TaskApproval/receipt，按 R5 保持 `blocked`。

## 全局任务冻结（所有 TASK，强制）

全部任务遵守 [`governance/task-freeze.md`](governance/task-freeze.md)
（`GOV-TASK-FREEZE-001`）：

1. **`pending` → `in_progress` 前**必须具备冻结完成包（output / tests / inScope /
   outOfScope / doneWhen）。  
2. **`in_progress` 与 `done` 禁止完成面变胖**（不得改 Output/Tests/Dependencies/
   Prerequisites 语义，不得在 AGENTS/checkpoint 追加“还必须…”）。  
3. **新缺口**只能：修实现、标 `blocked`、开新 task、或书面 Freeze Exception——禁止回填当前任务。  
4. **A0** 已冻结到 `TASK-A0-20`；**D0** 执行基线为 `TASK-D0-01`…`TASK-D0-07`；milestone
   增行须 Architecture + Quality 批准。  
5. 超时（默认 3 日或 20 个 task-owned commits）必须 24h 内 triage：Close / Split / Block /
   Exception。

任务选择以本文件为准，`AGENTS.md` 只镜像当前指针。新增 pre-acceptance task 必须先在本文件
说明为什么既有 Milestone 任务不能承载该工作；不得由 checkpoint 的 `Next task` 自动递增
`TASK-A0-*`。`Dependencies` 只列精确 `TASK-*` 完成依赖，禁止里程碑简称和范围简写；
非任务条件单独进入 `Prerequisites`。

## Pre-acceptance alpha checkpoint

以下任务验证设计可行性，不等同于关闭后续完整任务；`TST-A0-*` 只标识对应 alpha
验收切片，不冒充 formal milestone 的 `TST-*`；证据和限制见实现日志。A0 已冻结且不再参与
调度，历史执行先后不伪装成技术完成依赖，因此其 `Dependencies` 统一记为 `—`。

| ID | 输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-A0-01 | 文档控制面与 docs-check | — | — | TST-A0-001 | EV-20260715-0001 | done |
| TASK-A0-02 | 独立 Lake、统一 DSL/Core/需求推导最小切片 | — | — | TST-A0-002 | EV-20260715-0002 | done |
| TASK-A0-03 | 四目标 alpha artifacts 与 EVM runtime | — | — | TST-A0-003 | EV-20260715-0003, EV-20260715-0004 | done |
| TASK-A0-04 | archive isolation smoke（非完整 clean-room） | — | — | TST-A0-004 | EV-20260715-0005 | done |
| TASK-A0-05 | Lean parser 前端与独立 Typed/Semantic IR 集成 | — | — | TST-A0-005 | EV-20260715-0006, EV-20260715-0007 | done |
| TASK-A0-06 | network-denied clean-room alpha（非正式 hermetic） | — | — | TST-A0-006 | EV-20260715-0008 | done |
| TASK-A0-07 | content-addressed external tool/Mach-O closure slice | — | — | TST-A0-007 | EV-20260715-0009 | done |
| TASK-A0-08 | Host Stage-0 development attestation 与 formal-ineligible negative | — | — | TST-A0-008 | EV-20260715-0011, EV-20260715-0012 | done |
| TASK-A0-09 | strict development evidence schema/bundle/publication core | — | — | TST-A0-009 | EV-20260715-0014 | done |
| TASK-A0-10 | deny-default materialize/core/exact-local-port runtime continuation | — | — | TST-A0-010 | EV-20260715-0015 | done |
| TASK-A0-11 | evidence v1 exact-local-port 条件端口、current-reader legacy-v1 compatibility 与攻击 self-tests | — | — | TST-A0-011 | EV-20260715-0016 | done |
| TASK-A0-12 | H1e-a opt-in run/invocation contexts、canonical metadata receipt 与 single-writer receipt-last publication | — | — | TST-A0-012 | EV-20260716-0017 | done |
| TASK-A0-13 | 通用 UInt64 EvmPlan/Yul/ABI、动态 Keccak selector 与 Accumulator Anvil runtime | — | — | TST-A0-013 | EV-20260716-0018 | done |
| TASK-A0-14 | 通用 UInt64 SolanaPlan/typed audit IR/plan text/IDL 与 Accumulator artifact | — | — | TST-A0-014 | EV-20260716-0019 | done |
| TASK-A0-15 | 通用 UInt64 NearPlan/Wasm recipe/WAT 与 Accumulator artifact | — | — | TST-A0-015 | EV-20260716-0020 | done |
| TASK-A0-16 | 通用 UInt64 NoirPlan/typed relation IR/source 与 Accumulator external-state relation artifact | — | — | TST-A0-016 | EV-20260716-0021 | done |
| TASK-A0-17 | 递归 decode/type-check 前的共享 Syntax node/nesting preflight 与稳定 boundary diagnostics | — | — | TST-A0-017 | EV-20260716-0022 | done |
| TASK-A0-18 | accepted-width `Source.Program` 的线性 duplicate/name index 与 typecheck complexity regression | — | — | TST-A0-018 | EV-20260716-0023 | done |
| TASK-A0-19 | reusable Loader `ParserSession` 与 hosted `source-core` 重资源向量进程隔离 | — | — | TST-A0-019 | EV-20260716-0024 | done |
| TASK-A0-20 | Lean command/CLI Loader 共用唯一 validated decoded `Source.Program`，移除第二套 raw-Syntax AST construction | — | — | TST-A0-020 | EV-20260716-0025 | done |

本 checkpoint 截止 `TASK-A0-20` 冻结。2026-07-16 对账确认：A0 的 `done` 只表示 alpha
切片；它们不自动关闭 D0/D1。2026-07-17：`TASK-D0-01` 经 `FX-2026-07-17-D0-01` 关闭；
下一正式任务仍为 `TASK-D0-02`；其 implementation slice 已通过，等待合法 bootstrap closure。

## Milestone D0：文档与独立工程

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D0-01 | 建立文档 status/ID/link/trace/task→TST→EV/checkpoint checker 与 external TaskApproval/task-receipt pure consumer（FX-2026-07-17-D0-01：candidate-external protected production positive 移交 D0-04，缺失时 fail closed 不阻塞本任务 done） | — | PHASE-1@accepted, PHASE-2@accepted, PHASE-3@accepted | TST-DOC-001 | EV-20260717-0028 | done |
| TASK-D0-02 | 建立独立 Lake package/namespace/exe（FX-2026-07-17-D0-02：package-boundary 以 isolation development gates 关闭；signed TaskApproval/authenticated receipt 移交 D0-04） | TASK-D0-01 | — | TST-ISO-001 | EV-20260717-0030 | done |
| TASK-D0-03 | 锁定 Lean/external closure、Host Profile/Stage-0、candidate/evidence core、deny-default continuation 与 exact-port schema；只交付 development evidence schema/bundle/catalog finalizer 及 formal zero-output rejection，当前 alpha 输入为 `TASK-A0-02` | TASK-D0-01, TASK-D0-02 | — | TST-EVIDENCE-001, TST-HOST-001, TST-TOOL-001 | — | in_progress |
| TASK-D0-04 | 实现 bootstrap foundation：eligible Stage-0 handoff、跨 process-session containment、signed RequiredTestSet/formal-catalog authority、per-task verifier receipt/protected service，以及 six-item BootstrapApprovalSet/activation producer-consumer；owned TST 只在 pre-activation 运行，task done 另须随后取得 set+activation receipt，且二者不得回填 TST/TaskApproval/task receipt | TASK-D0-02, TASK-D0-03, TASK-D0-05, TASK-D0-06 | — | TST-BOOTSTRAP-001 | — | blocked |
| TASK-D0-05 | direct/transitive license inventory + CycloneDX 1.6 SBOM 生成、schema/closure/release binding | TASK-D0-03 | — | TST-SBOM-001 | — | pending |
| TASK-D0-06 | common scalar parsers、canonical encoders/domain hashes 与 ResourceProfileV1 types | TASK-D0-01, TASK-D0-02 | — | TST-COMMON-001 | — | pending |
| TASK-D0-07 | 在 current、non-revoked BootstrapApprovalSet activation 后执行正式 hermetic archive clean-room gate，并实现 formal evidence-set finalizer、freshness/private scan/revocation 与 acceptance/support-binding producer/store | TASK-D0-04 | — | TST-EVIDENCE-002, TST-ISO-002 | — | pending |

`TASK-D0-02` 的冻结 Output/Tests/Dependencies/Prerequisites 未变；阻塞项是候选外部 authority
才能产生的 exact signed TaskApproval 与 authenticated task receipt。`EV-20260717-0029` 只记录
package-boundary development GREEN，不满足 bootstrap grade，故不得把本行标为 `done`，也不得启动
依赖它完成的 `TASK-D0-03`。解除方式只能是取得规范对象，或经 Architecture + Quality 批准书面
Freeze Exception / 依赖修订；agent 不得自行选择后者。

## Milestone D1：语言前端

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D1-01 | source token、span、NodeId | TASK-D0-01, TASK-D0-02, TASK-D0-03, TASK-D0-04, TASK-D0-07 | — | TST-SRC-001, TST-SRC-002 | — | pending |
| TASK-D1-02 | `program ... where` command parser | TASK-D1-01 | — | TST-SRC-003 | — | pending |
| TASK-D1-03 | declaration grammar/elaboration | TASK-D1-02 | — | TST-SRC-004 | — | pending |
| TASK-D1-04 | statement/expression grammar | TASK-D1-03 | — | TST-SRC-005 | — | pending |
| TASK-D1-05 | `Source.Program` stable attribute export/schema | TASK-D1-03 | — | TST-SRC-006, TST-SRC-007 | — | pending |
| TASK-D1-06 | multi-program loader/selection | TASK-D1-05 | — | TST-SRC-008 | — | pending |
| TASK-D1-07 | stable source diagnostics | TASK-D1-02, TASK-D1-03, TASK-D1-04, TASK-D1-05, TASK-D1-06 | — | TST-DIAG-001 | — | pending |
| TASK-D1-08 | contained frontend worker、safe source open 与 ResourceProfileV1 supervisor | TASK-D0-04, TASK-D0-06, TASK-D0-07, TASK-D1-01, TASK-D1-02, TASK-D1-03, TASK-D1-04, TASK-D1-05, TASK-D1-06, TASK-D1-07 | — | TST-RESOURCE-001 | — | pending |

## Milestone D2：检查与语义

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D2-01 | name/type checker + pure-fn call graph + invariant/proof-reference source binding（不装载 proof environment） | TASK-D1-01, TASK-D1-02, TASK-D1-03, TASK-D1-04, TASK-D1-05, TASK-D1-06, TASK-D1-07, TASK-D1-08 | — | TST-TYPE-001, TST-TYPE-002, TST-TYPE-003 | — | pending |
| TASK-D2-02 | effect/call/view checker | TASK-D2-01 | — | TST-EFFECT-001 | — | pending |
| TASK-D2-03 | bound/termination checker | TASK-D2-01 | — | TST-BOUND-001 | — | pending |
| TASK-D2-04 | disclosure/authority/custody checker | TASK-D2-01 | — | TST-VIS-001, TST-VIS-002 | — | pending |
| TASK-D2-05 | canonical ProgramRequirements inference、predicate merge + origin | TASK-D2-01, TASK-D2-02, TASK-D2-03, TASK-D2-04 | — | TST-REQ-001, TST-REQ-002 | — | pending |
| TASK-D2-06 | closed SemanticProgram construction/canonical serializer + post-canonical proof-bundle/theorem signature validation | TASK-D2-05 | — | TST-SEM-001, TST-PROOF-001 | — | pending |
| TASK-D2-07 | reference step interpreter | TASK-D2-06 | — | TST-SEM-002, TST-SEM-003 | — | pending |

## Milestone D3：目标解析与制品框架

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D3-01 | Target/Profile ID parsers | TASK-D2-01, TASK-D2-02, TASK-D2-03, TASK-D2-04, TASK-D2-05, TASK-D2-06, TASK-D2-07 | — | TST-REG-001 | — | pending |
| TASK-D3-02 | static registry duplicate/exact lookup | TASK-D3-01 | — | TST-REG-002 | — | pending |
| TASK-D3-03 | ProgramRequirements requested predicates → exact static SupportClaim/claimDigest + selected BuildIdentity ProfileSupportIndex resolver；candidate/profile/ref/freshness/revocation exact fail closed 与 aggregate rejection | TASK-D3-02, TASK-D2-05 | — | TST-REQ-003 | — | pending |
| TASK-D3-04 | materializer associated-type protocol | TASK-D3-03 | — | TST-MAT-001, TST-BOUNDARY-001 | — | pending |
| TASK-D3-05 | OutputSet staging/manifest/schema + support-decisions exact schema/digest/binding | TASK-D3-04 | — | TST-OUT-001, TST-OUT-002 | — | pending |
| TASK-D3-06 | CLI check/build/inspect/list-targets + stage/field-specific lower-only resource override parser | TASK-D3-05 | — | TST-CLI-001, TST-CLI-002, TST-CLI-003, TST-CLI-004 | — | pending |
| TASK-D3-07 | contained compiler-core/tool/output supervisor、effective resource profile digest/receipt 与 whole-containment cleanup | TASK-D3-06 | — | TST-RESOURCE-002 | — | pending |

## Milestone D4：EVM

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D4-01 | EvmPlan schema/invariants | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-EVM-001 | — | pending |
| TASK-D4-02 | SemanticProgram → EvmPlan | TASK-D4-01 | — | TST-EVM-002 | — | pending |
| TASK-D4-03 | EvmPlan → Yul + ABI | TASK-D4-02 | — | TST-EVM-003 | — | pending |
| TASK-D4-04 | solc bytecode packaging | TASK-D4-03 | — | TST-EVM-004 | — | pending |
| TASK-D4-05 | Anvil Counter differential | TASK-D4-04 | — | TST-EVM-005 | — | pending |

## Milestone D5：Solana

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D5-01 | SolanaPlan account/layout schema | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-SOL-001 | — | pending |
| TASK-D5-02 | semantic → SolanaPlan | TASK-D5-01 | — | TST-SOL-002 | — | pending |
| TASK-D5-03 | Plan → sBPF AST/text + IDL | TASK-D5-02 | — | TST-SOL-003 | — | pending |
| TASK-D5-04 | 新建 `solana-sbpf-elf-v1` executable CodegenProfile，lock toolchain/ELF validation；formal gate 后以 registry 新版本切换 default，不得原地升级 plan profile | TASK-D5-03 | — | TST-SOL-004 | — | pending |
| TASK-D5-05 | local runtime Counter differential | TASK-D5-04 | — | TST-SOL-005 | — | pending |

## Milestone D6：NEAR

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D6-01 | NearPlan KV/ABI/import schema | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-NEAR-001 | — | pending |
| TASK-D6-02 | semantic → NearPlan | TASK-D6-01 | — | TST-NEAR-002 | — | pending |
| TASK-D6-03 | Plan → WasmModuleRecipe | TASK-D6-02 | — | TST-NEAR-003 | — | pending |
| TASK-D6-04 | deterministic Wasm emit/validate | TASK-D6-03 | — | TST-NEAR-004 | — | pending |
| TASK-D6-05 | sandbox Counter differential | TASK-D6-04 | — | TST-NEAR-005 | — | pending |

## Milestone D7：Noir

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D7-01 | NoirPlan disclosure/state relation schema | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07 | — | TST-NOIR-001 | — | pending |
| TASK-D7-02 | semantic → NoirPlan | TASK-D7-01 | — | TST-NOIR-002 | — | pending |
| TASK-D7-03 | Plan → `.nr`/ABI | TASK-D7-02 | — | TST-NOIR-003 | — | pending |
| TASK-D7-04 | 新建 `noir-acir-proof-v1` CodegenProfile，lock ACIR/witness/prove/verify toolchain，并发布 exact ZK security profile + candidate/build formal approval；formal gate 后以 registry 新版本切换 default，不得原地升级 source profile | TASK-D7-03 | — | TST-NOIR-004, TST-ZKSEC-001 | — | pending |
| TASK-D7-05 | Counter + PrivateSum4 proof tests | TASK-D7-04 | — | TST-NOIR-005, TST-NOIR-006 | — | pending |

## Milestone D8：集成与评审

| ID | 任务/输出 | Dependencies | Prerequisites | Tests | Evidence | 状态 |
|---|---|---|---|---|---|---|
| TASK-D8-01 | Counter + Accumulator four-target aggregate and target-neutral structural boundary | TASK-D4-01, TASK-D4-02, TASK-D4-03, TASK-D4-04, TASK-D4-05, TASK-D5-01, TASK-D5-02, TASK-D5-03, TASK-D5-04, TASK-D5-05, TASK-D6-01, TASK-D6-02, TASK-D6-03, TASK-D6-04, TASK-D6-05, TASK-D7-01, TASK-D7-02, TASK-D7-03, TASK-D7-04, TASK-D7-05 | — | TST-XTARGET-001, TST-XTARGET-003 | — | pending |
| TASK-D8-02 | unsupported/version/tool failure matrix | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D4-01, TASK-D4-02, TASK-D4-03, TASK-D4-04, TASK-D4-05, TASK-D5-01, TASK-D5-02, TASK-D5-03, TASK-D5-04, TASK-D5-05, TASK-D6-01, TASK-D6-02, TASK-D6-03, TASK-D6-04, TASK-D6-05, TASK-D7-01, TASK-D7-02, TASK-D7-03, TASK-D7-04, TASK-D7-05 | — | TST-XTARGET-002 | — | pending |
| TASK-D8-03 | reproducibility/concurrency/path/resource/performance attacks | TASK-D3-01, TASK-D3-02, TASK-D3-03, TASK-D3-04, TASK-D3-05, TASK-D3-06, TASK-D3-07, TASK-D4-01, TASK-D4-02, TASK-D4-03, TASK-D4-04, TASK-D4-05, TASK-D5-01, TASK-D5-02, TASK-D5-03, TASK-D5-04, TASK-D5-05, TASK-D6-01, TASK-D6-02, TASK-D6-03, TASK-D6-04, TASK-D6-05, TASK-D7-01, TASK-D7-02, TASK-D7-03, TASK-D7-04, TASK-D7-05 | — | TST-SEC-001, TST-PERF-001, TST-RESOURCE-001, TST-RESOURCE-002 | — | pending |
| TASK-D8-04 | clean-room full gate | TASK-D8-01, TASK-D8-02, TASK-D8-03 | — | TST-ISO-003 | — | pending |
| TASK-D8-05 | review report + release/rollback drill | TASK-D8-04 | — | TST-REL-001, TST-VER-001 | — | pending |

任务完成记录必须包含 commit、精确命令、结果、制品/evidence 路径及已知限制。
