object "EvmTypedStorageProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x06422075 {
      let _r := f_EvmTypedStorageProbe_bool_scalar_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x9f3c504b {
      let _r := f_EvmTypedStorageProbe_typed_array_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5ab2cb77 {
      let _r := f_EvmTypedStorageProbe_path_assign_u32()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xafbe1175 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmTypedStorageProbe_read_flag(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6a088e19 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 4294967295) {
        revert(0, 0)
      }
      f_EvmTypedStorageProbe_write_limb(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x4994f441 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmTypedStorageProbe_read_root(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmTypedStorageProbe_bool_scalar_lifecycle() -> __pf_result {
      sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(1, 255))))
      if iszero(eq(and(shr(0, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmTypedStorageProbe_typed_array_lifecycle() -> __pf_result {
      sstore(8, or(and(sload(8), not(shl(0, 18446744073709551615))), shl(0, and(999, 18446744073709551615))))
      sstore(__proof_forge_array_slot(1, 3, 0), 7)
      sstore(__proof_forge_array_slot(1, 3, 1), 11)
      sstore(__proof_forge_array_slot(1, 3, 2), 13)
      sstore(__proof_forge_array_slot(4, 2, 0), 1)
      sstore(__proof_forge_array_slot(4, 2, 1), 0)
      sstore(__proof_forge_array_slot(6, 2, 0), 6277101735386680764516354157049543343084444891548699590660)
      sstore(__proof_forge_array_slot(6, 2, 1), 31385508676933403821220641317563962861421152075426748694536)
      if iszero(eq(sload(__proof_forge_array_slot(4, 2, 0)), 1)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_array_slot(4, 2, 1)), 0)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_array_slot(6, 2, 0)), 6277101735386680764516354157049543343084444891548699590660)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_array_slot(6, 2, 1)), 31385508676933403821220641317563962861421152075426748694536)) {
        revert(0, 0)
      }
      let sum := __pf_checked_add(__pf_checked_add(sload(__proof_forge_array_slot(1, 3, 0)), sload(__proof_forge_array_slot(1, 3, 1))), sload(__proof_forge_array_slot(1, 3, 2)))
      __pf_result := __pf_checked_add(sum, sload(__proof_forge_array_slot(4, 2, 0)))
    }
    function f_EvmTypedStorageProbe_path_assign_u32() -> __pf_result {
      sstore(__proof_forge_array_slot(1, 3, 0), 10)
      {
        let __pf_storage_slot := __proof_forge_array_slot(1, 3, 0)
        sstore(__pf_storage_slot, add(sload(__pf_storage_slot), 5))
      }
      {
        let __pf_storage_slot := __proof_forge_array_slot(1, 3, 0)
        sstore(__pf_storage_slot, mul(sload(__pf_storage_slot), 2))
      }
      __pf_result := sload(__proof_forge_array_slot(1, 3, 0))
    }
    function f_EvmTypedStorageProbe_read_flag(index) -> __pf_result {
      __pf_result := sload(__proof_forge_array_slot(4, 2, index))
    }
    function f_EvmTypedStorageProbe_write_limb(index, value) {
      sstore(__proof_forge_array_slot(1, 3, index), value)
    }
    function f_EvmTypedStorageProbe_read_root(index) -> __pf_result {
      __pf_result := sload(__proof_forge_array_slot(6, 2, index))
    }
    function __proof_forge_array_slot(slot, length, index) -> result {
      if iszero(lt(index, length)) {
        revert(0, 0)
      }
      result := add(slot, index)
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
