#!/usr/bin/env bash
# Package side-by-side `pf` + `proof-forge-next` for local/release distribution (D9).
#
# Output: build/dist/pf-<os>-<arch>/
#   pf
#   proof-forge-next   (if available)
#   INSTALL.md
#   README.txt
#
# Not ordinary CI. Not formal Stage-0. Does not upload releases.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

os="$(uname -s | tr '[:upper:]' '[:lower:]')"
arch="$(uname -m)"
case "$os" in
  darwin) os_label=darwin ;;
  linux)  os_label=linux ;;
  *) echo "pf-cli-dist: unsupported OS $os" >&2; exit 2 ;;
esac
case "$arch" in
  arm64|aarch64) arch_label=arm64 ;;
  x86_64|amd64)  arch_label=x86_64 ;;
  *) arch_label="$arch" ;;
esac

label="pf-${os_label}-${arch_label}"
out="${PF_DIST_OUT:-$root/build/dist/$label}"
rm -rf "$out"
mkdir -p "$out"

echo "pf-cli-dist: building pf (release)"
cargo build --manifest-path "$root/clients/pf-cli/Cargo.toml" --locked --release

pf_src="$root/clients/pf-cli/target/release/pf"
[[ -x "$pf_src" ]] || { echo "pf-cli-dist: missing $pf_src" >&2; exit 1; }
cp "$pf_src" "$out/pf"
chmod 755 "$out/pf"

compiler_src="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"
if [[ -x "$compiler_src" ]]; then
  cp "$compiler_src" "$out/proof-forge-next"
  chmod 755 "$out/proof-forge-next"
  echo "pf-cli-dist: bundled proof-forge-next from $compiler_src"
else
  echo "pf-cli-dist: WARNING: proof-forge-next not found — package is pf-only" >&2
  echo "  build with: lake build proof_forge_next" >&2
fi

cp "$root/clients/pf-cli/INSTALL.md" "$out/INSTALL.md"
cat >"$out/README.txt" <<EOF
ProofForge developer CLI bundle ($label)

Contents:
  pf                 developer CLI
  proof-forge-next   compiler (if bundled)
  INSTALL.md         setup guide

Quick:
  export PATH="\$PWD:\$PATH"
  export PROOF_FORGE_CLI="\$PWD/proof-forge-next"   # if bundled
  pf version
  pf setup --target aleo
  pf new hello --target aleo && cd hello && pf build

Not formal / not mainnet / deployable never rewritten by pf.
EOF

# Fingerprints for operators
if command -v shasum >/dev/null 2>&1; then
  (cd "$out" && shasum -a 256 pf proof-forge-next 2>/dev/null || shasum -a 256 pf) \
    >"$out/SHA256SUMS" || true
fi

echo "pf-cli-dist: ok → $out"
ls -la "$out"
