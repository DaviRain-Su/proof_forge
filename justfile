set shell := ["bash", "-eu", "-o", "pipefail", "-c"]

# List available ProofForge development commands.
default:
    @just --list

# Build the Lean package and proof-forge executable.
build:
    lake build

# Build modules imported only by Tests/ (not reachable from the proof-forge
# exe, so `lake build` alone skips them). Several `check` recipes run
# `lake env lean --run Tests/X.lean`, which needs these oleans pre-built.
# This dynamically finds and builds whatever `lake build` left unbuilt, so it
# auto-adapts as the test surface changes (no brittle static module list).
build-test-deps:
    #!/usr/bin/env bash
    set -e
    mods=$({ for src in $(find ProofForge Examples -name "*.lean" -not -path "*/.*"); do
      olen=".lake/build/lib/lean/${src%.lean}.olean"
      [ -f "$olen" ] || echo "${src%.lean}" | sed 's|/|.|g'
    done; })
    if [ -n "$mods" ]; then lake build $mods; fi

# Check the target registry smoke.
target-registry:
    lake env lean --run Tests/TargetRegistry.lean

# PF-P1-01: registry-backed TargetBackend + CLI driver dispatch.
target-backend:
    lake env lean Tests/TargetBackend.lean

# PF-P1-02: machine-readable TargetProfile support matrix.
target-support:
    lake env lean --run Tests/TargetSupport.lean
    python3 scripts/docs/generate-backend-status.py --check

# PF-P1-03: ArtifactBundle honesty schema (intermediate/final/missing-tool).
artifact-bundle:
    lake env lean --run Tests/ArtifactBundle.lean

# PF-P1-04: preflight L0+L1+L2 readiness via TargetBackend hooks.
preflight-l2:
    lake env lean --run Tests/PreflightL2.lean

# PF-P1-06: Leo printer rejects unsupported AST ops (no comment placeholders).
leo-printer-fail-closed:
    lake env lean --run Tests/LeoPrinterFailClosed.lean

# PF-P1-05: contract_source DSL arity + version surface + Solana Surface isolation.
source-dsl-arity:
    #!/usr/bin/env bash
    set -euo pipefail
    lake env lean --run Tests/SourceDslArity.lean
    python3 - <<'PY'
    from pathlib import Path
    src = Path("ProofForge/Contract/Source.lean").read_text()
    assert "import ProofForge.Solana.Surface" not in src
    assert "import ProofForge.Solana\n" not in src and "import ProofForge.Solana\r" not in src
    assert "Solana.Surface" not in src
    sol = Path("ProofForge/Contract/Source/Solana.lean").read_text()
    assert "import ProofForge.Solana.Surface" in sol
    assert "trySolanaEntryStmt" in sol
    print("source-dsl isolation: ok")
    PY

# Regenerate docs/generated/backend-status.md from --list-targets --json.
backend-status-gen:
    python3 scripts/docs/generate-backend-status.py

# Check target-neutral ContractSpec JSON schema output.
contract-spec-json:
    lake env lean --run Tests/ContractSpecJson.lean

# Check generated target wrapper sketches from ContractSpec.
contract-client: entrypoint-mutability
    lake build ProofForge.Contract.Stdlib.NearFungibleToken
    lake env lean --run Tests/ContractClient.lean
    bash scripts/ts/evm-contract-client-smoke.sh

# Entrypoint call/view semantics across source DSL, validation, and canonical fixtures.
entrypoint-mutability:
    lake env lean --run Tests/EntrypointMutability.lean

# Check unified SDK schema generation, target extensions, diagnostics, and refs.
# U6.1 / RFC 0012: freeze IR + artifact version constants (portable-ir-v0, schemaVersion).
versioning-policy:
    lake build ProofForge.Contract.SdkSchema ProofForge.Backend.Solana.SbpfAsm ProofForge.Backend.Solana.Idl
    lake env lean --run Tests/VersioningPolicy.lean

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
    scripts/cli/token-spec-routing-smoke.sh

# Smoke the proof-forge --version CLI surface.
cli-version:
    lake env proof-forge --version

# Smoke the proof-forge --help / -h / build --help / emit --help / check --help surface.
cli-help:
    lake env lean --run Tests/CliHelp.lean
    lake env proof-forge --help >/dev/null
    lake env proof-forge -h >/dev/null
    lake env proof-forge build --help >/dev/null
    lake env proof-forge emit --help >/dev/null
    lake env proof-forge check --help >/dev/null

# Check that shared contract_source examples match their legacy Learn fixtures.
shared-contract-source:
    lake env lean --run Tests/SharedContractSource.lean

# Check shared TokenSpec intents and legacy Learn equivalence fixtures.
shared-token-intent:
    lake build Examples.Product.FungibleToken Examples.Product.FeeToken Examples.Product.SoulboundToken
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
    lake env lean --run Tests/Backend/Evm/EvmPlan.lean

# Check the EVM semantic plan (entrypoints, events, metadata) smoke.
evm-semantic-plan:
    lake build ProofForge.Backend.Evm.IR ProofForge.IR.Examples.Counter ProofForge.IR.Examples.EvmMapProbe ProofForge.IR.Examples.EvmStorageArrayProbe ProofForge.IR.Examples.EvmStorageStructProbe ProofForge.IR.Examples.EvmPackedStorageProbe ProofForge.IR.Examples.EventProbe ProofForge.Contract.Stdlib.UUPSUpgradeable ProofForge.Contract.Stdlib.ERC721 ProofForge.Contract.Stdlib.ERC1155 ProofForge.Contract.Stdlib.ERC4626
    lake env lean --run Tests/Backend/Evm/EvmSemanticPlan.lean
    lake env lean --run Tests/Backend/Evm/EvmPackedStorage.lean
    lake env lean --run Tests/Backend/Evm/EvmAbiSecurity.lean
    PATH="$HOME/.foundry/bin:$PATH" lake env lean --run Tests/Backend/Evm/EvmStandardEvents.lean

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

