# ProofForge 全量代码 + 架构评审（2026-07，FV-5 能力门分支）

- **评审对象**：`cursor/fv5-overflow-capability-gate` 分支（HEAD `bbf1582a`），
  覆盖可移植 IR、Target 能力路由、各链后端、以及当前正在实现的形式化验证
  （FV-1 / FV-4 / FV-5）部分。
- **定位**：原生中文分析文档，**不是工程权威源**。与
  [architecture-review-2026-07](architecture-review-2026-07.md)、
  [feasibility-analysis](feasibility-analysis.md) 同类。可落地为工程策略的
  结论应回写英文文档（`docs/decisions.md`、相关 RFC、
  [implementation-backlog](../implementation-backlog.md) Workstream 25）。
- **上一篇的分工**：`architecture-review-2026-07.md` 评审的是"分支模式 vs
  主干化"这条组织线；本文评审的是**实现正确性与 FV 可靠性**这条代码线，
  二者互补、不重叠。

---

## 总体结论

这是一个**架构清晰、工程纪律罕见地扎实**的项目。核心命题——"一份 Lean 合约
→ 可移植 IR → 按能力路由到各链后端，不支持的能力在编译期拒绝而非静默改变
语义"——立得住，代码也忠实实现了这个分层。约 75K 行 Lean，43K 在后端层，
成熟度分级诚实（EVM / Solana / NEAR 生产形态，Aleo / Move / CosmWasm 明确标注
为 spike），无跨后端耦合、无 god-module、无 TODO/FIXME 烂账。

**形式化验证部分的诚实度是最大亮点**：`docs/formal-verification.md` 用
Tier A / C-diff / C-proof 三层表格明确划分"证明了什么 / 没证明什么"，主动防止
对外过度宣称。这在同类项目里极少见，应当保持。

**但当前分支的 FV-5 overflow gate 存在一个实质性问题：这个 gate 对所有真实
合约是失效的**，而它本要防住的跨链溢出分歧，恰恰在每一个真实合约上都在发生。
详见第三节 P0。

---

## 一、架构层面：设计合理的地方

1. **分层边界干净**。`Authoring（Intent API / .learn / Token SDK）→ ContractSpec
   → Portable IR → Capability 路由 → Backends → Artifacts+Gates` 与代码一一对应。
   `ProofForge/Target/` 只有 ~1150 行却承担了整个路由契约，职责收敛得很好。

2. **D-027（目标扩展隔离）是正确的边界**。链专属语义（Solana CPI/PDA）通过
   capability id + metadata 走，而不是往可移植 IR 里塞链专属构造子。而且这条被
   机器验证了：`requireTargetExtensionMetadata_ok_iff`
   （`ProofForge/Target/Formal.lean:13`）是**全称量化**的结构归纳，不是
   `native_decide`——这是"对的证明形态"。

3. **FV-1 路由可靠性是真证明**。`requireCapabilityPlan_sound`
   （`ProofForge/Target/Formal.lean:26`）对所有 profile / plan 成立，把"拒绝而非
   静默改变语义"变成了 kernel 检查的不变量。

4. **`ChainSemantics`（`ProofForge/Target/ChainSemantics.lean`）把跨链语义分歧
   显式建模**（native amount 的单位与位宽、事件索引模型、crosscall 模型），
   而不是假装它们一样。这个建模方向是对的。

5. **后端成熟度分级健康、无跨后端耦合**。EVM（30 文件，参考实现）、
   WasmNear（34 文件，最模块化）、Solana（扩展层重）、Psy（精简）各自独立可测；
   Aleo / Move / CosmWasm 明确是 spike/stub。最大的文件（`Evm/IR/Expr.lean`
   ~1442 行）是领域集中而非 god-module。

---

## 二、架构层面：需要改进的结构性问题

### ① 能力派生的"二选一"是一个潜在可靠性漏洞（根因）

`capabilityCallsForSpec`（`ProofForge/Target/Adapter.lean:37`）逻辑是：

```
if intentCalls 非空 then intentCalls else moduleCalls
```

**有 intent 时，模块体真正用到的能力被整体丢弃**。而
`CapabilityPlan.capabilities`（`ProofForge/Target/Plan.lean:33`）完全从 `calls`
派生。后果：**`resolveSpec` 可能对一个"模块体用了目标不支持的能力"的 spec
返回 `.ok`**，只要 intent 声明不完整。

