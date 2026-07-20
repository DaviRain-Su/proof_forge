namespace ProofForgeV2.Source.DecodeBudgetV1

/-- Caller-threaded session residual for node-bearing constructions.
    Not a user/profile authority object; complete Program root creates it once. -/
structure DecodeBudgetV1 where
  remainingNodes : Nat
  deriving DecidableEq, Repr

end ProofForgeV2.Source.DecodeBudgetV1
