# Aleo Leo Target: Research Exit + Spike Design

**Date:** 2026-07-01  
**Status:** Historical Aleo sourcegen design record (archived 2026-07-12); current promotion boundary is the July 12 ZK analysis.
**Scope:** Document-only design for `aleo-leo` Research exit and first Leo sourcegen spike. No code changes in this round.  
**Related docs:**
- [Aleo Leo target note](../../targets/aleo-leo.md)
- [Capability registry](../../capability-registry.md)
- [Design decisions](../../decisions.md)
- [Validation gates](../../validation-gates.md)
- [Portable IR](../../portable-ir.md)
- [Shared scenario: Counter](../../shared-scenario.md)

---

## 1. Goal

Produce a reviewed, docs-first plan for adding Aleo as a `zk-app-sourcegen` target in ProofForge, then design the first runnable spike: a Counter-like Leo program generated from the existing portable IR Counter fixture.

This spec covers:
1. Research exit criteria for `aleo-leo`.
2. Canonical capability proposal.
3. Artifact manifest schema for Aleo Leo packages.
4. Toolchain decision.
5. Spike architecture, file structure, lowering rules, CLI extension, and smoke-test flow.

It explicitly does **not** write implementation code or modify `ProofForge.Target.Capability` / `ProofForge.Target.Registry`.

---

## 2. Executive Summary

Aleo is a ZK-native smart-contract L1 whose execution model splits into:
- **Proof context:** private, off-chain execution that consumes/creates records and generates ZK proofs.
- **Finalization context:** public, on-chain execution that reads/writes mappings and storage.

ProofForge should model Aleo as a **deployable program package** target, not as a generic ZK circuit target. The safest first boundary is **Leo source generation**, delegating `.aleo` instructions, AVM bytecode, ABI, and prover/verifier artifacts to the official `leo` toolchain.

The first spike proves the compiler boundary by lowering the existing portable IR `Counter` module to a Leo package with a public `mapping` and a `final` block, then validating it with `leo build` and `leo test`.

---

## 3. Target Classification

| Attribute | Value |
|---|---|
| Target id | `aleo-leo` |
| Target family | `zk-app-sourcegen` |
| Artifact kind | `aleo-leo-package` |
| Status | Research candidate (docs-only until Spike succeeds) |
| First source boundary | Leo |
| Lower-level compiler target | Aleo Instructions (`.aleo`) |
| Deployable execution artifact | Aleo VM bytecode + ABI + prover/verifier artifacts |
| Local validation | `leo build`, `leo test`; optional `leo test --prove`, `leo execute --print` |

Backend pattern:

```text
ProofForge portable IR subset
  -> generated Leo package
  -> leo build
  -> Aleo Instructions (.aleo)
  -> Aleo VM bytecode + ABI + prover/verifier artifacts
  -> leo test / optional leo test --prove / leo execute --print
```

Distinctions from other targets:
- Not `zk-circuit-sourcegen` like `psy-dpn` (Aleo programs are contracts, not just circuits).
- Not `privacy-utxo-zk-payment` like `zcash-shielded` (Aleo has programmable state and finalization).
- Not `cairo-sourcegen` like `starknet-cairo` (Aleo uses records, mappings, and Aleo VM).
- Not `avm-sourcegen` like `algorand-avm` (Aleo VM ≠ Algorand AVM).

---

## 4. Research Exit Design

### 4.1 Capability Proposal

The following capabilities are promoted from research candidates to **canonical capabilities** in `docs/capability-registry.md`. They are sufficient for the Road 1 Counter spike.

| Canonical capability | Portable meaning |
|---|---|
| `lang.leo` | Target emits Leo source packages. |
| `vm.aleo_avm` | Target runs on the Aleo VM. |
| `artifact.avm` | Build emits Aleo VM bytecode. |
| `artifact.aleo_abi` | Build emits Aleo ABI metadata. |
| `execution.finalize` | Program has public on-chain finalization logic. |
| `state.mapping` | Public state is held in mappings. |
| `input.public` | Function input is public data. |
| `output.public` | Function output is public. |
| `test.leo` | Validation uses Leo tests. |

