#!/usr/bin/env bash
# Materialize an engineering userspace GLIBC pack for locked near-sandbox on
# older Linux hosts (e.g. Debian 12 / GLIBC 2.36 running near-sandbox built
# against GLIBC 2.39).
#
# Layout written under PROOF_FORGE_TOOL_ROOT (default cache root):
#
#   near-sandbox-glibc/
#     ld-linux-x86-64.so.2
#     lib/   (libc and companions needed to exec near-sandbox --version)
#     MANIFEST.json
#
# Honesty:
#   - Does **not** replace Tool Lock near-sandbox bytes.
#   - Engineering runner pack only — **not** hermetic release evidence until
#     digests are admitted into toolchains-linux-x86_64.lock.json + CI pin.
#   - Linux x86_64 only.
#   - Prefer: host already has GLIBC ≥ binary requirement → skip (direct exec).
#
# Usage:
#   scripts/near_sandbox_glibc_materialize.sh
#   PROOF_FORGE_TOOL_ROOT=… scripts/near_sandbox_glibc_materialize.sh
#   PF_NEAR_GLIBC_FORCE=1 scripts/near_sandbox_glibc_materialize.sh   # rebuild pack
#
# Requires: curl, ar, tar, sha256sum|shasum, python3 (manifest), Linux x86_64.
set -euo pipefail

die() { echo "near-sandbox-glibc: $*" >&2; exit 1; }
info() { echo "near-sandbox-glibc: $*" >&2; }

if [[ "$(uname -s)" != "Linux" ]]; then
  die "Linux only (got $(uname -s))"
fi
if [[ "$(uname -m)" != "x86_64" ]]; then
  die "linux-x86_64 only (got $(uname -m))"
fi

case "$(uname -s)" in
  Linux) default_tool_root="$HOME/.cache/proof-forge-v2/tool-root/linux-x86_64" ;;
  *) die "unreachable" ;;
esac
tool_root="${PROOF_FORGE_TOOL_ROOT:-$default_tool_root}"
pack_root="${tool_root%/}/near-sandbox-glibc"
sandbox="${tool_root%/}/near-sandbox"

# Pinned Ubuntu noble libc6 (matches 2026-08-11 observed engineering run).
# Package version is product-intent pin; file digests recorded in MANIFEST after extract.
GLIBC_DEB_VERSION="${PF_NEAR_GLIBC_DEB_VERSION:-2.39-0ubuntu8.8}"
GLIBC_DEB_NAME="libc6_${GLIBC_DEB_VERSION}_amd64.deb"
GLIBC_DEB_URL="${PF_NEAR_GLIBC_DEB_URL:-http://archive.ubuntu.com/ubuntu/pool/main/g/glibc/${GLIBC_DEB_NAME}}"
# Optional expected deb sha256 (set when CI pins; empty = compute+record only).
GLIBC_DEB_SHA256="${PF_NEAR_GLIBC_DEB_SHA256:-}"

for need in curl ar tar python3; do
  command -v "$need" >/dev/null 2>&1 || die "missing required tool: $need"
done
if command -v sha256sum >/dev/null 2>&1; then
  sha256_file() { sha256sum "$1" | awk '{print $1}'; }
elif command -v shasum >/dev/null 2>&1; then
  sha256_file() { shasum -a 256 "$1" | awk '{print $1}'; }
else
  die "need sha256sum or shasum"
fi

# If sandbox already runs, pack is optional unless forced.
if [[ -x "$sandbox" && "${PF_NEAR_GLIBC_FORCE:-0}" != "1" ]]; then
  if "$sandbox" --version >/dev/null 2>&1; then
    info "near-sandbox already runnable on this host — pack not required"
    info "set PF_NEAR_GLIBC_FORCE=1 to materialize anyway"
    exit 0
  fi
fi

if [[ -d "$pack_root" && -x "$pack_root/ld-linux-x86-64.so.2" && "${PF_NEAR_GLIBC_FORCE:-0}" != "1" ]]; then
  # Validate pack can launch sandbox if present.
  if [[ -x "$sandbox" ]]; then
    if "$pack_root/ld-linux-x86-64.so.2" --library-path "$pack_root/lib" \
        "$sandbox" --version >/dev/null 2>&1; then
      info "existing pack ok at $pack_root"
      exit 0
    fi
    info "existing pack failed launch probe; rebuilding"
  else
    info "existing pack present (sandbox missing at $sandbox); leave as-is"
    exit 0
  fi
fi

workdir="$(mktemp -d "${TMPDIR:-/tmp}/pf-near-glibc.XXXXXX")"
cleanup() { rm -rf "$workdir"; }
trap cleanup EXIT

info "downloading $GLIBC_DEB_URL"
deb_path="$workdir/$GLIBC_DEB_NAME"
curl -fsSL --retry 3 -o "$deb_path" "$GLIBC_DEB_URL" \
  || die "download failed (set PF_NEAR_GLIBC_DEB_URL or check network)"

deb_hash="$(sha256_file "$deb_path")"
info "deb sha256=$deb_hash"
if [[ -n "$GLIBC_DEB_SHA256" && "$deb_hash" != "$GLIBC_DEB_SHA256" ]]; then
  die "deb sha256 mismatch: expected $GLIBC_DEB_SHA256 got $deb_hash"
