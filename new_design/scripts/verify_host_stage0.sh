#!/bin/bash
set -euo pipefail
umask 077

die() {
  printf 'PF-HOST-STAGE0: %s\n' "$*" >&2
  exit 1
}

usage() {
  printf '%s\n' \
    'usage: verify_host_stage0.sh (--allow-ineligible-development | --require-eligible)' >&2
  exit 2
}

[[ $# -eq 1 ]] || usage
case "$1" in
  --allow-ineligible-development)
    require_eligible=0
    ;;
  --require-eligible)
    require_eligible=1
    ;;
  *)
    usage
    ;;
esac

# This script is an audited Stage-0 TCB, not a self-establishing trust root.
# The authoritative invocation starts /usr/bin/env and /bin/bash outside this
# checkout so BASH_ENV, exported functions, PATH shadowing, and user startup
# files cannot run before the first check:
#
# /usr/bin/env -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC \
#   /bin/bash --noprofile --norc scripts/verify_host_stage0.sh \
#   --require-eligible
[[ "${HOME:-}" == /var/empty ]] || die 'HOME must be /var/empty; use the authoritative env -i invocation'
[[ "${PATH:-}" == /usr/bin:/bin ]] || die 'PATH must be /usr/bin:/bin; use the authoritative env -i invocation'
[[ "${LC_ALL:-}" == C ]] || die 'LC_ALL must be C; use the authoritative env -i invocation'
[[ "${TZ:-}" == UTC ]] || die 'TZ must be UTC; use the authoritative env -i invocation'
[[ -z "${BASH_ENV+x}" && -z "${ENV+x}" && -z "${CDPATH+x}" ]] ||
  die 'shell startup environment is not empty'
[[ -z "${DEVELOPER_DIR+x}" && -z "${PYTHONHOME+x}" && -z "${PYTHONPATH+x}" ]] ||
  die 'developer or Python environment is not empty'
[[ -z "${GIT_CONFIG_GLOBAL+x}" && -z "${GIT_CONFIG_SYSTEM+x}" && -z "${GIT_DIR+x}" ]] ||
  die 'Git environment is not empty'
[[ -z "${DYLD_LIBRARY_PATH+x}" && -z "${DYLD_INSERT_LIBRARIES+x}" && -z "${DYLD_FRAMEWORK_PATH+x}" ]] ||
  die 'dyld environment is not empty'

# Bash 3.2 has no timer process primitive. The audited Apple /bin/sleep and
# /bin/rm nodes therefore join env/bash/openssl/codesign in the minimal
# platform bootstrap TCB. A background process group, CPU/file ulimits, and a
# watchdog bound every command that runs before the Python verifier exists.
stage0_sleep_path=/bin/sleep
stage0_rm_path=/bin/rm
stage0_temp_prefix="/tmp/proof-forge-host-stage0.$$.$RANDOM.$RANDOM"
stage0_temp_files=()
stage0_cleanup_enabled=0
stage0_command_counter=0

