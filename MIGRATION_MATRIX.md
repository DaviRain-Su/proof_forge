# D1–D4 设计要求与代码完成度矩阵

本文件是 **engineering fact snapshot**，不是 task completion ledger，也不是 formal evidence。

- Snapshot date: `2026-07-25`
- Snapshot commit: `b9adad305b1c914bf5b39b1ef96bfce925ad2c14`
- Formal task source: [`docs/04-task-breakdown.md`](docs/04-task-breakdown.md)
- Test requirement source: [`docs/05-test-spec.md`](docs/05-test-spec.md)
- Product migration decision: [`docs/adr/0019-single-programv1-source-authority.md`](docs/adr/0019-single-programv1-source-authority.md)

## 结论

D1–D4 共 27 个 formal task，当前仍为：

| Milestone | Formal 状态 | Engineering 结论 |
|---|---|---|
| D1 | `TASK-D1-01` blocked，D1-02..08 pending | ProgramV1 wire/hash/NodeId 地基很强；CLI 只接通窄 V1 decoder，Lean command/export 仍在旧轨，worker/diagnostic 未完成 |
| D2 | 7/7 pending | 只有 UInt64 Counter/Accumulator 所需的 alpha Typed/Semantic 子集；正式 SemanticProgramV1、provenance、完整 checker 不存在 |
| D3 | 7/7 pending | 有可运行的 alpha registry/materializer/output/CLI；SupportClaim、BuildIdentity、exact resolver 与 OutputSetV1 不存在 |
| D4 | 5/5 pending | EVM Plan/Yul/ABI/solc/Anvil 算法已有真实功能，可复用；仍绑定 alpha D2/D3 contract，不能按 D4 完成 |

因此当前产品不是 `active/` 中的旧 v1，也不是正式 D1–D4 新设计完成态；准确描述是：

```text
ProgramV1 product subset
  → alpha Typed.Program
  → alpha Semantic.Program
  → alpha descriptor/contains resolver
  → target-owned alpha Plan/IR
  → v2alpha1 output
```

## 完成度口径

| 标签 | 可验证含义 |
|---|---|
| **可复用地基** | 新设计需要的 type、codec、primitive 或算法已存在，但没有完整产品接线 |
| **新轨子集** | 当前 CLI 确实使用 ProgramV1/new entry，但只覆盖规范子集 |
| **旧轨实现** | 行为主要存在于 `Source.Program`、quoted payload 或旧 schema 中 |
| **功能型 alpha** | 有真实端到端行为和测试，但 contract 不是正式 D1–D4 contract |
| **缺失** | 没有对应 production implementation；邻近 primitive 不计完成 |
| **替代就绪** | 新实现是唯一产品路径、已有 TST 迁移完成、旧引用归零并通过删除门禁 |

不使用百分比。formal 状态与 engineering 标签是两条独立轴；development test 成功不能把
`blocked`/`pending` 改成 `done`。

## D1：Source frontend

