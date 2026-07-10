object "ERC1155" {
  code {
    switch shr(224, calldataload(0))
    case 0x00fdd58e {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
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
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
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
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
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
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC1155_safeTransferFrom(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0xdacd30d8 {
      if lt(calldatasize(), 196) {
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
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC1155_safeBatchTransferFrom2(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      return(0, 0)
    }
    case 0x156e29f6 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC1155_mint(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xb390c0ab {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_ERC1155_burn(calldataload(4), calldataload(36))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_ERC1155_balanceOf(holder, id) -> __pf_result {
      if iszero(iszero(eq(holder, 0))) {
        revert(0, 0)
      }
      __pf_result := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, holder), id))
    }
    function f_ERC1155_isApprovedForAll(holder, operator) -> __pf_result {
      let approved := sload(__proof_forge_map_slot(__proof_forge_map_slot(1, holder), operator))
      __pf_result := iszero(eq(approved, 0))
    }
    function f_ERC1155_setApprovalForAll(operator, approved) {
      let holder := caller()
      if iszero(iszero(eq(holder, operator))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(1, holder), operator)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(1, holder), operator)
        sstore(__pf_storage_slot, approved)
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 29598998109930618199791702304337314570850007615435530133533608702771098496098)
        mstore(32, 50403592710896236504088002338673980987564355465062697744246489382138754891776)
        let __pf_event_topic0 := keccak256(0, 36)
        let __pf_event_indexed_topic0 := holder
        let __pf_event_indexed_topic1 := operator
        mstore(0, approved)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
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
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, src), id)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, src), id)
        sstore(__pf_storage_slot, __pf_checked_sub(fromBal, amount))
        sstore(__pf_storage_presence_slot, 1)
      }
      let toBal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, dst), id))
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, dst), id)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, dst), id)
        sstore(__pf_storage_slot, __pf_checked_add(toBal, amount))
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110211003777765918036897324371830465927261281)
        mstore(32, 45408759099000918016964216062045765926360248736437601954278641986188968198144)
        let __pf_event_topic0 := keccak256(0, 55)
        let __pf_event_indexed_topic0 := operator
        let __pf_event_indexed_topic1 := src
        let __pf_event_indexed_topic2 := dst
        mstore(0, id)
        mstore(32, amount)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
      {
        {
          let __pf_erc1155_operator := operator
          let __pf_erc1155_from := src
          let __pf_erc1155_to := dst
          let __pf_erc1155_id := id
          let __pf_erc1155_amount := amount
          if iszero(iszero(extcodesize(__pf_erc1155_to))) {
            mstore(0, shl(224, 4063915617))
            mstore(4, __pf_erc1155_operator)
            mstore(36, __pf_erc1155_from)
            mstore(68, __pf_erc1155_id)
            mstore(100, __pf_erc1155_amount)
            mstore(132, 160)
            mstore(164, 0)
            let __pf_erc1155_ok := call(gas(), __pf_erc1155_to, 0, 0, 196, 0, 32)
            if iszero(__pf_erc1155_ok) {
              revert(0, 0)
            }
            if lt(returndatasize(), 32) {
              revert(0, 0)
            }
            let __pf_erc1155_magic := mload(0)
            if iszero(eq(__pf_erc1155_magic, shl(224, 4063915617))) {
              revert(0, 0)
            }
          }
        }
      }
    }
    function f_ERC1155_safeBatchTransferFrom2(src, dst, id0, amount0, id1, amount1) {
      let operator := caller()
      let approved := sload(__proof_forge_map_slot(__proof_forge_map_slot(1, src), operator))
      if iszero(or(eq(operator, src), iszero(eq(approved, 0)))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(dst, 0))) {
        revert(0, 0)
      }
      let fromBal0 := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, src), id0))
      if iszero(iszero(lt(fromBal0, amount0))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, src), id0)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, src), id0)
        sstore(__pf_storage_slot, __pf_checked_sub(fromBal0, amount0))
        sstore(__pf_storage_presence_slot, 1)
      }
      let toBal0 := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, dst), id0))
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, dst), id0)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, dst), id0)
        sstore(__pf_storage_slot, __pf_checked_add(toBal0, amount0))
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110211003777765918036897324371830465927261281)
        mstore(32, 45408759099000918016964216062045765926360248736437601954278641986188968198144)
        let __pf_event_topic0 := keccak256(0, 55)
        let __pf_event_indexed_topic0 := operator
        let __pf_event_indexed_topic1 := src
        let __pf_event_indexed_topic2 := dst
        mstore(0, id0)
        mstore(32, amount0)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
      let fromBal1 := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, src), id1))
      if iszero(iszero(lt(fromBal1, amount1))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, src), id1)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, src), id1)
        sstore(__pf_storage_slot, __pf_checked_sub(fromBal1, amount1))
        sstore(__pf_storage_presence_slot, 1)
      }
      let toBal1 := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, dst), id1))
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, dst), id1)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, dst), id1)
        sstore(__pf_storage_slot, __pf_checked_add(toBal1, amount1))
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110211003777765918036897324371830465927261281)
        mstore(32, 45408759099000918016964216062045765926360248736437601954278641986188968198144)
        let __pf_event_topic0 := keccak256(0, 55)
        let __pf_event_indexed_topic0 := operator
        let __pf_event_indexed_topic1 := src
        let __pf_event_indexed_topic2 := dst
        mstore(0, id1)
        mstore(32, amount1)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
      {
        let __pf_erc1155_batch_operator := operator
        let __pf_erc1155_batch_from := src
        let __pf_erc1155_batch_to := dst
        let __pf_erc1155_batch_id0 := id0
        let __pf_erc1155_batch_amount0 := amount0
        let __pf_erc1155_batch_id1 := id1
        let __pf_erc1155_batch_amount1 := amount1
        if iszero(iszero(extcodesize(__pf_erc1155_batch_to))) {
          mstore(0, shl(224, 3155786881))
          mstore(4, __pf_erc1155_batch_operator)
          mstore(36, __pf_erc1155_batch_from)
          mstore(68, 160)
          mstore(100, 256)
          mstore(132, 352)
          mstore(164, 2)
          mstore(196, __pf_erc1155_batch_id0)
          mstore(228, __pf_erc1155_batch_id1)
          mstore(260, 2)
          mstore(292, __pf_erc1155_batch_amount0)
          mstore(324, __pf_erc1155_batch_amount1)
          mstore(356, 0)
          let __pf_erc1155_batch_ok := call(gas(), __pf_erc1155_batch_to, 0, 0, 388, 0, 32)
          if iszero(__pf_erc1155_batch_ok) {
            revert(0, 0)
          }
          if lt(returndatasize(), 32) {
            revert(0, 0)
          }
          let __pf_erc1155_batch_magic := mload(0)
          if iszero(eq(__pf_erc1155_batch_magic, shl(224, 3155786881))) {
            revert(0, 0)
          }
        }
      }
    }
    function f_ERC1155_mint(recipient, id, amount) {
      let operator := caller()
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let toBal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, recipient), id))
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, recipient), id)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, recipient), id)
        sstore(__pf_storage_slot, __pf_checked_add(toBal, amount))
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110211003777765918036897324371830465927261281)
        mstore(32, 45408759099000918016964216062045765926360248736437601954278641986188968198144)
        let __pf_event_topic0 := keccak256(0, 55)
        let __pf_event_indexed_topic0 := operator
        let __pf_event_indexed_topic1 := 0
        let __pf_event_indexed_topic2 := recipient
        mstore(0, id)
        mstore(32, amount)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_ERC1155_burn(id, amount) {
      let operator := caller()
      let bal := sload(__proof_forge_map_slot(__proof_forge_map_slot(0, operator), id))
      if iszero(iszero(lt(bal, amount))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(0, operator), id)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(0, operator), id)
        sstore(__pf_storage_slot, __pf_checked_sub(bal, amount))
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 38196372293521921434662571559482110211003777765918036897324371830465927261281)
        mstore(32, 45408759099000918016964216062045765926360248736437601954278641986188968198144)
        let __pf_event_topic0 := keccak256(0, 55)
        let __pf_event_indexed_topic0 := operator
        let __pf_event_indexed_topic1 := operator
        let __pf_event_indexed_topic2 := 0
        mstore(0, id)
        mstore(32, amount)
        log4(0, 64, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
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
