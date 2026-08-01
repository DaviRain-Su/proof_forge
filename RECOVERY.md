# ProofForge V2 Product Recovery

ProofForge V2 已完成第一个恢复纵切面，现在按
[`MIGRATION_MATRIX.md`](MIGRATION_MATRIX.md) 迁移 D1–D4：

```text
ValidatedSourceV1
  → complete Typed checker
  → SemanticProgramV1 + SemanticProvenanceV1
  → ProgramRequirementsV1 + exact resolver
  → target-owned Plan / TargetIR
  → OutputSetV1
```

当前可运行的 Counter/Accumulator 路径已由单一 `CompiledSemanticV1` 保留 structure-valid `SemanticProgramV1`，并直接构造四个 target Plan；产品编译、resolver 与 artifact identity 已不再持有 alpha carrier，但下游仍使用 transitional D3 output。它是迁移中的工程纵切面，不是上述目标链已经完成。

## 为什么重基线

历史 D1 工作把 TaskQualification、custody、formal evidence、eligible-host ceremony
放进了每个开发任务的关闭路径。结果是源码技术面已经通过，产品仍因单维护者无法完成的
多主体发布仪式而停住。恢复模式把两类结论重新分开：

- **development completion**：产品路径、类型/语义、目标制品和普通测试通过；
- **release qualification**：SBOM、主机资格、clean-room、签名/custody 和正式证据通过。

后者不能伪造，也不再阻塞前者。

## 当前范围

1. 保持普通主机可运行的 `docs-check`、`test-fast`、`dev-check` 与 `ci`，继续隔离
   `governance-check`/`release-check`。
2. 以 27 行矩阵区分 formal task状态、实际代码地基、产品接线和缺口，不使用虚假百分比。
3. 按 D1 → D2 → D3 → D4（EVM-first）把 alpha carrier/protocol迁到新设计；shared core切换时直接迁移
   EVM/Solana/NEAR/Noir consumers，D3 contract 冻结后的 target completion 先闭合 EVM。
4. 每层替代实现成为唯一产品路径并通过门禁后，删除对应旧代码、旧schema和旧tests；不保留fallback。
5. qualification代码继续按 [`QUALIFICATION_INVENTORY.md`](QUALIFICATION_INVENTORY.md) 隔离，
   不混入产品迁移。

## 工程迁移完成口径

当前仍**不是**新架构迁移完成态。只有以下条件全部满足，才能把 engineering migration 写成完成：

1. CLI source path 只走 supervised safe-open → worker，产品 `IO.FS.readFile`、双 open 与 fallback 归零。
2. shipped ProgramV1 产品表面都经 CheckV1 → NormalizeV1 生成 structure-valid `SemanticProgramV1`，不再仅是 Counter-like S1。
3. `CompiledSemanticV1` 是唯一产品编译成功 carrier；alpha Typed/Semantic lowering与 residual accessors 无产品调用。
4. `ProgramRequirementsV1` 是唯一产品 requirement authority；target-neutral contribution engine 只向该 authority供给，不存在第二套 AST walker、alpha parity或 caller override。
5. EVM/Solana/NEAR/Noir 四个 Plan body 均直接消费 retained `SemanticProgramV1`（经 resolved capability）。
6. 产品可达 registry digest、SupportClaim/decision、BuildIdentity、Plan/IR identity 与 `OutputSetV1` 已接线，v2alpha1 transitional sidecars 退役。
7. legacy `Core/Source`、alpha Typed/Semantic 与旧 compiler入口的产品 consumer 归零；测试先迁后删。
8. 聚焦/deletion/reflection gates、`just dev-check`、普通 `just ci`、docs/SBOM 全绿。

formal TASK/TST/EV/qualification 是独立轴，不由上述 engineering completion 代签；也不得用 formal pending 否定已经成为唯一产品 authority 的工程切片。

## 产品迁移 Wave DAG

```text
Wave 1  D1 supervised frontend + CLI cutover
  → Wave 2  [done] freeze current S1 Semantic contract
           → [done] EVM SemanticProgramV1-native Plan migration pilot (migration only, not D4 completion)
           → [done] freeze seam + Solana/NEAR/Noir non-overlapping target leaf migrations
           → [done] requirements single authority + alpha dual-carrier/product-consumer deletion
           → [current] expand the sole SemanticProgramV1 producer beyond S1
  → Wave 3  SupportClaim + BuildIdentity + Materializer identity + OutputSetV1 + supervisors
  → Wave 4  D4 EVM first → D5 Solana + D6 NEAR + D7 Noir target completion
  → Wave 5  D8 aggregate/security/repro/clean-room/review
```

