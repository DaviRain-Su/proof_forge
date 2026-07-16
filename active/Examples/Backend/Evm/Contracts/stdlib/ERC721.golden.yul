object "ERC721" {
  code {
    switch shr(224, calldataload(0))
    case 0x6352211e {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ERC721_ownerOf(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x23b872dd {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC721_transferFrom(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x42842e0e {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC721_safeTransferFrom(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x40c10f19 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC721_mint(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x42966c68 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC721_burn(calldataload(4))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_ERC721_ownerOf(tokenId) -> __pf_result {
      let tokenOwner := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(iszero(eq(tokenOwner, 0))) {
        revert(0, 0)
      }
      __pf_result := tokenOwner
    }
    function f_ERC721_transferFrom(holder, recipient, tokenId) {
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
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := holder
        let __pf_event_indexed_topic1 := recipient
        let __pf_event_indexed_topic2 := tokenId
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_ERC721_safeTransferFrom(holder, recipient, tokenId) {
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
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := holder
        let __pf_event_indexed_topic1 := recipient
        let __pf_event_indexed_topic2 := tokenId
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
      {
        {
          let __pf_erc721_operator := operator
          let __pf_erc721_from := holder
          let __pf_erc721_to := recipient
          let __pf_erc721_token_id := tokenId
          if iszero(iszero(extcodesize(__pf_erc721_to))) {
            mstore(0, shl(224, 353073666))
            mstore(4, __pf_erc721_operator)
            mstore(36, __pf_erc721_from)
            mstore(68, __pf_erc721_token_id)
            mstore(100, 128)
            mstore(132, 0)
            let __pf_erc721_ok := call(gas(), __pf_erc721_to, 0, 0, 164, 0, 32)
            if iszero(__pf_erc721_ok) {
              revert(0, 0)
            }
            if lt(returndatasize(), 32) {
              revert(0, 0)
            }
            let __pf_erc721_magic := mload(0)
            if iszero(eq(__pf_erc721_magic, shl(224, 353073666))) {
              revert(0, 0)
            }
          }
        }
      }
    }
    function f_ERC721_mint(recipient, tokenId) {
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let existing := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(eq(existing, 0)) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, tokenId, recipient)
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := 0
        let __pf_event_indexed_topic1 := recipient
        let __pf_event_indexed_topic2 := tokenId
        log4(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_ERC721_burn(tokenId) {
      let who := caller()
      let tokenOwner := sload(__proof_forge_map_slot(0, tokenId))
      if iszero(eq(tokenOwner, who)) {
        revert(0, 0)
      }
      __proof_forge_map_write(0, tokenId, 0)
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := who
        let __pf_event_indexed_topic1 := 0
        let __pf_event_indexed_topic2 := tokenId
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
  }
}
