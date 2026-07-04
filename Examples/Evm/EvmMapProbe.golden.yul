object "EvmMapProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x3bb39394 {
      let _r := f_EvmMapProbe_map_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x541be503 {
      let _r := f_EvmMapProbe_get_seed_balance()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x68eb1eef {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmMapProbe_read_balance(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe1de6ac8 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_EvmMapProbe_upsert_balance(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xb41d1f5c {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_EvmMapProbe_set_balance(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xa0c7a60a {
      let _r := f_EvmMapProbe_contains_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x4c136189 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmMapProbe_contains_balance(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x84c21205 {
      let _r := f_EvmMapProbe_path_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xbce9e77b {
      let _r := f_EvmMapProbe_path_assign_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x13a524e0 {
      let _r := f_EvmMapProbe_nested_path_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xce6fd7c0 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      let _r := f_EvmMapProbe_nested_path_dynamic(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmMapProbe_map_lifecycle() -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 111)))
      sstore(2, or(and(sload(2), not(shl(192, 18446744073709551615))), shl(192, 222)))
      let old0 := __proof_forge_map_set_return(1, 1001, 11)
      if iszero(eq(old0, 0)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_map_slot(1, 1001)), 11)) {
        revert(0, 0)
      }
      let old1 := __proof_forge_map_set_return(1, 1001, 55)
      if iszero(eq(old1, 11)) {
        revert(0, 0)
      }
      result := sload(__proof_forge_map_slot(1, 1001))
    }
    function f_EvmMapProbe_get_seed_balance() -> result {
      result := sload(__proof_forge_map_slot(1, 1001))
    }
    function f_EvmMapProbe_read_balance(key) -> result {
      result := sload(__proof_forge_map_slot(1, key))
    }
    function f_EvmMapProbe_upsert_balance(key, value) -> result {
      result := __proof_forge_map_set_return(1, key, value)
    }
    function f_EvmMapProbe_set_balance(key, value) {
      __proof_forge_map_write(1, key, value)
    }
    function f_EvmMapProbe_contains_lifecycle() -> result {
      if iszero(eq(iszero(iszero(sload(__proof_forge_map_presence_slot(1, 1001)))), 0)) {
        revert(0, 0)
      }
      let old0 := __proof_forge_map_set_return(1, 1001, 0)
      if iszero(eq(old0, 0)) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_map_slot(1, 1001)), 0)) {
        revert(0, 0)
      }
      if iszero(eq(iszero(iszero(sload(__proof_forge_map_presence_slot(1, 1001)))), 1)) {
        revert(0, 0)
      }
      __proof_forge_map_write(1, 1001, 99)
      if iszero(eq(iszero(iszero(sload(__proof_forge_map_presence_slot(1, 1001)))), 1)) {
        revert(0, 0)
      }
      result := sload(__proof_forge_map_slot(1, 1001))
    }
    function f_EvmMapProbe_contains_balance(key) -> result {
      result := iszero(iszero(sload(__proof_forge_map_presence_slot(1, key))))
    }
    function f_EvmMapProbe_path_lifecycle() -> result {
      __proof_forge_map_write(1, 2002, 77)
      result := sload(__proof_forge_map_slot(1, 2002))
    }
    function f_EvmMapProbe_path_assign_lifecycle() -> result {
      __proof_forge_map_write(1, 3003, 11)
      __proof_forge_map_assign_add(1, 3003, 5)
      __proof_forge_map_assign_sub(1, 3003, 1)
      __proof_forge_map_assign_mul(1, 3003, 2)
      __proof_forge_map_assign_div(1, 3003, 3)
      __proof_forge_map_assign_mod(1, 3003, 13)
      __proof_forge_map_assign_or(1, 3003, 16)
      __proof_forge_map_assign_and(1, 3003, 31)
      __proof_forge_map_assign_xor(1, 3003, 7)
      __proof_forge_map_assign_shl(1, 3003, 2)
      __proof_forge_map_assign_shr(1, 3003, 1)
      result := sload(__proof_forge_map_slot(1, 3003))
    }
    function f_EvmMapProbe_nested_path_lifecycle() -> result {
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(1, 4004), 5005)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(1, 4004), 5005)
        sstore(_slot, 88)
        sstore(_presence_slot, 1)
      }
      if iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(1, 4004), 5005)), 88)) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(1, 4004), 5005)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(1, 4004), 5005)
        sstore(_slot, __pf_checked_add(sload(_slot), 7))
        sstore(_presence_slot, 1)
      }
      result := sload(__proof_forge_map_slot(__proof_forge_map_slot(1, 4004), 5005))
    }
    function f_EvmMapProbe_nested_path_dynamic(outer, inner, value) -> result {
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(1, outer), inner)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(1, outer), inner)
        sstore(_slot, value)
        sstore(_presence_slot, 1)
      }
      result := sload(__proof_forge_map_slot(__proof_forge_map_slot(1, outer), inner))
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
      sstore(_slot, __pf_checked_add(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_sub(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, __pf_checked_sub(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_mul(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, __pf_checked_mul(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_div(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, div(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_mod(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, mod(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_or(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, or(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_and(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, and(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_xor(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, xor(sload(_slot), value))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_shl(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, shl(value, sload(_slot)))
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_map_assign_shr(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, shr(value, sload(_slot)))
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
