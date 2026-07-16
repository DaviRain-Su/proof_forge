# Portable SDK unification — task plan (EVM · Solana · NEAR · Soroban)

Status: **Complete (2026-07-09)** — successor: [unified-support-roadmap](2026-07-09-unified-support-roadmap.md)
Audience: product + compiler  
Related: [product-authoring-architecture](../../product-authoring-architecture.md),
[sdk-ecosystem-gaps-2026-07](../../sdk-ecosystem-gaps-2026-07.md),
[RFC 0006 Token SDK](../../rfcs/0006-multichain-token-sdk.md),
[ir-portability-remediation](../../ir-portability-remediation.md).

---

## 1. Goal

Make ProofForge feel like a **universal business-intent SDK** on the four
primary hosts we already support — without expanding to new chains:

| Host | Registry / surface | Role in this plan |
|------|--------------------|-------------------|
| **EVM** | `evm` | Generic EVM materialization (ERC / OZ-shaped) |
| **Solana** | `solana-sbpf-asm` | SPL / Token-2022 / CPI materialization |
| **NEAR** | `wasm-near` | NEP-141 + host storage / promise |
| **Soroban** | `wasm-stellar-soroban` | Host bridge (auth, storage, invoke) — **not** Token lane |

**Non-goals for this plan:** CosmWasm, Cloudflare Workers, Move Aptos/Sui token
lanes, new chain backends.

**North star:** authors write business intent only; `--target` selects the
native ecosystem standard. Chain SDKs (OpenZeppelin, SPL, near-sdk, stellar-sdk)
are **L4 adapter outputs**, not author-facing languages.

---

## 2. Planning principles

| Principle | Meaning |
|-----------|---------|
| One task = one mergeable slice | Entry files + acceptance command + Done definition |
| Close loops before depth | Plan/emit/test on three (or four) hosts before fee/permit polish |
| Soroban Token = out of scope | Token = EVM · Solana · NEAR only; Soroban follows policies/remote/auth |
| No silent drop | Unsupported feature → compile/plan diagnostic, never pretend success |
| Document then execute | This file is the execution backlog; update status as tasks land |

---

## 3. What is already unified (do not re-open without cause)

| Layer | Status | Evidence |
|-------|--------|----------|
| Portable IR + capability reject | ✅ | Portability / target gates |
| StorageBinding / Preflight | ✅ | D-050; primary materialize |
| Business checks (Ownable) | ✅ | `Tests/PortableAuthMaterialize` · EVM·Solana·NEAR·Soroban |
| Identity dual path | ✅ | u64 Ownable + OwnableHash (EVM `hashWord(caller)`, Solana limb0, NEAR hash) |
| Crosscall intent | ✅ | `remote` + PeerMap → CALL · CPI · promise · invoke_contract |
| TokenSpec features-only | ✅ | `planForTarget` / `resolveTokenStandard`; no author `TokenStandard` |
| Shared portable-default | ✅ | `just portable-default`; no chain DSL in Shared |
| Spec/Builder de-EVM names (partial) | ✅ | `ConstructorParam`, `constructorParams`, `abiWord?`, … |
| A/B/C layer model (Host · Protocols · Stdlib) | ✅ | [protocols-layer](../../protocols-layer.md); `ProofForge.Protocols` facade |
| Solana protocol CPI catalog (B) | ✅ | `Protocols.Solana` → Programs/Builders + Cpi packing |
| EVM IERC20 external client (B) | ✅ | `Protocols.Evm.IERC20` (CALL + selectors) |
| NEAR NEP-141 peer client (B) | ✅ | `Protocols.Near.FungibleToken` (`declareRemote` + method names) |
| Solana vault token-account path (B e2e) | ✅ | `VaultTokenAccountCpi`: create_account → initialize_account3 (owner=vault PDA) |
| EVM IERC20 client example (B e2e) | ✅ | `Examples/Backend/Evm/Contracts/Ierc20Client` + Yul selector smoke |
| EVM IERC721 client + example (B) | ✅ | `Protocols.Evm.IERC721` + `Ierc721Client` fixture |
| NEAR FT peer example (B e2e) | ✅ | `Examples/Backend/WasmNear/FtPeerClient` + promise_create smoke |
| Solana B layout inventory | ✅ | `Protocols.Solana.supportedDataLayouts` / `rejectedLayoutExamples` |

