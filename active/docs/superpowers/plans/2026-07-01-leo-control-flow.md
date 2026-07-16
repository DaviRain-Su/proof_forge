# Leo Control Flow and Pure-Function Entrypoints Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the Aleo Leo backend so that pure entrypoints can accept parameters and return values, and portable IR control-flow/assignment statements (`assert`, `ifElse`, `boundedFor`, `assign`, `assignOp`) lower correctly. Add a `PureMath` example with its own smoke test.

**Architecture:** Keep the AST unchanged; extend `ProofForge.Compiler.Leo.Printer` for clean control-flow output and `ProofForge.Compiler.Leo.Emit` with side-effect detection, pure-entrypoint lowering, and new statement handlers. Add a `ProofForge.IR.Examples.PureMath` module, a CLI mode, a golden fixture, and a smoke script.

**Tech Stack:** Lean 4 (`lake`), Leo 4.0.2 CLI, existing `ProofForge.IR.Contract`.

---

## File map

| File | Responsibility |
|---|---|
| `ProofForge/Compiler/Leo/Printer.lean` | Refine `assert`, `conditional`, `iteration`, `assign` printing. |
| `ProofForge/Compiler/Leo/Emit.lean` | Side-effect detection, pure entrypoint lowering, control-flow/assignment statement handlers. |
| `ProofForge/IR/Examples/PureMath.lean` | New IR example with pure functions. |
| `Examples/Backend/Aleo/PureMath.golden.leo` | Expected Leo source for the new example. |
| `ProofForge/Cli.lean` | Add `pureMathIrLeo` mode and handler. |
| `scripts/aleo/pure-math-smoke.sh` | End-to-end smoke test for PureMath. |
| `docs/targets/aleo-leo.md`, `docs/validation-gates.md` and Chinese versions | Document the new smoke gate. |

---

## Task 1: Refine printer for control flow and assignment

**Files:**
- Modify: `ProofForge/Compiler/Leo/Printer.lean`

- [ ] **Step 1: Update `assert` printing to ignore the message**

Replace the existing `.assert` branch in `printStatement` with:

```lean
    | .assert cond _ => do
        let c ← printExpression cond
        .ok (indent indentLevel s!"assert({c});")
```

- [ ] **Step 2: Update `conditional` printing for clean `if` / `else` blocks**

Replace the existing `.conditional` branch with:

```lean
    | .conditional cond thenBranch elseBranch? => do
        let c ← printExpression cond
        let t ← printBlock indentLevel thenBranch
        match elseBranch? with
        | none => .ok (indent indentLevel ("if " ++ c ++ " " ++ t))
        | some elseSt => do
            let e ← printStatement indentLevel elseSt
            .ok (indent indentLevel ("if " ++ c ++ " " ++ t ++ " else " ++ e))
```

- [ ] **Step 3: Update `iteration` printing for `u64` bounds**

Replace the existing `.iteration` branch with:

```lean
    | .iteration var ty? start stop inclusive body => do
        let lo ← printExpression start
        let hi ← printExpression stop
        let range := if inclusive then s!"{lo}..={hi}" else s!"{lo}..{hi}"
        let tyStr ← match ty? with | some t => do let s ← printType t; .ok (": " ++ s) | none => .ok ""
        let b ← printBlock indentLevel body
        .ok (indent indentLevel ("for " ++ var ++ tyStr ++ " in " ++ range ++ " " ++ b))
```

- [ ] **Step 4: Verify the printer compiles**

Run: `lake build ProofForge.Compiler.Leo.Printer`

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Compiler/Leo/Printer.lean
git commit -m "refactor(leo-ast): clean up control-flow and assert printing"
```

---

## Task 2: Add side-effect detection and pure entrypoint lowering to Emit

**Files:**
- Modify: `ProofForge/Compiler/Leo/Emit.lean`

- [ ] **Step 1: Add `hasEffect` helper**

Insert after the `mutual` block:

```lean
def hasEffect (body : Array IR.Statement) : Bool :=
  body.any hasEffectStmt
