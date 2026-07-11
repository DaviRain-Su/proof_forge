#!/usr/bin/env bash
set -euo pipefail

version="2.13.0"
sha256="522f9877c1abd42b8e065d9f0248223c8b7327a359996de8150723e8d7b289de"
version_id="jaJtMVj.St7Qw8WZy4jJhYxYv6mow5ej"
url="https://s3-us-west-1.amazonaws.com/build.nearprotocol.com/nearcore/Linux-x86_64/${version}/near-sandbox.tar.gz?versionId=${version_id}"
export PATH="$HOME/.local/bin:$PATH"
if [[ -n "${GITHUB_PATH:-}" ]]; then
  echo "$HOME/.local/bin" >> "$GITHUB_PATH"
fi

if command -v near-sandbox >/dev/null 2>&1 \
    && near-sandbox --version 2>&1 | grep -Fq "release ${version}"; then
  near-sandbox --version
  exit 0
fi

if [[ "$(uname -s)-$(uname -m)" != "Linux-x86_64" ]]; then
  echo "install-sandbox-ci: unsupported platform $(uname -s)-$(uname -m)" >&2
  exit 1
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
archive="$tmp/near-sandbox.tar.gz"
curl -fsSL --retry 5 "$url" -o "$archive"
printf '%s  %s\n' "$sha256" "$archive" | sha256sum -c -
tar -xzf "$archive" -C "$tmp"
install -d "$HOME/.local/bin"
install -m 0755 "$tmp/Linux-x86_64/near-sandbox" "$HOME/.local/bin/near-sandbox"
near-sandbox --version 2>&1 | grep -F "release ${version}"
