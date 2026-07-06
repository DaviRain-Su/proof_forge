#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

OUT_ROOT="${PROOF_FORGE_NEAR_HERMETIC_OUT:-build/wasm-near-hermetic}"
STUB_DIR="$OUT_ROOT/stubs"

rm -rf "$OUT_ROOT"
mkdir -p "$STUB_DIR"

for forbidden in near near-cli near-sandbox curl; do
  cat > "$STUB_DIR/$forbidden" <<'SH'
#!/usr/bin/env bash
echo "hermetic-validation-smoke: forbidden live NEAR/network invocation: $0 $*" >&2
exit 97
SH
  chmod +x "$STUB_DIR/$forbidden"
done

PATH="$STUB_DIR:$PATH" \
PROOF_FORGE_NEAR_TARGET_FIRST_OUT="$OUT_ROOT/target-first" \
  scripts/near/target-first-smoke.sh

echo "near-hermetic-validation: ok"
