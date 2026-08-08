---
id: TARGET-PSY-DPN
title: Psy DPN lowering plan (ProgramV1 → DPNFunctionCircuitDefinition)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Psy DPN 层落地规划

状态：`draft`（规划输入；DPN-1..7 engineering 已落地；**G5-WIDE** mul/div/shift + **G5-AGG** Array/Principal/Bytes/Struct multi-leaf + **G5-MATRIX** §3.2 admit 扫描/FC pins + **G5-HARD** residual allowlist / non-residual materialize hard-fail 已闭合；**R-NARROW** UInt8/16/32 守卫算术 DPN lower 已闭合；**R-INT** Int64 signedCompare/checkedNeg + Int{8,16,32} two's-complement signed 算术/比较 DPN lower 已闭合；**R-SHIFT-BIT** UInt64 shl/shr + checkedBitNot DPN lower 已闭合；**R-PURE** pureFn/localCall callFn inline DPN lower 已闭合；**R-HARD** narrow bitwise/shift + Goldilocks Field DPN lower + residual allowlist 已清空（full hard-require）；**G6-DEBUG** 产品默认仅 `{name}.dpn.json`，`.psy` 为 opt-in debug（`PROOF_FORGE_PSY_EMIT_PSY=1` / `emitPsyDebug`）；**G6-RUNTIME** DPN-first plant + PARTIAL `.psy` execute（locked dargo 0.1.0 无 package-only 标志）；**G6-PIN** WideCounter256 VM product Plan→DPN 结构 pin 已闭合；全量 dargo package 字节金样 **有意 deferred**（见 §10））
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
**DPN 现状**（G5-MATRIX + G5-HARD + R-HARD 2026-08-08）：`done` = 有 DPN lower + 自动化钉测；`residual` = **无**（R-HARD 后 allowlist 已空）；`plan-FC` = Plan/resolver 已 FC（达不到 DPN）；`partial` = PARTIAL 诚实编码。Plan-admitted 但 DPN lower 失败 → 产品 **`PSY-DPN-G5-HARD` materialize FC**（禁止 silent `.psy`-only）。

| ProgramV1 / Semantic 族 | 现 .psy 路径 | DPN 目标 | DPN 现状 | 证据（测试 / 路径） |
|---|---|---|---|---|
| UInt64 算术 + overflow assert | Y | **Y** | **done** | Counter 金样 add；`testCheckedSubMulDivModLower` sub/mul/div/mod |
| Bool / 比较 / 逻辑 | Y | **Y** | **done** | `testBoolCompareLogicalLower`；Map/if 路径复用 |
| UInt8/16/32 守卫算术 | Y | **Y** | **done** | R-NARROW：`testNarrowCheckedArithLower` + `testUInt8ProductDualWriteDpn` |
| UInt8/16/32 bitwise/shift/bitNot | Y | **Y** | **done** | R-HARD：`testNarrowCheckedArithLower` narrow bit* pins + `testUInt8NarrowBitwiseProductDualWriteDpn` |
| Int64 / 窄 Int | Y/P | **Y/P** | **done** | R-INT：`testSignedIntLower` + `testInt8ProductDualWriteDpn`；Int64 arith 复用 UInt64 checked 路径；signedCompare/neg + narrow two's-complement DPN |
| UInt128/256（显式 VM profile） | Y | **Y** | **done** | G5-WIDE + WideCounter VM product；default profile Plan FC |
| Field goldilocks | Y | **Y** | **done** | R-HARD：`testGoldilocksFieldProductDualWriteDpn`（native Target add/sub/mul/div，无 UInt64 overflow assert） |
| Field bn254 | F | **F** | **plan-FC** | `PsySourceV1.testFieldBn254FailClosed` |
| Principal / String / Bytes 叶 | Y/P | **Y/P** | **done**（state 叶）/ **plan-FC**（return） | G5-AGG Principal/Bytes product；String 同 wire 9 叶；return 9>cap FC |
| named Struct/Enum flatten | Y | **Y** | **done** | `testStructPairProductLower` / dual-leaf hand-built |
| Array UInt64 / Option UInt64 | Y | **Y** | **done** | G5-AGG Array + DPN-4 OptionState product |
| Map UInt64 UInt64 cap-8 | Plan Y；dargo 破 | **Y** | **done** | DPN-5 MapMini/Token product |
| 嵌套 Map / Map return | F | **F** | **plan-FC** | `testNestedMapStateFailClosed`；PsySource nested/return |
| let / assign / return | Y | **Y** | **done** | Counter / 通用 store+returnValue |
| if / match | Y | **Y** | **done** | DPN-3 if/switch + LoopSum |
| bounded for UInt64 | 静态 unroll Y | **Y** | **done** | DPN-3 unroll + over-budget FC |
| while / 无限循环 | N | **F** | **plan-FC** / budget FC | ProgramV1 无 while；`testBoundedForOverBudgetFailClosed` |
| pureFn / localCall | Y | **Y** | **done** | R-PURE：`testCallFnPureInlineLower` + `testPureFnProductDualWriteDpn`（callFn inline 进 caller；pureHelper 不进 package；`.psy` 仍 emit free helper） |
| const / Op.Constant | Y | **Y** | **done** | `testConstProductLower` → DPN Constant |
| bare assert / zero-arg revert | Y | **Y** | **done** | `testBareAssertAndRevertLower`（含 zero-arg revertError） |
| payload error | F | **F** | **done**（DPN FC） | `testPayloadRevertErrorFailClosedAtDpn`；Plan PSY-TYPED-ERROR |
| emit | PARTIAL | **P** | **partial** | DPN-6 events[] product |
| void call | PARTIAL | **P** | **partial** | DPN-6 InvokeExternal product |
| result-bearing call | F | **F** | **plan-FC** | `PsySourceV1.testResultBearingCallFailClosed` |
| schedule | F | **F** | **done**（DPN FC） | `testScheduleFailClosedAtDpn` |
| ContextRead / Commit | F | **F** | **plan-FC** | PsySource context/commit FC |
| nonempty invariant Plan | F | **F** | **plan-FC** | PsySource nonempty invariant FC |
| pf.assets | F | **F** | **plan-FC** | `PsyPfAssetsV1` 零绑定 |
| 元组 / 闭包 / trait / mod | N | **N/F** | **N** | 非 ProgramV1 作者面 |

