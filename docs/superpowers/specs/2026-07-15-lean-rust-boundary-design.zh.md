# Lean / Rust 边界设计

状态：**已接受为延期边界设计（2026-07-15）**  
实现：**在主三链 authoring cutover 稳定前，仅允许 Phase 0**  
非当前执行账本：在 [PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104)
与 cutover residual 仍打开时，不要把 Phase 2+ 排进当前
[AGENTS.md](../../../AGENTS.md) checkpoint。

英文原文：[2026-07-15-lean-rust-boundary-design.md](2026-07-15-lean-rust-boundary-design.md)

相关：

- [Canonical Core 设计](2026-07-11-core-ir-target-plan-design.md)
  （中文：[.zh](2026-07-11-core-ir-target-plan-design.zh.md)）
- [后端接口](../../backend-interface.md)（中文：[backend-interface.zh.md](../../zh/backend-interface.zh.md)）
- [架构](../../architecture.md)（中文：[architecture.zh.md](../../zh/architecture.zh.md)）
- [Artifact Contract v1 草稿](2026-07-15-artifact-contract-v1.md)
  （中文：[.zh](2026-07-15-artifact-contract-v1.zh.md)）
- [Core export v0 草稿](2026-07-15-core-export-v0-draft.md)
  （中文：[.zh](2026-07-15-core-export-v0-draft.zh.md)）

## 意图

若将 Rust 引入编译路径，必须挂在 Lean 已拥有「检查后含义」之后的稳定接缝上。
产品作者继续写 Lean。Rust 负责工程侧：链 SDK、VM runner、吞吐、并行编排，
以及（可选、更晚）在 dual-run 门禁下的 plan/render lowering。

一句话：

- **Lean** 写到检查后的含义为止（`Checked Core` + `CapabilityPlan`）。
- **Rust** 把含义变成链上可跑的制品与执行证据
  （Phase 0 可以只做证据，完全不碰 lowering）。

## 原则

| 原则 | 含义 |
|---|---|
| Lean 拥有含义 | 产品源、normalize/materialize、Core 校验、能力闭合、可选形式化精化 |
| Rust 拥有工程与链侧重活 | 吞吐、并行、按链隔离的 SDK/VM、差分 runner |
| 只交换稳定制品/契约 | 不交换 Lean 对象指针；不做多链 SDK 巨型二进制 |
| 双跑门禁 | 任何迁走的步骤：Lean 旧路径 vs Rust 新路径，在声明维度上对拍 |
| 形式化钉 Core | 证明与 content hash 钉 Core（或 export hash），不钉 Rust 内部数据结构 |

## 接缝

```text
L0  业务源 (Lean)
    Examples/Product · contract_source · TokenSpec · NFTSpec
              | 必须留在 Lean
              v
L1  Frontend (Lean)
    Authored.Canonicalize · normalize · Materialize
              | 必须留在 Lean（语义入口）
              v
L2  Canonical Core + Validate (Lean)   ★ 语义所有权边界
    IR.Core Syntax/Type/Validate · CapabilityPlan
    可选 Semantics / Formal
         |                              |
         | 接缝 A（推荐主缝）              | 接缝 B（现状 / 最低风险）
         | export Checked Core          | 只交换最终制品
         v                              v
    R1  Rust Plan/Render            R0  Rust Evidence（已有）
        buildFromCore → Plan            testkit harness-* / compare /
        → bytes + meta                  differential pilots
         |
         | 接缝 C（可选）
         v
    R2  按链隔离的 runner（分 crate / lock）
```

**不要**让 Rust 解析 `*.lean` 源或重写 `contract_source`。
那等于再做一个前端，并拆分语义权威。

### 接缝 A 的子缝（建议细化）

现网流水线比「Core 之后全归 Rust」更细：

```text
Checked Core + CapabilityPlan
  → buildFromCore → TargetPlan（Evm ModulePlan / Solana / Near …）
  → Render → 外部工具（solc / wat2wasm / sBPF）→ bytes + artifact JSON
```

| 子缝 | Lean 仍拥有 | Rust 可先拥有 | 风险 |
|---|---|---|---|
| **A0** | Core + CapPlan + `buildFromCore` | 工具链编排 / 可选 plan dump / render 打包 | 最低 |
| **A1** | Core + CapPlan 导出 | 试点目标上的完整 `buildFromCore` + render | Phase 2 主缝 |
| **A2** | 产品语言 + validate + export（+ formal） | 生产默认 lowering | 仅 Phase 4 |

