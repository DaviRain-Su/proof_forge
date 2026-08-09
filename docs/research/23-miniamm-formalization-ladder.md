---
id: RESEARCH-023
title: 通用程序形式化栈（L0–L2）与 MiniAmm 实例
status: draft
owner: engineering
updated: 2026-08-09
normative: false
---

# 通用程序形式化栈（L0–L2）与 MiniAmm 实例

> **目的**：定义 ProofForge **平台级**「业务逻辑 + 形式化」能力分层，避免：
> (1) 把 `InvariantTheoremV1` 误写成可达保持；
> (2) 把试点写成 **仅服务某一个合约** 的一次性数学库；
> (3) 再发明 **第二套手写 step** 与产品 Semantic/Reference 分叉。
>
> **产品立场**：统一源语言与共享证明 **形状 / 门禁**；每个 `program` **实例化**
> 自己的状态、谓词 P 与保持义务。2026-08-09 wave-3′ 已完成 generic-first
> 迁移：codec round-trip、contract-agnostic shape-family theorem、结构化
> `subjectDataV1`，以及普通 same-file `Counter` / `MiniAmmL1` product positives。
> `ProofInstances/`、`ClosedSubjectPinV1` 与历史 ParityCounter/ZeroCounter 专属栈已删除。
>
> **两条形式化账本**（见 ADR-0034 D10）：
> (1) **业务逻辑** — program invariant/preservation（本文件主线；generic-first
>     same-file product path GREEN）；
> (2) **工具内部** — compiler/Reference/wire formal TASK/TST（独立 ledger，不因实例正例关闭）。
>
> **L1 路线（Reference-first）**：禁止第二套 step；业务保持挂在 admitted
> `Reference` / 产品 Semantic 上。业务 proof/data 只在自身源文件，产品包不含
> contract-specific pin、bytes 或 theorem instance。
>
> 对齐：ADR-0027（当前 inline base authority）、ADR-0034（`proposed`；generic-first
> same-file product path GREEN；supersession/formal pending；**不** supersede 0027）、
> [`22-portable-surface-vs-chain-reality.md`](22-portable-surface-vs-chain-reality.md)、
> `Examples/Counter.lean` / `Examples/MiniAmmL1.lean`。

**非 formal**：本文件不关闭 TASK-D2-07 / TST-SEM-002/003 / TST-PROOF-001。

---

## 0. 通用 vs 实例（必读）

```text
┌──────────────────────────────────────────────────────┐
│  平台通用形式化栈                                       │
│  · 语法：invariant / proof / 同文件 theorem             │
│  · L0 门：certifyInlineProofV1 / simple-closure 族      │
│  · 共享 ABI：InvariantTheoremV1 / evalInvariantV1       │
│  · L1 ABI foundation：PreservationTheoremV1 + Reference step │
│  · L2：formal TASK / refine / hermetic（最后）          │
└───────────────────────────┬──────────────────────────┘
                            │ 实例化（每 program 自己的 P）
         ┌──────────────────┼──────────────────┐
         ▼                  ▼                  ▼
    Counter（普通）      MiniAmmL1（普通）     后续业务合约 …
```

| 层级 | 通用？ | 内容 |
|---|---|---|
| L0 语法与 CLI 门 | **是** | 任意符合族的 program 名/模块都可 certified |
| L0 simple-closure 形状 | **是** | `view Bool true` + `invariant : true` + generated helper |
| L1 **义务形状** | **是（foundation 已实现）** | `PreservationTheoremV1` = ordinal + positive admission + base + full-input product `step` |
| L1 **P 内容** | **否（每程序）** | Counter 偶数；MiniAmm empty-pool；后续合约各自定义 |
| L1 **step 权威** | **是（产品）** | sole admitted `Reference` / Semantic；**禁止** 第二套手写 step |
| L2 / 项目 formal | **是（平台轨道）** | 延后；不绑死某个 Example |

**验收通用性**：generic codec/shape/elaboration 已进入产品路径；
`Counter` 与 `MiniAmmL1` 作为普通 same-file 合约复用同一 ABI 并 product GREEN。
历史 forcing instances 与 closed pins 已删除，不是产品架构。

---

## 1. 三层命题（平台命名）

| 层 | 名称 | 命题直觉 | 当前工程状态 |
|---|---|---|---|
| **L0** | 证明表面 / simple-closure | 可认证的 `invariant : true` + 同文件 theorem | **已接线**；**当前产品 authority 仍为 ADR-0027** |
| **L1** | 业务保持 | 对 **该程序** 的 P：positive initial/admission + **product Reference step** 后保持 | **generic-first path GREEN**（codec/shape/structured subject + Counter/MiniAmmL1 ordinary same-file positives）；ADR-0027 supersession 独立 pending |
| **L2** | 项目 formal | formal step corpus、target refine、hermetic/release | **最后**（工具 track 2）；与单合约 L1 分账 |

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

