---
id: RPT-011
title: 特性覆盖审查——文档与代码对照
status: draft
owner: research
updated: 2026-08-02
normative: false
---

# 特性覆盖审查——文档与代码对照

状态：`draft`
研究日期：2026-08-01

> **历史快照警告（2026-08-02）**：本文正文保留 2026-08-01 审计时点，已被后续
> T-1/T-2、T8–T14、AddressBearing、Map/Bytes、Invariant ABI 与 target leaf 切片大幅超越，
> 不再作为当前能力或调度依据。当前工程事实以根级 `AGENTS.md` / `MIGRATION_MATRIX.md`、
> [`12-target-coverage-matrix.md`](12-target-coverage-matrix.md) 与
> [`../engineering-backlog.md`](../engineering-backlog.md) 为准。
>
> **执行队列**：缺口关闭请回写 [`../engineering-backlog.md`](../engineering-backlog.md)，勿另开平行清单。

## 目的

对照规范（`SPEC-LANG-001` 语言 EBNF、`SPEC-SEM-001` 目标中立语义核心、
`SPEC-TYPE-001` 类型/效应系统、各 target dossier）与实际代码（`ProofForgeV2/Semantic/NormalizeV1.lean`
docstring、`Targets/*/LowerSemanticV1.lean`、`Semantic/WireV1.lean`、`Examples/`、
`runtime-tests/`），盘点"覆盖全特性（不只 Counter）"还差什么。本文为非规范性研究，
不改变已接受决策、目标范围或任务状态；只固定审查结论与工作清单，供后续推进参考。

## 核心结论

瓶颈不在地基。`WireV1` structure gate 已经接受并校验**完整 op 集**（ContextRead /
Commit / PureCall / VariantTag / VariantPayload / IndexSet / CheckedCast / FieldSet，
含完整 CFG reachability/dominance/SSA/op-typing/terminator/effect-id/invariant-closure/
exact-fuel）。但 `NormalizeV1` 只 lowering 一个子集，`ReferenceV1` 只执行 admitted 子集。
即：地基已能容纳全部特性，缺的是把 ProgramV1 真正降成完整 SemanticProgramV1，并让
参考机与 target 跟上。

## 分层对照

### L1 Source / ProgramV1（D1）—— 基本完成

- ✅ 全 13 种 declaration、完整递归 type 表面、完整 statement/expr/place/pattern、
  command/export 已是 V1 唯一路径、wire/hash/NodeId/OriginJoin/SpanJoin。
- ✅ 前端监督层已按 2026-08-01 产品决策移除；CLI 源读取为进程内 `Loader.selectProgramV1Product`。
- ❌ formal `TASK-D1-01` 仍 blocked（release qualification 前置，独立轴，不阻塞开发）。

### L2 Typed CheckV1（D2）—— 五相位完成，三轴缺

- ✅ structure（name resolution + call graph）/ type（含 match typing、statement typing）/
  effect / bound / disclosure（显式 + PC-label implicit）均为产品 Normalize 门禁 sole 权威。
- ❌ **authority / custody 轴**（`TST-VIS-002` 全覆盖）未实现。
- ❌ **commit 算子**（`disclosure.commit`）未实现。
- ❌ context / extension requirements 未接 CheckV1。

### L3 NormalizeV1（ProgramV1 → SemanticProgramV1）—— 主瓶颈

已 lowering：

- multi-width UInt/Int{8..256} + Field(bn254) 算术 + Principal 身份 state/params；
- named Struct/Enum state/params（N3）；
- aggregates 作为值（`Construct` / `FieldGet` / `IndexGet` / `FieldSet` / `IndexSet` 带外向 rebind，
  含 state root `x.f[0].g = v`）；
- checked `+ - * / %`、bitwise `& ^ |`、shift `<< >>`、六比较、Field/Principal `== !=`；
- Bool 字面量；一元 `~ !`（`-` 在 UInt desugar 为 `0-x`，Int/Field 发 `Op.Unary.neg`）；
- `if`/`match`（Enum/Option 构造器臂经 `VariantTag`/`VariantPayload`，expression match 带 join block）；
- bare `assert`；不可变 `let`（field/index rebind）；bounded `for`；
- `fn`/localCall（pureCall）；`call`/`schedule`；`revert`/`emit`（public UInt64 event/error）；多块 CFG。