FV-1 的 soundness 定理虽然对 plan 成立，但它保证的**不是**用户真正关心的性质
（"模块只用受支持的能力"）——因为 plan 不忠实反映模块。`overflowChecked` 只是
第一个暴露出来的实例；任何"模块体产生但 intent 未声明"的能力
（`.cryptoHash`、`.controlBoundedLoop` 等）都可能同样漏过。

**建议**：把 `capabilityCallsForSpec` 改成 `intentCalls ∪ moduleDerivedCalls`
（去重），或补一条引理 `moduleCapabilities ⊆ planCapabilities`。这样
checkedArithmetic 自然流过 `requireCapabilities`，FV-5 的专用 gate 可以删掉。

### ② `native_decide` 用了 130 处（Tests 另有 23 处），扩大了 TCB

对一个卖点是形式化验证的项目，用"编译到原生代码再运行"来"证明"定理，等于把
Lean 编译器和 FFI 拉进可信基（不同于 `decide` 是 kernel 检查的）。文档说清了它是
pointwise，但没提这层 TCB 扩张。这些多是小 fixture，很多可以降级成 `decide`。

**建议**：审计哪些 `native_decide` 能降级到 `decide`；在 TCB / non-goals 里显式
写明"信任 Lean 编译器"这一条。

### ③ `partial def` 576 处，是通往真正（C-proof）验证的最大障碍

核心 IR 解释器 `evalExpr` / `runEntrypoint`（`ProofForge/IR/Semantics.lean`，
第 420、561… 行）与 ownership checker（`ProofForge/IR/Ownership.lean`）都是
`partial def`——**放弃了归纳原理**。这就是为什么 FV-2 / FV-3 都卡住、整个 FV
故事上限只能停在"对 fixture 做 `native_decide`"：那个"万物据以 refine 的可执行
语义"自己没法被归纳。文档 FV-3 已诚实承认这点。

**建议**：把定理需要的那部分核心解释器 / 检查器改写成良基 `def`
（`termination_by` 或 fuel）。这是大投入，但是解锁 C-proof 的必经之路。

### ④ RFC 0014 的 ModulePlan 收敛只做了一半

各后端 `PlanError` / `LowerError` 命名与类型各异；`ProofForge/Backend/Diagnostic.lean`
定义了 `LoweringError` typeclass，但**没有任何后端实现实例**（Phase 3 机制在、
实例为零）。这类半迁移要么补完，要么在 backlog 里显式 park，否则会误导后来者
以为已统一。

---

## 三、当前实现（FV-5 分支）的具体问题

### 🔴 P0 —— FV-5 overflow gate 对真实合约完全失效，底层分歧未处理

逐段追踪链路，代码与项目自己的文档互相印证：

| 环节 | 事实 | 证据 |
|---|---|---|
| SDK 的"检查"操作符 | `+!` / `-!` / `*!` / `/!` → `addValue`/… → 普通 IR `.add`，**不设 `overflowChecked`** | `Contract/Source.lean:81-94` |
| gate 触发条件 | 仅当 `spec.module.overflowChecked = true` 才拒绝 | `Target/Adapter.lean:143` |
| 谁设过该 flag | **全代码库只有一处**——FV-5 测试 fixture 自己 | `Target/FV5Overflow.lean:36` |
| EVM 实际 lowering | `.add` → `__pf_checked_add`（溢出 revert），**无视 flag，恒为 checked** | `Backend/Evm/ToYul/Helpers.lean:19,48` |
| Solana 实际 lowering | `.add` → `.add64`（静默回绕），恒为 wrapping | `Backend/Solana/SbpfAsm/Expr.lean:81` |
| NEAR 实际 lowering | `.add` → `i64.add`（静默回绕），恒为 wrapping | `Backend/WasmHost/LoweringEnv.lean:40` |

**推论**：Counter、ValueVault、ERC20、ERC1155、NearFungibleToken 等真实合约通篇
用 `+!`，但 `overflowChecked` 全是默认 `false`。于是：

