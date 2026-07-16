---
id: PHASE-1
title: 产品需求文档
status: proposed
owner: product
updated: 2026-07-16
normative: true
---

# Phase 1：PRD

## 产品愿景

让作者以一个 Lean `program` 描述业务语义，由命令行 target 选择平台物化；编译器
证明自己理解了程序需要什么，并在无法等价实现时准确拒绝。

| ID | 产品目标 |
|---|---|
| GOAL-001 | 一份 target-neutral Lean `program` 在保持业务语义的前提下按显式 target 物化，并对不等价能力 fail closed |

## 核心用户流程

1. 作者导入 `ProofForgeV2` 并声明一个或多个 `program Name where`。
2. `check` 在不选择 target 时完成 source/type/effect/termination/disclosure 检查。
3. `build --target <id>` 推导 requirements、精确求解 target support 并生成 OutputSet。
4. 用户读取 manifest、诊断、ABI/IDL/proof metadata，再由显式命令部署或验证。
5. 同一源码切换 target；语义保持不变，不支持项在 Plan 生成前失败。

## Functional Requirements

| ID | 需求 | 验收摘要 |
|---|---|---|
| FR-001 | 唯一顶层源码形式为 `program Name where` | parser 正负例；无顶层类别字段 |
| FR-002 | DSL 支持 state、struct、enum、const、event、error、init、entry、view、pure fn、invariant、requires 与受约束 proof reference | 每类有 D1 parser/Source AST 正负例；D2 另有完整 typed fixture，含 fn call 与 proof signature |
| FR-003 | 独立 type/effect/termination/disclosure 检查 | 稳定 `PF-SRC/TYPE/EFFECT/BOUND/VIS-*` |
| FR-004 | 生成目标中立 `SemanticProgram` 和可定位 requirements | 规范序列化及确定性测试 |
| FR-005 | `--target` 只选择物化，不改写业务语义 | import/branch 边界 gate + Counter 与非 Counter 跨 target 参考 trace 对比 |
| FR-006 | capability/extension 以 exact version + semantics digest 求解 | 缺失/不匹配必须 fail closed |
| FR-007 | 每个 target 拥有类型化 Plan 和 TargetIR | 编译期接口及 plan invariant 测试 |
| FR-008 | Phase 1 支持 `evm`、`solana`、`near`、`noir` | Counter 四目标 artifacts + runtime/proof evidence |
| FR-009 | 输出 manifest 记录 source/semantic/plan/artifact/toolchain hashes | schema 和 repeatability gate |
| FR-010 | 多 program 文件要求用 `--program` 消除歧义 | 唯一、缺失、歧义测试 |
| FR-011 | `check/build/inspect/list-targets` 提供 machine-readable JSON | schema snapshot 与错误退出码 |
| FR-012 | 私密 witness、授权和状态 custody 独立建模 | 不等价组合拒绝测试 |
| FR-013 | target extension 保持同一 DSL 但缩小可编译目标集合 | extension exact-match matrix |
| FR-014 | 部署和 proof verification 是显式动作 | build 不接触网络/私钥 |

## Non-Functional Requirements

| ID | 要求 | 指标 |
|---|---|---|
| NFR-001 | 决定性 | 相同输入/锁文件连续构建 semantic/plan/artifact hash 相同 |
| NFR-002 | 可诊断性 | 所有失败必含 schemaVersion/code/severity/phase/message；target、origin、requirement、expected/actual/suggestion 按 diagnostic condition matrix 条件必填 |
| NFR-003 | 安全默认 | 无 fallback、无动态插件、无 build-time network、无隐式部署 |
| NFR-004 | 独立性 | clean-room 副本清空父路径与 cache 后完整 build/test |
| NFR-005 | 可追踪性 | 所有 normative FR/NFR 均关联 SPEC、TASK、TST 和 EV |
| NFR-006 | 兼容性 | schema/DSL semantic versioning；破坏变化有 migration 和 major bump |
| NFR-007 | 性能 | `PerformanceProfileV1` 上 1000-node `check` 的 30 次测量 p95：新进程 cold full check ≤5s、same-session single-token warm full recheck ≤1s；不宣称 incremental compilation |
| NFR-008 | 资源可控 | check/build 显式接受 versioned time/memory/output limits；默认值、允许范围和超限 code 固定，parser 在限制生效后才读取不可信 source |
| NFR-009 | 供应链 | 所有直接/传递依赖和外部工具 exact pin + checksum + SPDX license；release 生成并校验 CycloneDX 1.6 SBOM |
| NFR-010 | 可维护性 | target backend 不反向依赖其他 target；boundary gate 强制 |

