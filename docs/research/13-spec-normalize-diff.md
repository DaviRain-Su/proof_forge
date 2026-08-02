---
id: RPT-013
title: SPEC × NormalizeV1 机械对账（DOC-SPEC-AUDIT）
status: draft
owner: research
updated: 2026-08-02
normative: false
---

# SPEC × NormalizeV1 机械对账

状态：`draft` · 切片 **DOC-SPEC-AUDIT** · 非 formal

> **执行队列**：缺口关闭回写 [`../engineering-backlog.md`](../engineering-backlog.md)。
> **不**替代 `11-feature-coverage-audit` / `12-target-coverage-matrix`；本文固定 **SPEC 意图 ↔ Normalize docstring/代码边界** 的对照表，供 backlog 校准。

## 方法（可复核）

| 输入 | 用法 |
|---|---|
| `ProofForgeV2/Semantic/NormalizeV1.lean` module docstring L15–123 | **sole** shipped surface 声明（支持 / fail closed / out of scope） |
| `docs/specs/language.md`（SPEC-LANG-001） | ProgramV1 EBNF 分母（抽样章节，非 2k 行全文逐条） |
| `docs/specs/semantic-core.md`（SPEC-SEM-001） | Semantic 核心 / Normalization / reference 意图 |
| `docs/specs/type-effect-system.md`（SPEC-TYPE-001） | 类型/效应意图（短） |
| `docs/research/11-feature-coverage-audit.md` | 分层缺口交叉引用 |
| `docs/engineering-backlog.md` | 工程 ID 映射 |

**非目标**：formal TASK/TST 关闭；完整 EBNF×decoder 行列证明；target Plan 逐 op（见 12）。

**证据等级**：`code-docstring` = Normalize 头注释与当前 HEAD 一致（2026-08-02）；`spec-intent` = accepted SPEC 意图；`backlog` = 工程队列状态。

---

## 1. 总览：地基 vs 产品 lowering

| 层 | SPEC 意图 | 工程事实 | 差距归属 |
|---|---|---|---|
| ProgramV1 grammar | 完整 EBNF 表面 | Loader/Syntax 大子集已产品化 | L1 ≈ 闭；formal D1 独立 |
| CheckV1 | type/effect/bound/disclosure | **六相位**产品门禁（structure→type→effect→bound→disclosure→authority） | full commit check 仍缺 |
| **NormalizeV1** | ProgramV1 → SemanticProgramV1 | **子集 lowering**；其余 `.unsupported` | **主瓶颈**（本文重点） |
| WireV1 structure | 完整 op/CFG 契约 | structure gate 宽于 Normalize | 可装更多；Normalize 未降 |
| ReferenceV1 | admitted `step` 子集 | 工程 admitted；非 formal step | R-1.. |
| Targets | Plan/IR per capability | 四 target 跟 Normalize 子集 | 12 矩阵 |

---

## 2. SPEC-LANG 构造 × Normalize

| ProgramV1 构造（语言意图） | Normalize | 备注 | Backlog |
|---|---|---|---|
| public UInt/Int state/param 多宽 | **LOWERED** | {8..256}；T8 ABI 另轨 | — |
| Field(bn254) / Principal state/param | **LOWERED** | 无源字面量 | — |
| named Struct/Enum state/param | **LOWERED** | N3 | — |
| anonymous Array/Map/Bytes/Option state | **LOWERED** | Map 非空 = empty+IndexSet（N-1）；Wire multi-arg Map Construct 仍 FC | N-1 ✅ N-A3 ✅ N-A4 ✅ |
| init/entry/view/fn/invariant | **LOWERED** | invariant → callable + exact fuel；proof 仅 certification metadata | N-INVARIANT-IR ✅ |
| bare assign / return / assert | **LOWERED** | `assert cond else Err` 仅 zero-arg error | — |
| if / match（stmt+expr） | **LOWERED** | multi-block；嵌套子模式已开；同键 duplicate FC | N-7 深化 |
| let 可变 + field/index rebind | **LOWERED** | bare `x:=e` env rebind 已开（N-6）；param 仍 immutable | N-6 ✅ |
| bounded for | **LOWERED** | 同宽 legal UInt/Int；signed half-open + exact loopBounds；六 target Int induction Plan FC | N-FOR-INT ✅ |
| 算术/位运算/移位/比较/逻辑 | **LOWERED** | Field mod FC；Field/Principal ordering FC | — |
| unary `- ~ !` | **LOWERED** | UInt `-` → `0-x` | — |
| fn / localCall pureCall | **LOWERED** | purity 门禁 | — |
| call / schedule | **LOWERED** | args legal UInt/Int；无返回值 | N-CALL-RET |
| revert / emit | **LOWERED** | shared event/error 字段 public UInt/Int/String；target String ABI 全 FC | N-STR-EVENT ✅ |
| `context.unixTimeSeconds` + `context.caller` | **LOWERED** | 两个 sole wire key（UInt64 / Principal） | N-2 ✅ |
| `commit(x)` | **LOWERED**（label-only） | disclosure 契约已钉（N-3）；pureFn **FC** | N-3 ✅ |
| aggregate entry/view/fn **result** | **partial** | named Struct/Enum 已 LOWERED（N-4）；**匿名 Array/Map/Bytes/Option result 仍 FC**；target ABI 见 12 矩阵 | N-4 ✅ |
| nonempty Map construction | **LOWERED** | 产品 = `Map.empty` + 连续 IndexSet（N-1）；仅 Wire multi-arg Map Construct 仍 FC | N-1 ✅ |
| Field/Principal **source** literals | **FAIL-CLOSED** | 经 param/state | — |
| proof / requires 完整 surface | **FAIL-CLOSED** 于 Normalize 项 | | R-2/R-3 |

