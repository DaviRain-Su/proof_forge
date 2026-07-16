# Leo AST Mirror: IR → AST → Source Design

**Date:** 2026-07-01  
**Status:** Historical implemented AST-migration design record (archived 2026-07-12).
**Scope:** Refactor the Aleo Leo backend so that it lowers ProofForge portable IR into a structured Leo AST that mirrors `ProvableHQ/leo crates/ast/src/` (v4.3.2), then pretty-prints that AST to Leo source compatible with the locally installed Leo 4.0.2 CLI.  
**Related docs:**
- [Aleo Leo spike design](./2026-07-01-aleo-leo-design.md)
- [Aleo Leo target note](../../targets/aleo-leo.md)
- [Capability registry](../../capability-registry.md)
- [Portable IR](../../portable-ir.md)

---

## 1. Goal

Replace the current direct string emission in `ProofForge.Backend.Aleo.IR` with a two-stage pipeline:

```text
ProofForge portable IR
  -> ProofForge.Compiler.Leo.Emit       (IR -> Leo AST)
  -> ProofForge.Compiler.Leo.Printer    (Leo AST -> String)
  -> Counter.leo
```

The Leo AST must be a faithful structural mirror of the official `leo_ast` crate so that future work can extend lowering without redesigning the representation. The printer targets the surface syntax accepted by the Leo 4.0.2 toolchain already installed for the spike smoke tests, while the AST itself stays aligned with Leo 4.3.2.

---

## 2. Executive Summary

The current Aleo backend concatenates strings. This works for the Counter spike but is hard to extend, review, and validate. This design introduces a complete, typed Leo AST in Lean, modeled on the official compiler's AST, plus a separate printer that knows how to render that AST as valid Leo 4.0.2 source.

Key consequences:
- The golden fixture and smoke test output remain unchanged (still Leo 4.0.2).
- New syntax nodes can be added to the AST without touching the IR lowering until needed.
- The printer is the single place that maps official AST concepts to surface syntax (e.g. `async { }` -> `final { }`, `Final<Fn(...)>` -> `Final`).

---

## 3. AST Structure

The AST is organized under `ProofForge/Compiler/Leo/` to mirror the project’s existing `ProofForge/Compiler/Yul/` pattern.

### 3.1 Module Layout

| Lean module | Official `leo_ast` source | Responsibility |
|---|---|---|
| `ProofForge.Compiler.Leo.AST` | `crates/ast/src/lib.rs` | Root re-exports. |
| `ProofForge.Compiler.Leo.AST.Core` | `common.rs`, `identifier.rs`, `annotation.rs` | `Identifier`, `Symbol`, `Annotation`, `Mode`, etc. |
| `ProofForge.Compiler.Leo.AST.Type` | `types/` | `Type`, `IntegerType`, `MappingType`, `FutureType`, `ArrayType`, etc. |
| `ProofForge.Compiler.Leo.AST.Literal` | `expressions/literal.rs` | `Literal` / `LiteralVariant`. |
| `ProofForge.Compiler.Leo.AST.Expression` | `expressions/` | `Expression`, `BinaryExpression`, `UnaryExpression`, `CallExpression`, `MemberAccess`, `AsyncExpression`, `CastExpression`, etc. |
| `ProofForge.Compiler.Leo.AST.Statement` | `statement/` | `Statement`, `Block`, `DefinitionStatement`, `AssignStatement`, `ConditionalStatement`, `IterationStatement`, `ReturnStatement`, `AssertStatement`. |
| `ProofForge.Compiler.Leo.AST.Function` | `functions/` | `Function`, `Variant`, `Input`, `Output`. |
| `ProofForge.Compiler.Leo.AST.Composite` | `composite/` | `Composite`, `Member` (struct/record). |
| `ProofForge.Compiler.Leo.AST.Mapping` | `mapping/` | `Mapping` declaration. |
| `ProofForge.Compiler.Leo.AST.Storage` | `storage/` | `StorageVariable`. |
| `ProofForge.Compiler.Leo.AST.Program` | `program/`, `constructor/` | `Program`, `ProgramScope`, `Import`, `Constructor`. |

### 3.2 Design Choices

- **No source spans.** The Lean AST drops `Span`, `NodeID`, and other parser bookkeeping. It is a semantic AST, not a concrete syntax tree.
- **Lists instead of `IndexMap`.** Use `List (Identifier × T)` for ordered mappings; order is preserved by the printer.
- **Identifiers as `String`.** `leo_ast` uses `Symbol`; we use plain strings.
- **All variants present.** Even nodes not needed for Counter (records, interfaces, consts, etc.) are defined. Their printer branches start as `unsupported` errors and are filled in later.
- **Async/final representation.** The AST follows Leo 4.3.2: entry functions return `FutureType` and contain `AsyncExpression` blocks. The printer downgrades this to Leo 4.0.2 `final { }` syntax.

