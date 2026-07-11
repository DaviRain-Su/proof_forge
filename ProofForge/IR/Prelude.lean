namespace ProofForge.IR.Prelude

/-! This `Repr ByteArray` instance is intentionally local to the IR layer:
`ByteArray` lives in `Init` and no project-wide `Repr` instance exists, so
Core IR provides one here for its own `bytesLit` literal rather than emitting
a global orphan instance from `ProofForge.IR.Core`. -/
instance : Repr ByteArray where
  reprPrec ba _ := s!"ByteArray[{ba.size}]"

end ProofForge.IR.Prelude
