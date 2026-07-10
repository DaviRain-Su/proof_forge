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
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_Pausable_pause() {
      if iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(1, 18446744073709551615))))
    }
    function f_Pausable_unpause() {
      if iszero(iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 0))) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
    }
  }
}
