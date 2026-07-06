# RFC 0014：跨后端的统一语义降级契约

Status: **Draft**

Date: 2026-07-06

Builds on: [RFC 0003](0003-portable-ir-and-runtime.md)（portable IR）、
[RFC 0004](0004-evm-semantic-plan.md)（EVM semantic plan）、
[RFC 0005](0005-solana-sbpf-assembly-backend.md)（Solana sBPF 后端）。

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

本 RFC 提议**Tier B 统一**：让每个主要后端对齐到相同的*契约*（validate、plan、AST、smoke），而不强制采用单一的全局 `ModulePlan` 类型。Plan 类型保持逐目标，正如 [RFC 0004](0004-evm-semantic-plan.md) 的非目标已经要求的那样，因为 account/CPI、host-import 和 circuit 模型各不相同。两个相邻的层级——共享 IR 操作语义（Tier A）和端到端 refinement 证明（Tier C）——在本 RFC 中界定范围但不交付。

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
   [`docs/formal-verification.md`](../formal-verification.md) 工作流 25
   的跨后端 obligation（FV-2 语义增长、FV-8 ValueVault 不变式）。
3. 一个共享的 `validate` 子集（标识符、返回路径、ownership hook），每个后端要么委托给它，要么显式覆盖，而不是每个后端各自重新发明相同的检查。

## "语义统一"的三个层级

| 层级 | 含义 | 代价 | 本 RFC 范围内？ |
|---|---|---|---|
| **A** | 共享 IR 操作语义（`IR/Semantics.lean`）是基准；每个后端针对 IR 子集（语义当前覆盖的部分）通过共享场景的 trace obligation。 | 中等——语义已存在但需增长（FV-2/FV-3）。 | **否**（已确认的依赖；由 FV 工作流跟踪）。 |
| **B** | 共享 lowering *契约*：逐后端的 `validateModule*` + `*ModulePlan` + `lowerToAst` + plan 驱动的 metadata + golden `*-semantic-plan` smoke。 | EVM 已完成；Psy 易–中等；NEAR 中等；Solana 中等–困难。 | **是。** |
| **C** | 端到端 refinement：机器可检查的 IR 语义 ⟷ 逐后端的链上行为。 | 困难；Solana 上仍为研究性质（FV-4）。 | **否**（明确的非目标）。 |

本 RFC 仅针对 **Tier B**，因为 Tier B 是不对称性伤害最大、且工程纪律无需新形式化模型即可产生回报的地方。

## 设计目标

- 让每个主要后端通过 **validate → plan → AST** 降级，且 plan 是一个**可检查的制品**，而不是临时的 lowering 上下文。
- 在 Psy、NEAR 和 Solana 上镜像 EVM 的 smoke 模式（`just evm-plan`、`just evm-semantic-plan`），使 reviewer 可以 diff plan，而不仅是 bytecode/asm。
- 抽取真正共享的 `validate` 子集（标识符、入口返回路径、按 profile 不支持的类型、ownership hook），让后端不再重复它。
- 保留 RFC 0004 的边界：目标 plan 类型是**目标特定的**，而不是一个对所有链通用的单一 `ModulePlan`。
- 为 Tier A（共享语义）和 Tier C（refinement）留下一个干净的接缝，以便后续挂载而无需重新争论 lowering 边界。

## 非目标

- 一个所有后端共享的单一全局 `ModulePlan` 类型。RFC 0004 的非目标已经排除了这一点；account/CPI、host-import 和 circuit 模型各不相同。
- 机器可检查的端到端 refinement（Tier C），包括 Solana syscall 或 sBPF 语义的 Lean 模型。
- 证明外部工具链（`solc`、`sbpf`、`wat2wasm`、`dargo`、Mollusk）。这些按照 `docs/formal-verification.md` 保持在证明 TCB 之外。
- 在初始范围内将契约扩展到 CosmWasm、Move（Sui/Aptos）、Aleo、Cloudflare TS。这些可在四个主要后端对齐之后跟进。
- 替换现有的 AST printer 或外部工具调用。契约位于 AST 层*之上*；printer 保持原样。
- 强制每个后端在第一天就长出 EVM 形态的 `ExprPlan`/`StmtPlan` body plan。Body planning 被后置（Phase 5），且只在有价值的地方进行。

## 各后端当前状态

### EVM（参考栈）

