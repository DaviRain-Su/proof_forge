#!/usr/bin/env bash
# ProofShip Cloud · C0 spike — prepare a minimal docker build context.
# Copies only what the gate needs (library, CLI build inputs, locked-tool
# manifests, golden fixture) into proofship/cloud-spike/context/ so the build
# is reproducible and the monorepo stays untouched.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$root"
ctx="proofship/cloud-spike/context"

rm -rf "$ctx"
mkdir -p "$ctx/proofship/rwa-share-v1/src"

cp lean-toolchain lakefile.lean lake-manifest.json \
   toolchains.lock.json toolchains-linux-x86_64.lock.json host-profiles.lock.json "$ctx/"
cp ProofForgeV2.lean "$ctx/"
rsync -a ProofForgeV2 "$ctx/"
rsync -a scripts "$ctx/"
cp proofship/rwa-share-v1/src/RwaShareRegistry.lean "$ctx/proofship/rwa-share-v1/src/"

echo "context prepared at $ctx ($(du -sh "$ctx" | cut -f1))" >&2
