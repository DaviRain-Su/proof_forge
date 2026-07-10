object "AccessControlProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xec2606c0 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_AccessControlProbe_hasRole(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1fe5f589 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_AccessControlProbe_grantRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x1d0b19e7 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_AccessControlProbe_revokeRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xe1c7392a {
      f_AccessControlProbe_init()
      return(0, 0)
    }
    case 0x261707fa {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_AccessControlProbe_grantMinter(calldataload(4))
      return(0, 0)
    }
    case 0xa55526db {
      f_AccessControlProbe_touch()
      return(0, 0)
    }
    case 0xecc69a6d {
      let _r := f_AccessControlProbe_getTouches()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_AccessControlProbe_hasRole(role, who) -> __pf_result {
      let member := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, role), who))
      __pf_result := iszero(eq(member, 0))
    }
    function f_AccessControlProbe_grantRole(role, who) {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 0), caller())), 0))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, role), who)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, role), who)
        sstore(__pf_storage_slot, 1)
        sstore(__pf_storage_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_revokeRole(role, who) {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 0), caller())), 0))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, role), who)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, role), who)
        sstore(__pf_storage_slot, 0)
        sstore(__pf_storage_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_init() {
      let admin := caller()
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, 0), admin)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, 0), admin)
        sstore(__pf_storage_slot, 1)
        sstore(__pf_storage_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_grantMinter(who) {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 0), caller())), 0))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, 1), who)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, 1), who)
        sstore(__pf_storage_slot, 1)
        sstore(__pf_storage_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_touch() {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 1), caller())), 0))) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(and(shr(0, sload(1)), 18446744073709551615), 18446744073709551615), __pf_checked_width(1, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
    }
    function f_AccessControlProbe_getTouches() -> __pf_result {
      __pf_result := and(shr(0, sload(1)), 18446744073709551615)
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
    function __pf_checked_width(value, maxValue) -> result {
      if gt(value, maxValue) {
        revert(0, 0)
      }
      result := value
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
