object "EvmCrosscallProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x452d8d77 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x11332f7e {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote1(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6ba69cad {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote2(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x829736d9 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_bool(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xde613df7 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_u32(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x80d00d8c {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_hash(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x465a3244 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_pair(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x11944892 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x6be95a25 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x55444f06 {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_pair_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x48c317af {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_array_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc8169678 {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x41e1d0ee {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_pair_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x03da4ae2 {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_pair_array_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5b6d7258 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3, _r4, _r5, _r6, _r7 := f_EvmCrosscallProbe_call_remote_pair_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      mstore(128, _r4)
      mstore(160, _r5)
      mstore(192, _r6)
      mstore(224, _r7)
      return(0, 256)
    }
    case 0xcc687a87 {
      if lt(calldatasize(), 324) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(196), 1) {
        revert(0, 0)
      }
      if gt(calldataload(228), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(260), 1) {
        revert(0, 0)
      }
      if gt(calldataload(292), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_pair_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196), calldataload(228), calldataload(260), calldataload(292))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xb9808ee5 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_value(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x61a9a998 {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_value_pair_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xddb16e35 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_value_pair(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x188c0b4c {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_value_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x8680eef8 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_value_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x122d46f1 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_value_pair_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x94f5dac2 {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_value_pair_array_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6335f903 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3, _r4, _r5, _r6, _r7 := f_EvmCrosscallProbe_call_remote_value_pair_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      mstore(128, _r4)
      mstore(160, _r5)
      mstore(192, _r6)
      mstore(224, _r7)
      return(0, 256)
    }
    case 0x41cff9e0 {
      if lt(calldatasize(), 324) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(196), 1) {
        revert(0, 0)
      }
      if gt(calldataload(228), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(260), 1) {
        revert(0, 0)
      }
      if gt(calldataload(292), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_value_pair_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196), calldataload(228), calldataload(260), calldataload(292))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6839edc5 {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_value_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5a64728a {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf5582845 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_bool(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x8da932c4 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_u32(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x56a04291 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_hash(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x468aac8f {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_pair_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x4207757f {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_static_pair(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x6fbda09c {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_static_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0x69be52ca {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_static_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0xdf333465 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_static_pair_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x38eef6db {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_pair_array_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xafa00ffe {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3, _r4, _r5, _r6, _r7 := f_EvmCrosscallProbe_call_remote_static_pair_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      mstore(128, _r4)
      mstore(160, _r5)
      mstore(192, _r6)
      mstore(224, _r7)
      return(0, 256)
    }
    case 0x0ff6a624 {
      if lt(calldatasize(), 324) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(196), 1) {
        revert(0, 0)
      }
      if gt(calldataload(228), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(260), 1) {
        revert(0, 0)
      }
      if gt(calldataload(292), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_pair_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196), calldataload(228), calldataload(260), calldataload(292))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x7522a3d0 {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_static_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa778a42a {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x0876d5a7 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_bool(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf2359287 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_u32(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x366ec140 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_hash(calldataload(4), calldataload(36), calldataload(68))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc2b329ae {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_pair_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xae195170 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_delegate_pair(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0xbb45913f {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1 := f_EvmCrosscallProbe_call_remote_delegate_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      return(0, 64)
    }
    case 0xe8e21f22 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_delegate_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x5205a28d {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3 := f_EvmCrosscallProbe_call_remote_delegate_pair_array(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      return(0, 128)
    }
    case 0x388b963b {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_pair_array_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x934bcc50 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      let _r0, _r1, _r2, _r3, _r4, _r5, _r6, _r7 := f_EvmCrosscallProbe_call_remote_delegate_pair_matrix(calldataload(4), calldataload(36))
      mstore(0, _r0)
      mstore(32, _r1)
      mstore(64, _r2)
      mstore(96, _r3)
      mstore(128, _r4)
      mstore(160, _r5)
      mstore(192, _r6)
      mstore(224, _r7)
      return(0, 256)
    }
    case 0x42a94e5e {
      if lt(calldatasize(), 324) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 1) {
        revert(0, 0)
      }
      if gt(calldataload(100), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(132), 1) {
        revert(0, 0)
      }
      if gt(calldataload(164), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(196), 1) {
        revert(0, 0)
      }
      if gt(calldataload(228), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(260), 1) {
        revert(0, 0)
      }
      if gt(calldataload(292), 4294967295) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_pair_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196), calldataload(228), calldataload(260), calldataload(292))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x15637bcf {
      if lt(calldatasize(), 196) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(68), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_call_remote_delegate_matrix_arg(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc9bc2909 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_deploy_create(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x70b22efb {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      let _r := f_EvmCrosscallProbe_deploy_create2(calldataload(4), calldataload(36))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmCrosscallProbe_call_remote(target, method) -> __pf_result {
      __pf_result := __proof_forge_crosscall_0(target, method)
    }
    function f_EvmCrosscallProbe_call_remote1(target, method, x) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1(target, method, x)
    }
    function f_EvmCrosscallProbe_call_remote2(target, method, x, y) -> __pf_result {
      __pf_result := __proof_forge_crosscall_2(target, method, x, y)
    }
    function f_EvmCrosscallProbe_call_remote_bool(target, method, flag) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1_bool(target, method, flag)
    }
    function f_EvmCrosscallProbe_call_remote_u32(target, method, x) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1_u32(target, method, x)
    }
    function f_EvmCrosscallProbe_call_remote_hash(target, method, value) -> __pf_result {
      __pf_result := __proof_forge_crosscall_1_hash(target, method, value)
    }
    function f_EvmCrosscallProbe_call_remote_pair(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_0_abi_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_array(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_0_abi_u64_u64(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_0_abi_u64_u64_u64_u64(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_pair_arg(target, method, flag, small) -> __pf_result {
      let __proof_forge_struct_pair_flag := flag
      let __proof_forge_struct_pair_small := small
      __pf_result := __proof_forge_crosscall_2_bool(target, method, __proof_forge_struct_pair_flag, __proof_forge_struct_pair_small)
    }
    function f_EvmCrosscallProbe_call_remote_array_arg(target, method, x, y) -> __pf_result {
      let __proof_forge_array_values_0 := x
      let __proof_forge_array_values_1 := y
      __pf_result := __proof_forge_crosscall_2(target, method, __proof_forge_array_values_0, __proof_forge_array_values_1)
    }
    function f_EvmCrosscallProbe_call_remote_matrix_arg(target, method, a, b, c, d) -> __pf_result {
      __pf_result := __proof_forge_crosscall_4(target, method, a, b, c, d)
    }
    function f_EvmCrosscallProbe_call_remote_pair_array(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_0_abi_bool_u32_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_pair_array_arg(target, method, flag0, small0, flag1, small1) -> __pf_result {
      let __proof_forge_array_struct_pairs_0_flag := flag0
      let __proof_forge_array_struct_pairs_0_small := small0
      let __proof_forge_array_struct_pairs_1_flag := flag1
      let __proof_forge_array_struct_pairs_1_small := small1
      __pf_result := __proof_forge_crosscall_4(target, method, __proof_forge_array_struct_pairs_0_flag, __proof_forge_array_struct_pairs_0_small, __proof_forge_array_struct_pairs_1_flag, __proof_forge_array_struct_pairs_1_small)
    }
    function f_EvmCrosscallProbe_call_remote_pair_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 := __proof_forge_crosscall_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_pair_matrix_arg(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11) -> __pf_result {
      __pf_result := __proof_forge_crosscall_8(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11)
    }
    function f_EvmCrosscallProbe_call_remote_value(target, method) -> __pf_result {
      __pf_result := __proof_forge_crosscall_value_0(target, method, callvalue())
    }
    function f_EvmCrosscallProbe_call_remote_value_pair_arg(target, method, flag, small) -> __pf_result {
      let __proof_forge_struct_pair_flag := flag
      let __proof_forge_struct_pair_small := small
      __pf_result := __proof_forge_crosscall_value_2(target, method, callvalue(), __proof_forge_struct_pair_flag, __proof_forge_struct_pair_small)
    }
    function f_EvmCrosscallProbe_call_remote_value_pair(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_value_0_abi_bool_u32(target, method, callvalue())
    }
    function f_EvmCrosscallProbe_call_remote_value_array(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_value_0_abi_u64_u64(target, method, callvalue())
    }
    function f_EvmCrosscallProbe_call_remote_value_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_value_0_abi_u64_u64_u64_u64(target, method, callvalue())
    }
    function f_EvmCrosscallProbe_call_remote_value_pair_array(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_value_0_abi_bool_u32_bool_u32(target, method, callvalue())
    }
    function f_EvmCrosscallProbe_call_remote_value_pair_array_arg(target, method, flag0, small0, flag1, small1) -> __pf_result {
      let __proof_forge_array_struct_pairs_0_flag := flag0
      let __proof_forge_array_struct_pairs_0_small := small0
      let __proof_forge_array_struct_pairs_1_flag := flag1
      let __proof_forge_array_struct_pairs_1_small := small1
      __pf_result := __proof_forge_crosscall_value_4(target, method, callvalue(), __proof_forge_array_struct_pairs_0_flag, __proof_forge_array_struct_pairs_0_small, __proof_forge_array_struct_pairs_1_flag, __proof_forge_array_struct_pairs_1_small)
    }
    function f_EvmCrosscallProbe_call_remote_value_pair_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 := __proof_forge_crosscall_value_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, method, callvalue())
    }
    function f_EvmCrosscallProbe_call_remote_value_pair_matrix_arg(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11) -> __pf_result {
      __pf_result := __proof_forge_crosscall_value_8(target, method, callvalue(), flag00, small00, flag01, small01, flag10, small10, flag11, small11)
    }
    function f_EvmCrosscallProbe_call_remote_value_matrix_arg(target, method, a, b, c, d) -> __pf_result {
      __pf_result := __proof_forge_crosscall_value_4(target, method, callvalue(), a, b, c, d)
    }
    function f_EvmCrosscallProbe_call_remote_static(target, method) -> __pf_result {
      __pf_result := __proof_forge_crosscall_static_0(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_static_bool(target, method, flag) -> __pf_result {
      __pf_result := __proof_forge_crosscall_static_1_bool(target, method, flag)
    }
    function f_EvmCrosscallProbe_call_remote_static_u32(target, method, x) -> __pf_result {
      __pf_result := __proof_forge_crosscall_static_1_u32(target, method, x)
    }
    function f_EvmCrosscallProbe_call_remote_static_hash(target, method, value) -> __pf_result {
      __pf_result := __proof_forge_crosscall_static_1_hash(target, method, value)
    }
    function f_EvmCrosscallProbe_call_remote_static_pair_arg(target, method, flag, small) -> __pf_result {
      let __proof_forge_struct_pair_flag := flag
      let __proof_forge_struct_pair_small := small
      __pf_result := __proof_forge_crosscall_static_2_u32(target, method, __proof_forge_struct_pair_flag, __proof_forge_struct_pair_small)
    }
    function f_EvmCrosscallProbe_call_remote_static_pair(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_static_0_abi_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_static_array(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_static_0_abi_u64_u64(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_static_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_static_0_abi_u64_u64_u64_u64(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_static_pair_array(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_static_0_abi_bool_u32_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_static_pair_array_arg(target, method, flag0, small0, flag1, small1) -> __pf_result {
      let __proof_forge_array_struct_pairs_0_flag := flag0
      let __proof_forge_array_struct_pairs_0_small := small0
      let __proof_forge_array_struct_pairs_1_flag := flag1
      let __proof_forge_array_struct_pairs_1_small := small1
      __pf_result := __proof_forge_crosscall_static_4(target, method, __proof_forge_array_struct_pairs_0_flag, __proof_forge_array_struct_pairs_0_small, __proof_forge_array_struct_pairs_1_flag, __proof_forge_array_struct_pairs_1_small)
    }
    function f_EvmCrosscallProbe_call_remote_static_pair_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 := __proof_forge_crosscall_static_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_static_pair_matrix_arg(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11) -> __pf_result {
      __pf_result := __proof_forge_crosscall_static_8(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11)
    }
    function f_EvmCrosscallProbe_call_remote_static_matrix_arg(target, method, a, b, c, d) -> __pf_result {
      __pf_result := __proof_forge_crosscall_static_4(target, method, a, b, c, d)
    }
    function f_EvmCrosscallProbe_call_remote_delegate(target, method) -> __pf_result {
      __pf_result := __proof_forge_crosscall_delegate_0(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_bool(target, method, flag) -> __pf_result {
      __pf_result := __proof_forge_crosscall_delegate_1_bool(target, method, flag)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_u32(target, method, x) -> __pf_result {
      __pf_result := __proof_forge_crosscall_delegate_1_u32(target, method, x)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_hash(target, method, value) -> __pf_result {
      __pf_result := __proof_forge_crosscall_delegate_1_hash(target, method, value)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_pair_arg(target, method, flag, small) -> __pf_result {
      let __proof_forge_struct_pair_flag := flag
      let __proof_forge_struct_pair_small := small
      __pf_result := __proof_forge_crosscall_delegate_2_u32(target, method, __proof_forge_struct_pair_flag, __proof_forge_struct_pair_small)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_pair(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_delegate_0_abi_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_array(target, method) -> __pf_return_0, __pf_return_1 {
      __pf_return_0, __pf_return_1 := __proof_forge_crosscall_delegate_0_abi_u64_u64(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_delegate_0_abi_u64_u64_u64_u64(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_pair_array(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3 := __proof_forge_crosscall_delegate_0_abi_bool_u32_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_pair_array_arg(target, method, flag0, small0, flag1, small1) -> __pf_result {
      let __proof_forge_array_struct_pairs_0_flag := flag0
      let __proof_forge_array_struct_pairs_0_small := small0
      let __proof_forge_array_struct_pairs_1_flag := flag1
      let __proof_forge_array_struct_pairs_1_small := small1
      __pf_result := __proof_forge_crosscall_delegate_4(target, method, __proof_forge_array_struct_pairs_0_flag, __proof_forge_array_struct_pairs_0_small, __proof_forge_array_struct_pairs_1_flag, __proof_forge_array_struct_pairs_1_small)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_pair_matrix(target, method) -> __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 {
      __pf_return_0, __pf_return_1, __pf_return_2, __pf_return_3, __pf_return_4, __pf_return_5, __pf_return_6, __pf_return_7 := __proof_forge_crosscall_delegate_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, method)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_pair_matrix_arg(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11) -> __pf_result {
      __pf_result := __proof_forge_crosscall_delegate_8(target, method, flag00, small00, flag01, small01, flag10, small10, flag11, small11)
    }
    function f_EvmCrosscallProbe_call_remote_delegate_matrix_arg(target, method, a, b, c, d) -> __pf_result {
      __pf_result := __proof_forge_crosscall_delegate_4(target, method, a, b, c, d)
    }
    function f_EvmCrosscallProbe_deploy_create(value) -> __pf_result {
      __pf_result := __proof_forge_create_69602a60005260206000f3600052600a6016f3(value)
    }
    function f_EvmCrosscallProbe_deploy_create2(value, salt) -> __pf_result {
      __pf_result := __proof_forge_create2_69602a60005260206000f3600052600a6016f3(value, salt)
    }
    function __proof_forge_crosscall_0(target, selector) -> result {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_1(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := call(gas(), target, 0, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_2(target, selector, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := call(gas(), target, 0, 0, 68, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_1_bool(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := call(gas(), target, 0, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 1) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_1_u32(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := call(gas(), target, 0, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_1_hash(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := call(gas(), target, 0, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_0_abi_bool_u32(target, selector) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_0_abi_u64_u64(target, selector) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
    }
    function __proof_forge_crosscall_0_abi_u64_u64_u64_u64(target, selector) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
    }
    function __proof_forge_crosscall_2_bool(target, selector, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := call(gas(), target, 0, 0, 68, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 1) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_4(target, selector, arg0, arg1, arg2, arg3) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      let _success := call(gas(), target, 0, 0, 132, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_0_abi_bool_u32_bool_u32(target, selector) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, selector) -> result0, result1, result2, result3, result4, result5, result6, result7 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, 0, 0, 4, 0, 256)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 256) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 256)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      result4 := mload(128)
      result5 := mload(160)
      result6 := mload(192)
      result7 := mload(224)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
      if gt(result4, 1) {
        revert(0, 0)
      }
      if gt(result5, 4294967295) {
        revert(0, 0)
      }
      if gt(result6, 1) {
        revert(0, 0)
      }
      if gt(result7, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_8(target, selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      mstore(132, arg4)
      mstore(164, arg5)
      mstore(196, arg6)
      mstore(228, arg7)
      let _success := call(gas(), target, 0, 0, 260, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_value_0(target, selector, call_value) -> result {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, call_value, 0, 4, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_value_2(target, selector, call_value, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := call(gas(), target, call_value, 0, 68, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_value_0_abi_bool_u32(target, selector, call_value) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, call_value, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_value_0_abi_u64_u64(target, selector, call_value) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, call_value, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
    }
    function __proof_forge_crosscall_value_0_abi_u64_u64_u64_u64(target, selector, call_value) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, call_value, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
    }
    function __proof_forge_crosscall_value_0_abi_bool_u32_bool_u32(target, selector, call_value) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, call_value, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_value_4(target, selector, call_value, arg0, arg1, arg2, arg3) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      let _success := call(gas(), target, call_value, 0, 132, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_value_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, selector, call_value) -> result0, result1, result2, result3, result4, result5, result6, result7 {
      mstore(0, shl(224, selector))
      let _success := call(gas(), target, call_value, 0, 4, 0, 256)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 256) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 256)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      result4 := mload(128)
      result5 := mload(160)
      result6 := mload(192)
      result7 := mload(224)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
      if gt(result4, 1) {
        revert(0, 0)
      }
      if gt(result5, 4294967295) {
        revert(0, 0)
      }
      if gt(result6, 1) {
        revert(0, 0)
      }
      if gt(result7, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_value_8(target, selector, call_value, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      mstore(132, arg4)
      mstore(164, arg5)
      mstore(196, arg6)
      mstore(228, arg7)
      let _success := call(gas(), target, call_value, 0, 260, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_static_0(target, selector) -> result {
      mstore(0, shl(224, selector))
      let _success := staticcall(gas(), target, 0, 4, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_static_1_bool(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := staticcall(gas(), target, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 1) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_static_1_u32(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := staticcall(gas(), target, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_static_1_hash(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := staticcall(gas(), target, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_static_2_u32(target, selector, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := staticcall(gas(), target, 0, 68, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_static_0_abi_bool_u32(target, selector) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := staticcall(gas(), target, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_static_0_abi_u64_u64(target, selector) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := staticcall(gas(), target, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
    }
    function __proof_forge_crosscall_static_0_abi_u64_u64_u64_u64(target, selector) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := staticcall(gas(), target, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
    }
    function __proof_forge_crosscall_static_0_abi_bool_u32_bool_u32(target, selector) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := staticcall(gas(), target, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_static_4(target, selector, arg0, arg1, arg2, arg3) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      let _success := staticcall(gas(), target, 0, 132, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_static_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, selector) -> result0, result1, result2, result3, result4, result5, result6, result7 {
      mstore(0, shl(224, selector))
      let _success := staticcall(gas(), target, 0, 4, 0, 256)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 256) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 256)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      result4 := mload(128)
      result5 := mload(160)
      result6 := mload(192)
      result7 := mload(224)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
      if gt(result4, 1) {
        revert(0, 0)
      }
      if gt(result5, 4294967295) {
        revert(0, 0)
      }
      if gt(result6, 1) {
        revert(0, 0)
      }
      if gt(result7, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_static_8(target, selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      mstore(132, arg4)
      mstore(164, arg5)
      mstore(196, arg6)
      mstore(228, arg7)
      let _success := staticcall(gas(), target, 0, 260, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_delegate_0(target, selector) -> result {
      mstore(0, shl(224, selector))
      let _success := delegatecall(gas(), target, 0, 4, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_delegate_1_bool(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := delegatecall(gas(), target, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 1) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_delegate_1_u32(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := delegatecall(gas(), target, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_delegate_1_hash(target, selector, arg0) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      let _success := delegatecall(gas(), target, 0, 36, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_delegate_2_u32(target, selector, arg0, arg1) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      let _success := delegatecall(gas(), target, 0, 68, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
      if gt(result, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_delegate_0_abi_bool_u32(target, selector) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := delegatecall(gas(), target, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_delegate_0_abi_u64_u64(target, selector) -> result0, result1 {
      mstore(0, shl(224, selector))
      let _success := delegatecall(gas(), target, 0, 4, 0, 64)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 64) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 64)
      result0 := mload(0)
      result1 := mload(32)
    }
    function __proof_forge_crosscall_delegate_0_abi_u64_u64_u64_u64(target, selector) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := delegatecall(gas(), target, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
    }
    function __proof_forge_crosscall_delegate_0_abi_bool_u32_bool_u32(target, selector) -> result0, result1, result2, result3 {
      mstore(0, shl(224, selector))
      let _success := delegatecall(gas(), target, 0, 4, 0, 128)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 128) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 128)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_delegate_4(target, selector, arg0, arg1, arg2, arg3) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      let _success := delegatecall(gas(), target, 0, 132, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_crosscall_delegate_0_abi_bool_u32_bool_u32_bool_u32_bool_u32(target, selector) -> result0, result1, result2, result3, result4, result5, result6, result7 {
      mstore(0, shl(224, selector))
      let _success := delegatecall(gas(), target, 0, 4, 0, 256)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 256) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 256)
      result0 := mload(0)
      result1 := mload(32)
      result2 := mload(64)
      result3 := mload(96)
      result4 := mload(128)
      result5 := mload(160)
      result6 := mload(192)
      result7 := mload(224)
      if gt(result0, 1) {
        revert(0, 0)
      }
      if gt(result1, 4294967295) {
        revert(0, 0)
      }
      if gt(result2, 1) {
        revert(0, 0)
      }
      if gt(result3, 4294967295) {
        revert(0, 0)
      }
      if gt(result4, 1) {
        revert(0, 0)
      }
      if gt(result5, 4294967295) {
        revert(0, 0)
      }
      if gt(result6, 1) {
        revert(0, 0)
      }
      if gt(result7, 4294967295) {
        revert(0, 0)
      }
    }
    function __proof_forge_crosscall_delegate_8(target, selector, arg0, arg1, arg2, arg3, arg4, arg5, arg6, arg7) -> result {
      mstore(0, shl(224, selector))
      mstore(4, arg0)
      mstore(36, arg1)
      mstore(68, arg2)
      mstore(100, arg3)
      mstore(132, arg4)
      mstore(164, arg5)
      mstore(196, arg6)
      mstore(228, arg7)
      let _success := delegatecall(gas(), target, 0, 260, 0, 32)
      if iszero(_success) {
        revert(0, 0)
      }
      if lt(returndatasize(), 32) {
        revert(0, 0)
      }
      returndatacopy(0, 0, 32)
      result := mload(0)
    }
    function __proof_forge_create_69602a60005260206000f3600052600a6016f3(call_value) -> result {
      mstore(0, 0x69602a60005260206000f3600052600a6016f300000000000000000000000000)
      result := create(call_value, 0, 19)
      if iszero(result) {
        revert(0, 0)
      }
    }
    function __proof_forge_create2_69602a60005260206000f3600052600a6016f3(call_value, salt) -> result {
      mstore(0, 0x69602a60005260206000f3600052600a6016f300000000000000000000000000)
      result := create2(call_value, 0, 19, salt)
      if iszero(result) {
        revert(0, 0)
      }
    }
  }
}
