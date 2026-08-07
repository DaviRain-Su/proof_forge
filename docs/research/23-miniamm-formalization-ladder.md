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

## 5. 下一步工程（有序）

1. ~~设计本文 + L0 Example + SafetySketch~~（本切片）  
2. L1 库：在 sketch 上实现 **纯数学** 的 init/P1 小引理（仍不接 product wire）  
3. Reference `step` 与 MiniAmm 对齐的 **preservation 义务**（可能新 ABI 名）  
4. 再考虑 materializer 对 read-only inv 的开放（独立 epic）  
5. formal TASK 轨道独立，不与 ordinary certified 混签  

---

## 6. 维护

- 升级「已证」层级时：改本表状态词 + Examples 注释 + 测试钉。  
- 禁止用 `invariant foo : true` 命名暗示已证 foo 业务性质（L0 应用中性名 `l0Surface`）。
