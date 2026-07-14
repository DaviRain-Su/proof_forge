object "ReentrancyGuard" {
  code {
    switch shr(224, calldataload(0))
    case 0xa7134f73 {
      f_ReentrancyGuard_acquire()
      return(0, 0)
    }
    case 0x86d1a69f {
      f_ReentrancyGuard_release()
      return(0, 0)
    }
    case 0xcf309012 {
      let _r := f_ReentrancyGuard_locked()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_ReentrancyGuard_acquire() {
      let v0 := and(shr(0, sload(0)), 18446744073709551615)
      let v1 := 0
      let v2 := eq(v0, v1)
      if iszero(v2) {
        revert(0, 0)
      }
      let v3 := 1
      {
        let __pf_packed_value := v3
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
    }
    function f_ReentrancyGuard_release() {
      let v4 := and(shr(0, sload(0)), 18446744073709551615)
      let v5 := 0
      let v6 := iszero(eq(v4, v5))
      if iszero(v6) {
        revert(0, 0)
      }
      let v7 := 0
      {
        let __pf_packed_value := v7
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(__pf_packed_value, 18446744073709551615))))
      }
    }
    function f_ReentrancyGuard_locked() -> __pf_result {
      let v8 := and(shr(0, sload(0)), 18446744073709551615)
      __pf_result := v8
    }
  }
}
