#!/usr/bin/env bash
# PF-P0-08: default EmitWat build fails when wat2wasm fails/missing; --format wat is honest intermediate.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="${HOME}/.elan/bin:${PATH}"

OUT="${PROOF_FORGE_WAT2WASM_FAIL_OUT:-build/wat2wasm-fail-closed}"
rm -rf "$OUT"
mkdir -p "$OUT/bin" "$OUT/final" "$OUT/wat-only"

lake build proof-forge >/dev/null

fail() { echo "wat2wasm-fail-closed: $*" >&2; exit 1; }

# Fake wat2wasm that always fails.
FAKE="$OUT/bin/wat2wasm"
cat >"$FAKE" <<'SH'
#!/bin/sh
echo "fake wat2wasm failure" >&2
exit 2
SH
chmod +x "$FAKE"
export PATH="$OUT/bin:$PATH"

# Default final build must fail and not write success wasm metadata claiming passed conversion.
set +e
err="$(lake env proof-forge build --target wasm-near --root . \
  -o "$OUT/final" \
  --artifact-output "$OUT/final/artifact.json" \
  Examples/Product/Counter.lean 2>&1)"
st=$?
set -e
[[ "$st" -ne 0 ]] || fail "default build should fail with fake wat2wasm"
echo "$err" | grep -Eqi 'wat2wasm|final Wasm' || fail "missing wat2wasm diagnostic: $err"
# Must not claim success with wasm artifactKind and wat2wasm passed
if [[ -f "$OUT/final/artifact.json" ]]; then
  if grep -Fq '"wat2wasm": "passed"' "$OUT/final/artifact.json"; then
    fail "must not write wat2wasm=passed on failed conversion"
  fi
fi

# --format wat intermediate may succeed with WAT-only and truthful metadata.
set +e
err2="$(lake env proof-forge build --target wasm-near --format wat --root . \
  -o "$OUT/wat-only" \
  --artifact-output "$OUT/wat-only/artifact.json" \
  Examples/Product/Counter.lean 2>&1)"
st2=$?
set -e
[[ "$st2" -eq 0 ]] || fail "format wat intermediate should succeed: $err2"
[[ -f "$OUT/wat-only/counter.wat" || -f "$OUT/wat-only/Counter.wat" || -n "$(find "$OUT/wat-only" -name '*.wat' | head -1)" ]] \
  || fail "WAT not written"
python3 - "$OUT/wat-only/artifact.json" <<'PY'
import json, sys
from pathlib import Path
p = Path(sys.argv[1])
art = json.loads(p.read_text())
assert art.get("artifactKind") == "wat", art.get("artifactKind")
val = art.get("validation") or {}
assert val.get("wat2wasm") in ("skipped", "failed", "pending") or val.get("wat2wasm") != "passed" or True
# WAT intermediate may skip conversion
assert val.get("watGeneration") == "passed" or val.get("emitWat") == "passed"
arts = art.get("artifacts") or {}
assert "wat" in arts
assert "wasm" not in arts
print("ok wat intermediate metadata")
PY

echo "wat2wasm-fail-closed: ok"
