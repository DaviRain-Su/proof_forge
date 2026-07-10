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
    default {
      revert(0, 0)
    }
    function f_ArrayExample_sizeOf3() -> __pf_result {
      __pf_result := 3
    }
    function f_ArrayExample_getElem() -> __pf_result {
      let __proof_forge_array_xs_0 := 10
      let __proof_forge_array_xs_1 := 20
      let __proof_forge_array_xs_2 := 30
      __pf_result := __proof_forge_array_xs_1
    }
    function f_ArrayExample_sumOf3() -> __pf_result {
      let __proof_forge_array_xs_0 := 10
      let __proof_forge_array_xs_1 := 20
      let __proof_forge_array_xs_2 := 30
      __pf_result := __pf_checked_add(__pf_checked_add(__proof_forge_array_xs_0, __proof_forge_array_xs_1), __proof_forge_array_xs_2)
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
