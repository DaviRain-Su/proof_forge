#!/usr/bin/env bash
# External Author MVP: side-by-side pf + proof-forge-next engineering bundle.
# Authority: docs/product/14-external-author-mvp.md · ADR-0040
#
# Produces:
#   dist/proof-forge-bundle-<ver>-<platform>/
#   dist/proof-forge-bundle-<ver>-<platform>.tar.gz
#   dist/proof-forge-bundle-<ver>-<platform>.tar.gz.sha256
#
# Not formal Stage-0 / hermetic / mainnet. Does not bundle Tool Lock *tool binaries*
# (solc etc. still via proof-forge-next install).
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$root"

PREFIX="package-bundle-dist"
STRIP=0
OUT_DIR="$root/dist"
BUILD_NEXT=0
BUILD_PF=1

usage() {
  cat <<'EOF'
usage: package_bundle_dist.sh [--strip] [--out DIR] [--build-next] [--no-build-pf]

  Package pf + proof-forge-next (+ doctor/install scripts + locks) into one tarball.

  Requires: .lake/build/bin/proof-forge-next (or --build-next)
  Requires: cargo for pf (unless prebuilt clients/pf-cli/target/release/pf)
  Requires: VERSION == Lean ProductVersionV1 == proof-forge-pf Cargo version

  --strip        strip both binaries when strip(1) exists
  --out DIR      output directory (default: <repo>/dist)
  --build-next   lake build proof_forge_next first
  --no-build-pf  do not cargo build pf (require existing release binary)

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
    --build-next) BUILD_NEXT=1; shift ;;
    --no-build-pf) BUILD_PF=0; shift ;;
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

# D4: pf Cargo version must match VERSION
pf_cargo_ver="$(
  # shellcheck disable=SC2016
  awk -F'"' '/^version = / { print $2; exit }' "$root/clients/pf-cli/Cargo.toml"
)"
[[ "$pf_cargo_ver" == "$VERSION" ]] \
  || bad "clients/pf-cli Cargo version ($pf_cargo_ver) != VERSION ($VERSION); align before bundle"

if [[ "$BUILD_NEXT" -eq 1 ]]; then
  echo "${PREFIX}: lake build proof_forge_next"
  lake build proof_forge_next
fi

NEXT_BIN="$root/.lake/build/bin/proof-forge-next"
[[ -x "$NEXT_BIN" ]] || bad "missing $NEXT_BIN; run: lake build proof_forge_next (or --build-next)"

ver_json="$("$NEXT_BIN" version --json 2>/dev/null || true)"
[[ -n "$ver_json" ]] || die "CLI version --json failed"
echo "$ver_json" | grep -q "\"version\":\"${VERSION}\"" \
  || die "CLI version != VERSION (${VERSION}); got: ${ver_json}"
echo "$ver_json" | grep -q '"channel":"engineering-dist"' \
  || die "CLI channel must be engineering-dist; got: ${ver_json}"
echo "$ver_json" | grep -q "\"leanToolchain\":\"${TOOLCHAIN}\"" \
  || die "CLI leanToolchain != lean-toolchain (${TOOLCHAIN}); got: ${ver_json}"

PF_BIN="$root/clients/pf-cli/target/release/pf"
if [[ "$BUILD_PF" -eq 1 ]]; then
  echo "${PREFIX}: cargo build pf --release"
  cargo build --manifest-path "$root/clients/pf-cli/Cargo.toml" --locked --release
fi
[[ -x "$PF_BIN" ]] || bad "missing $PF_BIN"

STAGE_NAME="proof-forge-bundle-${VERSION}-${plat}"
STAGE="${OUT_DIR}/${STAGE_NAME}"
ARCHIVE="${OUT_DIR}/${STAGE_NAME}.tar.gz"
SUMFILE="${ARCHIVE}.sha256"

mkdir -p "$OUT_DIR"
rm -rf "$STAGE"
mkdir -p "$STAGE/bin" "$STAGE/scripts"

echo "${PREFIX}: staging ${STAGE}"
cp -a "$NEXT_BIN" "$STAGE/bin/proof-forge-next"
cp -a "$PF_BIN" "$STAGE/bin/pf"
chmod 755 "$STAGE/bin/proof-forge-next" "$STAGE/bin/pf"

if [[ "$STRIP" -eq 1 ]]; then
  if command -v strip >/dev/null 2>&1; then
    echo "${PREFIX}: strip binaries"
    strip "$STAGE/bin/proof-forge-next" || die "strip next failed"
    strip "$STAGE/bin/pf" || true
  else
    die "strip requested but strip(1) not found"
  fi
fi

cp -a "$root/VERSION" "$STAGE/VERSION"
cp -a "$root/lean-toolchain" "$STAGE/lean-toolchain"

