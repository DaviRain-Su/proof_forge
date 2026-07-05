object "EvmMemoryArrayProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x351b36c7 {
      let _r := f_EvmMemoryArrayProbe_memory_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf748ed48 {
      let _r := f_EvmMemoryArrayProbe_memory_length()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc46232c0 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      let _r := f_EvmMemoryArrayProbe_get_and_sum(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmMemoryArrayProbe_memory_lifecycle() -> result {
      let arr := __proof_forge_memory_array_new(3)
      {
        if iszero(lt(0, mload(arr))) {
          revert(0, 0)
        }
        mstore(add(add(arr, 32), mul(0, 32)), 7)
      }
      {
        if iszero(lt(1, mload(arr))) {
          revert(0, 0)
        }
        mstore(add(add(arr, 32), mul(1, 32)), 11)
      }
      {
        if iszero(lt(2, mload(arr))) {
          revert(0, 0)
        }
        mstore(add(add(arr, 32), mul(2, 32)), 13)
      }
      result := __pf_checked_add(__pf_checked_add(__proof_forge_memory_array_get(arr, 0), __proof_forge_memory_array_get(arr, 1)), __proof_forge_memory_array_get(arr, 2))
    }
    function f_EvmMemoryArrayProbe_memory_length() -> result {
      let arr := __proof_forge_memory_array_new(5)
      result := mload(arr)
    }
    function f_EvmMemoryArrayProbe_get_and_sum(a, b, c) -> result {
      let arr := __proof_forge_memory_array_new(3)
      {
        if iszero(lt(0, mload(arr))) {
          revert(0, 0)
        }
        mstore(add(add(arr, 32), mul(0, 32)), a)
      }
      {
        if iszero(lt(1, mload(arr))) {
          revert(0, 0)
        }
        mstore(add(add(arr, 32), mul(1, 32)), b)
      }
      {
        if iszero(lt(2, mload(arr))) {
          revert(0, 0)
        }
        mstore(add(add(arr, 32), mul(2, 32)), c)
      }
      result := __pf_checked_add(__pf_checked_add(__proof_forge_memory_array_get(arr, 0), __proof_forge_memory_array_get(arr, 1)), __proof_forge_memory_array_get(arr, 2))
    }
    function __proof_forge_memory_array_new(length) -> ptr {
      ptr := mload(64)
      mstore(ptr, length)
      mstore(64, add(ptr, mul(add(length, 1), 32)))
    }
    function __proof_forge_memory_array_get(array, index) -> value {
      if iszero(lt(index, mload(array))) {
        revert(0, 0)
      }
      value := mload(add(add(array, 32), mul(index, 32)))
    }
    function __pf_checked_add(a, b) -> r {
      if gt(a, sub(115792089237316195423570985008687907853269984665640564039457584007913129639935, b)) {
        revert(0, 0)
      }
      r := add(a, b)
    }
    function __pf_checked_sub(a, b) -> r {
      if gt(b, a) {
        revert(0, 0)
      }
      r := sub(a, b)
    }
    function __pf_checked_mul(a, b) -> r {
      if iszero(a) {
        r := 0
        leave
      }
      if gt(a, div(115792089237316195423570985008687907853269984665640564039457584007913129639935, b)) {
        revert(0, 0)
      }
      r := mul(a, b)
    }
  }
}
