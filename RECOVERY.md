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
  metadata recheck 与 closed redacted faults）；B11a2 已新增 pure canonical/public-safe Darwin
  development-observation receipt model。B11b1 已以 `posix_spawn`/独立 process group 监督**已编码**
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
  pathname spawn；两个 worker均从 native no-follow fd-derived private snapshot执行，suspended spawn/vnode
  mutation与snapshot cleanup fail closed。当前非 Darwin product CLI 以 closed protocol diagnostic/零制品
  拒绝，portable CI 不声称 Linux materialization positive。formal executable/import identity、
  controller-backed containment 与 formal TASK-D1-08 仍缺失。
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

### 2026-07-30 shared-CFG selective integration

当前 sole Normalize 保留 upstream generalized lowering：`if` 支持嵌套、缺省 else 与
continuation，literal/bind statement `match` 支持多 case/default/join；Bool entry/view result
继续属于 shared ABI。新增能力限于显式 UInt64/Bool body-local `let`（新绑定遮蔽参数和旧
local，分支 local 不逃逸）以及精确 parameterless sole-UInt64-phi source contract。四 target
没有获得 general CFG adapter，只 fail-closed 识别 exact terminal 3-block Branch、4-block
empty join、4-block sole-UInt64-phi join 与 3-block one-UInt64-case+default Switch（转 compare-eq
conditional）。multi-case、nested 与其他 join 的 target materialization 仍 fail closed。
