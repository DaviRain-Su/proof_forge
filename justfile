set shell := ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

platform_tag := if os() == "macos" { "darwin-arm64" } else if os() == "linux" { "linux-" + arch() } else { "unsupported-" + os() }
tool_root := env_var_or_default("PROOF_FORGE_TOOL_ROOT", env_var("HOME") + "/.cache/proof-forge-v2/tool-root/" + platform_tag)
locked_git := if os() == "macos" { "/Applications/Xcode.app/Contents/Developer/usr/bin/git" } else { "/usr/bin/git" }
locked_python := if os() == "macos" { "/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9" } else { "/usr/bin/python3" }

default: check

build:
    lake build ProofForgeV2 proof_forge_next

test:
    lake build proof_forge_next_tests
    lake env .lake/build/bin/proof-forge-next-tests

# Re-run unit tests with host-profile toolchain self-tests (darwin lock only).
test-host-isolation: build
    lake build proof_forge_next_tests
    PROOF_FORGE_HOST_ISOLATION_TEST=1 lake env .lake/build/bin/proof-forge-next-tests

docs-check:
    /usr/bin/python3 -I -S scripts/docs_check.py
    /usr/bin/python3 -I -S scripts/docs_check_self_test.py
    /usr/bin/python3 -I -S scripts/genesis_root_policy_self_test.py
    /usr/bin/python3 -I -S scripts/bootstrap_task_objects_self_test.py
    /usr/bin/python3 -I -S scripts/bootstrap_task_producers_self_test.py
    /usr/bin/python3 -I -S scripts/authority_store_self_test.py
    /usr/bin/python3 -I -S scripts/stage0_handoff_self_test.py
    /usr/bin/python3 -I -S scripts/bootstrap_acceptance_self_test.py
    /usr/bin/python3 -I -S scripts/bootstrap_sign_tool_self_test.py
    /usr/bin/python3 -I -S scripts/stage0_activate_self_test.py
    /usr/bin/python3 -I -S scripts/formal_evidence_self_test.py
    /usr/bin/python3 -I -S scripts/formal_evidence_producer_self_test.py
    /usr/bin/python3 -I -S scripts/revocation_ledger_self_test.py
    /usr/bin/python3 -I -S scripts/private_scan_self_test.py
    /usr/bin/python3 -I -S scripts/formal_input_producers_self_test.py
    /usr/bin/python3 -I -S scripts/formal_evidence_finalizer_self_test.py
    /usr/bin/python3 -I -S scripts/bootstrap_ceremony_prep_self_test.py

# TASK-D0-05 / TST-SBOM-001: deterministic license inventory + CycloneDX 1.6.
sbom:
    /usr/bin/python3 -I -S scripts/sbom_self_test.py
    /usr/bin/python3 -I -S scripts/sbom_generate.py --root . generate --output-dir build/sbom
    /usr/bin/python3 -I -S scripts/sbom_generate.py --root . verify --output-dir build/sbom
    /usr/bin/python3 -I -S scripts/sbom_closure_self_test.py

# TASK-D0-08: re-pin the lean package file-set after any ProofForgeV2 source
# change (the manifest is a committed TST-SBOM-002 input).
sbom-package-files-refresh:
    /usr/bin/python3 -I -S scripts/sbom_package_files_refresh.py

# TASK-D0-08 pre-freeze primitives only. This protects PF-JCS,
# ToolLockV2Digest, direct leaf ownership, logical component identities, and
# single-pass compiler runtime discovery, and observation-to-tree binding;
# it is not the formal TST-SBOM-002 RED or task-completion gate.
supply-chain-core:
    /usr/bin/python3 -I -S -B scripts/supply_chain_core_self_test.py
    /usr/bin/python3 -I -S -B scripts/compiler_runtime_closure_self_test.py
    /usr/bin/python3 -I -S -B scripts/compiler_runtime_graph_self_test.py
    /usr/bin/python3 -I -S -B scripts/compiler_runtime_discovery_self_test.py
    /usr/bin/python3 -I -S -B scripts/compiler_runtime_observation_self_test.py
    /usr/bin/python3 -I -S -B scripts/compiler_runtime_manifest_self_test.py

