# RFC 0014：跨后端的统一语义降级契约

Status: **Draft**

Date: 2026-07-06

Builds on: [RFC 0003](0003-portable-ir-and-runtime.zh.md)（portable IR）、
[RFC 0004](0004-evm-semantic-plan.zh.md)（EVM semantic plan）、
[RFC 0005](../../rfcs/0005-solana-sbpf-assembly-backend.md)（Solana sBPF 后端）。

## 摘要

每个 ProofForge 目标后端都应当通过相同的**流水线形状**（pipeline shape）来降级 portable IR：

```text
contract_source / ContractSpec
  -> ProofForge.IR.Module
  -> resolveCapabilities          -- 共享，通过 Target.Adapter
  -> validateModule*              -- 逐目标检查 + 共享子集
  -> buildModulePlan*             -- 可检查的 target-semantic plan
  -> lowerToAst                   -- 语法 AST（Yul / Wasm / sBPF / Psy / Leo）
  -> printer -> 外部工具链
  -> buildArtifactMetadata        -- plan 驱动
```

EVM 已经端到端遵循这一形状（`Backend/Evm/{Validate,Plan,Lower,IR}`，由 `just evm-plan` / `just evm-semantic-plan` 门控，并带有 `Refinement` 层）。其他主要后端则不然：**Solana** 仅有 `validateCapabilities` 加上一个隐式的 `LowerCtx`，**NEAR** 拥有丰富的 `validateModule` 但没有 plan 模块，而 **Psy** 仅有仅元数据的 `PsyModulePlan`。

本 RFC 提议**Tier B 统一**：让每个主要后端对齐到相同的*契约*（validate、plan、AST、smoke），而不强制采用单一的全局 `ModulePlan` 类型。Plan 类型保持逐目标，正如 [RFC 0004](0004-evm-semantic-plan.zh.md) 的非目标已经要求的那样，因为 account/CPI、host-import 和 circuit 模型各不相同。两个相邻的层级——共享 IR 操作语义（Tier A）和端到端 refinement（Tier C-diff 差分 replay / Tier C-proof 机器证明）——在本 RFC 中界定范围但不交付。

## 动机

如今的强制执行不均衡，在 EVM 之外更是分散的：

| 后端 | Validate | ModulePlan | Refinement | Semantic-plan CI gate |
|---|---|---|---|---|
| EVM | `Evm.Validate.lean`（约 1.7k LOC） | `Evm.Plan.ModulePlan`，包含 `ExprPlan`/`StmtPlan` | `Evm.Refinement`（`TraceObligation`、`YulSemantics`） | `just evm-plan`、`just evm-semantic-plan` |
| NEAR | `WasmNear/IR.validateModule`（丰富） | **无** | `WasmNear/Refinement.lean`（最强的形式化层） | 无（形式化锚点在 `Tests/NearWasmFormal.lean`） |
| Psy | 仅有 `validateCapabilities` | `PsyModulePlan`（storage/context/events/crosscalls——仅元数据） | 差分 `dargo execute`（FV-4） | `just psy-metadata*` |
| Solana | 仅有 `validateCapabilities` | **无** | **无** | 无（行为级：golden asm、Mollusk、surfpool/web3） |

这一差距在 Solana 上最为明显：

- `SbpfAsm.lowerModuleCore` 以 `validateCapabilities`（target profile 检查，V-GATE-SOLANA-05）开头，随后立即在一个 `LowerCtx` 内构建 account schema、state layout、locals、scratch space 和 allocator。
- 不存在 `Solana/Plan.lean`。Account layout 位于 `StateLayout.lean` 和 `buildModuleInputSchema` 中；CPI/PDA/sysvar lowering 位于 `Extension.lean`（`ProgramExtensions.fromPlan`、`lowerPlan : Array AstNode`）；manifest 和 IDL 在同一个 lowering 的下游发射。
- `Extension.lean` 中的 PDA 校验目前对缺失的 account binding 发射的是**注释**，而不是 lowering 前的 plan 检查。
- 不存在 `Solana/Refinement.lean`，也没有从 `Solana` 到 `ProofForge.IR.Semantics.lean` 的链接。

其后果是：在 Solana 上，"语义强制执行"分散在 diagnostic、golden asm、Mollusk 和 surfpool/Web3 gate 之中，**没有可检查的 plan 制品**可供 reviewer、golden test 或 refinement obligation 持有。这种不对称并非 portable IR 所强加——`IR.Semantics.lean` 本身就是链中立的——它是每个后端各自选择 lowering 形状的结果。

统一*契约*（而非 plan 代数）使三件事成为可能：

1. 每个后端都有可 review 的 plan 制品，镜像为 `just *-semantic-plan` smoke，类似于 `evm-semantic-plan`。
2. 一个挂载点，用于承载来自
   [`docs/formal-verification.md`](../../formal-verification.md) 工作流 25
   的跨后端 obligation（FV-2 语义增长、FV-8 ValueVault 不变式）。
3. 一个共享的 `validate` 子集（标识符、返回路径、ownership hook），每个后端要么委托给它，要么显式覆盖，而不是每个后端各自重新发明相同的检查。

## "语义统一"的三个层级

| 层级 | 含义 | 代价 | 本 RFC 范围内？ |
|---|---|---|---|
| **A** | 共享 IR 操作语义（`IR/Semantics.lean`）是基准；每个后端针对 IR 子集（语义当前覆盖的部分）通过共享场景的 trace obligation。 | 中等——语义已存在但需增长（FV-2/FV-3）。 | **否**（已确认的依赖；由 FV 工作流跟踪）。 |
| **B** | 共享 lowering *契约*：逐后端的 `validateModule*` + `*ModulePlan` + `lowerToAst` + plan 驱动的 metadata + golden `*-semantic-plan` smoke。 | EVM 已完成；Psy 易–中等；NEAR 中等；Solana 中等–困难。 | **是。** |
| **C-diff** | 差分 trace replay：Quint MBT 后端从 `IR.Semantics` 生成 ITF trace，并针对每个后端实际发出的制品 replay（EVM 通过 Foundry；Solana 通过 Mollusk；NEAR 通过 offline-host）。作为完整目标链形式化语义的务实替代。 | EVM 已落地（`just quint-evm-backend-replay-gate`）；任何后端一旦存在 `*ModulePlan` 即可推广。2026-07-07 审计选定 NEAR 为下一个候选（见 `docs/quint-cdiff-multi-backend-design.md`）。 | **部分。** RFC 0014 消费 Quint 后端的 trace 做端到端 smoke；不重新设计 Quint 后端本身。 |
| **C-proof** | 机器可检查的端到端 refinement：Lean IR 语义 ⟷ 形式化目标链执行模型。 | 困难。EVM 可借鉴 `powdr-labs/evm-semantics`（一台通过 `ethereum/tests` 的 Lean EVM 语义）。Solana 仍是研究（FV-4）：没有现成的 sBPF Lean 语义。 | **否**（明确的非目标）。 |

**把旧的 Tier C 拆成 C-diff 与 C-proof 是关键决策。** 它把「我们能用同一份场景跑
真实链、并检查状态转移是否一致」（Tier C-diff —— 工程性的、可广泛推广的）与「我
们有一个机器证明，证明 IR 语义与目标执行模型在每种行为上都一致」（Tier C-proof
—— 研究级的、依赖生态的）区分开来。

### Quint 验证后端的角色

Quint 后端（`ProofForge/Backend/Quint/*`，见 [`docs/quint.md`](../../quint.md)）
是 ProofForge 第一个「制品」是**验证制品**而非部署制品的后端。它从 portable IR
发出：

- 一个 Quint 状态机模型（`.qnt`），供 Apalache 做 `quint verify`
  model-checking，检查 `quint_invariant` 安全性 / `quint_liveness` 时序性质——
  Tier A 的不变式在每个后端上游强制执行。
- MBT trace（ITF 格式，通过 `quint run --mbt --out-itf`），再用
  `ProofForge.IR.Semantics`（`Tests/Quint/*Replay.lean`）replay——随 IR 子集
  增长的 Tier A 差分覆盖。
- EVM backend replay（`just quint-evm-backend-replay-gate`）：同一份 ITF trace
  被降级为 Foundry 测试，对 etched runtime bytecode replay——这是当前 **EVM 的
  Tier C-diff** 实例。

具体而言，本 RFC 的 Tier B `*ModulePlan` 制品是**桥梁**，让 Tier C-diff 能扩展到
EVM 之外：一旦某后端有可检查的 plan 和稳定的制品发射器，一个类比 EVM 的
`*-quint-backend-replay-gate` 就能对那个后端的输出（Solana 的 Mollusk、NEAR 的
offline-host、Psy 的 `dargo execute`）replay Quint MBT trace，而无需等待目标 VM
的 Lean 形式化模型存在。Tier C-proof 仍是那些有成熟 Lean 语义的链（EVM 通过
powdr 式集成）的路径；Tier C-diff 则是其他所有后端的务实底线。

本 RFC 仅针对 **Tier B**。Tier A 和 Tier C-diff 被确认为已发布的依赖（Quint 后端、
`IR/Semantics.lean`）；Tier C-proof 仍为非目标。

## 设计目标

- 让每个主要后端通过 **validate → plan → AST** 降级，且 plan 是一个**可检查的制品**，而不是临时的 lowering 上下文。
- 在 Psy、NEAR 和 Solana 上镜像 EVM 的 smoke 模式（`just evm-plan`、`just evm-semantic-plan`），使 reviewer 可以 diff plan，而不仅是 bytecode/asm。
- 抽取真正共享的 `validate` 子集（标识符、入口返回路径、按 profile 不支持的类型、ownership hook），让后端不再重复它。
- 保留 RFC 0004 的边界：目标 plan 类型是**目标特定的**，而不是一个对所有链通用的单一 `ModulePlan`。
- 为 Tier A（共享语义）、Tier C-diff（差分 replay）和 Tier C-proof（refinement 证明）留下一个干净的接缝，以便后续挂载而无需重新争论 lowering 边界。

## 非目标

