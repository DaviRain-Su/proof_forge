# Incremental Legacy Replacement Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace obsolete source, product, canonical-pipeline, CLI, and fixture paths incrementally while keeping every advertised product and target behavior verified at each default switch.

**Architecture:** This is a companion plan to the Portable Intent A/B/C plan. Each legacy boundary moves through `inventoried -> replacement_ready -> parity_verified -> default_switched -> removed`; new architecture tasks create replacements, while D tasks freeze growth, migrate callers, switch defaults, and remove compatibility code in separate commits. `ContractSpec` remains an allowed internal exchange contract until a later reviewed decision proves that all legitimate consumers have a replacement.

**Tech Stack:** Lean 4, Lake, ProofForge Canonical Core, target plans and drivers, shell/Python repository checks, `just`, existing product/backend/testkit gates.

## Global Constraints

- Never overwrite unrelated worktree changes; stage only files owned by the active task.
- New product behavior enters through portable source, intent, or Surface v2 and never adds frontend `targetId` dispatch.
- A strict-path failure is never retried automatically through a legacy path.
- Default switching and legacy deletion are different tasks and different commits.
- A state transition requires a revision and reproducible positive and negative gates.
- `ContractSpec` is not globally deprecated; prevent new product coupling before considering type removal.
- Preserve artifact, metadata, diagnostic, client-schema, runtime, and resource-budget behavior promised by the migrated slice.
- Run focused tests first, `just product` for portable/product changes, `just check` before a cross-module default switch or removal, `just docs-check` for documentation changes, and `git diff --check` before every commit.
- Update `AGENTS.md`, the current A/B/C plan, the migration ledger,
  `docs/implementation-backlog.md`, and `docs/implementation-log.md` in the same
  change as each completed transition. Update `docs/gate-status.md` whenever a
  named gate criterion or phase status changes.

---

## File And Ownership Map

| File or area | Responsibility in this program |
|---|---|
| `docs/legacy-replacement-ledger.md` | Executable inventory and state/evidence for every tracked legacy boundary |
| `scripts/canonical/check-legacy-freeze.sh` | Production-import and legacy-surface growth guard |
| `scripts/portable/check-portable-default.py` | Product-source portability and target-dispatch guard |
| `ProofForge/Contract/Source*.lean` | D1 shared versus Solana-specific grammar ownership |
| `ProofForge/Contract/Intent*.lean` | D2 target-neutral intent and materializer boundary |
| `ProofForge/Compiler/CanonicalPipeline.lean` | D3 canonical normalization, strict target gate, and temporary dual-run harness |
| `ProofForge/Cli/TargetFirst.lean` | D4 typed target-first request compatibility during migration |
| `ProofForge/Cli/TargetDriver.lean` | Native target build/emit/check dispatch contract |
| `ProofForge/Cli.lean` | Top-level command parsing and native dispatch selection |
| `Tests/Canonical/*` | Strict-path, parity, default-switch, and legacy-removal evidence |
| `Tests/CliTargetFirst.lean` | Native-versus-compatibility CLI behavior and diagnostics |

---

### Task D0: Create The Migration Ledger And Freeze Baseline

**Depends on:** accepted legacy replacement design.

**Files:**
- Create: `docs/legacy-replacement-ledger.md`
- Modify: `scripts/canonical/check-legacy-freeze.sh`
- Create: `scripts/canonical/legacy-production-imports.txt`
- Modify: `justfile`
- Modify: `docs/validation-gates.md`
- Modify: `docs/document-status.md`

**Interfaces:**
- Produces: stable boundary IDs `D1-source-solana`, `D2-product-spec`, `D3-canonical-fallback`, `D4-cli-arg-roundtrip`, and `D5-legacy-imports`.
- Produces: `just legacy-replacement-freeze`, which fails when production legacy imports grow beyond the reviewed baseline.
- Consumes: the five-state lifecycle defined by the companion design.

- [x] **Step 1: Write the ledger with exact initial rows**

Create `docs/legacy-replacement-ledger.md` with this schema and initial states:

```markdown
# Legacy Replacement Ledger

Status: **Current executable migration ledger (2026-07-12)**

| Boundary ID | Legacy entry | Replacement | State | Trigger | Removal condition | Evidence |
|---|---|---|---|---|---|---|
| D1-source-solana | Solana grammar reachable from `Contract.Source` | `Contract.Source.Solana` ownership | inventoried | A1 | portable reject + Solana parity | pending |
| D2-product-spec | product entry directly routes `ContractSpec` | `IntentContract` materializer | inventoried | A2-A6 | each product family switched | pending |
| D3-canonical-fallback | advisory `runCanonicalValidationGate` | strict canonical target gate | inventoried | A5/B2 | advertised fragments strict by default | pending |
| D4-cli-arg-roundtrip | `newCommandArgsToLegacy` reparse | typed native target driver | inventoried | A6 | build/emit/check native | pending |
| D5-legacy-imports | production imports `IR.Legacy.*` | canonical or isolated test helper | inventoried | D6-D12 | production allowlist empty | pending |
```

- [x] **Step 2: Capture the production import baseline**

Run:

```bash
rg -l '^import ProofForge\.IR\.Legacy' ProofForge \
  | LC_ALL=C sort > scripts/canonical/legacy-production-imports.txt
```

Review every row. The baseline must contain paths only under `ProofForge/`, not
`Tests/`, `Examples/`, `docs/`, or generated output.

- [x] **Step 3: Extend the freeze check without requiring a false zero**

Add this comparison to `scripts/canonical/check-legacy-freeze.sh`:

```bash
actual="$(mktemp)"
trap 'rm -f "$actual"' EXIT
rg -l '^import ProofForge\.IR\.Legacy' ProofForge | LC_ALL=C sort > "$actual" || true
diff -u scripts/canonical/legacy-production-imports.txt "$actual"
```

The check freezes the exact reviewed set. Later migration tasks remove lines
from the baseline in the same commit as the corresponding production import.

- [x] **Step 4: Add and document the gate**

Add to `justfile`:

```just
legacy-replacement-freeze:
    scripts/canonical/check-legacy-freeze.sh
```

Add `legacy-replacement-freeze` to `just check` beside `legacy-freeze`, and
document its purpose in `docs/validation-gates.md`.

- [x] **Step 5: Verify and commit**

Run:

```bash
just legacy-replacement-freeze
just docs-check
git diff --check
```

Expected: all pass; the ledger remains `inventoried` because no replacement
has been proven by this task.

Commit:

```bash
git add docs/legacy-replacement-ledger.md docs/document-status.md \
  docs/validation-gates.md scripts/canonical/check-legacy-freeze.sh \
  scripts/canonical/legacy-production-imports.txt justfile
git commit -m "chore(legacy): inventory and freeze migration boundaries"
```

---

### Task D1: Close Source Grammar Isolation With A Shrinking Guard

**Depends on:** A1 implementation and Task D0.

**Files:**
- Modify: `Tests/SourceDslIsolation.lean`
- Modify: `scripts/portable/check-portable-default.py`
- Modify: `docs/legacy-replacement-ledger.md`
- Modify: `docs/superpowers/plans/2026-07-12-portable-intent-abstraction.md`
- Modify: `AGENTS.md`
- Modify: `docs/implementation-log.md`

**Interfaces:**
- Consumes: portable `ProofForge.Contract.Source` and explicit `ProofForge.Contract.Source.Solana` imports.
- Produces: D1 state `removed`; there is no compatibility reason for portable imports to expose Solana-only grammar.

- [x] **Step 1: Finish the A1 acceptance test before changing the guard**

The test must compile portable syntax with only `Contract.Source`, reject a
captured Solana PDA/CPI/realloc form under that import, and accept the same form
when `Contract.Source.Solana` is imported. It must print:

```text
source-dsl-isolation: ok
```

- [x] **Step 2: Run the focused before/after evidence**

Run:

```bash
lake env lean --run Tests/SourceDslIsolation.lean
just portable-default
just solana-light
just product
```

Expected: all pass and existing Solana artifact behavior remains unchanged.

- [x] **Step 3: Add a no-regression source ownership check**

Extend `scripts/portable/check-portable-default.py` so portable product sources
continue to reject imports of `ProofForge.Contract.Source.Solana`. Use the
existing violation-reporting pattern and the exact forbidden import string;
do not reject Solana backend fixtures under `Examples/Backend/`.

- [x] **Step 4: Advance D1 and close A1 together**

Update the ledger row to `removed` with the grammar move, acceptance-test,
product-guard, and review-repair revisions. Update A1 checkboxes, `AGENTS.md`,
and the implementation log only after the commands pass.

- [x] **Step 5: Verify and commit**

Run:

```bash
lake env lean --run Tests/SourceDslIsolation.lean
lake env lean --run Tests/SourceDslSolanaAcceptance.lean
python3 scripts/portable/check-portable-default.py --self-test
just portable-default
just solana-light
just product
just docs-check
git diff --check
```