# Package-owned olean root for inline-proof frontend (Loader.packageOleanRootV1):
#   IO.appDir (= bin/) / ../lib/lean/ProofForgeV2/Language/ProgramElaborationV1.olean
# Ship the Lean-source import closure of ProgramElaborationV1 only (not full monorepo 500MB+).
echo "${PREFIX}: staging lib/lean olean closure (ProgramElaborationV1)"
OLEAN_ROOT="$root/.lake/build/lib/lean"
[[ -f "$OLEAN_ROOT/ProofForgeV2/Language/ProgramElaborationV1.olean" ]] \
  || bad "missing $OLEAN_ROOT/ProofForgeV2/Language/ProgramElaborationV1.olean — lake build first"
/usr/bin/python3 -I -S - "$root" "$STAGE" "$OLEAN_ROOT" <<'PY'
import re, sys
from pathlib import Path
repo, stage, olean_root = map(Path, sys.argv[1:4])
IMPORT_RE = re.compile(r"^import\s+([A-Za-z0-9_.]+)\s*$")
start = "ProofForgeV2.Language.ProgramElaborationV1"
skip = ("Lean", "Init", "Std", "Lake")
seen: set[str] = set()
q = [start]
while q:
    m = q.pop()
    if m in seen or m.startswith(skip) or any(m.startswith(p + ".") for p in skip):
        continue
    seen.add(m)
    lean = repo.joinpath(*m.split(".")).with_suffix(".lean")
    if not lean.is_file():
        print(f"package-bundle-dist: missing lean for {m}", file=sys.stderr)
        sys.exit(2)
    for line in lean.read_text(encoding="utf-8").splitlines():
        mm = IMPORT_RE.match(line.strip())
        if mm:
            q.append(mm.group(1))
n = 0
for m in sorted(seen):
    src = olean_root.joinpath(*m.split(".")).with_suffix(".olean")
    if not src.is_file():
        print(f"package-bundle-dist: missing olean {src}", file=sys.stderr)
        sys.exit(2)
    dst = stage / "lib" / "lean" / Path(*m.split(".")).with_suffix(".olean")
    dst.parent.mkdir(parents=True, exist_ok=True)
    dst.write_bytes(src.read_bytes())
    n += 1
print(f"package-bundle-dist: staged {n} olean modules under lib/lean")
PY

required_scripts=(
  proof_forge_doctor.py
  proof_forge_install.py
  toolchain_assets.py
  pf_evm_test.sh
)
optional_scripts=(
  solana_runtime_test.sh
  evm_anvil_differential.sh
)
for f in "${required_scripts[@]}"; do
  [[ -f "$root/scripts/$f" ]] || bad "missing required package script scripts/$f"
  cp -a "$root/scripts/$f" "$STAGE/scripts/$f"
done
for f in "${optional_scripts[@]}"; do
  if [[ -f "$root/scripts/$f" ]]; then
    cp -a "$root/scripts/$f" "$STAGE/scripts/$f"
  fi