### 3.3 Expression Forms

Important expressions for Counter and near-term expansion:

```lean
inductive Expression where
  | literal     : Literal → Expression
  | identifier  : Identifier → Expression
  | binary      : BinaryOperation → Expression → Expression → Expression
  | unary       : UnaryOperation → Expression → Expression
  | call        : Path → List Expression → List Expression → Expression
  | memberAccess : Expression → Identifier → Expression
  | async       : Block → Expression
  | cast        : Expression → Type → Expression
  | unit
  | err
```

- `call` stores the function path, const generic arguments, and value arguments.
- Mapping operations are represented as `call` with a path like `Mapping::set`, `Mapping::get_or_use`, etc. (printer emits the `Mapping::` form to match the existing golden fixture).

### 3.4 Statement Forms

```lean
inductive Statement where
  | definition : DefinitionPlace → Option Type → Expression → Statement
  | assign     : Expression → Expression → Statement
  | block      : Block → Statement
  | conditional : Expression → Block → Option Statement → Statement
  | iteration  : Identifier → Option Type → Expression → Expression → Bool → Block → Statement
  | returnSt   : Option Expression → Statement
  | assertSt   : Expression → Option Expression → Statement
  | expression : Expression → Statement
```

### 3.5 Program / Function Forms

```lean
inductive Variant where
  | fn          -- regular function
  | finalFn     -- final fn
  | entryPoint  -- top-level transition
  | view        -- view fn

structure Function where
  annotations : List Annotation
  variant : Variant
  identifier : Identifier
  constParameters : List ConstParameter
  input : List Input
  output : List Output
  outputType : Type
  block : Block

structure ProgramScope where
  programId : Identifier
  parents : List Type
  consts : List (Identifier × ConstDeclaration)
  composites : List (Identifier × Composite)
  mappings : List (Identifier × Mapping)
  storageVariables : List (Identifier × StorageVariable)
  functions : List (Identifier × Function)
  interfaces : List (Identifier × Interface)
  constructor : Option Constructor

structure Program where
  imports : List (Identifier × ProgramId)
  scopes : List (Identifier × ProgramScope)
```

For the Counter spike the program has one `ProgramScope` containing one mapping, one constructor, and three entry functions.

---

## 4. Lowering Pipeline

### 4.1 IR → Leo AST

Implemented in `ProofForge/Compiler/Leo/Emit.lean`.

| Portable IR | Leo AST |
|---|---|
| `Module.name` | `Program` with one `ProgramScope` named `<name>.aleo` |
| scalar `U64` state | `Mapping` keyed and valued by `Type.integer IntegerType.u64` |
| `Entrypoint` with side effects / mapping reads | `Function { variant := .entryPoint, outputType := futureType, block := asyncBlock }` |
| `storageScalarRead` | `Expression.call "Mapping::get_or_use" [mappingName, 0u64, 0u64]` |
| `storageScalarWrite` | expression statement `Mapping::set(mappingName, 0u64, value)` inside the async block |
| `add` | `Expression.binary .add left right` |
| `U64 literal` | `Literal.integer .u64 value` |
| `letBind` | `Statement.definition (single name) (some type) value` |
| `return` | `Statement.returnSt (some expr)` |

The fixed mapping key `0u64` is the same placeholder used in the current string backend.

### 4.2 AST → String

Implemented in `ProofForge/Compiler/Leo/Printer.lean`.

The printer is responsible for all surface-syntax decisions:

| AST concept | Leo 4.0.2 surface output |
|---|---|
| `Program` | `program id.aleo { ... }` |
| `Mapping` | `mapping name: key => value;` |
| `Constructor` with `@noupgrade` | `@noupgrade constructor() {}` |
| `Function.entryPoint` | `fn name(...) -> Final { ... }` |
| `AsyncExpression` | `final { ... }` (downgraded from `async { }`) |
| `FutureType` | `Final` (downgraded from `Final<Fn(...)>`) |
| `Expression.call "Mapping::set" [...]` | `Mapping::set(count, 0u64, value);` |
| `Expression.call "Mapping::get_or_use" [...]` | `Mapping::get_or_use(count, 0u64, 0u64)` |
| `Statement.definition` | `let name: type = value;` |
| `Statement.returnSt` | `return expr;` |
| `Statement.block` | `{ ... }` with 4-space indentation |

For AST nodes that are defined but not yet supported, the printer returns `EmitError.unsupportedNode` with a descriptive message.

---

## 5. File Changes

### 5.1 New Files