- 一个所有后端共享的单一全局 `ModulePlan` 类型。RFC 0004 的非目标已经排除了这一点；account/CPI、host-import 和 circuit 模型各不相同。
- 机器可检查的端到端 refinement（Tier C-proof），包括 Solana syscall 或 sBPF 语义的 Lean 模型，或把 EVM 后端接到 `powdr-labs/evm-semantics`。Tier C-diff（通过 Quint MBT 后端做差分 trace replay）在范围内作为务实替代；Tier C-proof 仍为非目标。
- 重新设计 Quint 验证后端。本 RFC 消费它的 trace（Tier A 和 EVM 的 Tier C-diff）；Quint 后端自身的演进在 Quint 工作流下单独跟踪。
- 证明外部工具链（`solc`、`sbpf`、`wat2wasm`、`dargo`、Mollusk）。这些按照 `docs/formal-verification.md` 保持在证明 TCB 之外。
- 在初始范围内将契约扩展到 CosmWasm、Move（Sui/Aptos）、Aleo、Cloudflare TS。这些可在四个主要后端对齐之后跟进。
- 替换现有的 AST printer 或外部工具调用。契约位于 AST 层*之上*；printer 保持原样。
- 强制每个后端在第一天就长出 EVM 形态的 `ExprPlan`/`StmtPlan` body plan。Body planning 被后置（Phase 6），且只在有价值的地方进行。

## 各后端当前状态

### EVM（参考栈）

- `ProofForge/Backend/Evm/Validate.lean` —— 类型/形状/能力检查、init code、map-presence 域、event signature 类型。
- `ProofForge/Backend/Evm/Plan.lean` —— `StorageLayout`、`EntrypointPlan`、`DispatchPlan`、`EventPlan`、crosscall/create spec、`MetadataPlan`，以及组合成 `ModulePlan` 的 body-planning `ExprPlan` / `StmtPlan`。
- `ProofForge/Backend/Evm/Lower.lean` —— `buildModulePlan`、`buildFullModulePlan`、`buildFullModulePlanWithTargetPlan`。
- `ProofForge/Backend/Evm/IR.lean` —— `buildSemanticPlan`、`lowerModuleWithPlan`、`renderSemanticPlan`（plan 检查）。
- `ProofForge/Backend/Evm/{ToYul,Metadata,ConstructorInit}.lean` —— plan → Yul AST 以及 deploy/artifact metadata。
- `ProofForge/Backend/Evm/Refinement.lean` + `YulSemantics.lean` —— 针对 IR trace 与 selector-dispatched Yul 表面以及一个可执行 Yul 子集（Counter、ValueVault、Map/TypedStorage/StorageStruct/AbiAggregate/Conditional/Loop/Event 探针）的 `TraceObligation`。

CI：`just evm-plan`（`Tests/Backend/Evm/EvmPlan.lean`）、`just evm-semantic-plan`（`Tests/Backend/Evm/EvmSemanticPlan.lean`），以及 `lake build ProofForge.Backend.Evm.Refinement`（定理从 `Tests/NearWasmFormal.lean` 以 `#check` 锚定）。

**EVM 审计（2026-07-07，RFC 0014 Tier B 参考后端）。** 在 Solana 与 NEAR 完成 Step C 之后，对 EVM 做了一次镜像审计，确认 EVM 是否存在类似的、绕过 `Evm.Plan.ModulePlan` 的内联 `Ctx` 式推导（即 Step C 双路径模式）。**结论：EVM 已经是干净的 plan-only，无需 Step C 重构。** Lowering 派发为 `lowerModule module = lowerModuleWithPlan module (buildSemanticPlan module)`（严格）与 `lowerModuleBestEffort module = lowerModuleWithPlan module (buildSemanticPlanBestEffort module)`（best-effort），两者都经由 `lowerModuleWithPlan`。EVM 根本没有 `Ctx` / `LowerCtx` 结构体——plan 被直接消费。`lowerModule` 与 `lowerModuleBestEffort` 的拆分（commit `06e57e12`）是有意的严格 vs best-effort，并非 Step C 双路径：两者都经过 plan。`lowerModuleWithPlan` 内部的 best-effort 回退（当 plan 的 entrypoint/dispatch 数组不完整时回退到 `lowerEntrypoint` / `dispatchBlock`）也是 plan 驱动的——每个回退都通过 `Lower.buildEntrypointSurfacePlan` 构建一个 `EntrypointPlan` / `DispatchPlan` 并调用对应的 `*WithPlan` 函数。不存在绕过 plan 的内联 storage / ABI / dispatch 推导。EVM 是其他后端对齐的参考实现；它从未积累 Solana（`buildCtx`）与 NEAR（内联 `Ctx` 装配）在 Step C 之前携带的内联 `Ctx` 残留。完整审计、调用点表与验证见 [`docs/multi-backend-moduleplan-design.md`](../../multi-backend-moduleplan-design.md) §14。`lake build` 绿；`just evm-plan` / `just evm-semantic-plan` / `just evm-build-examples` 通过；frozen EVM golden 未变。

### NEAR（validate 丰富、plan 匮乏、形式化强）

- `ProofForge/Backend/WasmHost/IR.lean` —— `validateModule`：capability + 标识符 + state + 逐入口 param/return/type + 返回路径检查。
- `ProofForge/Backend/WasmHost/EmitWat.lean` —— `checkTargetPlan` 以及在 render 之前对 `IR.Ownership.checkModule` 的调用。
- `ProofForge/Backend/WasmHost/Refinement.lean` —— 最丰富的形式化层：IR trace、WAT export、Wasm AST host-boundary frame、离线宿主 Borsh/hex obligation；ValueVault 不变式桥接。
- **没有** `WasmNear/Plan.lean`。Lowering 在 `validateModule` 之后于 `WasmNear/IR` 内部从 IR 直接到 Wasm AST。

### Psy（部分 EVM 镜像——仅元数据）

- `ProofForge/Backend/Psy/Plan.lean` —— `PsyModulePlan`：storage shape、context op、event、crosscall、test plan、capability。**没有** `ExprPlan`/`StmtPlan`。
- `ProofForge/Backend/Psy/IR.lean` —— `validateCapabilities`、`buildModulePlan` → `buildModuleWithPlan`。
- `ProofForge/Backend/Psy/{Metadata,MetadataJson}.lean` —— plan 驱动的 metadata。
- **没有** refinement 层；仅有差分 `dargo execute`（FV-4）。

### Solana（主要差距）

- `ProofForge/Backend/Solana/SbpfAsm.lean` —— `validateCapabilities`（target profile 检查）位于 `lowerModuleCore` 顶部；lowering 的其余部分在一个 `LowerCtx` 内构建 account schema、state offset、local、scratch、allocator。`lowerModule` 使用空的 `ProgramExtensions {}`；`lowerModuleWithPlan` 从 `CapabilityPlan` 分层叠加 CPI/account extension。
- `ProofForge/Backend/Solana/StateLayout.lean`、`Extension.lean`（含 `ProgramExtensions.fromPlan` 和 `lowerPlan : Array AstNode`）、`Manifest.lean`、`Idl.lean`、`Client.lean`、`Package.lean`、`Syscalls.lean`、`Register.lean`。
- **没有** `Solana/Plan.lean`。**没有** `Solana/Refinement.lean`。没有 `*-semantic-plan` gate；强制执行是行为级的（golden asm/manifest、Mollusk/testkit、surfpool/web3）。

### 共享基础设施

- `ProofForge/IR/Semantics.lean` —— 针对标量、固定数组、struct、storage（标量/数组/struct/path、map insert/set）、`ifElse`、`boundedFor`、event-log 的 trace 解释器；构造即确定性的定理。
- `ProofForge/IR/Ownership.lean` —— 针对释放和已拥有堆 local 的 `checkModule` / `checkEntrypoint`。**只有** NEAR/CosmWasm 的 EmitWat 路径今天调用它；EVM/Psy/Solana 不调用。
- `ProofForge/Target/Plan.lean` —— `CapabilityPlan`（targetId + 已解析的 capability call）。**不是** semantic lowering plan。
- `ProofForge/Target/{Adapter,Registry,Check}.lean` —— capability 解析、`TargetProfile`、用于仅 IR emit 的 `resolveModule`。

## 详细设计

### 目标 lowering 接口（契约，而非 typeclass）

每个主要后端暴露五个阶段。该契约是**散文 + 模块布局**，而不是一个 Lean typeclass——Lean typeclass 编码是一个明确的待定问题（见下文），且不是落地 Tier B 所必需的。

```text
resolveCapabilities : IR.Module -> Except Diagnostic CapabilityPlan
                  -- 共享：Target.Adapter.defaultResolve + requireCapabilityPlan

validateModule*    : IR.Module -> Except Diagnostic Unit
                  -- 共享子集（SharedValidate）+ 逐后端检查

buildModulePlan*   : IR.Module -> CapabilityPlan -> Except Diagnostic <Target>ModulePlan
                  -- 可检查的制品；纯函数；不构造 AST

lowerToAst         : IR.Module -> <Target>ModulePlan -> Except LowerError <Target>.AST
                  -- plan 驱动；纯函数；printer 不变

buildArtifactMetadata : <Target>ModulePlan -> ArtifactMetadata
                  -- plan 驱动；由 CLI deploy/emit 消费
```

逐后端具体如下：

| 后端 | `ModulePlan` 类型 | Plan 模块 | AST 模块 |
|---|---|---|---|
| EVM | `Evm.Plan.ModulePlan`（已存在） | `Backend/Evm/Plan.lean`、`Lower.lean` | `Compiler/Yul` |
| Psy | `Psy.Plan.PsyModulePlan`（已存在，扩展） | `Backend/Psy/Plan.lean`、`IR.lean` | `Lean.Compiler.Psy` |
| NEAR | `WasmNear.Plan.NearModulePlan`（**新增**） | `Backend/WasmHost/Plan.lean`（**新增**） | `Compiler/Wasm` |
| Solana | `Solana.Plan.SolanaModulePlan`（**新增**） | `Backend/Solana/Plan.lean`（**新增**） | `Solana/Asm.AstNode` |

### 逐后端 plan 类型草案

**EVM**：不变。`Evm.Plan.ModulePlan` 保持为参考；body plan（`ExprPlan`/`StmtPlan`）按照 `docs/implementation-backlog.md` 继续增长。

**Solana**：`SolanaModulePlan` 初始覆盖：

