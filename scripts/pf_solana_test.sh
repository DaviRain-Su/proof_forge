#!/usr/bin/env bash
# Solana local Mollusk test for `pf test -t solana` (D7b, developer-first).
#
# Default lane: **StateCell-shaped** programs (what `pf new` scaffolds).
#   Any program name (Hello, MyCounter, StateCell, …) with
#   init + increment + get and a single UInt64 state field.
#
# Specialty lane (auto): **TransferSol** CPI gold fixture when TransferSol.so
# is present — same matrix as `just solana-transfer-sol-local` Mollusk half.
#
# Inputs:
#   PF_SOLANA_ARTIFACT_DIR  — OutputSet from `pf build` (required)
#   PROOF_FORGE_ROOT        — monorepo root (auto from script)
#
# Behavior:
#   - Missing cargo / runtime-tests → skip-clean exit 0
#   - Unsupported program shape → fail closed (not silent pass)
#   - No RPC / wallet / deploy
#
# Developer UX (short):
#   pf new hello --target solana && cd hello
#   pf build
#   pf test
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
artifact_dir="${PF_SOLANA_ARTIFACT_DIR:-${1:-}}"
if [[ -z "$artifact_dir" ]]; then
  echo "pf-solana-test: usage: PF_SOLANA_ARTIFACT_DIR=<dir> $0" >&2
  echo "  developer path: pf new hello --target solana && cd hello && pf build && pf test" >&2
  exit 2
fi
if [[ ! -d "$artifact_dir" ]]; then
  echo "pf-solana-test: artifact dir missing: $artifact_dir (run \`pf build\` first)" >&2
  exit 1
fi

die() { echo "pf-solana-test: FAIL: $*" >&2; exit 1; }

artifact_dir="$(cd "$artifact_dir" && pwd)"
manifest="$artifact_dir/manifest.json"
[[ -f "$manifest" ]] || die "missing manifest.json under $artifact_dir"

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
case "$(uname -s)" in
  Darwin) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/darwin-arm64" ;;
  Linux)  default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-$(uname -m)" ;;
  *)      default_tool_root="" ;;
esac
if [[ -z "${PROOF_FORGE_TOOL_ROOT:-}" && -n "$default_tool_root" ]]; then
  export PROOF_FORGE_TOOL_ROOT="$default_tool_root"
fi
export RUST_LOG="${RUST_LOG:-error}"

# Resolve program name + lane.
py=/usr/bin/python3
[[ -x "$py" ]] || py=python3
read -r program_name lane < <("$py" -I -S -c '
import json, sys, os
from pathlib import Path
d = Path(sys.argv[1])
m = json.load(open(d / "manifest.json", encoding="utf-8"))
name = m.get("artifactProgramName") or m.get("programName") or ""
so = d / f"{name}.so" if name else None
# TransferSol specialty (CPI gold)
if (d / "TransferSol.so").is_file() and name in ("", "TransferSol"):
    print("TransferSol", "transfer-sol")
    raise SystemExit(0)
if name == "TransferSol" and so and so.is_file():
    print("TransferSol", "transfer-sol")
    raise SystemExit(0)
# Default: StateCell-shaped via idl
if not name:
    # sole *.so
    sos = sorted(d.glob("*.so"))
    if len(sos) == 1:
        name = sos[0].stem
idl_path = d / f"{name}.idl.json"
if not name or not idl_path.is_file():
    print(name or "?", "unknown")
    raise SystemExit(0)
idl = json.load(open(idl_path, encoding="utf-8"))
ix = [(i.get("name"), i.get("mode")) for i in idl.get("instructions") or []]
has_init = any(n in ("init", "initialize") and m == "initialize" for n, m in ix)
has_inc = any(n == "increment" and m == "entry" for n, m in ix)
has_get = any(n == "get" and m == "view" for n, m in ix)
schemas = idl.get("stateSchemas") or []
ok_len = bool(schemas) and schemas[0].get("exactDataLen") == 16
if has_init and has_inc and has_get and ok_len and (d / f"{name}.so").is_file():
    print(name, "state-cell-shaped")
else:
    print(name, "unsupported")
' "$artifact_dir")

run_cargo_test() {
  local test_name="$1"
  local label="$2"
  echo "pf-solana-test: lane=$label program=$program_name artifact=$artifact_dir" >&2
  set +e
  out="$(
    cargo test --manifest-path "$crate" --locked \
      --test "$test_name" -- --nocapture 2>&1
  )"
  code=$?
  set -e
  if [[ "$code" -eq 0 ]]; then
    echo "$out" | rg -e 'test result: ok' -e '^test .* \.\.\. ok' -e 'running [0-9]+ tests' \
      || echo "$out"
  else
    echo "$out"
    die "cargo test $test_name failed (exit $code)"
  fi
  echo "$out" | rg -q 'test result: ok\.' \
    || die "Mollusk test produced no 'test result: ok' marker"
}

case "$lane" in
  state-cell-shaped)
    export PROOF_FORGE_SOLANA_TEST_OUT="$artifact_dir"
    run_cargo_test state_cell_shaped_product "state-cell-shaped"
    echo "pf-solana-test: ok program=$program_name lane=state-cell-shaped artifact=$artifact_dir"
    echo "pf-solana-test: notes=local-mollusk-only;pf-new-compatible;not-formal;not-mainnet;no-rpc"
    ;;
  transfer-sol)
    export PROOF_FORGE_TRANSFER_SOL_OUT="$artifact_dir"
    run_cargo_test transfer_sol_product "transfer-sol-cpi-gold"
    echo "pf-solana-test: ok program=TransferSol lane=transfer-sol-cpi-gold artifact=$artifact_dir"
    echo "pf-solana-test: notes=local-mollusk-only;cpi-specialty;not-formal;not-mainnet;no-rpc"
    ;;
  *)
    die "unsupported Solana artifact for \`pf test\` (program='$program_name').
  Supported:
    • StateCell-shaped (pf new template): init + increment + get, UInt64 count
    • TransferSol CPI gold fixture
  Tips:
    pf new hello --target solana && cd hello && pf build && pf test
    # offline joins only (when client accepts evidence notes):
    pf verify -t solana"
    ;;
esac
