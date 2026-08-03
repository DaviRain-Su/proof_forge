---
id: SPEC-SEM-001
title: 目标中立语义核心
status: proposed
owner: semantics
updated: 2026-08-04
normative: true
---

# 目标中立语义核心

## 数据结构

`SemanticProgramV1` 包含 qualified program name、canonical types、logical state、callable CFG、
events/errors、invariants 和无 source origin 的 business requirements，不包含 sourceHash/path/span/
origin map、target/profile/network、ABI selector、storage slot、account meta、Wasm import、circuit opcode
或 deploy address。完整字段、binary wire 与 hash authority 是
[`SPEC-SEM-WIRE-001`](semantic-program-wire.md)。sourceHash 和所有 `SourceOrigin` 只进入该规格的
`SemanticProvenanceV1` companion；companion exact 绑定 sourceHash+semanticHash，但不得反向改写
program 或成为 target resolution 输入。

`invariants` 是按 source declaration traversal 进入 canonicalization、再随其他 ID 一起稳定重编号的
array。每项包含 NFC name 与 typed Bool predicate CFG entry；其 source origin 只存在于 companion
provenance。`InvariantOrdinalV1`
就是 canonical array 的 zero-based `UInt32` index。proof reference、adjacent theorem body、
inline certification digest 与外部 proof-bundle identity 都是 certification metadata，
**不进入** `SemanticProgramV1`，因此不会改变 business `semanticHash`（见
[`ADR-0026`](../adr/0026-inline-same-file-theorem-certification.md)）。

proof ABI 与 reference interpreter 共用 `SPEC-SEM-WIRE-001`/`ProofForgeV2.Semantic.InvariantABI`
唯一声明的 `LogicalStateV1` closed state carrier；不得在本文件、proof bundle 或 target backend
重声明另一种 state type。其 exact fields 是 `initialized` 与 `canonicalValues`，字段/wire authority
只属于 SPEC-SEM-WIRE-001。

`canonicalValues` 是按 `SemanticProgramV1` canonical logical-state declaration order 串接的 type-driven
value encoding；每个 value 先写 `u32le byteLength` 再写 `pf.semantic.v1` 的 exact canonical value bytes，
Map entry 按 canonical key 排序。它不含 path/name、host pointer、origin 或 target layout；program state
schema 决定每段 bytes 的唯一 type/decoder。缺失、额外、noncanonical 或 type-invalid bytes 不构成
`LogicalStateV1` 的可信输入，必须由 `StateConformsV1` 返回 false。该 carrier 本身不作为外部
OutputSet artifact schema。

CFG block 参数采用 SSA value ID；state 操作是显式 logical `stateLoad(stateId)`/
`stateStore(stateId,value)`；
每个 static effect instruction 使用 canonical `EffectId`，动态执行以
`EffectOccurrenceV1(effectId,occurrence)` 标识。Value ID、block ID 按 source traversal 分配并在
canonicalization 时重编号，避免 hash 受内部 hash-map 顺序影响。

## Reference Semantics

以下 target-neutral runtime carriers 与 `step` 的唯一 public owning namespace/façade 是
`ProofForgeV2.Semantic.ReferenceV1`。实现位于lower `ReferenceMachineV1`，只import
`Core.Common`、`WireV1`与`InvariantFoundationV1`；public `ReferenceV1` façade再组合`InvariantABI`，为后续
`InvariantABI → ReferenceMachineV1` formal evaluator依赖保持无环。target adapter 只能转换到/
从这些 closed values，不能声明另一套 normalized outcome：

lower machine可提供仅消费structure-validated decoded program、selected invariant callable与canonical
state的执行seam；该seam不得依赖whole-program engineering admission、选择invariant ordinal或冒用
formal `evalInvariantV1`名称。public ABI负责program validation、ordinal/state/closure join后才能调用它。
machine在value写入、primitive operand、CFG block-param/condition/scrutinee、PureCall bind/result与return
边界必须重新验证exact TypeId/canonical bytes；Unit唯一constructor产生empty canonical bytes。

