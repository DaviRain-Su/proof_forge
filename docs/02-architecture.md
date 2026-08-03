---
id: PHASE-2
title: 系统架构
status: accepted
owner: architecture
updated: 2026-08-04
normative: true
approvers: architecture-owner, davirain, quality-owner, security-owner
approvedAt: 2026-07-20
reviewCommit: db4cf6b883196548e46e0e9c7d630ae6b397ee4e
reviewLink: https://ampcode.com/threads/T-019f7dea-e600-77ea-8884-9f35f81f747d
openFindings: none
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
    ├─ in-process source snapshot: Loader → ProgramV1 / CheckV1 → Normalize → CompiledSemanticV1
    ├─ optional inline same-file proof gate (ADR-0026; before target resolve)
    ├─ engineering requirement resolve → capability
    ├─ target Materializer → target Plan → TargetIR
    └─ emitter → engineering OutputSet + provenance
          │
          ├─ official packager/validator/runtime
          └─ deploy/prove/verify command (explicit)
```

> **Engineering path note（2026-08-04，ADR-0026）**：当前产品源路径是进程内
> `Loader.selectProgramV1Product` 单次 in-memory snapshot，**不是**下图历史
> contained frontend/core worker 叙述的运行形态。前端监督层已于 2026-08-01 移除。
> Inline theorem certification 若启用，对 **同一 snapshot raw source** 做 in-process
> elaboration + Environment audit；**不是** sandbox、**不是** hermetic/formal evidence。
> 下文若仍出现 contained worker 措辞，仅保留 historical accepted 意图；产品实现以
> `RECOVERY.md` / `AGENTS.md` 与 ADR-0026 为准。

编译器是代码生成与语义检查工具，不是链 VM、密钥托管器或默认网络执行器。
Lean Parser 提供 token/layout/syntax tree；它不替代业务 IR。parser 成功后，每个 portable
program command 先经过有界、非递归 Syntax preflight，再进入递归 checked decoder。
**当前工程产品路径**在同一进程内完成 source read → ProgramV1 decode/check → Normalize；
historical accepted 叙述中的独立 contained frontend/core worker 已非 sole 产品 authority。
随后三个互不等同的领域类型依次承担 surface、checked source 和 canonical semantics 责任。

Source 标识有三层、不得混用：**(A)** Lean `Name.str` **raw** payload（不含 renderer 添加的外围
guillemets；raw 本身可含 opening `U+00AB`）；**(B)**
`Name.toString` **rendered** spelling（可含 `«…»`）；**(C)** `SPEC-COMMON-001` `QualifiedName`/
isId\* **common** component（非 source wire Ident）。未来 `Source.ProgramV1` 的 Ident 与 source
identity 数组以 raw carrier `SourceNameComponentV1` 为 wire 权威，不把 rendered 写入 canonical
bytes，也不把 source identity 降格为 common `QualifiedName`。alpha `Source.Program` 字符串字段仍是
过渡面，不得当作 v1 wire 身份。

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
- INV-011：compiler 的时间、内存、输出与进程预算必须版本化、可测量并在超限时稳定失败。
- INV-012：每个 active normative `GOAL/FR/NFR` 必须以精确 ID 闭合到决定或不变量、
  规格、任务及其 specified 验收测试；task 只有在 `done` 时才要求 `passed` EV，release 只有在
  accepted 时才要求 formal candidate-bound evidence set。未知、缩写、范围和孤儿引用必须
  fail closed，specified 不得冒充 closed。
- INV-013：持久化 DSL、schema、target/codegen profile 的版本和兼容边界必须显式；破坏性
  变更要求 major bump、迁移路径和 old/new reader 或 upgrade/rollback 验收，禁止隐式兼容。
- INV-014：攻击者可控 source 在进入 Lean parser 前必须已经处于版本化资源与 process-session
  containment；parser timeout/OOM/process/output 超限必须由边界外 parent 转换为稳定诊断。

任务关闭有两个不可互换的 control-plane：`SPEC-TASKQUAL-001` 的 `TaskQualificationV1`
只对 accepted PHASE-4 row 的冻结 tests 作 candidate-bound qualification；`SPEC-EVFINAL-001`
的 full formal finalization 对 `RequiredTestSetV1` 全分母作 release aggregate。前者不得改变 EV
qualification vocabulary、推导 subset denominator 或满足 `TASK-D8-04`/`TST-ISO-003`。

## 中立语义

`SemanticProgramV1` 的唯一字段、constructor、wire 与 hash authority 是
[`SPEC-SEM-WIRE-001`](specs/semantic-program-wire.md)：public carrier 是 validated canonical bytes，
decoded data 包含 qualified name、types、constants、logical state、events/errors、callables、invariants
和 embedded ProgramRequirements。架构页不重新声明缩减版结构。

`SemanticProgram` 的 canonical bytes 不含 sourceHash、path/span 或 origin，也 **不含**
proof reference、theorem body 或 certification digest。独立 `SemanticProvenance` companion
exact 绑定 qualifiedName、sourceHash、semanticHash 与 entity origin map；
它只服务 diagnostics/audit/certification join，不能进入 target-neutral 业务求值或 target 选择。

### Inline same-file theorem certification（ADR-0026，engineering）

当 source 在 program 之后声明 ordinary adjacent Lean `theorem`（经 `proof … using …`
binding / theorem inventory）时，产品在 **requirement resolve 与 materialization 之前**
运行 proof gate：

1. 单一 in-memory source snapshot（禁止为证明重读磁盘）；
2. ProgramV1 / `sourceHash` **不含 theorem body**；`semanticHash` 永不携带 proof；
3. in-process elaboration（**非** sandbox）+ Environment declaration-kind / defeq /
   dependency / axiom audit；
4. 固定允许 base axiom：`Classical.choice` / `Quot.sound` / `propext`；
5. **不信任** 用户 `.olean` 或 ambient lake 路径作为 theorem authority；
6. 当前唯一命题为 `InvariantTheoremV1`：在全部 `StateConformsV1` 状态下
   `evalInvariantV1 = .returnedTrue`。

该 gate **不** 证明 reachability、init/step safety、target refinement，也 **不** 关闭
formal `TST-PROOF-001` / hermetic / release。失败零制品；空 proof 表面显式 skip。

`SPEC-SEM-001`/public façade `ProofForgeV2.Semantic.ReferenceV1` 唯一定义
`ReferenceValueV1`、`InvocationV1`、`ExternalResponsesV1`、`OrderedEffectV1`、revert/fault 与
`OutcomeV1`；实现机械抽取到lower `ReferenceMachineV1`但保留同一public namespace/FQName，本架构页
不声明简化替身。
`step : SemanticProgramV1 → LogicalStateV1 → InvocationV1 → ExternalResponsesV1 → OutcomeV1` 是
reference semantics。
失败时 logical state 原子回滚。NEAR receipt、ICP await 或外部 proof settlement 的额外提交
边界由 target Plan 表达；若源程序要求的原子边界无法保持则拒绝。

## Requirements 与 Support

requirements 是以下正交域的原子项：`value.*`、`control.*`、`state.*`、`effect.*`、
`context.*`、`disclosure.*`、`authority.*`、`state-custody.*`、`failure.*`、
`extension.*`。Resolver 流程固定为：

1. exact `TargetId` lookup。
2. 对每个 requirement 查找 exact version/digest `SupportClaim`。
3. 检查 claim preconditions 与最低 evidence grade。
4. 聚合所有 rejection；无 rejection 才构造 `ResolvedProgram target`。
5. materializer 只能接收 resolved 值，不能自行忽略 requirement。

## Target Descriptor

目标不是单一 family enum。`TargetSemanticsV1`、`TargetDescriptor`、`CodegenProfileV1`、
`AcceptanceProfileV1` 和 `MaturitySnapshot` 的唯一 schema authority 是
[`SPEC-REG-001`](specs/target-registry.md)；本架构页不重复定义字段。

`TargetId` 是稳定宿主名称，完整语义身份由 canonical `TargetSemanticsV1` 的
`(TargetId, semanticsVersion, semanticsDigest)` 派生。fork/precompile/protocol/resource/
failure 以及可观察 ABI 意义都只属于该 payload；CodegenProfile 只拥有实现它的
ABI byte encoding、emitter、artifact encoding、toolchain 和非语义 lowering，不能覆盖语义。
`TargetDescriptor` 只保留静态 semantics、`AcceptanceProfileRef`、support claim 和 codegen
registration；动态 maturity snapshot 不进入 descriptor 或 registry hash。
`NetworkProfileId` 只用于 chain/genesis identity、endpoint、fee 和部署政策。
deploy/verify 以含 codegen profile digest 的完整 `BuildIdentity` 与 network 做 exact
compatibility join；network
不匹配只能拒绝，不得改变 SemanticProgram、Plan 或 artifact。

## Target-owned Plan

每个 materializer 使用关联类型保留 Plan 和 TargetIR。Phase 1 分别为 `EvmPlan`、
`SolanaPlan`、`NearPlan`、`NoirPlan`。未来 Wasm host 各自拥有 Plan，只复用
`WasmModuleRecipe → deterministic Wasm encoder`；ZK target 也按 circuit、zkVM、
application chain 分开。
所有 target 默认 immutable；upgrade authority、proxy/controller 或 migration 只能来自
显式、版本化 requirement/extension。Plan 只能物化已 resolve 的决定，不得
自行选择管理员或可升级策略。

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
完整资产—攻击者—入口—控制—剩余风险矩阵由
[`SPEC-SEC-001`](specs/security.md) 约束，并以 `TST-SEC-001`、`TST-ISO-001/002/003`
验收 INV-005/008/010/011 与 ADR-0010/0011/0013。

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
