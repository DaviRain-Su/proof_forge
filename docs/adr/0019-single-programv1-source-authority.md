---
id: ADR-0019
title: ProgramV1 单一 source authority 与 alpha cutover
status: proposed
owner: architecture
updated: 2026-07-19
normative: true
---

# ADR-0019：ProgramV1 单一 source authority 与 alpha cutover

## 背景

当前可运行 frontend 由 ProofForge DSL 构造 `ProofForgeV2.Core.Source.Program`，而
`SPEC-SOURCE-WIRE-001` 已定义 source-order-preserving `ProgramV1`、raw component identity、
canonical bytes 与 NodeId。两者不是同一模型：alpha `Program` 按 declaration kind 分桶并使用
rendered `String` identity；`ProgramV1` 保留 source order并使用 raw component array。继续维护两套
parser projection、validator 和 source hash 会让相同源码拥有两个互相漂移的 source authority。

当前 language/source schema 均未发布 accepted release，现有实现与 evidence 明确标为 alpha /
pre-acceptance。因此本决定按 alpha reset 收敛实现，不承诺生产 reader 双轨兼容；已保存的 alpha
hash 不是 ProgramV1 hash，也不得作为新 schema golden。

## 决定

1. `ProgramV1` 是唯一 canonical source AST。DSL decoder、CLI Loader、Lean command、persistent
   export reconstruction 与 wire decoder最终都只产生 validated ProgramV1 source unit。
2. canonical source unit 精确携带 `moduleName`、`programIdentity` 与 `program : ProgramV1`。
   module identity 是 host boundary 的显式语义输入；诊断文件名、绝对路径与项目相对路径不得推导、
   覆盖或进入 canonical identity。各 host 的具体取得方式必须在对应 parser/CLI cutover slice 冻结。
3. declaration/source-shape validation、canonical bytes 与 `sourceHashV1` 只属于 ProgramV1 路径。
   alpha `Source.Program.canonicalBytes/sourceHash` 立即进入冻结退役状态，不得承载新语法或身份规则。
4. Typed 尚未直接消费 ProgramV1 时，只允许一个 compiler-private、单向
   `ProgramV1 → legacy Typed input` lowering。它不得公开、持久化、反向转换、排序或修复 AST、运行
   第二套 declaration validation、计算 hash、提供 fallback，且任何不可表示 constructor 必须拒绝。
5. surface external call 采用 `call QualifiedId(ExprList?)` / `schedule QualifiedId(ExprList?)`，与
   ProgramV1 `ExternalCallExprV1` 一致。现有 `call "arbitrary string"` 是未发布 alpha spelling，生产
   reader cutover 时删除；不得 split string、虚构 namespace 或丢弃 args。外部 alpha source 如需迁移，
   独立offline source-text rewrite tool必须由调用者显式给出old string到QualifiedId的mapping；它不得被
   compiler import或作为fallback。歧义以`PF-MIGRATION-FAILED`拒绝且不修改原文件。
6. persistent export payload meaning切换到 ProgramV1 时必须发布新 export schema，或在正式冻结前记录
   经评审的 alpha-reset schema裁决；不得让同一 schema string 同时解释 legacy Program 与 ProgramV1。
7. production/compiler路径不建立legacy AST→ProgramV1 adapter，不做两套validator/hash parity，不保留
   双向round-trip。第5条offline tool只改写source text，不接收或产生legacy内存AST。

## 迁移顺序

1. 建立 validated ProgramV1 source unit 与唯一 `sourceHashV1`。
2. 建立 private one-way Typed lowering及其 import allowlist。
3. 原子切换shared DSL decoder、Loader/Compiler/CLI与Lean command；Lean command carrier type和persistent
   export schema/reconstruction在同一cutover gate切换，不允许ProgramV1 decoder继续发布legacy export。
4. 完整ProgramV1 binary root decoder落地后，可让persistent export reconstruction复用该decoder；不得
   恢复legacy payload作为中间格式。
5. Typed 直接消费 ProgramV1 后删除 lowering、`Core.Source.Program`、alpha canonical/hash 与 legacy payload。

不要求等待完整 ProgramV1 binary decoder才开始前四项；但最终 persistent export 可等待完整 root decoder，
以避免新增另一套大型 quoted-expression decoder。等待不得成为继续扩展 legacy AST 的理由。

## 机械删除门槛

- production parser/Loader/elaborator/export 均无 legacy `Source.Program` 返回或构造；
- `Compiler.compile` 只接受 validated ProgramV1 source unit，sourceHash只来自 `sourceHashV1`；
- canonical declaration order唯一来自 `ProgramV1.items`，cross-kind reorder改变 bytes/hash；
- Lean command、ParserSession 与 export reconstruction 的 module/program identity、ProgramV1、bytes/hash相等；
- production 不存在 legacy→ProgramV1、第二套 validator/hash或 old string-call reader；
- 过渡期 `Core.Source` import仅允许 private lowering与尚未迁移的 Typed owner，最终归零；
- 旧 alpha hash fixtures不被重新标记为 ProgramV1 goldens。

## 否决方案

- 同一 decoder 同时构造两个 AST：会复制默认值、identity和错误优先级。
- 长期 parity adapter：模型不保序且 call identity不等价，无法证明无损。
- 一次性重写 frontend、Typed、export与targets：blast radius过大，难以在冻结的四小时切片内验收。

## 后果

迁移期仍存在 legacy Typed carrier，但它是明确不可观察的下游实现细节，不再是 source authority。
ProgramV1 source order和raw identity会改变既有 alpha hashes；这是预期 cutover，而不是需要兼容的回归。
