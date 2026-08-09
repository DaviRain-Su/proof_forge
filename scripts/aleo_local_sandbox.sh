#!/usr/bin/env bash
# Aleo local sandbox (generic): product build → offline Leo package → optional runs.
#
# Authority: docs/targets/09b-aleo-local-sandbox.md
# Parent IR authority: docs/targets/09-aleo-instructions-lowering.md
#
# Product path for *any* ProgramV1 source when --target aleo is selected:
#   1) proof-forge-next build <source> --module <mod> --target aleo
#      (+ PROOF_FORGE_ALEO_EMIT_LEO=1 for debug Leo package staging)
#   2) discover primary {id}.aleo + {id}.leo from product OutputSet
#   3) optional --golden: pin product {id}.aleo ≡ golden Instructions bytes
#   4) stage Leo 4.0.2 package from product {id}.leo
#   5) locked leo build --offline; pin build/main.aleo ≡ product Instructions
#   6) optional --run lines: locked leo run --offline (local interpret only)
#
# Not Counter-specific. Callers pass --source / --module / --run.
#
# Maturity (must stay honest):
#   * INSTRUCTIONS-PRIMARY: product authority is Plan→Instructions .aleo
#   * LEO-OFFLINE-RUN: local interpret — NOT chain deploy, NOT snarkVM package-only
#   * deployable=false; NOT ordinary ci; NOT formal / hermetic / mainnet
#
# Exit codes:
#   0  locked leo present; build (+ optional golden) pins; runs ok (or --skip-run)
#   1  tool present but build/pin/run failed
#   2  PF-TOOLCHAIN-MISSING / unsupported host / usage
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="aleo-local-sandbox"
PROFILE_LABEL="aleo-local-sandbox-v1"
# Official Leo local-dev default; NEVER use in production. Isolated HOME only.
readonly LEO_LOCAL_DEV_PRIVATE_KEY="APrivateKey1zkp8CZNn3yeCseEtxuVPbDCwSyhGW6yZKUYKfgXmcpoGPWH"

KEEP=0
SKIP_RUN=0
SOURCE=""
MODULE=""
PROGRAM=""
PROFILE=""
ROOT_ARG=""
GOLDEN=""
OUT_OVERRIDE=""
# Each element is one leo run invocation as a single string: "name [args...]"
RUNS=()

usage() {
  cat <<'EOF'
usage: aleo_local_sandbox.sh --source PATH --module NAME [options]

  Generic product Aleo local sandbox (any ProgramV1 source):
    build → Instructions primary → Leo package → offline leo build [+ leo run]

Required:
  --source PATH          ProgramV1 .lean source (project-relative under --root)
  --module NAME          Lean module (e.g. Examples.StateCell or Hello)

Options:
  --root DIR             Product build --root (external project root; default: package)
  --program NAME         Optional --program selector for product build
  --profile ID           Optional Aleo codegen profile id
  --golden PATH          Optional: require product {id}.aleo ≡ this file (bytes)
  --run 'name args...'   Offline leo run (repeatable). Example:
                           --run 'initialize 1u64' --run 'increment 2u64'
                         With neither --run nor --skip-run: build pins only
                         (no default program-specific runs).
  --skip-run             Skip all leo run steps (build + pins only)
  --output-dir DIR       Keep product OutputSet here (default: temp under workdir)
  --keep                 Keep workdir after exit
  -h, --help             This help

Requires locked Leo 4.0.2 at:
  $PROOF_FORGE_TOOL_ROOT/leo
  or $HOME/.cache/proof-forge-v2/tool-root/<platform>/leo
Never PATH-fallback.

Exit 0 on success; 1 on pin/run failure; 2 if tool missing / bad host / usage.

Maturity: LEO-OFFLINE-RUN local interpret only; deployable=false;
          NOT snarkVM package-only; NOT chain deploy.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --source)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --source needs a value" >&2; exit 2; }
      SOURCE="$2"
      shift 2
      ;;
    --module)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --module needs a value" >&2; exit 2; }
      MODULE="$2"
      shift 2
      ;;
    --program)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --program needs a value" >&2; exit 2; }
      PROGRAM="$2"
      shift 2
      ;;
    --root)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --root needs a value" >&2; exit 2; }
      ROOT_ARG="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --profile needs a value" >&2; exit 2; }
      PROFILE="$2"
      shift 2
      ;;
    --golden)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --golden needs a value" >&2; exit 2; }
      GOLDEN="$2"
      shift 2
      ;;
    --run)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --run needs a value" >&2; exit 2; }
      RUNS+=("$2")
      shift 2
      ;;
    --output-dir|--output)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --output-dir needs a value" >&2; exit 2; }
      OUT_OVERRIDE="$2"
      shift 2
      ;;
    --keep) KEEP=1; shift ;;
    --skip-run) SKIP_RUN=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "${PREFIX}: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "$SOURCE" || -z "$MODULE" ]]; then
  echo "${PREFIX}: usage error: --source and --module are required (generic sandbox; no default program)" >&2
  usage >&2
  exit 2
