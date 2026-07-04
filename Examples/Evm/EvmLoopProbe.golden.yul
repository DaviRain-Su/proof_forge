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
    function f_EvmLoopProbe_count_to_three() -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 0)))
      for {
        let _i := 0
      } lt(_i, 3) {
        _i := add(_i, 1)
      } {
        let n := and(shr(192, sload(0)), 18446744073709551615)
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, __pf_checked_add(n, 1))))
      }
      result := and(shr(192, sload(0)), 18446744073709551615)
    }
    function f_EvmLoopProbe_choose_with_early_return(flag) -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 0)))
      switch flag
      case 0 {
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 22)))
      }
      default {
        result := 11
        leave
      }
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 99)))
      result := and(shr(192, sload(0)), 18446744073709551615)
    }
    function f_EvmLoopProbe_loop_early_return() -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 100)))
      for {
        let _i := 0
      } lt(_i, 3) {
        _i := add(_i, 1)
      } {
        result := _i
        leave
      }
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
