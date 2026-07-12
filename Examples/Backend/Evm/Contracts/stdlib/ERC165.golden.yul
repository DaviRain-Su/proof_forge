object "ERC165" {
  code {
    switch shr(224, calldataload(0))
    case 0x01ffc9a7 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if and(calldataload(4), 26959946667150639794667015087019630673637144422540572481103610249215) {
        revert(0, 0)
      }
      let _r := f_ERC165_supportsInterface(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_ERC165_supportsInterface(interfaceId) -> __pf_result {
      __pf_result := eq(interfaceId, shl(224, 33540519))
    }
  }
}
