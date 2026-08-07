#!/usr/bin/env bash
# Aleo leo-build acceptance helper (engineering only; ALEO-I3 locked-Leo path).
#
# Wraps each *.aleo (or a directory of them) into a temporary Leo 4 package
# and runs:
#   leo build --offline --disable-update-check
#
# Locked tool resolution only (matches LockedToolchainV1.candidatePath):
#   1) $PROOF_FORGE_TOOL_ROOT/leo when PROOF_FORGE_TOOL_ROOT is set
#   2) else $HOME/.cache/proof-forge-v2/tool-root/<platform>/leo
# No PATH / cargo / homebrew fallback. Missing locked tool → skip (exit 0),
# not a pass that claims compile acceptance.
#
# Host isolation: suite-owned HOME + empty .aleo; ambient Aleo secret/network
# env cleared. Exact Leo 4.0.2 version probe required once resolved.
#
# Exit codes:
#   0  — all files accepted, or locked leo unavailable (skip with message)
#   1  — locked leo present but version/sha/build failed
#   2  — usage / host error
#
# Compile-only; does not run/execute/deploy/query/synthesize.
# Not formal Stage-0 / hermetic tool-lock / snarkVM prove-deploy.
# This is the wider host-optional corpus gate; ALEO-I4 separately provides an
# opt-in product compile profile. Neither claims VM/proof/deploy maturity.
set -euo pipefail

usage() {
  echo "usage: $0 <aleo-file-or-dir>" >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
target="$1"

# Default product CodegenProfileId used by this corpus gate (not the historical
# acceptance-lane phantom). Tool Lock also binds the ALEO-I4 compile profile.
readonly ALEO_CODEGEN_PROFILE_ID="aleo-leo-4.0.2-u64-v1"
readonly LEO_EXPECTED_VERSION="4.0.2"

platform_id() {
  local sys mach
  sys="$(uname -s | tr '[:upper:]' '[:lower:]')"
  mach="$(uname -m | tr '[:upper:]' '[:lower:]')"
  echo "${sys}-${mach}"
}

repo_root() {
  # scripts/ → package root
  cd "$(dirname "$0")/.." && pwd -P
}

# Locked tool only — no cargo/homebrew/PATH fallback.
# When PROOF_FORGE_TOOL_ROOT is set, only that root is considered (no
# silent fall-through to the default cache), matching LockedToolchainV1.
resolve_locked_leo() {
  local plat cand
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" ]]; then
    cand="${PROOF_FORGE_TOOL_ROOT%/}/leo"
    if [[ -x "$cand" ]]; then
      echo "$cand"
      return 0
    fi
    return 1
  fi
  plat="$(platform_id)"
  cand="${HOME}/.cache/proof-forge-v2/tool-root/${plat}/leo"
  if [[ -x "$cand" ]]; then
    echo "$cand"
    return 0
  fi
  return 1
}

# Drop ambient Aleo secrets / network selectors so acceptance cannot inherit
# user wallet keys or explorer endpoints from the launching shell.
isolate_aleo_env() {
  unset PRIVATE_KEY \
        VIEW_KEY \
        ADDRESS \
        NETWORK \
        ENDPOINT \
        DEVNET \
        CONSENSUS_VERSION \
        CONSENSUS_VERSION_HEIGHTS \
        CONSENSUS_HEIGHTS \
        NETWORK_RETRIES \
        PRIORITY_FEE \
        FEE_RECORD \
        || true
}

# Exact executableSha256 pin from the active platform Tool Lock file.
expected_leo_sha256() {
  local root plat lock
  root="$(repo_root)"
  plat="$(platform_id)"
  case "$plat" in
    darwin-arm64) lock="$root/toolchains.lock.json" ;;
    linux-x86_64) lock="$root/toolchains-linux-x86_64.lock.json" ;;
    *)
      echo "aleo-acceptance: unsupported platform for lock pin: $plat" >&2
      return 1
      ;;
  esac
  /usr/bin/env python3 -I -S - "$lock" <<'PY'
import json, sys
lock = json.load(open(sys.argv[1], encoding="utf-8"))
for tool in lock.get("tools", []):
    if tool.get("id") == "leo":
        sha = tool.get("executableSha256")
        if not isinstance(sha, str) or len(sha) != 64:
            sys.stderr.write("aleo-acceptance: leo executableSha256 missing/invalid in lock\n")
            sys.exit(1)
        profiles = tool.get("requiredByProfiles") or []
        expected_profiles = [
            "aleo-leo-4.0.2-u64-compile-v1",
            "aleo-leo-4.0.2-u64-v1",
        ]
        if profiles != expected_profiles:
            sys.stderr.write(
                "aleo-acceptance: leo requiredByProfiles must exactly bind "
                "compile-v1 + source-v1\n"
            )
            sys.exit(1)
        if tool.get("expectedVersion") != "4.0.2" and tool.get("version") != "4.0.2":
            sys.stderr.write("aleo-acceptance: leo lock version must be 4.0.2\n")
            sys.exit(1)
        print(sha)
        sys.exit(0)