- 任何一个合约**同时**编译到 EVM 和 Solana/NEAR，**产物的溢出语义就已经不一致**
  （EVM revert，Solana/NEAR 静默回绕）——这正是平台承诺要消除的"静默改变语义"。
- FV-5 gate **一次都不会触发**，因为没有真实合约会把 flag 设成 true。
- `docs/capability-registry.md:81-105` 自己也承认这是"平台里最实质的跨链语义
  分歧"，且 gate "exposes but does not yet enforce per-node"。

更微妙的一点：默认值 `false` 的**宣称含义是"到处都 wrapping（可移植）"**，但
**EVM 根本不兑现**这个含义（它恒为 checked）。所以默认态既不是"到处 wrapping"，
也没有 gate 兜底——三不靠。这条 commit 把自己框定为"完成了 arith.checked
story"，实际风险是给人**已经防住了分歧**的错觉，而真实防护面只覆盖一个 SDK
永远不会产生的模块状态。

**修复方向（择一或组合）**：

- （治标）让 `contract_source` 的 `+!` 或 EVM elaboration 在检测到显式 checked
  操作符时置 `overflowChecked := true`，至少让"SDK 里读作 checked 的东西"和 flag
  对齐。
- （治本，推荐）**把溢出模式下沉到 IR 节点级**：`.add` 携带 `checked | wrapping`
  标签。这样 EVM 的 checked、Solana/NEAR 的 wrapping 就成了**每个节点可判定、
  可 gate、可证明**的属性，而不是一个模块级、没人设、EVM 还不遵守的开关。同时
  把默认从"false=wrapping 但 EVM 不认"改成"未标注即为需拒绝的 mismatch"，与
  平台的 reject-by-default 承诺对齐。
- （最低限度）在此之前，至少让 EVM 在 `overflowChecked=false` 时也 emit wrapping
  （`addmod 2^256` 式），以兑现默认值的宣称语义；否则默认态本身就是静默分歧。

### 🟠 P1 —— Solana refinement 的 obligation 过弱，"定理"名不副实

`TraceObligation.hasEntrypointDispatch`（`Backend/Solana/Refinement.lean:119-123`）：

```lean
asm.contains s!"entry_{entrypointName}" || asm.contains entrypointName
```

第二个析取项 `asm.contains entrypointName` 是**裸子串匹配**：只要入口名作为子串
出现在汇编文本任意位置（注释里、更长标识符里、字符串里）就算通过。入口名 `get`
会被 `budget` / `target` / `getter` 或任何含 "get" 的注释命中。于是
`counter_sbpf_artifact_surface_ok`（`Backend/Solana/Refinement.lean:171`）这个
`native_decide` "定理"证明的东西，远弱于它的名字和 docstring 声称的"每个入口都有
dispatch label"。

**建议**：删掉裸子串那一支，只匹配真实 label 形态（`entry_<name>:` 或真实
dispatch 助记符）。obligation 的强度只等于它最弱的那一支。

### 🟡 P2 —— 命名 / 表述问题（非 bug，但会误导）

- **pointwise `native_decide` fixture 检查却叫 `theorem`**（遍布三个 Refinement
  层）。文档层用 Tier 表缓解了，但代码不自证。建议加命名约定
  （`_fixture_ok` / `example_`）或 tag 注释，区分"逐点检查"与"全称定理"。
- **`EvmBytecodeSemantics` 的 stub**（`step_noop : step s = s := rfl`，
  `Backend/Evm/EvmBytecodeSemantics.lean:95`）是诚实标注的 seam，被 Phase 6b
  工具链版本冲突（Lean v4.22 vs v4.31）正当地 block 住。没问题——但别让
  "sorry-free stub theorem"被当成 anchor 计入进度。
- `Lean.Evm` namespace 遮蔽 Lean 编译器自身的 `Lean`——已在 Workstream 24 记录，
  无需重复处理。

---

## 四、优先级建议清单

