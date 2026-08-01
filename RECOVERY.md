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

当前可运行的 Counter/Accumulator（及更广 Normalize 子集）路径已由单一 `CompiledSemanticV1` 保留
structure-valid `SemanticProgramV1`，并直接构造四个 target Plan；产品编译、resolver 与 artifact
identity 已不再持有 alpha carrier。D3 侧已有工程 `TargetRegistryV1` / requirement resolver /
Materialized/Finalized/disk-closure 与部分 planDigest 绑定，但 **formal** `registryDigest` /
SupportClaim / 可达 BuildIdentity mint / formal `OutputSetV1` 与完整 Phase-1 语言/runtime DoD
仍未闭合。这是迁移中的工程纵切面，不是目标链已经完成。

### D3-E1 产品决策（2026-08-02）

**正式-layout `registryDigest` / registry root codec 不进入当前产品路径。**
工程 sole authority 保持 frozen `TargetRegistryV1` membership/default/profile（无 root digest
字段；inspection-only engineering digests 不得充当 product selection / capability / artifacts
身份）。在 formal D3 TASK 与 codec 冻结前，**不**把工程 registry 伪装成 formal registry root；
也不在 CLI/publisher 暴露伪 `registryDigest`。该边界为 **永久工程-only**，直到显式 formal
切片重新打开产品面。

**日常工程队列**（非 formal）：[`docs/engineering-backlog.md`](docs/engineering-backlog.md)。

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

1. CLI 产品 source 路径为单一、fail-closed 权威（**当前工程事实**：进程内
   `Loader.selectProgramV1Product` → located Normalize → `compileProgramProductV1`；
   2026-08-01 起前端监督层 SafeOpen/worker supervisor 已按产品决策移除，不再作为完成条件）。
   无 dual open、无 embedded Counter fallback、无 legacy Source reader。
2. shipped ProgramV1 产品表面都经 CheckV1 → NormalizeV1 生成 structure-valid `SemanticProgramV1`，
   不再仅是 Counter-like S1（**当前**：Normalize 已扩多宽/控制流/fn/for/call 等，完整语言面仍未闭合）。
3. `CompiledSemanticV1` 是唯一产品编译成功 carrier；alpha Typed/Semantic lowering与 residual accessors 无产品调用。
4. `ProgramRequirementsV1` 是唯一产品 requirement authority；target-neutral contribution engine 只向该 authority供给，不存在第二套 AST walker、alpha parity或 caller override。
5. EVM/Solana/NEAR/Noir 四个 Plan body 均直接消费 retained `SemanticProgramV1`（经 resolved capability）。
6. 产品可达 formal-layout registry digest、SupportClaim/decision、BuildIdentity、Plan/IR identity 与
   formal `OutputSetV1` 已接线，transitional publisher 残留退役（**当前**：工程 carriers/S7 已接线，
   formal 与部分 planDigest 全 target 仍未闭合）。
7. legacy `Core/Source`、alpha Typed/Semantic 与旧 compiler入口的产品 consumer 归零；测试先迁后删
   （**当前**：alpha Core 模块与产品 import 已物理删除/门禁禁止）。
8. 聚焦/deletion/reflection gates、`just dev-check`、普通 `just ci`、docs/SBOM 全绿。

formal TASK/TST/EV/qualification 是独立轴，不由上述 engineering completion 代签；也不得用 formal pending 否定已经成为唯一产品 authority 的工程切片。

## 产品迁移 Wave DAG

```text
Wave 1  D1 ProgramV1 CLI source path + DiagnosticV1 product cutover
        [done as engineering] 2026-08-01：监督式 frontend 层按产品决策移除；
        现 sole 产品源路径 = 进程内 Loader.selectProgramV1Product
  → Wave 2  [done] freeze S1 Semantic + EVM/Solana/NEAR/Noir V1 Plan leaf + single carrier
           → [current] expand sole Normalize/Reference/target beyond S1
             （多宽/控制流/fn/for/call/部分聚合已接线；完整语言面未闭合）
  → Wave 3  formal-layout identity + OutputSetV1 闭合（工程 S4–S7c 已部分接线）
  → Wave 4  D4 EVM first → D5 Solana + D6 NEAR + D7 Noir target completion
  → Wave 5  D8 aggregate/security/repro/clean-room/review
```

