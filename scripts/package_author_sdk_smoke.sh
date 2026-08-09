#!/usr/bin/env bash
# Smoke: package Author SDK, lake build thin lib, optional hello elab import.
# Engineering-dist only. Not formal Stage-0.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-author-sdk-smoke"
die() { echo "${PREFIX}: $*" >&2; exit 1; }

command -v lake >/dev/null 2>&1 || die "lake not on PATH (install elan/lean-toolchain)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-author-sdk-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "${PREFIX}: package into ${tmp}/dist"
/usr/bin/python3 -I -S "$root/scripts/package_author_sdk.py" --out "$tmp/dist"

ver="$(tr -d '[:space:]' <"$root/VERSION")"
stage="$tmp/dist/proof-forge-author-${ver}"
[[ -d "$stage" ]] || die "missing stage $stage"
[[ -f "$stage/ProofForgeV2.lean" ]] || die "missing thin ProofForgeV2.lean"
[[ -f "$stage/ProofForgeV2/Language/Syntax.lean" ]] || die "missing Syntax.lean"
[[ -f "$stage/ProofForgeV2/Language/ProgramElaborationV1.lean" ]] || die "missing ProgramElaborationV1.lean"

echo "${PREFIX}: lake build Author SDK lib"
(
  cd "$stage"
  lake update 2>/dev/null || true
  lake build ProofForgeV2
)

echo "${PREFIX}: consumer lake project path-require"
consumer="$tmp/consumer"
mkdir -p "$consumer/src"
cat >"$consumer/lakefile.lean" <<EOF
import Lake
open Lake DSL

package «pf-author-consumer» where
  version := v!"0.0.0"

require «proof-forge-author» from "${stage}"

lean_lib Consumer where
  roots := #[\`Consumer]
EOF
cp "$stage/lean-toolchain" "$consumer/lean-toolchain"
hello_src="$(cat <<'EOF'
import ProofForgeV2
open ProofForgeV2.Language

program Hello where
  state count : UInt64
  init(initial : UInt64) do
    count := initial
  entry increment(delta : UInt64) : UInt64 do
    count := count + delta
    return count
  view get() : UInt64 do
    return count
EOF
)"
printf '%s\n' "$hello_src" >"$consumer/Consumer.lean"
printf '%s\n' "$hello_src" >"$consumer/src/Hello.lean"

(
  cd "$consumer"
  lake update
  lake build Consumer
)

# Product CLI text path still works on the consumer source (gate import ProofForgeV2).
PF="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
if [[ -x "$PF" ]]; then
  echo "${PREFIX}: product CLI build consumer source --target quint"
  out="$tmp/out-quint"
  "$PF" build src/Hello.lean --module Hello --target quint --root "$consumer" -o "$out"
  [[ -f "$out/manifest.json" ]] || die "missing product build manifest"
else
  echo "${PREFIX}: skip product CLI build (binary missing)"
fi

echo "${PREFIX}: AUTHOR-SDK-SMOKE-OK"
exit 0
