---
id: ADR-0034
title: Preservation ABI（L1 step-preservation；proposed extension/amendment to ADR-0027）
status: proposed
owner: architecture
updated: 2026-08-09
normative: true
---

# ADR-0034：Preservation ABI（L1 step-preservation）

- 状态：`proposed`（通用 ABI / kind / inventory / alias / protocol / certifier 已闭合；
  **wave-3′ generic-first cutover 已于 2026-08-09 完成**：codec round-trip、
  contract-agnostic shape-family theorems、结构化 `subjectDataV1`、same-file ordinary
  contract proofs。`ProofForgeV2/ProofInstances/`、`ClosedSubjectPinV1` 与
  `ParityCounter*`/`ZeroCounter*` 专属模块已删除；产品包零合约专属 proof/data/pin。
  `Examples/Counter.lean` 与 `Examples/MiniAmmL1.lean` 直接消费通用 API 并通过产品 certifier；
  ADR-0027 supersession 与 formal maturity 仍未完成）
- 日期：2026-08-07（2026-08-09 generic-first migration complete）
- **Proposed extension / amendment to**：
  [`ADR-0027`](0027-inline-same-file-theorem-certification.md)
  （**当前产品 authority 仍为 ADR-0027**；本 ADR 冻结 L1 Preservation 设计契约与
  inventory/kind 扩展；**不得** 因 EvenCounter/ZeroCounter 正例而把 ADR-0027 标 `superseded`，
  也 **不得** 把实例写成“任意合约已自动可证”或 formal maturity）
- 前置工程事实：`InvariantABI` / `ReferenceMachineV1`（`admitReferenceProgramSliceV1`、
  `stepReferenceSliceV1`、`OutcomeV1`、`InvocationV1`、`ExternalResponsesV1`、
  `ReferenceVaultSeedV1`、`AdmittedReferenceSliceV1`、`initialLogicalStateV1`、
  `evalInvariantV1` / `StateConformsV1` / `LogicalStateV1`）；research
  [`23-miniamm-formalization-ladder.md`](../research/23-miniamm-formalization-ladder.md)
  的 Reference-first / L1 `Preserves` 目标叙述；当前实现不含 closed subject pin，
  合约 proof/data 只在各自的 `Examples/*.lean` 源文件中。

## 背景

工程已闭合 **L0 holds** 命题（**当前 product authority = ADR-0027**；holds 形状本 ADR
原样继承，不改写）：

```lean
InvariantTheoremV1 program ordinal :=
  ordinal.toNat < program.invariants.size ∧
  ∀ state : LogicalStateV1,
    StateConformsV1 program state →
    evalInvariantV1 program ordinal state = .returnedTrue
```

该命题量化在 **布局/类型合法** 状态上，**不是** init 可达、也 **不是** 单步
保持。业务安全（例如“计数器始终偶数”“池子空则 reserve 为零”）不能诚实写成
holds 全称。

产品需要第二类证明表面：**在 product Reference step 上，选定 invariant 从
pre 到 post 的保持**。若把保持塞进 `InvariantTheoremV1`，或为某个 Example
（尤其 MiniAmm）再写一套 State/Effect/step，会分叉语义权威并重蹈已删除的
手写 sketch 路径。

本 ADR 初始提交冻结 **平台通用 Preservation ABI** 设计契约：独立 closed Prop 族、
**admission 成功为正义务**（禁止 implication 空真）、exact program+ordinal、base+step
合取、全输入 Outcome 不压扁、源码 proof kind、不冲突 alias、inventory 键
`(invariant, kind)`、EvenCounter 首实例 / 禁止 MiniAmm 特例，并记录相对 ADR-0027
的拟议扩展（见 D0）。

后续 engineering slices 已实现 D1–D3 通用 ABI foundation、D6–D8 kind plumbing，
以及 D9 的 acceptance 历史实例。2026-08-09 的 wave-3′ 将该历史实例栈替换为
contract-agnostic codec/shape/elaboration API：作者文件直接用结构化 `subjectDataV1`、
通用 preservation theorem 与 `decide`/`rfl` 形状事实完成同文件普通定理。
当前产品正例为 `Examples/Counter.lean` 与 `Examples/MiniAmmL1.lean`；
`ProofInstances/`、closed pins、ParityCounter/ZeroCounter 专属模块和重复 examples/tests
均已物理删除。没有修改 Reference 机器语义，也没有加入 MiniAmm 平台特例。

**当前产品路径的 single-snapshot/audit/axiom/proof-before-materialize 基线继续由 ADR-0027
约束；kind / Preservation 扩展由本 ADR 约束。** 本 ADR **不** 因 EvenCounter/ZeroCounter
正例立即 supersede 0027，也 **不** 声称 formal TASK/TST 关闭或任意合约自动可证。

