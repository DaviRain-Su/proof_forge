#!/usr/bin/env bash
# ALEO-R0 local Leo 4.0.2 toolchain spike (engineering research only).
#
# What this does (offline-first, locked Leo only):
#   1) Resolve locked leo (PROOF_FORGE_TOOL_ROOT or default cache path).
#   2) Isolate HOME + clear ambient Aleo secret/network env.
#   3) Build a minimal Leo 4 package (product-shaped Counter).
#   4) Run `leo build --offline --disable-update-check` twice.
#   5) Require exact three content-bearing outputs; inventory count=3;
#      compare byte-stable digests; scan those three for absolute-path strings.
#   6) Optionally probe offline-safe `leo run` (interpret only).
#   7) Report INFO-BLOCKED stages (execute/deploy/query/snarkOS) without installing.
#
# What this does NOT do:
#   - network install of snarkOS/snarkVM/SDK/CRS
#   - testnet/mainnet broadcast
#   - read secrets/wallets from ambient HOME
#   - PATH fallback for leo
#   - claim proof/runtime product maturity
#
# Exit codes:
#   0  — locked leo present; dual offline build digests identical; SPIKE-PASS
#   1  — locked leo present but build/determinism/inventory failed
#   2  — usage / internal error
#   3  — SPIKE-BLOCKED: locked leo missing (not a pass)
#
# Empirical host note: dual-build digests frozen on darwin-arm64 with locked
# leo 4.0.2; script is portable but does not claim multi-host hermeticity.
#
# Not formal Stage-0 / hermetic Tool Lock verification / CI product gate.
set -euo pipefail

# Exact content-bearing compile outputs under the package root.
# (Other files such as build/imports/* may appear after test/run; they are
# outside this determinism contract.)
readonly BUILD_OUTPUTS=(
  "build/main.aleo"
  "build/abi.json"
  "build/program.json"
)
readonly BUILD_OUTPUT_COUNT=3

usage() {
  cat >&2 <<'EOF'
usage: aleo_local_toolchain_spike.sh [--skip-run]

  Engineering spike for Leo 4.0.2 offline package/build determinism.
  Prefer locked tool at:
    $PROOF_FORGE_TOOL_ROOT/leo
    or $HOME/.cache/proof-forge-v2/tool-root/<platform>/leo
  Does not PATH-fallback (same locked-only policy as aleo_acceptance.sh).
  Missing locked tool → exit 3 SPIKE-BLOCKED (not a pass).
EOF
  exit 2
}

SKIP_RUN=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --skip-run) SKIP_RUN=1; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