#### 3.2.1 G5-MATRIX 覆盖表（扫描结论）

| 桶 | 行数 | 说明 |
|---|---|---|
| **done / partial** | 全部 Y + 两 P | 有 DPN lower 或诚实 PARTIAL + `PsyDpnV1` 钉测 |
| **residual** | **0** | R-HARD 后 `isPsyDpnG5HardResidualAllowlistV1` 恒 false；无 `.psy`-only residual 路径 |
| **plan-FC** | bn254 Field、nested Map、result-bearing call、Context/Commit、invariant、assets… | 产品 Plan 前拒绝；不发明 DPN |
| **open residual work** | 全量 dargo package 字节金样 / method_id 官方 hash | **R-*** + **G6-DEBUG** + **G6-RUNTIME** + **G6-PIN** done（2026-08-08）；WideCounter256 结构 pin 已合；全量 dargo 字节金样 **deferred**（见 §10） |

**结论（规划层 + G5-MATRIX + R-HARD + G6-DEBUG 事实）：**
在 **Psy 已开放且 Plan admit 的子集** 上，物化 **必须** 产出 `.dpn.json` primary，或 `PSY-DPN-G5-HARD` fail；`.psy` 仅 opt-in debug（env / `emitPsyDebug`）；**plan-FC** 族不经 DPN 旁路。
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
| G3 | WideCounter VM | **done（DPN-4 + G5-WIDE + G6-PIN）** | multi-leaf + UInt128 add + schoolbook mul + restoring div/mod + limb shift DPN；**G6-PIN** WideCounter256 8-limb product 结构 pin |
| G4 | Map / 聚合 | **done（DPN-5）** | MapMini+Token Plan→DPN；.psy 破点绕过 |
| G5 | 全 admit 面扫描 | **done（G5-WIDE + G5-AGG + G5-MATRIX + G5-HARD + R-HARD）** | §3.2 每行 DPN 钉测或 plan-FC；residual 桶 **0**；allowlist 空 + materialize hard-require；全量 dargo 字节金样 **deferred**（§10） |
| G6 | Execute 消费 DPN | **partial（G6-DEBUG + G6-RUNTIME + G6-PIN done）** | 产品默认 DPN-only；runtime DPN-first plant `target/<pkg>.json`；locked dargo 0.1.0 execute 仍强制 `.psy`（PARTIAL；无 package-only 标志）；WideCounter256 结构 pin |