```lean
structure ReferenceValueV1 where
  typeId     : TypeIdV1
  valueBytes : ByteArray

structure ContextInputV1 where
  key   : SchemaId
  value : ReferenceValueV1

structure InvocationV1 where
  callableId : CallableIdV1
  args       : Array ReferenceValueV1
  context    : Array ContextInputV1

inductive ExternalResponseDispositionV1
  | returned | reverted

structure ExternalResponseV1 where
  occurrence  : EffectOccurrenceV1
  disposition : ExternalResponseDispositionV1

abbrev ExternalResponsesV1 := Array ExternalResponseV1

inductive OrderedEffectPayloadV1
  | event        (eventId : EventIdV1) (args : Array ReferenceValueV1)
  | externalCall (callee : QualifiedName) (args : Array ReferenceValueV1)
  | schedule     (callee : QualifiedName) (args : Array ReferenceValueV1)

structure OrderedEffectV1 where
  occurrence : EffectOccurrenceV1
  payload    : OrderedEffectPayloadV1

inductive StandardRevertCodeV1
  | arithmeticOverflow | arithmeticUnderflow | divisionByZero
  | invalidShift | castOutOfRange | indexOutOfBounds | boundExceeded
  | assertionFailed | uninitialized | alreadyInitialized

inductive SemanticRevertV1
  | declared (errorId : ErrorIdV1) (args : Array ReferenceValueV1)
  | standard (code : StandardRevertCodeV1)
  | externalCallReverted (occurrence : EffectOccurrenceV1)

inductive SemanticFaultV1
  | invalidInvocation | invalidExternalResponse | invalidCore
  | resourceExhausted | unreachable | internalInvariant

inductive OutcomeV1
  | returned (postState : LogicalStateV1) (value : Option ReferenceValueV1)
      (effects : Array OrderedEffectV1)
  | reverted (reason : SemanticRevertV1) (unchangedState : LogicalStateV1)
  | trapped (fault : SemanticFaultV1) (unchangedState : LogicalStateV1)

def step
  (p : SemanticProgramV1)
  (pre : LogicalStateV1)
  (invocation : InvocationV1)
  (responses : ExternalResponsesV1) : OutcomeV1
```

`ReferenceValueV1.valueBytes` 必须被其 `typeId` 的 SPEC-SEM-WIRE-001 canonical value decoder 完整
消费并 re-encode 相等。invocation args 保持 parameter order；`context` 按 key UTF-8 唯一升序，且
必须 exact 等于 selected callable 及其 pure-fn closure 静态可达 `Op.ContextRead` key/type 集合，缺失、
额外、重复或 wrong type 为 `.trapped(.invalidInvocation, pre)`。callableId 必须存在且 kind 只能是
initializer/entry/view；arity/type/kind 不符同样是 invalidInvocation，不能 fallback 到 name dispatch。

`responses` 按实际同步 external-call 执行顺序排列，只为 `Op.ExternalCall` 提供项。validated program/Core
检查先于 invocation；invalid Core 返回 `.trapped(.invalidCore, pre)`。随后 invocation shape/context
检查先于 response cursor；invalid invocation 返回 `.trapped(.invalidInvocation, pre)`，不消费或重新
分类 caller responses。对 valid
invocation，cursor 从 0 开始；每个 external call 要求 `cursor < responses.size` 且该项 occurrence 与
下一个动态 pair exact 相等，然后恰消费一次。missing/duplicate/reordered pair 立即返回
`.trapped(.invalidExternalResponse, pre)`；`.returned` 继续执行，`.reverted` 先形成候选
`.reverted(.externalCallReverted occurrence, pre)`。

