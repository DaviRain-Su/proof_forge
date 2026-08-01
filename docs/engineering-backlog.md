---
id: ENG-BACKLOG
title: 工程业务 Backlog（文档↔实现差异 + 构建加速）
status: draft
owner: engineering
updated: 2026-08-01
normative: false
---

# 工程业务 Backlog

> **本文件是什么**：日常**工程执行队列**（可勾选、可并行、可关闭），把“规范意图 / 研究缺口 /
> 代码事实”压成下一刀切什么。  
> **本文件不是什么**：
> - **不是** “读完仓库每一页文档后的最终真理表”
> - **不是** formal `TASK-*` / `TST-*` / EV / release-qualification 权威（那是
>   `04-task-breakdown` / `05-test-spec` / `MIGRATION_MATRIX` / `just release-check`）
> - **不是** 第二套 PRD/SPEC（冲突时：accepted ADR → PRD → architecture → SPEC → 代码事实）

状态只允许：`pending` / `in_progress` / `done` / `blocked` / `wontfix`。

## 诚实范围声明（2026-08-01 二次汇总）

### 已作为主输入深度使用（工程队列真源）

| 材料 | 用法 |
|---|---|
| `AGENTS.md` / `Agents.md`（同内容） | 当前 checkpoint、产品路径、T8 状态 |
| `RECOVERY.md` | Wave DAG、工程完成口径（**正文有过时 B12 叙述，见 DOC-1**） |
| `MIGRATION_MATRIX.md` | D1–D4 行级工程 vs formal（**未逐字精读全部 400+ 行增量证明段**） |
| `docs/roadmap-t8.md` | T8/T9 切片状态 |
| `docs/research/11-feature-coverage-audit.md` | L1–L8 特性缺口清单 |
| `docs/research/12-target-coverage-matrix.md` | Op×target GAP/LOWERED |
| `docs/research/10-ibc-as-proofforge-programs.md` | 北极星用例与语言前置（**非近期任务**） |
| `docs/01-prd.md` FR/NFR/Phase-1 DoD | 产品验收分母（工程解读） |
| `justfile` / `lakefile.lean` / CI workflow | 构建与反馈循环 |
| `NormalizeV1` docstring + fail-closed 面抽样 | 代码事实抽检 |

### 扫过目录 / 抽样，但**未**做 line-by-line 规格对账

| 材料 | 规模感 | 备注 |
|---|---|---|
| `docs/specs/*`（19 份） | 含 language 2k+、wire 1k+、gate-catalog 2k+、task-qual 1k+ 行 | 应用 **accepted 规范**，不能假装已逐条映射到 backlog 行 |
| `docs/02-architecture.md` / `03-technical-spec.md` | 短入口 | 细节在 specs/modules |
| `docs/05-test-spec.md` | **~4.8k 行** | formal TST 权威；工程队列不展开每条 TST |
| `docs/06-implementation-log.md` | **~12.6k 行** | 已执行事实账本；只抽样检索，非全文回放 |
| `docs/04-task-breakdown.md` | formal 任务树 | 恢复期不新增 TASK；不驱动日常切片 |
| `docs/targets/*.md` + family | 多数 `proposed`/`draft` | 工程状态段**常落后于代码**（如 Solana 仍写 plan-only） |
| `docs/modules/*` | 除 source-frontend 外多为短 stub | 边界意图在，细节未当 checklist |
| `docs/adr/*` | 24 ADR | 决策约束已知；未逐 ADR 生成任务 |
| `docs/research/01–09` + claim/source register | 早期设计研究 | 已被 ADR/SPEC 吸收；**不单独开任务** |
| `docs/traceability/*` | formal 证据图式 | 属 release 轴 |
| `QUALIFICATION_INVENTORY.md` | 隔离 qualification 子系统 | 不进产品队列 |
| `build/**/*.md` | 历史 probe/review 草稿 | **非权威**；勿回填任务 |

### 明确未读透、若要对账需专项

