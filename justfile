set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List available ProofForge development commands.
default:
    @just --list

# Build the Lean package and proof-forge executable.
build:
    lake build

# Check the target registry smoke.
target-registry:
    lake env lean --run Tests/TargetRegistry.lean

# Check target-neutral ContractSpec JSON schema output.
contract-spec-json:
    lake env lean --run Tests/ContractSpecJson.lean

# Check generated target wrapper sketches from ContractSpec.
contract-client:
    lake env lean --run Tests/ContractClient.lean

# Check unified SDK schema generation, target extensions, diagnostics, and refs.
sdk-schema:
    lake env lean --run Tests/SdkSchema.lean
    lake env lean --run Tests/SdkSchemaExtensions.lean
    lake env lean --run Tests/SdkSchemaDiagnostics.lean
    lake env lean --run Tests/SuiSdkSchema.lean
    python3 scripts/sdk/validate-sdk-schema.py build/sdk/*/proof-forge-sdk.json --expect-schema proof-forge.sdk-schema.v0 --expect-ir portable-ir-v0
    python3 scripts/sdk/validate-sdk-artifact-refs.py --require-relative --reject-absolute build/sdk/*/proof-forge-sdk.json
    scripts/sdk/schema-determinism-smoke.sh
    scripts/sdk/discoverability-smoke.sh
    python3 scripts/sdk/validate-sdk-schema.py build/sdk/*/proof-forge-sdk.json --expect-schema proof-forge.sdk-schema.v0 --expect-ir portable-ir-v0
    python3 scripts/sdk/validate-sdk-artifact-refs.py --require-relative --reject-absolute build/sdk/*/proof-forge-sdk.json
    scripts/sdk/validate-sdk-layout.py build/sdk

# Check the proof-forge deploy command parser and defaults.
cli-deploy:
    lake env lean --run Tests/CliDeploy.lean

# Check structured proof-forge check diagnostics.
cli-check:
    lake env lean --run Tests/CliCheck.lean

# Check that shared contract_source examples match their legacy Learn fixtures.
shared-contract-source:
    lake env lean --run Tests/SharedContractSource.lean

# Check shared TokenSpec intents and legacy Learn equivalence fixtures.
shared-token-intent:
    lake build Examples.Shared.FungibleToken Examples.Shared.FeeToken Examples.Shared.SoulboundToken
    lake env lean --run Tests/SharedTokenIntent.lean

# Run the CosmWasm Counter WAT emission smoke through wat2wasm and cosmwasm-check.
cosmwasm-counter-smoke:
    scripts/cosmwasm/counter-smoke.sh

# Run the Aptos Move Counter sourcegen smoke through aptos move compile/test.
aptos-counter-smoke:
    scripts/aptos/counter-smoke.sh

# Emit and diff tracked Aptos Move example artifacts.
aptos-build-examples:
    scripts/aptos/build-examples.sh

# Run Aptos unsupported-shape diagnostic smoke.
aptos-diagnostics:
    lake env lean --run Tests/AptosDiagnostics.lean

# Emit and validate the Sui Move Counter package layout.
sui-build-examples:
    scripts/sui/build-examples.sh

# Run the Sui Move Counter package through local sui move build/test.
sui-counter-smoke:
    scripts/sui/counter-smoke.sh

# Run Sui unsupported-shape diagnostic smoke.
sui-diagnostics:
    lake env lean --run Tests/SuiDiagnostics.lean

# Check Sui emit/build target-first package parity.
sui-emit-build-parity:
    scripts/sui/emit-build-parity-smoke.sh

# Check generated Sui object source avoids Aptos/global-storage patterns.
sui-object-semantics:
    scripts/sui/object-semantics-smoke.sh

# Check Sui validation stays local to sui move build/test.
sui-local-only:
    scripts/sui/local-only-smoke.sh

# Type-check the generated Sui client in a minimal consumer smoke.
sui-client-ts-smoke:
    scripts/sui/client-ts-smoke.sh

# Check the EVM semantic plan smoke.
evm-plan:
    lake build ProofForge.Backend.Evm.Plan
    lake env lean --run Tests/EvmPlan.lean

# Check the EVM semantic plan (entrypoints, events, metadata) smoke.
evm-semantic-plan:
    lake build ProofForge.Backend.Evm.IR ProofForge.IR.Examples.Counter ProofForge.IR.Examples.EvmMapProbe ProofForge.IR.Examples.EvmStorageArrayProbe ProofForge.IR.Examples.EvmStorageStructProbe ProofForge.IR.Examples.EventProbe
    lake env lean --run Tests/EvmSemanticPlan.lean

# Check the RFC 0014 Phase 1 shared validate subset (identifiers, return-path predicate, type-check helpers).
shared-validate-smoke:
    lake build ProofForge.Backend.SharedValidate
    lake env lean --run Tests/SharedValidate.lean

