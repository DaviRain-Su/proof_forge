# Canonical Core IR 与 Target Plan 解耦设计

## 状态

架构边界已确认，尚未完成实现。

本文替换此前的 API spike 设计。现有 spike 证明了“可以在仓库中接入
Lean 定义的中间层”，但其中公开的 `*-core` target、物理 slot、
无类型的 `HostOpId := String`、与生产 plan 并行的 AST-bearing plan，
以及只检查字符串或非空数组的 smoke，都不属于本设计，也不能作为完成证据。

本次确认同时覆盖两个选项：

1. **可移植语法解耦：** 新 SDK 语法和高层集合先归一化为稳定的
   Canonical Core，不再逐个修改后端。
2. **类型化 HostOp：** 真正属于目标平台的语义通过带命名空间、版本、
   类型、effect class 和 capability 的扩展契约接入。

实施顺序是先完成第一条的 Core 基础和三后端迁移，再开放 Queue/Set。
第二条现在完整设计，并在 Core 基础之后实现一个真实的端到端 HostOp
垂直切片。

## 决策摘要

ProofForge 使用 Lean 来定义类型化编译 pass、验证器、可执行语义和
refinement 命题。真正实现解耦的不是“用了 Lean”，而是只有一个稳定的
语义边界，并复用仓库现有的 target-semantic plan。

```text
contract_source / SDK intents
              |
              v
ProofForge.Frontend.Surface
  独立语法 AST、Queue、Set、业务级操作
              |
              v
normalize + typecheck
              |
              v
CanonicalBundle
  + CheckedCanonicalContract
      - typed ANF/CFG Core.Module
      - logical StateId + StateShape
      - interface + materialization contract
      - capability requirements
  + CanonicalEvidence
      - source map、证明标注、迁移证据
              |
              v
CapabilityPlan + typed/versioned HostOp catalog
              |
              v
现有 Evm.Plan | Solana.Plan | NearModulePlan
              |
              v
Yul AST | sBPF AST | Wasm AST
              |
              v
printer + 外部工具链 + runtime parity gates
```

迁移期间，当前 `ProofForge.IR.Contract` 被冻结并视为 **Legacy IR**。
现有 `contract_source` 通过 fail-closed Legacy adapter 进入新流水线。
任何新 Surface 语法都不能再给 Legacy IR 增加 constructor。

## 对当前实现的定性

`ProofForge.Contract.Surface` 目前只是
`ProofForge.IR.Contract` 的 builder facade，并不是本文所说的独立
Surface AST。生产后端直接消费 `IR.Contract`，其 `Expr`、`Effect`
和 `Statement` 又都是封闭 inductive，因此这两层都不能再被称作可扩展
边界。

当前 Core spike 同样不是 canonical：

- storage path 使用物理数字，而不是逻辑 state identity；
- effectful read 仍可能嵌在 expression tree 中；
- state shape 和 metadata 可能在 elaboration 中丢失；
- unsupported 语义可能被降成空函数或占位指令；
- 三套新 CorePlan 与已有 target plan 重复；
- public target profile 暴露了不完整编译路径。

实施的第一步是把这些限制变成显式、可测试、fail-closed 的错误。

## 问题分类

需要区分三类变化：

1. **语法扩散：** Queue、Set、DSL sugar 和 authoring helper，归
   Surface normalization 管。
2. **可移植语义增长：** 新的链中立 primitive，需要显式 Core 版本变更，
   并修改所有适用 target plan。
3. **目标平台专属语义：** PDA、NEAR Promise、EVM CREATE2 等，通过
   typed HostOp 和目标自有 handler 接入。

target layout drift 是第四类问题，仓库现有 EVM、Solana、NEAR plan 已经
部分解决。本设计扩展这些 plan，不重新造一套。

## 目标

1. 只要新语法可以由既有 Core primitives 表达，改动只发生在 Surface
   和 normalization。