**非 formal**：不关闭 TASK-D2-07 / TST-SEM-002/003 / TST-PROOF-001；不声称
hermetic / Stage-0 / target refinement / release。

## 决策

### D0. Proposed extension / amendment to ADR-0027（非即时 supersession）

1. **Authority 现状（强制）**：
   - [`ADR-0027`](0027-inline-same-file-theorem-certification.md) 仍是 product inline gate 的
     base authority（`status=proposed`；**无** `successor`；**无** superseded 横幅），继续约束
     single snapshot、audit、axiom、user-olean rejection 与 proof-before-materialize。
   - 本 ADR = **proposed extension / amendment**：L1 ABI、kind plumbing 与
     wave-3′ generic-first product path 已实现；当前 same-file 正例为普通
     `Examples/Counter.lean` 与 `Examples/MiniAmmL1.lean`。
   - ADR-0027 supersession 仍 pending（须 **单独** 文档决策，不得预填）。
   - **禁止** 因工程正例就把 ADR-0027 标 `superseded`、写 `successor=ADR-0034`，
     或声称“任意合约已自动可证 / formal 完成”。
2. **未来 supersession 门槛**（仅在同时满足后 **单独** 记录，不得预填）：
   - ABI / kind / inventory / certifier、generic codec/shape/elaboration 与至少两个
     ordinary same-file contract positives 已闭合；
   - 产品路径、测试与文档已诚实覆盖 0034 义务及失败面；
   - 再以独立文档变更把 ADR-0027 标 `superseded` 并登记 `successor=ADR-0034`。
   - 在此之前，0027 与 0034 **并存**：0027 是通用 inline gate 基线；0034 是 L1 preserving
     扩展；supersession 未执行。
3. 本 ADR 扩展的**已实现 plumbing**（不改写 holds 形状）：
   - 第二期望 Prop 族 `PreservationTheoremV1`；
   - 源码 proof kind `holds | preserving` 与三字段 `ProofDecl` wire；
   - inventory sole key **`(invariantName, kind)`**（见 D6），取代新代码中的单键模型；
   - kind-bound alias、protocol obligation、theorem-set/certification digest 与 certifier audit。
4. 在 ADR-0027 下已 engineering-closed 的 holds 正例（simple-closure /
   ordinal-0 / literal-true / public-Bool-view product `check` certified）
   **继续有效**且其 kind 固定为 `holds`。inline certification 的 snapshot / in-process 非 sandbox /
   fixed axioms / proof-before-materialize 等纪律仍读 ADR-0027。当前 preserving product
   positives 由普通 `Examples/Counter.lean` 与 `Examples/MiniAmmL1.lean` 提供；
   holds 与 preserving 可并存于同一 program。

### D1. 独立 closed ABI（禁止塞进 `InvariantTheoremV1`）

1. 新增 **独立** 工程 ABI 命题族（建议名 `PreservationTheoremV1`，命名以
   实现切片冻结；本 ADR 锁 **normative 形状**）：
   - 参数：`program : SemanticProgramV1`、`ordinal`（dense invariant ordinal，
     与 holds 同源）；
   - **不得** 定义为 `InvariantTheoremV1` 的别名、扩展字段、或
     “holds ⇒ preserve”的隐式合成；
   - **不得** 以 `∀ state, StateConforms → holds` 冒充 step 保持。
2. Holds（L0）与 Preservation（L1）可同时存在于同一 program：同一 invariant
   可绑定 holds 与/或 preserving（见 D6）。二者命题形状不同，certifier
   expected Prop 按 kind 分支。
3. 可执行投影仍经 `evalInvariantV1` / `StateConformsV1` / `LogicalStateV1`；
   **step 权威唯一** 为 admitted product Reference：
   `admitReferenceProgramSliceV1` + `stepReferenceSliceV1`。禁止第二套
   program-local hand-written `step`。

### D2. Exact `SemanticProgramV1` + ordinal + 不冲突 alias

1. Expected closed shapes（实现须 defeq 对齐 exact subject program）：

   ```lean
   InvariantTheoremV1     program ordinal   -- kind = holds
   PreservationTheoremV1  program ordinal   -- kind = preserving
   ```

   其中 `program` 为当前 compiled closed `SemanticProgramV1`（exact
   `canonicalBytes` / `semanticHash` 主体），`ordinal` 为 source-order dense
   invariant ordinal（与 holds / `InvariantDecl` 表 **同一** 序数；
   `ordinal.toNat < program.invariants.size`）。
