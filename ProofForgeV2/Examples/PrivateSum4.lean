import ProofForgeV2.Language.Syntax

namespace ProofForgeV2.Examples

open ProofForgeV2.Language

program PrivateSum4 where
  entry sum(private a : UInt64, private b : UInt64, private c : UInt64, private d : UInt64) : UInt64 do
    return a + b + c + d

end ProofForgeV2.Examples
