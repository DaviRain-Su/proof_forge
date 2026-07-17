import ProofForgeV2

open ProofForgeV2.Language

program QualifiedType where
  state value : Foo.Bar

  view get() : UInt64 do
    return 0
