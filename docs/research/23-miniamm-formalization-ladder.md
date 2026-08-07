---
id: RESEARCH-023
title: 通用程序形式化栈（L0–L2）与首个实例 MiniAmm
status: draft
owner: engineering
updated: 2026-08-07
normative: false
---

# 通用程序形式化栈（L0–L2）与首个实例 MiniAmm

> **目的**：定义 ProofForge **平台级**「业务逻辑 + 形式化」能力分层，避免：  
> (1) 把 `InvariantTheoremV1` 误写成可达保持；  
> (2) 把试点写成 **仅服务某一个合约** 的一次性数学库。  
>
> **产品立场**：统一源语言与共享证明 **形状 / 门禁**；每个 `program` **实例化**  
> 自己的状态、谓词 P 与一步关系。MiniAmm 是 **第一个纵向切片**，不是唯一目标。  
>
> 对齐：ADR-0027、[`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)、  
> Examples `MiniAmm` / `MiniAmmProofSurface`、`MiniAmmSafetySketchV1`。

**非 formal**：本文件不关闭 TASK-D2-07 / TST-SEM-002/003 / TST-PROOF-001。

---

## 0. 通用 vs 实例（必读）

```text
┌──────────────────────────────────────────────────────┐
│  平台通用形式化栈                                       │
│  · 语法：invariant / proof / 同文件 theorem             │
│  · L0 门：certifyInlineProofV1 / simple-closure 族      │
│  · 共享 ABI：InvariantTheoremV1 / evalInvariantV1       │
│  · L1 形状（目标）：State / Effect / step / Preserves P │
│  · L2：formal TASK / refine / hermetic（最后）          │
└───────────────────────────┬──────────────────────────┘
                            │ 实例化（每 program 自己的 P 与 step）
         ┌──────────────────┼──────────────────┐
         ▼                  ▼                  ▼
    MiniAmm（首个）     第二实例（验收通用）   后续任意合约 …
```

| 层级 | 通用？ | 内容 |
|---|---|---|
| L0 语法与 CLI 门 | **是** | 任意符合族的 program 名/模块都可 certified |
| L0 simple-closure 形状 | **是** | `view Bool true` + `invariant : true` + generated helper |
| L1 **义务形状** | **是（目标）** | `Preserves P` = init(P) ∧ step 保持 P |
| L1 **P 与 step 内容** | **否（每程序）** | MiniAmm 的 empty-pool / swap 公式；Counter 的别的 P |
| L2 / 项目 formal | **是（平台轨道）** | 延后；不绑死某个 Example |

**验收通用性**：L1 形状稳定后，必须用 **第二个 program**（建议极简 Counter 类）  
复用同一 `Preserves` 挂载方式，证明栈不是 AMM 专用。

---

## 1. 三层命题（平台命名）

| 层 | 名称 | 命题直觉 | 当前工程状态 |
|---|---|---|---|
| **L0** | 证明表面 / simple-closure | 可认证的 `invariant : true` + 同文件 theorem | **已接线**；样例：`MiniAmmProofSurface`（任意程序可仿） |
| **L1** | 业务保持 | 对 **该程序** 的 P：`init` 真且 `step` 后保持 | **接口草图**；MiniAmm 为首个 instance |
| **L2** | 项目 formal | formal step corpus、target refine、hermetic/release | **最后**；与单合约 L1 分账 |

### 1.1 共享 L0 ABI（通用，不是 MiniAmm 专有）

```lean
InvariantTheoremV1 program ordinal :=
  ordinal < program.invariants.size ∧
  ∀ state, StateConformsV1 program state →
    evalInvariantV1 program ordinal state = .returnedTrue
```

- 量化域 = **布局/类型合法** 状态，**不是** 可达状态。  
- 真业务安全（守恒、无超发等）**不能** 靠「全称 StateConforms」硬证。  
- L0 `invariant … : true` 的诚实含义：**证明表面可认证**，不宣称业务安全。

### 1.2 共享 L1 形状（目标平台契约，草图）

对 **任意** 程序实例的抽象：

```text
State, Effect, initial : State
step : State → Effect → Option State
P : State → Prop

Preserves(P) :=
  P initial ∧
  ∀ s e s', step s e = some s' → P s → P s'
```

| 谁提供 | 什么 |
|---|---|
| **平台** | 上述形状、命名约定、与 Semantic/Reference 的对齐义务、测试模式 |
| **程序作者 / 实例库** | 具体 `State`、`Effect`、`step`、谓词 `P`、引理 |

产品侧将来可把 `P` 的可执行投影写成 `invariant`（eval / 认证）；  
**保持性** 始终是独立定理族，不塞进现有全称 `InvariantTheoremV1`。

MiniAmm 的 `MiniAmmState` / `MiniAmmEffect` / `P1_emptyPool` 只是 **该形状的一个填充**。

---

## 2. 首个实例：MiniAmm 谓词队列（非通用清单）

下列 P **仅** 针对 vault-internal `Examples/MiniAmm.lean` 试点。  
其他合约应有自己的 Pn 表，挂同一 L1 形状。

| ID | 谓词 P（直觉） | 依赖 | 难度 | 状态 |
|---|---|---|---|---|
| P0 | `true`（L0 表面） | simple-closure | — | **done**（`MiniAmmProofSurface`） |
| P1 | empty pool：`totalSupply=0 → reserves=0` | abstract step | 中 | init 半截 done；保持 pending |
| P2 | LP 份额和 = totalSupply（cap-4） | Map 模型 | 中高 | 草图 |
| P3 | remove/swap 成功后的 reserve 更新 | checked 算术 | 高 | 草图 |
| P4 | swap 后乘积弱形式（宽积） | Nat/UInt128 模型 | 高 | 草图 |
| P5 | Assets：转币与记账一致 | sync transfer | 更高 | 后置 |

---

## 3. 源文件分工（平台 + 实例）

### 3.1 平台（跨合约复用）

| 区域 | 角色 |
|---|---|
| 语言 / Loader / inventory | `invariant` / `proof` 通用 |
| `certifyInlineProofV1` + simple-closure 族 | L0 通用门 |
| `InvariantABI` | 共享定理命题 |
| （目标）通用 L1 挂载模块名/约定 | 如将来的 `ProgramSafetySpec` 形状；先由 MiniAmm sketch 试错 |

### 3.2 实例：MiniAmm 试点

| 文件 | 角色 |
|---|---|
| `Examples/MiniAmm.lean` | **业务程序**（可 deploy）；无 nonempty inv |
| `Examples/MiniAmmProofSurface.lean` | **L0 样例**（simple-closure）；可被其他程序名复制 |
| `ProofForgeV2/Semantic/MiniAmmSafetySketchV1.lean` | **MiniAmm instance** 的 L1 State/P/step 草图 |
| `Examples/MiniAmmAssets.lean` | 真资产实例；L1-F 之后 |

### 3.3 第二实例（通用性验收，计划）

在 L1 形状（step + Preserves）对 MiniAmm 跑通 **P1 级** 后：

- 选极简 program（如 Counter：`count` 非递减或 `count` 在 checked add 后仍 well-formed）；  
- **不复制** MiniAmm 谓词，只复用 **同一 Preserves 模式**；  
- 文档勾选：「L1 挂载已证明非 AMM 专用」。

---

## 4. 产品 CLI 边界（通用）

| 命令 | 无 nonempty inv 的业务 program | 带 nonempty inv 的 proof 表面 |
|---|---|---|
| `check` | ok（`noProof` 或无 proof 字段） | ok 时可 `proofStatus=certified`（L0 族） |
| `build` 多数 materializer | deploy 路径 | **FC**（nonempty inv；工程已知） |

不得把 L0 certified 写成「可部署且业务已证安全」。

---

## 5. 执行路线图

**优先级**：**先平台 L1 形状 + 业务实例证明**；**D/L2 项目 formal 最后**。  
**MiniAmm** = 纵向打穿；**第二 program** = 横向验收通用。

### 5.0 已完成

| 项 | 范围 |
|---|---|
| L0/L1/L2 分界 + 本通用架构叙述 | 平台 |
| simple-closure 产品门 + `MiniAmmProofSurface` | 平台 L0 + 样例 |
| `MiniAmmSafetySketchV1` + P1 init | **MiniAmm 实例** 接口 |
| MiniAmm 业务源无 inv | 实例 deploy 纪律 |

### 5.1 L1-A — 可执行 instance step（MiniAmm 先）

| 交付 | 说明 |
|---|---|
| 定义 `miniAmmStep`（去掉 opaque） | 与 MiniAmm 公式 / Vectors 一致 |
| 数值钉 | `MiniAmmVectorsV1` 同源 oracle |
| **提炼** | 文档化「instance step 应满足的接口清单」，供第二 program 照抄 |

### 5.2 L1-B — MiniAmm P1 完整保持

`Preserves P1` 在 abstract step 上全证；模式可复述为任意 P。

### 5.3 L1-C — MiniAmm Map + P2

实例加深；仍不把 Map 模型绑死进平台 ABI。

### 5.4 L1-D — MiniAmm P3 / 弱 P4

宽积模型；平台侧只要求「算术模型可陈述」，不规定唯一 P。

### 5.5 L1-E — instance step ≡ 产品语义（工程对齐）

| 交付 | 说明 |
|---|---|
| MiniAmm abstract ≡ Normalize/Reference 子集 | 避免第二套故事 |
| **通用义务** | 每个 instance 必须声明对齐策略（抽取或等价证明） |

### 5.6 L1-G — 第二实例（通用性门）

| 交付 | 说明 |
|---|---|
| 非 AMM program + 自有 P + step | 复用 Preserves 形状 |
| 短文档 + 测试 | 「同一挂载，不同业务」 |

（编号 L1-G 插在 Assets 前，强制横向验收。）

### 5.7 L1-F — Assets 实例（可选）

`MiniAmmAssets` 或等价：记账 + sync transfer 一致性；仍是 **实例**。

### 5.8 D / L2 — 项目 formal（最后）

- formal TASK-D2-07 / TST-SEM / TST-PROOF  
- hermetic / Stage-0 / release  
- target refine Reference  

**不得** 用 MiniAmm L1 或 L0 certified 勾 formal 完成。

### 5.9 切片顺序

```text
L1-A MiniAmm step + 接口清单
  → L1-B MiniAmm PreservesP1
  → L1-G 第二 program 复用 Preserves 形状   ← 尽早证明通用
  → L1-C / L1-D 加深 MiniAmm 业务
  → L1-E 语义对齐
  → (可选) L1-F Assets
  → …最后… D/L2
```

> **说明**：L1-G 提前到 P2/P4 之前，避免「做完所有 AMM 数学才发现栈不可复用」。

### 5.10 不在当前范围

| 项 | 原因 |
|---|---|
| 业务 program 强制带 inv 且 EVM/Solana build | materializer FC |
| 用 `InvariantTheoremV1` 证任意业务 P | 形状不对 |
| 只维护 MiniAmm、永不做第二实例 | 违背通用产品 |
| 现在开全项目 formal D | 产品决策：最后做 |

---

## 6. 维护

- 平台形状变更：更新 §0–§1；实例进度：更新 §2 / §5。  
- 新 program 形式化：新增「实例」小节或独立 instance 笔记，**链回** 本文件 §0。  
- L0 中性名（如 `l0Surface`），禁止用 `true` 不变式冒充业务安全名。  
- L1 每证一条实例 P：标注 **proved (abstract step / instance X)** + 定理名。
