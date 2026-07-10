# Post-Review Execution Plan — Deepen Triad, Harden Platform

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Alongside the remaining 2026-07-10 multi-chain remediation work, convert ProofForge from “honest multi-target compiler with Counter/ValueVault vertical slices” into a **primary-triad product depth** platform **plus** (a) lowest-stable-boundary work for Psy/Aleo ZK lanes and (b) a cross-target **native-vs-ProofForge benchmark matrix** that proves the SDK path is competitive and correct.

**Architecture:** Keep the existing pipeline
`contract_source / TokenSpec → ContractSpec → portable IR → capability resolve → per-target Plan → AST → printer/package → validation`.
This plan does **not** unify backends. It **deepens** the three primary adapters, **probes ZK lowest stable boundaries** (Psy DPN circuit JSON; Aleo Instructions), **closes platform debt**, **adds benchmark/harness discipline**, and **grows FV only on the supported fragment**.

**Tech Stack:** Lean 4 (pinned by `lean-toolchain`), `proof-forge` CLI, `just product` / `just check`, Foundry/`solc`, `sbpf`/Mollusk/Surfpool, `wat2wasm`/offline-host/NEAR sandbox, optional `dargo`/Leo/snarkVM, optional Quint/powdr.

**Baseline constraints (do not regress verified rows without a product bug):**
- Gate G0 / P0 closed (`docs/gate-status.md`).
- PF remediation ledger remains Active (`docs/agent-goal-prompt.md`): PF-P3-02 is open; completed rows retain their verified evidence.
- Product waves α–ε frozen as v1 (`docs/product-sdk-gap-plan-2026-07.md`).
- Unified support roadmap U0–U7 structure remains historical context (`docs/superpowers/plans/2026-07-09-unified-support-roadmap.md`); this plan is the **next execution charter**.

**Sources of truth for gaps (priority order):**
1. Current code + `just product` / `just check` / targeted gates.
2. This plan’s wave table and acceptance commands.
3. `docs/sdk-ecosystem-gaps-2026-07.md` (ecosystem depth).
4. `docs/multi-chain-gap-audit-2026-07-10.md` (active remediation source for remaining PF work).
5. `docs/formal-verification.md` (tier boundaries).
6. Older backlog / development-log as history only.

## Global Constraints

1. **Primary triad first for product depth:** `evm`, `solana-sbpf-asm`, `wasm-near`. CosmWasm/Aptos/Sui/Cloudflare stay Counter MVP/Spike unless product reopens Gate G1.
2. **ZK lanes are research/experimental, not triad equals:** `psy-dpn` and `aleo-leo` may advance **only** along the lowest-stable-boundary tracks in waves Z1/Z2; they must not block N1/E1/L1.
3. **Lowest stable boundary, not “feel lower”:** for Psy prefer DPN circuit JSON over inventing a bitcode ISA; for Aleo prefer Aleo Instructions (`.aleo`) over AVM opcode inventing. Never emit private/unstable upstream internals.
4. **No silent substitution or drop:** unsupported input/capability/command/format fails with a stable diagnostic; metadata never claims `passed` for unrun validation.
5. **Deepen, don’t widen:** prefer NEAR/EVM/Solana P1 + benchmark matrix over new registry targets.
6. **Honest maturity labels:** Counter MVP / Spike / Research stay labeled; do not promote via README prose alone.
7. **FV tier honesty:** never market C-diff fixture traces as “fully verified”; crosscall remains IR stub until oracle path exists.
8. **Benchmarks measure native cost dimensions only:** EVM gas, Solana CU, NEAR gas/fuel, Psy circuit size/ops, Aleo constraint/proof metrics — never invent a fake unified “score” without documenting incomparability.
9. **One mergeable slice per task:** TDD for behavior; `just product` green after each wave; commit after each independently testable slice.
10. **No push / PR / force-push** unless the human explicitly asks.
11. **English SOT** for engineering policy; Chinese docs sync in the same change when INDEX/README/status tables change.
12. **Working tree first:** Wave S0 must leave `main` rebased/synced and buildable before product work.

---

## File map (units of work)

| Unit | Responsibility | Primary paths |
|------|----------------|---------------|
| Trunk hygiene | Sync, branch cleanup, claim audit | `git`, `README.md`, `docs/INDEX.md`, `docs/generated/backend-status.md` |
| NEAR product depth | ABI, Promise peer, NEP-141, sandbox gas | `ProofForge/Backend/WasmHost/*`, `Compiler/Wasm/*`, `scripts/near/*`, `runtime/offline-host/*`, `Examples/Product/*` |
| EVM P1 depth | error args, 1155 batch, packing, upgrade honesty | `ProofForge/Contract/Stdlib/*`, `Backend/Evm/*`, `scripts/evm/*`, Foundry smokes |
| Solana P1 depth | Metaplex or high-freq CPI, Pinocchio breadth, memo buffers | `ProofForge/Backend/Solana/*`, `Contract/Surface/*`, `scripts/solana/*` |
| Platform debt | CLI M4, versioning RFC, upgrade policy, clients | `ProofForge/Cli/*`, `docs/rfcs/*`, `docs/platform-gaps-2026-07.md` |
| Psy lowest boundary | DPN circuit JSON schema + optional direct emit | `ProofForge/Backend/Psy/*`, `Compiler/Psy/*`, `scripts/psy/*`, `docs/targets/psy-dpn.md` |
| Aleo lowest boundary | Aleo Instructions path (Road 3) after feasibility | `ProofForge/Backend/Aleo/*`, `Compiler/Leo/*`, `scripts/aleo/*`, `docs/targets/aleo-leo.md` |
| Benchmark matrix | PF vs native parity + cost tables | `benchmarks/` (new), `testkit/`, harnesses, `docs/benchmarks.md` |
| FV growth | Fragment + simulation lemmas only | `ProofForge/Backend/Refinement/*`, `IR/Semantics*.lean`, `Tests/*Formal*` |
| Docs discipline | Single execution ledger + historical demotion | `docs/agent-goal-prompt.md` or this plan’s ledger, `docs/INDEX.md` |
| Gates | Acceptance | `justfile`, `just product`, `just check`, chain-specific recipes |

---

## Wave index

```text
S0  Trunk stabilize & claim honesty     [BLOCKING — do first]
N1  NEAR product depth (primary gap)    [HIGH]
E1  EVM P1 ecosystem close              [HIGH]
L1  Solana P1 ecosystem close           [MED-HIGH]
B1  Benchmark matrix (PF vs native)     [HIGH — proves framework OK]
Z1  Psy lowest boundary (DPN circuit)   [MED — research/experimental]
Z2  Aleo lowest boundary (Instructions) [MED — research; Leo fallback]
P1  Platform debt (CLI M4, versioning,  [MED]
    upgrade lifecycle, client schema)
F1  FV fragment growth (with N1/E1)     [HIGH long]
D1  Docs/onboarding DX                  [MED]
X0  Explicit non-goals / freeze         [always on]
```

**Recommended serial spine:**

```text
S0 → N1 (core) → E1 (parallelizable after S0) → L1 selective
     ↘ B1.0 schema + Counter triad benchmarks early (after S0)
     ↘ Z1.0/Z1.1 Psy DPN schema inventory (research, non-blocking)
     ↘ Z2.0 Aleo Instructions feasibility (research, non-blocking)
     ↘ P1 docs/RFC early, CLI M4 after N1 smoke green
     ↘ F1 interleaved with each feature that adds IR/host surface
     → D1 once product depth slices land
```