# Check the RFC 0014 Phase 3 shared lowering diagnostic contract (LoweringDiagnostic + LoweringError typeclass).
diagnostic-smoke:
    lake build ProofForge.Backend.Diagnostic
    lake env lean --run Tests/Diagnostic.lean

# Check RFC 0014 Phase 6a inductive IR trace semantics (IRTraceMatches + soundness by induction).
ir-step-semantics-smoke:
    lake build ProofForge.IR.StepSemantics ProofForge.Backend.Evm.Refinement
    lake env lean --run Tests/IRStepSemantics.lean

# Check Track 1.1 total Counter-fragment IR semantics for the first universal C-proof path.
ir-counter-semantics-smoke:
    lake build ProofForge.IR.CounterSemantics
    lake env lean --run Tests/IRCounterSemantics.lean

# Check the first all-call-list Counter simulation proof over total IR semantics.
counter-universal-refinement-smoke:
    lake build ProofForge.Backend.Refinement.CounterUniversal
    lake env lean --run Tests/CounterUniversalRefinement.lean

# Check proof-fragment boundaries for TargetSemantics-supported modules.
supported-fragment-smoke:
    lake build ProofForge.Backend.Refinement.Core ProofForge.Backend.Refinement.CounterUniversal
    lake env lean --run Tests/SupportedFragment.lean

# Check existing executable trace runners are wired through the shared TargetSemantics interface.
target-semantics-instances-smoke:
    lake build ProofForge.Backend.Evm.Refinement ProofForge.Backend.Solana.Refinement ProofForge.Backend.WasmNear.Refinement
    lake env lean --run Tests/TargetSemanticsInstances.lean

# Generic Wasm stack/state helper lemmas - active WASM C-proof surface.
wasm-exec-smoke:
    lake build ProofForge.Backend.WasmNear.WasmExec
    lake env lean --run Tests/WasmExec.lean

# NEAR host-model lemmas over the generic Wasm host-call hook.
wasm-near-host-smoke:
    lake build ProofForge.Backend.WasmNear.NearHost
    lake env lean --run Tests/WasmNearHost.lean

wasm-cosmwasm-host-smoke:
    lake build ProofForge.Backend.WasmNear.CosmWasmHost
    lake env lean --run Tests/WasmCosmWasmHost.lean

# WASM-5a contract axis: ValueVault universal IR↔Wasm core refinement.
value-vault-wasm-refinement-smoke:
    lake build ProofForge.Backend.WasmNear.ValueVaultWasmRefinement
    lake env lean --run Tests/ValueVaultWasmRefinement.lean

# WASM-5b chain-axis: Counter reuses the SAME host-agnostic core on CosmWasm.
wasm-cosmwasm-refinement-smoke:
    lake build ProofForge.Backend.WasmNear.CounterCosmWasmRefinement
    lake env lean --run Tests/WasmCosmWasmRefinementSmoke.lean

# Check the Phase 6b EVM bytecode-semantics seam for the preferred powdr target.
evm-bytecode-semantics-smoke:
    lake build ProofForge.Backend.Evm.EvmBytecodeSemantics
    lake env lean --run Tests/EvmBytecodeSemantics.lean

# Check the opt-in powdr/mathlib EVM refinement adapter target.
evm-powdr-adapter:
    lake build EvmRefinement

# Check that the generated Counter runtime matches the embedded powdr witness.
evm-powdr-counter-runtime: build
    scripts/evm/powdr-counter-runtime-smoke.sh

# Check the three-valued ExecResult (ok/reverted/error) classification for
# the IR reference semantics (FV-2 revert-model prerequisite).
ir-exec-result-smoke:
    lake env lean --run Tests/IRExecResult.lean

# Check the FV-5 checked-overflow capability gate (arith.checked: EVM accepts,
# Solana/NEAR reject checked-overflow modules).
fv5-overflow-smoke:
    lake build ProofForge.Target.FV5Overflow
    lake env lean --run Tests/FV5Overflow.lean

# Check that executable scripts/testkit callers use target-first CLI commands.
cli-target-first:
    python3 scripts/cli/check-target-first-migration.py
    lake env lean Tests/CliTargetFirst.lean

# Generic sBPF step lemmas — active C-proof surface (PRs touch SbpfExec here).
solana-sbpf-exec-smoke:
    lake build ProofForge.Backend.Solana.SbpfExec
    lake build ProofForge.Backend.Solana.SbpfExecSmoke
    lake env lean --run Tests/SolanaSbpfExec.lean

# Second-contract genericity smoke for the reusable sBPF execution layer.
solana-sbpf-genericity-smoke:
    lake build ProofForge.Backend.Solana.ValueVaultSbpfExec
    lake env lean --run Tests/SolanaValueVaultSbpfExec.lean

# Counter core-tail + IR↔sBPF refinement regression (frozen spike; do not expand).
solana-counter-sbpf-regression:
    lake build ProofForge.Backend.Solana.CounterSbpfExec
    lake build ProofForge.Backend.Solana.CounterSbpfRefinement
    lake env lean --run Tests/SolanaCounterSbpfRegression.lean

