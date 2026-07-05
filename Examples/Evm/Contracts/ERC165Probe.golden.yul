object "ERC165Probe" {
  code {
    switch shr(224, calldataload(0))
    case 0x01ffc9a7 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_ERC165Probe_supportsInterface(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x214cdb80 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      f_ERC165Probe_registerInterface(calldataload(4))
      return(0, 0)
    }
    case 0xe1c7392a {
      f_ERC165Probe_init()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_ERC165Probe_supportsInterface(interfaceId) -> result {
      let registered := sload(__proof_forge_map_slot(0, interfaceId))
      result := or(eq(interfaceId, shl(224, 33540519)), iszero(eq(registered, 0)))
    }
    function f_ERC165Probe_registerInterface(interfaceId) {
      __proof_forge_map_write(0, interfaceId, 1)
    }
    function f_ERC165Probe_init() {
      __proof_forge_map_write(0, shl(224, 305419896), 1)
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
  }
}
