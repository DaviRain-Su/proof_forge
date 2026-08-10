set shell := ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

platform_tag := if os() == "macos" { "darwin-arm64" } else if os() == "linux" { "linux-" + arch() } else { "unsupported-" + os() }
tool_root := env_var_or_default("PROOF_FORGE_TOOL_ROOT", env_var("HOME") + "/.cache/proof-forge-v2/tool-root/" + platform_tag)
locked_git := if os() == "macos" { "/Applications/Xcode.app/Contents/Developer/usr/bin/git" } else { "/usr/bin/git" }
locked_python := if os() == "macos" { "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9" } else { "/usr/bin/python3" }

default: dev-check

# Bounded parallelism for `just test` shard *execution* (not lake build).
# PROOF_FORGE_TEST_JOBS=1 keeps full serial (CI / low-memory hosts).
# Default 4; invalid values fall back to 4.
test_jobs := env_var_or_default("PROOF_FORGE_TEST_JOBS", "4")

# Product CLI path is in-process Loader (no worker subprocess). Keep both worker
# executables as explicit targets for the non-default worker shard.
# BUILD-7: Lake 5 has no `-j` flag; module builds already fan out across cores
# (see `Built … (N jobs)` in lake logs). PROOF_FORGE_TEST_JOBS only parallelizes
# *test shard processes*, not Lean compilation.
build:
    lake build ProofForgeV2 proof_forge_next

build-frontend-worker:
    lake build proof_forge_frontend_worker_v1 proof_forge_compiler_proof_worker_v1 proof_forge_compiler_proof_worker_v2

