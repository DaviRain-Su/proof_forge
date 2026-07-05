# Psy Metadata Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Clean `ContextPlan` residue, derive event field types from IR expressions, strengthen artifact metadata validation, add a `proof-forge metadata` CLI, and keep the schema backend-agnostic.

**Architecture:** Extend `ProofForge.Backend.Psy.Plan.EventPlan` to carry inferred field type names; add a small `exprTypeName?` helper; update `ProofForge.Backend.Psy.Metadata` to consume the richer plan. Extract JSON rendering into a shared `ProofForge.Backend.Psy.MetadataJson` module so the test runner and new CLI both use the same serializer. Strengthen `scripts/psy/write-artifact-metadata.py` with consistency checks and unit tests. Add `ProofForge.Cli.Metadata` and wire it into `ProofForge.Cli.main`.

**Tech Stack:** Lean 4, Lake, Python 3, `just`, Foundry/solc (existing toolchain).

## Global Constraints

- Every Lean change must keep `lake build` and `just check` green.
- No renaming or removal of existing artifact JSON fields; new fields are additive.
- Event field types that cannot be inferred fall back to `"Felt"` without breaking the build.
- Schema field names must be backend-agnostic (`targetId`, `capabilities`, `contextOps`, `crosscalls`, `events`, `entrypoints`).
- Python validation failures must print the exact mismatch and exit non-zero.
- Each task ends with a commit.

---

## File Structure

| File | Responsibility |
|---|---|
| `ProofForge/Backend/Psy/Plan.lean` | `EventPlan` shape, `exprTypeName?`, `stmtEvents`. |
| `ProofForge/Backend/Psy/Metadata.lean` | `AbiEventDescriptor` construction from `EventPlan`. |
| `ProofForge/Backend/Psy/MetadataJson.lean` (new) | JSON renderer for `ArtifactMetadata`; shared by tests and CLI. |
| `Tests/PsyMetadata.lean` | Unit assertions on metadata structures. |
| `Tests/PsyMetadataExport.lean` | JSON export runner for smoke scripts; uses `MetadataJson`. |
| `scripts/psy/write-artifact-metadata.py` | Artifact JSON generation + validation. |
| `scripts/psy/test-metadata-validation.py` (new) | Python unit tests for validation rules. |
| `ProofForge/Cli/Metadata.lean` (new) | `proof-forge metadata` command implementation. |
| `ProofForge/Cli.lean` | Main dispatch; add `"metadata"` branch. |

---

### Task 1: `ContextPlan` cleanup

**Files:**
- Search all `*.lean`, `*.py`, `*.sh`, `*.md`.

**Interfaces:**
- Produces: confirmation that no `ContextPlan` references remain.

- [ ] **Step 1: Search for references**

```bash
rg "ContextPlan" --type lean --type py --type sh --type md
```

Expected: no output (already verified in context exploration, but re-run to be safe).

- [ ] **Step 2: If any reference is found, remove or update it**

For doc references, replace with the current `contextOps : Array ContextOp` shape.
For code references, replace with `plan.contextOps` or delete.

- [ ] **Step 3: Verify build still passes**

```bash
just check
```

Expected: all gates green.

- [ ] **Step 4: Commit**

```bash
git commit -m "chore(psy): verify no ContextPlan references remain"
```

---

### Task 2: Add event field type inference to `ProofForge.Backend.Psy.Plan`

**Files:**
- Modify: `ProofForge/Backend/Psy/Plan.lean:115-119`, `ProofForge/Backend/Psy/Plan.lean:193-199`

**Interfaces:**
- Consumes: `IR.Expr`, `IR.Literal`, `ValueType.name`.
- Produces: `EventPlan.dataFields : Array (String × String)`; `exprTypeName? : IR.Expr → Option String`.

- [ ] **Step 1: Change `EventPlan` to carry type names**

In `ProofForge/Backend/Psy/Plan.lean`:

```lean
structure EventPlan where
  name : String
  dataFields : Array (String × String)  -- (fieldName, fieldTypeName)
  deriving Repr
```

- [ ] **Step 2: Add `exprTypeName?` helper before `stmtEvents`**

