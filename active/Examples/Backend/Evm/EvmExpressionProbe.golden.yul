object "EvmExpressionProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x139ade38 {
      let _r := f_EvmExpressionProbe_arithmetic_u64()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x2e124ba8 {
      let _r := f_EvmExpressionProbe_bitwise_u64()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x219a55f8 {
      let _r := f_EvmExpressionProbe_predicate_matrix()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x555e000e {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(36), 1) {
        revert(0, 0)
      }
      let _r := f_EvmExpressionProbe_casts_and_u32(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmExpressionProbe_arithmetic_u64() -> __pf_result {
      let delta := __pf_checked_sub(9, 4)
      if iszero(eq(delta, 5)) {
        revert(0, 0)
      }
      let sum := __pf_checked_add(delta, 7)
      if iszero(eq(sum, 12)) {
        revert(0, 0)
      }
      let product := __pf_checked_mul(sum, 3)
      if iszero(eq(product, 36)) {
        revert(0, 0)
      }
      let quotient := div(product, 5)
      if iszero(eq(quotient, 7)) {
        revert(0, 0)
      }
      let remainder := mod(product, 5)
      if iszero(eq(remainder, 1)) {
        revert(0, 0)
      }
      let powered := exp(2, 5)
      if iszero(eq(powered, 32)) {
        revert(0, 0)
      }
      __pf_result := __pf_checked_add(__pf_checked_add(powered, quotient), remainder)
    }
    function f_EvmExpressionProbe_bitwise_u64() -> __pf_result {
      let ored := or(20, 8)
      if iszero(eq(ored, 28)) {
        revert(0, 0)
      }
      let anded := and(ored, 10)
      if iszero(eq(anded, 8)) {
        revert(0, 0)
      }
      let xored := xor(anded, 3)
      if iszero(eq(xored, 11)) {
        revert(0, 0)
      }
      let left := shl(1, xored)
      if iszero(eq(left, 22)) {
        revert(0, 0)
      }
      let right := shr(1, left)
      if iszero(eq(right, 11)) {
        revert(0, 0)
      }
      __pf_result := right
    }
    function f_EvmExpressionProbe_predicate_matrix() -> __pf_result {
      let a := 7
      let b := 9
      let a_is_seven := eq(a, 7)
      let a_not_b := iszero(eq(a, b))
      let a_before_b := and(lt(a, b), iszero(gt(a, b)))
      let b_after_a := and(gt(b, a), iszero(lt(b, b)))
      let any_ordered := or(eq(a, b), a_before_b)
      let not_equal := iszero(eq(a, b))
      let bool_eq := eq(a_is_seven, 1)
      let bool_ne := iszero(eq(a_before_b, 0))
      if iszero(a_is_seven) {
        revert(0, 0)
      }
      if iszero(a_not_b) {
        revert(0, 0)
      }
      if iszero(a_before_b) {
        revert(0, 0)
      }
      if iszero(b_after_a) {
        revert(0, 0)
      }
      if iszero(any_ordered) {
        revert(0, 0)
      }
      if iszero(not_equal) {
        revert(0, 0)
      }
      if iszero(bool_eq) {
        revert(0, 0)
      }
      if iszero(bool_ne) {
        revert(0, 0)
      }
      __pf_result := __pf_checked_add(__pf_checked_add(__pf_checked_add(a_is_seven, a_not_b), __pf_checked_add(a_before_b, b_after_a)), __pf_checked_add(__pf_checked_add(any_ordered, not_equal), __pf_checked_add(bool_eq, bool_ne)))
    }
    function f_EvmExpressionProbe_casts_and_u32(delta, flag) -> __pf_result {
      let delta64 := delta
      let flag32 := flag
      let flag64 := flag
      let narrowed := 33
      let u32_bool := 1
      let u64_bool := 1
      let word_sum := __pf_checked_add(delta, 3)
      if iszero(eq(word_sum, 10)) {
        revert(0, 0)
      }
      let word_product := __pf_checked_mul(__pf_checked_sub(word_sum, 1), 2)
      if iszero(eq(word_product, 18)) {
        revert(0, 0)
      }
      let word_quotient := div(word_product, 3)
      if iszero(eq(word_quotient, 6)) {
        revert(0, 0)
      }
      let word_remainder := mod(word_product, 5)
      if iszero(eq(word_remainder, 3)) {
        revert(0, 0)
      }
      let word_bits := shr(2, shl(1, xor(or(and(12, 10), 1), 3)))
      if iszero(eq(word_bits, 5)) {
        revert(0, 0)
      }
      if iszero(u32_bool) {
        revert(0, 0)
      }
      if iszero(u64_bool) {
        revert(0, 0)
      }
      __pf_result := __pf_checked_add(__pf_checked_add(__pf_checked_add(delta64, flag32), __pf_checked_add(flag64, narrowed)), __pf_checked_add(word_remainder, word_bits))
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
