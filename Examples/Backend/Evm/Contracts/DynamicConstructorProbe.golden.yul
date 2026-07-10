object "DynamicConstructorProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x67644d3f {
      let _r := f_DynamicConstructorProbe_getNameLen()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe102d950 {
      let _r := f_DynamicConstructorProbe_getNameHash()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x185b4216 {
      let _r := f_DynamicConstructorProbe_getPayloadLen()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe08ca110 {
      let _r := f_DynamicConstructorProbe_getPayloadHash()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc976d9b0 {
      let _r := f_DynamicConstructorProbe_getAmountCount()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x1c4cbd36 {
      let _r := f_DynamicConstructorProbe_getAmountSum()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_DynamicConstructorProbe_getNameLen() -> __pf_result {
      __pf_result := and(shr(0, sload(0)), 18446744073709551615)
    }
    function f_DynamicConstructorProbe_getNameHash() -> __pf_result {
      __pf_result := sload(1)
    }
    function f_DynamicConstructorProbe_getPayloadLen() -> __pf_result {
      __pf_result := and(shr(0, sload(2)), 18446744073709551615)
    }
    function f_DynamicConstructorProbe_getPayloadHash() -> __pf_result {
      __pf_result := sload(3)
    }
    function f_DynamicConstructorProbe_getAmountCount() -> __pf_result {
      __pf_result := and(shr(0, sload(4)), 18446744073709551615)
    }
    function f_DynamicConstructorProbe_getAmountSum() -> __pf_result {
      __pf_result := and(shr(64, sload(4)), 18446744073709551615)
    }
  }
}