Commit the A1/D1 implementation and review repair separately from A2 files.
Evidence: grammar move `52402821`, acceptance repair `c1433b2e`, initial guard
`b8c03f5`, and multi-module import-parser repair `6af4eb72`.

---

### Task D2: Freeze Product-Level `ContractSpec` Growth

**Depends on:** A2 intent contract API exists.

**Files:**
- Create: `scripts/portable/product-contract-spec-allowlist.txt`
- Modify: `scripts/portable/check-portable-default.py`
- Create: `Tests/IntentProductBoundary.lean`
- Modify: `justfile`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Consumes: `IntentContract`, `IntentMaterialization`, and the duplicate-safe materializer registry from A2.
- Produces: a reviewed allowlist of existing product-level `ContractSpec` construction sites and a gate preventing growth.

- [x] **Step 1: Inventory exact product construction sites**

Run:

```bash
rg -n 'ContractSpec|ContractSpec\.fromIR' ProofForge/Contract Examples/Product \
  | LC_ALL=C sort
```

Record only legitimate pre-migration locations in
`scripts/portable/product-contract-spec-allowlist.txt` using
`path:line-independent-pattern` entries. Do not use line numbers as identity.

- [x] **Step 2: Write the failing boundary test**

Create `Tests/IntentProductBoundary.lean` with a minimal intent materializer
whose result contains a `ContractSpec`, then assert that target selection occurs
only in registry lookup:

```lean
let intent : IntentContract := {
  family := .nonFungibleToken
  name := "Example"
}
let materializer <- requireMaterializer registry "evm" intent.family
let result <- materializer.materialize intent
require (result.targetId == "evm") "registry selected the wrong target"
```

Use the exact A2 API names if they differ from the design, and update this plan's
interface note in the completion log rather than introducing duplicate wrappers.

- [x] **Step 3: Add the shrinking allowlist check**

Extend `check-portable-default.py` to scan only `ProofForge/Contract` and
`Examples/Product`, compare matches against the reviewed patterns, and fail on
new direct construction. The diagnostic must include:

```text
portable-default: new product ContractSpec coupling: <path>:<symbol>
```

- [x] **Step 4: Verify and advance the ledger**

Run:

```bash
lake env lean --run Tests/IntentProductBoundary.lean
just portable-default
just product
git diff --check
```

Expected: pass. Advance D2 to `replacement_ready`; existing product families
remain on their old defaults.

- [x] **Step 5: Commit**

```bash
git add Tests/IntentProductBoundary.lean scripts/portable/check-portable-default.py \
  scripts/portable/product-contract-spec-allowlist.txt docs/legacy-replacement-ledger.md justfile
git commit -m "test(intent): freeze product ContractSpec coupling"
```

---

### Task D3: Make Accepted NFT Materialization Strict

**Depends on:** A5 materializers and D2 `replacement_ready`.

**Files:**
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: `ProofForge/Contract/Nft/Materialize.lean`
- Modify: `Tests/NftMaterialization.lean`
- Create: `Tests/Canonical/StrictIntentMaterialization.lean`
- Modify: `justfile`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: `runStrictCanonicalTargetGate : String -> ContractSpec -> Except String Unit`.
- Produces: `runStrictCanonicalContractGate : String -> CanonicalContract -> Except String Unit`
  for validation and target-stage verification after non-legacy normalization.
- Guarantees: adapter, canonical validation, capability, HostOp, unknown-target, and target `buildFromCore` failures remain errors.

- [x] **Step 1: Write negative tests against the advisory gap**

Construct cases for an unadaptable spec, invalid canonical contract, unhandled
HostOp, unknown target, and supported target builder rejection. Each assertion
must require an error prefix identifying the failing stage:

```lean
requireErrorPrefix "canonical: adapt failed" (runStrictCanonicalTargetGate "evm" badAdaptSpec)
requireErrorPrefix "canonical: unknown target" (runStrictCanonicalTargetGate "missing" goodSpec)
```

Run:

```bash
lake env lean --run Tests/Canonical/StrictIntentMaterialization.lean
```

Expected before implementation: failure because the strict function is absent.

- [x] **Step 2: Extract strict planning without changing the advisory API**

Implement `runStrictCanonicalTargetGate` by reusing the existing normalization,
validation, capability, HostOp, and three target builders. Return the builder's
stage-specific message instead of `.ok ()`. Keep
`runCanonicalValidationGate` unchanged for unmigrated callers in this task.