# D-050: portable IR + target-resolved StorageBinding smoke.
ir-portability-smoke:
    lake build ProofForge.IR.Portability ProofForge.IR.NearHost ProofForge.Target.StorageBinding ProofForge.IR.Examples.Counter ProofForge.IR.Examples.NearCrosscallProbe ProofForge.Backend.Evm.Validate ProofForge.Backend.Move.Sui ProofForge.Backend.Move.Aptos
    lake env lean --run Tests/IRPortability.lean

# FV-9.0 M6: exercise the shared total fueled IR interpreter (the ∀-module theorem's quantification target).
semantics-fuel-smoke:
    lake build ProofForge.IR.SemanticsFuel ProofForge.IR.CounterSemantics ProofForge.IR.ValueVaultSemantics
    lake env lean --run Tests/SemanticsFuelSmoke.lean

# FV-9.2: constructor coverage table + IR-side preservation lemmas + counter-model irStateRel preservation.
constructor-coverage-smoke:
    lake build ProofForge.Backend.Refinement.ConstructorCoverage ProofForge.Backend.Refinement.CounterUniversal
    lake env lean --run Tests/ConstructorCoverageSmoke.lean

# Check the first all-call-list Counter simulation proof over total IR semantics.
counter-universal-refinement-smoke:
    lake build ProofForge.Backend.Refinement.CounterUniversal
    lake env lean --run Tests/CounterUniversalRefinement.lean

# Check proof-fragment boundaries for TargetSemantics-supported modules.
supported-fragment-smoke:
    lake build ProofForge.Backend.Refinement.Core ProofForge.Backend.Refinement.CounterUniversal
    lake env lean --run Tests/SupportedFragment.lean

# Track 1.4: exercise the proven⊂lowerable + lowerable⇒lowering-total + capability⇒lowerable theorems on the Counter fragment.
track14-fragment-theorems-smoke:
    lake build ProofForge.Backend.Evm.Refinement ProofForge.Backend.Solana.Refinement ProofForge.Backend.WasmHost.Refinement ProofForge.Backend.Refinement.CounterUniversal
    lake env lean --run Tests/CounterLowerableAllocator.lean
    lake env lean --run Tests/Track14FragmentTheorems.lean

# PF-P3-01: computational free-name lowering-total for Counter shape (dense name set).
evm-counter-shape-name-totality:
    lake build ProofForge.Backend.Evm.Refinement
    lake env lean --run Tests/EvmCounterShapeNameTotality.lean

# Track 1.7 / FV-8: exercise user-authored Lean invariants (ValueVault + Counter) pre-codegen.
lean-invariants-smoke:
    lake build ProofForge.Contract.LeanInvariant ProofForge.Contract.Examples.ValueVaultInvariant ProofForge.Contract.Examples.CounterInvariant ProofForge.Contract.Examples.Counter
    lake env lean --run Tests/LeanInvariantsSmoke.lean

# Check existing executable trace runners are wired through the shared TargetSemantics interface.
target-semantics-instances-smoke:
    lake build ProofForge.Backend.Evm.Refinement ProofForge.Backend.Evm.YulHostRefinement ProofForge.Backend.Solana.Refinement ProofForge.Backend.WasmHost.Refinement
    lake env lean --run Tests/TargetSemanticsInstances.lean

# Generic Wasm stack/state helper lemmas - active WASM C-proof surface.
wasm-exec-smoke:
    lake build ProofForge.Backend.WasmHost.WasmExec
    lake env lean --run Tests/Backend/Wasm/WasmExec.lean

# NEAR host-model lemmas over the generic Wasm host-call hook.
wasm-near-host-smoke:
    lake build ProofForge.Backend.WasmHost.NearHost
    lake env lean --run Tests/Backend/Wasm/WasmNearHost.lean

# N1.2: EmitWat Borsh aggregate ABI (struct/fixedArray param+return; bytes fail-closed).
emitwat-aggregate-abi:
    scripts/near/emitwat-aggregate-abi-smoke.sh

wasm-cosmwasm-host-smoke:
    lake build ProofForge.Backend.WasmHost.CosmWasmHost
    lake env lean --run Tests/Backend/Wasm/WasmCosmWasmHost.lean

# Phase 4 WASM host family: Soroban host dispatch (3rd WASM host adapter).
wasm-soroban-host-smoke:
    lake build ProofForge.Backend.WasmHost.SorobanHost ProofForge.Backend.WasmHost.CounterSorobanRefinement
    lake env lean --run Tests/Backend/Wasm/WasmSorobanHost.lean

# Phase 4 ZK lane: Aleo/Leo honest Counter reject + supported-fragment sourcegen.
# Also covers map-storage + finalize-context + record (Road 2) lowering and metadata.
aleo-leo-codegen-smoke:
    lake build ProofForge.Backend.Aleo.IR ProofForge.Backend.Aleo.Metadata ProofForge.Backend.Aleo.MetadataJson
    lake env lean --run Tests/AleoLeoCodegenSmoke.lean
    lake env lean --run Tests/AleoLeoMapLoweringSmoke.lean
    lake env lean --run Tests/AleoLeoStorageDefaultSmoke.lean
    lake env lean --run Tests/AleoLeoContextLoweringSmoke.lean
    lake env lean --run Tests/AleoLeoRecordLoweringSmoke.lean
    lake env lean --run Tests/AleoLeoRecordTransferSmoke.lean
    lake env lean --run Tests/AleoLeoCoverageSmoke.lean
    lake env lean --run Tests/AleoLeoMixedReturnSmoke.lean
    lake env lean --run Tests/AleoLeoHashLoweringSmoke.lean
    lake env lean --run Tests/AleoLeoSemanticHonestySmoke.lean
    lake env lean --run Tests/AleoLeoCrosscallSmoke.lean
    lake env lean --run Tests/AleoLeoMetadataSmoke.lean

# ZK lane portability: one portable module lowers on BOTH ZK sourcegen targets.
zk-portability-smoke:
    lake build ProofForge.Backend.Aleo.IR ProofForge.Backend.Psy.IR
    lake env lean --run Tests/ZkPortabilitySmoke.lean