2. Core 保留 state identity、state shape、类型、effect 顺序、控制流、
   loop bound、算术模式、错误、返回值、事件和 entrypoint 语义。
3. 每个 Legacy IR constructor 和字段都必须归类为
   `preserve`、`normalize`、`materialization`、`evidence`
   或 `reject`。
4. target lowering 只接受 checked canonical contract 和已解析的
   `CapabilityPlan`；不支持行为必须在产物发布前失败。
5. EVM、Solana、NEAR 复用已有 plan type，不维护平行的 CorePlan 架构。
6. 目标专属能力使用带版本和类型的 HostOp，由目标 handler 和语义 hook
   负责。
7. public CLI 仍只宣传 `evm`、`solana-sbpf-asm`、`wasm-near`。
8. Counter 和 ValueVault 是最小 semantic/runtime parity gate；public
   cutover 还必须覆盖完整现有 product matrix 和所有已宣传主目标片段。

## 非目标

- 重新实现一台统一的 EVM/sBPF/Wasm VM。
- 把 Queue、Set、Map 加进 Yul、sBPF 或 Wasm AST。
- 声称新可移植语义永远不需要修改目标后端。
- 运行时动态加载不受信任的 Lean plugin。
- 用证明替代 solc、assembler、wat2wasm 和 runtime tests。
- 为内部 pipeline variant 新增公开 blockchain target ID。
- 在本计划中迁移非主三链 research target。
- 第一阶段就完成所有 target-code constructor 的完整 refinement。

## 强制不变量

| 不变量 | 必须产生的结果 |
|---|---|
| 只有一个 canonical semantic IR | backend 不消费 Surface，也不增加第二套 Core AST。 |
| Legacy IR 冻结 | Queue/Set 和未来语法不得修改 `IR.Contract` constructor 或字段。 |
| Core storage 是逻辑模型 | Core path 从 `StateId` 开始；slot、account offset、KV prefix 只在 target plan 中出现。 |
| effect 显式产出结果 | storage/context/crosscall/host read 都是有顺序且带 result ID 的 instruction。 |
| loop intent 不丢失 | CFG 回边携带已验证 bound，或明确声明需要 unbounded-loop capability。 |
| plan 是 target-semantic | 现有 plan 可有语义操作，但不能包含 `Yul.Statement`、`Asm.AstNode`、`Wasm.Insn`。 |
| 所有 pass fail closed | normalize、validate、capability、plan、lower、render、artifact validate 均能返回错误。 |
| HostOp 类型化 | 未知 ID/版本、arity/type/effect/capability/handler 都是编译错误。 |
| Evidence 不影响语义 | 删除 `CanonicalEvidence` 不能改变 capability、目标代码和 observable behavior。 |
| public target 表示平台 | pipeline variant 不进入 `Target.knownIds` 或 `--list-targets`。 |
| 迁移不破坏 product path | canonical parity 通过前，原主路径继续权威。 |
| skeleton 不是成功 | 空 body、占位指令、缺失 return、未验证 artifact 都不能通过 gate。 |

## 分层职责

### 1. 独立 Surface AST

`contract_source` 和 SDK helper 继续作为公开 authoring interface。新建
`ProofForge.Frontend.Surface`，独立拥有 source type、expression、
lvalue、statement、declaration、entrypoint、source span 和 hygienic
generated symbol。该命名与历史
`ProofForge.Contract.Surface` builder facade 明确区分。

Surface 不 import Legacy IR、target plan 或 target AST。集合相关 schema
如下，完整实现还包含普通表达式、控制流、事件和错误节点：

