# Core IR + Target Plan Decoupling Layer

## Status

Draft — pending spec review and implementation planning.

## Authors

ProofForge team.

## Context

ProofForge has an extensible portable IR defined in `ProofForge/IR/Contract.lean`. When this IR is materialized to concrete blockchain instruction sets (EVM/Yul, Solana sBPF assembly, NEAR WASM), the current implementation suffers from tight coupling:

- **EVM**: IR lowering goes through `ExprPlan`/`StmtPlan` in `ProofForge/Backend/Evm/Plan.lean`, which mirrors almost every IR constructor. Adding a new `Expr`/`Effect` node ripples through plan, validation, Yul emission, refinement, and the in-Lean Yul interpreter.
- **Solana**: `ProofForge/Backend/Solana/SbpfAsm.lean` mixes account schema, state layout, locals, scratch space, and allocator in `LowerCtx`. New IR constructs require large downstream changes.
- **NEAR/WASM**: `ProofForge/Backend/WasmHost/EmitWat.lean` and its per-feature modules (`Scalar.lean`, `Map.lean`, `Statement.lean`, etc.) directly pattern-match on IR constructors.

The existing `ModulePlan` abstractions in Solana and NEAR have solved *layout-drift* (account layout, memory layout, host imports), but they have not solved *constructor diffusion*: the function-body lowering still exhaustively pattern-matches on the full `Contract.lean` AST.

## Goal

Introduce a stable **Core IR** and a **Target Plan** layer using Lean. The purpose is architectural decoupling: once the IR design stabilizes, downstream target platforms should require minimal changes when the surface IR evolves.

**Phase 1 boundary (option 1)**: decouple syntax and SDK abstractions. New syntax sugar, `Queue`, `Map`, set APIs, and business DSLs should only change the surface IR and the Surface → Core elaboration layer. Only genuinely new semantic primitives should require changes to target adapters.

**Phase 2 boundary (option 2)**: reserve an extension point (`hostOp`) for chain-specific runtime capabilities (Solana PDA, NEAR promises, EVM `create2`, etc.) without expanding the fixed Core IR enumeration.

We explicitly **do not** build a unified VM/bytecode interpreter for Phase 1.

## Non-goals

- Replace the existing EVM/Solana/NEAR backends immediately.
- Build a chain-agnostic VM or interpreter.
- Add high-level data structures like `Queue` directly to the low-level Yul/sBPF/WASM AST.
- Prove full refinement in Phase 1.

## Architecture

```
┌─────────────────────────────────────────┐
│  Surface IR                              │
│  ProofForge/IR/Contract.lean (existing)  │
│  Extensible: Queue, sets, syntax sugar,  │
│  business DSLs                           │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Elaborate                               │
│  ProofForge/IR/Elaborate.lean            │
│  Surface IR → Core IR normalization      │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Core IR                                 │
│  ProofForge/IR/Core.lean                 │
│  Stable semantic primitives              │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Target Plan                             │
│  ProofForge/Backend/{Evm,Solana,WasmHost}│
│  /CorePlan.lean                          │
│  Target-specific lowering plan           │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│  Target Code                             │
│  Yul / sBPF assembly / WAT               │
└─────────────────────────────────────────┘
```

## Core IR (`ProofForge/IR/Core.lean`)

Core IR contains only semantic primitives. It intentionally removes syntax sugar and chain-specific shapes.

### Types

```lean
inductive CoreType
  | unit | bool | u8 | u32 | u64 | u128
  | address
  | bytes | string | hash
  | fixedArray (element : CoreType) (length : Nat)
  | array (element : CoreType)
  | structType (name : String)
```

### Expressions

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
  | hostOpStub (op : HostOpId) (args : List CoreExpr)  -- Phase 2 extension point
```

### Effects

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
  | hostOpStubEffect (op : HostOpId) (args : List CoreExpr)  -- Phase 2 extension point
```

### Statements

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

### Module

```lean
structure CoreModule where
  name : String
  structs : List CoreStruct
  state : List CoreStateDecl
  entrypoints : List CoreEntrypoint
  events : List CoreEvent
```

### Supporting types

The following auxiliary types are defined alongside the main inductive types in `ProofForge/IR/Core.lean`. Their exact shapes are part of the implementation work; the list below fixes their roles so that the rest of the spec is unambiguous.

| Type | Role |
|---|---|
| `CoreLiteral` | Literals for unit, booleans, fixed-width integers, addresses, bytes, strings, and hashes. |
| `UnaryOp` / `BinaryOp` | Arithmetic, bitwise, comparison, and logical operators shared across targets. |
| `ContextKind` | Reads from transaction context: sender, value, block timestamp, etc. |
| `CrosscallSpec` | Cross-contract call descriptor, including target family and gas/value semantics. |
| `StoragePath` | Path to a storage location: scalar slot, map key, array index, or struct field projection. |
| `LValue` | Assignable target: local variable, storage path, or memory location. |
| `CoreStruct` / `CoreStateDecl` / `CoreEntrypoint` / `CoreEvent` | Module-level declarations matching the existing IR but without chain-specific metadata. |
| `HostOpId` | Opaque identifier reserved for Phase 2 host-op extension. |