# REAL Aleo compile gate: render every feature shape and `leo build` each.
# Needs `leo` (4.0.2) on PATH; exits 127 if absent (optional, like the CI aleo-smoke job).
aleo-leo-build-smoke:
    lake build ProofForge.Backend.Aleo.IR
    lake env lean --run RenderAleoFixtures.lean
    bash scripts/aleo/leo-build-smoke.sh

# WASM-5a contract axis: ValueVault universal IR↔Wasm core refinement.
value-vault-wasm-refinement-smoke:
    lake build ProofForge.Backend.WasmHost.ValueVaultWasmRefinement
    lake env lean --run Tests/ValueVaultWasmRefinement.lean

# WASM-5b chain-axis: Counter reuses the SAME host-agnostic core on CosmWasm.
wasm-cosmwasm-refinement-smoke:
    lake build ProofForge.Backend.WasmHost.CounterCosmWasmRefinement
    lake env lean --run Tests/Backend/Wasm/WasmCosmWasmRefinementSmoke.lean

# Check the Phase 6b EVM bytecode-semantics seam for the preferred powdr target.
evm-bytecode-semantics-smoke:
    lake build ProofForge.Backend.Evm.EvmBytecodeSemantics
    lake env lean --run Tests/Backend/Evm/EvmBytecodeSemantics.lean

# Mathlib-free IR ↔ EVM Yul-subset paired simulation (Portable-IR host lane).
evm-yul-host-refinement-smoke:
    lake build ProofForge.Backend.Evm.YulHostRefinement
    lake env lean --run Tests/Backend/Evm/EvmYulHostRefinement.lean

# Check the opt-in powdr/mathlib EVM refinement adapter target.
evm-powdr-adapter:
    lake build EvmRefinement

# Pin the Counter IR↔powdr bytecode delivery boundary (opt-in, mathlib).
evm-powdr-counter-refinement-smoke:
    lake build EvmRefinement.CounterRefinement
    lake env lean --run Tests/Backend/Evm/EvmPowdrCounterRefinement.lean

# Check that the generated Counter runtime matches the embedded powdr witness.
evm-powdr-counter-runtime: build
    scripts/evm/powdr-counter-runtime-smoke.sh

# External Yul→bytecode verification: compile emitted Counter Yul with solc
# and check it reproduces the embedded powdr runtime witness.
evm-yul-compiler-counter-smoke: build
    scripts/evm/yul-compiler-counter-smoke.sh

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

# PF-P0-01: ValueVault source identity across every registered target (no silent Counter).
source-identity:
    scripts/cli/source-identity-smoke.sh
    scripts/cli/artifact-source-provenance-smoke.sh

# PF-P0-02: --list-targets membership vs per-command support honesty.
registry-command:
    scripts/cli/registry-command-smoke.sh

# PF-P0-03: Solana contract_source default ELF + honest --format s assembly.
solana-source-elf:
    scripts/cli/solana-source-elf-smoke.sh

# PF-P0-04: Soroban uses its own TargetProfile / sidecar (not NEAR).
soroban-profile:
    scripts/cli/soroban-profile-smoke.sh

# PF-P3-02: six-gate promotion smoke for wasm-stellar-soroban (Counter fragment).
soroban-promotion:
    scripts/cli/soroban-promotion-smoke.sh

# PF-P3-02: six-gate promotion smoke for wasm-cosmwasm (Counter fragment).
cosmwasm-promotion:
    scripts/cli/cosmwasm-promotion-smoke.sh

# PF-P3-02: six-gate promotion smoke for move-aptos (Counter fixture fragment).
aptos-promotion:
    scripts/cli/aptos-promotion-smoke.sh

# PF-P3-02: six-gate promotion smoke for move-sui (Counter MVP fragment).
sui-promotion:
    scripts/cli/sui-promotion-smoke.sh

# PF-P3-02: six-gate promotion smoke for wasm-cloudflare-workers (Counter TS fragment).
cloudflare-promotion:
    scripts/cli/cloudflare-promotion-smoke.sh

# PF-P3-02: six-gate promotion smoke for psy-dpn (Counter fixture; dargo optional).
psy-promotion:
    scripts/cli/psy-promotion-smoke.sh

# Aleo promotion-readiness audit; expected non-zero until Counter getter is representable.
aleo-promotion:
    scripts/cli/aleo-promotion-smoke.sh

# PF-P0-08: default Wasm build fails without wat2wasm; --format wat is intermediate.
wat2wasm-fail-closed:
    scripts/cli/wat2wasm-fail-closed-smoke.sh

# PF-P0-07: check uses the same input-mode / L2 fail-closed rules as build.
check-l2-parity:
    scripts/cli/check-l2-parity-smoke.sh

# PF-P3-03: hosted isolation flag refuses trusted-local ContractLoader elaboration.
hosted-isolation:
    scripts/cli/hosted-isolation-smoke.sh

# PF-P3-03: clean EVM Counter rebuild reproduces bin/yul hashes + lean pin.
rebuild-hash:
    scripts/cli/rebuild-hash-smoke.sh

# PF-P3-03: process-tree wall-clock worker limit wrapper.
worker-limits:
    scripts/cli/worker-limits-smoke.sh

# PF-P3-03: CPU RLIMIT + wall-clock worker limits; memory when cgroup v2 / RLIMIT_AS available.
worker-cgroup:
    scripts/cli/worker-cgroup-smoke.sh

# Generic sBPF step lemmas — active C-proof surface (PRs touch SbpfExec here).
solana-sbpf-exec-smoke:
    lake build ProofForge.Backend.Solana.SbpfExec
    lake build ProofForge.Backend.Solana.SbpfExecSmoke
    lake env lean --run Tests/Backend/Solana/SolanaSbpfExec.lean

# Second-contract genericity smoke for the reusable sBPF execution layer.
solana-sbpf-genericity-smoke:
    lake build ProofForge.Backend.Solana.ValueVaultSbpfExec
    lake env lean --run Tests/Backend/Solana/SolanaValueVaultSbpfExec.lean

