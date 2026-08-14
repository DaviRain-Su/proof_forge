#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat >&2 <<'EOF'
usage: scripts/build_wasmcert_provider_v1.sh \
  --source <clean-wasmcert-checkout> \
  --opam-root <opam-root> \
  --switch <opam-switch> \
  --output <provider-executable> \
  [--repeat-check]

Builds a non-admitted ProofForge WasmCert provider candidate from the exact
WasmCert-Coq source revision. This command does not edit Tool Lock or change
the currently admitted product executable. --repeat-check performs two
independent clean builds and publishes only when their bytes are identical.
EOF
  exit 64
}

source_dir=""
opam_root=""
opam_switch=""
output=""
repeat_check=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --source) [[ $# -ge 2 ]] || usage; source_dir="$2"; shift 2 ;;
    --opam-root) [[ $# -ge 2 ]] || usage; opam_root="$2"; shift 2 ;;
    --switch) [[ $# -ge 2 ]] || usage; opam_switch="$2"; shift 2 ;;
    --output) [[ $# -ge 2 ]] || usage; output="$2"; shift 2 ;;
    --repeat-check) repeat_check=true; shift ;;
    *) usage ;;
  esac
done

[[ -n "$source_dir" && -n "$opam_root" && -n "$opam_switch" && -n "$output" ]] || usage

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
source_dir="$(cd "$source_dir" && pwd -P)"
opam_root="$(cd "$opam_root" && pwd -P)"
output_parent="$(dirname "$output")"
mkdir -p "$output_parent"
output_parent="$(cd "$output_parent" && pwd -P)"
output="$output_parent/$(basename "$output")"

revision="9ab0f87f03fff5507749efc273ec662fe27e6d14"
upstream_dune_sha256="818a426ded089ab4e6246cea180b51dfbcf27acee297ca3ff0ceb7a21ab12c5b"
provider_source="$repo_root/tools/wasmcert-provider/proof_forge_wasmcert_provider_v1.ml"
dune_overlay="$repo_root/tools/wasmcert-provider/dune.v1"
package_lock="$repo_root/tools/wasmcert-provider/opam-packages.v1.lock"

for command in cmp git install opam python3 tar uname; do
  command -v "$command" >/dev/null 2>&1 || {
    echo "build-wasmcert-provider: missing required command: $command" >&2
    exit 2
  }
done

case "$(uname -s):$(uname -m)" in
  Linux:x86_64) platform="linux-x86_64" ;;
  Darwin:arm64) platform="darwin-arm64" ;;
  *)
    echo "build-wasmcert-provider: unsupported build platform $(uname -s)-$(uname -m)" >&2
    exit 2
    ;;
esac

sha256_file() {
  python3 -I -S - "$1" <<'PY'
import hashlib
import pathlib
import sys

digest = hashlib.sha256()
with pathlib.Path(sys.argv[1]).open("rb") as handle:
    for chunk in iter(lambda: handle.read(1024 * 1024), b""):
        digest.update(chunk)
print(digest.hexdigest())
PY
}

[[ "$(git -C "$source_dir" rev-parse HEAD)" == "$revision" ]] || {
  echo "build-wasmcert-provider: source HEAD does not match $revision" >&2
  exit 2
}
git -C "$source_dir" diff --quiet --exit-code
git -C "$source_dir" diff --cached --quiet --exit-code
[[ -z "$(git -C "$source_dir" ls-files --others --exclude-standard)" ]] || {
  echo "build-wasmcert-provider: source checkout must not contain untracked files" >&2
  exit 2
}
[[ "$(sha256_file "$source_dir/src/dune")" == "$upstream_dune_sha256" ]] || {
  echo "build-wasmcert-provider: pinned upstream src/dune bytes differ" >&2
  exit 2
}

OPAMROOT="$opam_root" opam switch show --switch "$opam_switch" >/dev/null
installed_packages="$(OPAMROOT="$opam_root" opam list --switch "$opam_switch" \
  --installed --short --columns=name,version)"
python3 - "$package_lock" "$installed_packages" <<'PY'
import pathlib
import sys

lock_path = pathlib.Path(sys.argv[1])
installed_text = sys.argv[2]
installed = {}
for line in installed_text.splitlines():
    fields = line.split()
    if len(fields) >= 2:
        installed[fields[0]] = fields[1]

for number, line in enumerate(lock_path.read_text(encoding="utf-8").splitlines(), 1):
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    fields = line.split()
    if len(fields) != 2:
        raise SystemExit(f"{lock_path}:{number}: expected '<package> <version>'")
    package, expected = fields
    observed = installed.get(package)
    if observed != expected:
        raise SystemExit(
            f"WasmCert opam package mismatch for {package}: "
            f"expected {expected}, got {observed!r}"
        )
PY

staging_root="$(mktemp -d "${TMPDIR:-/tmp}/proof-forge-wasmcert-provider-v1.XXXXXX")"
cleanup() { rm -rf "$staging_root"; }
trap cleanup EXIT

build_once() {
  local staging="$1"
  mkdir -p "$staging"
  git -C "$source_dir" archive --format=tar "$revision" | tar -xf - -C "$staging"
  install -m 0644 "$provider_source" "$staging/src/proof_forge_wasmcert_provider_v1.ml"
  install -m 0644 "$dune_overlay" "$staging/src/dune"

  OPAMROOT="$opam_root" opam exec --switch "$opam_switch" -- \
    dune build src/proof_forge_wasmcert_provider_v1.exe --profile=release -j 1 \
    --root "$staging"

  local built="$staging/_build/default/src/proof_forge_wasmcert_provider_v1.exe"
  [[ -f "$built" && -x "$built" ]] || {
    echo "build-wasmcert-provider: Dune did not produce the provider executable" >&2
    exit 2
  }
  local expected_version="proof-forge-wasmcert-provider-v1 1.0.0 $revision"
  local observed_version
  observed_version="$($built --version)"
  [[ "$observed_version" == "$expected_version" ]] || {
    echo "build-wasmcert-provider: version probe mismatch: $observed_version" >&2
    exit 2
  }
}

first_staging="$staging_root/build-1"
build_once "$first_staging"
first_built="$first_staging/_build/default/src/proof_forge_wasmcert_provider_v1.exe"

if [[ "$repeat_check" == true ]]; then
  second_staging="$staging_root/build-2"
  build_once "$second_staging"
  second_built="$second_staging/_build/default/src/proof_forge_wasmcert_provider_v1.exe"
  if ! cmp -s "$first_built" "$second_built"; then
    echo "build-wasmcert-provider: repeat build executable bytes differ" >&2
    echo "build-wasmcert-provider: build-1-sha256=$(sha256_file "$first_built")" >&2
    echo "build-wasmcert-provider: build-2-sha256=$(sha256_file "$second_built")" >&2
    exit 2
  fi
fi

temporary_output="$output.tmp.$$"
rm -f "$temporary_output"
install -m 0555 "$first_built" "$temporary_output"
mv -f "$temporary_output" "$output"

echo "build-wasmcert-provider: platform=$platform"
echo "build-wasmcert-provider: output=$output"
echo "build-wasmcert-provider: sha256=$(sha256_file "$output")"
if [[ "$repeat_check" == true ]]; then
  echo "build-wasmcert-provider: repeat-check=2/2-byte-identical"
else
  echo "build-wasmcert-provider: repeat-check=not-requested"
fi
echo "build-wasmcert-provider: candidate remains non-admitted and cannot change product activation"
