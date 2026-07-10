object "EvmHashProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x1214538f {
      let _r := f_EvmHashProbe_hash_literal()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x6b28555d {
      let _r := f_EvmHashProbe_hash_pair()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x5d6d411d {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
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
      let _r := f_EvmHashProbe_pack_hash(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      mstore(0, _r)
      return(0, 32)
    }
    case 0x3db89466 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmHashProbe_hash_param(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xa9a07fbf {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_EvmHashProbe_store_hash(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    case 0xe3dfebc3 {
      let _r := f_EvmHashProbe_read_root()
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_EvmHashProbe_hash_literal() -> __pf_result {
      let data := 6277101735386680764516354157049543343084444891548699590660
      __pf_result := __proof_forge_hash_word(data)
    }
    function f_EvmHashProbe_hash_pair() -> __pf_result {
      let left := 6277101735386680764516354157049543343084444891548699590660
      let right := 31385508676933403821220641317563962861421152075426748694536
      __pf_result := __proof_forge_hash_pair(left, right)
    }
    function f_EvmHashProbe_pack_hash(a, b, c, d) -> __pf_result {
      __pf_result := or(shl(192, a), or(shl(128, b), or(shl(64, c), d)))
    }
    function f_EvmHashProbe_hash_param(input) -> __pf_result {
      __pf_result := __proof_forge_hash_word(input)
    }
    function f_EvmHashProbe_store_hash(input) -> __pf_result {
      sstore(0, input)
      __pf_result := sload(0)
    }
    function f_EvmHashProbe_read_root() -> __pf_result {
      __pf_result := sload(0)
    }
    function __proof_forge_hash_word(value) -> result {
      mstore(0, value)
      result := keccak256(0, 32)
    }
    function __proof_forge_hash_pair(left, right) -> result {
      mstore(0, left)
      mstore(32, right)
      result := keccak256(0, 64)
    }
  }
}