| 优先级 | 动作 | 理由 |
|---|---|---|
| **P0** | 把溢出模式下沉到 IR 节点级（`.add` 带 checked/wrapping 标签），或至少让 `+!` / elaboration 设置 `overflowChecked` | 当前 gate 对真实合约失效，最实质的跨链分歧仍在静默发生 |
| **P0** | `capabilityCallsForSpec` 改为 `intent ∪ module` 去重（或加 `moduleCaps ⊆ planCaps` 引理） | 根因；修好后 FV-5 专用 gate 可删，FV-1 定理才真正覆盖用户关心的性质 |
| **P1** | 收紧 `hasEntrypointDispatch`，删掉裸子串匹配 | 让 Solana artifact-surface obligation 名副其实 |
| **P2** | 审计 `native_decide` → `decide` 的可降级项；TCB 文档补"信任编译器"条目 | 收敛验证产品的可信基 |
| **中期** | 把核心 IR 解释器 + ownership checker 从 `partial def` 改成良基 `def` | 解锁 FV-2 / FV-3 / C-proof 的唯一路径 |
| **收尾** | 补完或显式 park RFC 0014 的 `LoweringError` 实例迁移 | 消除半迁移状态 |

---

## 五、映射完整性、目标语义与 FV 就绪度（补充评审，2026-07-07）

本节回应四个架构级追问：IR→多目标映射能否"完全映射"、Solana SBF 是否有更强
建模、"写一份合约按 target 自动生成部署格式"的达成度、以及语义层为融入形式化
验证还需哪些调整。

**一句话前提**："能力检查通过" ≠ "能正确降级"。下面分小节展开（5.1 映射完整性 /
5.2 Solana 建模 / 5.3 部署格式 / 5.4 refinement 的精确含义 / 5.5 FV 就绪度 /
5.6 keystone 建议）。

### 5.1 IR→目标映射不完整：拒绝逻辑散在三层，只有最粗的一层被证明

真实的"拒绝不支持"发生在三层、三种机制、证明状态各异：

| 层 | 机制 | 证明状态 | 问题 |
|---|---|---|---|
| ① Capability 路由 | profile 能力集（粗粒度） | FV-1 已证（全称） | 过度近似：说支持就整类支持 |
| ② 各后端 Validate | 硬编码错误臂 | 未证、逐后端重写 | 漏写就漏过 |
| ③ 各后端 Lower | "Phase 1 unsupported" 臂 | 未证 | 到 codegen 才失败 |

三层未对齐的证据链：

- `crosscallInvokeNamedValue` 的能力被映射成**通用 `.crosscallInvoke`**
  （`IR/Contract.lean:421`），EVM 声明了该能力 → **能力层根本不拒绝它**；真正
  挡住它的是 EVM 硬编码的 Validate 臂
  （`Backend/Evm/IR/Validate.lean:197`："NEAR promise API is not supported on EVM"）。
- 对比 `crosscallContinue` → `.nearPromise`（仅 wasmNear，`Registry.lean:117`），被
  能力层与 Validate 层**双重拦截**。同类节点、拦截责任不一致。
- Solana codegen 遍布 `"unsupported ... in Phase 1"`
  （`SbpfAsm/Expr.lean:523`、`Stmt.lean:439`），但其 profile 却声明支持
  `.storageArray` / `.dataStruct` / `.dataDynamicArray`。**于是一个 spec 可
  `resolveSpec = .ok`，却在 SbpfAsm 阶段以 Phase-1 失败。**

**结论**：某目标"真正能忠实降级的 IR 片段" = 能力集 − 硬编码 Validate 拒绝 −
Phase-1 缺口。这个集合**没有单一真相源、未被证明，且被证明的能力层恰是过度
近似的一层**。今天靠 CI 的 Python 覆盖清单兜底
（`scripts/{evm,near,psy}/check-ir-coverage-manifest.py`），且 **Solana 连这个
脚本都没有**。

**根因**：链专属节点（`nearPromise*`、`crosscallInvokeNamedValue`）混在可移植 `Expr`
里，违反 D-027 精神（链专属语义应走 metadata/capability id，而非共享 IR 构造子）。
三个方向：

- **（治本）** 把这些 NEAR 节点移出可移植 `Expr`，做成经 metadata 路由的 NEAR
  扩展节点（就像 Solana CPI/PDA 声称的那样），让可移植 `Expr` 恢复真正链中立。
- **（最低限度）** 给每个链专属节点一个**唯一能力**（先修
  `crosscallInvokeNamedValue → .nearPromise`），让能力层单独就能干净拒绝，不再靠各
  后端补硬编码 Validate 臂。