### 1.2 共享 L1 形状（ABI foundation 已实现；Reference-first）

对任意 closed `SemanticProgramV1` 与 dense invariant ordinal：

```lean
PreservationTheoremV1 program ordinal :=
  ordinal.toNat < program.invariants.size ∧
  ∃ admitted,
    admitReferenceProgramSliceV1 program = .ok admitted ∧
    PreservationBaseV1 program ordinal admitted ∧
    PreservationStepV1 program ordinal admitted
```

- Base 两个 lifecycle 分支都先正要求
  `∃ pre, initialLogicalStateV1 program = .ok pre`；无 initializer 再要求
  `StateConforms ∧ eval=true`，有 initializer 则全称量化 initializer-targeted
  invocation / responses / vault。
- Step 全称量化 `LogicalStateV1`、完整 `InvocationV1.context`、responses、vault，
  并逐项匹配 `OutcomeV1.returned/reverted/trapped`；失败分支要求 exact unchanged pre-state。
- admission/initial 失败都会使命题为假；不使用 implication 空真，不把 Outcome 压成 Option。

| 谁提供 | 什么 |
|---|---|
| **平台** | `PreservationABI` 形状、**sole product step**（Normalize → Semantic → admitted Reference）、测试模式 |
| **程序作者** | 对具体 executable invariant 的 base/step 证明；**不** 另写一套 `miniAmmStep` |

产品 kind/inventory/alias/protocol/certifier plumbing 已接线；保持性仍是独立定理族，不塞进
现有全称 `InvariantTheoremV1`。generic-first `Counter` / `MiniAmmL1`
product-certified 实例已闭合；alias/negative/identity 回归不得冒充 formal 完成。

**禁止**：为每个合约再维护平行的 `State` / `Effect` / `step` 手写解释器
（HEAD 曾有 Semantic `MiniAmmSafetySketchV1` 试点，**Slice 0 已从 HEAD 删除**，见 §5.0）。

---

## 2. MiniAmm 谓词队列（非通用清单）

下列 P **仅** 针对 MiniAmm 业务族；P1 由 `Examples/MiniAmmL1.lean`
以普通 same-file 合约路径完成。其他合约应有自己的 Pn 表。

| ID | 谓词 P（直觉） | 依赖 | 难度 | 状态 |
|---|---|---|---|---|
| P0 | `true`（L0 表面） | simple-closure | — | **done**（`MiniAmmProofSurface`） |
| P1 | empty pool：`totalSupply=0 → reserves=0` | product Reference step | 中 | **done（2026-08-09）**：`Examples/MiniAmmL1.lean` 同文件 invariant/proof/theorem；generic triple-UInt64 shape；product certified |
| P2 | LP 份额和 = totalSupply（cap-4） | Map 模型 + Reference | 中高 | 草图（Map Principal admission 已通） |
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
| `InvariantABI` | 共享定理命题 / logical state |
| `ReferenceMachineV1` / `ReferenceV1` | **sole L1 step 权威**（admitted engineering machine；非 formal `step`） |
| `PreservationABI` / `PreservationPackagingV1` / `PreservationShapeV1` + ADR-0034（`proposed`） | 通用 ABI、codec/shape/structured subject 与 ProofKind plumbing；产品包零合约专属内容；supersession/formal pending；ADR-0027 仍约束 inline base |

### 3.2 实例：MiniAmm 试点

| 文件 | 角色 |
|---|---|
| `Examples/MiniAmm.lean` | **业务程序**（可 deploy）；无 nonempty inv |
| `Examples/MiniAmmL1.lean` | **P1 同文件业务证明**；program + invariant + proof binding + ordinary theorem |
| `Examples/MiniAmmProofSurface.lean` | **L0 样例**（simple-closure） |
| `Tests/Semantic/MiniAmmVectorsV1.lean` | **共享数学向量 / oracle**（UInt64 floor；非 step） |
| `Examples/MiniAmmAssets.lean` | 真资产实例；L1-F 之后 |

**HEAD 删除面（Slice 0，2026-08-07）**：

| 路径 / 动作 | 说明 |
|---|---|
| `ProofForgeV2/Semantic/MiniAmmSafetySketchV1.lean` | 误入产品 Semantic 的手写 State/Effect/step |
| `ProofForgeV2.lean` umbrella import | 不得把合约 sketch 当平台依赖 |
| Examples 注释 + SBOM pin | 注释只指本 ladder；sketch 出 package-file 表 |

**未合入草稿（discarded before integration，非 ledger 成果）**：工作区曾短暂出现的
`Tests/Instances/…` / `Tests/Semantic/MiniAmmSafetySketchV1` / test registration
改动 **never on HEAD**；架构复核后丢弃，**不**计为已合入删除。

