object "Permit2Client" {
  code {
    switch shr(224, calldataload(0))
    case 0x0d42ae62 {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      f_Permit2Client_pull(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_Permit2Client_pull(from, to, amount, token) {
      let _r := __proof_forge_crosscall_4(0, 919045398, from, to, amount, token)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(amount, 18446744073709551615))))
    }
    function __proof_forge_crosscall_4(target, selector, arg0, arg1, arg2, arg3) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      let _success := call(gas(), target, 0, 0, 132, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
  }
}
