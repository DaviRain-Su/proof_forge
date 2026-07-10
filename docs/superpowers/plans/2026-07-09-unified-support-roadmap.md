# Unified Support Roadmap — HostEnv · Crosscall · FV · Platform

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Gradually make ProofForge a *unified* multi-host product: authors write business intent only; primary triad (`evm` · `solana-sbpf-asm` · `wasm-near`) materializes honestly; FV trust boundary grows with each feature — without reopening product α–ε or opening new chains by default.

**Architecture:** Keep the existing pipeline  
`contract_source / TokenSpec → ContractSpec → portable IR → PortableHonesty + capability resolve → per-target lower → artifacts + gates`.  
Unification means **closing HostEnv / identity / remote / error holes on the triad**, **making IR+FV semantics honest about crosscall**, and **hardening platform policies** — not merging backends into one codegen.

**Tech Stack:** Lean 4.31 (`lean-toolchain`), `proof-forge` CLI, `just product` / `just check`, Foundry/`solc`, `sbpf`/Mollusk, `wat2wasm`, optional Quint.

**Baseline (do not reopen without a product bug):**
- Gate G0 / P0 closed (three primary chains).
- Product waves α–ε frozen as v1 (`docs/product-sdk-gap-plan-2026-07.md`).
- Portable SDK unification Waves 1–4 **done** (`docs/superpowers/plans/2026-07-09-portable-sdk-unification.md`).
- Track 0 IR bugs fixed; Solana/WASM Counter/ValueVault proof surfaces and
  CosmWasm/Soroban host axes landed. EVM currently has canonical fixed-trace evidence plus
  an obligation-explicit universal theorem, not a closed triad-wide C-proof.
- Honesty pipeline lands in `resolveSpec` via `PortableHonesty.requirePortableHonesty` (`ProofForge/Target/Adapter.lean`, `PortableHonesty.lean`).

**Related audits / SOT:**
- Full project audit conclusions (session 2026-07-09).
- [product-north-star](../../zh/product-north-star.md) · [chain-agnostic-gap-analysis](../../zh/chain-agnostic-gap-analysis.md)
- [host-runtime](../../host-runtime.md) · [platform-gaps-2026-07](../../platform-gaps-2026-07.md)
- [formal-verification](../../formal-verification.md) · [FV-9 plan](2026-07-08-fv9-universal-compiler-correctness.md)
- [sdk-ecosystem-gaps-2026-07](../../sdk-ecosystem-gaps-2026-07.md)

## Global Constraints

1. **Primary triad first:** `evm`, `solana-sbpf-asm`, `wasm-near`. CosmWasm / Soroban / Move / Aleo / Psy stay spike or optional unless a task explicitly says otherwise.
2. **No silent drop:** unsupported → compile/plan diagnostic (`HostEnv` / capability / `PortableHonesty`), never fake success.
3. **materializeEnv honesty:** `.ok` only when a real lower/host path exists; never alias fields (e.g. `chainId` ↛ `block_index`).
4. **Product α–ε frozen:** free-form Call bytes, multi-host vault body, VaultSpec author API = v2 only.
5. **No new chain backends** in this roadmap unless product explicitly schedules Gate G1.
6. **One mergeable slice per task:** entry files + acceptance command + Done definition; prefer `just product` green after each wave.
7. **FV grows with features:** if a task adds IR constructors or HostEnv lowers used by portable products, update covered-fragment / HostEnv tests in the same change when feasible.
8. **English SOT:** engineering truth in `docs/*.md`; Chinese docs align, no independent policy.
9. **Working tree:** start from green `main` (honesty/CPI rollout already landed @ `4ffa1f1f`).

---

## File map (units of work)