```lean
namespace ProofForge.Frontend.Surface

structure SurfaceStateId where
  value : String

inductive StateDecl
  | scalar (id : SurfaceStateId) (type : SurfaceType)
  | map (id : SurfaceStateId) (key value : SurfaceType)
      (capacity : Option Nat)
  | fixedArray (id : SurfaceStateId) (element : SurfaceType)
      (length : Nat)
  | dynamicArray (id : SurfaceStateId) (element : SurfaceType)
  | queue (id : SurfaceStateId) (element : SurfaceType)
      (capacity : Nat)
  | set (id : SurfaceStateId) (element : SurfaceType)
      (capacity : Nat)

inductive Statement
  | bind (local : SurfaceLocalId) (type : SurfaceType) (value : Expr)
  | store (target : LValue) (value : Expr)
  | queueEnqueue (queueId : SurfaceStateId) (value : Expr)
  | queueDequeue (queueId : SurfaceStateId) (result : SurfaceLocalId)
  | setInsert (setId : SurfaceStateId) (value : Expr)
  | setRemove (setId : SurfaceStateId) (value : Expr)
  | branch (condition : Expr)
      (onTrue onFalse : Array Statement)
  | boundedLoop (index : SurfaceLocalId) (bound : Nat)
      (body : Array Statement)
  | return (value : Option Expr)

structure Module where
  name : String
  structs : Array StructDecl := #[]
  state : Array StateDecl := #[]
  entrypoints : Array Entrypoint := #[]
  events : Array EventDecl := #[]

end ProofForge.Frontend.Surface
```

相同 Surface schema version 的 normalization 必须确定性输出相同 canonical
hash。生成名只能使用一个保留 namespace，并在冲突时失败。

### 2. 迁移期 source compatibility

现有 `contract_source-v1` 继续导出
`ProofForge.Contract.ContractSpec`，通过 `adaptLegacy` 进入 canonical。
集合 slice 落地后，source elaborator 可以导出
`ProofForge.Frontend.Surface.Contract`。 `ContractLoader` 同时识别这
两种源类型，并统一产生 `CanonicalBundle`。

公开 source syntax 和 target ID 不变；模块开始导出独立 Surface 类型时，
machine-readable source DSL version 必须升级。禁止 Surface-to-Legacy
回译。旧 library consumer 继续支持 v1 source，新 Surface 功能必须使用
canonical compiler API。

### 3. 冻结的 Legacy adapter

`ProofForge.IR.Contract` 只作为 compatibility input。adapter 必须消费
完整 `ContractSpec`，不能只取 `spec.module`：

```lean
def adaptLegacy
    (spec : ProofForge.Contract.ContractSpec) :
    Except CanonicalizeError CanonicalBundle
```

CI 检查完整 constructor/field inventory。每个 case 只能属于以下一类：

- **preserve：** 一对一保存 Core runtime semantics；
- **normalize：** 展开成多条 Core instruction 或多个 CFG block；
- **materialization：** 因为会影响 capability 或 artifact，保存在 checked
  interface/materialization contract；
- **evidence：** 只用于 diagnostic、proof、migration tracking；
- **reject：** 返回包含 constructor 和 source location 的错误。

禁止 wildcard fallback、slot 0 fallback、默认零值、空 body、默认类型、
静默忽略 metadata，以及 unsupported-to-nop。

## Canonical Core

Core 是 typed ANF + explicit CFG，不是第二套 source AST。

### Identity 和类型

```lean
structure TypeId where value : Nat
structure StateId where value : Nat
structure FunctionId where value : Nat
structure EventId where value : Nat
structure BlockId where value : Nat
structure ValueId where value : Nat

structure ValueDef where
  id : ValueId
  type : CoreType

structure ValueRef where
  id : ValueId
  type : CoreType

inductive OverflowMode
  | wrapping
  | checked

inductive StateShape
  | scalar (value : CoreType)
  | map (key value : CoreType) (capacity : Option Nat)
  | fixedArray (element : CoreType) (length : Nat)
  | dynamicArray (element : CoreType)
  | record (type : TypeId)
```

canonical 引用使用 resolved numeric identity，不使用用户字符串。显示名放在
symbol table/source map。`StateId` 是逻辑 identity；EVM slot、Solana
account offset、NEAR storage prefix 都由 target plan 在 capability
resolution 之后分配。

