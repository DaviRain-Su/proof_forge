import ProofForge.IR.Legacy.Core
import ProofForge.Compiler.Yul.AST

namespace ProofForge.Backend.Evm.CorePlan

open ProofForge.IR.Legacy.Core
open Lean.Compiler.Yul

structure StorageSlotPlan where
  path : StoragePath
  slotExpr : Expr

structure ExprPlan where
  expr : Expr

structure StmtPlan where
  stmts : List Statement

-- Placeholder event plan; refine in Task 5.
structure EventPlan where
  name : String
  topicCount : Nat
  deriving Repr

structure EntrypointPlan where
  name : String
  selector : UInt32
  params : List (String × CoreType)
  body : List Statement

structure EvmCorePlan where
  moduleName : String
  stateSlots : List StorageSlotPlan
  entrypoints : List EntrypointPlan
  events : List EventPlan
  constructor : Option (List Statement)

def buildEvmCorePlan (m : CoreModule) : EvmCorePlan :=
  let stateSlots := m.state.zipIdx.map fun (_s, i) =>
    { path := StoragePath.scalar i, slotExpr := Expr.num i }
  let entrypoints := m.entrypoints.map fun e =>
    { name := e.name
    , selector := 0 -- TODO: compute selector from signature in Task 5
    , params := e.params
    , body := []    -- TODO: lower body in Task 5
    }
  { moduleName := m.name
  , stateSlots := stateSlots
  , entrypoints := entrypoints
  , events := []
  , constructor := .none
  }

end ProofForge.Backend.Evm.CorePlan
