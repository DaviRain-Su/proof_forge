object "EvmStorageArrayProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xe4684b67 {
      let _r := f_EvmStorageArrayProbe_storage_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xac35feee {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmStorageArrayProbe_read_value(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5a6fd3b0 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_EvmStorageArrayProbe_write_value(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x08b37751 {
      let _r0, _r1, _r2 := f_EvmStorageArrayProbe_return_values()
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      return(0, 96)
    }
    case 0x84c21205 {
      let _r := f_EvmStorageArrayProbe_path_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xbce9e77b {
      let _r := f_EvmStorageArrayProbe_path_assign_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmStorageArrayProbe_storage_lifecycle() -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 111)))
      sstore(4, or(and(sload(4), not(shl(192, 18446744073709551615))), shl(192, 222)))
      sstore(__proof_forge_array_slot(1, 3, 0), 7)
      sstore(__proof_forge_array_slot(1, 3, 1), 11)
      sstore(__proof_forge_array_slot(1, 3, 2), 13)
      result := __pf_checked_add(__pf_checked_add(sload(__proof_forge_array_slot(1, 3, 0)), sload(__proof_forge_array_slot(1, 3, 1))), sload(__proof_forge_array_slot(1, 3, 2)))
    }
    function f_EvmStorageArrayProbe_read_value(index) -> result {
      result := sload(__proof_forge_array_slot(1, 3, index))
    }
    function f_EvmStorageArrayProbe_write_value(index, value) {
      sstore(__proof_forge_array_slot(1, 3, index), value)
    }
    function f_EvmStorageArrayProbe_return_values() -> __proof_forge_return_0, __proof_forge_return_1, __proof_forge_return_2 {
      sstore(__proof_forge_array_slot(1, 3, 0), 17)
      sstore(__proof_forge_array_slot(1, 3, 1), 19)
      sstore(__proof_forge_array_slot(1, 3, 2), 23)
      __proof_forge_return_0 := sload(__proof_forge_array_slot(1, 3, 0))
      __proof_forge_return_1 := sload(__proof_forge_array_slot(1, 3, 1))
      __proof_forge_return_2 := sload(__proof_forge_array_slot(1, 3, 2))
    }
    function f_EvmStorageArrayProbe_path_lifecycle() -> result {
      sstore(__proof_forge_array_slot(1, 3, 0), 21)
      sstore(__proof_forge_array_slot(1, 3, 1), 22)
      result := __pf_checked_add(sload(__proof_forge_array_slot(1, 3, 0)), sload(__proof_forge_array_slot(1, 3, 1)))
    }
    function f_EvmStorageArrayProbe_path_assign_lifecycle() -> result {
      sstore(__proof_forge_array_slot(1, 3, 2), 10)
      {
        let _slot := __proof_forge_array_slot(1, 3, 2)
        sstore(_slot, __pf_checked_add(sload(_slot), 5))
      }
      result := sload(__proof_forge_array_slot(1, 3, 2))
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