# Check the Solana sBPF refinement anchor (Counter IR trace + artifact surface).
solana-refinement-smoke:
    lake build ProofForge.Backend.Solana.Refinement
    lake env lean --run Tests/SolanaRefinement.lean

# Check contract_source target capability diagnostics through the CLI.
contract-source-diagnostics:
    scripts/contract-source/diagnostic-smoke.sh

# Run Solana target, SDK, and diagnostics tests that need only the Lean toolchain.
solana-lean:
    lake build
    lake build ProofForge.Contract.Token
    lake build ProofForge.Contract.Examples.Counter
    lake build ProofForge.Solana.Examples
    lake env lean --run Tests/SolanaDiagnostics.lean
    lake env lean --run Tests/SolanaSdk.lean
    lake env lean --run Tests/SolanaSdkManifest.lean
    lake env lean --run Tests/SolanaAccountConstraints.lean
    lake env lean --run Tests/SolanaAccountRealloc.lean
    lake env lean --run Tests/SolanaCpiPacking.lean
    lake env lean --run Tests/SolanaLogs.lean
    lake env lean --run Tests/SolanaSysvars.lean
    lake env lean --run Tests/SolanaMemory.lean
    lake env lean --run Tests/SolanaCrypto.lean
    lake env lean --run Tests/SolanaReturnDataCompute.lean
    lake env lean --run Tests/SolanaComputeBudgetInstruction.lean
    lake env lean --run Tests/SolanaPdaSeeds.lean
    lake env lean --run Tests/SolanaLoop.lean
    lake env lean --run Tests/SolanaStorageArray.lean
    lake env lean --run Tests/SolanaStorageArrayStruct.lean
    lake env lean --run Tests/SolanaStorageStructField.lean
    lake env lean --run Tests/SolanaFixedArrayStruct.lean
    lake env lean --run Tests/SolanaHash.lean
    lake env lean --run Tests/SolanaMemoryArray.lean
    lake env lean --run Tests/SolanaMapContextSafety.lean
    lake env lean --run Tests/LearnSource.lean
    lake env lean --run Tests/SharedContractSource.lean
    lake env lean --run Tests/LearnDiagnostics.lean
    lake env lean --run Tests/TargetRouting.lean
    lake env lean --run Tests/ValueVaultExample.lean
    lake env lean --run Tests/SharedTokenIntent.lean
    lake env lean --run Tests/TokenSpec.lean
    lake env lean --run Tests/TokenLearn.lean
    lake env lean --run Tests/TokenEvm.lean

# Emit and diff tracked Solana sBPF example artifacts.
solana-build-examples:
    scripts/solana/build-examples.sh

# Run Solana control-flow/assertion emission smoke.
solana-emit-control:
    scripts/solana/emit-control-smoke.sh

# Run Solana SDK artifact smoke. The sbpf build portion is optional.
solana-sdk-smoke:
    scripts/solana/sdk-smoke.sh

# Run a live Solana Counter deploy/invoke smoke on Surfpool with the Rust harness.
solana-counter-live:
    scripts/solana/counter-live-smoke.sh

# Run the portable ValueVault SDK smoke across EVM Yul and Solana sBPF outputs.
portable-value-vault:
    scripts/portable/value-vault-smoke.sh

# Check that legacy Learn-token gate names only forward to token intent gates.
token-compat-wrappers:
    python3 scripts/portable/check-token-compat-wrappers.py

# Run the shared token intent SDK smoke across EVM and Solana target outputs.
token-intent-smoke: token-compat-wrappers
    scripts/portable/token-intent-smoke.sh

# Compatibility alias for the former Learn-token-centric smoke name.
learn-token-smoke: token-intent-smoke

# Run the shared token intent EVM artifact in a local Rust/revm VM.
token-intent-evm-vm: token-compat-wrappers
    scripts/evm/token-intent-evm-vm-smoke.sh

# Compatibility alias for the former Learn-token EVM VM smoke name.
learn-token-evm-vm: token-intent-evm-vm

# Run a live Solana SPL Token plan smoke on Surfpool with the Rust harness.
solana-token-plan-live:
    scripts/solana/token-plan-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-token-plan-web3: solana-token-plan-live

# Run the Wasm-NEAR target-first CLI, metadata, deploy-manifest, and offline-host smoke.
near-target-first:
    scripts/near/target-first-smoke.sh

# Check Wasm-NEAR Plan/EmitWat surface pruning. Builds the NEAR crosscall fixture
# first so stale oleans cannot turn this gate into a Lean segfault.
wasm-near-plan:
    lake build proof-forge ProofForge.IR.Examples.NearCrosscallProbe
    lake env lean --run Tests/WasmNearPlan.lean

# Run the NearModulePlan golden + dual-path parity smoke (Tier B gate, Step B).
# Builds the plan, diffs against golden, and asserts plan-driven WAT == inline WAT.
near-plan-smoke:
    scripts/near/plan-smoke.sh

