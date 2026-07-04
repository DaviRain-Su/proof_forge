object "Ownable" {
  code {
    switch shr(224, calldataload(0))
    case 0xe1c7392a {
      f_Ownable_init()
      return(0, 0)
    }
    case 0x8da5cb5b {
      let _r := f_Ownable_owner()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd23e8489 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      f_Ownable_transferOwnership(calldataload(4))
      return(0, 0)
    }
    case 0x715018a6 {
      f_Ownable_renounceOwnership()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_Ownable_init() {
      if iszero(eq(sload(0), 0)) {
        revert(0, 0)
      }
      sstore(0, caller())
    }
    function f_Ownable_owner() -> result {
      result := sload(0)
    }
    function f_Ownable_transferOwnership(newOwner) {
      if iszero(eq(caller(), sload(0))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(newOwner, 0))) {
        revert(0, 0)
      }
      sstore(0, newOwner)
    }
    function f_Ownable_renounceOwnership() {
      if iszero(eq(caller(), sload(0))) {
        revert(0, 0)
      }
      sstore(0, 0)
    }
  }
}