# Counter core-tail + IR↔sBPF refinement regression (frozen spike; do not expand).
solana-counter-sbpf-regression:
    lake build ProofForge.Backend.Solana.CounterSbpfExec
    lake build ProofForge.Backend.Solana.CounterSbpfRefinement
    lake env lean --run Tests/Backend/Solana/SolanaCounterSbpfRegression.lean

# Check the Solana sBPF refinement anchor (Counter IR trace + artifact surface).
solana-refinement-smoke:
    lake build ProofForge.Backend.Solana.Refinement
    lake env lean --run Tests/Backend/Solana/SolanaRefinement.lean

# Mathlib-free sBPF binary encoder + labeled view (Scheme 1/2A encode half).
solana-bpf-encode-smoke:
    lake build ProofForge.Backend.Solana.BpfEncode
    lake build ProofForge.Backend.Solana.LabeledSbpf
    lake env lean --run Tests/Backend/Solana/SolanaBpfEncode.lean

# Opt-in solanalib adapter + CompileCorrect pipeline (pulls solanalib/mathlib).
solana-solanalib-adapter:
    lake build SolanaRefinement
    lake env lean --run SolanaRefinement/CompileCorrectSmoke.lean

# Check contract_source target capability diagnostics through the CLI.
contract-source-diagnostics:
    scripts/contract-source/diagnostic-smoke.sh

# Run Solana target, SDK, and diagnostics tests that need only the Lean toolchain.
solana-lean:
    lake build
    lake build ProofForge.Contract.Token
    lake build ProofForge.Contract.Examples.Counter
    lake build ProofForge.Solana.Examples
    lake env lean --run Tests/Backend/Solana/SolanaDiagnostics.lean
    lake env lean --run Tests/Backend/Solana/SolanaSdk.lean
    lake env lean --run Tests/Backend/Solana/SolanaSdkManifest.lean
    lake env lean --run Tests/Backend/Solana/SolanaAccountConstraints.lean
    lake env lean --run Tests/Backend/Solana/SolanaAccountRealloc.lean
    lake env lean --run Tests/Backend/Solana/SolanaCpiPacking.lean
    lake env lean --run Tests/Backend/Solana/SolanaLogs.lean
    lake env lean --run Tests/Backend/Solana/SolanaSysvars.lean
    lake env lean --run Tests/Backend/Solana/SolanaMemory.lean
    lake env lean --run Tests/Backend/Solana/SolanaCrypto.lean
    lake env lean --run Tests/Backend/Solana/SolanaReturnDataCompute.lean
    lake env lean --run Tests/Backend/Solana/SolanaComputeBudgetInstruction.lean
    lake env lean --run Tests/Backend/Solana/SolanaPdaSeeds.lean
    lake env lean --run Tests/Backend/Solana/SolanaLoop.lean
    lake env lean --run Tests/Backend/Solana/SolanaStorageArray.lean
    lake env lean --run Tests/Backend/Solana/SolanaStorageArrayStruct.lean
    lake env lean --run Tests/Backend/Solana/SolanaStorageStructField.lean
    lake env lean --run Tests/Backend/Solana/SolanaFixedArrayStruct.lean
    lake env lean --run Tests/Backend/Solana/SolanaHash.lean
    lake env lean --run Tests/Backend/Solana/SolanaMemoryArray.lean
    lake env lean --run Tests/Backend/Solana/SolanaMapContextSafety.lean
    lake env lean --run Tests/LearnSource.lean
    lake env lean --run Tests/SharedContractSource.lean
    lake env lean --run Tests/LearnDiagnostics.lean
    lake env lean --run Tests/TargetRouting.lean
    lake env lean --run Tests/ValueVaultExample.lean
    just shared-token-intent
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

# TokenFeature × target support matrix (EVM full/reject · Solana full · NEAR no-lane).
token-feature-matrix:
    lake build ProofForge.Contract.Token
    lake env lean --run Tests/TokenFeatureMatrix.lean

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
    lake env lean --run Tests/Backend/Wasm/WasmNearPlan.lean

# Run the NearModulePlan golden + dual-path parity smoke (Tier B gate, Step B).
# Builds the plan, diffs against golden, and asserts plan-driven WAT == inline WAT.
near-plan-smoke:
    scripts/near/plan-smoke.sh

# Keep unversioned scalar storage on the stable per-key layout and conservatively
# load packed blobs before any partial patch.
wasm-near-scalar-safety:
    lake build ProofForge.Backend.WasmHost.EmitWat
    lake env lean --run Tests/Backend/Wasm/WasmNearScalarSafety.lean

# Verify near-sys promise amount pointers are decoded as little-endian u128.
near-promise-amount-pointer:
    scripts/near/promise-amount-pointer-smoke.sh

# Verify panicking offline-host calls roll back state and make the run fail.
near-offline-host-transaction:
    scripts/near/offline-host-transaction-smoke.sh

# Verify each offline-host receipt receives an independent Wasmtime fuel budget.
near-offline-host-fuel:
    scripts/near/offline-host-fuel-smoke.sh

# Check NEAR NEP-141 ft_transfer_call promise chain Plan + EmitWat smoke.
wasm-near-ft-transfer-call:
    lake build proof-forge ProofForge.Contract.Stdlib.NearFungibleToken
    lake env lean --run Tests/Backend/Wasm/WasmNearFtTransferCall.lean

# Run NEAR NEP-141 ft_transfer_call through the offline host promise callback path.
wasm-near-ft-transfer-call-e2e:
    scripts/near/ft-transfer-call-smoke.sh

# NEAR compare benchmarks (colocated under testkit/compare/).
# Offline by default. Set PROOF_FORGE_NEAR_SDK_BUILD=1 (or --build-sdk) to also
# cargo-build the near-sdk reference wasm for size comparison.
near-compare:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near counter

# Offline + NEAR Sandbox dual-deploy (ProofForge wasm vs near-sdk wasm).
# Requires network once to download neard-sandbox via near-workspaces.
# Skips (exit 0 offline, sandbox status=skipped) if sandbox cannot start.
near-compare-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near counter --live

