object "EventProbe" {
  code {
    switch shr(224, calldataload(0))
    case 0x2ae8cae3 {
      if lt(calldatasize(), 36) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_value_event(calldataload(4))
      return(0, 0)
    }
    case 0x989413a3 {
      if lt(calldatasize(), 100) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      if gt(calldataload(36), 4294967295) {
        revert(0, 0)
      }
      f_EventProbe_emit_typed_scalar_event(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xbc07d04f {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_indexed_event(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0xb94b71db {
      if lt(calldatasize(), 132) {
        revert(0, 0)
      }
      if gt(calldataload(4), 1) {
        revert(0, 0)
      }
      if gt(calldataload(36), 4294967295) {
        revert(0, 0)
      }
      if gt(calldataload(100), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_indexed_typed_scalar_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0x2d00700c {
      if lt(calldatasize(), 100) {
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
      f_EventProbe_emit_two_indexed_event(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xe7d142d1 {
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
      f_EventProbe_emit_three_indexed_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0x35361bda {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_pair_event(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x65123829 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_storage_pair_event(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x99eb21de {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_storage_array_event(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x393f7138 {
      if lt(calldatasize(), 68) {
        revert(0, 0)
      }
      if gt(calldataload(4), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(36), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_array_event(calldataload(4), calldataload(36))
      return(0, 0)
    }
    case 0x85611e74 {
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
      f_EventProbe_emit_pair_array_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0x765f1e45 {
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
      f_EventProbe_emit_matrix_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0x315aac0a {
      if lt(calldatasize(), 260) {
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
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(196), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(228), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_pair_matrix_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196), calldataload(228))
      return(0, 0)
    }
    case 0xf31d3375 {
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
      f_EventProbe_emit_storage_pair_array_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100))
      return(0, 0)
    }
    case 0xe027f054 {
      if lt(calldatasize(), 100) {
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
      f_EventProbe_emit_indexed_pair_event(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xf4a27402 {
      if lt(calldatasize(), 100) {
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
      f_EventProbe_emit_indexed_storage_pair_event(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x42a8056e {
      if lt(calldatasize(), 100) {
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
      f_EventProbe_emit_indexed_storage_array_event(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0xb7de5dd7 {
      if lt(calldatasize(), 100) {
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
      f_EventProbe_emit_indexed_array_event(calldataload(4), calldataload(36), calldataload(68))
      return(0, 0)
    }
    case 0x45440e6c {
      if lt(calldatasize(), 164) {
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
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_indexed_storage_pair_array_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132))
      return(0, 0)
    }
    case 0xc1375f82 {
      if lt(calldatasize(), 164) {
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
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_indexed_pair_array_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132))
      return(0, 0)
    }
    case 0x6a843f41 {
      if lt(calldatasize(), 164) {
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
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_indexed_matrix_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132))
      return(0, 0)
    }
    case 0xd1b4d456 {
      if lt(calldatasize(), 292) {
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
      if gt(calldataload(132), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(164), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(196), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(228), 18446744073709551615) {
        revert(0, 0)
      }
      if gt(calldataload(260), 18446744073709551615) {
        revert(0, 0)
      }
      f_EventProbe_emit_indexed_pair_matrix_event(calldataload(4), calldataload(36), calldataload(68), calldataload(100), calldataload(132), calldataload(164), calldataload(196), calldataload(228), calldataload(260))
      return(0, 0)
    }
    default {
      revert(0, 0)
    }
    function f_EventProbe_emit_value_event(value) {
      {
        mstore(0, 39071037697028742785112238941195820511403663684262765307557390900479590924288)
        let __pf_event_topic0 := keccak256(0, 18)
        mstore(0, value)
        log1(0, 32, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_typed_scalar_event(flag, count, root) {
      {
        mstore(0, 38208843504943548137420489878118617993276775205112769762916566927252878686580)
        mstore(32, 45887138460738243058303812952308706388865680699246200689541685559113304506368)
        let __pf_event_topic0 := keccak256(0, 37)
        mstore(0, flag)
        mstore(32, count)
        mstore(64, root)
        log1(0, 96, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_indexed_event(user, value) {
      {
        mstore(0, 33213884033972546292423408501581198898028345886020401664275624245368457265152)
        let __pf_event_topic0 := keccak256(0, 27)
        let __pf_event_indexed_topic0 := user
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_typed_scalar_event(flag, count, root, value) {
      {
        mstore(0, 33213884033972546280458060454858431511599761331471597493913756931208338615394)
        mstore(32, 54935509120255985269012947118551815935645971419818835731411993511806399152128)
        let __pf_event_topic0 := keccak256(0, 46)
        let __pf_event_indexed_topic0 := flag
        let __pf_event_indexed_topic1 := count
        let __pf_event_indexed_topic2 := root
        mstore(0, value)
        log4(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_EventProbe_emit_two_indexed_event(first, second, value) {
      {
        mstore(0, 33213884033972546280408919200171753220858272908402386486733397864180425698421)
        mstore(32, 47688004342275046375464606958974035449868406404978144265184762184116216004608)
        let __pf_event_topic0 := keccak256(0, 38)
        let __pf_event_indexed_topic0 := first
        let __pf_event_indexed_topic1 := second
        mstore(0, value)
        log3(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1)
      }
    }
    function f_EventProbe_emit_three_indexed_event(first, second, third, value) {
      {
        mstore(0, 33213884033972546280041413231164102947689571766429842866628026777411188438580)
        mstore(32, 20109214105441862435681744661945841593607557982736579915843921330113915912192)
        let __pf_event_topic0 := keccak256(0, 47)
        let __pf_event_indexed_topic0 := first
        let __pf_event_indexed_topic1 := second
        let __pf_event_indexed_topic2 := third
        mstore(0, value)
        log4(0, 32, __pf_event_topic0, __pf_event_indexed_topic0, __pf_event_indexed_topic1, __pf_event_indexed_topic2)
      }
    }
    function f_EventProbe_emit_pair_event(left, right) {
      let __proof_forge_struct_pair_left := left
      let __proof_forge_struct_pair_right := right
      {
        mstore(0, 36357139816060400917849370525218542085058024887522720989284665839002891321344)
        let __pf_event_topic0 := keccak256(0, 26)
        mstore(0, __proof_forge_struct_pair_left)
        mstore(32, __proof_forge_struct_pair_right)
        log1(0, 64, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_storage_pair_event(left, right) {
      {
        let __proof_forge_assign_storage_struct_storedPair_left := left
        let __proof_forge_assign_storage_struct_storedPair_right := right
        sstore(1, __proof_forge_assign_storage_struct_storedPair_left)
        sstore(2, __proof_forge_assign_storage_struct_storedPair_right)
      }
      {
        mstore(0, 37747689869461643464471119645442085481810897222302362980564207035825813599273)
        mstore(32, 18544826791913921923306290567797672742125270981606496584444378688767337168896)
        let __pf_event_topic0 := keccak256(0, 33)
        mstore(0, sload(1))
        mstore(32, sload(2))
        log1(0, 64, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_storage_array_event(left, right) {
      sstore(__proof_forge_array_slot(3, 2, 0), left)
      sstore(__proof_forge_array_slot(3, 2, 1), right)
      {
        mstore(0, 37747689869461643370732288145762730112294565184148027269019221409560751243264)
        let __pf_event_topic0 := keccak256(0, 28)
        mstore(0, sload(__proof_forge_array_slot(3, 2, 0)))
        mstore(32, sload(__proof_forge_array_slot(3, 2, 1)))
        log1(0, 64, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_array_event(left, right) {
      let __proof_forge_array_values_0 := left
      let __proof_forge_array_values_1 := right
      {
        mstore(0, 29602545150266774396616420083867752660517947997539484713696773112108127617024)
        let __pf_event_topic0 := keccak256(0, 21)
        mstore(0, __proof_forge_array_values_0)
        mstore(32, __proof_forge_array_values_1)
        log1(0, 64, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_pair_array_event(a, b, c, d) {
      let __proof_forge_array_struct_pairs_0_left := a
      let __proof_forge_array_struct_pairs_0_right := b
      let __proof_forge_array_struct_pairs_1_left := c
      let __proof_forge_array_struct_pairs_1_right := d
      {
        mstore(0, 36357139815637527055335479830577877812296532846634599718780626255005467892530)
        mstore(32, 42137535647899687876232062095217863683969663456586636532242186294627689037824)
        let __pf_event_topic0 := keccak256(0, 34)
        mstore(0, __proof_forge_array_struct_pairs_0_left)
        mstore(32, __proof_forge_array_struct_pairs_0_right)
        mstore(64, __proof_forge_array_struct_pairs_1_left)
        mstore(96, __proof_forge_array_struct_pairs_1_right)
        log1(0, 128, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_matrix_event(a, b, c, d) {
      let __proof_forge_array_matrix_0_0 := a
      let __proof_forge_array_matrix_0_1 := b
      let __proof_forge_array_matrix_1_0 := c
      let __proof_forge_array_matrix_1_1 := d
      {
        mstore(0, 35000277193312430329116110807205321618552619317420529425454772113559294836736)
        let __pf_event_topic0 := keccak256(0, 25)
        mstore(0, __proof_forge_array_matrix_0_0)
        mstore(32, __proof_forge_array_matrix_0_1)
        mstore(64, __proof_forge_array_matrix_1_0)
        mstore(96, __proof_forge_array_matrix_1_1)
        log1(0, 128, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_pair_matrix_event(a, b, c, d, e, f, g, h) {
      let __proof_forge_array_struct_pairMatrix_0_0_left := a
      let __proof_forge_array_struct_pairMatrix_0_0_right := b
      let __proof_forge_array_struct_pairMatrix_0_1_left := c
      let __proof_forge_array_struct_pairMatrix_0_1_right := d
      let __proof_forge_array_struct_pairMatrix_1_0_left := e
      let __proof_forge_array_struct_pairMatrix_1_0_right := f
      let __proof_forge_array_struct_pairMatrix_1_1_left := g
      let __proof_forge_array_struct_pairMatrix_1_1_right := h
      {
        mstore(0, 36357139816894284481188916627620183122405574950649796438417604283857043204443)
        mstore(32, 22780588622913510007042461698051134993564019663524360774140824138400869122048)
        let __pf_event_topic0 := keccak256(0, 38)
        mstore(0, __proof_forge_array_struct_pairMatrix_0_0_left)
        mstore(32, __proof_forge_array_struct_pairMatrix_0_0_right)
        mstore(64, __proof_forge_array_struct_pairMatrix_0_1_left)
        mstore(96, __proof_forge_array_struct_pairMatrix_0_1_right)
        mstore(128, __proof_forge_array_struct_pairMatrix_1_0_left)
        mstore(160, __proof_forge_array_struct_pairMatrix_1_0_right)
        mstore(192, __proof_forge_array_struct_pairMatrix_1_1_left)
        mstore(224, __proof_forge_array_struct_pairMatrix_1_1_right)
        log1(0, 256, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_storage_pair_array_event(a, b, c, d) {
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 0, 0), a)
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 1, 0), b)
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 0, 1), c)
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 1, 1), d)
      {
        mstore(0, 37747689869461643464471119639573531748372218098125097347532376174202949760361)
        mstore(32, 49959741704248868804343004437864887347782938572387770617318600583713283637248)
        let __pf_event_topic0 := keccak256(0, 41)
        mstore(0, sload(__proof_forge_struct_array_slot(5, 2, 2, 0, 0)))
        mstore(32, sload(__proof_forge_struct_array_slot(5, 2, 2, 1, 0)))
        mstore(64, sload(__proof_forge_struct_array_slot(5, 2, 2, 0, 1)))
        mstore(96, sload(__proof_forge_struct_array_slot(5, 2, 2, 1, 1)))
        log1(0, 128, __pf_event_topic0)
      }
    }
    function f_EventProbe_emit_indexed_pair_event(left, right, value) {
      let __proof_forge_struct_pair_left := left
      let __proof_forge_struct_pair_right := right
      {
        mstore(0, 33213884033972546254760509534762344613534147965852086162890939770421711040116)
        mstore(32, 24517052842465079370413120945299090683665717048513947648744169312629567782912)
        let __pf_event_topic0 := keccak256(0, 35)
        mstore(0, __proof_forge_struct_pair_left)
        mstore(32, __proof_forge_struct_pair_right)
        let __pf_event_indexed_topic0 := keccak256(0, 64)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_storage_pair_event(left, right, value) {
      {
        let __proof_forge_assign_storage_struct_storedPair_left := left
        let __proof_forge_assign_storage_struct_storedPair_right := right
        sstore(1, __proof_forge_assign_storage_struct_storedPair_left)
        sstore(2, __proof_forge_assign_storage_struct_storedPair_right)
      }
      {
        mstore(0, 33213884033972546274058268154838342578559400571704103657156312403158764516406)
        mstore(32, 23593015698242013539937703465736163356655840090613832088544081947677448732672)
        let __pf_event_topic0 := keccak256(0, 42)
        mstore(0, sload(1))
        mstore(32, sload(2))
        let __pf_event_indexed_topic0 := keccak256(0, 64)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_storage_array_event(left, right, value) {
      sstore(__proof_forge_array_slot(3, 2, 0), left)
      sstore(__proof_forge_array_slot(3, 2, 1), right)
      {
        mstore(0, 33213884033972546274058268154838341277671788258747004883246941827730250691945)
        mstore(32, 49959741704211352643985955585122750572963649782145707744252798302872684986368)
        let __pf_event_topic0 := keccak256(0, 37)
        mstore(0, sload(__proof_forge_array_slot(3, 2, 0)))
        mstore(32, sload(__proof_forge_array_slot(3, 2, 1)))
        let __pf_event_indexed_topic0 := keccak256(0, 64)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_array_event(left, right, value) {
      let __proof_forge_array_values_0 := left
      let __proof_forge_array_values_1 := right
      {
        mstore(0, 33213884033972546161021678077745898947667239935089798860719422326732315230208)
        let __pf_event_topic0 := keccak256(0, 30)
        mstore(0, __proof_forge_array_values_0)
        mstore(32, __proof_forge_array_values_1)
        let __pf_event_indexed_topic0 := keccak256(0, 64)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_storage_pair_array_event(a, b, c, d, value) {
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 0, 0), a)
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 1, 0), b)
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 0, 1), c)
      sstore(__proof_forge_struct_array_slot(5, 2, 2, 1, 1), d)
      {
        mstore(0, 33213884033972546274058268154838342578559401084626289698610701350084179014700)
        mstore(32, 53106884551204179912034263980349372986157771400049621062947512377323015897088)
        let __pf_event_topic0 := keccak256(0, 50)
        mstore(0, sload(__proof_forge_struct_array_slot(5, 2, 2, 0, 0)))
        mstore(32, sload(__proof_forge_struct_array_slot(5, 2, 2, 1, 0)))
        mstore(64, sload(__proof_forge_struct_array_slot(5, 2, 2, 0, 1)))
        mstore(96, sload(__proof_forge_struct_array_slot(5, 2, 2, 1, 1)))
        let __pf_event_indexed_topic0 := keccak256(0, 128)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_pair_array_event(a, b, c, d, value) {
      let __proof_forge_array_struct_pairs_0_left := a
      let __proof_forge_array_struct_pairs_0_right := b
      let __proof_forge_array_struct_pairs_1_left := c
      let __proof_forge_array_struct_pairs_1_right := d
      {
        mstore(0, 33213884033972546254760509571722283268355815339268100639988835399448156058665)
        mstore(32, 41249454635328975548020660243773414201120874226841181152181438624278037659648)
        let __pf_event_topic0 := keccak256(0, 43)
        mstore(0, __proof_forge_array_struct_pairs_0_left)
        mstore(32, __proof_forge_array_struct_pairs_0_right)
        mstore(64, __proof_forge_array_struct_pairs_1_left)
        mstore(96, __proof_forge_array_struct_pairs_1_right)
        let __pf_event_indexed_topic0 := keccak256(0, 128)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_matrix_event(a, b, c, d, value) {
      let __proof_forge_array_matrix_0_0 := a
      let __proof_forge_array_matrix_0_1 := b
      let __proof_forge_array_matrix_1_0 := c
      let __proof_forge_array_matrix_1_1 := d
      {
        mstore(0, 33213884033972546235930258014739257195049576989145838570368665434596530091062)
        mstore(32, 23592708855985765952925771527420190941844392474980139947797807605860351868928)
        let __pf_event_topic0 := keccak256(0, 34)
        mstore(0, __proof_forge_array_matrix_0_0)
        mstore(32, __proof_forge_array_matrix_0_1)
        mstore(64, __proof_forge_array_matrix_1_0)
        mstore(96, __proof_forge_array_matrix_1_1)
        let __pf_event_indexed_topic0 := keccak256(0, 128)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function f_EventProbe_emit_indexed_pair_matrix_event(a, b, c, d, e, f, g, h, value) {
      let __proof_forge_array_struct_pairMatrix_0_0_left := a
      let __proof_forge_array_struct_pairMatrix_0_0_right := b
      let __proof_forge_array_struct_pairMatrix_0_1_left := c
      let __proof_forge_array_struct_pairMatrix_0_1_right := d
      let __proof_forge_array_struct_pairMatrix_1_0_left := e
      let __proof_forge_array_struct_pairMatrix_1_0_right := f
      let __proof_forge_array_struct_pairMatrix_1_1_left := g
      let __proof_forge_array_struct_pairMatrix_1_1_right := h
      {
        mstore(0, 33213884033972546254760509589163296150283721795102253188335509998120224437812)
        mstore(32, 18705957479005271543611984770555474135478397334981757198088483621979016921088)
        let __pf_event_topic0 := keccak256(0, 47)
        mstore(0, __proof_forge_array_struct_pairMatrix_0_0_left)
        mstore(32, __proof_forge_array_struct_pairMatrix_0_0_right)
        mstore(64, __proof_forge_array_struct_pairMatrix_0_1_left)
        mstore(96, __proof_forge_array_struct_pairMatrix_0_1_right)
        mstore(128, __proof_forge_array_struct_pairMatrix_1_0_left)
        mstore(160, __proof_forge_array_struct_pairMatrix_1_0_right)
        mstore(192, __proof_forge_array_struct_pairMatrix_1_1_left)
        mstore(224, __proof_forge_array_struct_pairMatrix_1_1_right)
        let __pf_event_indexed_topic0 := keccak256(0, 256)
        mstore(0, value)
        log2(0, 32, __pf_event_topic0, __pf_event_indexed_topic0)
      }
    }
    function __proof_forge_array_slot(slot, length, index) -> result {
      if iszero(lt(index, length)) {
        revert(0, 0)
      }
      result := add(slot, index)
    }
    function __proof_forge_struct_array_slot(slot, length, field_count, field_offset, index) -> result {
      if iszero(lt(index, length)) {
        revert(0, 0)
      }
      result := add(add(slot, mul(index, field_count)), field_offset)
    }
  }
}