- `StorageAccountPlan` —— account 排序、大小、owner/signer/writable 标志，派生自 `StateLayout`。
- `EntrypointPlan` —— 8-bit discriminator、参数解码顺序、消费的 account binding。
- `InstructionDataPlan` —— 指令字节流的布局（header、discriminator、args、长度前缀）。
- `CpiPlan` —— 跨程序调用的摘要、PDA seed、account 依赖（即当前由 `Extension.lowerPlan` 临时产生的制品）。
- `SyscallPlan` —— body 将调用的 syscall 摘要（`sol_log_`、`sol_memcpy_`、`sol_invoke_signed_`、return-data），供 manifest 和 CU 估算使用。
- `ManifestPlan` —— manifest/IDL/client emitter 读取的链接字段。

Body planning（针对 Solana instruction 的 `ExprPlan`/`StmtPlan`）**推迟**到 Phase 5；Phase 2 仅 plan layout/dispatch/CPI/account schema。

**NEAR**：`NearModulePlan` 覆盖：

- `ExportPlan` —— Wasm 函数 export 以及 selector/dispatch 表面。
- `StorageKeyPlan` —— 每个 state 字段的 `storage_{read,write}` key 布局。
- `HostImportPlan` —— 从 effect 中发现的所需 NEAR 宿主导入（`storage_*`、`log`、`sha256`、`account_id`、`block_height` 等）。
- `PromisePlan`（未来）—— crosscall lowering 目标；如今 crosscall → Promise lowering 是一个已记录的 EmitWat 差距。

**Psy**：`PsyModulePlan` **稍后**（Phase 5）向 entrypoint/body plan 扩展；初始范围保留现有的仅元数据 plan，并将 `buildModulePlan` → `buildModuleWithPlan` 接缝对齐到共享契约。

### 共享 validate 子集

新模块：`ProofForge/Backend/SharedValidate.lean`（Phase 1 已落地）。

**Phase 1（已落地）—— 真正 byte-identical 的纯 helper。** 对 EVM 与 NEAR 的
validate 盘点发现，只有四个 helper 是真正重复（签名、规则、diagnostic 字符串
一致）的，已抽取：

- `SharedValidate.ensureType` —— 类型不匹配格式化
  （`{context} expected \`{expected}\`, got \`{actual}\``），原在 `Evm.Validate`、
  `Evm.IR`、`WasmNear.IR`、`Psy.IR` 中 byte-identical。
- `SharedValidate.sharedParamBindings` —— 支撑每个后端的
  `entrypointTypeEnv`。
- `SharedValidate.statementAlwaysReturns` / `statementsAlwaysReturn` ——
  控制流返回路径谓词（原本在 EVM 内部 `Validate.lean` 与 `IR.lean` 之间重复）。
- `SharedValidate.checkOwnership` —— 包装 `IR.Ownership.checkModule` 的 opt-in
  stub。未新接入任何后端；NEAR/CosmWasm 继续直接调用 `IR.Ownership.checkModule`。

EVM（`Validate.lean`、`IR.lean`）与 NEAR（`WasmNear/IR.lean`）现已委托
`SharedValidate`。diagnostic 字符串与抽取前 byte-identical（由
`Tests/SharedValidate.lean` 钉死）。

**Phase 1 发现 —— 当前不可安全抽取的内容。** 本节早先草稿将「标识符合法性、
入口返回路径检查、按 profile 不支持的类型、ownership hook」列为共享子集。实现
盘点表明这些**并非**真正跨后端重复——它们的签名、规则、消息各异：

- `validateCapabilities` —— EVM 调 `Target.resolveModule Target.evm`（返回
  `CapabilityPlan`）；NEAR 调 `requireCapabilities Target.wasmNear`（返回
  `Unit`）。签名与错误包装不同。
- **返回路径检查** —— EVM 分析每条控制流路径（`statementsAlwaysReturn`，
  消息 `"does not return on every control-flow path"`）；NEAR 用
  `bodyEndsWithReturn`（语法上检查最后一条语句，消息 `"does not end with a
  return statement"`）。规则与消息都不同——强行统一会改动 NEAR diagnostic。
- 标识符合法性 —— NEAR 专属（Rust 标识符规则）；EVM 无对应检查。
- `ensureNumericType` —— EVM 返回 `ValueType`（支持 U8）；NEAR 返回 `Unit`
  （仅 U32/U64）。不同构。

统一这些需要先引入共享 `Diagnostic` 类型并对齐跨后端返回路径语义。该重构归为
**Phase 2+ 前置项**（见 Open questions），不属于 Phase 1。Phase 1 按现状抽取
真正的重复，其余保留在各后端——这是 diagnostic 稳定性约束下的保守结果。

Solana 的 `validateCapabilities` 在 Phase 2 保留，并在适用处用共享 helper
增强；它不替代 capability 检查。

### Smoke gate 模式

在每个对齐的后端上镜像 EVM 的双 gate：

```text
just <target>-plan            -- layout/dispatch/metadata plan smoke
just <target>-semantic-plan   -- 更深：entrypoint、event、body plan（如适用）
```

外加一个统一的对比入口：

```text
just semantic-plan-matrix     -- 运行 evm + psy + near + solana 的 semantic-plan gate
```

Golden plan 快照（Phase 7 stretch）会将 plan 序列化为 JSON 供人工 review；这是一个待定问题，而非 Phase 1–5 的要求。

## 分阶段实施

每个阶段都可独立交付且可干净回退。Phase 0–4 属于 Tier B；Phase 5 开启 Tier C 接缝但不交付完整证明。

### Phase 0 —— Lowering 接口文档（4–6 周）

**里程碑：**

- 发布 `docs/target-lowering-interface.md`：所需阶段、逐目标不变式（Solana：account-layout ↔ manifest ↔ asm 一致性；EVM：plan.metadata ↔ `Metadata.lean`；NEAR：storage-key plan ↔ WAT export；Psy：plan ↔ `MetadataJson`）。
- 在 `ProofForge/Backend/Lowering.lean` 中添加一个 `LoweringStage` inductive 桩（仅设计；无行为）。

**改动清单：** `docs/`、`docs/rfcs/0014-…`（本 RFC）、可选的 `ProofForge/Backend/Lowering.lean` 桩。

**新 recipe：** 无（仅文档）。

**风险：** 过度规约单一 `ModulePlan` 类型——已明确避免。

**范围裁剪：** Lean typeclass 编码（待定问题）。

### Phase 1 —— 共享 validate 子集（2026-07-06 已落地）

**状态：** 已落地。Build 通过，测试通过，diagnostic byte-identical。

**已抽取的内容（真正重复的纯 helper）：**

- `ProofForge/Backend/SharedValidate.lean`（新）—— `ensureType`、
  `sharedParamBindings`、`statementAlwaysReturns`/`statementsAlwaysReturn`，
  以及 `checkOwnership` opt-in stub。
- EVM `Validate.lean` + `IR.lean` 与 NEAR `WasmNear/IR.lean` 委托
  `SharedValidate` 处理这四个 helper。
- `Tests/SharedValidate.lean`（12 例）钉死行为与 `ensureType` 的精确
  diagnostic。
- `justfile`：`shared-validate-smoke` recipe 加入 `check`。

**未抽取的内容（各后端签名/规则/消息不同）：**

- `validateCapabilities`、返回路径检查、标识符合法性、`ensureNumericType`
  —— 详见上文「共享 validate 子集」对每项为何不可安全抽取的完整盘点。

**Diagnostic 稳定性：** 不变。`Tests/SharedValidate.lean` 的
`testEnsureTypeMismatchMessage` 钉死 `"probe expected \`U64\`, got \`U32\`"`。
无需更新任何 golden diagnostic 测试。

**延后至 Phase 2+ 前置项：** 引入共享 `Diagnostic` 类型并对齐跨后端返回路径
语义，使 `validateCapabilities` 与返回路径检查可在不改动 NEAR diagnostic 的
前提下统一。已登记为 Open question；它不是 Phase 2（SolanaModulePlan）的工作，
也不阻塞 Phase 2。

### Phase 2 —— `SolanaModulePlan` + semantic-plan smoke（10–16 周）

**里程碑：**

- 添加 `ProofForge/Backend/Solana/Plan.lean`，含 `SolanaModulePlan` 及上述子 plan。
- 重构 `SbpfAsm.lowerModuleCore`，使 `LowerCtx` **从 plan 派生**，而非内联构建。为 `CapabilityPlan` extension 保留 `lowerModuleWithPlan`。
- 添加 `Tests/Backend/Solana/SolanaSemanticPlan.lean` 和 `just solana-semantic-plan`，镜像 `evm-plan`（layout + entrypoint + manifest + CPI/account schema 一致性）。
- Step C（切换默认）—— **已落地（2026-07-07）。** plan-driven 路径现在是唯一的
  lowering 路径。原先位于 `SbpfAsm.lowerModuleCore` 旁的内联 `buildCtx`（通过
  `buildStateOffsetsAtBase` 派生 `stateFieldOffsets` 并逐字段装配 `LowerCtx`）已
  删除；`lowerModuleCore` 现在通过 `SbpfAsm.buildLowerCtx` →
  `SbpfAsm.LowerCtx.fromPlanSeed` 派生其 `LowerCtx`（由拥有 `LowerCtx` 类型的
  `SbpfAsm` 拥有；`Solana.Plan.LowerCtx.fromSeed` 委托给它，保持 import 图单向）。
  共享的 `lowerModuleCoreWithSeed` 体不变。Phase 2 落地的双路径 parity 检查退役
  （已无第二条路径可对齐）；`Tests/Backend/Solana/SolanaModulePlan.lean` 现为单路径回归 gate
  （plan golden diff + `--render` 确认 plan-driven lowering 仍能发出 sBPF 汇编，
  字符数出现在 CI 日志中）。`scripts/solana/plan-smoke.sh` 切换为 `--render`。
  所有 `SbpfAsm.lowerModule`/`renderModule`/`lowerModuleWithPlan` 调用点
  （Cli.lean、九个 `Tests/Backend/Solana/Solana*.lean` 发射测试、`Package.renderPackageWithPlan`）
  现在自动经由 plan 派生的 `LowerCtx` 进行 lowering。验证：`lake build` green；
  `just solana-plan-smoke` 通过（4/4）；`just solana-build-examples` 通过
  （`Counter.s` 匹配冻结 golden）；`just solana-lean` 与 `just solana-emit-control`
  通过；冻结的 `.s` golden（`Counter.golden.s`、`ValueVault.golden.s`）及所有
  `plan.txt` golden 不变。Render 字符数：Counter 3830、EvmStorageArrayProbe 6609、
  EvmMapProbe 4470、EvmStorageStructProbe 2707，确认字节稳定。

  **EVM 审计（2026-07-07，Solana + NEAR Step C 之后）。** 对 EVM（参考 Tier B 后端）的镜像审计确认 EVM 已经是干净的 plan-only，无需 Step C 重构：`lowerModule` 委托给 `lowerModuleWithPlan module (buildSemanticPlan module)`，EVM 没有 `Ctx` / `LowerCtx` 结构体，且严格/best-effort 拆分两侧都经由 plan。EVM 是 Solana 与 NEAR 对齐的参考实现；它从未携带内联 `Ctx` 残留。完整结论见 [`docs/multi-backend-moduleplan-design.md`](../../multi-backend-moduleplan-design.md) §14。