| Task | Formal | 新设计要求 | 实际代码与产品接线 | 现有测试事实 | Engineering | 迁移与旧代码处理 |
|---|---|---|---|---|---|---|
| `TASK-D1-01` | blocked | token/span、完整 ProgramV1 wire/hash、NodeId、同一 immutable source origin | `ProofForgeV2/Source/*V1.lean` 已有完整 ProgramV1 AST、root codec/decoder/validator、`ValidatedSourceV1`、`sourceHashV1`、57-tag traversal、NodeId assign/collision seam；`SpanV1.lean` 可验证原始 parser span。产品只消费 validated source/hash，没有把完整 Syntax node span 与 NodeId inventory 接入 compiler | `SourceWireAcceptance`、`SourceBoundsAcceptance`、full-tag/field-count/marker/unknown-tag goldens及 independent Python oracle覆盖大量 wire事实；不是 contained frontend integration | **可复用地基**；hash 已接线，origin 未接线 | 建立 immutable parser snapshot到 canonical node preorder的 exact span join。完成后保留 V1模块；删除 legacy source canonical/hash只能等 D2 consumer迁移 |
| `TASK-D1-02` | pending | 唯一 `program ... where` parser直接产出 validated ProgramV1 | syntax command和 `decodeProgramCommandV1Checked` 已存在；CLI的 `selectProgramV1` 使用它。`elab_rules`、`decodeProgramCommandChecked`、`quoteProgram`仍产出/注册 `Source.Program` | `ProgramCommandAcceptance`固定 command正负例，但主要是旧 attributed carrier；`CounterV1Evm`证明 CLI V1 subset | **新轨子集 + 旧轨实现** | 共享 command decoder和Lean elaborator切到V1；删除 legacy decoder/quote和旧 attribute type |
| `TASK-D1-03` | pending | 13种 Phase-1 declaration、完整 type/default elaboration | legacy decoder覆盖 state/struct/enum/const/event/error/init/entry/view/fn/invariant/requires/proof；V1 Loader 已从 Syntax 直接接线 13 种 declaration alternatives，并保留 source order/raw identity；递归 TypeV1 prefix atom decoder内部可构造 primitive/Named/Bytes/Field/Option/Array/Map，但产品 `pfType` surface grammar仍不完整（尤其没有完整 Map surface），全部 declaration negatives 与 D2 typed legality仍未闭合 | `DeclarationAcceptance`仍包装大量 legacy Source AST suites；`ProgramV1Declarations`覆盖 source→Loader V1 的13种 declaration正例、source order、Named边界和少量 legacy fallback/type/extension/proof negatives；ProgramV1 full-tag golden仍是constructed value | **新轨子集 + 旧轨测试残留** | 继续迁移完整 TST-SRC-004 declaration negatives与旧 Source AST tests；替代就绪仍需唯一入口、legacy引用归零和删除门禁，不得经 legacy AST投影 |
| `TASK-D1-04` | pending | 完整 statement/expression/place/pattern；local fn与qualified external call/schedule分流 | grammar/legacy decoder有大量 unary/binary、let/assert/revert/emit/if/for等；V1 Loader 现已从 Syntax 直接构造 `.call/.schedule ExternalCallExprV1`、最小 `.if_/.for_` control-flow slice、`.localCall` / `.constructor` / complete `Place ::= Ident PlaceSuffix*` expression slice（任意混合 `.` field 与 `[Expr]` index suffix，构造嵌套 `.place (.field/.index ...)`）、prefix `-`/`~`/`!` `.unary` expression slice、`+`/binary `-`/`*`/`/`/`%` `.binary` arithmetic expression slice、`<<`/`>>` `.binary .shl/.shr` shift expression slice、`==`/`!=` `.binary .eq/.ne` equality expression slice、`<`/`<=`/`>`/`>=` `.binary .lt/.le/.gt/.ge` ordering comparison expression slice、`.literal (.string value)` string literal expression slice（entry return/let-value positions，含 empty/ASCII/escaped quote/backslash/tab/newline/Unicode scalar decoded values、alternate Lean escape spelling canonical identity、string payload/tag hash non-aliasing、redundant grouping identity 与 parser-boundary negatives）、dot-only `.place (.field ...)` field-place slice与任意 PlaceSuffix chaining slice（bare/field/index/mixed-chain rvalue 与 assignment target，含 multi-field/source suffix order、escaped raw component canonical identity、unary/binary operands、canonical ProgramV1 bytes/sourceHash equality、field-vs-whole-escaped-name/depth/order/suffix-kind non-aliasing、malformed dot/index boundaries、reserved component order、target-before-rhs 与 earlier-suffix-before-later-suffix priority，并固定 uppercase/lowercase root case-sensitive identity、constructor/local-call parentheses classification、terminal qualified-base index acceptance，继续拒绝 `(x)[0]`/`f()[0]`）、core statement slice（annotated/omitted-type `.let_`、simple-component、field-place及任意 place-suffix target `.assign`、valued/value-less `.return_`、`.assert_`/assert-else）、statement-level `.match_` slice（`match Expr with` + 一个或多个 `| Pattern => do Block` arms，Pattern 新增 `ConstructorPattern ::= QualifiedId "(" PatternList? ")"`，空参数、嵌套与混合参数 patterns 经 `pfPattern` max-precedence form 与现有 qualified-id helper 解码为 `PatternV1.constructor`，保留 scrutinee/arm/pattern/body source order、raw identity 与 canonical hash binding；wildcard/bind/bool/integer/string literal 行为不变，单组件 call-like pattern 继续 fail closed，nested match statements 递归解码；expression-level MatchExpr 与 legacy Source reader 保持 fail closed）以及 `.revert`/`.emit` statement slice，保留 raw qualified components、escaped embedded-dot raw components、args/index/source order、unary/binary operator与 operand order、same-tier left-assoc（含 shift cross-operator同层）、MulExpr over AddExpr、AddExpr/MulExpr/UnaryExpr over ShiftExpr、Shift/Add/Mul/Unary over equality、shared comparison-tier ordering/equality chain non-associativity、`&`/`^`/`|` bitwise operator tag/source-order/raw escaped identity、bitwise left-assoc/right-nested grouping、Compare > bit-and > bit-xor > bit-or precedence、bitwise preservation of higher unary/arithmetic/shift behavior、enum variant pipe coexistence、`&&`/`||` logical operator tag/source-order/Bool/raw escaped dotted place identity、logical same-tier left-assoc/right-nested grouping、Compare > `&` > `^` > `|` > `&&` > `||` precedence、logical preservation of higher unary/arithmetic/shift behavior、logical redundant grouping canonical identity/hash non-aliasing/malformed digraph boundary/left-before-right portable-name errors、unary-over-multiplicative、grouping override/canonical redundant grouping identity、nested/dangling-else ownership、statement/source order、raw iterator/binder/target/condition/error/event identity、revert/emit argument count/order/nested expression shape与 loop endpoint order；`decodeNameV1` 已在 ProgramV1 Syntax decoder 层拒绝多 component Lean Name，whole-escaped dotted identifier 仍是一个 raw component，unescaped qualified revert/emit name 在 D2 error/event lookup 尚未迁移前 fail closed；dot-only field-place chains（含 uppercase/lowercase roots）与任意 mixed PlaceSuffix chains 已迁移；并拒绝 one-component/reserved/legacy string、malformed core/if/for/call-like/index/arithmetic/shift/revert/emit/place-suffix、reserved iterator/callee/path/base/binder/target/error/event、`(x)[0]`/`f()[0]` grouped/call base suffix 和非法/越界 exact decimal bound；固定除零/模零与 shift count 0/64只形成 Source AST，不做 D1 numeric/width/sign求值或拒绝；仍缺 expression-level MatchExpr、剩余 pattern forms、D2 error/event lookup、typing/effect、Semantic rollback、event runtime与target behavior等完整迁移。shared grammar 仍保留 string-call shape 用于稳定拒绝，不能写成 string grammar 已删除 | `ProgramV1ExternalStatements`、`ProgramV1ControlFlow`、`ProgramV1MatchStatements`、`ProgramV1ConstructorPatterns`、`ProgramV1ExpressionForms`、`ProgramV1UnaryExpressions`、`ProgramV1ArithmeticExpressions`、`ProgramV1ShiftExpressions`、`ProgramV1EqualityExpressions`、`ProgramV1OrderingComparisons`、`ProgramV1BitwiseExpressions`、`ProgramV1LogicalExpressions`、`ProgramV1CoreStatements`、`ProgramV1FieldPlaces`、`ProgramV1IndexedPlaces`、`ProgramV1PlaceSuffixes`、`ProgramV1RevertEmitStatements` 与 `ProgramV1StringLiterals` 是聚焦 source→ProgramV1 suites；`Tests/Language/*Statements.lean`、operator suites（含 CheckedSub/CheckedMul/CheckedDiv/CheckedMod/CheckedNeg/ShiftLeft/ShiftRight/BitwiseNot/LogicalNot/Grouping）与 legacy expression suites 仍固定旧 Source AST | **旧轨实现 + 新轨子集** | formal 仍 pending；继续迁移剩余 statement/expression/place forms、未迁移 pattern forms、旧 statement/operator suites 与 legacy decoder/grammar reader；未达到删除门槛，不删除旧代码 |
| `TASK-D1-05` | pending | accepted ADR-0019要求 `proof-forge.program-export.v2` + canonical ProgramV1 root bytes | `ProgramExport.lean`登记 `proof-forge.program-export.v1`，attribute type固定 `Source.Program`；`ProgramPayload.lean`穷举重建quoted legacy constructor | `ProgramExportAcceptance`、`ProgramExports`、`ProgramPayloads`固定v1 schema/旧重建行为 | **旧轨实现** | 原子切到 `ProgramExportPayloadV2`；reconstruction只调用正式 root decoder；拒绝并删除v1 row/type/reader。Task表中的旧 `Source.Program`措辞不覆盖 accepted ADR-0019方向 |
| `TASK-D1-06` | pending | multi-program loader、raw component identity、exact `--program` selection | `parseProgramsV1`/`selectProgramV1`与raw `SourceQualifiedNameV1`已存在并被CLI调用；旧 `parsePrograms`/`selectProgram`并存，未接v2 export或worker | `Tests/Language/Loader.lean`及CLI product-negative有selection/`--module`负例；大量断言仍针对legacy APIs | **新轨子集** | 统一source/export selection contract；删除旧Loader APIs和rendered String identity |
| `TASK-D1-07` | pending | stable DiagnosticV1 code/schema/order/redaction和source origin | `Core/Diagnostic.lean`只有alpha `CompileError`；V1 decoder的大量String最终压成 `PF-SRC-INVALID`，CLI没有规范JSON bundle | 局部tests固定若干字符串/code；没有完整 `TST-DIAG-001` schema/redaction harness | **可复用地基** | 实现typed diagnostic bundle、稳定priority/origin/redaction和human/JSON renderer；迁移测试后移除String error seam |
| `TASK-D1-08` | pending | no-follow safe-open、contained frontend worker、ResourceProfileV1 supervisor/receipt | `Core/Common.lean`已有ResourceProfileV1和lower-only validation；CLI只有relative path/`realPath` containment与进程内 `readFile`/parser，无worker、timeout/OOM containment或receipt | Source bounds和negative shell tests覆盖部分size/path；不能关闭worker/process escape面 | **可复用地基 + 缺失** | 新建frontend worker protocol/safe-open/supervisor；CLI切换后移除不受控进程内source open入口 |

