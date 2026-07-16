set shell := ["/bin/bash", "-eu", "-o", "pipefail", "-c"]

tool_root := env_var_or_default("PROOF_FORGE_TOOL_ROOT", env_var("HOME") + "/.cache/proof-forge-v2/tool-root/darwin-arm64")

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

toolchains-validate:
    /usr/bin/python3 -I -S scripts/toolchain_assets.py validate
    /usr/bin/python3 -I -S scripts/toolchain_assets.py self-test

# Convenience wrappers only. Formal evidence must invoke the displayed env -i
# command directly because `just` itself starts an inherited recipe shell.
host-stage0-development:
    /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --allow-ineligible-development

host-stage0-formal:
    /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC /bin/bash --noprofile --norc scripts/verify_host_stage0.sh --require-eligible

host-stage0-negative:
    #!/bin/bash
    set -euo pipefail
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

candidate-binding:
    #!/bin/bash
    set -euo pipefail
    tmp="$PWD/build/candidate-binding"
    /bin/rm -rf "$tmp"
    /bin/mkdir -p "$tmp/extracted"
    git_bin=/Applications/Xcode.app/Contents/Developer/usr/bin/git
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
    xcode_python=/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9
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

sandbox-policy:
    #!/bin/bash
    set -euo pipefail
    tmp="$PWD/build/sandbox-policy"
    xcode_python=/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9
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
    rm -rf build/syntax-bounds
    /usr/bin/python3 -I -S scripts/generate_syntax_bound_fixtures.py build/syntax-bounds
    lake env lean build/syntax-bounds/namespace-at-limit.lean -o build/syntax-bounds/namespace-at-limit.olean
    lake env .lake/build/bin/proof-forge-next build namespace-at-limit.lean --root build/syntax-bounds --target solana -o cli-at-limit
    for fixture in namespace-over-limit expression-over-limit nodes-over-limit; do
        if lake env lean "build/syntax-bounds/$fixture.lean" -o "build/syntax-bounds/$fixture.olean" > "build/syntax-bounds/$fixture.lean.log" 2>&1; then echo "$fixture unexpectedly compiled through Lean command elaboration" >&2; exit 1; fi
        rg -q "PF-BOUND-001" "build/syntax-bounds/$fixture.lean.log"
        if lake env .lake/build/bin/proof-forge-next build "$fixture.lean" --root build/syntax-bounds --target solana -o "$fixture-cli" > "build/syntax-bounds/$fixture.cli.log" 2>&1; then echo "$fixture unexpectedly compiled through CLI loader" >&2; exit 1; fi
        rg -q "PF-BOUND-001" "build/syntax-bounds/$fixture.cli.log"
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
# host attestation, locked darwin tool roots, sandbox-exec, and clean-room
# archive isolation. Those remain `just check` / `just v2-clean-room-alpha`.
ci: docs-check build test dsl-negative target-negative

check: docs-check python-isolation-negative toolchains-validate host-stage0-development candidate-binding evidence-core sandbox-policy toolchains-verify-external toolchains-closure-negative toolchains-environment-negative toolchains-root-negative build test test-host-isolation dsl-negative target-negative target-smoke output-security

isolated-check:
    bash scripts/verify_isolation.sh --development

v2-clean-room-alpha:
    bash scripts/verify_isolation.sh --development