## Surface → Core Elaboration (`ProofForge/IR/Elaborate.lean`)

Elaboration is a pure function that expands high-level abstractions into Core IR primitives:

```lean
def elaborateModule (m : IR.Module) : Except ElabError CoreModule
```

| Surface construct | Core IR expansion |
|---|---|
| `Queue<T>` | `array T` plus head/tail index fields |
| `Set<T>` | `map T bool` |
| `a += b` | `assignOp` |
| `for i in 0..n` | `boundedFor` |
| `require cond` | `assert cond` |
| `emit Event(args)` | `eventEmit` |
| `crosscall Evm/Solana/Near(...)` | `crosscall` with `CrosscallSpec.family` |

Unsupported Surface nodes produce `ElabError.unsupported (node : String)`.

## Target Plan Abstraction

Each target defines its own plan and code types, then implements the pipeline:

```lean
structure TargetPlan (Plan Code : Type) where
  validateModule : CoreModule → Except ValidationError Unit
  buildPlan      : CoreModule → Plan
  lowerToCode    : Plan → Code
```

For example:
- `TargetPlan EvmCorePlan Yul.Object` for EVM.
- `TargetPlan SolanaCorePlan (List AstNode)` for Solana sBPF assembly.
- `TargetPlan WasmCorePlan Wasm.Module` for NEAR/WASM.

Target plan modules:

- `ProofForge/Backend/Evm/CorePlan.lean` — `EvmCorePlan` (storage slots, dispatcher, Yul function plan).
- `ProofForge/Backend/Solana/CorePlan.lean` — `SolanaCorePlan` (account layout, instruction data layout, CPI plan, syscall plan).
- `ProofForge/Backend/WasmHost/CorePlan.lean` — `WasmCorePlan` (memory layout, host import plan, function plan).

Each plan depends only on Core IR, never directly on Surface IR.

## Backend Code Generation

Each backend adds two new modules alongside the existing ones:

- `CorePlan.lean` — Core IR → target plan.
- `CoreLower.lean` — target plan → target code.

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

## Integration with Existing Code

The new modules run in parallel with existing backends. Existing paths are not deprecated in Phase 1.

| Existing path | New path |
|---|---|
| `ProofForge/Backend/Evm/Plan.lean` | `ProofForge/Backend/Evm/CorePlan.lean` |
| `ProofForge/Backend/Evm/IR.lean` | `ProofForge/Backend/Evm/CoreLower.lean` |
| `ProofForge/Backend/Solana/SbpfAsm.lean` | `ProofForge/Backend/Solana/CorePlan.lean` + `CoreLower.lean` |
| `ProofForge/Backend/WasmHost/EmitWat.lean` | `ProofForge/Backend/WasmHost/CorePlan.lean` + `CoreLower.lean` |

Experimental target ids for CLI:

- `evm-core`
- `solana-sbpf-asm-core`
- `wasm-near-core`

Once mature, the original target ids can be redirected to the new paths or the experimental ids can be promoted.

## Error Handling

- **Elaboration error**: Surface IR contains a node Core IR cannot express.
- **Validation error**: Core IR itself is malformed (type mismatch, uninitialized state, etc.).
- **Capability error**: A target does not support a Core IR node.
- **Lowering error**: Plan generation or code emission fails.

Error types live in `ProofForge/IR/Core/Error.lean` and `ProofForge/Target/CoreError.lean`.

## Testing Strategy

1. **Core IR well-formedness tests** for `CoreModule`.
2. **Elaboration roundtrip tests**: Surface fixtures → Core IR → structural checks.
3. **Backend output equivalence**: Same Surface fixture through both old and new paths; compare semantic equivalence of generated Yul/sBPF/WAT (text differences allowed).
4. **Product smokes**: Counter and ValueVault through `evm-core`, `solana-sbpf-asm-core`, and `wasm-near-core`.
5. **Formal anchor**: Define a small-step semantics for Core IR in `ProofForge/IR/Core/Semantics.lean`. Refinement proofs are not required in Phase 1.

## Phase 1 Milestones

1. **M0**: Core IR AST compiles with `lake build`.
2. **M1**: Surface → Core elaboration covers Counter and ValueVault.
3. **M2**: EVM `CorePlan` + `CoreLower` produce compilable Yul and pass Foundry smoke.
4. **M3**: Solana `CorePlan` + `CoreLower` skeleton produce sBPF assembly and pass `just solana-light`.
5. **M4**: WasmHost `CorePlan` + `CoreLower` skeleton produce WAT and pass `wasm-near-host-smoke`.
6. **M5**: CLI supports experimental target ids; documentation and tests complete.

## Risks and Rollback

- The new code paths are independent; existing backends remain untouched.
- If a target's new path fails, that target can continue using the old path.
- If the Core IR boundary proves insufficient, the reserved `hostOpStub` extension point allows growth without rewriting the architecture.

## Future Work (Phase 2)

- Implement the `hostOp` registry for chain-specific runtime capabilities.
- Prove Core IR ↔ target-code refinement for a fixed fragment.
- Promote experimental target ids to default ids once product gates pass.
