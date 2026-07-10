object "EvmErrorsProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xe6023528 {
      f_EvmErrorsProbe_revertPlain()
      return(0, 0)
    }
    case 0x185c38a4 {
      f_EvmErrorsProbe_revertWithMessage()
      return(0, 0)
    }
    case 0xb34aafd2 {
      f_EvmErrorsProbe_revertWithErrorRef()
      return(0, 0)
    }
    case 0xc5159795 {
      f_EvmErrorsProbe_revertCustomError()
      return(0, 0)
    }
    case 0x0ff6ea62 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      f_EvmErrorsProbe_guardedRevert(calldataload(4))
      return(0, 0)
    }
    case 0x194fd609 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      f_EvmErrorsProbe_conditionalRevert(calldataload(4))
      return(0, 0)
    }
    case 0xa3f05111 {
      let _r := f_EvmErrorsProbe_normalPath()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmErrorsProbe_revertPlain() {
      revert(0, 0)
    }
    function f_EvmErrorsProbe_revertWithMessage() {
      mstore(0, 147028384)
      mstore(4, 32)
      mstore(36, 20)
      mstore(68, 0)
      revert(0, 132)
    }
    function f_EvmErrorsProbe_revertWithErrorRef() {
      mstore(0, 42)
      mstore(32, 64)
      mstore(64, 3)
      mstore(96, 0x4534320000000000000000000000000000000000000000000000000000000000)
      revert(0, 128)
    }
    function f_EvmErrorsProbe_revertCustomError() {
      mstore(0, shl(224, 164293619))
      revert(0, 4)
    }
    function f_EvmErrorsProbe_guardedRevert(condition) {
      if iszero(condition) {
        mstore(0, 1)
        mstore(32, 64)
        mstore(64, 2)
        mstore(96, 0x4531000000000000000000000000000000000000000000000000000000000000)
        revert(0, 128)
      }
    }
    function f_EvmErrorsProbe_conditionalRevert(flag) {
      switch flag
      case 0 { }
      default {
        mstore(0, 147028384)
        mstore(4, 32)
        mstore(36, 23)
        mstore(68, 0)
        revert(0, 132)
      }
    }
    function f_EvmErrorsProbe_normalPath() -> result {
      result := and(shr(192, sload(0)), 18446744073709551615)
    }
  }
}
