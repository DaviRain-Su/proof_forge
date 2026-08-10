#!/usr/bin/env bash
# Aleo Wave-A: official tooling load gate for ProofForge-emitted Instructions.
#
# What this proves (engineering only):
#   1) proof-forge-next can materialize --target aleo for admitted programs
#   2) official Leo 4.0.x `leo abi` parses each emitted *.aleo (bytecode load)
#   3) reserved-name programs (Examples/Accumulator entry `add`) fail closed
#      at product build — they must never be emitted for official load
#
# What this does NOT prove:
#   - local VM interpret / proof / snarkOS
#   - Devnet / Testnet / Mainnet deploy or execute
#   - formal / hermetic / deployable=true
#
# Exit codes:
#   0  — load gate passed, or Leo unavailable (skip-clean with message)
#   1  — Leo present but load/build gate failed
#   2  — usage / host / product CLI missing
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

cli="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
if [[ ! -x "$cli" ]]; then
  echo "aleo-instructions-load: FAIL proof-forge-next not built ($cli)" >&2
  exit 2
fi

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

resolve_leo() {
  local plat cand
  if [[ -n "${PROOF_FORGE_ALEO_LEO:-}" && -x "${PROOF_FORGE_ALEO_LEO}" ]]; then
    echo "${PROOF_FORGE_ALEO_LEO}"
    return 0
  fi
  # Prefer Tool Lock root if a future pin lands; never invent PATH as product authority.
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
  # Host-optional research/operator path (Wave-A acceptance only; not product finalize).
  if [[ -x "${HOME}/.cargo/bin/leo" ]]; then
    echo "${HOME}/.cargo/bin/leo"
    return 0
  fi
  if command -v leo >/dev/null 2>&1; then
    command -v leo
    return 0
  fi
  return 1
}

if ! leo="$(resolve_leo)"; then
  echo "aleo-instructions-load: skipped (leo unavailable)"
  exit 0
fi

leo_ver="$("$leo" --version 2>&1 | head -1 || true)"
echo "aleo-instructions-load: using $leo ($leo_ver)"
if ! grep -q '4\.0\.' <<<"$leo_ver"; then
  echo "aleo-instructions-load: WARN expected Leo 4.0.x; continuing with host binary" >&2
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-aleo-load.XXXXXX")"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

# Isolated HOME so leo does not touch operator wallet/registry.
export HOME="$tmp/home"
mkdir -p "$HOME/.aleo"
unset PRIVATE_KEY VIEW_KEY NETWORK ENDPOINT DEVNET 2>/dev/null || true

out_root="$tmp/out"
mkdir -p "$out_root"

# --- Positive product emissions (admitted names) ---
positives=(
  "Examples/StateCell.lean:Examples.StateCell:statecell"
  "Examples/LoopSum.lean:Examples.LoopSum:loopsum"
)

loaded=0
for spec in "${positives[@]}"; do
  IFS=':' read -r src module want_id <<<"$spec"
  dest="$out_root/$want_id"
  echo "aleo-instructions-load: build $src → $dest"
  if ! "$cli" build "$src" --module "$module" --target aleo -o "$dest" >/dev/null; then
    echo "aleo-instructions-load: FAIL product build $src" >&2
    exit 1
  fi
  aleo_file="$(find "$dest" -maxdepth 1 -type f -name '*.aleo' ! -name '*.aleo-query-contract.json' | head -1)"
  if [[ -z "$aleo_file" || ! -f "$aleo_file" ]]; then
    echo "aleo-instructions-load: FAIL missing .aleo in $dest" >&2
    ls -la "$dest" >&2 || true
    exit 1
  fi
  base="$(basename "$aleo_file")"
  if [[ "$base" != "${want_id}.aleo" ]]; then
    echo "aleo-instructions-load: FAIL expected ${want_id}.aleo got $base" >&2
    exit 1
  fi
  abi_out="$tmp/${want_id}.abi.json"
  set +e
  abi_err="$("$leo" abi --disable-update-check --network testnet -o "$abi_out" "$aleo_file" 2>&1)"
  abi_code=$?
  set -e
  if [[ "$abi_code" -ne 0 ]]; then
    echo "aleo-instructions-load: FAIL leo abi on $aleo_file" >&2
    echo "$abi_err" >&2
    exit 1
  fi
  if [[ ! -s "$abi_out" ]]; then
    echo "aleo-instructions-load: FAIL empty ABI for $aleo_file" >&2
    exit 1
  fi
  if ! grep -q "\"program\": \"${want_id}.aleo\"" "$abi_out"; then
    echo "aleo-instructions-load: FAIL ABI program id mismatch for $want_id" >&2
    head -20 "$abi_out" >&2 || true
    exit 1
  fi
  echo "aleo-instructions-load: ok leo abi ← $base"
  loaded=$((loaded + 1))
done

# --- Golden fixtures that must load (non-reserved names) ---
for golden in \
  testdata/golden/aleo-instructions-v1/counter.aleo \
  testdata/golden/aleo-instructions-v1/optionstate-admit.aleo
do
  echo "aleo-instructions-load: leo abi golden $(basename "$golden")"
  set +e
  err="$("$leo" abi --disable-update-check --network testnet "$golden" 2>&1)"
  code=$?
  set -e
  if [[ "$code" -ne 0 ]]; then
    echo "aleo-instructions-load: FAIL leo abi golden $golden" >&2
    echo "$err" >&2
    exit 1
  fi
  loaded=$((loaded + 1))
done

# --- Historical reserved-name golden must NOT load (documents why product FC) ---
echo "aleo-instructions-load: expect fail leo abi on reserved-name golden accumulator.aleo"
set +e
acc_err="$("$leo" abi --disable-update-check --network testnet \
  testdata/golden/aleo-instructions-v1/accumulator.aleo 2>&1)"
acc_code=$?
set -e
if [[ "$acc_code" -eq 0 ]]; then
  echo "aleo-instructions-load: FAIL expected reserved-name golden to be rejected by leo abi" >&2
  exit 1
fi
if ! grep -qiE "reserved|add" <<<"$acc_err"; then
  echo "aleo-instructions-load: FAIL accumulator rejection should mention reserved/add" >&2
  echo "$acc_err" >&2
  exit 1
fi
echo "aleo-instructions-load: ok reserved golden rejected ($acc_code)"

# --- Product must fail closed on Examples/Accumulator (entry add) ---
acc_out="$out_root/accumulator-must-fc"
echo "aleo-instructions-load: expect product FC Examples/Accumulator"
set +e
acc_build_err="$("$cli" build Examples/Accumulator.lean \
  --module Examples.Accumulator --target aleo -o "$acc_out" 2>&1)"
acc_build_code=$?
set -e
if [[ "$acc_build_code" -eq 0 ]]; then
  echo "aleo-instructions-load: FAIL product must not emit Accumulator (reserved entry add)" >&2
  exit 1
fi
if ! grep -qiE "reserved|add|ALEO-IR" <<<"$acc_build_err"; then
  echo "aleo-instructions-load: FAIL product FC diagnostic should cite reserved/add" >&2
  echo "$acc_build_err" >&2
  exit 1
fi
if [[ -d "$acc_out" ]] && find "$acc_out" -name '*.aleo' 2>/dev/null | grep -q .; then
  echo "aleo-instructions-load: FAIL product must not leave .aleo after Accumulator FC" >&2
  exit 1
fi
echo "aleo-instructions-load: ok product FC on reserved entry add"

echo "aleo-instructions-load: ok ($loaded official loads + reserved FC)"
echo "aleo-instructions-load: non-claims = no VM/proof/devnet/testnet/mainnet/deployable"