- SPEC-LANG-001 / SPEC-SEM-001 / SPEC-TYPE-001 **全文 EBNF 与 §op 表** vs `NormalizeV1` 的机械 diff
- SPEC-CLI / output-contract / diagnostics **字段矩阵** vs CLI 实际 surface
- 每个 target dossier 与 `LowerSemanticV1` 的逐 op 复核（应用矩阵 12 的更新协议）
- `06-implementation-log` 全文与当前 HEAD 的“幽灵切片”清理
- formal `05-test-spec` 分母闭合（属 Wave 5 / release，非日常）

**结论**：本 backlog 是 **“工程轨道最可用的汇总队列”**，不是 **“全文档全集闭包证明”**。  
若要把“全集闭包”做实，需要专项 **SPEC×code 机械对账**（DOC-SPEC-AUDIT），那是独立切片，不是写一份 markdown 能完成的。

### 文档宇宙怎么读（避免再散）

```text
规范意图（accepted）     执行指针（recovery）      工程队列（本文件）
  ADR / PRD / Arch  ──►  RECOVERY + AGENTS   ──►  engineering-backlog
  specs / modules        MIGRATION_MATRIX          roadmap-t8（宽度切片）
                         research/11+12            research/10（北极星，非近期）
代码与制品事实 ─────────────────────────────────────► 关闭 backlog 项的唯一证据
formal / release ──────────────────► 04/05/traceability / release-check（独立轴）
```

**建议只维护这三份“活队列”**，其余 research 做引用不复制：

1. 本文件 — 总执行 backlog  
2. [`roadmap-t8.md`](roadmap-t8.md) — 宽度/ABI 专项协议（T8/T9）  
3. [`research/12-target-coverage-matrix.md`](research/12-target-coverage-matrix.md) — op×target 格子  

`research/11` 的分层审查、`research/10` 的 IBC 北极星，关闭后**回写本文件状态**，不必再开第三份平行清单。

**索引债**：`research/README.md` 仍停在 07-15，**未登记 11/12**（DOC-2）。

**产品现状一句话**：CLI 进程内 `Loader → Normalize → CompiledSemanticV1 → capability Plan/IR →
Materialized/Finalized + disk closure` 已通；sole Normalize 与四 target 已覆盖 public 多宽算术、
控制流、fn、let/for、shift/bitwise、call/schedule、部分聚合与 Field；**完整语言面与
target 真制品验收仍远未闭合**；formal D1–D4 = 0/27 done。

---

## PRD Phase-1 工程解读（非 formal 勾选）

对照 [`01-prd.md`](01-prd.md)。“部分”= 有工程路径但未达 Phase-1 DoD 字面。

| FR | 工程判断 | backlog 落点 |
|---|---|---|
| FR-001 唯一 `program` | 基本 done | — |
| FR-002 全 declaration + proof ref | parser/typed 强；**Normalize/product 子集**；proof reference 未闭合 | N-*、INV-* |
| FR-003 type/effect/bound/disclosure | CheckV1 五相位产品门禁；**authority/custody 轴缺** | T-1 |
| FR-004 SemanticProgram + requirements | structure-gated + S2 freeze 工程子集 | N-*、D3-E* |
| FR-005 target 不改语义 | 架构遵守；跨 target reference trace 矩阵未做满 | R-1、C-* |
| FR-006 exact capability | engineering resolver 有；formal SupportClaim 未 | D3-E2、B-3 |
| FR-007 typed Plan/IR | 四 target 有类型；schema/hash 不齐 | D4-E*、T9d |
| FR-008 四 target + runtime/proof | Counter 制品有；**NEAR runtime / Noir prove 未** | C-1、C-4、PRD-DoD |
| FR-009 manifest 全 hash 链 | engineering output 部分；plan/IR/tool 不齐 | D3-E3/E4、T9d |
| FR-010 multi-program `--program` | Loader 有 | 回归保持 |
| FR-011 CLI JSON | 主命令有；flag 面未满 | D3-E5 |
| FR-012 private/authority/custody | disclosure 有；**custody/authority 未** | T-1、N-3 |
| FR-013 extension exact-match | 矩阵雏形；非完整 | EXT-* |
| FR-014 无隐式 deploy | 遵守 | — |