done
chmod a+x "$STAGE/scripts"/*.sh 2>/dev/null || true

[[ -f "$root/host-profiles.lock.json" ]] || bad "missing host-profiles.lock.json"
cp -a "$root/host-profiles.lock.json" "$STAGE/host-profiles.lock.json"

# Network catalog for `pf network` (metadata only).
if [[ -f "$root/docs/product/networks.v1.json" ]]; then
  mkdir -p "$STAGE/docs/product"
  cp -a "$root/docs/product/networks.v1.json" "$STAGE/docs/product/networks.v1.json"
elif [[ -f "$root/clients/pf-cli/data/networks.v1.json" ]]; then
  mkdir -p "$STAGE/docs/product"
  cp -a "$root/clients/pf-cli/data/networks.v1.json" "$STAGE/docs/product/networks.v1.json"
fi

# UI templates for `pf scaffold-ui` (no node_modules/dist).
if [[ -d "$root/templates" ]]; then
  echo "${PREFIX}: staging templates/ (dApp UI sources, no node_modules)"
  mkdir -p "$STAGE/templates"
  /usr/bin/python3 -I -S - "$root/templates" "$STAGE/templates" <<'PY'
import shutil, sys
from pathlib import Path
src_root, dst_root = map(Path, sys.argv[1:3])
skip_dirs = {"node_modules", "dist", ".git", "target"}
skip_names = {"package-lock.json"}
n = 0
for src in src_root.rglob("*"):
    if any(p in skip_dirs for p in src.parts):
        continue
    if src.is_dir():
        continue
    if src.name in skip_names or src.name.endswith(".tsbuildinfo"):
        continue
    rel = src.relative_to(src_root)
    dst = dst_root / rel
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(src, dst)
    n += 1
print(f"package-bundle-dist: staged {n} template files under templates/")
PY
fi
shopt -s nullglob
lock_files=("$root"/toolchains*.lock.json)
shopt -u nullglob
((${#lock_files[@]} > 0)) || bad "missing toolchains*.lock.json"
for f in "${lock_files[@]}"; do
  cp -a "$f" "$STAGE/$(basename "$f")"
done

# Optional Solana offline verifier
sc_src="${PROOF_FORGE_SOLANA_CLIENT:-$root/clients/solana-client/target/release/proof-forge-solana-client}"
if [[ -x "$sc_src" ]]; then
  cp -a "$sc_src" "$STAGE/bin/proof-forge-solana-client"
  chmod 755 "$STAGE/bin/proof-forge-solana-client"
  echo "${PREFIX}: bundled proof-forge-solana-client"
fi

if command -v git >/dev/null 2>&1 && git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git -C "$root" rev-parse HEAD >"$STAGE/COMMIT" 2>/dev/null || true
  if git -C "$root" status --porcelain 2>/dev/null | grep -q .; then
    echo "dirty" >"$STAGE/TREE_STATE"
  else
    echo "clean" >"$STAGE/TREE_STATE"
  fi
fi

# INSTALL.md (quoted heredoc — no bash expansion of backticks)
cat >"$STAGE/INSTALL.md" <<'INSTALL_EOF'
# proof-forge-bundle __VERSION__ (__PLAT__)

Engineering external-author bundle (ADR-0040). **Not** formal Stage-0 / hermetic.

## Layout

```text
bin/pf
bin/proof-forge-next
lib/lean/         # package-owned olean root (ProgramElaborationV1 closure)
scripts/          # doctor + install engines
toolchains*.lock.json
host-profiles.lock.json
VERSION
```

## Quick start

```bash
export PATH="$PWD/bin:$PATH"
export PROOF_FORGE_CLI="$PWD/bin/proof-forge-next"
export PROOF_FORGE_ROOT="$PWD"   # resolves scripts/ for install/doctor
# host pin: default dev (no Mint/stat digest). Hermetic only on lock-native hosts:
# export PROOF_FORGE_HOST_MODE=hermetic

pf version
pf -y setup --target evm
pf new hello --target evm && cd hello
pf build
```

## Notes

- Channel: `engineering-dist`
- Tool binaries (solc, …) materialize via `proof-forge-next install` into
  `PROOF_FORGE_TOOL_ROOT` (default cache under `~/.cache/proof-forge-v2/`).
- Never require monorepo `lake build` for external authors.
INSTALL_EOF
# Inject version/platform into the quoted template.
if command -v sed >/dev/null 2>&1; then
  sed -i.bak \
    -e "s/__VERSION__/${VERSION}/g" \
    -e "s/__PLAT__/${plat}/g" \
    "$STAGE/INSTALL.md" && rm -f "$STAGE/INSTALL.md.bak"
else
  die "sed required to stamp INSTALL.md version"
fi

cat >"$STAGE/README.md" <<EOF
# ProofForge bundle ${VERSION} (${plat})

See INSTALL.md. Channel: engineering-dist. Not formal Stage-0.
EOF

# Self-check
stage_ver="$("$STAGE/bin/proof-forge-next" version --json)"
echo "$stage_ver" | grep -q "\"version\":\"${VERSION}\"" \
  || die "staged next version check failed: ${stage_ver}"
"$STAGE/bin/pf" version >/dev/null \
  || die "staged pf version failed"

echo "${PREFIX}: writing ${ARCHIVE}"
(
  cd "$OUT_DIR"
  tar -czf "${STAGE_NAME}.tar.gz" "${STAGE_NAME}"
)

echo "${PREFIX}: checksum"
if command -v sha256sum >/dev/null 2>&1; then
  ( cd "$OUT_DIR" && sha256sum "${STAGE_NAME}.tar.gz" >"${STAGE_NAME}.tar.gz.sha256" )
elif command -v shasum >/dev/null 2>&1; then
  ( cd "$OUT_DIR" && shasum -a 256 "${STAGE_NAME}.tar.gz" >"${STAGE_NAME}.tar.gz.sha256" )
else
  die "need sha256sum or shasum"
fi

BYTES="$(wc -c <"$ARCHIVE" | tr -d ' ')"
echo "${PREFIX}: archive=${ARCHIVE} bytes=${BYTES}"
echo "${PREFIX}: sha256_file=${SUMFILE}"
cat "$SUMFILE"
echo "${PREFIX}: PACKAGED-OK version=${VERSION} platform=${plat} channel=engineering-dist bundle=1"
echo "${PREFIX}: NOT formal Stage-0 / hermetic / mainnet"
exit 0
