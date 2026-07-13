#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT="$ROOT/build/stylus/public-route"
TOKEN_OUT="$ROOT/build/stylus/public-token-route"
RUST_OUT="$ROOT/build/stylus/public-route-rust"
INVALID_OUT="$ROOT/build/stylus/public-route-invalid"
STALE_OUT="$ROOT/build/stylus/public-route-stale"
VERIFIED_OUT="$ROOT/build/stylus/public-route-verified"
MISSING_EVIDENCE="$ROOT/build/stylus/no-cutover-evidence.json"
export PATH="$HOME/.foundry/bin:$PATH"
cd "$ROOT"

lake build proof-forge
rm -rf "$OUT"
rm -rf "$OUT".bundle-tmp-*
PROOF_FORGE_STYLUS_EVIDENCE="$MISSING_EVIDENCE" \
lake env proof-forge build --target wasm-arbitrum-stylus --root . \
  -o "$OUT" Examples/Product/Counter.lean

python3 - "$OUT" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
data = json.loads((root / "proof-forge-artifact.json").read_text())
assert data["target"] == "wasm-arbitrum-stylus"
bundle = data["artifactBundle"]
assert bundle["primaryOutput"] == "wasm" and bundle["finalOutput"] == "wasm"
assert data["plan"]["renderer"] == "direct-wasm"
assert data["plan"]["selectors"] == {
    "initialize": "8129fc1c", "increment": "d09de08a", "get": "6d4ce63c"
}
for output in bundle["outputs"]:
    path = root / output["path"]
    assert hashlib.sha256(path.read_bytes()).hexdigest() == output["sha256"]
assert (root / "contract.wasm").read_bytes()[:4] == b"\x00asm"
assert "(module" in (root / "contract.wat").read_text()
assert json.loads((root / "proof-forge-abi.json").read_text())[0]["name"] == "initialize"
assert "export const ABI" in (root / "proof-forge-client.ts").read_text()
deploy = json.loads((root / "proof-forge-deploy.json").read_text())
assert deploy["broadcast"] is False and deploy["activationValidation"] == "notRun"
evidence = json.loads((root / "proof-forge-evidence.json").read_text())
assert evidence["state"] == "unavailable"
assert next(v for v in bundle["validations"] if v["name"] == "nitro-evidence")["state"] == "unavailable"
assert not list(root.parent.glob(root.name + ".bundle-tmp-*"))
(root.parent / "direct-identity.json").write_text(json.dumps({
    output["kind"]: output["sha256"] for output in bundle["outputs"]
    if output["kind"] in {"stylus-plan", "stylus-storage-layout", "solidity-abi"}
}, sort_keys=True))
print("stylus-public-route-artifact: ok")
PY

rm -rf "$RUST_OUT" "$RUST_OUT".bundle-tmp-*
PROOF_FORGE_STYLUS_EVIDENCE="$MISSING_EVIDENCE" \
lake env proof-forge build --target wasm-arbitrum-stylus --renderer rust-sdk --root . \
  -o "$RUST_OUT" Examples/Product/Counter.lean
python3 - "$RUST_OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifact = json.loads((root / "proof-forge-artifact.json").read_text())
assert artifact["plan"]["renderer"] == "rust-sdk"
bundle = artifact["artifactBundle"]
assert bundle["primaryOutput"] == "stylus-rust-source"
assert bundle["finalOutput"] is None
assert (root / "Cargo.toml").is_file() and (root / "src/lib.rs").is_file()
assert not (root / "contract.wat").exists()
direct_identity = json.loads((root.parent / "direct-identity.json").read_text())
rust_identity = {
    output["kind"]: output["sha256"] for output in bundle["outputs"]
    if output["kind"] in {"stylus-plan", "stylus-storage-layout", "solidity-abi"}
}
assert rust_identity == direct_identity
print("stylus-public-route-rust-oracle: ok")
PY

rm -rf "$INVALID_OUT" "$INVALID_OUT".bundle-tmp-*
if lake env proof-forge build --target wasm-arbitrum-stylus --renderer unavailable \
    --root . -o "$INVALID_OUT" Examples/Product/Counter.lean >build/stylus/invalid-renderer.log 2>&1; then
  echo "unsupported Stylus renderer unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'unsupported Stylus renderer `unavailable`' build/stylus/invalid-renderer.log
test ! -e "$INVALID_OUT"
if compgen -G "$INVALID_OUT.bundle-tmp-*" >/dev/null; then
  echo "unsupported renderer left a partial bundle" >&2
  exit 1
fi
echo "stylus-public-route-no-fallback: ok"

rm -rf "$TOKEN_OUT"
rm -rf "$TOKEN_OUT".bundle-tmp-*
PROOF_FORGE_STYLUS_EVIDENCE="$MISSING_EVIDENCE" \
lake env proof-forge build --target wasm-arbitrum-stylus --token --root . \
  -o "$TOKEN_OUT" Examples/Product/FungibleToken.lean

