/-
Evm.AbiEncode layout smoke: pad32, bytes, Call[], aggregate / aggregate3,
plus Wave δ Plan → Yul mstore/CALL packing.
-/
import ProofForge.Backend.Evm.AbiEncode
import ProofForge.Backend.Evm.ToYul.AbiEncode
import ProofForge.Backend.Evm.IR
import ProofForge.IR.Contract
import ProofForge.Protocols.Evm.Multicall

namespace ProofForge.Tests.AbiEncode

open ProofForge.Backend.Evm.AbiEncode
open ProofForge.Backend.Evm.ToYul.AbiEncode
open ProofForge.Protocols.Evm.Multicall

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw (IO.userError message)

def contains (haystack needle : String) : Bool :=
  haystack.contains needle

def packedSpec (selector : Nat) (plan : Plan) (outSize : Nat := 32)
    (dynLenOffset? : Option Nat := none) (patchOffsets : Array Nat := #[]) :
    ProofForge.Backend.Evm.Plan.AbiPackedHelperSpec := {
  selector
  stores := plan.stores.map fun store => (store.offset, wordNat store.value)
  argsSize := plan.size
  outSize
  dynLenOffset?
  dynTargetOffsets := patchOffsets
}

def main : IO UInt32 := do
  require (ProofForge.Backend.Evm.AbiEncode.catalogId == "evm.abi_encode") "catalog id"
  require (ProofForge.Backend.Evm.ToYul.AbiEncode.catalogId == "evm.yul.abi_encode")
    "yul pack catalog"
  require (pad32 0 == 0) "pad32 0"
  require (pad32 1 == 32) "pad32 1"
  require (pad32 32 == 32) "pad32 32"
  require (pad32 33 == 64) "pad32 33"

  -- Empty bytes: length 0 only → size 32
  let (bStores, bEnd) := encodeBytesAt 0 #[]
  require (bEnd == 32) "empty bytes size"
  require (planWordAt? { stores := bStores, size := bEnd } 0 == some 0)
    "empty bytes length word"

  -- Four bytes of data → length + one data word
  let (b2, e2) := encodeBytesAt 0 #[1, 2, 3, 4]
  require (e2 == 64) "4 bytes → 64 total"
  require (planWordAt? { stores := b2, size := e2 } 0 == some 4) "len=4"

  -- Empty aggregate: head 0x20, array len 0 at 0x20 → size 0x40
  let empty := encodeAggregate #[]
  require (planWordAt? empty 0 == some 0x20) "aggregate head offset"
  require (planWordAt? empty 0x20 == some 0) "empty array length"
  require (empty.size == 0x40) s!"empty aggregate size got {empty.size}"

  -- One Call: target=0xab, empty data
  let c1 := mkCall 0xab #[]
  let one := encodeAggregate #[c1]
  require (planWordAt? one 0 == some 0x20) "one head"
  require (planWordAt? one 0x20 == some 1) "one length"
  -- offset table at 0x40: first element offset relative to array base 0x20
  -- first tuple at 0x20+0x20 = 0x40 from region? arrayBase=0x20, offsets at 0x40,
  -- first offset value = (tupleStart - 0x20). tupleStart = 0x20+32+32 = 0x60
  -- offset word at 0x40 should be 0x40 (0x60-0x20)
  require (planWordAt? one 0x40 == some 0x40) s!"call offset got {planWordAt? one 0x40}"
  require (planWordAt? one 0x60 == some 0xab) "call target"
  require (planWordAt? one 0x80 == some 0x40) "bytes rel offset in Call"
  require (planWordAt? one 0xa0 == some 0) "empty bytes len"
  require (one.size >= 0xc0) s!"one call min size {one.size}"

  -- Call with selector-only data (transfer-like 4 bytes)
  let data := innerCallData 0xa9059cbb #[]
  require (data.size == 4) s!"selector-only data len {data.size}"
  require (data[0]! == 0xa9 && data[3]! == 0xbb) "selector bytes order"
  let c2 := mkCall 0x11 data
  let p2 := encodeAggregate #[c2]
  require (planWordAt? p2 0x20 == some 1) "p2 length"
  require (planWordAt? p2 0x60 == some 0x11) "p2 target"
  -- bytes length at call base+0x40
  let callBase := 0x60
  require (planWordAt? p2 (callBase + 0x40) == some 4) "inner data len 4"

  -- aggregate3 empty
  let a3 := encodeAggregate3 #[]
  require (planWordAt? a3 0 == some 0x20) "a3 head"
  require (planWordAt? a3 0x20 == some 0) "a3 empty len"

  -- Call3 with allowFailure
  let c3 := mkCall3 0xcd true #[]
  let p3 := encodeAggregate3 #[c3]
  require (planWordAt? p3 0x20 == some 1) "c3 len"
  require (planWordAt? p3 0x60 == some 0xcd) "c3 target"
  require (planWordAt? p3 0x80 == some 1) "c3 allowFailure true"

  -- Two calls
  let two := encodeAggregate #[mkCall 1 #[], mkCall 2 #[]]
  require (planWordAt? two 0x20 == some 2) "two length"
  require (planWordAt? two 0x40 == some 0x60) "first offset"  -- 0x20+0x40?
  -- offsetsBase = 0x40, n=2, tuplesStart = 0x40+64 = 0x80
  -- first offset = 0x80-0x20 = 0x60
  require (planWordAt? two 0x40 == some 0x60) "first elem offset"
  require ((planWordAt? two 0x60).isSome) "second offset present"

  -- Wave δ: Plan → Yul (selector + mstore args + call)
  let yulEmpty := renderAggregateCallYul defaultMemBase 0xdeadbeef 0 #[]
  require (contains yulEmpty "mstore") "empty aggregate yul has mstore"
  require (contains yulEmpty "shl") "selector via shl(224, …)"
  require (contains yulEmpty "252dba42" || contains yulEmpty "623753794")
    "aggregate selector 0x252dba42 present"
  require (contains yulEmpty "call(") "emit CALL"
  require (contains yulEmpty "_abi_ok") "success local"
  require (contains yulEmpty "revert") "require success reverts"
  -- memBase 0x80 = 128; args at 132
  require (contains yulEmpty "128" || contains yulEmpty "0x80") "memBase 0x80"
  -- head word 0x20 at args base
  require (contains yulEmpty "32") "plan head 0x20"

  let yulOne := renderAggregateCallYul 0x80 0xabc 32 #[mkCall 0xab #[]]
  require (contains yulOne "mstore") "one-call yul mstore"
  require (contains yulOne "171") "target 0xab = 171"
  require (callInSize one == 4 + one.size) "inSize = 4 + plan.size"

  let yul3 := renderAggregate3CallYul 0x80 1 0 #[mkCall3 0xcd true #[]]
  require (contains yul3 "82ad56cb" || contains yul3 "2192398027")
    "aggregate3 selector"
  require (contains yul3 "205") "Call3 target 0xcd = 205"

  -- Protocol facade
  let viaMc := ProofForge.Protocols.Evm.Multicall.renderAggregateCallYul 0x11 0 #[]
  require (contains viaMc "call(") "Multicall.renderAggregateCallYul"

  let dense := planDenseWords empty
  require (dense.size == 2) s!"empty dense words {dense.size}"
  require (dense[0]! == 0x20 && dense[1]! == 0) "dense empty aggregate"

  -- Full Yul object (compile-time Call[] materialize)
  let objYul := renderAggregateObjectYul "Agg" 0xcA11 0 #[mkCall 1 #[]]
  require (contains objYul "object") "Yul object wrapper"
  require (contains objYul "function main") "main entry"
  require (contains objYul "call(") "object issues CALL"
  require (contains objYul "return(") "object returns"

  -- ABI layout stays in the EVM plan; no target ABI node is routed through IR.
  let packedPlan := encodeAggregate #[mkCall 0xab #[0x11]]
  let packSpec := packedSpec selectorAggregate packedPlan
  let helperYul := renderStatements #[abiPackedHelperFunction packSpec]
  require (contains helperYul "__pf_abi_packed_") "abi packed helper name"
  require (contains helperYul "mstore") "helper mstores plan"
  require (contains helperYul "call(") "helper issues CALL"
  require (contains helperYul "171") "inner Call target 0xab"

  -- Runtime length plan: overwrite the Call[] length at args offset 0x20.
  let calls2 := #[mkCall 0xab #[0x11], mkCall 0xcd #[0x22]]
  let calls2Plan := encodeAggregate calls2
  let dynSpec := packedSpec selectorAggregate calls2Plan 32 (some 0x20)
  let dynYul := renderStatements #[abiPackedHelperFunction dynSpec]
  require (contains dynYul "_dyn32" || contains dynYul "dyn") "dyn helper name"
  require (contains dynYul "n") "runtime length param n"
  require (contains dynYul "call(") "dyn helper CALL"

  -- Runtime target patch locations are computed directly from the EVM ABI plan.
  let targetOffsets := aggregateCallTargetOffsets calls2
  require (targetOffsets.size == 2) "two runtime target patch offsets"
  let tgtSpec := packedSpec selectorAggregate calls2Plan 32 none targetOffsets
  let tgtYul := renderStatements #[abiPackedHelperFunction tgtSpec]
  require (contains tgtYul "tgts2" || contains tgtYul "t0") "dyn target params"
  require (contains tgtYul "t1") "second target param"
  require (contains tgtYul "call(") "dyn-targets helper CALL"

  -- Runtime ABI word patch locations use static selector/shape templates.
  let wordCalls : Array Call := #[
    mkCall 0 (callDataFromSelectorArgs 0xa9059cbb #[0, 0]),
    mkCall 0 (callDataFromSelectorArgs 0x23b872dd #[0, 0, 0])
  ]
  let wordPlan := encodeAggregate wordCalls
  let wordOffsets := aggregateCallTargetOffsets wordCalls ++ aggregateCallArgWordOffsets wordCalls
  require (wordOffsets.size == 7) s!"dynamic call patch offsets={wordOffsets.size}"
  let wordSpec := packedSpec selectorAggregate wordPlan 32 none wordOffsets
  let wordYul := renderStatements #[abiPackedHelperFunction wordSpec]
  require (contains wordYul "t0" && contains wordYul "t6") "dyn call params t0..t6"
  require (contains wordYul "call(") "dyn-calls helper CALL"

  IO.println s!"abi-encode: ok (layout + EVM plan/yul packed/dyn/tgts/words empty={empty.size} one={one.size} two={two.size})"
  pure 0

end ProofForge.Tests.AbiEncode

def main : IO UInt32 :=
  ProofForge.Tests.AbiEncode.main
