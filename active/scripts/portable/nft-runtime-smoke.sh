#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.foundry/bin:$PATH"

OUT="${NFT_RUNTIME_OUT:-build/portable-nft-runtime}"
ARTIFACT_OUT="${NFT_RUNTIME_ARTIFACTS:-$OUT/artifacts}"
FORGE_ROOT="$OUT/foundry"
HOST=(cargo run --quiet --manifest-path runtime/offline-host/Cargo.toml -- run)

fail() { echo "portable-nft-runtime: FAIL: $1" >&2; exit 1; }
for tool in lake forge cargo python3; do
  command -v "$tool" >/dev/null 2>&1 || fail "$tool not on PATH"
done

rm -rf "$OUT"
mkdir -p "$OUT" "$FORGE_ROOT/test"
if [[ -z "${NFT_RUNTIME_ARTIFACTS:-}" ]]; then
  NFT_OUT="$ARTIFACT_OUT" scripts/portable/nft-multi-target.sh >/dev/null
fi

cat >"$FORGE_ROOT/foundry.toml" <<'TOML'
[profile.default]
src = "src"
test = "test"
out = "out"
TOML

cat >"$FORGE_ROOT/test/NftRuntime.t.sol" <<SOL
// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface Vm {
    function etch(address, bytes calldata) external;
    function prank(address) external;
}

contract NftRuntimeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ALICE = address(0xA11CE);
    address constant BOB = address(0xB0B);

    function testPortableNftLifecycle() public {
        address nft = address(0x721);
        vm.etch(nft, hex"$(cat "$ARTIFACT_OUT/evm/Nft.bin")");

        vm.prank(ALICE);
        (bool initOk,) = nft.call(abi.encodeWithSignature("init()"));
        require(initOk, "init failed");

        vm.prank(ALICE);
        (bool mintOk,) = nft.call(abi.encodeWithSignature("mint(address,uint256)", ALICE, 7));
        require(mintOk, "mint failed");

        vm.prank(ALICE);
        (bool duplicateOk,) = nft.call(abi.encodeWithSignature("mint(address,uint256)", ALICE, 7));
        require(!duplicateOk, "duplicate mint succeeded");

        (bool ownerOk, bytes memory ownerData) = nft.call(abi.encodeWithSignature("ownerOf(uint256)", 7));
        require(ownerOk && abi.decode(ownerData, (uint256)) == uint256(uint160(ALICE)), "owner after mint");

        vm.prank(BOB);
        (bool unauthorizedOk,) = nft.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", ALICE, BOB, 7));
        require(!unauthorizedOk, "unauthorized transfer succeeded");

        vm.prank(ALICE);
        (bool transferOk,) = nft.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", ALICE, BOB, 7));
        require(transferOk, "authorized transfer failed");

        (, ownerData) = nft.call(abi.encodeWithSignature("ownerOf(uint256)", 7));
        require(abi.decode(ownerData, (uint256)) == uint256(uint160(BOB)), "owner after transfer");
    }
}
SOL

forge test --root "$FORGE_ROOT" --match-test testPortableNftLifecycle >/dev/null
echo "portable-nft-runtime: EVM ok"

WAT="$ARTIFACT_OUT/near/nearnft.wat"
[[ -s "$WAT" ]] || fail "NEAR WAT missing"
eval "$(python3 - <<'PY'
import hashlib, struct
alice = hashlib.sha256(b"alice.testnet").digest()
bob = hashlib.sha256(b"bob.testnet").digest()
token = struct.pack("<Q", 7)
authorized = [b"", alice + token, token, alice, bob + token, token, alice, bob]
duplicate = [b"", alice + token, alice + token]
unauthorized = [b"", bob + token, alice + token]
print(f'AUTHORIZED="{",".join(x.hex() for x in authorized)}"')
print(f'DUPLICATE="{",".join(x.hex() for x in duplicate)}"')
print(f'UNAUTHORIZED="{",".join(x.hex() for x in unauthorized)}"')
PY
)"

near_out="$("${HOST[@]}" "$WAT" \
  init nft_mint nft_owner_of nft_balance_of nft_transfer nft_owner_of nft_balance_of nft_balance_of \
  --predecessor-account-id alice.testnet --signer-account-id alice.testnet \
  --inputs-hex "$AUTHORIZED")"
grep -Fq "return_u64=1" <<<"$near_out" || fail "NEAR balance did not reach one"
grep -Fq "return_u64=0" <<<"$near_out" || fail "NEAR sender balance did not reach zero"

if "${HOST[@]}" "$WAT" init nft_mint nft_mint \
    --predecessor-account-id alice.testnet --signer-account-id alice.testnet \
    --inputs-hex "$DUPLICATE" >/dev/null 2>&1; then
  fail "NEAR duplicate mint succeeded"
fi
if "${HOST[@]}" "$WAT" init nft_mint nft_transfer \
    --predecessor-account-id alice.testnet --signer-account-id alice.testnet \
    --inputs-hex "$UNAUTHORIZED" >/dev/null 2>&1; then
  fail "NEAR unauthorized transfer succeeded"
fi
echo "portable-nft-runtime: NEAR ok"

if [[ "${NFT_RUNTIME_SKIP_SOLANA:-0}" != "1" ]]; then
  PROOF_FORGE_SOLANA_NFT_ASM="$ARTIFACT_OUT/solana/Nft.s" \
    scripts/solana/nft-live-smoke.sh >/dev/null
  echo "portable-nft-runtime: Solana ok"
  echo "portable-nft-runtime: ok (evm · solana Surfpool · near Wasm)"
else
  echo "portable-nft-runtime: ok (evm · near Wasm; Solana skipped explicitly)"
fi
