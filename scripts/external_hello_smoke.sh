#!/usr/bin/env bash
# External ProgramV1 Hello smoke: copy template → build --root → optional sandbox.
# Authority: docs/product/02-external-program-v1.md
# Host-heavy offline run only when locked leo is present; never ordinary-ci formal.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="external-hello-smoke"
TEMPLATE="$root/templates/external-aleo-hello"
PF_BIN="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
SKIP_RUN=0
KEEP=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift ;;
    --skip-run) SKIP_RUN=1; shift ;;
    --keep) KEEP=1; shift ;;
    -h|--help)
      cat <<'EOF'
usage: external_hello_smoke.sh [--skip-run] [--keep]
  Copy templates/external-aleo-hello to a temp project, product build --target aleo,
  then generic local sandbox (skip-run or full offline runs when leo present).
EOF
      exit 0
      ;;
    *)
      echo "${PREFIX}: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

die() { echo "${PREFIX}: $*" >&2; exit 1; }

[[ -d "$TEMPLATE/src" ]] || die "missing template ${TEMPLATE}"
[[ -x "$PF_BIN" ]] || die "missing CLI ${PF_BIN}; lake build proof_forge_next"

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/pf-external-hello.XXXXXX")"
cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    echo "${PREFIX}: --keep workdir=${WORKDIR}"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

PROJ="${WORKDIR}/project"
cp -a "$TEMPLATE" "$PROJ"
# Drop monorepo-relative README links noise is fine; source is what matters.
OUT="${WORKDIR}/out-aleo"

echo "${PREFIX}: project=${PROJ}"
echo "${PREFIX}: --- product build (external --root) ---"
"$PF_BIN" build src/Hello.lean \
  --module Hello \
  --target aleo \
  --root "$PROJ" \
  -o "$OUT"
[[ -f "$OUT/hello.aleo" ]] || die "missing hello.aleo"
[[ -f "$OUT/manifest.json" ]] || die "missing manifest.json"
echo "${PREFIX}: build ok → ${OUT}/hello.aleo"

echo "${PREFIX}: --- inspect ---"
"$PF_BIN" inspect --output-dir "$OUT" --json | head -c 400 || true
echo

platform_id() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "linux-x86_64" ;;
    Darwin-arm64) echo "darwin-arm64" ;;
    *) return 1 ;;
  esac
}
plat="$(platform_id || true)"
default_tool_root="${HOME}/.cache/proof-forge-v2/tool-root/${plat:-linux-x86_64}"
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
LEO="${PROOF_FORGE_TOOL_ROOT%/}/leo"

if [[ ! -x "$LEO" ]]; then
  echo "${PREFIX}: locked leo missing at ${LEO}; sandbox skip (PF-TOOLCHAIN would apply)"
  echo "${PREFIX}: EXTERNAL-HELLO-SMOKE-OK (build-only)"
  exit 0
fi

echo "${PREFIX}: --- generic sandbox --root ---"
if [[ "$SKIP_RUN" -eq 1 ]]; then
  bash "$root/scripts/aleo_local_sandbox.sh" \
    --root "$PROJ" \
    --source src/Hello.lean \
    --module Hello \
    --skip-run
else
  bash "$root/scripts/aleo_local_sandbox.sh" \
    --root "$PROJ" \
    --source src/Hello.lean \
    --module Hello \
    --run 'initialize 1u64' \
    --run 'increment 2u64'
fi

echo "${PREFIX}: EXTERNAL-HELLO-SMOKE-OK"
exit 0