### 逻辑 StoragePath

```lean
inductive StorageSegment
  | mapKey (key : ValueRef)
  | index (index : ValueRef)
  | field (field : FieldId)

structure StorageRef where
  root : StateId
  path : Array StorageSegment := #[]
  resultType : CoreType
```

validator 必须沿声明的 `StateShape` 检查完整 path。未知 root、错误 key/
index type、错误 field、错误 result type 和 shape mismatch 都失败。
Core 类型系统中不能表示 target physical layout。

### ANF instruction

```lean
inductive PureOp
  | literal (value : CoreLiteral)
  | unary (op : UnaryOp) (arg : ValueRef)
  | arithmetic (op : ArithmeticOp) (mode : OverflowMode)
      (lhs rhs : ValueRef)
  | compare (op : CompareOp) (lhs rhs : ValueRef)
  | cast (to : CoreType) (arg : ValueRef)
  | hash (arg : ValueRef)

inductive InstructionOp
  | pure (op : PureOp)
  | storageLoad (path : StorageRef)
  | storageContains (path : StorageRef)
  | storageStore (path : StorageRef) (value : ValueRef)
  | storageLength (root : StateId)
  | storageResize (root : StateId) (length : ValueRef)
  | memoryAlloc (type : CoreType) (length : ValueRef)
  | memoryLoad (base index : ValueRef)
  | memoryStore (base index value : ValueRef)
  | memoryRelease (base : ValueRef)
  | contextRead (field : ContextField)
  | emit (event : EventId) (args : Array ValueRef)
  | assert (condition : ValueRef) (error : CoreErrorRef)
  | crosscall (spec : CoreCrosscallSpec) (args : Array ValueRef)
  | hostCall (call : HostOpCall)

structure Instruction where
  results : Array ValueDef
  op : InstructionOp
```

所有 value-producing effect 必须绑定显式 result ID。instruction 顺序就是
effect 顺序。nested expression 不能包含 storage/memory/context/crosscall/
host effect。portable crosscall 和 memory 属于固定 Core semantics；平台
专属调用形式仍使用 typed HostOp。

### CFG 和 loop bound

```lean
inductive LoopBound
  | atMost (iterations : Nat)
  | requiresUnbounded

inductive Terminator
  | jump (target : BlockId) (args : Array ValueRef)
      (backedgeBound : Option LoopBound := none)
  | branch (condition : ValueRef)
      (onTrue onFalse : BlockId)
  | return (values : Array ValueRef)
  | revert (error : CoreErrorRef)

structure Block where
  id : BlockId
  params : Array ValueDef := #[]
  instructions : Array Instruction
  terminator : Terminator
```

block parameter 承载 merge value，每个 block 只有一个 terminator。任何
cycle 都必须有已验证 `LoopBound`。不支持 unbounded loop 的目标必须在
capability 阶段拒绝 `requiresUnbounded`。禁止 implicit fallthrough 和
missing return。

### 算术和错误语义

checked/wrapping 模式附着在每条 arithmetic instruction 上。除零、
narrowing cast、shift、assertion failure、structured error、revert 都只有
一份 Core 定义。module default 可以指导 normalization，但不能成为会被
丢弃的隐含语义。

address、hash、crosscall 的结果类型和错误行为同样在 Core 中规范化。
目标无法实现时必须在 capability 或 plan 阶段失败。

### Canonical contract、materialization 与 evidence

`Core.Module` 只包含 portable runtime semantics。interface、deployment、
ABI、upgrade、allocator、capability 数据会影响 artifact，必须属于 checked
canonical contract：

```lean
structure CanonicalContract where
  schemaVersion : Nat
  module : Core.Module
  interface : InterfaceContract
  materialization : MaterializationContract
  requirements : Array ProofForge.Target.CapabilityCall

structure CanonicalEvidence where
  sourceMap : SourceMap
  verification : VerificationAnnotations
  legacyClassification : Array LegacyClassificationEvidence

structure CanonicalBundle where
  contract : CheckedCanonicalContract
  evidence : CanonicalEvidence
```