where
  hasEffectExpr : Expr → Bool
    | .effect _ => true
    | .add lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .sub lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .mul lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .div lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .mod lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .pow lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .bitAnd lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .bitOr lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .bitXor lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .shiftLeft lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .shiftRight lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .cast v _ => hasEffectExpr v
    | .eq lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .ne lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .lt lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .le lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .gt lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .ge lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .boolAnd lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .boolOr lhs rhs => hasEffectExpr lhs || hasEffectExpr rhs
    | .boolNot v => hasEffectExpr v
    | .arrayLit _ vs => vs.any hasEffectExpr
    | .arrayGet a i => hasEffectExpr a || hasEffectExpr i
    | .structLit _ fs => fs.any (fun (_, e) => hasEffectExpr e)
    | .field b _ => hasEffectExpr b
    | .hashValue a b c d => hasEffectExpr a || hasEffectExpr b || hasEffectExpr c || hasEffectExpr d
    | .hash v => hasEffectExpr v
    | .hashTwoToOne l r => hasEffectExpr l || hasEffectExpr r
    | .crosscallInvoke t m args => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallInvokeTyped t m args _ => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallInvokeValueTyped t m cv args _ => hasEffectExpr t || hasEffectExpr m || hasEffectExpr cv || args.any hasEffectExpr
    | .crosscallInvokeStaticTyped t m args _ => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallInvokeDelegateTyped t m args _ => hasEffectExpr t || hasEffectExpr m || args.any hasEffectExpr
    | .crosscallCreate cv _ => hasEffectExpr cv
    | .crosscallCreate2 cv s _ => hasEffectExpr cv || hasEffectExpr s
    | _ => false

  hasEffectStmt : IR.Statement → Bool
    | .effect _ => true
    | .letBind _ _ v => hasEffectExpr v
    | .letMutBind _ _ v => hasEffectExpr v
    | .assign t v => hasEffectExpr t || hasEffectExpr v
    | .assignOp t _ v => hasEffectExpr t || hasEffectExpr v
    | .assert c _ => hasEffectExpr c
    | .assertEq l r _ => hasEffectExpr l || hasEffectExpr r
    | .ifElse c thenBody elseBody => hasEffectExpr c || hasEffect thenBody || hasEffect elseBody
    | .boundedFor _ _ _ body => hasEffect body
    | .return v => hasEffectExpr v
```

- [ ] **Step 2: Add helper to build a function input**

Insert before `entrypointFunction`:

```lean
def makeInput (name : String) (ty : ValueType) : Except AST.LowerError Input := do
  .ok { name := name, ty := ← valueType ty, mode := .public_ }
