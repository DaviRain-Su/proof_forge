---
id: RESEARCH-023
title: MiniAmm 形式化阶梯（L0 工程门 → L1 业务保持 → L2 formal）
status: draft
owner: engineering
updated: 2026-08-07
normative: false
---

# MiniAmm 形式化阶梯

> **目的**：把「业务逻辑 + 形式化」拆成可交付层级，避免把  
> `InvariantTheoremV1`（全称 StateConforms）误写成「可达状态安全 / 步后保持」。  
> 与 [`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)、  
> ADR-0027、Examples `MiniAmm` / `MiniAmmProofSurface` 对齐。

**非 formal**：本文件不关闭 TASK-D2-07 / TST-SEM-002/003 / TST-PROOF-001。

---

## 1. 三层命题（必须分开命名）

| 层 | 名称 | 命题直觉 | 当前工程状态 |
|---|---|---|---|
| **L0** | 证明表面 / simple-closure | 存在可认证的 `invariant : true` + 同文件 theorem，CLI `proofStatus=certified` | **已接线**；产品例：`Examples/MiniAmmProofSurface.lean` |
| **L1** | 业务保持（目标） | `init` 满足 P，且每个合法 entry 的 reference `step` 后仍满足 P | **未闭合**；草图：`MiniAmmSafetySketchV1` |
| **L2** | formal / target refine | formal `step` corpus、target refine reference、hermetic | **pending** formal 轨道 |

### 1.1 当前产品 ABI 实际证的是什么

```lean
InvariantTheoremV1 program ordinal :=
  ordinal < program.invariants.size ∧
  ∀ state, StateConformsV1 program state →
    evalInvariantV1 program ordinal state = .returnedTrue
```

- 量化域 = **所有布局/类型合法** 的 logical state，**不是** 从 `init` 可达的状态。  
- 对「恒定乘积 / 无超发」等真安全性质，存在大量 StateConforms 反例 → **在 L0 形状下不应可证**。  
- L0 的 `invariant … : true` 诚实含义：**证明表面可认证**，不是「AMM 已安全」。

### 1.2 L1 目标形状（草图，非 shipped ABI）

对抽象状态 `MiniAmmState` 与谓词 `P`：

```text
InitOk s0 := P s0 ∧ s0 = initial
StepOk s s' e := step(s, e) = ok s' → (P s → P s')
Preserves P := InitOk initial ∧ ∀ s e s', StepOk s s' e
```

产品侧将来可把 `P` 的 **可执行投影** 写成 `invariant`（供 eval / 认证），  
但 **保持性** 必须是独立定理族，不能塞进现有全称 `InvariantTheoremV1`。

---

## 2. 业务谓词候选（L1 队列，按难度）

均针对 **vault-internal** `MiniAmm`（非 Assets 真转币）。

| ID | 谓词 P（直觉） | 依赖 | 难度 |
|---|---|---|---|
| P0 | `true`（L0 表面） | simple-closure 族 | 已交付 |
| P1 | empty pool：`totalSupply = 0 → reserve0 = reserve1 = 0` | step 后保持；init 真 | 中 |
| P2 | LP 与 totalSupply：份额之和 = totalSupply（cap-4 Map） | Map 语义 / 折叠 | 中高 |
| P3 | 无负向超发：remove 后 reserve 不反弹 | checked 算术 | 高 |
| P4 | 恒定乘积弱形式：swap 后 `r0' * r1' ≥ r0 * r1`（fee-free 整数） | UInt64 溢出模型 | 高 |
| P5 | Assets 路径：转币与 reserve 记账一致 | sync transfer + 原子性 | 更高（EVM/Solana only） |

**本切片只交付 P0 工程 + P1–P4 的 Prop 草图命名**，不声称已证。

---

## 3. 源文件分工

| 文件 | 角色 |
|---|---|
| `Examples/MiniAmm.lean` | **业务程序**（可 deploy）；**不**塞 nonempty invariant，以免 EVM/Solana materialize FC 破坏现网 pin |
| `Examples/MiniAmmProofSurface.lean` | **L0 证明表面**（simple-closure 族）；`check` → certified；build 到 8 target 仍 FC |
| `ProofForgeV2/Semantic/MiniAmmSafetySketchV1.lean` | L1 `MiniAmmState` / `P1`… / `Preserves` **接口草图**（无 sorry 冒充完成） |
| `Examples/MiniAmmAssets.lean` | 真资产；形式化更后（先 vault-internal L1） |

---

## 4. 产品 CLI 边界（诚实）

| 命令 | MiniAmm（无 inv） | MiniAmmProofSurface（有 inv） |
|---|---|---|
| `check` | ok，`noProof` 或无 proof 字段 | ok，`proofStatus=certified`（L0） |
| `build --target solana/evm` | deployable 路径保持 | **materializer FC**（nonempty inv；工程已知） |

不得把 L0 certified 写成「可部署安全 AMM」。

---

## 5. 执行路线图（2026-08-07 产品决策）

**优先级**：**先到业务层级 L1**；**D / L2（项目 formal 任务轨道）放到最后**。  
不并行用 formal TASK 挡 L1；L1 完成 ≠ formal 代签。

### 5.0 已完成

| 项 | 状态 |
|---|---|
| RESEARCH-023 分界 + L0/L1/L2 命名 | done |
| `MiniAmmProofSurface` + `check` certified | done（L0） |
| `MiniAmmSafetySketchV1` + `P1` init 半截 | done（接口） |
| MiniAmm 业务源无 inv（deploy 保持） | done |

### 5.1 阶段 L1-A — 可执行 abstract step（无 product wire）

**目标**：去掉 `opaque miniAmmStep`，换成 **与 MiniAmm 公式一致的 total 函数**。

| 交付 | 说明 |
|---|---|
| `miniAmmStep : MiniAmmState → MiniAmmEffect → Option MiniAmmState` | 成功 `some`，assert 失败 `none` |
| 与 `Tests.Semantic.MiniAmmVectorsV1` 对齐 | 同一组 oracle：first mint、swap0to1 100→181、remove 等 |
| 单元测试 | Lean 或现有 Vectors 扩展：step 前后数值钉 |

**不含**：Reference 机接线、InvariantTheorem、materializer。

**验收**：`PreservesP1` 可对 **该 abstract step** 陈述并开始证明（不必一次证完）。

### 5.2 阶段 L1-B — P1 empty-pool 完整保持

**目标**：`PreservesP1_emptyPool` 在 abstract step 上 **全证**。

| 交付 | 说明 |
|---|---|
| 各 effect 分案引理 | init / add / swap0/1 / remove 成功时 `P1 s → P1 s'` |
| 失败路径 | `step = none` 不要求后继（或显式 stutter 约定） |
| 测试钉 | 定理名 + suite 调用，禁止 sorry |

**业务含义**：零 LP 时不能留下非零 reserve（相对 **我们定义的 abstract 转移**）。

### 5.3 阶段 L1-C — 状态扩到 Map + P2

**目标**：LP Map 进 abstract 状态，证「份额与 totalSupply 一致」（cap-4 模型）。

| 交付 | 说明 |
|---|---|
| `MiniAmmState` 扩 `balances` | 有限 Map / list of (Principal, UInt64)，与 product cap-4 对齐 |
| `P2_lpSum` | sum(balances) = totalSupply（空槽不计入） |
| step 中 mint/burn LP | 与 MiniAmm match 分支一致 |
| `PreservesP2` | 全证或分案 + 测试 |

### 5.4 阶段 L1-D — 算术安全 P3 / 弱 P4

**目标**：在 **checked UInt64 模型** 下钉更强业务性质。

| 顺序 | 内容 |
|---|---|
| P3 | remove/swap 成功 ⇒ reserve 按公式增减；失败不写（或 none） |
| P4 | swap 成功后的乘积关系：用 **宽积**（Nat / UInt128）陈述，避免假证 UInt64 环绕 |

**验收**：关键 swap/remove 引理 + Vectors 回归；文档写清「整数 floor AMM，非 Uniswap 实数」。

### 5.5 阶段 L1-E — 与产品语义对齐（仍非 L2 formal）

**目标**：abstract step **不是第二套故事**。

| 交付 | 说明 |
|---|---|
| 对齐策略（二选一或组合） | (a) 从 Normalize 后的 MiniAmm Semantic 抽 step；(b) 证明 abstract ≡ Reference 在 MiniAmm 子集上 |
| 可选：可执行 inv 投影 | `P1`/`P2` 的 Bool 编码进 **独立** proof-only program 或库定理，**不**强迫 MiniAmm.lean 带 inv 破坏 deploy |
| 文档 | 「工程 L1 闭合」检查清单；明确 **未** 含 target refine |

**仍不做**：formal EV、Stage-0、改 accepted PRD formal 完成度。

### 5.6 阶段 L1-F — Assets（可选，L1 之后）

仅当 vault-internal L1 稳定后再开：

- abstract 增加「vault token 余额」或 effect 上的 transfer 事件；  
- 与 `MiniAmmAssets` pre-fund 诚实模型对齐；  
- EVM/Solana 运行时门已有，形式化是 **记账+转币一致性**，不是再造 runtime。

### 5.7 阶段 D / L2 — 项目 formal（最后）

**刻意延后**。包含且不限于：

- formal TASK-D2-07 / TST-SEM-002/003 / TST-PROOF-001  
- hermetic / Stage-0 / release qualification  
- target refinement（Anvil/Mollusk ↔ Reference formal）  
- 用 formal 完成度改写 accepted 范围  

**规则**：L1 工程证明 **可以** 写进 `MiniAmmSafetySketch` / 测试；**不得** 写入「formal TASK closed」。

### 5.8 建议切片粒度（一次一个）

```text
L1-A abstract step + Vectors 钉
  → L1-B PreservesP1
  → L1-C Map + P2
  → L1-D P3 / 弱 P4（宽积）
  → L1-E 与 Reference/Normalize 对齐声明
  → (可选) L1-F Assets
  → …很久以后… D/L2 formal 轨道
```

每切片：先失败测试/义务表 → 实现 → `lake` 相关 suite → 更新本文 §5 状态行。

### 5.9 明确不在 L1 范围

| 项 | 原因 |
|---|---|
| 给 `MiniAmm.lean` 加 nonempty inv 并要求 Solana/EVM build | materializer FC；破坏现网 pin |
| 用 `InvariantTheoremV1` 证 P1–P4 | 全称 StateConforms 形状不对 |
| NEAR 上同保证 Assets 形式化 | 跨合约 async；见 RESEARCH-022 |
| 「完全 formal 项目」 | = D/L2，最后做 |

---

## 6. 维护

- 升级「已证」层级时：改本表 §1/§5 状态词 + Examples 注释 + 测试钉。  
- 禁止用 `invariant foo : true` 命名暗示已证 foo 业务性质（L0 用中性名 `l0Surface`）。  
- L1 每闭合一条 P：在 §2 表加 **proved (abstract step)** 字样，并指向定理名。