**Wave 1 / D1 工程路径（2026-08-01 起）**：产品 CLI `build` 经 validated project root 下进程内
`Loader.selectProgramV1Product` 读源 → `normalizeProgramLocatedV1` → `compileProgramProductV1`。
历史上的 B9–B12 监督式 SafeOpen/frontend-worker 切片曾接线，**已按产品决策整体移除**
（模块/exe/gate 删除；contained/host-race formal 资格不再适用；`TASK-D1-08` superseded）。
`Frontend/ProtocolV1` 与 `WorkerV1` 协议面可仍存在于树中供测试/残留，**不是**产品 CLI 源权威。
D1-04 shared IntegerLiteral 与 ProgramV1 command/export/v2 仍为 sole 源表面。

**当前 wave = Wave 2 / D2 扩面**：四 target Plan body 已直连 retained `SemanticProgramV1`；
`CompiledSemanticV1` + `ProgramRequirementsV1` sole freeze + engineering resolver/capability
已接线；alpha Core 与产品 consumer 已删。sole Normalize 已超出最初 Counter-like S1（多宽 UInt/Int、
比较/assert、if/match、revert/emit、fn、let/for、shift/bitwise、call/schedule、部分聚合/Field 等），
完整 ProgramV1→Semantic 表面与 Reference 全 op 仍未闭合。**不是** D4–D7 formal 完成。

并发规则：`main` 是唯一集成权威。允许从 exact clean `main` 创建临时隔离 worktree 推进接口已冻结、文件 allowlist 完全不重叠的 leaf lanes；worker 不编辑 `AGENTS.md`、`RECOVERY.md`、`MIGRATION_MATRIX.md`、实现日志、umbrella、suite注册、`lakefile.lean`、justfile或SBOM pin。主代理只读审查并串行集成，聚合门禁通过后立即删除临时 worktree/branch。shared-core cutover、文档、package pin与提交始终串行。

## 当前结果

- `docs-check`/`dev-check`/`ci` 已不再运行 Stage-0 或 TaskQualification；历史审计由
  `governance-check` 显式运行，release host preflight 在当前主机准确返回 `PF-HOST-INELIGIBLE`。
- **产品 CLI 源路径（当前）**：`build` 经进程内 `Loader.selectProgramV1Product`（validated project root
  下 `IO.FS.readFile`）→ `normalizeProgramLocatedV1`（CheckV1 ok∧analysisComplete + structure-gated
  Semantic）→ `compileProgramProductV1` → private-ctor `CompiledSemanticV1` → engineering
  `resolveEngineeringRequirementsV1` → 四 target capability Plan/IR/finalize → disk closure。
  失败走 `DiagnosticBundleV1` / `selectExitCode`。全链不构造 legacy `Source.Program`。
- **历史 frontend 监督层（已移除）**：B9 Protocol / B10 worker / B11 SafeOpen+supervisor / B12 CLI
  切over 曾完成工程接线；**2026-08-01 产品决策整体删除**该层。详情与 superseded 说明见
  `MIGRATION_MATRIX` D1-08 与 AGENTS checkpoint；不得再写成当前产品路径。
- ProgramV1 expression 与 pattern integer literal 共用 sole decoder：unsigned decimal 或
  lowercase-prefix `0x` hexadecimal（hex digits 可大小写），拒绝 `0X`/binary/octal/underscore，
  范围 `0..2^256-1`；等值 spelling → 相同 AST/canonical bytes/sourceHash（D1-04 工程切片）。
- Counter/Accumulator 等真实 source 可经 CLI 产出四 target 工程制品；EVM 使用 digest-pinned
  `solc 0.8.34` 生成 bytecode，另有 EvmSolc 验收门与历史 Anvil smoke（**非** formal Reference↔Anvil）。
  Solana 有 SBPF→ELF + Mollusk 运行时差分工程链路；NEAR 主要为 `wat2wasm` 结构验证；Noir 为
  relation source package（无 prove/verify）。四 target Plan body 均由 retained `SemanticProgramV1`
  经 capability 构造；工程 output 已接 S7a–S7c，仍非 formal D1–D4 / formal OutputSetV1 完成。
- Legacy Source source-reading 与 v1 export decoder 已删除；command/export 仅 ProgramV1 v2。
  `selectProgramV1Product` 为产品 CLI 使用的 Loader 入口；`selectProgramV1*` /
  `compileValidatedSourceV1` 仍可为测试/库 API。alpha Core 模块与产品 import 已删/门禁禁止；
  无 adapter、dual reader、第二套 ProgramV1 decoder 或 fallback。
