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
      if iszero(eq(sload(0), 0)) {
        revert(0, 0)
      }
      sstore(0, 1)
    }
    function f_ReentrancyGuard_release() {
      sstore(0, 0)
    }
    function f_ReentrancyGuard_locked() -> result {
      result := sload(0)
    }
  }
}