所有 valid-invocation terminal candidate——正常 return、declared/standard/external revert、Core trap 或
resource trap——发布前都执行一次 exhaustion check：只有 `cursor == responses.size` 才保留候选；否则
统一覆盖为 `.trapped(.invalidExternalResponse, pre)` 并丢弃 overlay/effects。因此 matched `.reverted`
后仍有 trailing response，以及程序自行 revert/trap 时仍有 unconsumed response，都唯一得到
`invalidExternalResponse`，不存在“立即 revert”与“extra response trap”两种实现。v1 external call 无
return value，因此 response 没有 value 字段；增加 typed return 必须升级 semantic/reference schema，
而不能塞入 context。

执行顺序严格从左到右。所有 state write 写入 transaction overlay；`returned` 原子提交，
`reverted/trapped` 丢弃 overlay 并返回 pre-state。event/call/schedule 按实际执行顺序进入 ordered
effect buffer，每项携带其 occurrence pair，仅在 returned 时成为 committed effects。同步 external
call 从 `responses` 按该 pair 消费；pair 缺失、重复、额外、顺序或类型错误按上述 cursor/terminal
precedence trap；schedule 只产生
workflow intent。bounded loop 因而不会重复使用同一 response/effect identity。

`assert false else E` 与 `revert E` 产生 `.declared`；无 error 的 assert 使用
`.standard(.assertionFailed)`。checked arithmetic/cast/index/bound 按上表唯一 standard code；无效
invocation/response/Core 与 resource overrun 分别映射同名 `SemanticFaultV1`；
`Term.Trap(.unreachable/.invalidExternalResponse/.resourceExhausted/.internalInvariant)` 逐项映射为
`.unreachable/.invalidExternalResponse/.resourceExhausted/.internalInvariant`，不存在 generic string 或
第二层 trap payload。
`OutcomeV1.returned.value` 对 Unit result 必须为 `none`，其他 result 必须为 exact typed `some`；effect
payload args 也必须是 canonical `ReferenceValueV1`。Target 可使用不同低层错误形式，但 normalized
adapter 必须保留 exact OutcomeV1 status/reason/state/value/effect sequence。

这些 carriers 是 in-memory executable model，不是持久化 artifact schema；equality 是所有 constructor/
field 的 structural equality。当前 `proof-forge.evidence.v1 observations` 只是 verdict/diagnostic projection，
不是 OutcomeV1 wire，不能持久化证明该 structural equality。若 evidence/output 需要该证明，必须先另立
versioned exact tagged outcome artifact 并由 EV retained artifact digest 绑定；在它实现前，target adapter
structural differential 只能作为进程内/model development assertion，不能形成 formal evidence。不得用
target JSON、pretty text、`errorClass` 或自由字符串充当 OutcomeV1。

## 初始化与调用

以下 helper 只对已通过 `validateSemanticProgramV1` 的 carrier 成功；invalid program/type 返回
`SemanticWireErrorV1`，不能猜 default：

```lean
def defaultValueV1
    (p : SemanticProgramV1) (typeId : TypeIdV1) : Except SemanticWireErrorV1 ByteArray
def initialLogicalStateV1
    (p : SemanticProgramV1) : Except SemanticWireErrorV1 LogicalStateV1
```

`defaultValueV1` 按 semantic type total 构造唯一 canonical value：Bool=false；UInt/Int/Field=0；
Principal 的 opaque payload=单 byte `00`（canonical value 仍含 u32 length）；Unit=empty；Bytes=全零；
Array=element default 重复固定长度；Map=empty；Option=none；
Struct=field defaults；Enum=variant 0 加其 payload defaults。Struct/Enum 必须 nonempty，且 type cycle
必须穿过 Option，因此该算法终止。`initialLogicalStateV1` 按 state order 编码这些 defaults；存在
initializer 时 `initialized=false`，否则为 true。

