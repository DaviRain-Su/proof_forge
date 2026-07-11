# Core IR + Target Plan 解耦层

## 状态

草稿 —— 等待 spec 审查和实现计划。

## 作者

ProofForge 团队。

## 背景

ProofForge 当前的可移植 IR 定义在 `ProofForge/IR/Contract.lean` 中。当这个 IR 物化到具体区块链指令集（EVM/Yul、Solana sBPF 汇编、NEAR WASM）时，现有实现存在紧耦合问题：

- **EVM**：IR lowering 经过 `ProofForge/Backend/Evm/Plan.lean` 中的 `ExprPlan`/`StmtPlan`，几乎逐节点镜像 IR。新增一个 `Expr`/`Effect` 节点会扩散到 plan、验证、Yul 生成、refinement 和 Lean 内的 Yul 解释器。
- **Solana**：`ProofForge/Backend/Solana/SbpfAsm.lean` 把账户 schema、状态布局、locals、scratch space、allocator 全混在 `LowerCtx` 里。新增 IR 构造子需要大量下游改动。
- **NEAR/WASM**：`ProofForge/Backend/WasmHost/EmitWat.lean` 及其特性小模块（`Scalar.lean`、`Map.lean`、`Statement.lean` 等）直接对 IR 构造子做模式匹配。

Solana 和 NEAR 现有的 `ModulePlan` 抽象已经解决了*布局漂移*（账户布局、内存布局、host imports），但还没有解决*构造子扩散*：函数体 lowering 仍然直接穷举完整的 `Contract.lean` AST。

## 目标

引入一个稳定的 **Core IR** 和一个 **Target Plan** 层，使用 Lean 实现。目的是架构解耦：一旦 IR 设计稳定下来，上层 surface IR 演进时，下游目标平台应只需要最小改动。

**第一阶段边界（选项 1）**：解耦语法和 SDK 抽象。新增语法糖、`Queue`、`Map`、集合 API、业务 DSL 只应修改 surface IR 和 Surface → Core elaboration 层；只有真正新增的语义原语才需要修改目标适配器。

**第二阶段边界（选项 2）**：为链特定的 runtime 能力（Solana PDA、NEAR promise、EVM `create2` 等）预留扩展点（`hostOp`），无需扩展固定 Core IR 枚举。

第一阶段明确**不**构建统一的 VM/字节码解释器。

## 非目标

- 立即替换现有 EVM/Solana/NEAR 后端。
- 构建链无关的 VM 或解释器。
- 把 `Queue` 这类高层数据结构直接塞进低层 Yul/sBPF/WASM AST。
- 在第一阶段证明完整 refinement。

## 架构

```
┌─────────────────────────────────────────┐
│  Surface IR                              │
│  ProofForge/IR/Contract.lean（现有）     │
│  可扩展：Queue、集合、语法糖、业务 DSL    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Elaborate                               │
│  ProofForge/IR/Elaborate.lean            │
│  Surface IR → Core IR 规范化             │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Core IR                                 │
│  ProofForge/IR/Core.lean                 │
│  稳定语义原语                            │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Target Plan                             │
│  ProofForge/Backend/{Evm,Solana,WasmHost}│
│  /CorePlan.lean                          │
│  目标相关的 lowering 计划                │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Target Code                             │
│  Yul / sBPF assembly / WAT               │
└─────────────────────────────────────────┘
```

## Core IR（`ProofForge/IR/Core.lean`）

Core IR 只包含语义原语。它刻意去掉了语法糖和链特定形态。

### 类型

```lean
inductive CoreType
  | unit | bool | u8 | u32 | u64 | u128
  | address
  | bytes | string | hash
  | fixedArray (element : CoreType) (length : Nat)
  | array (element : CoreType)
  | structType (name : String)
```

### 表达式

```lean
inductive CoreExpr
  | literal (val : CoreLiteral)
  | local (name : String)
  | fieldAccess (base : CoreExpr) (field : String)
  | arrayIndex (base : CoreExpr) (index : CoreExpr)
  | unary (op : UnaryOp) (arg : CoreExpr)
  | binary (op : BinaryOp) (lhs rhs : CoreExpr)
  | cast (from to : CoreType) (arg : CoreExpr)
  | hash (arg : CoreExpr)
  | contextRead (kind : ContextKind)
  | crosscall (spec : CrosscallSpec) (args : List CoreExpr)
  | hostOpStub (op : HostOpId) (args : List CoreExpr)  -- 第二阶段扩展点
```