优先证明 A0 有收益，再把 target plan 逻辑整包重写成 Rust。

## 接缝契约

### 接缝 B — 证据层（现状；应先巩固）

| 侧 | 内容 |
|---|---|
| Lean 输出 | `*.bin` / `*.yul` / `*.wat`/`*.wasm` / `*.so`、`proof-forge-artifact.json`、deploy/metadata、SDK schema |
| Rust 输入 | 制品路径 + 场景（`testkit/scenarios`、differential `scenario.v1.json`） |
| Rust 输出 | 退出码、观察 JSON（return/state/events/error）、差分报告、CI 日志 |
| 今日挂点 | `testkit/harness-{evm,solana,near,quint}`、`testkit/compare/*`、`scripts/differential/*`、`tools/*-vm-runner`、`runtime/offline-host` |
| 风险 | 契约版本化后较低；harness 已是分包 |

**Phase 0 动作：** 把制品契约当正式 API（字段、版本、必选路径），而不是脚本约定。
见 [Artifact Contract v1](2026-07-15-artifact-contract-v1.zh.md)。

### 接缝 A — Checked Core 导出（若 Rust 做编译后端）

Lean **仅在** Validate + CapabilityPlan 成功后导出，例如：

```text
build/export/<module>/
  core.v0.json              # cutover 稳定前为 experimental
  capability-plan.v0.json
  source-manifest.json
  export-meta.json          # schemaVersion, leanToolchain, gitSha, contentHash
```

| 侧 | 内容 |
|---|---|
| Rust 输入 | `core.v*` + capability-plan + `--target` |
| Rust 工作 | （A1）`buildFromCore` → target plan → render → 外部工具 |
| Rust 输出 | 与现 CLI 同构的制品树 + 兼容的 `proof-forge-artifact.json` |
| Lean 仍做 | 同一 Core 上的 Semantics / Formal；不依赖 Rust 内存布局 |

字段族与 hash 范围见 [Core export v0 草稿](2026-07-15-core-export-v0-draft.zh.md)。

**关键门禁：** 同一 Product 上，Lean 全路径制品与「Lean 导出 Core → Rust 后端」
制品须在**声明维度**上等价（见下文「等价维度」），不要求 bytecode 字节级相同。

### 接缝 C — 按链隔离的 runner

| 建议 crate | 依赖 | 输入 | 输出 |
|---|---|---|---|
| `pf-run-evm` | revm / alloy（隔离） | bytecode + 调用序列 | 收据 / 状态观察 |
| `pf-run-solana` | mollusk / solana-* | ELF + instruction | 返回数据 / 账户 |
| `pf-run-near` | near-vm / sandbox | wasm + call | 日志 / 存储 |
| 未来 `pf-run-*` | 自有 lockfile | … | … |

规则：

- 禁止把 near + solana + sui SDK 链进同一 package 依赖闭包。
- Lean/CLI 通过进程 spawn（`Command::new`）或 CI `cargo run -p …` 调二进制，
  不做进程内多 SDK 链接。

#### Lockfile：现状 vs 目标

| 状态 | 说明 |
|---|---|
| **今天** | `testkit/` 是一个 Cargo workspace 多 member；`workspace.dependencies` 已同时列出 `revm` 与 `solana-*`。嵌套 NEAR compare 树与 `tools/*-vm-runner` 隔离更强。 |
| **当前最低规则** | 单个 **package** 不得依赖超过一个链 SDK 家族。 |
| **目标** | `pf-run-*` / `pf-backend-*` 各自拥有 lockfile（或独立 workspace），更接近 `tools/*-vm-runner`，而非单体 testkit workspace。 |

## Rust 不得拥有的部分（除非战略改口）

| 模块 | 原因 |
|---|---|
| `Contract.Source` / `contract_source` | 产品语言与证明起点 |
| Frontend canonicalize / materialize | 含义归一化；错了后面全错 |
| `IR.Core.Validate` 的语义规则源 | 须与形式化主张同一所有者 |
| 权威的 `IR.Core.Semantics` | Rust 可为差分测试镜像解释器；权威仍在 Lean |
| `ProofForgeFormal*` | 继续 Lean；钉 Core 或 contentHash |

Rust 最多是：Core 的只读消费者 + Plan/Render 实现者 + 执行观察者。

## 等价维度（dual-run）

