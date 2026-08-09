#!/usr/bin/env bash
# Focused smoke for MCP-V0: stdio initialize + tools/list + tool calls.
# Not host-heavy; not ordinary ci evidence of full toolchain completeness.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

server=(/usr/bin/python3 -I "$root/tools/mcp/proof_forge_mcp_server.py")
cli="${PROOF_FORGE_CLI:-$root/.lake/build/bin/proof-forge-next}"

echo "mcp-smoke: self-check"
out="$("${server[@]}" --self-check)"
echo "$out" | rg -q '"ok": true'
echo "$out" | rg -q 'pf_doctor'
echo "$out" | rg -q 'pf_list_targets'
echo "$out" | rg -q 'pf_install'
echo "$out" | rg -q 'pf_build'
echo "$out" | rg -q 'pf_artifacts'
echo "$out" | rg -q 'pf_local'
echo "$out" | rg -q 'pf_chain_catalog'

if [[ ! -x "$cli" ]]; then
  echo "mcp-smoke: FAIL proof-forge-next missing at $cli (lake build first)" >&2
  exit 1
fi
export PROOF_FORGE_ROOT="$root"
export PROOF_FORGE_CLI="$cli"

# Drive MCP over a one-shot stdin protocol session (newline JSON-RPC).
run_session() {
  local session_file="$1"
  # shellcheck disable=SC2068
  PROOF_FORGE_ROOT="$root" PROOF_FORGE_CLI="$cli" \
    /usr/bin/python3 -I -S - "$session_file" <<'PY'
import json, os, subprocess, sys
from pathlib import Path

session_path = Path(sys.argv[1])
messages = []
for line in session_path.read_text(encoding="utf-8").splitlines():
    line = line.strip()
    if not line or line.startswith("#"):
        continue
    messages.append(json.loads(line))

server = [
    "/usr/bin/python3", "-I",
    str(Path(os.environ["PROOF_FORGE_ROOT"]) / "tools/mcp/proof_forge_mcp_server.py"),
]
env = os.environ.copy()
proc = subprocess.Popen(
    server,
    stdin=subprocess.PIPE,
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    text=True,
    env=env,
    cwd=env["PROOF_FORGE_ROOT"],
)
assert proc.stdin is not None and proc.stdout is not None
responses = []
for msg in messages:
    proc.stdin.write(json.dumps(msg, separators=(",", ":")) + "\n")
    proc.stdin.flush()
    # Notifications (no id) expect no response line.
    if "id" not in msg:
        continue
    line = proc.stdout.readline()
    if not line:
        stderr = proc.stderr.read() if proc.stderr else ""
        raise SystemExit(f"server closed early; stderr={stderr!r}")
    responses.append(json.loads(line))
proc.stdin.close()
# Drain remaining
try:
    proc.wait(timeout=5)
except Exception:
    proc.kill()
print(json.dumps(responses, indent=2, ensure_ascii=False))
PY
}

tmp="$(mktemp -d /tmp/pf-mcp-smoke.XXXXXX)"
trap 'rm -rf "$tmp"' EXIT

cat >"$tmp/session1.jsonl" <<'EOF'
# initialize + list tools + list targets + doctor quint
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp-smoke","version":"0.0.1"}}}
{"jsonrpc":"2.0","method":"notifications/initialized"}
{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pf_list_targets","arguments":{}}}
{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"pf_doctor","arguments":{"target":"quint"}}}
{"jsonrpc":"2.0","id":5,"method":"tools/call","params":{"name":"pf_artifacts","arguments":{"target":"quint"}}}
{"jsonrpc":"2.0","id":6,"method":"tools/call","params":{"name":"pf_install","arguments":{"targets":["quint"],"dryRun":true}}}
EOF

echo "mcp-smoke: protocol session (initialize/list/targets/doctor/artifacts/install-dry-run)"
run_session "$tmp/session1.jsonl" >"$tmp/resp1.json"
printf '%s\n' "$(head -c 4000 "$tmp/resp1.json" || true)"
echo ""