- [`MIGRATION_MATRIX.md`](MIGRATION_MATRIX.md) 记录 D1–D4 formal vs 工程地基；formal 仍 0/27 done。
- [`docs/engineering-backlog.md`](docs/engineering-backlog.md) 为日常工程可勾选队列。
- [`QUALIFICATION_INVENTORY.md`](QUALIFICATION_INVENTORY.md) 隔离 qualification 子系统；ordinary
  product gate 无直接依赖。

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

Return与Block public composition现已接通：Return corollary组合真实tag/field-count/optional ValueId后
恢复Terminator parent；Block corollary严格线程header→id→bounded params→bounded instructions→
public Terminator，并恢复Block parent。两者均只提升既有body theorem，不新增runtime或nested claim。
现在可将zero/singleton array theorem与public Instruction/Return successes直接拼为fixture三种单Block。

canonical Block array composition现已闭合：`decodeBlockV1_emptyV1`组合empty params+empty instructions，
`decodeBlockV1_oneInstructionV1`组合empty params+exact一次public Instruction；两者均从真实bounded
count reader returned offset构造下一cursor，再消费真实public Terminator success。entry gate使用前者，
literal leaf与PureCall invariant使用后者。下一步将每个Block用singleton array接入具体Callable fields。

Callable public composition现已接通：`decodeCallableV1_eq_of_fieldsV1`将既有九字段body theorem穿过
sole tagged wrapper，严格保持id→kind→name→params→result→entryBlock→blocks→loopBounds→steps，
三个array各自继续使用production `maxArrayElements` authority，并保留final steps cursor input/offset、
恢复Callable parent depth。它仍以真实field successes为premises，不提前声称具体callable已闭合。

canonical single-Block Callable形状现已闭合：`decodeCallableV1_singleBlockV1`用真实count=0 params、
count=1 Block与count=0 loopBounds headers组合sole zero/singleton iterator；result与steps分别从前一
header exact returned offset开始。kind/name/result/steps仍是actual production successes，因此同一
theorem可服务entry gate、literal pureFn与PureCall invariant。下一步组合root多callable iterator run。

root四callable iterator run现已闭合：通用`decodeArray_fourV1`只接受真实bounded count=4 header，
按source order执行exact四次给定production decoder并返回第四cursor；Callable专用corollary锁定
`maxTableElements`与`decodeCallableV1`。它只证明四个supplied callable的顺序，不伪造entry/pureFn/
invariant kinds；具体fixture各项仍由前述public Callable successes提供。下一步接入root body callables field。

public tagged root fields composition现已接通：九字段body theorem直接穿过sole root nesting wrapper，
保持qualifiedName→types→constants→logicalState→events→errors→callables→invariants→requirements，
所有tables仍锁定`maxTableElements` production decoder，final requirements cursor保留input/offset并恢复
root parent depth。四-callable result可直接作为`hcallables`；magic、finish与structure仍明确不在该结论内。

full transport framing composition现已闭合：`decodeSemanticProgramDataV1_eq_of_framing`严格按production
顺序组合exact `bytes.size ≤ maxCanonicalProgramBytes` gate→magic→public tagged root→finish success；
配套finish-error theorem原样传播任意error，特别是`.trailingBytes`，不重映射。size limit仍先于magic，
magic/root errors仍由production premise authority拥有。structure gate与re-encode identity仍不在本层。

carrier identity composition现已接通：acceptance theorem依次要求真实transport decode、现有
`encodeSemanticProgramDataV1` success（其内部先运行structure gate）及exact runtime ByteArray BEq=true，
并返回包含original input bytes的opaque carrier；BEq=false theorem在encode success后exact返回
`.nonCanonical`。这没有引入structure-free encoder，也不把conditional composition写成formal validity。

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

## D2-07 concrete invariant carrier fixture（2026-08-01）

`Tests.Semantic.InvariantABI`中原先仅在IO测试体内构造的`PublicInvariantABI` fixture现提升为纯
`CanonicalInvariantFixtureV1.data`：exact `Tests.PublicInvariantABI` QualifiedName、Bool/Principal/Unit
三类型、单Bool state、entry gate→pure truth leaf→truth/falsehood两个invariant roots的四callable
source order，以及两个InvariantDecl均由一份data authority承载。新增独立显式1235-byte
`canonicalBytes` golden；工程suite先经sole production `encodeSemanticProgramDataV1`并检查size与
byte-for-byte identity，随后仍由既有encode→`decodeSemanticProgramV1`路径构造carrier。