`InterfaceContract` 和 `MaterializationContract` 保存 entrypoint kind/
mutability、dispatch hint、ABI override、constructor binding、upgrade/proxy
policy、intent 和 allocator requirement。每个字段必须由明确 target stage
消费，或对该 target 显式 reject。

`CanonicalEvidence` 只能包含 source location、verification annotation 和
migration evidence。删除它可以降低 diagnostics/proof link 质量，但不能
改变 capability、target code 或 observable execution。

## Validation

`validateCanonical` 产生 `CheckedCanonicalContract`，在 capability
resolution 前以及每次 Core rewrite 后运行。它至少检查：

- type/state/function/event/block/value identity 唯一；
- declaration/reference 已解析；
- fixed-width literal 在窄化前做 bounds check；
- operand/result/block argument/return type；
- dominance 和 def-before-use；
- storage root 与完整 path shape；
- entry block、CFG reachability 和 cycle bound；
- terminator 完整、return arity；
- event/error schema；
- arithmetic mode；
- HostOp catalog/version/arity/type/effect class；
- interface/materialization 对 canonical identity 的引用。

validation diagnostic 包含 pass、function、block、instruction index 和
reason。compiler 可以用 `CanonicalEvidence.sourceMap` 附加 source
location，但 decoration 不能改变 error tag、成功/失败结果、capability 或
target output。

## Core semantics 与 preservation

`ProofForge.IR.Core.Semantics` 定义 logical state、value environment、
CFG、event、error 和 host trace 上的 executable small-step semantics。
这里没有 target allocation。

第一条正式迁移边界是：

```lean
def LegacyScalarFragment (spec : ContractSpec) : Prop

theorem adaptLegacy_preserves_scalar_fragment
    (h : LegacyScalarFragment spec) :
    Core.Semantics.observable
      (adaptLegacy spec)
      =
    IR.Semantics.observable spec.module
```

该 theorem 覆盖 Counter 和 ValueVault 使用的 constructor 集合。其他
constructor 从 `reject` 升级为 `preserve` 或 `normalize` 前，必须
新增 proof lemma 或有记录的 executable differential certificate。
Counter/ValueVault 还要逐场景比较 state、return、event、error 和 effect
trace。

Surface normalization 具有相同义务：

```lean
theorem normalizeSurface_preserves_observables
    (h : SupportedSurfaceFragment surface) :
    Surface.Semantics.observable surface
      =
    Core.Semantics.observable (normalizeSurface surface)
```

Queue/Set 的 normalization lemma 和 executable scenario 通过后，才能扩展
`SupportedSurfaceFragment`。

## 类型化 HostOp

HostOp 只用于真正的平台专属语义，不得偷渡普通 arithmetic、storage、
branch、collection 或 target AST。

### ID 与签名

```lean
structure HostOpVersion where
  major : Nat
  minor : Nat
  patch : Nat

structure HostOpId where
  namespace : String
  name : String
  version : HostOpVersion

inductive HostOpEffectClass
  | pure
  | readOnly
  | stateful
  | external

structure HostOpSig where
  id : HostOpId
  params : Array CoreType
  results : Array CoreType
  effectClass : HostOpEffectClass
  requiredCapabilities : Array ProofForge.Target.Capability

structure HostOpCall where
  id : HostOpId
  args : Array ValueRef
```

第一版只支持 exact semantic version，不做隐含 range compatibility。
catalog 必须拒绝重复 ID 和冲突签名。

### Capability 集成

`CapabilityCall.operation` 改成 tagged operation reference：

```lean
inductive CapabilityOperation
  | builtin (name : String)
  | hostOp (id : HostOpId)
```

canonicalization 在 `HostOpCatalog` 中精确查找、校验签名，并把声明的
capability 加入现有 `CapabilityPlan`。目标既要支持 capability，也要有
该 HostOp 的具体 handler。

