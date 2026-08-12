import ProofForgeV2
namespace Examples
open ProofForgeV2.Language

-- Dense Map return (B-RET-MAP): view dumps occ/key/val × capacity as a JSON
-- array of u64 decimals (24 leaves at cap-8). Engineering runtime only.
program MapDump where
  state m : Map UInt64 UInt64
  init() do
    m := Map.empty()
  entry put(k : UInt64, v : UInt64) : UInt64 do
    m[k] := v
    return v
  view dump() : Map UInt64 UInt64 do
    return m
end Examples
