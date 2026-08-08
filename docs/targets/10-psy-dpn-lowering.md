---
id: TARGET-PSY-DPN
title: Psy DPN lowering plan (ProgramV1 → DPNFunctionCircuitDefinition)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Psy DPN 层落地规划

状态：`draft`（规划输入；DPN-1..7 engineering 已落地 dual-write；**G5-WIDE** mul/div/shift DPN 已闭合；G5 residual 仍含 Array/Principal/Bytes 产品金样与 hard-require）
目标：在 **不改变 ProgramV1 可移植业务语义** 的前提下，把 Psy target 的权威物化从 **文本 `.psy`** 切到 **官方 DPN 方法级定义**，并评估 **ProgramV1 语法/语义能覆盖到 DPN target 的范围**。

权威上游（pin）：

| 项 | 值 |
|---|---|
| 仓库 | [`PsyProtocol/psy-node`](https://github.com/PsyProtocol/psy-node) |
| rev（与 dargo 0.1.0 / psy-compiler workspace 对齐） | `79e0b82422ebdd1173a7b4b3751eb3186aad83e5` |
| crate | `psy_vm` |
| 顶层类型 | `DPNFunctionCircuitDefinition` |
| 路径 | `client_prover/psy_vm/src/dpn/vm/def.rs` + `ops/` |
| 人类可读说明 | `psy-node/docs/src/vm/bytecode.md`、`execution.md`（亦见于 docs.psy-protocol.xyz VM 章） |

**非目标（本规划明确排除）：**

- 把完整 **PSL 源语法** 变成 ProofForge 作者语言（仍 sole `program … where` / ProgramV1）。
- 在产品 Finalize 内调用网络 UPS / 部署 / hermetic/formal 完成。
- 实现全部 DPN 操作码（如 Secp、完整 IMT、ClearEntireTree）除非 ProgramV1 已有可诚实映射的语义。
- 声称 “官方 Language 手册每一节 PSL 已支持”。

---

## 1. 动机

当前 Psy 路径：

```text
ProgramV1 → Semantic → PsyPlan → EmitIR → 文本 .psy → 外部 dargo → DPN JSON
```

问题：

1. **脆性**：与 dargo 源语法/类型怪癖耦合（`return`-in-`if`、`for` 关键字、`u32` vs Felt）。
2. **双重真相**：业务语义在 Semantic/Plan，真正可执行/可证明的形状在 DPN；中间 `.psy` 是第三方言。
3. **覆盖度量失真**：用 “PSL 语法章” 当 KPI 会逼实现 closure/trait/mod；正确 KPI 是 **ProgramV1 已 admit 的构造在 DPN 上可诚实编码**。

目标路径：

```text
ProgramV1 → Semantic → PsyPlan → PsyDpnIR / DPNFunctionCircuitDefinition[]
                │                      │
                │                      ├─ serde JSON ≡ dargo package JSON（金样）
                │                      ├─ 可选：调试 pretty-print .psy（非权威）
                │                      └─ 后续：psy_vm / dargo execute 消费 DPN
                └─ 现有 .psy 发射在 DPN 主路径稳定前保留为过渡旁路
```

---

## 2. DPN 目标模型（实现必须对齐的形状）

### 2.1 方法级顶层

每个 **callable 方法**（init/entry/view/pureFn 在 Psy 物化后的公开方法）对应一份：

```text
DPNFunctionCircuitDefinition {
  name, method_id,
  circuit_inputs, circuit_outputs,   // Vec of encoded indexed ids
  state_commands,                    // Vec<DPNStateCmd<u64>>
  state_command_resolution_indices,  // 与 state_commands 对齐
  assertions,                        // left/right encoded ids + message
  definitions,                       // Vec<DPNIndexedVarDef>
  events                             // default []
}
```

### 2.2 计算图

`DPNIndexedVarDef { data_type, index, op_type, inputs }`：

- `data_type`：`Target=0` / `Bool=1` / `U32Target=2` / Hash / 数组…（`DPNBuiltInDataType`）
- `op_type`：exact `u16`（`DPNOpType`，**有空洞**，禁止按变体序号）
- 引用编码：`id = (data_type << 32) | index`

### 2.3 状态命令（首批必须）

| DPNStateCmd | ProgramV1 对应（首批） |
|---|---|
| `GetSelfUserCurrentContractStateSlotSingle` | `stateLoad` 叶 |
| `SetContractStateSlotSingle` | `stateStore` 叶（condition 常为 ConstantTrue） |
| `Get/Set … SlotRange` / `SlotHash` | 多叶聚合 state |
| `InvokeExternalContractFunctionSync` | void `call`（仅当产品打开；现 PARTIAL） |
| Deferred invoke / OtherUser / Checkpoint / IMT | **默认 FC** 除非有产品语义 |

### 2.4 首批 `DPNOpType` 白名单（可扩展）

`InputTarget`, `Constant`, `ConstantTrue/False`, `Add/Sub/Mul/Div/Mod`, 比较与 Bool 逻辑, `Select`, `GetStateCommandResultSingle/Hash/Array`, `U32*` / `CastU32`（循环与窄宽内部）, `UnaryNegative`（有界）.

**默认拒**：`Secp256k1Verify`, `Keccak256`（除非明确产品需求）, 未映射 context 全表.

### 2.5 金样权威

Linux locked-dargo 对同一 ProgramV1 产品源码：

1. 现有路径：`build → .psy → dargo compile → target/<pkg>.json`
2. DPN 路径：`build → DPN JSON`
3. **结构相等**（或规范化后相等）：`definitions` / `state_commands` / `assertions` / inputs-outputs 编码

首金样：`Examples/Counter` 的 `initialize` / `increment` / `get`。

Pin rev 与 dargo 0.1.0 不一致时 **fail closed**（文档 + Tool Lock 同步）。

---

## 3. 覆盖目标：什么叫 “全覆盖”

### 3.1 定义（本规划采用）

**“ProgramV1 → Psy DPN 全覆盖”** 指（产品最终目标，与用户确认一致）：

> **DSL 自有特性**（统一 `program … where` / ProgramV1）在 Psy 上 **admit 的全部构造**，最终都要有 **确定性 DPN 编码**，使任意该子集上的合约可物化；
> 凡 **不 admit** 的，在 **Normalize / Plan / DPN 边界** 有稳定诊断（证据化 FC），且 **不** 经 `.psy` 旁路偷偷实现。

即：终点不是“只做一个 Counter 模板”，而是 **任意使用已开放 DSL 特性的合约** 都能降到 DPN；分阶段用模板/SSA 扩展矩阵 §3.2，直到 G5。
**不**指：

- 官方 PSL 语言手册全部语法；
- DPN 枚举全部 op / 全部 state_cmd；
- UPS / 部署 / 主网。

### 3.2 覆盖矩阵（ProgramV1 族 → DPN）

图例：`Y` = 目标必须 Y；`P` = PARTIAL / 有界；`F` = 证据化 FC；`N` = 非 Psy 产品面。

| ProgramV1 / Semantic 族 | 现 .psy 路径 | DPN 目标 | 备注 |
|---|---|---|---|
| UInt64 算术 + overflow assert | Y | **Y** | Counter 金样 |
| Bool / 比较 / 逻辑 | Y | **Y** | |
| UInt8/16/32 守卫算术 | Y | **Y** | Felt + range assert 或 U32 子图 |
| Int64 / 窄 Int | Y/P | **Y/P** | 与现 emitter 一致 |
| UInt128/256（显式 VM profile） | Y | **Y** | 多 leaf + schoolbook/restoring 展开为 defs |
| Field bn254 | F | **F** | Psy Felt≠bn254 |
| Principal / String / Bytes 叶 | Y/P | **Y/P** | wire identity 多 leaf |
| named Struct/Enum flatten | Y | **Y** | leaf 序固定 |
| Array UInt64 / Option UInt64 | Y | **Y** | |
| Map UInt64 UInt64 cap-8 | Plan Y；dargo 破 | **Y**（DPN-5） | Select/upsert storeAggregate；绕过 return-in-if |
| 嵌套 Map / Map return | F | **F** | |
| let / assign / return | Y | **Y** | SSA defs |
| if / match | Y | **Y** | Select / 分支状态 cmd condition |
| bounded for UInt64 | 静态 unroll Y | **Y** | 展开或固定步；**无** while |
| while / 无限循环 | N | **F** | ProgramV1 无 while |
| pureFn / localCall | Y | **Y** | 内联或 pure 子图 |
| const / Op.Constant | Y | **Y** | Constant op |
| bare assert / zero-arg revert | Y | **Y** | assertions[] |
| payload error | F | **F** | |
| emit | PARTIAL | **P** | events[] 若可证；否则保持 PARTIAL 文档 |
| void call | PARTIAL | **P** | InvokeSync 仅证据充分后 |
| result-bearing call | F | **F** | |
| schedule | F | **F** | |
| ContextRead / Commit | F | **F** | 无官方 public-input 锚点前 |
| nonempty invariant Plan | F | **F** | |
| pf.assets | F | **F** | 零绑定 |
| 元组 / 闭包 / trait / mod | N | **N/F** | 非 ProgramV1 作者面 |

**结论（规划层）：**
在 **Psy 已开放的 ProgramV1 子集** 上，DPN **可以目标 “全覆盖”**（上表 `Y`/`P` 列）。
扩展到 **全部 DPN op** 或 **全部 PSL 语法** **不是** 本规划完成条件。

---

## 4. 架构切片

### 4.1 模块（建议）

```text
ProofForgeV2/Targets/Psy/
  Dpn/
    SchemaV1.lean      # OpType / DataType / StateCmd / FunctionDef 精确枚举与编码
    EncodeJsonV1.lean  # sole JSON 序列化（与 dargo package JSON 对齐）
    LowerPlanV1.lean   # PsyPlan → Array FunctionDef
    ValidateDpnV1.lean # 内部一致性（id 范围、resolution 长度、view 只读）
  EmitIRV1.lean        # 过渡：.psy 旁路；DPN 稳定后降级为 debug-only
```

### 4.2 与现有 Plan 关系

- **保留** `PsyPlan` 作为 target-owned 中间层（可读、可测、与现 ValidatePlan 兼容）。
- **新增** `plan → DPN` 为产品权威物化；或 `Semantic → DPN` 若 Plan 字段不足再补 Plan。
- **Finalize**：短期仍可包装 `.psy` 文件；中期 artifact 增加 `*.dpn.json` / package JSON；`deployable=false` 不变直至 UPS 决策。

### 4.3 验证阶梯

| 阶 | 门 | 状态 | 完成标准 |
|---|---|---|---|
| G0 | Schema + 金样 decode | **done（DPN-1）** | Counter dargo JSON round-trip / 字段钉死 |
| G1 | Lower Counter | **done（DPN-2）** | 我们生成的 DPN JSON 与 dargo 金样 **结构相等** |
| G2 | Accumulator / OptionState / LoopSum | **partial（DPN-3/4）** | Plan→DPN 结构门（LoopSum/OptionState）；**非** runtime 差分同 oracle |
| G3 | WideCounter VM | **done（DPN-4 + G5-WIDE）** | multi-leaf + UInt128 add + schoolbook mul + restoring div/mod + limb shift DPN |
| G4 | Map / 聚合 | **done（DPN-5）** | MapMini+Token Plan→DPN；.psy 破点绕过 |
| G5 | 全 admit 面扫描 | **partial（G5-WIDE done）** | mul/div/shift 已 DPN；Array/Principal/Bytes 产品金样 + hard-require 仍 open |
| G6 | Execute 消费 DPN | **open** | 不经 `.psy` 文本：`psy_vm` 或 dargo 可接受路径 |

G0–G1 + dual-write（DPN-7）为 **engineering MVP 已闭合**；G5 为 **“ProgramV1 admit 面全覆盖”** 声明门槛；G6 为 **去文本依赖**。
---

## 5. 分阶段实现（建议顺序）

### Phase DPN-0 — 规划与 pin（本文档）

- [x] 选定 DPN 为权威物化层
- [x] 文档钉死 `psy-node` rev `79e0b824…` 与 dargo 0.1.0 对齐关系（本规划 § 权威上游 pin）
- [x] 金样文件入库策略：`testdata/golden/psy-dpn-v1/counter-package.v1.json` + `PsyDpnV1` pin
- [ ] Tool Lock 独立条目镜像同一 rev（可选硬化；runtime 仍走 dargo 0.1.0 pin）

### Phase DPN-1 — Schema + Counter 金样

- [x] Lean：`SchemaV1` / `JsonCodecV1`（OpType/DataType/StateCmd 子集 / FunctionDef）
- [x] 金样：`testdata/golden/psy-dpn-v1/counter-package.v1.json`（dargo Counter）
- [x] 测试：`PsyDpnV1` decode≡手建 + encode round-trip

### Phase DPN-2 — Lowering MVP（UInt64 Counter 形）

- [x] `LowerPlanV1`：init store(param) / checkedAdd store+return / view load
- [x] method_id **金样 pin**（initialize/increment/get）
- [x] product Plan → package ≡ full Counter dargo golden
- [ ] method_id 官方 hash 复刻（可选硬化）

### Phase DPN-3 — 控制流与有界循环

- [x] if/match → Select + conditional `SetContractStateSlotSingle`（`LowerPlanV1` general builder；switch→nested if+eq+Select return merge）
- [x] bounded for → 静态 unroll（与 EmitIRV1 PSY-LOOP 一致：`boundExceeded` + N 步 `i=start+k`/`i<end` 门控 body；maxIter≤64；超预算 FC）
- [x] 结构测试：`PsyDpnV1` if/switch/for + `Examples/LoopSum` product Plan→package；Counter 金样仍绿

### Phase DPN-4 — 多叶与宽整数

- [x] multi-leaf `storeAggregate` / `returnAggregate` → multi `Get/Set … SlotSingle`（engineering sub_slot = fieldIndex+4，对齐 WideCounter dargo 证据；单叶 Counter 模板保持金样）
- [x] OptionState 产品 Plan→DPN（双叶 tag+payload）；手建 4-limb UInt128 init/get/add（limbAdd/Select/overflow assert + u32 param range）
- [x] UInt128 **仅** `psy-dargo-0.1.0-vm-v1`（默认 profile 在 Plan 层 FC）
- [x] **G5-WIDE（2026-08-08）**：`bindWideUintMul` schoolbook 8×UInt16（U32And/U32ShiftRight + Target Mul/Add + `u128 mul overflow`）；`bindWideUintDivMod` 四段×32 步 restoring 全展开（limb range + zero-div + internal asserts；无 Felt `/`/`%`）；`bindWideUintShift` 固定 128-step bit walk（U32Shift*/U32Or + Select；`invalidShift`/`u128 shl overflow`）；per-limb `bitAnd`/`bitOr`/`bitXor` 经 U32+CastFelt；WideCounter VM product Plan→DPN；UInt256 同算法路径（limbCount=8）已接通、产品金样可选
- [ ] Array/Struct/Principal/Bytes 产品金样与 dargo 全量 package 相等（结构已由 multi-leaf Single 路径覆盖）

### Phase DPN-5 — Map 与现 .psy 破点

- [x] Map cap-8 全在 DPN 表达（Plan 已 expand IndexGet→Option Select + IndexSet upsert `storeAggregate` + map-full assert；`LowerPlanV1` general builder 直接消费 Select/Bool/compare/multi-leaf Set；`maxStateLeavesV1=64`）
- [x] 回归：`PsyDpnV1` MapMini/Token product Plan→package + 手建 lookup/upsert 结构门；**不**经 dargo return-in-if `.psy` 路径
- [x] Nested Map / Map return 保持 Plan FC（非 DPN 发明）
- [ ] dargo MapMini package 金样相等（可选；dargo 仍破 return-in-if，无官方 JSON pin）

### Phase DPN-6 — 效果族诚实矩阵

- [x] emit / call：仅 PARTIAL 有证据时写 DPN；否则 FC
  - `emitEvent` → `DPNEventRecord`（condition + GetCheckpointId/GetUserId/GetContractId + data；官方 `emit_event` 形状；无 Finalize ordered-event 门）
  - void `externalCall` → `InvokeExternalContractFunctionSync`（`num_outputs=0`；FNV 组件 hash 对齐 EmitIR `__invoke_sync` PARTIAL；无部署地址/response/runtime 门）
- [x] schedule / assets / context / invariant：保持 FC
  - `schedule` DPN 深度防御稳定诊断（不 alias InvokeSync）；assets/ContextRead/Commit/nonempty invariant 仍 Plan FC
  - `PsyDpnV1` 钉手建 + product emit/call PARTIAL 与 schedule FC

### Phase DPN-7 — 产品切换

- [x] `emitFromIR` / `buildFromCapability` dual-write：`{name}.dpn.json`（package JSON，Plan→DPN 成功时 **primary**）+ 过渡 `{name}.psy`（always / residual-only when DPN lower 未 admit）
- [x] Finalize 证据注记：DPN JSON + transitional `.psy`；zero-tool；`deployable=false`
- [x] `PsyDpnV1` pin：Counter product dual-write package ≡ golden + `.psy` 非空
- [ ] residual Plan 形状 hard-require DPN（G5；当前 dual-write 过渡对未 lower 形状仅 `.psy`）
- [ ] 删除 `.psy` 权威路径（deletion-gate；现为 debug/transition）
- [ ] `just psy-runtime` 优先 DPN 路径（仍经 `.psy`→dargo；不经 product Finalize）

---

## 6. method_id / 布局约定

- **method_id**：优先复刻官方 hash（`psy_crypto::hash::utils::gen_dapen_contract_function_method_id`）；若 Lean 侧不便链接，则 **金样锁定** 已知方法 id，并单独 TASK 做跨语言 pin。
- **slot / sub_slot**：与现 Emit 一致——4 Felt/leaf；UInt64 占一个 sub-slot 策略与 dargo 金样对照后冻结。
- **condition**：无条件写 → ConstantTrue 的 encoded id（Counter 金样：`4294967296`）。

---

## 7. 风险与诚实边界

| 风险 | 缓解 |
|---|---|
| rev 漂移导致 op 码变化 | pin rev；schema 测试；未知 `op_type` fail closed |
| method_id 算法不一致 | 金样 + 官方函数对照 |
| 与 Reference 语义漂移 | 每族 Reference oracle + DPN execute（有工具时） |
| 范围膨胀到全 PSL/全 DPN | 完成条件锁在 §3.1 |
| 双路径 (.psy + DPN) 分裂 | 过渡期 dual-write 比较；稳定后删 .psy 权威 |

**成熟度**：DPN 路径落地后，registry 仍可 **source-only / non-deployable**，直到 UPS/网络决策。
**不得** 把 “DPN JSON 生成成功” 写成 formal / hermetic / 主网。

---

## 8. 与文档/backlog 的衔接

| 文档 | 作用 |
|---|---|
| 本文 | 规划与覆盖定义 sole 输入 |
| [`10-psy.md`](10-psy.md) | 产品边界摘要 + 指向本文 |
| [`engineering-backlog.md`](../engineering-backlog.md) | `PSY-DPN-*` 可勾选切片 |
| [`AGENTS.md`](../../AGENTS.md) | Active/Next task 指针 |
| 实现日志 | 每 Phase 完成后追加事实 |

---

## 9. 完成条件（Definition of Done）

### 9.1 MVP（DPN-2）

- Counter 产品路径产出 DPN JSON，与 locked-dargo 金样结构相等。
- 测试进 ordinary 或 targets shard（不强制 host-heavy execute）。
- 文档声明 `.psy` 为过渡旁路。

### 9.2 Admit 面全覆盖（DPN-5 + 矩阵 G5）

- §3.2 中所有 **Y** 行有 DPN lowering + 测试。
- 所有 **P/F** 行有稳定诊断或 PARTIAL 文档。
- Map 等不再依赖破损 `.psy` 路径。

### 9.3 非完成条件

- 官方 PSL 全语法。
- UPS/节点/RPC。
- formal TASK / Stage-0。

---

## 10. 下一步（DPN-1..7 + G5-WIDE 已闭合后）

1. **G5 residual**：Array/Principal/Bytes 产品金样；§3.2 每条 Y/P 有 DPN 或显式 FC；optional hard-require DPN for all Psy Plan admits；WideCounter256 product package pin（可选）。
2. **G6 / deletion-gate（可选）**：`.psy` 删除或 debug-only；`just psy-runtime` DPN-first（不经 product Finalize 改 claim）。
3. **可选硬化**：method_id 官方 hash 复刻；Tool Lock 镜像 `psy-node` rev。

规划 owner：engineering。
产品决策 implicit：用户已确认 “对准 DPN 层” 与 “ProgramV1 admit 面尽量全覆盖到 DPN target”。
