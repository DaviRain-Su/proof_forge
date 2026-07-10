object "EvmAbiAggregateProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x25508e13 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmAbiAggregateProbe_sum_pair(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xeb353b80 {
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
      let _r := f_EvmAbiAggregateProbe_sum_array(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xda76e471 {
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
      let _r := f_EvmAbiAggregateProbe_sum_matrix(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x10e4c1da {
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
      let _r := f_EvmAbiAggregateProbe_sum_pair_array(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xef51ff62 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmAbiAggregateProbe_make_pair(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x617df171 {
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
      let _r0, _r1, _r2, _r3 := f_EvmAbiAggregateProbe_make_pair_array(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0xb61c11b8 {
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
      let _r0, _r1, _r2, _r3 := f_EvmAbiAggregateProbe_make_matrix(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0xffac5c16 {
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
      let _r0, _r1, _r2 := f_EvmAbiAggregateProbe_make_array(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      return(0, 96)
    }
    case 0x384e9976 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(36), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmAbiAggregateProbe_sum_small(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x94f90bdd {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(36), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(68), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmAbiAggregateProbe_sum_small_matrix(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1df89823 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1) {
        revert(0, 0)
      }
      let _r := f_EvmAbiAggregateProbe_and_flags(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5e248cf3 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_EvmAbiAggregateProbe_echo_hash_pair(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd3a9b1bd {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmAbiAggregateProbe_make_hash_pair(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x44d9885a {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_EvmAbiAggregateProbe_pick_hash(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x3fcd733b {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmAbiAggregateProbe_make_hash_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    default {
      revert(0, 0)
    }
    function f_EvmAbiAggregateProbe_sum_pair(__proof_forge_struct_pair_left, __proof_forge_struct_pair_right) -> __pf_result {
      __pf_result := __pf_checked_add(__proof_forge_struct_pair_left, __proof_forge_struct_pair_right)
    }
    function f_EvmAbiAggregateProbe_sum_array(__proof_forge_array_xs_0, __proof_forge_array_xs_1, __proof_forge_array_xs_2) -> __pf_result {
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_xs_0, __proof_forge_array_xs_1), __proof_forge_array_xs_2)
    }
    function f_EvmAbiAggregateProbe_sum_matrix(__proof_forge_array_matrix_0_0, __proof_forge_array_matrix_0_1, __proof_forge_array_matrix_1_0, __proof_forge_array_matrix_1_1) -> __pf_result {
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_matrix_0_0, __proof_forge_array_matrix_0_1), __pf_checked_add(__proof_forge_array_matrix_1_0, __proof_forge_array_matrix_1_1))
    }
    function f_EvmAbiAggregateProbe_sum_pair_array(__proof_forge_array_struct_pairs_0_left, __proof_forge_array_struct_pairs_0_right, __proof_forge_array_struct_pairs_1_left, __proof_forge_array_struct_pairs_1_right) -> __pf_result {
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_struct_pairs_0_left, __proof_forge_array_struct_pairs_0_right), __pf_checked_add(__proof_forge_array_struct_pairs_1_left, __proof_forge_array_struct_pairs_1_right))
    }
    function f_EvmAbiAggregateProbe_make_pair(left, right) -> __pf_return_0, __pf_return_1 {
      __pf_return_0 := left
      __pf_return_1 := right
    }
    function f_EvmAbiAggregateProbe_make_pair_array(a, b, c, d) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      let __proof_forge_array_struct_pairs_0_left := a
      let __proof_forge_array_struct_pairs_0_right := b
      let __proof_forge_array_struct_pairs_1_left := c
      let __proof_forge_array_struct_pairs_1_right := d
      __pf_return_0 := __proof_forge_array_struct_pairs_0_left
      __pf_return_1 := __proof_forge_array_struct_pairs_0_right
      __pf_return_2 := __proof_forge_array_struct_pairs_1_left
      __pf_return_3 := __proof_forge_array_struct_pairs_1_right
    }
    function f_EvmAbiAggregateProbe_make_matrix(a, b, c, d) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0 := a
      __pf_return_1 := b
      __pf_return_2 := c
      __pf_return_3 := d
    }
    function f_EvmAbiAggregateProbe_make_array(a, b, c) -> __pf_return_0, __pf_return_1, __pf_return_2 {
      let __proof_forge_array_xs_0 := a
      let __proof_forge_array_xs_1 := b
      let __proof_forge_array_xs_2 := c
      __pf_return_0 := __proof_forge_array_xs_0
      __pf_return_1 := __proof_forge_array_xs_1
      __pf_return_2 := __proof_forge_array_xs_2
    }
    function f_EvmAbiAggregateProbe_sum_small(__proof_forge_array_xs_0, __proof_forge_array_xs_1) -> __pf_result {
      __pf_result := __pf_checked_add(__proof_forge_array_xs_0, __proof_forge_array_xs_1)
    }
    function f_EvmAbiAggregateProbe_sum_small_matrix(__proof_forge_array_xs_0_0, __proof_forge_array_xs_0_1, __proof_forge_array_xs_1_0, __proof_forge_array_xs_1_1) -> __pf_result {
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_xs_0_0, __proof_forge_array_xs_0_1), __pf_checked_add(__proof_forge_array_xs_1_0, __proof_forge_array_xs_1_1))
    }
    function f_EvmAbiAggregateProbe_and_flags(__proof_forge_struct_flags_enabled, __proof_forge_struct_flags_archived) -> __pf_result {
      __pf_result := and(__proof_forge_struct_flags_enabled, __proof_forge_struct_flags_archived)
    }
    function f_EvmAbiAggregateProbe_echo_hash_pair(__proof_forge_struct_pair_left, __proof_forge_struct_pair_right) -> __pf_result {
      __pf_result := __proof_forge_struct_pair_right
    }
    function f_EvmAbiAggregateProbe_make_hash_pair(left, right) -> __pf_return_0, __pf_return_1 {
      __pf_return_0 := left
      __pf_return_1 := right
    }
    function f_EvmAbiAggregateProbe_pick_hash(__proof_forge_array_roots_0, __proof_forge_array_roots_1) -> __pf_result {
      __pf_result := __proof_forge_array_roots_1
    }
    function f_EvmAbiAggregateProbe_make_hash_array(left, right) -> __pf_return_0, __pf_return_1 {
      __pf_return_0 := left
      __pf_return_1 := right
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
      if or(iszero(a), iszero(b)) {
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
