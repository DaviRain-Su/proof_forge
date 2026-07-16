# RFC 0004：EVM 语义计划与 Yul AST 边界

Status: **Accepted**

Date: 2026-07-02

Implemented: 2026-07-04 (CS-6.3 / D-046)

## 摘要

EVM portable IR 后端不应该长期从 ProofForge portable IR 直接降到低层
Yul 语法节点。ProofForge 现在已经有 `ProofForge.Compiler.Yul.AST`，portable
IR EVM 后端通过 `Yul.Printer` 渲染这个 AST。这个 AST 很有价值，但它是语法
AST：它描述 Yul object、block、statement、expression、function 和 literal。

缺少的是 portable IR 和这个语法 AST 之间的一层 target-semantic EVM
plan。

EVM target 的产品流水线应当是：

```text
contract_source / ContractSpec
  -> ProofForge portable IR
  -> EVM semantic plan
  -> Yul AST
  -> reproducible Yul source
  -> solc --strict-assembly
  -> runtime bytecode + ProofForge metadata
```

legacy `Lean.Compiler.LCNF` → `ProofForge.Compiler.LCNF.EmitYul` 路线、
`ProofForge.Evm` 和 `.evm-methods` sidecar 已在 CS-0.2 中从产品树移除，不再
可用于新工作。新的 EVM 示例、CI gate 和文档遵循上面的 portable-IR →
EVM-plan → Yul pipeline。

本 RFC 定义这层 EVM semantic plan 的边界和迁移路径。它保留现有 Yul AST
作为最终语法层，但不再让 ABI dispatch、storage layout、helper discovery、
event ABI、cross-call ABI 和 metadata 构造全部交织在同一个 lowering 过程里。

## 动机

当前 EVM portable IR 后端已经通过不断补能力，覆盖了 ABI entrypoint、标量和聚合表达式、storage slot、mapping、array、struct、event、cross-contract call、artifact metadata 和 diagnostic。这个进展也暴露了结构性问题：很多不同职责都挤在同一个 lowering 模块里：

- 类型检查与 unsupported-capability diagnostic。
- EVM storage layout 分配。
- ABI selector dispatch 和 calldata guard。
- Return-data encoding。
- Event signature 与 topic/data encoding。
- Helper function discovery 和 emission。
- Cross-contract call 的 calldata/returndata packing。
- Artifact metadata 和 deploy manifest 输入。
- 低层 Yul expression/statement 构造。

这样每补一个能力都会更难。Review 也会更难：一个 storage path 的改动，往往要同时检查 Yul 构造、helper emission、diagnostic、metadata 和 Foundry 覆盖。

本 RFC 的目标是在不丢掉现有 Yul AST 和 smoke suite 的前提下，让 EVM 后端更容易检查、更稳定。

## 当前状态

当前代码已经有真正的 Yul 语法 AST：

- `ProofForge.Compiler.Yul.AST`
- `ProofForge.Compiler.Yul.Printer`

portable IR EVM 后端当前暴露：

- `ProofForge.Backend.Evm.IR.lowerModule : Module -> Except LowerError Yul.Object`
- `ProofForge.Backend.Evm.IR.renderModule : Module -> Except LowerError String`

所以现在不是原始字符串拼接。问题是 semantic EVM lowering 和最终 Yul 语法构造发生在同一趟 pass 中。下一步架构改进，是把 semantic pass 显式化。

## 设计目标

- 在分阶段迁移时保持现有生成的 Yul、bytecode、metadata、diagnostic 和 smoke test。
- 让 ABI、storage、helper、event、cross-call 和 metadata 在最终 Yul 语法生成前成为一等计划产物。
- 保留现有 `Lean.Compiler.Yul.Object`，作为传给 `Yul.Printer` 的最终语法 AST。
- 让 unsupported capability 在 validation 或 semantic planning 阶段失败，而不是拖到语法渲染阶段。
- 让未来 optimizer、audit 和 metadata pass 能检查 EVM plan，而不用解析 Yul 文本或反向理解通用 Yul statement。
- 让这个设计保持 target-specific。它不是替代 portable IR 的新全局 IR。

## 非目标

- 本 RFC 不替换 `ProofForge.Compiler.Yul.AST`。
- 它不引入第二套 portable IR。
- 它不要求改变面向用户的合约语言。
- 它不要求一次性重写 `ProofForge.Backend.Evm.IR`。
- 它不定义 Solana、Wasm、Move 或 Psy 后端的 plan 结构；这些目标可以选择不同的 target-plan 层。

