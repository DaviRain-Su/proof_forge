# Gap Analysis: Backend Target Maturity

**Dimension:** backend-target-maturity
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Branch:** main (dirty: `docs/zh/INDEX.zh.md`, `scripts/i18n/manifest.json`, `scripts/near/target-first-smoke.sh`)

## Scope

This analysis compares the current state of ProofForge's target/back-end surface against what a real, production-grade multi-chain compiler/CLI product would require. It covers the target registry, backend implementations, CLI routing, CI gates, docs, and toolchains.

## Overall Maturity Score

**6 / 10**

The three primary chains (`evm`, `solana-sbpf-asm`, `wasm-near`) are intentionally hardened to a high local/CI standard, but the *majority* of listed targets are Counter-MVP/fixture-only or research spikes, and the CLI still routes new surface commands through legacy flag translation.

## What Appears Complete / Healthy

- **Registry contract is machine-readable and tested.** `ProofForge.Target.Registry` (lines 81–453) defines 12 profiles, `TargetSupport` (lines 84–93) captures maturity/input/commands/output/validation, and `Tests/TargetSupport.lean` enforces that only the primary triad advertises `contract-source` + `build`/`check` + `package` validation.
- **Primary triad has real backend hooks.** `ProofForge.Target.BackendRegistry` (lines 26–96) wires `validateModule?`, `ensurePlan?`, and `ensurePackage?` for EVM, Solana sBPF asm, and NEAR/Wasm. `Tests/TargetBackend.lean` (lines 24–47) exercises the full `validate → plan → resolve → package` path on `Counter`.
- **Honest fail-closed behavior.** `ProofForge.Cli.Check.lean` (lines 208–213, 215–231, 335–353) rejects source builds for fixture-only targets and never silently substitutes Counter.
- **CI is product-first.** `.github/workflows/ci.yml` (lines 14–63) runs `just product` as a required gate before the backend-heavy `build-test` job; `.woodpecker.yml` (lines 17–31) mirrors the same product-then-check flow.
- **Generated backend-status stays in sync.** `docs/generated/backend-status.md` is produced from `--list-targets --json` via `scripts/docs/generate-backend-status.py` and matches the registry.
- **EVM backend is the deepest.** 99 IR constructors classified, Foundry/Anvil deploy smokes, dynamic constructors, UUPS proxy, ERC-20/721/1155/165/4626, AccessControl, Pausable, ReentrancyGuard, Create2 (see `docs/sdk-ecosystem-gaps-2026-07.md`).
- **Solana backend has rich extensions.** PDA derivation, CPI packing, Token-2022 extensions, ComputeBudgetInstruction, Pinocchio reference-equivalence gates (`just solana-pinocchio-reference-equivalence`).
- **Formal verification anchors exist** for the primary triad and are exercised in `just check` (`evm-yul-host-refinement-smoke`, `solana-refinement-smoke`, `value-vault-wasm-refinement-smoke`, etc.).

## Identified Gaps