python3 - "$TOKEN_OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifact = json.loads((root / "proof-forge-artifact.json").read_text())
assert artifact["target"] == "wasm-arbitrum-stylus"
assert artifact["plan"]["renderer"] == "direct-wasm"
assert artifact["artifactBundle"]["finalOutput"] == "wasm"
selectors = artifact["plan"]["selectors"]
assert selectors["transfer"] == "a9059cbb"
assert selectors["approve"] == "095ea7b3"
assert selectors["transferFrom"] == "23b872dd"
abi = json.loads((root / "proof-forge-abi.json").read_text())
assert {entry["name"] for entry in abi} >= {
    "totalSupply", "balanceOf", "transfer", "allowance", "approve", "transferFrom"
}
client = (root / "proof-forge-client.ts").read_text()
assert "export async function transfer(recipient: string, amount: bigint)" in client
assert "export async function approve(spender: string, amount: bigint)" in client
assert "export async function transferFrom(src: string, dst: string, amount: bigint)" in client
assert (root / "contract.wasm").read_bytes()[:4] == b"\x00asm"
print("stylus-public-token-route: ok")
PY

python3 - "$OUT" "$ROOT/scripts/stylus/check-cutover-evidence.py" <<'PY'
import copy
import datetime
import json
import pathlib
import subprocess
import sys

root, checker = pathlib.Path(sys.argv[1]), pathlib.Path(sys.argv[2])
artifact = json.loads((root / "proof-forge-artifact.json").read_text())
identities = {
    "planSha256": next(x for x in artifact["artifactBundle"]["outputs"] if x["kind"] == "stylus-plan")["sha256"],
    "storageSha256": next(x for x in artifact["artifactBundle"]["outputs"] if x["kind"] == "stylus-storage-layout")["sha256"],
    "abiSha256": next(x for x in artifact["artifactBundle"]["outputs"] if x["kind"] == "solidity-abi")["sha256"],
}
gate = {"state": "passed", "skipped": False, "provenance": "nitro-testnode"}
payload = {
    "schemaVersion": "1", "target": "wasm-arbitrum-stylus",
    "planSchemaVersion": "stylus-plan-v1", "generatedAt": "2026-07-13T12:00:00Z",
    "identities": identities,
    "gates": {name: copy.deepcopy(gate) for name in
              ("valueVault", "mappingEvents", "token", "remoteCall", "aggregate")},
}
work = root.parent / "cutover-evidence-test"
work.mkdir(exist_ok=True)

def run(name, value):
    source, output = work / f"{name}.json", work / f"{name}.out.json"
    source.write_text(json.dumps(value))
    return subprocess.run([
        sys.executable, str(checker), "--input", str(source), "--output", str(output),
        "--plan-sha256", identities["planSha256"],
        "--storage-sha256", identities["storageSha256"],
        "--abi-sha256", identities["abiSha256"],
        "--now", "2026-07-13T12:00:00Z",
    ], capture_output=True, text=True)

assert run("valid", payload).returncode == 0
live = copy.deepcopy(payload)
live["generatedAt"] = datetime.datetime.now(datetime.timezone.utc).isoformat().replace("+00:00", "Z")
(work / "live.json").write_text(json.dumps(live))
stale = copy.deepcopy(payload); stale["generatedAt"] = "2020-01-01T00:00:00Z"
result = run("stale", stale); assert result.returncode != 0 and "stale" in result.stderr
skipped = copy.deepcopy(payload); skipped["gates"]["token"]["skipped"] = True
result = run("skipped", skipped); assert result.returncode != 0 and "skipped=false" in result.stderr
mismatch = copy.deepcopy(payload); mismatch["identities"]["abiSha256"] = "0" * 64
result = run("mismatch", mismatch); assert result.returncode != 0 and "does not match" in result.stderr
print("stylus-cutover-evidence-vectors: ok")
PY

STALE_EVIDENCE="$ROOT/build/stylus/cutover-evidence-test/stale.json"
rm -rf "$STALE_OUT" "$STALE_OUT".bundle-tmp-*
if PROOF_FORGE_STYLUS_EVIDENCE="$STALE_EVIDENCE" \
    lake env proof-forge build --target wasm-arbitrum-stylus --root . \
    -o "$STALE_OUT" Examples/Product/Counter.lean >build/stylus/stale-evidence.log 2>&1; then
  echo "stale Stylus evidence unexpectedly succeeded" >&2
  exit 1
fi
grep -Fq 'evidence is stale' build/stylus/stale-evidence.log
test ! -e "$STALE_OUT"
if compgen -G "$STALE_OUT.bundle-tmp-*" >/dev/null; then
  echo "stale evidence left a partial bundle" >&2
  exit 1
fi
echo "stylus-public-route-stale-evidence: rejected"

VERIFIED_EVIDENCE="$ROOT/build/stylus/cutover-evidence-test/live.json"
rm -rf "$VERIFIED_OUT" "$VERIFIED_OUT".bundle-tmp-*
PROOF_FORGE_STYLUS_EVIDENCE="$VERIFIED_EVIDENCE" \
lake env proof-forge build --target wasm-arbitrum-stylus --root . \
  -o "$VERIFIED_OUT" Examples/Product/Counter.lean
python3 - "$VERIFIED_OUT" <<'PY'
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
artifact = json.loads((root / "proof-forge-artifact.json").read_text())
validation = next(v for v in artifact["artifactBundle"]["validations"]
                  if v["name"] == "nitro-evidence")
assert validation["state"] == "passed"
evidence = json.loads((root / "proof-forge-evidence.json").read_text())
assert all(gate["provenance"] == "nitro-testnode" for gate in evidence["gates"].values())
print("stylus-public-route-verified-evidence: ok")
PY