# Build all memory-bounded test shards once, then run them with bounded
# parallelism. Each failing shard prints `FAIL shard: <name>` and xargs
# returns non-zero if any child fails.
test: build
    #!/usr/bin/env bash
    set -euo pipefail
    lake build \
      proof_forge_next_tests_shard_core \
      proof_forge_next_tests_shard_typed \
      proof_forge_next_tests_shard_language \
      proof_forge_next_tests_shard_language_b \
      proof_forge_next_tests_shard_language_c \
      proof_forge_next_tests_shard_aggregate \
      proof_forge_next_tests_shard_language_heavy \
      proof_forge_next_tests_shard_source \
      proof_forge_next_tests_shard_source_b \
      proof_forge_next_tests_shard_targets
    jobs='{{test_jobs}}'
    if ! [[ "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
      jobs=4
    fi
    shards=(
      proof-forge-next-tests-shard-core
      proof-forge-next-tests-shard-typed
      proof-forge-next-tests-shard-language
      proof-forge-next-tests-shard-language-b
      proof-forge-next-tests-shard-language-c
      proof-forge-next-tests-shard-aggregate
      proof-forge-next-tests-shard-language-heavy
      proof-forge-next-tests-shard-source
      proof-forge-next-tests-shard-source-b
      proof-forge-next-tests-shard-targets
    )
    run_shard() {
      local name="$1"
      echo "=== shard start: ${name} (jobs=${jobs}) ==="
      if lake env ".lake/build/bin/${name}"; then
        echo "=== shard ok: ${name} ==="
      else
        echo "FAIL shard: ${name}" >&2
        exit 1
      fi
    }
    export -f run_shard
    export jobs
    printf '%s\n' "${shards[@]}" | xargs -P "${jobs}" -n1 bash -c 'run_shard "$@"' _

# Hosted lean-product lane: run the nine non-target test shards only. The target
# shard owns external compiler/runtime checks and runs serially in target-smoke;
# keeping it out of this xargs pool prevents Linux runner starvation/hangs while
# the default `just test` above retains the complete local suite.
test-nontarget: build
    #!/usr/bin/env bash
    set -euo pipefail
    lake build \
      proof_forge_next_tests_shard_core \
      proof_forge_next_tests_shard_typed \
      proof_forge_next_tests_shard_language \
      proof_forge_next_tests_shard_language_b \
      proof_forge_next_tests_shard_language_c \
      proof_forge_next_tests_shard_aggregate \
      proof_forge_next_tests_shard_language_heavy \
      proof_forge_next_tests_shard_source \
      proof_forge_next_tests_shard_source_b
    jobs='{{test_jobs}}'
    if ! [[ "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
      jobs=4
    fi
    shards=(
      proof-forge-next-tests-shard-core
      proof-forge-next-tests-shard-typed
      proof-forge-next-tests-shard-language
      proof-forge-next-tests-shard-language-b
      proof-forge-next-tests-shard-language-c
      proof-forge-next-tests-shard-aggregate
      proof-forge-next-tests-shard-language-heavy
      proof-forge-next-tests-shard-source
      proof-forge-next-tests-shard-source-b
    )
    run_shard() {
      local name="$1"
      echo "=== shard start: ${name} (jobs=${jobs}) ==="
      if lake env ".lake/build/bin/${name}"; then
        echo "=== shard ok: ${name} ==="
      else
        echo "FAIL shard: ${name}" >&2
        exit 1
      fi
    }
    export -f run_shard
    export jobs
    printf '%s\n' "${shards[@]}" | xargs -P "${jobs}" -n1 bash -c 'run_shard "$@"' _

# Daily feedback path: prefer `just test-fast` over full `just test`.
# Does NOT build/run the frontend worker (removed from product CLI path).
test-fast: build
    lake build proof_forge_next_fast_tests
    lake env .lake/build/bin/proof-forge-next-fast-tests

# Explicit development worker suite (non-default). Builds real workers and the
# Linux native supervisor before the worker shard.
test-frontend-worker: build-frontend-worker
    lake build ProofForgeV2.Compiler.ProofWorkerSupervisorV1 proof_forge_next_tests_shard_worker
    lake env .lake/build/bin/proof-forge-next-tests-shard-worker

# Focused shard: `just test-shard core` → proof-forge-next-tests-shard-core.
# Names: core typed language language-b language-c aggregate language-heavy source source-b targets
# No recipe dependency on `build`: validate the name before any lake work.
test-shard name:
    #!/usr/bin/env bash
    set -euo pipefail
    case "{{name}}" in
      core|typed|language|language-b|language-c|aggregate|language-heavy|source|source-b|targets) ;;
      *)
        echo "test-shard: unknown name '{{name}}' (want core|typed|language|language-b|language-c|aggregate|language-heavy|source|source-b|targets)" >&2
        exit 2
        ;;
    esac
    # lake targets use underscores (language_b); bin names keep hyphens (language-b).
    lake_target="$(echo "proof_forge_next_tests_shard_{{name}}" | tr '-' '_')"
    bin_name="proof-forge-next-tests-shard-{{name}}"
    lake build ProofForgeV2 proof_forge_next "${lake_target}"
    lake env ".lake/build/bin/${bin_name}"

# Targets materialization / host-model suite only (faster than full `just test`).
test-targets: build
    lake build proof_forge_next_tests_shard_targets
    lake env .lake/build/bin/proof-forge-next-tests-shard-targets

# Wave 2 single-semantic-carrier cutover gate.
# Product compilation, resolver, materialization, finalization, CLI, and target
# Plan paths must not retain the dual alpha carrier or residual identity fields.
w2-single-semantic-carrier-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="w2-single-semantic-carrier-deletion-gate"
    product_paths=(
      ProofForgeV2/Compiler/Pipeline.lean
      ProofForgeV2/Targets/EngineeringBuildV1.lean
      ProofForgeV2/Materialization/MaterializedArtifactsV1.lean
      ProofForgeV2/Materialization/EngineeringFinalizationV1.lean
      ProofForgeV2/CLI/Emit.lean
      ProofForgeV2/Targets/Evm.lean
      ProofForgeV2/Targets/Solana.lean
      ProofForgeV2/Targets/Near.lean
      ProofForgeV2/Targets/Noir.lean
    )
    for pat in '\bCompiledProgramV1\b' '\balphaResidualOf\b' \
      '\bvalidateDualCarrierConsistencyV1\b' '\bmappedAlphaOfV1Id\?' \
      '\bv1IdOfMappedAlpha\?' '\bresidualProgramName\b' \
      '\bresidualSourceHash\b' '\bresidualSemanticHash\b'; do
      fail_if_match "$gate" "$pat" ProofForgeV2
    done
    fail_if_match "$gate" 'Semantic\.fromTyped|Typed\.checkV1' ProofForgeV2/Compiler/Pipeline.lean
    # Compatibility may define its own namespace, but no other ProofForgeV2
    # module (including the umbrella) may import or mention it.
    set +e
    compat_hits="$(rg --glob '*.lean' \
      --glob '!ProofForgeV2/Compiler/AlphaCompatibility.lean' \
      -n --no-heading 'Compiler\.AlphaCompatibility' ProofForgeV2 2>&1)"
    compat_ec=$?
    set -e
    if [[ $compat_ec -eq 0 ]]; then
      echo "w2-single-semantic-carrier-deletion-gate: AlphaCompatibility leaked into product tree" >&2
      printf '%s\n' "$compat_hits" >&2
      exit 1
    fi
    if [[ $compat_ec -ne 1 ]]; then
      echo "w2-single-semantic-carrier-deletion-gate: AlphaCompatibility scan failed (exit $compat_ec)" >&2
      printf '%s\n' "$compat_hits" >&2
      exit 1
    fi
    /usr/bin/python3 -I -S scripts/check_lean_import_closure.py \
      --root ProofForgeV2 \
      --root ProofForgeV2.Compiler.Pipeline \
      --root ProofForgeV2.Targets.Registry \
      --root ProofForgeV2.Materialization.MaterializedArtifactsV1 \
      --root ProofForgeV2.Materialization.EngineeringFinalizationV1 \
      --root ProofForgeV2.Materialization.EngineeringDiskClosureV1 \
      --root ProofForgeV2.CLI.Emit \
      --root ProofForgeV2.CLI.Main \
      --root ProofForgeV2.CLI.Exe \
      --root ProofForgeV2.Frontend.WorkerMainV1 \
      --forbid ProofForgeV2.Core.Source \
      --forbid ProofForgeV2.Core.Typed \
      --forbid ProofForgeV2.Core.TypedV1 \
      --forbid ProofForgeV2.Core.SemanticIR \
      --forbid ProofForgeV2.Core.Semantics \
      --forbid ProofForgeV2.Compiler.AlphaCompatibility
    fail_if_match "$gate" 'ProgramRequirement\.|Semantic\.deriveRequirements|Core\.SemanticIR' \
      ProofForgeV2/Typed/RequirementsInferV1.lean
    fail_if_match "$gate" '\bProgramRequirement\b|^\s*\|\s*unsupportedRequirement\b' \
      ProofForgeV2/Core/Diagnostic.lean
    for pat in 'private .*typeKeys' 'private .*exprKeys' 'private .*stmtKeys' \
      'private .*itemKeys' 'inferContributionKeysV1'; do
      fail_if_match "$gate" "$pat" ProofForgeV2/Semantic/RequirementsV1.lean
    done
    rg -q 'structure CompiledSemanticV1 where' ProofForgeV2/Compiler/Pipeline.lean
    rg -q 'private mk ::' ProofForgeV2/Compiler/Pipeline.lean
    # Alpha cleanup wave deleted the compat module; pin absence instead of presence.
    fail_if_file_exists "$gate" ProofForgeV2/Compiler/AlphaCompatibility.lean
    rg -q 'structure RequirementContributionV1 where' ProofForgeV2/Typed/RequirementsInferV1.lean
    rg -q 'inferRequirementContributionsV1' ProofForgeV2/Semantic/RequirementsV1.lean
    lake build ProofForgeV2.Compiler.Pipeline ProofForgeV2.Targets.EngineeringBuildV1 \
      ProofForgeV2.Materialization.MaterializedArtifactsV1 \
      ProofForgeV2.Materialization.EngineeringFinalizationV1 ProofForgeV2.CLI.Emit \
      Tests.Compiler.ValidatedSourceV1Pipeline Tests.Materialization.RequirementResolverV1 \
      Tests.Materialization.OutputEnvelopeV1 Tests.Materialization.EngineeringFinalizationV1
    echo "w2-single-semantic-carrier-deletion-gate: ok"

# D2 alpha-residual physical-deletion gate (durable just/ci pin).
# Core/Source, Core/Typed, Core/SemanticIR, Core/Semantics, Core/TypedV1,
# Compiler/AlphaCompatibility and Tests.Fixtures.SourcePrograms deleted by the
# AlphaCleanup wave; imports and physical presence must stay absent.
alpha-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="alpha-deletion-gate"
    fail_if_match "$gate" 'import ProofForgeV2\.Core\.Semantics' ProofForgeV2 Tests
    fail_if_match "$gate" 'import ProofForgeV2\.Core\.SemanticIR' ProofForgeV2 Tests
    fail_if_match "$gate" 'import ProofForgeV2\.Core\.Source' ProofForgeV2 Tests
    fail_if_match "$gate" 'import ProofForgeV2\.Core\.Typed$' ProofForgeV2 Tests
    fail_if_match "$gate" 'import ProofForgeV2\.Core\.TypedV1' ProofForgeV2 Tests
    fail_if_match "$gate" 'import ProofForgeV2\.Compiler\.AlphaCompatibility' ProofForgeV2 Tests
    fail_if_match "$gate" 'import Tests\.Fixtures\.SourcePrograms' Tests
    fail_if_file_exists "$gate" ProofForgeV2/Core/Semantics.lean
    fail_if_file_exists "$gate" ProofForgeV2/Core/SemanticIR.lean
    fail_if_file_exists "$gate" ProofForgeV2/Core/Source.lean
    fail_if_file_exists "$gate" ProofForgeV2/Core/Typed.lean
    fail_if_file_exists "$gate" ProofForgeV2/Core/TypedV1.lean
    fail_if_file_exists "$gate" ProofForgeV2/Compiler/AlphaCompatibility.lean
    fail_if_file_exists "$gate" Tests/Fixtures/SourcePrograms.lean
    echo "alpha-deletion-gate: ok"

# D3/S5 engineering deletion + sole-mint gate (durable just/ci pin).
# - no checkSupport def/call
# - no selection+compiled materialize/emit product signatures
# - sole ResolvedEngineeringBuildV1.mk in EngineeringBuildV1.lean
# - sole CompiledSemanticV1.mk in Compiler/Pipeline.lean (finishCompiledSemanticV1)
# Dual-arg sole public API authority is Lean Environment reflection in
# Tests/Materialization/RequirementResolverV1.lean (run_cmd product gate +
# synthetic probe self-test). This recipe builds that module so reflection
# runs even without full Fast/tests; suite runtime does not re-invoke this
# recipe (one-way: no just↔suite cycle).
# S6 closed public residual resolve/makePlan/emit product seams. All four Plan
# bodies consume retained SemanticProgramV1, and the Wave 2 single-carrier gate
# removes residual alpha from compiler/resolver/output identity (no public
# Residual namespace; see s6-plan-cutover-deletion-gate).
requirement-resolver-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="requirement-resolver-deletion-gate"
    # No fixed /tmp paths: capture rg output in shell variables only.
    # Line-anchored / call-site patterns so the suite's own string literals
    # (and justfile commentary) do not self-fail the gate.
    fail_if_match "$gate" '^\s*def checkSupport\b' ProofForgeV2 Tests
    fail_if_match "$gate" '\bTargets\.checkSupport\b' ProofForgeV2 Tests
    fail_if_match "$gate" '^\s*def materializeResult \(selection' ProofForgeV2
    fail_if_match "$gate" '^\s*def materialize \(selection' ProofForgeV2
    fail_if_match "$gate" '^\s*def emitProgram \(selection' ProofForgeV2
    # Sole mints (exact count + path whitelist).
    expect_one_match "$gate" 'ResolvedEngineeringBuildV1\.mk' 'EngineeringBuildV1.lean' \
      'ResolvedEngineeringBuildV1.mk'
    expect_one_match "$gate" 'CompiledSemanticV1\.mk' 'Pipeline.lean' \
      'CompiledSemanticV1.mk'
    # CompiledSemanticV1.mk must sit in the shared product/non-product finish gate.
    set +e
    mk_ctx="$(rg --glob '*.lean' -n --no-heading -C 12 'CompiledSemanticV1\.mk' ProofForgeV2/Compiler 2>&1)"
    mk_ec=$?
    set -e
    if [[ $mk_ec -ne 0 ]] || ! printf '%s\n' "$mk_ctx" | grep -q 'finishCompiledSemanticV1'; then
      echo "requirement-resolver-deletion-gate: CompiledSemanticV1.mk must be inside finishCompiledSemanticV1 in Compiler/Pipeline.lean" >&2
      printf '%s\n' "$mk_ctx" >&2
      exit 1
    fi
    # Lean Environment dual-arg reflection gate (elaboration-time run_cmd).
    lake build Tests.Materialization.RequirementResolverV1
    echo "requirement-resolver-deletion-gate: ok"

# S6: public residual alpha Plan authority closed (resolve/validateResolved/makePlan/
# TargetDescriptor.supportedRequirements removed). Capability-gated target entries
# are the sole product Plan/materialize path.
s6-plan-cutover-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="s6-plan-cutover-deletion-gate"
    # Public residual resolve / validateResolved closed in Common.
    fail_if_match "$gate" '^\s*def resolve\b' ProofForgeV2/Targets/Common.lean
    fail_if_match "$gate" '^\s*def validateResolved\b' ProofForgeV2
    # No public makePlan (ResolvedProgram or otherwise) under Targets.
    fail_if_match "$gate" '^\s*def makePlan\b' ProofForgeV2/Targets
    # No product call sites to residual resolve (space after resolve excludes
    # resolveEngineeringRequirementsV1). Doc comments must not use this form.
    fail_if_match "$gate" 'Targets\.resolve\s' ProofForgeV2
    fail_if_match "$gate" 'Common\.resolve\s' ProofForgeV2
    # TargetDescriptor carries no residual requirement list; resolver is sole authority.
    fail_if_match "$gate" '\bsupportedRequirements\b' ProofForgeV2
    # No public emit / lower / residual plan-alpha / Residual emission bypass under Targets.
    fail_if_match "$gate" '^\s*def emit\b' ProofForgeV2/Targets
    fail_if_match "$gate" '^\s*def lower\b' ProofForgeV2/Targets
    fail_if_match "$gate" '^\s*def planFromResidualAlpha\b' ProofForgeV2/Targets
    fail_if_match "$gate" '^\s*def planFromAlpha\b' ProofForgeV2/Targets
    fail_if_match "$gate" '^\s*def lowerPlan\b' ProofForgeV2/Targets
    fail_if_match "$gate" '^\s*def filesFromIR\b' ProofForgeV2/Targets
    fail_if_match "$gate" 'namespace Residual' ProofForgeV2/Targets
    # Dead public residual carrier deleted.
    fail_if_match "$gate" '^\s*structure ResolvedProgram\b' ProofForgeV2
    # Each implemented target must expose capability-gated public entries only.
    # Evm/Near/Noir keep planFromCapability on the façade. #125 moves Solana's
    # exhaustive legacy/CPI tagged entry to target-owned MaterializationV1,
    # imported by the façade. buildFromCapability remains in target submodules.
    for tgt in Evm Solana Near Noir; do
      facade="ProofForgeV2/Targets/${tgt}.lean"
      pfc_path="$facade"
      if [[ "$tgt" == "Solana" ]]; then
        if ! rg -q '^import ProofForgeV2.Targets.Solana.MaterializationV1$' "$facade"; then
          echo "s6-plan-cutover-deletion-gate: Solana façade must import MaterializationV1" >&2
          exit 1
        fi
        pfc_path="ProofForgeV2/Targets/Solana/MaterializationV1.lean"
      fi
      set +e
      pfc="$(rg -n --no-heading '^\s*def planFromCapability\b' "$pfc_path" 2>&1)"
      pfc_ec=$?
      bfc="$(rg --glob '*.lean' -n --no-heading '^\s*def buildFromCapability\b' "ProofForgeV2/Targets/${tgt}" 2>&1)"
      bfc_ec=$?
      set -e
      if [[ $pfc_ec -ne 0 ]]; then
        echo "s6-plan-cutover-deletion-gate: missing public planFromCapability in ${pfc_path}" >&2
        printf '%s\n' "$pfc" >&2
        exit 1
      fi
      if [[ $bfc_ec -ne 0 ]]; then
        echo "s6-plan-cutover-deletion-gate: missing public buildFromCapability in ${tgt} target family" >&2
        printf '%s\n' "$bfc" >&2
        exit 1
      fi
    done
    # Sole capability mint in EngineeringBuild leaf next to resolveEngineeringRequirementsV1.
    expect_one_match "$gate" 'ResolvedEngineeringBuildV1\.mk' 'EngineeringBuildV1.lean' \
      'ResolvedEngineeringBuildV1.mk'
    set +e
    mk_ctx="$(rg --glob '*.lean' -n --no-heading -C 60 'ResolvedEngineeringBuildV1\.mk' ProofForgeV2/Targets/EngineeringBuildV1.lean 2>&1)"
    mk_ec=$?
    set -e
    if [[ $mk_ec -ne 0 ]] || ! printf '%s\n' "$mk_ctx" | grep -q 'resolveEngineeringRequirementsV1'; then
      echo "s6-plan-cutover-deletion-gate: ResolvedEngineeringBuildV1.mk must be near resolveEngineeringRequirementsV1" >&2
      printf '%s\n' "$mk_ctx" >&2
      exit 1
    fi
    lake build Tests.Materialization.RequirementResolverV1
    echo "s6-plan-cutover-deletion-gate: ok"

# D3/S7a engineering deletion + sole-mint gate (durable just/ci pin).
# - no public OutputSet / OutputManifest structures
# - no public makeOutput / manifestJson / validateOutputSet product defs
# - sole MaterializedArtifactsV1.mk in Materialization/MaterializedArtifactsV1.lean
# - materializeResult returns MaterializedArtifactsV1
# Lean Environment reflection + runtime suite: Tests/Materialization/OutputEnvelopeV1.lean
# (one-way: gate builds that module; suite does not re-invoke this recipe).
# Not formal OutputSetV1 / proof-forge.output.v1 / BuildIdentity.
s7-output-envelope-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="s7-output-envelope-deletion-gate"
    # Public alpha product surfaces deleted.
    fail_if_match "$gate" '^\s*structure OutputSet\b' ProofForgeV2
    fail_if_match "$gate" '^\s*structure OutputManifest\b' ProofForgeV2
    fail_if_match "$gate" '^\s*def makeOutput\b' ProofForgeV2
    fail_if_match "$gate" '^\s*def manifestJson\b' ProofForgeV2
    fail_if_match "$gate" '^\s*def validateOutputSet\b' ProofForgeV2
    # Sole mint of MaterializedArtifactsV1.
    expect_one_match "$gate" 'MaterializedArtifactsV1\.mk' 'MaterializedArtifactsV1.lean' \
      'MaterializedArtifactsV1.mk'
    set +e
    # Wide context: private .mk sits at the end of mintMaterializedArtifactsV1.
    mk_ctx="$(rg --glob '*.lean' -n --no-heading -C 80 'MaterializedArtifactsV1\.mk' ProofForgeV2/Materialization 2>&1)"
    mk_ec=$?
    set -e
    if [[ $mk_ec -ne 0 ]] || ! printf '%s\n' "$mk_ctx" | grep -q 'mintMaterializedArtifactsV1'; then
      echo "s7-output-envelope-deletion-gate: MaterializedArtifactsV1.mk must be near mintMaterializedArtifactsV1" >&2
      printf '%s\n' "$mk_ctx" >&2
      exit 1
    fi
    # materializeResult signature returns the new carrier.
    set +e
    mat_hits="$(rg --glob '*.lean' -n --no-heading 'def materializeResult' ProofForgeV2/Targets/Registry.lean 2>&1)"
    mat_ec=$?
    set -e
    if [[ $mat_ec -ne 0 ]] || ! printf '%s\n' "$mat_hits" | grep -q 'MaterializedArtifactsV1'; then
      # Signature may span two lines — check following context.
      set +e
      mat_ctx="$(rg --glob '*.lean' -n --no-heading -A 2 'def materializeResult' ProofForgeV2/Targets/Registry.lean 2>&1)"
      set -e
      if ! printf '%s\n' "$mat_ctx" | grep -q 'MaterializedArtifactsV1'; then
        echo "s7-output-envelope-deletion-gate: materializeResult must return MaterializedArtifactsV1" >&2
        printf '%s\n' "$mat_ctx" >&2
        exit 1
      fi
    fi
    lake build Tests.Materialization.OutputEnvelopeV1
    echo "s7-output-envelope-deletion-gate: ok"

# D3/S7b engineering finalization-authority deletion + sole-mint gate.
# - no CLI/Toolchain.lean or CLI.Toolchain product imports
# - no finalizeEvm/finalizeNear or solc/wat2wasm product ids in CLI
# - sole FinalizedArtifactsV1.mk near mintFinalizedArtifactsV1
# - sole finalizeMaterializedArtifactsV1 in Registry
# Lean suite: Tests/Materialization/EngineeringFinalizationV1.lean
# (one-way: gate builds that module; suite does not re-invoke this recipe).
# Not formal OutputSetV1 / ToolchainIdentity / BuildIdentity.
s7b-finalize-authority-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="s7b-finalize-authority-deletion-gate"
    # CLI Toolchain module deleted; no product re-exports.
    fail_if_file_exists "$gate" ProofForgeV2/CLI/Toolchain.lean
    # Import form only (comments/tests may mention the deleted path).
    fail_if_match "$gate" 'import ProofForgeV2\.CLI\.Toolchain' ProofForgeV2 Tests
    fail_if_match "$gate" '^\s*def finalizeEvm\b' ProofForgeV2
    fail_if_match "$gate" '^\s*def finalizeNear\b' ProofForgeV2
    # solc/wat2wasm product tool resolve ids must not appear in CLI Emit publisher.
    fail_if_match "$gate" 'resolve "solc"' ProofForgeV2/CLI
    fail_if_match "$gate" 'resolve "wat2wasm"' ProofForgeV2/CLI
    # Sole FinalizedArtifactsV1 mint.
    expect_one_match "$gate" 'FinalizedArtifactsV1\.mk' 'EngineeringFinalizationV1.lean' \
      'FinalizedArtifactsV1.mk'
    set +e
    mk_ctx="$(rg --glob '*.lean' -n --no-heading -C 40 'FinalizedArtifactsV1\.mk' ProofForgeV2/Materialization 2>&1)"
    mk_ec=$?
    set -e
    if [[ $mk_ec -ne 0 ]] || ! printf '%s\n' "$mk_ctx" | grep -q 'mintFinalizedArtifactsV1'; then
      echo "s7b-finalize-authority-deletion-gate: FinalizedArtifactsV1.mk must be near mintFinalizedArtifactsV1" >&2
      printf '%s\n' "$mk_ctx" >&2
      exit 1
    fi
    # Sole Registry finalize dispatch.
    expect_one_match "$gate" '^\s*def finalizeMaterializedArtifactsV1\b' 'Registry.lean' \
      'finalizeMaterializedArtifactsV1'
    # LockedToolchain must not import Core.Source / CLI.
    fail_if_match "$gate" 'import ProofForgeV2\.Core\.Source' ProofForgeV2/Materialization/LockedToolchainV1.lean
    fail_if_match "$gate" 'import ProofForgeV2\.CLI' ProofForgeV2/Materialization/LockedToolchainV1.lean
    lake build Tests.Materialization.EngineeringFinalizationV1
    echo "s7b-finalize-authority-deletion-gate: ok"

# D3/S7c engineering exact disk-closure + manifest-last authority gate.
# Fast path: Python no-tool self-test of shared exact_physical_closure.
# Darwin product path: Solana + Noir StateCell publish + unified validate_artifacts
# membership (no EVM solc required). Linux retains static/Lean/Python closure
# checks; both hosts run the in-process Loader product CLI. Retains S5–S7b
# gates; not formal OutputSetV1 / hermetic publisher.
s7c-disk-closure-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="s7c-disk-closure-gate"
    # Sole production validator; no parallel expected-list caller API.
    expect_one_match "$gate" '^\s*def validateEngineeringDiskClosureV1\b' \
      'EngineeringDiskClosureV1.lean' 'validateEngineeringDiskClosureV1'
    fail_if_match "$gate" 'validateEngineeringDiskClosureV1\s*\([^)]*expected' ProofForgeV2
    # CLI Toolchain must remain deleted (S7b pin retained).
    fail_if_file_exists "$gate" ProofForgeV2/CLI/Toolchain.lean
    fail_if_match "$gate" 'import ProofForgeV2\.CLI\.Toolchain' ProofForgeV2 Tests
    # Manifest-last (D3-E7): constant-based sidecar writes + sole scanner pre/post.
    # Evidence write uses evidenceSidecarNameV1; manifest uses manifestSidecarNameV1.
    if ! rg -n --no-heading 'IO\.FS\.writeFile \(stagingDir / evidenceSidecarNameV1\)' \
        ProofForgeV2/CLI/Emit.lean >/dev/null; then
      echo "s7c-disk-closure-gate: Emit must write evidence sidecar via evidenceSidecarNameV1" >&2
      exit 1
    fi
    if ! rg -n --no-heading 'IO\.FS\.writeFile \(stagingDir / manifestSidecarNameV1\)' \
        ProofForgeV2/CLI/Emit.lean >/dev/null; then
      echo "s7c-disk-closure-gate: Emit must write manifest sidecar via manifestSidecarNameV1" >&2
      exit 1
    fi
    # Evidence write line number must be less than manifest write line number.
    ev_line="$(rg -n --no-heading 'IO\.FS\.writeFile \(stagingDir / evidenceSidecarNameV1\)' \
      ProofForgeV2/CLI/Emit.lean | head -1 | cut -d: -f1)"
    mf_line="$(rg -n --no-heading 'IO\.FS\.writeFile \(stagingDir / manifestSidecarNameV1\)' \
      ProofForgeV2/CLI/Emit.lean | head -1 | cut -d: -f1)"
    if [[ -z "$ev_line" || -z "$mf_line" || ! "$ev_line" -lt "$mf_line" ]]; then
      echo "s7c-disk-closure-gate: evidence sidecar must be written before manifest sidecar" >&2
      echo "  evidence line=$ev_line manifest line=$mf_line" >&2
      exit 1
    fi
    # Artifact-only pre-scan before mint (code-site line order; skip docstrings).
    pre_line="$(rg -n --no-heading 'let preInv ← scanEngineeringArtifactContentOnlyV1' \
      ProofForgeV2/CLI/Emit.lean | head -1 | cut -d: -f1)"
    mint_line="$(rg -n --no-heading 'match mintEngineeringOutputSetV1 finalized preInv' \
      ProofForgeV2/CLI/Emit.lean | head -1 | cut -d: -f1)"
    if [[ -z "$pre_line" || -z "$mint_line" || ! "$pre_line" -lt "$mint_line" ]]; then
      echo "s7c-disk-closure-gate: artifact-only scan must precede OutputSet mint" >&2
      echo "  pre-scan line=$pre_line mint line=$mint_line" >&2
      exit 1
    fi
    if [[ -z "$mint_line" || ! "$mint_line" -lt "$ev_line" ]]; then
      echo "s7c-disk-closure-gate: OutputSet mint must precede evidence write" >&2
      echo "  mint line=$mint_line evidence line=$ev_line" >&2
      exit 1
    fi
    # Full scan + pre/post inventory compare after manifest-last write.
    post_line="$(rg -n --no-heading 'let postInv ← scanEngineeringArtifactContentWithSidecarsV1' \
      ProofForgeV2/CLI/Emit.lean | head -1 | cut -d: -f1)"
    beq_line="$(rg -n --no-heading 'ArtifactContentInventoryV1\.beq preInv postInv' \
      ProofForgeV2/CLI/Emit.lean | head -1 | cut -d: -f1)"
    if [[ -z "$post_line" || ! "$mf_line" -lt "$post_line" ]]; then
      echo "s7c-disk-closure-gate: full sidecar scan must follow manifest write" >&2
      echo "  manifest line=$mf_line post-scan line=$post_line" >&2
      exit 1
    fi
    if [[ -z "$beq_line" || ! "$post_line" -lt "$beq_line" ]]; then
      echo "s7c-disk-closure-gate: pre/post inventory compare must follow full scan" >&2
      echo "  post-scan line=$post_line beq line=$beq_line" >&2
      exit 1
    fi
    # No second content walker in Emit (sole ArtifactContent authority).
    fail_if_match "$gate" 'IO\.FS\.readFile \(stagingDir /' ProofForgeV2/CLI/Emit.lean
    fail_if_match "$gate" 'IO\.FS\.readBinFile \(stagingDir /' ProofForgeV2/CLI/Emit.lean
    # Fast no-tool self-test of shared Python exact_physical_closure.
    /usr/bin/python3 -I -S scripts/validate_artifacts_self_test.py
    # Lean suite + product Solana/Noir closure without requiring solc for the gate.
    lake build Tests.Materialization.EngineeringDiskClosureV1
    lake build proof_forge_next
    rm -rf build/v2/s7c-gate-solana build/v2/s7c-gate-noir
    if [[ "$(uname -s)" == "Darwin" ]]; then
      lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target solana \
        -o build/v2/s7c-gate-solana
      lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target noir \
        -o build/v2/s7c-gate-noir
      /usr/bin/python3 -I -S scripts/s7c_product_closure_check.py
    else
      echo "s7c product CLI closure positive: skipped (non-Darwin)"
    fi
    echo "s7c-disk-closure-gate: ok"

# Wave 2 EVM pilot: target Plan body consumes retained SemanticProgramV1 only;
# the frozen public-UInt64 envelope retains exact checked add/sub semantics.
# Product CLI must not reintroduce structural ProofBundle join/flags.
# Non-product Semantic/Compiler ProofBundle modules and library tests remain.
# Inline certifier is product-wired (in-process certifyInlineProofV1 after
# compile, before TargetRegistry resolve/materialize). Structural ambient
# bundle join/flags stay deleted; legacy --proof-bundle* remain unknown options.
cli-structural-proof-bundle-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="cli-structural-proof-bundle-deletion-gate"
    cli_paths=(
      ProofForgeV2/CLI/Main.lean
      ProofForgeV2/CLI/Emit.lean
      ProofForgeV2/CLI/Exe.lean
    )
    for pat in \
      'ProofBundleFilesV1' \
      'ProofBundleV1' \
      'ProofReferenceJoinV1' \
      'applyProofBundleProductGateV1' \
      'failProofJoin' \
      'openProofBundleDirectoryV1' \
      'requireProofBundlePairGateV1' \
      'joinValidatedProofSubjectV1' \
      'collectSourceProofBindingsV1' \
      'proofSubjectOfCompiledSemanticV1' \
      'isValidProofBundleDigestWireV1' \
      'proofBundleDigest' \
      'proofBundle\b' \
      'proof-bundle'
    do
      # Leading "--flag" patterns confuse rg as options; match bare spellings.
      fail_if_match "$gate" "$pat" "${cli_paths[@]}"
    done
    # Product import closure must not pull structural bundle join into CLI.
    /usr/bin/python3 -I -S scripts/check_lean_import_closure.py \
      --root ProofForgeV2.CLI.Main \
      --root ProofForgeV2.CLI.Emit \
      --root ProofForgeV2.CLI.Exe \
      --forbid ProofForgeV2.Semantic.ProofBundleV1 \
      --forbid ProofForgeV2.Semantic.ProofReferenceJoinV1 \
      --forbid ProofForgeV2.Compiler.ProofBundleFilesV1
    # Certifier must be product-wired (not a reintroduced ambient bundle gate).
    rg -q 'certifyInlineProofV1' ProofForgeV2/CLI/Main.lean
    rg -q 'selectProgramV1ProductWithTheoremInventory' ProofForgeV2/CLI/Main.lean
    lake build ProofForgeV2.CLI.Main ProofForgeV2.CLI.Emit ProofForgeV2.CLI.Exe \
      Tests.CLI.ResourceFlagsV1 Tests.CLI.InlineProofProductV1
    echo "cli-structural-proof-bundle-deletion-gate: ok"

s1-evm-semantic-plan-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="s1-evm-semantic-plan-deletion-gate"
    source="ProofForgeV2/Targets/Evm"
    facade="ProofForgeV2/Targets/Evm.lean"
    fail_if_match "$gate" 'alphaResidualOf' "$source"
    fail_if_match "$gate" 'makePlanFromAlpha' "$source"
    fail_if_match "$gate" 'validateRequirementEnvelope' "$source"
    fail_if_match "$gate" 'Semantic\.deriveRequirements' "$source"
    rg -q 'private def makePlanFromSemanticV1' "$source"
    rg -q 'validateSemanticProgramV1' "$source"
    # Capability chain split across the facade and the lowering submodule:
    # planFromCapability (facade) → materializePlanFromCapabilityV1
    # (LowerSemanticV1) → semanticV1Of → private makePlanFromSemanticV1.
    rg -q 'def planFromCapability' "$facade"
    rg -q 'materializePlanFromCapabilityV1' "$facade"
    rg -Uq '(?s)def materializePlanFromCapabilityV1.*?semanticV1Of.*?makePlanFromSemanticV1 source' "$source/LowerSemanticV1.lean"
    rg -q 'expandedNodes' "$source"
    rg -q 'consumeCurrentSegmentV1' "$source"
    # checked-arithmetic makers and segment discipline must survive in the
    # per-block lowering reached from lowerCallableV1 via emitRegionV1.
    # Wave G repin: loop-body sinks use the arm-whitelisted variant
    # `consumeCurrentSegmentWithArmsV1`; the prefix pin covers both.
    rg -Uq '(?s)private def lowerBlockInstructionsV1.*?makeCheckedAddValueV1.*?makeCheckedSubValueV1.*?consumeCurrentSegment' "$source"
    rg -Uq '(?s)private def lowerCallableV1.*?emitRegionV1' "$source"
    rg -Uq '(?s)if op == \.add then.*?else if op == \.sub then.*?makeCheckedSubValueV1' "$source"
    rg -Uq '(?s)\.checkedSub lhs rhs =>.*?if lt\(\{lhs\.value\}, \{rhs\.value\}\).*?let \{name\} := sub\(' "$source"
    rg -Uq '(?s)\.stateStore stateId valueId, none =>.*?consumeCurrentSegmentWithArmsV1.*?segmentStart := values\.size' "$source"
    lake build ProofForgeV2.Targets.Evm Tests.Materialization.EvmSmoke Tests.Product.StateCellV1Evm
    echo "s1-evm-semantic-plan-deletion-gate: ok"

# Wave 2 target leaves: Solana/NEAR/Noir Plan bodies consume retained V1 only.
s1-target-semantic-plan-deletion-gate:
    #!/usr/bin/env bash
    set -euo pipefail
    source scripts/gate_helpers.sh
    gate="s1-target-semantic-plan-deletion-gate"
    for target in Solana Near Noir; do
      source="ProofForgeV2/Targets/${target}"
      facade="ProofForgeV2/Targets/${target}.lean"
      # Per-target residual message names the target (not shared fail_if_match
      # wording); same rg exit-code contract as scripts/gate_helpers.sh.
      for pat in alphaResidualOf makePlanFromAlpha validateRequirementEnvelope 'Semantic\.deriveRequirements'; do
        set +e
        hits="$(rg --glob '*.lean' -n --no-heading "$pat" "$source" 2>&1)"
        ec=$?
        set -e
        if [[ $ec -eq 0 ]]; then
          echo "$gate: forbidden ${target} residual pattern: $pat" >&2
          printf '%s\n' "$hits" >&2
          exit 1
        fi
        if [[ $ec -ne 1 ]]; then
          echo "$gate: rg failed for ${target}/$pat (exit $ec)" >&2
          printf '%s\n' "$hits" >&2
          exit 1
        fi
      done
      rg -q 'private def makePlanFromSemanticV1' "$source"
      rg -q 'validateSemanticProgramV1' "$source"
      # Near/Noir public façades reach their retained-Semantic Plan entry.
      # Solana's sole CPI product rail dispatches in MaterializationV1; its
      # business body reaches the same retained-Semantic lowerer only through
      # materializeFullBodyPlanForProductV1. The legacy helper must reject CPI.
      dispatch="$facade"
      if [[ "$target" == "Solana" ]]; then
        rg -q '^import ProofForgeV2.Targets.Solana.MaterializationV1$' "$facade"
        dispatch="$source/MaterializationV1.lean"
        rg -Uq '(?s)def planFromCapability.*?solanaSbpfCpiElfV1.*?productPlanFromCapabilityV1.*?unknownProfileFail' "$dispatch"
        rg -Uq '(?s)def irFromCapability.*?solanaSbpfCpiElfV1.*?productIrFromCapabilityV1.*?unknownProfileFail' "$dispatch"
        rg -Uq '(?s)def materializePlanFromCapabilityV1.*?solanaSbpfCpiElfV1.*?must use the target-owned CPI product Plan path' "$source/LowerSemanticV1.lean"
        rg -Uq '(?s)def materializeFullBodyPlanForProductV1.*?semanticV1Of.*?makePlanFromSemanticV1' "$source/LowerSemanticV1.lean"
      else
        rg -q 'materializePlanFromCapabilityV1' "$dispatch"
        rg -Uq '(?s)def materializePlanFromCapabilityV1.*?semanticV1Of.*?makePlanFromSemanticV1' "$source/LowerSemanticV1.lean"
      fi
      rg -q 'def planFromCapability' "$dispatch"
      rg -q 'expandedNodes' "$source"
      rg -q 'consumeCurrentSegmentV1' "$source"
      # checked-arithmetic bounded expanded-tree cost must survive either inline
      # (Noir) or behind a shared binary-tree helper (Solana/Near refactor;
      # Near's Wave H lane generalizes the shared helper to
      # makeBinaryTreeValueKindsV1 for UInt32 shift-count operand kinds).
      rg -Uq '(?s)(makeCheckedAddValueV1|makeBinaryTreeValueV1|makeBinaryTreeValueKindsV1).*?expandedNodes := 1 \+ lhs\.expandedNodes \+ rhs\.expandedNodes' "$source"
      rg -Uq '(?s)(makeCheckedSubValueV1|makeBinaryTreeValueV1|makeBinaryTreeValueKindsV1).*?expandedNodes := 1 \+ lhs\.expandedNodes \+ rhs\.expandedNodes' "$source"
      rg -q 'makeCheckedAddValueV1' "$source"
      rg -q 'makeCheckedSubValueV1' "$source"
      # Wave C: per-block lowering (reached from lowerCallableV1 via
      # emitRegionV1) owns checked add/sub and effect-segment consumption.
      rg -Uq '(?s)private def lowerBlockInstructionsV1.*?makeCheckedAddValueV1.*?makeCheckedSubValueV1.*?consumeCurrentSegmentV1' "$source"
      rg -Uq '(?s)private def lowerBlockInstructionsV1.*?private partial def emitRegionV1.*?private def lowerCallableV1' "$source"
      rg -Uq '(?s)if op == \.add then.*?else if op == \.sub then.*?makeCheckedSubValueV1' "$source"
      rg -Uq '(?s)\.stateStore stateId valueId, none =>.*?consumeCurrentSegmentV1.*?segmentStart := values\.size' "$source"
      case "$target" in
        Solana) rg -q 'checked_sub_u64' "$source" ;;
        Near) rg -q 'i64\.sub' "$source" ;;
        Noir) rg -Uq '(?s)\.checkedSub destination lhs rhs =>.*?assert\(\{renderValue relation lhs\} >= \{renderValue relation rhs\}\).*? - ' "$source" ;;
      esac
    done
    lake build ProofForgeV2.Targets.Solana ProofForgeV2.Targets.Near ProofForgeV2.Targets.Noir Tests.Materialization.Targets Tests.Materialization.NearHostModel Tests.Materialization.NoirRelationModel
    echo "s1-target-semantic-plan-deletion-gate: ok"