# Check NEAR NEP-141 ft_transfer_call promise chain Plan + EmitWat smoke.
wasm-near-ft-transfer-call:
    lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken
    lake env lean --run Tests/WasmNearFtTransferCall.lean

# Run NEAR NEP-141 ft_transfer_call through the offline host promise callback path.
wasm-near-ft-transfer-call-e2e:
    scripts/near/ft-transfer-call-smoke.sh

# Build the shared portable Counter to EVM, Solana sBPF, and NEAR/Wasm from one source file.
portable-counter-multi-target:
    scripts/portable/counter-multi-target.sh

# Build the shared ArrayExample to EVM, Solana sBPF, and NEAR/Wasm from one source file.
portable-array-example-multi-target:
    scripts/portable/array-example-multi-target.sh

# Build portable stdlib core mixin examples to EVM, Solana sBPF, and NEAR/Wasm.
portable-stdlib-core-multi-target:
    scripts/portable/stdlib-core-multi-target.sh

# Generate and validate the portable Counter canonical SDK layout for all four SDK targets.
portable-counter-four-target-sdk:
    scripts/portable/counter-four-target-sdk.sh

# Build portable Counter SDK outputs from the shared source authoring path.
portable-source-counter-sdk:
    scripts/portable/source-counter-sdk-smoke.sh

# Check canonical SDK generation does not mutate legacy portable Counter outputs.
portable-legacy-output-stability:
    scripts/portable/legacy-output-stability-smoke.sh

# Validate local Counter runtime behavior across runnable EVM, Solana, NEAR, and Sui targets.
portable-counter-four-target-runtime:
    scripts/portable/counter-four-target-runtime-smoke.sh

# Build the shared RoleGatedToken to EVM, Solana sBPF, and NEAR/Wasm from one source file.
portable-role-gated-token-multi-target:
    scripts/portable/role-gated-token-multi-target.sh

# Build the shared StakingVault to EVM, Solana sBPF, and NEAR/Wasm from one source file.
portable-staking-vault-multi-target:
    scripts/portable/staking-vault-multi-target.sh

# Scaffold a portable Counter project with `proof-forge init` and build EVM + Solana.
portable-init-smoke:
    scripts/portable/init-smoke.sh

# Validate init + Foundry workspace (forge test/script on stable build/evm paths).
portable-foundry-workspace:
    scripts/portable/foundry-workspace-smoke.sh

# Run proof-forge check diagnostics on a scaffolded portable project.
portable-check-smoke:
    scripts/portable/check-smoke.sh

# Validate init project emits EVM TypeScript client beside build/evm artifacts.
portable-evm-client:
    scripts/portable/evm-client-smoke.sh

# Run a live Solana Token-2022 transfer-fee plan smoke on Surfpool with the Rust harness.
solana-token-2022-transfer-fee-live:
    scripts/solana/token-2022-transfer-fee-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-token-2022-transfer-fee-web3: solana-token-2022-transfer-fee-live

# Run a live Solana Token-2022 non-transferable plan smoke on Surfpool with the Rust harness.
solana-token-2022-non-transferable-live:
    scripts/solana/token-2022-non-transferable-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-token-2022-non-transferable-web3: solana-token-2022-non-transferable-live

# Run Solana PDA typed-seed Rust derivation smoke.
solana-pda-rust:
    scripts/solana/pda-rust-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-pda-web3: solana-pda-rust

# Run a live System Program transfer CPI smoke on Surfpool with the Rust harness.
solana-system-cpi-live:
    scripts/solana/system-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-system-cpi-web3: solana-system-cpi-live

# Run a live Memo Program CPI smoke on Surfpool with the Rust harness.
solana-memo-cpi-live:
    scripts/solana/memo-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-memo-cpi-web3: solana-memo-cpi-live

# Compare the generated System transfer CPI artifact with the Pinocchio reference contract.
solana-pinocchio-system-transfer-equivalence:
    scripts/solana/pinocchio-system-transfer-equivalence.sh

# Compare the generated System create_account CPI artifact with the Pinocchio reference contract.
solana-pinocchio-system-create-account-equivalence:
    scripts/solana/pinocchio-system-create-account-equivalence.sh

# Compare the generated SPL Token transfer_checked CPI artifact with the Pinocchio reference contract.
solana-pinocchio-spl-token-transfer-equivalence:
    scripts/solana/pinocchio-spl-token-transfer-equivalence.sh

# Compare the generated SPL Token mint_to/burn/approve/revoke CPI artifact with the Pinocchio reference contract.
solana-pinocchio-spl-token-ops-equivalence:
    scripts/solana/pinocchio-spl-token-ops-equivalence.sh

# Compare the generated SPL Token set_authority CPI artifact with the Pinocchio reference contract.
solana-pinocchio-spl-token-authority-equivalence:
    scripts/solana/pinocchio-spl-token-authority-equivalence.sh

