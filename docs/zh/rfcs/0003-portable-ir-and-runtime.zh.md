# RFC 0003：可移植合约 IR、能力降级与运行时 profile

状态：草案

日期：2026-06-30

## 摘要

RFC 0001 将可移植合约 IR 定义为 Lean 源代码与目标后端之间的层。RFC 0002 列出了后端，但未对 IR、能力机制以及运行时选择问题做出规定。本 RFC 填补了这一空白。它定义了平台其余部分所依赖的三个事项：

1. 一个链中立的 Contract Intent API，其源码层操作由所选 target 在构建期解析。
2. 一个 capability 命名空间、capability plan 和逐目标降级表，target adapter 会查阅它们，把每个已路由的 capability 降级为具体宿主原语。
3. 每个目标的运行时 profile，说明 Lean 语言运行时如何与链宿主运行时协调，且编译器在降级前会进行静态检查。

本 RFC 明确的核心主张是：目标选择是一个构建时、表驱动且经过静态检查的决策。不存在针对链的运行时分派。合约要么解析 portable intent，并在目标的 capability 和运行时约束下干净地降级到该目标，要么在生成任何制品之前被拒绝并给出精确的诊断。

本 RFC 未定义完整的 IR 表面。IR 单元结构（模块、入口、状态、效应）在 [`portable-ir.md`](../portable-ir.zh.md) 中定义；规范的能力 id 和每目标支持矩阵在 [`capability-registry.md`](../capability-registry.zh.md) 中。本 RFC 仅定义了那些规范未涵盖的核心部分：能力降级规则格式、运行时 profile 和静态检查。除效应/能力表示之外的 IR 类型和语句细节推迟到 `portable-ir.md` 以及在了解 Solana 约束后的实现中。

## 动机

当前的 EVM 后端证明了 Lean 可以降级到链。它并未证明该设计具有通用性。目前有三件事阻碍了通用化：

- EVM 路径绕过了任何可移植层：`Lean → LCNF → EmitYul → Yul`。宿主调用 (`lean_evm_*`) 在 EmitYul 内部通过名称识别，并融合到 Yul 操作码中。不存在以抽象方式表示能力调用的 IR，因此没有可供第二个后端共享的内容。
- RFC 0001 和 RFC 0002 中将能力作为一个概念提及，但没有机制让编译器知道合约使用了哪些能力，或者拒绝无法满足这些能力的目标。
- Lean 语言运行时 (`lean_rt`) 与各条链的宿主运行时之间的关系从未说明。在实践中，EVM 后端将 Lean 运行时退化为无操作，并将 EVM 操作码视为运行时。Lean 分支中的 NEAR 参考保留了完整的 Lean 运行时并添加了宿主桥接。Move 后端根本无法携带 Lean 运行时。如果没有明确的模型，每个新后端都会临时重新推导这些决策。

本 RFC 修正共享层，使用户合约可以从同一个链中立 SDK 表面开始。后端在 intent routing、降级表和运行时 profile 上有所不同，而不是在心智模型上各自发明。

## 非目标

- 本 RFC 不指定 IR 单元结构（模块/入口/状态/效应）——那是 [`portable-ir.md`](../portable-ir.zh.md)。它仅指定后端和能力检查器所依赖的能力降级规则格式和运行时 profile。
- 它不定义规范的能力 id 集——那是 [`capability-registry.md`](../capability-registry.zh.md)。它使用这些 id。
- 它不会把 capability call 作为主要用户 SDK。capability id 是 target routing 产生的下层协议，由 target adapter 和 Target Extension SDK 使用。
- 它不选择 Solana 运行时策略。它定义了三种策略，以及 Solana spike 结果反馈到 IR 子集的约束。
- 它不定义云平台或制品注册表架构（RFC 0002 已经勾勒了元数据）。
- 它不要求立即将现有的 EVM 路径迁移到 IR。EVM 可以运行双路径（直接 LCNF 和通过 IR），直到黄金快照证明等效性。

## 与其他规范的关系

ProofForge 现在将共享层设计拆分到多个文档中。本 RFC 是运行时和降级的权威依据；其他文档则负责各自的领域。

