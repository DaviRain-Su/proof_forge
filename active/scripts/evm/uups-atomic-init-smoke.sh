#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
OUT_DIR="${PROOF_FORGE_UUPS_ATOMIC_OUT:-$ROOT/build/evm-uups-atomic}"
FORGE_DIR="${PROOF_FORGE_UUPS_ATOMIC_FORGE:-$ROOT/build/foundry-uups-atomic}"

export PATH="${HOME}/.elan/bin:${HOME}/.foundry/bin:${HOME}/.local/bin:${PATH}"

command -v lake >/dev/null 2>&1
command -v forge >/dev/null 2>&1
command -v solc >/dev/null 2>&1

rm -rf "$OUT_DIR" "$FORGE_DIR"
mkdir -p "$OUT_DIR" "$FORGE_DIR/test"

cd "$ROOT"
lake build proof-forge ProofForge.Contract.Stdlib.UUPSProxy \
  Examples.Backend.Evm.Contracts.CounterUUPSImpl >/dev/null

set +e
no_args_output=$(lake env proof-forge build --target evm --root . \
  --yul-output "$OUT_DIR/UUPSProxyMissingArgs.yul" \
  -o "$OUT_DIR/UUPSProxyMissingArgs.bin" \
  Examples/Backend/Evm/Contracts/stdlib/UUPSProxy.lean 2>&1)
no_args_status=$?
set -e
if [[ "$no_args_status" -eq 0 ]]; then
  echo "uups-atomic-init: proxy unexpectedly built without constructor arguments" >&2
  exit 1
fi
grep -Fq "UUPS proxy deployment requires constructor arguments" <<<"$no_args_output" || {
  echo "uups-atomic-init: missing constructor diagnostic: $no_args_output" >&2
  exit 1
}
if [[ -e "$OUT_DIR/UUPSProxyMissingArgs.yul" || -e "$OUT_DIR/UUPSProxyMissingArgs.bin" ]]; then
  echo "uups-atomic-init: missing-args failure left a deployable artifact" >&2
  exit 1
fi

expect_atomic_config_failure() {
  local fixture="$1"
  local source="$2"
  local output
  local status
  set +e
  output=$(lake env proof-forge build --target evm --root . \
    --evm-constructor-arg \
      "implementation=0x0000000000000000000000000000000000001001" \
    --evm-constructor-arg \
      "admin=0x1234567890123456789012345678901234567890" \
    --yul-output "$OUT_DIR/$fixture.yul" \
    -o "$OUT_DIR/$fixture.bin" \
    "$source" 2>&1)
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "uups-atomic-init: $fixture unexpectedly built with unsafe constructor bindings" >&2
    exit 1
  fi
  grep -Fq "UUPS proxy requires exact atomic constructor bindings" <<<"$output" || {
    echo "uups-atomic-init: $fixture missing atomic-binding diagnostic: $output" >&2
    exit 1
  }
  if [[ -e "$OUT_DIR/$fixture.yul" || -e "$OUT_DIR/$fixture.bin" ]]; then
    echo "uups-atomic-init: $fixture failure left a deployable artifact" >&2
    exit 1
  fi
}

expect_atomic_config_failure BadUUPSNoBindings \
  Tests/Backend/Evm/BadUUPSNoBindings.lean
expect_atomic_config_failure BadUUPSMissingBinding \
  Tests/Backend/Evm/BadUUPSMissingBinding.lean
expect_atomic_config_failure BadUUPSWrongBinding \
  Tests/Backend/Evm/BadUUPSWrongBinding.lean

expect_runtime_entrypoint_failure() {
  local fixture="$1"
  local source="$2"
  local output
  local status
  set +e
  output=$(lake env proof-forge build --target evm --root . \
    --evm-constructor-arg \
      "implementation=0x0000000000000000000000000000000000001001" \
    --evm-constructor-arg \
      "admin=0x1234567890123456789012345678901234567890" \
    --yul-output "$OUT_DIR/$fixture.yul" \
    -o "$OUT_DIR/$fixture.bin" \
    "$source" 2>&1)
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    echo "uups-atomic-init: $fixture unexpectedly built with a runtime entrypoint" >&2
    exit 1
  fi
  grep -Fq "UUPS proxy runtime must expose no entrypoints" <<<"$output" || {
    echo "uups-atomic-init: $fixture missing runtime-entrypoint diagnostic: $output" >&2
    exit 1
  }
  if [[ -e "$OUT_DIR/$fixture.yul" || -e "$OUT_DIR/$fixture.bin" ]]; then
    echo "uups-atomic-init: $fixture failure left a deployable artifact" >&2
    exit 1
  fi
}

expect_runtime_entrypoint_failure BadUUPSAlternateInitializer \
  Tests/Backend/Evm/BadUUPSAlternateInitializer.lean
expect_runtime_entrypoint_failure BadUUPSRuntimeWriter \
  Tests/Backend/Evm/BadUUPSRuntimeWriter.lean