**改动清单：**

- `ProofForge/Backend/Solana/Plan.lean`（新增）
- `ProofForge/Backend/Solana/SbpfAsm.lean`、`StateLayout.lean`、`Manifest.lean`、`Idl.lean`、`Package.lean`
- `justfile`、`.github/workflows/ci.yml`（加入 `solana-lean` 族或 `check`）

**风险：** `SbpfAsm.lean` 约 1.7k LOC，且喂给 golden asm + Pinocchio reference-equivalence gate；重构必须保持它们字节稳定。建议在 feature flag（如 `--solana-plan=v2`）后落地，并在证明 golden parity 后切换。

**范围裁剪：** body planning（Solana 的 `ExprPlan`/`StmtPlan`）→ Phase 6。

### Phase 3 —— 共享 diagnostic 契约（前置项，2026-07-07 落地）

**状态：** 桩于 2026-07-07 落地；后续 A（逐后端实例）与 B（`SharedValidate`
迁移）于 2026-07-07 落地。Build green，smoke green，未改动任何现有 diagnostic
字节。

**动机：** Phase 1 发现 `validateCapabilities`、返回路径检查、标识符合法性、
`ensureNumericType` 不可安全统一，因为每个后端的错误类型、规则和消息都不同。共享
diagnostic 词汇是将共享 validate 面扩展到 Phase 1 四个纯 helper 之外的前置项。本阶段
引入它，但不迁移任何后端。

**已落地内容（最小、安全的桩）：**

- `ProofForge/Backend/Diagnostic.lean`（新增）——`LoweringDiagnostic`
  （`message` + 可选的 `backend?` / `severity` / `code?` 元数据）、`Severity`、
  `LoweringError` typeclass 契约、两个 trivial adapter（`LoweringDiagnostic` 恒等、
  `String`，对应 `SharedValidate` 当前使用的 `Except String` 形状）、
  `fromTargetDiagnostic` 与 `liftSharedError`。
- `Tests/Diagnostic.lean`（新增，9 例）钉死字节稳定性不变式：
  `LoweringDiagnostic.render` **只**输出 `message`，因此任何委托给它的后端看到的
  输出与现有 `<Name>.render := err.message` 字节一致。
- `justfile`：`diagnostic-smoke` recipe 加入 `check`。

**设计决策（共享类型 + typeclass，非仅 typeclass）：** 字段级审计（见
[`docs/shared-diagnostic-design.md`](../../shared-diagnostic-design.md)）表明每个后端的
lowering/plan/emit 错误类型*已经是*同一形状——单字段
`structure <Name> where message : String`，其 `render` 为 `err.message`。因此共享具体
类型是合理的，而非过早抽象：仅 typeclass 契约会让 `SharedValidate` 继续返回
`Except String`（Phase 1 现状），而那正是本阶段要超越的。可选元数据字段不参与
`render`，故不会扰动 golden diagnostic。

**未做的事（明确的后续项，已登记）：**

- **逐后端 `LoweringError` 实例——已于 2026-07-07 落地（后续 A）。** 三个
  Tier-B 完成的后端（EVM、Solana、NEAR）现已在审计表中列出的全部 8 个具体错误类型
  上携带 trivial `LoweringError` adapter 实例
  （`Evm.Validate.LowerError`、`Evm.IR.LowerError`、`Evm.Plan.PlanError`、
  `Solana.SbpfAsm.LowerError`、`Solana.Plan.PlanError`、`WasmNear.IR.LowerError`、
  `WasmNear.Plan.PlanError`、`WasmNear.EmitWat.EmitError`）。每个实例为
  `toDiagnostic := fun e => { message := e.message, backend? := some "<backend>" }`，
  并依赖 class 默认 `render`。`Tests/Diagnostic.lean` 从 9 例扩展到 17 例，断言
  `LoweringError.toDiagnostic err |>.render` 等于各后端自身的 `<Name>.render err`
  与裸 `message`。其余后端（Psy、CosmWasm、Aleo、Move、Quint）在其 Tier-B 工作落地时
  按同一 trivial 模式补齐。
- **将 `SharedValidate` helper 迁移到返回 `Except LoweringDiagnostic α`
  ——已于 2026-07-07 落地（后续 B）。** `SharedError` 现为 `LoweringDiagnostic` 的
  alias。`ensureType` 与 `checkOwnership` 构造 `{ message := ... }` 而非返回裸
  `String`；消息*文本*字节一致。调用方（`Evm/Validate.lean`、`Evm/IR.lean`、
  `WasmNear/IR.lean`）从 `.error message => .error { message := message }` 改为
  `.error diag => .error { message := diag.message }`。`Tests/SharedValidate.lean`
  适配为在 `Except LoweringDiagnostic` 上模式匹配并检查 `diag.message`；全部 12 例
  通过，包括仍钉死精确字节的 `testEnsureTypeMismatchMessage`。
- **统一 `validateCapabilities` / 返回路径检查 / 标识符合法性 / `ensureNumericType`。**
  共享 `Diagnostic` 类型是*前置项*，不是充分条件——逐后端规则和消息也必须先对齐。
  推迟到后续阶段。

**Diagnostic 稳定性：** 不变。`Tests/Diagnostic.lean` 钉死
`LoweringDiagnostic.render` 只输出裸 `message`。未触碰任何后端的具体 `render`；无需
更新任何 golden diagnostic 测试。

**改动清单（桩）：**

- `ProofForge/Backend/Diagnostic.lean`（新增）
- `Tests/Diagnostic.lean`（新增）
- `justfile`（`diagnostic-smoke`，加入 `check`）
- `docs/shared-diagnostic-design.md`（新增——字段级审计 + 设计）
- `docs/rfcs/0014-…`（本 RFC）、`docs/zh/rfcs/0014-…`（翻译同步）

**改动清单（后续 A + B，2026-07-07 落地）：**

- `ProofForge/Backend/Evm/{Plan,Validate,IR}.lean`——在 `PlanError` /
  `LowerError`（×2）上添加 `LoweringError` 实例；`Evm.Validate` / `Evm.IR` 的
  `ensureType` wrapper 改为折叠 `diag.message`。
- `ProofForge/Backend/Solana/{SbpfAsm,Plan}.lean`——在 `LowerError` /
  `PlanError` 上添加 `LoweringError` 实例。
- `ProofForge/Backend/WasmHost/{IR,Plan,EmitWat}.lean`——在 `LowerError` /
  `PlanError` / `EmitError` 上添加 `LoweringError` 实例；`WasmNear.IR` 的
  `ensureType` wrapper 改为折叠 `diag.message`。
- `ProofForge/Backend/SharedValidate.lean`——`SharedError` alias 重定向到
  `LoweringDiagnostic`；`ensureType` / `checkOwnership` 构造 `{ message := ... }`；
  模块文档补充 Phase 3 迁移说明。
- `Tests/Diagnostic.lean`——从 9 例扩展到 17 例（逐后端实例检查）。
- `Tests/SharedValidate.lean`——harness 适配到 `Except LoweringDiagnostic`；
  消息字节不变。
- `docs/shared-diagnostic-design.md`、`docs/rfcs/0014-…`、
  `docs/zh/rfcs/0014-…`——后续 A & B 标记为已落地。

**风险：** 桩无风险（纯增量，无后端签名变更）。后续 A & B 若 adapter 或
`SharedValidate` 迁移意外改变 `s!"..."` 插值会导致 golden 漂移；通过扩展后的
`Tests/Diagnostic.lean`（实例级字节钉死）与 `testEnsureTypeMismatchMessage`
（共享 helper 字节钉死），以及各后端的 plan/diagnostic golden 套件缓解。实践中无
golden 字节移动（EVM/Solana/NEAR plan smoke 与 shared-validate smoke 全部通过）。

**范围裁剪：** 将后端迁移到 `LoweringDiagnostic` 作为公开错误类型（即完全替换具体
`LowerError` 类型）；统一逐后端验证规则。两者仍为后续项。

### Phase 4 —— NEAR plan 层（8–12 周）

**审计发现（2026-07-07）。** 对三个候选后端（NEAR、Psy、Move-Sui）的审计纠正了
早先"无 `WasmNear/Plan.lean`"的说法：`WasmNear.Plan.lean` 已存在并定义了
`ModulePlan` + `buildModulePlan` + `ModuleSurface`，且 `EmitWat.lowerModule` 已消费它
来驱动 host imports 与 helper-function 裁剪（由 `Tests/Backend/Wasm/WasmNearPlan.lean` /
`just wasm-near-plan` 把关）。剩余差距比 Solana 当年更窄：数据布局 `Ctx`
（scalar key 指针、map prefix 指针、string pool、panic pool、crosscall string pool）
仍在 `EmitWat.lowerModule` 顶部内联构建，而非由 plan 派生。完整审计、逐后端可行性
表、字段级设计与迁移路径见
[`docs/multi-backend-moduleplan-design.md`](../../multi-backend-moduleplan-design.md)。