| File | Responsibility |
|---|---|
| `ProofForge/Compiler/Leo.lean` | Public re-export of the Leo compiler namespace. |
| `ProofForge/Compiler/Leo/AST.lean` | Root AST re-exports. |
| `ProofForge/Compiler/Leo/AST/Core.lean` | Core identifiers, annotations, modes. |
| `ProofForge/Compiler/Leo/AST/Type.lean` | Type system AST. |
| `ProofForge/Compiler/Leo/AST/Literal.lean` | Literal AST. |
| `ProofForge/Compiler/Leo/AST/Expression.lean` | Expression AST. |
| `ProofForge/Compiler/Leo/AST/Statement.lean` | Statement and block AST. |
| `ProofForge/Compiler/Leo/AST/Function.lean` | Function, input, output, variant AST. |
| `ProofForge/Compiler/Leo/AST/Composite.lean` | Struct/record AST. |
| `ProofForge/Compiler/Leo/AST/Mapping.lean` | Mapping declaration AST. |
| `ProofForge/Compiler/Leo/AST/Storage.lean` | Storage variable AST. |
| `ProofForge/Compiler/Leo/AST/Program.lean` | Program, program scope, import, constructor AST. |
| `ProofForge/Compiler/Leo/Printer.lean` | AST pretty-printer. |
| `ProofForge/Compiler/Leo/Emit.lean` | IR → Leo AST lowering. |

### 5.2 Modified Files

| File | Change |
|---|---|
| `ProofForge/Backend/Aleo/IR.lean` | Replace string emission with `Emit.emitModule` followed by `Printer.printProgram`. Keep `renderModule` as a convenience alias. |
| `ProofForge/Backend/Aleo.lean` | Ensure it still re-exports the backend. |
| `ProofForge/Cli.lean` | No user-visible change; `--emit-counter-ir-leo` continues to call the backend. |
| `docs/superpowers/specs/2026-07-01-aleo-leo-design.md` | Update Section 5.2 architecture diagram and Section 6 lowering rules to reference the AST pipeline. |
| `docs/zh/superpowers/specs/2026-07-01-aleo-leo-design.zh.md` | Same updates in Chinese. |

### 5.3 Unchanged Files

| File | Reason |
|---|---|
| `Examples/Backend/Aleo/Counter.golden.leo` | Printer output must remain identical. |
| `scripts/aleo/counter-smoke.sh` | Smoke command and acceptance criteria do not change. |
| `ProofForge/IR/Contract.lean` | IR is the input; not modified. |
| `ProofForge/Target/Capability.lean`, `ProofForge/Target/Registry.lean` | Still out of scope. |

---

## 6. Acceptance Criteria

1. `lake build` succeeds.
2. `proof-forge --emit-counter-ir-leo` still emits output byte-for-byte equal to `Examples/Backend/Aleo/Counter.golden.leo`.
3. `./scripts/aleo/counter-smoke.sh` passes (`leo build`, `leo test`, artifact metadata validation).
4. The new AST modules compile and expose a `Program` type, a `Printer.printProgram : Program → Except EmitError String`, and an `Emit.emitModule : IR.Module → Except EmitError Program`.
5. Every AST node that is not yet supported by the printer has an explicit `unsupportedNode` error path rather than crashing or silently omitting output.

---

## 7. Non-Goals

- Do not implement a full round-trip parser; the AST is source-generation only.
- Do not port `leo_ast` serialization (`Serialize`/`Deserialize`) or `Display` impls.
- Do not extend Counter lowering to records, interfaces, consts, generics, or imports in this refactor.
- Do not change the target registry or capability definitions.
- Do not upgrade the local `leo` CLI to 4.3.2; the printer remains 4.0.2 compatible.

---

## 8. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| AST definitions become large | Medium | Split into the listed submodules; only define types, no logic. |
| Printer drifts from `leo_ast` semantics | Medium | Document every downgrade decision (async→final, FutureType→Final) and validate with smoke. |
| Counter output changes accidentally | High | Keep `Counter.golden.leo` as the regression test; diff before `leo build`. |
| Unsupported nodes silently produce invalid Leo | Medium | Require all printer branches to return `Except EmitError String`. |

---

## 9. Future Work

After this refactor lands:

1. Incrementally fill printer branches for record, interface, const, and storage-variable nodes.
2. Extend `Emit` to handle additional portable IR effects (`storageMap*`, `contextRead`, etc.) once their Aleo capabilities are defined.
3. When the local toolchain is upgraded to Leo 4.3.x, remove the `async→final` and `FutureType→Final` downgrades and emit official 4.3 syntax directly.
4. Consider a lossless formatter, but only if round-trip tests become a requirement.