- **（长期）** 为每目标定义显式"支持片段"谓词做单一真相源，并证两条：
  `能力接受 ⟹ 属于片段` 与 `属于片段 ⟹ 降级成功（totality）`。这才把"完全映射"
  从口号变成定理。

### 5.2 Solana SBF 建模：有类型化指令集，但零指令语义

- **好的一面**：`Backend/Solana/Asm.lean`（251 行）是真正类型化的 sBPF 指令模型
  ——`Reg`(r0–r10) / `Imm` / `MemOff` / `Opcode`（带
  `isLoad`/`isStore`/`isCondJump`/… 分类）/ `Inst` / `AstNode` / `Section` /
  `DataInit`。比字符串拼汇编强得多，是可做 FV 的底子。
- **缺的一面**：**没有任何 sBPF 指令语义**（全项目无对指令的 `step`/`exec`/`eval`）。
  `Solana/Refinement.lean` 跑的是 **IR 解释器** + 对渲染文本子串匹配，完全没碰
  指令语义。
- **后果**：三后端语义完备度 EVM（Yul 子集解释器 `YulSemantics.lean`）> NEAR
  （offline-host 可执行）>> Solana（无）。**Solana 目前无法陈述 IR↔sBPF
  refinement**，因为等式右边不存在。这是 Solana 在 FV 上的最大短板。

**建议**：按 `docs/solana-sbpf-executable-trace.md`，先写**最小 sBPF 解释器**覆盖
`AstNode` 子集（寄存器堆 + 线性内存 + Counter 用到的 ~15 个 opcode），再建 IR↔sBPF
差分 trace obligation。完整 CPI/syscall/账户模型语义应留在外部差分门
（Mollusk/Surfpool），这是正确的 non-goal。

### 5.3 自动部署格式生成：产物层面已达成，"一键部署"仅 EVM

- **产物生成相当完整**，Solana 尤其：`Package.lean`（Cargo sbpf-project）+
  `Manifest.lean`（806 行）+ `Idl.lean`（Anchor 风格 IDL，318）+ `Client.lean`
  （客户端，145）；`emit --format elf` 直接出可部署 `.so`。EVM 出
  bytecode+ABI+`proof-forge-deploy.json`。**"写一份合约 → 指定 target → 得到该
  链部署格式"在产物层面基本达成。**
- **但 `proof-forge deploy`（`Cli/Deploy.lean`）只做 EVM**（从
  `proof-forge-deploy.json` 广播 initcode 到 Anvil/cast）。其余链的实际广播靠原生
  工具（`solana program deploy`、`near deploy`）。
- **诚实表述**：现状是"生成部署就绪的包/清单/IDL/客户端"，不是"一键部署到任意
  链"。建议要么补各链广播适配器，要么把承诺明确改为"生成部署就绪产物，部署用
  各链原生工具"；并做一个跨链统一的部署清单 schema。

### 5.4 「相等性映射」的精确含义：refinement，而非语义整体相等

"把自定义 IR 语义与各链语义做相等性映射"这个直觉是对的，但要收紧成能真正建立的
命题，有五个限定：

1. **相等的是「可观测投影」，不是两套语义的整体状态。** 不证 `IR 内部状态 ==
   链上机器状态`（类型都不同：IR 是抽象变量绑定；EVM 是 256-bit 字的
   stack/memory/storage；sBPF 是寄存器 + 线性内存），而是两边各经一个 `observe`
   投影出**外部可观测 trace**（返回值、事件日志、revert 结局），再让这两个 trace
   相等。术语是 **refinement**；命题是等式，但等的是投影后的东西。
2. **方向性：目标 refine IR，IR 是真相源。** 是"具体实现忠实于抽象规范"，不是
   "两个对等物相等"。
3. **对「所有 input」全称，不是对固定 fixture。** 现在满地的 `native_decide`
   其实就是这个相等性——只是对**一条具体场景**逐点判定
   `observe(run 场景) == 预期`。目标是把 fixture 换成 `∀ input`；这一跳
   （pointwise → universal）就是 C-diff → C-proof，被 `partial def`（不能归纳）卡住。