# Development-only Unicode regeneration/conformance check. The caller must
# explicitly provide the digest-matched UCD directory until offline asset
# materialization is governed by its owning task.
unicode-data-self-test:
    test -n "${PROOF_FORGE_UNICODE_INPUT:-}"
    /usr/bin/python3 -I -S scripts/unicode_data_self_test.py

toolchains-validate:
    /usr/bin/python3 -I -S scripts/toolchain_assets.py validate
    /usr/bin/python3 -I -S scripts/toolchain_assets.py self-test
    /usr/bin/python3 -I -S scripts/host_profiles_self_test.py

# Convenience wrappers only. Formal evidence must invoke the displayed env -i
# command directly because `just` itself starts an inherited recipe shell.
host-stage0-development:
    /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --allow-ineligible-development

host-stage0-formal:
    /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --require-eligible

host-stage0-negative:
    #!/bin/bash
    set -euo pipefail
    case "$(uname -s)" in
      Darwin)
        tmp="$PWD/build/host-stage0-negative"
        rm -rf "$tmp"
        mkdir -p "$tmp/copied/scripts"
        cp host-bootstrap.lock host-profiles.lock.json toolchains.lock.json "$tmp/copied/"
        cp scripts/verify_host_stage0.sh scripts/toolchain_assets.py "$tmp/copied/scripts/"
        printf '\n' >> "$tmp/copied/host-profiles.lock.json"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc "$tmp/copied/scripts/verify_host_stage0.sh" --allow-ineligible-development > "$tmp/lock.log" 2>&1; then
          echo "mutated host lock unexpectedly passed Stage-0" >&2
          exit 1
        fi
        rg -q 'HOST_LOCK digest mismatch' "$tmp/lock.log"
        cp host-bootstrap.lock "$tmp/copied/host-bootstrap.lock"
        printf 'TRAILING=forbidden\n' >> "$tmp/copied/host-bootstrap.lock"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc "$tmp/copied/scripts/verify_host_stage0.sh" --allow-ineligible-development > "$tmp/record.log" 2>&1; then
          echo "bootstrap record with trailing data unexpectedly passed Stage-0" >&2
          exit 1
        fi
        rg -q 'bootstrap record contains trailing data' "$tmp/record.log"
        marker="$tmp/bash-env-executed"
        printf 'printf marker > %q\nexit 97\n' "$marker" > "$tmp/malicious-bash-env"
        BASH_ENV="$tmp/malicious-bash-env" /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --allow-ineligible-development > "$tmp/development.log" 2>&1
        test ! -e "$marker"
        rg -q '"eligibleForHermetic":false' "$tmp/development.log"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --require-eligible > "$tmp/formal.log" 2>&1; then
          echo "current ineligible host unexpectedly passed formal Stage-0" >&2
          exit 1
        fi
        rg -q 'PF-HOST-INELIGIBLE' "$tmp/formal.log"
        ;;
      Linux)
        tmp="$PWD/build/host-stage0-negative"
        rm -rf "$tmp"
        mkdir -p "$tmp/copied/scripts"
        cp host-bootstrap-linux.lock host-profiles.lock.json "toolchains-linux-$(uname -m).lock.json" "$tmp/copied/"
        cp scripts/verify_host_stage0.sh scripts/toolchain_assets.py "$tmp/copied/scripts/"
        printf '\n' >> "$tmp/copied/host-profiles.lock.json"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc "$tmp/copied/scripts/verify_host_stage0.sh" --allow-ineligible-development > "$tmp/lock.log" 2>&1; then
          echo "mutated host lock unexpectedly passed Stage-0" >&2
          exit 1
        fi
        rg -q 'HOST_LOCK digest mismatch' "$tmp/lock.log"
        cp host-bootstrap-linux.lock "$tmp/copied/host-bootstrap-linux.lock"
        printf 'TRAILING=forbidden\n' >> "$tmp/copied/host-bootstrap-linux.lock"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc "$tmp/copied/scripts/verify_host_stage0.sh" --allow-ineligible-development > "$tmp/record.log" 2>&1; then
          echo "bootstrap record with trailing data unexpectedly passed Stage-0" >&2
          exit 1
        fi
        rg -q 'bootstrap record contains trailing data' "$tmp/record.log"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC LD_PRELOAD=/tmp/proof-forge-stage0-injected.so /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --allow-ineligible-development > "$tmp/ld-preload.log" 2>&1; then
          echo "LD_PRELOAD-injected environment unexpectedly passed Stage-0" >&2
          exit 1
        fi
        rg -q 'ELF loader environment is not empty' "$tmp/ld-preload.log"
        # Formal-eligibility negative that holds on eligible and ineligible hosts
        # alike: tamper the registered profile to ineligible (flag + reason only,
        # so the live observation still matches), re-pin the copied bootstrap
        # record to the tampered host lock, and require-eligible must fail closed.
        mkdir -p "$tmp/ineligible/scripts"
        cp "toolchains-linux-$(uname -m).lock.json" "$tmp/ineligible/"
        cp scripts/verify_host_stage0.sh scripts/toolchain_assets.py "$tmp/ineligible/scripts/"
        /usr/bin/python3 -c 'import json, sys; lock = json.load(open(sys.argv[1])); [profile.update(eligibleForHermetic=False, ineligibilityReason="host-stage0-negative tamper: forced ineligible") for profile in lock["profiles"] if "distroTools" in profile]; json.dump(lock, open(sys.argv[2], "w"), indent=2)' host-profiles.lock.json "$tmp/ineligible/host-profiles.lock.json"
        tampered_sha="$(/usr/bin/sha256sum "$tmp/ineligible/host-profiles.lock.json" | /usr/bin/cut -d' ' -f1)"
        sed "s/^HOST_LOCK_SHA256=.*/HOST_LOCK_SHA256=$tampered_sha/" host-bootstrap-linux.lock > "$tmp/ineligible/host-bootstrap-linux.lock"
        if /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc "$tmp/ineligible/scripts/verify_host_stage0.sh" --require-eligible > "$tmp/formal.log" 2>&1; then
          echo "tampered ineligible profile unexpectedly passed formal Stage-0" >&2
          exit 1
        fi
        rg -q 'PF-HOST-INELIGIBLE' "$tmp/formal.log"
        ;;
      *)
        echo "unsupported host platform" >&2
        exit 1
        ;;
    esac

