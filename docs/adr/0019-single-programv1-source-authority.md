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

在本 ADR 转为 `accepted` 前，下述决定只作为可撤销的 pre-acceptance development hypothesis；
accepted 文档中的 `Source.Program` compiler path仍是现行 authority。PA109 不修改frontend/call sites/
export，不构成source-authority cutover、正式TASK关闭或release API承诺。

## 决定

1. `ProgramV1` 是唯一 canonical source AST。DSL decoder、CLI Loader、Lean command、persistent
   export reconstruction 与 wire decoder最终都只产生 validated ProgramV1 source unit。
2. canonical source unit 精确携带 `moduleName`、`programIdentity` 与 `program : ProgramV1`。
   module identity 是 host boundary 的显式语义输入；诊断文件名、绝对路径与项目相对路径不得推导、
   覆盖或进入 canonical identity。直接 Lean command 路径只接受 outer build invocation 已显式设置的
   main-module `Lean.Name`，按 root-to-leaf 顺序投影 pure `.str` raw components；anonymous、`.num`、
   缺失 main module 或任一不满足 `SourceNameComponentV1` 的 component 均在 quote/register 前 fail
   closed。ParserSession/one-shot Loader/CLI 不从 `fileName` 或 source path 猜 module：`check`/`build`
   必须接收独立 `--module <lean-module-name>`，value 由锁定 Lean identifier parser exact-consume 后投影
   同一 pure `.str` raw array；CLI path 仍只用于读取与 diagnostics。`programIdentity` 唯一等于
   `moduleName.components ++ activeNamespace.components ++ declarationName.components`；duplicate、
   `--program` selection 与双入口 parity 均比较 raw arrays，CLI 的 qualified selector同样由锁定 Lean
   identifier parser解析，禁止 dotted-string split/render comparison。
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
6. persistent export 在 cutover 后唯一 schema 为 `proof-forge.program-export.v2`；v1 row、v1 attributed
   constant type与v1 reader一律拒绝，不提供dual-read、自动升级或fallback。v2 attributed declaration
   携带封闭 `ProgramExportPayloadV2`（exact schema string + canonical ProgramV1 root bytes），persistent
   extension row只登记v2 schema与declaration lookup handle。reconstruction先bounded、穷举解码该常量的
   scalar/ByteArray表达式，再且只调用
   `decodeCanonicalSourceAstBytesV1 : ByteArray → Except Diagnostic ValidatedSourceV1`；不得在export层
   重建ProgramV1 constructor、validator、identity或hash。registry declaration只是Lean lookup handle；
   decoded unit必须满足`programIdentity = moduleName ++ rawComponents(declaration)`，其中declaration是
   Lean environment中的namespace+decl lookup name且本身不隐含main-module prefix；不得沿用legacy
   rendered full-string equality。
7. production/compiler路径不建立legacy AST→ProgramV1 adapter，不做两套validator/hash parity，不保留
   双向round-trip。第5条offline tool只改写source text，不接收或产生legacy内存AST。

## 迁移顺序

1. 建立 validated ProgramV1 source unit 与唯一 `sourceHashV1`。
2. 建立 private one-way Typed lowering及其 import allowlist。
3. 完整实现并验收 `decodeCanonicalSourceAstBytesV1`；它是v2 export reconstruction与原子cutover的硬
   prerequisite，不允许以legacy或另一套quoted ProgramV1 decoder代替。
4. 原子切换shared DSL decoder、Loader/Compiler/CLI与Lean command；Lean command carrier type和persistent
   export schema/reconstruction在同一cutover gate切换，不允许ProgramV1 decoder继续发布legacy export。
5. Typed 直接消费 ProgramV1 后删除 lowering、`Core.Source.Program`、alpha canonical/hash 与 legacy payload。

等待完整 root decoder 不得成为继续扩展 legacy AST 的理由；decoder完成前可以做独立、可撤销的
ProgramV1 pre-acceptance slice，但不得切换任一production frontend/export入口。

## 机械删除门槛

