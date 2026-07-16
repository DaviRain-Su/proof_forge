#!/usr/bin/env bash
# Atomic ERC-2612 product/runtime conformance.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.elan/bin:$HOME/.local/bin:$HOME/.foundry/bin:$PATH"

OUT="${PROOF_FORGE_ERC20_PERMIT_OUT:-build/portable/erc20-permit}"
FORGE_OUT="$OUT/foundry"
fail() { echo "FAIL: $1" >&2; exit 1; }
require_contains() { grep -Fq -- "$2" "$1" || fail "$3 missing '$2'"; }
require_absent() { ! grep -Fq -- "$2" "$1" || fail "$3 unexpectedly contains '$2'"; }

command -v lake >/dev/null || fail "lake missing"
command -v solc >/dev/null || fail "solc missing"
command -v forge >/dev/null || fail "forge missing"
rm -rf "$OUT"
mkdir -p "$OUT"

lake build proof-forge ProofForge.Contract.Stdlib.ERC20Permit >/dev/null \
  || fail "lake build ERC20Permit"

lake env proof-forge build \
  --target evm \
  --token \
  --root . \
  --yul-output "$OUT/ERC20Permit.yul" \
  --artifact-output "$OUT/ERC20Permit.proof-forge-artifact.json" \
  -o "$OUT/ERC20Permit.bin" \
  Examples/Backend/Evm/TokenPermit.lean \
  || fail "ERC20Permit product build"

require_contains "$OUT/ERC20Permit.yul" "case 0xd505accf" "canonical permit selector"
require_contains "$OUT/ERC20Permit.yul" "__proof_forge_ecrecover" "ecrecover helper"
require_contains "$OUT/ERC20Permit.yul" "__proof_forge_eip712_permit_digest" "permit digest"
require_contains "$OUT/ERC20Permit.yul" \
  "57896044618658097711785492504343953926418782139537452191302581570759080747168" \
  "secp256k1 half-order low-s guard"
require_absent "$OUT/ERC20Permit.proof-forge-artifact.json" "setPermitSig" "atomic artifact"
require_absent "$OUT/ERC20Permit.proof-forge-artifact.json" "permitV" "atomic artifact"

python3 - "$OUT/ERC20Permit.proof-forge-artifact.json" <<'PY'
import json
import pathlib
import sys

spec = json.loads(pathlib.Path(sys.argv[1]).read_text())
permit = next(entry for entry in spec["abi"]["entrypoints"] if entry["name"] == "permit")
assert permit["selector"] == "d505accf", permit
assert permit["signature"] == "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)", permit
print("erc20-permit schema: canonical seven-argument atomic surface")
PY

mkdir -p "$FORGE_OUT/test"
cat >"$FORGE_OUT/foundry.toml" <<'TOML'
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc_version = "0.8.30"
optimizer = true
optimizer_runs = 200
TOML

cat >"$FORGE_OUT/test/ERC20Permit.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function addr(uint256 privateKey) external returns (address);
    function expectEmit(bool, bool, bool, bool, address) external;
    function sign(uint256 privateKey, bytes32 digest) external returns (uint8 v, bytes32 r, bytes32 s);
    function warp(uint256 timestamp) external;
}