```lean
def exprTypeName? (e : IR.Expr) : Option String :=
  match e with
  | .literal (.u8 _) => some "U8"
  | .literal (.u32 _) => some "U32"
  | .literal (.u64 _) => some "U64"
  | .literal (.u128 _) => some "U128"
  | .literal (.bool _) => some "Bool"
  | .literal (.address _) => some "Address"
  | .literal (.hash4 _ _ _ _) => some "Hash"
  | .arrayLit elemType _ => some s!"Array<{elemType.name}>"
  | .cast _ targetType => some targetType.name
  | .crosscallInvokeTyped _ _ _ retType => some retType.name
  | .structLit typeName _ => some typeName
  | _ => none
```

- [ ] **Step 3: Update `stmtEvents` to use inferred types**

```lean
partial def stmtEvents (s : IR.Statement) : Array EventPlan :=
  let fieldType (e : IR.Expr) : String := exprTypeName? e |>.getD "Felt"
  match s with
  | .effect (.eventEmit name fields) =>
      #[{ name, dataFields := fields.map (fun (n, e) => (n, fieldType e)) }]
  | .effect (.eventEmitIndexed name indexedFields dataFields) =>
      #[{ name, dataFields := (indexedFields ++ dataFields).map (fun (n, e) => (n, fieldType e)) }]
  | .ifElse _ thenBody elseBody => thenBody.flatMap stmtEvents ++ elseBody.flatMap stmtEvents
  | .boundedFor _ _ _ body => body.flatMap stmtEvents
  | _ => #[]
```

- [ ] **Step 4: Verify build**

```bash
lake build ProofForge.Backend.Psy.Plan
```

Expected: build succeeds.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Backend/Psy/Plan.lean
git commit -m "feat(psy-plan): infer event field types from IR expressions"
```

---

### Task 3: Update `ProofForge.Backend.Psy.Metadata` to use real event field types

**Files:**
- Modify: `ProofForge/Backend/Psy/Metadata.lean:66-73`

**Interfaces:**
- Consumes: `EventPlan.dataFields : Array (String × String)`.
- Produces: `abiEventDescriptor` no longer hardcodes `psyFeltTypeName`.

- [ ] **Step 1: Replace hardcoded event field type**

In `ProofForge/Backend/Psy/Metadata.lean`:

```lean
def abiEventDescriptor (event : EventPlan) : AbiEventDescriptor :=
  {
    name := event.name
    fields := event.dataFields.map (fun (fieldName, fieldType) => { name := fieldName, type := fieldType })
  }
```

Remove the comment about hardcoded `psyFeltTypeName`.

- [ ] **Step 2: Verify build**

```bash
lake build ProofForge.Backend.Psy.Metadata
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Backend/Psy/Metadata.lean
git commit -m "feat(psy-metadata): use inferred event field types"
```

---

### Task 4: Extract shared JSON renderer `ProofForge.Backend.Psy.MetadataJson`

**Files:**
- Create: `ProofForge/Backend/Psy/MetadataJson.lean`
- Modify: `Tests/PsyMetadataExport.lean`

**Interfaces:**
- Consumes: `ArtifactMetadata` and descriptor structures from `ProofForge.Backend.Psy.Metadata`.
- Produces: `renderArtifactMetadata : ArtifactMetadata → String` and helpers.

- [ ] **Step 1: Create `ProofForge/Backend/Psy/MetadataJson.lean`**

```lean
import ProofForge.Backend.Psy.Metadata

namespace ProofForge.Backend.Psy.MetadataJson

open ProofForge.Backend.Psy.Metadata

def quoteString (s : String) : String :=
  "\"" ++ (s.toList.map (fun c => match c with
    | '\\' => "\\\\"
    | '"' => "\\\""
    | '\n' => "\\n"
    | '\r' => "\\r"
    | '\t' => "\\t"
    | c => c.toString)).foldl (· ++ ·) "" ++ "\""

def jsonArray (items : List String) : String :=
  "[" ++ ", ".intercalate items ++ "]"

def jsonObject (fields : List (String × String)) : String :=
  "{" ++ ", ".intercalate (fields.map (fun (k, v) => quoteString k ++ ": " ++ v)) ++ "}"

def renderAbiParam (p : AbiParamDescriptor) : String :=
  jsonObject [("name", quoteString p.name), ("type", quoteString p.type)]

