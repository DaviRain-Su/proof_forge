object "ContextProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x14a70e97 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_ContextProbe_sum_context(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf0eba40f {
      let _r := f_ContextProbe_native_value()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd9b80589 {
      let _r0, _r1, _r2, _r3, _r4, _r5 := f_ContextProbe_context_extras()
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      mstore(128, _r4)
      mstore(160, _r5)
      return(0, 192)
    }
    case 0xb59b9225 {
      let _r0, _r1, _r2 := f_ContextProbe_context_hashes()
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      return(0, 96)
    }
    default {
      revert(0, 0)
    }
    function f_ContextProbe_sum_context(a, b) -> __pf_result {
      __pf_result := __pf_checked_add(__pf_checked_add(a, b), __pf_checked_add(caller(), __pf_checked_add(address(), number())))
    }
    function f_ContextProbe_native_value() -> __pf_result {
      __pf_result := callvalue()
    }
    function f_ContextProbe_context_extras() -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5 {
      __pf_return_0 := timestamp()
      __pf_return_1 := chainid()
      __pf_return_2 := gasprice()
      __pf_return_3 := gas()
      __pf_return_4 := basefee()
      __pf_return_5 := prevrandao()
    }
    function f_ContextProbe_context_hashes() -> __pf_return_0, __pf_return_1, __pf_return_2 {
      __pf_return_0 := origin()
      __pf_return_1 := coinbase()
      __pf_return_2 := blockhash(1)
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
