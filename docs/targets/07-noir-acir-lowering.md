---
id: TARGET-NOIR-ACIR
title: Noir ACIR / circuit IR lowering plan (ProgramV1 → ACIR authority)
status: draft
owner: engineering
updated: 2026-08-08
normative: false
---

# Noir ACIR 层落地规划

状态：`draft`（规划 + **NOIR-IR-1 金样已冻结** + **NOIR-IR-2 Plan→ACIR MVP 已接线** + **NOIR-IR-3 G3 admit-surface circuit-hash pins 已接线** + **NOIR-IR-5 诚实矩阵（G5 轻量）已接线** + **NOIR-IR-6 产品 ACIR dual-write 可选 profile 已接线** + **NOIR-IR-7 / G6 prove honesty PARTIAL+MISSING 已接线**）
目标：在 **不改变 ProgramV1 可移植业务语义** 的前提下，把 Noir target 的权威物化从 **Noir 源包（`.nr` relations）** 切向官方 **电路中间表示（ACIR 及相关编译产物）**，并评估 admit 面覆盖。

与 Psy / Aleo 对照：

| | Psy | Aleo | Noir（本规划） |
|---|---|---|---|
| 旧 sole 权威 | `.psy` 文本 | Leo 源 | **Noir source package**（`main.nr` + Nargo.toml） |
| 新 sole 权威 | DPN package JSON | Aleo Instructions | **ACIR / nargo compile 电路产物**（精确形态 IR-1 冻结） |
| 工具 pin | dargo 0.1.0 | Leo 4.0.2 | **nargo 1.0.0-beta.26**（Tool Lock 已有） |
| 作者语言 | ProgramV1 | ProgramV1 | ProgramV1 |

权威上游（规划 pin；IR-1 实测冻结）：

| 项 | 值 |
|---|---|
| 工具 | locked **nargo 1.0.0-beta.26** |
| 官方语言 | Noir → **ACIR**（Abstract Circuit IR）→ backend prove |
| 工程现状 | 产品 emit `relations/*/src/main.nr`（过渡/debug base）；`NoirCompileAcceptance` / host-optional `nargo compile`；**IR-1** 金样 `testdata/golden/noir-acir-v1/` + inventory pin；**IR-2** nargo-assisted Plan→ACIR capture（Counter ≡ 金样 circuit core）；**IR-3** G3 CF/aggregate circuit-hash pins；**IR-5** §3.2 诚实矩阵；**IR-6** 默认 `noir-source-u64-relations-v1` zero-tool；显式 `noir-nargo-1.0.0-beta.26-acir-v1` Finalize dual-write path-normalized ProgramArtifact `finalized-extra`（`nargo-compile/{stem}/*.json`；缺 nargo fail-closed；`deployable=false`）；**IR-7/G6** prove honesty **PARTIAL+MISSING**（Tool Lock `barretenberg=null`；`scripts/noir_runtime_test.sh` + `just noir-runtime` → `PF-TOOLCHAIN-MISSING`；不发明 bb/CRS） |
| 非本阶段 | 产品 prove/verify、CRS、VK 产品绑定、formal（G6 lane 仅 honesty pin，非 product prove） |

**非目标：**

- 把完整 Noir 语言手册变成作者语言。
- 默认 product Finalize 调 prove/verify。
- unconstrained / oracle / foreign call。
- 声称 “ACIR 生成 = circuit proof 完成”。

---

## 1. 动机

当前 Noir 路径：

```text
ProgramV1 → Semantic → NoirPlan → relation IR → Noir source package (.nr)
                              └─ 可选：nargo compile（compile-only 验收，无 ACIR 入库）
```

问题（与 Psy `.psy` / Aleo Leo 同构）：

