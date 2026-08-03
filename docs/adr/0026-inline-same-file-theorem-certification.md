---
id: ADR-0026
title: Inline same-file theorem certification（engineering product path）
status: proposed
owner: architecture
updated: 2026-08-04
normative: true
---

# ADR-0026：Inline same-file theorem certification（engineering product path）

- 状态：`proposed`
- 日期：2026-08-04

本文是 **decision-complete proposed** 工程契约：冻结 inline same-file invariant
theorem certification 的产品边界与 fail-closed 纪律，供 language / semantic / CLI /
security / test 规格对齐。本文 **不是** formal approval、hermetic containment、
release qualification，也不关闭 `TASK-D2-06`/`TASK-D2-07`/`TST-PROOF-001` 或任何
formal EV。

## 背景

既有规格以 digest-pinned 外部 `ProofBundleV1` + locked `.olean` 作为
`proof x using N` 的 theorem 装载模型。工程实现同时演进了 **同文件相邻 ordinary Lean
theorem** 路径：产品在 **单一 in-memory source snapshot** 上完成 ProgramV1
decode → Check/Normalize → `CompiledSemanticV1`，再对同一 raw source 做 in-process
elaboration，并对 Environment 做 declaration-kind / defeq / dependency / axiom 审计。

若不把该路径写成明确边界，文档容易：

1. 把 theorem body 误写入 ProgramV1 / semantic identity；
2. 把 in-process elaboration 误写成 sandbox / contained worker；
3. 把 `InvariantTheoremV1` 的 StateConforms 全称量化误升为 reachability / init-step /
   target refinement 或 formal TST 闭合。

本 ADR 只冻结 **engineering product certification** 的最小完整契约。

## 决策

### D1. Single in-memory source snapshot

1. 产品 `check` / `build` 对选定 source 只建立 **一次** 已校验 in-memory snapshot
   （raw UTF-8 bytes / String + 由同一字节派生的 `ValidatedSourceV1` /
   origin / theorem inventory / `CompiledSemanticV1`）。
2. Inline certification **不得** 为 theorem 路径重新 `open` / `readFile` source，
   也不得切换到另一路径、另一 symlink 目标或另一 module 的磁盘内容。
3. In-process elaboration 的输入必须是该 snapshot 持有的 raw source 文本
   （同一 `fileName` / module selector 逻辑名仅作诊断与 Environment 模块名，
   不构成第二数据源）。

### D2. Identity：ProgramV1 / semantic hash 不含 theorem body

1. **Adjacent Lean theorem body**（`theorem … := by …` 的证明项 / tactic 树）位于
   `program … where` command **之外**，是 ordinary Lean declaration surface。
2. ProgramV1 canonical AST bytes 与 `sourceHash` **不编码、不哈希 theorem body**。
   改变证明项而保持 program 项与 `proof` 引用不变时，`sourceHash` 必须保持不变。
3. `SemanticProgramV1` / `semanticHash` / structure-gated semantic bytes **永不** 携带
   proof reference、theorem name、proof term 或 certification digest。有/无 proof、
   改写 theorem body 均不得改变业务 semantic identity。
4. `proof Ident using QualifiedName` 若作为 ProgramV1 item 存在，仅是
   **certification metadata binding**（invariant name ↔ expected theorem FQN），
   不进入 Semantic IR；其存在与否可影响 source-level inventory，但不得影响
   `semanticHash`。
5. 成功 certification 的 summary / digest（request digest、theorem-set digest、
   proofCertificationDigest、policy digest 等）**不得** 回写进 ProgramV1 或
   SemanticProgramV1，也不得参与 target selection。

### D3. Ordinary adjacent Lean theorem

1. 作者在 **同一 `.lean` 文件**、program command 之后，以 ordinary Lean
   `theorem` 写出证明（工程 inventory 可要求有限 tactic allowlist；kernel 侧仍做
   Environment 审计）。
2. Expected proposition 的唯一 closed shape 是：

   ```lean
   ProofForgeV2.Semantic.InvariantABI.InvariantTheoremV1 program ordinal
   ```

   其中 `program` 为当前 compiled closed `SemanticProgramV1`，`ordinal` 为
   source-order invariant 的 dense ordinal。
