#!/usr/bin/env bash
set -euo pipefail

# Compile the ProofForge EVM examples and run smoke tests with Foundry.
#
# This intentionally uses Forge's mature local EVM test runner, `vm.etch`
# for fast runtime checks, and one direct `create` initcode deployment check
# rather than a hand-rolled JSON-RPC harness.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${EVM_OUT_DIR:-$ROOT/build/evm}"
FORGE_DIR="${EVM_FORGE_DIR:-$ROOT/build/foundry-smoke}"

export PATH="$HOME/.foundry/bin:$PATH"

if ! command -v forge >/dev/null 2>&1; then
  echo "foundry-smoke: forge not found. Install Foundry, then re-run this script." >&2
  echo "foundry-smoke: https://getfoundry.sh/" >&2
  exit 127
fi

"$ROOT/scripts/evm/build-examples.sh"

python3 - "$OUT_DIR/Create2FactoryProbe.proof-forge-artifact.json" \
  "$OUT_DIR/Create2Factory.proof-forge-artifact.json" <<'PY'
import json
import sys
from pathlib import Path

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    artifact = json.loads(path.read_text())
    deploy = next(ep for ep in artifact["abi"]["entrypoints"] if ep["name"] == "deploy")
    event = next(event for event in artifact["abi"]["events"] if event["name"] == "Deployed")
    assert deploy["returns"] == "Address", f"{path}: deploy return IR type"
    assert deploy["returnValue"]["abiType"] == "address", f"{path}: deploy return ABI type"
    assert deploy["returnValue"]["wordTypes"] == ["address"], f"{path}: deploy return words"
    assert event["signature"] == "Deployed(address,bytes32)", f"{path}: deployed event signature"
    assert event["indexedFields"][0]["name"] == "addr", f"{path}: deployed address field"
    assert event["indexedFields"][0]["type"] == "address", f"{path}: deployed address ABI type"
    assert event["indexedFields"][0]["irType"] == "Address", f"{path}: deployed address IR type"

print("foundry-smoke: CREATE2 factory address ABI metadata ok")
PY

python3 - \
  "$OUT_DIR/CounterUUPSImpl.proof-forge-artifact.json" \
  "$OUT_DIR/Ownable.proof-forge-artifact.json" \
  "$OUT_DIR/AccessControlProbe.proof-forge-artifact.json" \
  "$OUT_DIR/ERC721Probe.proof-forge-artifact.json" \
  "$OUT_DIR/ERC1155.proof-forge-artifact.json" \
  "$OUT_DIR/ERC4626.proof-forge-artifact.json" <<'PY'
import json
import sys
from pathlib import Path

expected = {
    "CounterUUPSImpl": {
        "Upgraded": ("Upgraded(address)", ["address"]),
    },
    "Ownable": {
        "OwnershipTransferred": ("OwnershipTransferred(address,address)", ["address", "address"]),
    },
    "AccessControlProbe": {
        "RoleAdminChanged": ("RoleAdminChanged(bytes32,bytes32,bytes32)", ["bytes32", "bytes32", "bytes32"]),
        "RoleGranted": ("RoleGranted(bytes32,address,address)", ["bytes32", "address", "address"]),
        "RoleRevoked": ("RoleRevoked(bytes32,address,address)", ["bytes32", "address", "address"]),
    },
    "ERC721Probe": {
        "Transfer": ("Transfer(address,address,uint256)", ["address", "address", "uint256"]),
    },
    "ERC1155": {
        "ApprovalForAll": ("ApprovalForAll(address,address,bool)", ["address", "address", "bool"]),
        "TransferSingle": (
            "TransferSingle(address,address,address,uint256,uint256)",
            ["address", "address", "address", "uint256", "uint256"],
        ),
    },
    "ERC4626": {
        "Deposit": ("Deposit(address,address,uint256,uint256)", ["address", "address", "uint256", "uint256"]),
        "Withdraw": (
            "Withdraw(address,address,address,uint256,uint256)",
            ["address", "address", "address", "uint256", "uint256"],
        ),
    },
}

for raw_path in sys.argv[1:]:
    path = Path(raw_path)
    artifact = json.loads(path.read_text())
    fixture = artifact["fixture"]
    events = {event["name"]: event for event in artifact["abi"]["events"]}
    for name, (signature, field_types) in expected[fixture].items():
        event = events[name]
        actual_types = [
            field["type"]
            for field in event["indexedFields"] + event["dataFields"]
        ]
        assert event["signature"] == signature, f"{path}: {name} signature"
        assert actual_types == field_types, f"{path}: {name} field ABI types"

print("foundry-smoke: standard event ABI metadata ok")
PY

if [[ -n "${PROOF_FORGE_BIN:-}" ]]; then
  proof_forge=("$PROOF_FORGE_BIN")
else
  proof_forge=(lake env proof-forge)
fi

# Build constructor-init initcode fixtures without disturbing the default
# Counter.init.bin used by testCounterInitCodeDeploysRuntime().
rebuild_constructor_init_fixture() {
  local name="$1"
  local lean_file="$2"
  shift 2
  (
    cd "$ROOT"
    "${proof_forge[@]}" build \
      --target evm \
      --root . \
      --yul-output "$OUT_DIR/$name.yul" \
      --artifact-output "$OUT_DIR/$name.proof-forge-artifact.json" \
      -o "$OUT_DIR/$name.ctor.bin" \
      "$@" \
      "$lean_file"
    diff -u "${lean_file%.lean}.golden.yul" "$OUT_DIR/$name.yul"
  )
}

NAME_HASH="$(cast keccak hello | sed 's/^0x//')"
PAYLOAD_HASH="$(cast keccak 0xdeadbeef | sed 's/^0x//')"

rebuild_constructor_init_fixture DynamicConstructorProbe "$ROOT/Examples/Backend/Evm/Contracts/DynamicConstructorProbe.lean" \
  --evm-constructor-arg "name=hello" \
  --evm-constructor-arg "payload=0xdeadbeef" \
  --evm-constructor-arg "amounts=1,2,3"

rebuild_constructor_init_fixture Counter "$ROOT/Examples/Backend/Evm/Contracts/Counter.lean" \
  --evm-constructor-arg "initial=123"

# PF-P2-03: RemoteCall with deploy-time peer address for real CALL peer equivalence.
(
  cd "$ROOT"
  "${proof_forge[@]}" build \
    --target evm \
    --root . \
    --peer "peer.callee=0x000000000000000000000000000000000000b0b0" \
    --yul-output "$OUT_DIR/RemoteCall.peer.yul" \
    --artifact-output "$OUT_DIR/RemoteCall.peer.proof-forge-artifact.json" \
    -o "$OUT_DIR/RemoteCall.peer.bin" \
    Examples/Product/RemoteCall.lean
  # CALL target must be the peer address (0xb0b0 = 45232), method selector remote_call(uint256,uint256).
  grep -Fq '4054714009' "$OUT_DIR/RemoteCall.peer.yul" \
    || { echo "foundry-smoke: RemoteCall.peer.yul missing remote_call selector" >&2; exit 1; }
  grep -Fq '45232' "$OUT_DIR/RemoteCall.peer.yul" \
    || { echo "foundry-smoke: RemoteCall.peer.yul missing peer address word 0xb0b0=45232" >&2; exit 1; }
)

rm -rf "$FORGE_DIR"
mkdir -p "$FORGE_DIR/test"

cat > "$FORGE_DIR/foundry.toml" <<'TOML'
[profile.default]
src = "src"
test = "test"
out = "out"
libs = ["lib"]
solc_version = "0.8.30"
optimizer = true
optimizer_runs = 200
via_ir = true
TOML

cat > "$FORGE_DIR/test/ProofForgeSmoke.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function deal(address who, uint256 newBalance) external;
    function prank(address msgSender) external;
    function store(address target, bytes32 slot, bytes32 value) external;
    function expectEmit(bool checkTopic1, bool checkTopic2, bool checkTopic3, bool checkData, address emitter)
        external;
}

/// PF-P2-02: IERC721Receiver that returns the required magic.
contract GoodReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}

/// PF-P2-02: IERC721Receiver that returns the wrong selector.
contract BadReceiver {
    function onERC721Received(address, address, uint256, bytes calldata) external pure returns (bytes4) {
        return bytes4(0xdeadbeef);
    }
}

/// PF-P2-02: IERC1155Receiver that returns the required magic.
contract Good1155Receiver {
    address public batchOperator;
    address public batchFrom;
    uint256 public batchId0;
    uint256 public batchId1;
    uint256 public batchAmount0;
    uint256 public batchAmount1;
    uint256 public batchDataLength;
    uint256 public batchCalls;

    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return this.onERC1155Received.selector;
    }

    // E1.2: also accept batch receiver magic.
    function onERC1155BatchReceived(
        address operator,
        address from,
        uint256[] calldata ids,
        uint256[] calldata amounts,
        bytes calldata data
    ) external returns (bytes4) {
        require(ids.length == 2, "expected two ids");
        require(amounts.length == 2, "expected two amounts");
        batchOperator = operator;
        batchFrom = from;
        batchId0 = ids[0];
        batchId1 = ids[1];
        batchAmount0 = amounts[0];
        batchAmount1 = amounts[1];
        batchDataLength = data.length;
        batchCalls += 1;
        return this.onERC1155BatchReceived.selector;
    }
}

