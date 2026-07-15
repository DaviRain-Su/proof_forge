# Durable goal: Lean/Rust Seam A (Artifact Contract + core.v0 + dual-run)

Copy this **entire document** into one long-running goal or agent session.
It is a continuous execution charter, not a request for another audit or plan.

| Field | Value |
|---|---|
| Status | **Success met** (2026-07-15); **D-058** freezes LR-3 Rust machine-IR lower |
| Branch | `DaviRain-Su/artifact-contract-v1` |
| PR | https://github.com/DaviRain-Su/proof_forge/pull/105 |
| Worktree | `/Users/davirian/orca/workspaces/proof_forge/artifact-contract-v1` |
| Design authority | D-057; specs under `docs/superpowers/specs/2026-07-15-*` |
| Control plane | `AGENTS.md` checkpoint; backlog LR-0… rows; `docs/implementation-log.md` |

Do **not** treat this as a one-shot feature request. Select the next eligible
slice, implement, verify, commit, push to the branch/PR, update ledger docs,
and continue until the **success condition** below is met, the goal is blocked
with a concrete blocker, or a human explicitly pauses.

---

## Mission

Build a **general, experimental Seam A** pipeline so that:

1. Lean can export **checked Canonical Core** as versioned package files
   (`core.v0.json` + capability-plan + interface + meta).
2. Rust can **load, walk, sketch-lower (subset), and observe dual-run** against
   Lean plans **without** chain SDK mega-binaries and **without** replacing the
   Lean product CLI default.
3. Artifact Contract v1 (Seam B) remains fail-closed for testkit consumers of
   `proof-forge-artifact.json`.

**This is not product ABI/SDK/deploy-manifest export.** Those are separate
contracts. Seam A is semantic Core for optional Rust backends and dual-run.

One-line product contract:

> Same product meaning (Core) can be exported from Lean, consumed by Rust for
> inspection and experimental storage sketches, and compared on declared
> dimensions to Lean `buildFromCore` plans — while authors still build through
> Lean by default.

---

## Success condition (when to mark the goal complete)

Mark complete only when **all** of the following are true on one revision,
with commands and results recorded in `docs/implementation-log.md`:

1. **Export path (general)**  
   - `proof-forge export-core --experimental` works for fixture + product
     `contract_source` paths.  
   - Primary-triad HostOps registered in Normalize.  
   - Package always has: `core.v0.json`, `capability-plan.v0.json` (with
     `requirements`, `hostOpHandlers`, `targetHostOpCatalog`),
     `interface.v0.json`, `export-meta.json`, `source-manifest.json`.  
   - Used hostCalls fail-closed if missing on target.  
   - Core body identical across `evm` / `solana-sbpf-asm` / `wasm-near` for the
     same module (proven by gate).

2. **Rust consumer (general)**  
   - `tools/pf-core` loads packages, verifies contentHash, used⊆catalog.  
   - Op walker + dual-run readiness.  
   - `pf-core-inspect`: `check`, `summary`, `compare`, `lower-sketch`,
     `dual-run-observe`.  
   - Zero chain SDKs in `pf-core` / `pf-core-inspect`.

3. **Observe dual-run (declared dimensions)**  
   - At least **Counter** and **ValueVault** (scalar/stateful) pass  
     Lean `buildFromCore` observe dump vs EVM storage sketch  
     (entrypoints + storage slots).  
   - CREATE/hostCall modules refuse storage-only sketch fail-closed.

4. **Gates & docs**  
   - `just core-export-v0` (or successor aggregate) green locally.  
   - Backlog LR rows + implementation-log updated with SHAs.  
   - PR #105 description/body still accurate; no claim of product Rust default.

5. **Explicit non-goals still held**  
   - Product CLI default remains Lean.  
   - No multi-chain SDK mega-binary.  
   - No claiming bytecode dual-run or production Rust backend until a later
     release-cycle goal.

When complete: update AGENTS checkpoint, log, backlog; set goal `completed`
with summary + SHA + PR link. **D-058:** do not start LR-3 / Rust sBPF-WAT-Yul
product lower without a decision naming ready libraries or intentional sourcegen.

---

## Truth precedence

1. Checked-in code, generated packages under `build/export/`, runnable gates.  
2. This charter + `AGENTS.md` checkpoint.  
3. D-057 and:
   - `docs/superpowers/specs/2026-07-15-lean-rust-boundary-design.md`
   - `docs/superpowers/specs/2026-07-15-artifact-contract-v1.md`
   - `docs/superpowers/specs/2026-07-15-core-export-v0-draft.md`
4. Backlog / implementation-log (navigation + evidence).  
5. Historical plans only as history.

---

## Non-negotiable rules

1. **Stay on the dedicated branch/worktree** unless merging `main` in.  
   Isolate from cutover PR #104 authoring edits when possible.
2. **Experimental only:** `export-core` requires `--experimental`.  
3. **Fail-closed:** missing tools/handlers/validate → no green package claim.  
4. **General over examples:** examples are smoke; prefer invariants + matrices.  
5. **Memory-bounded tests:** full product×triad may OOM; use Counter+ValueVault
   triad identity + multi-product single-target smokes.  
6. **TDD for behavior:** failing check first when changing export/inspect contracts.  
7. **Commit + push** reviewable slices to the branch; update EN+zh backlog when
   mapped docs change; refresh i18n manifest hashes.  
8. **No silent maturity inflation.** Storage sketch ≠ bytecode ≠ production backend.  
9. **Destructive actions** (force-push, mass delete, default-CLI switch) require
   human confirmation.

---

## Already done (do not redo; verify if needed)

