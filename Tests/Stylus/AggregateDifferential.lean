import ProofForge.Backend.Stylus.AbiLayout

open ProofForge.Backend.Stylus

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def word (value : Nat) : Array UInt8 :=
  (List.range 32).toArray.map fun index => UInt8.ofNat ((value / (2 ^ (8 * (31 - index)))) % 256)

def main : IO Unit := do
  let empty := word 32 ++ word 0
  let emptySlice <- match decodeDynamicArgument empty 1 0 64 with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (emptySlice.dataOffset == 64 && emptySlice.length == 0 && emptySlice.paddedEnd == 64)
    "empty dynamic ABI slice changed"

  let hello := word 32 ++ word 5 ++ "hello".toUTF8.data ++ Array.replicate 27 0
  let helloSlice <- match decodeDynamicArgument hello 1 0 64 with
    | .ok value => pure value | .error error => throw <| IO.userError error.message
  require (helloSlice.dataOffset == 64 && helloSlice.length == 5 && helloSlice.paddedEnd == 96)
    "string tail layout changed"

  for (name, calldata, maximum) in #[
      ("unaligned", word 33 ++ word 0, 64),
      ("inside-head", word 0 ++ word 0, 64),
      ("missing-length", word 64, 64),
      ("truncated-tail", word 32 ++ word 33 ++ Array.replicate 32 0, 64),
      ("over-limit", word 32 ++ word 65 ++ Array.replicate 96 0, 64)] do
    match decodeDynamicArgument calldata 1 0 maximum with
    | .error _ => pure ()
    | .ok _ => throw <| IO.userError s!"{name} dynamic ABI vector was accepted"
  IO.println "stylus-aggregate-differential: ok"
