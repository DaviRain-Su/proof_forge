import ProofForgeV2

open ProofForgeV2.Language

program QualifiedFieldId where
  state value : Field Curves.bn254_fr

  view get() : UInt64 do
    return 0
