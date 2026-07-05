# Psy Metadata Hardening: Type-Driven Events, Validation, and CLI

**Date:** 2026-07-06
**Status:** Design spec (awaiting review)
**Scope:** Clean up `ContextPlan` residue, derive event field types from expressions, strengthen artifact metadata validation, and add a `proof-forge metadata` CLI. Schema changes are made with EVM/Solana reuse in mind.
**Related docs:**
- [Psy DPN build-fix + metadata design](./2026-07-05-psy-build-fix-and-metadata-design.md)
- [Psy DPN target note](../../targets/psy-dpn.md)
- [Capability registry](../../capability-registry.md)

---

## 1. Goal

Make the Psy metadata pipeline self-contained and backend-agnostic enough that EVM/Solana can reuse the same schema in a future phase:

1. Remove every remaining `ContextPlan` reference.
2. Derive real event field types from portable-IR expressions instead of hardcoding `felt`.
3. Validate that artifact metadata is internally consistent (capabilities ↔ contextOps, crosscall targets present).
4. Add a `proof-forge metadata` CLI command that emits plan-driven metadata JSON.
5. Keep the artifact JSON schema additive and naming generic (`targetId`, `capabilities`, `contextOps`, `crosscalls`, `events`, `entrypoints`) so it is not Psy-specific.

---

## 2. Background

The previous increment made the branch build, fixed lowering correctness gaps, and wired `ProofForge.Backend.Psy.Metadata` into the Psy smoke scripts. Remaining gaps:

- `EventPlan` only records field names, so `AbiEventDescriptor` hardcodes `psyFeltTypeName` for every field.
- `write-artifact-metadata.py` validates capabilities against the smoke script, but does not check that `contextOps` and `crosscalls` are consistent with `capabilities`.
- There is no standalone command to export metadata; users must run a smoke script.
- The `ContextPlan` structure was already deleted from `ProofForge.Backend.Psy.Plan`, but a doc reference may still exist.

---

## 3. Design

### 3.1 `ContextPlan` cleanup

Search the whole repo (`*.lean`, `*.py`, `*.sh`, `*.md`) for `ContextPlan`:

- If found in docs: update to the current `contextOps : Array ContextOp` shape.
- If found in code/tests: remove or replace with the equivalent `contextOps`/`crosscalls` fields.
- If no references remain: add a short cleanup commit noting the verification.

### 3.2 Event field type derivation

Extend `ProofForge.Backend.Psy.Plan.EventPlan` to carry both names and inferred types:

```lean
structure EventPlan where
  name : String
  dataFields : Array (String × String)  -- (fieldName, fieldTypeName)
  deriving Repr
```

When collecting events in `stmtEvents`, infer each field's type from its `IR.Expr` using a new helper:

```lean
def exprTypeName? (e : IR.Expr) : Option String
```

The helper returns a type name for the unambiguous cases:

- `literal l` → `Literal.type.name` (or equivalent).
- `arrayLit elemType _` → array descriptor of `elemType`.
- `cast _ targetType` → `targetType.name`.
- `crosscallInvokeTyped _ _ _ retType` → `retType.name`.
- `structLit typeName _` → `typeName`.
- Storage/effect reads that resolve to a known `ValueType`.

For locals, unresolved expressions, or complex nested expressions, the helper returns `none`. The collector falls back to `psyFeltTypeName` and emits a `warn` once per event field so builds do not break.

`ProofForge.Backend.Psy.Metadata.abiEventDescriptor` then uses `event.dataFields` directly instead of hardcoding `psyFeltTypeName`.

### 3.3 Metadata validation

Strengthen `scripts/psy/write-artifact-metadata.py` after merging `--plan-metadata`:

1. **Capability/contextOp consistency.** Every `contextOp.name` must map to a capability in `capabilities`. The mapping is:
   - `userId` → `callerSender`
   - `contractId` → `accountExplicit`
   - `checkpointId` → `envBlock`
   If a contextOp is present but its required capability is missing, fail with a clear message.

