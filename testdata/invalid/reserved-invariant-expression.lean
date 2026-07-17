import ProofForgeV2

open ProofForgeV2.Language

program ReservedInvariantExpression where
  invariant Holds : invariant

  entry ping() : UInt64 do
    return 0