| Slice | Evidence (approx.) |
|---|---|
| LR-0 Artifact Contract v1 testkit/Lean freeze | `just artifact-contract-v1` |
| LR-1a–1e export-core general package | `just core-export-v0` pieces |
| LR-2a pf-core loader | `cargo test --manifest-path tools/pf-core/Cargo.toml` |
| LR-2b walker + dual-run readiness | pf-core walk tests |
| LR-2c EVM storage sketch | `lower-sketch` on Counter; refuse CREATE |
| LR-2d observe dual-run Counter | `Tests/Canonical/DualRunObserve.lean` + `dual-run-observe` |
| LR-2e ValueVault dual-run | sketch allows `contextRead`+`emit`; 7 eps + 6 slots |
| LR-2f Ownable dual-run | sketch allows `assert`; surface dump fallback; 4 eps + 2 slots |
| LR-2g contentHash stability | re-export + pf-core reload |
| LR-2h–2j docs + stop review | core-export-v0 + validation-gates; **goal success** |

Re-run gates after merge-from-main or large conflicts.

---

## Execution loop (every slice)

1. `git status`; confirm branch `DaviRain-Su/artifact-contract-v1`.  
2. Pick **one** next eligible task from the queue below.  
3. Write/identify failing acceptance test.  
4. Implement smallest general slice.  
5. Run focused gates only (not full `just check` unless integrating).  
6. Update backlog, implementation-log, AGENTS checkpoint.  
7. Commit with complete sentences; push origin HEAD.  
8. Log progress via goal tool if available.  
9. Continue to next slice without waiting for human unless blocked.

---

## Next eligible task queue (order)

Work top-down; skip only with recorded reason.

| Order | ID | Task | Acceptance |
|---:|---|---|---|
| 1 | LR-2e | ValueVault observe dual-run | **done** |
| 2 | LR-2f | Ownable observe dual-run | **done** (surface dump if selectors missing) |
| 3 | LR-2g | Fixture counter contentHash stability | **done** |
| 4 | LR-2h | Document package layout + dual-run dimensions | **done** |
| 5 | LR-2i | validation-gates note for core-export-v0 | **done** (docs only) |
| 6 | LR-2j | Stop condition review against Success section | **done** — success met |

After success condition: **do not** implement full solc bytecode dual-run or
default Rust compile in this goal.

---

## Key commands

```bash
# Branch worktree
cd /Users/davirian/orca/workspaces/proof_forge/artifact-contract-v1

# Lean export + package gates
just core-export-v0   # aggregate when green; else focused lake/cargo below

lake env lean --run Tests/Canonical/CoreExport.lean
lake env lean --run Tests/Canonical/CoreExportPackage.lean
lake env lean --run Tests/Canonical/CoreExportGeneral.lean
lake env lean --run Tests/Canonical/CoreExportHostCall.lean
lake env lean --run Tests/Canonical/DualRunObserve.lean

# Rust
cargo test --manifest-path tools/pf-core/Cargo.toml
cargo run --manifest-path tools/pf-core-inspect/Cargo.toml -- check tools/pf-core/tests/fixtures/counter-evm
cargo run --manifest-path tools/pf-core-inspect/Cargo.toml -- summary tools/pf-core/tests/fixtures/create-evm
cargo run --manifest-path tools/pf-core-inspect/Cargo.toml -- lower-sketch tools/pf-core/tests/fixtures/counter-evm --out build/export/sketch-out
cargo run --manifest-path tools/pf-core-inspect/Cargo.toml -- dual-run-observe build/export/lr2d-dual-run/counter-evm
cargo run --manifest-path tools/pf-core-inspect/Cargo.toml -- compare \
  build/export/lr1d-counter/evm build/export/lr1d-counter/wasm-near
```

Merge main when available:

```bash
git fetch origin main
git merge origin/main   # resolve conflicts; prefer not force-push
```

---

## Package layout (normative for this goal)

```text
build/export/<id>/<target>/
  core.v0.json
  capability-plan.v0.json    # requirements + hostOpHandlers + targetHostOpCatalog
  interface.v0.json          # outside contentHash
  export-meta.json           # contentHash = core + capability-plan file bytes
  source-manifest.json
  lean-evm-observe.v0.json   # optional; for dual-run-observe
  evm-storage-sketch.v0.json # optional; from lower-sketch
```

---

## Done definition for each slice

A slice is done only when:

- Acceptance tests pass with commands recorded.  
- Commit on the branch with a clear message.  
- Pushed to `origin` (unless offline).  
- Backlog/log/checkpoint updated when state changes.  
- No unsupported claims (e.g. “Rust backend production ready”).

---

## Global blocked condition

Set goal **blocked** only if:

- Cannot build Lean/Rust toolchain on the machine after setup attempts, **or**  
- Hard dependency on merging cutover #104 for all further progress, **or**  
- Human forbids further experimental Rust work,

and the blocker message names the exact command/error and next human action.

Otherwise keep implementing.

---

## Human paste template (short)

```text
Read docs/agent-goal-prompt-lean-rust-seam-a.md fully.
You are on worktree artifact-contract-v1, branch DaviRain-Su/artifact-contract-v1, PR #105.
Seam A charter Success is already met (LR-0…2j). Re-verify gates if needed; do not reopen
finished slices unless a gate is red. Do not start LR-3 / product-default Rust lower.
Do not switch product CLI default to Rust. Prefer general infrastructure over new examples.
```

---

## Pointers

- Parent design: D-057  
- PR: #105  
- Sibling isolation: authoring cutover PR #104 — avoid large authoring conflicts; merge main when needed  
- Historical multi-chain goal (archived): `docs/agent-goal-prompt.md` — **not** this queue  
