import ProofForgeV2

open ProofForgeV2.Language

program PriorityExtensionIdBeforeVersionDigest where
  requires extension Near.promise version "v1.0.0"
    digest "bad"

  entry ping() : UInt64 do
    return 0