# ValueVault offline compare (size/fuel); add --live via near-compare-value-vault-live.
near-compare-value-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near value-vault

near-compare-value-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near value-vault --live

# FungibleToken (NEP-141 minimal) offline / live.
near-compare-fungible-token:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near fungible-token

near-compare-fungible-token-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near fungible-token --live

# Ownable offline / live.
near-compare-ownable:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ownable

near-compare-ownable-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ownable --live

# StakingVault offline / live.
near-compare-staking-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near staking-vault

near-compare-staking-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near staking-vault --live

# RoleGatedToken offline / live.
near-compare-role-gated-token:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near role-gated-token

near-compare-role-gated-token-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near role-gated-token --live

# FeeToken offline / live.
near-compare-fee-token:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near fee-token

near-compare-fee-token-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near fee-token --live

# RemoteCall (promise_create cross-contract) offline / live.
near-compare-remote-call:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near remote-call

near-compare-remote-call-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near remote-call --live

# StatusMessage (u64 status codes; tutorial-shaped map).
near-compare-status-message:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near status-message

near-compare-status-message-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near status-message --live

# GuestBook (append message codes).
near-compare-guestbook:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near guestbook

near-compare-guestbook-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near guestbook --live

# NEP-145-lite storage_deposit (U64 projected balances).
near-compare-storage-deposit:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near storage-deposit

near-compare-storage-deposit-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near storage-deposit --live

# Pausable emergency-stop mixin (unauthenticated).
near-compare-pausable:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near pausable

near-compare-pausable-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near pausable --live

# ReentrancyGuard lock-bit mixin.
near-compare-reentrancy-guard:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near reentrancy-guard

near-compare-reentrancy-guard-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near reentrancy-guard --live

# Ownable + Pausable (owner-gated pause).
near-compare-ownable-pausable:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ownable-pausable

near-compare-ownable-pausable-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ownable-pausable --live

# ArrayExample fixed u64x3 locals.
near-compare-array-example:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near array-example

near-compare-array-example-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near array-example --live

# OwnableHash (32-byte sha256 owner).
near-compare-ownable-hash:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ownable-hash

near-compare-ownable-hash-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ownable-hash --live

# HostEnvProbe triad snapshot.
near-compare-host-env-probe:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near host-env-probe

near-compare-host-env-probe-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near host-env-probe --live

# AuthRemoteCall (debit + promise receive).
near-compare-auth-remote-call:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near auth-remote-call

near-compare-auth-remote-call-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near auth-remote-call --live

# AccessControl role map.
near-compare-access-control:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near access-control

near-compare-access-control-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near access-control --live

# ExternalTokenTransfer (NEP-141 peer client).
near-compare-external-token-transfer:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near external-token-transfer

near-compare-external-token-transfer-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near external-token-transfer --live

# ExternalVault (vault peer client).
near-compare-external-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near external-vault

near-compare-external-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near external-vault --live

# ProRataVault (ERC-4626-inspired internal shares).
near-compare-pro-rata-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near pro-rata-vault

near-compare-pro-rata-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near pro-rata-vault --live

# SoulboundToken body (mint/burn, no transfer).
near-compare-soulbound-token:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near soulbound-token

near-compare-soulbound-token-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near soulbound-token --live

# Backend FtPeerClient (protocol-layer NEP-141 client).
near-compare-ft-peer-client:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ft-peer-client

near-compare-ft-peer-client-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near ft-peer-client --live

# VestingVault (HostEnv timestamp linear vesting).
near-compare-vesting-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near vesting-vault

near-compare-vesting-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near vesting-vault --live

# EscrowVault (two-party fund → release | refund).
near-compare-escrow-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near escrow-vault

near-compare-escrow-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near escrow-vault --live

# TimelockVault (binary HostEnv unlock).
near-compare-timelock-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near timelock-vault

near-compare-timelock-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near timelock-vault --live

# HeightLockVault (binary HostEnv block height unlock).
near-compare-height-lock-vault:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near height-lock-vault

near-compare-height-lock-vault-live:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near height-lock-vault --live

# Measurement-only escape hatch. Writes a sandbox report even when semantic
# observations are incomplete; such reports are excluded from MATRIX rankings.
near-compare-live-measure contract:
    cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit-compare -- near {{contract}} --live --allow-semantic-mismatch

# Regenerate MATRIX.md from sandbox-report.json files.
near-compare-matrix-test:
    python3 scripts/near/compare-matrix-snapshot-test.py

near-compare-matrix: near-compare-matrix-test
    python3 scripts/near/compare-matrix-snapshot.py

# Full matrix.
near-compare-all-live: near-compare-live near-compare-value-vault-live near-compare-fungible-token-live near-compare-ownable-live near-compare-staking-vault-live near-compare-role-gated-token-live near-compare-fee-token-live near-compare-remote-call-live near-compare-status-message-live near-compare-guestbook-live near-compare-storage-deposit-live near-compare-pausable-live near-compare-reentrancy-guard-live near-compare-ownable-pausable-live near-compare-array-example-live near-compare-ownable-hash-live near-compare-host-env-probe-live near-compare-auth-remote-call-live near-compare-access-control-live near-compare-external-token-transfer-live near-compare-external-vault-live near-compare-pro-rata-vault-live near-compare-soulbound-token-live near-compare-ft-peer-client-live near-compare-vesting-vault-live near-compare-escrow-vault-live near-compare-timelock-vault-live near-compare-height-lock-vault-live

near-compare-counter: near-compare
near-benchmark-counter: near-compare

# PF-P2-02/P2-03: near-sandbox real peer RemoteCall.call_with_args → 49 + storage_usage.
# Requires `near-sandbox` on PATH (or ~/.near/near-sandbox-*/near-sandbox).
near-sandbox-peer:
    scripts/near/sandbox-peer-smoke.sh

# N1.4: offline-host peer stub for Product RemoteCall (call_with_args → 49).
# Complements near-sandbox-peer when sandbox binary is unavailable in CI.
near-remote-call-offline-peer:
    scripts/near/remote-call-offline-peer-smoke.sh