3. 工程路径可生成 program-local Prop alias（例如
   `<programIdentity>.Proof.<invariantName>`）与 subject program literal
   （`<programIdentity>.Proof.subjectProgramV1`），但其 **definitional content**
   必须与 compiled semantic bytes / 上述 closed ABI **exact** 对齐；不得用
   hash-only、propositional cast 或未解 metavariable 替代。
4. 每个 invariant 最多一个 theorem；inventory 与 source proof/invariant 必须
   exact bijection。空 proof 表面是显式 skip（`noProof`），不是伪造 success。

### D4. In-process elaboration 不是 sandbox

1. Inline certification 的 elaboration **在当前 compiler 进程内** 运行
   （engineering `elaborateInlineProofSourceV1` 类路径）。
2. 该路径 **不是**：
   - process/session containment sandbox；
   - frontend/compiler-core contained worker；
   - 空 `LEAN_PATH` / deny-default 的 proof-bundle safe loader；
   - formal hermetic / Stage-0 / clean-room evidence surface。
3. 因此不得把 inline elaboration 成功写成 contained、hermetic 或 formal proof
   evidence。资源 wall/memory 若强制，只能是 **同一进程内** 预算，不升格 assurance
   class。

### D5. Environment audit（declaration-kind / defeq / dependency / axiom）

成功 mint private certification carrier **之前**，必须对 elaborator 产出的
`Environment` 做 structured audit（engineering `InlineProofAuditV1` 契约）：

| 检查 | 要求 |
|---|---|
| Root kind | 产品 root 必须是 **theorem**；opaque / def / axiom / induct 等拒绝 |
| Type defeq | kernel 下 type 与 expected Prop（生成 alias / closed `InvariantTheoremV1`）defeq |
| Safety | 拒绝 `unsafe` / `partial` root 与 value |
| Value / sorry | root 必须有 value；value/type 不得含 `sorryAx` |
| Attributes | 用户 main-module 声明拒绝 `implemented_by` / `extern` / initializer |
| Dependency closure | 递归 type/value constant 闭包不得含用户 axiom、`sorryAx`、上述 forbidden attrs |
| Allowed base axioms | 闭包中 **仅** 允许固定集合（见 D6） |

失败 fail closed：不得进入 target resolve、Plan/IR、finalize 或 artifact staging。

### D6. Fixed allowed axioms

Trust policy schema `proof-forge.proof-trust-policy.v1` 固定：

```text
allowedBaseAxioms = ["Classical.choice", "Quot.sound", "propext"]
```

全部 capability flags 为 `false`（含 bundle axioms、unsafe、partial、extern、
implemented_by、initializers、environment extensions、syntax/elaborators、
native artifacts、arbitrary term elaboration）。policy digest 由 compiler-owned
payload 唯一派生；caller **不得** 放宽。

### D7. 不信任用户 `.olean`

1. Inline path **不得** 把用户提供的 `.olean`、project/parent `.lake`、ambient
   `LEAN_PATH` 搜索命中或外部 proof-bundle modules 当作 theorem authority。
2. 不把用户 `.olean` digest 当作 success 证据；不把 ambient Environment 中既有
   同名 declaration 当作本 snapshot 的证明。
3. 外部 `ProofBundleV1` + locked olean loader（若仍存在于历史/并行工程面）是
   **另一条** 路径，不得与 inline snapshot 混用 fallback。

### D8. Proof gate 早于 target resolve / materialization / staging

固定产品顺序：

```text
single in-memory source snapshot
  → ProgramV1 decode / origin / theorem inventory
  → CheckV1 (structure→type→effect→bound→disclosure)
  → Normalize / CompiledSemanticV1
  → inline proof gate（inventory bijection → subject → elaborate → audit → certify
       | explicit noProof when empty surface）
  → requirement resolve / capability
  → target Plan / IR / materialize / finalize / publish
```

规则：

1. Proof gate **严格在** target resolve、materialize、staging、rename publish **之前**。
2. 任一 proof 失败：零 Plan、零 TargetIR、零 destination artifact 变更。
3. `noProof`（无 proof 表面）不是失败，可继续后续 resolve；有 proof 表面则必须
   全部 certify 成功。
