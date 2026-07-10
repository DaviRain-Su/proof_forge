object "Ierc721Client" {
  code {
    switch shr(224, calldataload(0))
    case 0x0d1dfd76 {
      if lt(calldatasize(), 100) {
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
      f_Ierc721Client_moveToken(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x60218c1e {
      if lt(calldatasize(), 100) {
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
      f_Ierc721Client_safeMoveToken(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xed953f2b {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_Ierc721Client_readOwner(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x9f700267 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_Ierc721Client_readBalance(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_Ierc721Client_moveToken(from, to, tokenId) {
      let _ok := __proof_forge_crosscall_3(0, 599290589, from, to, tokenId)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(tokenId, 18446744073709551615))))
    }
    function f_Ierc721Client_safeMoveToken(from, to, tokenId) {
      let _ok := __proof_forge_crosscall_3(0, 1115958798, from, to, tokenId)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(tokenId, 18446744073709551615))))
    }
    function f_Ierc721Client_readOwner(tokenId) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1(0, 1666326814, tokenId)
    }
    function f_Ierc721Client_readBalance(account) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1(0, 1889567281, account)
    }
    function __proof_forge_crosscall_3(target, selector, arg0, arg1, arg2) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      let _success := call(gas(), target, 0, 0, 100, 0, 32)
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