---

## 3. SPEC-SEM Op 家族 × Normalize（产品路径）

Wire 可接受的 op 不代表 Normalize 会发出。对照 Normalize docstring + L3 in `11`：

| Op / 语义族 | Normalize 产品 | 说明 |
|---|---|---|
| Literal / Constant / StateLoad/Store | yes | multi-width LE |
| Unary / Binary（算术位逻辑比较） | yes | 见上边界 |
| Construct / FieldGet / FieldSet | yes | named + Option |
| IndexGet / IndexSet | yes | Array/Bytes/Map；bounds 运行时 |
| VariantTag / VariantPayload | yes | match |
| PureCall | yes | pureFn |
| Assert / Emit / ExternalCall / Schedule | yes | void；EffectId 序 |
| ContextRead | **partial** | `unixTimeSeconds` + `caller` |
| Commit | **partial** | label-only identity |
| CheckedCast | 视切片 | structure 可；产品路径以 docstring out-of-scope 为准抽检 |
| block-param loop / join | yes | for + expr match |
| invariant callables / exact fuel | yes | Normalize 产 `.invariant` root + dense InvariantDecl，复用 Wire exact closure/fuel；target 全 FC |

---

## 4. SPEC-TYPE / effect × CheckV1（Normalize 前门）

| 意图 | CheckV1 | 产品 Normalize 依赖 |
|---|---|---|
| structure / type / effect / bound / disclosure | 六相位 sole 权威 | 必须 ok∧analysisComplete |
| authority / custody | **已接线**（T-1 工程子集：entry 写 private 需 `context.caller`） | 第六相位；**非** formal TST-VIS-002 |
| full `disclosure.commit` typing | **已钉**（N-3：private→commitment declass；commitment↛public） | 与 N-3 对齐 |
| `callerContext` | **已接线**（N-2：仅 admit caller/unixTimeSeconds） | ContextExtensionCheck 第七相 |
| extension keys 全表 | 有限 S2 freeze | RequirementsInfer + freeze |

---

## 5. 与 backlog 的校准（2026-08-03 复核更新：本表保留历史 ID 与当前 residual）

| ID | 2026-08-03 复核结论 | backlog 状态 |
|---|---|---|
| **N-1** | 产品 nonempty Map = `Map.empty`+IndexSet 已开；仅 Wire multi-arg Construct FC | **done** |
| **N-2** | `context.caller`（Principal）+ unixTimeSeconds 双 key 已接线 | **done** |
| **N-3** | Commit disclosure 契约已钉（private→commitment declass） | **done** |
| **N-4** | named Struct/Enum result 已开；匿名容器 result + target ABI 仍 FC（剩余缺口见 backlog 2.4 新 ID） | **done**（子集） |
| **N-5** | call 返回值：仅 RPT-014 schema 研究；**产品仍 void，实现 follow-on 未排**（见 backlog 2.4） | **done**（研究） |
| **N-6** | bare `x:=e` env rebind 已开；param immutable | **done** |
| **N-7** | 嵌套 ctor/lit/bind 子模式已开 | **done** |
| **N-8** | event/error 与 call/schedule legal UInt/Int 已开；for 的 Int 余量由 N-FOR-INT 闭合 | **done**（子集） |
| **N-FOR-INT** | shared Normalize/Reference 开同宽 Int bounded-for；六 target Int induction Plan FC | **done**（shared-only） |
| **N-STR-EVENT** | shared event/error String payload 已开并进 Reference；target ABI 全 FC | **done**（shared-only） |
| **N-A3** | 单步 IndexSet 已开；**嵌套穿透 `m[k].x` 仍 FC**（余量未排） | **done**（子集） |
| **N-A4** | Option state Normalize admit 已开；全 target Plan FC | **done**（子集） |
| **N-BYTES** | Bytes state+index 已开 | **done** |
| **DOC-SPEC-AUDIT** | 本文 | **done** |

---

## 6. 回流 engineering-backlog（2026-08-03 复核更新）

1. 登记本文路径；DOC-SPEC-AUDIT → done（已登记）。
2. N 家族 done 声明与代码主路径一致；String event payload、Int bounded-for、zero-arg assert-else 与 invariant IR 已闭合。剩余余量为 call 返回值、匿名 result、嵌套穿透与 multi-entry Map Construct，并继续只在 backlog §2.4 排队。
3. 下一产品优先按 backlog 推荐序：先处理 call 返回值 schema 与 call/schedule capability 产品决策，再串行其余 shared-core；target leaf 仅在接口冻结后并行。

---

## 7. 明确不做的声称

- 不声称 formal D2 / TST-SEM-001/002/003 完成
- 不声称 SPEC 全文 EBNF 已 100% 映射
- 不新开第四份平行 gap 清单（缺口只回 backlog + 11/12 更新）

## 变更记录

| 日期 | 事件 |
|---|---|
| 2026-08-02 | DOC-SPEC-AUDIT 初版：Normalize docstring × SPEC-LANG/SEM/TYPE 表 + backlog 校准 |
| 2026-08-02 | 复核刷新：CheckV1 六相位、N 家族 done 状态对齐 HEAD；§2/§3/§4 表修正（let 可变、caller ContextRead、named aggregate result、nonempty Map、authority/custody/commit 已接线）；§5 改为历史对照 + 余量指引 |
| 2026-08-03 | N-FOR-INT：同宽 Int bounded-for 进入 shared Normalize/Reference；六 target signed induction 继续 fail closed |