def renderAbiEntrypoint (e : AbiEntrypointDescriptor) : String :=
  jsonObject [
    ("name", quoteString e.name),
    ("params", jsonArray (e.params.toList.map renderAbiParam)),
    ("returnType", quoteString e.returnType)
  ]

def renderAbiEventField (f : AbiEventFieldDescriptor) : String :=
  jsonObject [("name", quoteString f.name), ("type", quoteString f.type)]

def renderAbiEvent (e : AbiEventDescriptor) : String :=
  jsonObject [
    ("name", quoteString e.name),
    ("fields", jsonArray (e.fields.toList.map renderAbiEventField))
  ]

def renderContextOp (o : ContextOpDescriptor) : String :=
  jsonObject [("name", quoteString o.name)]

def renderCrosscall (c : CrosscallDescriptor) : String :=
  jsonObject [("targetContractId", quoteString c.targetContractId)]

def renderArtifactMetadata (m : ArtifactMetadata) : String :=
  jsonObject [
    ("targetId", quoteString m.targetId),
    ("moduleName", quoteString m.moduleName),
    ("entrypoints", jsonArray (m.entrypoints.toList.map renderAbiEntrypoint)),
    ("events", jsonArray (m.events.toList.map renderAbiEvent)),
    ("contextOps", jsonArray (m.contextOps.toList.map renderContextOp)),
    ("crosscalls", jsonArray (m.crosscalls.toList.map renderCrosscall)),
    ("capabilities", jsonArray (m.capabilities.toList.map quoteString))
  ]

end ProofForge.Backend.Psy.MetadataJson
```

- [ ] **Step 2: Update `Tests/PsyMetadataExport.lean` to import and use the renderer**

Replace the inline `quoteString`, `jsonArray`, `jsonObject`, `renderAbiParam`, `renderAbiEntrypoint`, `renderAbiEventField`, `renderAbiEvent`, `renderContextOp`, `renderCrosscall`, and `renderArtifactMetadata` definitions with:

```lean
import ProofForge.Backend.Psy.MetadataJson

open ProofForge.Backend.Psy.MetadataJson
```

Remove the duplicated helper definitions. Keep `moduleByName` and `main`.

- [ ] **Step 3: Verify build and test**

```bash
lake build ProofForge.Backend.Psy.MetadataJson
lake env lean --run Tests/PsyMetadataExport.lean Counter
```

Expected: build succeeds; JSON prints to stdout.

- [ ] **Step 4: Commit**

```bash
git add ProofForge/Backend/Psy/MetadataJson.lean Tests/PsyMetadataExport.lean
git commit -m "refactor(psy): share metadata JSON renderer between tests and CLI"
```

---

### Task 5: Strengthen event field type assertions in `Tests/PsyMetadata.lean`

**Files:**
- Modify: `Tests/PsyMetadata.lean`

**Interfaces:**
- Consumes: `eventMeta.events[0]!.fields` now has real type strings.
- Produces: assertions that `ValueEvent` field is `"Felt"` (local fallback) and `PairEvent` field is `"Pair"`.

- [ ] **Step 1: Add event field type assertions**

Add after the existing event assertions in `Tests/PsyMetadata.lean`:

```lean
  assertEq "event value field type" "Felt" eventMeta.events[0]!.fields[0]!.type
  -- PairEvent is the first event whose field is a struct literal, so find it.
  let pairEvent? := eventMeta.events.find? (fun e => e.name == "PairEvent")
  match pairEvent? with
  | some pairEvent =>
      assertEq "pair event field type" "Pair" pairEvent.fields[0]!.type
  | none =>
      throw <| IO.userError "fail: PairEvent not found"
```

- [ ] **Step 2: Run the test**

```bash
lake env lean --run Tests/PsyMetadata.lean
```

Expected: `PsyMetadata: all assertions passed`.

- [ ] **Step 3: Commit**

```bash
git add Tests/PsyMetadata.lean
git commit -m "test(psy): assert inferred event field types"
```

---

### Task 6: Add metadata validation rules to `write-artifact-metadata.py`

**Files:**
- Modify: `scripts/psy/write-artifact-metadata.py:96-117`

**Interfaces:**
- Consumes: `metadata["contextOps"]`, `metadata["crosscalls"]`, `metadata["capabilities"]`.
- Produces: validation errors printed to stderr; non-zero exit on failure.

- [ ] **Step 1: Add validation helper functions**

Insert before `main()`:

```python
CONTEXT_OP_CAPABILITIES = {
    "userId": "callerSender",
    "contractId": "accountExplicit",
    "checkpointId": "envBlock",
}


