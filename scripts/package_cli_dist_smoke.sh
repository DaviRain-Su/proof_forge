#!/usr/bin/env bash
# No-host-heavy smoke for engineering CLI dist packager.
# Requires a built proof-forge-next with version command.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-cli-dist-smoke"
PF="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"

die() { echo "${PREFIX}: $*" >&2; exit 1; }

[[ -x "$PF" ]] || die "missing CLI $PF; lake build proof_forge_next first"

echo "${PREFIX}: version identity"
human="$("$PF" version)"
json="$("$PF" version --json)"
echo "  human=$human"
echo "  json=$json"
echo "$json" | grep -q '"schema":"proof-forge.cli.version.v1"' || die "schema"
echo "$json" | grep -q '"channel":"engineering-dist"' || die "channel"
ver_file="$(tr -d '[:space:]' <"$root/VERSION")"
echo "$json" | grep -q "\"version\":\"${ver_file}\"" || die "VERSION mismatch"
tc_file="$(tr -d '[:space:]' <"$root/lean-toolchain")"
echo "$json" | grep -q "\"leanToolchain\":\"${tc_file}\"" || die "toolchain mismatch"
"$PF" --version | grep -q "$ver_file" || die "--version human"

echo "${PREFIX}: package into temp dist"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-cli-dist-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
bash "$root/scripts/package_cli_dist.sh" --out "$tmp/dist"

archive="$(ls "$tmp/dist"/proof-forge-next-*-*.tar.gz | head -1)"
[[ -f "$archive" ]] || die "missing archive"
[[ -f "${archive}.sha256" ]] || die "missing sha256"
echo "${PREFIX}: archive=$archive"

# Verify checksum + extract + run version from package
if command -v sha256sum >/dev/null 2>&1; then
  (cd "$(dirname "$archive")" && sha256sum -c "$(basename "$archive").sha256")
elif command -v shasum >/dev/null 2>&1; then
  # shasum -c expects "HASH  FILE"
  (cd "$(dirname "$archive")" && shasum -a 256 -c "$(basename "$archive").sha256")
fi

extract="$tmp/extract"
mkdir -p "$extract"
tar -xzf "$archive" -C "$extract"
stage="$(find "$extract" -maxdepth 1 -type d -name 'proof-forge-next-*' | head -1)"
[[ -d "$stage" ]] || die "missing extracted stage"
packed_bin="$stage/bin/proof-forge-next"
[[ -x "$packed_bin" ]] || die "packed binary not executable"
for f in \
  scripts/proof_forge_doctor.py \
  scripts/proof_forge_install.py \
  scripts/toolchain_assets.py \
  host-profiles.lock.json \
  toolchains.lock.json \
  toolchains-linux-x86_64.lock.json
do
  [[ -f "$stage/$f" ]] || die "dist missing required file: $f"
done
packed_json="$("$packed_bin" version --json)"
echo "$packed_json" | grep -q "\"version\":\"${ver_file}\"" || die "packed version"
echo "${PREFIX}: PACK-SMOKE-OK"
exit 0