# Run all CI-safe Solana Pinocchio reference-equivalence gates.
solana-pinocchio-reference-equivalence:
    scripts/solana/pinocchio-reference-equivalence.sh

# Build/deploy ProofForge and Pinocchio System transfer programs and compare behavior on Surfpool.
solana-pinocchio-system-transfer-live-equivalence:
    scripts/solana/pinocchio-system-transfer-live-equivalence.sh

# Build/deploy ProofForge and Pinocchio System create_account programs and compare behavior on Surfpool.
solana-pinocchio-system-create-account-live-equivalence:
    scripts/solana/pinocchio-system-create-account-live-equivalence.sh

# Build/deploy ProofForge and Pinocchio SPL Token transfer_checked programs and compare behavior on Surfpool.
solana-pinocchio-spl-token-transfer-live-equivalence:
    scripts/solana/pinocchio-spl-token-transfer-live-equivalence.sh

# Build/deploy ProofForge and Pinocchio SPL Token mint_to/burn/approve/revoke programs and compare behavior on Surfpool.
solana-pinocchio-spl-token-ops-live-equivalence:
    scripts/solana/pinocchio-spl-token-ops-live-equivalence.sh

# Build/deploy ProofForge and Pinocchio SPL Token set_authority programs and compare behavior on Surfpool.
solana-pinocchio-spl-token-authority-live-equivalence:
    scripts/solana/pinocchio-spl-token-authority-live-equivalence.sh

# Run all Solana ProofForge-vs-Pinocchio live dual-deploy equivalence gates.
solana-pinocchio-live-equivalence:
    scripts/solana/pinocchio-live-equivalence.sh

# Repair/install the Solana SBF rustc/platform-tools used by the Pinocchio live gate.
solana-pinocchio-install-sbf-tools:
    PATH="$HOME/.cargo/bin:$PATH" cargo-build-sbf --install-only --force-tools-install --tools-version v1.52

# Run a live System Program create_account CPI smoke on Surfpool with the Rust RPC harness.
solana-system-create-account-cpi-live:
    scripts/solana/system-create-account-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-system-create-account-cpi-web3: solana-system-create-account-cpi-live

# Run a live SPL Token transfer_checked CPI smoke on Surfpool with the Rust RPC harness.
solana-spl-token-transfer-cpi-live:
    scripts/solana/spl-token-transfer-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-transfer-cpi-web3: solana-spl-token-transfer-cpi-live

# Run a live SPL Token mint_to/burn/approve/revoke CPI smoke on Surfpool with the Rust RPC harness.
solana-spl-token-ops-cpi-live:
    scripts/solana/spl-token-ops-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-ops-cpi-web3: solana-spl-token-ops-cpi-live

# Run a live SPL Token set_authority CPI smoke on Surfpool with the Rust RPC harness.
solana-spl-token-authority-cpi-live:
    scripts/solana/spl-token-authority-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-authority-cpi-web3: solana-spl-token-authority-cpi-live

# Run a live SPL Token close_account CPI smoke on Surfpool with the Rust RPC harness.
solana-spl-token-close-account-cpi-live:
    scripts/solana/spl-token-close-account-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-close-account-cpi-web3: solana-spl-token-close-account-cpi-live

# Run a live Associated Token create_idempotent CPI smoke on Surfpool with the Rust RPC harness.
solana-associated-token-cpi-live:
    scripts/solana/associated-token-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-associated-token-cpi-web3: solana-associated-token-cpi-live

# Run a live Token-2022 direct CPI smoke on Surfpool with the Rust RPC harness.
solana-spl-token-2022-cpi-live:
    scripts/solana/spl-token-2022-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-2022-cpi-web3: solana-spl-token-2022-cpi-live

# Run a live Token-2022 Pausable direct CPI smoke on Surfpool with the Rust RPC harness.
solana-spl-token-2022-pausable-cpi-live:
    scripts/solana/spl-token-2022-pausable-cpi-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-2022-pausable-cpi-web3: solana-spl-token-2022-pausable-cpi-live

# Run a live Token-2022 transfer-hook execute/extra-account-meta smoke on Surfpool with the Rust RPC harness.
solana-spl-token-2022-transfer-hook-live:
    scripts/solana/spl-token-2022-transfer-hook-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-spl-token-2022-transfer-hook-web3: solana-spl-token-2022-transfer-hook-live

# Run a live Solana log/event smoke on Surfpool with the Rust RPC harness.
solana-log-event-live:
    scripts/solana/log-event-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-log-event-web3: solana-log-event-live

# Run a live Solana Clock sysvar smoke on Surfpool with the Rust RPC harness.
solana-clock-sysvar-live:
    scripts/solana/clock-sysvar-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-clock-sysvar-web3: solana-clock-sysvar-live

# Run a live Solana Rent sysvar smoke on Surfpool with the Rust RPC harness.
solana-rent-sysvar-live:
    scripts/solana/rent-sysvar-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-rent-sysvar-web3: solana-rent-sysvar-live

