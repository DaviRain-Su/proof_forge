# Leo Control Flow and Pure-Function Entrypoints Design

**Date:** 2026-07-01  
**Status:** Historical Leo control-flow design record (archived 2026-07-12).
**Scope:** Extend the Aleo Leo backend to support entrypoint parameters/return values for pure functions and the portable IR control-flow/assignment statements (`assert`, `ifElse`, `boundedFor`, `assign`, `assignOp`).  
**Related docs:**
- [Leo AST mirror design](./2026-07-01-leo-ast-mirror-design.md)
- [Aleo Leo spike design](./2026-07-01-aleo-leo-design.md)

---

## 1. Goal

After the AST refactor, the Aleo backend only supports the Counter spike: unit-returning, parameter-less entrypoints with scalar state. This design extends lowering so that:

1. **Pure entrypoints** (no side effects) can accept parameters and return values.
2. **Control flow** (`assert`, `ifElse`, `boundedFor`) and **assignment** (`assign`, `assignOp`) lower correctly.
3. A new **PureMath** example demonstrates these features end-to-end with `leo build` and `leo test`.

The Counter example remains unchanged.

---

## 2. Executive Summary

We add two capabilities to `ProofForge.Compiler.Leo.Emit`:

- **Pure-function entrypoints:** When an entrypoint body contains no `Effect` nodes, emit a regular `fn name(...) -> T { ... }` with the parameter list and return type taken from the IR. The body is lowered directly without wrapping it in `async`/`final`.
- **Control-flow statements:** Extend the emitter and printer for `assert`, `ifElse`, `boundedFor`, `assign`, and `assignOp`.

A new `ProofForge.IR.Examples.PureMath` module defines pure functions (`add`, `max`, `sumTo`, `isEven`) and a new CLI mode `--emit-pure-math-ir-leo` plus smoke script `scripts/aleo/pure-math-smoke.sh` validate the output against a golden fixture.

---

## 3. AST / Printer Changes

The AST already contains the required nodes. Only the printer needs refinement for correct Leo 4.0.2 output.

### 3.1 `assert`

Portable IR: `Statement.assert condition message`

- Ignore the `message` string (Leo `assert` does not accept one).
- Print as `assert(condition);`.

### 3.2 `ifElse`

Portable IR: `Statement.ifElse cond thenBody elseBody`

- Print as:
  ```leo
  if <cond> {
      <thenBody>
  } else {
      <elseBody>
  }
  ```
- Both branches are blocks. The printer already has `printBlock`; we ensure the `else` branch is always printed as a block.

### 3.3 `boundedFor`

Portable IR: `Statement.boundedFor indexName start stopExclusive body`

- Print as:
  ```leo
  for <indexName>: u64 in <start>..<stopExclusive> {
      <body>
  }
  ```
- The loop bounds are `Nat` in the IR; emit them as `u64` literals.

### 3.4 `assign`

Portable IR: `Statement.assign target value`

- Supported targets: local variables (`.local`).
- Print as `target = value;`.
- Storage assignments continue to use the existing `effect` path.

### 3.5 `assignOp`

Portable IR: `Statement.assignOp target op value`

- Supported targets: local variables.
- Print as `target <op>= value;` where `<op>` is `+`, `-`, `*`, `/`, `%`, `&`, `|`, `^`, `<<`, or `>>`.

---

## 4. IR → AST Lowering Changes

### 4.1 Detecting Side Effects

Add a helper `hasEffect : Array Statement → Bool` that returns `true` if any statement (recursively into `ifElse`/`boundedFor`) contains an `.effect` constructor.

### 4.2 Pure Entrypoint Lowering

For an entrypoint whose body has no effects:

| IR field | Leo AST |
|---|---|
| `params` | `Function.input` array |
| `returns` | `Function.outputType` |
| body | `Function.block` directly (no `async`) |

The IR `return value` statement becomes a Leo `return value;`.

Validation:
- A pure entrypoint that declares a non-unit `returns` must contain a terminating `return` statement. The emitter trusts the IR; if it is missing, the generated Leo program will fail `leo build`.
- For now, pure entrypoints are not allowed to contain state effects. Attempting to lower a body with effects through the pure path is an error.

### 4.3 Stateful Entrypoint Lowering (Unchanged)

Entrypoints with effects continue to use the existing path:

- `outputType := Future<Fn(...)>` (printer downgrades to `Final`).
- Body is `{ return final { ... }; }`.
- Parameters are rejected for now; the emitter returns an error if a stateful entrypoint has params.

### 4.4 Statement Lowering

Extend `Emit.statement`:

| IR Statement | Leo Statement(s) |
|---|---|
| `.assert cond _` | `.assert (← expr cond) none` |
| `.ifElse cond then else` | `.conditional (← expr cond) (← block then) (some (.block (← block else)))` |
| `.boundedFor name start stop body` | `.iteration name (some .u64) (u64Lit start) (u64Lit stop) false (← block body)` |
| `.assign (.local name) value` | `.assign (.identifier name) (← expr value)` |
| `.assign target value` | error if target is not a local |
| `.assignOp (.local name) op value` | `.assign (.identifier name) (.binary opExpr (← expr value))` (desugar) OR emit compound assignment if printer supports it. |

