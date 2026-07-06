object "ERC1155" {
  code {
    switch shr(224, calldataload(0))
    case 0x00fdd58e {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_ERC1155_balanceOf(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe985e9c5 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      let _r := f_ERC1155_isApprovedForAll(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa22cb465 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1) {
        revert(0, 0)
      }
      f_ERC1155_setApprovalForAll(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x0febdd49 {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      f_ERC1155_safeTransferFrom(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0x156e29f6 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      f_ERC1155_mint(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xb390c0ab {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_ERC1155_burn(calldataload(4), calldataload(36))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_ERC1155_balanceOf(holder, id) -> result {
      if iszero(iszero(eq(holder, 0))) {
        revert(0, 0)
      }
      result := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, holder), id))
    }
    function f_ERC1155_isApprovedForAll(holder, operator) -> result {
      let approved := sload(__proof_forge_map_slot(__proof_forge_map_slot(1, holder), operator))
      result := iszero(eq(approved, 0))
    }
    function f_ERC1155_setApprovalForAll(operator, approved) {
      let holder := caller()
      if iszero(iszero(eq(holder, operator))) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(1, holder), operator)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(1, holder), operator)
        sstore(_slot, approved)
        sstore(_presence_slot, 1)
      }
      {
        mstore(0, 29598998109930618199791702304337314577662353053623321855103937010099468529519)
        mstore(32, 48922228376648683701831924498070670784747201620589013331429154107591348977664)
        let _topic0 := keccak256(0, 34)
        let _indexed_topic0 := holder
        let _indexed_topic1 := operator
        mstore(0, approved)
        log3(0, 32, _topic0, _indexed_topic0, _indexed_topic1)
      }
    }
    function f_ERC1155_safeTransferFrom(src, dst, id, amount) {
      let operator := caller()
      let approved := sload(__proof_forge_map_slot(__proof_forge_map_slot(1, src), operator))
      if iszero(or(eq(operator, src), iszero(eq(approved, 0)))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(dst, 0))) {
        revert(0, 0)
      }
      let fromBal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, src), id))
      if iszero(iszero(lt(fromBal, amount))) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, src), id)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, src), id)
        sstore(_slot, __pf_checked_sub(fromBal, amount))
        sstore(_presence_slot, 1)
      }
      let toBal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, dst), id))
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, dst), id)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, dst), id)
        sstore(_slot, __pf_checked_add(toBal, amount))
        sstore(_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110217816123204105828618894700137794298538350)
        mstore(32, 52564060266569530381556813907571567292663703373687215552951033558997877653504)
        let _topic0 := keccak256(0, 50)
        let _indexed_topic0 := operator
        let _indexed_topic1 := src
        let _indexed_topic2 := dst
        mstore(0, id)
        mstore(32, amount)
        log4(0, 64, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
      }
    }
    function f_ERC1155_mint(recipient, id, amount) {
      let operator := caller()
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let toBal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, recipient), id))
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, recipient), id)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, recipient), id)
        sstore(_slot, __pf_checked_add(toBal, amount))
        sstore(_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110217816123204105828618894700137794298538350)
        mstore(32, 52564060266569530381556813907571567292663703373687215552951033558997877653504)
        let _topic0 := keccak256(0, 50)
        let _indexed_topic0 := operator
        let _indexed_topic1 := 0
        let _indexed_topic2 := recipient
        mstore(0, id)
        mstore(32, amount)
        log4(0, 64, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
      }
    }
    function f_ERC1155_burn(id, amount) {
      let operator := caller()
      let bal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, operator), id))
      if iszero(iszero(lt(bal, amount))) {
        revert(0, 0)
      }
      {
        let _slot := __proof_forge_map_slot(__proof_forge_map_slot(0, operator), id)
        let _presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, operator), id)
        sstore(_slot, __pf_checked_sub(bal, amount))
        sstore(_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110217816123204105828618894700137794298538350)
        mstore(32, 52564060266569530381556813907571567292663703373687215552951033558997877653504)
        let _topic0 := keccak256(0, 50)
        let _indexed_topic0 := operator
        let _indexed_topic1 := operator
        let _indexed_topic2 := 0
        mstore(0, id)
        mstore(32, amount)
        log4(0, 64, _topic0, _indexed_topic0, _indexed_topic1, _indexed_topic2)
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
