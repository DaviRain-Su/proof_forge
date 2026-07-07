#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CONTRACTS_DIR="${CONTRACTS_DIR:-$ROOT/Examples/Evm/Contracts}"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v cast >/dev/null 2>&1; then
  echo "build-examples: cast not found. Install Foundry, then re-run this script." >&2
  echo "build-examples: https://getfoundry.sh/" >&2
  exit 127
fi

if ! command -v solc >/dev/null 2>&1; then
  echo "build-examples: solc not found. Install solc, then re-run this script." >&2
  exit 127
fi

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

mkdir -p "$OUT_DIR"

# Keep the CLI executable and importable contract modules fresh when this script
# is run directly. The examples may import stdlib modules that the executable
# does not depend on.
prebuild_targets=(proof-forge)
has_prebuild_target() {
  local target="$1"
  local existing
  for existing in "${prebuild_targets[@]}"; do
    if [[ "$existing" == "$target" ]]; then
      return 0
    fi
  done
  return 1
}

while IFS= read -r -d '' lean_file; do
  while IFS= read -r line; do
    if [[ "$line" =~ ^import[[:space:]]+((ProofForge|Examples)[A-Za-z0-9_.]*) ]]; then
      module="${BASH_REMATCH[1]}"
      if ! has_prebuild_target "$module"; then
        prebuild_targets+=("$module")
      fi
    fi
  done < "$lean_file"
done < <(find "$CONTRACTS_DIR" -name '*.lean' -print0 | sort -z)

(cd "$ROOT" && lake build "${prebuild_targets[@]}" >/dev/null)

is_contract_source() {
  local lean_file="$1"
  if grep -Eq 'contract_source |def spec : ProofForge\.Contract\.ContractSpec|def spec := ProofForge\.Contract\.Stdlib\.' "$lean_file"; then
    return 0
  fi
  return 1
}

failures=0
while IFS= read -r -d '' lean_file; do
  name="$(basename "$lean_file" .lean)"
  if ! is_contract_source "$lean_file"; then
    echo "build-examples: skipping $lean_file (not a portable contract source)" >&2
    continue
  fi
  source_kind="contract-sdk"
  fixture="$name"
  out="$OUT_DIR/$name.bin"
  yul_out="$OUT_DIR/$name.yul"
  golden="${lean_file%.lean}.golden.yul"
  metadata="$OUT_DIR/$name.proof-forge-artifact.json"
  if (
    cd "$ROOT"
    "${proof_forge[@]}" build --target evm --root . --yul-output "$yul_out" --artifact-output "$metadata" -o "$out" "$lean_file"
    if [[ ! -f "$golden" ]]; then
      echo "build-examples: missing golden Yul: $golden" >&2
      exit 1
    fi
    if ! diff -u "$golden" "$yul_out"; then
      echo "build-examples: $name differs from golden Yul: $golden" >&2
      exit 1
    fi
    python3 "$ROOT/scripts/evm/validate-artifact-metadata.py" \
      --root "$ROOT" \
      --expect-fixture "$fixture" \
      --expect-source-kind "$source_kind" \
      "$metadata"
  ); then
    :
  else
    echo "build-examples: $name failed" >&2
    failures=$((failures + 1))
  fi
done < <(find "$CONTRACTS_DIR" -name '*.lean' -print0 | sort -z)

if [[ "$failures" -ne 0 ]]; then
  echo "build-examples: $failures contract(s) failed" >&2
  exit 1
fi

echo "build-examples: wrote bytecode to $OUT_DIR"
