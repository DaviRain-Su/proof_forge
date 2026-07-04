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
    function f_ConditionalProbe_conditional_lifecycle() -> result {
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 0)))
      switch eq(1, 1)
      case 0 {
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 99)))
      }
      default {
        let seed := 4
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, seed)))
      }
      switch lt(and(shr(192, sload(0)), 18446744073709551615), 2)
      case 0 {
        let next := __pf_checked_add(and(shr(192, sload(0)), 18446744073709551615), 6)
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, next)))
      }
      default {
        sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, 100)))
      }
      if iszero(eq(and(shr(192, sload(0)), 18446744073709551615), 10)) {
        revert(0, 0)
      }
      result := and(shr(192, sload(0)), 18446744073709551615)
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
