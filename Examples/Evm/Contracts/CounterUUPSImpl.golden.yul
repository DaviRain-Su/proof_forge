object "CounterUUPSImpl" {
  code {
    switch shr(224, calldataload(0))
    case 0x3659cfe6 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      f_CounterUUPSImpl_upgradeTo(calldataload(4))
      return(0, 0)
    }
    case 0xe1c7392a {
      f_CounterUUPSImpl_init()
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
      if iszero(eq(caller(), sload(0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(newImpl, 0))) {
        revert(0, 0)
      }
      sstore(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc, newImpl)
      {
        mstore(0, 38645192964397054375116689231969871224811042888286884345660562590062149107712)
        let _topic0 := keccak256(0, 16)
        let _indexed_topic0 := newImpl
        log2(0, 0, _topic0, _indexed_topic0)
      }
    }
    function f_CounterUUPSImpl_init() {
      sstore(0, caller())
      sstore(2, 0)
    }
    function f_CounterUUPSImpl_increment() {
      let n := sload(2)
      sstore(2, __pf_checked_add(n, 1))
    }
    function f_CounterUUPSImpl_get() -> result {
      result := sload(2)
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
