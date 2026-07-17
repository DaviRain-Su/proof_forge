import ProofForgeV2

open ProofForgeV2.Language

program PriorityInvariantBeforeExtension where
  invariant Holds : 1
  invariant Holds : 2
  requires extension near.promise version "1.0.0"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  requires extension near.promise version "2.0.0"
    digest "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"

  entry ping() : UInt64 do
    return 0
