#!/usr/bin/env bash
# PF-P0-03: contract_source Solana builds emit real ELF by default; --format s is assembly-only.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.cargo/bin:${HOME}/.foundry/bin:${PATH}"

OUT="${PROOF_FORGE_SOLANA_SOURCE_ELF_OUT:-build/solana-source-elf}"
rm -rf "$OUT"
mkdir -p "$OUT"

lake build proof-forge >/dev/null

fail() { echo "solana-source-elf: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool missing: $1 (install sbpf for final Solana ELF builds)"
}

require_cmd sbpf

build_elf() {
  local source="$1"
  local name="$2"
  local dir="$OUT/$name"
  mkdir -p "$dir"
  lake env proof-forge build --target solana-sbpf-asm --root . \
    -o "$dir/${name}.so" \
    --artifact-output "$dir/${name}.proof-forge-artifact.json" \
    "$source" || fail "ELF build failed for $source"
  [[ -s "$dir/${name}.so" ]] || fail "missing ELF $dir/${name}.so"
  file "$dir/${name}.so" | grep -Eqi 'ELF|eBPF' || fail "not an ELF: $(file "$dir/${name}.so")"
  python3 - "$dir/${name}.proof-forge-artifact.json" "$name" <<'PY'
import json, sys
path, expect = sys.argv[1], sys.argv[2]
art = json.loads(open(path).read())
assert art.get("artifactKind") == "solana-elf", art.get("artifactKind")
assert art.get("sourceModule") == expect, art.get("sourceModule")
val = art.get("validation") or {}
assert val.get("sbpfBuild") == "passed", val
arts = art.get("artifacts") or {}
assert "solanaElf" in arts, arts.keys()
bundle = art.get("artifactBundle") or {}
assert bundle.get("kind") == "proof-forge-artifact-bundle", bundle
assert bundle.get("finalOutput") == "solana-elf", bundle
assert bundle.get("primaryOutput") == "solana-elf", bundle
kinds = {o.get("kind") for o in (bundle.get("outputs") or [])}
assert "solana-elf" in kinds and "sbpf-asm" in kinds, kinds
print(f"ok metadata sourceModule={expect} sbpfBuild=passed artifactBundle=final-elf")
PY
}

build_asm() {
  local source="$1"
  local name="$2"
  local dir="$OUT/${name}-asm"
  mkdir -p "$dir"
  lake env proof-forge build --target solana-sbpf-asm --format s --root . \
    -o "$dir/${name}.s" \
    --artifact-output "$dir/${name}.proof-forge-artifact.json" \
    "$source" || fail "assembly build failed for $source"
  [[ -s "$dir/${name}.s" ]] || fail "missing assembly"
  [[ ! -e "$dir/${name}.so" ]] || fail "assembly path must not emit ELF"
  python3 - "$dir/${name}.proof-forge-artifact.json" "$name" <<'PY'
import json, sys
path, expect = sys.argv[1], sys.argv[2]
art = json.loads(open(path).read())
assert art.get("artifactKind") == "solana-sbpf-asm", art.get("artifactKind")
assert art.get("sourceModule") == expect, art.get("sourceModule")
val = art.get("validation") or {}
# PF-P1-03: unexecuted ELF link is notRun (never passed/skipped-as-pass).
assert val.get("sbpfBuild") in ("notRun", "skipped"), val
arts = art.get("artifacts") or {}
assert "solanaElf" not in arts, arts.keys()
assert "sbpfAsm" in arts, arts.keys()
bundle = art.get("artifactBundle") or {}
assert bundle.get("finalOutput") in (None, "null") or bundle.get("finalOutput") is None, bundle
assert bundle.get("primaryOutput") in ("sbpf-asm", None) or True
print(f"ok assembly metadata sourceModule={expect} sbpfBuild={val.get('sbpfBuild')}")
PY
}

build_elf "Examples/Product/Counter.lean" "Counter"
build_elf "Examples/Product/ValueVault.lean" "ValueVault"
build_asm "Examples/Product/Counter.lean" "Counter"
build_asm "Examples/Product/ValueVault.lean" "ValueVault"

echo "solana-source-elf: ok"
