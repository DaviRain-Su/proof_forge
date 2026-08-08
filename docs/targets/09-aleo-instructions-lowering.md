---
id: TARGET-ALEO-INSTRUCTIONS
title: Aleo Instructions IR lowering plan (ProgramV1 → Aleo Instructions)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Aleo Instructions IR 落地规划

状态：`draft`（**IR-0..IR-7 engineering closeout 2026-08-08** + **G5-MATRIX 2026-08-08** + **G5-HARD 2026-08-08**：G0–G6 闭合；G6/IR-7 = runtime honesty **PARTIAL + MISSING**（无 locked snarkVM/package-only execute；`just aleo-runtime` → `PF-TOOLCHAIN-MISSING`；不发明 CLI）。residual 桶 Int64/Field/pureFn true lower；空 allowlist + `ALEO-IR-G5-HARD` 禁 silent Leo-only primary。Schema/TextCodec + Counter 金样 + `LowerPlanV1` + if/match/bounded-for + multi-leaf + narrow + 效果诚实矩阵 + **产品 primary = Instructions**。**Next = RES-CLEAN**；full opcode / record / prove 仍 open。`deployable=false`）
目标：在 **不改变 ProgramV1 可移植业务语义** 的前提下，把 Aleo target 的权威物化从 **Leo 4 源文本** 切到官方 **Aleo Instructions**（中间 IR / 寄存器指令集），并评估 **ProgramV1 在 Aleo 上 admit 的构造** 能覆盖到该 IR 的范围。

与 Psy 对照（已闭合 lane）：

| | Psy | Aleo（本规划） |
|---|---|---|
| 旧 sole 权威 | 文本 `.psy` | Leo 4 源（工程文件名 `{id}.aleo`） |
| 新 sole 权威 | `DPNFunctionCircuitDefinition` package | **Aleo Instructions** 程序文本/结构 |
| 官方管道 | dargo 源 → DPN JSON | Leo → **Instructions** → AVM bytecode |
| 工具 pin | dargo 0.1.0 | Leo **4.0.2**（Tool Lock 已有） |
| 作者语言 | sole ProgramV1 | 同左（不改） |

权威上游（规划 pin；实现切片再钉 exact 文档/grammar rev）：