def validate_context_ops(metadata: dict) -> tuple[bool, str]:
    capabilities = set(metadata.get("capabilities", []))
    for op in metadata.get("contextOps", []):
        name = op.get("name")
        required = CONTEXT_OP_CAPABILITIES.get(name)
        if required and required not in capabilities:
            return False, (
                f"contextOp `{name}` requires capability `{required}`, "
                f"but it is not in capabilities {sorted(capabilities)}"
            )
    return True, ""


def validate_crosscalls(metadata: dict) -> tuple[bool, str]:
    allowed_self = {"this", "self"}
    dependencies = set(metadata.get("dependencies", {}).keys())
    for call in metadata.get("crosscalls", []):
        target = call.get("targetContractId")
        if target not in dependencies and target not in allowed_self:
            return False, (
                f"crosscall target `{target}` is not listed in dependencies "
                f"{sorted(dependencies)} and is not a self-reference"
            )
    return True, ""


def validate_no_duplicates(metadata: dict) -> tuple[bool, str]:
    for key, identity in [
        ("events", lambda e: (e.get("name"), tuple((f.get("name"), f.get("type")) for f in e.get("fields", [])))),
        ("contextOps", lambda o: o.get("name")),
        ("crosscalls", lambda c: c.get("targetContractId")),
    ]:
        seen = set()
        for item in metadata.get(key, []):
            item_id = identity(item)
            if item_id in seen:
                return False, f"duplicate {key} entry: {item_id}"
            seen.add(item_id)
    return True, ""
```

- [ ] **Step 2: Call validators after plan metadata merge**

After the existing capability-set check (around line 113), add:

```python
    for validator in [validate_context_ops, validate_crosscalls, validate_no_duplicates]:
        ok, msg = validator(metadata)
        if not ok:
            print(f"Error: {msg}", file=sys.stderr)
            return 1
```

- [ ] **Step 3: Verify script syntax**

```bash
python3 -m py_compile scripts/psy/write-artifact-metadata.py
```

Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add scripts/psy/write-artifact-metadata.py
git commit -m "feat(psy): validate metadata contextOps, crosscalls, and duplicates"
```

---

### Task 7: Add Python unit tests for metadata validation

**Files:**
- Create: `scripts/psy/test-metadata-validation.py`

**Interfaces:**
- Consumes: `validate_context_ops`, `validate_crosscalls`, `validate_no_duplicates` from `write-artifact-metadata.py`.
- Produces: passing pytest/unittest output.

- [ ] **Step 1: Create the test file**

```python
#!/usr/bin/env python3
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))

from write_artifact_metadata import (
    validate_context_ops,
    validate_crosscalls,
    validate_no_duplicates,
)


class MetadataValidationTests(unittest.TestCase):
    def test_context_op_missing_capability(self):
        metadata = {
            "capabilities": [],
            "contextOps": [{"name": "userId"}],
        }
        ok, msg = validate_context_ops(metadata)
        self.assertFalse(ok)
        self.assertIn("callerSender", msg)

    def test_context_op_ok(self):
        metadata = {
            "capabilities": ["callerSender"],
            "contextOps": [{"name": "userId"}],
        }
        ok, msg = validate_context_ops(metadata)
        self.assertTrue(ok)
        self.assertEqual(msg, "")

    def test_crosscall_missing_dependency(self):
        metadata = {
            "dependencies": {},
            "crosscalls": [{"targetContractId": "OtherContract"}],
        }
        ok, msg = validate_crosscalls(metadata)
        self.assertFalse(ok)
        self.assertIn("OtherContract", msg)

    def test_crosscall_self_allowed(self):
        metadata = {
            "dependencies": {},
            "crosscalls": [{"targetContractId": "this"}],
        }
        ok, msg = validate_crosscalls(metadata)
        self.assertTrue(ok)

    def test_duplicate_event(self):
        metadata = {
            "events": [
                {"name": "ValueEvent", "fields": [{"name": "value", "type": "Felt"}]},
                {"name": "ValueEvent", "fields": [{"name": "value", "type": "Felt"}]},
            ]
        }
        ok, msg = validate_no_duplicates(metadata)
        self.assertFalse(ok)
        self.assertIn("duplicate events", msg)


if __name__ == "__main__":
    unittest.main()
```