G0–G1 + dual-write（DPN-7）为 **engineering MVP 已闭合**；G5 为 **“ProgramV1 admit 面全覆盖”** 声明门槛；**G6-DEBUG** 已使 `.psy` 非 default；**G6-RUNTIME** 已将 `just psy-runtime` 切 DPN-first plant + PARTIAL `.psy` execute；**G6-PIN** 已钉 WideCounter256 结构 package。
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
- [x] **G5-WIDE（2026-08-08）**：`bindWideUintMul` schoolbook 8×UInt16（U32And/U32ShiftRight + Target Mul/Add + `u128 mul overflow`）；`bindWideUintDivMod` 四段×32 步 restoring 全展开（limb range + zero-div + internal asserts；无 Felt `/`/`%`）；`bindWideUintShift` 固定 128-step bit walk（U32Shift*/U32Or + Select；`invalidShift`/`u128 shl overflow`）；per-limb `bitAnd`/`bitOr`/`bitXor` 经 U32+CastFelt；WideCounter VM product Plan→DPN；UInt256 同算法路径（limbCount=8）已接通
- [x] **G6-PIN（2026-08-08）**：`Examples/WideCounter256` 显式 VM profile product Plan→DPN **结构** pin（8 Sets sub_slot 4..11；`u256 mul overflow` / `u256 div by zero` / `u256 mod by zero` / `invalidShift: count >= 256` / `u256 shl overflow` / U32Shift*；default profile FC）；**非** locked-dargo 全量 package 字节相等
- [x] **G5-AGG（2026-08-08）**：Array UInt64 N / Principal wire-identity（len+8×UInt32）/ Bytes 1..8 / named Struct flatten → multi `SlotSingle` via existing `storeAggregate`/`returnAggregate`（sub_slot=`fieldIndex+4`）；`PsyDpnV1` 手建 + product Plan→DPN；Nested Map / Map return / Principal return 保持 Plan FC
- [ ] Array/Struct/Principal/Bytes 与 locked-dargo 全量 package 字节相等（可选；结构已由 multi-leaf Single 路径 + G5-AGG 产品门覆盖）

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

- [x] `emitFromIR` / `buildFromCapability`：`{name}.dpn.json`（package JSON，Plan→DPN 成功时 **primary / default sole**）
- [x] Finalize 证据注记：DPN JSON primary；`.psy` debug-only；zero-tool；`deployable=false`
- [x] `PsyDpnV1` pin：Counter product default package ≡ golden、无 `.psy`；`emitPsyDebug` dual-write
- [x] **G5-HARD（2026-08-08）**：gated residual policy 地基 — 非 residual DPN lower 失败以稳定 `PSY-DPN-G5-HARD` fail materialize（禁止 silent incomplete product）；`buildFromPlanV1` + `PsyDpnV1` 钉测
- [x] **R-NARROW（2026-08-08）**：UInt8/16/32 Felt-carried checked add/sub/mul/div/mod + entry param range + unsigned compare → DPN（mirror EmitIR；`result < 2^w`；产品 DPN-only default）
- [x] **R-INT（2026-08-08）**：Int64 `signedCompare`/`checkedNeg` + Int{8,16,32} two's-complement narrow signed add/sub/mul/div/mod/neg/compare → DPN（mirror EmitIR；bias-2^(w-1) compare；overflow asserts；产品 Int8 DPN）；Int64 arith 复用既有 UInt64 checked path
- [x] **R-SHIFT-BIT（2026-08-08）**：UInt64 `shl`/`shr` + `checkedBitNot` → DPN（mirror EmitIR `invalidShift: count >= 64` / bitNot representability；dargo Felt `<<`/`>>` → U32ShiftLeft/Right + CastFelt；checkedBitNot = Gte `2^32−1` + Sub mask `2^32−2`；产品 ShiftBit DPN）
- [x] **R-PURE（2026-08-08）**：pureFn/localCall callFn → DPN inline 进 caller；pureHelper 不进 package；product DPN
- [x] **R-HARD（2026-08-08）**：narrow bitwise/shift/bitNot + Goldilocks Field expr → DPN（mirror EmitIR）；`isPsyDpnG5HardResidualAllowlistV1` **恒 false**（full hard-require）
- [x] **G6-DEBUG（2026-08-08）**：产品默认 **仅** `{name}.dpn.json`；过渡 `{name}.psy` 仅 opt-in（`emitPsyDebug := true` 或 env `PROOF_FORGE_PSY_EMIT_PSY=1`）；EmitIR `.psy` lower 保留 gated；`deployable=false`
- [x] **G6-RUNTIME（2026-08-08）**：`just psy-runtime` / `PsyAcceptance` / `psy_acceptance.sh` DPN-first — 默认产品 build 要求 sole `{name}.dpn.json`、package-shape 校验、plant 为 `target/<package>.json`；method names ⊆ post-compile package；**PARTIAL**：locked dargo 0.1.0 无 package-only execute/compile 标志（`execute` 只 *写* package JSON，始终重编译 `.psy`），local-VM 差分仍 `PROOF_FORGE_PSY_EMIT_PSY=1`；不经 product Finalize；`deployable=false`
- [x] **G6-PIN（2026-08-08）**：WideCounter256 VM product Plan→DPN **结构** pin（`PsyDpnV1`）；全量 dargo package 字节金样 **deferred**（包体膨胀 + 无 package-only dargo 路径；Counter 仍为 sole 全量字节金样；见 §10）

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

