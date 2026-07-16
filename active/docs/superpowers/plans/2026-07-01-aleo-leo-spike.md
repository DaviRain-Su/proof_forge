# Aleo Leo Road 1 Spike Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the first `aleo-leo` sourcegen spike: lower the existing portable IR `Counter` module to a Leo package, validate it with `leo build` and `leo test`, and emit `proof-forge-artifact.json`.

**Architecture:** Add a Lean source-generation backend `ProofForge.Backend.Aleo.IR` that mirrors the Psy DPN backend structure. Extend the CLI with `--emit-counter-ir-leo`. Add shell/Python scripts to wrap `leo build`/`leo test`, generate a Leo package layout, and write/validate artifact metadata. Keep the Spike minimal: public mapping Counter only, no code registry changes.

**Tech Stack:** Lean 4, Python 3, Bash, Aleo `leo` CLI.

---

## Task 1: Scaffold `ProofForge.Backend.Aleo.IR`

**Files:**
- Create: `ProofForge/Backend/Aleo.lean`
- Create: `ProofForge/Backend/Aleo/IR.lean`
- Modify: `ProofForge/Backend.lean`

- [ ] **Step 1: Create `ProofForge/Backend/Aleo.lean` as public export**

```lean
import ProofForge.Backend.Aleo.IR

namespace ProofForge.Backend.Aleo
```

- [ ] **Step 2: Create `ProofForge/Backend/Aleo/IR.lean` skeleton**

```lean
import Init.Data.Array.Basic
import Init.Data.String.Basic
import ProofForge.IR.Contract
import ProofForge.Target.Check
import ProofForge.Target.Registry

namespace ProofForge.Backend.Aleo.IR

open ProofForge.IR
open ProofForge.Target

structure LowerError where
  message : String
  deriving Repr, Inhabited

def LowerError.render (err : LowerError) : String :=
  err.message

def capabilityError (err : CapabilityError) : LowerError := {
  message := err.render
}

def indent (level : Nat) (line : String) : String :=
  String.ofList (List.replicate (level * 4) ' ') ++ line

def lines (xs : Array String) : String :=
  String.intercalate "\n" xs.toList

def renderModule (module : Module) : Except LowerError String :=
  .error { message := "not implemented" }

end ProofForge.Backend.Aleo.IR
```

- [ ] **Step 3: Modify `ProofForge/Backend.lean` to export Aleo backend**

Add `public import ProofForge.Backend.Aleo` alongside existing Evm/Psy imports.

- [ ] **Step 4: Run `lake build` to confirm scaffolding compiles**

Run: `lake build`
Expected: PASS (backend module is empty but compiles).

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/Aleo.lean ProofForge/Backend/Aleo/IR.lean ProofForge/Backend.lean
git commit -m "feat(aleo): scaffold ProofForge.Backend.Aleo.IR module"
```

---

## Task 2: Implement Counter IR → Leo Lowering

**Files:**
- Modify: `ProofForge/Backend/Aleo/IR.lean`

- [ ] **Step 1: Add type rendering helpers**

```lean
def valueTypeName : ValueType → Except LowerError String
  | .unit => .error { message := "Aleo IR v0 does not support Unit as a value type" }
  | .bool => .ok "bool"
  | .u32 => .ok "u32"
  | .u64 => .ok "u64"
  | .hash => .error { message := "Aleo IR v0 does not support Hash" }
  | .fixedArray _ _ => .error { message := "Aleo IR v0 does not support fixed arrays" }
  | .structType _ => .error { message := "Aleo IR v0 does not support structs" }
```

- [ ] **Step 2: Add literal rendering**

```lean
def literal : Literal → String
  | .u32 value => s!"{value}u32"
  | .u64 value => s!"{value}u64"
  | .bool true => "true"
  | .bool false => "false"
  | .hash4 _ _ _ _ => ""
```

- [ ] **Step 3: Add expression rendering for the Counter subset**

Implement `expr` partial function supporting:
- `Expr.literal`
- `Expr.local`
- `Expr.add`
- `Expr.effect` (only `storageScalarRead`)

Reject everything else with `LowerError`.

- [ ] **Step 4: Add statement rendering for the Counter subset**

Implement `statement` supporting:
- `Statement.letBind`
- `Statement.effect` (only `storageScalarWrite`)
- `Statement.return`

- [ ] **Step 5: Add module rendering for Counter**

Generate:

```leo
program counter.aleo {
    mapping count: u64 => u64;

    transition initialize(public value: u64) -> u64 {
        return value;
    }
    final initialize(public value: u64) {
        Mapping::set(count, value);
    }

    transition increment() -> u64 {
        return 1u64;
    }
    final increment() {
        let current: u64 = Mapping::get_or_use(count, 0u64);
        Mapping::set(count, current + 1u64);
    }

    transition get() -> public u64 {
        return Mapping::get_or_use(count, 0u64);
    }
}
```

- [ ] **Step 6: Add a unit test or quick render check**

Create a temporary Lake script or use `#eval` to render `ProofForge.IR.Examples.Counter.module`.

