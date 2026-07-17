import ProofForgeV2

open ProofForgeV2.Language

program BareExtensionDigest where
  requires extension near.promise version "1.0.0"
    digest "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  entry ping() : UInt64 do
    return 0