fail closed（逐项对照 spec EBNF 与 `SPEC-SEM-001`；**N-A1/N-A2 已闭合 2026-08-02**）：

1. 非空 Map 构造（anonymous Map/Array/Bytes/Option **state** 已 admit；Option 默认 none，N-A4）；
2. ContextRead 扩 key / `callerContext`（sole `unixTimeSeconds` 已 N5）；
3. Commit **disclosure 契约**（label-only `commit(x)` 已 N5）；
4. aggregate entry/view/fn 返回值（target ABI 仍 scalar-only）；
5. call 返回值 / schedule response 语义（v1 external call 无返回值——`SPEC-SEM-001` 明确
   "加 typed return 必须升级 semantic/reference schema"）；
6. true mutable locals（仅 field/index rebind of 不可变 let）；
7. match 内构造器子模式嵌套深化；
8. Int event/error 字段（仍 UInt-only）；
9. 非 UInt64 的 call/schedule args 与 for 端点；
10. Field/Principal 源字面量、Field 排序比较、Field `mod`、Principal 算术。

注：String 不是运行时类型，只用于 extension metadata（`version`/`digest`），
因此不存在"String 产品路径"缺口。

### L4 ReferenceV1（step 执行）—— admitted 子集

- ✅ Bool/UInt8·32·64/Unit/Bytes + Literal/Constant/StateLoad·Store/Unary/Binary/
  CheckedCast/Assert/Emit/ExternalCall/Schedule + 全 terminator；ordered effects、
  response cursor、rollback、bounded loop。
- ❌ PureCall、context/commit、Int/Field/Principal、aggregates/index、general resource profile、
  `evalInvariantV1` / `InvariantTheoremV1`、target differential、full formal corpus；
  未接 product CLI/materializer。

### L5 WireV1 structure gate —— 最完整的一层

- ✅ 接受并校验全部 op + 完整 CFG（reachability/dominance/SSA/op-typing/terminator/
  effect-id/invariant-closure/exact-fuel）+ type-shape + valueBytes + name gates。
- 该层已为全特性 ready，是其他层追赶的基准；本审查不认为它有特性缺口。

### L6 Target lanes —— 成熟度差异巨大

| Target | 代码 | 真制品/运行 | 主要缺口 |
|---|---|---|---|
| EVM | `LowerSemantic` 2600 行 + `Keccak` + `ValidateIR` | ✅ solc bytecode + Anvil Counter/overflow | 完整 D4 lowering（非 Counter）、Reference↔Anvil closure、formal identity |
| Solana | `LowerSemantic` + `EmitSbpfAsm` + ELF | ✅ SBPF `.so` + Mollusk 差分 | multi-width UInt/Int + T9e UInt128/256 multiword；Map/Bytes state FAIL-CLOSED |
| NEAR | `LowerSemantic` 2007 行 | ❌ 仅 raw-u64 `wat2wasm` 结构验证 | 无真实 bytecode/runtime |
| Noir | `LowerSemantic` 1930 行 | ❌ 仅 Plan/typed relation IR + source packages | 无电路证明、无 runtime |

`runtime-tests/` 当前仅 `solana`。`Examples/` 含 Counter / Accumulator / PrivateSum4。

### L7 D3 identity / output —— 工程完成，formal 未完成

- ✅ `TargetRegistryV1` sole membership/default/profile、engineering registry root digest、
  engineering SupportClaim / BuildIdentity carriers、capability resolver、S7a
  `MaterializedArtifactsV1` / S7b `FinalizedArtifactsV1` / S7c disk closure；
  `Materialization/OutputSetV1.lean` 已存在（工程版）。
- ❌ formal `registryDigest` / formal SupportClaim / formal BuildIdentity mint /
  formal `OutputSetV1` / formal ToolchainIdentity；CLI 仍走 transitional v2alpha1 sidecars。

### L8 Release qualification —— 独立轴

- ❌ `TASK-D1-01` blocked；SBOM / eligible-host / clean-room / signing / custody /
  formal evidence pending。按恢复协议，不阻塞产品开发。

## 要做的工作清单（按杠杆排序）

### 第一梯队：Normalize lowering（解锁语言表达力 + 公共组件）