set +e
assign_op_output=$(lake env proof-forge build --target evm --root . \
  --yul-output "$OUT_DIR/BadUUPSImplementationAssignOp.yul" \
  -o "$OUT_DIR/BadUUPSImplementationAssignOp.bin" \
  Tests/Backend/Evm/BadUUPSImplementationAssignOp.lean 2>&1)
assign_op_status=$?
set -e
if [[ "$assign_op_status" -eq 0 ]]; then
  echo "uups-atomic-init: EIP-1967 implementation compound assignment unexpectedly built" >&2
  exit 1
fi
grep -Fq "compound assignment is not allowed for the EIP-1967 implementation state" \
  <<<"$assign_op_output" || {
  echo "uups-atomic-init: missing EIP-1967 compound-assignment diagnostic: $assign_op_output" >&2
  exit 1
}
if [[ -e "$OUT_DIR/BadUUPSImplementationAssignOp.yul" ||
      -e "$OUT_DIR/BadUUPSImplementationAssignOp.bin" ]]; then
  echo "uups-atomic-init: EIP-1967 compound-assignment failure left a deployable artifact" >&2
  exit 1
fi

NONCANONICAL_IMPLEMENTATION_WORD="0000000000000000000000010000000000000000000000000000000000001001"
CANONICAL_ADMIN_WORD="0000000000000000000000001234567890123456789012345678901234567890"
set +e
noncanonical_output=$(lake env proof-forge build --target evm --root . \
  --evm-constructor-args-hex \
    "${NONCANONICAL_IMPLEMENTATION_WORD}${CANONICAL_ADMIN_WORD}" \
  --yul-output "$OUT_DIR/UUPSProxyNoncanonicalAddress.yul" \
  -o "$OUT_DIR/UUPSProxyNoncanonicalAddress.bin" \
  Examples/Backend/Evm/Contracts/stdlib/UUPSProxy.lean 2>&1)
noncanonical_status=$?
set -e
if [[ "$noncanonical_status" -eq 0 ]]; then
  echo "uups-atomic-init: noncanonical raw address word unexpectedly built" >&2
  exit 1
fi
grep -Fq "non-zero high 96 bits" <<<"$noncanonical_output" || {
  echo "uups-atomic-init: missing noncanonical-address diagnostic: $noncanonical_output" >&2
  exit 1
}
if [[ -e "$OUT_DIR/UUPSProxyNoncanonicalAddress.yul" ||
      -e "$OUT_DIR/UUPSProxyNoncanonicalAddress.bin" ]]; then
  echo "uups-atomic-init: noncanonical address failure left a deployable artifact" >&2
  exit 1
fi

build_proxy_initcode() {
  local name="$1"
  local implementation="$2"
  local admin="$3"
  lake env proof-forge build --target evm --root . \
    --evm-constructor-arg "implementation=$implementation" \
    --evm-constructor-arg "admin=$admin" \
    --yul-output "$OUT_DIR/$name.yul" \
    -o "$OUT_DIR/$name.bin" \
    Examples/Backend/Evm/Contracts/stdlib/UUPSProxy.lean >/dev/null
}

ADMIN="0x1234567890123456789012345678901234567890"
build_proxy_initcode UUPSProxyAtomic \
  "0x0000000000000000000000000000000000001001" "$ADMIN"
build_proxy_initcode UUPSProxyZeroImplementation \
  "0x0000000000000000000000000000000000000000" "$ADMIN"
build_proxy_initcode UUPSProxyZeroAdmin \
  "0x0000000000000000000000000000000000001001" \
  "0x0000000000000000000000000000000000000000"
build_proxy_initcode UUPSProxyEoaImplementation \
  "0x0000000000000000000000000000000000001003" "$ADMIN"

ADDRESS_MASK="1461501637330902918203684832716283019655932542975"
guard_count=$(grep -Fc "if gt(__pf_address, $ADDRESS_MASK) { revert(0, 0) }" \
  "$OUT_DIR/UUPSProxyAtomic.deploy.yul")
if [[ "$guard_count" -ne 2 ]]; then
  echo "uups-atomic-init: expected canonical address guards for implementation and admin" >&2
  exit 1
fi

lake env proof-forge build --target evm --root . \
  --yul-output "$OUT_DIR/CounterUUPSImpl.yul" \
  -o "$OUT_DIR/CounterUUPSImpl.bin" \
  Examples/Backend/Evm/Contracts/CounterUUPSImpl.lean >/dev/null

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

cat > "$FORGE_DIR/test/UUPSAtomicInit.t.sol" <<SOL
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface Vm {
    function etch(address target, bytes calldata newRuntimeBytecode) external;
    function prank(address msgSender) external;
}