### 目标 handler

```lean
structure HostOpHandler (PlanOp : Type) where
  signature : HostOpSig
  lower : HostOpCall ->
    Except HostOpLowerError (Array PlanOp)

structure HostOpRegistry (PlanOp : Type) where
  targetId : String
  handlers : Array (HostOpHandler PlanOp)
```

unknown op、version mismatch、missing handler、malformed args、handler 产生
ill-typed plan op 都 fail closed。handler 不得直接生成 target AST。

### Semantics hook 与首个 slice

Core semantics 接受 `HostSemantics`。未知 HostOp 在 reference interpreter
中是 runtime error，不是 no-op。

首个真实 slice 固定为 `near.promise.create@1.0.0`：

| 字段 | 值 |
|---|---|
| 参数 | `string accountId`、`string methodName`、`bytes args`、`u128 deposit`、`u64 gas` |
| 返回 | `u64 promiseIndex` |
| effect class | `external` |
| capability | `nearPromise` |
| NEAR handler | 现有 `promise_create` semantic plan/import path |
| EVM、Solana | 编译期 `missingHostOpHandler` |

该 slice 用来证明 extension contract 可行，不代表未来所有 HostOp 已建模。

## Target plan 集成

canonical path 复用：

- `ProofForge.Backend.Evm.Plan.ModulePlan`；
- `ProofForge.Backend.Solana.Plan.SolanaModulePlan`；
- `ProofForge.Backend.WasmHost.NearModulePlan.NearModulePlan`。

可以在这些模块旁增加 Core builder，但 builder 必须产出已有 plan type，
不得新建 `EvmCorePlan`、`SolanaCorePlan`、`WasmCorePlan`。

```lean
def Evm.Plan.buildFromCore
    (contract : CheckedCanonicalContract)
    (capabilities : CapabilityPlan) :
    Except Evm.PlanError Evm.Plan.ModulePlan

def Solana.Plan.buildFromCore
    (contract : CheckedCanonicalContract)
    (capabilities : CapabilityPlan) :
    Except Solana.PlanError Solana.Plan.SolanaModulePlan

def NearModulePlan.buildFromCore
    (contract : CheckedCanonicalContract)
    (capabilities : CapabilityPlan) :
    Except NearModulePlan.PlanError NearModulePlan
```

对应 lower/render 也返回 `Except`。plan builder 分配 physical storage 和
ABI layout，lowerer 把 semantic plan op 变成 target AST，printer 渲染已
验证 AST，外部工具继续验证 artifact。

第一版不引入统一 `TargetPlan Plan Code` record。三条后端的 plan contract
确实不同，过早统一只会隐藏目标校验。

## 内部 pipeline 选择

```lean
inductive CompilerPipeline
  | legacy
  | canonical
```

dual-run test 通过 compiler API 分别调用两条路径。`--list-targets` 和
`Target.knownIds` 不变。`just canonical-*` 只运行 test/private API，
不注册新 blockchain target。

某个 target 完成全部 cutover gate 后，它原有 public ID 默认切换到
canonical。legacy builder 再保留一个 release window 供 parity/rollback，
之后删除。

## Queue/Set normalization

三条 target plan 都能消费 canonical Core，且 Counter/ValueVault parity
通过后，才能开放 Queue/Set。

### Queue

`Queue<T, capacity>` 展开为：

- `$queue.<id>.items : fixedArray T capacity`；
- `$queue.<id>.head : scalar u64`；
- `$queue.<id>.length : scalar u64`。

enqueue 先断言 `length < capacity`，写
`(head + length) mod capacity`，再递增 length。dequeue 先断言
`length > 0`，读取 head，head 按 capacity 环绕，length 减一。
capacity 不能为零，生成 identity 冲突时 normalization 失败。

### Set

