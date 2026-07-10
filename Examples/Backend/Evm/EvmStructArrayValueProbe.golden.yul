object "EvmStructArrayValueProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x6dcefec0 {
      let _r := f_EvmStructArrayValueProbe_local_struct_array_sum()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x0601d7ac {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmStructArrayValueProbe_dynamic_struct_array_pick(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xbfa2eef8 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmStructArrayValueProbe_mutable_struct_array_update(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc8c9bc70 {
      let _r := f_EvmStructArrayValueProbe_static_struct_array_update()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x8c32c4da {
      let _r := f_EvmStructArrayValueProbe_mixed_struct_array_fields()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xcd4a0dc2 {
      let _r := f_EvmStructArrayValueProbe_whole_struct_array_assign()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe5ea5747 {
      let _r := f_EvmStructArrayValueProbe_self_struct_array_assign()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x25daebe2 {
      let _r := f_EvmStructArrayValueProbe_nested_struct_array_sum()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x56d9da6f {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmStructArrayValueProbe_nested_struct_array_dynamic_pick(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd29b2aa1 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmStructArrayValueProbe_nested_struct_array_update(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x3bd4106e {
      let _r := f_EvmStructArrayValueProbe_nested_struct_array_whole_assign()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xcd232639 {
      let _r := f_EvmStructArrayValueProbe_nested_struct_array_self_assign()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmStructArrayValueProbe_local_struct_array_sum() -> __pf_result {
      let __proof_forge_array_struct_people_0_age := 10
      let __proof_forge_array_struct_people_0_score := 80
      let __proof_forge_array_struct_people_1_age := 20
      let __proof_forge_array_struct_people_1_score := 90
      __pf_result := __pf_checked_add(__proof_forge_array_struct_people_0_age, __proof_forge_array_struct_people_1_score)
    }
    function f_EvmStructArrayValueProbe_dynamic_struct_array_pick(idx) -> __pf_result {
      let __proof_forge_array_struct_people_0_age := 10
      let __proof_forge_array_struct_people_0_score := 80
      let __proof_forge_array_struct_people_1_age := 20
      let __proof_forge_array_struct_people_1_score := 90
      __pf_result := __pf_checked_add(__proof_forge_local_array_get_2(idx, __proof_forge_array_struct_people_0_age, __proof_forge_array_struct_people_1_age), __proof_forge_local_array_get_2(idx, __proof_forge_array_struct_people_0_score, __proof_forge_array_struct_people_1_score))
    }
    function f_EvmStructArrayValueProbe_mutable_struct_array_update(idx) -> __pf_result {
      let __proof_forge_array_struct_people_0_age := 10
      let __proof_forge_array_struct_people_0_score := 80
      let __proof_forge_array_struct_people_1_age := 20
      let __proof_forge_array_struct_people_1_score := 90
      {
        let __proof_forge_array_index := idx
        let __proof_forge_array_value := 30
        switch __proof_forge_array_index
        case 0 {
          __proof_forge_array_struct_people_0_age := __proof_forge_array_value
        }
        case 1 {
          __proof_forge_array_struct_people_1_age := __proof_forge_array_value
        }
        default {
          revert(0, 0)
        }
      }
      {
        let __proof_forge_array_index := idx
        let __proof_forge_array_value := 7
        switch __proof_forge_array_index
        case 0 {
          __proof_forge_array_struct_people_0_score := __pf_checked_add(__proof_forge_array_struct_people_0_score, __proof_forge_array_value)
        }
        case 1 {
          __proof_forge_array_struct_people_1_score := __pf_checked_add(__proof_forge_array_struct_people_1_score, __proof_forge_array_value)
        }
        default {
          revert(0, 0)
        }
      }
      __pf_result := __pf_checked_add(__proof_forge_local_array_get_2(idx, __proof_forge_array_struct_people_0_age, __proof_forge_array_struct_people_1_age), __proof_forge_local_array_get_2(idx, __proof_forge_array_struct_people_0_score, __proof_forge_array_struct_people_1_score))
    }
    function f_EvmStructArrayValueProbe_static_struct_array_update() -> __pf_result {
      let __proof_forge_array_struct_people_0_age := 10
      let __proof_forge_array_struct_people_0_score := 80
      let __proof_forge_array_struct_people_1_age := 20
      let __proof_forge_array_struct_people_1_score := 90
      __proof_forge_array_struct_people_1_age := 33
      __proof_forge_array_struct_people_0_score := add(__proof_forge_array_struct_people_0_score, 5)
      __pf_result := __pf_checked_add(__proof_forge_array_struct_people_0_score, __proof_forge_array_struct_people_1_age)
    }
    function f_EvmStructArrayValueProbe_mixed_struct_array_fields() -> __pf_result {
      let __proof_forge_array_struct_rows_0_enabled := 0
      let __proof_forge_array_struct_rows_0_small := 7
      let __proof_forge_array_struct_rows_0_root := 6277101735386680764516354157049543343084444891548699590660
      let __proof_forge_array_struct_rows_1_enabled := 1
      let __proof_forge_array_struct_rows_1_small := 9
      let __proof_forge_array_struct_rows_1_root := 31385508676933403821220641317563962861421152075426748694536
      __proof_forge_array_struct_rows_0_enabled := 1
      __proof_forge_array_struct_rows_1_small := 11
      __proof_forge_array_struct_rows_0_root := 56493915618480126877924928478078382379757859259304797798412
      if iszero(__proof_forge_array_struct_rows_0_enabled) {
        revert(0, 0)
      }
      if iszero(eq(__proof_forge_array_struct_rows_0_root, 56493915618480126877924928478078382379757859259304797798412)) {
        revert(0, 0)
      }
      __pf_result := __pf_checked_add(__proof_forge_array_struct_rows_1_small, __proof_forge_array_struct_rows_0_enabled)
    }
    function f_EvmStructArrayValueProbe_whole_struct_array_assign() -> __pf_result {
      let __proof_forge_array_struct_people_0_age := 1
      let __proof_forge_array_struct_people_0_score := 2
      let __proof_forge_array_struct_people_1_age := 3
      let __proof_forge_array_struct_people_1_score := 4
      let __proof_forge_array_struct_next_0_age := 11
      let __proof_forge_array_struct_next_0_score := 13
      let __proof_forge_array_struct_next_1_age := 17
      let __proof_forge_array_struct_next_1_score := 19
      {
        let __proof_forge_assign_array_struct_people_0_age := __proof_forge_array_struct_next_0_age
        let __proof_forge_assign_array_struct_people_0_score := __proof_forge_array_struct_next_0_score
        let __proof_forge_assign_array_struct_people_1_age := __proof_forge_array_struct_next_1_age
        let __proof_forge_assign_array_struct_people_1_score := __proof_forge_array_struct_next_1_score
        __proof_forge_array_struct_people_0_age := __proof_forge_assign_array_struct_people_0_age
        __proof_forge_array_struct_people_0_score := __proof_forge_assign_array_struct_people_0_score
        __proof_forge_array_struct_people_1_age := __proof_forge_assign_array_struct_people_1_age
        __proof_forge_array_struct_people_1_score := __proof_forge_assign_array_struct_people_1_score
      }
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_struct_people_0_age, __proof_forge_array_struct_people_0_score), __pf_checked_add(__proof_forge_array_struct_people_1_age, __proof_forge_array_struct_people_1_score))
    }
    function f_EvmStructArrayValueProbe_self_struct_array_assign() -> __pf_result {
      let __proof_forge_array_struct_people_0_age := 5
      let __proof_forge_array_struct_people_0_score := 7
      let __proof_forge_array_struct_people_1_age := 11
      let __proof_forge_array_struct_people_1_score := 13
      {
        let __proof_forge_assign_array_struct_people_0_age := __proof_forge_array_struct_people_1_age
        let __proof_forge_assign_array_struct_people_0_score := __proof_forge_array_struct_people_0_score
        let __proof_forge_assign_array_struct_people_1_age := __proof_forge_array_struct_people_0_age
        let __proof_forge_assign_array_struct_people_1_score := __proof_forge_array_struct_people_1_score
        __proof_forge_array_struct_people_0_age := __proof_forge_assign_array_struct_people_0_age
        __proof_forge_array_struct_people_0_score := __proof_forge_assign_array_struct_people_0_score
        __proof_forge_array_struct_people_1_age := __proof_forge_assign_array_struct_people_1_age
        __proof_forge_array_struct_people_1_score := __proof_forge_assign_array_struct_people_1_score
      }
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_struct_people_0_age, __proof_forge_array_struct_people_0_score), __pf_checked_add(__proof_forge_array_struct_people_1_age, __proof_forge_array_struct_people_1_score))
    }
    function f_EvmStructArrayValueProbe_nested_struct_array_sum() -> __pf_result {
      let __proof_forge_array_struct_grid_0_0_age := 10
      let __proof_forge_array_struct_grid_0_0_score := 80
      let __proof_forge_array_struct_grid_0_1_age := 20
      let __proof_forge_array_struct_grid_0_1_score := 90
      let __proof_forge_array_struct_grid_1_0_age := 30
      let __proof_forge_array_struct_grid_1_0_score := 100
      let __proof_forge_array_struct_grid_1_1_age := 40
      let __proof_forge_array_struct_grid_1_1_score := 110
      __pf_result := __pf_checked_add(__proof_forge_array_struct_grid_1_0_age, __proof_forge_array_struct_grid_0_1_score)
    }
    function f_EvmStructArrayValueProbe_nested_struct_array_dynamic_pick(row, col) -> __pf_result {
      let __proof_forge_array_struct_grid_0_0_age := 10
      let __proof_forge_array_struct_grid_0_0_score := 80
      let __proof_forge_array_struct_grid_0_1_age := 20
      let __proof_forge_array_struct_grid_0_1_score := 90
      let __proof_forge_array_struct_grid_1_0_age := 30
      let __proof_forge_array_struct_grid_1_0_score := 100
      let __proof_forge_array_struct_grid_1_1_age := 40
      let __proof_forge_array_struct_grid_1_1_score := 110
      __pf_result := __pf_checked_add(__proof_forge_local_array_get_nested_2_2(row, col, __proof_forge_array_struct_grid_0_0_age, __proof_forge_array_struct_grid_0_1_age, __proof_forge_array_struct_grid_1_0_age, __proof_forge_array_struct_grid_1_1_age), __proof_forge_local_array_get_nested_2_2(row, col, __proof_forge_array_struct_grid_0_0_score, __proof_forge_array_struct_grid_0_1_score, __proof_forge_array_struct_grid_1_0_score, __proof_forge_array_struct_grid_1_1_score))
    }
    function f_EvmStructArrayValueProbe_nested_struct_array_update(row, col) -> __pf_result {
      let __proof_forge_array_struct_grid_0_0_age := 10
      let __proof_forge_array_struct_grid_0_0_score := 80
      let __proof_forge_array_struct_grid_0_1_age := 20
      let __proof_forge_array_struct_grid_0_1_score := 90
      let __proof_forge_array_struct_grid_1_0_age := 30
      let __proof_forge_array_struct_grid_1_0_score := 100
      let __proof_forge_array_struct_grid_1_1_age := 40
      let __proof_forge_array_struct_grid_1_1_score := 110
      {
        let __proof_forge_array_value := 50
        {
          let __proof_forge_array_index_0 := row
          switch __proof_forge_array_index_0
          case 0 {
            {
              let __proof_forge_array_index_1 := col
              switch __proof_forge_array_index_1
              case 0 {
                __proof_forge_array_struct_grid_0_0_age := __proof_forge_array_value
              }
              case 1 {
                __proof_forge_array_struct_grid_0_1_age := __proof_forge_array_value
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
                __proof_forge_array_struct_grid_1_0_age := __proof_forge_array_value
              }
              case 1 {
                __proof_forge_array_struct_grid_1_1_age := __proof_forge_array_value
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
        let __proof_forge_array_value := 7
        {
          let __proof_forge_array_index_0 := row
          switch __proof_forge_array_index_0
          case 0 {
            {
              let __proof_forge_array_index_1 := col
              switch __proof_forge_array_index_1
              case 0 {
                __proof_forge_array_struct_grid_0_0_score := __pf_checked_add(__proof_forge_array_struct_grid_0_0_score, __proof_forge_array_value)
              }
              case 1 {
                __proof_forge_array_struct_grid_0_1_score := __pf_checked_add(__proof_forge_array_struct_grid_0_1_score, __proof_forge_array_value)
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
                __proof_forge_array_struct_grid_1_0_score := __pf_checked_add(__proof_forge_array_struct_grid_1_0_score, __proof_forge_array_value)
              }
              case 1 {
                __proof_forge_array_struct_grid_1_1_score := __pf_checked_add(__proof_forge_array_struct_grid_1_1_score, __proof_forge_array_value)
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
      __pf_result := __pf_checked_add(__proof_forge_local_array_get_nested_2_2(row, col, __proof_forge_array_struct_grid_0_0_age, __proof_forge_array_struct_grid_0_1_age, __proof_forge_array_struct_grid_1_0_age, __proof_forge_array_struct_grid_1_1_age), __proof_forge_local_array_get_nested_2_2(row, col, __proof_forge_array_struct_grid_0_0_score, __proof_forge_array_struct_grid_0_1_score, __proof_forge_array_struct_grid_1_0_score, __proof_forge_array_struct_grid_1_1_score))
    }
    function f_EvmStructArrayValueProbe_nested_struct_array_whole_assign() -> __pf_result {
      let __proof_forge_array_struct_grid_0_0_age := 1
      let __proof_forge_array_struct_grid_0_0_score := 2
      let __proof_forge_array_struct_grid_0_1_age := 3
      let __proof_forge_array_struct_grid_0_1_score := 4
      let __proof_forge_array_struct_grid_1_0_age := 5
      let __proof_forge_array_struct_grid_1_0_score := 6
      let __proof_forge_array_struct_grid_1_1_age := 7
      let __proof_forge_array_struct_grid_1_1_score := 8
      let __proof_forge_array_struct_next_0_0_age := 11
      let __proof_forge_array_struct_next_0_0_score := 13
      let __proof_forge_array_struct_next_0_1_age := 17
      let __proof_forge_array_struct_next_0_1_score := 19
      let __proof_forge_array_struct_next_1_0_age := 23
      let __proof_forge_array_struct_next_1_0_score := 29
      let __proof_forge_array_struct_next_1_1_age := 31
      let __proof_forge_array_struct_next_1_1_score := 37
      {
        let __proof_forge_assign_array_struct_grid_0_0_age := __proof_forge_array_struct_next_0_0_age
        let __proof_forge_assign_array_struct_grid_0_0_score := __proof_forge_array_struct_next_0_0_score
        let __proof_forge_assign_array_struct_grid_0_1_age := __proof_forge_array_struct_next_0_1_age
        let __proof_forge_assign_array_struct_grid_0_1_score := __proof_forge_array_struct_next_0_1_score
        let __proof_forge_assign_array_struct_grid_1_0_age := __proof_forge_array_struct_next_1_0_age
        let __proof_forge_assign_array_struct_grid_1_0_score := __proof_forge_array_struct_next_1_0_score
        let __proof_forge_assign_array_struct_grid_1_1_age := __proof_forge_array_struct_next_1_1_age
        let __proof_forge_assign_array_struct_grid_1_1_score := __proof_forge_array_struct_next_1_1_score
        __proof_forge_array_struct_grid_0_0_age := __proof_forge_assign_array_struct_grid_0_0_age
        __proof_forge_array_struct_grid_0_0_score := __proof_forge_assign_array_struct_grid_0_0_score
        __proof_forge_array_struct_grid_0_1_age := __proof_forge_assign_array_struct_grid_0_1_age
        __proof_forge_array_struct_grid_0_1_score := __proof_forge_assign_array_struct_grid_0_1_score
        __proof_forge_array_struct_grid_1_0_age := __proof_forge_assign_array_struct_grid_1_0_age
        __proof_forge_array_struct_grid_1_0_score := __proof_forge_assign_array_struct_grid_1_0_score
        __proof_forge_array_struct_grid_1_1_age := __proof_forge_assign_array_struct_grid_1_1_age
        __proof_forge_array_struct_grid_1_1_score := __proof_forge_assign_array_struct_grid_1_1_score
      }
      __pf_result := __pf_checked_add(__pf_checked_add(__pf_checked_add(__proof_forge_array_struct_grid_0_0_age, __proof_forge_array_struct_grid_0_0_score), __pf_checked_add(__proof_forge_array_struct_grid_0_1_age, __proof_forge_array_struct_grid_0_1_score)), __pf_checked_add(__pf_checked_add(__proof_forge_array_struct_grid_1_0_age, __proof_forge_array_struct_grid_1_0_score), __pf_checked_add(__proof_forge_array_struct_grid_1_1_age, __proof_forge_array_struct_grid_1_1_score)))
    }
    function f_EvmStructArrayValueProbe_nested_struct_array_self_assign() -> __pf_result {
      let __proof_forge_array_struct_grid_0_0_age := 1
      let __proof_forge_array_struct_grid_0_0_score := 2
      let __proof_forge_array_struct_grid_0_1_age := 3
      let __proof_forge_array_struct_grid_0_1_score := 4
      let __proof_forge_array_struct_grid_1_0_age := 5
      let __proof_forge_array_struct_grid_1_0_score := 6
      let __proof_forge_array_struct_grid_1_1_age := 7
      let __proof_forge_array_struct_grid_1_1_score := 8
      {
        let __proof_forge_assign_array_struct_grid_0_0_age := __proof_forge_array_struct_grid_1_1_age
        let __proof_forge_assign_array_struct_grid_0_0_score := 100
        let __proof_forge_assign_array_struct_grid_0_1_age := __proof_forge_array_struct_grid_0_0_age
        let __proof_forge_assign_array_struct_grid_0_1_score := 200
        let __proof_forge_assign_array_struct_grid_1_0_age := __proof_forge_array_struct_grid_0_1_age
        let __proof_forge_assign_array_struct_grid_1_0_score := 300
        let __proof_forge_assign_array_struct_grid_1_1_age := __proof_forge_array_struct_grid_1_0_age
        let __proof_forge_assign_array_struct_grid_1_1_score := 400
        __proof_forge_array_struct_grid_0_0_age := __proof_forge_assign_array_struct_grid_0_0_age
        __proof_forge_array_struct_grid_0_0_score := __proof_forge_assign_array_struct_grid_0_0_score
        __proof_forge_array_struct_grid_0_1_age := __proof_forge_assign_array_struct_grid_0_1_age
        __proof_forge_array_struct_grid_0_1_score := __proof_forge_assign_array_struct_grid_0_1_score
        __proof_forge_array_struct_grid_1_0_age := __proof_forge_assign_array_struct_grid_1_0_age
        __proof_forge_array_struct_grid_1_0_score := __proof_forge_assign_array_struct_grid_1_0_score
        __proof_forge_array_struct_grid_1_1_age := __proof_forge_assign_array_struct_grid_1_1_age
        __proof_forge_array_struct_grid_1_1_score := __proof_forge_assign_array_struct_grid_1_1_score
      }
      __pf_result := __pf_checked_add(__proof_forge_array_struct_grid_0_0_age, __proof_forge_array_struct_grid_0_1_age)
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
    function __proof_forge_local_array_get_2(index, value_0, value_1) -> result {
      switch index
      case 0 {
        result := value_0
      }
      case 1 {
        result := value_1
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