- [x] **Step 3: Require strict success inside accepted NFT materializers**

After materialization succeeds, call the strict gate before returning the
accepted result. Unsupported feature combinations must still fail earlier with
their stable feature diagnostic.

- [x] **Step 4: Verify accepted and rejected matrices**

Run:

```bash
lake env lean --run Tests/Canonical/StrictIntentMaterialization.lean
lake env lean --run Tests/NftMaterialization.lean
just canonical-parity
just product
git diff --check
```

Advance `D3-canonical-fallback` to `replacement_ready`. It is not
`default_switched` because non-NFT product callers still use the advisory gate.

- [x] **Step 5: Commit**

```bash
git add ProofForge/Compiler/CanonicalPipeline.lean \
  ProofForge/Contract/Nft/Materialize.lean Tests/NftMaterialization.lean \
  Tests/Canonical/StrictIntentMaterialization.lean docs/legacy-replacement-ledger.md justfile AGENTS.md \
  docs/superpowers/plans/2026-07-12-incremental-legacy-replacement.md docs/implementation-log.md
git commit -m "feat(canonical): add strict intent target gate"
```

---

### Task D4: Open NFT Through Native Target-First Dispatch

**Depends on:** A6 product route and D3 strict NFT gate.

**Files:**
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Cli/TargetFirst.lean`
- Modify: `ProofForge/Cli.lean`
- Modify: `Tests/CliTargetFirst.lean`
- Modify: `Tests/NftArtifactSchema.lean`
- Modify: `scripts/portable/nft-multi-target.sh`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: a typed native NFT build request handled by the registered target driver.
- Guarantees: the NFT command path does not call `newCommandArgsToLegacy` or reparse generated argument strings.

- [x] **Step 1: Add a native-dispatch marker test**

Extend `Tests/CliTargetFirst.lean` with an NFT build request and assert that the
resolved operation is native:

```lean
require (request.dispatchKind == .native) "NFT build must not use legacy argument translation"
require (request.targetId == "evm") "typed request lost target identity"
```

Use an explicit `DispatchKind` enum in `TargetDriver.lean` if no equivalent
typed marker exists; do not infer dispatch kind from a legacy flag string.

- [x] **Step 2: Implement native NFT request resolution**

Parse NFT input and options once into the typed request, resolve the materializer
registry, run the strict canonical gate, then invoke the existing target
artifact builder. Do not add an NFT legacy flag.

- [x] **Step 3: Pin CLI behavior and rejection identity**

Test all three targets, missing target, unsupported feature, unknown target,
output path, artifact metadata, and nonzero exit behavior. Confirm that public
diagnostics do not mention a translated legacy flag.

- [x] **Step 4: Verify and switch only NFT**

Run:

```bash
lake env lean --run Tests/CliTargetFirst.lean
lake env lean --run Tests/NftArtifactSchema.lean
scripts/portable/nft-multi-target.sh
just product
just check
git diff --check
```

Mark the NFT subrow of D2 and D4 `default_switched`. Do not mark D2 or D4 fully
switched while Counter, ValueVault, Token, Remote, build, or emit still use
compatibility dispatch.

- [x] **Step 5: Commit**

Commit the A6 default switch separately from any legacy deletion:

```bash
git add ProofForge/Cli/TargetDriver.lean ProofForge/Cli/TargetFirst.lean \
  ProofForge/Cli.lean Tests/CliTargetFirst.lean Tests/NftArtifactSchema.lean \
  scripts/portable/nft-multi-target.sh docs/legacy-replacement-ledger.md
git commit -m "feat(cli): switch NFT to native target dispatch"
```

**Completion note:** Steps 1-5 are complete for NFT `build` on the primary triad
only. `emit`, `check`, non-NFT product families, and secondary targets still use
compatibility dispatch, so D4 overall remains `replacement_ready` and only its
NFT `build` subrow is `default_switched`.

---

### Task D5: Migrate Counter As The First Existing Product Family

**Depends on:** D4 proves one native product route, and IR-B7 removes the EVM
Canonical renderer's dependency on legacy `IR.Module` declaration/storage
context. Both prerequisites are complete: Core storage effects are physical
EVM targets and `renderCanonicalModuleWithPlan` consumes `ModulePlan` alone.

**Files:**
- Modify: `Examples/Product/Counter.lean`
- Modify: `ProofForge/Cli/ContractSourceArtifacts.lean`
- Modify: `Tests/Canonical/ProductMatrix.lean`
- Modify: `Tests/SharedContractSource.lean`
- Modify: `scripts/portable/counter-multi-target.sh`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: Counter default path through portable source/Surface v2 and strict canonical target planning.
- Preserves: primary-triad artifacts, behavior trace, diagnostics, and budgets.

- [ ] **Step 1: Pin current Counter evidence before switching**

Run and retain hashes/traces in the test harness, not in hand-written prose:

```bash
just portable-counter-multi-target
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- \
  run --scenario counter --trace
