object "ArrayExample" {
  code {
    switch shr(224, calldataload(0))
    case 0x8c471d33 {
      let _r := f_ArrayExample_sizeOf3()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xff170768 {
      let _r := f_ArrayExample_getElem()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6d666075 {
      let _r := f_ArrayExample_sumOf3()
      mstore(0, _r)
      return(0, 32)
    }
    case 0xc1ea953e {
      let _r := f_ArrayExample_outOfBounds()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_ArrayExample_sizeOf3() -> __pf_result {
      let v0 := 3
      __pf_result := v0
    }
    function f_ArrayExample_getElem() -> __pf_result {
      let v1 := 3
      let v2 := __proof_forge_memory_array_new(v1)
      let v3 := 10
      let v4 := 0
      if iszero(lt(v4, mload(v2))) {
        revert(0, 0)
      }
      mstore(add(add(v2, 32), mul(v4, 32)), v3)
      let v5 := 20
      let v6 := 1
      if iszero(lt(v6, mload(v2))) {
        revert(0, 0)
      }
      mstore(add(add(v2, 32), mul(v6, 32)), v5)
      let v7 := 30
      let v8 := 2
      if iszero(lt(v8, mload(v2))) {
        revert(0, 0)
      }
      mstore(add(add(v2, 32), mul(v8, 32)), v7)
      let v9 := 1
      let v10 := __proof_forge_memory_array_get(v2, v9)
      __pf_result := v10
    }
    function f_ArrayExample_sumOf3() -> __pf_result {
      let v11 := 3
      let v12 := __proof_forge_memory_array_new(v11)
      let v13 := 10
      let v14 := 0
      if iszero(lt(v14, mload(v12))) {
        revert(0, 0)
      }
      mstore(add(add(v12, 32), mul(v14, 32)), v13)
      let v15 := 20
      let v16 := 1
      if iszero(lt(v16, mload(v12))) {
        revert(0, 0)
      }
      mstore(add(add(v12, 32), mul(v16, 32)), v15)
      let v17 := 30
      let v18 := 2
      if iszero(lt(v18, mload(v12))) {
        revert(0, 0)
      }
      mstore(add(add(v12, 32), mul(v18, 32)), v17)
      let v19 := 0
      let v20 := __proof_forge_memory_array_get(v12, v19)
      let v21 := 1
      let v22 := __proof_forge_memory_array_get(v12, v21)
      let v23 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v20, 18446744073709551615), __pf_checked_width(v22, 18446744073709551615)), 18446744073709551615)
      let v24 := 2
      let v25 := __proof_forge_memory_array_get(v12, v24)
      let v26 := __pf_checked_width(__pf_checked_add(__pf_checked_width(v23, 18446744073709551615), __pf_checked_width(v25, 18446744073709551615)), 18446744073709551615)
      __pf_result := v26
    }
    function f_ArrayExample_outOfBounds() -> __pf_result {
      let v27 := 3
      let v28 := __proof_forge_memory_array_new(v27)
      let v29 := 10
      let v30 := 0
      if iszero(lt(v30, mload(v28))) {
        revert(0, 0)
      }
      mstore(add(add(v28, 32), mul(v30, 32)), v29)
      let v31 := 20
      let v32 := 1
      if iszero(lt(v32, mload(v28))) {
        revert(0, 0)
      }
      mstore(add(add(v28, 32), mul(v32, 32)), v31)
      let v33 := 30
      let v34 := 2
      if iszero(lt(v34, mload(v28))) {
        revert(0, 0)
      }
      mstore(add(add(v28, 32), mul(v34, 32)), v33)
      let v35 := 3
      let v36 := __proof_forge_memory_array_get(v28, v35)
      __pf_result := v36
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