**默认不要求** `.bin` 字节级相同（`solc` 版本、metadata 尾巴、路径嵌入等）。
声明并门禁：

1. **运行时观察** — return / storage / events / 可移植 error id
   （现有 testkit trace parity）。
2. **ABI / entrypoint 面** — 名称、selector 或原生编码、适用时的 mutability。
3. **制品元数据** — `targetId`、模块身份、primary/final 输出 kind、
   在文档化 hash 策略下的文件清单。
4. **可选文本** — 目标定义了稳定 normalizer 时的规范化 Yul/WAT 或 strip 后 bytecode。

**Content hash** 钉 Core export 包（和/或策略下的最终文件列表）。
**CanonicalEvidence**（span、诊断溯源）**不得**进入语义制品 hash —
与 [architecture](../../architecture.md) 一致。

Observation JSON 的版本与 Core export schema **独立**，
避免 runner 演进强迫 Core bump。

## 分阶段路线图

### Phase 0 — 巩固证据契约（现在可做）

目标：接缝 B 成为成文契约；不写新编译后端。

| 区域 | 工作 |
|---|---|
| Lean | 文档化并冻结 `proof-forge-artifact.json` / ArtifactBundle 诚实性规则中对消费者可见的字段 |
| Rust | testkit 只消费文档化字段；保持 harness 分包 |
| 门禁 | `just product` + 现有 differential/harness 绿 |
| 产出 | [Artifact Contract v1](2026-07-15-artifact-contract-v1.zh.md) |

Rust 挂点：仅制品目录。输出：运行证据，不是新的产品编译路径。

### Phase 1 — Core 导出（Lean 侧；Rust 只读）

目标：足够稳定的 experimental 导出；Rust 不替换编译。

| 区域 | 工作 |
|---|---|
| Lean | Validate + CapabilityPlan 后 `proof-forge export-core … -o build/export/…` |
| 内容 | core + capability-plan + contentHash；schema 标 **`core.v0` / experimental**，直到 cutover 与 HostOp 身份安定 |
| Rust 可选 | `pf-core-inspect` 做 schema 校验 / 摘要（零链 SDK） |
| 门禁 | 导出确定性；与 Validate 失败用例 fail-closed 对齐；仅子集产品（如 Counter + 一个 stateful） |
| 形式化 | contentHash 可作为 formal / 差分锚点 |

在 authoring cutover 与 IR 扩展边界仍每周改 HostOp / 公共路由时，
不要宣称 `core.v1` 稳定。

### Phase 2 — 单链 Rust 试点（cutover 稳定后）

目标：证明 Rust 后端可行，而不重写全三链。

| 选项 | 指导 |
|---|---|
| 试点目标 | Lean EVM 路径安静后优先 **EVM**（工具成熟，EVM-R* 更靠前）。不要用试点「顺便」做完 NEAR residual cutover。主三链中 Solana 最后动第一刀。 |
| 优先顺序 | 痛点在 CI/工具链时先 A0；仅当 plan 逻辑本身是瓶颈时再 A1 |
| Crate | `pf-backend-evm`（或 near），Cargo 依赖隔离 |
| 输入 | Phase 1 导出 + target id |
| 输出 | 与 Lean CLI 同布局 + 兼容 artifact JSON |
| 门禁 | Counter + 一个 stateful 产品，在声明维度上 dual-run |
| 回滚 | CLI 默认仍走 Lean；可选 `--backend rust` 或 dual-run 环境变量 |

### Phase 3 — 主三链 Rust 后端 + 策略

- 包：`pf-backend-evm` / `pf-backend-solana` / `pf-backend-near`，依赖隔离。
- 薄 `pf-lower` 按 target dispatch。
- `proof-forge build` 可配置：`lean` / `rust` / `dual`。
- catalog 子集 dual-run，fail-closed。
- 文档化信任边界：外部 `solc` / `wat2wasm` / assembler 仍为假设。

仅当 dual-run 绿满一个发布周期，**且**记录了可衡量的 CI/集成收益后，
才考虑默认切到 Rust。

### Phase 4 — 可选生产拆分

```text
作者写 Lean 源
  → lake/lean：Canonicalize + Validate + export Core +（CI）Formal
  → rust：buildFromCore → 制品
  → rust runners：执行证据
```

额外默认切换门槛：

