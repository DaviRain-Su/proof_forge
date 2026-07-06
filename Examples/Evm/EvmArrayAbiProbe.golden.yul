object "EvmArrayAbiProbe" {
  code {
    {
      mstore(64, 128)
      switch shr(224, calldataload(0))
      case 0xc3b0874d {
        if lt(calldatasize(), 36) {
          revert(0, 0)
        }
        if gt(add(4, calldataload(4)), calldatasize()) {
          revert(0, 0)
        }
        if gt(add(add(4, calldataload(4)), add(32, mul(calldataload(add(4, calldataload(4))), 32))), calldatasize()) {
          revert(0, 0)
        }
        let __pf_dyn_ptr_xs := mload(64)
        mstore(__pf_dyn_ptr_xs, calldataload(add(4, calldataload(4))))
        calldatacopy(add(__pf_dyn_ptr_xs, 32), add(add(4, calldataload(4)), 32), mul(calldataload(add(4, calldataload(4))), 32))
        mstore(64, add(__pf_dyn_ptr_xs, add(mul(calldataload(add(4, calldataload(4))), 32), 32)))
        let xs__length := calldataload(add(4, calldataload(4)))
        let xs__data_ptr := __pf_dyn_ptr_xs
        let _r := f_EvmArrayAbiProbe_echo_array(xs__length, xs__data_ptr)
        let _ret_len := mload(_r)
        let _ret_word_count := _ret_len
        mstore(0, 32)
        mstore(32, _ret_len)
        for {
          let _i := 0
        } lt(_i, _ret_word_count) {
          _i := add(_i, 1)
        } {
          mstore(add(64, mul(_i, 32)), mload(add(add(_r, 32), mul(_i, 32))))
        }
        return(0, add(64, mul(_ret_word_count, 32)))
      }
      case 0xbc2d8fd1 {
        if lt(calldatasize(), 36) {
          revert(0, 0)
        }
        if gt(add(4, calldataload(4)), calldatasize()) {
          revert(0, 0)
        }
        if gt(add(add(4, calldataload(4)), add(32, mul(calldataload(add(4, calldataload(4))), 32))), calldatasize()) {
          revert(0, 0)
        }
        let __pf_dyn_ptr_xs := mload(64)
        mstore(__pf_dyn_ptr_xs, calldataload(add(4, calldataload(4))))
        calldatacopy(add(__pf_dyn_ptr_xs, 32), add(add(4, calldataload(4)), 32), mul(calldataload(add(4, calldataload(4))), 32))
        mstore(64, add(__pf_dyn_ptr_xs, add(mul(calldataload(add(4, calldataload(4))), 32), 32)))
        let xs__length := calldataload(add(4, calldataload(4)))
        let xs__data_ptr := __pf_dyn_ptr_xs
        let _r := f_EvmArrayAbiProbe_sum_array(xs__length, xs__data_ptr)
        mstore(0, _r)
        return(0, 32)
      }
      default {
        revert(0, 0)
      }
    }
    function f_EvmArrayAbiProbe_echo_array(xs__length, xs__data_ptr) -> result {
      let xs := xs__data_ptr
      result := xs__data_ptr
    }
    function f_EvmArrayAbiProbe_sum_array(xs__length, xs__data_ptr) -> result {
      let xs := xs__data_ptr
      if iszero(eq(mload(xs), 3)) {
        revert(0, 0)
      }
      result := __pf_checked_add(__pf_checked_add(__proof_forge_memory_array_get(xs, 0), __proof_forge_memory_array_get(xs, 1)), __proof_forge_memory_array_get(xs, 2))
    }
    function __proof_forge_memory_array_get(array, index) -> value {
      if iszero(lt(index, mload(array))) {
        revert(0, 0)
      }
      value := mload(add(add(array, 32), mul(index, 32)))
    }
    function __pf_checked_add(a, b) -> r {
      if gt(a, sub(115792089237316195423570985008687907853269984665640564039457584007913129639935, b)) {
        revert(0, 0)
      }
      r := add(a, b)
    }
    function __pf_checked_sub(a, b) -> r {
      if gt(b, a) {
        revert(0, 0)
      }
      r := sub(a, b)
    }
    function __pf_checked_mul(a, b) -> r {
      if iszero(a) {
        r := 0
        leave
      }
      if gt(a, div(115792089237316195423570985008687907853269984665640564039457584007913129639935, b)) {
        revert(0, 0)
      }
      r := mul(a, b)
    }
  }
}