**Wave 1 / D1 frontend engineering cutover 已闭合**：B11b2 把 pinned B11a safe-open helper 与 B10 frontend worker 纳入同一 absolute monotonic wall，B12 令 CLI `build`/`build-counter` sole consume success-only reconstructed product carrier，并删除 Main 内 `realPath`/`readFile`/Loader/reconstruct/embedded Counter fallback；native worker spawn也已切到 no-follow fd-derived bounded private snapshot（suspended spawn + vnode recheck），不再执行 caller pathname；D1-04 shared IntegerLiteral slice 同样已接线。formal executable/import identity、TASK-D1-08、controller-backed containment与完整 host/race matrix仍独立 pending。当前 wave 仍为 **Wave 2 / D2**：S1 Semantic contract、EVM迁移先导和 Solana/NEAR/Noir target leaf均已接线，四 target Plan body已切断 alpha residual；requirements contribution engine → `ProgramRequirementsV1` sole freeze、`CompiledSemanticV1` 单 carrier、Digest identity以及 compiler/resolver/materialize/finalize/CLI 的 alpha产品consumer删除已接线。sole Normalize 的首个扩面已加入 public UInt64 checked-sub，并同步贯穿四个 target-owned Plan/IR/emitter；完整 Normalize 表面仍远未闭合，下一步继续在同一 producer扩面。该 cutover只属于迁移，不冒充 D4–D7里程碑完成。

并发规则：`main` 是唯一集成权威。允许从 exact clean `main` 创建临时隔离 worktree 推进接口已冻结、文件 allowlist 完全不重叠的 leaf lanes；worker 不编辑 `AGENTS.md`、`RECOVERY.md`、`MIGRATION_MATRIX.md`、实现日志、umbrella、suite注册、`lakefile.lean`、justfile或SBOM pin。主代理只读审查并串行集成，聚合门禁通过后立即删除临时 worktree/branch。shared-core cutover、文档、package pin与提交始终串行。

## 当前结果

- `docs-check`/`dev-check`/`ci` 已不再运行 Stage-0 或 TaskQualification；历史审计由
  `governance-check` 显式运行，release host preflight 在当前主机准确返回 `PF-HOST-INELIGIBLE`。
- CLI `build`/`build-counter` 产品 source 路径只调用 pinned sibling safe-open helper → B10 worker →
  `SupervisedFrontendV1.productInput` → `compileProgramProductV1`；success pair 仅在 request-bound composer
  内 reconstruct 一次，canonical SafeOpen Err 只保留 closed fault（`.tooLarge` 精确恢复 16 MiB
  `PF-SRC-INVALID`，无 reopen/stat），source open/resource/protocol事件映射 closed
  `DiagnosticBundleV1`，失败按 `selectExitCode` 退出；成功后 mint private-ctor
  `CompiledSemanticV1`（retained semantic + artifact name + canonical source/semantic Digest），再经
  engineering exact requirement capability进入 target Plan/IR/finalization；EVM/Solana/NEAR/Noir 四个
  Plan body均在 capability 后直接消费 retained `SemanticProgramV1`，target module 内 alpha Plan route归零；
  resolver与artifact identity同样只读该单 carrier，全链不构造 legacy `Source.Program`。
- ProgramV1 expression 与 pattern integer literal 现共用 sole decoder：只接受 unsigned decimal 或 lowercase-prefix `0x` hexadecimal（hex digits 可大小写），拒绝 `0X`/binary/octal/underscore，范围精确为 `0..2^256-1`；等值 spelling 产生相同 AST、canonical bytes 与 sourceHash。该 bounded D1-04 工程切片不改变 formal 状态。
- B10 已新增一请求一进程的 `proof-forge-frontend-worker-v1`：stdin/stdout 只承载
  `Frontend.Req/Ok/Err.v1`，与产品 Loader 共享单 parser snapshot，并由真实子进程测试固定
  deterministic bytes 与 64/65/70 abnormal exits。B11a 已新增 package-owned native safe-open
  foundation（component no-follow、regular/single-link、16 MiB pre-read gate、read probe、fd/path
  metadata recheck 与 closed redacted faults）；B11a2 已新增 pure canonical/public-safe、host-tagged
  development-observation receipt model。B11b1 已以独立 process group 监督**已编码**
  canonical request：monotonic budget 从 native allocation/pipe/spawn 前开始，使用 selective
  `LEAN_SYSROOT`/`LEAN_PATH` + fixed env，轮询 aggregate process/memory、stdout/stderr 与 deadline，
  bounded kill/cleanup 后实际 mint B11a2 receipt；malformed/cross-request/incomplete-cleanup response
  fail closed。B11b2 另以 closed `SafeOpen.Req/Ok/Err.v1` one-request helper（不 import Loader）把
  `safeOpenSourceV1` 放入同一 hardened `posix_spawn` 监督面；private native `CLOCK_MONOTONIC` capability
  在 open request 前 sole mint，两个 child stage 消费 exact absolute start，wall 覆盖 open、parent request
  construction 与 B10 worker，并在每次 snapshot/allocation/pipe/spawn 前检查耗尽。SafeOpen Ok/Err 绑定
  canonical request digest，最终 observations 合并两阶段 peak；仅 request-bound canonical fault + complete
  cleanup mint `sourceOpenFailed`，并仅在 private supervised carrier保留 exact closed fault。B12 已令 CLI
  sole consume该完整 supervisor并以 durable deletion gate固定无 source reopen/Loader/fallback/direct
  pathname spawn。Darwin 保留 suspended spawn/vnode 复核；Linux development path 使用 root-owned
  sticky `/tmp` 下128-bit私有 snapshot、fork 后 `close_range` 清除 ambient fd、独立 process group、
  `/proc` group/RSS fail-closed sampling，并实际跑通 safe-open→frontend→CLI product positive。Linux
  receipt使用 `linux-development-observed` 与 `linuxProcRssAggregate`，不冒充 Darwin footprint、cgroup
  或 containment。formal executable/import identity、`setsid` escape、controller-backed containment
  与 formal TASK-D1-08 仍缺失。