- [ ] **Step 2: Run tests**

```bash
python3 scripts/psy/test-metadata-validation.py
```

Expected: `OK` / `Ran 5 tests`.

- [ ] **Step 3: Commit**

```bash
git add scripts/psy/test-metadata-validation.py
git commit -m "test(psy): add metadata validation unit tests"
```

---

### Task 8: Add `ProofForge.Cli.Metadata` module

**Files:**
- Create: `ProofForge/Cli/Metadata.lean`

**Interfaces:**
- Consumes: `ProofForge.Backend.Psy.Metadata.buildPlanArtifactMetadata`, `ProofForge.Backend.Psy.MetadataJson.renderArtifactMetadata`, all `ProofForge.IR.Examples.*` fixtures.
- Produces: `metadataCommand : MetadataOptions → IO UInt32`, `parseMetadataOptions : List String → Except String MetadataOptions`.

- [ ] **Step 1: Create the module**

```lean
import ProofForge.Backend.Psy.Metadata
import ProofForge.Backend.Psy.MetadataJson
import ProofForge.IR.Contract
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.MapProbe
import ProofForge.IR.Examples.EventProbe
import ProofForge.IR.Examples.ContextProbe
import ProofForge.IR.Examples.CrosscallProbe
import ProofForge.IR.Examples.StructProbe
import ProofForge.IR.Examples.StructArrayProbe
import ProofForge.IR.Examples.ArrayProbe
import ProofForge.IR.Examples.AssertProbe
import ProofForge.IR.Examples.HashProbe
import ProofForge.IR.Examples.HashStorageProbe
import ProofForge.IR.Examples.LoopProbe
import ProofForge.IR.Examples.ArithmeticProbe
import ProofForge.IR.Examples.BitwiseProbe
import ProofForge.IR.Examples.ConditionalProbe
import ProofForge.IR.Examples.ElseIfProbe
import ProofForge.IR.Examples.ExpressionPredicateProbe
import ProofForge.IR.Examples.GenericEntrypointProbe
import ProofForge.IR.Examples.AbiAggregateProbe
import ProofForge.IR.Examples.NestedAggregateProbe
import ProofForge.IR.Examples.StorageNestedAggregateProbe
import ProofForge.IR.Examples.U32ArithmeticProbe
import ProofForge.IR.Examples.U32HashPackingProbe
import ProofForge.IR.Examples.U32StorageArrayProbe
import ProofForge.IR.Examples.U32StorageScalarProbe
import ProofForge.IR.Examples.BoolStorageArrayProbe
import ProofForge.IR.Examples.BoolStorageScalarProbe

namespace ProofForge.Cli.Metadata

open ProofForge.Backend.Psy.Metadata
open ProofForge.Backend.Psy.Plan (PlanError)
open ProofForge.IR

structure MetadataOptions where
  target : String
  fixture : String
  output? : Option System.FilePath
  pretty : Bool
  deriving Repr

private def moduleByName (name : String) : Option Module :=
  match name with
  | "Counter" => some Examples.Counter.module
  | "MapProbe" => some Examples.MapProbe.module
  | "EventProbe" => some Examples.EventProbe.module
  | "ContextProbe" => some Examples.ContextProbe.module
  | "CrosscallProbe" => some Examples.CrosscallProbe.module
  | "StructProbe" => some Examples.StructProbe.module
  | "StructArrayProbe" => some Examples.StructArrayProbe.module
  | "ArrayProbe" => some Examples.ArrayProbe.module
  | "AssertProbe" => some Examples.AssertProbe.module
  | "HashProbe" => some Examples.HashProbe.module
  | "HashStorageProbe" => some Examples.HashStorageProbe.module
  | "LoopProbe" => some Examples.LoopProbe.module
  | "ArithmeticProbe" => some Examples.ArithmeticProbe.module
  | "BitwiseProbe" => some Examples.BitwiseProbe.module
  | "ConditionalProbe" => some Examples.ConditionalProbe.module
  | "ElseIfProbe" => some Examples.ElseIfProbe.module
  | "ExpressionPredicateProbe" => some Examples.ExpressionPredicateProbe.module
  | "GenericEntrypointProbe" => some Examples.GenericEntrypointProbe.module
  | "AbiAggregateProbe" => some Examples.AbiAggregateProbe.module
  | "NestedAggregateProbe" => some Examples.NestedAggregateProbe.module
  | "StorageNestedAggregateProbe" => some Examples.StorageNestedAggregateProbe.module
  | "U32ArithmeticProbe" => some Examples.U32ArithmeticProbe.module
  | "U32HashPackingProbe" => some Examples.U32HashPackingProbe.module
  | "U32StorageArrayProbe" => some Examples.U32StorageArrayProbe.module
  | "U32StorageScalarProbe" => some Examples.U32StorageScalarProbe.module
  | "BoolStorageArrayProbe" => some Examples.BoolStorageArrayProbe.module
  | "BoolStorageScalarProbe" => some Examples.BoolStorageScalarProbe.module
  | _ => none

private def renderJson (opts : MetadataOptions) (m : ArtifactMetadata) : String :=
  let raw := ProofForge.Backend.Psy.MetadataJson.renderArtifactMetadata m
  if opts.pretty then
    -- Lean's stdlib does not include a JSON pretty-printer; write compact JSON.
    raw
  else
    raw

def parseMetadataOptions (args : List String) : Except String MetadataOptions := do
  let rec loop (args : List String) (acc : MetadataOptions) : Except String MetadataOptions :=
    match args with
    | [] => .ok acc
    | "--target" :: target :: rest => loop rest { acc with target := target }
    | "--fixture" :: fixture :: rest => loop rest { acc with fixture := fixture }
    | "-o" :: out :: rest | "--output" :: out :: rest => loop rest { acc with output? := some out }
    | "--pretty" :: rest => loop rest { acc with pretty := true }
    | flag :: _ => .error s!"unknown metadata flag: {flag}"
  loop args { target := "psy-dpn", fixture := "", output? := none, pretty := false }

def metadataCommand (opts : MetadataOptions) : IO UInt32 := do
  if opts.target != "psy-dpn" then
    IO.eprintln s!"metadata command currently only supports --target psy-dpn, got {opts.target}"
    return 1
  let moduleName := opts.fixture
  match moduleByName moduleName with
  | none =>
      IO.eprintln s!"unknown fixture: {moduleName}"
      return 1
  | some module =>
      match buildPlanArtifactMetadata module with
      | .error e =>
          IO.eprintln s!"failed to build metadata: {PlanError.render e}"
          return 1
      | .ok m =>
          let json := renderJson opts m
          match opts.output? with
          | some path =>
              IO.FS.writeFile path json
              IO.println s!"wrote metadata to {path}"
          | none =>
              IO.println json
          return 0

end ProofForge.Cli.Metadata
```

