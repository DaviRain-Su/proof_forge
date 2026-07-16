---
id: PHASE-2
title: 系统架构
status: proposed
owner: architecture
updated: 2026-07-15
normative: true
---

# Phase 2：系统架构

视觉总览（非规范）：[`diagrams/01-architecture-overview.png`](diagrams/01-architecture-overview.png)
与完整图目录 [`diagrams/README.md`](diagrams/README.md)。图与本文冲突时以本文与代码为准。

## 系统上下文

```text
Author / CI
    │ Lean source + explicit CLI target/profile
    ▼
proof-forge-next
    ├─ Lean Parser → bounded Syntax preflight → ProofForge decoder → Source.Program
    ├─ name/type/effect checker → Typed.Program
    ├─ target-neutral normalization → Semantic.Program + ProgramRequirements
    ├─ Support resolver → ResolvedProgram target
    ├─ target Materializer → target Plan → TargetIR
    └─ emitter → OutputSet + provenance
          │
          ├─ official packager/validator/runtime
          └─ deploy/prove/verify command (explicit)
```

编译器是代码生成与语义检查工具，不是链 VM、密钥托管器或默认网络执行器。
Lean Parser 提供 token/layout/syntax tree；它不替代业务 IR。parser 成功后，每个 portable
program command 先经过有界、非递归 Syntax preflight，再进入递归 decoder。CLI loader 只加载
受信任的 ProofForge grammar initializer，解析后拒绝 DSL 白名单之外的 Lean command，不执行
用户模块 elaboration。当前 preflight 不保护 Lean parser 本身。随后三个互不等同的领域类型
依次承担 surface、checked source 和 canonical semantics 责任。

## 架构不变量

- INV-001：source/Typed/Semantic 层不根据 target 分支。
- INV-002：target 只能选择等价 materialization；不等价映射必须拒绝。
- INV-003：每个 requirement 有 source span；每个 support decision 可审计。
- INV-004：Plan 拥有 ABI、layout、imports、calls/proof wiring；emitter 不重新发现语义。
- INV-005：任一失败不转成成功或 legacy/fallback 路径。
- INV-006：artifact encoding 与 execution/commit/state/proof/settlement 维度分离。
- INV-007：disclosure、authority、state custody 是三个独立轴。
- INV-008：build 无网络和密钥副作用；deploy/prove/verify 显式执行。
- INV-009：所有身份、序列化和输出顺序决定性。
- INV-010：V2 在 clean-room 中不依赖父项目。

## 中立语义

```lean
structure SemanticProgram where
  schemaVersion : SemanticSchemaVersion
  identity      : ProgramIdentity
  types         : Array SemanticType
  logicalState  : Array StateDecl
  entries       : Array EntryDecl
  invariants    : Array InvariantDecl
  requirements  : ProgramRequirements

inductive Outcome where
  | returned (postState : State) (value : Value) (effects : Array OrderedEffect)
  | reverted (error : SemanticError) (unchangedState : State)
  | trapped (fault : SemanticFault) (unchangedState : State)
```

`step : State → Invocation → ExternalResponses → Outcome` 是 reference semantics。
失败时 logical state 原子回滚。NEAR receipt、ICP await 或外部 proof settlement 的额外提交
边界由 target Plan 表达；若源程序要求的原子边界无法保持则拒绝。

## Requirements 与 Support

requirements 是以下正交域的原子项：`value.*`、`control.*`、`state.*`、`effect.*`、
`context.*`、`disclosure.*`、`authority.*`、`stateCustody.*`、`failure.*`、
`extension.*`。Resolver 流程固定为：

1. exact `TargetId` lookup。
2. 对每个 requirement 查找 exact version/digest `SupportClaim`。
3. 检查 claim preconditions 与最低 evidence grade。
4. 聚合所有 rejection；无 rejection 才构造 `ResolvedProgram target`。
5. materializer 只能接收 resolved 值，不能自行忽略 requirement。

## Target Descriptor

目标不是单一 family enum：

```lean
structure TargetDescriptor where
  targetId         : TargetId
  artifactEncoding : ArtifactEncoding
  executionHost    : ExecutionHost
  commitModel      : CommitModel
  stateBinding     : StateBinding
  callModel        : CallModel
  proofModel       : ProofModel
  settlementModel  : SettlementModel
  abiModel         : AbiModel
  resourceModel    : ResourceModel
```

`TargetId` 定义语义身份；`CodegenProfileId` 固定 emitter/ABI/toolchain；
`NetworkProfileId` 只用于部署网络。不得由 network profile 改变生成语义。

## Target-owned Plan

每个 materializer 使用关联类型保留 Plan 和 TargetIR。Phase 1 分别为 `EvmPlan`、
`SolanaPlan`、`NearPlan`、`NoirPlan`。未来 Wasm host 各自拥有 Plan，只复用
`WasmModuleRecipe → deterministic Wasm encoder`；ZK target 也按 circuit、zkVM、
application chain 分开。

## 状态物化

同一 logical state 可物化到 EVM storage、Solana accounts、NEAR KV 或 Noir
pre/post-state relation。映射必须证明/测试读写、缺省值、键编码、整数溢出、失败回滚
和状态连续性保持。Noir 没有原生持续状态，manifest 必须标记
`stateContinuity = external`，并输出公开或承诺化的 pre/post state。

## Output 与信任边界

OutputSet 原子写入临时目录，校验后 rename。manifest 包含 source/semantic/plan/
artifact/toolchain hash、profiles、support decisions、deployability、settlement 和 evidence。
外部 packager、chain runtime、prover 和 RPC 均为不可信边界；stdout、路径、artifact
大小、运行时间和环境继承必须限制并记录。

## Clean-room 边界

V2 使用自己的 Lake package、toolchain lock 和命名空间。禁止父路径 import、相对依赖、
symlink、父 fixture/script/build/binary、`LEAN_PATH`/`PATH` 旧入口及父 cache。验收把
允许文件归档到空目录，设置新的 `HOME`/Lake cache，清理相关环境，只使用锁定工具
和明确网络策略执行 docs/build/test。

development continuation 分为 materialize、core 与 runtime 三个 deny-default stage；每个
stage 拥有独立 read/write/exec/network allowlist，payload 不能读取 policy/receipt。
launcher 关闭继承 FD、使用 `/dev/null` stdin、限制输出与运行时间，并把 stdout/stderr
发布为私有只读 receipt。

该开发实现只清理 launcher 建立的原 process group；子进程仍可通过 `setsid()` 建立新
session，因此不构成 formal orphan/fork-bomb containment。正式执行必须由 eligible host
上的 Stage-0 直接 handoff 到具备 process-session containment 的受控 runner。

## 关键风险

- 抽象过宽：以 requirement + honest rejection 控制。
- Plan 退化为字符串：关联类型和 invariant validation 控制。
- 形式语义与真实制品脱节：reference trace + target runtime/proof differential 控制。
- 工具链漂移：exact pin、checksum、profile 和 provenance 控制。
- ZK 信息泄漏：披露 taint 检查、artifact inspection、proof I/O tests 控制。
- 平台术语漂移：target dossier 和 source/claim register 定期复核。