```

- [ ] **Step 2: Change the parity test to compare legacy baseline with the strict candidate**

For Counter only, require both paths to succeed and compare artifact role,
entrypoints, capability requirements, target plan acceptance, trace, and budget.
Remove any comparison that checks only `isOk` equality.

- [ ] **Step 3: Switch the Counter default**

Route target-first Counter builds directly from the loaded portable source to
the strict canonical path. Keep the legacy renderer callable only from the
explicit parity test.

- [ ] **Step 4: Shrink the product coupling allowlist**

Remove Counter entries from
`scripts/portable/product-contract-spec-allowlist.txt`. A remaining direct
construction causes `just portable-default` to fail.

- [ ] **Step 5: Verify and commit**

Run:

```bash
just portable-counter-multi-target
just testkit
just product
just check
git diff --check
```

Record Counter as `default_switched`, with the exact revision and commands.
Commit:

```bash
git commit -m "refactor(product): switch Counter to strict canonical route"
```

---

### Task D6: Migrate ValueVault

**Depends on:** D5.

**Files:**
- Modify: `Examples/Product/ValueVault.lean`
- Modify: `Tests/Canonical/ProductMatrix.lean`
- Modify: `Tests/SharedContractSource.lean`
- Modify: `testkit/scenarios/value-vault.toml` (fixture route only; pinned budgets must remain unchanged)
- Modify: `scripts/portable/product-contract-spec-allowlist.txt`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: ValueVault strict default with its 11-step scenario, event, storage, return, and budget evidence preserved.

- [ ] **Step 1: Pin the existing 11-step behavior and resource evidence**

Run:

```bash
cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- \
  run --scenario value-vault --trace