1. **脆性**：与 Noir 源语法 / nargo 版本耦合。
2. **双重真相**：可证明的电路形状在 ACIR/backend；`.nr` 是第三方言。
3. **覆盖 KPI 失真**：易写成 “能吐 Noir 源”。正确 KPI = **admit 面在 ACIR 上诚实编码**。
4. **已有 compile 门**：locked nargo 可作金样抓取，却未成为产品权威。

目标路径：

```text
ProgramV1 → Semantic → NoirPlan → NoirAcirIR / ACIR bytes|JSON
                │                      │
                │                      ├─ ≡ nargo compile 产物（金样）
                │                      ├─ 可选：调试 .nr（非权威）
                │                      └─ 后续：prove backend 消费 ACIR
                └─ 现有 .nr 发射在 ACIR 主路径稳定前保留为过渡
```

---

## 2. 目标模型（实现必须对齐）

### 2.1 先冻结 “金样是什么”

IR-1 **必须** 用 locked nargo 对产品 Counter package 实测：

- `nargo compile` 输出目录中的 **ACIR / circuit artifact** 文件名、编码（JSON vs binary）、是否含 Brillig。
- 选定 **sole 金样形态**（优先：可稳定 round-trip 的 ACIR 序列化；若 nargo 只产 opaque 目录，则 pin **规范化文件集 + 内容 hash** 并文档化）。

**禁止** 在未打开真实 artifact 前假设 schema。

### 2.2 与 NoirPlan 关系

- 保留 `NoirPlan` / relation IR 为 target-owned 中间层。
- 新增 `Plan → ACIR`（或 `Plan → nargo-input + 我们自己的 ACIR encoder` 若与 nargo 对齐）。
- 短期诚实路径：**产品 dual-write** — primary ACIR（或 compile extras）+ debug `.nr`。
- 若无法在无 nargo 的情况下 pure-Lean 编码 ACIR：IR-2 可为 **capability 内调用 locked nargo 仅抓 ACIR**（host-heavy / Finalize 可选），Lean 侧做 validate/hash/pin——须在 IR-1 决策并写清 **非 hermetic**。

### 2.3 验证阶梯

| 阶 | 门 | 完成标准 |
|---|---|---|
| G0 | 金样捕获 + pin | **done（IR-1）** Counter nargo compile artifact 入库 + 文档 |
| G1 | Schema/codec 或 inventory hash | **done（IR-1）** exact multi-file SHA-256 + envelope keys（非 ACIR opcode codec） |
| G2 | Plan→ACIR MVP | **done（IR-2）** Counter product Plan → nargo-assisted capture ≡ 金样 circuit core；路径决策 = nargo-assisted |
| G3 | 控制流 / 聚合 admit 面 | **done（IR-3）** BranchCounter/LoopSum/OptionState/ArrayRet circuit-hash pins；MapMini init pin + put/get nargo-fail honesty |
| G4 | 产品 primary ACIR | **done（IR-6）** opt-in nargo ACIR profile dual-write；default zero-tool；`.nr` transitional/debug |
| G5 | admit 矩阵 | **done（IR-5 轻量）** §3.2 状态列 + call/schedule P + String/Option F + prove F；无假 Y |
| G6 | prove lane | **done PARTIAL/MISSING（IR-7 2026-08-08）**：无 locked bb/barretenberg；`just noir-runtime` → `PF-TOOLCHAIN-MISSING`；prove/VK 仍 F；不发明 CLI/CRS |

---

## 3. 覆盖目标

> ProgramV1 在 **Noir 已 admit** 的构造 → 确定性 ACIR 编码；不 admit → 稳定 FC。

**不是：** 全 Noir 语法、unconstrained、full prove pipeline、formal。

### 3.2 矩阵（IR-5 / G5 轻量，2026-08-08）

图例：`Y` = 有 ACIR capture / 等价钉测；`P` = PARTIAL（Plan/slot 可 admit 但不写满平台/证明 Y）；`F` = plan-FC 或无产品路径。
**禁止假 Y**：call/schedule / String·Option non-UInt64 / prove 不得写成 ACIR Y。