fi

# Product CLI requires a project-relative source under --root (default: this package).
PROJECT_ROOT="${ROOT_ARG:-$root}"
if [[ ! -d "$PROJECT_ROOT" ]]; then
  echo "${PREFIX}: --root is not a directory: ${PROJECT_ROOT}" >&2
  exit 2
fi
PROJECT_ROOT="$(cd "$PROJECT_ROOT" && pwd)"

# Resolve SOURCE to a path that exists, then rewrite as project-relative for the CLI.
# Relative --source is interpreted under PROJECT_ROOT first; otherwise an
# external --root paired with a path that also exists in this repo could be
# accidentally rejected after resolving to the package copy.
if [[ "$SOURCE" = /* ]]; then
  if [[ -f "$SOURCE" ]]; then
    SOURCE_ABS="$(cd "$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
  else
    echo "${PREFIX}: source not found: ${SOURCE}" >&2
    exit 2
  fi
elif [[ -f "${PROJECT_ROOT}/${SOURCE}" ]]; then
  SOURCE_ABS="$(cd "${PROJECT_ROOT}/$(dirname "$SOURCE")" && pwd)/$(basename "$SOURCE")"
else
  echo "${PREFIX}: source not found under --root (${PROJECT_ROOT}): ${SOURCE}" >&2
  exit 2
fi

case "$SOURCE_ABS" in
  "${PROJECT_ROOT}"/*)
    SOURCE_REL="${SOURCE_ABS#${PROJECT_ROOT}/}"
    ;;
  *)
    echo "${PREFIX}: source must live under --root (${PROJECT_ROOT}): ${SOURCE_ABS}" >&2
    exit 2
    ;;
esac
SOURCE="$SOURCE_REL"

die() {
  echo "${PREFIX}: $*" >&2
  exit 1
}

missing() {
  echo "${PREFIX}: PF-TOOLCHAIN-MISSING: $*" >&2
  exit 2
}

platform_id() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "linux-x86_64" ;;
    Darwin-arm64) echo "darwin-arm64" ;;
    *) return 1 ;;
  esac
}

if ! plat="$(platform_id)"; then
  missing "unsupported host $(uname -s)-$(uname -m) (only linux-x86_64 and darwin-arm64)"
fi

default_tool_root="${HOME}/.cache/proof-forge-v2/tool-root/${plat}"
export PROOF_FORGE_TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
TOOL_ROOT="${PROOF_FORGE_TOOL_ROOT%/}"
LEO="${TOOL_ROOT}/leo"

echo "${PREFIX}: profile=${PROFILE_LABEL} platform=${plat}"
echo "${PREFIX}: tool_root=${TOOL_ROOT}"
echo "${PREFIX}: root=${PROJECT_ROOT}"
echo "${PREFIX}: source=${SOURCE}"
echo "${PREFIX}: module=${MODULE}"
[[ -n "$PROGRAM" ]] && echo "${PREFIX}: program=${PROGRAM}"
[[ -n "$PROFILE" ]] && echo "${PREFIX}: codegen_profile=${PROFILE}"
echo "${PREFIX}: maturity=INSTRUCTIONS-PRIMARY + LEO-DEBUG-PACKAGE + LEO-OFFLINE-RUN"
echo "${PREFIX}: maturity=NOT-PACKAGE-ONLY-SNARKVM deployable=false"

if [[ ! -x "$LEO" ]]; then
  missing "locked leo not found at ${LEO} (materialize Tool Lock leo 4.0.2; no PATH fallback)"
fi

ver_line="$("$LEO" --version 2>&1 | head -1 || true)"
echo "${PREFIX}: leo=${LEO}"
echo "${PREFIX}: leo_version=${ver_line}"
if ! grep -q '4\.0\.2' <<<"$ver_line"; then
  die "expected Leo 4.0.2, got: ${ver_line}"
fi

# Prefer installed/dist CLI, then monorepo lake build.
if [[ -n "${PROOF_FORGE_CLI:-}" && -x "${PROOF_FORGE_CLI}" ]]; then
  PF_BIN="${PROOF_FORGE_CLI}"
elif [[ -x "${root}/bin/proof-forge-next" ]]; then
  PF_BIN="${root}/bin/proof-forge-next"
elif [[ -x "${root}/.lake/build/bin/proof-forge-next" ]]; then
  PF_BIN="${root}/.lake/build/bin/proof-forge-next"
else
  die "missing product CLI (set PROOF_FORGE_CLI, or install as <root>/bin/proof-forge-next, or lake build proof_forge_next)"
fi

if [[ -n "$GOLDEN" && ! -f "$GOLDEN" ]]; then
  if [[ -f "${root}/${GOLDEN}" ]]; then
    GOLDEN="${root}/${GOLDEN}"
  else
    die "missing golden ${GOLDEN}"
  fi
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/aleo-local-sandbox.XXXXXX")"
cleanup() {
  if [[ "$KEEP" -eq 1 ]]; then
    echo "${PREFIX}: --keep workdir=${WORKDIR}"
  else
    rm -rf "$WORKDIR"
  fi
}
trap cleanup EXIT

# Product CLI uses real HOME (elan/lake). Leo steps use isolated HOME only.
if [[ -n "$OUT_OVERRIDE" ]]; then
  OUT="$OUT_OVERRIDE"
  if [[ -e "$OUT" ]]; then
    die "output-dir must not already exist (product publisher fail-closed): ${OUT}"
  fi
else
  OUT="${WORKDIR}/product-out"
fi
PKG="${WORKDIR}/leo-pkg"
LEO_HOME="${WORKDIR}/leo-home"
REAL_HOME="${HOME}"
mkdir -p "$PKG/src" "$LEO_HOME/.aleo"

isolate_leo_env() {
  export HOME="$LEO_HOME"
  unset PRIVATE_KEY VIEW_KEY ADDRESS NETWORK ENDPOINT DEVNET \
        CONSENSUS_VERSION CONSENSUS_VERSION_HEIGHTS CONSENSUS_HEIGHTS \
        NETWORK_RETRIES PRIORITY_FEE FEE_RECORD \
        || true
}

restore_home() {
  export HOME="$REAL_HOME"
}

echo "${PREFIX}: --- product build (Instructions primary + Leo debug) ---"
# Do not pre-create -o dir: product publisher fails closed on existing path.
build_argv=(build "$SOURCE" --module "$MODULE" --target aleo --root "$PROJECT_ROOT" -o "$OUT")
if [[ -n "$PROGRAM" ]]; then
  build_argv+=(--program "$PROGRAM")
fi
if [[ -n "$PROFILE" ]]; then
  build_argv+=(--profile "$PROFILE")
fi

set +e
build_out="$(
  restore_home
  # Always invoke the product CLI from the proof-forge package (lake env / binary);
  # --root selects the author's project tree for source resolution.
  PROOF_FORGE_ALEO_EMIT_LEO=1 \
    "$PF_BIN" "${build_argv[@]}" 2>&1
)"
build_rc=$?
set -e
if [[ "$build_rc" -ne 0 ]]; then
  echo "$build_out" >&2
  die "product build failed (exit ${build_rc})"
fi
echo "$build_out" | tail -8

[[ -f "${OUT}/manifest.json" ]] || die "missing product artifact manifest.json"

# Discover primary program id from OutputSet: exactly one base *.aleo that is not
# the query-contract sidecar; require matching {id}.leo for LEO-DEBUG-PACKAGE path.
mapfile -t ALEO_BASES < <(
  find "$OUT" -maxdepth 1 -type f -name '*.aleo' ! -name '*.aleo-query-contract.json' \
    | LC_ALL=C sort
)
if [[ "${#ALEO_BASES[@]}" -ne 1 ]]; then
  die "expected exactly one primary *.aleo under ${OUT}, found ${#ALEO_BASES[@]}"
fi
PRIMARY_ALEO="${ALEO_BASES[0]}"
PROGRAM_ID="$(basename "$PRIMARY_ALEO" .aleo)"
PRIMARY_LEO="${OUT}/${PROGRAM_ID}.leo"
QUERY_JSON="${OUT}/${PROGRAM_ID}.aleo-query-contract.json"

[[ -f "$PRIMARY_LEO" ]] || die "missing Leo debug package source ${PRIMARY_LEO} (sandbox requires PROOF_FORGE_ALEO_EMIT_LEO=1 dual-write)"
[[ -f "$QUERY_JSON" ]] || die "missing query-contract ${QUERY_JSON}"

echo "${PREFIX}: program_id=${PROGRAM_ID}"
echo "${PREFIX}: primary_aleo=${PRIMARY_ALEO}"
echo "${PREFIX}: product artifacts ok under ${OUT}"

if [[ -n "$GOLDEN" ]]; then
  if ! cmp -s "$PRIMARY_ALEO" "$GOLDEN"; then
    die "product ${PROGRAM_ID}.aleo !== golden ${GOLDEN}"
  fi
  echo "${PREFIX}: pin ok: product ${PROGRAM_ID}.aleo ≡ golden Instructions"
else
  echo "${PREFIX}: golden pin skipped (no --golden; generic path)"
fi

# Leo program.json requires program name with .aleo suffix matching package id.
cat >"$PKG/program.json" <<EOF
{
  "program": "${PROGRAM_ID}.aleo",
  "version": "0.1.0",
  "description": "proof-forge-next aleo local sandbox (generic)",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
EOF
cp "$PRIMARY_LEO" "$PKG/src/main.leo"
echo "${PREFIX}: staged Leo package from product ${PROGRAM_ID}.leo (LEO-DEBUG-PACKAGE)"

echo "${PREFIX}: --- leo build --offline ---"
isolate_leo_env
set +e
bout="$("$LEO" build --offline --disable-update-check --path "$PKG" 2>&1)"
brc=$?
set -e
restore_home
if [[ "$brc" -ne 0 ]]; then
  echo "$bout" >&2
  die "leo build failed (exit ${brc})"
fi
if ! grep -qE 'Compiled|into Aleo instructions' <<<"$bout"; then
  echo "$bout" >&2
  die "leo build missing success marker"
fi
[[ -f "$PKG/build/main.aleo" ]] || die "leo build missing build/main.aleo"
if ! cmp -s "$PRIMARY_ALEO" "$PKG/build/main.aleo"; then
  die "leo build/main.aleo !== product ${PROGRAM_ID}.aleo (Instructions pin broken)"
fi
echo "${PREFIX}: pin ok: leo build/main.aleo ≡ product Instructions"

if [[ "$SKIP_RUN" -eq 1 ]]; then
  echo "${PREFIX}: --skip-run: skipping leo run"
  echo "${PREFIX}: LOCAL-SANDBOX-OK (build pins only)"
  exit 0
fi

if [[ "${#RUNS[@]}" -eq 0 ]]; then
  echo "${PREFIX}: no --run steps supplied; build pins only (generic: no default entrypoints)"
  echo "${PREFIX}: LOCAL-SANDBOX-OK (build pins only)"
  exit 0
fi

run_fn() {
  local line="$1"
  # shellcheck disable=SC2206
  local -a parts=($line)
  if [[ "${#parts[@]}" -lt 1 ]]; then
    die "empty --run value"
  fi
  local name="${parts[0]}"
  local -a args=("${parts[@]:1}")
  echo "${PREFIX}: --- leo run --offline ${name} ${args[*]:-} ---"
  isolate_leo_env
  set +e
  # Explicit local-dev key so the script does not depend on ambient wallets.
  rout="$("$LEO" run --offline --disable-update-check \
    --private-key "$LEO_LOCAL_DEV_PRIVATE_KEY" \
    --path "$PKG" "$name" ${args[@]+"${args[@]}"} 2>&1)"
  rrc=$?
  set -e
  restore_home
  if [[ "$rrc" -ne 0 ]]; then
    echo "$rout" >&2
    die "leo run ${name} failed (exit ${rrc})"
  fi
  if grep -q '➡️  Output' <<<"$rout"; then
    echo "$rout" | sed -n '/➡️  Output/,$p' | head -20
  else
    echo "$rout" | tail -15
  fi
  echo "${PREFIX}: ok: leo run ${name} (LEO-OFFLINE-RUN local interpret)"
}

for r in "${RUNS[@]}"; do
  run_fn "$r"
done

echo "${PREFIX}: --- query-contract (network-state descriptor; not live query) ---"
if command -v python3 >/dev/null 2>&1; then
  QUERY_JSON="$QUERY_JSON" PREFIX="$PREFIX" python3 - <<'PY'
import json, os
p = os.environ["QUERY_JSON"]
prefix = os.environ["PREFIX"]
with open(p) as f:
    d = json.load(f)
print(f"{prefix}: schema=", d.get("schema"))
print(f"{prefix}: program=", d.get("program"))
print(f"{prefix}: executionModel=", d.get("executionModel"))
for m in d.get("mappings") or []:
    print(f"{prefix}: mapping", m.get("name"), "dsl=", m.get("dslName"), "type=", m.get("type"))
for v in d.get("views") or []:
    print(f"{prefix}: view", v.get("name"), "→", v.get("mapping"), "[", v.get("key"), "]")
PY
else
  head -c 400 "$QUERY_JSON"
  echo
fi

cat <<EOF
${PREFIX}: --- maturity restate ---
${PREFIX}: profile=${PROFILE_LABEL}
${PREFIX}: program_id=${PROGRAM_ID}
${PREFIX}: INSTRUCTIONS-PRIMARY: product ${PROGRAM_ID}.aleo ≡ leo build/main.aleo
${PREFIX}: LEO-OFFLINE-RUN: ${#RUNS[@]} run step(s); local interpret only
${PREFIX}: NOT chain deploy / NOT leo execute broadcast / NOT snarkVM package-only
${PREFIX}: deployable=false; for package-only probe use: just aleo-runtime
${PREFIX}: LOCAL-SANDBOX-OK
EOF
exit 0