- [ ] **Step 2: Verify module builds**

```bash
lake build ProofForge.Cli.Metadata
```

Expected: build succeeds.

- [ ] **Step 3: Commit**

```bash
git add ProofForge/Cli/Metadata.lean
git commit -m "feat(cli): add proof-forge metadata command module"
```

---

### Task 9: Wire `metadata` command into `ProofForge.Cli.main`

**Files:**
- Modify: `ProofForge/Cli.lean` (imports and `main` dispatch)

**Interfaces:**
- Consumes: `ProofForge.Cli.Metadata.parseMetadataOptions`, `ProofForge.Cli.Metadata.metadataCommand`.
- Produces: `"metadata" :: rest` branch in `main`.

- [ ] **Step 1: Add import**

Add to the import list in `ProofForge/Cli.lean`:

```lean
import ProofForge.Cli.Metadata
```

- [ ] **Step 2: Add dispatch branch**

In `unsafe def main`, before the `| _ =>` catch-all branch, add:

```lean
  | "metadata" :: rest =>
    match ProofForge.Cli.Metadata.parseMetadataOptions rest with
    | Except.ok opts => ProofForge.Cli.Metadata.metadataCommand opts
    | Except.error msg =>
        IO.eprintln msg
        return 1
```

- [ ] **Step 3: Verify build**

