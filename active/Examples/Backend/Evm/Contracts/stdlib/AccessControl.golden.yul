object "AccessControl" {
  code {
    switch shr(224, calldataload(0))
    case 0x91d14854 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_AccessControl_hasRole(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x248a9ca3 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_AccessControl_getRoleAdmin(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x2f2ff15d {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_AccessControl_grantRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xd547741f {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_AccessControl_revokeRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x36568abe {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_AccessControl_renounceRole(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x1e4e0091 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_AccessControl_setRoleAdmin(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xe1c7392a {
      f_AccessControl_init()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_AccessControl_hasRole(role, who) -> __pf_result {
      __pf_result := iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(role, or(shl(192, who), or(shl(128, 0), or(shl(64, 0), 0)))))), 0))
    }
    function f_AccessControl_getRoleAdmin(role) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(1, role))
    }
    function f_AccessControl_grantRole(role, who) {
      let adminRole := sload(__proof_forge_map_slot(1, role))
      if iszero(iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(adminRole, or(shl(192, caller()), or(shl(128, 0), or(shl(64, 0), 0)))))), 0))) {
        revert(0, 0)
      }
      if iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(role, or(shl(192, who), or(shl(128, 0), or(shl(64, 0), 0)))))), 0)) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, __proof_forge_hash_pair(role, or(shl(192, who), or(shl(128, 0), or(shl(64, 0), 0)))), 1)
      {
        mstore(0, 37286521727102537424976711090937643760881108819285130226953705104192219407474)
        mstore(32, 45887579925547113691619605970066117200287473782411420879993550069304385339392)
        let __pf_event_topic0 := keccak256(0, 36)
        let __pf_event_indexed_topic0 := role
        let __pf_event_indexed_topic1 := who
        let __pf_event_indexed_topic2 := caller()
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_AccessControl_revokeRole(role, who) {
      let adminRole := sload(__proof_forge_map_slot(1, role))
      if iszero(iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(adminRole, or(shl(192, caller()), or(shl(128, 0), or(shl(64, 0), 0)))))), 0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(role, or(shl(192, who), or(shl(128, 0), or(shl(64, 0), 0)))))), 0))) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, __proof_forge_hash_pair(role, or(shl(192, who), or(shl(128, 0), or(shl(64, 0), 0)))), 0)
      {
        mstore(0, 37286521728255658495274898041275517564994298801364457244720562642952894309490)
        mstore(32, 45887579925547113691619605970066117200287473782411420879993550069304385339392)
        let __pf_event_topic0 := keccak256(0, 36)
        let __pf_event_indexed_topic0 := role
        let __pf_event_indexed_topic1 := who
        let __pf_event_indexed_topic2 := caller()
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_AccessControl_renounceRole(role, callerConfirmation) {
      if iszero(eq(callerConfirmation, caller())) {
        revert(0, 0)
      }
      if iszero(iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(role, or(shl(192, caller()), or(shl(128, 0), or(shl(64, 0), 0)))))), 0))) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, __proof_forge_hash_pair(role, or(shl(192, caller()), or(shl(128, 0), or(shl(64, 0), 0)))), 0)
      {
        mstore(0, 37286521728255658495274898041275517564994298801364457244720562642952894309490)
        mstore(32, 45887579925547113691619605970066117200287473782411420879993550069304385339392)
        let __pf_event_topic0 := keccak256(0, 36)
        let __pf_event_indexed_topic0 := role
        let __pf_event_indexed_topic1 := caller()
        let __pf_event_indexed_topic2 := caller()
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_AccessControl_setRoleAdmin(role, newAdminRole) {
      let previousAdminRole := sload(__proof_forge_map_slot(1, role))
      if iszero(iszero(eq(sload(__proof_forge_map_slot(0, __proof_forge_hash_pair(previousAdminRole, or(shl(192, caller()), or(shl(128, 0), or(shl(64, 0), 0)))))), 0))) {
        revert(0, 0)
      }
      __proof_forge_map_write(1, role, newAdminRole)
      {
        mstore(0, 37286521726464923660735391635556405666198232816436258111459303568805417136946)
        mstore(32, 20075754599357709783665843573121915874177270463108478787174045800082064801792)
        let __pf_event_topic0 := keccak256(0, 41)
        let __pf_event_indexed_topic0 := role
        let __pf_event_indexed_topic1 := previousAdminRole
        let __pf_event_indexed_topic2 := newAdminRole
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_AccessControl_init() {
      if iszero(eq(and(shr(0, sload(2)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(0, 18446744073709551615))), shl(0, and(1, 18446744073709551615))))
      let admin := caller()
      __proof_forge_map_write(0, __proof_forge_hash_pair(0, or(shl(192, admin), or(shl(128, 0), or(shl(64, 0), 0)))), 1)
      {
        mstore(0, 37286521727102537424976711090937643760881108819285130226953705104192219407474)
        mstore(32, 45887579925547113691619605970066117200287473782411420879993550069304385339392)
        let __pf_event_topic0 := keccak256(0, 36)
        let __pf_event_indexed_topic0 := 0
        let __pf_event_indexed_topic1 := caller()
        let __pf_event_indexed_topic2 := caller()
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
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
    function __proof_forge_map_write(slot, key, value) {
      let _slot := __proof_forge_map_slot(slot, key)
      sstore(_slot, value)
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
    function __proof_forge_hash_pair(left, right) -> result {
      mstore(0, left)
      mstore(32, right)
      result := keccak256(0, 64)
    }
  }
}