The following remain **research candidates** for future spikes:

| Candidate capability | Portable meaning |
|---|---|
| `ir.aleo_instructions` | Build emits or consumes Aleo Instructions. |
| `proof.prover_key` | Build or execute flow produces prover artifacts. |
| `proof.verifier_key` | Build or deploy flow records verifier artifacts. |
| `execution.transition` | Entry execution produces a transition and proof. |
| `state.record` | Private state is held in encrypted records. |
| `state.storage` | Public state uses storage variables or storage vectors. |
| `input.private` | Function input is private proof-context data. |
| `output.private` | Function output is private by default. |
| `program.import` | Program imports and calls another Aleo program. |
| `program.upgrade` | Deployment supports explicit program upgrades. |
| `transaction.execute` | Validation can produce an execute transaction. |
| `transaction.deploy` | Validation can produce or inspect a deploy transaction. |
| `fee.credits` | Fees are paid in Aleo Credits, publicly or privately. |
| `test.aleo_devnet` | Validation uses Leo devnet or devnode-backed flows. |

`zk.circuit` is intentionally **not** used for Aleo. It describes Psy/DPN-style circuit source generation and does not capture Aleo's program, state, finalization, and transaction semantics.

### 4.2 Artifact Manifest Schema

The `aleo-leo-package` artifact contains:

```text
aleo-leo-package
  - generated Leo source (main.leo)
  - program id and imports
  - mapping / storage schema
  - proof-context entry functions
  - finalization manifest
  - compiled Aleo Instructions (.aleo)
  - AVM bytecode
  - ABI JSON
  - prover and verifier artifacts (optional for spike)
  - execute/deploy transaction metadata (optional for spike)
  - test/devnet validation result
```

The corresponding `proof-forge-artifact.json` shape:

```json
{
  "schemaVersion": 1,
  "package": "counter",
  "target": "aleo-leo",
  "targetFamily": "zk-app-sourcegen",
  "artifactKind": "aleo-leo-package",
  "source": {
    "entryFile": "ProofForge/IR/Examples/Counter.lean",
    "module": "ProofForge.IR.Examples.Counter"
  },
  "proofs": {
    "checked": true,
    "warnings": []
  },
  "capabilities": [
    "lang.leo",
    "vm.aleo_avm",
    "artifact.avm",
    "artifact.aleo_abi",
    "execution.finalize",
    "state.mapping",
    "input.public",
    "output.public",
    "test.leo"
  ],
  "artifacts": {
    "leoSource": {
      "path": "build/aleo/counter/src/main.leo",
      "sha256": "...",
      "bytes": 0
    },
    "aleoInstructions": {
      "path": "build/aleo/counter/build/main.aleo",
      "sha256": "...",
      "bytes": 0
    },
    "abiJson": {
      "path": "build/aleo/counter/build/abi.json",
      "sha256": "...",
      "bytes": 0
    }
  },
  "toolchain": {
    "proofForge": "0.1.0",
    "lean": "4.31.0",
    "external": {
      "leo": "..."
    }
  },
  "targetMetadata": {
    "programId": "counter.aleo",
    "mappings": [
      { "name": "count", "keyType": "u64", "valueType": "u64" }
    ],
    "entrypoints": [
      { "name": "initialize", "publicInputs": [], "publicOutputs": [], "finalize": true },
      { "name": "increment", "publicInputs": [], "publicOutputs": [], "finalize": true },
      { "name": "get", "publicInputs": [], "publicOutputs": [], "finalize": true }
    ]
  },
  "validation": {
    "leoBuild": "passed",
    "leoTest": "passed",
    "leoTestProve": "skipped"
  }
}
```