**选定的首个候选：NEAR。** 整个 `Ctx` 都是 plan-可派生的（没有 lowering-local 的可变
状态需要拆分，不像 Solana 的 `locals`/`nextLabel`/`allocator`），因此迁移规模比
Phase 2 更小。Psy 与 Move-Sui 推迟：Psy 的 `PsyModulePlan` 已被消费且为 metadata-only
（在引入 body planning 之前收益低，这是 Phase 6 的产品决策），Move-Sui 是 Counter MVP
spike、没有真正的 lowering（`SuiModulePlan` 需要先于真正的 Move lowering 构建，而非
反之）。

**里程碑：**

- Step A（仅类型，增量）—— **已落地（commit 61cfa7a9）。** 添加了
  `ProofForge/Backend/WasmHost/NearModulePlan.lean`，包含 `NearModulePlan`、
  `NearLayoutPlan`、`NearLowerCtxSeed`，以及一个针对
  `ProofForge.IR.Examples.Counter.module` 的 `buildNearModulePlan`。不接入 EmitWat。
  添加了 `Tests/NearModulePlan.lean`、`Examples/Backend/WasmNear/Counter/golden/plan.txt`、
  `just near-plan-smoke`（镜像 `solana-plan-smoke`）。
- Step B（plan 构建 + `Ctx.fromSeed`，增量）—— **已落地（2026-07-07）。**
  实现了 `Ctx.fromPlanSeed`（从 plan 的 seed + layout 重建 `EmitWat.Ctx`；整个
  `Ctx` 都是 plan 派生的，因为 NEAR 没有 lowering-local 可变状态，不同于 Solana 的
  `locals`/`nextLabel`/`allocator`），以及 `lowerModuleFromPlan`（将重建的 `Ctx`
  交给从内联路径抽出的共享 `EmitWat.lowerModuleCoreWithCtx` 体，镜像 Solana 的
  `lowerModuleCoreWithSeed`）。`EmitWat.lowerModule` 中的内联 `Ctx` 构建保留
  （双路径），直到 Step C。`near-plan-smoke` gate 现在还运行双路径 parity 检查：
  对 `Counter`，plan 驱动 WAT 与内联 WAT 必须字节一致（断言为 `MATCH N chars`）。
  结果：`Counter: MATCH 2228 chars`。`lake build`、`just wasm-near-plan` 及冻结的
  `Counter.golden.wat` 均不受影响。
- Step B.2（将 parity 覆盖扩展到非标量状态形状）—— **已落地（2026-07-07）。**
  扩展 `Tests/NearModulePlan.lean`，添加 `moduleFor` 解析器与三个子模块 fixture，
  镜像 Solana Phase 2 的 array/map/struct 探针：`EvmMapProbe`（map 状态，u64 键
  `balances`）、`EvmStorageArrayProbe`（array 状态，`values` 长度 3）、
  `EvmStorageStructProbe`（struct 状态，`current : Point`）。每个子模块只使用
  NEAR 后端已支持的 lowering 路径。`scripts/near/plan-smoke.sh` 现在遍历全部四个
  fixture（Counter + 三个新增），生成并 diff 每个 plan golden 并逐个运行 parity
  检查。在 `Examples/Backend/WasmNear/<Fixture>/golden/` 下添加新的 golden `plan.txt`。
  Parity 结果（plan 驱动 WAT == 内联 WAT，字节一致）：`Counter: MATCH 2228 chars`、
  `EvmMapProbe: MATCH 3498 chars`、`EvmStorageArrayProbe: MATCH 4703 chars`、
  `EvmStorageStructProbe: MATCH 3375 chars`。覆盖现已横跨标量 / map / array /
  struct 状态形状；内联 `Ctx` 构建仍保留（双路径）直到 Step C，此时已有广泛覆盖
  证据可依赖。
- Step C（切换默认）—— **已落地（2026-07-07）。** plan-driven 路径现在是唯一的
  lowering 路径。`EmitWat.lowerModule` 顶部的内联 ad-hoc `Ctx` 装配已删除；
  `lowerModule` 现在通过 `EmitWat.buildLowerCtx` → `EmitWat.Ctx.fromPlanSeed`
  派生其 `Ctx`（由拥有 `Ctx` 类型的 `EmitWat` 拥有；`NearModulePlan.Ctx.fromPlanSeed`
  委托给它，保持 import 图单向）。共享的 `lowerModuleCoreWithCtx` 体不变。
  `NearModulePlan.lowerModuleFromPlan` 现在运行与 lowering 入口相同的
  `EmitWat.validateScratchCapacities` gate，弥补了 Step B 的一个缺口。双路径
  parity 检查已退役（没有第二条路径需要一致）；`Tests/NearModulePlan.lean`
  现在是单路径回归 gate（plan golden diff + `--render` 确认 plan-driven lowering
  仍能发出 WAT，字符数在 CI 日志中可见）。`WasmNear/Refinement.lean` 通过其
  现有的 `EmitWat.lowerModule` 调用点（现已 plan-driven）自动读取 plan-driven
  输出；无需修改 `Refinement.lean` 代码。验证：`lake build` 通过；`just
  near-plan-smoke` 通过（4/4）；`just wasm-near-plan` 通过；冻结的 WAT golden
  和所有 `plan.txt` golden 不变；render 字符数与 Step B.2 parity 结果完全一致
  （Counter 2228、EvmMapProbe 3498、EvmStorageArrayProbe 4703、
  EvmStorageStructProbe 3375），确认字节稳定。

**改动清单：**

- Step A：`ProofForge/Backend/WasmHost/NearModulePlan.lean`（新增）、
  `Tests/NearModulePlan.lean`（新增）、`Examples/Backend/WasmNear/Counter/golden/plan.txt`
  （新增）、`scripts/near/plan-smoke.sh`（新增）、`justfile`。
- Step B：`ProofForge/Backend/WasmHost/NearModulePlan.lean`（`Ctx.fromPlanSeed`、
  `lowerModuleFromPlan`、`renderModuleFromPlan`；`NearStatePlan`/`NearMapPlan` 现在
  携带 `ValueType`，使 seed 能重建 `StateInfo`/`MapInfo`）、
  `ProofForge/Backend/WasmHost/EmitWat.lean`（从 `lowerModule` 抽出
  `lowerModuleCoreWithCtx` 以打破 import 环）、`Tests/NearModulePlan.lean`（双路径
  parity 检查）、`scripts/near/plan-smoke.sh`（`--parity`）、`justfile`。
- Step B.2：`Tests/NearModulePlan.lean`（`moduleFor` + `mapSubModule` /
  `arraySubModule` / `structSubModule`）、`scripts/near/plan-smoke.sh`
  （多 fixture 循环）、`Examples/Backend/WasmNear/{EvmMapProbe,EvmStorageArrayProbe,
  EvmStorageStructProbe}/golden/plan.txt`（新 golden）。
- Step C：`ProofForge/Backend/WasmHost/EmitWat.lean`（新增 `Ctx.fromPlanSeed` +
  `buildLowerCtx`；删除 `lowerModule` 中的内联 `Ctx` 装配，改为通过 `buildLowerCtx`
  → `Ctx.fromPlanSeed` 路由）、`ProofForge/Backend/WasmHost/NearModulePlan.lean`
  （`Ctx.fromPlanSeed` 委托给 `EmitWat.Ctx.fromPlanSeed`；`lowerModuleFromPlan`
  运行 `validateScratchCapacities`）、`Tests/NearModulePlan.lean`（双路径 parity
  检查转为单路径 `--render` 回归 gate）、`scripts/near/plan-smoke.sh`
  （`--parity` → `--render`）。`ProofForge/Backend/WasmHost/Refinement.lean` 不变
  —— 其 `EmitWat.lowerModule` 调用点现在自动通过 plan-driven `Ctx` 降级。

**风险：** WAT golden 变更；离线宿主 smoke 必须保持字节稳定。与 Phase 2 相同的
feature-flag 策略（CI 中同时跑两条路径，parity 稳定后切换默认）。

**范围裁剪：** Lean 中的完整 Wasm 指令语义（Tier C-proof，推迟）；Rust sourcegen 路径
（`WasmNear/IR.lean`）不在范围内（一条无 `Ctx` 的平行 lowering）；`ExportPlan`
（每个 entrypoint 一条）推迟到 Phase 4.2。

**推迟的后端：**

- **Psy** —— `PsyModulePlan` 已存在并被 `Psy/IR.lean` 经 `BuildContext` 消费；
  没有 `LowerCtx` 需要拆分。把 plan 扩展到 entrypoint/body 形状（`ExprPlan`/`StmtPlan`）
  是 Phase 6 的产品决策，不是 Phase 4 的重构。
- **Move-Sui** —— 一个 Counter MVP spike，没有真正的 lowering。`SuiModulePlan`
  需要先于真正的 Move lowering 构建（struct/entrypoint/state/capability plan），
  这是 Phase 6+ 的研究项，不是 Phase 4。

### Phase 5 —— Refinement 接缝（持续）

Phase 5 在 Quint 验证后端作为 Tier C-diff 载体存在后，自然地拆成两条路径。

**路径 5a —— Tier C-diff 跨后端推广（工程性）。**

完整的逐后端可行性审计、抽象 replay 接口（从 `EvmReplay` 泛化）、所选下一个候选（NEAR）的字段级设计，以及延迟后端的理由，见
[`docs/quint-cdiff-multi-backend-design.md`](../../quint-cdiff-multi-backend-design.md)。摘要：