| 项 | 值 |
|---|---|
| 语言名 | **Aleo Instructions**（AVM 寄存器 IR） |
| 官方说明 | [Aleo Instructions Overview](https://docs.aleo.org/build/aleo-instructions/overview) |
| 官方管道 | `Leo source → Aleo Instructions (.aleo) → AVM bytecode (.avm)` |
| 语法 | [ProvableHQ/grammars](https://github.com/ProvableHQ/grammars) ABNF；opcode 见 Instructions Reference |
| 工程对照金样 | locked **Leo 4.0.2** `leo build --offline` 对同一子集产出的 **compiled instructions**（现产品 `*.compiled.aleo` extras） |
| 非本阶段 | snarkVM prove/deploy、网络 `leo query`、CRS、主网 |

**命名诚实（仓库现状 vs 官方术语）：**

| 制品 | 当前工程含义 | 本规划目标含义 |
|---|---|---|
| 产品 base `{id}.aleo` | **Aleo Instructions** 文本（Plan→`LowerPlanV1`；IR-6 + G5-HARD） | **产品权威**（Plan admitted 且 IR fail → `ALEO-IR-G5-HARD`；无 silent Leo-only） |
| 调试/对照 `{id}.leo` | Leo 4 源（`EmitIRV1` printer；env/`emitLeoDebug`/compile 双写） | debug / leo-build compare；**非**长期 sole 权威 |
| Finalize extra `{id}.compiled.aleo` | locked Leo 编译输出（**Instructions** 面） | **金样/对照**（IR-1/IR-6 compare path） |
| 产品目标权威 | **Plan → Instructions** 直出（IR-6） | 可选 Leo 对照；AVM 消费待 G6 |

**非目标（本规划明确排除）：**

- 把完整 **Leo 语言手册** 变成 ProofForge 作者语言（仍 sole `program … where` / ProgramV1）。
- 在产品 Finalize 内默认 prove / deploy / network query / hermetic Stage-0。
- 一步到位 **AVM bytecode** 或 snarkVM 内部 Program 对象（可作为后续 IR-N，非 MVP）。
- record custody / `pf.assets` 在 account-vault 语义下的假绑定（保持现 disposition FC，直至 custody v2 决策）。
- 声称 “全部 Aleo Instructions opcode 已支持”。

---

## 1. 动机

当前 Aleo 路径：

```text
ProgramV1 → Semantic → AleoPlan → Leo AST → 文本 Leo 源（{id}.aleo）
                              └─ 可选：leo build → compiled.aleo（Instructions）+ abi + program JSON
```

问题（与 Psy 源文本时代同构）：

1. **脆性**：与 Leo 4 源语法/保留字/cast/final 形态耦合；Leo 升级逼改 printer。
2. **双重真相**：业务语义在 Semantic/Plan；AVM 真正吃的是 **Instructions**（及后续 bytecode），Leo 是第三方言。
3. **覆盖度量失真**：KPI 若写成 “能 emit Leo”，会逼高阶语法；正确 KPI 是 **admit 面在 Instructions 上可诚实编码**。
4. **compile-only 已给金样入口**：ALEO-I4 已能产出 `compiled.aleo`，可作 IR 对照，却未成为产品权威。

目标路径：

```text
ProgramV1 → Semantic → AleoPlan → AleoInstructionsIR / program text
                │                      │
                │                      ├─ ≡ locked-leo compiled instructions（金样）
                │                      ├─ 可选：调试 Leo 源（非权威）
                │                      └─ 后续：snarkVM / local execute 消费 Instructions
                └─ 现有 Leo 发射在 IR 主路径稳定前保留为过渡旁路
```

---

## 2. Aleo Instructions 目标模型（实现必须对齐）

### 2.1 程序级形状（概念）

官方示例级结构（非完整 grammar）：

```text
program <name>.aleo;

// imports / mappings / records / structs …（子集白名单）

function <name>:
    input rK as <type>.<visibility>;
    <opcode> ... into rN;
    output rM as <type>.<visibility>;

// finalize / mapping ops 在 public finalization 路径（与 proof fn 分叉）
```

要点：

- **寄存器** `r0, r1, …`，静态类型。
- **可见性** `public` / `private` / `constant`（与 ProgramV1 Visibility / disclosure 对齐时必须 fail closed 于无映射）。
- **function** 体是线性指令序列（非 Leo 高级 `if`/`for` 源语法）；控制流由 Leo 编译器 lowering 结果决定——我们自 lower 时须 **显式** 产生等价指令序列（或诚实 FC）。

### 2.2 双上下文（Aleo 特有；相对 Psy 更硬）

| 上下文 | 典型内容 | ProgramV1 对应（首批） |
|---|---|---|
| **Proof / private function** | 算术、断言、private 输入输出 | pure 计算、checked 算术、部分 view |
| **Finalize / public** | mapping get/set、public 状态转换 | public state load/store、init/entry 写 mapping |

**纪律：** 不得把 mapping 写进“假 private-only”单上下文糊弄；无诚实 final 分叉则 **Plan/IR FC**。

### 2.3 首批 opcode / 构造白名单（可扩展）

MVP 候选（以 locked Leo 4.0.2 对 Counter 形编译结果 **实测冻结** 为准，下列为规划假设）：

- 字面量 / cast / `add` `sub` `mul` `div` `rem`（及 checked 语义与 Leo trap 对齐处）
- 比较与 ternary / 分支展开结果
- `assert` / `assert.eq` 等（以金样为准）
- mapping `get` / `get.or_use` / `set`（public final 路径）
- `input` / `output` 与可见性

**默认拒：** record mint/consume、program call 全表、async/Future 旧模型、未映射 crypto/group、任意新 opcode best-effort。

### 2.4 金样权威

Linux/Darwin locked Leo 4.0.2（Tool Lock 已 pin）：

1. 现路径：`build → Leo 源 → leo build --offline` → `*.compiled.aleo`
2. IR 路径：`build → Instructions`（我们发射）
3. **结构相等** 或规范化后相等（空白/寄存器重命名策略在 IR-1 冻结）

首金样：`Examples/Counter`（或 Aleo 已 admit 的最小 public UInt64 mapping counter）。

Pin：Leo **4.0.2** exact；grammar/opcode 文档 rev 写入 supply-chain annotation（实现切片）。

---

## 3. 覆盖目标：什么叫 “全覆盖”

### 3.1 定义

> **DSL 自有特性**（ProgramV1）在 **Aleo 已 admit** 的构造，最终都要有 **确定性 Aleo Instructions 编码**；
> **不 admit** 的，在 Normalize / Plan / IR 边界 **稳定诊断（证据化 FC）**，且 **不** 经 Leo 旁路偷偷实现。

**不是：** 全 Leo 语法、全 Instructions opcode、全 AVM、prove/deploy 完成。

### 3.2 覆盖矩阵（G5-MATRIX 扫描 2026-08-08）

图例：`Y` = 目标 Y；`P` = PARTIAL；`F` = 证据化 FC；`N` = 非作者面。
**现 Leo 路径** = Leo printer / Plan 现状；**IR 目标** = 规划目标（不得假 Y）。
**Instructions 现状**（G5-MATRIX）：`done` = Plan→Instructions lower + 自动化钉测；`residual` = Plan/Leo 可 admit 但 Instructions **稳定 ALEO-IR FC** + 钉测（**禁止**写成 done）；`plan-FC` = Semantic/Plan/resolve 已 FC（达不到 Instructions）；`partial` = 有界 PARTIAL（当前无）。

| ProgramV1 / Semantic 族 | 现 Leo 路径 | IR 目标 | Instructions 现状 | 证据（测试 / 路径） |
|---|---|---|---|---|
| UInt64/32/8 算术 + checked | Y（原生 uN trap） | **Y** | **done** | Counter golden add；`testProductNarrowUintWidths` / `testHandBuiltNarrowShiftCast` |
| Bool / 比较 / 逻辑 | Y | **Y** | **done** | `testG5MatrixBoolAssertStructural`（gt/and/not/ternary）；Branch product gt |
| Int64 | Y | **Y** | **done** | G5-HARD i64 mapping + signed ops；`testG5HardResidualTrueLower` |
| Field BLS12-377 | Y（T14） | **Y** | **done** | G5-HARD field mapping + fieldBinary；`testG5HardResidualTrueLower` |
| Field bn254 / Goldilocks | F | **F** | **plan-FC** | type-closure；`Aleo.testFieldBn254FailClosed` |
| mapping state / dense Map cap-2 | Y | **Y** | **done** | Counter mapping；`testProductMapMiniMultiLeaf` |
| Option UInt64 state | Y | **Y** | **done** | `testProductOptionStateMultiLeaf` |
| Array/Bytes/Struct flatten | Y | **Y** | **done** | `testProductArrayMultiLeaf` / multi-leaf hand-built |
| if / match / bounded for | Y（Leo 源） | **Y** | **done** | IR-3 structural + product Branch；for ceiling FC |
| pureFn / localCall | Y | **Y** | **done** | G5-HARD callFn inline pureHelper；`testG5HardResidualTrueLower` |
| const / Op.Constant | F（Constant load FC） | **F** | **plan-FC** | Semantic→Plan Constant FC；`testG5MatrixConstPlanFailClosed` |
| bare assert / bare revert | Y | **Y** | **done** | `testG5MatrixBoolAssertStructural` + `testG5MatrixProductAssertLower`；bare revert→`assert.eq true false` |
| emit / call / schedule | F | **F**（IR-5） | **done**（IR FC） / **plan-FC**（product） | Plan `ALEO-IR-5:`；product resolve/lower FC suite |
| ContextRead / Commit | F / 身份透传 | **F** / 身份透传（IR-5） | **plan-FC** | product context FC；Commit 无 crypto opcode |
| nonempty invariant | F | **F** | **plan-FC** | Normalize/materialize 对 nonempty invariants FC（八 target 纪律） |
| pf.assets | F（零绑定） | **F**（IR-5） | **plan-FC** | product assets FC；`AleoPfAssetsV1` 零绑定 |
| record custody | F | **F**（IR-5） | **plan-FC** | 无 mint/consume IR；honesty note |
| Principal / String | F | **F** | **plan-FC** | type-closure / Plan ABI 直至决策 |
| payload revert | F | **F**（IR-5） | **done**（IR FC） | Plan payload `ALEO-IR-5:`；bare revert admitted |
| nested Map | F | **F** | **plan-FC** | `testNestedMapFailClosedAtPlan` / `testG5MatrixNestedMapPlanFailClosed` |

#### 3.2.1 G5-MATRIX 覆盖表（扫描结论）

| 桶 | 行数 / 内容 | 说明 |
|---|---|---|
| **done** | UInt*/Int64/Field/Bool/assert/revert/mapping/Option/Array/if·match·for/pureFn + IR-5 F rows | 有 Instructions lower 或稳定 `ALEO-IR-5:` 钉测 |
| **residual** | **0**（G5-HARD closed） | 原 Int64/Field/pureFn 已 true lower |
| **plan-FC** | const、bn254/Goldilocks Field、nested Map、Context/assets/record/Principal/String/invariant | 达不到 Instructions；不发明 IR |
| **partial** | **0** | 无 PARTIAL 假 Y |
| **open residual work** | multi-program leo 金样 / prove / record（IR-7 runtime honesty **done PARTIAL/MISSING**） | 见 §10；`deployable=false` |

**结论（G5-MATRIX + G5-HARD）：** 每 **Y** 行均有 IR 钉测；每 **F** 行有 plan-FC 或 IR FC 钉测；residual allowlist 空；silent Leo-only primary 已禁。

---

## 4. 架构切片

### 4.1 模块（建议）

```text
ProofForgeV2/Targets/Aleo/
  Instructions/
    SchemaV1.lean         # program/function/instr/register/type/visibility (IR-1)
    TextCodecV1.lean       # sole 文本序列化（≡ compiled.aleo 风格）(IR-1)
    LowerPlanV1.lean      # AleoPlan → Instructions program (IR-2 Counter MVP)
    ValidateV1.lean       # 寄存器 SSA、可见性、final 边界（后续）
  EmitIRV1.lean           # 过渡：Leo 源；IR 稳定后 debug-only
  FinalizeV1.lean         # 主产物切 Instructions；compile profile 可对照
```

### 4.2 与 AleoPlan 关系

- **保留** `AleoPlan` 为 target-owned 中间层（validate、digest、测试）。
- **新增** `LowerPlanV1` / `programFromCapabilityV1`：`plan → Instructions`（IR-2..IR-5；**IR-6 产品 materialize primary**）。
- **Leo 源** 为 debug / compile-compare 旁路（`EmitIRV1` + `PROOF_FORGE_ALEO_EMIT_LEO`），对标 Psy `PROOF_FORGE_PSY_EMIT_PSY`。

**默认 profile vs compile profile（IR-2 钉死）：**

| Profile | id | Plan body | Instructions lower | 产品物化 |
|---|---|---|---|---|
| default source | `aleo-leo-4.0.2-u64-v1` | 共享 | 同 Plan → 同 Instructions | **Instructions** `{id}.aleo` + query-contract；Leo 仅 debug env；zero-tool Finalize |
| compile | `aleo-leo-4.0.2-u64-compile-v1` | 共享（同 planDigest） | 同 Plan → 同 Instructions | 同上 + 双写 `{id}.leo` → locked Leo compare extras |

`LowerPlanV1` 不读 profile：两 profile 对 Counter 产出结构相等 Instructions；compile profile 的 `compiled.aleo` 仍是金样权威来源，lower 输出必须 ≡ 该金样。

### 4.3 验证阶梯

| 阶 | 门 | 完成标准 |
|---|---|---|
| G0 | Schema + 金样 decode | **done（IR-1）**：Counter `compiled.aleo` round-trip / 字段钉死 |
| G1 | Lower Counter | **done（IR-2）**：`LowerPlanV1` Instructions ≡ locked-leo 金样（结构+字节） |
| G2 | OptionState / MapMini 子集 | **done（IR-4）**：multi-leaf flatten-to-mapping + Option/Map/Array/narrow 结构测试 |
| G3 | 控制流 / for 展开 | **done（IR-3）**：if/switch → `branch.eq`/`position`；bounded for 静态 unroll + boundExceeded 门；结构测试 + Counter 金样回归 |
| G4 | 产品 primary IR | **done（IR-6 closeout）**：默认权威 Instructions；Leo debug-only / compile dual-write |
| G5 | admit 面 + hard-require | **done（G5-MATRIX + G5-HARD 2026-08-08）**：admit 扫描 + Int64/Field/pureFn true lower + 空 allowlist `ALEO-IR-G5-HARD` |
| G6 | Runtime 消费 IR | **done PARTIAL/MISSING（IR-7 2026-08-08）**：无 locked snarkVM/package-only；`scripts/aleo_runtime_test.sh` + `just aleo-runtime` 钉 `PF-TOOLCHAIN-MISSING`；不发明 CLI；leo run ≠ package-only |

G0–G5 = **IR-0..IR-6 + G5-MATRIX + G5-HARD engineering closeout done（2026-08-08）**；G6/IR-7 = runtime honesty **done as PARTIAL/MISSING（2026-08-08）**（execute pin 待 Tool Lock 真实工具）。

---

## 5. 分阶段实现（建议顺序）

### Phase ALEO-IR-0 — 规划与 pin（本文档）

- [x] 选定 **Aleo Instructions** 为权威物化层（对标 Psy DPN）
- [x] Tool Lock / supply-chain 注释：Leo 4.0.2 + Instructions grammar 权威指针（SchemaV1 头注释 + golden pin）
- [x] 金样入库策略：`testdata/golden/aleo-instructions-v1/counter.compiled.aleo`

### Phase ALEO-IR-1 — Schema + Counter 金样

- [x] Lean：`ProofForgeV2/Targets/Aleo/Instructions/{SchemaV1,TextCodecV1}.lean`（program/function/finalize/constructor/mapping + input/output/async/get.or_use/set/add/not/assert.eq 子集）
- [x] 金样：locked Leo 4.0.2 product Counter `aleo-leo-4.0.2-u64-compile-v1` → `counter.compiled.aleo`（870 B，SHA-256 `efc9e7a60ec3e046b1eb36e7b397abb753e06e7f0086b1e41a50966e1a7c2d52`）
- [x] 测试：`Tests/Materialization/AleoInstructionsV1` — 手建 ≡ golden decode、encode 字节相等、round-trip、fail-closed

### Phase ALEO-IR-2 — Plan → Instructions MVP

- [x] `LowerPlanV1`：Counter 形 init store(param) + mutate checkedAdd store+return（Final mapping get/set/add；init one-shot `initialized` guard）；bare view 不进 Instructions（off-chain query，对齐金样）
- [x] 与金样结构相等（`programFromCapabilityV1` / 手建 Plan → encode ≡ `counter.compiled.aleo`）
- [x] 默认 profile / compile profile 关系文档化（见 §4.2 与 module 头；Plan  profile-insensitive，两 profile 同 Instructions）

### Phase ALEO-IR-3 — 控制流与有界循环

- [x] if/match → 指令序列（`branch.eq`/`position`；switch = 右嵌套 `is.eq` 链；对齐 Leo 4.0.2 Final if 形）
- [x] bounded for 静态展开（`0..maxIterations` 展开 + `start<end` 时 `end-start≤N` assert + 每步 `c<span` 门；`maxIterations>4096` FC）

### Phase ALEO-IR-4 — 多叶 / Map / Option / 窄宽

- [x] 复用现 flatten-to-mapping 布局，输出 Instructions（每 Plan leaf → `pf_state_{i}`；`storeAggregate` 先全求值再 set）
- [x] 宽度/Field 与现 FC 矩阵一致（UInt8/16/32/64 + G5-HARD Int64/Field BLS12-377 已开；nested Map 仍 Semantic/Plan FC）

### Phase ALEO-IR-5 — 效果与诚实矩阵

- [x] emit/call/schedule/assets/context：**全部 F**（无 PARTIAL 声称）
  - Plan-reachable：`checkEffectsHonestyMatrixV1` 先于 `validatePlan`；`emitEvent` / `callFn` / payload `revertError` 稳定 `ALEO-IR-5:` 诊断（`LowerPlanV1`）
  - 产品面：sync call / schedule 在 resolve 拒 S2 双键；`effect.event` resolve 拒；`pf.assets` Phase D 零绑定；ContextRead/EnvRead Semantic→Plan pilot FC
  - 测试：`Tests.Materialization.AleoInstructionsV1` 手建 Plan + product 路径钉 FC
- [x] record：保持 FC 直至产品决策（honesty note + assets 零绑定证据；无 record mint/consume IR）

### Phase ALEO-IR-6 — 产品切换

- [x] materialize primary = Instructions 文本（`{id}.aleo` when lower succeeds；≡ Counter golden）
- [x] Leo 源 debug flag：`PROOF_FORGE_ALEO_EMIT_LEO=1` / `emitLeoDebug` → `{id}.leo`；compile profile 始终双写供对照
- [x] Finalize：source profile zero-tool + IR primary note；compile profile 消费 dual-written `.leo` 跑 locked leo 作 **对照** 而非 sole 权威；`deployable=false`
- [x] dual-write transition residual：**superseded by G5-HARD**（空 allowlist；禁 silent Leo-only primary）

### Phase ALEO-IR-7 — Runtime（可选、独立 host-heavy）

- [x] pin snarkVM / 官方 execute 路径（若存在 package-only）— **probe：MISSING**（Tool Lock 仅 Leo 4.0.2；无 snarkVM/snarkOS asset；RPT-024）
- [x] **非** ordinary ci；`deployable=false` 直至产品决策
- [x] host-heavy `scripts/aleo_runtime_test.sh` + `just aleo-runtime`：缺工具 → `PF-TOOLCHAIN-MISSING`（exit 2）；**不**发明 snarkVM CLI；**不**把 `leo run`/`leo execute` 升格为 package-only Instructions execute
- [x] suite 钉测：`Tests.Materialization.AleoInstructionsV1.testIr7RuntimeHonestyNotes`

### Phase ALEO-G5-MATRIX — admit 面扫描 + FC pins

- [x] 刷新 §3.2 矩阵：**Instructions 现状**列 = `done` / `residual` / `plan-FC` / `partial`（2026-08-08）
- [x] 每 **Y** 行：IR 自动化钉测 **或** 稳定 residual FC（禁止假 Y）
- [x] 每 **P/F** 行：产品/Plan 诊断钉测或明确 plan-FC 引用（const / nested Map / bn254 / assets / context）
- [x] 覆盖表 §3.2.1（对标 Psy G5-MATRIX）
- [x] Int64 / Field / pureFn residual：residual 桶 + `Tests.Materialization.AleoInstructionsV1` 钉测（true lower 属 G5-HARD）

### Phase ALEO-G5-HARD — residual hard-require（对齐 Psy R-HARD）

- [x] 列出 residual Plan 形状：**Int64 / Field BLS12-377 / pureFn**（G5-MATRIX residual 桶 → 已闭合）
- [x] **true lower** residual 族（Int64 signed ops、Field BLS12-377、pureFn/localCall inline）
- [x] **空 allowlist** `isAleoInstructionsG5HardResidualAllowlistV1`；Plan-admitted 且 IR fail → 稳定 `ALEO-IR-G5-HARD` materialize FC
- [x] 测试：Counter 仍 Instructions primary；`testG5HardResidualTrueLower` + allowlist classifier
- [x] `deployable=false`；不声称 prove/deploy

### Phase ALEO-IR-7 / G6 — Runtime honesty（独立）

- [x] 探路：Tool Lock / 本机是否有 snarkVM、`leo run` 边界、package-only 路径（**无** snarkVM；`leo run` = 源解释；`leo execute` 需网络 state）
- [x] **若无诚实工具**：文档 + suite 钉 **PARTIAL / MISSING**（不发明 CLI）；`just aleo-runtime` → `PF-TOOLCHAIN-MISSING`
- [x] **若有**：host-heavy 差分（Counter 最小）— **N/A**（工具 MISSING；未发明 CLI）
- [x] 永不默认 deployable

### Phase ALEO-RES-CLEAN — residual honesty closeout

- [ ] 删除/避免假 dual-authority；docs/backlog/AGENTS Next
- [ ] 全量 multi-program leo 字节金样 **deferred** 声明（Counter sole 全量金样）

---

## 6. 与现有 ALEO-I1–I4 的关系

| 切片 | 状态 | 与本规划 |
|---|---|---|
| ALEO-I1 Plan digest | done | 保留 |
| ALEO-I2 `.aleo` + query-contract | done | `.aleo` Leo 源 → 过渡；query-contract 可继续 sidecar |
| ALEO-I3 Tool Lock Leo 4.0.2 | done | 金样与对照编译权威 |
| ALEO-I4 compile extras | done | `compiled.aleo` = IR-1 金样源；长期可由我们直出替代 “仅 leo 生成” |

**不**删除 I4，直到 IR 主路径证明可替代对照。

---

## 7. 风险与诚实边界

| 风险 | 缓解 |
|---|---|
| Leo 源与 Instructions 文件名都叫 `.aleo` | 文档 + 扩展名/角色分离（如 `.instructions.aleo` / primary role） |
| 双上下文说错 | Validate 强制 final/proof 分叉；混合 mapping 写 FC |
| 寄存器分配不确定 | 规范化策略或金样结构相等（允许 α-换名则测语义） |
| 无 package-only execute | G6 标 PARTIAL；不发明 snarkVM CLI |
| 范围膨胀到全 opcode / record | DoD 锁在 §3.1 |
| 与 Psy lane 并行抢主线 | **本规划起 Active = Aleo IR**；Psy DPN 保持 idle residual |

**成熟度：** IR 落地后 registry 仍可 **source-only / compile-only / non-deployable**，直到 prove/deploy 决策。
**不得** 把 “Instructions 文本生成成功” 写成 formal / hermetic / 主网。

---

## 8. 文档 / backlog 衔接

| 文档 | 作用 |
|---|---|
| 本文 | 规划与覆盖定义 sole 输入 |
| [`09-aleo.md`](09-aleo.md) | 产品边界摘要 + 指向本文 |
| [`engineering-backlog.md`](../engineering-backlog.md) | `ALEO-IR-*` 可勾选切片 |
| [`AGENTS.md`](../../AGENTS.md) | Active/Next = Aleo IR lane |
| 实现日志 | 每 Phase 完成后追加事实 |

---

## 9. 完成条件（Definition of Done）

### 9.1 MVP（ALEO-IR-2）— **done（engineering）**

- Counter 产品 Plan 经 `programFromCapabilityV1` 产出 Instructions，与 locked-leo 金样结构相等且 encode 字节相等。
- 测试：`Tests.Materialization.AleoInstructionsV1`（Fast + targets shard + ordinary Tests）。
- 文档声明（历史 IR-2）：当时产品 primary 仍 Leo 源；**IR-6 后**产品 primary = Instructions。

### 9.2 Admit 面（G5）

- §3.2 中目标 **Y** 有 IR + 测试，或 **residual** 稳定 FC（禁止假 Y）— **G5-MATRIX + G5-HARD done**。
- **P/F** 有诊断或 PARTIAL 文档 — **G5-MATRIX done**。
- **G5 整阶完成** — **G5-HARD done（2026-08-08）**。

### 9.3 非完成条件

- 全 Leo 语法；全 opcode；prove/deploy；formal TASK；UPS。

---

## 10. IR-6 后执行队列（已规划；lane 仍 active）

**IR-0..IR-7 / G0–G6 + G5-MATRIX + G5-HARD engineering closeout（2026-08-08）已闭合**。产品权威 = Plan→Instructions；Leo 源 debug/compare only；Counter ≡ golden；residual 桶 0；空 allowlist；效果矩阵无 PARTIAL 假 Y；IR-7 runtime = **PARTIAL + MISSING**（package-only snarkVM execute 无 Tool Lock pin）。

**后续队列：**

| 序 | 切片 | 目标 | 完成条件（摘要） |
|---|---|---|---|
| 1 | **G5-MATRIX** | §3.2 全行扫描 | **done（2026-08-08）** |
| 2 | **G5-HARD** | hard-require | **done（2026-08-08）**：true lower + 空 allowlist + `ALEO-IR-G5-HARD` |
| 3 | **IR-7 / G6** | runtime honesty | **done PARTIAL/MISSING（2026-08-08）**：`just aleo-runtime` → `PF-TOOLCHAIN-MISSING`；suite 钉测；不发明 CLI |
| 4 | **RES-CLEAN** | 文档收口 | deferred 金样 / prove / record 诚实列表（**Next**） |

### 已交付（不重开为 Next）
| 切片 | 交付 |
|---|---|
| IR-0 | 规划 + pin 策略 + Active 切 Aleo IR |
| IR-1 | SchemaV1 + TextCodecV1 + Counter `compiled.aleo` golden |
| IR-2 | LowerPlanV1 Counter MVP ≡ golden 字节 |
| IR-3 | if/match/bounded-for → branch.eq/position/static unroll |
| IR-4 | multi-leaf Map/Option/Array + narrow UInt{8,16,32} |
| IR-5 | effects honesty matrix（emit/callFn/payload-revert Plan FC；product call/schedule/assets/context FC） |
| IR-6 / G4 | product primary `{id}.aleo` = Instructions；Leo debug-only / compile dual-write |
| G5-MATRIX | §3.2 Instructions 现状列 + §3.2.1；Bool/assert/const/Int64/Field/pureFn/nested Map pins |
| G5-HARD | Int64/Field/pureFn true lower；`isAleoInstructionsG5HardResidualAllowlistV1` 恒 false；`ALEO-IR-G5-HARD` |
| IR-7 / G6 | runtime honesty PARTIAL/MISSING：`scripts/aleo_runtime_test.sh` + `just aleo-runtime` 钉 `PF-TOOLCHAIN-MISSING`；suite `testIr7RuntimeHonestyNotes`；不发明 snarkVM CLI |

### Remaining（blockers / next work）

1. **RES-CLEAN（Next）**：deferred multi-program leo 金样 / prove / record 诚实列表。
2. **full opcode / record / prove**：out-of-slice 直至产品决策；record custody / pf.assets 零绑定保持；`deployable=false`。
3. **可选未来**：若上游提供 package-only execute 且进入 Tool Lock，扩展 `aleo_runtime_test.sh` 为 Counter host-heavy 差分（仍非 ordinary ci）。

规划 owner：engineering。
产品决策：用户已确认 **切换到 Aleo**，权威层 = **Aleo Instructions（中间 IR）**；IR-0..IR-7 + G5-MATRIX + G5-HARD 已工程 closeout（产品 primary = Instructions；Leo debug-only；residual allowlist 空；runtime execute MISSING/PARTIAL）。