1. 主三链 catalog 子集 dual-run 绿（不只 Counter）。
2. 文档化 wall-clock：export + Rust lower 优于 Lean 全路径，或其他明确集成收益。
3. `PROOF_FORGE_BACKEND=lean` 在带日期的 deprecation 决策前始终可用。
4. Formal job 仍只消费 Core hash。

## 所有权矩阵

| 区域 | Phase 0–1 | Phase 2–3 | Phase 4 |
|---|---|---|---|
| Contract / Product | Lean | Lean | Lean |
| Frontend | Lean | Lean | Lean |
| IR.Core Validate/Syntax | Lean | Lean + export | Lean 权威 + export |
| Compiler/CanonicalPipeline | Lean | Lean 到 export；其后可 fork | Lean 止于 export |
| Backend.Evm/Solana/WasmHost | Lean | 试点 dual-run / 可选 Rust | 生产可为 Rust |
| CLI 制品写出 | Lean | Lean 调 Rust 或 Rust 自写 | 多为 Rust |
| testkit / runners | Rust | Rust 加强 | Rust |
| ProofForgeFormal* | Lean | Lean 钉 Core hash | Lean |

## 目标态数据流

```text
Examples/Product/Foo.lean
        │
        v
[Lean] Authored / Intent materialize
        │
        v
[Lean] IR.Core.validate  ──fail──► 产品诊断
        │ ok
        v
[Lean] CapabilityPlan
        │
        ├──────────────────────────────┐
        v                              v
[Lean] export core + hash       [Lean] Formal?（可选 CI）
        │
        v
[Rust] pf-lower --target evm|solana|near   （Phase 2+）
        │
        ├─► pf-backend-*  （每链一 crate）
        │         │
        │         v
        │   artifact + metadata JSON
        v
[Rust] pf-run-*  （每链一 crate/lock）
        │
        v
     observation JSON / differential / CI
```

Phase 2 之前，生产路径仍全程 Lean 到 render；Rust 只在接缝 B。

## 成功标准

算成功：

1. 业务作者仍只写 Lean。
2. 多链 SDK 从不共享同一 package 依赖闭包（目标：backend/runner 分 lockfile）。
3. 任一 Rust 后端可关；Lean 全路径仍能出制品（Phase 3 前必须）。
4. Core export schema 有版本；破坏性变更有 dual-run 窗口。
5. 形式化钉 Core 或 contentHash，不钉 Rust 内部。
6. CanonicalEvidence 永不进入 contentHash / 语义制品 hash。
7. Observation 契约与 Core export 版本独立。

## 明确不做

- Rust 解析 Lean 源。
- 一个 `proof-forge-rs` 静态链接 near + solana + sui 等。
- 未 dual-run 就删 Lean Backend。
- 宣称「Rust 后端 = 已形式化验证的编译器」。
- 以 Rust Core 解释器为语义权威（镜像可以；权威仍是 Lean Validate / Semantics）。

## 优先级门闩（当前项目）

| 形势 | 建议 |
|---|---|
| PR #104 cutover / Core 单路径仍在动 | 仅 Phase 0；可选 experimental Phase 1 设计/尖刺，不进默认路径 |
| 主三链 Lean Backend 已稳；CI/性能成为瓶颈 | 开 Phase 2 单链试点（优先 EVM；适用时先 A0 再 A1） |
| 形式化是一等叙事 | 永远保留 Lean 对 Core 的所有权；Rust 是 lowering / 工程加速器 |

本设计不得挤占活跃合并优先级（D-056）或 authoring cutover residual。

## 实现落点（流程）

Phase 0+ 代码启动时建议：

1. 使用**专用分支**（文档跟进可用 `docs/lean-rust-boundary`，
   之后 `feat/artifact-contract-v1` / `feat/export-core-v0`）。
2. 优先**隔离 worktree / Orca workspace**，避免与 cutover 共享脏树。
3. 在 dual-run 门禁存在前，Phase 2+ crate 不进默认产品路径。
4. 在 cutover 落地且显式排定 Phase 0 实现任务前，
   **不要**在 AGENTS.md 把本程序标为 `in_progress`。

## 本文档验收

- [x] 原则与接缝已记录。
- [x] 分期顺序与 cutover 优先级门闩已记录。
- [x] A0/A1 子缝与等价维度已记录。
- [x] 伴生 artifact / core-export 草稿已链接。
- [ ] Phase 0 代码：testkit 只消费文档化制品字段（未来分支）。
- [ ] Phase 1 代码：experimental `export-core`（未来分支，cutover 后）。