```

Expected: the current return trace, events, storage snapshots, and pinned
primary-triad budgets pass before migration.

- [ ] **Step 2: Add strict-path parity assertions**

Compare canonical requirements, target-plan acceptance, emitted event identity,
runtime trace, storage snapshots, and budget results. Include negative cases for
unauthorized or invalid transitions already promised by the scenario.

- [ ] **Step 3: Switch ValueVault and shrink the allowlist**

Use the same strict product entry as Counter. Remove ValueVault direct
construction entries only after the parity test passes.

- [ ] **Step 4: Verify and commit**

Run:

```bash
just testkit
just product
just check
git diff --check
```

Record and commit:

```bash
git commit -m "refactor(product): switch ValueVault to strict canonical route"
```

---

### Task D7: Migrate Token Product Families

**Depends on:** D6 and the A2 registry contract.

**Files:**
- Modify: `ProofForge/Contract/Token.lean`
- Modify: `ProofForge/Cli/TokenLoader.lean`
- Modify: `Examples/Product/FungibleToken.lean`
- Modify: `Examples/Product/FeeToken.lean`
- Modify: `Examples/Product/SoulboundToken.lean`
- Create: `Tests/TokenIntentMigration.lean`
- Modify: `scripts/portable/product-contract-spec-allowlist.txt`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: TokenSpec normalization to `IntentContract` and registry materialization without frontend target branching.
- Preserves: token feature IDs, standard selection, artifact metadata, and honest-reject behavior.

- [ ] **Step 1: Write a three-product intent parity test**

For each product, compare the existing spec with materialized intent on each
primary target. Assert identity, features, requirements, standard metadata,
entrypoints, and every currently tested rejection.

- [ ] **Step 2: Run the test to expose missing intent coverage**

```bash
lake env lean --run Tests/TokenIntentMigration.lean
```

Expected before migration: failure naming the first TokenSpec field or feature
that has no target-neutral intent representation.

- [ ] **Step 3: Implement only the existing TokenSpec feature mapping**

Add no new token feature. Normalize existing portable fields to stable intent
feature IDs, then select target standards inside registered materializers.

- [ ] **Step 4: Switch all three products and shrink the allowlist**

Move the loader and product entrypoints together so no partial route translates
back to a target-shaped spec in frontend code.

- [ ] **Step 5: Verify and commit**

Run:

```bash
lake env lean --run Tests/TokenIntentMigration.lean
just token-feature-matrix
just product
just check
git diff --check
```

Commit:

```bash
git commit -m "refactor(token): materialize existing products through intent"
```

---

### Task D8: Migrate Remote And Crosscall Products

**Depends on:** D7.

**Files:**
- Modify: `Examples/Product/RemoteCall.lean`
- Modify: `Tests/ChainAgnosticRoute.lean`
- Modify: `scripts/portable/remote-call-multi-target.sh`
- Modify: `scripts/portable/product-contract-spec-allowlist.txt`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: portable protocol-call intent plus target materialization and `PeerMap` binding.
- Preserves: EVM call, Solana CPI account graph, NEAR promise behavior, and unsupported-target diagnostics.

- [ ] **Step 1: Pin target-specific lowering behind one portable request**

Add a test that the portable request contains protocol identity and logical peer
only. Assert that EVM address binding, Solana account metas/PDA data, and NEAR
promise details appear only after target materialization.

- [ ] **Step 2: Compare positive and negative target behavior**

Exercise existing Remote/CPI/promise gates, including missing peer, unsupported
capability, duplicate account, and promise-chain failure cases.

- [ ] **Step 3: Switch the product default and shrink the allowlist**

Remove frontend target selection or direct target-shaped `ContractSpec`
construction. Do not collapse native crosscall semantics into a new portable
Core constructor.

- [ ] **Step 4: Verify and commit**

Run the exact remote gates listed by `just --list`, then:

```bash
just product
just check
git diff --check
```

Commit:

```bash
git commit -m "refactor(remote): switch crosscalls to intent materialization"
```

After this task, advance D2 to `default_switched` only if the product allowlist
is empty or every remaining row is explicitly compiler-internal.

---

### Task D9: Switch Advertised Products To The Strict Canonical Gate

**Depends on:** D5-D8 and B2 strict target gate.

**Files:**
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Modify: all production callers of `runCanonicalValidationGate`
- Modify: `Tests/Canonical/ProductMatrix.lean`
- Modify: `Tests/Canonical/StrictTargetGate.lean`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Replaces: advisory production calls to `runCanonicalValidationGate`.
- Produces: strict default for all advertised product families and primary targets.

- [x] **Step 1: Inventory production callers**

Run:

```bash
rg -n 'runCanonicalValidationGate|CompilerPipeline\.legacy|\.legacy\b' ProofForge Examples
```

Classify each caller as production, compatibility alias, or test-only. Record
the classification in the ledger before editing.

- [x] **Step 2: Write a no-fallback regression test**

For each primary target, inject a spec that reaches a distinct failure stage
and assert the production entry returns that error. Also assert a valid Counter,
ValueVault, Token, NFT, and Remote input succeeds.

- [x] **Step 3: Switch production callers**

Replace advisory calls with `runStrictCanonicalTargetGate`. Keep the advisory
function only if an explicit compatibility alias still uses it; annotate that
single owner and removal condition in the ledger.

- [ ] **Step 4: Verify the full switch**

Run:

```bash
just canonical-product
just canonical-boundary
just product
just check
git diff --check
```

Advance D3 to `default_switched` and commit:

```bash
git commit -m "refactor(canonical): switch products to strict target gate"
```

---

### Task D10: Replace CLI Build Argument Round Trips

**Depends on:** D9.

**Files:**
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Cli/TargetFirst.lean`
- Modify: `ProofForge/Cli.lean`
- Modify: `Tests/CliTargetFirst.lean`
- Modify: `Tests/TargetBackend.lean`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: native typed `build` request resolution for all registered build routes.
- Preserves: output paths, constructor data, chain profiles, peers, Solana arch, tool paths, and diagnostics.

- [ ] **Step 1: Characterize every current translated build option**

Add table-driven tests covering every field currently appended by
`newCommandArgsToLegacy`: output, root, module, Yul output, artifact output,
EVM profile/constructor/tool options, peer options, input, format, token, and
Solana arch.

- [ ] **Step 2: Define a typed native build request**

Use existing `NewCommandParseState` fields or a smaller immutable request
structure. The driver must return a native operation/handler, not a flag string.

- [ ] **Step 3: Switch only `build`**

Top-level `ProofForge/Cli.lean` must parse once and invoke native build dispatch.
Leave legacy aliases and `emit` compatibility unchanged for this commit.