## D2：Type/effect/semantic core

| Task | Formal | 新设计要求 | 实际代码与产品接线 | 现有测试事实 | Engineering | 迁移与旧代码处理 |
|---|---|---|---|---|---|---|
| `TASK-D2-01` | pending | 完整name/type checker、pure-fn call graph、invariant/proof-reference source binding | `Typed.checkV1`直接读 `ValidatedSourceV1`，但输出 `Core/Typed.lean`的alpha model，支持state/init/entry/view、UInt64 literal/name/add/call子集；struct/enum/const/fn/invariant/proof均拒绝 | `ValidatedSourceV1Pipeline`、`TypedNameIndex`和大量legacy fail-closed tests；没有完整 typed fixture | **新轨子集** | 建完整V1 typed model/checker，不依赖 `Source.ValueType`/alpha Typed；迁移全部 declaration和fn/proof binding |
| `TASK-D2-02` | pending | effect/call/view checker及pure-fn transitive effects | 仅在alpha checker中禁止view写state/同步call；requirements按少量semantic op推导，无fn propagation/effect lattice | `Core/Semantics`/pipeline覆盖少量view/operation负例 | **功能型 alpha 子集** | 分离effect pass，计算call graph closure并固定 `PF-EFFECT-*`；删除内嵌最小规则 |
| `TASK-D2-03` | pending | loop/call/recursion bound与termination | parser有syntax depth/node/for literal bound，targets有Plan resource guard；没有D2 fn SCC/termination/effect occurrence bound | `SourceBoundsAcceptance`与target resource tests只覆盖邻近边界 | **缺失** | 实现target-neutral termination/bound pass；不把parser/target资源限制冒充业务termination |
| `TASK-D2-04` | pending | disclosure/authority/custody checker | Source/alpha Typed/Semantic保留visibility，requirements会产生private/commitment标记；没有information-flow、authority guard或custody analysis | target negatives能拒绝某些非public shape；无完整 `TST-VIS-001/002` | **可复用地基** | 实现独立flow pass和稳定diagnostics；source visibility carrier可迁移，旧alpha inference删除 |
| `TASK-D2-05` | pending | canonical ProgramRequirements inference、predicate merge与origin | `Semantic.deriveRequirements`只对13项 `ProgramRequirement` enum做source-order stable-unique；无SemVer/digest/predicate/merge/origin | semantic tests固定enum集合及target rejection | **功能型 alpha** | 改为exact RequirementRef/Predicate canonical merge；业务值进SemanticProgramV1，origin按index进provenance |
| `TASK-D2-06` | pending | closed SemanticProgramV1 serializer/decoder、SemanticProvenanceV1、proof-bundle signature validation | `Core/SemanticIR.lean`明确标注“current Phase-1 subset”；只有自定义encoder/hash，无strict decoder、完整model、provenance或proof bundle validation | `Tests/Core/Semantics.lean`固定alpha bytes/hash；不是 `SPEC-SEM-WIRE-001` full-tag/cross-implementation验收 | **功能型 alpha + 正式协议缺失** | 按 owning `ProofForgeV2.Semantic.WireV1` contract新建完整closed model/codec/provenance/proof join；四target迁移后删除alpha IR |
| `TASK-D2-07` | pending | reference step interpreter：Invocation/context/responses/Outcome/effect/rollback | `Core/Semantics.lean`只解释UInt64 state/literal/add/store/return；同步call要求显式response但实际直接拒绝；无effect occurrence或规范Outcome | `Tests/Core/Semantics.lean`覆盖Counter式happy/overflow子集 | **功能型 alpha 子集** | 实现完整reference semantics和rollback differential oracle；新oracle替代后删除旧interpreter |