```

- [ ] **Step 3: Generalize `entrypointFunction`**

Replace the existing `entrypointFunction` with:

```lean
def entrypointFunction (ep : Entrypoint) : Except AST.LowerError Function := do
  if hasEffect ep.body then
    -- Stateful entrypoint: must return unit and have no params for now.
    if ep.returns != .unit then
      .error { message := s!"Stateful Aleo entrypoint `{ep.name}` must return Unit" }
    else if !ep.params.isEmpty then
      .error { message := s!"Stateful Aleo entrypoint `{ep.name}` cannot have parameters yet" }
    else if ep.name == "initialize" then
      let setCall := Expression.call ⟨#["Mapping", "set"], #[], #[.identifier "count", .literal (.integer .u64 0), .literal (.integer .u64 0)]⟩
      let asyncBlock : Block := { statements := #[.expression setCall] }
      .ok {
        annotations := #[]
        variant := .entryPoint
        identifier := "initialize"
        constParameters := #[]
        input := #[]
        output := #[]
        outputType := futureUnit
        block := { statements := #[.returnSt (some (.async asyncBlock))] }
      }
    else if ep.name == "get" then
      let readCall := Expression.call ⟨#["Mapping", "get_or_use"], #[], #[.identifier "count", .literal (.integer .u64 0), .literal (.integer .u64 0)]⟩
      let asyncBlock : Block := { statements := #[.definition (.single "n") (some (.integer .u64)) readCall] }
      .ok {
        annotations := #[]
        variant := .entryPoint
        identifier := "get"
        constParameters := #[]
        input := #[]
        output := #[]
        outputType := futureUnit
        block := { statements := #[.returnSt (some (.async asyncBlock))] }
      }
    else if ep.name == "increment" then
      let bodyStmts ← statements ep.body
      let asyncBlock : Block := { statements := bodyStmts }
      .ok {
        annotations := #[]
        variant := .entryPoint
        identifier := "increment"
        constParameters := #[]
        input := #[]
        output := #[]
        outputType := futureUnit
        block := { statements := #[.returnSt (some (.async asyncBlock))] }
      }
    else
      .error { message := s!"Aleo IR v0 does not support stateful entrypoint `{ep.name}`" }
  else
    -- Pure entrypoint: support params and return values directly.
    let inputs ← ep.params.mapM (fun (n, t) => makeInput n t)
    let ret ← valueType ep.returns
    let bodyStmts ← statements ep.body
    .ok {
      annotations := #[]
      variant := .entryPoint
      identifier := ep.name
      constParameters := #[]
      input := inputs
      output := #[]
      outputType := ret
      block := { statements := bodyStmts }
    }
```

- [ ] **Step 4: Verify Emit compiles**

Run: `lake build ProofForge.Compiler.Leo.Emit`

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Compiler/Leo/Emit.lean
git commit -m "feat(leo-emit): add side-effect detection and pure entrypoint lowering"
```

---

## Task 3: Add control-flow and assignment statement handlers

**Files:**
- Modify: `ProofForge/Compiler/Leo/Emit.lean`

- [ ] **Step 1: Add `assignOp` desugaring helper**

Insert inside the `Emit` namespace:

```lean
def assignOpToBinary : AssignOp → BinaryOperation
  | .add => .add
  | .sub => .sub
  | .mul => .mul
  | .div => .div
  | .mod => .mod
  | .bitAnd => .bitwiseAnd
  | .bitOr => .bitwiseOr
  | .bitXor => .xor
  | .shiftLeft => .shl
  | .shiftRight => .shr
```

- [ ] **Step 2: Extend `Emit.statement` with new branches**

Add these branches to `statement` inside the `mutual` block:

```lean
    | .assert cond _ => do
        let c ← expr cond
        .ok #[.assert c none]
    | .ifElse cond thenBody elseBody => do
        let c ← expr cond
        let thenStmts ← statements thenBody
        let elseStmts ← statements elseBody
        .ok #[.conditional c { statements := thenStmts } (some (.block { statements := elseStmts }))]
    | .boundedFor name start stop body => do
        let bodyStmts ← statements body
        .ok #[.iteration name (some (.integer .u64)) (.literal (.integer .u64 start)) (.literal (.integer .u64 stop)) false { statements := bodyStmts }]
    | .assign (.local name) value => do
        let v ← expr value
        .ok #[.assign (.identifier name) v]
    | .assign target _ =>
        .error { message := s!"Leo emitter only supports assignment to locals, got {repr target}" }
    | .assignOp (.local name) op value => do
        let v ← expr value
        let lhs := Expression.identifier name
        .ok #[.assign lhs (.binary ⟨assignOpToBinary op, lhs, v⟩)]
    | .assignOp target _ _ =>
        .error { message := s!"Leo emitter only supports assign-op on locals, got {repr target}" }
```

- [ ] **Step 3: Verify Emit compiles**

Run: `lake build ProofForge.Compiler.Leo.Emit`

Expected: build succeeds.

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Compiler/Leo/Emit.lean
git commit -m "feat(leo-emit): lower assert, ifElse, boundedFor, assign and assignOp"
```

---

## Task 4: Create the PureMath IR example

**Files:**
- Create: `ProofForge/IR/Examples/PureMath.lean`

- [ ] **Step 1: Write the module**

```lean
import ProofForge.IR.Contract

namespace ProofForge.IR.Examples.PureMath

open ProofForge.IR

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

end ProofForge.IR.Examples.PureMath
```

- [ ] **Step 2: Verify it compiles**

Run: `lake build ProofForge.IR.Examples.PureMath`

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/IR/Examples/PureMath.lean
git commit -m "feat(ir): add PureMath example for Leo control flow"
```

---

## Task 5: Add CLI mode for PureMath Leo emission

**Files:**
- Modify: `ProofForge/Cli.lean`

- [ ] **Step 1: Add the mode variant**

In the `EmitMode` inductive, add `| pureMathIrLeo` next to `| counterIrLeo`.

- [ ] **Step 2: Add argument parsing**

Find the branch that parses `--emit-counter-ir-leo` and add an analogous branch:

```lean
    | "--emit-pure-math-ir-leo" :: rest =>
        parseArgs rest { opts with mode := .pureMathIrLeo }
```

- [ ] **Step 3: Add the compile function**

Insert before `compileEvmBytecode`:

```lean
def compilePureMathIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/PureMath.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.PureMath.module with
  | .ok source =>
      writeTextFile output source
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render
```

- [ ] **Step 4: Wire the mode to the function**

In `compileFile`, add:

```lean
  | .pureMathIrLeo => compilePureMathIrLeo opts
```

- [ ] **Step 5: Import the new example**

Add near the existing Counter import:

```lean
import ProofForge.IR.Examples.PureMath
```

- [ ] **Step 6: Verify the CLI compiles**

Run: `lake build proof-forge`

Expected: build succeeds.

- [ ] **Step 7: Commit**

```bash
git add ProofForge/Cli.lean
git commit -m "feat(cli): add --emit-pure-math-ir-leo mode"
```

---

## Task 6: Create golden fixture and smoke script

**Files:**
- Create: `Examples/Backend/Aleo/PureMath.golden.leo`
- Create: `scripts/aleo/pure-math-smoke.sh`

- [ ] **Step 1: Generate the fixture**

Run: `lake exe proof-forge --emit-pure-math-ir-leo --output Examples/Backend/Aleo/PureMath.golden.leo`

Then inspect and adjust whitespace if needed so it matches the printer output exactly.

Expected content:

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

- [ ] **Step 2: Write the smoke script**

Create `scripts/aleo/pure-math-smoke.sh`:

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/../.."

BUILD_DIR="build/aleo/pure-math"
GOLDEN="Examples/Backend/Aleo/PureMath.golden.leo"

echo "[Aleo PureMath] Emitting Leo source..."
mkdir -p build/aleo
lake exe proof-forge --emit-pure-math-ir-leo --output "${BUILD_DIR}.leo"

echo "[Aleo PureMath] Diffing against golden fixture..."
diff -u "${GOLDEN}" "${BUILD_DIR}.leo"

echo "[Aleo PureMath] Writing Leo package..."
python3 scripts/aleo/write-leo-package.py "${BUILD_DIR}.leo" "${BUILD_DIR}/package"

echo "[Aleo PureMath] Running leo build..."
(cd "${BUILD_DIR}/package" && leo build)

echo "[Aleo PureMath] Running leo test..."
(cd "${BUILD_DIR}/package" && leo test)

echo "[Aleo PureMath] Writing artifact metadata..."
python3 scripts/aleo/write-artifact-metadata.py \
  --source "${BUILD_DIR}.leo" \
  --package "${BUILD_DIR}/package" \
  --program-id "pure_math.aleo" \
  --output "${BUILD_DIR}/proof-forge-artifact.json"

echo "[Aleo PureMath] Validating artifact metadata..."
python3 scripts/aleo/validate-artifact-metadata.py "${BUILD_DIR}/proof-forge-artifact.json"

echo "[Aleo PureMath] Smoke passed."
```

Make it executable:

```bash
chmod +x scripts/aleo/pure-math-smoke.sh
```

- [ ] **Step 3: Run the smoke script**

Run: `./scripts/aleo/pure-math-smoke.sh`

Expected: diff passes, `leo build` succeeds, `leo test` passes, metadata validates.

- [ ] **Step 4: Commit**

```bash
git add Examples/Backend/Aleo/PureMath.golden.leo scripts/aleo/pure-math-smoke.sh
git commit -m "test(aleo): add PureMath golden fixture and smoke script"
```

---

## Task 7: Update documentation and validation gates

**Files:**
- Modify: `docs/targets/aleo-leo.md`
- Modify: `docs/validation-gates.md`
- Modify: `docs/zh/targets/aleo-leo.zh.md`
- Modify: `docs/zh/validation-gates.zh.md`

- [ ] **Step 1: Update English target doc**

In `docs/targets/aleo-leo.md`, add a bullet under "Road 1 spike" describing the PureMath smoke script:

```markdown
- `scripts/aleo/pure-math-smoke.sh` proves that pure, parameter-bearing entrypoints and control-flow statements (`assert`, `if/else`, `for`, assignment) lower correctly.
```

- [ ] **Step 2: Update English validation gates**

In `docs/validation-gates.md`, add a row:

```markdown
| Aleo PureMath IR smoke | `scripts/aleo/pure-math-smoke.sh` | `leo` CLI (4.0.2 tested) on `PATH`; `python3`; Lean toolchain from `lean-toolchain` | Portable IR pure functions with params, `if/else`, `boundedFor`, `assign`, and `assert` lower to valid Leo 4.0 source, match `Examples/Backend/Aleo/PureMath.golden.leo`, and pass `leo build`/`leo test` | Stateful parameterized entrypoints, non-local assignment targets, dynamic loop bounds |
```

- [ ] **Step 3: Update Chinese docs**

Apply equivalent changes to `docs/zh/targets/aleo-leo.zh.md` and `docs/zh/validation-gates.zh.md`.

- [ ] **Step 4: Commit**

```bash
git add docs/targets/aleo-leo.md docs/validation-gates.md docs/zh/targets/aleo-leo.zh.md docs/zh/validation-gates.zh.md
git commit -m "docs(aleo): document PureMath smoke gate"
```

---

## Task 8: Final verification

**Files:**
- Test: `lake build`, `./scripts/aleo/counter-smoke.sh`, `./scripts/aleo/pure-math-smoke.sh`

- [ ] **Step 1: Full build**

Run: `lake build`

Expected: `Build completed successfully`.

- [ ] **Step 2: Counter regression**

Run: `./scripts/aleo/counter-smoke.sh`

Expected: passes.

- [ ] **Step 3: PureMath smoke**

Run: `./scripts/aleo/pure-math-smoke.sh`

Expected: passes.

- [ ] **Step 4: Commit (if all pass)**

```bash
git commit --allow-empty -m "test(aleo): verify Counter and PureMath smokes pass"
```

---

## Plan self-review

### Spec coverage
- Section 3.1 assert → Task 1, Step 1.
- Section 3.2 ifElse → Task 1, Step 2.
- Section 3.3 boundedFor → Task 1, Step 2 / Task 3, Step 2.
- Section 3.4 assign → Task 3, Step 2.
- Section 3.5 assignOp → Task 3, Steps 1–2.
- Section 4.2 pure entrypoints → Task 2.
- Section 5 PureMath example → Tasks 4–6.
- Section 7 docs → Task 7.
- Section 8 verification → Task 8.

### Placeholder scan
- No TBD/TODO.
- All code snippets include exact Lean syntax.
- All steps have exact commands and expected outputs.

### Type consistency
- `assignOpToBinary` maps `IR.AssignOp` to `AST.BinaryOperation` used in `.binary` constructor.
- `hasEffect` uses `IR.Statement` and `Expr` from `ProofForge.IR`.
- `entrypointFunction` returns `AST.Function` with `mode := .public_` (matches new `Mode` constructors).
