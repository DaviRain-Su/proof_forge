import ProofForgeV2

open ProofForgeV2.Language

program ReservedLetBinder where
  entry run() : UInt64 do
    let const : UInt64 := 1
    return 0