# N1.5: Product StorageDeposit offline lifecycle (deposit + withdraw).
near-storage-deposit-offline:
    scripts/near/storage-deposit-offline-smoke.sh

# N1.6: offline fuel field honesty (wasmtimeFuel* only; never near_gas).
# Real nearGas is reported by near-sandbox-peer when sandbox is available.
near-budget-honesty:
    scripts/near/budget-honesty-smoke.sh

# N1.7: deploy metadata honesty (offline-only; broadcast/networkDeploy not-generated).
near-deploy-honesty:
    scripts/near/deploy-honesty-smoke.sh

# E1.4: EVM upgrade-policy honesty (backend UUPS spike; product authority fails closed).
evm-upgrade-policy-honesty:
    scripts/evm/upgrade-policy-honesty-smoke.sh

# E1.4: UUPS constructor initialization is atomic; public init races fail closed.
evm-uups-atomic-init:
    scripts/evm/uups-atomic-init-smoke.sh

# Build the shared portable Counter to EVM, Solana sBPF, and NEAR/Wasm from one source file.
portable-counter-multi-target:
    scripts/portable/counter-multi-target.sh

# Shared RemoteCall → EVM CALL · Solana CPI · NEAR promise_create (CLI multi-target).
portable-remote-call-multi-target:
    scripts/portable/remote-call-multi-target.sh

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

# Compare the generated SPL Token close_account CPI artifact with the Pinocchio reference contract.
solana-pinocchio-spl-token-close-account-equivalence:
    scripts/solana/pinocchio-spl-token-close-account-equivalence.sh

# Compare the generated Memo CPI artifact with the Pinocchio reference contract.
solana-pinocchio-memo-equivalence:
    scripts/solana/pinocchio-memo-equivalence.sh

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
solana-light: solana-lean solana-build-examples solana-emit-control solana-sdk-smoke portable-value-vault solana-emit-asm solana-plan-smoke solana-auto-materialize primary-materialize crosscall-materialize solana-web3-compat solana-pinocchio-reference-equivalence solana-sbpf-exec-smoke solana-sbpf-genericity-smoke solana-counter-sbpf-regression solana-refinement-smoke solana-bpf-encode-smoke

# Check shared-vs-target example topology.
examples-topology:
    python3 scripts/examples/check-topology.py

# Phase A portable-default: Shared examples are business-intent only (no chain Surface / TokenStandard pick).
portable-default:
    python3 scripts/portable/check-portable-default.py
    python3 scripts/examples/check-topology.py
    lake build Examples.Product.FungibleToken Examples.Product.FeeToken Examples.Product.SoulboundToken
    lake env lean --run Tests/SharedTokenIntent.lean

# Phase B.2: portable IR → Solana accounts without Source.Solana authoring.
solana-auto-materialize:
    lake build ProofForge.Backend.Solana.Materialize Examples.Product.Counter Examples.Product.ValueVault ProofForge.Solana.Examples.Vault
    lake env lean --run Tests/Product/SolanaMaterialize.lean

# All implemented registry targets: materialization + crosscall map for Shared Counter.
primary-materialize:
    lake build ProofForge.Target.Materialize ProofForge.Target.CrosscallMaterialize Examples.Product.Counter
    lake env lean --run Tests/PrimaryMaterialize.lean

# U2: IR executable crosscall is a deterministic sum stub (not chain peer).
ir-crosscall-stub:
    lake build ProofForge.IR.Semantics ProofForge.IR.Examples.CrosscallProbe
    lake env lean --run Tests/IRCrosscallStub.lean

# Phase B.3: portable crosscall.invoke materialization (EVM CALL · Solana CPI · NEAR Promise).
crosscall-materialize:
    lake build ProofForge.Target.Preflight ProofForge.Backend.Solana.PortableCrosscall ProofForge.Backend.WasmHost.PortableCrosscall ProofForge.IR.Examples.CrosscallProbe ProofForge.IR.Examples.NearCrosscallProbe ProofForge.IR.Examples.Counter Examples.Product.RemoteCall ProofForge.Backend.Evm.Plan ProofForge.Backend.Solana.SbpfAsm ProofForge.Backend.WasmHost.EmitWat ProofForge.Backend.WasmHost.CosmWasm.EmitWat ProofForge.Backend.Psy.IR
    lake env lean --run Tests/CrosscallMaterialize.lean
    just portable-auth-materialize
    just portable-error-catalog
    just portable-solana-accounts
    just portable-remote-call-multi-target

# Portable business checks (Ownable) + declareRemote RemoteCall on EVM·Solana·NEAR·Soroban.
portable-auth-materialize:
    lake build Examples.Product.AccessControl Examples.Product.Ownable Examples.Product.OwnableHash Examples.Product.OwnablePausable Examples.Product.Pausable Examples.Product.ReentrancyGuard Examples.Product.RemoteCall Examples.Product.RoleGatedToken ProofForge.Backend.Evm.Plan ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.SbpfAsm ProofForge.Backend.WasmHost.EmitWat ProofForge.Target.Preflight
    lake env lean --run Tests/PortableAuthMaterialize.lean

# T3.4: assertionId catalogue parity across EVM · Solana · NEAR clients + sdk-schema + EmitWat PF.
# U6.4: entrypoint names + assertionId catalogue parity across EVM · Solana · NEAR clients/SDK.
client-schema-parity:
    lake build Examples.Product.Counter ProofForge.Contract.Client ProofForge.Contract.SdkSchema ProofForge.Backend.Solana.Client ProofForge.Backend.Solana.Idl ProofForge.IR.Examples.ErrorRefProbe
    lake env lean --run Tests/ClientSchemaParity.lean

portable-error-catalog:
    lake env lean --run Tests/PortableErrorCatalog.lean