contract UUPSAtomicInitTest {
    Vm constant vm = Vm(address(uint160(uint256(keccak256("hevm cheat code")))));

    function testAttackerCannotClaimIndependentInitializers() public {
        address attacker = address(0xBAD);
        address proxy = address(0x5005);
        address implementation = address(0x1001);
        vm.etch(proxy, hex"$(cat "$OUT_DIR/UUPSProxyAtomic.bin")");
        vm.etch(implementation, hex"$(cat "$OUT_DIR/CounterUUPSImpl.bin")");

        vm.prank(attacker);
        (bool proxyInitOk,) = proxy.call(abi.encodeWithSignature("init(address)", implementation));
        require(!proxyInitOk, "attacker claimed proxy implementation initializer");

        vm.prank(attacker);
        (bool ownerInitOk,) = proxy.call(abi.encodeWithSignature("init()"));
        require(!ownerInitOk, "attacker claimed implementation owner initializer");
    }

    function deploy(bytes memory initCode) internal returns (address deployed) {
        assembly {
            deployed := create(0, add(initCode, 0x20), mload(initCode))
        }
    }

    function testConstructorAtomicallyBindsImplementationAndAdmin() public {
        address admin = address(uint160(0x1234567890123456789012345678901234567890));
        address attacker = address(0xBAD);
        address implementationV1 = address(0x1001);
        address implementationV2 = address(0x1002);
        vm.etch(implementationV1, hex"$(cat "$OUT_DIR/CounterUUPSImpl.bin")");
        vm.etch(implementationV2, hex"$(cat "$OUT_DIR/CounterUUPSImpl.bin")");

        address proxy = deploy(hex"$(cat "$OUT_DIR/UUPSProxyAtomic.init.bin")");
        require(proxy != address(0), "atomic proxy deployment failed");

        vm.prank(attacker);
        (bool proxyInitOk,) = proxy.call(abi.encodeWithSignature("init(address)", implementationV2));
        require(!proxyInitOk, "attacker claimed proxy initializer");
        vm.prank(attacker);
        (bool ownerInitOk,) = proxy.call(abi.encodeWithSignature("init()"));
        require(!ownerInitOk, "attacker claimed owner initializer");

        (bool getOk, bytes memory getResult) = proxy.call(abi.encodeWithSignature("get()"));
        require(getOk && abi.decode(getResult, (uint256)) == 0, "implementation was not bound");
        (bool incrementOk,) = proxy.call(abi.encodeWithSignature("increment()"));
        require(incrementOk, "counter increment failed");

        vm.prank(attacker);
        (bool attackerUpgradeOk,) = proxy.call(abi.encodeWithSignature("upgradeTo(address)", implementationV2));
        require(!attackerUpgradeOk, "attacker became upgrade admin");
        vm.prank(admin);
        (bool adminUpgradeOk,) = proxy.call(abi.encodeWithSignature("upgradeTo(address)", implementationV2));
        require(adminUpgradeOk, "constructor admin cannot upgrade");

        (, bytes memory afterUpgrade) = proxy.call(abi.encodeWithSignature("get()"));
        require(abi.decode(afterUpgrade, (uint256)) == 1, "upgrade did not preserve storage");
    }

    function testConstructorRejectsZeroImplementationAndAdmin() public {
        require(
            deploy(hex"$(cat "$OUT_DIR/UUPSProxyZeroImplementation.init.bin")") == address(0),
            "zero implementation deployed"
        );
        require(
            deploy(hex"$(cat "$OUT_DIR/UUPSProxyZeroAdmin.init.bin")") == address(0),
            "zero admin deployed"
        );
    }

    function testConstructorRejectsEoaImplementation() public {
        require(
            deploy(hex"$(cat "$OUT_DIR/UUPSProxyEoaImplementation.init.bin")") == address(0),
            "EOA implementation deployed"
        );
    }

    function testUpgradeRejectsEoaAndProxySelf() public {
        address admin = address(uint160(0x1234567890123456789012345678901234567890));
        address implementationV1 = address(0x1001);
        vm.etch(implementationV1, hex"$(cat "$OUT_DIR/CounterUUPSImpl.bin")");

        address proxy = deploy(hex"$(cat "$OUT_DIR/UUPSProxyAtomic.init.bin")");
        require(proxy != address(0), "atomic proxy deployment failed");

        vm.prank(admin);
        (bool eoaUpgradeOk,) = proxy.call(
            abi.encodeWithSignature("upgradeTo(address)", address(0x1003))
        );
        require(!eoaUpgradeOk, "EOA implementation accepted");

        vm.prank(admin);
        (bool selfUpgradeOk,) = proxy.call(
            abi.encodeWithSignature("upgradeTo(address)", proxy)
        );
        require(!selfUpgradeOk, "proxy self implementation accepted");

        (bool getOk, bytes memory getResult) = proxy.call(abi.encodeWithSignature("get()"));
        require(getOk && abi.decode(getResult, (uint256)) == 0, "rejected upgrades changed implementation");
    }
}
SOL

(cd "$FORGE_DIR" && forge test -vv)
echo "uups-atomic-init: ok"
