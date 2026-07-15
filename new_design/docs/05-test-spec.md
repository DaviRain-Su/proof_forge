---
id: PHASE-5
title: 测试与验收规格
status: proposed
owner: quality
updated: 2026-07-16
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
| TST-HOST-001 | Stage-0 host attestation | development observation；formal fail closed | security/isolation |
| TST-ISO-002 | 正式 hermetic archive harness | 外部 candidate anchor、eligible host、deny-default stages、process containment、gate-catalog EV 全部通过 | isolation |
| TST-ISO-003 | release-candidate clean-room aggregate | 所有 required Phase 1 gates 完整通过 | release/isolation |

## 完整 Test ID Catalog

以下 ID 均为 specified；表中“测试对象”是必须实现的最小断言，不表示已有 gate。

| IDs | 测试对象 |
|---|---|
| TST-DOC-001 | frontmatter、状态、ID、链接、claim/ADR/trace 闭合 |
| TST-HOST-001 | 权威 `env -i` 入口、严格 bootstrap/JSON、live OS/Xcode/tool 匹配、development observation、formal ineligible 与环境/lock mutation negatives |
| TST-ISO-001 | 独立 Lake/package/namespace 与父依赖边界 |
| TST-ISO-002 | Stage-0 eligible host、外部 commit/tree/archive anchor、稳定 committed archive、前后 unchanged、空环境/cache；materialize/core deny-all-network；runtime exact-local-port + Anvil 127 bind/LAN refusal；stage read/write/exec negatives、closed FD/stdin EOF/output cap/timeout、formal session containment、0400 single-link receipts 与 gate-catalog-bound evidence |
| TST-ISO-003 | D8 release-candidate 全量 clean-room aggregate |
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
| TST-EVIDENCE-001 | restricted PF JCS/schema、exact-local-port 条件 port、artifact-set domain hash、safe bundle read、atomic layout、gate catalog、revocation/freshness/private scan |
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
- tree-object archive 的不稳定 mtime、错误 external commit/archive digest、archive 内嵌 commit
  不匹配、运行中 HEAD/tree/worktree 改变。
- EV duplicate/unknown/non-graphic key、float/unsafe integer、set-like array 乱序/重复、非法
  result/attempt 终态、ID/UTC 日期不符、artifact-set digest 不符。
- exact-local-port 缺 `networkPort`、端口为 bool/float/string/null/越界、非 exact policy 携带
  端口、unknown network/字段，以及 passed evidence 中 exact-port probe failed/skipped；同时
  保留无 port 的旧 deny-all/loopback v1 正例。
- evidence publish basename/gate directory 不匹配、existing output、symlink/hardlink、
  group/world-writable parent、staging pathname replacement；bundle claim 跨 role 复用 path、
  casefold/inode alias、单文件/文件数/总字节超限、read 时 inode/size/hash 改变或 I/O error。
- formal record 缺 external anchor/eligible host/deny-default/required inputs、出现 retry、未 retained
  artifact、截断/未扫描日志；revocation ledger 缺链、分叉、未知 authority 或 replacement 不符。
- allow-default/wildcard policy、policy read、stage source/output write、未批准 exec；runtime 相邻
  端口、外部地址、同机 LAN exact-port 暴露、Anvil chain-id/process identity 变化。
- inherited writable FD、interactive stdin、descendant-held pipe、fast leader exit、timeout/
  output-cap cleanup、PGID reuse 与 `setsid()` session escape。
- policy/receipt preexistence、symlink/hardlink/path replacement；failure tail 的 ANSI/OSC/control
  byte 必须 ASCII-escape，但 printable secret 仍需 formal retained/private scan/redaction。
- invocation receipt 的 policy/port/argv/env/terminal/raw-stream digest、receipt-last commit
  marker、rollback/partial-set rejection；catalog content/domain digest、exact-set、split-brain、single-snapshot 与
  development-only finalization negatives。完整矩阵见
  [`SPEC-EVFINAL-001`](specs/gate-catalog-finalization.md)。

## Gate 设计

预期命令名：`v2-source-core`、`v2-counter-four-target`、
`v2-target-extension-rejection`、`v2-artifact-repeatability`、`v2-missing-tool`、
`v2-runtime-primary-triad`、`v2-zk-noir-e2e`、`v2-clean-room`、`v2-check`。
命令未实现前它们是 specified，不得记录为通过。

`v2-clean-room-alpha` 是 pre-acceptance development command，`isolated-check` 是其兼容
别名；二者不占用正式 `v2-clean-room` 命令名，也不关闭 `TST-ISO-002` 或
`TST-ISO-003`。

当前 development alpha 已实际覆盖 deny-default `materialize`/`core`/`evm-runtime` stages、
closed-FD launcher、bounded private receipts、原 process-group cleanup、exact-local-port 与
Anvil `127.0.0.1` bind/LAN refusal；evidence v1 candidate 也已覆盖 exact-port 条件字段、边界、
错误类型与 current-reader 对旧 record 的兼容。H1e-a 还提供 opt-in 的 canonical run/invocation
contexts、policy/port/argv/env/terminal/raw-stream-bound metadata receipt、single-writer reservation
和 receipt-last publication；当前 alpha runner 尚未传入这些 opt-in contexts，也未 retained 新
metadata receipt。`networkPort` 与真实 retained policy/receipts/probes 的 catalog binding、完整
old/new reader fixture matrix、`setsid()` session escape、eligible host、formal Stage-0 handoff、
gate catalog/freshness/revocation/private scan 和正式 finalizer 仍是验收缺口。

H1e 固定按 invocation receipt → catalog core → real retained bundle integration 三个切片实施；前
两个切片通过不能追溯升级 H1c/EV-0015，也不能关闭 `TST-EVIDENCE-001`、`TST-ISO-002/003`
或 `TST-VER-001`。

## 证据要求

每次 gate 的目标输出是符合 [`TRACE-EV-001`](traceability/evidence-schema.md) 的不可变 `EV-*`
JSON：candidate commit/tree/git-tar anchor、dirty/unchanged、local host observation、环境、sandbox
policies/probes、工具 closure、全部 attempts、inputs/artifacts、domain-separated artifact-set
digest、normalized observations 和 logs。

验收必须分别覆盖：

1. restricted integer-only/ASCII-graphic-key PF JCS、exact-local-port 条件 port matrix 和所有
   schema/cross-field negative；
2. inputs、retained artifacts、logs 的逐组件 no-follow point-in-time size/hash 复核；
3. formal gate catalog 对 required tests/tools/probes、freshness、host/candidate、private scan 和
   revocation lookup 的完整 finalization。

前两层不能代替第三层。当前 formal publisher 继续 fail closed；development schema/bundle
结果不能关闭 `TST-EVIDENCE-001`。外部工具缺失必须让相应 required gate 失败，不能 skip 后仍
标绿。development flaky retry 必须记录全部 attempts；formal passed 只允许一次 attempt。
撤销/修正必须追加独立 revocation record 并保留原 EV；该 revocation parser/store 尚未实现。

## Release Acceptance

Phase 1 release 要求本表所有 required TST 有最新 EV；四目标 aggregate、security、
repeatability、clean-room 全绿；无 P0/P1 review finding；所有文档 trace 关闭。