cleanup_stage0() {
  if [[ "$stage0_cleanup_enabled" == 1 && ${#stage0_temp_files[@]} -gt 0 ]]; then
    "$stage0_rm_path" -f -- "${stage0_temp_files[@]}" 2>/dev/null || true
  fi
}
trap cleanup_stage0 EXIT

new_stage0_file() {
  local suffix="$1"
  local path="$stage0_temp_prefix.$suffix"
  if ! (set -o noclobber; : > "$path") 2>/dev/null; then
    die "could not create private Stage-0 temporary file: $suffix"
  fi
  [[ -f "$path" && ! -L "$path" ]] || die "invalid Stage-0 temporary file: $suffix"
  stage0_temp_files+=("$path")
  REPLY="$path"
}

bounded_capture() {
  local label="$1"
  local timeout_seconds="$2"
  shift 2
  local output_file marker_file marker_state command_pid watchdog_pid command_status
  stage0_command_counter=$((stage0_command_counter + 1))
  new_stage0_file "$stage0_command_counter.output"
  output_file="$REPLY"
  new_stage0_file "$stage0_command_counter.timeout"
  marker_file="$REPLY"
  printf 'pending' > "$marker_file"

  set -m
  (
    ulimit -t "$timeout_seconds"
    ulimit -f 128
    exec "$@"
  ) > "$output_file" 2>&1 &
  command_pid=$!
  set +m
  (
    "$stage0_sleep_path" "$timeout_seconds"
    printf 'timeout' > "$marker_file"
    kill -KILL -- "-$command_pid" 2>/dev/null || true
  ) &
  watchdog_pid=$!

  if wait "$command_pid"; then
    command_status=0
  else
    command_status=$?
  fi
  # The leader may exit after forking helpers. Reap every process that remains
  # in the isolated job-control group before the watchdog is dismissed.
  kill -KILL -- "-$command_pid" 2>/dev/null || true
  kill "$watchdog_pid" 2>/dev/null || true
  wait "$watchdog_pid" 2>/dev/null || true
  marker_state="$(<"$marker_file")"
  BOUNDED_OUTPUT="$(<"$output_file")"
  if [[ "$marker_state" == timeout ]]; then
    die "$label timed out after ${timeout_seconds}s"
  fi
  if [[ ${#BOUNDED_OUTPUT} -ge 65536 ]]; then
    die "$label output reached the 65536-byte limit"
  fi
  return "$command_status"
}

script_dir="$(cd -P -- "${BASH_SOURCE[0]%/*}" && pwd -P)"
root="$(cd -P -- "$script_dir/.." && pwd -P)"
launcher="$script_dir/${BASH_SOURCE[0]##*/}"
record="$root/host-bootstrap.lock"
host_lock="$root/host-profiles.lock.json"
tool_lock="$root/toolchains.lock.json"
verifier="$root/scripts/toolchain_assets.py"
[[ -f "$launcher" && ! -L "$launcher" ]] || die 'launcher must be a regular non-symlink file'
[[ -f "$record" && ! -L "$record" ]] || die 'host-bootstrap.lock must be a regular non-symlink file'
[[ -f "$host_lock" && ! -L "$host_lock" ]] || die 'host profile lock must be a regular non-symlink file'
[[ -f "$tool_lock" && ! -L "$tool_lock" ]] || die 'toolchain lock must be a regular non-symlink file'
[[ -f "$verifier" && ! -L "$verifier" ]] || die 'host verifier must be a regular non-symlink file'

read_field() {
  local key="$1"
  local line
  IFS= read -r line <&3 || die "host bootstrap record ended before $key"
  [[ "$line" == "$key="* ]] || die "host bootstrap record expected $key"
  REPLY="${line#*=}"
  [[ -n "$REPLY" ]] || die "host bootstrap record has an empty $key"
}

require_sha256() {
  [[ ${#1} -eq 64 && "$1" != *[!0-9a-f]* ]] || die "$2 must be a lowercase SHA-256"
}

exec 3<"$record"
read_field SCHEMA
[[ "$REPLY" == proof-forge.host-bootstrap.v1 ]] || die 'unsupported host bootstrap schema'
read_field PROFILE_ID
profile_id="$REPLY"
[[ "$profile_id" != *[!A-Za-z0-9._-]* ]] || die 'PROFILE_ID contains an invalid character'
read_field HOST_LOCK_SHA256
host_lock_sha256="$REPLY"
require_sha256 "$host_lock_sha256" HOST_LOCK_SHA256
read_field TOOL_LOCK_SHA256
tool_lock_sha256="$REPLY"
require_sha256 "$tool_lock_sha256" TOOL_LOCK_SHA256
read_field LAUNCHER_SHA256
launcher_sha256="$REPLY"
require_sha256 "$launcher_sha256" LAUNCHER_SHA256
read_field VERIFIER_SHA256
verifier_sha256="$REPLY"
require_sha256 "$verifier_sha256" VERIFIER_SHA256
read_field OPENSSL_PATH
openssl_path="$REPLY"
[[ "$openssl_path" == /usr/bin/openssl ]] || die 'OPENSSL_PATH is not the audited platform path'
read_field OPENSSL_SHA256
openssl_sha256="$REPLY"
require_sha256 "$openssl_sha256" OPENSSL_SHA256
read_field OPENSSL_KAT_INPUT
kat_input="$REPLY"
[[ "$kat_input" == abc ]] || die 'OPENSSL_KAT_INPUT is not the audited vector'
read_field OPENSSL_KAT_SHA256
kat_sha256="$REPLY"
require_sha256 "$kat_sha256" OPENSSL_KAT_SHA256
read_field ENV_PATH
env_path="$REPLY"
[[ "$env_path" == /usr/bin/env ]] || die 'ENV_PATH is not the audited platform path'
read_field ENV_SHA256
env_sha256="$REPLY"
require_sha256 "$env_sha256" ENV_SHA256
read_field BASH_PATH
bash_path="$REPLY"
[[ "$bash_path" == /bin/bash ]] || die 'BASH_PATH is not the audited platform path'
read_field BASH_SHA256
bash_sha256="$REPLY"
require_sha256 "$bash_sha256" BASH_SHA256
read_field SLEEP_PATH
sleep_path="$REPLY"
[[ "$sleep_path" == "$stage0_sleep_path" ]] || die 'SLEEP_PATH is not the audited platform path'
read_field SLEEP_SHA256
sleep_sha256="$REPLY"
require_sha256 "$sleep_sha256" SLEEP_SHA256
read_field RM_PATH
rm_path="$REPLY"
[[ "$rm_path" == "$stage0_rm_path" ]] || die 'RM_PATH is not the audited platform path'
read_field RM_SHA256
rm_sha256="$REPLY"
require_sha256 "$rm_sha256" RM_SHA256
read_field CODESIGN_PATH
codesign_path="$REPLY"
[[ "$codesign_path" == /usr/bin/codesign ]] || die 'CODESIGN_PATH is not the audited platform path'
read_field CODESIGN_SHA256
codesign_sha256="$REPLY"
require_sha256 "$codesign_sha256" CODESIGN_SHA256
read_field XCODE_APP_PATH
xcode_app_path="$REPLY"
[[ "$xcode_app_path" == /Applications/Xcode.app ]] || die 'XCODE_APP_PATH is not the audited developer bundle'
read_field PYTHON_PATH
python_path="$REPLY"
[[ "$python_path" == /Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/bin/python3.9 ]] ||
  die 'PYTHON_PATH is not the audited direct interpreter'
read_field PYTHON_SHA256
python_sha256="$REPLY"
require_sha256 "$python_sha256" PYTHON_SHA256
read_field GIT_PATH
git_path="$REPLY"
[[ "$git_path" == /Applications/Xcode.app/Contents/Developer/usr/bin/git ]] ||
  die 'GIT_PATH is not the audited direct implementation'
read_field GIT_SHA256
git_sha256="$REPLY"
require_sha256 "$git_sha256" GIT_SHA256
IFS= read -r line <&3 || die 'host bootstrap record is missing END'
[[ "$line" == END ]] || die 'host bootstrap record expected END'
if IFS= read -r line <&3; then
  die 'host bootstrap record contains trailing data'
fi
exec 3<&-

[[ -x "$openssl_path" && ! -L "$openssl_path" ]] || die 'OpenSSL bootstrap path is not an executable regular node'
new_stage0_file kat-input
kat_input_file="$REPLY"
printf '%s' "$kat_input" > "$kat_input_file"
if ! bounded_capture OPENSSL_KAT 15 "$openssl_path" dgst -sha256 -r "$kat_input_file"; then
  die 'OpenSSL bootstrap known-answer test could not run'
fi
kat_output="$BOUNDED_OUTPUT"
[[ "${kat_output%% *}" == "$kat_sha256" ]] || die 'OpenSSL bootstrap known-answer test failed'

sha256_file() {
  if ! bounded_capture OPENSSL_SHA256 15 "$openssl_path" dgst -sha256 -r "$1"; then
    die "could not hash $1"
  fi
  SHA256_OUTPUT="${BOUNDED_OUTPUT%% *}"
}

verify_digest() {
  local label="$1"
  local path="$2"
  local expected="$3"
  local actual
  sha256_file "$path"
  actual="$SHA256_OUTPUT"
  [[ "$actual" == "$expected" ]] || die "$label digest mismatch"
}

# The KAT cannot establish trust in OpenSSL by itself. These comparisons bind
# the small bootstrap closure to an externally reviewed source/release record;
# Apple SSV/AMFI remains the platform trust root and eligibility is derived by
# the live verifier below.
verify_digest OPENSSL "$openssl_path" "$openssl_sha256"
verify_digest ENV "$env_path" "$env_sha256"
verify_digest BASH "$bash_path" "$bash_sha256"
verify_digest SLEEP "$sleep_path" "$sleep_sha256"
verify_digest RM "$rm_path" "$rm_sha256"
stage0_cleanup_enabled=1
verify_digest CODESIGN "$codesign_path" "$codesign_sha256"
verify_digest LAUNCHER "$launcher" "$launcher_sha256"
verify_digest VERIFIER "$verifier" "$verifier_sha256"
verify_digest HOST_LOCK "$host_lock" "$host_lock_sha256"
verify_digest TOOL_LOCK "$tool_lock" "$tool_lock_sha256"
verify_digest PYTHON "$python_path" "$python_sha256"
verify_digest GIT "$git_path" "$git_sha256"

for platform_binary in "$openssl_path" "$env_path" "$bash_path" "$sleep_path" "$rm_path" "$codesign_path"; do
  if ! bounded_capture CODESIGN_PLATFORM 15 \
      "$codesign_path" --verify --strict "$platform_binary"; then
    die "Apple platform signature verification failed for $platform_binary"
  fi
done
if ! bounded_capture CODESIGN_XCODE 180 \
    "$codesign_path" --verify --deep --strict "$xcode_app_path"; then
  die 'Xcode deep strict signature verification failed'
fi

printf 'PF-HOST-STAGE0: bootstrap closure verified profile=%s launcher_sha256=%s host_lock_sha256=%s\n' \
  "$profile_id" "$launcher_sha256" "$host_lock_sha256" >&2

verify_args=(
  "$python_path" -I -S "$verifier"
  --lock "$tool_lock"
  --host-lock "$host_lock"
  verify-host --profile-id "$profile_id"
)
if [[ "$require_eligible" == 1 ]]; then
  verify_args+=(--require-eligible)
fi
if bounded_capture HOST_VERIFIER 300 \
    "$env_path" -i HOME=/var/empty PATH=/usr/bin:/bin LC_ALL=C TZ=UTC "${verify_args[@]}"; then
  printf '%s\n' "$BOUNDED_OUTPUT"
else
  verifier_status=$?
  if [[ "$BOUNDED_OUTPUT" != *PF-HOST-INELIGIBLE* ]]; then
    printf 'PF-HOST-STAGE0: locked host verifier failed\n' >&2
  fi
  printf '%s\n' "$BOUNDED_OUTPUT" >&2
  exit "$verifier_status"
fi