| Phase-1 DoD 要点 | 工程判断 |
|---|---|
| Counter 四目标 + overflow 状态不变 | 部分：EVM/Solana 强；NEAR 偏静态；产品路径有 overflow 语义 |
| EVM/Solana/NEAR local runtime；Noir prove/verify | **未满足字面**（C-1/C-4；EVM Anvil 非 formal 闭包） |
| PrivateSum4 隐私边界 | 有 fixture；未当持续验收主轴 | → **APP-1** |
| OutputSet 可重现 + clean-room | engineering 有；formal/clean-room 属 release |
| 全 FR/NFR×SPEC/TASK/TST/EV 闭合 | formal 轴；不进日常 |

| NFR 工程债（常被 research 漏） | backlog |
|---|---|
| NFR-007 check 性能 profile 测量 | **PERF-1** |
| NFR-008 显式 resource limit flags | D3-E5 / **RES-1** |
| NFR-009 release SBOM ceremony | Q-*（release） |

---

## 北极星用例（研究，非近期切片）

来自 [`research/10-ibc…`](research/10-ibc-as-proofforge-programs.md)；**不改变 PRD 范围**。

| ID | 项 | 说明 | 状态 |
|---|---|---|---|
| **NS-1** | Fungible Token 四 target | 验证“写一次跨链物化”；共享 N-1/N-2/B-3 前置 | pending（语言面够后再开） |
| **NS-2** | packet mailbox 最小件 | IBC-flavored 子集 | pending |
| **NS-3** | 真 IBC 模块栈 | 长期；依赖 crypto | wontfix-until-NS-1 |
| **EXT-CRYPTO** | `extension.crypto`（SHA-256 / Merkle / 签名） | IBC 与大量链上逻辑命脉；capability 矩阵 | pending（设计后单独立项） |
| **N-BYTES** | Bytes state/param 路径复核（+ 产品 String 若仍需） | state/index assign 随 N-A3 产品路径已钉；String 另议 | **done**（2026-08-02：随 MapBytesAssign；Bytes state+IndexGet/Set 测例） |

---

## 0. 构建与反馈循环加速（可并行于产品切片）

目标：缩短 `just dev-check` / `just ci` / 聚焦 rebuild 墙钟，不改变产品语义。