| # | Area | Evidence | Severity | Remediation Direction |
|---|------|----------|----------|-----------------------|
| 1 | **Most listed targets lack real backend hooks** | Of 10 `--list-targets` entries, only `evm`, `solana-sbpf-asm`, and `wasm-near` have `validateModule?`/`ensurePlan?`/`ensurePackage?` hooks (`ProofForge.Target.BackendRegistry.lean:77–96`). `wasm-cosmwasm`, `wasm-stellar-soroban`, `move-aptos`, `move-sui`, `psy-dpn`, `aleo-leo`, and `wasm-cloudflare-workers` are profile + CLI driver only; `Tests/TargetBackend.lean:54–61` explicitly confirms `wasm-cosmwasm` fails closed on `validateModule`. | **Blocker** for claiming them as product backends | Migrate each target to real `TargetBackend` hooks before marketing it as a build target; keep Counter-MVP profiles honest in the generated matrix. |
| 2 | **CLI target-first surface still translates to legacy flags** | `ProofForge.Cli.TargetFirst.lean:167–221` converts new `build`/`emit` commands into legacy internal flags (`--evm-bytecode`, `--emit-counter-ir-sbpf`, etc.). `check` is explicitly stubbed: `"proof-forge check is not yet implemented"` (`ProofForge.Cli.TargetFirst.lean:219`). | **High** | Finish the M3/M4 target-first migration so `build`/`emit`/`check` are native registry-driven paths; implement `check` in the new surface. |
| 3 | **Move-family targets are Counter-only and source-fail-closed** | `move-sui` supports only `storageScalar`, `assertions`, `accountExplicit` (`ProofForge.Target.Registry.lean:359–378`). `move-aptos` supports only scalar + assertions (`ProofForge.Backend.Move.Aptos.lean:32–36`). Both scripts (`scripts/cli/aptos-promotion-smoke.sh:35–43`, `scripts/cli/sui-promotion-smoke.sh:18–26`) assert that `Examples/Product/Counter.lean` *fails* on source build. | **High** | Expand Move lowering to maps, events, structs, and crosscalls, or clearly scope Move targets as research until after Aptos M4 / Sui beyond-Counter work is scheduled. |
| 4 | **Wasm-host secondary targets are thin adapters** | `wasm-cosmwasm` product path uses `HostBridge.cosmWasm` but `execute_msg` is a stub (`ProofForge.Target.Registry.lean:175–178`). `wasm-stellar-soroban` auth is `require_auth_for_args` always-auth in Lean (`ProofForge.Backend.WasmHost.SorobanHost.lean:78–90`) and Stellar CLI/TTL are follow-on (`docs/targets/README.md:90`). `wasm-cloudflare-workers` emits TypeScript only (`ProofForge.Target.Registry.lean:181–211`). | **High** | Close the host-bridge adapter gaps (real CosmWasm execute dispatch, Soroban auth/TTL, etc.) before calling them product targets; keep research targets out of `--list-targets` or mark `research` maturity. |
| 5 | **NEAR/Wasm still has significant depth gaps** | `docs/sdk-ecosystem-gaps-2026-07.md` lists missing `keccak256`, `storage_remove`, `balance_of`, full NEP-148/171/178/448, dynamic Borsh bytes/string ABI, real network broadcast tool, and full callback dispatch. TokenSpec bare build fails with a diagnostic requiring `--token` (`docs/sdk-ecosystem-gaps-2026-07.md:160`). | **Medium** (P1 expansion) | Prioritize the P1 NEAR gaps; at minimum document them as known limitations and avoid implying full NEAR SDK parity. |
| 6 | **Aleo / Psy ZK lane is research / Counter MVP** | `aleo-leo` is Road 1 sourcegen; private records/proofs are Road 2 (`docs/targets/aleo-leo.md`, `ProofForge.Backend.Aleo.IR.lean:30–34`). `psy-dpn` requires `dargo` which is not in the default toolchain (`AGENTS.md:43`). | **Medium** | Treat ZK targets as research until Road 2 capabilities land; do not list them in product marketing as deployable backends. |
| 7 | **TokenSpec parity is not broad** | `wasm-cosmwasm` and `wasm-stellar-soroban` have no TokenSpec lane (`ProofForge.Cli.TargetDriver.lean:223–226`, `244–251`). NEAR TokenSpec needs `--token` (`ProofForge.Cli.TargetDriver.lean:180–184`). | **Medium** | Either implement TokenSpec lowering for secondary targets or document the limitation explicitly in the support matrix. |
| 8 | **Deployment tooling is uneven across targets** | EVM has Anvil deploy (`just evm-anvil-deploy`). Solana has Surfpool live gates (`just solana-counter-live`). NEAR has no broadcast tool (`docs/sdk-ecosystem-gaps-2026-07.md:226–228`). Aptos/Sui require external CLIs. Aleo needs `leo`. | **Medium** | Build a uniform deploy manifest + broadcast abstraction, or honestly scope each target's deploy stage in `toolStages`. |
| 9 | **Capability registry acceptance criteria are partially unmet** | `docs/capability-registry.md:463–468` Phase 1 checklist still has unchecked items: every id in the table appears in `TargetProfile.capabilities`, EVM Counter artifact metadata lists used capabilities, and `storage.pda` on EVM fails closed. | **Low** | Close the checklist and add tests in `Tests/TargetSupport.lean` or `Tests/TargetRegistry.lean`. |
| 10 | **Offline runtime host is NEAR-only** | `runtime/offline-host` executes Wasm/NEAR WAT. There is no equivalent in-process runtime for EVM or Solana in the unified testkit; Solana relies on optional `mollusk-svm` (`docs/validation-gates.md` preview). | **Low** | Extend the offline host / testkit to cover EVM (revm) and Solana (mollusk) deterministically without optional tools. |

## Top 5 Gaps (Ranked)

1. **Most targets are registry entries without real backend hooks** — claiming 10 supported targets while only 3 have validate/plan/package implementations is a product credibility blocker.
2. **CLI target-first commands route through legacy flag translation** — the user-facing surface is not yet native; `check` is unimplemented.
3. **Move-family targets are Counter-only and reject product sources** — they cannot run the same `Examples/Product/*.lean` contracts that the primary triad runs.
4. **Wasm-host secondary targets are incomplete adapters** — CosmWasm execute is a stub, Soroban auth is always-auth, Cloudflare is TS-only.
5. **NEAR still lacks standard SDK/ecosystem depth** — keccak, storage_remove, NFT standards, dynamic Borsh, and real broadcast are missing.

## Recommendation

Do not market ProofForge as a "10-target compiler" today. The honest product surface is the three primary chains plus a set of actively maintained Counter-MVP/research spikes. The next product-readiness milestone should be completing the CLI M3/M4 target-first migration and either demoting research targets or implementing real backend hooks for at least CosmWasm and Aptos before expanding the target roster further.
