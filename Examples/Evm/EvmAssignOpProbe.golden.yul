object "EvmAssignOpProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x72250d96 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmAssignOpProbe_compound_assignment(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1508c8ff {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmAssignOpProbe_compound_u32(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmAssignOpProbe_compound_assignment(seed) -> result {
      let total := seed
      total := __pf_checked_add(total, 7)
      total := __pf_checked_sub(total, 2)
      total := __pf_checked_mul(total, 3)
      total := div(total, 5)
      total := mod(total, 11)
      total := or(total, 8)
      total := and(total, 14)
      total := xor(total, 3)
      total := shl(1, total)
      total := shr(1, total)
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, total)))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, __pf_checked_add(and(shr(192, sload(0)), 18446744073709551615), 5))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, __pf_checked_sub(and(shr(192, sload(0)), 18446744073709551615), 1))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, __pf_checked_mul(and(shr(192, sload(0)), 18446744073709551615), 2))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, div(and(shr(192, sload(0)), 18446744073709551615), 3))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, mod(and(shr(192, sload(0)), 18446744073709551615), 13))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, or(and(shr(192, sload(0)), 18446744073709551615), 16))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, and(and(shr(192, sload(0)), 18446744073709551615), 31))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, xor(and(shr(192, sload(0)), 18446744073709551615), 7))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, shl(2, and(shr(192, sload(0)), 18446744073709551615)))))
      sstore(0, or(and(sload(0), not(shl(192, 18446744073709551615))), shl(192, shr(1, and(shr(192, sload(0)), 18446744073709551615)))))
      result := and(shr(192, sload(0)), 18446744073709551615)
    }
    function f_EvmAssignOpProbe_compound_u32(seed) -> result {
      let word := seed
      word := __pf_checked_add(word, 3)
      word := __pf_checked_sub(word, 1)
      word := __pf_checked_mul(word, 2)
      word := div(word, 11)
      word := mod(word, 3)
      word := or(word, 8)
      word := and(word, 10)
      word := xor(word, 3)
      word := shl(1, word)
      word := shr(1, word)
      result := word
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
