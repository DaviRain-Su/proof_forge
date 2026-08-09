#!/usr/bin/env bash
# Engineering CLI dist packager (REL-CLI-1).
# Authority: docs/product/05-distribution-and-packages.md
#
# Produces:
#   dist/proof-forge-next-<ver>-<platform>/   (staging tree)
#   dist/proof-forge-next-<ver>-<platform>.tar.gz
#   dist/proof-forge-next-<ver>-<platform>.tar.gz.sha256
#
# Not formal Stage-0 / hermetic / mainnet. Does not bundle Tool Lock tools (leo etc.).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-cli-dist"
STRIP=0
OUT_DIR="$root/dist"
BUILD_FIRST=0

usage() {
  cat <<'EOF'
usage: package_cli_dist.sh [--strip] [--out DIR] [--build]

  Package the product CLI into an engineering tarball + SHA-256.

  Requires: .lake/build/bin/proof-forge-next (or pass --build to lake build it)
  Requires: repo VERSION matches Lean ProductVersionV1.productVersionV1
  Requires: lean-toolchain matches ProductVersionV1.leanToolchainIdV1

  --strip   run `strip` on the binary before packaging (smaller; optional)
  --out DIR output directory (default: <repo>/dist)
  --build   run `lake build proof_forge_next` first

Exit 0 on success; 1 on package failure; 2 on usage/precondition.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --strip) STRIP=1; shift ;;
    --out)
      [[ $# -ge 2 ]] || { echo "${PREFIX}: --out needs a value" >&2; exit 2; }
      OUT_DIR="$2"
      shift 2
      ;;
    --build) BUILD_FIRST=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *)
      echo "${PREFIX}: unknown arg: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

die() { echo "${PREFIX}: $*" >&2; exit 1; }
bad() { echo "${PREFIX}: $*" >&2; exit 2; }

platform_id() {
  case "$(uname -s)-$(uname -m)" in
    Linux-x86_64) echo "linux-x86_64" ;;
    Darwin-arm64) echo "darwin-arm64" ;;
    Darwin-x86_64) echo "darwin-x86_64" ;;
    *) return 1 ;;
  esac
}

if ! plat="$(platform_id)"; then
  bad "unsupported host $(uname -s)-$(uname -m)"
fi

[[ -f "$root/VERSION" ]] || bad "missing VERSION file"
VERSION="$(tr -d '[:space:]' <"$root/VERSION")"
[[ -n "$VERSION" ]] || bad "VERSION file is empty"
[[ -f "$root/lean-toolchain" ]] || bad "missing lean-toolchain"
TOOLCHAIN="$(tr -d '[:space:]' <"$root/lean-toolchain")"

if [[ "$BUILD_FIRST" -eq 1 ]]; then
  echo "${PREFIX}: lake build proof_forge_next"
  lake build proof_forge_next
fi

PF_BIN="$root/.lake/build/bin/proof-forge-next"
[[ -x "$PF_BIN" ]] || bad "missing CLI ${PF_BIN}; run: lake build proof_forge_next (or --build)"

# Identity gates: CLI version / channel / toolchain vs repo files.
ver_json="$("$PF_BIN" version --json 2>/dev/null || true)"
[[ -n "$ver_json" ]] || die "CLI version --json failed (rebuild after REL-CLI-0?)"
echo "$ver_json" | grep -q "\"version\":\"${VERSION}\"" \
  || die "CLI version != VERSION file (${VERSION}); got: ${ver_json}"
echo "$ver_json" | grep -q '"channel":"engineering-dist"' \
  || die "CLI channel must be engineering-dist; got: ${ver_json}"
echo "$ver_json" | grep -q "\"leanToolchain\":\"${TOOLCHAIN}\"" \
  || die "CLI leanToolchain != lean-toolchain file (${TOOLCHAIN}); got: ${ver_json}"
echo "$ver_json" | grep -q '"schema":"proof-forge.cli.version.v1"' \
  || die "CLI version schema mismatch; got: ${ver_json}"

STAGE_NAME="proof-forge-next-${VERSION}-${plat}"
STAGE="${OUT_DIR}/${STAGE_NAME}"
ARCHIVE="${OUT_DIR}/${STAGE_NAME}.tar.gz"
SUMFILE="${ARCHIVE}.sha256"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin"