Phase C rows in [product-authoring-architecture](../../product-authoring-architecture.md)
(C.1–C.9, P0–P1e) are the baseline; this plan is the **next product backlog**.

---

## 4. Waves and tasks

### Wave 1 — Policy mixins multi-target (recommended first)

**Done when:** Ownable · OwnableHash · Pausable have multi-host materialize
gates; Ownable+Pausable composition exists on Shared path; Reentrancy boundary
documented.

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **T1.1** | Expand policy smoke | Extend `Tests/PortableAuthMaterialize.lean` (or add `Tests/PortablePolicyMaterialize.lean`) for `Pausable` (+ Reentrancy if in-scope) on EVM plan/Yul, Solana SbpfAsm, NEAR/Soroban EmitWat | `lake env lean --run …` green; native fail shapes asserted | S | — | **done** |
| **T1.2** | Pausable multi-target gaps | Fix lower/validate for `Examples/Product/Pausable` / `Stdlib.Pausable` so all four hosts render; pause flag + `guard_not_paused` materialize | Four-host render + smoke checks | M | T1.1 (TDD ok) | **done** (already materializing; smoke locked) |
| **T1.3** | Ownable + Pausable compose | Shared portable composition: only owner can pause/unpause | Shared source + multi-target smoke; no chain Surface import | M | T1.2 | **done** (`Stdlib.OwnablePausable` + Shared facade) |
| **T1.4** | AccessControl / Roles MVP | Decide nested role map portable vs EVM-first; implement MVP or honest reject on non-EVM | Decision in this doc §6 + architecture note; EVM green; non-EVM reject or minimal lower | M–L | T1.2 | **done** (portable nested maps; EmitWat compound key + Soroban map `_get`/`_put`) |
| **T1.5** | ReentrancyGuard boundary | EVM full; Solana/NEAR/Soroban: reject, no-op+warn, or lock-state — pick one product rule | Docs + capability/diagnostic consistency; Shared does not claim false four-host parity | S | — | **done** (lock-state four-host; EVM primary semantics in stdlib header) |

**Suggested PR slice:** PR-A = T1.1+T1.2 · PR-B = T1.3+T1.5 · T1.4 follow-on.

---

### Wave 2 — Token intent three-host loop (EVM · Solana · NEAR)

**Done when:** Same Fungible TokenSpec → EVM bytecode path + Solana plan/harness
+ NEAR plan **and** a WAT/emit primary path; feature matrix is product-facing;
Soroban token explicitly unsupported.

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **T2.0** | Token target matrix boundary | Document + enforce: Soroban/Move have no TokenSpec lane; CLI `--token` on those targets fails clearly | `just token-feature-matrix`; clear error string | S | — | **done** (CLI reject + `noTokenLaneMessage`) |
| **T2.1** | NEAR NEP-141 plan → emit | Beyond `near-token-plan.json`: core features → IR and/or EmitWat (or staged plan-only milestone if blocked) | `build --target wasm-near --token` produces `.wat` (or documented two-step); smoke step checks `ft_*` / storage symbols | L | T2.0 | **done** (two-step: TokenSpec plan + `NearFungibleToken` body; smoke step 10) |
| **T2.2** | EVM extended features policy | For `transfer_fee` / `non_transferable` / `permit`: (A) implement in-contract or (B) keep reject with pointer to Solana; land at least one feature’s permanent policy + tests | `validateEvmTokenFeatures` + smoke/docs agree | M–L | T2.0 | **done** (permanent reject + Solana pointer; permit rejected on EVM) |
| **T2.3** | Feature matrix productization | Human-readable matrix from `featureSupportOnTarget`; wire `just token-feature-matrix` / portable aggregate as appropriate | One command lists EVM/Solana/NEAR support per feature | S | existing matrix fn | **done** (`just token-feature-matrix` + tests) |
| **T2.4** | Shared Fungible multi-target docs | Document single health path for three-host token (intent smoke + EVM vm smoke) | `Examples/Product/README` or tutorial step | S | T2.1 | **done** |
| **T2.5** | Portable token author entry | Clarify TokenSpec as portable entry; ERC-20 as EVM materialization (facade or docs only — no hard rename required) | Shared README + `Token.lean` header | S | — | **done** (Token.lean header table) |

