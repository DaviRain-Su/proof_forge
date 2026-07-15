---
id: PHASE-5
title: 测试与验收规格
status: proposed
owner: quality
updated: 2026-07-15
normative: true
---

# Phase 5：测试与验收规格

## 原则

测试骨架先于实现。source/type/semantic 层以 reference interpreter 为 oracle；target
验收比较声明的 observable dimensions，而不是二进制相等。每个公共接口至少包含
happy、boundary、error/attack 三类测试。

## 测试层级

1. Parser/elaborator unit：语法、span、hygiene、跨模块导出。
2. Type/effect/property：类型、终止、披露、requirements 决定性。
3. Semantic model：reference step、rollback、effect ordering。
4. Resolver/Plan：capability exact match、Plan invariants、honest rejection。
5. Artifact：schema、hash、official validator、可重现性。
6. Runtime/proof：EVM/Solana/NEAR trace 与 Noir prove/verify。
7. Security/clean-room：路径、环境、cache、工具输出和资源边界。

## 核心向量

### Counter

初始 `count=0`；`increment(1)` 返回 1；`increment(2)` 返回 3；`get()` 返回 3；
从 `UInt64.max` 执行 `increment(1)` 必须失败、返回稳定 overflow 错误且状态仍为 max。
四目标观测统一为 normalized `(status, return, logicalState, effects, error)`。

### PrivateSum4

四个 private `Field` 输入求和，public expected sum；Noir prove/verify 成功，错误 sum 验证
失败。private 值不得出现在 manifest、public ABI、日志、诊断或 verifier-visible witness。
EVM/Solana/NEAR 因不能保持 private witness 语义，在 Plan 前以 `PF-REQ-UNSUPPORTED`
拒绝。

## Acceptance Matrix

| ID | 场景 | 预期 | 证据级别 |
|---|---|---|---|
| TST-SRC-003 | `program Counter where` 与非法顶层形式 | 正例导出；非法稳定诊断 | unit |
| TST-SRC-006 | attribute export 跨模块/import 顺序 | identity 稳定，无重复 | integration |
| TST-TYPE-001 | widths、map、struct、enum | 类型成功/精确失败 | property |
| TST-EFFECT-001 | view 写状态/发 effect | `PF-EFFECT-001` | negative |
| TST-BOUND-001 | 无界循环/递归 | `PF-BOUND-001` | negative |
| TST-VIS-001 | private 流入 public/log | `PF-VIS-001` | security |
| TST-SEM-002 | Counter reference trace | 精确 normalized trace | model |
| TST-SEM-003 | overflow/revert | unchangedState | model |
| TST-REQ-001 | requirement inference | 稳定集合、origin/span | property |
| TST-REQ-003 | support exact version/digest | mismatch fail closed | negative |
| TST-REG-002 | duplicate/unknown target | stable registry errors | unit |
| TST-MAT-001 | associated Plan/IR | 不可擦除、invariants enforced | compile/unit |
| TST-OUT-001 | manifest/hash/partial failure | 原子输出或无变化 | integration |
| TST-EVM-005 | Counter on Anvil | reference trace 相同 | local_runtime |
| TST-SOL-005 | Counter on Solana local runtime | reference trace 相同 | local_runtime |
| TST-NEAR-005 | Counter on sandbox | reference trace 相同 | local_runtime |
| TST-NOIR-005 | Counter witness/proof | prove+verify，state continuity explicit | proof |
| TST-NOIR-006 | PrivateSum4 | 隐私检查 + prove/verify | proof/security |
| TST-XTARGET-001 | 一份 Counter 四 target | 四 OutputSet 均合法 | aggregate |
| TST-XTARGET-002 | unsupported/version/missing tool | 稳定错误，无 fallback | aggregate |
| TST-ISO-003 | archive clean-room | 清理环境后完整通过 | isolation |

## 完整 Test ID Catalog

以下 ID 均为 specified；表中“测试对象”是必须实现的最小断言，不表示已有 gate。