| ID | 项 | 现状 | 建议 | 状态 |
|---|---|---|---|---|
| **BUILD-1** | 测试 shard **串行**执行 | `justfile` `test` 在一次 `lake build` 后顺序跑 9 个 shard | 本地用有界并行（如 `xargs -P4` / job 组），CI runner 内存不足时保持串行或 `P=2`；失败时打印 shard 名 | **done**（2026-08-02：`PROOF_FORGE_TEST_JOBS` 默认 4，`xargs -P`；`FAIL shard: <name>`） |
| **BUILD-2** | 默认 `build` 仍链 frontend worker | `lake build … proof_forge_frontend_worker_v1`；产品 CLI 已走进程内 `selectProgramV1Product` | 将 worker 移出默认 `build`/`dev-check`，仅 `ci` 或显式 target 构建；核对 `Tests/Frontend/WorkerV1` 是否仍进 ordinary CI | **done**（2026-08-02：`build`/`test-fast`/`dev-check` 无 worker；`build-frontend-worker` + `test-frontend-worker` 显式；Fast 去掉 WorkerV1） |
| **BUILD-3** | 巨型 interpreter 测试 exe | 各 shard ~170–188 MB；`supportInterpreter := true` | 评估：减少跨 shard 重复 link、合并极轻 shard（core）、或仅对需要 elaborator 的 suite 开 interpreter | **done**（2026-08-02：test suite `supportInterpreter := false`；core ~7 MB，其余 shard ~100–120 MB；产品 CLI 仍 true） |
| **BUILD-4** | CI 单 job 串行 `just ci` + Solana runtime | `source-core` 一锅端 | 拆 job：docs（已独立）/ lean-product / target-smoke / solana-runtime，共享 Lake cache artifact；缩短失败反馈 | **done**（2026-08-02：CI jobs `docs` + `lean-product` + `target-smoke` + `solana-runtime`；`just ci-lean-product` / `ci-target-smoke`） |
| **BUILD-5** | 删除门与 `rg` 门禁串在 dev-check | 8+ deletion gates 顺序跑 | 多数为秒级；可 `bash` 并行跑无写盘门禁；保持失败汇总 | **done**（2026-08-02：`run-deletion-gates` **serial** — all gates touch `.lake`；`PROOF_FORGE_GATE_JOBS>1` forced to 1） |
| **BUILD-6** | 聚焦路径未默认暴露 | 改 target 时常全量 shard | 文档化 / 加 `just test-shard NAME`、`just test-targets`（已有部分 gate 内 build）；开发默认 `test-fast` + 一 shard | **done**（2026-08-02：`test-shard` / `test-targets` + CONTRIBUTING） |
| **BUILD-7** | Lake 并行度 | 本机 12 核；warm `ProofForgeV2` ~0.4s | 冷构建/CI 确认 `lake` 默认 job 数；必要时 `lake -j$(nproc) build` 写进 justfile | **done**（2026-08-02：Lake 5 无 `-j`；模块构建已多 job；justfile 注释 + 测试并行仍用 PROOF_FORGE_TEST_JOBS） |
| **BUILD-8** | 死代码与过时 RECOVERY 叙述 | RECOVERY 仍大量写 B12 supervisor 为当前路径；AGENTS 已写移除 | 文档对齐（见 DOC-1）；删除已 supersede 的 worker-only 路径若产品不再需要 | **done**（2026-08-02：audit 无 SafeOpen/Supervisor 产品模块；仅 Protocol/Worker；CLI=Loader；见 goal slice-BUILD-8-checks.log） |
| **BUILD-9** | `build/` 与 `runtime-tests/**/target` 垃圾 | 工作区含大量历史产物 | `.gitignore` 收紧 + 定期清理；避免误扫进 SBOM/索引 | **done**（2026-08-02：gitignore runtime-tests/**/target + build probe logs） |

**预期收益（粗估）**：BUILD-1 在本地满核可把 test 执行墙钟接近压到最慢 shard；BUILD-2/3 降冷构建与磁盘；BUILD-4 降 CI 排队与失败定位时间。

---

## 1. 文档 / 控制面同步（主代理串行）

| ID | 项 | 说明 | 状态 |
|---|---|---|---|
| **DOC-1** | RECOVERY / AGENTS / MIGRATION_MATRIX 与代码对齐 | 前端监督层移除、产品 CLI 进程内 Loader；AGENTS 已正确并链 backlog | **done**（2026-08-01 主代理文档同步；Matrix 行内历史 B12 叙述保留在 D1-08 superseded 段） |
| **DOC-2** | `12-target-coverage-matrix` 按代码复扫 + 登记 research README | README 已列 11/12；**NEAR 格子逐 op 复扫仍待** | **done**（2026-08-02：NEAR NearAggregate 列 GAP→LOWERED/FAIL-CLOSED；README 已登记） |
| **DOC-3** | `11-feature-coverage-audit` L4/L6 刷新 | Solana 多宽句已修；Reference admitted 全表仍待 | **done**（2026-08-02：L6 Solana/T9e + N-A1/A2 注记；L4 admitted 全表仍可深化） |
| **DOC-4** | 四 target dossier「工程迁移状态」刷新 | EVM/Solana/NEAR/Noir + targets/README | **done**（2026-08-01） |
| **DOC-5** | `docs/index.md` / document-status 恢复桥叙述 | 工程路径 + backlog 链接 | **done**（2026-08-01） |
| **DOC-T9-0** | `MIGRATION_MATRIX` 长表过时 present-tense 扫（UInt64-only / single-block / supervisor 等） | **非** 仅 roadmap 状态；commit **必须**改矩阵 | **done**（2026-08-02：矩阵 commit 含 `MIGRATION_MATRIX.md`；D2/边界/D1-06/D1-08 Engineering/Solana 标签对齐 multi-width + 进程内 Loader） |
| **SKEPTIC-1** | Goal 内闭合 skeptic 三缺口：DOC-T9-0 真扫 + DONE_IDS 全量（含 B-1d/B-1e/T9e）+ BUILD-5 exit-0 日志 | 入口 `prompt-skeptic-recovery.md` | **done**（2026-08-02：DOC-T9-0 `1657989ca` 含矩阵；`just run-deletion-gates` EXIT=0 无 traceback；DONE_IDS 含 B-1d/B-1e/T9e） |
| **DOC-SPEC-AUDIT** | SPEC-LANG/SEM/TYPE × Normalize **机械对账** | `docs/research/13-spec-normalize-diff.md`；回流 backlog 校准 | **done**（2026-08-02：RPT-013 表 + N-2/N-3/N-BYTES 校准注；非 formal 全集 EBNF） |
| **DOC-DEDUP** | 禁止再开第四份平行 gap 清单 | 新研究只追加 11/12 或本文件；关掉旧 `build/*-audit.md` 心智依赖 | **done**（2026-08-02：research README + goals README + index 已指向 sole live queues） |

