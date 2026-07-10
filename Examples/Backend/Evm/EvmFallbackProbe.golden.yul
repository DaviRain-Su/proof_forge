object "EvmFallbackProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xd09de08a {
      f_EvmFallbackProbe_increment()
      return(0, 0)
    }
    case 0x20965255 {
      let _r := f_EvmFallbackProbe_getValue()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      if iszero(calldatasize()) {
        __pf_receive()
        return(0, 0)
      }
      __pf_fallback()
    }
    function f_EvmFallbackProbe_increment() {
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(and(add(and(shr(0, sload(0)), 18446744073709551615), 1), 18446744073709551615), 18446744073709551615))))
    }
    function f_EvmFallbackProbe_getValue() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function __pf_fallback() {
      mstore(0, 147028384)
      mstore(4, 32)
      mstore(36, 26)
      mstore(68, 0)
      revert(0, 132)
    }
    function __pf_receive() {
      sstore(0, or(and(sload(0), not(shl(64, 18446744073709551615))), shl(64, and(and(add(and(shr(64, sload(0)), 18446744073709551615), 1), 18446744073709551615), 18446744073709551615))))
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
