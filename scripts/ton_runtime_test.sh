#!/usr/bin/env bash
# TON engineering @ton/sandbox runtime differential (TON-3):
#   product CLI build → Counter.compiled.boc + EventFlowTon.compiled.boc
#   → npm ci → node --test under runtime-tests/ton
#
# Covers Counter init/increment/get/overflow + EventFlowTon emit/Cap revert
# + ScheduleFlow createMessage schedule shape under @ton/sandbox 0.44.0
# (local TVM emulator).
#
# Not mainnet, not formal Stage-0 / hermetic release evidence / CI-registered
# shard (main agent decides just recipe wiring).
#
# Requires:
#   - lake / Lean toolchain on PATH
#   - node + npm on PATH
#   - locked tolk under PROOF_FORGE_TOOL_ROOT (or default cache root)
#   - companion fift + fiftlib + tolk-stdlib via PROOF_FORGE_TON_TOOLS
#     (or PROOF_FORGE_FIFT / PROOF_FORGE_FIFTLIB / PROOF_FORGE_TOLK_STDLIB)
#     — companions MUST stay outside PROOF_FORGE_TOOL_ROOT (FinalizeV1)
#
# Exit codes:
#   0 success (or skip-clean when tools/node/network absent)
#   1 product / npm test failure
#   2 missing tools / usage (hard miss on unsupported host)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() {
  echo "ton-runtime-test: $*" >&2
  exit 1
}

missing() {
  echo "ton-runtime-test: $*" >&2
  exit 2
}

