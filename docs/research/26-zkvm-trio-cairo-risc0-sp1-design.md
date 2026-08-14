---
id: RESEARCH-026
title: Cairo / RISC Zero / SP1 zkVM 三机 Plan 设计（fail-closed MVP）
status: draft
owner: engineering
updated: 2026-08-14
normative: false
---

# Cairo / RISC Zero / SP1 zkVM 三机 Plan 设计

> **目的**：在实现前固定三个独立 zkVM `TargetId` 的 **Plan/IR/制品/fail-closed 面** 与
> 相对 OpenVM/Noir/Aleo 的边界。  
> **不是** registry 扩面、不是 accepted PRD 扩面、不是 formal TASK、不是证明系统安全评估。  
> 前置归类：[`ADR-0017`](../adr/0017-research-phase-targets-ton-move-cairo-zkvm.md)、
> [`ADR-0008`](../adr/0008-separate-zk-execution-models.md)、
> [`25-remaining-target-landscape.md`](25-remaining-target-landscape.md)、
> [`../targets/08-openvm.md`](../targets/08-openvm.md)、
> [`../targets/family-zkvm.md`](../targets/family-zkvm.md)。

状态：`draft`。日期：2026-08-13。

---

## 0. 设计结论（先读）

1. **三个都是独立 target**：`cairo`、`risc0`、`sp1`。同属文档 family **zkVM**，**禁止**共享
   `ZkPlan` / `OpenVmPlan` / 彼此 Plan 类型。
2. **能做**，且应以 **fail-closed 窄片段** 做工程 MVP——与用户判断一致：不追求与
   EVM/Solana/NEAR 特性面齐平。
3. **产品角色**：`ArtifactDeployability = verifiable-workload`（或更弱的 source-only 制品）。
   **不是** deployable 链上合约；**不是** Aleo/Psy 应用链。
4. **状态模型**：与 Noir/OpenVM 同轴——逻辑 state 以 **external pre/post**（或 guest 内存一次运行）
   realization；不得假装有原生持久 storage。
5. **落地顺序**：先 **OpenVM**（registry 已有 design-only）钉共享「zkVM 产品纪律」；
   三机中 **第二深度 leaf 默认 `risc0` 或 `sp1`（择一）**；`cairo` 因 ISA/生态不同可并行
   **文档**、**串行实现**。三机可同时有 dossier + 冻结 Plan schema，但 **禁止三 materializer 并行抢共享核**。

---

## 1. 它们是什么 ZK

| TargetId | 证明对象 | Guest / ISA | 典型结算 | 与 PF 已有 leaf 的关系 |
|---|---|---|---|---|
| `noir`（已实现） | 电路约束 | ACIR / Brillig | external verifier | **电路**，不是 zkVM |
| `openvm`（design-only） | guest 执行 | RV32IM + extensions | external | **同族第一叶** |
| `risc0` | guest 执行 | RISC-V（zkVM receipt） | external | 同族；与 OpenVM 最近 |
| `sp1` | guest 执行 | RISC-V（Succinct） | external | 同族；与 risc0 近、工具链不同 |
| `cairo` | Cairo VM 执行 | Cairo / Sierra→CASM | 常 Starknet 语境，也可离线 STARK | 同族但 **另一 ISA**；勿并入 RISC-V Plan |
| `aleo` / `psy` | 应用链 proof+final | 平台专用 | 链内结算 | **禁止**当 zkVM 实现 |

「都是 ZK」只够放进导航标签；Plan、IR、tool lock、maturity 必须分机。

---

## 2. 共享产品模型（三机 + OpenVM）

### 2.1 一次 invocation 的语义故事

对 admitted 片段，Reference 故事固定为：

```text
(preLogicalState, invocation)  --[pure transition / effects subset]-->  (postLogicalState, outcome)
```

zkVM realization：

1. 把 `(pre, args)` 编码为 **guest public/private inputs**（精确字节布局进 Plan）。  
2. Guest 执行（可证明）计算出 `post` 与声明的 public outputs。  
3. **链上持久化 / 多调用连续性** 不由本 target 提供；continuity =
   `external-public-pre-post`（对齐 Noir 纪律）或 profile 声明的 commit/reveal 扩展。  
