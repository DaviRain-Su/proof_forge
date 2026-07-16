import ProofForge.Compiler.CanonicalPipeline
import ProofForge.IR.Examples.Counter
import ProofForge.IR.Examples.ValueVault
import ProofForge.Contract.Spec

/-! # Canonical Product Matrix Shadow Test

Runs the same business sources as `just product` through
`compileForTest .canonical` and compares success/rejection class
with the legacy route.
-/

open ProofForge.Compiler
open ProofForge.Contract

def require (condition : Bool) (message : String) : IO Unit :=
  if condition then pure () else throw <| IO.userError message

/-- Product fixture names and their ContractSpec. -/
def productFixtures : Array (String × ContractSpec) :=
  #[ ("counter", ContractSpec.fromIR ProofForge.IR.Examples.Counter.module)
   , ("value-vault", ContractSpec.fromIR ProofForge.IR.Examples.ValueVault.module)
   ]

/-- Primary target IDs. -/
def primaryTargets : Array String :=
  #[ "evm", "solana-sbpf-asm", "wasm-near" ]

def main : IO Unit := do
  let mut totalTests := 0
  let mut passed := 0
  let mut failed := 0
  for (fixtureName, spec) in productFixtures do
    for targetId in primaryTargets do
      totalTests := totalTests + 1
      /- Run legacy mode. -/
      let legacyResult ← compileForTest .legacy targetId spec
      let legacyOk := legacyResult.isOk
      /- Run canonical mode. -/
      let canonicalResult ← compileForTest .canonical targetId spec
      let canonicalOk := canonicalResult.isOk
      /- Both must agree on success/rejection class. -/
      if legacyOk == canonicalOk then
        passed := passed + 1
      else
        failed := failed + 1
        IO.eprintln s!"MISMATCH: {fixtureName}/{targetId}: legacy={legacyOk} canonical={canonicalOk}"
  require (failed == 0)
    s!"Product matrix: {passed}/{totalTests} passed, {failed} mismatches"
  IO.println s!"canonical-product-matrix: ok ({passed}/{totalTests})"