| 领域 | 权威依据 | 本 RFC 的角色 |
|---|---|---|
| Contract Intent API 和 IR 单元结构 | [`portable-ir.md`](../portable-ir.zh.md) | 使用它；在 `Effect` 之上添加 target intent resolution 和 capability 降级规则 |
| 能力 id + 支持矩阵 | [`capability-registry.md`](../capability-registry.zh.md) | 使用 id；定义降级规则格式以及后端如何使用它们 |
| 跨目标场景 | [`shared-scenario.md`](../shared-scenario.zh.md) | 提供静态检查必须通过/拒绝的测试用例 |
| 已定决策 | [`decisions.md`](../decisions.zh.md) | 继承选定决策；见下文 |

继承自 [`decisions.md`](../decisions.zh.md) 且影响本 RFC 的决策：

- **D-001**：RFC 0001/0002 已被采纳为工程方向。本 RFC 是它们所依赖的缺失环节。
- **D-002**：第一阶段（目标注册表 + 可移植 IR + 制品元数据）必须在非 EVM spike 之前完成。此处定义的能力检查器和运行时 profile 是第一阶段的交付物。
- **D-003**：CosmWasm 和 Solana 的 spike 在第二阶段**并行**运行。这取代了早期的顺序路线图（仅限 Solana 的第二阶段，或 CosmWasm 先于 Solana）。两者验证不同的后端家族；互不限制。Solana 运行时决策（B vs B'）仍必须在 Solana 退出 spike 之前确定，但它不再阻塞 CosmWasm。
- **D-004/D-005/D-026**：`solana-sbpf-asm` 是规范 Solana direct assembly 路线。`solana-sbpf-linker` 和 Zig 分支保留为历史 fallback/reference 路线。
- **D-007/D-008**：Move POC 是 Aptos 优先的源代码生成（Strategy C）。本 RFC 的 Strategy C 和 Move 运行时 profile 遵循该方案。
- **D-027**：Solana CPI/PDA 留在 Solana 特定层，通过 capability 门控，而不是加入 portable IR。
- **D-028**：用户合约面向链中立的 Contract Intent API；所选 target 将 intent 解析为 capability plan。


## 两种运行时，三种协调策略

ProofForge 必须协调两个不同的运行时层：

- Lean 语言运行时 (`lean_rt`)：Lean 的对象模型 —— 装箱标量 `(n << 1) | 1`、构造函数头、引用计数、闭包、thunk、bignum。语言级机制，与链无关。
- 链宿主运行时：链自身的执行 ABI —— EVM 操作码、Solana 系统调用、Wasm 宿主导入、Move VM。

它们不能作为两个对等的运行时共存于一个目标上。每个目标选择三种协调策略之一。该策略是每个目标最重要的决策，因为它决定了 IR 允许包含的内容。

### Strategy A：退化运行时（宿主即运行时）

Lean 语言运行时被简化为无操作（no-ops）。引用计数变为 `lean_inc/dec/del → no-op`；`isShared` 始终返回 1；堆是每次调用的暂存内存。宿主调用不通过桥接二进制文件路由 —— 它们在降级时被内联到发射的代码中。

使用者：EVM。

对 IR 的影响：IR 可以使用任何无需堆即可降级的纯 Lean 结构（算术运算、作为内存区域的结构体、降级为生成的 `switch` 的闭包）。它不能依赖无界分配、GC 或跨调用的持久堆对象。

### Strategy B：完整 Lean 运行时加宿主桥接

完整的 Lean 语言运行时被编译到目标上，并与恰好一个宿主桥接模块链接，该模块将 Lean 对象转换为链的宿主 ABI 调用。

使用者：NEAR、CosmWasm 以及（如果能链接）Solana。

对 IR 的影响：IR 可以使用 `lean_rt` 支持的完整 Lean 子集，包括闭包和堆对象，但受限于目标的容量和预算限制。

### Strategy C：无 Lean 运行时（源代码生成）

不交付 Lean 运行时。后端生成目标语言的源代码，目标自身的 VM 即为运行时。Lean 仅用于类型和证明，它们在代码生成前被检查并擦除。

使用者：Sui Move、Aptos Move。

对 IR 的影响：IR 必须是一个受限的、一阶的、与 Move 兼容的子集。没有闭包，没有 Lean 堆对象，没有任意递归。资源、对象和 ability 语义必须在 IR 中显式表示。### 变体 B'：受限 Lean 运行时