4. `call` / `schedule` / 原生资产：**默认 fail closed**（无诚实链上 CPI）。

### 2.2 六轴建议（未来进 registry 时）

| 轴 | 建议 wire（三机同形，digest 内仍分 target） |
|---|---|
| `executionHost` | 需扩枚举：至少 `cairo-vm`、`risc0-guest`、`sp1-guest`（**不要**复用 `openvm-guest`） |
| `commitModel` | `guest-external` |
| `stateBinding` | `guest-memory-io` |
| `callModel` | `guest-internal`（外部 call FC） |
| `proofModel` | `zkvm-execution` |
| `settlementModel` | `external-verifier`（Starknet 部署另用 NetworkProfile，不塞进 codegen） |

> SPEC-REG-001 扩枚举必须随独立实现 ADR；本设计只冻结意图。

### 2.3 MVP 成熟度阶梯（每机相同梯子，独立爬）

| 阶 | 制品 | 门禁 | 可声称 |
|---|---|---|---|
| **Z0 Plan-only** | Plan JSON / 结构化 IR 文本 | ValidatePlan | 有 target-owned Plan |
| **Z1 Guest source/IR** | 受控 guest 源或 IR | 结构/金样 | source-only workload |
| **Z2 Execute** | 锁定工具跑 guest，钉 public output | host-optional execute | deterministic execute |
| **Z3 Prove** | receipt/proof + VK 绑定 | Tool Lock prove/verify | `verifiable-workload` |
| **Z4 Network** | 明确 NetworkProfile（如 Starknet） | 另 ADR | 仅 cairo 可能；risc0/sp1 默认不做 |

**本设计默认首切片停在 Z0→Z1**；Z2/Z3 各机单独排期。禁止把 Z1 写成「已证明」。

---

## 3. 可移植片段 Q0（三机共用承认面）

> 原则：**承认面取交集**；某机多出来的能力用 **versioned extension**，不得静默放宽 Q0。

### 3.1 Q0 Admit（期望 LOWER）

| 面 | 规则 |
|---|---|
| 类型 | anonymous `UInt32`/`UInt64`/`Bool`/`Unit`；可选后期开 `UInt8/16` |
| State | ≤ N 个 public 标量 state（建议 N=4）；**无** Map/Bytes/String/Field/Principal |
| Callable | 至多一个 `init`、若干 `entry`、只读 `view`、`pureFn` |
| 运算 | checked `+ - *`（div/mod 可先 FC）、比较、Bool 逻辑、bit 可选 FC |
| 控制流 | `if`、有界 `for`（乘积 cap）、`match` 仅 Bool/小枚举；无递归 pureFn 环 |
| Effect | `assert` / zero-payload `revert`；**emit FC**（或降为 public log 扩展） |
| 连续性 | init/entry/view → **独立 guest entrypoints** 或单一 entry + mode tag；pre/post state 为 public I/O |
| Proof | Q0 **不要求** prove；metadata `proofMode=none` |

### 3.2 Q0 Fail-closed（必须显式拒绝 + 测）

| 面 | 原因 |
|---|---|
| `call` / `schedule` | 无原生链调用；禁止 witness 槽假装「调用已发生」（Noir 的 PARTIAL 槽也 **不**默认搬到 zkVM Q0） |
| `context.*` | 无链时钟/caller；除非未来 oracle extension |
| `commit` / disclosure 进阶 | 需独立 soundness；Q0 FC |
| nonempty `invariant` | 除非后续 invariant-as-assert 扩展 |
| 聚合 / 容器 state | 布局与 guest ABI 成本高；Q0 FC |
| Field / 曲线特化 | 避免与 Noir/Aleo/Psy 密码学面纠缠 |
| 无界循环 / 动态分配 | zkVM cycle 与确定性 |
| 多程序组合 / 跨 guest CPI | 超出 Q0 |

### 3.3 Counter 黄金路径（三机共用验收故事）

同一 `Examples/Counter`-级源（或等价 fixture）：

1. `init` → post.count=0  
2. `increment` → checked +1；overflow revert/trap 且 post=pre  
3. `view` → 读 post  

各机只证明：**在自己的 input/output 布局下** execute（及可选 prove）与 Reference 对该片段一致；  
**不**声称与 EVM Anvil 字节级相同。

---