# Run a live Solana EpochSchedule sysvar smoke on Surfpool with the Rust RPC harness.
solana-epoch-schedule-sysvar-live:
    scripts/solana/epoch-schedule-sysvar-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-epoch-schedule-sysvar-web3: solana-epoch-schedule-sysvar-live

# Run a live Solana EpochRewards sysvar smoke on Surfpool with the Rust RPC harness.
solana-epoch-rewards-sysvar-live:
    scripts/solana/epoch-rewards-sysvar-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-epoch-rewards-sysvar-web3: solana-epoch-rewards-sysvar-live

# Run a live Solana LastRestartSlot sysvar smoke on Surfpool with the Rust RPC harness.
solana-last-restart-slot-sysvar-live:
    scripts/solana/last-restart-slot-sysvar-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-last-restart-slot-sysvar-web3: solana-last-restart-slot-sysvar-live

# Run a live Solana memory syscall smoke on Surfpool with the Rust RPC harness.
solana-memory-live:
    scripts/solana/memory-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-memory-web3: solana-memory-live

# Run a live Solana SHA-256/Keccak-256/Blake3 syscall smoke on Surfpool with the Rust RPC harness.
solana-crypto-hash-live:
    scripts/solana/crypto-hash-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-crypto-hash-web3: solana-crypto-hash-live

# Run a live Solana return-data/compute-units syscall smoke on Surfpool with the Rust RPC harness.
solana-return-data-compute-live:
    scripts/solana/return-data-compute-live-smoke.sh

# Compatibility alias for the former Web3.js-backed gate name.
solana-return-data-compute-web3: solana-return-data-compute-live

# Run the canned Solana sBPF smoke. Skips when sbpf is unavailable.
solana-emit-asm:
    scripts/solana/emit-asm-smoke.sh

# Run the SolanaModulePlan golden smoke for the Counter fixture (Tier B gate).
solana-plan-smoke:
    scripts/solana/plan-smoke.sh

# Check that legacy Web3.js Solana entrypoints only forward to Rust/live gates.
solana-web3-compat:
    python3 scripts/solana/check-web3-compat-wrappers.py

# Run all Solana gates that are safe for default CI.
solana-light: solana-lean solana-build-examples solana-emit-control solana-sdk-smoke portable-value-vault solana-emit-asm solana-plan-smoke solana-web3-compat solana-pinocchio-reference-equivalence solana-sbpf-exec-smoke solana-sbpf-genericity-smoke solana-counter-sbpf-regression solana-refinement-smoke

# Check shared-vs-target example topology.
examples-topology:
    python3 scripts/examples/check-topology.py

# Check translated documentation freshness and example topology.
docs-check: examples-topology
    scripts/i18n/check-sync.sh

# Mechanical doc↔code drift report (advisory; see docs/doc-code-sync-audit-2026-07.md).
doc-sync-audit:
    scripts/docs/audit-doc-code-sync.sh

# Emit Counter .qnt model and run `quint verify`. Skips if Java < 17.
quint-model-gate:
    scripts/quint/model-check-gate.sh

# Emit Counter .qnt model, run `quint run --mbt`, and replay ITF traces against IR semantics.
quint-mbt-gate:
    scripts/quint/mbt-replay-gate.sh

# Replay a sampled Quint MBT trace through the EVM backend (Counter Foundry smoke).
quint-evm-backend-replay-gate:
    scripts/quint/evm-backend-replay-gate.sh

# NearReplay shim smoke: pure Lean string-render check (no quint/offline-host spawn).
quint-near-replay-smoke:
    lake build ProofForge.Backend.Quint.NearReplay
    lake env lean --run Tests/Quint/NearReplaySmoke.lean

# SolanaReplay shim smoke: pure Lean string-render check (no mollusk/sbpf/quint spawn).
# Not wired into `just check` — running end-to-end needs SBF platform-tools not
# installed here per AGENTS.md; the smoke is a pure-Lean string check.
quint-solana-replay-smoke:
    lake build ProofForge.Backend.Quint.SolanaReplay
    lake env lean --run Tests/Quint/SolanaReplaySmoke.lean

# Unified Quint IR model gate: emit, verify, MBT, IR replay, and Counter EVM backend replay.
quint-ir-model-gate:
    scripts/quint/ir-model-gate.sh

# Run the unified RFC 0007 testkit scenario suite.
testkit:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run

# List RFC 0007 testkit scenarios.
testkit-list:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- list

# Run Quint MBT ITF replay scenarios through the unified testkit harness.
testkit-quint:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --target quint

# Run contract_source Counter/ValueVault scenarios with budget assertions.
testkit-budget-gate:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario counter
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario value-vault