2. **Crosscall target present.** Every `crosscall.targetContractId` must either:
   - appear as a key in the artifact's `dependencies`/`contracts` map, or
   - be the literal string `"this"` / `"self"` if self-calls are supported.
   For now, self-calls are allowed; missing external targets fail.

3. **Duplicate freedom.** `events`, `contextOps`, and `crosscalls` must remain deduplicated. The Python script asserts this as a sanity check on the input JSON.

### 3.4 `proof-forge metadata` CLI

Add a new subcommand to the existing `proof-forge` CLI:

```bash
lake env proof-forge metadata \
  --target psy \
  --root . \
  --module contract \
  Examples/Psy/Contracts/Counter.lean
```

It prints the same JSON that `Tests/PsyMetadataExport.lean` currently writes, with options:

- `--output <file>` or `-o <file>`: write to file instead of stdout.
- `--pretty`: pretty-print JSON.

Implementation path:

- Add a `Metadata` command module under `ProofForge/Cli/Metadata.lean` (or the existing CLI directory).
- Reuse `ProofForge.Backend.Psy.Metadata.buildPlanArtifactMetadata`.
- Convert the `ArtifactMetadata` structure to JSON using the same serializer used by `Tests/PsyMetadataExport.lean`.

### 3.5 Backend-agnostic schema extension points

Keep field names generic so a future EVM/Solana backend can emit the same artifact shape:

- `targetId` rather than `psyTargetId`.
- `moduleName` rather than `psyModuleName`.
- `entrypoints[].params[].type` and `returnType` are plain strings; backends encode their own type grammar.
- `events[].fields[].type` is a plain string.
- `contextOps[].name` is a plain string.
- `crosscalls[].targetContractId` is a plain string.
- `capabilities` is `Array String` using canonical ids from `capability-registry.md`.

When the EVM/Solana backend is later integrated, the only Psy-specific piece should be the Lean function that builds `ArtifactMetadata`; the JSON schema stays the same.

### 3.6 Tests

- `Tests/PsyMetadata.lean`: assert that `EventProbe` events have non-trivial field types (e.g., `u32`, `u64`, struct names) where the source expression allows inference.
- `Tests/PsyMetadataExport.lean`: extend to verify the exported JSON passes Python-side validation.
- Add `scripts/psy/test-metadata-validation.py`: unit tests for the new validation rules using mock JSON inputs.
- Add a CLI test in `Tests/Cli/Metadata.lean` or a shell test that runs `proof-forge metadata` on `Counter.lean` and checks the JSON shape.

---

## 4. Testing Plan

1. `lake build` — must pass with no errors.
2. `just check` — must pass.
3. `just psy-diagnostics` — all 59 cases must pass.
4. `just psy-coverage` — IR coverage manifest must remain unchanged.
5. `just psy-golden-sources` — generated `.psy` sources must remain byte-identical.
6. New `Tests/PsyMetadata.lean` assertions pass.
7. New Python validation unit tests pass.
8. New `proof-forge metadata` CLI smoke test passes.

---

## 5. Risks and Mitigations

| Risk | Mitigation |
|---|---|
| Event type inference is incomplete and falls back to `felt` often | Document the fallback; warn once per field; improve incrementally as more type information is plumbed through the IR. |
| Changing `EventPlan` shape breaks existing callers | Update `stmtEvents`, `Metadata.abiEventDescriptor`, and `Tests/PsyMetadata.lean` in the same commit; verify with `lake build`. |
| New validation rules break existing smoke scripts | Fix mismatches in the same change; keep rules opt-in only during a transition if necessary. |
| CLI command duplicates Python writer logic | Keep the CLI as a thin wrapper around `Metadata.lean`; reuse the same JSON serializer. |
| Generic schema conflicts with EVM's existing metadata | Keep fields additive; do not rename existing EVM artifact fields; align only the new metadata block. |

---

## 6. Out of Scope

- Full `whileLoop` support across backends.
- EVM/Solana backend actually emitting this metadata schema (only schema alignment).
- Live Psy node/prover deployment research.
- Memory arrays.
- Type inference for local variables via environment analysis.

These remain future work after this increment lands.