**Suggested PR slice:** PR-C = T2.0+T2.3+T2.5 · PR-D = T2.1 · then T2.2.

---

### Wave 3 — Remote / identity / clients

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **T3.1** | Remote scalar ABI MVP | Portable args (u64/bool/hash) encoding table across four hosts; extend Shared RemoteCall | Multi-target smoke with one parameterized remote | L | RemoteCall baseline | **done** (`call_with_args` + Surface ABI table + CrosscallMaterialize asserts) |
| **T3.2** | Solana account auto-fill | Extend `ensurePortableAuthAccounts` pattern for transfer/remote intents; reduce Source.Solana need | Named Shared example emits without Solana Surface | L | T3.1 optional | **done** (`ensurePortableNativeValueAccounts` + AuthRemoteCall + `just portable-solana-accounts`) |
| **T3.3** | Identity docs + Solana Hash bound | Ownable vs OwnableHash chooser table; limb0 = Phase-1 product contract | Architecture + Surface comments; tests agree | S | OwnableHash landed | **done** (architecture table) |
| **T3.4** | Error id → clients | Map assertion_id across EVM revert / Solana custom / NEAR panic into sdk-schema | Same id in three-host artifacts | M | — | **done** (`Tests/PortableErrorCatalog.lean` + `just portable-error-catalog`) |
| **T3.5** | Soroban product close-out (non-token) | Counter/Ownable/RemoteCall artifact list, SDK extension, wat2wasm gates | Existing multi-target scripts stable | M | C.5–C.9 | **done** (remote-call multi-target + Soroban wat2wasm; justfile WasmHost paths) |

---

### Wave 4 — Author surface polish

| ID | Task | Work | Acceptance | Size | Deps | Status |
|----|------|------|------------|------|------|--------|
| **T4.1** | de-EVM naming pass 2 | Document `entrySelector` as EVM materialization; tutorials default without selectors | authoring-model updated | S | partial de-EVM done | **done** (`authoring-model` § selectors; Builder/Surface docs; Shared bans) |
| **T4.2** | Shared tutorial path | Counter → Ownable → Token → Remote Shared-only tutorial with `just` steps | `Examples/Product/README` runnable from zero | M | W1/W2 progress | **done** (`portable-shared-path.md` + `just portable-tutorial`) |
| **T4.3** | IR chain ctor visibility (optional) | Keep create2/promise out of author path; portability classification | portability smoke no regress | M | — | **done** (portable-default bans CREATE2/selectors; Portability already classifies) |

---

## 5. Dependency graph

```text
Wave 1:  T1.1 → T1.2 → T1.3
                  ↘ T1.4
             T1.5 (parallel)

Wave 2:  T2.0 → T2.1 → T2.4
              ↘ T2.2
              ↘ T2.3 (parallel)
             T2.5 (parallel)

Wave 3:  T3.3, T3.5 anytime · T3.1 → T3.2 · T3.4 parallel

Wave 4:  after W1/W2 progress; can interleave docs
```

---

## 6. Open product decisions (fill when executing)

| Decision | Options | Default until decided |
|----------|---------|------------------------|
| **D-W1-Roles** | Nested AccessControl portable on all hosts vs EVM-first | **Decided:** portable nested role maps on four hosts (T1.4) |
| **D-W1-Reentrancy** | Full lock on Wasm/Solana vs EVM-only policy | **Decided:** lock-state materializes on four hosts; EVM is primary reentrancy meaning (T1.5 done) |
| **D-W2-EvmFee** | Implement fee-on-transfer on EVM vs permanent reject→Solana | **Decided (B):** permanent reject on EVM → use Solana Token-2022; also reject `permit` until EIP-2612 |
| **D-W2-SorobanToken** | Ever add TokenSpec lane? | **No** in this plan (CLI + matrix enforce no-lane) |
| **D-W3-SolanaHash** | limb0 permanent vs full 32-byte OwnableHash | limb0 Phase-1; full 32B follow-up outside W1 |

---

## 7. Execution order (first delivery)

| PR | Tasks | Deliverable |
|----|-------|-------------|
| **PR-A** | T1.1 + T1.2 | Pausable four-host materialize + tests |
| **PR-B** | T1.3 + T1.5 | Ownable+Pausable compose + Reentrancy boundary |
| **PR-C** | T2.0 + T2.3 + T2.5 | Token matrix/boundary/entry docs |
| **PR-D** | T2.1 | NEAR NEP-141 emit path (largest token slice) |