**边界**：

| 禁止 | 原因 |
|---|---|
| 第二套手写 `step`（任何路径） | 与 product Semantic/Reference 分叉；架构复核否决 |
| `ProofForgeV2/Semantic/` 挂合约专属 step | 产品语义核只承载通用 Wire/Normalize/Reference… |
| `ProofForgeV2.lean` umbrella 导入合约实例 | 不得把合约 step 当平台依赖 |
| 随包产品模块挂业务 proof/data | 业务 proof 只在自己的 `Examples/*.lean` 源文件 |

### 3.3 Generic-first 迁移门

1. 通用 codec round-trip、shape-family preservation 与 structured subject elaboration 已完成。
2. `Examples/Counter.lean` 与 `Examples/MiniAmmL1.lean` 作为普通业务文件 product certified。
3. 历史 EvenCounter/ZeroCounter forcing instances、`ProofInstances/` 与
   `ClosedSubjectPinV1` 已删除；不得恢复为主路径。
4. 新业务合约只可在自身文件复用平台通用 API；MiniAmm 不享有特例。

---

## 4. 产品 CLI 边界（通用）

| 命令 | 无 nonempty inv 的业务 program | 带 nonempty inv 的 proof 表面 |
|---|---|---|
| `check` | ok（`noProof` 或无 proof 字段） | ok 时可 `proofStatus=certified`（L0 holds 族或 L1 preserving） |
| `build` 多数 materializer | deploy 路径 | **FC**（nonempty inv；工程已知） |

不得把 L0/L1 certified 写成「可部署且业务已证安全」或 formal 完成。

---

## 5. 执行路线图

**优先级**：business track generic-first migration 已完成；后续业务合约按需在自身文件
复用通用 API。**D/L2 项目 formal（工具 track 2）独立推进**；**不** supersede ADR-0027。

### 5.0 已完成 / superseded

| 项 | 范围 |
|---|---|
| L0/L1/L2 分界 + 本通用架构叙述 | 平台 |
| simple-closure 产品门 + `MiniAmmProofSurface` | 平台 L0 + 样例 |
| MiniAmm 业务源无 inv | 实例 deploy 纪律 |
| `MiniAmmVectorsV1` 共享数学向量 | oracle only；**不是** step |
| HEAD Semantic 手写 L1-A sketch | **deleted from HEAD（Slice 0）** — 第二套语义 |
| 未合入 Instances/suite 草稿 | **discarded before integration** — 非 ledger 成果 |

### 5.1 手写 L1-A supersession 与 Reference-first

| 交付 | 状态 |
|---|---|
| 删除 HEAD Semantic sketch + umbrella | **done** — Slice 0（真实合入删除面） |
| 路线改为 **Reference-first** | **done** — 本文件 |
| 禁止再引入第二套 step | **policy** — 见 §0 / §3.2 |
| MiniAmm 经 Normalize → `admitReferenceProgramSliceV1` | **done**（Map Wire-envelope admission；见 §5.1.1） |
| ADR-0034 Preservation ABI design freeze | **done** — `proposed`；**不** supersede ADR-0027 |
| Generic Preservation ABI foundation | **done** — positive initial/admission + base/step/full Outcome |
| ProofKind/inventory/certifier plumbing | **done** — bare holds；preserving kind；无 2-field fallback |
| Generic codec / shape / structured subject | **done（2026-08-09）** — product contract-agnostic APIs |
| Ordinary same-file Counter + MiniAmmL1 | **done（2026-08-09）** — product certified |
| 删除 ProofInstances / closed pin / historical instance stack | **done（2026-08-09）** — 产品包零合约专属内容 |

#### 5.1.1 MiniAmm Reference admission（Map budget 已切 Wire-envelope）

工程事实（admitted Reference machine，非 formal；**admission done**）：

- `Examples/MiniAmm` 含 dense `Map Principal UInt64` 等 aggregate state。
- 整程序 admission `admitReferenceProgramSliceV1` **已通过** 真实 product 路径：
  shipped `Examples/MiniAmm.lean` → Normalize → admit
  （`Tests/Semantic/ReferenceV1.lean` `testMiniAmmMapPrincipalAdmit`）。
- Map 静态资源 admission **不再** 固定 `maxMapEntriesReferenceBudgetV1 = 4096`
  做整表 worst-case 乘法，也不从少量 max/min homogeneous packing profile 派生容量
  （该形状无法保守覆盖 heterogeneous aggregate entries）。每个 Map 作为完整 Wire
  canonical envelope，parent-facing width/work 直接绑定 shared
  `maxCanonicalValueBytes` / `maxCanonicalProgramBytes` 的**单次 canonical-value/helper**
  上限；empty Map state default 单独按 exact 4-byte count header / O(1) 计费。
