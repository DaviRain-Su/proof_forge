object "VerifiedVault" {
  code {
    switch shr(224, calldataload(0))
    case 0xa7134f73 {
      f_VerifiedVault_acquire()
      return(0, 0)
    }
    case 0x86d1a69f {
      f_VerifiedVault_release()
      return(0, 0)
    }
    case 0xcf309012 {
      let _r := f_VerifiedVault_locked()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe1c7392a {
      f_VerifiedVault_init()
      return(0, 0)
    }
    case 0xd0e30db0 {
      f_VerifiedVault_deposit()
      return(0, 0)
    }
    case 0x2e1a7d4d {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_VerifiedVault_withdraw(calldataload(4))
      return(0, 0)
    }
    case 0x75172a8b {
      let _r := f_VerifiedVault_reserves()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x3a98ef39 {
      let _r := f_VerifiedVault_totalShares()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x9cc7f708 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_VerifiedVault_balanceOf(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x893d20e8 {
      let _r := f_VerifiedVault_getOwner()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_VerifiedVault_acquire() {
      if iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(1, 18446744073709551615))))
    }
    function f_VerifiedVault_release() {
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
    }
    function f_VerifiedVault_locked() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_VerifiedVault_init() {
      if iszero(eq(and(shr(128, sload(0)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(64, 18446744073709551615))), shl(64, and(caller(), 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(1, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(0, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
    }
    function f_VerifiedVault_deposit() {
      if iszero(iszero(eq(and(shr(128, sload(0)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      let depositor := caller()
      let amount := callvalue()
      if iszero(iszero(eq(amount, 0))) {
        revert(0, 0)
      }
      let curReserves := and(shr(192, sload(0)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(curReserves, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(__pf_packed_value, 18446744073709551615))))
      }
      let curShares := and(shr(0, sload(1)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(curShares, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      let bal := sload(__proof_forge_map_slot(2, depositor))
      __proof_forge_map_write(2, depositor, __pf_checked_add(bal, amount))
    }
    function f_VerifiedVault_withdraw(amount) {
      if iszero(iszero(eq(and(shr(128, sload(0)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(1, 18446744073709551615))))
      let withdrawer := caller()
      let bal := sload(__proof_forge_map_slot(2, withdrawer))
      if iszero(iszero(lt(bal, amount))) {
        revert(0, 0)
      }
      let curReserves := and(shr(192, sload(0)), 18446744073709551615)
      if iszero(iszero(lt(curReserves, amount))) {
        revert(0, 0)
      }
      let curShares := and(shr(0, sload(1)), 18446744073709551615)
      if iszero(iszero(lt(curShares, amount))) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(curReserves, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(__pf_packed_value, 18446744073709551615))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(curShares, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
      __proof_forge_map_write(2, withdrawer, __pf_checked_sub(bal, amount))
      let _sent := __proof_forge_native_transfer(withdrawer, amount)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
    }
    function f_VerifiedVault_reserves() -> __pf_result {
      __pf_result := and(shr(192, sload(0)), 18446744073709551615)
    }
    function f_VerifiedVault_totalShares() -> __pf_result {
      __pf_result := and(shr(0, sload(1)), 18446744073709551615)
    }
    function f_VerifiedVault_balanceOf(depositor) -> __pf_result {
      __pf_result := sload(__proof_forge_map_slot(2, depositor))
    }
    function f_VerifiedVault_getOwner() -> __pf_result {
      __pf_result := and(shr(64, sload(0)), 18446744073709551615)
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
    function __proof_forge_native_transfer(target, call_value) -> result {
      let _success := call(gas(), target, call_value, 0, 0, 0, 0)
      if iszero(_success) {
        revert(0, 0)
      }
      result := 0
    }
  }
}