candidate-binding:
    #!/bin/bash
    set -euo pipefail
    tmp="$PWD/build/candidate-binding"
    /bin/rm -rf "$tmp"
    /bin/mkdir -p "$tmp/extracted"
    git_bin={{locked_git}}
    export GIT_NO_REPLACE_OBJECTS=1 GIT_OPTIONAL_LOCKS=0
    repo_root="$("$git_bin" --no-replace-objects rev-parse --show-toplevel)"
    commit="$("$git_bin" --no-replace-objects rev-parse --verify 'HEAD^{commit}')"
    tree="$("$git_bin" --no-replace-objects rev-parse --verify "$commit^{tree}")"
    # Product archive = repository root minus archived legacy tree active/
    archive_paths=()
    while IFS= read -r name; do
      [[ -n "$name" ]] || continue
      [[ "$name" == "active" ]] && continue
      archive_paths+=("$name")
    done < <("$git_bin" --no-replace-objects ls-tree --name-only "$commit")
    test "${#archive_paths[@]}" -gt 0
    "$git_bin" --no-replace-objects -C "$repo_root" archive --format=tar "$commit" -- "${archive_paths[@]}" > "$tmp/a.tar"
    /bin/sleep 2
    "$git_bin" --no-replace-objects -C "$repo_root" archive --format=tar "$commit" -- "${archive_paths[@]}" > "$tmp/b.tar"
    /usr/bin/cmp "$tmp/a.tar" "$tmp/b.tar"
    test "$("$git_bin" get-tar-commit-id < "$tmp/a.tar")" = "$commit"
    test -n "$tree"
    /usr/bin/tar -C "$tmp/extracted" -xf "$tmp/a.tar"
    test -f "$tmp/extracted/scripts/verify_isolation.sh"
    test ! -e "$tmp/extracted/active"
    if /bin/bash scripts/verify_isolation.sh --development --candidate-commit bad --candidate-tree 0000000000000000000000000000000000000000 --candidate-archive-sha256 0000000000000000000000000000000000000000000000000000000000000000 > "$tmp/commit.log" 2>&1; then
      echo "malformed candidate commit unexpectedly passed" >&2
      exit 1
    fi
    rg -q 'candidate-commit must be a full lowercase SHA-1 object id' "$tmp/commit.log"
    if /bin/bash scripts/verify_isolation.sh --development --candidate-commit 0000000000000000000000000000000000000000 --candidate-tree bad --candidate-archive-sha256 0000000000000000000000000000000000000000000000000000000000000000 > "$tmp/tree.log" 2>&1; then
      echo "malformed candidate tree unexpectedly passed" >&2
      exit 1
    fi
    rg -q 'candidate-tree must be a full lowercase SHA-1 object id' "$tmp/tree.log"
    if /bin/bash scripts/verify_isolation.sh --development --candidate-commit 0000000000000000000000000000000000000000 --candidate-tree 0000000000000000000000000000000000000000 --candidate-archive-sha256 bad > "$tmp/archive.log" 2>&1; then
      echo "malformed candidate archive digest unexpectedly passed" >&2
      exit 1
    fi
    rg -q 'candidate-archive-sha256 must be a lowercase SHA-256' "$tmp/archive.log"

