object "Ierc4626Client" {
  code {
    switch shr(224, calldataload(0))
    case 0x3f167e17 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_Ierc4626Client_readShares(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x90f87f7c {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_Ierc4626Client_doDeposit(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xab795739 {
      let _r := f_Ierc4626Client_readTotalAssets()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_Ierc4626Client_readShares(assets) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1(0, 3337024914, assets)
    }
    function f_Ierc4626Client_doDeposit(assets, receiver) -> __pf_result {
      let shares := __proof_forge_crosscall_2(0, 1851080549, assets, receiver)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(shares, 18446744073709551615))))
      __pf_result := shares
    }
    function f_Ierc4626Client_readTotalAssets() -> __pf_result {
      __pf_result := __proof_forge_crosscall_0(0, 31576340)
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
