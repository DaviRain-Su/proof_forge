object "Ierc20PermitClient" {
  code {
    switch shr(224, calldataload(0))
    case 0x3e18cf35 {
      if lt(calldatasize(), 228) {
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
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(196), 18446744073709551615) {
        revert(0, 0)
      }
      f_Ierc20PermitClient_runPermit(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196))
      return(0, 0)
    }
    case 0x8c3f5563 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_Ierc20PermitClient_readNonce(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_Ierc20PermitClient_runPermit(owner, spender, value, deadline, v, r, s) {
      let _ok := __proof_forge_crosscall_7(0, 3573918927, owner, spender, value, deadline, v, r, s)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(value, 18446744073709551615))))
    }
    function f_Ierc20PermitClient_readNonce(owner) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1(0, 2127478272, owner)
    }
    function __proof_forge_crosscall_7(target, selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      mstore(132, arg4)
      mstore(164, arg5)
      mstore(196, arg6)
      let _success := call(gas(), target, 0, 0, 228, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_1(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := call(gas(), target, 0, 0, 36, 0, 32)
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