`Set<T, capacity>` 展开为 `map T bool (some capacity)` 加 scalar
cardinality。insert 只在 key 原本不存在时递增 cardinality，并检查
capacity；remove 只在 key 原本存在时递减。

两者都不得增加 Core instruction 或 target-plan constructor。目标不能
materialize 现有 state shape 时由 capability resolution 拒绝。

## 错误模型

```text
SurfaceError
  -> CanonicalizeError
  -> CoreValidationError
  -> CapabilityResolutionError
  -> HostOpResolutionError
  -> TargetPlanError
  -> TargetLowerError
  -> TargetRenderError
  -> ArtifactValidationError
```

任何 stage 都不能把错误转换为空 body、selector 0、slot 0、占位指令或
成功信息。`check` 至少到 canonical/capability/plan/target-AST validate；
`build` 在项目所需工具可用时继续到 printer 和外部 artifact validation。

## 迁移顺序

### Wave 0：恢复能力声明真实性

- 删除 public `*-core` profile 和 CLI route；
- 删除或重写 fail-open package check；
- spike 只作为待替换的内部代码；
- 增加 registry、advertised command invariant tests。

### Wave 1：Canonical Core 基础

- logical identity、StateShape、typed ANF/CFG、LoopBound、validator、
  structured diagnostic；
- checked interface/materialization ownership与 non-semantic evidence；
- Core executable semantics；
- 冻结 Legacy IR，建立完整 constructor/field classification。

### Wave 2：Legacy adapter 与语义等价

- Counter/ValueVault 不丢 state、metadata、effect；
- 证明 scalar fragment preservation；
- 运行 state/return/event/error/effect differential scenarios。

### Wave 3：Typed HostOp contract

- versioned ID、signature、catalog validator、capability operation tag、
  target registry、semantic hook；
- 没有 target handler 和 negative tests 时不能启用 host call。

### Wave 4：迁移到已有 target plan

- Core builder -> 现有 EVM Plan -> Yul；
- Core builder -> 现有 Solana Plan -> sBPF；
- Core builder -> 现有 NearModulePlan -> Wasm；
- 关闭完整现有 product/coverage manifest，包括 aggregate、storage path、
  context/hash/control/error、crosscall、ABI 和 deployment materialization；
- 每条 public route 在完整 gate 通过前继续用 Legacy。

### Wave 5：独立 Surface 与两个 vertical slice

- 新增独立 Surface AST 和 versioned source-loader route；
- Queue/Set 在三主 target 验证；
- `near.promise.create@1.0.0` 在 NEAR 成功，在 EVM/Solana fail closed。

### Wave 6：切换与清理

- 三个已有 public target ID 切换 canonical lowering；
- rollback window 内保留 legacy dual-run；
- 机械执行 dependency boundary；
- 删除 spike plan type 和过时 route。

## 验证与切换 Gate

### Core/Adapter

- constructor/field inventory 无未分类项；
- invalid literal、unknown state、shape mismatch、use-before-def、type
  mismatch、unbounded-loop mismatch、missing return、unknown HostOp 全失败；
- Counter/ValueVault 保留 state ID、entrypoint semantics 和所有
  artifact-affecting metadata；
- Legacy/Core 的 state、return、event、error、ordered effect 相同；
- scalar-fragment preservation theorem 编译通过。
- 现有 product matrix 和主目标 coverage manifest 使用的每个 constructor
  都完成 canonical parity，或返回相同/更严格的 public diagnostic。

### EVM

- canonical plan 可检查且不含 Yul AST；
- Yul 通过 `solc --strict-assembly`；
- Counter/ValueVault 的 Foundry/Anvil 行为与 legacy 相同；
- `just evm-all` 继续通过。

### Solana

- canonical plan 不含 `AstNode`；
- assembly 通过仓库 assembler/encoder/verifier；
- Counter/ValueVault execution trace 与 legacy 相同；
- `just solana-light` 继续通过；
- Surfpool/Pinocchio 保持 optional tool-enabled gate。