| 族 | 现 Noir 路径 | ACIR 现状 | 证据（测试 / 路径） |
|---|---|---|---|
| UInt*/Field bn254 算术 | Y | **Y** | Counter IR-1 inventory + IR-2 Plan→ACIR capture |
| Bool / 比较 / 逻辑 | Y | **Y** | Counter / BranchCounter compare；G3 if capture |
| Array/Map/Bytes flatten | Y/P | **P** | ArrayRet Y capture；MapMini init Y + put/get nargo-fail residual；Bytes 仍 Plan 面 |
| if/match/for | Y | **Y** | BranchCounter if；LoopSum for；OptionState match G3 pins |
| pureFn | Y | **Y** | Counter 回归（未另钉 G3 fixture） |
| call/schedule slots | P | **P** | 仅 witness-binding status/arg slots（B-CALL-SEM）；电路不执行外部调用、证明不 attest 链上调用；`testHonestyCallSchedulePartialNotY`；result-bearing 仍 FC |
| Option UInt64 state | Y | **Y** | OptionState G3 full capture pins |
| String state / Option non-UInt64 | F | **F** | product plan-FC：`testHonestyOptionStringProductFailClosed`（String / Option String / Option Bool） |
| prove/VK | F | **F** | G6 PARTIAL+MISSING（`barretenberg=null`；`just noir-runtime` → `PF-TOOLCHAIN-MISSING`）；Finalize `deployable=false`；`testHonestyProveFailClosedNotes` + `testIr7ProveHonestyNotes` |

Lean 权威表：`CaptureV1.honestyMatrixRowsV1`（与上表同序）；suite `Tests.Materialization.NoirAcirV1` IR-5 段恒跑（不依赖 nargo）。

#### 3.2.1 覆盖桶

| 桶 | 行 | 说明 |
|---|---|---|
| **Y** | UInt*/Field、Bool/compare、if/match/for、pureFn、Option UInt64 | IR-1/IR-2/IR-3 capture 证据 |
| **P** | Array/Map/Bytes、call/schedule | Map put/get residual；call/schedule 仅 witness slots |
| **F** | String/Option non-UInt64、prove/VK | plan-FC 或无产品 prove |
| **假 Y 守卫** | call/schedule、String/Option、prove ∉ Y bucket | suite 钉 `honestyAcirYFamiliesV1` |

---

## 4. 分阶段实现

### NOIR-IR-0 — 规划（本文档）

- [x] 选定 ACIR/compile 产物为权威方向
- [x] Tool Lock 注释：nargo pin 与 ACIR 权威关系（`docs/specs/toolchains.md` nargo 行）

### NOIR-IR-1 — 金样 + schema 探路

- [x] locked nargo 1.0.0-beta.26 对 Counter 抓 `nargo compile` ProgramArtifact JSON
- [x] 冻结 golden 路径 `testdata/golden/noir-acir-v1/`（product packages + path-normalized compile JSON + `inventory.json`/`README.md`）
- [x] Lean：`ProofForgeV2/Targets/Noir/Acir/InventoryV1.lean` multi-file exact SHA-256 pin + ProgramArtifact envelope keys；`Tests/Materialization/NoirAcirV1.lean`（nargo 缺席时 live recheck honest skip）
- **诚实结论（IR-1）**：sole 可稳定 pin 的形态 = **path-normalized multi-file inventory**（`file_map.path` → `src/main.nr`）；`bytecode` 为 base64(gzip(ACIR))，**未**解码 ACIR opcode；非 pure-Lean ACIR encoder

### NOIR-IR-2 — Plan→ACIR MVP

- [x] Counter Plan 路径 ≡ 金样（product Plan emit source-join + nargo-assisted circuit core）
- [x] 文档：路径决策 = **nargo-assisted**（非 pure-Lean ACIR opcode encoder）

**IR-2 路径决策（冻结）**：