# Validate response shapes
/usr/bin/python3 -I -S - "$tmp/resp1.json" <<'PY'
import json, sys
from pathlib import Path
responses = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8"))
by_id = {r["id"]: r for r in responses}
assert 1 in by_id and "result" in by_id[1]
assert by_id[1]["result"]["serverInfo"]["name"] == "proof-forge-mcp"
assert "tools" in by_id[1]["result"]["capabilities"]
tools = {t["name"] for t in by_id[2]["result"]["tools"]}
expected = {"pf_list_targets", "pf_doctor", "pf_install", "pf_build", "pf_artifacts"}
assert expected <= tools, tools
# pf_list_targets content
text3 = by_id[3]["result"]["content"][0]["text"]
body3 = json.loads(text3)
assert body3["ok"] is True, body3
assert body3["parsed"]["schema"] == "proof-forge.cli.list-targets.v1"
ids = {t["id"] for t in body3["parsed"]["targets"]}
assert "evm" in ids and "solana" in ids and "quint" in ids
# design-only must not appear without includeAll
assert "soroban" not in ids
# doctor
text4 = by_id[4]["result"]["content"][0]["text"]
body4 = json.loads(text4)
assert body4.get("parsed", {}).get("schema") == "proof-forge.doctor.v1"
# artifacts target inspect
text5 = by_id[5]["result"]["content"][0]["text"]
body5 = json.loads(text5)
assert body5["ok"] is True
assert body5["parsed"]["schema"] == "proof-forge.cli.inspect.v1"
assert body5["parsed"]["target"] == "quint"
# install dry-run
text6 = by_id[6]["result"]["content"][0]["text"]
body6 = json.loads(text6)
assert body6["ok"] is True, body6
assert body6["parsed"]["schema"] == "proof-forge.install.v1"
print("mcp-smoke: protocol assertions ok")
PY

# Reject network/broadcast on pf_build
cat >"$tmp/session2.jsonl" <<'EOF'
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp-smoke","version":"0.0.1"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pf_build","arguments":{"source":"Examples/StateCell.lean","module":"Examples.StateCell","target":"quint","broadcast":true}}}
EOF
echo "mcp-smoke: pf_build rejects broadcast"
run_session "$tmp/session2.jsonl" >"$tmp/resp2.json"
rg -q 'does not support network/broadcast|broadcast' "$tmp/resp2.json"
rg -q '"isError": true|"ok": false|usage' "$tmp/resp2.json"

# Optional: real zero-tool quint build if the neutral StateCell source is present
if [[ -f "$root/Examples/StateCell.lean" ]]; then
  out_dir="$tmp/build-quint"
  cat >"$tmp/session3.jsonl" <<EOF
{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"mcp-smoke","version":"0.0.1"}}}
{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"pf_build","arguments":{"source":"Examples/StateCell.lean","module":"Examples.StateCell","target":"quint","output":"$out_dir"}}}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"pf_artifacts","arguments":{"outputDir":"$out_dir"}}}
EOF
  echo "mcp-smoke: pf_build StateCell → quint + pf_artifacts"
  set +e
  run_session "$tmp/session3.jsonl" >"$tmp/resp3.json" 2>"$tmp/resp3.err"
  code=$?
  set -e
  head -c 3000 "$tmp/resp3.json" || true
  echo ""
  if [[ "$code" -eq 0 ]] && rg -q 'proof-forge.output.v1|"ok": true' "$tmp/resp3.json"; then
    echo "mcp-smoke: build+artifacts path exercised"
  else
    echo "mcp-smoke: build path soft-note (may fail on proof/toolchain); protocol already covered" >&2
    if [[ -s "$tmp/resp3.err" ]]; then
      head -c 500 "$tmp/resp3.err" >&2 || true
      echo >&2
    fi
  fi
fi

echo "mcp-smoke: OK"