2. **冻结不冲突 program-local alias**（若生成；实现切片须 exact 采用）：

   | Kind | Alias（definitional） | 定义体 |
   |---|---|---|
   | holds | `<ProgramIdentity>.Proof.<InvariantName>` | `InvariantTheoremV1 subjectProgramV1 ordinal` |
   | preserving | `<ProgramIdentity>.ProofPreserving.<InvariantName>` | `PreservationTheoremV1 subjectProgramV1 ordinal` |
   | shared subject | `<ProgramIdentity>.Proof.subjectProgramV1` | exact compiled `SemanticProgramV1` literal |

   规则：
   - holds 路径 **保持** 既有 `<Program>.Proof.<Inv>` 名（canonical 兼容
     ADR-0027 已发 surface）；**不得** 为 holds 改名到 `Proof.holds.*`。
   - preserving **必须** 使用 **独立** 命名空间前缀 `ProofPreserving`，
     **不得** 占用 `<Program>.Proof.<Inv>`（与 holds alias 冲突），
     **不得** 在 `.Proof` 下插入与 invariant 名同级的 `preserving` 组件
     （防止 invariant 名 `preserving` 或未来 kind 名冲突）。
   - 禁止 hash-only cast、未解 metavariable、或“任意 program 同构”替换 subject。
3. Theorem body 在 `program … where` 之外；subject program 由 product compile
   绑定，不信任用户 `.olean` 中的外来 program 常量。

### D3. Normative `PreservationTheoremV1`（完整 Prop）

以下为 **normative** 工程命题形状（名称可在实现时微调，但 **结构义务** 不得
弱化为 implication 空真）。辅助定义与顶层定理 **合取** 构成完整 closed Prop。

#### D3.1 机器 helper（revert / trap unchanged）

```lean
/-- Machine helper: reverted outcome carries byte-identical pre-state. -/
def OutcomeRevertedUnchangedV1
    (pre : LogicalStateV1)
    (reason : SemanticRevertV1)
    (unchanged : LogicalStateV1) : Prop :=
  unchanged = pre
  -- 实现可用 LogicalState 结构相等或既有 byte-eq helper；须与
  -- stepReferenceSliceV1 对 revert 的 pre 回传一致。

def OutcomeTrappedUnchangedV1
    (pre : LogicalStateV1)
    (fault : SemanticFaultV1)
    (unchanged : LogicalStateV1) : Prop :=
  unchanged = pre
```

Helper **只陈述** Reference 机器已保证的 unchanged；**不是** 业务 invariant。
Preservation 在 revert/trap 分支上应 **复用** helper（或 defeq 到
`unchanged = pre`）；禁止另写“失败也改状态”的旁路语义。

#### D3.2 Admission 成功 = 正义务（禁止 implication 空真）

**禁止** 下列空真形状（以及一切等价改写）：

```lean
-- FORBIDDEN (vacuous when admission always fails):
∀ (inputs …),
  admitReferenceProgramSliceV1 program = .ok admitted →
  … preservation obligations …
```

**要求** admission 以 **正存在 + 等式** 进入顶层合取：

```lean
∃ (admitted : AdmittedReferenceSliceV1),
  admitReferenceProgramSliceV1 program = Except.ok admitted
  ∧ PreservationBaseV1 program ordinal admitted
  ∧ PreservationStepV1 program ordinal admitted
```

解释：

1. 若 program **不能** 被 product Reference admission，则
   `PreservationTheoremV1` **为假**（不得“证明成功”）。
2. `admitted` 是 step/base-with-init 的 **唯一** `stepReferenceSliceV1` 句柄；
   禁止在 proof 内绕过 admission 直接构造 opaque admitted carrier。
3. Holds（`InvariantTheoremV1`）**不** 量化 admission（evaluator 独立）；仅
   Preservation 引入本正义务。

#### D3.3 Base：无 initializer / 有 initializer（全称）

由 **SemanticProgramV1 callables 表** 判定有无 initializer（structure gate
保证 0/1；不由作者手写 flag）。Base **不得** 省略。

