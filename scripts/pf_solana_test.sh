#!/usr/bin/env bash
# Minimal Solana Mollusk local test for `pf test -t solana` (D7b).
#
# Focused fixture: Examples/TransferSol product OutputSet only.
# Spawns runtime-tests/solana --test transfer_sol_product with
# PROOF_FORGE_TRANSFER_SOL_OUT pointing at the artifact dir.
#
# Inputs:
#   PF_SOLANA_ARTIFACT_DIR  — OutputSet dir with TransferSol.so (required)
#   PROOF_FORGE_ROOT        — monorepo root (auto-detected from script)
#   PROOF_FORGE_TOOL_ROOT   — locked tool root (optional; test may need sbpf only if rebuilding)
#
# Behavior:
#   - Missing cargo / runtime-tests crate → skip-clean exit 0 (host-optional)
#   - Non-TransferSol artifact → hard fail (fail closed; no silent pass)
#   - Mollusk assertion fail → exit 1
#   - No RPC / wallet / deploy / network write
#
# Not formal / not mainnet / not full solana-runtime corpus (19 programs).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${PF_SOLANA_ARTIFACT_DIR:-${1:-}}"
if [[ -z "$artifact_dir" ]]; then
  echo "pf-solana-test: usage: PF_SOLANA_ARTIFACT_DIR=<dir> $0" >&2
  exit 2
fi
if [[ ! -d "$artifact_dir" ]]; then
  echo "pf-solana-test: artifact dir missing: $artifact_dir" >&2
  exit 1
fi

die() { echo "pf-solana-test: FAIL: $*" >&2; exit 1; }

# Resolve absolute artifact path (Mollusk test reads env as path).
artifact_dir="$(cd "$artifact_dir" && pwd)"

manifest="$artifact_dir/manifest.json"
[[ -f "$manifest" ]] || die "missing manifest.json under $artifact_dir"
[[ -f "$artifact_dir/TransferSol.so" ]] \
  || die "TransferSol.so missing under $artifact_dir (D7b gold fixture is Examples/TransferSol; other programs: use pf verify offline or extend twin)"

# Fail closed if manifest program name is not TransferSol (when field present).
if command -v python3 >/dev/null 2>&1 || [[ -x /usr/bin/python3 ]]; then
  py="${PYTHON:-}"
  if [[ -z "$py" ]]; then
    if [[ -x /usr/bin/python3 ]]; then py=/usr/bin/python3; else py=python3; fi
  fi
  prog="$("$py" -I -S -c '
import json,sys
m=json.load(open(sys.argv[1],encoding="utf-8"))
print(m.get("artifactProgramName") or m.get("programName") or "")
' "$manifest")"
  if [[ -n "$prog" && "$prog" != "TransferSol" ]]; then
    die "artifact programName='$prog' (D7b Mollusk lane is TransferSol-only; got non-gold fixture)"
  fi
fi

crate="$root/runtime-tests/solana/Cargo.toml"
if [[ ! -f "$crate" ]]; then
  echo "pf-solana-test: skipped: runtime-tests/solana crate missing (optional; not pass)" >&2
  exit 0
fi
if ! command -v cargo >/dev/null 2>&1; then
  echo "pf-solana-test: skipped: cargo not on PATH (optional; not pass)" >&2
  exit 0
fi

export PROOF_FORGE_ROOT="${PROOF_FORGE_ROOT:-$root}"
export PROOF_FORGE_TRANSFER_SOL_OUT="$artifact_dir"

# Inherit tool root defaults like other solana scripts (for any rebuild path inside test).
case "$(uname -s)" in
  Darwin)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64"
    ;;
  Linux)
    default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)"
    ;;
  *)
    default_tool_root=""
    ;;
esac
if [[ -z "${PROOF_FORGE_TOOL_ROOT:-}" && -n "$default_tool_root" ]]; then
  export PROOF_FORGE_TOOL_ROOT="$default_tool_root"
fi

echo "pf-solana-test: Mollusk transfer_sol_product artifact=$artifact_dir" >&2
# Keep cargo/mollusk chatter quieter unless operator opts in.
export RUST_LOG="${RUST_LOG:-error}"
set +e
out="$(
  cargo test --manifest-path "$crate" --locked \
    --test transfer_sol_product -- --nocapture 2>&1
)"
code=$?
set -e
# Surface summary lines; full log still available on failure.
if [[ "$code" -eq 0 ]]; then
  echo "$out" | rg -e 'test result: ok' -e '^test .* \.\.\. ok' -e 'running [0-9]+ tests' || echo "$out"
else
  echo "$out"
fi

if [[ "$code" -ne 0 ]]; then
  # First-time dependency fetch failure can look like host-optional; treat compile/link
  # of mollusk as hard when cargo is present (developer intentionally ran pf test).
  die "cargo test transfer_sol_product failed (exit $code)"
fi

echo "$out" | rg -q 'test result: ok\.' \
  || die "Mollusk test produced no 'test result: ok' marker"

echo "pf-solana-test: ok fixture=TransferSol lane=mollusk-transfer-sol-product artifact=$artifact_dir"
echo "pf-solana-test: notes=local-mollusk-only;not-formal;not-mainnet;not-full-solana-runtime-corpus;no-rpc"
