object "Ownable" {
  code {
    switch shr(224, calldataload(0))
    case 0x8da5cb5b {
      let _r := f_Ownable_owner()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd23e8489 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_Ownable_transferOwnership(calldataload(4))
      return(0, 0)
    }
    case 0x715018a6 {
      f_Ownable_renounceOwnership()
      return(0, 0)
    }
    case 0xe1c7392a {
      f_Ownable_init()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_Ownable_owner() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_Ownable_transferOwnership(newOwner) {
      if iszero(eq(caller(), and(shr(0, sload(0)), 18446744073709551615))) {
        revert(0, 0)
      }
      if iszero(iszero(eq(newOwner, 0))) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(newOwner, 18446744073709551615))))
    }
    function f_Ownable_renounceOwnership() {
      if iszero(eq(caller(), and(shr(0, sload(0)), 18446744073709551615))) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(0, 18446744073709551615))))
    }
    function f_Ownable_init() {
      if iszero(eq(and(shr(0, sload(0)), 18446744073709551615), 0)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(0, 18446744073709551615))), shl(0, and(caller(), 18446744073709551615))))
    }
  }
}
