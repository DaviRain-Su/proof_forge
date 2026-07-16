object "EvmLoopProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xc4eff2de {
      let _r := f_EvmLoopProbe_count_to_three()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd9b42937 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      let _r := f_EvmLoopProbe_choose_with_early_return(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd11c9505 {
      let _r := f_EvmLoopProbe_loop_early_return()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmLoopProbe_count_to_three() -> __pf_result {
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
      for {
        let _i := 0
      } lt(_i, 3) {
        _i := add(_i, 1)
      } {
        let n := and(shr(0, sload(0)), 18446744073709551615)
        {
          let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(n, 18446744073709551615), __pf_checked_width(1, 18446744073709551615)), 18446744073709551615)
          if gt(__pf_packed_value, 18446744073709551615) {
            revert(0, 0)
          }
          sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
        }
      }
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_EvmLoopProbe_choose_with_early_return(flag) -> __pf_result {
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
      switch flag
      case 0 {
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(22, 18446744073709551615))))
      }
      default {
        __pf_result := 11
        leave
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(99, 18446744073709551615))))
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_EvmLoopProbe_loop_early_return() -> __pf_result {
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(100, 18446744073709551615))))
      for {
        let _i := 0
      } lt(_i, 3) {
        _i := add(_i, 1)
      } {
        __pf_result := _i
        leave
      }
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
