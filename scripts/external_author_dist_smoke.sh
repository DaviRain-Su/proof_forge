#!/usr/bin/env bash
# EA-CI-1 lite: from a local bundle tarball (or just-built stage), run
#   pf new → setup -y (best effort) → pf build -t aleo|evm
# without monorepo lake as the compiler source.
#
# Usage:
#   bash scripts/external_author_dist_smoke.sh
#   PROOF_FORGE_BUNDLE_ARCHIVE=/path/to/bundle.tar.gz bash scripts/external_author_dist_smoke.sh
#
# Prefer target aleo (zero-tool) when network/tool root unavailable; EVM when
# PROOF_FORGE_EA_TARGET=evm and install can materialize solc.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="external-author-dist-smoke"
TARGET="${PROOF_FORGE_EA_TARGET:-aleo}"

die() { echo "${PREFIX}: $*" >&2; exit 1; }
info() { echo "${PREFIX}: $*"; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/pf-ea-smoke.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

archive="${PROOF_FORGE_BUNDLE_ARCHIVE:-}"
if [[ -z "$archive" ]]; then
  info "building bundle into $tmp/dist"
  [[ -x "$root/.lake/build/bin/proof-forge-next" ]] \
    || die "need lake-built proof-forge-next or set PROOF_FORGE_BUNDLE_ARCHIVE"
  bash "$root/scripts/package_bundle_dist.sh" --out "$tmp/dist"
  archive="$(ls "$tmp/dist"/proof-forge-bundle-*-*.tar.gz | head -1)"
fi
[[ -f "$archive" ]] || die "missing archive"

bash "$root/scripts/install.sh" --from "$archive" --prefix "$tmp/prefix"
ver="$(tr -d '[:space:]' <"$tmp/prefix"/current/VERSION 2>/dev/null \
  || cat "$tmp/prefix"/current.path 2>/dev/null | xargs -I{} cat {}/VERSION)"
# resolve install dest
if [[ -L "$tmp/prefix/current" || -d "$tmp/prefix/current" ]]; then
  dest="$tmp/prefix/current"
elif [[ -f "$tmp/prefix/current.path" ]]; then
  dest="$(cat "$tmp/prefix/current.path")"
else
  dest="$(find "$tmp/prefix" -maxdepth 1 -type d -name '0.*' | head -1)"
fi
[[ -x "$dest/bin/pf" ]] || die "install dest missing pf: $dest"

export PATH="$dest/bin:$PATH"
export PROOF_FORGE_CLI="$dest/bin/proof-forge-next"
export PROOF_FORGE_ROOT="$dest"
export PROOF_FORGE_HOST_MODE=dev
unset PROOF_FORGE_TOOL_ROOT || true

# Ensure we are NOT using monorepo .lake as compiler
case "$PROOF_FORGE_CLI" in
  *".lake"*) die "compiler path still monorepo .lake: $PROOF_FORGE_CLI" ;;
esac

workdir="$tmp/work"
mkdir -p "$workdir"
cd "$workdir"

info "pf new hello --target $TARGET"
pf new hello --target "$TARGET"
cd hello

info "pf -y setup --target $TARGET"
set +e
pf -y setup --target "$TARGET"
setup_code=$?
set -e
info "setup exit=$setup_code (non-zero ok if network blocked for install)"

info "pf build"
export PROOF_FORGE_HOST_MODE=dev
if [[ "$TARGET" == "evm" ]]; then
  # Try product install into isolated tool root
  tool_root="$tmp/tool-root"
  mkdir -p "$tool_root"
  export PROOF_FORGE_TOOL_ROOT="$tool_root"
  set +e
  proof-forge-next install --targets evm --yes
  inst=$?
  set -e
  info "install exit=$inst"
fi

pf build -t "$TARGET"
[[ -d "build/${TARGET}" ]] || die "missing build/${TARGET}"
if [[ "$TARGET" == "aleo" ]]; then
  [[ -f "build/aleo/manifest.json" || -n "$(ls build/aleo/* 2>/dev/null || true)" ]] \
    || die "aleo artifacts missing"
else
  [[ -f "build/${TARGET}/manifest.json" ]] || die "missing manifest.json"
fi

info "EA-DIST-SMOKE-OK target=${TARGET} compiler=${PROOF_FORGE_CLI}"
info "no lake build used as external path"
exit 0
