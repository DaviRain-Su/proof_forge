object "EvmArrayValueProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x77bd09b1 {
      let _r := f_EvmArrayValueProbe_local_sum()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x7389a736 {
      let _r := f_EvmArrayValueProbe_direct_literal_index()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x7c95ba13 {
      let _r := f_EvmArrayValueProbe_bool_guard()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa13f4ee0 {
      let _r := f_EvmArrayValueProbe_u32_pick()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x211a2fc4 {
      let _r := f_EvmArrayValueProbe_hash_pick()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x0cde63a1 {
      let _r := f_EvmArrayValueProbe_mutable_update()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x70d82dc9 {
      let _r := f_EvmArrayValueProbe_mutable_mixed()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x17e4f54c {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmArrayValueProbe_dynamic_pick(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf45e18ed {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmArrayValueProbe_dynamic_update(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd59d3191 {
      let _r := f_EvmArrayValueProbe_whole_array_assign()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc54814ec {
      let _r := f_EvmArrayValueProbe_nested_local_sum()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x69c5b925 {
      let _r := f_EvmArrayValueProbe_nested_mutable_update()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1c21ce7e {
      let _r := f_EvmArrayValueProbe_nested_whole_array_assign()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xdeb5ba01 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_EvmArrayValueProbe_nested_dynamic_pick(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x731f5daf {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmArrayValueProbe_nested_dynamic_row_pick(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xbd33c419 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_EvmArrayValueProbe_nested_dynamic_update(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x69437a57 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmArrayValueProbe_nested_dynamic_row_update(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmArrayValueProbe_local_sum() -> result {
      let __proof_forge_array_xs_0 := 7
      let __proof_forge_array_xs_1 := 11
      let __proof_forge_array_xs_2 := 13
      let head := __proof_forge_array_xs_0
      result := __pf_checked_add(head, __proof_forge_array_xs_2)
    }
    function f_EvmArrayValueProbe_direct_literal_index() -> result {
      result := 6
    }
    function f_EvmArrayValueProbe_bool_guard() -> result {
      let __proof_forge_array_flags_0 := 0
      let __proof_forge_array_flags_1 := 1
      if iszero(__proof_forge_array_flags_1) {
        revert(0, 0)
      }
      result := __proof_forge_array_flags_0
    }
    function f_EvmArrayValueProbe_u32_pick() -> result {
      let __proof_forge_array_smalls_0 := 3
      let __proof_forge_array_smalls_1 := 5
      result := __proof_forge_array_smalls_1
    }
    function f_EvmArrayValueProbe_hash_pick() -> result {
      let __proof_forge_array_roots_0 := 6277101735386680764516354157049543343084444891548699590660
      let __proof_forge_array_roots_1 := 31385508676933403821220641317563962861421152075426748694536
      result := __proof_forge_array_roots_0
    }
    function f_EvmArrayValueProbe_mutable_update() -> result {
      let __proof_forge_array_xs_0 := 7
      let __proof_forge_array_xs_1 := 11
      let __proof_forge_array_xs_2 := 13
      __proof_forge_array_xs_1 := 19
      __proof_forge_array_xs_2 := __pf_checked_add(__proof_forge_array_xs_2, 5)
      result := __pf_checked_add(__proof_forge_array_xs_1, __proof_forge_array_xs_2)
    }
    function f_EvmArrayValueProbe_mutable_mixed() -> result {
      let __proof_forge_array_flags_0 := 0
      let __proof_forge_array_flags_1 := 0
      __proof_forge_array_flags_0 := 1
      if iszero(__proof_forge_array_flags_0) {
        revert(0, 0)
      }
      let __proof_forge_array_smalls_0 := 3
      let __proof_forge_array_smalls_1 := 5
      __proof_forge_array_smalls_1 := 9
      let __proof_forge_array_roots_0 := 6277101735386680764516354157049543343084444891548699590660
      let __proof_forge_array_roots_1 := 31385508676933403821220641317563962861421152075426748694536
      __proof_forge_array_roots_1 := 56493915618480126877924928478078382379757859259304797798412
      if iszero(eq(__proof_forge_array_roots_1, 56493915618480126877924928478078382379757859259304797798412)) {
        revert(0, 0)
      }
      result := __pf_checked_add(__proof_forge_array_flags_0, __proof_forge_array_smalls_1)
    }
    function f_EvmArrayValueProbe_dynamic_pick(idx) -> result {
      let __proof_forge_array_xs_0 := 7
      let __proof_forge_array_xs_1 := 11
      let __proof_forge_array_xs_2 := 13
      result := __pf_checked_add(__proof_forge_local_array_get_3(idx, __proof_forge_array_xs_0, __proof_forge_array_xs_1, __proof_forge_array_xs_2), __proof_forge_local_array_get_3(idx, 4, 6, 8))
    }
    function f_EvmArrayValueProbe_dynamic_update(idx) -> result {
      let __proof_forge_array_xs_0 := 7
      let __proof_forge_array_xs_1 := 11
      let __proof_forge_array_xs_2 := 13
      {
        let __proof_forge_array_index := idx
        let __proof_forge_array_value := 20
        switch __proof_forge_array_index
        case 0 {
          __proof_forge_array_xs_0 := __proof_forge_array_value
        }
        case 1 {
          __proof_forge_array_xs_1 := __proof_forge_array_value
        }
        case 2 {
          __proof_forge_array_xs_2 := __proof_forge_array_value
        }
        default {
          revert(0, 0)
        }
      }
      {
        let __proof_forge_array_index := idx
        let __proof_forge_array_value := 3
        switch __proof_forge_array_index
        case 0 {
          __proof_forge_array_xs_0 := __pf_checked_add(__proof_forge_array_xs_0, __proof_forge_array_value)
        }
        case 1 {
          __proof_forge_array_xs_1 := __pf_checked_add(__proof_forge_array_xs_1, __proof_forge_array_value)
        }
        case 2 {
          __proof_forge_array_xs_2 := __pf_checked_add(__proof_forge_array_xs_2, __proof_forge_array_value)
        }
        default {
          revert(0, 0)
        }
      }
      result := __proof_forge_local_array_get_3(idx, __proof_forge_array_xs_0, __proof_forge_array_xs_1, __proof_forge_array_xs_2)
    }
    function f_EvmArrayValueProbe_whole_array_assign() -> result {
      let __proof_forge_array_xs_0 := 1
      let __proof_forge_array_xs_1 := 2
      let __proof_forge_array_xs_2 := 3
      let __proof_forge_array_ys_0 := 7
      let __proof_forge_array_ys_1 := 11
      let __proof_forge_array_ys_2 := 13
      {
        let __proof_forge_assign_array_xs_0 := __proof_forge_array_ys_0
        let __proof_forge_assign_array_xs_1 := __proof_forge_array_ys_1
        let __proof_forge_assign_array_xs_2 := __proof_forge_array_ys_2
        __proof_forge_array_xs_0 := __proof_forge_assign_array_xs_0
        __proof_forge_array_xs_1 := __proof_forge_assign_array_xs_1
        __proof_forge_array_xs_2 := __proof_forge_assign_array_xs_2
      }
      {
        let __proof_forge_assign_array_xs_0 := __proof_forge_array_xs_1
        let __proof_forge_assign_array_xs_1 := __proof_forge_array_xs_0
        let __proof_forge_assign_array_xs_2 := __proof_forge_array_xs_2
        __proof_forge_array_xs_0 := __proof_forge_assign_array_xs_0
        __proof_forge_array_xs_1 := __proof_forge_assign_array_xs_1
        __proof_forge_array_xs_2 := __proof_forge_assign_array_xs_2
      }
      result := __pf_checked_add(__pf_checked_add(__proof_forge_array_xs_0, __pf_checked_mul(__proof_forge_array_xs_1, 10)), __proof_forge_array_xs_2)
    }
    function f_EvmArrayValueProbe_nested_local_sum() -> result {
      let __proof_forge_array_matrix_0_0 := 2
      let __proof_forge_array_matrix_0_1 := 3
      let __proof_forge_array_matrix_1_0 := 5
      let __proof_forge_array_matrix_1_1 := 7
      result := __pf_checked_add(__proof_forge_array_matrix_0_1, __proof_forge_array_matrix_1_0)
    }
    function f_EvmArrayValueProbe_nested_mutable_update() -> result {
      let __proof_forge_array_matrix_0_0 := 2
      let __proof_forge_array_matrix_0_1 := 3
      let __proof_forge_array_matrix_1_0 := 5
      let __proof_forge_array_matrix_1_1 := 7
      __proof_forge_array_matrix_1_0 := 17
      __proof_forge_array_matrix_0_1 := __pf_checked_add(__proof_forge_array_matrix_0_1, 4)
      result := __pf_checked_add(__proof_forge_array_matrix_1_0, __proof_forge_array_matrix_0_1)
    }
    function f_EvmArrayValueProbe_nested_whole_array_assign() -> result {
      let __proof_forge_array_matrix_0_0 := 1
      let __proof_forge_array_matrix_0_1 := 2
      let __proof_forge_array_matrix_1_0 := 3
      let __proof_forge_array_matrix_1_1 := 4
      let __proof_forge_array_other_0_0 := 5
      let __proof_forge_array_other_0_1 := 7
      let __proof_forge_array_other_1_0 := 11
      let __proof_forge_array_other_1_1 := 13
      {
        let __proof_forge_assign_array_matrix_0_0 := __proof_forge_array_other_0_0
        let __proof_forge_assign_array_matrix_0_1 := __proof_forge_array_other_0_1
        let __proof_forge_assign_array_matrix_1_0 := __proof_forge_array_other_1_0
        let __proof_forge_assign_array_matrix_1_1 := __proof_forge_array_other_1_1
        __proof_forge_array_matrix_0_0 := __proof_forge_assign_array_matrix_0_0
        __proof_forge_array_matrix_0_1 := __proof_forge_assign_array_matrix_0_1
        __proof_forge_array_matrix_1_0 := __proof_forge_assign_array_matrix_1_0
        __proof_forge_array_matrix_1_1 := __proof_forge_assign_array_matrix_1_1
      }
      {
        let __proof_forge_assign_array_matrix_0_0 := __proof_forge_array_matrix_1_0
        let __proof_forge_assign_array_matrix_0_1 := __proof_forge_array_matrix_0_1
        let __proof_forge_assign_array_matrix_1_0 := __proof_forge_array_matrix_0_0
        let __proof_forge_assign_array_matrix_1_1 := __proof_forge_array_matrix_1_1
        __proof_forge_array_matrix_0_0 := __proof_forge_assign_array_matrix_0_0
        __proof_forge_array_matrix_0_1 := __proof_forge_assign_array_matrix_0_1
        __proof_forge_array_matrix_1_0 := __proof_forge_assign_array_matrix_1_0
        __proof_forge_array_matrix_1_1 := __proof_forge_assign_array_matrix_1_1
      }
      result := __pf_checked_add(__pf_checked_add(__proof_forge_array_matrix_0_0, __pf_checked_mul(__proof_forge_array_matrix_0_1, 10)), __pf_checked_add(__pf_checked_mul(__proof_forge_array_matrix_1_0, 100), __pf_checked_mul(__proof_forge_array_matrix_1_1, 1000)))
    }
    function f_EvmArrayValueProbe_nested_dynamic_pick(row, col) -> result {
      let __proof_forge_array_matrix_0_0 := 2
      let __proof_forge_array_matrix_0_1 := 3
      let __proof_forge_array_matrix_1_0 := 5
      let __proof_forge_array_matrix_1_1 := 7
      result := __proof_forge_local_array_get_nested_2_2(row, col, __proof_forge_array_matrix_0_0, __proof_forge_array_matrix_0_1, __proof_forge_array_matrix_1_0, __proof_forge_array_matrix_1_1)
    }
    function f_EvmArrayValueProbe_nested_dynamic_row_pick(row) -> result {
      let __proof_forge_array_matrix_0_0 := 2
      let __proof_forge_array_matrix_0_1 := 3
      let __proof_forge_array_matrix_1_0 := 5
      let __proof_forge_array_matrix_1_1 := 7
      result := __proof_forge_local_array_get_nested_2_2(row, 1, __proof_forge_array_matrix_0_0, __proof_forge_array_matrix_0_1, __proof_forge_array_matrix_1_0, __proof_forge_array_matrix_1_1)
    }
    function f_EvmArrayValueProbe_nested_dynamic_update(row, col) -> result {
      let __proof_forge_array_matrix_0_0 := 2
      let __proof_forge_array_matrix_0_1 := 3
      let __proof_forge_array_matrix_1_0 := 5
      let __proof_forge_array_matrix_1_1 := 7
      {
        let __proof_forge_array_value := 20
        {
          let __proof_forge_array_index_0 := row
          switch __proof_forge_array_index_0
          case 0 {
            {
              let __proof_forge_array_index_1 := col
              switch __proof_forge_array_index_1
              case 0 {
                __proof_forge_array_matrix_0_0 := __proof_forge_array_value
              }
              case 1 {
                __proof_forge_array_matrix_0_1 := __proof_forge_array_value
              }
              default {
                revert(0, 0)
              }
            }
          }
          case 1 {
            {
              let __proof_forge_array_index_1 := col
              switch __proof_forge_array_index_1
              case 0 {
                __proof_forge_array_matrix_1_0 := __proof_forge_array_value
              }
              case 1 {
                __proof_forge_array_matrix_1_1 := __proof_forge_array_value
              }
              default {
                revert(0, 0)
              }
            }
          }
          default {
            revert(0, 0)
          }
        }
      }
      {
        let __proof_forge_array_value := 3
        {
          let __proof_forge_array_index_0 := row
          switch __proof_forge_array_index_0
          case 0 {
            {
              let __proof_forge_array_index_1 := col
              switch __proof_forge_array_index_1
              case 0 {
                __proof_forge_array_matrix_0_0 := __pf_checked_add(__proof_forge_array_matrix_0_0, __proof_forge_array_value)
              }
              case 1 {
                __proof_forge_array_matrix_0_1 := __pf_checked_add(__proof_forge_array_matrix_0_1, __proof_forge_array_value)
              }
              default {
                revert(0, 0)
              }
            }
          }
          case 1 {
            {
              let __proof_forge_array_index_1 := col
              switch __proof_forge_array_index_1
              case 0 {
                __proof_forge_array_matrix_1_0 := __pf_checked_add(__proof_forge_array_matrix_1_0, __proof_forge_array_value)
              }
              case 1 {
                __proof_forge_array_matrix_1_1 := __pf_checked_add(__proof_forge_array_matrix_1_1, __proof_forge_array_value)
              }
              default {
                revert(0, 0)
              }
            }
          }
          default {
            revert(0, 0)
          }
        }
      }
      result := __proof_forge_local_array_get_nested_2_2(row, col, __proof_forge_array_matrix_0_0, __proof_forge_array_matrix_0_1, __proof_forge_array_matrix_1_0, __proof_forge_array_matrix_1_1)
    }
    function f_EvmArrayValueProbe_nested_dynamic_row_update(row) -> result {
      let __proof_forge_array_matrix_0_0 := 2
      let __proof_forge_array_matrix_0_1 := 3
      let __proof_forge_array_matrix_1_0 := 5
      let __proof_forge_array_matrix_1_1 := 7
      {
        let __proof_forge_array_value := 20
        {
          let __proof_forge_array_index_0 := row
          switch __proof_forge_array_index_0
          case 0 {
            __proof_forge_array_matrix_0_1 := __proof_forge_array_value
          }
          case 1 {
            __proof_forge_array_matrix_1_1 := __proof_forge_array_value
          }
          default {
            revert(0, 0)
          }
        }
      }
      {
        let __proof_forge_array_value := 3
        {
          let __proof_forge_array_index_0 := row
          switch __proof_forge_array_index_0
          case 0 {
            __proof_forge_array_matrix_0_1 := __pf_checked_add(__proof_forge_array_matrix_0_1, __proof_forge_array_value)
          }
          case 1 {
            __proof_forge_array_matrix_1_1 := __pf_checked_add(__proof_forge_array_matrix_1_1, __proof_forge_array_value)
          }
          default {
            revert(0, 0)
          }
        }
      }
      result := __proof_forge_local_array_get_nested_2_2(row, 1, __proof_forge_array_matrix_0_0, __proof_forge_array_matrix_0_1, __proof_forge_array_matrix_1_0, __proof_forge_array_matrix_1_1)
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
    function __proof_forge_local_array_get_3(index, value_0, value_1, value_2) -> result {
      switch index
      case 0 {
        result := value_0
      }
      case 1 {
        result := value_1
      }
      case 2 {
        result := value_2
      }
      default {
        revert(0, 0)
      }
    }
    function __proof_forge_local_array_get_nested_2_2(index_0, index_1, value_0_0, value_0_1, value_1_0, value_1_1) -> result {
      switch index_0
      case 0 {
        switch index_1
        case 0 {
          result := value_0_0
        }
        case 1 {
          result := value_0_1
        }
        default {
          revert(0, 0)
        }
      }
      case 1 {
        switch index_1
        case 0 {
          result := value_1_0
        }
        case 1 {
          result := value_1_1
        }
        default {
          revert(0, 0)
        }
      }
      default {
        revert(0, 0)
      }
    }
  }
}