Notes:
- `targetMetadata` is target-specific. For Aleo it records program id, mappings, and entrypoint visibility/finalization metadata.
- Prover/verifier artifacts and transaction metadata are optional in the spike and recorded as `null` or omitted if not produced.
- `leo build` for Leo 4.0.2 emits `main.aleo` and `abi.json`; a standalone `.avm` file is not produced, so `avmBytecode` is omitted from the spike artifact list.

### 4.3 Toolchain Decision

| Gate | Tool | Required for spike |
|---|---|---|
| Source generation | `proof-forge --emit-counter-ir-leo` | Yes |
| Golden fixture diff | `diff` | Yes |
| Package layout | `scripts/aleo/write-leo-package.py` | Yes |
| Compile to Aleo Instructions | `leo build` | Yes |
| Run unit tests | `leo test` | Yes |
| Optional prove gate | `leo test --prove` | No |
| Optional execute metadata | `leo execute --print` | No |
| Network deploy/execute | devnet / devnode | Deferred |

The primary local validation path is `leo build` + `leo test`. Prove-heavy gates are optional, especially in CI.

### 4.4 Research Exit Checklist

Aleo leaves Research when all of the following are documented and reviewed:

- [ ] `docs/targets/aleo-leo.md` records the `zk-app-sourcegen` classification, non-goals, and exit criteria.
- [ ] `docs/capability-registry.md` contains the canonical capability table in Section 4.1.
- [ ] `docs/decisions.md` contains a decision (e.g., D-025) ratifying `aleo-leo` as a `zk-app-sourcegen` Research candidate and the Leo-first boundary.
- [ ] Artifact manifest schema for `aleo-leo-package` is documented.
- [ ] Toolchain decision (`leo build` / `leo test` primary) is documented.
- [ ] It is explicit that `aleo-leo` is **not** added to `ProofForge.Target.Capability` / `ProofForge.Target.Registry` until the Spike succeeds and the proof/finalization split is reviewed.
- [ ] One reproducible local smoke command is documented, even if optional prove gates are skipped in CI.

---

## 5. Spike Design

### 5.1 Spike Scope

- **Road 1 only:** Leo Sourcegen Package with a public `mapping` Counter.
- **IR input:** Reuse `ProofForge.IR.Examples.Counter.module`.
- **Generated artifact:** `Counter.leo` package.
- **Validation:** `leo build` and `leo test`.
- **Out of scope:** private records, transitions/proofs, direct Aleo Instructions, program imports, devnet deployment.

### 5.2 Architecture

```text
ProofForge.IR.Examples.Counter.module
  -> ProofForge.Compiler.Leo.Emit.emitModule
  -> ProofForge.Compiler.Leo.Printer.printProgram
  -> Counter.leo
  -> scripts/aleo/write-leo-package.py
  -> build/aleo/counter/{leo.toml, src/main.leo}
  -> leo build
  -> .aleo instructions + ABI JSON
  -> leo test
  -> proof-forge-artifact.json
```

The spike mirrors the Psy DPN sourcegen pattern:
- A Lean backend module lowers portable IR to target source.
- A CLI flag emits the source.
- A golden fixture is checked under version control.
- A shell script orchestrates package generation, toolchain invocation, and metadata validation.

### 5.3 File Structure

#### New Lean modules

| File | Responsibility |
|---|---|
| `ProofForge/Backend/Aleo.lean` | Public export of `ProofForge.Backend.Aleo.IR`. |
| `ProofForge/Backend/Aleo/IR.lean` | Thin wrapper around `ProofForge.Compiler.Leo.Emit` and `ProofForge.Compiler.Leo.Printer`. |
| `ProofForge/Compiler/Leo/` | Structured Leo AST (`AST`), AST printer (`Printer`), and IR-to-AST emitter (`Emit`). |
| `ProofForge/Aleo.lean` | Optional future SDK surface. For the spike it may be empty or omitted. |

#### New examples and fixtures

| File | Responsibility |
|---|---|
| `Examples/Backend/Aleo/Counter.golden.leo` | Expected generated Leo source for the Counter IR fixture. |
| `Examples/Backend/Aleo/README.md` | Notes on how the golden file is produced and updated. |

