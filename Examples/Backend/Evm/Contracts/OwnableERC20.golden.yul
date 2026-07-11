object "OwnableERC20" {
  code {
    switch shr(224, calldataload(0))
    case 0x8da5cb5b {
      let _r := f_OwnableERC20_owner()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf2fde38b {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_OwnableERC20_transferOwnership(calldataload(4))
      return(0, 0)
    }
    case 0x715018a6 {
      f_OwnableERC20_renounceOwnership()
      return(0, 0)
    }
    case 0x18160ddd {
      let _r := f_OwnableERC20_totalSupply()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x313ce567 {
      let _r := f_OwnableERC20_decimals()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x70a08231 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_OwnableERC20_balanceOf(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xdd62ed3e {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      let _r := f_OwnableERC20_allowance(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa9059cbb {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_OwnableERC20_transfer(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x095ea7b3 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_OwnableERC20_approve(calldataload(4), calldataload(36))
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
      let _r := f_OwnableERC20_transferFrom(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
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
      let _r := f_OwnableERC20_mint(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x42966c68 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_OwnableERC20_burn(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xb7b0422d {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_OwnableERC20_init(calldataload(4))
      return(0, 0)
    }
    case 0x484b973c {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_OwnableERC20_ownerMint(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_OwnableERC20_owner() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_OwnableERC20_transferOwnership(newOwner) {
      if iszero(eq(caller(), and(shr(0, sload(0)), 18446744073709551615))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(newOwner, 0))) {
        revert(0, 0)
      }
      {
        mstore(0, 35943731765892510050589367655672536643328569156915554301577312365719383532644)
        mstore(32, 51742913097576536687416843347501904736222912990880608286633430183482035798016)
        let __pf_event_topic0 := keccak256(0, 37)
        let __pf_event_indexed_topic0 := and(shr(0, sload(0)), 18446744073709551615)
        let __pf_event_indexed_topic1 := newOwner
        log3(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(newOwner, 18446744073709551615))))
    }
    function f_OwnableERC20_renounceOwnership() {
      if iszero(eq(caller(), and(shr(0, sload(0)), 18446744073709551615))) {
        revert(0, 0)
      }
      {
        mstore(0, 35943731765892510050589367655672536643328569156915554301577312365719383532644)
        mstore(32, 51742913097576536687416843347501904736222912990880608286633430183482035798016)
        let __pf_event_topic0 := keccak256(0, 37)
        let __pf_event_indexed_topic0 := and(shr(0, sload(0)), 18446744073709551615)
        let __pf_event_indexed_topic1 := 0
        log3(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
    }
    function f_OwnableERC20_totalSupply() -> __pf_result {
      __pf_result := and(shr(128, sload(0)), 18446744073709551615)
    }
    function f_OwnableERC20_decimals() -> __pf_result {
      __pf_result := and(shr(192, sload(0)), 18446744073709551615)
    }
    function f_OwnableERC20_balanceOf(who) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(1, who))
    }
    function f_OwnableERC20_allowance(holder, spender) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(__proof_forge_map_slot(2, holder), spender))
    }
    function f_OwnableERC20_transfer(recipient, amount) -> __pf_result {
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let sender := caller()
      let srcBal := sload(__proof_forge_map_slot(1, sender))
      if iszero(iszero(lt(srcBal, amount))) {
        revert(0, 0)
      }
      __proof_forge_map_write(1, sender, __pf_checked_sub(srcBal, amount))
      let dstBal := sload(__proof_forge_map_slot(1, recipient))
      __proof_forge_map_write(1, recipient, __pf_checked_add(dstBal, amount))
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := sender
        let __pf_event_indexed_topic1 := recipient
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_OwnableERC20_approve(spender, amount) -> __pf_result {
      let holder := caller()
      if iszero(iszero(eq(spender, 0))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(2, holder), spender)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(2, holder), spender)
        sstore(__pf_storage_slot, amount)
        sstore(__pf_storage_presence_slot, 1)
      }
      {
        mstore(0, 29598998109930618199054758324288223757593108964568133265786181954376800810294)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := holder
        let __pf_event_indexed_topic1 := spender
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_OwnableERC20_transferFrom(src, dst, amount) -> __pf_result {
      let spender := caller()
      let current := sload(__proof_forge_map_slot(__proof_forge_map_slot(2, src), spender))
      if iszero(iszero(lt(current, amount))) {
        revert(0, 0)
      }
      {
        let __pf_storage_slot := __proof_forge_map_slot(__proof_forge_map_slot(2, src), spender)
        let __pf_storage_presence_slot := __proof_forge_map_presence_slot(__proof_forge_map_slot(2, src), spender)
        sstore(__pf_storage_slot, __pf_checked_sub(current, amount))
        sstore(__pf_storage_presence_slot, 1)
      }
      let srcBal := sload(__proof_forge_map_slot(1, src))
      if iszero(iszero(lt(srcBal, amount))) {
        revert(0, 0)
      }
      __proof_forge_map_write(1, src, __pf_checked_sub(srcBal, amount))
      let dstBal := sload(__proof_forge_map_slot(1, dst))
      __proof_forge_map_write(1, dst, __pf_checked_add(dstBal, amount))
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := src
        let __pf_event_indexed_topic1 := dst
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_OwnableERC20_mint(recipient, amount) -> __pf_result {
      if iszero(iszero(eq(recipient, 0))) {
        revert(0, 0)
      }
      let ts := and(shr(128, sload(0)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
      }
      let bal := sload(__proof_forge_map_slot(1, recipient))
      __proof_forge_map_write(1, recipient, __pf_checked_add(bal, amount))
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := 0
        let __pf_event_indexed_topic1 := recipient
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_OwnableERC20_burn(amount) -> __pf_result {
      let who := caller()
      let bal := sload(__proof_forge_map_slot(1, who))
      if iszero(iszero(lt(bal, amount))) {
        revert(0, 0)
      }
      __proof_forge_map_write(1, who, __pf_checked_sub(bal, amount))
      let ts := and(shr(128, sload(0)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
      }
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := who
        let __pf_event_indexed_topic1 := 0
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
    }
    function f_OwnableERC20_init(supply) {
      if iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(caller(), 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(18, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(supply, 18446744073709551615))))
      let who := caller()
      __proof_forge_map_write(1, who, supply)
    }
    function f_OwnableERC20_ownerMint(recipient, amount) -> __pf_result {
      if iszero(eq(caller(), and(shr(0, sload(0)), 18446744073709551615))) {
        revert(0, 0)
      }
      let ts := and(shr(128, sload(0)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(ts, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(__pf_packed_value, 18446744073709551615))))
      }
      let bal := sload(__proof_forge_map_slot(1, recipient))
      __proof_forge_map_write(1, recipient, __pf_checked_add(bal, amount))
      {
        mstore(0, 38196372293521921433607444633801509737016894376733792893611070291108288410934)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        let __pf_event_indexed_topic0 := 0
        let __pf_event_indexed_topic1 := recipient
        mstore(0, amount)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := 1
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
