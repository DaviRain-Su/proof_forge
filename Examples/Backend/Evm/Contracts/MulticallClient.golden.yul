object "MulticallClient" {
  code {
    switch shr(224, calldataload(0))
    case 0x0eaa75fe {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_MulticallClient_batch(calldataload(4))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_MulticallClient_batch(tag) {
      let _r := __proof_forge_crosscall_1(0, 623753794, tag)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(tag, 18446744073709551615))))
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
