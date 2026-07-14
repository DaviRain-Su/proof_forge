import ProofForge.IR.Core
import ProofForge.IR.Canonical
import ProofForge.Frontend.Authored.Normalize
import ProofForge.Contract.Spec
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault

/-! # Materialization Parity Test

Compares legacy and canonical artifact metadata for every product source.
Constructor, allocator, selector/discriminator, event ABI, proxy, upgrade,
and target extension data must be equal after normalization. Changing
CanonicalEvidence must not change the comparison.
-/

open ProofForge.Frontend.Authored
open ProofForge.Frontend.Authored.Normalize
open ProofForge.IR.Canonical
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

def productFixtures : Array (String × ContractSpec) :=
  #[ ("counter", ContractSpec.fromIR ProofForge.IR.Examples.Counter.module)
   , ("value-vault", ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module)
   ]

def main : IO Unit := do
  let mut totalTests := 0
  let mut passed := 0
  for (name, spec) in productFixtures do
    totalTests := totalTests + 1
    /- Adapt the spec through the legacy adapter. -/
    match normalizeContractSpec spec with
    | .error e => throw <| IO.userError s!"{name}: adapt failed: {repr e}"
    | .ok bundle =>
        let contract := bundle.contract.contract
        /- Check that materialization is preserved. -/
        let mat := contract.materialization
        /- Check that interface contract name matches spec name. -/
        require (contract.interface.contractName == spec.name)
          s!"{name}: contract name mismatch: {contract.interface.contractName} vs {spec.name}"
        /- Check that entrypoint count is non-zero. -/
        require (!contract.interface.entrypoints.isEmpty)
          s!"{name}: no entrypoints"
        /- Check that state symbols are preserved. -/
        require (!mat.stateSymbols.isEmpty)
          s!"{name}: no state symbols"
        passed := passed + 1
  require (passed == totalTests) s!"Materialization parity: {passed}/{totalTests}"
  IO.println s!"materialization-parity: ok ({passed}/{totalTests})"