这只闭合了concrete data/byte spine，不是closed kernel carrier theorem。普通`rfl`/`decide`不能归约
production structure gate，且没有改用`native_decide`、axiom、cast、第二decoder或提高recursion limit。
下一步继续用现有production decoder composition显式闭合该golden的transport premises，再单独闭合
structure-gated encoder premise；`InvariantTheoremV1`与formal TASK/TST状态不变。

outer framing现已完成第一个kernel切片：显式golden被分成15-byte magic、26-byte
`SemanticProgram.Data`/9-fields root header和1194-byte field remainder，避免为prefix proof遍历完整
List。`CodecV1.consumeMagic_eq_of_bytesV1`只组合sole production `consumeMagicBytesAtV1`；fixture theorem
再经既有transparent-spine refinement证明真实production magic cursor `0→15`及root tagged-header
cursor `15→41`（tag body nesting=1），同时closed证明总长1235。没有新增decoder；qualifiedName及后续
九字段、finish、structure-gated encoder与carrier identity仍待后续逐层闭合。

QualifiedName下一子片已闭合production framing：count=2 cursor 41→45，`Tests` raw sized bytes
45→54，`PublicInvariantABI` raw sized bytes54→76。新增seam均为conditional composition/refinement，
不替代production reader；UTF-8/NFC与Common parser的最终value composition仍待下一片。

QualifiedName value现已闭合。`Unicode.normalizeNfc`在sole authority内部增加语义等价的all-ASCII
fixed-point fast path，并提供带显式`isAscii=true`前提的kernel theorem；全128 ASCII scalar及既有
non-ASCII corpus均通过。fixture随后经production UTF-8、NFC、two-element array iterator与Common
`parseQualifiedName`证明`decodeQualifiedName` cursor 41→76。types字段从offset 76开始。

types字段现已完整kernel闭合：count=3（76→80），三个production TypeDecl分别为anonymous Bool
（80→114）、Principal（114→153）、Unit（153→187）；每个路径均保留TypeDecl nesting=2与
TypeShape nesting=3，并经真实tag/field-count/scalar/Option-none decoder组合。empty constants array随后
由production zero-array authority闭合187→191。

singleton logicalState现已闭合191→249：production array count=1后，真实StateDecl路径依次消费
header 195→210、id 210→214、ASCII/NFC name `flag` 214→222、typeId 222→226，以及nested
`Visibility.Public` 226→249；StateDecl与Visibility wrapper均恢复parent nesting。empty events/errors又经
production zero-array authority闭合249→253→257。显式golden仅重新分段，production encoder
byte-for-byte suite仍确认总长1235且内容不变。下一字段为四元素callables；尚未闭合root finish、
structure-gated encoder/carrier theorem、`evalInvariantV1`/`InvariantTheoremV1`或formal TASK/TST evidence。

callables count=4现已闭合257→261，首个`entry_gate`完整闭合261→419。production路径依次消费
Callable header/id、nested Entry kind、Option.some ASCII/NFC name、empty params、nested public Unit
CallableResult、entryBlock=0、singleton Block；Block内部为empty params/instructions与nested
`Return none`，随后empty loopBounds及absent invariantSteps。所有wrapper均恢复parent nesting，显式
golden重分段后仍由production encoder suite确认1235-byte identity。下一片从offset 419的pure truth
leaf开始；其余callables/root/carrier及formal状态均未闭合。

第二个`truthLeaf` callable现已闭合419→654。除PureFn kind、ASCII/NFC name、public Bool result与
singleton Block外，production路径进一步闭合singleton Instruction：Option.some ValueDef `(0, Bool)`、
`Op.Literal` typeId 0及canonical Bool payload `[1]`，再消费`Return (some 0)`、empty loopBounds与
`invariantSteps=some 3`。Instruction/ValueDef/SemanticOp最高进入nesting 5并逐层恢复。显式golden
重分段及production encoder byte identity仍为1235 bytes；下一片从offset 654的`truth` invariant
callable开始，剩余root/carrier与formal状态不变。

第三个`truth` invariant callable现已闭合654→888。production路径确认Invariant kind、ASCII/NFC name、
public Bool result与singleton Block；唯一Instruction包含ValueDef `(0, Bool)`及真实`Op.PureCall 1 #[]`，
随后消费`Return (some 0)`、empty loopBounds与`invariantSteps=some 6`。最高nesting仍为5并正确恢复，
234-byte truth segment与347-byte remainder保持1235-byte encoder golden identity。下一片从offset 888的
`falsehood`开始；尚未闭合root fields、carrier theorem或formal evidence。

