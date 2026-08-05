---
id: TARGET-QUINT
title: Quint executable-specification target dossier
status: draft
owner: architecture
updated: 2026-08-04
normative: true
---

# Target Dossier：Quint（executable specification / model surface）

状态：`draft`
Target ID：`quint`
工程 MVP：**Q0 materializer 已接线**（ADR-0026；source-only、zero-tool finalize）。
**Engineering only**——**非** accepted PRD Phase 1 四目标范围；accepted scope
reconciliation 见 **`DOC-ADR-SCOPE`**。

## 0. 工程状态（2026-08-03 / A6 2026-08-04）

**设计冻结（Q0，见 [ADR-0026](../adr/0026-quint-target-integration.md)）**：

| 字段 | 冻结值 |
|---|---|
| `TargetId` | `quint` |
| `CodegenProfileId` | `quint-source-u64-model-v1` |
| `ArtifactEncoding` | `quintSource` |
| `AcceptanceProfileRef` | `research.quint.v1` |
| maturity 标签 | `source-only` |
| 制品 | `.qnt` 源码；**不可部署**（`deployable=false`） |
| product finalization | **zero-tool**（不调用 Quint CLI / Apalache / TLC / Java） |

**六轴（wire）**：

| 轴 | 值 |
|---|---|
| `executionHost` | `quint-model` |
| `commit` | `relation-external` |
| `state` | `external-public-pre-post` |
| `call` | `no-native-call` |
| `proof` | `no-proof` |
| `settlement` | `no-settlement` |

**Resolver（honest 6-key after ADR-0029 Phase A）**：
`effect.synchronous-call` / `extension.pf-assets` /
`failure.atomic-rollback` / `state.persistent` / `value.bool` /
`value.checked-arithmetic`。event / async-workflow 及其余 S2 键 **fail closed**。
`extension.pf-assets` 仅本 profile 精确 advertise（exact triple 与
[`pf-assets-extension-v1.json`](../specs/pf-assets-extension-v1.json) 对齐）；其它
target 对使用该 extension 的程序 **PF-REQ-UNSUPPORTED**。

**Q0 合法 Semantic 子集**：anonymous `UInt64`/`Bool`/`Unit`/`Principal`（Principal 仅作
pf.assets identity 参数，不可算术）；public `UInt64`
state/params；target Plan 合法面为 public `Unit`/`UInt64`/`Bool` result（当前 source Normalize
尚不物化 bare-Unit entry return，产品可达 Unit 主要是 initializer）；zero-parameter public-Bool、只读
Q0 invariant；view 仅 check-free 只读表达式；至少一个 entry，且 **single-block CFG**（无 loop /
branch / switch / block params）；op 面限 literal、state load+store、checked `UInt64` 算术、比较、Bool
and/or/not、`pureCall`、bare assert、zero-payload declared revert（failure code=`256+ErrorId`）、
以及 Phase A 准入的 void `ExternalCall` vault 子集（见下）。
**完整 `UInt64`
输入域**，禁止小域近似。其它形状一律 fail closed。

**失败语义**：失败 = **显式 outcome + 业务状态 stutter**；禁止用 blocked action
掩盖业务失败。

### ADR-0029 Phase A：`pf.assets` vault 建模（工程，2026-08-04）

| 项 | 工程事实 |
|---|---|
| 准入 QN | `pf.assets.native.deposit(amount)`、`pf.assets.native.transfer(dst, amount)` |
| 拒绝 | `*.transferAsync`、`token.*`、非 catalog QN、无 `requires extension pf.assets` 声明 |
| 模型 | target-owned `pf_vault_native`；nondet external outcome；success 时 credit/debit；failure 与 vault 溢出/不足均 first-failure + 业务/vault stutter |
| 产品 demo | [`Examples/TipJar.lean`](../../Examples/TipJar.lean) → CLI `build --target quint` → `TipJar.qnt` + `proof-forge.output.v1`；`inspect` exact disk closure（`Tests.Product.TipJarQuintV1`） |
| 明确边界 | **非** formal TASK/TST、**非** 主网、**仅** 模型层证据；非 deployable；Reference 仍为 opaque void（无 vault 解释器） |

**明确未声称**：ITF 导出、MBT、`quint verify`、Apalache/TLC pin、Tool Lock、
Reference↔Quint formal 差分、formal D3/D4 完成、accepted PRD 扩面、跨 target 资产互通完成。

