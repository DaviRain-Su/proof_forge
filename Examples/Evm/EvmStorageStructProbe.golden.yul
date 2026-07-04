object "EvmStorageStructProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x93ddf147 {
      let _r := f_EvmStorageStructProbe_struct_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x84c21205 {
      let _r := f_EvmStorageStructProbe_path_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x2d84bb06 {
      let _r := f_EvmStorageStructProbe_array_struct_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd16ccd19 {
      let _r0, _r1, _r2, _r3 := f_EvmStorageStructProbe_return_points()
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x2991a157 {
      let _r := f_EvmStorageStructProbe_array_path_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x2ec467be {
      let _r := f_EvmStorageStructProbe_typed_sum()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc42f8c06 {
      let _r := f_EvmStorageStructProbe_root_value()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc1e31e63 {
      let _r := f_EvmStorageStructProbe_whole_struct_write_sum()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xcd13529b {
      let _r0, _r1 := f_EvmStorageStructProbe_whole_struct_return()
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x696ddaa7 {
      let _r := f_EvmStorageStructProbe_self_struct_storage_write()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xdb006782 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmStorageStructProbe_read_point_x(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmStorageStructProbe_struct_lifecycle() -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 111)))
      sstore(3, or(and(sload(3), not(shl(192, 18446744073709551615))), shl(192, 222)))
      sstore(1, 7)
      sstore(2, 11)
      result := __pf_checked_add(sload(1), sload(2))
    }
    function f_EvmStorageStructProbe_path_lifecycle() -> result {
      sstore(1, 21)
      sstore(2, 22)
      {
        let _slot := 1
        sstore(_slot, __pf_checked_add(sload(_slot), 5))
      }
      result := __pf_checked_add(sload(1), sload(2))
    }
    function f_EvmStorageStructProbe_array_struct_lifecycle() -> result {
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 0, 0), 3)
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 1, 0), 5)
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 0, 1), 7)
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 1, 1), 11)
      result := __pf_checked_add(sload(__proof_forge_struct_array_slot(4, 2, 2, 0, 1)), sload(__proof_forge_struct_array_slot(4, 2, 2, 1, 0)))
    }
    function f_EvmStorageStructProbe_return_points() -> __proof_forge_return_0, __proof_forge_return_1, __proof_forge_return_2, __proof_forge_return_3 {
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 0, 0), 29)
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 1, 0), 31)
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 0, 1), 37)
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 1, 1), 41)
      __proof_forge_return_0 := sload(__proof_forge_struct_array_slot(4, 2, 2, 0, 0))
      __proof_forge_return_1 := sload(__proof_forge_struct_array_slot(4, 2, 2, 1, 0))
      __proof_forge_return_2 := sload(__proof_forge_struct_array_slot(4, 2, 2, 0, 1))
      __proof_forge_return_3 := sload(__proof_forge_struct_array_slot(4, 2, 2, 1, 1))
    }
    function f_EvmStorageStructProbe_array_path_lifecycle() -> result {
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 0, 1), 13)
      {
        let _slot := __proof_forge_struct_array_slot(4, 2, 2, 0, 1)
        sstore(_slot, __pf_checked_add(sload(_slot), 2))
      }
      sstore(__proof_forge_struct_array_slot(4, 2, 2, 1, 0), 8)
      result := __pf_checked_add(sload(__proof_forge_struct_array_slot(4, 2, 2, 0, 1)), sload(__proof_forge_struct_array_slot(4, 2, 2, 1, 0)))
    }
    function f_EvmStorageStructProbe_typed_sum() -> result {
      sstore(8, 1)
      sstore(9, 33)
      result := __pf_checked_add(sload(8), sload(9))
    }
    function f_EvmStorageStructProbe_root_value() -> result {
      sstore(10, 6277101735386680764516354157049543343084444891548699590660)
      result := sload(10)
    }
    function f_EvmStorageStructProbe_whole_struct_write_sum() -> result {
      {
        let __proof_forge_assign_storage_struct_current_x := 30
        let __proof_forge_assign_storage_struct_current_y := 40
        sstore(1, __proof_forge_assign_storage_struct_current_x)
        sstore(2, __proof_forge_assign_storage_struct_current_y)
      }
      let __proof_forge_struct_snapshot_x := sload(1)
      let __proof_forge_struct_snapshot_y := sload(2)
      result := __pf_checked_add(__proof_forge_struct_snapshot_x, __proof_forge_struct_snapshot_y)
    }
    function f_EvmStorageStructProbe_whole_struct_return() -> __proof_forge_return_0, __proof_forge_return_1 {
      {
        let __proof_forge_assign_storage_struct_current_x := 8
        let __proof_forge_assign_storage_struct_current_y := 13
        sstore(1, __proof_forge_assign_storage_struct_current_x)
        sstore(2, __proof_forge_assign_storage_struct_current_y)
      }
      __proof_forge_return_0 := sload(1)
      __proof_forge_return_1 := sload(2)
    }
    function f_EvmStorageStructProbe_self_struct_storage_write() -> result {
      {
        let __proof_forge_assign_storage_struct_current_x := 5
        let __proof_forge_assign_storage_struct_current_y := 7
        sstore(1, __proof_forge_assign_storage_struct_current_x)
        sstore(2, __proof_forge_assign_storage_struct_current_y)
      }
      {
        let __proof_forge_assign_storage_struct_current_x := sload(2)
        let __proof_forge_assign_storage_struct_current_y := sload(1)
        sstore(1, __proof_forge_assign_storage_struct_current_x)
        sstore(2, __proof_forge_assign_storage_struct_current_y)
      }
      result := __pf_checked_add(__pf_checked_mul(sload(1), 100), sload(2))
    }
    function f_EvmStorageStructProbe_read_point_x(index) -> result {
      result := sload(__proof_forge_struct_array_slot(4, 2, 2, 0, index))
    }
    function __proof_forge_struct_array_slot(slot, length, field_count, field_offset, index) -> result {
      if iszero(lt(index, length)) {
        revert(0, 0)
      }
      result := add(add(slot, mul(index, field_count)), field_offset)
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