For `.assignOp` we will **desugar** in the emitter: `total += x` becomes `total = total + x`. This avoids adding compound-assignment syntax to the AST and keeps the printer simple.

### 4.5 Expression Lowering (No New Nodes)

`add`, `sub`, `mul`, `div`, `mod`, `eq`, `ne`, `lt`, `le`, `gt`, `ge`, `boolAnd`, `boolOr`, `boolNot`, `cast`, literals, and locals are already supported.

---

## 5. New Example: PureMath

### 5.1 IR Definition

Create `ProofForge/IR/Examples/PureMath.lean`:

```lean
def add : Entrypoint := {
  name := "add"
  params := #[("a", .u64), ("b", .u64)]
  returns := .u64
  body := #[ .return (.add (.local "a") (.local "b")) ]
}

def max : Entrypoint := {
  name := "max"
  params := #[("a", .u64), ("b", .u64)]
  returns := .u64
  body := #[
    .ifElse (.gt (.local "a") (.local "b"))
      #[ .return (.local "a") ]
      #[ .return (.local "b") ]
  ]
}

def sumFirst10 : Entrypoint := {
  name := "sumFirst10"
  params := #[]
  returns := .u64
  body := #[
    .letBind "total" .u64 (.literal (.u64 0)),
    .boundedFor "i" 0 10 #[
      .assign (.local "total") (.add (.local "total") (.local "i"))
    ],
    .return (.local "total")
  ]
}

def isEven : Entrypoint := {
  name := "isEven"
  params := #[("n", .u64)]
  returns := .bool
  body := #[ .return (.eq (.mod (.local "n") (.literal (.u64 2))) (.literal (.u64 0))) ]
}

def module : Module := {
  name := "PureMath"
  state := #[]
  entrypoints := #[add, max, sumFirst10, isEven]
}
```

(The exact bound for `sumTo` will be `n` from params, not hard-coded 10; the design uses `n` as the upper bound.)

### 5.2 Expected Leo Output

```leo
program pure_math.aleo {
    fn add(a: u64, b: u64) -> u64 {
        return (a + b);
    }
    fn max(a: u64, b: u64) -> u64 {
        if (a > b) {
            return a;
        } else {
            return b;
        }
    }
    fn sumFirst10() -> u64 {
        let total: u64 = 0u64;
        for i: u64 in 0..10 {
            total = (total + i);
        }
        return total;
    }
    fn isEven(n: u64) -> bool {
        return ((n % 2u64) == 0u64);
    }
}
```

### 5.3 CLI Mode

Add `--emit-pure-math-ir-leo <dir>` to `ProofForge.Cli`, analogous to `--emit-counter-ir-leo`.

### 5.4 Smoke Script

Create `scripts/aleo/pure-math-smoke.sh`:

1. Run `lake exe proof-forge --emit-pure-math-ir-leo`.
2. Diff against `Examples/Backend/Aleo/PureMath.golden.leo`.
3. Use `scripts/aleo/write-leo-package.py` to create a Leo package.
4. Run `leo build` and `leo test`.
5. Validate artifact metadata.

---

## 6. Acceptance Criteria

1. `lake build` succeeds.
2. `proof-forge --emit-counter-ir-leo` still matches `Examples/Backend/Aleo/Counter.golden.leo`.
3. `proof-forge --emit-pure-math-ir-leo` matches `Examples/Backend/Aleo/PureMath.golden.leo`.
4. `./scripts/aleo/pure-math-smoke.sh` passes (`leo build`, `leo test`, metadata validation).
5. `./scripts/aleo/counter-smoke.sh` still passes.

---

## 7. Non-Goals

- Compound assignment syntax in the AST (we desugar in the emitter).
- Stateful entrypoints with parameters.
- Non-local assignment targets (mapping elements, struct fields).
- `for` loops with dynamic bounds or non-`u64` index types.
- `break`/`continue` (portable IR does not have them).
- `arrayLit`, `structLit`, `field` expressions.

---

## 8. File Changes

| File | Change |
|---|---|
| `ProofForge/Compiler/Leo/Printer.lean` | Refine `assert`, `conditional`, `iteration`, `assign` printing. |
| `ProofForge/Compiler/Leo/Emit.lean` | Add side-effect detection, pure entrypoint lowering, control-flow/assignment statement handlers. |
| `ProofForge/IR/Examples/PureMath.lean` | New IR example. |
| `Examples/Backend/Aleo/PureMath.golden.leo` | New golden fixture. |
| `ProofForge/Cli.lean` | Add `pureMathIrLeo` mode and handler. |
| `scripts/aleo/pure-math-smoke.sh` | New smoke script. |
| `docs/targets/aleo-leo.md` / `docs/zh/targets/aleo-leo.zh.md` | Mention PureMath smoke gate. |
| `docs/validation-gates.md` / `docs/zh/validation-gates.zh.md` | Add PureMath validation gate. |
