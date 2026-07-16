# Deep-Dive: Formal-Verification Boundary vs. Advertised Product Surface

**Dimension:** `fv-boundary-vs-product-surface`
**Project:** ProofForge (`/Users/davirian/orca/projects/proof_forge`)
**Date:** 2026-07-10
**Branch:** `main`

## Executive summary

ProofForge’s formal-verification scaffold is real and CI-gated, but the *proved* fragment is still essentially Counter-shaped. Of the seven documented product examples, only `Counter` has a closed `∀ (m : Module)` refinement theorem (`ProofForge.Backend.Refinement.CounterUniversal`). `ValueVault` has C-diff trace obligations and shallow universal step lemmas, but is not admitted to `TargetSemantics.supportedFragment`. `Ownable` and `StakingVault` already fit the *constructor* coverage of the fueled interpreter, yet no backend trace obligations or refinement theorems exist for them. `RoleGatedToken` is excluded by a single gap constructor (`storagePathRead`/`storagePathWrite`, introduced by `guard_role`). `RemoteCall` is axiomatized as a deterministic stub. `Token` (`FungibleToken`) lives in the separate `TokenSpec` intent layer and is validated only by target-specific runtime differential tests (ERC-20 Foundry/Anvil, SPL Token Surfpool, NEP-141 smokes).

Build artifacts today record capabilities, toolchain versions, and validation status, but they do **not** emit any proof manifest, theorem list, or signed certificate. External toolchains (`solc`, `wat2wasm`, `sbpf`, `leo`, chain runtimes) remain outside the proof TCB; the only external-verification evidence is a Counter-only Yul→bytecode smoke and a powdr runtime-witness hash check.

**Top 3 findings**

1. **The C-proof fragment is Counter-only.** Only `Counter` has a closed `∀ (m : Module)` refinement theorem (`CounterUniversal.lean:402-434`). `ValueVault` has C-diff trace obligations and shallow step simulation, but **not** in `supportedFragment`. `Ownable`, `StakingVault`, `RoleGatedToken`, `Token`, and `RemoteCall` have no `∀` refinement.
2. **Constructor coverage is wider than the proved fragment, but still gating real examples.** `Ownable` and `StakingVault` pass `moduleInCoveredFragment` (verified at runtime: both `true`). `RoleGatedToken` fails (`false`) because `guard_role` lowers to `storagePathRead`/`storagePathWrite`, which are `gap` in `ConstructorCoverage.lean`.
3. **No proof manifest is emitted.** `proof-forge-artifact.json` lists capabilities, tool versions, and validation results (`EvmArtifacts.lean:556-612`), but it never records which theorem was discharged, which fragment predicate applied, or what external-toolchain boundary was crossed.

---

## 1. Product example → FV coverage status

The tiers used below match `docs/formal-verification.md:40-59`:

| Tier | Meaning |
|---|---|
| **C-proof** | Universally-quantified Lean refinement theorem (`∀` module/call-list/state). |
| **C-diff** | Fixed-scenario differential trace check between IR and a target interpreter/artifact. |
| **Pointwise simulation** | `native_decide` paired-step check on a fixed trace; not `∀`. |
| **Differential test** | Runtime/product smoke that compares generated artifacts against reference behavior. |
| **Axiomatized / stub** | Semantics is intentionally a stub (e.g., crosscall) with no peer-VM equivalence. |
| **Outside** | Not in the proved fragment and no IR-level trace obligation. |

