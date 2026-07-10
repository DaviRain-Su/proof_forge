object "EvmDynamicAbiProbe" {
  code {
    {
      mstore(64, 128)
      switch shr(224, calldataload(0))
      case 0x1cc09e37 {
        if lt(calldatasize(), 36) {
          revert(0, 0)
        }
        if gt(add(4, calldataload(4)), calldatasize()) {
          revert(0, 0)
        }
        if gt(add(add(4, calldataload(4)), add(32, mul(div(add(calldataload(add(4, calldataload(4))), 31), 32), 32))), calldatasize()) {
          revert(0, 0)
        }
        let __pf_dyn_ptr_data := mload(64)
        mstore(__pf_dyn_ptr_data, calldataload(add(4, calldataload(4))))
        calldatacopy(add(__pf_dyn_ptr_data, 32), add(add(4, calldataload(4)), 32), mul(div(add(calldataload(add(4, calldataload(4))), 31), 32), 32))
        mstore(64, add(__pf_dyn_ptr_data, add(mul(div(add(calldataload(add(4, calldataload(4))), 31), 32), 32), 32)))
        let __pf_param_data_length := calldataload(add(4, calldataload(4)))
        let __pf_param_data_data_ptr := __pf_dyn_ptr_data
        let _r := f_EvmDynamicAbiProbe_echo_bytes(__pf_param_data_length, __pf_param_data_data_ptr)
        let _ret_len := mload(_r)
        let _ret_word_count := div(add(_ret_len, 31), 32)
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
      case 0x41ccc945 {
        if lt(calldatasize(), 36) {
          revert(0, 0)
        }
        if gt(add(4, calldataload(4)), calldatasize()) {
          revert(0, 0)
        }
        if gt(add(add(4, calldataload(4)), add(32, mul(div(add(calldataload(add(4, calldataload(4))), 31), 32), 32))), calldatasize()) {
          revert(0, 0)
        }
        let __pf_dyn_ptr_data := mload(64)
        mstore(__pf_dyn_ptr_data, calldataload(add(4, calldataload(4))))
        calldatacopy(add(__pf_dyn_ptr_data, 32), add(add(4, calldataload(4)), 32), mul(div(add(calldataload(add(4, calldataload(4))), 31), 32), 32))
        mstore(64, add(__pf_dyn_ptr_data, add(mul(div(add(calldataload(add(4, calldataload(4))), 31), 32), 32), 32)))
        let __pf_param_data_length := calldataload(add(4, calldataload(4)))
        let __pf_param_data_data_ptr := __pf_dyn_ptr_data
        let _r := f_EvmDynamicAbiProbe_echo_string(__pf_param_data_length, __pf_param_data_data_ptr)
        let _ret_len := mload(_r)
        let _ret_word_count := div(add(_ret_len, 31), 32)
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
      case 0xa9059cbb {
        if lt(calldatasize(), 68) {
          revert(0, 0)
        }
        if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
          revert(0, 0)
        }
        if gt(calldataload(36), 18446744073709551615) {
          revert(0, 0)
        }
        let _r := f_EvmDynamicAbiProbe_transfer(calldataload(4), calldataload(36))
        mstore(0, _r)
        return(0, 32)
      }
      default {
        revert(0, 0)
      }
    }
    function f_EvmDynamicAbiProbe_echo_bytes(__pf_param_data_length, __pf_param_data_data_ptr) -> __pf_result {
      let data := __pf_param_data_data_ptr
      __pf_result := __pf_param_data_data_ptr
    }
    function f_EvmDynamicAbiProbe_echo_string(__pf_param_data_length, __pf_param_data_data_ptr) -> __pf_result {
      let data := __pf_param_data_data_ptr
      __pf_result := __pf_param_data_data_ptr
    }
    function f_EvmDynamicAbiProbe_transfer(to, amount) -> __pf_result {
      __pf_result := 1
    }
  }
}