## D3：Registry、resolver、materializer与OutputSet

| Task | Formal | 新设计要求 | 实际代码与产品接线 | 现有测试事实 | Engineering | 迁移与旧代码处理 |
|---|---|---|---|---|---|---|
| `TASK-D3-01` | pending | TargetId、CodegenProfileId、NetworkProfileId三个独立typed parser | `Core/Diagnostic.lean`有TargetId enum/parse；descriptor和manifest中的codegen profile是裸String；无NetworkProfileId产品路径 | target parse/negative覆盖TargetId；无三ID exact parser suite | **可复用地基** | 引入三个独立identity/parser/renderer并迁移CLI/registry；删除裸String dispatch |
| `TASK-D3-02` | pending | static registry canonical digest、duplicate rejection、exact target/profile lookup | `Targets/Registry.lean`是hardcoded arrays/match；没有完整descriptor/profile payload或duplicate validation | `Tests/Materialization/Targets.lean`检查当前四target行为 | **功能型 alpha** | 建typed static registry和canonical digest；设计-only与implemented lookup按spec fail closed |
| `TASK-D3-03` | pending | ProgramRequirements → exact SupportClaim/claimDigest + BuildIdentity/ProfileSupportIndex | `Targets.resolve/checkSupport`只做 `supportedRequirements.contains`；production Lean中没有SupportClaim、BuildIdentity、ProfileSupportIndex | target negative固定unsupported enum；没有predicate/evidence binding矩阵 | **缺失** | 实现exact claim/predicate implication、aggregate diagnostics和binding resolution；`specified`空binding合法，更高grade无真实binding时零输出拒绝 |
| `TASK-D3-04` | pending | associated Plan/TargetIR protocol含schema、CodegenProfile、validation、EmitContext | `Materialization/Protocol.lean`已有associated `Plan`/`TargetIR`，但method是alpha `makePlan/lower/emit`，缺schema、validateTargetIR、IO EmitContext | target modules证明Plan type未擦除；没有正式boundary compile test | **可复用地基** | 升级接口并让四target直接实现；不得用Unit/string/JSON或兼容adapter保留旧API |
| `TASK-D3-05` | pending | OutputSetV1、support-decisions、manifest schema/digest、exact file closure与atomic publish | alpha OutputSet/OutputManifest和 `CLI/Emit.lean`具备路径检查、staging rename、no-clobber；schema为 `proof-forge-output/v2alpha1`，没有candidate/build/plan/IR/tool/support digest | `Tests/CLI/Emit.lean`与output shell negatives覆盖alpha原子性；artifact validator固定alpha manifest | **功能型 alpha** | 实现完整v1 manifest/decision-set/closure/rollback；迁移consumer后删除alpha manifest/evidence sidecar contract |
| `TASK-D3-06` | pending | `check/build/inspect/list-targets`、profile/evidence/resource flags、stable human/JSON | CLI只有list-targets、describe-target、build、build-counter；缺check/inspect/profile/minimum evidence/resource override/JSON | CLI emit与shell product-negative覆盖当前窄参数面 | **功能型 alpha 子集** | 实现规范command surface；删除ad-hoc `describe-target`/`build-counter`产品入口 |
| `TASK-D3-07` | pending | contained compiler-core/tool/output supervisor、effective profile digest/receipt和whole cleanup | Toolchain有exact locked execution/isolated env，Common有resource profile；compiler-core/output仍进程内，无统一receipt/whole-containment | `ToolchainPolicy`、toolchain negatives覆盖selected closure；不能关闭core/output process containment | **可复用地基 + 缺失** | 实现三stage supervisor/receipt/signal cleanup；保持与TaskQualification ceremony完全分离 |