| Product example | C-proof | C-diff / pointwise | Differential test | Axiomatized / outside | Key evidence |
|---|---|---|---|---|---|
| **Counter** | ✅ `counterModel_fragment_refines_all_of_isCounterModule` (`CounterUniversal.lean:402-434`) | ✅ EVM Yul host (`YulHostRefinement.lean:84-99`), Wasm/NEAR (`WasmHost/Refinement.lean:55-111`), Solana sBPF (`Solana/Refinement.lean:140-175`) | ✅ `just product`, `just testkit`, Foundry/Anvil smokes | — | `ConstructorCoverage.lean:776-780` covered capabilities; `Tests/ConstructorCoverageSmoke.lean:110-112` |
| **ValueVault** | ⚠️ Partial: shallow `valueVault_step_simulates_all_calls` + fuel coverage, but **not** in `supportedFragment` | ✅ EVM Yul host multi-field storage relation (`YulHostRefinement.lean:213-258`), Wasm/NEAR, Solana sBPF scalar/event | ✅ `just value-vault-wasm-refinement-smoke`, `just testkit` | — | `docs/formal-verification.md:287`; `ValueVaultInvariant.lean:134-146` |
| **Ownable** | ❌ | ❌ No backend trace obligation | ✅ EVM compile + Foundry smokes via `Examples/Product/Ownable.lean` | In constructor fragment only | `ProofForge/Contract/Stdlib/Ownable.lean:28-51`; `moduleInCoveredFragment = true` (verified at runtime) |
| **Token** (`FungibleToken` / `TokenSpec`) | ❌ | ❌ | ✅ ERC-20 EVM runtime smoke (`just token-intent-evm-vm`), SPL Token Surfpool, NEP-141 plan | Outside IR fragment; intent-layer only | `Examples/Product/FungibleToken.lean:38-44`; `ProofForge/Contract/Token.lean:267+` |
| **RemoteCall** | ❌ | ❌ | ✅ `just crosscall-materialize`, multi-target smokes | ✅ `crosscall.invoke` is deterministic IR stub, not peer-VM semantics | `Examples/Product/RemoteCall.lean:25-38`; `docs/formal-verification.md:61-82`; `Tests/ConstructorCoverageSmoke.lean:126-128` |
| **StakingVault** | ❌ | ❌ | ✅ `scripts/portable/staking-vault-multi-target.sh`, `just testkit` | In constructor fragment, but no theorem | `Examples/Product/StakingVault.lean:43-89`; `moduleInCoveredFragment = true` (verified at runtime) |
| **RoleGatedToken** | ❌ | ❌ | ✅ `scripts/portable/role-gated-token-multi-target.sh`, `just testkit` | Outside constructor fragment | `Examples/Product/RoleGatedToken.lean:43-99`; `moduleInCoveredFragment = false` (verified at runtime) |

### How the coverage map was verified

The `moduleInCoveredFragment` predicate is the machine-checked constructor-coverage gate (`ConstructorCoverage.lean:619-634`). I evaluated it at runtime for the product modules:

```text
Counter:       true
Ownable:       true
ValueVault:    true
RemoteCall:    false
StakingVault:  true
RoleGatedToken: false
```

This confirms `Tests/ConstructorCoverageSmoke.lean`’s explicit claims and extends them to `StakingVault` and `RoleGatedToken`.

---

## 2. IR constructors / capabilities needed for Token + basic Ownable/auth

### Current proved-fragment capability set

`ConstructorCoverage.lean:776-780` pins the capability subset that the C-proof fragment currently admits:

```lean
def coveredCapabilities : Array Capability :=
  #[ .storageScalar, .storageMap, .callerSender, .eventsEmit,
     .controlConditional, .checkedArithmetic, .assertions ]
```

### Basic Ownable/auth: already covered

`Ownable` uses only:

* scalar storage (`storageScalar`),
* caller context read (`callerSender`),
* equality/assert (`assertions`),
* conditional/assignment.

All of these are already `fuelCovered` (`SemanticsFuel.lean:84-191`; `ConstructorCoverage.lean:65-96`). The gap is not constructors, but **backend refinement**: there is no `OwnableTraceObligation`, no `ownable_yul_trace_simulation_ok`, and no `supportedFragment` admission in any backend.

### Simple token (contract_source style): already constructor-covered

A token with `balances : Map<U64,U64>`, `totalSupply : U64`, `Transfer`/`Approval` events, and `require` guards uses:

* `storageMap` (balances/allowances),
* `storageScalar` (totalSupply),
* `callerSender` (allowance owner/spender checks),
* `eventsEmit`/`eventEmitIndexed`,
* `assertions`,
* `checkedArithmetic` (if EVM overflow-checked),
* `controlConditional`.

All of these are in `coveredCapabilities`. So a hand-written `contract_source` token could be admitted to the constructor fragment today **if** a backend trace obligation and refinement theorem were supplied.

### Role-gated token: needs nested storage paths

`RoleGatedToken` fails `moduleInCoveredFragment` because role membership is modelled as a **nested path**, not a flat map key:

* `guard_role` macro (`Source.lean:478-481`) expands to `Surface.requireRole`,
* `requireRole` (`Surface.lean:338-340`) reads via `pathRead members.id (allowancePath roleKey accountKey)`,
* `pathRead` (`Surface.lean:328-329`) produces `Effect.storagePathRead`.