# T3.2: Solana transfer/remote/nativeValue account auto-fill without Source.Solana.
portable-solana-accounts:
    lake build Examples.Product.AuthRemoteCall Examples.Product.ExternalTokenTransfer Examples.Product.ExternalVault Examples.Product.Ownable Examples.Product.RemoteCall Examples.Product.RoleGatedToken Examples.Product.StakingVault ProofForge.Backend.Solana.Manifest ProofForge.Backend.Solana.Materialize ProofForge.Backend.Solana.SbpfAsm
    lake env lean --run Tests/Product/Accounts.lean

# Backend compiler probes (Solana / EmitWat / Evm unit tests). Not product API.
# Subsets: solana-lean, emitwat-ci-smoke, evm-plan, wasm-*-host-smoke, …
backend: solana-lean
    @echo "backend: solana-lean ok (use solana-light / emitwat-ci-smoke / evm-* for more)"

# PF-P2-01: every Examples/Product/*.lean must be in catalog.json
product-catalog:
    python3 scripts/portable/check-product-catalog.py

# Primary product gate: Product sources × multi-target materialize matrix.
# Docs: docs/product-sdk.md · Examples/Product/README.md
product:
    just product-catalog
    just portable-default
    just product-matrix
    just portable-counter-multi-target
    just portable-remote-call-multi-target
    just product-token-near
    just near-remote-call-offline-peer
    just near-storage-deposit-offline
    @echo "product: ok (catalog · matrix · counter · remote · NEAR token conformance · NEAR peer · NEAR storage)"

# Wave β: Product TokenSpec on wasm-near — NEP-141 plan + FT body WAT (one health path).
product-token-near:
    scripts/portable/token-near-smoke.sh

# Wave β deepen: Product TokenSpec → Solana SPL plan (one health path; live = solana-token-plan-live).
product-token-solana:
    scripts/portable/token-solana-smoke.sh

# Wave γ: portable protocol-intent external FT (no Protocols.* import) × EVM/Solana/NEAR.
product-protocol-ft:
    scripts/portable/protocol-ft-smoke.sh

# Wave δ follow-on: Multicall Call[] AbiEncode.Plan → full Yul object (+ solc if present).
multicall-abi-yul:
    scripts/evm/multicall-abi-yul-smoke.sh

# Wave ε: external ERC-4626 vault protocol intent (product path, no Protocols import).
product-protocol-vault:
    scripts/portable/protocol-vault-smoke.sh

# Wave ε Layer C: deployable ERC-4626 vault body (1:1 synthetic stdlib mixin).
product-erc4626-vault:
    scripts/portable/erc4626-vault-smoke.sh

# Wave ε Layer C: ERC20Permit body (EVM ecrecover precompile + EIP-712 digest).
product-erc20-permit:
    scripts/portable/erc20-permit-smoke.sh

# Product multi-target Lean matrix (all Product contracts × primary hosts).
product-matrix:
    lake build Examples.Product.AccessControl Examples.Product.ArrayExample Examples.Product.AuthRemoteCall Examples.Product.Counter Examples.Product.EscrowVault Examples.Product.ExternalTokenTransfer Examples.Product.ExternalVault Examples.Product.FeeToken Examples.Product.FungibleToken Examples.Product.GuestBook Examples.Product.HeightLockVault Examples.Product.HostEnvProbe Examples.Product.Ownable Examples.Product.OwnableHash Examples.Product.OwnablePausable Examples.Product.Pausable Examples.Product.ProRataVault Examples.Product.ReentrancyGuard Examples.Product.RemoteCall Examples.Product.RoleGatedToken Examples.Product.SoulboundToken Examples.Product.SoulboundTokenBody Examples.Product.StakingVault Examples.Product.StatusMessage Examples.Product.StorageDeposit Examples.Product.TimelockVault Examples.Product.ValueVault Examples.Product.VestingVault ProofForge.IR.Examples.Counter ProofForge.Backend.Evm.Plan ProofForge.Backend.Solana.SbpfAsm ProofForge.Backend.WasmHost.EmitWat ProofForge.Target.Materialize
    lake env lean --run Tests/Product/Matrix.lean

# Extended product path (policies + token honesty + Solana accounts); kept for depth.
portable-tutorial: product
    just portable-auth-materialize
    just shared-token-intent
    just token-feature-matrix
    just portable-solana-accounts
    @echo "portable-tutorial: ok (product + policies · token · accounts)"

# Check translated documentation freshness and example topology.
docs-check: examples-topology portable-default
    scripts/i18n/check-sync.sh

# Mechanical doc↔code drift report (advisory; see docs/doc-code-sync-audit-2026-07.md).
doc-sync-audit:
    scripts/docs/audit-doc-code-sync.sh

# PF-P0-05: fail if any mechanical doc↔code finding remains.
doc-sync-audit-strict:
    scripts/docs/audit-doc-code-sync.sh --strict

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

# B1.1: validate benchmark result JSON schema fixtures.
benchmark-schema:
    scripts/benchmarks/schema-smoke.sh

# B1.2: compile/typecheck native Counter corpus (solc/cargo when present).
benchmark-native-counter:
    scripts/benchmarks/native-counter-smoke.sh

# B1.3: ProofForge Counter triad runner → build/benchmarks/bm-counter_*_proofforge.json
benchmark-counter-pf:
    scripts/benchmarks/counter-pf-runner.sh

# B1.4: native Counter triad runner → build/benchmarks/bm-counter_*_native.json
benchmark-counter-native:
    scripts/benchmarks/counter-native-runner.sh

# Counter matrix entrypoint: PF rows (B1.3) + native rows (B1.4).
benchmark-counter: benchmark-counter-pf benchmark-counter-native

# B1.5: PF vs native behavior parity on bm-counter rows under build/benchmarks/.
benchmark-behavior-gate:
    scripts/benchmarks/behavior-gate-smoke.sh

# B1.6: render markdown cost/artifact table → docs/generated/benchmark-counter.md
benchmark-cost-table:
    scripts/benchmarks/cost-table-smoke.sh

# B1.7: ValueVault matrix (PF + native where available).
benchmark-value-vault-pf:
    scripts/benchmarks/value-vault-pf-runner.sh

benchmark-value-vault-native:
    scripts/benchmarks/value-vault-native-runner.sh