contract ERC20PermitAtomicTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    bytes32 constant PERMIT_TYPEHASH =
        0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    uint256 constant SECP256K1_N =
        0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141;

    event Approval(address indexed owner, address indexed spender, uint256 value);

    address token;
    uint256 ownerKey = 0xA11CE;
    address owner;
    address spender = address(0xB0B);
    bytes32 domain = keccak256("proof-forge-permit-domain");

    function setUp() public {
        owner = vm.addr(ownerKey);
        token = deploy(hex"$(tr -d '\n' < "$OUT/ERC20Permit.bin")");
        (bool ok,) = token.call(abi.encodeWithSignature("initDomain(bytes32)", domain));
        require(ok, "domain init failed");
    }

    function deploy(bytes memory creationCode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(creationCode, 0x20), mload(creationCode))
        }
        require(deployed != address(0), "deployment failed");
    }

    function digest(bytes32 selectedDomain, uint256 value, uint256 selectedNonce, uint256 deadline)
        internal
        view
        returns (bytes32)
    {
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, owner, spender, value, selectedNonce, deadline)
        );
        return keccak256(abi.encodePacked(hex"1901", selectedDomain, structHash));
    }

    function permitCall(uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        internal
        returns (bool ok)
    {
        (ok,) = token.call(
            abi.encodeWithSignature(
                "permit(address,address,uint256,uint256,uint8,bytes32,bytes32)",
                owner, spender, value, deadline, v, r, s
            )
        );
    }

    function nonce() internal view returns (uint256 value) {
        (bool ok, bytes memory out) = token.staticcall(abi.encodeWithSignature("nonces(address)", owner));
        require(ok, "nonce query failed");
        value = abi.decode(out, (uint256));
    }

    function allowance() internal view returns (uint256 value) {
        (bool ok, bytes memory out) = token.staticcall(
            abi.encodeWithSignature("allowance(address,address)", owner, spender)
        );
        require(ok, "allowance query failed");
        value = abi.decode(out, (uint256));
    }

    function signed(bytes32 selectedDomain, uint256 value, uint256 selectedNonce, uint256 deadline)
        internal
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        return vm.sign(ownerKey, digest(selectedDomain, value, selectedNonce, deadline));
    }

    function assertUnchanged() internal view {
        require(nonce() == 0, "nonce changed on failure");
        require(allowance() == 0, "allowance changed on failure");
    }

    function testAtomicPermitAndReplayProtection() public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = signed(domain, 77, 0, deadline);
        vm.expectEmit(true, true, false, true, token);
        emit Approval(owner, spender, 77);
        require(permitCall(77, deadline, v, r, s), "valid permit failed");
        require(nonce() == 1, "nonce not incremented");
        require(allowance() == 77, "allowance not written");
        require(!permitCall(77, deadline, v, r, s), "replay accepted");
        require(nonce() == 1 && allowance() == 77, "replay mutated state");
    }

    function testExpiredDeadlineRejectsAtomically() public {
        vm.warp(100);
        (uint8 v, bytes32 r, bytes32 s) = signed(domain, 10, 0, 99);
        require(!permitCall(10, 99, v, r, s), "expired permit accepted");
        assertUnchanged();
    }

    function testBadDomainRejectsAtomically() public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = signed(keccak256("wrong-domain"), 10, 0, deadline);
        require(!permitCall(10, deadline, v, r, s), "bad-domain permit accepted");
        assertUnchanged();
    }

    function testHighSRejectsAtomically() public {
        uint256 deadline = block.timestamp + 1 days;
        (uint8 v, bytes32 r, bytes32 s) = signed(domain, 10, 0, deadline);
        bytes32 highS = bytes32(SECP256K1_N - uint256(s));
        uint8 flippedV = v == 27 ? 28 : 27;
        require(!permitCall(10, deadline, flippedV, r, highS), "high-s permit accepted");
        assertUnchanged();
    }

    function testInvalidVRejectsAtomically() public {
        uint256 deadline = block.timestamp + 1 days;
        (, bytes32 r, bytes32 s) = signed(domain, 10, 0, deadline);
        require(!permitCall(10, deadline, 29, r, s), "invalid-v permit accepted");
        assertUnchanged();
    }

    function testNoSignatureStagingOrDomainOverwrite() public {
        (bool staged,) = token.call(
            abi.encodeWithSignature("setPermitSig(uint256,bytes32,bytes32)", 27, bytes32(0), bytes32(0))
        );
        require(!staged, "signature staging surface exists");
        (bool overwritten,) = token.call(
            abi.encodeWithSignature("initDomain(bytes32)", keccak256("attacker-domain"))
        );
        require(!overwritten, "domain overwrite accepted");
        assertUnchanged();
    }
}
SOL

(cd "$FORGE_OUT" && forge test -vv) || fail "Foundry atomic permit attacks"

echo "product-erc20-permit: ok (atomic permit · nonce · domain · deadline · low-s · v)"
