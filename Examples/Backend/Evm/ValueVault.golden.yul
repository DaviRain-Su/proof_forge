object "ValueVault" {
  code {
    switch shr(224, calldataload(0))
    case 0xfe4b84df {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_ValueVault_initialize(calldataload(4))
      return(0, 0)
    }
    case 0xb6b55f25 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_ValueVault_deposit(calldataload(4))
      return(0, 0)
    }
    case 0xbe168a46 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_ValueVault_charge_fee(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x37bdc99b {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_ValueVault_release(calldataload(4))
      return(0, 0)
    }
    case 0x9711715a {
      let _r := f_ValueVault_snapshot()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc1cfb99a {
      let _r := f_ValueVault_get_balance()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd43f79a2 {
      let _r := f_ValueVault_get_net_value()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_ValueVault_initialize(initial) {
      let checkpoint := number()
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(initial, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(64, 18446744073709551615))), shl(64, and(0, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(0, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(initial, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(checkpoint, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(1, 18446744073709551615))))
      {
        mstore(0, 39071099571687660945166386872448312871805156882141718791961628460695011207424)
        let __pf_event_topic0 := keccak256(0, 31)
        mstore(0, initial)
        mstore(32, checkpoint)
        log1(0, 64, __pf_event_topic0)
      }
    }
    function f_ValueVault_deposit(amount) {
      let current := and(shr(0, sload(0)), 18446744073709551615)
      let next := __pf_checked_add(current, amount)
      let ops := and(shr(64, sload(1)), 18446744073709551615)
      let next_ops := __pf_checked_add(ops, 1)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(next, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(amount, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(next_ops, 18446744073709551615))))
      {
        mstore(0, 39071037697028304160098723791689314040959467696239598275638237910041856665966)
        mstore(32, 52564060173324780267596278835754282818996031008839138188382124664963096117248)
        let __pf_event_topic0 := keccak256(0, 36)
        mstore(0, amount)
        mstore(32, next)
        mstore(64, next_ops)
        log1(0, 96, __pf_event_topic0)
      }
    }
    function f_ValueVault_charge_fee(gross, fee_bps) {
      let fee := div(__pf_checked_mul(gross, fee_bps), 10000)
      let net := __pf_checked_sub(gross, fee)
      let current := and(shr(0, sload(0)), 18446744073709551615)
      let next := __pf_checked_add(current, net)
      let current_fees := and(shr(128, sload(0)), 18446744073709551615)
      let next_fees := __pf_checked_add(current_fees, fee)
      let ops := and(shr(64, sload(1)), 18446744073709551615)
      let next_ops := __pf_checked_add(ops, 1)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(next, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(next_fees, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(net, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(next_ops, 18446744073709551615))))
      {
        mstore(0, 39071037697027897510689409130345737227010720245254687220372800936815839048758)
        mstore(32, 23598819743929234470467432538778669474426055237433427601561053256784151576576)
        let __pf_event_topic0 := keccak256(0, 41)
        mstore(0, gross)
        mstore(32, fee)
        mstore(64, net)
        mstore(96, next)
        log1(0, 128, __pf_event_topic0)
      }
    }
    function f_ValueVault_release(amount) {
      let current := and(shr(0, sload(0)), 18446744073709551615)
      let next := __pf_checked_sub(current, amount)
      let released_before := and(shr(64, sload(0)), 18446744073709551615)
      let released_next := __pf_checked_add(released_before, amount)
      let ops := and(shr(64, sload(1)), 18446744073709551615)
      let next_ops := __pf_checked_add(ops, 1)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(next, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(64, 18446744073709551615))), shl(64, and(released_next, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(amount, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(next_ops, 18446744073709551615))))
      {
        mstore(0, 39071037697034063400694021446782743710686767595469519175822566052150785961588)
        mstore(32, 24517052842465079370413120945299090683665717048513947648744169312629567782912)
        let __pf_event_topic0 := keccak256(0, 35)
        mstore(0, amount)
        mstore(32, next)
        mstore(64, released_next)
        log1(0, 96, __pf_event_topic0)
      }
    }
    function f_ValueVault_snapshot() -> __pf_result {
      let checkpoint := number()
      let balance_now := and(shr(0, sload(0)), 18446744073709551615)
      let released_now := and(shr(64, sload(0)), 18446744073709551615)
      let fees_now := and(shr(128, sload(0)), 18446744073709551615)
      sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(checkpoint, 18446744073709551615))))
      {
        mstore(0, 39071037697034489170499070161745893994303869518306945196793092304346311913076)
        mstore(32, 24517076713121108544309768058624709740433614168679780803641681990953488875520)
        let __pf_event_topic0 := keccak256(0, 42)
        mstore(0, balance_now)
        mstore(32, released_now)
        mstore(64, fees_now)
        mstore(96, checkpoint)
        log1(0, 128, __pf_event_topic0)
      }
      __pf_result := balance_now
    }
    function f_ValueVault_get_balance() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_ValueVault_get_net_value() -> __pf_result {
      let balance_now := and(shr(0, sload(0)), 18446744073709551615)
      let fees_now := and(shr(128, sload(0)), 18446744073709551615)
      __pf_result := __pf_checked_sub(balance_now, fees_now)
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
