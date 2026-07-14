object "Ownable" {
  code {
    switch shr(224, calldataload(0))
    case 0xe1c7392a {
      f_Ownable_init()
      return(0, 0)
    }
    case 0x8da5cb5b {
      let _r := f_Ownable_owner()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xf2fde38b {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1461501637330902918203684832716283019655932542975) {
        revert(0, 0)
      }
      f_Ownable_transferOwnership(calldataload(4))
      return(0, 0)
    }
    case 0x715018a6 {
      f_Ownable_renounceOwnership()
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_Ownable_init() {
      let v0 := and(shr(160, sload(0)), 18446744073709551615)
      let v1 := 0
      let v2 := eq(v0, v1)
      if iszero(v2) {
        revert(0, 0)
      }
      let v3 := 1
      {
        let __pf_packed_value := v3
        if gt(__pf_packed_value, 18446744073709551615) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(160, 18446744073709551615))), shl(160, and(__pf_packed_value, 18446744073709551615))))
      }
      let v4 := caller()
      let v5 := 0
      {
        mstore(0, 35943731765892510050589367655672536643328569156915554301577312365719383532644)
        mstore(32, 51742913097576536687416843347501904736222912990880608286633430183482035798016)
        let __pf_event_topic0 := keccak256(0, 37)
        let __pf_event_indexed_topic0 := v5
        let __pf_event_indexed_topic1 := v4
        log3(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      {
        let __pf_packed_value := v4
        if gt(__pf_packed_value, 1461501637330902918203684832716283019655932542975) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(__pf_packed_value, 1461501637330902918203684832716283019655932542975))))
      }
    }
    function f_Ownable_owner() -> __pf_result {
      let v6 := and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975)
      __pf_result := v6
    }
    function f_Ownable_transferOwnership(newOwner) {
      let v8 := and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975)
      let v9 := caller()
      let v10 := eq(v8, v9)
      if iszero(v10) {
        revert(0, 0)
      }
      let v11 := 0
      let v12 := iszero(eq(newOwner, v11))
      if iszero(v12) {
        revert(0, 0)
      }
      let v13 := and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975)
      {
        mstore(0, 35943731765892510050589367655672536643328569156915554301577312365719383532644)
        mstore(32, 51742913097576536687416843347501904736222912990880608286633430183482035798016)
        let __pf_event_topic0 := keccak256(0, 37)
        let __pf_event_indexed_topic0 := v13
        let __pf_event_indexed_topic1 := newOwner
        log3(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      {
        let __pf_packed_value := newOwner
        if gt(__pf_packed_value, 1461501637330902918203684832716283019655932542975) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(__pf_packed_value, 1461501637330902918203684832716283019655932542975))))
      }
    }
    function f_Ownable_renounceOwnership() {
      let v14 := and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975)
      let v15 := caller()
      let v16 := eq(v14, v15)
      if iszero(v16) {
        revert(0, 0)
      }
      let v17 := and(shr(0, sload(0)), 1461501637330902918203684832716283019655932542975)
      let v18 := 0
      {
        mstore(0, 35943731765892510050589367655672536643328569156915554301577312365719383532644)
        mstore(32, 51742913097576536687416843347501904736222912990880608286633430183482035798016)
        let __pf_event_topic0 := keccak256(0, 37)
        let __pf_event_indexed_topic0 := v17
        let __pf_event_indexed_topic1 := v18
        log3(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      let v19 := 0
      {
        let __pf_packed_value := v19
        if gt(__pf_packed_value, 1461501637330902918203684832716283019655932542975) {
          revert(0, 0)
        }
        sstore(0, or(and(sload(0), not(shl(0, 1461501637330902918203684832716283019655932542975))), shl(0, and(__pf_packed_value, 1461501637330902918203684832716283019655932542975))))
      }
    }
  }
}