# Locked tool only — no cargo/homebrew/PATH fallback for this spike.
# Uses the caller HOME / PROOF_FORGE_TOOL_ROOT before isolation.
resolve_locked_leo() {
  local plat cand
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" && -x "${PROOF_FORGE_TOOL_ROOT%/}/leo" ]]; then
    echo "${PROOF_FORGE_TOOL_ROOT%/}/leo"
    return 0
  fi
  plat="$(platform_id)"
  cand="${HOME}/.cache/proof-forge-v2/tool-root/${plat}/leo"
  if [[ -x "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  return 1
}

# Drop ambient Aleo secrets / network selectors so the probe cannot inherit
# user wallet keys or explorer endpoints from the launching shell.
isolate_aleo_env() {
  unset PRIVATE_KEY \
        VIEW_KEY \
        ADDRESS \
        NETWORK \
        ENDPOINT \
        DEVNET \
        CONSENSUS_VERSION \
        CONSENSUS_VERSION_HEIGHTS \
        CONSENSUS_HEIGHTS \
        NETWORK_RETRIES \
        PRIORITY_FEE \
        FEE_RECORD \
        || true
}

if ! LEO="$(resolve_locked_leo)"; then
  echo "SPIKE-BLOCKED: locked leo not found"
  echo "  looked for: \${PROOF_FORGE_TOOL_ROOT}/leo"
  echo "              \$HOME/.cache/proof-forge-v2/tool-root/$(platform_id)/leo"
  echo "  materialize Tool Lock leo 4.0.2 before re-running; do not PATH-fallback."
  exit 3
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/aleo-local-spike.XXXXXX")"
SPIKE_HOME="$WORKDIR/home"
mkdir -p "$SPIKE_HOME/.aleo"
cleanup() { rm -rf "$WORKDIR"; }
trap cleanup EXIT

# Isolate from ambient wallet/config; do not inherit user HOME for Leo state.
export HOME="$SPIKE_HOME"
isolate_aleo_env

echo "aleo-local-spike: leo=$LEO"
ver_line="$("$LEO" --version 2>&1 | head -1)"
echo "aleo-local-spike: version: $ver_line"
if ! grep -q '4\.0\.2' <<<"$ver_line"; then
  echo "FAIL: expected Leo 4.0.2, got: $ver_line" >&2
  exit 1
fi
leo_sha="$(shasum -a 256 "$LEO" | awk '{print $1}')"
echo "aleo-local-spike: leo_sha256=$leo_sha"
echo "aleo-local-spike: host=$(uname -s)-$(uname -m) (empirically frozen on darwin-arm64)"

PKG="$WORKDIR/counter"
mkdir -p "$PKG/src"
cat >"$PKG/program.json" <<'EOF'
{
  "program": "counter.aleo",
  "version": "0.1.0",
  "description": "aleo-r0 local toolchain spike",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
EOF

# Product-emission-shaped Final/fn surface (Leo 4.0.2; no async keyword).
cat >"$PKG/src/main.leo" <<'EOF'
// proof-forge-next ALEO-R0 spike: product-shaped Counter for Leo 4.0.2.
program counter.aleo {
    @noupgrade
    constructor() {}

    mapping pf_state_0: u8 => u64;
    mapping initialized: u8 => bool;

    fn initialize(public p0: u64) -> Final {
        return final {
            let pf_seen: bool = initialized.get_or_use(0u8, false);
            assert((!pf_seen));
            initialized.set(0u8, true);
            pf_state_0.set(0u8, p0);
        };
    }

    fn increment(public p0: u64) -> Final {
        return final {
            let cur: u64 = pf_state_0.get_or_use(0u8, 0u64);
            pf_state_0.set(0u8, cur + p0);
        };
    }

    fn get() -> u64 {
        return 0u64;
    }
}
EOF

# Fail closed unless every required content-bearing output exists.
require_build_outputs() {
  local root="$1"
  local f missing=0
  for f in "${BUILD_OUTPUTS[@]}"; do
    if [[ ! -f "$root/$f" ]]; then
      echo "FAIL: missing required build output: $f" >&2
      missing=1
    fi
  done
  if [[ "$missing" -ne 0 ]]; then
    return 1
  fi
  return 0
}

# Canonical inventory line format (space-separated fixed fields, path first):
#   <relpath> size=<N> sha256=<hex>
# Sorted LC_ALL=C. Exact BUILD_OUTPUT_COUNT lines; empty inventory fails closed.
inventory_build() {
  local root="$1" out="$2"
  local f sz sha count
  : >"$out"
  if ! require_build_outputs "$root"; then
    return 1
  fi
  (
    cd "$root"
    for f in "${BUILD_OUTPUTS[@]}"; do
      # require_build_outputs already checked; re-check for race-hardening.
      if [[ ! -f "$f" ]]; then
        echo "FAIL: inventory race-missing $f" >&2
        exit 1
      fi
      sz="$(wc -c <"$f" | tr -d ' ')"
      sha="$(shasum -a 256 "$f" | awk '{print $1}')"
      if [[ -z "$sz" || -z "$sha" ]]; then
        echo "FAIL: empty size/sha for $f" >&2
        exit 1
      fi
      printf '%s size=%s sha256=%s\n' "$f" "$sz" "$sha"
    done
  ) | LC_ALL=C sort >"$out"

  if [[ ! -s "$out" ]]; then
    echo "FAIL: empty inventory (fail closed)" >&2
    return 1
  fi
  count="$(wc -l <"$out" | tr -d ' ')"
  if [[ "$count" -ne "$BUILD_OUTPUT_COUNT" ]]; then
    echo "FAIL: inventory line count=$count expected $BUILD_OUTPUT_COUNT" >&2
    cat "$out" >&2 || true
    return 1
  fi
  # Every required path must appear exactly once as the first field.
  for f in "${BUILD_OUTPUTS[@]}"; do
    if ! awk -v want="$f" '$1 == want { found=1 } END { exit found ? 0 : 1 }' "$out"; then
      echo "FAIL: inventory missing path entry for $f" >&2
      return 1
    fi
  done
  return 0
}

# Parse canonical inventory and scan each listed artifact for absolute paths.
scan_abspath_from_inventory() {
  local root="$1" inv="$2"
  local path size_field sha_field full hit=0 lines=0
  if [[ ! -s "$inv" ]]; then
    echo "FAIL: abspath scan got empty inventory (fail closed)" >&2
    return 1
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" ]] && continue
    # Expected: "<path> size=<N> sha256=<hex>"
    path="${line%% *}"
    size_field="$(awk '{print $2}' <<<"$line")"
    sha_field="$(awk '{print $3}' <<<"$line")"
    if [[ -z "$path" || "$size_field" != size=* || "$sha_field" != sha256=* ]]; then
      echo "FAIL: malformed inventory line: $line" >&2
      return 1
    fi
    full="$root/$path"
    if [[ ! -f "$full" ]]; then
      echo "FAIL: inventory path not a file: $path" >&2
      return 1
    fi
    lines=$((lines + 1))
    if strings "$full" 2>/dev/null | grep -qE '/Users/|/private/var/|/var/folders/'; then
      echo "FAIL: absolute path string in $path" >&2
      hit=1
    fi
  done <"$inv"
  if [[ "$lines" -ne "$BUILD_OUTPUT_COUNT" ]]; then
    echo "FAIL: abspath scan line count=$lines expected $BUILD_OUTPUT_COUNT" >&2
    return 1
  fi
  if [[ "$hit" -ne 0 ]]; then
    return 1
  fi
  return 0
}

run_build() {
  local label="$1"
  echo "--- $label ---"
  isolate_aleo_env
  set +e
  out="$("$LEO" build --offline --disable-update-check --path "$PKG" 2>&1)"
  rc=$?
  set -e
  if [[ "$rc" -ne 0 ]]; then
    echo "FAIL: leo build exit $rc" >&2
    echo "$out" >&2
    return 1
  fi
  if ! grep -qE 'Compiled|into Aleo instructions' <<<"$out"; then
    echo "FAIL: missing leo success marker" >&2
    echo "$out" >&2
    return 1
  fi
  if ! require_build_outputs "$PKG"; then
    echo "FAIL: $label did not produce all required content-bearing outputs" >&2
    return 1
  fi
  echo "ok: $label (required outputs present)"
  return 0
}

if ! run_build "build-1"; then
  exit 1
fi
if ! inventory_build "$PKG" "$WORKDIR/inv1.txt"; then
  exit 1
fi
echo "inventory-1 (exact $BUILD_OUTPUT_COUNT content-bearing outputs):"
cat "$WORKDIR/inv1.txt"

if ! run_build "build-2"; then
  exit 1
fi
if ! inventory_build "$PKG" "$WORKDIR/inv2.txt"; then
  exit 1
fi
echo "inventory-2 (exact $BUILD_OUTPUT_COUNT content-bearing outputs):"
cat "$WORKDIR/inv2.txt"

if ! cmp -s "$WORKDIR/inv1.txt" "$WORKDIR/inv2.txt"; then
  echo "FAIL: dual-build inventory not byte-identical" >&2
  diff -u "$WORKDIR/inv1.txt" "$WORKDIR/inv2.txt" >&2 || true
  exit 1
fi
echo "aleo-local-spike: dual-build content digests identical (3/3)"

if ! scan_abspath_from_inventory "$PKG" "$WORKDIR/inv1.txt"; then
  exit 1
fi
echo "aleo-local-spike: no absolute-path strings in content-bearing outputs (3/3)"

if [[ "$SKIP_RUN" -eq 0 ]]; then
  echo "--- offline run initialize (interpret only) ---"
  isolate_aleo_env
  set +e
  rout="$("$LEO" run --offline --disable-update-check --path "$PKG" initialize 1u64 2>&1)"
  rrc=$?
  set -e
  if [[ "$rrc" -ne 0 ]]; then
    echo "FAIL: leo run exit $rrc" >&2
    echo "$rout" >&2
    exit 1
  fi
  echo "ok: leo run (local interpret; not a proof)"
fi

# Explicit post-compile stage limits (informational; do not fail the spike).
echo "--- offline stage limits (informational) ---"
echo "INFO-BLOCKED: leo execute/deploy — requires REST stateRoot/block even with --offline"
echo "INFO-BLOCKED: leo query — live network only"
echo "INFO-BLOCKED: snarkOS/snarkVM CLI — not in Tool Lock / materialize root"
echo "INFO-BLOCKED: leo synthesize CRS — may download parameters despite --offline (not invoked here)"
echo "INFO-BLOCKED: no top-level leo proof verify / finalize subcommand"
echo "NOTE: ALEO-I4 productizes compile-only outputs; VM/proof/deploy maturity remains blocked"
echo "SPIKE-PASS"
exit 0