- Counter 已从真实 source 完成 ProgramV1 到目标制品的 CLI smoke；快速测试固定
  ProgramV1 identity/sourceHash/NodeId、Typed/Semantic、EVM Plan/IR 与 deterministic Yul/ABI。
- 真实 Counter/Accumulator source 已经由当前恢复桥使用 digest-pinned `solc 0.8.34` 生成
  EVM bytecode；product runtime 只要求所选工具的 executable/runtime exact closure，无关 `jv`
  缺失不再阻塞 EVM，而 release checker 继续要求完整 global bundle。四 target Plan body现均由 retained
  `SemanticProgramV1` S1 carrier构造；EVM继续复用既有 IR/Yul/solc。工程链已删除 dual-carrier与 alpha-backed
  artifact identity，但仍保留 private v2alpha1 publisher，不代表正式 D1–D4 contract、formal `OutputSetV1`
  或 task completion；本切片也未新增 Anvil runtime 结论。
- Legacy Source source-reading 与 v1 export decoder 已删除；Lean command/export 与
  Loader 只读 ProgramV1。产品 CLI 入口是 B12 supervisor product carrier + located compile；
  `selectProgramV1Product`/`selectProgramV1*`/`compileValidatedSourceV1` helpers 仅保留给 worker共享实现、测试或嵌入方。B10 worker 的
  spans payload API 与产品 OriginJoin API 共享同一私有 parse/select/SpanJoin snapshot；
  产品编译只返回 `CompiledSemanticV1`，resolver、四 target Plan body与 artifact identity均只读 retained
  `SemanticProgramV1`及其 canonical Digests。隔离的 `AlphaCompatibility` 仅供 legacy hand-built测试；
  产品 umbrella/compiler/capability/materializer/CLI 的递归 import closure禁止 legacy Source/Typed/
  SemanticIR/Semantics与 AlphaCompatibility。无 adapter、dual reader、
  第二套 ProgramV1 decoder 或 fallback。
- [`MIGRATION_MATRIX.md`](MIGRATION_MATRIX.md) 已逐项记录 D1–D4 的 requirement、实现文件、
  产品接线、测试事实、缺口和删除门槛；formal仍为0/27 done。
- [`QUALIFICATION_INVENTORY.md`](QUALIFICATION_INVENTORY.md) 已确认 qualification 子系统为
  84 个文件、58,429 行；ordinary product gate 无直接依赖，本轮未移动或删除任何文件。

## 明确暂停

- 新 `TASK-*`、`D1-PA-*`、`EV-*`、freeze package 或资格对象；
- TaskQualification service/supervisor、durable custody 与 formal-evidence 协议扩张；
- D1–D4 accepted/proposed设计范围之外的新 target、DSL constructor或协议扩张；
- 产品路径中的 legacy→ProgramV1 adapter、dual reader、第二套 ProgramV1 decoder 与任何 fallback；
- 为了让历史表格显得“完成”而回填或降级证据。

## 命令边界

```bash
just dev-check          # 日常：docs + build + 核心产品测试
just ci                 # 普通主机：完整产品测试与负例
just governance-check   # 显式审计历史 task/freeze/evidence
just release-check      # 发布预检；非 eligible 主机应明确拒绝
```

`just ci` 成功只说明产品开发门禁通过，不等于 formal/hermetic evidence。
`just release-check` 失败也必须区分“主机/ceremony 不合格”和“产品代码失败”。

## 完成条件