fi

extract_dir="$workdir/extract"
mkdir -p "$extract_dir"
(
  cd "$extract_dir"
  ar x "$deb_path"
  if [[ -f data.tar.zst ]]; then
    if command -v zstd >/dev/null 2>&1; then
      zstd -d -c data.tar.zst | tar -xf -
    else
      die "deb uses zstd; install zstd or use a xz data.tar"
    fi
  elif [[ -f data.tar.xz ]]; then
    tar -xJf data.tar.xz
  elif [[ -f data.tar.gz ]]; then
    tar -xzf data.tar.gz
  else
    die "no data.tar.* in deb"
  fi
)

# Locate loader + multiarch lib dir inside the deb.
loader_src=""
lib_src=""
if [[ -f "$extract_dir/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2" ]]; then
  loader_src="$extract_dir/lib/x86_64-linux-gnu/ld-linux-x86-64.so.2"
  lib_src="$extract_dir/lib/x86_64-linux-gnu"
elif [[ -f "$extract_dir/lib64/ld-linux-x86-64.so.2" ]]; then
  loader_src="$extract_dir/lib64/ld-linux-x86-64.so.2"
  lib_src="$extract_dir/lib/x86_64-linux-gnu"
  [[ -d "$lib_src" ]] || lib_src="$extract_dir/lib64"
else
  die "ld-linux-x86-64.so.2 not found inside deb"
fi
[[ -d "$lib_src" ]] || die "lib dir missing in deb: $lib_src"

rm -rf "$pack_root"
mkdir -p "$pack_root/lib"
# Copy loader as a real file (no symlink) — launch helper rejects symlinks.
cp -L "$loader_src" "$pack_root/ld-linux-x86-64.so.2"
chmod 755 "$pack_root/ld-linux-x86-64.so.2"

# Copy shared objects from the multiarch dir (follow symlinks to real files).
# near-sandbox may need more than libc; libc6 provides the GLIBC ABI surface.
# Additional system libs (libssl, libgcc, …) still come from the host — if those
# are too old the pack alone may not suffice; document that as residual.
while IFS= read -r -d '' so; do
  base="$(basename "$so")"
  # Skip the loader itself if it appears under lib/
  [[ "$base" == "ld-linux-x86-64.so.2" ]] && continue
  cp -L "$so" "$pack_root/lib/$base" 2>/dev/null || true
done < <(find "$lib_src" -maxdepth 1 -type f -name '*.so*' -print0 2>/dev/null)

# Also copy common SONAME symlinks as files when present.
for name in libc.so.6 libm.so.6 libpthread.so.0 libdl.so.2 librt.so.1 \
            libresolv.so.2 libutil.so.1 libnss_dns.so.2 libnss_files.so.2; do
  if [[ -e "$lib_src/$name" && ! -e "$pack_root/lib/$name" ]]; then
    cp -L "$lib_src/$name" "$pack_root/lib/$name" 2>/dev/null || true
  fi
done

# Write MANIFEST with file digests (engineering observation).
python3 - <<PY
import json, hashlib, os
from pathlib import Path

pack = Path("$pack_root")
files = {}
for p in sorted(pack.rglob("*")):
    if not p.is_file():
        continue
    rel = str(p.relative_to(pack))
    h = hashlib.sha256(p.read_bytes()).hexdigest()
    files[rel] = {"sha256": h, "size": p.stat().st_size}

manifest = {
    "schema": "proof-forge.near-sandbox-glibc-pack.v1",
    "platform": "linux-x86_64",
    "purpose": "engineering userspace loader for locked near-sandbox on older GLIBC hosts",
    "honesty": "not hermetic Tool Lock pin; runner evidence only until admitted to toolchains lock",
    "sourcePackage": {
        "name": "libc6",
        "version": "$GLIBC_DEB_VERSION",
        "url": "$GLIBC_DEB_URL",
        "sha256": "$deb_hash",
        "licenseSpdx": "LGPL-2.1-or-later AND GPL-2.0-or-later",
    },
    "layout": {
        "loader": "ld-linux-x86-64.so.2",
        "libraryPath": "lib",
    },
    "files": files,
}
(pack / "MANIFEST.json").write_text(json.dumps(manifest, indent=2) + "\n")
print(f"wrote {pack / 'MANIFEST.json'} ({len(files)} files)")
PY

# Probe launch if sandbox present.
if [[ -x "$sandbox" ]]; then
  if ! "$pack_root/ld-linux-x86-64.so.2" --library-path "$pack_root/lib" \
      "$sandbox" --version; then
    die "pack materialized but near-sandbox --version still fails (host may need extra libs beyond libc6; set PF_NEAR_SANDBOX_LIBRARY_PATH to a fuller sysroot)"
  fi
  info "launch probe OK"
else
  info "sandbox not at $sandbox — pack written; install near-sandbox via pf setup --target near --with-runtime"
fi

info "pack ready: $pack_root"
info "scripts auto-discover this layout via scripts/lib/near_sandbox_launch.sh"
info "NOT hermetic release evidence until digests enter toolchains-linux-x86_64.lock.json"