- [ ] **Step 4: Verify and commit**

Run:

```bash
lake env lean --run Tests/CliTargetFirst.lean
lake env lean --run Tests/TargetBackend.lean
just cli-target-first
just product
just check
git diff --check
```

Commit:

```bash
git commit -m "refactor(cli): dispatch target-first build natively"
```

---

### Task D11: Replace CLI Emit Argument Round Trips

**Depends on:** D10.

**Files:**
- Modify: `ProofForge/Cli/TargetDriver.lean`
- Modify: `ProofForge/Cli/TargetFirst.lean`
- Modify: `ProofForge/Cli.lean`
- Modify: `Tests/CliTargetFirst.lean`
- Modify: `Tests/TargetBackend.lean`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: native typed `emit` request resolution.
- Preserves: fixture, format, output, Yul/artifact output, chain profile,
  scenario, Quint fixture identity, tool paths, and Solana arch.

- [ ] **Step 1: Add table-driven emit characterization tests**

Cover every option currently appended in the `emit` branch of
`newCommandArgsToLegacy`, including Quint and bytecode-specific behavior.

- [ ] **Step 2: Implement native emit resolution and dispatch**

Reuse the same driver ownership boundary as native build. Target drivers select
emit behavior; top-level CLI code does not branch per target.

- [ ] **Step 3: Remove production calls to `newCommandArgsToLegacy`**

After both build and emit are native, `ProofForge/Cli.lean` must have zero calls
to the mapper. Keep the mapper temporarily only for explicit alias tests.

- [ ] **Step 4: Verify and commit**

Run:

```bash
lake env lean --run Tests/CliTargetFirst.lean
just cli-target-first
just product
just check
git diff --check
```

Advance D4 to `default_switched` and commit:

```bash
git commit -m "refactor(cli): dispatch target-first emit natively"
```

---

### Task D12: Isolate Parity Harnesses And Remove Production Legacy Imports

**Depends on:** D9-D11.

**Files:**
- Create or modify: `Tests/Canonical/LegacyBaseline.lean`
- Modify: production files listed in `scripts/canonical/legacy-production-imports.txt`
- Modify: `ProofForge/IR.lean`
- Modify: `scripts/canonical/legacy-production-imports.txt`
- Modify: `scripts/canonical/check-legacy-freeze.sh`
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Produces: test-only legacy baseline helpers.
- Produces: zero production imports of `ProofForge.IR.Legacy.*`, unless a
  specifically reviewed compiler-exchange adapter remains and is named in the ledger.

- [ ] **Step 1: Move baseline-only behavior behind a test module**

Parity tests import `Tests.Canonical.LegacyBaseline`; production modules do not
export frozen renderers merely to support comparison tests.

- [ ] **Step 2: Replace or remove each production legacy import individually**

For each baseline row, run its narrow test before and after the edit. Remove the
same row from `legacy-production-imports.txt`; never refresh the baseline upward.

- [ ] **Step 3: Tighten the gate to zero or the reviewed residual set**

If the file becomes empty, keep it as a documented zero baseline. Any residual
row must identify its internal exchange role and a later removal decision in
the ledger.

- [ ] **Step 4: Verify and commit**

Run:

```bash
just legacy-replacement-freeze
just canonical-parity
just product
just check
git diff --check
```

Advance D5 to `default_switched` or `removed`, based on whether a reviewed
internal adapter remains. Commit:

```bash
git commit -m "refactor(ir): isolate legacy parity harnesses"
```

---

### Task D13: Remove Advisory Fallback And CLI Mapper

**Depends on:** D3 and D4 `default_switched`, D12 production-import isolation,
and a full green revision after those switches.

**Files:**
- Modify: `ProofForge/Compiler/CanonicalPipeline.lean`
- Delete or reduce: `ProofForge/Cli/LegacyArgs.lean`
- Modify: `ProofForge/Cli/TargetFirst.lean`
- Modify: `Tests/Canonical/ProductMatrix.lean`
- Modify: `Tests/CliTargetFirst.lean`
- Modify: CLI usage and compatibility-policy documentation
- Modify: `docs/legacy-replacement-ledger.md`

**Interfaces:**
- Removes: production advisory canonical success and target-first argument mapper.
- Preserves: explicit legacy CLI aliases only when the compatibility policy
  still requires them; aliases invoke a named compatibility handler, not the
  new target-first dispatch path.

- [x] **Step 1: Prove there are no production callers**

Run:

```bash
rg -n 'runCanonicalValidationGate|newCommandArgsToLegacy' ProofForge Examples
```

