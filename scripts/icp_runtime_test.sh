#!/usr/bin/env bash
# ICP engineering PocketIC gate (ADR-0047 ICP-3):
#   product CLI build StateCell → wat2wasm Finalize → .wasm
#   → cargo run icp_oneshot under PocketIC server 15.0.0 (host-optional).
#
# Pin: Rust crate pocket-ic = "=15.0.0" + matching dfinity/pocketic release
# asset (e.g. pocket-ic-arm64-darwin.gz). Set POCKET_IC_BIN to the server.
#
# Not mainnet, not formal Stage-0, not ordinary `just ci`.
#
# Exit codes:
#   0 success OR skip-clean (tools/PocketIC absent)
#   1 product build / oneshot failure
#   2 hard miss (unsupported usage)
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

die() {
  echo "icp-runtime-test: FAIL: $*" >&2
  exit 1
}

skip_clean() {
  echo "icp-runtime-test: skipped: $*" >&2
  exit 0
}

missing() {
  echo "icp-runtime-test: $*" >&2
  exit 2
}

case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    skip_clean "unsupported host $(uname -s)"
    ;;
esac

export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"

command -v cargo >/dev/null 2>&1 || skip_clean "cargo not on PATH"
command -v lake >/dev/null 2>&1 || skip_clean "lake not on PATH"

cli="$root/.lake/build/bin/proof-forge-next"
if [[ ! -x "$cli" ]]; then
  echo "icp-runtime-test: building proof-forge-next…" >&2
  (cd "$root" && lake build proof_forge_next) || die "lake build proof_forge_next failed"
fi
[[ -x "$cli" ]] || die "missing $cli"

artifact_dir="${PF_ICP_ARTIFACT_DIR:-}"
cleanup_artifact=0
if [[ -z "$artifact_dir" ]]; then
  # CLI rejects pre-existing -o paths (PF-OUTPUT-COLLISION); never pre-create.
  artifact_dir="$(mktemp -u "${TMPDIR:-/tmp}/pf-icp-runtime.XXXXXX")"
  cleanup_artifact=1
  trap 'if [[ "$cleanup_artifact" -eq 1 ]]; then rm -rf "$artifact_dir"; fi' EXIT
  echo "icp-runtime-test: building StateCell → $artifact_dir" >&2
  "$cli" build Examples/StateCell.lean \
    --module Examples.StateCell \
    --target icp \
    -o "$artifact_dir" || die "product build --target icp failed"
fi

[[ -f "$artifact_dir/StateCell.wasm" ]] || die "missing StateCell.wasm under $artifact_dir"
[[ -f "$artifact_dir/StateCell.did" ]] || die "missing StateCell.did under $artifact_dir"
[[ -f "$artifact_dir/manifest.json" ]] || die "missing manifest.json under $artifact_dir"

echo "icp-runtime-test: artifact=$artifact_dir" >&2
echo "icp-runtime-test: honesty — not formal/mainnet; PocketIC host-optional" >&2

if [[ -z "${POCKET_IC_BIN:-}" ]]; then
  # Common local cache locations; do not invent a download in-product.
  for cand in \
    "$PROOF_FORGE_TOOL_ROOT/bin/pocket-ic" \
    "$HOME/.cache/pocket-ic/pocket-ic" \
    "$HOME/.local/bin/pocket-ic"
  do
    if [[ -x "$cand" ]]; then
      export POCKET_IC_BIN="$cand"
      break
    fi
  done
fi

if [[ -z "${POCKET_IC_BIN:-}" ]]; then
  skip_clean "POCKET_IC_BIN unset and no pocket-ic binary found (install server; re-run)"
fi
[[ -x "$POCKET_IC_BIN" ]] || skip_clean "POCKET_IC_BIN not executable: $POCKET_IC_BIN"

echo "icp-runtime-test: POCKET_IC_BIN=$POCKET_IC_BIN" >&2

export PF_ICP_ARTIFACT_DIR="$artifact_dir"
log="$(mktemp "${TMPDIR:-/tmp}/pf-icp-runtime.XXXXXX.log")"
trap 'rm -f "$log"; if [[ "$cleanup_artifact" -eq 1 ]]; then rm -rf "$artifact_dir"; fi' EXIT

set +e
(
  cd "$root/runtime-tests/icp"
  cargo run --quiet --release --bin icp_oneshot -- "$artifact_dir"
) >"$log" 2>&1
rc=$?
set -e
cat "$log"

if [[ "$rc" -eq 0 ]]; then
  echo "icp-runtime-test: ok (PocketIC StateCell)"
  exit 0
fi
if [[ "$rc" -eq 2 ]] || grep -q "skipped:" "$log"; then
  skip_clean "icp_oneshot skipped or tools unavailable (exit $rc)"
fi
die "icp_oneshot failed (exit $rc)"
