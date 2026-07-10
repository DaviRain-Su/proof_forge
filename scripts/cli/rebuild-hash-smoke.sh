#!/usr/bin/env bash
# PF-P3-03: clean rebuild either reproduces artifact hashes or fails closed.
#
# Takes one source snapshot, builds two independent ProofForge binaries with
# separate `.lake/build` trees, then compares runtime bytecode + Yul digests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

fail() { echo "rebuild-hash: $*" >&2; exit 1; }

OUT="${PROOF_FORGE_REBUILD_HASH_OUT:-build/rebuild-hash-smoke}"
rm -rf "$OUT"
mkdir -p "$OUT/snapshot" "$OUT/a" "$OUT/b"
OUT_ABS="$(cd "$OUT" && pwd)"

command -v rsync >/dev/null 2>&1 || fail "rsync is required for isolated source snapshots"
[[ -d .lake/packages ]] || fail "Lake dependencies missing; run lake update before rebuild-hash"

# Freeze one source snapshot so concurrent edits cannot make build A/B differ.
rsync -a \
  --exclude='.git/' \
  --exclude='.lake/' \
  --exclude='build/' \
  --exclude='target/' \
  "$ROOT/" "$OUT/snapshot/"

prepare_tree() {
  local tree="$1"
  mkdir -p "$tree"
  rsync -a "$OUT/snapshot/" "$tree/"
  mkdir -p "$tree/.lake"
  ln -s "$ROOT/.lake/packages" "$tree/.lake/packages"
  [[ ! -e "$tree/.lake/build" ]] || fail "isolated tree unexpectedly contains .lake/build: $tree"
}

prepare_tree "$OUT/a/src"
prepare_tree "$OUT/b/src"

build_once() {
  local label="$1"
  local src="$OUT_ABS/$label/src"
  local dest="$OUT_ABS/$label/artifacts"
  mkdir -p "$dest"
  (cd "$src" && lake build proof-forge >/dev/null)
  [[ -x "$src/.lake/build/bin/proof-forge" ]] \
    || fail "isolated compiler missing: $src/.lake/build/bin/proof-forge"
  (
    cd "$src"
    lake env proof-forge build --target evm --root "$src" \
      --yul-output "$dest/Counter.yul" \
      --artifact-output "$dest/Counter.proof-forge-artifact.json" \
      -o "$dest/Counter.bin" \
      Examples/Product/Counter.lean >/dev/null
  )
  [[ -f "$dest/Counter.bin" ]] || fail "missing $dest/Counter.bin"
  [[ -f "$dest/Counter.yul" ]] || fail "missing $dest/Counter.yul"
}

build_once a
build_once b

sha_file() {
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$1" | awk '{print $1}'
  else
    sha256sum "$1" | awk '{print $1}'
  fi
}

bin_a="$(sha_file "$OUT/a/artifacts/Counter.bin")"
bin_b="$(sha_file "$OUT/b/artifacts/Counter.bin")"
yul_a="$(sha_file "$OUT/a/artifacts/Counter.yul")"
yul_b="$(sha_file "$OUT/b/artifacts/Counter.yul")"

echo "rebuild-hash: bin_a=$bin_a"
echo "rebuild-hash: bin_b=$bin_b"
echo "rebuild-hash: yul_a=$yul_a"
echo "rebuild-hash: yul_b=$yul_b"

[[ "$bin_a" == "$bin_b" ]] || fail "Counter.bin hashes differ across clean rebuilds (nondeterminism)"
[[ "$yul_a" == "$yul_b" ]] || fail "Counter.yul hashes differ across clean rebuilds (nondeterminism)"

# Provenance: lean pin recorded (PF-P3-03).
pin="$(tr -d '[:space:]' < lean-toolchain)"
python3 - "$OUT/a/artifacts/Counter.proof-forge-artifact.json" "$pin" <<'PY'
import json, sys
art, pin = sys.argv[1], sys.argv[2]
data = json.load(open(art))
bundle = data.get("artifactBundle") or {}
source = bundle.get("source") or {}
if source.get("leanElaborated") is not True:
    raise SystemExit(f"contract source must record leanElaborated=true: {source!r}")
tools = bundle.get("toolchain") if isinstance(bundle, dict) else None
if not tools:
    tools = data.get("toolchain") or []
found = False
if isinstance(tools, list):
    for t in tools:
        if isinstance(t, dict) and t.get("tool") == "lean":
            observed = t.get("observedVersion")
            expected = pin.rsplit(":", 1)[-1]
            if expected.startswith("v"):
                expected = expected[1:]
            found = (
                t.get("declaredVersion") == pin
                and observed == expected
                and t.get("version") == observed
            )
if not found:
    raise SystemExit(f"lean pin {pin!r} missing from artifact toolchain: {tools!r}")
print(f"rebuild-hash: declared/observed Lean provenance ok ({pin})")
PY

echo "rebuild-hash: ok (EVM Counter.bin + Counter.yul reproduce; lean pin recorded)"