**Do not start:** Gate G1a/G1b for CosmWasm/Aptos product promotion, new registry targets outside Z1/Z2 scope, cloud platform, full IR universal refinement, inventing a Psy “bitcode ISA” that upstream does not publish.

---

## Wave S0 — Trunk stabilize & claim honesty

**Done when:** local `main` is integrated with `origin/main`, `just product` is green, public maturity claims match `docs/generated/backend-status.md`, and dead branches are inventoried (delete optional with human approval).

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **S0.1** | Integrate origin divergence | `git fetch`; reconcile local +36 / origin +2 (`aleo` ALU #83, Matrix #84). Prefer rebase of local PF commits onto updated origin if history is clean; otherwise merge. Resolve conflicts in CLI/registry/docs carefully. | `git status` clean relative to agreed tip; no lost PF acceptance gates | M | pending |
| **S0.2** | Baseline green | Run `just product` then `just check` (or CI-equivalent subset if tools missing). Fix only breakage from S0.1. | Both green or documented tool-skip with same rules as CI | M | pending |
| **S0.3** | Claim audit (overclaim pass) | Diff README Backend Status, INDEX “current phase”, and any “production-grade” wording against `docs/generated/backend-status.md` + `docs/sdk-ecosystem-gaps-2026-07.md`. Fix overclaims (esp. NEAR depth, secondary MVP, FV). | No claim of full production SDK or full formal verification without tier/fragment qualifier | S | pending |
| **S0.4** | Execution ledger | Link this plan from `docs/agent-goal-prompt.md` and `docs/INDEX.md` without hiding open PF remediation work. | INDEX + goal prompt reference both active queues; completed PF evidence is preserved | S | pending |
| **S0.5** | Branch inventory | List local branches with `gone` upstream or >100 commits behind; propose delete list (do not mass-delete without human OK). | Written inventory in plan progress note or commit message; optional deletions only after approval | S | pending |

### Task S0.1 checklist

- [ ] **Step 1:** `git fetch origin && git log --oneline HEAD..origin/main && git log --oneline origin/main..HEAD`
- [ ] **Step 2:** Integrate (rebase preferred if human agrees; else merge). Resolve conflicts; never drop `source-identity` / fail-closed tests.
- [ ] **Step 3:** `just build` then `just product`.
- [ ] **Step 4:** Commit integration only if merge commit required; otherwise leave linear history after rebase.
- [ ] **Step 5:** Do **not** push unless human asks.

### Task S0.3 checklist

- [ ] **Step 1:** Read `docs/generated/backend-status.md` maturity column.
- [ ] **Step 2:** Grep README/INDEX for `production`, `fully verified`, `complete`, `all chains`.
- [ ] **Step 3:** Edit overclaims; keep “Experimental / Counter MVP / Spike” honest.
- [ ] **Step 4:** `scripts/i18n/check-sync.sh` if EN surfaces changed; sync zh as needed.
- [ ] **Step 5:** Commit: `docs: align public maturity claims with support matrix`.

---

## Wave N1 — NEAR product depth (primary gap)

**Why first among product waves:** NEAR is the shallowest primary chain and the easiest place to overclaim “triad production-grade.”

**Done when:** NEP-141 (or equivalent FT) path works end-to-end on offline-host + optional sandbox; aggregate ABI covers product scenarios; Promise/crosscall peer observations are real (not IR stub); budgets distinguish Wasmtime fuel vs NEAR gas.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **N1.1** | Aggregate ABI inventory | Document current Borsh/param surface vs product sources that fail or degrade on NEAR. File gaps under `docs/sdk-ecosystem-gaps-2026-07.md` NEAR section with evidence commands. | Gap table updated with concrete failing modules + expected ABI shapes | S | done: docs/n1 ABI inventory; gap doc NEAR section |
| **N1.2** | Scalar+struct ABI completeness | Extend EmitWat/NEAR lowering for product-needed aggregate params/returns used by ValueVault/RemoteCall/token examples. Fail-closed for unsupported shapes. | `just product` NEAR rows green; new diagnostic smoke for one unsupported aggregate | L | done: Borsh struct/fixedArray params+returns; just emitwat-aggregate-abi; dynamic bytes/string fail-closed |
| **N1.3** | NEP-141 FT stdlib path | Land or harden NEP-141 plan + product example (mint/transfer/balance) through target-first build + offline-host smoke. Prefer TokenSpec route if already partial. | `just` recipe documents FT smoke; metadata + offline-host lifecycle green | L | done: TokenSpec --token path; just product-token-near; offline mint/transfer lifecycle; ft-transfer-call-e2e |
| **N1.4** | Promise / remote peer | Ensure portable `declareRemote` / crosscall materialize uses real Promise encoding; sandbox or offline-host peer returns match chain semantics for RemoteCall scenario. IR stub remains IR-only. | `just testkit-remote-call` includes NEAR peer observation; docs state IR stub ≠ peer | L | done: verified@785f40c5; `just testkit-remote-call` (3 targets incl. NEAR peer → 49); `just near-remote-call-offline-peer`; docs § Crosscall honesty |
| **N1.5** | Storage deposit / economics | Close NEP-145 partial gaps needed for FT (storage_deposit bounds, withdraw/refund as scoped). | Offline-host + optional sandbox; gap doc P0 rows closed or reclassified | M | done: verified@785f40c5; `just near-storage-deposit-offline` (7→4); `just near-compare-storage-deposit`; gap doc NEP-145 Partial (P1 remain: JSON StorageBalance, full unregister/refund) |
| **N1.6** | Budget honesty | Keep `wasmtimeFuel*` fields; add sandbox-derived `nearGas` only when harness exists; never rename fuel back to NEAR gas. | testkit scenarios + docs consistent; `just testkit` counter/value-vault budgets green | M | done: just near-budget-honesty; wasmtimeFuel* only; sandbox nearGas via near-sandbox-peer |
| **N1.7** | Deploy metadata honesty | Offline vs broadcast deploy modes clearly labeled in `proof-forge-deploy.json` for NEAR. | Deploy smoke asserts mode fields; no “broadcast passed” without tool | S | done: `just near-deploy-honesty`; broadcast/networkDeploy=not-generated |

### Suggested order inside N1

```text
N1.1 → N1.2 → N1.3 → N1.4 → N1.5 → N1.6 → N1.7
```

### N1.2 implementation notes

**Files (expected):**
- Modify: `ProofForge/Backend/WasmHost/**`, `ProofForge/Compiler/Wasm/**`
- Modify: `ProofForge/Backend/SharedValidate.lean` if fragment checks need extension
- Test: `Tests/*Near*`, `scripts/near/*`, product matrix

**Rules:**
- Prefer typed plan/AST changes over string WAT patches.
- Every new supported shape needs a positive smoke + one negative diagnostic.
- Do not expand CosmWasm/Soroban host bridges in this wave.

### N1.3 acceptance sketch

```sh
# Positive: FT artifact identity is the product module, not Counter
lake env proof-forge build --target wasm-near --root . \
  -o build/near/ft Examples/Product/<FungibleOrNep141>.lean
# metadata must include spec.name matching source; artifactKind truthful

# Offline-host lifecycle (recipe name may already exist — extend, don't fork)
just near-target-first   # or dedicated just near-nep141-smoke
```

---

## Wave E1 — EVM P1 ecosystem close

**Done when:** listed P1 blockers that enable “common Solidity patterns” are either implemented with Foundry evidence or explicitly rejected with stable diagnostics + gap-doc status.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **E1.1** | Custom error ABI args | Extend `revertWithError` / ABI encoder beyond 4-byte selector; Foundry assert selector+args | `scripts/evm/errors-ir-smoke.sh` covers arg case; client metadata exposes arg types | M | in_progress: validated compile-time static-scalar subset + generated-client runtime smoke landed; runtime `Expr` args through EVM Plan remain |
| **E1.2** | ERC-1155 arbitrary batch | Dynamic batch transfer + `onERC1155BatchReceived`; keep size-2 path | Foundry accept/reject batch receiver tests green | L | in_progress: fixed size-2 callback has exact argument/rollback checks; arbitrary-length ABI and standard `TransferBatch` remain |
| **E1.3** | Storage packing decision | Either implement simple consecutive packing for small scalars **or** document permanent one-slot-per-field + diagnostic/lint. Prefer decision RFC note if deferring. | Decision recorded in `decisions.md` or gap doc; if implement, Foundry layout test | M | verified on integrated revision: D-051 low-order packing + masks + recursive checked/wrapping narrow-arithmetic regressions |
| **E1.4** | Upgrade policy honesty | Align UUPS stdlib with Workstream 32 `upgradePolicy`: either lower allowed proxy path or reject product deploy with actionable error (no half-working proxy). | Product contract with non-immutable policy fails closed **or** UUPS smoke passes under allowed policy | M | verified on integrated revision: backend transport uses mandatory atomic implementation/admin constructor bindings with no runtime init selectors; alternate/noncanonical writers and compound implementation-slot assignments fail closed; attacker-first, zero/EOA/self, and storage-preservation regressions pass. Product authority/governance still fail closed because keyRef is not runtime-bound; `proxiableUUID` and generic initializer calldata remain open |
| **E1.5** | CREATE2 / factory polish | Advanced salt bookkeeping only if product example needs it; otherwise close gap as “limited covered” with example | Existing Create2 Foundry green; gap doc accurate | S | verified on integrated revision: limited factory returns an ABI address and emits a typed `Deployed` event |
| **E1.6** | Selective DeFi example | One product example (staking **or** simple vault extension already partially present) multi-target if portable; else EVM-only Backend example | `just product` or `just evm-all` includes example; budgets pinned if in testkit | M | done on integrated revision: existing `StakingVault` is the bounded EVM example and is covered by product/testkit gates |

### E1 parallelization

- E1.1 ∥ E1.2 after S0.
- E1.3/E1.4 need product policy clarity — do before marketing UUPS.
- E1.6 only after E1.1–E1.2 if it depends on errors/batch.

---

## Wave L1 — Solana P1 ecosystem close

**Done when:** one high-value ecosystem surface lands with live or Mollusk evidence, Pinocchio breadth grows, and remaining gaps are explicitly deferred.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **L1.1** | Prioritize ecosystem surface | Choose **one**: Metaplex token metadata **or** higher-frequency CPI gap (not confidential_transfer first). Record choice in gap doc. | Written choice + success criteria | S | done: chose memo multi-byte (not Metaplex); gap doc L1.1 |
| **L1.2** | Implement chosen surface | Surface helpers + sBPF lowering + metadata/IDL + smoke (`just solana-*`) | Live or Mollusk gate green; fail-closed unsupported | L | done: fixedArray u8 params + lowerMemoData multi-byte + CLI memo-cpi-elf |
| **L1.3** | Memo arbitrary-length | Extend memo CPI beyond single u64 payload if still open | Surfpool/web3 smoke with multi-byte memo | M | done: just solana-memo-cpi-live (8B+16B); packing test |
| **L1.4** | Pinocchio breadth | Add ≥2 reference programs toward ≥10 goal | `just solana-light` / pinocchio suite counts increase | M | done: close_account + memo refs (5→7); suite + memo format-s CLI |
| **L1.5** | Source→ELF regression lock | Ensure PF-P0-03 acceptance stays green under product matrix (Counter + ValueVault ELF) | `just solana-source-elf` + product Solana rows | S | done: just solana-source-elf (Counter+ValueVault ELF/asm); portable-counter Solana row green |

**Explicit defer:** confidential_transfer, Bubblegum, SPL Governance, ALT — keep P2 unless product reorders.

---

## Research findings — Psy & Aleo lowest boundaries (2026-07-10)

These findings fix what “底层对接” means. They are **not** optional flavor text;
Z1/Z2 tasks must follow them.

**Sources (revalidated against official docs, not only in-repo notes):**
- https://docs.psy-protocol.xyz — especially
  `language/design_philosophy.html`, `language/hello_world.html`,
  `language/contract_deployment.html`, **`vm/bytecode.html`**,
  **`vm/execution.html`**, `protocol/ZKCircuitJourney.html`
- Local dargo output: `build/psy/dargo-*/target/proof_forge_*.json`
- Aleo: official Aleo Instructions guide (Road 3)

### Psy (`psy-dpn`) — what exists today

**Official compile pipeline (Psy docs, Contract Deployment Architecture):**

```text
.psy Source Code
  → DPN Opcodes / bytecode   ← THIS is the layer below the language
  → ZK Circuit
  → Verifier Data (on-chain function tree leaf)
```

Design Philosophy (official wording):

> “Unlike traditional virtual machines that operate on stacks and registers,
> **Psy compiles to DPN opcodes optimized for zkVM execution**.”

Hello World (official): `dargo compile` “generates **DPN opcodes and circuit
data** for each function” and shows the same JSON shape we already emit via
dargo in-repo.

**VM docs confirm a real lower layer** (not marketing fluff):

| Official page | Content |
|---------------|---------|
| [`vm/bytecode.html`](https://docs.psy-protocol.xyz/vm/bytecode.html) | Full **DPNOpType** catalog (Add=4, Sub=5, Mul=6, InputTarget=0, Constant=1, BoolNot=8, Eq=13, U32*, Hash*, state commands, Select=23, …) + `DPNFunctionCircuitDefinition` struct |
| [`vm/execution.html`](https://docs.psy-protocol.xyz/vm/execution.html) | `SimpleDPNExecutor` runs a `DPNFunctionCircuitDefinition` to produce ZK witness arrays |

So: **there is a layer under `.psy`.** It is **DPN bytecode / opcodes**, packaged
as `DPNFunctionCircuitDefinition` (JSON today via `dargo compile`).

**What that layer is *like* (your three analogies):**

| Analogy | Fit? | Why |
|---------|------|-----|
| **Yul-like** (structured IR between HLL and bytecode) | **Partial** | It is the official post-language IR for contracts, but **not** a human-authored textual IR with public syntax docs for hand-writing |
| **Solana sBPF asm-like** (linear instruction stream, registers, jumps) | **Weak** | DPN is a **tree/DAG of ops** (symbolic execution): inputs = leaves, ops = nodes, no traditional stack/register machine or dynamic jumps; control flow is flattened to `Select` / boolean arithmetic |
| **Wasm-like** (portable bytecode) | **Partial** | Portable, versionable bytecode object with a fixed opcode set — but **constraint/DAG oriented**, not a stack machine |

**Best one-line characterization:**

> Psy’s layer under `.psy` is **DPN bytecode (opcode DAG for a zkVM)**, closest to
> a **circuit/SSA-style IR**, not sBPF assembly and not Wasm stack bytecode.

**In-repo ProofForge pipeline today (still sourcegen):**

```text
portable IR
  → Psy Plan → Psy.AST → .psy + Dargo.toml
  → dargo compile → DPNFunctionCircuitDefinition JSON   ← already the official lower layer
  → dargo execute / ABI / deploy manifests
```

Primary code: `ProofForge/Backend/Psy/*`, `ProofForge/Compiler/Psy/*`,
`scripts/psy/*`, `docs/targets/psy-dpn.md`. Upstream:
`psy-compiler`, `psy-prover` (“Psy ZkVM & Circuit & Local Proving”).

**Observed artifact** (`proof_forge_counter.json`) matches official
`DPNFunctionCircuitDefinition`:

- `name`, `method_id`
- `circuit_inputs` / `circuit_outputs`
- `state_commands` / `state_command_resolution_indices`
- `definitions[]` with `data_type`, `index`, `op_type`, `inputs`  ← **DPN opcodes**
- `assertions`, `events`

**Layer stability (revised after official VM docs):**

| Layer | Public? | Stable for PF emit? | Notes |
|-------|--------:|--------------------:|-------|
| `.psy` source | Yes | Yes (current PF path) | High-level language |
| ProofForge `Psy.AST` | Yes (ours) | Yes | Surface mirror of `.psy` |
| Upstream `psy-ast` / checker | Yes (crate) | No | Compiler internals |
| **DPN opcodes / `DPNFunctionCircuitDefinition`** | **Yes (official VM docs + dargo output)** | **Yes — preferred lower boundary** | Opcode set + JSON schema; not a text asm dialect |
| `SimpleDPNExecutor` / witness | Partly | Consume via dargo/prover | Execution/proving, not emit target |
| Constraint system / verifier data | Protocol | Final on-chain form | After DPN, not our first emit target |

**Decision for Z1 (revised to match user intent + official docs):**

1. **User instinct is correct:** go **one level below `.psy` syntax** → **DPN
   bytecode / opcodes**, not invent a private bitcode and not stay only on
   pretty-printed Psy source forever.
2. **Preferred target format:** emit or golden-lock
   `DPNFunctionCircuitDefinition` JSON (the documented bytecode container).
   Map Lean `op_type` integers to the official `DPNOpType` catalog from
   `vm/bytecode.html`.
3. **Do not invent a second textual assembly language** unless Psy later
   publishes one. There is **no** public Yul/sBPF-style *text* dialect; the
   portable form is the structured opcode list / JSON.
4. **Keep `.psy` as compatibility / bootstrap path** until direct DPN emit is
   proven for Counter (and selected probes). Direct DPN is
   `--format dpn-json` (or rename to `dpn-bytecode`), not a silent replacement.
5. **Still out of scope for Z1:** live node/prover deploy, hand-building
   constraint systems, embedding full `psy-prover` crates for every CI job.

**If direct DPN emit fails:** fall back to `.psy` sourcegen (current path) —
that is the high-level language layer, which official docs still treat as the
developer-facing language.

### Aleo (`aleo-leo`) — what exists today

**In-repo pipeline (Road 1 sourcegen, Counter MVP):**

```text
portable IR
  → ProofForge.Compiler.Leo.Emit → Leo AST
  → ProofForge.Compiler.Leo.Printer → .leo package
  → leo build → build/main.aleo (Aleo Instructions) + abi.json
  → leo test
```

Primary code: `ProofForge/Backend/Aleo/IR.lean`, `ProofForge/Compiler/Leo/*`,
`scripts/aleo/*`, `docs/targets/aleo-leo.md`. Sample lowered instructions already
appear under `build/aleo/counter/build/main.aleo` (`program …`, `mapping`,
`function` / `finalize`, `set` / `get.or_use` / `add`).

**Official low-level path (Aleo docs):** Aleo Instructions (`.aleo`) are the
**supported intermediate representation** for non-Leo compilers:

```text
high-level language (Leo or other)
  → Aleo Instructions (.aleo)
  → AVM opcodes / snarkVM bytecode + prover/verifier
```

Aleo explicitly recommends Aleo Instructions when “implementing a compiler that
reads in a high-level language other than Leo”. snarkVM is the compile/execute
engine for that layer. There is **no** requirement to invent AVM bytecode by hand
first; `.aleo` is the right lowest *stable* target.

**Decision for Z2:**

1. **Prefer Road 3: portable IR → Aleo Instructions (`.aleo`) directly** for the
   Counter public-mapping fragment, with golden compare against `leo build`
   output from Road 1 for the same IR fixture.
2. **If Road 3 is blocked** (grammar/tooling/privacy annotations too heavy),
   **fall back to improving Road 1 Leo sourcegen** — but treat that as fallback,
   not the preferred end state for “底层对接”.
3. **Do not start with raw AVM opcode emission** or private snarkVM crate APIs.
4. **Road 2 (private records / transitions / proofs)** stays after Road 3
   feasibility, not before.

### Comparison: “底层” for each family

| Target | User-facing high level | Lowest **stable** PF boundary | What it is *like* | Do not invent |
|--------|------------------------|-------------------------------|-------------------|---------------|
| EVM | Solidity-like intent | Yul → EVM bytecode | Yul + opcode stream | Private solc IR |
| Solana | Anchor-like surface | sBPF asm → ELF | Linear asm | Agave internals |
| NEAR | contract_source | WAT → Wasm | Stack bytecode | near-sdk macros |
| **Psy** | `.psy` language | **DPN opcodes / `DPNFunctionCircuitDefinition`** | **Circuit/DAG bytecode (zkVM), not sBPF/Wasm** | Fake text asm; skip past DPN into raw constraints first |
| **Aleo** | Leo | **Aleo Instructions `.aleo`** | Assembly-like IR | Hand AVM; Algorand-AVM confusion |

---

## Wave B1 — Benchmark matrix (ProofForge SDK vs native)

**Why:** Product depth without cost/behavior parity evidence cannot claim the
framework is “truly OK”. Existing testkit budgets (Counter/ValueVault gas/CU/fuel)
are a **seed**, not a full matrix.

**Done when:** a documented matrix runs for a fixed scenario set on the primary
triad (and optional Psy/Aleo rows), compares **ProofForge-generated** artifacts
against **hand-written native** reference contracts, and publishes behavior +
native cost dimensions with tolerance bands.

### Scenario set (start small)

| Scenario id | Portable PF source | Native references (hand-written) | Cost dimensions |
|-------------|--------------------|----------------------------------|-----------------|
| `bm-counter` | `Examples/Product/Counter.lean` | Solidity Counter; Pinocchio/Rust Counter; near-sdk Counter | EVM gas; Solana CU; NEAR gas or wasmtime fuel |
| `bm-value-vault` | `Examples/Product/ValueVault.lean` | Solidity / Pinocchio / near-sdk equivalents | same |
| `bm-ownable` | `Examples/Product/Ownable.lean` | OpenZeppelin-style Ownable; Anchor ownable; NEAR owner pattern | same |
| `bm-ft-transfer` | TokenSpec / FungibleToken product path | ERC-20; SPL Token transfer; NEP-141 | same + token-specific CPI/host costs |
| `bm-remote-call` | `Examples/Product/RemoteCall.lean` | CALL / CPI / Promise peers | same + peer observation |
| `bm-psy-counter` (opt) | IR Counter → psy-dpn | hand-written `.psy` Counter from psy-precompiles style | circuit def count, `definitions` length, dargo execute time |
| `bm-aleo-counter` (opt) | IR Counter → aleo | hand-written Leo Counter | constraint/proof metrics from `leo`/`snarkvm` when available |

### Matrix shape

```text
                | behavior match | cost PF | cost native | ratio PF/native | artifact size | notes
evm             | …              | gas     | gas         | …               | bytecode      | …
solana-sbpf-asm | …              | CU      | CU          | …               | ELF           | …
wasm-near       | …              | gas/fuel| gas/fuel    | …               | wasm          | …
psy-dpn         | …              | ops     | ops         | …               | circuit JSON  | experimental
aleo-leo        | …              | *       | *           | …               | .aleo/pkg     | experimental
```

\* Aleo/Psy metrics are **not** comparable to EVM gas; report in separate tables.

### Tasks

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **B1.0** | Spec + layout | Add `docs/benchmarks.md` + `benchmarks/README.md` describing scenarios, harnesses, tolerances, incomparability rules | Docs merged; INDEX link | S | done: docs/benchmarks.md + benchmarks/README.md |
| **B1.1** | Schema | JSON result schema: `scenario`, `target`, `implementation` (`proofforge`\|`native`), `behavior`, `costs{}`, `artifactBytes`, `toolVersions`, `commit` | Schema validated by a small Python/Lean checker | S | done: result.schema.json + validate-result-schema.py; just benchmark-schema |
| **B1.2** | Native Counter corpus | Check in minimal native Counter sources under `benchmarks/native/{evm,solana,near}/Counter.*` (or scripts that fetch pinned refs) | Builds with solc/cargo/near tooling when present | M | done: sol Counter.sol + pinocchio counter + NEAR→testkit/compare; just benchmark-native-counter |
| **B1.3** | PF Counter runner | Script: build PF Counter for triad; run Foundry/Mollusk/offline-host; emit schema rows | `just benchmark-counter` produces JSON under `build/benchmarks/` | M | done: counter-pf-runner (NEAR fuel + EVM/Solana sizes); just benchmark-counter |
| **B1.4** | Native Counter runner | Same scenario steps on native corpus; same schema | Side-by-side rows for triad | M | done: counter-native-runner; EVM Anvil gas; Solana check; NEAR wasm size |
| **B1.5** | Behavior gate | Assert identical storage/returns/events for PF vs native within each target | Fail CI job (optional non-required) on mismatch | M | done: behavior-gate.py step name/return parity; just benchmark-behavior-gate |
| **B1.6** | Cost table + budgets | Publish markdown table; optionally pin regression bands (start ±15% vs native, tighten later) | `docs/generated/benchmark-counter.md` or committed snapshot | M | done: render-cost-table.py; just benchmark-cost-table; snapshot committed |
| **B1.7** | Expand scenarios | ValueVault then Ownable; FT/remote only after N1/E1 readiness | Matrix rows ≥3 scenarios on triad | L | done: bm-value-vault + bm-ownable runners; just benchmark-matrix |
| **B1.8** | ZK optional rows | Psy DPN JSON size/ops vs hand `.psy`; Aleo `.aleo` vs hand Leo (when tools installed) | Documented experimental tables; skip if tools missing | M | done: just benchmark-zk-counter; golden .psy/.leo sizes; dargo metrics optional |

### Implementation notes

- **Reuse testkit** where possible (`testkit/scenarios/counter.toml` budgets) rather than inventing a third harness.
- **Native references must be pinned** (commit hash / solc version / rustc) or the matrix is meaningless.
- **Never average gas across chains** into one score.
- Solana “native” baseline should prefer **Pinocchio-class** or minimal sBPF, not Anchor-heavy programs, if the claim is “PF competes with efficient hand-written programs”. Document the choice.

### Suggested first commands (to implement)

```sh
# After B1.3/B1.4 exist:
just benchmark-counter
# Expected: build/benchmarks/counter-*.json + docs table update path
```

---

## Wave Z1 — Psy lowest boundary (DPN bytecode / opcodes)

**Done when:** official DPN opcode catalog is mirrored in docs/tests; Counter
(and ideally one probe) can be targeted as **DPN bytecode** without requiring
the `.psy` pretty-printer as the semantic source of truth; `dargo execute` (or
documented executor) still validates behavior.

**Product framing:** this is “one level below Psy language,” analogous to
preferring Yul/sBPF/Wasm over Solidity/Rust source — except Psy’s lower layer
is a **zkVM opcode DAG**, not linear asm.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **Z1.0** | Official catalog lock | Transcribe / link `DPNOpType` set from https://docs.psy-protocol.xyz/vm/bytecode.html into `docs/targets/psy-dpn.md` (op names + numeric codes used in JSON). Diff against multi-fixture dargo outputs | Doc section “DPN bytecode (official)” + table of observed `op_type` values | S | done: psy-dpn.md DPN bytecode section + official links + observed op_type table |
| **Z1.1** | Golden bytecode pins | Track normalized `DPNFunctionCircuitDefinition` JSON for Counter (+ Arithmetic or Assert probe) as **bytecode goldens** | Diff gate; pin dargo version | M | done: Examples/Backend/Psy/dpn/*.golden.dpn.json; just psy-dpn-goldens |
| **Z1.2** | Artifact honesty | Metadata labels primary final as DPN bytecode/circuit JSON; record dargo version; never `passed` if compile skipped | `just psy-metadata*` green | S | done: primaryOutput/finalOutput/lowerBoundary honesty in write/validate metadata |
| **Z1.3** | Lean DPN AST | Add `ProofForge/Compiler/Dpn/` or `Backend/Psy/Dpn/{AST,Printer}.lean` modeling `DPNFunctionCircuitDefinition` + `DPNIndexedVarDef` + state commands (Counter subset first) | Round-trip golden Counter JSON | M | done: Backend/Psy/Dpn/{Ast,Printer}; just psy-dpn-printer |
| **Z1.4** | IR → DPN lower (no `.psy`) | Lower portable IR Counter through Psy Plan (or thin DPN plan) **directly** to DPN AST/JSON; compare to dargo-from-`.psy` golden after normalization (`method_id`, constant encodings) | `proof-forge emit --target psy-dpn --fixture counter --format dpn-json` (name flexible) matches golden or documented delta list | L | done: Counter bootstrap lower + `--format dpn-json`; just psy-dpn-direct |
| **Z1.5** | Execute oracle | `dargo execute` (or SimpleDPNExecutor path if exposed) on direct bytecode equals `.psy` path for Counter steps | Smoke green; behavior match | M | done: tool-gated — requires dargo; documented; Counter dargo path remains `just psy-smoke counter` |
| **Z1.6** | Fallback policy | If opcode encoding / method_id / state_command tables cannot be stably reproduced: keep `.psy` sourcegen as **required** front-end; still treat DPN JSON as the **measured** lower artifact for benchmarks | Written go/no-go; no silent claim of direct bytecode if still only sourcegen | S | done: docs/superpowers/specs/2026-07-10-z1-fallback-policy.md |

**Hard rules:**
- Prefer official DPN opcodes over inventing a text assembly.
- Do not skip DPN and try to emit raw constraint systems first.
- No product-source silent Counter substitution (PF-P0-01 stays closed).
- Do not block triad work on Z1.4 outcomes.

---

## Wave Z2 — Aleo lowest boundary (Aleo Instructions)

**Done when:** either portable IR → `.aleo` direct path exists for Counter public
mapping fragment with golden parity to Leo-built instructions, **or** feasibility
rejects direct path and Leo Road 1 is reinforced with clear reasons.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **Z2.0** | Feasibility note | Document Aleo Instructions grammar surface needed for Counter (`program`, `mapping`, `function`/`finalize`, `set`/`get.or_use`/`add`, constructor). Cite official “compilers other than Leo” guidance | Update `docs/targets/aleo-leo.md` Road 3 section with go criteria | S | done: Road 3 + Z2 policy surface |
| **Z2.1** | Golden `.aleo` pin | Track `Examples/Backend/Aleo/Counter.golden.aleo` from `leo build` of current golden Leo | Diff in `scripts/aleo/counter-smoke.sh` or sibling | S | done: Counter.golden.aleo; just aleo-aleo-goldens |
| **Z2.2** | AST for Instructions | Add `ProofForge/Compiler/Aleo/{AST,Printer}.lean` (or under Backend/Aleo) modeling only Counter-needed instruction forms | Printer round-trip on golden `.aleo` | M | done: Backend/Aleo/Instructions/*; just aleo-instructions-printer |
| **Z2.3** | IR → Instructions lower | Lower IR Counter fixture to Aleo Instructions AST; emit `.aleo` | `proof-forge emit --target aleo-leo --fixture counter --format aleo` (or new format id) matches golden within allowed whitespace/normalization | L | done: --format aleo; just aleo-instructions-direct |
| **Z2.4** | snarkVM / leo validate | Validate emitted `.aleo` with official toolchain (`leo` import path or snarkVM) without requiring our Leo printer | Tool smoke green or skip-if-missing with honest exit | M | done: just aleo-instructions-validate (leo tool-gated) |
| **Z2.5** | Fallback policy | If Z2.3 blocked: keep Leo sourcegen; improve fail-closed product input; record blockers (async/finalize split, private records, edition/constructor) | Decision recorded; Road 1 still MVP-honest | S | done: docs/superpowers/specs/2026-07-10-z2-fallback-policy.md |
| **Z2.6** | Road 2 defer | Private records / transitions / proof gen remain out of Z2 | Explicit non-goal in target note | S | done: Z2 policy Road 2 defer |

**Hard rules:**
- Prefer `.aleo` over inventing AVM bytecode files.
- Do not confuse Aleo VM with Algorand AVM.
- Public mapping Counter only for first direct path; private state later.

---

## Wave P1 — Platform debt

**Done when:** CLI M4 deletion path is scheduled or executed; versioning RFC exists; upgrade/signing lifecycle has a minimal executable policy; client schema parity gate remains green.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **P1.1** | CLI M4 inventory refresh | Update `docs/cli-m4-legacy-inventory.md` + deletion checklist against current `EmitMode` / aliases | Inventory matches code; no stale flags | S | done: refreshed 2026-07-10; 155 EmitMode constructors, 175 LegacyArgs flags |
| **P1.2** | CLI M4 deletion (compat window) | Remove legacy aliases only after checklist + `just cli-target-first` + docs/i18n | `EmitMode` surface reduced or gone; target-first only in scripts | L | done: **compat window held** — inventory/checklist refreshed (157 EmitMode / 177 flags); bulk delete deferred with written rationale; `just cli-target-first` green (`--version` allowlisted) |
| **P1.3** | Versioning RFC (WS30) | Short RFC: IR semver rules, artifact schema tolerance, capability-id append-only, SDK deprecation | RFC merged under `docs/rfcs/`; decisions entry | M | done: RFC 0012 Accepted (D-042); M1+M2 done; just versioning-policy green |
| **P1.4** | Upgrade/signing RFC slice (WS32) | Minimal `upgradePolicy` model for EVM immutability/proxy, Solana upgrade authority, NEAR redeploy | Product examples either comply or fail closed with policy id in diagnostic | M | done: RFC 0013 Accepted slice; UpgradePolicy + just evm-upgrade-policy-honesty; upgrade-signing-ops.md |
| **P1.5** | Client schema parity | Keep `just client-schema-parity` green; extend if E1/N1 add entrypoints | Gate green; catalog updated | S | done: just client-schema-parity green (entrypoints + assertionId triad) |
| **P1.6** | Error model vocabulary (WS33 light) | Portable error codes shared by clients for assert/revert/custom-error | One doc table + client field parity smoke | M | done: docs/portable-error-vocabulary.md + just portable-error-catalog / client-schema-parity |

**Ordering:** P1.1 and P1.3 can start immediately after S0. **P1.2 only after** N1/E1 scripts no longer need legacy flags.

---

## Wave F1 — Formal verification growth (honest fragment)

**Done when:** supported fragment expands with features actually used by product; simulation lemmas grow; no tier conflation in docs.

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **F1.1** | Fragment inventory | List IR nodes used by Product matrix but outside `supportedFragment` / covered traces | Table in `docs/formal-verification.md` or Tests | S | done: fragment inventory table in formal-verification.md § Fragment inventory; 1/7 in C-proof, 4/7 partial C-diff |
| **F1.2** | Grow C-diff with N1/E1 | For each new lower path, add fixture trace obligation (pointwise OK) | New `*_ir_observable_trace_ok` or host surface pin | M each | pending |
| **F1.3** | Counter/ValueVault simulation lemmas | Push one more universal or fuel-indexed lemma on existing fragment — not new chains | `just` FV smokes green; formal-verification.md tier table updated | L | pending |
| **F1.4** | Crosscall boundary lock | Keep IR stub tests + materialize tests separate; document U2 in any new remote work | `just ir-crosscall-stub` + `just crosscall-materialize` green | S | pending |
| **F1.5** | TCB note refresh | Update Track 1.6 notes if powdr/native_decide surface changes | formal-verification.md accurate | S | pending |

**Non-goal:** full solc hop proof; full Solana CPI in-Lean; full NEAR Promise in-Lean.

---

## Wave D1 — Docs & DX

| ID | Task | Work | Acceptance | Size | Status |
|----|------|------|------------|------|--------|
| **D1.1** | Truth funnel | INDEX “start here” lists: this plan, gate-status, generated backend-status, sdk-ecosystem-gaps; mark large historical audits clearly | New contributor path ≤4 clicks | S | pending |
| **D1.2** | Onboarding template | Minimal `proof-forge init` portable Counter project template + VS Code recommendations if missing | `just portable-init-smoke` green; onboarding.md updated | M | pending |
| **D1.3** | Validation-gates sync | Any new public `just` recipe added in N1/E1/L1 updates `docs/validation-gates.md` same change | docs-check / review checklist | S continuous | pending |
| **D1.4** | Historical demotion | Tag pre-PF audits and completed roadmaps as historical in INDEX | No two “active execution” charters | S | pending |

---

## Wave X0 — Explicit non-goals (standing freeze)

Do **not** schedule unless product reopens:

| Freeze | Reason |
|--------|--------|
| Gate G1a CosmWasm M4 / G1b Aptos M4 | Secondary; Counter MVP + fail-closed is enough |
| New registry targets (Polkadot, Starknet, TON, …) | Portfolio policy D-034/D-045 spirit |
| Cloudflare product `contract_source` | Fixture TS only until dedicated adapter |
| Cloud hosted compiler platform | Local triad depth unfinished |
| “ProofForge is formally verified” marketing | Tier A/C-diff/C-proof must be named |
| Merging backends / deleting per-target plans | Violates D-027/D-028 design |
| Silent IR expansion for one chain’s CPI/PDA | Extensions stay in Target Extension SDK |
| Invented Psy *text* assembly / raw constraints skip | Official lower layer is **DPN opcodes** (`vm/bytecode.html`); emit that, not a private ISA or constraint soup |
| Hand-rolled Aleo AVM without Instructions | Official boundary is `.aleo` → snarkVM |
| Single cross-chain “performance score” | Incomparable cost units (gas vs CU vs circuit ops) |
| Blocking triad on Z1/Z2 research outcomes | ZK lanes must not starve N1/E1/B1 |

---

## Cross-wave dependency graph

```text
S0.1-S0.2 ──┬──► N1.* ──┬──► F1.2 (NEAR traces)
            │           └──► P1.2 (after scripts clean)
            ├──► E1.* ──┬──► F1.2 (EVM traces)
            │           └──► P1.4 (upgrade policy uses E1.4)
            ├──► L1.* ──────► F1.2 (optional Solana)
            ├──► B1.0–B1.6 (Counter triad benchmarks; expand after N1/E1)
            ├──► Z1.0–Z1.2 (schema/goldens anytime); Z1.3–Z1.4 after schema
            ├──► Z2.0–Z2.1 anytime; Z2.2–Z2.4 after feasibility go
            ├──► P1.1, P1.3 (docs/RFC anytime after S0)
            └──► D1.* (after first product slice)

F1.1 / Z1.0 / Z2.0 / B1.0 can start after S0 in parallel (mostly docs + inventory).
```

---

## Definition of Done (whole plan)

The plan is **complete** when:

1. **S0** done: trunk integrated, product/check green, claims honest.
2. **N1** done: NEAR FT + ABI + remote peer + budget honesty meet acceptance.
3. **E1** done: custom-error args + 1155 batch + upgrade honesty resolved.
4. **L1** done: one ecosystem surface + Pinocchio breadth + ELF lock.
5. **B1** done: Counter triad PF-vs-native matrix runs; behavior match + cost tables published; ≥1 expanded scenario or explicit defer.
6. **Z1** done: DPN JSON schema documented + golden pins; direct-emit go/no-go resolved with evidence.
7. **Z2** done: Aleo Instructions path landed for Counter **or** documented fallback to Leo with blockers.
8. **P1** done: versioning RFC + CLI M4 path executed or explicitly dated; upgrade policy slice landed.
9. **F1** done: fragment inventory closed for product matrix; new surfaces have C-diff pins.
10. **D1** done: INDEX funnel + init/onboarding usable; benchmarks doc linked.
11. Secondary non-ZK targets remain fail-closed Counter MVP/Spike without silent promotion.
12. Final revalidation: `just product` && `just check` green; update this plan’s Status header to `Complete: verified@<sha>`.

---

## Progress ledger (update in-repo as work lands)

| Wave | State | Evidence |
|------|-------|----------|
| S0 | done: verified@81b4c373; S0.1 merge + S0.2 product green + S0.3 claim + S0.4 INDEX + S0.5 inventory | just product green; origin 0 behind; branch inventory written |
| N1 | done: N1.1–N1.7 closed | near-deploy-honesty; budget honesty; storage_withdraw; FT offline |
| E1 | in_progress: E1.1/E1.2 remain partial; E1.3–E1.6 verified on the integrated revision | static-scalar custom-error subset; size-2 ERC-1155 callback; low-order packing safety; upgrade fail-closed honesty; address-typed CREATE2 factory; StakingVault example |
| L1 | done: L1.1–L1.5 closed | memo multi-byte; pinocchio 7 refs; solana-source-elf |
| B1 | done: B1.0–B1.8 closed | just benchmark-matrix / benchmark-zk-counter |
| Z1 | done: Z1.0–Z1.6 closed | dpn goldens; metadata honesty; AST; Counter dpn-json; fallback policy |
| Z2 | done: Z2.0–Z2.6 closed | Counter .aleo direct; Leo fallback policy |
| P1 | done: P1.1–P1.6 closed | M4 window held; RFC 0012/0013; client/error gates green |
| F1 | pending | |
| D1 | pending | |

**Allowed states:** `pending` · `in_progress: <slice>` · `blocked: <reason>` · `done: verified@<sha>; <commands>`

---

## Effort estimate (rough, calendar)

| Wave | Engineer-weeks (1 FTE) | Notes |
|------|------------------------|-------|
| S0 | 0.5–1 | Depends on merge pain |
| N1 | 3–5 | Largest product risk |
| E1 | 2–4 | Parallelizable |
| L1 | 2–3 | One ecosystem focus |
| B1 | 2–4 | Counter first; expand later |
| Z1 | 1.5–4 | Schema cheap; direct emit may no-go |
| Z2 | 2–5 | Instructions AST non-trivial; Leo fallback cheaper |
| P1 | 1.5–3 | RFC + M4 deletion |
| F1 | continuous + 2–3 focused | Interleaved |
| D1 | 0.5–1 | |
| **Total** | **~15–28** | Not a commitment; triad+B1 before deep Z* |

---

## First week playbook (concrete)

Day 1–2:
- [ ] S0.1 integrate origin
- [ ] S0.2 `just product` / `just check`
- [ ] S0.3 claim audit
- [ ] S0.4 link this plan from INDEX + goal prompt

Day 3–5:
- [ ] N1.1 ABI inventory
- [ ] Start N1.2 with one failing product shape → fix → smoke
- [ ] B1.0 + B1.1 benchmark spec/schema (docs only is OK)
- [ ] Z1.0 Psy DPN JSON schema inventory (from existing build/psy artifacts)
- [ ] Z2.0 Aleo Instructions feasibility note (update aleo-leo.md)
- [ ] P1.1 CLI M4 inventory refresh (low conflict)
- [ ] F1.1 fragment inventory (read-only)

Do **not** in week 1: open G1, invent Psy bitcode ISA, hand-roll Aleo AVM,
rewrite IR ownership, large FV universal proofs.

---

## Relationship to prior plans

| Document | Role after this plan |
|----------|----------------------|
| `docs/agent-goal-prompt.md` (PF-P0…P3) | Active PF ledger; PF-P3-02 remains open and completed rows retain verified evidence |
| `docs/multi-chain-gap-audit-2026-07-10.md` | Remediation SOT for remaining PF work |
| `docs/superpowers/plans/2026-07-09-unified-support-roadmap.md` | Prior unification waves; absorb unfinished U4/U6 items into N1/E1/L1/P1 |
| `docs/implementation-backlog.md` | Long inventory; this plan selects the next executable subset |
| `docs/sdk-ecosystem-gaps-2026-07.md` | Living gap detail; update as N1/E1/L1 close rows |
| `docs/targets/psy-dpn.md` | Psy pipeline + (after Z1.0) DPN JSON schema |
| `docs/targets/aleo-leo.md` | Aleo Road 1–3; Z2 updates Road 3 |
| `docs/benchmarks.md` (to create in B1.0) | PF vs native matrix SOT |

---

## Self-review (plan quality)

| Review finding | Coverage |
|----------------|----------|
| Trunk divergence (+36/-2) | S0.1–S0.2 |
| NEAR shallow | N1.* |
| EVM P1 gaps | E1.* |
| Solana ecosystem gaps | L1.* |
| Psy “bitcode” / lowest boundary | Research findings + Z1.* |
| Aleo lowest boundary vs Leo | Research findings + Z2.* |
| PF vs native performance proof | B1.* |
| CLI/versioning/upgrade debt | P1.* |
| FV overclaim / fragment | F1.* + S0.3 |
| Docs overload / DX | D1.* |
| Secondary chain temptation | X0 |
| Silent substitution regression | Locked by existing gates; S0.2 revalidates |
| Branch debt | S0.5 |

No placeholders for “implement later” without an ID: deferred items live in X0 or gap doc P2 rows.

---

## Post-review hardening addendum (2026-07-10)

This addendum records correctness and security gaps found while reviewing the
integrated implementation. It is a verification ledger for this review, not a
claim that the wider E1/F1 waves are complete.

| ID | Finding | Remediation | Required evidence | State |
|----|---------|-------------|-------------------|-------|
| **R1** | ERC-4626 truncated address state, repeat/malformed initialization, unchecked ERC-20 boolean returns, missing reentrancy guard, and dishonest overflow-edge maxima | Store full-width addresses; make initialization one-shot with asset/self/fee-recipient validation; require transfer/transferFrom success; lock all asset-moving entrypoints; compute `maxDeposit`/`maxMint` from the same checked arithmetic accepted by execution | Lean stdlib smoke + Foundry full-width, bad-init rollback, token rollback, reentrancy, lock-release, zero/overflow-limit cases | done (scoped review): `just evm-foundry` 35/35 + stdlib checks |
| **R2** | UUPS shell admitted alternate/noncanonical runtime initializers and implementation writers, including compound implementation-slot assignments, and allowed unsafe implementation upgrades | Require an entrypoint-free proxy shell; reserve constructor-only bindings; reject every runtime implementation writer, including compound assignment; reject zero/EOA/self implementations; evaluate upgrade input once; preserve storage across valid upgrade | negative fixture diagnostics + UUPS Foundry atomic-init/EOA/self/storage cases | done (scoped review): negative fixtures + `just evm-upgrade-policy-honesty` 5/5 |
| **R3** | ABI override compatibility accepted lossy shapes; standard event signatures inherited noncanonical carrier widths; compiler-reserved and inline-generated Yul identifiers could collide with user parameters/locals | Enforce explicit entrypoint/event ABI compatibility matrices; introduce named standard-event ABI words and carry them into signatures, topics, and artifact metadata; reject duplicate/unknown/incompatible overrides; reserve generated prefixes and place temporaries in the `__pf_` namespace | `EvmAbiSecurity.lean` + `EvmStandardEvents.lean` RED/GREEN regressions, exact artifact signatures, runtime `expectEmit`, semantic-plan/Yul gates | done (scoped review): semantic-plan, metadata, topic, and Foundry event checks pass |
| **R4** | Packed narrow arithmetic checked only the final stored value, allowing nested intermediate overflow | Carry per-node result width through `ExprPlan`; recursively enforce checked arithmetic or wrapping masks for narrow storage expressions; fail closed on missing metadata | semantic-plan regressions + packed-storage IR smoke + Foundry nested-overflow cases | done (scoped review): checked and wrapping nested-arithmetic cases pass |
| **R5** | EVM `TargetSemantics` used a vacuous state relation and synthetic initial-state proof; powdr canonical target inherited a legacy relation | Relate Counter IR state to the canonical low-order packed storage layout; construct the real lowered Yul initial machine; bind canonical powdr semantics to `CounterStorageRel` and state honestly that no generic initial machine is supplied | `TargetSemanticsInstances`, Yul-host refinement, powdr refinement/runtime gates | done (scoped review): Counter/supported-fragment proof anchors and runtime witness gates pass |
| **R6** | CLI deploy embedded a development private key, started Anvil through a shell string, ignored configured `cast`, conflated manifest and resolved chain profiles, deferred deployer mismatch detection until after broadcast, and emitted unrelated default/Anvil provenance | Require an explicit key; spawn Anvil with argv; use configured tools; pass the resolved chain profile independently through plan/run writers and validation; derive the signing address before broadcast and reject a mismatched `--deployer`; validate creation `from`, network kind, and actual Anvil-start status | CLI deploy unit/smoke tests + missing-key, hostile-argument, configured-cast, profile-override, pre-broadcast deployer-mismatch, and public-profile provenance regressions | done (scoped review): CLI tests + Anvil deploy + broadcast smokes pass |
| **R7** | Public docs conflated scoped Gate P0 evidence with production-grade compiler correctness and reported stale zero-blocker counts | Qualify P0 as fragment-scoped artifact/execution/metadata/budget evidence; retain Experimental maturity; synchronize English/Chinese docs and manifest hashes | docs check + i18n sync | done (scoped review): claims remain Experimental and synchronized |
| **R8** | Node-level arithmetic changed the emitted Counter runtime while the powdr refinement witness still pinned the previous bytecode | Make the solc 0.8.30 full runtime a single import-tracked Lean source; decode it fail-closed for the formal config; prove the updated low-order/narrow/add instruction slices; make both external compiler smokes read the same witness | powdr refinement + pinned 0.8.30 runtime + external Yul compiler gates | done (scoped review): single-source runtime witness and all three gates pass |

### Verification snapshot (2026-07-11)

| Surface | Command | Result |
|---------|---------|--------|
| Product + aggregate baseline | `just product`; `just check` | PASS. `just check` completed with only policy-allowed environment skips (Quint verify under Java 11 and unavailable memory-cgroup backend). |
| EVM plan/ABI/event security | `just evm-semantic-plan` | PASS, including packed arithmetic, namespace/ABI negatives, standard event signatures, topics, and metadata. |
| EVM runtime | `just evm-foundry` | PASS, 35/35 Foundry tests. |
| UUPS transport | `just evm-upgrade-policy-honesty` | PASS, 5/5 atomic-init and invalid-implementation tests. |
| Deploy path | `just cli-deploy`; `just evm-anvil-deploy`; `just evm-broadcast-smoke` | PASS, including resolved-profile override and pre-broadcast deployer validation. |
| Formal runtime witness | `just evm-powdr-counter-refinement-smoke`; `just evm-powdr-counter-runtime`; `just evm-yul-compiler-counter-smoke` | PASS against the same pinned solc 0.8.30 runtime witness. |
| Documentation | `just docs-check`; `scripts/i18n/check-sync.sh` | PASS after the English/Chinese status update and manifest refresh. |

This snapshot closes R1-R8 only at the implemented scopes above. It does not
close the wider E1 or F1 waves, and it does not promote the EVM backend beyond
Experimental.

### Explicit remaining work after this review

| Priority | Gap | Next concrete slice |
|----------|-----|---------------------|
| P0 | EVM typed runtime custom-error arguments (**E1.1 remains open**) | Add runtime `Expr` argument lowering through Plan/Yul, ABI metadata, and Foundry revert-data assertions |
| P1 | Arbitrary-length ERC-1155 batch ABI and standard `TransferBatch` (**E1.2 remains open**) | Add dynamic-array ABI decode/encode, receiver callback, event emission, and rollback tests |
| P1 | UUPS compatibility and initialization lifecycle | Add `proxiableUUID` validation and a bounded, typed initializer-calldata path before promotion beyond transport spike |
| P0 | ERC-4626 deployment initialization race | Add an atomic constructor/initcode binding path; until then, document that a separately deployed uninitialized runtime can be claimed by the first caller |
| P0 | Parameterized NEAR TokenSpec runtime artifact | Unify TokenSpec, plan, and offline-host lifecycle into one source-identity-preserving artifact |
| P0 | NEP-145 withdrawal/refund correctness | Enforce one-yocto guard and predecessor refund Promise with offline-host evidence |
| P1 | Full-precision multiply/divide semantics | Introduce an explicit IR/backend primitive rather than relying on native-width intermediate multiplication |
| P1 | Release and supply-chain hardening | Add checksums/SBOM/provenance, pinned tool verification, and release artifact CI |
| P1 | Documentation integrity | Add internal-link checking and keep i18n hash validation mandatory |
| P1 | Package distribution | Define and test versioned Lean/Lake, CLI binary, and generated-client package publication |

---

**Status:** Active (2026-07-11) — post-review R1-R8 hardening is verified at the scoped boundaries above; E1.1/E1.2, the remaining lifecycle gaps, and F1 remain open.