/// PF-P2-02: IERC1155Receiver that returns the wrong selector.
contract Bad1155Receiver {
    function onERC1155Received(address, address, uint256, uint256, bytes calldata)
        external
        pure
        returns (bytes4)
    {
        return bytes4(0xdeadbeef);
    }

    function onERC1155BatchReceived(
        address,
        address,
        uint256[] calldata,
        uint256[] calldata,
        bytes calldata
    ) external pure returns (bytes4) {
        return bytes4(0xdeadbeef);
    }
}

/// PF-P2-03: peer oracle for RemoteCall.call_with_args (42 + 7 = 49).
contract PeerOracle {
    function remote_call(uint256 a, uint256 b) external pure returns (uint256) {
        return a + b;
    }
}

/// Minimal ERC-20 used to exercise ERC-4626 pull/push accounting.
contract ERC4626AssetMock {
    mapping(address => uint256) public balanceOf;
    uint256 public transferFeeBps;
    bool public failTransferFrom;
    bool public suppressTransferFromMove;
    bool public failTransfer;
    bool public suppressTransferMove;
    uint256 public falseTransferCall;
    uint256 public transferFromCalls;
    uint256 public transferCalls;
    address public callbackVault;
    uint8 public callbackMode;
    bool public callbackAttempted;
    bool public callbackSucceeded;
    bool private callbackActive;

    function setTransferFeeBps(uint256 value) external {
        require(value <= 10_000, "fee too high");
        transferFeeBps = value;
    }

    function mint(address recipient, uint256 amount) external {
        balanceOf[recipient] += amount;
    }

    function setTransferFromBehavior(bool result, bool moves) external {
        failTransferFrom = !result;
        suppressTransferFromMove = !moves;
    }

    function setTransferBehavior(bool result, bool moves) external {
        failTransfer = !result;
        suppressTransferMove = !moves;
    }

    function setFalseTransferCall(uint256 callNumber) external {
        falseTransferCall = callNumber;
    }

    function setCallback(address vault, uint8 mode) external {
        callbackVault = vault;
        callbackMode = mode;
        callbackAttempted = false;
        callbackSucceeded = false;
    }

    function tryCallback(uint8 mode) internal {
        if (callbackMode != mode || callbackActive) return;
        callbackActive = true;
        callbackAttempted = true;
        (callbackSucceeded,) = callbackVault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 1, address(this))
        );
        callbackActive = false;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        transferFromCalls += 1;
        tryCallback(1);
        if (!suppressTransferFromMove) {
            require(balanceOf[from] >= amount, "insufficient mock balance");
            balanceOf[from] -= amount;
            balanceOf[to] += amount - (amount * transferFeeBps / 10_000);
        }
        return !failTransferFrom;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        transferCalls += 1;
        tryCallback(2);
        bool forcedFalse = falseTransferCall != 0 && transferCalls == falseTransferCall;
        bool moves = forcedFalse ? false : !suppressTransferMove;
        if (moves) {
            require(balanceOf[msg.sender] >= amount, "insufficient mock balance");
            balanceOf[msg.sender] -= amount;
            balanceOf[to] += amount - (amount * transferFeeBps / 10_000);
        }
        return forcedFalse ? false : !failTransfer;
    }
}