# BUILD-5: product path serial, then deletion gates. Every current gate may invoke
# lake against the shared `.lake/` tree, so gates always run **serially** (fail-closed
# with `FAIL gate: <name>`). PROOF_FORGE_GATE_JOBS is accepted for forward-compat but
# values >1 are forced to 1 with a warning (no concurrent lake on one worktree).
# EVMOZ-006: corpus static (schema + Reference) after test-fast; serial lake only.
dev-check: docs-check sbom-package-files-check build test-fast evm-corpus-static run-deletion-gates

gate_jobs := env_var_or_default("PROOF_FORGE_GATE_JOBS", "1")

run-deletion-gates:
    #!/usr/bin/env bash
    set -euo pipefail
    jobs='{{gate_jobs}}'
    if ! [[ "${jobs}" =~ ^[1-9][0-9]*$ ]]; then
      jobs=1
    fi
    if [[ "${jobs}" -gt 1 ]]; then
      echo "run-deletion-gates: PROOF_FORGE_GATE_JOBS=${jobs} ignored; all gates touch .lake — serializing" >&2
      jobs=1
    fi
    gates=(
      s1-evm-semantic-plan-deletion-gate
      s1-target-semantic-plan-deletion-gate
      w2-single-semantic-carrier-deletion-gate
      requirement-resolver-deletion-gate
      s6-plan-cutover-deletion-gate
      s7-output-envelope-deletion-gate
      s7b-finalize-authority-deletion-gate
      s7c-disk-closure-gate
      cli-structural-proof-bundle-deletion-gate
    )
    for name in "${gates[@]}"; do
      echo "=== gate start: ${name} (serial) ==="
      if just "${name}"; then
        echo "=== gate ok: ${name} ==="
      else
        echo "FAIL gate: ${name}" >&2
        exit 1
      fi
    done