第四个`falsehood` invariant callable现已闭合888→1126：真实Literal路径确认ValueDef `(0, Bool)`与
canonical Bool false payload `[0]`，随后为`Return (some 0)`、empty loopBounds及steps=3。238-byte
segment与109-byte remainder保持golden identity。四个已证明的Callable再经sole production four-element
iterator按gate→leaf→truth→falsehood顺序组合，完整callables字段闭合257→1126。下一字段为两个
InvariantDecl；requirements/root finish/carrier theorem及formal evidence仍pending。

root尾部现已闭合：两个InvariantDecl分别固定`(0,"truth",2)`与`(1,"falsehood",3)`，production
two-element array消费1126→1206；empty ProgramRequirements再消费1206→1235。九字段root composition
按既有exact cursor链恢复nesting 0，size/magic/tagged-root/finish production framing最终证明
`decodeSemanticProgramDataV1 canonicalBytes = .ok data`。新增通用finish seam仅证明offset=input.size时
sole trailing-byte check成功，不替代decoder。当前结论严格为transport-only；structure-gated encoder
identity、`decodeSemanticProgramV1` carrier theorem及formal TASK/TST仍pending。

structure证明现已开始而未越界：原structure gate的root shape、table IDs与shallow declaration refs
被机械抽为`validateSemanticProgramStructurePreludeV1`，完整production validator直接调用该prelude，
没有第二套validator。production另提供按全部真实phase成功结果组合的refinement theorem；1235-byte
fixture已kernel证明prelude成功。type/value/signature/CFG/requirements phases及完整structure、encoder/
carrier identity仍需后续逐片闭合，formal状态不变。

下一production phase `validateTypesStructureV1`已对fixture的三项primitive声明闭合：Bool、Principal、
Unit逐项通过真实named-rule与shape/catalog authority。TypeKey phases尚未由kernel theorem闭合，不能把
本切片扩写为完整type/structure acceptance。

TypeKey按phase顺序继续：全anonymous三项已证明sole `validateNamedPrefixRankV1`成功。下一阻塞点是
`primitiveLeaf`内部真实TypeShape encoding + private qsort/adjacent comparison；不得用第二套shape key、
opaque digest或提高recursion depth绕过。recursive/namedBody尚未越序组合，完整TypeKey仍pending。

`primitiveLeaf`阻塞现已透明闭合：`encodeNullary_eq_okV1`仅refine sole tagged encoder成功framing；
production lex comparator的原local recursion被机械命名并提供equal-step/lt/gt refinement。为避开Lean
4.31 opaque qsort，sole primitive phase在全部keys编码完成后对≤3 keys作最多三组同comparator pair scan，
>3 keys原qsort+adjacent路径不变；3-key non-adjacent duplicate及4-key qsort boundary均有回归。
fixture的Bool/Principal/Unit exact encoded bytes及三组distinct比较已kernel闭合。下一片为
`recursiveAnonymous`，完整TypeKey仍pending。

剩余TypeKey已按序闭合：fixture无Array/Map/Option，production `recursiveAnonymous`在构造HashMap前走
empty-domain success；primitive-only table无Struct/Enum/Array/Map edge source，production
`namedBodyCycle`在DFS前success。四个真实subphase经`validateTypeKeyPhasesV1_eq_ok_of_phases`组合为
完整TypeKey seam成功。下一production gate为named TypeDecl name uniqueness；完整structure仍pending。

named TypeDecl exact-name uniqueness现已闭合：三项fixture TypeDecl均anonymous，真实production collector
得到empty array；shared name checker新增语义等价的empty/singleton no-sort fast path并返回success。
`validateNamedTypeNameUniquenessV1 data.types = .ok ()`已kernel证明。下一片进入canonical valueBytes。

canonical valueBytes第一片已闭合empty constants table：sole production walker执行零次，精确证明
`validateConstantsValueBytesV1 data.types data.constants maxCanonicalProgramBytes =
.ok maxCanonicalProgramBytes`。第二片也已按callable source order闭合：gate无literal，truthLeaf的
canonical Bool `#[1]`经sole decoder消耗2单位，truth的PureCall不消费valueBytes，falsehood的
canonical Bool `#[0]`再消耗2单位，故production callable walker精确返回
`maxCanonicalProgramBytes - 4`。下一片进入declaration/name/signature gates；完整structure、encoder/
carrier identity及formal TASK/TST仍pending。

