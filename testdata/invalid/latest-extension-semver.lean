import ProofForgeV2

open ProofForgeV2.Language

program LatestExtensionSemver where
  requires extension near.promise version "latest"
    digest "sha256:0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

  entry ping() : UInt64 do
    return 0
