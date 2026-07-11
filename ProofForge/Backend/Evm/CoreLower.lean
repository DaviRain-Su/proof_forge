import ProofForge.IR.Legacy.Core
import ProofForge.Backend.Evm.CorePlan
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.CoreLower

open ProofForge.Backend.Evm.CorePlan
open Lean.Compiler.Yul

/-- Lower a single EVM core entrypoint plan to a Yul function-definition
statement.  Adapts the brief's `Yul.FunctionDefinition` shape to the actual
`Lean.Compiler.Yul` AST, where functions are represented by
`Statement.funcDef`. -/
def lowerEntrypoint (ep : EntrypointPlan) : Statement :=
  let params := ep.params.map (fun (n, _) => ({ name := n } : TypedName)) |>.toArray
  let body := ep.body.toArray
  Statement.funcDef ep.name params #[] { statements := body }

/-- Lower an `EvmCorePlan` to a top-level Yul object.  The object's `code`
block contains one function definition per entrypoint. -/
def lowerEvmCorePlan (p : EvmCorePlan) : Object :=
  { name := p.moduleName
  , code := { statements := p.entrypoints.map lowerEntrypoint |>.toArray }
  , subObjects := #[]
  , dataSections := #[]
  }

end ProofForge.Backend.Evm.CoreLower