## D4：EVM

| Task | Formal | 新设计要求 | 实际代码与产品接线 | 现有测试事实 | Engineering | 迁移与旧代码处理 |
|---|---|---|---|---|---|---|
| `TASK-D4-01` | pending | versioned EvmPlan schema、canonical invariants/hash和resolved identity binding | `Targets/Evm.lean`有target-owned Plan、storage/selector/ABI/resource/shape validation；无正式schema/canonical serializer/BuildIdentity binding | `Tests/Materialization/EvmSmoke.lean`有Plan mutation/shape测试 | **功能型 alpha，可大量复用** | 保留算法，增加schema/hash/decision binding；旧alpha Plan public contract随后删除 |
| `TASK-D4-02` | pending | validated SemanticProgramV1 → EvmPlan | `makePlan`从alpha `ResolvedProgram .evm`通用lower UInt64 fragment；Counter和非Counter Accumulator均成功，无fixture/name matcher | `CounterV1Evm`、`EvmSmoke`、Accumulator runtime证明算法非模板 | **功能型 alpha，可大量复用** | 直接迁到new ResolvedProgram/SemanticProgramV1，不经过adapter；保留unsupported fail-closed |
| `TASK-D4-03` | pending | EvmPlan → validated TargetIR/Yul + ABI | 有typed IR、dynamic Keccak selector、Yul/ABI renderer；`lower`先validate Plan，但没有TargetIR schema/hash/trace validation | EVM smoke、artifact validator固定selectors/ABI/Yul | **功能型 alpha，可大量复用** | 加TargetIR schema/validator/hash/trace，接D3 Materializer/EmitContext；移除alpha emit signature |
| `TASK-D4-04` | pending | locked solc bytecode packaging到OutputSetV1 | 真实source已通过digest-pinned solc 0.8.34生成bytecode；selected-tool closure已修复。solc仍由 `CLI/Emit.finalizeEvm` target-special-case，输出alpha manifest | `ToolchainPolicy`、target-smoke、solc-only root positive/full release-root negative通过 | **功能型 alpha** | 将ToolchainIdentity、bytecode validation和artifact roles移入EVM emitter/OutputSetV1；删除CLI inline finalize |
| `TASK-D4-05` | pending | Anvil Counter与reference interpreter differential | `scripts/smoke_evm.sh`已验证Counter和Accumulator init/mutate/read/UInt64 overflow rollback | 当前开发机真实Anvil smoke通过；不是新Semantic/Output contract上的formal TST closure | **功能型 alpha** | 新D2/D3/D4唯一路径完成后重跑reference-vs-Anvil；旧结果只作回归，过期hash/golden删除 |

