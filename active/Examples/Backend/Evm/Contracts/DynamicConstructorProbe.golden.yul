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
      let v0 := and(shr(0, sload(0)), 18446744073709551615)
      __pf_result := v0
    }
    function f_DynamicConstructorProbe_getNameHash() -> __pf_result {
      let v1 := sload(1)
      __pf_result := v1
    }
    function f_DynamicConstructorProbe_getPayloadLen() -> __pf_result {
      let v2 := and(shr(0, sload(2)), 18446744073709551615)
      __pf_result := v2
    }
    function f_DynamicConstructorProbe_getPayloadHash() -> __pf_result {
      let v3 := sload(3)
      __pf_result := v3
    }
    function f_DynamicConstructorProbe_getAmountCount() -> __pf_result {
      let v4 := and(shr(0, sload(4)), 18446744073709551615)
      __pf_result := v4
    }
    function f_DynamicConstructorProbe_getAmountSum() -> __pf_result {
      let v5 := and(shr(64, sload(4)), 18446744073709551615)
      __pf_result := v5
    }
  }
}
