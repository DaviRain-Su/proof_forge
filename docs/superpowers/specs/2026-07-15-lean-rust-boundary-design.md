# Lean / Rust Boundary Design

Status: **Accepted as deferred boundary design (2026-07-15)**  
Implementation: **Phase 0 only until primary-triad authoring cutover stabilizes**  
Not active execution ledger: do not schedule Phase 2+ against the current
[AGENTS.md](../../../AGENTS.md) checkpoint while [PR #104](https://github.com/DaviRain-Su/proof_forge/pull/104)
and residual cutover work remain open.

Chinese: [2026-07-15-lean-rust-boundary-design.zh.md](2026-07-15-lean-rust-boundary-design.zh.md)

Related:

- [Canonical Core design](2026-07-11-core-ir-target-plan-design.md)
- [Backend interface](../../backend-interface.md)
- [Architecture](../../architecture.md)
- [Artifact Contract v1 draft](2026-07-15-artifact-contract-v1.md)
  ([中文](2026-07-15-artifact-contract-v1.zh.md))
- [Core export v0 draft](2026-07-15-core-export-v0-draft.md)
  ([中文](2026-07-15-core-export-v0-draft.zh.md))

## Intent

If Rust is introduced into the compiler path, it must hang at a stable seam
after Lean owns checked meaning. Product authors keep writing Lean. Rust owns
engineering work: chain SDKs, VM runners, throughput, parallel orchestration,
and (optionally later) plan/render lowering behind dual-run gates.

One sentence:

- **Lean** writes through checked meaning (`Checked Core` + `CapabilityPlan`).
- **Rust** turns meaning into chain-runnable artifacts and execution evidence
  (Phase 0 may be evidence-only and never touch lowering).

## Principles

| Principle | Meaning |
|---|---|
| Lean owns meaning | Product source, normalize/materialize, Core validate, capability closure, optional formal refinement |
| Rust owns engineering and chain liveness | Throughput, parallelism, per-chain SDK/VM, differential runners; dependencies isolated per chain |
| Exchange only stable artifacts/contracts | No Lean object pointers; no multi-chain SDK mega-binary |
| Dual-run gates | Any migrated step compares Lean old path vs Rust new path on declared dimensions |
| Formal pins Core | Proofs and content hashes pin Core (or export hash), never Rust internal data structures |

## Seams

```text
L0  Product source (Lean)
    Examples/Product · contract_source · TokenSpec · NFTSpec
              | must stay Lean
              v
L1  Frontend (Lean)
    Authored.Canonicalize · normalize · Materialize
              | must stay Lean (semantic entry)
              v
L2  Canonical Core + Validate (Lean)   ★ semantic ownership boundary
    IR.Core Syntax/Type/Validate · CapabilityPlan
    optional Semantics / Formal
         |                              |
         | Seam A (recommended main)    | Seam B (current / lowest risk)
         | export Checked Core          | final artifacts only
         v                              v
    R1  Rust Plan/Render            R0  Rust Evidence (exists)
        buildFromCore → Plan            testkit harness-* / compare /
        → bytes + meta                  differential pilots
         |
         | Seam C (optional)
         v
    R2  Per-chain runners (separate crates / locks)
```

Do **not** let Rust parse `*.lean` sources or reimplement `contract_source`.
That would recreate a second frontend and split semantic authority.

### Sub-seams under A (recommended refinement)

The live pipeline is already finer than “Rust owns everything after Core”:

```text
Checked Core + CapabilityPlan
  → buildFromCore → TargetPlan (Evm ModulePlan / Solana / Near …)
  → Render → external tools (solc / wat2wasm / sBPF) → bytes + artifact JSON
```

| Sub-seam | Lean still owns | Rust may own first | Risk |
|---|---|---|---|
| **A0** | Core + CapPlan + `buildFromCore` | Toolchain orchestration / optional plan dump / render packaging | Lowest |
| **A1** | Core + CapPlan export | Full `buildFromCore` + render for one pilot target | Main Phase 2 |
| **A2** | Product language + validate + export (+ formal) | Production default lowering | Phase 4 only |

Prefer proving A0 usefulness before rewriting target plan logic in Rust.

## Seam contracts

### Seam B — Evidence (current; consolidate first)

| Side | Content |
|---|---|
| Lean outputs | `*.bin` / `*.yul` / `*.wat`/`*.wasm` / `*.so`, `proof-forge-artifact.json`, deploy/metadata, SDK schema |
| Rust inputs | Artifact paths + scenarios (`testkit/scenarios`, differential `scenario.v1.json`) |
| Rust outputs | Exit codes, observation JSON (return/state/events/error), differential reports, CI logs |
| Hang points today | `testkit/harness-{evm,solana,near,quint}`, `testkit/compare/*`, `scripts/differential/*`, `tools/*-vm-runner`, `runtime/offline-host` |
| Risk | Low if contracts are versioned; harnesses are already split packages |

**Phase 0 action:** treat the artifact contract as a formal API (fields, versions,
required paths), not script folklore. See
[Artifact Contract v1](2026-07-15-artifact-contract-v1.md).

### Seam A — Checked Core export (if Rust becomes a compile backend)

Lean exports **only after** Validate + CapabilityPlan succeed, for example:

```text
build/export/<module>/
  core.v0.json              # experimental until cutover stabilizes
  capability-plan.v0.json
  source-manifest.json
  export-meta.json          # schemaVersion, leanToolchain, gitSha, contentHash
```

| Side | Content |
|---|---|
| Rust inputs | `core.v*` + capability-plan + `--target` |
| Rust work | (A1) `buildFromCore` → target plan → render → external tools |
| Rust outputs | Artifact tree isomorphic to current CLI + compatible `proof-forge-artifact.json` |
| Lean still | Semantics / Formal on the same Core; no dependency on Rust memory layout |

Field families and hash scope: [Core export v0 draft](2026-07-15-core-export-v0-draft.md).

**Critical gate:** for the same Product, Lean full-path artifacts and
Lean-export → Rust-backend artifacts must match on **declared dimensions**
(see Equivalence below), not necessarily byte-identical binaries.

### Seam C — Per-chain runners

| Suggested crate | Dependencies | Inputs | Outputs |
|---|---|---|---|
| `pf-run-evm` | revm / alloy (isolated) | bytecode + call sequence | receipt / state observation |
| `pf-run-solana` | mollusk / solana-* | ELF + instruction | return data / accounts |
| `pf-run-near` | near-vm / sandbox | wasm + call | logs / storage |
| future `pf-run-*` | own lockfile | … | … |

Rules:

- Never link near + solana + sui SDKs into one package dependency closure.
- Lean/CLI invokes binaries via process spawn (`Command::new`) or CI
  `cargo run -p …`, not in-process multi-SDK linking.

#### Lockfile reality vs goal

| State | Description |
|---|---|
| **Today** | `testkit/` is one Cargo workspace with multiple harness members; `workspace.dependencies` already lists both `revm` and `solana-*`. Nested NEAR compare trees and `tools/*-vm-runner` use stronger isolation. |
| **Minimum rule now** | A single **package** must not depend on more than one chain SDK family. |
| **Goal** | `pf-run-*` / `pf-backend-*` each own a lockfile (or separate workspaces), matching the `tools/*-vm-runner` pattern more than the monolithic testkit workspace. |

## What Rust must not own (unless strategy explicitly changes)

| Module | Reason |
|---|---|
| `Contract.Source` / `contract_source` | Product language and proof starting point |
| Frontend canonicalize / materialize | Meaning normalization; errors cascade |
| `IR.Core.Validate` semantic rule source | Must share owner with formal claims |
| Authoritative `IR.Core.Semantics` | Rust may mirror an interpreter for differential tests; Lean remains authority |
| `ProofForgeFormal*` | Stay Lean; pin Core or contentHash |

Rust is at most: read-only Core consumer, plan/render implementer, execution observer.

## Equivalence dimensions (dual-run)

Do **not** require byte-identical `.bin` by default (`solc` version, metadata
tails, path embedding). Declare and gate on:

1. **Runtime observation** — return / storage / events / portable error id
   (existing testkit trace parity).
2. **ABI / entrypoint surface** — names, selectors or native encodings,
   mutability class where applicable.
3. **Artifact metadata** — `targetId`, module identity, primary/final output
   kinds, file inventory under a documented hash policy.
4. **Optional text** — normalized Yul/WAT or stripped bytecode when a target
   defines a stable normalizer.

**Content hashes** pin the Core export package (and/or listed final files under
policy). **CanonicalEvidence** (spans, diagnostics provenance) must never enter
semantic artifact hashes — same rule as
[architecture.md](../../architecture.md).

Observation JSON versioning is **independent** of Core export schema version
so runner evolution does not force Core bumps.

## Phased roadmap

### Phase 0 — Consolidate evidence contract (allowed now)

Goal: Seam B becomes a written contract; no new compile backend.

| Area | Work |
|---|---|
| Lean | Document and freeze consumer-facing fields of `proof-forge-artifact.json` / ArtifactBundle honesty rules |
| Rust | testkit consumes only documented fields; keep harness packages split |
| Gate | `just product` + existing differential/harness green |
| Output | [Artifact Contract v1](2026-07-15-artifact-contract-v1.md) |

Rust hang point: artifact directories only. Output: evidence, not a new product compile path.

### Phase 1 — Core export (Lean-side; Rust read-only)

Goal: stable-enough experimental export; Rust does not replace compile.

| Area | Work |
|---|---|
| Lean | `proof-forge export-core … -o build/export/…` after validate + CapabilityPlan |
| Content | core + capability-plan + contentHash; schema **`core.v0` / experimental** until cutover and HostOp identity settle |
| Rust optional | `pf-core-inspect` schema check / summary (zero chain SDKs) |
| Gate | deterministic export; fail-closed alignment with Validate failures; subset products only (e.g. Counter + one stateful) |
| Formal | contentHash usable as formal/differential anchor |

Do not claim `core.v1` stable while authoring cutover and IR extension boundary
work still reshape HostOps and public routes.

### Phase 2 — One-chain Rust pilot (after cutover stability)

**Status under D-058 (2026-07-15): deferred / not scheduled.**  
Do **not** open a Rust product lower that re-prints sBPF/WAT/Yul without a
ready library or an explicit sourcegen decision. Seam A on PR #105 stops at
export + read-only inspect + surface observe sketch.

Historical guidance (kept for traceability only):

| Choice | Guidance |
|---|---|
| Pilot target | Prefer **EVM** only if the win is orchestration around `solc`, not re-authoring Yul in Rust. Solana/Wasm machine IR rewrite is **wont** without a sourcegen strategy (e.g. Pinocchio). |
| Prefer first | A0 tool orchestration / evidence; not A1 full `buildFromCore` for assembly printers |
| Crate | Would be `pf-backend-*` with isolated Cargo deps — **not started** |
| Gate | Would require dual-run + measurable benefit + new decision superseding D-058 |

### Phase 3 — Primary-triad Rust backends + policy

**Status under D-058: deferred.** No `pf-backend-solana` / `pf-backend-near`
machine-IR printers; no default CLI switch to Rust lower.

Default switch to Rust would require dual-run green for a full release cycle,
measurable benefit, **and** an explicit decision reopening D-058.

### Phase 4 — Optional production split

```text
Author Lean source
  → lake/lean: Canonicalize + Validate + export Core + (CI) Formal
  → rust: buildFromCore → artifacts
  → rust runners: execution evidence
```

Additional default-switch bar:

1. Primary-triad catalog subset dual-run green (not Counter-only).
2. Documented wall-clock win for export + Rust lower vs Lean full path, or
   another explicit integration benefit.
3. `PROOF_FORGE_BACKEND=lean` remains available until a dated deprecation decision.
4. Formal jobs still consume Core hash only.

## Ownership matrix

| Region | Phase 0–1 | Phase 2–3 | Phase 4 |
|---|---|---|---|
| Contract / Product | Lean | Lean | Lean |
| Frontend | Lean | Lean | Lean |
| IR.Core Validate/Syntax | Lean | Lean + export | Lean authority + export |
| Compiler/CanonicalPipeline | Lean | Lean through export; may fork after | Lean stops at export |
| Backend.Evm/Solana/WasmHost | Lean | Pilot dual-run / optional Rust | Production may be Rust |
| CLI artifact write | Lean | Lean spawns Rust or Rust writes | Mostly Rust |
| testkit / runners | Rust | Rust strengthened | Rust |
| ProofForgeFormal* | Lean | Lean pins Core hash | Lean |

## Target-state data flow

```text
Examples/Product/Foo.lean
        │
        v
[Lean] Authored / Intent materialize
        │
        v
[Lean] IR.Core.validate  ──fail──► product diagnostics
        │ ok
        v
[Lean] CapabilityPlan
        │
        ├──────────────────────────────┐
        v                              v
[Lean] export core + hash       [Lean] Formal? (optional CI)
        │
        v
[Rust] pf-lower --target evm|solana|near   (Phase 2+)
        │
        ├─► pf-backend-*  (one crate per chain)
        │         │
        │         v
        │   artifact + metadata JSON
        v
[Rust] pf-run-*  (one crate/lock per chain)
        │
        v
     observation JSON / differential / CI
```

Until Phase 2, the production path remains entirely Lean through render; Rust
stays on Seam B.

## Success criteria

Done means:

1. Authors still write only Lean for business logic.
2. Multi-chain SDKs never share one package dependency closure (goal: separate
   lockfiles for backends/runners).
3. Any Rust backend can be disabled; Lean full path still emits artifacts
   (required through Phase 3).
4. Core export schema is versioned; breaking changes get a dual-run window.
5. Formal work pins Core or contentHash, not Rust internals.
6. CanonicalEvidence never enters contentHash / semantic artifact hashes.
7. Observation contract versions independently from Core export.

## Explicit non-goals

- Rust parsing Lean sources.
- One `proof-forge-rs` static link of near + solana + sui (etc.).
- Deleting Lean backends without dual-run.
- Claiming “Rust backend = formally verified compiler”.
- Using a Rust Core interpreter as semantic authority (mirror OK; Lean Validate
  / Semantics remain authoritative).

## Priority gate (current program)

| Situation | Recommendation |
|---|---|
| PR #104 cutover / Core single path still moving | Phase 0 only; optional experimental Phase 1 design/spikes off the default path |
| Primary-triad Lean backends stable; CI/performance is the bottleneck | Open Phase 2 single-chain pilot (prefer EVM; prefer A0 before A1 when applicable) |
| Formal narrative is first-class | Keep Lean ownership of Core forever; Rust is lowering/engineering accelerator |

This design must not displace the active merge priority (D-056) or residual
authoring cutover work.

## Implementation placement (process)

Recommended when Phase 0+ code starts:

1. Create a **dedicated branch** (e.g. `docs/lean-rust-boundary` for doc follow-ups,
   later `feat/artifact-contract-v1` / `feat/export-core-v0`).
2. Prefer an **isolated worktree / Orca workspace** so cutover and boundary work
   do not share dirty trees.
3. Keep Phase 2+ crates out of the default product path until dual-run gates exist.
4. Do **not** mark this program `in_progress` in AGENTS.md until an explicit
   Phase 0 implementation task is scheduled after cutover land.

## Acceptance for this document

- [x] Principles and seams recorded.
- [x] Phase order and cutover priority gate recorded.
- [x] A0/A1 sub-seams and equivalence dimensions recorded.
- [x] Companion artifact and core-export drafts linked.
- [ ] Phase 0 code: testkit consumes only documented artifact fields (future branch).
- [ ] Phase 1 code: experimental `export-core` (future branch, post-cutover).
