import ProofForgeV2

namespace Examples

open ProofForgeV2.Language

-- APP-1 / Phase-1 DoD privacy vector: four private params summed into a public
-- return. Product path must fail closed with PF-VIS-001 (private→public).
-- Use only -- line comments here; module-doc openers before program break the
-- product Loader (parse fails before disclosure).
program PrivateSum4 where
  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do
    return a + b + c + d

end Examples