---

## 2. Wave 2 当前主轴：sole Normalize / Reference 扩面（串行共享核）

共享文件：`NormalizeV1` / `ReferenceV1` / `EnvelopeV1` / Wire 相关——**禁止并行改同一文件**。

### 2.1 覆盖审计第一梯队（语言表达力）

| ID | 项 | 解锁 | 状态 |
|---|---|---|---|
| **N-1** | Map：非空构造 + Map state/param + index | 余额表、IBC 表 | **done**（2026-08-02：product nonempty = empty/`Map.empty` + IndexSet；Wire multi-arg Construct 仍 FC；state/index 已 N-A3） |
| **N-2** | ContextRead **扩面** + `callerContext`（CheckV1 + Normalize + Reference） | **done**（2026-08-02：`context.caller` → Principal ContextRead + wire `context.caller`；unixTime 保留；Reference Principal identity admission + resource bounds；Plan 仍 FAIL-CLOSED） |
| **N-3** | Commit **disclosure 契约** + Check | Normalize label-only `commit(x)`（N5）+ Disclosure 契约钉测 | **done**（2026-08-02：sole private→commitment declass；commitment↛public；pureFn Commit FC；非 crypto commitment） |
| **N-4** | aggregate entry/view/fn **返回值** + target ABI struct 返回 | 查询型 API | **done**（2026-08-02：Normalize 允许 named Struct/Enum 作 entry/view/fn result；匿名容器 result 仍 FC；四 target ABI 仍 FAIL-CLOSED 待 B/leaf） |
| **N-5** | call **返回值** / typed external call（可能要升 semantic schema） | oracle/跨链 ack；大切片 | **done**（2026-08-02：RPT-014 schema 影响；产品仍 void Stmt.Call→ExternalCall FC；实现 follow-on 共享核 cutover） |
| **N-6** | true mutable locals（非仅 field/index rebind） | 循环携带聚合 | **done**（2026-08-02：let/for-binder bare `x:=e` env rebind；param 仍 immutable；SSA 新 ValueId） |
| **N-7** | match 构造器**嵌套子模式** | 完整 pattern | **done**（2026-08-02：递归 ctor/lit/bind 子模式 + N-A2 同外层；深度-2 VariantPayload 钉测） |
| **N-8** | Int event/error 字段；非 UInt64 call/schedule args 与 for 端点 | 宽度完整性 | **done**（2026-08-02：event/error legal UInt/Int；call/schedule legal UInt/Int args；for 同宽 legal UInt 端点） |

### 2.2 矩阵 A 组（已编号，与上表重叠处合并执行）