#### New scripts

| File | Responsibility |
|---|---|
| `scripts/aleo/counter-smoke.sh` | End-to-end smoke: generate Leo → leo build → leo test → write artifact metadata → validate. |
| `scripts/aleo/write-leo-package.py` | Generate `leo.toml` and `src/main.leo` layout from emitted source. |
| `scripts/aleo/write-artifact-metadata.py` | Write `proof-forge-artifact.json` for Aleo builds. |
| `scripts/aleo/validate-artifact-metadata.py` | Validate Aleo artifact metadata schema. |

#### Updated docs

| File | Responsibility |
|---|---|
| `docs/targets/aleo-leo.md` | Updated Research note. |
| `docs/capability-registry.md` | Canonical Aleo capabilities. |
| `docs/decisions.md` | D-025 ratification. |
| `docs/validation-gates.md` | `scripts/aleo/counter-smoke.sh` command. |

### 5.4 Relationship to Existing Code

- **Do not modify** `ProofForge.IR.Contract`.
- **Do not modify** `ProofForge.Target.Capability` or `ProofForge.Target.Registry`.
- **Extend** `ProofForge.Cli` with `--emit-counter-ir-leo` (implementation phase, not this design round).
- **Reference** `ProofForge.Backend.Psy.IR` for module layout, error handling, and golden-fixture patterns.

---

## 6. Lowering Rules

### 6.1 Counter IR to Leo Mapping

Input module (existing):

```text
module Counter {
  state count: scalar U64

  entrypoint initialize() {
    effect storage.scalar.write("count", 0)
  }

  entrypoint increment() {
    let n = effect storage.scalar.read("count")
    effect storage.scalar.write("count", n + 1)
  }

  entrypoint get() -> U64 {
    return effect storage.scalar.read("count")
  }
}
```

Output shape (Leo 4.0, confirmed by `leo build` and `leo test`):

```leo
program counter.aleo {
    mapping count: u64 => u64;

    @noupgrade
    constructor() {}

    fn initialize() -> Final {
        return final {
            Mapping::set(count, 0u64, 0u64);
        };
    }

    fn increment() -> Final {
        return final {
            let current: u64 = Mapping::get_or_use(count, 0u64, 0u64);
            Mapping::set(count, 0u64, current + 1u64);
        };
    }

    fn get() -> Final {
        return final {
            let current: u64 = Mapping::get_or_use(count, 0u64, 0u64);
        };
    }
}
```

Notes:
- The scalar `U64` state maps to a public `mapping` keyed by a fixed `0u64` placeholder,
  because Aleo mappings require an explicit key.
- Leo 4.0 uses `fn` for all entry points. State-changing entry points return `Final` and
  embed a `final { ... }` block for on-chain execution.
- New programs must include `@noupgrade constructor() {}` to satisfy deployment rules.
- `storage.scalar.read` maps to `Mapping::get_or_use(<name>, 0u64, 0u64)` inside a `final`
  block; mapping reads are only allowed in finalization context.
- `storage.scalar.write` maps to `Mapping::set(<name>, 0u64, <value>);` inside a `final`
  block.
- `get` cannot return a plain `u64` from a transition because transitions cannot read
  mappings. It returns `Final` so the mapping read happens in finalization context.

### 6.2 General Lowering Rules (v0)

| Portable IR | Leo (v0) |
|---|---|
| `Module.name` | `program <name>.aleo { ... }` |
| Program constructor | `@noupgrade constructor() {}` |
| `StateDecl scalar U64` | `mapping <name>: u64 => u64;` keyed by `0u64` (Counter-specific) |
| `Entrypoint` with side effects | `fn <name>() -> Final { return final { ... }; }` |
| `Entrypoint` reading mapping | `fn <name>() -> Final { return final { ... }; }` |
| `storageScalarRead` | `Mapping::get_or_use(<name>, 0u64, 0u64)` |
| `storageScalarWrite` | `Mapping::set(<name>, 0u64, <value>);` |
| `add` / `sub` / etc. | `+` / `-` / etc. |
| `U64 literal` | `<value>u64` |
| `letBind` / `letMutBind` | `let <name>: <type> = <value>;` |
| `return` | `return <expr>;` |