每一层只有在新实现成为唯一产品入口、旧consumer引用归零、已有测试迁到新carrier、
`just dev-check`/`just ci`和该层聚焦门禁通过后，才进入紧随其后的删除提交。最终目标是
CLI真实走完 `SemanticProgramV1 → exact resolver → target Plan/IR → OutputSetV1`，并让EVM在
该唯一路径上完成locked solc与Anvil differential。当前工程权威为
private-ctor `CompiledSemanticV1` 单 carrier + engineering exact requirement resolver capability
（`resolveEngineeringRequirementsV1 (selection, compiled)` → private
`ResolvedEngineeringBuildV1`，exact retained SemanticProgramV1 `data.requirements`，
无 caller request override；静态四行 S2 support index）。**精确边界**：shipped
aggregate/CLI `materialize`/`emit` 仅接受 capability；EVM/Solana/NEAR/Noir 均在 capability 后读取
retained `SemanticProgramV1`，经各自 private S1 lowering构造 target-owned Plan，再进入各自 IR/emission；
residual alpha不再参与 Plan body。**D3/S6 工程**：public residual Common resolve / validateResolved /
public makePlan 与 `TargetDescriptor.supportedRequirements` 字段/membership acceptance 已关闭；
cycle-free `EngineeringBuildV1` leaf sole mint；四 target 仅 capability-gated
`planFromCapability`/`irFromCapability`/`buildFromCapability`（+ descriptor/
validatePlan/validateIR inspection）；Registry 直接 capability dispatch；public
`namespace Residual` 与 `planFromAlpha`/`lowerPlan`/`filesFromIR` 完整
Semantic→Plan→IR→files bypass 已删除；dead public `ResolvedProgram` 已删除；
private target lower 仅 capability 内部；`s6-plan-cutover-deletion-gate` + Lean
residual type-chain reflection（defn/opaque/ctor）已接入 dev/ci。**D3/S7a 工程**：
aggregate `materializeResult` 返回 private-ctor `MaterializedArtifactsV1`（sole mint
`mintMaterializedArtifactsV1`；exact target/profile/kind + semantic-derived artifact name + canonical
ProgramV1 source Digest + `semanticHashV1` Digest + ordered files）；已删 public
`OutputSet`/`OutputManifest`/`makeOutput`/`manifestJson`；CLI private legacy-engineering
v2alpha1 renderer 保持 on-disk manifest/evidence 字节兼容；
`s7-output-envelope-deletion-gate` 已接入 dev/ci。**D3/S7b 工程**：locked-tool
finalization 已迁出 CLI：`Materialization/LockedToolchainV1`（无 Core.Source/CLI）；
private-ctor `FinalizedArtifactsV1` sole mint；Registry sole
`finalizeMaterializedArtifactsV1` → Evm/Near/Solana/Noir FinalizeV1 adapters；
CLI/Emit publisher-only；已删 `CLI/Toolchain` 与 `finalizeEvm`/`finalizeNear`；
exact on-disk v2alpha1/tool bytes 保持；`s7b-finalize-authority-deletion-gate` 已接入
dev/ci。**D3/S7c 工程**：sole `validateEngineeringDiskClosureV1`（private
`FinalizedArtifactsV1` + staging；derived base+extras+`evidence.json`/`manifest.json`；
no-follow bounded walk；limits 1024/64MiB/256MiB）；CLI publisher evidence→manifest-last
后 exact closure、destination race recheck/rename 前；`validate_artifacts.py`
统一 no-follow exact closure + self-test；`s7c-disk-closure-gate` 已接入 dev/ci。
仍**不是** SupportClaim/formal resolver/BuildIdentity/`OutputSetV1`/
ToolchainIdentity/formal exact closure/hermetic publisher/完整 SemanticProgramV1 lowering
完成态。formal task状态与 release qualification仍按各自真实条件变化，不由本恢复文档代签。

## D2-07 invariant reference evaluator status（2026-07-31）

远端general CFG walker lineage中的Reference machine继续作为唯一工程执行权威；其PureCall frame、
if/match、emit/revert、mul/div/mod/unary与let/for能力均保留。本地增量只新增明确非formal的
`evalInvariantReferenceSliceV1`：按InvariantDecl ordinal执行zero-arg public Bool invariant，先以
`StateConformsV1`拒绝uninitialized/malformed state，再以carried exact`invariantSteps`作为machine
fuel上限，映射true/false/revert/trap且不发布state/effects。正式`evalInvariantV1`与
`InvariantTheoremV1`仍由`InvariantABI`唯一拥有且尚未实现，formal TASK-D2-07/TST-SEM-002/003
仍pending。

模块依赖已为formal evaluator机械拆分且不改变public FQName：`InvariantFoundationV1`定义
`InvariantABI` namespace下的state carrier/codec/StateConforms，`ReferenceMachineV1`只依赖该
foundation并定义`ReferenceV1` namespace下的现有carriers/admission/machine；`InvariantABI.lean`与
`ReferenceV1.lean`保留public façade。lower machine不得重新import upper `InvariantABI`，否则会阻断
下一切片所需的`InvariantABI → ReferenceMachineV1`无环依赖。

`ReferenceMachineV1.runInvariantCallableV1`现提供formal-compatible lower seam：输入已structure-validated
`SemanticProgramDataV1`、selected callableId与state，使用callable携带的exact `invariantSteps`执行，
不依赖/扫描`AdmittedReferenceSliceV1`。既有`evalInvariantReferenceSliceV1`在完成engineering admission、
StateConforms与ordinal join后委托给该seam。整数运行时完成后，测试改以无关Field declaration固定
general admission限制不会污染selected UInt/Int invariant；这不表示Field runtime或formal
`evalInvariantV1`已完成。

后续non-numeric hardening切片已实现Unit唯一合法constructor（index 0、empty args、canonical empty
bytes），并在storeResult、primitive operands、Assert/Branch/Switch、jump block params、PureCall
arity/type/canonical bind与callee/root return处防御性重验。Principal不开放general engineering
admission，但selected invariant可经lower runner执行canonical Eq/Ne；Int/Field运算和完整CheckedCast
矩阵原为下一前置阶段；后续切片已闭合全部六种UInt/Int宽度与四类CheckedCast，Field仍是下一阶段。