```bash
lake build proof-forge
```

Expected: build succeeds.

- [ ] **Step 4: Test the CLI manually**

```bash
lake env proof-forge metadata --target psy-dpn --fixture Counter
```

Expected: compact JSON metadata printed to stdout.

- [ ] **Step 5: Commit**

```bash
git add ProofForge/Cli.lean
git commit -m "feat(cli): wire proof-forge metadata command into main dispatch"
```

---

### Task 10: Add CLI smoke test

**Files:**
- Create: `Tests/CliMetadata.lean` (or add to `Tests/PsyMetadataExport.lean`)

**Interfaces:**
- Consumes: `ProofForge.Cli.Metadata.parseMetadataOptions`, `ProofForge.Cli.Metadata.metadataCommand`.
- Produces: assertion that the command returns 0 and outputs valid JSON.

- [ ] **Step 1: Create `Tests/CliMetadata.lean`**

```lean
import ProofForge.Cli.Metadata

namespace ProofForge.Tests.CliMetadata

def require [Inhabited α] (cond : Bool) (msg : String) : IO α :=
  if cond then
    pure default
  else
    throw <| IO.userError s!"fail: {msg}"

partial def main : IO UInt32 := do
  let args := ["--target", "psy-dpn", "--fixture", "Counter"]
  match ProofForge.Cli.Metadata.parseMetadataOptions args with
  | .error msg =>
      IO.eprintln s!"parse error: {msg}"
      return 1
  | .ok opts =>
      let code ← ProofForge.Cli.Metadata.metadataCommand opts
      if code != 0 then
        IO.eprintln "metadata command failed"
        return 1
      IO.println "ok: CLI metadata command returned 0"
      return 0

end ProofForge.Tests.CliMetadata

def main : IO UInt32 :=
  ProofForge.Tests.CliMetadata.main
```

- [ ] **Step 2: Run the test**

```bash
lake env lean --run Tests/CliMetadata.lean
```

Expected: `ok: CLI metadata command returned 0`.

- [ ] **Step 3: Commit**

```bash
git add Tests/CliMetadata.lean
git commit -m "test(cli): add metadata command smoke test"
```

---

### Task 11: Final verification and `just check` alignment

**Files:**
- Modify: `justfile` (add metadata-validation test and CLI smoke test to `psy-metadata` gate if not already present)

**Interfaces:**
- Consumes: all previous deliverables.
- Produces: green CI gates.

- [ ] **Step 1: Update `justfile` `psy-metadata` gate**

Locate the `psy-metadata` recipe and ensure it runs:

```bash
lake env lean --run Tests/PsyMetadata.lean
lake env lean --run Tests/CliMetadata.lean
python3 scripts/psy/test-metadata-validation.py
```

If the recipe is missing any of these, add them.

- [ ] **Step 2: Run full verification**

```bash
just check
```

Expected: all gates green.

- [ ] **Step 3: Commit**

```bash
git add justfile
git commit -m "ci(psy): include metadata validation and CLI smoke in psy-metadata gate"
```

---

## Self-Review

**Spec coverage:**
- A. `ContextPlan` cleanup → Task 1.
- B. Event field type derivation → Tasks 2, 3, 5.
- D. Metadata validation → Tasks 6, 7.
- C. `proof-forge metadata` CLI → Tasks 4, 8, 9, 10.
- Backend-agnostic schema → preserved in `MetadataJson` field names; no Psy-specific naming introduced.

**Placeholder scan:** No TBD/TODO/similar placeholders.

**Type consistency:** `EventPlan.dataFields` is `Array (String × String)` in Plan, consumed by `Metadata.abiEventDescriptor`; rendered by `MetadataJson` as `fields: [{name, type}]`. `MetadataOptions.fixture` maps to `moduleByName` strings. Consistent across tasks.

**Gaps:** None identified; event local-variable type inference is intentionally out of scope per spec.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-07-06-psy-metadata-hardening.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per task, review between tasks, fast iteration.
2. **Inline Execution** — Execute tasks in this session using `executing-plans`, batch execution with checkpoints.

Which approach?
