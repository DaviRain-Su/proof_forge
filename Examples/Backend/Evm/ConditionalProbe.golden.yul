object "ConditionalProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xf3380744 {
      let _r := f_ConditionalProbe_conditional_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_ConditionalProbe_conditional_lifecycle() -> __pf_result {
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
      switch eq(1, 1)
      case 0 {
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(99, 18446744073709551615))))
      }
      default {
        let seed := 4
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(seed, 18446744073709551615))))
      }
      switch lt(and(shr(0, sload(0)), 18446744073709551615), 2)
      case 0 {
        let next := __pf_checked_add(and(shr(0, sload(0)), 18446744073709551615), 6)
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(next, 18446744073709551615))))
      }
      default {
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(100, 18446744073709551615))))
      }
      if iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 10)) {
        revert(0, 0)
      }
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
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