## 范围与非目标

第一阶段范围：语言核心、语义解释器、四个 materializer、Counter 和 PrivateSum4、
制品/诊断/可复现/clean-room gate。设计但不实现的目标为 CosmWasm、Soroban、ICP、
OpenVM、Aleo、Psy。

`Accumulator` 是强制的内部 backend genericity/非模板化验收向量，不是新增公开 DSL 或 target；
它与 Counter 共用产品范围内的 UInt64/state/entry/view 能力并进入四目标静态与适用 runtime/proof
差分。`fn` 与受约束 `proof` reference 属于 Phase 1 语言范围；任意 Lean term escape 仍为 OOS-004。

| ID | 非目标 |
|---|---|
| OOS-001 | 声称支持各目标全部 SDK 或协议标准 |
| OOS-002 | 在 Lean 中重写完整 EVM/SVM/Wasm/zkVM |
| OOS-003 | 自动部署、保管私钥或默认访问 RPC |
| OOS-004 | 允许任意 Lean term 进入 DSL 并绕过语义检查 |
| OOS-005 | 为不同目标提供互不兼容的顶层 DSL |
| OOS-006 | 以二进制相等代替跨目标可观察语义等价 |
| OOS-007 | 第一阶段生产就绪或审计完成声明 |

## TargetMaturity

唯一机器状态序为 `research → specified → prototype → artifact_validated → local_runtime →
network_or_proof_validated`：`research` 只有资料；`specified` 有 decision-complete dossier；
`prototype` 有目标制品但尚未通过官方结构校验；`artifact_validated` 通过官方或锁定的兼容
validator；`local_runtime` 有本地执行；`network_or_proof_validated` 有真实网络或完整
prove/verify。文档、`alpha`、`plan-only`、`source-only` 等说明不得成为平行状态或提升
`TargetMaturity`。该状态与单项 capability 的 `SupportEvidenceGrade`、证据账本的 evidence grade
相互独立。

## Phase 1 Definition of Done

- 一份 Counter 源码构建四目标，checked overflow 均失败且状态不变。
- EVM、Solana、NEAR 有本地 runtime trace；Noir 有 witness/prove/verify。
- PrivateSum4 的 raw private fields/values 不得成为 manifest、public ABI、诊断、日志、public
  inputs、cache key 或任何被拒绝目标的 staging/partial artifact 字段。proof 可以由 witness 派生，
  但只能由锁定且获批准的 ZK backend/profile 生成，不得携带 raw witness record；同一 circuit/plan
  的 VK 必须与 witness 无关。compiler-created witness staging 使用 `0700/0600` 并在成功/失败后
  删除；caller-owned `--inputs` 只做 no-follow stable read，绝不修改或删除。
- Diagnostic registry 登记的每个 rejection condition 至少有一个 required negative TST，并返回
  该 condition 的稳定 code 与条件必填字段。
- OutputSet 可重现，manifest schema 通过，clean-room gate 通过。
- 权威分母全部闭合：每个 active normative FR/NFR 有精确 SPEC/TASK/required TST；Test ID Catalog
  中除 `TST-A0-*` 外的每个 ID 都有最新 passed EV；每个已注册 rejection condition 被 required
  negative TST 覆盖。Phase 7 review 无 P0/P1；不含生产安全或全功能承诺。

## 成功指标

工程指标：四目标 acceptance 全绿、零 silent fallback；覆盖率只按上述三个机器可枚举集合计算，
不得用自由文本“100%”替代分母。产品指标沿用 Phase 0，未完成前不得宣称产品市场验证成功。
