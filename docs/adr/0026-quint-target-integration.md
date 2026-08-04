---
id: ADR-0026
title: Quint（可执行规格 / model surface）capability-gated target 集成
status: proposed
owner: architecture
updated: 2026-08-03
normative: true
---

# ADR-0026：Quint（可执行规格 / model surface）capability-gated target 集成

## 状态

proposed

## 背景

[Quint](https://quint.sh/)（Informal Systems）是面向可靠系统的**可执行规格语言**：规格可
模拟、可模型检查，后端可经 Apalache / 相关工具链做符号检查，并支持 ITF 轨迹与
model-based testing（MBT）工作流。它不是合约 VM、不是 Wasm host、也不是 ZK circuit /
zkVM / ZK 应用链；与现有 EVM/SVM/Wasm/TVM/ZK family **无** 共享 Plan/IR 的合理空间。

接入前 ProofForge 有八个 capability-gated materializer
（EVM/Solana/NEAR/Noir/Aleo/Psy/CosmWasm/TON）；Aleo/Psy/Noir 已提供 source-only / compile-only
先例。本 ADR 冻结 Quint 为第九个 materializer，并采用更窄的 **zero-tool source-only** finalize。
把 DSL 的 retained `SemanticProgramV1`
子集物化为 `.qnt` 模型源码，有助于在**不部署、不进链**的前提下做状态转移的显式
pre/post 检查；但产品边界必须诚实：

- 不得把 `.qnt` 写成可部署制品或 formal D3/D4 完成；
- 不得在 product finalization 中调用 Quint CLI / Apalache / TLC / Java；
- 不得用小域近似替代完整 `UInt64` 输入域；
- 不得用 blocked action 掩盖业务失败（失败须为显式 outcome + 业务状态 stutter）。

本 ADR 冻结 `quint` 为 **第 9 个 capability-gated engineering target**：registry
为 12 targets = 9 implemented + 3 design-only，架构形态对齐 Aleo（ADR-0023）与 TON
（ADR-0024）的 capability-only Plan 纪律。当前工程 leaf 已接入 registry/resolver、
target-owned Plan/IR/`.qnt` emitter、plan digest 与 zero-tool finalization；禁止任何
静默降级。

## 决策

1. **身份与归类**：`TargetId.quint`（小写、无分隔符）。执行语义归类为 **executable
   specification / model surface**（可执行规格与模型检查表面），**不**并入 EVM /
   SVM / Wasm host / TVM / ZK circuit / zkVM / ZK application chain family，**不得**
   复用任一既有 `*Plan` / `*IR` 类型（ADR-0006/0007/0008 同纪律）。
2. **Registry（工程意图冻结）**：`TargetRegistryV1` 冻结 seed 新增 `quint` 后计数为
   **12 targets = 9 implemented + 3 design-only**；九个 materializer 含 `quint`。
   六轴 closed enum 取值（wire 标签；Lean 构造子名在实现切片按既有 camelCase 惯例落地）
   精确为：
   - `executionHost` = `quint-model`
   - `commit` = `relation-external`
   - `state` = `external-public-pre-post`
   - `call` = `no-native-call`
   - `proof` = `no-proof`
   - `settlement` = `no-settlement`
   `CodegenProfileId` wire = `quint-source-u64-model-v1`；
   `ArtifactEncoding` = `quintSource`；
   `AcceptanceProfileRef` = `research.quint.v1`；
   registry maturity 标签 = **`source-only`**（不可部署；无 prove/settle）。
3. **Capability（honest 4-key 子集）**：resolver **仅** 承认
   `failure.atomic-rollback`、`state.persistent`、`value.bool`、
   `value.checked-arithmetic`。显式拒绝（非穷举）：`effect.event`、
   `effect.synchronous-call`、`effect.asynchronous-workflow`、以及本 4-key 外一切
   S2 键。跨模型/外部调用在本 profile **无原生 call 面**（`call=no-native-call`）；
   不得把 schedule/call 伪装成 model action 并静默忽略结果（B-CALL-SEM 同级诚实标准）。
4. **制品与 finalization**：engineering materializer 产出 **`.qnt` 源码**（及
   manifest/evidence 侧车）；`deployable=false`。**Product finalization 为零工具**：
   不调用 Quint CLI、不调用 Apalache、不调用 TLC、不拉起 Java 运行时、不写入 Tool Lock
   条目作为本 profile 的 finalize 依赖。ITF 导出、MBT、`quint verify`、Apalache pin /
   Tool Lock 均属 **后续独立 CodegenProfile**，**不得**在 Q0 或本 ADR 中声称已恢复或
   已验收。
5. **Q0 语言/CFG 子集（唯一本 profile 合法面）**：
   - 类型：仅 **anonymous** `UInt64` / `Bool` / `Unit`；
   - 状态与参数：仅 **public** `UInt64` state / params；
   - 结果：target Plan 合法面仅 **public** `Unit` / `UInt64` / `Bool`；当前 source Normalize
     尚不物化 bare-Unit entry return，因此产品可达 Unit 主要是 initializer，禁止据此声称完整 Unit ABI；
   - invariant：仅 zero-parameter public-Bool、single-block、只读 state / pureCall；
     发射为不依赖 instrumentation 的 Quint `val`；
   - view：只读且 **check-free**；带 assert/revert 或可能失败的 checked arithmetic view
     在本 profile fail closed（本 Q0 不发明 view outcome ABI）；
   - CFG：至少一个 entry，且 **single-block** only——无 loops、无 branch、无 switch、无 block params；
   - 指令/op 面：literal、state load + store、checked `UInt64` 算术、比较、
     Bool `and` / `or` / `not`、`pureCall`、bare assert、zero-payload declared revert；
   - **完整 `UInt64` 输入域**（`0 .. 2^64-1`）；禁止小域近似、禁止静默截断为
     模型友好子集；
   - 上述以外一律 **fail closed**（含 multi-width、Int、Field、Principal、String、
     聚合、named 类型、if/match/for、emit/nonzero revert payload、call/schedule、ContextRead/
     Commit、nonempty constants 与非上述 Q0 invariant 形状等）；zero-payload revert 以
     `256 + canonical ErrorId` 保留声明 identity；
   - resource gate：每 callable expanded op≤4096、fallible checks≤128、pureCall depth≤64、单
     fully-expanded **rendered** expression≤16384 nodes（含 div/mod guard 的 denominator duplication），
     并有 Plan-wide node budget；禁止线性 SSA 制造指数输出或超深 failure cascade。
6. **失败语义（不可协商）**：失败调用 / 失败转移必须编码为 **显式 outcome**（例如
   可观察的 result / error 指示）并伴随 **业务状态 stutter**（业务 state 不前进）。
   **禁止** 用 Quint / TLA 风格的 blocked action（使动作在前提不满足时“不可启用”）
   掩盖业务失败，从而让轨迹看起来像“什么都没发生且无失败”。原子回滚语义落在
   `failure.atomic-rollback` 的 capability 诚实映射上，不得降级为 best-effort stutter。
7. **不做（本 ADR 明确排除）**：
   - 把 Quint 写入 accepted PRD Phase 1 四目标范围（仍为 `evm`/`solana`/`near`/`noir`）；
   - formal TASK/TST、formal D3 registry root / SupportClaim / BuildIdentity、formal
     D4 lowering 或 Reference↔Quint 差分因本 ADR **完成**；
   - product 路径上的 verify / ITF / MBT / Apalache / TLC / Java；
   - 与其它 target 共享 Plan/IR，或第二套 Semantic 解释路径；
   - 小域模型、blocked-action 失败掩盖、deployable 伪声明。

## 理由

- Quint 提供与链上 host **正交**的可执行 pre/post 模型面，适合在 source-only 层面对
  public-UInt64 状态机做显式检查，而不强迫引入部署或 proof 工具链。
- 零工具 finalize 与 Aleo/Psy source-only 先例一致，避免把未 pin 的 JVM/Apalache 闭包
  偷渡进 product finalization 与 Tool Lock。
- Q0 收成 single-block + 4-key capability，是唯一能在不重开 multi-block CFG /
  effect 矩阵的前提下保持 fail-closed 与完整 `UInt64` 域诚实的最小纵切面。
- 显式 outcome + stutter 比 blocked action 更贴近 ProofForge 的 atomic-rollback /
  可观察失败纪律，避免“模型通过但业务失败不可区分”。

## 影响

- 工程 registry 意图：成员 **11 → 12**；implemented **8 → 9**；materializer **8 → 9**；
  design-only 仍为 `soroban` / `icp` / `openvm`（3）。相关 seed digest、descriptor
  join、resolver 静态行、CLI list-targets 须在实现切片同步钉死。
- `ArtifactEncoding` 新增 `quintSource`；`CodegenProfileId` 新增
  `quint-source-u64-model-v1`；六轴新增/复用上述 wire 标签对应的 closed 构造子。
- 文档：[`docs/targets/12-quint.md`](../targets/12-quint.md) 为 sole dossier；
  TARGET-INDEX 与 ADR 索引登记本决定。
- **不**修改 accepted PRD Phase 1 文案；**不**闭合 `DOC-ADR-SCOPE`；**不**新增
  formal `TASK-*` / `TST-*`；formal D3/D4 与 release-qualification 轴不因本 ADR 升格。
- engineering leaf 已在现有 authority 原位接线：registry/descriptor/resolver、
  `Registry.materializeResult`/planDigest/finalize dispatch 与 exact output closure 同源；
  unsupported semantic shape 必须返回 target-local fail-closed 错误，禁止“生成空目录”或
  降级到其它 target。

## 备选

- 保持 design-only / 仅研究链接（拒绝：Q0 子集与 4-key capability 已可决策冻结，值得
  engineering leaf，但仍非 accepted Phase 1）。
- Finalize 内嵌 `quint` CLI / Apalache（拒绝：JVM 闭包、版本漂移与 Tool Lock 成本超出
  source-only Q0；留给后续 profile）。
- 小域 `UInt` 近似以便 model check（拒绝：与 Semantic `UInt64` 与 checked-arithmetic
  契约不一致，属静默改语义）。
- 用 blocked action 表示 assert/失败（拒绝：与 atomic-rollback 可观察失败不可区分）。