```lean
/-- Executable shared classifier: validate, then use exact callable-id lookup.
    Args/context/lifecycle are not duplicated here. -/
def isInitializerCallableIdV1
    (program : SemanticProgramV1)
    (callableId : CallableIdV1) : Bool :=
  match validateSemanticProgramV1 program with
  | .error _ => false
  | .ok data =>
      match data.callables[callableId.toNat]? with
      | none => false
      | some callable => callable.kind == .initializer

private def IsInitializerCallableIdV1
    (program : SemanticProgramV1)
    (callableId : CallableIdV1) : Prop :=
  isInitializerCallableIdV1 program callableId = true

/-- True iff the validated callables table contains an initializer. -/
def HasInitializerV1 (program : SemanticProgramV1) : Prop :=
  ∃ callableId, IsInitializerCallableIdV1 program callableId

/-- Executable invocation-shaped view of the same classifier. -/
def isInitializerInvocationV1
    (program : SemanticProgramV1)
    (invocation : InvocationV1) : Bool :=
  isInitializerCallableIdV1 program invocation.callableId

/-- The invocation targets the validated initializer by exact callable id. -/
def IsInitializerInvocationV1
    (program : SemanticProgramV1)
    (invocation : InvocationV1) : Prop :=
  isInitializerInvocationV1 program invocation = true

/-- Base when the program has no initializer. `initialLogicalStateV1` returns
    Except, so constructor success is itself a positive obligation. -/
def PreservationBaseNoInitializerV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) : Prop :=
  ∃ pre : LogicalStateV1,
    initialLogicalStateV1 program = .ok pre ∧
    StateConformsV1 program pre ∧
    evalInvariantV1 program ordinal pre = .returnedTrue

/-- Base when the program has an initializer (full name / full quantifiers):
    initial-state construction must succeed, then every Reference step targeting
    the initializer either returns a post-state on which the invariant holds, or
    is an unchanged revert/trap. -/
def PreservationBaseWithInitializerV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) : Prop :=
  ∃ pre : LogicalStateV1,
    initialLogicalStateV1 program = .ok pre ∧
    ∀ (invocation : InvocationV1)
      (responses : ExternalResponsesV1)
      (vault : ReferenceVaultSeedV1),
      IsInitializerInvocationV1 program invocation →
      match stepReferenceSliceV1 admitted pre invocation responses vault with
      | .returned postState _value _effects =>
          evalInvariantV1 program ordinal postState = .returnedTrue
      | .reverted reason unchangedState =>
          OutcomeRevertedUnchangedV1 pre reason unchangedState
      | .trapped fault unchangedState =>
          OutcomeTrappedUnchangedV1 pre fault unchangedState

/-- Dispatcher: exactly one of the two base shapes (Prop 析取，非 Bool if). -/
def PreservationBaseV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) : Prop :=
  (HasInitializerV1 program ∧
      PreservationBaseWithInitializerV1 program ordinal admitted) ∨
  (¬ HasInitializerV1 program ∧
      PreservationBaseNoInitializerV1 program ordinal)
  -- `admitted` 在无 initializer 分支可不使用，但仍由顶层 ∃ 强制 admission 成功。
```

规则：

1. **无 initializer**：base 先要求
   `∃ pre, initialLogicalStateV1 program = .ok pre`，再正合取
   `StateConforms ∧ eval = .returnedTrue`；**不是** initial/error 或
   `StateConforms → eval` 上的空真 implication。
2. **有 initializer**：base 同样先正要求 initial constructor 成功，再进入
   `PreservationBaseWithInitializerV1` 的全称 invocation/response/vault 义务；
   initial 失败时该 base 为假，不能躲在全称量化后。
3. 本 base **不** 要求 `∃` 一次成功 init（成功依赖具体 args/context，属
   程序实例）；它要求：**凡** 成功 returned 的 init 路径 post 上 holds，且
   fail 路径不变。顶层仍因 admission 正义务而非空。
4. 非 init 的 entry/view 成功路径 **不** 充当 base；它们属于 D3.4 step 段。
5. 若初始未 initialized 且 evaluator 对未初始化 trap：无-init 程序的
   `initialLogicalStateV1` 必须与 product 纪律一致地进入可 eval 形态；
   不得发明第二套 initial。

#### D3.4 Step：全输入 returned 保持（Outcome 不压扁）

```lean
def PreservationStepV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1)
    (admitted : AdmittedReferenceSliceV1) : Prop :=
  ∀ (pre : LogicalStateV1)
    (invocation : InvocationV1)
    (responses : ExternalResponsesV1)
    (vault : ReferenceVaultSeedV1),
    StateConformsV1 program pre →
    evalInvariantV1 program ordinal pre = .returnedTrue →
    match stepReferenceSliceV1 admitted pre invocation responses vault with
    | .returned postState _value _effects =>
        evalInvariantV1 program ordinal postState = .returnedTrue
    | .reverted reason unchangedState =>
        OutcomeRevertedUnchangedV1 pre reason unchangedState
    | .trapped fault unchangedState =>
        OutcomeTrappedUnchangedV1 pre fault unchangedState
```

冻结纪律：

1. **全量化** `InvocationV1`（含 **context**）、**responses**、**vault**。
   不得只对“空 context / 空 responses / 默认 vault”证明后写成全称保持。
2. **Outcome 不压扁**：禁止把 `step` 改写为 `Option LogicalStateV1`、
   `Except`、或“仅成功态”投影后再证明。义务必须匹配 `OutcomeV1` 三构造器。
3. 成功路径只约束 **postState** 上 invariant 再成立；**不** 要求
   value/effects 额外业务谓词（后续独立引理族，不进本 ABI）。
4. view / pure 只读成功：若 `.returned` 且 state 不变，仍须同一 match 形状。
5. 非法 invocation / invalidExternalResponse 等落入 `.trapped` 时走 helper，
   **不得** 静默当成“状态任意”。