evidence-core:
    #!/bin/bash
    set -euo pipefail
    tmp="$PWD/build/evidence-core"
    xcode_python={{locked_python}}
    /bin/rm -rf "$tmp"
    /bin/mkdir -p "$tmp"
    test -x "$xcode_python"
    "$xcode_python" -O -I -S scripts/gate_evidence.py self-test
    "$xcode_python" -I -S -m py_compile scripts/gate_evidence.py
    if "$xcode_python" -S scripts/gate_evidence.py self-test > "$tmp/nonisolated.stdout" 2> "$tmp/nonisolated.stderr"; then
      echo "gate evidence unexpectedly accepted a site-enabled interpreter" >&2
      exit 1
    fi
    rg -q 'PF-EVIDENCE-PYTHON-MODE' "$tmp/nonisolated.stderr"

evidence-finalization:
    #!/bin/bash
    set -euo pipefail
    xcode_python={{locked_python}}
    test -x "$xcode_python"
    "$xcode_python" -I -S -m py_compile scripts/gate_evidence_finalization_self_test.py
    "$xcode_python" -I -S scripts/gate_evidence_finalization_self_test.py

sandbox-policy:
    #!/bin/bash
    set -euo pipefail
    tmp="$PWD/build/sandbox-policy"
    xcode_python={{locked_python}}
    /bin/rm -rf "$tmp"
    /bin/mkdir -p "$tmp"
    test -x "$xcode_python"
    "$xcode_python" -O -I -S scripts/sandbox_policy.py self-test
    "$xcode_python" -O -I -S scripts/sandbox_exec.py self-test
    "$xcode_python" -I -S -m py_compile scripts/sandbox_policy.py scripts/sandbox_exec.py
    if "$xcode_python" -S scripts/sandbox_policy.py self-test > "$tmp/nonisolated.stdout" 2> "$tmp/nonisolated.stderr"; then
      echo "sandbox policy renderer unexpectedly accepted a site-enabled interpreter" >&2
      exit 1
    fi
    rg -q 'PF-SANDBOX-PYTHON' "$tmp/nonisolated.stderr"
    if "$xcode_python" -S scripts/sandbox_exec.py self-test > "$tmp/launcher-nonisolated.stdout" 2> "$tmp/launcher-nonisolated.stderr"; then
      echo "sandbox launcher unexpectedly accepted a site-enabled interpreter" >&2
      exit 1
    fi
    rg -q 'PF-SANDBOX-LAUNCH-PYTHON' "$tmp/launcher-nonisolated.stderr"

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
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-closure-negative" lake env .lake/build/bin/proof-forge-next build-counter --target near -o build/v2/runtime-mismatch > build/runtime-mismatch.log 2>&1; then echo "compiler unexpectedly accepted tampered runtime dependency" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/runtime-mismatch.log
    test ! -e build/v2/runtime-mismatch

toolchains-environment-negative: build
    rm -rf build/toolchain-environment-negative build/v2/environment-negative
    lake build proof_forge_next_tests
    DYLD_IMAGE_SUFFIX=_debug lake env .lake/build/bin/proof-forge-next-tests
    cp -R "{{tool_root}}" build/toolchain-environment-negative
    dd if=/dev/zero of=build/toolchain-environment-negative/lib/libcrypto.3_debug.dylib bs=16 count=1 >/dev/null 2>&1
    if DYLD_IMAGE_SUFFIX=_debug PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-environment-negative" lake env .lake/build/bin/proof-forge-next build-counter --target near -o build/v2/environment-negative > build/toolchain-environment-negative.log 2>&1; then echo "compiler unexpectedly accepted an extra DYLD image-suffix candidate" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH.*unexpected node" build/toolchain-environment-negative.log
    test ! -e build/v2/environment-negative