fixed-width integer切片使用Lean arbitrary-precision Nat/Int计算后执行目标宽度检查和canonical
little-endian two's-complement编码。UInt/Int算术、signed div/rem、order、bitwise、checked left shift、
zero-fill/sign-extending right shift及跨signedness cast均由同一machine执行；`minInt / -1`、negation、
zero divisor、bad shift和out-of-range cast保留exact standard revert类别。whole-program engineering
admission现接纳所有Wire合法整数宽度，Field与Principal仍关闭。正式ABI仍不得调用engineering
admission；后续Field切片已接纳sole BN254 Field，Principal仍关闭。

Field runtime仅接受Wire catalog固定的`proof-forge.field.bn254-fr.v1`与exact modulus。add/sub/mul/neg
全部modulo p；nonzero division通过固定256轮binary exponentiation计算唯一inverse，zero精确走
`divisionByZero`。Field mod/order/bit/shift仍由Wire拒绝，runtime保留invalidCore防御。Field admission
按32-byte leaf计资源；selected lower runner以无关Principal声明固定不扫描whole-program engineering
admission。下一步应先做formal-compatible closure/defensive gap复核，再定义public evaluator。

该复核已闭合两个blocker。`WireV1.validateCallableCfgShape`现要求`blocks.size > 0`，因此声明
`entryBlock=0`却没有block 0的callable在CFG phase以`.badCfg`失败。`runInvariantCallableV1`现从carried
fuel先扣root frame-entry，PureCall instruction扣除后再单独扣callee frame-entry；root/callee仍共享
同一Nat fuel，不引入per-frame额度。测试以Wire-valid exact fuel 3/6成功和绕过Wire后仅将metadata降为
2/5必trap固定防御行为。下一步可进入public `InvariantABI.evalInvariantV1`实现。

public ABI切片已完成：`InvariantABI.lean`直接import lower machine并在唯一public namespace中定义exact
`evalInvariantV1`与`InvariantTheoremV1`。evaluator只validate carrier一次，随后按ordinal选
InvariantDecl、检查initialized canonical state并委托selected lower runner；不经过
`admitReferenceProgramSliceV1`、ordinary `stepReferenceSliceV1`或external input。测试覆盖two ordinal
true/false、PureCall、checked revert、explicit trap、OOR、malformed state/program、无关Principal及
theorem proposition definitional shape。下一步是`InvariantTheoremV1`/TST-SEM-002/003 canonical corpus，
formal TASK状态暂不提前关闭。

closed theorem的kernel路径现新增第一层可信wire refinement：`WireV1`以透明`List UInt8` spine定义
remaining/read-byte，并为production `ByteArray` primitive证明任意offset（含越界`.truncated`）的
exact等价；production Cursor `takeByte`直接消费该primitive，因此不是第二套validator。当前只闭合
size/single-byte边界。后续exact-slice切片已让Cursor `takeBytes`委托shared production primitive，并以
标准库extract correctness证明其logical list精确等于transparent `drop/take`（含short与offset越界的
zero-count边界）；runtime仍使用`ByteArray.extract`，proof可经theorem rewrite绕开`copySlice` reduction。
尚不能声称617-byte canonical carrier已完成kernel validation；下一步逐层覆盖u16/u32与transport
framing。NC canonical reader的`.nonCanonical`错误合同不得误改为`.truncated`。

后续scalar切片已闭合u16/u32 little-endian：transparent与production offset reader均组合shared
single-byte primitive，production `decodeU16le`/`decodeU32le`直接委托；universal theorem覆盖任意
offset和每个partial-prefix truncation，cursor-level tests另固定remaining/nesting。下一步不再重复
primitive reader，而应建立magic/version与tagged framing的结构性refinement。完整carrier kernel
validation与formal corpus仍pending。

magic/version切片现复用exact-take bridge建立transparent/production prefix consumer与universal theorem；
ByteArray/List equality经标准库`Array.beq_toList`关联，production private `consumeMagic`直接委托并保留
cursor input/nesting。short input仍先于内容比较返回`.truncated`，足长mismatch才`.badMagic`；program
root真实截断测试已固定。下一步进入root tagged header（tag length/bytes/field count）refinement，而不是
新增第二套root decoder。完整carrier kernel validation与formal corpus仍pending。

tagged-header切片现进一步闭合u32 tag length、`1..64`、exact raw slice、ASCII、expected-tag ByteArray
compare及u16 field count。`decodeTag`与`expectTag`均委托shared production primitives；两个universal
theorem把production raw/result投影到transparent spine并保持`.truncated`/`.badTag`/
`.badFieldCount`全序。runtime expected/raw不转List；List只用于proof。下一步从root
`SemanticProgram.Data`九字段payload开始逐段refinement，不应复制完整program decoder。formal状态不变。

root payload第一层现已在拆分后的sole `Wire/CodecV1`闭合u32-length-prefixed bytes：transparent与
production primitive保持prefix truncation→limit→payload truncation顺序、zero payload与next offset，
`decodeByteArray`/`decodeString`直接委托；String继续只走既有UTF-8/NFC权威。下一步建立array count
header/iteration refinement，再进入QualifiedName；不要在proof侧重写String validator。formal状态不变。