B 的子策略，用于当完整的 Lean 运行时无法适配某个目标（Solana sBPF 是预期情况）时。`lean_rt` 的一个子集被编译——包括装箱标量和显式构造函数，但闭包、大数（bignum）和 IR 解释器可能会被舍弃。宿主桥接保持不变。

对 IR 的影响：如果一个目标使用 B'，则 IR 不得使用被舍弃的特性，且静态检查必须在降级之前拒绝它们。Solana spike（工作流 7）决定 Solana 是使用 B、B'，还是回退到类似 A 的路径。

## 能力模型

### Intent resolution 和 capability plan

可移植 IR 不包含目标操作码。默认面向用户的 SDK 也不直接暴露 capability call。源码表达 contract intent，例如状态声明、入口、事件、caller 读取、value 访问、断言和证明义务。所选 target adapter 会在降级前把这些 intent 解析为 capability plan。

Capability call 是 routing 之后的下层表示。它们记录所选 target 必须支持的语义操作，并提供稳定的诊断/制品表面。Target Extension SDK 可以暴露目标特定操作，但这些操作仍通过 capability call 和 target metadata 路由。

概念表示（Lean 草图；具体的 IR 数据结构是实现细节，但它必须携带此信息）：

```lean
/-- A capability identifier in a hierarchical namespace, e.g. `storage.scalar`. -/
structure CapId where
  parts : List String

/-- A source-level portable operation before target routing. -/
structure ContractIntent where
  kind   : IntentKind
  args   : Array IRExpr
  source : SourceSpan

/-- A capability call recorded after target routing. The `capability` field lets
    the backend lower it from the table rather than by name matching. -/
structure CapabilityCall where
  capability : CapId
  operation  : Name        -- e.g. ``Storage.load``, ``Solana.Cpi.invokeSigned``
  args       : Array IRExpr

/-- Target-selected plan consumed by the checker and backend. -/
structure CapabilityPlan where
  calls          : Array CapabilityCall
  targetMetadata : TargetMetadata
```

target adapter 提供 routing 步骤：

```lean
structure TargetAdapter where
  targetId      : TargetId
  profile       : TargetProfile
  resolveIntent : ContractSpec -> Except Diagnostic CapabilityPlan
  lower         : CapabilityPlan -> IR.Module -> Except Diagnostic TargetAst
```

`@[capability "..."]` 这类 Lean attribute 仍可作为 opaque target-extension 函数的实现 hook。它不是默认产品 API。后端不再对 `lean_evm_*` 名称进行模式匹配；它们读取已解析的 capability plan。

### 能力命名空间

能力 id 的规范集合及其逐目标支持矩阵位于 [`capability-registry.md`](../capability-registry.zh.md)，这是 id 的唯一事实来源。RFC 0003 不会重新定义它们；它消费它们。

作为参考，注册表的第一个版本包括：`storage.scalar`、`storage.map`、`storage.pda`、`caller.sender`、`value.native`、`events.emit`、`crosscall.invoke`、`crosscall.cpi`、`env.block`、`crypto.hash` 和 `account.explicit`。每个 id 都是一个语义能力 (`<domain>.<operation>`)，而不是目标操作码。新 id 通过规范修订添加到注册表中，而不是由每个后端自行添加；后端提议 id，注册表拥有它们。

本 RFC 仅在注册表之上添加了两项内容：

1. **降级规则格式**（下一小节）——后端如何为已注册的 id 发射宿主原语。注册表说明了目标支持*哪些* id；本 RFC 说明了受支持的 id *如何*降级为宿主代码。
2. **运行时 profile**（后续章节）——约束目标下可能出现*哪些 IR 特性*，与能力 id 无关。

### 能力降级表

每个目标提供一个表格，将它支持的每个能力 id 映射到一个降级规则。该规则说明了后端如何为该能力发射宿主原语，以及降级是否需要额外的目标元数据（例如 Solana 账户清单、Move ability 注解）。

```lean
/-- How a target lowers one capability. -/
structure CapabilityLowering where
  capability : CapId
  -- A tag telling the backend which emitter to use for this capability.
  lowering   : LoweringKind
  -- Whether the lowering needs per-call target metadata from a manifest.
  needsMetadata : Bool

inductive LoweringKind where
  | evmOpcode   (op : String)              -- e.g. sload, sstore, caller
  | hostImport  (bridgeFn : Name)          -- e.g. `Lean.Near.storage_read`
  | syscall     (bridgeFn : Name)          -- e.g. `Lean.Solana.read_data`
  | generated   (targetApi : Name)         -- e.g. Move `sui::event::emit`
```