toolchains-root-negative: build
    mkdir -p build
    rm -rf build/toolchain-root-world build/toolchain-root-extra build/toolchain-root-hardlink build/toolchain-root-symlink build/toolchain-root-outside build/v2/root-world-negative build/v2/root-hardlink-negative build/v2/root-symlink-negative
    cp -R "{{tool_root}}" build/toolchain-root-world
    chmod 0777 build/toolchain-root-world
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-world" > build/toolchain-root-world.log 2>&1; then echo "world-writable tool root unexpectedly verified" >&2; exit 1; fi
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-root-world" lake env .lake/build/bin/proof-forge-next build-counter --target near -o build/v2/root-world-negative > build/toolchain-root-world-compiler.log 2>&1; then echo "compiler unexpectedly accepted a world-writable tool root" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/toolchain-root-world-compiler.log
    cp -R "{{tool_root}}" build/toolchain-root-extra
    ln -s /opt/homebrew build/toolchain-root-extra/unexpected-link
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-extra" > build/toolchain-root-extra.log 2>&1; then echo "tool root with an extra symlink unexpectedly verified" >&2; exit 1; fi
    cp -R "{{tool_root}}" build/toolchain-root-hardlink
    ln build/toolchain-root-hardlink/lib/libcrypto.3.dylib build/toolchain-root-outside
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-hardlink" > build/toolchain-root-hardlink.log 2>&1; then echo "tool root containing a multiply-linked file unexpectedly verified" >&2; exit 1; fi
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-root-hardlink" lake env .lake/build/bin/proof-forge-next build-counter --target near -o build/v2/root-hardlink-negative > build/toolchain-root-hardlink-compiler.log 2>&1; then echo "compiler unexpectedly accepted a multiply-linked runtime file" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/toolchain-root-hardlink-compiler.log
    ln -s "{{tool_root}}" build/toolchain-root-symlink
    if /usr/bin/python3 -I -S scripts/toolchain_assets.py verify-external --root "$PWD/build/toolchain-root-symlink" > build/toolchain-root-symlink.log 2>&1; then echo "symlink tool root unexpectedly verified" >&2; exit 1; fi
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/toolchain-root-symlink" lake env .lake/build/bin/proof-forge-next build-counter --target near -o build/v2/root-symlink-negative > build/toolchain-root-symlink-compiler.log 2>&1; then echo "compiler unexpectedly accepted a symlink tool root" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/toolchain-root-symlink-compiler.log
    test ! -e build/v2/root-world-negative
    test ! -e build/v2/root-hardlink-negative
    test ! -e build/v2/root-symlink-negative

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

target-negative: build
    rm -rf build/v2/openvm-negative build/v2/tool-negative build/v2/tool-mismatch
    if lake env .lake/build/bin/proof-forge-next build-counter --target openvm -o build/v2/openvm-negative > build/openvm-negative.log 2>&1; then echo "research-only target unexpectedly built" >&2; exit 1; fi
    rg -q "PF-TARGET-NOT-IMPLEMENTED" build/openvm-negative.log
    if PROOF_FORGE_TOOL_ROOT=/definitely/missing lake env .lake/build/bin/proof-forge-next build-counter --target evm -o build/v2/tool-negative > build/tool-negative.log 2>&1; then echo "missing solc unexpectedly accepted" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISSING" build/tool-negative.log
    rm -rf build/tool-mismatch-root
    mkdir -p build/tool-mismatch-root
    ln -s /usr/bin/false build/tool-mismatch-root/solc
    if PROOF_FORGE_TOOL_ROOT="$PWD/build/tool-mismatch-root" lake env .lake/build/bin/proof-forge-next build-counter --target evm -o build/v2/tool-mismatch > build/tool-mismatch.log 2>&1; then echo "invalid solc unexpectedly accepted" >&2; exit 1; fi
    rg -q "PF-TOOLCHAIN-MISMATCH" build/tool-mismatch.log

