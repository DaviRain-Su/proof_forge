---
id: PLAN-VERIFIED-CONTRACT-AUTHORING
title: ProofForge VerifiedVault 风格形式化验证作者体验实施规划
status: draft
owner: engineering
updated: 2026-08-09
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

1. 作者仍面对 `LogicalStateV1`、canonical bytes、callable id、invocation、responses、vault
   和大段 shape/decode 义务，缺少合约本地 typed `State`。
2. 缺少自动生成的 per-callable typed transition API；作者不能自然写
   `deposit s amount = .returned next`。
3. 缺少 DSL invariant expression 与 typed predicate 的通用等价桥。
4. `PreservationTheoremV1` 要求 base + 全输入 + 全 callable + 三 Outcome；当前缺少把
   per-callable 业务 lemma 自动组合成该 ABI 的程序级 packager。
5. ClosedSubjectPin/contract-specific golden 可以加速已知样例，但不能成为任意合约的主证明通道。
6. [`Examples/MiniAmmL1.lean`](../../Examples/MiniAmmL1.lean) 当前只有 executable
   `emptyPool` invariant 与 Normalize/Reference admission 正例，没有同文件 proof binding 和完整
   `PreservationTheoremV1`；`MiniAmmEmptyPoolV1` 又只是缩小的 closed instance，不能冒充完整 vault。
7. 多数 target 仍对 nonempty invariants fail closed；proof-bearing program 还不能自然地
   `check` 后继续 deploy artifact。
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

  entry deposit(amount : UInt64) : Unit do
    reserves := reserves + amount
    shares := shares + amount

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

**状态**：重复实现删除已完成；防回归门禁待补。

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

交付：

1. 将 DSL invariant expression 投影为 `<Program>.Model.<inv> : State → Prop`。
2. 证明 exact 双向桥：

   ```lean
   theorem solvent_iff_eval
       (hencode : encodeState typedState = .ok logical) :
       Model.solvent typedState ↔
         evalInvariantV1 subjectProgramV1 ordinal logical = .returnedTrue
   ```

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

**前置 authority change**：当前 ADR-0034 与各 target contract 明确保持 nonempty invariant
materialization fail closed。本 draft 不能覆盖该规则。进入 Phase 6 代码前，必须先提交并批准独立
ADR/target-spec amendment，冻结 versioned proof-only invariant erasure Plan；在该变更获批前，
proof-bearing target build 继续 fail closed。

交付一个真实单文件样例，不使用缩小 golden 替代完整业务程序：

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
- 声明仍是 “Reference-verified + NEAR engineering runtime observed”，不是 target-refined formal。

### Phase 7 — Reference → target refinement（独立长期轨道）

这是从“模型上证明”升级到“最终 artifact 被证明”的必要阶段，不能由同文件 theorem 替代。

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
| 1 | Typed State + codec bridge | **进行中（0B/UInt64 双向 complete/unique 首切已完成）** | generated `Model.State` 复用 production codec；`decode_encode`、`encode_decode_of_conforms`、conformance/typed-encode iff 与 conforming decode 唯一性均已闭合；更多 accepted scalar shape 仍待补 |
| 2 | Typed callable transition | 未开始 | 简单 entry theorem 只使用 typed State/args/outcome |
| 3 | Typed invariant bridge | 未开始 | typed predicate 与 `evalInvariantV1` 双向对齐 |
| 4 | Generic preservation composition | 未开始 | per-call lemmas 自动包成 exact `PreservationTheoremV1` |
| 5 | Same-file certifier ergonomics | 部分地基已有 | 任意未 pin 合约的真实 proof body可 certified |
| 6 | authority amendment + VerifiedVaultPF + NEAR build/runtime | 未开始 | 先批准 versioned invariant-erasure contract，再完成单文件 proof + build + runtime differential；诚实标注 Reference-level |
| 7 | Per-target refinement | 未开始 | target-specific refinement evidence逐个关闭 |

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
5. production decoder 的成功结果已有通用 exact re-encode theorem；generated UInt64 view 已证明
   每个 conforming logical state 经 typed decode 后可 byte-for-byte 编回原 carrier，并已导出
   `StateConformsV1 ↔ ∃ typedState, encodeState typedState = .ok logicalState`；整个链仍只调用
   production logical-state/value codec；
6. typed encoder 已有基于 production decode roundtrip 的 success-result injectivity theorem；空 state
   table 与多 UInt64 state table 都有 generated theorem 回归覆盖；
7. 当前 Normalize accepted language 尚不包含 logical-state Bool，故不能把 Bool 写成已闭环；
8. 下一切片先按 accepted language 扩更多 scalar/field projection，再进入 Phase 2，避免一次把
   state、step、certifier、target 全部耦合。

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