Run: `lake build`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add ProofForge/Backend/Aleo/IR.lean
git commit -m "feat(aleo): implement Counter IR to Leo lowering"
```

---

## Task 3: Add `--emit-counter-ir-leo` CLI Mode

**Files:**
- Modify: `ProofForge/Cli.lean`
- Modify: `ProofForge.lean`

- [ ] **Step 1: Add emit mode variant**

```lean
| counterIrLeo
```

- [ ] **Step 2: Add usage line**

```text
proof-forge --emit-counter-ir-leo [-o output.leo]
```

- [ ] **Step 3: Add argument parser branch**

```lean
| "--emit-counter-ir-leo" :: rest, opts =>
    parseArgs rest { opts with mode := .counterIrLeo }
```

- [ ] **Step 4: Add implementation function**

```lean
def compileCounterIrLeo (opts : CliOptions) : IO UInt32 := do
  let output := opts.output?.getD (FilePath.mk "build/aleo/Counter.leo")
  match ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module with
  | .ok leo =>
      writeTextFile output leo
      IO.println s!"wrote {output}"
      return 0
  | .error err =>
      throw <| IO.userError err.render
```

- [ ] **Step 5: Wire into main dispatch**

Add `| .counterIrLeo => compileCounterIrLeo opts` in the mode dispatch.

- [ ] **Step 6: Export Aleo backend from `ProofForge.lean`**

Add `public import ProofForge.Backend.Aleo` if not already present.

- [ ] **Step 7: Build and test CLI**

Run:
```bash
lake build
./.lake/build/bin/proof-forge --emit-counter-ir-leo -o build/aleo/Counter.leo
```

Expected: `build/aleo/Counter.leo` is created and contains Leo source.

- [ ] **Step 8: Commit**

```bash
git add ProofForge/Cli.lean ProofForge.lean
git commit -m "feat(cli): add --emit-counter-ir-leo mode"
```

---

## Task 4: Generate and Check `Examples/Backend/Aleo/Counter.golden.leo`

**Files:**
- Create: `Examples/Backend/Aleo/Counter.golden.leo`
- Create: `Examples/Backend/Aleo/README.md`

- [ ] **Step 1: Generate Leo output**

Run:
```bash
./.lake/build/bin/proof-forge --emit-counter-ir-leo -o build/aleo/Counter.leo
```

- [ ] **Step 2: Inspect output and fix any Leo syntax issues**

Compare against the design spec. Adjust lowering rules if `leo build` later rejects the shape.

- [ ] **Step 3: Copy to golden fixture**

```bash
mkdir -p Examples/Backend/Aleo
cp build/aleo/Counter.leo Examples/Backend/Aleo/Counter.golden.leo
```

- [ ] **Step 4: Create `Examples/Backend/Aleo/README.md`**

Explain that `Counter.golden.leo` is the expected output of `proof-forge --emit-counter-ir-leo`.

- [ ] **Step 5: Commit**

```bash
git add Examples/Backend/Aleo/Counter.golden.leo Examples/Backend/Aleo/README.md
git commit -m "feat(aleo): add Counter Leo golden fixture"
```

---

## Task 5: Create Aleo Smoke Scripts

**Files:**
- Create: `scripts/aleo/write-leo-package.py`
- Create: `scripts/aleo/write-artifact-metadata.py`
- Create: `scripts/aleo/validate-artifact-metadata.py`
- Create: `scripts/aleo/counter-smoke.sh`

- [ ] **Step 1: Create `scripts/aleo/write-leo-package.py`**

Responsibilities:
- Accept `--project-dir`, `--source`, `--program-name`.
- Remove and recreate project dir under `build/aleo/counter`.
- Copy source to `src/main.leo`.
- Write `leo.toml` with `[package]` section.

- [ ] **Step 2: Create `scripts/aleo/write-artifact-metadata.py`**

Responsibilities:
- Accept `--root`, `--fixture`, `--source`, `--leo-project`, `--out`, `--leo`.
- Compute SHA-256 and byte sizes for source and build outputs.
- Write `proof-forge-artifact.json` per design spec schema.

- [ ] **Step 3: Create `scripts/aleo/validate-artifact-metadata.py`**

Responsibilities:
- Validate JSON schema version and required fields.
- Check artifact paths exist and are non-empty.
- Check `validation.leoBuild` and `validation.leoTest` are `"passed"`.

- [ ] **Step 4: Create `scripts/aleo/counter-smoke.sh`**

Mirror the design spec flow:
- `lake build proof-forge`
- `proof-forge --emit-counter-ir-leo`
- `diff` against golden fixture
- `write-leo-package.py`
- `leo build`
- `leo test`
- `write-artifact-metadata.py`
- `validate-artifact-metadata.py`

Exit `127` with clear message if `leo` is missing.

- [ ] **Step 5: Make scripts executable**

```bash
chmod +x scripts/aleo/counter-smoke.sh
```

- [ ] **Step 6: Commit**

```bash
git add scripts/aleo/
git commit -m "feat(aleo): add counter smoke scripts and metadata writers"
```

---

## Task 6: Validate Smoke End-to-End

**Files:**
- All files created/modified above

- [ ] **Step 1: Install or verify `leo` CLI**

Ensure `leo` is on PATH. If not, document blocker and skip `leo build`/`leo test` portions.

- [ ] **Step 2: Run smoke script**

```bash
./scripts/aleo/counter-smoke.sh
```

Expected: PASS, writes `build/aleo/counter/proof-forge-artifact.json`.

- [ ] **Step 3: Fix any Leo syntax or lowering issues**

Iterate on `ProofForge.Backend.Aleo/IR.lean` until `leo build` and `leo test` succeed.

- [ ] **Step 4: Run `lake build` to ensure Lean package still compiles**

Run: `lake build`
Expected: PASS.

- [ ] **Step 5: Commit fixes**

```bash
git add -A
git commit -m "fix(aleo): adjust lowering for leo build/test compatibility"
```

---

## Task 7: Update Documentation to Reflect Implemented Spike

**Files:**
- Modify: `docs/targets/aleo-leo.md`
- Modify: `docs/zh/targets/aleo-leo.zh.md`
- Modify: `docs/validation-gates.md`
- Modify: `docs/zh/validation-gates.zh.md`

- [ ] **Step 1: Move Aleo target status from Research to Spike**

Update status line in both EN/ZH target notes to: **Spike (local smoke exists)**.

- [ ] **Step 2: Document the runnable smoke command**

Add a "Local Smoke" section pointing to `scripts/aleo/counter-smoke.sh`.

- [ ] **Step 3: Move Aleo smoke from Planned to Current gates**

In `docs/validation-gates.md` and `.zh.md`, move the Aleo gate from "Planned" to "Current gates".

- [ ] **Step 4: Commit**

```bash
git add docs/targets/aleo-leo.md docs/zh/targets/aleo-leo.zh.md docs/validation-gates.md docs/zh/validation-gates.zh.md
git commit -m "docs(aleo): mark Road 1 spike as implemented with local smoke"
```

---

## Task 8: Final Verification and Commit

- [ ] **Step 1: Run full verification sequence**

```bash
lake build
./scripts/aleo/counter-smoke.sh
```

- [ ] **Step 2: Review git log**

```bash
git log --oneline -10
```

- [ ] **Step 3: Final commit if any uncommitted changes**

```bash
git add -A
git commit -m "feat(aleo): complete Road 1 Leo sourcegen spike"
```

---

## Spec Coverage Check

| Spec section | Implementing task |
|---|---|
| Target family `zk-app-sourcegen` | Task 1 (module naming), docs updates |
| Canonical capabilities | Task 2 (reject unsupported IR), docs updates |
| Artifact manifest schema | Task 5 (`write-artifact-metadata.py`) |
| Toolchain decision (`leo build`/`leo test`) | Task 5, Task 6 |
| IR → Leo lowering rules | Task 2 |
| CLI `--emit-counter-ir-leo` | Task 3 |
| Smoke test flow | Task 4, Task 5, Task 6 |
| Non-goals (no registry changes) | Noted in commits and docs |

## Red Flag Check

- No TBD/TODO placeholders.
- Every task produces testable output.
- Exact file paths are specified.
- Exact commands with expected output are specified.
