object "Counter" {
  code {
    switch shr(224, calldataload(0))
    case 0x8129fc1c {
      f_Counter_initialize()
      return(0, 0)
    }
    case 0xd09de08a {
      f_Counter_increment()
      return(0, 0)
    }
    case 0x6d4ce63c {
      let _r := f_Counter_get()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_Counter_initialize() {
      let v0 := 0
      sstore(0, v0)
    }
    function f_Counter_increment() {
      let v1 := sload(0)
      let v2 := 1
      let v3 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v1, 18446744073709551615), __pf_checked_width(v2, 18446744073709551615)), 18446744073709551615)
      sstore(0, v3)
    }
    function f_Counter_get() -> __pf_result {
      let v4 := sload(0)
      __pf_result := v4
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