| 选项 | 结论 |
|---|---|
| pure-Lean ACIR opcode encoder | **不做**（IR-1 诚实结论：bytecode=base64(gzip ACIR)，未解码 opcode；不发明后端） |
| nargo-assisted capture | **sole authority** |

实现：

* `ProofForgeV2/Targets/Noir/Acir/CaptureV1.lean` — circuit core 抽取/比较、nargo resolve、`compilePackageCaptureCircuitCoreV1`、product package source-join
* `Tests/Materialization/NoirAcirV1.lean` — product Plan Counter materialize → source ≡ golden product packages（恒跑）；product packages → nargo compile → circuit core ≡ golden（nargo 缺席 honest skip）
* 产品 Finalize **仍** source-only / non-deployable；**无** ACIR `OutputFile`（留给 IR-6）
* `.nr` 继续作为过渡产品发射与 nargo 输入

### NOIR-IR-3 — 控制流 / 聚合 admit 面（G3）

- [x] 对已 admit 的 if/for / Array/Option 产品 fixture：nargo-assisted capture 成功 + **circuit-core hash pin**（非全量 multi-file inventory；inventory 扩张属 IR-4）
- [x] BranchCounter / LoopSum / OptionState / ArrayRet 进入 `NoirAcirV1` 钉测；MapMini Plan 包 + init capture pin，**put/get nargo type residual** 诚实失败钉（不 silent pass）
- [x] Counter 金样回归（IR-1 inventory + IR-2 source-join/capture 不变）
- [x] 缺 nargo：live capture honest skip；package-stem 与 Counter inventory 仍恒跑

实现：

* `CaptureV1.admitSurfaceFixturesV1` — 五 fixture 源文本 + package stems + 14 circuit-hash pins + MapMini `nargoFailStems`
* `Tests/Materialization/NoirAcirV1.lean` — `testAdmitSurfacePackageStems`（恒跑）+ `testAdmitSurfaceLiveCaptureOptional`（nargo 缺席 skip；在场时 hash pin + 二次编译稳定性 + Map fail）
* 产品 Finalize 仍 source-only / `deployable=false`；**无** ACIR OutputFile（IR-6）

### NOIR-IR-4 — 多 fixture 金样扩张

- [ ] 可选：额外 fixture 的 path-normalized compile inventory（非全量字节矩阵）
- [ ] 缺 nargo honest skip（G3 live 路径已具备；IR-4 仅 inventory 扩展）

### NOIR-IR-5 — 诚实矩阵（G5 轻量）

- [x] §3.2 状态列：Y/P/F + 证据列；`CaptureV1.honestyMatrixRowsV1` 与文档同序
- [x] call/schedule = **P**（witness-binding only；`testHonestyCallSchedulePartialNotY`；禁止 ACIR Y）
- [x] String state / Option non-UInt64 = **F**（product plan-FC 钉）
- [x] prove/VK = **F**（Finalize evidence + deployable=false；无产品 prove）
- [x] Counter 金样回归保持绿；nargo 缺席时 IR-5 恒跑
- [x] **无假 Y**

### NOIR-IR-6 — 产品 primary ACIR；`.nr` debug

- [x] **诚实路径 = optional profile dual-write**（host-dependent nargo 不能破坏 default zero-tool Finalize）
- [x] default `noir-source-u64-relations-v1`：zero-tool；`.nr` transitional/debug base；evidence 指向 ACIR profile
- [x] explicit `noir-nargo-1.0.0-beta.26-acir-v1`：Finalize nargo-assisted path-normalized ProgramArtifact extras under `nargo-compile/{stem}/{pf_relation_N}.json`；缺 nargo → `PF-TOOLCHAIN-MISSING`；`deployable=false`；无 prove/VK
- [x] Counter dual-write ≡ 金样 circuit core / path-normalized bytes（nargo 在场时 live；`NoirAcirV1` IR-6 段）
- [x] Plan surface 双 profile 共享；registry/resolver 13 support rows；Capture authority 仍 pin

