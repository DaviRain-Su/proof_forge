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

当前可运行的 Counter/Accumulator 路径仍经过 alpha Typed/Semantic/D3 output；它是迁移起点，
不是上述目标链已经完成。

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
3. 按 D1 → D2 → D3 → D4 把 alpha carrier/protocol迁到新设计；shared core切换时直接迁移
   EVM/Solana/NEAR/Noir consumers。
4. 每层替代实现成为唯一产品路径并通过门禁后，删除对应旧代码、旧schema和旧tests；不保留fallback。
5. qualification代码继续按 [`QUALIFICATION_INVENTORY.md`](QUALIFICATION_INVENTORY.md) 隔离，
   不混入产品迁移。

## 当前结果

- `docs-check`/`dev-check`/`ci` 已不再运行 Stage-0 或 TaskQualification；历史审计由
  `governance-check` 显式运行，release host preflight 在当前主机准确返回 `PF-HOST-INELIGIBLE`。
- CLI `build`/`build-counter` 产品诊断路径只调用 `selectProgramV1Product` →
  `normalizeProgramLocatedV1` → `compileProgramProductV1`，保留完整 located
  `DiagnosticBundleV1` 并按 `selectExitCode` 退出；成功后构造 retained
  `CompiledProgramV1` dual-carrier，再经 engineering exact requirement capability
  进入 target Plan/IR/finalization；residual alpha 仅在 capability 之后供 Plan body
  使用，不构造 legacy `Source.Program`。
- B10 已新增一请求一进程的 `proof-forge-frontend-worker-v1`：stdin/stdout 只承载
  `Frontend.Req/Ok/Err.v1`，与产品 Loader 共享单 parser snapshot，并由真实子进程测试固定
  deterministic bytes 与 64/65/70 abnormal exits。它尚未由 CLI 调用，也没有 safe-open、
  supervisor、resource receipt 或 containment 声明。
- Counter 已从真实 source 完成 ProgramV1 到目标制品的 CLI smoke；快速测试固定
  ProgramV1 identity/sourceHash/NodeId、Typed/Semantic、EVM Plan/IR 与 deterministic Yul/ABI。
- 真实 Counter/Accumulator source 已经由当前恢复桥使用 digest-pinned `solc 0.8.34` 生成
  EVM bytecode；product runtime 只要求所选工具的 executable/runtime exact closure，无关 `jv`
  缺失不再阻塞 EVM，而 release checker 继续要求完整 global bundle。这仍是 engineering
  dual-carrier + residual alpha Plan/IR + private v2alpha1 publisher 路径，不代表正式 D1–D4
  contract、formal `OutputSetV1` 或 task completion；本切片也未新增 Anvil runtime 结论。
- Legacy Source source-reading 与 v1 export decoder 已删除；Lean command/export 与
  Loader 只读 ProgramV1。产品入口是 `selectProgramV1Product` + located compile；非产品
  `selectProgramV1*`/`compileValidatedSourceV1` helpers 仅保留给测试/嵌入方。B10 worker 的
  spans payload API 与产品 OriginJoin API 共享同一私有 parse/select/SpanJoin snapshot；
  residual alpha 仅作为 `CompiledProgramV1` 内部 carrier 在 requirement capability 之后供
  target Plan/IR 使用；无 adapter、dual reader、第二套 ProgramV1 decoder 或 fallback。
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
`CompiledProgramV1` dual-carrier + engineering exact requirement resolver capability
（`resolveEngineeringRequirementsV1 (selection, compiled)` → private
`ResolvedEngineeringBuildV1`，exact retained SemanticProgramV1 `data.requirements`，
无 caller request override；静态四行 S2 support index）。**精确边界**：shipped
aggregate/CLI `materialize`/`emit` 仅接受 capability（capability 之后再抽 residual
alpha 做 Plan/IR）。**D3/S6 工程**：public residual Common resolve / validateResolved /
public makePlan 与 supportedRequirements membership 作为 product acceptance 已关闭；
cycle-free `EngineeringBuildV1` leaf sole mint；四 target 仅 capability-gated
`planFromCapability`/`irFromCapability`/`buildFromCapability`（+ descriptor/
validatePlan/validateIR inspection）；Registry 直接 capability dispatch；public
`namespace Residual` 与 `planFromAlpha`/`lowerPlan`/`filesFromIR` 完整
Semantic→Plan→IR→files bypass 已删除；dead public `ResolvedProgram` 已删除；
private target lower 仅 capability 内部；`s6-plan-cutover-deletion-gate` + Lean
residual type-chain reflection（defn/opaque/ctor）已接入 dev/ci。**D3/S7a 工程**：
aggregate `materializeResult` 返回 private-ctor `MaterializedArtifactsV1`（sole mint
`mintMaterializedArtifactsV1`；exact target/profile/kind + transitional residual-alpha
identity/hashes + retained `semanticHashV1` Digest + ordered files）；已删 public
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
ToolchainIdentity/formal exact closure/hermetic publisher/SemanticProgramV1 直连 Plan
完成态。formal task状态与 release qualification仍按各自真实条件变化，不由本恢复文档代签。