6. Step 前件 `holds pre` 使用 equality `eval = .returnedTrue`（在
   `StateConforms` 下），**不是** 对 admission 的 implication。

#### D3.5 顶层 closed Prop（ordinal + ∃ admitted + base + step）

```lean
def PreservationTheoremV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) : Prop :=
  ordinal.toNat < program.invariants.size ∧
  ∃ (admitted : AdmittedReferenceSliceV1),
    admitReferenceProgramSliceV1 program = Except.ok admitted ∧
    PreservationBaseV1 program ordinal admitted ∧
    PreservationStepV1 program ordinal admitted
```

**完整性检查清单**（实现/证书必须全部满足）：

| # | 义务 | 空真防护 |
|---|---|---|
| 1 | `ordinal` 在 dense invariant 表内 | 边界否定（OOB ⇒ ¬Prop） |
| 2 | `∃ admitted, admit = .ok admitted` | admission 失败 ⇒ ¬Prop |
| 3 | `PreservationBaseV1`（两分支均正要求 `initial = .ok pre`；无 init 再合取 holds；有 init 再全称 step） | initial 失败 ⇒ 两个 base 均为假；无-init 禁止 `Conforms → eval` 空真 |
| 4 | `PreservationStepV1` 全输入三分支 | 禁止压扁 Outcome；禁止省略 vault/context/responses |

### D4. Holds 形状（继承；kind = holds）

```lean
def InvariantTheoremV1
    (program : SemanticProgramV1)
    (ordinal : InvariantOrdinalV1) : Prop :=
  ordinal.toNat < program.invariants.size ∧
  ∀ state : LogicalStateV1,
    StateConformsV1 program state →
    evalInvariantV1 program ordinal state = .returnedTrue
```

1. 形状相对 ADR-0027 **零修改**。
2. **不** 引入 admission；**不** 声称 reachability / step safety。
3. Certifier kind=`holds` 时 expected Prop **仅** 此形状。

### D5. Revert / trap helper 使用纪律

1. Helper 可在无 invariant 的 suite 中单独钉死（Counter/EvenCounter step 轨迹），
   作为 ABI 前置机证，不依赖 MiniAmm。
2. Preservation 证明在 revert/trap 分支上应 **复用** D3.1 helper，再得
   pre 上 holds ⇒ 同 state 上 holds 的平凡步。
3. 禁止在业务 proof 中假设“revert 可改 logical state”。

### D6. 源码 proof kind、canonical 兼容、inventory

#### D6.1 语法与 kind canonical 兼容

| Kind | 源码形状 | 期望 closed Prop |
|---|---|---|
| **holds** | `proof Inv using Thm` | `InvariantTheoremV1 program ordinal` |
| **preserving** | `proof Inv preserving using Thm` | `PreservationTheoremV1 program ordinal` |

1. 既有 `proof Inv using Thm` **语义冻结为 holds**（`kind = holds`）；
   **canonical 兼容**：不得因本 ADR 改变其 expected Prop 或要求作者改写
   既有 holds 源码。
2. **显式** `preserving` 关键字进入 ProgramV1 `ProofDecl`（设计字段
   `kind : ProofKindV1`，closed enum `{ holds, preserving }`）；无第三种 kind。
3. AST/wire：**kind 为显式字段**；bare 语法 sugar 解码为 `holds`，与源码
   写明 holds（若未来允许）**同一** canonical kind 值，保证 sourceHash
   不因 sugar 分叉。
4. 禁止：
   - 无 kind 的“智能推断”到 preserving；
   - `proof Inv using Thm` 兼指 preserving；
   - 同一 `(Inv, kind)` 绑定多个 theorem 名；
   - 第三种 kind 或 open string kind。

#### D6.2 Inventory 键 = `(invariantName, kind)`

1. Theorem inventory / certifier bijection 的 **sole key** 是
   **`(invariantName, kind)`**（取代 ADR-0027 “每 invariant 至多一个 theorem”
   的单键模型）。
2. **允许** 每个 invariant：
   - **仅 holds**；或
   - **仅 preserving**；或
   - **双 kind**（holds 与 preserving 并存，两个 theorem 名，两条 binding）。
3. 每个 key 至多一条 binding；binding 集合与 source `ProofDecl` 集合
   **exact bijection**（无多余、无缺失 key）。
4. **程序级 proof 表面规则**：
   - **空表面**（零 `ProofDecl`）⇒ 显式 `noProof`，可跳过 certify；
   - **非空表面**（任意 ≥1 条 `ProofDecl`）⇒ **每一个** 已声明 invariant
     必须至少绑定 **一种** kind（holds 与/或 preserving）；禁止“只给部分
     invariant 挂 proof、其余裸奔”的半表面。
     （动机：非空表面表示作者选择了 proof 产品路径；半覆盖会制造
     false confidence。）