- **当前覆盖（2026-07-07 审计）：** 仅 EVM（`EvmReplay.lean`、`just quint-evm-backend-replay-gate`）。replay 接口是一个纯 Lean 的 trace → harness 渲染器（`renderFoundryTest`），把 ITF trace 降级为 Solidity/Foundry 测试；目标工具链（`forge`）执行它。链中立的 trace 解释（`resolveActionName`、`buildArgs`、`entrypointMap`、`buildInitialState`、`compareStates`、`itfValueToIr`）位于 `Replay.lean`，每个 shim 都复用它。
- **所选下一个候选：NEAR。** `runtime/offline-host`（wasmtime）在树内、无需外部 RPC，其 CLI 是一个扁平参数列表（`run <wat> <exports...> --inputs-hex <...>`）。`NearReplay.lean` shim 从同一份 ITF trace 渲染该参数列表；offline-host 执行它。这比 EVM 更简单（EVM 渲染一整个 Solidity 测试文件）。本步落地的最小类型-only stub（`ProofForge/Backend/Quint/NearReplay.lean` + `Tests/Quint/NearReplaySmoke.lean` + `just quint-near-replay-smoke`）**不**接线进 CI。Step B（完整 `renderOfflineHostArgs`、spawn `quint` + offline-host 的包装测试、gate 脚本、`just quint-near-backend-replay-gate`）是后续工作。
- **推荐顺序：** EVM（已完成）→ NEAR（stub 已落地）→ Solana（stub 已落地；Mollusk 作为 Rust crate 在树内，`SolanaModulePlan` 暴露 discriminator/account schema；shim 渲染 Rust Mollusk 测试文件）→ Psy（第 3，受限于 `dargo` 此处未安装）→ Move-Sui / Aleo / Cloudflare（延迟，研究性 spike，无真实 lowering）。
- **多模块渲染（2026-07-07）：** 三个 C-diff shim 不再仅限 Counter。`EvmReplay` 将 mutating/read/init 步骤渲染泛化为可编码 entrypoint ABI 参数（Counter 路径字节一致；ValueVault 现可渲染）。`NearReplay` 的 `init` 分支泛化为查找模块的 `initialize` entrypoint 并从 ITF nondet picks 编码其参数（原先硬编码 `("initialize", "")` 丢弃参数；Counter 路径字节一致），其 smoke 现覆盖 ValueVault。`SolanaReplay` 将账户列表与状态布局经由 `SolanaModulePlan`（Tier B）驱动，而非硬编码 Counter 账户，其 smoke 覆盖 ValueVault（多标量）与 `EvmMapProbe` map 子模块（非标量状态，v1 降级为跳过字节级 account-data 断言）。这些 smoke 是纯字符串渲染检查，**不**接线进 `just check`。详见 `docs/quint-cdiff-multi-backend-design.md` §15。
- 在每个后端于 Phase 2/4 落地 `*ModulePlan` 后，镜像现有的
  `just quint-evm-backend-replay-gate` 模式：
  - Solana：`just quint-solana-backend-replay-gate`——Quint MBT ITF trace →
    对发出的 `.so` 做 Mollusk 调用（Tier C-diff；避免需要 Lean sBPF 语义）。
  - NEAR：`just quint-near-backend-replay-gate`——trace → offline-host
    wasmtime stub（`scripts/near/emitwat-ci-smoke.sh` 已在用）。
  - Psy：`just quint-psy-backend-replay-gate`——trace → `dargo execute`。
- 每个 gate 消费同一份 `IR.Semantics` 派生的 trace；只有 replay harness 逐后端
  不同。`*ModulePlan` 正是让发出的制品足够稳定、可做 trace 级差分测试的关键。

**路径 5b —— Tier C-proof 可行性评估（2026-07-07 完成）。**

完整的可行性评估已完成，记录于 [`docs/tier-c-proof-feasibility.md`](../../tier-c-proof-feasibility.md)。结论摘要：