> Lean registry、resolver、`Targets/Quint/**` materializer 与聚合 dispatch 已落地；
> 当前 registry 为 **12 = 9 implemented + 3 design-only**、**9 materializers**。
> 这只证明 `.qnt` source materialization 与工程 output closure，不证明 verify/ITF/MBT。

## 1. 身份与来源

Quint 是 Informal Systems 的**可执行规格语言**：工程师编写可运行的规格，经模拟器与
模型检查（含 Apalache 后端）发现 subtle bug；可导出 ITF 轨迹并接入 model-based
testing。它描述的是**模型层状态机 / 关系**，不是链上 bytecode host。

- 项目入口：[quint.sh](https://quint.sh/)
- 文档入口：[quint.sh/docs](https://quint.sh/docs)（model checkers、simulator、MBT 等）

研究期引用为 plain link；**未** 在本切片登记 `SRC-*` / `CLM-*`。未 pin 工具版本前，
不得把外部 CLI 行为写成 product acceptance。

**Family 视图**：executable specification / model surface。不得塞进 EVM / SVM /
Wasm host / TVM Stack-Account / ZK circuit / zkVM / ZK application chain，也不得共享
其 Plan/IR 类型。

## 2. 执行、状态、调用、失败与资源

### 执行

- 执行宿主是 **Quint 模型**（`executionHost=quint-model`），不是 EVM/SVM/Wasm/TVM。
- Q0 只物化 **single-block** 可调用体为模型动作 / 纯函数片段；不降低 multi-block
  CFG、bounded for 或 switch。
- `commit=relation-external`：模型关系与外部观测/提交叙述分离；本 profile **不**
  产链上 commit 证明。

### 状态

- `state=external-public-pre-post`：逻辑状态是 **public** 的 pre/post 状态关系
  （Q0：public `UInt64` 槽位），不是私有 witness 树或 cell dict。
- 状态读写映射为模型变量的 load/store；store 失败路径必须保持 **业务 stutter** 且
  暴露显式失败 outcome（见下）。

### 调用

- `call=no-native-call`：本 profile **无** 原生跨合约 / 跨模型 call 面（轴值不变）。
- resolver 现 advertise `effect.synchronous-call` **仅** 为 ADR-0029 `pf.assets` vault
  子集服务；generic 非 catalog QN 可过 resolve 但在 Plan **fail closed**。
- `schedule` / async 仍 **fail closed**。
- Phase A 准入：`pf.assets.native.deposit` / `pf.assets.native.transfer` → vault 建模；
  async/token FC（见 §0）。
- `pureCall`（纯本地 pureFn）在 Q0 允许，不得引入 effectful 外部 callee。

### 失败

- 映射 `failure.atomic-rollback`：失败不得提交业务状态更新。
- **显式 outcome + 业务状态 stutter** 为唯一合法失败编码。
- **禁止** 将 assert/算术溢出/业务拒绝编码为“动作被 block、轨迹无失败标记”——那会
  使验收无法区分“未启用”与“执行失败并回滚”。
- bare assert、checked 算术与 zero-payload declared revert 均须可观察为失败类 outcome；
  revert 保留 canonical ErrorId。具体 Quint 语法由 materializer 冻结，但不得削弱可区分性。

### 资源

- Q0 **不** 建模 gas、cell、proof constraint 或链上 fee。
- **完整 `UInt64` 域**进入模型输入；不得为“加快 model check”而把域缩成 `0..N`
  却仍声称 Semantic `UInt64` 语义。任何有界检查 profile 必须是**新的**
  CodegenProfileId，不得静默替换本 profile。

## 3. Portable fragment 与扩展

### Q0 portable 映射

| Portable / Semantic 面 | Quint Q0 诚实映射 |
|---|---|
| public `UInt64` state | 模型状态变量；pre/post 关系 |
| public `UInt64` params | 动作参数；**全域** `0..2^64-1` |
| public `Unit`/`UInt64`/`Bool` result | 显式返回 / outcome 字段 |
| checked `UInt64` 算术 | 模型内 checked 算子；溢出 → 失败 outcome + stutter |
| 比较 / Bool and-or-not | 纯布尔表达式 |
| `pureCall` | 纯函数调用（无 state/effect） |
| bare assert | 失败 → 显式 outcome + stutter（**非** 静默 block） |
| zero-payload declared revert | `failure=256+ErrorId` + stutter；nonzero payload FC |
| `failure.atomic-rollback` | 失败路径不提交业务 store |
| `pf.assets.native.deposit` / `transfer`（exact extension） | vault `pf_vault_native` + nondet external outcome；async/token/无声明 FC |
| generic external `call` / `schedule` | Plan fail closed（非 vault catalog） |

### 必须 fail closed / 非 Q0

- multi-width `UInt`/`Int`、`Field`、`Principal`、`String`、Bytes/Array/Map/Option
- named Struct/Enum、nonempty constants、非 zero-param public-Bool/read-only Q0 invariants
- checked/fallible view（Q0 不发明 view outcome ABI）
- if / match / for / multi-block / branch / switch / block params
- `emit` / nonzero-payload `revert` / `call` / `schedule` / ContextRead / Commit
- 小域近似、blocked-action 失败掩盖
- ITF / MBT / verify / Apalache 作为 **本 profile** 产品步骤

### 扩展（后续 profile，不得回写 Q0）

独立 CodegenProfile 候选（须 exact 新 id + capability 行）：ITF 轨迹导出、MBT 夹具、
`quint verify` / Apalache pin + Tool Lock、多块 CFG、更宽类型、受控有界域实验（若
语义契约显式改写）。每项 schema 必须版本化；**不得** 在 `quint-source-u64-model-v1`
  下 best-effort 打开。

## 4. `QuintPlan` schema（设计冻结）

```text
QuintPlan {
  programName,
  sourceHash,
  semanticHash,
  states,                  -- source-order public UInt64 slots
  initializer?,            -- params + final stores；fallible init FC
  entries,                 -- dense action index + params/result/checks/final stores + terminalRevert
  views,                   -- pure check-free read-only result expressions
  invariants               -- read-only Bool expression + success checks
}
```

Plan expressions是 target-owned `UInt64`/`Bool` tree；checks 带 closed failure kind
（overflow/underflow/div-zero/assert/identity-preserving revert）。`terminalRevert` 使 non-Unit /
no-result 只有 canonical unconditional-revert 形态；fallible checks≤128，单 expression
fully-expanded rendered 上限 16384 nodes（含 div/mod totalization duplication），另有 Plan-wide
budget。full-UInt64 domain 与 explicit-outcome/business-state-stutter 是 emitter
固定策略，不由 caller 覆盖。

约束：

- `QuintPlan` **不得** 复用 `EvmPlan` / `SolanaPlan` / `NearPlan` / `NoirPlan` /
  `AleoPlan` / `PsyPlan` / `CosmWasmPlan` / `TonPlan`。
- renderer **不得** 回读 `SemanticProgram` 重推业务逻辑；Plan 必须自包含状态槽、
  动作与失败策略。
- `validatePlan`/plan digest 在编码前重验 expression type/use-site、parameter/state references、
  rendered-size/depth budgets 与 terminal-revert iff；Plan 不得编码 deploy、proof 或 settlement 步骤。

## 5. Target IR 与制品

设计路径：

```text
QuintPlan → QuintIR → .qnt 源码
  → Finalize = zero-tool 包装（manifest/evidence only）
  → deployable=false
```

- 产品 emitter 输出 **`.qnt`**；不把手写 TLA+ 或 Apalache 配置当作默认 IR。
- Quint module 与全部 generated identifier 使用 target-owned namespace（module=`PFModel_<program>`），
  避免 source 名与 Quint keyword/builtin 碰撞；artifact path 仍为 `<program>.qnt`。
- 制品：`*.qnt` + 工程 manifest/evidence 侧车；**无** bytecode / BoC / Wasm / proof。
- 不得把“生成了 `.qnt`”写成 verify 通过、模型检查完成或 formal 证据。

## 6. 工具链

| 工具 | Q0 工程状态 |
|---|---|
| Quint CLI | **不** 进入 product finalization；后续 profile 再决策 pin |
| Apalache | **不** 调用；不进本 profile Tool Lock |
| TLC | **不** 调用 |
| Java 运行时 | **不** 作为 finalize 依赖拉起 |
| ITF / MBT 夹具 | 后续 profile；本 dossier 不声称恢复 |

纪律：代码中的 `quint-0.32-compatible-source` 仅为 emitter syntax compatibility note，
不是 Tool Lock identity。missing tool **不得** 被 product 路径“可选调用”；Q0 finalize 成功条件
与主机是否安装 Quint **无关**。若未来 profile 引入 pin，必须走 Tool Lock / content-addressed
供给，并独立 acceptance id。

## 7. 部署流程

Q0 **无部署**。

允许的工程验收（当前仍非 formal）：

1. materialize 产出 `.qnt` + exact disk closure / inspect——结构门。
2. （可选、非 product finalize）主机手跑 Quint parse/typecheck——**不得** 写成
   registry maturity 升格或 Stage-0。
3. ITF / verify / MBT——**禁止** 在本 profile 声称。

禁止把“源码生成成功”写成部署、主网、证明或 formal Reference 差分完成。

## 8. 安全

重点（进入未来验证计划时必须覆盖）：

- **失败不可区分性**：blocked action vs 显式失败 + stutter 被混淆时，模型“安全”
  可能掩盖业务 rollback 义务。
- **域缩水**：静默 `UInt64 → 0..N` 导致假阴性 / 假阳性 model check。
- **pureCall 纯度**：误把 state/effect 塞进 pure 定义会破坏 pre/post 关系。
- **关系外提交**（`commit=relation-external`）：不得假装模型执行即链上 settlement。
- **源码注入 / 标识符**：emitter 必须保持 identifier 与字符串字面量的可预测转义，
  避免生成歧义 `.qnt`。
- **侧车完整性**：source-only 仍须 exact path/size/hash 闭包；禁止 path-only manifest。

## 9. 验证阶梯

```text
Q0 Plan/IR/.qnt 结构门 + inspect closure     ✅ engineering
  → （非 product）Quint 0.32 typecheck/run     ⚠ host-only observation，非 locked gate
  → ITF 轨迹 / MBT                             ❌ 后续 profile
  → Apalache / quint verify pin                ❌ 后续 profile
  → formal Reference 差分                      ❌ 不在本 dossier
```

每一级独立 fail closed；上级通过不蕴含下级。零工具 finalize **不是** formal 或
hermetic Stage-0。

## 10. 不支持、风险与成熟度退出

### 当前明确不支持 / fail closed

- 本 profile 下一切非 Q0 类型/CFG/effect。
- `effect.event` / `effect.synchronous-call` / `effect.asynchronous-workflow`。
- product finalize 调用 Quint/Apalache/TLC/Java。
- 小域近似、blocked-action 失败掩盖、deployable 伪声明。
- formal D3/D4、Stage-0、accepted PRD Phase 1 扩面。

### ADR-0030 E2-Quint：env-read native balanceOfSelf（2026-08-06）

payload v1.1.0 新 QN 的 per-target 绑定：`pf.assets.native.balanceOfSelf()` →
模型 `vaultNative` 读（与 ADR-0029 deposit/transfer 同一 Int vault，read-only、
view/entry-callable、effect-free、结果 UInt64）；`usesVaultNative` 现覆盖
env-read-only 程序（原仅 nonempty assetOps），ValidatePlan 以「assetOps 或
vaultNative 表达式」exact join 防漂移。`pf.assets.token.balanceOfSelf(mint)`
**永久 FC**：mint-keyed token vault Map + Principal identity 超出 Q0 Int vault
模型（诚实边界非债务）；pureFn/initializer/invariant 禁 envRead（host/模型
vault 读非纯）。Lean 钉测 `Tests.Materialization.QuintSourceV1` 扩展（view 值
`== .vaultNative`、env-read-only 程序 `usesVaultNative=true` 且发射
`var pf_vault_native`、token FC 诊断引用 Q0/Map）。无 Quint/Apalache/TLC 运行
（维持 source-only ceiling）。**非** formal。

### 风险

- 将“可执行规格”误读为“第 5 个 Phase 1 链上 target”或自动扩 accepted scope。
- 为跑通 Apalache 而在 emitter 中偷改算术域或失败语义。
- registry 登记与 materializer leaf 不同步导致 CLI 假绿或假红叙事不清。

### 成熟度边界

- 本 dossier ceiling：**research** 静态上限不因文档冻结而升格。
- registry maturity 标签：**source-only**；leaf 已落地，但在 verify/ITF profile 与
  独立 evaluator 之前 **不得** 写成 runtime/proof/settlement 完成。
- formal maturity / SupportClaim / BuildIdentity 路径不在本用户文档切片。