canonical valueBytes之后的same-error declaration-name组已按production顺序闭合：constants、events、
errors为空，interface-field walker也无声明可遍历；logicalState仅`flag`一项，走shared exact-name checker
的singleton no-sort success path。下一阻塞为callable signature phases，随后才是InvariantDecl exact join
与identifier grammar；不得提前声称完整structure成功。

callable signature phase现已闭合。production对≤4个extracted callable names使用六组以内exhaustive
exact equality scan，>4仍走原private qsort+adjacent路径；所有parameter表为空并由≤1 fast path跳过sort。
fixture随后真实通过kind/name、entry/view、initializer absence、Bool-public invariant result、zero params/
loopBounds、non-closure metadata与root steps presence。紧随其后的InvariantDecl exact join也已闭合：
production过滤callable source order得到`#[2,3]`，两行declaration依次精确匹配callable id、kind与name。
declaration identifier grammar也已闭合：production source-order walker检查state `flag`、两项
InvariantDecl name及四项callable name；重复的`truth`/`falsehood`仍在各自site经过sole shared
`validateIdentifierComponent`。ASCII只用于refine pinned Unicode NFC fixed-point，长度、非`_`、
`Lean.isIdFirst/isIdRest`仍由真实authority检查。下一production gate进入CFG/invariant phases。

CFG generic callable walker现已按source order闭合全部四项：entry `gate`通过empty
defs/effects/loops与`return none`；`truthLeaf`和`falsehood`各以single Bool literal定义ValueId 0并返回；
`truth`以nullary PureCall连接`truthLeaf`并返回同一Bool TypeId。sole
`validateCallableCfgShape`仍按a–j顺序运行；reachability/defSites/defTypes各只由production phase构造一次，
singleton dominator reachable/unreachable fixed point均由kernel定理固定。global ContextRead catalog尚未组合，
其后的invariant closure/fuel、requirements、完整structure/encoder/carrier/formal状态仍pending。

generic `.cfg` production phase现也已闭合：新seam原样执行四个source-order callable validator，再执行
原private global ContextRead catalog；fixture无ContextRead，故catalog保持empty seen table并成功。structure
gate仍消费同一phase，mixed callable/catalog error precedence由既有WireV1回归固定。下一片进入五项
invariant closure restrictions；fuel、requirements及完整structure仍pending。

进入closure证明前已先保持行为做单一analysis重构：direct-root检查后，production
`computeInvariantClosureMembershipV1`现在只计算一次，exact members依次传给metadata、call-DAG、
closure-CFG、PureFn-op及exact-fuel checker；不再由五个downstream phase重复计算。phase/error顺序不变，
fuel proof seam对members长度fail-closed，并由完整composition theorem固定它必须来自closure结果。
本片仅准备proof boundary，尚未声称canonical closure/fuel成功。

closure首个kernel结果现已闭合：production worklist `while`机械抽取为以`callables.size`为fuel的total
worker；每个callable由members bit保证最多append一次，pending work耗尽fuel时fail-closed。canonical roots
先seed `#[2,3]`，truth发现pure leaf 1，最终exact members为`#[false,true,true,true]`。额外tight-fuel
回归固定多root、duplicate call及reachable PureFn cycle下恰好处理四项；metadata/DAG/CFG/op closure仍pending。

紧随membership的两项closure gate现已闭合。metadata source-index scan改为等价total worker并确认唯一
PureFn `truthLeaf`的steps present与member bit一致。call-DAG保留caller→block→instruction顺序，将graph
build、ready collect与Kahn queue分别抽为fuel worker；canonical graph精确为indegree `#[0,1,0,0]`、
adjacency `#[#[],#[],#[1],#[]]`、ready `#[2,3]`，Kahn追加1并处理3 members。下一项为closure CFG。

剩余non-fuel closure也已闭合：CFG acyclicity与PureFn op allowlist的source-index loops均机械抽为
`callables.size` fuel workers，并由done/exhaustion lemmas固定total边界。members 1/2/3的singleton blocks均
无back edge；唯一reachable PureFn truthLeaf只含允许的Bool literal，invariant roots不进入PureFn-only scan。
因此`validateInvariantClosurePhasesV1 data.callables = .ok closureMembers`已kernel成立；下一项exact fuel。