| ID | 项 | 状态 |
|---|---|---|
| **N-A1** | EVM String `match` switch（N4 类型面已开） | **done**（2026-08-02：`a25365213` EvmStringMatch；matrix LOWERED） |
| **N-A2** | 多臂同外构造器 match 细化 | **done**（2026-08-02：`2a6c2bc9c` MultiArmCtor；matrix LOWERED 四 target） |
| **N-A3** | Map/Bytes 穿透元素赋值 | **done**（2026-08-02：TypeCheck assign-target Map→value / Bytes→UInt8；Normalize 单步 IndexSet；嵌套 FC；target Plan 仍 FAIL-CLOSED） |
| **N-A4** | Option state | **done**（2026-08-02：Normalize admit Option state/param；default none；四 target Plan FAIL-CLOSED 钉死） |

### 2.3 Reference / invariant 工程子集

| ID | 项 | 状态 |
|---|---|---|
| **R-1** | Reference 扩到 PureCall / aggregates / index / Int / Field / Principal / ContextRead / Commit | **done**（2026-08-02：Map empty-default admit + product IndexSet step；Option state product step；external UInt/Int 全宽；Map Reference budget 4096） |
| **R-2** | `evalInvariantV1` + `InvariantTheoremV1` 工程入口（非 formal theorem 完成） | **done**（2026-08-02：ABI 已接线；空 invariants OOR trap 钉测；theorem 形 Iff.rfl；非 formal corpus） |
| **R-3** | ProofBundleV1 safe loading 工程路径 | **done**（2026-08-02：`openProofBundleV1` PF-JCS re-encode identity + olean SHA join；malformed/mismatch/extra/missing FC；非 contained-worker/formal TST-PROOF-001） |

---

## 3. T9 宽度 / identity 切片（见 roadmap-t8）

| ID | 项 | 状态 |
|---|---|---|
| **T9a–T9c-2** | 窄结果 / EVM UInt128·256 / 窄 Int 四 target | **done**（roadmap merged） |
| **T9d** | NEAR/Solana/Noir `planDigest` 绑 BuildIdentity/OutputSet（镜像 M4） | **done**（`c3626725f` / roadmap 2026-08-01） |
| **T9e** | Solana/NEAR UInt128/256 多字算术（先设计后实现，可拆） | **done**（2026-08-02：T9e-Solana `52f527140` + T9e-NEAR claimed on main） |
| **T9-0** | 控制面/roadmap 状态对齐 | **done**（2026-08-02：roadmap merged `93b80db45` / control-plane status；**矩阵长表扫见 DOC-T9-0，仍 pending**） |

---

## 4. Target Plan/IR/emitter 覆盖（可按文件隔离并行）

