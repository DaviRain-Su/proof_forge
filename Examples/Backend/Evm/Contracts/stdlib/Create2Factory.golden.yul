object "Create2Factory" {
  code {
    switch shr(224, calldataload(0))
    case 0x9e67133d {
      let _r := f_Create2Factory_templateInitCodeHash()
      mstore(0, _r)
      return(0, 32)
    }
    case 0x2b85ba38 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      let _r := f_Create2Factory_deploy(calldataload(4))
      mstore(0, _r)
      return(0, 32)
    }
    default {
      revert(0, 0)
    }
    function f_Create2Factory_templateInitCodeHash() -> __pf_result {
      __pf_result := 68818659148533468236157942673803971936521608035699249785660344515652537758923
    }
    function f_Create2Factory_deploy(salt) -> __pf_result {
      let deployed := __proof_forge_create2_69602a60005260206000f3600052600a6016f3(callvalue(), salt)
      {
        mstore(0, 30936501176209415639598829821747794836005707844039030221877151186564641980416)
        let __pf_event_topic0 := keccak256(0, 25)
        let __pf_event_indexed_topic0 := deployed
        let __pf_event_indexed_topic1 := salt
        log3(0, 0, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
      __pf_result := deployed
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