| Unit | Responsibility | Primary paths |
|------|----------------|---------------|
| HostEnv catalog | Portable env materialize-or-reject | `ProofForge/Target/HostRuntime.lean` |
| Portable honesty gate | Fail-closed resolve | `ProofForge/Target/PortableHonesty.lean`, `Adapter.lean` |
| Solana context lower | Clock / program id / signer digests | `ProofForge/Backend/Solana/SbpfAsm/Expr.lean`, `Common.lean` |
| IR crosscall semantics | Executable + Quint-aligned stub boundary | `ProofForge/IR/Semantics.lean`, `SemanticsFuel.lean`, `Backend/Quint/Lower.lean` |
| Crosscall materialize | Sync remote → CALL/CPI/promise | `ProofForge/Target/CrosscallMaterialize.lean`, `Backend/Solana/Manifest.lean` |
| Product remote / accounts | Shared examples without Surface | `Examples/Product/*`, `scripts/portable/*` |
| EVM stdlib P1 | Callbacks / batch / errors | `ProofForge/Contract/Stdlib/*`, Foundry smokes |
| NEAR deploy honesty | Offline vs broadcast | `scripts/near/*`, deploy metadata |
| FV-9 | Universal fragment | `ProofForge/Backend/Refinement/*`, `IR/SemanticsFuel.lean` |
| Platform | CLI M4, versioning, clients | `ProofForge/Cli/*`, RFCs 0009/0012/0013 |
| Gates | Acceptance | `justfile`, `Tests/HostRuntime.lean`, `just product`, `just check` |

---

## Wave index (slow unification)

```text
U0  Stabilize & inventory          (docs + gates only)     [short]
U1  HostEnv triad fill             (product "only business") [HIGH]
U2  Crosscall semantic honesty     (IR/FV truth)             [HIGH]
U3  Product remote / accounts polish                         [MED]
U4  Selective ecosystem P1 (EVM/Solana/NEAR)                 [MED]
U5  FV-9 fragment growth (with U1/U2)                        [HIGH long]
U6  Platform debt (CLI M4, versioning, client schema)        [MED]
U7  Secondary hosts discipline (spike freeze / optional)     [LOW]
```

**Recommended serial spine:** U0 → U1 → U2 → (U3 ∥ U6 docs) → U5 interleaved → U4 selective → U7 only if needed.

### Wave U0 — Stabilize & inventory

**Done when:** this roadmap is linked from INDEX; portable-sdk plan marked complete; green `just product` baseline recorded.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **U0.1** | Land this roadmap | Add `docs/superpowers/plans/2026-07-09-unified-support-roadmap.md`; link from `docs/INDEX.md` Engineering section | Doc present; INDEX link | S | **done** |
| **U0.2** | Close portable-sdk plan | Status → **Complete**; pointer to this roadmap as successor | Status line + changelog row | S | **done** |
| **U0.3** | Baseline gate | Run `just product` (or note CI green @ HEAD) | Document HEAD + result in changelog | S | **done** (`just product` green @ `4ffa1f1f` + local docs) |

---

### Wave U1 — HostEnv triad fill (highest product leverage)

**Done when:** portable authors can use `blockTime` and `selfAddress` on **all three** primary hosts without Surface imports; remaining general-bucket holes are either wired or **explicitly documented permanent rejects** with product-facing reasons.

**Current matrix (must update as tasks land):** see `materializeEnv` docstring in `ProofForge/Target/HostRuntime.lean`.

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **U1.1** | Solana `blockTime` | Lower `contextRead .timestamp` via `sol_get_clock_sysvar` → `Clock.unix_timestamp` (i64 at offset in clock buffer); `materializeEnv .blockTime "solana-sbpf-asm" = .ok`; HostRuntime tests | `lake env lean --run Tests/HostRuntime.lean`; Solana fixture/smoke that reads timestamp; `just product` | M | — | **done** (`ac12d18d`) |
| **U1.2** | Solana `selfAddress` | Lower `contextRead .contractId` to program id (32-byte / limb0 Hash policy matching OwnableHash); materializeEnv ok; honesty tests | Same gates + identity note in `docs/host-runtime.md` | M | U1.1 optional | **done** (`83ed411b`) |
| **U1.3** | Solana `randomness` / `epoch` decision | Either wire SlotHashes / Clock.epoch **or** permanent reject + author doc | Decision row §Open decisions + tests match | S | — | **done** (permanent reject + host-runtime §) |
| **U1.4** | Gas/compute HostEnv path | Document EVM-only vs extension-only CU; optional Solana `gasOrComputeBudgetLeft` via `sol_remaining_compute_units` **as HostEnv** (not only extension) | materializeEnv matrix + one smoke or permanent reject | M | U1.1 | **done** (Solana wired; NEAR permanent reject) |
| **U1.5** | NEAR HostEnv holes | Confirm prepaid_gas / chainId permanent reject; wire only if real host import exists | Docs + `Tests/HostRuntime.lean` | S | — | **done** (permanent reject confirmed) |
| **U1.6** | Product example using triad HostEnv | Shared Product example (e.g. time-gated pause or self-check) × three targets | `just portable-*` or new smoke | M | U1.1–U1.2 | **done** |