The actual lowering is implemented in `ProofForge.Compiler.Leo.Emit`, which first translates the IR into a structured Leo AST (`ProofForge.Compiler.Leo.AST`) and then uses `ProofForge.Compiler.Leo.Printer` to emit Leo 4.0.2 compatible source. The AST mirrors `ProvableHQ/leo crates/ast/src/` (v4.3.2) while the printer downgrades `async { }` / `Future<Fn(...)>` to `final { }` / `Final` for the local toolchain.

### 6.3 Rejected IR Nodes

The following IR nodes are rejected by the Aleo backend in the spike because the required capabilities are not in scope:

| IR node | Missing capability |
|---|---|
| `eventEmit` / `eventEmitIndexed` | Aleo event capability not defined yet |
| `crosscallInvoke*` | `program.import` |
| `nativeValue` | `fee.credits` |
| `storageMap*` (general) | `state.mapping` general form deferred |
| `storageArray*` | `state.storage` |
| `contextRead` | `input.public` / `output.public` caller/env mapping not yet designed |

Each rejection must produce a `LowerError` with the target id, capability id, and source location when available.

---

## 7. CLI Extension

Add a new emit mode:

```lean
| counterIrLeo
```

Add command-line option:

```text
proof-forge --emit-counter-ir-leo [-o output.leo]
```

Default output path: `build/aleo/Counter.leo`.

Implementation function signature (planned):

```lean
def compileCounterIrLeo (opts : CliOptions) : IO UInt32
```

Behavior:
1. Call `ProofForge.Backend.Aleo.IR.renderModule ProofForge.IR.Examples.Counter.module`.
2. On lowering error, print `LowerError.render` and return non-zero exit code.
3. On success, write the generated Leo source to the output path.

---

## 8. Smoke Test Flow

### 8.1 `scripts/aleo/counter-smoke.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${ALEO_OUT_DIR:-$ROOT/build/aleo}"
PROJECT_DIR="$OUT_DIR/counter"
LEO_FILE="$OUT_DIR/Counter.leo"
GOLDEN_FILE="${ALEO_GOLDEN:-$ROOT/Examples/Backend/Aleo/Counter.golden.leo}"
LEO_BIN="${LEO:-leo}"
METADATA_FILE="$PROJECT_DIR/proof-forge-artifact.json"

mkdir -p "$OUT_DIR"

lake build proof-forge >/dev/null
"$ROOT/.lake/build/bin/proof-forge" --emit-counter-ir-leo -o "$LEO_FILE"

if [[ -f "$GOLDEN_FILE" ]]; then
  diff -u "$GOLDEN_FILE" "$LEO_FILE"
fi

if ! command -v "$LEO_BIN" >/dev/null 2>&1; then
  echo "aleo-counter-smoke: leo not found. Install the Aleo CLI." >&2
  echo "aleo-counter-smoke: generated $LEO_FILE for inspection." >&2
  exit 127
fi

python3 "$ROOT/scripts/aleo/write-leo-package.py" \
  --project-dir "$PROJECT_DIR" \
  --source "$LEO_FILE" \
  --program-name "counter"

(
  cd "$PROJECT_DIR"
  "$LEO_BIN" build
  "$LEO_BIN" test
)

python3 "$ROOT/scripts/aleo/write-artifact-metadata.py" \
  --root "$ROOT" \
  --fixture Counter \
  --source "$LEO_FILE" \
  --leo-project "$PROJECT_DIR" \
  --out "$METADATA_FILE" \
  --leo "$LEO_BIN"

python3 "$ROOT/scripts/aleo/validate-artifact-metadata.py" \
  --root "$ROOT" \
  "$METADATA_FILE"