5. `noProof` 仍表示 **无任何** proof 表面；仅有 holds、仅有 preserving、或
   双 kind 并存，均属“有 proof 表面”，须 **全部** key certify 成功。
6. Inline certifier 按 kind 选择 expected Prop；audit / axiom policy /
   single-snapshot / proof-before-materialize **纪律不变**（现行读 ADR-0027；
   cutover 后本 ADR 与 0027 对齐，不弱化）。

#### D6.3 Ordinal

1. `ordinal` = source-order dense index into `program.invariants` /
   `InvariantDecl` 表；holds 与 preserving **共享** 同一 ordinal 空间。
2. kind **不** 进入 ordinal；kind 只进入 inventory key 与 cert digest。
3. OOB ordinal ⇒ 对应 kind 的 expected Prop 为假；certifier fail closed。

### D7. Hash 与 certification digest 边界

| 身份 | proof / kind 是否进入 | 说明 |
|---|---|---|
| **ProgramV1 / `sourceHash`** | **是** | `ProofDecl` 为 source item；**kind 是 AST 字段**。`holds` ↔ `preserving` 切换、增删 proof 项均改变 canonical source bytes 与 `sourceHash`。theorem **body** 仍在 program 外，**不** 进 `sourceHash`。 |
| **`SemanticProgramV1` / `semanticHash`** | **否** | proof 引用、kind、theorem 名、cert digest、alias 名 **永不** 进入 Semantic IR / structure-gated bytes。有无 proof、改 kind、改 theorem body 均不得改变 `semanticHash`。 |
| **proof certification digest** | **是** | digest 覆盖 binding 集的 **(invariantName, kind, theorem FQN, ordinal, subject program digest, trust-policy digest, …)**。kind 不同 ⇒ digest 不同；仅改 theorem body 也改 digest。holds-only 与 dual-kind 程序 digest 不同。 |

禁止：

- 把 certification digest 写回 ProgramV1 / Semantic；
- 把 kind 偷运进 requirements 或 target selection；
- 用 semanticHash 变化“证明” proof 已认证。

### D8. 产品边界：check-only / non-formal / materializer FC

1. **Check-only（工程）**：`check` 可对 holds 与 preserving 报告
   `proofStatus=certified`（及 count/digest 扩展含 kind）。**不** 要求 `build`
   因 preserving 而解锁新 target 行为。
2. **Materializer fail closed**：nonempty invariants 在八个 materializer 上
   既有 FC 纪律 **不变**；preserving proof **不** 放宽 Plan/IR/emit。Quint Q0
   read-only Bool invariant 既有例外独立，不因本 ADR 扩张。
3. **Non-formal**：本 ABI 与 kind-aware inline plumbing 是 engineering 命题/认证表面；
   **不是** formal `step`、不是 TST-SEM-002/003 corpus、不是 target refinement。
4. 不恢复 `--proof-bundle*` 产品路径；不把 library ProofBundle 当 alternate。
5. Proof gate 顺序（ADR-0027 基线；当前 engineering plumbing 已 kind 感知）：

   ```text
   single in-memory source snapshot
     → ProgramV1 decode / origin / theorem inventory (keys = (inv, kind))
     → CheckV1 → Normalize / CompiledSemanticV1
     → inline proof gate（bijection → subject → elaborate → audit → certify
          | explicit noProof when empty surface）
     → requirement resolve / capability → materialize …
   ```

   上表的 `(inv,kind)` inventory、alias、protocol 与 certifier 分支现为工程事实；
   `Counter` 与 `MiniAmmL1` ordinary same-file preserving product positives 均已闭合；
   ADR-0027 supersession 与 formal 门槛仍未满足。

### D9. Generic-first 合约路径；禁止 MiniAmm 平台特例

1. **历史 acceptance**：EvenCounter（偶数）与 ZeroCounter（等零）曾以
   package-owned bytes/decode/preservation + closed pin 证明 ABI 可工作。它们只作为
   迁移前 forcing instances；不是最终产品架构。
2. **2026-08-09 wave-3′ clean cutover**：
   - `ProofForgeV2.Semantic.Wire.CodecInvert*` 闭合 generic codec round-trip；
   - `PreservationShapeV1` 提供 contract-agnostic store/view/invariant shape families；
   - elaborator 生成结构化 `subjectDataV1` / `subjectProgramV1`，author theorem 直接
     `apply` 通用定理并用 `decide`/`rfl` 放电该合约形状；
   - `ProofForgeV2/ProofInstances/`、`ClosedSubjectPinV1`、
     `ParityCounter*`/`ZeroCounter*`、重复 internal examples/tests 均物理删除；
   - `ProofForgeV2/` 产品包不再 import 或包含合约专属 proof/data/pin。
