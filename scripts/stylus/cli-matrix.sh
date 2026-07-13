#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
out_root="$root/build/stylus/cli-matrix"
missing_evidence="$out_root/no-cutover-evidence.json"
export PATH="$HOME/.foundry/bin:$PATH"
cd "$root"

lake build proof-forge Examples.Product.Aggregate
rm -rf "$out_root"
mkdir -p "$out_root"

build_pair() {
  local name="$1"
  local source="$2"
  shift 2
  local direct="$out_root/$name-direct"
  local rust="$out_root/$name-rust"
  PROOF_FORGE_STYLUS_EVIDENCE="$missing_evidence" \
    lake env proof-forge build --target wasm-arbitrum-stylus --root . \
      -o "$direct" "$@" "$source"
  PROOF_FORGE_STYLUS_EVIDENCE="$missing_evidence" \
    lake env proof-forge build --target wasm-arbitrum-stylus --renderer rust-sdk --root . \
      -o "$rust" "$@" "$source"
}

build_pair counter Examples/Product/Counter.lean
build_pair value-vault Examples/Product/ValueVault.lean
build_pair token Examples/Product/FungibleToken.lean --token
build_pair remote-call Examples/Product/RemoteCall.lean \
  --peer peer.callee=0x1111111111111111111111111111111111111111
build_pair aggregate Examples/Product/Aggregate.lean

unbound="$out_root/remote-call-unbound"
unbound_log="$out_root/remote-call-unbound.log"
if PROOF_FORGE_STYLUS_EVIDENCE="$missing_evidence" \
    lake env proof-forge build --target wasm-arbitrum-stylus --root . \
      -o "$unbound" Examples/Product/RemoteCall.lean >"$unbound_log" 2>&1; then
  echo "Stylus accepted a logical peer without --peer binding" >&2
  exit 1
fi
grep -F -- '--peer logical=0x...' "$unbound_log" >/dev/null
test ! -e "$unbound"
if compgen -G "$unbound.bundle-tmp-*" >/dev/null; then
  echo "failed Stylus peer binding left a temporary bundle" >&2
  exit 1
fi

remote_target="$(printf '11%.0s' {1..20})"
entry_selector="$(cast sig 'call_remote()' | sed 's/^0x//')"
remote_selector="$(cast sig 'remote_call()' | sed 's/^0x//')"
remote_runtime="$(cargo run --quiet --manifest-path tools/stylus-vm-runner/Cargo.toml -- \
  "$out_root/remote-call-direct/contract.wasm" \
  --mock-call "$remote_target=0:$(printf '00%.0s' {1..31})2a" \
  --calldata "$entry_selector" --invoke user_entrypoint)"

python3 - "$out_root" "$remote_target" "$remote_selector" "$remote_runtime" <<'PY'
import hashlib
import json
import pathlib
import sys

root = pathlib.Path(sys.argv[1])
remote_target, remote_selector = sys.argv[2:4]
remote_runtime = json.loads(sys.argv[4])
names = ("counter", "value-vault", "token", "remote-call", "aggregate")
identity_kinds = {"stylus-plan", "stylus-storage-layout", "solidity-abi"}

for name in names:
    direct_root, rust_root = root / f"{name}-direct", root / f"{name}-rust"
    direct = json.loads((direct_root / "proof-forge-artifact.json").read_text())
    rust = json.loads((rust_root / "proof-forge-artifact.json").read_text())
    direct_bundle, rust_bundle = direct["artifactBundle"], rust["artifactBundle"]
    assert direct["plan"]["renderer"] == "direct-wasm"
    assert rust["plan"]["renderer"] == "rust-sdk"
    assert direct_bundle["primaryOutput"] == "wasm" and direct_bundle["finalOutput"] == "wasm"
    assert rust_bundle["primaryOutput"] == "stylus-rust-source" and rust_bundle["finalOutput"] is None
    direct_identity = {item["kind"]: item["sha256"] for item in direct_bundle["outputs"]
                       if item["kind"] in identity_kinds}
    rust_identity = {item["kind"]: item["sha256"] for item in rust_bundle["outputs"]
                     if item["kind"] in identity_kinds}
    assert direct_identity == rust_identity
    for bundle_root, bundle in ((direct_root, direct_bundle), (rust_root, rust_bundle)):
        for item in bundle["outputs"]:
            path = bundle_root / item["path"]
            assert hashlib.sha256(path.read_bytes()).hexdigest() == item["sha256"]
        evidence = json.loads((bundle_root / "proof-forge-evidence.json").read_text())
        assert evidence["state"] == "unavailable"

aggregate_abi = json.loads((root / "aggregate-direct/proof-forge-abi.json").read_text())
assert {entry["name"] for entry in aggregate_abi} == {
    "echo_bytes", "echo_string", "echo_fixed"
}
fixed = next(entry for entry in aggregate_abi if entry["name"] == "echo_fixed")
assert fixed["inputs"] == [{"name": "value", "type": "uint64[2]"}]
assert fixed["outputs"] == [{"type": "uint64[2]"}]
remote_plan = (root / "remote-call-direct/proof-forge-plan.txt").read_text()
assert 'canonicalSignature := "remote_call()"' in remote_plan
assert 'canonicalSignature := "remote_call(uint64,uint64)"' in remote_plan
assert str(int("11" * 20, 16)) in remote_plan
assert 'StylusLiteralPlan.string "remote_call"' in remote_plan
calls = [event for event in remote_runtime["trace"] if event["event"] == "call_contract"]
assert len(calls) == 1
assert calls[0]["address"] == remote_target
assert calls[0]["calldata"] == remote_selector
assert remote_runtime["result"] == "00" * 31 + "2a"
print("stylus-cli-matrix: ok (5 products x 2 renderers)")
PY