# Run the fast local baseline used before broader target smokes.
check: build target-registry contract-spec-json contract-client sdk-schema cli-deploy cli-check evm-plan evm-semantic-plan shared-validate-smoke diagnostic-smoke ir-step-semantics-smoke ir-counter-semantics-smoke counter-universal-refinement-smoke supported-fragment-smoke target-semantics-instances-smoke wasm-exec-smoke wasm-near-host-smoke wasm-cosmwasm-host-smoke wasm-cosmwasm-refinement-smoke value-vault-wasm-refinement-smoke evm-bytecode-semantics-smoke ir-exec-result-smoke fv5-overflow-smoke solana-light portable-counter-multi-target cli-target-first contract-source-diagnostics near-target-first wasm-near-plan near-plan-smoke wasm-near-ft-transfer-call wasm-near-ft-transfer-call-e2e docs-check testkit evm-diagnostics evm-coverage psy-diagnostics psy-coverage psy-metadata psy-metadata-validation psy-metadata-cli quint-mbt-gate quint-ir-model-gate

# Check generated Psy golden sources that CI tracks without requiring dargo.
psy-golden-sources:
    #!/usr/bin/env bash
    set -euo pipefail
    mkdir -p build/psy
    fixtures=(
      "counter:Counter"
      "event:EventProbe"
      "crosscall:CrosscallProbe"
      "expression-predicate:ExpressionPredicateProbe"
      "generic-entrypoint:GenericEntrypointProbe"
      "arithmetic:ArithmeticProbe"
      "bitwise:BitwiseProbe"
      "conditional:ConditionalProbe"
      "else-if:ElseIfProbe"
      "u32-arithmetic:U32ArithmeticProbe"
      "u32-hash-packing:U32HashPackingProbe"
      "u32-storage-scalar:U32StorageScalarProbe"
      "bool-storage-scalar:BoolStorageScalarProbe"
      "bool-storage-array:BoolStorageArrayProbe"
      "u32-storage-array:U32StorageArrayProbe"
      "context:ContextProbe"
      "hash:HashProbe"
      "hash-storage:HashStorageProbe"
      "map:MapProbe"
      "assert:AssertProbe"
      "loop:LoopProbe"
      "array:ArrayProbe"
      "struct:StructProbe"
      "struct-array:StructArrayProbe"
      "abi-aggregate:AbiAggregateProbe"
      "nested-aggregate:NestedAggregateProbe"
      "storage-nested-aggregate:StorageNestedAggregateProbe"
    )
    for spec in "${fixtures[@]}"; do
      IFS=: read -r flag fixture <<< "$spec"
      lake env proof-forge emit --target psy-dpn --fixture "${flag}" -o "build/psy/${fixture}.psy"
      diff -u "Examples/Psy/${fixture}.golden.psy" "build/psy/${fixture}.psy"
    done

# Run Psy unsupported-shape diagnostic smoke.
psy-diagnostics:
    scripts/psy/diagnostic-smoke.sh

# Check the Psy portable IR coverage manifest.
psy-coverage:
    scripts/psy/check-ir-coverage-manifest.py

# Run Psy plan-driven metadata unit tests.
psy-metadata:
    lake build ProofForge.Backend.Psy.Metadata
    lake env lean --run Tests/PsyMetadata.lean
    lake env lean --run Tests/CliMetadata.lean

# Run Psy metadata validation unit tests (Python).
psy-metadata-validation:
    python3 scripts/psy/test-metadata-validation.py

# Run Psy metadata CLI smoke test.
psy-metadata-cli:
    lake build proof-forge
    diff <(lake env lean --run Tests/PsyMetadataExport.lean Counter) \
      <(lake env proof-forge metadata --fixture counter)