### NEAR/Wasm

- canonical plan 不含 `Wasm.Insn`；
- WAT 通过 `wat2wasm`；
- offline host 的 state/return/log/error 与 legacy 相同；
- EmitWat、target-first、NEAR offline-host gates 继续通过。

### Product/Repository

```bash
just product
just canonical-core
just canonical-parity
just canonical-product
just check
git diff --check
```

该修改触及 product authoring path，因此 `just product` 永远先跑。

## 架构机械门禁

仓库检查拒绝：

- backend import `ProofForge.Frontend.Surface`；
- canonical target builder import 或消费 Legacy IR；
- target plan declaration 包含 final AST type；
- public target ID 以 `-core` 结尾；
- canonical compiler pass 的 public result 无法表达 failure；
- Legacy constructor/field 未分类；
- stable primitive boundary 锁定后，Queue/Set 修改 Core 或 backend 文件。

对应 migration wave 能满足检查后再把它加入 `just check`，不能为了半成品
后端降低规则。

## 风险与控制

| 风险 | 控制 |
|---|---|
| Core 变成另一套快速变化的 Surface | Core 只保留 semantic ANF/CFG；collection 留在 Surface；新增 Core constructor 必须架构评审。 |
| materialization 变成无类型 metadata bag | 每个字段有类型、owner、target support rule 和测试。 |
| evidence 意外影响代码 | plan-builder signature 不接收 evidence，并用 deterministic artifact test 检查。 |
| HostOp 变成 string escape hatch | exact version、signature、effect class、capability、handler 和 semantics 全部强制。 |
| 两套 backend 长期共存 | 每 target cutover gate 加一个 release rollback window，不增加 public duplicate ID。 |
| 新旧 formal semantics 分叉 | Legacy adapter preservation 和 shared observable relation 桥接。 |
| Lean model 与工具链不一致 | 外部 syntax/verifier/runtime gate 永久保留。 |

## 拒绝的替代方案

### 先完整建模三个 target ISA

完整 EVM、sBPF、Wasm model 对验证有价值，但不能直接消除 Surface
constructor diffusion，而且会推迟稳定 compiler boundary。第一步应该是
Canonical Core 和 target-semantic plan。

### 继续把 `IR.Contract` 当可扩展 Surface

其 closed inductive 已经被所有后端消费，继续加 constructor 会复现原问题。

### 永久把 Core 回译为 Legacy IR

差分测试可以有临时 reifier，但 production target builder 不能依赖它。
永久 Core-to-Legacy 会保留旧 constructor bottleneck 和第二份 semantic
truth。

### 新增三套平行 CorePlan

`EvmCorePlan`、`SolanaCorePlan`、`WasmCorePlan` 会复制 plan、
diagnostic、proof 和 test ownership。

### 用 public `*-core` target 迁移

它们表示内部 compiler route，不是 blockchain platform，会把半成品纳入
产品契约。

### 打印成功就算正确

printer 成功不代表 target validity，更不代表 runtime equivalence。

## 完成标准

只有同时满足以下条件才算完成：

1. Frozen Legacy adapter 和独立 Surface normalizer 产生同一
   `CanonicalBundle` 边界。
2. Counter/ValueVault 通过 Core semantics 和三目标 runtime parity。
3. 完整现有 product matrix 和主目标 coverage manifest 通过 canonical
   lowering，不发生支持回退。
4. canonical lowering 只使用现有 EVM/Solana/NEAR plan type。
5. Queue/Set 通过现有三个 public target ID 编译，且没有修改 Core 或
   target-plan constructor。
6. `near.promise.create@1.0.0` 在 NEAR 成功，在 EVM/Solana 通过 typed
   registry fail closed。
7. public registry 和 CLI target list 不变。
8. `CanonicalEvidence` 不影响 capability resolution 和 target output。
9. `just product`、canonical gates、`just check`、
   `git diff --check` 全部通过。
