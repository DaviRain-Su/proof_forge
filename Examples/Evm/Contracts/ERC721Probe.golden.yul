object "ERC721Probe" {
  code {
    switch shr(224, calldataload(0))
    case 0x6352211e {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_ERC721Probe_ownerOf(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x23b872dd {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      f_ERC721Probe_transferFrom(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x42842e0e {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      f_ERC721Probe_safeTransferFrom(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x40c10f19 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_ERC721Probe_mint(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x42966c68 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      f_ERC721Probe_burn(calldataload(4))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_ERC721Probe_ownerOf(tokenId) -> result {
      let tokenOwner := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(iszero(eq(tokenOwner, 0))) {
        revert(0, 0)
      }
      result := tokenOwner
    }
    function f_ERC721Probe_transferFrom(holder, recipient, tokenId) {
      let operator := caller()
      let tokenOwner := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(iszero(eq(tokenOwner, 0))) {
        revert(0, 0)
      }
      if iszero(eq(tokenOwner, holder)) {
        revert(0, 0)
      }
      if iszero(eq(operator, holder)) {
        revert(0, 0)
      }
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, tokenId, recipient)
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288672809)
        let _topic0 := keccak256(0, 32)
        let _indexed_topic0 := holder
        let _indexed_topic1 := recipient
        let _indexed_topic2 := tokenId
        log4(0, 0, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
      }
    }
    function f_ERC721Probe_safeTransferFrom(holder, recipient, tokenId) {
      let operator := caller()
      let tokenOwner := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(iszero(eq(tokenOwner, 0))) {
        revert(0, 0)
      }
      if iszero(eq(tokenOwner, holder)) {
        revert(0, 0)
      }
      if iszero(eq(operator, holder)) {
        revert(0, 0)
      }
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, tokenId, recipient)
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288672809)
        let _topic0 := keccak256(0, 32)
        let _indexed_topic0 := holder
        let _indexed_topic1 := recipient
        let _indexed_topic2 := tokenId
        log4(0, 0, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
      }
    }
    function f_ERC721Probe_mint(recipient, tokenId) {
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let existing := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(eq(existing, 0)) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, tokenId, recipient)
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288672809)
        let _topic0 := keccak256(0, 32)
        let _indexed_topic0 := 0
        let _indexed_topic1 := recipient
        let _indexed_topic2 := tokenId
        log4(0, 0, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
      }
    }
    function f_ERC721Probe_burn(tokenId) {
      let who := caller()
      let tokenOwner := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(eq(tokenOwner, who)) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, tokenId, 0)
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288672809)
        let _topic0 := keccak256(0, 32)
        let _indexed_topic0 := who
        let _indexed_topic1 := 0
        let _indexed_topic2 := tokenId
        log4(0, 0, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
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
    function __proof_forge_map_set_return(slot, key, value) -> old {
      let _slot := __proof_forge_map_slot(slot, key)
      old := sload(_slot)
      sstore(_slot, value)
      sstore(__proof_forge_map_presence_slot(slot, key), 1)
    }
  }
}
