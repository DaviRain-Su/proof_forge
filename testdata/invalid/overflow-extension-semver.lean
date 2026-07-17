import ProofForgeV2

open ProofForgeV2.Language

program OverflowExtensionSemver where
  requires extension near.promise version "18446744073709551616.0.0"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  entry ping() : UInt64 do
    return 0