示例：

| 目标 | 能力 | 降级 |
|---|---|---|
| evm | `storage.scalar` | `evmOpcode "sload"` / `"sstore"` |
| evm | `caller.sender` | `evmOpcode "caller"` |
| wasm-near | `storage.scalar` | `hostImport ``Lean.Near.storage_read`` |
| wasm-cosmwasm | `storage.scalar` | `hostImport ``Lean.CosmWasm.storage_read`` |
| solana-sbpf-asm | `storage.scalar` | `syscall ``Lean.Solana.read_data`` (需要账户清单) |
| solana-sbpf-asm | `storage.pda` | `syscall PDA 派生 (需要账户清单) |
| solana-sbpf-asm | `crosscall.cpi` | `带有 account metas 的 syscall CPI |
| move-sui | `events.emit` | `generated ``sui::event::emit`` |
| move-aptos | `storage.scalar` | `generated resource access (needs abilities + acquires)`` |

目标支持的能力集合正是其表格中的行集合。如果某个能力在目标表格中没有对应的行，则该目标不支持该能力。

### 静态能力检查

在降级之前，编译器要求所选 target 把 contract intent 解析为 capability plan。然后计算该 plan 使用的 capability id 集合（加上 IR 中任何显式 target-extension call），并根据目标支持集合进行检查。这是一个集合操作；它要么成功，要么产生精确的诊断。

```
usedCapabilities(contract) ⊆ supportedCapabilities(target)
```

失败时，编译器会针对每个不支持的能力发射一条诊断信息：

```
error: target `solana-sbpf-asm` does not support capability `value.native`
  hint: Solana has no EVM-style msg.value; model native assets as explicit
        lamport/Coin accounts via the `account.explicit` capability
  used at: Examples/Counter.lean:42
```

此项检查使得“拒绝不支持的目标，而非静默地改变语义”成为真实的编译器行为，而不仅仅是文档中的承诺。它替换了 EmitYul 内部当前的名称匹配。

### 特性使用跟踪，而不仅仅是能力跟踪

同一个静态 pass 还会根据运行时 profile（见下文）跟踪 IR 特性的使用情况：闭包计数、递归深度、堆对象分配、大数使用。针对 B' 运行时的使用闭包的合约也会以同样的方式被拒绝：

```
error: target `solana-sbpf-asm` runtime profile `restrictedLean` does not support closures
  used at: Examples/Counter.lean:55 (`fun x => ...`)
  hint: rewrite as a first-order function or inline the body
```

## 运行时 profile

每个目标都声明一个运行时 profile。该 profile 规定了 Lean 运行时在该目标上的协调策略和功能预算。编译器会静态地根据该预算检查合约的功能使用情况。

```lean
inductive RuntimeMode where
  | degenerate       -- Strategy A: Lean runtime is no-ops; host is the runtime
  | fullLean         -- Strategy B: full lean_rt + host bridge
  | restrictedLean   -- Strategy B': subset of lean_rt
  | none             -- Strategy C: source generation; no lean_rt

inductive HostBridgeKind where
  | inlineOpcodes    -- EVM: no bridge binary; opcodes emitted inline
  | module (id : String)   -- "near" | "cosmwasm" | "solana"
  | none             -- source generation targets

inductive ChainAllocator where
  | bump             -- final chain artifact 中的线性 frontier
  | bumpReset        -- bump + 每个入口边界重置
  | nearWeeModel     -- NEAR 部署 profile；Rust SDK 使用 wee_alloc
  | minimalMalloc    -- direct-WAT 内部 free-list allocator
  | cosmWasmRegion   -- CosmWasm allocate/deallocate region ABI

inductive ExperimentAllocator where
  | hostBump
  | hostJemallocShape
  | hostMimallocShape

structure RuntimeProfile where
  mode              : RuntimeMode
  hostBridge        : HostBridgeKind
  deploymentAllocator? : Option ChainAllocator
  offlineAllocators : Array ExperimentAllocator
  supportsClosures  : Bool
  supportsBignum    : Bool
  supportsHeapObjects : Bool
  maxStackBytes     : Nat          -- EVM effectively unbounded; Solana 4096
  maxArtifactBytes  : Nat          -- target upload limit, if any