| IDs | 测试对象 |
|---|---|
| TST-DOC-001 | frontmatter、状态、ID、链接、claim/ADR/trace 闭合 |
| TST-ISO-001/002/003 | 独立 Lake 工程、父依赖扫描、完整 archive clean-room |
| TST-TOOL-001 | exact tool version/checksum、missing/shadow/timeout |
| TST-SRC-001/002 | token/span/NodeId canonicalization 与 limits |
| TST-SRC-003/004/005 | program command、declarations、statements/expressions 正负例 |
| TST-SRC-006/007/008 | attribute export、import/identity、multi-program selection |
| TST-DIAG-001 | diagnostic code/schema/order/redaction |
| TST-TYPE-001/002 | 类型 happy/boundary/error 与 name resolution |
| TST-EFFECT-001, TST-BOUND-001 | effect restrictions 与 termination/resource bounds |
| TST-VIS-001/002 | explicit/implicit disclosure flow 与 authority/custody separation |
| TST-SEM-001/002/003 | serialization、reference trace、revert/overflow rollback |
| TST-REQ-001/002/003 | inference/origin、merge/conflict、support exact match/rejection |
| TST-REG-001/002 | ID/profile parsing、registry duplicate/lookup/design-only rejection |
| TST-MAT-001 | associated Plan/IR、stage order、invariant mutation tests |
| TST-OUT-001/002 | manifest/atomicity 与 repeatability/tamper |
| TST-CLI-001/002/003/004 | parse/help、check/build、inspect/list、prove/verify/deploy guard |
| TST-EVM-001..005 | Plan、materialize、Yul/ABI、bytecode validation、runtime differential |
| TST-SOL-001..005 | Plan、materialize、sBPF/IDL、ELF validation、runtime differential |
| TST-NEAR-001..005 | Plan、materialize、Wasm recipe、Wasm validation、sandbox differential |
| TST-NOIR-001..006 | Plan、materialize、source/ABI、ACIR/prove/verify、Counter、PrivateSum4 |
| TST-XTARGET-001/002 | 四目标 aggregate 与 unsupported/version/tool matrix |
| TST-SEC-001 | path/env/process/supply-chain/privacy attack matrix |
| TST-VER-001 | schema/profile compatibility matrix |
| TST-PERF-001 | cold/incremental/resource benchmark budgets |
| TST-BOUNDARY-001 | Lean import graph、symbol ownership、target cross-import |
| TST-EVIDENCE-001 | EV schema/hash/revoke/freshness/private scan |
| TST-REL-001 | install/upgrade/build/rollback drill |

## 边界与攻击用例

- 空/多程序、重复名字、Unicode normalization、非法 UTF-8、最大 nesting/node count。
- UInt min/max、checked overflow/underflow、除零、shift ≥ width、Field modulus mismatch。
- 空/最大 bytes/string、Map 缺失键、重复 event/error/entry、init 缺失/重复。
- 循环上界 0/1/max、间接递归、动态 allocation、调用深度和 effect 数超限。
- private control-flow/索引/错误消息泄漏；authority 与 custody 混淆。
- unknown target/profile/network、重复 registry key、extension digest/version mismatch。
- output path `..`、absolute path、symlink、case collision、并发同目录、磁盘写满。
- 外部工具缺失、版本错误、timeout、signal、巨大 stdout、恶意 artifact path。
- `LEAN_PATH`、`PATH`、Lake cache、HOME 和父 Git root 泄漏。

## Gate 设计

预期命令名：`v2-source-core`、`v2-counter-four-target`、
`v2-target-extension-rejection`、`v2-artifact-repeatability`、`v2-missing-tool`、
`v2-runtime-primary-triad`、`v2-zk-noir-e2e`、`v2-clean-room`、`v2-check`。
命令未实现前它们是 specified，不得记录为通过。

## 证据要求

每次 gate 写 `EV-*` JSON：commit、dirty state、平台、工具版本、命令、开始/结束、
exit status、artifact hashes、normalized observations 和日志路径。外部工具缺失必须让
相应 required gate 失败，不能 skip 后仍标绿。flaky 重试必须记录全部尝试。

## Release Acceptance

Phase 1 release 要求本表所有 required TST 有最新 EV；四目标 aggregate、security、
repeatability、clean-room 全绿；无 P0/P1 review finding；所有文档 trace 关闭。