## 模块形态

EVM 后端应逐步拆成：

```text
ProofForge/Backend/Evm/
  IR.lean                 # 迁移期间的兼容 facade
  Plan.lean               # EVM semantic plan 数据结构
  Validate.lean           # EVM 专用 validation 和 diagnostics
  Lower.lean              # portable IR -> EVM plan
  ToYul.lean              # EVM plan -> Lean.Compiler.Yul.Object
  Metadata.lean           # plan -> artifact/deploy metadata 输入
```

当前 `IR.lean` 可以在迁移期间继续作为公共入口。最终
`IR.lowerModule` 应当变为：

```lean
def lowerModule (module : ProofForge.IR.Module) : Except LowerError Yul.Object := do
  let plan <- Lower.lowerModuleToPlan module
  ToYul.planToObject plan
```

`renderModule` 可以保持：

```lean
def renderModule (module : ProofForge.IR.Module) : Except LowerError String := do
  let object <- lowerModule module
  pure (Yul.Printer.render object)
```

## EVM plan 模型

plan 应该用 EVM 语义描述目标合约，而不是用通用 Yul 语法描述。草案如下：

```lean
namespace ProofForge.Backend.Evm.Plan

structure ModulePlan where
  name : String
  storage : StorageLayout
  entrypoints : Array EntrypointPlan
  helpers : HelperSet
  events : Array EventPlan
  crosscalls : Array CrosscallPlan
  capabilities : CapabilitySet
  metadata : MetadataPlan

structure EntrypointPlan where
  name : String
  selector : String
  params : Array AbiParamPlan
  returns : ReturnPlan
  calldataGuards : Array GuardPlan
  body : BlockPlan

structure StorageLayout where
  states : Array StorageStatePlan

inductive StorageSlotPlan where
  | scalarSlot (slot : Nat)
  | structFieldSlot (baseSlot : Nat) (fieldOffset : Nat)
  | arrayElementSlot (baseSlot length : Nat) (index : ValuePlan)
  | structArrayFieldSlot
      (baseSlot length fieldCount fieldOffset : Nat)
      (index : ValuePlan)
  | mapValueSlot (rootSlot : Nat) (keys : Array ValuePlan)
  | mapPresenceSlot (rootSlot : Nat) (keys : Array ValuePlan)

inductive StmtPlan where
  | letValue (name : String) (type : EvmWordType) (value : ValuePlan)
  | assignValue (target : AssignTargetPlan) (value : ValuePlan)
  | storageLoad (target : String) (slot : StorageSlotPlan)
  | storageStore (slot : StorageSlotPlan) (value : ValuePlan)
  | assert (condition : ValuePlan) (message : String)
  | ifElse (condition : ValuePlan) (thenBlock elseBlock : BlockPlan)
  | boundedFor (index : String) (start stop : Nat) (body : BlockPlan)
  | emitEvent (event : EventPlan) (args : Array ValuePlan)
  | returnValue (value : ReturnValuePlan)

end ProofForge.Backend.Evm.Plan
```

这个草案是语义化的。比如 `mapValueSlot` 表示“这是一个 EVM mapping slot path”，而不是“调用两次 `__proof_forge_map_slot`”。具体使用 helper 还是 inline Yul 形式，由 `ToYul` pass 决定。

## 计划边界

### Validation

Validation 负责：

- 类型一致性。
- target-specific supported/unsupported capability 检查。
- unsupported shape 的显式 diagnostic。
- ABI-facing 类型限制。
- Storage path 合法性。

validation pass 可以给 module 增加 type 信息，供 plan-lowering pass 使用。它不应该构造最终 Yul。

### Semantic lowering

`Lower` pass 负责：

- 分配 storage layout。
- 把 portable effect 转成 EVM plan statement。
- 解析 helper requirement。
- 构建带 selector、calldata guard 和 return plan 的 entrypoint plan。
- 构建 event 和 crosscall plan。
- 记录 capability id 和 metadata 输入。

输出应该无需渲染 Yul 就可以被检查。

### Yul generation

`ToYul` pass 负责：

- 把 plan statement 转成 `Lean.Compiler.Yul.Statement`。
- 根据 `HelperSet` 发射 helper function。
- 发射 dispatcher `switch`。
- 为 calldata、returndata、event、hash 和 call 生成 memory layout。
- 生成最终 `Lean.Compiler.Yul.Object`。