array count/header切片现已闭合：transparent与production primitive均先读取完整u32 prefix，再执行
`count > maxCount` gate，因此partial prefix保持`.truncated`、等于上限成功、超限才
`.limitExceeded`。production `decodeArray`只委托该header并以原input/nesting重建post-header cursor；
唯一既有element loop及其错误传播未改，没有第二套generic decoder。下一步单独建立element iteration
refinement，再进入QualifiedName；完整carrier kernel validation与formal TASK/TST仍pending。

array element iteration切片现已建立稳定proof seam：原production `forIn`循环原位抽为sole
`decodeArrayElementsV1`结构递归authority，`decodeArray`直接消费它；zero-count、source order、每步cursor
线程及首错fail-fast语义不变。`decodeArray_eq_elementsV1`把已证明的header success组合到该唯一循环，
closed proof可按具体count展开而无需依赖`forIn/foldlM`内部实现，也未新增transparent/proof-side generic
decoder。下一步进入QualifiedName；完整carrier kernel validation与formal TASK/TST仍pending。

QualifiedName framing切片现已闭合：`decodeString_eq_of_sizedBytesV1`在shared sized read成功后仍显式
保留production `String.fromUTF8?`与`requireNfc`分支；`decodeQualifiedName_eq_elementsV1`只在真实array
header成功后重写到sole production element iterator与既有`parseQualifiedName`。因此header→component
UTF-8/NFC→name grammar错误顺序及cursor input/offset/nesting均不变，也没有proof-side String/name
validator。下一步按root `SemanticProgram.Data`字段逐段组合；完整carrier validation与formal TASK/TST
仍pending。

root types组合前置 seam现已闭合：`withTaggedNesting_eqV1`完整暴露limit gate优先、body error原样传播、
success保留body返回input/offset并恢复parent nesting；`decodeTag_eq_of_readBytesV1`从真实raw tag reader
success进入既有UTF-8与String ASCII gate。原private ASCII helper仅原样公开为`isAsciiTagV1`供theorem
陈述，encoder/decoder继续共享同一实现。下一步组合TypeShape sum与TypeDecl；formal状态不变。

TypeShape组合前置层现已完成：原anonymous production sum body仅机械抽为
`decodeTypeShapeBodyV1`，public `decodeTypeShapeV1`仍exactly由一次`withTaggedNesting`包装；12个tag分支、
field count、payload顺序与错误相位不变。`decodeFieldCount_eq_of_readU16leV1`从真实u16 success暴露
exact offset与`.badFieldCount` mismatch。下一步组合nullary Bool/Principal/Unit与TypeDecl；formal状态不变。

nullary TypeShape success composition现已闭合：Bool/Principal/Unit theorem都要求真实`decodeTag`与
zero `decodeFieldCount` success，随后`decodeTypeShapeV1_eq_of_bodyV1`经真实nesting gate恢复parent depth，
同时保留body返回input/offset。错误路径仍由通用`withTaggedNesting_eqV1`覆盖；其余九个shape、TypeDecl
与root types array仍pending，formal状态不变。

TypeDecl composition现已闭合：`expectTag_eq_of_headerV1`将真实expected-header reader success映到cursor，
`decodeOption_noneV1`固定canonical marker 0且不调用payload decoder；sole `decodeTypeDeclBodyV1`按
tag→id→name→shape线程真实decoder结果，再经`decodeTypeDeclV1_eq_of_bodyV1`恢复parent nesting。
下一步将这些success组合进root types array；完整root/formal状态不变。

root `types` array composition seam现已闭合：`decodeArrayElementsV1_succ`按source order执行一个真实
TypeDecl decoder、push accumulator并将完整cursor传给tail；通用`decodeArray_eq_of_elementsV1`组合真实
count header与完整run，`decodeTypeDeclArrayV1_eq_of_elements`锁定root的`maxTableElements`调用。
Bool/Principal/Unit declaration array已无需额外迭代器 theorem；root body连接仍pending。

`SemanticProgram.Data` root scaffold现已闭合：原anonymous九字段production closure机械抽为sole
`decodeSemanticProgramDataBodyV1`，再由sole `decodeSemanticProgramDataTaggedV1`包装一次nesting；transport
decoder已直接改用该同一wrapper。field composition theorem固定tag后qualifiedName→types→constants→
logicalState→events→errors→callables→invariants→requirements顺序，未移动structure gate。剩余字段
具体proof仍逐段pending。

空root table的通用composition现已闭合：`decodeArray_zeroV1`只接受真实bounded header解出count=0，
随后definitionally结束sole iterator，返回原input/parent nesting与exact post-header offset；即使传入必错
element decoder也不会调用。constants/events/errors等空表可共享该theorem，不增加表专用decoder。

canonical empty ProgramRequirements composition现已闭合：原anonymous body机械抽为sole
`decodeProgramRequirementsBodyV1`，public decoder仍由一次`withTaggedNesting`包装；body theorem按真实
ProgramRequirements tag→items array线程，wrapper恢复parent nesting。items为空时直接复用
`decodeArray_zeroV1`，不需要RequirementRequest decoder执行。

canonical public logicalState composition现已闭合：Visibility与StateDecl anonymous bodies机械抽为sole
production bodies；public visibility theorem固定tag→zero field-count，StateDecl theorem固定
tag→id→name→typeId→visibility并正确恢复两层nesting。`decodeStateDeclArrayV1_eq_of_elements`锁定root
`maxTableElements` table。private/commitment runtime仍保留，仅branch proof按需pending。