- **Runtime upsert 权威不变**：IndexSet 仍经 Wire 实际 encode / `maxMapEntriesV1` /
  valueBytes / work 校验；没有第二套 runtime capacity。
- **资源诚实边界**：该 envelope 不是 whole-step cumulative-work receipt；多 pair
  `Map.of` 的 sequential upserts 仍各自使用 shared cap，单步累计 receipt 属后续资源切片。

诚实边界（仍成立）：

- MiniAmm L1 P1 已由 `Examples/MiniAmmL1.lean` 在 generic triple-UInt64
  shape family 上 product certified；这不等于 P2–P5、formal TASK 或 target refinement。
- `MiniAmmVectorsV1` 仍只钉数学 floor（非 step）。
- L0 `MiniAmmProofSurface` 仍由 **ADR-0027** 产品 holds 门约束。
- **禁止** 旁路手写 step；**禁止** 预填 ADR-0027 supersession 或 formal 关闭。

### 5.2 当前工程方向

| 项 | 说明 |
|---|---|
| Generic codec/shape/structured-subject cutover | **done** |
| Counter ordinary same-file preserving | **done** |
| MiniAmm P1 ordinary same-file preserving | **done** |
| Product contract-instance/pin deletion | **done** |
| 后续业务 | P2–P5 按需在业务文件深化；不得新增平台特例 |

### 5.3 L1-B — MiniAmm P1 完整保持（done）

`Examples/MiniAmmL1.lean` 已在 **product Reference step** 上以 generic
triple-UInt64 shape theorem 完成 `Preserves P1` 并通过产品 certifier。

### 5.4 L1-C — MiniAmm Map + P2

实例加深；Map 模型必须与 Reference/Wire 一致，不得旁路。

### 5.5 L1-D — MiniAmm P3 / 弱 P4

宽积模型；平台侧只要求「算术模型可陈述」，不规定唯一 P。

### 5.6 L1-E — 语义对齐义务（简化）

| 交付 | 说明 |
|---|---|
| 无第二套 step 即可 | Reference-first **取消**「abstract ≡ Reference」双模型 join 债务 |
| **通用义务** | 每个实例声明 P 与 product state 的投影；step 权威唯一 |

### 5.7 Generic-first 迁移门

| 交付 | 说明 |
|---|---|
| 通用 codec + shape + structured subject | **done** |
| Counter + MiniAmmL1 ordinary same-file positives | **done** |
| 历史 forcing instances / pin / ProofInstances 删除 | **done** |

### 5.8 L1-F — Assets 实例（可选）

`MiniAmmAssets` 或等价：记账 + sync transfer 一致性；仍是 **实例**。

### 5.9 D / L2 — 项目 formal（最后）

- formal TASK-D2-07 / TST-SEM / TST-PROOF
- hermetic / Stage-0 / release
- target refine Reference

**不得** 用 MiniAmm L0 certified 或工程 L1 草图勾 formal 完成。

### 5.10 切片顺序（Reference-first）

```text
Slice 0: 删除 HEAD Semantic 手写 L1-A sketch（done）
  → Map Wire-envelope Reference admission + MiniAmm admit（done）
  → Preservation ABI + kind/inventory/certifier（done）
  → historical forcing instances（done，后由 clean cutover 删除）
  → generic codec round-trip（done）
  → generic shape-family preservation（done）
  → structured subject elaboration（done）
  → Counter + MiniAmmL1 ordinary same-file product positives（done）
  → 删除 ProofInstances / closed pin / contract-specific product modules（done）
  → L1-C / L1-D 按需深化业务
  → (可选) L1-F Assets
  → …最后… D/L2 formal（工具 track 2）
```

### 5.11 不在当前范围

| 项 | 原因 |
|---|---|
| 再引入手写 `miniAmmStep` / 旁路 step 库 | Slice 0 否决；第二套语义 |
| 业务 program 强制带 inv 且 EVM/Solana build | materializer FC |
| 用 `InvariantTheoremV1` 证任意业务 P | 形状不对 |
| 在产品包新增合约专属 proof/data/pin | 违背 generic-first clean cutover |
| 现在开全项目 formal D | 产品决策：最后做 |
| 声称 formal TASK/TST 因本 ladder 关闭 | **禁止** |

---

## 6. 维护

- 平台形状变更：更新 §0–§1；实例进度：更新 §2 / §5。
- 新 program 形式化：新增「实例」小节或独立 instance 笔记，**链回** 本文件 §0。
- L0 中性名（如 `l0Surface`），禁止用 `true` 不变式冒充业务安全名。
- L1 每证一条实例 P：标注 **proved (product Reference step / instance X)** + 定理名。
- 任何「旁路 step」提案：默认拒绝，先读 §5.1。
