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
    function f_Pausable_paused() -> result {
      result := sload(0)
    }
    function f_Pausable_pause() {
      if iszero(eq(sload(0), 0)) {
        revert(0, 0)
      }
      sstore(0, 1)
    }
    function f_Pausable_unpause() {
      if iszero(iszero(eq(sload(0), 0))) {
        revert(0, 0)
      }
      sstore(0, 0)
    }
  }
}