```

初始 profile：

| 目标 | 模式 | 宿主桥接 | 支持闭包 | 支持大数 | 支持堆对象 |
|---|---|---|---|---|---|
| evm | 退化 | 内联 opcode | 否（降级为 switch） | 否（U256 封顶） | 否（每次调用暂存） |
| wasm-near | fullLean | 模块 "near" | 是 | 是 | 是 |
| wasm-cosmwasm | fullLean | 模块 "cosmwasm" | 是 | 是 | 是 |
| solana-sbpf-asm | 受限运行时（暂定） | 模块 "solana" | 由 spike 待定 | 待定 | 待定 |
| move-sui | 无 | 无 | 否 | 否（固定宽度） | 否（资源） |
| move-aptos | 无 | 无 | 否 | 否（固定宽度） | 否（资源） |

Solana 行是刻意暂定的。其 `restrictedLean` 模式及其特性布尔值并非假设——它们是工作流 7 的输出。在该 spike 落地之前，Solana profile 记录的是开放性问题，而非答案。

## 构建流

端到端的面向目标的构建：

1. 解析 `--target <id>`；解析目标 profile 及其运行时 profile。
2. 将 Lean 源代码编译为 LCNF 并构建链中立的 `ContractSpec`，同时记录特性使用情况（闭包、递归、分配）。
3. 要求所选 target adapter 把 contract intent 解析为 `CapabilityPlan`，然后构建可移植 IR：入口、类型、状态转移以及标记有其 `CapId` 的 target-resolved capability call。证明在步骤 2 中进行验证并擦除；IR 携带的是证明状态元数据，而非证明项。
4. **静态检查（集合运算，构建时，不可协商）：**
   - `usedCapabilities ⊆ supportedCapabilities(target)`，否则拒绝。
   - `usedFeatures ⊆ runtimeProfile.features`，否则拒绝。
5. 降级：对于每个 routed capability call，查找目标的降级规则并发射宿主原语（操作码 / 桥接调用 / 系统调用 / 生成的 API）。
6. 根据 `mode` 构建运行时：
   - 退化 → 仅发射无操作 RC 存根和内联的宿主操作码。
   - fullLean / 受限运行时 → 编译相应的 `lean_rt` 子集并链接恰好一个 `host/<bridge>` 模块。
   - 无 → 跳过运行时构建；发射目标源代码。
7. 根据目标的制品种类进行打包并运行其冒烟测试门禁。

步骤 4 和 6 是决定“编译后的代码知道调用哪个运行时”的地方。这是在构建时通过表查找和链接选择决定的，绝非在运行时决定。

## 宿主桥接选择是链接时且排他的

对于策略 B 和 B' 目标，链接恰好一个宿主桥接模块。不存在运行时选择，也没有符号冲突：每个桥接都实现了一组不同的 extern（`lean_near_*`、`lean_cosmwasm_*`、`lean_solana_*`）。构建过程从运行时 profile 的 `hostBridge` 字段中选择桥接。

这相对于现状所需的清理：Lean 分支在 EmitZig 的通用运行时 extern 列表中硬编码了 `lean_near_*`，因此每个 Wasm 构建都会强制链接 NEAR 桥接。工作流 4 使桥接选择变为目标驱动：EmitZig 为运行时 profile 命名的桥接发射 extern，而通用 Wasm 运行时不强制链接任何特定于链的内容。正是这一工程变更将“NEAR 可用”转变为“Wasm 家族可用”。

## Solana 约束反馈到 IR

Solana sBPF spike（工作流 6/7）并非 IR 的下游；它约束了 IR。该 spike 将回答完整的 `lean_rt` 是否能在 4KB 栈和加载器段约束下于 `bpfel-freestanding` 中链接。其结果以及各自对 IR 的强制要求如下：

- **完整运行时可链接（策略 B 成立）：** IR 可以为 Solana 保留闭包和堆对象。Solana profile 布尔值变为 true。
- **仅子集可链接（策略 B'）：** IR 必须支持一个在 Solana 下降级的一阶、无闭包、有界递归子集。静态检查器将拒绝超出该范围的 Solana 构建。该子集很可能与 Move 兼容子集重叠，这在战略上非常有用。
- **无可行运行时子集（回退至策略 A）：** IR 必须在 Solana 上直接降级为 Zig 而不使用 `lean_rt`，就像 EmitYul 在 EVM 上直接降级为 Yul 而不使用 `lean_rt` 一样。Solana 变成一个退化运行时目标，其“宿主即运行时”通过系统调用实现。由于结果尚不确定，IR 设计必须从一开始就保持 B' 兼容子集的整洁：一阶函数、显式入口、装箱标量、显式构造函数。仅在 Strategy B 下才能存续的特性（无界闭包、任意递归、完整大数）必须按目标选择性开启，而非默认假设。

## 与现有 EVM 后端的关系

EVM 后端仍作为工作基准。它不会在第一天就通过 IR 进行重写。迁移是分阶段进行的：

1. 为 `evm` 添加目标 profile、运行时 profile 和能力降级表，该表派生自 EmitYul 已有的功能。
2. 添加能力和特性的静态检查，作为在 EmitYul 之前运行的一个 pass。最初它仅根据 EVM profile 验证 EVM 合约。
3. 引入可移植 IR 作为降级到相同 Yul 的替代路径。保留直接的 LCNF→EmitYul 路径，直到 Yul 黄金快照证明这两条路径对每个示例都发射相同的输出。
4. 一旦等效性成立，即可移除直接路径。

现有的 `@[extern "lean_evm_*"]` 名称成为 `evmOpcode` 行的降级规则目标；EmitYul 的内部名称匹配被表查找取代。除非快照差异另有说明，否则 EVM 行为不会改变。

## 验收标准

本 RFC 在满足以下条件时即视为实现：

- 存在一个用于 `evm` 的目标 profile，描述了家族、制品种类、能力集和运行时 profile，且不改变当前的 EVM 输出。
- 如果合约使用了目标表中缺失的能力，则会被拒绝，并提供包含目标 id、能力 id 和源代码位置的诊断。
- 如果合约使用了目标的运行时 profile 禁用的特性，则会被拒绝，并提供包含该特性和源代码位置的诊断。
- 在添加能力和特性检查前后，EVM 构建产生相同的 Yul/字节码（黄金快照等效性）。
- 即使后端尚未实现，注册表中也至少记录了一个非 EVM 目标的运行时 profile，以便注册表成为能力和运行时约束的唯一事实来源。

## 待解决问题

- 能力 id 是否应该携带描述其触及状态*类型*的负载（例如 `storage.scalar` vs `storage.map` vs `account.explicit`），还是 `capability-registry.md` 中当前的扁平命名空间已足以进行精确诊断？
- Contract Intent API 操作如何在源码层识别；target-extension 函数什么时候需要显式 `@[capability "..."]` 实现 hook，而不是走 target intent routing？
- 静态特性检查应该是保守的（拒绝任何可能使用闭包的内容）还是精确的（仅拒绝确认的闭包）？对于初版来说，保守做法更安全。
- 对于 Move 源代码生成，资源 abilities 和 `acquires` 子句存放在哪里——在 IR 中、在目标清单中，还是从能力使用中派生？RFC 0002 的 Move 说明倾向于 IR；本 RFC 暂缓讨论。
- 可移植 IR 应该是被 Lean 实现的后端所使用的 Lean 数据结构，还是可以被外部（Zig/Rust）后端使用的序列化格式？答案将影响后端是否可以按照 RFC 0001 的待解决问题采用非 Lean 实现。

## 研究参考

- EVM 基准和退化运行时方法：`ProofForge.Evm`，`ProofForge.Compiler.LCNF.EmitYul`。EmitYul 中对 `lean_evm_*` 的识别是能力降级表的先驱。
- NEAR 全运行时加桥接参考：本地 Lean 分叉 `Lean.Near`，`tools/zigc-near`，`src/runtime/zig/host/near`。
- Solana 运行时决策（Strategy B vs B' vs 回退到 Strategy A）：`docs/implementation-backlog.md`，`docs/targets/solana-sbf.md` 中的工作流 6/7。
- Move 源代码生成限制（Strategy C IR 子集）：`docs/targets/move-family.md`。
- 能力矩阵和目标 profile：RFC 0002。
- IR 单元结构（Module/Entrypoint/State/Effect）：`docs/portable-ir.md`。
- 规范能力 id 和支持矩阵：`docs/capability-registry.md`。
- 已定决策，包括 D-027 和 D-028：`docs/decisions.md`。
- 跨目标 Counter 场景：`docs/shared-scenario.md`。
