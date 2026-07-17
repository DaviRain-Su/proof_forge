import ProofForgeV2

open ProofForgeV2.Language

program VPrefixExtensionSemver where
  requires extension near.promise version "v1.0.0"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  entry ping() : UInt64 do
    return 0
