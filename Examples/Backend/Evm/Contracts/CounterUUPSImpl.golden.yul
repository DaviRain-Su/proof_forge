object "CounterUUPSImpl" {
  code {
    switch shr(224, calldataload(0))
    case 0x3659cfe6 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_CounterUUPSImpl_upgradeTo(calldataload(4))
      return(0, 0)
    }
    case 0xd09de08a {
      f_CounterUUPSImpl_increment()
      return(0, 0)
    }
    case 0x6d4ce63c {
      let _r := f_CounterUUPSImpl_get()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_CounterUUPSImpl_upgradeTo(newImpl) {
      if iszero(eq(__proof_forge_hash_word(caller()), sload(0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(newImpl, 0))) {
        revert(0, 0)
      }
      {
        let __pf_implementation_candidate := newImpl
        if gt(__pf_implementation_candidate, 1461501637330902918203684832716283019655932542975) {
          revert(0, 0)
        }
        if iszero(extcodesize(__pf_implementation_candidate)) {
          revert(0, 0)
        }
        if eq(__pf_implementation_candidate, address()) {
          revert(0, 0)
        }
        sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, __pf_implementation_candidate)
      }
      {
        mstore(0, 38645192964397054375114771727196312373665420932860864730563608020886214410240)
        let __pf_event_topic0 := keccak256(0, 17)
        let __pf_event_indexed_topic0 := newImpl
        log2(0, 0, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_CounterUUPSImpl_increment() {
      let n := and(shr(64, sload(1)), 18446744073709551615)
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(n, 18446744073709551615), __pf_checked_width(1, 18446744073709551615)), 18446744073709551615)
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(64, 18446744073709551615))), shl(64, and(__pf_packed_value, 18446744073709551615))))
      }
    }
    function f_CounterUUPSImpl_get() -> __pf_result {
      __pf_result := and(shr(64, sload(1)), 18446744073709551615)
    }
    function __proof_forge_hash_word(value) -> result {
      mstore(0, value)
      result := keccak256(0, 32)
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
