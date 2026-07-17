import ProofForgeV2

open ProofForgeV2.Language

program WrongLengthExtensionDigest where
  requires extension near.promise version "1.0.0"
    digest "sha256:00"

  entry ping() : UInt64 do
    return 0