`storagePathRead`/`storagePathWrite` are **not** in `fuelCoveredEffect` (`ConstructorCoverage.lean:77-85` matches only scalar/map/struct/context/event effects; `_ => false`). The same gap blocks `pathWriteRole`.

Therefore, to cover `RoleGatedToken` in the proved fragment, one of the following must enter the fragment:

1. **Add `storagePathRead`/`storagePathWrite` to `SemanticsFuel`** and prove IR-side preservation lemmas for them, plus per-target lowering preservation; or
2. **Change the DSL** so role membership uses a composite single-key map (e.g., `Map<(role,account), bool>` via `storageMapGet`/`storageMapSet`), which are already covered.

### TokenSpec intent layer: separate, larger gap

`FungibleToken` is a `TokenSpec` (`Examples/Product/FungibleToken.lean:38-44`), not an `IR.Module`. The TokenSpec→artifact pipeline is tracked by FV-7 (`docs/formal-verification.md:247-257`) and is currently validated only by differential runtime tests. To bring it into the proved fragment would require:

* a formal `TokenSpec` semantics,
* a proved lowering from `TokenSpec` to `ContractSpec`/`IR.Module`,
* per-target refinement theorems for the generated ERC-20/SPL/NEP-141 shapes.

This is strictly larger than extending the IR constructor set.

### Backend refinement obligations, not just constructors

Even after constructor coverage is widened, a module gains a C-proof theorem only when a backend proves:

* a `fragmentAccepts` predicate (`Core.lean:1163-1165`),
* per-entrypoint `step_simulates` lemmas using `traceSimulation_lift` (`Core.lean:1006-1027`),
* a target-specific `TargetSemantics` instance.

Today only `Counter` has this end-to-end chain; `ValueVault` has the lemmas but not `supportedFragment` admission. Adding `Ownable`/`StakingVault`/simple-token to C-proof therefore requires **new backend trace obligations and refinement theorems**, not just a wider constructor table.

---

## 3. External-toolchain trust boundaries and user-visible assurance

### External toolchains in the trust boundary today

`docs/formal-verification.md:325-327` explicitly lists these as **non-goals** for formal proof:

| Target | External tools trusted by the default build | Where used |
|---|---|---|
| EVM | `solc` (Yul→bytecode), Foundry/Anvil (runtime/deploy), `cast` (ABI hydration) | `ProofForge.Target.Registry.lean:107`; `EvmArtifacts.lean:503-584`; `scripts/evm/foundry-smoke.sh`; `scripts/evm/anvil-deploy-smoke.sh` |
| NEAR/Wasm | `wat2wasm` (WAT→Wasm), `near-cli` (deploy), Rust/Cargo (`runtime/offline-host`) | `Registry.lean:141-147`; `scripts/near/emitwat-ci-smoke.sh` |
| Solana | `sbpf` (asm→ELF), optional `mollusk-svm`/`surfpool` (runtime differential) | `Registry.lean:313-316`; `just solana-light` |
| CosmWasm | `wat2wasm`, `cosmwasm-check` | `Registry.lean:167-178` |
| Soroban | `wat2wasm`, Stellar CLI (follow-on) | `Registry.lean:218-250` |
| Move | `aptos`, `sui` | `Registry.lean:330-378` |
| Psy DPN | `dargo` | `Registry.lean:402-406` |
| Aleo | `leo` | `Registry.lean:422-453` |

### Evidence of external verification *for Counter only*

The default EVM lane proves Yul-subset behavior, not Yul→bytecode equivalence. The only external-verification evidence is:

* `scripts/evm/yul-compiler-counter-smoke.sh` — compiles emitted Counter Yul with `solc --strict-assembly` and checks it matches the powdr witness runtime hash.
* `scripts/evm/powdr-counter-runtime-smoke.sh` — checks the CLI-emitted Counter runtime bytecode SHA-256 matches the embedded powdr witness.

Both are Counter-only. `docs/formal-verification.md:96-144` states the EVM bytecode lane trusts powdr `stepF` + Lean native evaluator and is opt-in.

### Current artifact metadata

`build/evm/Counter.proof-forge-artifact.json` and the `testkit/evm/*.proof-forge-artifact.json` files contain:

* `capabilities` — e.g., `["storage.scalar"]` for Counter, `["storage.map","storage.scalar","caller.sender","assertions.check","events.emit"]` for `RoleGatedToken`.
* `toolchain` — e.g., `{"solc": {"path":"solc","version":"0.8.34..."}}`.
* `validation` — `solcStrictAssembly`, `bytecodeGeneration`, `initCodeGeneration`, `deployManifest`, `contractSizeCheck`.
* `artifactBundle` — SHA-256 and byte sizes for Yul/bytecode/initcode, source identity, tool provenance, validation entries.

This is emitted in `ProofForge/Cli/EvmArtifacts.lean:556-612`. The `ArtifactBundle` schema in `ProofForge/Target/ArtifactBundle.lean:96-104` already has `validations` and `toolchain` arrays.

### What is missing

There is **no** machine-checkable proof output. A user cannot tell from the artifact:

* whether the module was in a proved fragment,
* which theorem(s) were discharged,
* whether the proof used `decide` (kernel-only) or `native_decide` (trusts Lean native evaluator),
* whether the proof relied on powdr `stepF`,
* which external-toolchain boundary was crossed,
* which scenario(s) the C-diff check covered.

### Recommended per-build assurance

The existing metadata schema can be extended without changing file names. Add a top-level `proofManifest` object (and corresponding `ValidationEntry` names in `ArtifactBundle`) that records:

```json
"proofManifest": {
  "fragment": "counter-model",
  "fragmentPredicate": "ProofForge.Backend.Refinement.ConstructorCoverage.moduleInCoveredFragment",
  "dischargedTheorems": [
    "ProofForge.Backend.Refinement.CounterUniversal.counterModel_fragment_refines_all_of_isCounterModule"
  ],
  "evaluatorTrust": ["native_decide"],
  "externalToolchainBoundary": [
    {"tool": "solc", "stage": "yul-to-bytecode", "verified": false, "differentialSmoke": "scripts/evm/yul-compiler-counter-smoke.sh"}
  ],
  "coveredScenarios": ["Counter.initialize/increment/get"],
  "unsupportedConstructors": []
}
```

For modules outside the proved fragment, the manifest should be honest:

```json
"proofManifest": {
  "fragment": null,
  "dischargedTheorems": [],
  "evaluatorTrust": [],
  "note": "Differentially tested only; no ∀-module refinement theorem."
}
```

This turns the FV boundary from an internal documentation issue into a machine-readable, auditable build output.

---

## References

* `ProofForge/Backend/Refinement/ConstructorCoverage.lean:65-96` — fuel-covered predicates.
* `ProofForge/Backend/Refinement/ConstructorCoverage.lean:107-118` — constructor status table.
* `ProofForge/Backend/Refinement/ConstructorCoverage.lean:619-634` — `moduleInCoveredFragment`.
* `ProofForge/Backend/Refinement/ConstructorCoverage.lean:723-746` — product module coverage map.
* `ProofForge/Backend/Refinement/ConstructorCoverage.lean:776-780` — `coveredCapabilities`.
* `ProofForge/Backend/Refinement/CounterUniversal.lean:402-434` — closed `∀` Counter refinement theorem.
* `ProofForge/Backend/Evm/YulHostRefinement.lean:84-99`, `:213-258` — Counter/ValueVault C-diff Yul host checks.
* `ProofForge/Contract/Stdlib/Ownable.lean:28-51` — Ownable source.
* `ProofForge/Contract/Surface.lean:328-340` — `pathRead`/`requireRole` use `storagePathRead`.
* `ProofForge/Contract/Source.lean:478-481` — `guard_role` macro expansion.
* `ProofForge/Target/Registry.lean:81-114`, `:116-148`, `:280-317` — target profiles and capabilities.
* `ProofForge/Target/FormalBoundary.lean:31-57` — FV-1 `resolveSpec` soundness checks.
* `ProofForge/Cli/EvmArtifacts.lean:556-612` — EVM artifact metadata emission.
* `ProofForge/Target/ArtifactBundle.lean:96-104` — bundle schema with `validations`/`toolchain`.
* `docs/formal-verification.md:40-59`, `:284-302`, `:325-327` — verification tiers, fragment inventory, non-goals.
* `docs/validation-gates.md` — runnable gates and external-toolchain dependencies.