## 4. 分机差异与 Plan schema

### 4.1 对照总表

| 维度 | `risc0` | `sp1` | `cairo` |
|---|---|---|---|
| ISA | RISC-V guest | RISC-V guest | Cairo / Sierra |
| 与 OpenVM 距离 | 近（都可走 ELF-ish guest 策略） | 近 | 远 |
| Guest 生成候选 | 受控 Rust → ELF；或 Lean 降小型 RV IR | 同左（工具链不同） | Cairo/Sierra 文本或中间 IR；**禁止** RV Plan |
| Proof 对象 | Session/Receipt | SP1 proof 对象 | STARK / Stone 等（版本钉死） |
| 链生态引力 | 通用 zkVM | 通用 zkVM | Starknet 强；易误写成「又一个 CosmWasm」 |
| Q0 难度 | 中 | 中 | 中高（felt/类型与 UInt64 映射） |
| 建议实现序 | **第二叶候选 A** | **第二叶候选 B** | **第三叶**（或文档并行） |

### 4.2 `Risc0Plan`（草稿）

```text
Risc0Plan {
  profileId                 -- e.g. risc0-guest-u64-v1
  semanticsDigest           -- bound TargetSemantics
  sourceHash, semanticHash  -- from CompiledSemanticV1
  continuity                -- external-public-pre-post
  proofMode                 -- none | execute-only | prove  (Q0=none|execute-only)
  guest {
    entrypoints[] { name, role: init|entry|view|pure,
                    publicInputLayout, privateInputLayout, publicOutputLayout }
    memoryLayout            -- fixed; no dynamic alloc in Q0
    cycleBudget             -- fail closed if static estimate > budget (optional Z1)
  }
  methods[]                 -- ordered lowering of admitted callables
  stateSlots[]              -- name, type, pre/post public offsets
  failurePolicy             -- trap ≡ revert for Q0 scalar overflow/assert
  resourceEnvelope
}
```

**IR**：`Risc0GuestIR`（target-owned）→ 受控 Rust guest 或最小 RV 指令序列。  
**禁止**：把 Solana/NEAR/OpenVM IR 节点 alias 进来。

### 4.3 `Sp1Plan`（草稿）

与 `Risc0Plan` **同形字段**，类型名必须是 `Sp1Plan` / `Sp1GuestIR`：

- `profileId` 例：`sp1-guest-u64-v1`  
- toolchain / proof 对象字段不同（`sp1ProofMode`、`vkBinding`）  
- **不得** `type Sp1Plan := Risc0Plan` 或共享 lowering 函数「改个名字」

允许抽取 **文档级** 共用 checklist（Q0 表）；Lean 共享只限与 zkVM 无关的纯字节布局 helper（若有），且需 ADR 批准。

### 4.4 `CairoPlan`（草稿）

```text
CairoPlan {
  profileId                 -- e.g. cairo-sierra-u64-v1
  semanticsDigest
  sourceHash, semanticHash
  continuity                -- external-public-pre-post
  proofMode                 -- none | execute-only | prove
  sierraOrCairo {
    entrypoints[] { name, role, feltLayout ... }
    -- Q0: UInt64 须显式 felt 范围守卫；禁止静默 wrap
  }
  methods[]
  stateSlots[]              -- felt-encoded pre/post
  failurePolicy             -- assert/revert → Cairo assert 或显式 panic 约定
  starknetHints             -- Q0 必须 empty；非空仅 extension
  resourceEnvelope
}
```

**关键**：Cairo 的 felt 宽度/取模 ≠ PF checked UInt64。Q0 必须 **范围检查后** 再运算，overflow 与 Reference checked 语义对齐；做不到就 FC 该 op。

**Starknet 系统调用**（storage、l1_handler、get_caller_address 等）：**整表 Q0 FC**。  
若未来要 Starknet 部署，走 **NetworkProfile + extension**，不得塞进默认 codegen。

---

## 5. Materializer / 产品链接入（实现时纪律）

与九 leaf 相同：

```text
CompiledSemanticV1
  → resolveEngineeringRequirementsV1   -- 仅声明 Q0 支持的 requirement keys
  → planFromCapability → validatePlan
  → irFromCapability
  → materialize → finalize             -- Z0/Z1 zero-tool 或 locked guest codegen
  → proof-forge.output.v1 + exact closure
```