benchmark-value-vault: benchmark-value-vault-pf benchmark-value-vault-native

# B1.7: Ownable matrix (EVM lifecycle primary; NEAR host tests; Solana size/skip).
benchmark-ownable-pf:
    scripts/benchmarks/ownable-pf-runner.sh

benchmark-ownable-native:
    scripts/benchmarks/ownable-native-runner.sh

benchmark-ownable: benchmark-ownable-pf benchmark-ownable-native

# B1.7 aggregate: Counter + ValueVault + Ownable rows, then behavior + cost table.
benchmark-matrix: benchmark-counter benchmark-value-vault benchmark-ownable
    just benchmark-behavior-gate
    just benchmark-cost-table

# B1.8: optional Psy/Aleo Counter experimental rows (dargo/leo tool-gated).
benchmark-zk-counter:
    scripts/benchmarks/zk-counter-runner.sh

# Full matrix including experimental ZK rows (still no cross-chain score).
benchmark-matrix-all: benchmark-matrix benchmark-zk-counter
    just benchmark-behavior-gate
    just benchmark-cost-table

# Run the unified RFC 0007 testkit scenario suite.
testkit:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run

# PF-P2-01 CI policy: skips and single-target "parity" are failures.
testkit-deny-skip:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --deny-skip

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

# PF-P2-01 map/array family: ArrayExample shared semantic returns on EVM/Solana/NEAR.
testkit-array-example:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario array-example

# PF-P2-01 auth/policy family: Ownable init → transferOwnership → owner.
testkit-ownable:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario ownable

# PF-P2-01 remote family: RemoteCall initialize + crosscall artifact checks.
testkit-remote-call:
    CAST="${CAST:-$HOME/.foundry/bin/cast}" cargo run --manifest-path testkit/Cargo.toml -p proof-forge-testkit -- run --scenario remote-call

# Run the fast local baseline used before broader target smokes.
# Product gate runs early so business multi-target failures surface first.
check: build build-test-deps product target-registry target-backend target-support artifact-bundle preflight-l2 source-dsl-arity leo-printer-fail-closed contract-spec-json contract-client sdk-schema cli-deploy cli-check cli-version cli-help evm-plan evm-semantic-plan shared-validate-smoke diagnostic-smoke ir-step-semantics-smoke ir-counter-semantics-smoke ir-portability-smoke semantics-fuel-smoke constructor-coverage-smoke counter-universal-refinement-smoke supported-fragment-smoke track14-fragment-theorems-smoke evm-counter-shape-name-totality lean-invariants-smoke target-semantics-instances-smoke wasm-exec-smoke wasm-near-host-smoke emitwat-aggregate-abi wasm-cosmwasm-host-smoke wasm-soroban-host-smoke zk-portability-smoke aleo-leo-codegen-smoke wasm-cosmwasm-refinement-smoke value-vault-wasm-refinement-smoke evm-bytecode-semantics-smoke evm-yul-host-refinement-smoke ir-exec-result-smoke fv5-overflow-smoke solana-light portable-counter-multi-target cli-target-first source-identity registry-command solana-source-elf soroban-profile wat2wasm-fail-closed check-l2-parity hosted-isolation rebuild-hash worker-limits worker-cgroup contract-source-diagnostics near-target-first wasm-near-plan near-plan-smoke wasm-near-scalar-safety near-promise-amount-pointer near-offline-host-transaction near-offline-host-fuel near-budget-honesty near-deploy-honesty near-compare-matrix-test wasm-near-ft-transfer-call wasm-near-ft-transfer-call-e2e docs-check testkit evm-diagnostics evm-upgrade-policy-honesty evm-coverage psy-diagnostics psy-test-naming psy-coverage psy-metadata psy-metadata-validation psy-metadata-cli quint-mbt-gate quint-ir-model-gate ci-install-script

# Z1.1: normalized DPN bytecode goldens (shape always; rebuild-diff when dargo artifacts present).
psy-dpn-goldens:
    scripts/psy/dpn-golden-gate.sh

# Z1.3: Lean DPN AST printer round-trip against Counter golden JSON.
psy-dpn-printer:
    lake build ProofForge.Backend.Psy.Dpn
    lake env lean --run Tests/PsyDpnPrinter.lean

# Z1.4: Counter IR → DPN JSON direct emit matches golden (bootstrap lower).
psy-dpn-direct:
    scripts/psy/dpn-direct-counter-smoke.sh

# Z1.5: dargo execute oracle (skips cleanly when dargo absent).
psy-dpn-execute-oracle:
    scripts/psy/dpn-execute-oracle-smoke.sh

# Z2.1: Counter Aleo Instructions golden pin (leo rebuild-diff when present).
aleo-aleo-goldens:
    scripts/aleo/aleo-goldens-gate.sh

# Z2.2: Lean Aleo Instructions printer round-trip.
aleo-instructions-printer:
    lake build ProofForge.Backend.Aleo.Instructions
    lake env lean --run Tests/AleoInstructionsPrinter.lean

# Z2.3: Counter IR → .aleo direct emit matches golden.
aleo-instructions-direct:
    scripts/aleo/aleo-instructions-direct-smoke.sh

# Z2.4: leo validate direct .aleo (skip if no leo).
aleo-instructions-validate:
    scripts/aleo/aleo-instructions-validate-smoke.sh

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
      diff -u "Examples/Backend/Psy/${fixture}.golden.psy" "build/psy/${fixture}.psy"
    done

# Run Psy unsupported-shape diagnostic smoke.
psy-diagnostics:
    scripts/psy/diagnostic-smoke.sh

# Unit test the generalized Psy test-function naming (snake_case derivation).
psy-test-naming:
    lake env lean --run Tests/PsyTestNaming.lean

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
    scripts/near/check-ir-coverage-manifest.py --manifest Tests/Backend/Wasm/EmitWatCoverage.tsv --label emitwat-ir-coverage
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

# Syntax-check the CI one-line installer script.
ci-install-script:
    bash -n scripts/ci/install.sh

# Check for whitespace errors before committing.
diff-check:
    git diff --check