sys.stderr.write("aleo-acceptance: leo tool missing from lock\n")
sys.exit(1)
PY
}

sha256_file() {
  local path="$1"
  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
  else
    sha256sum "$path" | awk '{print $1}'
  fi
}

if ! leo="$(resolve_locked_leo)"; then
  echo "skipped: locked leo unavailable"
  # Report only the path policy actually consulted (exclusive; no dual-list).
  if [[ -n "${PROOF_FORGE_TOOL_ROOT:-}" ]]; then
    echo "  looked for: ${PROOF_FORGE_TOOL_ROOT%/}/leo"
  else
    echo "  looked for: \$HOME/.cache/proof-forge-v2/tool-root/$(platform_id)/leo"
  fi
  echo "  profile pin: ${ALEO_CODEGEN_PROFILE_ID} (no PATH/cargo/homebrew fallback)"
  exit 0
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/aleo-accept.XXXXXX")"
accept_home="$workdir/home"
mkdir -p "$accept_home/.aleo"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

# Isolate from ambient wallet/config before any leo probe.
export HOME="$accept_home"
isolate_aleo_env

echo "aleo-acceptance: using locked $leo"
echo "aleo-acceptance: profile=${ALEO_CODEGEN_PROFILE_ID}"
ver_line="$("$leo" --version 2>&1 | head -1 || true)"
echo "aleo-acceptance: version: $ver_line"
if ! grep -q "${LEO_EXPECTED_VERSION}" <<<"$ver_line"; then
  echo "FAIL: expected Leo ${LEO_EXPECTED_VERSION}, got: $ver_line" >&2
  exit 1
fi

expected_sha="$(expected_leo_sha256)" || exit 1
actual_sha="$(sha256_file "$leo")"
if [[ "$actual_sha" != "$expected_sha" ]]; then
  echo "FAIL: leo executableSha256 mismatch" >&2
  echo "  expected: $expected_sha" >&2
  echo "  actual:   $actual_sha" >&2
  exit 1
fi
echo "aleo-acceptance: sha256 ok (${actual_sha:0:16}…)"

files=()
if [[ -f "$target" ]]; then
  files=("$target")
elif [[ -d "$target" ]]; then
  while IFS= read -r -d '' f; do
    files+=("$f")
  done < <(find "$target" -type f -name '*.aleo' -print0 | sort -z)
else
  echo "aleo-acceptance: not a file or directory: $target" >&2
  exit 2
fi

if [[ ${#files[@]} -eq 0 ]]; then
  echo "aleo-acceptance: no .aleo files under $target" >&2
  exit 2
fi

failed=0
for f in "${files[@]}"; do
  echo "--- $f"
  base="$(basename "$f")"
  stem="${base%.aleo}"
  pkg="$workdir/$stem"
  rm -rf "$pkg"
  mkdir -p "$pkg/src"
  cat >"$pkg/program.json" <<EOF
{
  "program": "${stem}.aleo",
  "version": "0.1.0",
  "description": "proof-forge-next aleo acceptance",
  "license": "MIT",
  "leo": "4.0.2",
  "dependencies": null,
  "dev_dependencies": null
}
EOF
  # Consume only the product .aleo base leaf as Leo package source.
  cp "$f" "$pkg/src/main.leo"
  # HOME already suite-owned; secrets cleared; compile-only offline flags.
  if ! out="$(
    env -i \
      HOME="$accept_home" \
      LC_ALL=C \
      TZ=UTC \
      PATH="/usr/bin:/bin" \
      "$leo" build --offline --disable-update-check --path "$pkg" 2>&1
  )"; then
    echo "FAIL: leo build rejected $f" >&2
    echo "$out" >&2
    failed=1
    continue
  fi
  if ! grep -qE 'Compiled|into Aleo instructions' <<<"$out"; then
    echo "FAIL: missing leo success marker for $f" >&2
    echo "$out" >&2
    failed=1
    continue
  fi
  echo "ok: $f"
done

if [[ "$failed" -ne 0 ]]; then
  echo "aleo-acceptance: failures detected" >&2
  exit 1
fi
echo "aleo-acceptance: ok"