4. **相等只在「支持片段」内成立，片段外义务是「干净拒绝」。** 所以其实是两条义务：
   `片段内 ⟹ 可观测相等` + `片段外 ⟹ encode 报错`（正是 5.1 要收敛的东西）。
5. **证的是 IR 对「目标的 Lean 模型」，不是真实链运行时。** 你在 Lean 里建每条链的
   语义模型（EVM Yul 子集解释器、NEAR offline-host、Solana 那个**尚不存在**的 sBPF
   解释器），证 `IR ≡ Lean 模型`；"Lean 模型 ≈ 真实运行时（solc/sbpf/VM）"那一跳留
   在差分测试信任边界（明确的 non-goal）。

**一个具体例子（Counter）**：

- IR 侧：跑 `[initialize, get, increment, get]` → 可观测 trace `[(), 0, (), 1]`。
- 目标侧：把产物喂给该链的 Lean 语义 → 可观测 `[(), 0, (), 1]`。
- **定理**：这两个可观测 trace 相等——且对**任意**合法调用序列成立，不只这一条。
- **不证**：IR 里 `count = 1` 这个绑定，等于 EVM 的 `sstore(slot0, 1)` 字节布局。

**为什么这个精确版直接决定了 5.6 的三个 keystone**：等的是可观测投影 → 需要一个
**共享 `observe`/`ObservableTrace` 类型**（keystone 2）；是 `∀ input` → 需要 IR
解释器**可归纳（total）**（keystone 1）；是对目标的 Lean 模型 → 每个目标都得**有**
一份 Lean 语义（keystone 3，补 Solana 解释器）。

### 5.5 FV 就绪度：语义层三处不对称，缺一个统一语义契约

模块级正确性今天**没有**保证，靠测试 + golden + 对固定 fixture 的 pointwise
`native_decide`。要融入 FV 需要三个语义件 + 一个关系：

| 需要的东西 | 现状 | 阻塞 |
|---|---|---|
| IR 参考语义 | 有（`IR/Semantics.lean`，1279 行，三值 ExecResult），但 `partial def` | 归纳丢失 → 只能 pointwise（keystone） |
| 各目标语义 | EVM/NEAR 有；Solana 无；Psy/Sui 无 | 不对称、不完整 |
| IR↔目标 refinement | 仅固定场景 `native_decide`；三后端各复制一份 obligation | 无共享契约、无全称 |

三份 `ObservableReturn`/`TraceObligation` 是复制粘贴
（`Solana/Refinement.lean:38,52`、`WasmNear/Refinement/Core.lean:23,37`、
`Evm/Refinement.lean:30,61`），不是被强制的接口。目标形态是把它翻转成一个所有
后端都要 discharge 的**语义契约**：

```lean
-- 一个共享的、每个后端都要 discharge 的义务
class BackendSemantics (T : Type) where
  encode    : IR.Module → Except Err T.Artifact
  semantics : T.Artifact → Input → T.Trace     -- 可执行
  observe   : T.Trace → ObservableTrace         -- 共享 observable 类型
theorem refines : ∀ m input,
  observe (semantics (encode m) input) = IR.observe (IR.run m input)
```

（`refines` 里"相等"的精确含义见 **5.4**：可观测投影的、有向的、全称的、分片段的
refinement，且针对目标的 Lean 模型，而非两套语义的整体状态相等。）

**统一成一个契约的收益**：加一条链 = 履行一个**已知义务**（而不是发明一个 bespoke
`Refinement.lean`）；"支持片段"自然变成 `encode` 成功且 `refines` 成立的定义域；
Q1（5.1）的覆盖完备性从 Python 清单脚本升级成定理。

### 5.6 补充建议清单（keystone 优先）

1. **让 IR 解释器在已验证片段上 total（良基 `def`/fuel）** —— 解锁归纳与全称
   refinement 的总开关；不做这个，FV 永远停在 pointwise `native_decide`。
2. **合并三份 `ObservableReturn`/`TraceObligation` 为一个共享类型** —— 建立统一
   语义契约，消除复制。
3. **补 Solana 最小 sBPF 解释器**（见 5.2）。
4. **收敛三层拒绝**为每目标一个声明式"支持片段"谓词 + totality/soundness 定理；
   链专属 IR 节点给唯一能力或移出可移植 IR。
