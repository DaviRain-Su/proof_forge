object "EvmPackedStorageProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0xde0edef5 {
      let _r := f_EvmPackedStorageProbe_packed_slot0_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc8fb82aa {
      let _r := f_EvmPackedStorageProbe_packed_slot1_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x329510c2 {
      let _r := f_EvmPackedStorageProbe_packed_slot2_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe077025f {
      let _r := f_EvmPackedStorageProbe_packed_slot3_lifecycle()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd1a61f5e {
      let _r := f_EvmPackedStorageProbe_packed_assign_op()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x9641cb4f {
      let _r := f_EvmPackedStorageProbe_packed_assign_op_wraps()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x48bedaed {
      let _r := f_EvmPackedStorageProbe_packed_nested_checked_overflow_reverts()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa691f1b1 {
      let _r := f_EvmPackedStorageProbe_packed_mixed_overflow_reverts()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xbaa34f4a {
      let _r := f_EvmPackedStorageProbe_packed_nested_wrapping_preserves_neighbors()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xffb3ca34 {
      let _r := f_EvmPackedStorageProbe_packed_checked_mul_zero_rhs_succeeds()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xab0efcd6 {
      let _r := f_EvmPackedStorageProbe_packed_assign_op_overflow_reverts()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x2b19bf56 {
      let _r := f_EvmPackedStorageProbe_packed_checked_write_overflow_reverts()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xd1614879 {
      let _r := f_EvmPackedStorageProbe_packed_checked_literal_write_overflow_reverts()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x463dd423 {
      let _r := f_EvmPackedStorageProbe_packed_checked_local_write_overflow_reverts()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc1244eee {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 255) {
        revert(0, 0)
      }
      let _r := f_EvmPackedStorageProbe_packed_checked_write_param(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmPackedStorageProbe_packed_slot0_lifecycle() -> __pf_result {
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 200
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 1000
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := 99999
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(48, 18446744073709551615))), shl(48, and(__pf_packed_value, 18446744073709551615))))
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 200)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(16, sload(0)), 4294967295), 1000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(48, sload(0)), 18446744073709551615), 99999)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := 42
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 42)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(16, sload(0)), 4294967295), 1000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(48, sload(0)), 18446744073709551615), 99999)) {
        revert(0, 0)
      }
      __pf_result := and(shr(48, sload(0)), 18446744073709551615)
    }
    function f_EvmPackedStorageProbe_packed_slot1_lifecycle() -> __pf_result {
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 42
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 340282366920938463463374607431768211455
        if gt(__pf_packed_value, 340282366920938463463374607431768211455) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(112, 340282366920938463463374607431768211455))), shl(112, and(__pf_packed_value, 340282366920938463463374607431768211455))))
      }
      if iszero(eq(and(shr(112, sload(0)), 340282366920938463463374607431768211455), 340282366920938463463374607431768211455)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 42)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 340282366920938463463374607431768211455) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(112, 340282366920938463463374607431768211455))), shl(112, and(__pf_packed_value, 340282366920938463463374607431768211455))))
      }
      if iszero(eq(and(shr(112, sload(0)), 340282366920938463463374607431768211455), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 42)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      __pf_result := and(shr(112, sload(0)), 340282366920938463463374607431768211455)
    }
    function f_EvmPackedStorageProbe_packed_slot2_lifecycle() -> __pf_result {
      {
        let __pf_packed_value := 97433442511412352346923430580824580583949948245
        if gt(__pf_packed_value, 1461501637330902918203684832716283019655932542975) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(__pf_packed_value, 1461501637330902918203684832716283019655932542975))))
      }
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 255))), shl(160, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(160, sload(1)), 255), 1)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 255))), shl(160, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(160, sload(1)), 255), 0)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(160, 255))), shl(160, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(160, sload(1)), 255), 1)) {
        revert(0, 0)
      }
      __pf_result := and(shr(160, sload(1)), 255)
    }
    function f_EvmPackedStorageProbe_packed_slot3_lifecycle() -> __pf_result {
      {
        let __pf_packed_value := 500000
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(1, or(and(sload(1), not(shl(168, 18446744073709551615))), shl(168, and(__pf_packed_value, 18446744073709551615))))
      }
      {
        let __pf_packed_value := 7777
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(0, 4294967295))), shl(0, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := 99
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(32, 255))), shl(32, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(40, 255))), shl(40, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(168, sload(1)), 18446744073709551615), 500000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(2)), 4294967295), 7777)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(32, sload(2)), 255), 99)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(40, sload(2)), 255), 1)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := 1
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(2, or(and(sload(2), not(shl(32, 255))), shl(32, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(32, sload(2)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(168, sload(1)), 18446744073709551615), 500000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(2)), 4294967295), 7777)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(40, sload(2)), 255), 1)) {
        revert(0, 0)
      }
      __pf_result := and(shr(168, sload(1)), 18446744073709551615)
    }
    function f_EvmPackedStorageProbe_packed_assign_op() -> __pf_result {
      {
        let __pf_packed_value := 10
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(and(shr(8, sload(0)), 255), 255), __pf_checked_width(5, 255)), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 15)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_mul(__pf_checked_width(and(shr(8, sload(0)), 255), 255), __pf_checked_width(2, 255)), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 30)) {
        revert(0, 0)
      }
      {
        let __pf_packed_value := 42
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(and(shr(16, sload(0)), 4294967295), 4294967295), __pf_checked_width(8, 4294967295)), 4294967295)
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      if iszero(eq(and(shr(16, sload(0)), 4294967295), 50)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 30)) {
        revert(0, 0)
      }
      __pf_result := and(shr(8, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_assign_op_wraps() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(and(add(255, 1), 255), 255))))
      if iszero(eq(and(shr(8, sload(0)), 255), 0)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 0)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(16, sload(0)), 4294967295), 305419896)) {
        revert(0, 0)
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_nested_checked_overflow_reverts() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_sub(__pf_checked_width(__pf_checked_width(__pf_checked_add(__pf_checked_width(255, 255), __pf_checked_width(1, 255)), 255), 255), __pf_checked_width(1, 255)), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_mixed_overflow_reverts() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := and(sub(__pf_checked_width(__pf_checked_add(__pf_checked_width(255, 255), __pf_checked_width(1, 255)), 255), 256), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_nested_wrapping_preserves_neighbors() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(and(sub(and(add(255, 1), 255), 1), 255), 255))))
      if iszero(eq(and(shr(8, sload(0)), 255), 255)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 0)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(16, sload(0)), 4294967295), 305419896)) {
        revert(0, 0)
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_checked_mul_zero_rhs_succeeds() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_mul(__pf_checked_width(7, 255), __pf_checked_width(0, 255)), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      if iszero(eq(and(shr(8, sload(0)), 255), 0)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(0, sload(0)), 255), 0)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(16, sload(0)), 4294967295), 305419896)) {
        revert(0, 0)
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_assign_op_overflow_reverts() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 255
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(and(shr(8, sload(0)), 255), 255), __pf_checked_width(1, 255)), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_checked_write_overflow_reverts() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := __pf_checked_width(__pf_checked_add(__pf_checked_width(255, 255), __pf_checked_width(1, 255)), 255)
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_checked_literal_write_overflow_reverts() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      {
        let __pf_packed_value := 256
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_checked_local_write_overflow_reverts() -> __pf_result {
      {
        let __pf_packed_value := 0
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 255))), shl(0, and(__pf_packed_value, 255))))
      }
      {
        let __pf_packed_value := 305419896
        if gt(__pf_packed_value, 4294967295) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(16, 4294967295))), shl(16, and(__pf_packed_value, 4294967295))))
      }
      let candidate := 256
      {
        let __pf_packed_value := candidate
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(0, sload(0)), 255)
    }
    function f_EvmPackedStorageProbe_packed_checked_write_param(candidate) -> __pf_result {
      {
        let __pf_packed_value := candidate
        if gt(__pf_packed_value, 255) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(8, 255))), shl(8, and(__pf_packed_value, 255))))
      }
      __pf_result := and(shr(8, sload(0)), 255)
    }
    function __pf_checked_width(value, maxValue) -> result {
      if gt(value, maxValue) {
        revert(0, 0)
      }
      result := value
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
      if or(iszero(a), iszero(b)) {
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
