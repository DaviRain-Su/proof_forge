import ProofForgeV2
namespace Examples
open ProofForgeV2.Language
program MapMini where
  state m : Map UInt64 UInt64
  init() do
    m := Map.empty()
  entry put(k : UInt64, v : UInt64) : UInt64 do
    m[k] := v
    return v
  view get(k : UInt64) : UInt64 do
    match m[k] with
    | Option.some(v) => do
      return v
    | _ => do
      return 0
end Examples
