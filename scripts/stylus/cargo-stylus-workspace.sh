#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workspace="$root/build/stylus/cargo-stylus-workspace"
mkdir -p "$workspace"
printf '[workspace]\nmembers = []\nresolver = "2"\n' > "$workspace/Cargo.toml"
printf '[workspace]\nnetworks = {}\n' > "$workspace/Stylus.toml"
printf '%s\n' "$workspace"