5. **（承接前文）**溢出模式下沉到 IR 节点级 + 能力派生改成 `intent ∪ module`。
6. **把 `native_decide` 尽量降级到 kernel 检查的 `decide`**，TCB 文档写明"信任
   Lean 编译器"。

**一句话总括**：架构方向没问题，但要"融入形式化验证"，真正的障碍是语义层的三处
不对称——IR 语义是 `partial`（不能归纳）、目标语义严重不均（Solana 为零）、
refinement 是逐后端复制的 pointwise 检查（没有统一契约）。先把 IR 解释器做 total、
把 refinement 义务统一成一个契约、再补 Solana 语义腿，FV 才有地基；否则加再多
`native_decide` 定理也只是给固定 fixture 背书。

---

## 六、附录：证据链索引（可复现）

| 主题 | 文件:行 |
|---|---|
| `+!`/`-!`/`*!`/`/!` 操作符定义 | `ProofForge/Contract/Source.lean:91-94` |
| `addValue`/`subValue`/… 定义（→ `.add` 等，不设 flag） | `ProofForge/Contract/Source.lean:81-88` |
| FV-5 gate 条件 | `ProofForge/Target/Adapter.lean:143` |
| 能力派生"二选一" | `ProofForge/Target/Adapter.lean:37` |
| `CapabilityPlan.capabilities` 从 calls 派生 | `ProofForge/Target/Plan.lean:33` |
| 唯一设 `overflowChecked := true` 处 | `ProofForge/Target/FV5Overflow.lean:36` |
| `Module.capabilities` 在 flag 为真时加 `.checkedArithmetic` | `ProofForge/IR/Contract.lean:509` |
| `overflowChecked` 默认 `false` | `ProofForge/IR/Contract.lean:320` |
| EVM `.add` → checked helper | `ProofForge/Backend/Evm/ToYul/Helpers.lean:19,48` |
| Solana `.add` → `.add64`（wrapping） | `ProofForge/Backend/Solana/SbpfAsm/Expr.lean:81` |
| NEAR `.add` → `i64.add`（wrapping） | `ProofForge/Backend/WasmHost/LoweringEnv.lean:40` |
| Solana obligation 裸子串匹配 | `ProofForge/Backend/Solana/Refinement.lean:119-123,171` |
| FV-1 全称结构定理（正面样例） | `ProofForge/Target/Formal.lean:13,26` |
| IR 解释器 `partial def` | `ProofForge/IR/Semantics.lean:420,561` |
| EVM bytecode 语义 stub | `ProofForge/Backend/Evm/EvmBytecodeSemantics.lean:95` |
| 跨链溢出分歧的官方说明 | `docs/capability-registry.md:81-105` |
| `crosscallInvokeNamedValue` 能力误映射为通用 `.crosscallInvoke` | `ProofForge/IR/Contract.lean:421` |
| EVM 靠硬编码 Validate 臂拒绝 NEAR 节点（非能力层） | `ProofForge/Backend/Evm/IR/Validate.lean:197` |
| Solana codegen "Phase 1 unsupported" 臂（能力 ⊋ 实际覆盖） | `ProofForge/Backend/Solana/SbpfAsm/Expr.lean:523`, `Stmt.lean:439` |
| Solana 有类型化指令 AST 但无指令语义 | `ProofForge/Backend/Solana/Asm.lean`（无 `step`/`exec`/`eval`） |
| 三后端各自复制 `ObservableReturn`/`TraceObligation` | `Evm/Refinement.lean:30,61`; `WasmNear/Refinement/Core.lean:23,37`; `Solana/Refinement.lean:38,52` |
| 覆盖清单是 Python 脚本（Solana 缺） | `scripts/{evm,near,psy}/check-ir-coverage-manifest.py` |
| `proof-forge deploy` 仅 EVM；其余链走 emit + 原生工具 | `ProofForge/Cli/Deploy.lean` |

**统计口径**（`grep --include="*.lean"`，HEAD `bbf1582a`）：
`native_decide` 130（ProofForge）+ 23（Tests）；`partial def` 576；真实 `sorry` 0
（另有 2 处仅出现在注释文本）；`unsafe` 18（全部在 CLI 的环境加载路径，属正当
元编程）；`@[extern]` 29。