contract ProofForgeSmokeTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));
    address constant ERC4626_ACTOR = address(0xA11CE4626);

    event Deployed(address indexed addr, bytes32 indexed salt);
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);
    event ApprovalForAll(address indexed account, address indexed operator, bool approved);
    event TransferSingle(
        address indexed operator,
        address indexed from,
        address indexed to,
        uint256 id,
        uint256 value
    );
    event Deposit(address indexed sender, address indexed owner, uint256 assets, uint256 shares);
    event Withdraw(
        address indexed sender,
        address indexed receiver,
        address indexed owner,
        uint256 assets,
        uint256 shares
    );
    event Upgraded(address indexed implementation);
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    function assertTrue(bool value) internal pure {
        require(value, "assertTrue failed");
    }

    function assertFalse(bool value) internal pure {
        require(!value, "assertFalse failed");
    }

    function assertEq(uint256 actual, uint256 expected) internal pure {
        require(actual == expected, "assertEq failed");
    }

    function deployRuntime(bytes memory code, address target) internal {
        vm.etch(target, code);
    }

    function deployInitCode(bytes memory initCode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
        require(deployed != address(0), "create failed");
    }

    function expectedCreate2Address(address deployer, bytes32 salt, bytes32 initCodeHash) internal pure returns (address) {
        return address(uint160(uint256(keccak256(abi.encodePacked(bytes1(0xff), deployer, salt, initCodeHash)))));
    }

    function callRuntime42(address target) internal returns (uint256) {
        (bool ok, bytes memory result) = target.call("");
        require(ok, "runtime call failed");
        return abi.decode(result, (uint256));
    }

    function callUint(address target, bytes memory data) internal view returns (uint256) {
        (bool ok, bytes memory result) = target.staticcall(data);
        require(ok, "uint call failed");
        return abi.decode(result, (uint256));
    }

    function setERC4626State(
        address vault,
        address asset,
        uint256 totalAssets_,
        uint256 totalSupply_,
        uint256 feeBps_,
        address feeRecipient_
    ) internal {
        // Address slots are full 160-bit words; adjacent u64 fields use the
        // remaining packed bytes where available.
        vm.store(vault, bytes32(uint256(0)), bytes32(uint256(uint160(asset))));
        vm.store(
            vault,
            bytes32(uint256(1)),
            bytes32(uint256(uint160(vault)) | (totalAssets_ << 160))
        );
        vm.store(vault, bytes32(uint256(2)), bytes32(totalSupply_));
        vm.store(vault, bytes32(uint256(3)), bytes32(feeBps_ << 192));
        vm.store(vault, bytes32(uint256(4)), bytes32(uint256(uint160(feeRecipient_))));
    }

    function setERC4626ShareBalance(address vault, address holder, uint256 amount) internal {
        vm.store(vault, keccak256(abi.encode(uint256(uint160(holder)), uint256(6))), bytes32(amount));
    }

    function installERC4626(
        address vault,
        address asset,
        uint256 totalAssets_,
        uint256 totalSupply_,
        uint256 feeBps_,
        address feeRecipient_,
        uint256 holderShares,
        uint256 vaultAssets,
        uint256 callerAssets
    ) internal {
        deployRuntime(hex"$(cat "$OUT_DIR/ERC4626.bin")", vault);
        ERC4626AssetMock template = new ERC4626AssetMock();
        vm.etch(asset, address(template).code);
        setERC4626State(vault, asset, totalAssets_, totalSupply_, feeBps_, feeRecipient_);
        setERC4626ShareBalance(vault, ERC4626_ACTOR, holderShares);
        ERC4626AssetMock(asset).mint(vault, vaultAssets);
        ERC4626AssetMock(asset).mint(ERC4626_ACTOR, callerAssets);
    }

    function assertCounterLifecycle(address counter) internal {
        (bool initOk,) = counter.call(abi.encodeWithSignature("initialize()"));
        assertTrue(initOk);

        (bool ok0, bytes memory r0) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok0);
        assertEq(abi.decode(r0, (uint256)), 0);

        (bool ok1,) = counter.call(abi.encodeWithSignature("increment()"));
        assertTrue(ok1);

        (bool ok2, bytes memory r2) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok2);
        assertEq(abi.decode(r2, (uint256)), 1);

        (bool ok3,) = counter.call(abi.encodeWithSignature("increment()"));
        assertTrue(ok3);

        (bool ok4, bytes memory r4) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok4);
        assertEq(abi.decode(r4, (uint256)), 2);
    }

    function testCounterLifecycle() public {
        address counter = address(0xCAFE);
        deployRuntime(hex"$(cat "$OUT_DIR/Counter.bin")", counter);
        assertCounterLifecycle(counter);
    }

    function testCounterInitCodeDeploysRuntime() public {
        address counter = deployInitCode(hex"$(cat "$OUT_DIR/Counter.init.bin")");
        assertCounterLifecycle(counter);
    }

    function testCounterConstructorInitBindsInitial() public {
        address counter = deployInitCode(hex"$(cat "$OUT_DIR/Counter.ctor.init.bin")");
        (bool ok, bytes memory result) = counter.call(abi.encodeWithSignature("get()"));
        assertTrue(ok);
        assertEq(abi.decode(result, (uint256)), 123);
    }

    function testDynamicConstructorProbeInitCodeBindsStorage() public {
        address probe = deployInitCode(hex"$(cat "$OUT_DIR/DynamicConstructorProbe.ctor.init.bin")");
        (bool ok0, bytes memory r0) = probe.call(abi.encodeWithSignature("getNameLen()"));
        (bool ok1, bytes memory r1) = probe.call(abi.encodeWithSignature("getNameHash()"));
        (bool ok2, bytes memory r2) = probe.call(abi.encodeWithSignature("getPayloadLen()"));
        (bool ok3, bytes memory r3) = probe.call(abi.encodeWithSignature("getPayloadHash()"));
        (bool ok4, bytes memory r4) = probe.call(abi.encodeWithSignature("getAmountCount()"));
        (bool ok5, bytes memory r5) = probe.call(abi.encodeWithSignature("getAmountSum()"));
        assertTrue(ok0 && ok1 && ok2 && ok3 && ok4 && ok5);
        assertEq(abi.decode(r0, (uint256)), 5);
        assertEq(abi.decode(r1, (uint256)), uint256(bytes32(hex"$NAME_HASH")));
        assertEq(abi.decode(r2, (uint256)), 4);
        assertEq(abi.decode(r3, (uint256)), uint256(bytes32(hex"$PAYLOAD_HASH")));
        assertEq(abi.decode(r4, (uint256)), 3);
        assertEq(abi.decode(r5, (uint256)), 6);
    }

    function testArrayExample() public {
        address arrayExample = address(0xA7);
        deployRuntime(hex"$(cat "$OUT_DIR/ArrayExample.bin")", arrayExample);

        (bool ok0, bytes memory r0) = arrayExample.call(abi.encodeWithSignature("sizeOf3()"));
        assertTrue(ok0);
        assertEq(abi.decode(r0, (uint256)), 3);

        (bool ok1, bytes memory r1) = arrayExample.call(abi.encodeWithSignature("getElem()"));
        assertTrue(ok1);
        assertEq(abi.decode(r1, (uint256)), 20);

        (bool ok2, bytes memory r2) = arrayExample.call(abi.encodeWithSignature("sumOf3()"));
        assertTrue(ok2);
        assertEq(abi.decode(r2, (uint256)), 60);
    }

    function testSimpleTokenLifecycle() public {
        address token = address(0x70C);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/SimpleToken.bin")", token);

        vm.prank(alice);
        (bool ok0,) = token.call(abi.encodeWithSignature("init(uint256)", uint256(1_000_000)));
        assertTrue(ok0);

        (bool ok1, bytes memory r1) = token.call(abi.encodeWithSignature("owner()"));
        assertTrue(ok1);
        assertEq(abi.decode(r1, (uint256)), uint256(uint160(alice)));

        (bool ok2, bytes memory r2) = token.call(abi.encodeWithSignature("totalSupply()"));
        assertTrue(ok2);
        assertEq(abi.decode(r2, (uint256)), 1_000_000);

        vm.prank(alice);
        (bool ok3,) = token.call(abi.encodeWithSignature("transfer(address,uint256)", bob, uint256(300_000)));
        assertTrue(ok3);

        (, bytes memory aliceBal) = token.call(abi.encodeWithSignature("balanceOf(address)", alice));
        assertEq(abi.decode(aliceBal, (uint256)), 700_000);

        (, bytes memory bobBal) = token.call(abi.encodeWithSignature("balanceOf(address)", bob));
        assertEq(abi.decode(bobBal, (uint256)), 300_000);

        vm.prank(bob);
        (bool overdraftOk,) = token.call(abi.encodeWithSignature("transfer(address,uint256)", alice, uint256(999_999)));
        assertFalse(overdraftOk);
    }

    function testERC4626InversePreviewsRoundUp() public {
        address vault = address(0x4626);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC4626.bin")", vault);
        setERC4626State(vault, address(0), 2, 3, 0, address(0));

        assertEq(callUint(vault, abi.encodeWithSignature("previewMint(uint256)", 1)), 1);
        assertEq(callUint(vault, abi.encodeWithSignature("previewWithdraw(uint256)", 1)), 2);
        assertEq(callUint(vault, abi.encodeWithSignature("previewMint(uint256)", 0)), 0);
        assertEq(callUint(vault, abi.encodeWithSignature("previewWithdraw(uint256)", 0)), 0);

        setERC4626State(vault, address(0), 6, 3, 0, address(0));
        assertEq(callUint(vault, abi.encodeWithSignature("previewMint(uint256)", 1)), 2);
        assertEq(callUint(vault, abi.encodeWithSignature("previewWithdraw(uint256)", 2)), 1);

        setERC4626State(vault, address(0), 2, 3, 100, address(0xFEE));
        assertEq(callUint(vault, abi.encodeWithSignature("previewMint(uint256)", 990)), 667);

        (bool mintOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewMint(uint256)", type(uint256).max)
        );
        assertFalse(mintOverflow);
        (bool withdrawOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewWithdraw(uint256)", type(uint256).max)
        );
        assertFalse(withdrawOverflow);

        uint256 maxU64 = type(uint64).max;
        setERC4626State(vault, address(0), maxU64, 1, 0, address(0));
        (bool mintWidthOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewMint(uint256)", maxU64)
        );
        assertFalse(mintWidthOverflow);
        setERC4626State(vault, address(0), 1, maxU64, 0, address(0));
        (bool withdrawWidthOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewWithdraw(uint256)", maxU64)
        );
        assertFalse(withdrawWidthOverflow);

        setERC4626State(vault, address(0), 1, maxU64, 0, address(0));
        (bool depositWidthOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewDeposit(uint256)", maxU64)
        );
        assertFalse(depositWidthOverflow);
        setERC4626State(vault, address(0), maxU64, 1, 0, address(0));
        (bool redeemWidthOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewRedeem(uint256)", maxU64)
        );
        assertFalse(redeemWidthOverflow);

        setERC4626State(vault, address(0), 0, 0, 0, address(0));
        (bool depositInputWidthOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewDeposit(uint256)", type(uint256).max)
        );
        assertFalse(depositInputWidthOverflow);
        (bool redeemInputWidthOverflow,) = vault.staticcall(
            abi.encodeWithSignature("previewRedeem(uint256)", type(uint256).max)
        );
        assertFalse(redeemInputWidthOverflow);
    }

    function testERC4626MintAndWithdrawMatchRoundedPreviews() public {
        address mintVault = address(0x4627);
        address mintAsset = address(0xA5501);
        installERC4626(mintVault, mintAsset, 2, 3, 0, address(0xFEE), 0, 2, 1);
        uint256 mintPreview = callUint(
            mintVault, abi.encodeWithSignature("previewMint(uint256)", 1)
        );
        vm.prank(ERC4626_ACTOR);
        (bool mintOk, bytes memory mintResult) =
            mintVault.call(abi.encodeWithSignature("mint(uint256,address)", 1, ERC4626_ACTOR));
        assertTrue(mintOk);
        assertEq(mintPreview, 1);
        assertEq(abi.decode(mintResult, (uint256)), mintPreview);
        assertEq(callUint(mintVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 1);
        assertEq(callUint(mintVault, abi.encodeWithSignature("totalAssets()")), 3);
        assertEq(callUint(mintVault, abi.encodeWithSignature("totalSupply()")), 4);

        address withdrawVault = address(0x4628);
        address withdrawAsset = address(0xA5502);
        installERC4626(withdrawVault, withdrawAsset, 2, 3, 0, address(0xFEE), 3, 2, 0);
        uint256 withdrawPreview = callUint(
            withdrawVault, abi.encodeWithSignature("previewWithdraw(uint256)", 1)
        );
        vm.prank(ERC4626_ACTOR);
        (bool withdrawOk, bytes memory withdrawResult) = withdrawVault.call(
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)", 1, ERC4626_ACTOR, ERC4626_ACTOR
            )
        );
        assertTrue(withdrawOk);
        assertEq(withdrawPreview, 2);
        assertEq(abi.decode(withdrawResult, (uint256)), withdrawPreview);
        assertEq(callUint(withdrawVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 1);
        assertEq(callUint(withdrawVault, abi.encodeWithSignature("totalAssets()")), 1);
        assertEq(callUint(withdrawVault, abi.encodeWithSignature("totalSupply()")), 1);
    }

    function testERC4626FeePathsMatchRoundedPreviews() public {
        address feeRecipient = address(0xFEE);
        address mintVault = address(0x4629);
        address mintAsset = address(0xA5503);
        installERC4626(mintVault, mintAsset, 2, 3, 100, feeRecipient, 0, 2, 667);
        uint256 mintPreview = callUint(
            mintVault, abi.encodeWithSignature("previewMint(uint256)", 990)
        );
        vm.prank(ERC4626_ACTOR);
        (bool mintOk, bytes memory mintResult) =
            mintVault.call(abi.encodeWithSignature("mint(uint256,address)", 990, ERC4626_ACTOR));
        assertTrue(mintOk);
        assertEq(mintPreview, 667);
        assertEq(abi.decode(mintResult, (uint256)), mintPreview);
        assertEq(callUint(mintVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 990);
        assertEq(callUint(mintVault, abi.encodeWithSignature("balanceOf(address)", feeRecipient)), 10);

        address withdrawVault = address(0x4630);
        address withdrawAsset = address(0xA5504);
        installERC4626(withdrawVault, withdrawAsset, 200, 300, 100, feeRecipient, 300, 200, 0);
        uint256 withdrawPreview = callUint(
            withdrawVault, abi.encodeWithSignature("previewWithdraw(uint256)", 100)
        );
        vm.prank(ERC4626_ACTOR);
        (bool withdrawOk, bytes memory withdrawResult) = withdrawVault.call(
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)", 100, ERC4626_ACTOR, ERC4626_ACTOR
            )
        );
        assertTrue(withdrawOk);
        assertEq(withdrawPreview, 150);
        assertEq(abi.decode(withdrawResult, (uint256)), withdrawPreview);
        assertEq(ERC4626AssetMock(withdrawAsset).balanceOf(ERC4626_ACTOR), 99);
        assertEq(ERC4626AssetMock(withdrawAsset).balanceOf(feeRecipient), 1);
    }

    function testERC4626MintUsesActualOnlyAsCoverage() public {
        address surplusVault = address(0x4631);
        address surplusAsset = address(0xA5505);
        installERC4626(surplusVault, surplusAsset, 2, 100, 0, address(0xFEE), 0, 2, 1);
        assertEq(callUint(surplusVault, abi.encodeWithSignature("previewMint(uint256)", 1)), 1);
        vm.prank(ERC4626_ACTOR);
        (bool surplusOk,) =
            surplusVault.call(abi.encodeWithSignature("mint(uint256,address)", 1, ERC4626_ACTOR));
        assertTrue(surplusOk);
        assertEq(callUint(surplusVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 1);
        assertEq(callUint(surplusVault, abi.encodeWithSignature("totalSupply()")), 101);

        address fotVault = address(0x4632);
        address fotAsset = address(0xA5506);
        installERC4626(fotVault, fotAsset, 200, 300, 0, address(0xFEE), 0, 200, 100);
        ERC4626AssetMock(fotAsset).setTransferFeeBps(100);
        assertEq(callUint(fotVault, abi.encodeWithSignature("previewMint(uint256)", 150)), 100);
        vm.prank(ERC4626_ACTOR);
        (bool fotOk,) =
            fotVault.call(abi.encodeWithSignature("mint(uint256,address)", 150, ERC4626_ACTOR));
        assertFalse(fotOk);
        assertEq(callUint(fotVault, abi.encodeWithSignature("totalAssets()")), 200);
        assertEq(callUint(fotVault, abi.encodeWithSignature("totalSupply()")), 300);
    }

    function testERC4626MaxLimitsAreExecutable() public {
        uint256 maxU64 = type(uint64).max;

        address depositVault = address(0x4633);
        address depositAsset = address(0xA5507);
        installERC4626(
            depositVault,
            depositAsset,
            maxU64 - 2,
            maxU64 - 3,
            0,
            address(0xFEE),
            0,
            maxU64 - 2,
            2
        );
        uint256 depositLimit = callUint(
            depositVault, abi.encodeWithSignature("maxDeposit(address)", ERC4626_ACTOR)
        );
        // 1 asset converts to zero shares; 2 * totalSupply overflows U64.
        assertEq(depositLimit, 0);

        address mintVault = address(0x4634);
        address mintAsset = address(0xA5508);
        installERC4626(
            mintVault,
            mintAsset,
            maxU64 - 2,
            maxU64 - 3,
            0,
            address(0xFEE),
            0,
            maxU64 - 2,
            2
        );
        uint256 mintLimit = callUint(
            mintVault, abi.encodeWithSignature("maxMint(address)", ERC4626_ACTOR)
        );
        // Minting one share pulls two assets, then 2 * totalSupply overflows U64.
        assertEq(mintLimit, 0);

        address feeMintVault = address(0x4638);
        address feeMintAsset = address(0xA5512);
        installERC4626(
            feeMintVault,
            feeMintAsset,
            maxU64 - 200,
            maxU64 - 300,
            100,
            address(0xFEE),
            0,
            maxU64 - 200,
            200
        );
        uint256 feeMintLimit = callUint(
            feeMintVault, abi.encodeWithSignature("maxMint(address)", ERC4626_ACTOR)
        );
        assertEq(feeMintLimit, 0);

        uint256 safeLimit = maxU64 / 100;
        address safeDepositVault = address(0x4639);
        address safeDepositAsset = address(0xA5513);
        installERC4626(
            safeDepositVault,
            safeDepositAsset,
            100,
            100,
            0,
            address(0),
            0,
            100,
            safeLimit
        );
        assertEq(
            callUint(safeDepositVault, abi.encodeWithSignature("maxDeposit(address)", ERC4626_ACTOR)),
            safeLimit
        );
        vm.prank(ERC4626_ACTOR);
        (bool safeDepositOk,) = safeDepositVault.call(
            abi.encodeWithSignature("deposit(uint256,address)", safeLimit, ERC4626_ACTOR)
        );
        assertTrue(safeDepositOk);

        address safeMintVault = address(0x463A);
        address safeMintAsset = address(0xA5514);
        installERC4626(
            safeMintVault,
            safeMintAsset,
            100,
            100,
            0,
            address(0),
            0,
            100,
            safeLimit
        );
        assertEq(
            callUint(safeMintVault, abi.encodeWithSignature("maxMint(address)", ERC4626_ACTOR)),
            safeLimit
        );
        vm.prank(ERC4626_ACTOR);
        (bool safeMintOk,) = safeMintVault.call(
            abi.encodeWithSignature("mint(uint256,address)", safeLimit, ERC4626_ACTOR)
        );
        assertTrue(safeMintOk);

        address narrowWithdrawVault = address(0x463B);
        address narrowWithdrawAsset = address(0xA5515);
        installERC4626(
            narrowWithdrawVault,
            narrowWithdrawAsset,
            maxU64 - 2,
            maxU64 - 3,
            0,
            address(0),
            2,
            maxU64 - 2,
            0
        );
        uint256 narrowWithdrawLimit = callUint(
            narrowWithdrawVault, abi.encodeWithSignature("maxWithdraw(address)", ERC4626_ACTOR)
        );
        assertEq(narrowWithdrawLimit, 1);
        vm.prank(ERC4626_ACTOR);
        (bool narrowWithdrawOk,) = narrowWithdrawVault.call(
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)", narrowWithdrawLimit, ERC4626_ACTOR, ERC4626_ACTOR
            )
        );
        assertTrue(narrowWithdrawOk);

        address narrowRedeemVault = address(0x463C);
        address narrowRedeemAsset = address(0xA5516);
        installERC4626(
            narrowRedeemVault,
            narrowRedeemAsset,
            maxU64 - 2,
            maxU64 - 3,
            0,
            address(0),
            2,
            maxU64 - 2,
            0
        );
        uint256 narrowRedeemLimit = callUint(
            narrowRedeemVault, abi.encodeWithSignature("maxRedeem(address)", ERC4626_ACTOR)
        );
        assertEq(narrowRedeemLimit, 1);
        vm.prank(ERC4626_ACTOR);
        (bool narrowRedeemOk,) = narrowRedeemVault.call(
            abi.encodeWithSignature(
                "redeem(uint256,address,address)", narrowRedeemLimit, ERC4626_ACTOR, ERC4626_ACTOR
            )
        );
        assertTrue(narrowRedeemOk);

        address withdrawVault = address(0x4635);
        address withdrawAsset = address(0xA5509);
        installERC4626(withdrawVault, withdrawAsset, 200, 300, 100, address(0xFEE), 300, 200, 0);
        uint256 withdrawLimit = callUint(
            withdrawVault, abi.encodeWithSignature("maxWithdraw(address)", ERC4626_ACTOR)
        );
        assertEq(withdrawLimit, 200);
        vm.prank(ERC4626_ACTOR);
        (bool withdrawOk, bytes memory withdrawResult) = withdrawVault.call(
            abi.encodeWithSignature(
                "withdraw(uint256,address,address)", withdrawLimit, ERC4626_ACTOR, ERC4626_ACTOR
            )
        );
        assertTrue(withdrawOk);
        assertEq(abi.decode(withdrawResult, (uint256)), 300);

        address redeemVault = address(0x4636);
        address redeemAsset = address(0xA5510);
        installERC4626(redeemVault, redeemAsset, 200, 300, 100, address(0xFEE), 300, 200, 0);
        uint256 redeemLimit = callUint(
            redeemVault, abi.encodeWithSignature("maxRedeem(address)", ERC4626_ACTOR)
        );
        assertEq(redeemLimit, 300);
        vm.prank(ERC4626_ACTOR);
        (bool redeemOk,) = redeemVault.call(
            abi.encodeWithSignature(
                "redeem(uint256,address,address)", redeemLimit, ERC4626_ACTOR, ERC4626_ACTOR
            )
        );
        assertTrue(redeemOk);
    }

    function testERC4626HundredPercentFeeDisablesMaxLimits() public {
        address vault = address(0x4637);
        address asset = address(0xA5511);
        installERC4626(vault, asset, 200, 300, 10_000, address(0xFEE), 300, 200, 100);
        assertEq(callUint(vault, abi.encodeWithSignature("maxDeposit(address)", ERC4626_ACTOR)), 0);
        assertEq(callUint(vault, abi.encodeWithSignature("maxMint(address)", ERC4626_ACTOR)), 0);
        assertEq(callUint(vault, abi.encodeWithSignature("maxWithdraw(address)", ERC4626_ACTOR)), 0);
        assertEq(callUint(vault, abi.encodeWithSignature("maxRedeem(address)", ERC4626_ACTOR)), 0);
    }

    function testERC4626InitPreservesFullWidthAddressesAndCannotRepeat() public {
        address vault = address(0x1234567890AbCdEF1234567890abCDEF12344626);
        address asset = address(0xa234567890abcdEf1234567890AbcDEF1234A551);
        address recipient = address(0xF234567890abcDEf1234567890AbcDef12340fEE);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC4626.bin")", vault);
        ERC4626AssetMock template = new ERC4626AssetMock();
        vm.etch(asset, address(template).code);

        (bool initOk,) = vault.call(
            abi.encodeWithSignature("init(address,address,uint256,address)", asset, vault, 100, recipient)
        );
        assertTrue(initOk);
        assertEq(callUint(vault, abi.encodeWithSignature("asset()")), uint256(uint160(asset)));
        assertEq(callUint(vault, abi.encodeWithSignature("feeRecipient()")), uint256(uint160(recipient)));

        ERC4626AssetMock(asset).mint(ERC4626_ACTOR, 10);
        vm.prank(ERC4626_ACTOR);
        (bool depositOk,) = vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 10, ERC4626_ACTOR)
        );
        assertTrue(depositOk);
        assertEq(ERC4626AssetMock(asset).balanceOf(vault), 10);

        address replacementAsset = address(0xBEEF);
        vm.prank(address(0xBAD));
        (bool secondInitOk,) = vault.call(
            abi.encodeWithSignature(
                "init(address,address,uint256,address)", replacementAsset, address(0xCAFE), 0, address(0)
            )
        );
        assertFalse(secondInitOk);
        assertEq(callUint(vault, abi.encodeWithSignature("asset()")), uint256(uint160(asset)));
        assertEq(callUint(vault, abi.encodeWithSignature("feeRecipient()")), uint256(uint160(recipient)));
        assertEq(callUint(vault, abi.encodeWithSignature("totalAssets()")), 10);
        assertEq(callUint(vault, abi.encodeWithSignature("totalSupply()")), 10);
    }

    function testERC4626InitRejectsInvalidConfigurationAtomically() public {
        address vault = address(0x4646);
        address asset = address(0xA5525);
        address recipient = address(0xFEE5525);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC4626.bin")", vault);

        (bool zeroAssetOk,) = vault.call(
            abi.encodeWithSignature("init(address,address,uint256,address)", address(0), vault, 0, address(0))
        );
        assertFalse(zeroAssetOk);

        (bool wrongSelfOk,) = vault.call(
            abi.encodeWithSignature("init(address,address,uint256,address)", asset, address(0xBAD), 0, address(0))
        );
        assertFalse(wrongSelfOk);

        (bool zeroFeeRecipientOk,) = vault.call(
            abi.encodeWithSignature("init(address,address,uint256,address)", asset, vault, 100, address(0))
        );
        assertFalse(zeroFeeRecipientOk);

        (bool validInitOk,) = vault.call(
            abi.encodeWithSignature("init(address,address,uint256,address)", asset, vault, 100, recipient)
        );
        assertTrue(validInitOk);
        assertEq(callUint(vault, abi.encodeWithSignature("asset()")), uint256(uint160(asset)));
        assertEq(callUint(vault, abi.encodeWithSignature("feeRecipient()")), uint256(uint160(recipient)));
    }

    function testERC4626StandardEventsPreserveHighAddresses() public {
        address vault = address(0x4647);
        address asset = address(0xA5526);
        address actor = address(uint160(0xa111111111111111111111111111111111111111));
        installERC4626(vault, asset, 0, 0, 0, address(0), 0, 0, 0);
        ERC4626AssetMock(asset).mint(actor, 10);

        vm.expectEmit(true, true, false, true, vault);
        emit Deposit(actor, actor, 5, 5);
        vm.prank(actor);
        (bool depositOk,) = vault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 5, actor)
        );
        assertTrue(depositOk);

        vm.expectEmit(true, true, true, true, vault);
        emit Withdraw(actor, actor, actor, 2, 2);
        vm.prank(actor);
        (bool withdrawOk,) = vault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 2, actor, actor)
        );
        assertTrue(withdrawOk);
    }

    function testERC4626ZeroReceiverHasZeroDepositAndMintLimits() public {
        address vault = address(0x4640);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC4626.bin")", vault);
        setERC4626State(vault, address(0), 0, 0, 0, address(0));
        assertEq(callUint(vault, abi.encodeWithSignature("maxDeposit(address)", address(0))), 0);
        assertEq(callUint(vault, abi.encodeWithSignature("maxMint(address)", address(0))), 0);
    }

    function testERC4626RejectsFalseTokenReturnsAtomically() public {
        address pullVault = address(0x4641);
        address pullAsset = address(0xA5520);
        installERC4626(pullVault, pullAsset, 0, 0, 0, address(0), 0, 0, 10);
        ERC4626AssetMock(pullAsset).setTransferFromBehavior(false, false);
        vm.prank(ERC4626_ACTOR);
        (bool pullNoMoveOk,) = pullVault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 5, ERC4626_ACTOR)
        );
        assertFalse(pullNoMoveOk);
        assertEq(callUint(pullVault, abi.encodeWithSignature("totalAssets()")), 0);
        assertEq(ERC4626AssetMock(pullAsset).balanceOf(ERC4626_ACTOR), 10);

        ERC4626AssetMock(pullAsset).setTransferFromBehavior(false, true);
        vm.prank(ERC4626_ACTOR);
        (bool pullMovedOk,) = pullVault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 5, ERC4626_ACTOR)
        );
        assertFalse(pullMovedOk);
        assertEq(callUint(pullVault, abi.encodeWithSignature("totalAssets()")), 0);
        assertEq(callUint(pullVault, abi.encodeWithSignature("totalSupply()")), 0);
        assertEq(callUint(pullVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 0);
        assertEq(ERC4626AssetMock(pullAsset).balanceOf(ERC4626_ACTOR), 10);
        assertEq(ERC4626AssetMock(pullAsset).balanceOf(pullVault), 0);

        address pushVault = address(0x4642);
        address pushAsset = address(0xA5521);
        installERC4626(pushVault, pushAsset, 2, 2, 0, address(0), 2, 2, 0);
        ERC4626AssetMock(pushAsset).setTransferBehavior(false, false);
        vm.prank(ERC4626_ACTOR);
        (bool pushNoMoveOk,) = pushVault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 1, ERC4626_ACTOR, ERC4626_ACTOR)
        );
        assertFalse(pushNoMoveOk);
        assertEq(callUint(pushVault, abi.encodeWithSignature("totalAssets()")), 2);
        assertEq(callUint(pushVault, abi.encodeWithSignature("totalSupply()")), 2);
        assertEq(callUint(pushVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 2);
        assertEq(ERC4626AssetMock(pushAsset).balanceOf(ERC4626_ACTOR), 0);
        assertEq(ERC4626AssetMock(pushAsset).balanceOf(pushVault), 2);

        ERC4626AssetMock(pushAsset).setTransferBehavior(false, true);
        vm.prank(ERC4626_ACTOR);
        (bool pushMovedOk,) = pushVault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 1, ERC4626_ACTOR, ERC4626_ACTOR)
        );
        assertFalse(pushMovedOk);
        assertEq(callUint(pushVault, abi.encodeWithSignature("totalAssets()")), 2);
        assertEq(callUint(pushVault, abi.encodeWithSignature("totalSupply()")), 2);
        assertEq(callUint(pushVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 2);
        assertEq(ERC4626AssetMock(pushAsset).balanceOf(ERC4626_ACTOR), 0);
        assertEq(ERC4626AssetMock(pushAsset).balanceOf(pushVault), 2);

        address feeVault = address(0x4643);
        address feeAsset = address(0xA5522);
        address feeRecipient = address(0xFEE5522);
        installERC4626(feeVault, feeAsset, 100, 100, 100, feeRecipient, 100, 100, 0);
        ERC4626AssetMock(feeAsset).setFalseTransferCall(2);
        vm.prank(ERC4626_ACTOR);
        (bool feePushOk,) = feeVault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 100, ERC4626_ACTOR, ERC4626_ACTOR)
        );
        assertFalse(feePushOk);
        assertEq(callUint(feeVault, abi.encodeWithSignature("totalAssets()")), 100);
        assertEq(callUint(feeVault, abi.encodeWithSignature("totalSupply()")), 100);
        assertEq(callUint(feeVault, abi.encodeWithSignature("balanceOf(address)", ERC4626_ACTOR)), 100);
        assertEq(ERC4626AssetMock(feeAsset).balanceOf(ERC4626_ACTOR), 0);
        assertEq(ERC4626AssetMock(feeAsset).balanceOf(feeRecipient), 0);
        assertEq(ERC4626AssetMock(feeAsset).balanceOf(feeVault), 100);
    }

    function testERC4626RejectsPullAndPushReentrancyAndReleasesLock() public {
        address pullVault = address(0x4644);
        address pullAsset = address(0xA5523);
        installERC4626(pullVault, pullAsset, 0, 0, 0, address(0), 0, 0, 10);
        ERC4626AssetMock(pullAsset).mint(pullAsset, 2);
        ERC4626AssetMock(pullAsset).setCallback(pullVault, 1);
        vm.prank(ERC4626_ACTOR);
        (bool firstDepositOk,) = pullVault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 5, ERC4626_ACTOR)
        );
        assertTrue(firstDepositOk);
        assertTrue(ERC4626AssetMock(pullAsset).callbackAttempted());
        assertFalse(ERC4626AssetMock(pullAsset).callbackSucceeded());
        assertEq(ERC4626AssetMock(pullAsset).transferFromCalls(), 1);
        assertEq(callUint(pullVault, abi.encodeWithSignature("totalAssets()")), 5);
        assertEq(callUint(pullVault, abi.encodeWithSignature("totalSupply()")), 5);

        ERC4626AssetMock(pullAsset).setCallback(pullVault, 1);
        vm.prank(ERC4626_ACTOR);
        (bool secondDepositOk,) = pullVault.call(
            abi.encodeWithSignature("deposit(uint256,address)", 5, ERC4626_ACTOR)
        );
        assertTrue(secondDepositOk);
        assertFalse(ERC4626AssetMock(pullAsset).callbackSucceeded());
        assertEq(ERC4626AssetMock(pullAsset).transferFromCalls(), 2);

        address pushVault = address(0x4645);
        address pushAsset = address(0xA5524);
        installERC4626(pushVault, pushAsset, 2, 2, 0, address(0), 2, 2, 0);
        ERC4626AssetMock(pushAsset).mint(pushAsset, 2);
        ERC4626AssetMock(pushAsset).setCallback(pushVault, 2);
        vm.prank(ERC4626_ACTOR);
        (bool firstWithdrawOk,) = pushVault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 1, ERC4626_ACTOR, ERC4626_ACTOR)
        );
        assertTrue(firstWithdrawOk);
        assertTrue(ERC4626AssetMock(pushAsset).callbackAttempted());
        assertFalse(ERC4626AssetMock(pushAsset).callbackSucceeded());
        assertEq(ERC4626AssetMock(pushAsset).transferCalls(), 1);

        ERC4626AssetMock(pushAsset).setCallback(pushVault, 2);
        vm.prank(ERC4626_ACTOR);
        (bool secondWithdrawOk,) = pushVault.call(
            abi.encodeWithSignature("withdraw(uint256,address,address)", 1, ERC4626_ACTOR, ERC4626_ACTOR)
        );
        assertTrue(secondWithdrawOk);
        assertFalse(ERC4626AssetMock(pushAsset).callbackSucceeded());
        assertEq(ERC4626AssetMock(pushAsset).transferCalls(), 2);
        assertEq(callUint(pushVault, abi.encodeWithSignature("totalAssets()")), 0);
        assertEq(callUint(pushVault, abi.encodeWithSignature("totalSupply()")), 0);
    }

    function testOwnableLifecycle() public {
        address ownable = address(0x0551);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/Ownable.bin")", ownable);

        vm.expectEmit(true, true, false, false, ownable);
        emit OwnershipTransferred(address(0), alice);
        vm.prank(alice);
        (bool initOk,) = ownable.call(abi.encodeWithSignature("init()"));
        assertTrue(initOk);

        vm.prank(bob);
        (bool reinitOk,) = ownable.call(abi.encodeWithSignature("init()"));
        assertFalse(reinitOk);

        (bool ownerOk, bytes memory ownerResult) = ownable.call(abi.encodeWithSignature("owner()"));
        assertTrue(ownerOk);
        assertTrue(abi.decode(ownerResult, (address)) == alice);

        vm.expectEmit(true, true, false, false, ownable);
        emit OwnershipTransferred(alice, bob);
        vm.prank(alice);
        (bool transferOk,) = ownable.call(abi.encodeWithSignature("transferOwnership(address)", bob));
        assertTrue(transferOk);

        vm.prank(alice);
        (bool staleOwnerOk,) = ownable.call(abi.encodeWithSignature("transferOwnership(address)", alice));
        assertFalse(staleOwnerOk);

        (bool ownerBobOk, bytes memory ownerBobResult) = ownable.call(abi.encodeWithSignature("owner()"));
        assertTrue(ownerBobOk);
        assertTrue(abi.decode(ownerBobResult, (address)) == bob);

        vm.expectEmit(true, true, false, false, ownable);
        emit OwnershipTransferred(bob, address(0));
        vm.prank(bob);
        (bool renounceOk,) = ownable.call(abi.encodeWithSignature("renounceOwnership()"));
        assertTrue(renounceOk);

        (bool ownerZeroOk, bytes memory ownerZeroResult) = ownable.call(abi.encodeWithSignature("owner()"));
        assertTrue(ownerZeroOk);
        assertTrue(abi.decode(ownerZeroResult, (address)) == address(0));

        vm.prank(alice);
        (bool postRenounceReinitOk,) = ownable.call(abi.encodeWithSignature("init()"));
        assertFalse(postRenounceReinitOk);
    }

    function testPausableLifecycle() public {
        address pausable = address(0xFA5E);
        deployRuntime(hex"$(cat "$OUT_DIR/Pausable.bin")", pausable);

        (bool paused0Ok, bytes memory paused0) = pausable.call(abi.encodeWithSignature("paused()"));
        assertTrue(paused0Ok);
        assertEq(abi.decode(paused0, (uint256)), 0);

        (bool pauseOk,) = pausable.call(abi.encodeWithSignature("pause()"));
        assertTrue(pauseOk);

        (bool paused1Ok, bytes memory paused1) = pausable.call(abi.encodeWithSignature("paused()"));
        assertTrue(paused1Ok);
        assertEq(abi.decode(paused1, (uint256)), 1);

        (bool unpauseOk,) = pausable.call(abi.encodeWithSignature("unpause()"));
        assertTrue(unpauseOk);

        (bool paused2Ok, bytes memory paused2) = pausable.call(abi.encodeWithSignature("paused()"));
        assertTrue(paused2Ok);
        assertEq(abi.decode(paused2, (uint256)), 0);
    }

    function testVerifiedVaultLifecycle() public {
        address vault = address(0x7A17);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/VerifiedVault.bin")", vault);

        vm.deal(alice, 100 ether);
        vm.deal(bob, 100 ether);

        vm.prank(alice);
        (bool initOk,) = vault.call(abi.encodeWithSignature("init()"));
        assertTrue(initOk);

        (bool ownerOk, bytes memory ownerResult) = vault.call(abi.encodeWithSignature("getOwner()"));
        assertTrue(ownerOk);
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(alice)));

        vm.prank(alice);
        (bool depositAliceOk,) = vault.call{value: 1000}(abi.encodeWithSignature("deposit()"));
        assertTrue(depositAliceOk);

        vm.prank(bob);
        (bool depositBobOk,) = vault.call{value: 500}(abi.encodeWithSignature("deposit()"));
        assertTrue(depositBobOk);

        (bool reservesOk, bytes memory reservesResult) = vault.call(abi.encodeWithSignature("reserves()"));
        assertTrue(reservesOk);
        assertEq(abi.decode(reservesResult, (uint256)), 1500);

        (bool sharesOk, bytes memory sharesResult) = vault.call(abi.encodeWithSignature("totalShares()"));
        assertTrue(sharesOk);
        assertEq(abi.decode(sharesResult, (uint256)), 1500);

        vm.prank(alice);
        (bool withdrawOk,) = vault.call(abi.encodeWithSignature("withdraw(uint256)", uint256(300)));
        assertTrue(withdrawOk);

        (bool reservesAfterOk, bytes memory reservesAfterResult) = vault.call(abi.encodeWithSignature("reserves()"));
        assertTrue(reservesAfterOk);
        assertEq(abi.decode(reservesAfterResult, (uint256)), 1200);

        (bool aliceBalanceOk, bytes memory aliceBalanceResult) =
            vault.call(abi.encodeWithSignature("balanceOf(uint256)", uint256(uint160(alice))));
        assertTrue(aliceBalanceOk);
        assertEq(abi.decode(aliceBalanceResult, (uint256)), 700);

        vm.prank(alice);
        (bool overdraftOk,) = vault.call(abi.encodeWithSignature("withdraw(uint256)", uint256(999)));
        assertFalse(overdraftOk);
    }

    function testERC165ProbeLifecycle() public {
        address probe = address(0x1650);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC165Probe.bin")", probe);

        (bool erc165Ok, bytes memory erc165Result) =
            probe.call(abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0x01ffc9a7)));
        assertTrue(erc165Ok);
        assertTrue(abi.decode(erc165Result, (bool)));

        (bool sampleOk, bytes memory sampleResult) =
            probe.call(abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0x12345678)));
        assertTrue(sampleOk);
        assertTrue(abi.decode(sampleResult, (bool)));

        (bool unknownOk, bytes memory unknownResult) =
            probe.call(abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0xdeadbeef)));
        assertTrue(unknownOk);
        assertFalse(abi.decode(unknownResult, (bool)));

        (bool invalidOk, bytes memory invalidResult) =
            probe.call(abi.encodeWithSignature("supportsInterface(bytes4)", bytes4(0xffffffff)));
        assertTrue(invalidOk);
        assertFalse(abi.decode(invalidResult, (bool)));

        (bool registerOk,) =
            probe.call(abi.encodeWithSignature("registerInterface(bytes4)", bytes4(0xdeadbeef)));
        assertFalse(registerOk);

        (bool nonCanonicalBytes4Ok,) = probe.call(
            abi.encodePacked(
                bytes4(keccak256("supportsInterface(bytes4)")),
                bytes32((uint256(0x01ffc9a7) << 224) | 1)
            )
        );
        assertFalse(nonCanonicalBytes4Ok);
    }

    function testAccessControlProbeLifecycle() public {
        address probe = address(0xAC00);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/AccessControlProbe.bin")", probe);

        bytes32 minterRole = keccak256("MINTER_ROLE");
        vm.expectEmit(true, true, true, false, probe);
        emit RoleGranted(bytes32(0), alice, alice);
        vm.prank(alice);
        (bool initOk,) = probe.call(abi.encodeWithSignature("init()"));
        assertTrue(initOk);

        vm.prank(bob);
        (bool reinitOk,) = probe.call(abi.encodeWithSignature("init()"));
        assertFalse(reinitOk);

        (bool adminOk, bytes memory adminResult) =
            probe.call(abi.encodeWithSignature("hasRole(bytes32,address)", bytes32(0), alice));
        assertTrue(adminOk);
        assertTrue(abi.decode(adminResult, (bool)));

        (, bytes memory roleAdminResult) =
            probe.call(abi.encodeWithSignature("getRoleAdmin(bytes32)", minterRole));
        assertTrue(abi.decode(roleAdminResult, (bytes32)) == bytes32(0));

        vm.prank(bob);
        (bool unauthorizedGrantOk,) =
            probe.call(abi.encodeWithSignature("grantRole(bytes32,address)", minterRole, bob));
        assertFalse(unauthorizedGrantOk);

        vm.expectEmit(true, true, true, false, probe);
        emit RoleGranted(minterRole, bob, alice);
        vm.prank(alice);
        (bool grantOk,) = probe.call(abi.encodeWithSignature("grantRole(bytes32,address)", minterRole, bob));
        assertTrue(grantOk);

        (bool minterOk, bytes memory minterResult) =
            probe.call(abi.encodeWithSignature("hasRole(bytes32,address)", minterRole, bob));
        assertTrue(minterOk);
        assertTrue(abi.decode(minterResult, (bool)));

        vm.prank(bob);
        (bool touchOk,) = probe.call(abi.encodeWithSignature("touch()"));
        assertTrue(touchOk);

        (, bytes memory touchesResult) = probe.call(abi.encodeWithSignature("getTouches()"));
        assertEq(abi.decode(touchesResult, (uint256)), 1);

        vm.prank(alice);
        (bool noRoleOk,) = probe.call(abi.encodeWithSignature("touch()"));
        assertFalse(noRoleOk);

        vm.prank(bob);
        (bool badConfirmationOk,) =
            probe.call(abi.encodeWithSignature("renounceRole(bytes32,address)", minterRole, alice));
        assertFalse(badConfirmationOk);

        vm.expectEmit(true, true, true, false, probe);
        emit RoleRevoked(minterRole, bob, alice);
        vm.prank(alice);
        (bool revokeOk,) = probe.call(abi.encodeWithSignature("revokeRole(bytes32,address)", minterRole, bob));
        assertTrue(revokeOk);

        vm.prank(bob);
        (bool revokedTouchOk,) = probe.call(abi.encodeWithSignature("touch()"));
        assertFalse(revokedTouchOk);

        vm.prank(alice);
        (bool regrantOk,) = probe.call(abi.encodeWithSignature("grantRole(bytes32,address)", minterRole, bob));
        assertTrue(regrantOk);
        vm.expectEmit(true, true, true, false, probe);
        emit RoleRevoked(minterRole, bob, bob);
        vm.prank(bob);
        (bool renounceOk,) = probe.call(abi.encodeWithSignature("renounceRole(bytes32,address)", minterRole, bob));
        assertTrue(renounceOk);
    }

    function testERC721ProbeLifecycle() public {
        address probe = address(0x7210);
        address alice = address(uint160(0xa111111111111111111111111111111111111111));
        address bob = address(uint160(0xb222222222222222222222222222222222222222));
        deployRuntime(hex"$(cat "$OUT_DIR/ERC721Probe.bin")", probe);

        vm.expectEmit(true, true, true, false, probe);
        emit Transfer(address(0), alice, 1);
        vm.prank(alice);
        (bool mintOk,) = probe.call(abi.encodeWithSignature("mint(address,uint256)", alice, uint256(1)));
        assertTrue(mintOk);

        (bool ownerOk, bytes memory ownerResult) =
            probe.call(abi.encodeWithSignature("ownerOf(uint256)", uint256(1)));
        assertTrue(ownerOk);
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(alice)));

        vm.prank(alice);
        (bool transferOk,) =
            probe.call(abi.encodeWithSignature("transferFrom(address,address,uint256)", alice, bob, uint256(1)));
        assertTrue(transferOk);

        (, ownerResult) = probe.call(abi.encodeWithSignature("ownerOf(uint256)", uint256(1)));
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(bob)));

        vm.prank(bob);
        (bool safeOk,) =
            probe.call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", bob, alice, uint256(1)));
        assertTrue(safeOk);

        (, ownerResult) = probe.call(abi.encodeWithSignature("ownerOf(uint256)", uint256(1)));
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(alice)));

        vm.prank(alice);
        (bool burnOk,) = probe.call(abi.encodeWithSignature("burn(uint256)", uint256(1)));
        assertTrue(burnOk);

        (bool burnedOwnerOk,) = probe.call(abi.encodeWithSignature("ownerOf(uint256)", uint256(1)));
        assertFalse(burnedOwnerOk);
    }

    // PF-P2-02: IERC721Receiver accept / reject for safeTransferFrom.
    function testERC721SafeTransferToReceiver_accepts() public {
        address probe = address(0x7211);
        address alice = address(0xA11CE);
        GoodReceiver good = new GoodReceiver();
        deployRuntime(hex"$(cat "$OUT_DIR/ERC721Probe.bin")", probe);

        vm.prank(alice);
        (bool mintOk,) = probe.call(abi.encodeWithSignature("mint(address,uint256)", alice, uint256(2)));
        assertTrue(mintOk);

        vm.prank(alice);
        (bool safeOk,) =
            probe.call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", alice, address(good), uint256(2)));
        assertTrue(safeOk);

        (bool ownerOk, bytes memory ownerResult) =
            probe.call(abi.encodeWithSignature("ownerOf(uint256)", uint256(2)));
        assertTrue(ownerOk);
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(address(good))));
    }

    function testERC721SafeTransferToReceiver_rejects() public {
        address probe = address(0x7212);
        address alice = address(0xA11CE);
        BadReceiver bad = new BadReceiver();
        deployRuntime(hex"$(cat "$OUT_DIR/ERC721Probe.bin")", probe);

        vm.prank(alice);
        (bool mintOk,) = probe.call(abi.encodeWithSignature("mint(address,uint256)", alice, uint256(3)));
        assertTrue(mintOk);

        vm.prank(alice);
        (bool safeOk,) =
            probe.call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256)", alice, address(bad), uint256(3)));
        assertFalse(safeOk);

        // Ownership must remain with alice after failed safe transfer.
        (bool ownerOk, bytes memory ownerResult) =
            probe.call(abi.encodeWithSignature("ownerOf(uint256)", uint256(3)));
        assertTrue(ownerOk);
        assertEq(abi.decode(ownerResult, (uint256)), uint256(uint160(alice)));
    }

    function testERC1155Lifecycle() public {
        address token = address(0x1155);
        address alice = address(uint160(0xa111111111111111111111111111111111111111));
        address bob = address(uint160(0xb222222222222222222222222222222222222222));
        address operator = address(uint160(0xc333333333333333333333333333333333333333));
        deployRuntime(hex"$(cat "$OUT_DIR/ERC1155.bin")", token);

        vm.expectEmit(true, true, true, true, token);
        emit TransferSingle(alice, address(0), alice, 7, 100);
        vm.prank(alice);
        (bool mintOk,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(7), uint256(100)));
        assertTrue(mintOk);

        (bool aliceBalOk, bytes memory aliceBal) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(7)));
        assertTrue(aliceBalOk);
        assertEq(abi.decode(aliceBal, (uint256)), 100);

        (bool nonCanonicalAddressOk,) = token.call(
            abi.encodePacked(
                bytes4(keccak256("balanceOf(address,uint256)")),
                bytes32(uint256(1) << 160),
                bytes32(uint256(7))
            )
        );
        assertFalse(nonCanonicalAddressOk);

        vm.prank(bob);
        (bool unauthorizedOk,) =
            token.call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256)", alice, bob, uint256(7), uint256(1)));
        assertFalse(unauthorizedOk);

        vm.expectEmit(true, true, false, true, token);
        emit ApprovalForAll(alice, operator, true);
        vm.prank(alice);
        (bool approvalOk,) = token.call(abi.encodeWithSignature("setApprovalForAll(address,bool)", operator, true));
        assertTrue(approvalOk);

        (bool approvedOk, bytes memory approvedResult) =
            token.call(abi.encodeWithSignature("isApprovedForAll(address,address)", alice, operator));
        assertTrue(approvedOk);
        assertTrue(abi.decode(approvedResult, (bool)));

        vm.prank(operator);
        (bool transferOk,) =
            token.call(abi.encodeWithSignature("safeTransferFrom(address,address,uint256,uint256)", alice, bob, uint256(7), uint256(40)));
        assertTrue(transferOk);

        (, aliceBal) = token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(7)));
        assertEq(abi.decode(aliceBal, (uint256)), 60);

        (bool bobBalOk, bytes memory bobBal) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", bob, uint256(7)));
        assertTrue(bobBalOk);
        assertEq(abi.decode(bobBal, (uint256)), 40);

        vm.prank(bob);
        (bool burnOk,) = token.call(abi.encodeWithSignature("burn(uint256,uint256)", uint256(7), uint256(10)));
        assertTrue(burnOk);

        (, bobBal) = token.call(abi.encodeWithSignature("balanceOf(address,uint256)", bob, uint256(7)));
        assertEq(abi.decode(bobBal, (uint256)), 30);

        vm.prank(bob);
        (bool overdraftBurnOk,) = token.call(abi.encodeWithSignature("burn(uint256,uint256)", uint256(7), uint256(31)));
        assertFalse(overdraftBurnOk);
    }

    // PF-P2-02: IERC1155Receiver accept / reject for safeTransferFrom.
    function testERC1155SafeTransferToReceiver_accepts() public {
        address token = address(0x11551);
        address alice = address(0xA11CE);
        Good1155Receiver good = new Good1155Receiver();
        deployRuntime(hex"$(cat "$OUT_DIR/ERC1155.bin")", token);

        vm.prank(alice);
        (bool mintOk,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(9), uint256(50)));
        assertTrue(mintOk);

        vm.prank(alice);
        (bool safeOk,) = token.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256)", alice, address(good), uint256(9), uint256(20)
            )
        );
        assertTrue(safeOk);

        (bool goodBalOk, bytes memory goodBal) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", address(good), uint256(9)));
        assertTrue(goodBalOk);
        assertEq(abi.decode(goodBal, (uint256)), 20);

        (, bytes memory aliceBal) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(9)));
        assertEq(abi.decode(aliceBal, (uint256)), 30);
    }

    function testERC1155SafeTransferToReceiver_rejects() public {
        address token = address(0x11552);
        address alice = address(0xA11CE);
        Bad1155Receiver bad = new Bad1155Receiver();
        deployRuntime(hex"$(cat "$OUT_DIR/ERC1155.bin")", token);

        vm.prank(alice);
        (bool mintOk,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(11), uint256(50)));
        assertTrue(mintOk);

        vm.prank(alice);
        (bool safeOk,) = token.call(
            abi.encodeWithSignature(
                "safeTransferFrom(address,address,uint256,uint256)", alice, address(bad), uint256(11), uint256(20)
            )
        );
        assertFalse(safeOk);

        // Balances must remain unchanged after failed safe transfer.
        (, bytes memory aliceBal) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(11)));
        assertEq(abi.decode(aliceBal, (uint256)), 50);
        (, bytes memory badBal) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", address(bad), uint256(11)));
        assertEq(abi.decode(badBal, (uint256)), 0);
    }

    // PF-P2-03: real peer CALL — RemoteCall.call_with_args → PeerOracle.remote_call(42,7)=49.
    function testRemoteCallPeerEquivalence_callWithArgs() public {
        address caller = address(0xC411);
        // Must match --peer peer.callee=… used when building RemoteCall.peer.bin.
        address peer = address(0xB0B0);
        PeerOracle oracle = new PeerOracle();
        deployRuntime(address(oracle).code, peer);
        deployRuntime(hex"$(cat "$OUT_DIR/RemoteCall.peer.bin")", caller);

        (bool ok, bytes memory ret) = caller.call(abi.encodeWithSignature("call_with_args()"));
        assertTrue(ok);
        assertEq(abi.decode(ret, (uint256)), 49);
    }

    // PF-P2-02: size-2 batch MVP (safeBatchTransferFrom2) to EOA.
    function testERC1155SafeBatchTransferFrom2() public {
        address token = address(0x11553);
        address alice = address(0xA11CE);
        address bob = address(0xB0B);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC1155.bin")", token);

        vm.prank(alice);
        (bool mint0Ok,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(1), uint256(100)));
        assertTrue(mint0Ok);
        vm.prank(alice);
        (bool mint1Ok,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(2), uint256(80)));
        assertTrue(mint1Ok);

        vm.prank(alice);
        (bool batchOk,) = token.call(
            abi.encodeWithSignature(
                "safeBatchTransferFrom2(address,address,uint256,uint256,uint256,uint256)",
                alice, bob, uint256(1), uint256(30), uint256(2), uint256(20)
            )
        );
        assertTrue(batchOk);

        (, bytes memory alice0) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(1)));
        assertEq(abi.decode(alice0, (uint256)), 70);
        (, bytes memory alice1) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(2)));
        assertEq(abi.decode(alice1, (uint256)), 60);
        (, bytes memory bob0) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", bob, uint256(1)));
        assertEq(abi.decode(bob0, (uint256)), 30);
        (, bytes memory bob1) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", bob, uint256(2)));
        assertEq(abi.decode(bob1, (uint256)), 20);
    }

    // E1.2: batch transfer to contract receiver — accept / reject.
    function testERC1155SafeBatchTransferToReceiver_accepts() public {
        address token = address(0x11554);
        address alice = address(0xA11CE);
        Good1155Receiver receiver = new Good1155Receiver();
        address recv = address(receiver);
        deployRuntime(hex"$(cat "$OUT_DIR/ERC1155.bin")", token);

        vm.prank(alice);
        (bool mint0Ok,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(1), uint256(50)));
        assertTrue(mint0Ok);
        vm.prank(alice);
        (bool mint1Ok,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(2), uint256(40)));
        assertTrue(mint1Ok);

        vm.prank(alice);
        (bool batchOk,) = token.call(
            abi.encodeWithSignature(
                "safeBatchTransferFrom2(address,address,uint256,uint256,uint256,uint256)",
                alice, recv, uint256(1), uint256(10), uint256(2), uint256(5)
            )
        );
        assertTrue(batchOk);

        (, bytes memory r0) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", recv, uint256(1)));
        assertEq(abi.decode(r0, (uint256)), 10);
        (, bytes memory r1) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", recv, uint256(2)));
        assertEq(abi.decode(r1, (uint256)), 5);
        assertEq(uint256(uint160(receiver.batchOperator())), uint256(uint160(alice)));
        assertEq(uint256(uint160(receiver.batchFrom())), uint256(uint160(alice)));
        assertEq(receiver.batchId0(), 1);
        assertEq(receiver.batchId1(), 2);
        assertEq(receiver.batchAmount0(), 10);
        assertEq(receiver.batchAmount1(), 5);
        assertEq(receiver.batchDataLength(), 0);
        assertEq(receiver.batchCalls(), 1);
    }

    function testERC1155SafeBatchTransferToReceiver_rejects() public {
        address token = address(0x11555);
        address alice = address(0xA11CE);
        address recv = address(new Bad1155Receiver());
        deployRuntime(hex"$(cat "$OUT_DIR/ERC1155.bin")", token);

        vm.prank(alice);
        (bool mint0Ok,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(1), uint256(50)));
        assertTrue(mint0Ok);
        vm.prank(alice);
        (bool mint1Ok,) = token.call(abi.encodeWithSignature("mint(address,uint256,uint256)", alice, uint256(2), uint256(40)));
        assertTrue(mint1Ok);

        vm.prank(alice);
        (bool batchOk,) = token.call(
            abi.encodeWithSignature(
                "safeBatchTransferFrom2(address,address,uint256,uint256,uint256,uint256)",
                alice, recv, uint256(1), uint256(10), uint256(2), uint256(5)
            )
        );
        assertFalse(batchOk);

        // The receiver rejection must roll back both token ids atomically.
        (, bytes memory alice0) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(1)));
        assertEq(abi.decode(alice0, (uint256)), 50);
        (, bytes memory alice1) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", alice, uint256(2)));
        assertEq(abi.decode(alice1, (uint256)), 40);
        (, bytes memory recv0) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", recv, uint256(1)));
        assertEq(abi.decode(recv0, (uint256)), 0);
        (, bytes memory recv1) =
            token.call(abi.encodeWithSignature("balanceOf(address,uint256)", recv, uint256(2)));
        assertEq(abi.decode(recv1, (uint256)), 0);
    }

    function testUUPSProxyUpgradeLifecycle() public {
        address admin = address(uint160(0x1234567890123456789012345678901234567890));
        address implV1 = address(0x1001);
        address implV2 = address(uint160(0xc222222222222222222222222222222222222222));
        deployRuntime(hex"$(cat "$OUT_DIR/CounterUUPSImpl.bin")", implV1);
        deployRuntime(hex"$(cat "$OUT_DIR/CounterUUPSImpl.bin")", implV2);
        address proxy = deployInitCode(hex"$(cat "$OUT_DIR/UUPSProxy.init.bin")");

        vm.prank(address(0xBAD));
        (bool proxyInitOk,) = proxy.call(abi.encodeWithSignature("init(address)", implV2));
        assertFalse(proxyInitOk);
        vm.prank(address(0xBAD));
        (bool ownerInitOk,) = proxy.call(abi.encodeWithSignature("init()"));
        assertFalse(ownerInitOk);

        (bool get0Ok, bytes memory get0) = proxy.call(abi.encodeWithSignature("get()"));
        assertTrue(get0Ok);
        assertEq(abi.decode(get0, (uint256)), 0);

        (bool incOk,) = proxy.call(abi.encodeWithSignature("increment()"));
        assertTrue(incOk);

        (, bytes memory get1) = proxy.call(abi.encodeWithSignature("get()"));
        assertEq(abi.decode(get1, (uint256)), 1);

        vm.prank(address(0xBAD));
        (bool unauthorizedUpgradeOk,) = proxy.call(abi.encodeWithSignature("upgradeTo(address)", implV2));
        assertFalse(unauthorizedUpgradeOk);

        vm.expectEmit(true, false, false, false, proxy);
        emit Upgraded(implV2);
        vm.prank(admin);
        (bool upgradeOk,) = proxy.call(abi.encodeWithSignature("upgradeTo(address)", implV2));
        assertTrue(upgradeOk);

        (bool inc2Ok,) = proxy.call(abi.encodeWithSignature("increment()"));
        assertTrue(inc2Ok);

        (, bytes memory get2) = proxy.call(abi.encodeWithSignature("get()"));
        assertEq(abi.decode(get2, (uint256)), 2);
    }

    function testCreate2FactoryProbeLifecycle() public {
        address probe = address(0xC2E2);
        deployRuntime(hex"$(cat "$OUT_DIR/Create2FactoryProbe.bin")", probe);
        bytes memory initCode = hex"69602a60005260206000f3600052600a6016f3";
        bytes32 initCodeHash = keccak256(initCode);
        bytes32 salt = keccak256("proof-forge-create2-factory-salt");

        (bool hashOk, bytes memory hashResult) =
            probe.call(abi.encodeWithSignature("templateInitCodeHash()"));
        assertTrue(hashOk);
        assertTrue(abi.decode(hashResult, (bytes32)) == initCodeHash);

        address expected = expectedCreate2Address(probe, salt, initCodeHash);

        vm.expectEmit(true, true, false, false, probe);
        emit Deployed(expected, salt);
        (bool deployOk, bytes memory deployResult) =
            probe.call(abi.encodeWithSignature("deploy(bytes32)", salt));
        assertTrue(deployOk);
        address deployed = abi.decode(deployResult, (address));
        assertEq(uint256(uint160(deployed)), uint256(uint160(expected)));
        assertEq(callRuntime42(deployed), 42);
    }
}
SOL

forge test --root "$FORGE_DIR" -vv
