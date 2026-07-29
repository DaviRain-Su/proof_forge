import ProofForgeV2

open ProofForgeV2.Language

program DiagnosticMulti where
  state count : UInt64
  view get() : UInt64 do
    count := count + 1
    return true