3. **普通合约正例**：
   - `Examples/Counter.lean`：program + invariant + proof binding + ordinary theorem 同文件；
   - `Examples/MiniAmmL1.lean`：MiniAmm empty-pool P1 同样只在业务文件内，复用
     generic triple-UInt64 shape theorem；产品 certifier GREEN。
4. **禁止 MiniAmm 特例**：
   - 不得为 MiniAmm 引入第二套 State/Effect/step；
   - 不得在 `ProofForgeV2/Semantic/` 挂 MiniAmm-only helper 或 bytes；
   - 不得把 Map/cap/宽积/资产 credit 写进平台 ABI；
   - 所有业务谓词继续在各自源文件复用同一 `PreservationTheoremV1`，且必须保留
     exact admission 正义务。

### D10. 业务逻辑形式化主路径（track 1）vs 工具内部形式化（track 2）

ProofForge 上“形式化”分 **两条独立账本**，不得混写完成态：

| 轨道 | 形式化对象 | 当前权威 / 表面 | 状态纪律 |
|---|---|---|---|
| **Track 1 — 业务逻辑** | 用户 `program` 的 invariant / preservation（业务 P） | 本 ADR + ADR-0027 product gate；sole step = product Reference | generic-first 迁移完成；Counter + MiniAmmL1 ordinary same-file positives **GREEN** |
| **Track 2 — 工具内部** | compiler / Reference 机器 / wire metatheory 的 formal TASK/TST | `docs/04-task-breakdown.md` formal 任务与 TST ledger | **独立推进**；实例正例不关闭 formal TASK |

**Track 1 主路径**（任意合约目标形态；package 无 contract instance）：

```text
program P where
  state / init / entry / view / invariant inv : …
  proof inv preserving using AuthorThm     -- kind = preserving

-- same-file ordinary Lean theorem（program 外）
theorem AuthorThm : P.ProofPreserving.inv := by
  -- 目标 Prop = PreservationTheoremV1 P.Proof.subjectProgramV1 ordinal
  -- 证明义务：admission 正存在 + base + 全输入 step 三 Outcome
  apply <generic-shape-theorem> <;> decide / rfl
```

产品链：

```text
单次 read → selectProgramV1ProductWithTheoremInventory
  → normalize / compileProgramProductV1
  → structured subjectDataV1 / subjectProgramV1（exact SemanticProgramV1）
  → certifyInlineProofV1（kind → expected Prop；closed tactic audit；digest）
  →（成功后）target resolve / materialize …
```

纪律：

1. **Inline same-file 是产品义务表面**（ADR-0027/0034 D6/D8）：author theorem 与
   `program … where` 在**同一源文件**、同一 in-memory snapshot 上 cert；theorem body
   不进 `sourceHash`/`semanticHash`，但证明义务在源码文件里。
2. **产品包零合约专属内容**：`ProofForgeV2/ProofInstances/` 与
   `ClosedSubjectPinV1` 已删除。通用 heavy proof 仅以 contract-agnostic codec、
   Reference 与 shape-family 定理存在；业务 shape facts 与 ordinary theorem 留在源文件。
3. **Sole L1 执行权威**：`SemanticProgramV1 → admitReferenceProgramSliceV1 →
   stepReferenceSliceV1`。禁止第二套 State/Effect/step。
4. **Structured subject**：elaborator 直接生成 `subjectDataV1` 与
   `subjectProgramV1`；不得恢复 per-contract byte spine、golden pin 或 certifier pin hop。
5. **Inventory 表面**：certifier 只允许受限 `apply` / `exact` / `decide` / `rfl`
   组合；禁止任意 tactic 执行和外来 `.olean` 信任。
6. **不声称**：reachability 闭包、多步归纳、target refinement、formal TASK 关闭。

**当前业务轨道**：generic-first wave-3′ 已完成；`Counter` 与 `MiniAmmL1` 已按普通
same-file 合约路径 product GREEN。新增业务合约只能在自身文件复用通用 API。

## 与 ADR-0027 / research-023 的关系

| 文档 | 关系 |
|---|---|
| ADR-0027 | **当前 inline base authority**（`proposed`；无 successor）。holds 形状、snapshot/audit/axiom、proof-before-materialize 纪律仍以 0027 为准。本 ADR 是 **proposed extension/amendment**；D6 plumbing 与 D9 generic-first same-file product path 已实现。**单独** supersession 决策前不得把 0027 标 `superseded`。 |
| research-023 | L1 `Preserves P` 目标叙述的设计收口落在本 ADR；MiniAmm P1 已作为普通同文件合约通过，不获得平台特例；formal 与 supersession 仍 pending。 |

## 后果

### 正面

