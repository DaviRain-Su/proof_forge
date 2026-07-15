# Core 导出 v0（草稿）

状态：**实验性草稿（非稳定产品 API）**  
父设计：[Lean / Rust 边界](2026-07-15-lean-rust-boundary-design.zh.md)  
伴生：[制品契约 v1](2026-07-15-artifact-contract-v1.zh.md)

英文原文：[2026-07-15-core-export-v0-draft.md](2026-07-15-core-export-v0-draft.md)

在主三链 authoring cutover 与 HostOp 身份工作足够安静、导出 churn 可接受之前，
**不要**作为默认 CLI 产品路径实现。在此之前优先标
**`core.v0` / experimental**；仅在有明确决策与 dual-run 窗口时升到 `core.v1`。

## 目的

序列化**已检查**的 Canonical Core 与已解析 CapabilityPlan，使外部工具
（Rust inspect、以后可选后端）能在不解析 Lean 源、不链接 Lean 对象的情况下
消费含义。

Lean 仍是 Validate 与 Semantics 的权威。Export 是对已检查语义程序的
**足够无损投影**，供 lowering 与哈希使用。

## 何时允许导出

仅在以下全部成功后导出：

1. Frontend materialize / normalize 进入 Canonical Core
2. `IR.Core` type/validate（fail-closed）
3. 对请求 target profile 的 CapabilityPlan 解析
4. 所选目标上 HostOp 的精确 id/version 解析

任一失败：**不写语义 export 目录**（或仅在语义 hash 树外写 diagnostics JSON）。
与 Validate 的 fail-closed 对齐是 Phase 1 门禁。

## 建议目录布局

```text
build/export/<module>/<targetId>/
  export-meta.json           # 版本、hash、工具链、git 身份
  source-manifest.json       # 产品路径、target 请求、输入摘要
  core.v0.json               # 已检查模块（experimental schema）
  capability-plan.v0.json    # 本目标解析后的 capabilities
```

以后可选：

```text
  plan.v0.json               # A0：Lean 建好的 TargetPlan dump，供 dual-run
  core.v0.bincode            # 可选紧凑编码；JSON 仍为参考
```

## `export-meta.json`（示意）

| 字段 | 含义 |
|---|---|
| `schemaVersion` | 导出信封版本（experimental 期间为 `0`） |
| `coreSchema` | `core.v0` |
| `capabilityPlanSchema` | `capability-plan.v0` |
| `leanToolchain` | 来自 `lean-toolchain` 的 pin |
| `leanVersionObserved` | 运行中 Lean 版本字符串 |
| `gitSha` | 可选；worktree 不净时省略或标 `dirty`——策略须写明 |
| `targetId` | 请求的公开目标 id |
| `moduleName` | 逻辑模块名 |
| `contentHash` | **语义包**的哈希（见下） |
| `createdBy` | `proof-forge export-core`（或等价） |

### Content hash 范围

`contentHash` 包含（canonical 字节、确定性键序）：

- `core.v0` 语义体
- `capability-plan.v0` 体
- `targetId`、`moduleName`、schema id

**排除**在 `contentHash` 之外：

- 绝对路径、墙上时钟时间戳
- CanonicalEvidence（source map、诊断 span、迁移痕迹）
- 自由 note、pretty-print 空白变体（只哈希 canonical 编码）
- 不影响语义体的 git dirty 标志

这与架构一致：evidence 不得影响 capability 选择、target plan、渲染制品或语义制品 hash。

## `source-manifest.json`（示意）

| 字段 | 含义 |
|---|---|
| `productPath` | 适用时的仓库相对 Lean 产品路径 |
| `sourceKind` | `contract-source` / intent / fixture 类 |
| `requestedTarget` | 目标 id |
| `inputDigests` | 可选源文件摘要，用于溯源 |
| `notPartOfContentHash` | 明确列出不进入语义 hash 的字段 |

## `core.v0.json` 字段族（示意）

确切构造子以实现时的 Lean `IR.Core` 类型为准。Core 形状变更时必须更新 export；
这正是 cutover 安静前保持 v0 的原因。

| 族 | 意图 |
|---|---|
| `schemaVersion` / `coreSchema` | `0` / `core.v0` |
| `module` | 模块身份 |
| `types` | ops 所需的已检查类型环境 |
| `state` | 逻辑状态声明（无物理 slot） |
| `entrypoints` | 名称、签名、mutability、体 |
| `blocks` / `ops` | ANF/CFG 语义程序 |
| `hostCalls` | 精确 HostOp id + version + 使用位点 |
| `interfaces` / materialization **需求** | 仅目标中立需求；无 Yul/sBPF/Wasm AST |
| `contentHashContribution` | 可选，供 hash 工具自描述 |

**不得出现在 Core export 中：**

- 目标物理布局（EVM slot、Solana 账户偏移、Wasm 线性地址）
- 原始目标 AST 节点
- Frontend Surface / Authored 树
- 证明对象 / Lean 环境指针

## `capability-plan.v0.json`（示意）

| 字段 | 意图 |
|---|---|
| `schemaVersion` | `0` |
| `targetId` | 解析后的目标 |
| `capabilities` | 选中的 capability id |
| `hostOpHandlers` | 精确 HostOp id/version → 目标上可用的 handler 身份 |
| `profileNotes` | 可选、不参与 hash 的诊断 |

## Rust 消费者（Phase 1）

| 消费者 | 角色 |
|---|---|
| `pf-core-inspect` | schema 校验、打印摘要、重算 contentHash（无链 SDK） |
| 未来 `pf-backend-*` | 仅在 dual-run 策略存在后做 Phase 2+ lowering |

Rust 不得把「缺少 Validate」当 soft-success。Lean 拒绝导出时，Rust 后端必须拒绝 lower。

## 确定性门禁（Phase 1）

1. 相同输入 + 相同 Lean pin → 字节级相同的 `core.v0.json` 与
   `capability-plan.v0.json`（canonical JSON 编码）。
2. Validate 失败用例不产生语义 export（或仅非哈希 diagnostics）。
3. 往返或结构检查：导出的 hostCalls ⊆ catalog；每次调用有精确 version。
4. 首批仅子集产品：一个目标上的 Counter + 一个 stateful 产品。

## 与 TargetPlan 的关系（A0）

可选 `plan.v0.json` 可 dump **`buildFromCore` 后 Lean 建好的** target plan，
供 render-only Rust 路径 dual-run。该 plan 为**目标拥有**，不能替代 Core 权威。
Plan schema 按目标独立版本化，与 `core.v0` 分离。

## 晋升标准：v0 → v1

仅当：

1. 主三链 direct authoring 已成为产品默认，且 Core 形状的残留双路径已消失或冻结。
2. HostOp 扩展边界（IR-B*）不再每周重塑 shared Core。
3. 至少存在一个 dual-run 消费者（inspect 或 backend 试点）。
4. 对破坏性 Core 字段变更的书面兼容策略已被接受（决策条目）。

## 非目标

- 对 `core.v0` 的稳定公共 SDK 承诺
- 把 Legacy `IR.Module` / `ContractSpec` 当作长期接缝导出
- 仅用 Rust schema 检查替代 Lean Validate
- 仅因消费了本 export 就宣称未来 Rust lowerer 已形式化验证
