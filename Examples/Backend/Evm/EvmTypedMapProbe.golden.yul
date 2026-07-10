object "EvmTypedMapProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xe4e7feaf {
      let _r := f_EvmTypedMapProbe_typed_map_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x04395342 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_read_score(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x9dfe7834 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(36), 4294967295) {
        revert(0, 0)
      }
      f_EvmTypedMapProbe_write_score(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x79b9741a {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_contains_score(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x7c7d06af {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_read_flag(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x481794a0 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_set_flag(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x430d2c8d {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_contains_flag(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xca27ec99 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_read_root(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x86370059 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_set_root(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1f24b6db {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmTypedMapProbe_contains_root(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa82c9bea {
      let _r := f_EvmTypedMapProbe_path_assign_score()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xcb239774 {
      if lt(calldatasize(), 100) {
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
      let _r := f_EvmTypedMapProbe_nested_path_score(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmTypedMapProbe_typed_map_lifecycle() -> __pf_result {
      sstore(3, or(and(sload(3), not(shl(0, 18446744073709551615))), shl(0, and(777, 18446744073709551615))))
      let old0 := __proof_forge_map_set_return(0, 7, 11)
      if iszero(eq(old0, 0)) {
        revert(0, 0)
      }
      let old1 := __proof_forge_map_set_return(0, 7, 13)
      if iszero(eq(old1, 11)) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, 8, 17)
      let flagOld := __proof_forge_map_set_return(1, 1, 1)
      if iszero(eq(flagOld, 0)) {
        revert(0, 0)
      }
      __proof_forge_map_write(1, 0, 0)
      let rootOld := __proof_forge_map_set_return(2, 6277101735386680764516354157049543343084444891548699590660, 31385508676933403821220641317563962861421152075426748694536)
      if iszero(eq(rootOld, 0)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_map_slot(1, 1)), 1)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_map_slot(1, 0)), 0)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_map_slot(2, 6277101735386680764516354157049543343084444891548699590660)), 31385508676933403821220641317563962861421152075426748694536)) {
        revert(0, 0)
      }
      let sum := __pf_checked_add(sload(__proof_forge_map_slot(0, 7)), sload(__proof_forge_map_slot(0, 8)))
      __pf_result := __pf_checked_add(sum, sload(__proof_forge_map_slot(1, 1)))
    }
    function f_EvmTypedMapProbe_read_score(key) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(0, key))
    }
    function f_EvmTypedMapProbe_write_score(key, value) {
      __proof_forge_map_write(0, key, value)
    }
    function f_EvmTypedMapProbe_contains_score(key) -> __pf_result {
      __pf_result := iszero(iszero(sload(__proof_forge_map_presence_slot(0, key))))
    }
    function f_EvmTypedMapProbe_read_flag(key) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(1, key))
    }
    function f_EvmTypedMapProbe_set_flag(key, value) -> __pf_result {
      __pf_result := __proof_forge_map_set_return(1, key, value)
    }
    function f_EvmTypedMapProbe_contains_flag(key) -> __pf_result {
      __pf_result := iszero(iszero(sload(__proof_forge_map_presence_slot(1, key))))
    }
    function f_EvmTypedMapProbe_read_root(key) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(2, key))
    }
    function f_EvmTypedMapProbe_set_root(key, value) -> __pf_result {
      __pf_result := __proof_forge_map_set_return(2, key, value)
    }
    function f_EvmTypedMapProbe_contains_root(key) -> __pf_result {
      __pf_result := iszero(iszero(sload(__proof_forge_map_presence_slot(2, key))))
    }
    function f_EvmTypedMapProbe_path_assign_score() -> __pf_result {
      __proof_forge_map_write(0, 9, 10)
      __proof_forge_map_assign_add(0, 9, 5)
      __proof_forge_map_assign_mul(0, 9, 2)
      __pf_result := sload(__proof_forge_map_slot(0, 9))
    }
    function f_EvmTypedMapProbe_nested_path_score(outer, inner, value) -> __pf_result {
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, outer), inner)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, outer), inner)
        sstore(__pf_storage_slot, value)
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, outer), inner)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, outer), inner)
        sstore(__pf_storage_slot, add(sload(__pf_storage_slot), 5))
        sstore(__pf_storage_presence_slot, 1)
      }
      __pf_result := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, outer), inner))
    }
    function __proof_forge_map_slot(slot, key) -> result {
      mstore(0, key)
      mstore(32, slot)
      result := keccak256(0, 64)
    }
    function __proof_forge_map_presence_slot(slot, key) -> result {
      mstore(0, slot)
      mstore(32, 1969478005224772198022937154314036040895674356107534287685)
      let _presence_slot := keccak256(0, 64)
      mstore(0, key)
      mstore(32, _presence_slot)
      result := keccak256(0, 64)
    }
    function __proof_forge_map_write(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, value)
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_set_return(slot, key, value) -> old {
      let _slot := __proof_forge_map_slot(slot, key)
      old := sload(_slot)
      sstore(_slot, value)
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_add(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, add(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_mul(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, mul(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
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