- Holds 与 step-preservation 命题边界清晰；admission 正义务堵住“未 admission
  却证明保持”的空真。
- `(invariant, kind)` inventory 允许单 kind 或双 kind，非空表面强制每 inv
  至少一种，避免半覆盖；该纪律已进入 engineering product plumbing。
- Outcome 三分支与 vault/context/responses 全量化对齐 product Reference。
- Generic codec/shape/elaboration 与 `Counter`/`MiniAmmL1` 两个 ordinary same-file
  certified positives 证明主路径可复用，同时保持产品包零合约专属内容。
- 0027 继续约束 inline base；0034 扩展已进入 generic-first 产品路径，但仍不假称
  任意合约自动可证或 formal 完成。

### 代价 / 风险

- ProgramV1 `ProofDecl` / Loader / inventory / certifier 已完成 kind 扩维；新增 source wire tag 与
  golden/oracle 需要原子 re-pin，不能保留 2/3-field dual reader。
- 全输入量化证明负担高于“空 responses 特例”；shape-family theorem 只覆盖已建模形状，
  新业务形状仍需新增**通用** lemma 或在业务文件内证明。
- 结构化 subject 与 closed tactic audit 需要同步维护 elaborator/certifier 契约；
  不允许通过恢复 byte pin 或 package-owned instance 降低证明成本。
- 非空表面“每 inv 至少一种 kind”比旧“proof 与 inv 全双射”更严于
  partial-proof 实验流；接受为产品诚实性。
- 0027/0034 文档并存：读者须区分 **inline base（0027）**、**L1 generic-first 扩展（0034）**
  与 **未完成的 supersession / formal**。

## 非目标

- **不** 因工程正例立即 supersede ADR-0027；**不** 把实例写成
  “全部业务合约已 formal”。
- 不关闭 formal TASK/TST；不升格 hermetic/release。
- 不解锁 nonempty invariant 的八 target materialization。
- 不定义 reachability 闭包、多步 trace 归纳框架、或跨交易 atomicity。
- 不把 value/effects 守恒、token 资产不变量并入本 ABI（可后续独立族）。
- 不为 MiniAmm / MiniAmmAssets 增加平台特例路径。
- 不要求 base-with-initializer 证明“存在一次成功 init”（仅全称成功⇒holds）。
- 不恢复 `ClosedSubjectPinV1`、`ProofInstances/` 或合约专属 byte spine。

## 实现切片顺序

工程顺序（仍非 formal；**单独** 文档决策后再记录 0027 supersession）：

1. **已完成 — ABI foundation**：`PreservationTheoremV1` + base/step/helpers（与
   `InvariantABI` 并列）；positive initial/admission + 完整 Outcome Prop。
2. **已完成 — Wire/AST + inventory/certifier plumbing**：`ProofKindV1` + 三字段 wire +
   `proof … preserving using …`；bare `proof … using` ⇒ holds；inventory 键 `(inv,kind)`、
   非空表面每 inv ≥1 kind、kind 进入 theorem-set/cert digest；无 2-field fallback。
3. **已完成 — Alias plumbing**：`Proof.<Inv>` holds 兼容；
   `ProofPreserving.<Inv>` preserving；共享 `Proof.subjectProgramV1`；simple-closure helper holds-only。
4. **已完成 — generic codec round-trip**：`CodecInvert*` 闭合 encode/decode 反演。
5. **已完成 — shape-family preservation**：`PreservationShapeV1` 仅含
   contract-agnostic callable/invariant/step families。
6. **已完成 — structured elaboration**：生成 `subjectDataV1` / `subjectProgramV1`；
   certifier 受限支持 `apply`/`decide`/`rfl`，无 pin hop。
7. **已完成 — ordinary same-file contracts**：`Examples/Counter.lean` 与
   `Examples/MiniAmmL1.lean` product certified。
8. **已完成 — clean deletion**：删除 `ProofInstances/`、`ClosedSubjectPinV1`、
   ParityCounter/ZeroCounter 专属模块与重复 examples/tests；刷新 umbrella/SBOM/docs。
9. ADR-0027 → `superseded` / `successor=ADR-0034` 仅可由后续单独决策执行。

## 状态

- `proposed` / ABI + kind plumbing + wave-3′ generic-first migration GREEN / 2026-08-09
- 已交付：通用 codec invert、Preservation packaging/shape families、structured subject
  elaboration、Counter/MiniAmmL1 ordinary same-file product positives、合约专属产品模块删除；
  **ADR-0027 保持 `proposed`，无 successor/横幅**
- 未交付：formal/product maturity 与 ADR supersession
- 禁止：修改 Reference 机器或加入 MiniAmm 特例；禁止恢复 pin/ProofInstances；
  禁止把工程实例正例写成任意合约自动可证 / formal 完成