4. Certification summary 可进入 check/build 人类/JSON 观察面，但 **不** 进入
   semantic/plan/output identity 的业务 hash（除非独立、显式命名的 engineering
   sidecar 契约另行冻结，且不得回写 semantic）。

### D9. 当前命题范围与明确非声称

**当前唯一 accepted proposition shape**（engineering + ABI）：

```lean
InvariantTheoremV1 program ordinal :=
  ordinal < program.invariants.size ∧
  ∀ state : LogicalStateV1,
    StateConformsV1 program state →
    evalInvariantV1 program ordinal state = .returnedTrue
```

即：在 **所有满足 `StateConformsV1` 的 logical state** 上，选定 invariant 求值为
`.returnedTrue`。

本 ADR **明确不声称** 下列任一完成或被证明：

| 非声称 | 说明 |
|---|---|
| Reachability | 不证明 state 由 init/entry 可达 |
| Init / step safety | 不证明 `initialLogicalState` 或 `step` 后自动保持 |
| Target refinement | 不证明 EVM/Solana/NEAR/… 制品细化 reference |
| Formal `step` / TST-SEM-002/003 | formal reference corpus 仍 pending |
| Formal TST-PROOF-001 | formal proof-bundle / olean closure 验收仍独立 |
| Hermetic / contained / Stage-0 / release | 不得用 ordinary CI 或 inline cert 代签 |
| Nonempty invariant materialization | 八 materializer 对 nonempty invariants 仍可 fail closed |

## 与 ProofBundleV1 的关系

- **Inline same-file** 是本 ADR 冻结的 **engineering product certification 主路径**。
- 外部 `ProofBundleV1` / digest-pinned olean 规则保留在 `SPEC-SEM-001` 等文档中作为
  **historical / alternate / formal-oriented** 设计面；在显式 formal task 与产品
  cutover 完成前，不得把两条路径写成可静默互替的 fallback。
- 两条路径共享同一 `InvariantTheoremV1` / `StateConformsV1` / trust-policy axiom
  集合 identity，但 **装载与执行环境不同**（in-process snapshot vs locked olean
  map），assurance 声明不得混写。

## 后果

### 正面

- 作者可在同一源文件维护 program 与证明，缩短 engineering 反馈环。
- 身份边界清晰：业务 semantic 与 proof body 解耦。
- Fail-closed gate 阻止未审计 theorem 进入制品链。

### 代价 / 风险

- In-process elaboration 扩大 compiler 进程 TCB（非 sandbox）；文档与 CLI 必须诚实。
- 有限 tactic inventory 与 full kernel 审计是两层；syntax allowlist **不** 替代
  Environment audit。
- Formal TST / release 仍须独立闭合；engineering 绿不得升格。

## 非目标

- 不新增 formal `TASK-*` / `EV-*` / freeze package。
- 不恢复 frontend supervisor 为 proof sandbox。
- 不解锁 target 对 nonempty invariants 的 materialization。
- 不定义 ZK prove/verify、deploy 或 network 侧 proof。
- 不把 `proofCertificationDigest` 绑入 formal OutputSetV1。

## 文档与实现对齐要求

| 文档 | 对齐点 |
|---|---|
| `docs/02-architecture.md` | 数据流插入 inline proof gate；非 sandbox 边界 |
| `docs/03-technical-spec.md` | 公共数据流顺序 |
| `SPEC-LANG-001` | adjacent theorem surface；hash 不含 body |
| `SPEC-SEM-001` / `SPEC-SEM-WIRE-001` | ABI 命题范围；cert metadata 不进 semantic |
| `SPEC-CLI-001` | gate 顺序；不信任用户 olean；summary 边界 |
| `SPEC-SEC-001` | in-process 非 sandbox；固定 axiom policy |
| `docs/05-test-spec.md` | engineering 覆盖 vs formal TST-PROOF-001 |
| `MIGRATION_MATRIX` / `AGENTS.md` / log | engineering 事实与非 formal 措辞 |

## 状态

`proposed`。落地实现与 ordinary CI 通过后，仍只记为 **engineering** 完成；formal
acceptance 需要独立 owner 流程，不由本 ADR 自动授予。