Expected: definitions and explicit compatibility modules only; no native build,
emit, check, product, or target driver caller.

- [ ] **Step 2: Delete advisory and mapper behavior**

Remove `runCanonicalValidationGate` if no compatibility owner remains. Remove
`newCommandArgsToLegacy`, `buildLegacyFlag`, and `emitLegacyFlag` after their
tests have been replaced by native-dispatch tests.

- [ ] **Step 3: Keep alias policy honest**

If RFC 0009's compatibility window still retains old public flags, test their
deprecation warning and direct compatibility handler. Do not report D4
`removed` until policy permits deleting the aliases themselves.

- [ ] **Step 4: Verify removal and commit**

Run:

```bash
just cli-target-first
just canonical-boundary
just product
just check
just docs-check
git diff --check
```

Advance D3 and the mapper sub-boundary of D4 to `removed`. Commit:

```bash
git commit -m "refactor(compiler): remove legacy fallback and arg mapper"
```

---

### Task D14: Audit The Residual `ContractSpec` Contract

**Depends on:** D13. This is a decision task, not automatic type deletion.

**Files:**
- Create: `docs/contract-spec-residual-audit.md`
- Modify after approval: `docs/decisions.md`
- Modify: `docs/legacy-replacement-ledger.md`
- Modify: `docs/implementation-backlog.md`

**Interfaces:**
- Produces: an exact classification of every remaining `ContractSpec` consumer.
- Produces: one reviewed decision: retain/version the internal exchange type,
  narrow it, or replace it through a separate design and plan.

- [ ] **Step 1: Generate and classify the residual inventory**

Run:

```bash
rg -n '\bContractSpec\b|ContractSpec\.fromIR' ProofForge Tests Examples scripts
```

Classify each result as materializer exchange, canonical adapter, client/schema,
backend fixture, formal fixture, parity fixture, or accidental product coupling.

- [ ] **Step 2: Fail the audit on accidental product coupling**

The audit cannot recommend completion while any migrated product frontend or
target-first dispatcher constructs a target-shaped spec directly.

- [ ] **Step 3: Write the decision with compatibility impact**

For each option, record schema/version impact, migration cost, formal-proof
impact, target-plan callers, and rollback. Do not delete the type in this task.

- [ ] **Step 4: Verify docs and commit**

Run:

```bash
just docs-check
scripts/docs/audit-doc-code-sync.sh --strict
git diff --check
```

Commit:

```bash
git commit -m "docs: audit residual ContractSpec boundary"
```

---

## State Transition Summary

| Boundary | `replacement_ready` | `parity_verified` | `default_switched` | `removed` |
|---|---|---|---|---|
| D1 source grammar | A1 implementation | A1 focused + Solana/product gates | same A1 slice | D1 completion; portable exposure has no compatibility role |
| D2 product spec coupling | A2 + D2 freeze | A5/A6 then each family parity | D4-D8 by family | after all product allowlist rows are gone |
| D3 canonical fallback | D3 strict API | A5 and D5-D9 parity | D9 | D13 |
| D4 CLI arg roundtrip | D4 native NFT route | D4, D10, D11 option matrices | D11 | D13 mapper removal; aliases follow policy separately |
| D5 production legacy imports | D0 shrinking baseline | each caller's focused parity | D12 isolation | D12 if residual set is zero; otherwise later reviewed adapter replacement |

## Per-Task Review Gate

For every task, review the declared file set and verify:

1. The ledger transition matches actual code and tests.
2. No new target dispatch entered portable frontend or Canonical Core.
3. No strict failure is swallowed or retried through legacy behavior.
4. Allowlist and baseline files only shrink unless a separately approved design
   introduces a legitimate compiler-internal consumer.
5. Default switching and deletion remain separate commits.
6. `AGENTS.md` contains one active task and the correct next task.
7. `docs/implementation-log.md` records exact commands, results, limitations,
   and revision.

## Self-Review

- Every design migration line D1-D5 has at least one implementation task.
- The plan freezes growth before attempting deletion.
- A1-A6 integration is explicit and does not reschedule B/C unnecessarily.
- Counter, ValueVault, Token, and Remote switch independently with runtime or
  product evidence.
- Canonical strict switching precedes fallback deletion.
- Native build and emit migrate independently before mapper deletion.
- `ContractSpec` receives a residual audit and separate decision rather than an
  assumed deletion task.
- Every cross-module switch or removal requires `just check`.