## 共享迁移依赖

删除 D2/D3 alpha core 不只是 EVM 问题。当前以下 consumers 都直接 import旧 shared types：

| Consumer | 当前 maturity | 迁移要求 | 不得顺带声称 |
|---|---|---|---|
| EVM | runtime-validated alpha | 完整迁入 D4新contract | D4 formal done，除非全部TST/formal条件真实闭合 |
| Solana | plan-only | 机械改接新 Semantic/ResolvedProgram/Materializer/OutputSet，保留target-owned Plan/IR | sBPF ELF或runtime完成 |
| NEAR | Wasm-validated alpha | 机械改接新shared contract，保留NEAR Plan/Wasm算法 | sandbox receipt或D6完成 |
| Noir | source-only | 机械改接新shared contract，继续non-deployable | ACIR/witness/proof/VK/verify或D7完成 |

如果任一 consumer仍import旧类型，相关删除行保持 `blocked by consumer`，不得增加公开兼容层来伪造归零。

## 旧代码退役清单

| 层 | 旧实现候选 | 当前删除状态 | 删除门槛 |
|---|---|---|---|
| D1 frontend | `Syntax.lean` legacy decoder/quote/elab；Loader legacy APIs；`ProgramExport` v1；quoted `ProgramPayload`；string-call语法；legacy-only fixtures | **未满足** | 完整V1 declaration/stmt parser、span/NodeId、v2 export、selection、DiagnosticV1、worker都成为唯一入口 |
| D2 core | `Core/Source.lean`、`Core/Typed.lean`、`Core/TypedV1.lean`、`Core/SemanticIR.lean`、`Core/Semantics.lean`、`Compiler.compile(Source.Program)` | **未满足** | 完整Typed/Semantic/provenance/interpreter完成，四target consumer全部直接迁移，imports归零 |
| D3 framework | alpha TargetDescriptor/contains resolver、旧 Materializer signature、v2alpha1 OutputSet、旧 CLI staging/finalize seams | **未满足** | typed registry/resolver/BuildIdentity/OutputSetV1/supervisor完成，四target直接实现新protocol |
| D4 EVM | alpha EVM descriptor/materialize入口、CLI inline solc finalize、alpha manifest assertions和过期 plan-hash goldens | **未满足** | 新EvmPlan/TargetIR/OutputSetV1上Counter+Accumulator deterministic build及Anvil differential全绿 |