未初始化 state 只能是 byte-for-byte `initialLogicalStateV1 p`，且只能调用唯一 initializer；其他
false-state、entry/view on false state 为 `.standard(.uninitialized)`。initializer 只能从该 state 开始，
成功原子提交 overlay 并置 `initialized=true`；再次 init 为 `.standard(.alreadyInitialized)`。没有
initializer 的 program 从 initialized default state 开始。view 在独立只读 snapshot 上执行，任何 Core
write 是 semantic validation error。entry/view/init 都按 callableId 与参数 exact match，没有 name/
target fallback。

`step` 首先 validate program；失败返回 `.trapped(.invalidCore, pre)`。非 initializer 调用要求
`StateConformsV1 p pre`；initializer 要求 pre exact 等于 successful `initialLogicalStateV1 p` 的 false
state。其他 malformed/noncanonical pre-state 是 `.trapped(.invalidInvocation, pre)`，不得补 default 或
部分 decode。

## Canonical Serialization

格式精确采用 `SPEC-SEM-WIRE-001` 的 closed length-prefixed binary `pf.semantic.v1`：固定
little-endian integers、NFC UTF-8、array 保留语义顺序、set/map 按 canonical key bytes 排序；禁止
float、host pointer、时间、absolute path。`semanticHash = SHA-256(serializedBytes)`。v1 没有 optional
extension field；unknown field/tag/version 必须拒绝。

## Normalization

source AST 先完成 type/effect，再消除语法糖、显式插入 checked operations、统一 match/
loop CFG、分别计算 business requirement 与 requirement/source provenance，最后 validate 两个 closed
carrier。Normalization 必须 total on TypedProgram；
内部失败为 `PF-SEMANTIC-INTERNAL` 并视为 compiler bug，不得生成部分 Core。

## Invariant proof ABI

proof validation 的输入只能是已经通过 normalize、全部 Core invariants validation 与 canonical
serialization 的同一个 closed `program : SemanticProgramV1`；bundle 不得提供、替换或重新
normalization 另一份 program。ABI 的唯一 owning module 是
public façade/namespace `ProofForgeV2.Semantic.InvariantABI`；其state carrier/codec/StateConforms
foundation可按SPEC-SEM-WIRE-001规定由lower `InvariantFoundationV1`在同一exact namespace下定义，
formal `evalInvariantV1`和`InvariantTheoremV1`仍必须直接由public `InvariantABI` façade定义。
`InvariantOrdinalV1`、`InvariantEvalResultV1`、`StateConformsV1`、`evalInvariantV1` 和
`InvariantTheoremV1` 的 exact declarations/proposition 只由SPEC-SEM-WIRE-001 第 7–9 节定义。
本文件只说明它们在通用 reference semantics 中的含义，不建立第二份field/proposition authority；
ABI `.olean` identity的trusted closure必须exact包含全部transitive dependencies（当前lower
foundation，formal evaluator引入后还包括reference machine）。

`StateConformsV1 program state` 精确表示 `state.initialized=true`，且 state 对 program logical
state schema 的每个 path 恰有一个 exact-typed canonical value、没有额外 path；Bytes/Array length、
enum tag/payload、struct field 和 Map key/value 均满足 SPEC-TYPE-001 与 canonical key 规则。
`evalInvariantV1` 只按 ordinal 选择 `program.invariants` 中的 predicate，使用本文件 reference
interpreter 的 pure expression/CFG 规则读取该 state 并调用 program 内 canonical pure-fn CFG；它的
external responses 与 ordered effect buffer 恒为空。Bool true/false 分别映射
`returnedTrue/returnedFalse`，任何 checked failure 映射 `reverted`，invalid Core/resource fault 映射
`trapped`；ordinal 越界也为 `trapped`。因此 revert/trap 不能证明 invariant。

对 `proof x using N`，compiler 在上述 canonical program 中按 exact NFC name 找到唯一 invariant
ordinal `i`，构造 closed expected type
`ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1 program i`。该命题 **精确** 表示：

