#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
expected_revision="$(tr -d '[:space:]' < "$root/tools/stylus-nitro/nitro-testnode.rev")"
checkout="${PROOF_FORGE_NITRO_TESTNODE_DIR:-$root/build/tools/nitro-testnode}"
endpoint="${PROOF_FORGE_STYLUS_ENDPOINT:-http://127.0.0.1:8547}"
toolchain="${PROOF_FORGE_STYLUS_RUST:-1.91.0}"

if [[ "${1:-}" == "--self-test" ]]; then
  python3 - <<'PY'
import json
print(json.dumps({
    "ready": True,
    "rustToolchain": "self-test",
    "cargoStylus": "self-test",
    "docker": "self-test",
    "cast": "self-test",
    "nitroRevision": "self-test",
    "rpcEndpoint": "self-test",
    "rpcChainId": "self-test",
}, sort_keys=True))
PY
  exit 0
fi

ready=true
rust_version="$(rustup run "$toolchain" rustc --version 2>/dev/null || true)"
cargo_stylus="$(rustup run "$toolchain" cargo stylus --version 2>/dev/null || true)"
docker_version="$(python3 - <<'PY'
import subprocess
try:
    result = subprocess.run(
        ["docker", "info", "--format", "{{.ServerVersion}}"],
        capture_output=True, text=True, timeout=5, check=False,
    )
    print(result.stdout.strip() if result.returncode == 0 else "")
except (OSError, subprocess.TimeoutExpired):
    print("")
PY
)"
export PATH="$HOME/.foundry/bin:$PATH"
cast_version="$(cast --version 2>/dev/null | head -1 || true)"
actual_revision="$(git -C "$checkout" rev-parse HEAD 2>/dev/null || true)"
rpc_response="$(python3 - "$endpoint" <<'PY'
import subprocess
import sys
try:
    result = subprocess.run([
        "curl", "-fsS", "-H", "content-type: application/json",
        "--data", '{"jsonrpc":"2.0","id":1,"method":"eth_chainId","params":[]}',
        sys.argv[1],
    ], capture_output=True, text=True, timeout=5, check=False)
    print(result.stdout.strip() if result.returncode == 0 else "")
except (OSError, subprocess.TimeoutExpired):
    print("")
PY
)"
rpc_chain_id="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("result", ""))' \
  <<<"$rpc_response" 2>/dev/null || true)"

for value in "$rust_version" "$cargo_stylus" "$docker_version" "$cast_version" "$rpc_chain_id"; do
  [[ -n "$value" ]] || ready=false
done
[[ "$actual_revision" == "$expected_revision" ]] || ready=false

report="$(python3 - "$ready" "$rust_version" "$cargo_stylus" "$docker_version" "$cast_version" \
  "$actual_revision" "$endpoint" "$rpc_chain_id" <<'PY'
import json
import sys

print(json.dumps({
    "ready": sys.argv[1] == "true",
    "rustToolchain": sys.argv[2],
    "cargoStylus": sys.argv[3],
    "docker": sys.argv[4],
    "cast": sys.argv[5],
    "nitroRevision": sys.argv[6],
    "rpcEndpoint": sys.argv[7],
    "rpcChainId": sys.argv[8],
}, sort_keys=True))
PY
)"
evidence_dir="$root/build/evidence/stylus"
mkdir -p "$evidence_dir"
tmp="$evidence_dir/nitro-doctor.json.tmp"
printf '%s\n' "$report" > "$tmp"
mv "$tmp" "$evidence_dir/nitro-doctor.json"
printf '%s\n' "$report"

[[ "$ready" == true ]]