- §3.2 中所有 **目标 Y** 行：DPN lowering + 测试（**done**）；R-HARD 后 **无 residual 桶**。
- 所有 **P/F** 行有稳定诊断或 PARTIAL 文档（`PsyDpnV1` 与/或 `PsySourceV1`）。
- Map 等不再依赖破损 `.psy` 路径。
- **G5-MATRIX（2026-08-08）** 已闭合扫描：覆盖表见 §3.2 / §3.2.1。
- **G5-HARD（2026-08-08）** 已闭合 gated residual policy 地基。
- **R-HARD（2026-08-08）** 已闭合 full hard-require：allowlist 空；Plan-admitted DPN 失败 → `PSY-DPN-G5-HARD`。

### 9.3 非完成条件

- 官方 PSL 全语法。
- UPS/节点/RPC。
- formal TASK / Stage-0。
- 完整去 dargo 文本依赖的 package-only execute（G6-RUNTIME 已 PARTIAL 诚实：dargo 0.1.0 仍强制 `.psy`）。

---

## 10. 下一步（DPN-1..7 + G5 + R-HARD + G6-DEBUG + G6-RUNTIME + G6-PIN 已闭合后）

1. **G6-RUNTIME（2026-08-08 done，PARTIAL）**：`scripts/psy_runtime_test.sh` 先跑默认 DPN-only product build + plant `target/<pkg>.json`；execute 差分仍 opt-in `.psy`（locked dargo 无 package-only 标志；不发明 CLI flag）。`PsyAcceptance`/`psy_acceptance.sh` 同步 plant + method ⊆ 检查。
2. **G6-PIN（2026-08-08 done）**：`PsyDpnV1` 钉 `Examples/WideCounter256` VM product Plan→DPN 结构（8-limb init Sets、u256 mul/div/mod/shift asserts、get 8 outputs、encode 为合法 JSON 数组；default profile FC）。**不是** full package 字节金样。
3. **全量 dargo package 字节金样 — deferred（诚实理由，非漏做）**：
   - **sole 全量字节金样**仍为 `testdata/golden/psy-dpn-v1/counter-package.v1.json`（locked-dargo Counter，三方法、小包、结构+字节双钉）。
   - WideCounter / WideCounter256 的 DPN 为 **全展开** schoolbook mul + restoring div + `bitWidth`-step shift；UInt256 包体相对 Counter 极大，把 exact UTF-8 字节当 CI 金样会膨胀仓库与 diff 噪声，且与 “结构 pin 已覆盖 admit 面” 的价值不成比例。
   - locked dargo 0.1.0 **无 package-only** compile/execute：`execute` 只 *写* package 并始终重编译 `.psy`，因此无法在不经文本路径的前提下从官方工具链稳定抓取 “sole DPN 权威” 的 multi-method 宽整数金样；MapMini 等路径 dargo 仍破 return-in-if，更无法生成官方 Map package 金样。
   - method_id：**Counter 三方法**已 pin 官方 id；其余方法用 engineering FNV-1a（`engineeringMethodIdV1`），**非** `gen_dapen_contract_function_method_id` 跨语言复刻——后者属可选硬化，需 psy_crypto/官方 pin，不阻塞 DPN-primary product。
   - 何时可 revisit：上游 dargo 增加 package-only 消费、或 Tool Lock 增加可复现的 multi-host dargo package 抓取流水线；届时优先仍应先 pin **小包**（Counter 已有）再考虑宽整数子集。
4. **仍 optional**：method_id 官方 hash 复刻；Tool Lock 镜像 `psy-node` rev；若上游 dargo 增加 package-only execute，再去掉 `.psy` PARTIAL。

规划 owner：engineering。
产品决策 implicit：用户已确认 “对准 DPN 层” 与 “ProgramV1 admit 面尽量全覆盖到 DPN target”。