# Re-run unit tests with host-profile toolchain self-tests (darwin lock only).
test-host-isolation: build
    lake build proof_forge_frontend_worker_v1 proof_forge_compiler_proof_worker_v1 proof_forge_compiler_proof_worker_v2 proof_forge_next_tests
    PROOF_FORGE_HOST_ISOLATION_TEST=1 lake env .lake/build/bin/proof-forge-next-tests

# Fast product-document validation. It deliberately excludes task/evidence
# qualification and all host ceremony.
docs-check:
    /usr/bin/python3 -I -S scripts/docs_check.py

# TASK-D0-08: re-pin the lean package file-set after any ProofForgeV2 source
# change (the manifest is a committed TST-SBOM-002 input).
sbom-package-files-refresh:
    /usr/bin/python3 -I -S scripts/sbom_package_files_refresh.py

# Fail closed when the committed lean-package-files pin is stale relative to
# the working tree (same discovery/hash as sbom-package-files-refresh).
sbom-package-files-check:
    /usr/bin/python3 -I -S scripts/sbom_package_files_refresh.py --check

toolchains-validate:
    /usr/bin/python3 -I -S scripts/toolchain_assets.py validate
    /usr/bin/python3 -I -S scripts/toolchain_assets.py self-test
    /usr/bin/python3 -I -S scripts/host_profiles_self_test.py

# Convenience wrappers only. Formal evidence must invoke the displayed env -i
# command directly because `just` itself starts an inherited recipe shell.
python-isolation-negative:
    #!/bin/bash
    set -euo pipefail
    tmp="$PWD/build/python-site-negative"
    rm -rf "$tmp"
    version="$(/usr/bin/python3 -I -S -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
    site="$tmp/Library/Python/$version/lib/python/site-packages"
    mkdir -p "$site"
    printf 'import sys; print("PTH_EXECUTED_BEFORE_TOOLCHAIN_VALIDATION")\n' > "$site/probe.pth"
    if HOME="$tmp" /usr/bin/python3 scripts/toolchain_assets.py validate > "$tmp/unisolated.log" 2>&1; then
      echo "toolchain validator unexpectedly accepted a site-enabled interpreter" >&2
      exit 1
    fi
    rg -q "PTH_EXECUTED_BEFORE_TOOLCHAIN_VALIDATION" "$tmp/unisolated.log"
    rg -q "run toolchain-assets with /usr/bin/python3 -I -S" "$tmp/unisolated.log"
    HOME="$tmp" /usr/bin/python3 -I -S scripts/toolchain_assets.py validate > "$tmp/isolated.log" 2>&1
    if rg -q "PTH_EXECUTED_BEFORE_TOOLCHAIN_VALIDATION" "$tmp/isolated.log"; then
      echo "isolated Python executed a user .pth file" >&2
      exit 1
    fi
    rg -q "toolchain-assets: lock validation ok" "$tmp/isolated.log"

toolchains-provision-external:
    /usr/bin/python3 -I -S scripts/toolchain_assets.py provision --group external

toolchains-provision-lean:
    /usr/bin/python3 -I -S scripts/toolchain_assets.py provision --group lean

toolchains-materialize-external destination="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64":
    /usr/bin/python3 -I -S scripts/toolchain_assets.py materialize-external --destination "{{destination}}"

toolchains-materialize-lean destination="$HOME/.cache/proof-forge-v2/lean-root/darwin-arm64":
    /usr/bin/python3 -I -S scripts/toolchain_assets.py materialize-lean --destination "{{destination}}"

toolchains-verify-external:
    /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "{{tool_root}}"

toolchains-closure-negative: build
    rm -rf build/toolchain-closure-negative
    rm -rf build/v2/runtime-mismatch
    mkdir -p build
    cp -R "{{tool_root}}" build/toolchain-closure-negative
    chmod u+w build/toolchain-closure-negative/lib/libcrypto.3.dylib
    dd if=/dev/zero of=build/toolchain-closure-negative/lib/libcrypto.3.dylib bs=1 count=1 conv=notrunc >/dev/null 2>&1
    chmod 0444 build/toolchain-closure-negative/lib/libcrypto.3.dylib
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-closure-negative" > build/toolchain-closure-negative.log 2>&1; then echo "tampered runtime dependency unexpectedly verified" >&2; exit 1; fi
    rg -q "bundle hash mismatch" build/toolchain-closure-negative.log
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-closure-negative" lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target near -o build/v2/runtime-mismatch > build/runtime-mismatch.log 2>&1; then echo "compiler unexpectedly accepted tampered runtime dependency" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/runtime-mismatch.log
    test ! -e build/v2/runtime-mismatch

toolchains-environment-negative: build
    rm -rf build/toolchain-environment-negative build/v2/environment-negative
    lake build proof_forge_frontend_worker_v1 proof_forge_compiler_proof_worker_v1 proof_forge_compiler_proof_worker_v2 proof_forge_next_tests
    DYLD_IMAGE_SUFFIX=_debug lake env .lake/build/bin/proof-forge-next-tests
    cp -R "{{tool_root}}" build/toolchain-environment-negative
    dd if=/dev/zero of=build/toolchain-environment-negative/lib/libcrypto.3_debug.dylib bs=16 count=1 >/dev/null 2>&1
    if DYLD_IMAGE_SUFFIX=_debug PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-environment-negative" lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target near -o build/v2/environment-negative > build/toolchain-environment-negative.log 2>&1; then echo "compiler unexpectedly accepted an extra DYLD image-suffix candidate" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH.*unexpected node" build/toolchain-environment-negative.log
    test ! -e build/v2/environment-negative

