import ProofForgeV2

open ProofForgeV2.Language

program PriorityExtensionBeforeProof where
  requires extension near.promise version "1.0.0"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
  requires extension near.promise version "2.0.0"
    digest "sha256:abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789"
  invariant Holds : 1
  proof Holds using Pkg.First
  proof Holds using Pkg.Second

  entry ping() : UInt64 do
    return 0