echo "aleo-counter-smoke: passed"
```

### 8.2 `scripts/aleo/write-leo-package.py`

Responsibilities:
- Create `leo.toml` with package metadata.
- Create `src/main.leo` by copying the generated source.
- Preserve deterministic layout so the smoke script can run idempotently.

### 8.3 `scripts/aleo/write-artifact-metadata.py`

Responsibilities:
- Compute SHA-256 and byte sizes for `leoSource`, `aleoInstructions`, `avmBytecode`, and `abiJson`.
- Record capabilities used.
- Record toolchain versions (`leo --version` if available).
- Write `proof-forge-artifact.json` per the schema in Section 4.2.

### 8.4 `scripts/aleo/validate-artifact-metadata.py`

Responsibilities:
- Validate JSON schema version.
- Validate required fields: `target`, `targetFamily`, `artifactKind`, `capabilities`, `artifacts`, `validation`.
- Validate that every listed artifact path exists and is non-empty.
- Validate that `validation.leoBuild` and `validation.leoTest` are `"passed"`.

### 8.5 Acceptance Criteria

- `lake build` passes.
- `proof-forge --emit-counter-ir-leo` emits Leo source that matches `Examples/Backend/Aleo/Counter.golden.leo`.
- `leo build` succeeds.
- `leo test` succeeds.
- `proof-forge-artifact.json` is produced and passes validation.
- The script exits with code `127` and a clear message when `leo` is not installed.

---

## 9. Non-Goals

- Do not add `aleo-leo` to `ProofForge.Target.Registry` in this round.
- Do not add Aleo capabilities to `ProofForge.Target.Capability` in this round.
- Do not implement private records, transitions, or proof generation in the spike.
- Do not implement direct Aleo Instructions generation.
- Do not implement devnet/deploy/execute transaction metadata in the spike.
- Do not model Aleo as only a generic ZK circuit target.
- Do not confuse Aleo VM with Algorand AVM.

---

## 10. Risks and Mitigations

| Risk | Impact | Mitigation |
|---|---|---|
| Leo syntax for mappings/finalize changes | High | Keep generated source minimal; update golden fixture and lowering rules as needed. |
| `leo` CLI installation is heavy or unavailable in CI | Medium | Make Aleo smoke optional, like Psy DPN. |
| Counter IR semantics do not map cleanly to Aleo mappings | Medium | Start with a hand-written Leo Counter to confirm shape before automating lowering. |
| Aleo requires explicit program id / address handling | Low | Generate deterministic `program counter.aleo` and document any setup steps. |
| Proving is too slow for CI | Low | Keep `leo test --prove` optional; spike relies on `leo test` only. |

---

## 11. Future Work

After the Spike succeeds, the next milestones are:

1. **Add Aleo to code registry:** Add `zkAppSourcegen` family, `aleoLeo` target profile, and canonical capabilities to `ProofForge.Target.Capability` / `ProofForge.Target.Registry`.
2. **Private record flow (Road 2):** Extend IR or create a new fixture that consumes and creates encrypted records.
3. **Prove/execute gates:** Integrate `leo test --prove` and `leo execute --print` as optional CI gates.
4. **Direct Aleo Instructions (Road 3):** Evaluate whether to lower IR directly to `.aleo` instructions for compiler precision.
5. **Devnet smoke:** Add devnet/devnode deploy/execute validation.
6. **Shared scenario hardening:** Ensure the Counter scenario passes across EVM, Psy DPN, and Aleo.

---

## 12. Decision Request

This spec requests approval of the following decisions:

1. `aleo-leo` remains a Research candidate with target family `zk-app-sourcegen`.
2. The canonical capabilities in Section 4.1 are accepted for documentation.
3. The artifact manifest schema in Section 4.2 is accepted.
4. The Leo-first toolchain decision in Section 4.3 is accepted.
5. The Spike scope is Road 1 only: public mapping Counter generated from `ProofForge.IR.Examples.Counter`.
6. No code registry changes are made until the Spike succeeds.