```text
ordinal 合法 ∧ ∀ state, StateConformsV1 program state →
  evalInvariantV1 program ordinal state = .returnedTrue
```

**不** 蕴含 state 可达性、init/`step` 后自动保持、target refinement 或 formal reference corpus
闭合。type 检查（inline Environment defeq 或 historical bundle export）只在展开 ABI / 显式
reducible closed program abbreviation 后做 definitional equality；不得用 semantic hash equality、
propositional cast、未解 metavariable 或任意 term elaboration 替代。成功只增加 certification
result；program、requirements、semantic serialization 和 target selection 保持不变。

## Inline same-file certification（ADR-0026 engineering）

工程产品路径以 **同一 in-memory source snapshot** 上的 adjacent ordinary Lean theorem 为
主 certification 面：

1. 在 Check/Normalize/`CompiledSemanticV1` 之后、requirement resolve / materialize **之前** 运行；
2. in-process elaboration **不是** sandbox / contained worker / hermetic runner；
3. Environment 审计 declaration kind（root theorem）、kernel defeq、dependency 闭包与固定
   allowed base axioms `Classical.choice` / `Quot.sound` / `propext`；
4. **不信任** 用户 `.olean`；不得 ambient lake/`LEAN_PATH` fallback；
5. theorem body 永不写入 semantic bytes/hash；subject program literal 若生成，其 bytes 必须
   exact 等于当前 compiled `SemanticProgramV1.canonicalBytes`。

空 proof 表面为显式 skip；失败 fail closed，不得进入 target Plan。

## ProofBundleV1（historical / alternate / formal-oriented）

外部 digest-pinned proof bundle 是 source-specific、只读、content-addressed **alternate**
input，不得与 ADR-0026 inline path 静默互替。directory
layout 唯一为 `proof-bundle.json` 与 `modules/<QualifiedName components>.olean`；component 逐级作为
文件名，最后一段追加 `.olean`。禁止 source、`.ilean`、native library、plugin、bytecode、临时文件
或其他额外 entry。manifest 的逻辑 schema 为：

```lean
structure ProofAbiIdentityV1 where
  semanticSchema           : SchemaId
  moduleName               : QualifiedName
  theoremName              : QualifiedName
  abiOleanDigest           : Digest
  trustPolicyDigest        : Digest
  trustedBaseClosureDigest : Digest

structure ProofModuleV1 where
  moduleName  : QualifiedName
  oleanPath   : ProjectRelativePath
  oleanDigest : Digest
  imports     : Array QualifiedName

structure ProofExportV1 where
  invariantName    : String
  invariantOrdinal : UInt32
  theoremName      : QualifiedName
  ownerModule      : QualifiedName

structure ProofBundleManifestV1 where
  schema                   : SchemaId
  sourceHash               : Digest
  semanticHash             : Digest
  semanticProvenanceDigest : Digest
  toolchainLockDigest      : Digest
  proofAbi                 : ProofAbiIdentityV1
  roots                    : NonEmptyArray QualifiedName
  modules                  : NonEmptyArray ProofModuleV1
  exports                  : NonEmptyArray ProofExportV1
```

wire object 只允许 `schema,sourceHash,semanticHash,semanticProvenanceDigest,toolchainLockDigest,proofAbi,roots,modules,exports`；nested
objects 只允许上面同名 lower-camel-case fields。`schema` 精确为
`proof-forge.proof-bundle.v1`，`proofAbi.semanticSchema` 精确为
`proof-forge.semantic-program.v1`；该 schema 的 binary domain/magic 仍由
SPEC-SEM-WIRE-001 固定为 `pf.semantic.v1`。module/theorem
分别精确为 `ProofForgeV2.Semantic.InvariantABI` 与
`ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1`。modules 按 module name NFC UTF-8 bytes
排序；roots 同序；exports 按 `(invariantName,theoremName)` 排序。所有 name/path/export/import
必须唯一，imports 保留 `.olean` direct-import 顺序，owner/root/module 引用必须存在。manifest
内所有 bundle-local import edge（包括 roots 不可达的 module）必须组成 DAG；self cycle 与任意
多 module cycle 都拒绝。未出现在 manifest modules 的 import 在本阶段只形成 unresolved import
frontier，不得据此认定它属于 trusted base；后续必须与独立验证的 trusted-base inventory exact
join。manifest 不得自含 digest：