Then: T2.2, Wave 3, Wave 4 as capacity allows.

**Start gate:** Land this document; then execute **PR-A** unless product chooses Wave 2 first.

---

## 8. Gates / commands (living list)

| Area | Command |
|------|---------|
| Policy materialize | `lake env lean --run Tests/PortableAuthMaterialize.lean` (+ new policy test) |
| Token intent | `just token-intent-smoke` |
| Token feature matrix | `just token-feature-matrix` |
| Token EVM VM | `just token-intent-evm-vm` |
| Portable default lint | `just portable-default` |
| Remote multi-target | `just portable-remote-call-multi-target` (EVM·Solana·NEAR·Soroban + Soroban wat2wasm) |
| Crosscall materialize | `just crosscall-materialize` |
| Error catalogue parity | `just portable-error-catalog` |
| Solana account auto-fill | `just portable-solana-accounts` |
| Shared tutorial path | `just portable-tutorial` · [portable-shared-path.md](../../tutorials/portable-shared-path.md) |

Update this table when recipes are renamed.

---

## 9. Status changelog

| Date | Note |
|------|------|
| 2026-07-09 | Plan recorded from portable SDK gap review; baseline includes OwnableHash multi-target + Spec de-EVM constructor names. Execution not started. |
| 2026-07-09 | **PR-A/B:** T1.1–T1.3, T1.5 — Pausable four-host smoke; `OwnablePausable`; Reentrancy lock-state boundary. **PR-C/D partial:** T2.0, T2.1 (two-step NEAR body), T2.3, T2.5. Remaining: T1.4 AccessControl, T2.2 EVM feature policy, T2.4 docs, Wave 3+. |
| 2026-07-09 | **T1.4:** nested map EmitWat fix (`__pf_map_*_nested_*`); Soroban map helpers use `_get`/`_put`; AccessControl + RoleGatedToken wat2wasm-valid on NEAR·Soroban; Shared facade + PortableAuthMaterialize. |
| 2026-07-09 | **Rename:** `Backend.WasmNear` → `Backend.WasmHost` (Wasm-family EmitWat core + `HostBridge`); registry target ids `wasm-near` / `wasm-stellar-soroban` unchanged; `Backend.WasmNear` remains a deprecation re-export. |
| 2026-07-09 | **Wasm family unify:** move CosmWasm Counter adapter under `Backend.WasmHost.CosmWasm`; document package tree in `docs/targets/wasm-family.md`. |
| 2026-07-09 | **CosmWasm into EmitWat:** `HostBridge.cosmWasm` storage (`db_read`/`db_write`) in Scalar/Map/Imports; unified `EmitWat.renderModule` for all bridges; remove top-level `Backend.WasmNear` / `Backend.CosmWasm` shims. |
| 2026-07-09 | **T2.2 + T3.1:** EVM TokenSpec permanent reject policy (fee/soulbound/permit); remote u64 scalar ABI locked in CrosscallMaterialize + Surface docs. CosmWasm product path still deferred. |
| 2026-07-09 | **T3.4 + T3.5:** `PortableErrorCatalog` locks assertionId 1/2 on EVM·Solana·NEAR clients + sdk-schema + EmitWat `PF:id:code`; justfile lake modules `WasmNear`→`WasmHost`; remote-call Soroban step runs wat2wasm when available. |
| 2026-07-09 | **T3.2:** Solana portable account auto-fill — `nativeValue` promotes writable signer@0; AuthRemoteCall Shared example (caller+debit+remote) without Source.Solana; `just portable-solana-accounts`. |
| 2026-07-09 | **Wave 4 (T4.1–T4.3):** de-EVM selector docs; Shared tutorial Counter→Ownable→Token→Remote (`just portable-tutorial`); ban CREATE2/selector pins in Shared via portable-default. Plan complete for primary four-host portable SDK slice. |
| 2026-07-09 | **Complete:** Waves 1–4 all done. Successor roadmap for HostEnv / crosscall honesty / FV-9 / platform: [unified-support-roadmap](2026-07-09-unified-support-roadmap.md). |

When a task completes: set Status to `done`, add commit hash or PR note in changelog.
