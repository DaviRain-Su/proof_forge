import ProofForgeV2

open ProofForgeV2.Language

program UppercaseExtensionDigest where
  requires extension near.promise version "1.0.0"
    digest "sha256:AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"

  entry ping() : UInt64 do
    return 0