toolchains-root-negative: build
    mkdir -p build
    rm -rf build/toolchain-root-world build/toolchain-root-extra build/toolchain-root-hardlink build/toolchain-root-symlink build/toolchain-root-outside build/v2/root-world-negative build/v2/root-hardlink-negative build/v2/root-symlink-negative
    cp -R "{{tool_root}}" build/toolchain-root-world
    chmod 0777 build/toolchain-root-world
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-world" > build/toolchain-root-world.log 2>&1; then echo "world-writable tool root unexpectedly verified" >&2; exit 1; fi
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-root-world" lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target near -o build/v2/root-world-negative > build/toolchain-root-world-compiler.log 2>&1; then echo "compiler unexpectedly accepted a world-writable tool root" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/toolchain-root-world-compiler.log
    cp -R "{{tool_root}}" build/toolchain-root-extra
    ln -s /opt/homebrew build/toolchain-root-extra/unexpected-link
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-extra" > build/toolchain-root-extra.log 2>&1; then echo "tool root with an extra symlink unexpectedly verified" >&2; exit 1; fi
    cp -R "{{tool_root}}" build/toolchain-root-hardlink
    ln build/toolchain-root-hardlink/lib/libcrypto.3.dylib build/toolchain-root-outside
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-hardlink" > build/toolchain-root-hardlink.log 2>&1; then echo "tool root containing a multiply-linked file unexpectedly verified" >&2; exit 1; fi
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-root-hardlink" lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target near -o build/v2/root-hardlink-negative > build/toolchain-root-hardlink-compiler.log 2>&1; then echo "compiler unexpectedly accepted a multiply-linked runtime file" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/toolchain-root-hardlink-compiler.log
    ln -s "{{tool_root}}" build/toolchain-root-symlink
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-symlink" > build/toolchain-root-symlink.log 2>&1; then echo "symlink tool root unexpectedly verified" >&2; exit 1; fi
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-root-symlink" lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target near -o build/v2/root-symlink-negative > build/toolchain-root-symlink-compiler.log 2>&1; then echo "compiler unexpectedly accepted a symlink tool root" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/toolchain-root-symlink-compiler.log
    test ! -e build/v2/root-world-negative
    test ! -e build/v2/root-hardlink-negative
    test ! -e build/v2/root-symlink-negative

# Historical legacy Source.Program dual-entry characterization. It is retained
# for quarantine inventory but is not a ProgramV1 product or CI gate.
dsl-negative: build
    #!/bin/bash
    set -euo pipefail
    mkdir -p build
    if lake env lean testdata/invalid/program-kind.lean > build/program-kind.log 2>&1; then echo "kind syntax unexpectedly compiled" >&2; exit 1; fi
    rg -q "unexpected token|unexpected identifier|expected" build/program-kind.log
    rm -rf build/frontend-parity-negative
    mkdir -p build/frontend-parity-negative
    expected_diagnostic() {
        case "$1" in
            zero-callable) echo "PF-SRC-INVALID: program 'ZeroCallable' must declare at least one entry or view" ;;
            duplicate-state) echo "PF-SRC-INVALID: program 'DuplicateState' contains duplicate state declarations" ;;
            duplicate-entry) echo "PF-SRC-INVALID: program 'DuplicateEntry' contains duplicate entry declarations" ;;
            duplicate-initializer-param) echo "PF-SRC-INVALID: initializer contains duplicate parameters" ;;
            duplicate-entry-param) echo "PF-SRC-INVALID: entry 'run' contains duplicate parameters" ;;
            duplicate-event) echo "PF-SRC-INVALID: program 'DuplicateEvent' contains duplicate event declarations" ;;
            duplicate-error) echo "PF-SRC-INVALID: program 'DuplicateError' contains duplicate error declarations" ;;
            duplicate-event-param) echo "PF-SRC-INVALID: event 'First' contains duplicate parameters" ;;
            duplicate-error-param) echo "PF-SRC-INVALID: error 'First' contains duplicate parameters" ;;
            duplicate-struct) echo "PF-SRC-INVALID: program 'DuplicateStruct' contains duplicate struct declarations" ;;
            duplicate-enum) echo "PF-SRC-INVALID: program 'DuplicateEnum' contains duplicate enum declarations" ;;
            duplicate-struct-field) echo "PF-SRC-INVALID: struct 'First' contains duplicate fields" ;;
            duplicate-enum-variant) echo "PF-SRC-INVALID: enum 'First' contains duplicate variants" ;;
            empty-struct) echo "PF-SRC-INVALID: struct 'Empty' must declare at least one field" ;;
            empty-enum) echo "PF-SRC-INVALID: enum 'Empty' must declare at least one variant" ;;
            empty-enum-payload) echo "PF-SRC-INVALID: enum variant 'Empty' payload must contain at least one type" ;;
            escaped-struct-keyword|escaped-enum-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            ordinary-reserved-struct-identifier|reserved-struct-identifier) echo "PF-SRC-INVALID: reserved portable identifier 'struct'" ;;
            ordinary-reserved-enum-identifier|reserved-enum-identifier) echo "PF-SRC-INVALID: reserved portable identifier 'enum'" ;;
            duplicate-const) echo "PF-SRC-INVALID: program 'DuplicateConst' contains duplicate const declarations" ;;
            escaped-const-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            ordinary-reserved-const-identifier|escaped-reserved-const-identifier|reserved-const-expression) echo "PF-SRC-INVALID: reserved portable identifier 'const'" ;;
            unknown-const-type) echo "PF-SRC-INVALID: unsupported portable type" ;;
            const-literal-overflow) echo "PF-SRC-INVALID: UInt64 literal is out of range: 18446744073709551616" ;;
            priority-enum-before-const) echo "PF-SRC-INVALID: program 'PriorityEnumBeforeConst' contains duplicate enum declarations" ;;
            priority-const-before-initializer-param) echo "PF-SRC-INVALID: program 'PriorityConstBeforeInitializerParam' contains duplicate const declarations" ;;
            priority-const-name-before-type-value) echo "PF-SRC-INVALID: reserved portable identifier 'const'" ;;
            priority-const-type-before-value) echo "PF-SRC-INVALID: unsupported portable type" ;;
            duplicate-fn) echo "PF-SRC-INVALID: program 'DuplicateFn' contains duplicate fn declarations" ;;
            duplicate-fn-param) echo "PF-SRC-INVALID: fn 'first' contains duplicate parameters" ;;
            empty-fn-body) echo "PF-SRC-INVALID: fn 'helper' must declare at least one statement" ;;
            escaped-fn-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            ordinary-reserved-fn-identifier|escaped-reserved-fn-identifier) echo "PF-SRC-INVALID: reserved portable identifier 'fn'" ;;
            unknown-fn-result) echo "PF-SRC-INVALID: unsupported portable type" ;;
            fn-literal-overflow) echo "PF-SRC-INVALID: UInt64 literal is out of range: 18446744073709551616" ;;
            priority-const-before-fn) echo "PF-SRC-INVALID: program 'PriorityConstBeforeFn' contains duplicate const declarations" ;;
            priority-fn-before-initializer-param) echo "PF-SRC-INVALID: program 'PriorityFnBeforeInitializerParam' contains duplicate fn declarations" ;;
            priority-initializer-param-before-fn-param) echo "PF-SRC-INVALID: initializer contains duplicate parameters" ;;
            priority-entry-param-before-fn-param) echo "PF-SRC-INVALID: entry 'run' contains duplicate parameters" ;;
            priority-fn-param-before-empty-body) echo "PF-SRC-INVALID: fn 'helper' contains duplicate parameters" ;;
            priority-fn-name-before-param-result-body) echo "PF-SRC-INVALID: reserved portable identifier 'const'" ;;
            priority-fn-param-before-result-body) echo "PF-SRC-INVALID: reserved portable identifier 'fn'" ;;
            priority-fn-result-before-body) echo "PF-SRC-INVALID: unsupported portable type" ;;
            duplicate-entry-fn-callable) echo "PF-SRC-INVALID: program 'DuplicateEntryFnCallable' contains duplicate callable declarations" ;;
            duplicate-view-fn-callable) echo "PF-SRC-INVALID: program 'DuplicateViewFnCallable' contains duplicate callable declarations" ;;
            priority-fn-before-callable) echo "PF-SRC-INVALID: program 'PriorityFnBeforeCallable' contains duplicate fn declarations" ;;
            priority-callable-before-invariant) echo "PF-SRC-INVALID: program 'PriorityCallableBeforeInvariant' contains duplicate callable declarations" ;;
            duplicate-entry-view-callable) echo "PF-SRC-INVALID: program 'DuplicateEntryViewCallable' contains duplicate entry declarations" ;;
            priority-entry-before-callable) echo "PF-SRC-INVALID: program 'PriorityEntryBeforeCallable' contains duplicate entry declarations" ;;
            duplicate-invariant) echo "PF-SRC-INVALID: program 'DuplicateInvariant' contains duplicate invariant declarations" ;;
            escaped-invariant-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            ordinary-reserved-invariant-identifier|escaped-reserved-invariant-identifier|reserved-invariant-expression) echo "PF-SRC-INVALID: reserved portable identifier 'invariant'" ;;
            invariant-literal-overflow) echo "PF-SRC-INVALID: UInt64 literal is out of range: 18446744073709551616" ;;
            priority-fn-before-invariant) echo "PF-SRC-INVALID: program 'PriorityFnBeforeInvariant' contains duplicate fn declarations" ;;
            priority-invariant-before-initializer-param) echo "PF-SRC-INVALID: program 'PriorityInvariantBeforeInitializerParam' contains duplicate invariant declarations" ;;
            priority-invariant-name-before-predicate) echo "PF-SRC-INVALID: reserved portable identifier 'invariant'" ;;
            duplicate-extension-same) echo "PF-SRC-INVALID: program 'DuplicateExtensionSame' contains duplicate extension requirements" ;;
            duplicate-extension-conflict) echo "PF-SRC-INVALID: program 'DuplicateExtensionConflict' contains duplicate extension requirements" ;;
            escaped-requires-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            malformed-extension-id|uppercase-extension-id|priority-extension-id-before-version-digest) echo "PF-SRC-INVALID: extension id has an invalid segment" ;;
            single-segment-extension-id) echo "PF-SRC-INVALID: extension id must contain at least one dot" ;;
            malformed-extension-semver|latest-extension-semver) echo "PF-SRC-INVALID: semver core requires major.minor.patch" ;;
            vprefix-extension-semver|priority-extension-version-before-digest) echo "PF-SRC-INVALID: v prefix forbidden" ;;
            range-extension-semver|wildcard-extension-semver) echo "PF-SRC-INVALID: numeric component must contain ASCII digits only" ;;
            leading-zero-extension-semver) echo "PF-SRC-INVALID: leading zero forbidden" ;;
            overflow-extension-semver) echo "PF-SRC-INVALID: numeric component exceeds UInt64" ;;
            bare-extension-digest) echo "PF-SRC-INVALID: digest must use sha256: tag" ;;
            uppercase-extension-digest) echo "PF-SRC-INVALID: digest hex must be lowercase [0-9a-f]" ;;
            wrong-length-extension-digest) echo "PF-SRC-INVALID: digest hex must be exactly 64 lowercase characters" ;;
            priority-invariant-before-extension) echo "PF-SRC-INVALID: program 'PriorityInvariantBeforeExtension' contains duplicate invariant declarations" ;;
            priority-extension-before-initializer-param) echo "PF-SRC-INVALID: program 'PriorityExtensionBeforeInitializerParam' contains duplicate extension requirements" ;;
            duplicate-proof-reference) echo "PF-SRC-INVALID: program 'DuplicateProofReference' contains duplicate proof references" ;;
            duplicate-proof-reference-conflict) echo "PF-SRC-INVALID: program 'DuplicateProofReferenceConflict' contains duplicate proof references" ;;
            unknown-proof-invariant|priority-unknown-before-initializer-param) echo "PF-SRC-INVALID: proof reference names unknown invariant 'Missing'" ;;
            unqualified-proof-theorem) echo "PF-SRC-INVALID: proof theorem name must contain at least two components" ;;
            escaped-proof-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            escaped-dotted-proof-theorem) echo "PF-SRC-INVALID: qualified-name component must use Lean identifier characters" ;;
            reserved-proof-theorem-component) echo "PF-SRC-INVALID: reserved portable identifier 'proof'" ;;
            reserved-proof-invariant|priority-proof-invariant-before-theorem) echo "PF-SRC-INVALID: reserved portable identifier 'proof'" ;;
            priority-extension-before-proof) echo "PF-SRC-INVALID: program 'PriorityExtensionBeforeProof' contains duplicate extension requirements" ;;
            priority-proof-before-unknown) echo "PF-SRC-INVALID: program 'PriorityProofBeforeUnknown' contains duplicate proof references" ;;
            escaped-event-keyword|escaped-error-keyword) echo "PF-SRC-INVALID: unsupported portable program item" ;;
            reserved-event-identifier|escaped-reserved-event-identifier) echo "PF-SRC-INVALID: reserved portable identifier 'event'" ;;
            reserved-error-identifier|escaped-reserved-error-identifier) echo "PF-SRC-INVALID: reserved portable identifier 'error'" ;;
            duplicate-initializer) echo "PF-SRC-INVALID: program may declare at most one initializer" ;;
            priority-identity-before-decode) echo "PF-BOUND-001: portable program identity exceeds nesting limit 256" ;;
            priority-decode-before-initializer) echo "PF-SRC-INVALID: UInt64 literal is out of range: 18446744073709551616" ;;
            priority-initializer-before-zero) echo "PF-SRC-INVALID: program may declare at most one initializer" ;;
            priority-zero-before-state) echo "PF-SRC-INVALID: program 'PriorityZeroBeforeState' must declare at least one entry or view" ;;
            priority-state-before-entry) echo "PF-SRC-INVALID: program 'PriorityStateBeforeEntry' contains duplicate state declarations" ;;
            priority-entry-before-initializer-param) echo "PF-SRC-INVALID: program 'PriorityEntryBeforeInitializerParam' contains duplicate entry declarations" ;;
            priority-initializer-param-before-entry-param) echo "PF-SRC-INVALID: initializer contains duplicate parameters" ;;
            priority-entry-param-declaration-order) echo "PF-SRC-INVALID: entry 'first' contains duplicate parameters" ;;
            escaped-bool-type|unknown-type|qualified-type) echo "PF-SRC-INVALID: unsupported portable type" ;;
            invalid-uint-width|escaped-uint8-type|qualified-uint8-type|uint8-second-token) echo "PF-SRC-INVALID: unsupported portable type" ;;
            unit64-type|escaped-unit-type|qualified-unit-type|unit-second-token) echo "PF-SRC-INVALID: unsupported portable type" ;;
            principal64-type|escaped-principal-type|qualified-principal-type|principal-second-token) echo "PF-SRC-INVALID: unsupported portable type" ;;
            plural-option-type|escaped-option-type|unknown-option-element|missing-option-element) echo "PF-SRC-INVALID: unsupported portable type" ;;
            bytes-bare-type|bytes64-type|escaped-bytes-type|qualified-bytes-type|bytes-identifier-length|bytes-hex-length|bytes-leading-zero-length|bytes-over-limit) echo "PF-SRC-INVALID: unsupported portable type" ;;
            unknown-let-type) echo "PF-SRC-INVALID: unsupported portable type" ;;
            reserved-let-binder) echo "PF-SRC-INVALID: reserved portable identifier 'const'" ;;
            escaped-field-constructor|escaped-field-id|unknown-field-constructor|unknown-field-id|qualified-field-id|missing-field-id) echo "PF-SRC-INVALID: unsupported portable type" ;;
            *) echo "missing expected diagnostic for $1" >&2; return 1 ;;
        esac
    }
    fixtures=(
        zero-callable duplicate-state duplicate-entry duplicate-initializer-param
        duplicate-entry-param duplicate-event duplicate-error duplicate-event-param
        duplicate-error-param escaped-event-keyword escaped-error-keyword duplicate-initializer
        duplicate-struct duplicate-enum duplicate-struct-field duplicate-enum-variant
        empty-struct empty-enum empty-enum-payload escaped-struct-keyword escaped-enum-keyword
        ordinary-reserved-struct-identifier reserved-struct-identifier
        ordinary-reserved-enum-identifier reserved-enum-identifier
        duplicate-const escaped-const-keyword ordinary-reserved-const-identifier
        escaped-reserved-const-identifier reserved-const-expression unknown-const-type
        const-literal-overflow
        priority-enum-before-const priority-const-before-initializer-param
        priority-const-name-before-type-value priority-const-type-before-value
        duplicate-fn duplicate-fn-param empty-fn-body escaped-fn-keyword ordinary-reserved-fn-identifier
        escaped-reserved-fn-identifier unknown-fn-result fn-literal-overflow
        priority-const-before-fn priority-fn-before-initializer-param
        priority-initializer-param-before-fn-param priority-entry-param-before-fn-param
        priority-fn-param-before-empty-body priority-fn-name-before-param-result-body
        priority-fn-param-before-result-body priority-fn-result-before-body
        duplicate-entry-fn-callable duplicate-view-fn-callable
        priority-fn-before-callable priority-callable-before-invariant
        duplicate-entry-view-callable priority-entry-before-callable
        duplicate-invariant escaped-invariant-keyword ordinary-reserved-invariant-identifier
        escaped-reserved-invariant-identifier reserved-invariant-expression invariant-literal-overflow
        priority-fn-before-invariant priority-invariant-before-initializer-param
        priority-invariant-name-before-predicate
        duplicate-extension-same duplicate-extension-conflict escaped-requires-keyword
        malformed-extension-id uppercase-extension-id single-segment-extension-id
        malformed-extension-semver vprefix-extension-semver range-extension-semver
        latest-extension-semver wildcard-extension-semver leading-zero-extension-semver
        overflow-extension-semver bare-extension-digest uppercase-extension-digest
        wrong-length-extension-digest priority-extension-id-before-version-digest
        priority-extension-version-before-digest priority-invariant-before-extension
        priority-extension-before-initializer-param
        duplicate-proof-reference duplicate-proof-reference-conflict unknown-proof-invariant
        unqualified-proof-theorem escaped-proof-keyword escaped-dotted-proof-theorem
        reserved-proof-theorem-component reserved-proof-invariant
        priority-extension-before-proof priority-proof-before-unknown
        priority-unknown-before-initializer-param priority-proof-invariant-before-theorem
        reserved-event-identifier reserved-error-identifier escaped-reserved-event-identifier
        escaped-reserved-error-identifier
        priority-identity-before-decode
        priority-decode-before-initializer
        priority-initializer-before-zero priority-zero-before-state priority-state-before-entry
        priority-entry-before-initializer-param priority-initializer-param-before-entry-param
        priority-entry-param-declaration-order escaped-bool-type unknown-type qualified-type
        invalid-uint-width escaped-uint8-type qualified-uint8-type uint8-second-token
        unit64-type escaped-unit-type qualified-unit-type unit-second-token
        principal64-type escaped-principal-type qualified-principal-type principal-second-token
        plural-option-type escaped-option-type unknown-option-element missing-option-element
        bytes-bare-type bytes64-type escaped-bytes-type qualified-bytes-type
        bytes-identifier-length bytes-hex-length bytes-leading-zero-length bytes-over-limit
        unknown-let-type reserved-let-binder
        escaped-field-constructor escaped-field-id unknown-field-constructor unknown-field-id
        qualified-field-id missing-field-id
    )
    for fixture in "${fixtures[@]}"; do
        lean_log="build/frontend-parity-negative/$fixture.lean.log"
        cli_log="build/frontend-parity-negative/$fixture.cli.log"
        lean_output="build/frontend-parity-negative/$fixture.olean"
        cli_output="build/frontend-parity-negative/$fixture-cli"
        if lake env lean "testdata/invalid/$fixture.lean" -o "$lean_output" > "$lean_log" 2>&1; then echo "$fixture unexpectedly compiled through Lean command elaboration" >&2; exit 1; fi
        rg -q "PF-(SRC-INVALID|BOUND-001)" "$lean_log"
        if lake env .lake/build/bin/proof-forge-next build "$fixture.lean" --root testdata/invalid --target solana -o "$cli_output" > "$cli_log" 2>&1; then echo "$fixture unexpectedly compiled through CLI loader" >&2; exit 1; fi
        rg -q "PF-(SRC-INVALID|BOUND-001)" "$cli_log"
        expected="$(expected_diagnostic "$fixture")"
        test "$(rg -o 'PF-(SRC-INVALID|BOUND-001):.*' "$lean_log" | head -1)" = "$expected"
        test "$(rg -o 'PF-(SRC-INVALID|BOUND-001):.*' "$cli_log" | head -1)" = "$expected"
        test ! -e "$lean_output"
        test ! -e "$cli_output"
    done
    rm -rf build/syntax-bounds
    /usr/bin/python3 -I -S scripts/generate_syntax_bound_fixtures.py build/syntax-bounds
    lake env lean build/syntax-bounds/namespace-at-limit.lean -o build/syntax-bounds/namespace-at-limit.olean
    lake env .lake/build/bin/proof-forge-next build namespace-at-limit.lean --root build/syntax-bounds --target solana -o cli-at-limit
    lake env lean build/syntax-bounds/namespace-unwound-at-limit.lean -o build/syntax-bounds/namespace-unwound-at-limit.olean
    lake env .lake/build/bin/proof-forge-next build namespace-unwound-at-limit.lean --root build/syntax-bounds --target solana -o cli-unwound-at-limit
    lake env .lake/build/bin/proof-forge-next build source-at-limit.lean --root build/syntax-bounds --target solana -o source-at-limit-cli
    for fixture in namespace-over-limit namespace-and-expression-over-limit expression-over-limit nodes-over-limit; do
        if lake env lean "build/syntax-bounds/$fixture.lean" -o "build/syntax-bounds/$fixture.olean" > "build/syntax-bounds/$fixture.lean.log" 2>&1; then echo "$fixture unexpectedly compiled through Lean command elaboration" >&2; exit 1; fi
        rg -q "PF-BOUND-001" "build/syntax-bounds/$fixture.lean.log"
        if lake env .lake/build/bin/proof-forge-next build "$fixture.lean" --root build/syntax-bounds --target solana -o "$fixture-cli" > "build/syntax-bounds/$fixture.cli.log" 2>&1; then echo "$fixture unexpectedly compiled through CLI loader" >&2; exit 1; fi
        rg -q "PF-BOUND-001" "build/syntax-bounds/$fixture.cli.log"
        test "$(rg -o 'PF-BOUND-001:.*' "build/syntax-bounds/$fixture.lean.log" | head -1)" = "$(rg -o 'PF-BOUND-001:.*' "build/syntax-bounds/$fixture.cli.log" | head -1)"
        test ! -e "build/syntax-bounds/$fixture-cli"
    done
    if lake env .lake/build/bin/proof-forge-next build source-over-limit.lean --root build/syntax-bounds --target solana -o source-over-limit-cli > build/syntax-bounds/source-over-limit.cli.log 2>&1; then echo "oversized source unexpectedly passed the CLI loader" >&2; exit 1; fi
    rg -q "PF-SRC-INVALID.*16 MiB" build/syntax-bounds/source-over-limit.cli.log
    test ! -e build/syntax-bounds/source-over-limit-cli

