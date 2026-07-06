object "EvmDynamicArrayProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xe4684b67 {
      let _r := f_EvmDynamicArrayProbe_storage_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xac35feee {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmDynamicArrayProbe_read_value(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5a6fd3b0 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      f_EvmDynamicArrayProbe_write_value(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xbce9e77b {
      let _r := f_EvmDynamicArrayProbe_path_assign_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xb408dd47 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      f_EvmDynamicArrayProbe_push_value(calldataload(4))
      return(0, 0)
    }
    case 0x12c62f71 {
      f_EvmDynamicArrayProbe_pop_value()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_EvmDynamicArrayProbe_storage_lifecycle() -> result {
      sstore(__proof_forge_dynamic_array_slot(0, 0), 7)
      sstore(__proof_forge_dynamic_array_slot(0, 1), 11)
      sstore(__proof_forge_dynamic_array_slot(0, 2), 13)
      result := __pf_checked_add(__pf_checked_add(sload(__proof_forge_dynamic_array_slot(0, 0)), sload(__proof_forge_dynamic_array_slot(0, 1))), sload(__proof_forge_dynamic_array_slot(0, 2)))
    }
    function f_EvmDynamicArrayProbe_read_value(index) -> result {
      result := sload(__proof_forge_dynamic_array_slot(0, index))
    }
    function f_EvmDynamicArrayProbe_write_value(index, value) {
      sstore(__proof_forge_dynamic_array_slot(0, index), value)
    }
    function f_EvmDynamicArrayProbe_path_assign_lifecycle() -> result {
      sstore(__proof_forge_dynamic_array_slot(0, 2), 10)
      {
        let _slot := __proof_forge_dynamic_array_slot(0, 2)
        sstore(_slot, __pf_checked_add(sload(_slot), 5))
      }
      result := sload(__proof_forge_dynamic_array_slot(0, 2))
    }
    function f_EvmDynamicArrayProbe_push_value(value) {
      let __proof_forge_dyn_array_len := sload(0)
      let __proof_forge_dyn_array_new_len := add(__proof_forge_dyn_array_len, 1)
      sstore(__proof_forge_dynamic_array_slot(0, __proof_forge_dyn_array_len), value)
      sstore(0, __proof_forge_dyn_array_new_len)
    }
    function f_EvmDynamicArrayProbe_pop_value() {
      let __proof_forge_dyn_array_len := sload(0)
      if iszero(__proof_forge_dyn_array_len) {
        revert(0, 0)
      }
      let __proof_forge_dyn_array_new_len := sub(__proof_forge_dyn_array_len, 1)
      sstore(0, __proof_forge_dyn_array_new_len)
    }
    function __proof_forge_dynamic_array_slot(slot, index) -> result {
      mstore(0, slot)
      result := add(keccak256(0, 32), index)
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