它不应该再做新的 target-support 决策。如果一个 plan node 到了 `ToYul`，就应当已经是合法的 EVM 计划。

### Metadata

metadata pass 应该消费 `ModulePlan`，而不是从渲染后的 Yul 里重新发现事实。这对这些字段尤其重要：

- `abi.entrypoints`
- `abi.events`
- capability list
- constructor metadata
- bytecode/Yul hash
- deploy manifest 字段

## 为什么比 portable IR 直接到 Yul AST 更好

现有低层 Yul AST 仍然必要，但它对后端架构来说太低层。semantic EVM plan 给 ProofForge 带来：

- 稳定的 EVM 语义 review 面。
- 在打印 Yul 之前测试 storage layout 和 ABI plan 的位置。
- artifact metadata 生成的干净输入。
- helper discovery 的干净位置。
- 未来 optimizer 可以理解 EVM 概念，而不是原始 Yul 语法。
- 更清晰的路径，用来比较旧 SDK/LCNF EVM 路径和 portable IR EVM 路径的等价性。

## 迁移计划

迁移应分阶段，并保持行为不变。

### Stage 1：引入 plan 数据结构

新增 `ProofForge.Backend.Evm.Plan`，先为最窄表面提供 semantic structure 和构造器：

- scalar value
- storage scalar read/write
- map value/presence slot
- entrypoint selector metadata
- helper requirement

这一阶段不应改变生成的 Yul。

### Stage 2：迁移 storage layout planning

把 slot assignment 和 storage-path planning 从 `IR.lean` 移到 `Plan`/`Lower`。第一个验收目标应该是 map 和 scalar storage，因为它们已经有强 golden Yul 和 Foundry 原始 slot 验证。

### Stage 3：迁移 entrypoint 和 ABI planning

用 plan 表达 dispatcher case、calldata guard、return encoder 和结构化 `abi.entrypoints` metadata。现有 ABI scalar 和 aggregate smoke 应保持字节级稳定，除非有明确的 printer 改动。

### Stage 4：迁移 helper discovery

用 plan 中的 `HelperSet` 替代分散的 helper accumulation。`ToYul` 应从这个集合确定性地发射 helper。

### Stage 5：迁移 events 和 crosscalls

在降到 Yul 前，用 plan node 表达 event signature、topic/data field layout 和 crosscall ABI packing。这是最复杂的表面，应在 storage 和 ABI entrypoint 证明模式可行后再迁移。

### Stage 6：增加 plan-level tests

添加直接检查 `ModulePlan` 的测试：

- storage slot formula
- selected helper
- entrypoint selector 和 ABI word count
- event signature 和 topic encoding
- unsupported diagnostic

Golden Yul 和 Foundry tests 仍然必须保留。plan tests 是额外证据，不是替代。

## 验收标准

一个迁移 slice 只有在满足以下条件时才算接受：

- 现有 golden Yul 仍然可复现，或者 diff 是有意且已 review 的。
- `solc --strict-assembly` 仍然接受生成的 Yul。
- 对应 Foundry smoke 仍然验证运行时行为。
- `proof-forge-artifact.json` metadata 仍然通过验证。
- unsupported node 仍然有显式 diagnostic。
- 对迁移的 capability，可以用 focused Lean test 或 smoke 检查 plan 数据。

## 开放问题

- plan tests 应该直接用 Lean structure equality，还是渲染稳定的 `.evm-plan.json` snapshot 方便 review？
- `HelperSet` 应该是带确定性顺序的 inductive set，还是从 plan traversal 计算出的 summary？
- storage layout 应该在全部 type validation 之前计算，还是只在 validation 得到 typed module 后计算？
- 现有 LCNF `EmitYul` 路径是否要共享同一层 semantic EVM plan？如果要，共享到什么程度？

## 初始实现建议

先从 storage planning 开始，不要先动 ABI 或 event。

第一个具体 slice：

1. 添加 `ProofForge.Backend.Evm.Plan`。
2. 建模 `StorageLayout`、`StorageSlotPlan` 和 `HelperSet`。
3. 把 scalar storage 和 map storage path 降到 plan node。
4. 把这些 plan node 转成现有 Yul AST，并保持生成的 Yul 不变。
5. 为 nested map value 和 presence slot 添加 focused plan test。
6. 保持 `just evm-smoke map`、`just evm-smoke typed-map`、`just evm-diagnostics` 和 `just evm-coverage` 作为验证门禁。

这是能证明新架构价值、同时不扰动既有 EVM 表面的最小 slice。