echo "${PREFIX}: staging ${STAGE}"
cp -a "$PF_BIN" "$STAGE/bin/proof-forge-next"
if [[ "$STRIP" -eq 1 ]]; then
  if command -v strip >/dev/null 2>&1; then
    echo "${PREFIX}: strip bin/proof-forge-next"
    strip "$STAGE/bin/proof-forge-next" || die "strip failed"
  else
    die "strip requested but strip(1) not found"
  fi
fi
chmod 755 "$STAGE/bin/proof-forge-next"

cp -a "$root/VERSION" "$STAGE/VERSION"
cp -a "$root/lean-toolchain" "$STAGE/lean-toolchain"

# Optional commit stamp (observation only; not formal BuildIdentity).
if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$root" rev-parse HEAD >"$STAGE/COMMIT" 2>/dev/null || true
  if git -C "$root" status --porcelain 2>/dev/null | grep -q .; then
    echo "dirty" >"$STAGE/TREE_STATE"
  else
    echo "clean" >"$STAGE/TREE_STATE"
  fi
fi

cat >"$STAGE/README.md" <<EOF
# proof-forge-next ${VERSION} (engineering-dist)

This is an **engineering** CLI distribution for ProofForge V2.

- **Not** formal Stage-0 / hermetic / mainnet release evidence
- **Not** a Tool Lock bundle (leo/solc/… still via \`proof-forge-next install\`)
- Channel: \`engineering-dist\`

## Install

1. Verify checksum:

   \`\`\`bash
   sha256sum -c proof-forge-next-${VERSION}-${plat}.tar.gz.sha256
   \`\`\`

2. Extract and put \`bin/proof-forge-next\` on \`PATH\`, or set:

   \`\`\`bash
   export PROOF_FORGE_CLI=/absolute/path/to/bin/proof-forge-next
   \`\`\`

3. Check identity:

   \`\`\`bash
   proof-forge-next version --json
   # expect version=${VERSION}, channel=engineering-dist
   \`\`\`

4. Install chain tools (from a checkout that still has package scripts, or future install surface):

   \`\`\`bash
   proof-forge-next install --targets aleo --yes
   \`\`\`

   Note: \`doctor\`/\`install\`/\`local\` currently expect package \`scripts/\` under the process CWD
   (repo root). Pure \`build\`/\`check\`/\`version\` work with only the binary.

## Contents

- \`bin/proof-forge-next\` — product CLI
- \`VERSION\` — SemVer (must match \`version --json\`)
- \`lean-toolchain\` — Lean pin used to build this binary
- \`COMMIT\` / \`TREE_STATE\` — optional git observation at pack time
EOF

# Self-check staged binary
stage_ver="$("$STAGE/bin/proof-forge-next" version --json)"
echo "$stage_ver" | grep -q "\"version\":\"${VERSION}\"" \
  || die "staged binary version check failed: ${stage_ver}"

echo "${PREFIX}: writing ${ARCHIVE}"
# Portable tar: archive from OUT_DIR so member path is STAGE_NAME/...
(
  cd "$OUT_DIR"
  tar -czf "${STAGE_NAME}.tar.gz" "${STAGE_NAME}"
)

echo "${PREFIX}: checksum"
if command -v sha256sum >/dev/null 2>&1; then
  (
    cd "$OUT_DIR"
    sha256sum "${STAGE_NAME}.tar.gz" >"${STAGE_NAME}.tar.gz.sha256"
  )
elif command -v shasum >/dev/null 2>&1; then
  (
    cd "$OUT_DIR"
    shasum -a 256 "${STAGE_NAME}.tar.gz" >"${STAGE_NAME}.tar.gz.sha256"
  )
else
  die "need sha256sum or shasum"
fi

BYTES="$(wc -c <"$ARCHIVE" | tr -d ' ')"
echo "${PREFIX}: archive=${ARCHIVE} bytes=${BYTES}"
echo "${PREFIX}: sha256_file=${SUMFILE}"
cat "$SUMFILE"
echo "${PREFIX}: PACKAGED-OK version=${VERSION} platform=${plat} channel=engineering-dist"
echo "${PREFIX}: NOT formal Stage-0 / hermetic / mainnet"
exit 0
