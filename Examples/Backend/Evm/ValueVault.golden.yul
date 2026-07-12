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
      let v1 := number()
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(initial, 18446744073709551615))))
      let v2 := 0
      sstore(0, or(and(sload(0), not(shl(64, 18446744073709551615))), shl(64, and(v2, 18446744073709551615))))
      let v3 := 0
      sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(v3, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(initial, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(v1, 18446744073709551615))))
      let v4 := 1
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(v4, 18446744073709551615))))
      {
        mstore(0, 39071099571687660945166386872448312871805156882141718791961628460695011207424)
        let __pf_event_topic0 := keccak256(0, 31)
        mstore(0, initial)
        mstore(32, v1)
        log1(0, 64, __pf_event_topic0)
      }
    }
    function f_ValueVault_deposit(amount) {
      let v6 := and(shr(0, sload(0)), 18446744073709551615)
      let v7 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v6, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
      let v8 := and(shr(64, sload(1)), 18446744073709551615)
      let v9 := 1
      let v10 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v8, 18446744073709551615), __pf_checked_width(v9, 18446744073709551615)), 18446744073709551615)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(v7, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(amount, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(v10, 18446744073709551615))))
      {
        mstore(0, 39071037697028304160098723791689314040959467696239598275638237910041856665966)
        mstore(32, 52564060173324780267596278835754282818996031008839138188382124664963096117248)
        let __pf_event_topic0 := keccak256(0, 36)
        mstore(0, amount)
        mstore(32, v7)
        mstore(64, v10)
        log1(0, 96, __pf_event_topic0)
      }
    }
    function f_ValueVault_charge_fee(gross, fee_bps) {
      let v13 := __pf_checked_width(__pf_checked_mul(__pf_checked_width(gross, 18446744073709551615), __pf_checked_width(fee_bps, 18446744073709551615)), 18446744073709551615)
      let v14 := 10000
      if iszero(iszero(iszero(v14))) {
        revert(0, 0)
      }
      let v15 := div(v13, v14)
      let v16 := __pf_checked_width(__pf_checked_sub(__pf_checked_width(gross, 18446744073709551615), __pf_checked_width(v15, 18446744073709551615)), 18446744073709551615)
      let v17 := and(shr(0, sload(0)), 18446744073709551615)
      let v18 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v17, 18446744073709551615), __pf_checked_width(v16, 18446744073709551615)), 18446744073709551615)
      let v19 := and(shr(128, sload(0)), 18446744073709551615)
      let v20 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v19, 18446744073709551615), __pf_checked_width(v15, 18446744073709551615)), 18446744073709551615)
      let v21 := and(shr(64, sload(1)), 18446744073709551615)
      let v22 := 1
      let v23 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v21, 18446744073709551615), __pf_checked_width(v22, 18446744073709551615)), 18446744073709551615)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(v18, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(128, 18446744073709551615))), shl(128, and(v20, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(v16, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(v23, 18446744073709551615))))
      {
        mstore(0, 39071037697027897510689409130345737227010720245254687220372800936815839048758)
        mstore(32, 23598819743929234470467432538778669474426055237433427601561053256784151576576)
        let __pf_event_topic0 := keccak256(0, 41)
        mstore(0, gross)
        mstore(32, v15)
        mstore(64, v16)
        mstore(96, v18)
        log1(0, 128, __pf_event_topic0)
      }
    }
    function f_ValueVault_release(amount) {
      let v25 := and(shr(0, sload(0)), 18446744073709551615)
      let v26 := __pf_checked_width(__pf_checked_sub(__pf_checked_width(v25, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
      let v27 := and(shr(64, sload(0)), 18446744073709551615)
      let v28 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v27, 18446744073709551615), __pf_checked_width(amount, 18446744073709551615)), 18446744073709551615)
      let v29 := and(shr(64, sload(1)), 18446744073709551615)
      let v30 := 1
      let v31 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v29, 18446744073709551615), __pf_checked_width(v30, 18446744073709551615)), 18446744073709551615)
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(v26, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(64, 18446744073709551615))), shl(64, and(v28, 18446744073709551615))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(amount, 18446744073709551615))))
      sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(v31, 18446744073709551615))))
      {
        mstore(0, 39071037697034063400694021446782743710686767595469519175822566052150785961588)
        mstore(32, 24517052842465079370413120945299090683665717048513947648744169312629567782912)
        let __pf_event_topic0 := keccak256(0, 35)
        mstore(0, amount)
        mstore(32, v26)
        mstore(64, v28)
        log1(0, 96, __pf_event_topic0)
      }
    }
    function f_ValueVault_snapshot() -> __pf_result {
      let v32 := number()
      let v33 := and(shr(0, sload(0)), 18446744073709551615)
      let v34 := and(shr(64, sload(0)), 18446744073709551615)
      let v35 := and(shr(128, sload(0)), 18446744073709551615)
      sstore(1, or(and(sload(1), not(shl(0, 18446744073709551615))), shl(0, and(v32, 18446744073709551615))))
      {
        mstore(0, 39071037697034489170499070161745893994303869518306945196793092304346311913076)
        mstore(32, 24517076713121108544309768058624709740433614168679780803641681990953488875520)
        let __pf_event_topic0 := keccak256(0, 42)
        mstore(0, v33)
        mstore(32, v34)
        mstore(64, v35)
        mstore(96, v32)
        log1(0, 128, __pf_event_topic0)
      }
      __pf_result := v33
    }
    function f_ValueVault_get_balance() -> __pf_result {
      let v36 := and(shr(0, sload(0)), 18446744073709551615)
      __pf_result := v36
    }
    function f_ValueVault_get_net_value() -> __pf_result {
      let v37 := and(shr(0, sload(0)), 18446744073709551615)
      let v38 := and(shr(128, sload(0)), 18446744073709551615)
      let v39 := __pf_checked_width(__pf_checked_sub(__pf_checked_width(v37, 18446744073709551615), __pf_checked_width(v38, 18446744073709551615)), 18446744073709551615)
      __pf_result := v39
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
