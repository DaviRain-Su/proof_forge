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
    default {
      revert(0, 0)
    }
    function f_EvmPackedStorageProbe_packed_slot0_lifecycle() -> result {
      sstore(0, or(and(sload(0), not(shl(248, 255))), shl(248, 1)))
      sstore(0, or(and(sload(0), not(shl(240, 255))), shl(240, 200)))
      sstore(0, or(and(sload(0), not(shl(208, 4294967295))), shl(208, 1000)))
      sstore(0, or(and(sload(0), not(shl(144, 18446744073709551615))), shl(144, 99999)))
      if iszero(eq(and(shr(248, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(240, sload(0)), 255), 200)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(208, sload(0)), 4294967295), 1000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(144, sload(0)), 18446744073709551615), 99999)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(240, 255))), shl(240, 42)))
      if iszero(eq(and(shr(240, sload(0)), 255), 42)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(248, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(208, sload(0)), 4294967295), 1000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(144, sload(0)), 18446744073709551615), 99999)) {
        revert(0, 0)
      }
      result := and(shr(144, sload(0)), 18446744073709551615)
    }
    function f_EvmPackedStorageProbe_packed_slot1_lifecycle() -> result {
      sstore(0, or(and(sload(0), not(shl(248, 255))), shl(248, 1)))
      sstore(0, or(and(sload(0), not(shl(240, 255))), shl(240, 42)))
      sstore(0, or(and(sload(0), not(shl(16, 340282366920938463463374607431768211455))), shl(16, 340282366920938463463374607431768211455)))
      if iszero(eq(and(shr(16, sload(0)), 340282366920938463463374607431768211455), 340282366920938463463374607431768211455)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(248, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(240, sload(0)), 255), 42)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(16, 340282366920938463463374607431768211455))), shl(16, 1)))
      if iszero(eq(and(shr(16, sload(0)), 340282366920938463463374607431768211455), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(240, sload(0)), 255), 42)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(248, sload(0)), 255), 1)) {
        revert(0, 0)
      }
      result := and(shr(16, sload(0)), 340282366920938463463374607431768211455)
    }
    function f_EvmPackedStorageProbe_packed_slot2_lifecycle() -> result {
      sstore(1, or(and(sload(1), not(shl(96, 1461501637330902918203684832716283019655932542975))), shl(96, 97433442511412352346923430580824580583949948245)))
      sstore(1, or(and(sload(1), not(shl(88, 255))), shl(88, 1)))
      if iszero(eq(and(shr(88, sload(1)), 255), 1)) {
        revert(0, 0)
      }
      sstore(1, or(and(sload(1), not(shl(88, 255))), shl(88, 0)))
      if iszero(eq(and(shr(88, sload(1)), 255), 0)) {
        revert(0, 0)
      }
      sstore(1, or(and(sload(1), not(shl(88, 255))), shl(88, 1)))
      if iszero(eq(and(shr(88, sload(1)), 255), 1)) {
        revert(0, 0)
      }
      result := and(shr(88, sload(1)), 255)
    }
    function f_EvmPackedStorageProbe_packed_slot3_lifecycle() -> result {
      sstore(1, or(and(sload(1), not(shl(24, 18446744073709551615))), shl(24, 500000)))
      sstore(2, or(and(sload(2), not(shl(224, 4294967295))), shl(224, 7777)))
      sstore(2, or(and(sload(2), not(shl(216, 255))), shl(216, 99)))
      sstore(2, or(and(sload(2), not(shl(208, 255))), shl(208, 1)))
      if iszero(eq(and(shr(24, sload(1)), 18446744073709551615), 500000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(224, sload(2)), 4294967295), 7777)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(216, sload(2)), 255), 99)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(208, sload(2)), 255), 1)) {
        revert(0, 0)
      }
      sstore(2, or(and(sload(2), not(shl(216, 255))), shl(216, 1)))
      if iszero(eq(and(shr(216, sload(2)), 255), 1)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(24, sload(1)), 18446744073709551615), 500000)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(224, sload(2)), 4294967295), 7777)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(208, sload(2)), 255), 1)) {
        revert(0, 0)
      }
      result := and(shr(24, sload(1)), 18446744073709551615)
    }
    function f_EvmPackedStorageProbe_packed_assign_op() -> result {
      sstore(0, or(and(sload(0), not(shl(240, 255))), shl(240, 10)))
      sstore(0, or(and(sload(0), not(shl(240, 255))), shl(240, __pf_checked_add(and(shr(240, sload(0)), 255), 5))))
      if iszero(eq(and(shr(240, sload(0)), 255), 15)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(240, 255))), shl(240, __pf_checked_mul(and(shr(240, sload(0)), 255), 2))))
      if iszero(eq(and(shr(240, sload(0)), 255), 30)) {
        revert(0, 0)
      }
      sstore(0, or(and(sload(0), not(shl(208, 4294967295))), shl(208, 42)))
      sstore(0, or(and(sload(0), not(shl(208, 4294967295))), shl(208, __pf_checked_add(and(shr(208, sload(0)), 4294967295), 8))))
      if iszero(eq(and(shr(208, sload(0)), 4294967295), 50)) {
        revert(0, 0)
      }
      if iszero(eq(and(shr(240, sload(0)), 255), 30)) {
        revert(0, 0)
      }
      result := and(shr(240, sload(0)), 255)
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