#### Task U1.1 detail (first executable slice)

**Files:**
- Modify: `ProofForge/Backend/Solana/SbpfAsm/Expr.lean` (contextRead arms ~374–403)
- Modify: `ProofForge/Target/HostRuntime.lean` (`materializeEnv` blockTime solana arm)
- Modify: `Tests/HostRuntime.lean` (HostEnv triad matrix asserts)
- Modify: `docs/host-runtime.md` § HostEnv matrix
- Optional: Solana Counter/context probe golden if emission comments change

**Interfaces:**
- Consumes: existing `sol_get_clock_sysvar` pattern used by `.checkpointId` (Clock.slot)
- Produces: `contextRead .timestamp` → u64 seconds (document ns vs s if Clock stores seconds — Solana Clock.unix_timestamp is i64 seconds)

- [ ] **Step 1:** Add failing HostRuntime assertion: `supportsHostEnv "solana-sbpf-asm" .blockTime = true`
- [ ] **Step 2:** Run `lake env lean --run Tests/HostRuntime.lean` → expect FAIL
- [ ] **Step 3:** Implement Expr lower for `.timestamp` (reuse clock buffer; load unix_timestamp field offset; zero-extend / clamp to u64)
- [ ] **Step 4:** Flip `materializeEnv` solana `blockTime` to `.ok` with syscall symbol + note
- [ ] **Step 5:** Re-run HostRuntime + narrow Solana smoke; `just product`
- [ ] **Step 6:** Commit `feat(host): Solana HostEnv blockTime via Clock.unix_timestamp`

---

### Wave U2 — Crosscall semantic honesty

**Done when:** docs and code agree that IR `evalCrosscallInvoke*` is a **deterministic stub** for MBT/Quint; product portable remotes are validated by **target emit + host smokes**, not IR return-value equality; optional Phase-2 oracle path designed.

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **U2.1** | Document stub boundary | `docs/portable-ir.md` + `formal-verification.md` Tier table: crosscall = stub; backends = real | Docs + link from FV tiers | S | — | **done** |
| **U2.2** | Code comments / API names | Rename or annotate `evalCrosscallInvokeSum` as `stub`; Quint Lower same | Grep “stub” consistent; no behavior change | S | U2.1 | **done** |
| **U2.3** | Test split | Separate tests: (a) IR stub determinism (b) target remote materialize smokes | Tests do not claim IR==EVM CALL | M | U2.1 | **done** |
| **U2.4** | Design real-peer oracle (spec only) | RFC/note: optional IR peer mock registry for FV later | Design doc only | M | U2.1 | **done** (note in portable-ir § Crosscall) |
| **U2.5** | Portable return decode MVP | Typed scalar returns already partial; extend table or honest reject richer shapes | CrosscallMaterialize + multi-target smoke | L | U2.3 | **done** (policy: scalar u64 product; richer reject/deferred) |

---

### Wave U3 — Product remote / accounts polish

**Done when:** every `Examples/Product/*` that uses remote/value builds Solana without `Source.Solana` where claimed; empty peer fail-closed stays green.

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **U3.1** | Audit Product examples vs Solana Surface | Inventory imports; fix or label fixture-only | Table in Examples/Product/README | S | — | **done** |
| **U3.2** | Account inference coverage | Extend `inferSolanaAccounts` / `ensurePortableCrosscallAccounts` for remaining Product remotes | `just portable-remote-call-multi-target` + product-matrix | M | U3.1 | **done** (protocol FT/vault + Accounts tests) |
| **U3.3** | PeerMap author UX | Document `declareRemote` / strings pool; fail messages point to fix | Docs + diagnostic string tests | S | — | **done** |

---

### Wave U4 — Selective ecosystem P1 (only when product needs)

Pick **at most one** track per cycle. Default order if capacity:

| ID | Track | Work | Acceptance | Size | Status |
|----|-------|------|------------|------|--------|
| **U4.E1** | ERC-721 `onERC721Received` | Optional callback or documented permanent skip | Foundry smoke | M | pending |
| **U4.E2** | ERC-1155 batch | batchTransfer + tests | Foundry | L | pending |
| **U4.E3** | Custom error selectors | IR/portable error → Solidity custom error surface | EVM diagnostics + smoke | M | pending |
| **U4.S1** | Memo arbitrary length | Beyond one-word payload | Surfpool or light gate | M | pending |
| **U4.N1** | NEAR broadcast smoke | Real near-cli/sandbox deploy beyond offline host | Script + optional CI | L | pending |
| **U4.N2** | Promise async honesty docs | Portable = sync only; extension path documented | Docs + reject tests | S | pending |

---

### Wave U5 — FV-9 fragment growth (interleaved)

**Done when:** covered fragment expands beyond Counter-local constructors used by Product Ownable/ValueVault paths; still no false “∀ contracts” claim outside fragment.

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **U5.1** | Map Product constructors → fragment | List IR nodes used by Counter/Ownable/ValueVault/RemoteCall | Coverage table in ConstructorCoverage or doc | S | — | **done** |
| **U5.2** | Fuel semantics for next constructor class | Extend `SemanticsFuel` + covered fragment | Smoke + theorems green | L | U5.1 | **done** (`boundedFor` + LoopProbe) |
| **U5.3** | Crosscall out of fragment | Explicitly **exclude** stub crosscall from ∀-fragment until U2.4 | fragment predicate tests | S | U2.1 | **done** (RemoteCall out; fuelCovered gap) |
| **U5.4** | HostEnv-using modules in fragment | After U1, prove or differentially gate time/self reads | Refinement smoke | L | U1.1 | **done** (HostEnvProbe in-fragment smoke) |

Follow detailed steps in [FV-9 plan](2026-07-08-fv9-universal-compiler-correctness.md); this wave only sequences product-driven expansion.

---

### Wave U6 — Platform debt

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **U6.1** | Versioning RFC 0012 enforcement | IR major.minor + artifact schemaVersion checks in emit | Doc + smoke | M | **done** (`just versioning-policy`) |
| **U6.2** | CLI M4 plan (no delete yet) | Inventory remaining legacy flags; deprecation window | Inventory md + `just cli-target-first` | S | **done** (`docs/cli-m4-legacy-inventory.md`) |
| **U6.3** | CLI M4 delete | Remove aliases after window | CI green; docs | L | U6.2 | **prep only** (`cli-m4-deletion-checklist.md`; no delete) |
| **U6.4** | Unified client schema gaps | Align method names / error ids three hosts | client-schema tests | M | **done** (`just client-schema-parity`) |
| **U6.5** | Upgrade/signing boundary docs | RFC 0013 operational notes for CI keys | Docs only | S | **done** (`docs/upgrade-signing-ops.md`) |

---

### Wave U7 — Secondary host discipline

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **U7.1** | Spike label audit | README/Backend Status vs Gate G1 not started | Doc sync | S | **done** |
| **U7.2** | CosmWasm/Soroban stub banners | CLI/docs: execute_msg / require_auth stub | Clear strings | S | **done** |
| **U7.3** | No G1 without explicit schedule | Do not implement CosmWasm M3 unless ticket | Process | — | standing rule |

---

## Dependency graph

```text
U0.1–U0.3
   │
   ▼
U1.1 → U1.2 → U1.6
   │      ↘ U1.4
   │
   ├────────► U5.4
   │
U2.1 → U2.2 → U2.3 → U2.5
   │              ↘ U5.3
   └→ U2.4 (design)

U3 ∥ U6 (after U0)
U4 after U1/U3 or on demand
U7 anytime (docs)
```

---

## Execution order (first delivery)

| PR | Tasks | Deliverable |
|----|-------|-------------|
| **PR-U0** | U0.1–U0.3 | Roadmap linked; baseline green |
| **PR-U1a** | U1.1 | Solana `blockTime` HostEnv real |
| **PR-U1b** | U1.2 + U1.6 | `selfAddress` + Product example |
| **PR-U2a** | U2.1–U2.3 | Crosscall stub honesty (docs+tests) |
| **PR-U5a** | U5.1 + U5.3 | Fragment map + exclude stub crosscall |
| Then | U1.3–U1.5, U3, U6.1–U6.2 | Fill / polish / platform |

**Start gate:** Land PR-U0, then execute **PR-U1a** unless product prioritizes U2 docs-only first.