### 副作用

```lean
inductive CoreEffect
  | storageRead  (path : StoragePath)
  | storageWrite (path : StoragePath) (val : CoreExpr)
  | memoryRead   (base : CoreExpr) (offset : Nat) (ty : CoreType)
  | memoryWrite  (base : CoreExpr) (offset : Nat) (val : CoreExpr)
  | eventEmit    (name : String) (args : List CoreExpr)
  | contextReadEffect (kind : ContextKind)
  | crosscallEffect (spec : CrosscallSpec) (args : List CoreExpr)
  | assert       (cond : CoreExpr) (msg : Option String)
  | revert       (msg : Option String)
  | hostOpStubEffect (op : HostOpId) (args : List CoreExpr)  -- 第二阶段扩展点
```

### 语句

```lean
inductive CoreStmt
  | letBind    (name : String) (ty : CoreType) (val : CoreExpr)
  | letMutBind (name : String) (ty : CoreType) (val : CoreExpr)
  | assign     (lhs : LValue) (rhs : CoreExpr)
  | assignOp   (lhs : LValue) (op : BinaryOp) (rhs : CoreExpr)
  | effect     (e : CoreEffect)
  | ifElse     (cond : CoreExpr) (thenBranch elseBranch : List CoreStmt)
  | boundedFor (iter : String) (bound : CoreExpr) (body : List CoreStmt)
  | whileLoop  (cond : CoreExpr) (body : List CoreStmt)
  | return     (val : CoreExpr)
```

### 模块

```lean
structure CoreModule where
  name : String
  structs : List CoreStruct
  state : List CoreStateDecl
  entrypoints : List CoreEntrypoint
  events : List CoreEvent
```

### 辅助类型

以下辅助类型与主 inductive 类型一起定义在 `ProofForge/IR/Core.lean` 中。它们的具体形状属于实现工作的一部分；下表固定它们的角色，以保证本 spec 其余部分无歧义。

| 类型 | 作用 |
|---|---|
| `CoreLiteral` | unit、布尔值、定宽整数、address、bytes、string、hash 的字面量。 |
| `UnaryOp` / `BinaryOp` | 跨目标共享的算术、位运算、比较和逻辑运算符。 |
| `ContextKind` | 从交易上下文中读取：sender、value、block timestamp 等。 |
| `CrosscallSpec` | 跨合约调用描述符，包括目标 family 和 gas/value 语义。 |
| `StoragePath` | 存储位置路径：标量 slot、map key、array index 或 struct field 投影。 |
| `LValue` | 可赋值目标：局部变量、storage path 或 memory 位置。 |
| `CoreStruct` / `CoreStateDecl` / `CoreEntrypoint` / `CoreEvent` | 与现有 IR 对应的模块级声明，但不含链特定元数据。 |
| `HostOpId` | 为第二阶段 host-op 扩展预留的不透明标识符。 |

## Surface → Core Elaboration（`ProofForge/IR/Elaborate.lean`）

Elaboration 是一个纯函数，负责把高层抽象展开为 Core IR 原语：

```lean
def elaborateModule (m : IR.Module) : Except ElabError CoreModule
```

| Surface 构造 | Core IR 展开 |
|---|---|
| `Queue<T>` | `array T` 加上头/尾索引字段 |
| `Set<T>` | `map T bool` |
| `a += b` | `assignOp` |
| `for i in 0..n` | `boundedFor` |
| `require cond` | `assert cond` |
| `emit Event(args)` | `eventEmit` |
| `crosscall Evm/Solana/Near(...)` | `crosscall`，携带 `CrosscallSpec.family` |

不支持的 Surface 节点产生 `ElabError.unsupported (node : String)`。

## Target Plan 抽象

每个目标定义自己的 plan 和 code 类型，然后实现流水线：

```lean
structure TargetPlan (Plan Code : Type) where
  validateModule : CoreModule → Except ValidationError Unit
  buildPlan      : CoreModule → Plan
  lowerToCode    : Plan → Code
```

例如：
- EVM 使用 `TargetPlan EvmCorePlan Yul.Object`。
- Solana 使用 `TargetPlan SolanaCorePlan (List AstNode)`。
- NEAR/WASM 使用 `TargetPlan WasmCorePlan Wasm.Module`。

Target plan 模块：