product-negative: build
    rm -rf build/v2/module-required-negative build/v2/module-parse-negative
    ec=0; lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --target solana -o build/v2/module-required-negative > build/module-required-negative.log 2>&1 || ec=$?; if [ "$ec" -eq 0 ]; then echo "ProgramV1 build unexpectedly accepted a missing --module" >&2; exit 1; fi; if [ "$ec" -ne 2 ]; then echo "missing --module must exit 2, got $ec" >&2; cat build/module-required-negative.log >&2; exit 1; fi
    rg -q -- "--module is required for canonical ProgramV1 identity" build/module-required-negative.log
    test ! -e build/v2/module-required-negative
    ec=0; lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module "Examples.StateCell trailing" --target solana -o build/v2/module-parse-negative > build/module-parse-negative.log 2>&1 || ec=$?; if [ "$ec" -eq 0 ]; then echo "ProgramV1 build unexpectedly accepted a non-identifier module" >&2; exit 1; fi; if [ "$ec" -ne 3 ]; then echo "bad --module must exit 3 (product diagnostic), got $ec" >&2; cat build/module-parse-negative.log >&2; exit 1; fi
    rg -q -- "--module must be one exact Lean identifier" build/module-parse-negative.log
    test ! -e build/v2/module-parse-negative

# Exact positive CLI stdout anchors for list/describe (selection surface; no build outputs).
target-cli-positive: build
	mkdir -p build
	lake env .lake/build/bin/proof-forge-next list-targets > build/list-targets.stdout
	printf '%b' 'aleo\tinstructions-only\ncosmwasm\twasm-validated-alpha\nevm\truntime-validated-alpha\nnear\twasm-validated-alpha\nnoir\tsource-only\npsy\tdpn-only\nquint\tsource-only\nsolana\tplan-only\nton\tsource-only\n' > build/list-targets.expected
	cmp -s build/list-targets.expected build/list-targets.stdout
	lake env .lake/build/bin/proof-forge-next list-targets --all > build/list-targets-all.stdout
	printf '%b' 'aleo\tinstructions-only\ncosmwasm\twasm-validated-alpha\nevm\truntime-validated-alpha\nicp\tresearch-only\nnear\twasm-validated-alpha\nnoir\tsource-only\nopenvm\tresearch-only\npsy\tdpn-only\nquint\tsource-only\nsolana\tplan-only\nsoroban\tresearch-only\nton\tsource-only\n' > build/list-targets-all.expected
	cmp -s build/list-targets-all.expected build/list-targets-all.stdout
	lake env .lake/build/bin/proof-forge-next inspect evm > build/inspect-evm.stdout
	rg -q '^target=evm$' build/inspect-evm.stdout
	rg -q '^profile=evm-yul-solc-0.8.34-v1$' build/inspect-evm.stdout
	# AddressBearing + pf.assets: EVM admits call/schedule and the exact SDK extension row.
	rg -q '^requirements=#\[effect.asynchronous-workflow, effect.event, effect.synchronous-call, extension.pf-assets, failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic\]$' build/inspect-evm.stdout
	rg -q '^status=implemented$' build/inspect-evm.stdout
	rg -q '^registryRootDigest=sha256:[0-9a-f]{64}$' build/inspect-evm.stdout
	rg -q '^supportClaimDigest=sha256:[0-9a-f]{64}$' build/inspect-evm.stdout
	rg -q '^buildIdentityDomain=pf.build-identity.engineering.v1$' build/inspect-evm.stdout
	lake env .lake/build/bin/proof-forge-next inspect aleo > build/inspect-aleo.stdout
	rg -q '^target=aleo$' build/inspect-aleo.stdout
	rg -q '^profile=aleo-instructions-v1$' build/inspect-aleo.stdout
	rg -q '^requirements=#\[failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic\]$' build/inspect-aleo.stdout
	rg -q '^maturity=instructions-only$' build/inspect-aleo.stdout
	rg -q '^registryRootDigest=sha256:[0-9a-f]{64}$' build/inspect-aleo.stdout
	rg -q '^supportClaimDigest=sha256:[0-9a-f]{64}$' build/inspect-aleo.stdout
	lake env .lake/build/bin/proof-forge-next inspect psy > build/inspect-psy.stdout
	rg -q '^target=psy$' build/inspect-psy.stdout
	rg -q '^profile=psy-dpn-v1$' build/inspect-psy.stdout
	rg -q '^requirements=#\[effect.event, effect.synchronous-call, failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic\]$' build/inspect-psy.stdout
	rg -q '^maturity=dpn-only$' build/inspect-psy.stdout
	rg -q '^registryRootDigest=sha256:[0-9a-f]{64}$' build/inspect-psy.stdout
	rg -q '^supportClaimDigest=sha256:[0-9a-f]{64}$' build/inspect-psy.stdout
	lake env .lake/build/bin/proof-forge-next inspect cosmwasm > build/inspect-cosmwasm.stdout
	rg -q '^target=cosmwasm$' build/inspect-cosmwasm.stdout
	rg -q '^profile=cosmwasm-wasm-u64-v1$' build/inspect-cosmwasm.stdout
	rg -q '^requirements=#\[effect.asynchronous-workflow, effect.event, effect.synchronous-call, extension.pf-assets, failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic\]$' build/inspect-cosmwasm.stdout
	rg -q '^status=implemented$' build/inspect-cosmwasm.stdout
	rg -q '^maturity=wasm-validated-alpha$' build/inspect-cosmwasm.stdout
	rg -q '^registryRootDigest=sha256:[0-9a-f]{64}$' build/inspect-cosmwasm.stdout
	rg -q '^supportClaimDigest=sha256:[0-9a-f]{64}$' build/inspect-cosmwasm.stdout
	rg -q '^buildIdentityDomain=pf.build-identity.engineering.v1$' build/inspect-cosmwasm.stdout
	lake env .lake/build/bin/proof-forge-next inspect quint > build/inspect-quint.stdout
	rg -q '^target=quint$' build/inspect-quint.stdout
	rg -q '^profile=quint-source-u64-model-v1$' build/inspect-quint.stdout
	rg -q '^requirements=#\[effect.synchronous-call, extension.pf-assets, failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic\]$' build/inspect-quint.stdout
	rg -q '^status=implemented$' build/inspect-quint.stdout
	rg -q '^maturity=source-only$' build/inspect-quint.stdout
	rg -q '^registryRootDigest=sha256:[0-9a-f]{64}$' build/inspect-quint.stdout
	rg -q '^supportClaimDigest=sha256:[0-9a-f]{64}$' build/inspect-quint.stdout
	rg -q '^buildIdentityDomain=pf.build-identity.engineering.v1$' build/inspect-quint.stdout
	lake env .lake/build/bin/proof-forge-next inspect ton > build/inspect-ton.stdout
	rg -q '^target=ton$' build/inspect-ton.stdout
	rg -q '^profile=ton-tolk-boc-v1$' build/inspect-ton.stdout
	rg -q '^requirements=#\[effect.asynchronous-workflow, effect.event, failure.atomic-rollback, state.persistent, value.bool, value.checked-arithmetic\]$' build/inspect-ton.stdout
	rg -q '^profiles=#\[ton-tolk-boc-v1\]$' build/inspect-ton.stdout
	rg -q '^status=implemented$' build/inspect-ton.stdout
	rg -q '^maturity=source-only$' build/inspect-ton.stdout
	rg -q '^registryRootDigest=sha256:[0-9a-f]{64}$' build/inspect-ton.stdout
	rg -q '^supportClaimDigest=sha256:[0-9a-f]{64}$' build/inspect-ton.stdout
	rg -q '^buildIdentityDomain=pf.build-identity.engineering.v1$' build/inspect-ton.stdout