- `ProofForge/Backend/Evm/Validate.lean` —— 类型/形状/能力检查、init code、map-presence 域、event signature 类型。
- `ProofForge/Backend/Evm/Plan.lean` —— `StorageLayout`、`EntrypointPlan`、`DispatchPlan`、`EventPlan`、crosscall/create spec、`MetadataPlan`，以及组合成 `ModulePlan` 的 body-planning `ExprPlan` / `StmtPlan`。
- `ProofForge/Backend/Evm/Lower.lean` —— `buildModulePlan`、`buildFullModulePlan`、`buildFullModulePlanWithTargetPlan`。
- `ProofForge/Backend/Evm/IR.lean` —— `buildSemanticPlan`、`lowerModuleWithPlan`、`renderSemanticPlan`（plan 检查）。
- `ProofForge/Backend/Evm/{ToYul,Metadata,ConstructorInit}.lean` —— plan → Yul AST 以及 deploy/artifact metadata。
- `ProofForge/Backend/Evm/Refinement.lean` + `YulSemantics.lean` —— 针对 IR trace 与 selector-dispatched Yul 表面以及一个可执行 Yul 子集（Counter、ValueVault、Map/TypedStorage/StorageStruct/AbiAggregate/Conditional/Loop/Event 探针）的 `TraceObligation`。

CI：`just evm-plan`（`Tests/EvmPlan.lean`）、`just evm-semantic-plan`（`Tests/EvmSemanticPlan.lean`），以及 `lake build ProofForge.Backend.Evm.Refinement`（定理从 `Tests/NearWasmFormal.lean` 以 `#check` 锚定）。

### NEAR（validate 丰富、plan 匮乏、形式化强）

- `ProofForge/Backend/WasmNear/IR.lean` —— `validateModule`：capability + 标识符 + state + 逐入口 param/return/type + 返回路径检查。
- `ProofForge/Backend/WasmNear/EmitWat.lean` —— `checkTargetPlan` 以及在 render 之前对 `IR.Ownership.checkModule` 的调用。
- `ProofForge/Backend/WasmNear/Refinement.lean` —— 最丰富的形式化层：IR trace、WAT export、Wasm AST host-boundary frame、离线宿主 Borsh/hex obligation；ValueVault 不变式桥接。
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
| NEAR | `WasmNear.Plan.NearModulePlan`（**新增**） | `Backend/WasmNear/Plan.lean`（**新增**） | `Compiler/Wasm` |
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

Golden plan 快照（Phase 6 stretch）会将 plan 序列化为 JSON 供人工 review；这是一个待定问题，而非 Phase 1–4 的要求。

## 分阶段实施

每个阶段都可独立交付且可干净回退。Phase 0–3 属于 Tier B；Phase 4 开启 Tier C 接缝但不交付完整证明。

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
- 添加 `Tests/SolanaSemanticPlan.lean` 和 `just solana-semantic-plan`，镜像 `evm-plan`（layout + entrypoint + manifest + CPI/account schema 一致性）。

**改动清单：**

- `ProofForge/Backend/Solana/Plan.lean`（新增）
- `ProofForge/Backend/Solana/SbpfAsm.lean`、`StateLayout.lean`、`Manifest.lean`、`Idl.lean`、`Package.lean`
- `justfile`、`.github/workflows/ci.yml`（加入 `solana-lean` 族或 `check`）

**风险：** `SbpfAsm.lean` 约 1.7k LOC，且喂给 golden asm + Pinocchio reference-equivalence gate；重构必须保持它们字节稳定。建议在 feature flag（如 `--solana-plan=v2`）后落地，并在证明 golden parity 后切换。

**范围裁剪：** body planning（Solana 的 `ExprPlan`/`StmtPlan`）→ Phase 5。

### Phase 3 —— NEAR plan 层（8–12 周）

**里程碑：**

- 添加 `ProofForge/Backend/WasmNear/Plan.lean`（`NearModulePlan`）。
- `EmitWat` 消费 plan：`validateModule` → `buildModulePlan` → `lowerToAst`（镜像 EVM 的 `lowerModuleWithPlan`）。
- 添加 `Tests/NearSemanticPlan.lean` 和 `just near-semantic-plan`。
- `WasmNear/Refinement.lean` 在当前重新推导 export/import 的地方消费 plan。

**改动清单：**

- `ProofForge/Backend/WasmNear/Plan.lean`（新增）、`EmitWat.lean`、`IR.lean`
- `ProofForge/Backend/WasmNear/Refinement.lean`

**风险：** WAT golden 变更；离线宿主 smoke 必须保持字节稳定。与 Phase 2 相同的 feature-flag 策略。

**范围裁剪：** Lean 中的完整 Wasm 指令语义（Tier C，推迟）。

