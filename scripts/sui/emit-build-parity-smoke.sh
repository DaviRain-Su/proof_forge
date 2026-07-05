#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"

EMIT_DIR="build/sui/counter-emit"
BUILD_DIR="build/sui/counter-build"
NORM_DIR="build/sui/counter-parity-normalized"

rm -rf "$EMIT_DIR" "$BUILD_DIR" "$NORM_DIR"
lake env proof-forge emit --target move-sui --fixture counter --format sui -o "$EMIT_DIR"
lake env proof-forge build --target move-sui --fixture counter -o "$BUILD_DIR"

mkdir -p "$NORM_DIR/emit" "$NORM_DIR/build"
cp -R "$EMIT_DIR"/. "$NORM_DIR/emit/"
cp -R "$BUILD_DIR"/. "$NORM_DIR/build/"

python3 - "$NORM_DIR/emit" "$NORM_DIR/build" <<'PY'
import json
import pathlib
import sys

emit_dir = pathlib.Path(sys.argv[1])
build_dir = pathlib.Path(sys.argv[2])
for root, token in [(emit_dir, "build/sui/counter-emit"), (build_dir, "build/sui/counter-build")]:
    for path in root.rglob("*"):
        if path.is_file():
            text = path.read_text()
            text = text.replace(token, "<sui-package>")
            path.write_text(text)

for root in (emit_dir, build_dir):
    schema = root / "proof-forge-sdk.json"
    data = json.loads(schema.read_text())
    artifact_metadata = data["artifacts"]["artifactMetadata"]
    artifact_metadata["sha256"] = "<normalized-artifact-metadata-sha256>"
    artifact_metadata["bytes"] = 0
    schema.write_text(json.dumps(data, sort_keys=True, separators=(",", ":")) + "\n")
PY

diff -ru "$NORM_DIR/emit" "$NORM_DIR/build"
echo "sui-emit-build-parity: ok"