# Dedicated ProgramV1 source-bound gate (B2). Independent of quarantined dsl-negative.
# Real proof-forge-next CLI with explicit --module Root; heavy fixtures under build/.
source-bounds: build
    bash scripts/program_v1_source_bounds

target-negative: build
    rm -rf build/v2/openvm-negative build/v2/network-negative build/v2/cross-profile-negative \
      build/v2/uppercase-target-negative build/v2/malformed-target-negative \
      build/v2/dup-target-negative build/v2/dup-profile-negative \
      build/v2/tool-negative build/v2/tool-mismatch
    mkdir -p build
    # design-only openvm — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target openvm -o build/v2/openvm-negative > build/openvm-negative.log 2>&1; then echo "research-only target unexpectedly built" >&2; exit 1; fi
    printf '%s\n' "uncaught exception: PF-TARGET-NOT-IMPLEMENTED: target 'openvm' has research metadata but no compiler implementation" > build/openvm-negative.expected
    cmp -s build/openvm-negative.expected build/openvm-negative.log
    test ! -e build/v2/openvm-negative
    # --network usage error — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm --network local -o build/v2/network-negative > build/network-negative.log 2>&1; then echo "--network unexpectedly accepted" >&2; exit 1; fi
    printf '%s\n' "unknown option '--network'" > build/network-negative.expected
    cmp -s build/network-negative.expected build/network-negative.log
    test ! -e build/v2/network-negative
    # cross-target profile — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm --profile near-wasm-raw-u64-v1 -o build/v2/cross-profile-negative > build/cross-profile-negative.log 2>&1; then echo "cross-target profile unexpectedly accepted" >&2; exit 1; fi
    printf '%s\n' "uncaught exception: PF-PROFILE-UNKNOWN: unknown codegen profile 'near-wasm-raw-u64-v1'" > build/cross-profile-negative.expected
    cmp -s build/cross-profile-negative.expected build/cross-profile-negative.log
    test ! -e build/v2/cross-profile-negative
    # uppercase target — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target EVM -o build/v2/uppercase-target-negative > build/uppercase-target-negative.log 2>&1; then echo "uppercase target unexpectedly accepted" >&2; exit 1; fi
    printf '%s\n' "unknown target 'EVM'" > build/uppercase-target-negative.expected
    cmp -s build/uppercase-target-negative.expected build/uppercase-target-negative.log
    test ! -e build/v2/uppercase-target-negative
    # malformed target — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target "1evm" -o build/v2/malformed-target-negative > build/malformed-target-negative.log 2>&1; then echo "malformed target unexpectedly accepted" >&2; exit 1; fi
    printf '%s\n' "unknown target '1evm'" > build/malformed-target-negative.expected
    cmp -s build/malformed-target-negative.expected build/malformed-target-negative.log
    test ! -e build/v2/malformed-target-negative
    # duplicate --target — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm --target near -o build/v2/dup-target-negative > build/dup-target-negative.log 2>&1; then echo "duplicate --target unexpectedly accepted" >&2; exit 1; fi
    printf '%s\n' "duplicate --target" > build/dup-target-negative.expected
    cmp -s build/dup-target-negative.expected build/dup-target-negative.log
    test ! -e build/v2/dup-target-negative
    # duplicate --profile — exact log
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm --profile evm-yul-solc-0.8.34-v1 --profile near-wasm-raw-u64-v1 -o build/v2/dup-profile-negative > build/dup-profile-negative.log 2>&1; then echo "duplicate --profile unexpectedly accepted" >&2; exit 1; fi
    printf '%s\n' "duplicate --profile" > build/dup-profile-negative.expected
    cmp -s build/dup-profile-negative.expected build/dup-profile-negative.log
    test ! -e build/v2/dup-profile-negative
    # Toolchain negatives require a successful source frontend and therefore run
    # only on the current Darwin development product path. Linux CI separately
    # asserts the closed unsupported-platform diagnostic with zero publication.
    if [ "$(uname -s)" = Darwin ]; then if PROOF_FORGE_TOOL_ROOT=/definitely/missing lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm -o build/v2/tool-negative > build/tool-negative.log 2>&1; then echo "missing solc unexpectedly accepted" >&2; exit 1; fi; rg -q "PF-TOOLCHAIN-MISSING" build/tool-negative.log; fi
    rm -rf build/tool-mismatch-root
    mkdir -p build/tool-mismatch-root
    ln -s /usr/bin/false build/tool-mismatch-root/solc
    if [ "$(uname -s)" = Darwin ]; then if PROOF_FORGE_TOOL_ROOT="$PWD/build/tool-mismatch-root" lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm -o build/v2/tool-mismatch > build/tool-mismatch.log 2>&1; then echo "invalid solc unexpectedly accepted" >&2; exit 1; fi; rg -q "PF-TOOLCHAIN-MISMATCH" build/tool-mismatch.log; fi

# Engineering-only subset of PRD NFR-001: same host/binary, StateCell,
# two consecutive product builds for zero-tool Solana-plan and Noir profiles.
# Not hermetic, clean-room, multi-host, formal TST, or full-target coverage.
nfr-repeat: build
    /usr/bin/python3 -I -S scripts/nfr_repeat_gate_self_test.py
    /usr/bin/python3 -I -S scripts/nfr_repeat_gate.py

target-smoke: build
    rm -rf build/v2/standalone build/v2/evm build/v2/evm-accumulator build/v2/evm-arithops build/v2/solana build/v2/solana-accumulator build/v2/near build/v2/near-accumulator build/v2/noir build/v2/noir-accumulator
    lake env .lake/build/bin/proof-forge-next build testdata/valid/Standalone.lean --module Standalone --target evm -o build/v2/standalone
    lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm -o build/v2/evm
    lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --module Examples.Accumulator --target evm -o build/v2/evm-accumulator
    lake env .lake/build/bin/proof-forge-next build testdata/valid/ArithOps.lean --module ArithOps --target evm -o build/v2/evm-arithops
    lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target solana -o build/v2/solana
    lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --module Examples.Accumulator --target solana -o build/v2/solana-accumulator
    DYLD_LIBRARY_PATH=/definitely/missing lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target near -o build/v2/near
    DYLD_LIBRARY_PATH=/definitely/missing lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --module Examples.Accumulator --target near -o build/v2/near-accumulator
    lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target noir -o build/v2/noir
    lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --module Examples.Accumulator --target noir -o build/v2/noir-accumulator
    /usr/bin/python3 -I -S scripts/validate_artifacts.py build/v2

output-security: build
    rm -rf build/v2/atomic-output build/v2/atomic-before build/v2/atomic-new build/source-overlap
    lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm -o build/v2/atomic-output
    cp -R build/v2/atomic-output build/v2/atomic-before
    if lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm -o build/v2/atomic-output > build/atomic-output.log 2>&1; then echo "existing output unexpectedly replaced" >&2; exit 1; fi
    rg -q "PF-OUTPUT-COLLISION" build/atomic-output.log
    diff -ru build/v2/atomic-before build/v2/atomic-output
    if PROOF_FORGE_TOOL_ROOT=/definitely/missing lake env .lake/build/bin/proof-forge-next build Examples/StateCell.lean --module Examples.StateCell --target evm -o build/v2/atomic-new > build/atomic-new.log 2>&1; then echo "tool failure unexpectedly published a new directory" >&2; exit 1; fi
    test ! -e build/v2/atomic-new
    test -z "$(find build/v2 -maxdepth 1 -name '.atomic-*.staging-*' -print -quit)"
    mkdir -p build/source-overlap/src
    cp testdata/valid/Standalone.lean build/source-overlap/src/Fixture.lean
    printf 'preserve-me\n' > build/source-overlap/src/important.txt
    if lake env .lake/build/bin/proof-forge-next build src/Fixture.lean --root build/source-overlap --module SourceOverlap --target solana -o src > build/source-overlap.log 2>&1; then echo "source directory unexpectedly replaced" >&2; exit 1; fi
    rg -q "PF-OUTPUT-COLLISION" build/source-overlap.log
    cmp testdata/valid/Standalone.lean build/source-overlap/src/Fixture.lean
    test "$(cat build/source-overlap/src/important.txt)" = preserve-me

evm-runtime: target-smoke
    bash scripts/smoke_evm.sh

# EVMOZ-006: closed corpus schema + inventory (no EVM tools / no lake).
# Self-test includes validate-manifest negatives; then live manifest + all
# business cases + exact runnable set pin join.
evm-corpus-schema:
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(pwd)"
    validator="$root/scripts/evm_corpus_v1.py"
    cases_dir="$root/testdata/evm-corpus/v1/cases"
    manifest="$root/testdata/evm-corpus/v1/manifest.json"
    /usr/bin/python3 -I -S "$validator" self-test
    /usr/bin/python3 -I -S "$validator" validate-manifest "$manifest"
    case_count=0
    while IFS= read -r case_path; do
      [[ -n "$case_path" ]] || continue
      /usr/bin/python3 -I -S "$validator" validate-case "$case_path"
      case_count=$((case_count + 1))
    done < <(find "$cases_dir" -maxdepth 1 -type f -name '*.json' | sort)
    [[ "$case_count" -eq 6 ]] || {
      echo "evm-corpus-schema: expected 6 business cases, got $case_count" >&2
      exit 1
    }
    runnable="$(/usr/bin/python3 -I -S "$validator" list-runnable-cases "$cases_dir")"
    runnable_count="$(printf '%s\n' "$runnable" | grep -c . || true)"
    [[ "$runnable_count" -eq 6 ]] || {
      echo "evm-corpus-schema: expected 6 runnable cases, got $runnable_count" >&2
      exit 1
    }
    echo "evm-corpus-schema: ok (self-test + manifest + $case_count cases + $runnable_count runnable)"