| # | 工作项 | 解锁什么 | 关联 spec |
|---|---|---|---|
| 1 | Map lowering（非空 Map 构造 + Map state/param） | token 余额表、IBC connection/channel 表 | `SPEC-LANG-001` Type `Map`；`SPEC-SEM-001` Map canonical key sort |
| 2 | ContextRead + callerContext（`context.read.<name>`） | owner/authority 检查（token owner、IBC port/channel owner）；接线 authority 轴 | `SPEC-SEM-001` `ContextInputV1`/`Op.ContextRead`；`SPEC-TYPE-001` `context.read.<name>` |
| 3 | aggregate entry/view/fn 返回值 + target ABI struct 返回 | 任何返回结构体的组件（IBC ChannelEnd 查询、token info） | `SPEC-SEM-001` result typing；target dossier ABI |
| 4 | call 返回值 + typed external call（semantic/reference schema 升级） | IBC ack、oracle 返回、跨链 response | `SPEC-SEM-001` "v1 external call 无返回值…加 typed return 必须升级 schema" |
| 5 | Commit 算子 + `disclosure.commit` | 闭合最后一个 disclosure 轴；解锁 private/commitment state 组件 | `SPEC-TYPE-001` `disclosure.commit`；`SPEC-SEM-001` `Op.Commit` |
| 6 | true mutable locals | loop-carried aggregates、复杂算法 | `SPEC-LANG-001` `let` reassign |
| 7 | match 构造器子模式嵌套 | 完整 pattern matching | `SPEC-LANG-001` `ConstructorPattern` nested `PatternList` |
| 8 | Int event/error 字段 + 非 UInt64 call/schedule args & for 端点 | 宽度完整性 | `SPEC-LANG-001` Int widths |

做完前四项即可落地 Fungible Token 与 IBC-flavored 组件（见
[`10-ibc-as-proofforge-programs.md`](10-ibc-as-proofforge-programs.md)）。

### 第二梯队：参考语义 + 证明

| # | 工作项 | 关联 spec |
|---|---|---|
| 9 | ReferenceV1 扩到全 op 集（PureCall/context/commit/aggregates/index/Int/Field/Principal） | `SPEC-SEM-001` `step` 全 carrier |
| 10 | `evalInvariantV1` + `InvariantTheoremV1` + ProofBundleV1 safe loading | `SPEC-SEM-001` Invariant proof ABI / ProofBundleV1；闭合 `TST-SEM-002/003` |

### 第三梯队：target 真制品

| # | 工作项 | 现状 |
|---|---|---|
| 11 | NEAR 真实 bytecode + runtime | 仅 raw-u64 `wat2wasm` 结构验证 |
| 12 | Noir 真实电路证明 + runtime | 仅 Plan/typed relation IR + source packages |
| 13 | EVM 完整 D4 lowering + Reference↔Anvil closure | 当前 solc bytecode 仅 Counter/overflow |

### 第四梯队：formal identity + 发布

| # | 工作项 | 现状 |
|---|---|---|
| 14 | formal D3 carriers（`OutputSetV1` / BuildIdentity / `registryDigest`）+ 退役 v2alpha1 | 工程版已存在，formal 未完成 |
| 15 | Release qualification（SBOM / eligible-host / clean-room / signing） | `TASK-D1-01` blocked，独立轴 |

## 不变量与边界（审查遵循）

- 本审查不声称任何 formal `TASK-*` / `TST-*` 完成；formal 状态以
  [`MIGRATION_MATRIX.md`](../../MIGRATION_MATRIX.md) 为准（当前 D1–D4 = 0/27 done）。
- "已 lowering"指产品 `compileProgramProductV1` 经 `normalizeProgramLocatedV1` 实际产出
  structure-valid `SemanticProgramV1`；"fail closed"指 Normalize 边界拒绝，不产出 carrier。
- target 成熟度以真实制品/运行验证为准，静态 Plan/IR 不算部署或运行完成（与根级
  AGENTS.md 成熟度声明一致）。
- 本文档与 [`10-ibc-as-proofforge-programs.md`](10-ibc-as-proofforge-programs.md) 互补：
  RPT-010 给 IBC 方向，RPT-011 给"覆盖全特性"的整体缺口与顺序。

## 待补充

- 第一梯队每项的具体 Normalize 切片草图（CFG op 序列、wire schema 变更点）。
- 各 target 对 aggregate 返回值 / typed external call 的 ABI 物化路径核对。
- ReferenceV1 扩面与 ProofBundleV1 safe loading 的工程依赖图。