### Phase 4 —— Refinement 接缝（持续）

**里程碑：**

- 添加 `ProofForge/Backend/Solana/Refinement.lean` 骨架：针对 selector-dispatched asm 表面的 Counter IR trace obligation（无完整 sBPF 语义）。
- 将 `Tests/NearWasmFormal.lean` 接线为在非空时导入 Solana obligation（CI build-gated）。
- 将 [`docs/formal-verification.md`](../formal-verification.md) 的 FV-8（ValueVault 不变式）链接到逐后端 obligation。
- 可选 Psy：以 Lean test 形式做 IR trace vs `dargo` 向量。

**改动清单：**

- `ProofForge/Backend/Solana/Refinement.lean`（新增）
- `Tests/NearWasmFormal.lean`
- `ProofForge/Contract/Examples/ValueVaultInvariant.lean`

**风险：** 夸大"已证明"的内容——本 RFC 明确 Phase 4 是一个*接缝*（Counter/ValueVault trace 形状），而非 Tier C 完整性。

**范围裁剪：** Solana 的 Tier C（Lean 中的完整 syscall 语义）。

### Phase 5–6（stretch）

- **Phase 5：** Psy body plan；Solana `ExprPlan`/`StmtPlan`；EVM 按 `docs/implementation-backlog.md` 完成 `StmtPlan` ownership。
- **Phase 6：** `.evm-plan.json` / `.solana-plan.json` / `.near-plan.json` 快照供人工 review（RFC 0004 待定问题）；若 Phase 0–4 形状稳定，考虑 lowering 契约的 Lean typeclass 编码。

## 可行性 / 难度

| 后端 | Tier B 难度 | 原因 | 复用 EVM？ |
|---|---|---|---|
| EVM | 已完成 | 参考栈。 | 不适用 |
| Psy | 易–中等 | `PsyModulePlan` 已存在；扩展 + 对齐接缝。 | Metadata + storage-shape plan 思路。 |
| NEAR | 中等 | 已有强 `validateModule`；重构在于从 `EmitWat`/`IR` 中抽取 plan。 | Plan 驱动的 metadata 模式。 |
| Solana | 中等–困难 | 新的 `AccountPlan`/`InstructionDataPlan`/`CpiPlan`；在约 1.7k LOC 模块中将 `LowerCtx` → plan 派生的重构，且 golden gate 字节稳定。 | Helper/event plan *模式*；account/syscall plan 是新的。 |
| CosmWasm | 中等（后续） | 克隆 NEAR 拆分。 | NEAR > EVM。 |

**依赖：**

1. FV-2 IR 语义增长（Tier A）——Phase 4 obligation 需要它才能覆盖标量 + 固定聚合之外的更多内容。
2. FV-3 ownership 规则——Phase 1 ownership hook 依赖于在范围内 IR 子集上 ownership 已是 sound 的。
3. `Target.resolveModule` / diagnostic——已就位（V-GATE-SOLANA-05、EVM/Psy `validateCapabilities`）。
4. Testkit 共享场景（`testkit/scenarios/*.toml`）——Tier A/B 跨后端 parity 的公认 oracle。

## 备选方案

- **将 EVM `ModulePlan` 逐字克隆到每个后端。** 拒绝：RFC 0004 非目标明确保持目标 plan 类型为目标特定；account/CPI、host-import 和 circuit 模型与 storage slot + ABI selector 不同构。本 RFC 沿用同一边界。
- **通过 Lean typeclass 进行纯形式化统一。** 推迟：一旦 Phase 0–4 形状稳定，typeclass 编码是可行的，但在 Solana/NEAR plan 存在之前锁定它会有过早抽象的风险。作为 Phase 6 的待定问题跟踪。
- **维持现状。** 拒绝：在 Solana 上，强制执行分散在 diagnostic、golden asm、Mollusk 和 surfpool/Web3 之中，没有可检查的 plan。这让 review 更困难、阻碍 Tier A/C 挂载，并使 Solana 成为唯一没有 `*-semantic-plan` gate 的主要后端。

## 风险