target-smoke: build
    rm -rf build/v2/standalone build/v2/evm build/v2/evm-accumulator build/v2/solana build/v2/solana-accumulator build/v2/near build/v2/near-accumulator build/v2/noir build/v2/noir-accumulator
    lake env .lake/build/bin/proof-forge-next build testdata/valid/Standalone.lean --program UserStandalone.Counter --target evm -o build/v2/standalone
    lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean --program Examples.Counter --target evm -o build/v2/evm
    lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --program Examples.Accumulator --target evm -o build/v2/evm-accumulator
    lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean --program Examples.Counter --target solana -o build/v2/solana
    lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --program Examples.Accumulator --target solana -o build/v2/solana-accumulator
    DYLD_LIBRARY_PATH=/definitely/missing lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean --program Examples.Counter --target near -o build/v2/near
    DYLD_LIBRARY_PATH=/definitely/missing lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --program Examples.Accumulator --target near -o build/v2/near-accumulator
    lake env .lake/build/bin/proof-forge-next build Examples/Counter.lean --program Examples.Counter --target noir -o build/v2/noir
    lake env .lake/build/bin/proof-forge-next build Examples/Accumulator.lean --program Examples.Accumulator --target noir -o build/v2/noir-accumulator
    /usr/bin/python3 -I -S scripts/validate_artifacts.py build/v2

output-security: build
    rm -rf build/v2/atomic-output build/v2/atomic-before build/v2/atomic-new build/source-overlap
    lake env .lake/build/bin/proof-forge-next build-counter --target evm -o build/v2/atomic-output
    cp -R build/v2/atomic-output build/v2/atomic-before
    if lake env .lake/build/bin/proof-forge-next build-counter --target evm -o build/v2/atomic-output > build/atomic-output.log 2>&1; then echo "existing output unexpectedly replaced" >&2; exit 1; fi
    rg -q "PF-OUTPUT-COLLISION" build/atomic-output.log
    diff -ru build/v2/atomic-before build/v2/atomic-output
    if PROOF_FORGE_TOOL_ROOT=/definitely/missing lake env .lake/build/bin/proof-forge-next build-counter --target evm -o build/v2/atomic-new > build/atomic-new.log 2>&1; then echo "tool failure unexpectedly published a new directory" >&2; exit 1; fi
    test ! -e build/v2/atomic-new
    test -z "$(find build/v2 -maxdepth 1 -name '.atomic-*.staging-*' -print -quit)"
    mkdir -p build/source-overlap/src
    cp testdata/valid/Standalone.lean build/source-overlap/src/Counter.lean
    printf 'preserve-me\n' > build/source-overlap/src/important.txt
    if lake env .lake/build/bin/proof-forge-next build src/Counter.lean --root build/source-overlap --program UserStandalone.Counter --target solana -o src > build/source-overlap.log 2>&1; then echo "source directory unexpectedly replaced" >&2; exit 1; fi
    rg -q "PF-OUTPUT-COLLISION" build/source-overlap.log
    cmp testdata/valid/Standalone.lean build/source-overlap/src/Counter.lean
    test "$(cat build/source-overlap/src/important.txt)" = preserve-me

evm-runtime: target-smoke
    bash scripts/smoke_evm.sh

reproducibility: build
    bash scripts/reproducibility.sh

# Portable Linux / GitHub CI subset. Explicitly excludes macOS-only hermetic
# host attestation, locked darwin tool roots, sandbox-exec, and formal clean-room
# isolation. `v2-isolation` below is only the focused D0 package-boundary gate.
v2-isolation:
    /usr/bin/python3 -I -S -B scripts/v2_isolation_self_test.py
    bash scripts/test_v2_isolation.sh

ci: v2-isolation docs-check sbom supply-chain-core build test dsl-negative target-negative

check: v2-isolation docs-check sbom python-isolation-negative toolchains-validate host-stage0-development candidate-binding evidence-core sandbox-policy toolchains-verify-external toolchains-closure-negative toolchains-environment-negative toolchains-root-negative build test test-host-isolation dsl-negative target-negative target-smoke output-security

isolated-check:
    bash scripts/verify_isolation.sh --development

v2-clean-room-alpha:
    bash scripts/verify_isolation.sh --development