# List available Psy smoke fixture names for `just psy-smoke <name>`.
psy-smokes-list:
    @for script in scripts/psy/*-smoke.sh; do basename "$script" | sed 's/-smoke\.sh$//'; done | sort

# Run one Psy smoke fixture, for example `just psy-smoke counter`.
psy-smoke fixture:
    @script="scripts/psy/{{fixture}}-smoke.sh"; \
      if [[ ! -f "$script" ]]; then \
        echo "unknown Psy smoke fixture '{{fixture}}'" >&2; \
        echo "run: just psy-smokes-list" >&2; \
        exit 2; \
      fi; \
      "$script"

# Run all Dargo-backed Psy smokes. Requires dargo on PATH.
psy-all:
    #!/usr/bin/env bash
    set -euo pipefail
    fixtures=(
      counter
      expression-predicate
      arithmetic
      u32-arithmetic
      bitwise
      u32-hash-packing
      u32-storage-scalar
      bool-storage-scalar
      bool-storage-array
      u32-storage-array
      conditional
      context
      event
      crosscall
      generic-entrypoint
      hash
      hash-storage
      map
      assert
      loop
      array
      struct
      struct-array
      abi-aggregate
      nested-aggregate
      storage-nested-aggregate
    )
    for fixture in "${fixtures[@]}"; do
      just psy-smoke "$fixture"
    done

# Run EVM unsupported-shape diagnostic smoke.
evm-diagnostics:
    scripts/evm/diagnostic-smoke.sh

# Check the EVM portable IR coverage manifest.
evm-coverage:
    scripts/evm/check-ir-coverage-manifest.py

# List available EVM IR smoke fixture names for `just evm-smoke <name>`.
evm-smokes-list:
    @for script in scripts/evm/*-ir-smoke.sh scripts/evm/ir-counter-smoke.sh; do basename "$script" | sed 's/-ir-smoke\.sh$//;s/-smoke\.sh$//'; done | sort

# Run one EVM IR smoke fixture, for example `just evm-smoke abi-scalar`.
evm-smoke fixture:
    @script="scripts/evm/{{fixture}}-ir-smoke.sh"; \
      if [[ "{{fixture}}" == "ir-counter" ]]; then script="scripts/evm/ir-counter-smoke.sh"; fi; \
      if [[ ! -f "$script" ]]; then \
        echo "unknown EVM smoke fixture '{{fixture}}'" >&2; \
        echo "run: just evm-smokes-list" >&2; \
        exit 2; \
      fi; \
      "$script"

# Build all SDK EVM examples and validate their metadata.
evm-build-examples:
    scripts/evm/build-examples.sh

# Run the Foundry EVM runtime smoke suite.
evm-foundry:
    scripts/evm/foundry-smoke.sh

# Regression gate for official Ownable + ERC-20 mixin composition (CS-2.7).
evm-mixin-compose:
    lake build ProofForge.Contract.Stdlib.Compose.Specs
    lake env lean --run Tests/MixinComposeProbe.lean

# Deploy generated Counter initcode to a local Anvil chain and validate a deploy-run artifact.
evm-anvil-deploy:
    scripts/evm/anvil-deploy-smoke.sh

# Broadcast Counter deploy with explicit gas flags on a local Anvil chain.
evm-broadcast-smoke:
    scripts/evm/broadcast-smoke.sh

# Deploy DynamicConstructorProbe with dynamic constructor args on Anvil and assert getters.
evm-dynamic-constructor-anvil:
    scripts/evm/dynamic-constructor-anvil-smoke.sh

# Record a deploy-plan artifact for a documented EVM testnet chain profile.
evm-deploy-plan:
    scripts/evm/deploy-plan-smoke.sh

# Run all CI-tracked EVM IR smokes.
evm-ir-smokes:
    #!/usr/bin/env bash
    set -euo pipefail
    fixtures=(
      abi-scalar
      assert
      assignment
      assign-op
      conditional
      loop
      context
      event
      crosscall
      expression
      hash
      map
      typed-map
      storage-array
      storage-struct
      typed-storage
      array-value
      struct-array-value
      struct-value
      abi-aggregate
      dynamic-abi
      array-abi
      dynamic-array
      memory-array
      packed-storage
      errors
      fallback
    )
    for fixture in "${fixtures[@]}"; do
      just evm-smoke "$fixture"
    done

# Run all EVM gates that CI tracks locally.
evm-all: evm-diagnostics evm-coverage evm-semantic-plan evm-ir-smokes evm-build-examples evm-mixin-compose evm-foundry evm-anvil-deploy evm-broadcast-smoke evm-dynamic-constructor-anvil

# Mirror the GitHub build-test job locally. Keep this recipe aligned with .github/workflows/ci.yml.
github-build-test:
    just build
    just target-registry
    just contract-spec-json
    just contract-client
    just evm-plan
    just solana-light
    just docs-check
    scripts/near/diagnostic-smoke.sh
    scripts/near/check-ir-coverage-manifest.py
    scripts/near/check-ir-coverage-manifest.py --manifest Tests/EmitWatCoverage.tsv --label emitwat-ir-coverage
    lake env lean --run Tests/IROwnership.lean
    just ir-counter-semantics-smoke
    just counter-universal-refinement-smoke
    just supported-fragment-smoke
    just target-semantics-instances-smoke
    lake build ProofForge.Backend.Evm.Refinement
    lake build ProofForge.Contract.Examples.ValueVaultInvariant
    lake env lean --run Tests/NearWasmFormal.lean
    scripts/near/emitwat-ci-smoke.sh
    just near-target-first
    just contract-source-diagnostics
    just testkit
    just psy-golden-sources
    just psy-diagnostics
    just psy-coverage
    just psy-metadata
    just psy-metadata-validation
    just psy-metadata-cli
    just quint-mbt-gate
    just quint-ir-model-gate
    just evm-diagnostics
    just evm-coverage
    just evm-ir-smokes
    just evm-build-examples
    just evm-foundry
    just evm-anvil-deploy
    just evm-dynamic-constructor-anvil
    just portable-counter-multi-target
    just portable-role-gated-token-multi-target
    just portable-staking-vault-multi-target

# Run the GitHub build-test mirror plus local EVM extensions not wired into that job.
ci: github-build-test evm-mixin-compose evm-broadcast-smoke

# Check for whitespace errors before committing.
diff-check:
    git diff --check
