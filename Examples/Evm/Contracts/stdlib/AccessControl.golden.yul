object "AccessControl" {
  code {
    switch shr(224, calldataload(0))
    case 0xec2606c0 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_AccessControl_hasRole(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1fe5f589 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_AccessControl_grantRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x1d0b19e7 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_AccessControl_revokeRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xe1c7392a {
      f_AccessControl_init()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_AccessControl_hasRole(role, who) -> result {
      let member := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, role), who))
      result := iszero(eq(member, 0))
    }
    function f_AccessControl_grantRole(role, who) {
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
    function f_AccessControl_revokeRole(role, who) {
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
    function f_AccessControl_init() {
      let admin := caller()
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, 0), admin)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, 0), admin)
        sstore(_slot, 1)
        sstore(_presence_slot, 1)
      }
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
  }
}