Resolver 行（示意）：

| keys（Q0） | 支持 |
|---|---|
| `state.persistent` / 标量 | yes |
| `value.bool` / `value.uint64` | yes |
| `failure.rollback` / checked arithmetic | yes |
| `effect.event` / sync-call / async | **no** |
| `context.*` / `disclosure.*` 进阶 | **no** |

Registry：实现前必须 **独立实现 ADR**（每机或「三机总 ADR + 每机 profile 附录」）；  
扩 `TargetId` 枚举与 `ExecutionHost`；**不**改 accepted Phase-1 文案（ADR-0036）。

---

## 6. 与 OpenVM / Noir 的分工

| | OpenVM | 本三机 | Noir |
|---|---|---|---|
| 角色 | zkVM **模板叶**（先钉纪律） | 同族扩展叶 | 电路叶 |
| Plan | `OpenVmPlan` | 各机自有 | `NoirPlan` |
| 状态 | guest I/O | 同左 | relation pre/post |
| 可复用 | Q0 表、maturity 梯子、文档 checklist | — | disclosure 词汇（非 Plan） |
| 禁止 | 成为「通用 zkVM Plan」 | 复用 OpenVM IR | 当 zkVM 用 |

推荐工程序：

```text
TGT-OPENVM-MVP (Z0–Z1)
    → 冻结「zkVM Q0 产品纪律」复盘
    → 择一：TGT-RISC0-MVP 或 TGT-SP1-MVP
    → TGT-CAIRO-MVP
```

三机 **Plan schema 可先全部写进 dossier**（本文件 + 后续 TARGET-*），实现仍串行。

---

## 7. 风险与诚实边界

| 风险 | 缓解 |
|---|---|
| 把 receipt 当成「合约已部署」 | deployable=false；文案只用 verifiable-workload |
| UInt64 ↔ felt/RV 宽默契不一致 | Q0 显式范围守卫；测 overflow |
| 三机并行导致假共享 IR | 类型分治；CI deletion gate 禁 `ZkPlan` |
| prove 工具链漂移 | Tool Lock 单版本；Z3 前禁止宣称 proof |
| Starknet 特化污染 cairo Q0 | `starknetHints` Q0 empty |
| 与 Aleo/Psy 用户预期混淆 | dossier 首段钉「无链结算」 |

---

## 8. 交付物清单（设计 → 实现前）

| 项 | 状态 | 说明 |
|---|---|---|
| 本设计 RPT-026 | **本文件** | Plan/Q0/阶梯 |
| `docs/targets/13-cairo.md` 等 dossier | **done**（2026-08-13） | `13-cairo` / `14-risc0` / `15-sp1` |
| `family-zkvm.md` 增列三机 | **done** | 阅读视图 |
| 实现 ADR（扩 registry） | pending | 每机或总+附录 |
| Backlog IDs | 见 §9 | 勾选 sole live 队列 |
| Lean materializer | **不做**直至 ADR | — |

---

## 9. Backlog 挂钩

| ID | 项 | 状态 |
|---|---|---|
| **TGT-ZKVM-TRIO-DESIGN** | 本设计（RPT-026） | **done**（随本文） |
| **TGT-ZKVM-DOSSIERS** | 补 `cairo`/`risc0`/`sp1` dossier + family 刷新 | **done**（2026-08-13） |
| **TGT-OPENVM-MVP** | 同族第一实现叶 | **done**（2026-08-14：O0/O1 engineering MVP；无 prove） |
| **TGT-ZKVM-SECOND** | OpenVM 后择一 `risc0` **或** `sp1` | pending（不抢 EVM formal 主轴） |
| **TGT-CAIRO-MVP** | 第三 zkVM leaf | pending（blocked-on second 或显式改序） |

不扩 accepted PRD；不插入 Soroban/ICP 之前，除非产品改 ADR-0036 工程优先序。

---

## 10. 非声称

- 不声称三机已可寻址或已实现。  
- 不声称 STARK/SNARK 安全参数或 auditor 级证明。  
- 不声称与 EVM/Solana Counter 全表面同构。  
- 不把 Cairo 写成 Starknet CosmWasm 替代。  
- 不新增 `TASK-*` / formal EV。
