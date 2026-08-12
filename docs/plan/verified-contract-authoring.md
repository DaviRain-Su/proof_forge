---
id: PLAN-VERIFIED-CONTRACT-AUTHORING
title: ProofForge VerifiedVault 风格形式化验证作者体验实施规划
status: draft
owner: engineering
updated: 2026-08-11
normative: false
---

# ProofForge VerifiedVault 风格形式化验证作者体验实施规划

> **目标**：让 ProofForge 合约作者获得与
> [`VerifiedVault.lean`](https://github.com/DaviRain-Su/lean4/blob/zig-backend-codegen-clean/examples/near/contracts/VerifiedVault.lean)
> 相近的体验——业务程序、typed state/transition 视图和普通 Lean theorem 位于同一个
> `.lean` 文件；Lean kernel 检查 theorem；产品只在证明门通过后继续物化。
> **关键约束**：ProofForge 只能有一个 authoritative executable semantics：
> `SemanticProgramV1 + ReferenceMachineV1`。作者友好的 typed proof view 必须从该语义
> 派生并有 bridge theorem，不能重新实现 `State / Effect / step`。
> **性质**：工程实施规划，不改写 accepted PRD/Architecture/Technical Spec，不关闭
> formal `TASK-D2-07`、`TST-SEM-002/003`、`TST-PROOF-001`，也不声称 target artifact
> 已经被形式化验证。

对齐文档：

- [`ADR-0027`](../adr/0027-inline-same-file-theorem-certification.md)：同文件、单 snapshot、
  Environment/axiom audit 与 proof-before-materialize 基线；
- [`ADR-0034`](../adr/0034-preservation-abi.md)：`PreservationTheoremV1`、positive admission、
  base + full-input Reference step 与 `(invariant, kind)`；
- [`RESEARCH-023`](../research/23-miniamm-formalization-ladder.md)：Reference-first、禁止第二套
  contract-local step、业务形式化与工具内部形式化分账。

---

## 0. 先给结论

### 0.1 “第二套 State / Effect / step”该不该删

**原则上该删**：凡是能独立解释同一个 DSL program、独立决定 state update / rollback /
effects / arithmetic / outcome 的平行 machine，都必须先迁移消费者，再物理删除，不保留
fallback 或 compatibility adapter。

**当前仓库的事实是：这一步已经做过，不应再把它列成尚未完成的代码删除任务。**

| 历史重复面 | HEAD 状态 | 结论 |
|---|---|---|
| `ProofForgeV2/Semantic/MiniAmmSafetySketchV1.lean` | 已删除 | 原 contract-local 手写 `State / Effect / step` 不再是产品路径 |
| `ProofForgeV2/Core/Semantics.lean` | 已删除 | 旧 alpha execution semantics 不再保留 |
| `ProofForgeV2/Core/SemanticIR.lean` | 已删除 | 旧 alpha semantic carrier 不再保留 |
| target/Compiler alpha residual route | 产品消费者已迁到 retained `SemanticProgramV1` | 不恢复第二 carrier/fallback |

所以本规划的第一阶段不是“再删一次不存在的文件”，而是：

1. 固化 semantic authority inventory；
2. 为已完成的 duplicate elimination 增加防回归门禁；
3. 从唯一 Reference semantics 上建设 typed author view。

### 0.2 不能按名字误删

“只有一套语义”不等于仓库中只能出现一个叫 `State` 或 `Effect` 的类型。以下对象不是
平行 runtime semantics，不应仅因重名删除：

| 对象 | 角色 | 是否保留 |
|---|---|---|
| `LogicalStateV1` | Reference machine 的 canonical logical state carrier | 保留，属于唯一语义 |
| `OrderedEffectV1` / `OutcomeV1` | Reference machine 的 effect/outcome carrier | 保留，属于唯一语义 |
| `Typed/CallGraphV1.State`、各 checker `CollectorState` | 编译器遍历/固定点算法的内部状态 | 保留，不解释合约执行 |
| `Typed/EffectCheckV1.EffectKindV1` | 静态 effect analysis/evidence | 保留，不执行 effect |
| Normalize `BodyStateV1` / `StateTableV1` | lowering 构建状态 | 保留，不是 runtime state |
| target Plan/IR/runtime host state | 目标物化或测试载体 | 保留，但必须与 Reference 做 refinement/差分 |
| 未来 `<Program>.Model.State` | 作者 typed projection | 保留，前提是由 canonical state 派生并有 bridge theorem |

判定标准不是名称，而是：**该对象能否在没有 Reference bridge 的情况下独立决定 DSL
程序的执行结果。**

### 0.3 是否必须先证明 ProofForge 所有 DSL 函数

**不需要。** 可以先让作者证明“具体 program 在 Reference semantics 上保持业务不变量”，
同时逐步补齐工具自身元理论。需要区分四层：

| 层 | 证明对象 | 是否是作者开始写 theorem 的前置 |
|---|---|---|
| A. 定义层 | `SemanticProgramV1`、canonical state、Reference step 是明确 total Lean 定义 | **是**；当前已有 engineering 定义 |
| B. Author bridge | typed State/transition/invariant 与 Reference state/step/evaluator 等价 | **是**；本规划的首要新增工作 |
| C. Contract theorem | 某个合约的 init/entry 保持业务谓词 | 可在 A+B 后逐合约推进 |
| D. Tool/backend metatheory | parser/Normalize correctness、Reference 元理论、target artifact refinement | 不阻塞 Reference-level contract theorem；但阻塞更高等级的 artifact-verified 声明 |

因此正确顺序不是“先证明整个编译器，最后才允许写业务证明”，而是：先固定唯一语义，
把作者 API **证明性地接到它上面**，再并行推进具体合约证明与工具/backend refinement。

---

## 1. VerifiedVault 的关键模式与 ProofForge 对应关系

参考 `VerifiedVault.lean` 的有效模式不是“文件里出现了 theorem”这么简单，而是三点：

1. `Spec.State` 和 `deposit?` / `withdraw?` 是纯 Lean 定义；
2. `deposit_preserves_solvent` / `withdraw_preserves_solvent` 直接证明这些 transition；
3. NEAR entrypoint 实际调用同一个 `Spec.deposit?` / `Spec.withdraw?`，避免 model/code drift。

ProofForge 是 deep-embedded DSL，不能照抄其实现方式，但应达到相同的信任结构：

```text
VerifiedVault
  pure Lean transition ───────► theorem
          │
          └───────────────────► runtime entrypoint directly calls it

ProofForge 目标
  DSL ─► SemanticProgramV1 ───► ReferenceMachineV1
                │                       │
                │                       └─► derived typed Model view ─► theorem
                │                                                   │
                └──────────────────────► target materializer         │
                                             ▲                       │
                                             └──── refinement ───────┘
```

二者的“同一份代码”含义不同：

- VerifiedVault：runtime entrypoint 直接调用被证明的纯函数；
- ProofForge：Reference proof view 与 target lowering **共同绑定同一个 exact
  `SemanticProgramV1`**；最终再用 Reference→target refinement 连接 artifact。

如果 ProofForge 作者另写一份独立 `Spec.deposit`，却没有证明它等价于
`stepReferenceSliceV1`，那仍然只是 shadow spec，不能获得 VerifiedVault 的可信度。

---

## 2. 当前工程基线

### 2.1 已有能力

| 能力 | 当前实现事实 |
|---|---|
| 唯一产品 semantic carrier | `CompiledSemanticV1` 私有构造，绑定 exact retained `SemanticProgramV1` 与 digest |
| 唯一 Reference execution | [`ReferenceMachineV1`](../../ProofForgeV2/Semantic/ReferenceMachineV1.lean) 定义 runtime carriers、admission 与纯 total `stepReferenceSliceV1` |
| Canonical logical state | [`InvariantFoundationV1`](../../ProofForgeV2/Semantic/InvariantFoundationV1.lean) 定义 `LogicalStateV1`、state codec/defaults、`StateConformsV1` |
| 真实 Lean Prop | [`InvariantABI`](../../ProofForgeV2/Semantic/InvariantABI.lean) 的 `InvariantTheoremV1`；[`PreservationABI`](../../ProofForgeV2/Semantic/PreservationABI.lean) 的 `PreservationTheoremV1` |
| Exact proof subject | elaborator 已生成 `<Program>.Proof.subjectDataV1`、`subjectBytesV1`、`subjectProgramV1` |
| 同文件认证 | `certifyInlineProofV1` 检查同一 snapshot、exact subject、expected Prop defeq、依赖/axiom/unsafe/extern policy |
| L1 通用性样例 | EvenCounter 与 ZeroCounter 已经通过同一 preserving ABI/product certifier；不是第二 step |
| Structured bridge 地基 | [`SubjectDataBridgeV1`](../../ProofForgeV2/Semantic/SubjectDataBridgeV1.lean)、[`PreservationPackagingV1`](../../ProofForgeV2/Semantic/PreservationPackagingV1.lean)、`PreservationShapeV1` 已开始减少 byte-spine 证明负担 |

### 2.2 当前离目标体验还有什么距离

1. UInt64/空 state 支持子集已有合约本地 typed `State`，但更多 accepted state shape 尚待接线；
   组合 preservation theorem 时仍会暴露 `LogicalStateV1`、raw invocation、responses、vault
   和 full-input gate 义务。
2. 已有首个自动生成的 per-callable typed relation API，但尚缺面向业务证明的
   `deposit s amount = .returned next` 短 executable notation。
3. evaluator-backed typed invariant predicate 与 exact ordinal/evaluator bridge 首切已完成；
   exact `stateLoad; stateLoad; eq; return` 的 UInt64 字段相等首切也已投影成普通 Lean
   `reserves = shares` 并与 evaluator-backed predicate 对齐；更多 expression shape、
   arbitrary-family premise-free exact subject validation packaging 与 arithmetic/lookup bridge 仍待补。
   exact recognized simple-closure、首个 field-comparison 与 stateful-equality family 均已生成
   `Proof.subjectValidationOkV1`，因此该字段样例可直接把 certificate 传给 `_iff_fields`；通用
   generated `_iff_fields` 仍保留 exact `hvalidate`，不支持的 family 不会因此被自动准入。
   generated typed encoder 已有 production-codec success theorem，所以字段相等 bridge 也不要求
   作者手工提供 `LogicalStateV1`/`hencode` witness。
4. `PreservationTheoremV1` 要求 base + 全输入 + 全 callable + 三 Outcome；程序级 composer
   已有，首个真实修改 UInt64 state 且保持字段不变量的 generated typed returned-row theorem
   也已闭合。除 exact name-parameterized `sync(amount)` equality family 外，当前还闭合了
   initializer + 双槽位同参数 checked-add entry + 双 guard checked-sub Unit entry + read-only
   view + equality invariant family：production validation/admission、initializer base、两个 entry
   的 returned success、assert/overflow/revert/trap rollback 与五个 callable row 组装共同得到最终
   Reference-level `PreservationTheoremV1`；但 arbitrary callable/expression family 的同类
   packaging 仍待补。
5. ClosedSubjectPin/contract-specific golden 可以加速已知样例，但不能成为任意合约的主证明通道。
6. [`Examples/MiniAmmL1.lean`](../../Examples/MiniAmmL1.lean) 当前只有 executable
   `emptyPool` invariant 与 Normalize/Reference admission 正例，没有同文件 proof binding 和完整
   `PreservationTheoremV1`；`MiniAmmEmptyPoolV1` 又只是缩小的 closed instance，不能冒充完整 vault。
7. 多数 target 仍对 nonempty invariants fail closed；NEAR 已按 ADR-0042 首切开放
   proof-bearing invariant-root erasure，要求 private certificate、exact source/semantic binding、
   complete preserving coverage 与 versioned Plan partition。普通 capability 与其他 target 仍
   fail closed。
8. 尚无 Reference→target artifact 的完整 refinement theorem，故当前最多声明
   “Reference semantics 上已认证”，不能声明 emitted Wasm/EVM/SBPF 已形式化验证。

---

## 3. 唯一语义架构合同

### 3.1 Authoritative path

固定唯一权威链：

```text
ProgramV1
  → CheckV1 / NormalizeV1
  → SemanticProgramDataV1
  → structure-gated SemanticProgramV1
  → admitReferenceProgramSliceV1
  → stepReferenceSliceV1
  → OutcomeV1(returned | reverted | trapped)
```

下列行为只能由该链定义：

- checked arithmetic / cast / aggregate codec；
- state load/store、初始化与 atomic rollback；
- context、external responses、vault seed；
- ordered effects 与 effect occurrence；
- returned/reverted/trapped 分类；
- invariant evaluator 所调用的 selected callable semantics。

### 3.2 Derived typed proof view 的合法形状

typed proof view 可以包含 `State`、`deposit`、`withdraw`、`Effect` 等作者友好名称，但必须满足：

1. 从 `<Program>.Proof.subjectDataV1` / `subjectProgramV1` 生成，不重读 source AST；
2. state 通过 canonical codec 与 `LogicalStateV1` 往返；
3. transition 的定义体调用 `admitReferenceProgramSliceV1` /
   `stepReferenceSliceV1`，或其 relation 直接包含同一 step equality；
4. effects 只是 `OrderedEffectV1` 的 typed projection，不重新决定 effect 顺序/提交；
5. invariant predicate 有 theorem 等价到 `evalInvariantV1 = .returnedTrue`；
6. 所有隐藏参数都必须有静态无关性证明；不能把 context/responses/vault 默认为空后声称全称；
7. 每个 wrapper/refinement theorem 对 exact subject program 参数化，不能 hash-only cast；
8. 不支持的 DSL shape 在 Model API 生成阶段 fail closed，不能 fallback 到手写 interpreter。

### 3.3 Duplicate semantics 判定门

新增实现若同时满足以下前三项，且不满足第四项，应视为第二套语义并拒绝：

1. 接受 DSL/Semantic program 或重建其业务逻辑；
2. 对 invocation 产生 state/effect/outcome；
3. 自己定义 arithmetic/rollback/effect ordering 中任一可观察规则；
4. 定义体直接复用 Reference，且有 kernel-checkable exact bridge theorem。

禁止用 `structure State`、`def step` 等名字的简单文本扫描代替这项架构判定；那会误杀 checker
state、target IR 和合法 typed projection。

---

## 4. 目标作者 API

以下是**目标体验草图，不是当前已存在 API**。最终命名以实现切片和 ADR 评审为准。

```lean
import ProofForgeV2

open ProofForgeV2.Language

program VerifiedVaultPF where
  state reserves : UInt64
  state shares : UInt64

  init() do
    reserves := 0
    shares := 0

  entry deposit(amount : UInt64) : UInt64 do
    reserves := reserves + amount
    shares := shares + amount
    return shares

  entry withdraw(amount : UInt64) : Unit do
    assert amount <= reserves
    assert amount <= shares
    reserves := reserves - amount
    shares := shares - amount

  view status() : UInt64 do
    return reserves

  invariant solvent : reserves == shares
  proof solvent preserving using VerifiedVaultPFProof.solvent

namespace VerifiedVaultPFProof

open VerifiedVaultPF.Model

theorem init_establishes_solvent
    {next : State} {input : InitInput}
    (hn : init input = .returned next) : solvent next := by
  -- `init` 从 `initialLogicalStateV1` 的 pre-init state 派生；
  -- 这里量化全部合法 typed initializer inputs。
  ...

theorem deposit_preserves_solvent
    {s next : State} {amount : UInt64}
    (h : solvent s)
    (hn : deposit s amount = .returned next) :
    solvent next := by
  -- 普通 Lean 数学证明；不操作 canonical bytes。
  ...

theorem withdraw_preserves_solvent
    {s next : State} {amount : UInt64}
    (h : solvent s)
    (hn : withdraw s amount = .returned next) :
    solvent next := by
  ...

theorem solvent : VerifiedVaultPF.ProofPreserving.solvent := by
  apply VerifiedVaultPF.Model.preserveSolvent
  · exact init_establishes_solvent
  · exact deposit_preserves_solvent
  · exact withdraw_preserves_solvent
  -- malformed input、view/state-stutter 与 revert/trap unchanged
  -- 由 exhaustive generic packager 消除。

end VerifiedVaultPFProof
```

### 4.1 目标 API 分层

| 层 | 示例 | 性质 |
|---|---|---|
| Raw subject | `VerifiedVaultPF.Proof.subjectProgramV1` | exact canonical identity，certifier authority |
| Structured subject | `VerifiedVaultPF.Proof.subjectDataV1` | proof bridge 输入，不是第二 carrier |
| Typed model | `VerifiedVaultPF.Model.State`、字段 projection | canonical logical state 的派生 view |
| Callable transition | `Model.deposit` / `Model.Deposit` | Reference step 的 typed wrapper/relation |
| Typed invariant | `Model.solvent : State → Prop` | DSL invariant evaluator 的逻辑投影 |
| Business lemmas | `deposit_preserves_solvent` | 作者普通 Lean theorem |
| ABI packaging | `Model.preserveSolvent` | per-callable lemmas → exact `PreservationTheoremV1` |
| Product binding | `ProofPreserving.solvent` + inline certifier | exact program/ordinal/kind + trust audit |

### 4.2 Function API 与 relation API

为了不伪造 admission 或失败语义，内部先以 exact relation 为 canonical proof surface：

```lean
def Deposit
    (admitted : AdmittedReferenceSliceV1)
    (hadmit :
      admitReferenceProgramSliceV1 subjectProgramV1 = .ok admitted)
    (s : State)
    (amount : UInt64)
    (context : DepositContext)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1)
    (next : State) : Prop :=
  ∃ pre post value effects,
    encodeState s = .ok pre ∧
    encodeState next = .ok post ∧
    stepReferenceSliceV1 admitted pre
      (depositInvocation amount context) responses vault =
        .returned post value effects
```

program-level packager 先构造**一个** positive admission witness，base 和所有 callable relation
共享同一个 `admitted`；不得由每条业务 lemma 各自选择存在 witness。在已经证明 determinism、
typed decode totality和 valid-input specialization 后，再提供较短的
`deposit s amount = .returned next` notation。该短 notation 只表示该 callable 的 exact 合法
context/response schedule（例如确实要求空 context/空 responses 的路径），**不**等价于对任意 raw
`InvocationV1` 输入量化；malformed/extra context、trailing responses 等仍由全输入 packager 分类为
Reference failure。vault 只有在有真正的 independence theorem 后才能隐藏。

---

## 5. 实施阶段

### Phase 0 — 语义权威审计与 duplicate elimination guard

**状态**：已完成。重复实现已删除，`alpha-deletion-gate` 已固定物理删除与禁止回流。

交付：

1. 冻结 semantic authority inventory：
   `SemanticProgramV1`、`LogicalStateV1`、`ReferenceValueV1`、`InvocationV1`、
   `OrderedEffectV1`、`OutcomeV1`、admission、Reference step、invariant evaluator。
2. 增加 architecture/deletion gate，拒绝：
   - 已删除 legacy module/symbol/import 回流；
   - product target/ProofInstances 绕开 `CompiledSemanticV1` / Reference；
   - contract-local module在 `ProofForgeV2/Semantic/` 定义独立执行 step；
   - proof path 读取 target-specific Plan/IR 作为业务 theorem subject。
3. 门禁按 ownership/import/behavioral surface 判断；不禁止普通 `State` 名。
4. 在代码注释和文档中统一使用 “sole Reference step” 术语。

退出条件：

- 产品中只有 `stepReferenceSliceV1` 能从 admitted semantic + runtime inputs 产生
  canonical `OutcomeV1`；
- 所有 target 仍只从 retained `SemanticProgramV1` lowering；
- 所有 L1 proof package 最终目标仍是 `PreservationTheoremV1`；
- 已删除路径/alpha carrier 无引用、无 fallback、无 feature flag。

### Phase 1 — 生成 typed State view 与 codec bridge

**状态**：UInt64/空 state table 首切已完成，并已对 generated typed state 证明 production
encoder success；其余 accepted scalar/aggregate shape 待扩展。

主要落点：program elaborator + 新的 program-agnostic Model bridge（避免每个 contract 一个平台模块）。

交付：

1. 从 `subjectDataV1.logicalState` 生成 `<Program>.Model.State`：
   - 字段顺序与 `StateIdV1` exact；
   - 字段类型由唯一 TypeId/TypeShape 映射；
   - `State` 表示 `initialized=true` 的 typed business state；pre-init lifecycle 由单独的
     `LifecycleState`/initializer relation 表达，不能静默丢掉 `LogicalStateV1.initialized`；
   - visibility 不改变运行时值，只影响作者可陈述/披露的 API。
2. 生成/提供通用：
   - `encodeState : Model.State → Except … LogicalStateV1`（结果 initialized=true）；
   - `decodeState : LogicalStateV1 → Except … Model.State`；
   - `decode_encode`、`encode_decode_of_conforms`；
   - `StateConformsV1 program logical ↔
     ∃ typedState, encodeState typedState = .ok logical`；
   - 必要的 encode injectivity / field projection lemmas。
3. 明确处理 codec totality：
   - 若 `Model.State` 的字段类型已把全部 canonical size/resource bounds 编入类型，
     `encodeState` 可进一步证明 total；
   - 否则保持 `Except`，所有 relation 必须携显式 `.ok pre/.ok post`；
   - 当前 Bool/UInt64 generated scalar 已通过
     `encodeLogicalStateValuesV1_exists_of_pairs` 证明唯一 production encoder 必然存在
     successful result，并生成 `Model.encode_exists`；该 theorem 的 declaration/value pair
     只用于证明 source-order identity 和 canonicality，不是第二 encoder；
   - 对每个 conforming logical state，必须证明存在**唯一** typed decode，不能只证
     typed→logical 单向 soundness。
4. 首切支持 Bool、UInt8/16/32/64、Unit；随后按 canonical Wire codec 扩 Struct/Enum/
   Option/Array/Map/Bytes/Principal，不能另写 proof-only codec。
5. 对 recursive/unsupported shape fail closed，并给稳定 elaboration diagnostic。

退出条件：

- 一个未 pin 的新 program 可以只通过 `subjectDataV1` 获得 typed State；
- 作者证明不需要 unfold `ByteArray` spine；
- codec roundtrip theorem 调用 production Wire/LogicalState codec，不复制 encoder/decoder；
- `StateConformsV1` 与 typed state 表示在支持子集上双向 complete/unique。

### Phase 2 — 生成 per-callable typed transition view

**状态**：进行中。entry/view 的 UInt64 参数、Unit/Bool/UInt64 result codec/relation、三分支
packaging、full-outcome relational totality、outcome uniqueness 与 returned state/result 唯一 typed
decode 已完成；独立的 generated pre-init `LifecycleState`、initializer params/result/relation、
三分支 packaging、outcome totality/uniqueness 与 returned post-state 唯一 typed decode 也已完成。
全 raw-input gate partition、面向 preservation packager 的组合 bridge 与 executable 短 notation尚未完成。

交付：

1. 生成一个 program-level positive admission certificate/carrier；initializer base 与所有
   callable transition共享同一个 admitted witness。
2. 为 pre-init lifecycle 建立 canonical bridge：
   - exact `initialLogicalStateV1 subjectProgramV1 = .ok preInit`；
   - preInit 的 `initialized=false` 与 typed `LifecycleState` 对齐；
   - initializer relation 从该 pre-init state 调用 sole Reference step；
   - every returned initializer post 必须能唯一 decode 为 typed initialized `State`。
3. 对 initializer/entry/view 生成 typed params/result/invocation constructor。
4. 定义 canonical relation，直接包含 exact admission + codec success + Reference step equality。
5. 在可证明 deterministic/total 的 admitted valid-input 子集上导出 executable function notation。
6. 保持 `OutcomeV1` 三分支，不压成 `Option State`：
   - returned：typed post/value/effects；
   - reverted：reason + exact unchanged pre；
   - trapped：fault + exact unchanged pre。
7. 为每个支持 callable 证明**双向 full-outcome bridge**：每个 Reference returned post
   必须有唯一 typed decode，typed returned/reverted/trapped 也必须对应同一 Reference outcome；
   不能只覆盖“恰好能找到 typed next”的成功子集。
8. context、responses、vault：
   - callable 真正使用时出现在 typed API；
   - 短 notation 只可固定 exact valid context/response schedule，不能冒充任意 raw input；
   - vault 只有通过 Reference independence theorem 证明无关时才可隐藏；
   - external call/schedule 的 effect observation 保留 source order/occurrence。
9. view/state-stutter、revert/trap unchanged 等通用事实由 machine lemma自动提供。

退出条件：

- 作者可以对简单 entry 写 `deposit` 保持 theorem，而不直接构造 `InvocationV1`；
- 展开 transition 后只有 `stepReferenceSliceV1`，无第二 arithmetic/rollback/effect implementation；
- pre-init/initializer 与 initialized entry/view lifecycle 均有 exact bridge；
- 支持的 valid typed invocation 与 Reference full outcome 双向 complete；
- malformed/extra raw inputs 由 generic gate partition 覆盖后，full-input
  `PreservationStepV1` 可由 typed callable lemmas回推。

### Phase 3 — Typed invariant 与 evaluator bridge

**状态**：进行中。已生成 `<Program>.Model.<inv> : State → Prop` 的 evaluator-backed
首切及 exact `evalInvariantV1` bridge；并已对 exact lowered
`stateLoad left; stateLoad right; Eq/Ne; return` UInt64 shape 生成字段比较数学 bridge
（Eq 投影为 `=`，Ne 投影为 `≠`）。
该字段 bridge 已用 generated `Model.encode_exists` 内部取得 production encoding witness，
作者只需提供 exact subject validation premise。simple-closure 与首个 exact field-comparison
family 已有 premise-free exact `Proof.subjectValidationOkV1`；该能力尚未扩展到任意 lowered
family，故通用 bridge 的 premise 不删除。更广 expression 投影、通用 validation packaging、
checked arithmetic/lookup 通用引理与业务 proof ergonomics尚未完成。

交付：

1. 将 DSL invariant expression 投影为 `<Program>.Model.<inv> : State → Prop`。
2. 证明 exact 双向桥：

   ```lean
   theorem solvent_iff_eval
       (hencode : encodeState typedState = .ok logical) :
       Model.solvent typedState ↔
         evalInvariantV1 subjectProgramV1 ordinal logical = .returnedTrue
   ```

   exact 两字段 Eq/Ne shape 还生成 `<inv>_iff_fields`：

   ```lean
   theorem solvent_iff_fields
       (typedState : Model.State)
       (hvalidate : validateSemanticProgramV1 subjectProgramV1 =
         .ok subjectDataV1) :
       Model.solvent typedState ↔
         typedState.reserves = typedState.shares
   ```

   `Model.encode_exists typedState` 从 production codec 内部提供 logical carrier 与
   successful encode equality，不要求业务作者手工构造 witness。exact `hvalidate` 仍显式保留；
   在 generated subject data 与 production validation result 的 exact identity bridge 完成前，
   不借 admission carrier 偷换 validated data，也不用 closed reduction 或第二 evaluator 隐藏它。

3. checked arithmetic/trap 边界必须与 invariant evaluator一致；不能把 partial evaluator
   简化成无条件数学运算。
4. 作者允许定义更高层 `Spec.solvent`，但要获得产品 certification，必须提供
   `Spec.solvent ↔ Model.solvent` 或足够方向的 refinement lemma。
5. 逐步提供 UInt arithmetic、Bool connective、Struct/Map lookup 等通用 evaluator lemmas。

退出条件：

- 业务 theorem 全部陈述在 typed State/predicate 上；
- packaging 到 `InvariantTheoremV1` / `PreservationTheoremV1` 时无需 contract-specific
  evaluator 重写器；
- ordinal、invariant name、subject program 仍由 generated exact binding 决定。

### Phase 4 — Per-callable theorem composition 与 preservation packager

交付：

1. packager 先要求一个 generated positive admission certificate，并在 base 与整个 step
   proof 中共享该**同一个** `admitted`；禁止 per-callable `∃ admitted` 拼接或 implication 空真。
2. 生成每个 invariant 的 program-specific proof skeleton/combiner：
   - initializer base；
   - 每个 entry returned preservation；
   - view/state-stutter；
   - revert/trap unchanged；
   - full invocation/context/responses/vault coverage。
3. callable table 枚举之外，还必须对 `gateInvocation` 建立 exhaustive partition：
   - 合法 initializer/entry/view roots；
   - invariant/pureFn 被当作普通 invocation root；
   - out-of-range callable id；
   - malformed args/context；
   - lifecycle failure；
   - missing/extra/reordered responses 与其他 Reference gate/finalization failure。
   只有合法 business root 的 returned 分支交给作者 lemma；其余分支由 generic machine
   unchanged/failure lemmas关闭。
4. callable coverage 从 exact `subjectDataV1.callables` 枚举；新增 callable 后旧 aggregate proof
   必须 fail closed，不能遗漏后继续 certified。
5. generic packager 最终生成 exact：

   ```lean
   PreservationTheoremV1 subjectProgramV1 ordinal
   ```

6. positive admission/initial obligations保持显式；不能通过 implication 在 unsupported program 上空真。
7. ClosedSubjectPin 降为 regression/golden 性能优化；任意新 contract 不注册 pin 也能完成证明。

退出条件：

- 作者主要义务是 init + 有状态 entry 的业务 lemma；
- 新增/删除/reorder callable、改变 invariant ordinal、改变 exact semantic bytes 都使旧证明失配；
- 包装层不包含 program-specific state transition implementation。

### Phase 5 — Same-file authoring 与 certifier 体验

**状态**：exact initializer + 双槽位同参数 checked-add deposit + 双 `<=` guard checked-sub
Unit withdraw + read-only view + two-field equality family 的 business slice 已闭合；通用
arbitrary-family 作者体验仍在进行中。真实 `VerifiedVaultPF.lean` 已由同一文件内 ordinary
Lean theorem 通过产品 certifier 与 CLI `check`。alpha-renamed 五 callable 同构 family 同样可
认证；删除任一 store/sub、改变 subtraction state/value flow、漏/reverse assert、用覆盖赋值
替代 subtraction、改变 withdraw result shape 或 callable order 的 typed-valid near miss 都会在
certification elaboration 阶段 fail closed。

交付：

1. Elaborator 在同一 program namespace 生成稳定 `Model` + `Proof` +
   `ProofPreserving` declarations。
2. Certifier继续强制：
   - 同一 in-memory source snapshot；
   - exact generated subject bytes/program；
   - theorem kind/type defeq；
   - dependency closure 与固定 axiom policy；
   - proof fail 严格早于 target resolve/materialize。
3. 在不降低 Environment audit 的前提下，为真实业务 theorem开放最小必要 proof syntax/tactic
   集合；拒绝 `sorry`、user axiom、unsafe/partial、arbitrary `run_tac`、未经允许的 native shortcut。
4. 提供稳定 diagnostics：缺 base、漏 callable、typed view unsupported、admission fail、
   theorem wrong subject、axiom dependency 分开报告。
5. 保持 identity 边界：theorem body 改变 certification digest，但不改变
   ProgramV1/SemanticProgramV1 业务 identity。

退出条件：

- 未 pin、无 package-owned contract theorem 的同文件业务证明可被 product `check` certified；
- false theorem、foreign subject、partial callable coverage、disallowed axiom 全部 fail closed；
- 生成 API 的名字冲突、namespace nesting、多 program 文件均有正负例。

### Phase 6 — `VerifiedVaultPF.lean` 纵向样例与 proof-bearing build

本阶段拆成两个不互相冒充的子阶段：

- **Phase 6A — Reference-certified author slice**：只要求产品 `check`，不触碰 target
  materialization authority，因此无需 invariant-erasure amendment。initializer + checked-add
  deposit + 双 guard checked-sub Unit withdraw + read-only status + equality invariant 已完成；
  exact subject、positive Reference admission、sole Reference execution、五 callable preservation、
  same-file theorem、product certifier 与真实 CLI `check` 已闭环。
- **Phase 6B — proof-bearing target build/runtime**：ADR-0042 与 NEAR target amendment 已落库，
  并按 private certificate authority、exact digest/coverage binding、derived callable partition、
  canonical Plan attestation 与 ordinary-path fail-closed 实现。`VerifiedVaultPF build --target near`
  已用 locked `wat2wasm` 产出 deployable Wasm/ABI；runtime corpus 已接入 exact KV slots、Unit
  withdraw、overflow/guard rollback 与 missing invariant export。2026-08-11 已在当前 GLIBC 2.36
  orb 中以 Ubuntu Noble `libc6 2.39-0ubuntu8.8` userspace loader 启动原始 locked
  near-sandbox 2.13.0，required 模式完整十套 corpus 全部 PASS；未以 wrapper 替换 locked
  executable。6B 因此达到 **NEAR engineering runtime observed**，但兼容 loader 尚非 Tool Lock
  资产，该运行不是 hermetic release evidence，也不构成 formal target refinement。

6A/6B 最终共同交付一个真实单文件样例，不使用缩小 golden 替代完整业务程序：

1. state：`reserves` / `shares`；
2. init：两者归零；
3. deposit：checked add 两者；
4. withdraw：guard + checked sub 两者；
5. view/status；
6. executable invariant：`reserves == shares`；
7. 同文件 ordinary Lean lemmas：initializer、deposit、withdraw、aggregate preserving theorem；
8. `proof solvent preserving using …` 经产品 inline certifier 为 `.certified`；
9. 不依赖 ClosedSubjectPin、contract-specific `ProofInstances/*` 或第二 step。

同时定义 proof-bearing materialization 纪律：

- invariant callable 是 compile-time proof subject，不是公开 runtime entry；
- target 可在 proof gate 后擦除/不物化 invariant callable，但该 erasure 必须是显式、版本化的
  Plan 决定，并有“业务 invocation/state/effect observation 不变”的通用证明或至少 engineering
  validation；
- erasure 只允许移除 invariant roots；被 business callables 与 invariant closure 共同引用的
  pureFn 必须保留，不能按“proof closure”粗暴删除；
- business callable id、ABI、state/effect observations 必须保持 exact；
- amendment 定义的 validated slice 之外一律 fail closed；
- 不得因为 target 暂不支持 invariant runtime callable 就丢弃整个已经认证的 program；
- 首个纵切优先 NEAR，随后复用同一 policy 到其他 materializer。

退出条件：

- `check`：同文件 proof certified；
- `build --target near`：证明门先通过，artifact 来源仍是 exact compiled semantic；
- locked NEAR runtime/differential 覆盖 init/deposit/withdraw/status、overflow/underflow rollback；
- 兼容 runner 实际通过前只声明 “Reference-verified + NEAR artifact engineering built”；通过后
  才能升级为 runtime-observed engineering evidence，两者都不是 target-refined formal。

### Phase 7 — Reference → target refinement（独立长期轨道）

这是从“模型上证明”升级到“最终 artifact 被证明”的必要阶段，不能由同文件 theorem 替代。

2026-08-11 已落下 NEAR VerifiedVault `status` 的第一块**静态对齐地基**：

- `StaticAlignmentV1` 只声明 passive call/storage observation carrier，不执行或更新 target state；
- scalar public UInt64 logical state 已与 initialized marker、physical KV field、8-byte LE value
  建立 proposition-only representation relation，并钉住 nullary/empty-input/UInt64-return ABI；
- successful return relation显式要求 canonical 8-byte result、Reference post=pre、ordered effects
  为空、target logs/promises为空和 target pre/post storage observation相等；failure relation要求
  Reference failure携 exact pre-state且 target observation无 commit；
- exact VerifiedVault semantic subject 的独立 candidate `status` Method/MethodIR shape 已满足静态
  relation，追加 store 会 fail closed；production 现以 `KeyRegionsV1` / `PlanIRLoweringV1` exact
  successful graph连接 materialized Plan、private canonical key constructor 与 validated lowering，
  并导出 source Plan、keys、method array及 entry-index MethodIR provenance；没有新增第二个
  Plan→IR constructor；
- 测试已在 exact VerifiedVault subject 上复用 production logical-state codec roundtrip 与
  `stepReferenceSliceV1_ready_viewLoad_returned_exact`：对任意长度 ready overlay 和空 external
  responses，固定 successful status 的完整 Reference outcome 为逻辑 state不变、返回被加载的
  canonical UInt64、ordered effects 为空；同一 theorem fixture 把该真实 Reference step 与
  initialized KV representation、nullary/empty-input ABI、passive successful observation relation
  合并成一个 kernel-checked proposition。真实 same-file certification fixture 继续经过
  certified capability → production Plan →
  production IR，固定 status 为 Plan entry 2 / IR method 3，携带 concrete
  `MethodIRLoweringV1` evidence；第三静态切新增 public proof-producing Method/MethodIR syntax
  recognizer，把动态 production 值恢复成 exact nullary UInt64 view 与四操作 static recipe。
  production relation 同时保留 capability 内 semantic carrier 的 validated-data 等式、UInt64
  semantic/storage binding、canonical key lookup 与 Plan→IR provenance，因此不是依赖另一份
  test golden literal。它只刻画本次 production output，不是一般 private lowering correctness；
- 第五静态切把 invocation readiness 的公开证明边界收窄到 sole production context gate：
  `emptyInvocationContextAcceptedV1` 只是 private context validator 对 supplied empty snapshot 的
  success projection，bridge 从 `true` 恢复原 validator 的 exact `some #[]`，随后
  `gateInvocation_ready_nullary_view_of_checksV1` 只组合 production callable lookup、view/arity、
  initial-state constructor、`StateConformsV1`、logical-state decoder 与该 context 结果，推出原
  `gateInvocation = .ready ...`；它没有第二次收集 context，也没有新增 invocation evaluator。
  VerifiedVault fixture 现从真实 generated subject 闭合 validation、Reference admission、admitted
  data identity、initializer presence、initialized state conformance、两槽 decode、status row lookup
  和 exact ready gate，不再要求调用者直接提供整个 `hgate`；
- 第六静态切删除上述最后一个 context premise：public、total 的
  `directInvocationContextFreeV1` 只检查单个 callable 是否完全不含 `ContextRead` / `PureCall`，
  是 empty context closure 的充分语法证书，不验证 supplied context、CFG、identity，也不计算
  transitive closure。sole production collector 先按 `root.id` 从 validated data lookup
  authoritative row，再在该 row 获证时返回 `some #[]`；含任一相关 op 时仍走原 private bounded
  worklist traversal，lookup 失败及 malformed/callee failure 仍 fail closed。因 fast path 不信任
  caller-supplied body，mismatched-root regression 已固定同 id forged root 不能绕过 context gate。
  `VerifiedVault.status` 的真实 authoritative row 只有 `StateLoad`，因此 certificate 由 kernel
  `simp` 闭合，并经 lookup equality 推出 production empty-context acceptance；ready theorem与
  exact Reference outcome composition 现在均无外部 context premise。这里没有第二套 context
  closure checker、gate、evaluator 或 step，private traversal 也未公开。
- 第七静态切把同一 certified capability 继续接到 sole private production emitter：
  proposition-only `IREmissionV1` 只是 `emitFromIR ir = .ok files` 的成功图，既不公开或复制
  WAT/ABI renderer，也不定义第二套 emission relation。`buildFromCapability_eq_ok_graphsV1`
  从 capability build success 恢复同一个 exact production Plan、同一个 validated Plan→IR graph、
  同一个 IR，以及该 IR 到 exact in-memory `OutputFile` array 的 emission graph；派生 shape theorem
  固定有序的 `<name>.wat` / `<name>.near-abi.json` 两文件 envelope（包括路径和 media type），
  而 exact graph 同时绑定 private renderer 产生的 content strings。真实 VerifiedVault fixture
  使用同一个 capability、Plan、IR 与 build result，以安全 optional lookup 拒绝 missing、
  reordered、duplicate、extra file 和 forged media type，并把已有 status MethodIR provenance
  接到该 exact production base output；没有 test-only lowering、emitter 或 renderer。
- 第八静态切把 successful passive observation relation 的 **Reference 侧义务**收成可复用 theorem：
  `uint64ReturnedObservationRelV1_of_readyViewLoad` 只从 sole production ready gate、admitted-data
  identity、UInt64/state row 与 overlay lookup 推出 production decoder 已接受返回 bytes、exact
  8-byte width，以及唯一 `stepReferenceSliceV1` 的 state-stutter / empty-effect returned outcome。
  theorem 不接受调用方提供 `hstep`、canonicality 或 size；target success、return bytes、logs、
  promises 与 storage snapshot equality 仍逐项作为 externally supplied passive-observation premises。
  真实 VerifiedVault fixture 通过该 API 组合原 static/KV/ABI 关系，错误 target return bytes 明确
  不能满足 relation；没有从 MethodIR/WAT/emission provenance 推导这些 target facts，也没有新增
  target transition、evaluator、State、Effect 或 step。
- 第九静态切把 exact status MethodIR 进一步定位到 sole production renderer 的有序 WAT methods
  block：`MethodWATEmissionV1` 同时绑定 `ir.methods[methodIndex]?`、private `renderMethod` 的 exact
  method text、按 `take/drop` 得到的 index-specific methods block 分解、private `renderWat` 的
  complete WAT text，以及该完整 methods block 在 exact WAT 中的嵌入。它不是任意全局 substring
  断言；即使不同 method 渲染成相同 text，归属仍来自有序 methods block 的 exact index split。
  `irEmissionV1_methodWATEmissionV1` 只从 `IREmissionV1`、exact `files[0]?` 与 method lookup 派生
  该关系。真实 VerifiedVault capability/build fixture 已把 method 3 的 production `statusIR` 接到
  同一次 build 的 WAT `OutputFile`，并证明在完整 WAT 后追加 forged suffix 后不存在任何
  method-text witness。renderer framing 由 `renderWat` 与证明共同复用同一 private helper，没有
  复制 renderer 或建立第二套 emitter。
- 第十静态切对同一次 emission graph 的 ABI 侧做 method-scoped closure：
  `MethodABIEmissionV1` 同时绑定 initializer+entries 的 exact Plan-method index、private
  `renderMethodJson` 的 exact fragment、按 `take/drop` 得到的 ordered rendered-method list、
  private `renderAbi` 的 complete JSON text，以及完整 exports text 在 exact ABI file 中的嵌入。
  `irEmissionV1_methodABIEmissionV1` 只从 `IREmissionV1`、exact `files[1]?` 和 Plan-method lookup
  派生该关系。真实 VerifiedVault fixture 已把 entry 2 / combined index 3 的 `status` Method 接到
  同一次 production ABI `OutputFile`，并证明 appended forged JSON suffix 不存在任何 method-text
  witness。ABI renderer 与证明复用同一 private pre-exports framing helper，没有复制 renderer。
- 第十一静态切把前两项 method-scoped graph 收束为一个 source-entry provenance carrier：
  `EntryBaseEmissionV1` 同时绑定 exact Plan entry `entryIndex`、由既有 private lowering 得到的
  MethodIR `entryIndex + 1`、方法名保持、同一个 `IREmissionV1` 的 WAT/ABI base-file lookup，
  以及同一 combined index 上的 `MethodWATEmissionV1` / `MethodABIEmissionV1`。initializer 仍独占
  combined index 0；`irEmissionV1_entryBaseEmissionV1` 只组合既有 Plan→IR 与 renderer graph，
  不解析或重渲染文本。真实 VerifiedVault fixture 现以 entry 2 / combined index 3 为 `status`
  构造该 combined witness；把 ABI content 追加 forged suffix 并替换同一 base-file array 后，
  不存在任何 combined method-text witness。该 carrier 证明两侧来自同一次 in-memory production
  emission 与同一个 source entry，并不证明 WAT↔ABI consumer/semantic consistency。
- 第十二静态切把此前分散的 capability、semantic、Plan/IR、static alignment 与 entry emission
  witness 收束为单一 capability-scoped kernel chain：`CapabilityEntryStaticEmissionV1` 同时保留
  capability 中 exact retained `SemanticProgramV1`、该程序的 validated data、同一个
  `planFromCapability` / `irFromCapability` / `buildFromCapability` success、
  `ProductionNullaryUInt64ViewStaticAlignmentV1`，以及同一 source entry 的
  `EntryBaseEmissionV1`。constructor theorem 只组合既有 production graph，不调用替代 Plan
  constructor、lowering、renderer 或 emitter，也不解析 WAT/JSON。真实 VerifiedVault fixture 已从
  同一 capability 为 `status` 构造该 witness；把 ABI content 追加 forged suffix并替换 base-file
  array 后，对任意 WAT/ABI method-text witness 都不能构造整个 capability-scoped carrier。
- 第十三切把真实 near-sandbox `status` query 接到此前故意保留的 passive-observation 边界：
  `runtime-tests/near/observation_v1.py` 严格映射 export name、exact empty input、raw result bytes、
  success flag、UTF-8 logs、empty promise/receipt boundary 与调用前后完整 KV snapshot；
  `NearClient.observe_view` 在同一 query 前后抓取 storage，VerifiedVault runtime suite 用 exact
  8-byte LE expected value执行 relation-side字段检查。错误宽度/值、failure、额外 log/promise/receipt
  与任意 storage mutation 均由 no-tool mutation self-test fail closed；Lean relation另固定
  failure/log/promise negatives。该 adapter 只把外部 RPC observation 结构化，不运行 Reference step，
  不定义 target transition，也不把 near-sandbox 提升为 formal semantics。

这仍然只是 **static alignment/refinement foundation**：Reference outcome 已精确闭合且
validated SemanticProgram → capability-gated production Plan/IR → status static alignment → exact
same-emission WAT+ABI 的 provenance 已由一个 capability-scoped carrier 连接；sandbox observation
现在可严格映射到同字段工程契约，但仍是外部提供的 passive carrier。没有证明
WAT renderer 实现 IR、没有 JSON/WAT parser/typechecker semantics、没有 WAT↔ABI consistency、
没有 NEAR `Operation` execution
semantics、IR/Wasm step、simulation theorem、一般 lowering characterization、locked `wat2wasm`
正确性、finalized Wasm bytes 或磁盘 artifact identity theorem。`NearHostModel` 继续是 private
test-only engineering model，不能作为 formal target semantics。当前声明仍是
**Reference-verified + NEAR engineering runtime observed ≠ formally target-refined**。

每个 target 至少需要：

1. state representation relation：logical state ↔ storage/account/KV/witness；
2. invocation/ABI decode relation；
3. checked arithmetic、rollback、return/revert/trap 对齐；
4. ordered effect relation（event/call/schedule/promise）；
5. Plan/IR validation 与 lowering simulation；
6. artifact/toolchain identity 绑定；
7. executable differential corpus 作为工程回归；
8. kernel-checkable refinement theorem或正式验证证据，才能升级 artifact claim。

优先顺序：NEAR VerifiedVault slice → EVM → Solana → 其他 target；每个 target 独立关闭，
不能用一个 target 的 refinement 为其他 target 背书。

---

## 6. 声明等级与可信边界

| 等级 | 可以声明 | 仍不能声明 |
|---|---|---|
| L0 — Lean theorem checked | ordinary theorem 通过 kernel/audit | theorem 与当前 DSL subject 已正确绑定 |
| L1 — Reference-certified contract | exact subject + `PreservationTheoremV1` + inline certifier 通过 | emitted target artifact 与 Reference 等价 |
| L2 — Engineering target observed | L1 + locked build + runtime/differential corpus | kernel-checkable target refinement / hermetic release |
| L3 — Target-refined | L1 + exact target identity + accepted refinement evidence | 未覆盖的 target/network/toolchain |

产品 UI/manifest 必须使用可机器区分的状态，禁止只显示模糊的 `verified=true`。

推荐最小字段：

- `proofKind = preserving`；
- `proofSubjectSemanticDigest`；
- `proofCertificationDigest`；
- `assurance = reference-certified | target-observed | target-refined`；
- `targetRefinement = none | <versioned evidence ref>`。

这些字段不得回写或改变 `SemanticProgramV1`；正式 OutputSet identity 接线须另行规格化。

---

## 7. 测试与验收矩阵

### 7.1 架构门

- deleted legacy files/imports/symbols 不回流；
- proof packages 不定义独立 invocation→state/effect/outcome machine；
- targets 只消费 `CompiledSemanticV1.semanticV1Of`；
- generated Model transition 展开/桥接到 sole Reference step；
- 不对普通 checker `State` / `Effect` 类型做误报。

### 7.2 Typed bridge

- state encode/decode roundtrip 与 malformed/noncanonical negatives；
- aggregate、visibility、default/initialized 边界；
- callable params/result/context typed mapping；
- returned/reverted/trapped 三分支；
- context/responses/vault relevant/irrelevant 对照；
- invariant typed predicate ↔ evaluator exact bridge。

### 7.3 Composition

- init base positive；initial/admission error 不能空真；
- 每个 mutable entry 的 preserving lemma；
- view stutter自动包装；
- overflow/underflow/assert revert 保持 exact pre；
- invalid invocation/response trap 保持 exact pre；
- 新增、删除、重排 callable 后旧 aggregate proof fail closed。

### 7.4 Inline product

- same-file positive；
- theorem body变化：source/semantic digest不变、certification digest变化；
- wrong kind/ordinal/program/subject bytes；
- forged partial/reordered inventory；
- user axiom/unsafe/partial/extern/native shortcut；
- proof failure 早于 target resolve，零 staging/零 destination mutation。

### 7.5 VerifiedVaultPF

- initializer 从 pre-init state returned 后 solvent；malformed/revert/trap 走 exact unchanged base；
- deposit success保持相等；任一 add overflow 回滚；
- withdraw guard/underflow失败回滚；success保持相等；
- status state-stutter；
- Near artifact/runtime trace 与 Reference outcome/effects 对照；
- 不注册 closed pin也能完成 author proof。

---

## 8. 实施顺序与里程碑

| 顺序 | 里程碑 | 状态 | 完成信号 |
|---|---|---|---|
| 0A | 删除第二套 executable semantics | **已完成** | `MiniAmmSafetySketchV1`、alpha `Core/Semantics`/`SemanticIR` 已不在 HEAD |
| 0B | 唯一语义防回归门 | **已完成** | `alpha-deletion-gate` 固定平行语义、contract-specific registry/pin 的物理删除，不误杀 checker state |
| 1 | Typed State + codec bridge | **进行中（generated Bool/UInt64 codec proof 首切已完成）** | generated `Model.State` 复用 production codec；`Model.encode_exists`、`decode_encode`、`encode_decode_of_conforms`、conformance/typed-encode iff 与 conforming decode 唯一性均已闭合；Bool 的产品 accepted-language 接线与更多 scalar shape 仍待补 |
| 2 | Typed callable transition | **进行中（typed UInt64 参数投影 + initialized entry/view + 独立 initializer lifecycle relation 首切已完成）** | production ready gate 可把 raw invocation 精确恢复为 generated named invocation；pre-init 只使用 exact production lifecycle carrier；initializer returned state 与 ordinary callable returned state 均可唯一投影为 typed State，固定 typed 输入有且至多有一个 typed outcome |
| 3 | Typed invariant bridge | **进行中（evaluator + UInt64 字段 Eq/Ne 数学 bridge 首切已完成）** | generated predicate 使用 exact state encoder 与 lowered invariant ordinal，并与 production `evalInvariantV1` 双向对齐；exact two-state Eq/Ne CFG 已 fail-closed 投影成字段 `=`/`≠` 且不再暴露 encoding witness；这不是任意 expression translator，更多表达式与 exact validation packaging 仍待补 |
| 4 | Generic preservation composition | **进行中（VerifiedVault 五 callable narrow family 已闭环）** | composer、finite-row assembler、typed returned lift、UInt64 参数投影及 literal-true 程序级闭环已有；除 `sync(amount)` 外，双槽位同参数 checked-add deposit 与双 guard checked-sub Unit withdraw 已经沿唯一 Reference step 证明 returned post-state两字段相等，assert/overflow/revert/trap 由唯一事务语义保持 exact pre，并由 name-parameterized production validation/admission family、initializer base 与五个 exact rows 组装成最终 `PreservationTheoremV1`。arbitrary contract coverage 仍待补 |
| 5 | Same-file certifier ergonomics | **进行中（VerifiedVault 五 callable business family 已产品认证）** | 未 pin、无 contract-specific theorem/pin 的 `VerifiedVaultPF` 已通过真实 certifier 与 CLI；alpha-renamed 五 callable 同构正例通过，漏 store/sub、错误 subtraction flow/slot、漏/reverse assert、覆盖赋值、withdraw result shape 与 callable order 等 typed-valid near miss 在 certification elaboration fail closed；arbitrary family 仍待补 |
| 6A | VerifiedVaultPF Reference-certified author slice | **已完成** | initializer、deposit、guarded withdraw、status 与 equality invariant 绑定 exact 五 callable subject；Reference admission/execution/preservation、same-file theorem、product certifier 和 CLI `check` 全部通过，theorem count 1、digest 非空；声明严格停在 `reference-certified` |
| 6B | authority amendment + NEAR build/runtime | **已完成（engineering observed；非 formal refinement）** | ADR-0042、private certificate authorization、versioned Plan partition、Unit entry、CLI/real Wasm/ABI 已闭环；2026-08-11 原始 locked near-sandbox 2.13.0 经 userspace GLIBC 2.39 loader 在 required 模式跑通十套 corpus，VerifiedVault exact slots/Unit/rollback/missing-export 全部 PASS；loader 未入 Tool Lock，故非 hermetic release evidence |
| 7 | Per-target refinement | **进行中（NEAR status Reference、static emission chain 与 strict sandbox observation adapter 已接通）** | 已有 passive observation、scalar initialized-KV/ABI/return/failure relation，以及 certified capability → validated semantic data → production Plan/canonical keys → Plan→IR graph → status Method/MethodIR proof-producing syntax recognition → sole private emitter → exact ordered in-memory WAT/ABI base files；`CapabilityEntryStaticEmissionV1` 现把 exact retained SemanticProgram、同一 capability 的 Plan/IR/build success、status static alignment 与 source entry 2 / combined method index 3 的同次 WAT/ABI renderer graph 绑定为一个 kernel carrier。真实 generated subject 的 validation/admission/initialized decode/status lookup/empty-context gate/ready 已由 kernel 无外部 context premise组合，通用 theorem 自动推出 canonical 8-byte 与 exact Reference state-stutter/empty-effect outcome；strict runtime adapter现从真实 query + pre/post full KV snapshot映射并检查剩余 target success/return/log/promise/storage 字段，mutation corpus fail closed。该 adapter 仍是 external engineering evidence，不是 Wasm/NEAR semantics。尚无一般 lowering/renderer correctness theorem、JSON/WAT/target execution semantics、WAT↔ABI consumer consistency、simulation、locked `wat2wasm` correctness、finalized Wasm 或 disk artifact identity evidence |

### 首个代码切片进展

首个 Phase 1 纵切已经完成 0B 与 UInt64 typed state 的以下部分：

1. semantic authority/deletion gate 已固定第二 executable semantics 与 contract-specific
   registry/pin 的物理删除；
2. 小型未 pin program 已能仅由 `subjectDataV1` 生成 source-order typed `Model.State`；
3. encode/decode 继续复用 production logical-state codec，并已生成 `decode_encode`、
   `conforms_of_encode`、`decode_existsUnique_of_conforms` 与
   `encode_decode_of_conforms`；
4. production decoder 已有通用 declaration-arity theorem，因此 logical→typed totality不依赖
   contract-specific slot parser；
5. production decoder 的成功结果已有通用 exact re-encode theorem；generated Bool/UInt64 scalar
   view 均已证明每个 conforming logical state 经 typed decode 后可 byte-for-byte 编回原 carrier，
   并已导出 `StateConformsV1 ↔ ∃ typedState, encodeState typedState = .ok logicalState`；整个链
   仍只调用 production logical-state/value codec；
6. typed encoder 已有基于 production decode roundtrip 的 success-result injectivity theorem；空 state
   table 与多 UInt64 state table 都有 generated theorem 回归覆盖；
7. generated codec 的 Bool scalar projection/re-encode kernel 已闭合，但当前 Normalize accepted
   language 尚不包含 logical-state Bool，故仍不能把 Bool 写成产品 authoring 已闭环；
8. production logical-state encoder 已有 declaration/value pair canonicality 驱动的通用
   existence theorem；generated `Model.encode_exists` 对当前 typed fields specialization，并由
   mixed Bool/UInt64 semantic regression 与 generated multi-UInt64 authoring regression 固定。
   该 theorem 只证明 `encodeLogicalStateValuesV1` 的成功结果，不构造平行 byte encoder；
9. Bool callable **result** 与 generated state scalar 的 projection 均已可生成，但这不代表
   product Normalize 已接受 logical-state Bool；当前 accepted language 仍维持原边界；
10. Phase 1 的后续工作继续按 accepted language 扩 scalar/field projection，并与 Phase 2 的
   relation 工作保持小切片，避免一次把 state、step、certifier、target 全部耦合。

### Phase 2 首切进展

当前已完成以下窄切片，尚不把整个 Phase 2 标为完成：

1. `AdmittedSubjectV1` 将一个 positive `AdmittedReferenceSliceV1` witness 与
   `admitReferenceProgramSliceV1 exactProgram = .ok admitted` 等式绑定；generated callable
   relations 共享该 carrier，不各自选择 existential admission；
2. `TypedOutcomeV1` 保留 returned/reverted/trapped 三个 canonical outcome 分支；returned
   保留 typed post/result 与 `OrderedEffectV1`，failure 分支保留 production reason/fault；
3. `TypedCallableRelationV1` 是 `Prop` relation，不是 executable evaluator。其三个分支均
   直接包含 sole `stepReferenceSliceV1` equality；revert/trap 明确要求 exact encoded pre-state；
4. elaborator 从 exact lowered `SemanticProgramDataV1.callables` 读取 callable id、parameter
   TypeId 与 result TypeId，生成 canonical invocation/result projection，不从 source AST 重算 id；
5. 当前 generated subset 覆盖 initialized entry/view 及独立 initializer lifecycle、UInt64
   parameters、Unit/Bool/UInt64 result；unsupported parameter/result、ordinary callable 与固定
   `Model` surface/`init` namespace 冲突均 fail closed，不生成半成品 transition；canonical Wire
   上匿名的 sole initializer 只在 proof projection 中映射为 `Model.init`，不改写 subject data；
6. `context`、`ExternalResponsesV1`、`ReferenceVaultSeedV1` 均保持显式，未以空值或默认值
   冒充全输入 theorem；
7. `typedCallableRelationV1_outcome_unique` 已证明：在 generated state/result codec injective
   条件下，固定 subject/pre/invocation/context/responses/vault 的 relation 至多对应一个 typed
   outcome；每个支持 callable 生成 `outcome_unique`，证明只比较同一个 Reference step equality，
   不执行 callable；
8. 每个支持 callable 已生成 `Result`、`encodeResult`、`decodeResult`、
   `decode_encode_result` 与 `encodeResult_injective`。decoder 检查 exact lowered TypeId，并调用
   production `validateValueBytesV1` 和 scalar projection；Bool/UInt64 canonical bytes 的正向
   roundtrip 由 production validator theorem 关闭，wrong TypeId/malformed bytes fail closed；
   production Bool validator 现也有 canonical payload→exact `encodeBool` carrier 的反向事实，
   与既有 UInt64 exact re-encode theorem 一起支撑 typed result 完整回编；
9. sole Reference machine 已从完整 successful step 证明 returned result 与 production-selected
   callable result row 一致：Unit 必须使用 `none`，非 Unit 必须使用 exact TypeId 且通过
   production `validateValueBytesV1`。generated Unit/Bool/UInt64 callable 进一步生成
   `decodeResult_complete_of_conforms` 与 `decodeResult_complete_of_returned`：任一真实 returned
   result 都存在唯一 typed decode，且 typed re-encode 精确恢复原 Reference carrier；原
   `decodeResult_existsUnique_of_*` 作为兼容投影保留。该 bridge 只消费 exact callable lookup、
   Reference step 与 production validator，不执行第二套 callable；
10. Unit result 已用 accepted declared-revert entry lowering 做 generated codec/relation/uniqueness 回归；
   这不扩张 accepted language，也不伪造 Unit return literal；
11. `finalize_returned_implies_encodeV1` 已从任意成功 final outcome 反解出 exact returned
   candidate、effects 与唯一 production logical-state encode；
   `stepReferenceSliceV1_returned_stateConformsV1_of_initialized` 已沿完整
   `stepReferenceSliceV1 → runMachine → finalize` 路径证明 initialized entry/view 的 returned
   post-state 满足 exact admitted program 的 `StateConformsV1`；generated
   `decodeState_complete_of_returned` 已将该事实接到 production `decodeState`/`encodeState`，得到
   唯一 typed post-state及 exact re-encode；原 `decodeState_existsUnique_of_returned` 作为兼容投影
   保留。initialized entry/view wrapper 仍显式要求 initialized pre-state；独立 production
   initializer lifecycle theorem 现从 exact admitted initializer lookup 出发，经
   `runMachine_isInitializer_eq` 将 gate 的 initializer bit 传到真实 finalizer，并证明 every returned
   initializer post 满足 `StateConformsV1`；它没有把 initializer 混入普通 callable typed surface；
12. generated `transition_returned_of_step` 已把同一真实 Reference returned step 的 typed post、
   typed result 与原 effects 合并为 `Transition … (.returned post value effects)` witness；证明只
   组合上述 state/result complete theorem 和 `TypedCallableRelationV1`，不运行另一 evaluator；
13. generated `transition_reverted_of_step` / `transition_trapped_of_step` 已把真实 failure step
   包装为 typed transition，并同时返回 production theorem 保证的 `unchanged = logicalPre`；
   failure branch 不需要 state/result decode，也不执行另一 evaluator；
14. generated `transition_exists` 对 sole `stepReferenceSliceV1` 的实际结果作三分支分类，并调用
   上述 exact bridges，证明 initialized typed pre 的任意完整 Reference execution 都存在 typed
   outcome；与 `outcome_unique` 合用即得到存在且至多唯一，不新增 executable typed step；
15. `InitialLifecycleStateV1` 以
   `initialLogicalStateV1 exactProgram = .ok logical` 精确携带 pre-init state；generated
   `Model.LifecycleState` / `initialLifecycleState` 直接复用该 production constructor。initializer
   `Transition` 的 pre-state 不再伪装成 initialized business `State`，只有 returned post-state进入
   既有 `decodeState`；revert/trap 都保留 exact lifecycle logical pre-state；
16. initializer 专属 emitter 从 exact lowered anonymous initializer row 生成 `Model.init` 的 invocation、
   result codec、三分支 relation、returned/reverted/trapped packaging、`transition_exists` 与
   `outcome_unique`；ordinary selector仍只接受 entry/view。回归同时 pin initializer id/kind、ordinary
   view id，以及 relation 展开后每个分支唯一出现的 `stepReferenceSliceV1`；没有 generated evaluator；
17. typed invariant 已进入下述 Phase 3 首切，并完成 exact UInt64 两字段 Eq/Ne 的普通 Lean
   数学投影；Phase 4 也已有 per-callable returned composer、program-specific exact row/ordinal
   finite aggregation/assembler，以及不隐藏 full inputs 的 typed returned lift。首个一参数
   state-changing callable 已从 production ready gate 恢复 named UInt64 参数，并沿唯一 Reference
   step 证明 exact typed post-state和字段相等不变量；该 narrow stateful-equality family 现已
   闭合 production validation/admission、two-UInt64 initial base 与 premise-free program-level
   `PreservationTheoremV1` packaging；更多 expression/callable shape 与通用 family 生成仍未完成；
18. 当前成果只能称 Reference-level proof view / `reference-certified` 地基；target refinement
   完成前不能称 target artifact verified。

### Phase 3 首切进展

当前完成的是 evaluator-backed 地基和一个 fail-closed 业务数学投影 shape，而不是通用
expression translator：

1. `TypedInvariantV1 encodeState program ordinal state` 只要求 generated production encoder
   成功，并要求唯一的 production evaluator
   `evalInvariantV1 program ordinal logical` 返回
   `.returnedTrue`；它没有重新解释 DSL expression，也没有新增 invariant evaluator；
2. `typedInvariantV1_iff_eval_of_encode` 在同一个成功 encoded logical carrier 上给出精确双向
   等价，不通过 implication、默认 state 或 OOR ordinal 制造空真；
3. elaborator 从 exact lowered `SemanticProgramDataV1.invariants` table 读取 invariant name 与
   `zipIdx` ordinal，生成 `Model.<inv>` 和 `Model.Invariant.<inv>_iff_eval`；不从 source AST
   重算 ordinal，也不假定 ordinal 恒为零；
4. generated predicate 的 domain 是 initialized `Model.State`。独立 initializer
   `LifecycleState` 没有被吸收到 invariant API；initializer 只有 returned post-state decode 成
   `Model.State` 后才能使用该 predicate；
5. fixed generated-root 名冲突时仅不生成对应 optional invariant view；unsupported typed
   state shape 不生成悬空 predicate/bridge，既有 program 与 `Proof` aliases 保持可用；
6. 回归覆盖 exact encoder binding、非零 invariant ordinal、evaluator bridge 展开、initializer
   lifecycle 分离和 fail-closed name/state shape；
7. production machine 已证明 exact 三指令 Eq/Ne body 的
   `runInvariantCallableV1 = returnedTrue` 分别等价于 decoded bytes 相等/不等；public
   `evalInvariantV1` bridge 再组合 exact validation、ordinal selection 与 initialized decoder；
8. elaborator 只检查 exact lowered CFG、`invariantSteps = some 5`、ValueId `0/1/2`、
   arbitrary concrete StateId、anonymous Bool result 与同一 UInt64 field type；不读取 source AST，
   任一额外 block/instruction/type/fuel variant 都返回 `none`，但保留原 `_iff_eval` API；
9. 对支持 shape 生成 `Model.Invariant.<inv>_iff_fields`，把 canonical `encodeU64le` 的 Eq/Ne
   通过 production projection left inverse 收回普通 Lean 字段 `=`/`≠`。回归覆盖非零 StateId、
   非零 invariant ordinal，并确认 unsupported literal-true 不生成该 optional theorem；这仍是
   exact CFG comparison rule，不是任意 expression translator；
10. 当前 `_iff_fields` 仍显式接收 exact `hvalidate`，但不再接收作者提供的
    `LogicalStateV1`/successful `hencode`；它调用 generated `Model.encode_exists`，而该 theorem
    只证明 production `encodeLogicalStateValuesV1` 的 successful result。尚未证明任意 lowered
    family 的 premise-free exact subject validation packaging，也尚未处理 arithmetic/Struct/Map
    expression；
    production root codec 层现已公开任意长度 array 的 fixed-depth 与 all-depth exact inversion
    归纳 seam：调用方只需提供每个 source element 的 production encode success 与对应深度的
    exact inversion，不再为固定表长重写 `encodeArrayChunksV1` / `decodeArrayElementsV1` 或 pin
    整表 bytes；fixed-depth 版本允许 StateDecl/Callable 等有嵌套 depth margin 的 codec 在 root
    depth 组合；anonymous Bool/UInt `TypeDecl` 也已有 parameterized fixed-depth leaf certificate，
    不再限于 closed two-row decoder；public `StateDecl` leaf certificate 也已保留任意 declaration
    id / type id，只要求 production identifier gate 与明确的 nesting margin，不再局限于 singleton
    state 0；fixed-depth array lift 也已补齐四元素档位，可直接承接目标 equality fixture 的
    四行 callable table，而不需要 caller 提供 element bytes；目标 fixture 使用的 production
    `Binary.Ne` leaf 也已有与 `Binary.Eq` 同层级的 fixed-depth exact inversion；callable 的
    `invariantSteps` present-option seam 也已从 closed `some 7` 泛化到任意 UInt8 structural
    budget，目标的 `some 3` / `some 5` 不再需要各自 pin bytes；单 literal-return 与双
    state-load compare-return callable 现在也都有 parameterized production `CallableV1` shape
    与 root-depth exact codec package，Eq/Ne 仅在各自 production binary-op leaf certificate
    处分叉，不固定 callable id/name/type/state id/payload；目标 family 的四行 callable table
    也已由 production 四元素 array seam 组合为 parameterized exact package，仍不固定合约
    qualified name 或 encoded table bytes；这些仍只是 root-table 组合地基，不能单独推出
    structure/validation success；production array worker 现在也补齐了不要求 caller 提供
    element bytes 的二元素 fixed-depth lift，并可将任意 exact items-array certificate 通过
    唯一的 tagged `ProgramRequirementsV1` codec wrapper 提升，目标的两行 requirements
    不再需要另写 closed byte proof；在这些 leaf/table seams 上，现已有独立的、名称与
    qualified-name 参数化的 field-comparison subject family，实际 generated equality fixture
    与它 definitionally 相等，并已取得真实 whole-program `RootFieldInvertV1`；该结论仍只
    是 codec transport certificate，尚未声称 structure/full validation success；该 family
    的四个 callable 也已逐项通过 production generic CFG phase（reachability、SSA uses /
    dominance、state lookup 与 UInt64 Eq/Ne typing），并由 production four-callable composer
    汇总；随后同一参数化 callable table 也已通过 production invariant closure 与 fuel
    phases：membership 为 `#[false,true,true,true]`、没有 `PureCall` 边、三个 root 的 exact
    intrinsic/carried fuel 为 3/5/5；现已由 production composer 闭合完整 CFG/invariant
    segment；production structure prelude（root shape、dense table IDs、shallow references）
    与 anonymous UInt64/Bool 的 type-shape、TypeKey、named-type phases 也已参数化闭合并由
    真实 generated fixture 消费；现已继续闭合 canonical Bool valueBytes、state/callable
    exact-name uniqueness、special signatures、InvariantDecl join、identifier grammar、
    `state.persistent`/`value.bool` requirements 及空 ContextRead/Commit/EnvRead joins，并由
    production phase composer 得到该参数化 family 的完整 structure success；witness 仅携带
    production identifier facts 与 state/callable namespace distinctness，不包含 shadow
    validity predicate 或 whole-validator reduction；在此之后才扩大 elaborator 的 exact
    fail-closed family recognition：它先把完整 generated `SemanticProgramDataV1` 与参数化
    production constructor 做 exact 比较，再生成 `Proof.subjectStructureOkV1` 与
    `Proof.subjectValidationOkV1`；后者只组合 generated body identity、root gates、上述
    structure certificate 和 `RootFieldInvertV1`，使普通同文件作者可直接用 generated
    certificate 关闭 `_iff_fields` 的 exact `hvalidate` 前提，而不再依赖外部假设；
    near-miss/unsupported family 继续不生成这两个 certificate；stateful-equality family 也已
    以同一方式闭合 singleton `state.persistent` requirements、完整 structure phases、
    `RootFieldInvertV1` 与 Reference resource admission，且同样先做 whole-subject exact 比较；
    当前已把 `subjectBodyEncodeOkV1` + 全部 production root gates + structure success +
    whole-program `RootFieldInvertV1` 组合 exact validation 的 theorem 抽到通用
    `SubjectDataBridgeV1`，不再归属于 parity shape；elaborator 现已对每个 proof-bearing program
    生成通用 `Proof.subjectRootGatesOkV1`，逐项 kernel-check production qualified-name 与七个
    table-size gate；并开始对 exact recognized、已有 production phase proof 的 structural family
    生成 `Proof.subjectStructureOkV1`。simple-closure family 通过 kernel `change` 绑定 exact
    `subjectDataV1`，再复用 `SimpleClosureStructureCertV1.structure_of_legal`（其内部通过
    `validateSemanticProgramStructureV1_eq_ok_of_phases` 组合全部 production phase），并通过
    parameterized、arbitrary-framing 的 `rootFieldInvertV1_of_legal` 证明九个 production root-field
    codec inversion；field-comparison 与 stateful-equality family 则分别复用本节上述参数化
    structure/codec certificates。elaborator 最终对这三个 exact family 用
    `SubjectDataBridgeV1` 组合
    body/root/structure/inversion，生成
    `Proof.subjectValidationOkV1 : validateSemanticProgramV1 subjectProgramV1 = .ok subjectDataV1`。
    不支持的 lowered shape 保留 subject/typed Model surface，但不生成 structure/validation
    capability，也不退回 whole-validator `decide`。通用生成仍需先补较大表 qsort uniqueness、
    budget trace、TypeKey、CFG/closure 与对应 codec inversion 等 production certificate seam；在它们
    完成前 body/root/structure certificate 不能冒充 program validity，unsupported-family
    `subjectValidationOkV1` 与删除通用 `_iff_fields` 的 `hvalidate` 都必须继续 fail closed；
    不得把此 narrow shape 宣称为完整 expression translation 或通用
    `Spec.solvent ↔ Model.solvent`；
11. 当前声明仍仅是 Reference-level proof view 地基；它不改变 target materialization authority，
   更不构成 Reference→target refinement。

### Phase 4 首切进展

当前完成的是通用结构 composer 和首个 state-changing program-level 业务闭环，不是任意
业务证明自动生成：

1. `PreservationReturnedCallableV1` 保留 raw invocation（args/context）、production gate
   overlay/context、responses、vault、returned value/effects 与 exact
   `stepReferenceSliceV1 = .returned ...`；作者义务只覆盖成功 returned post-state；
2. `PreservationReturnedCallablesV1` 按 `admitted.data.callables[id]? = some callable` 枚举 exact
   admitted table。新增、替换或重排 callable row 会改变 obligation，不能被旧 aggregate 静默遗漏；
3. `preservationStepV1_of_returnedCallablesV1` 从 production ready gate 取得同一 row lookup；
   invalid root 与 lifecycle-only gate 不可能 returned，reverted/trapped 则只用 production
   `stepReferenceSliceV1_failureStateUnchangedV1` 关闭；
4. initializer 与 no-initializer base 仍分别使用 `PreservationBaseWithInitializerV1` 和
   `PreservationBaseNoInitializerV1`，没有把 pre-init carrier伪装成 typed business state；
5. `preservationTheoremV1_of_callableObligationsV1` 共享一个 positive admitted witness，并把
   ordinal bound、selected lifecycle base、exact callable-table returned obligations 组合成原有
   `PreservationTheoremV1`。没有新增 `State`、`Effect`、step 或 evaluator；
6. `PreservationReturnedRowsV1` 以 `Fin subjectData.callables.size` 固定 finite row；通用 lift 只有在
   `admitted.data = subjectData` 时才把 rows 升为 exhaustive admitted-table obligations，避免用另一
   subject 的 row proof 拼接；
7. elaborator 已在每个 `ProofPreserving.<inv>` namespace 生成 exact `BaseV1`、initializer/no-init
   分支、`ReturnedCallablesV1`/`ReturnedRowsV1`、逐 callable-index
   `callable<N>ReturnedV1`、finite `returnedRowsV1` 与 `ofRowObligationsV1`；新增/重排 row 会改变
   assembler premise list。对拥有完整 generated Model codec 的 entry/view row，另生成
   `callable<N>TypedReturnedV1` 与 `callable<N>ReturnedV1_of_typed`；unsupported typed state 不生成
   dangling bridge，nonzero invariant ordinal 与 exact callable row 均有回归。它只生成 theorem
   target/lift/assembler，不生成业务 proof 或 transition；
8. `PreservingSurfaceProof.safe` 已构成首个同文件 preserving 闭环：同一 DSL subject 的 production
   validation 产生 positive admitted witness；无 initializer base 直接使用 production
   `initialLogicalStateV1`（并新增其 empty-state/no-initializer projection theorem）；returned rows
   则由 `stepReferenceSliceV1_returned_stateConformsV1_of_initialized` 证明 post-state conformance，
   最后调用 generated `ofRowObligationsV1` 得到原始 `PreservationTheoremV1`。该 fixture 的
   invariant 是 literal `true`，只验收 authoring/composition 链路，不代表非平凡业务保持性；
9. `TypedReturnedPreservationV1` 让作者在 generated State/Result 上证明保持性，premise 仍是唯一
   production step 支撑的 `TypedCallableRelationV1`，并显式保留 raw invocation/context、responses、
   vault、returned value/effects；通用 lift 只从 production state/result conformance 获取 typed
   witness，再用 exact encoder/evaluator bridge 返回 raw `PreservationReturnedCallableV1`。
   `PreservingSurfaceProof.safe` 的 view row 已实际改用 generated typed lift；
10. production `gateInvocation` 的 canonical argument 检查现可公开投影 exact arity 与逐位置
    canonical argument；StateModel 在 exact UInt64 TypeId/shape 下把 accepted bytes 唯一重编码为
    `UInt64`。elaborator 因此为每个 supported entry/view 生成
    `Model.<callable>.invocation_complete_of_ready`：它从同一个 positive admitted subject、exact
    callable row 与 ready gate 恢复全部具名 UInt64 参数，并证明 raw invocation 精确等于 generated
    `Model.<callable>.invocation ... rawInvocation.context`。一参数 state-changing entry、零参数 view
    与 Unit entry 均有 ordinary Lean 回归；该证明不执行或解释 callable body，也没有新增 step；
11. `StateChangingPreservationSurface` 是首个非平凡 state-changing same-file business slice：
    `sync(amount)` 的 production CFG 依次执行 `stateStore 0 0`、`stateStore 1 0`、
    `stateLoad 1`、`return`；新增的 Reference inversion theorem 从真实 ready gate 与
    `stepReferenceSliceV1 = .returned ...` 推出 post-state 正是
    `{ reserves := amount, shares := amount }`。业务 theorem 随后在 generated
    `callable0TypedReturnedV1` surface 上用普通字段等式关闭 `solvent : reserves == shares`；
    context、responses、vault、returned result/effects 与 raw invocation 均未被隐藏，也没有
    第二 evaluator；
12. `StateChangingPreservationSurface` 已 exact 命中 name-parameterized
    `StatefulEqualitySubjectV1`：family 使用真实
    singleton `state.persistent` requirements，组合 production structure phases 与
    `RootFieldInvertV1`；elaborator 只有在 reconstructed whole subject 完全相等时才生成
    `Proof.subjectStructureOkV1` / `Proof.subjectValidationOkV1`。随后 same-file aggregate 通过 sole
    Reference admission scan、可复用 two-UInt64/no-initializer initial-state theorem、typed entry row
    lift，以及 production gate 对 invariant callable row 的不可调用性，最终组装原始
    `PreservationTheoremV1`。没有 contract-qualified closed pin、admission carrier 伪造或第二套
    State/Effect/step/evaluator；该 name-parameterized family 现已有 shipped same-file source，且真实
    in-process certifier 与 CLI `check` 均验收 `.certified`（theorem count 1 与非空 SHA-256
    certification digest），无 contract-specific pin/package。这仍不代表 arbitrary contract
    generator 或任何 target refinement 已完成；
13. 首个真实 `Examples/VerifiedVaultPF.lean` 现已完成 initializer + `deposit(amount)` +
    `withdraw(amount)` + read-only `status` + `reserves == shares` invariant 的 exact production
    family：两字段 canonical zero 初始化经 sole Reference machine 建立 lifecycle base；deposit 对
    两个槽位分别执行同一参数的 checked-add 并返回第二槽位；withdraw 依次检查
    `amount <= reserves` 与 `amount <= shares`，再对两个槽位执行 checked subtraction，以 implicit
    Unit return结束；returned success 的 post 编码精确为同一 difference bytes 两次；status
    returned 路径证明 `post = pre`；最终同文件 ordinary theorem 将五个 callable row 组装为原始
    `PreservationTheoremV1`。assert false、checked arithmetic failure 与其他 reverted/trapped
    outcome 继续由 production transaction packaging 保证 exact pre rollback，没有新增 evaluator
    或 step；
14. 产品 elaborator 只在完整 `SemanticProgramDataV1` 与该名称参数化五 callable family exact 相等
    时生成 structure/validation certificate。真实 certifier/CLI 报告
    `proofStatus=certified`、theorem count 1 与非空 SHA-256 certification digest；alpha-renamed 同构
    正例同样 certified。除既有 deposit near miss 外，漏掉 withdraw 第二个 sub/store、读取错误
    subtraction 源/槽位、漏掉或反转 assert、用覆盖赋值替代 subtraction、改变 withdraw result
    shape 或 callable order 的 typed-valid near miss 都在 certification elaboration fail closed；
15. Phase 6A 的完整 Vault 业务窄切片已经达到 `reference-certified`。Phase 6B 已按 ADR-0042
    让 sole ordinary capability mint 经 private certificate authorization transition 获得 NEAR-only
    invariant-root erasure authority；Plan digest 绑定 exact proof digest/callable partition，真实
    CLI build 已产出只导出 init/deposit/withdraw/status 的 Wasm/ABI，`solvent` 仍只属于 compile-time
    proof subject。2026-08-11 以 userspace GLIBC 2.39 loader 启动原始 locked binary 的 required
    runtime run 已让十套 corpus 全部 PASS，其中 Vault exact slots、Unit withdraw、guard/overflow
    rollback 与 missing invariant export 均真实观察通过，Phase 6B 达到 engineering observed。
    兼容 loader 未入 Tool Lock，故不是 hermetic release evidence；arbitrary callable/expression
    family 与 formal target refinement 也仍未完成。不能把这一条 exact family 宣传成“任意业务
    合约都已自动可证”，更不能声称 emitted target artifact 已形式化验证。

---

## 9. 关键风险与止损条件

| 风险 | 止损条件 |
|---|---|
| typed Model 变成第二 interpreter | wrapper 定义体无法直接归约到 Reference，或缺 exact bridge，即停止合入 |
| 只对 closed golden 可证 | 新 API 若要求 pin/手写 canonical spine，Phase 1/4 不算完成 |
| 隐藏 full-input 义务 | context/responses/vault 未证明无关却从 theorem 消失，拒绝 API |
| package theorem 取代作者 theorem | source 无 `proof … using` + same-file theorem，不算目标体验 |
| reduced fixture 冒充真实合约 | MiniAmmEmptyPool 类缩小实例不能替代完整 VerifiedVaultPF/MiniAmm 验收 |
| proof-bearing build 偷删 invariant | erasure 未进入显式 Plan 决定/observation validation 时保持 fail closed |
| Reference proof 被宣传为 artifact proof | 无 target refinement evidence 时 UI/文档只能标 `reference-certified` |
| 为证明便利放宽 trust policy | 需要 user axiom/sorry/unsafe/native shortcut 才能通过时停止，先补通用 kernel lemma |

---

## 10. Definition of Done

本规划的作者体验目标只有在以下条件同时满足时才算完成：

1. 产品只有一个 authoritative `SemanticProgramV1 + ReferenceMachineV1` 执行语义；
2. 合约同文件内包含 DSL program、proof binding 与 ordinary Lean business theorem；
3. 作者使用 generated typed State/transition/invariant，不操作 canonical bytes/callable id；
4. generated Model 有 exact codec/evaluator/Reference step bridge；
5. per-callable theorem可通用组合为 exact `PreservationTheoremV1`；
6. 未 pin、无 contract-specific package theorem 的 `VerifiedVaultPF` product `check` certified；
7. proof fail 仍严格早于 materialization；
8. proof-bearing NEAR build/runtime 纵切通过，且 invariant erasure诚实；
9. UI/manifest 将 Reference certification 与 target refinement 分开；
10. 只有完成对应 target refinement 的目标，才允许使用 “artifact verified” 声明。

换句话说：**先删除平行语义是正确原则，但仓库已经完成了那次删除。下一步不是再造或再删
一套 `State / Effect / step`，而是在唯一 Reference semantics 上建立 typed、可证明、可组合的
作者视图。**
