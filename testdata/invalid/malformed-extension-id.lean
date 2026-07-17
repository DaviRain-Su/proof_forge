import ProofForgeV2

open ProofForgeV2.Language

program MalformedExtensionId where
  requires extension near.promise_bad version "1.0.0"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  entry ping() : UInt64 do
    return 0