- **`SbpfAsm.lean` 重构回归。** 缓解：feature flag `--solana-plan=v2`，切换前 golden-parity gate。
- **Diagnostic message 变更。** Phase 1 移动共享检查；golden diagnostic 快照必须一起更新。缓解：每个后端一个 PR，CI 变红会很明显。
- **NEAR 上 WAT golden 变更。** 同一缓解；Phase 3 由离线宿主 smoke parity 门控。
- **RFC 0004 边界漂移。** 本 RFC 不得被解读为"每个后端采纳 EVM 的 plan 类型"。非目标章节已明确。
- **CI 时间增长。** 新的 `*-semantic-plan` gate 增加的是仅 Lean 的 smoke；它们不替代任何东西但很廉价。`just semantic-plan-matrix` 对 reviewer 是 opt-in 的，在测量代价前不加入 `just check`。
- **过早抽象。** Phase 0 保持为文档；Phase 1 是最小可回退抽取（共享 validate）。若 Phase 1 干净落地，Phase 2/3 继续；否则在 Solana/NEAR 工作前重新审视本 RFC。

## 缺点

- 前期工程代价（仅 Phase 2 就 10–16 周）才有用户可见收益。收益面向 reviewer（可检查 plan、golden smoke）和面向形式化（refinement 接缝），而非新产品能力。
- 若契约在 Solana/NEAR plan 存在之前被过度规约，有过早抽象风险。通过将 Lean typeclass 编码后置到 Phase 6 来缓解。

## 待定问题

- Plan 制品是否应序列化为 JSON 供人工 review（Phase 6 stretch）？RFC 0004 将此留作开放；本 RFC 继承该问题。
- CosmWasm 现在就跟随 NEAR 拆分，还是在 Phase 3 落地之后？
- Lowering 契约是否应编码为 Lean typeclass？若是，在哪个阶段（Phase 0 桩 vs Phase 6 稳定形状）？
- `just semantic-plan-matrix` 应该属于 `just check`、`just ci`，还是一个独立的仅 reviewer 入口？
- **Phase 2+ 前置项 —— 共享 Diagnostic 类型。** Phase 1 盘点表明
  `validateCapabilities`、返回路径检查、标识符合法性、`ensureNumericType`
  当前不可安全统一，因为 EVM 与 NEAR 的签名、规则、diagnostic 字符串不同。
  是否应引入共享 `Diagnostic` 类型（带各后端 wrapper），使这些检查能在后续
  阶段统一而不改动现有 golden diagnostic 输出？这不阻塞 Phase 2
  （SolanaModulePlan）或 Phase 3（NEAR plan），但共享 validate 面要超越
  Phase 1 落地的四个纯 helper 的话，必须先做这一步。

## 后续工作

- **Tier A：** 按 FV-2/FV-3 增长 `IR/Semantics.lean`，使共享场景 trace obligation 覆盖每个对齐后端的 map/storage/event。
- **Tier C：** 深化 `Evm.Refinement` 和 `WasmNear.Refinement`；在 Phase 4 Counter 接缝之外添加面向 syscall-aware obligation 的 `Solana.Refinement`。
- 用于 CI 中跨后端 plan diff 的 **plan JSON 快照**。
- 在 Phase 0–4 形状被证明之后的 lowering 契约 **Lean typeclass**。

## 参考

- [RFC 0002](0002-target-implementation-design.md) —— 目标 profile 与后端实现设计。
- [RFC 0003](0003-portable-ir-and-runtime.md) —— portable IR、capability lowering、运行时 profile。
- [RFC 0004](0004-evm-semantic-plan.md) —— EVM semantic plan 与 Yul AST 边界（本 RFC 推广的参考形状）。
- [RFC 0005](0005-solana-sbpf-assembly-backend.md) —— Solana sBPF assembly 后端。
- [`docs/portable-ir.md`](../portable-ir.md) —— 共享流水线图。
- [`docs/formal-verification.md`](../formal-verification.md) —— FV-1..FV-8（FV-2 语义增长、FV-4 Psy 差分、FV-8 ValueVault 不变式）。
- [`docs/validation-gates.md`](../validation-gates.md)、[`docs/gate-status.md`](../gate-status.md) —— P0-2 EVM semantic-plan 状态。
- `ProofForge/Backend/Evm/{Validate,Plan,Lower,IR,Refinement,YulSemantics}.lean`
- `ProofForge/Backend/WasmNear/{IR,EmitWat,Refinement}.lean`
- `ProofForge/Backend/Psy/{Plan,IR,Metadata}.lean`
- `ProofForge/Backend/Solana/{SbpfAsm,StateLayout,Extension,Manifest,Idl,Package}.lean`
- `ProofForge/IR/{Semantics,Ownership}.lean`
- `ProofForge/Target/{Plan,Adapter,Registry,Check}.lean`
- `Tests/{EvmPlan,EvmSemanticPlan,NearWasmFormal,IROwnership,SolanaDiagnostics,PsyMetadata}.lean`
