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
| CheckV1 | type/effect/bound/disclosure | 五相位产品门禁 | authority/custody/full commit check 仍缺 |
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
| anonymous Array/Map/Bytes state | **LOWERED**（Map 非空构造仍 FC） | Option/Unit/Bool state **FC** | N-A4, N-1, N-BYTES |
| init/entry/view/fn | **LOWERED** | invariant/proof item 仍 FC | INV-1 |
| bare assign / return / assert | **LOWERED** | assert-else **FC** | — |
| if / match（stmt+expr） | **LOWERED** | multi-block；嵌套子模式已开；同键 duplicate FC | N-7 深化 |
| let 不可变 + field/index rebind | **LOWERED** | true mutable **FC** | N-6 |
| bounded for | **LOWERED** | 端点仍 UInt64 | N-8 |
| 算术/位运算/移位/比较/逻辑 | **LOWERED** | Field mod FC；Field/Principal ordering FC | — |
| unary `- ~ !` | **LOWERED** | UInt `-` → `0-x` | — |
| fn / localCall pureCall | **LOWERED** | purity 门禁 | — |
| call / schedule | **LOWERED** | args UInt64；无返回值 | N-5 |
| revert / emit | **LOWERED** | event/error 字段 UInt-only | N-8 |
| `context.unixTimeSeconds` | **LOWERED**（N5） |  sole wire key | N-2 余量：callerContext / 多 key |
| `commit(x)` | **LOWERED**（N5 label） | pureFn **FC** | N-3 余量：disclosure 契约 |
| aggregate entry/view/fn **result** | **FAIL-CLOSED** | ABI scalar | N-4 |
| nonempty Map construction | **FAIL-CLOSED** | | N-1 |
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
| ContextRead | **partial** | 仅 `unixTimeSeconds` |
| Commit | **partial** | label-only identity |
| CheckedCast | 视切片 | structure 可；产品路径以 docstring out-of-scope 为准抽检 |
| block-param loop / join | yes | for + expr match |
| invariant callables / exact fuel | **not product-normalized** | Wire gate 存在；Normalize 不产 invariant root |

---

## 4. SPEC-TYPE / effect × CheckV1（Normalize 前门）

| 意图 | CheckV1 | 产品 Normalize 依赖 |
|---|---|---|
| structure / type / effect / bound / disclosure | 五相位 sole 权威 | 必须 ok∧analysisComplete |
| authority / custody | **缺** | 不进 Normalize |
| full `disclosure.commit` typing | **部分**（Commit 算子 N5） | 与 N-3 对齐 |
| `callerContext` | **缺 / 窄** | N-2 |
| extension keys 全表 | 有限 S2 freeze | RequirementsInfer + freeze |

---

## 5. 与 backlog 的校准（避免假 pending / 假 done）

| ID | 审计结论 | 建议 |
|---|---|---|
| **N-1** | nonempty Map 构造仍 FC；Map state 可能已部分 admit | 保持 pending；拆「构造」vs「state」若实现分叉 |
| **N-2** | ContextRead **已**有 sole key；**非**全 callerContext | 改描述为「扩 key + callerContext + Check 接线」 |
| **N-3** | Commit **已** label-only；非 full disclosure contract | 改描述为「disclosure 契约 + Check」 |
| **N-4** | aggregate results 仍 FC | 保持 |
| **N-5** | call 返回值仍需 schema 升级 | 保持；大切片 |
| **N-6** | true mutable 仍 FC | 保持 |
| **N-7** | 嵌套子模式 docstring 称 open | 复核测例后可 done 或缩范围 |
| **N-8** | Int event/error；非 UInt64 for/call args | 保持 |
| **N-A3** | Map/Bytes 穿透赋值 | 与 IndexSet rebind 对照；可能已部分 |
| **N-A4** | Option state | 仍 FC（无 clean default） |
| **N-BYTES** | Bytes state docstring **admitted** | 状态可能过时 → 复扫代码后标 done 或缩到「产品 String」 |
| **DOC-SPEC-AUDIT** | 本文 | **done** 于本 commit |

---

## 6. 回流 engineering-backlog（本切片动作）

1. 登记本文路径；DOC-SPEC-AUDIT → done。  
2. **不**批量改 N-* 为 done（需代码+测例）；仅在 backlog 备注栏加「见 RPT-013 §5」指针（可选）。  
3. 下一产品优先仍按 backlog 推荐序：Normalize 串行 N-A4 / N-1 / N-2 余量，勿并行改共享核。

---

## 7. 明确不做的声称

- 不声称 formal D2 / TST-SEM-001/002/003 完成  
- 不声称 SPEC 全文 EBNF 已 100% 映射  
- 不新开第四份平行 gap 清单（缺口只回 backlog + 11/12 更新）

## 变更记录

| 日期 | 事件 |
|---|---|
| 2026-08-02 | DOC-SPEC-AUDIT 初版：Normalize docstring × SPEC-LANG/SEM/TYPE 表 + backlog 校准 |