- production parser/Loader/elaborator/export 均无 legacy `Source.Program` 返回或构造；
- `Compiler.compile` 只接受 validated ProgramV1 source unit，sourceHash只来自 `sourceHashV1`；
- canonical declaration order唯一来自 `ProgramV1.items`，cross-kind reorder改变 bytes/hash；
- Lean command、ParserSession 与 export reconstruction 的 module/program identity、ProgramV1、bytes/hash相等；
- CLI `--module`、Lean main-module identity与v2 export declaration suffix join均按raw component array验证，
  file/source path与rendered dotted string不参与identity；
- production只接受`proof-forge.program-export.v2`与`ProgramExportPayloadV2` canonical root bytes，且只经
  `decodeCanonicalSourceAstBytesV1`重建；v1 schema/type/reader与独立quoted ProgramV1 decoder均不存在；
- production 不存在 legacy→ProgramV1、第二套 validator/hash或 old string-call reader；
- PA109 后、frontend cutover 前，production direct `Core.Source` import只允许root umbrella、
  `CLI/Toolchain`、`Compiler/Pipeline`、`Core/Typed`、`Language/ProgramExport`、`ProgramPayload`与
  `Syntax`七个路径；frontend/export原子切换后只允许Pipeline与Typed，Typed直接消费ProgramV1后归零；
- 旧 alpha hash fixtures不被重新标记为 ProgramV1 goldens。

## 过渡 Typed lowering 精确边界

过渡 lowering 采用窄、fail-closed 投影，而不是复制全部 legacy AST：只接收当前 `Typed.check`
真正可执行的 `state`/`init`/`entry`/`view`；type只接受Bool、固定宽度UInt/Int、Principal、Unit、
0..4096 Bytes、递归Option、0..4096 Array与raw id精确为`bn254_fr`的Field；expression只接受
UInt64 integer/name-place/add，statement只接受
simple-name assign、value return 与零参数 external call。其他 top-level item、named/map type、超出
UInt64 的 integer、非 name place、其他 expression/statement、`schedule` 与非空 call args 在 private
lowering 中按 source order/constructor-before-child 拒绝；不得为了复用 Typed 的 unsupported diagnostic
而先丢失信息。通过 lowering 的 name resolution、type/effect、return 与 view legality 仍只由 Typed 检查。

unqualified name 精确使用 raw component；qualified program/callee identity 以 ordered raw components
构造完整 pure `.str` Lean `Name` 后只调用一次 `Name.toString`。禁止 `String.intercalate`、split、逐
component render/拼接、路径推导或 normalization。nonempty call args 必须在遍历参数前拒绝，不能静默
丢弃；`schedule` 不能降成 synchronous call。

迁移期 compiler 新入口只接受 validated unit。private lowering 不调用 validator、canonical encoder、
`sourceHashV1`、legacy builder或legacy canonical/hash API。compiler必须先完整lowering，再调用Typed；
只有两者成功后才各调用一次`sourceHashV1`与`renderDigest`，以exact `sha256:` prefix和64 lowercase hex
检查后把suffix投影到当前Semantic alpha String carrier，最后调用`Semantic.fromTyped`。该投影不是第二个
hash或可复用identity API。lowering按items/arrays/block source order、record/wire field order遍历；add先
lhs后rhs、assign先target后value；unsupported parent不访问child，nonempty call args不访问arg。更晚的
lowering error因此先于任何Typed semantic error。frontend原子切换时删除旧`compile(Source.Program)`并
把新入口收敛为唯一`compile`；Typed直接消费ProgramV1时删除整个lowering与import allowlist。

## 否决方案

- 同一 decoder 同时构造两个 AST：会复制默认值、identity和错误优先级。
- 长期 parity adapter：模型不保序且 call identity不等价，无法证明无损。
- 一次性重写 frontend、Typed、export与targets：blast radius过大，难以在冻结的四小时切片内验收。

## 后果

迁移期仍存在 legacy Typed carrier，但它是明确不可观察的下游实现细节，不再是 source authority。
ProgramV1 source order和raw identity会改变既有 alpha hashes；这是预期 cutover，而不是需要兼容的回归。