# EVMOZ-006: Reference leg only (depends on build; no solc/anvil).
# Safe-clean fixed OBS root under build/, run Loader→Normalize→Reference.
# scripts/evm_corpus_reference.sh enforces exact 28 reference obs and no PF/OZ legs.
evm-corpus-reference: build
    #!/usr/bin/env bash
    set -euo pipefail
    root="$(pwd)"
    validator="$root/scripts/evm_corpus_v1.py"
    obs_requested="$root/build/v2/evm-corpus-obs"
    obs_root="$(/usr/bin/python3 -I -S "$validator" safe-obs-root "$root" "$obs_requested")"
    rm -rf "$obs_root"
    mkdir -p "$obs_root"
    export PF_EVM_CORPUS_OBS_DIR="$obs_root"
    bash "$root/scripts/evm_corpus_reference.sh"

# Aggregate static corpus gate (schema + reference). Serial; no concurrent lake.
evm-corpus-static: evm-corpus-schema evm-corpus-reference

# Manual toolful Cancun full harness (required tools hard-fail). NOT ordinary CI.
evm-corpus-runtime: build
    bash scripts/evm_corpus_runtime.sh

# Solana S3a: Mollusk runtime differential for StateCell.so (requires materialised sbpf + Rust).
# Also runs #125 CPI product acceptance (fail-closed) before product ELF builds.
solana-runtime:
    bash scripts/solana_runtime_test.sh


# Engineering CLI dist (REL-CLI-1). Not formal Stage-0.
# Authority: docs/product/05-distribution-and-packages.md
# Requires: lake-built proof-forge-next with `version` command; VERSION == Lean constant.
package-cli *ARGS:
    bash scripts/package_cli_dist.sh {{ARGS}}

package-cli-smoke:
    bash scripts/package_cli_dist_smoke.sh

# CWD-free doctor from packaged dist (foreign working directory).
package-cli-cwd-free-smoke:
    bash scripts/package_cli_cwd_free_smoke.sh

# Minimal Lean Author SDK (Syntax import closure). Engineering-dist only.
# Authority: docs/product/05-distribution-and-packages.md REL-AUTHOR-0
package-author-sdk *ARGS:
    /usr/bin/python3 -I -S scripts/package_author_sdk.py {{ARGS}}

package-author-sdk-smoke:
    bash scripts/package_author_sdk_smoke.sh

# Host SDK Python wheel/sdist (engineering-dist). Not formal Stage-0.
package-host-sdk *ARGS:
    bash scripts/package_host_sdk.sh {{ARGS}}

package-host-sdk-smoke:
    bash scripts/package_host_sdk_smoke.sh

# Publish Host SDK to PyPI/TestPyPI (REL-HOST-1). Prefer CI Trusted Publishing.
# Local: TWINE_USERNAME=__token__ TWINE_PASSWORD=pypi-...
publish-host-sdk-pypi *ARGS:
    bash scripts/publish_host_sdk_pypi.sh {{ARGS}}


# CLI local-wrapper smoke: removed Aleo/Psy host lanes reject before spawn.
local-cli-smoke: build
    /bin/bash -p scripts/local_network_smoke.sh


# Aleo Wave-A: official Leo `abi` load gate for PF-emitted Instructions.
# Host-optional Leo 4.0.x (PROOF_FORGE_ALEO_LEO / TOOL_ROOT / cargo). Skip-clean
# if leo missing. Not VM/proof/devnet/testnet/mainnet/deployable evidence.
# See docs/plan/aleo-official-load-dev-testnet.md.
aleo-instructions-load: build
    /bin/bash -p scripts/aleo_instructions_load_acceptance.sh


# Aleo Wave-B: local VM interpret of PF-emitted Instructions via Leo runner shell.
# Product authority = PF .aleo copied into runner/build/imports (byte-pinned).
# Host-optional; skip-clean if leo missing. Not proof/devnet/testnet/mainnet.
# See docs/plan/aleo-official-load-dev-testnet.md.
aleo-instructions-interpret: build
    /bin/bash -p scripts/aleo_instructions_interpret_acceptance.sh


# Aleo Wave-C: network tx materialization (default save-only, no broadcast).
# Builds PF StateCell, proves Leo twin == PF Instructions (id rewrite), then
# leo deploy/execute --save against testnet (or PROOF_FORGE_ALEO_NETWORK=devnet).
# Broadcast only if PROOF_FORGE_ALEO_BROADCAST=1 + PROOF_FORGE_ALEO_PRIVATE_KEY.
# Mainnet rejected. Not product deployable=true / formal / MCP default.
# See docs/plan/aleo-official-load-dev-testnet.md.
aleo-instructions-network-tx: build
    /bin/bash -p scripts/aleo_instructions_network_tx_acceptance.sh


# Noir ACIR IR-7 / G6 prove honesty probe (host-heavy; NOT ordinary ci).
# Probes locked $PROOF_FORGE_TOOL_ROOT/bb|barretenberg only (never PATH).
# Default today: PF-TOOLCHAIN-MISSING + PARTIAL (Tool Lock barretenberg=null;
# nargo is compile-only, not IR-7 prove authority). Do not invent prove CLI/CRS.
# Exit 2 expected until a Tool Lock Barretenberg/backend pin lands.
# Not product finalize / prove product path / deploy / formal / hermetic.
noir-runtime:
    bash scripts/noir_runtime_test.sh

# #125 Solana CPI CLI/product acceptance only (proof-forge.output.v1 EscrowCpi
# under solana-sbpf-cpi-elf-v1). Not ordinary ci; host/tool heavy like solana-runtime.
# Does not consume #118–#124 preactivation runtime manifests. Requires #125 product
# activation path (ordinary resolver sync+extension on this profile only).
solana-cpi-product-acceptance:
    bash scripts/solana_cpi_product_acceptance.sh

# TransferSol product example: local compiler/toolchain only, no Solana RPC.
solana-transfer-sol-build:
    bash scripts/solana_transfer_sol_build.sh

# The generic Solana client tests are offline and use a minimal locked graph.
# The hosted Solana runtime lane separately executes product ELFs under Mollusk.
solana-client-test:
    cargo test --manifest-path clients/solana-client/Cargo.toml --locked
    cargo clippy --manifest-path clients/solana-client/Cargo.toml --locked --all-targets -- -D warnings

# Rust developer CLI (Aleo-first); compiler authority remains proof-forge-next.
pf-cli-test:
    cargo test --manifest-path clients/pf-cli/Cargo.toml --locked

pf-cli-build:
    cargo build --manifest-path clients/pf-cli/Cargo.toml --locked --release

# Host-optional e2e: pf new/build/run/clean + multi-target + safety (needs proof-forge-next; leo optional).
# Also builds solana-client when possible for `pf verify` D7a coverage.
pf-cli-smoke: build pf-cli-build
    #!/usr/bin/env bash
    set -euo pipefail
    cargo build --manifest-path clients/solana-client/Cargo.toml --locked --release
    /bin/bash -p scripts/pf_cli_smoke.sh

# Host-optional: pf project flow EVM (new → build → test → deploy save).
pf-cli-evm-test: build pf-cli-build
    /bin/bash -p scripts/evm_pf_statecell_smoke.sh

# D9: side-by-side pf + proof-forge-next package under build/dist/ (host-optional).
pf-cli-dist: pf-cli-build
    /bin/bash -p scripts/pf_cli_dist.sh

# Host-optional: pf Solana project smoke + TransferSol specialty via pf scripts.
pf-cli-solana-test: build pf-cli-build
    #!/usr/bin/env bash
    set -euo pipefail
    /bin/bash -p scripts/solana_pf_project_smoke.sh
    /bin/bash -p scripts/solana_transfer_sol_local.sh

# TransferSol offline via developer CLI `pf` (build + verify + adapter).
solana-transfer-sol-offline: build pf-cli-build
    /bin/bash -p scripts/solana_transfer_sol_offline.sh

# Surfpool local Surfnet (engineering). Requires `surfpool` + Solana CLI on PATH.
# Not ordinary ci; not formal/mainnet. Mollusk remains the CPI differential gate.
solana-surfpool-up:
    bash scripts/solana_surfpool_up.sh

solana-surfpool-down:
    bash scripts/solana_surfpool_down.sh

# One-shot: start Surfpool → build MiniAmmAssets cpi-elf → deploy → program show → stop.
solana-surfpool-miniamm-smoke:
    bash scripts/solana_miniamm_assets_surfpool_smoke.sh

# Full business matrix on Surfpool (mainnet fork for Token/ATA by default):
# init → addLiquidity → swap0to1 → slippage → removeLiquidity dual transfer.
# Host-optional; needs network for mainnet datasource. Not ordinary ci / not formal.
solana-surfpool-miniamm-business:
    bash scripts/solana_miniamm_assets_surfpool_business.sh

# TransferSol local via `pf` (build + verify + Mollusk). No public RPC.
solana-transfer-sol-local: build pf-cli-build
    /bin/bash -p scripts/solana_transfer_sol_local.sh

# Developer-facing smokes that only use `pf` (project flow).
pf-cli-aleo-local: build pf-cli-build
    /bin/bash -p scripts/aleo_pf_local_smoke.sh

# Video/rehearsal: Aleo full path save-only (no broadcast). See docs/demos/aleo-testnet-walkthrough.md
pf-cli-aleo-demo: build pf-cli-build
    /bin/bash -p scripts/demo_aleo_testnet_save_only.sh

# asciinema record of Aleo demo (save-only unless PF_ALEO_BROADCAST=1 + PF_ALEO_TESTNET_KEY)
pf-cli-aleo-record: build pf-cli-build
    /bin/bash -p scripts/demo_aleo_record.sh

pf-cli-evm-project: build pf-cli-build
    /bin/bash -p scripts/evm_pf_statecell_smoke.sh

pf-cli-solana-project: build pf-cli-build
    /bin/bash -p scripts/solana_pf_project_smoke.sh

# crates.io dry-run (no upload). See clients/pf-cli/PUBLISH.md
pf-cli-publish-dry-run: pf-cli-test
    #!/usr/bin/env bash
    set -euo pipefail
    cargo package --manifest-path clients/pf-cli/Cargo.toml --locked --allow-dirty --list
    cargo publish --manifest-path clients/pf-cli/Cargo.toml --locked --dry-run --allow-dirty

# Real crates.io publish — requires PF_PUBLISH=1, cargo login, and a clean git tree.
pf-cli-publish: pf-cli-test
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${PF_PUBLISH:-}" != "1" ]]; then
      echo "pf-cli-publish: refuse (set PF_PUBLISH=1 after reading clients/pf-cli/PUBLISH.md)" >&2
      exit 2
    fi
    if [[ -n "$(git status --porcelain clients/pf-cli)" ]]; then
      echo "pf-cli-publish: clients/pf-cli has uncommitted changes — commit first (cargo publish refuses dirty trees)" >&2
      git status --short clients/pf-cli >&2
      exit 2
    fi
    cargo publish --manifest-path clients/pf-cli/Cargo.toml --locked

# Offline Solana verifier crate (test recipe lives above with clippy).
solana-client-publish-dry-run: solana-client-test
    #!/usr/bin/env bash
    set -euo pipefail
    cargo package --manifest-path clients/solana-client/Cargo.toml --locked --allow-dirty --list
    cargo publish --manifest-path clients/solana-client/Cargo.toml --locked --dry-run --allow-dirty

solana-client-publish: solana-client-test
    #!/usr/bin/env bash
    set -euo pipefail
    if [[ "${SC_PUBLISH:-}" != "1" ]]; then
      echo "solana-client-publish: refuse (set SC_PUBLISH=1 after reading clients/solana-client/PUBLISH.md)" >&2
      exit 2
    fi
    if [[ -n "$(git status --porcelain clients/solana-client)" ]]; then
      echo "solana-client-publish: clients/solana-client has uncommitted changes — commit first" >&2
      git status --short clients/solana-client >&2
      exit 2
    fi
    cargo publish --manifest-path clients/solana-client/Cargo.toml --locked

# Ordinary-host product gate. Release qualification is intentionally excluded.
# `source-bounds` is the dedicated ProgramV1 PF-BOUND-001 / 16 MiB gate;
# selection and S5–S7c deletion gates retain the engineering output closure.
# BUILD-4 local recipes: three independent lanes (also mapped in CI jobs).
# Hosted workflow invokes each `*-gates` / `*-cli-smoke` half as its own step so
# no single command shares the runner budget with shard compilation/execution.
# Full local `ci` retains all ten test shards and every existing gate.
# EVMOZ-006: evm-corpus-static after build/test (serial; avoids concurrent lake).
ci-lean-gates: docs-check sbom-package-files-check build product-negative source-bounds evm-corpus-static run-deletion-gates alpha-deletion-gate

ci-lean-product: test-nontarget ci-lean-gates

ci-target-cli-smoke: build target-cli-positive target-negative nfr-repeat local-cli-smoke

ci-target-smoke: test-targets ci-target-cli-smoke

ci: ci-lean-product ci-target-smoke

check: ci