- `ProofForge/Backend/Evm/CorePlan.lean` —— `EvmCorePlan`（storage slot 分配、dispatcher、Yul function 计划）。
- `ProofForge/Backend/Solana/CorePlan.lean` —— `SolanaCorePlan`（账户布局、指令数据布局、CPI 计划、syscall 计划）。
- `ProofForge/Backend/WasmHost/CorePlan.lean` —— `WasmCorePlan`（内存布局、host import 计划、function 计划）。

每个 plan 只依赖 Core IR，不直接依赖 Surface IR。

## 后端代码生成

每个后端新增两个模块，与现有模块并行：

- `CorePlan.lean` —— Core IR → 目标 plan。
- `CoreLower.lean` —— 目标 plan → 目标代码。

### EVM

```
Core IR → EvmCorePlan → Yul.Statement/Yul.Expr → Yul.Printer → solc --strict-assembly
```

### Solana

```
Core IR → SolanaCorePlan → Asm.AstNode → Asm.renderNodes → sbpf toolchain
```

### NEAR / WASM

```
Core IR → WasmCorePlan → Wasm.Module → Wasm.Printer → wat2wasm
```

## 与现有代码的衔接

新模块与现有后端并行运行。第一阶段不废弃现有路径。

| 现有路径 | 新路径 |
|---|---|
| `ProofForge/Backend/Evm/Plan.lean` | `ProofForge/Backend/Evm/CorePlan.lean` |
| `ProofForge/Backend/Evm/IR.lean` | `ProofForge/Backend/Evm/CoreLower.lean` |
| `ProofForge/Backend/Solana/SbpfAsm.lean` | `ProofForge/Backend/Solana/CorePlan.lean` + `CoreLower.lean` |
| `ProofForge/Backend/WasmHost/EmitWat.lean` | `ProofForge/Backend/WasmHost/CorePlan.lean` + `CoreLower.lean` |

CLI 实验性 target id：

- `evm-core`
- `solana-sbpf-asm-core`
- `wasm-near-core`

成熟后，原 target id 可以重定向到新路径，或者实验性 id 可以晋升为主路径。

## 错误处理

- **Elaboration 错误**：Surface IR 包含 Core IR 无法表达的节点。
- **Validation 错误**：Core IR 本身非法（类型不匹配、状态未初始化等）。
- **Capability 错误**：目标不支持某个 Core IR 节点。
- **Lowering 错误**：plan 生成或代码生成失败。

错误类型放在 `ProofForge/IR/Core/Error.lean` 和 `ProofForge/Target/CoreError.lean`。

## 测试策略

1. **Core IR 良构性测试**：针对 `CoreModule` 的 well-formedness checker。
2. **Elaboration roundtrip 测试**：Surface fixture → Core IR → 结构检查。
3. **后端输出等价性**：同一 Surface fixture 同时走旧路径和新路径，比较生成 Yul/sBPF/WAT 的语义等价性（允许文本差异）。
4. **产品 smoke**：Counter 和 ValueVault 通过 `evm-core`、`solana-sbpf-asm-core`、`wasm-near-core` 跑通。
5. **形式化锚点**：在 `ProofForge/IR/Core/Semantics.lean` 中定义 Core IR 小步语义。第一阶段不要求 refinement 证明。

## 第一阶段里程碑

1. **M0**：Core IR AST 通过 `lake build` 编译。
2. **M1**：Surface → Core elaboration 覆盖 Counter 和 ValueVault。
3. **M2**：EVM `CorePlan` + `CoreLower` 生成可编译 Yul，通过 Foundry smoke。
4. **M3**：Solana `CorePlan` + `CoreLower` 骨架生成 sBPF 汇编，通过 `just solana-light`。
5. **M4**：WasmHost `CorePlan` + `CoreLower` 骨架生成 WAT，通过 `wasm-near-host-smoke`。
6. **M5**：CLI 支持实验性 target id，文档和测试补齐。

## 风险与回退

- 新代码路径完全独立；现有后端不受影响。
- 如果某条链的新路径失败，该链可以继续使用旧路径。
- 如果 Core IR 边界被发现不够，预留的 `hostOpStub` 扩展点允许在不推翻整体架构的情况下增长。

## 未来工作（第二阶段）

- 为链特定 runtime 能力实现 `hostOp` 注册表。
- 对固定片段证明 Core IR ↔ 目标代码 refinement。
- 产品 gate 通过后，把实验性 target id 晋升为主路径。