```text
proofBundleDigest = SHA-256(
  "proof-forge.proof-bundle.v1" || 0x00 || JCS(ProofBundleManifestV1)
)
```

manifest 的每个 `oleanDigest` 是对应 regular file bytes 的 SHA-256。`toolchainLockDigest` 必须精确
等于 SPEC-TOOL-001 从当前平台已验证完整 Tool Lock v4 payload 产生的唯一 `ToolLockV4Digest`；raw
`toolchainLockSha256`、legacy `proof-forge.toolchain-lock.v1` domain 或其他同长摘要替代都以
`PF-TOOLCHAIN-MISMATCH` 拒绝，不得 dual-read。`abiOleanDigest` 必须等于当前 candidate 自带 ABI `.olean`。
该 Tool Lock join 只固定当前平台工具链身份，不提供 per-module `.olean` inventory、ABI digest
或 trusted-base closure authority；后三者仍须由独立 candidate package manifest 建立。
trusted base 只包括该 candidate 的 ABI/Semantic Core closure 与 lock 中 Lean kernel/core `.olean`
closure，按 module name 排序并以
`SHA-256("proof-forge.trusted-olean-closure.v1" || 0x00 || JCS([{moduleName,oleanDigest,imports}...]))`
得到 `trustedBaseClosureDigest`。bundle module 的每个 transitive import 必须 exact resolve 到 manifest
modules 或该 base closure；禁止 ambient project `.lake`、父仓库、HOME、`LEAN_PATH` 或通用 search
path fallback。

trust policy 的 canonical JCS payload 固定为：schema
`proof-forge.proof-trust-policy.v1`、`allowedBaseAxioms=["Classical.choice","Quot.sound","propext"]`，
以及 `allowBundleAxioms/allowUnsafe/allowPartial/allowExtern/allowImplementedBy/allowInitializers/`
`allowEnvironmentExtensions/allowSyntaxOrElaborators/allowNativeArtifacts/`
`allowArbitraryTermElaboration` 全部为 `false`。其 identity 为
`SHA-256("proof-forge.proof-trust-policy.v1" || 0x00 || JCS(payload))`。base 中其他 axiom（尤其
`sorryAx`）不得位于 exported theorem 的 constant dependency closure；bundle 自己的任一 forbidden
declaration 即使不可达也拒绝。export 必须是有 value 的 theorem 或 opaque definition，type 为
`Prop`，且其 complete constant dependency graph 通过上述 policy。

`sourceHash` 必须等于当前 selected Source.ProgramV1 的 exact hash；`semanticHash` 必须等于随后
canonical SemanticProgramV1 的 exact hash；`semanticProvenanceDigest` 必须等于同一次 normalization
产生且已按 `SPEC-SEM-WIRE-001` 对当前 Source.Program 完整验证的 companion digest。三者分别阻止
source、业务语义和 source-to-semantic origin binding substitution；它们都进入 bundle digest，但只有
closed program value/ordinal 进入 theorem proposition。

bundle theorem 可以引用 bundle-local、显式 reducible 的 canonical `SemanticProgramV1` value
abbreviation；该 abbreviation 必须是 closed value，不能读取文件、环境或 source module。loader
通过 manifest semanticHash 与最终 expected-type definitional equality 同时验证它，不能相信其自报
hash。v1 compiler 只消费预构建 bundle，不在 check/build 过程中编译用户 Lean source 或生成
`.olean`。