### NOIR-IR-7 — prove honesty（工具存在时）

- [x] 探路 Tool Lock：`unresolved.barretenberg=null`；tool root 无 `bb`/`barretenberg` 资产
- [x] 无 backend pin → `scripts/noir_runtime_test.sh` + `just noir-runtime` → `PF-TOOLCHAIN-MISSING`（exit 2）+ PARTIAL 文档
- [x] 有 pin 时预留路径：binary  alone 仍拒绝（无 digest/version/recipe → 仍 `PF-TOOLCHAIN-MISSING`）；真正 Counter prove pin 待真实 Tool Lock pin
- [x] suite `testIr7ProveHonestyNotes`（恒跑；非 ordinary ci 跑 runtime recipe）
- [x] 不发明 prove CLI / CRS；nargo compile ≠ prove；prove/VK 矩阵仍 **F**；`deployable=false`

---

## 5. 与现有 Noir 工程的关系

| 现状 | 保留 |
|---|---|
| relation Plan + `.nr` emit | 过渡/debug base（IR-2/IR-6 nargo 输入；仍 materialized-base） |
| locked nargo compile-only | 金样 + 对照 + IR-2 capture + IR-6 ACIR profile dual-write |
| Finalize zero-tool default / non-deployable | default 保持；ACIR profile 仍 `deployable=false` |
| NoirCompileAcceptance | 不删除；IR-2/IR-6 另由 `NoirAcirV1` 钉 Counter≡金样 |

---

## 6. 风险

| 风险 | 缓解 |
|---|---|
| ACIR 格式随 nargo 漂移 | exact nargo pin；未知字段 fail closed |
| 无法 pure-Lean 编码 | nargo-assisted 诚实路径 + 非 hermetic |
| 范围膨胀到 prove | G6 独立；deployable=false |
| 与 Aleo/Psy 抢主线 | **本规划起 Active = Noir ACIR**；Aleo/Psy idle residual |

---

## 7. DoD

### MVP（IR-2）

- [x] Counter ACIR（ProgramArtifact circuit core）与 locked-nargo 金样结构/字节相等（nargo 在场时 live；源码 join 恒跑）。
- [x] 测试进 targets shard（`Tests.Materialization.NoirAcirV1`）。
- [x] `.nr` 声明为过渡；路径决策文档化为 nargo-assisted。

### 非完成

- prove/verify **产品**门、CRS、formal、全 Noir 表面、default-profile 自动 ACIR（有意保持 zero-tool）。
- IR-7 仅 honesty pin：**PARTIAL+MISSING**；有 Tool Lock backend pin 后才可扩展 Counter prove（仍 host-heavy）。

---

## 8. 下一步

1. **NOIR-IR-0** 已完成。
2. **NOIR-IR-1** 已完成：Counter 金样 + multi-file inventory pin。
3. **NOIR-IR-2** 已完成：nargo-assisted Plan→ACIR MVP（Counter ≡ 金样）。
4. **NOIR-IR-3** 已完成：G3 CF/aggregate circuit-hash pins。
5. **NOIR-IR-5** 已完成：§3.2 诚实矩阵 + call/schedule/Option-String/prove FC 边界。
6. **NOIR-IR-6** 已完成：opt-in nargo ACIR dual-write profile；default zero-tool；`.nr` transitional/debug。
7. **NOIR-IR-7 / G6** 已完成（PARTIAL+MISSING）：`just noir-runtime` → `PF-TOOLCHAIN-MISSING`；不发明 bb/CRS。
8. **Lane idle**（optional residual）：IR-4 multi-fixture inventory；未来真实 Barretenberg/backend Tool Lock pin 后的 Counter prove 扩展（仍非 ordinary ci / 非 product prove）。

规划 owner：engineering。
IR-1/IR-2 冻结细节见 `testdata/golden/noir-acir-v1/README.md`。
