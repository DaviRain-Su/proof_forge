#!/usr/bin/env bash
# Smoke: package_bundle_dist produces pf+next tarball with VERSION gate.
# Host-optional; needs lake-built proof-forge-next + cargo.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-bundle-dist-smoke"
PF="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"

die() { echo "${PREFIX}: $*" >&2; exit 1; }

[[ -x "$PF" ]] || die "missing CLI $PF; lake build proof_forge_next first"

ver_file="$(tr -d '[:space:]' <"$root/VERSION")"
pf_cargo_ver="$(awk -F'"' '/^version = / { print $2; exit }' "$root/clients/pf-cli/Cargo.toml")"
[[ "$pf_cargo_ver" == "$ver_file" ]] \
  || die "pf Cargo version ($pf_cargo_ver) != VERSION ($ver_file)"

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-bundle-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

echo "${PREFIX}: package into $tmp/dist"
bash "$root/scripts/package_bundle_dist.sh" --out "$tmp/dist"

archive="$(ls "$tmp/dist"/proof-forge-bundle-*-*.tar.gz | head -1)"
[[ -f "$archive" ]] || die "missing archive"
[[ -f "${archive}.sha256" ]] || die "missing sha256"

if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive").sha256" )
elif command -v shasum >/dev/null 2>&1; then
  want="$(awk '{print $1}' "${archive}.sha256")"
  got="$(shasum -a 256 "$archive" | awk '{print $1}')"
  [[ "$want" == "$got" ]] || die "sha mismatch"
fi

extract="$tmp/extract"
mkdir -p "$extract"
tar -xzf "$archive" -C "$extract"
stage="$(find "$extract" -maxdepth 1 -type d -name 'proof-forge-bundle-*' | head -1)"
[[ -x "$stage/bin/pf" ]] || die "no pf"
[[ -x "$stage/bin/proof-forge-next" ]] || die "no next"
[[ -f "$stage/scripts/proof_forge_install.py" ]] || die "no install engine"
[[ -f "$stage/VERSION" ]] || die "no VERSION"
[[ -f "$stage/lib/lean/ProofForgeV2/Language/ProgramElaborationV1.olean" ]] \
  || die "missing package-owned olean root (ProgramElaborationV1)"
[[ -f "$stage/scripts/pf_evm_test.sh" ]] || die "missing scripts/pf_evm_test.sh (P1-1 standalone test)"

export PATH="$stage/bin:$PATH"
export PROOF_FORGE_CLI="$stage/bin/proof-forge-next"
export PROOF_FORGE_ROOT="$stage"
# Explicit dev (also the default) — must not require Mint host lock.
export PROOF_FORGE_HOST_MODE=dev

echo "${PREFIX}: pf version"
"$stage/bin/pf" version
echo "${PREFIX}: next version --json"
"$stage/bin/proof-forge-next" version --json | grep -q "\"version\":\"${ver_file}\""

echo "${PREFIX}: install.sh --from archive"
bash "$root/scripts/install.sh" --from "$archive" --prefix "$tmp/prefix"
[[ -x "$tmp/prefix/${ver_file}/bin/pf" ]] || die "install.sh did not place pf"

echo "${PREFIX}: BUNDLE-SMOKE-OK version=${ver_file}"
exit 0