root invariants composition现已闭合：InvariantDecl anonymous body机械抽为sole production body，field
theorem固定tag→id→name→callableId，wrapper恢复parent nesting；root array corollary复用真实
`maxTableElements` header与sole iterator。callableId的structure join仍由后续structure gate负责，transport
proof不提前验证引用。

root callables scaffold现已闭合：Callable anonymous body机械抽为sole production body，九字段顺序固定为
id→kind→name→params→result→entryBlock→blocks→loopBounds→invariantSteps，public decoder仍仅一层
tagged nesting；root array corollary锁定`maxTableElements`。本切片只接受nested production decoder
success premise，不宣称Block/Instruction/Op已完成proof。

CallableKind canonical composition现已闭合：通用`decodeOption_someV1`要求真实marker reader解出1，
再从exact post-marker cursor执行真实payload decoder并保留其结果cursor；CallableKind原anonymous body
机械抽为sole production body，tag→zero field-count顺序及initializer/entry/view/pureFn/invariant五个runtime
分支均不变。当前branch theorem只覆盖fixture所需entry/pureFn/invariant，再经唯一tagged-nesting wrapper
恢复parent depth；initializer/view proof按需pending。下一步依次闭合empty params/loopBounds、
CallableResult、optional name/steps，再进入Block、Terminator与fixture所需Instruction/Op。

CallableResult composition现已闭合：原anonymous decoder body机械抽为sole production body，public decoder
仍由一次tagged nesting包装；field theorem严格线程expected CallableResult/2 header→u32 TypeId→真实
Visibility decoder，wrapper保留body input/offset并恢复parent depth。该transport theorem覆盖canonical
public result，但TypeId引用合法性仍由structure gate负责。empty params/loopBounds可直接复用zero-array；
下一步组合optional name/steps，再进入Block与fixture所需terminator/instruction/op。

optional invariantSteps的u64 blocker现已闭合：新增transparent `readSpineU64leV1`与sole production
`readU64leAtV1`，八个little-endian byte及任一位置truncation有universal refinement；production
`decodeU64le`直接委托该reader，保留input/nesting并采用reader exact offset。既有`decodeOption_someV1`
现可组合marker 1→u64 payload，all-0xff边界固定为UInt64 max；none仍复用既有marker-0 theorem。
optional name同理复用String production seam。下一步进入Block/Terminator/Instruction/Op。

Block root-element scaffold现已闭合：原anonymous Block decoder机械抽为sole production body，public
decoder仍只包装一次tagged nesting；composition严格线程Block/4 header→id→bounded params→bounded
instructions→terminator，并保留两个`maxArrayElements` gate与parent depth restoration。当前只接受真实
Instruction/Terminator decoder success premise，不宣称其nested branches已闭合；下一步处理canonical
Term.Return none/some，再处理Instruction与Literal/PureCall。

canonical Term.Return composition现已闭合：Terminator原anonymous sum body机械抽为sole production body，
Jump/Branch/Switch/Return/Revert/Trap六分支与unknown-tag `.badTag`路径保持；Return theorem严格线程
真实tag→field count 1→`decodeOption decodeU32le`，因此none/some可分别复用既有marker theorem，wrapper
恢复parent nesting。其余五个branch proof按需pending。下一步处理Instruction record，再闭合fixture
所需ValueDef、Op.Literal与Op.PureCall。

ValueDef与Instruction production scaffold现已闭合：两个原anonymous record body均机械抽为sole body，
各public decoder仍仅一层tagged wrapper。ValueDef固定header→valueId→typeId；Instruction固定header→
optional ValueDef→SemanticOp，并正确处理Option marker不占nesting、nested ValueDef恢复Instruction body
depth、最终Instruction恢复parent depth。SemanticOp仍只是真实decoder success premise。下一步机械抽取
sole SemanticOp sum body并仅闭合fixture所需Literal与PureCall branches。

canonical SemanticOp composition现已闭合到fixture所需范围：原anonymous sum body机械抽为sole
production body，全部既有op与unknown-tag行为保持；Literal严格线程tag→field count 2→typeId→
`maxCanonicalProgramBytes` sized payload，PureCall严格线程tag→field count 2→callableId→
`maxArrayElements` args，再经唯一tagged wrapper恢复parent depth。其余op branch proof按需pending。
下一步把这些field successes组合为具体Instruction、Block及callables array run。

向上组合所需singleton array现已闭合：`decodeArray_oneV1`只接受真实bounded count reader解出1，
随后通过sole `decodeArrayElementsV1`执行exact一次真实element decoder，从空accumulator得到`#[value]`
并原样返回element完整cursor；没有第二iterator或专用Instruction/Block循环。该seam将直接服务一个
instruction的leaf/root block和每个callable的单block array；多callable root仍复用通用succ theorem。

public nested-record composition现已接通：ValueDef、canonical Literal/PureCall及Instruction新增的
corollaries只组合各既有body theorem与sole `withTaggedNesting` theorem，不改runtime；premises仍是
真实header/scalar/option/bounded payload/array decoder equalities。每层以parent+1进入、保留最终body
input/offset并恢复该层parent depth。后续Block证明可直接消费public Instruction/Terminator success，
无需再次手工展开nested wrapper。