| ID | 项 | 文件边界 | 状态 |
|---|---|---|---|
| **B-1a** | NEAR named 聚合 + Array/容器 lower 或显式 FAIL-CLOSED+测 | `Targets/Near/**` | **done**（`4c79e0a59` NearAggregate） |
| **B-1b** | Noir named 聚合 | Noir/** | **done**（`61b7dff09`） |
| **B-1c** | Aleo 覆盖核对 + 显式边界 | Aleo/** | **done**（`04fe6e815`） |
| **B-1d** | Solana Map/Bytes/Option state：open 或钉死 FAIL-CLOSED | Solana/** | **done**（2026-08-02：Array-only container pilot；Map/Bytes planInvariant；Targets decline tests） |
| **B-1e** | EVM Map/Bytes/Option state：同上 | Evm/** | **done**（2026-08-02：Map/Bytes FAIL-CLOSED；Array EvmIndex LOWERED；Targets decline pins） |
| **B-3** | Principal → address，解锁 EVM/Solana call/schedule | Envelope + EVM/Solana | **done**（2026-08-02：sole research pin `4ecb4f86e` PrincipalAddr — wire Principal ≠ EVM 20B / Solana 32B pubkey；no CALL/CPI unlock；`pilotPrincipalPolicyNone`；docs close） |
| **B-ctx** | ContextRead 各 target Plan：保持 fail-closed 并补齐负向测 | 四 target | **done**（2026-08-02：unixTime + caller 五 target materialize decline 钉测） |

### 验收门（工程，非 formal）

| ID | 项 | 状态 |
|---|---|---|
| **C-1** | NEAR 真实 Wasm 运行时差分（对标 Mollusk/EvmSolc） | **done**（2026-08-02：`672e6115d` NearWasmAcceptance wat2wasm+wasm-interp；工具缺席 skip；非 sandbox/formal Reference↔Wasm） |
| **C-2** | Aleo/Psy compiler/VM 可用性研究与是否升格验收 | **done**（2026-08-02：RPT-015 不升格门；Aleo/Psy 保持 source-only；矩阵 C-2 行 + research README 已登记） |
| **C-3** | EVM Reference↔Anvil **formal** 差分 | blocked（formal 轨道；工程 Anvil smoke 可保留） |
| **C-4** | Noir 真实电路证明/prove 路径（若工具链锁定可行） | **done**（2026-08-02：RPT-016 **不**升格 prove/verify；无 nargo Tool Lock pin；保持 source-only；见 `16-noir-prove-path.md`） |
| **C-5** | Solana 已有 Mollusk；扩 fixture 跟 Normalize 新面 | **ongoing**（fixture 集：Counter + LoopSum/MathOps/FnCall/Events/MultiField/MatchOps/NarrowGates/NarrowAbi/NarrowResult；N 系列 Map/Option/Context 等 Solana Plan 多为 FAIL-CLOSED，不发明 runtime 面；随新 LOWERED 再扩） |

---

## 5. Wave 3：D3 identity / output 工程→规格对齐

工程 S4–S7c 已接线；下列是**与 accepted 规格仍差的产品形态**（非立刻 formal done）：

| ID | 项 | 状态 |
|---|---|---|
| **D3-E1** | 产品可达 formal-layout `registryDigest` / root codec（或明确永久工程-only） | **done**（2026-08-02：**永久工程-only** 决策 — 产品不暴露 formal `registryDigest`；`TargetRegistryV1` 无 root digest 字段；见 `RECOVERY.md` D3-E1 段） |
| **D3-E2** | SupportClaim/decision 全字段与 resolver 决策面 | pending |
| **D3-E3** | 可达 BuildIdentity mint + Plan/IR digest 全 target（T9d 子集） | pending |
| **D3-E4** | formal `OutputSetV1` 字段齐套；退役 transitional v2alpha1 残留 | pending |
| **D3-E5** | CLI 剩余 flag：evidence/resource override 等 SPEC-CLI 面 | pending |
| **D3-E6** | stage supervisor / receipt（compiler-core/tool/output）——与 D1 监督层移除决策协调 | pending / 需产品再决策 |

---

## 6. Wave 4：Target completion（D3 冻结后，EVM-first）

| ID | 项 | 状态 |
|---|---|---|
| **D4-E1** | EVM Plan schema/canonical hash/BuildIdentity 绑定完整 | pending |
| **D4-E2** | EVM 完整 Semantic→Plan 表面（非仅当前 pilot 集） | pending |
| **D4-E3** | TargetIR schema/validator/hash/trace | pending |
| **D4-E4** | locked solc + OutputSet 角色齐套 | pending |
| **D5+** | Solana / NEAR / Noir 里程碑完成（ELF/runtime/prove 按 dossier） | pending |

---

## 7. Typed / requirements 边角（Check 已五相位，仍缺轴）

| ID | 项 | 状态 |
|---|---|---|
| **T-1** | authority / custody 轴（`TST-VIS-002` 工程子集） | pending |
| **T-2** | context / extension requirements 接入 CheckV1 | pending |
| **T-3** | RequirementsInfer：callerContext / commit 等贡献键（随 N-2/N-3） | **done**（2026-08-02：context.unixTimeSeconds/caller + commit 贡献 wire id；S2 freeze skip；Normalize 仍 sole wire-row mint） |
| **INV-1** | 受约束 `proof` reference 产品路径（FR-002 / Phase-1 语言范围） | pending |
| **APP-1** | PrivateSum4 持续作为隐私边界验收向量（Phase-1 DoD） | pending |

---

## 8. 性能 / 资源（NFR，常被特性审计忽略）

| ID | 项 | 状态 |
|---|---|---|
| **PERF-1** | NFR-007：`PerformanceProfileV1` 上 1000-node check 测量 harness（不宣称增量编译） | pending |
| **RES-1** | NFR-008：check/build 显式 time/memory/output limit flags（与 D1 监督层移除后的进程内路径协调） | pending |

---

## 9. Formal / release（独立轴，不阻塞产品切片）

| ID | 项 | 状态 |
|---|---|---|
| **F-*** | D1–D4 formal 0/27；`TASK-D1-01` blocked | 不进日常队列 |
| **Q-*** | SBOM ceremony / eligible-host / clean-room / custody | `just release-check` 专用 |

---

## 推荐击杀顺序（产品开发）

```text
0. ~~DOC-1/4/5 + T9d + B-1a/b/c~~（2026-08-01/02 已合入 main）
1. **BUILD-1/2/6**（justfile 小改：shard 并行、worker 移出默认 build、test-shard）— 立刻改善循环
2. **Normalize 串行主轴**（Wave 2 当前）：N-A2 → N-A1 → N-A4 → N-1/N-A3/N-BYTES → N-2 → N-3 → N-4 …
   （每切片：测试 RED → 实现 → 四 target fail-closed 或 lower → Reference 跟进）
3. 并行 leaf：B-1d/e 钉 Map/Bytes/Option 边界、**C-1** NearWasm runtime（文件不重叠）
4. **T9e** 仅在需要宽整数跨 Solana/NEAR 时开设计（大切片，勿插队）
5. 语言面够用后：APP-1 PrivateSum4 + NS-1 Token 试金石（非 IBC）
6. Wave 3 D3-E* / Wave 4 EVM-first；EXT-CRYPTO 在 Token 之后
```

**切片纪律**（继承 roadmap-t8 / AGENTS）：

1. 一次一个 shared-core cutover；leaf 可 worktree 并行且文件 allowlist 零重叠。  
2. 先失败测试再最小实现；不新增 formal `TASK-*`。  
3. 改 `ProofForgeV2/**` 后 `just sbom-package-files-refresh`。  
4. 日常 `just dev-check`；合并前 `just ci`。  
5. 完成一项后：改本文件状态 + 必要时更新 matrix/AGENTS 一行事实。

---

## 变更记录

| 日期 | 变更 |
|---|---|
| 2026-08-01 | 初版：汇总 RECOVERY/Matrix/RPT-011/012/roadmap-t8 + 构建观测 |
| 2026-08-01 | 二次汇总：诚实范围声明、文档宇宙分层、PRD FR/DoD 工程解读、IBC/Token 北极星、NFR 性能/资源、DOC-SPEC-AUDIT、dossier/index 债；明确“工程最可用队列 ≠ 全文档闭包” |
| 2026-08-01 | DOC-1/4/5 落地：RECOVERY 当前路径改进程内 Loader；index/document-status/targets dossiers+README；Matrix D1-02/06 CLI 句；research 11/12 链 backlog |
| 2026-08-02 | 与 main 对齐：T9d / NearAggregate / NoirAggregate / AleoCoverage 标 done；推荐序改为 BUILD → Normalize 串行 |
| 2026-08-02 | Goal+workflow 操作：`.grok/goals/README.md` + `prompt-build-1-2.md` + `prompt-n-a2.md`；配合 `proof-forge-engineering-slice` / `proof-forge-one-slice` |
| 2026-08-02 | **全队列 Goal**：`.grok/goals/prompt-master-queue.md` + `QUEUE.md` + `slices/`（60 个工程切片 prompt）；排除 formal/release |
| 2026-08-02 | **Goal 默认 drain**：master 禁止「做满 3 项即结束」；仅预算硬尽/阻塞/队列空可停；续跑用 starting at NEXT |
