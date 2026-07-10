object "UUPSProxy" {
  code {
    switch shr(224, calldataload(0))
    default {
      let _impl := sload(0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc)
      if iszero(_impl) {
        revert(0, 0)
      }
      calldatacopy(0, 0, calldatasize())
      let _ok := delegatecall(gas(), _impl, 0, calldatasize(), 0, 0)
      returndatacopy(0, 0, returndatasize())
      if iszero(_ok) {
        revert(0, returndatasize())
      }
      return(0, returndatasize())
    }
  }
}
