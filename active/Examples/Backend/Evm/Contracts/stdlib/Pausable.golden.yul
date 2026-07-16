object "Pausable" {
  code {
    switch shr(224, calldataload(0))
    case 0x5c975abb {
      let _r := f_Pausable_paused()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x8456cb59 {
      f_Pausable_pause()
      return(0, 0)
    }
    case 0x3f4ba83a {
      f_Pausable_unpause()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_Pausable_paused() -> __pf_result {
      let v0 := and(shr(0, sload(0)), 18446744073709551615)
      __pf_result := v0
    }
    function f_Pausable_pause() {
      let v1 := and(shr(0, sload(0)), 18446744073709551615)
      let v2 := 0
      let v3 := eq(v1, v2)
      if iszero(v3) {
        revert(0, 0)
      }
      let v4 := 1
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(v4, 18446744073709551615))))
    }
    function f_Pausable_unpause() {
      let v5 := and(shr(0, sload(0)), 18446744073709551615)
      let v6 := 0
      let v7 := iszero(eq(v5, v6))
      if iszero(v7) {
        revert(0, 0)
      }
      let v8 := 0
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(v8, 18446744073709551615))))
    }
  }
}