---

## Gates / commands (living list)

| Area | Command |
|------|---------|
| Product primary | `just product` |
| Full static | `just check` (53 sub-recipes) |
| HostRuntime | `lake env lean --run Tests/HostRuntime.lean` |
| Portable default | `just portable-default` |
| Remote multi-target | `just portable-remote-call-multi-target` |
| Crosscall materialize | `just crosscall-materialize` (if present) / `Tests/CrosscallMaterialize.lean` |
| Solana light | `just solana-light` |
| NEAR target-first | `just near-target-first` |
| FV fragment | `just constructor-coverage-smoke` · `just counter-universal-refinement-smoke` |
| CLI target-first | `just cli-target-first` |

---

## Open product decisions

| ID | Decision | Options | Default until decided |
|----|----------|---------|------------------------|
| **D-U1-Random** | Solana portable randomness | Wire SlotHashes vs permanent reject | **Decided:** permanent reject + doc until SlotHashes HostEnv lower |
| **D-U1-Gas** | Portable gas/CU left | HostEnv on Solana/NEAR vs EVM-only | **Decided:** Solana HostEnv via `sol_remaining_compute_units`; NEAR permanent reject |
| **D-U1-TimeUnit** | Solana timestamp unit | seconds (Clock) vs ns (NEAR-like) | **Decided:** **seconds** (Clock.unix_timestamp) + note NEAR ns |
| **D-U2-Oracle** | IR real peer later? | Design-only vs implement mock | design-only in this roadmap |
| **D-U4-721** | onERC721Received | implement vs permanent skip | permanent skip until product asks |
| **D-U7-G1** | CosmWasm/Aptos M3 | schedule vs freeze | **freeze** |

---

## Status changelog

| Date | Note |
|------|------|
| 2026-07-09 | Roadmap created from full project audit + completed portable-sdk waves. First execution target: U0 then U1.1 Solana `blockTime`. HEAD baseline: `4ffa1f1f` honesty/CPI green `just check`. |
| 2026-07-09 | **U0 complete:** INDEX link; portable-sdk plan → Complete; `just product` green locally (`product: ok (matrix · counter · remote)`). Next: **PR-U1a** = U1.1 Solana HostEnv `blockTime`. |
| 2026-07-09 | **U1.3/U1.5/U1.6 done:** permanent HostEnv rejects documented; HostEnvProbe Shared example + product-matrix; Source.contractId export; `just product` green.
| 2026-07-09 | **U1.2 done (`83ed411b`):** Solana `contextRead.contractId` → sha256(program_id) limb0; HostEnv.selfAddress + Identity.self triad; HostRuntime/IRPortability/ChainAgnosticRoute green; `just product` ok. Next: U1.3 decision + U1.6 product example.
| 2026-07-09 | **U1.1 done (`ac12d18d`):** Solana `contextRead.timestamp` → `Clock.unix_timestamp`; `materializeEnv` triad `blockTime`; HostRuntime lower smoke; `isPortableEnv` derives triad (timestamp now portable-core). `lake build` + `just product` green. Next: **U1.2** Solana `selfAddress`. |

When a task completes: set Status to **done**, add commit hash in changelog.

---

## Agent handoff (how to “慢慢解决”)

1. One PR = one table row (or one PR-U* slice).
2. Never start U4 ecosystem depth if U1 HostEnv still blocks portable authors.
3. Never claim “formally verified compiler” outside FV tier + fragment (see `formal-verification.md`).
4. After each PR: `just product` minimum; touch Solana lower → also HostRuntime + relevant solana light smoke.
5. Update this file’s Status column in the same PR as the code.

---

## Self-review (plan quality)

| Spec / audit item | Task coverage |
|-------------------|---------------|
| HostEnv Solana blockTime/selfAddress holes | U1.1, U1.2 |
| IR crosscall sum stub | U2.* |
| Product remote / account inference | U3.* |
| EVM/Solana/NEAR ecosystem P1 | U4.* selective |
| FV-9 not universal | U5.* |
| CLI M4 / versioning / clients | U6.* |
| Spike backends / G1 freeze | U7.* |
| No silent drop / honesty | Global constraints + existing PortableHonesty |
| Product α–ε freeze | Global constraint 4 |
| New chains out of scope | Global constraint 5 + U7.3 |
