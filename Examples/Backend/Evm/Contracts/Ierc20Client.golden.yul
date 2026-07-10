object "Ierc20Client" {
  code {
    switch shr(224, calldataload(0))
    case 0x51720e25 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_Ierc20Client_pushTokens(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x9f700267 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_Ierc20Client_readBalance(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6df137f6 {
      let _r := f_Ierc20Client_readSupply()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_Ierc20Client_pushTokens(to, amount) {
      let _ok := __proof_forge_crosscall_2(0, 2835717307, to, amount)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(amount, 18446744073709551615))))
    }
    function f_Ierc20Client_readBalance(account) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1(0, 1889567281, account)
    }
    function f_Ierc20Client_readSupply() -> __pf_result {
      __pf_result := __proof_forge_crosscall_0(0, 404098525)
    }
    function __proof_forge_crosscall_2(target, selector, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := call(gas(), target, 0, 0, 68, 0, 32)
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
    function __proof_forge_crosscall_0(target, selector) -> result {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 32)
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