## Proof bundle safe loading

proof loader 属于 compiler-core stage，不属于 frontend。它在 fresh contained worker 中以空 HOME、
空 `LEAN_PATH`、deny network/write/exec、closed inherited FD、`/dev/null` stdin 和
`enableInitializersExecution=false` 运行；只使用锁定 Lean importer 和 manifest 构造的 exact
read-only module map。先 dirfd-relative/no-follow 打开 bundle root 和 manifest，再逐个 stable-read
regular single-link file，拒绝 symlink、hardlink、special file、case-fold collision、inode/size
变化和 manifest 外 entry。上限固定为 1024 modules、单文件 64 MiB、全部文件 256 MiB，并同时受
effective compiler-core ResourceProfileV1 更小上限约束。

loader 先核对 CLI pin、manifest/schema/sourceHash/semanticHash/semanticProvenanceDigest/toolchain/base/ABI/policy 与全部 file digest，再按 closure
拓扑加载；实际 `.olean` direct imports 必须与 manifest array 逐项相同。它不运行 initializer、
macro/elaborator、environment extension、bytecode 或 native code，不 elaboration 任何 source/term；
只进行 Lean importer/kernel validation、declaration-policy/dependency inspection、exact export lookup
和 expected-type definitional equality。worker 只返回 bounded validation record，不把 Environment
或 declaration value 缓存到 parent。malformed/truncated `.olean`、unknown import/export、closure
不完整、digest/ABI/toolchain/policy/sourceHash/semanticHash/provenance mismatch、forbidden declaration、kernel/typecheck
failure、timeout/signal/resource overrun 均 fail closed，且不得产生 target Plan、OutputSet、partial
certification 或 ambient fallback。

## 不变量

- 所有 ID 唯一且引用存在；CFG 有入口、终结块、无不可达 side effects。
- 类型 exact；phi/block 参数 arity/type exact。
- state path 类型正确；view 无 write/effect；static effect ID 按 canonical instruction order 唯一，
  dynamic occurrence 计数不超过 UInt32。
- loop/call graph bound 已证明；private flow 已验证。
- requirement 集与实际 operations 双向一致：每个 op 有 requirement；validated companion provenance
  对每个 requirement index 恰有一个 nonempty origin binding。由 program-level invariant 推导的
  synthetic requirement 必须绑定 canonical Program root `SourceOrigin`，不存在空 origin 例外。

## 错误与边界

`PF-SEMANTIC-INVALID` 外部/反序列化 Core 违反不变量；`PF-SEMANTIC-INTERNAL` 编译器
生成无效 Core；`PF-SEMANTICS-MISMATCH` target normalized observation 不等价。覆盖 zero
state/callable、最大 CFG、unreachable blocks、duplicate IDs、bad phi、effect reorder、
missing response、extra response、nested revert、event-before-revert、call failure、init twice、
matched reverted 后 trailing extra、程序自行 revert/trap 后 unconsumed response、
view snapshot、Map absent、integer extrema、serializer order/path independence、unknown schema；以及
semantic provenance wrong source/semantic hash、missing/duplicate entity binding、origin substitution；以及
proof bundle manifest/file/closure mutation、stale semanticHash、wrong ordinal/program、ambient module
poisoning、forbidden declaration/axiom、signature mismatch、loader timeout/signal/resource overrun。

## 验收

关联 `FR-004/005`、`TST-SEM-001..003`、`TST-TYPE-003`、`TST-PROOF-001`、
`TST-CLI-002`、`TST-SEC-001`。Counter、Map、event、external failure 和
bounded loop model tests 必须可执行；semantic/provenance serializer golden + roundtrip + property tests；四目标
normalized Counter trace 与 reference 完全一致。proof positive 必须使用 exact closed program
theorem；每个 bundle/schema/closure/trust/safe-loading rejection 都必须稳定 fail closed 且零 target/output。
