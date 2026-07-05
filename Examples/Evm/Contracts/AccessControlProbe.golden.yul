object "AccessControlProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xec2606c0 {
      if lt(calldatasize(), 68) {
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
      f_AccessControlProbe_grantRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x1d0b19e7 {
      if lt(calldatasize(), 68) {
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
    function f_AccessControlProbe_hasRole(role, who) -> result {
      let member := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, role), who))
      result := iszero(eq(member, 0))
    }
    function f_AccessControlProbe_grantRole(role, who) {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 0), caller())), 0))) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, role), who)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, role), who)
        sstore(_slot, 1)
        sstore(_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_revokeRole(role, who) {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 0), caller())), 0))) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, role), who)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, role), who)
        sstore(_slot, 0)
        sstore(_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_init() {
      let admin := caller()
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, 0), admin)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, 0), admin)
        sstore(_slot, 1)
        sstore(_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_grantMinter(who) {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 0), caller())), 0))) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, 1), who)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, 1), who)
        sstore(_slot, 1)
        sstore(_presence_slot, 1)
      }
    }
    function f_AccessControlProbe_touch() {
      if iszero(iszero(eq(sload(__proof_forge_map_slot(__proof_forge_map_slot(0, 1), caller())), 0))) {
        revert(0, 0)
      }
      sstore(1, or(and(sload(1), not(shl(192, 18446744073709551615))), shl(192, __pf_checked_add(and(shr(192, sload(1)), 18446744073709551615), 1))))
    }
    function f_AccessControlProbe_getTouches() -> result {
      result := and(shr(192, sload(1)), 18446744073709551615)
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