- **现状并非机器检查 refinement。** `Evm.Refinement.lean` 与 `ValueVaultInvariant.lean` 以 `native_decide` 对*固定*场景（Counter、ValueVault 等）做可执行 trace 等价检查，不是全称量化的 simulation 证明。`ValueVaultInvariant.lean` 只对*default* inputs 检查会计不变式，而非对所有 `ScenarioInputs`。
- **目标语义。** 首选 Lean 4 EVM 形式化模型现在是 [`powdr-labs/evm-semantics`](https://github.com/powdr-labs/evm-semantics)：它锁定 Lean `v4.31.0` + `mathlib @ v4.31.0`，并提供关系式 EVM 字节码语义（`Step` / `Eval`）以及可执行影子 `stepF`。它是独立语义，不是 refinement 框架——simulation obligation 由 ProofForge 承担。`EVMYulLean` 仍是有用的 sibling/reference，但它的 v4.22 工具链 pin 使其当前不适合作为 ProofForge 的主依赖。
- **最大阻塞（IR 侧）。** `IR.Semantics` 是解释器（`runEntrypointWithArgs`），不是小步 `step : State → Option State` 关系。simulation 证明需要显式 step 关系 + 归纳原理。这是首要前置项，且无需新依赖。
- **第二阻塞（目标侧）。** 树内 `Evm.YulSemantics` 是*伪* Yul 语义（伪 keccak、简化存储），未做 conformance 测试。真正的 Tier C-proof 需要 `powdr-labs/evm-semantics` 的字节码 `Step` 关系和可执行 `stepF`，即添加一个拉入 mathlib 的 opt-in `lake` 依赖。
- **存储布局桥接。** IR 扁平 `State` 与 EVM 256 位 storage slot 的映射当前只在 lowering 中隐式编码；`Evm.Plan.ModulePlan` 存储布局是让它显式化的正确位置（Tier B 工作的副收益）。

**分阶段路线图（取代之前的"研究接缝"草案）：**

- **Phase 6a —— 把 `Evm.Refinement` 收紧为真正的 simulation（内部，无新依赖）。**
  引入 `ProofForge/IR/StepSemantics.lean`，定义小步 `step` 关系；把 `irTraceOk` 重述为归纳谓词 `IRTraceMatches`；用归纳法证明 soundness（而非 `native_decide`）。保留现有 `native_decide` 定理作为回归 smoke。交付物：首批全称量化 IR 侧 trace 引理。
  **状态（2026-07-07 落地）：** `ProofForge/IR/StepSemantics.lean` 定义了通用归纳谓词 `IRTraceMatches`（按 call list 结构归纳，两个构造器 `nil`/`cons`），通用 runner `runTraceListGen`，以及 `runTraceListGen_sound`——用 `induction calls generalizing s` 完成证明（而非 `native_decide`），这是 Tier C-proof 链中首个全称量化 IR 侧 trace 引理。`IRTraceMatches` 上的 `Decidable` 实例（通过 iff 桥到 `runTraceListGen`）使 `native_decide` 能在固定场景上重证。设计选择 (b)：按 call list 大步归纳（保留现有大步解释器 `runEntrypointWithArgs` 作为原子步；小步 `step` 关系推迟到 6b+）。`Evm.Refinement.lean` 新增 `counter_ir_trace_matches_inductive` 与 `value_vault_ir_trace_matches_inductive`，保留现有 `counter_ir_observable_trace_ok` / `value_vault_ir_observable_trace_ok` 作为回归 smoke。`Tests/IRStepSemantics.lean` 与 `just ir-step-semantics-smoke`（接线进 `just check`）锚定该层。详见 [`docs/tier-c-proof-feasibility.md`](../../tier-c-proof-feasibility.md) 的 Phase 6a「已落地」说明。
  **状态（2026-07-07）：已落地。** `ProofForge/IR/StepSemantics.lean` 定义了通用归纳谓词 `IRTraceMatches`（对 call list 结构归纳，两个构造子 `nil`/`cons`），通用执行器 `runTraceListGen`，以及 `runTraceListGen_sound`——用 `induction calls generalizing s`（非 `native_decide`）消解，是 Tier C-proof 链中首个全称量化 IR 侧 trace 引理（对所有状态 `s` 与所有 call list，执行器与归纳谓词在 `.ok` 上一致，`.error` 为 `True`）。另有 completeness 引理与 iff 桥。`IRTraceMatches` 上的 `Decidable` 实例计算 `runTraceListGen` 并比较 observable 数组，使 `native_decide` 能把固定场景定理重证为 `IRTraceMatches` 实例而不改变真值。设计选择 (b)：对 call list 做大步归纳（保留现有大步解释器 `runEntrypointWithArgs` 作为原子步；小步 `step` 关系推迟到 6b+）。`Evm.Refinement.lean` 新增 `counter_ir_trace_matches_inductive` 与 `value_vault_ir_trace_matches_inductive`，保留现有 `counter_ir_observable_trace_ok`/`value_vault_ir_observable_trace_ok` 作为回归 smoke。`Tests/IRStepSemantics.lean` + `just ir-step-semantics-smoke`（接线进 `just check`）锚定该层。详见 `docs/tier-c-proof-feasibility.md` 的 Phase 6a "已落地"段落。
  **状态（2026-07-07）：已落地。** `ProofForge/IR/StepSemantics.lean` 定义泛型归纳谓词 `IRTraceMatches`（对 call list 结构归纳），泛型 runner `runTraceListGen`，以及用 `induction calls generalizing s` 证明的 `runTraceListGen_sound`（非 `native_decide`）——这是首条全称量化 IR 侧 trace 引理。`IRTraceMatches` 上的 `Decidable` instance（通过 iff 桥到 `runTraceListGen`）让 `native_decide` 可重新证明固定场景定理。设计选择 (b)：对 call list 做大步归纳（保留现有大步解释器 `runEntrypointWithArgs` 作为原子步；小步 `step` 关系推迟到 6b+）。`Evm.Refinement.lean` 新增 `counter_ir_trace_matches_inductive` 与 `value_vault_ir_trace_matches_inductive`，保留现有 `counter_ir_observable_trace_ok` / `value_vault_ir_observable_trace_ok` 作为回归 smoke。`Tests/IRStepSemantics.lean` + `just ir-step-semantics-smoke`（已接线进 `just check`）锚定该层。见 [`docs/tier-c-proof-feasibility.md`](../../tier-c-proof-feasibility.md) Phase 6a"已落地"段落。
  **状态（2026-07-07）：已落地。** `ProofForge/IR/StepSemantics.lean` 定义通用归纳谓词 `IRTraceMatches`（按 call list 结构递归）、通用 runner `runTraceListGen`，以及用 `induction calls generalizing s`（非 `native_decide`）证明的 `runTraceListGen_sound` —— 首个全称量化 IR 侧 trace 引理。`IRTraceMatches` 上的 `Decidable` instance（经 iff 桥到 `runTraceListGen`）使 `native_decide` 可在固定场景上重证。设计选择 (b)：按 call list 大步归纳（保留现有大步解释器 `runEntrypointWithArgs` 作为原子步；小步 `step` 关系推迟到 6b+）。`Evm.Refinement.lean` 新增 `counter_ir_trace_matches_inductive` 与 `value_vault_ir_trace_matches_inductive`，保留现有 `counter_ir_observable_trace_ok` / `value_vault_ir_observable_trace_ok` 作为回归 smoke。`Tests/IRStepSemantics.lean` + `just ir-step-semantics-smoke`（接线进 `just check`）锚定该层。见 `docs/tier-c-proof-feasibility.md` Phase 6a "已落地"小节。
  **状态（2026-07-07）：已落地。** `ProofForge/IR/StepSemantics.lean` 定义了通用归纳谓词 `IRTraceMatches`（按 call list 结构归纳），通用 runner `runTraceListGen`，以及 `runTraceListGen_sound`——以 `induction calls generalizing s` 证成（不是 `native_decide`），这是 Tier C-proof 链中首个全称量化 IR 侧 trace 引理。`IRTraceMatches` 上的 `Decidable` 实例（经 iff 桥接 `runTraceListGen`）让 `native_decide` 可重证固定场景定理。设计选择 (b)：按 call list 做大步归纳（保留现有大步解释器 `runEntrypointWithArgs` 作为原子 step；小步 `step` 关系推迟到 6b+）。`Evm.Refinement.lean` 新增 `counter_ir_trace_matches_inductive` 与 `value_vault_ir_trace_matches_inductive`，保留现有 `counter_ir_observable_trace_ok` / `value_vault_ir_observable_trace_ok` 作为回归 smoke。`Tests/IRStepSemantics.lean` + `just ir-step-semantics-smoke`（已接线进 `just check`）锚定此层。详见 [`docs/tier-c-proof-feasibility.md`](../../tier-c-proof-feasibility.md) 的 Phase 6a "已落地"小节。
  **状态（2026-07-07）：已落地。** `ProofForge/IR/StepSemantics.lean` 定义泛化归纳谓词 `IRTraceMatches`（按 call list 结构递归）、泛化 runner `runTraceListGen`，并以 `induction calls generalizing s`（而非 `native_decide`）证明 `runTraceListGen_sound`——首个全称量化 IR 侧 trace 引理。`IRTraceMatches` 上的 `Decidable` 实例（经与 `runTraceListGen` 的 iff 桥接）让 `native_decide` 重证固定场景定理。设计选择 (b)：在 call list 上做 big-step 归纳（保留现有 big-step 解释器 `runEntrypointWithArgs` 作为原子步；小步 `step` 关系推迟到 6b+）。`Evm.Refinement.lean` 新增 `counter_ir_trace_matches_inductive` 与 `value_vault_ir_trace_matches_inductive`，保留现有 `counter_ir_observable_trace_ok` / `value_vault_ir_observable_trace_ok` 作为回归 smoke。`Tests/IRStepSemantics.lean` + `just ir-step-semantics-smoke`（已接线进 `just check`）锚定该层。详见 [`docs/tier-c-proof-feasibility.md`](../../tier-c-proof-feasibility.md) 的 Phase 6a"已落地"小节。
- **Phase 6b —— 把 `powdr-labs/evm-semantics` 集成为 opt-in EVM refinement target。**
  将 `powdr-labs/evm-semantics` 作为按 commit pin 的 opt-in `lake` 依赖，只供 EVM refinement 模块使用；默认构建继续保持 mathlib-free。提供薄的 opt-in 适配器，暴露 powdr 的 `State` / `Step` / 可执行 `stepF` 并与 `ObservableStep` 对齐。交付物：可在 Lean 证明中调用的、由外部 conformance baseline 支撑的 EVM 字节码语义。
  **状态（2026-07-10 校正）：powdr target 已接入；Phase 6b 已解锁。** 早先 `EVMYulLean` 路线因 Lean 工具链 + mathlib 版本不匹配而阻塞（`v4.22.0` vs ProofForge 的 `v4.31.0`）。refinement target 现在改为 `powdr-labs/evm-semantics`，并已在 `lakefile.lean` 与 `lake-manifest.json` 中按 commit pin 到 opt-in `EvmRefinement` target 后面；因此默认 `lake build` 仍保持 mathlib-free，而 `lake build EvmRefinement` 会导入真实 `EvmSemantics` 模块。`ProofForge/Backend/Evm/EvmBytecodeSemantics.lean` 中的默认构建 seam 仍按设计保留为 mathlib-free stub；真实 wrapper 是 `EvmRefinement/PowdrAdapter.lean`，它暴露 powdr-backed `State`、`Step`、`stepF`、`runBytecode`，以及把 `runBytecode` 桥到 powdr 关系式 `Steps` 的 `runBytecode_steps`。当前 pin 的 powdr tree 暴露的是 bytecode semantics，不是 Yul 级关系，所以 Yul→bytecode 的 `solc` 步骤仍是显式信任边界。当前低位布局路径已锁定 solc 0.8.30 的 Counter 固定 trace；通用 theorem 仍显式要求 `CounterCompiledPowdrEntrypointObligations`。旧 prepared-frame opcode 证明仅作为 `LegacyHighPacked` 历史证据保留。见 [`docs/tier-c-proof-feasibility.md`](../../tier-c-proof-feasibility.md) §2。
- **Phase 6c —— 证明 Counter 的 IR → 字节码 refinement。** 定义 Counter 模块（单个 U64 标量 → 一个 storage slot）的 simulation 关系 `R : IR.State ↔ EVM.State`；为 `initialize`/`increment`/`get` 分别证明 `R`-simulation；通过对 call list 归纳提升为 trace 定理。交付物：首个端到端机器检查 refinement。
- **Phase 6d —— 扩展到 ValueVault（storage map + events）。** 扩展 `R` 把 IR map state 映射到 EVM storage slot 前缀（用 `Evm.Plan.ModulePlan`）；为全部七个 entrypoint 证明 refinement，含 event 发射；对 `ScenarioInputs` 全称量证明 `value_vault_accounting_invariant`。交付物：从 IR 携带到字节码的全称量化合约不变式。
- **Phase 6e —— 泛化 simulation 框架。** 抽取可复用的参数化 `SimulationFramework`，使同一模式原则上可瞄准 Solana（Mollusk/Pinocchio）或 NEAR（offline-host wasm）。注：非 EVM 链的 Tier C-proof 需要各自的形式化目标语义，目前不存在；此阶段为探索性，非 EVM 链在此类语义出现前留在 Tier C-diff。

**改动清单：**

- 路径 5a：`scripts/quint/*-backend-replay-gate.sh`（逐后端新增）、
  `ProofForge/Backend/Quint/{Solana,Near,Psy}Replay.lean`（新增，镜像现有
  `EvmReplay.lean`）、`justfile` recipe。**本步落地（additive stub）：**
  `ProofForge/Backend/Quint/NearReplay.lean`、`Tests/Quint/NearReplaySmoke.lean`、
  `just quint-near-replay-smoke`（不接线进 `just check`）。**2026-07-07 落地（Solana stub）：**
  `ProofForge/Backend/Quint/SolanaReplay.lean`、`Tests/Quint/SolanaReplaySmoke.lean`、
  `just quint-solana-replay-smoke`（不接线进 `just check`——端到端运行需要此处未安装的 SBF
  platform-tools，见 AGENTS.md）。Solana shim 渲染一个 Rust Mollusk 测试文件（设计文档的
  option (a)——镜像 EVM 的 Solidity 测试渲染和树内 `Tests/solana/counter_mollusk.rs.tpl`
  模板）；account-model 翻译（通过 `Manifest.externalDiscriminatorBytes?` 取指令
  discriminator + 单个可写 state account + 小端 instruction-data 字节）是相对 NEAR 的主要
  额外工作。见
  [`docs/quint-cdiff-multi-backend-design.md`](../../quint-cdiff-multi-backend-design.md)。
- 路径 5b：`docs/tier-c-proof-feasibility.md`（新增 —— 本步落地）。
  **2026-07-07 落地（Phase 6a）：** `ProofForge/IR/StepSemantics.lean`、
  `Tests/IRStepSemantics.lean`、`just ir-step-semantics-smoke`（接线进 `just check`）、
  `ProofForge/Backend/Evm/Refinement.lean` 桥接定理
  （`counter_ir_trace_matches_inductive`、`value_vault_ir_trace_matches_inductive`）。
  **2026-07-07 落地（Phase 6b）：** `lakefile.lean`、`lake-manifest.json`、
  `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean`、
  `EvmRefinement/PowdrAdapter.lean`、`EvmRefinement/CounterRefinement.lean`
  以及 opt-in powdr smoke gates 已把 `powdr-labs/evm-semantics` 接为 EVM
  refinement target，同时默认构建继续保持 mathlib-free。
  **下一步（Phase 6c）：** 通过可复用自动化消解当前低位 runtime 的
  `CounterCompiledPowdrEntrypointObligations`；不再手工扩展 legacy prepared-frame 证明。

**风险：** 夸大"已证明"的内容——路径 5a 是差分测试（Tier C-diff），不是证明；路径 5b 现有的 `Evm.Refinement`/`ValueVaultInvariant` 是 `native_decide` 可执行检查，不是机器检查 refinement。分阶段路线图（6a–6e）是通往真正 Tier C-proof 的具体路径，其中 6a 是无需新依赖的第一步。

**范围裁剪：** Solana 的 Tier C-proof（Lean 中的完整 syscall 语义——无现成形式化 sBPF 语义）。NEAR/Psy 同样推迟，待形式化目标语义出现；它们留在 Tier C-diff。完整 EVM conformance-suite 覆盖与所有 EVM opcode 不在本 RFC 范围内——conformance 属于外部 EVM 语义包；ProofForge 只需 adapter 与 simulation proofs 正确。

### Phase 6–7（stretch）

- **Phase 6：** Psy body plan；Solana `ExprPlan`/`StmtPlan`；EVM 按 `docs/implementation-backlog.md` 完成 `StmtPlan` ownership。
- **Phase 7：** `.evm-plan.json` / `.solana-plan.json` / `.near-plan.json` 快照供人工 review（RFC 0004 待定问题）；若 Phase 0–5 形状稳定，考虑 lowering 契约的 Lean typeclass 编码。

## 可行性 / 难度

| 后端 | Tier B 难度 | 原因 | 复用 EVM？ |
|---|---|---|---|
| EVM | 已完成 | 参考栈。 | 不适用 |
| Solana | 中等–困难（已在 main） | 新的 `AccountPlan`/`InstructionDataPlan`/`CpiPlan`；在约 1.7k LOC 模块中将 `LowerCtx` → plan 派生的重构，且 golden gate 字节稳定。 | Helper/event plan *模式*；account/syscall plan 是新的。 |
| NEAR | 易–中等（Phase 4 首选） | `WasmNear.Plan.ModulePlan` 已存在并被 `EmitWat` 消费（驱动 host imports/helpers）；剩余差距仅是把数据布局 `Ctx` 外化为 plan 字段，整个 `Ctx` 都是 plan-可派生的，没有 lowering-local 可变状态需要拆分。详见 `docs/multi-backend-moduleplan-design.md`。 | Plan 驱动的 metadata + helper-discovery 模式。 |
| Psy | 易（对齐接缝；推迟） | `PsyModulePlan` 已存在并被消费；没有 `LowerCtx` 需要拆分。扩展到 body planning 是 Phase 6 产品决策。 | Metadata + storage-shape plan 思路。 |
| Move-Sui | 困难（研究项；推迟） | Counter MVP spike，无真正 lowering；`SuiModulePlan` 须先于真正 lowering 构建，属 Phase 6+。 | 无。 |
| CosmWasm | 中等（后续） | 克隆 NEAR 拆分。 | NEAR > EVM。 |

**依赖：**

1. FV-2 IR 语义增长（Tier A）——Phase 5 obligation 需要它才能覆盖标量 + 固定聚合之外的更多内容。
2. FV-3 ownership 规则——Phase 1 ownership hook 依赖于在范围内 IR 子集上 ownership 已是 sound 的。
3. `Target.resolveModule` / diagnostic——已就位（V-GATE-SOLANA-05、EVM/Psy `validateCapabilities`）。
4. Testkit 共享场景（`testkit/scenarios/*.toml`）——Tier A/B 跨后端 parity 的公认 oracle。

## 备选方案

- **将 EVM `ModulePlan` 逐字克隆到每个后端。** 拒绝：RFC 0004 非目标明确保持目标 plan 类型为目标特定；account/CPI、host-import 和 circuit 模型与 storage slot + ABI selector 不同构。本 RFC 沿用同一边界。
- **通过 Lean typeclass 进行纯形式化统一。** 推迟：一旦 Phase 0–5 形状稳定，typeclass 编码是可行的，但在 Solana/NEAR plan 存在之前锁定它会有过早抽象的风险。作为 Phase 7 的待定问题跟踪。
- **维持现状。** 拒绝：在 Solana 上，强制执行分散在 diagnostic、golden asm、Mollusk 和 surfpool/Web3 之中，没有可检查的 plan。这让 review 更困难、阻碍 Tier A/C 挂载，并使 Solana 成为唯一没有 `*-semantic-plan` gate 的主要后端。

## 风险

- **`SbpfAsm.lean` 重构回归。** 缓解：feature flag `--solana-plan=v2`，切换前 golden-parity gate。
- **Diagnostic message 变更。** Phase 1 移动共享检查；golden diagnostic 快照必须一起更新。缓解：每个后端一个 PR，CI 变红会很明显。
- **NEAR 上 WAT golden 变更。** 同一缓解；Phase 4 由离线宿主 smoke parity 门控。
- **RFC 0004 边界漂移。** 本 RFC 不得被解读为"每个后端采纳 EVM 的 plan 类型"。非目标章节已明确。
- **CI 时间增长。** 新的 `*-semantic-plan` gate 增加的是仅 Lean 的 smoke；它们不替代任何东西但很廉价。`just semantic-plan-matrix` 对 reviewer 是 opt-in 的，在测量代价前不加入 `just check`。
- **过早抽象。** Phase 0 保持为文档；Phase 1 是最小可回退抽取（共享 validate）。若 Phase 1 干净落地，Phase 2/4 继续；否则在 Solana/NEAR 工作前重新审视本 RFC。

## 缺点

- 前期工程代价（仅 Phase 2 就 10–16 周）才有用户可见收益。收益面向 reviewer（可检查 plan、golden smoke）和面向形式化（refinement 接缝），而非新产品能力。
- 若契约在 Solana/NEAR plan 存在之前被过度规约，有过早抽象风险。通过将 Lean typeclass 编码后置到 Phase 7 来缓解。

## 待定问题

- Plan 制品是否应序列化为 JSON 供人工 review（Phase 7 stretch）？RFC 0004 将此留作开放；本 RFC 继承该问题。
- CosmWasm 现在就跟随 NEAR 拆分，还是在 Phase 4 落地之后？
- Lowering 契约是否应编码为 Lean typeclass？若是，在哪个阶段（Phase 0 桩 vs Phase 7 稳定形状）？
- `just semantic-plan-matrix` 应该属于 `just check`、`just ci`，还是一个独立的仅 reviewer 入口？
- **Phase 2+ 前置项 —— 共享 Diagnostic 类型。** Phase 1 盘点表明
  `validateCapabilities`、返回路径检查、标识符合法性、`ensureNumericType`
  当前不可安全统一，因为 EVM 与 NEAR 的签名、规则、diagnostic 字符串不同。
  是否应引入共享 `Diagnostic` 类型（带各后端 wrapper），使这些检查能在后续
  阶段统一而不改动现有 golden diagnostic 输出？这不阻塞 Phase 2
  （SolanaModulePlan）或 Phase 4（NEAR plan），但共享 validate 面要超越
  Phase 1 落地的四个纯 helper 的话，必须先做这一步。

  **决议（2026-07-07，Phase 3 桩落地）：** 是——在 `ProofForge.Backend.Diagnostic`
  中引入共享具体 `LoweringDiagnostic` 类型*加* `LoweringError` typeclass 契约。字段级
  审计（见 [`docs/shared-diagnostic-design.md`](../../shared-diagnostic-design.md)）表明
  每个后端的 lowering/plan/emit 错误类型已是同一形状——单字段
  `structure <Name> where message : String`，其 `render` 为 `err.message`——故共享具体
  类型是合理的，非过早抽象。共享 `render` **只**输出 `message`，因此委托的后端看到字节
  一致的输出；可选的 `backend?` / `severity` / `code?` 字段是 CLI 报告层的元数据，不参与
  `render`。后端保留其具体错误类型并以 trivial adapter 实现 typeclass；`SharedValidate`
  的 `SharedError = String` 在桩中不迁移。这为"共享 validate 面超越 Phase 1"目标解锁了
  后续（逐后端 adapter 实例落地后），但其本身并不统一
  `validateCapabilities` / 返回路径检查 / 标识符合法性 / `ensureNumericType`——那些仍需
  先对齐逐后端规则和消息。见下方「Phase 3 —— 共享 diagnostic 契约」小节。

## 后续工作

- **Tier A：** 按 FV-2/FV-3 增长 `IR/Semantics.lean`，使共享场景 trace obligation 覆盖每个对齐后端的 map/storage/event。
- **Tier C-diff：** 随着每个后端 `*ModulePlan` 落地，把 Quint backend replay harness 推广到 EVM 之外（Solana 通过 Mollusk、NEAR 通过 offline-host、Psy 通过 `dargo execute`）。长期目标：每个主要后端都有一个 `just quint-<target>-backend-replay-gate`。审计 + 抽象 replay 接口 + `NearReplay` 字段级设计 + 最小 additive stub 于 2026-07-07 落地；见 [`docs/quint-cdiff-multi-backend-design.md`](../../quint-cdiff-multi-backend-design.md)。NEAR 是所选的下一个候选（stub 已落地），Solana 是第 2（stub 已落地，渲染 Rust Mollusk 测试文件），Psy 是第 3（受限于 `dargo` 此处未安装），Move-Sui/Aleo/Cloudflare 延迟（研究性 spike）。一个类型-only 的 `SolanaReplay.lean` stub（渲染 Rust Mollusk 测试文件，option (a)）于 2026-07-07 落地。见 [`docs/quint-cdiff-multi-backend-design.md`](../../quint-cdiff-multi-backend-design.md) 获取逐后端可行性表、抽象 replay 接口、以及 `NearReplay`（§7）与 `SolanaReplay`（§8.1）的字段级设计。
- **Tier C-proof：** 继续推进已经 pin 到 `powdr-labs/evm-semantics` 的
  opt-in EVM proof lane：完成 Counter per-entrypoint powdr `Step` obligations
  和 universal trace lift，然后把同一形状扩展到 Counter 之外。深化
  `WasmNear.Refinement`；等目标语义存在后，再在 Phase 5 Counter 接缝之外添加
  面向 syscall-aware obligation 的 `Solana.Refinement`。
- 用于 CI 中跨后端 plan diff 的 **plan JSON 快照**。
- 在 Phase 0–5 形状被证明之后的 lowering 契约 **Lean typeclass**。

## 参考

- [RFC 0002](0002-target-implementation-design.zh.md) —— 目标 profile 与后端实现设计。
- [RFC 0003](0003-portable-ir-and-runtime.zh.md) —— portable IR、capability lowering、运行时 profile。
- [RFC 0004](0004-evm-semantic-plan.zh.md) —— EVM semantic plan 与 Yul AST 边界（本 RFC 推广的参考形状）。
- [RFC 0005](../../rfcs/0005-solana-sbpf-assembly-backend.md) —— Solana sBPF assembly 后端。
- [`docs/portable-ir.md`](../portable-ir.zh.md) —— 共享流水线图。
- [`docs/formal-verification.md`](../../formal-verification.md) —— FV-1..FV-8（FV-2 语义增长、FV-4 Psy 差分、FV-8 ValueVault 不变式）。
- [`docs/validation-gates.md`](../validation-gates.zh.md)、[`docs/gate-status.md`](../gate-status.zh.md) —— P0-2 EVM semantic-plan 状态。
- `ProofForge/Backend/Evm/{Validate,Plan,Lower,IR,Refinement,YulSemantics}.lean`
- `ProofForge/Backend/WasmHost/{IR,EmitWat,Refinement}.lean`
- `ProofForge/Backend/Psy/{Plan,IR,Metadata}.lean`
- `ProofForge/Backend/Solana/{SbpfAsm,StateLayout,Extension,Manifest,Idl,Package}.lean`
- `ProofForge/IR/{Semantics,Ownership}.lean`
- `ProofForge/Target/{Plan,Adapter,Registry,Check}.lean`
- `Tests/{EvmPlan,EvmSemanticPlan,NearWasmFormal,IROwnership,SolanaDiagnostics,PsyMetadata}.lean`