## 每次删除的机械门禁

1. 新实现已经是 CLI、Lean command、Loader/compiler和相关target的唯一产品入口；没有flag、fallback或第二reader。
2. `ProofForgeV2/**`、`Tests/**`、Lake入口和当前scripts对旧symbol/type/schema引用为零；历史文档只能以historical文字保留。
3. 旧正例、负例、边界和diagnostic priority已迁到新carrier，不能靠删测试获得绿色。
4. 所有shared consumers已直接迁移；不保留长期adapter。
5. 聚焦测试、`just dev-check`、`just ci`、`just target-negative`、`git diff --check`通过；EVM删除再要求deterministic target-smoke和Anvil differential。
6. `ProofForgeV2/**`变化已刷新并核对 `supply-chain/lean-package-files.v1.json`。
7. 本矩阵更新replacement、remaining consumers、删除文件和实际验证；formal task状态只按其独立规则变化。

## 下一实施顺序

1. 完整迁移 ProgramV1 declaration decoder和 `TST-SRC-004`现有测试断言。
2. 继续迁移 expression-level MatchExpr、剩余 pattern/expression/place forms、旧 statement/operator suites 和 `TST-SRC-005`。
3. 接通span/NodeId inventory，原子切Lean command/export/Loader到ProgramV1 v2 schema。
4. 完成DiagnosticV1和contained frontend worker，随后删除D1 legacy frontend。
5. 按 D2 → D3 → D4迁移shared core和EVM；shared cutover时机械迁移另外三个target consumers。
