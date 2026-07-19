import ProofForgeV2.Language.Syntax

namespace Tests.Language.ProgramPayloadFixtures.Rich

open ProofForgeV2.Language

program RichPayload where
  requires extension near.promise version "1.0.0-alpha.1+build.7"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  state value : UInt64
  state private secret : Bool
  state commitment commitVal : Field bn254_fr
  state maybeCount : Option UInt64
  state blob : Bytes 8
  state batch : Array UInt64 2
  state owner : Principal
  state flag : Unit
  state width : UInt8
  state width16 : UInt16
  state width32 : UInt32
  state width128 : UInt128
  state width256 : UInt256
  state signed8 : Int8
  state signed16 : Int16
  state signed32 : Int32
  state signed64 : Int64
  state signed128 : Int128
  state signed256 : Int256
  struct Point where
    x : UInt64
    y : Field bn254_fr
    z : Option Bool
  enum Status where
    | Pending
    | Done(UInt64)
    | Pair(Bool, UInt8)
  const Zero : UInt64 := 0
  const One : UInt64 := Zero + 1
  event Tick()
  event Log(amount : UInt64)
  error Bad(code : UInt64)
  proof Holds using Bundle.Specs.Holds
  invariant Holds : 1
  init(start : UInt64) do
    value := start
    let tmp : UInt64 := 1
    assert true else Bad
    emit Tick()
    for i in 0 ..< start bounded 4 do
      assert true
    call "peer"
    return 0
  entry run(n : UInt64, bit : Bool) : UInt64 do
    if bit then
      value := n + 1 - 0 * 1
      emit Log(n)
      assert n else Bad
    else
      revert Bad(0)
    let s := "ok"
    return helper(n) + One
  view peek() : UInt64 do
    return value
  fn helper(x : UInt64) : UInt64 do
    let a := g(x)
    let b : UInt64 := A.B(x, 1)
    let c := batch[0]
    return a + b + c + ~x + -x + (x / 1) + (x % 1) + (x << 1) + (x >> 1)
      + (x & 1) + (x | 1) + (x ^ 1) + (x == 1) + (x != 0) + (x < 2)
      + (x <= 2) + (x > 0) + (x >= 0) + (!bit) + (true && false) + (true || false)
  fn g(x : UInt64) : UInt64 do
    return x
  entry unitRun() : Unit do
    return

end Tests.Language.ProgramPayloadFixtures.Rich
