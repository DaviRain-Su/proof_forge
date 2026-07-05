# ProofForge Design Decisions

This document records architecture decisions that are settled enough to guide
implementation. Open questions stay in RFCs and target notes until resolved here.

See also: [Review checklist (English)](review-checklist.md),
[Review checklist (中文)](zh/review-checklist.md).

## Decision Log

| ID | Date | Decision | Rationale |
|---|---|---|---|
| D-001 | 2026-06-30 | RFC 0001 and RFC 0002 are **Accepted** as the engineering direction | Detailed target and backlog docs exist; Draft status was misleading |
| D-002 | 2026-06-30 | Phase 1 (target registry + portable IR + artifact metadata) must complete before non-EVM spikes | Spikes need capability checks and shared scenario definitions |
| D-003 | 2026-06-30 | CosmWasm and Solana spikes run **in parallel** after Phase 1 | No fixed order between the two; both validate different backend families |
| D-004 | 2026-06-30 | ~~Canonical Solana target id is `solana-sbpf-linker`~~ **Superseded by D-026** | Stock Zig + sbpf-linker fitted platform tooling; `solana-sbf` is a filename alias only. D-026 supersedes this with `solana-sbpf-asm` as the preferred direct-assembly route. |
| D-005 | 2026-06-30 | Keep **`solana-zig-fork`** as fallback/reference track | Mature SDK reference from solana-sdk-mono; not the primary product path |
| D-006 | 2026-06-30 | NEAR is the Wasm-host **reference**; CosmWasm is the first new Wasm spike in-repo | Fork lessons inform structure; CosmWasm validates host adapter generality |
| D-007 | 2026-06-30 | Move POC starts with **Aptos only**; Sui follows | Aptos account resources are simpler; Sui object model tests abstraction harder |
| D-008 | 2026-06-30 | Move targets use **source generation**, not Lean runtime on MoveVM | Proofs stay in Lean; Move carries executable logic only |
| D-009 | 2026-06-30 | **`wasm-polkadot` / ink!** stays research-only | Not in the target registry until a spike is scheduled |
| D-010 | 2026-06-30 | Cloud platform waits until **two or more targets** reach Experimental stage | Avoid building a UI shell before local backends are real |
| D-011 | 2026-06-30 | Add **`psy-dpn`** as a Research target under ZK circuit source generation | Psy has no public Yul-like IR; first integration should generate `.psy` and call Dargo |
| D-012 | 2026-07-01 | Classify **`kaspa-toccata`** as a docs-first Research candidate, not a ZK circuit sourcegen target | Toccata is Kaspa L1 programmability through transaction v1, covenants, inline proof verification, and based-app settlement; code registry changes wait until UTXO/covenant capabilities are reviewed |
| D-013 | 2026-07-01 | Classify **`wasm-stellar-soroban`** as a docs-first Wasm-host Research candidate | Soroban emits Wasm but has Stellar-specific storage TTL, authorization, contract spec, deployment, and CLI semantics; registry changes wait until the first spike path is chosen |
| D-014 | 2026-07-01 | Classify **`wasm-icp-canister`** as a docs-first Wasm-host Research candidate | Internet Computer canisters emit Wasm but have Candid, principal identity, update/query call modes, cycles, stable memory, async inter-canister calls, and lifecycle semantics; registry changes wait until a canister spike path is chosen |
| D-015 | 2026-07-01 | Classify **`ton-tvm`** as a docs-first TVM/Tolk sourcegen Research candidate | TON contracts target TVM with cells, TL-B serialization, message handlers, get methods, action lists, account lifecycle, and TVM gas semantics; registry changes wait until a sourcegen spike path is chosen |
| D-016 | 2026-07-01 | Classify **`bch-cashscript`** as a docs-first UTXO script/covenant sourcegen Research candidate | Bitcoin Cash contracts through CashScript lock and spend UTXOs with BCH Script, transaction introspection, CashTokens, and SDK transaction-builder semantics; registry changes wait until a CashScript spike path is chosen |
| D-017 | 2026-07-01 | Classify **`algorand-avm`** as a docs-first AVM/TEAL sourcegen Research candidate | Algorand contracts target AVM approval/clear-state or LogicSig programs with ARC-4 ABI, global/local/box storage, resource references, atomic transaction groups, inner transactions, and AVM budget semantics; registry changes wait until an Algorand package spike path is chosen |
| D-018 | 2026-07-01 | Classify **`cardano-plutus-aiken`** as a docs-first eUTXO validator sourcegen Research candidate | Cardano contracts validate eUTXO spends through datum, redeemer, script context, Plutus/UPLC artifacts, execution units, Plutus blueprints, and off-chain transaction-building semantics; registry changes wait until an Aiken sourcegen spike path is chosen |
| D-019 | 2026-07-01 | Classify **`tezos-michelson-ligo`** as a docs-first Michelson/LIGO sourcegen Research candidate | Tezos contracts target Michelson with typed storage, parameters, entrypoints, views/events, operation lists, `big_map`, tickets, Sapling, gas, and storage-burn semantics; registry changes wait until a LIGO sourcegen spike path is chosen |
| D-020 | 2026-07-01 | Classify **`starknet-cairo`** as a docs-first Cairo/Sierra/CASM sourcegen Research candidate | Starknet contracts compile through Cairo into Sierra/CASM with ABI, class hashes, declaration/deployment metadata, Starknet storage/events, account abstraction, syscalls, and L1/L2 messaging semantics; registry changes wait until a Cairo package spike path is chosen |
| D-021 | 2026-07-01 | Classify **`bitcoin-script-miniscript`** as a docs-first Bitcoin base-layer spending-policy Research candidate | Bitcoin Script is intentionally limited to UTXO locking/unlocking policy with signatures, hash locks, timelocks, descriptors, Miniscript, Taproot/Tapscript, PSBT flows, and standardness/fee constraints; registry changes wait until a Miniscript/descriptor spike path is chosen |
| D-022 | 2026-07-01 | Classify **`zcash-shielded`** as a docs-first privacy UTXO/ZK payment Research candidate | Zcash is Bitcoin-derived but shielded support depends on Sapling/Orchard notes, nullifiers, anchors, value-balance constraints, viewing/disclosure policy, and protocol-defined ZK proofs; registry changes wait until shielded-note capabilities and a proving/validation boundary are reviewed |
| D-023 | 2026-07-01 | Classify **`aleo-leo`** as a docs-first Aleo ZK application sourcegen Research candidate | Aleo programs combine private off-chain proof execution, public on-chain finalization, encrypted records, public mappings/storage, Aleo Instructions, Aleo VM bytecode, ABI, prover/verifier artifacts, and execute/deploy transactions; registry changes wait until the proof/finalization split is reviewed |
| D-024 | 2026-07-01 | Model Robinhood Chain as **`robinhood-chain-testnet`**, an EVM-compatible chain profile under `evm`, not a new compiler target | Robinhood Chain executes EVM-compatible Arbitrum Orbit L2 contracts; ProofForge's EVM backend covers bytecode generation, while the chain profile records chain id, RPC, explorer, verifier, rollup, and deployment metadata |
| D-025 | 2026-07-01 | Add **`solana-sbpf-asm`** as a new Solana route (direct sBPF assembly codegen) under exploration; keep `solana-sbpf-linker` as fallback | Generating sBPF assembly directly from the portable IR avoids the full Lean Zig runtime linking risk; the blueshift-gg/sbpf toolchain handles assembly and linking. See [RFC 0005](rfcs/0005-solana-sbpf-assembly-backend.md) and [design doc](targets/solana-sbpf-asm.md). |
| D-026 | 2026-07-01 | **Adopt `solana-sbpf-asm` as the canonical Solana route; supersede `solana-sbpf-linker`** | The direct-assembly route avoids Lean runtime linking risk, gives full control over compute units and stack, and mirrors the EVM/Yul pattern. `solana-sbpf-linker` is kept as historical reference only — codegen should target the assembly route. |
| D-027 | 2026-07-01 | **CPI and PDA effects stay in a Solana‑specific layer, not the portable IR** | `cpiInvoke`, `cpiInvokeSigned`, and `pdaDerive` are Solana‑only concepts (Solana's account‑passing CPI + PDA derivation have no analog on EVM, Wasm, or Move). They belong in `ProofForge.Backend.Solana.Effects` or the Solana SDK module, gated by the `crosscall.cpi` and `storage.pda` capabilities. The portable IR (`ProofForge.IR.Contract.Effect`) remains chain‑neutral — new constructors only when ≥2 target families share the same semantic shape. |
| D-028 | 2026-07-02 | **User contracts target a chain-neutral Contract Intent API; the selected target resolves intents into capability plans** | The default SDK surface should not reveal the destination chain. Users write portable contract intents, then `--target` selects the target adapter, which routes those intents to lower-level capability implementations, checks support/runtime constraints, and emits target artifacts. Capability ids remain the internal protocol used by target adapters and Target Extension SDKs; they are not the primary user-facing API. |
| D-029 | 2026-07-01 | Adopt Rust `near-sdk-rs` source generation as the in-repo `wasm-near` v0 backend | The EmitZig/Zig host bridge sources are not present in the repository; portable IR → near-sdk-rs package → cargo wasm32 validates NEAR semantics now and preserves the Zig host-bridge path for restoration later. (Renumbered from the NEAR branch's D-025 during the 2026-07 branch consolidation merge.) |
| D-030 | 2026-07-01 | `wasm-near` v0 supports `Hash` map keys, `.assertions.check`, and `.account.explicit` | Required by existing `MapProbe` (Hash keys, `assertEq`) and `ContextProbe` (`contractId`) fixtures; `.crosscall.invoke` remains unsupported for sourcegen v0. (Renumbered from the NEAR branch's D-026.) |
| D-031 | 2026-07-01 | Adopt **`EmitWat`** (portable IR → Wasm AST → WAT text → `wat2wasm`) as the canonical Wasm-family backend; demote the Rust `near-sdk-rs` sourcegen to a **frozen v0 stopgap** | `EmitWat` mirrors the in-repo **portable-IR → Yul** renderer `Backend/Evm/IR.lean` (used by every `--emit-*-ir-yul` CLI mode), *not* the separate LCNF-based `Compiler/LCNF/EmitYul.lean`. Because the portable IR already abstracts over Lean objects (`u32`/`u64`/`bool`/`hash` scalars + storage effects only), `EmitWat` needs no Lean runtime port, object-model boxing, or GC — avoiding both the `near-sdk` macro coupling of the Rust route (E0119 Borsh / missing-`&self` cargo-check failures) and the Lean-runtime-to-Wasm port that blocks the prior `EmitZig` plan. Shared layer: `Compiler/Wasm/AST.lean` + `Printer.lean` + IR→AST lowering (parallel to `Compiler/Yul/AST.lean` + `Printer.lean`); reusable validation from `Backend/WasmNear/IR.lean` and `Backend/Evm/IR.lean`. Per-chain: host imports + ABI serialization. Key spike risk: NEAR argument (de)serialization (JSON/Borsh), which the EVM backend does not face (EVM uses calldata). (Renumbered from the NEAR branch's D-027.) |
| D-032 | 2026-07-01 | Ratify **`aleo-leo`** Research exit design: Leo-first `zk-app-sourcegen` boundary, canonical capabilities for Road 1, artifact manifest schema, and `leo build`/`leo test` toolchain | Aleo's proof/finalization split requires its own sourcegen family distinct from `psy-dpn`-style circuit sourcegen; code registry changes remain deferred until the Road 1 spike succeeds and is reviewed. (Renumbered from the Aleo branch's D-025 during the 2026-07 branch consolidation merge.) |
| D-033 | 2026-07-01 | Add **`wasm-cloudflare-workers`** as a Research Wasm-host target | Cloudflare Workers is not a blockchain, but it shares the Wasm-host backend pattern with NEAR/CosmWasm; it validates the portable-core model by running the same verified business logic off-chain with reinterpreted capabilities. (Renumbered from the Cloudflare branch's D-025 during the 2026-07 branch consolidation merge.) |
| D-034 | 2026-07-02 | Adopt the **tiered target portfolio** ([target-roadmap](target-roadmap.md)) and classify UTXO script targets as a separate **policy family** | Tier gates: shared-scenario parity on `evm`/`solana-sbpf-asm`/`wasm-near` opens `wasm-cosmwasm` (D-006) and `move-aptos` (D-007) in parallel; Soroban/Sui/sourcegen targets open on those exits; at most one sourcegen spike active at a time. Bitcoin-family targets (`bitcoin-script-miniscript`, `bch-cashscript`, `zcash-shielded`, `kaspa-toccata`) are spending-policy generators, not contract executors: they get a policy IR (predicate tree; no storage/events/crosscall) with new `policy.*` capability ids and a PSBT/regtest validation lane, instead of being forced through the contract pipeline |
| D-035 | 2026-07-02 | **Current phase completion criterion:** shared scenario (Counter, then ValueVault) must pass on `evm`, `solana-sbpf-asm`, and `wasm-near` before opening Tier-1 targets | Locks the Definition of Done for the current consolidation phase; keeps new research targets docs-only until Gate G0 is met, preventing premature registry/capability churn |
| D-036 | 2026-07-02 | **Unify allocator modeling** at the IR/Target layer under one `AllocatorModel` (strategy/region/release), keep Solana `solana.allocator.*` metadata keys as the Solana-specific configuration syntax, and give EVM an explicit bump-over-scratch binding | Resolves the Workstream 24 allocator-unification open question; RFC 0008 defines the triple. Persistent-state models (EVM storage, Solana accounts, NEAR storage) stay outside the allocator abstraction. `Statement.release` remains rejected on EVM until ownership soundness (FV-3) justifies a checked no-op |
| D-037 | 2026-07-02 | Keep **`wasm-cloudflare-workers`** under the `wasmHost` target family as a Research off-chain host | It shares the Wasm-host backend pattern (EmitWat, portable-core + host-bridge) with NEAR/CosmWasm; its off-chain status is expressed by stage (Research) and capability set rather than by a separate family. A distinct off-chain host family is deferred until more off-chain targets force a new classification |
| D-038 | 2026-07-03 | Bind the **`evm` target profile** to the explicit bump-over-call-scratch allocator model (`AllocatorConfig.evm`: strategy `bump`, region call-scratch, `release = none`) | Documents what `EmitYul`/EVM plan already do: EVM uses word-addressed transaction-scratch memory with compiler-chosen offsets and never frees. `Statement.release` stays rejected on EVM v0. The transition to `release = noop` is gated on FV-3 proving that ownership checking makes release semantically transparent (no use-after-release, no double-release) so that EVM traces remain identical to reuse-capable targets |
| D-039 | 2026-07-03 | Accept the CLI product surface as `proof-forge build|emit|check --target <id> [--fixture <id>]` before testkit M4 binds to legacy flags | RFC 0009 defines the target-first surface, fixture registry, and legacy-flag alias/deprecation plan. The 2026-07-03 review found M1 already landed through the compatibility layer (`Command`/`CliOptions`, `check`, list commands, and legacy alias metadata), so this decision ratifies the surface and makes the remaining M3/M4 migration explicit rather than acting as a pre-code freeze |
| D-040 | 2026-07-03 | Make resource budgets (EVM gas, Solana CU, NEAR gas) a required part of the Tier-0 parity gate | Tier-0 shared-scenario parity (D-034) must compare behavior *and* budgets; RFC 0010 defines optional per-step budget baselines with tolerance bands in testkit scenarios, preventing fake parity and locking in the current Solana direct-assembly CU advantage |
| D-041 | 2026-07-03 | Adopt a portable runtime error model (`assertion_id` + optional `user_code`) and a unified `ContractSpec` client schema | Each target encodes the same error id in its native form (EVM revert, Solana custom error, NEAR panic payload, Psy assertion index); testkit asserts `expect.error`. A target-neutral `ContractSpec` JSON generalizes the existing Solana IDL and feeds per-chain TS clients after testkit M3 |
| D-042 | 2026-07-03 | Adopt a versioning and compatibility policy for the portable IR, artifact/deploy JSON schemas, capability ids, and the SDK/CLI | IR uses `major.minor` where new constructors are minor and semantic changes are major; artifact/deploy schemas use integer `schemaVersion` with a tolerant-reader rule; capability ids are append-only; SDK/CLI follows semver-ish rules pre- and post-1.0. RFC 0012 defines the full policy |
| D-043 | 2026-07-03 | Add an `upgradePolicy` intent (`immutable | authority(keyRef) | governance(ref)`) and keep signing outside the compiler | Each target lowers the policy honestly or rejects it at compile time; EVM v0 supports only `immutable`; Solana supports `immutable` and `authority`; NEAR supports `immutable` and `authority` as account-key policy. ProofForge emits unsigned transactions/manifests only; key custody stays in wallets/KMS/CI secrets. RFC 0013 defines the full lifecycle and signing boundary |
| D-044 | 2026-07-03 | **Tier-0 completion first:** finish `solana-sbpf-asm`, `evm`, `wasm-near` (in that implementation priority) to full DoD — behavior parity *and* resource budgets (D-040) — before any new-chain advancement | Operationalizes D-035/D-040. Until Gate G0 closes with budgets, the already-landed Aptos/CosmWasm spikes are frozen at their current M1/M2 state (no registry stage, no M3/M4, no Tier-2 start); D-045 extends that freeze through the stricter primary-chain sign-off Gate P0. The old "open Tier-1 in parallel" wording in D-034/Workstream 28 is superseded for the current phase by this completion-first rule. See [target-roadmap](target-roadmap.md) Tier-0 completion checklist and [gate-status](gate-status.md) for per-criterion status. |
| D-045 | 2026-07-03 | **Primary-chain completion covenant:** product implementation priority is `solana-sbpf-asm` → `evm` (Ethereum) → `wasm-near` (NEAR/Wasm), and those three chains must be completed to production-grade quality before any additional chain advances beyond docs-only research or frozen spike maintenance | This is the product-level sequencing rule above individual workstreams. "Complete" means target-first build/emission, local execution or deployment smoke, artifact/deploy metadata, capability diagnostics, resource budgets, CI coverage, and maintained docs. New targets may still receive docs-first research notes, and already-landed Aptos/CosmWasm/Aleo/Psy/Cloudflare spikes may receive CI/security maintenance, but no new registry/capability/testkit/CI advancement for additional chains should land until the primary three-chain sign-off is recorded in [gate-status](gate-status.md). |
| D-046 | 2026-07-04 | **Close the legacy EVM authoring route:** `ProofForge.Evm`, LCNF `EmitYul`, and `.evm-methods` are removed from the product tree (CS-0.2); **`contract_source` → portable IR → EVM semantic plan → Yul → solc** is the sole EVM product pipeline; [RFC 0004](rfcs/0004-evm-semantic-plan.md) is **Accepted** | Workstream 24 / CS-6.3 closure. Application examples use `contract_source` or stdlib composition; Builder/`ContractSpec` fixtures remain under compiler test paths only. Historical RFCs may still mention LCNF as project history, not as a supported route. |
| D-047 | 2026-07-05 | Adopt **two-stage lowering for `psy-dpn`**: portable IR → `ProofForge.Compiler.Psy.AST` (`Psy.Module`) → `ProofForge.Compiler.Psy.Printer` → `.psy` source | Mirrors the EVM (`Compiler/Yul/AST.lean` + `Printer.lean`) and Wasm-family (`Compiler/Wasm/AST.lean` + `Printer.lean`) backend pattern. The AST is a target-side surface AST mirroring `.psy` source forms, **not** the upstream `psy-ast::Program` interner/arena/checker layers. Validation and shape resolution stay on the IR-lowering side; the printer is pure and self-describing. All Psy golden sources, 55 diagnostic cases, and the IR coverage manifest are unchanged after the refactor. See [psy-dpn](targets/psy-dpn.md) Phase B2. |
| D-048 | 2026-07-05 | Add **semantic Plan layer** for `psy-dpn` (`ProofForge.Backend.Psy.Plan`), extending the two-stage lowering to three stages: IR → Plan → AST → source | Mirrors the EVM `Lower.lean` → `Plan.lean` → `IR.lean(lowerModuleWithPlan)` split. The plan captures Psy-specific resolved shapes (storage layout with feltBackedU32 flags, context ops, event plans, crosscall targets, fixture-shape test body) that the AST builder previously resolved inline. `buildModuleWithPlan(module, plan)` + `renderModule` build the plan first. Also adds 4 `memoryArray*` diagnostic cases (55 → 59). All Psy golden sources, 59 diagnostic cases, and IR coverage manifest pass unchanged. See [psy-dpn](targets/psy-dpn.md) Phase B3. |
| D-049 | 2026-07-05 | **Complete Phase B3:** introduce `BuildContext` for plan-time shape resolution + add `ProofForge.Backend.Psy.Metadata` for plan-driven artifact metadata | `BuildContext` (module + StorageLayout) replaces inline `findState?`/`requireScalarState` calls in all AST builder functions with context-based lookups against the pre-resolved storage layout. Validation functions keep raw `Module` since they run pre-plan. `Metadata.lean` produces `ArtifactMetadata` (entrypoints, events, context ops, crosscalls, capabilities) from `PsyModulePlan`, mirroring EVM `Metadata.lean`. All Psy golden sources, 59 diagnostic cases, and IR coverage manifest pass unchanged. |

## Target Family Classification

| Family | Targets | Backend pattern |
|---|---|---|
| Direct compiler | `evm` | `contract_source` / ContractSpec → portable IR → EVM semantic plan → Yul AST/source → solc |
| EVM-compatible chain profiles | `robinhood-chain-testnet` | Reuse `evm` bytecode/ABI output; add chain id, RPC, explorer, verifier, rollup, and deployment metadata |
| Wasm host | `wasm-near`, `wasm-cosmwasm`, `wasm-cloudflare-workers` (off-chain host, D-033), `wasm-stellar-soroban` (candidate, docs only), `wasm-icp-canister` (candidate, docs only) | Portable IR → **`EmitWat`** (Wasm AST → WAT) → `wat2wasm` + per-chain host imports; Rust/CDK sourcegen used only as a frozen v0 stopgap (D-031, [wasm-family](targets/wasm-family.md)); Cloudflare Workers currently uses TypeScript sourcegen |
| Binary toolchain | `solana-sbpf-linker`, `solana-zig-fork` | Lean → EmitZig → bitcode → sbpf-linker (historical reference; superseded by D-026) |
| sBPF direct codegen | `solana-sbpf-asm` | Lean → IR → sBPF assembly (.s) → sbpf toolchain → ELF (canonical D-026) |
| Source codegen | `move-aptos`, `move-sui` | Portable IR → Move package source |
| AVM sourcegen research | `algorand-avm` (candidate, docs only) | Portable IR → Algorand Python, Algorand TypeScript, or TEAL package → AVM approval/clear-state or LogicSig bytecode + ARC-4/app metadata |
| eUTXO validator sourcegen research | `cardano-plutus-aiken` (candidate, docs only) | Portable IR → Aiken package → UPLC/Plutus validator artifacts + Plutus blueprint + transaction scenario metadata |
| Michelson sourcegen research | `tezos-michelson-ligo` (candidate, docs only) | Portable IR → LIGO package → Michelson contract + parameter/storage schema + operation/view/event manifests |
| Cairo sourcegen research | `starknet-cairo` (candidate, docs only) | Portable IR → Cairo/Scarb package → Sierra/CASM artifacts + ABI/class-hash/deployment metadata |
| Aleo ZK app sourcegen (`zk-app-sourcegen`) | `aleo-leo` (candidate, docs only) | Portable IR → Leo package → Aleo Instructions → Aleo VM bytecode + ABI/prover/verifier artifacts + execute/deploy metadata |
| TVM sourcegen research | `ton-tvm` (candidate, docs only) | Portable IR → Tolk or lower-level TON source → TVM/BOC artifact + TL-B/message manifests |
| Bitcoin script policy research | `bitcoin-script-miniscript` (candidate, docs only) | Portable IR → policy/Miniscript/descriptor package → Script/Tapscript output + PSBT/regtest validation metadata |
| Privacy UTXO ZK payment research | `zcash-shielded` (candidate, docs only) | Portable IR → shielded transaction/proving manifest → Zcash transaction with Sapling/Orchard proof bundle + zcashd/library validation metadata |
| UTXO script sourcegen research | `bch-cashscript` (candidate, docs only) | Portable IR → CashScript `.cash` source → cashc artifact JSON + BCH transaction-builder validation |
| ZK circuit sourcegen | `psy-dpn` | Portable IR → `.psy` package → Dargo → DPN circuit JSON |
| UTXO covenant research | `kaspa-toccata` (candidate, docs only) | Portable IR → covenant/Silverscript package + transaction v1 manifest + optional proof settlement metadata |

## Roadmap Summary

**Superseded** by the tier/gate model in [target-roadmap](target-roadmap.md) (D-034),
the Tier-0 completion-first rule (D-044), and the primary-chain completion
covenant (D-045). The historical phase labels below are
kept only for traceability; do not use them for scheduling. The authoritative
sequencing is the tier model with the primary-chain sign-off gate first
(Tier 0 active → Gate P0 → Tier 1 → Gate G2 → …), with Gate status tracked in
[gate-status](gate-status.md).

```text
Phase 0: EVM baseline (done)
Phase 1: Target registry + portable IR + artifact metadata + capability errors
Phase 2: Parallel spikes — CosmWasm (wasm-cosmwasm) + Solana (solana-sbpf-linker)   [superseded: Solana is solana-sbpf-asm per D-026]
Phase 3: Move sourcegen — Aptos POC first, then Sui                                  [frozen at Aptos M1/M2 spike per D-044 until Tier-0 DoD]
Phase 3.5: Psy DPN sourcegen research spike
Research lane: Kaspa Toccata covenant/based-app target note before registry changes
Research lane: Stellar Soroban Wasm-host target note before registry changes
Research lane: Internet Computer canister target note before registry changes
Research lane: Algorand AVM/TEAL target note before registry changes
Research lane: Cardano Plutus/Aiken eUTXO target note before registry changes
Research lane: Tezos Michelson/LIGO target note before registry changes
Research lane: Starknet Cairo target note before registry changes
Research lane: Aleo Leo ZK app target note before registry changes
Research lane: TON TVM/Tolk target note before registry changes
Research lane: Bitcoin Script/Miniscript spending-policy target note before registry changes
Research lane: Zcash shielded privacy payment target note before registry changes
Research lane: Bitcoin Cash CashScript target note before registry changes
Phase 4: Cross-target shared scenario hardening   [= Gate G0, D-035/D-040/D-044]
Phase 5: Cloud platform
```

Detailed tasks: [Implementation backlog](implementation-backlog.md).

## Authoritative Specs

| Topic | Document |
|---|---|
| Portable Contract IR | [portable-ir.md](portable-ir.md) |
| Capability IDs | [capability-registry.md](capability-registry.md) |
| Counter shared scenario | [shared-scenario.md](shared-scenario.md) |
| Target engineering shape | [RFC 0002](rfcs/0002-target-implementation-design.md) |
| CosmWasm SDK spike sketch | [targets/wasm-family.md](targets/wasm-family.md) |
| Wasm-NEAR sourcegen target | [targets/wasm-near.md](targets/wasm-near.md) |
| Cloudflare Workers target | [targets/cloudflare-workers.md](targets/cloudflare-workers.md) |
| Stellar/Soroban target candidate | [targets/stellar-soroban.md](targets/stellar-soroban.md) |
| Internet Computer target candidate | [targets/internet-computer.md](targets/internet-computer.md) |
| Algorand AVM target candidate | [targets/algorand-avm.md](targets/algorand-avm.md) |
| Solana instruction manifest | [targets/solana-sbf.md](targets/solana-sbf.md) |
| Cardano Plutus/Aiken target candidate | [targets/cardano-plutus-aiken.md](targets/cardano-plutus-aiken.md) |
| Tezos Michelson/LIGO target candidate | [targets/tezos-michelson-ligo.md](targets/tezos-michelson-ligo.md) |
| Starknet Cairo target candidate | [targets/starknet-cairo.md](targets/starknet-cairo.md) |
| Aleo Leo target candidate | [targets/aleo-leo.md](targets/aleo-leo.md) |
| TON TVM target candidate | [targets/ton-tvm.md](targets/ton-tvm.md) |
| Bitcoin Script/Miniscript target candidate | [targets/bitcoin-script-miniscript.md](targets/bitcoin-script-miniscript.md) |
| Zcash Shielded target candidate | [targets/zcash-shielded.md](targets/zcash-shielded.md) |
| Bitcoin Cash CashScript target candidate | [targets/bitcoin-cash-cashscript.md](targets/bitcoin-cash-cashscript.md) |
| Psy/DPN ZK target | [targets/psy-dpn.md](targets/psy-dpn.md) |
| Kaspa/Toccata target candidate | [targets/kaspa-toccata.md](targets/kaspa-toccata.md) |

## Superseded Positions

These earlier doc positions are no longer authoritative:

- RFC 0001 Phase 2 = Solana only, Phase 3 = Wasm only — replaced by parallel Phase 2 spikes (D-003).
- Milestone 3 = Solana as the single second target — replaced by parallel CosmWasm + Solana (D-003).
- CLI id `solana-sbf` — use `solana-sbpf-asm` (D-026).
- Move POC generates both Sui and Aptos packages at once — Aptos first (D-007).
- D-034 "open Tier-1 (cosmwasm + aptos) in parallel after Gate G0" — for the current phase, Tier-0 completion-first (D-044) and the primary-chain completion covenant (D-045) take precedence: finish `solana-sbpf-asm`/`evm`/`wasm-near` to production-grade DoD before advancing any Tier-1 spike past its current state.
- D-039's original "no code changes until Workstream 29 M1" wording — corrected on 2026-07-03 after review found M1 already landed; RFC 0009 is accepted with M1 implemented and M3/M4 still open.
- decisions.md "Roadmap Summary" Phase 0–5 model — superseded by the tier/gate model in [target-roadmap](target-roadmap.md) (D-034); kept above only for traceability.