PureCall frame保持root invocation的initializer身份，Unit pureFn的`return none`在caller所需result
slot中绑定canonical empty Unit；Unit/non-Unit错误return shape继续trap `invalidCore`。因此initializer
经过任意PureCall frame成功返回后仍发布`initialized=true`。

## D2-07 reference Array/Bytes index engineering status（2026-07-31）

`WireV1`现提供fixed Array的窄canonical split/encode seam；`ReferenceV1`工程admission/runtime
现支持Array Construct与Array/Bytes IndexGet/IndexSet，set保持immutable SSA，越界走既有
`indexOutOfBounds`标准revert。Array资源通过explicit-stack postorder与cap-safe乘加分析，巨大length
不迭代，零宽元素仍按count计work，recursive Array aggregate graph fail closed。Wire sole value decoder
另以64MiB program-wide cumulative work budget跨declarations与recursive siblings线程化，并在进入
raw Array helper循环前防御性执行length cap。Map Construct/Index与Commit runtime已由后续切片
开放；formal `evalInvariantV1`/`InvariantTheoremV1`与TASK/TST仍pending。

D2-07 首个 ContextRead static-only 提议切片已冻结单行 wire catalog：仅
`proof-forge.context.unix-time-seconds.v1` → anonymous UInt64，并 exact 绑定
`context.unix-time-seconds@1.0.0` requirement。语义为 invocation immutable Unix-seconds
snapshot。Reference runtime现按selected initializer/entry/view root及其statically reachable
PureCall closure收集exact key/type集合，在lifecycle/response cursor前拒绝missing/extra/duplicate/
nonascending/wrong-TypeId/noncanonical value，并由所有PureCall frame共享同一immutable snapshot；
执行时不可能的missing/mismatch映射`internalInvariant`。invariant root/closure、targets、
caller/authorizers/randomness与formal evaluator仍未开放。

Commit当前Wire contract要求operand可解析、result TypeId精确等于operand TypeId，canonical
aggregate同样可通过；并exact绑定Wire-owned `disclosure.commitment@1.0.0` empty-predicate row，
digest domain为`pf.commit-requirement.v1`。Reference runtime现将operand的同一
`ReferenceValueV1`（exact TypeId/valueBytes）绑定到result，不hash、不重编码、不修改state/context/
effects/response cursor；initializer/entry/view与ordinary PureCall均可执行，invariant root/reachable
closure仍由Wire拒绝。该row不加入S2或target support catalog，不能把Reference执行解释为target
commitment support。

## D2-07 reference Struct engineering status（2026-07-31）

同一general-CFG Reference machine现支持Struct-only`Construct`/`FieldGet`/`FieldSet`。canonical
Struct拆分与重组由`WireV1`的窄public seam拥有并复用sole type-driven decoder；outer nesting fuel、
16MiB aggregate cap、field count/type/order、full consume与re-encode identity均fail closed。
Reference admission只开放Struct形态Construct，并以explicit-stack postorder、cap-saturating width/depth
及construction-work分析拒绝compact Struct DAG与宽值深层包装的allocation amplification；
logical-state defaults含slot prefix累计受64MiB byte/work caps。
runtime再次检查shape/index/TypeId/canonical bytes，FieldSet为immutable SSA update。entry、nested
Struct、PureCall及nonformal invariant evaluator均复用远端canonical machine。Enum/Option、
Array/Bytes/Map index与Commit runtime已由后续切片开放；formal evaluator仍pending。

## D2-07 reference Option/Enum engineering status（2026-07-31）

Map增量：Reference现接纳Wire-legal Map、empty `Construct 0 []`与immutable
IndexGet/IndexSet；Wire sole canonical decoder及新增lookup/upsert seam独占framing、unsigned
lex order、key legality和共享byte/work/nesting caps。资源 admission 使用`maxMapEntriesV1`
理论最大值作无count循环的保守上界，因此可能拒绝实际小Map。Commit runtime已由后续切片开放；
formal evaluator与TASK-D2-07/TST-SEM-002/003仍pending。

同一general-CFG/PureCall Reference machine现进一步开放`TypeShapeV1.Option`/`Enum`、对应
`Construct`以及`VariantTag`/`VariantPayload`。`WireV1`拥有唯一窄canonical variant split/encode
seam，保留outer nesting fuel、16MiB append前cap、full-consume/re-encode及错误shape/tag/count/
payload/trailing fail-closed。admission的显式栈width/depth/work分析按constructor取最大值，并按
payload occurrence（包括共享TypeId）计费；runtime防御性复核shape、TypeId、tag及payload index，
Enum runtime-tag不一致和Option-none payload access均trap `invalidCore`。Unit/Array/Map Construct、
Wire-legal recursive Struct/Option/Enum type graph在该有限maximum-resource subset仍显式unsupported；
Index与Commit runtime已由后续切片开放；正式`evalInvariantV1`/`InvariantTheoremV1`与formal
TASK-D2-07/TST-SEM-002/003仍pending。