skip_clean() {
  echo "ton-runtime-test: skipped: $*" >&2
  exit 0
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    missing "unsupported host platform: $(uname -s)"
    ;;
esac

export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
tolk_bin="$PROOF_FORGE_TOOL_ROOT/tolk"

if [[ ! -x "$tolk_bin" ]]; then
  skip_clean "tolk not found at $tolk_bin (set PROOF_FORGE_TOOL_ROOT or run toolchains materialize for tolk)"
fi

# Companion discovery (mirrors FinalizeV1.resolveCompanion).
resolve_companion() {
  local explicit_env="$1"
  local leaf="$2"
  if [[ -n "${!explicit_env:-}" ]]; then
    if [[ -e "${!explicit_env}" ]]; then
      echo "${!explicit_env}"
      return 0
    fi
    return 1
  fi
  if [[ -n "${PROOF_FORGE_TON_TOOLS:-}" && -e "${PROOF_FORGE_TON_TOOLS%/}/$leaf" ]]; then
    echo "${PROOF_FORGE_TON_TOOLS%/}/$leaf"
    return 0
  fi
  return 1
}

if ! fift_bin="$(resolve_companion PROOF_FORGE_FIFT fift)"; then
  skip_clean "fift companion missing (set PROOF_FORGE_FIFT or PROOF_FORGE_TON_TOOLS/fift; outside tool-root)"
fi
if ! fiftlib_dir="$(resolve_companion PROOF_FORGE_FIFTLIB fiftlib)"; then
  # also accept fift-lib spelling used by some TON unpacks
  if fiftlib_dir="$(resolve_companion PROOF_FORGE_FIFTLIB fift-lib)"; then
    :
  else
    skip_clean "fiftlib companion missing (set PROOF_FORGE_FIFTLIB or PROOF_FORGE_TON_TOOLS/fiftlib)"
  fi
fi
if ! tolk_stdlib="$(resolve_companion PROOF_FORGE_TOLK_STDLIB tolk-stdlib)"; then
  skip_clean "tolk-stdlib companion missing (set PROOF_FORGE_TOLK_STDLIB or PROOF_FORGE_TON_TOOLS/tolk-stdlib)"
fi

# Re-export absolute companions for FinalizeV1.
export PROOF_FORGE_FIFT="$fift_bin"
export PROOF_FORGE_FIFTLIB="$fiftlib_dir"
export PROOF_FORGE_TOLK_STDLIB="$tolk_stdlib"

if ! command -v lake >/dev/null 2>&1; then
  skip_clean "lake not on PATH"
fi
if ! command -v node >/dev/null 2>&1; then
  skip_clean "node not on PATH"
fi
if ! command -v npm >/dev/null 2>&1; then
  skip_clean "npm not on PATH"
fi

cli="$root/.lake/build/bin/proof-forge-next"
out_dir="${PROOF_FORGE_RUNTIME_OUT:-$root/build/v2/ton-runtime}"
crate_dir="$root/runtime-tests/ton"

# Product example + local fixtures (source stem == program name == artifact stem).
programs=(
  "Examples/Counter.lean:Examples.Counter:Counter"
  "runtime-tests/ton/fixtures/EventFlowTon.lean:Examples.EventFlowTon:EventFlowTon"
  "runtime-tests/ton/fixtures/ScheduleFlow.lean:Examples.ScheduleFlow:ScheduleFlow"
)

echo "ton-runtime-test: building proof-forge-next (lake build proof_forge_next)"
# Lean exe target is `proof_forge_next`; on-disk name is `proof-forge-next`.
lake build proof_forge_next || die "lake build proof_forge_next failed"
[[ -x "$cli" ]] || die "CLI missing after build: $cli"

echo "ton-runtime-test: tool root=$PROOF_FORGE_TOOL_ROOT"
echo "ton-runtime-test: tolk=$("$tolk_bin" --version 2>&1 | head -1 || true)"
echo "ton-runtime-test: fift=$fift_bin"
echo "ton-runtime-test: fiftlib=$fiftlib_dir"
echo "ton-runtime-test: tolk-stdlib=$tolk_stdlib"
echo "ton-runtime-test: node=$(node --version 2>&1) npm=$(npm --version 2>&1)"

# CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); remove and let it create.
rm -rf "$out_dir"
mkdir -p "$out_dir"

normalize_boc() {
  local name="$1"
  local fixture_out="$2"
  local boc=""
  if [[ -f "$fixture_out/${name}.compiled.boc" ]]; then
    boc="$fixture_out/${name}.compiled.boc"
  else
    boc="$(find "$fixture_out" -name "${name}.compiled.boc" -type f 2>/dev/null | head -n 1 || true)"
  fi
  [[ -n "$boc" && -f "$boc" ]] || return 1
  if [[ "$(cd "$(dirname "$boc")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
    cp -f "$boc" "$fixture_out/${name}.compiled.boc"
  fi
  # Optional ABI sidecars normalize
  for side in ton-abi.json abi.json tolk fif; do
    local f=""
    if [[ -f "$fixture_out/${name}.${side}" ]]; then
      f="$fixture_out/${name}.${side}"
    else
      f="$(find "$fixture_out" -name "${name}.${side}" -type f 2>/dev/null | head -n 1 || true)"
    fi
    if [[ -n "$f" && -f "$f" && "$(cd "$(dirname "$f")" && pwd)" != "$(cd "$fixture_out" && pwd)" ]]; then
      cp -f "$f" "$fixture_out/${name}.${side}"
    fi
  done
  [[ -f "$fixture_out/${name}.compiled.boc" ]] || return 1
  echo "ton-runtime-test: ${name}.compiled.boc=$(wc -c <"$fixture_out/${name}.compiled.boc" | tr -d ' ') bytes"
  return 0
}

for entry in "${programs[@]}"; do
  IFS=':' read -r rel_src module name <<<"$entry"
  src="$root/$rel_src"
  [[ -f "$src" ]] || die "source missing: $src"
  fixture_out="$out_dir/$name"
  echo "ton-runtime-test: build $rel_src --module $module --target ton -o $fixture_out"
  if ! lake env "$cli" build \
    "$rel_src" \
    --module "$module" \
    --target ton \
    -o "$fixture_out"; then
    die "proof-forge-next build failed for $name"
  fi
  normalize_boc "$name" "$fixture_out" || die "${name}.compiled.boc not found under $fixture_out (need fift companions; deployable BoC)"
done

echo "ton-runtime-test: npm ci / npm test (cwd=$crate_dir)"
export PROOF_FORGE_FIXTURES_DIR="$out_dir"

if ! (
  cd "$crate_dir"
  # Prefer offline when package-lock exists and cache is warm; fall back to network.
  if [[ -f package-lock.json ]]; then
    if npm ci --offline 2>/dev/null; then
      echo "ton-runtime-test: npm ci --offline ok"
    else
      echo "ton-runtime-test: offline npm ci unavailable; npm ci with network (if needed)"
      if ! npm ci; then
        echo "ton-runtime-test: npm ci failed; trying npm install" >&2
        npm install || exit 1
      fi
    fi
  else
    echo "ton-runtime-test: no package-lock.json; npm install"
    npm install || exit 1
  fi
  npm test
); then
  # Distinguish network/tool skip vs real failure: if node_modules missing after install attempt, skip.
  if [[ ! -d "$crate_dir/node_modules/@ton/sandbox" ]]; then
    skip_clean "npm could not install @ton/sandbox (network or registry unavailable)"
  fi
  die "npm test failed (see output above)"
fi

echo "ton-runtime-test: ok (engineering sandbox differential; not mainnet/formal)"
